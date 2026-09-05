defmodule GuildfordVue.PDFGenerator do
  @moduledoc """
  Boundary for receipt-PDF rendering. Two adapters:

    * `GuildfordVue.PDFGenerator.Stub` — returns the
      ReceiptTemplate-rendered HTML as raw bytes. Used in tests
      so the suite doesn't spawn Chromium. The ReceiptController
      sniffs the magic bytes and serves `text/html` when it gets
      HTML, `application/pdf` when it gets a real PDF.
    * `GuildfordVue.PDFGenerator.Chromic` — (Slice 3) runs the
      HTML through `ChromicPDF.print_to_pdf/2` to produce a real
      PDF. Used in dev + prod.

  Pick via `config :guildford_vue, :pdf_generator, Adapter`.

  Sprint 9 changed the contract from `{:ok, url}` to
  `{:ok, binary}` — the binary is the rendered PDF (or HTML for
  Stub). The booking's `pdf_url` field is now always
  `/candidate/bookings/<reference>/receipt.pdf`, hitting
  `ReceiptController.show_pdf/2` which calls back into this
  module on-demand. No persistent storage layer needed.
  """

  @type render_result :: {:ok, binary()} | {:error, atom()}

  @callback render_receipt(data :: map()) :: render_result()

  @spec render_receipt(map()) :: render_result()
  def render_receipt(data) do
    adapter().render_receipt(data)
  end

  defp adapter do
    Application.get_env(:guildford_vue, :pdf_generator, GuildfordVue.PDFGenerator.Stub)
  end
end
