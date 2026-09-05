defmodule GuildfordVueWeb.ExamCentre.ExamCentreLoginLiveTest do
  @moduledoc """
  Feature tests for GET /examcenter/login and POST /examcenter/login.
  Differs from the candidate/admin login flow in one important way: a
  pending centre that supplies the right password is STILL rejected and
  shown a "your registration is awaiting admin approval" flash.
  """
  # Sprint 11.5 Slice 4 made the rate-limit plug honour the global
  # `:rate_limit_enabled` Application.env flag. The "rate-limit on
  # POST /login" describe below mutates that flag; serialising the
  # file with `async: false` avoids racing it with other async tests.
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

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

    {:ok, approved} = ExamCentres.approve(pending, admin)

    %{conn: conn, admin: admin, pending: pending, approved: approved}
  end

  describe "GET /examcenter/login (ExamCentreLoginLive)" do
    test "renders the login form with register link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/examcenter/login")
      assert html =~ "Sign in"
      assert html =~ "Exam centre"
      assert html =~ "Email"
      assert html =~ "Password"
    end

    test "redirects an already-authenticated approved centre to /examcenter/dashboard",
         %{conn: conn, approved: c} do
      token = ExamCentres.generate_session_token(c)

      assert {:error, {:live_redirect, %{to: "/examcenter/dashboard"}}} =
               conn
               |> init_test_session(%{exam_centre_token: token})
               |> live(~p"/examcenter/login")
    end
  end

  describe "POST /examcenter/login (session controller)" do
    test "logs an approved centre in on valid credentials",
         %{conn: conn, approved: c} do
      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/examcenter/dashboard"
      assert get_session(conn, :exam_centre_token)
    end

    test "stamps an error flash on wrong password", %{conn: conn, approved: c} do
      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => "wrong"}
        })

      assert redirected_to(conn) == ~p"/examcenter/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      refute get_session(conn, :exam_centre_token)
    end

    test "honours the remember-me checkbox for approved centres",
         %{conn: conn, approved: c} do
      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{
            "email" => c.email,
            "password" => "supersecret123!A",
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_guildford_vue_exam_centre_remember_me"]
    end

    test "PENDING centre with correct password gets the generic invalid-credentials flash (Sprint 11.5 Slice 3 — collapses :pending vs :invalid to defeat account enumeration)",
         %{conn: conn} do
      # Use a SEPARATE pending centre (not yet approved by the setup admin).
      {:ok, pending} =
        ExamCentres.register_exam_centre(%{
          "email" => "leeds@example.com",
          "password" => "supersecret123!A",
          "name" => "Leeds Test Centre",
          "address_line_1" => "1 Briggate",
          "city" => "Leeds",
          "postcode" => "LS1 1UR"
        })

      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => pending.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/examcenter/login"
      flash = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash == "Invalid email or password."
      refute flash =~ "awaiting"
      refute flash =~ "pending"
      refute get_session(conn, :exam_centre_token)
    end

    test "SUSPENDED centre sees the generic invalid-credentials flash (no leak)",
         %{conn: conn, approved: c} do
      {:ok, _} = ExamCentres.suspend(c)

      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/examcenter/login"
      # Deliberately the generic flash — we don't want to advertise that
      # an account has been suspended.
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      refute get_session(conn, :exam_centre_token)
    end
  end

  describe "rate-limit on POST /examcenter/login" do
    setup do
      previous = Application.get_env(:guildford_vue, :rate_limit_enabled)
      Application.put_env(:guildford_vue, :rate_limit_enabled, true)
      on_exit(fn -> Application.put_env(:guildford_vue, :rate_limit_enabled, previous) end)
      :ok
    end

    test "blocks after 5 attempts from the same IP", %{conn: conn, approved: c} do
      ip = {127, 0, 0, :rand.uniform(255)}
      conn = %{conn | remote_ip: ip}

      for _ <- 1..5 do
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => "wrong"}
        })
      end

      blocked =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(blocked) == ~p"/examcenter/login"
      assert Phoenix.Flash.get(blocked.assigns.flash, :error) =~ "Too many"
    end
  end
end
