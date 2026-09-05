defmodule GuildfordVue.ExamCentres.ExamCentreToken do
  @moduledoc """
  Token schema for the exam-centre auth scope. Same shape as the candidate
  and admin token modules — sessions use raw bytes; password-reset uses
  SHA-256 of a URL-safe token.
  """
  use Ecto.Schema
  import Ecto.Query

  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.ExamCentres.ExamCentreToken

  @hash_algorithm :sha256
  @rand_size 32

  @session_validity_in_days 14
  @reset_validity_in_days 1

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exam_centre_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :exam_centre, ExamCentre

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec build_session_token(ExamCentre.t()) :: {binary(), t()}
  def build_session_token(%ExamCentre{id: id}) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %ExamCentreToken{token: token, context: "session", exam_centre_id: id}}
  end

  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Queryable.t()}
  def verify_session_token_query(token) do
    query =
      from t in ExamCentreToken,
        join: c in assoc(t, :exam_centre),
        where:
          t.token == ^token and
            t.context == "session" and
            t.inserted_at > ago(@session_validity_in_days, "day") and
            c.status == "approved",
        select: c

    {:ok, query}
  end

  @spec build_password_reset_token(ExamCentre.t()) :: {String.t(), t()}
  def build_password_reset_token(%ExamCentre{id: id, email: email}) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, raw)

    {Base.url_encode64(raw, padding: false),
     %ExamCentreToken{
       token: hashed,
       context: "reset-password",
       sent_to: email,
       exam_centre_id: id
     }}
  end

  @spec verify_password_reset_token_query(String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def verify_password_reset_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in ExamCentreToken,
            join: c in assoc(t, :exam_centre),
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

  @spec by_token_and_context_query(binary(), String.t()) :: Ecto.Queryable.t()
  def by_token_and_context_query(token, context) do
    from t in ExamCentreToken, where: t.token == ^token and t.context == ^context
  end

  @spec by_hashed_token_query(String.t(), String.t()) ::
          {:ok, Ecto.Queryable.t()} | {:error, :invalid_token}
  def by_hashed_token_query(token, "reset-password" = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        {:ok, from(t in ExamCentreToken, where: t.token == ^hashed and t.context == ^context)}

      :error ->
        {:error, :invalid_token}
    end
  end
end
