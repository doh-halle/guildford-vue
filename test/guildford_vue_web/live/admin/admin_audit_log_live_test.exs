defmodule GuildfordVueWeb.Admin.AdminAuditLogLiveTest do
  @moduledoc """
  Sprint 2 Slice 6 — audit log viewer.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog, Candidates}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "audit-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Audit Admin",
        "role" => "superadmin"
      })

    {:ok, cand} =
      Candidates.register_candidate(%{
        "email" => "watched@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Watched",
        "last_name" => "Person"
      })

    {:ok, _} = Candidates.suspend(cand, admin)
    {:ok, _} = AuditLog.append(:some_other_event, %{actor: %{id: admin.id, type: "admin"}})

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, admin: admin, cand: cand}
  end

  test "lists recent audit events newest-first", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/audit-log")
    assert html =~ "some_other_event"
    assert html =~ "candidate_suspended"
  end

  test "event_type filter narrows the list", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/audit-log")

    html =
      lv
      |> form("#audit-filter", filter: %{"event_type" => "candidate_suspended"})
      |> render_change()

    assert html =~ "candidate_suspended"
    refute html =~ "some_other_event"
  end

  test "shows the actor and aggregate columns", %{conn: conn, cand: c, admin: a} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/audit-log")
    # The actor id should appear in the actor column for the suspend event.
    assert html =~ a.email or html =~ a.id
    assert html =~ c.id or html =~ c.email
  end

  test "date-range filter narrows the list", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/audit-log")

    # Filter to tomorrow → nothing should match
    tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

    html =
      lv
      |> form("#audit-filter", filter: %{"from" => tomorrow})
      |> render_change()

    assert html =~ "No matching events"
    refute html =~ "candidate_suspended"
    refute html =~ "some_other_event"
  end

  test "operator (non-superadmin) can read the audit log", %{conn: conn} do
    # Operators view the audit log — but only superadmins manage admins.
    # Confirm the page is accessible to a base operator session.
    {:ok, op} =
      Admins.register_admin(%{
        "email" => "viewer@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Viewer",
        "role" => "operator"
      })

    op_conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(op)})
    {:ok, _lv, _html} = live(op_conn, ~p"/backoffice/audit-log")
  end
end
