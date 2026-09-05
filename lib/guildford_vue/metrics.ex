defmodule GuildfordVue.Metrics do
  @moduledoc """
  Operational metrics for the back-office dashboard (PRD §4.10 /
  Sprint 10).

  Pure query layer over `bookings`, `payments`, `candidates`, and
  `exam_centres`. Every public function returns either a primitive
  count/sum or a plain map snapshot — no GenServer state, no
  caching. The LiveView refreshes by re-calling `snapshot/0` on a
  timer.
  """
  import Ecto.Query, only: [from: 2]

  alias GuildfordVue.Bookings.Booking
  alias GuildfordVue.Candidates
  alias GuildfordVue.ExamCentres
  alias GuildfordVue.Payments.Payment
  alias GuildfordVue.Repo

  @doc """
  Returns a snapshot map suitable for direct assignment in a
  LiveView. All values are computed at call time.
  """
  @spec snapshot() :: map()
  def snapshot do
    %{
      bookings_today: count_bookings_today(),
      bookings_this_week: count_bookings_this_week(),
      bookings_this_month: count_bookings_this_month(),
      revenue_pence: sum_revenue_pence(),
      candidates_total: Candidates.count_all(),
      candidates_active: Candidates.count_active(),
      centres_approved: ExamCentres.count_by_status("approved"),
      centres_pending: ExamCentres.count_by_status("pending")
    }
  end

  @spec count_bookings_today() :: non_neg_integer()
  def count_bookings_today, do: count_bookings_since(start_of_today())

  @spec count_bookings_this_week() :: non_neg_integer()
  def count_bookings_this_week, do: count_bookings_since(start_of_week())

  @spec count_bookings_this_month() :: non_neg_integer()
  def count_bookings_this_month, do: count_bookings_since(start_of_month())

  @spec sum_revenue_pence() :: non_neg_integer()
  def sum_revenue_pence do
    Repo.one(
      from p in Payment,
        where: p.status == "succeeded",
        select: coalesce(sum(p.amount_pence), 0)
    )
  end

  # ---- helpers -----------------------------------------------------

  defp count_bookings_since(%DateTime{} = at) do
    Repo.one(
      from b in Booking,
        where: b.inserted_at >= ^at,
        select: count(b.id)
    )
  end

  defp start_of_today do
    today = Date.utc_today()
    DateTime.new!(today, ~T[00:00:00.000000], "Etc/UTC")
  end

  defp start_of_week do
    today = Date.utc_today()
    monday = Date.add(today, -(Date.day_of_week(today) - 1))
    DateTime.new!(monday, ~T[00:00:00.000000], "Etc/UTC")
  end

  defp start_of_month do
    today = Date.utc_today()
    first = %{today | day: 1}
    DateTime.new!(first, ~T[00:00:00.000000], "Etc/UTC")
  end
end
