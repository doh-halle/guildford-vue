defmodule GuildfordVueWeb.Admin.AdminAuthTest do
  @moduledoc """
  Mirror of `CandidateAuthTest` for the admin scope. Pins the same isolation
  properties: this plug only ever touches `:admin_token` and `:current_admin`.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.Admins
  alias GuildfordVueWeb.Admin.AdminAuth

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "ops@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Ops User"
      })

    conn =
      %{conn | secret_key_base: GuildfordVueWeb.Endpoint.config(:secret_key_base)}
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()

    %{conn: conn, admin: admin}
  end

  describe "log_in_admin/3" do
    test "stores a session token under :admin_token", %{conn: conn, admin: a} do
      conn = AdminAuth.log_in_admin(conn, a)
      assert get_session(conn, :admin_token)
      assert redirected_to(conn) == "/backoffice/dashboard"
    end

    test "honours :admin_return_to from the session", %{conn: conn, admin: a} do
      conn =
        conn
        |> put_session(:admin_return_to, "/backoffice/audit")
        |> AdminAuth.log_in_admin(a)

      assert redirected_to(conn) == "/backoffice/audit"
    end

    test "does NOT touch candidate or exam_centre tokens", %{conn: conn, admin: a} do
      conn =
        conn
        |> put_session(:candidate_token, "candidate-token")
        |> put_session(:exam_centre_token, "centre-token")
        |> AdminAuth.log_in_admin(a)

      assert get_session(conn, :candidate_token) == "candidate-token"
      assert get_session(conn, :exam_centre_token) == "centre-token"
    end
  end

  describe "log_out_admin/1" do
    test "clears the admin token, leaves other scopes intact", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      conn =
        conn
        |> put_session(:candidate_token, "candidate-token")
        |> put_session(:exam_centre_token, "centre-token")
        |> put_session(:admin_token, token)
        |> AdminAuth.log_out_admin()

      refute get_session(conn, :admin_token)
      assert get_session(conn, :candidate_token) == "candidate-token"
      assert get_session(conn, :exam_centre_token) == "centre-token"
      assert redirected_to(conn) == "/"
    end

    test "deletes the underlying DB token row", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)
      assert Admins.get_admin_by_session_token(token)

      _ =
        conn
        |> put_session(:admin_token, token)
        |> AdminAuth.log_out_admin()

      refute Admins.get_admin_by_session_token(token)
    end
  end

  describe "fetch_current_admin/2" do
    test "assigns :current_admin from a valid token", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      conn =
        conn
        |> put_session(:admin_token, token)
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin.id == a.id
    end

    test "assigns nil when no token", %{conn: conn} do
      conn = AdminAuth.fetch_current_admin(conn, [])
      assert conn.assigns.current_admin == nil
    end

    test "does NOT set candidate or exam_centre assigns", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      conn =
        conn
        |> put_session(:admin_token, token)
        |> AdminAuth.fetch_current_admin([])

      refute Map.has_key?(conn.assigns, :current_candidate)
      refute Map.has_key?(conn.assigns, :current_exam_centre)
    end
  end

  describe "remember-me + idle timeout (defects 001 + 003 fix)" do
    test "writes the remember-me cookie when remember_me=true", %{conn: conn, admin: a} do
      conn = AdminAuth.log_in_admin(conn, a, %{"remember_me" => "true"})
      cookie = conn.resp_cookies["_guildford_vue_admin_remember_me"]
      assert cookie
      # Admin remember-me is 14 days (shorter than candidates' 30)
      assert cookie.max_age == 14 * 24 * 60 * 60
    end

    test "does not write the cookie when remember_me param absent",
         %{conn: conn, admin: a} do
      conn = AdminAuth.log_in_admin(conn, a)
      refute conn.resp_cookies["_guildford_vue_admin_remember_me"]
    end

    test "fetch_current_admin clears session on idle timeout", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)
      stale = System.system_time(:second) - 31 * 60

      conn =
        conn
        |> put_session(:admin_token, token)
        |> put_session(:admin_last_activity_at, stale)
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin == nil
      refute get_session(conn, :admin_token)
    end

    test "log_out_admin clears the remember-me cookie", %{conn: conn, admin: a} do
      conn1 = AdminAuth.log_in_admin(conn, a, %{"remember_me" => "true"})
      assert conn1.resp_cookies["_guildford_vue_admin_remember_me"]

      conn2 =
        conn
        |> put_session(:admin_token, Admins.generate_session_token(a))
        |> AdminAuth.log_out_admin()

      cookie = conn2.resp_cookies["_guildford_vue_admin_remember_me"]
      assert cookie.max_age == 0
    end
  end

  describe "remember-me cookie defensive branches" do
    test "invalid remember-me cookie → nil", %{conn: conn} do
      conn =
        conn
        |> put_resp_cookie("_guildford_vue_admin_remember_me", "garbage",
          sign: true,
          max_age: 60,
          http_only: true
        )
        |> recycle()
        |> Map.replace!(:secret_key_base, GuildfordVueWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin == nil
    end

    test "valid-looking cookie pointing at revoked token → nil", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)
      :ok = Admins.delete_session_token(token)

      conn =
        conn
        |> put_resp_cookie("_guildford_vue_admin_remember_me", token,
          sign: true,
          max_age: 30 * 24 * 60 * 60,
          http_only: true
        )
        |> recycle()
        |> Map.replace!(:secret_key_base, GuildfordVueWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> AdminAuth.fetch_current_admin([])

      assert conn.assigns.current_admin == nil
    end
  end

  describe "require_authenticated_admin/2 (more)" do
    test "POST without auth does NOT stash return_to (only GETs do)", %{conn: conn} do
      conn =
        %{conn | method: "POST", request_path: "/backoffice/somewhere"}
        |> Plug.Conn.fetch_query_params()
        |> assign(:current_admin, nil)
        |> AdminAuth.require_authenticated_admin([])

      assert conn.halted
      refute get_session(conn, :admin_return_to)
    end

    test "GET with query string stashes the full request_path?query", %{conn: conn} do
      conn =
        %{conn | request_path: "/backoffice/users", query_string: "filter=active"}
        |> Plug.Conn.fetch_query_params()
        |> assign(:current_admin, nil)
        |> AdminAuth.require_authenticated_admin([])

      assert get_session(conn, :admin_return_to) == "/backoffice/users?filter=active"
    end
  end

  describe "require_authenticated_admin/2" do
    test "passes through when current_admin set", %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      conn =
        conn
        |> put_session(:admin_token, token)
        |> AdminAuth.fetch_current_admin([])
        |> AdminAuth.require_authenticated_admin([])

      refute conn.halted
    end

    test "halts and redirects to /backoffice/login", %{conn: conn} do
      conn =
        conn
        |> assign(:current_admin, nil)
        |> Map.put(:request_path, "/backoffice/dashboard")
        |> Plug.Conn.fetch_query_params()
        |> AdminAuth.require_authenticated_admin([])

      assert conn.halted
      assert redirected_to(conn) == "/backoffice/login"
    end
  end
end
