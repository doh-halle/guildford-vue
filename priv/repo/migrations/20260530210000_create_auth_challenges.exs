defmodule GuildfordVue.Repo.Migrations.CreateAuthChallenges do
  use Ecto.Migration

  def change do
    create table(:auth_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :subject_type, :string, null: false, size: 32
      add :subject_id, :binary_id, null: false
      add :purpose, :string, null: false, size: 32
      add :code_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :attempts, :integer, null: false, default: 0
      add :consumed_at, :utc_datetime_usec
      add :ip_hash, :string, size: 128

      timestamps(type: :utc_datetime_usec)
    end

    create index(:auth_challenges, [:subject_type, :subject_id, :consumed_at])
    create index(:auth_challenges, [:inserted_at])
  end
end
