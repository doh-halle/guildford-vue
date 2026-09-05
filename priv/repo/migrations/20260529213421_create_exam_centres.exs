defmodule GuildfordVue.Repo.Migrations.CreateExamCentres do
  use Ecto.Migration

  def change do
    create table(:exam_centres, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :name, :string, null: false
      add :address_line_1, :string, null: false
      add :address_line_2, :string
      add :city, :string, null: false
      add :postcode, :string, null: false
      add :latitude, :float
      add :longitude, :float
      add :geom, :geometry
      add :contact_phone, :string
      add :accreditation_evidence_url, :string
      # ADT: status ∈ {pending, approved, suspended}
      # PRD §4.3: centres self-register as :pending and cannot log in until
      # an admin approves them.
      add :status, :string, null: false, default: "pending"
      add :approved_at, :utc_datetime_usec
      add :approved_by_admin_id, references(:admins, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:exam_centres, [:email])
    create index(:exam_centres, [:status])
    # GiST index on the PostGIS geom column for geo-spatial proximity queries
    # (Sprint 5 will use ST_DWithin against this).
    create index(:exam_centres, [:geom], using: :gist)

    create table(:exam_centre_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :exam_centre_id,
          references(:exam_centres, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:exam_centre_tokens, [:context, :token])
    create index(:exam_centre_tokens, [:exam_centre_id])
  end
end
