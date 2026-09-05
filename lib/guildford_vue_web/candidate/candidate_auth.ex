defmodule GuildfordVueWeb.Candidate.CandidateAuth do
  @moduledoc """
  Authentication plug for the candidate scope.

  Public plug functions:

    * `fetch_current_candidate/2` — assigns `:current_candidate` based on the
      session cookie. Enforces the 30-minute idle timeout (PRD §4.1
      FR-AUTH-5) and falls back to the signed remember-me cookie when the
      session is missing or stale.
    * `require_authenticated_candidate/2` — halts with a redirect to
      `/candidate/login` if no candidate is logged in.
    * `log_in_candidate/3` — issues a session token, stores it under the
      `:candidate_token` session key, sets `:candidate_last_activity_at`,
      and (if `params["remember_me"] == "true"`) writes the signed
      remember-me cookie with a 30-day max_age.
    * `log_out_candidate/1` — deletes the session-token DB row, clears the
      `:candidate_token` session key, and clears the remember-me cookie.

  ## Idle timeout & remember-me (defects 001 + 003 fix)

  PRD §4.1 FR-AUTH-5: *"Sessions expire after 30 minutes of inactivity;
  'Remember me' extends to 30 days."*

  Mechanics:

    * Every authenticated request refreshes `:candidate_last_activity_at`.
    * On each `fetch_current_candidate/2`, if the timestamp is older than
      30 minutes, the session is treated as not authenticated.
    * If `:remember_me` was set at login, a signed cookie carries the same
      session token for 30 days. When the session expires (idle or browser
      close), `fetch_current_candidate/2` reads the cookie, restores the
      session, and the user stays logged in.
    * `log_out_candidate/1` clears both the session and the cookie.

  ## Isolation properties (PRD §4.1)

    * Reads/writes ONLY the `:candidate_token`,
      `:candidate_last_activity_at`, and `:candidate_return_to` session
      keys + the `_guildford_vue_candidate_remember_me` cookie — never
      touches admin or exam-centre keys/cookies.
    * Assigns ONLY `:current_candidate`.
  """
  import Plug.Conn
  use GuildfordVueWeb, :verified_routes

  alias GuildfordVue.Candidates

  @session_key :candidate_token
  @last_activity_key :candidate_last_activity_at
  @session_issued_at_key :candidate_session_issued_at
  @return_to_key :candidate_return_to
  @remember_me_cookie "_guildford_vue_candidate_remember_me"

  # 30 days (PRD FR-AUTH-5)
  @remember_me_max_age 30 * 24 * 60 * 60

  # 30 minutes idle (PRD FR-AUTH-5)
  @idle_timeout_seconds 30 * 60

  # 12 h absolute (Sprint 11.5 Slice 3) — hard cap on session age
  # complementing the idle timeout. A live session must re-authenticate
  # at 12 h regardless of activity. Defends against long-lived
  # stolen cookies / forgotten public terminals.
  @absolute_timeout_seconds 12 * 60 * 60

  @remember_me_cookie_options [
    sign: true,
    same_site: "Lax",
    max_age: @remember_me_max_age,
    http_only: true
  ]

  # ---------------------------------------------------------------------------
  # Login
  # ---------------------------------------------------------------------------

  @doc """
  Logs the candidate in. Renews the session id (defence against
  session-fixation), stores a freshly-issued token, stamps
  `:candidate_last_activity_at`, and — if `params["remember_me"] == "true"`
  — writes the signed remember-me cookie. Redirects to either the stashed
  return_to or `/candidate/dashboard`.
  """
  def log_in_candidate(conn, candidate, params \\ %{}) do
    token = Candidates.generate_session_token(candidate)
    return_to = get_session(conn, @return_to_key)
    remember_me? = params["remember_me"] == "true"

    now = System.system_time(:second)

    conn
    |> renew_session()
    |> put_session(@session_key, token)
    |> put_session(@last_activity_key, now)
    |> put_session(@session_issued_at_key, now)
    |> put_session(:live_socket_id, "candidate_sessions:#{Base.url_encode64(token)}")
    |> maybe_write_remember_me_cookie(token, remember_me?)
    |> Phoenix.Controller.redirect(to: return_to || ~p"/candidate/dashboard")
  end

  # ---------------------------------------------------------------------------
  # Logout
  # ---------------------------------------------------------------------------

  @doc """
  Logs the candidate out: deletes the DB session-token row, clears the
  `:candidate_token` session key, removes the remember-me cookie, broadcasts
  a LiveView disconnect, and redirects to /.
  """
  def log_out_candidate(conn) do
    token = get_session(conn, @session_key)

    if token do
      Candidates.delete_session_token(token)

      if live_socket_id = get_session(conn, :live_socket_id) do
        GuildfordVueWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
      end
    end

    conn
    |> delete_session(@session_key)
    |> delete_session(@last_activity_key)
    |> delete_session(@session_issued_at_key)
    |> delete_session(:live_socket_id)
    |> delete_session(@return_to_key)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_cookie_options)
    |> Phoenix.Controller.redirect(to: ~p"/")
  end

  # ---------------------------------------------------------------------------
  # fetch_current_candidate plug
  # ---------------------------------------------------------------------------

  @doc """
  Plug. Assigns `:current_candidate` to the candidate matching the session
  token (or `nil`). Enforces the 30-minute idle timeout and falls back to
  the remember-me cookie when needed. Never touches admin or exam-centre
  assigns.
  """
  def fetch_current_candidate(conn, _opts) do
    case session_path(conn) do
      {:ok, candidate, conn} ->
        assign(conn, :current_candidate, candidate)

      :stale_or_missing ->
        # Clear any lingering stale session keys before trying the
        # remember-me fallback. This satisfies the test invariant that
        # "after idle timeout, the session no longer carries the token"
        # (defect 003).
        conn =
          conn
          |> delete_session(@session_key)
          |> delete_session(@last_activity_key)
          |> delete_session(@session_issued_at_key)
          |> delete_session(:live_socket_id)

        case remember_me_path(conn) do
          {:ok, candidate, conn} -> assign(conn, :current_candidate, candidate)
          :no_remember -> assign(conn, :current_candidate, nil)
        end
    end
  end

  defp session_path(conn) do
    now = System.system_time(:second)
    # If the timestamp keys are missing entirely, treat the session as
    # fresh (we'll stamp them below). This covers the case where the
    # session cookie carries a token from a build that predates
    # idle/absolute-timeout tracking.
    last_at = get_session(conn, @last_activity_key) || now
    issued_at = get_session(conn, @session_issued_at_key) || now

    with token when is_binary(token) <- get_session(conn, @session_key),
         true <- last_at + @idle_timeout_seconds > now,
         true <- issued_at + @absolute_timeout_seconds > now,
         %Candidates.Candidate{} = candidate <- Candidates.get_candidate_by_session_token(token) do
      {:ok, candidate, put_session(conn, @last_activity_key, now)}
    else
      _ -> :stale_or_missing
    end
  end

  defp remember_me_path(conn) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    case conn.cookies[@remember_me_cookie] do
      token when is_binary(token) ->
        case Candidates.get_candidate_by_session_token(token) do
          %Candidates.Candidate{} = candidate ->
            now = System.system_time(:second)

            conn =
              conn
              |> put_session(@session_key, token)
              |> put_session(@last_activity_key, now)
              |> put_session(@session_issued_at_key, now)
              |> put_session(:live_socket_id, "candidate_sessions:#{Base.url_encode64(token)}")

            {:ok, candidate, conn}

          _ ->
            :no_remember
        end

      _ ->
        :no_remember
    end
  end

  # ---------------------------------------------------------------------------
  # require_authenticated_candidate plug
  # ---------------------------------------------------------------------------

  @doc """
  Plug. Halts with redirect to /candidate/login if `:current_candidate` is
  nil. Stashes the requested path in `:candidate_return_to` so the candidate
  is bounced back after logging in.
  """
  def require_authenticated_candidate(conn, _opts) do
    if conn.assigns[:current_candidate] do
      conn
    else
      conn
      |> maybe_stash_return_to()
      |> Phoenix.Controller.put_flash(:error, "You must log in to continue.")
      |> Phoenix.Controller.redirect(to: ~p"/candidate/login")
      |> halt()
    end
  end

  # ---------------------------------------------------------------------------
  # LiveView on_mount
  # ---------------------------------------------------------------------------

  @doc """
  LiveView `on_mount` hook: assigns `:current_candidate` from the session.
  Used by `live_session` blocks so a LiveView can know whether the visitor
  is already a logged-in candidate.
  """
  def on_mount(:assign_current_candidate, _params, session, socket) do
    candidate =
      case session["candidate_token"] do
        token when is_binary(token) -> Candidates.get_candidate_by_session_token(token)
        _ -> nil
      end

    {:cont, Phoenix.Component.assign(socket, :current_candidate, candidate)}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> delete_session(@session_key)
    |> delete_session(@last_activity_key)
    |> delete_session(@session_issued_at_key)
    |> delete_session(@return_to_key)
    |> delete_session(:live_socket_id)
  end

  defp maybe_write_remember_me_cookie(conn, token, true) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_cookie_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, false), do: conn

  defp maybe_stash_return_to(%{method: "GET"} = conn) do
    put_session(conn, @return_to_key, current_path(conn))
  end

  defp maybe_stash_return_to(conn), do: conn

  defp current_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end
end
