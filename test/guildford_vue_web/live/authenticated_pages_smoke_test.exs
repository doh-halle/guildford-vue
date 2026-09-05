defmodule GuildfordVueWeb.AuthenticatedPagesSmokeTest do
  @moduledoc """
  Smoke tests for the 6 authenticated LiveViews (3 dashboards + 3 settings
  pages). Sprint 1c slice E shipped these as visual surfaces without
  feature tests; this file is the minimum-viable test set that pins each
  page to:

    - mount succeeds (no exceptions)
    - the page renders identifying content
    - require_authenticated_X gates a non-authed request

  More substantive tests (form interactions, error states) come in Sprint
  2+ as the dashboards gain real functionality.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Candidates, ExamCentres}

  describe "candidate dashboard + settings" do
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

    test "dashboard renders profile card", %{conn: conn, candidate: c} do
      {:ok, _view, html} = live(conn, ~p"/candidate/dashboard")
      assert html =~ "Welcome back"
      assert html =~ c.first_name
      assert html =~ c.email
    end

    test "settings renders both forms", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/candidate/settings")
      assert html =~ "Settings"
      assert html =~ "Profile"
      assert html =~ "Change password"
      assert html =~ "First name"
      assert html =~ "Current password"
    end

    test "settings updates the profile via phx-submit", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/candidate/settings")

      lv
      |> form("#candidate-profile-form",
        profile: %{
          "first_name" => "Updated",
          "last_name" => "Name",
          "phone" => "+447777000000",
          "postcode" => "EH1 1YZ"
        }
      )
      |> render_submit()

      assert Candidates.get_candidate_by_email("alice@example.com").first_name == "Updated"
    end

    test "settings: change_password with wrong current pw does NOT rotate hash",
         %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/candidate/settings")
      before = Candidates.get_candidate_by_email("alice@example.com").hashed_password

      lv
      |> form("#candidate-password-form",
        password: %{"current_password" => "wrong", "password" => "newpassword456!B"}
      )
      |> render_submit()

      after_hash = Candidates.get_candidate_by_email("alice@example.com").hashed_password
      assert before == after_hash, "password must NOT rotate when current_password is wrong"
    end
  end

  describe "admin dashboard + settings" do
    setup %{conn: conn} do
      {:ok, admin} =
        Admins.register_admin(%{
          "email" => "ops@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Ops User"
        })

      token = Admins.generate_session_token(admin)
      conn = init_test_session(conn, %{admin_token: token})
      %{conn: conn, admin: admin}
    end

    test "dashboard renders welcome", %{conn: conn, admin: a} do
      {:ok, _view, html} = live(conn, ~p"/backoffice/dashboard")
      assert html =~ "Welcome, #{a.name}"
      assert html =~ "Role: operator"
    end

    test "settings renders password form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/backoffice/settings")
      assert html =~ "Change password"
      assert html =~ "Current password"
    end

    test "settings: wrong current password does NOT rotate hash",
         %{conn: conn, admin: a} do
      {:ok, lv, _} = live(conn, ~p"/backoffice/settings")
      before = Admins.get_admin_by_email(a.email).hashed_password

      lv
      |> form("#admin-password-form",
        password: %{"current_password" => "wrong", "password" => "newpassword456!B"}
      )
      |> render_submit()

      assert Admins.get_admin_by_email(a.email).hashed_password == before
    end
  end

  describe "exam centre dashboard + settings" do
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

    test "dashboard renders centre name + address", %{conn: conn, centre: c} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/dashboard")
      assert html =~ c.name
      assert html =~ c.postcode
    end

    test "settings renders password form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/settings")
      assert html =~ "Change password"
    end

    test "settings: wrong current password does NOT rotate hash",
         %{conn: conn, centre: c} do
      {:ok, lv, _} = live(conn, ~p"/examcenter/settings")
      before = ExamCentres.get_exam_centre_by_email(c.email).hashed_password

      lv
      |> form("#exam-centre-password-form",
        password: %{"current_password" => "wrong", "password" => "newpassword456!B"}
      )
      |> render_submit()

      assert ExamCentres.get_exam_centre_by_email(c.email).hashed_password == before
    end
  end

  describe "require_authenticated_X gates" do
    test "unauthenticated GET /candidate/settings redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/candidate/settings")
      assert redirected_to(conn) == ~p"/candidate/login"
    end

    test "unauthenticated GET /backoffice/settings redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/backoffice/settings")
      assert redirected_to(conn) == ~p"/backoffice/login"
    end

    test "unauthenticated GET /examcenter/settings redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/examcenter/settings")
      assert redirected_to(conn) == ~p"/examcenter/login"
    end
  end
end
