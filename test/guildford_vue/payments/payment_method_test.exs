defmodule GuildfordVue.Payments.PaymentMethodTest do
  @moduledoc """
  Sprint 8 Slice 2 — provider ADT + helpers. Pure, exhaustively
  pattern-matched.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Payments.PaymentMethod

  describe "all/0" do
    test "enumerates the six PRD-mentioned methods in display order" do
      assert PaymentMethod.all() == [
               :visa,
               :mastercard,
               :amex,
               :paypal,
               :apple_pay,
               :google_pay
             ]
    end
  end

  describe "label/1 — exhaustive over ADT" do
    test "every variant has a human label" do
      for m <- PaymentMethod.all() do
        assert is_binary(PaymentMethod.label(m))
        assert PaymentMethod.label(m) != ""
      end
    end

    test "labels match the PRD wording" do
      assert PaymentMethod.label(:visa) == "Visa"
      assert PaymentMethod.label(:mastercard) == "Mastercard"
      assert PaymentMethod.label(:amex) == "Amex"
      assert PaymentMethod.label(:paypal) == "PayPal"
      assert PaymentMethod.label(:apple_pay) == "Apple Pay"
      assert PaymentMethod.label(:google_pay) == "Google Pay"
    end
  end

  describe "accepts_card?/1" do
    test "visa / mastercard / amex are card brands" do
      assert PaymentMethod.accepts_card?(:visa)
      assert PaymentMethod.accepts_card?(:mastercard)
      assert PaymentMethod.accepts_card?(:amex)
    end

    test "paypal / apple_pay / google_pay are wallets — no card form" do
      refute PaymentMethod.accepts_card?(:paypal)
      refute PaymentMethod.accepts_card?(:apple_pay)
      refute PaymentMethod.accepts_card?(:google_pay)
    end
  end

  describe "detect_from_pan/1" do
    test "Visa — 4xxx" do
      assert :visa = PaymentMethod.detect_from_pan("4242424242424242")
      assert :visa = PaymentMethod.detect_from_pan("4111111111111111")
    end

    test "Mastercard — 51-55 + 22-27" do
      assert :mastercard = PaymentMethod.detect_from_pan("5555555555554444")
      assert :mastercard = PaymentMethod.detect_from_pan("5105105105105100")
      assert :mastercard = PaymentMethod.detect_from_pan("2221000000000009")
      assert :mastercard = PaymentMethod.detect_from_pan("2720990000000003")
    end

    test "Amex — 34 / 37" do
      assert :amex = PaymentMethod.detect_from_pan("378282246310005")
      assert :amex = PaymentMethod.detect_from_pan("341234567890123")
    end

    test "unknown prefix → nil" do
      assert is_nil(PaymentMethod.detect_from_pan("6011111111111117"))
      assert is_nil(PaymentMethod.detect_from_pan("9999999999999999"))
    end

    test "tolerates whitespace + hyphens" do
      assert :visa = PaymentMethod.detect_from_pan("4242 4242 4242 4242")
      assert :amex = PaymentMethod.detect_from_pan("3782-822463-10005")
    end

    test "nil / non-string → nil" do
      assert is_nil(PaymentMethod.detect_from_pan(nil))
      assert is_nil(PaymentMethod.detect_from_pan(""))
      assert is_nil(PaymentMethod.detect_from_pan(:atom))
    end
  end

  describe "from_string/1 + to_string/1 round-trip" do
    test "atom ↔ string" do
      for m <- PaymentMethod.all() do
        s = PaymentMethod.to_string(m)
        assert PaymentMethod.from_string(s) == {:ok, m}
      end
    end

    test "unknown string → :error" do
      assert :error = PaymentMethod.from_string("bitcoin")
      assert :error = PaymentMethod.from_string("")
      assert :error = PaymentMethod.from_string(nil)
    end
  end
end
