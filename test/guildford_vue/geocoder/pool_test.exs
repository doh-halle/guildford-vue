defmodule GuildfordVue.Geocoder.PoolTest do
  @moduledoc """
  Sprint 5 Slice 2 — supervised geocoding worker pool. Public API:

      Pool.lookup(pc)         — synchronous, cache-aware
      Pool.lookup_many(pcs)   — parallel via Task.Supervisor

  Backed by an ETS cache (`Geocoder.Cache`) and the configured
  adapter (`GuildfordVue.Geocoder`). Cache hit short-circuits the
  adapter entirely.
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.Geocoder.{Cache, Pool}

  setup do
    Cache.reset()
    :ok
  end

  describe "lookup/1" do
    test "cache miss → adapter → caches the result" do
      assert {:ok, %{latitude: _, longitude: _}} = Pool.lookup("M1 1AE")
      assert {:hit, {:ok, _}} = Cache.get("M1 1AE")
    end

    test "cache hit returns the cached value (skipping adapter)" do
      Cache.put("M1 1AE", {:ok, %{latitude: 99.0, longitude: 99.0}})
      assert {:ok, %{latitude: 99.0, longitude: 99.0}} = Pool.lookup("M1 1AE")
    end

    test "negative cache hit" do
      Cache.put("XX99 9XX", {:error, :unknown_postcode})
      assert {:error, :unknown_postcode} = Pool.lookup("XX99 9XX")
    end

    test "miss caches the negative too" do
      assert {:error, :unknown_postcode} = Pool.lookup("XX99 9XX")
      assert {:hit, {:error, :unknown_postcode}} = Cache.get("XX99 9XX")
    end
  end

  describe "lookup_many/1 — parallel lookups under Task.Supervisor" do
    test "returns one result per postcode in the same order" do
      results = Pool.lookup_many(["M1 1AE", "EC1A 1BB", "XX99 9XX"])

      assert [
               {:ok, %{}},
               {:ok, %{}},
               {:error, :unknown_postcode}
             ] = results
    end

    test "concurrent identical lookups all return the cached value" do
      # Prime the cache.
      {:ok, _} = Pool.lookup("M1 1AE")

      # 32 concurrent calls for the same postcode.
      tasks = for _ <- 1..32, do: Task.async(fn -> Pool.lookup("M1 1AE") end)
      results = Enum.map(tasks, &Task.await/1)

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
