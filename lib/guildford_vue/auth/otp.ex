defmodule GuildfordVue.Auth.OTP do
  @moduledoc """
  Email-OTP MFA context (Sprint 11.5 Slice 6 / OWASP A07).

  Per-subject single-use 6-digit codes, HMAC-hashed at rest,
  10 min TTL, 5-attempt lockout. The caller emails the plaintext
  code; only the hash lives on the row.

  ## Lifecycle

      {:ok, challenge_id, plain_code} =
        OTP.issue(:candidate, candidate.id, ip: "203.0.113.10")

      OTP.verify(challenge_id, "123456")
      # → :ok | {:error, :expired | :exhausted | :consumed | :mismatch | :not_found}

      OTP.resend(challenge_id, ip: "203.0.113.10")
      # rate-limited to 1/min via Hammer; supersedes the previous

  ## Why HMAC, not Argon2

  6-digit codes have only ~10⁶ possible values, so Argon2 buys
  nothing against an attacker with a leaked `code_hash`. An
  HMAC keyed by `SECRET_KEY_BASE` means:
    * Verification is constant-time + microseconds-fast.
    * Without the key, a leaked hash cannot be brute-forced.

  ## Audit log

  Every transition writes a `GuildfordVue.AuditLog` event:
  `:otp_issued`, `:otp_verified`, `:otp_failed`, `:otp_locked`.
  """
  import Ecto.Query, warn: false

  alias GuildfordVue.{AuditLog, AuthAuditLog, Hammer, Repo}
  alias GuildfordVue.Auth.OTP.Challenge

  @code_length 6
  @expiry_seconds 10 * 60
  @max_attempts 5
  @resend_window_ms 60 * 1_000
  @resend_limit 1

  @type scope :: :candidate | :admin | :exam_centre
  @type verify_error :: :expired | :exhausted | :consumed | :mismatch | :not_found

  @doc """
  Issues a fresh challenge for `subject_type` × `subject_id`.
  Returns `{:ok, challenge_id, plain_code}` — the caller emails
  the plain code; we keep only the HMAC.

  Opts:
    * `:ip` — dotted IP string, hashed via `AuthAuditLog.hash_ip/1`
      and stored for correlation.
  """
  @spec issue(scope(), binary(), keyword()) :: {:ok, binary(), String.t()} | {:error, term()}
  def issue(subject_type, subject_id, opts \\ [])
      when subject_type in [:candidate, :admin, :exam_centre] and is_binary(subject_id) do
    plain = generate_code()
    ip = Keyword.get(opts, :ip)

    attrs = %{
      subject_type: Atom.to_string(subject_type),
      subject_id: subject_id,
      purpose: "login_otp",
      code_hash: hmac(plain),
      expires_at: DateTime.add(DateTime.utc_now(), @expiry_seconds, :second),
      attempts: 0,
      ip_hash: AuthAuditLog.hash_ip(ip)
    }

    %Challenge{}
    |> Ecto.Changeset.cast(attrs, Map.keys(attrs))
    |> Ecto.Changeset.validate_required([
      :subject_type,
      :subject_id,
      :purpose,
      :code_hash,
      :expires_at
    ])
    |> Repo.insert()
    |> case do
      {:ok, challenge} ->
        _ =
          AuditLog.append(:otp_issued, %{
            aggregate_id: challenge.id,
            actor: %{id: subject_id, type: Atom.to_string(subject_type)},
            payload: %{purpose: "login_otp", ip_hash: attrs.ip_hash}
          })

        {:ok, challenge.id, plain}

      {:error, cs} ->
        {:error, cs}
    end
  end

  @doc """
  Verifies a plaintext code against the stored hash.

  Returns:
    * `:ok` — verified + marked consumed.
    * `{:error, :not_found}` — no such challenge id.
    * `{:error, :consumed}` — single-use already burned.
    * `{:error, :expired}` — past `expires_at`.
    * `{:error, :exhausted}` — `@max_attempts` failed verifications.
    * `{:error, :mismatch}` — wrong code (attempts bumped).
  """
  @spec verify(binary(), String.t()) :: :ok | {:error, verify_error()}
  def verify(challenge_id, plain_code)
      when is_binary(challenge_id) and is_binary(plain_code) do
    case Repo.get(Challenge, challenge_id) do
      nil ->
        {:error, :not_found}

      %Challenge{} = challenge ->
        do_verify(challenge, plain_code)
    end
  end

  defp do_verify(%Challenge{consumed_at: at}, _plain) when not is_nil(at),
    do: {:error, :consumed}

  defp do_verify(%Challenge{attempts: a}, _plain) when a >= @max_attempts,
    do: {:error, :exhausted}

  defp do_verify(%Challenge{expires_at: exp} = challenge, plain) do
    if DateTime.compare(exp, DateTime.utc_now()) == :lt do
      {:error, :expired}
    else
      if Plug.Crypto.secure_compare(challenge.code_hash, hmac(plain)) do
        mark_consumed!(challenge)
        :ok
      else
        record_failure!(challenge)
      end
    end
  end

  defp mark_consumed!(%Challenge{} = challenge) do
    {:ok, updated} =
      challenge
      |> Ecto.Changeset.change(consumed_at: DateTime.utc_now())
      |> Repo.update()

    _ =
      AuditLog.append(:otp_verified, %{
        aggregate_id: updated.id,
        actor: %{id: updated.subject_id, type: updated.subject_type},
        payload: %{purpose: updated.purpose}
      })

    updated
  end

  defp record_failure!(%Challenge{} = challenge) do
    new_attempts = challenge.attempts + 1

    {:ok, updated} =
      challenge
      |> Ecto.Changeset.change(attempts: new_attempts)
      |> Repo.update()

    # Sprint 11.5 Slice 9 — emit telemetry for the security handler.
    :telemetry.execute([:guildford_vue, :auth, :otp_failed], %{count: 1}, %{
      scope: String.to_existing_atom(updated.subject_type)
    })

    _ =
      AuditLog.append(:otp_failed, %{
        aggregate_id: updated.id,
        actor: %{id: updated.subject_id, type: updated.subject_type},
        payload: %{attempts: new_attempts}
      })

    if new_attempts >= @max_attempts do
      _ =
        AuditLog.append(:otp_locked, %{
          aggregate_id: updated.id,
          actor: %{id: updated.subject_id, type: updated.subject_type},
          payload: %{attempts: new_attempts}
        })

      {:error, :exhausted}
    else
      {:error, :mismatch}
    end
  end

  @doc """
  Issues a fresh challenge to supersede `previous_id`, rate-limited
  to 1 per minute per subject. The previous challenge stays in the
  DB (audit trail) but its plain code is no longer needed.

  Returns the same shape as `issue/3` plus `{:error, :rate_limited}`.
  """
  @spec resend(binary(), keyword()) ::
          {:ok, binary(), String.t()} | {:error, :not_found | :rate_limited | term()}
  def resend(previous_id, opts \\ []) when is_binary(previous_id) do
    case Repo.get(Challenge, previous_id) do
      nil ->
        {:error, :not_found}

      %Challenge{subject_type: scope_str, subject_id: subject_id} ->
        case Hammer.check(
               "otp-resend:#{scope_str}:#{subject_id}",
               "subject",
               @resend_limit,
               @resend_window_ms
             ) do
          :allow -> issue(String.to_existing_atom(scope_str), subject_id, opts)
          {:deny, _} -> {:error, :rate_limited}
        end
    end
  end

  @doc """
  Sweep utility — marks expired non-consumed challenges as
  expired by stamping `consumed_at` so they don't accumulate
  active rows. Returns the row count.
  """
  @spec expire_old!() :: non_neg_integer()
  def expire_old! do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(c in Challenge,
          where: is_nil(c.consumed_at) and c.expires_at < ^now
        ),
        set: [consumed_at: now]
      )

    count
  end

  # ---- private helpers --------------------------------------------

  defp generate_code do
    # Cryptographically-random 6-digit code, zero-padded.
    n = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(1_000_000)
    String.pad_leading(Integer.to_string(n), @code_length, "0")
  end

  defp hmac(plain) when is_binary(plain) do
    :crypto.mac(:hmac, :sha256, hmac_key(), plain)
  end

  defp hmac_key do
    Application.fetch_env!(:guildford_vue, GuildfordVueWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
