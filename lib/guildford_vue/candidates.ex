defmodule GuildfordVue.Candidates do
  @moduledoc """
  The `Candidates` context — public surface for the candidate auth scope.

  Boundary module per `CLAUDE.md` §"Architectural conventions" — every
  side-effectful operation (DB read/write, hash check, email dispatch) lives
  here. The pure validation logic lives in `Candidates.Candidate` /
  `Candidates.CandidateToken`.

  Companion auth scopes:
    * `GuildfordVue.Admins`
    * `GuildfordVue.ExamCentres`

  Each is independent — no shared session, no shared token, no shared `Scope`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GuildfordVue.AuditLog
  alias GuildfordVue.Candidates.Candidate
  alias GuildfordVue.Candidates.CandidateNotifier
  alias GuildfordVue.Candidates.CandidateToken
  alias GuildfordVue.Repo

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t() | atom()}

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------

  @doc "Registers a candidate. Returns `{:ok, candidate}` or `{:error, changeset}`."
  @spec register_candidate(map()) :: result(Candidate.t())
  def register_candidate(attrs) do
    %Candidate{}
    |> Candidate.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Reset an in-memory changeset for the registration form (LiveView helper)."
  @spec change_registration(map()) :: Ecto.Changeset.t()
  def change_registration(attrs \\ %{}) do
    Candidate.registration_changeset(%Candidate{}, attrs)
  end

  # ---------------------------------------------------------------------------
  # Lookup
  # ---------------------------------------------------------------------------

  @spec get_candidate!(binary()) :: Candidate.t()
  def get_candidate!(id), do: Repo.get!(Candidate, id)

  @spec get_candidate_by_email(String.t() | nil) :: Candidate.t() | nil
  def get_candidate_by_email(nil), do: nil

  def get_candidate_by_email(email) when is_binary(email) do
    Repo.get_by(Candidate, email: normalise(email))
  end

  @doc """
  Returns the candidate matching `email` and `password`, or `nil`. The
  function always spends time hashing whether or not the email matches, to
  prevent timing oracles. Suspended candidates are treated as non-existent.
  """
  @spec get_candidate_by_email_and_password(String.t() | nil, String.t() | nil) ::
          Candidate.t() | nil
  def get_candidate_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    candidate = get_candidate_by_email(email)

    cond do
      is_nil(candidate) ->
        Candidate.valid_password?(nil, password)
        nil

      candidate.suspended_at != nil ->
        Candidate.valid_password?(nil, password)
        nil

      Candidate.valid_password?(candidate, password) ->
        candidate

      true ->
        nil
    end
  end

  def get_candidate_by_email_and_password(_, _), do: nil

  @doc """
  Sprint 11.5 Slice 3 — login-time wrapper that adds an
  `email_verified_at` enforcement on top of
  `get_candidate_by_email_and_password/2`.

  Returns:
    * `{:ok, candidate}` — verified candidate + correct password
    * `{:error, :email_not_verified}` — correct password but
      email not yet verified
    * `{:error, :invalid_credentials}` — anything else
      (wrong password, unknown email, suspended candidate,
      nil/non-binary input) — collapsed so the caller can never
      enumerate which case it is.
  """
  @spec authenticate_candidate(String.t() | nil, String.t() | nil) ::
          {:ok, Candidate.t()}
          | {:error, :email_not_verified | :invalid_credentials}
  def authenticate_candidate(email, password) do
    case get_candidate_by_email_and_password(email, password) do
      %Candidate{email_verified_at: nil} -> {:error, :email_not_verified}
      %Candidate{} = candidate -> {:ok, candidate}
      nil -> {:error, :invalid_credentials}
    end
  end

  # ---------------------------------------------------------------------------
  # Session tokens
  # ---------------------------------------------------------------------------

  @spec generate_session_token(Candidate.t()) :: binary()
  def generate_session_token(%Candidate{} = candidate) do
    {token, struct} = CandidateToken.build_session_token(candidate)
    Repo.insert!(struct)
    token
  end

  @spec get_candidate_by_session_token(binary()) :: Candidate.t() | nil
  def get_candidate_by_session_token(token) when is_binary(token) do
    {:ok, query} = CandidateToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_candidate_by_session_token(_), do: nil

  @spec delete_session_token(binary()) :: :ok
  def delete_session_token(token) when is_binary(token) do
    token
    |> CandidateToken.by_token_and_context_query("session")
    |> Repo.delete_all()

    :ok
  end

  # ---------------------------------------------------------------------------
  # Email verification
  # ---------------------------------------------------------------------------

  @doc """
  Generates an email-verification token, calls `url_fun.(token)` to render the
  email body (the caller decides what URL the token is embedded in), and
  delivers the message via `CandidateNotifier`. Returns `{:ok, token}` on
  success — the raw token is also returned for testing convenience.
  """
  @spec deliver_email_verification_instructions(Candidate.t(), (String.t() -> any())) ::
          {:ok, String.t()} | {:error, term()}
  def deliver_email_verification_instructions(%Candidate{} = candidate, url_fun)
      when is_function(url_fun, 1) do
    {raw, struct} = CandidateToken.build_email_verification_token(candidate)
    Repo.insert!(struct)

    case CandidateNotifier.deliver_verification_email(candidate, url_fun.(raw)) do
      {:ok, _} -> {:ok, raw}
      other -> other
    end
  end

  @doc """
  Verifies an email using a URL-safe token. Marks the candidate verified and
  destroys the token (single-use). Returns `{:ok, candidate}` or
  `{:error, :invalid_token}`.
  """
  @spec verify_email(String.t()) :: result(Candidate.t())
  def verify_email(token) when is_binary(token) do
    with {:ok, candidate_query} <- CandidateToken.verify_email_token_query(token),
         %Candidate{} = candidate <- Repo.one(candidate_query),
         {:ok, _} <- delete_token(token, "verify-email") do
      candidate
      |> Candidate.confirm_email_changeset(DateTime.utc_now())
      |> Repo.update()
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify_email(_), do: {:error, :invalid_token}

  # ---------------------------------------------------------------------------
  # Password reset
  # ---------------------------------------------------------------------------

  @spec deliver_password_reset_instructions(Candidate.t(), (String.t() -> any())) ::
          {:ok, String.t()} | {:error, term()}
  def deliver_password_reset_instructions(%Candidate{} = candidate, url_fun)
      when is_function(url_fun, 1) do
    {raw, struct} = CandidateToken.build_password_reset_token(candidate)
    Repo.insert!(struct)

    case CandidateNotifier.deliver_password_reset_email(candidate, url_fun.(raw)) do
      {:ok, _} -> {:ok, raw}
      other -> other
    end
  end

  @doc """
  Returns the candidate matching a valid (non-consumed) password-reset
  token, or nil. The token row is NOT deleted — use `reset_password/2`
  to consume the token and rotate the password atomically.

  Useful for the GET handler of /candidate/reset-password/:token which
  must validate the token without consuming it (otherwise the user's
  subsequent POST would always fail).
  """
  @spec get_candidate_by_reset_token(String.t() | nil) :: Candidate.t() | nil
  def get_candidate_by_reset_token(token) when is_binary(token) do
    case CandidateToken.verify_password_reset_token_query(token) do
      {:ok, query} -> Repo.one(query)
      {:error, _} -> nil
    end
  end

  def get_candidate_by_reset_token(_), do: nil

  @spec reset_password(String.t(), map()) :: result(Candidate.t())
  def reset_password(token, attrs) when is_binary(token) do
    # Defect 004 fix: update before deleting the token so a failed Repo.update
    # leaves the token usable for retry.
    with {:ok, candidate_query} <- CandidateToken.verify_password_reset_token_query(token),
         %Candidate{} = candidate <- Repo.one(candidate_query),
         changeset = Candidate.password_changeset(candidate, attrs),
         true <- changeset.valid? || {:cs, changeset},
         {:ok, updated} <- Repo.update(changeset),
         {:ok, _} <- delete_token(token, "reset-password") do
      {:ok, updated}
    else
      {:cs, cs} -> {:error, cs}
      _ -> {:error, :invalid_token}
    end
  end

  def reset_password(_, _), do: {:error, :invalid_token}

  # ---------------------------------------------------------------------------
  # Suspend / reactivate
  # ---------------------------------------------------------------------------

  @doc """
  Updates a candidate's profile fields (first_name, last_name, phone,
  postcode). Password and email cannot be changed via this path —
  password uses change_password/3; email change requires re-verification
  (out of scope for Sprint 1c).
  """
  @spec update_profile(Candidate.t(), map()) :: result(Candidate.t())
  def update_profile(%Candidate{} = candidate, attrs) do
    candidate
    |> Ecto.Changeset.cast(attrs, [:first_name, :last_name, :phone, :postcode])
    |> Ecto.Changeset.validate_required([:first_name, :last_name])
    |> Ecto.Changeset.validate_length(:first_name, max: 80)
    |> Ecto.Changeset.validate_length(:last_name, max: 80)
    |> Ecto.Changeset.validate_length(:phone, max: 32)
    |> Ecto.Changeset.validate_length(:postcode, max: 16)
    |> Repo.update()
  end

  @doc "Returns a changeset for the LiveView settings form (profile)."
  @spec change_profile(Candidate.t(), map()) :: Ecto.Changeset.t()
  def change_profile(%Candidate{} = candidate, attrs \\ %{}) do
    candidate
    |> Ecto.Changeset.cast(attrs, [:first_name, :last_name, :phone, :postcode])
    |> Ecto.Changeset.validate_required([:first_name, :last_name])
  end

  @doc """
  Changes a candidate's password. Requires the current password as proof
  of knowledge — a stolen session alone cannot rotate the password.
  Returns {:error, :invalid_current_password} if the supplied current
  password doesn't match.
  """
  @spec change_password(Candidate.t(), String.t(), map()) :: result(Candidate.t())
  def change_password(%Candidate{} = candidate, current_password, attrs)
      when is_binary(current_password) do
    if Candidate.valid_password?(candidate, current_password) do
      candidate
      |> Candidate.password_changeset(attrs)
      |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  def change_password(_, _, _), do: {:error, :invalid_current_password}

  @spec suspend(Candidate.t()) :: result(Candidate.t())
  def suspend(%Candidate{} = candidate) do
    candidate
    |> Candidate.suspend_changeset(DateTime.utc_now())
    |> Repo.update()
  end

  @spec suspend(Candidate.t(), GuildfordVue.Admins.Admin.t()) :: result(Candidate.t())
  def suspend(%Candidate{} = candidate, %GuildfordVue.Admins.Admin{} = admin) do
    Multi.new()
    |> Multi.update(:candidate, Candidate.suspend_changeset(candidate, DateTime.utc_now()))
    |> Multi.run(:audit, fn _repo, %{candidate: c} ->
      AuditLog.append(:candidate_suspended, %{
        aggregate_id: c.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{candidate_email: c.email}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{candidate: c}} -> {:ok, c}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @spec reactivate(Candidate.t()) :: result(Candidate.t())
  def reactivate(%Candidate{} = candidate) do
    candidate
    |> Candidate.reactivate_changeset()
    |> Repo.update()
  end

  @spec reactivate(Candidate.t(), GuildfordVue.Admins.Admin.t()) :: result(Candidate.t())
  def reactivate(%Candidate{} = candidate, %GuildfordVue.Admins.Admin{} = admin) do
    Multi.new()
    |> Multi.update(:candidate, Candidate.reactivate_changeset(candidate))
    |> Multi.run(:audit, fn _repo, %{candidate: c} ->
      AuditLog.append(:candidate_reactivated, %{
        aggregate_id: c.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{candidate_email: c.email}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{candidate: c}} -> {:ok, c}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Admin-facing candidate search/listing.

  Options:
    * `:search` — case-insensitive ILIKE against email, first_name, last_name
    * `:status` — `:active` (suspended_at IS NULL) | `:suspended` | `:all`
    * `:limit`  — default 50
  """
  @spec list_candidates(keyword()) :: [Candidate.t()]
  def list_candidates(opts \\ []) do
    search = Keyword.get(opts, :search)
    status = Keyword.get(opts, :status, :all)
    limit = Keyword.get(opts, :limit, 50)

    Candidate
    |> maybe_search(search)
    |> filter_status(status)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"

    from c in query,
      where:
        ilike(c.email, ^pattern) or ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern)
  end

  defp filter_status(query, :all), do: query
  defp filter_status(query, :active), do: from(c in query, where: is_nil(c.suspended_at))
  defp filter_status(query, :suspended), do: from(c in query, where: not is_nil(c.suspended_at))

  @spec count_all() :: non_neg_integer()
  def count_all, do: Repo.aggregate(Candidate, :count, :id)

  @spec count_active() :: non_neg_integer()
  def count_active do
    Repo.aggregate(from(c in Candidate, where: is_nil(c.suspended_at)), :count, :id)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp delete_token(raw_token, context) when context in ~w(verify-email reset-password) do
    case CandidateToken.by_hashed_token_query(raw_token, context) do
      {:ok, query} ->
        {count, _} = Repo.delete_all(query)
        if count > 0, do: {:ok, count}, else: {:error, :invalid_token}

      {:error, _} = err ->
        err
    end
  end

  defp normalise(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
end
