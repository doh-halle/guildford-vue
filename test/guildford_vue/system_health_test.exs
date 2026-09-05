defmodule GuildfordVue.SystemHealthTest do
  @moduledoc """
  Sprint 10 Slice 2 — system health probes. Read-only
  introspection of the OTP tree.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Centres, ExamCentres, SystemHealth}

  defp seed_centre do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "sys-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "sys-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Sys Centre",
        "address_line_1" => "1 St",
        "city" => "Bath",
        "postcode" => "BA1 1LT"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)
    centre
  end

  describe "process_count/0" do
    test "returns a positive integer" do
      count = SystemHealth.process_count()
      assert is_integer(count)
      assert count > 0
    end
  end

  describe "running_centres/0" do
    test "returns a list (possibly empty)" do
      assert is_list(SystemHealth.running_centres())
    end

    test "lists each pid + registered centre_id after starting one" do
      centre = seed_centre()
      {:ok, pid} = Centres.start_centre(centre.id)
      on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

      assert Enum.any?(SystemHealth.running_centres(), fn entry ->
               entry.centre_id == centre.id and entry.pid == pid
             end)
    end

    test "each entry carries a mailbox depth + status + memory" do
      centre = seed_centre()
      {:ok, _pid} = Centres.start_centre(centre.id)
      on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

      entry = Enum.find(SystemHealth.running_centres(), &(&1.centre_id == centre.id))
      assert is_map(entry)
      assert is_integer(entry.mailbox) and entry.mailbox >= 0

      assert entry.status in [
               :running,
               :waiting,
               :runnable,
               :suspended,
               :exiting,
               :garbage_collecting
             ]

      assert is_integer(entry.memory) and entry.memory > 0
    end
  end

  describe "supervision_tree/0" do
    test "returns a nested tree rooted at the top supervisor" do
      tree = SystemHealth.supervision_tree()

      assert tree.name == GuildfordVue.Supervisor

      assert Enum.any?(tree.children, fn child ->
               child.name == GuildfordVue.Centres.Supervisor
             end)
    end

    test "children of Centres.Supervisor include the Registry + DynamicSupervisor" do
      tree = SystemHealth.supervision_tree()

      centres = Enum.find(tree.children, fn c -> c.name == GuildfordVue.Centres.Supervisor end)

      names = Enum.map(centres.children, & &1.name)
      assert GuildfordVue.Centres.Registry in names
      assert GuildfordVue.Centres.DynamicSupervisor in names
    end
  end
end
