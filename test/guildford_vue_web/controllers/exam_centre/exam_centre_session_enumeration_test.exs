defmodule GuildfordVueWeb.ExamCentre.ExamCentreSessionEnumerationTest do
  @moduledoc """
  Sprint 11.5 Slice 3 — exam-centre login must NOT distinguish
  "pending" centres from "invalid credentials" at the login
  layer. Distinct flashes let an attacker enumerate which
  emails are registered (pending = "we have this account, it
  just hasn't been approved" vs invalid = "no such account").

  The underlying `ExamCentres.authenticate/2` ADT (`:pending`
  vs `:invalid`) is preserved for the post-approval dashboard
  surface — it's only the *login form response* that's
  collapsed here.
  """
  use GuildfordVueWeb.ConnCase, async: false

  alias GuildfordVue.{Admins, ExamCentres}

  defp register_pending(email) do
    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => email,
        "password" => "supersecret123!A",
        "name" => "Pending Centre",
        "address_line_1" => "1 St",
        "city" => "Cardiff",
        "postcode" => "CF1 1AA"
      })

    centre
  end

  defp register_approved(email) do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "enum-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Admin",
        "role" => "superadmin"
      })

    centre = register_pending(email)
    {:ok, approved} = ExamCentres.approve(centre, admin)
    approved
  end

  test "pending centre + correct password gets the generic invalid flash", %{conn: conn} do
    centre = register_pending("pending-#{System.unique_integer([:positive])}@example.com")

    result_conn =
      post(conn, ~p"/examcenter/login", %{
        "exam_centre" => %{
          "email" => centre.email,
          "password" => "supersecret123!A"
        }
      })

    assert redirected_to(result_conn) =~ "/examcenter/login"
    assert flash = Phoenix.Flash.get(result_conn.assigns.flash, :error)
    assert flash =~ "Invalid email or password"
    refute flash =~ "pending"
    refute flash =~ "awaiting"
    refute flash =~ "approval"
  end

  test "unknown email gets the same generic flash", %{conn: conn} do
    result_conn =
      post(conn, ~p"/examcenter/login", %{
        "exam_centre" => %{
          "email" => "nobody-#{System.unique_integer([:positive])}@example.com",
          "password" => "supersecret123!A"
        }
      })

    assert redirected_to(result_conn) =~ "/examcenter/login"
    assert Phoenix.Flash.get(result_conn.assigns.flash, :error) == "Invalid email or password."
  end

  test "wrong password on a pending centre gets the same generic flash", %{conn: conn} do
    centre = register_pending("pending-wrong-#{System.unique_integer([:positive])}@example.com")

    result_conn =
      post(conn, ~p"/examcenter/login", %{
        "exam_centre" => %{
          "email" => centre.email,
          "password" => "WRONG!"
        }
      })

    assert Phoenix.Flash.get(result_conn.assigns.flash, :error) == "Invalid email or password."
  end

  test "the underlying ExamCentres.authenticate/2 still distinguishes :pending vs :invalid" do
    pending = register_pending("ctx-pending-#{System.unique_integer([:positive])}@example.com")

    assert {:error, :pending} = ExamCentres.authenticate(pending.email, "supersecret123!A")
    assert {:error, :invalid} = ExamCentres.authenticate("nobody@example.com", "x")
  end

  test "approved centre still logs in successfully", %{conn: conn} do
    centre = register_approved("approved-#{System.unique_integer([:positive])}@example.com")

    result_conn =
      post(conn, ~p"/examcenter/login", %{
        "exam_centre" => %{
          "email" => centre.email,
          "password" => "supersecret123!A"
        }
      })

    assert redirected_to(result_conn) =~ "/examcenter/dashboard"
    assert Phoenix.Flash.get(result_conn.assigns.flash, :info) =~ "Welcome back"
  end
end
