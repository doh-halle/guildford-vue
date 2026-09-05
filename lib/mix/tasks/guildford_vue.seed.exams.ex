defmodule Mix.Tasks.GuildfordVue.Seed.Exams do
  @moduledoc """
  Seeds the UK exam catalogue from PRD §12.2 (~30 entries spanning
  driving, academic, IT, project mgmt, finance, language). Idempotent
  — existing codes are skipped.

  Requires at least one admin (uses the first `superadmin` if any,
  otherwise the first admin). Run `mix guildford_vue.seed.admins`
  first if the admin table is empty.

      $ mix guildford_vue.seed.exams
  """
  use Mix.Task

  alias GuildfordVue.Exams.Catalogue

  @shortdoc "Seeds the UK exam catalogue (PRD §12.2)."

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {inserted, skipped} = Catalogue.seed_catalogue()
    Mix.shell().info("  inserted: #{inserted}, skipped: #{skipped}")
    :ok
  end
end
