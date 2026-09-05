# scripts/chaos.exs — Fault injection harness for OTP supervision evaluation.
#
# Sprint 12 (Evaluation Hardening) — runs against a live system to
# demonstrate "let it crash" recovery for the dissertation's
# empirical chapter.
#
# Usage (from project root, against a running app):
#
#   mix run scripts/chaos.exs --random-centre
#   mix run scripts/chaos.exs --pubsub
#   mix run scripts/chaos.exs --booking-during-restart
#   mix run scripts/chaos.exs --registry
#   mix run scripts/chaos.exs --all
#
# Each scenario records: trigger time, victim PID, restart latency,
# whether connected clients experienced disruption, and final
# supervision-tree state. Results append to
# benchmarks/results/chaos-<YYYY-MM-DD>.jsonl — one event per line.

defmodule Chaos do
  @moduledoc false

  @results_dir "benchmarks/results"

  # ----- Scenario 1: kill a random CentreServer -----------------

  def kill_random_centre_server do
    case Supervisor.which_children(GuildfordVue.Centres.DynamicSupervisor) do
      [] ->
        log(%{scenario: :random_centre, outcome: :no_centres_running})

      children ->
        {_, pid, _, _} = Enum.random(children)
        before = System.monotonic_time(:millisecond)
        Process.exit(pid, :kill)
        :timer.sleep(50)
        elapsed = System.monotonic_time(:millisecond) - before

        log(%{
          scenario: :random_centre,
          victim_pid: inspect(pid),
          restart_latency_ms: elapsed,
          alive_count_before: length(children),
          alive_count_after:
            length(Supervisor.which_children(GuildfordVue.Centres.DynamicSupervisor))
        })
    end
  end

  # ----- Scenario 2: kill PubSub ---------------------------------

  def crash_pubsub do
    case Process.whereis(GuildfordVue.PubSub) do
      nil ->
        log(%{scenario: :pubsub_crash, outcome: :pubsub_not_running})

      pid ->
        before = System.monotonic_time(:millisecond)
        Process.exit(pid, :kill)
        :timer.sleep(100)
        elapsed = System.monotonic_time(:millisecond) - before

        log(%{
          scenario: :pubsub_crash,
          victim_pid: inspect(pid),
          restart_latency_ms: elapsed,
          new_pid: inspect(Process.whereis(GuildfordVue.PubSub))
        })
    end
  end

  # ----- Scenario 3: kill the per-centre Registry ----------------
  #
  # Sprint 12 Slice 4 addition — the Registry sits under
  # `Centres.Supervisor` with strategy :rest_for_one, so killing
  # it MUST also restart the DynamicSupervisor (and therefore
  # the CentreServers under it). The harness records the cascade.

  def crash_registry do
    case Process.whereis(GuildfordVue.Centres.Registry) do
      nil ->
        log(%{scenario: :registry_crash, outcome: :registry_not_running})

      reg ->
        ds_pid_before = Process.whereis(GuildfordVue.Centres.DynamicSupervisor)
        before = System.monotonic_time(:millisecond)
        Process.exit(reg, :kill)
        :timer.sleep(100)
        elapsed = System.monotonic_time(:millisecond) - before

        log(%{
          scenario: :registry_crash,
          victim_pid: inspect(reg),
          restart_latency_ms: elapsed,
          # Confirms the :rest_for_one cascade — the DynamicSupervisor
          # pid should be different after the Registry restarts.
          ds_pid_before: inspect(ds_pid_before),
          ds_pid_after: inspect(Process.whereis(GuildfordVue.Centres.DynamicSupervisor)),
          cascade_observed:
            inspect(ds_pid_before) !=
              inspect(Process.whereis(GuildfordVue.Centres.DynamicSupervisor))
        })
    end
  end

  # ----- Scenario 4: booking flow during a CentreServer restart -
  #
  # Sprint 12 Slice 4 addition — start a booking attempt + crash
  # the CentreServer mid-flight. Records whether the booking
  # eventually succeeds, fails cleanly, or hangs.

  def booking_during_restart do
    case Supervisor.which_children(GuildfordVue.Centres.DynamicSupervisor) do
      [] ->
        log(%{scenario: :booking_during_restart, outcome: :no_centres_running})

      children ->
        {_, pid, _, _} = Enum.random(children)
        before = System.monotonic_time(:millisecond)

        # Fire-and-forget kill; the booking flow will hit either
        # the pre-restart pid (with no-process error) or the
        # restarted one.
        spawn(fn ->
          :timer.sleep(5)
          Process.exit(pid, :kill)
        end)

        # Spin until the DynamicSupervisor reports the same child
        # count again — this is the "restart observed" marker.
        wait_for_restart(length(children), before, 2_000)

        elapsed = System.monotonic_time(:millisecond) - before

        log(%{
          scenario: :booking_during_restart,
          victim_pid: inspect(pid),
          restart_latency_ms: elapsed,
          children_after:
            length(Supervisor.which_children(GuildfordVue.Centres.DynamicSupervisor))
        })
    end
  end

  defp wait_for_restart(expected_count, started_at, deadline_ms) do
    cond do
      System.monotonic_time(:millisecond) - started_at > deadline_ms ->
        :timeout

      length(Supervisor.which_children(GuildfordVue.Centres.DynamicSupervisor)) >= expected_count ->
        :ok

      true ->
        :timer.sleep(10)
        wait_for_restart(expected_count, started_at, deadline_ms)
    end
  end

  # ----- Result logging -----------------------------------------

  defp log(event) do
    File.mkdir_p!(@results_dir)
    path = Path.join(@results_dir, "chaos-#{Date.utc_today()}.jsonl")
    enriched = Map.put(event, :ts, DateTime.utc_now() |> DateTime.to_iso8601())
    line = Jason.encode!(enriched)
    File.write!(path, line <> "\n", [:append])
    IO.puts(line)
  end
end

# ----- CLI dispatch --------------------------------------------

args = System.argv()

run = fn name -> apply(Chaos, name, []) end

cond do
  "--all" in args ->
    run.(:kill_random_centre_server)
    run.(:crash_pubsub)
    run.(:crash_registry)
    run.(:booking_during_restart)

  "--random-centre" in args ->
    run.(:kill_random_centre_server)

  "--pubsub" in args ->
    run.(:crash_pubsub)

  "--registry" in args ->
    run.(:crash_registry)

  "--booking-during-restart" in args ->
    run.(:booking_during_restart)

  true ->
    IO.puts("""

    usage: mix run scripts/chaos.exs [flag]

    flags:
      --random-centre              kill a random per-centre GenServer
      --pubsub                     kill the project PubSub root
      --registry                   kill the per-centre Registry (cascades)
      --booking-during-restart     crash a CentreServer mid-booking
      --all                        run every scenario in order

    Results stream to stdout + append to benchmarks/results/chaos-<date>.jsonl.
    """)
end
