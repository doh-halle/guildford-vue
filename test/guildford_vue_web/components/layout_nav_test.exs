defmodule GuildfordVueWeb.Components.LayoutNavTest do
  @moduledoc """
  Tests for the scope-aware nav bar rendered by the root layout. The nav
  has four branches depending on which (if any) scope is logged in:

    * `nil` (public)                  → "Candidate" + "Exam centre" + "Back office" login links
    * `current_candidate` set         → email + Settings + Log out (candidate URLs)
    * `current_admin` set             → email + Settings + Log out (backoffice URLs)
    * `current_exam_centre` set       → email + Settings + Log out (examcenter URLs)

  Tests use the landing route as a convenient HTML capture point.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.{Admins, Candidates, ExamCentres}

  describe "GET / (public)" do
    test "shows three login links and no email", %{conn: conn} do
      html =
        conn
        |> get(~p"/")
        |> html_response(200)

      assert html =~ ~r{href="/candidate/login"}
      assert html =~ ~r{href="/examcenter/login"}
      assert html =~ ~r{href="/backoffice/login"}
      # No "Log out" or "Settings" in the layout nav when unauthenticated
      refute html =~ ~r{<nav[^>]*>.*?Log out}s
    end
  end

  describe "GET / with a logged-in candidate" do
    setup %{conn: conn} do
      {:ok, candidate} =
        Candidates.register_candidate(%{
          "email" => "alice@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Alice",
          "last_name" => "Worthington"
        })

      token = Candidates.generate_session_token(candidate)
      conn = init_test_session(conn, %{candidate_token: token})
      %{conn: conn, candidate: candidate}
    end

    test "shows the candidate's email and candidate-scope settings/logout links",
         %{conn: conn, candidate: c} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ c.email
      assert html =~ ~r{href="/candidate/settings"}
      assert html =~ ~r{href="/candidate/logout"}
      # MUST NOT show other scopes' urls (PRD §4.1 isolation)
      refute html =~ ~r{href="/backoffice/settings"}
      refute html =~ ~r{href="/examcenter/settings"}
    end
  end

  describe "GET / with a logged-in admin" do
    setup %{conn: conn} do
      {:ok, admin} =
        Admins.register_admin(%{
          "email" => "ops@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Ops"
        })

      token = Admins.generate_session_token(admin)
      conn = init_test_session(conn, %{admin_token: token})
      %{conn: conn, admin: admin}
    end

    test "shows the admin's email and backoffice settings/logout links",
         %{conn: conn, admin: a} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ a.email
      assert html =~ ~r{href="/backoffice/settings"}
      assert html =~ ~r{href="/backoffice/logout"}
      refute html =~ ~r{href="/candidate/settings"}
      refute html =~ ~r{href="/examcenter/settings"}
    end
  end

  describe "GET / with a logged-in exam centre" do
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
      token = ExamCentres.generate_session_token(centre)
      conn = init_test_session(conn, %{exam_centre_token: token})
      %{conn: conn, centre: centre}
    end

    test "shows the centre's email and examcenter settings/logout links",
         %{conn: conn, centre: c} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ c.email
      assert html =~ ~r{href="/examcenter/settings"}
      assert html =~ ~r{href="/examcenter/logout"}
      refute html =~ ~r{href="/candidate/settings"}
      refute html =~ ~r{href="/backoffice/settings"}
    end
  end
end
