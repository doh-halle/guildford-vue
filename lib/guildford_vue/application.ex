defmodule GuildfordVue.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias GuildfordVueWeb.Telemetry.SecurityHandler

  @impl true
  def start(_type, _args) do
    children =
      [
        GuildfordVueWeb.Telemetry,
        GuildfordVue.Repo,
        {DNSCluster, query: Application.get_env(:guildford_vue, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: GuildfordVue.PubSub},
        # Project-wide Task.Supervisor for fire-and-forget / async_stream
        # work that wants restart semantics (PRD §4.5 geocoder pool, etc).
        {Task.Supervisor, name: GuildfordVue.TaskSupervisor},
        # Geocoder cache (ETS-backed; named so async tests can reset).
        GuildfordVue.Geocoder.Cache,
        # Per-centre process tree (PRD §2.1 / §4.3). Registry + DynamicSupervisor;
        # CentreServers spawn on demand via GuildfordVue.Centres.start_centre/1.
        GuildfordVue.Centres.Supervisor,
        # Sprint 12 Slice 2 — PromEx metrics collector. Must start
        # AFTER Centres.Supervisor so the BookingPlugin's polled
        # measurement can read Centres.Registry on its first tick.
        GuildfordVue.PromEx
      ] ++
        chromic_pdf_children() ++
        [
          # Start to serve requests, typically the last entry
          GuildfordVueWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GuildfordVue.Supervisor]

    # Sprint 11.5 Slice 9 — attach the security telemetry handler
    # before the supervisor starts. Idempotent: telemetry returns
    # :already_exists if we re-attach (e.g. in dev code reload).
    _ = SecurityHandler.attach()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GuildfordVueWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ChromicPDF starts a Chromium pool, which is heavy and only
  # needed when the Chromic PDF adapter is in use. Test env leaves
  # it off (Stub serves rendered HTML directly); dev + prod opt
  # in via `config :guildford_vue, :start_chromic_pdf, true`.
  defp chromic_pdf_children do
    if Application.get_env(:guildford_vue, :start_chromic_pdf, false) do
      [{ChromicPDF, []}]
    else
      []
    end
  end
end
