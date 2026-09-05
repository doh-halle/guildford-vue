# Registers Postgrex extensions for PostGIS geometry/geography types so Ecto
# schemas can use `:geometry` and `:geography` columns transparently. The
# module is defined by Postgrex.Types.define/3 itself, not by `defmodule`.
# Referenced from `config :guildford_vue, GuildfordVue.Repo, types: …`.

Postgrex.Types.define(
  GuildfordVue.PostgresTypes,
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
