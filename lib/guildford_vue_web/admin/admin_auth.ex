defmodule GuildfordVueWeb.Admin.AdminAuth do
  @moduledoc """
  Authentication plug for the admin (back-office) scope.

  Mirrors `GuildfordVueWeb.Candidate.CandidateAuth` with the
  remember-me cookie + 30-min idle timeout (defects 001 + 003 from
  Sprint 1b, fixed Sprint 1c). Admin sessions use a shorter remember-me
  ceiling (14 days vs candidates' 30) because the blast radius of an
  admin compromise is larger.
  """
  import Plug.Conn
  use GuildfordVueWeb, :verified_routes

  alias GuildfordVue.Admins

  @session_key :admin_token
  @last_activity_key :admin_last_activity_at
  @session_issued_at_key :admin_session_issued_at
  @return_to_key :admin_return_to
  @remember_me_cookie "_guildford_vue_admin_remember_me"

  # 14 days — shorter than candidates' 30 because admin compromise is worse
  @remember_me_max_age 14 * 24 * 60 * 60

  # 30 minutes idle (PRD FR-AUTH-5)
  @idle_timeout_seconds 30 * 60

  # 12 h absolute (Sprint 11.5 Slice 3) — hard cap on session age
  # complementing the idle timeout.
  @absolute_timeout_seconds 12 * 60 * 60

  @remember_me_cookie_options [
    sign: true,
    same_site: "Lax",
    max_age: @remember_me_max_age,
    http_only: true
  ]

  def log_in_admin(conn, admin, params \\ %{}) do
    token = Admins.generate_session_token(admin)
    return_to = get_session(conn, @return_to_key)
    remember_me? = params["remember_me"] == "true"

    now = System.system_time(:second)

    conn
    |> renew_session()
    |> put_session(@session_key, token)
    |> put_session(@last_activity_key, now)
    |> put_session(@session_issued_at_key, now)
    |> put_session(:live_socket_id, "admin_sessions:#{Base.url_encode64(token)}")
    |> maybe_write_remember_me_cookie(token, remember_me?)
    |> Phoenix.Controller.redirect(to: return_to || ~p"/backoffice/dashboard")
  end

  def log_out_admin(conn) do
    token = get_session(conn, @session_key)

    if token do
      Admins.delete_session_token(token)

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

  def fetch_current_admin(conn, _opts) do
    case session_path(conn) do
      {:ok, admin, conn} ->
        assign(conn, :current_admin, admin)

      :stale_or_missing ->
        conn =
          conn
          |> delete_session(@session_key)
          |> delete_session(@last_activity_key)
          |> delete_session(@session_issued_at_key)
          |> delete_session(:live_socket_id)

        case remember_me_path(conn) do
          {:ok, admin, conn} -> assign(conn, :current_admin, admin)
          :no_remember -> assign(conn, :current_admin, nil)
        end
    end
  end

  defp session_path(conn) do
    now = System.system_time(:second)
    last_at = get_session(conn, @last_activity_key) || now
    issued_at = get_session(conn, @session_issued_at_key) || now

    with token when is_binary(token) <- get_session(conn, @session_key),
         true <- last_at + @idle_timeout_seconds > now,
         true <- issued_at + @absolute_timeout_seconds > now,
         %Admins.Admin{} = admin <- Admins.get_admin_by_session_token(token) do
      {:ok, admin, put_session(conn, @last_activity_key, now)}
    else
      _ -> :stale_or_missing
    end
  end

  defp remember_me_path(conn) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    case conn.cookies[@remember_me_cookie] do
      token when is_binary(token) ->
        case Admins.get_admin_by_session_token(token) do
          %Admins.Admin{} = admin ->
            now = System.system_time(:second)

            conn =
              conn
              |> put_session(@session_key, token)
              |> put_session(@last_activity_key, now)
              |> put_session(@session_issued_at_key, now)
              |> put_session(:live_socket_id, "admin_sessions:#{Base.url_encode64(token)}")

            {:ok, admin, conn}

          _ ->
            :no_remember
        end

      _ ->
        :no_remember
    end
  end

  @doc """
  LiveView `on_mount` hook: assigns `:current_admin` from the session.
  Used by the `:admin_unauthenticated` live_session block.
  """
  def on_mount(:assign_current_admin, _params, session, socket) do
    admin =
      case session["admin_token"] do
        token when is_binary(token) -> Admins.get_admin_by_session_token(token)
        _ -> nil
      end

    {:cont, Phoenix.Component.assign(socket, :current_admin, admin)}
  end

  def require_authenticated_admin(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn
    else
      conn
      |> maybe_stash_return_to()
      |> Phoenix.Controller.put_flash(:error, "You must log in to continue.")
      |> Phoenix.Controller.redirect(to: ~p"/backoffice/login")
      |> halt()
    end
  end

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
