defmodule GuildfordVue.Candidates.CandidateToken do
  @moduledoc """
  Tokens used by the candidate auth scope for session persistence, email
  verification, and password reset. Tokens stored in DB are SHA-256 digests
  of the random URL-safe token issued to the candidate — the database never
  sees the raw token, so a DB read cannot impersonate.
  """
  use Ecto.Schema
  import Ecto.Query

  alias GuildfordVue.Candidates.{Candidate, CandidateToken}

  @hash_algorithm :sha256
  @rand_size 32

  @session_validity_in_days 30
  @verify_validity_in_days 7
  @reset_validity_in_days 1

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "candidate_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :candidate, Candidate

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  # ---------- Session ----------

  @doc "Returns {raw_token, %CandidateToken{}} for a new session."
  @spec build_session_token(Candidate.t()) :: {binary(), t()}
  def build_session_token(%Candidate{id: id}) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %CandidateToken{token: token, context: "session", candidate_id: id}}
  end

  @doc """
  Query that returns the candidate for a valid session token (≤ 30 days old
  and not suspended).
  """
  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Queryable.t()}
  def verify_session_token_query(token) do
    query =
      from t in CandidateToken,
        join: c in assoc(t, :candidate),
        where:
          t.token == ^token and
            t.context == "session" and
            t.inserted_at > ago(@session_validity_in_days, "day") and
            is_nil(c.suspended_at),
        select: c

    {:ok, query}
  end

  # ---------- Email verification ----------

  @doc "Returns {url_safe_token, %CandidateToken{}} for the email-verification context."
  @spec build_email_verification_token(Candidate.t()) :: {String.t(), t()}
  def build_email_verification_token(%Candidate{} = candidate) do
    build_hashed_token(candidate, "verify-email", candidate.email)
  end

  @doc """
  Looks up the candidate for a raw url-safe verification token, if it has not
  expired. Returns {:ok, candidate} or {:error, :invalid_token}.
  """
  @spec verify_email_token_query(String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def verify_email_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in CandidateToken,
            join: c in assoc(t, :candidate),
            where:
              t.token == ^hashed and
                t.context == "verify-email" and
                t.sent_to == c.email and
                t.inserted_at > ago(@verify_validity_in_days, "day"),
            select: c

        {:ok, query}

      :error ->
        {:error, :invalid_token}
    end
  end

  # ---------- Password reset ----------

  @doc "Returns {url_safe_token, %CandidateToken{}} for the password-reset context."
  @spec build_password_reset_token(Candidate.t()) :: {String.t(), t()}
  def build_password_reset_token(%Candidate{} = candidate) do
    build_hashed_token(candidate, "reset-password", candidate.email)
  end

  @doc "Same shape as verify_email_token_query but for the password-reset context."
  @spec verify_password_reset_token_query(String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def verify_password_reset_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in CandidateToken,
            join: c in assoc(t, :candidate),
            where:
              t.token == ^hashed and
                t.context == "reset-password" and
                t.inserted_at > ago(@reset_validity_in_days, "day"),
            select: c

        {:ok, query}

      :error ->
        {:error, :invalid_token}
    end
  end

  # ---------- Queries used to revoke ----------

  @doc "Query that finds a single token row by raw bytes & context."
  @spec by_token_and_context_query(binary(), String.t()) :: Ecto.Queryable.t()
  def by_token_and_context_query(token, context) do
    from t in CandidateToken, where: t.token == ^token and t.context == ^context
  end

  @doc "Query that finds the token row for a raw url-safe token in a given context."
  @spec by_hashed_token_query(String.t(), String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def by_hashed_token_query(token, context) when context in ~w(verify-email reset-password) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        {:ok, from(t in CandidateToken, where: t.token == ^hashed and t.context == ^context)}

      :error ->
        {:error, :invalid_token}
    end
  end

  # --- internal ---

  defp build_hashed_token(%Candidate{id: id}, context, sent_to) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, raw)

    {Base.url_encode64(raw, padding: false),
     %CandidateToken{
       token: hashed,
       context: context,
       sent_to: sent_to,
       candidate_id: id
     }}
  end
end
