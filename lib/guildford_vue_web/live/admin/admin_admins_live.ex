defmodule GuildfordVueWeb.Admin.AdminAdminsLive do
  @moduledoc """
  Admin user management — invite new admins, change roles, suspend or
  reactivate. Restricted to superadmins. The role-check is the
  authorization policy point for the whole Admins surface (PRD §4.4
  FR-ADMIN-3).
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.Admins

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns.current_admin.role == "superadmin" do
      {:ok,
       socket
       |> assign(:page_title, "Admins")
       |> assign(:admins, Admins.list_admins())
       |> assign(:invite_form, blank_invite_form())}
    else
      {:ok,
       socket
       |> put_flash(:error, "You need the superadmin role to manage admins.")
       |> push_navigate(to: ~p"/backoffice/dashboard")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event(
        "invite",
        %{"invite" => %{"email" => email, "name" => name, "role" => role}},
        socket
      ) do
    case Admins.invite_admin(
           %{"email" => email, "name" => name, "role" => role},
           socket.assigns.current_admin
         ) do
      {:ok, _admin, _token} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{email}.")
         |> assign(:admins, Admins.list_admins())
         |> assign(:invite_form, blank_invite_form())}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :invite_form, to_form(cs, as: :invite))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Invite failed: #{inspect(reason)}")}
    end
  end

  def handle_event("change_role", %{"id" => id, "role" => %{"role" => new_role}}, socket) do
    admin = Admins.get_admin!(id)

    case Admins.change_role(admin, new_role, socket.assigns.current_admin) do
      {:ok, _} ->
        {:noreply, socket |> assign(:admins, Admins.list_admins())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Role change failed: #{inspect(reason)}")}
    end
  end

  def handle_event("suspend", %{"id" => id}, socket) do
    admin = Admins.get_admin!(id)
    {:ok, _} = Admins.suspend(admin, socket.assigns.current_admin)
    {:noreply, assign(socket, :admins, Admins.list_admins())}
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    admin = Admins.get_admin!(id)
    {:ok, _} = Admins.reactivate(admin, socket.assigns.current_admin)
    {:noreply, assign(socket, :admins, Admins.list_admins())}
  end

  defp blank_invite_form do
    to_form(%{"email" => "", "name" => "", "role" => "operator"}, as: :invite)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:admins}>
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Admins</h1>
      <p class="mt-2 text-sm text-ink-500">
        Invite new admins, change roles, or suspend access.
      </p>

      <section
        aria-labelledby="invite-heading"
        class="mt-8 rounded-2xl border border-ink-200 bg-white p-6"
      >
        <h2 id="invite-heading" class="font-sans text-xl font-bold tracking-tight text-ink-900">
          Invite admin
        </h2>
        <p class="mt-1 text-sm text-ink-500">
          The new admin receives an email with a link to set their password.
        </p>

        <.form
          for={@invite_form}
          id="invite-admin-form"
          phx-submit="invite"
          class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3"
        >
          <input
            type="email"
            name="invite[email]"
            value={@invite_form[:email].value}
            placeholder="email@example.com"
            required
            class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          />
          <input
            type="text"
            name="invite[name]"
            value={@invite_form[:name].value}
            placeholder="Name"
            required
            class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          />
          <select
            name="invite[role]"
            class="rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
          >
            <option value="operator">operator</option>
            <option value="superadmin">superadmin</option>
          </select>

          <button
            type="submit"
            class="col-span-1 rounded-lg bg-orange-700 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-600 sm:col-span-3 sm:w-fit"
          >
            Send invite
          </button>
        </.form>
      </section>

      <section aria-labelledby="admins-heading" class="mt-10">
        <h2 id="admins-heading" class="font-sans text-xl font-bold tracking-tight text-ink-900">
          Existing admins
        </h2>

        <ul class="mt-4 divide-y divide-ink-200 rounded-2xl border border-ink-200 bg-white">
          <%= for a <- @admins do %>
            <li class="flex flex-wrap items-center gap-4 px-6 py-4">
              <div class="min-w-0 flex-1">
                <p class="font-semibold text-ink-900">{a.name}</p>
                <p class="text-sm text-ink-600">{a.email}</p>
                <%= if a.suspended_at do %>
                  <p class="mt-1 inline-block rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700">
                    Suspended
                  </p>
                <% end %>
              </div>

              <.form
                for={%{}}
                id={"role-form-#{a.id}"}
                phx-submit="change_role"
                phx-value-id={a.id}
                class="flex items-center gap-2"
              >
                <select
                  name="role[role]"
                  class="rounded-lg border border-ink-200 bg-white px-2 py-1 text-sm"
                >
                  <option value="operator" selected={a.role == "operator"}>operator</option>
                  <option value="superadmin" selected={a.role == "superadmin"}>
                    superadmin
                  </option>
                </select>
                <button
                  type="submit"
                  class="rounded-lg border border-ink-200 px-3 py-1 text-xs font-semibold text-ink-700 hover:bg-ink-50"
                >
                  Save
                </button>
              </.form>

              <%= if a.suspended_at do %>
                <button
                  type="button"
                  phx-click="reactivate"
                  phx-value-id={a.id}
                  data-test-id={"reactivate-admin-#{a.id}"}
                  class="rounded-lg bg-teal-700 px-3 py-1.5 text-sm font-semibold text-white hover:bg-teal-600"
                >
                  Reactivate
                </button>
              <% else %>
                <%= if a.id != @current_admin.id do %>
                  <button
                    type="button"
                    phx-click="suspend"
                    phx-value-id={a.id}
                    data-test-id={"suspend-admin-#{a.id}"}
                    data-confirm={"Suspend #{a.name}?"}
                    class="rounded-lg border border-red-300 px-3 py-1.5 text-sm font-semibold text-red-700 hover:bg-red-50"
                  >
                    Suspend
                  </button>
                <% end %>
              <% end %>
            </li>
          <% end %>
        </ul>
      </section>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end
end
