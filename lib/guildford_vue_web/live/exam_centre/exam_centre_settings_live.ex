defmodule GuildfordVueWeb.ExamCentre.ExamCentreSettingsLive do
  @moduledoc """
  Exam-centre settings page. Sprint 1c version: password-change form only.
  Profile editing (centre name, address, accreditation evidence) lands in
  Sprint 3 alongside centre-profile management.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.ExamCentres

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Exam centre settings")
     |> assign(
       :password_form,
       to_form(%{"current_password" => "", "password" => ""}, as: :password)
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("change_password", %{"password" => params}, socket) do
    %{"current_password" => current, "password" => new} = params

    case ExamCentres.change_password(socket.assigns.current_exam_centre, current, %{
           "password" => new
         }) do
      {:ok, _centre} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated. Please sign in again.")
         |> redirect(to: ~p"/examcenter/logout")}

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
    <GuildfordVueWeb.Layouts.centre_shell
      current_exam_centre={@current_exam_centre}
      active={:dashboard}
    >
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Settings</h1>
      <p class="mt-1 text-sm text-ink-500">Signed in as {@current_exam_centre.email}</p>

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
          id="exam-centre-password-form"
          phx-submit="change_password"
          class="mt-6 space-y-4"
        >
          <div>
            <label class="block text-sm font-medium text-ink-700" for="exam-centre-current-password">
              Current password
            </label>
            <input
              type="password"
              name="password[current_password]"
              id="exam-centre-current-password"
              required
              autocomplete="current-password"
              class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-ink-700" for="exam-centre-new-password">
              New password (at least 12 characters)
            </label>
            <input
              type="password"
              name="password[password]"
              id="exam-centre-new-password"
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
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end
end
