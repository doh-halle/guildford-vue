defmodule Mix.Tasks.GuildfordVue.Bench.Booking do
  @moduledoc """
  Sprint 12 Slice 5 — end-to-end booking-pipeline latency
  benchmark. Drives `Bookings.create_booking/3` serially against
  a freshly-seeded large-capacity slot, returns percentile
  latencies for the dissertation's empirical chapter.

      $ mix guildford_vue.bench.booking
      $ mix guildford_vue.bench.booking --iterations 500

  Output:
    * Stdout: human-readable summary
    * File: `benchmarks/results/booking-<UTC timestamp>.json`

  Use against an isolated dev DB (run `mix ecto.reset` first) so
  the seeded fixtures don't accumulate.
  """
  use Mix.Task

  alias GuildfordVue.Bench.Booking

  @shortdoc "Booking pipeline latency benchmark (Sprint 12 Slice 5)."

  @switches [iterations: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    iterations = Keyword.get(opts, :iterations, 100)

    result = Booking.run(iterations: iterations)
    print(result)
    write_json(result)
  end

  defp print(result) do
    Mix.shell().info("""

    Booking pipeline benchmark
    --------------------------
      Iterations:    #{result.iterations}
      Successes:     #{result.successes}
      Wall elapsed:  #{result.elapsed_ms} ms
      Throughput:    #{result.throughput_per_s} bookings/s

    Per-booking latency (validate → reserve → pay → persist → attach_pdf):
      p50:           #{format_us(result.p50_us)}
      p95:           #{format_us(result.p95_us)}
      p99:           #{format_us(result.p99_us)}
      max:           #{format_us(result.max_us)}
    """)
  end

  defp write_json(result) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    path = Path.join(["benchmarks", "results", "booking-#{ts}.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(result, pretty: true))
    Mix.shell().info("Wrote #{path}")
  end

  defp format_us(us) when us < 1_000, do: "#{us} µs"
  defp format_us(us) when us < 1_000_000, do: "#{Float.round(us / 1_000, 2)} ms"
  defp format_us(us), do: "#{Float.round(us / 1_000_000, 2)} s"
end
