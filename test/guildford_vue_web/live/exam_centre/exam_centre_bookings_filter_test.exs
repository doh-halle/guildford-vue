defmodule GuildfordVueWeb.ExamCentre.ExamCentreBookingsFilterTest do
  @moduledoc """
  TDD tests for the search-box + status-filter form on the exam-centre
  bookings listing LiveView (`GuildfordVueWeb.ExamCentre.ExamCentreBookingsLive`,
  live action `:index`, mounted at `/examcenter/bookings`).

  These tests are written BEFORE the production code exists for the filter
  form. They are expected to fail until:
    1. The filter form `<form id="bookings-filter-form" phx-change="filter">`
       is rendered in the :index template.
    2. The `handle_event("filter", ...)` callback narrows `@rows` in assigns.
    3. `GuildfordVue.Bookings.list_bookings_for_centre/2` accepts a `:status`
       keyword opt (tested separately in bookings_for_centre_filter_test.exs).

  Form contract:
    - text input: `name="filter[query]"` — substring match on reference,
      candidate first_name, last_name, and email (case-insensitive).
    - select: `name="filter[status]"` — options: all / confirmed / cancelled /
      refunded. Default is "all" (no filter).

  Empty-state disambiguation:
    - `data-test-id="bookings-empty-state"` — centre has NO bookings at all.
    - `data-test-id="bookings-no-matches"` — bookings exist but filters yield
      no results.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  # ---------------------------------------------------------------------------
  # Shared setup — two approved centres, one exam, three bookings at centre_a
  # with three distinct candidates and three distinct statuses, one at centre_b.
  # ---------------------------------------------------------------------------

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bflt-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "BFLT Admin",
        "role" => "superadmin"
      })

    {:ok, centre_a} =
      ExamCentres.register_exam_centre(%{
        "email" => "bflt-ca-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BFLT Centre A",
        "address_line_1" => "1 High St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, centre_a} = ExamCentres.approve(centre_a, admin)

    {:ok, centre_b} =
      ExamCentres.register_exam_centre(%{
        "email" => "bflt-cb-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BFLT Centre B",
        "address_line_1" => "2 Low St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre_b} = ExamCentres.approve(centre_b, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "BFLT Exam",
          "code" => "BFLT-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 5_000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre_a, [exam.id], centre_a)
    {:ok, _} = ExamCentres.set_offerings(centre_b, [exam.id], centre_b)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    # One slot per booking at centre_a.
    {:ok, slot_a1} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 3600, :second),
        "capacity" => 10
      })

    {:ok, slot_a2} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => DateTime.add(future, 1, :day),
        "ends_at" => DateTime.add(future, 86_400 + 3600, :second),
        "capacity" => 10
      })

    {:ok, slot_a3} =
      Slots.create_slot(centre_a, %{
        "exam_id" => exam.id,
        "starts_at" => DateTime.add(future, 2, :day),
        "ends_at" => DateTime.add(future, 2 * 86_400 + 3600, :second),
        "capacity" => 10
      })

    {:ok, slot_b} =
      Slots.create_slot(centre_b, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 3600, :second),
        "capacity" => 10
      })

    # Three distinct candidates — each belongs to one booking at centre_a.
    idx = System.unique_integer([:positive])

    {:ok, candidate1} =
      Candidates.register_candidate(%{
        "email" => "bflt-alpha-#{idx}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alpha",
        "last_name" => "Zephyr"
      })

    {:ok, candidate2} =
      Candidates.register_candidate(%{
        "email" => "bflt-beta-#{idx}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Beta",
        "last_name" => "Quasar"
      })

    {:ok, candidate3} =
      Candidates.register_candidate(%{
        "email" => "bflt-gamma-#{idx}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Gamma",
        "last_name" => "Nebula"
      })

    # Start GenServers.
    {:ok, _pid_a} = Centres.start_centre(centre_a.id)
    {:ok, _pid_b} = Centres.start_centre(centre_b.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre_a.id)
      _ = Centres.stop_centre(centre_b.id)
    end)

    # booking1 (candidate1, centre_a) → confirmed (default).
    {:ok, booking1} = Bookings.create_booking(candidate1, slot_a1)

    # booking2 (candidate2, centre_a) → cancelled.
    {:ok, booking2_raw} = Bookings.create_booking(candidate2, slot_a2)
    {:ok, booking2} = Bookings.cancel_booking(booking2_raw, candidate2)

    # booking3 (candidate3, centre_a) → refunded.
    {:ok, booking3_raw} = Bookings.create_booking(candidate3, slot_a3)
    {:ok, booking3} = Bookings.refund(booking3_raw, admin)

    # One booking at centre_b (candidate1) — must never appear via centre_a.
    {:ok, booking_b} = Bookings.create_booking(candidate1, slot_b)

    conn_a =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre_a)})

    %{
      conn: conn_a,
      admin: admin,
      centre_a: centre_a,
      centre_b: centre_b,
      exam: exam,
      booking1: booking1,
      booking2: booking2,
      booking3: booking3,
      booking_b: booking_b,
      candidate1: candidate1,
      candidate2: candidate2,
      candidate3: candidate3
    }
  end

  # ---------------------------------------------------------------------------
  # Default render — all three bookings visible
  # ---------------------------------------------------------------------------

  describe "filter form — default render" do
    test "renders all 3 centre_a bookings with no filters applied", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      assert html =~ ctx.booking1.reference
      assert html =~ ctx.booking2.reference
      assert html =~ ctx.booking3.reference
    end

    test "renders the filter form element", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      assert html =~ ~s(id="bookings-filter-form")
      assert html =~ ~s(phx-change="filter")
    end

    test "renders the query text input", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      assert html =~ ~s(name="filter[query]")
    end

    test "renders the status select with all four options", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      assert html =~ ~s(name="filter[status]")
      assert html =~ "confirmed"
      assert html =~ "cancelled"
      assert html =~ "refunded"
    end
  end

  # ---------------------------------------------------------------------------
  # Text filter — reference substring
  # ---------------------------------------------------------------------------

  describe "filter form — query by booking reference" do
    test "filtering by the first 4 chars of booking1's reference shows it and hides the others",
         ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      # Take a slice from the random tail of the reference (the GV-YYYY- prefix is
      # shared across bookings made in the same year, so a leading slice isn't unique).
      query_needle = String.slice(ctx.booking1.reference, -4..-1//1)

      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: query_needle, status: "all"})
        |> render_change()

      assert html =~ ctx.booking1.reference
      refute html =~ ctx.booking2.reference
      refute html =~ ctx.booking3.reference
    end
  end

  # ---------------------------------------------------------------------------
  # Text filter — candidate first_name
  # ---------------------------------------------------------------------------

  describe "filter form — query by candidate first_name" do
    test "partial lowercase first_name for candidate1 shows booking1 and hides the others",
         ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      # "alpha" is a case-insensitive substring of "Alpha".
      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "alpha", status: "all"})
        |> render_change()

      assert html =~ ctx.booking1.reference
      refute html =~ ctx.booking2.reference
      refute html =~ ctx.booking3.reference
    end
  end

  # ---------------------------------------------------------------------------
  # Text filter — candidate last_name
  # ---------------------------------------------------------------------------

  describe "filter form — query by candidate last_name" do
    test "mixed-case partial last_name for candidate2 shows booking2 and hides the others",
         ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      # "Qua" is a case-insensitive substring of "Quasar".
      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "Qua", status: "all"})
        |> render_change()

      assert html =~ ctx.booking2.reference
      refute html =~ ctx.booking1.reference
      refute html =~ ctx.booking3.reference
    end
  end

  # ---------------------------------------------------------------------------
  # Text filter — candidate email
  # ---------------------------------------------------------------------------

  describe "filter form — query by candidate email" do
    test "email substring for candidate3 shows booking3 and hides the others", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      # "bflt-gamma" is unique to candidate3's email.
      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "bflt-gamma", status: "all"})
        |> render_change()

      assert html =~ ctx.booking3.reference
      refute html =~ ctx.booking1.reference
      refute html =~ ctx.booking2.reference
    end
  end

  # ---------------------------------------------------------------------------
  # Status filter
  # ---------------------------------------------------------------------------

  describe "filter form — status: confirmed" do
    test "shows the confirmed booking and hides cancelled and refunded", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "", status: "confirmed"})
        |> render_change()

      assert html =~ ctx.booking1.reference
      refute html =~ ctx.booking2.reference
      refute html =~ ctx.booking3.reference
    end
  end

  describe "filter form — status: cancelled" do
    test "shows the cancelled booking and hides confirmed and refunded", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "", status: "cancelled"})
        |> render_change()

      assert html =~ ctx.booking2.reference
      refute html =~ ctx.booking1.reference
      refute html =~ ctx.booking3.reference
    end
  end

  describe "filter form — status: refunded" do
    test "shows the refunded booking and hides confirmed and cancelled", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "", status: "refunded"})
        |> render_change()

      assert html =~ ctx.booking3.reference
      refute html =~ ctx.booking1.reference
      refute html =~ ctx.booking2.reference
    end
  end

  # ---------------------------------------------------------------------------
  # Combined filter + zero-results empty-state
  # ---------------------------------------------------------------------------

  describe "filter form — combined text + status that matches nothing" do
    test "renders bookings-no-matches empty-state and NOT bookings-empty-state", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      # A status of "confirmed" combined with text that doesn't match booking1
      # should yield zero results while bookings DO exist in general.
      html =
        lv
        |> form("#bookings-filter-form",
          filter: %{query: "ZZZNOMATCH", status: "confirmed"}
        )
        |> render_change()

      assert html =~ ~s(data-test-id="bookings-no-matches")
      refute html =~ ~s(data-test-id="bookings-empty-state")
    end

    test "no booking references appear when filters match nothing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      html =
        lv
        |> form("#bookings-filter-form",
          filter: %{query: "ZZZNOMATCH", status: "confirmed"}
        )
        |> render_change()

      refute html =~ ctx.booking1.reference
      refute html =~ ctx.booking2.reference
      refute html =~ ctx.booking3.reference
    end
  end

  # ---------------------------------------------------------------------------
  # Tenant isolation — centre_b bookings never appear regardless of filter
  # ---------------------------------------------------------------------------

  describe "filter form — tenant isolation" do
    test "centre_b's booking never appears with status: all and empty query", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "", status: "all"})
        |> render_change()

      refute html =~ ctx.booking_b.reference
    end

    test "centre_b's booking never appears with status: confirmed", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/examcenter/bookings")

      html =
        lv
        |> form("#bookings-filter-form", filter: %{query: "", status: "confirmed"})
        |> render_change()

      refute html =~ ctx.booking_b.reference
    end
  end
end
