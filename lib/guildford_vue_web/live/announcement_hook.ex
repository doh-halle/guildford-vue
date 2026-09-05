defmodule GuildfordVueWeb.Live.AnnouncementHook do
  @moduledoc """
  LiveView `on_mount` hook that assigns `:current_announcement`
  and subscribes to live updates so a posted/cleared banner
  refreshes without a page reload.
  """
  import Phoenix.Component, only: [assign: 3]

  alias GuildfordVue.Announcements

  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket), do: Announcements.subscribe()

    socket =
      socket
      |> assign(:current_announcement, Announcements.current())
      |> Phoenix.LiveView.attach_hook(
        :announcement_changed,
        :handle_info,
        &handle_announcement_change/2
      )

    {:cont, socket}
  end

  defp handle_announcement_change({:announcement_changed, current}, socket) do
    {:halt, assign(socket, :current_announcement, current)}
  end

  defp handle_announcement_change(_, socket), do: {:cont, socket}
end
