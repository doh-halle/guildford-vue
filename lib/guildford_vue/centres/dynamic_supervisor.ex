defmodule GuildfordVue.Centres.DynamicSupervisor do
  @moduledoc """
  Supervises the per-centre `CentreServer` processes. Centres are
  spawned on demand (first booking / first slot creation) via
  `GuildfordVue.Centres.start_centre/1`, not eagerly at boot — a
  100-centre seed wouldn't want 100 idle GenServers.

  `:one_for_one` restart strategy: a crashed centre brings only
  itself back up, with state reloaded from the DB during `init/1`.
  """
  use DynamicSupervisor

  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Starts a CentreServer for `centre_id`. If one already exists,
  returns its pid (idempotent). Crashes during start are returned
  as `{:error, reason}` rather than raised.
  """
  @spec start_child(binary()) :: {:ok, pid()} | {:error, term()}
  def start_child(centre_id) when is_binary(centre_id) do
    spec = {GuildfordVue.Centres.CentreServer, centre_id}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} = err -> err
    end
  end
end
