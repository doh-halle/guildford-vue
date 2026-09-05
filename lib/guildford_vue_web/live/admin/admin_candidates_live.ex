defmodule GuildfordVueWeb.Admin.AdminCandidatesLive do
  @moduledoc """
  Admin candidate management (PRD §4.4 FR-ADMIN-2). Lists candidates
  with search + status filter and exposes suspend / reactivate per
  candidate. Both lifecycle actions go through `Candidates.suspend/2`
  and `Candidates.reactivate/2` which write `candidate_suspended` /
  `candidate_reactivated` audit events.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Candidates

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Candidates")
     |> assign(:search, "")
     |> assign(:status, :all)
     |> assign(:candidates, [])}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    status = parse_status(params["status"])
    search = params["q"] || ""

    {:noreply,
     socket
     |> assign(:status, status)
     |> assign(:search, search)
     |> reload()}
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => %{"q" => q}}, socket) do
    {:noreply,
     socket
     |> assign(:search, q)
     |> reload()}
  end

  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status, parse_status(status))
     |> reload()}
  end

  def handle_event("suspend", %{"id" => id}, socket) do
    candidate = Candidates.get_candidate!(id)
    {:ok, _} = Candidates.suspend(candidate, socket.assigns.current_admin)
    {:noreply, reload(socket)}
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    candidate = Candidates.get_candidate!(id)
    {:ok, _} = Candidates.reactivate(candidate, socket.assigns.current_admin)
    {:noreply, reload(socket)}
  end

  defp reload(socket) do
    candidates =
      Candidates.list_candidates(
        search: socket.assigns.search,
        status: socket.assigns.status
      )

    assign(socket, :candidates, candidates)
  end

  defp parse_status("active"), do: :active
  defp parse_status("suspended"), do: :suspended
  defp parse_status(_), do: :all

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:candidates}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Candidates</h1>
      <p class="mt-2 text-sm text-ink-500">
        Search, suspend, or reactivate candidate accounts.
      </p>

      <div class="mt-6 flex flex-wrap items-center gap-3">
        <.form
          for={%{}}
          id="candidate-search"
          phx-change="search"
          phx-submit="search"
          class="flex-1"
        >
          <input
            type="search"
            name="search[q]"
            value={@search}
            placeholder="Search by name or email"
            autocomplete="off"
            class="w-full max-w-sm rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          />
        </.form>

        <div class="flex gap-1" role="tablist" aria-label="Status filter">
          <button
            type="button"
            phx-click="filter"
            phx-value-status="all"
            aria-pressed={@status == :all}
            class={status_tab_classes(@status == :all)}
          >
            All
          </button>
          <button
            type="button"
            phx-click="filter"
            phx-value-status="active"
            aria-pressed={@status == :active}
            class={status_tab_classes(@status == :active)}
          >
            Active
          </button>
          <button
            type="button"
            phx-click="filter"
            phx-value-status="suspended"
            aria-pressed={@status == :suspended}
            class={status_tab_classes(@status == :suspended)}
          >
            Suspended
          </button>
        </div>
      </div>

      <%= if @candidates == [] do %>
        <div class="mt-8 rounded-2xl border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
          No candidates match.
        </div>
      <% else %>
        <ul class="mt-6 divide-y divide-ink-200 rounded-2xl border border-ink-200 bg-white">
          <%= for c <- @candidates do %>
            <li
              id={"candidate-row-#{c.id}"}
              class="flex flex-wrap items-center gap-4 px-6 py-4"
            >
              <div class="min-w-0 flex-1">
                <p class="font-semibold text-ink-900">{c.first_name} {c.last_name}</p>
                <p class="text-sm text-ink-600">{c.email}</p>
                <%= if c.suspended_at do %>
                  <p class="mt-1 inline-block rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700">
                    Suspended
                  </p>
                <% end %>
              </div>

              <%= if c.suspended_at do %>
                <button
                  type="button"
                  phx-click="reactivate"
                  phx-value-id={c.id}
                  data-test-id={"reactivate-#{c.id}"}
                  class="rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white hover:bg-teal-600"
                >
                  Reactivate
                </button>
              <% else %>
                <button
                  type="button"
                  phx-click="suspend"
                  phx-value-id={c.id}
                  data-test-id={"suspend-#{c.id}"}
                  data-confirm={"Suspend #{c.first_name} #{c.last_name}?"}
                  class="rounded-lg border border-red-300 px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50"
                >
                  Suspend
                </button>
              <% end %>
            </li>
          <% end %>
        </ul>
      <% end %>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  defp status_tab_classes(true) do
    "rounded-lg bg-orange-100 px-3 py-1.5 text-sm font-semibold text-orange-800"
  end

  defp status_tab_classes(false) do
    "rounded-lg px-3 py-1.5 text-sm text-ink-600 hover:bg-ink-100"
  end
end
