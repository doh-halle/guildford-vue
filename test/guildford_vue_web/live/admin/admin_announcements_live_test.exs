defmodule GuildfordVueWeb.Admin.AdminAnnouncementsLiveTest do
  @moduledoc """
  Sprint 11 Slice 1 — /backoffice/announcements post + clear flow.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Announcements}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "ann-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    on_exit(fn -> Announcements.clear() end)

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, admin: admin}
  end

  test "posts a banner and shows it in the 'Currently posted' panel", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/announcements")

    html =
      lv
      |> form("#announcement-form", announcement: %{"text" => "Heads up team"})
      |> render_submit()

    assert html =~ "Heads up team"
    assert html =~ "Currently posted"
    assert Announcements.current().text == "Heads up team"
  end

  test "clear button removes the banner", %{conn: conn, admin: a} do
    {:ok, _} = Announcements.post("To be cleared", a)
    {:ok, lv, _} = live(conn, ~p"/backoffice/announcements")

    html = lv |> element("[data-test-id='clear-announcement']") |> render_click()

    assert html =~ "No banner is currently posted"
    refute Announcements.current()
  end
end
