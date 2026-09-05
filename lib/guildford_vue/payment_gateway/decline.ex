defmodule GuildfordVue.PaymentGateway.Decline do
  @moduledoc """
  Always-decline payment adapter. Used in tests to exercise the
  booking pipeline's rollback branch — when a payment fails after
  a slot reservation, the reservation must be released.

  Wire in via test setup:

      Application.put_env(:guildford_vue, :payment_gateway,
        GuildfordVue.PaymentGateway.Decline)
  """
  @behaviour GuildfordVue.PaymentGateway

  @impl true
  def charge(_amount, _opts), do: {:error, :card_declined}
end
