defmodule GuildfordVue.Bookings.BookingReference do
  @moduledoc """
  Human-friendly booking reference generator. Format:

      GV-YYYY-XXXXXX

  Where YYYY is the booking year and XXXXXX is a 6-character random
  suffix drawn from an alphabet that excludes scanner-confusable
  characters (`I`, `O`, `0`, `1`). PRD §4.7 acceptance: refs are
  short, spoken naturally, and impossible to misread off a printed
  receipt.

      iex> ref = GuildfordVue.Bookings.BookingReference.generate()
      iex> GuildfordVue.Bookings.BookingReference.valid?(ref)
      true
  """

  # 30-character alphabet. 30^6 = 729 000 000 possibilities — a
  # year-scoped collision is essentially nil at expected volumes.
  @alphabet ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
  @suffix_length 6

  @spec generate() :: String.t()
  def generate, do: generate(Date.utc_today().year)

  @spec generate(integer()) :: String.t()
  def generate(year) when is_integer(year) do
    suffix =
      for _ <- 1..@suffix_length, into: <<>> do
        <<Enum.random(@alphabet)>>
      end

    "GV-#{year}-#{suffix}"
  end

  @spec valid?(any()) :: boolean()
  def valid?(s) when is_binary(s) do
    Regex.match?(~r/\AGV-\d{4}-[A-HJ-NP-Z2-9]{6}\z/, s)
  end

  def valid?(_), do: false
end
