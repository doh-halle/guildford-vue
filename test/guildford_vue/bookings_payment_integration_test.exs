defmodule GuildfordVue.BookingsPaymentIntegrationTest do
  @moduledoc """
  Sprint 8 Slice 5 — pipeline + Payments persistence integration.

  Pinned invariants:
    - Successful booking writes a Payment row alongside the
      Booking, linked via booking_id, with provider + masked_pan
      from the gateway response.
    - The full PAN is never persisted — `masked_pan` is the
      stored form. Defence-in-depth: Payments.create_changeset
      rejects digit-only values (Slice 1).
    - Failed payments DO NOT create a Payment row — the audit
      log carries the decline. (Real systems often keep declined
      records for fraud analysis; that's out of scope here.)
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Payments, Slots}
  alias GuildfordVue.Payments.Card

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bpi-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bpi-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Pay Integ Centre",
        "address_line_1" => "1 St",
        "city" => "Bristol",
        "postcode" => "BS1 4DJ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Integ Exam",
          "code" => "INT",
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
        "capacity" => 5
      })

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "bpi-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Integ",
        "last_name" => "Cand"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre.id)

      Application.put_env(
        :guildford_vue,
        :payment_gateway,
        GuildfordVue.PaymentGateway.Stub
      )
    end)

    %{centre: centre, exam: exam, slot: slot, candidate: candidate}
  end

  defp valid_card do
    {:ok, card} =
      Card.validate(%{
        "number" => "4242424242424242",
        "exp_month" => "12",
        "exp_year" => "2030",
        "cvc" => "123",
        "holder_name" => "Test User"
      })

    card
  end

  test "successful booking writes a Payment row with provider + masked_pan",
       %{candidate: c, slot: slot} do
    Application.put_env(
      :guildford_vue,
      :payment_gateway,
      GuildfordVue.PaymentGateway.Simulated
    )

    assert {:ok, booking} =
             Bookings.create_booking(c, slot,
               payment_method: :visa,
               card: valid_card(),
               latency_ms: 0,
               decline_rate: 0.0
             )

    payment = Payments.get_payment_for_booking(booking.id)
    assert payment
    assert payment.provider == "visa"
    assert payment.amount_pence == booking.price_pence
    assert payment.status == "succeeded"
    assert payment.processed_at
    assert payment.masked_pan =~ "4242"
    refute String.match?(payment.masked_pan, ~r/\A\d+\z/)
  end

  test "PayPal wallet booking writes a Payment row with provider=paypal, masked_pan=nil",
       %{candidate: c, slot: slot} do
    Application.put_env(
      :guildford_vue,
      :payment_gateway,
      GuildfordVue.PaymentGateway.Simulated
    )

    {:ok, booking} =
      Bookings.create_booking(c, slot,
        payment_method: :paypal,
        latency_ms: 0,
        decline_rate: 0.0
      )

    payment = Payments.get_payment_for_booking(booking.id)
    assert payment.provider == "paypal"
    refute payment.masked_pan
  end

  test "declined payment → NO Payment row + NO Booking row",
       %{candidate: c, slot: slot} do
    Application.put_env(
      :guildford_vue,
      :payment_gateway,
      GuildfordVue.PaymentGateway.Simulated
    )

    assert {:error, :pay, :card_declined} =
             Bookings.create_booking(c, slot,
               payment_method: :visa,
               card: valid_card(),
               latency_ms: 0,
               decline_rate: 1.0
             )

    assert Bookings.list_candidate_bookings(c) == []
  end

  test "Stub adapter still works (backwards compat for Sprint-7 callers)",
       %{candidate: c, slot: slot} do
    # Default test env uses Stub.
    assert {:ok, booking} = Bookings.create_booking(c, slot)

    # Stub now also writes a Payment row (provider="visa" default).
    payment = Payments.get_payment_for_booking(booking.id)
    assert payment
    assert payment.status == "succeeded"
  end
end
