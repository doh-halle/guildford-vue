defmodule GuildfordVue.Slots.AvailabilityTest do
  @moduledoc """
  Sprint 6 Slice 1 — slot availability ADT. Pure classifier so the
  ADT pattern matching is testable without booting the supervision
  tree or any HTML rendering.

  ADT: `:available | :limited | :fully_booked | :cancelled`. Tests
  cover every variant exhaustively so a future schema change that
  drops or adds a status surfaces immediately.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.Slots.Availability
  alias GuildfordVue.Slots.Slot

  defp slot(opts) do
    %Slot{
      capacity: Keyword.get(opts, :capacity, 10),
      available_count: Keyword.get(opts, :available_count, 10),
      status: Keyword.get(opts, :status, "open")
    }
  end

  describe "classify/1 ADT" do
    test ":cancelled — status \"cancelled\" beats everything else" do
      assert :cancelled = Availability.classify(slot(status: "cancelled", available_count: 0))
      assert :cancelled = Availability.classify(slot(status: "cancelled", available_count: 5))
    end

    test ":fully_booked — open status but available_count is 0" do
      assert :fully_booked = Availability.classify(slot(available_count: 0))
      assert :fully_booked = Availability.classify(slot(status: "full", available_count: 0))
    end

    test ":limited — between 1 and 25% of capacity" do
      assert :limited = Availability.classify(slot(capacity: 20, available_count: 1))
      assert :limited = Availability.classify(slot(capacity: 20, available_count: 5))
    end

    test ":available — above 25% of capacity" do
      assert :available = Availability.classify(slot(capacity: 20, available_count: 6))
      assert :available = Availability.classify(slot(capacity: 20, available_count: 20))
    end

    test "edge: capacity 1 → 1/1 = :available, 0/1 = :fully_booked" do
      assert :available = Availability.classify(slot(capacity: 1, available_count: 1))
      assert :fully_booked = Availability.classify(slot(capacity: 1, available_count: 0))
    end

    test "edge: capacity 4 → 1/4 = :limited (25% boundary is exclusive)" do
      assert :limited = Availability.classify(slot(capacity: 4, available_count: 1))
      assert :available = Availability.classify(slot(capacity: 4, available_count: 2))
    end
  end

  describe "all/0" do
    test "exhaustively enumerates every ADT value" do
      assert [:available, :limited, :fully_booked, :cancelled] = Availability.all()
    end
  end

  describe "label/1" do
    test "every ADT variant has a human-readable label" do
      for state <- Availability.all() do
        assert is_binary(Availability.label(state))
      end
    end
  end

  describe "tailwind_classes/1" do
    test "every ADT variant maps to a non-empty class string" do
      for state <- Availability.all() do
        assert is_binary(Availability.tailwind_classes(state))
        assert Availability.tailwind_classes(state) != ""
      end
    end

    test ":available → green tones" do
      assert Availability.tailwind_classes(:available) =~ "teal"
    end

    test ":limited → amber tones" do
      assert Availability.tailwind_classes(:limited) =~ "amber"
    end

    test ":fully_booked → red tones" do
      assert Availability.tailwind_classes(:fully_booked) =~ "red"
    end

    test ":cancelled → grey tones" do
      assert Availability.tailwind_classes(:cancelled) =~ "ink"
    end
  end
end
