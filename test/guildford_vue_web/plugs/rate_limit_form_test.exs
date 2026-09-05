defmodule GuildfordVueWeb.Plugs.RateLimitFormTest do
  @moduledoc """
  Sprint 11.5 Slice 1 — generic form-rate-limit plug. Sibling to
  RateLimitLogin (which is purpose-built for the three login
  POST endpoints) with a customisable flash message + redirect.
  Fails CLOSED on backend errors.
  """
  use GuildfordVueWeb.ConnCase, async: false

  alias GuildfordVueWeb.Plugs.RateLimitForm

  setup %{conn: conn} do
    {:ok, conn: Phoenix.ConnTest.init_test_session(conn, %{}) |> Phoenix.Controller.fetch_flash()}
  end

  defp opts(extra) do
    Keyword.merge(
      [
        scope: "test-form",
        limit: 3,
        scale_ms: 60 * 1000,
        redirect_to: "/redirected",
        flash_message: "Whoa, slow down."
      ],
      extra
    )
    |> RateLimitForm.init()
  end

  test "passes through when the limiter allows", %{conn: conn} do
    stub = fn _, _, _ -> {:allow, 1} end

    result = RateLimitForm.call(conn, opts(check_rate_fn: stub))
    refute result.halted
  end

  test "halts + redirects + flashes when the limiter denies", %{conn: conn} do
    stub = fn _, _, _ -> {:deny, 3} end

    result = RateLimitForm.call(conn, opts(check_rate_fn: stub))
    assert result.halted
    assert redirected_to(result) == "/redirected"
    assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Whoa, slow down."
  end

  test "fails CLOSED when the backend errors", %{conn: conn} do
    stub = fn _, _, _ -> {:error, :backend_down} end

    result = RateLimitForm.call(conn, opts(check_rate_fn: stub))
    assert result.halted
    assert redirected_to(result) == "/redirected"
    assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "Whoa, slow down."
  end
end
