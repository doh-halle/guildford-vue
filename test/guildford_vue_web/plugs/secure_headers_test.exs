defmodule GuildfordVueWeb.Plugs.SecureHeadersTest do
  @moduledoc """
  Tests the security headers plug (PRD §9 NFR). Asserts on the rendered
  landing page response since that's the simplest GET that goes through
  the full browser_base pipeline.
  """
  use GuildfordVueWeb.ConnCase, async: true

  setup %{conn: conn} do
    %{conn: get(conn, ~p"/")}
  end

  test "sets a strict Content-Security-Policy", %{conn: conn} do
    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
    assert csp =~ "script-src 'self'"
    refute csp =~ "'unsafe-eval'"
    refute csp =~ ~r/script-src[^;]*unsafe-inline/
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "object-src 'none'"
  end

  test "sets Referrer-Policy", %{conn: conn} do
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
  end

  test "sets X-Content-Type-Options", %{conn: conn} do
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "sets X-Frame-Options to DENY", %{conn: conn} do
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
  end

  test "sets Permissions-Policy denying the dangerous defaults", %{conn: conn} do
    [pp] = get_resp_header(conn, "permissions-policy")
    assert pp =~ "geolocation=()"
    assert pp =~ "microphone=()"
    assert pp =~ "camera=()"
  end

  test "sets Cross-Origin-Opener-Policy", %{conn: conn} do
    assert get_resp_header(conn, "cross-origin-opener-policy") == ["same-origin"]
  end

  test "does NOT set HSTS in dev/test (only force_ssl in prod sets HSTS)",
       %{conn: conn} do
    assert get_resp_header(conn, "strict-transport-security") == []
  end
end
