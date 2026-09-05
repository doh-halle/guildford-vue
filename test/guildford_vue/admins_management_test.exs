defmodule GuildfordVue.AdminsManagementTest do
  @moduledoc """
  Sprint 2 Slice 5 — admin invite + role assignment.
  Only superadmins should be making these calls; authorisation is
  enforced at the LiveView boundary, not in the context. The context
  records the actor in the audit log so the policy decision is
  retrievable from the log even if the LV layer is bypassed.
  """
  use GuildfordVue.DataCase, async: true
  import Swoosh.TestAssertions

  alias GuildfordVue.{Admins, AuditLog}

  setup do
    {:ok, super_admin} =
      Admins.register_admin(%{
        "email" => "admgmt-boss@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Boss",
        "role" => "superadmin"
      })

    {:ok, operator} =
      Admins.register_admin(%{
        "email" => "admgmt-op@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Op",
        "role" => "operator"
      })

    %{super_admin: super_admin, operator: operator}
  end

  describe "invite_admin/2" do
    test "creates a new admin and returns {:ok, admin, reset_token}",
         %{super_admin: super_admin} do
      assert {:ok, new_admin, reset_token} =
               Admins.invite_admin(
                 %{"email" => "new@guildfordvue.test", "name" => "New One", "role" => "operator"},
                 super_admin
               )

      assert new_admin.email == "new@guildfordvue.test"
      assert new_admin.role == "operator"
      assert is_binary(reset_token)
      assert String.length(reset_token) > 16

      # New admin can complete the invite via reset-password
      assert {:ok, _updated} =
               Admins.reset_password(reset_token, %{"password" => "freshpassword!12"})
    end

    test "writes an admin_invited audit event with the inviter as actor",
         %{super_admin: super_admin} do
      {:ok, new_admin, _} =
        Admins.invite_admin(
          %{"email" => "another@guildfordvue.test", "name" => "Another", "role" => "operator"},
          super_admin
        )

      [event] = AuditLog.list(event_type: "admin_invited", aggregate_id: new_admin.id)
      assert event.actor_id == super_admin.id
      assert event.actor_type == "admin"
      assert event.payload["invited_email"] == "another@guildfordvue.test"
      assert event.payload["invited_role"] == "operator"
    end

    test "sends an invitation email containing a setup link",
         %{super_admin: super_admin} do
      {:ok, _new_admin, _token} =
        Admins.invite_admin(
          %{"email" => "withmail@guildfordvue.test", "name" => "Mail", "role" => "operator"},
          super_admin
        )

      assert_email_sent(fn email ->
        assert email.subject =~ "invited"
        assert email.to == [{"Mail", "withmail@guildfordvue.test"}]
        text = email.text_body
        assert text =~ "set up your password"
        assert text =~ "/backoffice/reset-password/"
      end)
    end

    test "rejects duplicate email", %{super_admin: super_admin} do
      Admins.invite_admin(
        %{"email" => "dupe@guildfordvue.test", "name" => "Dupe", "role" => "operator"},
        super_admin
      )

      assert {:error, %Ecto.Changeset{} = cs} =
               Admins.invite_admin(
                 %{"email" => "dupe@guildfordvue.test", "name" => "Dupe2", "role" => "operator"},
                 super_admin
               )

      assert "has already been taken" in errors_on(cs).email
    end

    test "rejects invalid role", %{super_admin: super_admin} do
      assert {:error, %Ecto.Changeset{} = cs} =
               Admins.invite_admin(
                 %{
                   "email" => "bad@guildfordvue.test",
                   "name" => "Bad",
                   "role" => "evil_overlord"
                 },
                 super_admin
               )

      assert Enum.any?(errors_on(cs).role, &String.contains?(&1, "must be one of"))
    end
  end

  describe "change_role/3" do
    test "promotes an operator to superadmin and audits it",
         %{super_admin: super_admin, operator: operator} do
      assert {:ok, updated} = Admins.change_role(operator, "superadmin", super_admin)
      assert updated.role == "superadmin"

      [event] = AuditLog.list(event_type: "admin_role_changed", aggregate_id: operator.id)
      assert event.actor_id == super_admin.id
      assert event.payload["from"] == "operator"
      assert event.payload["to"] == "superadmin"
    end

    test "rejects invalid role", %{super_admin: super_admin, operator: operator} do
      assert {:error, :invalid_role} = Admins.change_role(operator, "rogue", super_admin)
    end

    test "is a no-op when the role doesn't actually change (no audit event)",
         %{super_admin: super_admin, operator: operator} do
      {:ok, _} = Admins.change_role(operator, "operator", super_admin)
      assert AuditLog.list(event_type: "admin_role_changed", aggregate_id: operator.id) == []
    end
  end

  describe "suspend/2 + reactivate/2 (admin actor → audit)" do
    test "suspend/2 writes an admin_suspended audit event",
         %{super_admin: super_admin, operator: operator} do
      {:ok, _} = Admins.suspend(operator, super_admin)
      [event] = AuditLog.list(event_type: "admin_suspended", aggregate_id: operator.id)
      assert event.actor_id == super_admin.id
    end

    test "reactivate/2 writes an admin_reactivated audit event",
         %{super_admin: super_admin, operator: operator} do
      {:ok, suspended} = Admins.suspend(operator, super_admin)
      {:ok, _} = Admins.reactivate(suspended, super_admin)
      assert [_] = AuditLog.list(event_type: "admin_reactivated", aggregate_id: operator.id)
    end
  end
end
