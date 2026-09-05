defmodule GuildfordVueWeb.ExamCentre.ExamCentreDashboardLive do
  @moduledoc """
  Exam-centre dashboard. Sprint 3 wraps the page in the new
  `centre_shell` sidebar layout and replaces the old placeholder
  cards with navigation tiles linking to Profile / Exams / Slots
  (Slots is the Sprint 4 surface).
  """
  use GuildfordVueWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Exam centre dashboard")}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell
      current_exam_centre={@current_exam_centre}
      active={:dashboard}
    >
      <h1 class="font-sans text-4xl font-bold tracking-tight text-ink-900">
        {@current_exam_centre.name}
      </h1>
      <p class="mt-1 text-sm text-ink-500">
        {@current_exam_centre.address_line_1}, {@current_exam_centre.city}, {@current_exam_centre.postcode}
      </p>

      <section class="mt-10 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <.link
          navigate={~p"/examcenter/profile"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-indigo-300 hover:shadow-sm"
        >
          <h2 class="font-mono text-xs uppercase tracking-widest text-ink-500">Profile</h2>
          <p class="mt-3 text-sm text-ink-500">Address, contact, accreditation evidence.</p>
        </.link>
        <.link
          navigate={~p"/examcenter/exams"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-indigo-300 hover:shadow-sm"
        >
          <h2 class="font-mono text-xs uppercase tracking-widest text-ink-500">Exams I offer</h2>
          <p class="mt-3 text-sm text-ink-500">
            Pick from the platform catalogue. Lands in Sprint 3 Slice 6.
          </p>
        </.link>
        <.link
          navigate={~p"/examcenter/slots"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-indigo-300 hover:shadow-sm"
        >
          <h2 class="font-mono text-xs uppercase tracking-widest text-ink-500">Slots</h2>
          <p class="mt-3 text-sm text-ink-500">Publish availability — Sprint 4.</p>
        </.link>
        <.link
          navigate={~p"/examcenter/bookings"}
          class="block rounded-2xl border border-ink-200 bg-white p-6 transition hover:border-indigo-300 hover:shadow-sm"
        >
          <h2 class="font-mono text-xs uppercase tracking-widest text-ink-500">Bookings</h2>
          <p class="mt-3 text-sm text-ink-500">
            Every reservation made at your centre, with candidate and slot details.
          </p>
        </.link>
      </section>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end
end
