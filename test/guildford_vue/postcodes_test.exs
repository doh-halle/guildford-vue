defmodule GuildfordVue.PostcodesTest do
  @moduledoc """
  Sprint 5 Slice 1 — UK postcode validation. The regex covers the
  common UK postcode formats per the ONS structure, normalising
  whitespace and case.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Postcodes

  describe "validate/1" do
    test "accepts canonical formats (returns the canonical OUT IN form)" do
      for pc <-
            ~w(SW1A1AA EC1A1BB M11AE B11AA LS11UR G11XQ EH11YZ CF101EP BS14DJ L18JQ S12HE NE14ST NG15FS GU14LZ) do
        assert {:ok, normalised} = Postcodes.validate(pc),
               "expected #{pc} valid"

        # Returned value is always canonicalised — OUT IN with single space.
        assert String.contains?(normalised, " ")
        assert normalised == Postcodes.format(pc)
      end
    end

    test "accepts formats with internal whitespace" do
      assert {:ok, "M1 1AE"} = Postcodes.validate("M1 1AE")
      assert {:ok, "SW1A 1AA"} = Postcodes.validate("SW1A 1AA")
    end

    test "normalises case + trims surrounding whitespace" do
      assert {:ok, "M1 1AE"} = Postcodes.validate(" m1 1ae ")
      assert {:ok, "EC1A 1BB"} = Postcodes.validate("ec1a 1bb")
    end

    test "rejects empty / nil / non-string" do
      assert {:error, :invalid_postcode} = Postcodes.validate(nil)
      assert {:error, :invalid_postcode} = Postcodes.validate("")
      assert {:error, :invalid_postcode} = Postcodes.validate(:atom)
    end

    test "rejects obviously bad formats" do
      assert {:error, :invalid_postcode} = Postcodes.validate("NOTAPOSTCODE")
      assert {:error, :invalid_postcode} = Postcodes.validate("12345")
      assert {:error, :invalid_postcode} = Postcodes.validate("XX99 9XX9")
    end
  end

  describe "format/1" do
    test "canonicalises to OUT IN with single space" do
      assert Postcodes.format("M11AE") == "M1 1AE"
      assert Postcodes.format("ec1a1bb") == "EC1A 1BB"
      assert Postcodes.format("SW1A 1AA") == "SW1A 1AA"
    end
  end

  describe "valid?/1" do
    test "true for valid, false for invalid" do
      assert Postcodes.valid?("M1 1AE")
      refute Postcodes.valid?("nope")
    end
  end
end
