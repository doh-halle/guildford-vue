defmodule GuildfordVue.Properties.Argon2PropertyTest do
  @moduledoc """
  Property tests for the password-hashing round-trip used by all three auth
  scopes. The dissertation evaluation chapter cites property-based testing as
  a methodological contribution — these tests are evidence of that.

  Invariants:
    * For any password, the hash verifies against that password.
    * For any pair of different passwords, the hash of one never verifies
      against the other (modulo astronomically improbable collisions).
    * Hashes are non-deterministic — hashing the same password twice yields
      different output (salts).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  @tag :property

  property "a password verifies against its own hash" do
    check all(password <- string(:utf8, min_length: 12, max_length: 64), max_runs: 20) do
      hash = Argon2.hash_pwd_salt(password)
      assert Argon2.verify_pass(password, hash)
    end
  end

  @tag :property
  property "two different passwords never share a verifying hash" do
    check all(
            {a, b} <-
              tuple({
                string(:utf8, min_length: 12, max_length: 32),
                string(:utf8, min_length: 12, max_length: 32)
              }),
            a != b,
            max_runs: 20
          ) do
      hash = Argon2.hash_pwd_salt(a)
      refute Argon2.verify_pass(b, hash)
    end
  end

  @tag :property
  property "hashing the same password twice yields different hashes (salting)" do
    check all(password <- string(:utf8, min_length: 12, max_length: 64), max_runs: 20) do
      h1 = Argon2.hash_pwd_salt(password)
      h2 = Argon2.hash_pwd_salt(password)
      assert h1 != h2
      assert Argon2.verify_pass(password, h1)
      assert Argon2.verify_pass(password, h2)
    end
  end
end
