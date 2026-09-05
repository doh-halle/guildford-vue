defmodule GuildfordVueWeb.Admin.AdminSystemLive do
  @moduledoc """
  Sprint 10 Slice 2 — system health panel. Renders the live OTP
  supervision tree, total process count, and the running
  per-centre GenServers with their mailbox depths.

  The page auto-refreshes every 5 seconds via `:timer.send_interval/2`
  so the panel reflects the live state without an operator manually
  reloading.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.SystemHealth

  @refresh_ms 5_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    {:ok,
     socket
     |> assign(:page_title, "System health")
     |> refresh()}
  end

  @impl Phoenix.LiveView
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    socket
    |> assign(:tree, SystemHealth.supervision_tree())
    |> assign(:running, SystemHealth.running_centres())
    |> assign(:process_count, SystemHealth.process_count())
    |> assign(:last_refreshed_at, DateTime.utc_now())
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:system}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">System health</h1>
      <p class="mt-2 text-sm text-ink-500">
        Live OTP introspection. Auto-refreshes every 5 seconds.
        Last refresh: {Calendar.strftime(@last_refreshed_at, "%H:%M:%S UTC")}
      </p>

      <section class="mt-6 grid grid-cols-1 gap-6 sm:grid-cols-3">
        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">Total processes</p>
          <p
            class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900"
            data-test-id="process-count"
          >
            {@process_count}
          </p>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">Centre servers</p>
          <p
            class="mt-2 font-sans text-3xl font-bold tracking-tight text-teal-700"
            data-test-id="centre-server-count"
          >
            {length(@running)}
          </p>
          <p class="mt-1 text-xs text-ink-500">live per-centre GenServers</p>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">Max mailbox</p>
          <p class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900">
            {max_mailbox(@running)}
          </p>
          <p class="mt-1 text-xs text-ink-500">deepest centre queue</p>
        </div>
      </section>

      <section class="mt-10">
        <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">
          Per-centre servers
        </h2>
        <%= if @running == [] do %>
          <p class="mt-4 text-sm text-ink-500">
            No CentreServers running. They spawn on demand when the first slot lookup
            for a centre arrives.
          </p>
        <% else %>
          <div class="mt-4 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
            <table class="w-full text-left text-sm">
              <thead class="border-b border-ink-200 bg-ink-50">
                <tr>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Centre
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    PID
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Mailbox
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Status
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Memory (KB)
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-ink-200">
                <tr :for={c <- @running}>
                  <td class="px-4 py-2 font-mono text-[11px] text-ink-700">{c.centre_id}</td>
                  <td class="px-4 py-2 font-mono text-[11px] text-ink-600">{inspect(c.pid)}</td>
                  <td class={["px-4 py-2 font-mono text-[11px]", mailbox_class(c.mailbox)]}>
                    {c.mailbox}
                  </td>
                  <td class="px-4 py-2 font-mono text-[11px] text-ink-600">{c.status}</td>
                  <td class="px-4 py-2 font-mono text-[11px] text-ink-600">
                    {div(c.memory, 1024)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>

      <section class="mt-10">
        <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">Supervision tree</h2>
        <div class="mt-4 rounded-2xl border border-ink-200 bg-white p-6">
          <.tree_node node={@tree} depth={0} />
        </div>
      </section>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  attr :node, :map, required: true
  attr :depth, :integer, required: true

  defp tree_node(assigns) do
    ~H"""
    <div class={"py-1 #{indent(@depth)}"}>
      <span class="font-mono text-xs text-ink-900">{inspect(@node.name)}</span>
      <span class="ml-2 font-mono text-[10px] uppercase tracking-widest text-ink-400">
        {@node.type}
      </span>
    </div>
    <.tree_node :for={child <- @node.children} node={child} depth={@depth + 1} />
    """
  end

  defp indent(0), do: "pl-0"
  defp indent(1), do: "pl-4"
  defp indent(2), do: "pl-8"
  defp indent(3), do: "pl-12"
  defp indent(_), do: "pl-16"

  defp mailbox_class(0), do: "text-ink-500"
  defp mailbox_class(n) when n < 10, do: "text-ink-700"
  defp mailbox_class(n) when n < 100, do: "text-amber-700 font-semibold"
  defp mailbox_class(_), do: "text-red-700 font-semibold"

  defp max_mailbox([]), do: 0
  defp max_mailbox(centres), do: centres |> Enum.map(& &1.mailbox) |> Enum.max()
end
