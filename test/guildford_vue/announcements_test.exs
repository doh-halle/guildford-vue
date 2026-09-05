defmodule GuildfordVue.AnnouncementsTest do
  @moduledoc """
  Sprint 11 Slice 1 — global broadcast banner.

  The current banner is at most one row in the database; admins
  set or clear it. Subscribers (LiveViews) receive a PubSub
  `{:announcement_changed, current}` event so they can re-render
  without polling.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Announcements}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "an-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    on_exit(fn -> Announcements.clear() end)

    %{admin: admin}
  end

  describe "current/0" do
    test "returns nil when no announcement is posted" do
      :ok = Announcements.clear()
      assert Announcements.current() == nil
    end

    test "returns the announcement after post/2", ctx do
      {:ok, a} = Announcements.post("Scheduled maintenance tonight 22:00 UTC.", ctx.admin)
      reloaded = Announcements.current()

      assert reloaded.id == a.id
      assert reloaded.text == "Scheduled maintenance tonight 22:00 UTC."
      assert reloaded.posted_by_admin_id == ctx.admin.id
    end
  end

  describe "post/2" do
    test "replaces a previous announcement (only one is current)", ctx do
      {:ok, _first} = Announcements.post("First message", ctx.admin)
      {:ok, second} = Announcements.post("Second message", ctx.admin)

      cur = Announcements.current()
      assert cur.id == second.id
      assert cur.text == "Second message"
    end

    test "rejects blank text", ctx do
      assert {:error, cs} = Announcements.post("   ", ctx.admin)
      assert errors_on(cs)[:text]
    end

    test "rejects text longer than 280 chars", ctx do
      long = String.duplicate("a", 281)
      assert {:error, cs} = Announcements.post(long, ctx.admin)
      assert errors_on(cs)[:text]
    end

    test "writes an audit log entry", ctx do
      {:ok, _} = Announcements.post("Maintenance window", ctx.admin)
      events = GuildfordVue.AuditLog.list(event_type: "announcement_posted", limit: 5)
      assert Enum.any?(events, &(&1.actor_id == ctx.admin.id))
    end

    test "broadcasts {:announcement_changed, _} to subscribers", ctx do
      :ok = Announcements.subscribe()
      {:ok, posted} = Announcements.post("Heads-up", ctx.admin)

      assert_receive {:announcement_changed, current}, 500
      assert current.id == posted.id
      assert current.text == "Heads-up"
    end
  end

  describe "clear/0" do
    test "removes the current banner and broadcasts cleared event", ctx do
      {:ok, _} = Announcements.post("Going down", ctx.admin)

      :ok = Announcements.subscribe()
      :ok = Announcements.clear()

      assert Announcements.current() == nil
      assert_receive {:announcement_changed, nil}, 500
    end

    test "clearing when there's nothing posted is a no-op" do
      :ok = Announcements.clear()
      assert :ok = Announcements.clear()
    end
  end
end
