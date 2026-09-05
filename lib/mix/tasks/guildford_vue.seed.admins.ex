defmodule Mix.Tasks.GuildfordVue.Seed.Admins do
  @moduledoc """
  Seeds the two baseline admin accounts (PRD §12.5):

      admin@guildfordvue.test       — operator
      superadmin@guildfordvue.test  — superadmin

  Both are seeded with a single dev password sourced from `SEED_ADMIN_PASSWORD`
  (defaults to `seed-password-1!A` when the env var is unset, which is fine
  for dev/test but should be overridden in any environment that will be left
  reachable). The task is idempotent — re-running it is a no-op if both
  accounts already exist.

      $ mix guildford_vue.seed.admins
  """
  use Mix.Task

  alias GuildfordVue.Admins

  @shortdoc "Seeds the two baseline admin accounts."

  @seeds [
    %{
      "email" => "admin@guildfordvue.test",
      "name" => "Baseline Operator",
      "role" => "operator"
    },
    %{
      "email" => "superadmin@guildfordvue.test",
      "name" => "Baseline Superadmin",
      "role" => "superadmin"
    }
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    password = System.get_env("SEED_ADMIN_PASSWORD", "seed-password-1!A")

    Enum.each(@seeds, &seed_one(Map.put(&1, "password", password)))

    :ok
  end

  defp seed_one(attrs) do
    case Admins.get_admin_by_email(attrs["email"]) do
      nil -> insert(attrs)
      _existing -> Mix.shell().info("  exists: #{attrs["email"]} (skipping)")
    end
  end

  defp insert(attrs) do
    case Admins.register_admin(attrs) do
      {:ok, admin} ->
        Mix.shell().info("  inserted #{admin.role}: #{admin.email}")

      {:error, cs} ->
        Mix.shell().error("  failed to insert #{attrs["email"]}: #{inspect(cs.errors)}")
    end
  end
end
