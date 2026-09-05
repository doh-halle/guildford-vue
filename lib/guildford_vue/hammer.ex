defmodule GuildfordVue.Hammer do
  @moduledoc """
  Rate-limit wrapper for callers that don't have a `Plug.Conn` —
  primarily LiveView `handle_event/3` implementations.

  Mirrors the contract of `GuildfordVueWeb.Plugs.RateLimitLogin`:
  same Hammer ETS backend, same `rate_limit:<scope>:<id>` bucket
  shape, same fail-CLOSED defaulting on backend errors (matches
  Defect 002 remediation, Sprint 1c).

  ## Usage

      case GuildfordVue.Hammer.check("candidate-register", peer_ip, 5, 60 * 60 * 1000) do
        :allow ->
          do_register(socket, params)

        {:deny, retry_after_seconds} ->
          {:noreply,
           put_flash(socket, :error,
             "Too many attempts. Please wait \#{retry_after_seconds}s and try again.")}
      end

  ## Test injection

  Pass `check_rate_fn: stub` in `opts` to swap the underlying
  Hammer call — useful in unit tests that want to drive the
  decision shape without spinning up the ETS backend.
  """

  @type result :: :allow | {:deny, retry_after_seconds :: pos_integer()}

  @doc """
  Returns `:allow` if the caller is under the per-scope limit,
  `{:deny, retry_after_seconds}` otherwise. **Fails CLOSED** when
  the backend errors — a hiccup must not become a free pass.

  Application-env switch `:rate_limit_enabled` (default `true`)
  short-circuits to `:allow` when false. `config/test.exs` flips
  it off so the wider suite doesn't have to manage shared ETS
  bucket state across unrelated LV tests. The `hammer_test.exs`
  unit + `rate_limit_form_test.exs` integration specs that
  actually verify the limiter pass `check_rate_fn:` stubs and so
  bypass the global flag.
  """
  @spec check(String.t(), String.t(), pos_integer(), pos_integer(), keyword()) :: result()
  def check(scope, identifier, limit, scale_ms, opts \\ [])
      when is_binary(scope) and is_binary(identifier) and is_integer(limit) and
             is_integer(scale_ms) do
    check_rate_fn = Keyword.get(opts, :check_rate_fn)

    cond do
      check_rate_fn ->
        do_check(check_rate_fn, scope, identifier, limit, scale_ms)

      Application.get_env(:guildford_vue, :rate_limit_enabled, true) == false ->
        :allow

      true ->
        do_check(&Hammer.check_rate/3, scope, identifier, limit, scale_ms)
    end
  end

  defp do_check(check_rate_fn, scope, identifier, limit, scale_ms) do
    bucket = "rate_limit:#{scope}:#{identifier}"

    case check_rate_fn.(bucket, scale_ms, limit) do
      {:allow, _count} ->
        :allow

      {:deny, _limit} ->
        {:deny, retry_after_seconds(scale_ms)}

      {:error, _reason} ->
        # Defect 002 fix: fail CLOSED on backend errors.
        {:deny, retry_after_seconds(scale_ms)}
    end
  end

  defp retry_after_seconds(scale_ms), do: max(1, div(scale_ms, 1_000))

  @doc """
  Reads `peer_data` from the LiveView connect info and stashes
  the dotted IP string under `:peer_ip` in socket assigns. Call
  this from `mount/3` (connect_info is only readable during
  mount); `socket_ip/1` then reads it back in any `handle_event`.

  Falls back to `"unknown"` for the disconnected HTTP-render
  pass; the WebSocket-mount pass overwrites it with the real
  client IP.
  """
  @spec assign_peer_ip(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_peer_ip(%Phoenix.LiveView.Socket{} = socket) do
    Phoenix.Component.assign(socket, :peer_ip, resolve_peer_ip(socket))
  end

  defp resolve_peer_ip(socket) do
    if Phoenix.LiveView.connected?(socket) do
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> address |> :inet.ntoa() |> to_string()
        _ -> "unknown"
      end
    else
      "unknown"
    end
  end

  @doc """
  Returns the assigned `:peer_ip` for the socket. Pair with
  `assign_peer_ip/1` in `mount/3`. Safe to call from
  `handle_event/3` because it reads assigns, not connect_info.
  """
  @spec socket_ip(Phoenix.LiveView.Socket.t()) :: String.t()
  def socket_ip(%Phoenix.LiveView.Socket{assigns: assigns}) do
    Map.get(assigns, :peer_ip, "unknown")
  end
end
