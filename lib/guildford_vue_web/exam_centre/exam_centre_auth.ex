defmodule GuildfordVueWeb.ExamCentre.ExamCentreAuth do
  @moduledoc """
  Authentication plug for the exam-centre scope.

  Mirrors `GuildfordVueWeb.Candidate.CandidateAuth` and
  `GuildfordVueWeb.Admin.AdminAuth` with the remember-me cookie +
  30-min idle timeout (defects 001 + 003 from Sprint 1b, fixed
  Sprint 1c).

  Distinct from the other two scopes by the underlying `ExamCentres`
  context's authentication contract: pending and suspended centres are
  rejected at the context boundary, so a centre that gets approved and
  later suspended will have any in-flight session immediately
  invalidated on the next request.
  """
  import Plug.Conn
  use GuildfordVueWeb, :verified_routes

  alias GuildfordVue.ExamCentres

  @session_key :exam_centre_token
  @last_activity_key :exam_centre_last_activity_at
  @session_issued_at_key :exam_centre_session_issued_at
  @return_to_key :exam_centre_return_to
  @remember_me_cookie "_guildford_vue_exam_centre_remember_me"

  @remember_me_max_age 14 * 24 * 60 * 60
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

  def log_in_exam_centre(conn, centre, params \\ %{}) do
    token = ExamCentres.generate_session_token(centre)
    return_to = get_session(conn, @return_to_key)
    remember_me? = params["remember_me"] == "true"

    now = System.system_time(:second)

    conn
    |> renew_session()
    |> put_session(@session_key, token)
    |> put_session(@last_activity_key, now)
    |> put_session(@session_issued_at_key, now)
    |> put_session(:live_socket_id, "exam_centre_sessions:#{Base.url_encode64(token)}")
    |> maybe_write_remember_me_cookie(token, remember_me?)
    |> Phoenix.Controller.redirect(to: return_to || ~p"/examcenter/dashboard")
  end

  def log_out_exam_centre(conn) do
    token = get_session(conn, @session_key)

    if token do
      ExamCentres.delete_session_token(token)

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

  def fetch_current_exam_centre(conn, _opts) do
    case session_path(conn) do
      {:ok, centre, conn} ->
        assign(conn, :current_exam_centre, centre)

      :stale_or_missing ->
        conn =
          conn
          |> delete_session(@session_key)
          |> delete_session(@last_activity_key)
          |> delete_session(@session_issued_at_key)
          |> delete_session(:live_socket_id)

        case remember_me_path(conn) do
          {:ok, centre, conn} -> assign(conn, :current_exam_centre, centre)
          :no_remember -> assign(conn, :current_exam_centre, nil)
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
         %ExamCentres.ExamCentre{} = centre <-
           ExamCentres.get_exam_centre_by_session_token(token) do
      {:ok, centre, put_session(conn, @last_activity_key, now)}
    else
      _ -> :stale_or_missing
    end
  end

  defp remember_me_path(conn) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    case conn.cookies[@remember_me_cookie] do
      token when is_binary(token) ->
        case ExamCentres.get_exam_centre_by_session_token(token) do
          %ExamCentres.ExamCentre{} = centre ->
            now = System.system_time(:second)

            conn =
              conn
              |> put_session(@session_key, token)
              |> put_session(@last_activity_key, now)
              |> put_session(@session_issued_at_key, now)
              |> put_session(:live_socket_id, "exam_centre_sessions:#{Base.url_encode64(token)}")

            {:ok, centre, conn}

          _ ->
            :no_remember
        end

      _ ->
        :no_remember
    end
  end

  @doc """
  LiveView `on_mount` hook: assigns `:current_exam_centre` from the session.
  Used by the `:exam_centre_unauthenticated` live_session block.
  """
  def on_mount(:assign_current_exam_centre, _params, session, socket) do
    centre =
      case session["exam_centre_token"] do
        token when is_binary(token) ->
          ExamCentres.get_exam_centre_by_session_token(token)

        _ ->
          nil
      end

    {:cont, Phoenix.Component.assign(socket, :current_exam_centre, centre)}
  end

  def require_authenticated_exam_centre(conn, _opts) do
    if conn.assigns[:current_exam_centre] do
      conn
    else
      conn
      |> maybe_stash_return_to()
      |> Phoenix.Controller.put_flash(:error, "You must log in to continue.")
      |> Phoenix.Controller.redirect(to: ~p"/examcenter/login")
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
