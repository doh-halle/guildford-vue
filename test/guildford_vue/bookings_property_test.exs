defmodule GuildfordVue.BookingsPropertyTest do
  @moduledoc """
  Sprint 7 Slice 5 — PRD §4.7 property test:
  "cancellation + rebooking restores original state".

  For a slot with capacity C, booking K seats (K ≤ C) then
  cancelling all K must return the slot's available_count to C
  and slot status to "open".

  Plus the dissertation's headline stress test: 200 candidates
  concurrently booking a capacity-1 slot — exactly one succeeds.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "prop-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "prop-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Property Centre",
        "address_line_1" => "1 St",
        "city" => "Liverpool",
        "postcode" => "L1 8JQ"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "Property Exam",
          "code" => "PROP",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 1_000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    %{centre: centre, exam: exam}
  end

  defp make_slot(centre, exam, capacity) do
    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(centre, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => capacity
      })

    {:ok, _pid} = Centres.start_centre(centre.id)
    slot
  end

  defp make_candidate(i) do
    {:ok, c} =
      Candidates.register_candidate(%{
        "email" => "stress-#{i}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "C#{i}",
        "last_name" => "X"
      })

    c
  end

  describe "PROPERTY: book then cancel restores state" do
    test "capacity 5, book 3, cancel 3 → back to 5 available + open",
         %{centre: centre, exam: exam} do
      slot = make_slot(centre, exam, 5)

      bookings =
        for i <- 1..3 do
          c = make_candidate(i)
          {:ok, b} = Bookings.create_booking(c, Slots.get_slot!(slot.id))
          {b, c}
        end

      assert Slots.get_slot!(slot.id).available_count == 2

      for {b, c} <- bookings do
        {:ok, _} = Bookings.cancel_booking(b, c)
      end

      assert Slots.get_slot!(slot.id).available_count == 5
      assert Slots.get_slot!(slot.id).status == "open"
    end

    test "capacity 4, fill it, cancel all → status flips back to open",
         %{centre: centre, exam: exam} do
      slot = make_slot(centre, exam, 4)

      bookings =
        for i <- 100..103 do
          c = make_candidate(i)
          {:ok, b} = Bookings.create_booking(c, Slots.get_slot!(slot.id))
          {b, c}
        end

      assert Slots.get_slot!(slot.id).available_count == 0
      assert Slots.get_slot!(slot.id).status == "full"

      for {b, c} <- bookings do
        {:ok, _} = Bookings.cancel_booking(b, c)
      end

      assert Slots.get_slot!(slot.id).available_count == 4
      assert Slots.get_slot!(slot.id).status == "open"
    end
  end

  describe "STRESS: concurrent booking — exactly one wins per seat" do
    @describetag :stress

    test "200 candidates × capacity-1 slot → exactly 1 succeeds, 199 :sold_out",
         %{centre: centre, exam: exam} do
      slot = make_slot(centre, exam, 1)

      # Pre-create the candidates so the stress phase measures only
      # the booking pipeline, not Argon2 hashing.
      candidates = for i <- 200..399, do: make_candidate(i)

      results =
        candidates
        |> Task.async_stream(
          fn c -> Bookings.create_booking(c, Slots.get_slot!(slot.id)) end,
          max_concurrency: 32,
          ordered: false,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      ok = Enum.count(results, &match?({:ok, _}, &1))
      sold_out = Enum.count(results, &match?({:error, :reserve, :sold_out}, &1))
      other = length(results) - ok - sold_out

      assert ok == 1,
             "exactly 1 booking should succeed, got #{ok} (and #{sold_out} :sold_out, #{other} other)"

      assert sold_out + other == 199

      # DB + in-memory state match.
      reloaded = Slots.get_slot!(slot.id)
      assert reloaded.available_count == 0
      assert reloaded.status == "full"
    end
  end
end
