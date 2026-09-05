defmodule GuildfordVue.PaymentGateway do
  @moduledoc """
  Payment-processing boundary. The booking pipeline (Sprint 7) calls
  this; an adapter actually moves the money. The PRD ships two
  in-tree adapters and reserves space for a real one in Sprint 8:

    * `GuildfordVue.PaymentGateway.Stub`     — always succeeds.
      Used in dev/test and as the Sprint 7 default while the
      Sprint 8 payment-simulation UI is being built.
    * `GuildfordVue.PaymentGateway.Decline`  — always declines.
      Useful for testing the booking pipeline's rollback branch.
    * `GuildfordVue.PaymentGateway.Simulated` — (Sprint 8) random
      decline rate, masked card details, randomised latency.

  Pick via `config :guildford_vue, :payment_gateway, Adapter`.
  """

  @type charge_opts :: %{optional(any()) => any()}
  @type charge_result :: {:ok, %{token: String.t(), charged_at: DateTime.t()}} | {:error, atom()}

  @callback charge(amount_pence :: pos_integer(), opts :: charge_opts()) :: charge_result()

  @spec charge(pos_integer(), charge_opts()) :: charge_result()
  def charge(amount_pence, opts \\ %{}) do
    adapter().charge(amount_pence, opts)
  end

  defp adapter do
    Application.get_env(:guildford_vue, :payment_gateway, GuildfordVue.PaymentGateway.Stub)
  end
end
