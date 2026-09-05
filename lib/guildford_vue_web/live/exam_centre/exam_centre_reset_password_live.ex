defmodule GuildfordVueWeb.ExamCentre.ExamCentreResetPasswordLive do
  @moduledoc """
  LiveView for GET /examcenter/reset-password/:token. Renders the new-
  password form for a still-valid token, or an "invalid/expired"
  message otherwise.

  Token consumption only happens on phx-submit "save". The double
  LiveView mount is harmless here because mount only QUERIES the token
  via `get_candidate_by_reset_token/1` (no DB writes).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{AuthAuditLog, ExamCentres, Hammer}

  @impl Phoenix.LiveView
  def mount(%{"token" => token}, _session, socket) do
    case ExamCentres.get_exam_centre_by_reset_token(token) do
      nil ->
        {:ok, assign(socket, status: :invalid_token, page_title: "Invalid reset link")}

      _candidate ->
        form = to_form(%{"password" => ""}, as: :exam_centre)

        {:ok,
         socket
         |> Hammer.assign_peer_ip()
         |> assign(:status, :valid)
         |> assign(:token, token)
         |> assign(:page_title, "Reset your password")
         |> assign(:form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"exam_centre" => params}, socket) do
    case ExamCentres.reset_password(socket.assigns.token, params) do
      {:ok, centre} ->
        _ =
          AuthAuditLog.log_password_reset_completed(
            :exam_centre,
            centre.id,
            Hammer.socket_ip(socket)
          )

        {:noreply,
         socket
         |> put_flash(:info, "Password updated. You can now sign in.")
         |> push_navigate(to: ~p"/examcenter/login")}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        {:noreply, assign(socket, form: to_form(changeset, as: :exam_centre))}

      {:error, :invalid_token} ->
        {:noreply, assign(socket, status: :invalid_token)}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Exam centre</p>

      <%= case @status do %>
        <% :valid -> %>
          <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">
            Reset your password
          </h1>
          <p class="mt-2 text-sm text-ink-600">
            Pick a new password of at least 12 characters.
          </p>

          <.form
            for={@form}
            id="exam-centre-reset-password-form"
            phx-submit="save"
            class="mt-8 space-y-4"
          >
            <div>
              <label for={@form[:password].id} class="block text-sm font-medium text-ink-700">
                New password
              </label>
              <input
                type="password"
                name={@form[:password].name}
                id={@form[:password].id}
                required
                autocomplete="new-password"
                class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
              />
              <%= for {msg, opts} <- @form[:password].errors do %>
                <p class="mt-1 text-sm text-orange-700">{format_error(msg, opts)}</p>
              <% end %>
            </div>

            <button
              type="submit"
              class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
              phx-disable-with="Saving..."
            >
              Save new password
            </button>
          </.form>
        <% :invalid_token -> %>
          <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">
            Reset link is invalid or expired
          </h1>
          <p class="mt-2 text-sm text-ink-600">
            Reset links expire 24 hours after they're issued. Request a new one from the
            <.link
              navigate={~p"/examcenter/forgot-password"}
              class="font-semibold text-teal-700 hover:underline"
            >
              forgot-password page
            </.link>
            and try again.
          </p>
      <% end %>
    </main>
    """
  end

  defp format_error(msg, opts) do
    Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", stringify(v)) end)
  end

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v) when is_integer(v), do: Integer.to_string(v)
  defp stringify(v), do: inspect(v)
end
