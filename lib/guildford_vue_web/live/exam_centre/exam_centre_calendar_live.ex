defmodule GuildfordVueWeb.ExamCentre.ExamCentreCalendarLive do
  @moduledoc """
  Live calendar view at `/examcenter/calendar` (PRD §4.6). Renders
  the next 14 days of slots as a colour-coded grid; subscribes to
  the centre's PubSub topic on connect so reservations / cancels
  from other clients update the cell in real-time.

  Pattern: subscribe ONLY after `connected?(socket)` per Phoenix
  guidance — the initial mount runs twice (HTTP + WebSocket); we
  want the subscription on the WebSocket side only.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Centres.PubSub, as: CentrePubSub
  alias GuildfordVue.ExamCentres
  alias GuildfordVue.Slots
  alias GuildfordVue.Slots.Slot
  alias GuildfordVueWeb.Components.CalendarGrid

  @times [~T[10:00:00], ~T[14:00:00], ~T[16:30:00]]
  @days_ahead 14

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    centre = socket.assigns.current_exam_centre
    today = Date.utc_today()
    end_date = Date.add(today, @days_ahead - 1)

    slots =
      ExamCentres.get_exam_centre!(centre.id)
      |> Slots.list_centre_slots(include_past: false, limit: 1000)

    if connected?(socket), do: CentrePubSub.subscribe(centre.id)

    {:ok,
     socket
     |> assign(:page_title, "Calendar")
     |> assign(:start_date, today)
     |> assign(:end_date, end_date)
     |> assign(:times, @times)
     |> assign(:slots, slots)}
  end

  @impl Phoenix.LiveView
  def handle_info({:slot_changed, %Slot{} = updated}, socket) do
    slots = upsert(socket.assigns.slots, updated)
    {:noreply, assign(socket, :slots, slots)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # Replace an existing slot in-place (or append if it's new).
  # Cancelled slots are kept in the list so the cell flips to the
  # "cancelled" colour rather than reverting to empty.
  defp upsert(slots, %Slot{id: id} = new) do
    if Enum.any?(slots, &(&1.id == id)) do
      Enum.map(slots, &maybe_replace(&1, new))
    else
      [new | slots]
    end
  end

  defp maybe_replace(%Slot{id: id}, %Slot{id: id} = new), do: new
  defp maybe_replace(other, _new), do: other

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell
      current_exam_centre={@current_exam_centre}
      active={:calendar}
    >
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Calendar</h1>
      <p class="mt-2 text-sm text-ink-500">
        Next {Date.diff(@end_date, @start_date) + 1} days. Updates in real time as candidates reserve or you publish new slots.
      </p>

      <section class="mt-8 rounded-2xl border border-ink-200 bg-white p-4">
        <CalendarGrid.grid
          slots={@slots}
          start_date={@start_date}
          end_date={@end_date}
          times={@times}
        />
      </section>

      <div class="mt-4 flex flex-wrap items-center gap-4 text-xs text-ink-600">
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded bg-teal-100 border border-teal-300"></span> Available
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded bg-amber-100 border border-amber-300"></span> Limited
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded bg-red-100 border border-red-300"></span> Fully booked
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded bg-ink-100 border border-ink-200"></span> Cancelled
        </span>
      </div>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end
end
