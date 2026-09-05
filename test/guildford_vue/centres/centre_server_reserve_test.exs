defmodule GuildfordVue.Centres.CentreServerReserveTest do
  @moduledoc """
  Sprint 4 Slice 3 — reserve + release primitives. The no-double-
  booking invariant is the dissertation's headline property
  (PRD §2.2 goal 3); these tests exercise it directly.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Centres.CentreServer

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "reserve-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "reserve-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Reserve Centre",
        "address_line_1" => "1 St",
        "city" => "Liverpool",
        "postcode" => "L1 8JQ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Reserve Exam",
          "code" => "RSV",
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

    %{centre: centre, exam: exam, slot: slot, pid: pid}
  end

  describe "reserve_slot/2 (sequential)" do
    test "decrements available_count by 1", %{pid: pid, slot: slot} do
      assert {:ok, updated} = CentreServer.reserve_slot(pid, slot.id)
      assert updated.available_count == slot.capacity - 1
      assert updated.status == "open"
    end

    test "DB row is updated alongside in-memory state",
         %{pid: pid, slot: slot} do
      {:ok, _} = CentreServer.reserve_slot(pid, slot.id)
      reloaded = Slots.get_slot!(slot.id)
      assert reloaded.available_count == slot.capacity - 1
    end

    test "filling capacity flips status to full + final reserve still succeeds",
         %{pid: pid, slot: slot} do
      for _ <- 1..(slot.capacity - 1) do
        assert {:ok, _} = CentreServer.reserve_slot(pid, slot.id)
      end

      assert {:ok, final} = CentreServer.reserve_slot(pid, slot.id)
      assert final.available_count == 0
      assert final.status == "full"
    end

    test "reserve after sold-out returns {:error, :sold_out}",
         %{pid: pid, slot: slot} do
      for _ <- 1..slot.capacity do
        {:ok, _} = CentreServer.reserve_slot(pid, slot.id)
      end

      assert {:error, :sold_out} = CentreServer.reserve_slot(pid, slot.id)
    end

    test "unknown slot id returns :slot_not_in_inventory", %{pid: pid} do
      assert {:error, :slot_not_in_inventory} =
               CentreServer.reserve_slot(pid, Ecto.UUID.generate())
    end

    test "cancelled slot is not reservable", %{pid: pid, centre: c, slot: slot} do
      {:ok, _cancelled} = CentreServer.cancel_slot(pid, slot.id, c)

      assert {:error, :slot_not_in_inventory} =
               CentreServer.reserve_slot(pid, slot.id)
    end
  end

  describe "release_slot/2 (sequential)" do
    test "increments available_count by 1", %{pid: pid, slot: slot} do
      {:ok, _} = CentreServer.reserve_slot(pid, slot.id)
      {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

      assert {:ok, released} = CentreServer.release_slot(pid, slot.id)
      assert released.available_count == slot.capacity - 1
    end

    test "release on a full slot flips it back to open",
         %{pid: pid, slot: slot} do
      for _ <- 1..slot.capacity, do: {:ok, _} = CentreServer.reserve_slot(pid, slot.id)

      assert {:ok, released} = CentreServer.release_slot(pid, slot.id)
      assert released.status == "open"
    end

    test "release at capacity returns :at_capacity (no over-release)",
         %{pid: pid, slot: slot} do
      assert {:error, :at_capacity} = CentreServer.release_slot(pid, slot.id)
    end
  end

  describe "PROPERTY: no double-booking under concurrent stress" do
    @describetag :stress

    test "exactly capacity calls succeed; the rest return :sold_out",
         %{pid: pid, slot: slot} do
      n_attempts = slot.capacity * 4

      results =
        1..n_attempts
        |> Task.async_stream(
          fn _ -> CentreServer.reserve_slot(pid, slot.id) end,
          max_concurrency: 64,
          ordered: false
        )
        |> Enum.map(fn {:ok, r} -> r end)

      ok_count = Enum.count(results, &match?({:ok, _}, &1))
      sold_out_count = Enum.count(results, &match?({:error, :sold_out}, &1))

      assert ok_count == slot.capacity,
             "exactly #{slot.capacity} reservations should succeed, got #{ok_count}"

      assert sold_out_count == n_attempts - slot.capacity,
             "the remaining #{n_attempts - slot.capacity} should be :sold_out, got #{sold_out_count}"

      # DB state matches in-memory state.
      assert Slots.get_slot!(slot.id).available_count == 0
      assert Slots.get_slot!(slot.id).status == "full"
    end
  end

  describe "PROPERTY: cancel/release reverses state" do
    @describetag :stress

    test "interleaved reserve + release leaves available_count unchanged",
         %{pid: pid, slot: slot} do
      # Reserve 4, release 4 in interleaved tasks. Net change should be 0.
      pairs = 4

      reserves =
        Task.async_stream(1..pairs, fn _ -> CentreServer.reserve_slot(pid, slot.id) end,
          max_concurrency: 8
        )
        |> Enum.map(fn {:ok, r} -> r end)

      # All reserves must have succeeded — capacity is 8, we asked for 4.
      assert Enum.all?(reserves, &match?({:ok, _}, &1))

      releases =
        Task.async_stream(1..pairs, fn _ -> CentreServer.release_slot(pid, slot.id) end,
          max_concurrency: 8
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.all?(releases, &match?({:ok, _}, &1))

      assert Slots.get_slot!(slot.id).available_count == slot.capacity
      assert Slots.get_slot!(slot.id).status == "open"
    end
  end
end
