defmodule GuildfordVue.PaymentsTest do
  @moduledoc """
  Sprint 8 Slice 1 — Payments context covering persistence.

  Slice 5 wires the pipeline; this slice pins the schema + insert
  behaviour so the booking pipeline has a stable interface to
  call.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Payments, Slots}
  alias GuildfordVue.Payments.Payment

  defp seed_booking do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "pay-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "pay-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Pay Centre",
        "address_line_1" => "1 St",
        "city" => "Leeds",
        "postcode" => "LS1 1UR"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Pay Exam",
          "code" => "PAY-#{System.unique_integer([:positive])}",
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
        "email" => "pay-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Pay",
        "last_name" => "Cand"
      })

    {:ok, booking} = Bookings.create_booking(candidate, slot)
    booking
  end

  setup do
    %{booking: seed_booking()}
  end

  describe "record_payment/1" do
    test "persists a payment with the expected fields", %{booking: booking} do
      attrs = %{
        booking_id: booking.id,
        provider: "visa",
        masked_pan: "•••• •••• •••• 4242",
        amount_pence: 4500,
        status: "succeeded",
        processed_at: DateTime.utc_now()
      }

      assert {:ok, %Payment{} = p} = Payments.record_payment(attrs)
      assert p.provider == "visa"
      assert p.masked_pan == "•••• •••• •••• 4242"
      assert p.amount_pence == 4500
      assert p.status == "succeeded"
      refute p.declined_reason
    end

    test "validates status ADT" do
      attrs = %{
        booking_id: Ecto.UUID.generate(),
        provider: "visa",
        amount_pence: 4500,
        status: "bogus",
        processed_at: DateTime.utc_now()
      }

      assert {:error, cs} = Payments.record_payment(attrs)
      assert Enum.any?(errors_on(cs).status, &String.contains?(&1, "one of"))
    end

    test "validates provider ADT" do
      attrs = %{
        booking_id: Ecto.UUID.generate(),
        provider: "bitcoin",
        amount_pence: 4500,
        status: "succeeded",
        processed_at: DateTime.utc_now()
      }

      assert {:error, cs} = Payments.record_payment(attrs)
      assert Enum.any?(errors_on(cs).provider, &String.contains?(&1, "one of"))
    end

    test "rejects non-positive amount" do
      attrs = %{
        booking_id: Ecto.UUID.generate(),
        provider: "visa",
        amount_pence: 0,
        status: "succeeded",
        processed_at: DateTime.utc_now()
      }

      assert {:error, cs} = Payments.record_payment(attrs)
      assert "must be greater than 0" in errors_on(cs).amount_pence
    end

    test "rejects raw PAN in masked_pan field (defence-in-depth check)" do
      attrs = %{
        booking_id: Ecto.UUID.generate(),
        provider: "visa",
        masked_pan: "4242424242424242",
        amount_pence: 4500,
        status: "succeeded",
        processed_at: DateTime.utc_now()
      }

      assert {:error, cs} = Payments.record_payment(attrs)
      assert Enum.any?(errors_on(cs).masked_pan, &(&1 =~ "must be masked"))
    end
  end
end
