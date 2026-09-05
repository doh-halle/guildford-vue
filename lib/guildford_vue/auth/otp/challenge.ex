defmodule GuildfordVue.Auth.OTP.Challenge do
  @moduledoc """
  Persisted OTP challenge row backing `GuildfordVue.Auth.OTP`
  (Sprint 11.5 Slice 6). One row per issued code per subject;
  history is preserved (never deleted), so the audit trail is
  reconstructible.

  ## Fields

    * `subject_type` — `"candidate" | "admin" | "exam_centre"`,
      the auth scope. Stored as a string because the `subject_id`
      FK could point at any of three tables — we deliberately
      don't add a hard FK constraint.
    * `subject_id` — UUID of the candidate / admin / exam centre.
    * `purpose` — currently always `"login_otp"`; leaves room for
      future variants (e.g. `"transaction_otp"`).
    * `code_hash` — `HMAC-SHA256(SECRET_KEY_BASE, plaintext_code)`.
      Verified via `Plug.Crypto.secure_compare/2`.
    * `expires_at` — issued_at + 10 min.
    * `attempts` — incremented on each wrong verify; locked at 5.
    * `consumed_at` — non-nil = challenge already used (single-use).
    * `ip_hash` — SHA-256(ip + SECRET_KEY_BASE) — correlation key,
      not PII.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "auth_challenges" do
    field :subject_type, :string
    field :subject_id, :binary_id
    field :purpose, :string, default: "login_otp"
    field :code_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :attempts, :integer, default: 0
    field :consumed_at, :utc_datetime_usec
    field :ip_hash, :string

    timestamps(type: :utc_datetime_usec)
  end
end
