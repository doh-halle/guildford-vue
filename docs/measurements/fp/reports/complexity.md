# FP reference — static-analysis report

Generated 2026-08-01 23:07:50.007945Z UTC. Rerun via `mix run scripts/report_complexity.exs`.

## Scope

Source directories: `lib/guildford_vue` (functional core) and
`lib/guildford_vue_web` (imperative shell). Tests, migrations,
seeds, and deps are excluded — the C5 comparison against the OO
artefact is per-domain-module, not per-fixture.

## LOC / files / modules

| Directory | Files | Modules | Lines |
|-----------|-------|---------|-------|
| `lib/guildford_vue` | 73 | 72 | 7942 |
    | `lib/guildford_vue_web` | 69 | 70 | 10460 |

Total: 142 files, 142 modules, 18402 lines.

## Cyclomatic complexity (Credo default threshold = 9)

Every function with CC ≥ 9 is listed. Reported via
`mix credo --only Credo.Check.Refactor.CyclomaticComplexity`; that
invocation uses Credo's built-in `max_complexity: 9` — the CLI has
no threshold override. If a future dissertation cite needs a lower
threshold, add a `.credo.threshold-N.exs` and pass
`--config-file <file>` to the credo invocation
(Sprint 13 Defect 023 closure).

No function exceeds CC 9 — the codebase's highest complexity is under the review-flag bar.

## Strict Credo audit

`mix credo --strict` — total issues: **1**.

| Count | Check |
|-------|-------|
| 1 | `Credo.Check.Readability.AliasOrder` |


## Notes

- No function exceeds Credo's default `max_complexity: 9`. Credo's CLI has no threshold override; to survey below that bar, see the `.credo.threshold-N.exs` workaround called out in the Cyclomatic-complexity section (Sprint 13 Defect 023 closure).
- Imperative shell (`lib/guildford_vue_web`, 10460 lines) vs functional core (`lib/guildford_vue`, 7942 lines): shell/core ratio = 1.32. The FP-idiomatic shape is shell < core — a ratio > 1 warrants a review flag.
