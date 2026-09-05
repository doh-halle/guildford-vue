defmodule GuildfordVue.CentreMetrics do
  @moduledoc """
  Per-centre performance metrics for the back-office (PRD §4.10
  Sprint 10 Slice 5).

  Pure SQL aggregates over `bookings` and `slots`. Same shape as
  `GuildfordVue.Metrics` — no GenServer state, no caching; the LV
  re-queries on each mount/refresh.
  """
  import Ecto.Query, warn: false

  alias GuildfordVue.Bookings.Booking
  alias GuildfordVue.ExamCentres
  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.Repo
  alias GuildfordVue.Slots.Slot

  @typedoc """
  Per-centre metric snapshot.

    * `:bookings_total` — every booking ever recorded for the centre
    * `:bookings_confirmed` — currently-confirmed bookings
    * `:bookings_cancelled` / `:bookings_refunded` — non-confirmed states
    * `:capacity_total` — sum of `slot.capacity` across every slot
    * `:fill_rate` — `bookings_confirmed / capacity_total`, 0..1.0
    * `:cancellation_rate` — `(cancelled + refunded) / bookings_total`, 0..1.0
  """
  @type t :: %{
          centre_id: binary(),
          centre_name: String.t(),
          bookings_total: non_neg_integer(),
          bookings_confirmed: non_neg_integer(),
          bookings_cancelled: non_neg_integer(),
          bookings_refunded: non_neg_integer(),
          capacity_total: non_neg_integer(),
          fill_rate: float(),
          cancellation_rate: float()
        }

  @spec metrics_for(ExamCentre.t() | binary()) :: t()
  def metrics_for(%ExamCentre{} = centre), do: build(centre)

  def metrics_for(centre_id) when is_binary(centre_id) do
    build(ExamCentres.get_exam_centre!(centre_id))
  end

  @doc """
  Returns one metrics map per *approved* centre, sorted by
  `:bookings_total` descending (busiest first), then by name.
  """
  @spec list_all() :: [t()]
  def list_all do
    Repo.all(
      from c in ExamCentre,
        where: c.status == "approved",
        order_by: [asc: c.name]
    )
    |> Enum.map(&build/1)
    |> Enum.sort_by(&{-&1.bookings_total, &1.centre_name})
  end

  # --- private ------------------------------------------------------

  defp build(%ExamCentre{} = centre) do
    counts = booking_counts(centre.id)
    capacity = capacity_total(centre.id)

    fill_rate =
      case capacity do
        0 -> 0.0
        n -> safe_round(counts.confirmed / n)
      end

    cancellation_rate =
      case counts.total do
        0 -> 0.0
        n -> safe_round((counts.cancelled + counts.refunded) / n)
      end

    %{
      centre_id: centre.id,
      centre_name: centre.name,
      bookings_total: counts.total,
      bookings_confirmed: counts.confirmed,
      bookings_cancelled: counts.cancelled,
      bookings_refunded: counts.refunded,
      capacity_total: capacity,
      fill_rate: fill_rate,
      cancellation_rate: cancellation_rate
    }
  end

  defp booking_counts(centre_id) do
    grouped =
      Repo.all(
        from b in Booking,
          where: b.exam_centre_id == ^centre_id,
          group_by: b.status,
          select: {b.status, count(b.id)}
      )
      |> Map.new()

    confirmed = Map.get(grouped, "confirmed", 0)
    cancelled = Map.get(grouped, "cancelled", 0)
    refunded = Map.get(grouped, "refunded", 0)

    %{
      confirmed: confirmed,
      cancelled: cancelled,
      refunded: refunded,
      total: confirmed + cancelled + refunded
    }
  end

  defp capacity_total(centre_id) do
    Repo.one(
      from s in Slot,
        where: s.exam_centre_id == ^centre_id,
        select: coalesce(sum(s.capacity), 0)
    )
  end

  defp safe_round(value), do: Float.round(value, 4)
end
