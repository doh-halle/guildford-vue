defmodule GuildfordVue.Repo.Migrations.CreateAuditLogEvents do
  use Ecto.Migration

  def change do
    create table(:audit_log_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :aggregate_id, :binary_id
      # Actor — the admin who performed the action. Nullable because some
      # events are system-driven (e.g. cron jobs, automated cleanups).
      add :actor_id, :binary_id
      add :actor_type, :string
      add :payload, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:audit_log_events, [:event_type])
    create index(:audit_log_events, [:aggregate_id])
    create index(:audit_log_events, [:actor_id])
    create index(:audit_log_events, [:inserted_at])
  end
end
