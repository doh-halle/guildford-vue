defmodule GuildfordVue.Repo.Migrations.CreateExams do
  use Ecto.Migration

  def change do
    create table(:exams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :code, :string, null: false
      add :certification_body, :string, null: false
      add :description, :text
      add :duration_minutes, :integer, null: false
      add :price_pence, :integer, null: false
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:exams, [:code])
    create index(:exams, [:archived_at])
  end
end
