defmodule GuildfordVueWeb.ExamCentre.ExamCentreSessionController do
  @moduledoc """
  HTTP entry points for exam-centre sessions.

  Actions:
    * `:create`    — POST /examcenter/login. Dispatches to
                     `ExamCentres.authenticate/2` so pending centres can
                     be told "your registration is awaiting admin approval"
                     while suspended/wrong-credentials cases collapse into
                     the generic "Invalid email or password" message.
    * `:delete`    — DELETE /examcenter/logout.
    * `:dashboard` — placeholder protected page.
  """
  use GuildfordVueWeb, :controller

  alias GuildfordVue.Auth.OTP
  alias GuildfordVue.{AuthAuditLog, ExamCentres}
  alias GuildfordVue.ExamCentres.ExamCentreNotifier
  alias GuildfordVueWeb.Auth.PendingMfa
  alias GuildfordVueWeb.ExamCentre.ExamCentreAuth

  def create(conn, %{"exam_centre" => params}) do
    %{"email" => email, "password" => password} = params
    ip = peer_ip(conn)

    case ExamCentres.authenticate(email, password) do
      {:ok, centre} ->
        _ = AuthAuditLog.log_login_success(:exam_centre, centre.id, ip)
        maybe_mfa_or_log_in(conn, centre, params, ip)

      {:error, reason} when reason in [:pending, :invalid] ->
        # Sprint 11.5 Slice 3 — collapse :pending vs :invalid at the
        # login layer to defeat account enumeration. The underlying
        # ADT is preserved so the post-approval dashboard / admin
        # listing can still distinguish the two states.
        _ = AuthAuditLog.log_login_failure(:exam_centre, email, ip)

        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: ~p"/examcenter/login")
    end
  end

  def delete(conn, _params) do
    if centre = conn.assigns[:current_exam_centre] do
      _ = AuthAuditLog.log_logout(:exam_centre, centre.id, peer_ip(conn))
    end

    conn
    |> put_flash(:info, "You have been logged out.")
    |> ExamCentreAuth.log_out_exam_centre()
  end

  @doc "POST /examcenter/verify-otp — Slice 7."
  def verify_otp(conn, %{"verify" => %{"code" => code}}) when is_binary(code) do
    case PendingMfa.read(conn) do
      {:ok, :exam_centre, challenge_id, subject_id} ->
        do_verify(conn, challenge_id, subject_id, code)

      _ ->
        conn
        |> put_flash(:error, "Your verification session has expired. Please sign in again.")
        |> redirect(to: ~p"/examcenter/login")
    end
  end

  defp do_verify(conn, challenge_id, subject_id, code) do
    case OTP.verify(challenge_id, code) do
      :ok ->
        centre = ExamCentres.get_exam_centre!(subject_id)

        conn
        |> PendingMfa.clear()
        |> put_flash(:info, "Welcome back, #{centre.name}.")
        |> ExamCentreAuth.log_in_exam_centre(centre, %{})

      {:error, :mismatch} ->
        conn
        |> put_flash(:error, "That code didn't match. Try again.")
        |> redirect(to: ~p"/examcenter/verify-otp")

      {:error, reason} when reason in [:exhausted, :expired, :consumed, :not_found] ->
        conn
        |> PendingMfa.clear()
        |> put_flash(:error, "Verification expired. Please sign in again.")
        |> redirect(to: ~p"/examcenter/login")
    end
  end

  defp maybe_mfa_or_log_in(conn, centre, params, ip) do
    if PendingMfa.enabled?() do
      issue_and_redirect_to_mfa(conn, centre, ip)
    else
      conn
      |> put_flash(:info, "Welcome back, #{centre.name}.")
      |> ExamCentreAuth.log_in_exam_centre(centre, params)
    end
  end

  defp issue_and_redirect_to_mfa(conn, centre, ip) do
    case OTP.issue(:exam_centre, centre.id, ip: ip) do
      {:ok, challenge_id, plain_code} ->
        _ = ExamCentreNotifier.deliver_otp_email(centre, plain_code)

        conn
        |> PendingMfa.stash(:exam_centre, challenge_id, centre.id)
        |> put_flash(
          :info,
          "We've sent a 6-digit sign-in code to your email. Enter it below to finish signing in."
        )
        |> redirect(to: ~p"/examcenter/verify-otp")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not start MFA verification. Please try again.")
        |> redirect(to: ~p"/examcenter/login")
    end
  end

  defp peer_ip(%Plug.Conn{remote_ip: ip}), do: ip |> :inet.ntoa() |> to_string()
end
