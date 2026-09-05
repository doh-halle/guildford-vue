defmodule GuildfordVue.Centres.PubSub do
  @moduledoc """
  Centre-scoped PubSub helpers (PRD §4.6 / Sprint 6). The topic
  convention is `"centre:<uuid>"` — one topic per centre, regardless
  of the surface that's subscribed. The CentreServer broadcasts on
  state changes; subscribers (calendar LV, search results LV)
  receive `{:slot_changed, slot}` messages.

  Why a thin wrapper rather than the bare `Phoenix.PubSub` calls?
  Topic-string format drift is a common source of "why isn't my
  client receiving messages" bugs. Centralising the format here
  makes the topic an implementation detail of this module.
  """

  alias Phoenix.PubSub

  @pubsub_name GuildfordVue.PubSub

  @spec topic(binary()) :: String.t()
  def topic(centre_id) when is_binary(centre_id), do: "centre:" <> centre_id

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(centre_id), do: PubSub.subscribe(@pubsub_name, topic(centre_id))

  @spec unsubscribe(binary()) :: :ok
  def unsubscribe(centre_id), do: PubSub.unsubscribe(@pubsub_name, topic(centre_id))

  @spec broadcast(binary(), term()) :: :ok | {:error, term()}
  def broadcast(centre_id, message), do: PubSub.broadcast(@pubsub_name, topic(centre_id), message)
end
