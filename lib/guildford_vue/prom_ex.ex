defmodule GuildfordVue.PromEx do
  @moduledoc """
  PromEx wiring (Sprint 12 Slice 2). Exposes Prometheus-format
  metrics at `/metrics` so an external scraper (Prometheus,
  Grafana Cloud, etc.) can pull them.

  ## Plugins enabled

    * `Application`  — release version, beam memory, deps versions
    * `Beam`         — schedulers, processes, atoms, GC, memory
    * `Phoenix`      — endpoint + LiveView latency, sockets, status
    * `Ecto`         — pool checkout, query duration, row count
    * `PhoenixLiveView` — mount latency, handle_event duration
    * `Oban` — job runtimes, queue depths (Sprint 13+ when Oban
      gets active; safe to enable now)
    * `GuildfordVue.PromEx.SecurityPlugin` (custom) — security
      counters from the existing Sprint 11.5 SecurityHandler
    * `GuildfordVue.PromEx.BookingPlugin` (custom) — booking
      pipeline + CentreServer health

  ## /metrics endpoint

  Scrape with `curl -H "Authorization: Bearer $METRICS_TOKEN"
  http://host/metrics`. Token comes from the `PROMETHEUS_AUTH_TOKEN`
  env var (set in `config/runtime.exs`); when unset, the endpoint
  refuses every request — fail closed.
  """
  use PromEx, otp_app: :guildford_vue

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: GuildfordVueWeb.Router, endpoint: GuildfordVueWeb.Endpoint},
      Plugins.Ecto,
      Plugins.PhoenixLiveView,
      Plugins.Oban,
      GuildfordVue.PromEx.SecurityPlugin,
      GuildfordVue.PromEx.BookingPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "phoenix_live_view.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
