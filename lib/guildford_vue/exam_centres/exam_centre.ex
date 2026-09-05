defmodule GuildfordVue.ExamCentres.ExamCentre do
  @moduledoc """
  Accredited exam centre — books slots, accepts candidates. One of three
  independent auth scopes.

  Status is an ADT: `"pending" | "approved" | "suspended"`. New centres land
  in `"pending"` and cannot log in until an admin approves them.

  PostGIS `geom` is populated from lat/lng on save so Sprint 5's
  `ST_DWithin`-based proximity search can index against it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Geo.Point
  alias GuildfordVue.Geocoder.Pool, as: GeocoderPool

  @type t :: %__MODULE__{}
  @statuses ~w(pending approved suspended rejected)
  @srid 4326

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exam_centres" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :name, :string
    field :address_line_1, :string
    field :address_line_2, :string
    field :city, :string
    field :postcode, :string
    field :latitude, :float
    field :longitude, :float
    field :geom, Geo.PostGIS.Geometry
    field :contact_phone, :string
    field :accreditation_evidence_url, :string
    field :status, :string, default: "pending"
    field :approved_at, :utc_datetime_usec
    field :approved_by_admin_id, :binary_id
    field :rejected_at, :utc_datetime_usec
    field :rejected_by_admin_id, :binary_id
    field :rejection_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Self-registration changeset — sets status: \"pending\" and computes geom."
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(centre, attrs) do
    centre
    |> cast(attrs, [
      :email,
      :password,
      :name,
      :address_line_1,
      :address_line_2,
      :city,
      :postcode,
      :latitude,
      :longitude,
      :contact_phone,
      :accreditation_evidence_url
    ])
    |> validate_required([
      :email,
      :password,
      :name,
      :address_line_1,
      :city,
      :postcode
    ])
    |> validate_email()
    |> validate_password()
    |> validate_length(:name, max: 160)
    |> validate_length(:address_line_1, max: 160)
    |> validate_length(:address_line_2, max: 160)
    |> validate_length(:city, max: 80)
    |> validate_length(:postcode, max: 16)
    |> put_change(:status, "pending")
    |> maybe_geocode_postcode(strict?: false)
    |> compute_geom()
  end

  @doc """
  Profile self-service changeset for the centre operator. Only the
  fields a centre is allowed to change about itself:
    - name, address lines, city, postcode
    - contact_phone, accreditation_evidence_url
    - latitude/longitude (Slice 5 will derive these from postcode
      via a Geocoder behaviour; for now the caller can pass them
      explicitly)

  Explicitly NOT castable: email (auth-scope identity), password,
  status, approved_at, approved_by_admin_id, rejected_at, etc.
  Recomputes geom when lat/lng change.
  """
  @spec profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(centre, attrs) do
    centre
    |> cast(attrs, [
      :name,
      :address_line_1,
      :address_line_2,
      :city,
      :postcode,
      :latitude,
      :longitude,
      :contact_phone,
      :accreditation_evidence_url
    ])
    |> validate_required([:name, :address_line_1, :city, :postcode])
    |> validate_length(:name, max: 160)
    |> validate_length(:address_line_1, max: 160)
    |> validate_length(:address_line_2, max: 160)
    |> validate_length(:city, max: 80)
    |> validate_length(:postcode, max: 16)
    |> validate_length(:contact_phone, max: 32)
    |> validate_url(:accreditation_evidence_url)
    |> normalise_blank(:accreditation_evidence_url)
    |> maybe_geocode_postcode()
    |> compute_geom()
  end

  # If postcode is changing and lat/lng weren't explicitly set on this
  # changeset, look the postcode up via the configured Geocoder and
  # populate lat/lng from the result.
  #
  # The strict?: option controls how a geocoder miss is surfaced:
  #   * strict?: true (default — used by profile updates) — unknown
  #     postcode is a validation error, the user gets immediate
  #     feedback.
  #   * strict?: false (used by registration) — silently accept the
  #     row with nil lat/lng. The centre will appear on the map
  #     after they update their profile (or a future admin
  #     reconciliation runs the geocoder again). Registration
  #     shouldn't fail just because the seeded geocoder doesn't
  #     know a postcode — the centre still needs to exist so an
  #     admin can review.
  defp maybe_geocode_postcode(changeset, opts \\ [])
  defp maybe_geocode_postcode(%Ecto.Changeset{valid?: false} = changeset, _opts), do: changeset

  defp maybe_geocode_postcode(changeset, opts) do
    postcode_changed? = Map.has_key?(changeset.changes, :postcode)

    explicit_coords? =
      Map.has_key?(changeset.changes, :latitude) or
        Map.has_key?(changeset.changes, :longitude)

    strict? = Keyword.get(opts, :strict?, true)

    cond do
      not postcode_changed? -> changeset
      explicit_coords? -> changeset
      true -> apply_geocode(changeset, strict?)
    end
  end

  defp apply_geocode(changeset, strict?) do
    case GeocoderPool.lookup(get_change(changeset, :postcode)) do
      {:ok, %{latitude: lat, longitude: lng}} ->
        changeset
        |> put_change(:latitude, lat)
        |> put_change(:longitude, lng)

      {:error, _} when not strict? ->
        changeset

      {:error, :unknown_postcode} ->
        add_error(changeset, :postcode, "is unknown — geocoder could not locate it")

      {:error, :not_implemented} ->
        add_error(changeset, :postcode, "geocoding is not available")

      {:error, _} ->
        add_error(changeset, :postcode, "could not be geocoded")
    end
  end

  @doc """
  Changeset used for password reset — replaces the hash only. Status,
  address, name, and approver are untouched. Mirrors
  `Candidates.Candidate.password_changeset/2` and
  `Admins.Admin.password_changeset/2`.
  """
  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(centre, attrs) do
    centre
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
  end

  @doc "Approval changeset — flips status to :approved and stamps approver."
  @spec approval_changeset(t(), binary(), DateTime.t()) :: Ecto.Changeset.t()
  def approval_changeset(centre, admin_id, %DateTime{} = at) do
    centre
    |> change(
      status: "approved",
      approved_at: DateTime.truncate(at, :microsecond),
      approved_by_admin_id: admin_id
    )
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Suspend changeset — flips status to :suspended."
  @spec suspend_changeset(t()) :: Ecto.Changeset.t()
  def suspend_changeset(centre) do
    change(centre, status: "suspended")
  end

  @doc """
  Reject changeset — flips status to :rejected and records who, when, why.
  Rejection is terminal in this slice — Sprint 9 may add an
  appeal/re-submit flow, at which point this becomes a transition the
  centre itself can trigger (via re-registration with the same email).
  """
  @spec reject_changeset(t(), binary(), DateTime.t(), String.t()) :: Ecto.Changeset.t()
  def reject_changeset(centre, admin_id, %DateTime{} = at, reason) when is_binary(reason) do
    centre
    |> change(
      status: "rejected",
      rejected_at: DateTime.truncate(at, :microsecond),
      rejected_by_admin_id: admin_id,
      rejection_reason: reason
    )
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Reactivate changeset — back to :approved (only allowed from :suspended)."
  @spec reactivate_changeset(t()) :: Ecto.Changeset.t()
  def reactivate_changeset(centre) do
    change(centre, status: "approved")
  end

  @spec valid_password?(t() | nil, String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and is_binary(password) do
    Argon2.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  # ---- helpers ----

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &normalise_email/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, GuildfordVue.Repo)
    |> unique_constraint(:email)
  end

  defp normalise_email(nil), do: nil

  defp normalise_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> validate_not_breached()
    |> hash_password()
  end

  # Sprint 11.5 Slice 5 — HIBP breached-password check (see
  # `GuildfordVue.PasswordBreach`). Stub default returns :ok; the
  # real adapter is a config swap in a later sprint.
  defp validate_not_breached(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_not_breached(changeset) do
    case Ecto.Changeset.get_change(changeset, :password) do
      password when is_binary(password) ->
        case GuildfordVue.PasswordBreach.check(password) do
          :ok ->
            changeset

          {:error, :breached, count} ->
            Ecto.Changeset.add_error(
              changeset,
              :password,
              "has appeared in #{count} known data breaches — please choose another",
              validation: :breached_password,
              count: count
            )

          {:error, _reason} ->
            changeset
        end

      _ ->
        changeset
    end
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset)
       when is_binary(password) do
    changeset
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset

  defp compute_geom(%Ecto.Changeset{valid?: true} = changeset) do
    lat = get_field(changeset, :latitude)
    lng = get_field(changeset, :longitude)

    if is_number(lat) and is_number(lng) do
      point = %Point{coordinates: {lng * 1.0, lat * 1.0}, srid: @srid}
      put_change(changeset, :geom, point)
    else
      changeset
    end
  end

  defp compute_geom(changeset), do: changeset

  defp validate_url(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      "" ->
        changeset

      url when is_binary(url) ->
        if Regex.match?(~r{\Ahttps?://[^\s]+\z}i, url) do
          changeset
        else
          add_error(changeset, field, "must start with http:// or https://")
        end

      _ ->
        add_error(changeset, field, "must be a URL")
    end
  end

  defp normalise_blank(changeset, field) do
    case get_change(changeset, field) do
      "" -> put_change(changeset, field, nil)
      _ -> changeset
    end
  end
end
