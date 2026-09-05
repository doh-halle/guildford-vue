defmodule GuildfordVue.PasswordBreach.Stub do
  @moduledoc """
  Default `GuildfordVue.PasswordBreach` adapter (Sprint 11.5
  Slice 5). Returns `:ok` for every password unless the caller
  has explicitly seeded a breach via `seed_breach/2`.

  Backed by `:persistent_term` keyed under this module — fast,
  thread-safe, and survives across processes inside the same
  BEAM. Tests should call `reset/0` in their setup (or as an
  `on_exit`) so seeded breaches don't leak across cases.
  """

  @behaviour GuildfordVue.PasswordBreach

  @persistent_key {__MODULE__, :seeds}

  @impl true
  def check(password) when is_binary(password) do
    case Map.get(seeds(), password) do
      nil -> :ok
      count when is_integer(count) -> {:error, :breached, count}
    end
  end

  @doc "Mark `password` as having appeared in `count` breaches."
  @spec seed_breach(String.t(), pos_integer()) :: :ok
  def seed_breach(password, count) when is_binary(password) and is_integer(count) and count > 0 do
    :persistent_term.put(@persistent_key, Map.put(seeds(), password, count))
    :ok
  end

  @doc "Clear every seeded breach. Safe to call repeatedly."
  @spec reset() :: :ok
  def reset do
    :persistent_term.put(@persistent_key, %{})
    :ok
  end

  defp seeds, do: :persistent_term.get(@persistent_key, %{})
end
