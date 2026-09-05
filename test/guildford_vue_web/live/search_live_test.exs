defmodule GuildfordVueWeb.SearchLiveTest do
  @moduledoc """
  Sprint 5 Slice 4 — public guest search at `/search`. No login
  required; the booking action gets auth-gated in Slice 6.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "srch-lv-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, london} =
      ExamCentres.register_exam_centre(%{
        "email" => "srch-lv-london@example.com",
        "password" => "supersecret123!A",
        "name" => "London LV",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, london} = ExamCentres.approve(london, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Search LV Exam",
          "code" => "SLV",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(london, [exam.id], london)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(london, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => 8
      })

    %{conn: conn, admin: admin, london: london, exam: exam, slot: slot}
  end

  test "renders the search form (no login required)", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/search")
    assert html =~ "Find an exam centre"
    assert html =~ "Postcode"
  end

  test "submitting a valid postcode shows matching centres + slots",
       %{conn: conn, london: l, exam: e} do
    {:ok, lv, _} = live(conn, ~p"/search")

    html =
      lv
      |> form("#centre-search-form", search: %{"postcode" => "SW1A 1AA"})
      |> render_submit()

    assert html =~ l.name
    assert html =~ e.name
  end

  test "invalid postcode shows an inline error", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/search")

    html =
      lv
      |> form("#centre-search-form", search: %{"postcode" => "not a postcode"})
      |> render_submit()

    assert html =~ "postcode" or html =~ "Postcode"
    assert html =~ "valid"
  end

  test "unknown postcode shows a friendlier 'no results' message",
       %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/search")

    html =
      lv
      |> form("#centre-search-form", search: %{"postcode" => "XX99 9XX"})
      |> render_submit()

    assert html =~ "couldn't find" or html =~ "could not find" or html =~ "no centre"
  end

  test "empty results show an empty-state message",
       %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/search")

    # Atlantic-ocean postcode is invalid; pick a real but unpopulated
    # area — Newcastle (NE2 4PT) where no centre is registered in
    # this test's setup.
    html =
      lv
      |> form("#centre-search-form",
        search: %{"postcode" => "NE2 4PT", "radius_metres" => "10000"}
      )
      |> render_submit()

    assert html =~ "No centres" or html =~ "no centres" or html =~ "didn"
  end

  test "exam filter restricts results", %{conn: conn, london: l, exam: e, admin: _} do
    # Add a second exam that London does NOT offer.
    {:ok, other} =
      Exams.create_exam(
        %{
          "name" => "Other Exam",
          "code" => "OTH",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1000
        },
        Admins.get_admin_by_email("srch-lv-admin@guildfordvue.test")
      )

    {:ok, lv, _} = live(conn, ~p"/search")

    html =
      lv
      |> form("#centre-search-form",
        search: %{"postcode" => "SW1A 1AA", "exam_id" => other.id}
      )
      |> render_submit()

    refute html =~ l.name, "London doesn't offer this exam"
    # The exam_id filter is still respected
    assert html =~ "No centres" or html =~ "no centres" or html =~ "didn"
  end

  # ---------------------------------------------------------------------------
  # TDD: results layout + slot modal
  # These tests are RED against the current implementation (Sprint 12 layout)
  # and will turn GREEN once the implementer:
  #   - replaces the side-by-side grid with a full-width map + card-per-centre layout
  #   - adds `id="centre-card-<id>"`, `phx-click="open_slots"` on each card
  #   - adds `id="slots-modal"` rendered when @selected_centre_id != nil
  #   - handles `open_slots` / `close_slots` events
  # ---------------------------------------------------------------------------
  describe "results layout + slot modal" do
    # This setup runs after the outer `setup` block, so `london`, `exam`, and
    # `slot` (7 days out) are already in the context.  We add a second slot
    # ~30 days out so the date-range assertion has two distinct dates.
    setup %{london: london, exam: exam, slot: slot} do
      future_30 = DateTime.utc_now() |> DateTime.add(30, :day)

      {:ok, slot2} =
        Slots.create_slot(london, %{
          "exam_id" => exam.id,
          "starts_at" => future_30,
          "ends_at" => DateTime.add(future_30, 60 * 60, :second),
          "capacity" => 5
        })

      %{slot: slot, slot2: slot2}
    end

    test "result card exposes centre name, distance, slot count and earliest date",
         %{conn: conn, london: london, slot: slot} do
      {:ok, lv, _} = live(conn, ~p"/search")

      html =
        lv
        |> form("#centre-search-form", search: %{"postcode" => "SW1A 1AA"})
        |> render_submit()

      # The card element itself must exist with the contract id.
      assert html =~ ~s(id="centre-card-#{london.id}"),
             "Expected a result card with id=\"centre-card-#{london.id}\" but it was absent. " <>
               "The current layout uses id=\"centre-result-<id>\" — the implementer must rename it."

      # Centre name must appear inside the card.
      assert html =~ london.name

      # The rendered distance string (via format_distance/1) must be present.
      # For a same-postcode search the value is <= a few hundred metres; we
      # assert the unit token (" m" or " mi") appears rather than an exact
      # figure so the test is geocoder-agnostic.
      assert html =~ " m" or html =~ " mi",
             "Expected format_distance output (' m' or ' mi') in the rendered card."

      # Slot count: the new card must surface the number of bookable slots.
      # Use a regex so the assertion holds regardless of how many fixture slots
      # the describe-block setup has added (the inner setup adds a second slot).
      assert html =~ ~r/\b\d+ slots?\b/,
             "Expected a bookable-slot count (e.g. '2 slots') in the card."

      # Earliest date of the slot (7 days out) must be rendered on the card
      # using the %-d %b format (e.g. "14 Jun").
      earliest_date = Calendar.strftime(slot.starts_at, "%-d %b")

      assert html =~ earliest_date,
             "Expected earliest slot date '#{earliest_date}' in the card summary."
    end

    test "no slots-modal present in the DOM before a card is clicked",
         %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/search")

      html =
        lv
        |> form("#centre-search-form", search: %{"postcode" => "SW1A 1AA"})
        |> render_submit()

      refute html =~ ~s(id="slots-modal"),
             "Expected no #slots-modal in the DOM before any card click, but it was found."
    end

    test "clicking a centre card opens the slot modal with slot details and Book link",
         %{conn: conn, london: london, slot: slot} do
      {:ok, lv, _} = live(conn, ~p"/search")

      lv
      |> form("#centre-search-form", search: %{"postcode" => "SW1A 1AA"})
      |> render_submit()

      # Click the centre card — this sends the open_slots event.
      html =
        lv
        |> element("#centre-card-#{london.id}")
        |> render_click()

      assert html =~ ~s(id="slots-modal"),
             "Expected #slots-modal in the DOM after clicking the centre card, but it was absent."

      # The modal must contain the slot's formatted start date.
      slot_date = Calendar.strftime(slot.starts_at, "%-d %b")

      assert html =~ slot_date,
             "Expected slot date '#{slot_date}' inside #slots-modal."

      # Each slot row must have the contract data-test-id wrapper.
      assert html =~ ~s(data-test-id="modal-slot-#{slot.id}"),
             "Expected data-test-id=\"modal-slot-#{slot.id}\" wrapper in the modal."

      # The "Book this slot" navigate link must point to /book/<slot-id>.
      assert html =~ ~s(href="/book/#{slot.id}"),
             "Expected a 'Book this slot' link with href='/book/#{slot.id}' in the modal."
    end

    test "clicking the close trigger removes the slot modal",
         %{conn: conn, london: london} do
      {:ok, lv, _} = live(conn, ~p"/search")

      lv
      |> form("#centre-search-form", search: %{"postcode" => "SW1A 1AA"})
      |> render_submit()

      # Open the modal first.
      lv
      |> element("#centre-card-#{london.id}")
      |> render_click()

      # Now close it.  The close button is the only element with
      # aria-label="Close"; the backdrop shares the phx-click binding but
      # element/2 requires a unique match, so we target the button directly.
      html =
        lv
        |> element("button[aria-label='Close']")
        |> render_click()

      refute html =~ ~s(id="slots-modal"),
             "Expected #slots-modal to be removed from the DOM after clicking close, but it persists."
    end

    test "date range on card shows both earliest and latest date when two slots exist",
         %{conn: conn, london: london, slot: slot, slot2: slot2} do
      {:ok, lv, _} = live(conn, ~p"/search")

      html =
        lv
        |> form("#centre-search-form", search: %{"postcode" => "SW1A 1AA"})
        |> render_submit()

      assert html =~ ~s(id="centre-card-#{london.id}"),
             "Expected a result card with id=\"centre-card-#{london.id}\"."

      earliest_date = Calendar.strftime(slot.starts_at, "%-d %b")
      latest_date = Calendar.strftime(slot2.starts_at, "%-d %b")

      assert html =~ earliest_date,
             "Expected earliest date '#{earliest_date}' in the date range on the card."

      assert html =~ latest_date,
             "Expected latest date '#{latest_date}' in the date range on the card."

      # The en-dash separator between range ends must be present on the card.
      assert html =~ "–",
             "Expected an en-dash range separator ('–') between dates on the card."
    end
  end
end
