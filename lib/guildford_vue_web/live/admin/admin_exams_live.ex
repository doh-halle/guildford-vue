defmodule GuildfordVueWeb.Admin.AdminExamsLive do
  @moduledoc """
  Admin exam catalogue CRUD (PRD §4.4 + §12.2). Three live actions
  on one module so the form's modal-style overlay can share the
  underlying list — `:index`, `:new`, `:edit`.

  - `/backoffice/exams` → list (archive action lives here)
  - `/backoffice/exams/new` → create form
  - `/backoffice/exams/:id/edit` → edit form (`code` field is read-only)
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Exams
  alias GuildfordVue.Exams.Exam

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:exams, Exams.list_exams())}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Exams")
    |> assign(:exam, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    exam = %Exam{}

    socket
    |> assign(:page_title, "New exam")
    |> assign(:exam, exam)
    |> assign(:form, to_form(Exams.change_exam(exam), as: :exam))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    exam = Exams.get_exam!(id)

    socket
    |> assign(:page_title, "Edit #{exam.name}")
    |> assign(:exam, exam)
    |> assign(
      :form,
      to_form(Exams.change_exam(exam, exam_to_form_attrs(exam)), as: :exam)
    )
  end

  defp exam_to_form_attrs(exam) do
    %{
      "name" => exam.name,
      "code" => exam.code,
      "certification_body" => exam.certification_body,
      "description" => exam.description,
      "duration_minutes" => exam.duration_minutes,
      "price_pence" => exam.price_pence
    }
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => %{"q" => q}}, socket) do
    {:noreply,
     socket
     |> assign(:search, q)
     |> assign(:exams, Exams.list_exams(search: q))}
  end

  def handle_event("save", %{"exam" => params}, socket) do
    case socket.assigns.live_action do
      :new ->
        case Exams.create_exam(params, socket.assigns.current_admin) do
          {:ok, _exam} ->
            {:noreply,
             socket
             |> put_flash(:info, "Exam created.")
             |> push_navigate(to: ~p"/backoffice/exams")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, :form, to_form(cs, as: :exam))}
        end

      :edit ->
        case Exams.update_exam(socket.assigns.exam, params, socket.assigns.current_admin) do
          {:ok, _exam} ->
            {:noreply,
             socket
             |> put_flash(:info, "Exam updated.")
             |> push_navigate(to: ~p"/backoffice/exams")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, :form, to_form(cs, as: :exam))}
        end
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    exam = Exams.get_exam!(id)
    {:ok, _} = Exams.archive_exam(exam, socket.assigns.current_admin)

    {:noreply,
     socket
     |> put_flash(:info, "Archived.")
     |> assign(:exams, Exams.list_exams(search: socket.assigns.search))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:exams}>
      <div class="flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Exams</h1>
          <p class="mt-1 text-sm text-ink-500">
            Master catalogue. Centres pick from this list to publish offerings.
          </p>
        </div>
        <.link
          navigate={~p"/backoffice/exams/new"}
          class="rounded-lg bg-orange-700 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-600"
        >
          + New exam
        </.link>
      </div>

      <%= if @form do %>
        <section class="mt-8 rounded-2xl border border-ink-200 bg-white p-6">
          <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">
            {@page_title}
          </h2>

          <.form
            for={@form}
            id="exam-form"
            phx-submit="save"
            class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2"
          >
            <.field label="Name" field={@form[:name]} />
            <.field
              label="Code"
              field={@form[:code]}
              hint="Unique short identifier (e.g. AZ-104). Immutable after creation."
              readonly={@live_action == :edit}
            />
            <.field label="Certification body" field={@form[:certification_body]} />
            <.field
              label="Duration (minutes)"
              field={@form[:duration_minutes]}
              type="number"
            />
            <.field label="Price (pence)" field={@form[:price_pence]} type="number" />
            <div class="sm:col-span-2">
              <.field label="Description" field={@form[:description]} type="textarea" />
            </div>

            <div class="sm:col-span-2 flex gap-2">
              <button
                type="submit"
                class="rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white hover:bg-teal-600"
              >
                Save
              </button>
              <.link
                navigate={~p"/backoffice/exams"}
                class="rounded-lg border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 hover:bg-ink-50"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </section>
      <% end %>

      <%= if @exams == [] do %>
        <div class="mt-8 rounded-2xl border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
          No exams yet. Click "+ New exam" or run <code class="font-mono">mix guildford_vue.seed.exams</code>.
        </div>
      <% else %>
        <div class="mt-8 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-ink-200 bg-ink-50">
              <tr>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Code
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Name
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Body
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Mins
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Price
                </th>
                <th class="px-4 py-2"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-ink-200">
              <%= for e <- @exams do %>
                <tr id={"exam-row-#{e.id}"}>
                  <td class="px-4 py-2 align-top font-mono text-xs text-ink-700">
                    {e.code}
                  </td>
                  <td class="px-4 py-2 align-top text-ink-900">{e.name}</td>
                  <td class="px-4 py-2 align-top text-ink-600">{e.certification_body}</td>
                  <td class="px-4 py-2 align-top text-ink-600">{e.duration_minutes}</td>
                  <td class="px-4 py-2 align-top text-ink-600">
                    £{format_price(e.price_pence)}
                  </td>
                  <td class="px-4 py-2 align-top text-right">
                    <.link
                      navigate={~p"/backoffice/exams/#{e.id}/edit"}
                      class="text-sm font-semibold text-teal-700 hover:underline"
                    >
                      Edit
                    </.link>
                    <button
                      type="button"
                      phx-click="archive"
                      phx-value-id={e.id}
                      data-test-id={"archive-#{e.id}"}
                      data-confirm={"Archive #{e.name}?"}
                      class="ml-3 text-sm font-semibold text-red-700 hover:underline"
                    >
                      Archive
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :hint, :string, default: nil
  attr :type, :string, default: "text"
  attr :readonly, :boolean, default: false

  defp field(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-ink-700" for={@field.id}>
        {@label}
      </label>
      <%= case @type do %>
        <% "textarea" -> %>
          <textarea
            id={@field.id}
            name={@field.name}
            rows="3"
            readonly={@readonly}
            class={input_class(@readonly)}
          ><%= Phoenix.HTML.Form.normalize_value("textarea", @field.value) %></textarea>
        <% _ -> %>
          <input
            id={@field.id}
            name={@field.name}
            type={@type}
            value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
            readonly={@readonly}
            class={input_class(@readonly)}
          />
      <% end %>
      <%= if @hint do %>
        <p class="mt-1 text-xs text-ink-500">{@hint}</p>
      <% end %>
      <%= for {msg, _} <- @field.errors do %>
        <p class="mt-1 text-sm text-red-700">{msg}</p>
      <% end %>
    </div>
    """
  end

  defp input_class(true) do
    "mt-1 block w-full rounded-lg border border-ink-200 bg-ink-50 px-3 py-2 text-ink-700"
  end

  defp input_class(false) do
    "mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
  end

  defp format_price(pence) when is_integer(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end
end
