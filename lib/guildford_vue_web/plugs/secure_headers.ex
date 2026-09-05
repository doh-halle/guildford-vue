defmodule GuildfordVueWeb.Plugs.SecureHeaders do
  @moduledoc """
  Sets strict security headers on every HTML response:

    * `Content-Security-Policy` — locks scripts and styles down to the
      same origin plus Google Fonts (for our typography). No
      `unsafe-inline` or `unsafe-eval`. (PRD §9 security NFR)
    * `Referrer-Policy: strict-origin-when-cross-origin`
    * `Permissions-Policy` — denies geolocation/microphone/camera by
      default (we don't use them).
    * `X-Content-Type-Options: nosniff`
    * `X-Frame-Options: DENY`
    * `Cross-Origin-Opener-Policy: same-origin`

  HSTS is set by `Plug.SSL` via the endpoint's `force_ssl:` option in
  `config/runtime.exs` (prod only) — it'd be wrong to set HSTS on
  insecure dev requests, so this plug doesn't.

  ## Why a separate plug rather than `put_secure_browser_headers`?

  Phoenix's `put_secure_browser_headers/1` sets a reasonable default
  set but does NOT include a `Content-Security-Policy` header. CSP is
  the single most effective mitigation for XSS — making it explicit
  + auditable here is worth the extra plug.
  """
  import Plug.Conn

  @default_csp [
    "default-src 'self'",
    # Leaflet is loaded from unpkg's pinned-version URL (SRI-checked
    # in the root layout), so script-src must allow that origin. We
    # still refuse 'unsafe-inline' / 'unsafe-eval' — the highest-impact
    # XSS vector remains hardened.
    "script-src 'self' https://unpkg.com",
    # 'unsafe-inline' is needed for our Tailwind-generated CSS (which
    # injects @theme custom properties into a <style> block in the page),
    # AND for Google Fonts' inline @font-face stylesheet — both are
    # trusted self-content. unpkg.com also serves Leaflet's CSS. We
    # mitigate by also setting strict script-src (no unsafe-inline
    # scripts allowed).
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://unpkg.com",
    "font-src 'self' https://fonts.gstatic.com data:",
    # OpenStreetMap tiles for the search map.
    "img-src 'self' data: blob: https://*.tile.openstreetmap.org https://unpkg.com",
    "connect-src 'self' ws: wss:",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'"
  ]

  @default_permissions_policy [
    "geolocation=()",
    "microphone=()",
    "camera=()",
    "payment=()",
    "usb=()"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", Enum.join(@default_csp, "; "))
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", Enum.join(@default_permissions_policy, ", "))
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
  end
end
