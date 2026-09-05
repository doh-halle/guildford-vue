defmodule GuildfordVue.Repo.Migrations.CreateBookings do
  use Ecto.Migration

  def change do
    create table(:bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :reference, :string, null: false
      add :status, :string, null: false, default: "confirmed"
      add :price_pence, :integer, null: false

      add :candidate_id,
          references(:candidates, type: :binary_id, on_delete: :restrict),
          null: false

      add :slot_id,
          references(:slots, type: :binary_id, on_delete: :restrict),
          null: false

      add :exam_id, references(:exams, type: :binary_id, on_delete: :restrict), null: false

      add :exam_centre_id,
          references(:exam_centres, type: :binary_id, on_delete: :restrict),
          null: false

      add :paid_at, :utc_datetime_usec
      add :payment_token, :string
      add :pdf_url, :string
      add :cancelled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bookings, [:reference])
    create index(:bookings, [:candidate_id, :inserted_at])
    create index(:bookings, [:slot_id])
    create index(:bookings, [:exam_centre_id])

    create constraint(:bookings, :price_pence_nonneg, check: "price_pence >= 0")
  end
end
