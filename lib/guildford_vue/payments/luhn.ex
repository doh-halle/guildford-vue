defmodule GuildfordVue.Payments.Luhn do
  @moduledoc """
  Luhn mod-10 checksum validation. Pure function, no
  card-network awareness — just the algorithm. Card-brand
  detection lives in `GuildfordVue.Payments.PaymentMethod` (Slice 2).

  Accepts strings with embedded whitespace / hyphens (the way
  humans actually type card numbers). Returns false for anything
  not parsable as a 12–19 digit sequence.
  """

  @spec valid?(any()) :: boolean()
  def valid?(s) when is_binary(s) do
    digits = String.replace(s, ~r/[\s-]/, "")

    if String.match?(digits, ~r/\A\d{12,19}\z/),
      do: checksum(digits) == 0,
      else: false
  end

  def valid?(_), do: false

  defp checksum(digits) do
    digits
    |> String.graphemes()
    |> Enum.map(&String.to_integer/1)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(&weighted/1)
    |> Enum.sum()
    |> rem(10)
  end

  defp weighted({d, i}) when rem(i, 2) == 1, do: doubled(d)
  defp weighted({d, _i}), do: d

  defp doubled(d) when d < 5, do: d * 2
  defp doubled(d), do: d * 2 - 9
end
