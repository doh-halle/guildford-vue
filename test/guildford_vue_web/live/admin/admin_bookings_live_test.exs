defmodule GuildfordVueWeb.Admin.AdminBookingsLiveTest do
  @moduledoc """
  Sprint 10 Slice 4 — /backoffice/bookings admin list + refund button.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "ab-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "ab-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Admin Bookings Centre",
        "address_line_1" => "1 St",
        "city" => "Hull",
        "postcode" => "HU1 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "AB Exam",
          "code" => "AB-#{System.unique_integer([:positive])}",
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
        "email" => "ab-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "AB",
        "last_name" => "Cand"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)
    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    {:ok, booking} = Bookings.create_booking(candidate, slot)

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, admin: admin, centre: centre, booking: booking}
  end

  test "lists the booking with its reference + exam + status", %{conn: conn, booking: b} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/bookings")

    assert html =~ "Bookings"
    assert html =~ b.reference
    assert html =~ "confirmed"
    assert html =~ "AB Exam"
  end

  test "refund button flips the row + flashes success",
       %{conn: conn, booking: b} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/bookings")

    html =
      lv
      |> element("[data-test-id='refund-#{b.reference}']")
      |> render_click()

    assert html =~ "refunded"
    refute html =~ "Refunded #{b.reference}." |> String.replace(" ", "&nbsp;")

    reloaded = Bookings.get_booking_by_reference(b.reference)
    assert reloaded.status == "refunded"
  end

  test "already-refunded bookings have no Refund button", %{conn: conn, booking: b, admin: a} do
    {:ok, _refunded} = Bookings.refund(b, a)

    {:ok, _lv, html} = live(conn, ~p"/backoffice/bookings")
    refute html =~ "refund-#{b.reference}"
    assert html =~ "refunded"
  end
end
