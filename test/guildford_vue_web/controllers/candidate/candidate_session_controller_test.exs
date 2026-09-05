defmodule GuildfordVueWeb.Candidate.CandidateSessionControllerTest do
  @moduledoc """
  Sprint 1b Slice 1 — placeholder coverage for the candidate session
  controller. The dashboard and login actions are stubs until the LiveViews
  land in Slice 3; only the logout action is real.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.Candidates

  setup %{conn: conn} do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alice",
        "last_name" => "Worthington"
      })

    %{conn: conn, candidate: candidate}
  end

  describe "DELETE /candidate/logout" do
    test "redirects to / and clears the candidate token", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> init_test_session(%{candidate_token: token})
        |> delete(~p"/candidate/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :candidate_token)
    end

    test "is a no-op when there is no candidate session", %{conn: conn} do
      conn = delete(conn, ~p"/candidate/logout")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "GET /candidate/dashboard (placeholder)" do
    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/candidate/dashboard")
      assert redirected_to(conn) == ~p"/candidate/login"
    end

    test "renders the placeholder when authenticated", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> init_test_session(%{candidate_token: token})
        |> get(~p"/candidate/dashboard")

      assert conn.status == 200
      assert conn.resp_body =~ "Welcome back, Alice"
      assert conn.resp_body =~ c.email
    end
  end
end
