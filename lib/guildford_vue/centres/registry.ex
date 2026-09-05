defmodule GuildfordVue.Centres.Registry do
  @moduledoc """
  Name registry for per-centre `CentreServer` processes. One entry
  per centre keyed by `centre_id` (binary). Built on `Registry` with
  `unique` keys so `whereis` is O(1).

  Started under `GuildfordVue.Centres.Supervisor` ahead of the
  DynamicSupervisor so registrations land successfully on
  CentreServer init.
  """

  @doc "Spec helper for the application supervisor."
  def child_spec(_), do: Registry.child_spec(keys: :unique, name: __MODULE__)

  @doc "Returns a `:via` tuple used when registering / looking up by centre id."
  @spec via(binary()) :: {:via, Registry, {__MODULE__, binary()}}
  def via(centre_id) when is_binary(centre_id), do: {:via, Registry, {__MODULE__, centre_id}}

  @spec whereis(binary()) :: {:ok, pid()} | {:error, :not_running}
  def whereis(centre_id) when is_binary(centre_id) do
    case Registry.lookup(__MODULE__, centre_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_running}
    end
  end
end
