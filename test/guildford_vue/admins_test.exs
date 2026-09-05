defmodule GuildfordVue.AdminsTest do
  @moduledoc """
  Tests for the `GuildfordVue.Admins` context — the platform-administrator
  auth scope. Mirror structure of `GuildfordVue.CandidatesTest` so the same
  reviewer can audit both with one mental model.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.Admins
  alias GuildfordVue.Admins.{Admin, AdminToken}

  @valid_attrs %{
    "email" => "operator@guildfordvue.test",
    "password" => "supersecret123!A",
    "name" => "Ops User"
  }

  describe "register_admin/1" do
    test "creates an admin with default role :operator" do
      assert {:ok, %Admin{} = admin} = Admins.register_admin(@valid_attrs)
      assert admin.email == "operator@guildfordvue.test"
      assert admin.name == "Ops User"
      assert admin.role == "operator"
      assert is_binary(admin.hashed_password)
      refute admin.hashed_password == "supersecret123!A"
    end

    test "honours an explicit :superadmin role" do
      attrs = Map.put(@valid_attrs, "role", "superadmin")
      assert {:ok, admin} = Admins.register_admin(attrs)
      assert admin.role == "superadmin"
    end

    test "rejects unknown roles" do
      attrs = Map.put(@valid_attrs, "role", "saboteur")
      assert {:error, cs} = Admins.register_admin(attrs)
      assert Enum.any?(errors_on(cs).role, &(&1 =~ "must be one of"))
    end

    test "rejects taken email (case-insensitive)" do
      assert {:ok, _} = Admins.register_admin(@valid_attrs)
      attrs = %{@valid_attrs | "email" => "OPERATOR@GUILDFORDVUE.TEST"}
      assert {:error, cs} = Admins.register_admin(attrs)
      assert "has already been taken" in errors_on(cs).email
    end
  end

  describe "get_admin_by_email_and_password/2" do
    setup do
      {:ok, admin} = Admins.register_admin(@valid_attrs)
      %{admin: admin}
    end

    test "succeeds with right credentials", %{admin: admin} do
      assert Admins.get_admin_by_email_and_password(admin.email, "supersecret123!A").id ==
               admin.id
    end

    test "fails silently with wrong password" do
      refute Admins.get_admin_by_email_and_password("operator@guildfordvue.test", "wrong")
    end

    test "fails silently with missing email (no leak)" do
      refute Admins.get_admin_by_email_and_password("nobody@x", "supersecret123!A")
    end

    test "rejects suspended admins", %{admin: admin} do
      {:ok, _} = Admins.suspend(admin)
      refute Admins.get_admin_by_email_and_password(admin.email, "supersecret123!A")
    end
  end

  describe "session tokens" do
    test "generate, lookup, revoke" do
      {:ok, admin} = Admins.register_admin(@valid_attrs)
      token = Admins.generate_session_token(admin)
      assert Admins.get_admin_by_session_token(token).id == admin.id
      :ok = Admins.delete_session_token(token)
      refute Admins.get_admin_by_session_token(token)

      # And the token row exists in admin_tokens with context "session"
      assert is_nil(Repo.get_by(AdminToken, token: token))
    end
  end

  describe "password reset" do
    test "rotates the hash via one-time token" do
      {:ok, admin} = Admins.register_admin(@valid_attrs)

      {:ok, token} =
        Admins.deliver_password_reset_instructions(admin, fn t -> "url " <> t end)

      {:ok, updated} = Admins.reset_password(token, %{"password" => "newpassword456!B"})
      refute updated.hashed_password == admin.hashed_password

      assert Admins.get_admin_by_email_and_password(admin.email, "newpassword456!B").id ==
               admin.id

      # single-use
      assert {:error, :invalid_token} =
               Admins.reset_password(token, %{"password" => "yetanother789!C"})
    end
  end

  describe "list_admins/0" do
    test "returns all admins" do
      {:ok, _} = Admins.register_admin(@valid_attrs)
      {:ok, _} = Admins.register_admin(%{@valid_attrs | "email" => "two@guildfordvue.test"})
      assert length(Admins.list_admins()) == 2
    end
  end
end
