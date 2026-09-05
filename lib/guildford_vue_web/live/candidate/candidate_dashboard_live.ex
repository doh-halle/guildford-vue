defmodule GuildfordVueWeb.Candidate.CandidateDashboardLive do
  @moduledoc """
  Candidate dashboard. Sprint 1c version: profile card + nav placeholders
  for upcoming reservations / past reservations / find a centre (Sprints
  5-9 fill these in).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Bookings

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    upcoming = Bookings.list_upcoming_candidate_bookings(socket.assigns.current_candidate)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:upcoming_bookings, upcoming)
     |> assign(:upcoming_count, length(upcoming))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-container px-6 py-12 sm:px-10">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Candidate</p>
      <h1 class="mt-4 font-sans text-4xl font-bold tracking-tight text-ink-900">
        Welcome back, {@current_candidate.first_name}
      </h1>

      <section
        aria-labelledby="book-an-exam"
        class="mt-8 rounded-2xl border border-teal-200 bg-teal-50 p-6 sm:p-8"
      >
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="min-w-0 flex-1">
            <h2 id="book-an-exam" class="font-sans text-xl font-bold tracking-tight text-ink-900">
              Book an exam
            </h2>
            <p class="mt-1 text-sm text-ink-600">
              Pick an exam and enter your postcode to see nearby centres with open slots.
            </p>
          </div>
          <.link
            navigate={~p"/search"}
            data-test-id="find-centre-cta"
            class="inline-flex items-center gap-2 rounded-lg bg-teal-700 px-5 py-3 text-sm font-semibold text-white hover:bg-teal-600 focus:outline-none focus:ring-2 focus:ring-teal-500/40"
          >
            Find an exam centre →
          </.link>
        </div>
      </section>

      <section
        aria-labelledby="profile-card"
        class="mt-10 grid grid-cols-1 gap-6 lg:grid-cols-3"
      >
        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <h2 id="profile-card" class="font-mono text-xs uppercase tracking-widest text-ink-500">
            Profile
          </h2>
          <p class="mt-3 font-semibold text-ink-900">
            {@current_candidate.first_name} {@current_candidate.last_name}
          </p>
          <p class="text-sm text-ink-600">{@current_candidate.email}</p>
          <%= if @current_candidate.postcode do %>
            <p class="text-sm text-ink-500">{@current_candidate.postcode}</p>
          <% end %>
          <.link
            navigate={~p"/candidate/settings"}
            class="mt-4 inline-block text-sm font-semibold text-teal-700 hover:underline"
          >
            Edit profile →
          </.link>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <h2 class="font-mono text-xs uppercase tracking-widest text-ink-500">
            Upcoming reservations
          </h2>
          <p
            class="mt-3 font-sans text-3xl font-bold tracking-tight text-ink-900"
            data-test-id="upcoming-count"
          >
            {@upcoming_count}
          </p>
          <%= if @upcoming_count == 0 do %>
            <p class="mt-2 text-sm text-ink-500">
              No upcoming bookings. Find a centre via <.link
                navigate={~p"/search"}
                class="font-semibold text-teal-700 hover:underline"
              >
                /search
              </.link>.
            </p>
          <% else %>
            <ul class="mt-3 space-y-2 text-sm">
              <li :for={b <- Enum.take(@upcoming_bookings, 3)}>
                <.link
                  navigate={~p"/candidate/bookings/#{b.reference}"}
                  class="font-mono font-semibold text-teal-700 hover:underline"
                >
                  {b.reference}
                </.link>
              </li>
            </ul>
            <.link
              navigate={~p"/candidate/bookings"}
              class="mt-4 inline-block text-sm font-semibold text-teal-700 hover:underline"
            >
              All bookings →
            </.link>
          <% end %>
        </div>

        <div class="rounded-2xl border border-ink-200 bg-white p-6">
          <h2 class="font-mono text-xs uppercase tracking-widest text-ink-500">Find a centre</h2>
          <p class="mt-3 text-sm text-ink-600">
            Search by postcode and exam type to see open slots at centres near you.
          </p>
          <.link
            navigate={~p"/search"}
            class="mt-4 inline-block text-sm font-semibold text-teal-700 hover:underline"
          >
            Search centres →
          </.link>
          <%= if @current_candidate.postcode do %>
            <p class="mt-3 text-xs text-ink-500">
              Tip — your saved postcode <span class="font-mono">{@current_candidate.postcode}</span>
              will pre-fill.
            </p>
          <% end %>
        </div>
      </section>
    </main>
    """
  end
end
