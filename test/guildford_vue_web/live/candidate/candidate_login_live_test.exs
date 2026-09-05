defmodule GuildfordVueWeb.Candidate.CandidateLoginLiveTest do
  @moduledoc """
  Feature tests for GET /candidate/login and the form submit → POST flow.
  """
  # Sprint 11.5 Slice 4 made the rate-limit plug honour the global
  # `:rate_limit_enabled` Application.env flag. The "rate-limit on
  # POST /login" describe below mutates that flag; serialising the
  # file with `async: false` avoids racing it with other async tests.
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.Candidates
  alias GuildfordVue.Candidates.Candidate

  setup %{conn: conn} do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "alice@example.com",
        "password" => "supersecret123!A",
        "first_name" => "Alice",
        "last_name" => "Worthington"
      })

    # Sprint 11.5 Slice 3 — the HTTP /candidate/login path enforces
    # email verification; stamp it here so these existing login-form
    # tests stay focused on the LV behaviour.
    {:ok, candidate} =
      candidate
      |> Candidate.confirm_email_changeset(DateTime.utc_now())
      |> GuildfordVue.Repo.update()

    %{conn: conn, candidate: candidate}
  end

  describe "GET /candidate/login (CandidateLoginLive)" do
    test "renders the login form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/candidate/login")
      assert html =~ "Sign in"
      assert html =~ "Email"
      assert html =~ "Password"
      assert html =~ "Register"
    end

    test "redirects an already-authenticated candidate to /candidate/dashboard",
         %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      assert {:error, {:live_redirect, %{to: "/candidate/dashboard"}}} =
               conn
               |> init_test_session(%{candidate_token: token})
               |> live(~p"/candidate/login")
    end
  end

  describe "POST /candidate/login (session controller)" do
    test "logs the candidate in on valid credentials", %{conn: conn, candidate: c} do
      conn =
        post(conn, ~p"/candidate/login", %{
          "candidate" => %{"email" => c.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/candidate/dashboard"
      assert get_session(conn, :candidate_token)
    end

    test "stamps an error flash on wrong password", %{conn: conn, candidate: c} do
      conn =
        post(conn, ~p"/candidate/login", %{
          "candidate" => %{"email" => c.email, "password" => "wrongpassword"}
        })

      assert redirected_to(conn) == ~p"/candidate/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      refute get_session(conn, :candidate_token)
    end

    test "stamps an error on unknown email (no leak)", %{conn: conn} do
      conn =
        post(conn, ~p"/candidate/login", %{
          "candidate" => %{"email" => "nobody@example.com", "password" => "supersecret123!A"}
        })

      assert redirected_to(conn) == ~p"/candidate/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
    end
  end

  describe "rate-limit on POST /candidate/login" do
    setup do
      # Sprint 11.5 Slice 4 extended the test-env :rate_limit_enabled
      # bypass to the login plug. Flip it back on for this describe
      # block — it specifically tests the limiter.
      previous = Application.get_env(:guildford_vue, :rate_limit_enabled)
      Application.put_env(:guildford_vue, :rate_limit_enabled, true)
      on_exit(fn -> Application.put_env(:guildford_vue, :rate_limit_enabled, previous) end)
      :ok
    end

    test "blocks after 5 attempts from the same IP within 15 minutes", %{conn: conn, candidate: c} do
      ip = {127, 0, 0, :rand.uniform(255)}
      conn = %{conn | remote_ip: ip}

      # 5 wrong-password attempts — all allowed but unsuccessful
      for _ <- 1..5 do
        resp =
          post(conn, ~p"/candidate/login", %{
            "candidate" => %{"email" => c.email, "password" => "wrong"}
          })

        assert Phoenix.Flash.get(resp.assigns.flash, :error) =~ "Invalid"
      end

      # 6th attempt — rate-limited
      blocked =
        post(conn, ~p"/candidate/login", %{
          "candidate" => %{"email" => c.email, "password" => "supersecret123!A"}
        })

      assert redirected_to(blocked) == ~p"/candidate/login"
      assert Phoenix.Flash.get(blocked.assigns.flash, :error) =~ "Too many"
      refute get_session(blocked, :candidate_token)
    end
  end
end
