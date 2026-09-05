defmodule Mix.Tasks.GuildfordVue.Seed.ExamsTest do
  @moduledoc """
  Sprint 3 Slice 2 — UK exam catalogue seed.

  The seed task is idempotent (running it twice doesn't duplicate),
  inserts every exam in `GuildfordVue.Exams.Catalogue.uk_catalogue/0`,
  and uses a system admin so the audit log records *something* as the
  actor even though no human ran the action.
  """
  use GuildfordVue.DataCase, async: false
  alias GuildfordVue.{Admins, Exams}
  alias GuildfordVue.Exams.Catalogue

  setup do
    {:ok, _} =
      Admins.register_admin(%{
        "email" => "system+seed@guildfordvue.test",
        "password" => "supersecret123!A",
        "name" => "System Seed",
        "role" => "superadmin"
      })

    :ok
  end

  describe "Catalogue.uk_catalogue/0" do
    test "covers the six PRD §12.2 categories" do
      cat = Catalogue.uk_catalogue()
      bodies = cat |> Enum.map(& &1.certification_body) |> Enum.uniq()

      # Spot-check known certification bodies from PRD §12.2.
      for expected <- ["DVSA", "AQA", "Edexcel", "OCR", "CompTIA", "Microsoft", "AWS"] do
        assert expected in bodies, "expected certification body #{expected} in catalogue"
      end
    end

    test "every entry has the required fields" do
      for entry <- Catalogue.uk_catalogue() do
        assert is_binary(entry.code) and entry.code != ""
        assert is_binary(entry.name) and entry.name != ""
        assert is_binary(entry.certification_body) and entry.certification_body != ""
        assert is_integer(entry.duration_minutes) and entry.duration_minutes > 0
        assert is_integer(entry.price_pence) and entry.price_pence >= 0
      end
    end

    test "codes are unique" do
      codes = Catalogue.uk_catalogue() |> Enum.map(& &1.code)
      assert length(codes) == length(Enum.uniq(codes))
    end

    test "has at least 30 entries (PRD §12.2 lists ~35)" do
      assert length(Catalogue.uk_catalogue()) >= 30
    end
  end

  describe "seed_catalogue/0" do
    test "inserts every catalogue entry" do
      {inserted, skipped} = Catalogue.seed_catalogue()
      assert inserted == length(Catalogue.uk_catalogue())
      assert skipped == 0

      for entry <- Catalogue.uk_catalogue() do
        assert Exams.get_exam_by_code(entry.code)
      end
    end

    test "running twice is idempotent (skips, doesn't duplicate)" do
      {inserted_a, _} = Catalogue.seed_catalogue()
      {inserted_b, skipped_b} = Catalogue.seed_catalogue()
      assert inserted_b == 0
      assert skipped_b == inserted_a
    end
  end
end
