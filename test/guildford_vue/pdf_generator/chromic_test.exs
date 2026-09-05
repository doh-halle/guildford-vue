defmodule GuildfordVue.PDFGenerator.ChromicTest do
  @moduledoc """
  Sprint 9 Slice 3 — Chromic adapter unit tests.

  The full rendering test would require ChromicPDF + headless
  Chromium, which we deliberately don't start in the test env (heavy
  + flaky in CI). We test the error path here — when ChromicPDF is
  not running, the adapter returns `{:error, :chromic_unavailable}`
  rather than crashing.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.PDFGenerator.Chromic

  defp fixture do
    %{
      booking: %{
        reference: "GV-2026-AB34CD",
        price_pence: 4500,
        paid_at: ~U[2026-05-30 17:42:00.000000Z]
      },
      candidate: %{first_name: "A", last_name: "B", email: "a@b.test"},
      exam: %{name: "X", code: "X", certification_body: "Z", duration_minutes: 60},
      centre: %{
        name: "C",
        address_line_1: "1 St",
        address_line_2: nil,
        city: "City",
        postcode: "P1 1P"
      },
      slot: %{starts_at: ~U[2026-06-01 10:00:00.000000Z]}
    }
  end

  describe "render_receipt/1" do
    test "returns {:error, :chromic_unavailable} when ChromicPDF process is not running" do
      # Test env doesn't start ChromicPDF — confirms the adapter
      # surfaces a clean error rather than raising.
      assert {:error, :chromic_unavailable} = Chromic.render_receipt(fixture())
    end

    test "returns {:error, :invalid_data} for non-map input" do
      assert {:error, :invalid_data} = Chromic.render_receipt(nil)
      assert {:error, :invalid_data} = Chromic.render_receipt("nope")
    end
  end
end
