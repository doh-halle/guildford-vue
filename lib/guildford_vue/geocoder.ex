defmodule GuildfordVue.Geocoder do
  @moduledoc """
  Postcode → lat/lng geocoder. Two implementations:

    * `GuildfordVue.Geocoder.Seeded` — dev/test/seed. Hardcoded table
      of PRD §12.1 postcodes.
    * `GuildfordVue.Geocoder.OSNames` — prod stub (would call the OS
      Names API; not implemented in the dissertation reference).

  Pick via `config :guildford_vue, :geocoder, Adapter`.
  """

  @type result :: {:ok, %{latitude: float(), longitude: float()}} | {:error, atom()}

  @callback lookup(String.t() | nil) :: result()

  @doc "Dispatches to the configured adapter."
  @spec lookup(String.t() | nil) :: result()
  def lookup(postcode) do
    adapter().lookup(postcode)
  end

  defp adapter do
    Application.get_env(:guildford_vue, :geocoder, GuildfordVue.Geocoder.Seeded)
  end
end
