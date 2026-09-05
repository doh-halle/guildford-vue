defmodule GuildfordVueWeb.ExamCentre.ExamCentreSessionControllerTest do
  @moduledoc """
  Sprint 1b Slice 1 placeholder coverage for the exam-centre session
  controller. Note: only approved centres can hold a valid session token,
  so the dashboard test must approve before it can log in.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.{Admins, ExamCentres}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "approver@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Approver"
      })

    {:ok, pending} =
      ExamCentres.register_exam_centre(%{
        "email" => "centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Test Centre",
        "address_line_1" => "1 Test Street",
        "city" => "Bristol",
        "postcode" => "BS1 4DJ"
      })

    {:ok, centre} = ExamCentres.approve(pending, admin)

    %{conn: conn, centre: centre}
  end

  describe "DELETE /examcenter/logout" do
    test "redirects to / and clears the exam_centre token", %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)

      conn =
        conn
        |> init_test_session(%{exam_centre_token: token})
        |> delete(~p"/examcenter/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :exam_centre_token)
    end
  end

  describe "GET /examcenter/dashboard (placeholder)" do
    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/examcenter/dashboard")
      assert redirected_to(conn) == ~p"/examcenter/login"
    end

    test "renders the placeholder when an approved centre is authenticated",
         %{conn: conn, centre: c} do
      token = ExamCentres.generate_session_token(c)

      conn =
        conn
        |> init_test_session(%{exam_centre_token: token})
        |> get(~p"/examcenter/dashboard")

      assert conn.status == 200
      assert conn.resp_body =~ "Test Centre"
      assert conn.resp_body =~ c.email
    end
  end
end
