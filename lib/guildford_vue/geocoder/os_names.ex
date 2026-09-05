defmodule GuildfordVue.Geocoder.OSNames do
  @moduledoc """
  Production adapter that would call the Ordnance Survey OS Names API
  (https://api.os.uk/search/names/v1/). The dissertation reference
  implementation doesn't make live network calls, so this returns
  `{:error, :not_implemented}` — production should swap in a real
  HTTP client (e.g. Req) and a per-request OS_API_KEY.

  Wire up via:

      config :guildford_vue, :geocoder, GuildfordVue.Geocoder.OSNames
  """
  @behaviour GuildfordVue.Geocoder

  @impl GuildfordVue.Geocoder
  def lookup(_postcode), do: {:error, :not_implemented}
end
