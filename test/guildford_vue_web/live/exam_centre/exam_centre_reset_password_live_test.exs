defmodule GuildfordVueWeb.ExamCentre.ExamCentreResetPasswordLiveTest do
  @moduledoc """
  Feature tests for GET /examcenter/reset-password/:token. The form is
  rendered by the LiveView; phx-submit calls ExamCentres.reset_password/2
  which consumes the token and rotates the hash.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, ExamCentres}

  setup do
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
        "address_line_1" => "1 Street",
        "city" => "City",
        "postcode" => "PC1 1PC"
      })

    {:ok, centre} = ExamCentres.approve(pending, admin)

    {:ok, token} =
      ExamCentres.deliver_password_reset_instructions(centre, fn t -> "url " <> t end)

    %{centre: centre, token: token}
  end

  describe "GET /examcenter/reset-password/:token with a valid token" do
    test "renders the password form", %{conn: conn, token: token} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/reset-password/#{token}")
      assert html =~ "Reset your password"
      assert html =~ "New password"
    end
  end

  describe "GET with an invalid token" do
    test "shows an invalid-token message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/reset-password/not-a-real-token")
      assert html =~ "Reset link is invalid or expired"
    end
  end

  describe "submit (phx-submit save event)" do
    test "rotates the password and redirects to login",
         %{conn: conn, token: token, centre: c} do
      {:ok, lv, _} = live(conn, ~p"/examcenter/reset-password/#{token}")

      lv
      |> form("#exam-centre-reset-password-form",
        exam_centre: %{"password" => "newpassword456!B"}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/examcenter/login")

      assert ExamCentres.get_exam_centre_by_email_and_password(c.email, "newpassword456!B").id ==
               c.id
    end

    test "shows an error on too-short password (token preserved)",
         %{conn: conn, token: token} do
      {:ok, lv, _} = live(conn, ~p"/examcenter/reset-password/#{token}")

      result =
        lv
        |> form("#exam-centre-reset-password-form", exam_centre: %{"password" => "short"})
        |> render_submit()

      assert result =~ "should be at least 12"
    end
  end
end
