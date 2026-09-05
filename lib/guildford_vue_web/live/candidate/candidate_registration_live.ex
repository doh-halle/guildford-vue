defmodule GuildfordVueWeb.Candidate.CandidateRegistrationLive do
  @moduledoc """
  LiveView rendering GET /candidate/register.

  Form is wired with `phx-submit="save"` and `phx-change="validate"` —
  this LiveView handles both events directly, no controller round-trip.
  On a successful save:
    - Persists the candidate via `Candidates.register_candidate/1`.
    - Sends the verification email via
      `Candidates.deliver_email_verification_instructions/2`.
    - `push_navigate`s to /candidate/login with a "check your email"
      flash.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{Candidates, Hammer}

  # 5 registration attempts per IP per hour (Sprint 11.5 Slice 1).
  @rate_limit_scope "candidate-register"
  @rate_limit_limit 5
  @rate_limit_window_ms 60 * 60 * 1000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns[:current_candidate] do
      {:ok, push_navigate(socket, to: ~p"/candidate/dashboard")}
    else
      changeset = Candidates.change_registration(%{})

      {:ok,
       socket
       |> Hammer.assign_peer_ip()
       |> assign(:page_title, "Register")
       |> assign_form(changeset)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"candidate" => params}, socket) do
    changeset = Candidates.change_registration(params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"candidate" => params}, socket) do
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
    case Candidates.register_candidate(params) do
      {:ok, candidate} ->
        _ = send_verification_email(socket, candidate)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Account created. Please check your email to verify your address."
         )
         |> push_navigate(to: ~p"/candidate/login")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp send_verification_email(socket, candidate) do
    Candidates.deliver_email_verification_instructions(candidate, fn token ->
      url(socket, ~p"/candidate/verify-email/#{token}")
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: :candidate))
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-6 py-16 sm:py-24">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Candidate</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">Register</h1>
      <p class="mt-2 text-sm text-ink-600">
        Already have an account?
        <.link
          navigate={~p"/candidate/login"}
          class="font-semibold text-teal-700 hover:underline"
        >
          Sign in
        </.link>
      </p>

      <.form
        for={@form}
        id="candidate-registration-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-8 space-y-4"
      >
        <.field field={@form[:first_name]} label="First name" required autocomplete="given-name" />
        <.field field={@form[:last_name]} label="Last name" required autocomplete="family-name" />
        <.field field={@form[:email]} type="email" label="Email" required autocomplete="email" />
        <.field
          field={@form[:password]}
          type="password"
          label="Password (at least 12 characters)"
          required
          autocomplete="new-password"
        />
        <.field field={@form[:phone]} type="tel" label="Phone (optional)" autocomplete="tel" />
        <.field
          field={@form[:postcode]}
          label="Postcode (optional)"
          autocomplete="postal-code"
        />

        <button
          type="submit"
          class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
          phx-disable-with="Registering..."
        >
          Register
        </button>
      </.form>
    </main>
    """
  end

  # Phoenix changesets carry error messages with `%{key}` placeholders
  # that need to be substituted. The default phx.gen.auth uses Gettext for
  # this; we use a plain interpolation since this project is English-only
  # (PRD §14: "Multi-language support" is out of scope).
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
  attr :rest, :global, include: ~w(required autocomplete inputmode)

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
