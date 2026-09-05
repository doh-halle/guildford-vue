defmodule GuildfordVueWeb.ExamCentre.ExamCentreExamsLive do
  @moduledoc """
  Centre exam-offering picker (PRD §4.3). Checkbox list of every
  live catalogue exam; ticking one means "I offer this", unticking
  it means "I don't". Submit overwrites the centre's offerings;
  the context writes per-exam audit events for the diff.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{ExamCentres, Exams}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    centre = socket.assigns.current_exam_centre

    {:ok,
     socket
     |> assign(:page_title, "My exams")
     |> assign(:exams, Exams.list_exams())
     |> assign(
       :selected_ids,
       ExamCentres.list_offerings(centre) |> Enum.map(& &1.id) |> MapSet.new()
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("save", params, socket) do
    centre = socket.assigns.current_exam_centre
    ids = params |> get_in(["offerings", "exam_ids"]) |> List.wrap()

    {:ok, _offerings} = ExamCentres.set_offerings(centre, ids, centre)

    {:noreply,
     socket
     |> put_flash(:info, "Offerings saved.")
     |> assign(:selected_ids, MapSet.new(ids))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell current_exam_centre={@current_exam_centre} active={:exams}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Exams I offer</h1>
      <p class="mt-2 text-sm text-ink-500">
        Pick from the platform catalogue. Candidates will see your centre
        when searching for any exam ticked here.
      </p>

      <.form
        for={%{}}
        id="offerings-form"
        phx-submit="save"
        class="mt-8 max-w-3xl rounded-2xl border border-ink-200 bg-white p-6"
      >
        <fieldset>
          <legend class="font-sans text-sm font-semibold text-ink-900">
            Catalogue ({length(@exams)} exams)
          </legend>

          <%= if @exams == [] do %>
            <p class="mt-4 text-sm text-ink-500">
              No exams in the catalogue yet. Ask an admin to add some.
            </p>
          <% else %>
            <ul class="mt-4 divide-y divide-ink-200">
              <%= for exam <- @exams do %>
                <li class="flex items-start gap-3 py-3">
                  <input
                    type="checkbox"
                    id={"offer-#{exam.id}"}
                    name="offerings[exam_ids][]"
                    value={exam.id}
                    checked={MapSet.member?(@selected_ids, exam.id)}
                    class="mt-1 size-4 rounded border-ink-300 text-indigo-700 focus:ring-indigo-500"
                  />
                  <label for={"offer-#{exam.id}"} class="flex-1 cursor-pointer">
                    <span class="block font-semibold text-ink-900">{exam.name}</span>
                    <span class="font-mono text-xs text-ink-500">
                      {exam.code} · {exam.certification_body} · {exam.duration_minutes} min
                    </span>
                  </label>
                </li>
              <% end %>
            </ul>
          <% end %>
        </fieldset>

        <div class="mt-6">
          <button
            type="submit"
            class="rounded-lg bg-indigo-700 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-600"
          >
            Save offerings
          </button>
        </div>
      </.form>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end
end
