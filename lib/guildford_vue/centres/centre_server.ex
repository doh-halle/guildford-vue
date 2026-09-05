defmodule GuildfordVue.Centres.CentreServer do
  @moduledoc """
  Per-centre GenServer — the authoritative in-memory holder of one
  centre's slot inventory. PRD §2.2 + §4.3.

  Why a GenServer per centre and not, say, a SELECT FOR UPDATE inside
  one Booking context: the BEAM gives us a mailbox for free. Booking
  requests for centre X are calls to that centre's process, so they
  serialise by construction. No row-locks, no retry storms, no
  optimistic-concurrency conflict path. The dissertation's
  no-double-booking property test (Slice 3) demonstrates the
  invariant under hundreds of concurrent reserve attempts.

  ## State

      %{
        centre_id: binary(),
        slots: %{slot_id => %Slot{}}
      }

  Slots are stored as an `id → %Slot{}` map so updates are O(1). The
  list view is materialised on demand.

  ## API

    * `start_link(centre_id)` — spawn under the DynamicSupervisor.
      Loads existing slots from the DB during `init/1`.
    * `list_slots(server)` — current snapshot.
    * `add_slot(server, slot)` — register a newly-created slot.
    * `cancel_slot(server, slot_id, actor)` — proxies to the
      `Slots` context AND drops the slot from in-memory state.

  The reserve / release primitives land in Slice 3.
  """
  use GenServer

  alias GuildfordVue.Centres.PubSub, as: CentrePubSub
  alias GuildfordVue.Centres.Registry, as: CentresRegistry
  alias GuildfordVue.ExamCentres
  alias GuildfordVue.Repo
  alias GuildfordVue.Slots
  alias GuildfordVue.Slots.Slot

  @type state :: %{centre_id: binary(), slots: %{binary() => Slot.t()}}

  # --- start/stop --------------------------------------------------

  @spec start_link(binary()) :: GenServer.on_start()
  def start_link(centre_id) when is_binary(centre_id) do
    GenServer.start_link(__MODULE__, centre_id, name: CentresRegistry.via(centre_id))
  end

  # --- client API --------------------------------------------------

  @spec list_slots(pid()) :: [Slot.t()]
  def list_slots(server), do: GenServer.call(server, :list_slots)

  @spec add_slot(pid(), Slot.t()) :: :ok
  def add_slot(server, %Slot{} = slot), do: GenServer.call(server, {:add_slot, slot})

  @spec cancel_slot(pid(), binary(), ExamCentres.ExamCentre.t() | map()) ::
          {:ok, Slot.t()} | {:error, term()}
  def cancel_slot(server, slot_id, actor) when is_binary(slot_id) do
    GenServer.call(server, {:cancel_slot, slot_id, actor})
  end

  @doc """
  Atomically reserves one seat on `slot_id`. The GenServer call
  serialises every reserve attempt for this centre, which is the
  whole point of the per-centre process — no double-booking is
  structural, not optimistic-locking.

  Returns:
    * `{:ok, slot}` — reservation succeeded; `slot.available_count`
      is the new value.
    * `{:error, :sold_out}` — capacity exhausted.
    * `{:error, :slot_not_in_inventory}` — unknown / cancelled slot.
  """
  @spec reserve_slot(pid(), binary()) ::
          {:ok, Slot.t()} | {:error, :sold_out | :slot_not_in_inventory}
  def reserve_slot(server, slot_id) when is_binary(slot_id) do
    GenServer.call(server, {:reserve_slot, slot_id})
  end

  @doc """
  Atomically releases one seat back to `slot_id`. Used by the
  booking pipeline (Sprint 7) when a booking fails after the
  reservation step, and by the cancellation flow.

  Returns:
    * `{:ok, slot}` — release succeeded.
    * `{:error, :at_capacity}` — slot is already at full capacity.
    * `{:error, :slot_not_in_inventory}` — unknown / cancelled slot.
  """
  @spec release_slot(pid(), binary()) ::
          {:ok, Slot.t()} | {:error, :at_capacity | :slot_not_in_inventory}
  def release_slot(server, slot_id) when is_binary(slot_id) do
    GenServer.call(server, {:release_slot, slot_id})
  end

  # --- callbacks ---------------------------------------------------

  @impl GenServer
  def init(centre_id) do
    centre = ExamCentres.get_exam_centre!(centre_id)
    slots = Slots.list_centre_slots(centre, include_cancelled: false, include_past: false)

    state = %{
      centre_id: centre_id,
      slots: Map.new(slots, &{&1.id, &1})
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:list_slots, _from, state) do
    {:reply, Map.values(state.slots), state}
  end

  def handle_call({:add_slot, %Slot{} = slot}, _from, state) do
    broadcast(state.centre_id, slot)
    {:reply, :ok, %{state | slots: Map.put(state.slots, slot.id, slot)}}
  end

  def handle_call({:reserve_slot, slot_id}, _from, state) do
    with {:ok, slot} <- Map.fetch(state.slots, slot_id) |> wrap_fetch(),
         true <- slot.available_count > 0 || {:error, :sold_out},
         {:ok, updated} <- Repo.update(Slot.reserve_changeset(slot, 1)) do
      broadcast(state.centre_id, updated)
      {:reply, {:ok, updated}, %{state | slots: Map.put(state.slots, slot_id, updated)}}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:release_slot, slot_id}, _from, state) do
    with {:ok, slot} <- Map.fetch(state.slots, slot_id) |> wrap_fetch(),
         true <- slot.available_count < slot.capacity || {:error, :at_capacity},
         {:ok, updated} <- Repo.update(Slot.release_changeset(slot, 1)) do
      broadcast(state.centre_id, updated)
      {:reply, {:ok, updated}, %{state | slots: Map.put(state.slots, slot_id, updated)}}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:cancel_slot, slot_id, actor}, _from, state) do
    case Map.fetch(state.slots, slot_id) do
      {:ok, slot} ->
        case Slots.cancel_slot(slot, actor) do
          {:ok, cancelled} ->
            broadcast(state.centre_id, cancelled)
            # Cancelled slots leave the in-memory inventory — they're no
            # longer bookable. They remain in DB for audit.
            {:reply, {:ok, cancelled}, %{state | slots: Map.delete(state.slots, slot_id)}}

          {:error, _} = err ->
            {:reply, err, state}
        end

      :error ->
        {:reply, {:error, :slot_not_in_inventory}, state}
    end
  end

  # Every successful state transition fan-outs `{:slot_changed, slot}`
  # to the centre's PubSub topic. Subscribers (calendar LV, search
  # LV) re-render from the included slot snapshot — no extra DB read.
  defp broadcast(centre_id, %Slot{} = slot) do
    CentrePubSub.broadcast(centre_id, {:slot_changed, slot})
  end

  # Map.fetch/2 returns :error; wrap to the {:error, reason} shape so
  # the with-pipelines line up.
  defp wrap_fetch({:ok, _} = ok), do: ok
  defp wrap_fetch(:error), do: {:error, :slot_not_in_inventory}
end
