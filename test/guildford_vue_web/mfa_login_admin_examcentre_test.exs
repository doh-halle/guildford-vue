defmodule GuildfordVueWeb.MfaLoginAdminExamCentreTest do
  @moduledoc """
  Sprint 11.5 Slice 7 — end-to-end MFA flow for the admin + exam-
  centre scopes. Mirrors the candidate suite in
  `mfa_login_integration_test.exs`; lifted into its own file so
  the cross-scope coverage of `<scope>_session_controller.ex` +
  the `<scope>_notifier.deliver_otp_email/2` paths is explicit.
  """
  use GuildfordVueWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias GuildfordVue.{Admins, ExamCentres}

  setup do
    previous = Application.get_env(:guildford_vue, :mfa_via_email_enabled)
    Application.put_env(:guildford_vue, :mfa_via_email_enabled, true)
    on_exit(fn -> Application.put_env(:guildford_vue, :mfa_via_email_enabled, previous) end)
    :ok
  end

  # Test-only fixture password.
  # secrets:allow test-only fixture
  @fixture_password "supersecret123!A"

  describe "admin scope" do
    setup do
      {:ok, admin} =
        Admins.register_admin(%{
          "email" => "mfa-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => @fixture_password,
          "name" => "MFA Admin",
          "role" => "superadmin"
        })

      %{admin: admin}
    end

    test "MFA-on login → 302 verify-otp + emailed code", %{conn: conn, admin: a} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => @fixture_password}
        })

      assert redirected_to(conn) =~ "/backoffice/verify-otp"
      refute get_session(conn, :admin_token)
      assert get_session(conn, :pending_mfa_subject_id) == a.id

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_n, addr} -> addr == a.email end) and
          email.subject =~ "sign-in code" and
          email.text_body =~ ~r/\b\d{6}\b/
      end)
    end

    test "correct OTP completes login", %{conn: conn, admin: a} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => @fixture_password}
        })

      assert_email_sent(fn email ->
        [_, code | _] = Regex.run(~r/(\d{6})/, email.text_body)

        conn2 =
          recycle(conn)
          |> post(~p"/backoffice/verify-otp", %{"verify" => %{"code" => code}})

        assert redirected_to(conn2) =~ "/backoffice/dashboard"
        assert get_session(conn2, :admin_token)
        refute get_session(conn2, :pending_mfa_challenge_id)
        true
      end)
    end

    test "wrong OTP code keeps the verify form open", %{conn: conn, admin: a} do
      conn =
        post(conn, ~p"/backoffice/login", %{
          "admin" => %{"email" => a.email, "password" => @fixture_password}
        })

      conn2 =
        recycle(conn)
        |> post(~p"/backoffice/verify-otp", %{"verify" => %{"code" => "000000"}})

      assert redirected_to(conn2) =~ "/backoffice/verify-otp"
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "didn't match"
    end
  end

  describe "exam-centre scope" do
    setup do
      {:ok, admin} =
        Admins.register_admin(%{
          "email" => "mfa-c-approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => @fixture_password,
          "name" => "Approver",
          "role" => "superadmin"
        })

      {:ok, centre} =
        ExamCentres.register_exam_centre(%{
          "email" => "mfa-centre-#{System.unique_integer([:positive])}@example.com",
          "password" => @fixture_password,
          "name" => "MFA Centre",
          "address_line_1" => "1 St",
          "city" => "Cardiff",
          "postcode" => "CF1 1AA"
        })

      {:ok, approved} = ExamCentres.approve(centre, admin)
      # Drain the approval email so subsequent assert_email_sent
      # blocks see only the OTP email.
      _ = Process.info(self(), :messages)
      receive_drain()
      %{centre: approved}
    end

    defp receive_drain do
      receive do
        _ -> receive_drain()
      after
        10 -> :ok
      end
    end

    test "MFA-on login → 302 verify-otp + emailed code", %{conn: conn, centre: c} do
      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => @fixture_password}
        })

      assert redirected_to(conn) =~ "/examcenter/verify-otp"
      refute get_session(conn, :exam_centre_token)
      assert get_session(conn, :pending_mfa_subject_id) == c.id

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_n, addr} -> addr == c.email end) and
          email.subject =~ "sign-in code" and
          email.text_body =~ ~r/\b\d{6}\b/
      end)
    end

    test "correct OTP completes login", %{conn: conn, centre: c} do
      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => @fixture_password}
        })

      assert_email_sent(fn email ->
        [_, code | _] = Regex.run(~r/(\d{6})/, email.text_body)

        conn2 =
          recycle(conn)
          |> post(~p"/examcenter/verify-otp", %{"verify" => %{"code" => code}})

        assert redirected_to(conn2) =~ "/examcenter/dashboard"
        assert get_session(conn2, :exam_centre_token)
        true
      end)
    end

    test "5 wrong codes locks + redirects to login", %{conn: conn, centre: c} do
      conn =
        post(conn, ~p"/examcenter/login", %{
          "exam_centre" => %{"email" => c.email, "password" => @fixture_password}
        })

      final =
        Enum.reduce(1..5, conn, fn _, acc ->
          recycle(acc)
          |> post(~p"/examcenter/verify-otp", %{"verify" => %{"code" => "000000"}})
        end)

      assert redirected_to(final) =~ "/examcenter/login"
      refute get_session(final, :pending_mfa_challenge_id)
    end
  end
end
