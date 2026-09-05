defmodule GuildfordVue.ExamCentres.ExamCentreExam do
  @moduledoc """
  Join row between a centre and an exam in the catalogue. The
  presence of the row is the entire fact — there's no per-offering
  metadata at this layer (price overrides land in Sprint 4 with
  the Slot model). Add/remove operations are surfaced via audit
  events on the centre as the aggregate.
  """
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "exam_centre_exams" do
    field :exam_centre_id, :binary_id
    field :exam_id, :binary_id
    field :inserted_at, :utc_datetime_usec
  end
end
