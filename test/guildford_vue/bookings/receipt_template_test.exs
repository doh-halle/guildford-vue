defmodule GuildfordVue.Bookings.ReceiptTemplateTest do
  @moduledoc """
  Sprint 9 Slice 1 — pure receipt HTML template. Tested in
  isolation so the dissertation can demonstrate the FP separation:
  the same template renders identically into a browser preview, an
  email attachment, and a ChromicPDF input — no per-target branching.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Bookings.ReceiptTemplate

  defp fixture do
    %{
      booking: %{
        reference: "GV-2026-AB34CD",
        price_pence: 4500,
        paid_at: ~U[2026-05-30 17:42:00.000000Z]
      },
      candidate: %{
        first_name: "Alice",
        last_name: "Worthington",
        email: "alice@example.com"
      },
      exam: %{
        name: "Cisco CCNA",
        code: "CCNA",
        certification_body: "Cisco",
        duration_minutes: 120
      },
      centre: %{
        name: "Manchester Examination Hub",
        address_line_1: "12 Deansgate",
        address_line_2: nil,
        city: "Manchester",
        postcode: "M1 1AE"
      },
      slot: %{
        starts_at: ~U[2026-06-15 10:00:00.000000Z]
      }
    }
  end

  describe "render_html/1" do
    test "includes booking reference + candidate name + exam + centre" do
      html = ReceiptTemplate.render_html(fixture())

      assert html =~ "GV-2026-AB34CD"
      assert html =~ "Alice Worthington"
      assert html =~ "Cisco CCNA"
      assert html =~ "Manchester Examination Hub"
      assert html =~ "12 Deansgate"
      assert html =~ "M1 1AE"
    end

    test "includes slot start time in human form" do
      html = ReceiptTemplate.render_html(fixture())
      assert html =~ "15 June 2026"
      assert html =~ "10:00"
    end

    test "includes price formatted as £NN.NN" do
      html = ReceiptTemplate.render_html(fixture())
      assert html =~ "£45.00"
    end

    test "includes an inline SVG QR code carrying the booking reference" do
      html = ReceiptTemplate.render_html(fixture())
      # eqrcode renders an SVG element.
      assert html =~ "<svg"
      # The QR encodes the reference — we can't decode it from the SVG
      # in a test, but we can assert the SVG exists and has matrix
      # rect elements (the QR pixels).
      assert html =~ "rect"
    end

    test "includes a 'Powered by Guildford Vue' footer" do
      html = ReceiptTemplate.render_html(fixture())
      assert html =~ "Guildford Vue"
    end

    test "is self-contained — no external CSS / JS references" do
      html = ReceiptTemplate.render_html(fixture())
      # Receipts get rendered into PDFs offline; external requests
      # would either fail or leak metadata.
      refute html =~ "<link"
      refute html =~ "<script"
    end
  end
end
