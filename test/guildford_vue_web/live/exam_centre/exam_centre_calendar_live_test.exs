defmodule GuildfordVueWeb.ExamCentre.ExamCentreCalendarLiveTest do
  @moduledoc """
  Sprint 6 Slice 4 — live calendar at /examcenter/calendar. Subscribes
  to the centre's PubSub topic and re-renders on `{:slot_changed, _}`.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Centres.CentreServer
  alias GuildfordVue.Centres.PubSub, as: CentrePubSub

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "cal-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "cal-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Cal Centre",
        "address_line_1" => "1 St",
        "city" => "Edinburgh",
        "postcode" => "EH1 1YZ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Cal Exam",
          "code" => "CAL",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    # Slot at next Monday 10:00 UTC so the calendar deterministically
    # includes it within the next-14-days window.
    next_monday = next_weekday(Date.utc_today(), 1)
    {:ok, starts_at} = DateTime.new(next_monday, ~T[10:00:00], "Etc/UTC")

    {:ok, slot} =
      Slots.create_slot(centre, %{
        "exam_id" => exam.id,
        "starts_at" => starts_at,
        "ends_at" => DateTime.add(starts_at, 60 * 60, :second),
        "capacity" => 10
      })

    {:ok, pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    conn =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre)})

    %{conn: conn, centre: centre, exam: exam, slot: slot, pid: pid, slot_date: next_monday}
  end

  defp next_weekday(date, target_dow) do
    # Advance day-by-day until we hit the target weekday (1 = Mon).
    Enum.reduce_while(0..6, date, fn _, d ->
      if Date.day_of_week(d) == target_dow do
        {:halt, d}
      else
        {:cont, Date.add(d, 1)}
      end
    end)
  end

  test "renders the calendar grid with the centre's slots",
       %{conn: conn, slot_date: date} do
    {:ok, _lv, html} = live(conn, ~p"/examcenter/calendar")
    assert html =~ "Calendar"
    assert html =~ Date.to_iso8601(date)
    # Slot at 10:00 → cell coloured :available (teal)
    assert html =~ "bg-teal-100"
  end

  test "live update: PubSub broadcast re-renders the affected cell",
       %{conn: conn, centre: c, slot: slot, pid: pid} do
    {:ok, lv, html} = live(conn, ~p"/examcenter/calendar")
    # Initially the cell is :available (teal).
    assert html =~ "bg-teal-100"

    # Trigger a state change that fills the slot.
    for _ <- 1..slot.capacity, do: {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

    # The LV's handle_info({:slot_changed, _}, _) flips the cell to
    # :fully_booked. The legend at the bottom still contains the
    # teal swatch class for "Available" (a static reference), so we
    # check the actual cell — the test-id'd <td> should now carry
    # the red availability classes (not teal).
    html = render(lv)
    cell_re = ~r/data-test-id="calendar-cell-[^"]+"[^>]*class="[^"]*bg-red-100/

    assert html =~ cell_re,
           "expected the affected cell to be coloured fully_booked (red) after capacity reserves"

    refute html =~
             ~r/data-test-id="calendar-cell-[^"]+"[^>]*class="[^"]*bg-teal-100/,
           "the cell should NOT still carry the teal :available colour"

    _ = c
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/calendar")
    assert redirect =~ "/examcenter/login"
  end
end
