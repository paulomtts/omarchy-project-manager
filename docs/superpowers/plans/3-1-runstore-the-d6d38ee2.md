# 3.1 RunStore: the snapshot of every project root — design

Card `d6d38ee2` (subtask of story `fee6bfab` "Global runs store"). Parent design:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (cited below as
**S6:line**).

## Where this card and the parent spec disagree

S6:113 says there is no `runs-snapshot-all.py`, and S6:136-137 say "there is one list error,
no per-project errors". Both lines come from the later "retarget to the new `am`" revision
(commit b839794). Milestone 2 built the per-root fan-out anyway:
`core/backend/runs/runs-snapshot-all.py` (abd9b9b, e4d0c32) and `common/am_runs.py`
(69b4bcc). This card is explicit about using it, along with `runsByProject`,
`projectErrors` and "first root wins". **The card wins for this subtask.** Every other S6
constraint cited below still holds. The planner must not switch the list call back to
`runs-snapshot.py` with no argument, and must not edit `runs-snapshot-all.py` or its pytest.

## Precondition (checked)

S6:13-17 says `Runs.normalizeRun` of a real `am status` payload has to give a populated
tree, and fixtures are recorded, never hand-shaped. Exploration confirmed this:
`tests/ui/tst_runs_real_data.qml` builds runs from `tests/fixtures/am/status-*.json`
(captured 2026-10-08 from the installed `am`, each with a `_note`) through
`tests/helpers/amFixtures.js`, and gets stories, subtasks, progress and phases. The card's
escalation clause does not fire. If a recorded payload ever normalizes to an empty tree
(no subtasks, progress 0/0, no default attempt) while this card is being implemented, STOP
and escalate. Do not adapt the model or the fixtures.

## What the store must do

### Inputs

- **`projectRoots`** is a new property of type `var`, defaulting to `[]`. Its shape is
  `[{root, name}]`, set from outside. `App.qml` binds it to
  `app.projects.projects.map(p => ({root: p.root_path, name: p.name}))`, in registry
  order. The store never reads `ProjectStore` (S6:127-129, architecture layering: stores
  import only QtQml, Quickshell, Quickshell.Io and `../domain`).
- A usable root is an entry whose `root` is a non-empty string that does not start with
  `-`. Every other entry is ignored everywhere in this spec. That covers non-objects, a
  missing, empty or non-string root, and a root starting with `-`. Such a root would make
  `runs-snapshot-all.py` refuse the whole call with `Usage`, so it must never reach argv.
  A root that appears twice is used once, at its first position, with its first name.
- **`project`** keeps its meaning: the open project's root, `""` when no project is open
  (S6:130-133). It no longer guards anything about the run list.

### Outputs (all replaced, never mutated in place)

- **`runsByProject`**: `{root: runs[]}`. It has one key per usable root that some reply
  has covered. Each value holds that root's runs in am's order, each run
  `Runs.withProject(Runs.normalizeRun({row, status}), root, name)`.
- **`projectErrors`**: `{root: message}`. It has one key per usable root whose latest
  entry failed. The message is `Runs.errorText(entry.error)`. A later ok entry for that
  root removes the key.
- **`runs`**: the concatenation of `runsByProject[root]` over the usable roots in
  `projectRoots` order, de-duplicated by run id. **The first root wins**: a run id already
  taken by an earlier root is dropped from a later one. Runs without a string id are never
  de-duplicated. Every run carries `project: {root, name}` from `Runs.withProject` with
  the root's current name. `runById`, `filteredRuns`, `hasRunningRun`, controls and alerts
  keep reading `runs` as before.

### The snapshot call

- `refresh()` launches `python3 <backendDir>runs/runs-snapshot-all.py <root> ...` with
  every usable root, in `projectRoots` order. With no usable root it launches nothing, and
  it sets `runs` to `[]`, `runsByProject` to `{}` and `projectErrors` to `{}`. Whether a
  project is open no longer matters.
- The snapshot runner's script becomes `runs-snapshot-all.py`. **It has no guard**: the
  card drops `guard: store.project` and `onGuardChanged: store.projectSwitched()`. Runners
  other than the snapshot keep their guards: logs, settings, dispatch and control are owned
  by 3.4 and 3.5 (S6:133 in full, staged by the story).
- A newer `refresh()` still replaces an older call in flight (`HelperRunner` latest-wins).
  The one-in-flight-plus-pending rule (S6:154-156) belongs to 3.2.

### Applying a reply `{ok: true, projects: [entry...], data_dir}`

Entries are matched to usable roots by exact `root` string. An entry for a root that is
not currently usable is ignored, for example one the registry dropped while the call was
in flight. A usable root that has no entry keeps its previous runs and error.

1. **Every entry failed with `AmMissing`** (the helper puts it in every entry when `am`
   is not on PATH): this behaves exactly like today's AmMissing (`RunStore.qml:690-699`).
   `runs`, `runsByProject` and `appliedSeq` are emptied, `asOfSeq` becomes 0,
   `projectErrors` becomes `{}`, `amStatus` becomes `"missing"`, `lastError` is the
   errorText, and `alertsArmed` becomes false (S6:165).
2. Otherwise, per entry:
   - `ok: true`: `runsByProject[root]` becomes its runs, normalized and given their project
     as above, and `projectErrors[root]` is removed. Rows that are not objects are
     skipped, as today.
   - `ok: false`: `runsByProject[root]` keeps its previous value, or `[]` when the root
     had none, and `projectErrors[root]` is set. This includes per-entry `StoreBusyError`,
     `RootMissing`, `AmTimeout`, `SchemaMismatch`, `RepoDirError` and `HelperError`.
3. `runs` is recomputed (merge, order, de-dup). Alerts compare the previous `runs` with
   the new `runs` exactly as today: `Runs.newAlerts(alertsArmed ? old : null, new)`. Per
   project arming is 3.4. Because a failed root keeps its runs, a failed entry never
   raises or replays an alert.
4. **At least one entry ok**: the post-good-snapshot path runs as today. That path covers
   `settleAfterSnapshot`, `logsAfterSnapshot`, `amStatus` "ok" (or the watch's schema
   banner while its poll runs), `lastError` "", `stale` false, and, while active, the
   stale timer restart, a watch start if none was tried, raising alerts and setting
   `alertsArmed`.
   **No entry ok** (and not case 1): `amStatus` becomes `"error"` and `lastError` is the
   errorText of the first failed entry in reply order. Alerts are not raised and
   `alertsArmed` is unchanged (S6:80-81: "A failed snapshot keeps the previous runs and the
   armed state"). `stale` is unchanged.
5. **Coverage**: `runs-snapshot-all.py` forwards no `as_of_seq` and no `store_id`
   (`runs-snapshot-all.py:1-30`). After a reply that is not case 1, `asOfSeq` is 0 and
   `appliedSeq` is `{id: 0}` for every run id in the new `runs`. A watch nudge for a
   listed run then always costs one run read, and a nudge for an unlisted run costs one
   list snapshot (today's `triggerNudges` rule, unchanged). The list reply never calls
   `seeStore`. `readState.rows` becomes `{id: am runs row}` for every run kept in `runs`:
   the row of an ok entry's run comes from that entry (the winning root's, for a
   de-duplicated id), and the row of a run a failed root keeps is carried over from the
   previous `readState.rows`. `applyRunRead` reads `rows[id]` to rebuild a run, so a kept
   run must not lose its row.

### Whole-call failures (unchanged from today)

- `{ok: false}` (`Usage`, `HelperError`): `amStatus` becomes `"error"` and `lastError` is
  set. Runs, `runsByProject` and `projectErrors` are kept.
- Unparseable stdout: `amStatus` becomes `"error"` and `lastError` reads "The runs snapshot
  gave no usable result (exit N)." Everything else is kept.

### Registry change

When `projectRoots` changes, the store does two things at once and in this order:

1. It drops the `runsByProject` and `projectErrors` keys of roots that are no longer
   usable, then recomputes `runs` in the new order with the new names. A removed project's
   runs leave the list immediately (S6:167), and a renamed project's runs carry the new
   name.
2. It calls `refresh()`, which snapshots every usable root.

No alert is raised by step 1.

### Opening the panel

`startLive()` snapshots every usable root, whether or not a project is open. The stale
clock runs while `active`, with no project condition: `restartStale` drops its
`project !== ""` test. A first good reply starts the watch as today. `runs-watch.py`'s argv
is 3.2's work (see Out of scope).

### A project switch changes nothing about the run list

`projectSwitched()` is no longer called by the snapshot runner. It runs on
`onProjectChanged`, and it only does what the remaining cards still own:

- **Kept for now:** the notify-switch reset and `get-run-settings` load (owned by 3.4);
  `runSettings = {}`; `resetDispatch()`; `closeCancel()`, `dismissControlError()` and
  `flash("")` (owned by 3.5); `settingsLoadRunner.guard = project` and its launch when
  `project` is non-empty.
- **No longer touched:** `runs`, `runsByProject`, `projectErrors`, `selectedRunId`,
  `selectedAttempt`, the logs fields, `runFilter`, `lastError`, `amStatus`, the watch
  (`stopWatch`, `watchTried`, the poll, `watchWarning`), `nudges` and the debounce,
  `appliedSeq`, `asOfSeq`, run reads in flight, the stale clock, `pending`,
  `stillWaiting`, the control requests' bookkeeping, `alertsArmed` and `toasts`. No
  snapshot is launched.

This is a deliberate partial fix. The header comment of `runFilter` (RunStore.qml:44-46),
which says it "is reset by a project switch", must be corrected.

What follows from it:

- **The watch survives a switch.** `isCurrentWatch(proc)` compares only `launchSeq`, not
  `launchProject`. Otherwise every line after a switch would be ignored.
- **Run reads survive a switch and work with no project open.** `readRun` no longer
  returns when `project === ""`, and `readReplied` no longer drops a reply whose `madeFor`
  differs from `project`. It stays the latest-read check only. `applyRunRead` rebuilds the
  run as `Runs.withProject(normalizeRun({row, status}), run.project.root, run.project.name)`,
  where `run` is the one being replaced, so the read run keeps its project. The rebuilt run
  also replaces the run with that id inside every `runsByProject` list whose root equals
  `run.project.root` (compared as `Runs.withProject` stores it, trailing slashes removed),
  so a registry change or a failed root's kept runs recompute `runs` from the read value,
  not the older list value. Add a store test for it (item 11).
- **A control request in flight at a switch does not hang.** Its runner keeps its guard
  (3.5 removes it), so its reply is dropped. When that drop happens and the request is
  still the pending one for its run (`requestOf(runner) !== null`), the request is
  settled: its `pending` and `stillWaiting` entries go and its buttons come back, with no
  control error. An acknowledged request (its reply landed before the switch) stays
  pending until a snapshot settles it, as today.
- **A logs fetch in flight at a switch does not hang.** Its reply is dropped by the
  logs runner's guard. `logsLoading` becomes false when that runner goes idle, and the
  shown text, error and fetch time are kept.

### Header comment

The RunStore header (RunStore.qml:6-29) states the new contract, which replaces "kept to
the selected project". The contract is: the snapshot covers every registered root through
`runs-snapshot-all.py`, `runs`, `runsByProject` and `projectErrors` are as defined above,
and a project switch leaves the run list alone. Comments state the contract only and carry
no history (card).

## Out of scope (sibling cards)

- **3.2**: `runs-watch.py` argv (roots and known run ids), `runsChanged(ids)`, refreshing
  only the roots a nudge names, one-in-flight-plus-pending, the global `stale` rule, the
  liveness re-read per root. Until 3.2 lands, the watch is launched with no argument as
  today, even though the helper now needs a root. That gap is known and is not fixed here.
- **3.3**: `projectFilter`, `groups`, display order, `filteredRuns` by group.
- **3.4**: per-project alert arming, a project name on toasts, the global notify setting,
  and removing the per-project settings read from `projectSwitched`.
- **3.5**: control, resume settings and logs for a run of any project. That card removes
  the remaining runner guards and `madeFor` drops, makes `control` work with no project
  and pass the run's `repo_dir`, and stops `projectSwitched` closing the cancel dialog,
  the control error and the flash.
- All UI (`RunsScreen`, sidebar, chips, `RunIndicator`), Navigator gates, and any change
  to `runs-snapshot-all.py`, `runs-snapshot.py`, `runs.js` or the fixtures.

## Tests

Tests come first (TDD). QML store tests drive the stubbed `HelperRunner` / `Process`
(`tests/stubs`) through `proc.outText` plus `proc.exited(code)`. Snapshot entries are built
from recorded fixtures with `amFixtures.load("runs.json")` / `status-*.json`. Each fixture's
`_am_runs_row` and `data` give `{...row, status: data}`. Synthetic `entry()` rows are
allowed only where a case needs ids or states the recordings do not have, such as
duplicates or many roots. A new helper `allReply([{root, ok, runs|error}])` builds the
`runs-snapshot-all.py` line.

Run a single file with
`QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input <file>`.
The gate is `bash tests/run.sh` green (card), which includes `tests/architecture`.

### `tests/core/stores/tst_run_store.qml` (store tier: the behaviour is the store's own)

1. **argv**: with roots A, B and no project, `refresh()` launches exactly
   `["python3", "/plugin/core/backend/runs/runs-snapshot-all.py", A, B]`. Unusable roots
   (`""`, `"-x"`, non-string, a non-object entry) and a repeated root are left out. No
   usable root means no launch and empty outputs.
2. **multi-project merge and order**: a reply for A and B with recorded rows gives
   `runsByProject` per root, and `runs` in A-then-B order with each run's
   `project = {root, name}`. Swapping the `projectRoots` order swaps `runs`.
3. **de-duplication**: the same run id under A and B is listed once, under A (first root
   wins), and `runsByProject[B]` still holds its own copy.
4. **a failing project**: after a good reply for A and B, a reply where B fails
   (`AmTimeout`) keeps B's previous runs, sets `projectErrors[B]` to errorText, updates A,
   keeps `amStatus` "ok" and raises no toast. A later ok entry for B clears the error.
   Also cover a first reply where B fails: `runsByProject[B]` is `[]` and it has an error.
5. **no entry ok**: every entry fails with non-AmMissing errors, so `amStatus` is "error",
   `lastError` comes from the first entry, the previous runs are kept, and `alertsArmed`
   is unchanged.
6. **AmMissing**: every entry is `AmMissing`, so `runs`, `runsByProject`, `projectErrors`
   and `appliedSeq` are empty, `amStatus` is "missing" and `alertsArmed` is false.
7. **whole-call failure and garbage**: `{ok:false, Usage}` and non-JSON keep everything
   and set "error" with the sentences above.
8. **coverage**: after a good reply, `asOfSeq` is 0 and `appliedSeq` is `{id: 0}` for
   every listed id. A nudge for a listed run launches a run read. A nudge for an unknown id
   launches one list snapshot.
9. **registry change**: removing B drops its runs and error at once and launches a
   snapshot of A only. Renaming A changes every A run's `project.name` at once. Adding C
   launches a snapshot of A, B and C. A late reply naming a removed root ignores that
   entry.
10. **a project switch changes nothing**: with runs, a selection, a selected attempt with
    logs text, `runFilter`, a running watch, a toast, a pending request already
    acknowledged, `alertsArmed` and `appliedSeq` in place, switching `project` (A to B,
    and to `""`) leaves every one of them, launches no snapshot, and stops no watch. A
    watch line after the switch is still handled. The dispatch is still reset and
    `get-run-settings` still launches for the new project.
11. **no project needed**: with `project = ""`, `active = true` launches the snapshot of
    every root and starts the stale clock. A good reply starts the watch. A run read with
    no project launches, and its reply applies and keeps the run's `project`.
12. **interim guards don't hang**: a control request in flight at a switch is settled when
    its dropped reply's runner goes idle, with no error. A logs fetch in flight at a
    switch ends `logsLoading` and keeps the old text.

Existing tests that encode the old guard behaviour are rewritten or removed:
`test_a_project_switch_clears_runs_selection_and_error_and_refreshes`, the
"drops the old project's late result" cases, the activation and refresh-without-project
cases, and every `okReply`/`makeWithProject` use that assumes one project's reply. They
are not left failing or skipped.

### `tests/core/stores/tst_app_runs.qml` (composition tier: only App's wiring)

13. **projectRoots follows the registry**: after `applyProjectsList([pA, pB])`,
    `app.runs.projectRoots` deep-equals
    `[{root: pA.root_path, name: "alpha"}, {root: pB.root_path, name: "beta"}]`. A new
    list replaces it, and selecting or clearing a project does not change it.
14. Replace `test_the_snapshot_runs_for_the_selected_root_path` and
    `test_clearing_the_selection_empties_project_and_runs` with: the snapshot argv names
    every registered root, and clearing the selection keeps the runs.

### `tests/ui/**` (UI tier: kept green, not extended)

`tst_runs_flow.qml`, `tst_runs_real_data.qml` and the other UI tests that feed
`snapshotRunner` (grep `snapshotRunner|runs-snapshot` under `tests/ui`) move to the
`runs-snapshot-all.py` reply shape and argv. No new UI behaviour is asserted here.

## Review focus (inputs this card implies that the list above could miss)

1. A registry entry with an empty, `-`-leading or duplicate root. It must never reach argv,
   or the whole snapshot is refused with `Usage`.
2. A reply that arrives after `projectRoots` changed. Removed roots' entries are ignored,
   and new roots are not emptied.
3. A run read reply rebuilding a run. It must keep `project` or the run vanishes from
   project-grouped views.
4. A failed root's previous runs must not be compared as "new" on its recovery, which
   would replay alerts. Since they were kept, `newAlerts` sees no change.
5. A watch line after a project switch must still be handled (`isCurrentWatch`).


---

# 3.1 RunStore: the snapshot of every project root Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` snapshots every registered project root through `runs-snapshot-all.py`, keeps `runsByProject` / `projectErrors` / a merged `runs`, and a project switch no longer touches the run list.

**Architecture:** A new `projectRoots` input (bound by `App.qml` to the project registry) drives `refresh()`, which launches one `runs-snapshot-all.py` call with every usable root. Each reply entry is matched to a usable root, normalized with `Runs.normalizeRun` + `Runs.withProject`, stored per root, then merged into `runs` in registry order with "the first root wins" de-duplication. `projectSwitched()` moves to `onProjectChanged` and resets only the per-project state other cards still own. The watch, run reads, a control request in flight and a logs fetch in flight all keep working across a switch.

**Tech Stack:** QML (Qt 6, `QtQml` + the Quickshell stubs in `tests/stubs`), `core/domain/runs.js`, QtTest via `qmltestrunner`, pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/3-1-runstore-the-d6d38ee2.md` (prepended above). Parent: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md`.

## Global Constraints

- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io` and `"../domain/x.js"`. `tests/architecture/test_layers.py` enforces this. `RunStore` never reads `ProjectStore`.
- Do not edit `core/backend/runs/runs-snapshot-all.py`, `core/backend/runs/runs-snapshot.py`, `core/domain/runs.js`, `tests/fixtures/am/*` or the pytest of either helper.
- The list call is `python3 <backendDir>runs/runs-snapshot-all.py <root> ...`. Never switch it back to `runs-snapshot.py` with no argument.
- `runs-watch.py` is still launched with no argument (3.2 owns its argv). Do not change `startWatch`'s command.
- Only the snapshot runner loses its guard. Logs, settings, dispatch and control runners keep `guard: store.project` (3.4/3.5 own them).
- Comments state the contract only and carry no history ("used to", "no longer", card numbers).
- Test entries are built from recorded fixtures through `tests/helpers/amFixtures.js`. Synthetic entries (`entry()`, `ctlEntry()`) are allowed only where a case needs ids or states the recordings lack, such as duplicates, many roots or a failure. Each synthetic value gets a `// synthetic:` comment where it is not obviously synthetic.
- If a recorded payload ever normalizes to an empty tree (no subtasks, progress 0/0, no default attempt) while you implement this, STOP and escalate. Do not adapt the model or the fixtures.
- Gate: `bash tests/run.sh` green (pytest, including `tests/architecture`, then every `tst_*.qml`).
- One QML file: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input <file>`, or `bash tests/run.sh <substring-of-path>` (this one also runs pytest first).
- Process safety: never `pkill`/`killall`/`kill` by pattern. Wrap long runs in `timeout`, e.g. `timeout 600 bash tests/run.sh`.

## Review Focus

1. **A registry entry with an empty, `-`-leading, non-string or repeated root.** It must never reach argv, or `runs-snapshot-all.py` refuses the whole call with `Usage`. Pinned by `test_the_snapshot_names_every_usable_root_in_registry_order` (Task 1).
2. **The registry empties while a snapshot is in flight.** Its late reply must change nothing: no runs come back and no error banner appears, because the in-flight call is stopped. Pinned by `test_no_usable_root_launches_nothing_and_empties_the_outputs` (Task 1).
3. **An `ok: true` reply with no entry for any registered root** (no `projects` key, or only foreign roots). The spec is silent here. The plan treats it as unusable output: `amStatus` `"error"` with "The runs snapshot gave no usable result (exit N).", and the runs are kept. Otherwise an empty "every entry is AmMissing" test would vacuously empty everything. Pinned by `test_a_whole_call_failure_or_garbage_keeps_everything` (Task 1).
4. **A run read rebuilds a run.** It must keep `project`, and it must also replace the run in its root's `runsByProject` list. Otherwise a later registry change re-merges the older list value. Pinned by `test_a_read_with_no_project_open_launches_applies_and_keeps_its_project` (Task 3).
5. **A failed root's escalated run recovers.** It must not replay a toast: its runs were kept, so `newAlerts` sees no change. Pinned by `test_a_failing_root_keeps_its_runs_and_says_why` (Task 1).

---

## File Structure

- `core/stores/RunStore.qml`: the store. Task 1 handles the inputs and outputs, `refresh`, the reply, the registry change, the project-switch contract, the watch guard, the stale clock and the header. Task 3 handles run reads, the control request dropped at a switch, and the logs fetch dropped at a switch.
- `core/stores/App.qml`: binds `runs.projectRoots` to the registry (Task 2).
- `tests/core/stores/tst_run_store.qml`: store-tier tests. Task 1 adds new tests and rewrites old ones; Task 3 adds more.
- `tests/core/stores/tst_app_runs.qml`: App wiring tests (Task 2).
- `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_runs_real_data.qml`: move to the `runs-snapshot-all.py` reply shape (Task 2).

Between Task 1 and Task 2, `tst_app_runs.qml` and the two UI files above are expected to fail: App does not bind `projectRoots` yet, and their replies are still the old shape. Task 1's gate is `tst_run_store.qml` alone. Task 2 restores the full suite.

---

### Task 1: The global snapshot and the project-switch contract (store)

**Files:**
- Modify: `core/stores/RunStore.qml` (header L6-28; properties L32-75 and L110-115; `refresh` L186-192; `restartStale` L231-237; `startWatch`/`isCurrentWatch` L247-266; `triggerNudges` comment L316-320; `forgetLive` L346-357; `seeStore` comment L359-362; `watchExited`/`startPoll` comments L376-406; `projectSwitched` L413-456; `entryProject` L601-607; `applySnapshot` L616-700; runner blocks L1500-1561; `readState` comment L1657-1660; `watchC` L1767-1784)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `Runs.normalizeRun({row, status})`, `Runs.withProject(run, root, name)` (copies the run; `project = {root: root without trailing "/", name: trimmed name or root's last segment}`), `Runs.errorText(error)`, `Runs.newAlerts(prev|null, next)`.
- Produces (later tasks rely on these exact names):
  - `property var projectRoots: []`: `[{root, name}]`, set from outside.
  - `property var runsByProject: ({})`: `{root: run[]}`.
  - `property var projectErrors: ({})`: `{root: string}`.
  - `function usableRoots()` → `[{root: string, name: any}]`, first occurrence of each usable root, registry order.
  - `function taggedByProject(byProject, usable)` → `{root: run[]}` cut to the usable roots, each run carrying its root's current project.
  - `function mergedRuns(byProject, usable)` → `{runs: run[], owner: {id: root}}`.
  - `function registryChanged()`, `function applyProjects(entries, exitCode)`.
  - `snapshotRunner.script === backendDir + "runs/runs-snapshot-all.py"`, `snapshotRunner.guard === ""`.
  - Test helpers in `tst_run_store.qml`: `rootEntry(root)`, `registry(roots)`, `makeWithRoots(roots)`, `activeRoots(roots)`, `allReply(projects)`, `okEntry(root, runs)`, `failEntry(root, type, message)`, `rec(name)`, `namedStore()`, plus the properties `rootC`, `snapCmd`, `escRun` and `doneIntRun`.

- [ ] **Step 1: Replace the test file's header comment and shared helpers**

In `tests/core/stores/tst_run_store.qml`, replace lines 2-5 (the comment under the file name) with:

```qml
// The run monitor's store: the snapshot helper's exact argv, how its one JSON
// line becomes every registered root's normalized runs and an amStatus, the
// latest-wins rule, what a registry change does and what a project switch
// leaves alone. Built directly and driven through stubbed Process objects.
```

Replace the property block

```qml
  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
```

with

```qml
  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
  // The recorded escalated run (status-escalated.json) and the recorded
  // finished Integrate run (status-done-integrate.json).
  readonly property string escRun: "20261008T143755Z-f18d342f"
  readonly property string doneIntRun: "20261008T143803Z-f7f73454"
```

Replace the whole `makeWithProject` function (the comment above it included) with:

```qml
  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // A store with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var store = make(); if (!store) return null
    store.projectRoots = registry(roots)
    return store
  }

  // An active store (the panel is open) with `roots` registered and no
  // project open: the snapshot of every root is in flight.
  function activeRoots(roots) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = registry(roots)
    return store
  }

  // A store with one registered project, `root`, open: its first snapshot (of
  // that root alone) is in flight.
  function makeWithProject(root) {
    var store = make(); if (!store) return null
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }
```

Replace the whole `okReply` function (its comment included) with:

```qml
  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // One root's entry that failed with {type, message}.
  function failEntry(root, type, message) {
    return { root: root, ok: false, error: { type: type, message: message } }
  }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir. The store ignores a root it has not registered.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // A recorded snapshot entry, {...am runs row, status: am status data}:
  // "started" and "done" are runs.json's two rows with status-started.json's
  // and status-done.json's data; any other name is status-<name>.json's
  // _am_runs_row with its data.
  function rec(name) {
    if (name === "started" || name === "done") {
      var row = F.load("runs.json").data.runs[name === "started" ? 0 : 1]
      row.status = F.load("status-" + name + ".json").data
      return row
    }
    var fixture = F.load("status-" + name + ".json")
    var out = fixture._am_runs_row
    out.status = fixture.data
    return out
  }
```

- [ ] **Step 2: Add the new store tests (spec items 1-11, the snapshot half)**

Insert this section right before the line `  // ---- defaults and the snapshot command`:

```qml
  // ---- the snapshot of every registered root (3.1)

  // 1
  function test_the_snapshot_names_every_usable_root_in_registry_order() {
    var store = make(); if (!store) return
    compare(store.project, "")
    store.projectRoots = [rootEntry(tc.rootA), rootEntry(tc.rootB)]
    var proc = store.snapshotRunner.current
    verify(proc, "a registry with roots launches a snapshot, with no project open")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
    compare(proc.command[2], tc.rootA, "a root with a space is one argument")
    compare(proc.launchGuard, "", "the snapshot has no guard")
    // synthetic: registry entries runs-snapshot-all.py would refuse, and repeats.
    store.projectRoots = [{ root: "", name: "empty" }, { root: "-x", name: "dash" }, { root: 7, name: "num" },
                          { name: "none" }, null, "/home/u/str", [tc.rootC], rootEntry(tc.rootA),
                          { root: tc.rootA, name: "again" }, rootEntry(tc.rootB)]
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB,
            "unusable and repeated roots are left out")
    store.refresh()
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, "refresh() names the same roots")
  }

  // 1 (no usable root) and Review Focus 2
  function test_no_usable_root_launches_nothing_and_empties_the_outputs() {
    var bare = make(); if (!bare) return
    bare.projectRoots = [{ root: "", name: "x" }, { root: "-y", name: "y" }, null]
    verify(!bare.snapshotRunner.current, "no usable root: nothing is launched")
    bare.refresh()
    verify(!bare.snapshotRunner.current, "refresh() launches nothing either")

    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.runs.length, 1)
    compare(Object.keys(store.projectErrors).join(","), tc.rootB)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    store.projectRoots = []
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0)
    compare(Object.keys(store.projectErrors).length, 0)
    compare(store.snapshotRunner.busy, false, "nothing is in flight")
    compare(inFlight.running, false, "the snapshot in flight was stopped")
    reply(inFlight, allReply([okEntry(tc.rootA, [rec("started")])]), 0)
    compare(store.runs.length, 0, "its late reply changes nothing")
    compare(store.amStatus, "ok", "and raises no banner")
  }

  // 2
  function test_runs_merge_every_root_in_registry_order_with_its_project() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [rec("done")]),
                                                  okEntry(tc.rootA, [rec("started"), rec("escalated")])]), 0)
    compare(ids(store.runsByProject[tc.rootA]), tc.startedRun + "," + tc.escRun, "A's runs in am's order")
    compare(ids(store.runsByProject[tc.rootB]), tc.doneRun)
    compare(ids(store.runs), [tc.startedRun, tc.escRun, tc.doneRun].join(","), "A then B, whatever the reply's order")
    compare(JSON.stringify(store.runs[0].project), JSON.stringify({ root: tc.rootA, name: "alpha" }))
    compare(JSON.stringify(store.runs[2].project), JSON.stringify({ root: tc.rootB, name: "beta" }))
    compare(store.runs[0].status, "started", "normalized from the recorded am status")
    verify(store.runs[0].tree.stories.length > 0, "the recorded tree")
    compare(Object.keys(store.projectErrors).length, 0)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    compare(ids(store.runs), [tc.doneRun, tc.startedRun, tc.escRun].join(","), "the registry's order decides")
  }

  // 3
  function test_a_run_listed_under_two_roots_is_listed_once_under_the_first() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    // synthetic: the same recorded run under both roots, and a run without an id under each.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started"), entry("", "started", true)]),
                                                  okEntry(tc.rootB, [rec("started"), rec("done"), entry("", "done", false)])]), 0)
    compare(ids(store.runs), [tc.startedRun, "", tc.doneRun, ""].join(","))
    compare(store.runs[0].project.root, tc.rootA, "the first root wins")
    compare(store.runs[3].project.root, tc.rootB, "runs without an id are never de-duplicated")
    compare(ids(store.runsByProject[tc.rootB]), [tc.startedRun, tc.doneRun, ""].join(","), "B keeps its own copy")
    compare(store.runsByProject[tc.rootB][0].project.root, tc.rootB)
    compare(Object.keys(store.appliedSeq).sort().join(","), [tc.startedRun, tc.doneRun].sort().join(","))
  }

  // 4 and Review Focus 5
  function test_a_failing_root_keeps_its_runs_and_says_why() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("escalated")])]), 0)
    compare(store.alertsArmed, true)
    compare(store.toasts.length, 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started"), rec("done-integrate")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(ids(store.runsByProject[tc.rootA]), tc.startedRun + "," + tc.doneIntRun, "A is updated")
    compare(ids(store.runsByProject[tc.rootB]), tc.escRun, "B keeps its previous runs")
    compare(ids(store.runs), [tc.startedRun, tc.doneIntRun, tc.escRun].join(","))
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    compare(Object.keys(store.projectErrors).join(","), tc.rootB)
    compare(store.amStatus, "ok", "A answered")
    compare(store.lastError, "")
    compare(store.toasts.length, 0, "a failed entry raises nothing")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("escalated")])]), 0)
    compare(Object.keys(store.projectErrors).length, 0, "a good entry clears B's error")
    compare(store.toasts.length, 0, "B's recovery replays no alert")

    var first = makeWithRoots([tc.rootA, tc.rootB]); if (!first) return
    reply(first.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "RootMissing", tc.rootB + " is not a directory.")]), 0)
    verify(Object.keys(first.runsByProject).indexOf(tc.rootB) >= 0, "a first failure still lists B")
    compare(first.runsByProject[tc.rootB].length, 0)
    compare(first.projectErrors[tc.rootB], "RootMissing: /home/u/b is not a directory.")
    compare(first.amStatus, "ok")
  }

  // 5
  function test_when_no_root_answers_the_snapshot_is_an_error_and_keeps_the_runs() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "StoreBusyError", "the am store is busy; try again"),
                                                  failEntry(tc.rootB, "SchemaMismatch", "the plugin needs the newer am")]), 0)
    compare(store.amStatus, "error")
    compare(store.lastError, "StoreBusyError: the am store is busy; try again", "the first failed entry in reply order")
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun, "the previous runs stay")
    compare(store.projectErrors[tc.rootA], "StoreBusyError: the am store is busy; try again")
    compare(store.projectErrors[tc.rootB], "SchemaMismatch: the plugin needs the newer am")
    compare(store.alertsArmed, true, "the armed state is unchanged")
    compare(store.stale, true, "stale is unchanged")

    var closed = makeWithRoots([tc.rootA]); if (!closed) return
    reply(closed.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(closed.alertsArmed, false, "a disarmed store stays disarmed")
    compare(closed.amStatus, "error")
  }

  // 6
  function test_am_missing_in_every_entry_empties_everything() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.alertsArmed, true)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed."),
                                                  failEntry(tc.rootB, "AmMissing", "am is not installed.")]), 0)
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0)
    compare(Object.keys(store.projectErrors).length, 0)
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.amStatus, "missing")
    compare(store.lastError, "AmMissing: am is not installed.")
    compare(store.alertsArmed, false)
    store.refresh()
    // synthetic: AmMissing beside another failure is not "am is missing".
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed."),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.amStatus, "error")
    compare(store.lastError, "AmMissing: am is not installed.")
  }

  // 7 and Review Focus 3
  function test_a_whole_call_failure_or_garbage_keeps_everything() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage",
          message: "usage: runs-snapshot-all.py <root> [<root> ...]" } }) + "\n", 2)
    compare(store.amStatus, "error")
    compare(store.lastError, "Usage: usage: runs-snapshot-all.py <root> [<root> ...]")
    compare(ids(store.runs), tc.startedRun)
    compare(Object.keys(store.runsByProject).sort().join(","), [tc.rootA, tc.rootB].sort().join(","))
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    store.refresh()
    reply(store.snapshotRunner.current, "Traceback (most recent call last):\n  oops", 1)
    compare(store.amStatus, "error")
    compare(store.lastError, "The runs snapshot gave no usable result (exit 1).")
    compare(ids(store.runs), tc.startedRun)
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    store.refresh()
    // synthetic: an ok line with no entry for any registered root.
    reply(store.snapshotRunner.current, JSON.stringify({ ok: true, data_dir: "/d" }) + "\n", 0)
    compare(store.amStatus, "error")
    compare(store.lastError, "The runs snapshot gave no usable result (exit 0).")
    compare(ids(store.runs), tc.startedRun, "runs are kept")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootC, [rec("done")])]), 0)
    compare(store.lastError, "The runs snapshot gave no usable result (exit 0).", "a foreign root alone is no answer either")
    compare(ids(store.runs), tc.startedRun)
  }

  // 8
  function test_a_list_covers_every_listed_run_at_0_and_nudges_follow_it() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    // A project is open, whose reads these are.
    store.project = tc.rootA
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    compare(store.asOfSeq, 0)
    var want = {}
    want[tc.startedRun] = 0
    want[tc.doneRun] = 0
    compare(JSON.stringify(store.appliedSeq), JSON.stringify(want))
    verify(store.watchProc, "the watch runs")
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.doneRun, 1])
    fire(store.debounceTimer)
    compare(store.readRunners.length, 1, "a listed run costs one run read, whatever its seq")
    compare(argv(store.readRunners[0].current), tc.readCmd + tc.doneRun)
    compare(store.snapshotRunner.seq, seq, "and no list snapshot")
    // synthetic: a run am started after the list.
    nudge(store, ["20261008T150000Z-0a1b2c3d", 1006])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "an unlisted run costs one list snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // 9
  function test_a_registry_change_drops_renames_adds_and_snapshots_again() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
    compare(Object.keys(store.projectErrors).join(","), tc.rootB)
    store.projectRoots = registry([tc.rootA])
    compare(ids(store.runs), tc.startedRun, "a removed project's runs leave at once")
    compare(Object.keys(store.runsByProject).join(","), tc.rootA)
    compare(Object.keys(store.projectErrors).length, 0, "and so does its error")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "then A alone is snapshotted")
    compare(store.toasts.length, 0, "the registry change raises nothing")
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }]
    compare(store.runs[0].project.name, "renamed", "a renamed project's runs carry the new name at once")
    compare(store.runsByProject[tc.rootA][0].project.name, "renamed")
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB), rootEntry(tc.rootC)]
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC,
            "adding C snapshots every root")
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootC)]
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [rec("done")]),
                                                  okEntry(tc.rootA, [rec("started"), rec("escalated")])]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.escRun, "B's entry is ignored: B is not registered")
    compare(store.runs[1].project.name, "renamed")
    compare(Object.keys(store.runsByProject).join(","), tc.rootA, "C, with no entry, has no list yet")
    compare(store.amStatus, "ok")
  }

  // 10
  function test_a_project_switch_leaves_the_run_list_and_the_live_state_alone() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    store.project = tc.rootA
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [treeEntry("r1", "started"), running("r2")]),
                                                  okEntry(tc.rootB, [rec("done")])]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    compare(store.control("pause", "r2"), true)
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [treeEntry("r1", "started"), running("r2"), escalated("r3")]),
                                                  okEntry(tc.rootB, [rec("done")])]), 0)
    compare(store.toasts.length, 1, "r3 escalated")
    compare(store.pending.r2, "pause", "acknowledged, not yet settled")
    store.toggleRunFilter("live")
    var watch = store.watchProc
    var runs = store.runs
    var applied = store.appliedSeq
    var attempt = store.selectedAttempt
    var toasts = store.toasts
    var seq = store.snapshotRunner.seq
    var targets = [tc.rootB, ""]
    for (var i = 0; i < targets.length; i++) {
      var label = "project " + JSON.stringify(targets[i])
      store.project = targets[i]
      verify(store.runs === runs, label + ": the runs")
      verify(store.appliedSeq === applied, label + ": the coverage")
      compare(store.selectedRunId, "r1", label)
      verify(store.selectedAttempt === attempt, label + ": the attempt")
      compare(store.logsText, "kept", label)
      compare(store.runFilter, "live", label)
      verify(store.watchProc === watch, label + ": the watch")
      compare(watch.running, true, label)
      compare(store.watching, true, label)
      verify(store.toasts === toasts, label + ": the toasts")
      compare(store.pending.r2, "pause", label)
      compare(store.alertsArmed, true, label)
      compare(store.amStatus, "ok", label)
      compare(store.snapshotRunner.seq, seq, label + ": no snapshot")
    }
    sendLine(watch, { changed: [{ run: "r2", seq: 7 }] })
    compare(store.debounceTimer.running, true, "a watch line after the switch is still handled")
    compare(store.nudges.r2, 7)
    store.project = tc.rootB
    compare(argv(store.settingsLoadRunner.current), tc.viewerCmd + "get-run-settings|" + tc.rootB,
            "the new project's run settings still load")
    compare(store.dispatchState, "idle", "and the dispatch is still reset")
  }

  // 10
  function test_opening_a_project_launches_no_snapshot() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    var seq = store.snapshotRunner.seq
    store.project = tc.rootA
    compare(store.snapshotRunner.seq, seq, "the registry, not the open project, decides the snapshot")
    store.project = ""
    compare(store.snapshotRunner.seq, seq)
  }

  // 11 (the snapshot half; Task 3 pins the run read)
  function test_with_no_project_open_the_panel_snapshots_every_root_and_watches() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel snapshots every root")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
    compare(store.staleTimer.running, true, "the stale clock runs with no project")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    verify(store.watchProc, "a good reply starts the watch")
    compare(store.watching, true)
    compare(store.alertsArmed, true)
    compare(store.staleTimer.running, true)
  }

```

- [ ] **Step 3: Rewrite the existing tests that encode the old snapshot, coverage and switch rules**

Each item below names a whole function in `tests/core/stores/tst_run_store.qml`. "Replace" means: replace from `function <name>() {` up to its closing `}` (keep any comment line above it unless told otherwise) with the code given. "Delete" means: remove the function and the comment lines directly above it.

1. Delete `test_setting_the_project_starts_a_snapshot_with_the_exact_argv`, `test_a_project_switch_clears_runs_selection_and_error_and_refreshes` and `test_clearing_the_project_clears_state_and_launches_nothing`. Also delete the `// ---- project changes` line between them. New tests 1 and 10 cover this ground.

2. In `test_an_ok_reply_without_runs_is_ok_and_empty`, replace

```qml
    reply(store.snapshotRunner.current, '{"ok": true, "data_dir": "/x"}\n', 0)
    compare(store.runs.length, 0, "an absent runs key is an empty list, not an error")
```

with

```qml
    reply(store.snapshotRunner.current, allReply([{ root: tc.rootA, ok: true }]), 0)
    compare(store.runs.length, 0, "an entry without a runs key is an empty list, not an error")
```

3. Delete `test_a_project_switch_drops_the_old_projects_late_result`.

4. Replace `test_malformed_runs_are_skipped_without_throwing` with:

```qml
  function test_malformed_runs_are_skipped_without_throwing() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [null, 3, "x", [1], entry("r1", "started", true), { id: "r2" }])]), 0)
    compare(store.runs.length, 2, "only the object entries are kept")
    compare(store.runs[0].id, "r1")
    compare(store.runs[1].id, "r2", "an entry without status data still normalizes")
    compare(store.runs[1].lease, null)
    compare(store.amStatus, "ok")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([{ root: tc.rootA, ok: true, runs: { r1: {} } }]), 0)
    compare(store.runs.length, 0, "a runs value that is not an array is empty")
    compare(store.amStatus, "ok")
    store.refresh()
    // synthetic: entries that are not objects or name no root, then a good one.
    reply(store.snapshotRunner.current, allReply([null, 3, [okEntry(tc.rootA, [])], { ok: true, runs: [] },
                                                  okEntry(tc.rootA, [entry("r3", "started", true)])]), 0)
    compare(ids(store.runs), "r3", "only the entry naming a registered root counts")
  }
```

5. Replace `test_am_missing_sets_missing_and_clears_the_runs` with:

```qml
  function test_am_missing_sets_missing_and_clears_the_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing")
    compare(store.runs.length, 0, "no badges while am is missing")
    compare(store.lastError, "AmMissing: am is not installed.")
  }
```

6. In `test_a_good_reply_after_an_error_restores_ok`, replace

```qml
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}', 1)
```

with

```qml
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
```

7. Replace the comment above `activeStore` and the function itself with:

```qml
  // An active store (the panel is open) with project `root` registered and
  // open: its first snapshot is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }
```

8. Replace `test_activation_refreshes_the_project` with:

```qml
  function test_activation_refreshes_every_root() {
    var store = makeWithProject(rootA); if (!store) return
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel fetches a fresh snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
  }
```

9. In `test_burst_coalesces_to_one_snapshot`, replace `"/plugin/core/backend/runs/runs-snapshot.py"` with `"/plugin/core/backend/runs/runs-snapshot-all.py"`.

10. Replace `test_hello_reset_on_project_switch` with:

```qml
  function test_a_project_switch_keeps_the_hello() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    store.project = rootB
    compare(store.amSchema, 2, "the watch is every project's")
    compare(store.amVersion, "0.1.0")
    store.project = ""
    compare(store.amSchema, 2)
    compare(store.amVersion, "0.1.0")
  }
```

11. Replace `test_old_watch_hello_ignored` with:

```qml
  function test_old_watch_hello_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var old = store.watchProc
    sendLine(old, helloLine("schema_2"))
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    verify(store.watchProc !== old, "the new opening runs its own watch")
    sendLine(old, helloLine("schema_2"))
    compare(store.amSchema, 0, "the old watch's late hello is dropped")
    compare(store.amVersion, "")
    sendLine(store.watchProc, helloLine("schema_1"))
    compare(store.amSchema, 1, "the new watch's own hello counts")
    compare(store.amVersion, "0.1.0")
    old.exited(0)
    compare(store.amSchema, 1, "the old watch's late exit forgets nothing")
    compare(store.amVersion, "0.1.0")
  }
```

12. Replace `test_project_switch_resets_stale` with:

```qml
  function test_a_project_switch_keeps_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.project = rootB
    compare(store.stale, true, "the snapshot's age is every project's")
    compare(store.staleTimer.running, false, "the clock is not restarted")
  }
```

13. Replace the `// ---- project switch and the launch guard` heading with `// ---- a project switch keeps the watch`. Then replace `test_project_switch_stops_watch_and_clears_runs` with:

```qml
  function test_a_project_switch_keeps_the_watch_and_the_runs() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    var seq = store.snapshotRunner.seq
    sendLine(w, { changed: [{ run: "a", seq: 990 }] })
    store.project = rootB
    compare(w.running, true, "the watch is not stopped")
    compare(store.watching, true)
    verify(store.watchProc === w)
    compare(store.debounceTimer.running, true, "its pending nudge stays")
    compare(store.nudges.a, 990)
    compare(ids(store.runs), "a")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
  }
```

14. Delete `test_new_project_watch_starts_after_its_snapshot`.

15. Replace `test_old_watch_lines_ignored_after_switch` with:

```qml
  // Review Focus (spec 5)
  function test_watch_lines_after_a_switch_still_count() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.project = rootB
    sendLine(w, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, true, "a line after a switch is handled")
    compare(store.nudges.a, 990)
    store.project = ""
    sendLine(w, { cursor: 1005 })
    compare(store.watchCursor, 1005, "and with no project open")
  }
```

16. Replace `test_clearing_the_project_while_active_stops_everything` with:

```qml
  function test_clearing_the_project_while_active_keeps_everything_running() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    var seq = store.snapshotRunner.seq
    store.project = ""
    compare(w.running, true, "the watch runs on")
    compare(store.watching, true)
    compare(store.staleTimer.running, true, "the stale clock runs with no project")
    compare(store.livenessTimer.running, true, "a running run is still re-read")
    compare(ids(store.runs), "a")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
  }
```

17. Replace `test_old_watch_exit_ignored_after_switch` with:

```qml
  function test_a_watch_exit_after_a_switch_is_still_handled() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    store.project = rootB
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.amStatus, "schema")
    compare(store.lastError, "SchemaMismatch: schema 2")
    compare(store.pollTimer.running, true)
  }
```

18. Replace `test_project_switch_clears_warning_and_poll` with:

```qml
  function test_a_project_switch_keeps_the_warning_and_the_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.pollTimer.running, true)
    store.project = rootB
    compare(store.watchWarning, "CorruptJournal: bad")
    compare(store.pollTimer.running, true)
    compare(store.watching, false)
  }
```

19. Replace `test_a_project_switch_resets_the_filter` with:

```qml
  function test_a_project_switch_keeps_the_filter() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    store.toggleRunFilter("attention")
    store.project = rootB
    compare(store.runFilter, "attention")
    compare(ids(store.filteredRuns), "esc1,dead1")
  }
```

20. Delete `test_a_project_switch_clears_the_logs_and_drops_the_late_reply` (Task 3 adds its replacement).

21. In `test_logs_argv_leads_with_the_current_project_root`, delete everything from the line `    store.project = tc.rootB` down to (not including) the function's closing `}`. Change the comment above the function to:

```qml
  // The logs launch: python3, the script, then the project root and the
  // attempt, five arguments; the root is the open project's, one element.
```

22. Delete `test_every_logs_launch_after_a_switch_carries_the_new_root` and its two comment lines.

23. Delete `test_a_project_switch_empties_the_control_state_and_drops_the_old_reply` (Task 3 adds its replacement).

24. Replace `test_an_old_reply_after_returning_to_the_project_changes_nothing` (keep its `// Review Focus 1: A -> B -> A before the old reply lands.` comment) with:

```qml
  function test_a_reply_after_returning_to_the_project_is_applied() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var proc = store.controlRunners[0].current
    store.project = rootB
    store.project = rootA
    compare(store.pending.r1, "pause", "the request is still pending")
    compare(store.control("pause", "r1"), false, "so the run cannot be asked again")
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotAcceptingError", "x"), 0)
    compare(store.pending.r1, undefined, "its reply is this project's again and settles it")
    compare(store.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(store.snapshotRunner.seq, seq + 1, "and re-snapshots")
    compare(store.controlRunners.length, 0)
  }
```

25. In `test_am_missing_disarms_and_a_failed_snapshot_does_not`, replace

```qml
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "AmMissing", message: "am is not installed" } }) + "\n", 1)
```

with

```qml
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed")]), 0)
```

26. Replace `test_a_project_switch_empties_the_toasts_and_disarms` (keep its comment line) with:

```qml
  function test_a_project_switch_keeps_the_toasts_and_the_alerts_armed() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    store.project = rootB
    compare(store.toasts.length, 1)
    compare(store.alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b", "the next snapshot compares as before")
  }
```

27. In `test_start_ok_with_run_id_emits_and_saves`, replace

```qml
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
```

with

```qml
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
```

28. Rename the section heading `// ---- list snapshots (4.1.3)` to `// ---- list snapshots`. Replace the comment above `capturedList` and the function itself with:

```qml
  // runs-snapshot-all.py's reply for the captures: the captured root's entry
  // lists runs.json's two `am runs` rows, each with `status` replaced by its
  // `am status` data (status-started.json, status-done.json); with
  // `escalate`, the started run's is status-escalated.json's data
  // (synthetic). `extra` entries come last.
  function capturedList(extra, escalate) {
    var runs = F.load("runs.json").data.runs
    runs[0].status = F.load(escalate ? "status-escalated.json" : "status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return allReply([okEntry(tc.capRoot, runs.concat(extra || []))])
  }
```

29. Replace `test_a_list_snapshot_asks_for_every_project` with:

```qml
  function test_a_list_snapshot_asks_for_every_registered_root() {
    var store = makeWithProject(tc.capRoot); if (!store) return
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    compare(store.snapshotRunner.current.launchGuard, "", "no guard")
    store.refresh()
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
  }
```

30. Replace `test_a_list_reply_keeps_this_projects_runs_and_covers_every_listed_run` with:

```qml
  function test_a_list_reply_lists_the_roots_runs_and_covers_them_at_0() {
    var store = makeWithProject(tc.capRoot); if (!store) return
    // synthetic: a run whose repo_dir is another project's, listed under the captured root.
    reply(store.snapshotRunner.current, capturedList([entry("extra1", "done", false, "/home/u/elsewhere")]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun + ",extra1", "the entry's runs, in am's order, whatever their repo_dir")
    compare(store.runs[2].project.root, tc.capRoot, "a run belongs to the root whose entry lists it")
    compare(store.asOfSeq, 0)
    compare(Object.keys(store.appliedSeq).join(","), [tc.startedRun, tc.doneRun, "extra1"].join(","))
    compare(store.appliedSeq[tc.startedRun], 0)
  }
```

31. Delete `test_a_list_reply_without_a_usable_as_of_seq_covers_at_0` and its `// Review Focus 5.` comment.

32. Replace `test_a_busy_store_keeps_the_last_list_and_marks_it_stale` with:

```qml
  function test_a_busy_root_keeps_its_runs_and_says_why() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    store.refresh()
    // synthetic: am's StoreBusyError, which runs-snapshot-all.py puts in the root's entry unchanged.
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "StoreBusyError", "the am store is busy; try again")]), 0)
    compare(ids(store.runs), "a", "the last good runs stay")
    compare(store.projectErrors[tc.rootA], "StoreBusyError: the am store is busy; try again")
    compare(store.amStatus, "error", "no root answered")
    compare(store.lastError, "StoreBusyError: the am store is busy; try again")
    compare(store.stale, false, "stale is left as it was")
    compare(store.toasts.length, 0)
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the next tick retries")
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.amStatus, "ok")
    compare(Object.keys(store.projectErrors).length, 0)
  }
```

33. Replace `test_am_missing_and_a_project_switch_forget_the_coverage` with:

```qml
  function test_am_missing_forgets_the_coverage_and_a_project_switch_keeps_it() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.appliedSeq.r1, 0)
    store.project = rootB
    compare(store.appliedSeq.r1, 0, "a project switch keeps the coverage")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(Object.keys(store.appliedSeq).length, 0, "AmMissing forgets it")
    compare(store.asOfSeq, 0)
  }
```

34. Rename `// ---- nudges (4.1.3)` to `// ---- nudges`. In the comment above `capturedStore`, replace `both captured runs are covered at 989 and the` with `both captured runs are covered at 0 and the`.

35. Replace `test_a_nudge_no_newer_than_the_list_launches_nothing` with:

```qml
  function test_a_nudge_for_a_listed_run_always_costs_a_read() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.startedRun, 1, tc.doneRun, 900])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.readRunners.length, 2, "the list covers at 0: each listed run is read")
    compare(Object.keys(store.nudges).length, 0, "the nudges were taken")
  }
```

36. In `test_a_nudge_for_an_unknown_run_costs_one_list_snapshot`, replace

```qml
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
```

with

```qml
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
```

37. Delete `test_a_nudge_for_another_projects_run_launches_nothing`. Every listed run now belongs to a registered root.

38. Replace `test_a_project_switch_forgets_the_nudges_but_keeps_the_cursor` with:

```qml
  function test_a_project_switch_keeps_the_nudges_and_the_cursor() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.project = rootB
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.debounceTimer.running, true)
    compare(store.watchCursor, 1005)
  }
```

39. Rename `// ---- run reads (4.1.3)` to `// ---- run reads`. In `test_a_nudge_for_a_held_run_reads_only_that_run`, replace

```qml
    compare(store.appliedSeq[tc.startedRun], 989)
    compare(store.asOfSeq, 989, "a run read leaves asOfSeq")
```

with

```qml
    compare(store.appliedSeq[tc.startedRun], 0)
    compare(store.asOfSeq, 0, "a run read leaves asOfSeq")
```

40. Replace `test_a_read_older_than_the_list_changes_nothing` with:

```qml
  function test_a_read_older_than_a_read_already_applied_changes_nothing() {
    var store = capturedStore(); if (!store) return
    var first = readOf(store, tc.doneRun, 1005)
    // synthetic: status-done.json's run read reply at as_of_seq 1100.
    var late = JSON.parse(runReply(tc.doneRun, "status-done.json"))
    late.as_of_seq = 1100
    reply(first, JSON.stringify(late) + "\n", 0)
    compare(store.appliedSeq[tc.doneRun], 1100)
    var second = readOf(store, tc.doneRun, 1200)
    var before = store.runs[1]
    // synthetic: status-escalated.json's data (as_of_seq 1005) under the done run's id.
    reply(second, runReply(tc.doneRun, "status-escalated.json"), 0)
    verify(store.runs[1] === before)
    compare(store.runs[1].status, "done")
    compare(store.appliedSeq[tc.doneRun], 1100)
  }
```

41. In `test_a_read_of_a_run_the_list_dropped_changes_nothing`, replace the line

```qml
    reply(store.snapshotRunner.current, JSON.stringify({ ok: true, as_of_seq: 1000, store_id: data.store_id, runs: only, data_dir: "/d" }) + "\n", 0)
```

with

```qml
    reply(store.snapshotRunner.current, allReply([okEntry(tc.capRoot, only)]), 0)
```

and replace its comment `// synthetic: runs.json's list without the done run, at an as_of_seq older` / `// than the read's, landing before it.` with `// synthetic: runs.json's list without the done run, landing before the read.`

42. In `test_a_read_reply_that_does_not_fit_changes_nothing`, replace `compare(store.appliedSeq[tc.doneRun], 989, label)` with `compare(store.appliedSeq[tc.doneRun], 0, label)`.

43. Delete `test_a_project_switch_drops_the_reads_in_flight`. Also delete `test_a_read_from_before_a_return_to_the_project_changes_nothing` with its `// Review Focus 1: A -> B -> A before the old read lands.` comment. Task 3 adds their replacement.

44. In `test_a_read_of_a_run_am_does_not_know_relists`, replace

```qml
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
```

with

```qml
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
```

Then replace

```qml
    // synthetic: runs.json's list without the done run, at a later as_of_seq.
```

with `    // synthetic: runs.json's list without the done run.`. Finally replace

```qml
    reply(store.snapshotRunner.current, JSON.stringify({ ok: true, as_of_seq: 1010, store_id: data.store_id, runs: only, data_dir: "/d" }) + "\n", 0)
```

with

```qml
    reply(store.snapshotRunner.current, allReply([okEntry(tc.capRoot, only)]), 0)
```

45. Rename `// ---- cursor reset (4.1.3)` to `// ---- cursor reset`. In `test_a_cursor_reset_starts_over_from_a_list_snapshot`, replace

```qml
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
```

with

```qml
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0, "every root's list is forgotten too")
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
```

Then replace the six lines from `    // synthetic: runs.json's list with the started run's status replaced by` through `    reply(list, JSON.stringify({ ok: true, as_of_seq: 1010, store_id: data.store_id, runs: data.runs, data_dir: "/d" }) + "\n", 0)` with

```qml
    reply(list, capturedList([], true), 0)
```

and replace the function's last assertion `compare(store.asOfSeq, 1010)` with `compare(store.appliedSeq[tc.startedRun], 0)`.

46. In `test_only_a_true_cursor_reset_starts_over`, replace `compare(store.asOfSeq, 989, label)` with `compare(Object.keys(store.appliedSeq).length, 2, label)`.

47. Rename `// ---- store id reset (4.1.4)` to `// ---- store id reset`. Delete `storeList` and `unnamedStore` with their comments. In their place, after `otherStore`, add:

```qml
  // capturedStore() whose watch then named the captures' store in its hello
  // (synthetic: storeHello with the fixture store id): storeId is the
  // fixture's, and nothing was reset.
  function namedStore() {
    var store = capturedStore(); if (!store) return null
    sendLine(store.watchProc, storeHello(tc.fixtureStore(), 989, false))
    compare(store.storeId, tc.fixtureStore())
    compare(store.runs.length, 2)
    return store
  }
```

48. Replace `test_a_list_with_the_seen_store_id_keeps_the_live_state` with:

```qml
  function test_a_list_reply_never_reads_a_store_id() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.refresh()
    var seq = store.snapshotRunner.seq
    // synthetic: the captured list carrying another store's id at the top and in its entry.
    var value = JSON.parse(capturedList())
    value.store_id = otherStore()
    value.projects[0].store_id = otherStore()
    reply(store.snapshotRunner.current, JSON.stringify(value) + "\n", 0)
    compare(store.storeId, fixtureStore(), "the list names no store")
    compare(store.watchCursor, 1005)
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.debounceTimer.running, true)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
    compare(store.snapshotRunner.seq, seq, "no further list snapshot")
    var fresh = capturedStore(); if (!fresh) return
    compare(fresh.storeId, "", "a list alone names no store")
  }
```

49. Delete these five tests with their comment lines: `test_a_list_from_another_store_starts_over_in_place`, `test_a_list_from_another_store_while_closed_is_applied_without_arming`, `test_a_list_from_another_store_keeps_the_selection`, `test_the_first_store_id_a_list_names_resets_nothing` and `test_a_list_without_a_store_id_is_ignored`.

50. Replace `test_the_store_id_outlives_the_watch_a_project_switch_and_am_missing` with:

```qml
  function test_the_store_id_outlives_the_watch_a_project_switch_and_am_missing() {
    var store = namedStore(); if (!store) return
    endWatch(store.watchProc, "", 0)
    compare(store.storeId, fixtureStore(), "the watch ending")
    store.active = false
    compare(store.storeId, fixtureStore(), "the panel closing")
    store.project = rootB
    compare(store.storeId, fixtureStore(), "a project switch")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.capRoot, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing")
    compare(store.storeId, fixtureStore(), "AmMissing")
  }
```

51. Replace `test_a_refused_list_naming_another_store_changes_no_store_id` with:

```qml
  function test_a_refused_list_naming_another_store_changes_no_store_id() {
    var store = namedStore(); if (!store) return
    store.refresh()
    // synthetic: a whole-call refusal carrying another store's id.
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, store_id: otherStore(),
          error: { type: "HelperError", message: "The runs snapshot failed: boom" } }) + "\n", 1)
    compare(store.storeId, fixtureStore())
    compare(store.amStatus, "error")
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
  }
```

52. In `test_a_hello_with_the_seen_store_id_keeps_the_live_state`, change `var store = capturedStore(); if (!store) return` to `var store = namedStore(); if (!store) return`. Replace `compare(store.asOfSeq, 989)` with `compare(Object.keys(store.appliedSeq).length, 2)`.

53. In `test_a_hello_from_another_store_starts_over_from_a_list_snapshot`, change `capturedStore()` to `namedStore()`. Replace `reply(list, storeList(otherStore(), 1200, true), 0)` with `reply(list, capturedList([], true), 0)`. Replace `compare(store.asOfSeq, 1200)` with `compare(store.appliedSeq[tc.startedRun], 0)`.

54. In `test_a_hello_from_another_store_with_cursor_reset_launches_one_list`, change `capturedStore()` to `namedStore()`.

55. In `test_the_first_store_id_a_hello_names_resets_nothing`, change `unnamedStore()` to `capturedStore()`. Replace `compare(store.asOfSeq, 989)` with `compare(Object.keys(store.appliedSeq).length, 2)`.

56. In `test_a_hello_without_a_store_id_is_ignored`, change `capturedStore()` to `namedStore()`.

57. In `test_a_store_that_changes_back_starts_over_again`, change `capturedStore()` to `namedStore()`. Replace `reply(store.snapshotRunner.current, storeList(otherStore(), 1200), 0)` with `reply(store.snapshotRunner.current, capturedList(), 0)`.

58. In `test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied`, change `capturedStore()` to `namedStore()`. Replace

```qml
    reply(store.snapshotRunner.current, storeList(otherStore(), 1200), 0)
    compare(store.asOfSeq, 1200)
    compare(store.runs.length, 2)
```

with

```qml
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.runs.length, 2)
```

59. In `test_a_run_read_from_another_store_is_not_applied_and_starts_over`, change `capturedStore()` to `namedStore()`. Replace `reply(store.snapshotRunner.current, storeList(otherStore(), 1200, true), 0)` with `reply(store.snapshotRunner.current, capturedList([], true), 0)`.

60. In `test_a_run_read_with_the_seen_or_a_first_store_id_is_applied`, change the first `var store = capturedStore(); if (!store) return` to `var store = namedStore(); if (!store) return`. Change `var fresh = unnamedStore(); if (!fresh) return` to `var fresh = capturedStore(); if (!fresh) return`.

61. In `test_a_run_read_without_a_store_id_is_applied`, `test_a_refused_run_read_naming_another_store_changes_no_store_id` and `test_a_superseded_run_read_naming_another_store_changes_nothing`, change `capturedStore()` to `namedStore()`.

62. Check that nothing old is left behind:

Run: `grep -n "storeList\|unnamedStore\|launchProject\|runs-snapshot.py\")\|as_of_seq: 10\|asOfSeq, 9\|asOfSeq, 1" tests/core/stores/tst_run_store.qml`
Expected: no output. (`readCmd` still names `runs-snapshot.py|--run|`. That is correct, and the pattern does not match it.)

- [ ] **Step 4: Run the store tests to verify they fail**

Run: `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)" | head -60`
Expected: FAIL lines for the new tests (assigning the non-existent property `projectRoots`, argv mismatches) and for the rewritten ones. The `Totals` line shows failures.

- [ ] **Step 5: Rewrite the RunStore header and the property block**

In `core/stores/RunStore.qml`, replace lines 6-28 (from `// The am run monitor's data: a list snapshot of every project's runs` through `// `active` to the panel being open.`) with:

```qml
// The am run monitor's data. One list snapshot covers every registered
// project: runs-snapshot-all.py with each usable root of `projectRoots`, in
// registry order. `runsByProject` holds each root's runs, normalized by the
// run domain model and tagged with their project; `projectErrors` the roots
// whose latest entry failed; `runs` every root's runs merged in registry
// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project, decides only
// the run settings, the dispatch, the run controls and the attempt logs'
// root. Plus the selected run, the attempt the Run detail pane shows and that
// attempt's `am logs` snapshot (runs-logs.py), and whether `am` could be
// asked at all. While `active` (the panel is open) a long-lived
// runs-watch.py nudges it, "run X changed at seq N", and is never folded into
// state: once per debounce window, a nudge newer than the coverage of its run
// (appliedSeq) costs one run read (runs-snapshot.py --run RUN, one
// HelperRunner per run) for a run it holds, or one list snapshot for a run it
// does not know. A list snapshot covers its runs at 0. A cursorReset hello
// starts over from a list snapshot, as does a hello or a run read naming a
// store_id other than the one last seen (storeId); the first store_id seen
// resets nothing. watchCursor is the watch's last cursor, held in memory
// only. Logs are fetched on a selection, on Refresh and when a snapshot
// changes the selected attempt's status -- never on a timer.
// Pause, resume and cancel (control()) each get a HelperRunner of their own.
// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start.
// The registry, the open project's root and the backend directory are handed
// to it from outside -- it never reaches for another store. App composes it
// as `app.runs` and binds `active` to the panel being open.
```

Replace

```qml
  property string project: ""         // project root path
  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open" (app.panelOpen)

  property var runs: []               // Runs.normalizeRun output, am's order
```

with

```qml
  property var projectRoots: []       // [{root, name}], the registry in its order; App binds it
  property string project: ""         // the open project's root path; "" when none is open
  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open" (app.panelOpen)

  // Each usable root's runs, {root: runs[]}: am's order, each run
  // Runs.withProject(Runs.normalizeRun(..), root, name). One key per usable
  // root a reply has covered.
  property var runsByProject: ({})
  // {root: Runs.errorText sentence} for each usable root whose latest entry failed.
  property var projectErrors: ({})
  // runsByProject's lists over the usable roots in registry order, a run id
  // an earlier root lists dropped from a later one.
  property var runs: []
```

Replace

```qml
  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and is reset by a project switch.
```

with

```qml
  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and a project switch.
```

Replace

```qml
  // Snapshot coverage. `asOfSeq` is the last good list snapshot's as_of_seq
  // (0 before one). `appliedSeq` is {runId: seq}: the as_of_seq of the
  // snapshot that last covered each run the list named, of every project.
  // Both are replaced, never changed in place.
```

with

```qml
  // Snapshot coverage. `asOfSeq` is 0: the list snapshot names no as_of_seq.
  // `appliedSeq` is {runId: seq}: 0 for every run the last list put in
  // `runs`, then the as_of_seq of each run read applied since. Both are
  // replaced, never changed in place.
```

Replace

```qml
  // am's store_id from the last hello or snapshot that named one; "" = none
  // yet. Replaced, never derived. A project switch, the watch ending and
  // AmMissing keep it.
```

with

```qml
  // am's store_id from the last hello or run read that named one; "" = none
  // yet. Replaced, never derived. A project switch, the watch ending and
  // AmMissing keep it.
```

Replace

```qml
  // A watch has been started since the last activation or project switch:
  // later snapshots never start another (the helper picks up the project's new
  // runs itself), and a watch that ended is not restarted until the next
  // activation or project switch.
```

with

```qml
  // A watch has been started since the last activation: later snapshots never
  // start another (the helper picks up new runs itself), and a watch that
  // ended is not restarted until the next activation.
```

Replace

```qml
  // against: the first good snapshot after an opening, a project switch or an
  // am-missing spell only arms, so history is never replayed. `toasts` is
```

with

```qml
  // against: the first good snapshot after an opening, a store change or an
  // am-missing spell only arms, so history is never replayed. `toasts` is
```

- [ ] **Step 6: Rewrite `refresh`, `restartStale`, the watch guard, `forgetLive` and the comments that name a project switch**

Replace the `refresh` function with its comment:

```qml
  // Asks for a list snapshot: runs-snapshot-all.py with every usable root, in
  // registry order, whether or not a project is open. With no usable root
  // nothing is launched, a snapshot in flight is stopped, and the run list,
  // runsByProject and projectErrors are emptied. A newer call replaces an
  // older one (the runner's latest-wins rule).
  function refresh() {
    var usable = store.usableRoots()
    if (usable.length === 0) {
      snapshotRunner.cancel()
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      return
    }
    snapshotRunner.run(usable.map(function(p) { return p.root }))
  }
```

Replace the `restartStale` function with its comment:

```qml
  // Nothing is stale yet; the 30 s clock starts again while the panel is open.
  function restartStale() {
    store.stale = false
    if (store.active) staleTimer.restart()
    else staleTimer.stop()
  }
```

In `startWatch`, replace

```qml
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq, launchProject: store.project })
```

with

```qml
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq })
```

Replace `isCurrentWatch` with its comment:

```qml
  // A line or exit counts only from the newest launch: a watch that was
  // stopped (the panel closed) may still print or exit late. Which project
  // is open does not matter.
  function isCurrentWatch(proc) {
    return proc.launchSeq === store.watchSeq
  }
```

In the comment above `triggerNudges`, replace

```qml
  // costs one run read, in nudge order. A nudge no newer than
  // appliedSeq[run], or for another project's listed run, is ignored.
```

with

```qml
  // costs one run read, in nudge order. A nudge no newer than
  // appliedSeq[run], or for a run no longer in `runs`, is ignored.
```

Replace `forgetLive` with its comment:

```qml
  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, every run read in flight (its reply changes
  // nothing), the runs and every root's list of them, and the alerts (the
  // next list snapshot only arms). Selection, logs, controls and dispatch stay.
  function forgetLive() {
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.dropReads()
    store.runs = []
    store.runsByProject = {}
    store.alertsArmed = false
  }
```

In the comment above `seeStore`, replace `// A store id seen in a hello or a good snapshot. A non-empty string is` with `// A store id seen in a hello or a good run read. A non-empty string is`.

In the comment above `watchExited`, replace `// and the watch stays off until the next activation or project switch.` with `// and the watch stays off until the next activation.`

Replace the comment above `startPoll`:

```qml
  // The poll replaces the watch signal until the panel closes or the project
  // changes.
```

with

```qml
  // The poll replaces the watch signal until the panel closes.
```

- [ ] **Step 7: Replace `projectSwitched` and add the registry functions**

Replace the whole `projectSwitched` function and its two comment lines (`// A different project: nothing the old one left behind may show, and its` / `// runs are fetched straight away.`) with:

```qml
  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests and the alerts belong to
  // every registered project and stay, and no snapshot is launched. Reset:
  // the notify switch and the run settings (loaded for the new project), the
  // dispatch, the cancel dialog, the control error and the footer flash.
  function projectSwitched() {
    // The switch reads off until this project's own reply. Notifications
    // already launched still run.
    store.notifyOnEscalation = false
    store.notifySaved = false
    store.notifyTouched = false
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    store.dismissControlError()
    store.closeCancel()
    store.flash("")
    settingsLoadRunner.guard = store.project
    if (store.project !== "") settingsLoadRunner.run(["get-run-settings", store.project])
  }

  onProjectChanged: store.projectSwitched()

  // The registry's usable entries, {root, name}, in registry order: an object
  // whose root is a non-empty string not starting with "-" (runs-snapshot-all.py
  // refuses any other), each root once, at its first position with its first
  // name.
  function usableRoots() {
    var list = store.projectRoots
    var n = list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
    var out = []
    var seen = {}
    for (var i = 0; i < n; i++) {
      var p = list[i]
      if (p === null || typeof p !== "object" || Array.isArray(p)) continue
      var root = p.root
      if (typeof root !== "string" || root === "" || root.charAt(0) === "-" || store.hasKey(seen, root)) continue
      seen[root] = true
      out.push({ root: root, name: p.name })
    }
    return out
  }

  // byProject cut to the usable roots, each run carrying its root's current
  // project (Runs.withProject); a run that already carries it stays the same
  // object.
  function taggedByProject(byProject, usable) {
    var out = {}
    for (var i = 0; i < usable.length; i++) {
      var p = usable[i]
      if (!store.hasKey(byProject, p.root)) continue
      var tag = Runs.withProject({}, p.root, p.name).project
      out[p.root] = byProject[p.root].map(function(run) {
        var cur = run !== null && typeof run === "object" ? run.project : null
        if (cur && cur.root === tag.root && cur.name === tag.name) return run
        return Runs.withProject(run, p.root, p.name)
      })
    }
    return out
  }

  // byProject's lists over the usable roots in registry order, as {runs,
  // owner}: a run id an earlier root already listed is dropped (the first root
  // wins; a run without a non-empty string id is never dropped), and owner is
  // {id: root} of every run id kept.
  function mergedRuns(byProject, usable) {
    var out = []
    var owner = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      var list = store.hasKey(byProject, root) ? byProject[root] : []
      for (var j = 0; j < list.length; j++) {
        var run = list[j]
        var id = run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
        if (id !== "") {
          if (store.hasKey(owner, id)) continue
          owner[id] = root
        }
        out.push(run)
      }
    }
    return { runs: out, owner: owner }
  }

  // The registry changed. First the roots no longer usable lose their runs
  // and their errors, and `runs` is merged again in the new order with the
  // new names; no alert is raised. Then every usable root is snapshotted.
  function registryChanged() {
    var usable = store.usableRoots()
    var errors = {}
    for (var i = 0; i < usable.length; i++) {
      var root = usable[i].root
      if (store.hasKey(store.projectErrors, root)) errors[root] = store.projectErrors[root]
    }
    var byProject = store.taggedByProject(store.runsByProject, usable)
    store.runsByProject = byProject
    store.projectErrors = errors
    store.runs = store.mergedRuns(byProject, usable).runs
    store.refresh()
  }

  onProjectRootsChanged: store.registryChanged()
```

- [ ] **Step 8: Replace the list reply**

Delete `entryProject` and its comment (the block that starts `// The entry's project root: project.repo_dir when project is an object with`). Keep `trimSlashes`; Task 3 uses it.

Replace the whole `applySnapshot` function and its comment block (from `// One list snapshot reply. ok:true keeps the entries whose project is` through the function's closing `}`) with:

```qml
  // One list snapshot reply. {ok: true, projects} goes to applyProjects. An
  // ok:false envelope (Usage, HelperError) or output that is not one keeps
  // the runs, runsByProject and projectErrors and only reports why this one
  // failed. Never reads a store_id. Never throws.
  function applySnapshot(stdout, exitCode) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.applyProjects(Array.isArray(envelope.projects) ? envelope.projects : [], exitCode)
      return
    }
    store.amStatus = "error"
    if (envelope !== null && envelope.ok === false) store.lastError = Runs.errorText(envelope)
    else store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
  }

  // A list reply's entries, {root, ok, runs | error}, matched to the usable
  // roots by exact root: the first entry of a root counts, any other entry is
  // ignored. No matched entry at all is a reply with no usable result. Every
  // matched entry AmMissing: the runs, runsByProject, projectErrors and the
  // coverage are emptied and amStatus is "missing", disarming the alerts.
  // Otherwise an ok entry replaces its root's runs and clears its error
  // (entries that are not objects are skipped); a failed one keeps its
  // root's runs ([] when it had none) and records Runs.errorText of its
  // error; a usable root with no entry keeps both. `runs` is merged again,
  // asOfSeq is 0, appliedSeq {id: 0} for every run in it, and readState.rows
  // each kept run's `am runs` row: the winning root's from this reply, else
  // the row kept from before. With an entry ok, everything after a good
  // snapshot follows. With none, amStatus is "error" with the first failed
  // entry's sentence, and the alerts and `stale` stay as they are.
  function applyProjects(entries, exitCode) {
    var usable = store.usableRoots()
    var names = {}
    for (var u = 0; u < usable.length; u++) names[usable[u].root] = usable[u].name
    var matched = []
    var seen = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      if (typeof e.root !== "string" || !store.hasKey(names, e.root) || store.hasKey(seen, e.root)) continue
      seen[e.root] = true
      matched.push(e)
    }
    if (matched.length === 0) {
      store.amStatus = "error"
      store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
      return
    }
    var missing = true
    for (var m = 0; m < matched.length; m++) {
      var err = matched[m].error
      var type = err !== null && typeof err === "object" ? err.type : ""
      if (matched[m].ok === true || type !== "AmMissing") missing = false
    }
    if (missing) {
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      store.appliedSeq = {}
      store.asOfSeq = 0
      store.amStatus = "missing"
      store.lastError = Runs.errorText(matched[0].error)
      // Comparing the next good snapshot against [] would alert every
      // escalated run again.
      store.alertsArmed = false
      return
    }
    var byProject = store.copyMap(store.runsByProject)
    var errors = store.copyMap(store.projectErrors)
    var fresh = {}          // {root: {id: am runs row}} of this reply's ok entries
    var anyOk = false
    var firstError = ""
    for (var k = 0; k < matched.length; k++) {
      var entry = matched[k]
      var root = entry.root
      if (entry.ok === true) {
        anyOk = true
        var list = Array.isArray(entry.runs) ? entry.runs : []
        var out = []
        var rows = {}
        for (var r = 0; r < list.length; r++) {
          var item = list[r]
          if (item === null || typeof item !== "object" || Array.isArray(item)) continue
          var row = store.rowOf(item)
          if (typeof item.id === "string" && item.id !== "" && !store.hasKey(rows, item.id)) rows[item.id] = row
          out.push(Runs.withProject(Runs.normalizeRun({ row: row, status: item.status }), root, names[root]))
        }
        byProject[root] = out
        fresh[root] = rows
        delete errors[root]
      } else {
        if (!store.hasKey(byProject, root)) byProject[root] = []
        errors[root] = Runs.errorText(entry.error)
        if (firstError === "") firstError = errors[root]
      }
    }
    byProject = store.taggedByProject(byProject, usable)
    var merged = store.mergedRuns(byProject, usable)
    var applied = {}
    var keptRows = {}
    var ids = Object.keys(merged.owner)
    for (var d = 0; d < ids.length; d++) {
      var id = ids[d]
      var owner = merged.owner[id]
      applied[id] = 0
      if (store.hasKey(fresh, owner) && store.hasKey(fresh[owner], id)) keptRows[id] = fresh[owner][id]
      else if (store.hasKey(readState.rows, id)) keptRows[id] = readState.rows[id]
    }
    // Compared before the runs are replaced; raised below only while open.
    var alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, merged.runs)
    store.runsByProject = byProject
    store.projectErrors = errors
    store.asOfSeq = 0
    store.appliedSeq = applied
    readState.rows = keptRows
    store.runs = merged.runs
    if (!anyOk) {
      store.amStatus = "error"
      store.lastError = firstError
      return
    }
    store.settleAfterSnapshot()
    store.logsAfterSnapshot()
    if (pollTimer.running && store.watchSchemaError !== "") {
      // The watch's schema banner outlives the polling snapshots.
      store.amStatus = "schema"
      store.lastError = store.watchSchemaError
    } else {
      store.amStatus = "ok"
      store.lastError = ""
    }
    store.stale = false
    if (store.active) {
      staleTimer.restart()
      if (!store.watchTried) store.startWatch()
      store.raiseAlerts(alerts)
      store.alertsArmed = true
    }
  }
```

- [ ] **Step 9: Drop the snapshot runner's guard and fix the runner comments**

Replace

```qml
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
    onFinished: function(stdout, exitCode) { store.applySnapshot(stdout, exitCode) }
  }

  // The attempt-logs helper. Guarded by the project like the snapshot, so a
  // reply for a project the user has left is dropped; a newer fetch (another
  // attempt, a Refresh) wins over an older one. No onGuardChanged here: the
  // snapshot runner's already runs projectSwitched() once per switch.
```

with

```qml
  // The list snapshot of every usable root. No guard: its reply is matched to
  // the registry by root, whatever project is open.
  HelperRunner {
    id: snapshotRunner
    script: store.backendDir + "runs/runs-snapshot-all.py"
    onFinished: function(stdout, exitCode) { store.applySnapshot(stdout, exitCode) }
  }

  // The attempt-logs helper. Guarded by the project, so a reply for a project
  // the user has left is dropped; a newer fetch (another attempt, a Refresh)
  // wins over an older one.
```

Replace

```qml
  // get-run-settings on a project switch. Its guard is set by projectSwitched()
  // itself rather than bound to `project`: projectSwitched() runs from the
  // snapshot runner's guard change, before a binding here is sure to have
  // followed the project, and this launch must carry the NEW project.
```

with

```qml
  // get-run-settings on a project switch. Its guard is set by projectSwitched()
  // itself rather than bound to `project`: projectSwitched() runs from
  // onProjectChanged, before a binding here is sure to have followed the
  // project, and this launch must carry the NEW project.
```

Replace

```qml
  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped. No onGuardChanged:
  // the snapshot runner's already runs projectSwitched().
```

with

```qml
  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped.
```

In the `readState` comment, replace

```qml
  // runner}, the read whose reply counts; `rows` is {runId: am runs row} of
  // the runs the last good list snapshot kept, which a run read rebuilds from.
```

with

```qml
  // runner}, the read whose reply counts; `rows` is {runId: am runs row} of
  // the runs in `runs`, which a run read rebuilds from.
```

In the `watchC` component, delete the line `      property string launchProject: ""`.

- [ ] **Step 10: Run the store tests to verify they pass**

Run: `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: a single `Totals: N passed, 0 failed, ...` line and no error lines.

Then run: `timeout 300 bash tests/run.sh tests/architecture` (pytest, including `tests/architecture`, runs before the QML filter)
Expected: pytest passes. `tests/architecture` contains no `tst_*.qml`, so no QML runs.

- [ ] **Step 11: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): snapshot every registered root and leave the run list alone on a project switch

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: App binds the registry; the composition and UI tests move to the new reply

**Files:**
- Modify: `core/stores/App.qml:104-117`
- Test: `tests/core/stores/tst_app_runs.qml`
- Test: `tests/ui/tst_runs_flow.qml:170-178, 245-257, 265-275`
- Test: `tests/ui/tst_runs_real_data.qml:18, 58-67`

**Interfaces:**
- Consumes: `RunStore.projectRoots` (Task 1), `ProjectStore.projects` (`[{root_path, name}]`, replaced by `applyProjectsList`).
- Produces: `app.runs.projectRoots` deep-equal to `app.projects.projects.map(p => ({root: p.root_path, name: p.name}))`.

- [ ] **Step 1: Write the failing App tests**

In `tests/core/stores/tst_app_runs.qml`, replace the header comment (lines 2-5) with:

```qml
// App's composition of the run monitor's store: `app.runs` exists, and its
// inputs come from App -- the backend dir, the registry's roots and names,
// the selected project's ROOT PATH (never the project object), and App's
// panel-open flag. The store's own behaviour is tested in tst_run_store.qml;
// here only the wiring is.
```

Add after `name: "StoresAppRuns"`:

```qml

  Component { id: spyC; SignalSpy {} }
```

Replace `okReply` with:

```qml
  // runs-snapshot-all.py's reply: pA's entry lists runs `ids`.
  function okReply(ids) {
    var runs = ids.map(function(id) {
      return { id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
               status: { run: { id: id, milestone_id: "m-" + id, status: "done" }, rows: [], stories: [], subtasks: [],
                         control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: false } } } }
    })
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: runs }],
                            data_dir: "/home/u/.local/share" }) + "\n"
  }
```

In `test_app_composes_a_run_store_with_no_project_and_closed`, replace `verify(!app.runs.snapshotRunner.current, "no snapshot without a project")` with `verify(!app.runs.snapshotRunner.current, "no snapshot without a registered project")`.

Replace `test_the_snapshot_runs_for_the_selected_root_path` and `test_clearing_the_selection_empties_project_and_runs` with:

```qml
  // 13
  function test_project_roots_follow_the_registry() {
    var app = make(); if (!app) return
    compare(JSON.stringify(app.runs.projectRoots),
            JSON.stringify([{ root: tc.pA.root_path, name: "alpha" }, { root: tc.pB.root_path, name: "beta" }]))
    var spy = createTemporaryObject(spyC, tc, { target: app.runs, signalName: "projectRootsChanged" })
    app.projects.chooseProject(pB)
    compare(app.runs.project, "/home/u/b")
    compare(spy.count, 0, "selecting a project does not change it")
    app.projects.clearSelection()
    compare(spy.count, 0, "nor does clearing the selection")
    app.projects.applyProjectsList([pB])
    compare(JSON.stringify(app.runs.projectRoots), JSON.stringify([{ root: tc.pB.root_path, name: "beta" }]),
            "a new list replaces it")
  }

  // 14
  function test_the_snapshot_names_every_registered_root() {
    var app = make(); if (!app) return
    var proc = app.runs.snapshotRunner.current
    verify(proc, "the registry starts a snapshot")
    compare(proc.command.join("|"), "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj|/home/u/b")
    compare(proc.launchGuard, "", "the snapshot has no guard")
  }

  // 14
  function test_clearing_the_selection_keeps_the_runs() {
    var app = make(); if (!app) return
    var proc = app.runs.snapshotRunner.current
    proc.outText = okReply(["r1"])
    proc.exited(0)
    compare(app.runs.runs.length, 1)
    app.projects.clearSelection()
    compare(app.runs.project, "")
    compare(app.runs.runs.length, 1, "the run list is every registered project's")
  }
```

In `test_opening_with_no_project_launches_nothing`, replace `verify(!app.runs.snapshotRunner.current, "no snapshot without a project")` with `verify(!app.runs.snapshotRunner.current, "no snapshot without a registered project")`.

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: FAIL for `test_project_roots_follow_the_registry`, `test_the_snapshot_names_every_registered_root`, `test_clearing_the_selection_keeps_the_runs` and `test_panel_close_through_app_stops_the_watch`. App does not bind `projectRoots`, so no snapshot is launched.

- [ ] **Step 3: Bind the registry in App**

In `core/stores/App.qml`, replace

```qml
  // The run store never imports the project or board store: App hands it the
  // selected project's root path (never the project object) and the panel-open
  // flag that starts and stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
```

with

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object) and the panel-open flag that starts and
  // stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
```

- [ ] **Step 4: Run the App tests to verify they pass**

Run: `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: ... 0 failed`.

- [ ] **Step 5: Move the UI tests to the new reply shape**

In `tests/ui/tst_runs_flow.qml`:

Replace

```qml
  // One runs-snapshot.py entry: the `am runs` summary whose `status` the
  // helper replaced with the `am status` data. workflow "task" makes a resume
  // skip the run-settings read.
```

with

```qml
  // One run of a runs-snapshot-all.py entry: the `am runs` summary whose
  // `status` the helper replaced with the `am status` data. workflow "task"
  // makes a resume skip the run-settings read.
```

Replace

```qml
  function snapOk(entries) { return JSON.stringify({ ok: true, runs: entries, data_dir: "/d" }) + "\n" }
```

with

```qml
  // runs-snapshot-all.py's reply: pA's entry lists `entries`.
  function snapOk(entries) {
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: entries }], data_dir: "/d" }) + "\n"
  }
```

Replace `test_a_project_switch_clears_the_runs_and_the_filter` with:

```qml
  function test_a_project_that_leaves_the_registry_takes_its_runs_with_it() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.app.projects.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.runs.runs.length, 0)
  }
```

Replace `test_a_project_switch_on_the_run_view_clears_it` with:

```qml
  function test_a_project_switch_on_the_run_view_leaves_it_and_drops_the_late_logs() {
    var p = openDetail(); if (!p) return
    var proc = p.app.runs.logsRunner.current
    p.app.projects.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.nav.viewMode, "board")
    compare(H.find(p, "runDetailView").visible, false)
    proc.outText = logsOk("late\n")
    proc.exited(0)
    compare(p.app.runs.logsText, "", "the old project's late reply changes nothing")
  }
```

In `tests/ui/tst_runs_real_data.qml`:

Replace `  // The captured runs' project: runs.json's repo_dir, so the store keeps them.` with `  // The captured runs' project, registered: its snapshot entry lists them.`

Replace

```qml
  // The runs-snapshot.py reply for the captured runs: each `am runs` row with
  // its `status` replaced by that run's `am status` data, and runs.json's
  // as_of_seq and store_id, as the helper does.
  function snapshot() {
    var data = F.load("runs.json").data
    var runs = data.runs
    runs[0].status = F.load("status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return JSON.stringify({ ok: true, as_of_seq: data.as_of_seq, store_id: data.store_id, runs: runs, data_dir: "/d" }) + "\n"
  }
```

with

```qml
  // The runs-snapshot-all.py reply for the captured runs: pA's entry lists
  // each `am runs` row with its `status` replaced by that run's `am status`
  // data, as the helper does.
  function snapshot() {
    var runs = F.load("runs.json").data.runs
    runs[0].status = F.load("status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: runs }], data_dir: "/d" }) + "\n"
  }
```

- [ ] **Step 6: Run the whole suite**

Run: `timeout 900 bash tests/run.sh 2>&1 | tail -80`
Expected: pytest passes, and every `== tests/...` block shows `Totals: ... 0 failed` with no `TypeError`/`ReferenceError` lines. The exit status is 0.

Another UI test may fail only because it asserted that a project switch empties `runs`, `runFilter`, the selection, the logs or the toasts. If so, change that one assertion to the value the store now keeps (the value before the switch) and leave the rest of the test alone. Name every such change in the commit message. A failure for any other reason is a defect in Task 1 or Task 2: stop and fix it there.

- [ ] **Step 7: Commit**

```bash
git add core/stores/App.qml tests/core/stores/tst_app_runs.qml tests/ui/tst_runs_flow.qml tests/ui/tst_runs_real_data.qml
git commit -m "feat(app): hand the run store the registry's roots; tests move to the runs-snapshot-all reply

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Run reads, a control request and a logs fetch survive a project switch

**Files:**
- Modify: `core/stores/RunStore.qml`: `readRun`, `readReplied`, `applyRunRead`; `requestOf` comment; `logsRunner`; the `controlC` and `readC` components
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `runsByProject`, `trimSlashes(path)`, `requestOf(runner)`, `settle(runId)`, `dropRunner(runner)`, and the Task 1 test helpers (`activeRoots`, `allReply`, `okEntry`, `failEntry`, `rec`, `readOf`, `runReply`, `ctlStore`, `opened`, `logsReply`).
- Produces: `function withRun(byProject, root, rebuilt)` → `{root: run[]}`; `function controlDropped(runner)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, in `test_a_nudge_for_a_held_run_reads_only_that_run`, replace

```qml
    compare(store.runs[1].project.repo_dir, tc.capRoot, "from its remembered am runs row")
```

with

```qml
    compare(JSON.stringify(store.runs[1].project), JSON.stringify({ root: tc.capRoot, name: "proj" }), "the read run keeps its project")
    compare(store.runs[1].milestone_id, "63060df3-f582-4eb9-a56e-44cadb15b693", "rebuilt from its remembered am runs row")
```

Add this section right after `test_a_read_landing_after_the_panel_closed_is_applied_quietly`:

```qml
  // ---- reads, requests and logs across a project switch (3.1)

  // 11 (the run read) and Review Focus 4
  function test_a_read_with_no_project_open_launches_applies_and_keeps_its_project() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    compare(store.project, "")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    var proc = readOf(store, tc.doneRun, 1005)
    verify(proc, "a run read launches with no project open")
    compare(argv(proc), tc.readCmd + tc.doneRun)
    // synthetic: status-escalated.json's data under the done run's id.
    reply(proc, runReply(tc.doneRun, "status-escalated.json"), 0)
    var run = store.runById(tc.doneRun)
    compare(run.status, "escalated", "its reply applies")
    compare(store.appliedSeq[tc.doneRun], 1005)
    compare(JSON.stringify(run.project), JSON.stringify({ root: tc.rootB, name: "beta" }), "the read run keeps its project")
    verify(store.runsByProject[tc.rootB][0] === run, "B's list holds the read run")
    store.projectRoots = [rootEntry(tc.rootA), { root: tc.rootB, name: "bee" }]
    compare(store.runById(tc.doneRun).status, "escalated", "a registry change merges the read value")
    compare(store.runById(tc.doneRun).project.name, "bee")
  }

  function test_a_read_in_flight_at_a_project_switch_still_applies() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    store.project = rootB
    store.project = ""
    // synthetic: status-escalated.json's data under the done run's id.
    reply(proc, runReply(tc.doneRun, "status-escalated.json"), 0)
    compare(store.runs[1].status, "escalated", "applied whatever project is open")
    compare(store.appliedSeq[tc.doneRun], 1005)
    compare(store.readRunners.length, 0)
  }

  // 5 of the coverage rule: a kept run must not lose its row
  function test_a_run_kept_by_a_failed_root_reads_back_from_its_row() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    reply(readOf(store, tc.doneRun, 1005), runReply(tc.doneRun, "status-done.json"), 0)
    var run = store.runById(tc.doneRun)
    compare(store.appliedSeq[tc.doneRun], 1005)
    compare(run.milestone_id, "63060df3-f582-4eb9-a56e-44cadb15b693", "rebuilt from the row B's failed entry kept")
    compare(run.project.root, tc.rootB)
  }

  // 12 (the control half)
  function test_a_control_request_in_flight_at_a_switch_is_settled_without_an_error() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    store.control("cancel", "r2")
    var inFlight = store.controlRunners[0].current
    reply(store.controlRunners[1].current, ctlOk({ requested_at: "t2" }), 0)
    compare(store.pending.r2, "cancel", "acknowledged")
    store.stillWaiting = { r1: true, r2: true }
    store.project = rootB
    compare(store.pending.r1, "pause", "in flight until its runner goes idle")
    reply(inFlight, ctlFail("NotAcceptingError", "x"), 0)
    compare(store.pending.r1, undefined, "its dropped reply settles it: the buttons come back")
    compare(store.stillWaiting.r1, undefined)
    compare(store.lastControlError, "", "with no control error")
    compare(store.controlRunners.length, 0)
    compare(store.pending.r2, "cancel", "an acknowledged request stays pending until a snapshot settles it")
    compare(store.stillWaiting.r2, true)
  }

  // 12 (the logs half)
  function test_a_logs_fetch_in_flight_at_a_switch_ends_and_keeps_the_text() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var fetched = store.logsFetchedMs
    store.refreshLogs()
    var pending = store.logsRunner.current
    compare(store.logsLoading, true)
    store.project = rootB
    compare(store.logsLoading, true, "still in flight")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsLoading, false, "the dropped reply ends the fetch")
    compare(store.logsText, "kept", "the shown text stays")
    compare(store.logsError, "")
    compare(store.logsFetchedMs, fetched)
    compare(store.selectedRunId, "r1")
    verify(store.selectedAttempt !== null)
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: FAIL for the five new tests and for `test_a_nudge_for_a_held_run_reads_only_that_run`:
- `readRun` returns when `project === ""`.
- `readReplied` drops replies whose `madeFor` differs from `project`.
- `applyRunRead` drops `project`.
- `pending.r1` stays `"pause"`.
- `logsLoading` stays true.

- [ ] **Step 3: Run reads keep working with no project and keep the run's project**

In `core/stores/RunStore.qml`, replace `readRun` with its comment:

```qml
  // One runs-snapshot.py --run RUN on its own runner, for a nudge at seq,
  // whatever project is open. It supersedes an older read of the same run
  // still in flight.
  function readRun(runId, seq) {
    var runner = readC.createObject(store, { runId: runId, nudgeSeq: seq })
    var latest = store.copyMap(readState.latest)
    latest[runId] = runner
    readState.latest = latest
    readState.runners = readState.runners.concat([runner])
    runner.run(["--run", runId])
  }
```

In the comment above `readReplied`, replace

```qml
  // reply that is not its run's latest read, or for a project the user has
  // left, changes nothing. ok:true records its store_id (seeStore): one
```

with

```qml
  // reply that is not its run's latest read changes nothing, whatever project
  // is open. ok:true records its store_id (seeStore): one
```

In `readReplied`, replace

```qml
    var latest = store.hasKey(readState.latest, runId) && readState.latest[runId] === runner
    var current = latest && runner.madeFor === store.project
```

with

```qml
    var latest = store.hasKey(readState.latest, runId) && readState.latest[runId] === runner
```

and replace `    if (!current) return` with `    if (!latest) return`.

Replace the comment above `applyRunRead` and the function itself with:

```qml
  // A good run read, {run, as_of_seq, status}: for the run asked, with a
  // non-negative integer as_of_seq and an object status, still in `runs` and
  // not covered by a newer read, the run at its position is rebuilt from its
  // remembered `am runs` row and the reply's status, keeping the replaced
  // run's project (Runs.withProject), and it replaces that run in its root's
  // runsByProject list too (withRun); the other runs stay the same objects.
  // appliedSeq[run] becomes as_of_seq. Then alerts, settling, logs and the
  // stale clock as after a list snapshot; asOfSeq, amStatus and lastError are
  // left alone. Anything else changes nothing.
  function applyRunRead(runId, envelope) {
    var asOf = envelope.as_of_seq
    var status = envelope.status
    if (envelope.run !== runId || !store.isSeq(asOf)) return
    if (status === null || typeof status !== "object" || Array.isArray(status)) return
    if (store.hasKey(store.appliedSeq, runId) && store.appliedSeq[runId] > asOf) return
    var index = -1
    for (var i = 0; i < store.runs.length; i++) {
      if (store.runs[i] && store.runs[i].id === runId) {
        index = i
        break
      }
    }
    if (index < 0) return
    var row = store.hasKey(readState.rows, runId) ? readState.rows[runId] : { id: runId }
    var old = store.runs[index]
    var project = old.project !== null && typeof old.project === "object" ? old.project : { root: "", name: "" }
    var rebuilt = Runs.withProject(Runs.normalizeRun({ row: row, status: status }), project.root, project.name)
    var next = store.runs.slice()
    next[index] = rebuilt
    // Compared before the runs are replaced; raised below only while open.
    var alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, next)
    store.runs = next
    store.runsByProject = store.withRun(store.runsByProject, project.root, rebuilt)
    var applied = store.copyMap(store.appliedSeq)
    applied[runId] = asOf
    store.appliedSeq = applied
    store.settleAfterSnapshot()
    store.logsAfterSnapshot()
    store.stale = false
    if (store.active) {
      staleTimer.restart()
      store.raiseAlerts(alerts)
    }
  }

  // byProject with the run of rebuilt's id replaced by rebuilt in every list
  // whose root, without its trailing "/", is `root`; the other lists and runs
  // stay the same objects.
  function withRun(byProject, root, rebuilt) {
    var out = {}
    var keys = Object.keys(byProject)
    for (var i = 0; i < keys.length; i++) {
      var list = byProject[keys[i]]
      out[keys[i]] = store.trimSlashes(keys[i]) !== root ? list : list.map(function(r) {
        return r !== null && typeof r === "object" && r.id === rebuilt.id ? rebuilt : r
      })
    }
    return out
  }
```

In the `readC` component, replace

```qml
  // One HelperRunner per run read, so reads of different runs run in
  // parallel. Guard "": readReplied checks the project and the latest read
  // itself, so every exit lands there and the runner always goes.
```

with

```qml
  // One HelperRunner per run read, so reads of different runs run in
  // parallel. Guard "": readReplied checks the latest read itself, so every
  // exit lands there and the runner always goes.
```

and delete its line `      property string madeFor: ""     // the project the read was made in`.

- [ ] **Step 4: A control request dropped at a switch is settled**

Replace the comment above `requestOf`:

```qml
  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled, emptied by a project switch
  // or replaced by a newer request.
```

with

```qml
  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled or replaced by a newer
  // request.
```

Add right after the `dropRunner` function:

```qml

  // A runner whose reply its guard dropped (the open project changed while it
  // was in flight): a request still pending for its run is settled -- its
  // buttons come back, with no control error -- and the runner goes. A
  // request am already acknowledged has no runner left and stays pending
  // until a snapshot settles it.
  function controlDropped(runner) {
    if (store.requestOf(runner) !== null) store.settle(runner.runId)
    store.dropRunner(runner)
  }
```

In the `controlC` component, replace the comment block

```qml
  // One HelperRunner per control request, so requests for different runs never
  // stop each other. Guarded by the project like the others: a reply for a
  // project the user has left is dropped, and its runner goes when its process
  // exits (the runner clears `busy` on that exit but emits no `finished`). No
  // onGuardChanged: the snapshot runner's already runs projectSwitched(). A
  // milestone resume uses its runner twice: viewer-state.py, then run-control.py.
```

with

```qml
  // One HelperRunner per control request, so requests for different runs never
  // stop each other. Guarded by the project: a reply for a project the user
  // has left is dropped, and when its process exits (the runner clears `busy`
  // but emits no `finished`) controlDropped settles its request and the
  // runner goes. A milestone resume uses its runner twice: viewer-state.py,
  // then run-control.py.
```

and replace

```qml
      onBusyChanged: if (!cr.busy && cr.guard !== cr.madeFor) store.dropRunner(cr)
```

with

```qml
      onBusyChanged: if (!cr.busy && cr.guard !== cr.madeFor) store.controlDropped(cr)
```

- [ ] **Step 5: A logs fetch dropped at a switch ends `logsLoading`**

Replace

```qml
  // The attempt-logs helper. Guarded by the project, so a reply for a project
  // the user has left is dropped; a newer fetch (another attempt, a Refresh)
  // wins over an older one.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.applyLogs(stdout, exitCode) }
  }
```

with

```qml
  // The attempt-logs helper. Guarded by the project, so a reply for a project
  // the user has left is dropped; a newer fetch (another attempt, a Refresh)
  // wins over an older one. Whenever the runner goes idle, dropped reply or
  // not, no fetch is loading; the shown text, error and time stay.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    guard: store.project
    onBusyChanged: if (!logsRunner.busy) store.logsLoading = false
    onFinished: function(stdout, exitCode) { store.applyLogs(stdout, exitCode) }
  }
```

- [ ] **Step 6: Run the store tests to verify they pass**

Run: `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function"`
Expected: `Totals: N passed, 0 failed, ...` and no error lines.

Check that no `madeFor` read check is left behind:

Run: `grep -n "madeFor" core/stores/RunStore.qml`
Expected: only the control runner (`madeFor: store.project` in `control()`, `property string madeFor` and `cr.madeFor` in `controlC`) and the dispatch start runner (`dispatchStartC`, `isHereStart`, `dispatchStart`, `dispatchStartReplied`). Nothing in `readRun`, `readReplied` or `readC`.

- [ ] **Step 7: Run the whole gate**

Run: `timeout 900 bash tests/run.sh 2>&1 | tail -80`
Expected: pytest passes (including `tests/architecture`), every QML file shows `0 failed`, no error lines, and the exit status is 0.

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): run reads, control requests and logs fetches survive a project switch

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Covered by |
|---|---|
| `projectRoots` input; usable-root rule; first position wins | Task 1 Steps 5 and 7 (`usableRoots`), test 1 |
| `runsByProject`, `projectErrors`, merged `runs` with first-root de-dup and `withProject` | Task 1 Step 8 (`applyProjects`, `taggedByProject`, `mergedRuns`), tests 2-3 |
| `refresh()` argv; no usable root empties the outputs | Task 1 Step 6, test 1 and the no-usable-root test |
| Snapshot runner script and no guard | Task 1 Step 9, tests 1 and 29 |
| Latest-wins | Unchanged `HelperRunner`, `test_only_the_latest_refresh_is_applied` |
| Reply cases 1-5: AmMissing, per-entry ok/fail, re-merge, post-good path vs. no entry ok, coverage at 0 | Task 1 Step 8, tests 4-8, test 32 |
| Kept rows for a failed root | Task 1 Step 8 (`keptRows`), Task 3 `test_a_run_kept_by_a_failed_root_reads_back_from_its_row` |
| Whole-call failures | Task 1 Step 8 (`applySnapshot`), test 7, `test_another_ok_false_keeps_the_previous_runs` |
| Registry change: drop, re-merge, then refresh; no alert | Task 1 Step 7 (`registryChanged`), test 9 |
| Opening the panel: stale clock with no project | Task 1 Step 6 (`restartStale`), test 11 |
| A project switch changes nothing in the run list; `projectSwitched` on `onProjectChanged` with only the kept resets | Task 1 Step 7, test 10 and the rewritten switch tests |
| `runFilter` header comment | Task 1 Step 5 |
| Watch survives a switch (`isCurrentWatch`) | Task 1 Step 6, tests 10 and 15 |
| Run reads with no project; `madeFor` drop removed; rebuilt run keeps `project` and replaces it in `runsByProject` | Task 3 Step 3, Task 3 tests |
| Control request settled when its dropped reply's runner goes idle | Task 3 Step 4, test 12 (control half) |
| Logs fetch ends `logsLoading` | Task 3 Step 5, test 12 (logs half) |
| Header comment | Task 1 Step 5 |
| `App.qml` binding; `tst_app_runs` items 13-14 | Task 2 |
| UI tests on the new reply shape and argv | Task 2 Step 5 |

**Placeholder scan:** no step says "TBD", "handle errors" or "similar to". Every code step shows its code. Task 2 Step 6 covers an unlisted UI test failing for the one known reason, and gives the exact rule for it.

**Type consistency:**
- `usableRoots()` returns `[{root, name}]`; `taggedByProject` and `mergedRuns` take `(byProject, usable)`; `mergedRuns` returns `{runs, owner}`. `applyProjects(entries, exitCode)` and `registryChanged()` use them that way.
- `withRun(byProject, root, rebuilt)` is defined and used in Task 3, `controlDropped(runner)` likewise.
- The test helpers `allReply`, `okEntry`, `failEntry`, `rec`, `registry`, `rootEntry`, `makeWithRoots`, `activeRoots`, `namedStore`, `capturedList(extra, escalate)` and the properties `snapCmd`, `rootC`, `escRun`, `doneIntRun` are defined in Task 1. Task 3 uses them under the same names.

**Review Focus:** each of the five lines names its test, and each test sits in the task that owns its code.
<!-- task-pipeline: validated -->
