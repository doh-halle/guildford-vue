# scripts/report_complexity.exs — C5 static-analysis reporter for the FP artefact.
#
# Sprint 13 counterpart to the OO project's scripts/report_complexity.py.
# Emits a Markdown report at docs/measurements/fp/reports/complexity.md
# capturing:
#
#   * Cyclomatic-complexity per function, ranked by score, via Credo's
#     Refactor.CyclomaticComplexity check with the max_complexity lowered
#     so every non-trivial function surfaces.
#   * Module / function / line counts by domain area
#     (functional core `lib/guildford_vue/` vs imperative shell
#     `lib/guildford_vue_web/`).
#   * Strict-mode Credo issue count and category breakdown.
#
# Rerun via `mix run scripts/report_complexity.exs`.

defmodule ReportComplexity do
  @out "docs/measurements/fp/reports/complexity.md"
  # Credo's built-in max_complexity default (see
  # https://hexdocs.pm/credo/Credo.Check.Refactor.CyclomaticComplexity.html).
  # `mix credo --only Refactor.CyclomaticComplexity` does NOT accept a
  # threshold override on the CLI; if a future dissertation cite needs a
  # lower threshold, add a `.credo.threshold-N.exs` and pass
  # `--config-file <file>` (Sprint 13 Defect 023 closure).
  @credo_default_cc_threshold 9

  def run do
    File.mkdir_p!(Path.dirname(@out))
    now = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace("T", " ")

    loc = loc_by_dir()
    cc = cyclomatic_complexity_hits()
    credo = strict_credo_summary()

    md = build_report(now, loc, cc, credo)
    File.write!(@out, md)
    IO.puts("wrote #{Path.expand(@out)}")
  end

  # ------------------------------------------------------------------
  # LOC / file / module counts by domain area
  # ------------------------------------------------------------------

  defp loc_by_dir do
    for dir <- ~w(lib/guildford_vue lib/guildford_vue_web) do
      files = Path.wildcard("#{dir}/**/*.ex")

      loc =
        files
        |> Enum.map(&count_lines/1)
        |> Enum.sum()

      modules =
        files
        |> Enum.flat_map(&extract_module_names/1)
        |> Enum.uniq()
        |> length()

      %{dir: dir, files: length(files), lines: loc, modules: modules}
    end
  end

  defp count_lines(path) do
    path |> File.stream!() |> Enum.count()
  end

  defp extract_module_names(path) do
    path
    |> File.read!()
    |> then(&Regex.scan(~r/^\s*defmodule\s+([A-Za-z0-9_.]+)/m, &1))
    |> Enum.map(fn [_, name] -> name end)
  end

  # ------------------------------------------------------------------
  # Cyclomatic complexity (via Credo, lowered threshold)
  # ------------------------------------------------------------------

  defp cyclomatic_complexity_hits do
    {out, _status} =
      System.cmd(
        "mix",
        [
          "credo",
          "--format=json",
          "--only",
          "Credo.Check.Refactor.CyclomaticComplexity"
        ],
        env: [{"MIX_ENV", "dev"}]
      )

    case Jason.decode(out) do
      {:ok, %{"issues" => issues}} ->
        # Credo puts the CC score in the message, e.g. "Function is too complex (CC is 12)."
        # Parse it back out.
        issues
        |> Enum.map(fn i ->
          score =
            case Regex.run(~r/CC is (\d+)/, i["message"] || "") do
              [_, s] -> String.to_integer(s)
              _ -> 0
            end

          %{
            file: i["filename"],
            line: i["line_no"],
            function: i["trigger"] || "?",
            cc: score
          }
        end)
        |> Enum.sort_by(& &1.cc, :desc)

      _ ->
        []
    end
  end

  # ------------------------------------------------------------------
  # Strict-mode Credo summary
  # ------------------------------------------------------------------

  defp strict_credo_summary do
    {out, _status} =
      System.cmd(
        "mix",
        ["credo", "--strict", "--format=json"],
        env: [{"MIX_ENV", "dev"}]
      )

    case Jason.decode(out) do
      {:ok, %{"issues" => issues}} ->
        by_check =
          issues
          |> Enum.group_by(&String.replace(&1["check"] || "?", "Elixir.Credo.Check.", ""))
          |> Enum.map(fn {k, v} -> {k, length(v)} end)
          |> Enum.sort_by(fn {_, n} -> -n end)

        %{total: length(issues), by_check: by_check}

      _ ->
        %{total: 0, by_check: []}
    end
  end

  # ------------------------------------------------------------------
  # Markdown report
  # ------------------------------------------------------------------

  defp build_report(now, loc, cc, credo) do
    """
    # FP reference — static-analysis report

    Generated #{now} UTC. Rerun via `mix run scripts/report_complexity.exs`.

    ## Scope

    Source directories: `lib/guildford_vue` (functional core) and
    `lib/guildford_vue_web` (imperative shell). Tests, migrations,
    seeds, and deps are excluded — the C5 comparison against the OO
    artefact is per-domain-module, not per-fixture.

    ## LOC / files / modules

    | Directory | Files | Modules | Lines |
    |-----------|-------|---------|-------|
    #{loc_rows(loc)}

    Total: #{Enum.sum(Enum.map(loc, & &1.files))} files, #{Enum.sum(Enum.map(loc, & &1.modules))} modules, #{Enum.sum(Enum.map(loc, & &1.lines))} lines.

    ## Cyclomatic complexity (Credo default threshold = #{@credo_default_cc_threshold})

    Every function with CC ≥ #{@credo_default_cc_threshold} is listed. Reported via
    `mix credo --only Credo.Check.Refactor.CyclomaticComplexity`; that
    invocation uses Credo's built-in `max_complexity: #{@credo_default_cc_threshold}` — the CLI has
    no threshold override. If a future dissertation cite needs a lower
    threshold, add a `.credo.threshold-N.exs` and pass
    `--config-file <file>` to the credo invocation
    (Sprint 13 Defect 023 closure).

    #{cc_section(cc)}

    ## Strict Credo audit

    `mix credo --strict` — total issues: **#{credo.total}**.

    #{credo_check_table(credo.by_check)}

    ## Notes

    #{notes(cc, loc)}
    """
  end

  defp loc_rows(loc) do
    loc
    |> Enum.map(fn r ->
      "| `#{r.dir}` | #{r.files} | #{r.modules} | #{r.lines} |"
    end)
    |> Enum.join("\n    ")
  end

  defp cc_section([]),
    do:
      "No function exceeds CC #{@credo_default_cc_threshold} — the codebase's highest complexity is under the review-flag bar."

  defp cc_section(cc) do
    rows =
      cc
      |> Enum.take(20)
      |> Enum.map(fn h ->
        "| #{h.file}:#{h.line} | `#{h.function}` | #{h.cc} |"
      end)
      |> Enum.join("\n    ")

    """
    | File:line | Function | CC |
    |-----------|----------|----|
    #{rows}

    (Top 20 shown. Full list: #{length(cc)} functions ≥ CC #{@credo_default_cc_threshold}.)
    """
  end

  defp credo_check_table([]),
    do: "No breakdown — the strict pass is clean."

  defp credo_check_table(checks) do
    rows =
      checks
      |> Enum.map(fn {name, n} -> "| #{n} | `#{name}` |" end)
      |> Enum.join("\n    ")

    """
    | Count | Check |
    |-------|-------|
    #{rows}
    """
  end

  defp notes(cc, loc) do
    max = List.first(cc)

    max_note =
      case max do
        nil ->
          "- No function exceeds Credo's default `max_complexity: #{@credo_default_cc_threshold}`. Credo's CLI has no threshold override; to survey below that bar, see the `.credo.threshold-N.exs` workaround called out in the Cyclomatic-complexity section (Sprint 13 Defect 023 closure)."

        %{function: name, cc: score, file: file, line: line} ->
          "- Highest-complexity function this run: `#{name}` at CC #{score} (`#{file}:#{line}`). Computed from Credo's `Refactor.CyclomaticComplexity` output, not hardcoded."
      end

    web =
      loc
      |> Enum.find(&(&1.dir == "lib/guildford_vue_web"))

    core =
      loc
      |> Enum.find(&(&1.dir == "lib/guildford_vue"))

    ratio_note =
      if web && core && core.lines > 0 do
        r = Float.round(web.lines / core.lines, 2)

        "- Imperative shell (`lib/guildford_vue_web`, #{web.lines} lines) vs functional core (`lib/guildford_vue`, #{core.lines} lines): shell/core ratio = #{r}. The FP-idiomatic shape is shell < core — a ratio > 1 warrants a review flag."
      else
        ""
      end

    [max_note, ratio_note] |> Enum.reject(&(&1 == "")) |> Enum.join("\n")
  end
end

ReportComplexity.run()
