defmodule GuildfordVue.Centres.CentreServerTest do
  @moduledoc """
  Sprint 4 Slice 2 — per-centre GenServer + supervision tree.

  Each centre gets its own process holding its slot inventory in
  immutable state. The process is the concurrency boundary that
  serialises booking requests; the DB is the durability layer.

  Tests cover lifecycle (start, stop, restart), name lookup, state
  loading from DB on init, and supervisor restart behaviour.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Centres.CentreServer

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "cs-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "cs-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "CS Centre",
        "address_line_1" => "1 St",
        "city" => "Cardiff",
        "postcode" => "CF10 1EP"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "CS Exam",
          "code" => "CSX",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    on_exit(fn ->
      # Best-effort: stop any leftover server so async tests don't pin pids
      _ = Centres.stop_centre(centre.id)
    end)

    %{admin: admin, centre: centre, exam: exam}
  end

  describe "start_link/1 + lookup" do
    test "starts a server registered under the centre id", %{centre: c} do
      assert {:ok, pid} = Centres.start_centre(c.id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Lookup returns the same pid.
      assert {:ok, ^pid} = Centres.whereis(c.id)
    end

    test "start_centre is idempotent (returns existing pid)", %{centre: c} do
      assert {:ok, pid1} = Centres.start_centre(c.id)
      assert {:ok, pid2} = Centres.start_centre(c.id)
      assert pid1 == pid2
    end

    test "whereis returns :not_running when none started", %{centre: c} do
      assert {:error, :not_running} = Centres.whereis(c.id)
    end
  end

  describe "slot state from DB on init" do
    setup ctx do
      future = DateTime.utc_now() |> DateTime.add(7, :day)

      {:ok, s1} =
        Slots.create_slot(ctx.centre, %{
          "exam_id" => ctx.exam.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 10
        })

      {:ok, s2} =
        Slots.create_slot(ctx.centre, %{
          "exam_id" => ctx.exam.id,
          "starts_at" => DateTime.add(future, 1, :day),
          "ends_at" => DateTime.add(future, 1, :day) |> DateTime.add(60 * 60, :second),
          "capacity" => 5
        })

      Map.merge(ctx, %{s1: s1, s2: s2})
    end

    test "init/1 loads centre's slots into memory", %{centre: c, s1: s1, s2: s2} do
      {:ok, pid} = Centres.start_centre(c.id)
      slots = CentreServer.list_slots(pid)
      ids = Enum.map(slots, & &1.id) |> Enum.sort()
      assert ids == Enum.sort([s1.id, s2.id])
    end

    test "ignores other centres' slots", %{centre: c, exam: e} = ctx do
      admin = Map.fetch!(ctx, :admin)

      {:ok, other_centre} =
        ExamCentres.register_exam_centre(%{
          "email" => "cs-other@example.com",
          "password" => "supersecret123!A",
          "name" => "Other",
          "address_line_1" => "1 St",
          "city" => "Edinburgh",
          "postcode" => "EH1 1YZ"
        })

      {:ok, other_centre} = ExamCentres.approve(other_centre, admin)
      {:ok, _} = ExamCentres.set_offerings(other_centre, [e.id], other_centre)

      future = DateTime.utc_now() |> DateTime.add(7, :day)

      {:ok, _other_slot} =
        Slots.create_slot(other_centre, %{
          "exam_id" => e.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 10
        })

      {:ok, pid} = Centres.start_centre(c.id)
      # The other centre's slot must not appear in this server's list.
      slot_centre_ids =
        pid
        |> CentreServer.list_slots()
        |> Enum.map(& &1.exam_centre_id)
        |> Enum.uniq()

      assert slot_centre_ids in [[c.id], []]
    end
  end

  describe "supervisor restart" do
    test "after a crash, supervisor restarts with state reloaded from DB",
         %{centre: c, exam: e} do
      future = DateTime.utc_now() |> DateTime.add(7, :day)

      {:ok, slot} =
        Slots.create_slot(c, %{
          "exam_id" => e.id,
          "starts_at" => future,
          "ends_at" => DateTime.add(future, 60 * 60, :second),
          "capacity" => 10
        })

      slot_id = slot.id
      {:ok, pid1} = Centres.start_centre(c.id)
      assert [^slot_id] = pid1 |> CentreServer.list_slots() |> Enum.map(& &1.id)

      # Inject a crash.
      Process.exit(pid1, :kill)

      # Wait briefly for the DynamicSupervisor to restart, with a
      # bounded retry — registry lookups are eventually consistent
      # under a restart.
      pid2 =
        Enum.reduce_while(1..50, nil, fn _, _ ->
          case Centres.whereis(c.id) do
            {:ok, p} when is_pid(p) and p != pid1 -> {:halt, p}
            _ -> Process.sleep(20) && {:cont, nil}
          end
        end)

      assert is_pid(pid2)
      assert pid2 != pid1
      assert [^slot_id] = pid2 |> CentreServer.list_slots() |> Enum.map(& &1.id)
    end
  end
end
