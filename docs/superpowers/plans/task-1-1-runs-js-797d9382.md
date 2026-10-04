<!-- task-pipeline: validated -->
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

---

# runs.js normalizeRun and runState Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure run domain file `core/domain/runs.js` with `normalizeRun(raw)` (turns an `am runs` row plus `am status` data into one defaulted run object) and `runState(run)` (maps a normalised run to running/dead/parked/escalated/cancelled/done/unknown), driven test-first by `tests/core/domain/tst_runs.qml`.

**Architecture:** One new `.pragma library` JS file in `core/domain/` with no imports. Both functions are total: they never throw and fill defaults for anything missing or malformed. Private helpers are nested inside `normalizeRun` so the library exposes exactly two top-level functions. Tests are one headless QtTest file in the domain tier, auto-discovered by `tests/run.sh`.

**Tech Stack:** QML JavaScript library (ES5 style: `function`, `var`), Qt 6 QtTest via `qmltestrunner` (offscreen), pytest for the architecture rules.

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382/docs/superpowers/specs/task-1-1-runs-js-797d9382-design.md` (prepended above).

**Working directory for every command:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382` (branch `mon/task-1-1-runs-js-797d9382`, cut fresh from `origin/main`; no other subtask's code exists here, and `core/domain/runs.js` does not exist yet).

## Global Constraints

- `core/domain/runs.js` first line is exactly `.pragma library`.
- `core/domain/runs.js` has no `import` / `.import` lines at all (no QML, `Qt*`, `Quickshell*`, `qs.*`; domain imports would be allowed by `tests/architecture/test_layers.py` `violations_domain` but none are needed).
- ES5 style matching `core/domain/results.js` and `core/domain/milestones.js`: `function`, `var`, no arrow functions, no `let`/`const`.
- Exactly two top-level (public) functions: `normalizeRun(raw)` and `runState(run)`. Helpers are nested inside `normalizeRun`.
- Neither function ever throws, for any input.
- Run status comes only from `am` (`status.run.status`, then `row.status`); never from brd card status.
- `runState` never returns `stale`; it consults the lease only when status is `started`; for anything not in the table it returns `unknown`.
- No UI glyphs, no stores, no backend scripts, no contract/ui tests, no `docs/architecture.md` edits. Only two files change: `core/domain/runs.js` and `tests/core/domain/tst_runs.qml`.
- `tests/architecture/test_layers.py` must pass unchanged.
- Verification: `bash tests/run.sh` (no typecheck, no lint).

## Review Focus

- An empty `status.run.status` (`""`, e.g. a half-written `am status`) should fall back to `row.status`, not blank the status; pinned in Task 1 `test_normalize_status_prefers_am_status`.
- A numeric `row.id` (e.g. `7`) should normalise to the string `"7"`, and a missing row should take `id`/`repo_dir` from `status.run`; pinned in Task 1 `test_normalize_ids_fallback_and_coercion`.
- A lease that is present but malformed (`null`, a string, an array) should be treated as missing (`lease === null`), not as a lease object with blank fields; pinned in Task 1 `test_normalize_missing_lease`.
- A sloppy serializer sending `live: "true"` must not make a run look alive: `runState` of such a normalised run is `dead`; pinned in Task 2 `test_state_dead_not_live`.
- Case variants such as `"STARTED"` or `"Done"`, and a non-object `run` such as `"x"`, should give `unknown` rather than being guessed at; pinned in Task 2 `test_state_unknown`.

---

### Task 1: normalizeRun

**Files:**
- Create: `tests/core/domain/tst_runs.qml`
- Create: `core/domain/runs.js`

**Interfaces:**
- Consumes: nothing (first task; `core/domain/runs.js` does not exist yet).
- Produces: `normalizeRun(raw) -> { id: string, repo_dir: string, milestone_id: string, status: string, lease: null | { pid, host, heartbeat_at, accepting: bool, live: bool }, rows: Array, tree: { stories: Array, subtasks: Array } }`. Task 2's `runState` reads `run.status` and `run.lease.live` from this shape. Test helper functions `fullRaw()` and `checkDefaults(r)` inside the `TestCase` are reused by Task 2's tests.

- [ ] **Step 1: Write the failing test**

Create `tests/core/domain/tst_runs.qml` with exactly this content:

```qml
// tests/core/domain/tst_runs.qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

// Input shape for Runs.normalizeRun (provisional until the runs-snapshot helper exists):
//   raw = {
//     row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
//     status: { run: {...}, rows: [...], stories: [...], subtasks: [...],
//               control: { lease: { pid, host, heartbeat_at, accepting, live } }, ... }  // `am status` data, may be absent
//   }
TestCase {
  name: "DomainRuns"

  function fullRaw() {
    return {
      row: { id: "r1", workflow: "orchestrator", repo_dir: "/home/u/repo", base_branch: "main",
             branch_prefix: "mon/", status: "started", started_at: "2026-10-03T10:00:00Z" },
      status: {
        run: { id: "r1", repo_dir: "/home/u/repo", milestone_id: "m-4bf4", status: "started" },
        rows: [{ card_id: "c1", phase: "implement" }],
        stories: [{ card_id: "s1", subtasks: [] }],
        subtasks: [{ card_id: "c1", phases: [{ name: "implement", attempts: [] }] }],
        control: { lease: { pid: 4242, host: "box", heartbeat_at: "2026-10-03T10:05:00Z",
                            accepting: true, live: true } },
        requests: [],
        claims: []
      }
    }
  }

  function checkDefaults(r, label) {
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,status,tree", label)
    compare(r.id, "", label)
    compare(r.repo_dir, "", label)
    compare(r.milestone_id, "", label)
    compare(r.status, "", label)
    compare(r.lease, null, label)
    compare(Array.isArray(r.rows), true, label)
    compare(r.rows.length, 0, label)
    compare(Array.isArray(r.tree.stories), true, label)
    compare(r.tree.stories.length, 0, label)
    compare(Array.isArray(r.tree.subtasks), true, label)
    compare(r.tree.subtasks.length, 0, label)
  }

  function test_normalize_full() {
    var r = Runs.normalizeRun(fullRaw())
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,status,tree")
    compare(r.id, "r1")
    compare(r.repo_dir, "/home/u/repo")
    compare(r.milestone_id, "m-4bf4")
    compare(r.status, "started")
    compare(Object.keys(r.lease).sort().join(","), "accepting,heartbeat_at,host,live,pid")
    compare(r.lease.pid, 4242)
    compare(r.lease.host, "box")
    compare(r.lease.heartbeat_at, "2026-10-03T10:05:00Z")
    compare(r.lease.accepting, true)
    compare(r.lease.live, true)
    compare(r.rows.length, 1)
    compare(r.rows[0].card_id, "c1")
    compare(r.tree.stories.length, 1)
    compare(r.tree.stories[0].card_id, "s1")
    compare(r.tree.subtasks.length, 1)
    compare(r.tree.subtasks[0].card_id, "c1")
    compare(r.tree.subtasks[0].phases[0].name, "implement")
  }

  function test_normalize_status_prefers_am_status() {
    var raw = fullRaw()
    raw.row.status = "stopped"
    raw.status.run.status = "done"
    compare(Runs.normalizeRun(raw).status, "done")

    compare(Runs.normalizeRun({ row: { id: "r1", status: "stopped" } }).status, "stopped")

    var noRun = fullRaw()
    noRun.row.status = "escalated"
    delete noRun.status.run
    compare(Runs.normalizeRun(noRun).status, "escalated")

    // An empty am-status value is not fresher detail: fall back to the row.
    var blank = fullRaw()
    blank.row.status = "stopped"
    blank.status.run.status = ""
    compare(Runs.normalizeRun(blank).status, "stopped")
  }

  function test_normalize_ids_fallback_and_coercion() {
    compare(Runs.normalizeRun({ row: { id: 7 } }).id, "7")

    var fromStatus = Runs.normalizeRun({ status: { run: { id: "r9", repo_dir: "/r", milestone_id: "m9" } } })
    compare(fromStatus.id, "r9")
    compare(fromStatus.repo_dir, "/r")
    compare(fromStatus.milestone_id, "m9")

    compare(Runs.normalizeRun({ row: { milestone_id: "m1" } }).milestone_id, "m1")
    compare(Runs.normalizeRun({ row: { milestone_id: "m1" }, status: { run: { milestone_id: "m2" } } }).milestone_id, "m2")

    var rowWins = Runs.normalizeRun({ row: { id: "a", repo_dir: "/a" }, status: { run: { id: "b", repo_dir: "/b" } } })
    compare(rowWins.id, "a")
    compare(rowWins.repo_dir, "/a")
  }

  function test_normalize_missing_lease() {
    var noControl = fullRaw()
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).lease, null, "no control")

    var cases = [
      { label: "empty control", control: {} },
      { label: "null control", control: null },
      { label: "null lease", control: { lease: null } },
      { label: "string lease", control: { lease: "yes" } },
      { label: "array lease", control: { lease: [] } }
    ]
    for (var i = 0; i < cases.length; i++) {
      var raw = fullRaw()
      raw.status.control = cases[i].control
      compare(Runs.normalizeRun(raw).lease, null, cases[i].label)
    }

    compare(Runs.normalizeRun({ row: { id: "r1", status: "started" } }).lease, null, "no status at all")
  }

  function test_normalize_lease_live_strict() {
    var empty = fullRaw()
    empty.status.control.lease = {}
    var e = Runs.normalizeRun(empty).lease
    compare(e.live, false)
    compare(e.accepting, false)
    compare(e.pid, "")
    compare(e.host, "")
    compare(e.heartbeat_at, "")

    var stringy = fullRaw()
    stringy.status.control.lease = { live: "true", accepting: "true" }
    compare(Runs.normalizeRun(stringy).lease.live, false)
    compare(Runs.normalizeRun(stringy).lease.accepting, false)

    var numeric = fullRaw()
    numeric.status.control.lease = { live: 1, accepting: 1 }
    compare(Runs.normalizeRun(numeric).lease.live, false)
    compare(Runs.normalizeRun(numeric).lease.accepting, false)
  }

  function test_normalize_missing_rows_tree() {
    var bare = Runs.normalizeRun({ status: { run: { status: "started" } } })
    compare(Array.isArray(bare.rows), true)
    compare(bare.rows.length, 0)
    compare(bare.tree.stories.length, 0)
    compare(bare.tree.subtasks.length, 0)

    var raw = fullRaw()
    raw.status.rows = { a: 1 }
    raw.status.stories = {}
    raw.status.subtasks = "x"
    var r = Runs.normalizeRun(raw)
    compare(Array.isArray(r.rows), true)
    compare(r.rows.length, 0)
    compare(Array.isArray(r.tree.stories), true)
    compare(r.tree.stories.length, 0)
    compare(Array.isArray(r.tree.subtasks), true)
    compare(r.tree.subtasks.length, 0)

    var strRows = fullRaw()
    strRows.status.rows = "x"
    compare(Runs.normalizeRun(strRows).rows.length, 0)
  }

  function test_normalize_garbage() {
    checkDefaults(Runs.normalizeRun(undefined), "undefined")
    checkDefaults(Runs.normalizeRun(null), "null")
    checkDefaults(Runs.normalizeRun("x"), "string")
    checkDefaults(Runs.normalizeRun(5), "number")
    checkDefaults(Runs.normalizeRun({}), "empty object")
    checkDefaults(Runs.normalizeRun([]), "array")
    checkDefaults(Runs.normalizeRun({ row: "x", status: 5 }), "non-object row and status")
    checkDefaults(Runs.normalizeRun({ row: null, status: null }), "null row and status")
    checkDefaults(Runs.normalizeRun({ status: { run: "x", control: "y" } }), "non-object run and control")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382 && bash tests/run.sh tst_runs; echo "exit=$?"`

Expected: pytest passes first (unchanged suite), then the `== tests/core/domain/tst_runs.qml` section fails because `core/domain/runs.js` does not exist (the runner reports the script import as unavailable / a FAIL for the file, with no passing Totals), and `exit=1`.

- [ ] **Step 3: Write minimal implementation**

Create `core/domain/runs.js` with exactly this content:

```js
.pragma library

// Run domain model: one `am` orchestrator run, normalised from the CLI's
// output.
//
// Input shape for normalizeRun (provisional until the runs-snapshot helper
// exists; pinned by tests/core/domain/tst_runs.qml):
//   raw = {
//     row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
//     status: { run: {...}, rows: [...], stories: [...], subtasks: [...],
//               control: { lease: { pid, host, heartbeat_at, accepting, live } }, ... }  // `am status` data, may be absent
//   }
//
// The status always comes from `am` (am status first, then the am runs row),
// never from a brd card. Never throws: anything missing or malformed becomes
// its default, and a missing lease means the run is not live.
function normalizeRun(raw) {
  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
  function objectOr(v) { return isObject(v) ? v : {} }
  function arrayOr(v) { return Array.isArray(v) ? v : [] }
  function text(v) { return v === undefined || v === null ? "" : String(v) }
  function firstText(a, b) { var s = text(a); return s !== "" ? s : text(b) }
  function asGiven(v) { return v === undefined || v === null ? "" : v }

  var r = objectOr(raw)
  var row = objectOr(r.row)
  var st = objectOr(r.status)
  var run = objectOr(st.run)
  var control = objectOr(st.control)

  var lease = null
  if (isObject(control.lease)) {
    var l = control.lease
    lease = {
      pid: asGiven(l.pid),
      host: asGiven(l.host),
      heartbeat_at: asGiven(l.heartbeat_at),
      accepting: l.accepting === true,
      live: l.live === true
    }
  }

  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    lease: lease,
    rows: arrayOr(st.rows),
    tree: { stories: arrayOr(st.stories), subtasks: arrayOr(st.subtasks) }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382 && bash tests/run.sh tst_runs; echo "exit=$?"`

Expected: pytest passes (including `tests/architecture/test_layers.py`), the `tst_runs.qml` section prints `Totals: 9 passed, 0 failed` (7 test functions plus initTestCase/cleanupTestCase), no TypeError/ReferenceError lines, and `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(domain): add runs.js normalizeRun for am run rows and status"
```

---

### Task 2: runState

**Files:**
- Modify: `tests/core/domain/tst_runs.qml` (append five test functions before the final closing `}` of the `TestCase`)
- Modify: `core/domain/runs.js` (append `runState` after `normalizeRun`)

**Interfaces:**
- Consumes: `Runs.normalizeRun(raw)` and its returned shape from Task 1 (`run.status: string`, `run.lease: null | { live: bool, ... }`); the `fullRaw()` test helper from Task 1.
- Produces: `runState(run) -> "running" | "dead" | "parked" | "escalated" | "cancelled" | "done" | "unknown"`. Sibling card 1.2 (791537cf) builds `cardRunState`/`rollup`/`attention` on this.

- [ ] **Step 1: Write the failing test**

In `tests/core/domain/tst_runs.qml`, insert the following functions directly after the closing `}` of `test_normalize_garbage()` and before the final `}` that closes `TestCase`:

```qml
  function test_state_running() {
    compare(Runs.runState({ status: "started", lease: { live: true } }), "running")
    compare(Runs.runState(Runs.normalizeRun(fullRaw())), "running")
  }

  function test_state_dead_not_live() {
    compare(Runs.runState({ status: "started", lease: { live: false } }), "dead")

    var raw = fullRaw()
    raw.status.control.lease.live = false
    compare(Runs.runState(Runs.normalizeRun(raw)), "dead")

    // A sloppy "true" string is not liveness.
    var stringy = fullRaw()
    stringy.status.control.lease.live = "true"
    compare(Runs.runState(Runs.normalizeRun(stringy)), "dead")
  }

  function test_state_dead_missing_lease() {
    compare(Runs.runState({ status: "started", lease: null }), "dead")
    compare(Runs.runState({ status: "started" }), "dead")
    compare(Runs.runState(Runs.normalizeRun({ row: { id: "r1", status: "started" } })), "dead")

    var noLease = fullRaw()
    delete noLease.status.control
    compare(Runs.runState(Runs.normalizeRun(noLease)), "dead")
  }

  function test_state_terminal_and_parked() {
    var expected = [
      ["stopped", "parked"],
      ["escalated", "escalated"],
      ["cancelled", "cancelled"],
      ["done", "done"]
    ]
    for (var i = 0; i < expected.length; i++) {
      var status = expected[i][0]
      var state = expected[i][1]
      compare(Runs.runState({ status: status, lease: { live: true } }), state, status + " live lease")
      compare(Runs.runState({ status: status, lease: { live: false } }), state, status + " dead lease")
      compare(Runs.runState({ status: status, lease: null }), state, status + " no lease")
      compare(Runs.runState({ status: status }), state, status + " lease key absent")
    }
  }

  function test_state_unknown() {
    var statuses = ["weird", "", "stale", "STARTED", "Done", "running", "dead"]
    for (var i = 0; i < statuses.length; i++) {
      compare(Runs.runState({ status: statuses[i], lease: { live: true } }), "unknown", "status " + statuses[i])
    }
    compare(Runs.runState({ lease: { live: true } }), "unknown", "missing status")
    compare(Runs.runState({}), "unknown", "empty run")
    compare(Runs.runState(null), "unknown", "null")
    compare(Runs.runState(undefined), "unknown", "undefined")
    compare(Runs.runState("x"), "unknown", "string run")
    compare(Runs.runState(Runs.normalizeRun(undefined)), "unknown", "normalised garbage")
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382 && bash tests/run.sh tst_runs; echo "exit=$?"`

Expected: pytest passes; the `tst_runs.qml` section shows `FAIL!` lines for the five `test_state_*` functions with a `TypeError: Property 'runState' of object [object Object] is not a function` (run.sh echoes that line because it matches `TypeError` / `is not a function`), the seven `test_normalize_*` functions still pass, and `exit=1`.

- [ ] **Step 3: Write minimal implementation**

Append to the end of `core/domain/runs.js` (after the closing `}` of `normalizeRun`, separated by one blank line):

```js

// The one state shown for a normalised run. The lease matters only while the
// run says `started`: a started run whose lease is missing or not live is
// dead. Anything else -- an unknown or empty status, or no run at all -- is
// `unknown`, which is neither running nor finished. `stale` is a card state,
// never a run state.
function runState(run) {
  if (run === null || typeof run !== "object") return "unknown"
  var status = run.status
  if (status === "started") {
    var lease = run.lease
    return lease !== null && typeof lease === "object" && lease.live === true ? "running" : "dead"
  }
  if (status === "stopped") return "parked"
  if (status === "escalated" || status === "cancelled" || status === "done") return status
  return "unknown"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382 && bash tests/run.sh tst_runs; echo "exit=$?"`

Expected: pytest passes; the `tst_runs.qml` section prints `Totals: 14 passed, 0 failed` (12 test functions plus initTestCase/cleanupTestCase), no TypeError/ReferenceError lines, and `exit=0`.

- [ ] **Step 5: Run the full verification suite**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382 && bash tests/run.sh; echo "exit=$?"`

Expected: pytest passes in full (including `tests/architecture/test_layers.py` unchanged, which confirms `runs.js` has `.pragma library` and no forbidden imports); every `tst_*.qml` section reports `0 failed`; no TypeError / ReferenceError / "is not a function" lines anywhere; `exit=0`. Also confirm `git status --short` lists only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml` (plus this plan/spec under `docs/superpowers/` if not yet committed).

- [ ] **Step 6: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-1-1-runs-js-797d9382
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(domain): add runState mapping am run status and lease to a run state"
```

---

## Spec coverage map

| Spec item | Where |
|---|---|
| `.pragma library`, no imports, ES5 style, two public functions | Global Constraints; Task 1 Step 3, Task 2 Step 3; verified by `test_layers.py` in Task 2 Step 5 |
| Input shape documented in code and tests | Header comments in Task 1 Step 1 (test) and Step 3 (runs.js) |
| `id` / `repo_dir` / `milestone_id` precedence and defaults | `test_normalize_full`, `test_normalize_ids_fallback_and_coercion`, `test_normalize_garbage` |
| `status` from am status first, then row, never brd | `test_normalize_status_prefers_am_status` |
| `lease` null when missing / non-object; strict `live` / `accepting`; pass-through pid/host/heartbeat_at with `""` default | `test_normalize_missing_lease`, `test_normalize_lease_live_strict`, `test_normalize_full` |
| `rows` / `tree` defaults and pass-through | `test_normalize_missing_rows_tree`, `test_normalize_full` |
| Never throws on garbage | `test_normalize_garbage`, `test_state_unknown` |
| Spec tests 1-6 | Task 1 tests of the same names |
| Spec tests 7-11 | Task 2 tests of the same names |
| runState table, lease only for `started`, never `stale`, `unknown` default | Task 2 tests |
| Verification `bash tests/run.sh` | Task 2 Step 5 |
