defmodule GuildfordVue.BookingsForCentreTest do
  @moduledoc """
  TDD tests for the exam-centre-scoped booking queries — Sprint 13 (centre
  bookings listing + detail feature).

  Tests are written BEFORE production code exists; they are expected to fail
  until `GuildfordVue.Bookings.list_bookings_for_centre/1` and
  `GuildfordVue.Bookings.get_booking_for_centre/2` are implemented.

  Invariants exercised:
    - Tenant isolation: only bookings belonging to the queried centre are
      returned — no cross-centre leakage.
    - Ordering: `list_bookings_for_centre/1` returns newest-first
      (`inserted_at DESC`).
    - Binary-id overload: passing `centre.id` (string) produces the same
      result as passing the struct.
    - `get_booking_for_centre/2` returns `{:ok, booking}` when the
      reference belongs to the specified centre, and `{:error, :not_found}`
      for any unknown or cross-tenant reference.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  # ---------------------------------------------------------------------------
  # Shared setup — two approved centres, one exam, one slot per centre,
  # one candidate, one booking per centre.
  # ---------------------------------------------------------------------------

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bfc-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "BFC Admin",
        "role" => "superadmin"
      })

    {:ok, centre_a} =
      ExamCentres.register_exam_centre(%{
        "email" => "bfc-ca-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BFC Centre A",
        "address_line_1" => "1 High St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, centre_a} = ExamCentres.approve(centre_a, admin)

    {:ok, centre_b} =
      ExamCentres.register_exam_centre(%{
        "email" => "bfc-cb-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BFC Centre B",
        "address_line_1" => "2 Low St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre_b} = ExamCentres.approve(centre_b, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "BFC Exam",
          "code" => "BFC-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4_500
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
        "email" => "bfc-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "BFC",
        "last_name" => "Candidate"
      })

    # Start GenServers so the booking pipeline's reserve step can succeed.
    {:ok, _pid_a} = Centres.start_centre(centre_a.id)
    {:ok, _pid_b} = Centres.start_centre(centre_b.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre_a.id)
      _ = Centres.stop_centre(centre_b.id)
    end)

    {:ok, booking_a} = Bookings.create_booking(candidate, slot_a)
    {:ok, booking_b} = Bookings.create_booking(candidate, slot_b)

    %{
      admin: admin,
      centre_a: centre_a,
      centre_b: centre_b,
      exam: exam,
      slot_a: slot_a,
      slot_b: slot_b,
      candidate: candidate,
      booking_a: booking_a,
      booking_b: booking_b
    }
  end

  # ---------------------------------------------------------------------------
  # list_bookings_for_centre/1 — struct overload
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/1 (struct)" do
    test "returns only the bookings belonging to centre_a", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_a)

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_a.reference in refs
      refute ctx.booking_b.reference in refs
    end

    test "returns only the bookings belonging to centre_b", ctx do
      bookings = Bookings.list_bookings_for_centre(ctx.centre_b)

      refs = Enum.map(bookings, & &1.reference)
      assert ctx.booking_b.reference in refs
      refute ctx.booking_a.reference in refs
    end
  end

  # ---------------------------------------------------------------------------
  # list_bookings_for_centre/1 — binary id overload
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/1 (binary id)" do
    test "binary id overload returns the same list as the struct overload", ctx do
      via_struct = Bookings.list_bookings_for_centre(ctx.centre_a)
      via_id = Bookings.list_bookings_for_centre(ctx.centre_a.id)

      assert Enum.map(via_struct, & &1.id) == Enum.map(via_id, & &1.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Ordering — newest first
  # ---------------------------------------------------------------------------

  describe "list_bookings_for_centre/1 ordering" do
    test "returns bookings newest-first when a centre has multiple bookings", ctx do
      # Create a second candidate + slot at centre_a so we can get two
      # separate bookings with different inserted_at values.
      {:ok, candidate2} =
        Candidates.register_candidate(%{
          "email" => "bfc-cand2-#{System.unique_integer([:positive])}@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Second",
          "last_name" => "Candidate"
        })

      future = DateTime.utc_now() |> DateTime.add(14, :day)

      {:ok, slot_a2} =
        Slots.create_slot(ctx.centre_a, %{
          "exam_id" => ctx.exam.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 3600, :second),
          "capacity" => 10
        })

      {:ok, pid_a} = Centres.whereis(ctx.centre_a.id)
      :ok = Centres.add_slot(pid_a, slot_a2)

      {:ok, booking_a2} = Bookings.create_booking(candidate2, slot_a2)

      bookings = Bookings.list_bookings_for_centre(ctx.centre_a)

      assert length(bookings) == 2

      # Newest booking (booking_a2, inserted after booking_a) comes first.
      [first, second] = bookings
      assert first.id == booking_a2.id
      assert second.id == ctx.booking_a.id

      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
    end
  end

  # ---------------------------------------------------------------------------
  # get_booking_for_centre/2
  # ---------------------------------------------------------------------------

  describe "get_booking_for_centre/2" do
    test "returns {:ok, booking} when the reference belongs to the centre", ctx do
      assert {:ok, found} =
               Bookings.get_booking_for_centre(ctx.centre_a, ctx.booking_a.reference)

      assert found.id == ctx.booking_a.id
    end

    test "returns {:error, :not_found} when the reference belongs to a different centre",
         ctx do
      # booking_b.reference is valid but belongs to centre_b, not centre_a.
      assert {:error, :not_found} =
               Bookings.get_booking_for_centre(ctx.centre_a, ctx.booking_b.reference)
    end

    test "returns {:error, :not_found} for an entirely unknown reference", ctx do
      assert {:error, :not_found} =
               Bookings.get_booking_for_centre(ctx.centre_a, "GV-NOT-EXIST")
    end
  end
end
