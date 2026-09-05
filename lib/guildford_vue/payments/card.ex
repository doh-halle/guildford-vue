defmodule GuildfordVue.Payments.Card do
  @moduledoc """
  Pure CardDetails struct + validation + masking. **The full PAN
  is never persisted** — `masked_pan/1` is the only safe form
  for storage, audit logs, or email confirmations.

  The struct exists only in-memory between form submit and the
  simulated payment processor's response. Once
  `PaymentGateway.Simulated.charge/2` returns, the only thing
  retained is the masked PAN + provider + token.
  """

  alias GuildfordVue.Payments.Luhn

  @enforce_keys [:number, :exp_month, :exp_year, :cvc, :holder_name]
  defstruct [:number, :exp_month, :exp_year, :cvc, :holder_name]

  @type t :: %__MODULE__{
          number: String.t(),
          exp_month: 1..12,
          exp_year: pos_integer(),
          cvc: String.t(),
          holder_name: String.t()
        }

  @type validation_error ::
          :invalid_card_number
          | :card_expired
          | :invalid_cvc
          | :invalid_expiry
          | :missing_holder_name

  @spec validate(map()) :: {:ok, t()} | {:error, validation_error()}
  def validate(attrs) when is_map(attrs) do
    with {:ok, holder} <- holder(attrs),
         {:ok, number} <- number(attrs),
         {:ok, {month, year}} <- expiry(attrs),
         {:ok, cvc} <- cvc(attrs) do
      {:ok,
       %__MODULE__{
         number: number,
         exp_month: month,
         exp_year: year,
         cvc: cvc,
         holder_name: holder
       }}
    end
  end

  @spec masked_pan(t()) :: String.t()
  def masked_pan(%__MODULE__{number: number}) do
    last4 = String.slice(number, -4..-1//1)
    star_count = max(String.length(number) - 4, 0)
    stars = String.duplicate("•", star_count)

    case String.length(number) do
      16 ->
        # Standard Visa/Mastercard/Discover — 4-4-4-4 grouping.
        "•••• •••• •••• " <> last4

      _ ->
        # Variable-length (Amex 15, Diners 14, etc.) — keep the
        # last-4 trailing group readable, mask the rest as a single
        # run. The receipt-eyeballing UX doesn't depend on any
        # particular intermediate grouping.
        stars <> " " <> last4
    end
  end

  # ---- internals ----

  defp holder(%{"holder_name" => name}) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :missing_holder_name}
      trimmed -> {:ok, trimmed}
    end
  end

  defp holder(_), do: {:error, :missing_holder_name}

  defp number(%{"number" => raw}) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s-]/, "")

    if Luhn.valid?(digits),
      do: {:ok, digits},
      else: {:error, :invalid_card_number}
  end

  defp number(_), do: {:error, :invalid_card_number}

  defp expiry(%{"exp_month" => m_s, "exp_year" => y_s})
       when is_binary(m_s) and is_binary(y_s) do
    with {month, ""} <- Integer.parse(m_s),
         {year, ""} <- Integer.parse(y_s),
         true <- month in 1..12,
         true <- year >= 2000 and year <= 2100 do
      case in_future?(month, year) do
        true -> {:ok, {month, year}}
        false -> {:error, :card_expired}
      end
    else
      _ -> {:error, :invalid_expiry}
    end
  end

  defp expiry(_), do: {:error, :invalid_expiry}

  defp cvc(%{"cvc" => raw}) when is_binary(raw) do
    if String.match?(raw, ~r/\A\d{3,4}\z/),
      do: {:ok, raw},
      else: {:error, :invalid_cvc}
  end

  defp cvc(_), do: {:error, :invalid_cvc}

  defp in_future?(month, year) do
    today = Date.utc_today()

    cond do
      year > today.year -> true
      year < today.year -> false
      true -> month >= today.month
    end
  end
end
