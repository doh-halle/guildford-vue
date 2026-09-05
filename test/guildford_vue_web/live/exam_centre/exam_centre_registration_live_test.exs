defmodule GuildfordVueWeb.ExamCentre.ExamCentreRegistrationLiveTest do
  @moduledoc """
  Feature tests for the exam-centre registration LiveView.

  PRD §4.3 FR-CENTRE-1: centre self-registration (centre lands in :pending,
  awaiting admin approval).
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.ExamCentres

  @valid %{
    "email" => "manchester@example.com",
    "password" => "supersecret123!A",
    "name" => "Manchester Examination Hub",
    "address_line_1" => "12 Deansgate",
    "city" => "Manchester",
    "postcode" => "M1 1AE",
    "contact_phone" => "+441619998888"
  }

  describe "GET /examcenter/register" do
    test "renders the registration form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/register")
      assert html =~ "Register"
      assert html =~ "Centre name"
      assert html =~ "Email"
      assert html =~ "Address"
      assert html =~ "Postcode"
      assert html =~ "Password"
    end
  end

  describe "submit (phx-submit save event)" do
    test "registers a centre as :pending and redirects with the pending flash",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/examcenter/register")

      lv
      |> form("#exam-centre-registration-form", exam_centre: @valid)
      |> render_submit()

      assert_redirect(lv, ~p"/examcenter/login")

      centre = ExamCentres.get_exam_centre_by_email("manchester@example.com")
      assert centre
      assert centre.status == "pending"
    end

    test "rejects missing address", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/examcenter/register")

      result =
        lv
        |> form("#exam-centre-registration-form",
          exam_centre: Map.delete(@valid, "address_line_1")
        )
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "rejects duplicate email", %{conn: conn} do
      {:ok, _} = ExamCentres.register_exam_centre(@valid)

      {:ok, lv, _html} = live(conn, ~p"/examcenter/register")

      result =
        lv
        |> form("#exam-centre-registration-form", exam_centre: @valid)
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end
end
