defmodule GuildfordVueWeb.Admin.AdminSessionControllerTest do
  @moduledoc """
  Sprint 1b Slice 1 placeholder coverage for the admin session controller.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.Admins

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "operator@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Ops User"
      })

    %{conn: conn, admin: admin}
  end

  describe "DELETE /backoffice/logout" do
    test "redirects to / and clears the admin token", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      conn =
        conn
        |> init_test_session(%{admin_token: token})
        |> delete(~p"/backoffice/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :admin_token)
    end
  end

  describe "GET /backoffice/dashboard (placeholder)" do
    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/backoffice/dashboard")
      assert redirected_to(conn) == ~p"/backoffice/login"
    end

    test "renders the placeholder when authenticated", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      conn =
        conn
        |> init_test_session(%{admin_token: token})
        |> get(~p"/backoffice/dashboard")

      assert conn.status == 200
      assert conn.resp_body =~ "Welcome, Ops User"
      assert conn.resp_body =~ a.email
    end
  end
end
