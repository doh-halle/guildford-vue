defmodule GuildfordVue.AuditLog.Event do
  @moduledoc """
  Append-only audit-log event. PRD §7.1 schema:

      audit_log_events
        id          binary_id   pk
        event_type  string      (e.g. "centre_approved")
        aggregate_id binary_id  (the entity the event is about)
        actor_id    binary_id   (the admin / candidate / system that
                                 performed the action; nullable)
        actor_type  string      (the actor's scope: "admin" / "candidate" /
                                 "exam_centre" / nil for system events)
        payload     map         (jsonb — event-specific data)
        inserted_at utc_datetime_usec   (no updated_at — append-only)
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_log_events" do
    field :event_type, :string
    field :aggregate_id, :binary_id
    field :actor_id, :binary_id
    field :actor_type, :string
    field :payload, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
