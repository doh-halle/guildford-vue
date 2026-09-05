defmodule GuildfordVueWeb.ExamCentre.ExamCentreProfileLiveTest do
  @moduledoc """
  Sprint 3 Slice 4 — centre profile editor LiveView.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.ExamCentres

  setup %{conn: conn} do
    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "live-profile@example.com",
        "password" => "supersecret123!A",
        "name" => "Original Name",
        "address_line_1" => "1 Old Street",
        "city" => "London",
        "postcode" => "EC1A 1BB",
        "latitude" => 51.52,
        "longitude" => -0.10
      })

    # Approve so the centre can mint a session token and reach the profile page.
    {:ok, admin} =
      GuildfordVue.Admins.register_admin(%{
        "email" => "live-profile-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, approved} = ExamCentres.approve(centre, admin)

    token = ExamCentres.generate_session_token(approved)
    conn = init_test_session(conn, %{exam_centre_token: token})
    %{conn: conn, centre: approved}
  end

  test "renders the form prefilled with the centre's current values",
       %{conn: conn, centre: c} do
    {:ok, _lv, html} = live(conn, ~p"/examcenter/profile")
    assert html =~ c.name
    assert html =~ c.address_line_1
    assert html =~ c.postcode
  end

  test "submitting the form updates the centre", %{conn: conn, centre: c} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/profile")

    lv
    |> form("#centre-profile-form",
      profile: %{
        "name" => "Updated Name",
        "address_line_1" => "2 New Street",
        "address_line_2" => "",
        "city" => "Manchester",
        "postcode" => "M1 1AE",
        "contact_phone" => "+441619998888",
        "accreditation_evidence_url" => "https://evidence.example.com/cert.pdf"
      }
    )
    |> render_submit()

    reloaded = ExamCentres.get_exam_centre!(c.id)
    assert reloaded.name == "Updated Name"
    assert reloaded.city == "Manchester"
    assert reloaded.contact_phone == "+441619998888"

    assert reloaded.accreditation_evidence_url ==
             "https://evidence.example.com/cert.pdf"
  end

  test "invalid submit shows validation errors", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/profile")

    html =
      lv
      |> form("#centre-profile-form",
        profile: %{"name" => "", "address_line_1" => "", "city" => "", "postcode" => ""}
      )
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "phx-submit save event with extra params does NOT change email",
       %{conn: conn, centre: c} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/profile")

    # Bypass the form's field-allowlist by pushing the save event with
    # a payload that includes email — this simulates a hostile client
    # bypassing the rendered form. The context-level cast list is the
    # security boundary.
    render_hook(lv, "save", %{
      "profile" => %{
        "name" => c.name,
        "address_line_1" => c.address_line_1,
        "city" => c.city,
        "postcode" => c.postcode,
        "email" => "hijack@example.com"
      }
    })

    assert ExamCentres.get_exam_centre!(c.id).email == c.email
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/profile")
    assert redirect =~ "/examcenter/login"
  end
end
