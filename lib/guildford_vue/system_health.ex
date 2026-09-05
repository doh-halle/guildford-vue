defmodule GuildfordVue.SystemHealth do
  @moduledoc """
  Read-only OTP introspection for the back-office system-health
  panel (PRD §4.10 / Sprint 10 Slice 2). Wraps `Process.info/2`,
  `Supervisor.which_children/1`, and the per-centre `Registry` so
  the LiveView can render the supervision tree, count processes,
  and surface mailbox depths.

  Every public function returns plain data — no GenServer state,
  no caching. The LiveView calls these on a refresh timer.
  """

  @top_supervisor GuildfordVue.Supervisor
  @centres_registry GuildfordVue.Centres.Registry

  @doc "Total live process count on the node."
  @spec process_count() :: non_neg_integer()
  def process_count, do: length(Process.list())

  @doc """
  All running per-centre servers as a list of:

      %{centre_id: binary, pid: pid, mailbox: non_neg_integer,
        status: atom, memory: non_neg_integer}

  Sorted by descending mailbox depth so a backed-up centre is
  the first thing the operator sees.
  """
  @spec running_centres() :: [map()]
  def running_centres do
    Registry.select(@centres_registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {centre_id, pid} -> pid_info(centre_id, pid) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.mailbox, :desc)
  end

  defp pid_info(centre_id, pid) do
    case Process.info(pid, [:message_queue_len, :status, :memory]) do
      nil ->
        nil

      info ->
        %{
          centre_id: centre_id,
          pid: pid,
          mailbox: Keyword.fetch!(info, :message_queue_len),
          status: Keyword.fetch!(info, :status),
          memory: Keyword.fetch!(info, :memory)
        }
    end
  end

  @doc """
  Nested map of the live supervision tree, rooted at the
  application's top supervisor.

      %{name: GuildfordVue.Supervisor, pid: #PID<…>,
        children: [%{name: …, pid: …, type: …, children: […]} | …]}
  """
  @spec supervision_tree() :: map()
  def supervision_tree do
    walk(@top_supervisor)
  end

  defp walk(name_or_pid) do
    pid = resolve_pid(name_or_pid)

    %{
      name: registered_name(pid) || name_or_pid,
      pid: pid,
      type: process_type(pid),
      children: children_of(pid)
    }
  end

  defp resolve_pid(pid) when is_pid(pid), do: pid
  defp resolve_pid(name) when is_atom(name), do: Process.whereis(name)

  defp registered_name(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, []} -> nil
      {:registered_name, name} -> name
      _ -> nil
    end
  end

  defp registered_name(_), do: nil

  defp process_type(pid) when is_pid(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :"$initial_call") do
          {:supervisor, _, _} -> :supervisor
          {Supervisor, _, _} -> :supervisor
          {DynamicSupervisor, _, _} -> :dynamic_supervisor
          _ -> :worker
        end

      _ ->
        :worker
    end
  end

  defp process_type(_), do: :unknown

  defp children_of(pid) when is_pid(pid) do
    if supervisor?(pid) do
      pid
      |> Supervisor.which_children()
      |> Enum.map(&child_summary/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp children_of(_), do: []

  defp supervisor?(pid) do
    process_type(pid) in [:supervisor, :dynamic_supervisor]
  end

  defp child_summary({id, pid, type, _modules}) do
    %{
      name: (is_pid(pid) && registered_name(pid)) || id,
      pid: if(is_pid(pid), do: pid, else: nil),
      type: type,
      children: if(is_pid(pid) and supervisor?(pid), do: children_of(pid), else: [])
    }
  end
end
