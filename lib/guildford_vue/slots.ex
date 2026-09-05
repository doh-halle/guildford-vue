defmodule GuildfordVue.Slots do
  @moduledoc """
  Slots context — durable storage layer for exam slots. Per-centre
  GenServer (Sprint 4 Slice 2) holds the authoritative in-memory
  inventory and writes through to this context.

  Context is the persistence boundary; the GenServer is the
  concurrency boundary. Together they preserve the
  no-double-booking invariant PRD §2.2 promises.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.AuditLog
  alias GuildfordVue.ExamCentres
  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.Exams
  alias GuildfordVue.Repo
  alias GuildfordVue.Slots.Slot

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t() | atom()}

  @doc """
  Creates a slot. Centre must currently offer the exam; otherwise
  `{:error, :exam_not_offered}` so the LV can surface the right
  flash without leaking which exams the centre has historically
  offered.

  Writes a `slot_created` audit event with the centre as actor.
  """
  @spec create_slot(ExamCentre.t(), map()) :: result(Slot.t())
  def create_slot(%ExamCentre{} = centre, attrs) when is_map(attrs) do
    attrs = Map.put(attrs, "exam_centre_id", centre.id)
    exam_id = attrs["exam_id"]

    if exam_id && offers?(centre, exam_id) do
      Multi.new()
      |> Multi.insert(:slot, Slot.create_changeset(%Slot{}, attrs))
      |> Multi.run(:audit, fn _repo, %{slot: s} ->
        exam = Exams.get_exam!(s.exam_id)

        AuditLog.append(:slot_created, %{
          aggregate_id: s.id,
          actor: %{id: centre.id, type: "exam_centre"},
          payload: %{
            centre_email: centre.email,
            exam_id: s.exam_id,
            exam_code: exam.code,
            starts_at: DateTime.to_iso8601(s.starts_at),
            capacity: s.capacity
          }
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{slot: s}} -> {:ok, s}
        {:error, :slot, %Ecto.Changeset{} = cs, _} -> {:error, cs}
        {:error, _, reason, _} -> {:error, reason}
      end
    else
      {:error, :exam_not_offered}
    end
  end

  defp offers?(centre, exam_id) do
    centre |> ExamCentres.list_offerings() |> Enum.any?(&(&1.id == exam_id))
  end

  @doc """
  Bulk-create slots inside a single transaction. Same validation as
  `create_slot/2` applied to each. The caller assembles the list
  (date+time math is the LV's job in Slice 5).

  Audit logging is per-slot — the bulk-creation surface tells the
  audit log "slot 1, slot 2, ..." rather than one summary.
  """
  @spec bulk_create_slots(ExamCentre.t(), [map()]) ::
          {:ok, [Slot.t()]} | {:error, integer(), term()}
  def bulk_create_slots(%ExamCentre{} = centre, attrs_list) when is_list(attrs_list) do
    Repo.transaction(fn -> reduce_create(centre, attrs_list) end)
    |> case do
      {:ok, slots} when is_list(slots) -> {:ok, slots}
      {:error, {idx, reason}} -> {:error, idx, reason}
    end
  end

  defp reduce_create(centre, attrs_list) do
    attrs_list
    |> Enum.with_index()
    |> Enum.reduce_while([], &accumulate_or_halt(&1, &2, centre))
    |> finalise_bulk_result()
  end

  defp accumulate_or_halt({attrs, idx}, acc, centre) do
    case create_slot(centre, attrs) do
      {:ok, slot} -> {:cont, [slot | acc]}
      {:error, reason} -> {:halt, {:rollback, idx, reason}}
    end
  end

  defp finalise_bulk_result({:rollback, idx, reason}), do: Repo.rollback({idx, reason})
  defp finalise_bulk_result(slots) when is_list(slots), do: Enum.reverse(slots)

  @doc """
  Cancels an open slot. Cancelled is a terminal state — re-opening
  would require creating a new slot.
  """
  @spec cancel_slot(Slot.t(), ExamCentre.t() | Admin.t()) :: result(Slot.t())
  def cancel_slot(%Slot{status: "cancelled"}, _actor), do: {:error, :already_cancelled}

  def cancel_slot(%Slot{} = slot, actor) do
    actor_desc =
      case actor do
        %ExamCentre{id: id, email: email} ->
          %{id: id, type: "exam_centre", email: email}

        %Admin{id: id, email: email} ->
          %{id: id, type: "admin", email: email}
      end

    Multi.new()
    |> Multi.update(:slot, Slot.cancel_changeset(slot))
    |> Multi.run(:audit, fn _repo, %{slot: s} ->
      AuditLog.append(:slot_cancelled, %{
        aggregate_id: s.id,
        actor: Map.take(actor_desc, [:id, :type]),
        payload: %{
          actor_email: actor_desc.email,
          exam_id: s.exam_id,
          starts_at: DateTime.to_iso8601(s.starts_at)
        }
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{slot: s}} -> {:ok, s}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @spec get_slot!(binary()) :: Slot.t()
  def get_slot!(id), do: Repo.get!(Slot, id)

  @doc """
  Lists slots for a centre. Options:
    * `:include_cancelled` — default false
    * `:include_past` — default false (only starts_at >= now)
    * `:limit` — default 200
  """
  @spec list_centre_slots(ExamCentre.t(), keyword()) :: [Slot.t()]
  def list_centre_slots(%ExamCentre{id: id}, opts \\ []) do
    include_cancelled = Keyword.get(opts, :include_cancelled, false)
    include_past = Keyword.get(opts, :include_past, false)
    limit = Keyword.get(opts, :limit, 200)
    now = DateTime.utc_now()

    Slot
    |> where([s], s.exam_centre_id == ^id)
    |> maybe_exclude_cancelled(include_cancelled)
    |> maybe_exclude_past(include_past, now)
    |> order_by([s], asc: s.starts_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_exclude_cancelled(query, true), do: query
  defp maybe_exclude_cancelled(query, false), do: where(query, [s], s.status != "cancelled")

  defp maybe_exclude_past(query, true, _now), do: query
  defp maybe_exclude_past(query, false, now), do: where(query, [s], s.starts_at >= ^now)
end
