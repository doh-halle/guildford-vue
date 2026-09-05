defmodule GuildfordVueWeb.HealthController do
  @moduledoc """
  Operational health endpoints. Three routes, used by:

    * Fly's load balancer (`/health`) — must respond in <500 ms with no DB call
    * Internal monitoring (`/health/ready`) — pings DB and PubSub
    * Cluster introspection (`/health/cluster`) — for the dissertation's
      OTP distribution evidence chapter

  See `.claude/skills/devops-engineer/SKILL.md` §"Observability".
  """
  use GuildfordVueWeb, :controller

  alias Ecto.Adapters.SQL
  alias GuildfordVue.Repo

  def live(conn, _params) do
    json(conn, %{status: "ok", app: "guildford_vue"})
  end

  def ready(conn, _params) do
    {db_status, http_status} =
      case SQL.query(Repo, "SELECT 1", []) do
        {:ok, _} -> {"ok", 200}
        {:error, _} -> {"error", 503}
      end

    pubsub_status =
      case Process.whereis(GuildfordVue.PubSub) do
        nil -> "error"
        _pid -> "ok"
      end

    overall = if db_status == "ok" and pubsub_status == "ok", do: "ok", else: "degraded"

    conn
    |> put_status(http_status)
    |> json(%{
      status: overall,
      checks: %{
        "database" => db_status,
        "pubsub" => pubsub_status
      }
    })
  end

  def cluster(conn, _params) do
    nodes = [Node.self() | Node.list()] |> Enum.map(&Atom.to_string/1)
    json(conn, %{status: "ok", nodes: nodes})
  end
end
