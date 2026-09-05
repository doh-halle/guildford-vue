defmodule GuildfordVueWeb.Plugs.RateLimitForm do
  @moduledoc """
  Generic per-IP rate-limit plug for non-login form / GET
  endpoints. Sibling to `RateLimitLogin` (which is purpose-built
  for the three login POST endpoints) with a customisable flash
  message + redirect target so it can be wired to any controller
  action.

  Fails **CLOSED** on Hammer backend errors — matches the
  Defect 002 remediation in the sibling plug.

  ## Usage (controller-side)

      plug GuildfordVueWeb.Plugs.RateLimitForm,
        [
          scope: "receipt-pdf",
          limit: 30,
          scale_ms: 60 * 60 * 1000,
          redirect_to: "/candidate/bookings",
          flash_message: "Too many receipt requests. Try again in an hour."
        ]
        when action in [:show_pdf]

  ## Options

    * `:scope` (required) — bucket namespace, e.g. `"candidate-register"`.
    * `:limit` (required) — max requests per `scale_ms` per IP.
    * `:scale_ms` (required) — window length in ms.
    * `:redirect_to` (required) — path to redirect on denial.
    * `:flash_message` (required) — flash text shown on denial.
    * `:check_rate_fn` (optional) — test injection point; defaults
      to `&Hammer.check_rate/3`.
  """
  import Plug.Conn

  @type opts :: %{
          required(:scope) => String.t(),
          required(:limit) => pos_integer(),
          required(:scale_ms) => pos_integer(),
          required(:redirect_to) => String.t(),
          required(:flash_message) => String.t(),
          required(:check_rate_fn) => (String.t(), pos_integer(), pos_integer() -> term())
        }

  @spec init(keyword()) :: opts()
  def init(opts) do
    %{
      scope: Keyword.fetch!(opts, :scope),
      limit: Keyword.fetch!(opts, :limit),
      scale_ms: Keyword.fetch!(opts, :scale_ms),
      redirect_to: Keyword.fetch!(opts, :redirect_to),
      flash_message: Keyword.fetch!(opts, :flash_message),
      check_rate_fn: Keyword.get(opts, :check_rate_fn, &Hammer.check_rate/3)
    }
  end

  @spec call(Plug.Conn.t(), opts()) :: Plug.Conn.t()
  def call(conn, %{
        scope: scope,
        limit: limit,
        scale_ms: scale_ms,
        redirect_to: to,
        flash_message: msg,
        check_rate_fn: check_rate_fn
      }) do
    # When the global :rate_limit_enabled flag is false (test env)
    # AND the caller hasn't passed an explicit stub, skip the
    # backend entirely — keeps unrelated tests free of cross-test
    # bucket bleed.
    if Application.get_env(:guildford_vue, :rate_limit_enabled, true) == false and
         check_rate_fn == (&Hammer.check_rate/3) do
      conn
    else
      ip = ip_string(conn)
      bucket = "rate_limit:#{scope}:#{ip}"

      case check_rate_fn.(bucket, scale_ms, limit) do
        {:allow, _count} -> conn
        {:deny, _limit} -> deny(conn, to, msg, scope, ip)
        # Defect 002 fix: fail CLOSED.
        {:error, _reason} -> deny(conn, to, msg, scope, ip)
      end
    end
  end

  defp deny(conn, to, msg, scope, ip) do
    # Sprint 11.5 Slice 2 — audit-log every rate-limit trip.
    _ = GuildfordVue.AuthAuditLog.log_rate_limit_exceeded(scope, ip)
    # Sprint 11.5 Slice 9 — emit telemetry for the security handler.
    :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{scope: scope})

    conn
    |> Phoenix.Controller.put_flash(:error, msg)
    |> Phoenix.Controller.redirect(to: to)
    |> halt()
  end

  defp ip_string(%Plug.Conn{remote_ip: ip}), do: :inet.ntoa(ip) |> to_string()
end
