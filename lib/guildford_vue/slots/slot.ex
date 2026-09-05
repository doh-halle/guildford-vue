defmodule GuildfordVue.Slots.Slot do
  @moduledoc """
  Exam slot — one bookable session at one centre for one exam.

  ADT-style status: `"open" | "full" | "cancelled"`. `available_count`
  is denormalised so reads don't need to count reservations. The
  per-centre GenServer (Slice 2) owns the authoritative in-memory
  state; this row is the durable snapshot.

  Storage-level CHECK constraints enforce the invariants that the
  GenServer enforces in memory — defence in depth against any future
  code path that tries to oversell.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @statuses ~w(open full cancelled)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slots" do
    field :exam_centre_id, :binary_id
    field :exam_id, :binary_id
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :capacity, :integer
    field :available_count, :integer
    field :status, :string, default: "open"

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creation changeset. `available_count` is auto-set to `capacity` —
  callers don't set it directly.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(slot, attrs) do
    slot
    |> cast(attrs, [:exam_centre_id, :exam_id, :starts_at, :ends_at, :capacity])
    |> validate_required([:exam_centre_id, :exam_id, :starts_at, :ends_at, :capacity])
    |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_in_future(:starts_at)
    |> validate_ends_after_starts()
    |> put_change(:status, "open")
    |> put_available_count()
  end

  @doc "Cancellation changeset — flips status to cancelled."
  @spec cancel_changeset(t()) :: Ecto.Changeset.t()
  def cancel_changeset(slot) do
    change(slot, status: "cancelled")
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Atomic reservation changeset — decrements available_count and (if
  it hits zero) flips status to "full". Called by the per-centre
  GenServer in Slice 2; not part of any LV's normal post path.
  """
  @spec reserve_changeset(t(), pos_integer()) :: Ecto.Changeset.t()
  def reserve_changeset(slot, count \\ 1) when is_integer(count) and count > 0 do
    new_available = slot.available_count - count

    new_status =
      cond do
        new_available < 0 -> slot.status
        new_available == 0 -> "full"
        true -> "open"
      end

    slot
    |> change(available_count: new_available, status: new_status)
    |> validate_number(:available_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Release reservation changeset — increments available_count and (if
  status was "full") flips back to "open".
  """
  @spec release_changeset(t(), pos_integer()) :: Ecto.Changeset.t()
  def release_changeset(slot, count \\ 1) when is_integer(count) and count > 0 do
    new_available = slot.available_count + count

    new_status =
      if slot.status == "full" and new_available > 0,
        do: "open",
        else: slot.status

    slot
    |> change(available_count: new_available, status: new_status)
    |> validate_number(:available_count, less_than_or_equal_to: slot.capacity)
  end

  # --- helpers ---

  defp validate_in_future(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      %DateTime{} = dt ->
        if DateTime.compare(dt, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, field, "must be in the future")
        end
    end
  end

  defp validate_ends_after_starts(changeset) do
    starts = get_field(changeset, :starts_at)
    ends = get_field(changeset, :ends_at)

    if is_struct(starts, DateTime) and is_struct(ends, DateTime) and
         DateTime.compare(ends, starts) == :gt do
      changeset
    else
      add_error(changeset, :ends_at, "must be after starts_at")
    end
  end

  defp put_available_count(changeset) do
    case get_change(changeset, :capacity) do
      nil -> changeset
      c when is_integer(c) -> put_change(changeset, :available_count, c)
    end
  end
end
