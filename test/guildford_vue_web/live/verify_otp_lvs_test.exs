defmodule GuildfordVueWeb.VerifyOtpLvsTest do
  @moduledoc """
  Sprint 11.5 Slice 7 — direct LV-mount tests for the three
  verify-OTP forms. The candidate end-to-end flow is covered by
  `mfa_login_integration_test.exs`; this file pins the
  pending-stash + render behaviour for the admin + exam-centre
  variants (which mirror the candidate one) without needing the
  full POST→LV round-trip.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defp seed_pending(conn, scope) do
    challenge_id = Ecto.UUID.generate()
    subject_id = Ecto.UUID.generate()

    init_test_session(conn, %{
      pending_mfa_scope: Atom.to_string(scope),
      pending_mfa_challenge_id: challenge_id,
      pending_mfa_subject_id: subject_id
    })
  end

  describe "/candidate/verify-otp" do
    test "renders the 6-digit form when a pending stash exists", %{conn: conn} do
      conn = seed_pending(conn, :candidate)
      {:ok, _lv, html} = live(conn, ~p"/candidate/verify-otp")

      assert html =~ "Enter your sign-in code"
      assert html =~ "candidate-verify-otp-form"
      assert html =~ ~s(action="/candidate/verify-otp")
      assert html =~ ~s(autocomplete="one-time-code")
    end

    test "no stash → bounces to /candidate/login", %{conn: conn} do
      conn = init_test_session(conn, %{})
      result = live(conn, ~p"/candidate/verify-otp")
      assert {:error, {:redirect, %{to: to}}} = result
      assert to =~ "/candidate/login"
    end
  end

  describe "/backoffice/verify-otp" do
    test "renders the form for an admin pending stash", %{conn: conn} do
      conn = seed_pending(conn, :admin)
      {:ok, _lv, html} = live(conn, ~p"/backoffice/verify-otp")

      assert html =~ "Enter your sign-in code"
      assert html =~ "admin-verify-otp-form"
      assert html =~ ~s(action="/backoffice/verify-otp")
    end

    test "no stash → bounces to /backoffice/login", %{conn: conn} do
      conn = init_test_session(conn, %{})
      result = live(conn, ~p"/backoffice/verify-otp")
      assert {:error, {:redirect, %{to: to}}} = result
      assert to =~ "/backoffice/login"
    end

    test "candidate-scope stash on the admin verify-otp route → bounces (cross-scope guard)",
         %{conn: conn} do
      conn = seed_pending(conn, :candidate)
      result = live(conn, ~p"/backoffice/verify-otp")
      assert {:error, {:redirect, %{to: to}}} = result
      assert to =~ "/backoffice/login"
    end
  end

  describe "/examcenter/verify-otp" do
    test "renders the form for an exam-centre pending stash", %{conn: conn} do
      conn = seed_pending(conn, :exam_centre)
      {:ok, _lv, html} = live(conn, ~p"/examcenter/verify-otp")

      assert html =~ "Enter your sign-in code"
      assert html =~ "exam-centre-verify-otp-form"
      assert html =~ ~s(action="/examcenter/verify-otp")
    end

    test "no stash → bounces to /examcenter/login", %{conn: conn} do
      conn = init_test_session(conn, %{})
      result = live(conn, ~p"/examcenter/verify-otp")
      assert {:error, {:redirect, %{to: to}}} = result
      assert to =~ "/examcenter/login"
    end
  end

  describe "POST /<scope>/verify-otp — no stash" do
    test "candidate verify-otp POST without stash bounces", %{conn: conn} do
      conn = init_test_session(conn, %{})
      conn = post(conn, ~p"/candidate/verify-otp", %{"verify" => %{"code" => "123456"}})
      assert redirected_to(conn) =~ "/candidate/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end

    test "admin verify-otp POST without stash bounces", %{conn: conn} do
      conn = init_test_session(conn, %{})
      conn = post(conn, ~p"/backoffice/verify-otp", %{"verify" => %{"code" => "123456"}})
      assert redirected_to(conn) =~ "/backoffice/login"
    end

    test "exam-centre verify-otp POST without stash bounces", %{conn: conn} do
      conn = init_test_session(conn, %{})
      conn = post(conn, ~p"/examcenter/verify-otp", %{"verify" => %{"code" => "123456"}})
      assert redirected_to(conn) =~ "/examcenter/login"
    end
  end
end
