defmodule GuildfordVue.PromEx.SecurityPlugin do
  @moduledoc """
  Sprint 12 Slice 2 — PromEx plugin exposing the security
  telemetry events emitted by:

    * `RateLimitLogin` / `RateLimitForm` — `[:guildford_vue, :rate_limit, :tripped]`
    * `AuthAuditLog.log_login_failure/3` — `[:guildford_vue, :auth, :login_failed]`
    * `Auth.OTP.verify/2` failure path — `[:guildford_vue, :auth, :otp_failed]`

  All as Prometheus counters tagged by `scope` so a SOC dashboard
  can break down per-endpoint.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:guildford_vue_security_event_metrics, [
      counter(
        [:guildford_vue, :security, :rate_limit, :tripped, :count],
        event_name: [:guildford_vue, :rate_limit, :tripped],
        description: "Rate-limit denials by scope",
        tags: [:scope],
        tag_values: &tag_scope/1
      ),
      counter(
        [:guildford_vue, :security, :auth, :login_failed, :count],
        event_name: [:guildford_vue, :auth, :login_failed],
        description: "Failed login attempts by scope",
        tags: [:scope],
        tag_values: &tag_scope/1
      ),
      counter(
        [:guildford_vue, :security, :auth, :otp_failed, :count],
        event_name: [:guildford_vue, :auth, :otp_failed],
        description: "Failed OTP verify attempts by scope",
        tags: [:scope],
        tag_values: &tag_scope/1
      )
    ])
  end

  defp tag_scope(%{scope: scope}) when is_atom(scope) or is_binary(scope) do
    %{scope: to_string(scope)}
  end

  defp tag_scope(_), do: %{scope: "unknown"}
end
