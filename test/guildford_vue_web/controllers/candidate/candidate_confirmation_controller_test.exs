defmodule GuildfordVueWeb.Candidate.CandidateConfirmationControllerTest do
  @moduledoc """
  Feature tests for GET /candidate/verify-email/:token — the email
  verification page that consumes the one-time token from the
  registration email (PRD §4.2 FR-AUTH-3).

  Implemented as a controller (not a LiveView) so the single-use token
  isn't consumed twice by the HTTP + WebSocket mount pair.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.Candidates

  setup do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alice",
        "last_name" => "Worthington"
      })

    {:ok, token} =
      Candidates.deliver_email_verification_instructions(candidate, fn t -> "url " <> t end)

    %{candidate: candidate, token: token}
  end

  describe "GET /candidate/verify-email/:token with a valid token" do
    test "marks the email verified and renders a success message",
         %{conn: conn, token: token, candidate: c} do
      conn = get(conn, ~p"/candidate/verify-email/#{token}")
      html = html_response(conn, 200)

      assert html =~ "Email verified"
      assert html =~ "You can now sign in"

      verified = Candidates.get_candidate_by_email(c.email)
      assert verified.email_verified_at
    end

    test "the token is single-use — a second visit shows an error",
         %{conn: conn, token: token} do
      _conn = get(conn, ~p"/candidate/verify-email/#{token}")

      conn = get(build_conn(), ~p"/candidate/verify-email/#{token}")
      html = html_response(conn, 200)

      assert html =~ "Verification link is invalid or expired"
    end
  end

  describe "GET /candidate/verify-email/:token with an invalid token" do
    test "renders an error message", %{conn: conn} do
      conn = get(conn, ~p"/candidate/verify-email/not-a-real-token")
      html = html_response(conn, 200)
      assert html =~ "Verification link is invalid or expired"
    end
  end
end
