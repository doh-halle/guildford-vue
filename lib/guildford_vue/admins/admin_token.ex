defmodule GuildfordVue.Admins.AdminToken do
  @moduledoc """
  Token schema for the admin auth scope. Same shape as the candidate token —
  sessions store raw bytes, password-reset stores SHA-256 hash of a URL-safe
  token. The DB can never impersonate an admin via a stolen token row.
  """
  use Ecto.Schema
  import Ecto.Query

  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.Admins.AdminToken

  @hash_algorithm :sha256
  @rand_size 32

  @session_validity_in_days 14
  @reset_validity_in_days 1

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admin_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :admin, Admin

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  # ---------- Session ----------

  @spec build_session_token(Admin.t()) :: {binary(), t()}
  def build_session_token(%Admin{id: id}) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %AdminToken{token: token, context: "session", admin_id: id}}
  end

  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Queryable.t()}
  def verify_session_token_query(token) do
    query =
      from t in AdminToken,
        join: a in assoc(t, :admin),
        where:
          t.token == ^token and
            t.context == "session" and
            t.inserted_at > ago(@session_validity_in_days, "day") and
            is_nil(a.suspended_at),
        select: a

    {:ok, query}
  end

  # ---------- Password reset ----------

  @spec build_password_reset_token(Admin.t()) :: {String.t(), t()}
  def build_password_reset_token(%Admin{id: id, email: email}) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, raw)

    {Base.url_encode64(raw, padding: false),
     %AdminToken{token: hashed, context: "reset-password", sent_to: email, admin_id: id}}
  end

  @spec verify_password_reset_token_query(String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def verify_password_reset_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in AdminToken,
            join: a in assoc(t, :admin),
            where:
              t.token == ^hashed and
                t.context == "reset-password" and
                t.inserted_at > ago(@reset_validity_in_days, "day"),
            select: a

        {:ok, query}

      :error ->
        {:error, :invalid_token}
    end
  end

  # ---------- Lookup / revoke ----------

  @spec by_token_and_context_query(binary(), String.t()) :: Ecto.Queryable.t()
  def by_token_and_context_query(token, context) do
    from t in AdminToken, where: t.token == ^token and t.context == ^context
  end

  @spec by_hashed_token_query(String.t(), String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def by_hashed_token_query(token, context) when context == "reset-password" do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        {:ok, from(t in AdminToken, where: t.token == ^hashed and t.context == ^context)}

      :error ->
        {:error, :invalid_token}
    end
  end
end
