defmodule GuildfordVue.CandidatesManagementTest do
  @moduledoc """
  Sprint 2 Slice 4 — admin-facing candidate listing + lifecycle.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, AuditLog, Candidates}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "candmgmt-ops@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Ops"
      })

    {:ok, alice} =
      Candidates.register_candidate(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alice",
        "last_name" => "Worthington"
      })

    {:ok, bob} =
      Candidates.register_candidate(%{
        "email" => "bob@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Bob",
        "last_name" => "Mason"
      })

    %{admin: admin, alice: alice, bob: bob}
  end

  describe "list_candidates/1" do
    test "returns every candidate when no filters", %{alice: a, bob: b} do
      ids = Candidates.list_candidates() |> Enum.map(& &1.id)
      assert a.id in ids
      assert b.id in ids
    end

    test "supports a search query against email and name", %{alice: a, bob: b} do
      [hit] = Candidates.list_candidates(search: "alice")
      assert hit.id == a.id

      [hit] = Candidates.list_candidates(search: "mason")
      assert hit.id == b.id
    end

    test "search is case-insensitive", %{alice: a} do
      [hit] = Candidates.list_candidates(search: "WORTH")
      assert hit.id == a.id
    end

    test "search returns [] for no matches" do
      assert Candidates.list_candidates(search: "no-such-person") == []
    end

    test "supports a status filter — only_active / only_suspended", %{alice: a, bob: b} do
      {:ok, _} = Candidates.suspend(b)

      active_ids = Candidates.list_candidates(status: :active) |> Enum.map(& &1.id)
      assert a.id in active_ids
      refute b.id in active_ids

      suspended_ids = Candidates.list_candidates(status: :suspended) |> Enum.map(& &1.id)
      assert b.id in suspended_ids
      refute a.id in suspended_ids
    end

    test "respects :limit", %{alice: _, bob: _} do
      assert length(Candidates.list_candidates(limit: 1)) == 1
    end
  end

  describe "suspend/2 + reactivate/2 (admin actor → audit log)" do
    test "suspend/2 writes a candidate_suspended audit event",
         %{admin: admin, alice: a} do
      {:ok, suspended} = Candidates.suspend(a, admin)
      assert suspended.suspended_at

      [event] = AuditLog.list(event_type: "candidate_suspended", aggregate_id: a.id)
      assert event.actor_id == admin.id
      assert event.actor_type == "admin"
      assert event.payload["candidate_email"] == a.email
    end

    test "reactivate/2 writes a candidate_reactivated audit event",
         %{admin: admin, alice: a} do
      {:ok, suspended} = Candidates.suspend(a, admin)
      {:ok, reactivated} = Candidates.reactivate(suspended, admin)
      refute reactivated.suspended_at

      [event] = AuditLog.list(event_type: "candidate_reactivated", aggregate_id: a.id)
      assert event.actor_id == admin.id
    end

    test "a suspended candidate cannot log in",
         %{admin: admin, alice: a} do
      {:ok, _} = Candidates.suspend(a, admin)

      refute Candidates.get_candidate_by_email_and_password(
               a.email,
               "supersecret123!A"
             )
    end
  end
end
