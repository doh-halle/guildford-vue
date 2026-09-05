defmodule GuildfordVueWeb.SearchLive do
  @moduledoc """
  Public guest search at `/search` (PRD §4.5 — no login required).
  Postcode → list of nearby centres with their available slots.

  The "Book this slot" action is auth-gated in Slice 6; for guests
  it redirects to `/candidate/login?return_to=...`. Listing itself
  has no auth requirement so candidates can window-shop before
  signing in.

  Filter inputs are URL params (?postcode=...) so deep-links work
  and Sprint 11's mobile polish can drive the form from the OS
  share sheet.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Centres.PubSub, as: CentrePubSub
  alias GuildfordVue.CentreSearch
  alias GuildfordVue.CentreSearch.MarkerData
  alias GuildfordVue.Exams
  alias GuildfordVue.Hammer
  alias GuildfordVue.Slots.Slot

  # 60 search submits per IP per hour (Sprint 11.5 Slice 1) — generous
  # but stops a scraper from hammering Geocoder.
  @rate_limit_scope "centre-search"
  @rate_limit_limit 60
  @rate_limit_window_ms 60 * 60 * 1000

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> Hammer.assign_peer_ip()
     |> assign(:page_title, "Find an exam centre")
     |> assign(:exams, Exams.list_exams())
     |> assign(:postcode, Map.get(params, "postcode", ""))
     |> assign(:radius_metres, parse_int(Map.get(params, "radius_metres", "80467"), 80_467))
     |> assign(:exam_id, Map.get(params, "exam_id", ""))
     |> assign(:results, nil)
     |> assign(:error_msg, nil)
     |> assign(:subscribed_ids, MapSet.new())
     |> assign(:selected_centre_id, nil)
     |> maybe_run_search()}
  end

  defp maybe_run_search(socket) do
    if socket.assigns.postcode == "", do: socket, else: run_search(socket)
  end

  defp run_search(socket) do
    opts = %{
      postcode: socket.assigns.postcode,
      radius_metres: socket.assigns.radius_metres
    }

    opts =
      case socket.assigns.exam_id do
        "" -> opts
        id when is_binary(id) -> Map.put(opts, :exam_id, id)
      end

    case CentreSearch.search(opts) do
      {:ok, results} ->
        socket
        |> assign(:results, results)
        |> assign(:error_msg, nil)
        |> sync_subscriptions(results)
        |> push_markers(results)

      {:error, :invalid_postcode} ->
        socket
        |> assign(:results, nil)
        |> assign(:error_msg, "Please enter a valid UK postcode.")

      {:error, :unknown_postcode} ->
        socket
        |> assign(:results, [])
        |> assign(
          :error_msg,
          "We could not find that postcode. Try a nearby one or a broader area."
        )
        |> push_markers([])

      {:error, _} ->
        socket
        |> assign(:results, nil)
        |> assign(:error_msg, "Search failed. Please try again.")
    end
  end

  defp push_markers(socket, results) do
    push_event(socket, "map:set-markers", %{markers: MarkerData.from_results(results)})
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => params}, socket) do
    case Hammer.check(
           @rate_limit_scope,
           Hammer.socket_ip(socket),
           @rate_limit_limit,
           @rate_limit_window_ms
         ) do
      :allow ->
        {:noreply,
         socket
         |> assign(:postcode, Map.get(params, "postcode", ""))
         |> assign(
           :radius_metres,
           parse_int(Map.get(params, "radius_metres", "80467"), 80_467)
         )
         |> assign(:exam_id, Map.get(params, "exam_id", ""))
         |> run_search()}

      {:deny, retry_after} ->
        {:noreply,
         assign(
           socket,
           :error_msg,
           "Too many searches from your network. Please try again in #{retry_after}s."
         )}
    end
  end

  def handle_event("open_slots", %{"id" => centre_id}, socket) do
    {:noreply, assign(socket, :selected_centre_id, centre_id)}
  end

  def handle_event("close_slots", _params, socket) do
    {:noreply, assign(socket, :selected_centre_id, nil)}
  end

  defp parse_int(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  # Subscribe to every visible centre's PubSub topic; unsubscribe
  # from any no-longer-visible. Only meaningful when the LV is on
  # the WebSocket side (HTTP-render path skips it).
  defp sync_subscriptions(socket, results) do
    if connected?(socket) do
      want = results |> Enum.map(& &1.centre.id) |> MapSet.new()
      have = socket.assigns.subscribed_ids

      Enum.each(MapSet.difference(want, have), &CentrePubSub.subscribe/1)
      Enum.each(MapSet.difference(have, want), &CentrePubSub.unsubscribe/1)

      assign(socket, :subscribed_ids, want)
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:slot_changed, %Slot{} = slot}, socket) do
    updated = update_results_slot(socket.assigns.results, slot)

    socket =
      socket
      |> assign(:results, updated)
      |> push_markers(updated || [])

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # Replace the matching slot in-place inside the appropriate centre's
  # `:slots` list. Untouched centres pass through verbatim.
  defp update_results_slot(nil, _slot), do: nil
  defp update_results_slot([], _slot), do: []

  defp update_results_slot(results, updated_slot) when is_list(results) do
    Enum.map(results, &replace_slot_in_result(&1, updated_slot))
  end

  defp replace_slot_in_result(result, updated_slot) do
    if Enum.any?(result.slots, &(&1.id == updated_slot.id)) do
      %{result | slots: Enum.map(result.slots, &maybe_replace(&1, updated_slot))}
    else
      result
    end
  end

  defp maybe_replace(%Slot{id: id}, %Slot{id: id} = new), do: new
  defp maybe_replace(slot, _new), do: slot

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">
        Find an exam centre
      </h1>
      <p class="mt-2 text-sm text-ink-600">
        Enter a UK postcode to see nearby centres and their published slots.
      </p>

      <.form
        for={%{}}
        id="centre-search-form"
        phx-submit="search"
        class="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-4"
      >
        <input
          type="text"
          name="search[postcode]"
          value={@postcode}
          placeholder="Postcode (e.g. SW1A 1AA)"
          autocomplete="postal-code"
          required
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30 sm:col-span-2"
        />

        <select
          name="search[exam_id]"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
        >
          <option value="">All exams</option>
          <%= for e <- @exams do %>
            <option value={e.id} selected={@exam_id == e.id}>{e.name}</option>
          <% end %>
        </select>

        <select
          name="search[radius_metres]"
          class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
        >
          <option value="10000" selected={@radius_metres == 10_000}>Within 10 km</option>
          <option value="25000" selected={@radius_metres == 25_000}>Within 25 km</option>
          <option value="50000" selected={@radius_metres == 50_000}>Within 50 km</option>
          <option value="80467" selected={@radius_metres == 80_467}>Within 50 mi</option>
          <option value="160934" selected={@radius_metres == 160_934}>Within 100 mi</option>
        </select>

        <button
          type="submit"
          class="min-h-11 rounded-lg bg-teal-700 px-4 py-2 text-base font-semibold text-white hover:bg-teal-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-500 sm:text-sm"
        >
          Search
        </button>
      </.form>

      <%= if @error_msg do %>
        <p class="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          {@error_msg}
        </p>
      <% end %>

      <%= cond do %>
        <% is_nil(@results) -> %>
        <% @results == [] -> %>
          <p class="mt-8 rounded-lg border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
            No centres with matching slots in that area. Try widening the radius or a different exam.
          </p>
        <% true -> %>
          <.map_panel markers={MarkerData.from_results(@results)} />
          <.results_list results={@results} />
      <% end %>

      <%= if @selected_centre_id do %>
        <.slots_modal result={selected_result(@results, @selected_centre_id)} />
      <% end %>
    </main>
    """
  end

  attr :markers, :list, required: true

  defp map_panel(assigns) do
    ~H"""
    <section class="mt-8" aria-label="Map of nearby centres">
      <div
        id="centre-map"
        phx-hook="Map"
        phx-update="ignore"
        data-markers={Jason.encode!(@markers)}
        class="aspect-square w-full rounded-2xl border border-ink-200 bg-ink-50"
      >
      </div>

      <div class="mt-3 flex items-center gap-4 text-xs text-ink-600">
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded-full bg-teal-600"></span> Plenty available
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded-full bg-amber-600"></span> Some left
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="size-3 rounded-full bg-red-700"></span> Full
        </span>
      </div>
    </section>
    """
  end

  attr :results, :list, required: true

  defp results_list(assigns) do
    ~H"""
    <ul class="mt-8 space-y-4">
      <%= for r <- @results do %>
        <li>
          <button
            type="button"
            id={"centre-card-#{r.centre.id}"}
            phx-click="open_slots"
            phx-value-id={r.centre.id}
            class="block w-full rounded-2xl border border-ink-200 bg-white p-6 text-left transition hover:border-teal-400 hover:shadow-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/40"
            aria-haspopup="dialog"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-3">
              <div class="min-w-0 flex-1">
                <h2 class="font-sans text-lg font-bold tracking-tight text-ink-900">
                  {r.centre.name}
                </h2>
                <p class="text-sm text-ink-600">
                  {r.centre.address_line_1}, {r.centre.city} {r.centre.postcode}
                </p>
              </div>
              <p class="font-mono text-xs uppercase tracking-widest text-ink-500">
                {format_distance(r.distance_metres)}
              </p>
            </div>

            <dl class="mt-4 grid grid-cols-2 gap-4 text-sm sm:grid-cols-3">
              <div>
                <dt class="font-mono text-[10px] uppercase tracking-widest text-ink-500">
                  Available slots
                </dt>
                <dd class="mt-1 font-sans text-base font-semibold text-ink-900">
                  {available_slot_count(r.slots)}
                </dd>
              </div>
              <div class="sm:col-span-2">
                <dt class="font-mono text-[10px] uppercase tracking-widest text-ink-500">
                  Date range
                </dt>
                <dd class="mt-1 font-sans text-base font-semibold text-ink-900">
                  {format_date_range(r.slots)}
                </dd>
              </div>
            </dl>
          </button>
        </li>
      <% end %>
    </ul>
    """
  end

  attr :result, :map, required: true

  defp slots_modal(assigns) do
    ~H"""
    <div
      id="slots-modal"
      class="fixed inset-0 z-[9999] flex items-end justify-center bg-ink-900/60 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="slots-modal-title"
      phx-click="close_slots"
    >
      <div
        class="max-h-[85vh] w-full max-w-2xl overflow-hidden rounded-2xl bg-white shadow-2xl"
        phx-click-away="close_slots"
        phx-window-keydown="close_slots"
        phx-key="escape"
      >
        <div class="flex items-start justify-between gap-4 border-b border-ink-200 px-6 py-4">
          <div class="min-w-0 flex-1">
            <h2
              id="slots-modal-title"
              class="font-sans text-lg font-bold tracking-tight text-ink-900"
            >
              {@result.centre.name}
            </h2>
            <p class="text-sm text-ink-600">
              {@result.centre.address_line_1}, {@result.centre.city} {@result.centre.postcode}
            </p>
          </div>
          <button
            type="button"
            phx-click="close_slots"
            aria-label="Close"
            class="rounded-lg p-2 text-ink-500 hover:bg-ink-100 hover:text-ink-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/40"
          >
            ×
          </button>
        </div>

        <div class="max-h-[65vh] overflow-y-auto px-6 py-4">
          <%= if @result.slots == [] do %>
            <p class="rounded-lg border border-dashed border-ink-300 p-6 text-center text-sm text-ink-500">
              No slots available for this centre.
            </p>
          <% else %>
            <ul class="divide-y divide-ink-200">
              <%= for slot <- @result.slots do %>
                <li
                  data-test-id={"modal-slot-#{slot.id}"}
                  class="flex flex-col gap-3 py-3 text-sm sm:flex-row sm:items-center sm:justify-between"
                >
                  <div class="min-w-0 flex-1">
                    <p class="font-mono text-sm text-ink-700">
                      {Calendar.strftime(slot.starts_at, "%a %-d %b %Y · %H:%M")}
                    </p>
                    <p class="text-xs text-ink-500">
                      Capacity {slot.capacity} · {slot.available_count} available
                    </p>
                  </div>
                  <.link
                    navigate={~p"/book/#{slot.id}"}
                    class="inline-flex min-h-11 w-full items-center justify-center rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white hover:bg-teal-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-500 sm:w-auto sm:py-1.5 sm:text-xs"
                  >
                    Book this slot
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp selected_result(results, centre_id) do
    Enum.find(results, fn r -> r.centre.id == centre_id end)
  end

  defp available_slot_count(slots) do
    n = Enum.count(slots, &(&1.available_count > 0))

    case n do
      0 -> "0 slots"
      1 -> "1 slot"
      n -> "#{n} slots"
    end
  end

  defp format_date_range([]), do: "—"

  defp format_date_range(slots) do
    starts = Enum.map(slots, & &1.starts_at)
    first = Enum.min(starts, DateTime)
    last = Enum.max(starts, DateTime)

    case Date.compare(DateTime.to_date(first), DateTime.to_date(last)) do
      :eq -> Calendar.strftime(first, "%-d %b")
      _ -> "#{Calendar.strftime(first, "%-d %b")} – #{Calendar.strftime(last, "%-d %b")}"
    end
  end

  defp format_distance(m) when m < 1000, do: "#{m} m"
  defp format_distance(m), do: "#{Float.round(m / 1609.34, 1)} mi"
end
