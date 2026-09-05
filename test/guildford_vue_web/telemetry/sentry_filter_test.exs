defmodule GuildfordVueWeb.Telemetry.SentryFilterTest do
  @moduledoc """
  Sprint 11.5 Slice 9 — `before_send` strips known sensitive keys
  recursively from any payload. Covers atom + string keys at every
  level of a nested map / list.
  """
  use ExUnit.Case, async: true

  alias GuildfordVueWeb.Telemetry.SentryFilter

  test "atom-keyed sensitive values are filtered" do
    raw = %{password: "hunter2", email: "alice@example.com"}
    expected_pw = "[FILTERED]"
    out = SentryFilter.strip_sensitive(raw)
    assert out.password == expected_pw
    assert out.email == "alice@example.com"
  end

  test "string-keyed sensitive values are filtered" do
    assert SentryFilter.strip_sensitive(%{"token" => "abc", "user_id" => "u_1"}) ==
             %{"token" => "[FILTERED]", "user_id" => "u_1"}
  end

  test "nested maps + lists are walked recursively" do
    input = %{
      request: %{
        params: %{
          "card" => %{"pan" => "4242", "cvc" => "123"},
          "email" => "x@example.com"
        }
      },
      breadcrumbs: [
        %{message: "ok", data: %{secret: "S", color: "blue"}}
      ]
    }

    out = SentryFilter.strip_sensitive(input)
    assert out.request.params["card"] == "[FILTERED]"
    assert out.request.params["email"] == "x@example.com"
    [crumb] = out.breadcrumbs
    assert crumb.data.secret == "[FILTERED]"
    assert crumb.data.color == "blue"
  end

  test "passthrough for non-sensitive payloads" do
    assert SentryFilter.strip_sensitive(%{event: "ok", count: 1}) == %{event: "ok", count: 1}
  end

  test "OTP plain code is filtered (defense-in-depth for Slice 7 emails)" do
    out = SentryFilter.strip_sensitive(%{"code" => "123456", "purpose" => "login_otp"})
    assert out["code"] == "[FILTERED]"
    assert out["purpose"] == "login_otp"
  end
end
