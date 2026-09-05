defmodule GuildfordVue.Announcements.Announcement do
  @moduledoc """
  Platform-wide broadcast banner row. Append-only — the current
  banner is the most-recent insert; `clear/0` records a tombstone
  via Application.env rather than deleting rows so the audit log
  trail stays intact.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "announcements" do
    field :text, :string
    field :posted_by_admin_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(announcement, attrs) do
    announcement
    |> cast(attrs, [:text, :posted_by_admin_id])
    |> update_change(:text, &trim_or_nil/1)
    |> validate_required([:text, :posted_by_admin_id])
    |> validate_length(:text, min: 1, max: 280)
  end

  defp trim_or_nil(nil), do: nil

  defp trim_or_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
