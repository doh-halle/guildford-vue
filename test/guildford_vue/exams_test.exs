defmodule GuildfordVue.ExamsTest do
  @moduledoc """
  Sprint 3 Slice 1 — exam catalogue context. Admin-only domain.
  Each exam has a unique code; archiving is a soft-delete so historical
  bookings keep their exam reference even after a curriculum change.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, AuditLog, Exams}
  alias GuildfordVue.Exams.Exam

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "examscat-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Cat Admin",
        "role" => "superadmin"
      })

    %{admin: admin}
  end

  describe "create_exam/2" do
    test "creates a valid exam + audit event", %{admin: admin} do
      assert {:ok, exam} =
               Exams.create_exam(
                 %{
                   "name" => "DVSA Theory Test (Car)",
                   "code" => "DVSA-CAR",
                   "certification_body" => "DVSA",
                   "description" => "UK car driver theory test",
                   "duration_minutes" => 57,
                   "price_pence" => 2300
                 },
                 admin
               )

      assert exam.name == "DVSA Theory Test (Car)"
      assert exam.code == "DVSA-CAR"
      assert exam.duration_minutes == 57
      assert exam.price_pence == 2300
      refute exam.archived_at

      assert [event] = AuditLog.list(event_type: "exam_created", aggregate_id: exam.id)
      assert event.actor_id == admin.id
      assert event.payload["code"] == "DVSA-CAR"
    end

    test "code must be unique", %{admin: admin} do
      base = %{
        "name" => "x",
        "code" => "DUP",
        "certification_body" => "X",
        "description" => "x",
        "duration_minutes" => 30,
        "price_pence" => 1000
      }

      {:ok, _} = Exams.create_exam(base, admin)

      assert {:error, %Ecto.Changeset{} = cs} =
               Exams.create_exam(Map.put(base, "name", "y"), admin)

      assert "has already been taken" in errors_on(cs).code
    end

    test "validates required fields", %{admin: admin} do
      assert {:error, %Ecto.Changeset{} = cs} = Exams.create_exam(%{}, admin)
      errors = errors_on(cs)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.code
      assert "can't be blank" in errors.certification_body
      assert "can't be blank" in errors.duration_minutes
      assert "can't be blank" in errors.price_pence
    end

    test "duration_minutes must be positive", %{admin: admin} do
      attrs = %{
        "name" => "x",
        "code" => "NEG",
        "certification_body" => "X",
        "duration_minutes" => 0,
        "price_pence" => 100
      }

      assert {:error, cs} = Exams.create_exam(attrs, admin)
      assert "must be greater than 0" in errors_on(cs).duration_minutes
    end

    test "price_pence cannot be negative", %{admin: admin} do
      attrs = %{
        "name" => "x",
        "code" => "NEG2",
        "certification_body" => "X",
        "duration_minutes" => 30,
        "price_pence" => -100
      }

      assert {:error, cs} = Exams.create_exam(attrs, admin)
      assert "must be greater than or equal to 0" in errors_on(cs).price_pence
    end

    test "code is upcased for consistency", %{admin: admin} do
      {:ok, exam} =
        Exams.create_exam(
          %{
            "name" => "x",
            "code" => "lower-case",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 100
          },
          admin
        )

      assert exam.code == "LOWER-CASE"
    end
  end

  describe "update_exam/3" do
    setup %{admin: admin} do
      {:ok, exam} =
        Exams.create_exam(
          %{
            "name" => "Original",
            "code" => "UPD",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 1000
          },
          admin
        )

      %{exam: exam}
    end

    test "updates editable fields + audits", %{admin: admin, exam: exam} do
      assert {:ok, updated} =
               Exams.update_exam(
                 exam,
                 %{"name" => "Updated", "price_pence" => 2000},
                 admin
               )

      assert updated.name == "Updated"
      assert updated.price_pence == 2000
      assert updated.code == "UPD", "code should be immutable"

      assert [event] = AuditLog.list(event_type: "exam_updated", aggregate_id: exam.id)
      assert event.actor_id == admin.id
    end

    test "does NOT allow changing the code", %{admin: admin, exam: exam} do
      {:ok, updated} = Exams.update_exam(exam, %{"code" => "OTHER"}, admin)
      assert updated.code == "UPD"
    end

    test "no audit event if nothing actually changed", %{admin: admin, exam: exam} do
      {:ok, _} = Exams.update_exam(exam, %{"name" => "Original"}, admin)
      assert AuditLog.list(event_type: "exam_updated", aggregate_id: exam.id) == []
    end
  end

  describe "archive_exam/2 (soft delete)" do
    setup %{admin: admin} do
      {:ok, exam} =
        Exams.create_exam(
          %{
            "name" => "Old",
            "code" => "OLD",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 1000
          },
          admin
        )

      %{exam: exam}
    end

    test "sets archived_at + audits", %{admin: admin, exam: exam} do
      assert {:ok, archived} = Exams.archive_exam(exam, admin)
      assert archived.archived_at

      assert [_] = AuditLog.list(event_type: "exam_archived", aggregate_id: exam.id)
    end

    test "double-archive is a no-op", %{admin: admin, exam: exam} do
      {:ok, archived} = Exams.archive_exam(exam, admin)
      assert {:error, :already_archived} = Exams.archive_exam(archived, admin)
    end
  end

  describe "list_exams/1" do
    setup %{admin: admin} do
      {:ok, live1} =
        Exams.create_exam(
          %{
            "name" => "Live 1",
            "code" => "L1",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 100
          },
          admin
        )

      {:ok, live2} =
        Exams.create_exam(
          %{
            "name" => "Live 2",
            "code" => "L2",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 100
          },
          admin
        )

      {:ok, archived} =
        Exams.create_exam(
          %{
            "name" => "Was Live",
            "code" => "OLD",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 100
          },
          admin
        )

      {:ok, archived} = Exams.archive_exam(archived, admin)

      %{live1: live1, live2: live2, archived: archived}
    end

    test "default returns only live exams ordered by name", %{
      live1: l1,
      live2: l2,
      archived: a
    } do
      result = Exams.list_exams()
      ids = Enum.map(result, & &1.id)
      assert l1.id in ids
      assert l2.id in ids
      refute a.id in ids
    end

    test "include_archived: true returns archived too", %{archived: a} do
      assert Enum.any?(Exams.list_exams(include_archived: true), &(&1.id == a.id))
    end

    test "search: filters by name or code (ILIKE)", %{live1: l1} do
      assert [hit] = Exams.list_exams(search: "live 1")
      assert hit.id == l1.id

      assert [hit] = Exams.list_exams(search: "l1")
      assert hit.id == l1.id
    end
  end

  describe "get_exam_by_code/1" do
    test "case-insensitive lookup", %{admin: admin} do
      {:ok, exam} =
        Exams.create_exam(
          %{
            "name" => "x",
            "code" => "case-test",
            "certification_body" => "X",
            "duration_minutes" => 30,
            "price_pence" => 100
          },
          admin
        )

      assert Exams.get_exam_by_code("case-test").id == exam.id
      assert Exams.get_exam_by_code("CASE-TEST").id == exam.id
    end

    test "returns nil for unknown code" do
      refute Exams.get_exam_by_code("NOPE")
    end
  end

  describe "change_exam/2 (form helper)" do
    test "returns an Exam changeset with the given attrs" do
      cs = Exams.change_exam(%Exam{}, %{"name" => "x"})
      assert %Ecto.Changeset{} = cs
      assert cs.changes.name == "x"
    end
  end
end
