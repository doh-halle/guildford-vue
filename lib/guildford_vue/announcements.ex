defmodule GuildfordVue.Announcements do
  @moduledoc """
  Platform-wide broadcast banner (PRD §4.10 Sprint 11 carry-over).

  One "current" banner at a time; posting a new one supersedes
  the previous. Subscribers receive
  `{:announcement_changed, current | nil}` via PubSub on the
  `"announcements"` topic so LiveViews refresh without polling.

  History is preserved in the table — `clear/0` flips a flag in
  the application env (a tombstone newer than the row's
  `inserted_at`) so the audit trail is intact while still
  allowing "clear without delete".
  """
  import Ecto.Query, warn: false

  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.Announcements.Announcement
  alias GuildfordVue.AuditLog
  alias GuildfordVue.Repo

  @pubsub GuildfordVue.PubSub
  @topic "announcements"
  @cleared_at_key {__MODULE__, :cleared_at}

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "Returns the active banner, or nil if none / cleared."
  @spec current() :: Announcement.t() | nil
  def current do
    case {latest(), cleared_at()} do
      {nil, _} -> nil
      {%Announcement{} = a, nil} -> a
      {%Announcement{} = a, %DateTime{} = at} -> apply_tombstone(a, at)
    end
  end

  defp apply_tombstone(%Announcement{} = a, %DateTime{} = cleared_at) do
    if DateTime.compare(cleared_at, a.inserted_at) == :gt, do: nil, else: a
  end

  defp latest do
    Repo.one(from a in Announcement, order_by: [desc: a.inserted_at], limit: 1)
  end

  defp cleared_at, do: :persistent_term.get(@cleared_at_key, nil)

  defp set_cleared_at(at), do: :persistent_term.put(@cleared_at_key, at)

  @doc "Post a new banner. Replaces the current one (history kept)."
  @spec post(String.t(), Admin.t()) ::
          {:ok, Announcement.t()} | {:error, Ecto.Changeset.t()}
  def post(text, %Admin{} = admin) when is_binary(text) do
    %Announcement{}
    |> Announcement.create_changeset(%{text: text, posted_by_admin_id: admin.id})
    |> Repo.insert()
    |> case do
      {:ok, posted} = ok ->
        # New row is newer than any tombstone — clear it so `current/0`
        # returns the post.
        set_cleared_at(nil)

        {:ok, _} =
          AuditLog.append(:announcement_posted, %{
            aggregate_id: posted.id,
            actor: %{id: admin.id, type: "admin"},
            payload: %{text: posted.text}
          })

        broadcast({:announcement_changed, posted})
        ok

      err ->
        err
    end
  end

  @doc """
  Clear the current banner. Records a tombstone in application
  env so `current/0` returns nil without deleting any rows.
  Always returns `:ok` — even when there's nothing to clear, the
  caller doesn't need to know.
  """
  @spec clear() :: :ok
  def clear do
    set_cleared_at(DateTime.utc_now())
    broadcast({:announcement_changed, nil})
    :ok
  end

  defp broadcast(message), do: Phoenix.PubSub.broadcast(@pubsub, @topic, message)
end
