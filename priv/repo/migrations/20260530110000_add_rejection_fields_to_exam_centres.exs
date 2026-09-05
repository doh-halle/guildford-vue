defmodule GuildfordVue.Repo.Migrations.AddRejectionFieldsToExamCentres do
  use Ecto.Migration

  def change do
    alter table(:exam_centres) do
      add :rejected_at, :utc_datetime_usec
      add :rejected_by_admin_id, :binary_id
      add :rejection_reason, :text
    end
  end
end
