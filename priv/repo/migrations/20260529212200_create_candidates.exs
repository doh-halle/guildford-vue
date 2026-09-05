defmodule GuildfordVue.Repo.Migrations.CreateCandidates do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :phone, :string
      add :postcode, :string
      add :email_verified_at, :utc_datetime_usec
      add :suspended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:candidates, [:email])

    create table(:candidate_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :candidate_id, references(:candidates, type: :binary_id, on_delete: :delete_all),
        null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:candidate_tokens, [:context, :token])
    create index(:candidate_tokens, [:candidate_id])
  end
end
