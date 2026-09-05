# scripts/ramp.exs — Sprint 13 BEAM-native C1 read ramp harness.
#
# Fires N concurrent GET /search requests per ramp step against the
# running Phoenix endpoint; reports per-step throughput + response-time
# percentiles. Written because tsung isn't installed on this measurement
# host; the shipped `benchmarks/tsung/search-baseline.xml` remains the
# canonical dissertation-cite path once a tsung box is available.
#
# C3 (WebSocket connection ramp) is handled by a sibling Python
# script (`scripts/ws_ramp.py`) so the same Python `websockets`
# client used against the OO artefact drives both artefacts — parity
# of measurement instrument.
#
# Usage:
#     mix run scripts/ramp.exs --steps 50,200,500,1000
#     mix run scripts/ramp.exs --steps 50,200,500,1000 --host 127.0.0.1:4000

defmodule Ramp do
  @raw "docs/measurements/fp/raw/c1_search_ramp.csv"

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [steps: :string, host: :string]
      )

    host = opts[:host] || "127.0.0.1:4000"
    steps = parse_steps(opts[:steps] || "50,200,500,1000")

    :inets.start()
    :ssl.start()

    run_ramp(steps, host)
  end

  defp parse_steps(s) do
    s
    |> String.split([",", " "], trim: true)
    |> Enum.map(&String.to_integer/1)
  end

  defp run_ramp(steps, host) do
    File.mkdir_p!(Path.dirname(@raw))

    File.open!(@raw, [:write], fn fh ->
      IO.puts(
        fh,
        "step,target_concurrency,successful,failed,latency_p50_ms,latency_p95_ms,latency_p99_ms,elapsed_ms"
      )

      Enum.with_index(steps)
      |> Enum.each(fn {n, idx} ->
        row = run_step(n, host)

        IO.puts(
          fh,
          "#{idx},#{n},#{row.ok},#{row.fail},#{row.p50},#{row.p95},#{row.p99},#{row.elapsed}"
        )

        IO.puts(
          "step=#{String.pad_leading(to_string(idx), 2)} target=#{String.pad_leading(to_string(n), 5)} ok=#{row.ok} fail=#{row.fail}  p50=#{row.p50}ms p95=#{row.p95}ms p99=#{row.p99}ms  elapsed=#{row.elapsed}ms"
        )

        Process.sleep(2000)
      end)
    end)
  end

  defp run_step(count, host) do
    parent = self()
    t0 = System.monotonic_time(:millisecond)

    _ =
      Enum.each(1..count, fn i ->
        spawn(fn ->
          started = System.monotonic_time(:microsecond)

          result =
            try do
              case :httpc.request(
                     :get,
                     {String.to_charlist("http://#{host}/search"), []},
                     [{:timeout, 15_000}, {:connect_timeout, 5_000}],
                     []
                   ) do
                {:ok, {{_, code, _}, _, _}} when code in 200..399 -> :ok
                _ -> :fail
              end
            rescue
              _ -> :fail
            catch
              _, _ -> :fail
            end

          send(parent, {:done, i, result, System.monotonic_time(:microsecond) - started})
        end)
      end)

    outcomes =
      Enum.map(1..count, fn _ ->
        receive do
          {:done, _, result, elapsed_us} -> {result, elapsed_us}
        after
          30_000 -> {:timeout, 30_000_000}
        end
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - t0
    ok = Enum.count(outcomes, fn {r, _} -> r == :ok end)
    fail = count - ok
    lat_ms = outcomes |> Enum.map(fn {_, us} -> us / 1000 end) |> Enum.sort()

    %{
      ok: ok,
      fail: fail,
      elapsed: elapsed_ms,
      p50: percentile(lat_ms, 0.50) |> Float.round(2),
      p95: percentile(lat_ms, 0.95) |> Float.round(2),
      p99: percentile(lat_ms, 0.99) |> Float.round(2)
    }
  end

  defp percentile([], _), do: 0.0

  defp percentile(sorted, q) do
    idx = max(round(length(sorted) * q) - 1, 0)
    Enum.at(sorted, idx)
  end
end

Ramp.main(System.argv())
