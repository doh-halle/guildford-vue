defmodule GuildfordVue.ExamCentresTest do
  @moduledoc """
  Tests for the `GuildfordVue.ExamCentres` context — the exam centre auth
  scope. Centre-specific behaviours not present in Candidates/Admins:

    * Self-registration lands in `:pending` status; cannot log in until an
      admin approves.
    * Address fields + lat/lng + PostGIS `geom` populated from lat/lng on
      save (Sprint 5 uses `ST_DWithin` for proximity search).
    * status ADT: `:pending | :approved | :suspended` — exhaustively
      pattern-matched in the context.
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.ExamCentres
  alias GuildfordVue.ExamCentres.{ExamCentre, ExamCentreToken}

  @valid_attrs %{
    "email" => "manchester-exam-hub@example.com",
    "password" => "supersecret123!A",
    "name" => "Manchester Examination Hub",
    "address_line_1" => "12 Deansgate",
    "city" => "Manchester",
    "postcode" => "M1 1AE",
    "latitude" => 53.4794,
    "longitude" => -2.2453,
    "contact_phone" => "+441619998888"
  }

  describe "register_exam_centre/1" do
    test "creates a centre with status :pending" do
      assert {:ok, %ExamCentre{} = centre} = ExamCentres.register_exam_centre(@valid_attrs)
      assert centre.status == "pending"
      assert centre.name == "Manchester Examination Hub"
      assert centre.postcode == "M1 1AE"
      refute centre.approved_at
      refute centre.approved_by_admin_id
    end

    test "populates the geom field from lat/lng" do
      {:ok, centre} = ExamCentres.register_exam_centre(@valid_attrs)
      assert %Geo.Point{coordinates: {-2.2453, 53.4794}, srid: 4326} = centre.geom
    end

    test "is invalid without an address" do
      attrs = Map.delete(@valid_attrs, "address_line_1")
      assert {:error, cs} = ExamCentres.register_exam_centre(attrs)
      assert "can't be blank" in errors_on(cs).address_line_1
    end

    test "is invalid without a postcode" do
      attrs = Map.delete(@valid_attrs, "postcode")
      assert {:error, cs} = ExamCentres.register_exam_centre(attrs)
      assert "can't be blank" in errors_on(cs).postcode
    end
  end

  describe "approve/2 (admin -> centre)" do
    setup do
      {:ok, centre} = ExamCentres.register_exam_centre(@valid_attrs)

      {:ok, admin} =
        GuildfordVue.Admins.register_admin(%{
          "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      %{centre: centre, admin: admin}
    end

    test "flips status to :approved and records approver", %{centre: centre, admin: admin} do
      assert {:ok, approved} = ExamCentres.approve(centre, admin)
      assert approved.status == "approved"
      assert approved.approved_at
      assert approved.approved_by_admin_id == admin.id
    end

    test "an already-approved centre is rejected idempotently", %{centre: centre, admin: admin} do
      {:ok, _} = ExamCentres.approve(centre, admin)
      reloaded = ExamCentres.get_exam_centre!(centre.id)
      assert {:error, :already_approved} = ExamCentres.approve(reloaded, admin)
    end
  end

  describe "authenticate (pending centres cannot log in)" do
    setup do
      {:ok, centre} = ExamCentres.register_exam_centre(@valid_attrs)

      {:ok, admin} =
        GuildfordVue.Admins.register_admin(%{
          "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      %{centre: centre, admin: admin}
    end

    test "rejects pending centres at the login boundary", %{centre: centre} do
      refute ExamCentres.get_exam_centre_by_email_and_password(
               centre.email,
               "supersecret123!A"
             )
    end

    test "accepts approved centres", %{centre: centre, admin: admin} do
      {:ok, _} = ExamCentres.approve(centre, admin)

      assert ExamCentres.get_exam_centre_by_email_and_password(
               centre.email,
               "supersecret123!A"
             ).id == centre.id
    end

    test "rejects suspended centres", %{centre: centre, admin: admin} do
      {:ok, approved} = ExamCentres.approve(centre, admin)
      {:ok, _} = ExamCentres.suspend(approved)

      refute ExamCentres.get_exam_centre_by_email_and_password(
               centre.email,
               "supersecret123!A"
             )
    end
  end

  describe "session tokens" do
    test "approved centres get tokens" do
      {:ok, centre} = ExamCentres.register_exam_centre(@valid_attrs)

      {:ok, admin} =
        GuildfordVue.Admins.register_admin(%{
          "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      {:ok, approved} = ExamCentres.approve(centre, admin)

      token = ExamCentres.generate_session_token(approved)
      assert ExamCentres.get_exam_centre_by_session_token(token).id == approved.id

      :ok = ExamCentres.delete_session_token(token)
      refute ExamCentres.get_exam_centre_by_session_token(token)

      assert is_nil(Repo.get_by(ExamCentreToken, token: token))
    end
  end

  describe "deliver_password_reset_instructions/2 and reset_password/2" do
    setup do
      {:ok, admin} =
        GuildfordVue.Admins.register_admin(%{
          "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      {:ok, pending} = ExamCentres.register_exam_centre(@valid_attrs)
      {:ok, approved} = ExamCentres.approve(pending, admin)

      %{centre: approved, admin: admin}
    end

    test "rotates the hash without altering centre status, address, or approver",
         %{centre: centre} do
      {:ok, token} =
        ExamCentres.deliver_password_reset_instructions(centre, fn t -> "url " <> t end)

      assert {:ok, updated} =
               ExamCentres.reset_password(token, %{"password" => "newpassword789!A"})

      assert updated.id == centre.id
      assert updated.status == "approved"
      assert updated.approved_at == centre.approved_at
      assert updated.approved_by_admin_id == centre.approved_by_admin_id
      assert updated.name == centre.name
      assert updated.address_line_1 == centre.address_line_1
      refute updated.hashed_password == centre.hashed_password

      # single-use
      assert {:error, :invalid_token} =
               ExamCentres.reset_password(token, %{"password" => "yetanother789!B"})

      # new password authenticates
      assert ExamCentres.get_exam_centre_by_email_and_password(
               centre.email,
               "newpassword789!A"
             ).id == centre.id
    end

    test "preserves :suspended status across reset", %{centre: centre} do
      {:ok, suspended} = ExamCentres.suspend(centre)

      {:ok, token} =
        ExamCentres.deliver_password_reset_instructions(suspended, fn t -> "url " <> t end)

      assert {:ok, updated} =
               ExamCentres.reset_password(token, %{"password" => "newpassword789!A"})

      assert updated.status == "suspended"
    end

    test "rejects short passwords without consuming the token", %{centre: centre} do
      {:ok, token} =
        ExamCentres.deliver_password_reset_instructions(centre, fn t -> "url " <> t end)

      assert {:error, %Ecto.Changeset{}} =
               ExamCentres.reset_password(token, %{"password" => "short"})

      # Token still valid because the password was rejected
      assert {:ok, _} =
               ExamCentres.reset_password(token, %{"password" => "newpassword789!A"})
    end
  end

  describe "authenticate/2 (status-aware login dispatch — defect 002 1c fix)" do
    setup do
      {:ok, admin} =
        GuildfordVue.Admins.register_admin(%{
          "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      {:ok, pending} = ExamCentres.register_exam_centre(@valid_attrs)
      {:ok, approved} = ExamCentres.approve(pending, admin)

      %{admin: admin, pending: pending, approved: approved}
    end

    test "{:ok, centre} when approved and password matches", %{approved: c} do
      assert {:ok, returned} =
               ExamCentres.authenticate("manchester-exam-hub@example.com", "supersecret123!A")

      assert returned.id == c.id
    end

    test "{:error, :pending} when status is pending and password matches" do
      {:ok, _pending} =
        ExamCentres.register_exam_centre(%{
          @valid_attrs
          | "email" => "leeds@example.com",
            "name" => "Leeds Centre",
            "postcode" => "LS1 1UR"
        })

      assert {:error, :pending} =
               ExamCentres.authenticate("leeds@example.com", "supersecret123!A")
    end

    test "{:error, :invalid} on wrong password (approved centre)", %{approved: c} do
      assert {:error, :invalid} = ExamCentres.authenticate(c.email, "wrong-password")
    end

    test "{:error, :invalid} on missing email (and Argon2.no_user_verify is called)" do
      # The no-user-verify call is timing-mostly-similar to a real Argon2.verify
      # — we don't time-assert here (that would be flaky in CI), but we DO
      # ensure the result is correct.
      assert {:error, :invalid} =
               ExamCentres.authenticate("nobody@example.com", "supersecret123!A")
    end

    test "{:error, :invalid} on SUSPENDED centre (no leak of suspended state)",
         %{approved: c} do
      {:ok, _} = ExamCentres.suspend(c)
      assert {:error, :invalid} = ExamCentres.authenticate(c.email, "supersecret123!A")
    end

    test "{:error, :invalid} on non-binary inputs (defensive fallthrough)" do
      assert {:error, :invalid} = ExamCentres.authenticate(nil, "supersecret123!A")
      assert {:error, :invalid} = ExamCentres.authenticate("manchester-exam-hub@example.com", nil)
      assert {:error, :invalid} = ExamCentres.authenticate(:atom, :atom)
    end
  end

  describe "list_pending_centres/0" do
    test "returns only :pending centres in registration order" do
      {:ok, first} = ExamCentres.register_exam_centre(@valid_attrs)

      {:ok, _second} =
        ExamCentres.register_exam_centre(%{
          @valid_attrs
          | "email" => "leeds@example.com",
            "name" => "Leeds Test Centre",
            "postcode" => "LS1 1UR"
        })

      {:ok, admin} =
        GuildfordVue.Admins.register_admin(%{
          "email" => "approver-#{System.unique_integer([:positive])}@guildfordvue.test",
          "password" => "supersecret123!A",
          "name" => "Approver"
        })

      {:ok, _} = ExamCentres.approve(first, admin)

      pending = ExamCentres.list_pending_centres()
      assert length(pending) == 1
      assert hd(pending).name == "Leeds Test Centre"
    end
  end
end
