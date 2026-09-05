defmodule GuildfordVueWeb.Admin.AdminCentrePerformanceLiveTest do
  @moduledoc """
  Sprint 10 Slice 5 — /backoffice/centres/performance.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "cp-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "cp-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Perf Centre",
        "address_line_1" => "1 St",
        "city" => "York",
        "postcode" => "YO1 8XT"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Perf Exam",
          "code" => "PF-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(centre, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => 5
      })

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "cp-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "CP",
        "last_name" => "Cand"
      })

    {:ok, _b} =
      Bookings.persist_booking(%{
        candidate_id: candidate.id,
        slot_id: slot.id,
        exam_id: exam.id,
        exam_centre_id: centre.id,
        reference: "GV-2026-XYZRT4",
        status: "confirmed",
        price_pence: exam.price_pence,
        paid_at: DateTime.utc_now(),
        payment_token: "tok_stub",
        pdf_url: nil
      })

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, centre: centre}
  end

  test "renders the centre + booking + fill rate", %{conn: conn, centre: c} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/centres/performance")

    assert html =~ "Centre performance"
    assert html =~ c.name
    # 1 confirmed booking on a capacity-5 slot → 20.0% fill rate
    assert html =~ "20.0%"
  end

  test "renders the centre-specific row", %{conn: conn, centre: c} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/centres/performance")
    row_html = lv |> element("[data-test-id='centre-#{c.id}']") |> render()
    assert row_html =~ c.name
  end
end
