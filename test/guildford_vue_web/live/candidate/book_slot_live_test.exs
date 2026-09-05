defmodule GuildfordVueWeb.Candidate.BookSlotLiveTest do
  @moduledoc """
  Sprint 5 Slice 6 — auth-gated "Book this slot" entry point.

  The actual booking pipeline lands in Sprint 7. This slice's
  responsibilities are narrower:
    - Guests can't reach the page (require_authenticated_candidate)
    - The path is preserved across login (return_to)
    - Authenticated candidates see the slot details

  Also covers real-time slot availability via CentrePubSub
  (TDD stubs for the {:slot_changed, slot} handle_info wiring).
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Candidates, ExamCentres, Exams, Slots}
  alias GuildfordVue.Slots.Slot

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "book-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "book-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Book Centre",
        "address_line_1" => "1 St",
        "city" => "Bristol",
        "postcode" => "BS1 4DJ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Book Exam",
          "code" => "BK",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 5000
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

    %{conn: conn, centre: centre, exam: exam, slot: slot}
  end

  test "guest visit redirects to /candidate/login (return_to stashed)",
       %{slot: slot} do
    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})

    conn = get(conn, ~p"/book/#{slot.id}")

    assert redirected_to(conn) == ~p"/candidate/login"
    assert get_session(conn, :candidate_return_to) == "/book/#{slot.id}"
  end

  test "authenticated candidate sees the slot details",
       %{conn: conn, centre: c, exam: e, slot: slot} do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "book-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Cand",
        "last_name" => "X"
      })

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    {:ok, _lv, html} = live(conn, ~p"/book/#{slot.id}")

    assert html =~ c.name
    assert html =~ e.name
    # Sprint 8 Slice 4 replaced "Confirm booking" → "Continue to payment".
    assert html =~ "Continue to payment"

    # Sprint 11 Slice 3 — bottom-sheet treatment markers must be present
    # so the mobile breakpoint can pick up the rounded-top + fixed
    # positioning. The desktop sm: classes co-exist on the same element.
    assert html =~ "booking-sheet"
    assert html =~ "rounded-t-3xl"
  end

  test "unknown slot id 404s (or shows not-found)",
       %{conn: conn} do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "book-cand-404@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Cand",
        "last_name" => "X"
      })

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    bogus = Ecto.UUID.generate()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/book/#{bogus}")
    end
  end

  test "search LV's Book button targets /book/:slot_id (not a login URL)",
       %{conn: conn, centre: centre, slot: slot} do
    {:ok, lv, _html} = live(conn, ~p"/search?postcode=BS1+4DJ")

    # The redesigned search page shows cards — the Book link only appears
    # inside the slot modal after clicking the centre card.
    html =
      lv
      |> element("#centre-card-#{centre.id}")
      |> render_click()

    assert html =~ "/book/#{slot.id}"
  end

  # ------------------------------------------------------------------
  # Real-time updates via CentrePubSub
  # ------------------------------------------------------------------

  describe "real-time updates via CentrePubSub" do
    # Each test in this describe block needs an authenticated candidate
    # and a mounted BookSlotLive. We reuse the module-level setup (which
    # builds the centre/exam/slot) and register a candidate on top.

    setup %{conn: conn, slot: slot} do
      {:ok, candidate} =
        Candidates.register_candidate(%{
          "email" => "book-pubsub-cand@example.com",
          "password" => "supersecret123!A",
          "first_name" => "PubSub",
          "last_name" => "Cand"
        })

      conn =
        init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

      %{conn: conn, slot: slot, candidate: candidate}
    end

    test "available_count updates when a {:slot_changed, slot} message arrives for the same slot id",
         %{conn: conn, slot: slot} do
      # Arrange — mount with the slot's initial count (5 of 5).
      # The factory setup creates capacity: 5, so available_count == 5.
      {:ok, lv, html} = live(conn, ~p"/book/#{slot.id}")

      assert html =~ "#{slot.available_count} of #{slot.capacity} seats remaining"

      # Act — simulate a PubSub broadcast that reduces availability to 2.
      updated_slot = %Slot{slot | available_count: 2}
      send(lv.pid, {:slot_changed, updated_slot})

      # Assert — the rendered HTML should reflect the new count.
      new_html = render(lv)

      assert new_html =~ "2 of #{slot.capacity} seats remaining",
             "expected updated available_count (2) to appear after :slot_changed broadcast"

      refute new_html =~ "#{slot.available_count} of #{slot.capacity} seats remaining",
             "stale available_count (#{slot.available_count}) should no longer be shown"
    end

    test "slot_changed for a DIFFERENT slot id is ignored",
         %{conn: conn, slot: slot} do
      # Arrange — mount with the original slot (available_count: 5 of 5).
      {:ok, lv, html} = live(conn, ~p"/book/#{slot.id}")

      assert html =~ "#{slot.available_count} of #{slot.capacity} seats remaining"

      # Act — broadcast a change for a completely different slot id.
      other_id = Ecto.UUID.generate()

      other_slot = %Slot{
        id: other_id,
        exam_centre_id: slot.exam_centre_id,
        exam_id: slot.exam_id,
        starts_at: slot.starts_at,
        ends_at: slot.ends_at,
        capacity: slot.capacity,
        available_count: 0,
        status: "full"
      }

      send(lv.pid, {:slot_changed, other_slot})

      # Assert — the LV should ignore the message and still show the
      # original available_count for the mounted slot.
      new_html = render(lv)

      assert new_html =~ "#{slot.available_count} of #{slot.capacity} seats remaining",
             "original count should be unchanged after :slot_changed for a different slot id"
    end
  end
end
