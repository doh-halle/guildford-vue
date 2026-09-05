defmodule GuildfordVue.Repo do
  use Ecto.Repo,
    otp_app: :guildford_vue,
    adapter: Ecto.Adapters.Postgres
end
