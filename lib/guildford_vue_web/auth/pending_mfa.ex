defmodule GuildfordVueWeb.Auth.PendingMfa do
  @moduledoc """
  Session-side stash for an in-flight MFA challenge (Sprint 11.5
  Slice 7). Bridges the gap between the session controller's
  `:create` action (which validates the password + issues the
  OTP) and the verify-OTP form (which the user completes after
  reading the emailed code).

  ## Session keys

  Three keys, all short-lived (cleared on every login attempt
  outcome — success, exhausted, or restart):

    * `:pending_mfa_scope`         → `"candidate" | "admin" | "exam_centre"`
    * `:pending_mfa_challenge_id`  → UUID of the issued challenge
    * `:pending_mfa_subject_id`    → UUID of the candidate / admin /
                                     centre being authenticated
  """
  import Plug.Conn

  @scope_key :pending_mfa_scope
  @challenge_key :pending_mfa_challenge_id
  @subject_key :pending_mfa_subject_id

  @type scope :: :candidate | :admin | :exam_centre

  @spec stash(Plug.Conn.t(), scope(), binary(), binary()) :: Plug.Conn.t()
  def stash(conn, scope, challenge_id, subject_id)
      when scope in [:candidate, :admin, :exam_centre] and is_binary(challenge_id) and
             is_binary(subject_id) do
    conn
    |> put_session(@scope_key, Atom.to_string(scope))
    |> put_session(@challenge_key, challenge_id)
    |> put_session(@subject_key, subject_id)
  end

  @spec read(Plug.Conn.t() | map()) ::
          {:ok, scope(), binary(), binary()} | :none
  def read(%Plug.Conn{} = conn) do
    do_read(
      get_session(conn, @scope_key),
      get_session(conn, @challenge_key),
      get_session(conn, @subject_key)
    )
  end

  def read(session) when is_map(session) do
    do_read(
      session[Atom.to_string(@scope_key)],
      session[Atom.to_string(@challenge_key)],
      session[Atom.to_string(@subject_key)]
    )
  end

  defp do_read(scope_str, challenge_id, subject_id)
       when is_binary(scope_str) and is_binary(challenge_id) and is_binary(subject_id) do
    {:ok, String.to_existing_atom(scope_str), challenge_id, subject_id}
  end

  defp do_read(_, _, _), do: :none

  @spec clear(Plug.Conn.t()) :: Plug.Conn.t()
  def clear(conn) do
    conn
    |> delete_session(@scope_key)
    |> delete_session(@challenge_key)
    |> delete_session(@subject_key)
  end

  @doc """
  Reads `:mfa_via_email_enabled` from the application env (default
  false). Slice 8 adds the admin toggle that flips this at runtime.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:guildford_vue, :mfa_via_email_enabled, false)
  end
end
