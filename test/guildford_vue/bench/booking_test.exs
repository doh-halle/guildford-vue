defmodule GuildfordVue.Bench.BookingTest do
  @moduledoc """
  Sprint 12 Slice 5 — smoke test for the booking benchmark. The
  benchmark itself is run interactively via
  `mix guildford_vue.bench.booking`; this test pins the result
  shape so a regression in the bench module shows up in the test
  suite.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.Bench.Booking

  test "returns the expected result shape with successes > 0" do
    result = Booking.run(iterations: 5, capacity: 10)

    assert is_integer(result.iterations) and result.iterations == 5
    assert is_integer(result.successes) and result.successes > 0
    assert is_integer(result.elapsed_ms) and result.elapsed_ms >= 0
    assert is_float(result.throughput_per_s)

    for key <- [:p50_us, :p95_us, :p99_us, :max_us] do
      assert Map.fetch!(result, key) >= 0
    end
  end
end
