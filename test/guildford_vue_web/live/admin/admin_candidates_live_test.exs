defmodule GuildfordVueWeb.Admin.AdminCandidatesLiveTest do
  @moduledoc """
  Sprint 2 Slice 4 — admin candidate management LiveView. Tests:
    - the index lists every candidate
    - the search input filters the list (phx-change)
    - clicking Suspend marks a candidate suspended and writes audit
    - clicking Reactivate clears it
    - the status filter buttons (Active / Suspended / All) work
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog, Candidates}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "acmgmt-ops@guildfordvue.test",
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

    token = Admins.generate_session_token(admin)
    conn = init_test_session(conn, %{admin_token: token})
    %{conn: conn, admin: admin, alice: alice, bob: bob}
  end

  test "lists every candidate", %{conn: conn, alice: a, bob: b} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/candidates")
    assert html =~ a.email
    assert html =~ b.email
    assert html =~ a.first_name
    assert html =~ b.first_name
  end

  test "search input narrows the list", %{conn: conn, alice: a, bob: b} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/candidates")

    html =
      lv
      |> form("#candidate-search", search: %{"q" => "alice"})
      |> render_change()

    assert html =~ a.email
    refute html =~ b.email
  end

  test "Suspend button suspends + writes audit", %{conn: conn, alice: a, admin: admin} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/candidates")

    lv
    |> element("[data-test-id='suspend-#{a.id}']")
    |> render_click()

    reloaded = Candidates.get_candidate!(a.id)
    assert reloaded.suspended_at

    [event] = AuditLog.list(event_type: "candidate_suspended", aggregate_id: a.id)
    assert event.actor_id == admin.id
  end

  test "Reactivate button reactivates a suspended candidate",
       %{conn: conn, alice: a, admin: admin} do
    {:ok, _} = Candidates.suspend(a, admin)

    # Filter on suspended so Alice appears (default filter is :active)
    {:ok, lv, _} = live(conn, ~p"/backoffice/candidates?status=suspended")

    lv
    |> element("[data-test-id='reactivate-#{a.id}']")
    |> render_click()

    refute Candidates.get_candidate!(a.id).suspended_at
    assert [_] = AuditLog.list(event_type: "candidate_reactivated", aggregate_id: a.id)
  end

  test "status filter restricts the list", %{conn: conn, alice: a, bob: b, admin: admin} do
    {:ok, _} = Candidates.suspend(b, admin)

    {:ok, _lv, html} = live(conn, ~p"/backoffice/candidates?status=active")
    assert html =~ a.email
    refute html =~ b.email

    {:ok, _lv, html} = live(conn, ~p"/backoffice/candidates?status=suspended")
    assert html =~ b.email
    refute html =~ a.email
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/backoffice/candidates")
    assert redirect =~ "/backoffice/login"
  end
end
