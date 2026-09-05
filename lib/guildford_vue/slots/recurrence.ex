defmodule GuildfordVue.Slots.Recurrence do
  @moduledoc """
  Pure expansion of a recurrence spec into a list of `starts_at`
  DateTimes. Used by the bulk-create LiveView so the LV can show a
  "this will create N slots" preview before committing.

  Spec:

      %{
        start_date: Date.t(),
        end_date:   Date.t(),       # inclusive
        weekdays:   [1..7],         # 1 = Monday, 7 = Sunday
        times:      [String.t()]    # "HH:MM" or "HH:MM:SS"
      }

  Returns a list of UTC `DateTime`s in ascending order. Empty if
  the date range is reversed or no weekday matches.
  """

  @type spec :: %{
          required(:start_date) => Date.t(),
          required(:end_date) => Date.t(),
          required(:weekdays) => [1..7],
          required(:times) => [String.t()]
        }

  @spec expand(spec()) :: [DateTime.t()]
  def expand(%{
        start_date: start_date,
        end_date: end_date,
        weekdays: weekdays,
        times: times
      }) do
    if Date.compare(start_date, end_date) == :gt do
      []
    else
      times_parsed = Enum.map(times, &parse_time!/1)

      Date.range(start_date, end_date)
      |> Enum.filter(&(Date.day_of_week(&1) in weekdays))
      |> Enum.flat_map(fn date ->
        Enum.map(times_parsed, &date_time_at(date, &1))
      end)
      |> Enum.sort(DateTime)
    end
  end

  defp parse_time!(s) when is_binary(s) do
    if String.match?(s, ~r/^\d{2}:\d{2}$/) do
      Time.from_iso8601!(s <> ":00")
    else
      Time.from_iso8601!(s)
    end
  end

  defp date_time_at(date, %Time{} = time) do
    {:ok, naive} = NaiveDateTime.new(date, time)
    {:ok, dt} = DateTime.from_naive(naive, "Etc/UTC")
    dt
  end
end
