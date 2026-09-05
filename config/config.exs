# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :guildford_vue,
  ecto_repos: [GuildfordVue.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :guildford_vue, GuildfordVueWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GuildfordVueWeb.ErrorHTML, json: GuildfordVueWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GuildfordVue.PubSub,
  live_view: [signing_salt: "CaqKDDCF"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :guildford_vue, GuildfordVue.Mailer, adapter: Swoosh.Adapters.Local

# Geocoder adapter — dev/test use the seeded postcode table; prod
# should switch to OSNames (or a real implementation thereof) via
# runtime config.
config :guildford_vue, :geocoder, GuildfordVue.Geocoder.Seeded

# Sprint 11.5 Slice 5 — breached-password adapter.
# Stub (returns :ok by default; tests can seed breaches) ships now;
# the real HIBP adapter (k-anonymity over Req) is a config swap
# in a follow-up sprint.
config :guildford_vue, :password_breach, GuildfordVue.PasswordBreach.Stub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  guildford_vue: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  guildford_vue: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Hammer rate limiter — used on /candidate/login, /backoffice/login,
# /examcenter/login in Sprint 1. Keyed by IP, 5 attempts per 15 minutes.
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Oban background jobs (queues are wired in runtime.exs for prod-vs-dev).
config :guildford_vue, Oban,
  repo: GuildfordVue.Repo,
  queues: [
    emails: 20,
    pdfs: 10,
    audits: 5,
    scheduled: 5
  ]

# Sentry — DSN comes from runtime.exs in prod; dev is a no-op.
config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
