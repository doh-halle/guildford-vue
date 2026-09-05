defmodule GuildfordVue.Bench.Broadcast do
  @moduledoc """
  Benchmark scaffold for PRD §2.2 goal — "1,000 concurrent
  subscribers receive updates within 500 ms p95".

  Spawns N subscriber processes, each subscribed to one centre
  topic; broadcasts M `{:slot_changed, _}` messages; collects
  end-to-end latency samples and returns percentiles.

  Run via `mix guildford_vue.bench.broadcast` (defaults to N=1000,
  M=10) or programmatically:

      iex> GuildfordVue.Bench.Broadcast.run(subscribers: 100, broadcasts: 5)
      %{subscribers: 100, broadcasts: 5, delivered_samples: 500,
        p50_us: 142, p95_us: 318, p99_us: 612, max_us: 1041,
        elapsed_ms: 12}

  All latencies are in microseconds (System.monotonic_time(:microsecond)).
  """

  alias GuildfordVue.Centres.PubSub, as: CentrePubSub

  @type result :: %{
          subscribers: pos_integer(),
          broadcasts: pos_integer(),
          delivered_samples: non_neg_integer(),
          p50_us: non_neg_integer(),
          p95_us: non_neg_integer(),
          p99_us: non_neg_integer(),
          max_us: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

  @spec run(keyword()) :: result()
  def run(opts \\ []) do
    subscribers = Keyword.get(opts, :subscribers, 1000)
    broadcasts = Keyword.get(opts, :broadcasts, 10)
    centre_id = Ecto.UUID.generate()

    parent = self()
    started_at = System.monotonic_time(:millisecond)

    # Spawn subscribers; each one subscribes, then forwards every
    # message it receives with (sent_at, received_at) timestamps.
    pids =
      for _ <- 1..subscribers do
        spawn_link(fn -> subscriber_loop(parent, centre_id, broadcasts) end)
      end

    # Wait for every subscriber to have completed its own subscribe call
    # before broadcasting, otherwise messages will be silently dropped.
    Enum.each(1..subscribers, fn _ ->
      receive do
        :ready -> :ok
      after
        5_000 -> :erlang.error(:subscriber_setup_timeout)
      end
    end)

    # Broadcast with monotonic timestamp embedded in the message;
    # subscribers diff against System.monotonic_time at receipt.
    for _ <- 1..broadcasts do
      sent_at = System.monotonic_time(:microsecond)
      CentrePubSub.broadcast(centre_id, {:bench_msg, sent_at})
    end

    # Collect samples — expect subscribers * broadcasts.
    expected = subscribers * broadcasts

    latencies =
      Enum.reduce_while(1..expected, [], fn _, acc ->
        receive do
          {:sample, us} -> {:cont, [us | acc]}
        after
          10_000 -> {:halt, acc}
        end
      end)

    # Subscribers are done; let them exit gracefully.
    Enum.each(pids, &Process.exit(&1, :normal))

    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    summarise(latencies, subscribers, broadcasts, elapsed_ms)
  end

  # --- subscriber implementation ----------------------------------

  defp subscriber_loop(parent, centre_id, expected_msgs) do
    :ok = CentrePubSub.subscribe(centre_id)
    send(parent, :ready)
    receive_loop(parent, expected_msgs)
  end

  defp receive_loop(_parent, 0), do: :ok

  defp receive_loop(parent, remaining) do
    receive do
      {:bench_msg, sent_at} ->
        latency = System.monotonic_time(:microsecond) - sent_at
        send(parent, {:sample, latency})
        receive_loop(parent, remaining - 1)

      _other ->
        receive_loop(parent, remaining)
    end
  end

  # --- summary ----------------------------------------------------

  defp summarise([], subscribers, broadcasts, elapsed_ms) do
    %{
      subscribers: subscribers,
      broadcasts: broadcasts,
      delivered_samples: 0,
      p50_us: 0,
      p95_us: 0,
      p99_us: 0,
      max_us: 0,
      elapsed_ms: elapsed_ms
    }
  end

  defp summarise(latencies, subscribers, broadcasts, elapsed_ms) do
    sorted = Enum.sort(latencies)
    n = length(sorted)

    %{
      subscribers: subscribers,
      broadcasts: broadcasts,
      delivered_samples: n,
      p50_us: percentile(sorted, 0.50),
      p95_us: percentile(sorted, 0.95),
      p99_us: percentile(sorted, 0.99),
      max_us: List.last(sorted),
      elapsed_ms: elapsed_ms
    }
  end

  defp percentile(sorted, p) when is_list(sorted) and p > 0 and p <= 1 do
    n = length(sorted)
    idx = max(0, trunc(:math.ceil(n * p)) - 1)
    Enum.at(sorted, idx)
  end
end
