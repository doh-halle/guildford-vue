defmodule GuildfordVueWeb.ExamCentre.ExamCentreLoginLive do
  @moduledoc """
  LiveView rendering GET /examcenter/login. Mirror of `CandidateLoginLive`
  with the eyebrow + heading set to "Exam centre". Registration is
  self-service for centres (Sprint 1c will add `ExamCentreRegistrationLive`),
  so the "Register" link is present here unlike admin login.
  """
  use GuildfordVueWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns[:current_exam_centre] do
      {:ok, push_navigate(socket, to: ~p"/examcenter/dashboard")}
    else
      form = to_form(%{"email" => "", "password" => ""}, as: :exam_centre)

      {:ok, assign(socket, form: form, page_title: "Exam centre sign in"),
       temporary_assigns: [form: form]}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"exam_centre" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :exam_centre))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Exam centre</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">Sign in</h1>
      <p class="mt-2 text-sm text-ink-600">
        Don't have an account yet?
        <a
          href="/examcenter/register"
          class="font-semibold text-teal-700 hover:underline"
          data-test="register-link"
        >
          Register your centre
        </a>
      </p>

      <.form
        for={@form}
        id="exam-centre-login-form"
        action={~p"/examcenter/login"}
        method="post"
        phx-change="validate"
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
            <input type="checkbox" name="exam_centre[remember_me]" value="true" /> Remember me
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
