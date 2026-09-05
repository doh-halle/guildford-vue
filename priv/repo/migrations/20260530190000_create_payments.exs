defmodule GuildfordVue.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :booking_id, references(:bookings, type: :binary_id, on_delete: :restrict), null: false

      add :provider, :string, null: false
      add :masked_pan, :string
      add :amount_pence, :integer, null: false
      add :status, :string, null: false
      add :declined_reason, :string
      add :processed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:payments, [:booking_id])

    create constraint(:payments, :amount_positive, check: "amount_pence > 0")
  end
end
