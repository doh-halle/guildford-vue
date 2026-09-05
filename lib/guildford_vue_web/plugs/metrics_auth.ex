defmodule GuildfordVueWeb.Plugs.MetricsAuth.OptsType do
  @moduledoc false
end

defmodule GuildfordVueWeb.Plugs.MetricsAuth do
  @moduledoc """
  Sprint 12 Slice 2 — bearer-token auth for the /metrics endpoint.

  Reads `PROMETHEUS_AUTH_TOKEN` from the application env (set in
  `config/runtime.exs`). When unset, every request is refused
  (401) — **fails closed**. Matches the existing Defect 002
  pattern.

  Comparison is constant-time via `Plug.Crypto.secure_compare/2`.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.get_env(:guildford_vue, :prometheus_auth_token)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> given] when is_binary(expected) and expected != "" ->
        if Plug.Crypto.secure_compare(given, expected) do
          conn
        else
          deny(conn)
        end

      _ ->
        deny(conn)
    end
  end

  defp deny(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="metrics"))
    |> send_resp(401, "unauthorized")
    |> halt()
  end
end
