defmodule GuildfordVue.Centres.Supervisor do
  @moduledoc """
  Top-level supervisor for the per-centre process tree (PRD §2.1
  architecture diagram). Children:

    1. `GuildfordVue.Centres.Registry` — `:via` name lookup for
       CentreServers, started first so registrations succeed.
    2. `GuildfordVue.Centres.DynamicSupervisor` — spawns the
       CentreServer per centre on demand.

  Restart strategy `:rest_for_one`: if the Registry crashes, the
  DynamicSupervisor's children's registrations are invalid, so we
  rebuild the DynamicSupervisor too. If the DynamicSupervisor
  crashes, the Registry is fine on its own.
  """
  use Supervisor

  def start_link(init_arg), do: Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

  @impl true
  def init(_init_arg) do
    children = [
      GuildfordVue.Centres.Registry,
      GuildfordVue.Centres.DynamicSupervisor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
