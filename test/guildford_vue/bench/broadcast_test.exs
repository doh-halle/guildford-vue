defmodule GuildfordVue.Bench.BroadcastTest do
  @moduledoc """
  Sprint 6 Slice 6 — load-test scaffold for the PRD §2.2 target
  "1,000 concurrent subscribers receive updates within 500 ms p95".

  These tests exercise the scaffold at N=20, M=5 so they run in
  ~100ms. The real 1000-subscriber benchmark is run via
  `mix guildford_vue.bench.broadcast` — its output lands in
  `benchmarks/results/`.
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.Bench.Broadcast

  test "run/1 returns p50/p95/p99 + sample counts" do
    result = Broadcast.run(subscribers: 20, broadcasts: 5)

    assert is_map(result)
    assert is_integer(result.subscribers)
    assert is_integer(result.broadcasts)
    assert is_integer(result.delivered_samples)
    assert is_integer(result.p50_us)
    assert is_integer(result.p95_us)
    assert is_integer(result.p99_us)
    assert is_integer(result.max_us)
  end

  test "every subscriber receives every broadcast (no drops at small N)" do
    %{subscribers: n, broadcasts: m, delivered_samples: delivered} =
      Broadcast.run(subscribers: 10, broadcasts: 3)

    # We don't require ZERO drops at large N, but at 10×3 the BEAM
    # should never lose a message. Sanity-check.
    assert delivered == n * m
  end

  test "p95 < 500_000 microseconds (500 ms) at small N" do
    %{p95_us: p95} = Broadcast.run(subscribers: 50, broadcasts: 3)

    assert p95 < 500_000,
           "p95 latency #{p95}us exceeds the PRD §2.2 target (500ms) at small N"
  end
end
