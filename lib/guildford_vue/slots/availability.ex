defmodule GuildfordVue.Slots.Availability do
  @moduledoc """
  Slot availability ADT (PRD §4.6 / Sprint 6). Pure classifier so
  the UI render path can pattern-match exhaustively and the
  dissertation can claim the unrepresentable-invalid-state benefit.

  ADT: `:available | :limited | :fully_booked | :cancelled`.

      iex> import GuildfordVue.Slots.Availability
      iex> classify(%GuildfordVue.Slots.Slot{capacity: 10, available_count: 10, status: "open"})
      :available

  The buckets:

    * `:cancelled`    — slot.status is "cancelled" (terminal)
    * `:fully_booked` — capacity > 0 but available_count = 0
    * `:limited`      — 1 ≤ available_count ≤ 25% of capacity
    * `:available`    — available_count > 25% of capacity
  """

  alias GuildfordVue.Slots.Slot

  @type t :: :available | :limited | :fully_booked | :cancelled

  @doc "Exhaustive enumeration of every ADT variant — used by ADT-coverage tests."
  @spec all() :: [t()]
  def all, do: [:available, :limited, :fully_booked, :cancelled]

  @spec classify(Slot.t() | map()) :: t()
  def classify(%{status: "cancelled"}), do: :cancelled
  def classify(%{available_count: 0}), do: :fully_booked

  def classify(%{available_count: avail, capacity: cap})
      when is_integer(avail) and is_integer(cap) and cap > 0 do
    # 25% threshold, integer-arithmetic to keep things deterministic:
    # :limited iff avail*4 <= cap, :available otherwise.
    if avail * 4 <= cap, do: :limited, else: :available
  end

  @doc "Human-readable label for UI rendering."
  @spec label(t()) :: String.t()
  def label(:available), do: "Available"
  def label(:limited), do: "Limited"
  def label(:fully_booked), do: "Fully booked"
  def label(:cancelled), do: "Cancelled"

  @doc """
  Tailwind classes per ADT variant — the canonical mapping the
  calendar + search marker use. Centralised so the design tokens
  stay consistent across surfaces.
  """
  @spec tailwind_classes(t()) :: String.t()
  def tailwind_classes(:available), do: "bg-teal-100 text-teal-900 border-teal-300"
  def tailwind_classes(:limited), do: "bg-amber-100 text-amber-900 border-amber-300"
  def tailwind_classes(:fully_booked), do: "bg-red-100 text-red-900 border-red-300"
  def tailwind_classes(:cancelled), do: "bg-ink-100 text-ink-500 border-ink-200"
end
