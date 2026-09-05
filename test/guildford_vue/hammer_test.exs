defmodule GuildfordVue.HammerTest do
  @moduledoc """
  Sprint 11.5 Slice 1 — LiveView-event-level rate-limiting
  wrapper. Mirrors the contract of `RateLimitLogin` but for
  callers that don't have a Plug.Conn — typically LiveView
  handle_event/3 implementations.

  Fail-CLOSED on backend errors (matches Defect 002 remediation
  in the login plug).
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.Hammer, as: H

  describe "check/4" do
    test ":allow when the check returns {:allow, _}" do
      stub = fn _, _, _ -> {:allow, 1} end

      assert H.check("scope", "alice", 5, 60_000, check_rate_fn: stub) == :allow
    end

    test "{:deny, retry_after_seconds} when the check returns {:deny, _}" do
      stub = fn _, _, _ -> {:deny, 5} end

      assert {:deny, retry_after} =
               H.check("scope", "alice", 5, 60_000, check_rate_fn: stub)

      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "fails CLOSED — {:deny, _} when the backend errors" do
      stub = fn _, _, _ -> {:error, :backend_down} end

      assert {:deny, _} = H.check("scope", "alice", 5, 60_000, check_rate_fn: stub)
    end

    test "scope + identifier are namespaced in the bucket key" do
      captured = :ets.new(:hammer_test_capture, [:public, :set])

      stub = fn id, _, _ ->
        :ets.insert(captured, {id, true})
        {:allow, 1}
      end

      H.check("regfx", "10.0.0.1", 5, 60_000, check_rate_fn: stub)
      H.check("regfx", "10.0.0.2", 5, 60_000, check_rate_fn: stub)
      H.check("login", "10.0.0.1", 5, 60_000, check_rate_fn: stub)

      keys = :ets.tab2list(captured) |> Enum.map(&elem(&1, 0))
      :ets.delete(captured)

      assert "rate_limit:regfx:10.0.0.1" in keys
      assert "rate_limit:regfx:10.0.0.2" in keys
      assert "rate_limit:login:10.0.0.1" in keys
    end
  end

  describe "default backend (no injection)" do
    setup do
      previous = Application.get_env(:guildford_vue, :rate_limit_enabled)
      Application.put_env(:guildford_vue, :rate_limit_enabled, true)
      on_exit(fn -> Application.put_env(:guildford_vue, :rate_limit_enabled, previous) end)
      :ok
    end

    test "integration smoke — first call is :allow" do
      scope = "smoke-#{System.unique_integer([:positive])}"
      assert H.check(scope, "10.0.0.42", 5, 60_000) == :allow
    end

    test "integration smoke — N+1 calls are :deny" do
      scope = "burst-#{System.unique_integer([:positive])}"

      for _ <- 1..5 do
        assert H.check(scope, "10.0.0.43", 5, 60_000) == :allow
      end

      assert {:deny, _} = H.check(scope, "10.0.0.43", 5, 60_000)
    end

    test "the global flag short-circuits to :allow when false" do
      Application.put_env(:guildford_vue, :rate_limit_enabled, false)
      scope = "off-#{System.unique_integer([:positive])}"

      for _ <- 1..20 do
        assert H.check(scope, "10.0.0.44", 5, 60_000) == :allow
      end
    end
  end
end
