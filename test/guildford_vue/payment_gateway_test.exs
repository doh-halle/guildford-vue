defmodule GuildfordVue.PaymentGatewayTest do
  @moduledoc """
  Sprint 7 Slice 2 — PaymentGateway behaviour + adapters. Real
  payment processing arrives in Sprint 8; this slice ships the
  behaviour + always-succeed Stub adapter so the booking pipeline
  has something to call.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.PaymentGateway
  alias GuildfordVue.PaymentGateway.{Decline, Stub}

  describe "Stub.charge/2" do
    test "always returns {:ok, %{token, charged_at}}" do
      assert {:ok, %{token: token, charged_at: %DateTime{}}} =
               Stub.charge(4_500, %{candidate_id: Ecto.UUID.generate()})

      assert is_binary(token)
      assert String.starts_with?(token, "tok_stub_")
    end
  end

  describe "Decline.charge/2" do
    test "always returns {:error, :card_declined}" do
      assert {:error, :card_declined} =
               Decline.charge(4_500, %{candidate_id: Ecto.UUID.generate()})
    end
  end

  describe "PaymentGateway.charge/2 (dispatch)" do
    test "delegates to the configured adapter (default: Stub in test env)" do
      assert {:ok, _} = PaymentGateway.charge(1_000, %{})
    end
  end
end
