defmodule GuildfordVueWeb.Admin.AdminAuthSettingsLiveTest do
  @moduledoc """
  Sprint 11.5 Slice 8 — /backoffice/auth-settings (MFA toggle).
  Superadmin-only; audit-logged; hostile-client-resistant.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog}

  setup %{conn: conn} do
    {:ok, super_admin} =
      Admins.register_admin(%{
        "email" => "auth-s-super-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Super",
        "role" => "superadmin"
      })

    {:ok, operator} =
      Admins.register_admin(%{
        "email" => "auth-s-op-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Op",
        "role" => "operator"
      })

    previous = Application.get_env(:guildford_vue, :mfa_via_email_enabled)
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, false)
    on_exit(fn -> Application.put_env(:guildford_vue, :mfa_via_email_enabled, previous) end)

    super_conn =
      init_test_session(conn, %{admin_token: Admins.generate_session_token(super_admin)})

    op_conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(operator)})

    %{super_conn: super_conn, op_conn: op_conn, super: super_admin, operator: operator}
  end

  test "superadmin sees current MFA state", %{super_conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/auth-settings")

    assert html =~ "Email-OTP MFA"
    assert html =~ "Currently"
    assert html =~ "OFF"
  end

  test "non-superadmin operator is bounced to /backoffice/dashboard",
       %{op_conn: conn} do
    result = live(conn, ~p"/backoffice/auth-settings")
    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ "/backoffice/dashboard"
  end

  test "Apply ON flips the env flag and audit-logs", %{super_conn: conn, super: actor} do
    {:ok, lv, _html} = live(conn, ~p"/backoffice/auth-settings")

    html =
      lv
      |> form("#mfa-toggle-form", mfa: %{"enabled" => "true"})
      |> render_submit()

    assert html =~ "ON"
    assert Application.get_env(:guildford_vue, :mfa_via_email_enabled) == true

    [event | _] = AuditLog.list(event_type: "mfa_email_otp_toggled", limit: 5)
    assert event.actor_id == actor.id
    assert event.payload["new"] == true
    assert event.payload["old"] == false
  end

  test "Apply OFF flips it back", %{super_conn: conn} do
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, true)

    {:ok, lv, _html} = live(conn, ~p"/backoffice/auth-settings")

    lv
    |> form("#mfa-toggle-form", mfa: %{"enabled" => "false"})
    |> render_submit()

    assert Application.get_env(:guildford_vue, :mfa_via_email_enabled) == false
  end

  test "hostile-client value (anything other than true/false) is rejected server-side",
       %{super_conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/backoffice/auth-settings")

    html =
      lv
      |> render_submit("set_mfa", %{"mfa" => %{"enabled" => "maybe"}})

    assert html =~ "Invalid toggle value"
    # Env unchanged.
    assert Application.get_env(:guildford_vue, :mfa_via_email_enabled) == false
  end
end
