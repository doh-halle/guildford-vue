defmodule GuildfordVue.Admins.Admin do
  @moduledoc """
  Platform administrator. One of three independent auth scopes.

  Roles:
    * `"operator"`  — default; can approve centres, manage candidates,
                      view audit log.
    * `"superadmin"` — additionally can invite/remove other admins and
                      access destructive ops.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @roles ~w(operator superadmin)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admins" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :name, :string
    field :role, :string, default: "operator"
    field :suspended_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :password, :name, :role])
    |> validate_required([:email, :password, :name])
    |> validate_email()
    |> validate_password()
    |> validate_inclusion(:role, @roles, message: "must be one of: #{Enum.join(@roles, ", ")}")
    |> validate_length(:name, max: 120)
  end

  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
  end

  @spec suspend_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def suspend_changeset(admin, %DateTime{} = at) do
    change(admin, suspended_at: DateTime.truncate(at, :microsecond))
  end

  @spec reactivate_changeset(t()) :: Ecto.Changeset.t()
  def reactivate_changeset(admin), do: change(admin, suspended_at: nil)

  @spec valid_password?(t() | nil, String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and is_binary(password) do
    Argon2.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  # --- helpers ---

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
end
