defmodule GuildfordVue.SlotsTest do
  @moduledoc """
  Sprint 4 Slice 1 — pure data layer for slots.

  Slot lifecycle ADT: `"open" | "full" | "cancelled"`. `available_count`
  is denormalised from capacity − reservations (Sprint 7 fills the
  reservation table; for now reserve_slot/1 in the GenServer
  decrements directly).
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, AuditLog, ExamCentres, Exams, Slots}
  alias GuildfordVue.Slots.Slot

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "slots-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Slots Admin",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "slots-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Slots Centre",
        "address_line_1" => "1 St",
        "city" => "Bristol",
        "postcode" => "BS1 4DJ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Slot Exam",
          "code" => "SLT",
          "certification_body" => "X",
          "duration_minutes" => 90,
          "price_pence" => 2500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    %{admin: admin, centre: centre, exam: exam}
  end

  defp future_starts_at, do: DateTime.utc_now() |> DateTime.add(7, :day)

  describe "create_slot/2" do
    test "creates a valid slot + writes slot_created audit event",
         %{centre: c, exam: e} do
      starts = future_starts_at()
      ends = DateTime.add(starts, 90 * 60, :second)

      assert {:ok, %Slot{} = slot} =
               Slots.create_slot(c, %{
                 "exam_id" => e.id,
                 "starts_at" => starts,
                 "ends_at" => ends,
                 "capacity" => 12
               })

      assert slot.exam_centre_id == c.id
      assert slot.exam_id == e.id
      assert slot.capacity == 12
      assert slot.available_count == 12
      assert slot.status == "open"

      assert [event] = AuditLog.list(event_type: "slot_created", aggregate_id: slot.id)
      assert event.actor_id == c.id
      assert event.actor_type == "exam_centre"
      assert event.payload["exam_code"] == "SLT"
    end

    test "requires the exam to be in the centre's offerings",
         %{admin: admin, centre: c} do
      {:ok, other_exam} =
        Exams.create_exam(
          %{
            "name" => "Not Offered",
            "code" => "NOPE",
            "certification_body" => "X",
            "duration_minutes" => 60,
            "price_pence" => 1000
          },
          admin
        )

      starts = future_starts_at()
      ends = DateTime.add(starts, 60 * 60, :second)

      assert {:error, :exam_not_offered} =
               Slots.create_slot(c, %{
                 "exam_id" => other_exam.id,
                 "starts_at" => starts,
                 "ends_at" => ends,
                 "capacity" => 10
               })
    end

    test "rejects past starts_at", %{centre: c, exam: e} do
      starts = DateTime.utc_now() |> DateTime.add(-1, :day)
      ends = DateTime.add(starts, 60 * 60, :second)

      assert {:error, cs} =
               Slots.create_slot(c, %{
                 "exam_id" => e.id,
                 "starts_at" => starts,
                 "ends_at" => ends,
                 "capacity" => 10
               })

      assert Enum.any?(errors_on(cs).starts_at, &String.contains?(&1, "future"))
    end

    test "ends_at must be after starts_at", %{centre: c, exam: e} do
      starts = future_starts_at()
      ends = DateTime.add(starts, -1, :hour)

      assert {:error, cs} =
               Slots.create_slot(c, %{
                 "exam_id" => e.id,
                 "starts_at" => starts,
                 "ends_at" => ends,
                 "capacity" => 10
               })

      assert Enum.any?(errors_on(cs).ends_at, &String.contains?(&1, "after"))
    end

    test "capacity must be positive", %{centre: c, exam: e} do
      starts = future_starts_at()
      ends = DateTime.add(starts, 60 * 60, :second)

      assert {:error, cs} =
               Slots.create_slot(c, %{
                 "exam_id" => e.id,
                 "starts_at" => starts,
                 "ends_at" => ends,
                 "capacity" => 0
               })

      assert "must be greater than 0" in errors_on(cs).capacity
    end
  end

  describe "cancel_slot/2" do
    setup ctx do
      {:ok, slot} =
        Slots.create_slot(ctx.centre, %{
          "exam_id" => ctx.exam.id,
          "starts_at" => future_starts_at(),
          "ends_at" => future_starts_at() |> DateTime.add(90 * 60, :second),
          "capacity" => 12
        })

      Map.put(ctx, :slot, slot)
    end

    test "flips status to cancelled + writes audit event",
         %{centre: c, slot: slot} do
      assert {:ok, cancelled} = Slots.cancel_slot(slot, c)
      assert cancelled.status == "cancelled"

      assert [event] = AuditLog.list(event_type: "slot_cancelled", aggregate_id: slot.id)
      assert event.actor_id == c.id
    end

    test "double-cancel is a no-op error", %{centre: c, slot: slot} do
      {:ok, cancelled} = Slots.cancel_slot(slot, c)
      assert {:error, :already_cancelled} = Slots.cancel_slot(cancelled, c)
    end
  end

  describe "list_centre_slots/2" do
    test "returns upcoming open slots for the centre by default",
         %{centre: c, exam: e} do
      future = future_starts_at()

      {:ok, slot1} =
        Slots.create_slot(c, %{
          "exam_id" => e.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 8
        })

      {:ok, slot2} =
        Slots.create_slot(c, %{
          "exam_id" => e.id,
          "starts_at" => DateTime.add(future, 1, :day),
          "ends_at" => DateTime.add(future, 1, :day) |> DateTime.add(60 * 60, :second),
          "capacity" => 8
        })

      {:ok, _} = Slots.cancel_slot(slot2, c)

      ids = Slots.list_centre_slots(c) |> Enum.map(& &1.id)
      assert slot1.id in ids
      refute slot2.id in ids, "cancelled slots excluded by default"
    end

    test ":include_cancelled returns cancelled slots too",
         %{centre: c, exam: e} do
      future = future_starts_at()

      {:ok, slot} =
        Slots.create_slot(c, %{
          "exam_id" => e.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 8
        })

      {:ok, _} = Slots.cancel_slot(slot, c)

      ids = Slots.list_centre_slots(c, include_cancelled: true) |> Enum.map(& &1.id)
      assert slot.id in ids
    end
  end

  describe "get_slot!/1" do
    test "fetches a slot by id", %{centre: c, exam: e} do
      future = future_starts_at()

      {:ok, slot} =
        Slots.create_slot(c, %{
          "exam_id" => e.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 8
        })

      assert Slots.get_slot!(slot.id).id == slot.id
    end
  end
end
