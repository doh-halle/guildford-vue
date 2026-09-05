defmodule GuildfordVue.Candidates.Candidate do
  @moduledoc """
  Candidate user — UK resident booking exam slots. One of three independent
  auth scopes (alongside `GuildfordVue.Admins.Admin` and
  `GuildfordVue.ExamCentres.ExamCentre`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "candidates" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :first_name, :string
    field :last_name, :string
    field :phone, :string
    field :postcode, :string
    field :email_verified_at, :utc_datetime_usec
    field :suspended_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for registering a new candidate. Hashes the password via Argon2id.
  """
  @spec registration_changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def registration_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:email, :password, :first_name, :last_name, :phone, :postcode])
    |> validate_required([:email, :password, :first_name, :last_name])
    |> validate_email()
    |> validate_password()
    |> validate_length(:first_name, max: 80)
    |> validate_length(:last_name, max: 80)
    |> validate_length(:phone, max: 32)
    |> validate_length(:postcode, max: 16)
  end

  @doc "Changeset used for password reset — replaces the hash."
  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
  end

  @doc "Marks the candidate as email-verified at the given moment."
  @spec confirm_email_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def confirm_email_changeset(candidate, %DateTime{} = at) do
    change(candidate, email_verified_at: DateTime.truncate(at, :microsecond))
  end

  @doc "Stamps suspended_at."
  @spec suspend_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def suspend_changeset(candidate, %DateTime{} = at) do
    change(candidate, suspended_at: DateTime.truncate(at, :microsecond))
  end

  @doc "Clears suspended_at."
  @spec reactivate_changeset(t()) :: Ecto.Changeset.t()
  def reactivate_changeset(candidate) do
    change(candidate, suspended_at: nil)
  end

  # --- internal validation helpers ---

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

  # Sprint 11.5 Slice 5 — HIBP breached-password check. Sits between
  # validate_length and hash_password so we never hash a known-bad
  # password and the changeset surfaces the breached error before
  # the put_change(:hashed_password, …) step. The Stub adapter (the
  # default) returns :ok for everything; the real network-backed
  # adapter is a config swap in a later sprint.
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
            # Backend hiccup → treat as :ok so a network blip never
            # blocks a legitimate registration / password reset.
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

  @doc """
  Verifies a plaintext password against the stored hash. Returns the candidate
  on success, nil otherwise. Always spends the same time whether or not the
  candidate exists, to defeat timing attacks (call with `nil` for the candidate
  to consume the same Argon2 work without comparing).
  """
  @spec valid_password?(t() | nil, String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and is_binary(password) do
    Argon2.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end
end
