defmodule GuildfordVueWeb.MetricsControllerTest do
  @moduledoc """
  Sprint 12 Slice 2 — /metrics endpoint behaviour. The PromEx
  collector itself is configured in `GuildfordVue.PromEx`; this
  suite pins the bearer-token auth + the controller's response
  shape.
  """
  use GuildfordVueWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:guildford_vue, :prometheus_auth_token)
    Application.put_env(:guildford_vue, :prometheus_auth_token, "test-secret-token-1234")

    on_exit(fn ->
      Application.put_env(:guildford_vue, :prometheus_auth_token, previous)
    end)

    :ok
  end

  test "401 without a bearer token", %{conn: conn} do
    conn = get(conn, ~p"/metrics")
    assert response(conn, 401) == "unauthorized"
    assert ["Bearer realm=\"metrics\""] = get_resp_header(conn, "www-authenticate")
  end

  test "401 with a wrong bearer token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong-token")
      |> get(~p"/metrics")

    assert response(conn, 401) == "unauthorized"
  end

  test "401 when PROMETHEUS_AUTH_TOKEN is unset (fails closed)", %{conn: conn} do
    Application.delete_env(:guildford_vue, :prometheus_auth_token)

    conn =
      conn
      |> put_req_header("authorization", "Bearer anything-at-all")
      |> get(~p"/metrics")

    assert response(conn, 401) == "unauthorized"
  end

  test "200 with the correct bearer token + Prometheus content-type", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer test-secret-token-1234")
      |> get(~p"/metrics")

    assert conn.status == 200

    [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/plain"
    assert content_type =~ "version=0.0.4"
  end
end
