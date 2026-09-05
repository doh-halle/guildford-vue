defmodule GuildfordVueWeb.Admin.AdminResetPasswordLiveTest do
  @moduledoc """
  Feature tests for GET /backoffice/reset-password/:token. The form is
  rendered by the LiveView; phx-submit calls Candidates.reset_password/2
  which consumes the token and rotates the hash.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.Admins

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "name" => "Alice Worthington"
      })

    {:ok, token} =
      Admins.deliver_password_reset_instructions(admin, fn t -> "url " <> t end)

    %{admin: admin, token: token}
  end

  describe "GET /backoffice/reset-password/:token with a valid token" do
    test "renders the password form", %{conn: conn, token: token} do
      {:ok, _view, html} = live(conn, ~p"/backoffice/reset-password/#{token}")
      assert html =~ "Reset your password"
      assert html =~ "New password"
    end
  end

  describe "GET with an invalid token" do
    test "shows an invalid-token message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/backoffice/reset-password/not-a-real-token")
      assert html =~ "Reset link is invalid or expired"
    end
  end

  describe "submit (phx-submit save event)" do
    test "rotates the password and redirects to login",
         %{conn: conn, token: token, admin: a} do
      {:ok, lv, _} = live(conn, ~p"/backoffice/reset-password/#{token}")

      lv
      |> form("#admin-reset-password-form",
        admin: %{"password" => "newpassword456!B"}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/backoffice/login")

      assert Admins.get_admin_by_email_and_password(a.email, "newpassword456!B").id == a.id
    end

    test "shows an error on too-short password (token preserved)",
         %{conn: conn, token: token} do
      {:ok, lv, _} = live(conn, ~p"/backoffice/reset-password/#{token}")

      result =
        lv
        |> form("#admin-reset-password-form", admin: %{"password" => "short"})
        |> render_submit()

      assert result =~ "should be at least 12"
    end
  end
end
