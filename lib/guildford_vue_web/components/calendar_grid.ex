defmodule GuildfordVueWeb.Components.CalendarGrid do
  @moduledoc """
  Pure function component rendering a centre's slot calendar as a
  date × time grid (PRD §4.6 calendar view). Each cell shows the
  worst-case availability across any slots scheduled for that
  (date, time) intersection.

  Exhaustive ADT pattern matching: `cell_classes/1` branches on
  every `Slots.Availability` variant — adding a new ADT value
  fails Dialyzer rather than producing a default-coloured cell.

  ## Props

      <CalendarGrid.grid
        slots={@slots}
        start_date={~D[2026-06-01]}
        end_date={~D[2026-06-14]}
        times={[~T[10:00:00], ~T[14:00:00]]}
      />
  """
  use Phoenix.Component

  alias GuildfordVue.Slots.Availability

  attr :slots, :list, required: true
  attr :start_date, Date, required: true
  attr :end_date, Date, required: true
  attr :times, :list, required: true

  def grid(assigns) do
    assigns =
      assigns
      |> assign(:dates, Date.range(assigns.start_date, assigns.end_date) |> Enum.to_list())
      |> assign(:slots_by_cell, group_by_cell(assigns.slots))

    ~H"""
    <div class="overflow-x-auto" role="region" aria-label="Slot calendar">
      <table class="w-full border-collapse text-left text-xs">
        <thead>
          <tr>
            <th class="border-b border-ink-200 bg-ink-50 px-3 py-2 font-mono text-[10px] uppercase tracking-widest text-ink-600">
              Date
            </th>
            <%= for time <- @times do %>
              <th class="border-b border-ink-200 bg-ink-50 px-3 py-2 text-center font-mono text-[10px] uppercase tracking-widest text-ink-600">
                {Calendar.strftime(time, "%H:%M")}
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody class="divide-y divide-ink-100">
          <%= for date <- @dates do %>
            <tr>
              <th
                scope="row"
                class="bg-ink-50 px-3 py-2 text-left font-mono text-[11px] text-ink-700"
              >
                {Date.to_iso8601(date)}
              </th>
              <%= for time <- @times do %>
                <td
                  data-test-id={cell_id(date, time)}
                  class={[
                    "border border-white px-3 py-2 text-center transition-colors duration-300",
                    cell_classes(cell_state(@slots_by_cell, date, time))
                  ]}
                >
                  {cell_label(cell_state(@slots_by_cell, date, time))}
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  # ---- pure helpers (exhaustively pattern-matched) ----

  defp cell_id(date, time) do
    "calendar-cell-#{Date.to_iso8601(date)}-#{format_hm(time)}"
  end

  defp format_hm(%Time{} = time) do
    "#{pad(time.hour)}:#{pad(time.minute)}"
  end

  defp pad(n) when n < 10, do: "0" <> Integer.to_string(n)
  defp pad(n), do: Integer.to_string(n)

  defp group_by_cell(slots) do
    Enum.group_by(slots, fn slot ->
      {DateTime.to_date(slot.starts_at), {slot.starts_at.hour, slot.starts_at.minute}}
    end)
  end

  # `:empty` is added to the ADT here as a render-only state — DB
  # never represents it. We pattern-match exhaustively over BOTH
  # the four real Availability variants AND :empty in `cell_classes/1`
  # / `cell_label/1` so any drift fails Dialyzer.
  defp cell_state(slots_by_cell, date, time) do
    cell_slots = Map.get(slots_by_cell, {date, {time.hour, time.minute}}, [])

    case cell_slots do
      [] -> :empty
      slots -> worst(slots)
    end
  end

  defp worst(slots) do
    states = Enum.map(slots, &Availability.classify/1)

    cond do
      :cancelled in states -> :cancelled
      :fully_booked in states -> :fully_booked
      :limited in states -> :limited
      :available in states -> :available
    end
  end

  defp cell_classes(:available), do: Availability.tailwind_classes(:available)
  defp cell_classes(:limited), do: Availability.tailwind_classes(:limited)
  defp cell_classes(:fully_booked), do: Availability.tailwind_classes(:fully_booked)
  defp cell_classes(:cancelled), do: Availability.tailwind_classes(:cancelled)
  defp cell_classes(:empty), do: "bg-white text-ink-300"

  defp cell_label(:available), do: "·"
  defp cell_label(:limited), do: "•"
  defp cell_label(:fully_booked), do: "—"
  defp cell_label(:cancelled), do: "×"
  defp cell_label(:empty), do: ""
end
