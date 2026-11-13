defmodule ParcelRelayResultsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  defp play(game, commands), do: Enum.reduce(commands, game, &ParcelRelay.act(&2, &1))

  setup do
    game = ParcelRelay.start()
    Process.unlink(game.supervisor)
    on_exit(fn -> if Process.alive?(game.supervisor), do: ParcelRelay.stop(game) end)
    %{game: game}
  end

  test "REQ-result records each bridge failure once and preserves it after delivery", %{
    game: game
  } do
    game = play(game, ["t", "t", "1s", "1s", "2s", "t", "t"])
    assert length(game.parcels) == 2
    game = play(game, ["t", "t", "1s", "2s", "t", "t", "1s", "2s", "t", "t"])

    assert ParcelRelay.result(game) == %{
             delivered: 2,
             late: 0,
             lost: 4,
             shortfall: 2,
             failures: [
               "#1 C1: LOST tick 4: SHORT bridge closed (sent 2).",
               "#2 C2: LOST tick 4: SHORT bridge closed (sent 2).",
               "#3 C1: LOST tick 8: SHORT bridge closed (sent 6).",
               "#4 C2: LOST tick 8: SHORT bridge closed (sent 6)."
             ]
           }

    assert ParcelRelay.act(game, "t") == game
    screen = ParcelRelay.screen(game)
    assert screen =~ "delivered 2 | late 0 | lost 4"
    assert screen =~ "Goal shortfall: 2"
    assert screen =~ "r: retry same seed | n: next seed | q: quit"
    assert length(String.split(screen, "\n")) <= 24
    assert Enum.all?(String.split(screen, "\n"), &(String.length(&1) <= 80))
  end

  test "REQ-result late means dispatched but still travelling at the deadline", %{game: game} do
    game = play(game, List.duplicate("t", 8) ++ ["1", "2s", "t", "t"])

    assert ParcelRelay.result(game) == %{
             delivered: 1,
             late: 1,
             lost: 0,
             shortfall: 3,
             failures: ["#1 C1: LATE tick 10: safe needs 1 tick(s) (sent 8)."]
           }
  end

  test "REQ-result no dispatch is a shortfall without invented lost or late parcels", %{
    game: game
  } do
    game = play(game, List.duplicate("t", 10))

    assert ParcelRelay.result(game) == %{
             delivered: 0,
             late: 0,
             lost: 0,
             shortfall: 4,
             failures: []
           }
  end

  test "REQ-result delivery on tick ten counts toward the victory", %{game: game} do
    game =
      play(game, ["1", "2", "t", "t", "t"] ++ List.duplicate("t", 4) ++ ["1", "2", "t", "t", "t"])

    assert ParcelRelay.status(game) == :won

    assert ParcelRelay.result(game) == %{
             delivered: 4,
             late: 0,
             lost: 0,
             shortfall: 0,
             failures: []
           }
  end

  test "REQ-seed three closure schedules are reproducible and safe routes always win" do
    for seed <- 0..8 do
      game = ParcelRelay.start(seed)

      try do
        assert game.closures == Enum.at([[5, 9], [3, 7], [4, 8]], rem(seed, 3))
        assert ParcelRelay.screen(game) =~ "seed #{seed}"
        game = play(game, List.flatten(List.duplicate(["1", "2", "t", "t", "t"], 2)))
        assert ParcelRelay.status(game) == :won
        assert game.lost == 0
      after
        ParcelRelay.stop(game)
      end
    end
  end

  test "REQ-session retry resets all state, next changes seed, quit removes every process" do
    # Trace only the CLI session's descendants, including supervisors, couriers and tick tasks.
    parent = self()
    tracer = spawn(fn -> collect(parent, []) end)
    lose = "t\nt\n1s\n2s\nt\nt\nt\nt\n1s\n2s\nt\nt\nt\nt\n"

    output =
      capture_io(lose <> "r\n" <> lose <> "n\nq\n", fn ->
        :erlang.trace(self(), true, [:procs, :set_on_spawn, {:tracer, tracer}])

        try do
          assert ParcelRelay.main() == :ok
        after
          :erlang.trace(self(), false, [:all])
        end
      end)

    ref = :erlang.trace_delivered(:all)
    assert_receive {:trace_delivered, :all, ^ref}
    send(tracer, :collect)
    assert_receive {:spawned, pids}
    assert length(pids) >= 3 * 3
    assert Enum.all?(pids, &(not Process.alive?(&1)))
    screens = String.split(output, "\e[2J\e[H", trim: true)
    starts = Enum.filter(screens, &String.contains?(&1, "tick 0/10"))
    assert length(starts) == 3
    assert Enum.at(starts, 0) == Enum.at(starts, 1)
    assert List.last(starts) =~ "seed 60"
    assert List.last(starts) =~ "bridge CLOSED 5 and 9"
    assert List.last(starts) =~ "delivered 0/4 | lost 0"
    assert List.last(starts) =~ "Courier 1: READY"
    assert List.last(starts) =~ "Courier 2: READY"
    results = Enum.filter(screens, &String.contains?(&1, "PARCEL RELAY | LOST"))
    assert length(results) == 2
    assert Enum.at(results, 0) == Enum.at(results, 1)
  end

  test "REQ-seed the selected closure kills only the shortcut parcel" do
    for seed <- 59..61 do
      game = ParcelRelay.start(seed)

      try do
        [closure | _] = game.closures
        game = play(game, List.duplicate("t", closure - 1) ++ ["1s", "2", "t"])
        assert game.lost == 1

        assert [%{courier: 1, outcome: :lost, tick: ^closure}, %{courier: 2, outcome: :moving}] =
                 game.parcels

        assert GenServer.call(ParcelRelay.worker(game, 1), :position) == {0, :safe}
        assert GenServer.call(ParcelRelay.worker(game, 2), :position) == {2, :safe}
      after
        ParcelRelay.stop(game)
      end
    end
  end

  test "REQ-session retry and next are ignored while playing" do
    output = capture_io("1\nr\nn\nq\n", fn -> ParcelRelay.main() end)
    assert length(Regex.scan(~r/seed 59/, output)) == 4
    assert length(Regex.scan(~r/Courier 1: safe \(3 ticks\)/, output)) == 3
    refute output =~ "seed 60"
  end

  test "REQ-session invalid result input costs nothing and EOF quits", %{game: _game} do
    output = capture_io(String.duplicate("t\n", 10) <> "1\nt\nx\n", fn -> ParcelRelay.main() end)
    assert length(Regex.scan(~r/RESULT: delivered 0 \| late 0 \| lost 0/, output)) == 4
  end

  defp collect(parent, pids) do
    receive do
      {:trace, _, :spawn, pid, _} -> collect(parent, [pid | pids])
      :collect -> send(parent, {:spawned, Enum.uniq(pids)})
      _ -> collect(parent, pids)
    end
  end
end
