defmodule GuildfordVue.ExamCentres.ExamCentreNotifier do
  @moduledoc """
  Swoosh stubs for exam-centre emails. Centres receive notifications on
  registration-acknowledgement, approval, and rejection (Sprint 2 will wire
  the approval-flow emails). Sprint 1a scope: password reset only.
  """
  import Swoosh.Email

  alias GuildfordVue.ExamCentres.ExamCentre
  alias GuildfordVue.Mailer

  @from {"Guildford Vue", "no-reply@guildfordvue.test"}

  @spec deliver_password_reset_email(ExamCentre.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_password_reset_email(%ExamCentre{email: to, name: name}, url) do
    new()
    |> to({name, to})
    |> from(@from)
    |> subject("Reset your Guildford Vue exam-centre password")
    |> text_body("""
    Hi #{name},

    To reset your Guildford Vue exam-centre password, visit:

    #{url}

    This link expires in 24 hours.

    — Guildford Vue platform
    """)
    |> Mailer.deliver()
  end

  @spec deliver_approval_email(ExamCentre.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_approval_email(%ExamCentre{email: to, name: name}) do
    new()
    |> to({name, to})
    |> from(@from)
    |> subject("Your Guildford Vue exam centre has been approved")
    |> text_body("""
    Hi #{name},

    Good news — your exam centre has been approved on Guildford Vue.
    You can now sign in and publish exam slots.

    Sign in: https://guildfordvue.test/examcenter/login

    — Guildford Vue platform
    """)
    |> Mailer.deliver()
  end

  @spec deliver_rejection_email(ExamCentre.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_rejection_email(%ExamCentre{email: to, name: name}, reason) do
    new()
    |> to({name, to})
    |> from(@from)
    |> subject("Update on your Guildford Vue exam centre application")
    |> text_body("""
    Hi #{name},

    Thank you for your application to register as an exam centre on
    Guildford Vue. After review, your application was not accepted at
    this time. The reviewing administrator's note:

    #{reason}

    If you would like to address the points raised and re-apply, please
    contact platform support.

    — Guildford Vue platform
    """)
    |> Mailer.deliver()
  end

  @doc "Sprint 11.5 Slice 7 — email-OTP MFA sign-in code."
  @spec deliver_otp_email(ExamCentre.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_otp_email(%ExamCentre{email: to, name: name}, code) when is_binary(code) do
    new()
    |> to({name, to})
    |> from(@from)
    |> subject("Your Guildford Vue sign-in code")
    |> text_body("""
    Hi #{name},

    Your sign-in code is:

      #{code}

    Enter it on the verification page to finish signing in. The code
    expires in 10 minutes. If you didn't try to sign in, you can ignore
    this email.

    — Guildford Vue platform
    """)
    |> Mailer.deliver()
  end
end
