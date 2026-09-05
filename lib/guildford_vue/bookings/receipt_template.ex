defmodule GuildfordVue.Bookings.ReceiptTemplate do
  @moduledoc """
  Self-contained HTML receipt for a booking (PRD §4.9). Pure
  function: takes a struct-like map with the booking, candidate,
  exam, centre, and slot, returns an HTML string ready to be:

    * served as text/html for an in-browser preview
    * piped through ChromicPDF to produce a PDF
    * attached to the confirmation email (as HTML or PDF)

  No external CSS / JS / fonts — the dissertation's "rendered
  offline by ChromicPDF" path can't make network requests at
  render time, so everything is inlined.

  The QR code carries the booking reference. Scanning it on a
  printed receipt at the exam centre lets the centre operator
  look the booking up without typing the ref.
  """

  @spec render_html(map()) :: String.t()
  def render_html(%{
        booking: booking,
        candidate: candidate,
        exam: exam,
        centre: centre,
        slot: slot
      }) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <title>Booking #{booking.reference} — Guildford Vue receipt</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
               color: #1a1a1a; max-width: 720px; margin: 40px auto; padding: 0 24px; }
        header { display: flex; justify-content: space-between; align-items: flex-start;
                 border-bottom: 2px solid #0d9488; padding-bottom: 16px; margin-bottom: 24px; }
        h1 { font-size: 28px; margin: 0 0 4px 0; color: #0f766e; }
        .reference { font-family: ui-monospace, SFMono-Regular, monospace;
                     font-size: 22px; font-weight: 700; color: #0f766e; }
        .qr { width: 120px; height: 120px; }
        dl { margin: 0; }
        dt { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em;
             color: #6b7280; margin-top: 16px; }
        dd { font-size: 16px; margin: 4px 0 0 0; color: #111827; }
        .price { font-size: 22px; font-weight: 700; color: #0f766e; margin-top: 24px; }
        footer { margin-top: 40px; font-size: 11px; color: #6b7280;
                 border-top: 1px solid #e5e7eb; padding-top: 12px; }
      </style>
    </head>
    <body>
      <header>
        <div>
          <h1>Booking receipt</h1>
          <p class="reference">#{escape(booking.reference)}</p>
        </div>
        <div class="qr">#{qr_svg(booking.reference)}</div>
      </header>

      <dl>
        <dt>Candidate</dt>
        <dd>#{escape(candidate.first_name)} #{escape(candidate.last_name)}<br />#{escape(candidate.email)}</dd>

        <dt>Exam</dt>
        <dd>#{escape(exam.name)} (#{escape(exam.code)}) — #{escape(exam.certification_body)}</dd>

        <dt>Duration</dt>
        <dd>#{exam.duration_minutes} minutes</dd>

        <dt>Centre</dt>
        <dd>
          #{escape(centre.name)}<br />
          #{address_lines(centre)}
        </dd>

        <dt>When</dt>
        <dd>#{Calendar.strftime(slot.starts_at, "%A %d %B %Y · %H:%M UTC")}</dd>
      </dl>

      <p class="price">£#{format_price(booking.price_pence)}</p>

      <footer>
        Powered by Guildford Vue. Paid #{Calendar.strftime(booking.paid_at, "%d %B %Y")}.
        Present this receipt (or scan its QR) at the centre on the day of your exam.
      </footer>
    </body>
    </html>
    """
  end

  # ---- helpers -----------------------------------------------------

  defp address_lines(%{address_line_2: nil} = c),
    do: "#{escape(c.address_line_1)}<br />#{escape(c.city)} #{escape(c.postcode)}"

  defp address_lines(%{address_line_2: a2} = c) do
    "#{escape(c.address_line_1)}<br />#{escape(a2)}<br />#{escape(c.city)} #{escape(c.postcode)}"
  end

  defp qr_svg(reference) do
    reference
    |> EQRCode.encode()
    |> EQRCode.svg(width: 120, viewbox: true)
  end

  defp format_price(pence) do
    pounds = div(pence, 100)
    p = rem(pence, 100)
    "#{pounds}.#{String.pad_leading(Integer.to_string(p), 2, "0")}"
  end

  defp escape(nil), do: ""

  defp escape(s) when is_binary(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape(other), do: escape(to_string(other))
end
