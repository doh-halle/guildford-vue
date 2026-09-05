defmodule GuildfordVueWeb.Admin.AdminPaymentSettingsLive do
  @moduledoc """
  Superadmin-only toggle for the Simulated PaymentGateway's
  decline rate (PRD §4.8: "Optional admin toggle for 5% simulated
  decline rate"). Lets dev/demo operators flip between 0% (always
  succeed) / 5% (default realistic-feeling rate) / 50% (visible
  failure path for screenshots) / 100% (force every booking onto
  the decline branch for testing).

  The rate is held in `Application.env` because:
    - The Simulated adapter reads it via Application.get_env at
      charge-time.
    - Single-node deployment scope (PRD §14 out-of-scope) makes
      a runtime DB or cluster broadcast unnecessary.
    - A node restart loads the default 5% — matches PRD wording
      that this toggle is "optional".

  Every change is audit-logged with the acting admin + new rate.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.AuditLog

  @allowed_rates [0.0, 0.05, 0.5, 1.0]
  @env_key :payment_decline_rate

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns.current_admin.role == "superadmin" do
      {:ok,
       socket
       |> assign(:page_title, "Payment simulation")
       |> assign(:current_rate, current_rate())
       |> assign(:error_msg, nil)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You need the superadmin role for payment settings.")
       |> push_navigate(to: ~p"/backoffice/dashboard")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("set_rate", %{"rate" => %{"value" => raw}}, socket) do
    with {parsed, ""} <- Float.parse(raw),
         true <- parsed in @allowed_rates do
      old = current_rate()
      Application.put_env(:guildford_vue, @env_key, parsed)

      {:ok, _} =
        AuditLog.append(:payment_decline_rate_changed, %{
          actor: %{id: socket.assigns.current_admin.id, type: "admin"},
          payload: %{old_rate: old, new_rate: parsed}
        })

      {:noreply,
       socket
       |> assign(:current_rate, parsed)
       |> assign(:error_msg, nil)
       |> put_flash(:info, "Decline rate set to #{format_pct(parsed)}.")}
    else
      _ ->
        {:noreply, assign(socket, :error_msg, "invalid — pick one of the offered rates.")}
    end
  end

  defp current_rate, do: Application.get_env(:guildford_vue, @env_key, 0.05)

  defp format_pct(rate), do: "#{round(rate * 100)}%"

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:payment_settings}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">
        Payment simulation
      </h1>
      <p class="mt-2 text-sm text-ink-500">
        Controls the `GuildfordVue.PaymentGateway.Simulated` decline rate.
        Currently <strong>{format_pct(@current_rate)}</strong>.
      </p>

      <section class="mt-8 max-w-md rounded-2xl border border-ink-200 bg-white p-6">
        <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">
          Decline rate
        </h2>

        <.form for={%{}} id="decline-rate-form" phx-submit="set_rate" class="mt-6 space-y-3">
          <%= for {rate, label} <- options() do %>
            <label class="flex items-start gap-3 rounded-lg border border-ink-200 px-4 py-3 text-sm hover:bg-ink-50">
              <input
                type="radio"
                name="rate[value]"
                value={Float.to_string(rate)}
                checked={rate == @current_rate}
                class="mt-1 size-4 border-ink-300 text-orange-700 focus:ring-orange-500"
              />
              <span class="flex-1">
                <span class="font-semibold text-ink-900">{label}</span>
                <span class="ml-2 text-ink-500">— {desc_for(rate)}</span>
              </span>
            </label>
          <% end %>

          <%= if @error_msg do %>
            <p class="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              {@error_msg}
            </p>
          <% end %>

          <button
            type="submit"
            class="rounded-lg bg-orange-700 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-600"
          >
            Apply
          </button>
        </.form>
      </section>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  defp options do
    [
      {0.0, "0% — always succeed"},
      {0.05, "5% — realistic default"},
      {0.5, "50% — visible failure path"},
      {1.0, "100% — every payment declines"}
    ]
  end

  defp desc_for(+0.0), do: "use for screenshot-perfect demos"
  defp desc_for(0.05), do: "matches PRD §4.8 default"
  defp desc_for(0.5), do: "exercises the decline UX without forcing it"
  defp desc_for(1.0), do: "demonstrate the booking-pipeline rollback branch"
end
