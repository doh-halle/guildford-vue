defmodule GuildfordVue.Bench.Booking do
  @moduledoc """
  Sprint 12 Slice 5 — end-to-end booking-pipeline latency
  benchmark. Drives `Bookings.create_booking/3` against pre-
  seeded test fixtures and returns percentile latencies for the
  dissertation's empirical chapter.

  The benchmark uses the PaymentGateway.Stub adapter (no
  payment latency) so the measured number is the pure pipeline
  cost: validate → reserve via CentreServer → fetch exam → pay
  → persist booking + payment rows → attach PDF URL → notify +
  audit (best-effort, async).

  Run via `mix guildford_vue.bench.booking --iterations 200`.
  """

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  @doc """
  Seeds a one-centre one-exam setup with a large-capacity slot,
  then drives N booking attempts serially. Returns:

      %{iterations: 200, successes: 199,
        p50_us: …, p95_us: …, p99_us: …, max_us: …,
        elapsed_ms: …}
  """
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100)
    capacity = Keyword.get(opts, :capacity, iterations + 10)

    {centre, exam, slot, candidate_factory} = seed_environment(capacity)
    _ = Centres.ensure_started(centre.id)

    candidates = Enum.map(1..iterations, fn _ -> candidate_factory.() end)

    start = System.monotonic_time(:millisecond)

    {samples, successes} =
      Enum.map_reduce(candidates, 0, fn candidate, succ ->
        t0 = System.monotonic_time(:microsecond)
        outcome = Bookings.create_booking(candidate, slot)
        t1 = System.monotonic_time(:microsecond)
        ok? = match?({:ok, _}, outcome)
        {{t1 - t0, ok?}, succ + if(ok?, do: 1, else: 0)}
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - start
    successful_latencies = for {us, true} <- samples, do: us

    %{
      iterations: iterations,
      successes: successes,
      elapsed_ms: elapsed_ms,
      throughput_per_s: throughput(iterations, elapsed_ms),
      p50_us: percentile(successful_latencies, 0.5),
      p95_us: percentile(successful_latencies, 0.95),
      p99_us: percentile(successful_latencies, 0.99),
      max_us: max_or_zero(successful_latencies)
    }
  end

  defp seed_environment(capacity) do
    suffix = System.unique_integer([:positive])

    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bench-admin-#{suffix}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Bench Admin",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bench-centre-#{suffix}@example.com",
        "password" => "supersecret123!A",
        "name" => "Bench Centre",
        "address_line_1" => "1 Bench St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Bench Exam #{suffix}",
          "code" => "BENCH-#{suffix}",
          "certification_body" => "Bench",
          "duration_minutes" => 60,
          "price_pence" => 1000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], admin)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(centre, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => capacity
      })

    factory = fn ->
      i = System.unique_integer([:positive])

      {:ok, c} =
        Candidates.register_candidate(%{
          "email" => "bench-cand-#{i}@example.com",
          "password" => "supersecret123!A",
          "first_name" => "B",
          "last_name" => "C"
        })

      c
    end

    {centre, exam, slot, factory}
  end

  defp percentile([], _), do: 0

  defp percentile(samples, p) do
    sorted = Enum.sort(samples)
    idx = min(length(sorted) - 1, max(0, trunc(p * (length(sorted) - 1))))
    Enum.at(sorted, idx)
  end

  defp max_or_zero([]), do: 0
  defp max_or_zero(samples), do: Enum.max(samples)

  defp throughput(_iterations, 0), do: 0.0

  defp throughput(iterations, elapsed_ms) do
    Float.round(iterations * 1_000 / elapsed_ms, 2)
  end
end
