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
