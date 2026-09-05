defmodule GuildfordVue.PasswordBreachTest do
  @moduledoc """
  Sprint 11.5 Slice 5 — behaviour + Stub adapter for HIBP-style
  breached-password checks. No outbound HTTP this sprint
  (per-user direction); the real adapter is a config swap in a
  follow-up.

  Stub semantics:
    * Returns `:ok` for any password by default.
    * `Stub.seed_breach/2` registers a password → breach-count
      mapping for the duration of the test. The check then
      returns `{:error, :breached, count}` for matches.
    * `Stub.reset/0` clears all seeded breaches.
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.PasswordBreach
  alias GuildfordVue.PasswordBreach.Stub

  setup do
    Stub.reset()
    on_exit(&Stub.reset/0)
    :ok
  end

  describe "Stub adapter (default behaviour)" do
    test "returns :ok for any password by default" do
      assert PasswordBreach.check("PasswordThatIsLongEnough!1") == :ok
      assert PasswordBreach.check("anything goes here, really") == :ok
    end

    test "returns {:error, :breached, count} for a seeded password" do
      Stub.seed_breach("Password12345!", 123)
      assert PasswordBreach.check("Password12345!") == {:error, :breached, 123}
    end

    test "non-seeded passwords still pass" do
      Stub.seed_breach("Password12345!", 7)
      assert PasswordBreach.check("a different long password") == :ok
    end

    test "reset/0 clears all seeded breaches" do
      Stub.seed_breach("hunter2!hunter2!", 1)
      assert {:error, :breached, _} = PasswordBreach.check("hunter2!hunter2!")

      Stub.reset()
      assert PasswordBreach.check("hunter2!hunter2!") == :ok
    end
  end

  describe "dispatch" do
    test "PasswordBreach.check/1 routes via the configured adapter" do
      previous = Application.get_env(:guildford_vue, :password_breach)
      Application.put_env(:guildford_vue, :password_breach, GuildfordVue.PasswordBreach.Stub)
      Stub.seed_breach("route-test!12345", 9)
      assert PasswordBreach.check("route-test!12345") == {:error, :breached, 9}
      Application.put_env(:guildford_vue, :password_breach, previous)
    end

    test "nil / non-binary input returns :ok (other validators handle shape)" do
      assert PasswordBreach.check(nil) == :ok
      assert PasswordBreach.check(123) == :ok
    end
  end
end
