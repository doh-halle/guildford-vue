defmodule GuildfordVue.Bookings do
  @moduledoc """
  Bookings context — the dissertation's railway-oriented programming
  showcase (PRD §4.7 / Sprint 7).

  This Sprint 7 Slice 1 lands the persistence layer only:
  `persist_booking/1`, lookups, and listings. The `create_booking/3`
  railway pipeline lands in Slice 3 alongside the PaymentGateway /
  PDFGenerator stubs.
  """
  import Ecto.Query, warn: false

  alias GuildfordVue.AuditLog
  alias GuildfordVue.Bookings.{Booking, BookingReference}
  alias GuildfordVue.Candidates.Candidate
  alias GuildfordVue.Candidates.CandidateNotifier
  alias GuildfordVue.Centres
  alias GuildfordVue.Exams
  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.PaymentGateway
  alias GuildfordVue.Payments
  alias GuildfordVue.Repo
  alias GuildfordVue.Slots.Slot

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t() | atom()}

  @spec persist_booking(map()) :: result(Booking.t())
  def persist_booking(attrs) when is_map(attrs) do
    %Booking{}
    |> Booking.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_booking!(binary()) :: Booking.t()
  def get_booking!(id), do: Repo.get!(Booking, id)

  @spec get_booking_by_reference(String.t() | nil) :: Booking.t() | nil
  def get_booking_by_reference(nil), do: nil
  def get_booking_by_reference(ref) when is_binary(ref), do: Repo.get_by(Booking, reference: ref)

  @doc """
  Admin-facing listing — every booking, newest-first.
  Accepts an optional `:limit` (default 100).
  """
  @spec list_recent_bookings(keyword()) :: [Booking.t()]
  def list_recent_bookings(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from b in Booking,
        order_by: [desc: b.inserted_at],
        limit: ^limit
    )
  end

  @spec list_candidate_bookings(Candidate.t() | binary()) :: [Booking.t()]
  def list_candidate_bookings(%Candidate{id: id}), do: list_candidate_bookings(id)

  def list_candidate_bookings(id) when is_binary(id) do
    Repo.all(
      from b in Booking,
        where: b.candidate_id == ^id,
        order_by: [desc: b.inserted_at]
    )
  end

  @doc """
  Every booking that belongs to `centre`, newest-first. Used by the
  exam-centre dashboard's bookings tab. Tenant isolation is enforced
  via `exam_centre_id` — no cross-centre leakage.

  Opts:
    * `:status` — `"confirmed" | "cancelled" | "refunded" | "all" | nil`.
      Missing / `nil` / `"all"` = no status filter. Any other value
      narrows the result set with `WHERE status = ^value`.
  """
  @spec list_bookings_for_centre(ExamCentre.t() | binary(), keyword()) :: [Booking.t()]
  def list_bookings_for_centre(centre_or_id, opts \\ [])

  def list_bookings_for_centre(%ExamCentre{id: id}, opts),
    do: list_bookings_for_centre(id, opts)

  def list_bookings_for_centre(id, opts) when is_binary(id) do
    from(b in Booking,
      where: b.exam_centre_id == ^id,
      order_by: [desc: b.inserted_at]
    )
    |> apply_status_filter(Keyword.get(opts, :status))
    |> Repo.all()
  end

  defp apply_status_filter(query, status) when status in [nil, "all", ""], do: query

  defp apply_status_filter(query, status) when is_binary(status),
    do: from(b in query, where: b.status == ^status)

  @doc """
  Single booking by `reference`, but only when it belongs to `centre`.
  `{:error, :not_found}` for unknown reference OR a reference owned
  by a different centre — the LV can't tell the two cases apart, so
  there's no enumeration leak.
  """
  @spec get_booking_for_centre(ExamCentre.t(), String.t()) ::
          {:ok, Booking.t()} | {:error, :not_found}
  def get_booking_for_centre(%ExamCentre{id: centre_id}, reference) when is_binary(reference) do
    case Repo.get_by(Booking, reference: reference, exam_centre_id: centre_id) do
      nil -> {:error, :not_found}
      %Booking{} = booking -> {:ok, booking}
    end
  end

  @doc """
  Bookings whose slot starts at or after `now` — soonest first.
  Sprint 9 dashboard: candidates' "upcoming reservations".
  """
  @spec list_upcoming_candidate_bookings(Candidate.t() | binary()) :: [Booking.t()]
  def list_upcoming_candidate_bookings(%Candidate{id: id}),
    do: list_upcoming_candidate_bookings(id)

  def list_upcoming_candidate_bookings(id) when is_binary(id) do
    now = DateTime.utc_now()

    Repo.all(
      from b in Booking,
        join: s in GuildfordVue.Slots.Slot,
        on: s.id == b.slot_id,
        where: b.candidate_id == ^id and s.starts_at >= ^now,
        order_by: [asc: s.starts_at]
    )
  end

  @doc """
  Bookings whose slot has already started — most recent first.
  Sprint 9 dashboard: candidates' "past reservations".
  """
  @spec list_past_candidate_bookings(Candidate.t() | binary()) :: [Booking.t()]
  def list_past_candidate_bookings(%Candidate{id: id}),
    do: list_past_candidate_bookings(id)

  def list_past_candidate_bookings(id) when is_binary(id) do
    now = DateTime.utc_now()

    Repo.all(
      from b in Booking,
        join: s in GuildfordVue.Slots.Slot,
        on: s.id == b.slot_id,
        where: b.candidate_id == ^id and s.starts_at < ^now,
        order_by: [desc: s.starts_at]
    )
  end

  # ---------------------------------------------------------------------------
  # Railway pipeline — Sprint 7 Slice 3
  # ---------------------------------------------------------------------------

  @type pipeline_error :: {:error, atom(), term()}
  @type pipeline_result :: {:ok, Booking.t()} | pipeline_error()

  @doc """
  Books `slot` for `candidate`. Eight-stage railway:

      validate → reserve → pay → persist → pdf → notify → audit

  Each stage returns a tagged tuple. The first `{:error, reason}`
  short-circuits the `with`. On failure AFTER `:reserve` the
  acquired seat is released so concurrent bookers can pick it up
  again — this is the dissertation's compensating-transaction
  example.

  Returns `{:ok, %Booking{}}` on success or
  `{:error, stage_atom, reason}` so callers can branch on stage
  for UX-friendly flash messages (e.g. ":pay → 'Your card was
  declined'", ":reserve → 'That slot just sold out'").
  """
  @spec create_booking(Candidate.t(), Slot.t(), keyword()) :: pipeline_result()
  def create_booking(%Candidate{} = candidate, %Slot{} = slot, opts \\ []) do
    with :ok <- validate(slot),
         {:ok, centre_pid} <- ensure_centre(slot.exam_centre_id),
         {:ok, reserved} <- reserve(centre_pid, slot.id),
         {:ok, exam} <- fetch_exam(slot.exam_id),
         {:ok, payment} <- pay(exam.price_pence, candidate, centre_pid, slot.id, opts),
         {:ok, booking} <- persist(candidate, reserved, exam, payment),
         _ = record_payment(booking, payment, exam.price_pence),
         {:ok, with_pdf} <- attach_pdf(booking) do
      _ = notify(candidate, with_pdf, reserved, exam)
      _ = audit(candidate, with_pdf, reserved, exam)
      # Sprint 12 Slice 2 — emit telemetry for the PromEx booking plugin.
      :telemetry.execute([:guildford_vue, :booking, :created], %{count: 1}, %{
        centre_id: slot.exam_centre_id
      })

      {:ok, with_pdf}
    else
      {:error, :pay, :card_declined} = err ->
        :telemetry.execute([:guildford_vue, :booking, :payment_declined], %{count: 1}, %{})
        err

      {:error, :reserve, :sold_out} = err ->
        :telemetry.execute([:guildford_vue, :booking, :slot_sold_out], %{count: 1}, %{})
        err

      {:error, _stage, _reason} = err ->
        err

      {:error, reason} ->
        {:error, :unknown, reason}
    end
  end

  # ---- Stage 1: validate -----------------------------------------

  defp validate(%Slot{status: "cancelled"}), do: {:error, :validate, :slot_unbookable}

  defp validate(%Slot{starts_at: %DateTime{} = at}) do
    if DateTime.compare(at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :validate, :slot_in_past}
    end
  end

  # ---- Stage 2: reserve via centre server ------------------------

  defp ensure_centre(centre_id) do
    case Centres.ensure_started(centre_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, :reserve, reason}
    end
  end

  defp reserve(pid, slot_id) do
    case Centres.reserve_slot(pid, slot_id) do
      {:ok, slot} -> {:ok, slot}
      {:error, reason} -> {:error, :reserve, reason}
    end
  end

  # ---- Stage 3: charge -------------------------------------------

  defp fetch_exam(exam_id) do
    {:ok, Exams.get_exam!(exam_id)}
  rescue
    Ecto.NoResultsError -> {:error, :validate, :exam_missing}
  end

  defp pay(amount_pence, candidate, centre_pid, slot_id, opts) do
    gateway_opts =
      %{candidate_id: candidate.id, slot_id: slot_id}
      |> Map.merge(opts_to_map(opts))

    case PaymentGateway.charge(amount_pence, gateway_opts) do
      {:ok, payment} ->
        {:ok, payment}

      {:error, reason} ->
        # Compensating transaction: release the seat so a concurrent
        # booker can pick it up.
        _ = Centres.release_slot(centre_pid, slot_id)
        {:error, :pay, reason}
    end
  end

  defp opts_to_map(opts) when is_list(opts), do: Map.new(opts)
  defp opts_to_map(opts) when is_map(opts), do: opts
  defp opts_to_map(_), do: %{}

  # ---- Stage 4: persist ------------------------------------------

  defp persist(candidate, slot, exam, payment) do
    attrs = %{
      candidate_id: candidate.id,
      slot_id: slot.id,
      exam_id: slot.exam_id,
      exam_centre_id: slot.exam_centre_id,
      reference: BookingReference.generate(),
      status: "confirmed",
      price_pence: exam.price_pence,
      paid_at: payment.charged_at,
      payment_token: payment.token,
      pdf_url: nil
    }

    case persist_booking(attrs) do
      {:ok, booking} -> {:ok, booking}
      {:error, cs} -> {:error, :persist, cs}
    end
  end

  # ---- Stage 4b: persist payment ---------------------------------

  # Best-effort: writes a Payment row from the gateway's response.
  # Failure does not roll back the booking — the booking is canonical
  # and an operator can reconcile via the audit log + the payment
  # adapter's own records.
  defp record_payment(booking, payment, amount_pence) do
    Payments.record_payment(%{
      booking_id: booking.id,
      provider: Map.get(payment, :provider, "visa"),
      masked_pan: Map.get(payment, :masked_pan),
      amount_pence: amount_pence,
      status: "succeeded",
      processed_at: Map.get(payment, :charged_at, DateTime.utc_now())
    })
  end

  # ---- Stage 5: PDF URL ------------------------------------------
  #
  # Since Sprint 9 Slice 2 the PDF is rendered on-demand by
  # `ReceiptController.show_pdf/2`. We just stamp the canonical
  # URL on the booking so list/email/preview links resolve.

  defp attach_pdf(booking) do
    url = "/candidate/bookings/#{booking.reference}/receipt.pdf"

    case Repo.update(Ecto.Changeset.change(booking, pdf_url: url)) do
      {:ok, updated} -> {:ok, updated}
      {:error, _cs} -> {:ok, %{booking | pdf_url: url}}
    end
  end

  # ---- Stage 6 + 7: side effects (best-effort) -------------------

  defp notify(candidate, booking, slot, exam) do
    centre = GuildfordVue.ExamCentres.get_exam_centre!(booking.exam_centre_id)
    pdf_bytes = render_pdf_for_email(booking, candidate, exam, centre, slot)

    CandidateNotifier.deliver_booking_confirmation_email(candidate, %{
      reference: booking.reference,
      pdf_url: booking.pdf_url,
      starts_at: slot.starts_at,
      exam_name: exam.name,
      pdf_bytes: pdf_bytes
    })
  end

  defp render_pdf_for_email(booking, candidate, exam, centre, slot) do
    data = %{
      booking: booking,
      candidate: candidate,
      exam: exam,
      centre: centre,
      slot: slot
    }

    case GuildfordVue.PDFGenerator.render_receipt(data) do
      {:ok, bytes} -> bytes
      {:error, _reason} -> nil
    end
  end

  defp audit(candidate, booking, slot, exam) do
    AuditLog.append(:booking_created, %{
      aggregate_id: booking.id,
      actor: %{id: candidate.id, type: "candidate"},
      payload: %{
        reference: booking.reference,
        exam_code: exam.code,
        slot_id: slot.id,
        slot_starts_at: DateTime.to_iso8601(slot.starts_at),
        centre_id: slot.exam_centre_id,
        price_pence: booking.price_pence
      }
    })
  end

  # ---------------------------------------------------------------------------
  # Cancellation
  # ---------------------------------------------------------------------------

  @doc """
  Cancels a confirmed booking. Releases the slot via the
  CentreServer (so concurrent bookers immediately see availability)
  and audits the cancellation. Refunds are Sprint 8 follow-up.

  Returns `{:ok, %Booking{}}` or `{:error, :already_cancelled}`.
  """
  @spec cancel_booking(Booking.t(), Candidate.t()) ::
          {:ok, Booking.t()} | {:error, atom()}
  def cancel_booking(%Booking{status: "cancelled"}, _candidate),
    do: {:error, :already_cancelled}

  def cancel_booking(%Booking{} = booking, %Candidate{} = candidate) do
    with {:ok, pid} <- Centres.ensure_started(booking.exam_centre_id),
         _ <- Centres.release_slot(pid, booking.slot_id),
         {:ok, cancelled} <-
           Repo.update(Booking.cancel_changeset(booking, DateTime.utc_now())) do
      {:ok, _} =
        AuditLog.append(:booking_cancelled, %{
          aggregate_id: cancelled.id,
          actor: %{id: candidate.id, type: "candidate"},
          payload: %{
            reference: cancelled.reference,
            slot_id: cancelled.slot_id
          }
        })

      {:ok, cancelled}
    end
  end

  @doc """
  Admin-initiated refund. Flips status to "refunded", releases the
  slot, records a refunded Payment row mirroring the original
  amount, and writes a `booking_refunded` audit entry.

  Idempotent on already-refunded bookings: `{:error, :already_refunded}`.
  """
  @spec refund(Booking.t(), GuildfordVue.Admins.Admin.t()) ::
          {:ok, Booking.t()} | {:error, atom() | Ecto.Changeset.t()}
  def refund(%Booking{status: "refunded"}, _admin), do: {:error, :already_refunded}

  def refund(%Booking{} = booking, %GuildfordVue.Admins.Admin{} = admin) do
    with {:ok, pid} <- Centres.ensure_started(booking.exam_centre_id),
         _ <- Centres.release_slot(pid, booking.slot_id),
         {:ok, refunded} <-
           Repo.update(Booking.refund_changeset(booking, DateTime.utc_now())) do
      _ = record_refund_payment(refunded)

      {:ok, _} =
        AuditLog.append(:booking_refunded, %{
          aggregate_id: refunded.id,
          actor: %{id: admin.id, type: "admin"},
          payload: %{
            reference: refunded.reference,
            slot_id: refunded.slot_id,
            amount_pence: refunded.price_pence
          }
        })

      {:ok, refunded}
    end
  end

  defp record_refund_payment(booking) do
    Payments.record_payment(%{
      booking_id: booking.id,
      provider: "visa",
      masked_pan: "•••• •••• •••• 0000",
      amount_pence: booking.price_pence,
      status: "refunded",
      processed_at: DateTime.utc_now()
    })
  end
end
