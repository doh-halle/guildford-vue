defmodule GuildfordVue.CentreSearchTest do
  @moduledoc """
  Sprint 5 Slice 3 — CentreSearch context. Postcode + radius + exam
  + date range → centres with their matching available slots,
  ordered nearest-first.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, CentreSearch, ExamCentres, Exams, Slots}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "search-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, london} =
      ExamCentres.register_exam_centre(%{
        "email" => "search-london@example.com",
        "password" => "supersecret123!A",
        "name" => "Search London",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, london} = ExamCentres.approve(london, admin)

    {:ok, guildford} =
      ExamCentres.register_exam_centre(%{
        "email" => "search-guildford@example.com",
        "password" => "supersecret123!A",
        "name" => "Search Guildford",
        "address_line_1" => "1 St",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ"
      })

    {:ok, guildford} = ExamCentres.approve(guildford, admin)

    {:ok, ccna} =
      Exams.create_exam(
        %{
          "name" => "CCNA",
          "code" => "CCNA",
          "certification_body" => "Cisco",
          "duration_minutes" => 120,
          "price_pence" => 24_000
        },
        admin
      )

    {:ok, az104} =
      Exams.create_exam(
        %{
          "name" => "Azure Administrator",
          "code" => "AZ-104",
          "certification_body" => "Microsoft",
          "duration_minutes" => 120,
          "price_pence" => 13_500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(london, [ccna.id, az104.id], london)
    {:ok, _} = ExamCentres.set_offerings(guildford, [ccna.id], guildford)

    next_week = DateTime.utc_now() |> DateTime.add(7, :day)
    next_month = DateTime.utc_now() |> DateTime.add(30, :day)

    {:ok, london_ccna_next_week} = create_slot(london, ccna, next_week)
    {:ok, london_az104_next_week} = create_slot(london, az104, next_week)
    {:ok, london_ccna_next_month} = create_slot(london, ccna, next_month)
    {:ok, guildford_ccna_next_week} = create_slot(guildford, ccna, next_week)

    %{
      london: london,
      guildford: guildford,
      ccna: ccna,
      az104: az104,
      london_ccna_next_week: london_ccna_next_week,
      london_az104_next_week: london_az104_next_week,
      london_ccna_next_month: london_ccna_next_month,
      guildford_ccna_next_week: guildford_ccna_next_week
    }
  end

  defp create_slot(centre, exam, starts_at) do
    Slots.create_slot(centre, %{
      "exam_id" => exam.id,
      "starts_at" => starts_at,
      "ends_at" => DateTime.add(starts_at, 60 * 60, :second),
      "capacity" => 8
    })
  end

  describe "search/1" do
    test "London postcode + 50mi default → London + Guildford ordered nearest-first",
         %{london: l, guildford: g} do
      {:ok, results} = CentreSearch.search(%{postcode: "SW1A 1AA"})
      ids = Enum.map(results, & &1.centre.id)
      assert l.id in ids
      assert g.id in ids

      assert Enum.find_index(ids, &(&1 == l.id)) <
               Enum.find_index(ids, &(&1 == g.id))
    end

    test "10-mile radius around London → only London",
         %{london: l, guildford: g} do
      {:ok, results} = CentreSearch.search(%{postcode: "SW1A 1AA", radius_metres: 16_093})
      ids = Enum.map(results, & &1.centre.id)
      assert l.id in ids
      refute g.id in ids
    end

    test "exam filter: AZ-104 → only London (Guildford doesn't offer it)",
         %{london: l, guildford: g, az104: e} do
      {:ok, results} = CentreSearch.search(%{postcode: "SW1A 1AA", exam_id: e.id})
      ids = Enum.map(results, & &1.centre.id)
      assert l.id in ids
      refute g.id in ids
    end

    test "exam filter narrows slot list per centre too",
         %{london: l, ccna: c, london_ccna_next_week: lcnw, london_ccna_next_month: lcnm} do
      {:ok, results} =
        CentreSearch.search(%{postcode: "SW1A 1AA", exam_id: c.id, radius_metres: 16_093})

      assert [result] = results
      assert result.centre.id == l.id
      slot_ids = Enum.map(result.slots, & &1.id) |> Enum.sort()
      assert slot_ids == Enum.sort([lcnw.id, lcnm.id])
    end

    test "date range filter: starts_before next month - 1 → only next-week slots",
         %{london: l, ccna: c, london_ccna_next_week: lcnw, london_ccna_next_month: lcnm} do
      starts_before = DateTime.utc_now() |> DateTime.add(15, :day)

      {:ok, results} =
        CentreSearch.search(%{
          postcode: "SW1A 1AA",
          exam_id: c.id,
          radius_metres: 16_093,
          starts_before: starts_before
        })

      assert [result] = results
      assert result.centre.id == l.id
      slot_ids = Enum.map(result.slots, & &1.id)
      assert lcnw.id in slot_ids
      refute lcnm.id in slot_ids
    end

    test "every result includes a distance_metres value", %{} do
      {:ok, results} = CentreSearch.search(%{postcode: "SW1A 1AA"})
      assert Enum.all?(results, &is_integer(&1.distance_metres))
    end

    test "excludes centres with no matching slots",
         %{london: l, az104: az} do
      # Cancel the only AZ-104 slot, then search for AZ-104 → London has
      # no matching slots so shouldn't appear in results.
      {:ok, _} = Slots.cancel_slot(Enum.at(Slots.list_centre_slots(l), 0), l)

      # Re-cancel the AZ-104 one specifically; the first cancel may have
      # caught the CCNA. Loop until no AZ-104 slot remains for London.
      Enum.each(Slots.list_centre_slots(l), fn s ->
        if s.exam_id == az.id, do: Slots.cancel_slot(s, l)
      end)

      {:ok, results} = CentreSearch.search(%{postcode: "SW1A 1AA", exam_id: az.id})
      ids = Enum.map(results, & &1.centre.id)
      refute l.id in ids
    end

    test "invalid postcode → {:error, :invalid_postcode}" do
      assert {:error, :invalid_postcode} = CentreSearch.search(%{postcode: "not a postcode"})
    end

    test "unknown postcode → {:error, :unknown_postcode}" do
      assert {:error, :unknown_postcode} = CentreSearch.search(%{postcode: "XX99 9XX"})
    end
  end
end
