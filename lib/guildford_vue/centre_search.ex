defmodule GuildfordVue.CentreSearch do
  @moduledoc """
  Guest- and candidate-facing centre search (PRD §4.5). Composes:

    1. Postcode validation (`GuildfordVue.Postcodes`)
    2. Geocoding via the cached pool (`Geocoder.Pool`)
    3. PostGIS proximity (`ExamCentres.find_within_radius/3`)
    4. Per-centre slot fetch (filtered by exam + date window)

  Returns a flat list of `%{centre:, slots:, distance_metres:}`
  ordered nearest-first. Centres without any matching slots after
  filtering are excluded so the UI doesn't render an empty list
  with a useless centre row.
  """
  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL
  alias GuildfordVue.{ExamCentres, Postcodes, Repo}
  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.Geocoder.Pool, as: GeocoderPool
  alias GuildfordVue.Slots.Slot

  @type opts :: %{
          required(:postcode) => String.t(),
          optional(:radius_metres) => pos_integer(),
          optional(:exam_id) => binary(),
          optional(:starts_after) => DateTime.t(),
          optional(:starts_before) => DateTime.t()
        }

  @type result :: %{
          centre: ExamCentre.t(),
          slots: [Slot.t()],
          distance_metres: non_neg_integer()
        }

  @default_radius_metres 80_467

  @spec search(opts()) :: {:ok, [result()]} | {:error, atom()}
  def search(%{postcode: postcode} = opts) do
    with {:ok, normalised} <- Postcodes.validate(postcode),
         {:ok, %{latitude: lat, longitude: lng}} <- GeocoderPool.lookup(normalised) do
      radius = Map.get(opts, :radius_metres, @default_radius_metres)
      centres = ExamCentres.find_within_radius(lat, lng, radius)

      results =
        centres
        |> Enum.map(&hydrate(&1, lat, lng, opts))
        |> Enum.reject(&(&1.slots == []))

      {:ok, results}
    end
  end

  def search(_opts), do: {:error, :postcode_required}

  defp hydrate(%ExamCentre{} = centre, lat, lng, opts) do
    %{
      centre: centre,
      slots: matching_slots(centre, opts),
      distance_metres: distance_metres(centre, lat, lng)
    }
  end

  defp matching_slots(centre, opts) do
    now = DateTime.utc_now()

    query =
      from s in Slot,
        where:
          s.exam_centre_id == ^centre.id and
            s.status != "cancelled" and
            s.available_count > 0 and
            s.starts_at >= ^now,
        order_by: [asc: s.starts_at]

    query
    |> maybe_filter_exam(opts[:exam_id])
    |> maybe_filter_starts_after(opts[:starts_after])
    |> maybe_filter_starts_before(opts[:starts_before])
    |> Repo.all()
  end

  defp maybe_filter_exam(query, nil), do: query
  defp maybe_filter_exam(query, exam_id), do: where(query, [s], s.exam_id == ^exam_id)

  defp maybe_filter_starts_after(query, nil), do: query
  defp maybe_filter_starts_after(query, dt), do: where(query, [s], s.starts_at >= ^dt)

  defp maybe_filter_starts_before(query, nil), do: query
  defp maybe_filter_starts_before(query, dt), do: where(query, [s], s.starts_at <= ^dt)

  defp distance_metres(%ExamCentre{geom: nil}, _lat, _lng), do: 0

  defp distance_metres(%ExamCentre{geom: geom}, lat, lng) do
    # Single-row geography distance — cheap and avoids re-projecting
    # the result set. Returned as an integer metre count for UI use.
    point = %Geo.Point{coordinates: {lng * 1.0, lat * 1.0}, srid: 4326}

    [[d]] =
      SQL.query!(
        Repo,
        "SELECT ST_DistanceSphere($1::geometry, $2::geometry)::int",
        [geom, point]
      ).rows

    d
  end
end
