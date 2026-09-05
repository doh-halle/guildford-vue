defmodule GuildfordVue.PaymentGateway.Stub do
  @moduledoc """
  Always-succeed payment adapter. Returns a synthetic token (prefixed
  `tok_stub_`) so audit log entries are recognisable as stubs and
  Sprint 8's Simulated adapter can token-prefix differently to avoid
  confusion when the in-tree benchmark dumps payments.

  Since Sprint 8 Slice 5, the result shape matches Simulated's —
  includes `:provider` (derived from the optional `payment_method`
  opt, defaulting to "visa") and `:masked_pan` (derived from the
  optional `card` opt, nil otherwise). This keeps the pipeline's
  Payment-row writer free of adapter-specific branching.
  """
  @behaviour GuildfordVue.PaymentGateway

  alias GuildfordVue.Payments.{Card, PaymentMethod}

  @impl true
  def charge(amount_pence, opts) when is_integer(amount_pence) and amount_pence > 0 do
    token = "tok_stub_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))

    {:ok,
     %{
       token: token,
       charged_at: DateTime.utc_now(),
       provider: provider_from_opts(opts),
       masked_pan: masked_pan_from_opts(opts)
     }}
  end

  def charge(_, _), do: {:error, :invalid_amount}

  defp provider_from_opts(opts) do
    case Map.get(opts || %{}, :payment_method) do
      m when is_atom(m) and m in [:visa, :mastercard, :amex, :paypal, :apple_pay, :google_pay] ->
        PaymentMethod.to_string(m)

      _ ->
        "visa"
    end
  end

  defp masked_pan_from_opts(opts) do
    case Map.get(opts || %{}, :card) do
      %Card{} = c -> Card.masked_pan(c)
      _ -> nil
    end
  end
end
