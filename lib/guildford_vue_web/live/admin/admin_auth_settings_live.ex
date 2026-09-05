defmodule GuildfordVueWeb.Admin.AdminAuthSettingsLive do
  @moduledoc """
  Sprint 11.5 Slice 8 — superadmin-only toggle for platform-wide
  email-OTP MFA. When ON, every successful password login is
  followed by a 6-digit OTP step (see Slice 7). When OFF, login
  completes immediately after the password check.

  The toggle is held in `Application.env` (`:mfa_via_email_enabled`)
  because `PendingMfa.enabled?/0` reads it on every login. Matches
  the Sprint 8 payment-decline-rate pattern: single-node prod
  (PRD §14), node restart restores the compile-time default
  (`false`) — operators must re-enable post-restart if they wanted
  it persistent.

  Hostile-client guard: server re-validates the boolean from the
  phx-submit payload — only `"true"` and `"false"` are accepted.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.AuditLog

  @env_key :mfa_via_email_enabled

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns.current_admin.role == "superadmin" do
      {:ok,
       socket
       |> assign(:page_title, "Authentication settings")
       |> assign(:mfa_enabled, mfa_enabled?())
       |> assign(:error_msg, nil)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You need the superadmin role for authentication settings.")
       |> push_navigate(to: ~p"/backoffice/dashboard")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("set_mfa", %{"mfa" => %{"enabled" => raw}}, socket) do
    case parse_bool(raw) do
      {:ok, new_value} ->
        old = mfa_enabled?()
        Application.put_env(:guildford_vue, @env_key, new_value)

        {:ok, _} =
          AuditLog.append(:mfa_email_otp_toggled, %{
            actor: %{id: socket.assigns.current_admin.id, type: "admin"},
            payload: %{old: old, new: new_value}
          })

        {:noreply,
         socket
         |> assign(:mfa_enabled, new_value)
         |> assign(:error_msg, nil)
         |> put_flash(:info, flash_for(new_value))}

      :error ->
        {:noreply, assign(socket, :error_msg, "Invalid toggle value — expected true or false.")}
    end
  end

  defp mfa_enabled?, do: Application.get_env(:guildford_vue, @env_key, false) == true

  defp parse_bool("true"), do: {:ok, true}
  defp parse_bool("false"), do: {:ok, false}
  defp parse_bool(_), do: :error

  defp flash_for(true), do: "Email-OTP MFA is now ON for every login."
  defp flash_for(false), do: "Email-OTP MFA is now OFF."

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell
      current_admin={@current_admin}
      active={:auth_settings}
    >
      <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">
        Authentication settings
      </h1>
      <p class="mt-2 text-sm text-ink-500">
        Platform-wide multi-factor authentication. Affects every login flow
        (candidate, admin, exam centre). Currently <strong>{if @mfa_enabled, do: "ON", else: "OFF"}</strong>.
      </p>

      <section class="mt-8 max-w-xl rounded-2xl border border-ink-200 bg-white p-6">
        <h2 class="font-sans text-xl font-bold tracking-tight text-ink-900">
          Email-OTP MFA
        </h2>
        <p class="mt-2 text-sm text-ink-600">
          When ON, every successful password login is followed by a 6-digit
          code emailed to the user. The code expires in 10 minutes and locks
          after 5 wrong attempts. Users whose email isn't yet verified are
          let through without MFA — we can't email them a code we trust.
        </p>

        <.form for={%{}} id="mfa-toggle-form" phx-submit="set_mfa" class="mt-6 space-y-3">
          <label class="flex items-start gap-3 rounded-lg border border-ink-200 px-4 py-3 text-sm hover:bg-ink-50">
            <input
              type="radio"
              name="mfa[enabled]"
              value="true"
              checked={@mfa_enabled}
              data-test-id="mfa-on"
              class="mt-1 size-4 border-ink-300 text-orange-700 focus:ring-orange-500"
            />
            <span class="flex-1">
              <span class="font-semibold text-ink-900">On</span>
              <span class="ml-2 text-ink-500">
                — require an emailed 6-digit code after every login
              </span>
            </span>
          </label>

          <label class="flex items-start gap-3 rounded-lg border border-ink-200 px-4 py-3 text-sm hover:bg-ink-50">
            <input
              type="radio"
              name="mfa[enabled]"
              value="false"
              checked={not @mfa_enabled}
              data-test-id="mfa-off"
              class="mt-1 size-4 border-ink-300 text-orange-700 focus:ring-orange-500"
            />
            <span class="flex-1">
              <span class="font-semibold text-ink-900">Off</span>
              <span class="ml-2 text-ink-500">— password only (default)</span>
            </span>
          </label>

          <%= if @error_msg do %>
            <p class="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              {@error_msg}
            </p>
          <% end %>

          <button
            type="submit"
            data-test-id="apply-mfa"
            class="rounded-lg bg-orange-700 px-4 py-2 text-sm font-semibold text-white hover:bg-orange-600"
          >
            Apply
          </button>
        </.form>
      </section>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end
end
