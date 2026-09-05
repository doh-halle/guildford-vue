# GuildfordVue

Guildford Vue is a nationwide examination booking and reservation system that enables candidates across the United Kingdom to discover, reserve and pay for professional certification and academic examination slots at accredited test centres. The system serves three user types — candidates, exam centres, and platform administrators.

The application is engineered as a deliberate demonstration of functional programming solutions to the structural limitations of object-oriented web architectures. Every architectural decision — from the per-centre GenServer process model to the railway-oriented booking pipeline, from property-based invariant testing to the functional core/imperative shell separation — exists to make a defensible academic claim about how functional paradigms address modern web development challenges.

The system serves a real product purpose (booking exams) while doubling as the reference implementation for the dissertation's empirical evaluation phase.

## 1. Core Features & Functional Requirements

### 1.1 Authentication & Authorisation

 Each user type has its own registration flow (candidates self-register; centres self-register but require admin approval before going live; admins are created by other admins).

### 1.2 Candidate Experience

- Guest postcode search — enter a UK postcode and an exam type to see a list of centres and indicative availability without registering.
- Interactive map view showing centres within a configurable radius (default 25 miles), with markers colour-coded by availability.
- Date-selectable calendar per centre showing colour-coded slot availability: **green** (more than 5 slots available), **yellow** (1–5 slots remaining), **grey** (fully booked).
- Availability indicators update in real time via Phoenix Channels — when another candidate books a slot, the indicator transitions live across all connected viewers without page refresh.
- Profile management — update personal details, change password, manage notification preferences.

### 1.3 Exam Centre Experience

- Self-service registration including centre name, address, postcode (auto-geocoded to lat/long), contact details, and accreditation evidence upload.
- Centre dashboard with current day's bookings, upcoming schedule, and cancellation requests.
- Slot creation — define exams offered, dates, times, and capacity. Bulk slot creation via recurring schedules (e.g., "every Tuesday and Thursday, 10:00 and 14:00, for the next 12 weeks").
- Slot management — view, edit, or cancel published slots (cancelling a slot triggers candidate notifications and refunds).
- Real-time booking notifications — when a candidate books a slot, the centre's dashboard updates live.
- Centre profile management — update address, contact info, accepted exam types.

### 1.4 Administrator Experience

- Admin dashboard with key metrics: total candidates, total centres, total bookings (today/week/month), revenue simulated, system uptime, p95 latency.
- Centre approval queue — review and approve/reject newly registered centres.
- User management — search, view, suspend, or delete candidate accounts.
- Exam catalogue management — add, edit, archive exam types available platform-wide.
- Audit log viewer — searchable, filterable view of every booking transaction in the system.
- System health panel — live view of OTP supervision tree status, active processes, message queue depths.
- Action buttons: approve centre, suspend user, refund booking, broadcast announcement, force slot cancellation.

### 1.5 Booking Pipeline (Railway-Oriented)

The booking confirmation flow is explicitly implemented as a railway-oriented pipeline using Elixir's `with` construct. Each stage returns `{:ok, result}` or `{:error, reason}`. Any failure causes the remaining stages to be bypassed, and the error is surfaced to the candidate with a meaningful message.

```
Validate Slot Availability
       ↓ {:ok, slot}
Reserve Slot (Atomic via GenServer)
       ↓ {:ok, reservation}
Process Simulated Payment
       ↓ {:ok, payment}
Persist Reservation
       ↓ {:ok, reservation}
Generate Booking Reference & PDF
       ↓ {:ok, pdf_url}
Dispatch Confirmation Email
       ↓ {:ok, email_id}
Broadcast Availability Update via PubSub
       ↓ {:ok, broadcast_id}
Append Event to Audit Log
       ↓ {:ok, audit_id}
                      → Success: confirmation page
                      → Failure at any stage: rollback + error page
```

### 1.6 Payment Simulation

There is no real payment integration. The flow is:

1. Candidate selects a payment method from a list: **Visa**, **Mastercard**, **American Express**, **PayPal**, **Apple Pay**, **Google Pay**.
2. Candidate enters fake card details (validated for format only: 16-digit card number using the Luhn algorithm, MM/YY expiry not in the past, 3-digit CVV).
3. On submission, a loading spinner is shown for a randomised 1.5–3 second interval (simulating gateway processing).
4. The system displays "Payment Successfully Processed" with a simulated transaction reference.
5. The reservation pipeline proceeds.

-  Card number must pass Luhn validation to mimic realistic card validation.
-  A 5% randomised "simulated decline" mode (toggleable in admin settings) for testing failure paths.

### 1.7 Real-Time Availability

- Every connected candidate viewing a centre's availability is subscribed to that centre's PubSub topic.
- When a booking is confirmed, an availability event is published to all subscribers within 500 ms p95.
- Colour transitions (green → yellow → grey) animate smoothly without full re-render.
- When a slot is cancelled (by candidate or centre), the availability event reverses (grey → yellow → green).

### 1.8 PDF Reservation Receipt

- Generated server-side using ChromicPDF or Typst (functional PDF library).
- Branded with the Guildford Vue logo and colour palette.
- Contains: booking reference, candidate full name, exam name and code, exam centre name and full address, date and time, candidate instructions, QR code encoding the booking reference for centre check-in, and a footer with platform contact details.
- Available for download immediately after booking and re-downloadable from the candidate dashboard at any time.

---


## 2. Technical Architecture

### 2.1 High-Level Architecture

The system follows the **functional core, imperative shell** architectural pattern. All business logic — slot availability calculations, state transitions, geo-spatial scoring, booking validation — is implemented as pure functions in the functional core. All side-effectful operations — database persistence, payment processing, email dispatch, PDF generation — are confined to boundary modules in the imperative shell.

### 2.2 Concurrency Architecture

- Each exam centre is represented by a dedicated **GenServer** holding the centre's slot inventory as immutable state.
- Booking requests are routed to the appropriate centre's GenServer, where the mailbox serialises concurrent attempts naturally — no locks required.
- An **OTP supervision tree** monitors all centre GenServers. A crashed GenServer is automatically restarted from its last persisted state snapshot.
- **Phoenix Channels** spawn one BEAM process per connected client for real-time updates.
- **Phoenix PubSub** broadcasts availability events to subscribed clients.

### 2.3 Geo-Spatial Layer

- **PostGIS** extension on PostgreSQL handles spatial indexing and queries.
- Postcode-to-coordinate geocoding via an OS Names API integration (or seeded coordinates for development).
- A supervised pool of geo-spatial query workers (`poolboy` or similar) handles concurrent search requests.

### 2.4 Property-Based Testing

- **StreamData** validates system invariants under exhaustive randomised conditions.
- Core invariants tested: bookings never exceed capacity, double-booking is impossible, cancellation reverses state correctly, availability transitions are deterministic.

### 2.5 Technology Stack


| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.16+ |
| Web framework | Phoenix 1.7+ |
| UI | Phoenix LiveView |
| Styling | Tailwind CSS 3.4+ |
| Database | PostgreSQL 16 with PostGIS |
| Background jobs | Oban |
| Email | Swoosh + Mailgun (dev: Mailcatcher) |
| PDF generation | ChromicPDF |
| Testing | ExUnit + StreamData + Wallaby/Playwright |
| Code quality | Credo + Dialyxir + SonarQube |
| Deployment target | Single VM initially; horizontally scalable via BEAM distribution |

---

## 3. Glossary

| Term | Definition |
|------|------------|
| **BEAM** | The virtual machine on which Erlang and Elixir run. |
| **GenServer** | An OTP behaviour for stateful processes with serialised message handling. |
| **LiveView** | A Phoenix feature for server-rendered, real-time, interactive UI without bespoke JavaScript. |
| **OTP** | Open Telecom Platform — the standard library and conventions for building robust Erlang/Elixir applications. |
| **PubSub** | Publish/subscribe messaging system built into Phoenix. |
| **Railway-Oriented Programming** | An error-handling pattern where multi-step workflows form a two-track railway with success and error tracks. |
| **Supervision tree** | A hierarchy of processes that monitor and restart their children, enabling self-healing systems. |

---

## 4. Test environment setup

### 4.1 One-time bootstrap

```bash
# From the repo root.
cd ~/guildford-vue

# Reset the dev DB to a known-clean state and re-seed the PRD §12
# reference dataset (Sprint 12 Slice 1).
mix ecto.reset                     # drops + creates + migrates
mix run priv/repo/seeds.exs        # full dataset (~30s)
# or:
SEED_MIN=1 mix run priv/repo/seeds.exs   # 3 centres / 3 candidates smoke set

# Start the dev server.
mix phx.server                     # http://localhost:4000
```

### 4.2 Supporting services

| Service | URL | Purpose |
|---------|-----|---------|
| App | http://localhost:4000 | Phoenix endpoint |
| Mailcatcher | http://localhost:1080 | All outbound email (verification, OTP, password reset, booking confirmation) lands here in dev |
| MinIO (if running) | http://localhost:9001 | S3-compatible storage (PDF receipts use on-demand rendering by default, so MinIO is optional) |
| Postgres | localhost:5434 | Dev DB; `postgres/postgres` |

### 4.3 Per-test browser state

For each persona switch, **clear cookies for `localhost:4000`** to
avoid the multi-scope session chip rendering (a candidate + an admin
can coexist in different cookies on the same browser, which is
useful for cross-scope isolation testing but confusing during UAT).

---

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
