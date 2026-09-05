defmodule GuildfordVue.Test.CoverRecorder do
  @moduledoc """
  Bypass for ExCoveralls defect 002 (Sprint 1, carried to Sprint 1c).

  ExCoveralls silently drops the four `lib/guildford_vue/exam_centres/*.ex`
  files from its `cover/excoveralls.json` report despite `:cover` itself
  having valid line-coverage data for those modules. Sprint 1c slice A
  works around this by registering an `ExUnit.after_suite/1` callback that
  queries `:cover.modules/0` and `:cover.analyse/3` directly and writes a
  JSON report at `cover/guildford_vue_coverage.json` — the canonical
  source of truth for `mix guildford_vue.coverage.audit`.

  The output schema matches ExCoveralls' `source_files` shape so the audit
  task can read either file with the same logic.

  The callback runs only when `:cover` is active (i.e. under
  `mix coveralls.*` or `mix test --cover`). Plain `mix test` is unaffected.
  """

  @output_path "cover/guildford_vue_coverage.json"

  @doc """
  Registers an `ExUnit.after_suite/1` callback that writes the JSON file.
  Called from `test/test_helper.exs`.
  """
  def install do
    ExUnit.after_suite(fn _results -> write_report() end)
  end

  @doc false
  def write_report do
    case :cover.modules() do
      [] ->
        # No cover state — we're not running under coveralls.
        :ok

      modules ->
        modules
        |> Enum.filter(&our_module?/1)
        |> Enum.flat_map(&analyse_module/1)
        |> Enum.group_by(fn {file, _, _} -> file end)
        |> Enum.map(&summarise_file/1)
        |> dedupe_by_name()
        |> write_json()
    end

    :ok
  end

  defp our_module?(mod) do
    name = Atom.to_string(mod)

    String.starts_with?(name, "Elixir.GuildfordVue") and
      not String.starts_with?(name, "Elixir.Inspect.")
  end

  defp analyse_module(mod) do
    case :cover.analyse(mod, :calls, :line) do
      {:ok, lines} ->
        source_path =
          mod.module_info(:compile)[:source]
          |> List.to_string()
          |> Path.relative_to(File.cwd!())

        Enum.map(lines, fn {{_mod, line}, count} -> {source_path, line, count} end)

      _ ->
        []
    end
  end

  defp summarise_file({file, hits}) do
    if MapSet.member?(skip_files_set(), file), do: nil, else: build_file_entry(file, hits)
  end

  defp build_file_entry(file, hits) do
    case File.read(file) do
      {:ok, source} -> %{name: file, source: source, coverage: coverage_array(source, hits)}
      _ -> nil
    end
  end

  defp coverage_array(source, hits) do
    line_count = source |> String.split("\n") |> length()
    by_line = Enum.into(hits, %{}, fn {_f, line, count} -> {line, count} end)
    for line <- 1..line_count, do: Map.get(by_line, line)
  end

  defp skip_files_set do
    case File.read("coveralls.json") do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"skip_files" => skip}} -> MapSet.new(skip)
          _ -> MapSet.new()
        end

      _ ->
        MapSet.new()
    end
  end

  defp dedupe_by_name(entries) do
    entries
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp write_json(source_files) do
    File.mkdir_p!("cover")
    payload = Jason.encode!(%{source_files: source_files}, pretty: false)
    File.write!(@output_path, payload)
  end
end
