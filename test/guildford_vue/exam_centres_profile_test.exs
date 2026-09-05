defmodule GuildfordVue.ExamCentresProfileTest do
  @moduledoc """
  Sprint 3 Slice 4 — centre profile self-service.

  Centres can edit their own address/contact/evidence; they cannot
  change their email (would break the auth scope) or their status
  (admin-only). Postcode changes trigger geom recompute (currently
  via the lat/lng on the changeset; Slice 5 introduces a Geocoder
  adapter so postcode alone is enough).
  """
  use GuildfordVue.DataCase, async: true

  alias GuildfordVue.ExamCentres

  setup do
    {:ok, centre} =
      ExamCentres.register_exam_centre(%{
        "email" => "profile@example.com",
        "password" => "supersecret123!A",
        "name" => "Profile Centre",
        "address_line_1" => "1 Old Street",
        "city" => "London",
        "postcode" => "EC1A 1BB",
        "latitude" => 51.52,
        "longitude" => -0.10
      })

    %{centre: centre}
  end

  describe "update_centre_profile/2" do
    test "updates editable fields", %{centre: centre} do
      assert {:ok, updated} =
               ExamCentres.update_centre_profile(centre, %{
                 "name" => "Renamed Centre",
                 "address_line_1" => "10 New Street",
                 "address_line_2" => "Suite 5",
                 "city" => "Manchester",
                 "postcode" => "M1 1AE",
                 "contact_phone" => "+441619998888",
                 "accreditation_evidence_url" => "https://evidence.example.com/cert.pdf"
               })

      assert updated.name == "Renamed Centre"
      assert updated.address_line_1 == "10 New Street"
      assert updated.address_line_2 == "Suite 5"
      assert updated.city == "Manchester"
      assert updated.postcode == "M1 1AE"
      assert updated.contact_phone == "+441619998888"
      assert updated.accreditation_evidence_url == "https://evidence.example.com/cert.pdf"
    end

    test "does NOT change email", %{centre: centre} do
      {:ok, updated} = ExamCentres.update_centre_profile(centre, %{"email" => "hijack@x.test"})
      assert updated.email == "profile@example.com"
    end

    test "does NOT change status / approval audit fields", %{centre: centre} do
      {:ok, updated} =
        ExamCentres.update_centre_profile(centre, %{
          "status" => "approved",
          "approved_at" => DateTime.utc_now()
        })

      assert updated.status == "pending"
      refute updated.approved_at
    end

    test "does NOT change password", %{centre: centre} do
      {:ok, updated} = ExamCentres.update_centre_profile(centre, %{"password" => "newpass!2345"})
      assert updated.hashed_password == centre.hashed_password
    end

    test "required fields cannot be blanked", %{centre: centre} do
      assert {:error, cs} =
               ExamCentres.update_centre_profile(centre, %{
                 "name" => "",
                 "address_line_1" => "",
                 "city" => "",
                 "postcode" => ""
               })

      errors = errors_on(cs)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.address_line_1
      assert "can't be blank" in errors.city
      assert "can't be blank" in errors.postcode
    end

    test "URL validation: rejects non-https accreditation URLs", %{centre: centre} do
      assert {:error, cs} =
               ExamCentres.update_centre_profile(centre, %{
                 "accreditation_evidence_url" => "javascript:alert(1)"
               })

      assert Enum.any?(errors_on(cs).accreditation_evidence_url, &String.contains?(&1, "http"))
    end

    test "blank accreditation URL is accepted", %{centre: centre} do
      {:ok, updated} =
        ExamCentres.update_centre_profile(centre, %{"accreditation_evidence_url" => ""})

      # Blank stored as nil
      assert updated.accreditation_evidence_url in [nil, ""]
    end
  end

  describe "change_centre_profile/2 (form helper)" do
    test "returns a changeset", %{centre: centre} do
      assert %Ecto.Changeset{} = ExamCentres.change_centre_profile(centre, %{"name" => "x"})
    end
  end
end
