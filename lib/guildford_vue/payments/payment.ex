defmodule GuildfordVue.Payments.Payment do
  @moduledoc """
  Persisted payment record — one per booking.

  Status ADT: `"succeeded" | "declined" | "refunded"`. The
  `masked_pan` column is constrained on insert to refuse a raw
  PAN — defence in depth against a future code path that
  accidentally bypasses `Card.masked_pan/1`.

  PRD §9 NFR: card data is never persisted in cleartext. The
  `:masked_pan` field is the only piece of "card identity" we
  keep; the CVC + full PAN never touch the database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(succeeded declined refunded)
  @providers ~w(visa mastercard amex paypal apple_pay google_pay)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "payments" do
    field :booking_id, :binary_id
    field :provider, :string
    field :masked_pan, :string
    field :amount_pence, :integer
    field :status, :string
    field :declined_reason, :string
    field :processed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Create changeset for the Payments context's `record_payment/1`."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :booking_id,
      :provider,
      :masked_pan,
      :amount_pence,
      :status,
      :declined_reason,
      :processed_at
    ])
    |> validate_required([:booking_id, :provider, :amount_pence, :status, :processed_at])
    |> validate_inclusion(:status, @statuses,
      message: "must be one of: #{Enum.join(@statuses, ", ")}"
    )
    |> validate_inclusion(:provider, @providers,
      message: "must be one of: #{Enum.join(@providers, ", ")}"
    )
    |> validate_number(:amount_pence, greater_than: 0)
    |> validate_pan_is_masked()
  end

  # Defence in depth — `masked_pan` should never contain only digits
  # (that would mean a raw PAN landed). Storage CHECK could enforce
  # it too, but the changeset gives a friendlier error in tests.
  defp validate_pan_is_masked(changeset) do
    case get_change(changeset, :masked_pan) do
      nil ->
        changeset

      "" ->
        changeset

      pan when is_binary(pan) ->
        if String.match?(pan, ~r/\A\d+\z/),
          do: add_error(changeset, :masked_pan, "must be masked (digits only is not allowed)"),
          else: changeset
    end
  end
end
