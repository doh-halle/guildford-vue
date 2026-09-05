# Comprehensive seed data (Sprint 12 Slice 1).
#
# Idempotent: re-runs reuse existing records by email / code. Safe to
# run repeatedly against the same dev DB.
#
#     mix run priv/repo/seeds.exs                # full dataset
#     SEED_MIN=1 mix run priv/repo/seeds.exs     # admins + a few centres only
#
# Generates roughly:
#   * 2 admins (admin + superadmin)
#   * 16 exams across 7 categories (curated subset)
#   * 58 production-shaped centres covering UK (every 50-mile
#     radius reaches >= 3 centres) + 5 QA pending centres
#   * Each centre offers 5-15 exams
#   * 60 days × 1-2 sessions/weekday/centre, generated in parallel
#   * 20 sample candidates (PRD §12.5)
#   * ~40 sample bookings sprinkled across slots
#
# Reuses the existing register_* / create_* context functions — no
# direct Repo.insert! so seeded data goes through the full
# validation pipeline.

import Ecto.Query, only: [from: 2]

alias GuildfordVue.{Admins, Bookings, ExamCentres, Exams, Slots}

defmodule Seeder do
  @moduledoc false

  def minimal?, do: System.get_env("SEED_MIN") == "1"

  def banner(text), do: IO.puts(IO.ANSI.format([:bright, "\n=== ", text, :reset]))
  def info(text), do: IO.puts(IO.ANSI.format([:faint, "    ", text, :reset]))
  def ok(text), do: IO.puts(IO.ANSI.format([:green, "  ✓ ", :reset, text]))

  def find_or_register_admin(attrs) do
    case Admins.get_admin_by_email(attrs["email"]) do
      nil ->
        {:ok, a} = Admins.register_admin(attrs)
        a

      a ->
        a
    end
  end

  def find_or_register_candidate(attrs) do
    case GuildfordVue.Candidates.get_candidate_by_email(attrs["email"]) do
      nil ->
        {:ok, c} = GuildfordVue.Candidates.register_candidate(attrs)
        # Mark verified so seeded candidates can log in immediately.
        {:ok, c} =
          c
          |> GuildfordVue.Candidates.Candidate.confirm_email_changeset(DateTime.utc_now())
          |> GuildfordVue.Repo.update()

        c

      c ->
        c
    end
  end

  def find_or_register_centre(attrs) do
    case ExamCentres.get_exam_centre_by_email(attrs["email"]) do
      nil ->
        {:ok, c} = ExamCentres.register_exam_centre(attrs)
        c

      c ->
        c
    end
  end

  def find_or_create_exam(attrs, admin) do
    case Exams.get_exam_by_code(attrs["code"]) do
      nil ->
        {:ok, e} = Exams.create_exam(attrs, admin)
        e

      e ->
        e
    end
  end
end

# =============================================================================
# 1. Admins (PRD §12.5)
# =============================================================================
Seeder.banner("Seeding admins")

_admin =
  Seeder.find_or_register_admin(%{
    "email" => "admin@guildfordvue.test",
    "password" => "supersecret123!A",
    "name" => "Admin",
    "role" => "operator"
  })

Seeder.ok("admin@guildfordvue.test (operator)")

super_admin =
  Seeder.find_or_register_admin(%{
    "email" => "superadmin@guildfordvue.test",
    "password" => "supersecret123!A",
    "name" => "Super Admin",
    "role" => "superadmin"
  })

Seeder.ok("superadmin@guildfordvue.test (superadmin)")

# =============================================================================
# 2. Exams (PRD §12.2)
# =============================================================================
Seeder.banner("Seeding exams")

# Curated 16-exam catalogue spanning 7 categories — driving (2),
# academic (3), IT (5), project/service (2), accounting (1),
# language (2), and finance (1). Anything in the DB with a code NOT
# in this list is archived after seeding so the live catalogue
# matches the seed spec.
exam_specs = [
  # Driving (2)
  %{
    "name" => "DVSA Theory Test (Car)",
    "code" => "DVSA-CAR",
    "certification_body" => "DVSA",
    "duration_minutes" => 57,
    "price_pence" => 2300
  },
  %{
    "name" => "DVSA Hazard Perception",
    "code" => "DVSA-HP",
    "certification_body" => "DVSA",
    "duration_minutes" => 20,
    "price_pence" => 1800
  },

  # Academic (3)
  %{
    "name" => "GCSE Mathematics (Edexcel)",
    "code" => "GCSE-MATH-EDX",
    "certification_body" => "Edexcel",
    "duration_minutes" => 90,
    "price_pence" => 4000
  },
  %{
    "name" => "GCSE English Language (AQA)",
    "code" => "GCSE-ENG-AQA",
    "certification_body" => "AQA",
    "duration_minutes" => 105,
    "price_pence" => 4000
  },
  %{
    "name" => "A-Level Mathematics (OCR)",
    "code" => "AL-MATH-OCR",
    "certification_body" => "OCR",
    "duration_minutes" => 120,
    "price_pence" => 5500
  },

  # IT (5)
  %{
    "name" => "CompTIA A+",
    "code" => "CTA-AP",
    "certification_body" => "CompTIA",
    "duration_minutes" => 90,
    "price_pence" => 22000
  },
  %{
    "name" => "CompTIA Security+",
    "code" => "CTA-SEC",
    "certification_body" => "CompTIA",
    "duration_minutes" => 90,
    "price_pence" => 27000
  },
  %{
    "name" => "Microsoft AZ-104 (Azure Administrator)",
    "code" => "MS-AZ104",
    "certification_body" => "Microsoft",
    "duration_minutes" => 150,
    "price_pence" => 14000
  },
  %{
    "name" => "AWS Certified Solutions Architect — Associate",
    "code" => "AWS-SAA",
    "certification_body" => "AWS",
    "duration_minutes" => 130,
    "price_pence" => 14500
  },
  %{
    "name" => "Cisco CCNA",
    "code" => "CCNA",
    "certification_body" => "Cisco",
    "duration_minutes" => 120,
    "price_pence" => 27000
  },

  # Project & service management (2)
  %{
    "name" => "PRINCE2 Foundation",
    "code" => "P2F",
    "certification_body" => "AXELOS",
    "duration_minutes" => 60,
    "price_pence" => 38000
  },
  %{
    "name" => "ITIL 4 Foundation",
    "code" => "ITIL4F",
    "certification_body" => "AXELOS",
    "duration_minutes" => 60,
    "price_pence" => 33000
  },

  # Accounting (1)
  %{
    "name" => "AAT Level 2",
    "code" => "AAT-L2",
    "certification_body" => "AAT",
    "duration_minutes" => 150,
    "price_pence" => 8500
  },

  # Finance (1)
  %{
    "name" => "CFA Level 1",
    "code" => "CFA-L1",
    "certification_body" => "CFA Institute",
    "duration_minutes" => 270,
    "price_pence" => 73000
  },

  # Language (2)
  %{
    "name" => "IELTS Academic",
    "code" => "IELTS-AC",
    "certification_body" => "British Council",
    "duration_minutes" => 165,
    "price_pence" => 19500
  },
  %{
    "name" => "Cambridge C1 Advanced",
    "code" => "CAM-C1",
    "certification_body" => "Cambridge",
    "duration_minutes" => 235,
    "price_pence" => 19000
  }
]

exams = Enum.map(exam_specs, &Seeder.find_or_create_exam(&1, super_admin))

# Archive any pre-existing exam whose code isn't in the canonical
# 16. Archived exams stay in the DB (their slots remain in place for
# audit completeness) but are filtered out of the search dropdown
# and the candidate-facing /search results — exactly what we want
# after a catalogue trim.
canonical_codes = MapSet.new(exam_specs, & &1["code"])

archived =
  Exams.list_exams(include_archived: false)
  |> Enum.reject(&MapSet.member?(canonical_codes, &1.code))
  |> Enum.map(fn ex ->
    {:ok, archived} = Exams.archive_exam(ex, super_admin)
    archived
  end)

Seeder.ok(
  "#{length(exams)} exams in catalogue" <>
    if(archived == [], do: "", else: " (archived #{length(archived)} non-canonical)")
)

# =============================================================================
# 3. Exam centres (PRD §12.1 + §12.3)
# =============================================================================
Seeder.banner("Seeding exam centres")

centre_specs = [
  # London
  {"London Bridge Assessment Centre", "ec1@centres.guildfordvue.test", "55 Old Broad Street",
   "London", "EC1A 1BB"},
  {"London City Assessment Hub", "e1@centres.guildfordvue.test", "1 Aldgate", "London", "E1 6AN"},
  {"Westminster Examination Centre", "sw1@centres.guildfordvue.test", "10 Victoria Street",
   "London", "SW1A 1AA"},
  {"Islington Test Hub", "n1@centres.guildfordvue.test", "Angel Square", "London", "N1 9GU"},
  {"Marylebone Examination Hub", "w1@centres.guildfordvue.test", "Wigmore Street", "London",
   "W1A 1AB"},

  # Manchester
  {"Manchester Examination Hub", "m1@centres.guildfordvue.test", "Piccadilly Place", "Manchester",
   "M1 1AE"},
  {"Manchester Spinningfields Tests", "m2@centres.guildfordvue.test", "Hardman Square",
   "Manchester", "M2 3WS"},
  {"Manchester Northern Quarter Hub", "m4@centres.guildfordvue.test", "Stevenson Square",
   "Manchester", "M4 1DH"},

  # Birmingham
  {"Birmingham Central Test Centre", "b1@centres.guildfordvue.test", "Centenary Square",
   "Birmingham", "B1 1AA"},
  {"Birmingham Jewellery Quarter Centre", "b2@centres.guildfordvue.test", "Vyse Street",
   "Birmingham", "B2 4BS"},
  {"Birmingham Eastside Centre", "b3@centres.guildfordvue.test", "Curzon Street", "Birmingham",
   "B3 3HN"},

  # Leeds
  {"Leeds City Examination Centre", "ls1@centres.guildfordvue.test", "1 Briggate", "Leeds",
   "LS1 1UR"},
  {"Leeds Headingley Test Centre", "ls6@centres.guildfordvue.test", "Otley Road", "Leeds",
   "LS6 1JL"},

  # Glasgow
  {"Glasgow Central Assessment Hub", "g1@centres.guildfordvue.test", "Buchanan Street", "Glasgow",
   "G1 1XQ"},
  {"Glasgow West End Test Centre", "g3@centres.guildfordvue.test", "Byres Road", "Glasgow",
   "G3 7DN"},

  # Edinburgh
  {"Edinburgh Test Centre — George Street", "eh1@centres.guildfordvue.test", "84 George Street",
   "Edinburgh", "EH1 1YZ"},
  {"Edinburgh New Town Examination Hub", "eh2@centres.guildfordvue.test", "Princes Street",
   "Edinburgh", "EH2 2AD"},

  # Cardiff
  {"Cardiff Bay Test Centre", "cf10@centres.guildfordvue.test", "Mermaid Quay", "Cardiff",
   "CF10 1EP"},
  {"Cardiff Central Examination Hub", "cf11@centres.guildfordvue.test", "St Mary Street",
   "Cardiff", "CF11 9HW"},

  # Bristol
  {"Bristol Harbourside Test Centre", "bs1@centres.guildfordvue.test", "Wapping Wharf", "Bristol",
   "BS1 4DJ"},
  {"Bristol Clifton Assessment Centre", "bs8@centres.guildfordvue.test", "Whiteladies Road",
   "Bristol", "BS8 1TH"},

  # Liverpool
  {"Liverpool Waterfront Test Centre", "l1@centres.guildfordvue.test", "Albert Dock", "Liverpool",
   "L1 8JQ"},
  {"Liverpool Knowledge Quarter Hub", "l3@centres.guildfordvue.test", "Pembroke Place",
   "Liverpool", "L3 5UX"},

  # Sheffield
  {"Sheffield City Centre Test Hub", "s1@centres.guildfordvue.test", "Fargate", "Sheffield",
   "S1 2HE"},
  {"Sheffield Kelham Island Centre", "s3@centres.guildfordvue.test", "Alma Street", "Sheffield",
   "S3 7HG"},

  # Newcastle
  {"Newcastle Quayside Test Centre", "ne1@centres.guildfordvue.test", "Sandhill", "Newcastle",
   "NE1 4ST"},
  {"Newcastle Jesmond Examination Hub", "ne2@centres.guildfordvue.test", "Osborne Road",
   "Newcastle", "NE2 4PT"},

  # Nottingham
  {"Nottingham Lace Market Centre", "ng1@centres.guildfordvue.test", "Stoney Street",
   "Nottingham", "NG1 5FS"},

  # Guildford (project name homage)
  {"Guildford High Street Assessment Centre", "gu1@centres.guildfordvue.test", "High Street",
   "Guildford", "GU1 4LZ"},
  {"University of Surrey Test Centre", "gu2@centres.guildfordvue.test", "Stag Hill", "Guildford",
   "GU2 7XH"},

  # ---------------------------------------------------------------------------
  # Expanded coverage — added so every 50-mile radius across the UK
  # has at least 3 reachable centres. Picked by population centre and
  # geographic gap-filling rather than commercial density.
  # ---------------------------------------------------------------------------

  # Scotland — north / east / south fill
  {"Aberdeen City Test Centre", "ab10@centres.guildfordvue.test", "Union Street", "Aberdeen",
   "AB10 1AB"},
  {"Dundee Riverside Test Centre", "dd1@centres.guildfordvue.test", "Riverside Drive", "Dundee",
   "DD1 1HP"},
  {"Inverness Highland Hub", "iv1@centres.guildfordvue.test", "Academy Street", "Inverness",
   "IV1 1NB"},
  {"Dumfries Borders Test Centre", "dg1@centres.guildfordvue.test", "High Street", "Dumfries",
   "DG1 2RW"},

  # North-East England
  {"Sunderland Coast Test Centre", "sr1@centres.guildfordvue.test", "St Thomas Street",
   "Sunderland", "SR1 3DN"},
  {"Middlesbrough Tees Test Centre", "ts1@centres.guildfordvue.test", "Albert Road",
   "Middlesbrough", "TS1 4DA"},

  # Cumbria / North-West fill
  {"Carlisle Cumbria Test Centre", "ca1@centres.guildfordvue.test", "Castle Street", "Carlisle",
   "CA1 1QE"},
  {"Lancaster City Test Centre", "la1@centres.guildfordvue.test", "Penny Street", "Lancaster",
   "LA1 1HE"},
  {"Preston Central Test Centre", "pr1@centres.guildfordvue.test", "Fishergate", "Preston",
   "PR1 2HT"},

  # Yorkshire / Humber fill
  {"Hull Quayside Test Centre", "hu1@centres.guildfordvue.test", "Queen Street", "Hull",
   "HU1 2AA"},
  {"York Minster Test Centre", "yo1@centres.guildfordvue.test", "Stonegate", "York", "YO1 7HH"},

  # East Midlands fill
  {"Leicester Cathedral Test Centre", "le1@centres.guildfordvue.test", "Cathedral Lane",
   "Leicester", "LE1 5PZ"},
  {"Lincoln Cathedral Test Centre", "ln1@centres.guildfordvue.test", "Bailgate", "Lincoln",
   "LN1 3AA"},

  # West Midlands fill
  {"Coventry Cathedral Test Centre", "cv1@centres.guildfordvue.test", "Priory Street", "Coventry",
   "CV1 5RB"},
  {"Stoke-on-Trent Cultural Centre", "st1@centres.guildfordvue.test", "Bethesda Street",
   "Stoke-on-Trent", "ST1 1JD"},

  # Wales — south + north fill
  {"Swansea Maritime Test Centre", "sa1@centres.guildfordvue.test", "Wind Street", "Swansea",
   "SA1 5LF"},
  {"Bangor University Test Centre", "ll57@centres.guildfordvue.test", "College Road", "Bangor",
   "LL57 2RB"},

  # Northern Ireland
  {"Belfast Titanic Test Centre", "bt1@centres.guildfordvue.test", "Donegall Square", "Belfast",
   "BT1 5GS"},
  {"Derry Walled City Test Centre", "bt48@centres.guildfordvue.test", "Strand Road", "Derry",
   "BT48 7BN"},

  # East Anglia
  {"Cambridge Market Square Centre", "cb2@centres.guildfordvue.test", "Market Hill", "Cambridge",
   "CB2 3ER"},
  {"Norwich Cathedral Test Centre", "nr1@centres.guildfordvue.test", "Tombland", "Norwich",
   "NR1 3DH"},

  # South West fill
  {"Bath Spa Test Centre", "ba1@centres.guildfordvue.test", "Stall Street", "Bath", "BA1 1LZ"},
  {"Exeter Cathedral Test Centre", "ex1@centres.guildfordvue.test", "Cathedral Yard", "Exeter",
   "EX1 1HS"},
  {"Plymouth Hoe Test Centre", "pl1@centres.guildfordvue.test", "Royal Parade", "Plymouth",
   "PL1 1HZ"},

  # South / South East fill
  {"Southampton City Test Centre", "so14@centres.guildfordvue.test", "Above Bar Street",
   "Southampton", "SO14 7DU"},
  {"Portsmouth Spinnaker Test Centre", "po1@centres.guildfordvue.test", "Gunwharf Quays",
   "Portsmouth", "PO1 3TZ"},
  {"Oxford Cornmarket Test Centre", "ox1@centres.guildfordvue.test", "Cornmarket Street",
   "Oxford", "OX1 3HF"},
  {"Brighton Pier Test Centre", "bn1@centres.guildfordvue.test", "Brighton Pier", "Brighton",
   "BN1 1RG"}
]

# Five clearly-labelled QA-only centres, kept separate so manual UAT can target
# them without polluting the production-shaped reference dataset above. These
# are always seeded — even under SEED_MIN=1 — because they're the focus of
# manual exploratory testing.
test_centre_specs = [
  {"Trafalgar Test Centre (London)", "qa1@centres.guildfordvue.test", "Trafalgar Square",
   "London", "WC2N 5DU"},
  {"Deansgate Test Centre (Manchester)", "qa2@centres.guildfordvue.test", "Deansgate",
   "Manchester", "M3 4LY"},
  {"Snow Hill Test Centre (Birmingham)", "qa3@centres.guildfordvue.test", "Hurst Street",
   "Birmingham", "B5 5JR"},
  {"Ashford Test Centre (Middlesex)", "qa4@centres.guildfordvue.test", "Lothian Road",
   "Middlesex", "TW15 2PX"},
  {"North Guildford Test Centre (Guildford)", "qa5@centres.guildfordvue.test", "Bridge Street",
   "Guildford", "GU7 1NJ"}
]

centre_specs =
  if Seeder.minimal?(),
    do: Enum.take(centre_specs, 3) ++ test_centre_specs,
    else: centre_specs ++ test_centre_specs

centres =
  Enum.map(centre_specs, fn {name, email, addr1, city, postcode} ->
    centre =
      Seeder.find_or_register_centre(%{
        "email" => email,
        "password" => "supersecret123!A",
        "name" => name,
        "address_line_1" => addr1,
        "city" => city,
        "postcode" => postcode
      })

    # QA test centres (qa1..qa5) are left in :pending status so the
    # admin Pending-Centres queue at /backoffice/centres has rows to
    # demonstrate the review/approve/reject workflow during UAT.
    # Production-shaped centres are auto-approved so search results
    # work immediately out of the box.
    cond do
      String.starts_with?(email, "qa") ->
        centre

      centre.status == "approved" ->
        centre

      true ->
        {:ok, approved} = ExamCentres.approve(centre, super_admin)
        approved
    end
  end)

qa_pending_count = Enum.count(centres, &String.starts_with?(&1.email, "qa"))

Seeder.ok(
  "#{length(centres)} centres seeded " <>
    "(#{length(centres) - qa_pending_count} approved, " <>
    "#{qa_pending_count} pending for UAT review)"
)

# =============================================================================
# 4. Centre offerings — each centre picks 5–15 exams
# =============================================================================
Seeder.banner("Wiring centre offerings")

Enum.each(centres, fn centre ->
  count = Enum.random(5..min(15, length(exams)))
  offerings = exams |> Enum.take_random(count) |> Enum.map(& &1.id)
  {:ok, _} = ExamCentres.set_offerings(centre, offerings, super_admin)
end)

Seeder.ok("offerings wired for #{length(centres)} centres")

# =============================================================================
# 5. Slots — next 60 days, weekdays, 1-2 sessions/day, generated
#    per-centre in parallel.
#
# Per-centre slot generation is independent (each centre has its own
# GenServer mailbox that serialises its own slot writes), so we
# Task.async_stream across centres. Cap concurrency at the BEAM's
# scheduler count to stay well within the Postgres pool.
# =============================================================================
Seeder.banner("Seeding slots (next 60 days, parallel)")

today = Date.utc_today()
days_range = if Seeder.minimal?(), do: 0..7, else: 0..59

build_slot_attrs = fn centre, offered_ids ->
  # Each centre gets a deterministic-ish per-centre session pattern
  # so re-runs produce comparable density.
  sessions = if :rand.uniform(2) == 1, do: [{10, 0}, {14, 0}], else: [{11, 0}]

  for day_offset <- days_range,
      date = Date.add(today, day_offset),
      Date.day_of_week(date) <= 5,
      offered_ids != [],
      {h, m} <- sessions do
    exam_id = Enum.random(offered_ids)
    {:ok, starts_at} = DateTime.new(date, Time.new!(h, m, 0), "Etc/UTC")
    ends_at = DateTime.add(starts_at, 90 * 60, :second)

    {centre,
     %{
       "exam_id" => exam_id,
       "starts_at" => starts_at,
       "ends_at" => ends_at,
       "capacity" => Enum.random(8..24)
     }}
  end
end

# Skip slot generation for centres that already have slots — keeps
# the seed idempotent and avoids slot duplication on repeated runs.
slot_targets =
  centres
  |> Enum.filter(fn c ->
    GuildfordVue.Repo.aggregate(
      from(s in GuildfordVue.Slots.Slot, where: s.exam_centre_id == ^c.id),
      :count,
      :id
    ) == 0
  end)
  |> Enum.flat_map(fn centre ->
    offered_ids = centre |> ExamCentres.list_offerings() |> Enum.map(& &1.id)
    build_slot_attrs.(centre, offered_ids)
  end)

slot_count =
  slot_targets
  |> Task.async_stream(
    fn {centre, attrs} ->
      case Slots.create_slot(centre, attrs) do
        {:ok, _} -> 1
        {:error, _} -> 0
      end
    end,
    max_concurrency: System.schedulers_online(),
    ordered: false,
    timeout: 30_000
  )
  |> Enum.reduce(0, fn
    {:ok, n}, acc -> acc + n
    _, acc -> acc
  end)

Seeder.ok("#{slot_count} new slots created")

# =============================================================================
# 6. Sample candidates (PRD §12.5)
# =============================================================================
Seeder.banner("Seeding sample candidates")

candidate_specs = [
  {"Alice", "Smith", "alice.smith@example.test", "SW1A 1AA"},
  {"Bob", "Jones", "bob.jones@example.test", "M1 1AE"},
  {"Charlie", "Williams", "charlie.williams@example.test", "B1 1AA"},
  {"Daisy", "Brown", "daisy.brown@example.test", "LS1 1UR"},
  {"Edward", "Davies", "edward.davies@example.test", "G1 1XQ"},
  {"Faye", "Miller", "faye.miller@example.test", "EH1 1YZ"},
  {"George", "Wilson", "george.wilson@example.test", "CF10 1EP"},
  {"Hannah", "Moore", "hannah.moore@example.test", "BS1 4DJ"},
  {"Iris", "Taylor", "iris.taylor@example.test", "L1 8JQ"},
  {"James", "Anderson", "james.anderson@example.test", "S1 2HE"},
  {"Katie", "Thomas", "katie.thomas@example.test", "NE1 4ST"},
  {"Liam", "Jackson", "liam.jackson@example.test", "NG1 5FS"},
  {"Mia", "White", "mia.white@example.test", "GU1 4LZ"},
  {"Noah", "Harris", "noah.harris@example.test", "M2 3WS"},
  {"Olivia", "Martin", "olivia.martin@example.test", "B2 4BS"},
  {"Pete", "Thompson", "pete.thompson@example.test", "LS6 1JL"},
  {"Quinn", "Garcia", "quinn.garcia@example.test", "G3 7DN"},
  {"Ruth", "Robinson", "ruth.robinson@example.test", "EH2 2AD"},
  {"Sam", "Lewis", "sam.lewis@example.test", "CF11 9HW"},
  {"Tara", "Walker", "tara.walker@example.test", "BS8 1TH"}
]

candidate_specs =
  if Seeder.minimal?(), do: Enum.take(candidate_specs, 3), else: candidate_specs

candidates =
  Enum.map(candidate_specs, fn {first, last, email, postcode} ->
    Seeder.find_or_register_candidate(%{
      "email" => email,
      "password" => "supersecret123!A",
      "first_name" => first,
      "last_name" => last,
      "postcode" => postcode
    })
  end)

Seeder.ok("#{length(candidates)} sample candidates")

# =============================================================================
# 7. Sample bookings — sprinkle 30-40 across the slots
# =============================================================================
Seeder.banner("Seeding sample bookings")

all_slots =
  GuildfordVue.Repo.all(GuildfordVue.Slots.Slot)
  |> Enum.filter(&(DateTime.compare(&1.starts_at, DateTime.utc_now()) == :gt))

booking_target = if Seeder.minimal?(), do: 5, else: 40

booking_count =
  candidates
  |> Stream.cycle()
  |> Enum.zip(Enum.take_random(all_slots, min(booking_target, length(all_slots))))
  |> Enum.reduce(0, fn {candidate, slot}, acc ->
    _ = GuildfordVue.Centres.ensure_started(slot.exam_centre_id)

    case Bookings.create_booking(candidate, slot) do
      {:ok, _booking} -> acc + 1
      {:error, _stage, _reason} -> acc
    end
  end)

Seeder.ok("#{booking_count} bookings created")

# =============================================================================
# Summary
# =============================================================================
Seeder.banner("Done — PRD §12 reference dataset ready")
Seeder.info("admins:     #{length(Admins.list_admins())}")
Seeder.info("exams:      #{length(exams)}")
Seeder.info("centres:    #{length(centres)}")
Seeder.info("candidates: #{length(candidates)}")
Seeder.info("slots:      #{slot_count}")
Seeder.info("bookings:   #{booking_count}")
IO.puts("")
