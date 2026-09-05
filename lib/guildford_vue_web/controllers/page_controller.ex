defmodule GuildfordVueWeb.PageController do
  use GuildfordVueWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
