defmodule GuildfordVue.AuditLog do
  @moduledoc """
  Append-only audit log (PRD §4.4 FR-ADMIN-5 + §7.1).

  Public API is **write-only at the context level**: `append/1` and
  `append/3` insert events; `list/1` reads them. There is no public
  `update` or `delete` function. The Stop hook's sprint-gate test
  enforces this contract via `__info__(:functions)` introspection so
  a future developer can't quietly add a delete path.

  ## Storage

  PostgreSQL table `audit_log_events` with a `jsonb` payload column.
  Indexed on `event_type`, `aggregate_id`, `actor_id`, `inserted_at`
  for the admin viewer's typical filter columns.

  ## Why no per-event struct types

  Events are intentionally schemaless at the boundary — the
  `:payload` map is `jsonb`, callers pass whatever Elixir map they
  like, atoms become strings on the JSONB round-trip. This trades
  type safety for forward-compatibility: adding a new event type
  doesn't require a code change in the AuditLog module.
  """
  import Ecto.Query, warn: false

  alias GuildfordVue.AuditLog.Event
  alias GuildfordVue.Repo

  @type append_opts :: %{
          optional(:aggregate_id) => binary(),
          optional(:actor) => %{id: binary(), type: String.t()},
          optional(:payload) => map()
        }

  @doc "Convenience overload: append/1 records a bare event with no actor/payload."
  @spec append(atom() | String.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def append(event_type), do: append(event_type, %{})

  @doc """
  Append an event to the log.

      AuditLog.append(:centre_approved, %{
        aggregate_id: centre.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{centre_name: centre.name}
      })

  Keys in `opts`:
    * `:aggregate_id` — UUID of the entity the event is about
    * `:actor` — %{id: uuid, type: "admin" | "candidate" | "exam_centre"}
    * `:payload` — map serialised as `jsonb` (atom keys become strings)
  """
  @spec append(atom() | String.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def append(event_type, opts) when is_map(opts) do
    actor = Map.get(opts, :actor) || %{}

    attrs = %{
      event_type: to_string(event_type),
      aggregate_id: Map.get(opts, :aggregate_id),
      actor_id: Map.get(actor, :id),
      actor_type: Map.get(actor, :type),
      payload: stringify_keys(Map.get(opts, :payload, %{})),
      inserted_at: DateTime.utc_now()
    }

    %Event{}
    |> Ecto.Changeset.cast(attrs, [
      :event_type,
      :aggregate_id,
      :actor_id,
      :actor_type,
      :payload,
      :inserted_at
    ])
    |> Ecto.Changeset.validate_required([:event_type, :payload, :inserted_at])
    |> Ecto.Changeset.validate_length(:event_type, max: 120)
    |> Repo.insert()
  end

  @doc """
  List events newest-first. Filters and pagination:

    * `:limit` — max rows (default 50)
    * `:event_type` — exact match
    * `:aggregate_id` — exact match
    * `:actor_id` — exact match
    * `:from` — inclusive lower bound on `inserted_at` (`DateTime.t()`)
    * `:to`   — inclusive upper bound on `inserted_at` (`DateTime.t()`)
  """
  @spec list(keyword()) :: [Event.t()]
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Event
    |> maybe_where(:event_type, opts)
    |> maybe_where(:aggregate_id, opts)
    |> maybe_where(:actor_id, opts)
    |> maybe_from(opts)
    |> maybe_to(opts)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_where(query, field, opts) do
    case Keyword.get(opts, field) do
      nil -> query
      value -> where(query, [e], field(e, ^field) == ^value)
    end
  end

  defp maybe_from(query, opts) do
    case Keyword.get(opts, :from) do
      %DateTime{} = at -> where(query, [e], e.inserted_at >= ^at)
      _ -> query
    end
  end

  defp maybe_to(query, opts) do
    case Keyword.get(opts, :to) do
      %DateTime{} = at -> where(query, [e], e.inserted_at <= ^at)
      _ -> query
    end
  end

  # PostgreSQL jsonb stores keys as strings. We normalise at write time so
  # callers can pass atom-keyed maps and `list/1`'s callers can rely on
  # string keys without surprise.
  defp stringify_keys(map) when is_map(map) do
    for {k, v} <- map, into: %{} do
      {to_string(k), stringify_keys(v)}
    end
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
