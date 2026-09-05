defmodule GuildfordVueWeb.Admin.AdminCentresLiveTest do
  @moduledoc """
  Sprint 2 Slice 3 — admin centre approval queue. LiveView feature tests:
    - the queue lists every pending centre
    - approve button approves + removes from queue
    - reject button (with reason) rejects + removes from queue
    - approved / rejected centres do not appear in the queue
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias GuildfordVue.{Admins, AuditLog, ExamCentres}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "queue-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Queue Admin"
      })

    {:ok, alpha} =
      ExamCentres.register_exam_centre(%{
        "email" => "alpha@example.com",
        "password" => "supersecret123!A",
        "name" => "Alpha Centre",
        "address_line_1" => "1 Alpha St",
        "city" => "Aberdeen",
        "postcode" => "AB1 1AB",
        "latitude" => 57.1,
        "longitude" => -2.1
      })

    {:ok, bravo} =
      ExamCentres.register_exam_centre(%{
        "email" => "bravo@example.com",
        "password" => "supersecret123!A",
        "name" => "Bravo Centre",
        "address_line_1" => "1 Bravo St",
        "city" => "Bristol",
        "postcode" => "BS1 1BS",
        "latitude" => 51.5,
        "longitude" => -2.6
      })

    token = Admins.generate_session_token(admin)
    conn = init_test_session(conn, %{admin_token: token})
    %{conn: conn, admin: admin, alpha: alpha, bravo: bravo}
  end

  test "the queue lists every pending centre", %{conn: conn, alpha: a, bravo: b} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/centres")
    assert html =~ a.name
    assert html =~ b.name
    assert html =~ a.email
    assert html =~ b.email
  end

  test "Approve button approves the centre and removes it from the queue", %{conn: conn, alpha: a} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/centres")

    html =
      lv
      |> element("[data-test-id='approve-#{a.id}']")
      |> render_click()

    refute html =~ a.email, "approved centre should be removed from the pending queue"

    reloaded = ExamCentres.get_exam_centre!(a.id)
    assert reloaded.status == "approved"

    assert [_] = AuditLog.list(event_type: "centre_approved", aggregate_id: a.id)
    assert_email_sent(to: [{a.name, a.email}])
  end

  test "Reject form rejects the centre with a reason", %{conn: conn, alpha: a} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/centres")

    # Open the reject form for centre A
    html =
      lv
      |> element("[data-test-id='open-reject-#{a.id}']")
      |> render_click()

    assert html =~ "Reason"

    # Submit it
    lv
    |> form("#reject-form-#{a.id}",
      reject: %{"reason" => "Insufficient evidence of accreditation"}
    )
    |> render_submit()

    reloaded = ExamCentres.get_exam_centre!(a.id)
    assert reloaded.status == "rejected"
    assert reloaded.rejection_reason == "Insufficient evidence of accreditation"

    assert [event] = AuditLog.list(event_type: "centre_rejected", aggregate_id: a.id)
    assert event.payload["rejection_reason"] == "Insufficient evidence of accreditation"
    assert_email_sent(to: [{a.name, a.email}])
  end

  test "rejecting with a blank reason shows a validation flash", %{conn: conn, alpha: a} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/centres")

    _ = lv |> element("[data-test-id='open-reject-#{a.id}']") |> render_click()

    html =
      lv
      |> form("#reject-form-#{a.id}", reject: %{"reason" => ""})
      |> render_submit()

    assert html =~ "Reason is required"
    # Still pending
    assert ExamCentres.get_exam_centre!(a.id).status == "pending"
  end

  test "unauthenticated visit redirects to /backoffice/login", %{alpha: _} do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/backoffice/centres")
    assert redirect =~ "/backoffice/login"
  end

  describe "status filter tabs" do
    test "?status=approved lists approved centres, hides pending ones",
         %{conn: conn, admin: admin, alpha: a, bravo: b} do
      {:ok, _approved} = ExamCentres.approve(a, admin)

      {:ok, _lv, html} = live(conn, ~p"/backoffice/centres?status=approved")

      assert html =~ a.name, "approved centre should appear on the approved tab"
      refute html =~ b.email, "still-pending centre should not appear on the approved tab"

      refute html =~ "data-test-id=\"approve-#{a.id}\"",
             "approve button should be hidden on the approved tab"
    end

    test "?status=rejected lists rejected centres",
         %{conn: conn, admin: admin, alpha: a} do
      {:ok, _rejected} = ExamCentres.reject(a, admin, "Test rejection reason")

      {:ok, _lv, html} = live(conn, ~p"/backoffice/centres?status=rejected")

      assert html =~ a.name, "rejected centre should appear on the rejected tab"
      assert html =~ "Test rejection reason", "rejection reason should be visible"
    end

    test "default (no status param) still lists only pending centres",
         %{conn: conn, admin: admin, alpha: a, bravo: b} do
      {:ok, _} = ExamCentres.approve(a, admin)

      {:ok, _lv, html} = live(conn, ~p"/backoffice/centres")

      refute html =~ a.email, "approved centre should not appear on the default (pending) tab"
      assert html =~ b.email, "still-pending centre should appear on the default tab"
    end
  end
end
