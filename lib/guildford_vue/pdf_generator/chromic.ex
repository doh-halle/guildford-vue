defmodule GuildfordVue.PDFGenerator.Chromic do
  @moduledoc """
  Real-PDF adapter backed by `ChromicPDF` (which manages a pool
  of headless Chromium processes). Used in dev/prod; the test env
  stays on `GuildfordVue.PDFGenerator.Stub` to keep the suite
  Chromium-free.

  The Sprint 9 Slice 1 `ReceiptTemplate` produces the HTML string
  this adapter feeds to ChromicPDF. Output: `{:ok, pdf_binary}`.

  ## Startup

  `ChromicPDF` is added to the supervision tree by
  `GuildfordVue.Application` only when configured (`config
  :guildford_vue, :start_chromic_pdf, true`). The test env leaves
  it off; dev + prod turn it on.

  When the adapter is invoked WITHOUT a running ChromicPDF process
  it returns `{:error, :chromic_unavailable}` rather than letting
  the GenServer call crash — operators get a clean diagnostic.
  """
  @behaviour GuildfordVue.PDFGenerator

  alias GuildfordVue.Bookings.ReceiptTemplate

  @impl true
  def render_receipt(data) when is_map(data) do
    if running?() do
      do_render(data)
    else
      {:error, :chromic_unavailable}
    end
  end

  def render_receipt(_), do: {:error, :invalid_data}

  defp running?, do: Process.whereis(ChromicPDF) != nil

  defp do_render(data) do
    html = ReceiptTemplate.render_html(data)

    case ChromicPDF.print_to_pdf({:html, html}) do
      {:ok, base64} ->
        {:ok, Base.decode64!(base64)}

      other ->
        {:error, {:chromic_failed, other}}
    end
  end
end
