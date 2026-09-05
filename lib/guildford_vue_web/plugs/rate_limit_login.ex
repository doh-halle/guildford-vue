defmodule GuildfordVueWeb.Plugs.RateLimitLogin do
  @moduledoc """
  Plug that throttles login attempts per IP using Hammer's ETS backend.

  PRD §4.1 FR-AUTH-4: 5 attempts per 15 minutes per IP across all three
  login endpoints. Each scope (`candidate`, `admin`, `exam_centre`) gets
  its own bucket via the `:scope` option so that one scope being attacked
  does not lock out the others.

  ## Usage

      pipeline :candidate_login_post do
        plug GuildfordVueWeb.Plugs.RateLimitLogin,
          scope: "candidate-login",
          limit: 5,
          scale_ms: 15 * 60 * 1000,
          redirect_to: "/candidate/login"
      end

  ## Behaviour

    * `{:allow, _}` — pass through.
    * `{:deny, _}` — halt and redirect to `:redirect_to` with a flash
      explaining the lockout duration.
    * `{:error, _}` (Hammer backend unavailable) — **fail CLOSED**.
      Halt and redirect with a "Login is temporarily unavailable" flash.
      This is the safe default for a regulated UK exam-booking system
      (defect 002, Sprint 1b → fixed Sprint 1c). The earlier fail-open
      behaviour silently allowed unlimited attempts whenever the ETS
      backend hiccupped.

  ## Test injection

  The `:check_rate_fn` option (default `&Hammer.check_rate/3`) lets tests
  swap in a stub returning any of the three result shapes.
  """
  import Plug.Conn

  @type opts :: %{
          required(:scope) => String.t(),
          required(:limit) => pos_integer(),
          required(:scale_ms) => pos_integer(),
          required(:redirect_to) => String.t(),
          required(:check_rate_fn) => (String.t(), pos_integer(), pos_integer() -> term())
        }

  @spec init(keyword()) :: opts()
  def init(opts) do
    %{
      scope: Keyword.fetch!(opts, :scope),
      limit: Keyword.fetch!(opts, :limit),
      scale_ms: Keyword.fetch!(opts, :scale_ms),
      redirect_to: Keyword.fetch!(opts, :redirect_to),
      check_rate_fn: Keyword.get(opts, :check_rate_fn, &Hammer.check_rate/3)
    }
  end

  @spec call(Plug.Conn.t(), opts()) :: Plug.Conn.t()
  def call(conn, %{
        scope: scope,
        limit: limit,
        scale_ms: scale_ms,
        redirect_to: to,
        check_rate_fn: check_rate_fn
      }) do
    # When the global :rate_limit_enabled flag is false (test env)
    # AND the caller hasn't passed an explicit stub, skip the
    # backend entirely. Mirrors the same bypass added in
    # Sprint 11.5 Slice 1 to RateLimitForm + the GuildfordVue.Hammer
    # LV wrapper so the three-scope auth-flow tests don't share
    # cross-test bucket state.
    if Application.get_env(:guildford_vue, :rate_limit_enabled, true) == false and
         check_rate_fn == (&Hammer.check_rate/3) do
      conn
    else
      do_call(conn, scope, limit, scale_ms, to, check_rate_fn)
    end
  end

  defp do_call(conn, scope, limit, scale_ms, to, check_rate_fn) do
    id = "rate_limit:#{scope}:#{ip_string(conn)}"

    case check_rate_fn.(id, scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        # Sprint 11.5 Slice 2 — audit-log every rate-limit trip.
        _ = GuildfordVue.AuthAuditLog.log_rate_limit_exceeded(scope, ip_string(conn))
        # Sprint 11.5 Slice 9 — emit telemetry for the security handler.
        :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{
          scope: scope,
          reason: :deny
        })

        minutes = max(1, div(scale_ms, 60_000))

        conn
        |> Phoenix.Controller.put_flash(
          :error,
          "Too many login attempts. Try again in #{minutes} minute#{if minutes == 1, do: "", else: "s"}."
        )
        |> Phoenix.Controller.redirect(to: to)
        |> halt()

      {:error, _} ->
        # Defect 002 fix (Sprint 1b → Sprint 1c): fail CLOSED.
        # If the rate-limiter can't make a decision we refuse the request
        # rather than silently allowing unlimited login attempts.
        _ = GuildfordVue.AuthAuditLog.log_rate_limit_exceeded(scope, ip_string(conn))

        :telemetry.execute([:guildford_vue, :rate_limit, :tripped], %{count: 1}, %{
          scope: scope,
          reason: :error
        })

        conn
        |> Phoenix.Controller.put_flash(
          :error,
          "Login is temporarily unavailable. Please try again in a moment."
        )
        |> Phoenix.Controller.redirect(to: to)
        |> halt()
    end
  end

  defp ip_string(%Plug.Conn{remote_ip: ip}), do: :inet.ntoa(ip) |> to_string()
end
