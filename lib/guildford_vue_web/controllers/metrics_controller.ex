defmodule GuildfordVueWeb.MetricsController do
  @moduledoc """
  Sprint 12 Slice 2 — Prometheus-format metrics scrape endpoint.
  Bearer-authenticated by the `:metrics_auth` pipeline; renders
  the PromEx metric snapshot.

  Returns 503 when PromEx hasn't initialised (eg. during boot or
  in test env without the supervisor running) — never crashes.
  """
  use GuildfordVueWeb, :controller

  def show(conn, _params) do
    case PromEx.get_metrics(GuildfordVue.PromEx) do
      :prom_ex_down ->
        send_resp(conn, 503, "metrics collector not running")

      body when is_binary(body) ->
        conn
        |> put_resp_content_type("text/plain; version=0.0.4; charset=utf-8")
        |> send_resp(200, body)
    end
  end
end
