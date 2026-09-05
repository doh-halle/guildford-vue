defmodule GuildfordVue.ExamCentresProximityTest do
  @moduledoc """
  Sprint 5 Slice 1 — PostGIS proximity query. Returns approved
  centres within `radius_metres` of the given lat/lng, ordered by
  distance.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, ExamCentres}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "prox-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    # Three centres at known UK postcodes.
    {:ok, london} =
      ExamCentres.register_exam_centre(%{
        "email" => "prox-london@example.com",
        "password" => "supersecret123!A",
        "name" => "Prox London",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, london} = ExamCentres.approve(london, admin)

    {:ok, manchester} =
      ExamCentres.register_exam_centre(%{
        "email" => "prox-manchester@example.com",
        "password" => "supersecret123!A",
        "name" => "Prox Manchester",
        "address_line_1" => "1 St",
        "city" => "Manchester",
        "postcode" => "M1 1AE"
      })

    {:ok, manchester} = ExamCentres.approve(manchester, admin)

    {:ok, guildford} =
      ExamCentres.register_exam_centre(%{
        "email" => "prox-guildford@example.com",
        "password" => "supersecret123!A",
        "name" => "Prox Guildford",
        "address_line_1" => "1 St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, guildford} = ExamCentres.approve(guildford, admin)

    %{
      admin: admin,
      london: london,
      manchester: manchester,
      guildford: guildford
    }
  end

  describe "find_within_radius/3" do
    test "30-mile radius of central London returns London + Guildford, not Manchester",
         %{london: l, guildford: g, manchester: m} do
      # London ≈ 51.5014, -0.1419. 30 miles ≈ 48280m.
      results = ExamCentres.find_within_radius(51.5014, -0.1419, 48_280)
      ids = Enum.map(results, & &1.id)

      assert l.id in ids
      assert g.id in ids, "Guildford (~25 miles) should be within 30 miles"
      refute m.id in ids, "Manchester is too far for 30 miles"
    end

    test "200-mile radius returns all three centres", %{
      london: l,
      manchester: m,
      guildford: g
    } do
      # 200 miles ≈ 321869m
      results = ExamCentres.find_within_radius(51.5014, -0.1419, 321_869)
      ids = Enum.map(results, & &1.id)

      assert l.id in ids
      assert m.id in ids
      assert g.id in ids
    end

    test "10-mile radius around London returns only London", %{london: l, guildford: g} do
      # 10 miles ≈ 16093m
      results = ExamCentres.find_within_radius(51.5014, -0.1419, 16_093)
      ids = Enum.map(results, & &1.id)

      assert l.id in ids
      refute g.id in ids
    end

    test "results are ordered nearest-first",
         %{london: l, guildford: g} do
      # From London's coords, London should be first, then Guildford.
      results = ExamCentres.find_within_radius(51.5014, -0.1419, 100_000)
      ids = Enum.map(results, & &1.id)

      london_idx = Enum.find_index(ids, &(&1 == l.id))
      guildford_idx = Enum.find_index(ids, &(&1 == g.id))

      assert london_idx < guildford_idx
    end

    test "excludes non-approved (pending/suspended/rejected) centres",
         %{admin: admin} do
      {:ok, pending} =
        ExamCentres.register_exam_centre(%{
          "email" => "prox-pending@example.com",
          "password" => "supersecret123!A",
          "name" => "Pending One",
          "address_line_1" => "1 St",
          "city" => "London",
          "postcode" => "EC1A 1BB"
        })

      results = ExamCentres.find_within_radius(51.5014, -0.1419, 100_000)
      ids = Enum.map(results, & &1.id)
      refute pending.id in ids

      # If we approve it, it shows up.
      {:ok, approved} = ExamCentres.approve(pending, admin)

      assert approved.id in (ExamCentres.find_within_radius(51.5014, -0.1419, 100_000)
                             |> Enum.map(& &1.id))
    end

    test "returns empty list when nothing within radius" do
      # Middle of the Atlantic.
      assert [] = ExamCentres.find_within_radius(45.0, -30.0, 1_000)
    end
  end
end
