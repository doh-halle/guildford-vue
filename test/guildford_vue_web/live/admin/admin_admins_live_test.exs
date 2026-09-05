defmodule GuildfordVueWeb.Admin.AdminAdminsLiveTest do
  @moduledoc """
  Sprint 2 Slice 5 — admin user management LiveView. Tests:
    - operator visits → redirected to dashboard (not authorised)
    - superadmin sees the list + invite form
    - submit invite → creates admin + audit + email
    - change role → audited
    - suspend / reactivate → audited
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog}

  setup %{conn: conn} do
    {:ok, super_admin} =
      Admins.register_admin(%{
        "email" => "adlive-boss@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Boss",
        "role" => "superadmin"
      })

    {:ok, operator} =
      Admins.register_admin(%{
        "email" => "adlive-op@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Op",
        "role" => "operator"
      })

    %{conn: conn, super_admin: super_admin, operator: operator}
  end

  defp sign_in_as(conn, admin) do
    token = Admins.generate_session_token(admin)
    init_test_session(conn, %{admin_token: token})
  end

  test "operator gets redirected (not authorised)", %{conn: conn, operator: op} do
    conn = sign_in_as(conn, op)
    {:error, {:live_redirect, %{to: redirect}}} = live(conn, ~p"/backoffice/admins")
    assert redirect =~ "/backoffice/dashboard"
  end

  test "superadmin sees both admins listed", %{conn: conn, super_admin: sa, operator: op} do
    conn = sign_in_as(conn, sa)
    {:ok, _lv, html} = live(conn, ~p"/backoffice/admins")

    assert html =~ sa.email
    assert html =~ op.email
    assert html =~ "Invite admin"
  end

  test "invite form creates a new admin + audits + emails",
       %{conn: conn, super_admin: sa} do
    conn = sign_in_as(conn, sa)
    {:ok, lv, _} = live(conn, ~p"/backoffice/admins")

    lv
    |> form("#invite-admin-form",
      invite: %{
        "email" => "newhire@guildfordvue.test",
        "name" => "New Hire",
        "role" => "operator"
      }
    )
    |> render_submit()

    new_admin = Admins.get_admin_by_email("newhire@guildfordvue.test")
    assert new_admin
    assert new_admin.role == "operator"

    assert [_] = AuditLog.list(event_type: "admin_invited", aggregate_id: new_admin.id)
    import Swoosh.TestAssertions
    assert_email_sent(to: [{"New Hire", "newhire@guildfordvue.test"}])
  end

  test "change role updates + audits", %{conn: conn, super_admin: sa, operator: op} do
    conn = sign_in_as(conn, sa)
    {:ok, lv, _} = live(conn, ~p"/backoffice/admins")

    lv
    |> form("#role-form-#{op.id}", role: %{"role" => "superadmin"})
    |> render_submit()

    assert Admins.get_admin!(op.id).role == "superadmin"
    assert [_] = AuditLog.list(event_type: "admin_role_changed", aggregate_id: op.id)
  end

  test "suspend + reactivate flow", %{conn: conn, super_admin: sa, operator: op} do
    conn = sign_in_as(conn, sa)
    {:ok, lv, _} = live(conn, ~p"/backoffice/admins")

    lv
    |> element("[data-test-id='suspend-admin-#{op.id}']")
    |> render_click()

    assert Admins.get_admin!(op.id).suspended_at
    assert [_] = AuditLog.list(event_type: "admin_suspended", aggregate_id: op.id)

    lv
    |> element("[data-test-id='reactivate-admin-#{op.id}']")
    |> render_click()

    refute Admins.get_admin!(op.id).suspended_at
    assert [_] = AuditLog.list(event_type: "admin_reactivated", aggregate_id: op.id)
  end
end
