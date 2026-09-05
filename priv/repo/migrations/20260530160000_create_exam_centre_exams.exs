defmodule GuildfordVue.Repo.Migrations.CreateExamCentreExams do
  use Ecto.Migration

  def change do
    create table(:exam_centre_exams, primary_key: false) do
      add :exam_centre_id,
          references(:exam_centres, type: :binary_id, on_delete: :delete_all),
          null: false

      add :exam_id, references(:exams, type: :binary_id, on_delete: :restrict), null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:exam_centre_exams, [:exam_centre_id, :exam_id])
    create index(:exam_centre_exams, [:exam_id])
  end
end
