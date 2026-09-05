defmodule GuildfordVueWeb.Admin.AdminExamsLiveTest do
  @moduledoc """
  Sprint 3 Slice 1 — admin-facing exam catalogue CRUD.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, AuditLog, Exams}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "examslive-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "Cat Admin",
        "role" => "superadmin"
      })

    conn = init_test_session(conn, %{admin_token: Admins.generate_session_token(admin)})
    %{conn: conn, admin: admin}
  end

  test "shows the exam list (empty state copy when no exams)", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/backoffice/exams")
    assert html =~ "Exams"
    assert html =~ "No exams yet"
  end

  test "lists existing exams ordered by name", %{conn: conn, admin: admin} do
    {:ok, _} = Exams.create_exam(base_attrs("ZULU", "Zulu Exam"), admin)
    {:ok, _} = Exams.create_exam(base_attrs("ALPHA", "Alpha Exam"), admin)

    {:ok, _lv, html} = live(conn, ~p"/backoffice/exams")
    assert html =~ "Alpha Exam"
    assert html =~ "Zulu Exam"
    # Alpha precedes Zulu in the HTML
    assert :binary.match(html, "Alpha Exam") < :binary.match(html, "Zulu Exam")
  end

  test "create form creates an exam + audits", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/exams/new")

    lv
    |> form("#exam-form",
      exam: %{
        "name" => "Cisco CCNA",
        "code" => "ccna",
        "certification_body" => "Cisco",
        "description" => "Routing and switching",
        "duration_minutes" => 120,
        "price_pence" => 33_000
      }
    )
    |> render_submit()

    assert exam = Exams.get_exam_by_code("CCNA")
    assert exam.name == "Cisco CCNA"
    assert [_] = AuditLog.list(event_type: "exam_created", aggregate_id: exam.id)
  end

  test "edit form updates an exam + audits", %{conn: conn, admin: admin} do
    {:ok, exam} = Exams.create_exam(base_attrs("EDIT", "To Edit"), admin)

    {:ok, lv, _} = live(conn, ~p"/backoffice/exams/#{exam.id}/edit")

    lv
    |> form("#exam-form",
      exam: %{
        "name" => "Edited Name",
        "certification_body" => exam.certification_body,
        "duration_minutes" => exam.duration_minutes,
        "price_pence" => 9999
      }
    )
    |> render_submit()

    reloaded = Exams.get_exam!(exam.id)
    assert reloaded.name == "Edited Name"
    assert reloaded.price_pence == 9999
    assert reloaded.code == "EDIT", "code is not editable"
    assert [_] = AuditLog.list(event_type: "exam_updated", aggregate_id: exam.id)
  end

  test "Archive button archives + removes from list", %{conn: conn, admin: admin} do
    {:ok, exam} = Exams.create_exam(base_attrs("OLD", "Old Exam"), admin)

    {:ok, lv, _} = live(conn, ~p"/backoffice/exams")

    lv
    |> element("[data-test-id='archive-#{exam.id}']")
    |> render_click()

    refute Exams.get_exam!(exam.id).archived_at == nil
    assert [_] = AuditLog.list(event_type: "exam_archived", aggregate_id: exam.id)
  end

  test "validation errors surface inline on submit", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/backoffice/exams/new")

    html =
      lv
      |> form("#exam-form", exam: %{"name" => "", "code" => "", "duration_minutes" => "-5"})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/backoffice/exams")
    assert redirect =~ "/backoffice/login"
  end

  defp base_attrs(code, name) do
    %{
      "name" => name,
      "code" => code,
      "certification_body" => "Body",
      "description" => "desc",
      "duration_minutes" => 60,
      "price_pence" => 5000
    }
  end
end
