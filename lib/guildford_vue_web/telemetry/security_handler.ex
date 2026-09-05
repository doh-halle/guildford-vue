defmodule GuildfordVueWeb.Telemetry.SecurityHandler do
  @moduledoc """
  Sprint 11.5 Slice 9 — `:telemetry` handler that listens for
  security-relevant events emitted by the rate-limit plugs +
  auth modules + OTP context, bumps an ETS counter, and (when
  Sentry is wired) breadcrumbs the event so the next exception
  carries the context.

  ## Subscribed events

    * `[:guildford_vue, :rate_limit, :tripped]`  — RateLimitLogin /
      RateLimitForm / Hammer.check denials.
    * `[:guildford_vue, :auth, :login_failed]`   — session-controller
      :create branch on bad password.
    * `[:guildford_vue, :auth, :otp_failed]`     — wrong OTP code.

  ## Counter storage

  An ETS table `:guildford_vue_security_counters` keyed by
  `{event, scope_or_label}`. `count/1` reads; `reset/0` zeroes
  (test helper).
  """
  require Logger

  @ets_table :guildford_vue_security_counters

  @events [
    [:guildford_vue, :rate_limit, :tripped],
    [:guildford_vue, :auth, :login_failed],
    [:guildford_vue, :auth, :otp_failed]
  ]

  @spec attach() :: :ok
  def attach do
    ensure_table!()

    Enum.each(@events, fn event ->
      handler_id = "security-handler-" <> Enum.join(event, ":")
      :telemetry.attach(handler_id, event, &__MODULE__.handle/4, nil)
    end)
  end

  def handle(event, _measurements, metadata, _config) do
    ensure_table!()
    key = {event, metadata[:scope] || metadata[:label] || :unknown}
    :ets.update_counter(@ets_table, key, {2, 1}, {key, 0})

    # Sentry breadcrumb — survives without Sentry; the module is
    # safely loaded even when no DSN is configured.
    if Code.ensure_loaded?(Sentry) and function_exported?(Sentry, :Context, 1) do
      Sentry.Context.add_breadcrumb(%{
        category: "security",
        message: Enum.join(event, "."),
        data: Map.take(metadata, [:scope, :label, :ip_hash])
      })
    end

    :ok
  end

  @doc "Read the counter for a specific event + label combo."
  @spec count(list(atom()), atom() | binary()) :: non_neg_integer()
  def count(event, label) do
    ensure_table!()

    case :ets.lookup(@ets_table, {event, label}) do
      [{_, n}] -> n
      [] -> 0
    end
  end

  @doc "Test helper — zero every counter."
  @spec reset() :: :ok
  def reset do
    ensure_table!()
    :ets.delete_all_objects(@ets_table)
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:public, :named_table, :set, write_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  end
end
