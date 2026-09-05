defmodule GuildfordVue.Admins.AdminNotifier do
  @moduledoc """
  Swoosh stubs for admin emails. No email verification flow — admins are
  invited by other admins or seeded.
  """
  import Swoosh.Email

  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.Mailer

  @from {"Guildford Vue", "no-reply@guildfordvue.test"}

  @spec deliver_password_reset_email(Admin.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_password_reset_email(%Admin{email: to, name: name}, url) do
    new()
    |> to({name, to})
    |> from(@from)
    |> subject("Reset your Guildford Vue admin password")
    |> text_body("""
    Hi #{name},

    To reset your Guildford Vue administrator password, visit:

    #{url}

    This link expires in 24 hours.

    — Guildford Vue platform
    """)
    |> Mailer.deliver()
  end

  @spec deliver_invitation_email(Admin.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_invitation_email(%Admin{email: to, name: name, role: role}, url) do
    new()
    |> to({name, to})
    |> from(@from)
    |> subject("You've been invited as a Guildford Vue administrator")
    |> text_body("""
    Hi #{name},

    You've been invited to the Guildford Vue back-office as an
    administrator with the role: #{role}.

    To complete your account, set up your password here:

    #{url}

    This link expires in 24 hours.

    — Guildford Vue platform
    """)
    |> Mailer.deliver()
  end

  @doc "Sprint 11.5 Slice 7 — email-OTP MFA sign-in code."
  @spec deliver_otp_email(Admin.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_otp_email(%Admin{email: to, name: name}, code) when is_binary(code) do
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
