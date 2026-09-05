defmodule GuildfordVueWeb.Admin.AdminVerifyOtpLive do
  @moduledoc """
  Sprint 11.5 Slice 7 — GET /backoffice/verify-otp. Mirror of
  the candidate variant; POSTs to
  `AdminSessionController.verify_otp/2`.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVueWeb.Auth.PendingMfa

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    case PendingMfa.read(session) do
      {:ok, :admin, _challenge_id, _subject_id} ->
        {:ok,
         socket
         |> assign(:page_title, "Verify sign-in code")
         |> assign(:form, to_form(%{"code" => ""}, as: :verify))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Your verification session has expired. Please sign in again.")
         |> redirect(to: ~p"/backoffice/login")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Back office</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">
        Enter your sign-in code
      </h1>
      <p class="mt-2 text-sm text-ink-600">
        We've sent a 6-digit code to your email. Enter it below to finish signing in.
        The code expires in 10 minutes.
      </p>

      <.form
        for={@form}
        id="admin-verify-otp-form"
        action={~p"/backoffice/verify-otp"}
        method="post"
        class="mt-8 space-y-4"
      >
        <div>
          <label for={@form[:code].id} class="block text-sm font-medium text-ink-700">
            6-digit code
          </label>
          <input
            type="text"
            name={@form[:code].name}
            id={@form[:code].id}
            inputmode="numeric"
            autocomplete="one-time-code"
            pattern="\d{6}"
            maxlength="6"
            required
            class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-center font-mono text-2xl tracking-widest text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
          />
        </div>

        <button
          type="submit"
          class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
        >
          Verify and sign in
        </button>
      </.form>
    </main>
    """
  end
end
