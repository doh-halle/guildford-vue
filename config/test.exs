import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :guildford_vue, GuildfordVue.Repo,
  username: "postgres",
  # secrets:allow local docker-compose test DB (CI also uses this value via service container)
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "guildford_vue_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  types: GuildfordVue.PostgresTypes,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :guildford_vue, GuildfordVueWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "5cxaCLt+QlWQMqveMdZW5KEWNyIb6Jr4JyJSSuimki4OLF6i/SPHbdc6+63bCFA0",
  server: false

# In test we don't send emails
config :guildford_vue, GuildfordVue.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Sprint 11.5 Slice 1 — disable the Hammer rate-limit globally in the
# test env. Per-test ETS bucket state across the async suite would
# otherwise flake unrelated LV tests after a few hits. Dedicated
# rate-limit tests (hammer_test.exs, rate_limit_form_test.exs) pass
# their own check_rate_fn stub and therefore bypass this flag.
config :guildford_vue, :rate_limit_enabled, false
