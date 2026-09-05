defmodule GuildfordVueWeb.Components.CalendarGridTest do
  @moduledoc """
  Sprint 6 Slice 3 — calendar grid component. Pure function component
  rendering an N-day × M-time grid with availability colour-coded cells.
  """
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.Slots.Slot
  alias GuildfordVueWeb.Components.CalendarGrid

  defp slot(date, time, opts) do
    {:ok, dt} = DateTime.new(date, time, "Etc/UTC")

    %Slot{
      id: Ecto.UUID.generate(),
      starts_at: dt,
      ends_at: DateTime.add(dt, 60 * 60, :second),
      capacity: Keyword.get(opts, :capacity, 10),
      available_count: Keyword.get(opts, :available_count, 10),
      status: Keyword.get(opts, :status, "open"),
      exam_id: Keyword.get(opts, :exam_id, Ecto.UUID.generate()),
      exam_centre_id: Ecto.UUID.generate()
    }
  end

  defp render_grid(assigns) do
    render_component(&CalendarGrid.grid/1, assigns)
  end

  describe "grid/1 — render basics" do
    test "renders one cell per (date, time) intersection" do
      html =
        render_grid(
          slots: [],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-03],
          times: [~T[10:00:00], ~T[14:00:00]]
        )

      # 3 dates × 2 times = 6 cells
      assert html =~ "data-test-id=\"calendar-cell-2026-06-01-10:00\""
      assert html =~ "data-test-id=\"calendar-cell-2026-06-01-14:00\""
      assert html =~ "data-test-id=\"calendar-cell-2026-06-03-14:00\""
    end

    test "renders date row headings (YYYY-MM-DD)" do
      html =
        render_grid(
          slots: [],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-02],
          times: [~T[10:00:00]]
        )

      assert html =~ "2026-06-01"
      assert html =~ "2026-06-02"
    end

    test "renders time column headings" do
      html =
        render_grid(
          slots: [],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00], ~T[14:00:00]]
        )

      assert html =~ "10:00"
      assert html =~ "14:00"
    end
  end

  describe "ADT-driven colour-coding" do
    test ":available — teal colour class" do
      html =
        render_grid(
          slots: [slot(~D[2026-06-01], ~T[10:00:00], capacity: 10, available_count: 10)],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00]]
        )

      assert html =~ "bg-teal-100"
    end

    test ":limited — amber colour class (1–25% capacity)" do
      html =
        render_grid(
          slots: [slot(~D[2026-06-01], ~T[10:00:00], capacity: 20, available_count: 2)],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00]]
        )

      assert html =~ "bg-amber-100"
    end

    test ":fully_booked — red colour class" do
      html =
        render_grid(
          slots: [slot(~D[2026-06-01], ~T[10:00:00], capacity: 5, available_count: 0)],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00]]
        )

      assert html =~ "bg-red-100"
    end

    test ":cancelled — ink (grey) colour class" do
      html =
        render_grid(
          slots: [slot(~D[2026-06-01], ~T[10:00:00], status: "cancelled")],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00]]
        )

      assert html =~ "bg-ink-100"
    end

    test "empty cell renders without an availability colour class" do
      html =
        render_grid(
          slots: [],
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00]]
        )

      refute html =~ "bg-teal-100"
      refute html =~ "bg-amber-100"
      refute html =~ "bg-red-100"
      assert html =~ "data-test-id=\"calendar-cell-2026-06-01-10:00\""
    end
  end

  describe "cell aggregation" do
    test "multiple slots in one cell → worst availability wins (cancelled > fully_booked > limited > available)" do
      slots = [
        slot(~D[2026-06-01], ~T[10:00:00], capacity: 10, available_count: 10),
        slot(~D[2026-06-01], ~T[10:00:00], capacity: 10, available_count: 0)
      ]

      html =
        render_grid(
          slots: slots,
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          times: [~T[10:00:00]]
        )

      # fully_booked beats available
      assert html =~ "bg-red-100"
      refute html =~ "bg-teal-100"
    end
  end
end
