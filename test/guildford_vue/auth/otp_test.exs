defmodule GuildfordVue.Auth.OTPTest do
  @moduledoc """
  Sprint 11.5 Slice 6 — email-OTP MFA context. Pins the issue/
  verify/exhaust/expire/resend state machine + the HMAC round-trip
  + audit-log emissions.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{AuditLog, Repo}
  alias GuildfordVue.Auth.OTP
  alias GuildfordVue.Auth.OTP.Challenge

  defp subject, do: {Enum.random([:candidate, :admin, :exam_centre]), Ecto.UUID.generate()}

  describe "issue/3" do
    test "returns {:ok, challenge_id, plain_code} and persists an HMAC-hashed row" do
      {scope, id} = subject()

      assert {:ok, challenge_id, plain} = OTP.issue(scope, id, ip: "203.0.113.42")
      assert is_binary(challenge_id)
      assert String.length(plain) == 6
      assert plain =~ ~r/^\d{6}$/

      row = Repo.get!(Challenge, challenge_id)
      assert row.subject_type == Atom.to_string(scope)
      assert row.subject_id == id
      assert row.purpose == "login_otp"
      assert row.attempts == 0
      assert row.consumed_at == nil
      # The stored hash is NOT the plain code:
      refute row.code_hash == plain
      assert byte_size(row.code_hash) == 32
    end

    test "expires_at is ~10 min from now" do
      {scope, id} = subject()
      {:ok, challenge_id, _} = OTP.issue(scope, id)
      row = Repo.get!(Challenge, challenge_id)

      seconds_from_now = DateTime.diff(row.expires_at, DateTime.utc_now())
      assert seconds_from_now > 9 * 60
      assert seconds_from_now <= 10 * 60 + 1
    end

    test "two calls issue distinct codes (cryptographically random)" do
      {scope, id} = subject()
      {:ok, _, a} = OTP.issue(scope, id)
      {:ok, _, b} = OTP.issue(scope, id)
      # Probability of collision is 1/10^6 per pair — accept the
      # tiny flake risk in exchange for the smoke test of randomness.
      refute a == b
    end

    test "writes an :otp_issued audit event with the subject as actor" do
      {scope, id} = subject()
      {:ok, _, _} = OTP.issue(scope, id, ip: "10.0.0.1")

      [event | _] = AuditLog.list(event_type: "otp_issued", limit: 5)
      assert event.actor_id == id
      assert event.actor_type == Atom.to_string(scope)
      assert event.payload["purpose"] == "login_otp"
      assert event.payload["ip_hash"]
    end
  end

  describe "verify/2" do
    test ":ok on the correct plain code; marks consumed_at" do
      {scope, id} = subject()
      {:ok, challenge_id, plain} = OTP.issue(scope, id)

      assert :ok = OTP.verify(challenge_id, plain)
      row = Repo.get!(Challenge, challenge_id)
      assert row.consumed_at
    end

    test "writes an :otp_verified audit event on success" do
      {scope, id} = subject()
      {:ok, challenge_id, plain} = OTP.issue(scope, id)

      :ok = OTP.verify(challenge_id, plain)

      [event | _] = AuditLog.list(event_type: "otp_verified", limit: 5)
      assert event.aggregate_id == challenge_id
    end

    test "{:error, :not_found} for an unknown challenge id" do
      assert {:error, :not_found} = OTP.verify(Ecto.UUID.generate(), "123456")
    end

    test "{:error, :mismatch} bumps attempts and audit-logs :otp_failed" do
      {scope, id} = subject()
      {:ok, challenge_id, _plain} = OTP.issue(scope, id)

      assert {:error, :mismatch} = OTP.verify(challenge_id, "000000")
      row = Repo.get!(Challenge, challenge_id)
      assert row.attempts == 1

      assert [_event | _] = AuditLog.list(event_type: "otp_failed", limit: 1)
    end

    test "{:error, :exhausted} on the 5th wrong code; audits :otp_locked" do
      {scope, id} = subject()
      {:ok, challenge_id, _plain} = OTP.issue(scope, id)

      for _ <- 1..4, do: OTP.verify(challenge_id, "000000")
      assert {:error, :exhausted} = OTP.verify(challenge_id, "000000")

      row = Repo.get!(Challenge, challenge_id)
      assert row.attempts == 5

      assert [_event | _] = AuditLog.list(event_type: "otp_locked", limit: 1)
    end

    test "{:error, :exhausted} on any subsequent verify, even with the right code" do
      {scope, id} = subject()
      {:ok, challenge_id, plain} = OTP.issue(scope, id)

      for _ <- 1..5, do: OTP.verify(challenge_id, "000000")
      assert {:error, :exhausted} = OTP.verify(challenge_id, plain)
    end

    test "{:error, :consumed} on a single-use re-verify" do
      {scope, id} = subject()
      {:ok, challenge_id, plain} = OTP.issue(scope, id)

      assert :ok = OTP.verify(challenge_id, plain)
      assert {:error, :consumed} = OTP.verify(challenge_id, plain)
    end

    test "{:error, :expired} when expires_at is in the past" do
      {scope, id} = subject()
      {:ok, challenge_id, plain} = OTP.issue(scope, id)

      # Backdate the expiry so the next verify trips the guard.
      Repo.get!(Challenge, challenge_id)
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      |> Repo.update!()

      assert {:error, :expired} = OTP.verify(challenge_id, plain)
    end
  end

  describe "resend/2" do
    test "issues a new challenge with a new plain code" do
      {scope, id} = subject()
      {:ok, first_id, first_plain} = OTP.issue(scope, id)

      assert {:ok, second_id, second_plain} = OTP.resend(first_id, ip: "10.0.0.2")
      refute first_id == second_id
      refute first_plain == second_plain
    end

    test "{:error, :not_found} for an unknown previous id" do
      assert {:error, :not_found} = OTP.resend(Ecto.UUID.generate())
    end
  end

  describe "expire_old!/0" do
    test "stamps consumed_at on every past-expiry non-consumed challenge" do
      {scope, id} = subject()
      {:ok, fresh_id, _} = OTP.issue(scope, id)
      {:ok, stale_id, _} = OTP.issue(scope, id)

      Repo.get!(Challenge, stale_id)
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -120, :second))
      |> Repo.update!()

      count = OTP.expire_old!()
      assert count >= 1

      assert Repo.get!(Challenge, stale_id).consumed_at
      assert Repo.get!(Challenge, fresh_id).consumed_at == nil
    end
  end
end
