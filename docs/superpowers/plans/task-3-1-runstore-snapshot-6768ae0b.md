<!-- task-pipeline: validated -->
# 3.1 RunStore: snapshot, selection, amStatus (card 6768ae0b)

Parent story 779eb1bf "RunStore", milestone 4bf4fb2f. This narrows `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (Refresh model step 1, and the error table) to this one subtask. It is blocked by 92b4d150 (Run backend helpers), which is done.

## Scope

New files:
- `core/stores/RunStore.qml`: a `Scope`, shaped like `MilestoneStore.qml`.
- `tests/core/stores/tst_run_store.qml`: written first (TDD).

Imports allowed in the store: `QtQml`, `Quickshell`, `Quickshell.Io`, and `import "../domain/runs.js" as Runs`. Nothing else: no QtQuick*, `qs.*`, `ui/`, `vendor/`, sibling stores (never BoardStore), and no other directories.

Prerequisites: `core/domain/runs.js` (with `normalizeRun` and `errorText`) and `core/backend/runs/runs-snapshot.py` must exist in the tree being worked in. Both are present in this worktree. If they are missing, stop and report it. Do not recreate them here. The tests never execute the script.

Not touched: `core/stores/App.qml` and `docs/architecture.md` (both belong to 3.3), any UI, the repo root, and `tests/architecture`.

Out of scope:
- 3.2: the runs-watch Process, `active`, `watching`, the debounce, liveness, `stale`, setting `amStatus` to `schema` from the watch hello line, and the 5 s poll fallback.
- 3.3: composing the store into App.
- The attempt-logs HelperRunner.
- All 4.x and 5.x work.

## Public surface

| Property | Type | Meaning |
|---|---|---|
| `project` | string | Project root path. Set from outside. |
| `backendDir` | string | Ends with `/`, for example `/plugin/core/backend/`. |
| `runs` | var (array) | Runs normalized by `Runs.normalizeRun`. Starts as `[]`. |
| `selectedRunId` | string | Starts as `""`. |
| `amStatus` | string | One of `ok`, `missing`, `schema`, `error`. Starts as `ok`. |
| `lastError` | string | Starts as `""`. |
| `snapshotRunner` | HelperRunner child | Exposed so tests can reach `snapshotRunner.current`. The script is `backendDir + "runs/runs-snapshot.py"`. Its `guard` is bound to `project`. |
| `refresh()` | function | Starts a snapshot for the current project. |

## Observable behavior

- **refresh():** if `project` is empty, it does nothing. Otherwise it calls `snapshotRunner.run([project])`, so the argv is `["python3", backendDir + "runs/runs-snapshot.py", project]`. A newer refresh replaces an older one (HelperRunner's latest-wins behavior). A result is dropped if its guard no longer equals `project`.
- **On project change:**
  1. Set `runs` to `[]`, `selectedRunId` to `""` and `lastError` to `""`.
  2. Set `amStatus` to `ok`.
  3. If the new project is not empty, call `refresh()`.

  The panel-open trigger belongs to whoever composes the store (3.3), which calls `refresh()`.
- **Parsing `finished(stdout, exitCode, launchedGuard)`:** take the last non-empty line of stdout and parse it as JSON.
  - **`ok:true`:** each entry in `runs` holds the `am runs` summary fields plus a `status` field containing `am status` data. Map each entry with `Runs.normalizeRun({ row: <entry without its status key>, status: entry.status })`. Removing `status` from `row` is required, because the snapshot overwrote the summary's status string with the status object. Then set `runs` to the mapped list, `amStatus` to `ok` and `lastError` to `""`. A missing or empty `runs` array (no runs, or no data dir) is ok with `runs = []`, and is not an error. A `runs` value that is not an array counts as empty. Entries that are not objects are skipped, so the store never throws. The reply's `data_dir` field is ignored in 3.1: it is not stored or exposed (the footer that shows it belongs to the UI subtasks).
  - **`ok:false` with `error.type === "AmMissing"`:** set `amStatus` to `missing`, set `runs` to `[]` (the spec says the UI shows no badges in this state), and set `lastError` to `Runs.errorText(envelope)`.
  - **`ok:false` with any other type** (AmBadOutput, Usage, HelperError, or a re-emitted am error): keep the previous `runs`, set `amStatus` to `error`, and set `lastError` to `Runs.errorText(envelope)`.
  - **Unparseable or empty stdout, or a non-object result:** treat it like `ok:false`. Keep the previous `runs`, set `amStatus` to `error`, and set `lastError` to a non-empty message that includes the exit code. The store never throws.
- **Selection:** `selectedRunId` is plain state that the UI sets. A project switch clears it. A refresh within the same project leaves it unchanged.
- **The `schema` value:** it is declared in the enum, but no 3.1 path produces it. 3.2 sets it from the watch hello line.

## Tests

All tests below go in `tests/core/stores/tst_run_store.qml`. Store behavior belongs in headless store tests that drive stubbed Process objects and assert on properties, per docs/architecture.md "Tests".

Tests set `project` after creating the store, not through `createObject` properties, because the project-change handler does not fire for an initial value. Because the stub `Process` has no real lifecycle, a test that needs a late exit of an older process must capture `store.snapshotRunner.current` before the next `refresh()` or project switch.

The test creates the store directly with `Qt.createComponent("../../../core/stores/RunStore.qml")`, because App does not compose it until 3.3. It passes `backendDir: "/plugin/core/backend/"`. It fakes replies with `store.snapshotRunner.current.outText = '<json>'; store.snapshotRunner.current.exited(code)`.

1. **Defaults:** `runs` is `[]`, `selectedRunId` is `""`, `amStatus` is `ok`, `lastError` is `""`, and no process runs while there is no project.
2. **Setting `project` starts a snapshot:** the argv equals `["python3", "/plugin/core/backend/runs/runs-snapshot.py", "/home/u/my proj"]`. The path contains a space, and it is passed as one argument.
3. **An `ok:true` reply fills `runs` with normalized runs:**
   - `id`, `status` and `lease` come from the nested `status` data.
   - `status` is not `"[object Object]"`.
   - `amStatus` is `ok` and `lastError` is empty.
4. **`ok:true` with `runs: []`, or with `runs` absent:** `runs` is `[]` and `amStatus` is `ok`.
5. **Refresh sequencing:** two `refresh()` calls in a row, then a late exit of the first process. Only the second reply is applied.
6. **AmMissing:** `amStatus` is `missing`, `runs` is cleared, and `lastError` equals `"AmMissing: am is not installed."`.
7. **`ok:false` of another type after a good snapshot** (for example AmBadOutput, exit 1): the previous `runs` are kept, `amStatus` is `error`, and `lastError` equals `"AmBadOutput: <message>"`.
8. **Garbage stdout after a good snapshot:** the previous `runs` are kept, `amStatus` is `error`, `lastError` is non-empty, and there is no TypeError.
9. **A good reply after an error restores the ok state:** `amStatus` returns to `ok` and `lastError` returns to `""`.
10. **Project switch:**
    - Set project A, load runs, and set `selectedRunId`. Then switch to B.
    - Immediately after the switch: `runs` is `[]`, `selectedRunId` is `""`, and a new snapshot for B was launched.
    - A late exit from A's process changes nothing.
    - B's reply is applied.
11. **Clearing `project` to `""`:** `runs` and the selection are cleared, and no snapshot is launched.

Verification: `bash tests/run.sh run_store` while iterating, then the full `bash ./tests/run.sh`. The full run includes `tests/architecture`, which must stay green and needs no changes.

---

# RunStore Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `core/stores/RunStore.qml`, a headless store that runs `runs-snapshot.py` for the selected project and exposes normalized runs, the selection, `amStatus` and `lastError`, with `tests/core/stores/tst_run_store.qml` written first.

**Architecture:** RunStore is a `Scope` that holds one `HelperRunner` (`snapshotRunner`, latest run wins) whose `guard` is bound to `project`. The project-change reaction (clear, then refresh) runs from the runner's `onGuardChanged` handler rather than from `onProjectChanged`. QML does not define whether a binding or a sibling change handler runs first when `project` changes. If `refresh()` ran before the guard binding updated, the new process would carry the OLD project as its `launchGuard`, and its reply would be dropped. `guard` changes only after its binding has re-evaluated, so at that point `guard === project` always holds. The observable behavior is exactly the spec's "On project change". Parsing lives in the store (`applySnapshot`) and uses `Runs.normalizeRun` and `Runs.errorText` from `core/domain/runs.js`.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), Qt Quick Test via `qmltestrunner` with the stubs in `tests/stubs`, and `tests/run.sh`.

**Spec:** `docs/superpowers/specs/task-3-1-runstore-snapshot-6768ae0b-design.md` (prepended above, verbatim).

## Global Constraints

- The store imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `import "../domain/runs.js" as Runs`. No QtQuick*, `qs.*`, `ui/`, `vendor/`, sibling stores (never BoardStore). `tests/architecture/test_layers.py` enforces this.
- Script path: `store.backendDir + "runs/runs-snapshot.py"`. `backendDir` ends with `/`.
- `amStatus` is one of `ok`, `missing`, `schema`, `error` and starts as `ok`. No 3.1 path sets `schema`.
- Do NOT edit `core/stores/App.qml`, `docs/architecture.md`, `tests/architecture`, any UI, `core/domain/runs.js` or `core/backend/runs/*`. Do not create `.qml`/`.js`/`.py` files at the repo root.
- Out of scope: the watch process, `active`, `watching`, `stale`, the debounce, liveness, the poll fallback, attempt logs, and the `data_dir` footer.
- Prerequisite check: `core/domain/runs.js` and `core/backend/runs/runs-snapshot.py` must exist in the worktree. If either is missing, STOP and report it. Do not recreate them.
- All commands run from the worktree root `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-3-1-runstore-snapshot-6768ae0b`.
- `tests/run.sh` fails on `TypeError`, `ReferenceError`, `Unable to assign` and similar strings in qmltestrunner output, even when every test passes. A green run means no such lines.

## Review Focus

1. Helper stdout with extra lines (a warning line before the JSON, or a trailing newline): the last non-empty line is used, and the reply still applies. The test is in Task 2 (`test_the_last_non_empty_line_is_the_reply`).
2. `ok:true` with a `runs` value that is not an array, or with entries that are `null`, numbers or strings: those entries are skipped, the valid ones still load, and nothing throws. The test is in Task 2 (`test_malformed_runs_are_skipped_without_throwing`).
3. Valid JSON that is not an envelope object (`[]`, `"x"`, `null`, or `{}` with no `ok`): treated as unusable output, so the previous runs are kept, `amStatus` is `error`, and `lastError` names the exit code. The test is in Task 3 (`test_json_that_is_not_an_envelope_is_an_error`).
4. `ok:false` with no `error` object: `amStatus` is `error` and `lastError` is `"unknown error"`, not blank and not a throw. The test is in Task 3 (`test_ok_false_without_an_error_object_is_unknown_error`).
5. A refresh within the same project leaves `selectedRunId` alone (the user's selection must not vanish every snapshot). The test is in Task 2 (`test_a_refresh_in_the_same_project_keeps_the_selection`).

---

### Task 0: Prerequisite check

**Files:** none changed.

- [ ] **Step 1: Confirm the domain module and the helper exist**

Run: `ls core/domain/runs.js core/backend/runs/runs-snapshot.py && grep -n "^function normalizeRun\|^function errorText" core/domain/runs.js`
Expected: both paths are listed, and grep prints `function normalizeRun(raw) {` and `function errorText(error) {`. If anything is missing, STOP and report it. Do not create these files.

---

### Task 1: RunStore skeleton (defaults, argv, project change, clearing)

**Files:**
- Create: `tests/core/stores/tst_run_store.qml`
- Create: `core/stores/RunStore.qml`

**Interfaces:**
- Consumes: `core/stores/HelperRunner.qml`: properties `script`, `guard`, `busy`, `seq` and `current`, the method `run(args)`, and the signal `finished(string stdout, int exitCode, string launchedGuard)`. Each `current` process carries `command`, `running`, `launchGuard`, `launchSeq` and `outText`, plus the `exited(int)` signal (stub in `tests/stubs/Quickshell/Io/Process.qml`).
- Produces: `RunStore` with `property string project`, `property string backendDir`, `property var runs: []`, `property string selectedRunId: ""`, `property string amStatus: "ok"`, `property string lastError: ""`, `readonly property alias snapshotRunner`, `function refresh()` and `function projectSwitched()`. Task 2 adds `applySnapshot(stdout, exitCode, launchedGuard)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/core/stores/tst_run_store.qml`:

```qml
// tests/core/stores/tst_run_store.qml
// The run monitor's store: the snapshot helper's exact argv, how its one JSON
// line becomes normalized runs and an amStatus, the latest-wins and project
// guards, and what a project switch clears. Built directly (App composes the
// store only in 3.3) and driven through stubbed Process objects.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresRunStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"

  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // A store with project A set, so its first snapshot is already in flight.
  function makeWithProject(root) {
    var store = make(); if (!store) return null
    store.project = root
    return store
  }

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data.
  function entry(id, runStatus, live) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
      status: {
        run: run,
        rows: [],
        stories: [],
        subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
  }

  function okReply(entries) {
    return JSON.stringify({ ok: true, runs: entries, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // ---- defaults and the snapshot command

  function test_defaults_and_no_process_without_a_project() {
    var store = make(); if (!store) return
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.project, "")
    verify(!store.snapshotRunner.current, "no snapshot while there is no project")
    store.refresh()
    verify(!store.snapshotRunner.current, "refresh() with no project does nothing")
  }

  function test_setting_the_project_starts_a_snapshot_with_the_exact_argv() {
    var store = makeWithProject(rootA); if (!store) return
    var proc = store.snapshotRunner.current
    verify(proc, "a snapshot was launched")
    compare(proc.command.length, 3)
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command[2], "/home/u/my proj", "the path with a space is one argument")
    compare(proc.running, true)
    compare(proc.launchGuard, "/home/u/my proj", "the launch is guarded by the NEW project")
  }

  // ---- project changes

  function test_a_project_switch_clears_runs_selection_and_error_and_refreshes() {
    var store = makeWithProject(rootA); if (!store) return
    var procA = store.snapshotRunner.current
    store.runs = [{ id: "r1" }]
    store.selectedRunId = "r1"
    store.lastError = "boom"
    store.amStatus = "error"
    store.project = rootB
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.lastError, "")
    compare(store.amStatus, "ok")
    var procB = store.snapshotRunner.current
    verify(procB !== procA, "a new snapshot was launched")
    compare(procB.command[2], "/home/u/b")
    compare(procB.launchGuard, "/home/u/b")
    compare(procA.running, false, "A's snapshot is stopped")
  }

  function test_clearing_the_project_clears_state_and_launches_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var procA = store.snapshotRunner.current
    var seqBefore = store.snapshotRunner.seq
    store.runs = [{ id: "r1" }]
    store.selectedRunId = "r1"
    store.project = ""
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.amStatus, "ok")
    compare(store.snapshotRunner.seq, seqBefore, "no snapshot is launched")
    compare(store.snapshotRunner.current, procA, "the runner was not asked to run again")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
Expected: FAIL. Every test fails in `make()` with an error like `No such file or directory` / `RunStore.qml` not found from `comp.errorString()`, because the store does not exist yet. (pytest runs first and should pass.)

- [ ] **Step 3: Write the minimal implementation**

Create `core/stores/RunStore.qml`:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run
// and whether `am` could be asked at all. The project root and the backend
// directory are handed to it from outside -- it never reaches for another
// store. The live watch (3.2) and composing it into App (3.3) come later.
Scope {
  id: store

  property string project: ""         // project root path
  property string backendDir: ""      // <plugin>/core/backend/

  property var runs: []               // Runs.normalizeRun output, am's order
  property string selectedRunId: ""   // set by the UI
  property string amStatus: "ok"      // "ok" | "missing" | "schema" | "error"
  property string lastError: ""

  readonly property alias snapshotRunner: snapshotRunner

  // Asks for a fresh snapshot of the current project. A newer call replaces an
  // older one (the runner's latest-wins rule).
  function refresh() {
    if (store.project === "") return
    snapshotRunner.run([store.project])
  }

  // A different project: nothing the old one left behind may show, and its
  // runs are fetched straight away.
  function projectSwitched() {
    store.runs = []
    store.selectedRunId = ""
    store.lastError = ""
    store.amStatus = "ok"
    if (store.project !== "") store.refresh()
  }

  // The guard is the project root, so a snapshot launched for a project the
  // user has since left is dropped. The project-change reaction hangs off the
  // guard, not off `project`: the guard has already followed the project by the
  // time it changes, so the snapshot launched here is always guarded by the NEW
  // project (QML does not order a binding against a sibling change handler).
  HelperRunner {
    id: snapshotRunner
    script: store.backendDir + "runs/runs-snapshot.py"
    guard: store.project
    onGuardChanged: store.projectSwitched()
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 6 passed, 0 failed` for `tests/core/stores/tst_run_store.qml` (4 tests plus initTestCase/cleanupTestCase), with no `TypeError`/`ReferenceError`/`Unable to assign` lines, and exit status 0.

- [ ] **Step 5: Commit**

```bash
git add tests/core/stores/tst_run_store.qml core/stores/RunStore.qml
git commit -m "feat(runs): RunStore skeleton with snapshot runner and project switch (6768ae0b)"
```

---

### Task 2: Applying an ok snapshot (normalization, sequencing, project guard)

**Files:**
- Modify: `tests/core/stores/tst_run_store.qml` (append tests before the TestCase's final `}`)
- Modify: `core/stores/RunStore.qml` (add parsing helpers and `applySnapshot`, and wire `onFinished`)

**Interfaces:**
- Consumes: `Runs.normalizeRun(raw)` with `raw = { row, status }`, which returns `{ id, repo_dir, milestone_id, status, lease, rows, tree }`. `lease` is `null` or `{ pid, host, heartbeat_at, accepting, live }`. Also the Task 1 test helpers `make()`, `makeWithProject(root)`, `reply(proc, text, code)`, `entry(id, runStatus, live)`, `okReply(entries)`, `rootA`, `rootB`.
- Produces: `store.lastLine(text) -> string`, `store.parseEnvelope(text) -> object|null`, `store.rowOf(entry) -> object` (entry without `status`), and `store.applySnapshot(stdout, exitCode, launchedGuard)`. Task 3 replaces `applySnapshot`'s body.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, insert the following immediately before the last line (the closing `}` of `TestCase`):

```qml

  // ---- ok snapshots

  function test_an_ok_reply_fills_runs_with_normalized_runs() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true), entry("r2", "", false)]), 0)
    compare(store.runs.length, 2)
    compare(store.runs[0].id, "r1")
    compare(store.runs[0].status, "started", "the status comes from the nested am status data")
    compare(store.runs[0].milestone_id, "m-r1")
    verify(store.runs[0].lease !== null, "the lease comes from the nested control data")
    compare(store.runs[0].lease.live, true)
    compare(store.runs[0].lease.pid, 42)
    compare(store.runs[1].id, "r2")
    // r2's am status has no run.status: normalizeRun falls back to the row's
    // status, which must not be the status OBJECT the helper put there.
    verify(store.runs[1].status !== "[object Object]", "the summary's overwritten status is not used")
    compare(store.runs[1].status, "")
    compare(store.runs[1].lease.live, false)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  function test_an_ok_reply_without_runs_is_ok_and_empty() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.runs.length, 1)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.runs.length, 0, "runs: [] empties the list")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": true, "data_dir": "/x"}\n', 0)
    compare(store.runs.length, 0, "an absent runs key is an empty list, not an error")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  function test_only_the_latest_refresh_is_applied() {
    var store = makeWithProject(rootA); if (!store) return
    store.refresh()
    var first = store.snapshotRunner.current
    store.refresh()
    var second = store.snapshotRunner.current
    verify(first !== second, "the second refresh launched its own process")
    compare(first.running, false, "the older snapshot is stopped")
    reply(second, okReply([entry("new", "started", true)]), 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "new")
    reply(first, okReply([entry("old", "started", true), entry("old2", "done", false)]), 0)
    compare(store.runs.length, 1, "a late exit of the older snapshot changes nothing")
    compare(store.runs[0].id, "new")
  }

  function test_a_project_switch_drops_the_old_projects_late_result() {
    var store = makeWithProject(rootA); if (!store) return
    var procA = store.snapshotRunner.current
    reply(procA, okReply([entry("a1", "started", true)]), 0)
    compare(store.runs[0].id, "a1")
    store.selectedRunId = "a1"
    store.refresh()
    var procA2 = store.snapshotRunner.current
    store.project = rootB
    compare(store.runs.length, 0, "cleared at once")
    compare(store.selectedRunId, "", "the selection belongs to the old project")
    var procB = store.snapshotRunner.current
    verify(procB !== procA2, "a snapshot for B was launched")
    compare(procB.command[2], "/home/u/b")
    reply(procA2, okReply([entry("a2", "started", true)]), 0)
    compare(store.runs.length, 0, "A's late reply changes nothing")
    compare(store.amStatus, "ok")
    reply(procB, okReply([entry("b1", "done", false)]), 0)
    compare(store.runs.length, 1, "B's reply is applied")
    compare(store.runs[0].id, "b1")
  }

  function test_a_refresh_in_the_same_project_keeps_the_selection() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    store.selectedRunId = "r1"
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r1", "done", false)]), 0)
    compare(store.selectedRunId, "r1")
    compare(store.runs[0].status, "done")
  }

  function test_the_last_non_empty_line_is_the_reply() {
    var store = makeWithProject(rootA); if (!store) return
    var text = "warning: something chatty\n" + okReply([entry("r1", "started", true)]) + "\n  \n"
    reply(store.snapshotRunner.current, text, 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r1")
    compare(store.amStatus, "ok")
  }

  function test_malformed_runs_are_skipped_without_throwing() {
    var store = makeWithProject(rootA); if (!store) return
    var mixed = JSON.stringify({ ok: true, runs: [null, 3, "x", [1], entry("r1", "started", true), { id: "r2" }] })
    reply(store.snapshotRunner.current, mixed, 0)
    compare(store.runs.length, 2, "only the object entries are kept")
    compare(store.runs[0].id, "r1")
    compare(store.runs[1].id, "r2", "an entry without status data still normalizes")
    compare(store.runs[1].lease, null)
    compare(store.amStatus, "ok")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": true, "runs": {"r1": {}}}', 0)
    compare(store.runs.length, 0, "a runs value that is not an array is empty")
    compare(store.amStatus, "ok")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
Expected: FAIL. The new tests fail on their first `compare(store.runs...)`, for example `test_an_ok_reply_fills_runs_with_normalized_runs` with `Compared values are not the same Actual (): 0 Expected (): 2`, because nothing handles `finished` yet. The four Task 1 tests still pass.

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, insert these functions immediately after the closing `}` of `function projectSwitched()` (before the blank line and the `// The guard is the project root` comment):

```qml

  // The helper prints exactly one JSON line; anything before it (a warning) and
  // blank lines after it are ignored.
  function lastLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line !== "") return line
    }
    return ""
  }

  // The reply's envelope object, or null when there is none to read.
  function parseEnvelope(text) {
    var line = store.lastLine(text)
    if (line === "") return null
    var value = null
    try { value = JSON.parse(line) } catch (e) { return null }
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null
  }

  // The `am runs` summary without its `status` key: the helper replaced the
  // summary's status string with the `am status` object, which normalizeRun
  // must never read as the row's status ("[object Object]").
  function rowOf(entry) {
    var row = {}
    for (var key in entry) {
      if (key !== "status" && Object.prototype.hasOwnProperty.call(entry, key)) row[key] = entry[key]
    }
    return row
  }

  function applySnapshot(stdout, exitCode, launchedGuard) {
    if (launchedGuard !== store.project) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope === null || envelope.ok !== true) return
    var list = Array.isArray(envelope.runs) ? envelope.runs : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      out.push(Runs.normalizeRun({ row: store.rowOf(e), status: e.status }))
    }
    store.runs = out
    store.amStatus = "ok"
    store.lastError = ""
  }
```

Then, in the same file, replace:

```qml
    guard: store.project
    onGuardChanged: store.projectSwitched()
  }
```

with:

```qml
    guard: store.project
    onGuardChanged: store.projectSwitched()
    onFinished: function(stdout, exitCode, launchedGuard) { store.applySnapshot(stdout, exitCode, launchedGuard) }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 13 passed, 0 failed` for `tst_run_store.qml` (11 tests plus init/cleanup), with no `TypeError`/`ReferenceError` lines and exit status 0.

- [ ] **Step 5: Commit**

```bash
git add tests/core/stores/tst_run_store.qml core/stores/RunStore.qml
git commit -m "feat(runs): RunStore applies ok snapshots, latest-wins and project-guarded (6768ae0b)"
```

---

### Task 3: Error replies (AmMissing, other ok:false, unusable output, recovery)

**Files:**
- Modify: `tests/core/stores/tst_run_store.qml` (append tests before the TestCase's final `}`)
- Modify: `core/stores/RunStore.qml` (replace `applySnapshot`)

**Interfaces:**
- Consumes: `Runs.errorText(envelope) -> string`, which gives `"type: message"`, either part alone, or `"unknown error"`. Also `store.parseEnvelope` and `store.rowOf` from Task 2, and the test helpers from Task 1.
- Produces: the final `store.applySnapshot(stdout, exitCode, launchedGuard)`, which covers every reply shape.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, insert the following immediately before the last line (the closing `}` of `TestCase`):

```qml

  // ---- errors

  // A store whose first snapshot loaded r1, ready for the next reply.
  function loaded() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.runs.length, 1)
    store.refresh()
    return store
  }

  function test_am_missing_sets_missing_and_clears_the_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}\n', 1)
    compare(store.amStatus, "missing")
    compare(store.runs.length, 0, "no badges while am is missing")
    compare(store.lastError, "AmMissing: am is not installed.")
  }

  function test_another_ok_false_keeps_the_previous_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmBadOutput", "message": "am status did not print JSON (exit 3)."}}\n', 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1, "the previous runs stay")
    compare(store.runs[0].id, "r1")
    compare(store.lastError, "AmBadOutput: am status did not print JSON (exit 3).")
  }

  function test_garbage_stdout_keeps_the_previous_runs_and_names_the_exit_code() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, "Traceback (most recent call last):\n  oops {not json", 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r1")
    verify(store.lastError !== "", "the reason is shown")
    verify(store.lastError.indexOf("exit 1") >= 0, "the exit code is named: " + store.lastError)
    store.refresh()
    reply(store.snapshotRunner.current, "", 7)
    compare(store.amStatus, "error", "empty stdout is an error too")
    compare(store.runs.length, 1)
    verify(store.lastError.indexOf("exit 7") >= 0, "the exit code is named: " + store.lastError)
  }

  function test_json_that_is_not_an_envelope_is_an_error() {
    var store = loaded(); if (!store) return
    var shapes = ["[]", '"x"', "null", "{}", '{"ok": "yes"}']
    for (var i = 0; i < shapes.length; i++) {
      reply(store.snapshotRunner.current, shapes[i], 0)
      compare(store.amStatus, "error", shapes[i] + " is not a usable reply")
      compare(store.runs.length, 1, shapes[i] + " keeps the previous runs")
      verify(store.lastError.indexOf("exit 0") >= 0, "the exit code is named: " + store.lastError)
      store.refresh()
    }
  }

  function test_ok_false_without_an_error_object_is_unknown_error() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false}', 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1)
    compare(store.lastError, "unknown error")
  }

  function test_a_good_reply_after_an_error_restores_ok() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "The runs snapshot failed: boom"}}', 1)
    compare(store.amStatus, "error")
    verify(store.lastError !== "")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r2", "done", false)]), 0)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r2")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}', 1)
    compare(store.amStatus, "missing")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.amStatus, "ok", "missing recovers too")
    compare(store.lastError, "")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
Expected: FAIL. Each new test fails on its first `amStatus` compare, for example `test_am_missing_sets_missing_and_clears_the_runs` with `Actual (): ok Expected (): missing`, because Task 2's `applySnapshot` ignores everything that is not `ok:true`. The Task 1 and Task 2 tests still pass.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, replace the whole `function applySnapshot(stdout, exitCode, launchedGuard) { ... }` from Task 2 with:

```qml
  // One snapshot reply. ok:true replaces the runs (none at all is fine).
  // AmMissing empties them: no badges while am is not there. Any other failure
  // -- an ok:false envelope or output that is not one -- keeps what the last
  // good snapshot said and only reports why this one failed. Never throws.
  function applySnapshot(stdout, exitCode, launchedGuard) {
    if (launchedGuard !== store.project) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var list = Array.isArray(envelope.runs) ? envelope.runs : []
      var out = []
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e === null || typeof e !== "object" || Array.isArray(e)) continue
        out.push(Runs.normalizeRun({ row: store.rowOf(e), status: e.status }))
      }
      store.runs = out
      store.amStatus = "ok"
      store.lastError = ""
      return
    }
    if (envelope !== null && envelope.ok === false) {
      var err = envelope.error
      var type = err !== null && typeof err === "object" ? err.type : ""
      store.lastError = Runs.errorText(envelope)
      if (type === "AmMissing") {
        store.runs = []
        store.amStatus = "missing"
      } else {
        store.amStatus = "error"
      }
      return
    }
    store.amStatus = "error"
    store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 19 passed, 0 failed` for `tst_run_store.qml` (17 tests plus init/cleanup), with no `TypeError`/`ReferenceError` lines and exit status 0.

- [ ] **Step 5: Commit**

```bash
git add tests/core/stores/tst_run_store.qml core/stores/RunStore.qml
git commit -m "feat(runs): RunStore maps AmMissing, ok:false and unusable output to amStatus (6768ae0b)"
```

---

### Task 4: Full verification

**Files:** none changed (unless a failure must be fixed in the two files above).

- [ ] **Step 1: Run the full suite**

Run: `bash ./tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py`, which checks the store's imports). Every `tst_*.qml` reports `0 failed`, no `TypeError`/`ReferenceError`/`Unable to assign`/`is not a function` lines are printed, and the exit status is 0.

- [ ] **Step 2: Confirm nothing out of scope changed**

Run: `git status --porcelain && git diff --stat cd26bdf HEAD`
Expected: `git status` shows nothing except the untracked plan and spec files under `docs/superpowers/plans/` and `docs/superpowers/specs/` (they are not part of this change; do not commit them). The diff against `cd26bdf` (the commit before Task 1) lists only `core/stores/RunStore.qml` and `tests/core/stores/tst_run_store.qml`. No `App.qml`, `docs/architecture.md`, `core/domain/runs.js`, `core/backend/runs/*`, `tests/architecture` or root-level files.

- [ ] **Step 3: If Step 1 or 2 found anything, fix it in the two files above, rerun Step 1, and commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "fix(runs): RunStore full-suite fixes (6768ae0b)"
```

(Skip this step when Steps 1 and 2 were already clean.)

---

## Spec coverage map

| Spec test | Plan test |
|---|---|
| 1 Defaults | Task 1 `test_defaults_and_no_process_without_a_project` |
| 2 Exact argv | Task 1 `test_setting_the_project_starts_a_snapshot_with_the_exact_argv` |
| 3 Normalization | Task 2 `test_an_ok_reply_fills_runs_with_normalized_runs` |
| 4 Empty/absent runs | Task 2 `test_an_ok_reply_without_runs_is_ok_and_empty` |
| 5 Refresh sequencing | Task 2 `test_only_the_latest_refresh_is_applied` |
| 6 AmMissing | Task 3 `test_am_missing_sets_missing_and_clears_the_runs` |
| 7 Other ok:false | Task 3 `test_another_ok_false_keeps_the_previous_runs` |
| 8 Garbage stdout | Task 3 `test_garbage_stdout_keeps_the_previous_runs_and_names_the_exit_code` |
| 9 Recovery | Task 3 `test_a_good_reply_after_an_error_restores_ok` |
| 10 Project switch + late result | Task 1 `test_a_project_switch_clears_runs_selection_and_error_and_refreshes`, Task 2 `test_a_project_switch_drops_the_old_projects_late_result` |
| 11 Clearing project | Task 1 `test_clearing_the_project_clears_state_and_launches_nothing` |
