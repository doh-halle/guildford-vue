defmodule GuildfordVueWeb.Candidate.CandidateConfirmationController do
  @moduledoc """
  GET /candidate/verify-email/:token — consumes the one-time email
  verification token issued at registration (PRD §4.2 FR-AUTH-3).

  Implemented as a regular controller rather than a LiveView because
  token consumption is a single-shot operation: LiveView mounts twice
  (once for the HTTP render, once for the WebSocket connection), which
  would consume the single-use token on the HTTP pass and leave the
  WebSocket pass seeing an "expired" token.
  """
  use GuildfordVueWeb, :controller

  alias GuildfordVue.Candidates

  def show(conn, %{"token" => token}) do
    case Candidates.verify_email(token) do
      {:ok, _candidate} -> render(conn, :verified, layout: false)
      {:error, _} -> render(conn, :invalid, layout: false)
    end
  end
end
