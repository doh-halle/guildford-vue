# Guildford Vue — Product Backlog

**Status convention**: `[ ]` pending · `[x]` complete · `[~]` in progress · `[!]` blocked

After each sprint closes, every item in its section MUST be checked.


---

## Sprint 0 — Foundation (Week 1)

**Goal**: Project scaffolding, CI/CD.

**Definition of done**: `mix phx.server` boots; `/health` returns 200; CI green
on a sample PR.

- [x] Initialise Phoenix project (`mix phx.new . --module GuildfordVue --binary-id --live`)
- [x] Configure PostgreSQL + PostGIS via docker-compose
- [x] Migration `EnablePostgis` (first migration)
- [x] Add core deps: argon2_elixir, geo, geo_postgis, oban, swoosh, gen_smtp, ex_aws + ex_aws_s3, chromic_pdf, eqrcode, hammer, stream_data, ex_machina, excoveralls, credo, dialyxir, sobelow, libcluster, prom_ex, sentry, mox, bypass, floki
- [x] Set up GitHub Actions CI (`.github/workflows/ci.yml`) running ExUnit, Credo, ExCoveralls, sobelow, Playwright
- [x] Author `.github/workflows/secret-scan.yml` (gitleaks + project secret-scan.sh)
- [x] Author `.github/workflows/deploy.yml` (inert via `if: false` until FLY_API_TOKEN ready)
- [x] Wire Tailwind v4 `@theme` + tokens.css from `docs/design/` into `assets/css/`
- [x] Load Manrope + IBM Plex Mono via Google Fonts in `root.html.heex`
- [x] Base layout with token-driven typography and three top-level auth links
- [x] Health endpoints: `/health`, `/health/ready`, `/health/cluster` (TDD; 4/4 tests, 81.8% line)
- [x] Playwright config with desktop + mobile projects + landing axe-core test
- [x] `scripts/secret-scan.sh` + `install-git-hooks.sh` + `chaos.exs`
- [x] `.githooks/pre-commit` installed; smoke-test (planted AKIA correctly blocked)


---

## Sprint 1 — Authentication Foundations (Weeks 2 - 3)

**Goal**: The authentication system operational and tested.

**Definition of done**: A candidate can self-register, verify email, log in,
log out, and reset their password. An admin (from seed) can log in. A centre
can self-register and lands in `:pending` status (cannot log in). Cross-auth
isolation test passes (candidate session cannot reach `/backoffice`).

**Status**: Sprint 1 **fully complete** (a + b + c). 251 ExUnit tests + 3 properties, 65 Playwright E2E tests (run in CI), 89.2% line coverage, 0 open defects. All three independent auth scopes operational end-to-end: register, log in (rate-limited), email-verify, forgot/reset password, dashboard, settings, log out. HSTS + strict CSP + force_ssl wired for production.

  - [x] `GuildfordVue.Candidates` context + schema + token + notifier
  - [x] `GuildfordVue.Admins` context + schema + token + notifier
  - [x] `GuildfordVue.ExamCentres` context + schema + token + notifier
- [x] Argon2id used everywhere; no `Bcrypt` references in `lib/`
- [x] Candidate schema additions: first_name, last_name, phone, postcode, email_verified_at, suspended_at
- [x] Admin schema additions: name, role (enum {operator, superadmin})
- [x] ExamCentre schema additions: name, address_*, postcode, latitude, longitude, geom (PostGIS, GiST-indexed), contact_phone, status (ADT pending/approved/suspended), approved_at, approved_by_admin_id, accreditation_evidence_url
- [x] Email verification flow for candidates (Swoosh → Mailcatcher in dev)
- [x] Rate limiting via Hammer on all three login endpoints (5 / 15 min / IP, fail-CLOSED) — **Sprint 1b + 1c**
- [x] Session management: 30-min idle timeout, "remember me" cookie (30 days candidate / 14 days admin + exam-centre) — **Sprint 1c** (closes defects 001 + 003)
- [x] Password reset for all three (single-use SHA-256-hashed email tokens) — context only; LiveViews in **Sprint 1c**
- [x] Pending centre state — `:pending` cannot log in until approved
- [x] Admin seed task: `mix guildford_vue.seed.admins` creating `admin@guildfordvue.test`, `superadmin@guildfordvue.test`
- [x] Logout flow for all three scopes (candidate / admin / exam centre) — **Sprint 1b + 1c** (dashboards still placeholder text)
- [x] Unit tests for password hashing (argon2 verify): grew to 197 tests + 3 properties across Sprints 1a/1b/1c
- [x] Property test: hashed password verifies; any tampered hash never verifies
- [x] LiveView feature tests for candidate login (6 tests, Sprint 1b), admin login (7 tests, Sprint 1c), exam-centre login (8 tests, Sprint 1c). Registration / forgot / reset / settings LiveViews → **Sprint 1c remaining**.
- [x] Cross-auth isolation test: context-level (9 tests) + HTTP-level (12 tests)
- [x] Three independent HTTP browser pipelines (`:browser_candidate` / `:browser_admin` / `:browser_exam_centre`) + scope-specific `require_<scope>` pipelines — **Sprint 1b**
- [x] Scope-aware layout cond-nav (4 branches) — **Sprint 1b**
- [x] AdminLoginLive + AdminSessionController.create + rate-limit — **Sprint 1c**
- [x] ExamCentreLoginLive + ExamCentreSessionController.create + pending-status messaging + rate-limit — **Sprint 1c**
- [x] `ExamCentres.authenticate/2` ADT with explicit pending vs invalid branches — **Sprint 1c**


**Sprint 1c full close — all carry-forward items now done**:
- [x] Fix ExCoveralls discovery — defect 002 closed via CoverRecorder bypass
- [x] CandidateRegistrationLive + ExamCentreRegistrationLive
- [x] Candidate email-verify (controller, not LiveView — single-shot token defeats LV double-mount)
- [x] CandidateForgotPasswordLive + CandidateResetPasswordLive (+ admin + exam-centre mirrors, 6 LiveViews)
- [x] Settings LiveViews for all three scopes (candidate: profile + password; admin & centre: password only)
- [x] Real dashboards for all three scopes
- [x] Layout `href=` flipped to `~p` for settings links
- [x] HSTS + strict CSP + force_ssl in endpoint config (prod-only via Plug.SSL; dev/test unaffected)
- [x] Playwright E2E: 3 spec files × 5 browser projects = 65 tests (run in CI; Chromium ~300MB)
- [x] axe-core in CI on all three login pages + landing
- [x] Lighthouserc.json with thresholds (CI job gated `if: false` until deploy preview URL exists)


---

## Sprint 2 — Admin Foundations (Weeks 2 - 3)

- [x] Admin layout with sidebar navigation
- [x] Dashboard landing with placeholder metrics
- [x] Candidate management: search, view, suspend, reactivate
- [x] Admin user management: invite, role assignment
- [x] Centre approval queue: list pending, view details, approve/reject with reason
- [x] Email notifications on approval/rejection
- [x] Audit log schema + write-only context API

---

## Sprint 3 — Exam Catalogue & Centre Profile (Week 4)

- [x] Exam CRUD in admin (name, code, certification body, description, duration, price)
- [x] Seed UK exam catalogue
- [x] Centre dashboard layout
- [x] Centre profile management (address, contact, accreditation evidence)
- [x] Geocoding integration: postcode → lat/long on save (OS Names API in prod, seeded in dev)
- [x] Centre exam offering selection (many-to-many join `exam_centre_exams`)


---

## Sprint 4 — Slot Management (Week 5)

- [x] Slot schema (capacity, available_count, status)
- [x] Per-centre GenServer (`GuildfordVue.Centres.CentreServer`) holding slot inventory as immutable state
- [x] OTP supervision: `Centres.Supervisor` → `DynamicSupervisor` → `CentreServer` instances
- [x] Slot creation UI (single slot)
- [x] Bulk slot creation with recurring schedules
- [x] Slot listing + editing in centre dashboard
- [x] Slot cancellation with candidate notification stub
- [x] Property test: bookings never exceed capacity
- [x] Property test: cancellation reverses state correctly


---

## Sprint 5 — Guest & Candidate Search (Week 6)

- [x] UK postcode validation
- [x] Geo-spatial query via PostGIS (`ST_DWithin`) for centres within radius
- [x] Supervised geocoding worker pool (poolboy)
- [x] Map view (Leaflet or MapLibre)
- [x] Centre list view alongside map
- [x] Filter by exam type + date range
- [x] Guest postcode search page (no login)
- [x] Auth-gate on "Book this slot" action
- [x] Indicative availability indicators on map markers


---

## Sprint 6 — Real-Time Availability (Week 7)

- [x] Phoenix Channels topic per centre (`centre:<id>`)
- [x] LiveView subscriptions on calendar view (after `connected?(socket)`)
- [x] Calendar component with colour-coded slot grid (green/yellow/grey)
- [x] ADT for slot availability (`:available`, `:limited`, `:fully_booked`, `:cancelled`)
- [x] Exhaustive pattern matching in availability rendering
- [x] PubSub broadcast on every state change
- [x] Smooth colour transition animations
- [x] Load test: 1,000 concurrent subscribers receive updates within 500 ms p95


---

## Sprint 7 — Booking Pipeline (Railway-Oriented) (Week 8)

- [x] Booking flow LiveView (select slot → confirm details)
- [x] Railway-oriented pipeline module using `with`: validate → reserve → pay → persist → generate PDF → email → broadcast → audit
- [x] Each pipeline stage returns `{:ok, _} | {:error, _}`
- [x] Rollback semantics on failure at any stage
- [x] Booking reference generation (e.g. `GV-2026-A4B7K9`)
- [x] Reservation persistence
- [x] Property test: cancellation + rebooking restores original state
- [x] Concurrent stress test: 200 candidates → same slot → exactly one succeeds


---

## Sprint 8 — Payment Simulation (Week 9)

- [x] Payment selection step (Visa, Mastercard, Amex, PayPal, Apple Pay, Google Pay)
- [x] Card details form with Luhn validation + expiry check
- [x] Loading spinner randomised 1.5–3 second interval
- [x] "Payment Successfully Processed" confirmation
- [x] Admin toggle: 5% simulated decline rate
- [x] Pipeline integration: payment failure surfaces gracefully
- [x] Payment record persisted with masked card details


---

## Sprint 9 — PDF Receipts & Candidate Dashboard (Week 10)

- [x] ChromicPDF integration (Chromium in runtime image) — Slice 3
- [x] PDF template with branding, booking ref, exam details, centre address, QR code — Slice 1
- [x] Download button on confirmation page — Slice 2 (canonical `/candidate/bookings/<ref>/receipt.pdf` URL stamped on the booking, served by `ReceiptController` via the active adapter)
- [x] Candidate dashboard listing upcoming + past reservations — Slice 5 (Upcoming/Past sections on `/candidate/bookings`; dashboard upcoming count + first-three quick links)
- [x] Re-download PDF from dashboard — Slice 2 (the per-booking detail page's "Download PDF" link is now Chromic-rendered on demand)
- [x] Cancellation flow from candidate dashboard — Sprint 7 carry-over, still wired on the detail page
- [x] Email confirmation with PDF attachment — Slice 4 (`CandidateNotifier.deliver_booking_confirmation_email/2` attaches the rendered PDF when `:pdf_bytes` is supplied)


---

## Sprint 10 — Admin Metrics & Operations (Weeks 11)

- [x] Live metrics dashboard (candidates, centres, bookings, revenue) — Slice 1 (uptime + p95 latency are PromEx/Telemetry surface, deferred to Sprint 12 evaluation hardening)
- [x] Audit log viewer with search + filters — Slice 3 extends Sprint 2's viewer with date-range filters
- [x] System health panel (OTP supervision tree visualisation, process counts, mailbox depths) — Slice 2
- [x] Action buttons: refund booking, suspend user — Slice 4 (broadcast announcement deferred to Sprint 11; candidate suspend was already shipped in Sprint 2)
- [x] Centre performance metrics (bookings per centre, fill rate, cancellation rate) — Slice 5 (no-show rate needs slot-attendance tracking, deferred)


---

## Sprint 11 — Mobile Polish & Accessibility (Week 12)

- [x] Mobile-specific layouts (search map-first ordering, booking flow as bottom-sheet) — Slices 2–3
- [x] Touch-optimised slot selection (full-width `min-h-11` CTAs on mobile) — Slice 2
- [x] Bottom-sheet modals on mobile — Slice 3
- [x] axe-core audit in CI with zero violations — Slice 4 (`test/e2e/accessibility.spec.ts`, picked up by the existing Playwright CI job)
- [x] Keyboard navigation audit + skip-to-main link — Slice 5 (`docs/a11y-keyboard-nav.md`)
- [ ] Lighthouse ≥90 all categories — deferred to Sprint 12 (needs deployed instance + Lighthouse-CI runner)
- [x] Performance optimisation (gzip + minify + cache_static_manifest + HSTS already shipped; HTTP/2 + code splitting deferred to deploy) — Slice 6 + `docs/performance.md`
- [x] Broadcast announcement (Sprint 10 carry-over) — Slice 1


---

## Sprint 11.5 — Security Hardening (Week 14 - OWASP Top 10)

Security Hardening - OWASP Top 10 vulnerability mitigation

- [x] Form rate-limit beyond login (registration, forgot-password, search, PDF fetch, payment attempt) — Slice 1
- [x] Session cookie hardening (`http_only` + `secure: :always` + `encryption_salt`) — Slice 2
- [x] Auth-event audit logging (login success/failure, password reset, logout, rate-limit hits, OTP events) — Slice 2
- [x] Email-verification enforcement on candidate login — Slice 3
- [x] Exam-centre login enumeration fix (collapse "pending" vs "invalid" at the login layer) — Slice 3
- [x] Absolute session timeout (12 h hard cap) — Slice 3
- [x] GitHub Actions pinned to commit SHAs — Slice 4
- [x] Dockerfile base images pinned to @sha256 digests — Slice 4
- [x] Dependabot config (mix / npm / github-actions / docker) — Slice 4
- [x] Sobelow CSP false-positive suppressed via `.sobelow-conf` — Slice 4
- [x] HIBP breached-password check — behaviour + Stub adapter (no outbound HTTP this sprint; real adapter is a config swap in a follow-up) — Slice 5
- [x] Email-OTP MFA foundations: `auth_challenges` table + `Auth.OTP` context (HMAC-SHA256 codes, 10 min expiry, 5-attempt lockout) — Slice 6
- [x] Email-OTP MFA login integration across all three scopes + verify-OTP LiveViews + `<scope>Notifier.deliver_otp_email/2` — Slice 7
- [x] Admin MFA toggle at `/backoffice/auth-settings` (superadmin-only, audit-logged) — Slice 8
- [x] Sentry wired with PII-filtering `before_send` (strips password / card / pan / cvc / secret / token / code) — Slice 9
- [x] Security telemetry handler (rate-limit / login-failed / otp-failed counters via PromEx) — Slice 9

---

## Sprint 12 — Evaluation Hardening, Measurement Instrument and The measurement Campaign (Week 14, +1 week due to Sprint 11.5)


- [x] Tsung load test scripts (target ≥10K sustained) — Slice 6 (XML + runner; actual runs deploy-time)
- [x] Fault injection harness — Slice 4 (extended `scripts/chaos.exs` from 2 → 4 scenarios with JSONL emit)
- [x] Telemetry instrumentation — Slice 2 (PromEx + custom Security & Booking plugins + bearer-auth `/metrics`)
- [x] SonarQube config skeleton — Slice 8 (`sonar-project.properties`; live run deferred — needs SONAR_TOKEN)
- [x] Comprehensive seed data — Slice 1 (2 admins, 30 exams, 30 centres, 20 candidates, ~5000 slots, ~40 bookings; idempotent)
- [x] Performance benchmark suite — Slice 5 (`mix guildford_vue.bench.booking` joins the existing broadcast bench)
- [x] HIBP real adapter (Sprint 11.5 deferral) — Slice 3 (k-anonymity over Req)
- [x] Bandit slow-body limits (Sprint 11.5 deferral) — Slice 7 (`config/runtime.exs` http + thousand_island opts)
- [x] Exam-centres async-deadlock remediation (long-standing flake) — Slice 7 (unique admin email; 32/0 × 3 runs)

Sprint 12 closes with setup of the measurement instrument in preparation for the empirical evaluation:
  * Comprehensive seed data (`mix run priv/repo/seeds.exs`)
  * `/metrics` for production telemetry capture
  * `scripts/chaos.exs --all` for the supervision-tree narrative
  * `mix guildford_vue.bench.{broadcast,booking}` for the latency
    numbers
  * `benchmarks/tsung/` for the scalability story
  * `docs/runbook.md` for the operations narrative

---

## Continuous (touch every sprint)

- [ ] Coverage ≥90% line, ≥85% branch (every PR)
- [ ] `mix credo --strict` green
- [ ] `mix dialyzer` no new warnings
- [ ] `mix sobelow --config` clean or accepted
- [ ] axe-core zero violations on any new UI
- [ ] Lighthouse ≥90 on any new candidate-facing route
- [ ] Secret scan clean (commit + CI + build + deploy gates)

---


