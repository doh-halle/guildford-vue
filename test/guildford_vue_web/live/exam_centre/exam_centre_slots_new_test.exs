defmodule GuildfordVueWeb.ExamCentre.ExamCentreSlotsNewTest do
  @moduledoc """
  Sprint 4 Slice 4 — single-slot creation form at
  /examcenter/slots/new. The bulk + listing UIs land in Slices 5/6.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "slots-new-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "A",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "slots-new-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Slots New Centre",
        "address_line_1" => "1 St",
        "city" => "Sheffield",
        "postcode" => "S1 2HE"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Slots New Exam",
          "code" => "SNE",
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

  test "/examcenter/slots/new renders the form with the centre's offerings",
       %{conn: conn, exam: e} do
    {:ok, _lv, html} = live(conn, ~p"/examcenter/slots/new")
    assert html =~ "New slot"
    assert html =~ e.name
    assert html =~ e.code
  end

  test "submitting valid attrs creates a slot AND registers it with the GenServer",
       %{conn: conn, centre: c, exam: e} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots/new")

    {date, time} = future_date_time()

    lv
    |> form("#slot-form",
      slot: %{
        "exam_id" => e.id,
        "date" => date,
        "time" => time,
        "duration_minutes" => "60",
        "capacity" => "12"
      }
    )
    |> render_submit()

    [slot] = Slots.list_centre_slots(c)
    assert slot.capacity == 12
    assert slot.available_count == 12
    assert slot.status == "open"
    assert slot.exam_id == e.id

    # GenServer holds the new slot in its in-memory inventory.
    {:ok, pid} = Centres.ensure_started(c.id)
    [slot_in_memory] = Centres.list_slots(pid)
    assert slot_in_memory.id == slot.id
  end

  test "invalid submit shows inline errors and creates nothing",
       %{conn: conn, centre: c, exam: e} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots/new")

    html =
      lv
      |> form("#slot-form",
        slot: %{
          "exam_id" => e.id,
          "date" => "2020-01-01",
          "time" => "10:00",
          "duration_minutes" => "60",
          "capacity" => "0"
        }
      )
      |> render_submit()

    assert html =~ "must be in the future"
    assert html =~ "must be greater than 0"
    assert Slots.list_centre_slots(c) == []
  end

  test "centre with no offerings sees an empty-state message",
       %{conn: conn, centre: c} do
    {:ok, _} = ExamCentres.set_offerings(c, [], c)

    {:ok, _lv, html} = live(conn, ~p"/examcenter/slots/new")
    assert html =~ "no exams"
  end

  test "unauthenticated visit redirects to /examcenter/login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/slots/new")
    assert redirect =~ "/examcenter/login"
  end

  defp future_date_time do
    future = DateTime.utc_now() |> DateTime.add(7, :day)
    {Date.to_iso8601(DateTime.to_date(future)), Time.to_iso8601(DateTime.to_time(future))}
  end
end
