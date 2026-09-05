defmodule GuildfordVueWeb.Plugs.RateLimitLoginTest do
  @moduledoc """
  Tests for the Hammer-backed rate-limit plug guarding /candidate/login,
  /backoffice/login, and /examcenter/login. PRD §4.1 FR-AUTH-4: 5 attempts
  per 15 minutes per IP.
  """
  use GuildfordVueWeb.ConnCase, async: false

  alias GuildfordVueWeb.Plugs.RateLimitLogin

  setup %{conn: conn} do
    # Sprint 11.5 Slice 1 introduced a global :rate_limit_enabled flag
    # (default true; false in config/test.exs) so unrelated tests don't
    # share Hammer ETS bucket state. The login plug tests specifically
    # exercise the limiter so we flip the flag on for the duration of
    # this module.
    previous = Application.get_env(:guildford_vue, :rate_limit_enabled)
    Application.put_env(:guildford_vue, :rate_limit_enabled, true)
    on_exit(fn -> Application.put_env(:guildford_vue, :rate_limit_enabled, previous) end)

    # Each test uses its own unique remote_ip so we never collide with another
    # test's rate-limit bucket across the run.
    ip = {127, 0, 0, :rand.uniform(255)}
    conn = %{conn | remote_ip: ip} |> init_test_session(%{}) |> Phoenix.Controller.fetch_flash()
    %{conn: conn, ip: ip}
  end

  describe "call/2" do
    test "passes through the first `limit` requests", %{conn: conn} do
      opts = RateLimitLogin.init(scope: "test-A", limit: 5, scale_ms: 60_000, redirect_to: "/x")

      for _ <- 1..5 do
        result = RateLimitLogin.call(conn, opts)
        refute result.halted
      end
    end

    test "halts and redirects on the (limit + 1)th request", %{conn: conn} do
      opts =
        RateLimitLogin.init(
          scope: "test-B",
          limit: 2,
          scale_ms: 60_000,
          redirect_to: "/candidate/login"
        )

      Enum.each(1..2, fn _ -> RateLimitLogin.call(conn, opts) end)
      result = RateLimitLogin.call(conn, opts)

      assert result.halted
      assert redirected_to(result) == "/candidate/login"
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Too many"
    end

    test "buckets are per-IP — a different remote_ip is not blocked",
         %{conn: conn} do
      opts = RateLimitLogin.init(scope: "test-C", limit: 1, scale_ms: 60_000, redirect_to: "/x")

      _ = RateLimitLogin.call(conn, opts)
      _ = RateLimitLogin.call(conn, opts)
      blocked = RateLimitLogin.call(conn, opts)
      assert blocked.halted

      different_ip_conn = %{conn | remote_ip: {10, 0, 0, 1}}
      allowed = RateLimitLogin.call(different_ip_conn, opts)
      refute allowed.halted
    end

    test "buckets are per-scope — candidate-login bucket does not block admin-login",
         %{conn: conn} do
      candidate_opts =
        RateLimitLogin.init(
          scope: "candidate-test",
          limit: 1,
          scale_ms: 60_000,
          redirect_to: "/candidate/login"
        )

      admin_opts =
        RateLimitLogin.init(
          scope: "admin-test",
          limit: 1,
          scale_ms: 60_000,
          redirect_to: "/backoffice/login"
        )

      RateLimitLogin.call(conn, candidate_opts)
      blocked = RateLimitLogin.call(conn, candidate_opts)
      assert blocked.halted

      allowed = RateLimitLogin.call(conn, admin_opts)
      refute allowed.halted
    end

    test "fails CLOSED on Hammer backend error (defect 002 fix)", %{conn: conn} do
      # Stub Hammer.check_rate to return {:error, :boom}. We do this by
      # injecting a custom :check_rate_fn so the plug calls our function
      # instead of Hammer.check_rate/3.
      opts =
        RateLimitLogin.init(
          scope: "test-fail-closed",
          limit: 5,
          scale_ms: 60_000,
          redirect_to: "/candidate/login",
          check_rate_fn: fn _id, _scale, _limit -> {:error, :boom} end
        )

      result = RateLimitLogin.call(conn, opts)

      assert result.halted
      assert redirected_to(result) == "/candidate/login"

      assert Phoenix.Flash.get(result.assigns.flash, :error) =~
               "Login is temporarily unavailable"
    end
  end
end
