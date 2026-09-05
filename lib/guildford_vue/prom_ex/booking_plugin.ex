defmodule GuildfordVue.PromEx.BookingPlugin do
  @moduledoc """
  Sprint 12 Slice 2 — PromEx plugin for booking-pipeline +
  per-centre GenServer health.

  Emits two families:
    * Polled gauges read on a fixed interval (count of running
      CentreServers, mailbox depth percentiles).
    * Event counters for booking-pipeline outcomes
      (`[:guildford_vue, :booking, :created | :payment_declined |
      :slot_sold_out]`).

  ## Custom telemetry events

  Sprint 12 takes the opportunity to emit booking-pipeline events
  alongside the existing security ones. The pipeline already
  audit-logs every outcome via `AuditLog.append/2`; this plugin
  just shadows the calls with `:telemetry.execute/3` so PromEx
  picks them up.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:guildford_vue_booking_event_metrics, [
      counter(
        [:guildford_vue, :booking, :created, :count],
        event_name: [:guildford_vue, :booking, :created],
        description: "Bookings successfully created",
        tags: [:centre_id]
      ),
      counter(
        [:guildford_vue, :booking, :payment_declined, :count],
        event_name: [:guildford_vue, :booking, :payment_declined],
        description: "Booking attempts where the payment was declined"
      ),
      counter(
        [:guildford_vue, :booking, :slot_sold_out, :count],
        event_name: [:guildford_vue, :booking, :slot_sold_out],
        description: "Booking attempts that lost the slot race"
      )
    ])
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    Polling.build(
      :guildford_vue_centre_server_polling,
      poll_rate,
      {__MODULE__, :execute_centre_metrics, []},
      [
        last_value(
          [:guildford_vue, :centres, :servers, :running],
          event_name: [:guildford_vue, :centres, :poll],
          description: "Number of live per-centre GenServers",
          measurement: :running_count
        ),
        last_value(
          [:guildford_vue, :centres, :mailbox, :max],
          event_name: [:guildford_vue, :centres, :poll],
          description: "Deepest mailbox across all per-centre GenServers",
          measurement: :max_mailbox
        )
      ]
    )
  end

  @doc false
  def execute_centre_metrics do
    running = GuildfordVue.SystemHealth.running_centres()

    measurements = %{
      running_count: length(running),
      max_mailbox:
        case running do
          [] -> 0
          centres -> centres |> Enum.map(& &1.mailbox) |> Enum.max()
        end
    }

    :telemetry.execute([:guildford_vue, :centres, :poll], measurements, %{})
  end
end
