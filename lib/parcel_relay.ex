defmodule ParcelRelay.Courier do
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, {0, :safe})
  def init(state), do: {:ok, state}

  def handle_call({:dispatch, route}, _, {0, _}) do
    {:reply, :ok, {if(route == :short, do: 2, else: 3), route}}
  end

  def handle_call({:dispatch, _}, _, state), do: {:reply, :busy, state}
  def handle_call(:tick, _, {left, route}), do: {:reply, left == 1, {max(0, left - 1), route}}
  def handle_call(:position, _, state), do: {:reply, state, state}
end

defmodule ParcelRelay do
  @moduledoc "Two supervised couriers; short routes trade time for scheduled bridge outages."
  @closure_ticks [4, 8]
  def start(seed \\ 59) when is_integer(seed) and seed >= 0 do
    children = for id <- 1..2, do: Supervisor.child_spec({ParcelRelay.Courier, []}, id: id)

    {:ok, supervisor} =
      Supervisor.start_link(children,
        strategy: :one_for_one,
        max_restarts: length(children) * length(@closure_ticks)
      )

    %{
      supervisor: supervisor,
      workers: [1, 2],
      seed: seed,
      closures: Enum.map(@closure_ticks, &(&1 + rem(seed + 2, 3) - 1)),
      ticks: 0,
      delivered: 0,
      lost: 0,
      parcels: [],
      notice: ""
    }
  end

  def stop(game), do: Supervisor.stop(game.supervisor)

  def worker(game, id) do
    Enum.find_value(Supervisor.which_children(game.supervisor), fn
      {^id, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end)
  end

  def status(%{delivered: n}) when n >= 4, do: :won
  def status(%{ticks: n}) when n >= 10, do: :lost
  def status(_), do: :playing

  def act(game, command) do
    if status(game) == :playing, do: apply_command(game, command), else: game
  end

  defp apply_command(game, command) when command in ["1", "2", "1s", "2s"] do
    id = command |> String.first() |> String.to_integer()
    route = if String.ends_with?(command, "s"), do: :short, else: :safe
    reply = GenServer.call(worker(game, id), {:dispatch, route})

    parcel = %{
      id: length(game.parcels) + 1,
      courier: id,
      route: route,
      sent: game.ticks,
      outcome: :moving,
      tick: nil
    }

    parcels = if reply == :ok, do: game.parcels ++ [parcel], else: game.parcels
    %{game | parcels: parcels, notice: "Courier #{id}: #{reply} (#{route})"}
  end

  defp apply_command(game, "t") do
    tick = game.ticks + 1

    outcomes =
      game.workers
      |> Task.async_stream(fn id -> advance(game, id, tick) end, max_concurrency: 2)
      |> Enum.map(fn {:ok, outcome} -> outcome end)

    lost = Enum.count(outcomes, fn {_, outcome} -> outcome == :lost end)

    parcels =
      Enum.map(game.parcels, fn parcel ->
        {_, outcome} = List.keyfind(outcomes, parcel.courier, 0)

        if parcel.outcome == :moving and outcome in [:lost, :delivered],
          do: %{parcel | outcome: outcome, tick: tick},
          else: parcel
      end)

    %{
      game
      | ticks: tick,
        parcels: parcels,
        delivered: game.delivered + Enum.count(outcomes, fn {_, o} -> o == :delivered end),
        lost: game.lost + lost,
        notice:
          if(lost > 0,
            do: "Bridge closed: #{lost} parcel(s) lost; courier restarted READY.",
            else: "Both couriers advanced."
          )
    }
  end

  defp apply_command(game, _), do: game

  defp advance(game, id, tick) do
    pid = worker(game, id)

    {left, route} = GenServer.call(pid, :position)

    if left > 0 and route == :short and tick in game.closures do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
      await_restart(game, id, pid, 1000)
      {id, :lost}
    else
      {id, if(GenServer.call(pid, :tick), do: :delivered, else: :moving)}
    end
  end

  defp await_restart(_, _, _, 0), do: raise("Courier restart timed out")

  defp await_restart(game, id, old, remaining) do
    case worker(game, id) do
      pid when is_pid(pid) and pid != old ->
        :ok

      _ ->
        Process.sleep(1)
        await_restart(game, id, old, remaining - 1)
    end
  end

  def result(game) do
    late =
      if status(game) == :lost, do: Enum.count(game.parcels, &(&1.outcome == :moving)), else: 0

    failures =
      for parcel <- game.parcels,
          parcel.outcome == :lost or (status(game) == :lost and parcel.outcome == :moving) do
        if parcel.outcome == :lost do
          "##{parcel.id} C#{parcel.courier}: LOST tick #{parcel.tick}: SHORT bridge closed (sent #{parcel.sent})."
        else
          duration = if parcel.route == :short, do: 2, else: 3
          left = parcel.sent + duration - game.ticks

          "##{parcel.id} C#{parcel.courier}: LATE tick #{game.ticks}: #{parcel.route} needs #{left} tick(s) (sent #{parcel.sent})."
        end
      end

    %{
      delivered: game.delivered,
      lost: game.lost,
      late: late,
      shortfall: max(0, 4 - game.delivered),
      failures: failures
    }
  end

  def screen(game) do
    lanes =
      for id <- game.workers do
        {remaining, route} = GenServer.call(worker(game, id), :position)

        "  Courier #{id}: " <>
          if(remaining == 0, do: "READY", else: "#{route} (#{remaining} ticks)")
      end

    Enum.join(
      [
        "PARCEL RELAY | #{String.upcase(to_string(status(game)))} | seed #{game.seed}",
        "Goal: 4 by tick 10 | tick #{game.ticks}/10 | delivered #{game.delivered}/4 | lost #{game.lost}",
        "Safe: 3 ticks | Short: 2 ticks; bridge CLOSED #{Enum.join(game.closures, " and ")}",
        Enum.join(lanes, "\n"),
        game.notice,
        if(status(game) == :playing,
          do: "1 / 2: SAFE | 1s / 2s: SHORT | t: advance BOTH | q: quit",
          else: result_screen(game)
        )
      ],
      "\n"
    )
  end

  defp result_screen(game) do
    r = result(game)

    Enum.join(
      [
        "RESULT: delivered #{r.delivered} | late #{r.late} | lost #{r.lost}",
        "Goal shortfall: #{r.shortfall} (4 minus delivered; late = on road at tick 10)"
      ] ++
        r.failures ++
        [
          "r: retry same seed | n: next seed | q: quit"
        ],
      "\n"
    )
  end

  def main(seed \\ 59), do: session(seed)

  defp session(seed) do
    game = start(seed)

    next =
      try do
        loop(game)
      after
        stop(game)
      end

    case next do
      :retry -> session(seed)
      :next -> session(seed + 1)
      :quit -> :ok
    end
  end

  defp loop(game) do
    IO.puts("\e[2J\e[H" <> screen(game))

    case IO.gets("> ") do
      eof when eof in [nil, :eof] ->
        :quit

      line ->
        case {String.trim(line), status(game)} do
          {"q", _} -> :quit
          {"r", state} when state != :playing -> :retry
          {"n", state} when state != :playing -> :next
          {command, _} -> loop(act(game, command))
        end
    end
  end
end
