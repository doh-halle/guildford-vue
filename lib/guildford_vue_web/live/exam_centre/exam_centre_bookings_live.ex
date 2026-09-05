defmodule GuildfordVueWeb.ExamCentre.ExamCentreBookingsLive do
  @moduledoc """
  Centre-facing bookings: a listing of every booking made at the
  signed-in centre, plus a detail page reached by clicking a row.

  Mounted twice in the router:

      live "/bookings",            ExamCentreBookingsLive, :index
      live "/bookings/:reference", ExamCentreBookingsLive, :show

  Tenant isolation is enforced inside the LV via
  `Bookings.list_bookings_for_centre/1` and
  `Bookings.get_booking_for_centre/2`. A cross-centre or unknown
  reference on the :show route redirects back to /examcenter/bookings
  with an error flash — never reveals whether the reference exists.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{Bookings, Candidates, Exams, Slots}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bookings")
     |> assign(:query, "")
     |> assign(:status_filter, "all")}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:query, Map.get(filter, "query", ""))
     |> assign(:status_filter, Map.get(filter, "status", "all"))
     |> apply_action(:index, %{})}
  end

  defp apply_action(socket, :index, _params) do
    centre = socket.assigns.current_exam_centre
    bookings = Bookings.list_bookings_for_centre(centre, status: socket.assigns.status_filter)

    rows =
      bookings
      |> Enum.map(&row_for/1)
      |> filter_rows(socket.assigns.query)

    socket
    |> assign(:rows, rows)
    |> assign(:filters_active?, filters_active?(socket.assigns))
  end

  defp filters_active?(%{query: q, status_filter: s}),
    do: String.trim(q) != "" or s not in ["", "all", nil]

  defp filter_rows(rows, ""), do: rows

  defp filter_rows(rows, query) do
    needle = query |> String.trim() |> String.downcase()

    case needle do
      "" -> rows
      n -> Enum.filter(rows, &row_matches?(&1, n))
    end
  end

  defp row_matches?(row, needle) do
    candidate = row.candidate || %{}

    [
      row.booking.reference,
      Map.get(candidate, :first_name),
      Map.get(candidate, :last_name),
      Map.get(candidate, :email)
    ]
    |> Enum.any?(&contains_ci?(&1, needle))
  end

  defp contains_ci?(nil, _), do: false
  defp contains_ci?(value, needle), do: value |> String.downcase() |> String.contains?(needle)

  defp apply_action(socket, :show, %{"reference" => reference}) do
    centre = socket.assigns.current_exam_centre

    case Bookings.get_booking_for_centre(centre, reference) do
      {:ok, booking} ->
        assign(socket, :detail, detail_for(booking))

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "That booking could not be found.")
        |> push_navigate(to: ~p"/examcenter/bookings")
    end
  end

  defp row_for(booking) do
    %{
      booking: booking,
      exam: safe_exam(booking.exam_id),
      candidate: safe_candidate(booking.candidate_id),
      slot: safe_slot(booking.slot_id)
    }
  end

  defp detail_for(booking), do: row_for(booking)

  defp safe_exam(id) do
    Exams.get_exam!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp safe_candidate(id) do
    Candidates.get_candidate!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp safe_slot(id) do
    Slots.get_slot!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  @impl Phoenix.LiveView
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell
      current_exam_centre={@current_exam_centre}
      active={:bookings}
    >
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Bookings</h1>
      <p class="mt-2 text-sm text-ink-500">
        Every booking made at <span class="font-semibold">{@current_exam_centre.name}</span>, newest first.
      </p>

      <form
        id="bookings-filter-form"
        phx-change="filter"
        class="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-[1fr_220px]"
      >
        <input
          type="text"
          name="filter[query]"
          value={@query}
          placeholder="Search reference, candidate name or email"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />

        <select
          name="filter[status]"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        >
          <option value="all" selected={@status_filter == "all"}>All statuses</option>
          <option value="confirmed" selected={@status_filter == "confirmed"}>confirmed</option>
          <option value="cancelled" selected={@status_filter == "cancelled"}>cancelled</option>
          <option value="refunded" selected={@status_filter == "refunded"}>refunded</option>
        </select>
      </form>

      <%= cond do %>
        <% @rows == [] and @filters_active? -> %>
          <p
            data-test-id="bookings-no-matches"
            class="mt-8 rounded-lg border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500"
          >
            No bookings match your filters.
          </p>
        <% @rows == [] -> %>
          <p
            data-test-id="bookings-empty-state"
            class="mt-8 rounded-lg border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500"
          >
            No bookings yet. As candidates reserve slots they'll appear here.
          </p>
        <% true -> %>
          <div class="mt-6 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
            <table class="w-full text-left text-sm">
              <thead class="border-b border-ink-200 bg-ink-50">
                <tr>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Reference
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Candidate
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Exam
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Slot
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Status
                  </th>
                  <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                    Price
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for r <- @rows do %>
                  <tr class="border-b border-ink-100 last:border-b-0 hover:bg-ink-50">
                    <td class="px-4 py-3 align-top">
                      <.link
                        navigate={~p"/examcenter/bookings/#{r.booking.reference}"}
                        class="font-mono text-sm font-semibold text-indigo-700 hover:underline"
                      >
                        {r.booking.reference}
                      </.link>
                    </td>
                    <td class="px-4 py-3 align-top">
                      <%= if r.candidate do %>
                        <p class="font-medium text-ink-900">
                          {r.candidate.first_name} {r.candidate.last_name}
                        </p>
                        <p class="text-xs text-ink-500">{r.candidate.email}</p>
                      <% else %>
                        <span class="text-ink-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-4 py-3 align-top text-ink-700">
                      {if r.exam, do: r.exam.name, else: "—"}
                    </td>
                    <td class="px-4 py-3 align-top">
                      <%= if r.slot do %>
                        <p class="font-mono text-xs text-ink-700">
                          {Calendar.strftime(r.slot.starts_at, "%a %-d %b %Y · %H:%M")}
                        </p>
                      <% else %>
                        <span class="text-ink-400">—</span>
                      <% end %>
                    </td>
                    <td class="px-4 py-3 align-top">
                      <.status_badge status={r.booking.status} />
                    </td>
                    <td class="px-4 py-3 align-top font-mono text-sm text-ink-900">
                      £{format_price(r.booking.price_pence)}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
      <% end %>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end

  def render(%{live_action: :show, detail: detail} = assigns) when not is_nil(detail) do
    assigns = assign(assigns, :r, detail)

    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell
      current_exam_centre={@current_exam_centre}
      active={:bookings}
    >
      <.link
        navigate={~p"/examcenter/bookings"}
        class="inline-flex items-center gap-1 text-sm font-semibold text-indigo-700 hover:underline"
      >
        ← Back to bookings
      </.link>

      <div class="mt-4 flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <p class="font-mono text-xs uppercase tracking-widest text-ink-500">Booking</p>
          <h1 class="mt-1 font-mono text-3xl font-bold tracking-tight text-ink-900">
            {@r.booking.reference}
          </h1>
        </div>
        <.status_badge status={@r.booking.status} />
      </div>

      <section
        aria-labelledby="booking-summary"
        class="mt-8 rounded-2xl border border-ink-200 bg-white p-6"
      >
        <h2
          id="booking-summary"
          class="font-mono text-xs uppercase tracking-widest text-ink-500"
        >
          Summary
        </h2>

        <dl class="mt-4 grid grid-cols-1 gap-y-3 text-sm sm:grid-cols-3">
          <dt class="font-medium text-ink-600">Exam</dt>
          <dd class="text-ink-900 sm:col-span-2">
            {if @r.exam, do: @r.exam.name, else: "—"}
          </dd>

          <dt class="font-medium text-ink-600">Slot</dt>
          <dd class="text-ink-900 sm:col-span-2">
            <%= if @r.slot do %>
              {Calendar.strftime(@r.slot.starts_at, "%A %-d %B %Y · %H:%M")}
              <span class="text-ink-500">
                – {Calendar.strftime(@r.slot.ends_at, "%H:%M")}
              </span>
            <% else %>
              —
            <% end %>
          </dd>

          <dt class="font-medium text-ink-600">Price</dt>
          <dd class="font-mono text-ink-900 sm:col-span-2">
            £{format_price(@r.booking.price_pence)}
          </dd>

          <dt class="font-medium text-ink-600">Paid at</dt>
          <dd class="text-ink-900 sm:col-span-2">
            <%= if @r.booking.paid_at do %>
              {Calendar.strftime(@r.booking.paid_at, "%-d %b %Y · %H:%M UTC")}
            <% else %>
              —
            <% end %>
          </dd>

          <%= if @r.booking.cancelled_at do %>
            <dt class="font-medium text-ink-600">Cancelled at</dt>
            <dd class="text-ink-900 sm:col-span-2">
              {Calendar.strftime(@r.booking.cancelled_at, "%-d %b %Y · %H:%M UTC")}
            </dd>
          <% end %>

          <dt class="font-medium text-ink-600">Booked on</dt>
          <dd class="text-ink-900 sm:col-span-2">
            {Calendar.strftime(@r.booking.inserted_at, "%-d %b %Y · %H:%M UTC")}
          </dd>
        </dl>
      </section>

      <section
        aria-labelledby="booking-candidate"
        class="mt-6 rounded-2xl border border-ink-200 bg-white p-6"
      >
        <h2
          id="booking-candidate"
          class="font-mono text-xs uppercase tracking-widest text-ink-500"
        >
          Candidate
        </h2>

        <%= if @r.candidate do %>
          <dl class="mt-4 grid grid-cols-1 gap-y-3 text-sm sm:grid-cols-3">
            <dt class="font-medium text-ink-600">Name</dt>
            <dd class="text-ink-900 sm:col-span-2">
              {@r.candidate.first_name} {@r.candidate.last_name}
            </dd>

            <dt class="font-medium text-ink-600">Email</dt>
            <dd class="text-ink-900 sm:col-span-2">{@r.candidate.email}</dd>

            <%= if @r.candidate.postcode do %>
              <dt class="font-medium text-ink-600">Postcode</dt>
              <dd class="text-ink-900 sm:col-span-2">{@r.candidate.postcode}</dd>
            <% end %>
          </dl>
        <% else %>
          <p class="mt-4 text-sm text-ink-500">Candidate record unavailable.</p>
        <% end %>
      </section>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.centre_shell
      current_exam_centre={@current_exam_centre}
      active={:bookings}
    >
      <p class="text-sm text-ink-500">Loading…</p>
    </GuildfordVueWeb.Layouts.centre_shell>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
      status_classes(@status)
    ]}>
      {@status}
    </span>
    """
  end

  defp status_classes("confirmed"), do: "bg-teal-50 text-teal-800 border border-teal-200"
  defp status_classes("cancelled"), do: "bg-ink-100 text-ink-700 border border-ink-200"
  defp status_classes("refunded"), do: "bg-amber-50 text-amber-800 border border-amber-200"
  defp status_classes(_), do: "bg-ink-100 text-ink-700 border border-ink-200"

  defp format_price(pence) when is_integer(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end
end
