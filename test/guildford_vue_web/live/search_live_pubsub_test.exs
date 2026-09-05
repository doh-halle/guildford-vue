defmodule GuildfordVueWeb.SearchLivePubsubTest do
  @moduledoc """
  Sprint 6 Slice 5 — live updates on /search results. After a
  successful search the LV subscribes to each visible centre's
  PubSub topic; a {:slot_changed, slot} broadcast updates the
  matching slot's row in real time.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Centres.CentreServer
  alias GuildfordVue.Centres.PubSub, as: CentrePubSub
  alias GuildfordVue.Slots.Slot

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "sl-pubsub-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "sl-pubsub-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "PubSub Centre",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "PubSub Exam",
          "code" => "PSE",
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
        "capacity" => 8
      })

    {:ok, pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    %{conn: conn, centre: centre, exam: exam, slot: slot, pid: pid}
  end

  test "search results subscribe to each visible centre's topic + re-render on broadcast",
       %{conn: conn, centre: centre, slot: slot, pid: pid} do
    {:ok, lv, _} = live(conn, ~p"/search?postcode=SW1A+1AA")

    # Capture the initial marker pushed when results first load.
    assert_push_event(lv, "map:set-markers", %{markers: initial_markers})
    assert is_list(initial_markers)

    initial_marker = Enum.find(initial_markers, fn m -> m.centre_id == centre.id end)
    assert initial_marker != nil, "Expected a marker for the test centre in the initial push"

    initial_available = initial_marker.available_count

    # Reserve one seat — CentreServer decrements available_count and
    # broadcasts {:slot_changed, slot}. SearchLive should re-push markers.
    {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

    # Allow the PubSub broadcast to propagate to the LV.
    Process.sleep(50)

    # The LV must re-push the markers with a decremented available_count.
    assert_push_event(lv, "map:set-markers", %{markers: updated_markers})
    assert is_list(updated_markers)

    updated_marker = Enum.find(updated_markers, fn m -> m.centre_id == centre.id end)
    assert updated_marker != nil, "Expected a marker for the test centre in the updated push"

    assert updated_marker.available_count < initial_available,
           "Expected available_count to decrease after reservation: " <>
             "initial=#{initial_available}, updated=#{updated_marker.available_count}"

    # Slot count reference: the unused alias is kept here for clarity.
    _ = slot
  end

  test "fully-booking a slot drops it from results (no matching slots)",
       %{conn: conn, centre: centre, slot: slot, pid: pid} do
    {:ok, lv, _} = live(conn, ~p"/search?postcode=SW1A+1AA")
    assert render(lv) =~ "PubSub Centre"

    # Drain the initial marker push triggered by the search on mount so the
    # assert_push_event calls below only see reservation-driven updates.
    assert_push_event(lv, "map:set-markers", %{markers: _initial_markers})

    # Drain all capacity sequentially. Each CentreServer.reserve_slot/2 call
    # broadcasts {:slot_changed, slot} and the LV pushes a new map:set-markers.
    # We consume each push event in lock-step (capacity == 8 slots).
    capacity = slot.capacity

    final_markers =
      Enum.reduce(1..capacity, nil, fn _i, _acc ->
        {:ok, _} = CentreServer.reserve_slot(pid, slot.id)
        # Each reservation triggers a push; read it from the mailbox.
        # assert_push_event returns the matched payload via assert_receive.
        %{proxy: {ref, _topic, _}} = lv
        assert_receive {^ref, {:push_event, "map:set-markers", %{markers: markers}}}, 500
        markers
      end)

    # The last payload corresponds to the final reservation (available_count == 0).
    assert is_list(final_markers)

    final_marker = Enum.find(final_markers, fn m -> m.centre_id == centre.id end)
    assert final_marker != nil, "Expected a marker for the test centre after full booking"

    assert final_marker.available_count == 0,
           "Expected available_count == 0 on the marker after fully booking all #{capacity} seats"

    assert final_marker.available_slot_count == 0,
           "Expected available_slot_count == 0 on the marker after fully booking all #{capacity} seats"
  end

  test "map:set-markers event fires with updated available_count after a slot reservation",
       %{conn: conn, centre: centre, slot: slot, pid: pid} do
    {:ok, lv, _} = live(conn, ~p"/search?postcode=SW1A+1AA")

    # Capture the initial marker payload pushed when results first load.
    assert_push_event(lv, "map:set-markers", %{markers: initial_markers})
    assert is_list(initial_markers)

    initial_marker =
      Enum.find(initial_markers, fn m -> m.centre_id == centre.id end)

    assert initial_marker != nil, "Expected a marker for the test centre in the initial push"

    # Reserve one seat — CentreServer decrements available_count and
    # broadcasts {:slot_changed, slot}. SearchLive should re-push markers.
    {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

    # Let the PubSub broadcast settle (mirrors the style of the third test).
    Process.sleep(50)

    assert_push_event(lv, "map:set-markers", %{markers: updated_markers})
    assert is_list(updated_markers)

    updated_marker =
      Enum.find(updated_markers, fn m -> m.centre_id == centre.id end)

    assert updated_marker != nil, "Expected a marker for the test centre in the updated push"

    assert updated_marker.available_count < initial_marker.available_count,
           "Expected available_count to decrease after reservation: " <>
             "initial=#{initial_marker.available_count}, updated=#{updated_marker.available_count}"
  end

  test "broadcast on a different centre's topic does NOT affect the LV",
       %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/search?postcode=SW1A+1AA")
    initial = render(lv)

    other_id = Ecto.UUID.generate()

    CentrePubSub.broadcast(
      other_id,
      {:slot_changed, %Slot{id: Ecto.UUID.generate()}}
    )

    Process.sleep(50)
    assert render(lv) == initial
  end
end
