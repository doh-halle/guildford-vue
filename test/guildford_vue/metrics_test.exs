defmodule GuildfordVue.MetricsTest do
  @moduledoc """
  Sprint 10 Slice 1 — operational metrics. Counts the
  bookings landed today / this week (UTC, Mon-start) /
  this month and totals revenue from `payments.amount_pence`
  where the payment succeeded.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Metrics, Payments, Slots}
  alias GuildfordVue.Bookings.Booking
  alias GuildfordVue.Payments.Payment

  import Ecto.Query, only: [from: 2]

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "met-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "met-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Metrics Centre",
        "address_line_1" => "1 St",
        "city" => "Leeds",
        "postcode" => "LS1 1UR"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Metrics Exam",
          "code" => "MET-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "met-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Met",
        "last_name" => "Cand"
      })

    %{admin: admin, centre: centre, exam: exam, candidate: candidate}
  end

  defp make_slot(ctx) do
    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(ctx.centre, %{
        "exam_id" => ctx.exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => 5
      })

    slot
  end

  defp persist_booking(ctx, slot, ref, opts \\ []) do
    {:ok, booking} =
      Bookings.persist_booking(%{
        candidate_id: ctx.candidate.id,
        slot_id: slot.id,
        exam_id: ctx.exam.id,
        exam_centre_id: ctx.centre.id,
        reference: ref,
        status: Keyword.get(opts, :status, "confirmed"),
        price_pence: Keyword.get(opts, :price_pence, ctx.exam.price_pence),
        paid_at: DateTime.utc_now(),
        payment_token: "tok_stub",
        pdf_url: nil
      })

    case Keyword.get(opts, :inserted_at) do
      nil ->
        booking

      %DateTime{} = at ->
        {1, _} =
          Repo.update_all(
            from(b in Booking, where: b.id == ^booking.id),
            set: [inserted_at: at]
          )

        Bookings.get_booking!(booking.id)
    end
  end

  defp record_payment(booking, opts) do
    {:ok, payment} =
      Payments.record_payment(%{
        booking_id: booking.id,
        provider: "visa",
        masked_pan: "•••• •••• •••• 4242",
        amount_pence: Keyword.get(opts, :amount_pence, booking.price_pence),
        status: Keyword.get(opts, :status, "succeeded"),
        processed_at: DateTime.utc_now()
      })

    case Keyword.get(opts, :processed_at) do
      nil ->
        payment

      %DateTime{} = at ->
        {1, _} =
          Repo.update_all(
            from(p in Payment, where: p.id == ^payment.id),
            set: [processed_at: at]
          )

        Repo.reload!(payment)
    end
  end

  describe "count_bookings_today/0" do
    test "counts only bookings whose inserted_at is today (UTC)", ctx do
      slot = make_slot(ctx)
      _today = persist_booking(ctx, slot, "GV-2026-TDAYAX")

      yesterday = DateTime.utc_now() |> DateTime.add(-26 * 60 * 60, :second)
      _y = persist_booking(ctx, slot, "GV-2026-YESTRD", inserted_at: yesterday)

      assert Metrics.count_bookings_today() == 1
    end
  end

  describe "count_bookings_this_week/0" do
    test "counts bookings from Monday 00:00 UTC of the current week", ctx do
      slot = make_slot(ctx)
      _now = persist_booking(ctx, slot, "GV-2026-WKNXWA")

      ten_days_ago = DateTime.utc_now() |> DateTime.add(-10 * 86_400, :second)
      _old = persist_booking(ctx, slot, "GV-2026-WKTNAG", inserted_at: ten_days_ago)

      assert Metrics.count_bookings_this_week() >= 1
      assert Metrics.count_bookings_this_week() < 2
    end
  end

  describe "count_bookings_this_month/0" do
    test "counts bookings from the 1st of the current month, UTC", ctx do
      slot = make_slot(ctx)
      _now = persist_booking(ctx, slot, "GV-2026-MTNXWA")

      forty_days_ago = DateTime.utc_now() |> DateTime.add(-40 * 86_400, :second)
      _old = persist_booking(ctx, slot, "GV-2026-MT42AG", inserted_at: forty_days_ago)

      assert Metrics.count_bookings_this_month() == 1
    end
  end

  describe "sum_revenue_pence/0" do
    test "sums amount_pence of succeeded payments only", ctx do
      slot = make_slot(ctx)
      b1 = persist_booking(ctx, slot, "GV-2026-REVAAA")
      _ = record_payment(b1, amount_pence: 4500, status: "succeeded")

      b2 = persist_booking(ctx, slot, "GV-2026-REVBBB")
      _ = record_payment(b2, amount_pence: 6000, status: "succeeded")

      b3 = persist_booking(ctx, slot, "GV-2026-REVDEC")
      _ = record_payment(b3, amount_pence: 9999, status: "refunded")

      assert Metrics.sum_revenue_pence() == 10_500
    end

    test "returns 0 when no successful payments exist" do
      assert Metrics.sum_revenue_pence() == 0
    end
  end

  describe "snapshot/0" do
    test "bundles all the metrics into a single map", ctx do
      slot = make_slot(ctx)
      b = persist_booking(ctx, slot, "GV-2026-SNAPXY")
      _ = record_payment(b, amount_pence: 7700, status: "succeeded")

      snap = Metrics.snapshot()

      assert is_integer(snap.bookings_today)
      assert is_integer(snap.bookings_this_week)
      assert is_integer(snap.bookings_this_month)
      assert snap.revenue_pence == 7700
      assert is_integer(snap.candidates_total)
      assert is_integer(snap.centres_approved)
      assert is_integer(snap.centres_pending)
    end
  end
end
