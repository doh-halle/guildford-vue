defmodule GuildfordVueWeb.Admin.AdminCentresLive do
  @moduledoc """
  Pending centre approval queue (PRD §4.4 FR-ADMIN-1).

  Each pending centre gets a card with an Approve button and a Reject
  action. Reject pops out an inline form to capture a required reason
  (the centre receives it in the rejection email).

  Both actions go through `ExamCentres.approve/2` /
  `ExamCentres.reject/3` which run the state change, audit-log append,
  and email delivery in a single transaction.
  """
  use GuildfordVueWeb, :live_view

  alias GuildfordVue.ExamCentres

  @valid_statuses ~w(pending approved rejected)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Centres")
     |> assign(:rejecting_id, nil)
     |> assign(:reject_error, nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    status = normalise_status(params["status"])

    {:noreply,
     socket
     |> assign(:status, status)
     |> assign(:centres, list_for(status))}
  end

  defp normalise_status(s) when s in @valid_statuses, do: s
  defp normalise_status(_), do: "pending"

  defp list_for("approved"), do: ExamCentres.list_approved_centres()
  defp list_for("rejected"), do: ExamCentres.list_rejected_centres()
  defp list_for(_), do: ExamCentres.list_pending_centres()

  defp tab_caption("approved"), do: "Approved exam centres currently visible to candidates."
  defp tab_caption("rejected"), do: "Rejected registrations, ordered most recent first."
  defp tab_caption(_), do: "Pending exam-centre registrations awaiting review."

  defp empty_caption("approved"), do: "No approved centres yet."
  defp empty_caption("rejected"), do: "No rejected centres."
  defp empty_caption(_), do: "No centres pending approval."

  @impl Phoenix.LiveView
  def handle_event("approve", %{"id" => id}, socket) do
    centre = ExamCentres.get_exam_centre!(id)

    case ExamCentres.approve(centre, socket.assigns.current_admin) do
      {:ok, approved} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{approved.name} has been approved.")
         |> assign(:centres, list_for(socket.assigns.status))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not approve: #{inspect(reason)}")}
    end
  end

  def handle_event("open-reject", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:rejecting_id, id) |> assign(:reject_error, nil)}
  end

  def handle_event("close-reject", _params, socket) do
    {:noreply, assign(socket, :rejecting_id, nil)}
  end

  def handle_event("reject", %{"id" => id, "reject" => %{"reason" => reason}}, socket) do
    centre = ExamCentres.get_exam_centre!(id)

    case ExamCentres.reject(centre, socket.assigns.current_admin, reason) do
      {:ok, rejected} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{rejected.name} has been rejected.")
         |> assign(:rejecting_id, nil)
         |> assign(:reject_error, nil)
         |> assign(:centres, list_for(socket.assigns.status))}

      {:error, :reason_required} ->
        {:noreply, assign(socket, :reject_error, "Reason is required")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not reject: #{inspect(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <GuildfordVueWeb.Layouts.admin_shell current_admin={@current_admin} active={:centres}>
      <div class="flex flex-wrap items-baseline justify-between gap-3">
        <h1 class="font-sans text-3xl font-bold tracking-tight text-ink-900">Centres</h1>
        <.link
          navigate={~p"/backoffice/centres/performance"}
          class="text-sm font-semibold text-teal-700 hover:underline"
        >
          Performance →
        </.link>
      </div>

      <nav class="mt-4 flex gap-1 border-b border-ink-200" aria-label="Centre status">
        <%= for {key, label} <- [{"pending", "Pending"}, {"approved", "Approved"}, {"rejected", "Rejected"}] do %>
          <.link
            patch={~p"/backoffice/centres?status=#{key}"}
            data-test-id={"tab-#{key}"}
            class={[
              "px-4 py-2 text-sm font-semibold border-b-2 -mb-px",
              @status == key && "border-teal-700 text-teal-700",
              @status != key && "border-transparent text-ink-500 hover:text-ink-700"
            ]}
            aria-current={@status == key && "page"}
          >
            {label}
          </.link>
        <% end %>
      </nav>

      <p class="mt-3 text-sm text-ink-500">
        {tab_caption(@status)}
      </p>

      <%= if @centres == [] do %>
        <div class="mt-10 rounded-2xl border border-dashed border-ink-300 bg-white p-10 text-center text-sm text-ink-500">
          {empty_caption(@status)}
        </div>
      <% else %>
        <ul class="mt-8 space-y-4">
          <%= for centre <- @centres do %>
            <li
              id={"centre-card-#{centre.id}"}
              class="rounded-2xl border border-ink-200 bg-white p-6"
            >
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="min-w-0 flex-1">
                  <h2 class="font-sans text-lg font-bold tracking-tight text-ink-900">
                    {centre.name}
                  </h2>
                  <p class="text-sm text-ink-600">{centre.email}</p>
                  <p class="mt-1 text-sm text-ink-500">
                    {centre.address_line_1}, {centre.city} {centre.postcode}
                  </p>
                  <%= if @status == "rejected" and centre.rejection_reason do %>
                    <p class="mt-2 text-sm text-red-700">
                      <span class="font-semibold">Rejection reason:</span>
                      {centre.rejection_reason}
                    </p>
                  <% end %>
                </div>

                <%= if @status == "pending" do %>
                  <div class="flex shrink-0 gap-2">
                    <button
                      type="button"
                      phx-click="approve"
                      phx-value-id={centre.id}
                      data-test-id={"approve-#{centre.id}"}
                      class="rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white hover:bg-teal-600"
                    >
                      Approve
                    </button>
                    <button
                      type="button"
                      phx-click="open-reject"
                      phx-value-id={centre.id}
                      data-test-id={"open-reject-#{centre.id}"}
                      class="rounded-lg border border-ink-300 px-4 py-2 text-sm font-semibold text-ink-700 hover:bg-ink-50"
                    >
                      Reject
                    </button>
                  </div>
                <% end %>
              </div>

              <%= if @rejecting_id == centre.id do %>
                <form
                  id={"reject-form-#{centre.id}"}
                  phx-submit="reject"
                  phx-value-id={centre.id}
                  class="mt-6 border-t border-ink-200 pt-6"
                >
                  <label
                    class="block text-sm font-medium text-ink-700"
                    for={"reject-reason-#{centre.id}"}
                  >
                    Reason for rejection
                  </label>
                  <p class="mt-1 text-xs text-ink-500">
                    The centre will receive this verbatim in their rejection email.
                  </p>
                  <textarea
                    id={"reject-reason-#{centre.id}"}
                    name="reject[reason]"
                    rows="3"
                    class="mt-2 block w-full rounded-lg border border-ink-200 bg-white px-3 py-2 text-sm text-ink-900 focus:border-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-500/30"
                  ></textarea>
                  <%= if @reject_error do %>
                    <p class="mt-2 text-sm text-red-700">{@reject_error}</p>
                  <% end %>
                  <div class="mt-3 flex gap-2">
                    <button
                      type="submit"
                      class="rounded-lg bg-red-700 px-4 py-2 text-sm font-semibold text-white hover:bg-red-600"
                    >
                      Confirm rejection
                    </button>
                    <button
                      type="button"
                      phx-click="close-reject"
                      class="rounded-lg border border-ink-300 px-4 py-2 text-sm text-ink-700 hover:bg-ink-50"
                    >
                      Cancel
                    </button>
                  </div>
                </form>
              <% end %>
            </li>
          <% end %>
        </ul>
      <% end %>
    </GuildfordVueWeb.Layouts.admin_shell>
    """
  end
end
