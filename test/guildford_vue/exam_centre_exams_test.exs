defmodule GuildfordVue.ExamCentreExamsTest do
  @moduledoc """
  Sprint 3 Slice 6 — centre ↔ exam many-to-many offerings.

  A centre publishes a curated subset of the admin-managed exam
  catalogue. Add/remove is per-event audit-logged so we can answer
  "when did Manchester start offering CCNA?".
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, AuditLog, ExamCentres, Exams}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "offerings-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "A",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "offerings-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Offerings Centre",
        "address_line_1" => "1 St",
        "city" => "Leeds",
        "postcode" => "LS1 1UR"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, e1} = create_exam(admin, "E1", "Exam One")
    {:ok, e2} = create_exam(admin, "E2", "Exam Two")
    {:ok, e3} = create_exam(admin, "E3", "Exam Three")

    %{admin: admin, centre: centre, e1: e1, e2: e2, e3: e3}
  end

  defp create_exam(admin, code, name) do
    Exams.create_exam(
      %{
        "name" => name,
        "code" => code,
        "certification_body" => "X",
        "duration_minutes" => 60,
        "price_pence" => 1000
      },
      admin
    )
  end

  describe "list_offerings/1" do
    test "returns [] when no offerings", %{centre: c} do
      assert ExamCentres.list_offerings(c) == []
    end
  end

  describe "set_offerings/3" do
    test "adds the given exam IDs and lists them back",
         %{centre: c, e1: e1, e2: e2} do
      assert {:ok, _} = ExamCentres.set_offerings(c, [e1.id, e2.id], c)

      ids = ExamCentres.list_offerings(c) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([e1.id, e2.id])
    end

    test "removes exams not present in the new list (overwrite semantics)",
         %{centre: c, e1: e1, e2: e2, e3: e3} do
      {:ok, _} = ExamCentres.set_offerings(c, [e1.id, e2.id], c)
      {:ok, _} = ExamCentres.set_offerings(c, [e3.id], c)

      ids = ExamCentres.list_offerings(c) |> Enum.map(& &1.id)
      assert ids == [e3.id]
    end

    test "writes per-exam audit events (added / removed)",
         %{centre: c, e1: e1, e2: e2} do
      {:ok, _} = ExamCentres.set_offerings(c, [e1.id, e2.id], c)
      added = AuditLog.list(event_type: "centre_offering_added", aggregate_id: c.id)
      assert length(added) == 2

      {:ok, _} = ExamCentres.set_offerings(c, [e1.id], c)
      removed = AuditLog.list(event_type: "centre_offering_removed", aggregate_id: c.id)
      assert length(removed) == 1

      [event] = removed
      assert event.payload["exam_code"] == "E2"
    end

    test "no-op when the new list equals the current one (no audit events)",
         %{centre: c, e1: e1} do
      {:ok, _} = ExamCentres.set_offerings(c, [e1.id], c)

      n_before =
        length(AuditLog.list(event_type: "centre_offering_added", aggregate_id: c.id))

      {:ok, _} = ExamCentres.set_offerings(c, [e1.id], c)

      n_after =
        length(AuditLog.list(event_type: "centre_offering_added", aggregate_id: c.id))

      assert n_after == n_before
    end

    test "ignores non-existent exam IDs (silently drops them)", %{centre: c, e1: e1} do
      bogus = Ecto.UUID.generate()
      assert {:ok, _} = ExamCentres.set_offerings(c, [e1.id, bogus], c)
      ids = ExamCentres.list_offerings(c) |> Enum.map(& &1.id)
      assert ids == [e1.id]
    end

    test "ignores archived exams", %{centre: c, e1: e1, e2: e2, admin: admin} do
      {:ok, _} = Exams.archive_exam(e2, admin)

      {:ok, _} = ExamCentres.set_offerings(c, [e1.id, e2.id], c)
      ids = ExamCentres.list_offerings(c) |> Enum.map(& &1.id)
      assert ids == [e1.id]
    end
  end

  describe "centres_offering/1 (inverse lookup)" do
    test "returns the centres that offer a given exam",
         %{centre: c, e1: e1} do
      {:ok, _} = ExamCentres.set_offerings(c, [e1.id], c)
      assert [hit] = ExamCentres.centres_offering(e1.id)
      assert hit.id == c.id
    end
  end
end
