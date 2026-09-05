defmodule GuildfordVue.Candidates.CandidateNotifierPdfAttachmentTest do
  @moduledoc """
  Sprint 9 Slice 4 — booking confirmation email carries the PDF
  receipt as an attachment.
  """
  use ExUnit.Case, async: true
  import Swoosh.TestAssertions

  alias GuildfordVue.Candidates.Candidate
  alias GuildfordVue.Candidates.CandidateNotifier

  defp candidate do
    %Candidate{
      email: "alice@example.com",
      first_name: "Alice"
    }
  end

  defp meta do
    %{
      reference: "GV-2026-AB34CD",
      pdf_url: "/candidate/bookings/GV-2026-AB34CD/receipt.pdf",
      pdf_bytes: "%PDF-1.4 stub bytes",
      starts_at: ~U[2026-06-15 10:00:00.000000Z],
      exam_name: "Cisco CCNA"
    }
  end

  test "email has a single attachment with the reference as filename" do
    {:ok, _} = CandidateNotifier.deliver_booking_confirmation_email(candidate(), meta())

    assert_email_sent(fn email ->
      [att] = email.attachments

      att.filename == "GV-2026-AB34CD.pdf" and
        att.content_type == "application/pdf" and
        att.data == "%PDF-1.4 stub bytes"
    end)
  end

  test "email body still mentions the booking reference + URL" do
    {:ok, _} = CandidateNotifier.deliver_booking_confirmation_email(candidate(), meta())

    assert_email_sent(fn email ->
      email.text_body =~ "GV-2026-AB34CD" and
        email.text_body =~ "/candidate/bookings/GV-2026-AB34CD/receipt.pdf"
    end)
  end

  test "missing pdf_bytes → email is still sent (best-effort attachment)" do
    meta_no_pdf = Map.delete(meta(), :pdf_bytes)

    assert {:ok, _} =
             CandidateNotifier.deliver_booking_confirmation_email(candidate(), meta_no_pdf)

    assert_email_sent(fn email ->
      email.attachments == [] and email.text_body =~ "GV-2026-AB34CD"
    end)
  end
end
