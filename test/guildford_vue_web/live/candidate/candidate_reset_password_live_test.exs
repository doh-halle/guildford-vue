defmodule GuildfordVueWeb.Candidate.CandidateResetPasswordLiveTest do
  @moduledoc """
  Feature tests for GET /candidate/reset-password/:token. The form is
  rendered by the LiveView; phx-submit calls Candidates.reset_password/2
  which consumes the token and rotates the hash.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

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
      Candidates.deliver_password_reset_instructions(candidate, fn t -> "url " <> t end)

    %{candidate: candidate, token: token}
  end

  describe "GET /candidate/reset-password/:token with a valid token" do
    test "renders the password form", %{conn: conn, token: token} do
      {:ok, _view, html} = live(conn, ~p"/candidate/reset-password/#{token}")
      assert html =~ "Reset your password"
      assert html =~ "New password"
    end
  end

  describe "GET with an invalid token" do
    test "shows an invalid-token message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/candidate/reset-password/not-a-real-token")
      assert html =~ "Reset link is invalid or expired"
    end
  end

  describe "submit (phx-submit save event)" do
    test "rotates the password and redirects to login",
         %{conn: conn, token: token, candidate: c} do
      {:ok, lv, _} = live(conn, ~p"/candidate/reset-password/#{token}")

      lv
      |> form("#candidate-reset-password-form",
        candidate: %{"password" => "newpassword456!B"}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/candidate/login")

      assert Candidates.get_candidate_by_email_and_password(c.email, "newpassword456!B").id ==
               c.id
    end

    test "shows an error on too-short password (token preserved)",
         %{conn: conn, token: token} do
      {:ok, lv, _} = live(conn, ~p"/candidate/reset-password/#{token}")

      result =
        lv
        |> form("#candidate-reset-password-form", candidate: %{"password" => "short"})
        |> render_submit()

      assert result =~ "should be at least 12"
    end
  end
end
