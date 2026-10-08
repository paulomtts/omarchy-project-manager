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
