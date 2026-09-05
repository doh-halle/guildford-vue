defmodule GuildfordVue.Repo.Migrations.CreateAnnouncements do
  use Ecto.Migration

  def change do
    create table(:announcements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :text, :string, size: 280, null: false
      add :posted_by_admin_id, references(:admins, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # The "current" announcement is the most-recent row. We keep
    # history for the audit log + admin "previous banners" view
    # rather than truncating.
    create index(:announcements, [:inserted_at])
  end
end
