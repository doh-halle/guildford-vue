defmodule GuildfordVueWeb.Candidate.CandidateLoginLive do
  @moduledoc """
  LiveView rendering GET /candidate/login.

  The form `action` posts to `/candidate/login` (handled by
  `CandidateSessionController.create`) rather than a `handle_event` because
  the resulting session-cookie write must happen on the parent conn —
  LiveView sockets cannot write session cookies.
  """
  use GuildfordVueWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns[:current_candidate] do
      {:ok, push_navigate(socket, to: ~p"/candidate/dashboard")}
    else
      form = to_form(%{"email" => "", "password" => ""}, as: :candidate)
      {:ok, assign(socket, form: form, page_title: "Sign in"), temporary_assigns: [form: form]}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"candidate" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :candidate))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Candidate</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">Sign in</h1>
      <p class="mt-2 text-sm text-ink-600">
        Don't have an account yet?
        <a
          href="/candidate/register"
          class="font-semibold text-teal-700 hover:underline"
          data-test="register-link"
        >
          Register
        </a>
      </p>

      <.form
        for={@form}
        id="candidate-login-form"
        action={~p"/candidate/login"}
        method="post"
        phx-change="validate"
        phx-trigger-action={false}
        class="mt-8 space-y-4"
      >
        <div>
          <label for={@form[:email].id} class="block text-sm font-medium text-ink-700">
            Email
          </label>
          <input
            type="email"
            name={@form[:email].name}
            id={@form[:email].id}
            value={Phoenix.HTML.Form.normalize_value("email", @form[:email].value)}
            required
            autocomplete="email"
            class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
          />
        </div>

        <div>
          <label for={@form[:password].id} class="block text-sm font-medium text-ink-700">
            Password
          </label>
          <input
            type="password"
            name={@form[:password].name}
            id={@form[:password].id}
            required
            autocomplete="current-password"
            class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
          />
        </div>

        <div class="flex items-center justify-between">
          <label class="flex items-center gap-2 text-sm text-ink-700">
            <input type="checkbox" name="candidate[remember_me]" value="true" /> Remember me
          </label>
        </div>

        <button
          type="submit"
          class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
          phx-disable-with="Signing in..."
        >
          Sign in
        </button>
      </.form>
    </main>
    """
  end
end
