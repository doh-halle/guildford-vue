defmodule GuildfordVue.Payments do
  @moduledoc """
  Payments context (PRD §4.8). Persists payment records linked
  to bookings. The actual money-movement is the responsibility
  of `GuildfordVue.PaymentGateway` adapters — this context is
  the durable side.
  """
  import Ecto.Query, warn: false

  alias GuildfordVue.Payments.Payment
  alias GuildfordVue.Repo

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t()}

  @spec record_payment(map()) :: result(Payment.t())
  def record_payment(attrs) when is_map(attrs) do
    %Payment{}
    |> Payment.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_payment_for_booking(binary()) :: Payment.t() | nil
  def get_payment_for_booking(booking_id) when is_binary(booking_id) do
    Repo.one(
      from p in Payment,
        where: p.booking_id == ^booking_id,
        order_by: [desc: p.inserted_at],
        limit: 1
    )
  end
end
