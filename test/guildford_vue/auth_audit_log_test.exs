defmodule GuildfordVue.AuthAuditLogTest do
  @moduledoc """
  Sprint 11.5 Slice 2 — small wrapper that records auth-relevant
  events (login success/failure, logout, password-reset
  request/completion, rate-limit hit) via the existing
  `AuditLog.append/2` API.

  The wrapper exists so the three session controllers + auth
  modules don't each have to know event names + payload shapes.
  It also hashes the client IP before storing it (PRD §9 NFR:
  audit-log entries must be useful for correlation but not
  re-identifiable as PII).
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{AuditLog, AuthAuditLog}

  describe "hash_ip/1" do
    test "returns a deterministic string for the same IP" do
      a = AuthAuditLog.hash_ip("10.0.0.42")
      b = AuthAuditLog.hash_ip("10.0.0.42")
      assert a == b
      assert is_binary(a)
    end

    test "different IPs map to different hashes" do
      refute AuthAuditLog.hash_ip("10.0.0.42") ==
               AuthAuditLog.hash_ip("10.0.0.43")
    end

    test "raw IP does not appear in the hash" do
      hash = AuthAuditLog.hash_ip("203.0.113.7")
      refute hash =~ "203.0.113.7"
    end

    test "nil / unknown returns a stable sentinel" do
      assert AuthAuditLog.hash_ip(nil) == AuthAuditLog.hash_ip(nil)
      assert AuthAuditLog.hash_ip("unknown") == AuthAuditLog.hash_ip("unknown")
    end
  end

  describe "log_login_success/3" do
    test "writes a :candidate_login_succeeded audit event with the candidate id + ip hash" do
      cand_id = Ecto.UUID.generate()
      AuthAuditLog.log_login_success(:candidate, cand_id, "203.0.113.10")

      [event | _] = AuditLog.list(event_type: "candidate_login_succeeded", limit: 5)
      assert event.actor_id == cand_id
      assert event.actor_type == "candidate"
      assert event.payload["ip_hash"] == AuthAuditLog.hash_ip("203.0.113.10")
      refute event.payload["ip"]
    end

    test "writes per-scope event types" do
      ip = "10.0.0.1"
      AuthAuditLog.log_login_success(:admin, Ecto.UUID.generate(), ip)
      AuthAuditLog.log_login_success(:exam_centre, Ecto.UUID.generate(), ip)

      assert [_ | _] = AuditLog.list(event_type: "admin_login_succeeded", limit: 1)
      assert [_ | _] = AuditLog.list(event_type: "exam_centre_login_succeeded", limit: 1)
    end
  end

  describe "log_login_failure/3" do
    test "records the attempted email but never the password" do
      AuthAuditLog.log_login_failure(:candidate, "alice@example.com", "10.0.0.7")

      [event | _] = AuditLog.list(event_type: "candidate_login_failed", limit: 5)
      assert event.actor_id == nil
      assert event.payload["email"] == "alice@example.com"
      assert event.payload["ip_hash"]
      refute event.payload["password"]
    end
  end

  describe "log_logout/3" do
    test ":candidate_logged_out with actor + ip_hash" do
      cand_id = Ecto.UUID.generate()
      AuthAuditLog.log_logout(:candidate, cand_id, "10.0.0.8")

      [event | _] = AuditLog.list(event_type: "candidate_logged_out", limit: 5)
      assert event.actor_id == cand_id
      assert event.actor_type == "candidate"
    end
  end

  describe "log_password_reset_requested/3" do
    test "stores email + ip_hash, no actor id (we don't authenticate the requester)" do
      AuthAuditLog.log_password_reset_requested(:candidate, "alice@example.com", "10.0.0.9")

      [event | _] = AuditLog.list(event_type: "password_reset_requested", limit: 5)
      assert event.payload["email"] == "alice@example.com"
      assert event.payload["scope"] == "candidate"
      assert event.payload["ip_hash"]
      refute event.actor_id
    end
  end

  describe "log_password_reset_completed/3" do
    test "stores actor id + scope + ip_hash" do
      admin_id = Ecto.UUID.generate()
      AuthAuditLog.log_password_reset_completed(:admin, admin_id, "10.0.0.10")

      [event | _] = AuditLog.list(event_type: "password_reset_completed", limit: 5)
      assert event.actor_id == admin_id
      assert event.actor_type == "admin"
    end
  end

  describe "log_rate_limit_exceeded/3" do
    test "stores scope + ip_hash, no actor id" do
      AuthAuditLog.log_rate_limit_exceeded("candidate-login", "10.0.0.11")

      [event | _] = AuditLog.list(event_type: "rate_limit_exceeded", limit: 5)
      assert event.payload["scope"] == "candidate-login"
      assert event.payload["ip_hash"]
    end
  end
end
