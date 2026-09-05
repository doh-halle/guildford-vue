defmodule GuildfordVueWeb.Admin.AdminPaymentSettingsLiveTest do
  @moduledoc """
  Sprint 8 Slice 6 — admin-only toggle for the Simulated payment
  adapter's decline rate. Superadmins can flip between 0% / 5% /
  50% / 100% for demo / load-testing the decline path.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog}

  setup %{conn: conn} do
    {:ok, super_admin} =
      Admins.register_admin(%{
        "email" => "pays-boss@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Boss",
        "role" => "superadmin"
      })

    {:ok, operator} =
      Admins.register_admin(%{
        "email" => "pays-op@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Op",
        "role" => "operator"
      })

    on_exit(fn ->
      Application.put_env(:guildford_vue, :payment_decline_rate, 0.05)
    end)

    %{conn: conn, super_admin: super_admin, operator: operator}
  end

  defp sign_in_as(conn, admin) do
    token = Admins.generate_session_token(admin)
    init_test_session(conn, %{admin_token: token})
  end

  test "operator → redirected (not authorised)", %{conn: conn, operator: op} do
    conn = sign_in_as(conn, op)
    {:error, {:live_redirect, %{to: redirect}}} = live(conn, ~p"/backoffice/payment-settings")
    assert redirect =~ "/backoffice/dashboard"
  end

  test "superadmin sees the form with the current rate",
       %{conn: conn, super_admin: sa} do
    Application.put_env(:guildford_vue, :payment_decline_rate, 0.05)
    conn = sign_in_as(conn, sa)

    {:ok, _lv, html} = live(conn, ~p"/backoffice/payment-settings")
    assert html =~ "Payment simulation"
    assert html =~ "5%" or html =~ "0.05"
  end

  test "setting a new rate persists + audits + flashes",
       %{conn: conn, super_admin: sa} do
    conn = sign_in_as(conn, sa)
    {:ok, lv, _} = live(conn, ~p"/backoffice/payment-settings")

    lv
    |> form("#decline-rate-form", rate: %{"value" => "0.5"})
    |> render_submit()

    assert Application.get_env(:guildford_vue, :payment_decline_rate) == 0.5

    assert [event] = AuditLog.list(event_type: "payment_decline_rate_changed")
    assert event.actor_id == sa.id
    assert event.payload["new_rate"] == 0.5
  end

  test "0% / 5% / 50% / 100% are the offered options",
       %{conn: conn, super_admin: sa} do
    conn = sign_in_as(conn, sa)
    {:ok, _lv, html} = live(conn, ~p"/backoffice/payment-settings")

    for value <- ["0.0", "0.05", "0.5", "1.0"] do
      assert html =~ ~s(value="#{value}")
    end
  end

  test "non-canonical value is rejected with a flash + does not change env",
       %{conn: conn, super_admin: sa} do
    Application.put_env(:guildford_vue, :payment_decline_rate, 0.05)
    conn = sign_in_as(conn, sa)
    {:ok, lv, _} = live(conn, ~p"/backoffice/payment-settings")

    # Bypass the radio's client-side allowlist via render_hook —
    # simulates a hostile client pushing a non-offered rate.
    html = render_hook(lv, "set_rate", %{"rate" => %{"value" => "0.42"}})

    assert html =~ "invalid" or html =~ "Invalid"
    assert Application.get_env(:guildford_vue, :payment_decline_rate) == 0.05
  end
end
