defmodule GuildfordVue.AuthDefensiveTest do
  @moduledoc """
  Defensive-edge tests for the three auth contexts. These pin the behaviour
  of every guard clause and `:error` branch that the happy-path tests don't
  exercise. Without these, the suite is at the mercy of the type system to
  catch malformed inputs — Dialyzer is good, but it isn't a runtime test.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.{Admins, Candidates, ExamCentres}

  # ---------------------------------------------------------------------------
  # Candidates
  # ---------------------------------------------------------------------------

  describe "Candidates defensive boundaries" do
    test "get_candidate_by_email rejects non-binary input" do
      assert is_nil(Candidates.get_candidate_by_email(nil))
    end

    test "get_candidate_by_email_and_password rejects non-binary input" do
      refute Candidates.get_candidate_by_email_and_password(nil, "x")
      refute Candidates.get_candidate_by_email_and_password("x", nil)
      refute Candidates.get_candidate_by_email_and_password(:atom, "x")
    end

    test "get_candidate_by_session_token rejects non-binary input" do
      refute Candidates.get_candidate_by_session_token(nil)
      refute Candidates.get_candidate_by_session_token(:atom)
    end

    test "verify_email rejects non-binary token" do
      assert {:error, :invalid_token} = Candidates.verify_email(nil)
      assert {:error, :invalid_token} = Candidates.verify_email(:atom)
    end

    test "verify_email rejects a syntactically invalid base64 token" do
      # not-base64-decodable string -> the :error branch in by_hashed_token_query
      assert {:error, :invalid_token} = Candidates.verify_email("!!!!not-base64!!!!")
    end

    test "reset_password rejects non-binary token" do
      assert {:error, :invalid_token} = Candidates.reset_password(nil, %{})
      assert {:error, :invalid_token} = Candidates.reset_password(:atom, %{})
    end

    test "reset_password rejects a malformed base64 token" do
      assert {:error, :invalid_token} = Candidates.reset_password("!!!", %{"password" => "x"})
    end
  end

  # ---------------------------------------------------------------------------
  # Admins
  # ---------------------------------------------------------------------------

  describe "Admins defensive boundaries" do
    test "get_admin_by_email rejects nil" do
      assert is_nil(Admins.get_admin_by_email(nil))
    end

    test "get_admin_by_email_and_password rejects non-binary input" do
      refute Admins.get_admin_by_email_and_password(nil, "x")
      refute Admins.get_admin_by_email_and_password("x", nil)
      refute Admins.get_admin_by_email_and_password(:atom, :atom)
    end

    test "get_admin_by_session_token rejects non-binary input" do
      refute Admins.get_admin_by_session_token(nil)
      refute Admins.get_admin_by_session_token(:atom)
    end

    test "reset_password rejects non-binary token" do
      assert {:error, :invalid_token} = Admins.reset_password(nil, %{})
      assert {:error, :invalid_token} = Admins.reset_password(:atom, %{})
    end

    test "reset_password rejects a malformed base64 token" do
      assert {:error, :invalid_token} = Admins.reset_password("!!!", %{"password" => "x"})
    end
  end

  # ---------------------------------------------------------------------------
  # ExamCentres
  # ---------------------------------------------------------------------------

  describe "ExamCentres defensive boundaries" do
    test "get_exam_centre_by_email rejects nil" do
      assert is_nil(ExamCentres.get_exam_centre_by_email(nil))
    end

    test "get_exam_centre_by_email_and_password rejects non-binary input" do
      refute ExamCentres.get_exam_centre_by_email_and_password(nil, "x")
      refute ExamCentres.get_exam_centre_by_email_and_password("x", nil)
      refute ExamCentres.get_exam_centre_by_email_and_password(:atom, :atom)
    end

    test "get_exam_centre_by_session_token rejects non-binary input" do
      refute ExamCentres.get_exam_centre_by_session_token(nil)
      refute ExamCentres.get_exam_centre_by_session_token(:atom)
    end

    test "reset_password rejects non-binary token" do
      assert {:error, :invalid_token} = ExamCentres.reset_password(nil, %{})
      assert {:error, :invalid_token} = ExamCentres.reset_password(:atom, %{})
    end

    test "reset_password rejects a malformed base64 token" do
      assert {:error, :invalid_token} = ExamCentres.reset_password("!!!", %{"password" => "x"})
    end

    test "reactivate refuses non-suspended centres" do
      {:ok, c} =
        ExamCentres.register_exam_centre(%{
          "email" => "centre@example.com",
          "password" => "supersecret123!A",
          "name" => "Centre",
          "address_line_1" => "1 The Road",
          "city" => "Bristol",
          "postcode" => "BS1 4DJ"
        })

      # pending → cannot reactivate (only suspended → approved)
      assert {:error, :not_suspended} = ExamCentres.reactivate(c)
    end

    test "approve refuses suspended centres" do
      {:ok, admin} =
        Admins.register_admin(%{
          "email" => "approver@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      {:ok, pending} =
        ExamCentres.register_exam_centre(%{
          "email" => "centre@example.com",
          "password" => "supersecret123!A",
          "name" => "Centre",
          "address_line_1" => "1 The Road",
          "city" => "Bristol",
          "postcode" => "BS1 4DJ"
        })

      {:ok, approved} = ExamCentres.approve(pending, admin)
      {:ok, suspended} = ExamCentres.suspend(approved)

      assert {:error, :cannot_approve_suspended} = ExamCentres.approve(suspended, admin)
    end
  end
end
