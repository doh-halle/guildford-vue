defmodule GuildfordVueWeb.ExamCentre.ExamCentreRegistrationLive do
  @moduledoc """
  LiveView rendering GET /examcenter/register.

  Self-service centre registration. New centres land in `:pending`
  (PRD §4.3). On a successful save:
    - Persists the centre via `ExamCentres.register_exam_centre/1`.
    - Redirects to /examcenter/login with the "awaiting admin
      approval" flash.

  No email-verification flow for centres in this slice — admin
  approval IS the verification gate (Sprint 2's centre-approval
  queue will email the centre once approved).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{ExamCentres, Hammer}

  # 5 registration attempts per IP per hour (Sprint 11.5 Slice 1).
  @rate_limit_scope "exam-centre-register"
  @rate_limit_limit 5
  @rate_limit_window_ms 60 * 60 * 1000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns[:current_exam_centre] do
      {:ok, push_navigate(socket, to: ~p"/examcenter/dashboard")}
    else
      changeset = ExamCentres.change_registration(%{})

      {:ok,
       socket
       |> Hammer.assign_peer_ip()
       |> assign(:page_title, "Register your centre")
       |> assign_form(changeset)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"exam_centre" => params}, socket) do
    changeset = ExamCentres.change_registration(params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"exam_centre" => params}, socket) do
    case Hammer.check(
           @rate_limit_scope,
           Hammer.socket_ip(socket),
           @rate_limit_limit,
           @rate_limit_window_ms
         ) do
      :allow ->
        do_save(params, socket)

      {:deny, retry_after} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Too many registration attempts. Please try again in #{retry_after}s."
         )}
    end
  end

  defp do_save(params, socket) do
    case ExamCentres.register_exam_centre(params) do
      {:ok, _centre} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Centre registered. Your registration is awaiting admin approval; we'll email you when approved."
         )
         |> push_navigate(to: ~p"/examcenter/login")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: :exam_centre))
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-2xl px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Exam centre</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">
        Register your centre
      </h1>
      <p class="mt-2 text-sm text-ink-600">
        Already have a centre account?
        <.link
          navigate={~p"/examcenter/login"}
          class="font-semibold text-teal-700 hover:underline"
        >
          Sign in
        </.link>
      </p>

      <.form
        for={@form}
        id="exam-centre-registration-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2"
      >
        <div class="sm:col-span-2">
          <.field field={@form[:name]} label="Centre name" required autocomplete="organization" />
        </div>
        <div class="sm:col-span-2">
          <.field
            field={@form[:email]}
            type="email"
            label="Email"
            required
            autocomplete="email"
          />
        </div>
        <div class="sm:col-span-2">
          <.field
            field={@form[:password]}
            type="password"
            label="Password (at least 12 characters)"
            required
            autocomplete="new-password"
          />
        </div>
        <div class="sm:col-span-2">
          <.field
            field={@form[:address_line_1]}
            label="Address line 1"
            required
            autocomplete="address-line1"
          />
        </div>
        <div class="sm:col-span-2">
          <.field
            field={@form[:address_line_2]}
            label="Address line 2 (optional)"
            autocomplete="address-line2"
          />
        </div>
        <.field field={@form[:city]} label="City" required autocomplete="address-level2" />
        <.field field={@form[:postcode]} label="Postcode" required autocomplete="postal-code" />
        <.field
          field={@form[:contact_phone]}
          type="tel"
          label="Contact phone (optional)"
          autocomplete="tel"
        />

        <div class="sm:col-span-2">
          <button
            type="submit"
            class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
            phx-disable-with="Registering..."
          >
            Register centre
          </button>
        </div>
      </.form>
    </main>
    """
  end

  defp format_error(msg, opts) do
    Enum.reduce(opts, msg, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", stringify(v))
    end)
  end

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v) when is_integer(v), do: Integer.to_string(v)
  defp stringify(v), do: inspect(v)

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :rest, :global, include: ~w(required autocomplete)

  defp field(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-sm font-medium text-ink-700">{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
        {@rest}
      />
      <%= for {msg, opts} <- @field.errors do %>
        <p class="mt-1 text-sm text-orange-700">{format_error(msg, opts)}</p>
      <% end %>
    </div>
    """
  end
end
