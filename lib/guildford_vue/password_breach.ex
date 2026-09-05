defmodule GuildfordVue.PasswordBreach do
  @moduledoc """
  Behaviour + dispatcher for HIBP-style breached-password checks
  (OWASP A07 / Sprint 11.5 Slice 5).

  ## Behaviour

  Implementations return one of:

    * `:ok` — password not found in any known breach
    * `{:error, :breached, count}` — password found in `count`
      breach corpora
    * `{:error, term()}` — backend failure (network, parse, etc.).
      Schemas treat this as `:ok` so a hiccup never blocks a
      legitimate registration / password reset.

  ## Stub vs real adapter

  This sprint ships **architecture only**: a `Stub` adapter that
  returns `:ok` by default plus a `seed_breach/2` helper for tests
  that want to drive the check into the breached branch. The real
  HIBP adapter (k-anonymity API via Req) is a config swap in a
  later sprint — flip `:password_breach` to
  `GuildfordVue.PasswordBreach.Hibp` and no caller code changes.

  ## Dispatch

      iex> GuildfordVue.PasswordBreach.check("Password12345!")

  reads the configured adapter from
  `Application.get_env(:guildford_vue, :password_breach,
  GuildfordVue.PasswordBreach.Stub)` and delegates.
  """

  @type result :: :ok | {:error, :breached, non_neg_integer()} | {:error, term()}

  @callback check(password :: String.t()) :: result()

  @spec check(any()) :: result()
  def check(password) when is_binary(password), do: adapter().check(password)

  # Non-binary input is somebody else's problem (Ecto's
  # validate_required / validate_length already catches it). We
  # return :ok so the breach validator can sit unconditionally on
  # the changeset pipeline without re-implementing input checks.
  def check(_other), do: :ok

  # Tolerant of an explicit nil config value (Application.put_env
  # with nil is distinct from "not set" — `get_env`'s third-arg
  # default doesn't apply). Default to Stub.
  defp adapter do
    Application.get_env(:guildford_vue, :password_breach) || GuildfordVue.PasswordBreach.Stub
  end
end
