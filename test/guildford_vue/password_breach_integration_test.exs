defmodule GuildfordVue.PasswordBreachIntegrationTest do
  @moduledoc """
  Sprint 11.5 Slice 5 — schema-side wiring of the breached-password
  check. Pins that each of the three scope schemas rejects a seeded
  breached password during registration AND during password reset.
  """
  use GuildfordVue.DataCase, async: false

  alias GuildfordVue.{Admins, Candidates, ExamCentres}
  alias GuildfordVue.PasswordBreach.Stub

  setup do
    Stub.reset()
    on_exit(&Stub.reset/0)
    :ok
  end

  defp seeded_breach do
    pw = "BreachedPassword#{System.unique_integer([:positive])}!"
    Stub.seed_breach(pw, 42)
    pw
  end

  defp safe_password, do: "freshUniquePass#{System.unique_integer([:positive])}!"

  describe "candidate registration" do
    test "rejects a seeded breached password with a :breached_password error" do
      cs =
        Candidates.change_registration(%{
          "email" => "alice-#{System.unique_integer([:positive])}@example.com",
          "password" => seeded_breach(),
          "first_name" => "A",
          "last_name" => "X"
        })

      assert {_msg, opts} = cs.errors[:password]
      assert opts[:validation] == :breached_password
      assert opts[:count] == 42
    end

    test "accepts a non-breached password" do
      {:ok, _} =
        Candidates.register_candidate(%{
          "email" => "fresh-#{System.unique_integer([:positive])}@example.com",
          "password" => safe_password(),
          "first_name" => "Fresh",
          "last_name" => "X"
        })
    end
  end

  describe "admin registration" do
    test "rejects a seeded breached password" do
      breached = seeded_breach()

      {:error, cs} =
        Admins.register_admin(%{
          "email" => "ab-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => breached,
          "name" => "X",
          "role" => "operator"
        })

      assert {_msg, opts} = cs.errors[:password]
      assert opts[:validation] == :breached_password
    end
  end

  describe "exam-centre registration" do
    test "rejects a seeded breached password" do
      breached = seeded_breach()

      {:error, cs} =
        ExamCentres.register_exam_centre(%{
          "email" => "bc-#{System.unique_integer([:positive])}@example.com",
          "password" => breached,
          "name" => "Centre",
          "address_line_1" => "1 St",
          "city" => "Bath",
          "postcode" => "BA1 1LT"
        })

      assert {_msg, opts} = cs.errors[:password]
      assert opts[:validation] == :breached_password
    end
  end

  describe "candidate password reset" do
    test "rejects a seeded breached password as the new password" do
      {:ok, candidate} =
        Candidates.register_candidate(%{
          "email" => "reset-#{System.unique_integer([:positive])}@example.com",
          "password" => safe_password(),
          "first_name" => "R",
          "last_name" => "X"
        })

      {:ok, token} = Candidates.deliver_password_reset_instructions(candidate, fn t -> t end)

      assert {:error, cs} = Candidates.reset_password(token, %{"password" => seeded_breach()})

      assert {_msg, opts} = cs.errors[:password]
      assert opts[:validation] == :breached_password
    end
  end
end
