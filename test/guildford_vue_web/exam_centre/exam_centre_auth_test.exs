defmodule GuildfordVueWeb.ExamCentre.ExamCentreAuthTest do
  @moduledoc """
  Mirror of `CandidateAuthTest` for the exam-centre scope. Pins the same
  isolation properties and additionally verifies that a session token
  issued to an approved centre is invalidated if the centre is later
  suspended.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.{Admins, ExamCentres}
  alias GuildfordVueWeb.ExamCentre.ExamCentreAuth

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "approver@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Approver"
      })

    {:ok, pending} =
      ExamCentres.register_exam_centre(%{
        "email" => "centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Test Centre",
        "address_line_1" => "1 Test Street",
        "city" => "Bristol",
        "postcode" => "BS1 4DJ"
      })

    {:ok, centre} = ExamCentres.approve(pending, admin)

    conn =
      %{conn | secret_key_base: GuildfordVueWeb.Endpoint.config(:secret_key_base)}
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()

    %{conn: conn, centre: centre}
  end

  describe "log_in_exam_centre/3" do
    test "stores a session token under :exam_centre_token", %{conn: conn, centre: c} do
      conn = ExamCentreAuth.log_in_exam_centre(conn, c)
      assert get_session(conn, :exam_centre_token)
      assert redirected_to(conn) == "/examcenter/dashboard"
    end

    test "does NOT touch candidate or admin tokens", %{conn: conn, centre: c} do
      conn =
        conn
        |> put_session(:candidate_token, "ct")
        |> put_session(:admin_token, "at")
        |> ExamCentreAuth.log_in_exam_centre(c)

      assert get_session(conn, :candidate_token) == "ct"
      assert get_session(conn, :admin_token) == "at"
    end
  end

  describe "log_out_exam_centre/1" do
    test "clears the exam_centre token and deletes the DB row", %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)
      assert ExamCentres.get_exam_centre_by_session_token(token)

      conn =
        conn
        |> put_session(:exam_centre_token, token)
        |> ExamCentreAuth.log_out_exam_centre()

      refute get_session(conn, :exam_centre_token)
      refute ExamCentres.get_exam_centre_by_session_token(token)
      assert redirected_to(conn) == "/"
    end
  end

  describe "fetch_current_exam_centre/2" do
    test "assigns :current_exam_centre from a valid token", %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)

      conn =
        conn
        |> put_session(:exam_centre_token, token)
        |> ExamCentreAuth.fetch_current_exam_centre([])

      assert conn.assigns.current_exam_centre.id == c.id
    end

    test "assigns nil when token belongs to a suspended centre",
         %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)
      {:ok, _} = ExamCentres.suspend(c)

      conn =
        conn
        |> put_session(:exam_centre_token, token)
        |> ExamCentreAuth.fetch_current_exam_centre([])

      assert conn.assigns.current_exam_centre == nil
    end

    test "does NOT set candidate or admin assigns", %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)

      conn =
        conn
        |> put_session(:exam_centre_token, token)
        |> ExamCentreAuth.fetch_current_exam_centre([])

      refute Map.has_key?(conn.assigns, :current_candidate)
      refute Map.has_key?(conn.assigns, :current_admin)
    end
  end

  describe "remember-me + idle timeout (defects 001 + 003 fix)" do
    test "writes the remember-me cookie when remember_me=true", %{conn: conn, centre: c} do
      conn = ExamCentreAuth.log_in_exam_centre(conn, c, %{"remember_me" => "true"})
      cookie = conn.resp_cookies["_guildford_vue_exam_centre_remember_me"]
      assert cookie
      assert cookie.max_age == 14 * 24 * 60 * 60
    end

    test "fetch_current_exam_centre clears session on idle timeout",
         %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)
      stale = System.system_time(:second) - 31 * 60

      conn =
        conn
        |> put_session(:exam_centre_token, token)
        |> put_session(:exam_centre_last_activity_at, stale)
        |> ExamCentreAuth.fetch_current_exam_centre([])

      assert conn.assigns.current_exam_centre == nil
      refute get_session(conn, :exam_centre_token)
    end

    test "log_out_exam_centre clears the remember-me cookie",
         %{conn: conn, centre: c} do
      conn1 = ExamCentreAuth.log_in_exam_centre(conn, c, %{"remember_me" => "true"})
      assert conn1.resp_cookies["_guildford_vue_exam_centre_remember_me"]

      conn2 =
        conn
        |> put_session(:exam_centre_token, ExamCentres.generate_session_token(c))
        |> ExamCentreAuth.log_out_exam_centre()

      cookie = conn2.resp_cookies["_guildford_vue_exam_centre_remember_me"]
      assert cookie.max_age == 0
    end
  end

  describe "remember-me cookie defensive branches" do
    test "invalid remember-me cookie → nil", %{conn: conn} do
      conn =
        conn
        |> put_resp_cookie("_guildford_vue_exam_centre_remember_me", "garbage",
          sign: true,
          max_age: 60,
          http_only: true
        )
        |> recycle()
        |> Map.replace!(:secret_key_base, GuildfordVueWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> ExamCentreAuth.fetch_current_exam_centre([])

      assert conn.assigns.current_exam_centre == nil
    end

    test "valid-looking cookie pointing at revoked token → nil", %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)
      :ok = ExamCentres.delete_session_token(token)

      conn =
        conn
        |> put_resp_cookie("_guildford_vue_exam_centre_remember_me", token,
          sign: true,
          max_age: 14 * 24 * 60 * 60,
          http_only: true
        )
        |> recycle()
        |> Map.replace!(:secret_key_base, GuildfordVueWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> ExamCentreAuth.fetch_current_exam_centre([])

      assert conn.assigns.current_exam_centre == nil
    end
  end

  describe "require_authenticated_exam_centre/2 (more)" do
    test "POST without auth does NOT stash return_to (only GETs do)", %{conn: conn} do
      conn =
        %{conn | method: "POST", request_path: "/examcenter/somewhere"}
        |> Plug.Conn.fetch_query_params()
        |> assign(:current_exam_centre, nil)
        |> ExamCentreAuth.require_authenticated_exam_centre([])

      assert conn.halted
      refute get_session(conn, :exam_centre_return_to)
    end

    test "GET with query string stashes the full request_path?query", %{conn: conn} do
      conn =
        %{conn | request_path: "/examcenter/slots", query_string: "date=2026-05-30"}
        |> Plug.Conn.fetch_query_params()
        |> assign(:current_exam_centre, nil)
        |> ExamCentreAuth.require_authenticated_exam_centre([])

      assert get_session(conn, :exam_centre_return_to) == "/examcenter/slots?date=2026-05-30"
    end
  end

  describe "require_authenticated_exam_centre/2" do
    test "halts and redirects to /examcenter/login", %{conn: conn} do
      conn =
        conn
        |> assign(:current_exam_centre, nil)
        |> Map.put(:request_path, "/examcenter/dashboard")
        |> Plug.Conn.fetch_query_params()
        |> ExamCentreAuth.require_authenticated_exam_centre([])

      assert conn.halted
      assert redirected_to(conn) == "/examcenter/login"
    end
  end
end
