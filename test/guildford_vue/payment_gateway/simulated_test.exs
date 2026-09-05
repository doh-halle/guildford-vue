defmodule GuildfordVue.PaymentGateway.SimulatedTest do
  @moduledoc """
  Sprint 8 Slice 3 — Simulated PaymentGateway adapter. Tests use
  `latency_ms: 0` and explicit `decline_rate` so they're
  deterministic + fast.
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.PaymentGateway.Simulated
  alias GuildfordVue.Payments.Card

  defp valid_card do
    {:ok, card} =
      Card.validate(%{
        "number" => "4242424242424242",
        "exp_month" => "12",
        "exp_year" => "2030",
        "cvc" => "123",
        "holder_name" => "Test User"
      })

    card
  end

  describe "Card-based methods" do
    test "valid card + 0% decline rate → {:ok, %{token, charged_at, provider, masked_pan}}" do
      assert {:ok, result} =
               Simulated.charge(4_500, %{
                 payment_method: :visa,
                 card: valid_card(),
                 latency_ms: 0,
                 decline_rate: 0.0
               })

      assert is_binary(result.token)
      assert String.starts_with?(result.token, "tok_sim_")
      assert %DateTime{} = result.charged_at
      assert result.provider == "visa"
      assert result.masked_pan =~ "4242"
    end

    test "valid card + 100% decline rate → {:error, :card_declined}" do
      assert {:error, :card_declined} =
               Simulated.charge(4_500, %{
                 payment_method: :mastercard,
                 card: valid_card(),
                 latency_ms: 0,
                 decline_rate: 1.0
               })
    end

    test "card-based method WITHOUT card → {:error, :invalid_card}" do
      assert {:error, :invalid_card} =
               Simulated.charge(4_500, %{
                 payment_method: :visa,
                 card: nil,
                 latency_ms: 0,
                 decline_rate: 0.0
               })
    end

    test "passes the card brand into the response provider" do
      {:ok, r1} =
        Simulated.charge(4_500, %{
          payment_method: :amex,
          card: valid_card(),
          latency_ms: 0,
          decline_rate: 0.0
        })

      assert r1.provider == "amex"
    end
  end

  describe "Wallet methods (no card)" do
    test "paypal succeeds with provider=paypal, masked_pan=nil" do
      assert {:ok, r} =
               Simulated.charge(4_500, %{
                 payment_method: :paypal,
                 latency_ms: 0,
                 decline_rate: 0.0
               })

      assert r.provider == "paypal"
      refute r.masked_pan
    end

    test "apple_pay succeeds + can be declined" do
      assert {:ok, _} =
               Simulated.charge(4_500, %{
                 payment_method: :apple_pay,
                 latency_ms: 0,
                 decline_rate: 0.0
               })

      assert {:error, :card_declined} =
               Simulated.charge(4_500, %{
                 payment_method: :apple_pay,
                 latency_ms: 0,
                 decline_rate: 1.0
               })
    end
  end

  describe "Application-config defaults" do
    setup do
      # Save + restore the global config so this test is hermetic.
      previous = Application.get_env(:guildford_vue, :payment_decline_rate)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:guildford_vue, :payment_decline_rate, previous),
          else: Application.delete_env(:guildford_vue, :payment_decline_rate)
      end)

      :ok
    end

    test "decline_rate from app env when not given in opts" do
      Application.put_env(:guildford_vue, :payment_decline_rate, 1.0)

      assert {:error, :card_declined} =
               Simulated.charge(4_500, %{
                 payment_method: :visa,
                 card: valid_card(),
                 latency_ms: 0
               })
    end
  end

  describe "Default opts" do
    test "missing :payment_method → falls back to :card_declined (defensive)" do
      assert {:error, :invalid_payment_method} =
               Simulated.charge(4_500, %{latency_ms: 0, decline_rate: 0.0})
    end

    test "amount must be positive" do
      assert {:error, :invalid_amount} =
               Simulated.charge(0, %{
                 payment_method: :paypal,
                 latency_ms: 0,
                 decline_rate: 0.0
               })
    end
  end
end
