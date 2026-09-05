defmodule GuildfordVueWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GuildfordVueWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @admin_nav_items [
    {:dashboard, "Dashboard", "/backoffice/dashboard"},
    {:centres, "Centres", "/backoffice/centres"},
    {:candidates, "Candidates", "/backoffice/candidates"},
    {:bookings, "Bookings", "/backoffice/bookings"},
    {:exams, "Exams", "/backoffice/exams"},
    {:admins, "Admins", "/backoffice/admins"},
    {:audit_log, "Audit log", "/backoffice/audit-log"},
    {:payment_settings, "Payments", "/backoffice/payment-settings"},
    {:auth_settings, "Auth", "/backoffice/auth-settings"},
    {:announcements, "Announcements", "/backoffice/announcements"},
    {:system, "System", "/backoffice/system"}
  ]

  @doc """
  Admin shell — left sidebar nav + main content area. Used by every
  authenticated `/backoffice/*` LiveView so the navigation, branding,
  and signed-in identity are consistent.

  ## Why a function component (not a `live_session` layout)

  LiveView layouts can't easily render dynamic per-page state from
  the LiveView itself (e.g. the active nav highlight depends on
  which LV is mounted). A wrapping function component lets each
  page pass its own `active:` atom.

  ## Active highlighting

  Pass `active: :dashboard | :centres | :candidates | :admins | :audit_log`.
  The matching link gets `aria-current="page"` (semantic + styled
  via Tailwind's `aria-[current=page]:` variant).
  """
  attr :current_admin, :map, required: true
  attr :active, :atom, required: true
  slot :inner_block, required: true

  def admin_shell(assigns) do
    assigns = assign(assigns, :nav_items, @admin_nav_items)

    ~H"""
    <div class="flex min-h-screen bg-ink-50">
      <aside
        aria-label="Back-office navigation"
        class="hidden w-64 shrink-0 flex-col gap-1 border-r border-ink-200 bg-white px-4 py-6 md:flex"
      >
        <div class="mb-6 px-2">
          <p class="font-mono text-xs uppercase tracking-widest text-orange-700">Back office</p>
          <p class="mt-2 truncate font-sans text-sm font-semibold text-ink-900">
            {@current_admin.name}
          </p>
          <p class="text-xs text-ink-500">{@current_admin.role}</p>
        </div>

        <nav class="flex flex-col gap-1">
          <%= for {key, label, path} <- @nav_items do %>
            <.link
              navigate={path}
              aria-current={if key == @active, do: "page"}
              class={[
                "block rounded-lg px-3 py-2 text-sm transition",
                "text-ink-700 hover:bg-ink-100",
                "aria-[current=page]:bg-orange-50 aria-[current=page]:font-semibold aria-[current=page]:text-orange-800"
              ]}
            >
              {label}
            </.link>
          <% end %>
        </nav>

        <div class="mt-auto border-t border-ink-200 pt-4">
          <.link
            href="/backoffice/settings"
            class="block rounded-lg px-3 py-2 text-sm text-ink-700 hover:bg-ink-100"
          >
            Settings
          </.link>
          <.link
            href="/backoffice/logout"
            method="delete"
            class="block rounded-lg px-3 py-2 text-sm text-ink-700 hover:bg-ink-100"
          >
            Log out
          </.link>
        </div>
      </aside>

      <main class="flex-1 px-6 py-10 sm:px-10">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @centre_nav_items [
    {:dashboard, "Dashboard", "/examcenter/dashboard"},
    {:profile, "Profile", "/examcenter/profile"},
    {:exams, "Exams I offer", "/examcenter/exams"},
    {:slots, "Slots", "/examcenter/slots"},
    {:calendar, "Calendar", "/examcenter/calendar"},
    {:bookings, "Bookings", "/examcenter/bookings"}
  ]

  @doc """
  Centre shell — sidebar nav for `/examcenter/*` authenticated pages.
  Mirror of `admin_shell/1` with the centre-side nav items. Indigo
  accent (matches the root-layout scope chip colour) so an admin
  who's also signed in as a centre can tell screens apart at a glance.
  """
  attr :current_exam_centre, :map, required: true
  attr :active, :atom, required: true
  slot :inner_block, required: true

  def centre_shell(assigns) do
    assigns = assign(assigns, :nav_items, @centre_nav_items)

    ~H"""
    <div class="flex min-h-screen bg-ink-50">
      <aside
        aria-label="Centre navigation"
        class="hidden w-64 shrink-0 flex-col gap-1 border-r border-ink-200 bg-white px-4 py-6 md:flex"
      >
        <div class="mb-6 px-2">
          <p class="font-mono text-xs uppercase tracking-widest text-indigo-700">Exam centre</p>
          <p class="mt-2 truncate font-sans text-sm font-semibold text-ink-900">
            {@current_exam_centre.name}
          </p>
          <p class="truncate text-xs text-ink-500">{@current_exam_centre.email}</p>
        </div>

        <nav class="flex flex-col gap-1">
          <%= for {key, label, path} <- @nav_items do %>
            <.link
              navigate={path}
              aria-current={if key == @active, do: "page"}
              class={[
                "block rounded-lg px-3 py-2 text-sm transition",
                "text-ink-700 hover:bg-ink-100",
                "aria-[current=page]:bg-indigo-50 aria-[current=page]:font-semibold aria-[current=page]:text-indigo-800"
              ]}
            >
              {label}
            </.link>
          <% end %>
        </nav>

        <div class="mt-auto border-t border-ink-200 pt-4">
          <.link
            href="/examcenter/settings"
            class="block rounded-lg px-3 py-2 text-sm text-ink-700 hover:bg-ink-100"
          >
            Settings
          </.link>
          <.link
            href="/examcenter/logout"
            method="delete"
            class="block rounded-lg px-3 py-2 text-sm text-ink-700 hover:bg-ink-100"
          >
            Log out
          </.link>
        </div>
      </aside>

      <main class="flex-1 px-6 py-10 sm:px-10">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end
end
