defmodule GuildfordVueWeb.Admin.AdminSessionController do
  @moduledoc """
  HTTP entry points for admin sessions.

  Actions:
    * `:create`    — POST /backoffice/login. Authenticates via
                     `Admins.get_admin_by_email_and_password/2` and calls
                     `AdminAuth.log_in_admin/3`. Rate-limited by the
                     `:backoffice_login_post` pipeline.
    * `:delete`    — DELETE /backoffice/logout.
    * `:dashboard` — placeholder protected page (Sprint 2 replaces with
                     the admin dashboard LiveView).
  """
  use GuildfordVueWeb, :controller

  alias GuildfordVue.{Admins, AuthAuditLog}
  alias GuildfordVue.Admins.AdminNotifier
  alias GuildfordVue.Auth.OTP
  alias GuildfordVueWeb.Admin.AdminAuth
  alias GuildfordVueWeb.Auth.PendingMfa

  def create(conn, %{"admin" => params}) do
    %{"email" => email, "password" => password} = params
    ip = peer_ip(conn)

    case Admins.get_admin_by_email_and_password(email, password) do
      nil ->
        _ = AuthAuditLog.log_login_failure(:admin, email, ip)

        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: ~p"/backoffice/login")

      admin ->
        _ = AuthAuditLog.log_login_success(:admin, admin.id, ip)
        maybe_mfa_or_log_in(conn, admin, params, ip)
    end
  end

  def delete(conn, _params) do
    if admin = conn.assigns[:current_admin] do
      _ = AuthAuditLog.log_logout(:admin, admin.id, peer_ip(conn))
    end

    conn
    |> put_flash(:info, "You have been logged out.")
    |> AdminAuth.log_out_admin()
  end

  @doc "POST /backoffice/verify-otp — Slice 7."
  def verify_otp(conn, %{"verify" => %{"code" => code}}) when is_binary(code) do
    case PendingMfa.read(conn) do
      {:ok, :admin, challenge_id, subject_id} ->
        do_verify(conn, challenge_id, subject_id, code)

      _ ->
        conn
        |> put_flash(:error, "Your verification session has expired. Please sign in again.")
        |> redirect(to: ~p"/backoffice/login")
    end
  end

  defp do_verify(conn, challenge_id, subject_id, code) do
    case OTP.verify(challenge_id, code) do
      :ok ->
        admin = Admins.get_admin!(subject_id)

        conn
        |> PendingMfa.clear()
        |> put_flash(:info, "Welcome back, #{admin.name}.")
        |> AdminAuth.log_in_admin(admin, %{})

      {:error, :mismatch} ->
        conn
        |> put_flash(:error, "That code didn't match. Try again.")
        |> redirect(to: ~p"/backoffice/verify-otp")

      {:error, reason} when reason in [:exhausted, :expired, :consumed, :not_found] ->
        conn
        |> PendingMfa.clear()
        |> put_flash(:error, "Verification expired. Please sign in again.")
        |> redirect(to: ~p"/backoffice/login")
    end
  end

  defp maybe_mfa_or_log_in(conn, admin, params, ip) do
    if PendingMfa.enabled?() do
      issue_and_redirect_to_mfa(conn, admin, ip)
    else
      conn
      |> put_flash(:info, "Welcome back, #{admin.name}.")
      |> AdminAuth.log_in_admin(admin, params)
    end
  end

  defp issue_and_redirect_to_mfa(conn, admin, ip) do
    case OTP.issue(:admin, admin.id, ip: ip) do
      {:ok, challenge_id, plain_code} ->
        _ = AdminNotifier.deliver_otp_email(admin, plain_code)

        conn
        |> PendingMfa.stash(:admin, challenge_id, admin.id)
        |> put_flash(
          :info,
          "We've sent a 6-digit sign-in code to your email. Enter it below to finish signing in."
        )
        |> redirect(to: ~p"/backoffice/verify-otp")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not start MFA verification. Please try again.")
        |> redirect(to: ~p"/backoffice/login")
    end
  end

  defp peer_ip(%Plug.Conn{remote_ip: ip}), do: ip |> :inet.ntoa() |> to_string()
end
