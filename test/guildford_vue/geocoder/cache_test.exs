defmodule GuildfordVue.Geocoder.CacheTest do
  @moduledoc """
  Sprint 5 Slice 2 — ETS cache in front of the Geocoder adapter.
  Postcodes never change, so every successful lookup is cached
  forever. Misses (unknown postcode) are also cached so we don't
  re-hit the adapter for the same bad input.
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.Geocoder.Cache

  setup do
    # Reset the cache between tests so they don't see each other's data.
    Cache.reset()
    :ok
  end

  describe "get/1 + put/2" do
    test "round-trip ok" do
      assert :miss = Cache.get("M1 1AE")

      Cache.put("M1 1AE", {:ok, %{latitude: 53.4794, longitude: -2.2453}})

      assert {:hit, {:ok, %{latitude: 53.4794, longitude: -2.2453}}} = Cache.get("M1 1AE")
    end

    test "negative caching: errors are remembered too" do
      Cache.put("XX99 9XX", {:error, :unknown_postcode})

      assert {:hit, {:error, :unknown_postcode}} = Cache.get("XX99 9XX")
    end

    test "normalises whitespace + case on key" do
      Cache.put("m1 1ae", {:ok, %{latitude: 1.0, longitude: 1.0}})

      # Different casing / whitespace hits the same entry.
      assert {:hit, _} = Cache.get("M1 1AE")
      assert {:hit, _} = Cache.get("m11ae")
      assert {:hit, _} = Cache.get(" M1 1AE ")
    end
  end

  describe "reset/0" do
    test "clears every cached entry" do
      Cache.put("A1 1AA", {:ok, %{latitude: 1.0, longitude: 1.0}})
      Cache.reset()
      assert :miss = Cache.get("A1 1AA")
    end
  end
end
