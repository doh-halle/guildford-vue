defmodule GuildfordVue.CentreMetricsTest do
  @moduledoc """
  Sprint 10 Slice 5 — per-centre performance metrics.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{
    Admins,
    Bookings,
    Candidates,
    CentreMetrics,
    ExamCentres,
    Exams,
    Slots
  }

  setup do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "cm-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "cm-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "CM Centre",
        "address_line_1" => "1 St",
        "city" => "Glasgow",
        "postcode" => "G1 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "CM Exam",
          "code" => "CM-#{System.unique_integer([:positive])}",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 4500
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "cm-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "CM",
        "last_name" => "Cand"
      })

    %{admin: admin, centre: centre, exam: exam, candidate: candidate}
  end

  defp make_slot(ctx, capacity) do
    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(ctx.centre, %{
        "exam_id" => ctx.exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => capacity
      })

    slot
  end

  defp persist(ctx, slot, ref, opts) do
    {:ok, booking} =
      Bookings.persist_booking(%{
        candidate_id: ctx.candidate.id,
        slot_id: slot.id,
        exam_id: ctx.exam.id,
        exam_centre_id: ctx.centre.id,
        reference: ref,
        status: Keyword.get(opts, :status, "confirmed"),
        price_pence: ctx.exam.price_pence,
        paid_at: DateTime.utc_now(),
        payment_token: "tok_stub",
        pdf_url: nil
      })

    booking
  end

  describe "metrics_for/1" do
    test "returns zero metrics for a centre with no slots/bookings", ctx do
      m = CentreMetrics.metrics_for(ctx.centre)
      assert m.bookings_total == 0
      assert m.bookings_confirmed == 0
      assert m.bookings_cancelled == 0
      assert m.bookings_refunded == 0
      assert m.capacity_total == 0
      assert m.fill_rate == 0.0
      assert m.cancellation_rate == 0.0
    end

    test "counts confirmed + cancelled + refunded bookings separately", ctx do
      slot = make_slot(ctx, 10)
      _ = persist(ctx, slot, "GV-2026-CFM2BK", status: "confirmed")
      _ = persist(ctx, slot, "GV-2026-CNCLBK", status: "cancelled")
      _ = persist(ctx, slot, "GV-2026-RFNDBK", status: "refunded")

      m = CentreMetrics.metrics_for(ctx.centre)
      assert m.bookings_total == 3
      assert m.bookings_confirmed == 1
      assert m.bookings_cancelled == 1
      assert m.bookings_refunded == 1
    end

    test "fill_rate = confirmed bookings / total slot capacity, rounded to 4 dp", ctx do
      slot = make_slot(ctx, 4)
      _ = persist(ctx, slot, "GV-2026-FRABCD", status: "confirmed")
      _ = persist(ctx, slot, "GV-2026-FREFGH", status: "confirmed")

      m = CentreMetrics.metrics_for(ctx.centre)
      assert m.capacity_total == 4
      assert m.bookings_confirmed == 2
      assert m.fill_rate == 0.5
    end

    test "cancellation_rate = (cancelled+refunded) / total bookings", ctx do
      slot = make_slot(ctx, 10)
      _ = persist(ctx, slot, "GV-2026-XRABCD", status: "confirmed")
      _ = persist(ctx, slot, "GV-2026-XREFGH", status: "confirmed")
      _ = persist(ctx, slot, "GV-2026-XRJKLM", status: "cancelled")
      _ = persist(ctx, slot, "GV-2026-XRNPQR", status: "refunded")

      m = CentreMetrics.metrics_for(ctx.centre)
      assert m.bookings_total == 4
      assert m.cancellation_rate == 0.5
    end
  end

  describe "list_all/0" do
    test "returns one metrics map per approved centre, sorted by total bookings desc", ctx do
      slot = make_slot(ctx, 5)
      _ = persist(ctx, slot, "GV-2026-LSAXYZ", status: "confirmed")

      {:ok, quiet_centre} =
        ExamCentres.register_exam_centre(%{
          "email" => "cm-quiet-#{System.unique_integer([:positive])}@example.com",
          "password" => "supersecret123!A",
          "name" => "Quiet Centre",
          "address_line_1" => "1 St",
          "city" => "Inverness",
          "postcode" => "IV1 1AA"
        })

      {:ok, _quiet} = ExamCentres.approve(quiet_centre, ctx.admin)

      all = CentreMetrics.list_all()
      assert is_list(all)

      busy_idx = Enum.find_index(all, &(&1.centre_id == ctx.centre.id))
      quiet_idx = Enum.find_index(all, &(&1.centre_id == quiet_centre.id))

      assert busy_idx != nil
      assert quiet_idx != nil
      assert busy_idx < quiet_idx
    end
  end
end
