defmodule GuildfordVueWeb.AuthAbsoluteTimeoutTest do
  @moduledoc """
  Sprint 11.5 Slice 3 — every auth scope enforces a 12 hour
  absolute session cap on top of the existing 30 min idle
  timeout. Faking the issued-at stamp to 13 h ago forces
  re-authentication on the next request.
  """
  use GuildfordVueWeb.ConnCase, async: true

  alias GuildfordVue.{Admins, Candidates, ExamCentres}
  alias GuildfordVue.Candidates.Candidate
  alias GuildfordVueWeb.Admin.AdminAuth
  alias GuildfordVueWeb.Candidate.CandidateAuth
  alias GuildfordVueWeb.ExamCentre.ExamCentreAuth

  defp register_verified_candidate do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => "tmo-cand-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "first_name" => "T",
        "last_name" => "X"
      })

    {:ok, verified} =
      candidate
      |> Candidate.confirm_email_changeset(DateTime.utc_now())
      |> GuildfordVue.Repo.update()

    verified
  end

  defp register_admin do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "tmo-admin-#{System.unique_integer([:positive])}@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Admin",
        "role" => "superadmin"
      })

    admin
  end

  defp register_approved_centre do
    admin = register_admin()

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "tmo-centre-#{System.unique_integer([:positive])}@example.com",
        "password" => "supersecret123!A",
        "name" => "Centre",
        "address_line_1" => "1 St",
        "city" => "Bath",
        "postcode" => "BA1 1LT"
      })

    {:ok, approved} = ExamCentres.approve(centre, admin)
    approved
  end

  defp thirteen_hours_ago, do: System.system_time(:second) - 13 * 60 * 60

  describe "candidate session" do
    test "fresh issued-at → request authenticated", %{conn: conn} do
      candidate = register_verified_candidate()

      conn =
        conn
        |> init_test_session(%{
          candidate_token: Candidates.generate_session_token(candidate),
          candidate_last_activity_at: System.system_time(:second),
          candidate_session_issued_at: System.system_time(:second)
        })
        |> CandidateAuth.fetch_current_candidate([])

      assert conn.assigns.current_candidate.id == candidate.id
    end

    test "issued-at > 12 h ago → re-auth required (current_candidate nil)", %{conn: conn} do
      candidate = register_verified_candidate()

      conn =
        conn
        |> init_test_session(%{
          candidate_token: Candidates.generate_session_token(candidate),
          candidate_last_activity_at: System.system_time(:second),
          candidate_session_issued_at: thirteen_hours_ago()
        })
        |> CandidateAuth.fetch_current_candidate([])

      refute conn.assigns.current_candidate
    end
  end

  describe "admin session" do
    test "issued-at > 12 h ago → re-auth required", %{conn: conn} do
      admin = register_admin()

      conn =
        conn
        |> init_test_session(%{
          admin_token: Admins.generate_session_token(admin),
          admin_last_activity_at: System.system_time(:second),
          admin_session_issued_at: thirteen_hours_ago()
        })
        |> AdminAuth.fetch_current_admin([])

      refute conn.assigns.current_admin
    end
  end

  describe "exam-centre session" do
    test "issued-at > 12 h ago → re-auth required", %{conn: conn} do
      centre = register_approved_centre()

      conn =
        conn
        |> init_test_session(%{
          exam_centre_token: ExamCentres.generate_session_token(centre),
          exam_centre_last_activity_at: System.system_time(:second),
          exam_centre_session_issued_at: thirteen_hours_ago()
        })
        |> ExamCentreAuth.fetch_current_exam_centre([])

      refute conn.assigns.current_exam_centre
    end
  end
end
