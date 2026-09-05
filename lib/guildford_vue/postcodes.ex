defmodule GuildfordVue.Postcodes do
  @moduledoc """
  UK postcode validation + canonical formatting.

  The structure is OUTWARD INWARD where:
    * OUTWARD = area (1–2 letters) + district (1–2 digits, optionally
      with a trailing letter)
    * INWARD  = sector (1 digit) + unit (2 letters)

  This module accepts the common formats (with or without internal
  whitespace, any case) and rejects obviously malformed input. It
  is intentionally regex-based rather than calling the Royal Mail
  database — the dissertation reference doesn't ship a postcode
  database, and the search surface tolerates the small false-positive
  rate of regex validation (an invalid postcode produces a geocoder
  miss, which produces a "we couldn't find that postcode" UI).
  """

  # OUTWARD: A[A]9[9A], INWARD: 9AA. From ONS spec, simplified.
  @regex ~r/\A[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\z/

  @spec validate(any()) :: {:ok, String.t()} | {:error, :invalid_postcode}
  def validate(nil), do: {:error, :invalid_postcode}
  def validate(""), do: {:error, :invalid_postcode}

  def validate(s) when is_binary(s) do
    canonical = s |> String.trim() |> String.upcase()

    if Regex.match?(@regex, canonical) do
      {:ok, format(canonical)}
    else
      {:error, :invalid_postcode}
    end
  end

  def validate(_), do: {:error, :invalid_postcode}

  @spec valid?(any()) :: boolean()
  def valid?(s) do
    case validate(s) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Re-formats a syntactically-valid postcode to canonical `OUT IN`
  form with a single space. Idempotent on already-canonical inputs.
  Returns the input unchanged if it doesn't look like a postcode.
  """
  @spec format(String.t()) :: String.t()
  def format(s) when is_binary(s) do
    cleaned = s |> String.trim() |> String.upcase() |> String.replace(~r/\s+/, "")

    case String.length(cleaned) do
      n when n in 5..7 ->
        # Inward is always the last 3 chars; everything before is outward.
        outward = String.slice(cleaned, 0..-4//1)
        inward = String.slice(cleaned, -3..-1//1)
        "#{outward} #{inward}"

      _ ->
        s
    end
  end
end
