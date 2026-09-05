defmodule GuildfordVueWeb.RootLayoutTest do
  @moduledoc """
  Sprint 1c defect 003 was: the root layout's account nav used a `cond`
  block, so when two scope sessions co-existed in the same browser the
  earlier branch shadowed the later one. A user holding both a candidate
  and an admin session would see only the candidate chip — no way to
  see they were also logged in as admin, and no easy way to log out the
  admin session.

  Closed in Sprint 2 Slice 2: render one chip per active scope.

  Tests visit `/` because that route runs the `:browser_with_scopes`
  pipeline which fetches all three current_* assigns. Scope-specific
  routes (e.g. /candidate/*) only fetch their own scope by design.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.{Admins, Candidates, ExamCentres, Repo}

  setup %{conn: conn} do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "candidate@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Cand",
        "last_name" => "Worth"
      })

    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "admin@example.com",
        "password" => "supersecret123!A",
        "name" => "An Admin",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Test Centre",
        "address_line_1" => "1 Test Way",
        "city" => "Testville",
        "postcode" => "TE1 1ST",
        "latitude" => 51.5,
        "longitude" => -0.1
      })

    {:ok, centre} = centre |> Ecto.Changeset.change(status: "approved") |> Repo.update()

    {:ok, conn: conn, candidate: candidate, admin: admin, centre: centre}
  end

  test "no sessions → only the unauthenticated links render", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Candidate"
    assert html =~ "Exam centre"
    assert html =~ "Back office"
    refute html =~ "candidate@example.com"
    refute html =~ "admin@example.com"
    refute html =~ "centre@example.com"
  end

  test "candidate-only session → only candidate chip",
       %{conn: conn, candidate: candidate} do
    conn =
      conn
      |> init_test_session(%{candidate_token: Candidates.generate_session_token(candidate)})

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ candidate.email
    refute html =~ "admin@example.com"
    refute html =~ "centre@example.com"
  end

  test "candidate + admin sessions → BOTH chips render (defect 003 fix)",
       %{conn: conn, candidate: candidate, admin: admin} do
    conn =
      conn
      |> init_test_session(%{
        candidate_token: Candidates.generate_session_token(candidate),
        admin_token: Admins.generate_session_token(admin)
      })

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ candidate.email, "candidate chip should be visible"

    assert html =~ admin.email,
           "admin chip should ALSO be visible (cond would have shadowed it)"
  end

  test "all three scope sessions → all three chips render",
       %{conn: conn, candidate: candidate, admin: admin, centre: centre} do
    conn =
      conn
      |> init_test_session(%{
        candidate_token: Candidates.generate_session_token(candidate),
        admin_token: Admins.generate_session_token(admin),
        exam_centre_token: ExamCentres.generate_session_token(centre)
      })

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ candidate.email
    assert html =~ admin.email
    assert html =~ centre.email
  end

  test "each chip's logout link goes to the right scope endpoint",
       %{conn: conn, candidate: candidate, admin: admin, centre: centre} do
    conn =
      conn
      |> init_test_session(%{
        candidate_token: Candidates.generate_session_token(candidate),
        admin_token: Admins.generate_session_token(admin),
        exam_centre_token: ExamCentres.generate_session_token(centre)
      })

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "/candidate/logout"
    assert html =~ "/backoffice/logout"
    assert html =~ "/examcenter/logout"
  end
end
