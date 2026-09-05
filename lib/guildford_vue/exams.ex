defmodule GuildfordVue.Exams do
  @moduledoc """
  Exam catalogue context (PRD §4.4 admin domain). Admins manage the
  master list; centres pick from it via `exam_centre_exams` (Slice 6).
  Every state change writes an audit-log event with the acting admin
  as the actor.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias GuildfordVue.Admins.Admin
  alias GuildfordVue.AuditLog
  alias GuildfordVue.Exams.Exam
  alias GuildfordVue.Repo

  @type result(t) :: {:ok, t} | {:error, Ecto.Changeset.t() | atom()}

  @spec create_exam(map(), Admin.t()) :: result(Exam.t())
  def create_exam(attrs, %Admin{} = admin) do
    Multi.new()
    |> Multi.insert(:exam, Exam.create_changeset(%Exam{}, attrs))
    |> Multi.run(:audit, fn _repo, %{exam: e} ->
      AuditLog.append(:exam_created, %{
        aggregate_id: e.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{code: e.code, name: e.name}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{exam: e}} -> {:ok, e}
      {:error, :exam, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @spec update_exam(Exam.t(), map(), Admin.t()) :: result(Exam.t())
  def update_exam(%Exam{} = exam, attrs, %Admin{} = admin) do
    changeset = Exam.update_changeset(exam, attrs)

    if changeset.changes == %{} do
      # No-op: skip the audit event entirely — we record decisions, not
      # form-submits.
      {:ok, exam}
    else
      Multi.new()
      |> Multi.update(:exam, changeset)
      |> Multi.run(:audit, fn _repo, %{exam: e} ->
        AuditLog.append(:exam_updated, %{
          aggregate_id: e.id,
          actor: %{id: admin.id, type: "admin"},
          payload: %{code: e.code, changes: Map.keys(changeset.changes)}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{exam: e}} -> {:ok, e}
        {:error, :exam, %Ecto.Changeset{} = cs, _} -> {:error, cs}
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  @spec archive_exam(Exam.t(), Admin.t()) :: result(Exam.t())
  def archive_exam(%Exam{archived_at: nil} = exam, %Admin{} = admin) do
    Multi.new()
    |> Multi.update(:exam, Exam.archive_changeset(exam, DateTime.utc_now()))
    |> Multi.run(:audit, fn _repo, %{exam: e} ->
      AuditLog.append(:exam_archived, %{
        aggregate_id: e.id,
        actor: %{id: admin.id, type: "admin"},
        payload: %{code: e.code, name: e.name}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{exam: e}} -> {:ok, e}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def archive_exam(%Exam{}, _admin), do: {:error, :already_archived}

  @spec get_exam!(binary()) :: Exam.t()
  def get_exam!(id), do: Repo.get!(Exam, id)

  @spec get_exam_by_code(String.t() | nil) :: Exam.t() | nil
  def get_exam_by_code(nil), do: nil

  def get_exam_by_code(code) when is_binary(code) do
    Repo.get_by(Exam, code: code |> String.trim() |> String.upcase())
  end

  @doc """
  List exams. Options:
    * `:include_archived` — default false
    * `:search` — ILIKE on name or code
    * `:limit` — default 200
  """
  @spec list_exams(keyword()) :: [Exam.t()]
  def list_exams(opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 200)

    Exam
    |> maybe_exclude_archived(include_archived)
    |> maybe_search(search)
    |> order_by([e], asc: e.name)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_exclude_archived(query, true), do: query
  defp maybe_exclude_archived(query, false), do: from(e in query, where: is_nil(e.archived_at))

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"
    from e in query, where: ilike(e.name, ^pattern) or ilike(e.code, ^pattern)
  end

  @spec change_exam(Exam.t(), map()) :: Ecto.Changeset.t()
  def change_exam(%Exam{} = exam, attrs \\ %{}), do: Exam.create_changeset(exam, attrs)
end
