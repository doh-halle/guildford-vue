defmodule GuildfordVue.Admins do
  @moduledoc """
  The `Admins` context — public surface for the platform-administrator auth
  scope. Boundary module; pure validation lives in `Admins.Admin` and
  `Admins.AdminToken`.

  Independent from `GuildfordVue.Candidates` and `GuildfordVue.ExamCentres` —
  no shared session, no shared token table, no shared `Scope` module.

  Admins are created either by other admins (via `register_admin/1` called
  inside an authorised LiveView) or by the seed mix task
  `Mix.Tasks.GuildfordVue.Seed.Admins`. There is no self-service registration.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.Admins.AdminNotifier
  alias GuildfordVue.Admins.AdminToken
  alias GuildfordVue.AuditLog
  alias GuildfordVue.Repo

  @roles ~w(operator superadmin)

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t() | atom()}

  # ---------------------------------------------------------------------------
  # Registration / listing
  # ---------------------------------------------------------------------------

  @spec register_admin(map()) :: result(Admin.t())
  def register_admin(attrs) do
    %Admin{}
    |> Admin.registration_changeset(attrs)
    |> Repo.insert()
  end

  @spec list_admins() :: [Admin.t()]
  def list_admins, do: Repo.all(from a in Admin, order_by: a.inserted_at)

  @spec get_admin!(binary()) :: Admin.t()
  def get_admin!(id), do: Repo.get!(Admin, id)

  @spec get_admin_by_email(String.t() | nil) :: Admin.t() | nil
  def get_admin_by_email(nil), do: nil

  def get_admin_by_email(email) when is_binary(email) do
    Repo.get_by(Admin, email: email |> String.trim() |> String.downcase())
  end

  @spec get_admin_by_email_and_password(String.t() | nil, String.t() | nil) :: Admin.t() | nil
  def get_admin_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    admin = get_admin_by_email(email)

    cond do
      is_nil(admin) ->
        Admin.valid_password?(nil, password)
        nil

      admin.suspended_at != nil ->
        Admin.valid_password?(nil, password)
        nil

      Admin.valid_password?(admin, password) ->
        admin

      true ->
        nil
    end
  end

  def get_admin_by_email_and_password(_, _), do: nil

  # ---------------------------------------------------------------------------
  # Session tokens
  # ---------------------------------------------------------------------------

  @spec generate_session_token(Admin.t()) :: binary()
  def generate_session_token(%Admin{} = admin) do
    {token, struct} = AdminToken.build_session_token(admin)
    Repo.insert!(struct)
    token
  end

  @spec get_admin_by_session_token(binary()) :: Admin.t() | nil
  def get_admin_by_session_token(token) when is_binary(token) do
    {:ok, query} = AdminToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_admin_by_session_token(_), do: nil

  @spec delete_session_token(binary()) :: :ok
  def delete_session_token(token) when is_binary(token) do
    token
    |> AdminToken.by_token_and_context_query("session")
    |> Repo.delete_all()

    :ok
  end

  # ---------------------------------------------------------------------------
  # Password reset
  # ---------------------------------------------------------------------------

  @spec deliver_password_reset_instructions(Admin.t(), (String.t() -> any())) ::
          {:ok, String.t()} | {:error, term()}
  def deliver_password_reset_instructions(%Admin{} = admin, url_fun)
      when is_function(url_fun, 1) do
    {raw, struct} = AdminToken.build_password_reset_token(admin)
    Repo.insert!(struct)

    case AdminNotifier.deliver_password_reset_email(admin, url_fun.(raw)) do
      {:ok, _} -> {:ok, raw}
      other -> other
    end
  end

  @doc """
  Returns the admin matching a valid (non-consumed) reset token, or nil.
  Mirror of `GuildfordVue.Candidates.get_candidate_by_reset_token/1` —
  used by the reset-password LiveView's GET handler to validate without
  consuming.
  """
  @spec get_admin_by_reset_token(String.t() | nil) :: Admin.t() | nil
  def get_admin_by_reset_token(token) when is_binary(token) do
    case AdminToken.verify_password_reset_token_query(token) do
      {:ok, query} -> Repo.one(query)
      {:error, _} -> nil
    end
  end

  def get_admin_by_reset_token(_), do: nil

  @spec reset_password(String.t(), map()) :: result(Admin.t())
  def reset_password(token, attrs) when is_binary(token) do
    # Defect 004 fix: update before deleting the token so a failed Repo.update
    # leaves the token usable for retry.
    with {:ok, admin_query} <- AdminToken.verify_password_reset_token_query(token),
         %Admin{} = admin <- Repo.one(admin_query),
         changeset = Admin.password_changeset(admin, attrs),
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

  @doc "Changes an admin's password. Requires the current password."
  @spec change_password(Admin.t(), String.t(), map()) ::
          result(Admin.t()) | {:error, :invalid_current_password}
  def change_password(%Admin{} = admin, current_password, attrs)
      when is_binary(current_password) do
    if Admin.valid_password?(admin, current_password) do
      admin |> Admin.password_changeset(attrs) |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  def change_password(_, _, _), do: {:error, :invalid_current_password}

  @spec suspend(Admin.t()) :: result(Admin.t())
  def suspend(%Admin{} = admin) do
    admin |> Admin.suspend_changeset(DateTime.utc_now()) |> Repo.update()
  end

  @spec suspend(Admin.t(), Admin.t()) :: result(Admin.t())
  def suspend(%Admin{} = admin, %Admin{} = actor) do
    Multi.new()
    |> Multi.update(:admin, Admin.suspend_changeset(admin, DateTime.utc_now()))
    |> Multi.run(:audit, fn _repo, %{admin: a} ->
      AuditLog.append(:admin_suspended, %{
        aggregate_id: a.id,
        actor: %{id: actor.id, type: "admin"},
        payload: %{admin_email: a.email}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{admin: a}} -> {:ok, a}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @spec reactivate(Admin.t()) :: result(Admin.t())
  def reactivate(%Admin{} = admin) do
    admin |> Admin.reactivate_changeset() |> Repo.update()
  end

  @spec reactivate(Admin.t(), Admin.t()) :: result(Admin.t())
  def reactivate(%Admin{} = admin, %Admin{} = actor) do
    Multi.new()
    |> Multi.update(:admin, Admin.reactivate_changeset(admin))
    |> Multi.run(:audit, fn _repo, %{admin: a} ->
      AuditLog.append(:admin_reactivated, %{
        aggregate_id: a.id,
        actor: %{id: actor.id, type: "admin"},
        payload: %{admin_email: a.email}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{admin: a}} -> {:ok, a}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Invite + role assignment (superadmin actions)
  # ---------------------------------------------------------------------------

  @doc """
  Invites a new admin. Creates the row with a random placeholder
  password (never communicated), generates a password-reset token, and
  emails the invitee a link to set their real password. Returns
  `{:ok, admin, raw_reset_token}` so callers can surface the link in
  development or tests without round-tripping through the mailbox.

  The acting `inviter` is recorded as the actor on the `admin_invited`
  audit event.
  """
  @spec invite_admin(map(), Admin.t()) ::
          {:ok, Admin.t(), String.t()} | result(Admin.t())
  def invite_admin(attrs, %Admin{} = inviter) when is_map(attrs) do
    placeholder = "PH-" <> (:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))

    attrs = Map.put(attrs, "password", placeholder)

    Multi.new()
    |> Multi.insert(:admin, Admin.registration_changeset(%Admin{}, attrs))
    |> Multi.run(:reset_token, fn _repo, %{admin: a} ->
      {raw, struct} = AdminToken.build_password_reset_token(a)
      {:ok, _} = Repo.insert(struct)
      {:ok, raw}
    end)
    |> Multi.run(:audit, fn _repo, %{admin: a} ->
      AuditLog.append(:admin_invited, %{
        aggregate_id: a.id,
        actor: %{id: inviter.id, type: "admin"},
        payload: %{invited_email: a.email, invited_role: a.role}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{admin: a, reset_token: raw}} ->
        _ = AdminNotifier.deliver_invitation_email(a, invite_url(raw))
        {:ok, a, raw}

      {:error, :admin, %Ecto.Changeset{} = cs, _} ->
        {:error, cs}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp invite_url(raw_token) do
    GuildfordVueWeb.Endpoint.url() <> "/backoffice/reset-password/" <> raw_token
  end

  @doc """
  Changes an admin's role. The actor must be a superadmin — but that
  policy is enforced at the LiveView boundary; the context only checks
  the role is valid and audits the transition. Returns
  `{:error, :invalid_role}` for unknown roles.
  """
  @spec change_role(Admin.t(), String.t(), Admin.t()) :: result(Admin.t())
  def change_role(_admin, new_role, _actor) when new_role not in @roles,
    do: {:error, :invalid_role}

  def change_role(%Admin{role: same} = admin, same, _actor), do: {:ok, admin}

  def change_role(%Admin{} = admin, new_role, %Admin{} = actor) do
    old_role = admin.role

    Multi.new()
    |> Multi.update(:admin, Ecto.Changeset.change(admin, role: new_role))
    |> Multi.run(:audit, fn _repo, %{admin: a} ->
      AuditLog.append(:admin_role_changed, %{
        aggregate_id: a.id,
        actor: %{id: actor.id, type: "admin"},
        payload: %{admin_email: a.email, from: old_role, to: new_role}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{admin: a}} -> {:ok, a}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp delete_token(raw_token, "reset-password" = context) do
    case AdminToken.by_hashed_token_query(raw_token, context) do
      {:ok, query} ->
        {count, _} = Repo.delete_all(query)
        if count > 0, do: {:ok, count}, else: {:error, :invalid_token}

      {:error, _} = err ->
        err
    end
  end
end
