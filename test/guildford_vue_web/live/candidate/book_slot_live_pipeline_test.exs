defmodule GuildfordVueWeb.Candidate.BookSlotLivePipelineTest do
  @moduledoc """
  Sprint 7 Slice 4 — BookSlotLive's Confirm button → pipeline.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bk-pl-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bk-pl-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Pipeline LV Centre",
        "address_line_1" => "1 St",
        "city" => "London",
        "postcode" => "SW1A 1AA"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "BookLV Exam",
          "code" => "BLV",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 3_000
        },
        admin
      )

    {:ok, _} = ExamCentres.set_offerings(centre, [exam.id], centre)

    future = DateTime.utc_now() |> DateTime.add(7, :day)

    {:ok, slot} =
      Slots.create_slot(centre, %{
        "exam_id" => exam.id,
        "starts_at" => future,
        "ends_at" => DateTime.add(future, 60 * 60, :second),
        "capacity" => 3
      })

    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "bk-pl-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "BookLV",
        "last_name" => "Cand"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)

    on_exit(fn ->
      _ = Centres.stop_centre(centre.id)

      Application.put_env(
        :guildford_vue,
        :payment_gateway,
        GuildfordVue.PaymentGateway.Stub
      )
    end)

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    %{conn: conn, centre: centre, exam: exam, slot: slot, candidate: candidate}
  end

  # Sprint 8 Slice 4 inserted the :payment state between :pending
  # and :confirmed. These tests traverse the new path via PayPal
  # (wallet method, no card form).
  defp click_continue_then_paypal_and_pay(lv) do
    _ = lv |> element("[data-test-id='continue-to-payment']") |> render_click()
    _ = lv |> element("[data-test-id='method-paypal']") |> render_click()
    lv |> element("[data-test-id='pay-button']") |> render_click()
  end

  test "Pay (PayPal) creates a booking and shows the success state",
       %{conn: conn, slot: slot, candidate: c} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    html = click_continue_then_paypal_and_pay(lv)

    [booking] = Bookings.list_candidate_bookings(c)
    assert booking.status == "confirmed"
    assert booking.candidate_id == c.id

    assert html =~ booking.reference
    assert html =~ "Booking confirmed"
    # Sprint 9 Slice 2 changed pdf_url to point at the
    # ReceiptController endpoint, replacing the Sprint 7 stub URL.
    assert html =~ "/candidate/bookings/#{booking.reference}/receipt.pdf"
  end

  test "Decline → stays on payment page with stage-aware error",
       %{conn: conn, slot: slot, candidate: c} do
    Application.put_env(
      :guildford_vue,
      :payment_gateway,
      GuildfordVue.PaymentGateway.Decline
    )

    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")
    html = click_continue_then_paypal_and_pay(lv)

    assert html =~ "declined" or html =~ "Declined"
    assert Bookings.list_candidate_bookings(c) == []
  end

  test "sold-out slot → flash about sold-out, no booking",
       %{conn: conn, slot: slot, candidate: c} do
    {:ok, pid} = Centres.ensure_started(slot.exam_centre_id)
    for _ <- 1..slot.capacity, do: {:ok, _} = Centres.reserve_slot(pid, slot.id)

    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")
    html = click_continue_then_paypal_and_pay(lv)

    assert html =~ "sold out" or html =~ "Sold out"
    assert Bookings.list_candidate_bookings(c) == []
  end
end
