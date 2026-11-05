defmodule ParcelRelayTest do
  use ExUnit.Case

  setup do
    game = ParcelRelay.start()
    Process.unlink(game.supervisor)
    on_exit(fn -> if Process.alive?(game.supervisor), do: Supervisor.stop(game.supervisor) end)
    %{game: game}
  end

  test "REQ-dispatch both couriers really advance on the same tick", %{game: game} do
    game = Enum.reduce(["1", "2", "t", "t", "t"], game, &ParcelRelay.act(&2, &1))
    assert game.delivered == 2
    assert game.ticks == 3
    assert length(Enum.uniq(game.workers)) == 2
  end

  test "REQ-dispatch busy courier cannot lose its current parcel", %{game: game} do
    game = Enum.reduce(["1", "t", "1", "t", "t"], game, &ParcelRelay.act(&2, &1))
    assert game.delivered == 1
  end

  test "REQ-finish four deliveries win and finished games freeze", %{game: game} do
    game =
      Enum.reduce(
        List.duplicate(["1", "2", "t", "t", "t"], 2) |> List.flatten(),
        game,
        &ParcelRelay.act(&2, &1)
      )

    assert ParcelRelay.status(game) == :won
    assert ParcelRelay.act(game, "t") == game
  end

  test "REQ-finish last tick still permits a delivery", %{game: game} do
    game = Enum.reduce(1..10, game, fn _, g -> ParcelRelay.act(g, "t") end)
    assert ParcelRelay.status(game) == :lost
    assert ParcelRelay.status(%{game | delivered: 4}) == :won
  end

  test "REQ-input invalid commands preserve time", %{game: game} do
    assert ParcelRelay.act(game, "99") == game
    assert ParcelRelay.screen(game) =~ "READY"
  end
end

defmodule ParcelRelayRoutesTest do
  use ExUnit.Case

  setup do
    game = ParcelRelay.start()
    Process.unlink(game.supervisor)
    on_exit(fn -> if Process.alive?(game.supervisor), do: Supervisor.stop(game.supervisor) end)
    %{game: game}
  end

  defp play(game, commands), do: Enum.reduce(commands, game, &ParcelRelay.act(&2, &1))

  test "REQ-route shortcut saves one tick before the outage", %{game: game} do
    game = play(game, ["1s", "2", "t", "t"])
    assert game.delivered == 1
    assert GenServer.call(ParcelRelay.worker(game, 2), :position) == {1, :safe}
    assert game.lost == 0
  end

  test "REQ-recovery outage restarts both actual processes without reviving parcels", %{
    game: game
  } do
    game = play(game, ["t", "t", "1s", "2s", "t"])
    old = Enum.map(1..2, &ParcelRelay.worker(game, &1))
    game = ParcelRelay.act(game, "t")
    assert game.lost == 2
    assert game.delivered == 0
    assert Enum.all?(old, &(not Process.alive?(&1)))
    new = Enum.map(1..2, &ParcelRelay.worker(game, &1))
    assert Enum.all?(new, &Process.alive?/1)
    assert ParcelRelay.screen(game) =~ "restarted READY"
    game = play(game, ["t", "1", "2", "t", "t", "t"])
    assert game.delivered == 2
    assert game.lost == 2
    Supervisor.stop(game.supervisor)
    assert Enum.all?(new, &(not Process.alive?(&1)))
  end

  test "REQ-route safe parcels survive the bridge closure; busy dispatch preserves route", %{
    game: game
  } do
    game = play(game, ["t", "t", "1", "1s", "2", "t", "t", "t"])
    assert game.delivered == 2
    assert game.lost == 0
  end

  test "REQ-finish route choices and tick ten have deterministic results", %{game: game} do
    game = play(game, ["1s", "2s", "t", "t", "1", "2", "t", "t", "t"])
    assert ParcelRelay.status(game) == :won
    assert game.ticks == 5
  end
end
