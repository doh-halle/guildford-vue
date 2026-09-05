defmodule GuildfordVue.CentreSearch.MarkerDataTest do
  @moduledoc """
  Sprint 5 Slice 5 — pure transform from CentreSearch results to
  map marker payloads. Tested directly so the LV can keep its
  render thin.
  """
  use ExUnit.Case, async: true

  alias GuildfordVue.CentreSearch.MarkerData

  defp slot(available, capacity) do
    %GuildfordVue.Slots.Slot{
      id: Ecto.UUID.generate(),
      capacity: capacity,
      available_count: available,
      starts_at: ~U[2026-06-01 10:00:00.000000Z]
    }
  end

  defp centre(lat, lng) do
    %GuildfordVue.ExamCentres.ExamCentre{
      id: Ecto.UUID.generate(),
      name: "C",
      city: "X",
      postcode: "X1 1XX",
      latitude: lat,
      longitude: lng
    }
  end

  defp result(lat, lng, slots) do
    %{
      centre: centre(lat, lng),
      slots: slots,
      distance_metres: 1000
    }
  end

  describe "from_results/1" do
    test "one marker per result with centre's lat/lng" do
      r = result(51.5, -0.1, [slot(5, 10)])
      [marker] = MarkerData.from_results([r])
      assert marker.latitude == 51.5
      assert marker.longitude == -0.1
      assert marker.name == "C"
    end

    test "marker carries total available across slots" do
      r = result(51.5, -0.1, [slot(2, 10), slot(3, 10), slot(0, 10)])
      [marker] = MarkerData.from_results([r])
      assert marker.available_count == 5
      assert marker.slot_count == 3
      assert marker.available_slot_count == 2
      # 3 slots × capacity 10 each → seat_capacity == 30
      assert marker.seat_capacity == 30
    end

    test "marker carries seat_capacity (sum of slot capacities)" do
      # Two fully-sold-out slots with different capacities
      r1 = result(51.5, -0.1, [slot(0, 10), slot(0, 5)])
      [m1] = MarkerData.from_results([r1])
      assert m1.seat_capacity == 15

      # Two slots with remaining seats
      r2 = result(51.6, -0.2, [slot(7, 12), slot(3, 8)])
      [m2] = MarkerData.from_results([r2])
      assert m2.seat_capacity == 20
    end

    test "marker carries the count of slots with seats remaining (available_slot_count)" do
      # All slots full → available_slot_count == 0
      r_full = result(51.5, -0.1, [slot(0, 10), slot(0, 5)])
      [m_full] = MarkerData.from_results([r_full])
      assert m_full.available_slot_count == 0

      # All slots have seats → available_slot_count == length(slots)
      r_all = result(51.6, -0.2, [slot(3, 10), slot(1, 5), slot(7, 10)])
      [m_all] = MarkerData.from_results([r_all])
      assert m_all.available_slot_count == 3

      # Mixed: 4 slots with available=[0, 1, 5, 0] → 2 have seats left
      r_mixed = result(51.7, -0.3, [slot(0, 10), slot(1, 10), slot(5, 10), slot(0, 10)])
      [m_mixed] = MarkerData.from_results([r_mixed])
      assert m_mixed.available_slot_count == 2
    end

    test "skips results whose centre has no coordinates" do
      r_no_geo = result(nil, nil, [slot(5, 10)])
      r_ok = result(51.5, -0.1, [slot(5, 10)])

      assert [marker] = MarkerData.from_results([r_no_geo, r_ok])
      assert marker.latitude == 51.5
    end
  end

  describe "availability_class/1 (indicative marker colour)" do
    test ":green when many seats remain (≥50% of total capacity)" do
      r = result(0.0, 0.0, [slot(10, 10), slot(8, 10)])
      assert MarkerData.availability_class(r) == :green
    end

    test ":amber when some seats remain (1–49% of total capacity)" do
      r = result(0.0, 0.0, [slot(2, 10), slot(1, 10)])
      assert MarkerData.availability_class(r) == :amber
    end

    test ":red when no seats remain (filtered slots would be empty)" do
      r = result(0.0, 0.0, [slot(0, 10)])
      assert MarkerData.availability_class(r) == :red
    end

    test ":red on empty slot list" do
      r = result(0.0, 0.0, [])
      assert MarkerData.availability_class(r) == :red
    end
  end
end
