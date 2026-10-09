# 1.1 RunStore coverage map and characterization tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin today's cross-concern behaviour of `RunStore.qml` with 14 characterization tests and replace
the parent spec's Appendix A stub with the full member map, the not-present table, the cross-concern call
list and the list of added tests.

**Architecture:** No production change. Twelve App-level tests in `tests/core/stores/tst_app_runs.qml` drive a
real `App` (`app.runs`, `app.projects`, `app.panelOpen`) through stubbed `Process` objects; two store-level
twins in `tests/core/stores/tst_run_store.qml` reuse that file's existing builders. Appendix A is pasted
whole from Task 5 and checked by a script.

**Tech Stack:** QML / QtTest (`qmltestrunner`, Qt 6), the repo's `tests/stubs` Quickshell stubs, Python 3
for the appendix check, `bash tests/run.sh` for the full gate.

**Spec:** `docs/superpowers/specs/1-1-runstore-coverage-c1570886.md` (prepended in full below). Parent:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`.

## Global Constraints

- No file under `core/` or `ui/` changes. `git diff --stat` touches only
  `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, `tests/core/stores/tst_app_runs.qml`,
  `tests/core/stores/tst_run_store.qml` (plus this spec and plan).
- Tests pin TODAY's behaviour; no `dispatchRoot`, no `snapshotReplied`, no `refreshRequested`.
- Tests read only `app.runs`, plus the existing `app.projects`, `app.nav` and `app.panelOpen` inputs.
- No existing test or expectation is changed or deleted. No shared helper file.
- New helpers go at the top of `tst_app_runs.qml`, next to `make()` and `okReply`, each with a one-line contract comment.
- Comments state the contract only, with no narrative.
- `bash tests/run.sh` is green; its failure scan sees none of `FAIL`, `TypeError`, `ReferenceError`,
  `non-existent`, `Unable to assign`, `is not a function`. `tests/architecture` stays green.
- Only the body under `## Appendix A — member mapping` changes in the parent spec; the heading stays.

## Facts the executor needs

- Run a QML file directly (fast, about 0.3 s): `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`. Append `StoresAppRuns::test_name` to run
  one test. `QML_XHR_ALLOW_FILE_READ=1` is required: without it `tst_run_store.qml`'s fixture loads fail
  with "amFixtures: cannot load runs.json".
- A stubbed reply is `proc.outText = text; proc.exited(code)` (the `reply` helper). `HelperRunner.run`
  bumps `seq`; a request while the runner is busy only queues a pending snapshot, so `seq` counts launches.
- `make()` registers pA and pB and auto-selects pA: a snapshot of both roots is in flight and
  `runSettingsRunner` has a `get-run-settings` for pA in flight. Opening the panel while that snapshot is in
  flight queues one pending "all" snapshot, which is why `openApp` answers twice.
- `applyGlobalSettings` reads `notifyOnEscalation` at the top level of the reply.

## Deviations from the spec's wording (each one keeps the spec's intent)

1. **Test 9's reply shape.** The spec writes `{"ok":true,"settings":{"notifyOnEscalation":true}}`, but
   also says to copy the exact shape `tst_run_store.qml`'s notify tests use. That shape is the bare
   `{"notifyOnEscalation": true}` (`test_the_global_switch_loads_on_each_opening_with_no_project`), and
   `applyGlobalSettings` (`RunStore.qml:1407-1413`) reads the top-level key: with the spec's literal shape
   the switch would stay off. The plan uses the bare shape.
2. **Test 9 can fail on `notifyTouched`.** A fresh App has `notifyTouched === false` already, so the test
   first touches the switch with `setNotifyOnEscalation(false)` and lets the save land; only then does the
   opening's reset show.
3. **Test 12 adds a control.** pA's run escalates in the same reply, so the test also shows pA stayed armed
   (exactly one toast, `a1`).
4. **2b candidates.** `test_a_snapshot_after_a_no_root_watch_attempt_does_not_retry` is **not** added:
   `test_with_no_absolute_root_no_watch_is_launched` (no watch, a second good reply does not retry,
   `watchSeq` unchanged) and `test_reactivation_starts_a_new_watch` (reset by the next `startLive`) already
   pin `watchTried`. The two refresh twins **are** added: every existing control and dispatch reply test
   that checks the re-snapshot uses one root (`ctlStore`, `dispatchStore`/`readyStore`), and the 3.5
   `crossStore` tests check only `seq`, never the argv.
5. **The "already covered" list was confirmed by reading:** `dismissControlError`
   (`test_a_new_request_and_dismiss_clear_the_control_error`), `closeCancel` (`:3220` in
   `test_open_cancel_opens_only_for_a_cancellable_run`, `:3261` in
   `test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm`), `dispatchSaveReplied`,
   `mergedPrefixes`, `isHereStart`, `retargetToMilestone`, `hasRunningRun` (`:1661-1689`), `stopLive`,
   `projectSwitched`.
6. **Line numbers.** A re-grep at plan time found no drift from the spec's table: 225 top-level
   declarations, every line as listed.

## Review Focus

1. **A test that cannot fail.** A characterization test is green from its first run, so it can pass
   vacuously. Every task has a RED step that breaks one expectation per test. The plan's author also
   checked each coupling test by removing the production line it pins (`RunStore.qml` lines 743, 979, 1026,
   1208, 1359, 363, 386, 659, 1729, 1759): each removal failed exactly the matching test.
2. **A reply landing while the snapshot runner is busy.** Then the re-snapshot is only queued, `seq` does
   not move, and a test that reads `snapshotRunner.current` reads the old process. Every App test answers
   all in-flight snapshots first (`openApp` answers both; `readyApp` answers make()'s) and asserts
   `busy === false` in `openApp`.
3. **Appendix drift.** If `RunStore.qml` changes before Task 5 runs, line numbers and the row count drift.
   Task 5's check script re-greps the count and fails on any mismatch; the executor then fixes the line
   numbers, never the targets.
4. **A named test that does not exist.** A typo in a `file::test_name` breaks the next subtask's moves.
   The check script resolves every name in the appendix against `^  function <name>(` in its file.
5. **An AmMissing reply for only some roots.** Today it disarms only when every matched entry is AmMissing.
   Test 3 sends AmMissing for both roots; the partial case stays pinned by the existing
   `test_a_partial_reply_that_is_am_missing_empties_every_root` and
   `test_an_am_missing_spell_disarms_every_project`.

---

## Task 1: App-level snapshot couplings (tests 1-3)

**Files:**
- Modify: `tests/core/stores/tst_app_runs.qml` (helpers before the first test; tests at the end)

**Interfaces:**
- Consumes: the file's existing `make()`, `tc.pA`, `tc.pB`, `spyC`.
- Produces (later tasks use these exact names): `reply(proc, text, code)`,
  `runEntry(id, runStatus, live, root, requests)`, `runningIn(id, root)`, `escalatedIn(id, root)`,
  `listReply(aRuns, bRuns)` (bRuns `null` = no pB entry), `missingReply()`, `snapshot(app, text)`,
  `openApp(aRuns, bRuns)` → App, `ctlOk(data)` → string.

- [ ] **Step 1: Add this task's fixture helpers**

In `tests/core/stores/tst_app_runs.qml`, insert this block immediately **before** the line
`  function test_app_composes_a_run_store_with_no_project_and_closed() {` (so helpers from earlier tasks stay above it, in task order), followed by one blank line:

```qml
  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // One snapshot entry: run `id` of `root` with am status `runStatus`, its
  // lease live or not, and its am control requests ([] when omitted).
  function runEntry(id, runStatus, live, root, requests) {
    return { id: id, workflow: "milestone", repo_dir: root, started_at: "2026-10-01T00:00:00Z",
             status: { run: { id: id, milestone_id: "m-" + id, status: runStatus }, rows: [], stories: [], subtasks: [],
                       control: { requests: requests || [],
                                  lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } } } }
  }

  // A running run of `root` (pA when omitted).
  function runningIn(id, root) { return runEntry(id, "started", true, root || tc.pA.root_path) }

  // An escalated run of `root` (pA when omitted).
  function escalatedIn(id, root) { return runEntry(id, "escalated", false, root || tc.pA.root_path) }

  // runs-snapshot-all.py's reply: pA's entry lists aRuns, pB's lists bRuns; no pB entry when bRuns is null.
  function listReply(aRuns, bRuns) {
    var projects = [{ root: tc.pA.root_path, ok: true, runs: aRuns }]
    if (bRuns !== null) projects.push({ root: tc.pB.root_path, ok: true, runs: bRuns })
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // runs-snapshot-all.py's reply where both roots' entries are AmMissing.
  function missingReply() {
    var error = { type: "AmMissing", message: "am is not installed." }
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: false, error: error },
                                                 { root: tc.pB.root_path, ok: false, error: error }],
                            data_dir: "/home/u/.local/share" }) + "\n"
  }

  // The next snapshot of every root, answered with `text`.
  function snapshot(app, text) {
    app.runs.refresh()
    reply(app.runs.snapshotRunner.current, text, 0)
  }

  // make() with the panel open and both snapshots answered with aRuns and
  // bRuns: make()'s, then the one the opening queued behind it. Armed, nothing raised.
  function openApp(aRuns, bRuns) {
    var app = make(); if (!app) return null
    app.panelOpen = true
    var text = listReply(aRuns, bRuns)
    reply(app.runs.snapshotRunner.current, text, 0)
    verify(app.runs.snapshotRunner.busy, "the opening queued a snapshot behind make()'s")
    reply(app.runs.snapshotRunner.current, text, 0)
    compare(app.runs.snapshotRunner.busy, false)
    return app
  }

  // run-control.py's ok reply.
  function ctlOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }
```

- [ ] **Step 2: Write the tests**

Append this block at the end of the file: after the last test (`test_a_project_filter_toggle_puts_the_cursor_home`), before the final `}` that closes `TestCase`, with one blank line before it.

```qml
  // ---- couplings between the run monitor's concerns, through App

  function test_a_snapshot_through_app_settles_a_pending_request() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.control("pause", "r1"), true)
    compare(app.runs.pending.r1, "pause")
    reply(app.runs.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.pending.r1, "pause", "am has it; a snapshot settles it")
    reply(app.runs.snapshotRunner.current,
          listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: null }])], []), 0)
    compare(app.runs.pending.r1, "pause", "not handled yet")
    snapshot(app, listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])], []))
    compare(app.runs.pending.r1, undefined, "the handled request is settled")
  }

  function test_a_snapshot_through_app_raises_one_toast_after_arming() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.toasts.length, 0, "the first snapshots only arm")
    compare(app.runs.alertsArmed, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runs.toasts.length, 1)
    compare(app.runs.toasts[0].id, "r1")
  }

  function test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.alertsArmed, true)
    snapshot(app, missingReply())
    compare(app.runs.amStatus, "missing")
    compare(app.runs.alertsArmed, false)
    compare(app.runs.runs.length, 0)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runs.toasts.length, 0, "the first good snapshot after am came back only arms")
    compare(app.runs.alertsArmed, true)
  }
```

- [ ] **Step 3: Run the whole file**

Run: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: 17 passed, 0 failed` (12 existing tests + 3 new + init/cleanup), no `FAIL` line and no error line.

- [ ] **Step 4: Prove each test can fail (the RED check)**

The production code already exists, so each test is green on its first run. For each test, make the temporary
edit below **in the test file**, run it alone, confirm FAIL, then undo the edit exactly. A test that does not
fail under its edit is rewritten until it does.

| test | temporary edit | expected FAIL |
|---|---|---|
| `test_a_snapshot_through_app_settles_a_pending_request` | last `compare(app.runs.pending.r1, undefined, …)` → `"pause"` | the handled request is settled |
| `test_a_snapshot_through_app_raises_one_toast_after_arming` | `compare(app.runs.toasts[0].id, "r1")` → `"r2"` | Compared values are not the same |
| `test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms` | first `compare(app.runs.alertsArmed, false)` → `true` | Compared values are not the same |

Run one test: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml StoresAppRuns::<test_name> 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"` (use `StoresRunStore::` and `tst_run_store.qml` for a
store-level test). After undoing every edit, `git diff tests/core/stores/` must show only the added code.

- [ ] **Step 5: Commit**

```bash
git add tests/core/stores/tst_app_runs.qml
git commit -m "test(runs): pin snapshot settle, toast and AmMissing couplings through App"
```

## Task 2: Control reply re-snapshots every root (tests 4-5 and the store twin)

**Files:**
- Modify: `tests/core/stores/tst_app_runs.qml`
- Modify: `tests/core/stores/tst_run_store.qml` (one test in `// ---- control and logs for a run of any project (3.5)`)

**Interfaces:**
- Consumes: Task 1's `openApp`, `runningIn`, `reply`, `ctlOk`. In `tst_run_store.qml`: the existing
  `crossStore(open, aRuns, bRuns)`, `running(id)`, `bWork(e)`, `ctlOk(data)`, `reply`, `argv`, `tc.snapCmd`,
  `tc.rootA`, `tc.rootB`.
- Produces: `tc.snapAll` (string), `argv(proc)` → string, `ctlFail(type, message)` → string.

- [ ] **Step 1: Add this task's fixture helpers**

In `tests/core/stores/tst_app_runs.qml`, insert this block immediately **before** the line
`  function test_app_composes_a_run_store_with_no_project_and_closed() {` (so helpers from earlier tasks stay above it, in task order), followed by one blank line:

```qml
  property string snapAll: "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj|/home/u/b"

  function argv(proc) { return proc.command.join("|") }

  // run-control.py's refusal.
  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }
```

- [ ] **Step 2: Write the tests**

Append this block at the end of the file, after the last test added by the previous task and before the final `}` that closes `TestCase`, with one blank line before it.

```qml
  function test_a_control_reply_through_app_snapshots_every_registered_root() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runs.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root, not only the run's")
  }

  function test_a_failed_control_reply_through_app_also_snapshots_every_root() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runs.controlRunners[0].current, ctlFail("NotAcceptingError", "run r1 is in integrate"), 0)
    compare(app.runs.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(app.runs.pending.r1, undefined)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll)
  }
```

- [ ] **Step 3: Write the store-level twin**

In `tests/core/stores/tst_run_store.qml`, insert this block immediately **before** these two lines
(they occur once):

```qml
  // Review Focus 2.
  function test_open_cancel_on_a_run_with_no_repository_flashes_why() {
```

```qml
  // A control reply re-snapshots every usable root, not only the run's.
  function test_a_control_reply_refreshes_every_usable_root() {
    var store = crossStore(rootA, [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(store.control("pause", "a1"), true)
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, ctlOk({ run_id: "a1", command: "pause", requested_at: "t1" }), 0)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }
```

- [ ] **Step 4: Run the whole file**

Run: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: 19 passed, 0 failed`, no `FAIL` line and no error line.

- [ ] **Step 5: Run the whole file**

Run: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: 305 passed, 0 failed` (302 existing + 1 new + init/cleanup), no `FAIL` line and no error line.

- [ ] **Step 6: Prove each test can fail (the RED check)**

The production code already exists, so each test is green on its first run. For each test, make the temporary
edit below **in the test file**, run it alone, confirm FAIL, then undo the edit exactly. A test that does not
fail under its edit is rewritten until it does.

| test | temporary edit | expected FAIL |
|---|---|---|
| `test_a_control_reply_through_app_snapshots_every_registered_root` | `compare(app.runs.snapshotRunner.seq, seq + 1, …)` → `seq + 2` | one snapshot |
| `test_a_failed_control_reply_through_app_also_snapshots_every_root` | last `compare(argv(…), tc.snapAll)` → `tc.snapAll + "|x"` | Compared values are not the same |
| `test_a_control_reply_refreshes_every_usable_root (store)` | `tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB` → `tc.snapCmd + "|" + tc.rootA` | Compared values are not the same |

Run one test: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml StoresAppRuns::<test_name> 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"` (use `StoresRunStore::` and `tst_run_store.qml` for a
store-level test). After undoing every edit, `git diff tests/core/stores/` must show only the added code.

- [ ] **Step 7: Commit**

```bash
git add tests/core/stores/tst_app_runs.qml tests/core/stores/tst_run_store.qml
git commit -m "test(runs): pin that a control reply re-snapshots every registered root"
```

## Task 3: Dispatch start re-snapshots every root and saves its settings (tests 6-7 and the store twin)

**Files:**
- Modify: `tests/core/stores/tst_app_runs.qml`
- Modify: `tests/core/stores/tst_run_store.qml` (one test in `// ---- dispatch (S3 3.1)`)

**Interfaces:**
- Consumes: Task 1's `make`, `reply`, `listReply`; Task 2's `argv`, `ctlFail`, `tc.snapAll`. In
  `tst_run_store.qml`: the existing `makeWithRoots`, `dispatchSettings`, `allReply`, `okEntry`,
  `dispatchCards`, `defaultsOk`, `previewOk`, `dispatchDryRun`, `startOk`.
- Produces: `tc.viewerCmd`, `dispatchSettings()`, `dispatchCards()`, `defaultsOk(branch)`, `previewOk(data)`,
  `dispatchDryRun()`, `startOk(runId, message)`, `readyApp()` → App with milestone m1's dispatch `ready`.

- [ ] **Step 1: Add this task's fixture helpers**

In `tests/core/stores/tst_app_runs.qml`, insert this block immediately **before** the line
`  function test_app_composes_a_run_store_with_no_project_and_closed() {` (so helpers from earlier tasks stay above it, in task order), followed by one blank line: (the fixture builders are copies of `tst_run_store.qml`'s, by design: each test file keeps its own small builders)

```qml
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // make() with pA's run settings read, make()'s snapshot answered with no
  // runs, and milestone m1's dispatch ready: its default branch read and its preview landed.
  function readyApp() {
    var app = make(); if (!app) return null
    reply(app.runs.runSettingsRunner.current, dispatchSettings(), 0)
    reply(app.runs.snapshotRunner.current, listReply([], []), 0)
    var cards = dispatchCards()
    compare(app.runs.openDispatch(cards.m1, cards), true)
    reply(app.runs.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(app.runs.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(app.runs.dispatchState, "ready")
    return app
  }
```

- [ ] **Step 2: Write the tests**

Append this block at the end of the file, after the last test added by the previous task and before the final `}` that closes `TestCase`, with one blank line before it.

```qml
  function test_a_dispatch_start_through_app_snapshots_every_registered_root() {
    var app = readyApp(); if (!app) return
    var spy = createTemporaryObject(spyC, tc, { target: app.runs, signalName: "dispatchStarted" })
    compare(app.runs.dispatchStart(), true)
    var runner = app.runs.dispatchStartRunners[0]
    var seq = app.runs.snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runs.dispatchState, "started")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root, not only the started run's")
    var save = runner.current
    compare(save.command.length, 5)
    compare(save.command.slice(0, 4).join("|"), tc.viewerCmd + "set-run-settings|/home/u/my proj")
  }

  function test_a_dispatch_settings_save_failure_through_app_flashes() {
    var app = readyApp(); if (!app) return
    compare(app.runs.dispatchStart(), true)
    var runner = app.runs.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runs.flashText, "")
    reply(runner.current, ctlFail("Invalid", "x"), 1)
    compare(app.runs.flashText, "Dispatch settings could not be saved")
    compare(app.runs.dispatchState, "started", "the run still started")
    compare(app.runs.dispatchStartRunners.length, 0)
  }
```

- [ ] **Step 3: Write the store-level twin**

In `tests/core/stores/tst_run_store.qml`, insert this block immediately **before** these two lines
(they occur once):

```qml
  // 30
  function test_settings_write_failure_flashes() {
```

```qml
  // A start re-snapshots every usable root, not only the project it was made in.
  function test_a_dispatch_start_refreshes_every_usable_root() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    store.project = rootA
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var seq = store.snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }
```

- [ ] **Step 4: Run the whole file**

Run: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: 21 passed, 0 failed`, no `FAIL` line and no error line.

- [ ] **Step 5: Run the whole file**

Run: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: 306 passed, 0 failed`, no `FAIL` line and no error line.

- [ ] **Step 6: Prove each test can fail (the RED check)**

The production code already exists, so each test is green on its first run. For each test, make the temporary
edit below **in the test file**, run it alone, confirm FAIL, then undo the edit exactly. A test that does not
fail under its edit is rewritten until it does.

| test | temporary edit | expected FAIL |
|---|---|---|
| `test_a_dispatch_start_through_app_snapshots_every_registered_root` | `compare(spy.signalArguments[0][0], "r-1")` → `"r-2"` | Compared values are not the same |
| `test_a_dispatch_settings_save_failure_through_app_flashes` | `"Dispatch settings could not be saved"` → `"x"` | Compared values are not the same |
| `test_a_dispatch_start_refreshes_every_usable_root (store)` | `seq + 1, "one snapshot"` → `seq, "one snapshot"` | one snapshot |

Run one test: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml StoresAppRuns::<test_name> 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"` (use `StoresRunStore::` and `tst_run_store.qml` for a
store-level test). After undoing every edit, `git diff tests/core/stores/` must show only the added code.

- [ ] **Step 7: Commit**

```bash
git add tests/core/stores/tst_app_runs.qml tests/core/stores/tst_run_store.qml
git commit -m "test(runs): pin that a dispatch start re-snapshots every root and flashes a failed save"
```

## Task 4: Lifecycle couplings through App (tests 8-12)

**Files:**
- Modify: `tests/core/stores/tst_app_runs.qml`

**Interfaces:**
- Consumes: Task 1's `make`, `openApp`, `reply`, `runEntry`, `runningIn`, `escalatedIn`, `listReply`,
  `snapshot`; Task 2's `argv`; Task 3's `tc.viewerCmd`, `dispatchSettings`, `dispatchCards`, `defaultsOk`.
- Produces: `tc.notifyCmd`.

- [ ] **Step 1: Add this task's fixture helpers**

In `tests/core/stores/tst_app_runs.qml`, insert this block immediately **before** the line
`  function test_app_composes_a_run_store_with_no_project_and_closed() {` (so helpers from earlier tasks stay above it, in task order), followed by one blank line:

```qml
  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"
```

- [ ] **Step 2: Write the tests**

Append this block at the end of the file, after the last test added by the previous task and before the final `}` that closes `TestCase`, with one blank line before it.

```qml

  function test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    reply(app.runs.runSettingsRunner.current, dispatchSettings(), 0)
    compare(app.runs.runSettings.parallelism, 4)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runs.toasts.length, 1)
    compare(app.runs.control("pause", "r2"), true)
    app.runs.flash("kept")
    var cards = dispatchCards()
    compare(app.runs.openDispatch(cards.m1, cards), true)
    reply(app.runs.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(app.runs.dispatchState, "previewing")
    var seq = app.runs.snapshotRunner.seq
    app.projects.chooseProject(pB)
    compare(app.runs.dispatchState, "idle")
    compare(Object.keys(app.runs.runSettings).length, 0)
    compare(argv(app.runs.runSettingsRunner.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(app.runs.toasts.length, 1, "the toast stays")
    compare(app.runs.toasts[0].id, "r1")
    compare(app.runs.pending.r2, "pause", "the request stays")
    compare(app.runs.flashText, "kept", "the flash stays")
    compare(app.runs.snapshotRunner.seq, seq, "no snapshot is launched")
  }
  function test_opening_the_panel_through_app_reads_the_notify_switch() {
    var app = make(); if (!app) return
    verify(!app.runs.settingsLoadRunner.current, "a closed panel reads nothing")
    app.runs.setNotifyOnEscalation(false)
    compare(app.runs.notifyTouched, true)
    reply(app.runs.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    app.panelOpen = true
    compare(argv(app.runs.settingsLoadRunner.current), tc.viewerCmd + "get-global-settings")
    compare(app.runs.notifyTouched, false, "the opening's load is not too late")
    reply(app.runs.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runs.notifyOnEscalation, true)
  }
  function test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runs.toasts.length, 1)
    var cards = dispatchCards()
    compare(app.runs.openDispatch(cards.m1, cards), true)
    compare(app.runs.dispatchState, "previewing")
    app.panelOpen = false
    compare(app.runs.toasts.length, 0)
    compare(app.runs.alertsArmed, false)
    compare(app.runs.dispatchState, "idle")
  }
  function test_an_escalation_through_app_notifies_only_with_the_switch_on() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    compare(app.runs.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runs.toasts.length, 1)
    compare(app.runs.notifyRunners.length, 0, "the switch is off: a toast only")
    reply(app.runs.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runs.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runs.toasts.length, 2)
    compare(app.runs.notifyRunners.length, 1, "one notification, for r2")
    compare(argv(app.runs.notifyRunners[0].current), tc.notifyCmd + "m-r2|escalated")
  }
  function test_a_project_leaving_the_registry_through_app_loses_its_arming() {
    var app = openApp([runningIn("a1")], [runningIn("b1", tc.pB.root_path)]); if (!app) return
    compare(Object.keys(app.runs.armedRoots).sort().join(","), [tc.pA.root_path, tc.pB.root_path].sort().join(","))
    app.projects.applyProjectsList([pA])
    compare(Object.keys(app.runs.armedRoots).join(","), tc.pA.root_path, "pB's arming goes with it")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("a1")], null), 0)
    app.projects.applyProjectsList([pA, pB])
    reply(app.runs.snapshotRunner.current, listReply([escalatedIn("a1")], [escalatedIn("b1", tc.pB.root_path)]), 0)
    compare(app.runs.toasts.length, 1, "pB's first entry back only re-arms it")
    compare(app.runs.toasts[0].id, "a1", "pA stayed armed")
    compare(Object.keys(app.runs.armedRoots).length, 2)
  }
```

- [ ] **Step 3: Run the whole file**

Run: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: 26 passed, 0 failed` (12 existing + 12 new + init/cleanup), no `FAIL` line and no error line.

- [ ] **Step 4: Prove each test can fail (the RED check)**

The production code already exists, so each test is green on its first run. For each test, make the temporary
edit below **in the test file**, run it alone, confirm FAIL, then undo the edit exactly. A test that does not
fail under its edit is rewritten until it does.

| test | temporary edit | expected FAIL |
|---|---|---|
| `test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` | `compare(app.runs.dispatchState, "idle")` → `"previewing"` | Compared values are not the same |
| `test_opening_the_panel_through_app_reads_the_notify_switch` | `compare(app.runs.notifyTouched, false, …)` → `true` | the opening's load is not too late |
| `test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` | last `compare(app.runs.dispatchState, "idle")` → `"previewing"` | Compared values are not the same |
| `test_an_escalation_through_app_notifies_only_with_the_switch_on` | `compare(app.runs.notifyRunners.length, 1, …)` → `2` | one notification, for r2 |
| `test_a_project_leaving_the_registry_through_app_loses_its_arming` | `compare(app.runs.toasts.length, 1, …)` → `2` | pB's first entry back only re-arms it |

Run one test: `QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml StoresAppRuns::<test_name> 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"` (use `StoresRunStore::` and `tst_run_store.qml` for a
store-level test). After undoing every edit, `git diff tests/core/stores/` must show only the added code.

- [ ] **Step 5: Commit**

```bash
git add tests/core/stores/tst_app_runs.qml
git commit -m "test(runs): pin project switch, panel open/close, notify and registry couplings through App"
```

## Task 5: Appendix A and the full gate

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-split-runstore-design.md` (from the line `## Appendix A — member mapping` to the end of the file; that heading is the file's last section)

**Interfaces:**
- Consumes: every test name added by Tasks 1-4, exactly as written there.
- Produces: Appendix A (A.1-A.4) that the later split subtasks read to move members and tests.

- [ ] **Step 1: Re-grep the member list**

Run: `grep -cE '^  (readonly )?(property|signal|function)|^  on[A-Z]|^  (HelperRunner|Timer|QtObject|Component) \{' core/stores/RunStore.qml`
Expected: `225`. If it differs, or `grep -n` shows a line other than the one in the A.1 row, correct the line
numbers (never the target) in the text below before pasting; a new member is mapped with the
responsibilities table (parent spec l.52-57) with a one-clause reason in its row.

- [ ] **Step 2: Replace the appendix**

In `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, replace everything from the line
`## Appendix A — member mapping` to the end of the file with exactly this text (it keeps the heading),
ending with a single newline:

````markdown
## Appendix A — member mapping

Built from `core/stores/RunStore.qml` at the commit of subtask 1.1 (2038 lines). Line numbers are that
file's. Test names are `file::test_name`, with the file relative to `tests/`; `(added)` marks a test
subtask 1.1 added.

### A.1 Member map

One row per top-level declaration of the root `Scope`: 225 rows, the count of
`grep -nE '^  (readonly )?(property|signal|function)|^  on[A-Z]|^  (HelperRunner|Timer|QtObject|Component) \{' core/stores/RunStore.qml`.
A child item is listed under its `id`; the readonly alias that exposes it is its own row of kind
`alias`, mapped to the same store.

| member | line | kind | target | tests that cover it |
|---|---|---|---|---|
| `projectRoots` | 41 | input property | RunStore | `core/stores/tst_app_runs.qml::test_project_roots_follow_the_registry` |
| `project` | 42 | input property | RunStore | `core/stores/tst_app_runs.qml::test_the_project_is_the_selected_root_path_string` |
| `backendDir` | 43 | input property | RunStore | `core/stores/tst_app_runs.qml::test_the_backend_dir_follows_app` |
| `active` | 44 | input property | RunStore | `core/stores/tst_app_runs.qml::test_active_follows_panel_open` |
| `runsByProject` | 49 | property | RunStore | `core/stores/tst_run_store.qml::test_runs_merge_every_root_in_registry_order_with_its_project` |
| `projectErrors` | 51 | property | RunStore | `core/stores/tst_run_store.qml::test_a_failing_root_keeps_its_runs_and_says_why` |
| `runs` | 54 | property | RunStore | `core/stores/tst_run_store.qml::test_runs_merge_every_root_in_registry_order_with_its_project` |
| `selectedRunId` | 55 | property | RunStore | `core/stores/tst_run_store.qml::test_selecting_a_run_fetches_its_default_attempt` |
| `amStatus` | 56 | property | RunStore | `core/stores/tst_run_store.qml::test_am_missing_sets_missing_and_clears_the_runs` |
| `amSchema` | 57 | property | RunStore | `core/stores/tst_run_store.qml::test_hello_sets_schema_and_version` |
| `amVersion` | 58 | property | RunStore | `core/stores/tst_run_store.qml::test_hello_sets_schema_and_version` |
| `lastError` | 59 | property | RunStore | `core/stores/tst_run_store.qml::test_garbage_stdout_keeps_the_previous_runs_and_names_the_exit_code` |
| `stale` | 60 | property | RunStore | `core/stores/tst_run_store.qml::test_stale_after_timer_fires` |
| `watchWarning` | 61 | property | RunStore | `core/stores/tst_run_store.qml::test_corrupt_journal_sets_warning_and_polls` |
| `runFilter` | 66 | property | RunStore | `core/stores/tst_run_store.qml::test_toggle_run_filter_and_back_to_all` |
| `searchQuery` | 67 | input property | RunStore | `core/stores/tst_app_runs.qml::test_the_search_query_follows_the_navigation_store`<br>`core/stores/tst_run_store.qml::test_filtered_runs_follow_the_filter_and_the_search` |
| `runFilterToggled` | 69 | signal | RunStore | `core/stores/tst_run_store.qml::test_toggle_run_filter_and_back_to_all`<br>`core/stores/tst_app_runs.qml::test_a_filter_change_puts_the_cursor_home` |
| `projectFilter` | 74 | property | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal` |
| `projectFilterToggled` | 77 | signal | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal`<br>`core/stores/tst_app_runs.qml::test_a_project_filter_toggle_puts_the_cursor_home` |
| `groups` | 80 | readonly property | RunStore | `core/stores/tst_run_store.qml::test_the_list_reads_project_by_project_in_display_order` |
| `filteredRuns` | 83 | readonly property | RunStore | `core/stores/tst_run_store.qml::test_filtered_runs_follow_the_filter_and_the_search` |
| `asOfSeq` | 88 | property | RunStore | `core/stores/tst_run_store.qml::test_am_missing_in_every_entry_empties_everything` |
| `appliedSeq` | 89 | property | RunStore | `core/stores/tst_run_store.qml::test_a_list_reply_lists_the_roots_runs_and_covers_them_at_0` |
| `watchCursor` | 91 | property | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_line_sets_the_watch_cursor` |
| `nudges` | 94 | property | RunStore | `core/stores/tst_run_store.qml::test_nudges_keep_the_highest_seq_per_run` |
| `storeId` | 98 | property | RunStore | `core/stores/tst_run_store.qml::test_a_store_id_starts_as_none` |
| `watchTried` | 105 | property | RunStore | `core/stores/tst_run_store.qml::test_with_no_absolute_root_no_watch_is_launched`<br>`core/stores/tst_run_store.qml::test_reactivation_starts_a_new_watch` |
| `watchSeq` | 106 | property | RunStore | `core/stores/tst_run_store.qml::test_with_no_absolute_root_no_watch_is_launched` |
| `watchSchemaError` | 107 | property | RunStore | `core/stores/tst_run_store.qml::test_schema_banner_survives_poll_snapshots` |
| `selectedAttempt` | 111 | property | RunStore | `core/stores/tst_run_store.qml::test_selecting_a_run_fetches_its_default_attempt` |
| `logsText` | 112 | property | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `logsTruncated` | 113 | property | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `logsFetchedMs` | 114 | property | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `logsLoading` | 115 | property | RunStore | `core/stores/tst_run_store.qml::test_logs_defaults` |
| `logsError` | 116 | property | RunStore | `core/stores/tst_run_store.qml::test_logs_failures_keep_the_text_and_never_touch_am_status` |
| `logsStatus` | 117 | property | RunStore | `core/stores/tst_run_store.qml::test_a_snapshot_that_changes_the_attempt_status_fetches_once` |
| `pending` | 124 | property | RunControlStore | `core/stores/tst_run_store.qml::test_control_sets_pending_as_a_new_object` |
| `stillWaiting` | 125 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_request_is_still_waiting_after_30_seconds` |
| `stillWaitingText` | 126 | readonly property | RunControlStore | `core/stores/tst_run_store.qml::test_control_defaults` |
| `lastControlError` | 127 | property | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_false_reply_clears_pending_and_says_why` |
| `lastControlErrorRunId` | 128 | property | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_false_reply_clears_pending_and_says_why` |
| `cancelRunId` | 133 | property | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `cancelOpen` | 134 | readonly property | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `cancelText` | 135 | property | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `cancelError` | 136 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm` |
| `flashText` | 138 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `armedRoots` | 149 | property | RunAlertsStore | `core/stores/tst_run_store.qml::test_a_root_that_leaves_the_registry_loses_its_arming` |
| `alertsArmed` | 150 | readonly property | RunAlertsStore | `core/stores/tst_run_store.qml::test_am_missing_disarms_and_a_failed_snapshot_does_not` |
| `toasts` | 151 | property | RunAlertsStore | `core/stores/tst_run_store.qml::test_a_run_that_turns_escalated_raises_one_toast` |
| `toastMs` | 152 | property | RunAlertsStore | `core/stores/tst_run_store.qml::test_a_run_that_turns_escalated_raises_one_toast`<br>`core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `notifyOnEscalation` | 158 | property | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `notifySaved` | 159 | property | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `notifyTouched` | 160 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_load_reply_after_the_user_toggled_is_ignored` |
| `runSettings` | 165 | property | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `dispatchState` | 173 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_dispatch_starts_idle` |
| `dispatchTarget` | 174 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchTargetLabel` | 175 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_sets_the_target_label` |
| `dispatchForm` | 176 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchPreview` | 177 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_preview_ok_goes_ready_with_summary` |
| `dispatchError` | 178 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_preview_refusal_goes_refused_verbatim` |
| `dispatchErrorType` | 179 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_done_card_is_refused` |
| `dispatchErrors` | 180 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_invalid_form_is_refused_without_launch` |
| `dispatchSuggest` | 181 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_from_a_blocked_preview` |
| `dispatchRunId` | 182 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `dispatchMessage` | 183 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `dispatchLog` | 184 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_failure_goes_failed_with_log` |
| `dispatchLogTail` | 185 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_failure_goes_failed_with_log` |
| `dispatchExitCode` | 186 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_failure_goes_failed_with_log` |
| `dispatchStarted` | 189 | signal | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `runsNudged` | 193 | signal | RunStore | `core/stores/tst_run_store.qml::test_a_debounce_firing_announces_its_run_ids_once` |
| `watching` | 195 | alias | RunStore | `core/stores/tst_app_runs.qml::test_panel_close_through_app_stops_the_watch` |
| `watchProc` | 196 | alias | RunStore | `core/stores/tst_app_runs.qml::test_panel_close_through_app_stops_the_watch` |
| `watchRoots` | 197 | alias | RunStore | `core/stores/tst_run_store.qml::test_a_reordered_or_renamed_registry_keeps_the_watch` |
| `snapshotRunner` | 198 | alias | RunStore | `core/stores/tst_app_runs.qml::test_the_snapshot_names_every_registered_root` |
| `snapshotRoots` | 199 | alias | RunStore | `core/stores/tst_run_store.qml::test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| `pendingSnapshot` | 200 | alias | RunStore | `core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `debounceTimer` | 202 | alias | RunStore | `core/stores/tst_run_store.qml::test_changed_line_starts_debounce` |
| `livenessTimer` | 203 | alias | RunStore | `core/stores/tst_run_store.qml::test_liveness_on_with_running_run` |
| `staleTimer` | 204 | alias | RunStore | `core/stores/tst_run_store.qml::test_stale_timer_runs_only_while_active` |
| `pollTimer` | 205 | alias | RunStore | `core/stores/tst_run_store.qml::test_schema_mismatch_falls_back_to_poll` |
| `logsRunner` | 206 | alias | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `controlRunners` | 207 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_a_finished_request_leaves_control_runners` |
| `pendingTimer` | 208 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_the_pending_timer_runs_only_while_active_with_something_pending` |
| `flashTimer` | 209 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `toastTimer` | 210 | alias | RunAlertsStore | `core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `settingsLoadRunner` | 211 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `settingsSaveRunner` | 212 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `runSettingsRunner` | 213 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `notifyRunners` | 214 | alias | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dispatchDefaultsRunner` | 215 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchPreviewRunner` | 216 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_defaults_reply_sets_base_and_launches_preview` |
| `dispatchDebounceTimer` | 217 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_restarts_400ms_debounce_and_one_preview_per_burst` |
| `dispatchStartRunners` | 218 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `hasRunningRun` | 222 | readonly property | RunStore | `core/stores/tst_run_store.qml::test_liveness_on_with_running_run`<br>`core/stores/tst_run_store.qml::test_liveness_off_without_running_run` |
| `refresh` | 234 | function | RunStore | `core/stores/tst_run_store.qml::test_the_snapshot_names_every_usable_root_in_registry_order` |
| `requestSnapshot` | 249 | function | RunStore | `core/stores/tst_run_store.qml::test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| `launchSnapshot` | 268 | function | RunStore | `core/stores/tst_run_store.qml::test_a_pending_set_of_roots_launches_those_roots_in_registry_order` |
| `dropSnapshots` | 281 | function | RunStore | `core/stores/tst_run_store.qml::test_an_emptied_registry_drops_the_snapshot_in_flight_and_the_pending_request` |
| `snapshotEnded` | 289 | function | RunStore | `core/stores/tst_run_store.qml::test_a_failed_or_garbage_reply_still_launches_the_pending_request` |
| `toggleRunFilter` | 299 | function | RunStore | `core/stores/tst_run_store.qml::test_toggle_run_filter_and_back_to_all` |
| `toggleProjectFilter` | 307 | function | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal` |
| `projectRootOf` | 316 | function | RunStore | `core/stores/tst_run_store.qml::test_a_root_registered_with_a_trailing_slash_is_filtered_by_either_spelling` |
| `isFilterable` | 323 | function | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal` |
| `keepProjectFilter` | 343 | function | RunStore | `core/stores/tst_run_store.qml::test_the_registry_dropping_the_filtered_root_falls_back_to_all` |
| `onRunsChanged` | 349 | handler | RunStore | `core/stores/tst_run_store.qml::test_a_reply_that_leaves_the_project_without_runs_falls_back_to_all` |
| `onActiveChanged` | 351 | handler | RunStore | `core/stores/tst_app_runs.qml::test_active_follows_panel_open`<br>`core/stores/tst_run_store.qml::test_activation_refreshes_every_root` |
| `startLive` | 360 | function | RunStore | `core/stores/tst_run_store.qml::test_activation_refreshes_every_root`<br>`core/stores/tst_app_runs.qml::test_opening_the_panel_through_app_reads_the_notify_switch` (added) |
| `stopLive` | 375 | function | RunStore | `core/stores/tst_run_store.qml::test_deactivate_kills_watch_and_timers`<br>`core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (added) |
| `restartStale` | 392 | function | RunStore | `core/stores/tst_run_store.qml::test_stale_timer_runs_only_while_active` |
| `stopWatch` | 399 | function | RunStore | `core/stores/tst_run_store.qml::test_deactivate_kills_watch_and_timers` |
| `startWatch` | 412 | function | RunStore | `core/stores/tst_run_store.qml::test_watch_argv_after_first_snapshot` |
| `watchableRoots` | 428 | function | RunStore | `core/stores/tst_run_store.qml::test_with_no_absolute_root_no_watch_is_launched` |
| `knownRunIds` | 437 | function | RunStore | `core/stores/tst_run_store.qml::test_the_watch_names_every_root_then_every_known_run_id` |
| `sameRoots` | 455 | function | RunStore | `core/stores/tst_run_store.qml::test_a_reordered_or_renamed_registry_keeps_the_watch` |
| `isCurrentWatch` | 466 | function | RunStore | `core/stores/tst_run_store.qml::test_old_watch_hello_ignored`<br>`core/stores/tst_run_store.qml::test_killed_watch_lines_ignored_after_deactivation` |
| `watchLine` | 481 | function | RunStore | `core/stores/tst_run_store.qml::test_changed_line_starts_debounce`<br>`core/stores/tst_run_store.qml::test_garbage_watch_line_ignored` |
| `recordNudges` | 504 | function | RunStore | `core/stores/tst_run_store.qml::test_invalid_changed_entries_are_ignored` |
| `triggerNudges` | 523 | function | RunStore | `core/stores/tst_run_store.qml::test_a_debounce_firing_announces_its_run_ids_once` |
| `listsRun` | 546 | function | RunStore | `core/stores/tst_run_store.qml::test_a_nudge_refreshes_only_the_roots_that_list_its_runs` |
| `refreshLive` | 556 | function | RunStore | `core/stores/tst_run_store.qml::test_a_liveness_tick_refreshes_only_the_roots_with_a_running_run` |
| `resetCursor` | 575 | function | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_reset_starts_over_from_a_list_snapshot` |
| `forgetLive` | 587 | function | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_reset_starts_over_from_a_list_snapshot` |
| `seeStore` | 600 | function | RunStore | `core/stores/tst_run_store.qml::test_the_first_store_id_a_hello_names_resets_nothing`<br>`core/stores/tst_run_store.qml::test_a_hello_from_another_store_starts_over_from_a_list_snapshot` |
| `forgetHello` | 608 | function | RunStore | `core/stores/tst_run_store.qml::test_hello_reset_on_deactivate` |
| `watchExited` | 618 | function | RunStore | `core/stores/tst_run_store.qml::test_other_watch_error_stops_watching_without_poll` |
| `startPoll` | 640 | function | RunStore | `core/stores/tst_run_store.qml::test_schema_mismatch_falls_back_to_poll` |
| `stopPoll` | 644 | function | RunStore | `core/stores/tst_run_store.qml::test_poll_stops_on_deactivate` |
| `projectSwitched` | 655 | function | RunControlStore | `core/stores/tst_run_store.qml::test_project_switch_resets_dispatch_and_drops_old_preview`<br>`core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `onProjectChanged` | 664 | handler | RunControlStore | `core/stores/tst_app_runs.qml::test_the_project_is_the_selected_root_path_string`<br>`core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `usableRoots` | 670 | function | RunStore | `core/stores/tst_run_store.qml::test_the_snapshot_names_every_usable_root_in_registry_order` |
| `taggedByProject` | 689 | function | RunStore | `core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `mergedRuns` | 708 | function | RunStore | `core/stores/tst_run_store.qml::test_a_run_listed_under_two_roots_is_listed_once_under_the_first` |
| `registryChanged` | 731 | function | RunStore | `core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `onProjectRootsChanged` | 748 | handler | RunStore | `core/stores/tst_app_runs.qml::test_project_roots_follow_the_registry`<br>`core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `runById` | 753 | function | RunStore | `core/stores/tst_run_store.qml::test_refusal_of_says_why_a_control_would_not_start` |
| `runRoot` | 762 | function | RunStore | `core/stores/tst_run_store.qml::test_logs_argv_leads_with_the_runs_project_root` |
| `selectAttempt` | 772 | function | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `refreshLogs` | 788 | function | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `fetchLogs` | 796 | function | RunStore | `core/stores/tst_run_store.qml::test_no_logs_launch_without_a_run_or_a_selection` |
| `clearLogs` | 808 | function | RunStore | `core/stores/tst_run_store.qml::test_changing_the_selected_run_resets_to_its_default_attempt` |
| `openDefaultAttempt` | 820 | function | RunStore | `core/stores/tst_run_store.qml::test_selecting_a_run_fetches_its_default_attempt` |
| `logsAfterSnapshot` | 829 | function | RunStore | `core/stores/tst_run_store.qml::test_a_snapshot_that_changes_the_attempt_status_fetches_once` |
| `onSelectedRunIdChanged` | 841 | handler | RunStore | `core/stores/tst_run_store.qml::test_changing_the_selected_run_resets_to_its_default_attempt` |
| `applyLogs` | 850 | function | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `lastLine` | 870 | function | core/domain | `core/stores/tst_run_store.qml::test_the_last_non_empty_line_is_the_reply` |
| `parseEnvelope` | 880 | function | core/domain | `core/stores/tst_run_store.qml::test_json_that_is_not_an_envelope_is_an_error` |
| `rowOf` | 891 | function | RunStore | `core/stores/tst_run_store.qml::test_an_ok_reply_fills_runs_with_normalized_runs` |
| `isSeq` | 900 | function | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_line_sets_the_watch_cursor` |
| `applySnapshot` | 909 | function | RunStore | `core/stores/tst_run_store.qml::test_a_whole_call_failure_or_garbage_keeps_everything` |
| `applyProjects` | 939 | function | RunStore | `core/stores/tst_run_store.qml::test_a_failing_root_keeps_its_runs_and_says_why`<br>`core/stores/tst_run_store.qml::test_am_missing_in_every_entry_empties_everything` |
| `alertsOf` | 1056 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_an_escalation_in_another_project_raises_one_toast_with_its_project` |
| `copyMap` | 1080 | function | core/domain | `core/stores/tst_run_store.qml::test_control_sets_pending_as_a_new_object` |
| `hasKey` | 1088 | function | core/domain | `core/stores/tst_run_store.qml::test_a_run_listed_under_two_roots_is_listed_once_under_the_first` |
| `control` | 1096 | function | RunControlStore | `core/stores/tst_run_store.qml::test_pause_and_cancel_launch_the_exact_argv` |
| `launchControl` | 1125 | function | RunControlStore | `core/stores/tst_run_store.qml::test_pause_and_cancel_launch_the_exact_argv` |
| `requestOf` | 1133 | function | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_reply_keeps_pending_and_refreshes`<br>`core/stores/tst_run_store.qml::test_two_runs_in_flight_at_once_both_apply` |
| `settle` | 1141 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled` |
| `failControl` | 1161 | function | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_false_reply_clears_pending_and_says_why` |
| `dismissControlError` | 1167 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_new_request_and_dismiss_clear_the_control_error` |
| `dropRunner` | 1173 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_finished_request_leaves_control_runners` |
| `controlReplied` | 1183 | function | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_reply_keeps_pending_and_refreshes`<br>`core/stores/tst_app_runs.qml::test_a_control_reply_through_app_snapshots_every_registered_root` (added) |
| `resumeWithSettings` | 1216 | function | RunControlStore | `core/stores/tst_run_store.qml::test_milestone_resume_reads_the_settings_then_passes_the_verify_set` |
| `settleAfterSnapshot` | 1244 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_settles_a_pending_request` (added) |
| `isHandled` | 1259 | function | RunControlStore | `core/stores/tst_run_store.qml::test_without_requested_at_the_last_request_of_that_command_decides` |
| `checkWaiting` | 1271 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_request_is_still_waiting_after_30_seconds` |
| `refusalOf` | 1287 | function | RunControlStore | `core/stores/tst_run_store.qml::test_refusal_of_says_why_a_control_would_not_start` |
| `flash` | 1299 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `openCancel` | 1307 | function | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `closeCancel` | 1319 | function | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run`<br>`core/stores/tst_run_store.qml::test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm` |
| `confirmCancel` | 1328 | function | RunControlStore | `core/stores/tst_run_store.qml::test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes` |
| `raiseAlerts` | 1349 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_five_alerts_in_one_snapshot_leave_the_last_three_toasts` |
| `expireToasts` | 1364 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `dismissToast` | 1370 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties` |
| `dismissAllToasts` | 1375 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties` |
| `notify` | 1382 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dropNotifyRunner` | 1388 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `setNotifyOnEscalation` | 1395 | function | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `applyGlobalSettings` | 1407 | function | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `applyRunSettings` | 1417 | function | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `notifySaveReplied` | 1424 | function | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `clearDispatchError` | 1437 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_failed_then_change_previews_again` |
| `resetDispatch` | 1450 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_close_and_reopen_drop_the_pending_lookup`<br>`core/stores/tst_run_store.qml::test_project_switch_resets_dispatch_and_drops_old_preview` |
| `openDispatch` | 1478 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `closeDispatch` | 1505 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_close_and_reopen_drop_the_pending_lookup` |
| `blockedSuggest` | 1514 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_from_a_blocked_preview` |
| `retargetToMilestone` | 1523 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_from_a_blocked_preview`<br>`core/stores/tst_run_store.qml::test_retarget_refused_outside_a_blocked_refusal` |
| `withField` | 1530 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_after_ready_drops_preview_and_goes_previewing` |
| `dispatchTargetArgs` | 1537 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_board_preview_argv` |
| `dispatchCommands` | 1543 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `dispatchOptionArgs` | 1550 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_allow_no_verification_flag`<br>`core/stores/tst_run_store.qml::test_defaults_failure_sends_no_base` |
| `dispatchDefaultsReplied` | 1565 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_defaults_reply_sets_base_and_launches_preview` |
| `checkDispatch` | 1579 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_invalid_form_is_refused_without_launch`<br>`core/stores/tst_run_store.qml::test_subtask_goes_ready_without_preview` |
| `dispatchPreviewReplied` | 1603 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_preview_ok_goes_ready_with_summary` |
| `setDispatchField` | 1638 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_restarts_400ms_debounce_and_one_preview_per_burst` |
| `mergedPrefixes` | 1656 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_a_story_start_saves_the_prefix_under_its_milestone`<br>`core/stores/tst_run_store.qml::test_a_stored_map_that_is_not_an_object_merges_from_nothing` |
| `dispatchStart` | 1669 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `isHereStart` | 1698 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_reply_after_switching_away_and_back_is_not_here` |
| `dispatchStartReplied` | 1709 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves`<br>`core/stores/tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` (added) |
| `dispatchSaveReplied` | 1757 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_settings_write_failure_flashes` |
| `dropStartRunner` | 1764 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_settings_write_failure_flashes` |
| `snapshotRunner` | 1773 | runner | RunStore | `core/stores/tst_run_store.qml::test_the_snapshot_names_every_usable_root_in_registry_order` |
| `logsRunner` | 1782 | runner | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `settingsLoadRunner` | 1792 | runner | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `runSettingsRunner` | 1803 | runner | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `settingsSaveRunner` | 1812 | runner | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `dispatchDefaultsRunner` | 1821 | runner | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchPreviewRunner` | 1829 | runner | RunDispatchStore | `core/stores/tst_run_store.qml::test_defaults_reply_sets_base_and_launches_preview` |
| `debounceTimer` | 1837 | timer | RunStore | `core/stores/tst_run_store.qml::test_changed_line_starts_debounce` |
| `livenessTimer` | 1847 | timer | RunStore | `core/stores/tst_run_store.qml::test_liveness_on_with_running_run` |
| `staleTimer` | 1857 | timer | RunStore | `core/stores/tst_run_store.qml::test_stale_timer_runs_only_while_active` |
| `pollTimer` | 1866 | timer | RunStore | `core/stores/tst_run_store.qml::test_schema_mismatch_falls_back_to_poll` |
| `pendingTimer` | 1876 | timer | RunControlStore | `core/stores/tst_run_store.qml::test_the_pending_timer_runs_only_while_active_with_something_pending` |
| `flashTimer` | 1886 | timer | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `toastTimer` | 1895 | timer | RunAlertsStore | `core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `dispatchDebounceTimer` | 1905 | timer | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_restarts_400ms_debounce_and_one_preview_per_burst` |
| `watchState` | 1915 | state object | RunStore | `core/stores/tst_app_runs.qml::test_panel_close_through_app_stops_the_watch` |
| `snapshotState` | 1925 | state object | RunStore | `core/stores/tst_run_store.qml::test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| `controlState` | 1935 | state object | RunControlStore | `core/stores/tst_run_store.qml::test_a_finished_request_leaves_control_runners` |
| `toastState` | 1943 | state object | RunAlertsStore | `core/stores/tst_run_store.qml::test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties` |
| `notifyState` | 1949 | state object | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dispatchBook` | 1960 | state object | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_goes_once_to_the_milestone_recorded_at_the_opening` |
| `controlC` | 1974 | component | RunControlStore | `core/stores/tst_run_store.qml::test_pause_and_cancel_launch_the_exact_argv` |
| `notifyC` | 1991 | component | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dispatchStartC` | 2007 | component | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `watchC` | 2022 | component | RunStore | `core/stores/tst_run_store.qml::test_watch_argv_after_first_snapshot` |

### A.2 Not present at this commit

| member or section | from milestone | target | note |
|---|---|---|---|
| `dispatchRoot` | Dispatch from the Runs screen | RunDispatchStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `// ---- dispatch: project and target steps` (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, their two `board-tree.py` runners) | Dispatch from the Runs screen | RunDispatchStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| a Runs-opened start's `started` refreshing `[dispatchRoot]` only | Dispatch from the Runs screen | RunDispatchStore (`refreshRequested`) | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `// ---- relaunch` (`relaunchOpenFor`, `relaunch*`) | Resume and recover | RunDispatchStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `// ---- resume dialog` (`resume*`, `resumeOpenFor`, `resumeClose`, `resumeConfirm`, `resumeSaveRunner`) | Resume and recover | RunControlStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `lastControlErrorType` | Resume and recover | RunControlStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| the stopped-run attempt choice | Resume and recover | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| the events state | S5 | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `runsChanged(ids)` | S6 / milestone 4 | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `snapshotReplied(root, outcome, previousRuns, runs)` | this milestone (new, rule 3) | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| the persisted `gseq` alert cursor | Alerts while the panel is closed | RunAlertsStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |

### A.3 Cross-concern calls

| caller (line) | callee or effect (line) | from → to | App route | pinned by |
|---|---|---|---|---|
| `applyProjects` (939) | `settleAfterSnapshot()` (1026) | RunStore → Control | `snapshotReplied` outcome `ok` → `runControl.settleAfterSnapshot()`, first in the handler | `core/stores/tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_settles_a_pending_request` (added) |
| `applyProjects` (939) | `alertsOf(…)` (1015), only while `active` | RunStore → Alerts | `snapshotReplied(root, outcome, previousRuns, runs)` → `runAlerts.snapshotReplied(…)` | `core/stores/tst_run_store.qml::test_a_run_that_turns_escalated_raises_one_toast`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_raises_one_toast_after_arming` (added) |
| `applyProjects` (939) | `raiseAlerts(alerts)` (1044), arming the ok roots (1045-1047), only while `active` | RunStore → Alerts | same handler, after the settle | `core/stores/tst_run_store.qml::test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_raises_one_toast_after_arming` (added) |
| `applyProjects`, AmMissing branch (969) | `armedRoots = {}` (979) | RunStore → Alerts | `snapshotReplied` outcome `missing` | `core/stores/tst_run_store.qml::test_am_missing_disarms_and_a_failed_snapshot_does_not`<br>`core/stores/tst_app_runs.qml::test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms` (added) |
| `forgetLive` (587) | `armedRoots = {}` (593) | RunStore → Alerts | `snapshotReplied` outcome `missing` (forgetLive runs on that path) | `core/stores/tst_run_store.qml::test_a_cursor_reset_starts_over_from_a_list_snapshot`<br>`core/stores/tst_run_store.qml::test_a_hello_from_another_store_starts_over_from_a_list_snapshot` |
| `registryChanged` (731) | drops `armedRoots` entries for roots that left (738, 743) | RunStore → Alerts | App binds `projectRoots` to `RunAlertsStore`, which prunes on its own change | `core/stores/tst_run_store.qml::test_a_root_that_leaves_the_registry_loses_its_arming`<br>`core/stores/tst_app_runs.qml::test_a_project_leaving_the_registry_through_app_loses_its_arming` (added) |
| `startLive` (360) | `armedRoots = {}` (362) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first` |
| `startLive` (360) | `notifyTouched` reset unless a save is busy (363), `settingsLoadRunner.run(["get-global-settings"])` (364) | RunStore → Control | `RunControlStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project`<br>`core/stores/tst_run_store.qml::test_a_save_in_flight_survives_a_reopening`<br>`core/stores/tst_app_runs.qml::test_opening_the_panel_through_app_reads_the_notify_switch` (added) |
| `stopLive` (375) | `armedRoots = {}` (385), `toasts = []` (386) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first`<br>`core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (added) |
| `stopLive` (375) | `closeDispatch()` (388) | RunStore → Dispatch | `RunDispatchStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_panel_close_closes_dispatch_but_not_a_start`<br>`core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (added) |
| `projectSwitched` (655) | `resetDispatch()` (659) | Control → Dispatch | `RunDispatchStore`'s own `project` reaction | `core/stores/tst_run_store.qml::test_project_switch_resets_dispatch_and_drops_old_preview`<br>`core/stores/tst_app_runs.qml::test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` (added) |
| `raiseAlerts` (1349) | reads `notifyOnEscalation` (1359) | Alerts → Control | App binds `runAlerts.notifyOnEscalation: runControl.notifyOnEscalation` | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification`<br>`core/stores/tst_app_runs.qml::test_an_escalation_through_app_notifies_only_with_the_switch_on` (added) |
| `controlReplied` (1183) | `refresh()` (1208) | Control → RunStore | `refreshRequested(roots)`; today the roots are every usable root | `core/stores/tst_run_store.qml::test_a_control_reply_refreshes_every_usable_root` (added)<br>`core/stores/tst_app_runs.qml::test_a_control_reply_through_app_snapshots_every_registered_root` (added)<br>`core/stores/tst_app_runs.qml::test_a_failed_control_reply_through_app_also_snapshots_every_root` (added) |
| `control` (1096), `refusalOf` (1287) | `runById` (1098, 1289), `runRoot` (1109, 1292) | Control → RunStore | App binds `runs`; the lookup is the rule-2 domain function | `core/stores/tst_run_store.qml::test_refusal_of_says_why_a_control_would_not_start`<br>`core/stores/tst_run_store.qml::test_a_run_with_no_repository_or_no_project_root_is_refused` |
| `settleAfterSnapshot` (1244) | `runById` (1251) | Control → RunStore | App binds `runs` | `core/stores/tst_run_store.qml::test_a_request_settles_when_its_run_vanishes` |
| `dispatchStartReplied` (1709) | `refresh()` (1729) | Dispatch → RunStore | `refreshRequested(roots)`; today every usable root | `core/stores/tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` (added)<br>`core/stores/tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` (added) |
| `dispatchStartReplied` (1709) | writes `runSettings` (1727) | Dispatch → Control | `runSettingsSaveRequested(root, patch)`, then `runSettings` comes back in as an input | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `dispatchStartReplied` (1709) | runs `set-run-settings` through `viewer-state.py` on its own runner (1733) | Dispatch → Control | `runSettingsSaveRequested(root, patch)` | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves`<br>`core/stores/tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` (added) |
| `dispatchSaveReplied` (1757) | `flash("Dispatch settings could not be saved")` (1759) | Dispatch → Control | `noticeRequested(text)` | `core/stores/tst_run_store.qml::test_settings_write_failure_flashes`<br>`core/stores/tst_app_runs.qml::test_a_dispatch_settings_save_failure_through_app_flashes` (added) |
| `openDispatch` (1478) | reads `runSettings` and `runs` (`Runs.dispatchDefaults`, 1494) | Dispatch → Control, RunStore | App binds `runSettings` and `runs` | `core/stores/tst_run_store.qml::test_story_prefix_reads_the_snapshot_then_the_keyed_map`<br>`core/stores/tst_run_store.qml::test_open_before_the_settings_reply_starts_from_nothing` |
| `openDispatch` (1478), `checkDispatch` (1579) | read `project` (1479, 1499, 1594) | Dispatch → RunStore input | App binds `project` | `core/stores/tst_run_store.qml::test_open_without_project_is_refused`<br>`core/stores/tst_run_store.qml::test_board_preview_argv` |

Calls inside one store are not listed (for example `openCancel` → `flash` (1310), `confirmCancel` →
`control`, `notifySaveReplied` → `flash` (1431), `applyProjects` → `logsAfterSnapshot` (1027)).

### A.4 Tests added by this subtask

- `core/stores/tst_app_runs.qml::test_a_snapshot_through_app_settles_a_pending_request` — an acknowledged pause stays pending until a snapshot shows its request handled, then settles.
- `core/stores/tst_app_runs.qml::test_a_snapshot_through_app_raises_one_toast_after_arming` — the opening's first snapshots only arm; a later escalation raises exactly one toast.
- `core/stores/tst_app_runs.qml::test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms` — AmMissing empties the runs and disarms; the next good snapshot re-arms and raises nothing.
- `core/stores/tst_app_runs.qml::test_a_control_reply_through_app_snapshots_every_registered_root` — an ok control reply re-snapshots both registered roots.
- `core/stores/tst_app_runs.qml::test_a_failed_control_reply_through_app_also_snapshots_every_root` — an ok:false control reply sets the control error and still re-snapshots both roots.
- `core/stores/tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` — a started dispatch emits `dispatchStarted("r-1")`, re-snapshots both roots and writes `set-run-settings` for its project.
- `core/stores/tst_app_runs.qml::test_a_dispatch_settings_save_failure_through_app_flashes` — a failed `set-run-settings` after a start flashes "Dispatch settings could not be saved".
- `core/stores/tst_app_runs.qml::test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` — a switch resets the dispatch and `runSettings`, reads the new project's settings, keeps the toast, the request and the flash, and launches no snapshot.
- `core/stores/tst_app_runs.qml::test_opening_the_panel_through_app_reads_the_notify_switch` — opening reads `get-global-settings` with `notifyTouched` cleared, and a true reply turns the switch on.
- `core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` — closing empties the toasts, disarms and closes a previewing dispatch.
- `core/stores/tst_app_runs.qml::test_an_escalation_through_app_notifies_only_with_the_switch_on` — an escalation only toasts while the switch is off and also notifies once it is on.
- `core/stores/tst_app_runs.qml::test_a_project_leaving_the_registry_through_app_loses_its_arming` — a root that leaves the registry loses its arming; on its return its first entry only re-arms.
- `core/stores/tst_run_store.qml::test_a_control_reply_refreshes_every_usable_root` — store level: a control reply re-snapshots every usable root.
- `core/stores/tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` — store level: a started dispatch re-snapshots every usable root.
````

- [ ] **Step 3: Check the appendix (the RED/GREEN for this task)**

Save this script as `/tmp/check_appendix.py` (outside the repo; it is not committed):

```python
import re, subprocess, sys
spec = open("docs/superpowers/specs/2026-10-05-split-runstore-design.md").read()
app = spec.split("## Appendix A — member mapping", 1)[1]
a1 = app.split("### A.1", 1)[1].split("### A.2", 1)[0]
a3 = app.split("### A.3", 1)[1].split("### A.4", 1)[0]
rows1 = [l for l in a1.splitlines() if l.startswith("| `")]
rows3 = [l for l in a3.splitlines() if l.startswith("| `")]
grep = subprocess.run(["grep", "-cE", r"^  (readonly )?(property|signal|function)|^  on[A-Z]|^  (HelperRunner|Timer|QtObject|Component) \{",
                       "core/stores/RunStore.qml"], capture_output=True, text=True).stdout.strip()
errs = []
if len(rows1) != int(grep): errs.append(f"A.1 has {len(rows1)} rows, grep counts {grep}")
for r in rows1:
    if not r.rstrip(" |").split("|")[-1].strip(): errs.append("A.1 row without tests: " + r)
for r in rows3:
    if "::test_" not in r.split("|")[-2]: errs.append("A.3 row without pinned by: " + r)
for f, t in sorted(set(re.findall(r"`([\w/]+\.qml)::(test_\w+)`", app))):
    if not re.search(r"^  function " + t + r"\(", open("tests/" + f).read(), re.M): errs.append(f"missing {f}::{t}")
print("A.1 rows", len(rows1), "grep", grep, "A.3 rows", len(rows3))
print("\n".join(errs) if errs else "appendix OK")
sys.exit(1 if errs else 0)
```

Run: `python3 /tmp/check_appendix.py`
Expected: `A.1 rows 225 grep 225 A.3 rows 21` then `appendix OK`, exit 0. To see it fail once, delete the
tests cell of one A.1 row, rerun (expected: `A.1 row without tests: …`, exit 1), then restore the row.

- [ ] **Step 4: Run the full gate**

Run: `timeout 900 bash tests/run.sh; echo "exit $?"`
Expected: pytest all passed; every `== tests/…` QML file prints a `Totals:` line with `0 failed`; no
`FAIL`, `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` line;
`exit 0`.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-split-runstore-design.md
git commit -m "docs(split-runstore): Appendix A member map, cross-concern calls and added tests"
```

- [ ] **Step 6: Check the diff's scope**

`398fde3` is the branch's base commit at plan time (the integrate merge this branch starts from).

Run: `git diff --stat 398fde3 HEAD -- . ':!docs/superpowers/specs/1-1-runstore-coverage-c1570886.md' ':!docs/superpowers/plans/1-1-runstore-coverage-c1570886.md'; git status --short`
Expected: exactly three files — `docs/superpowers/specs/2026-10-05-split-runstore-design.md`,
`tests/core/stores/tst_app_runs.qml`, `tests/core/stores/tst_run_store.qml` — and a clean status. Nothing
under `core/` or `ui/`.

---

## Spec (prepended verbatim)

# 1.1 RunStore coverage map and missing characterization tests — design

Card: `c1570886` (subtask of story `db774a43`). Parent design:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N".

## Purpose

This is the first subtask of the RunStore split. Nothing moves yet. It produces two things:

1. **Appendix A** of the parent spec (P l.166-171). This replaces the stub there with the member
   map and the cross-concern call list, built from `core/stores/RunStore.qml` at this commit.
2. **Characterization tests** for every member or coupling that no test pins today. They test
   TODAY's behaviour. Store-level tests go in `tests/core/stores/tst_run_store.qml`, and
   couplings tested through `App` go in `tests/core/stores/tst_app_runs.qml`.

There are no production code changes. Every file under `core/` and `ui/` is left as it is.

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
  no code or test reads it (P l.61-67, rule 1).
- The target stores and what each owns come from the responsibilities table (P l.52-57).
- `lastLine`, `parseEnvelope`, `copyMap`, `hasKey` and the lookup inside `runById` become
  pure `core/domain/` functions (P l.68-71, rule 2).
- The App routes for cross-concern calls are inputs and signals (P l.72-91, rule 3):
  - `snapshotReplied(root, outcome, previousRuns, runs)` is handled in ONE App handler.
    `runControl.settleAfterSnapshot()` runs first, only on `ok`, then
    `runAlerts.snapshotReplied(…)`.
  - `refreshRequested(roots)` comes from `RunControlStore` and `RunDispatchStore`.
  - `runSettingsWanted(root)`, `runSettingsSaveRequested(root, patch)` and
    `noticeRequested(text)` come from `RunDispatchStore`.
  - App binds `runs`, `project`, `active`, `backendDir`, `notifyOnEscalation`, `runSettings`,
    `projectRoots` and `cardMap` as the table lists them.
- Each store keeps its own lifecycle. A reset that `projectSwitched`, `startLive` or
  `stopLive` does for another concern moves into that store's own reaction (P l.92-97,
  rule 4).
- A test that crosses two concerns becomes an App-level test in `tst_app_runs.qml`. Examples:
  a snapshot settles a pending request, a snapshot raises a toast, and a control reply
  re-snapshots (P l.98-104, rule 5; P l.154-162).
- `tests/architecture` stays green (P l.105-106, rule 6).
- No behaviour change (P l.146-147). The tests pin today's behaviour, even where a later spec
  changes it.
- From the card:
  - follow the `docs/architecture.md` layering;
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative.

## Facts at this commit that differ from the parent spec

- **The queued sections do not exist yet.** The parent assumes that Dispatch from the Runs
  screen and Resume and recover are merged (P l.3-12, 32-42, 154-159). They are not on this
  branch. A grep of `*.qml`, `*.js` and `*.py` finds none of the following:
  - `dispatchRoot`, `dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`,
    `dispatchProject*`, `dispatchTarget*` (other than the existing `dispatchTarget` and
    `dispatchTargetLabel`), and their `board-tree.py` runners;
  - the `// ---- dispatch: project and target steps`, `// ---- resume dialog` and
    `// ---- relaunch` sections;
  - `resume*` (other than the existing `resumeWithSettings`), `relaunchOpenFor`,
    `lastControlErrorType`, the stopped-run attempt choice;
  - the S5 events state, `snapshotReplied`, `runsChanged(ids)`.

  Those names appear only in `2026-10-05-dispatch-from-runs-design.md` and
  `2026-10-05-resume-recover-design.md`. They cannot be characterized against today's
  behaviour, so this subtask adds **no tests** for them. Appendix A records them in a
  separate "Not present at this commit" table (below).
- **A dispatch start refreshes every root today.** `dispatchStartReplied` calls
  `store.refresh()` (`RunStore.qml:1729`), which snapshots every usable root, not only the
  started run's root. A Runs-opened start does not exist. The characterization pins
  "every usable root". The parent's "Runs-opened `started` refreshes `dispatchRoot` only"
  (P l.158-159) is listed as not present.
- **A control reply refreshes every root.** `controlReplied` calls `store.refresh()`
  (`:1208`).
- **The parent's line numbers are stale.** The Problem table (P l.19-30) cites cbe313c. Appendix
  A uses the line numbers of `RunStore.qml` at this commit (2038 lines). P l.99 says "127
  tests today", but the file has about 302 tests. That number is left as it is, since it is
  outside the appendix.

## Deliverable 1 — Appendix A

Replace only the body under `## Appendix A — member mapping` (P l.166-171). Keep the heading.
Nothing else in the parent spec changes. The appendix has four parts, in this order.

### A.1 Member map

One Markdown table with the columns `member | line | kind | target | tests that cover it`.

- **Rows.** There is one row for every top-level member of the root `Scope` in
  `RunStore.qml`: every `property` (including `readonly`), every `readonly property alias`,
  `signal`, `function`, `on<Signal>:` handler, `HelperRunner`, `Timer`, `QtObject` and
  `Component` declared at the store's top level (2-space indentation). A child item is listed
  under its `id` (`snapshotRunner`, `debounceTimer`, `watchState`, `controlC`, …). The
  readonly alias that exposes it is a separate row of kind `alias`, mapped to the same store.
  No top-level member may be missing. Self-check: the number of rows equals the number of
  top-level declarations found by
  `grep -nE '^  (readonly )?(property|signal|function)|^  on[A-Z]|^  (HelperRunner|Timer|QtObject|Component) \{' core/stores/RunStore.qml`.
- **`kind`** is one of: `property`, `readonly property`, `input property` (App binds it:
  `backendDir`, `project`, `active`, `searchQuery`, `projectRoots`), `alias`, `signal`,
  `function`, `handler`, `runner`, `timer`, `state object`, `component`.
- **`target`** is exactly one of `RunStore`, `RunControlStore`, `RunAlertsStore`,
  `RunDispatchStore`, `core/domain`. `core/domain` is only for the four rule-2 helpers
  (`lastLine`, `parseEnvelope`, `copyMap`, `hasKey`; P l.68-71).
  - An input property that several stores read stays in `RunStore`. The other stores get
    their own App binding (P l.72-79), which is a new input, not a duplicated member.
  - A function whose body serves several concerns is mapped to the store that keeps its
    name. The lines that belong to another concern are listed in A.3.
- **`tests that cover it`** names one or more tests as `file::test_name`, with the file
  relative to `tests/`. This includes tests that exercise a private function only through
  its observable effects (for example `watchLine` through the watch-line tests). A ui-suite
  test counts when it reads or drives the member. A row with no test is not allowed when the
  work is done: the test added under Deliverable 2 is named there, marked `(added)`.

The mapping is fixed as follows. Lines are `RunStore.qml` at this commit. The implementer
re-greps before writing and corrects any line that has drifted, never the target.

| target | members |
|---|---|
| `RunStore` | **inputs:** `projectRoots` 41, `project` 42, `backendDir` 43, `active` 44<br>**snapshot and runs state:** `runsByProject` 49, `projectErrors` 51, `runs` 54, `selectedRunId` 55, `amStatus` 56, `amSchema` 57, `amVersion` 58, `lastError` 59, `stale` 60, `watchWarning` 61<br>**list filter:** `runFilter` 66, `searchQuery` 67, `runFilterToggled` 69, `projectFilter` 74, `projectFilterToggled` 77, `groups` 80, `filteredRuns` 83<br>**watch state:** `asOfSeq` 88, `appliedSeq` 89, `watchCursor` 91, `nudges` 94, `storeId` 98, `watchTried` 105, `watchSeq` 106, `watchSchemaError` 107<br>**selection and logs:** `selectedAttempt` 111, `logsText`, `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError`, `logsStatus` 112-117<br>**signals and derived:** `runsNudged` 193, `hasRunningRun` 222<br>**aliases:** `watching`, `watchProc`, `watchRoots`, `snapshotRunner`, `snapshotRoots`, `pendingSnapshot`, `debounceTimer`, `livenessTimer`, `staleTimer`, `pollTimer`, `logsRunner` 195-206<br>**functions:** `refresh` 234, `requestSnapshot` 249, `launchSnapshot` 268, `dropSnapshots` 281, `snapshotEnded` 289, `toggleRunFilter` 299, `toggleProjectFilter` 307, `projectRootOf` 316, `isFilterable` 323, `keepProjectFilter` 343, `startLive` 360, `stopLive` 375, `restartStale` 392, `stopWatch` 399, `startWatch` 412, `watchableRoots` 428, `knownRunIds` 437, `sameRoots` 455, `isCurrentWatch` 466, `watchLine` 481, `recordNudges` 504, `triggerNudges` 523, `listsRun` 546, `refreshLive` 556, `resetCursor` 575, `forgetLive` 587, `seeStore` 600, `forgetHello` 608, `watchExited` 618, `startPoll` 640, `stopPoll` 644, `usableRoots` 670, `taggedByProject` 689, `mergedRuns` 708, `registryChanged` 731, `runById` 753, `runRoot` 762, `selectAttempt` 772, `refreshLogs` 788, `fetchLogs` 796, `clearLogs` 808, `openDefaultAttempt` 820, `logsAfterSnapshot` 829, `applyLogs` 850, `rowOf` 891, `isSeq` 900, `applySnapshot` 909, `applyProjects` 939<br>**handlers:** `onRunsChanged` 349, `onActiveChanged` 351, `onProjectRootsChanged` 748, `onSelectedRunIdChanged` 841<br>**children:** `snapshotRunner` 1773, `logsRunner` 1782 (runners); `debounceTimer` 1837, `livenessTimer` 1847, `staleTimer` 1857, `pollTimer` 1866 (timers); `watchState` 1915, `snapshotState` 1925 (state objects); `watchC` 2022 (component) |
| `RunControlStore` | **control and cancel state:** `pending` 124, `stillWaiting` 125, `stillWaitingText` 126, `lastControlError` 127, `lastControlErrorRunId` 128, `cancelRunId` 133, `cancelOpen` 134, `cancelText` 135, `cancelError` 136, `flashText` 138<br>**settings state:** `notifyOnEscalation` 158, `notifySaved` 159, `notifyTouched` 160, `runSettings` 165<br>**aliases:** `controlRunners` 207, `pendingTimer` 208, `flashTimer` 209, `settingsLoadRunner` 211, `settingsSaveRunner` 212, `runSettingsRunner` 213<br>**functions:** `projectSwitched` 655 (its `resetDispatch()` line goes to A.3), `control` 1096, `launchControl` 1125, `requestOf` 1133, `settle` 1141, `failControl` 1161, `dismissControlError` 1167, `dropRunner` 1173, `controlReplied` 1183, `resumeWithSettings` 1216, `settleAfterSnapshot` 1244, `isHandled` 1259, `checkWaiting` 1271, `refusalOf` 1287, `flash` 1299, `openCancel` 1307, `closeCancel` 1319, `confirmCancel` 1328, `setNotifyOnEscalation` 1395, `applyGlobalSettings` 1407, `applyRunSettings` 1417, `notifySaveReplied` 1424<br>**handlers:** `onProjectChanged` 664<br>**children:** `settingsLoadRunner` 1792, `runSettingsRunner` 1803, `settingsSaveRunner` 1812 (runners); `pendingTimer` 1876, `flashTimer` 1886 (timers); `controlState` 1935 (state object); `controlC` 1974 (component) |
| `RunAlertsStore` | **state:** `armedRoots` 149, `alertsArmed` 150, `toasts` 151, `toastMs` 152<br>**aliases:** `toastTimer` 210, `notifyRunners` 214<br>**functions:** `alertsOf` 1056, `raiseAlerts` 1349, `expireToasts` 1364, `dismissToast` 1370, `dismissAllToasts` 1375, `notify` 1382, `dropNotifyRunner` 1388<br>**children:** `toastTimer` 1895 (timer); `toastState` 1943, `notifyState` 1949 (state objects); `notifyC` 1991 (component) |
| `RunDispatchStore` | **state:** `dispatchState`, `dispatchTarget`, `dispatchTargetLabel`, `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchErrorType`, `dispatchErrors`, `dispatchSuggest`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode` 173-186<br>**signal:** `dispatchStarted` 189<br>**aliases:** `dispatchDefaultsRunner` 215, `dispatchPreviewRunner` 216, `dispatchDebounceTimer` 217, `dispatchStartRunners` 218<br>**functions:** `clearDispatchError` 1437, `resetDispatch` 1450, `openDispatch` 1478, `closeDispatch` 1505, `blockedSuggest` 1514, `retargetToMilestone` 1523, `withField` 1530, `dispatchTargetArgs` 1537, `dispatchCommands` 1543, `dispatchOptionArgs` 1550, `dispatchDefaultsReplied` 1565, `checkDispatch` 1579, `dispatchPreviewReplied` 1603, `setDispatchField` 1638, `mergedPrefixes` 1656, `dispatchStart` 1669, `isHereStart` 1698, `dispatchStartReplied` 1709, `dispatchSaveReplied` 1757, `dropStartRunner` 1764<br>**children:** `dispatchDefaultsRunner` 1821, `dispatchPreviewRunner` 1829 (runners); `dispatchDebounceTimer` 1905 (timer); `dispatchBook` 1960 (state object); `dispatchStartC` 2007 (component) |
| `core/domain` | `lastLine` 870, `parseEnvelope` 880, `copyMap` 1080, `hasKey` 1088 |

If the re-grep finds a top-level member that is not in this table, the implementer maps it with
the responsibilities table (P l.52-57) and states the reason in one clause in its row.

### A.2 Not present at this commit

A second table with the columns `member or section | from milestone | target | note`. Each
row's note reads "not in `RunStore.qml` at this commit; mapped whole when it lands; no
characterization test". Rows:

| member or section | from milestone | target |
|---|---|---|
| `dispatchRoot` | Dispatch from the Runs screen | `RunDispatchStore` |
| `// ---- dispatch: project and target steps` (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, their two `board-tree.py` runners) | Dispatch from the Runs screen | `RunDispatchStore` |
| a Runs-opened start's `started` refreshing `[dispatchRoot]` only | Dispatch from the Runs screen | `RunDispatchStore` (`refreshRequested`) |
| `// ---- relaunch` (`relaunchOpenFor`, `relaunch*`) | Resume and recover | `RunDispatchStore` |
| `// ---- resume dialog` (`resume*`, `resumeOpenFor`, `resumeClose`, `resumeConfirm`, `resumeSaveRunner`) | Resume and recover | `RunControlStore` |
| `lastControlErrorType` | Resume and recover | `RunControlStore` |
| the stopped-run attempt choice | Resume and recover | `RunStore` |
| the events state | S5 | `RunStore` |
| `runsChanged(ids)` | S6 / milestone 4 | `RunStore` |
| `snapshotReplied(root, outcome, previousRuns, runs)` | this milestone (new, rule 3) | `RunStore` |
| the persisted `gseq` alert cursor | Alerts while the panel is closed | `RunAlertsStore` |

### A.3 Cross-concern calls

A table with the columns `caller (line) | callee or effect (line) | from → to | App route |
pinned by`. It lists every place where a member mapped to one store reads or writes a member
mapped to another. `pinned by` names at least one `file::test_name` per row (an existing test,
or an added one marked `(added)`). The cases below give the first four columns; the
implementer fills `pinned by` (lines at this commit):

| caller | callee or effect | from → to | App route |
|---|---|---|---|
| `applyProjects` (939) | `settleAfterSnapshot()` (1026) | RunStore → Control | `snapshotReplied` outcome `ok` → `runControl.settleAfterSnapshot()`, first in the handler |
| `applyProjects` | `alertsOf(…)` (1015), only while `active` | RunStore → Alerts | `snapshotReplied(root, outcome, previousRuns, runs)` → `runAlerts.snapshotReplied(…)` |
| `applyProjects` | `raiseAlerts(alerts)` (1044), arming the ok roots (1045-1047), only while `active` | RunStore → Alerts | same handler, after the settle |
| `applyProjects`, AmMissing branch | `armedRoots = {}` (979) | RunStore → Alerts | `snapshotReplied` outcome `missing` |
| `forgetLive` (587) | `armedRoots = {}` (593) | RunStore → Alerts | `snapshotReplied` outcome `missing` (forgetLive runs on that path) |
| `registryChanged` (731) | drops `armedRoots` entries for roots that left (738, 743) | RunStore → Alerts | App binds `projectRoots` to `RunAlertsStore`, which prunes on its own change |
| `startLive` (360) | `armedRoots = {}` (362) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction |
| `startLive` | `notifyTouched` reset unless a save is busy (363), `settingsLoadRunner.run(["get-global-settings"])` (364) | RunStore → Control | `RunControlStore`'s own `active` reaction |
| `stopLive` (375) | `armedRoots = {}` (385), `toasts = []` (386) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction |
| `stopLive` | `closeDispatch()` (388) | RunStore → Dispatch | `RunDispatchStore`'s own `active` reaction |
| `projectSwitched` (655) | `resetDispatch()` (659) | Control → Dispatch | `RunDispatchStore`'s own `project` reaction |
| `raiseAlerts` (1349) | reads `notifyOnEscalation` (1359) | Alerts → Control | App binds `runAlerts.notifyOnEscalation: runControl.notifyOnEscalation` |
| `controlReplied` (1183) | `refresh()` (1208) | Control → RunStore | `refreshRequested(roots)`; today the roots are every usable root |
| `control` (1096), `refusalOf` (1287) | `runById` (1098, 1289), `runRoot` (1109, 1292) | Control → RunStore | App binds `runs`; the lookup is the rule-2 domain function |
| `settleAfterSnapshot` (1244) | `runById` (1251) | Control → RunStore | App binds `runs` |
| `dispatchStartReplied` (1709) | `refresh()` (1729) | Dispatch → RunStore | `refreshRequested(roots)`; today every usable root |
| `dispatchStartReplied` | writes `runSettings` (1727) | Dispatch → Control | `runSettingsSaveRequested(root, patch)`, then `runSettings` comes back in as an input |
| `dispatchStartReplied` | runs `set-run-settings` through `viewer-state.py` on its own runner (1733) | Dispatch → Control | `runSettingsSaveRequested(root, patch)` |
| `dispatchSaveReplied` (1757) | `flash("Dispatch settings could not be saved")` (1759) | Dispatch → Control | `noticeRequested(text)` |
| `openDispatch` (1478) | reads `runSettings` and `runs` (`Runs.dispatchDefaults`, 1494) | Dispatch → Control, RunStore | App binds `runSettings` and `runs` |
| `openDispatch`, `checkDispatch` (1579) | read `project` (1479, 1499, 1594) | Dispatch → RunStore input | App binds `project` |

Calls inside one store are not listed. Examples: `openCancel` → `flash` (1310),
`confirmCancel` → `control`, `notifySaveReplied` → `flash` (1431), and `applyProjects` →
`logsAfterSnapshot` (1027). If the implementer finds another cross-store call while filling
A.1, it is added here with a route in the same style (P l.87-91).

### A.4 Tests added by this subtask

A list with one line per added test: `file::test_name — what it pins`. Every name here also
appears in an A.1 row or an A.3 row (as a fifth column, `pinned by`, which A.3 has: every
A.3 row names at least one test).

## Deliverable 2 — characterization tests

All tests pin today's behaviour and pass on the first green run once written. Because the
production code already exists, TDD's "red" step here means checking that each new test can
fail. Before committing a test, the implementer breaks the expectation once, by changing
the compared value, and confirms the test fails. A test that cannot fail is rewritten. No
`core/` or `ui/` file changes.

### 2a. App-level coupling tests (`tests/core/stores/tst_app_runs.qml`)

**Why this tier:** each test crosses two concerns that become two stores. Rule 5 (P
l.101-104) puts such a test in `tst_app_runs.qml`, built on a real `App` (`make()`, the
existing helper). Today it drives `app.runs` alone. After the split, only the property paths
change. The existing `make()` and `okReply` helpers are reused. New helpers go at the top of
the file, next to them, and are not copied from `tst_run_store.qml` into a shared file: two
test files may each have their own small fixture builders. Each helper gets a one-line
contract comment. Throughout, "the panel is open" means `app.panelOpen = true`, and a reply
is delivered by setting `outText` on the runner's `current` process and calling
`exited(code)`.

The required tests, named exactly:

1. `test_a_snapshot_through_app_settles_a_pending_request`
   - Setup: the panel is open; pA's snapshot lists a running, accepting run `r1`.
   - `app.runs.control("pause", "r1")` gives `pending.r1 === "pause"`.
   - Then an ok control reply arrives, followed by a snapshot in which `r1`'s control shows the
     pause request handled (the shape `tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled`
     uses).
   - Expect: `pending.r1` is `undefined`.
2. `test_a_snapshot_through_app_raises_one_toast_after_arming`
   - Setup: the panel is open. The first ok snapshot lists `r1` as running.
   - Expect after the first snapshot: no toast, and `alertsArmed` is true.
   - Then a second snapshot lists `r1` as escalated.
   - Expect: exactly one toast, with `id === "r1"`.
3. `test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms`
   - Setup: armed as in test 2.
   - An AmMissing reply gives `alertsArmed === false` and `runs.length === 0`.
   - Then an ok snapshot with an escalated `r1` arrives.
   - Expect: no toast, `alertsArmed` is true again.
4. `test_a_control_reply_through_app_snapshots_every_registered_root`
   - Setup: pA and pB are registered, the panel is open, and the snapshot is applied.
   - `control("pause", "r1")`, then an ok control reply.
   - Expect: `snapshotRunner.seq` goes up by one. The new snapshot's argv is
     `python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj|/home/u/b`.
5. `test_a_failed_control_reply_through_app_also_snapshots_every_root`
   - The same as test 4, but with an `ok:false` reply.
   - Expect: `lastControlError` is set, and the same re-snapshot of both roots happens.
6. `test_a_dispatch_start_through_app_snapshots_every_registered_root`
   - Setup: pA is open and pA and pB are registered.
   - The dispatch is driven to `ready` through `app.runs`: `openDispatch(card, cardMap)` with
     a one-milestone card map, then the defaults reply and an ok preview reply. Follow the
     steps of `tst_run_store.qml`'s `readyStore`.
   - Then `dispatchStart()` and an ok start reply with run id `r-1`.
   - Expect:
     - `dispatchStarted` fires once, with `"r-1"`;
     - a new snapshot names both roots (today: every usable root, not the started run's
       root);
     - the start runner's next process runs `set-run-settings` for `/home/u/my proj`.
7. `test_a_dispatch_settings_save_failure_through_app_flashes`
   - Continue test 6's flow. The `set-run-settings` reply is a failure.
   - Expect: `flashText === "Dispatch settings could not be saved"`.
8. `test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings`
   - Setup: pA is open, the panel is open, the dispatch is in `previewing` or `ready`, and
     `runSettings` is non-empty (from a `get-run-settings` reply for pA).
   - Also present before the switch: a toast, a pending request, and a flash.
   - Action: `app.projects.chooseProject(pB)`.
   - Expect:
     - `dispatchState === "idle"` and `runSettings` is `{}`;
     - `runSettingsRunner.current`'s argv ends `get-run-settings|/home/u/b`;
     - the toast, the pending request and the flash are unchanged;
     - no new snapshot is launched (`snapshotRunner.seq` is unchanged).
9. `test_opening_the_panel_through_app_reads_the_notify_switch`
   - Setup: `make()` with the panel closed.
   - Action: `app.panelOpen = true`.
   - Expect: `settingsLoadRunner.current`'s argv ends `get-global-settings`, and
     `notifyTouched === false`.
   - Then the reply `{"ok":true,"settings":{"notifyOnEscalation":true}}`, in the shape
     `tst_run_store.qml`'s notify tests use, gives `notifyOnEscalation === true`.
10. `test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch`
    - Setup: the panel is open, alerts are armed, there is one toast, and the dispatch is not
      idle.
    - Action: `app.panelOpen = false`.
    - Expect: `toasts.length === 0`, `alertsArmed === false`, and `dispatchState === "idle"`.
11. `test_an_escalation_through_app_notifies_only_with_the_switch_on`
    - Setup: armed as in test 2.
    - With `notifyOnEscalation` false, an escalated snapshot gives one toast and
      `notifyRunners.length === 0`.
    - With the switch set true by the global-settings reply, another run's escalation gives
      `notifyRunners.length === 1`.
12. `test_a_project_leaving_the_registry_through_app_loses_its_arming`
    - Setup: pA and pB are armed; this is observable as a later escalation in each raising a
      toast.
    - Action: `app.projects.applyProjectsList([pA])`.
    - Then `applyProjectsList([pA, pB])` again, and a snapshot where pB's run is escalated
      arrives.
    - Expect: no toast for pB, because it is re-armed rather than compared against its old
      runs.

The fixture text for each reply copies the exact shapes the matching `tst_run_store.qml` tests
use. The implementer locates them by test name and does not invent new envelope fields.

### 2b. Store-level gap tests (`tests/core/stores/tst_run_store.qml`)

**Why this tier:** these pin one concern's own behaviour. The test moves unchanged with its
member's store in later subtasks.

While filling A.1, any row whose member no existing test exercises gets one store-level test,
added to the section of `tst_run_store.qml` that covers its concern (P l.99-100 move
targets). The test drives only public inputs, functions and stubbed processes, never a private
function's return value directly. Exceptions are the members whose observable effect is only
their own value: `stillWaitingText`, `toastMs`, the timers' `interval`.

The implementer must check each of these candidates. Each is a test name to add **only if**
the check shows no existing test pins the behaviour:

- `test_a_snapshot_after_a_no_root_watch_attempt_does_not_retry` (`watchTried`): while
  active, with only non-absolute usable roots, a first ok snapshot launches no watch, and a
  second ok snapshot launches none either (`watchProc` stays null, `watching` false). It is
  reset by the next `startLive`.
- `test_a_dispatch_start_refreshes_every_usable_root` (`dispatchStartReplied` → `refresh`):
  the store-level twin of App test 6, with two registered roots. Add it only if no existing
  dispatch test has more than one root.
- `test_a_control_reply_refreshes_every_usable_root`: the store-level twin of App test 4,
  with the same condition.

These members are already covered and need no new test; the A.1 rows name the tests listed:

- `dismissControlError`: `:2915`.
- `closeCancel`: `:3220`, `:3261`.
- `dispatchSaveReplied`: `test_settings_write_failure_flashes`.
- `mergedPrefixes`: `test_a_story_start_saves_the_prefix_under_its_milestone`.
- `isHereStart`: `test_start_reply_after_switching_away_and_back_is_not_here`.
- `retargetToMilestone`.
- `hasRunningRun`: the liveness tests `:1661-1689`.
- `stopLive`: `test_deactivate_kills_watch_and_timers`.
- `projectSwitched`: `test_project_switch_resets_dispatch_and_drops_old_preview`.

The implementer confirms each one by reading the test, not by name alone.

### 2c. What the tests must not do

- They must not assert a behaviour from a later spec: no `dispatchRoot`, no `snapshotReplied`,
  no `refreshRequested`.
- They must not reach past `app.runs` into another store's internals, except the existing
  `app.projects`, `app.nav` and `app.panelOpen` inputs.
- They must not change or delete any existing test or its expectations.
- They must not add a shared helper file, which would duplicate existing patterns that
  `tests/architecture` guards.

## Error paths covered

- **AmMissing:** disarms every root and empties the runs (App test 3).
- **Failed control reply:** still re-snapshots every root (App test 5).
- **Failed dispatch settings write:** flashes (App test 7).
- **Project switch with a dispatch mid-flight:** resets it, and the other concerns' state is
  untouched (App test 8).
- **Registry shrink:** forgets the arming (App test 12).

## Out of scope

- Any production change in `core/` or `ui/`, including the rule-2 domain helpers. Those
  belong to the next subtask of story `db774a43`.
- Creating `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`, `snapshotReplied` or
  `refreshRequested`, the shims, or moving any test into `tst_run_control_store.qml`,
  `tst_run_alerts_store.qml` or `tst_run_dispatch_store.qml`. Those belong to later stories.
- Tests for members that are not present at this commit (A.2).
- Editing any part of the parent spec other than the Appendix A body. That includes the
  stale Problem line numbers and the "127 tests" figure.
- The ui suites under `tests/ui/`. They are read to fill the coverage column and are not
  changed.

## Verification

- `bash tests/run.sh` is green. It runs pytest, including `tests/architecture`, and every
  `tst_*.qml`. Its failure scan sees none of: `FAIL`, `TypeError`, `ReferenceError`,
  `non-existent`, `Unable to assign`, `is not a function`.
- `git diff --stat` touches only these files (besides this spec and its plan under
  `docs/superpowers/`):
  - `docs/superpowers/specs/2026-10-05-split-runstore-design.md`;
  - `tests/core/stores/tst_app_runs.qml`;
  - `tests/core/stores/tst_run_store.qml`, only if a 2b test was added.
- Appendix A self-checks:
  - the A.1 row count equals the grep count above;
  - every A.1 row has a non-empty tests column;
  - every A.3 row has a `pinned by` test;
  - every test named in A.4 exists in its file (`grep -n "function <name>("`).

<!-- task-pipeline: validated -->
