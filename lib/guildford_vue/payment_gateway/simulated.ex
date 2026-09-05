defmodule GuildfordVue.PaymentGateway.Simulated do
  @moduledoc """
  Realistic-feeling payment simulator (PRD §4.8). Validates the
  card (for card-based methods), sleeps a randomised interval to
  imitate processor latency, then succeeds — except for a
  configurable fraction of attempts that decline.

  Configuration:

    * `:latency_ms` (opt) — fixed sleep in milliseconds. Defaults
      to a uniform-random value in 1500..3000. Tests pass `0`.
    * `:decline_rate` (opt) — float in 0.0..1.0. Defaults to the
      application env `:payment_decline_rate` (default 0.05). The
      Slice 6 admin toggle writes the app env so dev-mode operators
      can flip between 0% and 100% for demo purposes.

  Result shape (extends the behaviour's contract with provider +
  masked_pan so the Slice 5 pipeline can write the Payment row
  without re-deriving them):

      {:ok, %{
        token: "tok_sim_<rand>",
        charged_at: %DateTime{},
        provider: "visa" | "paypal" | ...,
        masked_pan: "•••• •••• •••• 4242" | nil
      }}

  Or `{:error, :card_declined | :invalid_card |
  :invalid_payment_method | :invalid_amount}`.
  """
  @behaviour GuildfordVue.PaymentGateway

  alias GuildfordVue.Payments.{Card, PaymentMethod}

  @default_latency_min_ms 1500
  @default_latency_max_ms 3000

  @impl GuildfordVue.PaymentGateway
  def charge(amount_pence, opts) when is_integer(amount_pence) and amount_pence > 0 do
    with {:ok, method} <- fetch_method(opts),
         :ok <- maybe_validate_card(method, opts) do
      sleep(opts)

      if declined?(opts) do
        {:error, :card_declined}
      else
        success_result(method, opts)
      end
    end
  end

  def charge(_, _), do: {:error, :invalid_amount}

  # ---- helpers ----

  defp fetch_method(opts) do
    case Map.get(opts, :payment_method) do
      m when m in [:visa, :mastercard, :amex, :paypal, :apple_pay, :google_pay] -> {:ok, m}
      _ -> {:error, :invalid_payment_method}
    end
  end

  defp maybe_validate_card(method, opts) do
    if PaymentMethod.accepts_card?(method) do
      case Map.get(opts, :card) do
        %Card{} -> :ok
        _ -> {:error, :invalid_card}
      end
    else
      :ok
    end
  end

  defp sleep(opts) do
    case Map.get(opts, :latency_ms) do
      ms when is_integer(ms) and ms > 0 ->
        Process.sleep(ms)

      0 ->
        :ok

      _ ->
        ms =
          :rand.uniform(@default_latency_max_ms - @default_latency_min_ms + 1) +
            @default_latency_min_ms - 1

        Process.sleep(ms)
    end
  end

  defp declined?(opts) do
    rate =
      Map.get(opts, :decline_rate) ||
        Application.get_env(:guildford_vue, :payment_decline_rate, 0.05)

    :rand.uniform() < rate
  end

  defp success_result(method, opts) do
    token = "tok_sim_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))

    masked_pan =
      case Map.get(opts, :card) do
        %Card{} = c -> Card.masked_pan(c)
        _ -> nil
      end

    {:ok,
     %{
       token: token,
       charged_at: DateTime.utc_now(),
       provider: PaymentMethod.to_string(method),
       masked_pan: masked_pan
     }}
  end
end
