defmodule GuildfordVue.BookingsTest do
  @moduledoc """
  Sprint 7 Slice 1 — Bookings context covering the data layer:
  schema + reference uniqueness + status ADT.

  The pipeline (`create_booking/3`) lands in Slice 3; this file
  focuses on persistence-only behaviours so the changeset rules
  are pinned without depending on payment / PDF stubs.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Slots}
  alias GuildfordVue.Bookings.Booking

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bk-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bk-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Booking Centre",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Booking Exam",
          "code" => "BKE",
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
        "capacity" => 10
      })

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "bk-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Cand",
        "last_name" => "Last"
      })

    %{
      admin: admin,
      centre: centre,
      exam: exam,
      slot: slot,
      candidate: candidate
    }
  end

  describe "persist_booking/1" do
    test "persists a booking with the expected fields", ctx do
      attrs = %{
        candidate_id: ctx.candidate.id,
        slot_id: ctx.slot.id,
        exam_id: ctx.exam.id,
        exam_centre_id: ctx.centre.id,
        reference: "GV-2026-AB34CD",
        status: "confirmed",
        price_pence: ctx.exam.price_pence,
        paid_at: DateTime.utc_now(),
        payment_token: "tok_stub",
        pdf_url: nil
      }

      assert {:ok, %Booking{} = b} = Bookings.persist_booking(attrs)
      assert b.reference == "GV-2026-AB34CD"
      assert b.candidate_id == ctx.candidate.id
      assert b.price_pence == ctx.exam.price_pence
      assert b.status == "confirmed"
    end

    test "reference is unique", ctx do
      attrs = booking_attrs(ctx, "GV-2026-DUP2CT")

      {:ok, _} = Bookings.persist_booking(attrs)
      assert {:error, cs} = Bookings.persist_booking(attrs)
      assert "has already been taken" in errors_on(cs).reference
    end

    test "invalid status rejected", ctx do
      attrs = ctx |> booking_attrs("GV-2026-BADSTA") |> Map.put(:status, "bogus")

      assert {:error, cs} = Bookings.persist_booking(attrs)
      assert Enum.any?(errors_on(cs).status, &String.contains?(&1, "one of"))
    end

    test "negative price_pence rejected", ctx do
      attrs = ctx |> booking_attrs("GV-2026-NEGPRC") |> Map.put(:price_pence, -1)

      assert {:error, cs} = Bookings.persist_booking(attrs)
      assert "must be greater than or equal to 0" in errors_on(cs).price_pence
    end
  end

  describe "get_booking_by_reference/1" do
    test "round-trips the booking", ctx do
      {:ok, b} = Bookings.persist_booking(booking_attrs(ctx, "GV-2026-GETXY3"))
      reloaded = Bookings.get_booking_by_reference("GV-2026-GETXY3")
      assert reloaded.id == b.id
    end

    test "nil for unknown reference" do
      refute Bookings.get_booking_by_reference("GV-2026-NOPE99")
    end
  end

  describe "list_candidate_bookings/1" do
    test "lists newest-first for the candidate, hides other candidates' bookings",
         ctx do
      {:ok, b1} = Bookings.persist_booking(booking_attrs(ctx, "GV-2026-AAAAAA"))
      {:ok, b2} = Bookings.persist_booking(booking_attrs(ctx, "GV-2026-BBBBBB"))

      {:ok, other_cand} =
        Candidates.register_candidate(%{
          "email" => "bk-other@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Other",
          "last_name" => "X"
        })

      {:ok, _other_booking} =
        Bookings.persist_booking(%{
          booking_attrs(ctx, "GV-2026-CCCCCC")
          | candidate_id: other_cand.id
        })

      ids = ctx.candidate |> Bookings.list_candidate_bookings() |> Enum.map(& &1.id)
      assert b2.id in ids
      assert b1.id in ids
      assert length(ids) == 2
    end
  end

  defp booking_attrs(ctx, reference) do
    %{
      candidate_id: ctx.candidate.id,
      slot_id: ctx.slot.id,
      exam_id: ctx.exam.id,
      exam_centre_id: ctx.centre.id,
      reference: reference,
      status: "confirmed",
      price_pence: ctx.exam.price_pence,
      paid_at: DateTime.utc_now(),
      payment_token: "tok_stub",
      pdf_url: nil
    }
  end
end
