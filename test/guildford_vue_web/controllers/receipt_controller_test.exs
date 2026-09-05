defmodule GuildfordVueWeb.ReceiptControllerTest do
  @moduledoc """
  Sprint 9 Slice 2 — receipt download controller. Two endpoints:

    GET /candidate/bookings/:reference/receipt.html  — preview
    GET /candidate/bookings/:reference/receipt.pdf   — download

  Both gated by `require_authenticated_candidate` AND a per-booking
  authorisation check (booking.candidate_id == current_candidate.id).
  """
  use GuildfordVueWeb.ConnCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "rc-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "rc-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Receipt Centre",
        "address_line_1" => "1 Receipt St",
        "city" => "Leeds",
        "postcode" => "LS1 1UR"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Receipt Exam",
          "code" => "RCT",
          "certification_body" => "Receipt Body",
          "duration_minutes" => 90,
          "price_pence" => 3500
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
        "email" => "rc-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Receipt",
        "last_name" => "Candidate"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)
    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    {:ok, booking} = Bookings.create_booking(candidate, slot)

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    %{conn: conn, candidate: candidate, booking: booking, exam: exam, centre: centre}
  end

  describe "GET /candidate/bookings/:reference/receipt.html" do
    test "200 with HTML containing the booking reference + exam name",
         %{conn: conn, booking: b, exam: e, centre: c} do
      conn = get(conn, ~p"/candidate/bookings/#{b.reference}/receipt.html")
      html = response(conn, 200)

      assert get_resp_header(conn, "content-type")
             |> List.first()
             |> String.starts_with?("text/html")

      assert html =~ b.reference
      assert html =~ e.name
      assert html =~ c.name
    end

    test "another candidate can't fetch this receipt", %{booking: b} do
      {:ok, snooper} =
        Candidates.register_candidate(%{
          "email" => "rc-snoop@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Snoop",
          "last_name" => "C"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{candidate_token: Candidates.generate_session_token(snooper)})

      conn = get(conn, ~p"/candidate/bookings/#{b.reference}/receipt.html")
      assert redirected_to(conn) =~ "/candidate/bookings"
    end

    test "unauthenticated → redirected to login", %{booking: b} do
      conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})
      conn = get(conn, ~p"/candidate/bookings/#{b.reference}/receipt.html")
      assert redirected_to(conn) =~ "/candidate/login"
    end

    test "unknown reference → redirect to bookings list", %{conn: conn} do
      conn = get(conn, ~p"/candidate/bookings/GV-2026-NOPE99/receipt.html")
      assert redirected_to(conn) =~ "/candidate/bookings"
    end
  end

  describe "GET /candidate/bookings/:reference/receipt.pdf" do
    test "200 with application/pdf content-type", %{conn: conn, booking: b} do
      conn = get(conn, ~p"/candidate/bookings/#{b.reference}/receipt.pdf")
      assert response(conn, 200)

      ct = get_resp_header(conn, "content-type") |> List.first()
      assert ct =~ "application/pdf" or ct =~ "text/html"
      # Stub returns HTML bytes for tests; real Chromic returns
      # application/pdf. Both are acceptable here.
    end

    test "content-disposition is attachment for downloads",
         %{conn: conn, booking: b} do
      conn = get(conn, ~p"/candidate/bookings/#{b.reference}/receipt.pdf")
      cd = get_resp_header(conn, "content-disposition") |> List.first()
      assert cd =~ "attachment"
      assert cd =~ b.reference
    end

    test "auth-scoped: another candidate can't download this PDF",
         %{booking: b} do
      {:ok, snooper} =
        Candidates.register_candidate(%{
          "email" => "rc-snoop-pdf@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Snoop",
          "last_name" => "PDF"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{candidate_token: Candidates.generate_session_token(snooper)})

      conn = get(conn, ~p"/candidate/bookings/#{b.reference}/receipt.pdf")
      assert redirected_to(conn) =~ "/candidate/bookings"
    end
  end

  describe "Booking.pdf_url now points at the controller URL" do
    test "newly-created bookings have pdf_url = /candidate/bookings/REF/receipt.pdf",
         %{booking: b} do
      assert b.pdf_url == "/candidate/bookings/#{b.reference}/receipt.pdf"
    end
  end
end
