defmodule GuildfordVueWeb.Candidate.CandidateRegistrationLiveTest do
  @moduledoc """
  Feature tests for the candidate registration LiveView.

  PRD §4.2 FR-CAND-1: candidate self-registration with email-verification
  via Mailcatcher (dev) / Mailgun (prod).
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias GuildfordVue.Candidates

  @valid %{
    "email" => "alice@example.com",
    "password" => "supersecret123!A",
    "first_name" => "Alice",
    "last_name" => "Worthington",
    "postcode" => "GU1 4LZ"
  }

  describe "GET /candidate/register" do
    test "renders the registration form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/candidate/register")
      assert html =~ "Register"
      assert html =~ "First name"
      assert html =~ "Last name"
      assert html =~ "Email"
      assert html =~ "Password"
      assert html =~ "Postcode"
    end

    test "redirects an already-logged-in candidate to /candidate/dashboard",
         %{conn: conn} do
      {:ok, c} =
        Candidates.register_candidate(%{
          "email" => "existing@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Existing",
          "last_name" => "Candidate"
        })

      token = Candidates.generate_session_token(c)

      assert {:error, {:live_redirect, %{to: "/candidate/dashboard"}}} =
               conn
               |> init_test_session(%{candidate_token: token})
               |> live(~p"/candidate/register")
    end
  end

  describe "submit (phx-submit save event)" do
    test "registers a candidate, sends a verification email, and redirects",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/candidate/register")

      lv
      |> form("#candidate-registration-form", candidate: @valid)
      |> render_submit()

      assert_redirect(lv, ~p"/candidate/login")

      candidate = Candidates.get_candidate_by_email("alice@example.com")
      assert candidate
      refute candidate.email_verified_at

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_name, addr} -> addr == "alice@example.com" end) and
          email.subject =~ "Verify your" and
          email.text_body =~ "/candidate/verify-email/"
      end)
    end

    test "shows error on invalid email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/candidate/register")

      result =
        lv
        |> form("#candidate-registration-form",
          candidate: %{@valid | "email" => "not-an-email"}
        )
        |> render_submit()

      assert result =~ "must be a valid email address"
      refute Candidates.get_candidate_by_email("not-an-email")
    end

    test "shows error on too-short password", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/candidate/register")

      result =
        lv
        |> form("#candidate-registration-form", candidate: %{@valid | "password" => "short"})
        |> render_submit()

      assert result =~ "should be at least 12"
      refute Candidates.get_candidate_by_email("alice@example.com")
    end

    test "shows error on duplicate email", %{conn: conn} do
      {:ok, _} = Candidates.register_candidate(@valid)

      {:ok, lv, _html} = live(conn, ~p"/candidate/register")

      result =
        lv
        |> form("#candidate-registration-form", candidate: @valid)
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end
end
