defmodule GuildfordVueWeb.ExamCentre.ExamCentreForgotPasswordLive do
  @moduledoc """
  LiveView for GET /examcenter/forgot-password. The user enters their
  email and gets a generic "if registered, check your email" flash —
  the response is identical whether or not the email exists in the
  database (PRD §9 privacy + OWASP A07 enumeration defence).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{AuthAuditLog, ExamCentres, Hammer}

  # 5 forgot-password attempts per IP per hour (Sprint 11.5 Slice 1).
  @rate_limit_scope "exam-centre-forgot-password"
  @rate_limit_limit 5
  @rate_limit_window_ms 60 * 60 * 1000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: :exam_centre)

    {:ok,
     socket
     |> Hammer.assign_peer_ip()
     |> assign(:page_title, "Forgot password")
     |> assign(:form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("submit", %{"exam_centre" => %{"email" => email}}, socket) do
    case Hammer.check(
           @rate_limit_scope,
           Hammer.socket_ip(socket),
           @rate_limit_limit,
           @rate_limit_window_ms
         ) do
      :allow -> do_submit(socket, email)
      {:deny, retry_after} -> deny(socket, retry_after)
    end
  end

  defp do_submit(socket, email) do
    _ = AuthAuditLog.log_password_reset_requested(:exam_centre, email, Hammer.socket_ip(socket))

    if centre = ExamCentres.get_exam_centre_by_email(email) do
      ExamCentres.deliver_password_reset_instructions(centre, fn token ->
        url(socket, ~p"/examcenter/reset-password/#{token}")
      end)
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "If that email is registered, a password reset link has been sent. Check your inbox."
     )
     |> push_navigate(to: ~p"/examcenter/login")}
  end

  defp deny(socket, retry_after) do
    {:noreply,
     put_flash(socket, :error, "Too many requests. Please try again in #{retry_after}s.")}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Exam centre</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">
        Forgot password
      </h1>
      <p class="mt-2 text-sm text-ink-600">
        Enter your email and we'll send you a reset link.
      </p>

      <.form
        for={@form}
        id="exam-centre-forgot-password-form"
        phx-submit="submit"
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

        <button
          type="submit"
          class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
          phx-disable-with="Sending..."
        >
          Send reset link
        </button>
      </.form>
    </main>
    """
  end
end
