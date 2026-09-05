defmodule GuildfordVueWeb.Candidate.BookSlotLive do
  @moduledoc """
  Auth-gated booking confirmation page (PRD §4.5 + §4.7 + §4.8).
  Three render states form a small state machine:

      :pending  →  click "Continue to payment"        →  :payment
      :payment  →  pick method + (for cards) fill form
                →  click "Pay"
                →  pipeline runs
                →  :confirmed | :payment (with error)

  Sprint 7 Slice 4 introduced the :pending → :confirmed flow with
  a single button. Sprint 8 Slice 4 inserts the :payment state.

  The booking pipeline (`Bookings.create_booking/3`) accepts the
  selected payment_method + card via opts. The actual money-movement
  is delegated to `GuildfordVue.PaymentGateway` — Sprint 8 Slice 5
  swaps the default Stub adapter for the Simulated one (which
  validates the card + simulates latency + can decline a fraction
  of attempts).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.{Bookings, ExamCentres, Exams, Hammer, Slots}
  alias GuildfordVue.Centres.PubSub, as: CentrePubSub
  alias GuildfordVue.Payments.{Card, PaymentMethod}
  alias GuildfordVue.Slots.Slot

  # 5 payment attempts per IP per 15 minutes (Sprint 11.5 Slice 1) —
  # mirrors the login rate-limit shape so a brute-forced card surface
  # has the same throttle as a brute-forced password.
  @pay_rate_scope "candidate-pay"
  @pay_rate_limit 5
  @pay_rate_window_ms 15 * 60 * 1000

  @impl Phoenix.LiveView
  def mount(%{"slot_id" => id}, _session, socket) do
    slot = Slots.get_slot!(id)
    centre = ExamCentres.get_exam_centre!(slot.exam_centre_id)
    exam = Exams.get_exam!(slot.exam_id)

    if connected?(socket), do: CentrePubSub.subscribe(centre.id)

    {:ok,
     socket
     |> Hammer.assign_peer_ip()
     |> assign(:page_title, "Book #{exam.name}")
     |> assign(:slot, slot)
     |> assign(:centre, centre)
     |> assign(:exam, exam)
     |> assign(:state, :pending)
     |> assign(:booking, nil)
     |> assign(:payment_method, nil)
     |> assign(:card_error, nil)
     |> assign(:error_msg, nil)}
  end

  @impl Phoenix.LiveView
  def handle_info({:slot_changed, %Slot{} = slot}, socket) do
    if slot.id == socket.assigns.slot.id do
      {:noreply, assign(socket, :slot, slot)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ------------------------------------------------------------------
  # State transitions
  # ------------------------------------------------------------------

  @impl Phoenix.LiveView
  def handle_event("continue_to_payment", _, socket) do
    {:noreply, assign(socket, :state, :payment)}
  end

  def handle_event("pick_method", %{"method" => m}, socket) do
    case PaymentMethod.from_string(m) do
      {:ok, method} ->
        {:noreply,
         socket
         |> assign(:payment_method, method)
         |> assign(:card_error, nil)}

      :error ->
        {:noreply, put_flash(socket, :error, "Unknown payment method.")}
    end
  end

  # Pay click for wallet methods (no card form to submit).
  def handle_event("pay_wallet", _, socket) do
    rate_limited(socket, fn -> do_pay(socket, nil) end)
  end

  # Pay submit for card methods.
  def handle_event("pay_card", %{"card" => params}, socket) do
    rate_limited(socket, fn ->
      case Card.validate(params) do
        {:ok, card} ->
          do_pay(socket, card)

        {:error, reason} ->
          {:noreply, assign(socket, :card_error, friendly_card_error(reason))}
      end
    end)
  end

  defp rate_limited(socket, fun) do
    case Hammer.check(
           @pay_rate_scope,
           Hammer.socket_ip(socket),
           @pay_rate_limit,
           @pay_rate_window_ms
         ) do
      :allow ->
        fun.()

      {:deny, retry_after} ->
        {:noreply,
         assign(
           socket,
           :error_msg,
           "Too many payment attempts. Please try again in #{retry_after}s."
         )}
    end
  end

  defp do_pay(socket, card) do
    candidate = socket.assigns.current_candidate
    slot = socket.assigns.slot
    method = socket.assigns.payment_method

    case Bookings.create_booking(candidate, slot, payment_method: method, card: card) do
      {:ok, booking} ->
        {:noreply,
         socket
         |> assign(:state, :confirmed)
         |> assign(:booking, booking)
         |> put_flash(:info, "Booking confirmed — #{booking.reference}")}

      {:error, stage, reason} ->
        {:noreply,
         socket
         |> assign(:error_msg, flash_for(stage, reason))
         |> assign(:card_error, nil)}
    end
  end

  defp friendly_card_error(:invalid_card_number), do: "That card number looks invalid."
  defp friendly_card_error(:card_expired), do: "That card has expired."
  defp friendly_card_error(:invalid_cvc), do: "CVC must be 3 or 4 digits."
  defp friendly_card_error(:invalid_expiry), do: "Please enter a valid month + year."
  defp friendly_card_error(:missing_holder_name), do: "Cardholder name is required."

  defp flash_for(:validate, :slot_in_past), do: "That slot has already started."
  defp flash_for(:validate, :slot_unbookable), do: "That slot was cancelled."
  defp flash_for(:reserve, :sold_out), do: "Sold out — try a different slot."
  defp flash_for(:reserve, _), do: "We could not reserve that slot. Please try again."
  defp flash_for(:pay, :card_declined), do: "Your card was declined. Please try a different card."
  defp flash_for(:pay, :invalid_card), do: "Card details were rejected. Please check and retry."
  defp flash_for(:pay, _), do: "Payment failed. Please try again."
  defp flash_for(:persist, _), do: "We could not save your booking. Please try again."
  defp flash_for(stage, reason), do: "Booking failed (#{stage}): #{inspect(reason)}"

  # ------------------------------------------------------------------
  # Render
  # ------------------------------------------------------------------

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%!--
      Bottom-sheet treatment on mobile: full-bleed white card with a
      drag handle, rounded top corners, glued to the bottom of the
      viewport with a translucent backdrop above. Above the sm
      breakpoint the page reverts to the centred max-w-2xl card.
    --%>
    <div
      class="fixed inset-x-0 top-0 -z-10 hidden h-32 bg-ink-900/40 sm:hidden"
      aria-hidden="true"
      data-test-id="booking-backdrop"
    >
    </div>

    <main
      data-test-id="booking-sheet"
      class={[
        "mx-auto rounded-t-3xl bg-white px-4 pb-10 pt-6",
        "fixed inset-x-0 bottom-0 max-h-[92vh] overflow-y-auto shadow-2xl",
        "sm:static sm:max-w-2xl sm:rounded-2xl sm:bg-transparent sm:px-6 sm:py-10 sm:shadow-none"
      ]}
    >
      <div
        class="mx-auto mb-4 h-1.5 w-12 rounded-full bg-ink-200 sm:hidden"
        aria-hidden="true"
      >
      </div>

      <p class="font-mono text-xs uppercase tracking-widest text-teal-700">Booking</p>
      <h1 class="mt-2 font-sans text-3xl font-bold tracking-tight text-ink-900">
        {header_for(@state)}
      </h1>

      <%= case @state do %>
        <% :pending -> %>
          <.pending_card slot={@slot} centre={@centre} exam={@exam} error_msg={@error_msg} />
        <% :payment -> %>
          <.payment_card
            exam={@exam}
            payment_method={@payment_method}
            card_error={@card_error}
            error_msg={@error_msg}
          />
        <% :confirmed -> %>
          <.confirmed_card booking={@booking} slot={@slot} centre={@centre} exam={@exam} />
      <% end %>
    </main>
    """
  end

  defp header_for(:pending), do: "Confirm your booking"
  defp header_for(:payment), do: "Payment"
  defp header_for(:confirmed), do: "Booking confirmed"

  attr :slot, :map, required: true
  attr :centre, :map, required: true
  attr :exam, :map, required: true
  attr :error_msg, :string, default: nil

  defp pending_card(assigns) do
    ~H"""
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
        <dt class="font-medium text-ink-500">Duration</dt>
        <dd class="text-ink-900 sm:col-span-2">{@exam.duration_minutes} minutes</dd>
        <dt class="font-medium text-ink-500">Price</dt>
        <dd class="text-ink-900 sm:col-span-2">£{format_price(@exam.price_pence)}</dd>
        <dt class="font-medium text-ink-500">Availability</dt>
        <dd class="text-ink-900 sm:col-span-2">
          {@slot.available_count} of {@slot.capacity} seats remaining
        </dd>
      </dl>

      <%= if @error_msg do %>
        <p class="mt-6 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {@error_msg}
        </p>
      <% end %>

      <div class="mt-8 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
        <button
          type="button"
          phx-click="continue_to_payment"
          data-test-id="continue-to-payment"
          class="inline-flex min-h-11 w-full items-center justify-center rounded-lg bg-teal-700 px-4 py-2 text-base font-semibold text-white hover:bg-teal-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-500 sm:w-auto sm:text-sm"
        >
          Continue to payment
        </button>
        <.link
          navigate={~p"/search"}
          class="inline-flex min-h-11 w-full items-center justify-center rounded-lg border border-ink-300 px-4 py-2 text-base font-semibold text-ink-700 hover:bg-ink-50 sm:w-auto sm:text-sm"
        >
          Back to search
        </.link>
      </div>
    </section>
    """
  end

  attr :exam, :map, required: true
  attr :payment_method, :atom, default: nil
  attr :card_error, :string, default: nil
  attr :error_msg, :string, default: nil

  defp payment_card(assigns) do
    ~H"""
    <section class="mt-8 rounded-2xl border border-ink-200 bg-white p-6">
      <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">Payment method</h2>
      <p class="mt-1 text-sm text-ink-500">£{format_price(@exam.price_pence)} for {@exam.name}.</p>

      <div class="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
        <%= for m <- PaymentMethod.all() do %>
          <button
            type="button"
            phx-click="pick_method"
            phx-value-method={Atom.to_string(m)}
            data-test-id={"method-#{Atom.to_string(m)}"}
            class={method_button_class(m == @payment_method)}
          >
            {PaymentMethod.label(m)}
          </button>
        <% end %>
      </div>

      <%= if @payment_method do %>
        <%= if PaymentMethod.accepts_card?(@payment_method) do %>
          <.card_form payment_method={@payment_method} card_error={@card_error} />
        <% else %>
          <div class="mt-6 rounded-lg border border-ink-200 bg-ink-50 p-4 text-sm text-ink-700">
            You'll be redirected to {PaymentMethod.label(@payment_method)} to complete the
            payment. (Simulated for the dissertation reference.)
          </div>

          <div class="mt-6">
            <button
              type="button"
              phx-click="pay_wallet"
              data-test-id="pay-button"
              phx-disable-with="Processing…"
              class="inline-flex min-h-11 items-center justify-center rounded-lg bg-teal-700 px-4 py-2 text-base font-semibold text-white hover:bg-teal-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-500 sm:text-sm"
            >
              Pay £{format_price(@exam.price_pence)} with {PaymentMethod.label(@payment_method)}
            </button>
          </div>
        <% end %>
      <% end %>

      <%= if @error_msg do %>
        <p class="mt-6 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {@error_msg}
        </p>
      <% end %>
    </section>
    """
  end

  attr :payment_method, :atom, required: true
  attr :card_error, :string, default: nil

  defp card_form(assigns) do
    ~H"""
    <.form for={%{}} id="card-form" phx-submit="pay_card" class="mt-6 grid grid-cols-1 gap-4">
      <div>
        <label for="card-holder" class="block text-sm font-medium text-ink-700">
          Cardholder name
        </label>
        <input
          id="card-holder"
          name="card[holder_name]"
          type="text"
          autocomplete="cc-name"
          required
          class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
        />
      </div>

      <div>
        <label for="card-number" class="block text-sm font-medium text-ink-700">
          Card number
        </label>
        <input
          id="card-number"
          name="card[number]"
          type="text"
          inputmode="numeric"
          autocomplete="cc-number"
          placeholder="4242 4242 4242 4242"
          required
          class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm font-mono focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
        />
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div>
          <label for="card-month" class="block text-sm font-medium text-ink-700">Expiry MM</label>
          <input
            id="card-month"
            name="card[exp_month]"
            type="text"
            inputmode="numeric"
            autocomplete="cc-exp-month"
            placeholder="MM"
            required
            class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
          />
        </div>
        <div>
          <label for="card-year" class="block text-sm font-medium text-ink-700">YYYY</label>
          <input
            id="card-year"
            name="card[exp_year]"
            type="text"
            inputmode="numeric"
            autocomplete="cc-exp-year"
            placeholder="YYYY"
            required
            class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
          />
        </div>
        <div>
          <label for="card-cvc" class="block text-sm font-medium text-ink-700">CVC</label>
          <input
            id="card-cvc"
            name="card[cvc]"
            type="text"
            inputmode="numeric"
            autocomplete="cc-csc"
            placeholder="123"
            required
            class="mt-1 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500/30"
          />
        </div>
      </div>

      <%= if @card_error do %>
        <p class="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {@card_error}
        </p>
      <% end %>

      <div>
        <button
          type="submit"
          data-test-id="pay-button"
          phx-disable-with="Processing…"
          class="inline-flex min-h-11 items-center justify-center rounded-lg bg-teal-700 px-4 py-2 text-base font-semibold text-white hover:bg-teal-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-500 sm:text-sm"
        >
          Pay
        </button>
      </div>
    </.form>
    """
  end

  defp method_button_class(true) do
    "rounded-lg border-2 border-teal-700 bg-teal-50 px-3 py-3 text-sm font-semibold text-teal-900 transition"
  end

  defp method_button_class(false) do
    "rounded-lg border border-ink-200 bg-white px-3 py-3 text-sm font-medium text-ink-700 hover:border-teal-300 transition"
  end

  attr :booking, :map, required: true
  attr :slot, :map, required: true
  attr :centre, :map, required: true
  attr :exam, :map, required: true

  defp confirmed_card(assigns) do
    ~H"""
    <section class="mt-8 rounded-2xl border border-teal-300 bg-teal-50 p-6">
      <p class="font-mono text-xs uppercase tracking-widest text-teal-700">Reference</p>
      <p class="mt-1 font-mono text-2xl font-bold tracking-tight text-teal-900">
        {@booking.reference}
      </p>

      <dl class="mt-6 grid grid-cols-1 gap-y-3 text-sm sm:grid-cols-3">
        <dt class="font-medium text-ink-600">Exam</dt>
        <dd class="text-ink-900 sm:col-span-2">{@exam.name}</dd>
        <dt class="font-medium text-ink-600">Centre</dt>
        <dd class="text-ink-900 sm:col-span-2">{@centre.name}, {@centre.city}</dd>
        <dt class="font-medium text-ink-600">Starts</dt>
        <dd class="text-ink-900 sm:col-span-2">
          {Calendar.strftime(@slot.starts_at, "%A %d %B %Y · %H:%M")}
        </dd>
        <dt class="font-medium text-ink-600">Receipt</dt>
        <dd class="text-ink-900 sm:col-span-2">
          <a href={@booking.pdf_url} class="font-semibold text-teal-700 hover:underline">
            Download PDF
          </a>
        </dd>
      </dl>

      <div class="mt-8 flex flex-wrap gap-3">
        <.link
          navigate={~p"/search"}
          class="rounded-lg border border-ink-300 bg-white px-4 py-2 text-sm font-semibold text-ink-700 hover:bg-ink-50"
        >
          Find another exam
        </.link>
        <.link
          navigate={~p"/candidate/bookings"}
          class="inline-flex min-h-11 items-center justify-center rounded-lg bg-teal-700 px-4 py-2 text-base font-semibold text-white hover:bg-teal-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-500 sm:text-sm"
        >
          Your bookings
        </.link>
      </div>
    </section>
    """
  end

  defp format_price(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end
end
