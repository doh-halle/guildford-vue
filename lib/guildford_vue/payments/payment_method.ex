defmodule GuildfordVue.Payments.PaymentMethod do
  @moduledoc """
  Payment-method ADT + provider catalogue (PRD §4.8). Pure module
  — the ADT is the canonical list of method atoms used across the
  Payment schema (as strings), the LV picker, and the
  PaymentGateway.Simulated adapter.

  ADT: `:visa | :mastercard | :amex | :paypal | :apple_pay | :google_pay`.
  """

  @type t :: :visa | :mastercard | :amex | :paypal | :apple_pay | :google_pay

  @all [:visa, :mastercard, :amex, :paypal, :apple_pay, :google_pay]

  @spec all() :: [t()]
  def all, do: @all

  @spec label(t()) :: String.t()
  def label(:visa), do: "Visa"
  def label(:mastercard), do: "Mastercard"
  def label(:amex), do: "Amex"
  def label(:paypal), do: "PayPal"
  def label(:apple_pay), do: "Apple Pay"
  def label(:google_pay), do: "Google Pay"

  @doc "True for card-based methods that need a PAN + CVC + expiry."
  @spec accepts_card?(t()) :: boolean()
  def accepts_card?(:visa), do: true
  def accepts_card?(:mastercard), do: true
  def accepts_card?(:amex), do: true
  def accepts_card?(:paypal), do: false
  def accepts_card?(:apple_pay), do: false
  def accepts_card?(:google_pay), do: false

  @doc """
  Detects the card brand from the PAN prefix. Returns nil for
  unknown brands. Visa / Mastercard / Amex coverage matches PRD;
  Discover and JCB are deliberately omitted — out of scope.
  """
  @spec detect_from_pan(any()) :: t() | nil
  def detect_from_pan(s) when is_binary(s) do
    digits = String.replace(s, ~r/[\s-]/, "")

    cond do
      String.starts_with?(digits, "4") -> :visa
      mastercard_prefix?(digits) -> :mastercard
      amex_prefix?(digits) -> :amex
      true -> nil
    end
  end

  def detect_from_pan(_), do: nil

  defp mastercard_prefix?(digits) do
    case digits do
      <<a::binary-size(2), _::binary>> when a in ~w(51 52 53 54 55) -> true
      <<a::binary-size(4), _::binary>> -> mastercard_4digit?(a)
      _ -> false
    end
  end

  # Mastercard 2-series range: 2221–2720
  defp mastercard_4digit?(<<"2", _::binary>> = s) do
    case Integer.parse(s) do
      {n, ""} -> n >= 2221 and n <= 2720
      _ -> false
    end
  end

  defp mastercard_4digit?(_), do: false

  defp amex_prefix?(digits) do
    case digits do
      <<a::binary-size(2), _::binary>> when a in ~w(34 37) -> true
      _ -> false
    end
  end

  @spec to_string(t()) :: String.t()
  def to_string(m) when m in @all, do: Atom.to_string(m)

  @spec from_string(any()) :: {:ok, t()} | :error
  def from_string(s) when is_binary(s) do
    case Enum.find(@all, fn m -> Atom.to_string(m) == s end) do
      nil -> :error
      m -> {:ok, m}
    end
  end

  def from_string(_), do: :error
end
