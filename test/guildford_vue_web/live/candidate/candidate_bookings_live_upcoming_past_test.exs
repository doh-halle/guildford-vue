defmodule GuildfordVueWeb.Candidate.CandidateBookingsLiveUpcomingPastTest do
  @moduledoc """
  Sprint 9 Slice 5 — /candidate/bookings index renders bookings in
  two sections: Upcoming (slot.starts_at >= now) and Past.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query, only: [from: 2]

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Slots}
  alias GuildfordVue.Slots.Slot

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "up-bks-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "up-bks-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Up Bks Centre",
        "address_line_1" => "1 St",
        "city" => "Cardiff",
        "postcode" => "CF10 1EP"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Slice5 Exam",
          "code" => "S5-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "up-bks-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Up",
        "last_name" => "Cand"
      })

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    %{conn: conn, admin: admin, centre: centre, exam: exam, candidate: candidate}
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
      GuildfordVue.Repo.update_all(
        from(s in Slot, where: s.id == ^slot.id),
        set: [
          starts_at: past,
          ends_at: DateTime.add(past, 60 * 60, :second)
        ]
      )

    Slots.get_slot!(slot.id)
  end

  defp persist(ctx, slot, ref) do
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

  test "renders Upcoming + Past headings with the right booking in each", ctx do
    future_slot = make_slot(ctx)
    past_slot = make_slot(ctx) |> backdate(3)

    _future = persist(ctx, future_slot, "GV-2026-FXTRSV")
    _past = persist(ctx, past_slot, "GV-2026-PSTBKD")

    {:ok, _lv, html} = live(ctx.conn, ~p"/candidate/bookings")

    assert html =~ "Upcoming"
    assert html =~ "Past"
    assert html =~ "GV-2026-FXTRSV"
    assert html =~ "GV-2026-PSTBKD"

    # Sanity: the Upcoming section appears before Past in markup
    upcoming_idx = :binary.match(html, "Upcoming") |> elem(0)
    past_idx = :binary.match(html, "Past") |> elem(0)
    assert upcoming_idx < past_idx

    # And the future booking appears before the past one (sectioned correctly).
    future_idx = :binary.match(html, "GV-2026-FXTRSV") |> elem(0)
    past_ref_idx = :binary.match(html, "GV-2026-PSTBKD") |> elem(0)
    assert future_idx < past_ref_idx
  end

  test "empty Upcoming with non-empty Past says so (no false empty-state)", ctx do
    past_slot = make_slot(ctx) |> backdate(5)
    _ = persist(ctx, past_slot, "GV-2026-XNLYPS")

    {:ok, _lv, html} = live(ctx.conn, ~p"/candidate/bookings")

    assert html =~ "No upcoming reservations"
    assert html =~ "GV-2026-XNLYPS"
    refute html =~ "haven&#39;t booked"
    refute html =~ "haven't booked"
  end

  test "empty Upcoming and empty Past shows the global empty state", ctx do
    {:ok, _lv, html} = live(ctx.conn, ~p"/candidate/bookings")

    assert html =~ "haven&#39;t booked" or html =~ "haven't booked"
  end
end
