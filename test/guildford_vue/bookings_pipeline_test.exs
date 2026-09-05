defmodule GuildfordVue.BookingsPipelineTest do
  @moduledoc """
  Sprint 7 Slice 3 — the railway-oriented booking pipeline. Pinned
  invariants:

    - Happy path: validate → reserve → pay → persist → pdf → email
      → audit. All return tagged tuples; the whole pipeline is a
      `with` expression so a single failure short-circuits.
    - Reservation is released if any later stage fails (payment
      decline being the headline case).
    - Pipeline returns `{:error, stage, reason}` carrying which
      stage failed — the LV maps stage names to UX-friendly flash
      messages.
  """
  use GuildfordVue.DataCase, async: false
  import Swoosh.TestAssertions

  alias GuildfordVue.{
    Admins,
    AuditLog,
    Bookings,
    Candidates,
    Centres,
    ExamCentres,
    Exams,
    PaymentGateway,
    Slots
  }

  alias GuildfordVue.Bookings.Booking
  alias GuildfordVue.Bookings.BookingReference
  alias GuildfordVue.Centres.PubSub, as: CentrePubSub

  # Receive-based predicate matcher — flushes the Swoosh test inbox
  # until it finds an email satisfying `match_fun?`. Tolerates other
  # emails (centre-approval, password-reset) in the mailbox.
  defp assert_email_received_matching(match_fun?, timeout \\ 500) do
    receive do
      {:email, email} ->
        if match_fun?.(email),
          do: email,
          else: assert_email_received_matching(match_fun?, timeout)
    after
      timeout ->
        flunk("no email satisfying the predicate within #{timeout}ms")
    end
  end

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "pl-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "pl-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Pipeline Centre",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Pipeline Exam",
          "code" => "PIPE",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4_500
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
        "capacity" => 3
      })

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "pl-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Pipeline",
        "last_name" => "Cand"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    on_exit(fn ->
      # Default the adapter back to Stub between tests that swap it.
      Application.put_env(:guildford_vue, :payment_gateway, GuildfordVue.PaymentGateway.Stub)
    end)

    %{centre: centre, exam: exam, slot: slot, candidate: candidate}
  end

  describe "happy path" do
    test "validate → reserve → pay → persist → pdf → email → audit",
         %{candidate: c, slot: slot, exam: e, centre: centre} do
      assert {:ok, %Booking{} = booking} = Bookings.create_booking(c, slot)

      assert booking.candidate_id == c.id
      assert booking.slot_id == slot.id
      assert booking.exam_id == e.id
      assert booking.exam_centre_id == centre.id
      assert booking.price_pence == e.price_pence
      assert booking.status == "confirmed"
      assert is_binary(booking.reference)
      assert is_binary(booking.payment_token)
      assert is_binary(booking.pdf_url)
      assert booking.paid_at

      # Slot inventory decremented.
      reloaded_slot = Slots.get_slot!(slot.id)
      assert reloaded_slot.available_count == slot.capacity - 1

      # Audit event written.
      [event] = AuditLog.list(event_type: "booking_created", aggregate_id: booking.id)
      assert event.actor_id == c.id
      assert event.actor_type == "candidate"
      assert event.payload["reference"] == booking.reference

      # Confirmation email sent. The Swoosh test mailbox also holds
      # the centre-approval email from setup, so we use a receive +
      # pattern-match loop to find the booking-confirmation email
      # regardless of arrival order.
      ref = booking.reference

      assert_email_received_matching(fn email ->
        email.subject == "Booking confirmed — #{ref}" and
          email.text_body =~ ref
      end)
    end

    test "broadcast on the centre's PubSub topic", %{candidate: c, slot: slot, centre: centre} do
      :ok = CentrePubSub.subscribe(centre.id)
      {:ok, _booking} = Bookings.create_booking(c, slot)

      assert_receive {:slot_changed, _updated}, 500
    end
  end

  describe "validation failures (pipeline doesn't reserve)" do
    test "cancelled slot → {:error, :validate, :slot_unbookable}",
         %{candidate: c, slot: slot, centre: centre} do
      {:ok, _} = Slots.cancel_slot(slot, centre)

      assert {:error, :validate, :slot_unbookable} =
               Bookings.create_booking(c, Slots.get_slot!(slot.id))

      assert Slots.get_slot!(slot.id).available_count == slot.capacity
    end

    test "past slot → {:error, :validate, :slot_in_past}",
         %{candidate: c, exam: e, centre: centre} do
      # Bypass the schema validation that rejects past starts_at by
      # backdating via raw query (simulating an in-progress slot).
      past = DateTime.utc_now() |> DateTime.add(-1, :hour)

      slot = %GuildfordVue.Slots.Slot{
        id: Ecto.UUID.generate(),
        starts_at: past,
        ends_at: DateTime.add(past, 60 * 60, :second),
        status: "open",
        available_count: 5,
        capacity: 5,
        exam_id: e.id,
        exam_centre_id: centre.id
      }

      assert {:error, :validate, :slot_in_past} = Bookings.create_booking(c, slot)
    end
  end

  describe "rollback semantics" do
    test "payment decline releases the reserved seat",
         %{candidate: c, slot: slot} do
      Application.put_env(
        :guildford_vue,
        :payment_gateway,
        GuildfordVue.PaymentGateway.Decline
      )

      before = Slots.get_slot!(slot.id).available_count

      assert {:error, :pay, :card_declined} = Bookings.create_booking(c, slot)

      after_avail = Slots.get_slot!(slot.id).available_count
      assert before == after_avail, "decline must release the seat"
    end

    test "no booking row is persisted when the pipeline fails before :persist",
         %{candidate: c, slot: slot} do
      Application.put_env(
        :guildford_vue,
        :payment_gateway,
        GuildfordVue.PaymentGateway.Decline
      )

      _ = Bookings.create_booking(c, slot)

      assert Bookings.list_candidate_bookings(c) == []
    end

    test "sold-out slot → {:error, :reserve, :sold_out}, no booking",
         %{candidate: c, slot: slot} do
      # Fill the slot first via direct CentreServer calls.
      {:ok, pid} = Centres.ensure_started(slot.exam_centre_id)
      for _ <- 1..slot.capacity, do: {:ok, _} = Centres.reserve_slot(pid, slot.id)

      assert {:error, :reserve, :sold_out} = Bookings.create_booking(c, Slots.get_slot!(slot.id))
      assert Bookings.list_candidate_bookings(c) == []
    end
  end

  describe "reference + uniqueness" do
    test "every booking gets a unique GV-YYYY-XXXXXX reference",
         %{candidate: c, exam: e, centre: centre} do
      # Two slots so we can book twice from this candidate.
      future = DateTime.utc_now() |> DateTime.add(8, :day)

      {:ok, slot2} =
        Slots.create_slot(centre, %{
          "exam_id" => e.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 3
        })

      {:ok, pid} = Centres.ensure_started(centre.id)
      :ok = Centres.add_slot(pid, slot2)

      {:ok, b1} = Bookings.create_booking(c, Slots.get_slot!(slot2.id))

      # First slot still has capacity.
      first_slot = ctx_slot(c, e, centre)
      {:ok, b2} = Bookings.create_booking(c, first_slot)

      assert b1.reference != b2.reference
      assert BookingReference.valid?(b1.reference)
      assert BookingReference.valid?(b2.reference)
    end
  end

  # The "first slot" from setup, fetched fresh.
  defp ctx_slot(_c, exam, centre) do
    [s | _] =
      centre
      |> Slots.list_centre_slots()
      |> Enum.filter(&(&1.exam_id == exam.id))
      |> Enum.sort_by(& &1.starts_at, DateTime)

    s
  end
end
