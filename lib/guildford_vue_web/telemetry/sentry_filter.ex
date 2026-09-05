defmodule GuildfordVueWeb.Telemetry.SentryFilter do
  @moduledoc """
  Sprint 11.5 Slice 9 — `Sentry.before_send` filter. Walks the
  outgoing event recursively and replaces the value of any
  sensitive key with `"[FILTERED]"`. Closed allowlist of sensitive
  keys so the redaction set is explicit + greppable.

  Returns the event (possibly mutated) — Sentry forwards. Returning
  `nil` here would drop the event entirely; we do that only for
  payloads that match no useful pattern, never for unknown ones.
  """

  @sensitive_keys ~w(
    password
    password_confirmation
    hashed_password
    card
    pan
    masked_pan
    cvc
    cvv
    secret
    secret_key_base
    token
    code
    code_hash
    api_key
    authorization
  )

  @spec strip_sensitive(map() | Sentry.Event.t()) :: map() | Sentry.Event.t() | nil
  def strip_sensitive(%{} = event) do
    walk(event)
  end

  defp walk(%{__struct__: _} = struct) do
    Map.from_struct(struct) |> walk() |> then(&struct(struct.__struct__, &1))
  end

  defp walk(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      if sensitive?(k), do: {k, "[FILTERED]"}, else: {k, walk(v)}
    end)
  end

  defp walk(list) when is_list(list), do: Enum.map(list, &walk/1)
  defp walk(other), do: other

  defp sensitive?(k) when is_atom(k), do: Atom.to_string(k) in @sensitive_keys
  defp sensitive?(k) when is_binary(k), do: k in @sensitive_keys
  defp sensitive?(_), do: false
end
