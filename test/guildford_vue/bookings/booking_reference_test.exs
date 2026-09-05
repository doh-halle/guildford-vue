defmodule GuildfordVue.Bookings.BookingReferenceTest do
  @moduledoc """
  Sprint 7 Slice 1 — booking reference generator. Format:
  `GV-YYYY-XXXXXX` where YYYY is the booking year and XXXXXX is
  a 6-character random suffix (alphanumeric, uppercase, no I/O/0/1
  to avoid scanner / OCR confusion).
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Bookings.BookingReference

  describe "generate/0 and generate/1" do
    test "generate/0 — current year, valid format" do
      ref = BookingReference.generate()
      assert ref =~ ~r/\AGV-\d{4}-[A-Z2-9]{6}\z/

      year = Date.utc_today().year
      assert String.starts_with?(ref, "GV-#{year}-")
    end

    test "generate/1 — caller can pin the year" do
      ref = BookingReference.generate(2030)
      assert String.starts_with?(ref, "GV-2030-")
    end

    test "alphabet excludes scanner-confusable characters" do
      for _ <- 1..200 do
        ref = BookingReference.generate()
        suffix = String.split(ref, "-") |> List.last()
        # Reject I (looks like 1), O (looks like 0), 0, 1.
        for ch <- String.graphemes(suffix) do
          refute ch in ["I", "O", "0", "1"], "#{ref} contains forbidden #{ch}"
        end
      end
    end

    test "uniqueness — collisions in 1000 generates should be essentially nil" do
      refs = for _ <- 1..1000, do: BookingReference.generate()
      assert length(Enum.uniq(refs)) == 1000
    end
  end

  describe "valid?/1" do
    test "true for canonical format" do
      assert BookingReference.valid?("GV-2026-A4B7K9")
      assert BookingReference.valid?(BookingReference.generate())
    end

    test "false for malformed" do
      refute BookingReference.valid?("nope")
      refute BookingReference.valid?(nil)
      refute BookingReference.valid?("GV-26-A4B7K9")
      refute BookingReference.valid?("GV-2026-A4B7")
      # Lowercase suffix
      refute BookingReference.valid?("GV-2026-a4b7k9")
      # Forbidden chars in suffix
      refute BookingReference.valid?("GV-2026-IOOO00")
    end
  end
end
