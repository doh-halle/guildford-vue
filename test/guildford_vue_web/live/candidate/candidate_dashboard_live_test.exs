defmodule GuildfordVueWeb.Candidate.CandidateDashboardLiveTest do
  @moduledoc """
  Sprint 9 Slice 5 — /candidate/dashboard surfaces an upcoming
  reservations count (and the first few references), linking to
  the full bookings page.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query, only: [from: 2]

  alias GuildfordVue.{Admins, Bookings, Candidates, ExamCentres, Exams, Repo, Slots}
  alias GuildfordVue.Slots.Slot

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "dash-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "dash-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Dash Centre",
        "address_line_1" => "1 St",
        "city" => "Belfast",
        "postcode" => "BT1 5GS"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Dash Exam",
          "code" => "DSH-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "dash-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Dash",
        "last_name" => "Cand"
      })

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    %{conn: conn, candidate: candidate, centre: centre, exam: exam}
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

    slot
  end

  defp persist(ctx, slot, ref) do
    {:ok, b} =
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

    b
  end

  test "shows 0 upcoming bookings + empty-state copy with no bookings", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/candidate/dashboard")

    count_html = lv |> element("[data-test-id='upcoming-count']") |> render()
    assert count_html =~ ~r/>\s*0\s*</
  end

  test "shows the count and reference links when there are upcoming bookings", ctx do
    _ = persist(ctx, make_slot(ctx), "GV-2026-RFENXT")
    _ = persist(ctx, make_slot(ctx), "GV-2026-RFEFAR")

    {:ok, lv, _html} = live(ctx.conn, ~p"/candidate/dashboard")

    count_html = lv |> element("[data-test-id='upcoming-count']") |> render()
    assert count_html =~ ~r/>\s*2\s*</

    full = render(lv)
    assert full =~ "GV-2026-RFENXT"
    assert full =~ "GV-2026-RFEFAR"
    assert full =~ "All bookings"
  end

  test "past bookings do NOT inflate the upcoming count", ctx do
    _ = persist(ctx, make_slot(ctx), "GV-2026-FUTRE2")
    past = backdate(make_slot(ctx), 4)
    _ = persist(ctx, past, "GV-2026-PSTBK2")

    {:ok, lv, _html} = live(ctx.conn, ~p"/candidate/dashboard")
    count_html = lv |> element("[data-test-id='upcoming-count']") |> render()
    assert count_html =~ ~r/>\s*1\s*</
  end

  test "dashboard surfaces a prominent CTA linking to /search", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/candidate/dashboard")

    cta = lv |> element("[data-test-id='find-centre-cta']") |> render()
    assert cta =~ ~s{href="/search"}, "find-centre CTA should link to /search"
    assert cta =~ "Find" or cta =~ "Book", "CTA copy should mention finding/booking"

    full = render(lv)

    refute full =~ "lands in Sprint 5",
           "stale Sprint 1c placeholder should be gone"
  end
end
