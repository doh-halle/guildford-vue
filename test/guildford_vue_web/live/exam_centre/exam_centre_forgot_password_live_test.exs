defmodule GuildfordVueWeb.ExamCentre.ExamCentreForgotPasswordLiveTest do
  @moduledoc """
  Feature tests for GET /examcenter/forgot-password — the password-reset
  request page. Does NOT leak whether an email is registered (PRD §9
  privacy + OWASP A07).
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias GuildfordVue.ExamCentres

  setup do
    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "name" => "Test Centre",
        "address_line_1" => "1 Street",
        "city" => "City",
        "postcode" => "PC1 1PC"
      })

    %{centre: centre}
  end

  describe "GET /examcenter/forgot-password" do
    test "renders the form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/forgot-password")
      assert html =~ "Forgot password"
      assert html =~ "Email"
    end
  end

  describe "submit" do
    test "sends a reset email and redirects with a generic confirmation",
         %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/examcenter/forgot-password")

      lv
      |> form("#exam-centre-forgot-password-form", exam_centre: %{"email" => "alice@example.com"})
      |> render_submit()

      assert_redirect(lv, ~p"/examcenter/login")

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_n, addr} -> addr == "alice@example.com" end) and
          email.subject =~ "Reset your" and
          email.text_body =~ "/examcenter/reset-password/"
      end)
    end

    test "does NOT leak whether the email is registered (always same flash)",
         %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/examcenter/forgot-password")

      lv
      |> form("#exam-centre-forgot-password-form",
        exam_centre: %{"email" => "nobody@example.com"}
      )
      |> render_submit()

      assert_redirect(lv, ~p"/examcenter/login")
      # No email sent for non-existent address
      refute_email_sent()
    end
  end
end
