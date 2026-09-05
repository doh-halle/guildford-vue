defmodule GuildfordVueWeb.Admin.AdminForgotPasswordLiveTest do
  @moduledoc """
  Feature tests for GET /backoffice/forgot-password — the password-reset
  request page. Does NOT leak whether an email is registered (PRD §9
  privacy + OWASP A07).
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias GuildfordVue.Admins

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "name" => "Alice Worthington"
      })

    %{admin: admin}
  end

  describe "GET /backoffice/forgot-password" do
    test "renders the form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/backoffice/forgot-password")
      assert html =~ "Forgot password"
      assert html =~ "Email"
    end
  end

  describe "submit" do
    test "sends a reset email and redirects with a generic confirmation",
         %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/backoffice/forgot-password")

      lv
      |> form("#admin-forgot-password-form", admin: %{"email" => "alice@example.com"})
      |> render_submit()

      assert_redirect(lv, ~p"/backoffice/login")

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_n, addr} -> addr == "alice@example.com" end) and
          email.subject =~ "Reset your" and
          email.text_body =~ "/backoffice/reset-password/"
      end)
    end

    test "does NOT leak whether the email is registered (always same flash)",
         %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/backoffice/forgot-password")

      lv
      |> form("#admin-forgot-password-form", admin: %{"email" => "nobody@example.com"})
      |> render_submit()

      assert_redirect(lv, ~p"/backoffice/login")
      # No email sent for non-existent address
      refute_email_sent()
    end
  end
end
