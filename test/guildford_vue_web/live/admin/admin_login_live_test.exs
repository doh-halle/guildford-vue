defmodule GuildfordVueWeb.Admin.AdminLoginLiveTest do
  @moduledoc """
  Feature tests for GET /backoffice/login and POST /backoffice/login.
  Mirror of `CandidateLoginLiveTest` for the admin scope.
  """
  # Sprint 11.5 Slice 4 made the rate-limit plug honour the global
  # `:rate_limit_enabled` Application.env flag. The "rate-limit on
  # POST /login" describe below mutates that flag; serialising the
  # file with `async: false` avoids racing it with other async tests.
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.Admins

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "ops@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Ops User"
      })

    %{conn: conn, admin: admin}
  end

  describe "GET /backoffice/login (AdminLoginLive)" do
    test "renders the login form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/backoffice/login")
      assert html =~ "Sign in"
      assert html =~ "Back office"
      assert html =~ "Email"
      assert html =~ "Password"
      # Admin login does NOT show a register link (admins are seeded/invited).
      refute html =~ ~r{href="/backoffice/register"}
    end

    test "redirects an already-authenticated admin to /backoffice/dashboard",
         %{conn: conn, admin: a} do
      token = Admins.generate_session_token(a)

      assert {:error, {:live_redirect, %{to: "/backoffice/dashboard"}}} =
               conn
               |> init_test_session(%{admin_token: token})
               |> live(~p"/backoffice/login")
    end
  end

  describe "POST /backoffice/login (session controller)" do
    test "logs the admin in on valid credentials", %{conn: conn, admin: a} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/backoffice/dashboard"
      assert get_session(conn, :admin_token)
    end

    test "stamps an error flash on wrong password", %{conn: conn, admin: a} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => "wrong"}
        })

      assert redirected_to(conn) == ~p"/backoffice/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      refute get_session(conn, :admin_token)
    end

    test "stamps an error on unknown email", %{conn: conn} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => "nobody@x", "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/backoffice/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
    end

    test "honours the remember-me checkbox", %{conn: conn, admin: a} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{
            "email" => a.email,
            "password" => "supersecret123!A",
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_guildford_vue_admin_remember_me"]
    end
  end

  describe "rate-limit on POST /backoffice/login" do
    setup do
      previous = Application.get_env(:guildford_vue, :rate_limit_enabled)
      Application.put_env(:guildford_vue, :rate_limit_enabled, true)
      on_exit(fn -> Application.put_env(:guildford_vue, :rate_limit_enabled, previous) end)
      :ok
    end

    test "blocks after 5 attempts from the same IP", %{conn: conn, admin: a} do
      ip = {127, 0, 0, :rand.uniform(255)}
      conn = %{conn | remote_ip: ip}

      for _ <- 1..5 do
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => "wrong"}
        })
      end

      blocked =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(blocked) == ~p"/backoffice/login"
      assert Phoenix.Flash.get(blocked.assigns.flash, :error) =~ "Too many"
      refute get_session(blocked, :admin_token)
    end
  end
end
