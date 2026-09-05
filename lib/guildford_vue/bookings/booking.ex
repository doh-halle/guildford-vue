defmodule GuildfordVue.Bookings.Booking do
  @moduledoc """
  Persisted booking record. Created by the railway pipeline
  `GuildfordVue.Bookings.create_booking/3` after the slot has been
  reserved + payment recorded.

  Status ADT: `"confirmed" | "cancelled" | "refunded"`. "refunded"
  is a Sprint 8 follow-up state; included now so future migrations
  don't need to widen the validation list.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias GuildfordVue.Bookings.BookingReference

  @type t :: %__MODULE__{}
  @statuses ~w(confirmed cancelled refunded)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bookings" do
    field :reference, :string
    field :status, :string, default: "confirmed"
    field :price_pence, :integer
    field :candidate_id, :binary_id
    field :slot_id, :binary_id
    field :exam_id, :binary_id
    field :exam_centre_id, :binary_id
    field :paid_at, :utc_datetime_usec
    field :payment_token, :string
    field :pdf_url, :string
    field :cancelled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Create changeset. `reference` MUST be valid format + unique."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(booking, attrs) do
    booking
    |> cast(attrs, [
      :reference,
      :status,
      :price_pence,
      :candidate_id,
      :slot_id,
      :exam_id,
      :exam_centre_id,
      :paid_at,
      :payment_token,
      :pdf_url
    ])
    |> validate_required([
      :reference,
      :status,
      :price_pence,
      :candidate_id,
      :slot_id,
      :exam_id,
      :exam_centre_id
    ])
    |> validate_inclusion(:status, @statuses,
      message: "must be one of: #{Enum.join(@statuses, ", ")}"
    )
    |> validate_number(:price_pence, greater_than_or_equal_to: 0)
    |> validate_change(:reference, fn :reference, ref ->
      if BookingReference.valid?(ref),
        do: [],
        else: [reference: "is not a valid booking reference"]
    end)
    |> unsafe_validate_unique(:reference, GuildfordVue.Repo)
    |> unique_constraint(:reference)
  end

  @doc "Cancellation changeset — flips status + stamps cancelled_at."
  @spec cancel_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def cancel_changeset(booking, %DateTime{} = at) do
    change(booking,
      status: "cancelled",
      cancelled_at: DateTime.truncate(at, :microsecond)
    )
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Refund changeset — flips status to refunded + stamps cancelled_at."
  @spec refund_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def refund_changeset(booking, %DateTime{} = at) do
    change(booking,
      status: "refunded",
      cancelled_at: DateTime.truncate(at, :microsecond)
    )
    |> validate_inclusion(:status, @statuses)
  end
end
