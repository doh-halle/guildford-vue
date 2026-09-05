defmodule GuildfordVueWeb.ExamCentre.ExamCentreExamsLiveTest do
  @moduledoc """
  Sprint 3 Slice 6 — centre exam offerings LiveView.
  Checkbox list of catalogue exams; submit overwrites offerings.
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVue.{Admins, ExamCentres, Exams}

  setup %{conn: conn} do
    {:ok, admin} =
      Admins.register_admin(%{
        "email" => "offerings-lv-admin@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "A",
        "role" => "superadmin"
      })

    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "offerings-lv@example.com",
        "password" => "supersecret123!A",
        "name" => "Offerings LV",
        "address_line_1" => "1 St",
        "city" => "Sheffield",
        "postcode" => "S1 2HE"
      })

    {:ok, centre} = ExamCentres.approve(centre, admin)

    {:ok, e1} = Exams.create_exam(base("LV1", "Cat Exam 1"), admin)
    {:ok, e2} = Exams.create_exam(base("LV2", "Cat Exam 2"), admin)
    {:ok, e3} = Exams.create_exam(base("LV3", "Cat Exam 3"), admin)

    conn =
      init_test_session(conn, %{exam_centre_token: ExamCentres.generate_session_token(centre)})

    %{conn: conn, centre: centre, e1: e1, e2: e2, e3: e3}
  end

  defp base(code, name) do
    %{
      "name" => name,
      "code" => code,
      "certification_body" => "X",
      "duration_minutes" => 60,
      "price_pence" => 1000
    }
  end

  test "renders every catalogue exam as a labelled checkbox",
       %{conn: conn, e1: e1, e2: e2, e3: e3} do
    {:ok, _lv, html} = live(conn, ~p"/examcenter/exams")
    assert html =~ e1.name
    assert html =~ e2.name
    assert html =~ e3.name
    assert html =~ "Save offerings"
  end

  test "checking exams and submitting persists offerings",
       %{conn: conn, centre: c, e1: e1, e3: e3} do
    {:ok, lv, _} = live(conn, ~p"/examcenter/exams")

    lv
    |> form("#offerings-form", offerings: %{"exam_ids" => [e1.id, e3.id]})
    |> render_submit()

    ids = ExamCentres.list_offerings(c) |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == Enum.sort([e1.id, e3.id])
  end

  test "currently-offered exams render with `checked`",
       %{conn: conn, centre: c, e1: e1} do
    {:ok, _} = ExamCentres.set_offerings(c, [e1.id], c)

    {:ok, _lv, html} = live(conn, ~p"/examcenter/exams")

    # Match: a checkbox with value=e1.id and the `checked` attribute
    assert html =~ ~s(value="#{e1.id}" checked)
  end

  test "submitting with no checkbox params clears offerings",
       %{conn: conn, centre: c, e1: e1} do
    {:ok, _} = ExamCentres.set_offerings(c, [e1.id], c)

    {:ok, lv, _} = live(conn, ~p"/examcenter/exams")

    # When all checkboxes are unchecked, the browser omits the param entirely.
    # We can't model "no param" via Phoenix.LiveViewTest.form/3 (it merges with
    # the rendered form's current checked state), so dispatch the LV event
    # directly with a params shape that matches what the wire would send.
    render_hook(lv, "save", %{"offerings" => %{}})

    assert ExamCentres.list_offerings(c) == []
  end

  test "unauthenticated visit redirects to login" do
    conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: redirect}}} = live(conn, ~p"/examcenter/exams")
    assert redirect =~ "/examcenter/login"
  end
end
