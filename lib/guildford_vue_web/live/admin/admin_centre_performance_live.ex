defmodule GuildfordVueWeb.Admin.AdminCentrePerformanceLive do
  @moduledoc """
  Sprint 10 Slice 5 — `/backoffice/centres/performance`. Per-centre
  metrics table sorted by total bookings descending (busiest at the
  top), with fill rate and cancellation rate per centre.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.CentreMetrics

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Centre performance")
     |> assign(:rows, CentreMetrics.list_all())}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:centres}>
      <div class="flex flex-wrap items-baseline justify-between gap-3">
        <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">
          Centre performance
        </h1>
        <.link
          navigate={~p"/backoffice/centres"}
          class="text-sm font-semibold text-teal-700 hover:underline"
        >
          ← Back to all centres
        </.link>
      </div>
      <p class="mt-2 text-sm text-ink-500">
        Per-centre booking totals, fill rate (confirmed / capacity), and
        cancellation rate ((cancelled + refunded) / total bookings).
        Approved centres only.
      </p>

      <%= if @rows == [] do %>
        <p class="mt-8 rounded-lg border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
          No approved centres yet.
        </p>
      <% else %>
        <div class="mt-6 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-ink-200 bg-ink-50">
              <tr>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Centre
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Bookings
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Confirmed
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Cancelled
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Refunded
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Capacity
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Fill rate
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Cancellation rate
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-ink-200">
              <tr :for={r <- @rows} data-test-id={"centre-#{r.centre_id}"}>
                <td class="px-4 py-2 text-ink-900">{r.centre_name}</td>
                <td class="px-4 py-2 font-mono text-xs text-ink-900">{r.bookings_total}</td>
                <td class="px-4 py-2 font-mono text-xs text-teal-700">{r.bookings_confirmed}</td>
                <td class="px-4 py-2 font-mono text-xs text-ink-500">{r.bookings_cancelled}</td>
                <td class="px-4 py-2 font-mono text-xs text-amber-700">{r.bookings_refunded}</td>
                <td class="px-4 py-2 font-mono text-xs text-ink-600">{r.capacity_total}</td>
                <td class="px-4 py-2 font-mono text-xs text-ink-900">{percent(r.fill_rate)}</td>
                <td class={[
                  "px-4 py-2 font-mono text-xs",
                  cancellation_class(r.cancellation_rate)
                ]}>
                  {percent(r.cancellation_rate)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  defp percent(value) when is_float(value) do
    "#{:erlang.float_to_binary(value * 100, decimals: 1)}%"
  end

  defp cancellation_class(rate) when rate < 0.1, do: "text-ink-700"
  defp cancellation_class(rate) when rate < 0.25, do: "text-amber-700"
  defp cancellation_class(_), do: "text-red-700 font-semibold"
end
