defmodule GuildfordVue.ExamCentres do
  @moduledoc """
  The `ExamCentres` context — public surface for the exam-centre auth scope.
  Boundary module; pure validation lives in `ExamCentres.ExamCentre` and
  `ExamCentres.ExamCentreToken`.

  Centre lifecycle ADT:
    * `"pending"`    — newly self-registered; cannot log in.
    * `"approved"`   — admin has approved; can log in, publish slots.
    * `"suspended"`  — admin has revoked; cannot log in.

  Independent from `GuildfordVue.Candidates` and `GuildfordVue.Admins`.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.AuditLog
  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.ExamCentres.ExamCentreExam
  alias GuildfordVue.ExamCentres.ExamCentreNotifier
  alias GuildfordVue.ExamCentres.ExamCentreToken
  alias GuildfordVue.Exams.Exam
  alias GuildfordVue.Repo

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t() | atom()}

  # ---------------------------------------------------------------------------
  # Registration / lookup
  # ---------------------------------------------------------------------------

  @spec register_exam_centre(map()) :: result(ExamCentre.t())
  def register_exam_centre(attrs) do
    %ExamCentre{}
    |> ExamCentre.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns an in-memory changeset for the LiveView registration form."
  @spec change_registration(map()) :: Ecto.Changeset.t()
  def change_registration(attrs \\ %{}) do
    ExamCentre.registration_changeset(%ExamCentre{}, attrs)
  end

  @spec get_exam_centre!(binary()) :: ExamCentre.t()
  def get_exam_centre!(id), do: Repo.get!(ExamCentre, id)

  @spec get_exam_centre_by_email(String.t() | nil) :: ExamCentre.t() | nil
  def get_exam_centre_by_email(nil), do: nil

  def get_exam_centre_by_email(email) when is_binary(email) do
    Repo.get_by(ExamCentre, email: email |> String.trim() |> String.downcase())
  end

  @spec list_pending_centres() :: [ExamCentre.t()]
  def list_pending_centres do
    Repo.all(from c in ExamCentre, where: c.status == "pending", order_by: c.inserted_at)
  end

  @spec list_approved_centres() :: [ExamCentre.t()]
  def list_approved_centres do
    Repo.all(from c in ExamCentre, where: c.status == "approved", order_by: c.name)
  end

  @spec list_rejected_centres() :: [ExamCentre.t()]
  def list_rejected_centres do
    Repo.all(from c in ExamCentre, where: c.status == "rejected", order_by: [desc: c.rejected_at])
  end

  @spec count_by_status(String.t()) :: non_neg_integer()
  def count_by_status(status) when is_binary(status) do
    Repo.aggregate(from(c in ExamCentre, where: c.status == ^status), :count, :id)
  end

  @doc """
  Returns approved centres within `radius_metres` of (`lat`, `lng`),
  ordered nearest-first. Uses PostGIS `ST_DWithin` against the centre's
  `geom` column. The metres-based distance is computed via `ST_DistanceSphere`
  so radii compose naturally with the radius input (no SRID conversion
  in the caller).
  """
  @spec find_within_radius(float(), float(), pos_integer()) :: [ExamCentre.t()]
  def find_within_radius(lat, lng, radius_metres)
      when is_number(lat) and is_number(lng) and is_integer(radius_metres) and
             radius_metres > 0 do
    point = %Geo.Point{coordinates: {lng * 1.0, lat * 1.0}, srid: 4326}

    from(c in ExamCentre,
      where:
        c.status == "approved" and
          fragment(
            "ST_DWithin(?::geography, ?::geography, ?)",
            c.geom,
            ^point,
            ^radius_metres
          ),
      order_by: [
        asc:
          fragment(
            "ST_DistanceSphere(?, ?)",
            c.geom,
            ^point
          )
      ]
    )
    |> Repo.all()
  end

  @doc """
  Returns the centre matching email+password ONLY if the centre is approved.
  Pending or suspended centres are treated as non-existent at the login
  boundary (PRD §4.3 + §4.1 acceptance criteria).
  """
  @spec get_exam_centre_by_email_and_password(String.t() | nil, String.t() | nil) ::
          ExamCentre.t() | nil
  def get_exam_centre_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    centre = get_exam_centre_by_email(email)

    cond do
      is_nil(centre) ->
        ExamCentre.valid_password?(nil, password)
        nil

      centre.status != "approved" ->
        ExamCentre.valid_password?(nil, password)
        nil

      ExamCentre.valid_password?(centre, password) ->
        centre

      true ->
        nil
    end
  end

  def get_exam_centre_by_email_and_password(_, _), do: nil

  @doc """
  Authenticate a centre with explicit status awareness. Unlike
  `get_exam_centre_by_email_and_password/2` (which collapses every failure
  into nil), this returns:

    * `{:ok, centre}`         — credentials valid AND centre is approved.
    * `{:error, :pending}`    — credentials valid BUT centre is awaiting
                                 admin approval. Lets the LiveView surface
                                 a friendlier flash than "invalid email or
                                 password" so the operator knows what's
                                 happening.
    * `{:error, :invalid}`    — wrong password, missing email, OR centre
                                 is suspended. The three are merged into
                                 one error so we don't reveal which centres
                                 exist or have been suspended.

  Spends Argon2 work on every call (via `valid_password?(nil, _)` on the
  missing-email path) to defeat timing oracles.
  """
  @spec authenticate(String.t() | nil, String.t() | nil) ::
          {:ok, ExamCentre.t()} | {:error, :pending | :invalid}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    centre = get_exam_centre_by_email(email)

    cond do
      is_nil(centre) ->
        ExamCentre.valid_password?(nil, password)
        {:error, :invalid}

      not ExamCentre.valid_password?(centre, password) ->
        {:error, :invalid}

      centre.status == "approved" ->
        {:ok, centre}

      centre.status == "pending" ->
        {:error, :pending}

      # "suspended" or any unexpected status — never reveal suspended state
      true ->
        {:error, :invalid}
    end
  end

  def authenticate(_, _), do: {:error, :invalid}

  # ---------------------------------------------------------------------------
  # Approval / suspend / reactivate (admin actions; status ADT transitions)
  # ---------------------------------------------------------------------------

  @doc """
  Approves a pending centre. Idempotent in the strict sense: re-approving an
  already-approved centre returns `{:error, :already_approved}` so callers
  surface it as a no-op rather than silently re-stamping.

  Side effects (in a single transaction):
    - update centre status -> "approved"
    - append a `centre_approved` audit event
    - send the approval email (the email send is best-effort; a delivery
      failure does NOT rollback the approval — once an admin clicks
      Approve, the centre is approved, and the operator chases the email
      separately if Swoosh complains.)
  """
  @spec approve(ExamCentre.t(), GuildfordVue.Admins.Admin.t()) ::
          result(ExamCentre.t())
  def approve(%ExamCentre{} = centre, %GuildfordVue.Admins.Admin{} = admin) do
    case centre.status do
      "pending" ->
        Multi.new()
        |> Multi.update(
          :centre,
          ExamCentre.approval_changeset(centre, admin.id, DateTime.utc_now())
        )
        |> Multi.run(:audit, fn _repo, %{centre: c} ->
          AuditLog.append(:centre_approved, %{
            aggregate_id: c.id,
            actor: %{id: admin.id, type: "admin"},
            payload: %{centre_name: c.name, centre_email: c.email}
          })
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{centre: c}} ->
            _ = ExamCentreNotifier.deliver_approval_email(c)
            {:ok, c}

          {:error, _step, reason, _} ->
            {:error, reason}
        end

      "approved" ->
        {:error, :already_approved}

      "suspended" ->
        {:error, :cannot_approve_suspended}

      "rejected" ->
        {:error, :cannot_approve_rejected}
    end
  end

  @doc """
  Rejects a pending centre with a reason. Only `"pending"` → `"rejected"`
  is permitted (you can't un-approve a centre this way; use suspend
  instead). The reason is required, surfaced in the audit log, and
  included in the email sent to the centre.
  """
  @spec reject(ExamCentre.t(), GuildfordVue.Admins.Admin.t(), String.t() | nil) ::
          result(ExamCentre.t())
  def reject(%ExamCentre{}, _admin, reason)
      when not is_binary(reason) or reason == "",
      do: {:error, :reason_required}

  def reject(
        %ExamCentre{status: "pending"} = centre,
        %GuildfordVue.Admins.Admin{} = admin,
        reason
      )
      when is_binary(reason) and reason != "" do
    Multi.new()
    |> Multi.update(
      :centre,
      ExamCentre.reject_changeset(centre, admin.id, DateTime.utc_now(), reason)
    )
    |> Multi.run(:audit, fn _repo, %{centre: c} ->
      AuditLog.append(:centre_rejected, %{
        aggregate_id: c.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{
          centre_name: c.name,
          centre_email: c.email,
          rejection_reason: reason
        }
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{centre: c}} ->
        _ = ExamCentreNotifier.deliver_rejection_email(c, reason)
        {:ok, c}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  def reject(%ExamCentre{}, _admin, _reason), do: {:error, :cannot_reject_non_pending}

  @doc """
  Centre self-service profile update. Only the fields a centre
  operator may edit about themselves — see
  `ExamCentre.profile_changeset/2` for the exhaustive cast list.
  """
  @spec update_centre_profile(ExamCentre.t(), map()) :: result(ExamCentre.t())
  def update_centre_profile(%ExamCentre{} = centre, attrs) do
    centre |> ExamCentre.profile_changeset(attrs) |> Repo.update()
  end

  @doc "Form-helper changeset for the LiveView profile editor."
  @spec change_centre_profile(ExamCentre.t(), map()) :: Ecto.Changeset.t()
  def change_centre_profile(%ExamCentre{} = centre, attrs \\ %{}) do
    ExamCentre.profile_changeset(centre, attrs)
  end

  # ---------------------------------------------------------------------------
  # Exam offerings (many-to-many — Sprint 3 Slice 6)
  # ---------------------------------------------------------------------------

  @doc "Lists the (live, unarchived) exams this centre currently offers."
  @spec list_offerings(ExamCentre.t()) :: [Exam.t()]
  def list_offerings(%ExamCentre{id: centre_id}) do
    Repo.all(
      from e in Exam,
        join: ce in ExamCentreExam,
        on: ce.exam_id == e.id,
        where: ce.exam_centre_id == ^centre_id and is_nil(e.archived_at),
        order_by: e.name
    )
  end

  @doc """
  Overwrites a centre's offerings with the given exam IDs. The
  `actor` is the entity performing the change (the centre itself,
  or an admin acting on its behalf). Each add and each remove
  writes its own audit event so the log can answer "when did this
  centre start offering CCNA?" without scanning state diffs.

  Non-existent or archived exam IDs are silently dropped — the
  catalogue is the source of truth, not the form payload.
  """
  @spec set_offerings(ExamCentre.t(), [binary()], ExamCentre.t() | Admin.t()) ::
          {:ok, [Exam.t()]} | {:error, term()}
  def set_offerings(%ExamCentre{id: centre_id} = centre, exam_ids, actor)
      when is_list(exam_ids) do
    valid_ids =
      Repo.all(
        from e in Exam,
          where: e.id in ^exam_ids and is_nil(e.archived_at),
          select: e.id
      )
      |> MapSet.new()

    current_ids =
      Repo.all(
        from ce in ExamCentreExam,
          where: ce.exam_centre_id == ^centre_id,
          select: ce.exam_id
      )
      |> MapSet.new()

    to_add = MapSet.difference(valid_ids, current_ids)
    to_remove = MapSet.difference(current_ids, valid_ids)

    actor_descriptor = describe_actor(actor)

    Repo.transaction(fn ->
      # Inserts
      now = DateTime.utc_now()

      for exam_id <- to_add do
        Repo.insert!(%ExamCentreExam{
          exam_centre_id: centre_id,
          exam_id: exam_id,
          inserted_at: now
        })

        write_offering_audit(:centre_offering_added, centre, exam_id, actor_descriptor)
      end

      # Removes
      for exam_id <- to_remove do
        Repo.delete_all(
          from ce in ExamCentreExam,
            where: ce.exam_centre_id == ^centre_id and ce.exam_id == ^exam_id
        )

        write_offering_audit(:centre_offering_removed, centre, exam_id, actor_descriptor)
      end

      list_offerings(centre)
    end)
  end

  defp describe_actor(%ExamCentre{id: id}), do: %{id: id, type: "exam_centre"}
  defp describe_actor(%Admin{id: id}), do: %{id: id, type: "admin"}

  defp write_offering_audit(event_type, centre, exam_id, actor) do
    exam = Repo.get(Exam, exam_id)

    {:ok, _} =
      AuditLog.append(event_type, %{
        aggregate_id: centre.id,
        actor: actor,
        payload: %{
          centre_email: centre.email,
          exam_id: exam_id,
          exam_code: exam && exam.code,
          exam_name: exam && exam.name
        }
      })
  end

  @doc "Returns the centres currently offering a given exam (Sprint 5 prep)."
  @spec centres_offering(binary()) :: [ExamCentre.t()]
  def centres_offering(exam_id) when is_binary(exam_id) do
    Repo.all(
      from c in ExamCentre,
        join: ce in ExamCentreExam,
        on: ce.exam_centre_id == c.id,
        where: ce.exam_id == ^exam_id and c.status == "approved",
        order_by: c.name
    )
  end

  @doc "Changes a centre's password. Requires the current password."
  @spec change_password(ExamCentre.t(), String.t(), map()) ::
          result(ExamCentre.t()) | {:error, :invalid_current_password}
  def change_password(%ExamCentre{} = centre, current_password, attrs)
      when is_binary(current_password) do
    if ExamCentre.valid_password?(centre, current_password) do
      centre |> ExamCentre.password_changeset(attrs) |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  def change_password(_, _, _), do: {:error, :invalid_current_password}

  @doc """
  Suspends a centre. Without an actor (legacy 1-arg form retained for
  internal callers) the audit log is skipped — every admin-driven path
  should call `suspend/2` with the acting admin so the log records who.
  """
  @spec suspend(ExamCentre.t()) :: result(ExamCentre.t())
  def suspend(%ExamCentre{} = centre) do
    centre |> ExamCentre.suspend_changeset() |> Repo.update()
  end

  @spec suspend(ExamCentre.t(), GuildfordVue.Admins.Admin.t()) :: result(ExamCentre.t())
  def suspend(%ExamCentre{} = centre, %GuildfordVue.Admins.Admin{} = admin) do
    Multi.new()
    |> Multi.update(:centre, ExamCentre.suspend_changeset(centre))
    |> Multi.run(:audit, fn _repo, %{centre: c} ->
      AuditLog.append(:centre_suspended, %{
        aggregate_id: c.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{centre_name: c.name, centre_email: c.email}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{centre: c}} -> {:ok, c}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @spec reactivate(ExamCentre.t()) :: result(ExamCentre.t())
  def reactivate(%ExamCentre{status: "suspended"} = centre) do
    centre |> ExamCentre.reactivate_changeset() |> Repo.update()
  end

  def reactivate(_), do: {:error, :not_suspended}

  @spec reactivate(ExamCentre.t(), GuildfordVue.Admins.Admin.t()) :: result(ExamCentre.t())
  def reactivate(%ExamCentre{status: "suspended"} = centre, %GuildfordVue.Admins.Admin{} = admin) do
    Multi.new()
    |> Multi.update(:centre, ExamCentre.reactivate_changeset(centre))
    |> Multi.run(:audit, fn _repo, %{centre: c} ->
      AuditLog.append(:centre_reactivated, %{
        aggregate_id: c.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{centre_name: c.name, centre_email: c.email}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{centre: c}} -> {:ok, c}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def reactivate(_, _), do: {:error, :not_suspended}

  # ---------------------------------------------------------------------------
  # Session tokens
  # ---------------------------------------------------------------------------

  @spec generate_session_token(ExamCentre.t()) :: binary()
  def generate_session_token(%ExamCentre{} = centre) do
    {token, struct} = ExamCentreToken.build_session_token(centre)
    Repo.insert!(struct)
    token
  end

  @spec get_exam_centre_by_session_token(binary()) :: ExamCentre.t() | nil
  def get_exam_centre_by_session_token(token) when is_binary(token) do
    {:ok, query} = ExamCentreToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_exam_centre_by_session_token(_), do: nil

  @spec delete_session_token(binary()) :: :ok
  def delete_session_token(token) when is_binary(token) do
    token
    |> ExamCentreToken.by_token_and_context_query("session")
    |> Repo.delete_all()

    :ok
  end

  # ---------------------------------------------------------------------------
  # Password reset
  # ---------------------------------------------------------------------------

  @spec deliver_password_reset_instructions(ExamCentre.t(), (String.t() -> any())) ::
          {:ok, String.t()} | {:error, term()}
  def deliver_password_reset_instructions(%ExamCentre{} = centre, url_fun)
      when is_function(url_fun, 1) do
    {raw, struct} = ExamCentreToken.build_password_reset_token(centre)
    Repo.insert!(struct)

    case ExamCentreNotifier.deliver_password_reset_email(centre, url_fun.(raw)) do
      {:ok, _} -> {:ok, raw}
      other -> other
    end
  end

  @doc """
  Returns the centre matching a valid (non-consumed) reset token, or
  nil. Mirror of `GuildfordVue.Candidates.get_candidate_by_reset_token/1`.
  """
  @spec get_exam_centre_by_reset_token(String.t() | nil) :: ExamCentre.t() | nil
  def get_exam_centre_by_reset_token(token) when is_binary(token) do
    case ExamCentreToken.verify_password_reset_token_query(token) do
      {:ok, query} -> Repo.one(query)
      {:error, _} -> nil
    end
  end

  def get_exam_centre_by_reset_token(_), do: nil

  @spec reset_password(String.t(), map()) :: result(ExamCentre.t())
  def reset_password(token, attrs) when is_binary(token) do
    # Defect 001 + 004 fix:
    #   - use `password_changeset` (not `registration_changeset`) so status,
    #     name, address, approver are NOT touched
    #   - update the row BEFORE deleting the token so a failed Repo.update
    #     leaves the token usable for retry
    with {:ok, centre_query} <- ExamCentreToken.verify_password_reset_token_query(token),
         %ExamCentre{} = centre <- Repo.one(centre_query),
         changeset = ExamCentre.password_changeset(centre, attrs),
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
  # Internal
  # ---------------------------------------------------------------------------

  defp delete_token(raw_token, "reset-password" = context) do
    case ExamCentreToken.by_hashed_token_query(raw_token, context) do
      {:ok, query} ->
        {count, _} = Repo.delete_all(query)
        if count > 0, do: {:ok, count}, else: {:error, :invalid_token}

      {:error, _} = err ->
        err
    end
  end
end
