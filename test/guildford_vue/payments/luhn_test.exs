defmodule GuildfordVue.Payments.LuhnTest do
  @moduledoc """
  Sprint 8 Slice 1 — Luhn checksum module. Pure function; covers
  every PRD-mentioned card brand at the algorithm level.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Payments.Luhn

  describe "valid?/1" do
    test "accepts canonical test PANs from common brands" do
      # These are the standard PCI / brand-published test numbers —
      # public, not real cardholder data.
      assert Luhn.valid?("4242424242424242"), "Visa test PAN"
      assert Luhn.valid?("4111111111111111"), "Visa Classic test PAN"
      assert Luhn.valid?("5555555555554444"), "Mastercard test PAN"
      assert Luhn.valid?("378282246310005"), "Amex test PAN"
      assert Luhn.valid?("6011111111111117"), "Discover test PAN"
    end

    test "accepts numbers with whitespace + hyphens" do
      assert Luhn.valid?("4242 4242 4242 4242")
      assert Luhn.valid?("4242-4242-4242-4242")
    end

    test "rejects PANs with an altered last digit" do
      refute Luhn.valid?("4242424242424243")
      refute Luhn.valid?("5555555555554440")
    end

    test "rejects too-short / too-long" do
      refute Luhn.valid?("42")
      refute Luhn.valid?(String.duplicate("4", 20))
    end

    test "rejects non-numeric / nil / empty" do
      refute Luhn.valid?(nil)
      refute Luhn.valid?("")
      refute Luhn.valid?("abcd")
      refute Luhn.valid?(:atom)
    end
  end
end
