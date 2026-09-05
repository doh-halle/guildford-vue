defmodule GuildfordVueWeb.Admin.AdminSystemLiveTest do
  @moduledoc """
  Sprint 10 Slice 2 — /backoffice/system live OTP introspection panel.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Centres, ExamCentres}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "sys-live-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, admin: admin}
  end

  test "renders process count + centre server count + the supervision tree",
       %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/backoffice/system")

    assert html =~ "System health"
    assert html =~ "Supervision tree"
    assert html =~ "GuildfordVue.Supervisor"
    assert html =~ "GuildfordVue.Centres.Supervisor"

    count_html = lv |> element("[data-test-id='process-count']") |> render()
    assert count_html =~ ~r/>\s*\d+\s*</
  end

  test "lists running centres in the per-centre table", %{conn: conn} do
    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "sys-live-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Sys Live Centre",
        "address_line_1" => "1 St",
        "city" => "Bath",
        "postcode" => "BA1 1LT"
      })

    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "sys-live-approver-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Approver",
        "role" => "superadmin"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)
    {:ok, _pid} = Centres.start_centre(centre.id)
    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    {:ok, _lv, html} = live(conn, ~p"/backoffice/system")

    assert html =~ centre.id
    assert html =~ "Mailbox"
    assert html =~ "Memory"
  end
end
