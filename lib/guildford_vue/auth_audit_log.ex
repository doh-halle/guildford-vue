defmodule GuildfordVue.AuthAuditLog do
  @moduledoc """
  Auth-relevant audit-log helpers (Sprint 11.5 Slice 2 / OWASP
  A09 Logging & Monitoring). Wraps `GuildfordVue.AuditLog.append/2`
  so the three session controllers + auth modules don't have to
  reach for event names + payload shapes individually.

  ## IP hashing

  PRD §9 NFR: audit-log entries must be useful for cross-event
  correlation but not re-identifiable as PII. `hash_ip/1` derives
  an HMAC-SHA-256 of the IP string keyed by `SECRET_KEY_BASE`,
  Base64-encoded. Same IP → same hash; raw IP can't be recovered
  from the hash even by an investigator with full DB access.

  ## Scopes

  Pass the scope atom `:candidate` / `:admin` / `:exam_centre` —
  it becomes both the audit event prefix (e.g.
  `:candidate_login_succeeded`) and the `actor_type` string on
  the event row.
  """

  alias GuildfordVue.AuditLog

  @type scope :: :candidate | :admin | :exam_centre

  @doc """
  Returns an HMAC-SHA-256 of the IP, keyed by SECRET_KEY_BASE.
  `nil` and `"unknown"` map to stable sentinel hashes.
  """
  @spec hash_ip(String.t() | nil) :: String.t()
  def hash_ip(nil), do: hash_ip("__nil__")
  def hash_ip(ip) when is_binary(ip), do: do_hmac(ip)

  defp do_hmac(input) do
    :hmac
    |> :crypto.mac(:sha256, key(), input)
    |> Base.url_encode64(padding: false)
  end

  defp key do
    Application.fetch_env!(:guildford_vue, GuildfordVueWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end

  # Explicit per-scope event atoms — avoids `:"#{scope}_…"` atom
  # interpolation (Sobelow DOS.BinToAtom false positive on a closed
  # scope set) and keeps every event name greppable.
  @login_succeeded %{
    candidate: :candidate_login_succeeded,
    admin: :admin_login_succeeded,
    exam_centre: :exam_centre_login_succeeded
  }
  @login_failed %{
    candidate: :candidate_login_failed,
    admin: :admin_login_failed,
    exam_centre: :exam_centre_login_failed
  }
  @logged_out %{
    candidate: :candidate_logged_out,
    admin: :admin_logged_out,
    exam_centre: :exam_centre_logged_out
  }

  @doc "Successful login — actor id + ip hash recorded."
  @spec log_login_success(scope(), binary(), String.t() | nil) ::
          {:ok, AuditLog.Event.t()} | {:error, Ecto.Changeset.t()}
  def log_login_success(scope, actor_id, ip) do
    AuditLog.append(Map.fetch!(@login_succeeded, scope), %{
      aggregate_id: actor_id,
      actor: %{id: actor_id, type: scope_string(scope)},
      payload: %{ip_hash: hash_ip(ip)}
    })
  end

  @doc """
  Failed login attempt — records the attempted email + ip hash.
  Never records the password. No actor id (we couldn't
  authenticate).
  """
  @spec log_login_failure(scope(), String.t(), String.t() | nil) ::
          {:ok, AuditLog.Event.t()} | {:error, Ecto.Changeset.t()}
  def log_login_failure(scope, attempted_email, ip) do
    # Sprint 11.5 Slice 9 — emit telemetry alongside the audit row.
    :telemetry.execute([:guildford_vue, :auth, :login_failed], %{count: 1}, %{scope: scope})

    AuditLog.append(Map.fetch!(@login_failed, scope), %{
      payload: %{
        email: attempted_email,
        ip_hash: hash_ip(ip),
        scope: scope_string(scope)
      }
    })
  end

  @doc "Logout — actor id + ip hash."
  @spec log_logout(scope(), binary(), String.t() | nil) ::
          {:ok, AuditLog.Event.t()} | {:error, Ecto.Changeset.t()}
  def log_logout(scope, actor_id, ip) do
    AuditLog.append(Map.fetch!(@logged_out, scope), %{
      aggregate_id: actor_id,
      actor: %{id: actor_id, type: scope_string(scope)},
      payload: %{ip_hash: hash_ip(ip)}
    })
  end

  @doc """
  Password reset *requested*. We do NOT know whether the email
  matches a real account at this point (the LV deliberately
  responds identically either way to defeat enumeration), so we
  store the attempted email + ip hash + scope and no actor id.
  """
  @spec log_password_reset_requested(scope(), String.t(), String.t() | nil) ::
          {:ok, AuditLog.Event.t()} | {:error, Ecto.Changeset.t()}
  def log_password_reset_requested(scope, attempted_email, ip) do
    AuditLog.append(:password_reset_requested, %{
      payload: %{
        email: attempted_email,
        ip_hash: hash_ip(ip),
        scope: scope_string(scope)
      }
    })
  end

  @doc "Password reset *completed* — actor id known by this point."
  @spec log_password_reset_completed(scope(), binary(), String.t() | nil) ::
          {:ok, AuditLog.Event.t()} | {:error, Ecto.Changeset.t()}
  def log_password_reset_completed(scope, actor_id, ip) do
    AuditLog.append(:password_reset_completed, %{
      aggregate_id: actor_id,
      actor: %{id: actor_id, type: scope_string(scope)},
      payload: %{ip_hash: hash_ip(ip), scope: scope_string(scope)}
    })
  end

  @doc """
  Rate-limit tripped. `scope` is the Hammer scope string (e.g.
  `\"candidate-login\"` or `\"receipt-pdf\"`), not the auth scope
  atom.
  """
  @spec log_rate_limit_exceeded(String.t(), String.t() | nil) ::
          {:ok, AuditLog.Event.t()} | {:error, Ecto.Changeset.t()}
  def log_rate_limit_exceeded(scope, ip) when is_binary(scope) do
    AuditLog.append(:rate_limit_exceeded, %{
      payload: %{scope: scope, ip_hash: hash_ip(ip)}
    })
  end

  defp scope_string(:candidate), do: "candidate"
  defp scope_string(:admin), do: "admin"
  defp scope_string(:exam_centre), do: "exam_centre"
end
