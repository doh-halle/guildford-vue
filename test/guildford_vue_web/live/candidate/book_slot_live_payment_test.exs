defmodule GuildfordVueWeb.Candidate.BookSlotLivePaymentTest do
  @moduledoc """
  Sprint 8 Slice 4 — payment selection + card form state in
  BookSlotLive. The booking pipeline still uses the Stub adapter
  here; Slice 5 swaps it for the Simulated adapter and persists
  the Payment row.

  State machine:
    :pending → click "Continue to payment" → :payment
    :payment (method picker + card form for card methods)
       → click "Pay" → pipeline → :confirmed | :payment (with flash)
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, Bookings, Candidates, Centres, ExamCentres, Exams, Slots}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "bk-pay-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "X",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "bk-pay-centre@example.com",
        "password" => "supersecret123!A",
        "name" => "Pay LV Centre",
        "address_line_1" => "1 St",
        "city" => "Cardiff",
        "postcode" => "CF10 1EP"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, exam} =
      Exams.create_exam(
        %{
          "name" => "PayLV Exam",
          "code" => "PLV",
          "certification_body" => "X",
          "duration_minutes" => 60,
          "price_pence" => 3500
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
        "email" => "bk-pay-cand@example.com",
        "password" => "supersecret123!A",
        "first_name" => "PayLV",
        "last_name" => "C"
      })

    {:ok, _pid} = Centres.start_centre(centre.id)

    on_exit(fn -> _ = Centres.stop_centre(centre.id) end)

    conn =
      init_test_session(conn, %{candidate_token: Candidates.generate_session_token(candidate)})

    %{conn: conn, centre: centre, exam: exam, slot: slot, candidate: candidate}
  end

  test "Continue to payment → state = :payment + renders method picker",
       %{conn: conn, slot: slot} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    html =
      lv
      |> element("[data-test-id='continue-to-payment']")
      |> render_click()

    assert html =~ "Payment method"

    for label <- ~w(Visa Mastercard Amex PayPal) do
      assert html =~ label
    end
  end

  test "selecting Visa shows the card details form",
       %{conn: conn, slot: slot} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    _ = lv |> element("[data-test-id='continue-to-payment']") |> render_click()

    html =
      lv
      |> element("[data-test-id='method-visa']")
      |> render_click()

    assert html =~ "Card number"
    assert html =~ "Cardholder name"
    assert html =~ "Expiry"
    assert html =~ "CVC"
  end

  test "wallet method (PayPal) skips card form and shows Pay button directly",
       %{conn: conn, slot: slot} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    _ = lv |> element("[data-test-id='continue-to-payment']") |> render_click()

    html =
      lv
      |> element("[data-test-id='method-paypal']")
      |> render_click()

    refute html =~ "Card number"
    assert html =~ "Pay" or html =~ "pay"
  end

  test "Pay (PayPal wallet) → pipeline runs → :confirmed",
       %{conn: conn, slot: slot, candidate: c} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    _ = lv |> element("[data-test-id='continue-to-payment']") |> render_click()
    _ = lv |> element("[data-test-id='method-paypal']") |> render_click()

    html =
      lv
      |> element("[data-test-id='pay-button']")
      |> render_click()

    assert [b] = Bookings.list_candidate_bookings(c)
    assert html =~ b.reference
    assert html =~ "Booking confirmed"
  end

  test "Pay (Visa) with valid card → :confirmed",
       %{conn: conn, slot: slot, candidate: c} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    _ = lv |> element("[data-test-id='continue-to-payment']") |> render_click()
    _ = lv |> element("[data-test-id='method-visa']") |> render_click()

    html =
      lv
      |> form("#card-form",
        card: %{
          "number" => "4242 4242 4242 4242",
          "exp_month" => "12",
          "exp_year" => "2030",
          "cvc" => "123",
          "holder_name" => "Pay LV Candidate"
        }
      )
      |> render_submit()

    assert [b] = Bookings.list_candidate_bookings(c)
    assert html =~ b.reference
  end

  test "Pay (Visa) with invalid card → stays on :payment with error",
       %{conn: conn, slot: slot, candidate: c} do
    {:ok, lv, _} = live(conn, ~p"/book/#{slot.id}")

    _ = lv |> element("[data-test-id='continue-to-payment']") |> render_click()
    _ = lv |> element("[data-test-id='method-visa']") |> render_click()

    html =
      lv
      |> form("#card-form",
        card: %{
          "number" => "4242424242424243",
          "exp_month" => "12",
          "exp_year" => "2030",
          "cvc" => "123",
          "holder_name" => "Pay LV Candidate"
        }
      )
      |> render_submit()

    # Stays on the payment form; no booking persisted.
    assert html =~ "Card number" or html =~ "card number"
    assert html =~ "invalid" or html =~ "Invalid"
    assert Bookings.list_candidate_bookings(c) == []
  end
end
