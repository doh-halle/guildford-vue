defmodule GuildfordVue.Repo.Migrations.CreateSlots do
  use Ecto.Migration

  def change do
    create table(:slots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :exam_centre_id,
          references(:exam_centres, type: :binary_id, on_delete: :restrict),
          null: false

      add :exam_id, references(:exams, type: :binary_id, on_delete: :restrict), null: false

      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec, null: false
      add :capacity, :integer, null: false
      add :available_count, :integer, null: false
      add :status, :string, null: false, default: "open"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:slots, [:exam_centre_id, :starts_at])
    create index(:slots, [:exam_id, :starts_at])
    create index(:slots, [:status])

    # Enforce the invariant at the storage layer too — defence in depth
    # against any future code path that tries to oversell a slot.
    create constraint(:slots, :available_count_nonneg, check: "available_count >= 0")
    create constraint(:slots, :available_count_lte_capacity, check: "available_count <= capacity")
    create constraint(:slots, :capacity_positive, check: "capacity > 0")
  end
end
