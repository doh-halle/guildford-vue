defmodule GuildfordVue.Centres.PubSubTest do
  @moduledoc """
  Sprint 6 Slice 1 — PubSub topic conventions for per-centre
  broadcasts. Topic = "centre:<centre_id>". Helpers wrap subscribe +
  broadcast so the call sites don't repeat the topic-string format.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Centres.PubSub, as: CentrePubSub

  test "topic/1 returns 'centre:<id>'" do
    id = Ecto.UUID.generate()
    assert CentrePubSub.topic(id) == "centre:" <> id
  end

  test "subscribe/1 + broadcast/2 round-trip" do
    id = Ecto.UUID.generate()
    :ok = CentrePubSub.subscribe(id)

    :ok = CentrePubSub.broadcast(id, {:slot_changed, %{a: 1}})

    assert_receive {:slot_changed, %{a: 1}}, 500
  end

  test "broadcast/2 only delivers to that centre's subscribers" do
    id_a = Ecto.UUID.generate()
    id_b = Ecto.UUID.generate()

    :ok = CentrePubSub.subscribe(id_a)
    :ok = CentrePubSub.broadcast(id_b, {:slot_changed, %{centre: :b}})

    refute_receive {:slot_changed, _}, 100
  end

  test "unsubscribe/1 stops further deliveries" do
    id = Ecto.UUID.generate()
    :ok = CentrePubSub.subscribe(id)
    :ok = CentrePubSub.unsubscribe(id)
    :ok = CentrePubSub.broadcast(id, {:slot_changed, %{}})

    refute_receive {:slot_changed, _}, 100
  end
end
