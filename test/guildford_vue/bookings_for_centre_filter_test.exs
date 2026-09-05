defmodule GuildfordVue.BookingsForCentreFilterTest do
  @moduledoc """
  TDD tests for the status-filter overload of
  `GuildfordVue.Bookings.list_bookings_for_centre/2`.

  These tests are written BEFORE the production code exists; they are expected
  to fail with a FunctionClauseError (or UndefinedFunctionError if the arity-2
  form doesn't exist yet) until the implementation is added.

  Invariants exercised:
    - `:status` filter accepts `"confirmed"`, `"cancelled"`, `"refunded"`.
    - `"all"`, `nil`, and `[]` (missing opt) behave identically — no filter.
    - 1-arg form keeps returning all bookings unchanged.
    - Tenant isolation: a status filter on centre_a never leaks centre_b rows.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  # ---------------------------------------------------------------------------
  # Shared setup — two approved centres, one exam, three bookings at centre_a
  # (confirmed / cancelled / refunded), one confirmed at centre_b.
  # ---------------------------------------------------------------------------

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bff-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "BFF Admin",
        "role" => "superadmin"
      })

    {:ok, centre_a} =
      ExamCentres.register_exam_centre(%{
        "email" => "bff-ca-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BFF Centre A",
        "address_line_1" => "1 High St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, centre_a} = ExamCentres.approve(centre_a, admin)

    {:ok, centre_b} =
      ExamCentres.register_exam_centre(%{
        "email" => "bff-cb-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BFF Centre B",
        "address_line_1" => "2 Low St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre_b} = ExamCentres.approve(centre_b, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "BFF Exam",
          "code" => "BFF-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4_500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre_a, [exam.id], centre_a)
    {:ok, _} = ExamCentres.set_offerings(centre_b, [exam.id], centre_b)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    # Three slots at centre_a — one per booking so capacity is not a concern.
    {:ok, slot_a1} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 3600, :second),
        "capacity" => 10
      })

    {:ok, slot_a2} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => DateTime.add(future, 1, :day),
        "ends_at" => DateTime.add(future, 86_400 + 3600, :second),
        "capacity" => 10
      })

    {:ok, slot_a3} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => DateTime.add(future, 2, :day),
        "ends_at" => DateTime.add(future, 2 * 86_400 + 3600, :second),
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
        "email" => "bff-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "BFF",
        "last_name" => "Candidate"
      })

    # Start GenServers for both centres.
    {:ok, _pid_a} = Centres.start_centre(centre_a.id)
    {:ok, _pid_b} = Centres.start_centre(centre_b.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre_a.id)
      _ = Centres.stop_centre(centre_b.id)
    end)

    # booking_confirmed — stays confirmed (default status after create).
    {:ok, booking_confirmed} = Bookings.create_booking(candidate, slot_a1)

    # booking_cancelled — cancel it via Bookings.cancel_booking/2.
    {:ok, booking_for_cancel} = Bookings.create_booking(candidate, slot_a2)
    {:ok, booking_cancelled} = Bookings.cancel_booking(booking_for_cancel, candidate)

    # booking_refunded — refund it via Bookings.refund/2 (admin action).
    {:ok, booking_for_refund} = Bookings.create_booking(candidate, slot_a3)
    {:ok, booking_refunded} = Bookings.refund(booking_for_refund, admin)

    # One confirmed booking at centre_b — must never leak into centre_a queries.
    {:ok, booking_b} = Bookings.create_booking(candidate, slot_b)

    %{
      admin: admin,
      centre_a: centre_a,
      centre_b: centre_b,
      exam: exam,
      candidate: candidate,
      booking_confirmed: booking_confirmed,
      booking_cancelled: booking_cancelled,
      booking_refunded: booking_refunded,
      booking_b: booking_b
    }
  end

  # ---------------------------------------------------------------------------
  # Status-specific filters
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/2 with status: \"confirmed\"" do
    test "returns only the confirmed booking", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, status: "confirmed")

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_confirmed.reference in refs
      refute ctx.booking_cancelled.reference in refs
      refute ctx.booking_refunded.reference in refs
    end
  end

  describe "list_bookings_for_centre/2 with status: \"cancelled\"" do
    test "returns only the cancelled booking", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, status: "cancelled")

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_cancelled.reference in refs
      refute ctx.booking_confirmed.reference in refs
      refute ctx.booking_refunded.reference in refs
    end
  end

  describe "list_bookings_for_centre/2 with status: \"refunded\"" do
    test "returns only the refunded booking", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, status: "refunded")

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_refunded.reference in refs
      refute ctx.booking_confirmed.reference in refs
      refute ctx.booking_cancelled.reference in refs
    end
  end

  # ---------------------------------------------------------------------------
  # "All" / no-filter forms — must return all three bookings
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/2 with status: \"all\"" do
    test "returns all three bookings at centre_a", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, status: "all")

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_confirmed.reference in refs
      assert ctx.booking_cancelled.reference in refs
      assert ctx.booking_refunded.reference in refs
    end
  end

  describe "list_bookings_for_centre/2 with status: nil" do
    test "returns all three bookings at centre_a (nil = no filter)", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, status: nil)

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_confirmed.reference in refs
      assert ctx.booking_cancelled.reference in refs
      assert ctx.booking_refunded.reference in refs
    end
  end

  describe "list_bookings_for_centre/2 with empty opts []" do
    test "returns all three bookings at centre_a (no opts = no filter)", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, [])

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_confirmed.reference in refs
      assert ctx.booking_cancelled.reference in refs
      assert ctx.booking_refunded.reference in refs
    end
  end

  # ---------------------------------------------------------------------------
  # 1-arg form unchanged
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/1 (1-arg form unchanged)" do
    test "still returns all three bookings at centre_a", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a)

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_confirmed.reference in refs
      assert ctx.booking_cancelled.reference in refs
      assert ctx.booking_refunded.reference in refs
    end
  end

  # ---------------------------------------------------------------------------
  # Tenant isolation with status filter
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/2 tenant isolation" do
    test "status: \"confirmed\" on centre_a does NOT return centre_b's confirmed booking",
         ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a, status: "confirmed")

      refs = Enum.map(bookings, & &1.reference)
      refute ctx.booking_b.reference in refs
    end
  end
end
