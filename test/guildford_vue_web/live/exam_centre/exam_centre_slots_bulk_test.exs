defmodule GuildfordVueWeb.ExamCentre.ExamCentreSlotsBulkTest do
  @moduledoc """
  Sprint 4 Slice 5 — bulk slot creation form at /examcenter/slots/bulk.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bulk-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "A",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bulk-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Bulk Centre",
        "address_line_1" => "1 St",
        "city" => "Newcastle",
        "postcode" => "NE1 4ST"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Bulk Exam",
          "code" => "BLK",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    conn =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre)})

    %{conn: conn, centre: centre, exam: exam}
  end

  test "renders the bulk form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/examcenter/slots/bulk")
    assert html =~ "Bulk create slots"
    assert html =~ "Date range"
    assert html =~ "Times"
    # Day-of-week labels
    for d <- ~w(Mon Tue Wed Thu Fri Sat Sun) do
      assert html =~ d
    end
  end

  test "submitting a Mon-Wed × 10:00 14:00 schedule creates N slots",
       %{conn: conn, centre: c, exam: e} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots/bulk")

    # Compute a Mon → Sun window at least two weeks in the future so
    # validate_in_future(:starts_at) on Slot.create_changeset/2 never rejects
    # the generated slots regardless of when the test suite runs.
    today = Date.utc_today()
    days_until_next_monday = rem(8 - Date.day_of_week(today), 7)
    days_until_next_monday = if days_until_next_monday == 0, do: 7, else: days_until_next_monday
    # The Monday a calendar week after the very next Monday — guarantees ≥ 8 days out.
    start_date = Date.add(today, days_until_next_monday + 7)
    end_date = Date.add(start_date, 6)

    mon_iso = Date.to_iso8601(start_date)
    wed_iso = Date.to_iso8601(Date.add(start_date, 2))

    lv
    |> form("#bulk-slot-form",
      bulk: %{
        "exam_id" => e.id,
        "start_date" => mon_iso,
        "end_date" => Date.to_iso8601(end_date),
        "times" => ["10:00", "14:00"],
        "weekdays" => ["1", "3"],
        "duration_minutes" => "60",
        "capacity" => "8"
      }
    )
    |> render_submit()

    slots = Slots.list_centre_slots(c)

    # Mon + Wed = 2 days × 2 times = 4 slots
    assert length(slots) == 4

    starts = slots |> Enum.map(& &1.starts_at) |> Enum.sort(DateTime)

    assert Enum.map(starts, & &1.hour) == [10, 14, 10, 14]

    assert Enum.map(starts, &Date.to_iso8601(DateTime.to_date(&1))) ==
             [mon_iso, mon_iso, wed_iso, wed_iso]

    assert Enum.all?(slots, &(&1.capacity == 8))
  end

  test "no weekdays selected → validation error, no slots created",
       %{conn: conn, centre: c, exam: e} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots/bulk")

    html =
      lv
      |> form("#bulk-slot-form",
        bulk: %{
          "exam_id" => e.id,
          "start_date" => "2026-06-01",
          "end_date" => "2026-06-07",
          "times" => ["10:00"],
          "weekdays" => [],
          "duration_minutes" => "60",
          "capacity" => "8"
        }
      )
      |> render_submit()

    assert html =~ "at least one weekday"
    assert Slots.list_centre_slots(c) == []
  end

  test "no times → validation error",
       %{conn: conn, centre: c, exam: e} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots/bulk")

    html =
      lv
      |> form("#bulk-slot-form",
        bulk: %{
          "exam_id" => e.id,
          "start_date" => "2026-06-01",
          "end_date" => "2026-06-07",
          "times" => [],
          "weekdays" => ["1"],
          "duration_minutes" => "60",
          "capacity" => "8"
        }
      )
      |> render_submit()

    assert html =~ "at least one time"
    assert Slots.list_centre_slots(c) == []
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/slots/bulk")
    assert redirect =~ "/examcenter/login"
  end
end
