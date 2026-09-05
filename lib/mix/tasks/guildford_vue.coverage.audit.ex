defmodule Mix.Tasks.GuildfordVue.Coverage.Audit do
  @moduledoc """
  Audits `cover/excoveralls.json` to ensure every `lib/**.ex` production file
  is represented in the coverage report. ExCoveralls has a known bug where
  certain modules (notably ones whose Ecto schema declares a custom-type
  field like `Geo.PostGIS.Geometry`) are silently dropped from its report —
  the 90% coverage gate then passes against an artificially narrow
  denominator (see `docs/sprint-reports/sprint-1/defects/002`).

  This task fails with a non-zero exit code if ANY production file is missing
  from the report **unless** the file is listed in `coveralls.json`'s
  `skip_files` OR in `.coverage-known-omissions` (one path per line).

  The known-omissions file is the compensating control until defect 002 is
  fixed: it makes the omission visible and grep-able, while preventing CI
  from masking *new* omissions.

      $ mix coveralls.json
      $ mix guildford_vue.coverage.audit
  """
  use Mix.Task
  @shortdoc "Fails if any lib/**.ex is missing from cover/excoveralls.json."

  # Sprint 1c slice A: switched from cover/excoveralls.json to
  # cover/guildford_vue_coverage.json — the latter is produced by
  # GuildfordVue.Test.CoverRecorder which bypasses the ExCoveralls
  # discovery bug (defect 002 from Sprint 1). If the new report exists
  # we use it; otherwise we fall back to the ExCoveralls report so the
  # task remains usable in environments that don't yet have the new
  # recorder.
  @canonical_path "cover/guildford_vue_coverage.json"
  @fallback_path "cover/excoveralls.json"
  @known_omissions_path ".coverage-known-omissions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadconfig")

    report_path = choose_report_path()

    unless report_path do
      Mix.shell().error("coverage report not found at #{@canonical_path} or #{@fallback_path}")
      Mix.shell().error("run `mix coveralls.json` (and/or `mix test --cover`) first")
      exit({:shutdown, 2})
    end

    expected = list_production_files()
    reported = list_reported_files(report_path)
    skipped = list_skipped_files()
    known_omissions = list_known_omissions()
    candidate_missing = expected -- (reported ++ skipped)
    new_missing = candidate_missing -- known_omissions
    unused_known_omissions = known_omissions -- candidate_missing

    cond do
      new_missing != [] ->
        Mix.shell().error(
          "coverage-audit: #{length(new_missing)} NEW production file(s) missing from #{report_path}:"
        )

        Enum.each(new_missing, &Mix.shell().error("  - #{&1}"))
        Mix.shell().error("")

        Mix.shell().error(
          "If this is a real test gap, write the missing tests. Do not silently lower the gate by adding to .coverage-known-omissions (that file is now obsolete since Sprint 1c slice A — the canonical report at cover/guildford_vue_coverage.json sees every module that :cover sees)."
        )

        exit({:shutdown, 1})

      unused_known_omissions != [] ->
        Mix.shell().info(
          "coverage-audit: #{length(unused_known_omissions)} known-omission entry/entries are no longer needed (the coverage report now includes these files). Remove them from .coverage-known-omissions:"
        )

        Enum.each(unused_known_omissions, &Mix.shell().info("  - #{&1}"))
        exit({:shutdown, 3})

      true ->
        Mix.shell().info(
          "coverage-audit: OK (#{Path.basename(report_path)}) — " <>
            "#{length(reported)} reported, #{length(skipped)} skipped, " <>
            "#{length(known_omissions)} known omissions"
        )
    end
  end

  defp choose_report_path do
    cond do
      File.exists?(@canonical_path) -> @canonical_path
      File.exists?(@fallback_path) -> @fallback_path
      true -> nil
    end
  end

  defp list_production_files do
    Path.wildcard("lib/**/*.ex") |> Enum.sort()
  end

  defp list_reported_files(report_path) do
    report_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("source_files")
    |> Enum.map(& &1["name"])
    |> Enum.sort()
  end

  defp list_skipped_files do
    "coveralls.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("skip_files", [])
  end

  defp list_known_omissions do
    if File.exists?(@known_omissions_path) do
      @known_omissions_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    else
      []
    end
  end
end
