defmodule GuildfordVueWeb.MfaLoginIntegrationTest do
  @moduledoc """
  Sprint 11.5 Slice 7 — end-to-end email-OTP MFA login. Drives
  the full flow for the candidate scope (admin + exam-centre
  mirror the same controller + LV shape).

  Pins:
    * MFA disabled → login as today, no OTP redirect
    * MFA enabled → POST /candidate/login → 302 /candidate/verify-otp
      AND an email lands with a 6-digit code AND the pending stash
      is set in the session.
    * The 6-digit code POST → log_in_candidate runs.
    * Wrong code → flash + back to verify form, pending stash kept.
    * 5 wrong codes → "verification expired" + back to login.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias GuildfordVue.Auth.OTP.Challenge
  alias GuildfordVue.{Candidates, Repo}
  alias GuildfordVue.Candidates.Candidate

  setup do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "mfa-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Mfa",
        "last_name" => "X"
      })

    {:ok, candidate} =
      candidate
      |> Candidate.confirm_email_changeset(DateTime.utc_now())
      |> Repo.update()

    previous = Application.get_env(:guildford_vue, :mfa_via_email_enabled)
    on_exit(fn -> Application.put_env(:guildford_vue, :mfa_via_email_enabled, previous) end)

    %{candidate: candidate}
  end

  # Test-only fixture password, matched against the setup-block hash.
  @fixture_password "supersecret123!A"  # secrets:allow test-only fixture

  defp login_post(conn, candidate, opts \\ []) do
    post(conn, ~p"/candidate/login", %{
      "candidate" =>
        Keyword.merge(
          [email: candidate.email, password: @fixture_password],
          opts
        )
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
    })
  end

  test "MFA disabled — login proceeds straight to dashboard", %{conn: conn, candidate: c} do
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, false)

    conn = login_post(conn, c)
    assert redirected_to(conn) =~ "/candidate/dashboard"
    assert get_session(conn, :candidate_token)
  end

  test "MFA enabled — login redirects to verify-otp and emails the code",
       %{conn: conn, candidate: c} do
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, true)

    conn = login_post(conn, c)

    assert redirected_to(conn) =~ "/candidate/verify-otp"
    # No candidate_token yet — the session isn't established until verify_otp
    refute get_session(conn, :candidate_token)
    assert get_session(conn, :pending_mfa_challenge_id)
    assert get_session(conn, :pending_mfa_subject_id) == c.id

    assert_email_sent(fn email ->
      Enum.any?(email.to, fn {_n, addr} -> addr == c.email end) and
        email.subject =~ "sign-in code" and
        email.text_body =~ ~r/\b\d{6}\b/
    end)
  end

  test "verify-otp with the correct code completes login", %{conn: conn, candidate: c} do
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, true)

    conn = login_post(conn, c)
    challenge_id = get_session(conn, :pending_mfa_challenge_id)

    # Read the plain code from the audit-log payload? No — the plain
    # code only lives in the email. Pull it from the Mailcatcher
    # capture via the Swoosh test adapter.
    assert_email_sent(fn email ->
      [_, code | _] = Regex.run(~r/(\d{6})/, email.text_body)

      conn2 =
        recycle(conn)
        |> post(~p"/candidate/verify-otp", %{"verify" => %{"code" => code}})

      assert redirected_to(conn2) =~ "/candidate/dashboard"
      assert get_session(conn2, :candidate_token)
      refute get_session(conn2, :pending_mfa_challenge_id)
      true
    end)

    # The challenge row should now be marked consumed.
    assert Repo.get!(Challenge, challenge_id).consumed_at
  end

  test "wrong code keeps the verify form open and bumps attempts",
       %{conn: conn, candidate: c} do
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, true)

    conn = login_post(conn, c)
    challenge_id = get_session(conn, :pending_mfa_challenge_id)

    conn2 =
      recycle(conn)
      |> post(~p"/candidate/verify-otp", %{"verify" => %{"code" => "000000"}})

    assert redirected_to(conn2) =~ "/candidate/verify-otp"
    assert get_session(conn2, :pending_mfa_challenge_id) == challenge_id
    assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "didn't match"
    assert Repo.get!(Challenge, challenge_id).attempts == 1
  end

  test "5 wrong codes locks the challenge + redirects to login", %{conn: conn, candidate: c} do
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, true)

    conn = login_post(conn, c)

    final_conn =
      Enum.reduce(1..5, conn, fn _, acc ->
        recycle(acc)
        |> post(~p"/candidate/verify-otp", %{"verify" => %{"code" => "000000"}})
      end)

    assert redirected_to(final_conn) =~ "/candidate/login"
    refute get_session(final_conn, :pending_mfa_challenge_id)
    assert Phoenix.Flash.get(final_conn.assigns.flash, :error) =~ "expired"
  end
end
