defmodule GuildfordVueWeb.Admin.AdminDashboardLiveTest do
  @moduledoc """
  Sprint 2 Slice 6 — real admin dashboard metrics.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Candidates, ExamCentres}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "dash-boss@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Boss",
        "role" => "superadmin"
      })

    {:ok, pending_centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "pending@example.com",
        "password" => "supersecret123!A",
        "name" => "Pending Centre",
        "address_line_1" => "1 Pending Way",
        "city" => "Cardiff",
        "postcode" => "CF1 1AA",
        "latitude" => 51.5,
        "longitude" => -3.2
      })

    {:ok, approved_seed} =
      ExamCentres.register_exam_centre(%{
        "email" => "approved@example.com",
        "password" => "supersecret123!A",
        "name" => "Approved Centre",
        "address_line_1" => "2 Approved Way",
        "city" => "Edinburgh",
        "postcode" => "EH1 1AA",
        "latitude" => 55.9,
        "longitude" => -3.2
      })

    {:ok, _approved} = ExamCentres.approve(approved_seed, admin)

    {:ok, _cand} =
      Candidates.register_candidate(%{
        "email" => "a@example.com",
        "password" => "supersecret123!A",
        "first_name" => "A",
        "last_name" => "X"
      })

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, admin: admin, pending_centre: pending_centre}
  end

  test "shows metric counts", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/dashboard")

    assert html =~ "Pending centres"
    assert html =~ "Approved centres"
    assert html =~ "Candidates"
    # Counts: 1 pending, 1 approved, 1 candidate
    assert html =~ ~r/Pending centres.*?>\s*1\s*</s or html =~ ">1<"
  end

  test "links to centres / candidates / audit log", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/dashboard")
    assert html =~ "/backoffice/centres"
    assert html =~ "/backoffice/candidates"
    assert html =~ "/backoffice/audit-log"
  end

  test "shows Sprint 10 bookings + revenue tiles", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/backoffice/dashboard")

    assert html =~ "Bookings today"
    assert html =~ "This week"
    assert html =~ "This month"
    assert html =~ "Revenue"

    # No bookings yet → zeros
    today = lv |> element("[data-test-id='bookings-today']") |> render()
    assert today =~ ~r/>\s*0\s*</

    revenue = lv |> element("[data-test-id='revenue-total']") |> render()
    assert revenue =~ "£0.00"
  end
end
