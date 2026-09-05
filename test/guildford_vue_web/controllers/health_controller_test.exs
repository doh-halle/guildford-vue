defmodule GuildfordVueWeb.HealthControllerTest do
  @moduledoc """
  Tests for the three health endpoints used by Fly's load balancer, internal
  monitoring, and the operations runbook (see `.claude/skills/devops-engineer`).

      GET /health           — liveness (200 + "ok")
      GET /health/ready     — readiness; pings DB and PubSub
      GET /health/cluster   — returns the list of connected BEAM nodes
  """
  use GuildfordVueWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 with a structured payload identifying the app", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "app" => "guildford_vue"
             }
    end

    test "responds well under Fly's 5-second health-check budget", %{conn: conn} do
      # Fly's load balancer times out a health check after 5s. We assert a
      # generous 2s ceiling to avoid flakes on a loaded CI runner — the
      # endpoint itself does no DB work, so the only sources of latency are
      # Phoenix/Bandit overhead. Drop this ceiling once we have a perf
      # baseline from Sprint 12's benchmarks.
      {micros, _} = :timer.tc(fn -> get(conn, ~p"/health") end)
      assert micros < 2_000_000, "health endpoint took #{micros} µs; budget is 2_000_000"
    end
  end

  describe "GET /health/ready" do
    test "returns 200 when the database is reachable", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      assert %{
               "status" => "ok",
               "checks" => %{
                 "database" => "ok",
                 "pubsub" => "ok"
               }
             } = json_response(conn, 200)
    end
  end

  describe "GET /health/cluster" do
    test "returns 200 with the local node always included", %{conn: conn} do
      conn = get(conn, ~p"/health/cluster")

      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert is_list(response["nodes"])
      assert Atom.to_string(Node.self()) in response["nodes"]
    end
  end
end
