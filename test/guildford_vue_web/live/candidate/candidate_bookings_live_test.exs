defmodule GuildfordVueWeb.Candidate.CandidateBookingsLiveTest do
  @moduledoc """
  Sprint 7 Slice 6 — candidate bookings list + detail. List at
  /candidate/bookings; detail at /candidate/bookings/:reference.
  Both scoped to the signed-in candidate.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "cb-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "cb-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Bookings Centre",
        "address_line_1" => "1 St",
        "city" => "Bristol",
        "postcode" => "BS1 4DJ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Bookings Exam",
          "code" => "BKL",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4_000
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
        "email" => "cb-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Bookings",
        "last_name" => "Candidate"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    {:ok, booking} = Bookings.create_booking(candidate, slot)

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    %{
      conn: conn,
      candidate: candidate,
      booking: booking,
      slot: slot,
      exam: exam,
      centre: centre
    }
  end

  describe "/candidate/bookings (list)" do
    test "renders the candidate's bookings", %{conn: conn, booking: b, exam: e} do
      {:ok, _lv, html} = live(conn, ~p"/candidate/bookings")
      assert html =~ b.reference
      assert html =~ e.name
    end

    test "empty state when no bookings", %{conn: _conn} do
      {:ok, fresh} =
        Candidates.register_candidate(%{
          "email" => "cb-fresh@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Fresh",
          "last_name" => "C"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{candidate_token: Candidates.generate_session_token(fresh)})

      {:ok, _lv, html} = live(conn, ~p"/candidate/bookings")
      # HTML-escaped apostrophe in the rendered output.
      assert html =~ "haven&#39;t booked" or html =~ "haven't booked"
    end

    test "lists only the signed-in candidate's bookings", %{conn: conn, booking: b} do
      # Create a second candidate with their own booking — must not appear.
      {:ok, other} =
        Candidates.register_candidate(%{
          "email" => "cb-other@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Other",
          "last_name" => "C"
        })

      {:ok, %{slot: slot}} = {:ok, %{slot: Slots.get_slot!(b.slot_id)}}
      {:ok, other_booking} = Bookings.create_booking(other, slot)

      {:ok, _lv, html} = live(conn, ~p"/candidate/bookings")
      assert html =~ b.reference
      refute html =~ other_booking.reference
    end
  end

  describe "/candidate/bookings/:reference (detail)" do
    test "shows reference, exam, centre, PDF link, status",
         %{conn: conn, booking: b, exam: e, centre: c} do
      {:ok, _lv, html} = live(conn, ~p"/candidate/bookings/#{b.reference}")

      assert html =~ b.reference
      assert html =~ e.name
      assert html =~ c.name
      assert html =~ "confirmed"
      assert html =~ b.pdf_url
    end

    test "Cancel button cancels the booking + reloads the page",
         %{conn: conn, booking: b} do
      {:ok, lv, _} = live(conn, ~p"/candidate/bookings/#{b.reference}")

      html =
        lv
        |> element("[data-test-id='cancel-booking']")
        |> render_click()

      assert html =~ "cancelled"
      assert Bookings.get_booking_by_reference(b.reference).status == "cancelled"
    end

    test "another candidate can't see this booking",
         %{booking: b} do
      {:ok, other} =
        Candidates.register_candidate(%{
          "email" => "cb-snoop@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Snoop",
          "last_name" => "C"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{candidate_token: Candidates.generate_session_token(other)})

      # Either redirect to the list with a flash, or 404 — both
      # demonstrate authorisation. We accept either shape.
      result = live(conn, ~p"/candidate/bookings/#{b.reference}")

      assert match?({:error, {:redirect, _}}, result) or
               match?({:error, {:live_redirect, _}}, result)
    end

    test "unknown reference → redirect to list with flash",
         %{conn: conn} do
      {:error, {:live_redirect, %{to: to}}} =
        live(conn, ~p"/candidate/bookings/GV-2026-NOPE99")

      assert to =~ "/candidate/bookings"
    end
  end
end
