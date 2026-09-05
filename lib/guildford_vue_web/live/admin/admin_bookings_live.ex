defmodule GuildfordVueWeb.Admin.AdminBookingsLive do
  @moduledoc """
  Sprint 10 Slice 4 — admin bookings list with the refund action.
  Read-only by default; confirmed bookings expose a Refund button
  that calls `Bookings.refund/2` and audit-logs the action.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{Bookings, Exams}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bookings")
     |> reload()}
  end

  defp reload(socket) do
    bookings = Bookings.list_recent_bookings(limit: 200)
    exam_names = exam_name_map(bookings)

    socket
    |> assign(:bookings, bookings)
    |> assign(:exam_names, exam_names)
  end

  defp exam_name_map(bookings) do
    ids = bookings |> Enum.map(& &1.exam_id) |> Enum.uniq()

    ids
    |> Enum.map(fn id ->
      try do
        {id, Exams.get_exam!(id).name}
      rescue
        Ecto.NoResultsError -> {id, "—"}
      end
    end)
    |> Map.new()
  end

  @impl Phoenix.LiveView
  def handle_event("refund", %{"id" => id}, socket) do
    booking = Bookings.get_booking!(id)
    admin = socket.assigns.current_admin

    case Bookings.refund(booking, admin) do
      {:ok, refunded} ->
        {:noreply,
         socket
         |> put_flash(:info, "Refunded #{refunded.reference}.")
         |> reload()}

      {:error, :already_refunded} ->
        {:noreply, put_flash(socket, :error, "That booking is already refunded.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Refund failed: #{inspect(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:bookings}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Bookings</h1>
      <p class="mt-2 text-sm text-ink-500">
        Most recent {length(@bookings)} bookings. Refund confirmed bookings to release the slot
        and record a refunded Payment row.
      </p>

      <%= if @bookings == [] do %>
        <p class="mt-8 rounded-lg border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
          No bookings yet.
        </p>
      <% else %>
        <div class="mt-6 overflow-x-auto rounded-2xl border border-ink-200 bg-white">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-ink-200 bg-ink-50">
              <tr>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Reference
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Exam
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Status
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Booked
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Price
                </th>
                <th class="px-4 py-2 font-mono text-xs uppercase tracking-widest text-ink-600">
                  Action
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-ink-200" id="admin-bookings" phx-update="replace">
              <tr :for={b <- @bookings} id={"booking-#{b.id}"}>
                <td class="px-4 py-2 font-mono text-xs text-teal-800">{b.reference}</td>
                <td class="px-4 py-2 text-xs text-ink-700">{Map.get(@exam_names, b.exam_id, "—")}</td>
                <td class="px-4 py-2">
                  <span class={status_pill(b.status)}>{b.status}</span>
                </td>
                <td class="px-4 py-2 text-xs text-ink-500">
                  {Calendar.strftime(b.inserted_at, "%Y-%m-%d %H:%M")}
                </td>
                <td class="px-4 py-2 font-mono text-xs text-ink-700">
                  £{format_pounds(b.price_pence)}
                </td>
                <td class="px-4 py-2">
                  <%= if b.status == "confirmed" do %>
                    <button
                      type="button"
                      phx-click="refund"
                      phx-value-id={b.id}
                      data-test-id={"refund-#{b.reference}"}
                      data-confirm={"Refund #{b.reference}? The slot will be released and a refunded Payment row recorded."}
                      class="rounded-lg border border-red-300 px-3 py-1 text-xs font-semibold text-red-700 hover:bg-red-50"
                    >
                      Refund
                    </button>
                  <% else %>
                    <span class="text-xs text-ink-400">—</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end

  defp status_pill("confirmed"),
    do: "inline-block rounded-full bg-teal-50 px-3 py-0.5 text-xs font-semibold text-teal-800"

  defp status_pill("cancelled"),
    do: "inline-block rounded-full bg-ink-100 px-3 py-0.5 text-xs font-semibold text-ink-600"

  defp status_pill("refunded"),
    do: "inline-block rounded-full bg-amber-50 px-3 py-0.5 text-xs font-semibold text-amber-800"

  defp status_pill(_),
    do: "inline-block rounded-full bg-ink-50 px-3 py-0.5 text-xs font-semibold text-ink-700"

  defp format_pounds(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end
end
