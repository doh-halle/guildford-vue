defmodule GuildfordVueWeb.AdminShellTest do
  @moduledoc """
  Tests for the admin sidebar shell — the layout wrapper used by every
  authenticated admin page. Sprint 2 Slice 2 introduces it ahead of
  the centre-approval queue (Slice 3) and the admin pages that follow.

  Rendered directly via render_component/2 — we don't need a full LV
  mount cycle, just the markup contract.
  """
  use GuildfordVueWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GuildfordVueWeb.Layouts

  defp admin(role \\ "superadmin") do
    %GuildfordVue.Admins.Admin{
      id: Ecto.UUID.generate(),
      email: "admin@example.com",
      name: "An Admin",
      role: role
    }
  end

  test "renders a sidebar nav with the canonical admin sections" do
    html =
      render_component(&Layouts.admin_shell/1,
        current_admin: admin(),
        active: :dashboard,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ "Dashboard"
    assert html =~ "Centres"
    assert html =~ "Candidates"
    assert html =~ "Admins"
    assert html =~ "Audit log"
  end

  test "marks the active nav item with aria-current=page" do
    html =
      render_component(&Layouts.admin_shell/1,
        current_admin: admin(),
        active: :centres,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    # Match the aria-current attribute next to the active link.
    # Centres is the active one; Dashboard, Candidates, etc must not be marked.
    assert html =~ ~r/aria-current="page"[^>]*>\s*Centres/
    refute html =~ ~r/aria-current="page"[^>]*>\s*Dashboard/
    refute html =~ ~r/aria-current="page"[^>]*>\s*Candidates/
  end

  test "links use ~p paths under /backoffice" do
    html =
      render_component(&Layouts.admin_shell/1,
        current_admin: admin(),
        active: :dashboard,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ "/backoffice/dashboard"
    assert html =~ "/backoffice/centres"
    assert html =~ "/backoffice/candidates"
    assert html =~ "/backoffice/admins"
    assert html =~ "/backoffice/audit-log"
  end

  test "renders the inner_block content" do
    html =
      render_component(&Layouts.admin_shell/1,
        current_admin: admin(),
        active: :dashboard,
        inner_block: %{
          __slot__: :inner_block,
          inner_block: fn _, _ ->
            Phoenix.HTML.raw("<p class=\"my-page-content\">my-page-content-XYZ</p>")
          end
        }
      )

    assert html =~ "my-page-content-XYZ"
  end

  test "shows the admin's name + role in the sidebar header" do
    html =
      render_component(&Layouts.admin_shell/1,
        current_admin: admin("operator"),
        active: :dashboard,
        inner_block: %{__slot__: :inner_block, inner_block: fn _, _ -> "" end}
      )

    assert html =~ "An Admin"
    assert html =~ "operator"
  end
end
