# Task 1.1 — runs.js: normalizeRun and runState (card 797d9382)

Parent story: 10d626dc "Run domain model". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` ("Data sources", "Domain model"). Sibling 791537cf (1.2) builds on this file and is blocked by it.

## Scope

Create `core/domain/runs.js` with exactly two public functions, `normalizeRun(raw)` and `runState(run)`, plus their headless tests in `tests/core/domain/tst_runs.qml`. Work test-first.

The file is pure: first line `.pragma library`, no QML / `Qt*` / `Quickshell*` / `qs.*` imports, and the only allowed imports are other `core/domain/*.js` files or `vendor/canvas/*.js` (none are needed). Follow the style of `core/domain/results.js` and `milestones.js`: ES5 `function`, `var`, `String()` / `typeof` coercion with defaults for missing fields, and no throwing on bad input.

## Out of scope

- `cardRunState`, `rollup`, `attention`, `escalationReason`, `errorText`, card mapping and synthetic ids (all of these belong to 1.2 / 791537cf).
- `RunStore.qml`, the `core/backend/runs/*.py` helpers, `am` contract tests, all UI (badges, glyphs, screens), navigation, and the `docs/architecture.md` edits.

## Input shape (provisional, pinned by the tests)

The snapshot helper does not exist yet, so the input `raw` gets a defensive shape. Document it in a comment in both `runs.js` and the test file:

```
raw = {
  row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
  status: { run: {...}, rows: [...], control: { lease: { pid, host, heartbeat_at, accepting, live } }, ... } // `am status` data, may be absent
}
```

## Observable behaviour

**`normalizeRun(raw)`** always returns a plain object with these fields:

- `id`: `String(row.id)`, falling back to `status.run.id`. Default `""`.
- `repo_dir`: `row.repo_dir`, falling back to `status.run.repo_dir`. Default `""`.
- `milestone_id`: `status.run.milestone_id`, falling back to `row.milestone_id`. Default `""`.
- `status`: the `am` run status as a string. `status.run.status` wins over `row.status` because it is the fresher detail. Default `""`. The value is never taken from brd card status.
- `lease`: either `null` or `{ pid, host, heartbeat_at, accepting, live }`.
  - It is `null` when `status.control.lease` is missing or is not an object. A missing lease means not live.
  - When a lease is present, `pid`, `host` and `heartbeat_at` are copied through as given (default `""` when missing). `live` is `true` only if the source value is strictly `true`. `accepting` follows the same rule.
- `rows`: the `status.rows` array, or `[]` when that field is missing or not an array.
- `tree`: always an object `{ stories, subtasks }`. Provisionally these are the arrays at `status.stories` and `status.subtasks` (the shape is pinned by the tests, like the rest of the input). Each is passed through unchanged, with its nested phase/attempt data, so that 1.2 can read `stories[].card_id` / `subtasks[].card_id`. A missing or non-array value becomes `[]`. If the real `am status` nests them differently, the fix is confined to this one mapping in `normalizeRun`.

Bad input never throws. For `undefined`, `null` or a non-object `raw`, and for a missing `row` or `status`, the function returns the default-filled object.

**`runState(run)`** works on a normalised run and returns one string:

| `run.status` | lease | result |
|---|---|---|
| `started` | `lease.live === true` | `running` |
| `started` | not live, or `lease` null/missing | `dead` |
| `stopped` | any | `parked` |
| `escalated` | any | `escalated` |
| `cancelled` | any | `cancelled` |
| `done` | any | `done` |
| anything else (unknown, `""`, missing) or `run` null/undefined | any | `unknown` |

`unknown` is the defined safe value. It counts as neither running nor terminal, so it never turns on the liveness timer and is never shown as finished. `stale` is never returned. Lease is consulted only for `started`.

## Tests (all in tier `tests/core/domain/` — headless QtTest)

Per the placement rule in `docs/architecture.md` ("How to add" / "Tests") and the milestone spec's Testing section ("tst_runs.qml: normalisation, every run-state rule, …"), pure `core/domain/*.js` logic is tested only by `tests/core/domain/tst_runs.qml`. Its structure is `import QtQuick`, `import QtTest`, `import "../../../core/domain/runs.js" as Runs`, `TestCase { name: "DomainRuns" }`, and `tests/run.sh` discovers it automatically. Nothing goes in the stores, backend, contract or ui tiers.

1. `test_normalize_full`: a complete `row` + `status` input yields every field (`id`, `repo_dir`, `milestone_id`, `status`, `lease` with all five keys, `rows`, `tree`).
2. `test_normalize_status_prefers_am_status`: `status.run.status` overrides `row.status`, and `row.status` is used when `status` is absent.
3. `test_normalize_missing_lease`: when there is no `control` or `control.lease`, `lease` is `null`.
4. `test_normalize_lease_live_strict`: a lease with `live` missing, `"true"` or `1` gives `live === false`.
5. `test_normalize_missing_rows_tree`: missing or non-array `rows` gives `[]`, and a missing tree gives empty `stories` / `subtasks`.
6. `test_normalize_garbage`: `undefined`, `null`, `"x"` and `{}` all return the default-filled object without throwing.
7. `test_state_running`: `started` with a live lease gives `running`.
8. `test_state_dead_not_live`: `started` with `live: false` gives `dead`.
9. `test_state_dead_missing_lease`: `started` with `lease: null`, and a run built by `normalizeRun` with no lease, both give `dead`.
10. `test_state_terminal_and_parked`: `stopped` → `parked`, `escalated` → `escalated`, `cancelled` → `cancelled`, `done` → `done`, each tested with both a live lease and no lease. This shows the lease is ignored for these statuses.
11. `test_state_unknown`: `"weird"`, `""`, `"stale"`, a missing status, `null` and `undefined` all give `unknown`.

## Verification

Run `bash tests/run.sh`. It runs the full pytest suite first, including `tests/architecture/test_layers.py`, which must pass unchanged, and then every `tst_*.qml`. The QML output must contain no TypeError, ReferenceError or "is not a function" errors. For a quicker loop, use `bash tests/run.sh tst_runs`. The project has no typecheck and no lint step.
