defmodule GuildfordVueWeb.HttpAuthIsolationTest do
  @moduledoc """
  HTTP-layer counterpart to `test/guildford_vue/auth_isolation_test.exs`.

  The context-level isolation test proves the three Elixir contexts can't
  share session tokens. THIS test proves the HTTP pipelines can't either:
  a request to `/backoffice/dashboard` carrying a candidate-scoped session
  cookie must be redirected to `/backoffice/login`, regardless of how
  "logged in" the requester is in another scope.

  PRD §4.1: "There is no cross-authentication: a candidate cannot use admin
  credentials and vice versa."
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.{Admins, Candidates, ExamCentres}

  setup %{conn: conn} do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alice",
        "last_name" => "Worthington"
      })

    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "ops@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Ops"
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

    %{
      conn: conn,
      candidate: candidate,
      admin: admin,
      centre: centre,
      candidate_token: Candidates.generate_session_token(candidate),
      admin_token: Admins.generate_session_token(admin),
      centre_token: ExamCentres.generate_session_token(centre)
    }
  end

  describe "a candidate session cannot access /backoffice/* or /examcenter/*" do
    test "GET /backoffice/dashboard with candidate token redirects to /backoffice/login",
         %{conn: conn, candidate_token: t} do
      resp =
        conn
        |> init_test_session(%{candidate_token: t})
        |> get(~p"/backoffice/dashboard")

      assert redirected_to(resp) == ~p"/backoffice/login"
    end

    test "GET /examcenter/dashboard with candidate token redirects to /examcenter/login",
         %{conn: conn, candidate_token: t} do
      resp =
        conn
        |> init_test_session(%{candidate_token: t})
        |> get(~p"/examcenter/dashboard")

      assert redirected_to(resp) == ~p"/examcenter/login"
    end
  end

  describe "an admin session cannot access /candidate/* or /examcenter/* protected routes" do
    test "GET /candidate/dashboard with admin token redirects to /candidate/login",
         %{conn: conn, admin_token: t} do
      resp =
        conn
        |> init_test_session(%{admin_token: t})
        |> get(~p"/candidate/dashboard")

      assert redirected_to(resp) == ~p"/candidate/login"
    end

    test "GET /examcenter/dashboard with admin token redirects to /examcenter/login",
         %{conn: conn, admin_token: t} do
      resp =
        conn
        |> init_test_session(%{admin_token: t})
        |> get(~p"/examcenter/dashboard")

      assert redirected_to(resp) == ~p"/examcenter/login"
    end
  end

  describe "an exam-centre session cannot access /candidate/* or /backoffice/* protected routes" do
    test "GET /candidate/dashboard with centre token redirects to /candidate/login",
         %{conn: conn, centre_token: t} do
      resp =
        conn
        |> init_test_session(%{exam_centre_token: t})
        |> get(~p"/candidate/dashboard")

      assert redirected_to(resp) == ~p"/candidate/login"
    end

    test "GET /backoffice/dashboard with centre token redirects to /backoffice/login",
         %{conn: conn, centre_token: t} do
      resp =
        conn
        |> init_test_session(%{exam_centre_token: t})
        |> get(~p"/backoffice/dashboard")

      assert redirected_to(resp) == ~p"/backoffice/login"
    end
  end

  describe "a user logged into one scope can still use their own scope" do
    test "candidate session reaches /candidate/dashboard",
         %{conn: conn, candidate_token: t, candidate: c} do
      resp =
        conn
        |> init_test_session(%{candidate_token: t})
        |> get(~p"/candidate/dashboard")

      assert resp.status == 200
      assert resp.resp_body =~ c.email
    end

    test "admin session reaches /backoffice/dashboard",
         %{conn: conn, admin_token: t, admin: a} do
      resp =
        conn
        |> init_test_session(%{admin_token: t})
        |> get(~p"/backoffice/dashboard")

      assert resp.status == 200
      assert resp.resp_body =~ a.email
    end

    test "exam-centre session reaches /examcenter/dashboard",
         %{conn: conn, centre_token: t, centre: c} do
      resp =
        conn
        |> init_test_session(%{exam_centre_token: t})
        |> get(~p"/examcenter/dashboard")

      assert resp.status == 200
      assert resp.resp_body =~ c.email
    end
  end

  describe "stashing scope-specific :return_to" do
    test "an unauthenticated request to /candidate/dashboard stashes ONLY :candidate_return_to",
         %{conn: conn} do
      resp = get(conn, ~p"/candidate/dashboard")

      assert redirected_to(resp) == ~p"/candidate/login"
      assert get_session(resp, :candidate_return_to) == "/candidate/dashboard"
      refute get_session(resp, :admin_return_to)
      refute get_session(resp, :exam_centre_return_to)
    end

    test "an unauthenticated request to /backoffice/dashboard stashes ONLY :admin_return_to",
         %{conn: conn} do
      resp = get(conn, ~p"/backoffice/dashboard")

      assert redirected_to(resp) == ~p"/backoffice/login"
      assert get_session(resp, :admin_return_to) == "/backoffice/dashboard"
      refute get_session(resp, :candidate_return_to)
      refute get_session(resp, :exam_centre_return_to)
    end

    test "an unauthenticated request to /examcenter/dashboard stashes ONLY :exam_centre_return_to",
         %{conn: conn} do
      resp = get(conn, ~p"/examcenter/dashboard")

      assert redirected_to(resp) == ~p"/examcenter/login"
      assert get_session(resp, :exam_centre_return_to) == "/examcenter/dashboard"
      refute get_session(resp, :candidate_return_to)
      refute get_session(resp, :admin_return_to)
    end
  end
end
