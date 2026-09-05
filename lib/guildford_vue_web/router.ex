defmodule GuildfordVueWeb.Router do
  use GuildfordVueWeb, :router

  # Import each scope's plug functions individually. This keeps Phoenix's
  # `plug :fn` syntax usable inside pipelines AND keeps the import surface
  # tight (only what each pipeline actually needs).
  import GuildfordVueWeb.Candidate.CandidateAuth,
    only: [fetch_current_candidate: 2, require_authenticated_candidate: 2]

  import GuildfordVueWeb.Admin.AdminAuth,
    only: [fetch_current_admin: 2, require_authenticated_admin: 2]

  import GuildfordVueWeb.ExamCentre.ExamCentreAuth,
    only: [fetch_current_exam_centre: 2, require_authenticated_exam_centre: 2]

  # ===========================================================================
  # Pipelines
  #
  # Each scope has its OWN browser pipeline so the three auth systems stay
  # genuinely independent — a request to /candidate/* does NOT run admin or
  # exam-centre scope fetchers, etc. (PRD §4.1: "There is no cross-
  # authentication: a candidate cannot use admin credentials and vice versa.")
  # ===========================================================================
  pipeline :browser_base do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GuildfordVueWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug GuildfordVueWeb.Plugs.SecureHeaders
    plug GuildfordVueWeb.Plugs.AssignAnnouncement
  end

  pipeline :browser_candidate do
    plug :fetch_current_candidate
  end

  pipeline :candidate_login_post do
    plug GuildfordVueWeb.Plugs.RateLimitLogin,
      scope: "candidate-login",
      limit: 5,
      scale_ms: 15 * 60 * 1000,
      redirect_to: "/candidate/login"
  end

  pipeline :require_candidate do
    plug :require_authenticated_candidate
  end

  pipeline :browser_admin do
    plug :fetch_current_admin
  end

  pipeline :require_admin do
    plug :require_authenticated_admin
  end

  pipeline :admin_login_post do
    plug GuildfordVueWeb.Plugs.RateLimitLogin,
      scope: "admin-login",
      limit: 5,
      scale_ms: 15 * 60 * 1000,
      redirect_to: "/backoffice/login"
  end

  pipeline :browser_exam_centre do
    plug :fetch_current_exam_centre
  end

  pipeline :require_exam_centre do
    plug :require_authenticated_exam_centre
  end

  pipeline :exam_centre_login_post do
    plug GuildfordVueWeb.Plugs.RateLimitLogin,
      scope: "exam-centre-login",
      limit: 5,
      scale_ms: 15 * 60 * 1000,
      redirect_to: "/examcenter/login"
  end

  # Public-but-scope-aware: runs all three fetchers so a logged-in candidate,
  # admin, or exam centre sees the right nav on shared pages (landing, /).
  # The fetchers each only touch their own session key + assigns key, so
  # running them in series does not violate PRD §4.1 isolation.
  pipeline :browser_with_scopes do
    plug :fetch_current_candidate
    plug :fetch_current_admin
    plug :fetch_current_exam_centre
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Sprint 12 Slice 2 — Prometheus scrape endpoint. Bearer-token
  # auth via PROMETHEUS_AUTH_TOKEN; fails closed when unset.
  pipeline :metrics_auth do
    plug GuildfordVueWeb.Plugs.MetricsAuth
  end

  # ===========================================================================
  # Public routes
  # ===========================================================================
  scope "/", GuildfordVueWeb do
    pipe_through [:browser_base, :browser_with_scopes]

    get "/", PageController, :home

    live_session :public_search, on_mount: [GuildfordVueWeb.Live.AnnouncementHook] do
      live "/search", SearchLive, :index
    end
  end

  scope "/health", GuildfordVueWeb do
    pipe_through :api

    get "/", HealthController, :live
    get "/ready", HealthController, :ready
    get "/cluster", HealthController, :cluster
  end

  scope "/", GuildfordVueWeb do
    pipe_through :metrics_auth

    get "/metrics", MetricsController, :show
  end

  # ===========================================================================
  # Candidate scope — /candidate/{login,logout,dashboard,settings,...}
  # ===========================================================================
  scope "/candidate", GuildfordVueWeb.Candidate do
    pipe_through [:browser_base, :browser_candidate]

    live_session :candidate_unauthenticated,
      on_mount: [
        {GuildfordVueWeb.Candidate.CandidateAuth, :assign_current_candidate},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/login", CandidateLoginLive, :new
      live "/register", CandidateRegistrationLive, :new
      live "/forgot-password", CandidateForgotPasswordLive, :new
      live "/reset-password/:token", CandidateResetPasswordLive, :new
      live "/verify-otp", CandidateVerifyOtpLive, :new
    end

    # Email verification is a single-shot controller, not a LiveView
    # (mount runs twice on a LiveView — once HTTP, once WebSocket — which
    # consumes the single-use token on the HTTP pass and shows "expired"
    # on the WebSocket pass).
    get "/verify-email/:token", CandidateConfirmationController, :show

    delete "/logout", CandidateSessionController, :delete
  end

  scope "/candidate", GuildfordVueWeb.Candidate do
    pipe_through [:browser_base, :browser_candidate, :candidate_login_post]

    post "/login", CandidateSessionController, :create
  end

  scope "/candidate", GuildfordVueWeb.Candidate do
    pipe_through [:browser_base, :browser_candidate]

    post "/verify-otp", CandidateSessionController, :verify_otp
  end

  scope "/candidate", GuildfordVueWeb.Candidate do
    pipe_through [:browser_base, :browser_candidate, :require_candidate]

    live_session :candidate_authenticated,
      on_mount: [
        {GuildfordVueWeb.Candidate.CandidateAuth, :assign_current_candidate},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/dashboard", CandidateDashboardLive, :index
      live "/settings", CandidateSettingsLive, :edit
      live "/bookings", CandidateBookingsLive, :index
      live "/bookings/:reference", CandidateBookingsLive, :show
    end
  end

  # Receipt download endpoints — plain controller (not LiveView)
  # because PDFs/HTML responses are byte streams with
  # `content-disposition` headers, not LV-shaped.
  scope "/candidate", GuildfordVueWeb do
    pipe_through [:browser_base, :browser_candidate, :require_candidate]

    get "/bookings/:reference/receipt.html", ReceiptController, :show_html
    get "/bookings/:reference/receipt.pdf", ReceiptController, :show_pdf
  end

  # Top-level auth-gated routes for candidate-initiated actions that don't
  # belong under /candidate (e.g. the booking flow that's reached from
  # the public /search). Same auth pipeline as /candidate/*; different
  # URL surface so the candidate is bookmarking the action, not their
  # dashboard.
  scope "/", GuildfordVueWeb do
    pipe_through [:browser_base, :browser_candidate, :require_candidate]

    live_session :candidate_authenticated_actions,
      on_mount: [
        {GuildfordVueWeb.Candidate.CandidateAuth, :assign_current_candidate},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/book/:slot_id", Candidate.BookSlotLive, :new
    end
  end

  # ===========================================================================
  # Admin / back-office scope — /backoffice/{login,logout,dashboard,...}
  # ===========================================================================
  scope "/backoffice", GuildfordVueWeb.Admin do
    pipe_through [:browser_base, :browser_admin]

    live_session :admin_unauthenticated,
      on_mount: [
        {GuildfordVueWeb.Admin.AdminAuth, :assign_current_admin},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/login", AdminLoginLive, :new
      live "/forgot-password", AdminForgotPasswordLive, :new
      live "/reset-password/:token", AdminResetPasswordLive, :new
      live "/verify-otp", AdminVerifyOtpLive, :new
    end

    delete "/logout", AdminSessionController, :delete
  end

  scope "/backoffice", GuildfordVueWeb.Admin do
    pipe_through [:browser_base, :browser_admin, :admin_login_post]

    post "/login", AdminSessionController, :create
  end

  scope "/backoffice", GuildfordVueWeb.Admin do
    pipe_through [:browser_base, :browser_admin]

    post "/verify-otp", AdminSessionController, :verify_otp
  end

  scope "/backoffice", GuildfordVueWeb.Admin do
    pipe_through [:browser_base, :browser_admin, :require_admin]

    live_session :admin_authenticated,
      on_mount: [
        {GuildfordVueWeb.Admin.AdminAuth, :assign_current_admin},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/dashboard", AdminDashboardLive, :index
      live "/settings", AdminSettingsLive, :edit
      live "/centres", AdminCentresLive, :index
      live "/candidates", AdminCandidatesLive, :index
      live "/admins", AdminAdminsLive, :index
      live "/audit-log", AdminAuditLogLive, :index
      live "/exams", AdminExamsLive, :index
      live "/exams/new", AdminExamsLive, :new
      live "/exams/:id/edit", AdminExamsLive, :edit
      live "/payment-settings", AdminPaymentSettingsLive, :edit
      live "/auth-settings", AdminAuthSettingsLive, :edit
      live "/system", AdminSystemLive, :index
      live "/bookings", AdminBookingsLive, :index
      live "/centres/performance", AdminCentrePerformanceLive, :index
      live "/announcements", AdminAnnouncementsLive, :index
    end
  end

  # ===========================================================================
  # Exam-centre scope — /examcenter/{login,logout,dashboard,...}
  # ===========================================================================
  scope "/examcenter", GuildfordVueWeb.ExamCentre do
    pipe_through [:browser_base, :browser_exam_centre]

    live_session :exam_centre_unauthenticated,
      on_mount: [
        {GuildfordVueWeb.ExamCentre.ExamCentreAuth, :assign_current_exam_centre},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/login", ExamCentreLoginLive, :new
      live "/register", ExamCentreRegistrationLive, :new
      live "/forgot-password", ExamCentreForgotPasswordLive, :new
      live "/reset-password/:token", ExamCentreResetPasswordLive, :new
      live "/verify-otp", ExamCentreVerifyOtpLive, :new
    end

    delete "/logout", ExamCentreSessionController, :delete
  end

  scope "/examcenter", GuildfordVueWeb.ExamCentre do
    pipe_through [:browser_base, :browser_exam_centre, :exam_centre_login_post]

    post "/login", ExamCentreSessionController, :create
  end

  scope "/examcenter", GuildfordVueWeb.ExamCentre do
    pipe_through [:browser_base, :browser_exam_centre]

    post "/verify-otp", ExamCentreSessionController, :verify_otp
  end

  scope "/examcenter", GuildfordVueWeb.ExamCentre do
    pipe_through [:browser_base, :browser_exam_centre, :require_exam_centre]

    live_session :exam_centre_authenticated,
      on_mount: [
        {GuildfordVueWeb.ExamCentre.ExamCentreAuth, :assign_current_exam_centre},
        GuildfordVueWeb.Live.AnnouncementHook
      ] do
      live "/dashboard", ExamCentreDashboardLive, :index
      live "/settings", ExamCentreSettingsLive, :edit
      live "/profile", ExamCentreProfileLive, :edit
      live "/exams", ExamCentreExamsLive, :index
      live "/slots", ExamCentreSlotsLive, :index
      live "/slots/new", ExamCentreSlotsLive, :new
      live "/slots/bulk", ExamCentreSlotsLive, :bulk
      live "/calendar", ExamCentreCalendarLive, :index
      live "/bookings", ExamCentreBookingsLive, :index
      live "/bookings/:reference", ExamCentreBookingsLive, :show
    end
  end

  # ===========================================================================
  # Dev-only routes
  # ===========================================================================
  if Application.compile_env(:guildford_vue, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser_base

      live_dashboard "/dashboard", metrics: GuildfordVueWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
