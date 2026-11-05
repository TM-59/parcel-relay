defmodule ParcelRelay.Courier do
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, 0)
  def init(state), do: {:ok, state}
  def handle_call(:dispatch, _, 0), do: {:reply, :ok, 3}
  def handle_call(:dispatch, _, state), do: {:reply, :busy, state}
  def handle_call(:tick, _, state), do: {:reply, state == 1, max(0, state - 1)}
  def handle_call(:position, _, state), do: {:reply, state, state}
end

defmodule ParcelRelay do
  @moduledoc "Two real courier processes advance together; no background clock."
  def start do
    children = for id <- 1..2, do: Supervisor.child_spec({ParcelRelay.Courier, []}, id: id)
    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    workers = Supervisor.which_children(supervisor) |> Enum.sort() |> Enum.map(&elem(&1, 1))
    %{supervisor: supervisor, workers: workers, ticks: 0, delivered: 0}
  end

  def status(%{delivered: n}) when n >= 4, do: :won
  def status(%{ticks: n}) when n >= 10, do: :lost
  def status(_), do: :playing

  def act(game, command) do
    if status(game) == :playing, do: apply_command(game, command), else: game
  end

  defp apply_command(game, command) when command in ["1", "2"] do
    GenServer.call(Enum.at(game.workers, String.to_integer(command) - 1), :dispatch)
    game
  end

  defp apply_command(game, "t") do
    deliveries =
      game.workers
      |> Task.async_stream(&GenServer.call(&1, :tick), max_concurrency: 2, ordered: false)
      |> Enum.count(&(&1 == {:ok, true}))

    %{game | ticks: game.ticks + 1, delivered: game.delivered + deliveries}
  end

  defp apply_command(game, _), do: game

  def screen(game) do
    lanes =
      for {worker, id} <- Enum.with_index(game.workers, 1) do
        remaining = GenServer.call(worker, :position)

        "  Courier #{id}: " <>
          if(remaining == 0, do: "READY", else: "in transit (#{remaining} ticks)")
      end

    Enum.join(
      [
        "PARCEL RELAY | #{String.upcase(to_string(status(game)))}",
        "Deliver 4 parcels before tick 10 | tick #{game.ticks}/10 | delivered #{game.delivered}/4",
        "",
        Enum.join(lanes, "\n"),
        "",
        "1 / 2: dispatch to a READY courier | t: advance BOTH | q: quit"
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
