defmodule GuildfordVueWeb.Admin.AdminDashboardLive do
  @moduledoc """
  Admin dashboard. Sprint 2 Slice 6 — real metrics for pending centres,
  candidate counts, recent audit activity. Replaces the Sprint 1c
  placeholder cards.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{AuditLog, Metrics}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Back office dashboard")
     |> assign(:metrics, Metrics.snapshot())
     |> assign(:recent_events, AuditLog.list(limit: 5))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:dashboard}>
      <h1 class="font-sans text-4xl font-bold tracking-tight text-ink-900">
        Welcome, {@current_admin.name}
      </h1>
      <p class="mt-1 text-sm text-ink-500">Role: {@current_admin.role}</p>

      <section class="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          navigate={~p"/backoffice/centres"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-orange-300 hover:shadow-sm"
        >
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">
            Pending centres
          </p>
          <p class="mt-2 font-sans text-4xl font-bold tracking-tight text-orange-700">
            {@metrics.centres_pending}
          </p>
          <p class="mt-1 text-xs text-ink-500">awaiting review</p>
        </.link>

        <.link
          navigate={~p"/backoffice/centres"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-teal-300 hover:shadow-sm"
        >
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">
            Approved centres
          </p>
          <p class="mt-2 font-sans text-4xl font-bold tracking-tight text-teal-700">
            {@metrics.centres_approved}
          </p>
          <p class="mt-1 text-xs text-ink-500">live on the platform</p>
        </.link>

        <.link
          navigate={~p"/backoffice/candidates"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-orange-300 hover:shadow-sm"
        >
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">
            Candidates
          </p>
          <p class="mt-2 font-sans text-4xl font-bold tracking-tight text-ink-900">
            {@metrics.candidates_total}
          </p>
          <p class="mt-1 text-xs text-ink-500">
            {@metrics.candidates_active} active
          </p>
        </.link>
      </section>

      <section class="mt-6 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">Bookings today</p>
          <p
            class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900"
            data-test-id="bookings-today"
          >
            {@metrics.bookings_today}
          </p>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">This week</p>
          <p
            class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900"
            data-test-id="bookings-week"
          >
            {@metrics.bookings_this_week}
          </p>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">This month</p>
          <p
            class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900"
            data-test-id="bookings-month"
          >
            {@metrics.bookings_this_month}
          </p>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">Revenue</p>
          <p
            class="mt-2 font-sans text-3xl font-bold tracking-tight text-teal-700"
            data-test-id="revenue-total"
          >
            £{format_pounds(@metrics.revenue_pence)}
          </p>
          <p class="mt-1 text-xs text-ink-500">all-time succeeded payments</p>
        </div>
      </section>

      <section class="mt-10 rounded-2xl border border-ink-200 bg-white p-6">
        <div class="flex items-baseline justify-between">
          <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">
            Recent activity
          </h2>
          <.link
            navigate={~p"/backoffice/audit-log"}
            class="text-sm font-semibold text-teal-700 hover:underline"
          >
            View full audit log →
          </.link>
        </div>

        <%= if @recent_events == [] do %>
          <p class="mt-4 text-sm text-ink-500">No activity yet.</p>
        <% else %>
          <ul class="mt-4 divide-y divide-ink-200">
            <%= for e <- @recent_events do %>
              <li class="flex items-center justify-between py-3 text-sm">
                <span class="font-mono text-xs text-ink-700">{e.event_type}</span>
                <span class="text-xs text-ink-500">
                  {Calendar.strftime(e.inserted_at, "%Y-%m-%d %H:%M")}
                </span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  defp format_pounds(pence) when is_integer(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end
end
