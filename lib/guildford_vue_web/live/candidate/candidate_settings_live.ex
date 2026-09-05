defmodule GuildfordVueWeb.Candidate.CandidateSettingsLive do
  @moduledoc """
  Candidate settings page. Two side-by-side forms:

    * **Profile** — update first/last name, phone, postcode.
    * **Password** — rotate password (requires current password as
      proof of knowledge so a stolen session cannot rotate the
      password without re-authenticating).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Candidates

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    candidate = socket.assigns.current_candidate

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:profile_form, to_form(Candidates.change_profile(candidate), as: :profile))
     |> assign(
       :password_form,
       to_form(%{"current_password" => "", "password" => ""}, as: :password)
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("update_profile", %{"profile" => params}, socket) do
    case Candidates.update_profile(socket.assigns.current_candidate, params) do
      {:ok, candidate} ->
        {:noreply,
         socket
         |> assign(:current_candidate, candidate)
         |> assign(:profile_form, to_form(Candidates.change_profile(candidate), as: :profile))
         |> put_flash(:info, "Profile updated.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)
        {:noreply, assign(socket, :profile_form, to_form(changeset, as: :profile))}
    end
  end

  def handle_event("change_password", %{"password" => params}, socket) do
    %{"current_password" => current, "password" => new} = params

    case Candidates.change_password(socket.assigns.current_candidate, current, %{
           "password" => new
         }) do
      {:ok, _candidate} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated. Please sign in again.")
         |> redirect(to: ~p"/candidate/logout")}

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
    <main class="mx-auto max-w-container px-6 py-12 sm:px-10">
      <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Candidate</p>
      <h1 class="mt-4 font-sans text-3xl font-bold tracking-tight text-ink-900">Settings</h1>

      <div class="mt-10 grid grid-cols-1 gap-8 lg:grid-cols-2">
        <section
          aria-labelledby="profile-form-heading"
          class="rounded-2xl border border-ink-200 bg-white p-6"
        >
          <h2
            id="profile-form-heading"
            class="font-sans text-xl font-bold tracking-tight text-ink-900"
          >
            Profile
          </h2>

          <.form
            for={@profile_form}
            id="candidate-profile-form"
            phx-submit="update_profile"
            class="mt-6 space-y-4"
          >
            <.field
              field={@profile_form[:first_name]}
              label="First name"
              required
              autocomplete="given-name"
            />
            <.field
              field={@profile_form[:last_name]}
              label="Last name"
              required
              autocomplete="family-name"
            />
            <.field field={@profile_form[:phone]} type="tel" label="Phone" autocomplete="tel" />
            <.field
              field={@profile_form[:postcode]}
              label="Postcode"
              autocomplete="postal-code"
            />

            <button
              type="submit"
              class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
              phx-disable-with="Saving..."
            >
              Save profile
            </button>
          </.form>
        </section>

        <section
          aria-labelledby="password-form-heading"
          class="rounded-2xl border border-ink-200 bg-white p-6"
        >
          <h2
            id="password-form-heading"
            class="font-sans text-xl font-bold tracking-tight text-ink-900"
          >
            Change password
          </h2>
          <p class="mt-2 text-sm text-ink-500">
            You'll be signed out after a successful change.
          </p>

          <.form
            for={@password_form}
            id="candidate-password-form"
            phx-submit="change_password"
            class="mt-6 space-y-4"
          >
            <.field
              field={@password_form[:current_password]}
              type="password"
              label="Current password"
              required
              autocomplete="current-password"
            />
            <.field
              field={@password_form[:password]}
              type="password"
              label="New password (at least 12 characters)"
              required
              autocomplete="new-password"
            />

            <button
              type="submit"
              class="w-full rounded-lg bg-teal-700 px-6 py-3 font-sans font-semibold text-white shadow-sm transition hover:bg-teal-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
              phx-disable-with="Updating..."
            >
              Update password
            </button>
          </.form>
        </section>
      </div>
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
