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
