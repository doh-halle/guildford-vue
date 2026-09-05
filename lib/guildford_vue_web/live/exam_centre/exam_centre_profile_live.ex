defmodule GuildfordVueWeb.ExamCentre.ExamCentreProfileLive do
  @moduledoc """
  Centre profile self-service editor (PRD §4.3). Editable: name,
  address, contact phone, accreditation evidence URL. Read-only:
  email (auth-scope identity), status (admin-managed).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.ExamCentres

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    centre = socket.assigns.current_exam_centre

    {:ok,
     socket
     |> assign(:page_title, "Centre profile")
     |> assign(:form, to_form(ExamCentres.change_centre_profile(centre), as: :profile))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"profile" => params}, socket) do
    cs =
      socket.assigns.current_exam_centre
      |> ExamCentres.change_centre_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs, as: :profile))}
  end

  def handle_event("save", %{"profile" => params}, socket) do
    case ExamCentres.update_centre_profile(socket.assigns.current_exam_centre, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:current_exam_centre, updated)
         |> assign(:form, to_form(ExamCentres.change_centre_profile(updated), as: :profile))
         |> put_flash(:info, "Profile saved.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :profile))}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell current_exam_centre={@current_exam_centre} active={:profile}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Profile</h1>
      <p class="mt-2 text-sm text-ink-500">
        Update what candidates and admins see about your centre. Email
        and status are managed elsewhere.
      </p>

      <section class="mt-8 max-w-2xl rounded-2xl border border-ink-200 bg-white p-6">
        <dl class="mb-6 grid grid-cols-1 gap-y-2 text-sm sm:grid-cols-3">
          <dt class="font-medium text-ink-500">Email</dt>
          <dd class="sm:col-span-2 font-mono text-ink-700">{@current_exam_centre.email}</dd>
          <dt class="font-medium text-ink-500">Status</dt>
          <dd class="sm:col-span-2 text-ink-700">{@current_exam_centre.status}</dd>
        </dl>

        <.form
          for={@form}
          id="centre-profile-form"
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 gap-4 sm:grid-cols-2"
        >
          <.profile_field label="Centre name" field={@form[:name]} />
          <.profile_field label="Contact phone" field={@form[:contact_phone]} />
          <.profile_field label="Address line 1" field={@form[:address_line_1]} />
          <.profile_field label="Address line 2" field={@form[:address_line_2]} />
          <.profile_field label="City" field={@form[:city]} />
          <.profile_field label="Postcode" field={@form[:postcode]} />
          <div class="sm:col-span-2">
            <.profile_field
              label="Accreditation evidence URL"
              field={@form[:accreditation_evidence_url]}
              type="url"
              hint="A link admins can verify (e.g. a published certificate or letter)."
            />
          </div>

          <div class="sm:col-span-2">
            <button
              type="submit"
              class="rounded-lg bg-indigo-700 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-600"
            >
              Save profile
            </button>
          </div>
        </.form>
      </section>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end

  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :hint, :string, default: nil

  defp profile_field(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-ink-700" for={@field.id}>
        {@label}
      </label>
      <input
        id={@field.id}
        name={@field.name}
        type={@type}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
      />
      <%= if @hint do %>
        <p class="mt-1 text-xs text-ink-500">{@hint}</p>
      <% end %>
      <%= for {msg, _} <- @field.errors do %>
        <p class="mt-1 text-sm text-red-700">{msg}</p>
      <% end %>
    </div>
    """
  end
end
