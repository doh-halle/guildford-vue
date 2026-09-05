defmodule GuildfordVue.CandidatesAuthenticateTest do
  @moduledoc """
  Sprint 11.5 Slice 3 — email-verification enforcement on
  candidate login. The new `Candidates.authenticate_candidate/2`
  layers an `email_verified_at` check on top of the existing
  password lookup so unverified candidates can't sign in.

  The lower-level `get_candidate_by_email_and_password/2` is
  kept (other tests + the audit isolation tests depend on its
  shape); only the session-controller path uses the new tighter
  function.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.Candidates
  alias GuildfordVue.Candidates.Candidate

  defp register_unverified(email) do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => email,
        "password" => "supersecret123!A",
        "first_name" => "Cand",
        "last_name" => "X"
      })

    candidate
  end

  defp register_verified(email) do
    candidate = register_unverified(email)

    {:ok, verified} =
      candidate
      |> Candidate.confirm_email_changeset(DateTime.utc_now())
      |> Repo.update()

    verified
  end

  test "verified candidate + correct password → {:ok, candidate}" do
    candidate = register_verified("verified-#{System.unique_integer([:positive])}@example.com")

    assert {:ok, result} =
             Candidates.authenticate_candidate(candidate.email, "supersecret123!A")

    assert result.id == candidate.id
  end

  test "unverified candidate + correct password → {:error, :email_not_verified}" do
    candidate =
      register_unverified("unverified-#{System.unique_integer([:positive])}@example.com")

    assert {:error, :email_not_verified} =
             Candidates.authenticate_candidate(candidate.email, "supersecret123!A")
  end

  test "verified candidate + wrong password → {:error, :invalid_credentials}" do
    candidate = register_verified("wrongpw-#{System.unique_integer([:positive])}@example.com")

    assert {:error, :invalid_credentials} =
             Candidates.authenticate_candidate(candidate.email, "WRONG!")
  end

  test "unknown email → {:error, :invalid_credentials} (never leaks 'no such email')" do
    assert {:error, :invalid_credentials} =
             Candidates.authenticate_candidate(
               "nobody-#{System.unique_integer([:positive])}@example.com",
               "x"
             )
  end

  test "suspended candidate → {:error, :invalid_credentials} (treated as non-existent)" do
    candidate = register_verified("suspended-#{System.unique_integer([:positive])}@example.com")
    {:ok, _} = Candidates.suspend(candidate)

    assert {:error, :invalid_credentials} =
             Candidates.authenticate_candidate(candidate.email, "supersecret123!A")
  end

  test "nil / non-binary input → {:error, :invalid_credentials}" do
    assert {:error, :invalid_credentials} = Candidates.authenticate_candidate(nil, "x")
    assert {:error, :invalid_credentials} = Candidates.authenticate_candidate("x", nil)
  end
end
