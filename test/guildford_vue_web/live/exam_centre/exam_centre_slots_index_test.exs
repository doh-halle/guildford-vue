defmodule GuildfordVueWeb.ExamCentre.ExamCentreSlotsIndexTest do
  @moduledoc """
  Sprint 4 Slice 6 — slot listing + per-row cancellation.

  Also covers real-time slot availability updates via CentrePubSub
  (TDD stubs for the {:slot_changed, slot} handle_info wiring that
  ExamCentreSlotsLive does not yet implement).
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog, Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Slots.Slot

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "slotix-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "A",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "slotix-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "SlotIdx Centre",
        "address_line_1" => "1 St",
        "city" => "Glasgow",
        "postcode" => "G1 1XQ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "SlotIdx Exam",
          "code" => "SIX",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1000
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
        "capacity" => 10
      })

    # Pre-start the GenServer so the slot is in inventory.
    {:ok, pid} = Centres.start_centre(centre.id)
    :ok = Centres.add_slot(pid, slot)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    conn =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre)})

    %{conn: conn, centre: centre, exam: exam, slot: slot}
  end

  test "shows the slot in the index", %{conn: conn, slot: slot, exam: e} do
    {:ok, _lv, html} = live(conn, ~p"/examcenter/slots")
    assert html =~ e.code
    assert html =~ "open"
    assert html =~ to_string(slot.capacity)
  end

  test "Cancel button cancels the slot, audits, and removes it from inventory",
       %{conn: conn, centre: c, slot: slot} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots")

    lv
    |> element("[data-test-id='cancel-slot-#{slot.id}']")
    |> render_click()

    reloaded = Slots.get_slot!(slot.id)
    assert reloaded.status == "cancelled"

    # Audit event with the centre as actor
    assert [event] = AuditLog.list(event_type: "slot_cancelled", aggregate_id: slot.id)
    assert event.actor_id == c.id
    assert event.actor_type == "exam_centre"

    # In-memory inventory drops the cancelled slot
    {:ok, pid} = Centres.whereis(c.id)
    assert Centres.list_slots(pid) == []
  end

  test "after cancellation, slot is excluded from the upcoming list",
       %{conn: conn, slot: slot} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/slots")

    lv
    |> element("[data-test-id='cancel-slot-#{slot.id}']")
    |> render_click()

    html = render(lv)
    refute html =~ "slot-row-#{slot.id}", "cancelled slot should be gone"
  end

  test "empty state when no upcoming slots",
       %{conn: conn, centre: c, slot: slot} do
    {:ok, _} = Slots.cancel_slot(slot, c)

    {:ok, _lv, html} = live(conn, ~p"/examcenter/slots")
    assert html =~ "No upcoming slots"
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/slots")
    assert redirect =~ "/examcenter/login"
  end

  # ------------------------------------------------------------------
  # Real-time updates via CentrePubSub
  # ------------------------------------------------------------------

  describe "real-time updates via CentrePubSub" do
    test "slot row's available_count updates on {:slot_changed, slot}",
         %{conn: conn, slot: slot} do
      # Arrange — mount the slots index. The setup already creates one
      # slot with capacity: 10 / available_count: 10 and registers it
      # with the GenServer.
      {:ok, lv, html} = live(conn, ~p"/examcenter/slots")

      # Verify initial render shows the original available_count.
      assert html =~ to_string(slot.available_count),
             "initial render should include available_count #{slot.available_count}"

      # Act — simulate a PubSub broadcast that drops the count to 3.
      updated_slot = %Slot{slot | available_count: 3}
      send(lv.pid, {:slot_changed, updated_slot})

      # Assert — the Available column cell in the slot's row must show 3.
      # We parse the HTML with Floki and target the exact <td> for the
      # Available column (4th <td> in the row) so the Capacity column
      # still showing 10 does not produce a false negative.
      new_html = render(lv)

      available_cell =
        new_html
        |> Floki.parse_document!()
        |> Floki.find("tr#slot-row-#{slot.id} td:nth-child(4)")
        |> Floki.text()
        |> String.trim()

      assert available_cell == "3",
             "expected Available cell to show '3' after :slot_changed, got #{inspect(available_cell)}"
    end

    test "slot_changed for a slot NOT in the listing is ignored (no crash)",
         %{conn: conn, slot: slot} do
      # Arrange — mount the slots index. The listing contains the slot
      # created in setup.
      {:ok, lv, _html} = live(conn, ~p"/examcenter/slots")

      # Act — send a :slot_changed message for a slot id not in the listing.
      ghost_slot = %Slot{
        id: Ecto.UUID.generate(),
        exam_centre_id: slot.exam_centre_id,
        exam_id: slot.exam_id,
        starts_at: slot.starts_at,
        ends_at: slot.ends_at,
        capacity: 5,
        available_count: 0,
        status: "full"
      }

      send(lv.pid, {:slot_changed, ghost_slot})

      # Assert — the LV must still be alive and must still show the
      # original slot.
      new_html = render(lv)

      assert new_html =~ "slot-row-#{slot.id}",
             "the original slot row should still be present after receiving an unknown :slot_changed"
    end
  end
end
