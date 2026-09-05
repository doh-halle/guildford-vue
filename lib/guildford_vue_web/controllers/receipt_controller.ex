defmodule GuildfordVueWeb.ReceiptController do
  @moduledoc """
  Serves booking receipts (PRD §4.9). Two formats:

    * `.html` — in-browser preview, useful in dev
    * `.pdf`  — downloadable, runs through `PDFGenerator` (Sprint 9
      Slice 3 swaps the Stub for Chromic in dev/prod)

  Authorisation: the booking must belong to the signed-in
  candidate. Unknown / other-candidate's references redirect to
  the bookings list with a generic flash — no information leak
  about whether the reference exists.

  Why a controller rather than a LiveView?

    * PDF/HTML responses aren't LV-shaped; they're plain HTTP
      with a `content-disposition: attachment` header for the PDF.
    * The renderer is pure (`ReceiptTemplate.render_html/1`) so
      the controller is a thin glue layer — no socket state needed.
  """
  use GuildfordVueWeb, :controller

  alias GuildfordVue.{Bookings, ExamCentres, Exams, PDFGenerator, Slots}
  alias GuildfordVue.Bookings.ReceiptTemplate

  # Sprint 11.5 Slice 1 — per-IP rate-limit on receipt fetches to
  # block scrape loops. 30 / IP / hour is generous for a real user
  # (re-downloads + refreshes) but tight enough to throttle a bot.
  plug GuildfordVueWeb.Plugs.RateLimitForm,
       [
         scope: "receipt-pdf",
         limit: 30,
         scale_ms: 60 * 60 * 1000,
         redirect_to: "/candidate/bookings",
         flash_message: "Too many receipt requests. Please try again in an hour."
       ]
       when action in [:show_pdf]

  # sobelow_skip ["XSS.SendResp"]
  # The template HTML-escapes every user-controlled field via
  # ReceiptTemplate.escape/1; the only unescaped interpolations
  # are system-generated (booking.reference is regex-validated;
  # the rest are integers + Calendar.strftime output).
  def show_html(conn, %{"reference" => ref}) do
    case load_for(conn, ref) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, ReceiptTemplate.render_html(data))

      :not_found ->
        not_found(conn)
    end
  end

  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  # `bytes` is the raw PDF/HTML body returned by PDFGenerator;
  # `content_type_for/1` is a closed-set helper returning one of two
  # literals, picked by magic-byte sniff. No user input flows into
  # either argument.
  def show_pdf(conn, %{"reference" => ref}) do
    case load_for(conn, ref) do
      {:ok, data} ->
        case PDFGenerator.render_receipt(data) do
          {:ok, bytes} ->
            filename = "#{data.booking.reference}.pdf"

            conn
            |> put_resp_content_type(content_type_for(bytes))
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, bytes)

          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not generate the PDF (#{inspect(reason)}).")
            |> redirect(to: ~p"/candidate/bookings")
        end

      :not_found ->
        not_found(conn)
    end
  end

  # ---- helpers -----------------------------------------------------

  defp load_for(conn, ref) do
    candidate = conn.assigns.current_candidate

    case Bookings.get_booking_by_reference(ref) do
      %{candidate_id: cid} = booking when cid == candidate.id ->
        {:ok,
         %{
           booking: booking,
           candidate: candidate,
           exam: Exams.get_exam!(booking.exam_id),
           centre: ExamCentres.get_exam_centre!(booking.exam_centre_id),
           slot: Slots.get_slot!(booking.slot_id)
         }}

      _ ->
        :not_found
    end
  end

  defp not_found(conn) do
    conn
    |> put_flash(:error, "We could not find that booking.")
    |> redirect(to: ~p"/candidate/bookings")
  end

  # Stub returns HTML-as-bytes for tests; Chromic returns a true PDF.
  # Sniff by magic bytes so the response declares the right MIME.
  defp content_type_for(<<"%PDF", _::binary>>), do: "application/pdf"
  defp content_type_for(_), do: "text/html"
end
