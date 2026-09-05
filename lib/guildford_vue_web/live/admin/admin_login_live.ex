defmodule GuildfordVueWeb.Admin.AdminLoginLive do
  @moduledoc """
  LiveView rendering GET /backoffice/login. Mirror of `CandidateLoginLive`
  with two differences:

    * No "Register" link — admins are seeded or invited, not self-registered.
    * Eyebrow + heading reflect the back-office scope.
  """
  use GuildfordVueWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns[:current_admin] do
      {:ok, push_navigate(socket, to: ~p"/backoffice/dashboard")}
    else
      form = to_form(%{"email" => "", "password" => ""}, as: :admin)

      {:ok, assign(socket, form: form, page_title: "Back office sign in"),
       temporary_assigns: [form: form]}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"admin" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :admin))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Back office</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">Sign in</h1>
      <p class="mt-2 text-sm text-ink-600">
        Administrator access is invitation-only. Speak to a superadmin if you need an account.
      </p>

      <.form
        for={@form}
        id="admin-login-form"
        action={~p"/backoffice/login"}
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
            <input type="checkbox" name="admin[remember_me]" value="true" /> Remember me
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
