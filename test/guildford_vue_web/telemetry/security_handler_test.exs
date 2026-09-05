defmodule GuildfordVueWeb.Telemetry.SecurityHandlerTest do
  @moduledoc """
  Sprint 11.5 Slice 9 — counters increment when security events
  fire. Tests directly emit telemetry and read the counters; the
  end-to-end emission paths (rate-limit plugs, auth, OTP) are
  already covered by their own suites.
  """
  use ExUnit.Case, async: false

  alias GuildfordVueWeb.Telemetry.SecurityHandler

  setup do
    SecurityHandler.attach()
    SecurityHandler.reset()
    on_exit(&SecurityHandler.reset/0)
    :ok
  end

  test "rate_limit tripped increments per scope" do
    :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{
      scope: "candidate-register"
    })

    :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{
      scope: "candidate-register"
    })

    :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{
      scope: "admin-login"
    })

    assert SecurityHandler.count([:guildford_vue, :rate_limit, :tripped], "candidate-register") ==
             2

    assert SecurityHandler.count([:guildford_vue, :rate_limit, :tripped], "admin-login") == 1
  end

  test "auth login_failed increments per scope atom" do
    :telemetry.execute([:guildford_vue, :auth, :login_failed], %{count: 1}, %{scope: :candidate})
    :telemetry.execute([:guildford_vue, :auth, :login_failed], %{count: 1}, %{scope: :candidate})
    :telemetry.execute([:guildford_vue, :auth, :login_failed], %{count: 1}, %{scope: :admin})

    assert SecurityHandler.count([:guildford_vue, :auth, :login_failed], :candidate) == 2
    assert SecurityHandler.count([:guildford_vue, :auth, :login_failed], :admin) == 1
  end

  test "otp_failed increments per scope" do
    :telemetry.execute([:guildford_vue, :auth, :otp_failed], %{count: 1}, %{scope: :candidate})

    assert SecurityHandler.count([:guildford_vue, :auth, :otp_failed], :candidate) == 1
  end

  test "metadata without a known scope tag falls into :unknown" do
    :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{
      bogus: "nope"
    })

    assert SecurityHandler.count([:guildford_vue, :rate_limit, :tripped], :unknown) == 1
  end

  test "reset/0 zeroes every counter" do
    :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{scope: "x"})
    assert SecurityHandler.count([:guildford_vue, :rate_limit, :tripped], "x") == 1
    SecurityHandler.reset()
    assert SecurityHandler.count([:guildford_vue, :rate_limit, :tripped], "x") == 0
  end
end
