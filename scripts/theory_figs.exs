# Regenerates the drawn figures and the measured-values table of docs/theory.
# Run with `make theory-figs`. Every number is produced by playing the real game
# (supervised courier processes); nothing here changes it. No packages are needed.
defmodule TheoryFigs do
  @dir List.first(System.argv()) || "docs/theory/figures"
  @green "#2ca02c"
  @red "#d62728"
  @blue "#1f77b4"
  @grey "#999999"

  def dir, do: @dir

  def row(id, what, measured, theory) do
    error = if theory != 0, do: abs(measured / theory - 1), else: abs(measured - theory)

    "| `#{id}` | #{what} | #{fmt(measured)} | #{fmt(theory)} | #{:io_lib.format("~.2e", [error * 1.0])} |"
  end

  defp fmt(x) when is_integer(x), do: Integer.to_string(x)
  defp fmt(x), do: :io_lib.format("~.4g", [x * 1.0]) |> to_string()

  def svg(name, width, height, body) do
    head =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}" font-family="sans-serif" font-size="12">)

    text =
      Enum.join(
        [head, ~s(<rect width="#{width}" height="#{height}" fill="#ffffff"/>) | body] ++
          ["</svg>"],
        "\n"
      )

    File.write!(Path.join(@dir, name), text <> "\n")
  end

  def title(text),
    do: ~s(<text x="16" y="26" font-size="16" font-weight="bold" fill="#222">#{text}</text>)

  # ---- playing the real game -------------------------------------------------
  def with_game(fun) do
    game = ParcelRelay.start()

    try do
      fun.(game)
    after
      Supervisor.stop(game.supervisor)
    end
  end

  def play(game, commands), do: Enum.reduce(commands, game, &ParcelRelay.act(&2, &1))

  @doc "Courier 1 is dispatched on `route` after `wait` ticks; returns {tick delivered | :lost, game}."
  def single(route, wait) do
    with_game(fn game ->
      game = play(game, List.duplicate("t", wait) ++ [if(route == :short, do: "1s", else: "1")])

      Enum.reduce_while(1..4, game, fn _, g ->
        g = ParcelRelay.act(g, "t")

        cond do
          g.lost > 0 -> {:halt, {:lost, g.ticks}}
          g.delivered > 0 -> {:halt, {:delivered, g.ticks}}
          g.ticks >= 10 -> {:halt, {:none, g.ticks}}
          true -> {:cont, g}
        end
      end)
    end)
  end

  @doc "Both couriers follow the same list of routes, each dispatched as soon as the courier is READY."
  def plan(routes) do
    with_game(fn game ->
      {game, _} =
        Enum.reduce_while(1..10, {game, {routes, routes}}, fn _, {g, {r1, r2}} ->
          {g, r1} = dispatch(g, 1, r1)
          {g, r2} = dispatch(g, 2, r2)
          g = ParcelRelay.act(g, "t")

          if ParcelRelay.status(g) == :playing,
            do: {:cont, {g, {r1, r2}}},
            else: {:halt, {g, {r1, r2}}}
        end)

      %{
        status: ParcelRelay.status(game),
        ticks: game.ticks,
        delivered: game.delivered,
        lost: game.lost
      }
    end)
  end

  defp dispatch(game, _id, []), do: {game, []}

  defp dispatch(game, id, [route | rest] = routes) do
    case GenServer.call(ParcelRelay.worker(game, id), :position) do
      {0, _} -> {ParcelRelay.act(game, "#{id}#{if route == :short, do: "s", else: ""}"), rest}
      _ -> {game, routes}
    end
  end

  def sequences(0), do: [[]]
  def sequences(n), do: for(head <- [:safe, :short], tail <- sequences(n - 1), do: [head | tail])

  # ---- figures -----------------------------------------------------------------
  def routes_figure(safe, short) do
    left = 130
    step = 60

    lane = fn y, label, ticks, colour ->
      [
        ~s(<text x="16" y="#{y + 18}" fill="#222">#{label}</text>),
        ~s(<rect x="#{left}" y="#{y}" width="#{ticks * step}" height="26" fill="#{colour}" opacity="0.85"/>),
        ~s(<text x="#{left + ticks * step + 8}" y="#{y + 18}" fill="#222">delivered on tick #{ticks}</text>)
      ]
    end

    ticks =
      for t <- 0..4 do
        [
          ~s(<line x1="#{left + t * step}" y1="50" x2="#{left + t * step}" y2="150" stroke="#cccccc"/>),
          ~s(<text x="#{left + t * step}" y="168" text-anchor="middle" fill="#444">#{t}</text>)
        ]
      end

    body =
      [
        title("One parcel dispatched at tick 0: the two routes"),
        ticks,
        lane.(62, "SAFE route", safe, @blue),
        lane.(104, "SHORT route", short, @green),
        ~s(<text x="#{left}" y="188" fill="#444">ticks advanced with t</text>)
      ]

    svg("routes.svg", 560, 200, List.flatten(body))
  end

  def closures_figure(grid) do
    cell = 58
    left = 110
    top = 70

    cells =
      for {route, y} <- [{:safe, 0}, {:short, 1}], wait <- 0..8 do
        {outcome, tick} = Map.fetch!(grid, {route, wait})
        colour = %{delivered: @green, lost: @red, none: @grey}[outcome]
        x = left + wait * cell
        yy = top + y * cell

        [
          ~s(<rect x="#{x}" y="#{yy}" width="#{cell - 4}" height="#{cell - 4}" fill="#{colour}" opacity="0.85"/>),
          ~s(<text x="#{x + 27}" y="#{yy + 24}" text-anchor="middle" fill="#fff">#{%{delivered: "tick", lost: "lost", none: "late"}[outcome]}</text>),
          ~s(<text x="#{x + 27}" y="#{yy + 42}" text-anchor="middle" fill="#fff">#{tick}</text>)
        ]
      end

    heads =
      for wait <- 0..8 do
        ~s(<text x="#{left + wait * cell + 27}" y="#{top - 8}" text-anchor="middle" fill="#444">#{wait}</text>)
      end

    body = [
      title("Dispatch tick against route: delivered on tick n, lost to a closure, or too late"),
      ~s(<text x="#{left}" y="46" fill="#444">ticks already passed when the courier is dispatched →</text>),
      heads,
      ~s(<text x="16" y="#{top + 32}" fill="#222">SAFE</text>),
      ~s(<text x="16" y="#{top + cell + 32}" fill="#222">SHORT</text>),
      cells
    ]

    svg("closures.svg", 680, 200, List.flatten(body))
  end

  def plans_figure(rows) do
    left = 190
    top = 50
    step = 34

    bars =
      for {{label, result}, i} <- Enum.with_index(rows) do
        y = top + i * step
        won = result.status == :won
        colour = if won, do: @green, else: @red

        [
          ~s(<text x="16" y="#{y + 18}" fill="#222">#{label}</text>),
          ~s(<rect x="#{left}" y="#{y}" width="#{result.ticks * 36}" height="24" fill="#{colour}" opacity="0.85"/>),
          ~s(<text x="#{left + result.ticks * 36 + 8}" y="#{y + 17}" fill="#222">#{if won, do: "won on tick #{result.ticks}", else: "lost: #{result.delivered} of 4 by tick #{result.ticks}"}, parcels lost #{result.lost}</text>)
        ]
      end

    body = [
      title("Both couriers follow the same list of routes: the tick on which the game ends"),
      bars
    ]

    svg("plans.svg", 820, top + length(rows) * step + 16, List.flatten(body))
  end

  def colours, do: {@green, @red, @blue, @grey}

  def run do
    File.mkdir_p!(@dir)

    # S01 / S02: a courier, and the two routes
    {:delivered, safe} = single(:safe, 0)
    {:delivered, short} = single(:short, 0)
    routes_figure(safe, short)

    busy =
      with_game(fn game ->
        game = play(game, ["1", "t", "1s"])
        {game.notice, GenServer.call(ParcelRelay.worker(game, 1), :position)}
      end)

    # S03: both couriers advance on one tick
    both =
      with_game(fn game ->
        game = play(game, ["1", "2", "t"])
        for id <- 1..2, do: GenServer.call(ParcelRelay.worker(game, id), :position) |> elem(0)
      end)

    # S04: the closure grid
    grid =
      for route <- [:safe, :short],
          wait <- 0..8,
          into: %{},
          do: {{route, wait}, single(route, wait)}

    closures_figure(grid)
    lost_waits = for wait <- 0..8, match?({:lost, _}, grid[{:short, wait}]), do: wait
    safe_lost = Enum.count(0..8, &match?({:lost, _}, grid[{:safe, &1}]))

    # S05: supervision
    {pids_differ, alive, ready, restarts} =
      with_game(fn game ->
        before = for id <- 1..2, do: ParcelRelay.worker(game, id)
        game = play(game, ["t", "t", "1s", "2s", "t", "t"])
        now = for id <- 1..2, do: ParcelRelay.worker(game, id)
        ready = for pid <- now, do: GenServer.call(pid, :position) |> elem(0)
        alive_now = Enum.count(now, &Process.alive?/1)
        game2 = play(game, ["t", "t", "1s", "2s", "t", "t"])

        {Enum.count(Enum.zip(before, now), fn {a, b} -> a != b end), alive_now,
         Enum.count(ready, &(&1 == 0)), {game2.lost, Process.alive?(game2.supervisor)}}
      end)

    # S06: the end of a game
    frozen =
      with_game(fn game ->
        won = play(game, ["1", "2", "t", "t", "t", "1", "2", "t", "t", "t"])
        after_more = play(won, ["1", "t", "t"])
        {ParcelRelay.status(won), won.ticks, after_more.ticks, after_more.delivered}
      end)

    idle =
      with_game(fn game ->
        play(game, List.duplicate("t", 12)) |> then(&{ParcelRelay.status(&1), &1.ticks})
      end)

    invalid =
      with_game(fn game ->
        play(game, ["x", "", "3", "1x", "T"]) |> then(&{&1.ticks, &1.delivered})
      end)

    # S07: every list of up to four routes per courier, played through the real game
    results = for routes <- sequences(4), do: {routes, plan(routes)}
    winners = Enum.filter(results, fn {_, r} -> r.status == :won end)
    best = winners |> Enum.map(fn {_, r} -> r.ticks end) |> Enum.min()
    best_plans = for {routes, r} <- winners, r.ticks == best, do: routes
    label = fn routes -> routes |> Enum.map(&Atom.to_string/1) |> Enum.join(", ") end

    shown =
      [
        [:safe, :safe, :safe, :safe],
        [:short, :safe, :safe, :safe],
        [:short, :short, :safe, :safe],
        [:short, :short, :short, :short],
        [:safe, :short, :short, :short]
      ]
      |> Enum.map(fn routes -> {label.(routes), plan(routes)} end)

    plans_figure(shown)
    all_safe = plan([:safe, :safe, :safe, :safe])
    all_short = plan([:short, :short, :short, :short])

    rows = [
      row("route-safe", "ticks for a SAFE parcel dispatched at tick 0 (theory 3)", safe, 3),
      row("route-short", "ticks for a SHORT parcel dispatched at tick 0 (theory 2)", short, 2),
      row(
        "busy-refused",
        "a second dispatch to a courier already on the road is answered busy (1 = yes)",
        if(String.contains?(elem(busy, 0), "busy"), do: 1, else: 0),
        1
      ),
      row(
        "busy-keeps-route",
        "ticks left on the first parcel after that refused dispatch (theory 2: SAFE, one tick gone)",
        elem(elem(busy, 1), 0),
        2
      ),
      row(
        "tick-both",
        "couriers that moved on one t after both were dispatched SAFE (theory 2)",
        Enum.count(both, &(&1 == 2)),
        2
      ),
      row(
        "closure-short-lost",
        "of nine dispatch ticks 0..8, SHORT parcels lost to a closure (theory 4: dispatched after 2, 3, 6 or 7 ticks)",
        length(lost_waits),
        4
      ),
      row(
        "closure-first-lost",
        "earliest dispatch tick whose SHORT parcel is lost (theory 2)",
        List.first(lost_waits),
        2
      ),
      row(
        "closure-safe-lost",
        "of nine dispatch ticks, SAFE parcels lost (theory 0)",
        safe_lost,
        0
      ),
      row(
        "restart-new-pids",
        "couriers whose process identifier changed after a closure killed both (theory 2)",
        pids_differ,
        2
      ),
      row("restart-alive", "courier processes alive after that closure (theory 2)", alive, 2),
      row("restart-ready", "of those, READY with no parcel (theory 2)", ready, 2),
      row(
        "restart-four",
        "parcels lost when both closures kill both couriers in one game (theory 4)",
        elem(restarts, 0),
        4
      ),
      row(
        "restart-supervisor",
        "the supervisor is still alive after those four restarts (1 = yes)",
        if(elem(restarts, 1), do: 1, else: 0),
        1
      ),
      row(
        "win-safe-tick",
        "tick on which two SAFE rounds by both couriers win (theory 6)",
        elem(frozen, 1),
        6
      ),
      row(
        "frozen-ticks",
        "tick counter after three more commands on that won game (theory 6: unchanged)",
        elem(frozen, 2),
        6
      ),
      row("frozen-delivered", "deliveries after those commands (theory 4)", elem(frozen, 3), 4),
      row(
        "idle-lost-tick",
        "tick on which a game with no dispatch is lost; further t does nothing (theory 10)",
        elem(idle, 1),
        10
      ),
      row("invalid-ticks", "ticks used by five invalid commands (theory 0)", elem(invalid, 0), 0),
      row(
        "plans-tried",
        "route lists tried: four routes, SAFE or SHORT each (theory 16)",
        length(results),
        16
      ),
      row(
        "plans-won",
        "of those, lists that win by tick 10 (reported)",
        length(winners),
        length(winners)
      ),
      row("plans-best-tick", "earliest winning tick over all sixteen (reported)", best, best),
      row(
        "plans-best-count",
        "lists that reach it (reported)",
        length(best_plans),
        length(best_plans)
      ),
      row(
        "plans-all-safe",
        "winning tick of SAFE, SAFE, SAFE, SAFE (theory 6)",
        all_safe.ticks,
        6
      ),
      row(
        "plans-all-short-lost",
        "parcels lost by SHORT, SHORT, SHORT, SHORT (reported)",
        all_short.lost,
        all_short.lost
      ),
      row(
        "plans-all-short-tick",
        "tick on which SHORT, SHORT, SHORT, SHORT ends (reported)",
        all_short.ticks,
        all_short.ticks
      )
    ]

    IO.puts("best plans: " <> Enum.map_join(best_plans, " | ", label))

    File.write!(
      Path.join(@dir, "values.md"),
      Enum.join(
        [
          "# Measured values",
          "",
          "Written by `make theory-figs` (scripts/theory_figs.exs) by playing the real game with its supervised processes. Do not edit by hand.",
          "The last column is the relative error; where the theory column is 0 it is the absolute value.",
          "",
          "| id | what is measured | measured | theory | error |",
          "|---|---|---|---|---|" | rows
        ],
        "\n"
      ) <> "\n"
    )
  end
end

TheoryFigs.run()
