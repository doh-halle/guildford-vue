defmodule GuildfordVue.BookingsUpcomingPastTest do
  @moduledoc """
  Sprint 9 Slice 5 — upcoming/past segmentation of a candidate's
  bookings. The dashboard + bookings page need the split, and the
  Bookings context owns the SQL that joins slot.starts_at.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Slots}
  alias GuildfordVue.Slots.Slot

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "up-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "up-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Upcoming Centre",
        "address_line_1" => "1 St",
        "city" => "York",
        "postcode" => "YO1 8XT"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Up Exam",
          "code" => "UP-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "up-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Upcoming",
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

  defp backdate(slot, days_ago) do
    past = DateTime.utc_now() |> DateTime.add(-days_ago * 86_400, :second)

    {1, _} =
      Repo.update_all(
        from(s in Slot, where: s.id == ^slot.id),
        set: [
          starts_at: past,
          ends_at: DateTime.add(past, 60 * 60, :second)
        ]
      )

    Slots.get_slot!(slot.id)
  end

  defp persist_booking(ctx, slot, ref) do
    {:ok, booking} =
      Bookings.persist_booking(%{
        candidate_id: ctx.candidate.id,
        slot_id: slot.id,
        exam_id: ctx.exam.id,
        exam_centre_id: ctx.centre.id,
        reference: ref,
        status: "confirmed",
        price_pence: ctx.exam.price_pence,
        paid_at: DateTime.utc_now(),
        payment_token: "tok_stub",
        pdf_url: nil
      })

    booking
  end

  describe "list_upcoming_candidate_bookings/1" do
    test "returns only bookings whose slot starts_at >= now", ctx do
      future_slot = make_slot(ctx)
      past_slot = make_slot(ctx) |> backdate(2)

      _future_booking = persist_booking(ctx, future_slot, "GV-2026-FTRESV")
      _past_booking = persist_booking(ctx, past_slot, "GV-2026-PASTPS")

      assert [%{reference: "GV-2026-FTRESV"}] =
               Bookings.list_upcoming_candidate_bookings(ctx.candidate)
    end

    test "returns [] when the candidate has no future bookings", ctx do
      past_slot = make_slot(ctx) |> backdate(2)
      _ = persist_booking(ctx, past_slot, "GV-2026-XNLYPA")

      assert Bookings.list_upcoming_candidate_bookings(ctx.candidate) == []
    end

    test "only returns the signed-in candidate's bookings", ctx do
      {:ok, other} =
        Candidates.register_candidate(%{
          "email" => "up-other-#{System.unique_integer([:positive])}@example.com",
          "password" => "supersecret123!A",
          "first_name" => "Other",
          "last_name" => "C"
        })

      future_slot = make_slot(ctx)

      _mine = persist_booking(ctx, future_slot, "GV-2026-MNEXXX")

      _theirs =
        Bookings.persist_booking(%{
          candidate_id: other.id,
          slot_id: future_slot.id,
          exam_id: ctx.exam.id,
          exam_centre_id: ctx.centre.id,
          reference: "GV-2026-THERXY",
          status: "confirmed",
          price_pence: ctx.exam.price_pence,
          paid_at: DateTime.utc_now(),
          payment_token: "tok_stub",
          pdf_url: nil
        })

      refs =
        ctx.candidate
        |> Bookings.list_upcoming_candidate_bookings()
        |> Enum.map(& &1.reference)

      assert "GV-2026-MNEXXX" in refs
      refute "GV-2026-THERXY" in refs
    end

    test "orders soonest-first (ascending starts_at)", ctx do
      slot_far = make_slot(ctx)

      # Make a closer-future slot by rewriting starts_at to +1 day
      slot_near = make_slot(ctx)

      one_day = DateTime.utc_now() |> DateTime.add(86_400, :second)

      {1, _} =
        Repo.update_all(
          from(s in Slot, where: s.id == ^slot_near.id),
          set: [
            starts_at: one_day,
            ends_at: DateTime.add(one_day, 60 * 60, :second)
          ]
        )

      _ = persist_booking(ctx, slot_far, "GV-2026-FARFAR")
      _ = persist_booking(ctx, slot_near, "GV-2026-NEARNR")

      refs =
        ctx.candidate
        |> Bookings.list_upcoming_candidate_bookings()
        |> Enum.map(& &1.reference)

      assert refs == ["GV-2026-NEARNR", "GV-2026-FARFAR"]
    end
  end

  describe "list_past_candidate_bookings/1" do
    test "returns only bookings whose slot starts_at < now", ctx do
      future_slot = make_slot(ctx)
      past_slot = make_slot(ctx) |> backdate(2)

      _ = persist_booking(ctx, future_slot, "GV-2026-FTTRX2")
      _ = persist_booking(ctx, past_slot, "GV-2026-PASTBK")

      refs =
        ctx.candidate
        |> Bookings.list_past_candidate_bookings()
        |> Enum.map(& &1.reference)

      assert refs == ["GV-2026-PASTBK"]
    end

    test "orders most-recent-first (descending starts_at)", ctx do
      slot_old = make_slot(ctx) |> backdate(10)
      slot_recent = make_slot(ctx) |> backdate(1)

      _ = persist_booking(ctx, slot_old, "GV-2026-XYDXYD")
      _ = persist_booking(ctx, slot_recent, "GV-2026-RECNTX")

      refs =
        ctx.candidate
        |> Bookings.list_past_candidate_bookings()
        |> Enum.map(& &1.reference)

      assert refs == ["GV-2026-RECNTX", "GV-2026-XYDXYD"]
    end
  end
end
