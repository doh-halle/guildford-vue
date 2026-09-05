defmodule GuildfordVue.PDFGeneratorTest do
  @moduledoc """
  PDFGenerator behaviour + Stub adapter. Sprint 7 introduced the
  behaviour with a URL-returning stub; Sprint 9 Slice 2 changed
  the contract to return raw HTML/PDF bytes (the ReceiptController
  serves them on demand).
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.PDFGenerator
  alias GuildfordVue.PDFGenerator.Stub

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

  describe "Stub.render_receipt/1" do
    test "returns {:ok, bytes} that contain the booking reference" do
      assert {:ok, bytes} = Stub.render_receipt(fixture())
      assert is_binary(bytes)
      assert bytes =~ "GV-2026-AB34CD"
    end

    test "returns {:error, :invalid_data} for non-map input" do
      assert {:error, :invalid_data} = Stub.render_receipt(nil)
      assert {:error, :invalid_data} = Stub.render_receipt("nope")
    end
  end

  describe "PDFGenerator.render_receipt/1 (dispatch)" do
    test "delegates to the configured adapter (default: Stub in test env)" do
      assert {:ok, _} = PDFGenerator.render_receipt(fixture())
    end
  end
end
