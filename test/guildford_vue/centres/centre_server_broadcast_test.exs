defmodule GuildfordVue.Centres.CentreServerBroadcastTest do
  @moduledoc """
  Sprint 6 Slice 2 — CentreServer broadcasts a `{:slot_changed, slot}`
  message on every state transition (add, reserve, release, cancel).
  Subscribers (calendar LV, search LV) re-render from the new slot
  state.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Centres.CentreServer
  alias GuildfordVue.Centres.PubSub, as: CentrePubSub

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "broadcast-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "broadcast-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Broadcast Centre",
        "address_line_1" => "1 St",
        "city" => "Cardiff",
        "postcode" => "CF10 1EP"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Broadcast Exam",
          "code" => "BC",
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
        "capacity" => 4
      })

    {:ok, pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    %{centre: centre, exam: exam, slot: slot, pid: pid}
  end

  test "subscribers receive {:slot_changed, slot} after reserve",
       %{centre: c, slot: slot, pid: pid} do
    :ok = CentrePubSub.subscribe(c.id)

    {:ok, reserved} = CentreServer.reserve_slot(pid, slot.id)

    assert_receive {:slot_changed, ^reserved}, 500
    assert reserved.available_count == slot.capacity - 1
  end

  test "subscribers receive a broadcast after release",
       %{centre: c, slot: slot, pid: pid} do
    {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

    :ok = CentrePubSub.subscribe(c.id)
    {:ok, released} = CentreServer.release_slot(pid, slot.id)

    assert_receive {:slot_changed, ^released}, 500
  end

  test "subscribers receive a broadcast after cancel",
       %{centre: c, slot: slot, pid: pid} do
    :ok = CentrePubSub.subscribe(c.id)

    {:ok, cancelled} = CentreServer.cancel_slot(pid, slot.id, c)

    assert_receive {:slot_changed, ^cancelled}, 500
    assert cancelled.status == "cancelled"
  end

  test "subscribers receive a broadcast after add_slot (new slot pushed to inventory)",
       %{centre: c, exam: e, pid: pid} do
    :ok = CentrePubSub.subscribe(c.id)

    future2 = DateTime.utc_now() |> DateTime.add(8, :day)

    {:ok, slot2} =
      Slots.create_slot(c, %{
        "exam_id" => e.id,
        "starts_at" => future2,
        "ends_at" => DateTime.add(future2, 60 * 60, :second),
        "capacity" => 2
      })

    :ok = CentreServer.add_slot(pid, slot2)

    assert_receive {:slot_changed, ^slot2}, 500
  end

  test "subscribers to OTHER centres do not receive this centre's broadcasts",
       %{slot: slot, pid: pid} do
    other_id = Ecto.UUID.generate()
    :ok = CentrePubSub.subscribe(other_id)

    {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

    refute_receive {:slot_changed, _}, 100
  end

  test "failed reserve (sold out) does NOT broadcast",
       %{centre: c, slot: slot, pid: pid} do
    # Fill the slot
    for _ <- 1..slot.capacity, do: {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

    :ok = CentrePubSub.subscribe(c.id)
    assert {:error, :sold_out} = CentreServer.reserve_slot(pid, slot.id)

    refute_receive {:slot_changed, _}, 100
  end
end
