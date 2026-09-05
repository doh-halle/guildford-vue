defmodule GuildfordVueWeb.Candidate.CandidateAuthTest do
  @moduledoc """
  Tests for `GuildfordVueWeb.Candidate.CandidateAuth` — the HTTP layer that
  reads/writes the candidate session cookie and gates `/candidate/*` routes.

  Independent from the admin and exam-centre auth plugs by construction: each
  uses a distinct session key (`:candidate_token` / `:admin_token` /
  `:exam_centre_token`) and a distinct assigns key (`:current_candidate` etc.).
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.Candidates
  alias GuildfordVue.Candidates.Candidate
  alias GuildfordVueWeb.Candidate.CandidateAuth

  @valid_attrs %{
    "email" => "alice@example.com",
    "password" => "supersecret123!A",
    "first_name" => "Alice",
    "last_name" => "Worthington"
  }

  setup %{conn: conn} do
    {:ok, candidate} = Candidates.register_candidate(@valid_attrs)

    # Sprint 11.5 Slice 3 — the HTTP /candidate/login path now requires
    # the candidate's email to be verified. The original Sprint 1c tests
    # registered + immediately logged in; verify the email here so the
    # existing flow tests stay focused on the auth-plug behaviour.
    {:ok, candidate} =
      candidate
      |> Candidate.confirm_email_changeset(DateTime.utc_now())
      |> GuildfordVue.Repo.update()

    # We use init_test_session/2 + fetch_flash/2 to materialise the session
    # storage and flash bag independently of the full endpoint pipeline so
    # these plug tests can run in isolation. secret_key_base is needed for
    # signed remember-me cookies — the endpoint normally sets it, but plug
    # tests don't go through the endpoint so we inject it here.
    conn =
      %{conn | secret_key_base: GuildfordVueWeb.Endpoint.config(:secret_key_base)}
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()

    %{conn: conn, candidate: candidate}
  end

  describe "log_in_candidate/3" do
    test "stores a session token under the :candidate_token key", %{conn: conn, candidate: c} do
      conn = CandidateAuth.log_in_candidate(conn, c)
      assert get_session(conn, :candidate_token)
      assert redirected_to(conn) == "/candidate/dashboard"
    end

    test "honours :candidate_return_to from the session if present",
         %{conn: conn, candidate: c} do
      conn =
        conn
        |> put_session(:candidate_return_to, "/candidate/settings")
        |> CandidateAuth.log_in_candidate(c)

      assert redirected_to(conn) == "/candidate/settings"
    end

    test "does NOT touch the :admin_token or :exam_centre_token session keys",
         %{conn: conn, candidate: c} do
      conn =
        conn
        |> put_session(:admin_token, "an-admin-token")
        |> put_session(:exam_centre_token, "a-centre-token")
        |> CandidateAuth.log_in_candidate(c)

      assert get_session(conn, :admin_token) == "an-admin-token"
      assert get_session(conn, :exam_centre_token) == "a-centre-token"
      assert get_session(conn, :candidate_token)
    end
  end

  describe "log_out_candidate/1" do
    test "clears the candidate token and redirects to /", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> put_session(:candidate_token, token)
        |> CandidateAuth.log_out_candidate()

      refute get_session(conn, :candidate_token)
      assert redirected_to(conn) == "/"
    end

    test "leaves the admin and exam_centre tokens intact", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> put_session(:admin_token, "an-admin-token")
        |> put_session(:exam_centre_token, "a-centre-token")
        |> put_session(:candidate_token, token)
        |> CandidateAuth.log_out_candidate()

      assert get_session(conn, :admin_token) == "an-admin-token"
      assert get_session(conn, :exam_centre_token) == "a-centre-token"
    end

    test "deletes the underlying DB token row", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)
      assert Candidates.get_candidate_by_session_token(token)

      _conn =
        conn
        |> put_session(:candidate_token, token)
        |> CandidateAuth.log_out_candidate()

      refute Candidates.get_candidate_by_session_token(token)
    end
  end

  describe "fetch_current_candidate/2" do
    test "assigns :current_candidate when a valid session token is present",
         %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> put_session(:candidate_token, token)
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate.id == c.id
    end

    test "assigns :current_candidate to nil when no token in session", %{conn: conn} do
      conn = CandidateAuth.fetch_current_candidate(conn, [])
      assert conn.assigns.current_candidate == nil
    end

    test "assigns :current_candidate to nil when token is invalid/garbage", %{conn: conn} do
      conn =
        conn
        |> put_session(:candidate_token, "not-a-real-token")
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate == nil
    end

    test "does NOT set the admin or exam-centre assigns", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> put_session(:candidate_token, token)
        |> CandidateAuth.fetch_current_candidate([])

      refute Map.has_key?(conn.assigns, :current_admin)
      refute Map.has_key?(conn.assigns, :current_exam_centre)
    end
  end

  describe "remember-me cookie (defect 001 fix)" do
    test "writes a signed remember-me cookie when params has remember_me=true",
         %{conn: conn, candidate: c} do
      conn = CandidateAuth.log_in_candidate(conn, c, %{"remember_me" => "true"})
      assert conn.resp_cookies["_guildford_vue_candidate_remember_me"]

      assert conn.resp_cookies["_guildford_vue_candidate_remember_me"].max_age >=
               30 * 24 * 60 * 60
    end

    test "does NOT write the remember-me cookie when the param is absent",
         %{conn: conn, candidate: c} do
      conn = CandidateAuth.log_in_candidate(conn, c, %{})
      refute conn.resp_cookies["_guildford_vue_candidate_remember_me"]
    end

    test "does NOT write the remember-me cookie when remember_me is something other than 'true'",
         %{conn: conn, candidate: c} do
      conn = CandidateAuth.log_in_candidate(conn, c, %{"remember_me" => "false"})
      refute conn.resp_cookies["_guildford_vue_candidate_remember_me"]
    end

    test "log_out_candidate clears the remember-me cookie", %{conn: conn, candidate: c} do
      conn1 = CandidateAuth.log_in_candidate(conn, c, %{"remember_me" => "true"})
      assert conn1.resp_cookies["_guildford_vue_candidate_remember_me"]

      conn2 =
        conn
        |> put_session(:candidate_token, Candidates.generate_session_token(c))
        |> CandidateAuth.log_out_candidate()

      cookie = conn2.resp_cookies["_guildford_vue_candidate_remember_me"]
      assert cookie.max_age == 0
    end
  end

  describe "idle session timeout (defect 003 fix)" do
    test "fetch_current_candidate clears the session if last_activity > 30 min ago",
         %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)
      stale = System.system_time(:second) - 31 * 60

      conn =
        conn
        |> put_session(:candidate_token, token)
        |> put_session(:candidate_last_activity_at, stale)
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate == nil
      refute get_session(conn, :candidate_token)
    end

    test "fetch_current_candidate refreshes last_activity_at on every request",
         %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> put_session(:candidate_token, token)
        |> put_session(:candidate_last_activity_at, System.system_time(:second) - 60)
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate.id == c.id
      refreshed = get_session(conn, :candidate_last_activity_at)
      assert refreshed >= System.system_time(:second) - 5
    end

    test "log_in_candidate sets last_activity_at fresh", %{conn: conn, candidate: c} do
      before_at = System.system_time(:second)
      conn = CandidateAuth.log_in_candidate(conn, c)
      assert get_session(conn, :candidate_last_activity_at) >= before_at
    end
  end

  describe "remember-me cookie fallback (defect 001 + 003 interplay)" do
    test "fetch_current_candidate uses the remember-me cookie when session token is missing",
         %{conn: conn, candidate: c} do
      # Step 1: log in with remember_me=true through the real endpoint so
      # the signed cookie gets a real signature.
      conn1 =
        conn
        |> post(~p"/candidate/login", %{
          "candidate" => %{
            "email" => c.email,
            "password" => "supersecret123!A",
            "remember_me" => "true"
          }
        })

      assert get_session(conn1, :candidate_token)

      # Step 2: recycle the conn — Phoenix carries the response cookies
      # forward as req cookies on the next request. Clear the session so
      # only the remember-me cookie remains as a valid auth carrier.
      conn2 =
        conn1
        |> recycle()
        |> get(~p"/candidate/dashboard")

      # If remember-me worked, the dashboard rendered (status 200).
      # If it didn't, we got a redirect to /candidate/login.
      assert conn2.status == 200
      assert conn2.resp_body =~ c.email
    end
  end

  describe "remember-me cookie defensive branches" do
    test "an invalid/garbage remember-me cookie is treated as no-cookie",
         %{conn: conn} do
      # Put a bogus value in the signed cookie slot — signature won't verify,
      # so Plug returns nil for the cookie and we fall through to nil assigns.
      conn =
        conn
        |> put_resp_cookie("_guildford_vue_candidate_remember_me", "garbage",
          sign: true,
          max_age: 60,
          http_only: true
        )

      # Recycle to move the resp_cookie into a req cookie
      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, GuildfordVueWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate == nil
    end

    test "a valid-looking remember-me cookie pointing at a revoked token returns nil",
         %{conn: conn, candidate: c} do
      # Issue a real token, then delete it from the DB to simulate
      # revocation while the cookie is still in the user's browser.
      token = Candidates.generate_session_token(c)
      :ok = Candidates.delete_session_token(token)

      conn =
        conn
        |> put_resp_cookie("_guildford_vue_candidate_remember_me", token,
          sign: true,
          max_age: 30 * 24 * 60 * 60,
          http_only: true
        )

      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, GuildfordVueWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate == nil
    end
  end

  describe "require_authenticated_candidate/2" do
    test "passes through when current_candidate is set", %{conn: conn, candidate: c} do
      token = Candidates.generate_session_token(c)

      conn =
        conn
        |> put_session(:candidate_token, token)
        |> CandidateAuth.fetch_current_candidate([])
        |> CandidateAuth.require_authenticated_candidate([])

      refute conn.halted
      assert conn.assigns.current_candidate.id == c.id
    end

    test "halts and redirects to /candidate/login with a flash when not logged in",
         %{conn: conn} do
      conn =
        conn
        |> assign(:current_candidate, nil)
        |> Map.put(:request_path, "/candidate/dashboard")
        |> Plug.Conn.fetch_query_params()
        |> CandidateAuth.require_authenticated_candidate([])

      assert conn.halted
      assert redirected_to(conn) == "/candidate/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "must log in"
    end

    test "stashes the requested path in :candidate_return_to", %{conn: conn} do
      conn =
        conn
        |> assign(:current_candidate, nil)
        |> Map.put(:request_path, "/candidate/settings")
        |> Plug.Conn.fetch_query_params()
        |> CandidateAuth.require_authenticated_candidate([])

      assert get_session(conn, :candidate_return_to) == "/candidate/settings"
    end
  end
end
