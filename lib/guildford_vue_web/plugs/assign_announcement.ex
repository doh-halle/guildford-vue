defmodule GuildfordVueWeb.Plugs.AssignAnnouncement do
  @moduledoc """
  Assigns `:current_announcement` on every `:browser_base`
  request so the root layout can render the platform banner
  without each controller having to fetch it.

  LiveViews additionally subscribe via the `on_mount` hook (see
  `GuildfordVueWeb.Live.AnnouncementHook`) so the banner updates
  live without a page reload.
  """
  import Plug.Conn

  alias GuildfordVue.Announcements

  def init(opts), do: opts

  def call(conn, _opts) do
    assign(conn, :current_announcement, Announcements.current())
  end
end
