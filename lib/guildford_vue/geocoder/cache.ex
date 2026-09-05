defmodule GuildfordVue.Geocoder.Cache do
  @moduledoc """
  ETS-backed cache in front of the configured `Geocoder` adapter.

  Postcodes don't change, so every successful lookup is cached
  forever. Misses (`{:error, :unknown_postcode}`) are also cached —
  re-asking the adapter for a postcode that's already been rejected
  would just waste time.

  Key normalisation: whitespace + case-insensitive. Different
  presentations of the same postcode hit the same entry.

  The cache table is named (`:guildford_vue_geocoder_cache`) and
  owned by this module's GenServer so the supervision tree restarts
  it cleanly. Started under `GuildfordVue.Centres.Supervisor`.
  """
  use GenServer

  @table :guildford_vue_geocoder_cache

  # -- Public API ---------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @type cached :: {:ok, %{latitude: float(), longitude: float()}} | {:error, atom()}

  @spec get(String.t() | nil) :: {:hit, cached()} | :miss
  def get(nil), do: :miss
  def get(""), do: :miss

  def get(postcode) when is_binary(postcode) do
    case :ets.lookup(@table, normalise(postcode)) do
      [{_, value}] -> {:hit, value}
      [] -> :miss
    end
  end

  @spec put(String.t(), cached()) :: :ok
  def put(postcode, value) when is_binary(postcode) do
    :ets.insert(@table, {normalise(postcode), value})
    :ok
  end

  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  # -- GenServer callbacks ------------------------------------------

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  defp normalise(postcode),
    do: postcode |> String.trim() |> String.upcase() |> String.replace(~r/\s+/, "")
end
