defmodule GuildfordVue.ExamCentresApprovalTest do
  @moduledoc """
  Sprint 2 Slice 3: admin actions on exam centres (approve, reject,
  suspend, reactivate). Each action writes an audit-log event and
  triggers an email to the centre.

  Lives in its own file so the existing `exam_centres_test.exs`
  remains focused on the auth/login surface that Sprint 1 established.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, AuditLog, ExamCentres}

  import Swoosh.TestAssertions

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Approver"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "leeds@example.com",
        "password" => "supersecret123!A",
        "name" => "Leeds Test Centre",
        "address_line_1" => "1 Boar Lane",
        "city" => "Leeds",
        "postcode" => "LS1 1UR",
        "latitude" => 53.7958,
        "longitude" => -1.5455
      })

    %{admin: admin, centre: centre}
  end

  describe "approve/2 — audit + email side effects" do
    test "writes a centre_approved audit event with the admin as actor",
         %{admin: admin, centre: centre} do
      {:ok, _approved} = ExamCentres.approve(centre, admin)

      [event | _] = AuditLog.list(event_type: "centre_approved")
      assert event.event_type == "centre_approved"
      assert event.aggregate_id == centre.id
      assert event.actor_id == admin.id
      assert event.actor_type == "admin"
      assert event.payload["centre_name"] == "Leeds Test Centre"
      assert event.payload["centre_email"] == "leeds@example.com"
    end

    test "sends an approval email to the centre", %{admin: admin, centre: centre} do
      {:ok, _approved} = ExamCentres.approve(centre, admin)
      assert_email_sent(to: [{"Leeds Test Centre", "leeds@example.com"}])
    end

    test "writes no audit event if the approval fails (already_approved)",
         %{admin: admin, centre: centre} do
      {:ok, approved} = ExamCentres.approve(centre, admin)
      assert {:error, :already_approved} = ExamCentres.approve(approved, admin)
      assert length(AuditLog.list(event_type: "centre_approved")) == 1
    end
  end

  describe "reject/3" do
    test "rejects a pending centre with a reason", %{admin: admin, centre: centre} do
      assert {:ok, rejected} =
               ExamCentres.reject(centre, admin, "Insufficient evidence of accreditation")

      assert rejected.status == "rejected"
      assert rejected.rejection_reason == "Insufficient evidence of accreditation"
      assert rejected.rejected_at
      assert rejected.rejected_by_admin_id == admin.id
    end

    test "writes a centre_rejected audit event including the reason",
         %{admin: admin, centre: centre} do
      {:ok, _} = ExamCentres.reject(centre, admin, "Insufficient evidence")

      [event] = AuditLog.list(event_type: "centre_rejected")
      assert event.actor_id == admin.id
      assert event.payload["rejection_reason"] == "Insufficient evidence"
      assert event.payload["centre_email"] == "leeds@example.com"
    end

    test "sends a rejection email to the centre", %{admin: admin, centre: centre} do
      {:ok, _} = ExamCentres.reject(centre, admin, "Missing accreditation")
      assert_email_sent(to: [{"Leeds Test Centre", "leeds@example.com"}])
    end

    test "a rejected centre cannot log in (status hides them)",
         %{admin: admin, centre: centre} do
      {:ok, _} = ExamCentres.reject(centre, admin, "no good")

      assert {:error, :invalid} =
               ExamCentres.authenticate("leeds@example.com", "supersecret123!A")
    end

    test "rejecting an approved centre fails (approved→rejected is not a valid transition)",
         %{admin: admin, centre: centre} do
      {:ok, approved} = ExamCentres.approve(centre, admin)

      assert {:error, :cannot_reject_non_pending} =
               ExamCentres.reject(approved, admin, "too late")
    end

    test "rejection_reason is required", %{admin: admin, centre: centre} do
      assert {:error, :reason_required} = ExamCentres.reject(centre, admin, "")
      assert {:error, :reason_required} = ExamCentres.reject(centre, admin, nil)
    end
  end

  describe "suspend/2 — audit side effect" do
    test "writes a centre_suspended audit event when an admin actor is given",
         %{admin: admin, centre: centre} do
      {:ok, approved} = ExamCentres.approve(centre, admin)
      {:ok, _suspended} = ExamCentres.suspend(approved, admin)

      [event] = AuditLog.list(event_type: "centre_suspended")
      assert event.actor_id == admin.id
      assert event.aggregate_id == centre.id
    end
  end

  describe "reactivate/2 — audit side effect" do
    test "writes a centre_reactivated audit event", %{admin: admin, centre: centre} do
      {:ok, approved} = ExamCentres.approve(centre, admin)
      {:ok, suspended} = ExamCentres.suspend(approved, admin)
      {:ok, _reactivated} = ExamCentres.reactivate(suspended, admin)

      [event] = AuditLog.list(event_type: "centre_reactivated")
      assert event.actor_id == admin.id
    end
  end

  describe "list_pending_centres/0 (excludes rejected centres)" do
    test "rejected centres do not appear in pending list", %{admin: admin, centre: centre} do
      assert centre.id in Enum.map(ExamCentres.list_pending_centres(), & &1.id)

      {:ok, _} = ExamCentres.reject(centre, admin, "no good")

      refute centre.id in Enum.map(ExamCentres.list_pending_centres(), & &1.id)
    end
  end
end
