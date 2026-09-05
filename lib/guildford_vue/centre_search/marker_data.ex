defmodule GuildfordVue.CentreSearch.MarkerData do
  @moduledoc """
  Pure transform from `CentreSearch.search/1` results into map
  marker payloads. The LV ships the resulting list as a JSON-encoded
  `data-markers` attribute on the `<div id="map">` element; the
  client-side Leaflet hook reads it and drops markers on a tile map.

  Keeping the transform pure means: (1) the test suite covers the
  visual colour-coding without booting a browser, and (2) the LV's
  render stays focused on layout.

  ## Availability classification

  PRD §4.5 — "indicative availability indicators on map markers".
  The colour buckets:

      :green  — ≥50% of total capacity available across the
                centre's matching slots
      :amber  —  1%–49% available
      :red    —  0% available (or no matching slots)
  """

  @type marker :: %{
          centre_id: binary(),
          name: String.t(),
          city: String.t(),
          postcode: String.t(),
          latitude: float(),
          longitude: float(),
          slot_count: non_neg_integer(),
          available_slot_count: non_neg_integer(),
          available_count: non_neg_integer(),
          seat_capacity: non_neg_integer(),
          availability: :green | :amber | :red
        }

  @spec from_results(list()) :: [marker()]
  def from_results(results) when is_list(results) do
    results
    |> Enum.filter(&has_coordinates?/1)
    |> Enum.map(&to_marker/1)
  end

  defp has_coordinates?(%{centre: %{latitude: lat, longitude: lng}})
       when is_number(lat) and is_number(lng),
       do: true

  defp has_coordinates?(_), do: false

  defp to_marker(%{centre: c, slots: slots} = result) do
    %{
      centre_id: c.id,
      name: c.name,
      city: c.city,
      postcode: c.postcode,
      latitude: c.latitude,
      longitude: c.longitude,
      slot_count: length(slots),
      available_slot_count: Enum.count(slots, &(&1.available_count > 0)),
      available_count: Enum.sum(Enum.map(slots, & &1.available_count)),
      seat_capacity: Enum.sum(Enum.map(slots, & &1.capacity)),
      availability: availability_class(result)
    }
  end

  @spec availability_class(map()) :: :green | :amber | :red
  def availability_class(%{slots: []}), do: :red

  def availability_class(%{slots: slots}) do
    available = Enum.sum(Enum.map(slots, & &1.available_count))
    capacity = Enum.sum(Enum.map(slots, & &1.capacity))

    cond do
      capacity == 0 -> :red
      available == 0 -> :red
      available * 100 >= capacity * 50 -> :green
      true -> :amber
    end
  end
end
