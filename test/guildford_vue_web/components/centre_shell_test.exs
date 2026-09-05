defmodule GuildfordVueWeb.CentreShellTest do
  @moduledoc """
  Sprint 3 Slice 3 — centre-side sidebar shell. Mirror of admin_shell
  but for `/examcenter/*` LiveViews. Nav items: Dashboard, Profile,
  Exams I offer, Slots (Sprint 4).
  """
  use GuildfordVueWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias GuildfordVueWeb.Layouts

  defp centre do
    %GuildfordVue.ExamCentres.ExamCentre{
      id: Ecto.UUID.generate(),
      email: "centre@example.com",
      name: "Test Centre",
      status: "approved"
    }
  end

  test "renders a sidebar nav with the canonical centre sections" do
    html =
      render_component(&Layouts.centre_shell/1,
        current_exam_centre: centre(),
        active: :dashboard,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ "Dashboard"
    assert html =~ "Profile"
    assert html =~ "Exams I offer"
    assert html =~ "Slots"
  end

  test "marks the active nav item with aria-current=page" do
    html =
      render_component(&Layouts.centre_shell/1,
        current_exam_centre: centre(),
        active: :profile,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ ~r/aria-current="page"[^>]*>\s*Profile/
    refute html =~ ~r/aria-current="page"[^>]*>\s*Dashboard/
  end

  test "uses /examcenter/* paths" do
    html =
      render_component(&Layouts.centre_shell/1,
        current_exam_centre: centre(),
        active: :dashboard,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ "/examcenter/dashboard"
    assert html =~ "/examcenter/profile"
    assert html =~ "/examcenter/exams"
    assert html =~ "/examcenter/slots"
  end

  test "renders inner_block content" do
    html =
      render_component(&Layouts.centre_shell/1,
        current_exam_centre: centre(),
        active: :dashboard,
        inner_block: %{
          __slot__: :inner_block,
          inner_block: fn _, _ ->
            Phoenix.HTML.raw("<p>centre-content-MARK</p>")
          end
        }
      )

    assert html =~ "centre-content-MARK"
  end

  test "shows centre name + email in the sidebar header" do
    html =
      render_component(&Layouts.centre_shell/1,
        current_exam_centre: centre(),
        active: :dashboard,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ "Test Centre"
    assert html =~ "centre@example.com"
  end
end
