defmodule GuildfordVue.BookingsCancelTest do
  @moduledoc """
  Sprint 7 Slice 5 — cancellation reverses the pipeline. Used by
  the property test in `bookings_property_test.exs` to demonstrate
  the PRD §4.7 "cancellation + rebooking restores original state"
  invariant.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, AuditLog, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bc-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bc-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Cancel Centre",
        "address_line_1" => "1 St",
        "city" => "Leeds",
        "postcode" => "LS1 1UR"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Cancel Exam",
          "code" => "CNCL",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 2_500
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
        "email" => "bc-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Bc",
        "last_name" => "Cand"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    %{centre: centre, exam: exam, slot: slot, candidate: candidate}
  end

  describe "cancel_booking/2" do
    test "flips status, releases the seat, writes audit",
         %{candidate: c, slot: slot} do
      {:ok, booking} = Bookings.create_booking(c, slot)
      before_avail = Slots.get_slot!(slot.id).available_count

      assert {:ok, cancelled} = Bookings.cancel_booking(booking, c)
      assert cancelled.status == "cancelled"
      assert cancelled.cancelled_at

      assert Slots.get_slot!(slot.id).available_count == before_avail + 1

      assert [_] = AuditLog.list(event_type: "booking_cancelled", aggregate_id: booking.id)
    end

    test "double-cancel is a no-op error",
         %{candidate: c, slot: slot} do
      {:ok, booking} = Bookings.create_booking(c, slot)
      {:ok, cancelled} = Bookings.cancel_booking(booking, c)
      assert {:error, :already_cancelled} = Bookings.cancel_booking(cancelled, c)
    end
  end
end
