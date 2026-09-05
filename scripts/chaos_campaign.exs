# scripts/chaos_campaign.exs — Sprint 13 Defect 021+022 fix.
#
# The shipped scripts/chaos.exs runs one scenario per invocation
# (Sprint 12 Slice 4 design). This wrapper runs N iterations of one
# or more scenarios and appends structured MTTR rows to a JSONL raw
# file for percentile analysis.
#
# Two operating modes:
#
#   1. `mix run scripts/chaos_campaign.exs` — short-lived BEAM,
#      launches the app itself. Fine for `random_centre` (kills a
#      per-centre GenServer, DynamicSupervisor respawns it — no
#      Application-supervisor cascade). NOT recommended for
#      `pubsub_crash` / `registry_crash` because repeated kills at
#      that layer exhaust the Application supervisor's max_restarts
#      budget in a short-lived BEAM (Defect 022 root cause).
#
#   2. `mix run scripts/chaos_campaign.exs --node NAME@HOST` —
#      drives scenarios against a long-running Phoenix node via
#      :rpc.call/4. Requires the target to have been started with
#      `iex --sname NAME --cookie chaos-cookie -S mix phx.server`
#      and both sides to share the same cookie. This is the
#      correct path for `pubsub_crash` / `registry_crash` campaigns.
#
# Usage:
#
#     mix run scripts/chaos_campaign.exs \
#         --scenarios random_centre \
#         --runs 30 \
#         --output docs/measurements/fp/raw/c4_chaos.jsonl
#
#     # Long-running target:
#     mix run scripts/chaos_campaign.exs \
#         --node guildford_vue@localhost \
#         --cookie chaos-cookie \
#         --scenarios random_centre pubsub_crash registry_crash \
#         --runs 30

defmodule ChaosCampaign do
  @default_output "docs/measurements/fp/raw/c4_chaos.jsonl"
  @wait_deadline_ms 5_000

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [
          scenarios: :string,
          runs: :integer,
          output: :string,
          node: :string,
          cookie: :string
        ]
      )

    scenarios =
      (opts[:scenarios] || "random_centre")
      |> String.split([",", " "], trim: true)
      |> Enum.map(&String.to_atom/1)

    runs = opts[:runs] || 30
    output = opts[:output] || @default_output

    target = maybe_connect_node(opts[:node], opts[:cookie])

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, "")

    warm_centres(target)

    for scenario <- scenarios do
      for i <- 1..runs do
        Process.sleep(200)
        if scenario == :random_centre, do: warm_centres(target)

        record = run_scenario(scenario, i, target)
        line = Jason.encode!(record) <> "\n"
        File.write!(output, line, [:append])
        IO.puts(line |> String.trim())
      end
    end
  end

  # ------------------------------------------------------------------
  # Optional Node.connect (Defect 022 fix)
  # ------------------------------------------------------------------

  defp maybe_connect_node(nil, _), do: :local

  defp maybe_connect_node(name, cookie) when is_binary(name) do
    node = String.to_atom(name)

    # Elixir needs a name for Node.connect/1 to work. If we're
    # already named, keep it; otherwise start a hidden distributed
    # node for the runner.
    if Node.self() == :nonode@nohost do
      # Use the same shortname / longname mode as the target implies.
      # If the target has a dot in the host part it's a longname; else shortname.
      [_, host] = String.split(name, "@")
      mode = if String.contains?(host, "."), do: :longnames, else: :shortnames
      {:ok, _} = Node.start(:chaos_runner, mode)
    end

    if cookie do
      Node.set_cookie(String.to_atom(cookie))
    end

    case Node.connect(node) do
      true -> node
      false -> raise "cannot connect to #{node} — is it up + is the cookie right?"
      :ignored -> raise "distribution not started"
    end
  end

  # ------------------------------------------------------------------
  # Scenario dispatch — either in-process or via :rpc.call/4
  # ------------------------------------------------------------------

  defp run_scenario(scenario, i, :local),
    do: do_run_scenario(scenario, i)

  defp run_scenario(scenario, i, node) when is_atom(node) do
    # Elixir anonymous functions carry a module reference — they can't
    # be `:erpc.call`'d unless the target has the same module loaded.
    # ChaosCampaign isn't in the target's code path. Workaround: drive
    # every scenario as a chain of `:rpc.call`s that only reference
    # functions the target already has (Elixir stdlib + GuildfordVue.*).
    # The wait loop runs on the runner; each poll is a fresh RPC.
    # Same-host localhost RPC is ~sub-ms, so 5 ms poll interval works.
    result =
      try do
        rpc_run_scenario(scenario, node)
      catch
        kind, reason ->
          %{outcome: :rpc_failed, error: inspect({kind, reason}), mttr_ms: -1}
      end

    Map.merge(result, %{scenario: scenario, run: i})
  end

  # ------------------------------------------------------------------
  # rpc_run_scenario/2 — orchestrates each scenario across the wire.
  # ------------------------------------------------------------------

  defp rpc_run_scenario(:pubsub_crash, node) do
    before = rpc_now_ms(node)
    pid = rpc_whereis_named(node, GuildfordVue.PubSub)

    if pid do
      :ok = rpc_kill(node, pid)
      mttr = rpc_wait_named_pid_change(node, GuildfordVue.PubSub, pid, before, 5_000)
      %{victim_pid: inspect(pid), mttr_ms: mttr}
    else
      %{outcome: :pubsub_missing, mttr_ms: -1}
    end
  end

  defp rpc_run_scenario(:registry_crash, node) do
    before = rpc_now_ms(node)
    pid = rpc_whereis_named(node, GuildfordVue.Centres.Registry)

    if pid do
      :ok = rpc_kill(node, pid)
      mttr = rpc_wait_named_pid_change(node, GuildfordVue.Centres.Registry, pid, before, 5_000)
      %{victim_pid: inspect(pid), mttr_ms: mttr}
    else
      %{outcome: :registry_missing, mttr_ms: -1}
    end
  end

  defp rpc_run_scenario(:random_centre, node) do
    before = rpc_now_ms(node)

    case :rpc.call(node, Supervisor, :which_children, [GuildfordVue.Centres.DynamicSupervisor], 5_000) do
      [] ->
        %{outcome: :no_centres, mttr_ms: -1}

      {:badrpc, r} ->
        %{outcome: :rpc_failed, error: inspect(r), mttr_ms: -1}

      children ->
        {_, victim, _, _} = Enum.random(children)

        centre_id =
          :rpc.call(node, Registry, :select, [
            GuildfordVue.Centres.Registry,
            [{{:"$1", :"$2", :"$3"}, [{:==, :"$2", victim}], [:"$1"]}]
          ], 5_000)
          |> List.first()

        :ok = rpc_kill(node, victim)

        mttr =
          if centre_id do
            rpc_wait_centre_pid_change(node, centre_id, victim, before, 5_000)
          else
            -1
          end

        %{victim_pid: inspect(victim), centre_id: centre_id, mttr_ms: mttr}
    end
  end

  # ------------------------------------------------------------------
  # RPC primitives — one wire call each.
  # ------------------------------------------------------------------

  defp rpc_now_ms(node),
    do: :rpc.call(node, System, :monotonic_time, [:millisecond], 5_000)

  defp rpc_whereis_named(node, name),
    do: :rpc.call(node, Process, :whereis, [name], 5_000)

  defp rpc_kill(node, pid) do
    :rpc.call(node, Process, :exit, [pid, :kill], 5_000)
    :ok
  end

  defp rpc_wait_named_pid_change(node, name, old_pid, before, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_named(node, name, old_pid, before, deadline)
  end

  defp poll_named(node, name, old_pid, before, deadline) do
    current = rpc_whereis_named(node, name)
    now = System.monotonic_time(:millisecond)

    cond do
      current != nil and current != old_pid ->
        rpc_now_ms(node) - before

      now >= deadline ->
        -1

      true ->
        Process.sleep(5)
        poll_named(node, name, old_pid, before, deadline)
    end
  end

  defp rpc_wait_centre_pid_change(node, centre_id, old_pid, before, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_centre(node, centre_id, old_pid, before, deadline)
  end

  defp poll_centre(node, centre_id, old_pid, before, deadline) do
    result = :rpc.call(node, GuildfordVue.Centres, :whereis, [centre_id], 5_000)
    now = System.monotonic_time(:millisecond)

    fresh =
      case result do
        {:ok, p} when p != old_pid -> p
        _ -> nil
      end

    cond do
      is_pid(fresh) ->
        rpc_now_ms(node) - before

      now >= deadline ->
        -1

      true ->
        Process.sleep(5)
        poll_centre(node, centre_id, old_pid, before, deadline)
    end
  end

  # ------------------------------------------------------------------
  # Scenarios (public so :rpc.call/4 can hit them)
  # ------------------------------------------------------------------

  def do_run_scenario(:random_centre, i) do
    before = System.monotonic_time(:millisecond)

    case Supervisor.which_children(GuildfordVue.Centres.DynamicSupervisor) do
      [] ->
        %{scenario: :random_centre, run: i, outcome: :no_centres, mttr_ms: -1}

      children ->
        # Pick a victim + its centre_id so we can poll the Registry.
        {_, victim, _, _} = Enum.random(children)
        centre_id = fetch_centre_id_from_pid(victim)

        Process.exit(victim, :kill)
        wait_for_registry(centre_id, victim, before, :random_centre, i)
    end
  end

  def do_run_scenario(:pubsub_crash, i) do
    before = System.monotonic_time(:millisecond)
    pid = Process.whereis(GuildfordVue.PubSub)

    if pid do
      Process.exit(pid, :kill)
      elapsed = wait_for_named_process(GuildfordVue.PubSub, pid, before, @wait_deadline_ms)
      %{scenario: :pubsub_crash, run: i, victim_pid: inspect(pid), mttr_ms: elapsed}
    else
      %{scenario: :pubsub_crash, run: i, outcome: :pubsub_missing, mttr_ms: -1}
    end
  end

  def do_run_scenario(:registry_crash, i) do
    before = System.monotonic_time(:millisecond)
    pid = Process.whereis(GuildfordVue.Centres.Registry)

    if pid do
      Process.exit(pid, :kill)
      elapsed = wait_for_named_process(GuildfordVue.Centres.Registry, pid, before, @wait_deadline_ms)

      %{
        scenario: :registry_crash,
        run: i,
        victim_pid: inspect(pid),
        mttr_ms: elapsed
      }
    else
      %{scenario: :registry_crash, run: i, outcome: :registry_missing, mttr_ms: -1}
    end
  end

  # ------------------------------------------------------------------
  # Wait helpers — Defect 021 fix: poll the Registry for the specific
  # centre_id, not Supervisor.which_children, which lags under load.
  # ------------------------------------------------------------------

  def wait_for_registry(centre_id, old_pid, before, scenario, run_id) do
    deadline = System.monotonic_time(:millisecond) + @wait_deadline_ms
    do_wait_registry(centre_id, old_pid, before, scenario, run_id, deadline)
  end

  defp do_wait_registry(nil, _, before, scenario, run_id, _deadline) do
    # Couldn't recover centre_id from the killed PID — fall back to a
    # simple "any new child appeared" heuristic. This branch shouldn't
    # fire in practice because fetch_centre_id_from_pid/1 caches from
    # Registry BEFORE the kill.
    Process.sleep(50)

    %{
      scenario: scenario,
      run: run_id,
      outcome: :unknown_centre_id,
      mttr_ms: System.monotonic_time(:millisecond) - before
    }
  end

  defp do_wait_registry(centre_id, old_pid, before, scenario, run_id, deadline) do
    result = GuildfordVue.Centres.whereis(centre_id)
    now = System.monotonic_time(:millisecond)

    fresh_pid =
      case result do
        {:ok, p} when p != old_pid -> p
        _ -> nil
      end

    cond do
      is_pid(fresh_pid) ->
        %{
          scenario: scenario,
          run: run_id,
          victim_pid: inspect(old_pid),
          new_pid: inspect(fresh_pid),
          centre_id: centre_id,
          mttr_ms: now - before
        }

      now >= deadline ->
        %{
          scenario: scenario,
          run: run_id,
          outcome: :timeout,
          centre_id: centre_id,
          mttr_ms: -1
        }

      true ->
        Process.sleep(5)
        do_wait_registry(centre_id, old_pid, before, scenario, run_id, deadline)
    end
  end

  defp wait_for_named_process(name, old_pid, before, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_named(name, old_pid, before, deadline)
  end

  defp do_wait_named(name, old_pid, before, deadline) do
    now = System.monotonic_time(:millisecond)
    current = Process.whereis(name)

    cond do
      current != nil and current != old_pid ->
        now - before

      now >= deadline ->
        -1

      true ->
        Process.sleep(5)
        do_wait_named(name, old_pid, before, deadline)
    end
  end

  # ------------------------------------------------------------------
  # centre_id lookup — walk Registry entries and match by PID.
  # ------------------------------------------------------------------

  def fetch_centre_id_from_pid(pid) do
    # GuildfordVue.Centres.Registry is a :unique Registry keyed by
    # centre_id → CentreServer PID. Walk its select and match.
    match =
      Registry.select(GuildfordVue.Centres.Registry, [
        {{:"$1", :"$2", :"$3"}, [{:==, :"$2", pid}], [:"$1"]}
      ])

    case match do
      [centre_id | _] -> centre_id
      _ -> nil
    end
  end

  # ------------------------------------------------------------------
  # Warm up: ensure a handful of centres are running so random_centre
  # has something to kill.
  # ------------------------------------------------------------------

  defp warm_centres(:local), do: do_warm_centres_local()

  defp warm_centres(node) when is_atom(node) do
    # Can't RPC to ChaosCampaign.do_warm_centres — that module isn't on
    # the target. Compose the warm-up out of :rpc.call to GuildfordVue.*
    # functions that DO exist on the target.
    case :rpc.call(node, GuildfordVue.ExamCentres, :list_approved_centres, [], 10_000) do
      {:badrpc, _} ->
        :ok

      centres when is_list(centres) ->
        centres
        |> Enum.take(3)
        |> Enum.each(fn c ->
          :rpc.call(node, GuildfordVue.Centres, :start_centre, [c.id], 5_000)
        end)

        Process.sleep(50)
    end
  end

  def do_warm_centres_local do
    centres = GuildfordVue.ExamCentres.list_approved_centres() |> Enum.take(3)

    Enum.each(centres, fn c ->
      try do
        GuildfordVue.Centres.start_centre(c.id)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)

    Process.sleep(50)
  end
end

ChaosCampaign.main(System.argv())
