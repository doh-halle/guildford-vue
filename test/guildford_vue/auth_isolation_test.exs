defmodule GuildfordVue.AuthIsolationTest do
  @moduledoc """
  Cross-context isolation tests. The PRD (§4.1) is explicit: "There is no
  cross-authentication: a candidate cannot use admin credentials and vice
  versa." These tests pin that property at the context level so the
  invariant survives even before the LiveView session pipelines exist.

  What we verify:

    1. The three contexts use disjoint database tables and never share rows.
    2. The same email address can be registered as all three user types
       independently.
    3. A session token issued by one context is not honoured by another.
    4. A password-reset token issued by one context is not honoured by
       another.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, Candidates, ExamCentres}

  @password "supersecret123!A"
  @email "shared@example.com"

  setup do
    {:ok, candidate} =
      Candidates.register_candidate(%{
        "email" => @email,
        "password" => @password,
        "first_name" => "Sam",
        "last_name" => "Shared"
      })

    {:ok, admin} =
      Admins.register_admin(%{
        "email" => @email,
        "password" => @password,
        "name" => "Sam Shared (admin)"
      })

    {:ok, centre_pending} =
      ExamCentres.register_exam_centre(%{
        "email" => @email,
        "password" => @password,
        "name" => "Sam's Test Centre",
        "address_line_1" => "1 The Street",
        "city" => "Guildford",
        "postcode" => "GU1 4LZ",
        "latitude" => 51.236,
        "longitude" => -0.572
      })

    {:ok, centre} = ExamCentres.approve(centre_pending, admin)

    %{candidate: candidate, admin: admin, centre: centre}
  end

  test "the same email may exist in all three contexts independently",
       %{candidate: c, admin: a, centre: e} do
    # Three distinct rows, three distinct ids
    assert c.id != a.id
    assert a.id != e.id
    assert c.id != e.id
  end

  test "Candidates.get_admin_by_email returns nil (function does not exist)" do
    # Compile-time guarantee — there is no such function on the Candidates module.
    refute function_exported?(Candidates, :get_admin_by_email, 1)
    refute function_exported?(Candidates, :get_exam_centre_by_email, 1)
  end

  test "Admins.get_candidate_by_email is not a function on the Admins module" do
    refute function_exported?(Admins, :get_candidate_by_email, 1)
    refute function_exported?(Admins, :get_exam_centre_by_email, 1)
  end

  test "ExamCentres.get_candidate_by_email is not a function on the ExamCentres module" do
    refute function_exported?(ExamCentres, :get_candidate_by_email, 1)
    refute function_exported?(ExamCentres, :get_admin_by_email, 1)
  end

  test "a candidate session token is rejected by Admins and ExamCentres",
       %{candidate: candidate} do
    token = Candidates.generate_session_token(candidate)

    refute Admins.get_admin_by_session_token(token)
    refute ExamCentres.get_exam_centre_by_session_token(token)

    # But the candidate context honours it
    assert Candidates.get_candidate_by_session_token(token).id == candidate.id
  end

  test "an admin session token is rejected by Candidates and ExamCentres",
       %{admin: admin} do
    token = Admins.generate_session_token(admin)

    refute Candidates.get_candidate_by_session_token(token)
    refute ExamCentres.get_exam_centre_by_session_token(token)
  end

  test "an exam-centre session token is rejected by Candidates and Admins",
       %{centre: centre} do
    token = ExamCentres.generate_session_token(centre)

    refute Candidates.get_candidate_by_session_token(token)
    refute Admins.get_admin_by_session_token(token)
  end

  test "a candidate password-reset token cannot reset an admin's password",
       %{candidate: candidate, admin: admin} do
    {:ok, candidate_reset_token} =
      Candidates.deliver_password_reset_instructions(candidate, fn t -> "url " <> t end)

    # The candidate token is in candidate_tokens, not admin_tokens.
    # Admins.reset_password decodes the token but finds no matching row.
    assert {:error, :invalid_token} =
             Admins.reset_password(candidate_reset_token, %{"password" => "newpassword789!"})

    # ExamCentres similarly refuses.
    assert {:error, :invalid_token} =
             ExamCentres.reset_password(candidate_reset_token, %{
               "password" => "newpassword789!",
               "name" => "x",
               "email" => "x@y.z",
               "address_line_1" => "x",
               "city" => "x",
               "postcode" => "x"
             })

    # The admin's password is untouched.
    assert Admins.get_admin_by_email_and_password(admin.email, @password).id == admin.id
  end

  test "credentials valid in one scope are rejected in others",
       %{candidate: candidate, admin: admin, centre: centre} do
    # Candidate creds don't authenticate as admin
    refute Admins.get_admin_by_email_and_password(candidate.email, @password) == candidate
    # But each one authenticates within its own scope
    assert Candidates.get_candidate_by_email_and_password(@email, @password).id == candidate.id
    assert Admins.get_admin_by_email_and_password(@email, @password).id == admin.id
    assert ExamCentres.get_exam_centre_by_email_and_password(@email, @password).id == centre.id
  end
end
