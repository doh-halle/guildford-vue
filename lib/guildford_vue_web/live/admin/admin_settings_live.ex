defmodule GuildfordVueWeb.Admin.AdminSettingsLive do
  @moduledoc """
  Admin settings page. Sprint 1c version: password-change form only.
  Profile editing (name, role) lives in Sprint 2's admin-user
  management surface since it touches authorisation policy.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Admins

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Back-office settings")
     |> assign(
       :password_form,
       to_form(%{"current_password" => "", "password" => ""}, as: :password)
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("change_password", %{"password" => params}, socket) do
    %{"current_password" => current, "password" => new} = params

    case Admins.change_password(socket.assigns.current_admin, current, %{"password" => new}) do
      {:ok, _admin} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated. Please sign in again.")
         |> redirect(to: ~p"/backoffice/logout")}

      {:error, :invalid_current_password} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your current password is incorrect.")
         |> assign(
           :password_form,
           to_form(%{"current_password" => "", "password" => ""}, as: :password)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        {:noreply, assign(socket, :password_form, to_form(changeset, as: :password))}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:dashboard}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Settings</h1>
      <p class="mt-1 text-sm text-ink-500">Signed in as {@current_admin.email}</p>

      <section
        aria-labelledby="password-form-heading"
        class="mt-10 max-w-md rounded-2xl border border-ink-200 bg-white p-6"
      >
        <h2
          id="password-form-heading"
          class="font-sans text-xl font-bold tracking-tight text-ink-900"
        >
          Change password
        </h2>
        <p class="mt-2 text-sm text-ink-500">You'll be signed out after a successful change.</p>

        <.form
          for={@password_form}
          id="admin-password-form"
          phx-submit="change_password"
          class="mt-6 space-y-4"
        >
          <div>
            <label class="block text-sm font-medium text-ink-700" for="admin-current-password">
              Current password
            </label>
            <input
              type="password"
              name="password[current_password]"
              id="admin-current-password"
              required
              autocomplete="current-password"
              class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-ink-700" for="admin-new-password">
              New password (at least 12 characters)
            </label>
            <input
              type="password"
              name="password[password]"
              id="admin-new-password"
              required
              autocomplete="new-password"
              class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
            />
          </div>

          <button
            type="submit"
            class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
            phx-disable-with="Updating..."
          >
            Update password
          </button>
        </.form>
      </section>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end
end
