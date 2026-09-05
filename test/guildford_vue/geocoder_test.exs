defmodule GuildfordVue.GeocoderTest do
  @moduledoc """
  Sprint 3 Slice 5 — postcode → lat/lng geocoder.

  Behaviour with two implementations:
    - `Seeded`: dev/test, uses PRD §12.1 postcode → (lat,lng) table.
    - `OSNames`: prod stub (would call OS Names API; not implemented
      since the dissertation reference doesn't make live network
      calls).

  Selection via application config: `:guildford_vue, :geocoder`.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Geocoder

  describe "Seeded.lookup/1" do
    test "returns {:ok, %{latitude, longitude}} for known PRD postcodes" do
      assert {:ok, %{latitude: lat, longitude: lng}} = Geocoder.Seeded.lookup("EC1A 1BB")
      assert is_float(lat) and is_float(lng)
      assert lat > 51.0 and lat < 52.0
      assert lng > -1.0 and lng < 0.0
    end

    test "is case + whitespace insensitive" do
      assert {:ok, _} = Geocoder.Seeded.lookup("ec1a 1bb")
      assert {:ok, _} = Geocoder.Seeded.lookup("EC1A1BB")
      assert {:ok, _} = Geocoder.Seeded.lookup("  EC1A 1BB  ")
    end

    test "returns {:error, :unknown_postcode} for unknown" do
      assert {:error, :unknown_postcode} = Geocoder.Seeded.lookup("XX99 9XX")
    end

    test "{:error, :invalid_postcode} for nil / empty / non-binary" do
      assert {:error, :invalid_postcode} = Geocoder.Seeded.lookup(nil)
      assert {:error, :invalid_postcode} = Geocoder.Seeded.lookup("")
      assert {:error, :invalid_postcode} = Geocoder.Seeded.lookup(:atom)
    end

    test "area-level fallback resolves arbitrary UK postcodes to city centroid" do
      # Random real UK postcodes NOT in @table — each one should
      # still resolve via the @area_centroids fallback.
      cases = [
        # {postcode, expected_lat_range, expected_lng_range}
        # The lat/lng range bounds the area centroid loosely so
        # we don't hard-code the actual value.
        {"AB25 3JT", {57.0, 57.5}, {-2.5, -1.5}},
        {"IV2 3BH", {57.0, 57.8}, {-4.8, -3.5}},
        {"BN2 5EQ", {50.5, 51.2}, {-0.5, 0.0}},
        {"CB1 2AD", {52.0, 52.5}, {0.0, 0.5}},
        {"PL4 6AB", {50.2, 50.7}, {-4.5, -3.8}},
        {"BT9 5LS", {54.4, 54.9}, {-6.5, -5.5}}
      ]

      for {pc, {lat_min, lat_max}, {lng_min, lng_max}} <- cases do
        assert {:ok, %{latitude: lat, longitude: lng}} = Geocoder.Seeded.lookup(pc),
               "area-fallback should resolve #{pc}"

        assert lat >= lat_min and lat <= lat_max,
               "#{pc} lat #{lat} outside expected range #{lat_min}..#{lat_max}"

        assert lng >= lng_min and lng <= lng_max,
               "#{pc} lng #{lng} outside expected range #{lng_min}..#{lng_max}"
      end
    end

    test "covers every PRD §12.1 postcode (smoke)" do
      prd_postcodes = ~w(
        EC1A1BB E16AN SW1A1AA N19GU W1A1AB
        M11AE M23WS M34FP M41DH
        B11AA B24BS B33HN B54UA
        LS11UR LS27EY LS61JL
        G11XQ G24PJ G37DN
        EH11YZ EH22AD EH39RG
        CF101EP CF119HW CF144HH
        BS14DJ BS20JT BS81TH
        L18JQ L22DP L35UX
        S12HE S24SU S37HG
        NE14ST NE24PT
        NG15FS NG72RD
        GU14LZ GU27XH
      )

      for pc <- prd_postcodes do
        assert {:ok, _} = Geocoder.Seeded.lookup(pc), "missing seed for postcode #{pc}"
      end
    end
  end

  describe "Geocoder dispatch (uses configured adapter)" do
    test "Geocoder.lookup/1 delegates to the configured adapter" do
      # In test env we expect Seeded to be configured.
      assert {:ok, _} = Geocoder.lookup("EC1A 1BB")
      assert {:error, :unknown_postcode} = Geocoder.lookup("XX99 9XX")
    end
  end
end
