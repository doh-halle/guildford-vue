defmodule GuildfordVue.Centres do
  @moduledoc """
  Public facade over the per-centre process tree. Callers (LiveViews,
  Slots context, Bookings context in Sprint 7) use this module rather
  than touching the Registry / DynamicSupervisor / CentreServer
  directly.

  Lifecycle:

      {:ok, pid} = Centres.start_centre(centre_id)   # on demand
      {:ok, pid} = Centres.whereis(centre_id)        # lookup
      :ok        = Centres.stop_centre(centre_id)    # shutdown
  """

  alias GuildfordVue.Centres.{CentreServer, DynamicSupervisor, Registry}

  @spec start_centre(binary()) :: {:ok, pid()} | {:error, term()}
  def start_centre(centre_id) when is_binary(centre_id),
    do: DynamicSupervisor.start_child(centre_id)

  @spec whereis(binary()) :: {:ok, pid()} | {:error, :not_running}
  def whereis(centre_id) when is_binary(centre_id), do: Registry.whereis(centre_id)

  @doc """
  Returns the pid for `centre_id`, starting the server on demand
  if it isn't already running. Centres should mostly call this so
  the lazy-start semantics are transparent.
  """
  @spec ensure_started(binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(centre_id) when is_binary(centre_id) do
    case whereis(centre_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_running} -> start_centre(centre_id)
    end
  end

  @spec stop_centre(binary()) :: :ok
  def stop_centre(centre_id) when is_binary(centre_id) do
    case whereis(centre_id) do
      {:ok, pid} ->
        Elixir.DynamicSupervisor.terminate_child(DynamicSupervisor, pid)
        :ok

      {:error, :not_running} ->
        :ok
    end
  end

  # --- convenience pass-throughs to CentreServer -------------------

  defdelegate list_slots(server), to: CentreServer
  defdelegate add_slot(server, slot), to: CentreServer
  defdelegate cancel_slot(server, slot_id, actor), to: CentreServer
  defdelegate reserve_slot(server, slot_id), to: CentreServer
  defdelegate release_slot(server, slot_id), to: CentreServer
end
