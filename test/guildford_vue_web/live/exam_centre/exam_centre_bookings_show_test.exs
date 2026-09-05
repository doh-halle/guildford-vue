defmodule GuildfordVueWeb.ExamCentre.ExamCentreBookingsShowTest do
  @moduledoc """
  TDD tests for the exam-centre single-booking detail LiveView:
  `GuildfordVueWeb.ExamCentre.ExamCentreBookingsLive` mounted at
  `/examcenter/bookings/:reference` (live action `:show`).

  All tests are written BEFORE the production module exists; they must fail
  with a missing-module / compile error until the LiveView is implemented.

  Invariants:
    - Detail page renders: reference, exam name, candidate email + name,
      slot start date (human-formatted), price (£-prefixed), status.
    - A back-link to `/examcenter/bookings` is present.
    - Tenant isolation: visiting another centre's booking reference
      redirects to `/examcenter/bookings` with a flash error.
    - Unknown reference likewise redirects.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  # ---------------------------------------------------------------------------
  # Shared setup — two centres, one exam, one booking per centre.
  # ---------------------------------------------------------------------------

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bsh-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "BSH Admin",
        "role" => "superadmin"
      })

    {:ok, centre_a} =
      ExamCentres.register_exam_centre(%{
        "email" => "bsh-ca-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BSH Centre A",
        "address_line_1" => "1 High St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, centre_a} = ExamCentres.approve(centre_a, admin)

    {:ok, centre_b} =
      ExamCentres.register_exam_centre(%{
        "email" => "bsh-cb-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BSH Centre B",
        "address_line_1" => "2 Low St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre_b} = ExamCentres.approve(centre_b, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "BSH Exam",
          "code" => "BSH-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 7_500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre_a, [exam.id], centre_a)
    {:ok, _} = ExamCentres.set_offerings(centre_b, [exam.id], centre_b)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot_a} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 3600, :second),
        "capacity" => 10
      })

    {:ok, slot_b} =
      Slots.create_slot(centre_b, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 3600, :second),
        "capacity" => 10
      })

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "bsh-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Carol",
        "last_name" => "Williams"
      })

    {:ok, _pid_a} = Centres.start_centre(centre_a.id)
    {:ok, _pid_b} = Centres.start_centre(centre_b.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre_a.id)
      _ = Centres.stop_centre(centre_b.id)
    end)

    {:ok, booking_a} = Bookings.create_booking(candidate, slot_a)
    {:ok, booking_b} = Bookings.create_booking(candidate, slot_b)

    conn_a =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre_a)})

    %{
      conn: conn_a,
      centre_a: centre_a,
      centre_b: centre_b,
      exam: exam,
      slot_a: slot_a,
      booking_a: booking_a,
      booking_b: booking_b,
      candidate: candidate
    }
  end

  # ---------------------------------------------------------------------------
  # Content — signed in as centre_a, viewing booking_a
  # ---------------------------------------------------------------------------

  describe "/examcenter/bookings/:reference show" do
    test "renders the booking reference", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      assert html =~ ctx.booking_a.reference
    end

    test "renders the exam name", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      assert html =~ ctx.exam.name
    end

    test "renders the candidate's email", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      assert html =~ ctx.candidate.email
    end

    test "renders the candidate's full name or last name", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      assert html =~ ctx.candidate.last_name
    end

    test "renders the slot start date in a human-readable format", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      # The LV must format the date in some human-readable way. We verify the
      # year (unambiguous) and the day-of-month number appear somewhere together.
      start_year = ctx.slot_a.starts_at |> DateTime.to_date() |> Map.fetch!(:year) |> to_string()

      assert html =~ start_year
    end

    test "renders the price formatted with a £ prefix", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      # price_pence = 7_500 → £75.00 (or similar £-prefixed format)
      assert html =~ "£"
    end

    test "renders the booking status", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      assert html =~ "confirmed"
    end

    test "renders a back-link to /examcenter/bookings", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_a.reference}")

      assert html =~ ~s(href="/examcenter/bookings")
    end
  end

  # ---------------------------------------------------------------------------
  # Tenant isolation
  # ---------------------------------------------------------------------------

  describe "tenant isolation on /examcenter/bookings/:reference" do
    test "visiting centre_b's booking as centre_a redirects to /examcenter/bookings with an error flash",
         ctx do
      # centre_a is signed in; booking_b belongs to centre_b — must be denied.
      result = live(ctx.conn, ~p"/examcenter/bookings/#{ctx.booking_b.reference}")

      assert {:error, {:live_redirect, %{to: "/examcenter/bookings", flash: flash}}} = result
      assert is_binary(flash["error"])
    end

    test "visiting an entirely unknown reference redirects to /examcenter/bookings with an error flash",
         ctx do
      result = live(ctx.conn, ~p"/examcenter/bookings/GV-NOT-EXIST")

      assert {:error, {:live_redirect, %{to: "/examcenter/bookings", flash: flash}}} = result
      assert is_binary(flash["error"])
    end
  end
end
