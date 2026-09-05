defmodule GuildfordVueWeb.Admin.AdminAuditLogLive do
  @moduledoc """
  Audit log viewer. Read-only — the `AuditLog` context has no public
  delete API and never will (test in `audit_log_test.exs` pins the
  contract).

  Filter inputs: event_type (exact string match), actor_id (UUID),
  aggregate_id (UUID). Newest events first.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.AuditLog

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> assign(:filters, %{
       "event_type" => "",
       "actor_id" => "",
       "aggregate_id" => "",
       "from" => "",
       "to" => ""
     })
     |> reload()}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"filter" => filters}, socket) do
    {:noreply, socket |> assign(:filters, filters) |> reload()}
  end

  defp reload(socket) do
    opts =
      []
      |> maybe_filter(:event_type, socket.assigns.filters["event_type"])
      |> maybe_filter(:actor_id, socket.assigns.filters["actor_id"])
      |> maybe_filter(:aggregate_id, socket.assigns.filters["aggregate_id"])
      |> maybe_date(:from, socket.assigns.filters["from"], :start_of_day)
      |> maybe_date(:to, socket.assigns.filters["to"], :end_of_day)
      |> Keyword.put(:limit, 100)

    assign(socket, :events, AuditLog.list(opts))
  end

  defp maybe_filter(opts, _key, nil), do: opts
  defp maybe_filter(opts, _key, ""), do: opts
  defp maybe_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_date(opts, _key, nil, _edge), do: opts
  defp maybe_date(opts, _key, "", _edge), do: opts

  defp maybe_date(opts, key, value, edge) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Keyword.put(opts, key, to_datetime(date, edge))
      _ -> opts
    end
  end

  defp to_datetime(date, :start_of_day),
    do: DateTime.new!(date, ~T[00:00:00.000000], "Etc/UTC")

  defp to_datetime(date, :end_of_day),
    do: DateTime.new!(date, ~T[23:59:59.999999], "Etc/UTC")

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:audit_log}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Audit log</h1>
      <p class="mt-2 text-sm text-ink-500">
        Append-only log of admin actions. Read-only.
      </p>

      <.form
        for={%{}}
        id="audit-filter"
        phx-change="filter"
        phx-submit="filter"
        class="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3"
      >
        <input
          type="text"
          name="filter[event_type]"
          value={@filters["event_type"]}
          placeholder="event_type (e.g. centre_approved)"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
        />
        <input
          type="text"
          name="filter[actor_id]"
          value={@filters["actor_id"]}
          placeholder="actor_id (UUID)"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
        />
        <input
          type="text"
          name="filter[aggregate_id]"
          value={@filters["aggregate_id"]}
          placeholder="aggregate_id (UUID)"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
        />
        <label class="flex flex-col text-xs text-ink-500">
          From
          <input
            type="date"
            name="filter[from]"
            value={@filters["from"]}
            class="mt-1 rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          />
        </label>
        <label class="flex flex-col text-xs text-ink-500">
          To
          <input
            type="date"
            name="filter[to]"
            value={@filters["to"]}
            class="mt-1 rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          />
        </label>
      </.form>

      <%= if @events == [] do %>
        <div class="mt-8 rounded-2xl border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
          No matching events.
        </div>
      <% else %>
        <div class="mt-6 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-ink-200 bg-ink-50">
              <tr>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  When
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Event
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Actor
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Aggregate
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Payload
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-ink-200">
              <%= for e <- @events do %>
                <tr>
                  <td class="px-4 py-2 align-top text-xs text-ink-600">
                    {Calendar.strftime(e.inserted_at, "%Y-%m-%d %H:%M:%S")}
                  </td>
                  <td class="px-4 py-2 align-top font-mono text-xs text-ink-900">
                    {e.event_type}
                  </td>
                  <td class="px-4 py-2 align-top font-mono text-[11px] text-ink-600">
                    {e.actor_id || "—"}
                    <%= if e.actor_type do %>
                      <br />
                      <span class="text-[10px] uppercase tracking-widest text-ink-400">
                        {e.actor_type}
                      </span>
                    <% end %>
                  </td>
                  <td class="px-4 py-2 align-top font-mono text-[11px] text-ink-600">
                    {e.aggregate_id || "—"}
                  </td>
                  <td class="px-4 py-2 align-top">
                    <pre class="whitespace-pre-wrap font-mono text-[11px] text-ink-700"><%= inspect(e.payload, pretty: true) %></pre>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end
end
