defmodule GuildfordVueWeb.ExamCentre.ExamCentreSlotsLive do
  @moduledoc """
  Centre-side slot management. Two live actions in one module so
  the layout, sidebar highlight, and data plumbing are shared:

    * `:index` — list upcoming slots. Listing + per-row cancel land
      properly in Sprint 4 Slice 6; this slice (Slice 4) ships a
      simple table.
    * `:new` — single-slot creation form (this slice).

  Bulk creation arrives at `/examcenter/slots/bulk` in Slice 5.

  ## Form date/time handling

  The form takes a `:date` + `:time` pair (HTML inputs) which we
  combine into a `:starts_at` `DateTime` and derive `:ends_at` from
  the form's `:duration_minutes` (defaulting to the exam's
  catalogue duration). This keeps the calendar UX natural without
  the LV having to introspect timezone state — everything is UTC
  at the boundary.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{Centres, ExamCentres, Exams, Slots}
  alias GuildfordVue.Centres.PubSub, as: CentrePubSub
  alias GuildfordVue.Slots.{Recurrence, Slot}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    centre = socket.assigns.current_exam_centre

    if connected?(socket), do: CentrePubSub.subscribe(centre.id)

    {:ok,
     socket
     |> assign(:page_title, "Slots")
     |> assign(:offerings, ExamCentres.list_offerings(centre))
     |> assign(:slots, Slots.list_centre_slots(centre))
     |> assign(:form, blank_form())}
  end

  @impl Phoenix.LiveView
  def handle_info({:slot_changed, %Slot{} = updated}, socket) do
    {:noreply, assign(socket, :slots, upsert_slot(socket.assigns.slots, updated))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp upsert_slot(slots, %Slot{id: id} = new) do
    if Enum.any?(slots, &(&1.id == id)) do
      Enum.map(slots, fn
        %Slot{id: ^id} -> new
        other -> other
      end)
    else
      slots
    end
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :index) do
    socket
    |> assign(:page_title, "Slots")
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new) do
    socket
    |> assign(:page_title, "New slot")
    |> assign(:form, blank_form())
  end

  defp apply_action(socket, :bulk) do
    socket
    |> assign(:page_title, "Bulk slots")
    |> assign(:bulk_form, blank_bulk_form())
    |> assign(:bulk_error, nil)
  end

  defp blank_bulk_form do
    to_form(
      %{
        "exam_id" => "",
        "start_date" => "",
        "end_date" => "",
        "times" => [],
        "weekdays" => [],
        "duration_minutes" => "",
        "capacity" => ""
      },
      as: :bulk
    )
  end

  defp blank_form do
    to_form(
      %{
        "exam_id" => "",
        "date" => "",
        "time" => "",
        "duration_minutes" => "",
        "capacity" => ""
      },
      as: :slot
    )
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"slot" => params}, socket) do
    centre = socket.assigns.current_exam_centre

    case build_slot_attrs(params) do
      {:ok, attrs} ->
        case Slots.create_slot(centre, attrs) do
          {:ok, slot} ->
            register_with_genserver(centre, slot)

            {:noreply,
             socket
             |> put_flash(:info, "Slot published.")
             |> assign(:slots, Slots.list_centre_slots(centre))
             |> push_navigate(to: ~p"/examcenter/slots")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, :form, to_form(cs, as: :slot, action: :insert))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not create slot: #{inspect(reason)}")}
        end

      {:error, msg} ->
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("cancel_slot", %{"id" => id}, socket) do
    centre = socket.assigns.current_exam_centre

    # Route the cancel through the GenServer so the in-memory inventory
    # is updated alongside the DB row + audit event.
    {:ok, pid} = Centres.ensure_started(centre.id)

    case Centres.cancel_slot(pid, id, centre) do
      {:ok, _cancelled} ->
        # Stub: candidate-notification job runs here in Sprint 7.
        :ok

        {:noreply,
         socket
         |> put_flash(:info, "Slot cancelled.")
         |> assign(:slots, Slots.list_centre_slots(centre))}

      {:error, :slot_not_in_inventory} ->
        # Already cancelled / unknown — fall back to direct cancel via context
        # so the page still gets an honest result.
        case Slots.get_slot!(id) |> Slots.cancel_slot(centre) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Slot cancelled.")
             |> assign(:slots, Slots.list_centre_slots(centre))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Cancel failed: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cancel failed: #{inspect(reason)}")}
    end
  end

  def handle_event("bulk_save", %{"bulk" => params}, socket) do
    centre = socket.assigns.current_exam_centre

    with {:ok, spec} <- parse_bulk_params(params),
         starts when starts != [] <- Recurrence.expand(spec),
         attrs_list = build_bulk_attrs(starts, spec, params),
         {:ok, slots} <- bulk_publish(centre, attrs_list) do
      {:noreply,
       socket
       |> put_flash(:info, "Published #{length(slots)} slot(s).")
       |> push_navigate(to: ~p"/examcenter/slots")}
    else
      [] ->
        {:noreply,
         assign(
           socket,
           :bulk_error,
           "Schedule matched zero dates — check date range and weekdays."
         )}

      {:error, msg} when is_binary(msg) ->
        {:noreply, assign(socket, :bulk_error, msg)}

      {:error, idx, reason} ->
        {:noreply, assign(socket, :bulk_error, "Row #{idx + 1} failed: #{inspect(reason)}")}
    end
  end

  defp build_slot_attrs(%{"date" => date_s, "time" => time_s} = params)
       when is_binary(date_s) and is_binary(time_s) and date_s != "" and time_s != "" do
    with {:ok, date} <- Date.from_iso8601(date_s),
         {:ok, time} <- parse_time(time_s),
         {:ok, naive} <- NaiveDateTime.new(date, time),
         {:ok, dt} <- DateTime.from_naive(naive, "Etc/UTC") do
      duration =
        params
        |> Map.get("duration_minutes", "")
        |> parse_int(60)

      ends_at = DateTime.add(dt, duration * 60, :second)

      {:ok,
       %{
         "exam_id" => Map.get(params, "exam_id"),
         "starts_at" => dt,
         "ends_at" => ends_at,
         "capacity" => parse_int(Map.get(params, "capacity", ""), 0)
       }}
    else
      _ -> {:error, "Please enter a valid date and time."}
    end
  end

  defp build_slot_attrs(_), do: {:error, "Date and time are required."}

  # HTML5 `<input type="time">` sends "HH:MM" without seconds; tests
  # may pass full ISO times like "HH:MM:SS.fffff". Accept both.
  defp parse_time(s) when is_binary(s) do
    if String.match?(s, ~r/^\d{2}:\d{2}$/) do
      Time.from_iso8601(s <> ":00")
    else
      Time.from_iso8601(s)
    end
  end

  defp parse_int(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  defp bulk_publish(centre, attrs_list) do
    case Slots.bulk_create_slots(centre, attrs_list) do
      {:ok, slots} ->
        for s <- slots, do: register_with_genserver(centre, s)
        {:ok, slots}

      other ->
        other
    end
  end

  defp parse_bulk_params(params) do
    weekdays =
      params
      |> Map.get("weekdays", [])
      |> List.wrap()
      |> Enum.map(&parse_int(&1, 0))
      |> Enum.filter(&(&1 in 1..7))

    times =
      params
      |> Map.get("times", [])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    cond do
      weekdays == [] ->
        {:error, "Select at least one weekday."}

      times == [] ->
        {:error, "Select at least one time."}

      true ->
        with {:ok, start_date} <- date_from(Map.get(params, "start_date")),
             {:ok, end_date} <- date_from(Map.get(params, "end_date")) do
          {:ok,
           %{
             start_date: start_date,
             end_date: end_date,
             weekdays: weekdays,
             times: times
           }}
        else
          _ -> {:error, "Enter a valid date range."}
        end
    end
  end

  defp date_from(""), do: :error
  defp date_from(nil), do: :error
  defp date_from(s) when is_binary(s), do: Date.from_iso8601(s)

  defp build_bulk_attrs(starts, _spec, params) do
    duration = parse_int(Map.get(params, "duration_minutes", "60"), 60)
    capacity = parse_int(Map.get(params, "capacity", "0"), 0)
    exam_id = Map.get(params, "exam_id")

    for dt <- starts do
      %{
        "exam_id" => exam_id,
        "starts_at" => dt,
        "ends_at" => DateTime.add(dt, duration * 60, :second),
        "capacity" => capacity
      }
    end
  end

  defp register_with_genserver(centre, slot) do
    case Centres.ensure_started(centre.id) do
      {:ok, pid} -> Centres.add_slot(pid, slot)
      _ -> :ok
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell current_exam_centre={@current_exam_centre} active={:slots}>
      <div class="flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Slots</h1>
          <p class="mt-1 text-sm text-ink-500">
            Publish bookable exam sessions. Single + bulk creation, edit and cancel.
          </p>
        </div>
        <.link
          navigate={~p"/examcenter/slots/new"}
          class="rounded-lg bg-indigo-700 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-600"
        >
          + New slot
        </.link>
      </div>

      <%= if @live_action == :new do %>
        <.slot_form form={@form} offerings={@offerings} />
      <% end %>

      <%= if @live_action == :bulk do %>
        <.bulk_form form={@bulk_form} offerings={@offerings} error={@bulk_error} />
      <% end %>

      <%= if @live_action == :index do %>
        <div class="mt-4 flex gap-2">
          <.link
            navigate={~p"/examcenter/slots/bulk"}
            class="rounded-lg border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 hover:bg-ink-50"
          >
            Bulk create
          </.link>
        </div>
        <.slot_table slots={@slots} />
      <% end %>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end

  attr :form, :any, required: true
  attr :offerings, :list, required: true

  defp slot_form(assigns) do
    ~H"""
    <section class="mt-8 max-w-2xl rounded-2xl border border-ink-200 bg-white p-6">
      <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">New slot</h2>

      <%= if @offerings == [] do %>
        <p class="mt-4 rounded-lg border border-dashed border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
          You haven't added any exams to your offerings yet, so there are <strong>no exams</strong>
          you can publish slots for. Visit
          <.link navigate={~p"/examcenter/exams"} class="font-semibold underline">
            Exams I offer
          </.link>
          to add one.
        </p>
      <% else %>
        <.form
          for={@form}
          id="slot-form"
          phx-submit="save"
          class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2"
        >
          <div class="sm:col-span-2">
            <label class="block text-sm font-medium text-ink-700" for={@form[:exam_id].id}>
              Exam
            </label>
            <select
              id={@form[:exam_id].id}
              name={@form[:exam_id].name}
              class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            >
              <option value="">— pick one —</option>
              <%= for exam <- @offerings do %>
                <option value={exam.id} selected={@form[:exam_id].value == exam.id}>
                  {exam.name} ({exam.code} · {exam.duration_minutes} min)
                </option>
              <% end %>
            </select>
          </div>

          <.field label="Date" field={@form[:date]} type="date" />
          <.field label="Start time" field={@form[:time]} type="time" />
          <.field
            label="Duration (minutes)"
            field={@form[:duration_minutes]}
            type="number"
            hint="Defaults to exam's catalogue duration if you leave it blank."
          />
          <.field label="Capacity" field={@form[:capacity]} type="number" />

          <%= unless @form.errors == [] do %>
            <div class="sm:col-span-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              <ul class="list-disc pl-5">
                <%= for {field_name, {msg, opts}} <- @form.errors do %>
                  <li>{humanize_field(field_name)}: {interpolate_msg(msg, opts)}</li>
                <% end %>
              </ul>
            </div>
          <% end %>

          <div class="sm:col-span-2 flex gap-2">
            <button
              type="submit"
              class="rounded-lg bg-indigo-700 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-600"
            >
              Publish slot
            </button>
            <.link
              navigate={~p"/examcenter/slots"}
              class="rounded-lg border border-ink-300 px-4 py-2 text-sm text-ink-700 hover:bg-ink-50"
            >
              Cancel
            </.link>
          </div>
        </.form>
      <% end %>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :offerings, :list, required: true
  attr :error, :string, default: nil

  defp bulk_form(assigns) do
    weekdays = [
      {1, "Mon"},
      {2, "Tue"},
      {3, "Wed"},
      {4, "Thu"},
      {5, "Fri"},
      {6, "Sat"},
      {7, "Sun"}
    ]

    times = ["10:00", "12:00", "14:00", "16:30"]
    assigns = assign(assigns, weekdays: weekdays, time_options: times)

    ~H"""
    <section class="mt-8 max-w-2xl rounded-2xl border border-ink-200 bg-white p-6">
      <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">
        Bulk create slots
      </h2>
      <p class="mt-1 text-sm text-ink-500">
        Pick a date range, weekdays, and the times to run each day. The system
        will create one slot per (date, time) combination.
      </p>

      <%= if @offerings == [] do %>
        <p class="mt-4 rounded-lg border border-dashed border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
          You haven't added any exams to your offerings yet. Visit
          <.link navigate={~p"/examcenter/exams"} class="font-semibold underline">
            Exams I offer
          </.link>
          to add one first.
        </p>
      <% else %>
        <.form
          for={@form}
          id="bulk-slot-form"
          phx-submit="bulk_save"
          class="mt-6 space-y-5"
        >
          <div>
            <label class="block text-sm font-medium text-ink-700" for={@form[:exam_id].id}>
              Exam
            </label>
            <select
              id={@form[:exam_id].id}
              name={@form[:exam_id].name}
              class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            >
              <option value="">— pick one —</option>
              <%= for exam <- @offerings do %>
                <option value={exam.id}>
                  {exam.name} ({exam.code} · {exam.duration_minutes} min)
                </option>
              <% end %>
            </select>
          </div>

          <fieldset>
            <legend class="text-sm font-medium text-ink-700">Date range</legend>
            <div class="mt-2 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <input
                type="date"
                name="bulk[start_date]"
                value={@form[:start_date].value}
                class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
              />
              <input
                type="date"
                name="bulk[end_date]"
                value={@form[:end_date].value}
                class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
              />
            </div>
          </fieldset>

          <fieldset>
            <legend class="text-sm font-medium text-ink-700">Weekdays</legend>
            <div class="mt-2 flex flex-wrap gap-3">
              <%= for {n, label} <- @weekdays do %>
                <label class="inline-flex items-center gap-2 rounded-lg border border-ink-200 px-3 py-1.5 text-sm">
                  <input
                    type="checkbox"
                    name="bulk[weekdays][]"
                    value={n}
                    class="size-4 rounded border-ink-300 text-indigo-700 focus:ring-indigo-500"
                  />
                  {label}
                </label>
              <% end %>
            </div>
          </fieldset>

          <fieldset>
            <legend class="text-sm font-medium text-ink-700">Times</legend>
            <div class="mt-2 flex flex-wrap gap-3">
              <%= for t <- @time_options do %>
                <label class="inline-flex items-center gap-2 rounded-lg border border-ink-200 px-3 py-1.5 text-sm font-mono">
                  <input
                    type="checkbox"
                    name="bulk[times][]"
                    value={t}
                    class="size-4 rounded border-ink-300 text-indigo-700 focus:ring-indigo-500"
                  />
                  {t}
                </label>
              <% end %>
            </div>
          </fieldset>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label class="block text-sm font-medium text-ink-700" for="bulk_duration">
                Duration (minutes)
              </label>
              <input
                id="bulk_duration"
                type="number"
                name="bulk[duration_minutes]"
                value={@form[:duration_minutes].value}
                class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-ink-700" for="bulk_capacity">
                Capacity per slot
              </label>
              <input
                id="bulk_capacity"
                type="number"
                name="bulk[capacity]"
                value={@form[:capacity].value}
                class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-ink-900 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
              />
            </div>
          </div>

          <%= if @error do %>
            <p class="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              {@error}
            </p>
          <% end %>

          <div class="flex gap-2">
            <button
              type="submit"
              class="rounded-lg bg-indigo-700 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-600"
            >
              Publish slots
            </button>
            <.link
              navigate={~p"/examcenter/slots"}
              class="rounded-lg border border-ink-300 px-4 py-2 text-sm text-ink-700 hover:bg-ink-50"
            >
              Cancel
            </.link>
          </div>
        </.form>
      <% end %>
    </section>
    """
  end

  attr :slots, :list, required: true

  defp slot_table(assigns) do
    ~H"""
    <%= if @slots == [] do %>
      <div class="mt-8 rounded-2xl border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
        No upcoming slots. Click "+ New slot" to publish one.
      </div>
    <% else %>
      <div class="mt-8 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-ink-200 bg-ink-50">
            <tr>
              <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                Starts
              </th>
              <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                Exam
              </th>
              <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                Capacity
              </th>
              <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                Available
              </th>
              <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                Status
              </th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-ink-200">
            <%= for slot <- @slots do %>
              <tr id={"slot-row-#{slot.id}"}>
                <td class="px-4 py-2 font-mono text-xs text-ink-700">
                  {Calendar.strftime(slot.starts_at, "%Y-%m-%d %H:%M")}
                </td>
                <td class="px-4 py-2 font-mono text-xs text-ink-700">
                  {exam_code(slot.exam_id)}
                </td>
                <td class="px-4 py-2 text-ink-700">{slot.capacity}</td>
                <td class="px-4 py-2 text-ink-700">{slot.available_count}</td>
                <td class="px-4 py-2">
                  <span class={status_pill_class(slot.status)}>{slot.status}</span>
                </td>
                <td class="px-4 py-2 text-right">
                  <button
                    type="button"
                    phx-click="cancel_slot"
                    phx-value-id={slot.id}
                    data-test-id={"cancel-slot-#{slot.id}"}
                    data-confirm="Cancel this slot? Any bookings will be notified."
                    class="text-sm font-semibold text-red-700 hover:underline"
                  >
                    Cancel
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  defp exam_code(exam_id) do
    case Exams.get_exam!(exam_id) do
      %{code: code} -> code
    end
  rescue
    Ecto.NoResultsError -> "?"
  end

  defp status_pill_class("open"),
    do: "inline-block rounded-full bg-teal-50 px-2 py-0.5 text-xs font-medium text-teal-800"

  defp status_pill_class("full"),
    do: "inline-block rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-800"

  defp status_pill_class("cancelled"),
    do: "inline-block rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700"

  defp status_pill_class(_),
    do: "inline-block rounded-full bg-ink-50 px-2 py-0.5 text-xs font-medium text-ink-700"

  defp humanize_field(field) when is_atom(field),
    do: field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp interpolate_msg(msg, opts) when is_binary(msg) and is_list(opts) do
    Enum.reduce(opts, msg, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  defp interpolate_msg(msg, _), do: msg

  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :hint, :string, default: nil

  defp field(assigns) do
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
    </div>
    """
  end
end
