defmodule GuildfordVueWeb.ExamCentre.ExamCentreBookingsIndexTest do
  @moduledoc """
  TDD tests for the exam-centre bookings listing LiveView:
  `GuildfordVueWeb.ExamCentre.ExamCentreBookingsLive` mounted at
  `/examcenter/bookings` (live action `:index`).

  All tests are written BEFORE the production module exists; they must fail
  with a missing-module / compile error until the LiveView is implemented.

  Invariants:
    - The page renders booking references + exam name + candidate email/name.
    - Each row links to the booking detail page.
    - Only the signed-in centre's bookings appear (tenant isolation).
    - An empty-state message is shown when the centre has no bookings.
    - The sidebar nav item for Bookings carries `aria-current="page"`.
    - Unauthenticated access redirects to /examcenter/login.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  # ---------------------------------------------------------------------------
  # Shared setup — two approved centres, one exam, slots, two bookings at
  # centre_a and one at centre_b.
  # ---------------------------------------------------------------------------

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bix-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "BIX Admin",
        "role" => "superadmin"
      })

    {:ok, centre_a} =
      ExamCentres.register_exam_centre(%{
        "email" => "bix-ca-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BIX Centre A",
        "address_line_1" => "1 High St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, centre_a} = ExamCentres.approve(centre_a, admin)

    {:ok, centre_b} =
      ExamCentres.register_exam_centre(%{
        "email" => "bix-cb-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "BIX Centre B",
        "address_line_1" => "2 Low St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre_b} = ExamCentres.approve(centre_b, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "BIX Exam",
          "code" => "BIX-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 5_000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre_a, [exam.id], centre_a)
    {:ok, _} = ExamCentres.set_offerings(centre_b, [exam.id], centre_b)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

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

    {:ok, candidate1} =
      Candidates.register_candidate(%{
        "email" => "bix-c1-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alice",
        "last_name" => "Smith"
      })

    {:ok, candidate2} =
      Candidates.register_candidate(%{
        "email" => "bix-c2-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Bob",
        "last_name" => "Jones"
      })

    # Start GenServers for both centres.
    {:ok, _pid_a} = Centres.start_centre(centre_a.id)
    {:ok, _pid_b} = Centres.start_centre(centre_b.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre_a.id)
      _ = Centres.stop_centre(centre_b.id)
    end)

    # Two bookings at centre_a, one at centre_b.
    {:ok, booking_a1} = Bookings.create_booking(candidate1, slot_a1)
    {:ok, booking_a2} = Bookings.create_booking(candidate2, slot_a2)
    {:ok, booking_b} = Bookings.create_booking(candidate1, slot_b)

    conn_a =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre_a)})

    %{
      conn: conn_a,
      admin: admin,
      centre_a: centre_a,
      centre_b: centre_b,
      exam: exam,
      booking_a1: booking_a1,
      booking_a2: booking_a2,
      booking_b: booking_b,
      candidate1: candidate1,
      candidate2: candidate2
    }
  end

  # ---------------------------------------------------------------------------
  # Content tests (signed in as centre_a)
  # ---------------------------------------------------------------------------

  describe "/examcenter/bookings index" do
    test "renders both of centre_a's booking references", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      assert html =~ ctx.booking_a1.reference
      assert html =~ ctx.booking_a2.reference
    end

    test "does NOT render centre_b's booking reference (tenant isolation)", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      refute html =~ ctx.booking_b.reference
    end

    test "renders the exam name in each row", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      # Both bookings are for the same exam; the name must appear at least once.
      assert html =~ ctx.exam.name
    end

    test "renders candidate identifying information (email or last name) in the rows",
         ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      # At minimum one of: email, first name, last name should appear for
      # each candidate so the table is useful at a glance.
      assert html =~ ctx.candidate1.email or html =~ ctx.candidate1.last_name
      assert html =~ ctx.candidate2.email or html =~ ctx.candidate2.last_name
    end

    test "each row contains a navigable link to the booking detail page", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      assert html =~ ~s(href="/examcenter/bookings/#{ctx.booking_a1.reference}")
      assert html =~ ~s(href="/examcenter/bookings/#{ctx.booking_a2.reference}")
    end

    test "renders an empty-state message when the centre has no bookings", %{conn: _conn} do
      # Create a fresh third centre with no bookings.
      {:ok, admin} =
        Admins.register_admin(%{
          "email" => "bix-admin2-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "BIX Admin2",
          "role" => "superadmin"
        })

      {:ok, centre_c} =
        ExamCentres.register_exam_centre(%{
          "email" => "bix-cc-#{System.unique_integer([:positive])}@example.com",
          "password" => "supersecret123!A",
          "name" => "BIX Centre C",
          "address_line_1" => "3 Empty Rd",
          "city" => "Manchester",
          "postcode" => "M1 1AE"
        })

      {:ok, centre_c} = ExamCentres.approve(centre_c, admin)

      conn_c =
        Phoenix.ConnTest.build_conn()
        |> init_test_session(%{exam_centre_token: ExamCentres.generate_session_token(centre_c)})

      {:ok, _lv, html} = live(conn_c, ~p"/examcenter/bookings")

      # Some "no bookings" empty-state text must be present.
      assert html =~ ~r/no bookings/i or html =~ ~r/haven.t received/i or
               html =~ ~r/no results/i or html =~ ~r/empty/i
    end

    test "sidebar Bookings link carries aria-current='page'", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/examcenter/bookings")

      # The centre_shell renders nav links with aria-current="page" for the
      # active item. When `active={:bookings}` is passed the Bookings link
      # should carry the attribute.
      assert html =~
               ~s(aria-current="page") and html =~ ~s(href="/examcenter/bookings")
    end

    test "unauthenticated visit redirects to examcenter login" do
      conn = Phoenix.ConnTest.build_conn()
      {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/bookings")
      assert redirect =~ "/examcenter/login"
    end
  end
end
