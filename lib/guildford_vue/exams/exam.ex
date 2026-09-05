defmodule GuildfordVue.Exams.Exam do
  @moduledoc """
  Exam catalogue entry — PRD §4.4 admin domain, §12.2 seed source.

  `code` is the public-facing short identifier (e.g. "DVSA-CAR",
  "AZ-104"). Uppercased on save so lookups are case-insensitive in
  the natural way. Immutable after creation — used as a stable
  cross-reference in URLs and audit payloads.

  `price_pence` is integer pence to keep money out of float-land.
  `duration_minutes` is the time the candidate is sitting the exam.

  Archive instead of delete — historical bookings keep their exam
  reference after a curriculum change.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exams" do
    field :name, :string
    field :code, :string
    field :certification_body, :string
    field :description, :string
    field :duration_minutes, :integer
    field :price_pence, :integer
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creation — `code` is required and uniqueness-checked."
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :name,
      :code,
      :certification_body,
      :description,
      :duration_minutes,
      :price_pence
    ])
    |> validate_required([
      :name,
      :code,
      :certification_body,
      :duration_minutes,
      :price_pence
    ])
    |> update_change(:code, &normalise_code/1)
    |> validate_length(:name, max: 160)
    |> validate_length(:code, max: 60)
    |> validate_length(:certification_body, max: 80)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_number(:price_pence, greater_than_or_equal_to: 0)
    |> unsafe_validate_unique(:code, GuildfordVue.Repo)
    |> unique_constraint(:code)
  end

  @doc "Changeset for update — `code` is intentionally NOT castable."
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(exam, attrs) do
    exam
    |> cast(attrs, [
      :name,
      :certification_body,
      :description,
      :duration_minutes,
      :price_pence
    ])
    |> validate_required([:name, :certification_body, :duration_minutes, :price_pence])
    |> validate_length(:name, max: 160)
    |> validate_length(:certification_body, max: 80)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_number(:price_pence, greater_than_or_equal_to: 0)
  end

  @spec archive_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def archive_changeset(exam, %DateTime{} = at) do
    change(exam, archived_at: DateTime.truncate(at, :microsecond))
  end

  defp normalise_code(nil), do: nil
  defp normalise_code(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
end
