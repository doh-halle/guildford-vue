defmodule GuildfordVueWeb.Admin.AdminAnnouncementsLive do
  @moduledoc """
  Sprint 11 Slice 1 — post / clear the platform-wide broadcast
  banner. Superadmin-only. Audited.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Announcements

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Announcements")
     |> assign(:form, to_form(%{"text" => ""}))
     |> assign(:current, Announcements.current())}
  end

  @impl Phoenix.LiveView
  def handle_event("post", %{"announcement" => %{"text" => text}}, socket) do
    case Announcements.post(text, socket.assigns.current_admin) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:current, Announcements.current())
         |> assign(:form, to_form(%{"text" => ""}))
         |> put_flash(:info, "Announcement posted.")}

      {:error, cs} ->
        {:noreply,
         socket
         |> assign(:form, to_form(Map.put(cs.changes, :text, text), action: :insert))
         |> put_flash(:error, "Could not post: #{inspect(cs.errors)}")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("clear", _, socket) do
    :ok = Announcements.clear()
    {:noreply, socket |> assign(:current, nil) |> put_flash(:info, "Banner cleared.")}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:announcements}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Announcements</h1>
      <p class="mt-2 text-sm text-ink-500">
        Posts a platform-wide banner visible to every signed-in user. Up to 280 characters.
        Only one banner is active at a time — posting a new one supersedes the previous.
      </p>

      <%= if @current do %>
        <section class="mt-6 rounded-2xl border border-amber-300 bg-amber-50 p-4">
          <p class="font-mono text-xs uppercase tracking-widest text-amber-800">Currently posted</p>
          <p class="mt-2 text-sm text-amber-900">{@current.text}</p>
          <button
            type="button"
            phx-click="clear"
            data-test-id="clear-announcement"
            data-confirm="Clear the platform banner? Users will stop seeing it on their next page load."
            class="mt-3 rounded-lg border border-amber-500 px-3 py-1 text-xs font-semibold text-amber-800 hover:bg-amber-100"
          >
            Clear banner
          </button>
        </section>
      <% else %>
        <p class="mt-6 rounded-lg border border-dashed border-ink-300 bg-white p-6 text-center text-sm text-ink-500">
          No banner is currently posted.
        </p>
      <% end %>

      <.form
        for={@form}
        id="announcement-form"
        phx-submit="post"
        class="mt-8 space-y-3"
      >
        <label class="block text-sm font-medium text-ink-700" for="announcement_text">
          New banner text
        </label>
        <textarea
          id="announcement_text"
          name="announcement[text]"
          maxlength="280"
          rows="3"
          class="w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          placeholder="e.g. Scheduled maintenance Friday 22:00–23:00 UTC."
        ></textarea>
        <button
          type="submit"
          data-test-id="post-announcement"
          class="rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white hover:bg-teal-800"
        >
          Post banner
        </button>
      </.form>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end
end
