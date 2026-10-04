<!-- task-pipeline: validated -->
# 3.2 RunStore: watch signal, debounce, liveness timer, stale flag (card 5a3c8015)

Narrows the "Refresh model", "Domain model" (stale) and "Errors and edge cases" sections of `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` to the live-refresh half of `core/stores/RunStore.qml`. Builds on 3.1 (snapshot, selection, amStatus), which is unchanged except where noted below.

## Scope

Files touched:
- `core/stores/RunStore.qml`: extend it.
- `tests/core/stores/tst_run_store.qml`: extend it. Tests are written first.
- `tests/stubs/Quickshell/Io/SplitParser.qml` plus a `SplitParser` line in `tests/stubs/Quickshell/Io/qmldir`: a new test stub with a `read(string data)` signal, so the watch's stdout can be fed line by line. This mirrors real Quickshell.Io's `SplitParser`.

Not touched: `App.qml` and `docs/architecture.md` (both belong to 3.3), BoardStore, `runs.js`, the python helpers, UI, the attempt-logs runner, and controls or dispatch. The store keeps the existing layer rule: it imports only QtQml, Quickshell, Quickshell.Io and `../domain/runs.js`. It gets `project` and `backendDir` only through properties. The snapshot still runs through the existing `snapshotRunner` (HelperRunner). The watch is the only plain `Process`. Update the 3.1 header comment so it no longer says "the live watch (3.2) comes later".

## Observable behavior

New public properties: `active` (bool, default false; App binds it to "panel open" in 3.3), `watching` (bool, read-only to consumers), `stale` (bool), `watchWarning` (string, "" when there is no warning). Each Timer and the watch Process is exposed as a `readonly property alias` with an `objectName`: `watchProc`, `debounceTimer`, `livenessTimer`, `staleTimer`, `pollTimer`. This follows BoardStore's `watchTimer` pattern (BoardStore.qml:135-141).

1. **Activation.** When `active` becomes true and `project` is not "", the store calls `refresh()`. The 3.1 `projectSwitched()` and `refresh()` behavior stays as it is.
2. **Watch start.** The first successful (`ok:true`) snapshot after an activation or project switch, while `active` is true and no fallback poll is running, starts `watchProc` with the command `["python3", backendDir + "runs/runs-watch.py", project, <run ids of that snapshot, in snapshot order>]`. `watching` becomes true. Later snapshots do not restart a watch that is already running, because the helper itself picks up new runs of the project.
3. **Debounce.** Each stdout line is parsed as JSON. A `{"changed":[...]}` line restarts `debounceTimer` (250 ms, `repeat: false`). When the timer fires, it calls `refresh()` once, so a burst of lines costs one snapshot. Blank, unparsable or unrecognised lines are ignored and never throw.
4. **Liveness.** `livenessTimer` (10 s, repeating) runs only while `active` is true and at least one run in `runs` has `Runs.runState(run) === "running"`. Each tick calls `refresh()`. In every other case the timer is stopped, so no timer runs while idle.
5. **Stale.** `stale` becomes true when the last good snapshot is more than 30 s old while `active` is true. `staleTimer` (30 s, non-repeating) runs only while active and is restarted on activation and on every `ok:true` snapshot. When it fires, `stale` becomes true. A good snapshot sets `stale` back to false. Failed snapshots do not restart the timer. When the store goes inactive, `stale` is set to false. `stale` is not a run state and it leaves `runs` unchanged.
6. **Deactivation.** When `active` becomes false, the store stops `watchProc` (`running = false`) and stops the debounce, liveness, stale and poll timers. `watching`, `stale` and `watchWarning` are cleared. `runs`, `selectedRunId` and `amStatus` stay as they are.
7. **Project switch.** The 3.1 behavior still applies: runs, selection and lastError are cleared, and a new snapshot is requested. In addition, the old watch is stopped, `watching` becomes false, pending debounce and poll timers stop, and `watchWarning` is cleared. The new project's watch starts after its first good snapshot (rule 2). Lines or an exit from the old watch that arrive after the switch or after deactivation are ignored. The store records the project the watch was launched for plus a launch counter (bumped on every start and every stop) and checks both on each line and each exit, which acts as a stale-exit guard. This also covers deactivate then re-activate on the same project: the old process's late exit must not clear `watching` of the new watch. In addition, `stale` is set to false and `staleTimer` is restarted (when `active`), because the old project's snapshot age says nothing about the new one.

## Error paths (watch helper)

The helper prints `{"ok":false,"error":{"type":...,"message":...}}` and then exits 1.
- `SchemaMismatch`: `amStatus = "schema"` and `lastError = Runs.errorText(envelope)`, which drives the banner. The store switches to the fallback poll.
- `CorruptJournal`: `watchWarning = Runs.errorText(envelope)`, which drives the warning chip. The store switches to the fallback poll.
- Fallback poll: `watching` becomes false. `pollTimer` (5 s, repeating) runs while `active` is true and calls `refresh()` on each tick. It replaces the watch signal: no watch is restarted while it runs. Liveness and stale rules continue to apply. The poll is cleared on deactivation or project switch. A later activation tries the watch again.
- The helper's envelope arrives as a stdout line; the store keeps the last envelope line it saw and applies the error paths at process exit (the exit code decides "no envelope"). Other types (`HelperError`, `AmMissing`, `Usage`), or a non-zero exit with no envelope: `watching` becomes false and `lastError` is set. The store starts no poll and no restart. While the fallback poll is running (`pollTimer.running`), `applySnapshot` must not reset `amStatus` from "schema" to "ok" nor clear the `lastError` the watch set, so the banner survives the polling snapshots. A project switch clears both (3.1 behavior). Deactivation stops the poll but leaves `amStatus` and `lastError` as they are (rule 6); the next good snapshot after re-activation then resets them normally, and the watch is tried again.
- Exit 0 means the watch was stopped (the store killed it, or `am` exited). `watching` becomes false and nothing else changes.

## Tests

Tier: every test below goes in `tests/core/stores/tst_run_store.qml`. This is the headless QML store tier, following the placement rule "A store: ... test headless under tests/core/stores/" and the monitor spec's Testing section, which assigns "debounce, liveness timer on/off, fallback to poll, stale flag, project switch clears runs" to this file. None of these tests go in the ui, contract, pytest backend or architecture tiers. The tests use the existing `make()`, `makeWithProject()`, `reply()`, `entry()` and `okReply()` helpers and the stubbed Process, and they feed watch lines through the new SplitParser stub's `read`. Each test starts timers by checking `running` and fires them by calling `triggered()` directly. No test sleeps.

1. `test_watch_not_started_before_first_snapshot`: after activation, `watchProc.running` stays false until the snapshot reply.
2. `test_watch_argv_after_first_snapshot`: after an ok reply with runs a and b, the command is `python3 <backendDir>runs/runs-watch.py <project> a b`, and both `running` and `watching` are true.
3. `test_watch_not_started_when_inactive`: an ok snapshot while `active` is false leaves the watch off.
4. `test_failed_first_snapshot_does_not_start_watch`.
5. `test_second_snapshot_does_not_restart_watch`.
6. `test_deactivate_kills_watch_and_timers`: `watchProc.running`, `watching` and all timers are false, and `runs` is unchanged.
7. `test_changed_line_starts_debounce`, then `test_burst_coalesces_to_one_snapshot`: three `changed` lines followed by one `triggered()` launch exactly one snapshot.
8. `test_garbage_watch_line_ignored`.
9. `test_liveness_on_with_running_run`, `test_liveness_off_without_running_run` (dead, parked and done runs), `test_liveness_off_when_inactive`, and `test_liveness_tick_refreshes`.
10. `test_stale_after_timer_fires`, `test_good_snapshot_clears_stale`, `test_failed_snapshot_keeps_stale_timer_running` (the timer is not restarted), and `test_stale_cleared_on_deactivate`.
11. `test_schema_mismatch_falls_back_to_poll`: amStatus is "schema", `pollTimer.running` is true, `watching` is false, and a poll tick triggers a refresh.
12. `test_corrupt_journal_sets_warning_and_polls`.
13. `test_poll_stops_on_deactivate`.
14. `test_other_watch_error_stops_watching_without_poll`.
15. `test_watch_exit_zero_only_clears_watching`.
16. `test_project_switch_stops_watch_and_clears_runs`: the old watch is off, runs are empty, and `watching` and `watchWarning` are cleared.
17. `test_new_project_watch_starts_after_its_snapshot`: the argv carries the new project.
18. `test_old_watch_lines_ignored_after_switch`.
19. `test_schema_banner_survives_poll_snapshots` (amStatus stays "schema" and lastError is kept across an ok snapshot while polling), `test_stale_exit_after_reactivation_ignored`, and `test_project_switch_resets_stale`.
20. The existing 3.1 tests stay green without changes.

---

# RunStore live refresh (watch, debounce, liveness, stale, fallback poll) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `core/stores/RunStore.qml` keep its runs fresh while the panel is open: a long-lived `runs-watch.py` whose `changed` lines cost one debounced snapshot, a 10 s liveness re-read while a run is running, a 30 s `stale` flag, and a 5 s fallback poll when the watch cannot read am's journal.

**Architecture:** The 3.1 store already fetches snapshots through `snapshotRunner` (HelperRunner, latest wins, project guard). This plan adds an `active` property, four `Timer`s exposed as readonly aliases (BoardStore's `watchTimer` pattern), and a watch `Process` created per launch from a `Component` (the HelperRunner pattern) that carries its launch counter and launch project, so a killed watch's late line or exit can never be mistaken for the current one. Lines arrive through a `SplitParser`; the error envelope a failing watch prints is kept and acted on at exit.

**Tech Stack:** QML (QtQml `Timer`/`QtObject`/`Component`, Quickshell `Scope`, Quickshell.Io `Process`/`SplitParser`/`StdioCollector`), QtTest via `qmltestrunner` with the stubs under `tests/stubs/`, `bash ./tests/run.sh`.

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-3-2-runstore-watch-5a3c8015/docs/superpowers/specs/task-3-2-runstore-watch-5a3c8015-design.md` (prepended above, read from disk after its adversarial review). The orientation summary handed to the planner was truncated at 2000 characters by the upstream stage; this plan works only from the on-disk spec, not from that summary.

**Worktree / branch:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-3-2-runstore-watch-5a3c8015`, branch `mon/task-3-2-runstore-watch-5a3c8015`, cut from `mon/task-3-1-runstore-snapshot-6768ae0b`. Every command below runs from that directory. Nothing beyond 3.1's code is assumed to exist.

**Two implementation choices the spec leaves open (decided here):**
- `watchProc` is a per-launch `Process` created from a `Component` and exposed as `readonly property alias watchProc: watchState.proc` (it is `null` until the first watch starts). A single static `Process` cannot tell a killed launch's late exit from the new launch's exit, which spec rule 7 and test 19 (`test_stale_exit_after_reactivation_ignored`) require. `watching` is likewise `readonly property alias watching: watchState.watching`, so consumers cannot write it.
- "No fallback poll is running" in rule 2 is covered by a `watchTried` flag (set when a watch starts, reset on activation and project switch): a poll only ever starts after a watch was started, so a poll implies `watchTried` and the watch is never restarted while polling. The same flag gives "no restart" after `HelperError`/`AmMissing`/`Usage` and after exit 0. `staleTimer` is not started while `project` is "" (the spec is silent; there is nothing to be stale about).

## Global Constraints

- `core/stores/RunStore.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `"../domain/runs.js" as Runs` — no QtQuick, no `qs.*`, no `ui/`, no sibling directories (enforced by `tests/architecture/test_layers.py`).
- The store gets `project` and `backendDir` only through properties; it never touches BoardStore or any other store.
- Snapshots still go through the existing `snapshotRunner` (HelperRunner); the watch is the only plain `Process`.
- Do not edit `core/stores/App.qml` or `docs/architecture.md` (both are 3.3), `core/domain/runs.js`, or anything under `core/backend/`.
- Watch argv is exactly `["python3", backendDir + "runs/runs-watch.py", project, <run ids in snapshot order>]`.
- Intervals: `debounceTimer` 250 ms `repeat: false`; `livenessTimer` 10000 ms `repeat: true`; `staleTimer` 30000 ms `repeat: false`; `pollTimer` 5000 ms `repeat: true`.
- `objectName`s: `watchProc`, `debounceTimer`, `livenessTimer`, `staleTimer`, `pollTimer`.
- All new tests go in `tests/core/stores/tst_run_store.qml` (headless store tier). No test sleeps: timers are checked via `running` and fired via `triggered()`.
- The existing 3.1 tests in `tst_run_store.qml` stay unchanged and green.
- `tests/run.sh` fails a QML file on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` in its output, so the store must never throw on a watch line.

## Review Focus

- A snapshot reply that lands after the panel closed: the runs are applied but no watch, stale clock or liveness timer starts — pinned by `test_snapshot_landing_after_deactivation_starts_nothing` (Task 5).
- Rapid close/open/close/open before the next reply: only the latest activation's snapshot counts and exactly one new watch starts — pinned by `test_reactivation_starts_a_new_watch` (Task 4).
- A project with zero runs (or entries without an id): it is still watched with the project root alone, and no empty argv element is passed — pinned by `test_watch_with_no_runs_watches_the_project_alone` and the id-less entry in `test_watch_argv_after_first_snapshot` (Task 1).
- The project cleared to "" while the panel is open: the watch and stale clock stop and no snapshot is launched — pinned by `test_clearing_the_project_while_active_stops_everything` (Task 6).
- The watch dying with no envelope (killed, crashed) and a non-zero exit: `lastError` names the exit code and no poll or restart happens — pinned by `test_watch_exit_without_envelope_names_the_exit_code` (Task 7).

---

### Task 1: `active`, activation refresh, and starting the watch after the first good snapshot

**Files:**
- Create: `tests/stubs/Quickshell/Io/SplitParser.qml`
- Modify: `tests/stubs/Quickshell/Io/qmldir`
- Modify: `core/stores/RunStore.qml` (header comment lines 6-10, properties lines 14-22, after `refresh()` lines 26-29, `applySnapshot` ok-branch lines 88-91, after the `HelperRunner` block lines 114-121)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: 3.1's `refresh()`, `applySnapshot(stdout, exitCode)`, `snapshotRunner`, test helpers `make()`, `makeWithProject(root)`, `reply(proc, text, code)`, `entry(id, runStatus, live)`, `okReply(entries)`, properties `rootA` ("/home/u/my proj"), `rootB` ("/home/u/b").
- Produces: `property bool active`; `property bool watchTried`; `readonly property alias watching` (bool); `readonly property alias watchProc` (Process or null); `function startLive()`; `function startWatch()`; `QtObject { id: watchState; property var proc; property bool watching }`; `Component { id: watchC; Process { id: wp; objectName: "watchProc" } }`. Test helpers `activeStore(root)` and `watchedStore(entries)`.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/core/stores/tst_run_store.qml`, after `test_a_good_reply_after_an_error_restores_ok()` and before the file's final `}`:

```qml

  // ---- live refresh (3.2)

  // An active store (the panel is open) with project `root`: its first snapshot
  // is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.project = root
    return store
  }

  // An active store on project A whose first snapshot listed `entries`, so its
  // watch is running.
  function watchedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  // ---- activation and watch start

  function test_activation_refreshes_the_project() {
    var store = makeWithProject(rootA); if (!store) return
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel fetches a fresh snapshot")
    compare(store.snapshotRunner.current.command[2], "/home/u/my proj")
  }

  function test_activation_without_a_project_launches_nothing() {
    var store = make(); if (!store) return
    store.active = true
    verify(!store.snapshotRunner.current, "no snapshot without a project")
    verify(!store.watchProc, "no watch without a project")
    compare(store.watching, false)
  }

  function test_watch_not_started_before_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    verify(store.snapshotRunner.current, "the first snapshot is in flight")
    verify(!store.watchProc, "no watch before the first snapshot reply")
    compare(store.watching, false)
  }

  function test_watch_argv_after_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    var noId = { workflow: "orchestrator" }
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), noId, entry("b", "done", false)]), 0)
    compare(store.runs.length, 3)
    var w = store.watchProc
    verify(w, "the first good snapshot starts the watch")
    compare(w.objectName, "watchProc")
    compare(w.command.length, 5, "a run without an id adds no empty argument")
    compare(w.command[0], "python3")
    compare(w.command[1], "/plugin/core/backend/runs/runs-watch.py")
    compare(w.command[2], "/home/u/my proj", "the path with a space is one argument")
    compare(w.command[3], "a")
    compare(w.command[4], "b")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_watch_with_no_runs_watches_the_project_alone() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var w = store.watchProc
    verify(w, "an empty project is watched too: its first run must show up")
    compare(w.command.length, 3)
    compare(w.command[2], "/home/u/my proj")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_watch_not_started_when_inactive() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.runs.length, 1)
    verify(!store.watchProc, "a closed panel never watches")
    compare(store.watching, false)
  }

  function test_failed_first_snapshot_does_not_start_watch() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n', 1)
    verify(!store.watchProc, "a failed snapshot starts no watch")
    compare(store.watching, false)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(store.watchProc.command[3], "a")
    compare(store.watching, true)
  }

  function test_second_snapshot_does_not_restart_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("c", "started", true)]), 0)
    verify(store.watchProc === w, "the running watch is kept")
    compare(w.running, true)
    compare(w.command.length, 4, "its argv is not rewritten: the helper picks up new runs itself")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: the `== tests/core/stores/tst_run_store.qml` section shows `FAIL!  : StoresRunStore::test_activation_refreshes_the_project()` and FAILs for the other new tests (no `active`, `watching` or `watchProc` on the store; `run.sh` may also print a `non-existent property` line). The 3.1 tests still pass.

- [ ] **Step 3: Add the SplitParser test stub**

Create `tests/stubs/Quickshell/Io/SplitParser.qml`:

```qml
import QtQuick
QtObject { property string splitMarker: "\n"; signal read(string data) }
```

In `tests/stubs/Quickshell/Io/qmldir`, replace:

```
FileView 1.0 FileView.qml
```

with:

```
FileView 1.0 FileView.qml
SplitParser 1.0 SplitParser.qml
```

- [ ] **Step 4: Write the minimal implementation in `core/stores/RunStore.qml`**

Replace the header comment:

```qml
// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run
// and whether `am` could be asked at all. The project root and the backend
// directory are handed to it from outside -- it never reaches for another
// store. The live watch (3.2) and composing it into App (3.3) come later.
```

with:

```qml
// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run
// and whether `am` could be asked at all. While `active` (the panel is open) a
// long-lived runs-watch.py says which runs changed, and each burst of changes
// costs one debounced snapshot. The project root and the backend directory are
// handed to it from outside -- it never reaches for another store. Composing
// it into App (3.3) comes later.
```

Replace:

```qml
  property string backendDir: ""      // <plugin>/core/backend/
```

with:

```qml
  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open" (3.3)
```

Replace:

```qml
  property string lastError: ""

  readonly property alias snapshotRunner: snapshotRunner
```

with:

```qml
  property string lastError: ""

  // A watch has been started since the last activation or project switch:
  // later snapshots never start another (the helper picks up the project's new
  // runs itself), and a watch that ended is not restarted until the next
  // activation or project switch.
  property bool watchTried: false

  readonly property alias watching: watchState.watching   // the footer's "watching"
  readonly property alias watchProc: watchState.proc      // the current watch Process, or null
  readonly property alias snapshotRunner: snapshotRunner
```

Replace:

```qml
    snapshotRunner.run([store.project])
  }
```

with:

```qml
    snapshotRunner.run([store.project])
  }

  onActiveChanged: {
    if (store.active) store.startLive()
  }

  // The panel opened: fetch now; the first good snapshot starts the watch.
  function startLive() {
    store.watchTried = false
    store.refresh()
  }

  // runs-watch.py for this project and the runs the snapshot just listed, in
  // its order. Long-lived, so a plain Process rather than the HelperRunner.
  function startWatch() {
    store.watchTried = true
    var ids = []
    for (var i = 0; i < store.runs.length; i++) {
      var id = store.runs[i].id
      if (typeof id === "string" && id !== "") ids.push(id)
    }
    var proc = watchC.createObject(store)
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py", store.project].concat(ids)
    watchState.proc = proc
    watchState.watching = true
    proc.running = true
  }
```

In `applySnapshot`, replace:

```qml
      store.runs = out
      store.amStatus = "ok"
      store.lastError = ""
      return
```

with:

```qml
      store.runs = out
      store.amStatus = "ok"
      store.lastError = ""
      if (store.active && !store.watchTried) store.startWatch()
      return
```

Replace the end of the file:

```qml
    onFinished: function(stdout, exitCode) { store.applySnapshot(stdout, exitCode) }
  }
}
```

with:

```qml
    onFinished: function(stdout, exitCode) { store.applySnapshot(stdout, exitCode) }
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
  QtObject {
    id: watchState
    property var proc: null
    property bool watching: false
  }

  // One Process per watch launch, so each carries what it was launched with.
  Component {
    id: watchC

    Process {
      id: wp
      objectName: "watchProc"
      stdout: SplitParser {}
      stderr: StdioCollector { waitForEnd: true }
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `Totals:` line for `tst_run_store.qml` with `0 failed`, no `TypeError`/`non-existent` lines.

- [ ] **Step 6: Commit**

```bash
git add tests/stubs/Quickshell/Io/SplitParser.qml tests/stubs/Quickshell/Io/qmldir core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): start the runs watch after the first good snapshot while active"
```

---

### Task 2: `changed` lines restart a 250 ms debounce that costs one snapshot

**Files:**
- Modify: `core/stores/RunStore.qml` (aliases block, after `startWatch()`, the `watchC` Component, before the `watchState` QtObject)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `watchedStore(entries)`, `store.watchProc` (its `stdout` is a SplitParser with signal `read(string data)`), `snapshotRunner.seq`.
- Produces: `readonly property alias debounceTimer` (Timer, objectName "debounceTimer"); `function watchLine(proc, data)`; test helper `sendLine(proc, value)` (value is an object, JSON-stringified, or a raw string).

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, after `test_second_snapshot_does_not_restart_watch()`:

```qml

  // ---- debounce

  // One stdout line of a watch: an object is sent as its JSON, a string as is.
  function sendLine(proc, value) {
    proc.stdout.read(typeof value === "string" ? value : JSON.stringify(value))
  }

  function test_changed_line_starts_debounce() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var t = store.debounceTimer
    compare(t.objectName, "debounceTimer")
    compare(t.interval, 250)
    compare(t.repeat, false)
    compare(t.running, false, "idle until a line arrives")
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    compare(t.running, true)
    compare(store.snapshotRunner.seq, seq, "a line alone launches no snapshot")
  }

  function test_burst_coalesces_to_one_snapshot() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    sendLine(store.watchProc, { changed: ["b"] })
    sendLine(store.watchProc, '{"changed": ["a", "c"]}')
    compare(store.snapshotRunner.seq, seq, "no snapshot during the burst")
    store.debounceTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the burst cost exactly one snapshot")
    compare(store.snapshotRunner.current.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
  }

  function test_garbage_watch_line_ignored() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var lines = ["", "   ", "not json {", "[]", "null", "3", '"changed"', "{}", '{"hello": 1}', '{"changed": "a"}', '{"changed": null}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.debounceTimer.running, false, JSON.stringify(lines[i]) + " is ignored")
    }
    compare(store.watching, true, "the watch keeps running")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: FAIL for `test_changed_line_starts_debounce`, `test_burst_coalesces_to_one_snapshot` and `test_garbage_watch_line_ignored` (`store.debounceTimer` is undefined; `run.sh` prints the `TypeError`).

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace:

```qml
  readonly property alias snapshotRunner: snapshotRunner
```

with:

```qml
  readonly property alias snapshotRunner: snapshotRunner
  readonly property alias debounceTimer: debounceTimer
```

Replace:

```qml
    watchState.watching = true
    proc.running = true
  }
```

with:

```qml
    watchState.watching = true
    proc.running = true
  }

  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
  // anything else -- blank, not JSON, not an object -- is ignored. Never throws.
  function watchLine(proc, data) {
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) debounceTimer.restart()
  }
```

Replace:

```qml
      stdout: SplitParser {}
```

with:

```qml
      stdout: SplitParser { onRead: function(data) { store.watchLine(wp, data) } }
```

Replace:

```qml
  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

with:

```qml
  // A burst of changed lines costs one snapshot.
  Timer {
    id: debounceTimer
    objectName: "debounceTimer"
    interval: 250
    repeat: false
    onTriggered: store.refresh()
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): debounce watch change lines into one snapshot"
```

---

### Task 3: 10 s liveness timer only while active and a run is running

**Files:**
- Modify: `core/stores/RunStore.qml` (aliases block, before `refresh()`, before the `watchState` QtObject)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `Runs.runState(run)` (returns "running" for status "started" with `lease.live === true`, "dead" for started without a live lease, "parked" for "stopped", "done" for "done"), `watchedStore`, `makeWithProject`.
- Produces: `readonly property bool hasRunningRun`; `readonly property alias livenessTimer` (Timer, objectName "livenessTimer", `running` bound to `store.active && store.hasRunningRun`).

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, after `test_garbage_watch_line_ignored()`:

```qml

  // ---- liveness

  function test_liveness_on_with_running_run() {
    var store = watchedStore([entry("a", "done", false), entry("b", "started", true)]); if (!store) return
    var t = store.livenessTimer
    compare(t.objectName, "livenessTimer")
    compare(t.interval, 10000)
    compare(t.repeat, true)
    compare(t.running, true, "a started run with a live lease is re-read")
  }

  function test_liveness_off_without_running_run() {
    var store = watchedStore([entry("d", "started", false), entry("p", "stopped", true), entry("f", "done", false)]); if (!store) return
    compare(store.livenessTimer.running, false, "dead, parked and done runs need no liveness re-read")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("d", "started", true)]), 0)
    compare(store.livenessTimer.running, true, "it starts once a run is running")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("d", "done", false)]), 0)
    compare(store.livenessTimer.running, false, "and stops when none is")
  }

  function test_liveness_off_when_inactive() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.livenessTimer.running, false, "no timer while the panel is closed")
    store.active = true
    compare(store.livenessTimer.running, true, "opening the panel with a running run starts it")
  }

  function test_liveness_tick_refreshes() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "each tick fetches a snapshot")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: FAIL for the four `test_liveness_*` tests (`store.livenessTimer` is undefined).

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace:

```qml
  readonly property alias debounceTimer: debounceTimer
```

with:

```qml
  readonly property alias debounceTimer: debounceTimer
  readonly property alias livenessTimer: livenessTimer
```

Replace:

```qml
  // Asks for a fresh snapshot of the current project. A newer call replaces an
```

with:

```qml
  // Some run is started with a live lease: its heartbeat must be re-read even
  // when the journal is quiet.
  readonly property bool hasRunningRun: {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (Runs.runState(list[i]) === "running") return true
    }
    return false
  }

  // Asks for a fresh snapshot of the current project. A newer call replaces an
```

Replace:

```qml
  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

with:

```qml
  // Only while the panel is open and a run is running: no timer while idle.
  Timer {
    id: livenessTimer
    objectName: "livenessTimer"
    interval: 10000
    repeat: true
    running: store.active && store.hasRunningRun
    onTriggered: store.refresh()
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): re-read running runs every 10 s while the panel is open"
```

---

### Task 4: Deactivation kills the watch and its timers, re-activation watches again

**Files:**
- Modify: `core/stores/RunStore.qml` (`onActiveChanged`, after `startLive()`)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `startLive()`, `watchState`, `debounceTimer`, `livenessTimer` (bound to `active`), `sendLine`, `watchedStore`.
- Produces: `function stopLive()`; `function stopWatch()` (sets the current watch's `running = false` and clears `watching`).

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, after `test_liveness_tick_refreshes()`:

```qml

  // ---- deactivation

  function test_deactivate_kills_watch_and_timers() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    store.selectedRunId = "a"
    var w = store.watchProc
    sendLine(w, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    compare(store.livenessTimer.running, true)
    store.active = false
    compare(w.running, false, "the watch is killed")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "the pending refresh is dropped")
    compare(store.livenessTimer.running, false)
    compare(store.runs.length, 1, "the runs stay for the next opening")
    compare(store.runs[0].id, "a")
    compare(store.selectedRunId, "a")
    compare(store.amStatus, "ok")
  }

  function test_reactivation_starts_a_new_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    store.active = true
    var first = store.snapshotRunner.current
    store.active = false
    store.active = true
    var second = store.snapshotRunner.current
    verify(first !== second, "each opening fetches its own snapshot")
    compare(old.running, false, "the old watch stays dead")
    reply(first, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc === old, "the superseded opening's late reply starts nothing")
    compare(store.watching, false)
    reply(second, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old, "the latest opening's first good snapshot starts a new watch")
    compare(fresh.running, true)
    compare(fresh.command[3], "a")
    compare(store.watching, true)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: FAIL for `test_deactivate_kills_watch_and_timers` (`w.running` is still true) and `test_reactivation_starts_a_new_watch` (`old.running` is still true; no new watch starts because `watchTried` is never reset by a deactivation).

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace:

```qml
  onActiveChanged: {
    if (store.active) store.startLive()
  }
```

with:

```qml
  onActiveChanged: {
    if (store.active) store.startLive()
    else store.stopLive()
  }
```

Replace:

```qml
  function startLive() {
    store.watchTried = false
    store.refresh()
  }
```

with:

```qml
  function startLive() {
    store.watchTried = false
    store.refresh()
  }

  // The panel closed: no process and no timer is left running. The runs, the
  // selection and amStatus stay for the next opening.
  function stopLive() {
    store.stopWatch()
    debounceTimer.stop()
  }

  function stopWatch() {
    if (watchState.proc) watchState.proc.running = false
    watchState.watching = false
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): stop the watch and its timers when the panel closes"
```

---

### Task 5: The 30 s `stale` flag

**Files:**
- Modify: `core/stores/RunStore.qml` (properties, aliases, `startLive()`/`stopLive()`, `applySnapshot` ok-branch, `projectSwitched()`, before the `watchState` QtObject)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `startLive()`, `stopLive()`, `applySnapshot`, `projectSwitched()`, `watchedStore`, `activeStore`, `makeWithProject`.
- Produces: `property bool stale`; `readonly property alias staleTimer` (Timer, objectName "staleTimer"); `function restartStale()` (clears `stale`; restarts `staleTimer` when `active && project !== ""`, else stops it). Test helper `fire(timer)` (stops a non-repeating timer, then emits `triggered()`, as a real firing does).

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, after `test_reactivation_starts_a_new_watch()`:

```qml

  // ---- stale

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  function test_stale_timer_runs_only_while_active() {
    var store = makeWithProject(rootA); if (!store) return
    var t = store.staleTimer
    compare(t.objectName, "staleTimer")
    compare(t.interval, 30000)
    compare(t.repeat, false)
    compare(t.running, false, "no stale clock while the panel is closed")
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(t.running, false, "a good snapshot while closed starts no clock")
    store.active = true
    compare(t.running, true, "opening the panel starts the clock")
    compare(store.stale, false)
  }

  function test_stale_after_timer_fires() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "a good snapshot (re)starts the clock")
    fire(store.staleTimer)
    compare(store.stale, true)
    compare(store.runs.length, 1, "stale is not a run state: the runs are untouched")
    compare(store.runs[0].status, "done")
  }

  function test_good_snapshot_clears_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the clock counts from this snapshot")
  }

  function test_failed_snapshot_keeps_stale_timer_running() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var failure = '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n'
    store.refresh()
    reply(store.snapshotRunner.current, failure, 1)
    compare(store.staleTimer.running, true, "a failed snapshot leaves the clock running")
    compare(store.stale, false)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, failure, 1)
    compare(store.stale, true, "a failed snapshot does not clear stale")
    compare(store.staleTimer.running, false, "nor restart the clock")
  }

  function test_stale_cleared_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.active = false
    compare(store.stale, false)
    compare(store.staleTimer.running, false)
    compare(store.runs.length, 1)
  }

  function test_project_switch_resets_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.project = rootB
    compare(store.stale, false, "A's snapshot age says nothing about B")
    compare(store.staleTimer.running, true, "B's clock starts now")
  }

  function test_snapshot_landing_after_deactivation_starts_nothing() {
    var store = activeStore(rootA); if (!store) return
    var proc = store.snapshotRunner.current
    store.active = false
    reply(proc, okReply([entry("a", "started", true)]), 0)
    compare(store.runs.length, 1, "the runs are still applied")
    verify(!store.watchProc, "no watch for a closed panel")
    compare(store.watching, false)
    compare(store.staleTimer.running, false)
    compare(store.livenessTimer.running, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: FAIL for all seven new tests (`store.staleTimer` is undefined).

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace:

```qml
  property string lastError: ""
```

with:

```qml
  property string lastError: ""
  property bool stale: false          // the last good snapshot is over 30 s old while active
```

Replace:

```qml
  readonly property alias livenessTimer: livenessTimer
```

with:

```qml
  readonly property alias livenessTimer: livenessTimer
  readonly property alias staleTimer: staleTimer
```

Replace:

```qml
  // The panel opened: fetch now; the first good snapshot starts the watch.
  function startLive() {
    store.watchTried = false
    store.refresh()
  }

  // The panel closed: no process and no timer is left running. The runs, the
  // selection and amStatus stay for the next opening.
  function stopLive() {
    store.stopWatch()
    debounceTimer.stop()
  }
```

with:

```qml
  // The panel opened: fetch now; the first good snapshot starts the watch, and
  // the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.restartStale()
    store.refresh()
  }

  // The panel closed: no process and no timer is left running. The runs, the
  // selection and amStatus stay for the next opening.
  function stopLive() {
    store.stopWatch()
    debounceTimer.stop()
    staleTimer.stop()
    store.stale = false
  }

  // Nothing is stale yet; the 30 s clock starts again while there is something
  // to watch.
  function restartStale() {
    store.stale = false
    if (store.active && store.project !== "") staleTimer.restart()
    else staleTimer.stop()
  }
```

Replace:

```qml
  function projectSwitched() {
    store.runs = []
```

with:

```qml
  function projectSwitched() {
    store.restartStale()
    store.runs = []
```

In `applySnapshot`, replace:

```qml
      store.amStatus = "ok"
      store.lastError = ""
      if (store.active && !store.watchTried) store.startWatch()
      return
```

with:

```qml
      store.amStatus = "ok"
      store.lastError = ""
      store.stale = false
      if (store.active) {
        staleTimer.restart()
        if (!store.watchTried) store.startWatch()
      }
      return
```

Replace:

```qml
  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

with:

```qml
  // Fires 30 s after the last good snapshot (or the activation) while open.
  Timer {
    id: staleTimer
    objectName: "staleTimer"
    interval: 30000
    repeat: false
    onTriggered: store.stale = true
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): flag the runs stale 30 s after the last good snapshot"
```

---

### Task 6: Project switch stops the watch; a launch guard drops a dead watch's lines

**Files:**
- Modify: `core/stores/RunStore.qml` (properties, `startWatch()`, `stopWatch()`, `watchLine()`, `projectSwitched()`, the `watchC` Component)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `stopWatch()`, `restartStale()`, `watchLine(proc, data)`, `sendLine`, `watchedStore`, `rootB`.
- Produces: `property int watchSeq` (bumped on every watch start and stop); Process properties `launchSeq` (int) and `launchProject` (string); `function isCurrentWatch(proc)` (true when `proc.launchSeq === watchSeq && proc.launchProject === project`).

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, after `test_snapshot_landing_after_deactivation_starts_nothing()`:

```qml

  // ---- project switch and the launch guard

  function test_project_switch_stops_watch_and_clears_runs() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    store.project = rootB
    compare(old.running, false, "the old project's watch is stopped")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "its pending refresh is dropped")
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.current.command[2], "/home/u/b", "B's snapshot is requested")
  }

  function test_new_project_watch_starts_after_its_snapshot() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true)]), 0)
    var w = store.watchProc
    verify(w !== old, "B gets its own watch")
    compare(w.command.length, 4)
    compare(w.command[2], "/home/u/b")
    compare(w.command[3], "b1")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_old_watch_lines_ignored_after_switch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.project = rootB
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "the old watch's late line is dropped")
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true)]), 0)
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "even once B's watch runs")
    sendLine(store.watchProc, { changed: ["b1"] })
    compare(store.debounceTimer.running, true, "B's own lines still count")
  }

  function test_killed_watch_lines_ignored_after_deactivation() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "a killed watch's late line is dropped")
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc !== old)
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "same project, but an older launch")
  }

  function test_clearing_the_project_while_active_stops_everything() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    var seq = store.snapshotRunner.seq
    store.project = ""
    compare(old.running, false, "the watch is stopped")
    compare(store.watching, false)
    compare(store.staleTimer.running, false, "nothing to be stale about")
    compare(store.livenessTimer.running, false, "no runs, no liveness")
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.seq, seq, "no snapshot without a project")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: FAIL for `test_project_switch_stops_watch_and_clears_runs` (`old.running` still true), `test_new_project_watch_starts_after_its_snapshot` (no new watch: `watchTried` not reset), `test_old_watch_lines_ignored_after_switch` and `test_killed_watch_lines_ignored_after_deactivation` (the old watch's line restarts the debounce), and `test_clearing_the_project_while_active_stops_everything` (`old.running` still true).

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace:

```qml
  property bool watchTried: false
```

with:

```qml
  property bool watchTried: false
  property int watchSeq: 0            // bumped on every watch start and stop: the launch guard
```

Replace:

```qml
  function startWatch() {
    store.watchTried = true
```

with:

```qml
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
```

Replace:

```qml
    var proc = watchC.createObject(store)
```

with:

```qml
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq, launchProject: store.project })
```

Replace:

```qml
  function stopWatch() {
    if (watchState.proc) watchState.proc.running = false
```

with:

```qml
  function stopWatch() {
    store.watchSeq += 1
    if (watchState.proc) watchState.proc.running = false
```

Replace:

```qml
  function watchLine(proc, data) {
    var text = String(data || "").trim()
```

with:

```qml
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
```

Replace:

```qml
  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
```

with:

```qml
  // A line or exit counts only from the newest launch, for the project it was
  // launched for: a watch that was stopped (project switch, panel closed) may
  // still print or exit late.
  function isCurrentWatch(proc) {
    return proc.launchSeq === store.watchSeq && proc.launchProject === store.project
  }

  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
```

Replace:

```qml
  function projectSwitched() {
    store.restartStale()
```

with:

```qml
  function projectSwitched() {
    store.stopWatch()
    store.watchTried = false
    debounceTimer.stop()
    store.restartStale()
```

Replace:

```qml
      objectName: "watchProc"
```

with:

```qml
      objectName: "watchProc"
      property int launchSeq: 0
      property string launchProject: ""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): stop the watch on a project switch and guard its late lines"
```

---

### Task 7: Watch exit handling and the 5 s fallback poll

**Files:**
- Modify: `core/stores/RunStore.qml` (properties, aliases, `stopLive()`, `watchLine()`, after `watchLine()`, `projectSwitched()`, `applySnapshot` ok-branch, the `watchC` Component, before the `watchState` QtObject)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `isCurrentWatch(proc)`, `stopWatch()`, `restartStale()`, `Runs.errorText(envelope)` (gives "type: message"), `sendLine`, `fire`, `watchedStore`.
- Produces: `property string watchWarning`; `property string watchSchemaError`; `readonly property alias pollTimer` (Timer, objectName "pollTimer"); `function startPoll()`; `function stopPoll()`; `function watchExited(proc, exitCode)`; Process property `envelope` (var, last `{"ok": false, ...}` line); test helpers `watchError(type, message)` and `endWatch(proc, line, code)`.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase`, after `test_clearing_the_project_while_active_stops_everything()`:

```qml

  // ---- watch exit and the fallback poll

  function watchError(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } })
  }

  // The watch prints its last line (none when `line` is ""), then exits.
  function endWatch(proc, line, code) {
    if (line !== "") sendLine(proc, line)
    proc.exited(code)
  }

  function test_schema_mismatch_falls_back_to_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var t = store.pollTimer
    compare(t.objectName, "pollTimer")
    compare(t.interval, 5000)
    compare(t.repeat, true)
    compare(t.running, false, "no poll while the watch works")
    var msg = "am watch speaks journal schema 2; this helper reads schema 1."
    endWatch(store.watchProc, watchError("SchemaMismatch", msg), 1)
    compare(store.amStatus, "schema")
    compare(store.lastError, "SchemaMismatch: " + msg)
    compare(store.watching, false)
    compare(t.running, true)
    var seq = store.snapshotRunner.seq
    t.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "a poll tick fetches a snapshot")
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.watching, false, "the poll replaces the watch: none is restarted")
    compare(t.running, true)
  }

  function test_schema_banner_survives_poll_snapshots() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    store.pollTimer.triggered()
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.runs[0].status, "done", "the polled snapshot is applied")
    compare(store.amStatus, "schema", "the banner stays while polling")
    compare(store.lastError, "SchemaMismatch: schema 2")
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the stale rule still applies while polling")
  }

  function test_corrupt_journal_sets_warning_and_polls() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "journal line 12 is not JSON"), 1)
    compare(store.watchWarning, "CorruptJournal: journal line 12 is not JSON")
    compare(store.amStatus, "ok", "a warning chip, not a banner")
    compare(store.lastError, "")
    compare(store.watching, false)
    compare(store.pollTimer.running, true)
    var seq = store.snapshotRunner.seq
    store.pollTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1)
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.watchWarning, "CorruptJournal: journal line 12 is not JSON", "the chip stays while polling")
    compare(store.amStatus, "ok")
    compare(store.watching, false)
  }

  function test_poll_stops_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.pollTimer.running, true)
    store.active = false
    compare(store.pollTimer.running, false)
    compare(store.amStatus, "schema", "deactivation leaves amStatus as it is")
    compare(store.lastError, "SchemaMismatch: schema 2")
    store.active = true
    compare(store.pollTimer.running, false, "the next opening tries the watch first")
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.amStatus, "ok", "a good snapshot after re-opening resets the status")
    compare(store.lastError, "")
    compare(store.watching, true, "and the watch is tried again")
  }

  function test_corrupt_warning_cleared_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.watchWarning, "CorruptJournal: bad")
    store.active = false
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
  }

  function test_other_watch_error_stops_watching_without_poll() {
    var cases = [["HelperError", 1], ["AmMissing", 1], ["Usage", 2]]
    for (var i = 0; i < cases.length; i++) {
      var type = cases[i][0]
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      endWatch(store.watchProc, watchError(type, "m"), cases[i][1])
      compare(store.watching, false, type)
      compare(store.lastError, type + ": m")
      compare(store.amStatus, "ok", type + " is not a schema banner")
      compare(store.watchWarning, "", type + " is not a warning chip")
      compare(store.pollTimer.running, false, type + " starts no poll")
      store.refresh()
      reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
      compare(store.watching, false, type + ": no restart until the next opening")
    }
  }

  function test_watch_exit_without_envelope_names_the_exit_code() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, "", 137)
    compare(store.watching, false)
    verify(store.lastError.indexOf("exit 137") >= 0, "the exit code is named: " + store.lastError)
    compare(store.pollTimer.running, false)
    compare(store.amStatus, "ok")
  }

  function test_watch_exit_zero_only_clears_watching() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    sendLine(store.watchProc, { changed: ["a"] })
    endWatch(store.watchProc, "", 0)
    compare(store.watching, false)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
    compare(store.debounceTimer.running, true, "the pending refresh still happens")
    compare(store.livenessTimer.running, true)
    compare(store.runs.length, 1)
  }

  function test_stale_exit_after_reactivation_ignored() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old)
    compare(store.watching, true)
    old.exited(0)
    compare(store.watching, true, "the killed watch's late exit does not end the new one")
    compare(fresh.running, true)
  }

  function test_old_watch_exit_ignored_after_switch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.project = rootB
    endWatch(old, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.amStatus, "ok", "A's watch says nothing about B")
    compare(store.lastError, "")
    compare(store.pollTimer.running, false)
  }

  function test_project_switch_clears_warning_and_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.pollTimer.running, true)
    store.project = rootB
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
    compare(store.watching, false)
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    compare(store.watching, true, "B's watch is tried")
    compare(store.watchProc.command[2], "/home/u/b")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash ./tests/run.sh tst_run_store`
Expected: FAIL for every new test that reads `pollTimer`, `watchWarning` or expects a reaction to `exited` (`test_schema_mismatch_falls_back_to_poll`, `test_schema_banner_survives_poll_snapshots`, `test_corrupt_journal_sets_warning_and_polls`, `test_poll_stops_on_deactivate`, `test_corrupt_warning_cleared_on_deactivate`, `test_other_watch_error_stops_watching_without_poll`, `test_watch_exit_without_envelope_names_the_exit_code`, `test_watch_exit_zero_only_clears_watching`, `test_old_watch_exit_ignored_after_switch`, `test_project_switch_clears_warning_and_poll`). `test_stale_exit_after_reactivation_ignored` passes already (nothing reacts to `exited` yet); it pins the launch guard against the exit handler added next.

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunStore.qml`, replace:

```qml
  property bool stale: false          // the last good snapshot is over 30 s old while active
```

with:

```qml
  property bool stale: false          // the last good snapshot is over 30 s old while active
  property string watchWarning: ""    // the corrupt-journal chip; "" when there is none
```

Replace:

```qml
  property int watchSeq: 0            // bumped on every watch start and stop: the launch guard
```

with:

```qml
  property int watchSeq: 0            // bumped on every watch start and stop: the launch guard
  property string watchSchemaError: "" // the schema banner text while its fallback poll runs
```

Replace:

```qml
  readonly property alias staleTimer: staleTimer
```

with:

```qml
  readonly property alias staleTimer: staleTimer
  readonly property alias pollTimer: pollTimer
```

Replace:

```qml
    debounceTimer.stop()
    staleTimer.stop()
    store.stale = false
  }
```

with:

```qml
    debounceTimer.stop()
    store.stopPoll()
    staleTimer.stop()
    store.stale = false
    store.watchWarning = ""
  }
```

Replace:

```qml
    if (Array.isArray(value.changed)) debounceTimer.restart()
  }
```

with:

```qml
    if (Array.isArray(value.changed)) debounceTimer.restart()
    else if (value.ok === false) proc.envelope = value
  }

  // The watch ended. Exit 0: it was stopped (by us, or because am exited).
  // Otherwise the last envelope line it printed says why: a journal the helper
  // cannot read switches to the 5 s poll; anything else is reported and the
  // watch stays off until the next activation or project switch.
  function watchExited(proc, exitCode) {
    if (!store.isCurrentWatch(proc)) return
    watchState.watching = false
    if (exitCode === 0) return
    var envelope = proc.envelope
    var err = envelope ? envelope.error : null
    var type = err !== null && typeof err === "object" ? err.type : ""
    if (type === "SchemaMismatch") {
      store.watchSchemaError = Runs.errorText(envelope)
      store.amStatus = "schema"
      store.lastError = store.watchSchemaError
      store.startPoll()
    } else if (type === "CorruptJournal") {
      store.watchWarning = Runs.errorText(envelope)
      store.startPoll()
    } else {
      store.lastError = envelope ? Runs.errorText(envelope) : "The runs watch stopped (exit " + exitCode + ")."
    }
  }

  // The poll replaces the watch signal until the panel closes or the project
  // changes.
  function startPoll() {
    pollTimer.start()
  }

  function stopPoll() {
    pollTimer.stop()
    store.watchSchemaError = ""
  }
```

Replace:

```qml
    store.watchTried = false
    debounceTimer.stop()
    store.restartStale()
```

with:

```qml
    store.watchTried = false
    debounceTimer.stop()
    store.stopPoll()
    store.watchWarning = ""
    store.restartStale()
```

In `applySnapshot`, replace:

```qml
      store.runs = out
      store.amStatus = "ok"
      store.lastError = ""
      store.stale = false
```

with:

```qml
      store.runs = out
      if (pollTimer.running && store.watchSchemaError !== "") {
        // The watch's schema banner outlives the polling snapshots.
        store.amStatus = "schema"
        store.lastError = store.watchSchemaError
      } else {
        store.amStatus = "ok"
        store.lastError = ""
      }
      store.stale = false
```

Replace:

```qml
      property string launchProject: ""
      stdout: SplitParser { onRead: function(data) { store.watchLine(wp, data) } }
      stderr: StdioCollector { waitForEnd: true }
    }
```

with:

```qml
      property string launchProject: ""
      property var envelope: null       // the last {"ok": false, ...} line it printed
      stdout: SplitParser { onRead: function(data) { store.watchLine(wp, data) } }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        store.watchExited(wp, exitCode)
        wp.destroy()
      }
    }
```

Replace:

```qml
  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

with:

```qml
  // Replaces the watch when it cannot read am's journal (schema or corrupt).
  Timer {
    id: pollTimer
    objectName: "pollTimer"
    interval: 5000
    repeat: true
    onTriggered: store.refresh()
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
```

- [ ] **Step 4: Run the store tests to verify they pass**

Run: `bash ./tests/run.sh tst_run_store`
Expected: `0 failed` for `tst_run_store.qml`, no `TypeError`/`ReferenceError`/`non-existent` lines.

- [ ] **Step 5: Run the full suite**

Run: `bash ./tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py`, which checks RunStore's imports), every `tst_*.qml` section reports `0 failed`, and the script exits 0.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): fall back to a 5 s poll when the watch cannot read the journal"
```
