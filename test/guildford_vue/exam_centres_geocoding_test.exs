defmodule GuildfordVue.ExamCentresGeocodingTest do
  @moduledoc """
  Sprint 3 Slice 5 — postcode-driven geocoding on save.
  When the centre's postcode changes, the profile changeset
  derives lat/lng (and therefore geom) from the configured
  Geocoder adapter unless explicit coordinates are supplied.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.ExamCentres

  setup do
    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "geo@example.com",
        "password" => "supersecret123!A",
        "name" => "Geo Centre",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "EC1A 1BB",
        "latitude" => 51.5,
        "longitude" => -0.1
      })

    %{centre: centre}
  end

  test "changing postcode auto-derives lat/lng + geom", %{centre: c} do
    {:ok, updated} =
      ExamCentres.update_centre_profile(c, %{
        # PRD §12.1 known postcode
        "postcode" => "M1 1AE"
      })

    # Seeded Manchester coords (~53.4794, -2.2453)
    assert_in_delta updated.latitude, 53.4794, 0.001
    assert_in_delta updated.longitude, -2.2453, 0.001

    # geom updated alongside
    assert %Geo.Point{coordinates: {lng, lat}, srid: 4326} = updated.geom
    assert_in_delta lat, 53.4794, 0.001
    assert_in_delta lng, -2.2453, 0.001
  end

  test "explicit lat/lng on the change overrides geocoding", %{centre: c} do
    {:ok, updated} =
      ExamCentres.update_centre_profile(c, %{
        "postcode" => "M1 1AE",
        "latitude" => 60.0,
        "longitude" => 5.0
      })

    assert updated.latitude == 60.0
    assert updated.longitude == 5.0
  end

  test "unknown postcode fails validation", %{centre: c} do
    assert {:error, cs} = ExamCentres.update_centre_profile(c, %{"postcode" => "XX99 9XX"})

    assert Enum.any?(
             errors_on(cs).postcode,
             &(String.contains?(&1, "unknown") or String.contains?(&1, "could not"))
           )
  end

  test "unchanged postcode does NOT re-geocode", %{centre: c} do
    {:ok, updated} = ExamCentres.update_centre_profile(c, %{"name" => "Renamed Only"})
    assert updated.latitude == c.latitude
    assert updated.longitude == c.longitude
  end
end
