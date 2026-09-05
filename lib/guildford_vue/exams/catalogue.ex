defmodule GuildfordVue.Exams.Catalogue do
  @moduledoc """
  The UK exam catalogue from PRD §12.2 — a realistic mix of academic,
  professional, and certification exams. The list is hardcoded here
  rather than read from a CSV so it travels with the codebase and
  diffs are auditable in git.

  `seed_catalogue/0` is the runtime entry point. The Mix task
  `mix guildford_vue.seed.exams` is a thin shell over it. Idempotent:
  re-running skips codes that already exist instead of erroring.
  """

  alias GuildfordVue.Admins
  alias GuildfordVue.Exams

  @type entry :: %{
          code: String.t(),
          name: String.t(),
          certification_body: String.t(),
          description: String.t(),
          duration_minutes: pos_integer(),
          price_pence: non_neg_integer()
        }

  @spec uk_catalogue() :: [entry()]
  def uk_catalogue do
    [
      # --- Driving & transport ---
      e("DVSA-CAR", "DVSA Theory Test (Car)", "DVSA", 57, 2300, "UK car driver theory test."),
      e(
        "DVSA-MOTO",
        "DVSA Theory Test (Motorcycle)",
        "DVSA",
        57,
        2300,
        "UK motorcycle theory test."
      ),
      e("DVSA-HPT", "DVSA Hazard Perception", "DVSA", 20, 1100, "Hazard perception module."),
      e("CPC-MOD2", "CPC Driver Module 2", "DVSA", 90, 2600, "Driver CPC case studies."),

      # --- Academic ---
      e(
        "GCSE-MATH-EDX",
        "GCSE Mathematics (Edexcel)",
        "Edexcel",
        90,
        4400,
        "Foundation/higher tier exam."
      ),
      e(
        "GCSE-ENG-AQA",
        "GCSE English Language (AQA)",
        "AQA",
        105,
        4400,
        "English language GCSE."
      ),
      e("AL-MATH-OCR", "A-Level Mathematics (OCR)", "OCR", 120, 5300, "A-Level mathematics."),
      e(
        "AL-CS-AQA",
        "A-Level Computer Science (AQA)",
        "AQA",
        150,
        5300,
        "A-Level computer science."
      ),

      # --- IT certifications ---
      e("COMP-AP", "CompTIA A+", "CompTIA", 90, 19_500, "Core IT support certification."),
      e("COMP-NP", "CompTIA Network+", "CompTIA", 90, 23_000, "Foundational networking."),
      e("COMP-SP", "CompTIA Security+", "CompTIA", 90, 25_400, "Foundational security."),
      e(
        "AZ-104",
        "Microsoft AZ-104 (Azure Administrator)",
        "Microsoft",
        120,
        13_500,
        "Azure admin."
      ),
      e("AZ-204", "Microsoft AZ-204 (Azure Developer)", "Microsoft", 120, 13_500, "Azure dev."),
      e(
        "AWS-SAA",
        "AWS Certified Solutions Architect — Associate",
        "AWS",
        130,
        12_000,
        "AWS solutions architect."
      ),
      e("CISCO-CCNA", "Cisco CCNA", "Cisco", 120, 24_000, "Routing & switching."),
      e("CISCO-CCNP", "Cisco CCNP", "Cisco", 120, 32_000, "Professional networking."),

      # --- Project & service management ---
      e(
        "PR2-FOUND",
        "PRINCE2 Foundation",
        "AXELOS",
        60,
        47_000,
        "Project management foundations."
      ),
      e(
        "PR2-PRACT",
        "PRINCE2 Practitioner",
        "AXELOS",
        150,
        58_000,
        "PRINCE2 practitioner."
      ),
      e(
        "ITIL4-FOUND",
        "ITIL 4 Foundation",
        "AXELOS",
        60,
        39_000,
        "Service management foundation."
      ),
      e("PMI-PMP", "PMI PMP", "PMI", 230, 55_500, "Project management professional."),
      e("AGILE-SCRUM", "Agile Scrum Master", "Scrum.org", 60, 17_500, "Scrum mastery."),

      # --- Accounting & finance ---
      e("AAT-L2", "AAT Level 2", "AAT", 120, 8500, "Bookkeeping foundations."),
      e("AAT-L3", "AAT Level 3", "AAT", 150, 12_000, "Advanced bookkeeping."),
      e("ACCA-AS", "ACCA Applied Skills", "ACCA", 180, 13_000, "Applied skills exam."),
      e("CIMA-OP", "CIMA Operational", "CIMA", 90, 11_500, "Operational case."),
      e(
        "CFA-L1",
        "CFA Level 1",
        "CFA Institute",
        270,
        78_000,
        "Level 1 chartered financial analyst."
      ),

      # --- Language ---
      e(
        "IELTS-AC",
        "IELTS Academic",
        "British Council",
        165,
        19_500,
        "Academic English proficiency."
      ),
      e("TOEFL-IBT", "TOEFL iBT", "ETS", 180, 17_000, "Internet-based English test."),
      e("CAM-C1", "Cambridge C1 Advanced", "Cambridge Assessment", 230, 17_000, "C1 English."),
      e("CAM-C2", "Cambridge C2 Proficiency", "Cambridge Assessment", 240, 18_500, "C2 English.")
    ]
  end

  defp e(code, name, body, mins, pence, desc) do
    %{
      code: code,
      name: name,
      certification_body: body,
      description: desc,
      duration_minutes: mins,
      price_pence: pence
    }
  end

  @doc """
  Inserts every catalogue entry that isn't already present. Returns
  `{inserted_count, skipped_count}`. Uses the first `superadmin`
  found as the audit-log actor (or the first admin if no superadmin
  exists). Refuses to run if there are no admins at all — seed the
  admins first.
  """
  @spec seed_catalogue() :: {non_neg_integer(), non_neg_integer()}
  def seed_catalogue do
    admin = system_actor!()

    Enum.reduce(uk_catalogue(), {0, 0}, fn entry, {ins, skp} ->
      if Exams.get_exam_by_code(entry.code) do
        {ins, skp + 1}
      else
        {:ok, _} = Exams.create_exam(stringify(entry), admin)
        {ins + 1, skp}
      end
    end)
  end

  defp stringify(map) when is_map(map) do
    for {k, v} <- map, into: %{}, do: {to_string(k), v}
  end

  defp system_actor! do
    admins = Admins.list_admins()

    case admins do
      [] ->
        raise "Cannot seed exams: no admins exist. Run `mix guildford_vue.seed.admins` first."

      _ ->
        Enum.find(admins, &(&1.role == "superadmin")) || hd(admins)
    end
  end
end
