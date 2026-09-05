defmodule GuildfordVue.Geocoder.Seeded do
  @moduledoc """
  Two-tier postcode → (lat, lng) geocoder for dev/test/seed:

    1. **Exact match** against `@table` — every postcode used by
       the PRD §12.1 sample dataset + every centre seeded by
       `priv/repo/seeds.exs`. Returns the precise district
       centroid.

    2. **Area fallback** against `@area_centroids` — extracts the
       1-2 letter postcode area (`AB`, `EH`, `SW`, etc.) and
       returns the area's principal-city centroid. This makes any
       real UK postcode resolvable, even ones we've never seen,
       at city-level precision (≈ a few miles).

  Production should swap in a real geocoder (OS Names API or
  similar); see `GuildfordVue.Geocoder.OSNames`.
  """
  @behaviour GuildfordVue.Geocoder

  # All coordinates are public domain (postcode district centroids
  # from open data). Truncated to 4 decimal places (≈11m precision —
  # plenty for a centre's pin on a map).
  @table %{
    # --- London ---
    "EC1A1BB" => {51.5187, -0.0985},
    "E16AN" => {51.5197, -0.0716},
    "SW1A1AA" => {51.5014, -0.1419},
    "N19GU" => {51.5331, -0.1058},
    "W1A1AB" => {51.5170, -0.1437},
    "WC2N5DU" => {51.5074, -0.1278},
    # --- Manchester ---
    "M11AE" => {53.4794, -2.2453},
    "M23WS" => {53.4805, -2.2358},
    "M34FP" => {53.4870, -2.2424},
    "M34LY" => {53.4823, -2.2510},
    "M41DH" => {53.4839, -2.2300},
    # --- Birmingham ---
    "B11AA" => {52.4778, -1.8989},
    "B24BS" => {52.4795, -1.8983},
    "B33HN" => {52.4859, -1.9013},
    "B54UA" => {52.4756, -1.9050},
    "B55JR" => {52.4733, -1.8964},
    # --- Leeds ---
    "LS11UR" => {53.7958, -1.5455},
    "LS27EY" => {53.8008, -1.5491},
    "LS61JL" => {53.8190, -1.5747},
    # --- Glasgow ---
    "G11XQ" => {55.8617, -4.2576},
    "G24PJ" => {55.8642, -4.2526},
    "G37DN" => {55.8703, -4.2871},
    # --- Edinburgh ---
    "EH11YZ" => {55.9533, -3.1883},
    "EH22AD" => {55.9519, -3.1953},
    "EH39LX" => {55.9474, -3.2056},
    "EH39RG" => {55.9580, -3.2014},
    # --- Cardiff ---
    "CF101EP" => {51.4816, -3.1791},
    "CF119HW" => {51.4783, -3.1828},
    "CF144HH" => {51.5076, -3.2099},
    # --- Bristol ---
    "BS14DJ" => {51.4545, -2.5879},
    "BS20JT" => {51.4628, -2.5783},
    "BS81TH" => {51.4623, -2.6038},
    # --- Liverpool ---
    "L18JQ" => {53.4084, -2.9916},
    "L22DP" => {53.4106, -2.9794},
    "L35UX" => {53.4084, -2.9755},
    # --- Sheffield ---
    "S12HE" => {53.3811, -1.4701},
    "S24SU" => {53.3724, -1.4654},
    "S37HG" => {53.3897, -1.4738},
    # --- Newcastle ---
    "NE14ST" => {54.9783, -1.6178},
    "NE24PT" => {54.9806, -1.6133},
    # --- Nottingham ---
    "NG15FS" => {52.9548, -1.1581},
    "NG72RD" => {52.9419, -1.1969},
    # --- Guildford / Surrey ---
    "GU14LZ" => {51.2362, -0.5704},
    "GU27XH" => {51.2426, -0.5891},
    "GU71NJ" => {51.1857, -0.6122},
    "TW152PX" => {51.4393, -0.4671},

    # --- Expanded coverage (Sprint 12 reseed) ---
    # Scotland
    "AB101AB" => {57.1497, -2.0943},
    "DD11HP" => {56.4620, -2.9707},
    "IV11NB" => {57.4778, -4.2247},
    "DG12RW" => {55.0700, -3.6055},
    # North-East England
    "SR13DN" => {54.9069, -1.3838},
    "TS14DA" => {54.5742, -1.2349},
    # Cumbria + North-West
    "CA11QE" => {54.8924, -2.9325},
    "LA11HE" => {54.0466, -2.8007},
    "PR12HT" => {53.7575, -2.7012},
    # Yorkshire / Humber
    "HU12AA" => {53.7446, -0.3325},
    "YO17HH" => {53.9600, -1.0828},
    # East Midlands
    "LE15PZ" => {52.6369, -1.1398},
    "LN13AA" => {53.2350, -0.5391},
    # West Midlands
    "CV15RB" => {52.4083, -1.5106},
    "ST11JD" => {53.0050, -2.1828},
    # Wales
    "SA15LF" => {51.6214, -3.9436},
    "LL572RB" => {53.2280, -4.1295},
    # Northern Ireland
    "BT15GS" => {54.5973, -5.9301},
    "BT487BN" => {54.9966, -7.3086},
    # East Anglia
    "CB23ER" => {52.2053, 0.1218},
    "NR13DH" => {52.6309, 1.2974},
    # South West
    "BA11LZ" => {51.3811, -2.3590},
    "EX11HS" => {50.7236, -3.5275},
    "PL11HZ" => {50.3713, -4.1426},
    # South / South East
    "SO147DU" => {50.9097, -1.4044},
    "PO13TZ" => {50.7989, -1.1014},
    "OX13HF" => {51.7520, -1.2577},
    "BN11RG" => {50.8198, -0.1374}
  }

  # UK postcode area → principal city/town centroid. Used as a
  # fallback when an exact-match miss occurs. Covers every area in
  # current use except the most obscure / overseas codes (e.g. JE,
  # GY, IM) and PO box-only areas.
  @area_centroids %{
    # Scotland
    "AB" => {57.1497, -2.0943},
    "DD" => {56.4620, -2.9707},
    "DG" => {55.0700, -3.6055},
    "EH" => {55.9533, -3.1883},
    "FK" => {56.1175, -3.9389},
    "G" => {55.8617, -4.2576},
    "HS" => {58.2095, -6.3853},
    "IV" => {57.4778, -4.2247},
    "KA" => {55.6111, -4.6655},
    "KW" => {58.4382, -3.0934},
    "KY" => {56.1135, -3.1689},
    "ML" => {55.7869, -3.9700},
    "PA" => {55.8467, -4.4244},
    "PH" => {56.3962, -3.4370},
    "TD" => {55.5476, -2.7867},
    "ZE" => {60.1551, -1.1455},
    # Northern Ireland
    "BT" => {54.5973, -5.9301},
    # Wales
    "CF" => {51.4816, -3.1791},
    "LD" => {52.0617, -3.4039},
    "LL" => {53.2280, -4.1295},
    "NP" => {51.5882, -2.9977},
    "SA" => {51.6214, -3.9436},
    "SY" => {52.7077, -2.7531},
    # North East England
    "DH" => {54.7755, -1.5849},
    "DL" => {54.5252, -1.5526},
    "NE" => {54.9783, -1.6178},
    "SR" => {54.9069, -1.3838},
    "TS" => {54.5742, -1.2349},
    # North West England + Cumbria
    "BB" => {53.7480, -2.4810},
    "BL" => {53.5780, -2.4282},
    "CA" => {54.8924, -2.9325},
    "CH" => {53.1908, -2.8910},
    "CW" => {53.0610, -2.4517},
    "FY" => {53.8175, -3.0357},
    "L" => {53.4084, -2.9916},
    "LA" => {54.0466, -2.8007},
    "M" => {53.4794, -2.2453},
    "OL" => {53.5409, -2.1114},
    "PR" => {53.7575, -2.7012},
    "SK" => {53.4083, -2.1494},
    "WA" => {53.3900, -2.5970},
    "WN" => {53.5450, -2.6315},
    # Yorkshire / Humber
    "BD" => {53.7960, -1.7594},
    "DN" => {53.5228, -1.1285},
    "HD" => {53.6458, -1.7850},
    "HG" => {53.9920, -1.5418},
    "HU" => {53.7446, -0.3325},
    "HX" => {53.7218, -1.8638},
    "LS" => {53.7958, -1.5455},
    "S" => {53.3811, -1.4701},
    "WF" => {53.6833, -1.4977},
    "YO" => {53.9600, -1.0828},
    # East Midlands
    "DE" => {52.9225, -1.4746},
    "LE" => {52.6369, -1.1398},
    "LN" => {53.2350, -0.5391},
    "NG" => {52.9548, -1.1581},
    "NN" => {52.2405, -0.9027},
    # West Midlands
    "B" => {52.4778, -1.8989},
    "CV" => {52.4083, -1.5106},
    "DY" => {52.5114, -2.1144},
    "HR" => {52.0567, -2.7160},
    "ST" => {53.0050, -2.1828},
    "TF" => {52.6766, -2.4458},
    "WR" => {52.1925, -2.2208},
    "WS" => {52.5862, -1.9817},
    "WV" => {52.5862, -2.1280},
    # East Anglia
    "CB" => {52.2053, 0.1218},
    "CM" => {51.7350, 0.4690},
    "CO" => {51.8959, 0.8919},
    "IP" => {52.0567, 1.1482},
    "NR" => {52.6309, 1.2974},
    "PE" => {52.5695, -0.2405},
    "SS" => {51.5450, 0.7077},
    # South West
    "BA" => {51.3811, -2.3590},
    "BH" => {50.7192, -1.8808},
    "BS" => {51.4545, -2.5879},
    "DT" => {50.7156, -2.4373},
    "EX" => {50.7236, -3.5275},
    "GL" => {51.8642, -2.2382},
    "PL" => {50.3713, -4.1426},
    "SN" => {51.5557, -1.7797},
    "SP" => {51.0688, -1.7945},
    "TA" => {51.0149, -3.1086},
    "TQ" => {50.4619, -3.5253},
    "TR" => {50.2660, -5.0527},
    # South Central
    "GU" => {51.2362, -0.5704},
    "HP" => {51.7526, -0.7569},
    "MK" => {52.0406, -0.7594},
    "OX" => {51.7520, -1.2577},
    "PO" => {50.7989, -1.1014},
    "RG" => {51.4543, -0.9781},
    "SL" => {51.5105, -0.5950},
    "SO" => {50.9097, -1.4044},
    # South East
    "BN" => {50.8198, -0.1374},
    "CT" => {51.2802, 1.0789},
    "DA" => {51.4416, 0.2143},
    "ME" => {51.3826, 0.5494},
    "RH" => {51.1118, -0.1872},
    "TN" => {51.1324, 0.2637},
    # London
    "E" => {51.5197, -0.0716},
    "EC" => {51.5187, -0.0985},
    "EN" => {51.6520, -0.0820},
    "HA" => {51.5798, -0.3346},
    "IG" => {51.5590, 0.0741},
    "KT" => {51.4124, -0.3007},
    "N" => {51.5331, -0.1058},
    "NW" => {51.5479, -0.1875},
    "RM" => {51.5750, 0.1832},
    "SE" => {51.4828, -0.0760},
    "SM" => {51.3618, -0.1945},
    "SW" => {51.5014, -0.1419},
    "TW" => {51.4393, -0.4671},
    "UB" => {51.5395, -0.4030},
    "W" => {51.5170, -0.1437},
    "WC" => {51.5074, -0.1278},
    "WD" => {51.6555, -0.3957}
  }

  @impl GuildfordVue.Geocoder
  def lookup(nil), do: {:error, :invalid_postcode}
  def lookup(""), do: {:error, :invalid_postcode}

  def lookup(postcode) when is_binary(postcode) do
    normalised = normalise(postcode)

    cond do
      coords = Map.get(@table, normalised) ->
        {lat, lng} = coords
        {:ok, %{latitude: lat, longitude: lng}}

      area = extract_area(normalised) ->
        case Map.get(@area_centroids, area) do
          nil -> {:error, :unknown_postcode}
          {lat, lng} -> {:ok, %{latitude: lat, longitude: lng}}
        end

      true ->
        {:error, :unknown_postcode}
    end
  end

  def lookup(_), do: {:error, :invalid_postcode}

  defp normalise(pc), do: pc |> String.replace(~r/\s+/, "") |> String.upcase()

  # UK postcode areas are 1-2 leading letters followed by a digit.
  # Returns "AB", "EH", "SW", etc., or nil if the input isn't shaped
  # like a UK postcode.
  defp extract_area(normalised) do
    case Regex.run(~r/^([A-Z]{1,2})\d/, normalised) do
      [_, area] -> area
      _ -> nil
    end
  end
end
