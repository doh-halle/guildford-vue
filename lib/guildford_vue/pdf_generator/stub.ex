defmodule GuildfordVue.PDFGenerator.Stub do
  @moduledoc """
  Stub PDF generator — returns the HTML rendered by
  `ReceiptTemplate.render_html/1` as raw bytes. Tests + dev get a
  recognisable output without spawning Chromium.

  The `ReceiptController` sniffs the magic bytes (`%PDF` for real
  PDFs) to decide whether to send `text/html` or `application/pdf`,
  so the same controller works against either adapter.
  """
  @behaviour GuildfordVue.PDFGenerator

  alias GuildfordVue.Bookings.ReceiptTemplate

  @impl true
  def render_receipt(data) when is_map(data) do
    {:ok, ReceiptTemplate.render_html(data)}
  end

  def render_receipt(_), do: {:error, :invalid_data}
end
