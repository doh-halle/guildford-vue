defmodule GuildfordVue.SlotsRecurrenceTest do
  @moduledoc """
  Sprint 4 Slice 5 — recurrence expansion. Pure function: takes a
  date range + weekday set + time-of-day list and returns the list
  of starts_at DateTimes that the bulk creator will use.

  This is a unit test on the expansion logic separately from
  Slots.bulk_create_slots/2 (which is already covered in Slice 1).
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Slots.Recurrence

  describe "expand/1" do
    test "weekday filter — only Mondays + Wednesdays in a one-week range" do
      starts =
        Recurrence.expand(%{
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-07],
          # Mon, Wed
          weekdays: [1, 3],
          times: ["10:00"]
        })

      dates = Enum.map(starts, &DateTime.to_date/1) |> Enum.uniq()
      assert dates == [~D[2026-06-01], ~D[2026-06-03]]
    end

    test "multiple times per day produce one DateTime per (date, time)" do
      starts =
        Recurrence.expand(%{
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          weekdays: [1],
          times: ["10:00", "14:00", "16:30"]
        })

      assert length(starts) == 3
      hours = Enum.map(starts, & &1.hour)
      assert hours == [10, 14, 16]
    end

    test "full week × two times = 14 slots" do
      starts =
        Recurrence.expand(%{
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-07],
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          times: ["10:00", "14:00"]
        })

      assert length(starts) == 14
    end

    test "30 days × weekdays only × two times = 22 slots in June 2026" do
      starts =
        Recurrence.expand(%{
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-11],
          # Mon-Fri
          weekdays: [1, 2, 3, 4, 5],
          times: ["10:00", "14:00"]
        })

      # 11 days, 9 weekdays (Mon-Fri × 2 incl. partial), × 2 times.
      # 1-5 Jun + 8-11 Jun = 9 weekdays * 2 = 18.
      assert length(starts) == 18
    end

    test "ascending order" do
      starts =
        Recurrence.expand(%{
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-07],
          weekdays: [1, 5],
          times: ["14:00", "10:00"]
        })

      sorted = Enum.sort_by(starts, & &1, DateTime)
      assert starts == sorted
    end

    test "empty if start_date > end_date" do
      assert [] =
               Recurrence.expand(%{
                 start_date: ~D[2026-06-10],
                 end_date: ~D[2026-06-01],
                 weekdays: [1],
                 times: ["10:00"]
               })
    end

    test "empty if no weekdays match" do
      # 2026-06-08 is a Monday (1). No Tuesdays in a single Monday.
      assert [] =
               Recurrence.expand(%{
                 start_date: ~D[2026-06-08],
                 end_date: ~D[2026-06-08],
                 weekdays: [2],
                 times: ["10:00"]
               })
    end

    test "returns UTC DateTimes" do
      [dt | _] =
        Recurrence.expand(%{
          start_date: ~D[2026-06-01],
          end_date: ~D[2026-06-01],
          weekdays: [1],
          times: ["10:00"]
        })

      assert dt.time_zone == "Etc/UTC"
    end
  end
end
