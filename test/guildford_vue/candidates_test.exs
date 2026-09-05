defmodule GuildfordVue.CandidatesTest do
  @moduledoc """
  Tests for the `GuildfordVue.Candidates` context — the candidate auth scope.
  Hand-rolled rather than scaffolded so the schema, password hashing, email
  verification, and password-reset flows match the PRD §4.1 exactly.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.Candidates
  alias GuildfordVue.Candidates.{Candidate, CandidateToken}

  @valid_attrs %{
    "email" => "alice@example.com",
    "password" => "supersecret123!A",
    "first_name" => "Alice",
    "last_name" => "Worthington",
    "phone" => "+447700900111",
    "postcode" => "GU1 4LZ"
  }

  describe "register_candidate/1" do
    test "creates a candidate with hashed password when attrs are valid" do
      assert {:ok, %Candidate{} = candidate} = Candidates.register_candidate(@valid_attrs)
      assert candidate.email == "alice@example.com"
      assert candidate.first_name == "Alice"
      assert candidate.last_name == "Worthington"
      assert candidate.phone == "+447700900111"
      assert candidate.postcode == "GU1 4LZ"
      assert is_binary(candidate.hashed_password)
      refute candidate.hashed_password == "supersecret123!A"
      refute candidate.email_verified_at, "new candidates start unverified"
      refute candidate.suspended_at
    end

    test "lowercases the email so it can be looked up case-insensitively" do
      assert {:ok, c} =
               Candidates.register_candidate(%{@valid_attrs | "email" => "ALICE@EXAMPLE.com"})

      assert c.email == "alice@example.com"
    end

    test "returns {:error, changeset} when email is missing" do
      attrs = Map.delete(@valid_attrs, "email")
      assert {:error, changeset} = Candidates.register_candidate(attrs)
      assert "can't be blank" in errors_on(changeset).email
    end

    test "returns {:error, changeset} when email is taken" do
      assert {:ok, _} = Candidates.register_candidate(@valid_attrs)

      attrs = %{@valid_attrs | "email" => "ALICE@example.COM"}
      assert {:error, changeset} = Candidates.register_candidate(attrs)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "returns {:error, changeset} when password is too short" do
      attrs = %{@valid_attrs | "password" => "short"}
      assert {:error, changeset} = Candidates.register_candidate(attrs)
      assert Enum.any?(errors_on(changeset).password, &(&1 =~ "should be at least"))
    end

    test "returns {:error, changeset} when first_name or last_name missing" do
      attrs = Map.delete(@valid_attrs, "first_name")
      assert {:error, cs} = Candidates.register_candidate(attrs)
      assert "can't be blank" in errors_on(cs).first_name
    end
  end

  describe "get_candidate_by_email/1" do
    test "returns the candidate when email matches (case-insensitive)" do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      assert Candidates.get_candidate_by_email("ALICE@example.COM").id == candidate.id
      assert Candidates.get_candidate_by_email("alice@example.com").id == candidate.id
    end

    test "returns nil when no candidate matches" do
      refute Candidates.get_candidate_by_email("nobody@example.com")
    end
  end

  describe "get_candidate_by_email_and_password/2" do
    setup do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      %{candidate: candidate}
    end

    test "returns the candidate when password is correct", %{candidate: candidate} do
      assert Candidates.get_candidate_by_email_and_password(
               "alice@example.com",
               "supersecret123!A"
             ).id == candidate.id
    end

    test "returns nil when password is wrong" do
      refute Candidates.get_candidate_by_email_and_password(
               "alice@example.com",
               "wrong-password"
             )
    end

    test "returns nil when email doesn't exist" do
      refute Candidates.get_candidate_by_email_and_password(
               "nobody@example.com",
               "supersecret123!A"
             )
    end

    test "does not leak existence via timing — calls Argon2.no_user_verify for missing emails" do
      # If we short-circuit before hashing on missing email, an attacker can
      # distinguish "user not found" from "wrong password" by timing. Spend the
      # same CPU either way.
      {missing_time, _} =
        :timer.tc(fn ->
          Candidates.get_candidate_by_email_and_password("nobody@example.com", "x")
        end)

      {wrong_time, _} =
        :timer.tc(fn ->
          Candidates.get_candidate_by_email_and_password("alice@example.com", "wrong")
        end)

      # Both should at least run argon2; loose bound — within 4x of each other.
      assert missing_time > wrong_time / 4
    end
  end

  describe "deliver_email_verification_instructions/2 and verify_email/1" do
    test "generates a one-time token, then consumes it on verify" do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      refute candidate.email_verified_at

      assert {:ok, token} =
               Candidates.deliver_email_verification_instructions(
                 candidate,
                 fn url_token -> "url with " <> url_token end
               )

      assert is_binary(token)

      assert {:ok, verified} = Candidates.verify_email(token)
      assert verified.id == candidate.id
      assert verified.email_verified_at

      # Token is single-use — second attempt fails
      assert {:error, :invalid_token} = Candidates.verify_email(token)
    end

    test "returns :invalid_token for a bogus token" do
      assert {:error, :invalid_token} = Candidates.verify_email("not-a-real-token")
    end
  end

  describe "deliver_password_reset_instructions/2 and reset_password/2" do
    setup do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      %{candidate: candidate}
    end

    test "issues a one-time reset token and rotates the password", %{candidate: candidate} do
      assert {:ok, token} =
               Candidates.deliver_password_reset_instructions(
                 candidate,
                 fn url_token -> "reset url " <> url_token end
               )

      assert {:ok, updated} =
               Candidates.reset_password(token, %{"password" => "newpassword123!A"})

      assert updated.id == candidate.id
      refute updated.hashed_password == candidate.hashed_password

      # Token can't be reused
      assert {:error, :invalid_token} =
               Candidates.reset_password(token, %{"password" => "yetanother123!A"})

      # New password works
      assert Candidates.get_candidate_by_email_and_password(
               candidate.email,
               "newpassword123!A"
             ).id == candidate.id
    end

    test "rejects too-short passwords", %{candidate: candidate} do
      {:ok, token} =
        Candidates.deliver_password_reset_instructions(candidate, fn t -> "url " <> t end)

      assert {:error, changeset} = Candidates.reset_password(token, %{"password" => "short"})
      assert Enum.any?(errors_on(changeset).password, &(&1 =~ "should be at least"))
    end
  end

  describe "suspend/1 and reactivate/1" do
    test "stamps suspended_at, then clears it" do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      refute candidate.suspended_at

      assert {:ok, suspended} = Candidates.suspend(candidate)
      assert suspended.suspended_at

      assert {:ok, active} = Candidates.reactivate(suspended)
      refute active.suspended_at
    end

    test "suspended candidates cannot authenticate" do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      {:ok, _} = Candidates.suspend(candidate)

      refute Candidates.get_candidate_by_email_and_password(
               candidate.email,
               "supersecret123!A"
             )
    end
  end

  describe "session tokens" do
    test "generate, lookup, and revoke" do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)

      token = Candidates.generate_session_token(candidate)
      assert is_binary(token)

      found = Candidates.get_candidate_by_session_token(token)
      assert found.id == candidate.id

      :ok = Candidates.delete_session_token(token)
      refute Candidates.get_candidate_by_session_token(token)
    end

    test "tokens are scoped to the :session context" do
      {:ok, candidate} = Candidates.register_candidate(@valid_attrs)
      token = Candidates.generate_session_token(candidate)

      # A reset token is in a different context — should not be acceptable as session
      assert %CandidateToken{context: "session"} = Repo.get_by(CandidateToken, token: token)
    end
  end
end
