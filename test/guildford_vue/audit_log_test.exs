defmodule GuildfordVue.AuditLogTest do
  @moduledoc """
  Tests for the append-only audit log (PRD §4.4 FR-ADMIN-5 + §7.1).

  The audit log records every administrative action and every booking-
  pipeline event so the admin "audit log viewer" surface (Sprint 10)
  has structured history to render. The public API is intentionally
  write-only at the context level — there is no public `update` or
  `delete` function. Storage uses `inserted_at` only (no updated_at).
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.AuditLog
  alias GuildfordVue.AuditLog.Event

  describe "append/1 and append/3" do
    test "append/1 inserts an event with no actor and no payload" do
      assert {:ok, %Event{} = ev} = AuditLog.append(:system_started)
      assert ev.event_type == "system_started"
      assert ev.payload == %{}
      assert ev.actor_id == nil
      assert ev.actor_type == nil
      assert ev.aggregate_id == nil
      assert ev.inserted_at
    end

    test "append/3 records actor + payload + aggregate_id" do
      aggregate = Ecto.UUID.generate()

      assert {:ok, ev} =
               AuditLog.append(:centre_approved, %{
                 aggregate_id: aggregate,
                 actor: %{id: Ecto.UUID.generate(), type: "admin"},
                 payload: %{centre_name: "Manchester Hub", region: "north-west"}
               })

      assert ev.event_type == "centre_approved"
      assert ev.aggregate_id == aggregate
      assert ev.actor_type == "admin"
      assert ev.payload == %{"centre_name" => "Manchester Hub", "region" => "north-west"}
    end

    test "event_type is coerced to a string" do
      assert {:ok, ev} = AuditLog.append(:candidate_suspended)
      assert is_binary(ev.event_type)
    end

    test "payload accepts arbitrary jsonb-serialisable data" do
      complex = %{
        nested: %{deep: ["a", "b", "c"]},
        count: 42,
        flag: true
      }

      assert {:ok, ev} = AuditLog.append(:bulk_import, %{payload: complex})
      # JSONB round-trip: atoms become strings
      assert ev.payload["nested"]["deep"] == ["a", "b", "c"]
      assert ev.payload["count"] == 42
      assert ev.payload["flag"] == true
    end
  end

  describe "list/1" do
    setup do
      admin_id = Ecto.UUID.generate()

      events =
        for i <- 1..5 do
          # Stagger inserts by a microsecond so list order is deterministic.
          Process.sleep(1)

          {:ok, ev} =
            AuditLog.append(:centre_approved, %{
              aggregate_id: Ecto.UUID.generate(),
              actor: %{id: admin_id, type: "admin"},
              payload: %{n: i}
            })

          ev
        end

      %{events: events, admin_id: admin_id}
    end

    test "returns events newest-first by default", %{events: events} do
      [latest | _] = AuditLog.list()
      assert latest.id == List.last(events).id
    end

    test "honours :limit", %{events: _events} do
      assert length(AuditLog.list(limit: 3)) == 3
    end

    test "honours :event_type filter" do
      {:ok, _} = AuditLog.append(:candidate_suspended)
      {:ok, _} = AuditLog.append(:candidate_reactivated)

      suspensions = AuditLog.list(event_type: "candidate_suspended")
      assert length(suspensions) == 1
      assert hd(suspensions).event_type == "candidate_suspended"
    end

    test "honours :actor_id filter", %{admin_id: admin_id, events: events} do
      filtered = AuditLog.list(actor_id: admin_id)
      assert length(filtered) == length(events)
    end

    test "honours :aggregate_id filter", %{events: [first | _]} do
      filtered = AuditLog.list(aggregate_id: first.aggregate_id)
      assert length(filtered) == 1
      assert hd(filtered).id == first.id
    end

    test "honours :from filter (inclusive lower bound on inserted_at)" do
      {:ok, e1} = AuditLog.append(:dr_old)
      from_time = DateTime.utc_now()
      :timer.sleep(20)
      {:ok, e2} = AuditLog.append(:dr_new)

      ids = AuditLog.list(from: from_time) |> Enum.map(& &1.id)
      assert e2.id in ids
      refute e1.id in ids
    end

    test "honours :to filter (inclusive upper bound on inserted_at)" do
      {:ok, e1} = AuditLog.append(:dr_first)
      :timer.sleep(20)
      to_time = DateTime.utc_now()
      :timer.sleep(20)
      {:ok, e2} = AuditLog.append(:dr_after)

      ids = AuditLog.list(to: to_time) |> Enum.map(& &1.id)
      assert e1.id in ids
      refute e2.id in ids
    end

    test "honours :from + :to as a closed range" do
      {:ok, _before} = AuditLog.append(:rng_before)
      :timer.sleep(20)
      from_time = DateTime.utc_now()
      :timer.sleep(20)
      {:ok, inside} = AuditLog.append(:rng_inside)
      :timer.sleep(20)
      to_time = DateTime.utc_now()
      :timer.sleep(20)
      {:ok, _after} = AuditLog.append(:rng_after)

      ids = AuditLog.list(from: from_time, to: to_time) |> Enum.map(& &1.id)
      assert ids == [inside.id]
    end
  end

  describe "write-only contract" do
    test "the public AuditLog module exports no update / delete function" do
      exported = AuditLog.__info__(:functions) |> Keyword.keys() |> Enum.map(&Atom.to_string/1)

      refute Enum.any?(exported, &String.contains?(&1, "update"))
      refute Enum.any?(exported, &String.contains?(&1, "delete"))
    end
  end
end
