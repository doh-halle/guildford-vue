defmodule Mix.Tasks.GuildfordVue.Bench.Broadcast do
  @moduledoc """
  PRD §2.2 goal — measures the BEAM's PubSub broadcast latency
  under load. Defaults to 1000 subscribers × 10 broadcasts; tune
  via `--subscribers N` and `--broadcasts M`.

  Run:

      $ mix guildford_vue.bench.broadcast
      $ mix guildford_vue.bench.broadcast --subscribers 5000 --broadcasts 5

  Output:
    - Stdout: human-readable summary
    - File: `benchmarks/results/broadcast-<UTC timestamp>.json`
      (gitignored — the dissertation captures specific runs into
      `docs/` by hand)
  """
  use Mix.Task

  alias GuildfordVue.Bench.Broadcast

  @shortdoc "Broadcast latency benchmark (PRD §2.2: 1000 subs / 500ms p95)."

  @switches [subscribers: :integer, broadcasts: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    subscribers = Keyword.get(opts, :subscribers, 1000)
    broadcasts = Keyword.get(opts, :broadcasts, 10)

    result = Broadcast.run(subscribers: subscribers, broadcasts: broadcasts)

    print(result)
    write_json(result)
  end

  defp print(result) do
    Mix.shell().info("""

    PubSub broadcast benchmark
    --------------------------
      Subscribers:        #{result.subscribers}
      Broadcasts:         #{result.broadcasts}
      Delivered samples:  #{result.delivered_samples} / #{result.subscribers * result.broadcasts}
      Wall elapsed:       #{result.elapsed_ms} ms

    Per-message latency (sub-to-receive):
      p50:                #{format_us(result.p50_us)}
      p95:                #{format_us(result.p95_us)}
      p99:                #{format_us(result.p99_us)}
      max:                #{format_us(result.max_us)}
    """)

    if result.p95_us > 500_000 do
      Mix.shell().error("""
      p95 #{format_us(result.p95_us)} exceeds PRD §2.2's 500ms target.
      """)
    end
  end

  defp write_json(result) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    path = Path.join(["benchmarks", "results", "broadcast-#{ts}.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(result, pretty: true))
    Mix.shell().info("Wrote #{path}")
  end

  defp format_us(us) when us < 1_000, do: "#{us} µs"
  defp format_us(us) when us < 1_000_000, do: "#{Float.round(us / 1_000, 2)} ms"
  defp format_us(us), do: "#{Float.round(us / 1_000_000, 2)} s"
end
