defmodule GuildfordVue.Candidates.CandidateNotifier do
  @moduledoc """
  Swoosh email dispatch for the candidate auth scope. In dev the messages land
  in Mailcatcher (port 1080); in test they're captured by `Swoosh.Adapters.Test`.

  Each helper takes a fully-rendered URL (assembled by the caller in
  `GuildfordVue.Candidates`) so this module is free of routing concerns —
  matches the functional-core / imperative-shell pattern.
  """
  import Swoosh.Email

  alias GuildfordVue.Candidates.Candidate
  alias GuildfordVue.Mailer

  @from {"Guildford Vue", "no-reply@guildfordvue.test"}

  @spec deliver_verification_email(Candidate.t(), String.t() | any()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_verification_email(%Candidate{email: to, first_name: first_name}, url) do
    new()
    |> to(to)
    |> from(@from)
    |> subject("Verify your Guildford Vue account")
    |> text_body("""
    Hi #{first_name},

    Please confirm your email address by visiting:

    #{url}

    If you did not create a Guildford Vue account, you can ignore this email.

    — The Guildford Vue team
    """)
    |> Mailer.deliver()
  end

  @spec deliver_password_reset_email(Candidate.t(), String.t() | any()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_password_reset_email(%Candidate{email: to, first_name: first_name}, url) do
    new()
    |> to(to)
    |> from(@from)
    |> subject("Reset your Guildford Vue password")
    |> text_body("""
    Hi #{first_name},

    A password reset was requested for your Guildford Vue account.

    To reset your password, visit:

    #{url}

    This link expires in 24 hours. If you did not request a reset, ignore this email.

    — The Guildford Vue team
    """)
    |> Mailer.deliver()
  end

  @doc """
  Sends a booking-confirmation email with the booking reference,
  the receipt URL, and (Sprint 9 Slice 4) the PDF receipt as an
  attachment when `:pdf_bytes` is supplied.

  If `:pdf_bytes` is missing/nil, the email is still sent without
  an attachment — best-effort, the URL link in the body remains.
  """
  @spec deliver_booking_confirmation_email(Candidate.t(), map()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_booking_confirmation_email(
        %Candidate{email: to, first_name: first_name},
        %{reference: ref, pdf_url: pdf_url, starts_at: starts_at, exam_name: exam_name} = meta
      ) do
    new()
    |> to({first_name, to})
    |> from(@from)
    |> subject("Booking confirmed — #{ref}")
    |> text_body("""
    Hi #{first_name},

    Your Guildford Vue booking is confirmed.

    Reference: #{ref}
    Exam:      #{exam_name}
    Starts:    #{Calendar.strftime(starts_at, "%A %d %B %Y · %H:%M")}

    Your PDF receipt:
    #{pdf_url}

    — The Guildford Vue team
    """)
    |> maybe_attach_pdf(Map.get(meta, :pdf_bytes), ref)
    |> Mailer.deliver()
  end

  defp maybe_attach_pdf(email, bytes, ref) when is_binary(bytes) do
    att =
      Swoosh.Attachment.new({:data, bytes},
        filename: "#{ref}.pdf",
        content_type: "application/pdf",
        type: :attachment
      )

    Swoosh.Email.attachment(email, att)
  end

  defp maybe_attach_pdf(email, _bytes, _ref), do: email

  @doc """
  Sprint 11.5 Slice 7 — email-OTP MFA. Sends a single-use 6-digit
  sign-in code that the candidate enters at the verify-OTP form.
  Caller (Auth.OTP.issue/3) generates the code; we just deliver it.
  """
  @spec deliver_otp_email(Candidate.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_otp_email(%Candidate{email: to, first_name: first_name}, code)
      when is_binary(code) do
    new()
    |> to({first_name, to})
    |> from(@from)
    |> subject("Your Guildford Vue sign-in code")
    |> text_body("""
    Hi #{first_name},

    Your sign-in code is:

      #{code}

    Enter it on the verification page to finish signing in. The code
    expires in 10 minutes. If you didn't try to sign in, you can ignore
    this email.

    — The Guildford Vue team
    """)
    |> Mailer.deliver()
  end
end
