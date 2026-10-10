<!-- The spec this plan implements, prepended verbatim from docs/superpowers/specs/4-1-3-runstore-refresh-8bc05ecf.md. -->

# 4.1.3 RunStore: refresh on nudge with appliedSeq and cursorReset — design

Card `8bc05ecf`, subtask of story 4.1 (`1b1f4f8b`). Parent design:
`/home/mtts/Code/omarchy-project-manager/docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md`
(untracked local file; cited below as **P** with line numbers). Code references are measured on
this branch at `388978f`; re-read before acting.

## Problem

`core/stores/RunStore.qml` treats every `{"changed": [...]}` watch line as "something changed"
and answers each debounced burst with a full snapshot of one project
(`runs-snapshot.py <project_root>`, `refresh()` at `RunStore.qml:163-166`; `debounceTimer` at
`:1300-1306`). Since 4.1.1 and 4.1.2 the helpers speak a different contract:

- `runs-watch.py` takes no project and no run ids, watches every project, and prints
  `{"changed": [{"run": ID, "seq": G}, ...]}` followed by `{"cursor": C}`, and a hello carrying
  `head`, `cursorReset` and `storeId` (`core/backend/runs/runs-watch.py:1-30`).
- `runs-snapshot.py` with no argument lists every project and forwards `as_of_seq` and
  `store_id`; `runs-snapshot.py --run RUN` reads one run through `am status` alone; an am
  refusal (`StoreBusyError`, `UnknownRunError`, ...) is re-emitted unchanged
  (`core/backend/runs/runs-snapshot.py:1-33`).

The store still launches the watch with `[project, ...runIds]` (`RunStore.qml:223-238`), which
the 4.1.1 helper refuses as a Usage error, and still reads `changed` as an array of strings.

## Goal

The store reads snapshots and treats watch lines as nudges (P:45-47, P:101-112). A nudge for a
run the store already holds refreshes only that run, once per debounce window, and only when the
nudge is newer than the snapshot that last covered the run. Anything the store cannot place
refreshes the list. A `cursorReset` hello starts over from a full snapshot.

## Inherited constraints

- The plugin never folds events into state; a watch line is a nudge "run X changed at seq N"
  (P:45-47, P:101-104).
- am calls are argv lists through the helpers only; no reading of `am.db`, journals or the data
  dir (P:58-59). This card changes no helper: `runs-watch.py` and `runs-snapshot.py` are done
  (4.1.1, 4.1.2) and the single-run read is `runs-snapshot.py --run RUN` (no second helper).
- A snapshot plus the events with `gseq > as_of_seq` is complete with no repeats; lines with an
  unknown event or key are ignored (P:79-80).
- No dead-run detection from events; the lease poll stays (P:61-62): `livenessTimer`,
  `pollTimer` and `staleTimer` keep calling `refresh()`.
- Registered-project filtering happens in the store, from the snapshot's `project.repo_dir`
  (P:87-89, P:131-133). Inside `RunStore` the only registered project is the one it is given,
  `store.project` (App composes it with `backendDir`, `project`, `active`, `searchQuery` only).
- Errors (P:193-205): `cursorReset` clears `appliedSeq`, the cursor and the list, full snapshot,
  no alerts; a nudge for a run already covered is ignored; a nudge for an unknown run refreshes
  the list; `am status` refusing an unknown run drops the run on the next list snapshot with no
  error toast; `StoreBusyError` keeps the last good snapshot, shows `stale`, retries on the next
  nudge or poll.
- In M4 the watch cursor is held in memory only; persisting it is the Alerts milestone's work
  (P:269).
- Layering per `docs/architecture.md`; `tests/architecture` must pass (P:230-237). Stores import
  only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`.
- Comments and docstrings state the contract only, no narrative.
- am output in tests comes from `tests/fixtures/am/` through `tests/helpers/amFixtures.js`;
  a hand-built edge case is labelled `synthetic:`.
- Verification: `bash tests/run.sh` green. TDD: tests first.

## Behaviour

### Vocabulary

- **List snapshot**: `runs-snapshot.py` launched with no argument by `snapshotRunner`. Reply
  `{ok: true, as_of_seq, store_id, runs: [{<am runs row>, status: <am status data>}], data_dir}`.
- **Run read**: `runs-snapshot.py --run RUN`. Reply
  `{ok: true, run, as_of_seq, store_id, status: <am status data>, data_dir}` (no `am runs` row).
- **Nudge**: one entry `{run, seq}` of a `changed` line from the current watch.
- **Covered seq** of a run: the `as_of_seq` of the snapshot that last covered it (`appliedSeq`).

### New public members

| member | type | meaning |
|---|---|---|
| `asOfSeq` | int | `as_of_seq` of the last good list snapshot; 0 before one, or when that reply carried no non-negative integer `as_of_seq` |
| `appliedSeq` | map `{runId: int}` | covered seq of every run listed by the last good list snapshot (every project's, before filtering), raised by run reads |
| `watchCursor` | int | the last valid `{"cursor": C}` from the current watch; 0 = none |
| `nudges` | map `{runId: int}` | nudges not yet consumed: the highest seq seen per run since the last trigger |
| `readRunners` | list (read-only alias) | the in-flight run reads, oldest first |

`pending` keeps its current meaning (control requests); nudges never use it. Every map above is
replaced, never changed in place. No Timer is added: the timer set asserted by
`test_logs_add_no_timer` (`tests/core/stores/tst_run_store.qml:1420`) stays
`debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer,toastTimer`.

### List snapshot (`refresh()`)

1. `refresh()` with a project launches `snapshotRunner.run([])`: the argv is exactly
   `["python3", <backendDir>runs/runs-snapshot.py]`. The launch guard stays `store.project`.
   No project: nothing is launched (unchanged).
2. An `ok: true` reply:
   - keeps only entries whose project is `store.project`. An entry's project is
     `entry.project.repo_dir` when `entry.project` is an object with a string `repo_dir`, else
     `entry.repo_dir` when it is a string, else the entry has no project and is dropped. Both
     sides are compared after removing trailing `/` characters (a lone `/` stays `/`).
   - normalizes the kept entries exactly as today (`Runs.normalizeRun({row, status})`, in am's
     order) and replaces `runs`; alerts, `settleAfterSnapshot`, `logsAfterSnapshot`, amStatus,
     lastError, stale and the first-watch start behave as today (`RunStore.qml:496-541`).
   - sets `asOfSeq` to the reply's `as_of_seq` (non-negative integer, else 0) and replaces
     `appliedSeq` with `{id: asOfSeq}` for every well-formed entry in the reply, of every project.
     A run read with a higher covered seq that landed earlier is overwritten: the list is am's
     state as of `asOfSeq`.
   - remembers each kept entry's `am runs` row, so a later run read can rebuild the run.
3. An `ok: false` reply with `error.type === "StoreBusyError"`: `runs`, `appliedSeq`, `asOfSeq`,
   `amStatus` and `lastError` are unchanged; `stale` becomes `true`; no toast. The next nudge,
   liveness tick or poll retries.
4. Any other failure: unchanged behaviour (`AmMissing` empties the runs and sets `missing`; the
   rest set `error` and `lastError`). `AmMissing` also empties `appliedSeq` and sets `asOfSeq` 0.

### Watch launch

`startWatch()` launches exactly `["python3", <backendDir>runs/runs-watch.py]`: no project, no
run ids, no `--since-seq` (the cursor is not handed back in this card). It still starts on the
first good list snapshot while active, once per activation or project switch, with the same
`launchSeq`/`launchProject` guard.

### Watch lines

Only lines from the current watch count (`isCurrentWatch`, unchanged). Lines are parsed as today;
never throws.

- `{"changed": [...]}`: each entry that is an object with a non-empty string `run` and an
  integer `seq >= 1` is recorded as `nudges[run] = max(nudges[run], seq)`. Every other entry is
  ignored (strings included). When at least one entry was recorded the debounce restarts; a line
  with none changes nothing. Recording never compares with `appliedSeq`: that happens on trigger.
- `{"cursor": C}`: `watchCursor = C` when `C` is an integer `>= 0`; anything else is ignored.
- `{"ok": false, ...}`: kept as the exit envelope (unchanged).
- `{"hello": {...}}`: `amSchema`/`amVersion` as today. When `hello.cursorReset === true` (JSON
  true only): `appliedSeq = {}`, `asOfSeq = 0`, `watchCursor = 0`, `nudges = {}`, the debounce
  stops, `runs = []`, `alertsArmed = false` (the next snapshot only arms, so nothing is replayed
  as a toast), every in-flight run read is dropped (its reply changes nothing), and one list
  snapshot is launched. Selection, logs, controls and dispatch are untouched. A hello without
  `cursorReset: true` starts nothing (unchanged, `test_hello_starts_nothing`).
- Anything else is ignored.

### Debounce trigger

`debounceTimer` (250 ms, unchanged) no longer calls `refresh()` directly. On trigger the store
takes `nudges` and empties it, then for each run whose nudge seq is greater than
`appliedSeq[run]` (absent counts as "unknown"):

1. If any such run is **unknown** (no key in `appliedSeq`), exactly one list snapshot is launched
   and no run read; the list covers every run.
2. Otherwise, for each such run that is in `runs` (the current project's), exactly one run read
   is launched, in nudge order.
3. A run that is in `appliedSeq` but not in `runs` (another project's run, listed by the last
   list snapshot) is ignored.

Nudges with `seq <= appliedSeq[run]` are ignored (stale). A trigger with nothing left launches
nothing.

### Run read

- Launched on its own runner (one per run, so several runs read in parallel), argv exactly
  `["python3", <backendDir>runs/runs-snapshot.py, "--run", RUN]`, guarded by `store.project`.
  A reply after a project switch or a `cursorReset` changes nothing. A runner leaves
  `readRunners` and is destroyed when its process exits.
- A newer read for the same run supersedes an older in-flight one: the older reply changes
  nothing.
- `ok: true` with `run` equal to the run asked, `status` an object and `as_of_seq` a non-negative
  integer, for a run still in `runs` whose `appliedSeq` is not greater than the reply's
  `as_of_seq`: the run at the same position is replaced by
  `Runs.normalizeRun({row: <its remembered am runs row>, status: <reply status>})`; `runs` is a
  new array, the other runs are the same objects; `appliedSeq[run] = as_of_seq`. Then, as after a
  list snapshot: alerts are compared against the previous `runs` and raised while active and
  armed, `settleAfterSnapshot()` and `logsAfterSnapshot()` run, `stale` becomes false and the
  stale clock restarts while active. `asOfSeq`, `amStatus` and `lastError` are unchanged.
  Any other `ok: true` reply changes nothing.
- `ok: false` with `error.type === "UnknownRunError"`: no toast, `lastError` and `amStatus`
  unchanged, the run stays until the next list snapshot, and one list snapshot is launched (the
  run then drops out because am no longer lists it).
- `ok: false` with `StoreBusyError`: `runs` unchanged, `stale = true`, no toast, `lastError` and
  `amStatus` unchanged; the run's nudge seq is put back into `nudges` (max rule) without
  restarting the debounce, so the next trigger retries it.
- Any other failure (`AmMissing`, `SchemaMismatch`, `HelperError`, unparseable output): nothing
  changes; the list snapshot path reports such conditions.

### Clearing

- `projectSwitched()` additionally empties `nudges`, `appliedSeq`, `asOfSeq` and drops every
  in-flight run read. `watchCursor` is global (not per project) and is kept.
- `stopLive()` (panel closed) additionally empties `nudges`. Run reads in flight land as the
  list snapshot does today.

### Header comment

The `RunStore.qml` header (`:6-20`) and the `watchLine`/`startWatch`/`refresh` comments are
rewritten to the contract above: one list snapshot of every project filtered to `project`, the
watch as a nudge source, one run read per newer nudge, `appliedSeq`/`asOfSeq`/`watchCursor`.

## Known consequences (not changed here)

- The list's terminal cap (10 newest terminal runs among am's 200 newest rows) is now global
  across projects (`runs-snapshot.py:12-16`), so a project can show fewer finished runs than
  before when others are busier. That is 4.1.2's selection rule.
- A nudge for one of this project's terminal runs that the list did not select is "unknown" and
  costs a list snapshot each time it is nudged.

## Error table

| case | behaviour |
|---|---|
| nudge with `seq <= appliedSeq[run]` | ignored, nothing launched |
| nudge for a run not in `appliedSeq` | one list snapshot per trigger, no run reads in that trigger |
| nudge for another project's listed run | ignored |
| several nudges for one run in a window | one run read, at the highest seq |
| changed entry that is a string, has a non-integer/zero/negative seq or empty run | ignored; no debounce if none valid |
| `{"cursor": C}` with C not an integer `>= 0` | ignored |
| hello `cursorReset: true` | `appliedSeq`, `asOfSeq`, `watchCursor`, `nudges`, `runs` cleared, alerts disarmed, reads dropped, one list snapshot |
| run read: `UnknownRunError` | no toast, no lastError; one list snapshot; the run drops when unlisted |
| run read or list: `StoreBusyError` | last good runs kept, `stale = true`, no toast, retried on next nudge/poll |
| run read reply older than `appliedSeq[run]` | ignored |
| run read reply after project switch / cursorReset / superseded | ignored |
| list entry with no project or another project | not shown; still recorded in `appliedSeq` when it has an id |

## Tests

All in **QML store tier** (`tests/core/stores/tst_run_store.qml`, TestCase `StoresRunStore`)
unless noted: the behaviour is the store's reaction to helper stdout, driven through stubbed
`Process` objects (`reply(proc, text, code)`, `store.watchLine(store.watchProc, line)`,
`store.debounceTimer.triggered()`), which is exactly what this tier exists for. List replies are
built from `runs.json` rows plus `status-*.json` data with `runs.json`'s `as_of_seq` (989) and
`store_id`; run replies from `status-*.json` data. The helper's own lines (`changed`, `cursor`,
the forwarded hello) are labelled `synthetic:` with the helper contract they follow.

New:

1. `refresh()` argv is exactly `[python3, …/runs-snapshot.py]`, guarded by the project.
2. A list reply keeps only entries whose `project.repo_dir` (or `repo_dir`) equals `project`,
   trailing `/` ignored; sets `asOfSeq` and `appliedSeq` for every listed run of every project.
3. `startWatch` argv is exactly `[python3, …/runs-watch.py]`.
4. A changed line for a held run refreshes only that run, once, after the debounce: argv
   `[python3, …/runs-snapshot.py, --run, ID]`; no list snapshot; reply replaces that run
   (same position), sets `appliedSeq[run]`, leaves the other run objects identical.
5. Stale nudge (`seq <= appliedSeq`): nothing launched after the trigger.
6. Latest wins: two lines for one run in a window → one read; `nudges[run]` holds the max.
7. Unknown run → exactly one list snapshot, no run reads, even with known runs in the same window.
8. Another project's listed run → nothing launched.
9. Invalid changed entries (strings, seq 0, float, empty run) are ignored; a line of only
   invalid entries does not start the debounce.
10. `{"cursor": C}` sets `watchCursor`; invalid values leave it.
11. `cursorReset: true` hello clears `appliedSeq`, `asOfSeq`, `watchCursor`, `nudges`, `runs`,
    disarms alerts and launches one list snapshot; an in-flight run read's late reply changes
    nothing; the next list snapshot raises no toast.
12. Project switch guard: an old project's run-read reply and old watch lines change nothing;
    `nudges`, `appliedSeq`, `asOfSeq` are emptied; `watchCursor` kept.
13. Run read `UnknownRunError`: no toast, `lastError` empty, `amStatus` unchanged, one list
    snapshot launched; its reply without the run drops it.
14. `StoreBusyError` on a list snapshot keeps the runs and sets `stale`, `amStatus` unchanged;
    on a run read the same, and the next trigger retries that run.
15. A run read whose reply turns a run escalated raises one toast while active and armed.
16. A run read reply older than `appliedSeq[run]` (a list landed in between) changes nothing.
17. Two runs nudged in one window: two run reads in parallel, both replies applied.

Updated (same tier, existing tests whose inputs or argv the contract changed): the argv tests
(`tst_run_store.qml:78-90`, `:92-109` and every `command[2] === root` assertion), the watch-argv
tests around `:356-420`, the debounce tests around `:422-510` and `:577-600` (changed entries
become `{run, seq}`; the trigger no longer launches a list snapshot for a held run), the
project-switch/watch-guard tests around `:888-940` and `:1069`, every test that switches to
`rootB` (its entries need `repo_dir` `rootB`).

Flow tier (`tests/core/stores/tst_app_runs.qml:78`, `tests/ui/tst_runs_flow.qml`,
`tests/ui/tst_runs_real_data.qml`): updated, not extended. They compose App and assert the
snapshot argv or feed snapshot replies; the argv loses the root and entries must belong to the
selected project (`tst_runs_real_data.qml` selects `/home/u/a` while `runs.json` rows carry
`/home/user/Code/omarchy-project-manager`, so the selected project must be the fixture's
`repo_dir`). Any flow that fires a changed line switches to `{run, seq}` entries.

Architecture tier (`tests/architecture`): unchanged, must pass.

## Out of scope

- Any change to `runs-watch.py`, `runs-snapshot.py`, `runs.js` or other helpers (4.1.1, 4.1.2,
  4.0.3 are done).
- 4.1.4: resetting on a `store_id` change (hello `storeId` or snapshot `store_id`); this card
  ignores `store_id`.
- Persisting `watchCursor` or passing `--since-seq` to the watch (Alerts milestone, P:269).
- Global Runs, the timeline, the alert cursor, start-run discovery (4.3, dropped from M4) and
  the 4.2 spec retargets.
- `docs/architecture.md` and README run-monitor sections (4.4.1).
- Showing other projects' runs; registry (`brd projects`) filtering beyond `store.project`.

---

# 4.1.3 RunStore: refresh on nudge with appliedSeq and cursorReset — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `core/stores/RunStore.qml` read list snapshots of every project (filtered to `store.project`), treat `runs-watch.py` lines as `{run, seq}` nudges, answer a newer nudge for a held run with one `runs-snapshot.py --run RUN` read and an unknown run with one list snapshot, and start over on a `cursorReset` hello.

**Architecture:** One QML store, edited in place. The list path (`refresh()`/`applySnapshot()`) loses its root argument and gains a project filter plus `asOfSeq`/`appliedSeq` coverage. `watchLine()` records nudges into a `{runId: seq}` map; `debounceTimer` calls a new `triggerNudges()` that compares each nudge with `appliedSeq`. Run reads are one `HelperRunner` per read (a `readC` Component, like `controlC`), tracked in a private `readState` QtObject (`runners`, `latest`, `rows`). No helper, domain file or Timer is added or changed.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), the QML store test tier (`qmltestrunner` with `tests/stubs`), Python only for the unchanged architecture tests.

**Spec:** `docs/superpowers/specs/4-1-3-runstore-refresh-8bc05ecf.md` (prepended above, verbatim).

## Global Constraints

- The watch is a nudge source only ("run X changed at seq N"); the store never folds events into state.
- am is reached only through `runs-snapshot.py` and `runs-watch.py` argv lists; no `am.db`, journal or data-dir reads. No helper changes: `runs-watch.py`, `runs-snapshot.py`, `runs.js` and every other file under `core/backend/` and `core/domain/` stay as they are.
- List snapshot argv is exactly `["python3", <backendDir>runs/runs-snapshot.py]`; run read argv exactly `["python3", <backendDir>runs/runs-snapshot.py, "--run", RUN]`; watch argv exactly `["python3", <backendDir>runs/runs-watch.py]` (no project, no run ids, no `--since-seq`).
- A list entry's project is `entry.project.repo_dir` (object with a string `repo_dir`), else `entry.repo_dir` (string), else none (dropped); both sides compared with trailing `/` removed (a lone `/` stays `/`).
- `asOfSeq`, `watchCursor`: non-negative integers, 0 = none. `appliedSeq`, `nudges`: `{runId: int}` maps, replaced, never changed in place. A nudge entry counts only as an object with a non-empty string `run` and an integer `seq >= 1`.
- No Timer is added: the timer set stays `debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer,toastTimer` (`test_logs_add_no_timer_and_none_runs_while_idle`). `livenessTimer`, `pollTimer` and `staleTimer` keep calling `refresh()`.
- `pending` keeps its meaning (control requests); nudges never use it.
- `watchCursor` is memory only and global (a project switch keeps it); it is never handed back to the watch.
- `store_id` is ignored in this card (4.1.4).
- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain`; `tests/architecture` passes.
- Comments and docstrings state the contract only, no narrative.
- am output in tests comes from `tests/fixtures/am/` through `tests/helpers/amFixtures.js` (`F.load`); a hand-built edge case is labelled `synthetic:`.
- Out of scope (do not touch): `docs/architecture.md`, `README.md`, `tests/fixtures/*`, `tests/contract/*`, every helper and its Python tests.
- Verification: `bash tests/run.sh` green. TDD: tests first.
- Never signal a process by name or pattern; stop a stuck test run with `timeout`.

## Review Focus

- A run read still in flight when the user switches to another project and back (A → B → A): the old reply must change nothing, although `madeFor` equals the project again. Pinned in Task 3 (`test_a_read_from_before_a_return_to_the_project_changes_nothing`).
- A run read that moves the selected run's open attempt (started → ok): the Run detail pane must fetch the attempt's logs again, exactly as after a list snapshot. Pinned in Task 3 (`test_a_read_that_moves_the_selected_attempt_fetches_its_logs`).
- A run read that moves a run with an acknowledged control request: the request must settle (buttons come back) without waiting for the next list. Pinned in Task 3 (`test_a_read_that_moves_the_run_settles_its_pending_request`).
- A run read that lands after the panel closed: applied like a late list snapshot, but no toast and no stale clock. Pinned in Task 3 (`test_a_read_landing_after_the_panel_closed_is_applied_quietly`).
- A list reply whose `as_of_seq` is missing, negative, a float, a string or null: `asOfSeq` and every covered seq become 0 (so any nudge is newer), and the list still replaces the coverage. Pinned in Task 1 (`test_a_list_reply_without_a_usable_as_of_seq_covers_at_0`).

## Running tests

One QML test file (fast; run from the worktree root):

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input <path> 2>&1 | grep -E "^(FAIL|Totals)"
```

The whole gate (pytest, then every QML file against a temp mirror of the repo; also fails on `TypeError`/`ReferenceError` output):

```bash
timeout 900 bash tests/run.sh
```

Test helpers already in `tests/core/stores/tst_run_store.qml` that the new tests use: `make()`, `makeWithProject(root)`, `reply(proc, text, code)` (sets `outText` then emits `exited`), `activeStore(root)`, `watchedStore(entries)`, `sendLine(proc, value)`, `helloLine(key)`, `fire(timer)` (stops a one-shot timer, then emits `triggered`), `ids(list)`, `argv(proc)` (`command.join("|")`), `logsReply(stdout)`, `ctlOk(data)`, `openCard` (`"2280a6ab-9c40-434b-9729-63fd1f373754"`), `rootA` (`"/home/u/my proj"`), `rootB` (`"/home/u/b"`). QML functions in a `TestCase` are visible from anywhere in it, so the new sections can be appended at the end of the file.

Fixture facts the tests rely on: `runs.json` data is `{as_of_seq: 989, runs: [started row, done row], store_id}`; both rows carry `project: {id: 1, repo_dir: "/home/user/Code/omarchy-project-manager"}` and the same `repo_dir`; the started run is `20261008T143823Z-e795ad19` (`status-started.json`, as_of_seq 989, live lease), the done run `20261008T143807Z-63060df3` (`status-done.json`, as_of_seq 1005); `status-escalated.json` is another run's escalated `am status` data with as_of_seq 1005. `Runs.normalizeRun` takes the run id from the row first, so a status capture under another run's id keeps the row's id (such uses are labelled `synthetic:`).

## File Structure

- Modify: `core/stores/RunStore.qml` — the store (the only source file touched).
- Modify: `tests/core/stores/tst_run_store.qml` — store tests: existing ones updated per task, new sections appended at the end of the file.
- Modify: `tests/core/stores/tst_app_runs.qml` — the snapshot argv assertion (Task 1).
- Modify: `tests/ui/tst_runs_real_data.qml` — the selected project becomes the captures' `repo_dir`; the snapshot reply forwards `as_of_seq`/`store_id` (Task 1).
- `tests/ui/tst_runs_flow.qml` needs no change: its entries already carry `repo_dir: "/home/u/a"`, the selected project, and it fires no changed line.

Spec test numbers → tasks: 1, 2, 14 (list half) → Task 1; 3, 5, 6 (recording), 7, 8, 9, 10, 12 (nudges/cursor) → Task 2; 4, 6 (one read), 12 (reads), 15, 16, 17 → Task 3; 13, 14 (read half) → Task 4; 11 → Task 5.

---

### Task 1: List snapshot of every project, filtered to `project`, with `asOfSeq` and `appliedSeq`

**Files:**
- Modify: `core/stores/RunStore.qml` (properties near `:47`, `refresh()` `:161-166`, `projectSwitched()` `:313-350`, `applySnapshot()` `:490-545`)
- Test: `tests/core/stores/tst_run_store.qml`, `tests/core/stores/tst_app_runs.qml`, `tests/ui/tst_runs_real_data.qml`

**Interfaces:**
- Consumes: `Runs.normalizeRun`, `Runs.errorText`, `store.rowOf(e)`, `store.parseEnvelope(text)` (all existing).
- Produces: `property int asOfSeq`, `property var appliedSeq` (`{runId: int}`), `function isSeq(value) -> bool` (non-negative integer), `function entryProject(e) -> string|null`, `function trimSlashes(path) -> string`; `refresh()` launches `snapshotRunner.run([])`. Test helpers: `entry(id, runStatus, live, root)`, `okReply(entries, asOf)`, `treeEntry(id, status, root)`, `capRoot`, `startedRun`, `doneRun`, `capturedList(extra, asOf)`.

- [ ] **Step 1: Update the existing tests whose inputs or argv the contract changes**

Apply each replacement below exactly (each `Replace:` block occurs once in its file).

**`tests/core/stores/tst_run_store.qml`** — `entry()` takes the project root (`tst_run_store.qml:43-58`). Replace:

```qml
  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data.
  function entry(id, runStatus, live) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
```

with:

```qml
  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data. Its repo_dir is `root`, else rootA.
  function entry(id, runStatus, live, root) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: root || tc.rootA, started_at: "2026-10-01T00:00:00Z",
```

**`tests/core/stores/tst_run_store.qml`** — `okReply()` takes an optional as_of_seq (`tst_run_store.qml:60-62`). Replace:

```qml
  function okReply(entries) {
    return JSON.stringify({ ok: true, runs: entries, data_dir: "/home/u/.local/share" }) + "\n"
  }
```

with:

```qml
  // A list snapshot reply; with `asOf`, it carries that as_of_seq.
  function okReply(entries, asOf) {
    var envelope = { ok: true, runs: entries, data_dir: "/home/u/.local/share" }
    if (asOf !== undefined) envelope.as_of_seq = asOf
    return JSON.stringify(envelope) + "\n"
  }
```

**`tests/core/stores/tst_run_store.qml`** — `test_setting_the_project_starts_a_snapshot_with_the_exact_argv`: no root argument. Replace:

```qml
    compare(proc.command.length, 3)
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command[2], "/home/u/my proj", "the path with a space is one argument")
    compare(proc.running, true)
```

with:

```qml
    compare(proc.command.length, 2, "every project: no root argument")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.running, true)
```

**`tests/core/stores/tst_run_store.qml`** — `test_a_project_switch_clears_runs_selection_and_error_and_refreshes`. Replace:

```qml
    verify(procB !== procA, "a new snapshot was launched")
    compare(procB.command[2], "/home/u/b")
```

with:

```qml
    verify(procB !== procA, "a new snapshot was launched")
    compare(procB.command.length, 2)
```

**`tests/core/stores/tst_run_store.qml`** — `test_a_project_switch_drops_the_old_projects_late_result` (1 of 2). Replace:

```qml
    verify(procB !== procA2, "a snapshot for B was launched")
    compare(procB.command[2], "/home/u/b")
```

with:

```qml
    verify(procB !== procA2, "a snapshot for B was launched")
    compare(procB.launchGuard, "/home/u/b")
```

**`tests/core/stores/tst_run_store.qml`** — `test_a_project_switch_drops_the_old_projects_late_result` (2 of 2): B's entry belongs to B. Replace:

```qml
    reply(procB, okReply([entry("b1", "done", false)]), 0)
    compare(store.runs.length, 1, "B's reply is applied")
```

with:

```qml
    reply(procB, okReply([entry("b1", "done", false, rootB)]), 0)
    compare(store.runs.length, 1, "B's reply is applied")
```

**`tests/core/stores/tst_run_store.qml`** — `test_malformed_runs_are_skipped_without_throwing`: the bare entry names its project. Replace:

```qml
var mixed = JSON.stringify({ ok: true, runs: [null, 3, "x", [1], entry("r1", "started", true), { id: "r2" }] })
```

with:

```qml
var mixed = JSON.stringify({ ok: true, runs: [null, 3, "x", [1], entry("r1", "started", true), { id: "r2", repo_dir: rootA }] })
```

**`tests/core/stores/tst_run_store.qml`** — `test_activation_refreshes_the_project`. Replace:

```qml
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel fetches a fresh snapshot")
    compare(store.snapshotRunner.current.command[2], "/home/u/my proj")
```

with:

```qml
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel fetches a fresh snapshot")
    compare(store.snapshotRunner.current.command.length, 2)
```

**`tests/core/stores/tst_run_store.qml`** — `test_watch_argv_after_first_snapshot`: the id-less entry names its project (Task 2 rewrites this test). Replace:

```qml
    var noId = { workflow: "orchestrator" }
```

with:

```qml
    var noId = { workflow: "orchestrator", repo_dir: rootA }
```

**`tests/core/stores/tst_run_store.qml`** — `test_project_switch_stops_watch_and_clears_runs`. Replace:

```qml
    compare(store.snapshotRunner.current.command[2], "/home/u/b", "B's snapshot is requested")
```

with:

```qml
    compare(store.snapshotRunner.current.launchGuard, "/home/u/b", "B's snapshot is requested")
```

**`tests/core/stores/tst_run_store.qml`** — `test_new_project_watch_starts_after_its_snapshot`: B's entry belongs to B. Replace:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true)]), 0)
    var w = store.watchProc
```

with:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true, rootB)]), 0)
    var w = store.watchProc
```

**`tests/core/stores/tst_run_store.qml`** — `test_project_switch_clears_warning_and_poll`: B's entry belongs to B. Replace:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    compare(store.watching, true, "B's watch is tried")
```

with:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false, rootB)]), 0)
    compare(store.watching, true, "B's watch is tried")
```

**`tests/core/stores/tst_run_store.qml`** — `test_hello_reset_on_project_switch`: B's entry belongs to B. Replace:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    sendLine(store.watchProc, helloLine("schema_1"))
```

with:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false, rootB)]), 0)
    sendLine(store.watchProc, helloLine("schema_1"))
```

**`tests/core/stores/tst_run_store.qml`** — `test_old_watch_hello_ignored`: B's entry belongs to B. Replace:

```qml
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    verify(store.watchProc !== old, "B runs its own watch")
```

with:

```qml
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false, rootB)]), 0)
    verify(store.watchProc !== old, "B runs its own watch")
```

**`tests/core/stores/tst_run_store.qml`** — `test_old_watch_lines_ignored_after_switch`: B's entry belongs to B. Replace:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true)]), 0)
    sendLine(old, { changed: ["a"] })
```

with:

```qml
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true, rootB)]), 0)
    sendLine(old, { changed: ["a"] })
```

**`tests/core/stores/tst_run_store.qml`** — `treeEntry()` takes the project root and sets both project keys (`tst_run_store.qml:1170-1183`). Replace:

```qml
  // A snapshot entry of the started capture: runs.json's first `am runs` row
  // whose `status` is status-started.json's `am status` data. Its open attempt
  // is openCard explore 1 and doneCard spec 1 is an earlier, ok attempt. The
  // run id and repo dir are the test's; so is the open attempt's status, in
  // am's attempt vocabulary (started, ok).
  function treeEntry(id, status) {
    var e = F.load("runs.json").data.runs[0]
    e.id = id
    e.repo_dir = tc.rootA
```

with:

```qml
  // A snapshot entry of the started capture: runs.json's first `am runs` row
  // whose `status` is status-started.json's `am status` data. Its open attempt
  // is openCard explore 1 and doneCard spec 1 is an earlier, ok attempt. The
  // run id and project root (`root`, else rootA) are the test's; so is the
  // open attempt's status, in am's attempt vocabulary (started, ok).
  function treeEntry(id, status, root) {
    var e = F.load("runs.json").data.runs[0]
    e.id = id
    e.repo_dir = root || tc.rootA
    e.project.repo_dir = root || tc.rootA
```

**`tests/core/stores/tst_run_store.qml`** — `test_changing_the_selected_run_resets_to_its_default_attempt`: r2's project is rootA. Replace:

```qml
    r2.repo_dir = tc.rootA
```

with:

```qml
    r2.repo_dir = tc.rootA
    r2.project.repo_dir = tc.rootA
```

**`tests/core/stores/tst_run_store.qml`** — `test_logs_argv_leads_with_the_current_project_root`: B's entry belongs to B. Replace:

```qml
    store.project = tc.rootB
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    compare(store.logsRunner.current, procA
```

with:

```qml
    store.project = tc.rootB
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started", tc.rootB)]), 0)
    compare(store.logsRunner.current, procA
```

**`tests/core/stores/tst_run_store.qml`** — `test_every_logs_launch_after_a_switch_carries_the_new_root` (1 of 2). Replace:

```qml
    store.project = tc.rootB
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("b\n"), 0)
```

with:

```qml
    store.project = tc.rootB
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started", tc.rootB)]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("b\n"), 0)
```

**`tests/core/stores/tst_run_store.qml`** — `test_every_logs_launch_after_a_switch_carries_the_new_root` (2 of 2). Replace:

```qml
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches again")
```

with:

```qml
    snapshot(store, [treeEntry("r1", "ok", tc.rootB)])
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches again")
```

**`tests/core/stores/tst_run_store.qml`** — `test_logs_argv_keeps_an_odd_root_verbatim`: the entry belongs to the odd root. Replace:

```qml
    var store = makeWithProject(odd); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
```

with:

```qml
    var store = makeWithProject(odd); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started", odd)]), 0)
```

**`tests/core/stores/tst_run_store.qml`** — `test_a_project_switch_empties_the_toasts_and_disarms`: B's entry belongs to B. Replace:

```qml
    reply(store.snapshotRunner.current, okReply([escalated("z")]), 0)
    compare(store.toasts.length, 0, "B's first snapshot raises nothing")
```

with:

```qml
    reply(store.snapshotRunner.current, okReply([entry("z", "escalated", false, rootB)]), 0)
    compare(store.toasts.length, 0, "B's first snapshot raises nothing")
```

**`tests/core/stores/tst_run_store.qml`** — `test_start_ok_with_run_id_emits_and_saves`: the refetch is a list snapshot. Replace:

```qml
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py|/home/u/my proj")
```

with:

```qml
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
```

**`tests/core/stores/tst_app_runs.qml`** — `test_the_snapshot_runs_for_the_selected_root_path` (`tst_app_runs.qml:73-80`). Replace:

```qml
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command[2], "/home/u/my proj")
```

with:

```qml
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command.length, 2, "every project, filtered to the root path by the store")
    compare(proc.launchGuard, "/home/u/my proj")
```

**`tests/ui/tst_runs_real_data.qml`** — The selected project is the captures' repo_dir (`tst_runs_real_data.qml:18`). Replace:

```qml
  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
```

with:

```qml
  // The captured runs' project: runs.json's repo_dir, so the store keeps them.
  property var pA: ({ root_path: "/home/user/Code/omarchy-project-manager", name: "alpha" })
```

**`tests/ui/tst_runs_real_data.qml`** — `snapshot()` forwards runs.json's as_of_seq and store_id (`tst_runs_real_data.qml:57-64`). Replace:

```qml
  // The runs-snapshot.py reply for the captured runs: each `am runs` row with
  // its `status` replaced by that run's `am status` data, as the helper does.
  function snapshot() {
    var runs = F.load("runs.json").data.runs
    runs[0].status = F.load("status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return JSON.stringify({ ok: true, runs: runs, data_dir: "/d" }) + "\n"
  }
```

with:

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

**`tests/ui/tst_runs_real_data.qml`** — `test_opening_the_done_run_fetches_its_default_attempt_under_the_project_root`. Replace:

```qml
    compare(argv(proc), "/home/u/a|" + doneRun + "|767b5f1c-506a-4daa-9157-0c838165cc63|review|1")
```

with:

```qml
    compare(argv(proc), tc.pA.root_path + "|" + doneRun + "|767b5f1c-506a-4daa-9157-0c838165cc63|review|1")
```

**`tests/ui/tst_runs_real_data.qml`** — `test_a_subtask_row_fetches_its_attempt_and_the_pane_shows_the_captured_output`. Replace:

```qml
    compare(argv(proc), "/home/u/a|" + doneRun + "|7442d674-e0d4-4048-96ee-cd27b5ba34f8|review|1")
```

with:

```qml
    compare(argv(proc), tc.pA.root_path + "|" + doneRun + "|7442d674-e0d4-4048-96ee-cd27b5ba34f8|review|1")
```

**`tests/ui/tst_runs_real_data.qml`** — `test_opening_the_started_run_fetches_its_running_attempt`. Replace:

```qml
            "/home/u/a|" + startedRun + "|2280a6ab-9c40-434b-9729-63fd1f373754|explore|1")
```

with:

```qml
            tc.pA.root_path + "|" + startedRun + "|2280a6ab-9c40-434b-9729-63fd1f373754|explore|1")
```


- [ ] **Step 2: Append the new list-snapshot tests**

In `tests/core/stores/tst_run_store.qml`, insert this block just before the file's final closing `}` (the end of `TestCase`):

```qml
  // ---- list snapshots (4.1.3)

  // The captured runs' project root, and their run ids (runs.json).
  readonly property string capRoot: "/home/user/Code/omarchy-project-manager"
  readonly property string startedRun: "20261008T143823Z-e795ad19"
  readonly property string doneRun: "20261008T143807Z-63060df3"

  // runs-snapshot.py's list reply for the captures: runs.json's two `am runs`
  // rows, each with `status` replaced by its `am status` data
  // (status-started.json, status-done.json), runs.json's store_id and its
  // as_of_seq (989) unless `asOf` is given; `extra` entries come last.
  function capturedList(extra, asOf) {
    var data = F.load("runs.json").data
    var runs = data.runs
    runs[0].status = F.load("status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return JSON.stringify({ ok: true, as_of_seq: asOf === undefined ? data.as_of_seq : asOf,
                            store_id: data.store_id, runs: runs.concat(extra || []), data_dir: "/d" }) + "\n"
  }

  function test_a_list_snapshot_asks_for_every_project() {
    var store = makeWithProject(tc.capRoot); if (!store) return
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
    compare(store.snapshotRunner.current.launchGuard, tc.capRoot, "guarded by the project")
    store.refresh()
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
  }

  function test_a_list_reply_keeps_this_projects_runs_and_covers_every_listed_run() {
    var store = makeWithProject(tc.capRoot + "/"); if (!store) return
    // synthetic: entries runs-snapshot.py lists beside the captures -- another
    // project's; this project's by repo_dir alone with trailing "/"; this
    // project's by repo_dir under a project object with no repo_dir; another
    // project's by project.repo_dir though its repo_dir is this one; and one
    // with no project at all.
    var other = entry("other1", "started", true, "/home/u/elsewhere")
    var flat = entry("flat1", "done", false, tc.capRoot + "//")
    var partial = entry("partial1", "done", false, tc.capRoot)
    partial.project = { id: 9 }
    var moved = entry("moved1", "done", false, tc.capRoot)
    moved.project = { id: 2, repo_dir: "/home/u/elsewhere" }
    var lost = entry("lost1", "done", false)
    delete lost.repo_dir
    reply(store.snapshotRunner.current, capturedList([other, flat, partial, moved, lost]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun + ",flat1,partial1", "this project's, in am's order")
    compare(store.asOfSeq, 989)
    compare(Object.keys(store.appliedSeq).sort().join(","),
            [tc.startedRun, tc.doneRun, "other1", "flat1", "partial1", "moved1", "lost1"].sort().join(","),
            "every listed run of every project is covered")
    compare(store.appliedSeq[tc.startedRun], 989)
    compare(store.appliedSeq.other1, 989)
  }

  // Review Focus 5.
  function test_a_list_reply_without_a_usable_as_of_seq_covers_at_0() {
    var bad = [undefined, -1, 2.5, "989", null]
    for (var i = 0; i < bad.length; i++) {
      var label = "as_of_seq " + JSON.stringify(bad[i])
      var store = makeWithProject(rootA); if (!store) return
      reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)], 989), 0)
      compare(store.appliedSeq.r1, 989, label)
      store.refresh()
      reply(store.snapshotRunner.current, okReply([entry("r2", "started", true)], bad[i]), 0)
      compare(store.asOfSeq, 0, label)
      compare(store.appliedSeq.r2, 0, label)
      compare(store.appliedSeq.r1, undefined, label + ": the list replaces the coverage")
      compare(ids(store.runs), "r2", label)
    }
  }

  function test_a_busy_store_keeps_the_last_list_and_marks_it_stale() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)], 989), 0)
    compare(store.stale, false)
    store.refresh()
    // synthetic: am's StoreBusyError envelope, which runs-snapshot.py re-emits unchanged.
    reply(store.snapshotRunner.current, '{"error": {"message": "the am store is busy; try again", "type": "StoreBusyError"}, "ok": false}\n', 1)
    compare(ids(store.runs), "a", "the last good list stays")
    compare(store.stale, true)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.toasts.length, 0)
    compare(store.asOfSeq, 989)
    compare(store.appliedSeq.a, 989)
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the next tick retries")
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)], 990), 0)
    compare(store.stale, false)
    compare(store.asOfSeq, 990)
  }

  function test_am_missing_and_a_project_switch_forget_the_coverage() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)], 989), 0)
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}\n', 1)
    compare(store.asOfSeq, 0, "AmMissing")
    compare(Object.keys(store.appliedSeq).length, 0, "AmMissing")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)], 989), 0)
    compare(store.asOfSeq, 989)
    store.project = rootB
    compare(store.asOfSeq, 0, "a project switch")
    compare(Object.keys(store.appliedSeq).length, 0, "a project switch")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 204 passed, 9 failed`, the failures being `test_a_busy_store_keeps_the_last_list_and_marks_it_stale`, `test_a_list_reply_keeps_this_projects_runs_and_covers_every_listed_run`, `test_a_list_reply_without_a_usable_as_of_seq_covers_at_0` (`Cannot read property 'r1' of undefined`), `test_a_list_snapshot_asks_for_every_project`, `test_a_project_switch_clears_runs_selection_and_error_and_refreshes`, `test_activation_refreshes_the_project`, `test_am_missing_and_a_project_switch_forget_the_coverage`, `test_setting_the_project_starts_a_snapshot_with_the_exact_argv`, `test_start_ok_with_run_id_emits_and_saves`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 11 passed, 1 failed` (`test_the_snapshot_runs_for_the_selected_root_path`).

`tests/ui/tst_runs_real_data.qml` still passes at this point (the old store does not filter); it pins Step 4.

- [ ] **Step 4: Implement the list path**

**`core/stores/RunStore.qml`** — Add `asOfSeq` and `appliedSeq` above the `watchTried` block (around `RunStore.qml:47`). Replace:

```qml
  // A watch has been started since the last activation or project switch:
```

with:

```qml
  // Snapshot coverage. `asOfSeq` is the last good list snapshot's as_of_seq
  // (0 before one). `appliedSeq` is {runId: seq}: the as_of_seq of the
  // snapshot that last covered each run the list named, of every project.
  // Both are replaced, never changed in place.
  property int asOfSeq: 0
  property var appliedSeq: ({})

  // A watch has been started since the last activation or project switch:
```

**`core/stores/RunStore.qml`** — Replace `refresh()` (`RunStore.qml:161-166`). Replace:

```qml
  // Asks for a fresh snapshot of the current project. A newer call replaces an
  // older one (the runner's latest-wins rule).
  function refresh() {
    if (store.project === "") return
    snapshotRunner.run([store.project])
  }
```

with:

```qml
  // Asks for a list snapshot: runs-snapshot.py with no argument, every
  // project's runs, filtered to `project` on arrival. Nothing without a
  // project. A newer call replaces an older one (the runner's latest-wins rule).
  function refresh() {
    if (store.project === "") return
    snapshotRunner.run([])
  }
```

**`core/stores/RunStore.qml`** — In `projectSwitched()`, forget the coverage right after `debounceTimer.stop()`. Replace:

```qml
    store.watchTried = false
    debounceTimer.stop()
    store.stopPoll()
```

with:

```qml
    store.watchTried = false
    debounceTimer.stop()
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.stopPoll()
```

**`core/stores/RunStore.qml`** — Replace the head of `applySnapshot()` (its comment through the entry loop, `RunStore.qml:490-505`) and add the three helpers above it. Replace:

```qml
  // One snapshot reply. ok:true replaces the runs (none at all is fine).
  // AmMissing empties them: no badges while am is not there. Any other failure
  // -- an ok:false envelope or output that is not one -- keeps what the last
  // good snapshot said and only reports why this one failed. Never throws.
  // A reply for a project the user has left never gets here: the runner only
  // emits `finished` when the launch guard still equals its (project) guard.
  function applySnapshot(stdout, exitCode) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var list = Array.isArray(envelope.runs) ? envelope.runs : []
      var out = []
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e === null || typeof e !== "object" || Array.isArray(e)) continue
        out.push(Runs.normalizeRun({ row: store.rowOf(e), status: e.status }))
      }
```

with:

```qml
  // A non-negative integer: an as_of_seq or a cursor.
  function isSeq(value) {
    return typeof value === "number" && Number.isInteger(value) && value >= 0
  }

  // The entry's project root: project.repo_dir when project is an object with
  // a string repo_dir, else repo_dir when it is a string, else null.
  function entryProject(e) {
    var p = e.project
    if (p !== null && typeof p === "object" && !Array.isArray(p) && typeof p.repo_dir === "string") return p.repo_dir
    return typeof e.repo_dir === "string" ? e.repo_dir : null
  }

  // A path without its trailing "/" characters; a lone "/" stays "/".
  function trimSlashes(path) {
    var s = path
    while (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
    return s
  }

  // One list snapshot reply. ok:true keeps the entries whose project is
  // `project` (trailing "/" ignored on both sides) and replaces the runs with
  // them, in am's order (none at all is fine); asOfSeq becomes its as_of_seq
  // (a non-negative integer, else 0) and appliedSeq {id: asOfSeq} for every
  // entry with an id, of every project. StoreBusyError keeps everything and
  // only marks the runs stale. AmMissing empties them and the coverage: no
  // badges while am is not there. Any other failure -- an ok:false envelope or
  // output that is not one -- keeps what the last good snapshot said and only
  // reports why this one failed. Never throws.
  // A reply for a project the user has left never gets here: the runner only
  // emits `finished` when the launch guard still equals its (project) guard.
  function applySnapshot(stdout, exitCode) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var list = Array.isArray(envelope.runs) ? envelope.runs : []
      var asOf = store.isSeq(envelope.as_of_seq) ? envelope.as_of_seq : 0
      var root = store.trimSlashes(store.project)
      var out = []
      var applied = {}
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e === null || typeof e !== "object" || Array.isArray(e)) continue
        var id = typeof e.id === "string" && e.id !== "" ? e.id : ""
        if (id !== "") applied[id] = asOf
        var owner = store.entryProject(e)
        if (owner === null || store.trimSlashes(owner) !== root) continue
        out.push(Runs.normalizeRun({ row: store.rowOf(e), status: e.status }))
      }
      store.asOfSeq = asOf
      store.appliedSeq = applied
```

**`core/stores/RunStore.qml`** — In `applySnapshot()`'s `ok: false` branch, handle StoreBusyError first and clear the coverage on AmMissing. Replace:

```qml
      var err = envelope.error
      var type = err !== null && typeof err === "object" ? err.type : ""
      store.lastError = Runs.errorText(envelope)
      if (type === "AmMissing") {
        store.runs = []
```

with:

```qml
      var err = envelope.error
      var type = err !== null && typeof err === "object" ? err.type : ""
      if (type === "StoreBusyError") {
        store.stale = true
        return
      }
      store.lastError = Runs.errorText(envelope)
      if (type === "AmMissing") {
        store.runs = []
        store.appliedSeq = {}
        store.asOfSeq = 0
```


- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 213 passed, 0 failed`

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 12 passed, 0 failed`

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_real_data.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 9 passed, 0 failed`

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 23 passed, 0 failed`

- [ ] **Step 6: Run the whole gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml tests/core/stores/tst_app_runs.qml tests/ui/tst_runs_real_data.qml
git commit -m "feat(run-store): list every project's runs, keep this project's and record asOfSeq and appliedSeq"
```

---

### Task 2: Watch every project and record `{run, seq}` nudges and the cursor

**Files:**
- Modify: `core/stores/RunStore.qml` (properties, aliases, `stopLive()`, `startWatch()` `:220-237`, `watchLine()` `:246-266`, `projectSwitched()`, `debounceTimer` `:1300-1307`, a new `readState` QtObject)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `isSeq(value)`, `appliedSeq`, `refresh()` (Task 1); `copyMap(map)`, `hasKey(map, key)` (existing).
- Produces: `property int watchCursor`, `property var nudges` (`{runId: int}`), `readonly property alias readRunners: readState.runners` (always `[]` until Task 3), `function recordNudges(entries)`, `function triggerNudges()` (`debounceTimer.onTriggered`), `QtObject { id: readState; property var runners: [] }`. Test helpers: `capturedStore(extra)`, `nudge(store, pairs)`.

- [ ] **Step 1: Update the existing watch-argv and changed-line tests**

**`tests/core/stores/tst_run_store.qml`** — `test_watch_argv_after_first_snapshot`: no project, no run ids. Replace:

```qml
    var noId = { workflow: "orchestrator", repo_dir: rootA }
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
```

with:

```qml
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("b", "done", false)]), 0)
    compare(store.runs.length, 2)
    var w = store.watchProc
    verify(w, "the first good snapshot starts the watch")
    compare(w.objectName, "watchProc")
    compare(w.command.length, 2, "no project, no run ids, no --since-seq")
    compare(w.command[0], "python3")
    compare(w.command[1], "/plugin/core/backend/runs/runs-watch.py")
    compare(w.running, true)
```

**`tests/core/stores/tst_run_store.qml`** — `test_watch_with_no_runs_watches_the_project_alone`. Replace:

```qml
    verify(w, "an empty project is watched too: its first run must show up")
    compare(w.command.length, 3)
    compare(w.command[2], "/home/u/my proj")
```

with:

```qml
    verify(w, "an empty project is watched too: its first run must show up")
    compare(w.command.length, 2)
```

**`tests/core/stores/tst_run_store.qml`** — `test_failed_first_snapshot_does_not_start_watch`. Replace:

```qml
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(store.watchProc.command[3], "a")
```

with:

```qml
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(store.watchProc.command.length, 2)
```

**`tests/core/stores/tst_run_store.qml`** — `test_second_snapshot_does_not_restart_watch`. Replace:

```qml
    compare(w.command.length, 4, "its argv is not rewritten: the helper picks up new runs itself")
```

with:

```qml
    compare(w.command.length, 2, "its argv is not rewritten: the helper watches every run itself")
```

**`tests/core/stores/tst_run_store.qml`** — `test_reactivation_starts_a_new_watch`. Replace:

```qml
    compare(fresh.running, true)
    compare(fresh.command[3], "a")
```

with:

```qml
    compare(fresh.running, true)
    compare(fresh.command.length, 2)
```

**`tests/core/stores/tst_run_store.qml`** — `test_new_project_watch_starts_after_its_snapshot`. Replace:

```qml
    verify(w !== old, "B gets its own watch")
    compare(w.command.length, 4)
    compare(w.command[2], "/home/u/b")
    compare(w.command[3], "b1")
```

with:

```qml
    verify(w !== old, "B gets its own watch")
    compare(w.command.length, 2)
    compare(w.launchProject, "/home/u/b")
```

**`tests/core/stores/tst_run_store.qml`** — `test_project_switch_clears_warning_and_poll`. Replace:

```qml
    compare(store.watchProc.command[2], "/home/u/b")
```

with:

```qml
    compare(store.watchProc.launchProject, "/home/u/b")
```

**`tests/core/stores/tst_run_store.qml`** — `test_changed_line_starts_debounce`. Replace:

```qml
    sendLine(store.watchProc, { changed: ["a"] })
    compare(t.running, true)
    compare(store.snapshotRunner.seq, seq, "a line alone launches no snapshot")
```

with:

```qml
    sendLine(store.watchProc, { changed: [{ run: "a", seq: 990 }] })
    compare(t.running, true)
    compare(store.snapshotRunner.seq, seq, "a line alone launches no snapshot")
```

**`tests/core/stores/tst_run_store.qml`** — `test_burst_coalesces_to_one_snapshot`: a burst for runs the list did not name. Replace:

```qml
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    sendLine(store.watchProc, { changed: ["b"] })
    sendLine(store.watchProc, '{"changed": ["a", "c"]}')
```

with:

```qml
    var seq = store.snapshotRunner.seq
    // synthetic: runs-watch.py changed lines for runs the list did not name.
    sendLine(store.watchProc, { changed: [{ run: "b", seq: 990 }] })
    sendLine(store.watchProc, { changed: [{ run: "c", seq: 991 }] })
    sendLine(store.watchProc, '{"changed": [{"run": "b", "seq": 992}, {"run": "c", "seq": 993}]}')
```

**`tests/core/stores/tst_run_store.qml`** — `test_hello_starts_nothing`. Replace:

```qml
    verify(!store.watchProc.envelope, "a hello is not an envelope")
    sendLine(store.watchProc, { changed: ["a"] })
```

with:

```qml
    verify(!store.watchProc.envelope, "a hello is not an envelope")
    sendLine(store.watchProc, { changed: [{ run: "a", seq: 990 }] })
```

**`tests/core/stores/tst_run_store.qml`** — `test_hello_beside_changed_or_ok_false_keeps_its_meaning`. Replace:

```qml
    var changed = helloLine("schema_2")
    changed.changed = ["a"]
```

with:

```qml
    var changed = helloLine("schema_2")
    changed.changed = [{ run: "a", seq: 990 }]
```

**`tests/core/stores/tst_run_store.qml`** — `test_hello_mid_burst_keeps_the_debounce`: the burst names a run the list did not. Replace:

```qml
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    sendLine(store.watchProc, helloLine("schema_2"))
```

with:

```qml
    var seq = store.snapshotRunner.seq
    // synthetic: a runs-watch.py changed line for a run the list did not name.
    sendLine(store.watchProc, { changed: [{ run: "z", seq: 990 }] })
    compare(store.debounceTimer.running, true)
    sendLine(store.watchProc, helloLine("schema_2"))
```

**`tests/core/stores/tst_run_store.qml`** — `test_deactivate_kills_watch_and_timers`: the nudges go too. Replace:

```qml
    var w = store.watchProc
    sendLine(w, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    compare(store.livenessTimer.running, true)
    store.active = false
    compare(w.running, false, "the watch is killed")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "the pending refresh is dropped")
```

with:

```qml
    var w = store.watchProc
    sendLine(w, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, true)
    compare(store.livenessTimer.running, true)
    store.active = false
    compare(w.running, false, "the watch is killed")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "the pending refresh is dropped")
    compare(Object.keys(store.nudges).length, 0, "and its nudges")
```

**`tests/core/stores/tst_run_store.qml`** — `test_project_switch_stops_watch_and_clears_runs`. Replace:

```qml
    var old = store.watchProc
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    store.project = rootB
```

with:

```qml
    var old = store.watchProc
    sendLine(old, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, true)
    store.project = rootB
```

**`tests/core/stores/tst_run_store.qml`** — `test_old_watch_lines_ignored_after_switch`. Replace:

```qml
    store.project = rootB
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "the old watch's late line is dropped")
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true, rootB)]), 0)
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "even once B's watch runs")
    sendLine(store.watchProc, { changed: ["b1"] })
```

with:

```qml
    store.project = rootB
    sendLine(old, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, false, "the old watch's late line is dropped")
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true, rootB)]), 0)
    sendLine(old, { changed: [{ run: "a", seq: 991 }] })
    compare(store.debounceTimer.running, false, "even once B's watch runs")
    compare(Object.keys(store.nudges).length, 0, "nothing was recorded")
    sendLine(store.watchProc, { changed: [{ run: "b1", seq: 992 }] })
```

**`tests/core/stores/tst_run_store.qml`** — `test_killed_watch_lines_ignored_after_deactivation`. Replace:

```qml
    store.active = false
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "a killed watch's late line is dropped")
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc !== old)
    sendLine(old, { changed: ["a"] })
```

with:

```qml
    store.active = false
    sendLine(old, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, false, "a killed watch's late line is dropped")
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc !== old)
    sendLine(old, { changed: [{ run: "a", seq: 991 }] })
```

**`tests/core/stores/tst_run_store.qml`** — `test_watch_exit_zero_only_clears_watching`. Replace:

```qml
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    sendLine(store.watchProc, { changed: ["a"] })
    endWatch(store.watchProc, "", 0)
```

with:

```qml
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    sendLine(store.watchProc, { changed: [{ run: "a", seq: 990 }] })
    endWatch(store.watchProc, "", 0)
```


- [ ] **Step 2: Append the new nudge tests**

In `tests/core/stores/tst_run_store.qml`, insert this block just before the file's final closing `}`:

```qml
  // ---- nudges (4.1.3)

  // An active store on the captured runs' project whose first list snapshot
  // was capturedList(extra): both captured runs are covered at 989 and the
  // watch runs.
  function capturedStore(extra) {
    var store = activeStore(tc.capRoot); if (!store) return null
    reply(store.snapshotRunner.current, capturedList(extra), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  // synthetic: one runs-watch.py changed line, {"changed": [{run, seq}, ...]},
  // for pairs [run, seq, run, seq, ...].
  function nudge(store, pairs) {
    var list = []
    for (var i = 0; i < pairs.length; i += 2) list.push({ run: pairs[i], seq: pairs[i + 1] })
    sendLine(store.watchProc, { changed: list })
  }

  function test_invalid_changed_entries_are_ignored() {
    var store = capturedStore(); if (!store) return
    // synthetic: changed entries runs-watch.py never prints.
    var lines = ['{"changed": ["' + tc.doneRun + '"]}', '{"changed": [{"run": "x", "seq": 0}]}',
                 '{"changed": [{"run": "x", "seq": -3}]}', '{"changed": [{"run": "x", "seq": 2.5}]}',
                 '{"changed": [{"run": "x", "seq": "990"}]}', '{"changed": [{"run": "", "seq": 990}]}',
                 '{"changed": [{"run": 7, "seq": 990}]}', '{"changed": [{"seq": 990}]}',
                 '{"changed": [null, [], 3]}', '{"changed": []}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.debounceTimer.running, false, lines[i])
      compare(Object.keys(store.nudges).length, 0, lines[i])
    }
    sendLine(store.watchProc, '{"changed": ["x", {"run": "' + tc.doneRun + '", "seq": 990}, {"run": "y", "seq": 0}]}')
    compare(store.debounceTimer.running, true, "one valid entry is enough")
    compare(Object.keys(store.nudges).join(","), tc.doneRun)
    compare(store.nudges[tc.doneRun], 990)
  }

  function test_nudges_keep_the_highest_seq_per_run() {
    var store = capturedStore(); if (!store) return
    nudge(store, [tc.doneRun, 995])
    nudge(store, [tc.doneRun, 993, tc.startedRun, 990])
    nudge(store, [tc.doneRun, 997])
    compare(store.nudges[tc.doneRun], 997)
    compare(store.nudges[tc.startedRun], 990)
    compare(Object.keys(store.nudges).join(","), tc.doneRun + "," + tc.startedRun, "in first-nudge order")
  }

  function test_a_cursor_line_sets_the_watch_cursor() {
    var store = capturedStore(); if (!store) return
    compare(store.watchCursor, 0)
    // synthetic: runs-watch.py's cursor lines.
    sendLine(store.watchProc, { cursor: 1005 })
    compare(store.watchCursor, 1005)
    var bad = ['{"cursor": -1}', '{"cursor": 2.5}', '{"cursor": "1006"}', '{"cursor": null}', '{"cursor": true}']
    for (var i = 0; i < bad.length; i++) {
      sendLine(store.watchProc, bad[i])
      compare(store.watchCursor, 1005, bad[i])
    }
    sendLine(store.watchProc, { cursor: 0 })
    compare(store.watchCursor, 0, "0 is a cursor too")
    compare(store.debounceTimer.running, false, "a cursor is not a change")
  }

  function test_a_nudge_no_newer_than_the_list_launches_nothing() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.startedRun, 989, tc.doneRun, 900])
    compare(store.debounceTimer.running, true, "recorded: the trigger compares")
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.readRunners.length, 0, "no run read")
    compare(Object.keys(store.nudges).length, 0, "the nudges were taken")
  }

  function test_a_nudge_for_an_unknown_run_costs_one_list_snapshot() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    // synthetic: a run am started after the list, beside a held run.
    nudge(store, [tc.doneRun, 1005, "20261008T150000Z-0a1b2c3d", 1006])
    nudge(store, ["20261008T150000Z-0a1b2c3d", 1007])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "exactly one list snapshot")
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
    compare(store.readRunners.length, 0, "and no run read in that trigger")
    compare(Object.keys(store.nudges).length, 0)
  }

  function test_a_nudge_for_another_projects_run_launches_nothing() {
    // synthetic: another project's run listed beside the captures.
    var store = capturedStore([entry("other1", "started", true, "/home/u/elsewhere")]); if (!store) return
    compare(store.appliedSeq.other1, 989)
    var seq = store.snapshotRunner.seq
    nudge(store, ["other1", 1200])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.readRunners.length, 0, "no run read")
  }

  function test_a_project_switch_forgets_the_nudges_but_keeps_the_cursor() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.project = rootB
    compare(Object.keys(store.nudges).length, 0)
    compare(store.watchCursor, 1005, "the cursor is not per project")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 205 passed, 15 failed`, the failures being `test_a_cursor_line_sets_the_watch_cursor`, `test_a_nudge_for_an_unknown_run_costs_one_list_snapshot`, `test_a_nudge_for_another_projects_run_launches_nothing` ("no list snapshot"), `test_a_nudge_no_newer_than_the_list_launches_nothing` ("no list snapshot"), `test_a_project_switch_forgets_the_nudges_but_keeps_the_cursor`, `test_deactivate_kills_watch_and_timers`, `test_failed_first_snapshot_does_not_start_watch`, `test_invalid_changed_entries_are_ignored`, `test_new_project_watch_starts_after_its_snapshot`, `test_nudges_keep_the_highest_seq_per_run`, `test_old_watch_lines_ignored_after_switch`, `test_reactivation_starts_a_new_watch`, `test_second_snapshot_does_not_restart_watch`, `test_watch_argv_after_first_snapshot`, `test_watch_with_no_runs_watches_the_project_alone`.

- [ ] **Step 4: Implement the watch launch, nudge recording, the cursor and the trigger**

`triggerNudges()` here handles only the "unknown run → one list snapshot" rule; Task 3 adds the run reads. A nudge newer than its covered seq for a held run launches nothing until then.

**`core/stores/RunStore.qml`** — Add `watchCursor` and `nudges` below `appliedSeq`. Replace:

```qml
  property int asOfSeq: 0
  property var appliedSeq: ({})
```

with:

```qml
  property int asOfSeq: 0
  property var appliedSeq: ({})
  // The current watch's last {"cursor": C} (0 = none), held in memory only.
  property int watchCursor: 0
  // {runId: seq}: the highest changed seq per run since the last debounce
  // trigger. Replaced, never changed in place.
  property var nudges: ({})
```

**`core/stores/RunStore.qml`** — Add the `readRunners` alias below the `snapshotRunner` alias. Replace:

```qml
  readonly property alias snapshotRunner: snapshotRunner
```

with:

```qml
  readonly property alias snapshotRunner: snapshotRunner
  readonly property alias readRunners: readState.runners  // in-flight run reads, oldest first
```

**`core/stores/RunStore.qml`** — In `stopLive()`, empty the nudges after `debounceTimer.stop()`. Replace:

```qml
    store.stopWatch()
    debounceTimer.stop()
    store.stopPoll()
    staleTimer.stop()
```

with:

```qml
    store.stopWatch()
    debounceTimer.stop()
    store.nudges = {}
    store.stopPoll()
    staleTimer.stop()
```

**`core/stores/RunStore.qml`** — Replace `startWatch()`'s comment and argv (`RunStore.qml:220-233`). Replace:

```qml
  // runs-watch.py for this project and the runs the snapshot just listed, in
  // its order. Long-lived, so a plain Process rather than the HelperRunner.
  // It starts with am's schema and version unknown until its own hello.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    store.forgetHello()
    var ids = []
    for (var i = 0; i < store.runs.length; i++) {
      var id = store.runs[i].id
      if (typeof id === "string" && id !== "") ids.push(id)
    }
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq, launchProject: store.project })
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py", store.project].concat(ids)
```

with:

```qml
  // runs-watch.py with no argument: every project's nudges, from now.
  // Long-lived, so a plain Process rather than the HelperRunner. It starts
  // with am's schema and version unknown until its own hello.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    store.forgetHello()
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq, launchProject: store.project })
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py"]
```

**`core/stores/RunStore.qml`** — Replace `watchLine()` (`RunStore.qml:246-266`) and add `recordNudges()` and `triggerNudges()` after it. Replace:

```qml
  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V}}, sets amSchema to N (an integer of 1 or
  // more, else 0) and amVersion to V (a string, else "") and starts nothing.
  // Anything else -- blank, not JSON, not an object, a hello that is not an
  // object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) debounceTimer.restart()
    else if (value.ok === false) proc.envelope = value
    else if (value.hello !== null && typeof value.hello === "object" && !Array.isArray(value.hello)) {
      var schema = value.hello.schema
      store.amSchema = typeof schema === "number" && Number.isInteger(schema) && schema >= 1 ? schema : 0
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
    }
  }
```

with:

```qml
  // One stdout line of the watch, a nudge source never folded into state.
  // {"changed": [{run, seq}, ...]} records each nudge (recordNudges).
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V}}, sets amSchema to N (an integer of 1 or
  // more, else 0) and amVersion to V (a string, else "") and starts nothing.
  // {"cursor": C} sets watchCursor when C is an integer of 0 or more.
  // Anything else -- blank, not JSON, not an object, a hello that is not an
  // object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) store.recordNudges(value.changed)
    else if (value.ok === false) proc.envelope = value
    else if (value.hello !== null && typeof value.hello === "object" && !Array.isArray(value.hello)) {
      var schema = value.hello.schema
      store.amSchema = typeof schema === "number" && Number.isInteger(schema) && schema >= 1 ? schema : 0
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
    } else if (store.hasKey(value, "cursor")) {
      if (store.isSeq(value.cursor)) store.watchCursor = value.cursor
    }
  }

  // A changed line's entries: each {run: non-empty string, seq: integer of 1
  // or more} raises nudges[run] to seq; every other entry is ignored. The
  // debounce restarts when at least one entry was recorded.
  function recordNudges(entries) {
    var next = null
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e === null || typeof e !== "object" || Array.isArray(e)) continue
      if (typeof e.run !== "string" || e.run === "" || !store.isSeq(e.seq) || e.seq < 1) continue
      if (next === null) next = store.copyMap(store.nudges)
      if (!store.hasKey(next, e.run) || next[e.run] < e.seq) next[e.run] = e.seq
    }
    if (next === null) return
    store.nudges = next
    debounceTimer.restart()
  }

  // The debounce fired: the nudges are taken. A nudge for a run appliedSeq
  // does not know costs one list snapshot, which covers every run. A nudge no
  // newer than appliedSeq[run], or for another project's listed run, is
  // ignored.
  function triggerNudges() {
    var taken = store.nudges
    store.nudges = {}
    var ids = Object.keys(taken)
    for (var i = 0; i < ids.length; i++) {
      if (!store.hasKey(store.appliedSeq, ids[i])) {
        store.refresh()
        return
      }
    }
  }
```

**`core/stores/RunStore.qml`** — In `projectSwitched()`, empty the nudges too. Replace:

```qml
    debounceTimer.stop()
    store.appliedSeq = {}
    store.asOfSeq = 0
```

with:

```qml
    debounceTimer.stop()
    store.nudges = {}
    store.appliedSeq = {}
    store.asOfSeq = 0
```

**`core/stores/RunStore.qml`** — `debounceTimer` takes the nudges instead of refreshing (`RunStore.qml:1300-1307`). Replace:

```qml
  // A burst of changed lines costs one snapshot.
  Timer {
    id: debounceTimer
    objectName: "debounceTimer"
    interval: 250
    repeat: false
    onTriggered: store.refresh()
  }
```

with:

```qml
  // A burst of changed lines is taken in one go (triggerNudges).
  Timer {
    id: debounceTimer
    objectName: "debounceTimer"
    interval: 250
    repeat: false
    onTriggered: store.triggerNudges()
  }
```

**`core/stores/RunStore.qml`** — Add the `readState` QtObject above the `toastState` one. Replace:

```qml
  // The toast keys only grow
```

with:

```qml
  // The run reads' own state; kept apart so consumers cannot write it.
  // `runners` are the reads in flight, oldest first.
  QtObject {
    id: readState
    property var runners: []
  }

  // The toast keys only grow
```


- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 220 passed, 0 failed`

- [ ] **Step 6: Run the whole gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): watch every project and record {run, seq} nudges and the cursor"
```

---

### Task 3: One run read per newer nudge of a held run

**Files:**
- Modify: `core/stores/RunStore.qml` (`triggerNudges()`, `projectSwitched()`, `applySnapshot()`, a new `// ---- run reads` section above `// ---- run controls (S2 4.1)`, `readState`, a new `readC` Component above `watchC`)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `appliedSeq`, `isSeq`, `entryProject`, `trimSlashes` (Task 1); `nudges`, `readState.runners`, `triggerNudges()` (Task 2); `runById(id)`, `rowOf(e)`, `copyMap`, `hasKey`, `parseEnvelope`, `settleAfterSnapshot()`, `logsAfterSnapshot()`, `raiseAlerts(alerts)`, `Runs.newAlerts(prev, next)`, `Runs.normalizeRun({row, status})` (existing).
- Produces: `function readRun(runId, seq)`, `function dropReads()`, `function readReplied(runner, stdout)`, `function applyRunRead(runId, envelope)`; `readState.latest` (`{runId: runner}`), `readState.rows` (`{runId: am runs row}`); each read runner has `runId` (string), `nudgeSeq` (int), `madeFor` (string). Test helpers: `readCmd`, `runReply(run, name)`, `readOf(store, run, seq) -> Process|null`.

- [ ] **Step 1: Append the run-read tests**

In `tests/core/stores/tst_run_store.qml`, insert this block just before the file's final closing `}`:

```qml
  // ---- run reads (4.1.3)

  property string readCmd: "python3|/plugin/core/backend/runs/runs-snapshot.py|--run|"

  // runs-snapshot.py --run RUN's reply: `name`'s `am status` data with its own
  // as_of_seq and store_id, under `run`.
  function runReply(run, name) {
    var data = F.load(name).data
    return JSON.stringify({ ok: true, run: run, as_of_seq: data.as_of_seq, store_id: data.store_id,
                            status: data, data_dir: "/d" }) + "\n"
  }

  // The store's run read of `run` in flight after a nudge at `seq` and the
  // debounce: its Process.
  function readOf(store, run, seq) {
    nudge(store, [run, seq])
    fire(store.debounceTimer)
    var list = store.readRunners
    return list.length > 0 ? list[list.length - 1].current : null
  }

  function test_a_nudge_for_a_held_run_reads_only_that_run() {
    var store = capturedStore(); if (!store) return
    var before = store.runs
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.doneRun, 1005])
    compare(store.readRunners.length, 0, "nothing before the debounce")
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.readRunners.length, 1)
    var proc = store.readRunners[0].current
    compare(argv(proc), tc.readCmd + tc.doneRun)
    compare(proc.command.length, 4)
    compare(proc.running, true)
    reply(proc, runReply(tc.doneRun, "status-done.json"), 0)
    verify(store.runs !== before, "runs is a new array")
    compare(store.runs.length, 2)
    verify(store.runs[0] === before[0], "the other run is the same object")
    verify(store.runs[1] !== before[1], "the read run was rebuilt in its place")
    compare(store.runs[1].id, tc.doneRun)
    compare(store.runs[1].status, "done")
    compare(store.runs[1].project.repo_dir, tc.capRoot, "from its remembered am runs row")
    compare(store.appliedSeq[tc.doneRun], 1005)
    compare(store.appliedSeq[tc.startedRun], 989)
    compare(store.asOfSeq, 989, "a run read leaves asOfSeq")
    compare(store.readRunners.length, 0, "the runner is gone")
    nudge(store, [tc.doneRun, 1005])
    fire(store.debounceTimer)
    compare(store.readRunners.length, 0, "the read covered 1005")
  }

  function test_several_nudges_in_a_window_cost_one_read() {
    var store = capturedStore(); if (!store) return
    nudge(store, [tc.doneRun, 1000])
    nudge(store, [tc.doneRun, 1005])
    fire(store.debounceTimer)
    compare(store.readRunners.length, 1)
    compare(store.readRunners[0].nudgeSeq, 1005, "at the highest seq")
  }

  function test_a_newer_read_of_a_run_supersedes_the_older() {
    var store = capturedStore(); if (!store) return
    var older = readOf(store, tc.doneRun, 1000)
    var newer = readOf(store, tc.doneRun, 1005)
    compare(store.readRunners.length, 2, "both in flight")
    compare(older.running, true, "the older one is not stopped")
    var before = store.runs[1]
    // synthetic: status-escalated.json's data under the done run's id.
    reply(older, runReply(tc.doneRun, "status-escalated.json"), 0)
    verify(store.runs[1] === before, "the superseded reply changes nothing")
    compare(store.readRunners.length, 1)
    reply(newer, runReply(tc.doneRun, "status-done.json"), 0)
    verify(store.runs[1] !== before)
    compare(store.runs[1].status, "done")
  }

  function test_a_read_older_than_the_list_changes_nothing() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    store.refresh()
    // synthetic: a later list at as_of_seq 1100 lands before the read.
    reply(store.snapshotRunner.current, capturedList([], 1100), 0)
    var before = store.runs[1]
    // synthetic: status-escalated.json's data (as_of_seq 1005) under the done run's id.
    reply(proc, runReply(tc.doneRun, "status-escalated.json"), 0)
    verify(store.runs[1] === before)
    compare(store.runs[1].status, "done")
    compare(store.appliedSeq[tc.doneRun], 1100)
  }

  function test_a_read_reply_that_does_not_fit_changes_nothing() {
    var store = capturedStore(); if (!store) return
    var good = JSON.parse(runReply(tc.doneRun, "status-escalated.json"))
    // synthetic: status-escalated.json's run read reply, each with one key broken.
    var breaks = [["run", tc.startedRun], ["run", undefined], ["status", null], ["status", []],
                  ["as_of_seq", -1], ["as_of_seq", "1005"], ["as_of_seq", undefined]]
    for (var i = 0; i < breaks.length; i++) {
      var label = breaks[i][0] + " " + JSON.stringify(breaks[i][1])
      var proc = readOf(store, tc.doneRun, 1001 + i)
      var before = store.runs[1]
      var value = JSON.parse(JSON.stringify(good))
      if (breaks[i][1] === undefined) delete value[breaks[i][0]]
      else value[breaks[i][0]] = breaks[i][1]
      reply(proc, JSON.stringify(value) + "\n", 0)
      verify(store.runs[1] === before, label)
      compare(store.appliedSeq[tc.doneRun], 989, label)
      compare(store.readRunners.length, 0, label)
    }
  }

  function test_other_read_failures_change_nothing() {
    var store = capturedStore(); if (!store) return
    // synthetic: helper failures runs-snapshot.py --run prints, then output that is not an envelope.
    var replies = ['{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}',
                   '{"ok": false, "error": {"type": "SchemaMismatch", "message": "the plugin needs the newer am"}}',
                   '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}',
                   '{"ok": false}', "Traceback (most recent call last):", ""]
    for (var i = 0; i < replies.length; i++) {
      var label = JSON.stringify(replies[i])
      var proc = readOf(store, tc.doneRun, 1001 + i)
      var before = store.runs[1]
      var seq = store.snapshotRunner.seq
      reply(proc, replies[i], 1)
      verify(store.runs[1] === before, label)
      compare(store.amStatus, "ok", label)
      compare(store.lastError, "", label)
      compare(store.stale, false, label)
      compare(store.snapshotRunner.seq, seq, label + ": no list snapshot")
      compare(Object.keys(store.nudges).length, 0, label + ": nothing to retry")
    }
  }

  function test_two_runs_nudged_together_are_read_in_parallel() {
    var store = capturedStore(); if (!store) return
    nudge(store, [tc.doneRun, 1005, tc.startedRun, 1000])
    fire(store.debounceTimer)
    compare(store.readRunners.length, 2)
    var first = store.readRunners[0].current
    var second = store.readRunners[1].current
    compare(argv(first), tc.readCmd + tc.doneRun, "in nudge order")
    compare(argv(second), tc.readCmd + tc.startedRun)
    compare(first.running, true, "neither stops the other")
    compare(second.running, true)
    // synthetic: status-escalated.json's data under the started run's id.
    reply(second, runReply(tc.startedRun, "status-escalated.json"), 0)
    reply(first, runReply(tc.doneRun, "status-done.json"), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.runs[1].status, "done")
    compare(store.appliedSeq[tc.startedRun], 1005)
    compare(store.appliedSeq[tc.doneRun], 1005)
  }

  function test_a_read_that_escalates_a_run_raises_one_toast() {
    var store = capturedStore(); if (!store) return
    compare(store.alertsArmed, true)
    // synthetic: status-escalated.json's data under the started run's id.
    reply(readOf(store, tc.startedRun, 1005), runReply(tc.startedRun, "status-escalated.json"), 0)
    compare(store.toasts.length, 1)
    compare(store.toasts[0].id, tc.startedRun)
    compare(store.toasts[0].state, "escalated")
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the stale clock restarts")
    reply(readOf(store, tc.startedRun, 1006), runReply(tc.startedRun, "status-escalated.json"), 0)
    compare(store.toasts.length, 1, "still escalated: no second toast")
  }

  function test_a_project_switch_drops_the_reads_in_flight() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    var old = store.watchProc
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true, rootB)], 1200), 0)
    reply(proc, runReply(tc.doneRun, "status-done.json"), 0)
    compare(ids(store.runs), "b1", "A's read changes nothing")
    compare(store.appliedSeq[tc.doneRun], undefined)
    compare(store.readRunners.length, 0, "its runner still goes")
    sendLine(old, { changed: [{ run: "b1", seq: 1300 }] })
    compare(store.debounceTimer.running, false, "A's watch lines change nothing")
    compare(Object.keys(store.nudges).length, 0)
  }

  // Review Focus 1: A -> B -> A before the old read lands.
  function test_a_read_from_before_a_return_to_the_project_changes_nothing() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    store.project = rootB
    store.project = tc.capRoot
    reply(store.snapshotRunner.current, capturedList(), 0)
    var before = store.runs[1]
    // synthetic: status-escalated.json's data under the done run's id.
    reply(proc, runReply(tc.doneRun, "status-escalated.json"), 0)
    verify(store.runs[1] === before)
    compare(store.appliedSeq[tc.doneRun], 989)
  }

  // Review Focus 2.
  function test_a_read_that_moves_the_selected_attempt_fetches_its_logs() {
    var store = capturedStore(); if (!store) return
    store.selectedRunId = tc.startedRun
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var seq = store.logsRunner.seq
    var proc = readOf(store, tc.startedRun, 990)
    // synthetic: status-started.json's data with its open attempt (explore 1) ok.
    var data = F.load("status-started.json").data
    data.stories[1].subtasks[1].phases[1].attempts[0].status = "ok"
    reply(proc, JSON.stringify({ ok: true, run: tc.startedRun, as_of_seq: 990, store_id: data.store_id, status: data, data_dir: "/d" }) + "\n", 0)
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches the logs again")
    compare(argv(store.logsRunner.current), "python3|/plugin/core/backend/runs/runs-logs.py|" + tc.capRoot + "|" + tc.startedRun + "|" + tc.openCard + "|explore|1")
  }

  // Review Focus 3.
  function test_a_read_that_moves_the_run_settles_its_pending_request() {
    var store = capturedStore(); if (!store) return
    compare(store.control("cancel", tc.startedRun), true)
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.pending[tc.startedRun], "cancel")
    // synthetic: status-escalated.json's data under the started run's id.
    reply(readOf(store, tc.startedRun, 1005), runReply(tc.startedRun, "status-escalated.json"), 0)
    compare(store.pending[tc.startedRun], undefined, "the read settled it")
  }

  // Review Focus 4.
  function test_a_read_landing_after_the_panel_closed_is_applied_quietly() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.startedRun, 1005)
    store.active = false
    // synthetic: status-escalated.json's data under the started run's id.
    reply(proc, runReply(tc.startedRun, "status-escalated.json"), 0)
    compare(store.runs[0].status, "escalated", "applied, as a list snapshot is")
    compare(store.toasts.length, 0, "no toast while closed")
    compare(store.staleTimer.running, false, "no stale clock while closed")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 220 passed, 13 failed` — every test of the new section: `test_a_nudge_for_a_held_run_reads_only_that_run`, `test_several_nudges_in_a_window_cost_one_read` and `test_two_runs_nudged_together_are_read_in_parallel` ("Compared values are not the same"), `test_a_newer_read_of_a_run_supersedes_the_older` ("both in flight"), and the other nine with `Value is null and could not be converted to an object` (no read runner exists, so `readOf` returns null).

- [ ] **Step 3: Implement the run reads**

**`core/stores/RunStore.qml`** — `triggerNudges()` launches a run read for each newer nudge of a run it holds. Replace:

```qml
  // The debounce fired: the nudges are taken. A nudge for a run appliedSeq
  // does not know costs one list snapshot, which covers every run. A nudge no
  // newer than appliedSeq[run], or for another project's listed run, is
  // ignored.
  function triggerNudges() {
    var taken = store.nudges
    store.nudges = {}
    var ids = Object.keys(taken)
    for (var i = 0; i < ids.length; i++) {
      if (!store.hasKey(store.appliedSeq, ids[i])) {
        store.refresh()
        return
      }
    }
  }
```

with:

```qml
  // The debounce fired: the nudges are taken. A nudge for a run appliedSeq
  // does not know costs one list snapshot, which covers every run, and no run
  // read. Otherwise each nudge newer than appliedSeq[run] for a run in `runs`
  // costs one run read, in nudge order. A nudge no newer than
  // appliedSeq[run], or for another project's listed run, is ignored.
  function triggerNudges() {
    var taken = store.nudges
    store.nudges = {}
    var ids = Object.keys(taken)
    var reads = []
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (!store.hasKey(store.appliedSeq, id)) {
        store.refresh()
        return
      }
      if (taken[id] > store.appliedSeq[id] && store.runById(id) !== null) reads.push(id)
    }
    for (var j = 0; j < reads.length; j++) store.readRun(reads[j], taken[reads[j]])
  }
```

**`core/stores/RunStore.qml`** — In `projectSwitched()`, drop the reads in flight. Replace:

```qml
    store.nudges = {}
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.stopPoll()
```

with:

```qml
    store.nudges = {}
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.dropReads()
    store.stopPoll()
```

**`core/stores/RunStore.qml`** — `applySnapshot()` remembers each kept entry's `am runs` row. Replace:

```qml
      var out = []
      var applied = {}
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e === null || typeof e !== "object" || Array.isArray(e)) continue
        var id = typeof e.id === "string" && e.id !== "" ? e.id : ""
        if (id !== "") applied[id] = asOf
        var owner = store.entryProject(e)
        if (owner === null || store.trimSlashes(owner) !== root) continue
        out.push(Runs.normalizeRun({ row: store.rowOf(e), status: e.status }))
      }
      store.asOfSeq = asOf
      store.appliedSeq = applied
```

with:

```qml
      var out = []
      var rows = {}
      var applied = {}
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e === null || typeof e !== "object" || Array.isArray(e)) continue
        var id = typeof e.id === "string" && e.id !== "" ? e.id : ""
        if (id !== "") applied[id] = asOf
        var owner = store.entryProject(e)
        if (owner === null || store.trimSlashes(owner) !== root) continue
        var row = store.rowOf(e)
        if (id !== "") rows[id] = row
        out.push(Runs.normalizeRun({ row: row, status: e.status }))
      }
      store.asOfSeq = asOf
      store.appliedSeq = applied
      readState.rows = rows
```

**`core/stores/RunStore.qml`** — Add the run-read functions above `// ---- run controls (S2 4.1)`. Replace:

```qml
  // ---- run controls (S2 4.1)
```

with:

```qml
  // ---- run reads

  // One runs-snapshot.py --run RUN on its own runner, for a nudge at seq. It
  // supersedes an older read of the same run still in flight.
  function readRun(runId, seq) {
    if (store.project === "") return
    var runner = readC.createObject(store, { runId: runId, nudgeSeq: seq, madeFor: store.project })
    var latest = store.copyMap(readState.latest)
    latest[runId] = runner
    readState.latest = latest
    readState.runners = readState.runners.concat([runner])
    runner.run(["--run", runId])
  }

  // Every run read in flight is dropped: its reply changes nothing.
  function dropReads() {
    readState.latest = {}
  }

  // One run read's reply. The runner leaves readRunners and is destroyed. A
  // reply that is not its run's latest read, or for a project the user has
  // left, changes nothing; ok:true goes to applyRunRead; anything else changes
  // nothing.
  function readReplied(runner, stdout) {
    var runId = runner.runId
    var latest = store.hasKey(readState.latest, runId) && readState.latest[runId] === runner
    var current = latest && runner.madeFor === store.project
    readState.runners = readState.runners.filter(function(r) { return r !== runner })
    if (latest) {
      var next = store.copyMap(readState.latest)
      delete next[runId]
      readState.latest = next
    }
    runner.destroy()
    if (!current) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) store.applyRunRead(runId, envelope)
  }

  // A good run read, {run, as_of_seq, status}: for the run asked, with a
  // non-negative integer as_of_seq and an object status, still in `runs` and
  // not covered by a newer snapshot, the run at its position is rebuilt from
  // its remembered `am runs` row and the reply's status (the other runs stay
  // the same objects) and appliedSeq[run] becomes as_of_seq. Then alerts,
  // settling, logs and the stale clock as after a list snapshot; asOfSeq,
  // amStatus and lastError are left alone. Anything else changes nothing.
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
    var next = store.runs.slice()
    next[index] = Runs.normalizeRun({ row: row, status: status })
    // Compared before the runs are replaced; raised below only while open.
    var alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, next)
    store.runs = next
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

  // ---- run controls (S2 4.1)
```

**`core/stores/RunStore.qml`** — `readState` gains `latest` and `rows`. Replace:

```qml
  // The run reads' own state; kept apart so consumers cannot write it.
  // `runners` are the reads in flight, oldest first.
  QtObject {
    id: readState
    property var runners: []
  }
```

with:

```qml
  // The run reads' own state; kept apart so consumers cannot write it.
  // `runners` are the reads in flight, oldest first; `latest` is {runId:
  // runner}, the read whose reply counts; `rows` is {runId: am runs row} of
  // the runs the last good list snapshot kept, which a run read rebuilds from.
  QtObject {
    id: readState
    property var runners: []
    property var latest: ({})
    property var rows: ({})
  }
```

**`core/stores/RunStore.qml`** — Add the `readC` component above `// One Process per watch launch`. Replace:

```qml
  // One Process per watch launch
```

with:

```qml
  // One HelperRunner per run read, so reads of different runs run in
  // parallel. Guard "": readReplied checks the project and the latest read
  // itself, so every exit lands there and the runner always goes.
  Component {
    id: readC

    HelperRunner {
      id: rr
      property string runId: ""
      property int nudgeSeq: 0        // the nudge seq it was launched for
      property string madeFor: ""     // the project the read was made in
      script: store.backendDir + "runs/runs-snapshot.py"
      guard: ""
      onFinished: function(stdout, exitCode) { store.readReplied(rr, stdout) }
    }
  }

  // One Process per watch launch
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 233 passed, 0 failed`

- [ ] **Step 5: Run the whole gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): refresh only the nudged run with runs-snapshot.py --run when it is newer than its snapshot"
```

---

### Task 4: Run read refusals: UnknownRunError relists, StoreBusyError retries

**Files:**
- Modify: `core/stores/RunStore.qml` (`readReplied()`, a new `keepNudge()` after it)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `readReplied(runner, stdout)`, `readRunners`, `nudges`, `refresh()` (Tasks 1-3).
- Produces: `function keepNudge(runId, seq)` — raises `nudges[runId]` to `seq`, never lowers it, never touches the debounce.

- [ ] **Step 1: Append the refusal tests**

In `tests/core/stores/tst_run_store.qml`, insert this block just before the file's final closing `}`:

```qml
  // ---- run read refusals (4.1.3)

  function test_a_read_of_a_run_am_does_not_know_relists() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    var seq = store.snapshotRunner.seq
    // synthetic: am's UnknownRunError envelope, which runs-snapshot.py --run re-emits unchanged.
    reply(proc, '{"error": {"message": "unknown run", "type": "UnknownRunError"}, "ok": false}\n', 1)
    compare(store.toasts.length, 0, "no toast")
    compare(store.lastError, "")
    compare(store.amStatus, "ok")
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun, "the run stays until the next list")
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot")
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py")
    // synthetic: runs.json's list without the done run, at a later as_of_seq.
    var data = F.load("runs.json").data
    var only = data.runs.slice(0, 1)
    only[0].status = F.load("status-started.json").data
    reply(store.snapshotRunner.current, JSON.stringify({ ok: true, as_of_seq: 1010, store_id: data.store_id, runs: only, data_dir: "/d" }) + "\n", 0)
    compare(ids(store.runs), tc.startedRun, "it drops when am no longer lists it")
    compare(store.appliedSeq[tc.doneRun], undefined)
    compare(store.lastError, "")
  }

  function test_a_busy_store_on_a_read_keeps_the_run_and_retries_it() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    var before = store.runs[1]
    var seq = store.snapshotRunner.seq
    // synthetic: am's StoreBusyError envelope, which runs-snapshot.py --run re-emits unchanged.
    reply(proc, '{"error": {"message": "the am store is busy; try again", "type": "StoreBusyError"}, "ok": false}\n', 1)
    verify(store.runs[1] === before, "the last good run stays")
    compare(store.stale, true)
    compare(store.toasts.length, 0)
    compare(store.lastError, "")
    compare(store.amStatus, "ok")
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.nudges[tc.doneRun], 1005, "the nudge is put back")
    compare(store.debounceTimer.running, false, "without restarting the debounce")
    nudge(store, [tc.startedRun, 1000])
    fire(store.debounceTimer)
    compare(store.readRunners.length, 2, "the next trigger retries it")
    compare(argv(store.readRunners[0].current), tc.readCmd + tc.doneRun)
    compare(argv(store.readRunners[1].current), tc.readCmd + tc.startedRun)
  }

  function test_a_busy_read_keeps_a_newer_nudge() {
    var store = capturedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    nudge(store, [tc.doneRun, 1010])
    // synthetic: am's StoreBusyError envelope, which runs-snapshot.py --run re-emits unchanged.
    reply(proc, '{"error": {"message": "the am store is busy; try again", "type": "StoreBusyError"}, "ok": false}\n', 1)
    compare(store.nudges[tc.doneRun], 1010, "the higher seq wins")
    compare(store.debounceTimer.running, true, "the newer line's debounce still runs")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 234 passed, 2 failed` — `test_a_busy_store_on_a_read_keeps_the_run_and_retries_it` (stale is still false) and `test_a_read_of_a_run_am_does_not_know_relists` ("one list snapshot"). `test_a_busy_read_keeps_a_newer_nudge` already passes: it pins that the put-back in Step 3 never lowers a newer nudge.

- [ ] **Step 3: Implement the refusals**

**`core/stores/RunStore.qml`** — `readReplied()` handles UnknownRunError and StoreBusyError. Replace:

```qml
  // One run read's reply. The runner leaves readRunners and is destroyed. A
  // reply that is not its run's latest read, or for a project the user has
  // left, changes nothing; ok:true goes to applyRunRead; anything else changes
  // nothing.
  function readReplied(runner, stdout) {
    var runId = runner.runId
    var latest = store.hasKey(readState.latest, runId) && readState.latest[runId] === runner
    var current = latest && runner.madeFor === store.project
    readState.runners = readState.runners.filter(function(r) { return r !== runner })
    if (latest) {
      var next = store.copyMap(readState.latest)
      delete next[runId]
      readState.latest = next
    }
    runner.destroy()
    if (!current) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) store.applyRunRead(runId, envelope)
  }
```

with:

```qml
  // One run read's reply. The runner leaves readRunners and is destroyed. A
  // reply that is not its run's latest read, or for a project the user has
  // left, changes nothing. ok:true goes to applyRunRead. UnknownRunError
  // launches one list snapshot: the run stays until am no longer lists it.
  // StoreBusyError marks the runs stale and puts the nudge back for the next
  // trigger. Neither raises a toast or touches amStatus or lastError. Any other
  // failure changes nothing: the list snapshot reports such conditions.
  function readReplied(runner, stdout) {
    var runId = runner.runId
    var seq = runner.nudgeSeq
    var latest = store.hasKey(readState.latest, runId) && readState.latest[runId] === runner
    var current = latest && runner.madeFor === store.project
    readState.runners = readState.runners.filter(function(r) { return r !== runner })
    if (latest) {
      var next = store.copyMap(readState.latest)
      delete next[runId]
      readState.latest = next
    }
    runner.destroy()
    if (!current) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope === null) return
    if (envelope.ok === true) {
      store.applyRunRead(runId, envelope)
      return
    }
    if (envelope.ok !== false) return
    var err = envelope.error
    var type = err !== null && typeof err === "object" ? err.type : ""
    if (type === "UnknownRunError") {
      store.refresh()
    } else if (type === "StoreBusyError") {
      store.stale = true
      store.keepNudge(runId, seq)
    }
  }

  // nudges[runId] raised to seq (never lowered), without touching the
  // debounce: the next trigger takes it.
  function keepNudge(runId, seq) {
    if (store.hasKey(store.nudges, runId) && store.nudges[runId] >= seq) return
    var next = store.copyMap(store.nudges)
    next[runId] = seq
    store.nudges = next
  }
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 236 passed, 0 failed`

- [ ] **Step 5: Run the whole gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): relist on UnknownRunError and retry a run read on StoreBusyError"
```

---

### Task 5: `cursorReset` hello starts over; the header states the contract

**Files:**
- Modify: `core/stores/RunStore.qml` (header comment `:6-20`, `watchLine()`, a new `resetCursor()` after `triggerNudges()`)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `appliedSeq`, `asOfSeq`, `watchCursor`, `nudges`, `dropReads()`, `refresh()`, `readOf`, `runReply`, `capturedStore` (Tasks 1-3).
- Produces: `function resetCursor()`. Test helper: `resetHello(value)`.

- [ ] **Step 1: Append the cursor-reset tests**

In `tests/core/stores/tst_run_store.qml`, insert this block just before the file's final closing `}`:

```qml
  // ---- cursor reset (4.1.3)

  // synthetic: runs-watch.py's forwarded hello for watch-hello.json's schema_2
  // (schema, am, head, storeId) with cursorReset set to `value`.
  function resetHello(value) {
    var h = F.load("watch-hello.json").schema_2
    return { hello: { schema: h.schema, am: h.am, head: h.head, cursorReset: value, storeId: h.store_id } }
  }

  function test_a_cursor_reset_starts_over_from_a_list_snapshot() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var proc = readOf(store, tc.doneRun, 1005)
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, resetHello(true))
    compare(store.amSchema, 2, "still a hello")
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot")
    var list = store.snapshotRunner.current
    reply(proc, runReply(tc.doneRun, "status-done.json"), 0)
    compare(store.runs.length, 0, "the dropped read changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    // synthetic: runs.json's list with the started run's status replaced by
    // status-escalated.json's data.
    var data = F.load("runs.json").data
    data.runs[0].status = F.load("status-escalated.json").data
    data.runs[1].status = F.load("status-done.json").data
    reply(list, JSON.stringify({ ok: true, as_of_seq: 1010, store_id: data.store_id, runs: data.runs, data_dir: "/d" }) + "\n", 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the first list after a reset only arms")
    compare(store.alertsArmed, true)
    compare(store.asOfSeq, 1010)
  }

  function test_only_a_true_cursor_reset_starts_over() {
    var store = capturedStore(); if (!store) return
    var values = [false, "true", 1, null, undefined]
    for (var i = 0; i < values.length; i++) {
      var label = "cursorReset " + JSON.stringify(values[i])
      var seq = store.snapshotRunner.seq
      sendLine(store.watchProc, resetHello(values[i]))
      compare(store.snapshotRunner.seq, seq, label)
      compare(store.runs.length, 2, label)
      compare(store.asOfSeq, 989, label)
      compare(store.alertsArmed, true, label)
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 237 passed, 1 failed` — `test_a_cursor_reset_starts_over_from_a_list_snapshot`. `test_only_a_true_cursor_reset_starts_over` already passes: it pins that only a JSON `true` resets.

- [ ] **Step 3: Implement the reset and rewrite the header**

**`core/stores/RunStore.qml`** — Rewrite the header comment (`RunStore.qml:6-20`). Replace:

```qml
// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run,
// the attempt the Run detail pane shows and that attempt's `am logs` snapshot
// (runs-logs.py), and whether `am` could be asked at all. Two HelperRunners
// (snapshot, attempt logs) plus, while `active` (the panel is open), a
// long-lived runs-watch.py that says which runs changed; each burst of changes
// costs one debounced snapshot. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
```

with:

```qml
// The am run monitor's data: a list snapshot of every project's runs
// (runs-snapshot.py) kept to the selected project and normalized by the run
// domain model, plus the selected run, the attempt the Run detail pane shows
// and that attempt's `am logs` snapshot (runs-logs.py), and whether `am` could
// be asked at all. While `active` (the panel is open) a long-lived
// runs-watch.py nudges it, "run X changed at seq N", and is never folded into
// state: once per debounce window, a nudge newer than the snapshot that last
// covered its run (appliedSeq) costs one run read (runs-snapshot.py --run RUN,
// one HelperRunner per run) for a run it holds, or one list snapshot for a run
// it does not know. A cursorReset hello starts over from a list snapshot.
// asOfSeq is the last list's as_of_seq and watchCursor the watch's last
// cursor, held in memory only. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
```

**`core/stores/RunStore.qml`** — `watchLine()` starts over on a `cursorReset: true` hello; add `resetCursor()` after `triggerNudges()`. Replace:

```qml
  // One stdout line of the watch, a nudge source never folded into state.
  // {"changed": [{run, seq}, ...]} records each nudge (recordNudges).
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V}}, sets amSchema to N (an integer of 1 or
  // more, else 0) and amVersion to V (a string, else "") and starts nothing.
  // {"cursor": C} sets watchCursor when C is an integer of 0 or more.
  // Anything else -- blank, not JSON, not an object, a hello that is not an
  // object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) store.recordNudges(value.changed)
    else if (value.ok === false) proc.envelope = value
    else if (value.hello !== null && typeof value.hello === "object" && !Array.isArray(value.hello)) {
      var schema = value.hello.schema
      store.amSchema = typeof schema === "number" && Number.isInteger(schema) && schema >= 1 ? schema : 0
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
    } else if
```

with:

```qml
  // One stdout line of the watch, a nudge source never folded into state.
  // {"changed": [{run, seq}, ...]} records each nudge (recordNudges).
  // {"ok": false, ...} is kept as the envelope its exit explains. The hello,
  // {"hello": {"schema": N, "am": V, "cursorReset": B}}, sets amSchema to N
  // (an integer of 1 or more, else 0) and amVersion to V (a string, else "");
  // B === true starts over (resetCursor), anything else starts nothing.
  // {"cursor": C} sets watchCursor when C is an integer of 0 or more.
  // Anything else -- blank, not JSON, not an object, a hello that is not an
  // object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) store.recordNudges(value.changed)
    else if (value.ok === false) proc.envelope = value
    else if (value.hello !== null && typeof value.hello === "object" && !Array.isArray(value.hello)) {
      var schema = value.hello.schema
      store.amSchema = typeof schema === "number" && Number.isInteger(schema) && schema >= 1 ? schema : 0
      store.amVersion = typeof value.hello.am === "string" ? value.hello.am : ""
      if (value.hello.cursorReset === true) store.resetCursor()
    } else if
```

**`core/stores/RunStore.qml`** — Add `resetCursor()` right after `triggerNudges()`. Replace:

```qml
    for (var j = 0; j < reads.length; j++) store.readRun(reads[j], taken[reads[j]])
  }
```

with:

```qml
    for (var j = 0; j < reads.length; j++) store.readRun(reads[j], taken[reads[j]])
  }

  // The watch's hello says its cursor no longer holds: the coverage, the
  // cursor and the nudges are forgotten, the runs emptied, the alerts disarmed
  // (the next list snapshot only arms), every run read in flight dropped, and
  // one list snapshot launched. Selection, logs, controls and dispatch stay.
  function resetCursor() {
    store.appliedSeq = {}
    store.asOfSeq = 0
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
    store.runs = []
    store.alertsArmed = false
    store.dropReads()
    store.refresh()
  }
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `Totals: 238 passed, 0 failed`

- [ ] **Step 5: Check no stale contract text is left**

Run: `grep -n "each burst of changes\|costs one debounced snapshot\|the runs the snapshot just listed\|snapshotRunner.run(\[store.project\])\|onTriggered: store.refresh()$" core/stores/RunStore.qml`
Expected: only the `livenessTimer` and `pollTimer` lines (`onTriggered: store.refresh()`), which keep refreshing by design; nothing else.

- [ ] **Step 6: Run the whole gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed` (including `tests/architecture` in the pytest run).

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): start over from a list snapshot on a cursorReset hello and state the nudge contract"
```
<!-- task-pipeline: validated -->
