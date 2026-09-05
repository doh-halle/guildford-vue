defmodule GuildfordVueWeb.Candidate.CandidateBookingsLive do
  @moduledoc """
  Candidate's own bookings — list + detail (PRD §4.7). Two live
  actions in one module:

    * `:index` — `/candidate/bookings` — newest-first list of every
      booking by the signed-in candidate.
    * `:show`  — `/candidate/bookings/:reference` — full detail page
      with the PDF receipt link and a Cancel button for confirmed
      bookings.

  Authorisation is per-action: a candidate can only see their own
  bookings. Asking for another candidate's reference (or an unknown
  one) live-redirects to the list with a flash, rather than 404-ing
  — booking references are short and intentionally human-typeable;
  a friendly redirect beats a 404 page for the mistyped case.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{Bookings, ExamCentres, Exams, Slots}

  @doc false
  defp load_grouped(candidate) do
    %{
      upcoming: Bookings.list_upcoming_candidate_bookings(candidate),
      past: Bookings.list_past_candidate_bookings(candidate)
    }
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    candidate = socket.assigns.current_candidate
    grouped = load_grouped(candidate)

    socket
    |> assign(:page_title, "Your bookings")
    |> assign(:upcoming, grouped.upcoming)
    |> assign(:past, grouped.past)
  end

  defp apply_action(socket, :show, %{"reference" => ref}) do
    candidate = socket.assigns.current_candidate

    case Bookings.get_booking_by_reference(ref) do
      nil ->
        socket
        |> put_flash(:error, "We could not find that booking.")
        |> push_navigate(to: ~p"/candidate/bookings")

      %{candidate_id: cid} = booking when cid == candidate.id ->
        socket
        |> assign(:page_title, "Booking #{booking.reference}")
        |> assign(:booking, booking)
        |> assign(:slot, Slots.get_slot!(booking.slot_id))
        |> assign(:exam, Exams.get_exam!(booking.exam_id))
        |> assign(:centre, ExamCentres.get_exam_centre!(booking.exam_centre_id))

      _ ->
        # Different candidate's booking — don't reveal its existence.
        socket
        |> put_flash(:error, "We could not find that booking.")
        |> push_navigate(to: ~p"/candidate/bookings")
    end
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_booking", _, socket) do
    candidate = socket.assigns.current_candidate
    booking = socket.assigns.booking

    case Bookings.cancel_booking(booking, candidate) do
      {:ok, cancelled} ->
        {:noreply,
         socket
         |> assign(:booking, cancelled)
         |> put_flash(:info, "Booking #{cancelled.reference} cancelled.")}

      {:error, :already_cancelled} ->
        {:noreply, put_flash(socket, :error, "That booking is already cancelled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cancel failed: #{inspect(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-3xl px-4 py-10 sm:px-6">
      <%= case @live_action do %>
        <% :index -> %>
          <.bookings_list upcoming={@upcoming} past={@past} />
        <% :show -> %>
          <.booking_detail booking={@booking} slot={@slot} exam={@exam} centre={@centre} />
      <% end %>
    </main>
    """
  end

  attr :upcoming, :list, required: true
  attr :past, :list, required: true

  defp bookings_list(assigns) do
    ~H"""
    <p class="font-mono text-xs uppercase tracking-widest text-teal-700">Your bookings</p>
    <h1 class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900">Bookings</h1>

    <%= if @upcoming == [] and @past == [] do %>
      <p class="mt-8 rounded-lg border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
        You haven't booked any exams yet. Find a centre via <.link
          navigate={~p"/search"}
          class="font-semibold text-teal-700 hover:underline"
        >
          /search
        </.link>.
      </p>
    <% else %>
      <section aria-labelledby="bookings-upcoming" class="mt-8">
        <h2
          id="bookings-upcoming"
          class="font-mono text-xs uppercase tracking-widest text-ink-500"
        >
          Upcoming
        </h2>
        <%= if @upcoming == [] do %>
          <p class="mt-3 text-sm text-ink-500">No upcoming reservations.</p>
        <% else %>
          <ul class="mt-3 space-y-3">
            <li :for={b <- @upcoming} class="rounded-2xl border border-ink-200 bg-white p-6">
              <.booking_row booking={b} />
            </li>
          </ul>
        <% end %>
      </section>

      <section aria-labelledby="bookings-past" class="mt-10">
        <h2 id="bookings-past" class="font-mono text-xs uppercase tracking-widest text-ink-500">
          Past
        </h2>
        <%= if @past == [] do %>
          <p class="mt-3 text-sm text-ink-500">No past reservations yet.</p>
        <% else %>
          <ul class="mt-3 space-y-3">
            <li :for={b <- @past} class="rounded-2xl border border-ink-200 bg-white/60 p-6">
              <.booking_row booking={b} />
            </li>
          </ul>
        <% end %>
      </section>
    <% end %>
    """
  end

  attr :booking, :map, required: true

  defp booking_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-baseline justify-between gap-3">
      <.link
        navigate={~p"/candidate/bookings/#{@booking.reference}"}
        class="font-mono text-lg font-bold tracking-tight text-teal-700 hover:underline"
      >
        {@booking.reference}
      </.link>
      <span class={status_pill_class(@booking.status)}>{@booking.status}</span>
    </div>
    <p class="mt-2 text-sm text-ink-600">
      {fetch_exam_name(@booking)}
    </p>
    """
  end

  attr :booking, :map, required: true
  attr :slot, :map, required: true
  attr :exam, :map, required: true
  attr :centre, :map, required: true

  defp booking_detail(assigns) do
    ~H"""
    <p class="font-mono text-xs uppercase tracking-widest text-teal-700">Booking</p>
    <div class="mt-2 flex flex-wrap items-baseline justify-between gap-3">
      <h1 class="font-mono text-3xl font-bold tracking-tight text-teal-900">
        {@booking.reference}
      </h1>
      <span class={status_pill_class(@booking.status)}>{@booking.status}</span>
    </div>

    <section class="mt-8 rounded-2xl border border-ink-200 bg-white p-6">
      <dl class="grid grid-cols-1 gap-y-3 text-sm sm:grid-cols-3">
        <dt class="font-medium text-ink-500">Exam</dt>
        <dd class="text-ink-900 sm:col-span-2">{@exam.name} ({@exam.code})</dd>

        <dt class="font-medium text-ink-500">Centre</dt>
        <dd class="text-ink-900 sm:col-span-2">
          {@centre.name}<br />
          {@centre.address_line_1}, {@centre.city} {@centre.postcode}
        </dd>

        <dt class="font-medium text-ink-500">Starts</dt>
        <dd class="text-ink-900 sm:col-span-2">
          {Calendar.strftime(@slot.starts_at, "%A %d %B %Y · %H:%M")}
        </dd>

        <dt class="font-medium text-ink-500">Price</dt>
        <dd class="text-ink-900 sm:col-span-2">£{format_price(@booking.price_pence)}</dd>

        <dt class="font-medium text-ink-500">Receipt</dt>
        <dd class="text-ink-900 sm:col-span-2">
          <%= if @booking.pdf_url && String.starts_with?(@booking.pdf_url, "/") do %>
            <a href={@booking.pdf_url} class="font-semibold text-teal-700 hover:underline">
              Download PDF
            </a>
          <% else %>
            <span class="text-ink-500">Receipt unavailable.</span>
          <% end %>
        </dd>
      </dl>

      <div class="mt-8 flex flex-wrap gap-3">
        <.link
          navigate={~p"/candidate/bookings"}
          class="rounded-lg border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 hover:bg-ink-50"
        >
          Back to bookings
        </.link>

        <%= if @booking.status == "confirmed" do %>
          <button
            type="button"
            phx-click="cancel_booking"
            data-test-id="cancel-booking"
            data-confirm="Cancel this booking? The seat will be released to other candidates."
            class="rounded-lg border border-red-300 px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50"
          >
            Cancel booking
          </button>
        <% end %>
      </div>
    </section>
    """
  end

  defp status_pill_class("confirmed"),
    do: "inline-block rounded-full bg-teal-50 px-3 py-0.5 text-xs font-semibold text-teal-800"

  defp status_pill_class("cancelled"),
    do: "inline-block rounded-full bg-ink-100 px-3 py-0.5 text-xs font-semibold text-ink-600"

  defp status_pill_class("refunded"),
    do: "inline-block rounded-full bg-amber-50 px-3 py-0.5 text-xs font-semibold text-amber-800"

  defp status_pill_class(_),
    do: "inline-block rounded-full bg-ink-50 px-3 py-0.5 text-xs font-semibold text-ink-700"

  defp fetch_exam_name(%{exam_id: id}) do
    case Exams.get_exam!(id) do
      %{name: n} -> n
    end
  rescue
    Ecto.NoResultsError -> "—"
  end

  defp format_price(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end
end
