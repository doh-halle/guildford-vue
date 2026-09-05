defmodule GuildfordVueWeb.Candidate.CandidateSessionController do
  @moduledoc """
  HTTP entry points for candidate sessions.

  Actions:
    * `:new`       — placeholder GET /candidate/login until Sprint 1b Slice 3
                     replaces it with the LiveView (kept for backwards-route
                     compatibility; the router now points GET at the LiveView).
    * `:create`    — POST /candidate/login. Authenticates via
                     `Candidates.get_candidate_by_email_and_password/2` and
                     calls `CandidateAuth.log_in_candidate/2`. Wraps the
                     authentication in a rate-limit plug at the router level
                     (PRD §4.1 FR-AUTH-4: 5 attempts / 15 min / IP).
    * `:delete`    — DELETE /candidate/logout.
    * `:dashboard` — placeholder protected page (Sprint 2 replaces with the
                     candidate dashboard LiveView).
  """
  use GuildfordVueWeb, :controller

  alias GuildfordVue.Auth.OTP
  alias GuildfordVue.{AuthAuditLog, Candidates}
  alias GuildfordVue.Candidates.CandidateNotifier
  alias GuildfordVueWeb.Auth.PendingMfa
  alias GuildfordVueWeb.Candidate.CandidateAuth

  def create(conn, %{"candidate" => params}) do
    %{"email" => email, "password" => password} = params
    ip = peer_ip(conn)

    case Candidates.authenticate_candidate(email, password) do
      {:ok, candidate} ->
        _ = AuthAuditLog.log_login_success(:candidate, candidate.id, ip)
        maybe_mfa_or_log_in(conn, candidate, params, ip)

      {:error, :email_not_verified} ->
        # Sprint 11.5 Slice 3 — bespoke flash for the unverified
        # case is OK here because the user already proved they know
        # the password (so we're not leaking account existence — the
        # password check itself is the gate).
        _ = AuthAuditLog.log_login_failure(:candidate, email, ip)

        conn
        |> put_flash(
          :error,
          "Please verify your email before signing in. Check your inbox for the verification link."
        )
        |> redirect(to: ~p"/candidate/login")

      {:error, :invalid_credentials} ->
        _ = AuthAuditLog.log_login_failure(:candidate, email, ip)

        conn
        |> put_flash(:error, "Invalid email or password.")
        |> redirect(to: ~p"/candidate/login")
    end
  end

  def delete(conn, _params) do
    if candidate = conn.assigns[:current_candidate] do
      _ = AuthAuditLog.log_logout(:candidate, candidate.id, peer_ip(conn))
    end

    conn
    |> put_flash(:info, "You have been logged out.")
    |> CandidateAuth.log_out_candidate()
  end

  @doc """
  POST /candidate/verify-otp — Slice 7. Reads the pending MFA
  stash, verifies the 6-digit code, and on success completes the
  login by re-fetching the candidate and calling
  `CandidateAuth.log_in_candidate/3`.
  """
  def verify_otp(conn, %{"verify" => %{"code" => code}}) when is_binary(code) do
    case PendingMfa.read(conn) do
      {:ok, :candidate, challenge_id, subject_id} ->
        do_verify(conn, challenge_id, subject_id, code)

      _ ->
        conn
        |> put_flash(:error, "Your verification session has expired. Please sign in again.")
        |> redirect(to: ~p"/candidate/login")
    end
  end

  defp do_verify(conn, challenge_id, subject_id, code) do
    case OTP.verify(challenge_id, code) do
      :ok ->
        candidate = Candidates.get_candidate!(subject_id)

        conn
        |> PendingMfa.clear()
        |> put_flash(:info, "Welcome back, #{candidate.first_name}.")
        |> CandidateAuth.log_in_candidate(candidate, %{})

      {:error, :mismatch} ->
        conn
        |> put_flash(:error, "That code didn't match. Try again.")
        |> redirect(to: ~p"/candidate/verify-otp")

      {:error, reason} when reason in [:exhausted, :expired, :consumed, :not_found] ->
        conn
        |> PendingMfa.clear()
        |> put_flash(:error, "Verification expired. Please sign in again.")
        |> redirect(to: ~p"/candidate/login")
    end
  end

  defp maybe_mfa_or_log_in(conn, candidate, params, ip) do
    if PendingMfa.enabled?() do
      issue_and_redirect_to_mfa(conn, candidate, ip)
    else
      conn
      |> put_flash(:info, "Welcome back, #{candidate.first_name}.")
      |> CandidateAuth.log_in_candidate(candidate, params)
    end
  end

  defp issue_and_redirect_to_mfa(conn, candidate, ip) do
    case OTP.issue(:candidate, candidate.id, ip: ip) do
      {:ok, challenge_id, plain_code} ->
        _ = CandidateNotifier.deliver_otp_email(candidate, plain_code)

        conn
        |> PendingMfa.stash(:candidate, challenge_id, candidate.id)
        |> put_flash(
          :info,
          "We've sent a 6-digit sign-in code to your email. Enter it below to finish signing in."
        )
        |> redirect(to: ~p"/candidate/verify-otp")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not start MFA verification. Please try again.")
        |> redirect(to: ~p"/candidate/login")
    end
  end

  defp peer_ip(%Plug.Conn{remote_ip: ip}), do: ip |> :inet.ntoa() |> to_string()
end
