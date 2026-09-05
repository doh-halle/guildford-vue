defmodule GuildfordVue.BookingsRefundTest do
  @moduledoc """
  Sprint 10 Slice 4 — admin refund flow.

  `Bookings.refund/2` flips status to "refunded", releases the
  slot back to the centre, records a refunded Payment row, and
  writes a `booking_refunded` audit entry.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{
    Admins,
    AuditLog,
    Bookings,
    Candidates,
    Centres,
    ExamCentres,
    Exams,
    Slots
  }

  alias GuildfordVue.Payments.Payment

  import Ecto.Query, only: [from: 2]

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "rf-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "rf-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Refund Centre",
        "address_line_1" => "1 St",
        "city" => "Cardiff",
        "postcode" => "CF1 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Refund Exam",
          "code" => "RF-#{System.unique_integer([:positive])}",
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
        "email" => "rf-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "RF",
        "last_name" => "Cand"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)
    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    {:ok, booking} = Bookings.create_booking(candidate, slot)

    %{
      admin: admin,
      candidate: candidate,
      booking: booking,
      slot: slot,
      exam: exam,
      centre: centre
    }
  end

  describe "refund/2" do
    test "flips status to refunded and stamps cancelled_at", ctx do
      assert {:ok, refunded} = Bookings.refund(ctx.booking, ctx.admin)
      assert refunded.status == "refunded"
      assert refunded.cancelled_at
    end

    test "records a refunded Payment row referencing the booking", ctx do
      {:ok, refunded} = Bookings.refund(ctx.booking, ctx.admin)

      refund_payments =
        Repo.all(
          from p in Payment,
            where: p.booking_id == ^refunded.id and p.status == "refunded"
        )

      assert [%Payment{} = p] = refund_payments
      assert p.amount_pence == ctx.booking.price_pence
    end

    test "writes a booking_refunded audit entry with the admin actor", ctx do
      {:ok, _} = Bookings.refund(ctx.booking, ctx.admin)

      events = AuditLog.list(event_type: "booking_refunded", limit: 5)
      assert Enum.any?(events, fn e -> e.actor_id == ctx.admin.id end)
    end

    test "is idempotent — second call returns {:error, :already_refunded}", ctx do
      {:ok, refunded} = Bookings.refund(ctx.booking, ctx.admin)
      assert {:error, :already_refunded} = Bookings.refund(refunded, ctx.admin)
    end

    test "releases the slot back to availability", ctx do
      {:ok, _pid} = Centres.ensure_started(ctx.centre.id)
      before_refund = Slots.get_slot!(ctx.slot.id)

      {:ok, _} = Bookings.refund(ctx.booking, ctx.admin)

      after_refund = Slots.get_slot!(ctx.slot.id)
      assert after_refund.available_count >= before_refund.available_count
    end
  end
end
