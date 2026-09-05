defmodule GuildfordVue.Payments.CardTest do
  @moduledoc """
  Sprint 8 Slice 1 — pure CardDetails struct + validation +
  masking. Used by the form on the booking page, the Simulated
  payment adapter, and the Payment-row serializer.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Payments.Card

  describe "validate/1 — happy paths" do
    test "accepts a valid card with future expiry" do
      assert {:ok, %Card{} = card} =
               Card.validate(%{
                 "number" => "4242 4242 4242 4242",
                 "exp_month" => "12",
                 "exp_year" => "2030",
                 "cvc" => "123",
                 "holder_name" => "Alice Worthington"
               })

      # Number normalised — strip whitespace, store as-is (full PAN
      # is never persisted — see masked_pan/1).
      assert card.number == "4242424242424242"
      assert card.exp_month == 12
      assert card.exp_year == 2030
      assert card.cvc == "123"
      assert card.holder_name == "Alice Worthington"
    end

    test "accepts Amex 4-digit CVC" do
      assert {:ok, %Card{cvc: "1234"}} =
               Card.validate(%{
                 "number" => "378282246310005",
                 "exp_month" => "06",
                 "exp_year" => "2030",
                 "cvc" => "1234",
                 "holder_name" => "Amex Holder"
               })
    end
  end

  describe "validate/1 — failures" do
    test "fails Luhn" do
      assert {:error, :invalid_card_number} =
               Card.validate(%{
                 "number" => "4242424242424243",
                 "exp_month" => "12",
                 "exp_year" => "2030",
                 "cvc" => "123",
                 "holder_name" => "X"
               })
    end

    test "fails expired card" do
      assert {:error, :card_expired} =
               Card.validate(%{
                 "number" => "4242424242424242",
                 "exp_month" => "01",
                 "exp_year" => "2020",
                 "cvc" => "123",
                 "holder_name" => "X"
               })
    end

    test "fails missing CVC" do
      assert {:error, :invalid_cvc} =
               Card.validate(%{
                 "number" => "4242424242424242",
                 "exp_month" => "12",
                 "exp_year" => "2030",
                 "cvc" => "",
                 "holder_name" => "X"
               })
    end

    test "fails non-numeric CVC" do
      assert {:error, :invalid_cvc} =
               Card.validate(%{
                 "number" => "4242424242424242",
                 "exp_month" => "12",
                 "exp_year" => "2030",
                 "cvc" => "abc",
                 "holder_name" => "X"
               })
    end

    test "fails out-of-range month" do
      assert {:error, :invalid_expiry} =
               Card.validate(%{
                 "number" => "4242424242424242",
                 "exp_month" => "13",
                 "exp_year" => "2030",
                 "cvc" => "123",
                 "holder_name" => "X"
               })
    end

    test "fails missing holder name" do
      assert {:error, :missing_holder_name} =
               Card.validate(%{
                 "number" => "4242424242424242",
                 "exp_month" => "12",
                 "exp_year" => "2030",
                 "cvc" => "123",
                 "holder_name" => ""
               })
    end
  end

  describe "masked_pan/1" do
    test "stars all but the last 4 digits" do
      {:ok, card} = Card.validate(valid_attrs())
      assert Card.masked_pan(card) == "•••• •••• •••• 4242"
    end

    test "amex form (4-6-5) — last 4 only, the rest stars" do
      {:ok, card} =
        Card.validate(%{
          "number" => "378282246310005",
          "exp_month" => "06",
          "exp_year" => "2030",
          "cvc" => "1234",
          "holder_name" => "Amex Holder"
        })

      # Length is 15 → 11 stars + 4 digits
      masked = Card.masked_pan(card)
      assert String.ends_with?(masked, "0005")
      refute masked =~ "3782"
    end
  end

  defp valid_attrs do
    %{
      "number" => "4242 4242 4242 4242",
      "exp_month" => "12",
      "exp_year" => "2030",
      "cvc" => "123",
      "holder_name" => "Alice Worthington"
    }
  end
end
