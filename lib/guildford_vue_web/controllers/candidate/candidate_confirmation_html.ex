defmodule GuildfordVueWeb.Candidate.CandidateConfirmationHTML do
  @moduledoc """
  Templates for the candidate email-verification controller.
  Renders without the root layout to keep the page focused.
  """
  use GuildfordVueWeb, :html

  embed_templates "candidate_confirmation_html/*"
end
