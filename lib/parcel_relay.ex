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
  def start do
    children = for id <- 1..2, do: Supervisor.child_spec({ParcelRelay.Courier, []}, id: id)
    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    %{supervisor: supervisor, workers: [1, 2], ticks: 0, delivered: 0, lost: 0, notice: ""}
  end

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
    %{game | notice: "Courier #{id}: #{reply} (#{route})"}
  end

  defp apply_command(game, "t") do
    tick = game.ticks + 1

    outcomes =
      game.workers
      |> Task.async_stream(fn id -> advance(game, id, tick) end, max_concurrency: 2)
      |> Enum.map(fn {:ok, outcome} -> outcome end)

    lost = Enum.count(outcomes, &(&1 == :lost))

    %{
      game
      | ticks: tick,
        delivered: game.delivered + Enum.count(outcomes, &(&1 == :delivered)),
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

    case GenServer.call(pid, :position) do
      {left, :short} when left > 0 and tick in [4, 8] ->
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)
        receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
        await_restart(game, id, pid, 1000)
        :lost

      _ ->
        if GenServer.call(pid, :tick), do: :delivered, else: :moving
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

  def screen(game) do
    lanes =
      for id <- game.workers do
        {remaining, route} = GenServer.call(worker(game, id), :position)

        "  Courier #{id}: " <>
          if(remaining == 0, do: "READY", else: "#{route} (#{remaining} ticks)")
      end

    Enum.join(
      [
        "PARCEL RELAY | #{String.upcase(to_string(status(game)))}",
        "Deliver 4 parcels by tick 10 | tick #{game.ticks}/10 | delivered #{game.delivered}/4 | lost #{game.lost}",
        "Safe: 3 ticks | Short: 2 ticks, bridge CLOSED at ticks 4 and 8",
        Enum.join(lanes, "\n"),
        game.notice,
        "1 / 2: SAFE dispatch | 1s / 2s: SHORT dispatch | t: advance BOTH | q: quit"
      ],
      "\n"
    )
  end

  def main do
    game = start()

    try do
      loop(game)
    after
      Supervisor.stop(game.supervisor)
    end
  end

  defp loop(game) do
    IO.puts("\e[2J\e[H" <> screen(game))

    if status(game) == :playing do
      case IO.gets("> ") do
        nil ->
          :ok

        line ->
          command = String.trim(line)
          if command != "q", do: loop(act(game, command))
      end
    end
  end
end
