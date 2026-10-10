# 3.2 RunStore: the watch covers every root and a change refreshes only its projects — design

Card `b54795cd` (subtask of story `fee6bfab` "Global runs store"), blocked by 3.1
(`d6d38ee2`, landed: `docs/superpowers/specs/3-1-runstore-the-d6d38ee2.md`, cited as
**3.1:§**). Parent design: `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md`
(cited as **S6:line**).

## Where this card and the parent spec disagree

The card wins for this subtask. 3.1 made the same call (3.1 "Where this card and the parent
spec disagree"). The disagreements are these:

- **S6:118-121** says `runs-watch.py` "takes no roots and no run ids". The helper that
  milestone 2 built requires at least one root. An argument beginning with `/` is a root,
  and any other non-empty argument not beginning with `-` is a run id. An empty argument,
  any other `-` argument, or no root at all is a `Usage` error (exit 2):
  `core/backend/runs/runs-watch.py:1-10, 86-113`. The card says "startWatch passes every
  root and the known run ids". Today's no-argument launch (`RunStore.qml:271-281`) is
  therefore a `Usage` failure on every opening. 3.1 left that gap open on purpose
  (3.1 "Out of scope", 3.2 bullet).
- **S6:150-153** says "a nudge refreshes one run" through `am status RUN`. The card says the
  store "maps the ids to the roots that listed them and refreshes only those". From this
  card on, **a nudge never launches a run read.** It launches a list snapshot of the roots
  that list the nudged runs. The run-read path (`readRun`, `readReplied`, `keepNudge`,
  `applyRunRead`, `withRun`, `dropReads`, the whole `readState` object (`runners`, `latest`
  and `rows`), `readC`, the `readRunners` alias) has no caller left, so this card removes it
  along with its tests. `readState.rows` (the `am runs` row `applyRunRead` rebuilt a run
  from) has no other reader, so `applyProjects` stops building `fresh` / `keptRows`; its
  doc comment loses the `readState.rows` clause. `runs-snapshot.py --run` and its pytest stay untouched.

Every other constraint cited below still holds. Those are S6:154-156 (one in flight plus one
pending), S6:158 (stale), S6:174 (a slow snapshot makes liveness wait as the pending
request), S6:136-139 (`runsChanged(ids)` for the events pane) and S6:127-129 (layering).

## What the store must do

Terms from 3.1 that this spec reuses unchanged:

- **Usable roots** are `usableRoots()`, in registry order.
- **`runsByProject`**, **`projectErrors`** and **`runs`** keep 3.1's definitions.
- **Applying a reply** is `applyProjects`. Entries are matched to the usable roots by exact
  root, and a usable root with no entry keeps its runs and its error (3.1 "Applying a
  reply").

### 1. Snapshot requests: one in flight, one pending (S6:154-156)

Every list snapshot goes through one request path. A request asks for a set of roots, or
for **all** roots.

- **Idle runner** (`snapshotRunner.busy` false). The request launches at once:
  `python3 <backendDir>runs/runs-snapshot-all.py <root> ...`. The roots are the
  requested ones that are usable right now, in registry order, each once. "All" means every
  usable root at launch time. If none of the requested roots is usable, nothing launches.
- **Busy runner.** The request **never stops, restarts or relaunches the snapshot in
  flight.** `snapshotRunner.current` stays the same Process and `snapshotRunner.seq` does
  not move. The request is merged into the single **pending** request. A request for all
  roots wins over any set of roots. Otherwise the pending request becomes the union of
  the roots. However many requests arrive during one snapshot, there is at most one
  pending request.
- **The snapshot ends.** Its reply is applied first, whatever it was: an ok reply, an
  `ok:false` envelope, or output that is no envelope. Then the pending request, if there is
  one, is cleared and launched by the idle-runner rule above. "All" and the roots are
  resolved against the registry as it is now. So a snapshot ends and exactly one
  follow-up starts, never more.
- **No usable root at all** (`refresh()` with an empty registry). The runner is cancelled,
  the pending request is dropped, and `runs`, `runsByProject` and `projectErrors` are
  emptied (3.1 behaviour, unchanged).
- **The panel closes** (`stopLive`). The pending request is dropped. A snapshot in flight
  runs to its end and is applied, as it is today. A registry change while the panel is
  closed still requests every root, as in 3.1.
- `refresh()` keeps its name and becomes "request all roots". The store also exposes
  the roots of the snapshot in flight (`[]` when idle) and the pending request (none, all,
  or a list of roots) as readable properties, so tests can assert them. The planner picks
  the exact names and lists them in the plan's Interfaces.

- **Starting over is the one exception to "never stops".** `resetCursor` forgets the store
  last seen, so a snapshot in flight belongs to it. `resetCursor` cancels the runner
  (`snapshotRunner.cancel()`; its late exit changes nothing), drops the pending request and
  then requests all roots, which launches at once. Otherwise that reply would be applied
  and arm the alerts, and the follow-up of the new store would toast against the old
  store's runs. A nudge, a poll, a liveness tick or a registry change never cancels.

Which trigger requests what:

| trigger | request |
|---|---|
| the panel opens (`startLive`) | all |
| a registry change (`registryChanged`) | all |
| the fallback poll tick (`pollTimer`, 5 s) | all |
| starting over (`resetCursor`: cursorReset hello, another store_id) | all, after cancelling the snapshot in flight (below) |
| a debounce firing that holds a nudge for an unknown run id | all |
| a debounce firing whose run ids are all known | the roots that list them (§3) |
| the liveness tick (`livenessTimer`, 10 s) | the roots with a running run (§4) |

### 2. A reply that covers only some roots

`applyProjects` already merges a partial reply (3.1). This card pins the cases a partial
reply makes reachable:

- Roots the reply does not name keep their runs and their errors. `runs` is merged again over every usable root. A run of an unrefreshed root is
  the same object as before.
- **No matched entry.** When the reply matches no usable root, and none of the roots the
  snapshot was launched for is usable any more (they all left the registry while it was in
  flight), the reply changes nothing: no `amStatus`, no `lastError`. Any other reply with
  no matched entry is today's "The runs snapshot gave no usable result (exit N)." error.
- **AmMissing** is judged over the matched entries, as today. A partial reply whose every
  matched entry is `AmMissing` is the store-wide `missing` state, because `am` is either on
  PATH or it is not.
- Alerts compare the previous `runs` with the new `runs` as in 3.1. Unrefreshed runs are
  unchanged, so they never alert.
- `asOfSeq` stays 0 and `appliedSeq` stays `{id: 0}` for every run in `runs`, as in 3.1.
  They are now only "which run ids the store knows". Removing them is not this card's work.

### 3. Nudges: announce, map to roots, refresh those (card; S6:136-139)

The watch line contract, `recordNudges` and the 250 ms debounce are unchanged
(`RunStore.qml:300-339`). When the debounce fires (`triggerNudges`), the store does this:

1. It takes the nudges, so `nudges` becomes `{}`. If none were taken, nothing else happens.
2. It emits **`runsChanged(ids)`** once. `ids` is an array of the taken run ids as
   strings, each once, in the order they were first recorded in the window. It includes
   ids the store does not know. The signal fires only from a debounce firing, never for a
   snapshot the store started itself (open, registry, poll, liveness, reset). It fires
   before the refresh request.
3. It maps each id to **the usable roots whose `runsByProject` list holds a run with that
   id**. That is every such root, not only the root that won the de-duplication (3.1 "first
   root wins").
4. If **any** id is listed by no usable root, the store requests **all** roots once.
   Otherwise it requests the union of the mapped roots once. The nudge's seq is not
   compared with anything: a known run's nudge always refreshes its roots.

The seq stays part of the nudge contract. `nudges` keeps the highest seq per run, as
today. It just no longer gates anything.

### 4. Liveness covers only the roots with a running run (card)

`livenessTimer` keeps its interval (10 s), its `repeat` and its `running` binding
(`active && hasRunningRun`). Each tick requests the usable roots whose `runsByProject` list
holds a run with `Runs.runState(run) === "running"`, in registry order. When no root
qualifies, the tick requests nothing. A tick during a snapshot in flight becomes or joins
the pending request and never stacks (S6:174).

### 5. The watch argv (card)

`startWatch()` launches:

```
["python3", <backendDir> + "runs/runs-watch.py", <root> ..., <run id> ...]
```

- **Roots** are the usable roots in registry order that begin with `/`. The helper reads a
  root not beginning with `/` as a run id (`runs-watch.py:5-7`), so such a root is left
  out.
- **Run ids** are the known run ids: every run id in the `runsByProject` lists of the usable
  roots, in registry order and then list order, each once. Ids that are empty or begin with
  `-` or `/` are left out, because the helper would refuse them (`Usage`) or misread them
  as roots. No `--since-seq` is passed, as today.
- **No root qualifies.** No watch Process is launched, `watching` stays false and
  `watchTried` becomes true, so later snapshots do not retry. Liveness, the stale clock and
  the snapshots work as before. (Registry roots come from `brd` as absolute paths, so this
  is a guard, not a path users take.)
- **Restarting on a new root set.** When a good snapshot is applied while `active` and a
  watch is running (`watching` true), and the usable `/` roots differ from the roots the
  running watch was launched with (as a set), the watch is stopped and started again with
  the argv above. Without this, a project registered while the panel is open would never be
  nudged: the helper only keeps runs whose `repo_dir` matches a root it was given. The
  restart waits for that snapshot so the argv carries the new root's run ids. A watch that
  has ended (exit, or the poll replaced it) is not restarted. That stays "until the next
  activation", as today. A new run id in an already-watched root does not restart the
  watch, because the helper picks it up from its `run_upsert`.

The hello, cursor, exit and poll handling of the watch are unchanged.

### 6. `stale` is global (card; S6:158)

`stale` becomes true when no root has had a good reply for 30 s while the panel is open:

- A reply with **at least one ok matched entry** counts as good, whether it is full or
  partial (a nudge's or a liveness tick's). It sets `stale` false and restarts the 30 s
  clock while `active`, as `applyProjects` does today.
- A reply where every matched entry failed, an `ok:false` reply, output that is no
  envelope, or a reply dropped by §2's "no matched entry" rule leaves `stale` and the clock
  alone.
- Opening the panel starts the clock (`restartStale`). Closing it stops the clock and sets
  `stale` false. Both are unchanged.
- The run read's `StoreBusyError → stale = true` path goes away with the run reads. A
  per-entry `StoreBusyError` is a failed entry (3.1).

### 7. Header and comments

The RunStore header comment (`RunStore.qml:17-24`) and the comments on `triggerNudges`,
`livenessTimer`, `snapshotRunner`, `refresh`, `startWatch`, `appliedSeq` and `storeId`
must state the new contract:

- nudges announce `runsChanged` and refresh their roots;
- one snapshot in flight plus one pending request;
- the watch argv;
- `storeId` comes from a hello only.

Comments state the contract only, with no history (card).

## Out of scope

- **3.3**: `projectFilter`, `groups`, display order. **3.4**: per-project alert arming,
  the project name on toasts, the global notify setting. **3.5**: control, resume settings
  and logs for a run of any project, and the remaining runner guards.
- The events pane that consumes `runsChanged` (S5). This card only emits the signal.
- Any change to `core/backend/**` (`runs-watch.py`, `runs-snapshot-all.py`,
  `runs-snapshot.py`) or its pytest, to `runs.js`, `App.qml`, the fixtures or any UI file.
- Removing `asOfSeq` / `appliedSeq`, resuming the watch from `watchCursor`, restarting a
  watch that ended, and `docs/architecture.md`. Its RunStore paragraph already predates 3.1
  and is left for the milestone's docs card.

## Tests

Tests come first (TDD). The gate is `bash tests/run.sh` green, which includes
`tests/architecture` (layering: stores import only QtQml, Quickshell, Quickshell.Io and
`../domain`). A single file runs with `bash tests/run.sh run_store`.

All new tests are in the **store tier**, `tests/core/stores/tst_run_store.qml`. Every
behaviour here is RunStore's own, it is observable through its properties, signals and
the stubbed `Process` argv, and it needs no App or UI. Drive it with the existing helpers:
`activeRoots`, `allReply` / `okEntry` / `failEntry` (use these, not `okReply`, for partial
replies, because `okReply` always answers rootA), `entry(id, status, live, root)`,
`sendLine`, `fire(timer)`, `argv(proc)` and `spyC` (SignalSpy). rootA
(`/home/u/my proj`, with a space) must appear as one argv element.

1. **Watch argv.** With A and B registered, a first good reply listing `a1` under A and
   `b1` under B starts the watch with exactly
   `["python3", "/plugin/core/backend/runs/runs-watch.py", A, B, "a1", "b1"]`. A run id
   listed under both roots appears once. Ids `""`, `"-x"` and `"/x"` are left out. A
   registered root not beginning with `/` is left out. With no runs, the argv is the roots
   alone.
2. **No absolute root.** With only a relative root registered, a good reply launches no
   watch, `watching` is false, and a second good reply still launches none.
3. **runsChanged.** One `changed` line with `b1` then `a1`, followed by a debounce firing,
   emits `runsChanged` exactly once with `["b1", "a1"]`. It is emitted with an unknown id
   too. It is not emitted by `refresh()`, by a liveness tick, by a poll tick or by opening
   the panel, and not by a firing with no nudges.
4. **Partial refresh by ids.** With A, B and C listed (`a1`, `b1`, `c1`), a nudge for `b1`
   launches a snapshot whose argv is the snapshot command plus B only. Nudges for `a1` and
   `c1` in one window launch one snapshot of A and C, in registry order. A run id listed by
   A and B refreshes both. No `--run` read is ever launched (`readRunners` is gone).
5. **Partial reply applied.** In that partial snapshot, a reply for B alone replaces B's
   runs and keeps A's and C's runs as the same objects, their `projectErrors` entries, and
   `runs` in registry order. A good partial reply clears `stale`.
6. **Unknown id refreshes all.** A window holding a known id and an unknown id launches
   exactly one snapshot of every usable root.
7. **Coalescing.** With a snapshot in flight, a nudge, a liveness tick and `refresh()`
   leave `snapshotRunner.current` the same object, still running, and `seq` unchanged.
   When the in-flight snapshot is answered, exactly one follow-up launches (`seq + 1`), with
   the union of the wanted roots (all, when `refresh()` was among them). Answering that
   follow-up launches nothing more. Two nudges for B and C during one snapshot give a
   follow-up of B and C only. A failed or garbage reply also starts the pending follow-up.
8. **Pending resolves at launch.** With a snapshot in flight and a pending request for B,
   removing B from the registry means the pending set is resolved when the snapshot ends.
   A pending B-only request launches nothing. A pending "all" launches the new registry's
   roots. With an empty registry, `refresh()` cancels the snapshot in flight and drops the
   pending request, so a late exit launches nothing.
   `resetCursor` with a snapshot in flight cancels it (a late exit applies nothing and
   launches nothing) and launches one snapshot of all roots at once.
9. **Closing drops the pending request.** With a snapshot in flight and a pending request,
   setting `active` to false and then answering the snapshot applies the reply and
   launches no follow-up.
10. **Liveness only for running projects.** With A holding a running run and B only a done
    run, a liveness tick launches a snapshot of A alone. With running runs in A and C, it
    launches A and C. With no running run, the timer is off and a forced trigger launches
    nothing.
11. **Stale.** While active with A and B:
    - no good reply for 30 s (`fire(staleTimer)`) sets `stale` true;
    - a later partial reply with one ok entry (B) clears it and restarts the clock;
    - a reply where every entry failed leaves `stale` true and the clock untouched;
    - a reply for roots that all left the registry while it was in flight leaves
      `amStatus`, `lastError` and `stale` untouched.
12. **Watch restart on a new root set.** While watching A, registering C gives a good
    reply for A and C, and that reply stops the old watch and starts one with A, C and
    their run ids. A further good reply with the same roots keeps the watch object.
    Removing C does the same, the other way. A watch that exited (non-zero, poll running)
    is not restarted by a registry change.

### Existing tests that change (store tier)

These are rewritten to the rules above or removed. None is left failing or skipped.

- The watch argv tests (`test_watch_argv_after_first_snapshot`,
  `test_watch_with_no_runs_watches_the_project_alone`, the `command.length === 2`
  assertions in `test_failed_first_snapshot_does_not_start_watch` and
  `test_second_snapshot_does_not_restart_watch`) become tests 1 and 12.
- `test_only_the_latest_refresh_is_applied` becomes test 7. A second `refresh()` no longer
  kills the first snapshot.
- `test_liveness_tick_refreshes` asserts test 10's argv.
- The run-read tests (`test_a_list_covers_every_listed_run_at_0_and_nudges_follow_it`, the
  `readRunners` assertions in `test_with_no_project_open_the_panel_snapshots_every_root_and_watches`,
  `test_a_nudge_for_a_listed_run_always_costs_a_read` through
  `test_a_busy_read_keeps_a_newer_nudge`, about lines 4240-4650) are removed or rewritten
  as nudge → partial-snapshot tests. Behaviour they covered that still exists must keep a
  test. That means a refresh that escalates a run raises one toast, a refresh that moves
  the selected attempt refetches its logs, a refresh that moves a run settles its pending
  request, and a nudge after a project switch is still handled.
- Any test that calls `refresh()` (or changes `projectRoots` or `active`) while a snapshot
  is still in flight and expects a new Process must answer the in-flight one first, or
  assert the pending follow-up instead.

### Other tiers (kept green, not extended)

`tests/core/stores/tst_app_runs.qml` (composition) and `tests/ui/**` feed `snapshotRunner`.
A test there that launched a second snapshot over a running one now gets that second
snapshot only as a follow-up, after replying to the first. Adjust the test's driving and
nothing else. No new App or UI behaviour is asserted.

## Review focus (inputs this card implies that the tests above could miss)

1. **A burst of nudges during a slow fan-out.** It must never stop the snapshot in flight,
   and it must give exactly one follow-up. Any call to `snapshotRunner.run` while it is busy
   is a bug.
2. **A run id or root that the helper refuses or misreads** (`-` prefix, empty, relative
   path) must never reach the watch argv. Otherwise the watch exits 2 on every opening.
3. **A partial reply** must not reset unrefreshed roots: their runs, errors and alerts stay
   as they were.
4. **A registry change while a snapshot is in flight.** The pending request resolves
   against the registry at launch, and a reply for removed roots is not an error.
5. **A project added while the panel is open** must get nudges, through the watch restart
   after its first good snapshot.

---

# 3.2 RunStore: the watch covers every root and a change refreshes only its projects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RunStore keeps one list snapshot in flight plus one pending request, a debounce of nudges announces its run ids and refreshes only the roots that list them, the liveness tick refreshes only the roots with a running run, and `runs-watch.py` is launched with every absolute usable root and every known run id (restarted when the root set changes). The run-read path goes away.

**Architecture:** Every list snapshot goes through `requestSnapshot(roots | "all")`. An idle `snapshotRunner` launches the request at once. A busy one keeps it as the single pending request (`snapshotState.pending`). `snapshotEnded` applies the reply, then launches the pending request against the registry as it is at that moment. `triggerNudges`, `refreshLive`, `refresh`, the poll and the registry change are all requesters. Only `resetCursor` and an empty-registry `refresh()` cancel the runner. `startWatch` builds the argv from `usableRoots()` and `runsByProject`. `applyProjects` restarts a running watch when the absolute usable roots differ, as a set, from the roots it was launched with.

**Tech Stack:** QML (Qt 6 / Quickshell) store, `qmltestrunner` store-tier tests with stubbed `Process`, `bash tests/run.sh` gate (pytest + every QML test).

**Spec:** `docs/superpowers/specs/3-2-runstore-the-watch-b54795cd.md` (reproduced verbatim above).

## Where this plan departs from the spec

- **The signal is `runsNudged(ids)`, not `runsChanged(ids)`.** `RunStore` has `property var runs`, so QML already generates a `runsChanged()` change signal. Declaring `signal runsChanged(var ids)` next to it fails to compile with `Duplicate signal name: invalid override of property change signal or superclass signal`. This was checked with `qmltestrunner` against a two-line QML file. Everything else the spec says about the signal holds under the new name: it is emitted once per debounce firing that took nudges, with the taken ids as strings, in first-recorded order, unknown ids included, before the refresh request, and never for a snapshot the store started itself. The S5 events pane must connect to `runsNudged`. The declaration's comment says why the name differs.
- **Spec test 8, "a pending B-only request launches nothing".** Removing B from the registry cannot leave a B-only pending request. The registry change itself calls `refresh()`, which turns the pending request into `"all"`. The plan pins both halves separately. `test_a_pending_request_resolves_against_the_registry_at_launch` removes B mid-flight, and the pending `"all"` launches the new registry's roots. `test_a_request_for_roots_no_longer_usable_launches_nothing` uses `requestSnapshot` with a root the registry no longer holds, and nothing launches.

Exposed names the spec left to the planner: `snapshotRoots` (the roots of the snapshot in flight, `[]` when idle), `pendingSnapshot` (`null`, `"all"` or `[root, ...]`) and `watchRoots` (the roots the current watch was launched with).

## Global Constraints

- The gate is `bash tests/run.sh` green. It runs pytest (including `tests/architecture`) and then every `tst_*.qml`. A single QML file runs with `bash tests/run.sh run_store`.
- Layering: stores import only QtQml, Quickshell, Quickshell.Io and `../domain` (S6:127-129). `RunStore.qml` gains no import.
- Only two files change: `core/stores/RunStore.qml` and `tests/core/stores/tst_run_store.qml`. Do not change `core/backend/**` (`runs-watch.py`, `runs-snapshot-all.py`, `runs-snapshot.py`) or its pytest, `core/domain/runs.js`, `App.qml`, the fixtures, any UI file, `docs/architecture.md`, `tests/core/stores/tst_app_runs.qml` or `tests/ui/**`. The end state of this plan was run against the whole suite, and those tiers pass unchanged.
- The watch argv is exactly `["python3", <backendDir> + "runs/runs-watch.py", <root> ..., <run id> ...]`, with no `--since-seq`. rootA (`/home/u/my proj`, with a space) is one argv element.
- Timers keep their values: `debounceTimer` 250 ms one-shot; `livenessTimer` 10 000 ms, `repeat: true`, `running: store.active && store.hasRunningRun`; `staleTimer` 30 000 ms one-shot; `pollTimer` 5 000 ms repeat.
- While `snapshotRunner.busy`, nothing calls `snapshotRunner.run(...)`. Only `resetCursor()` and `refresh()` with no usable root call `snapshotRunner.cancel()`.
- `asOfSeq` stays 0 and `appliedSeq` stays `{id: 0}` for every run in `runs`. Neither is removed.
- Comments state the contract only: no history of what the code did before. A test comment like `// 7 and Review Focus 1` numbers the spec's tests and the spec's Review Focus. `// The plan's Review Focus N` numbers the list below.
- `nudges` keeps the highest seq per run. The seq gates nothing.

## Review Focus

These are the inputs the spec implies but its own test list does not exercise. Each line names the task that pins it.

1. **A nudge's partial reply in which every matched entry is `AmMissing`.** Expect the store-wide `missing` state, with every root's runs and errors emptied, not only the nudged root's. Test: `test_a_partial_reply_that_is_am_missing_empties_every_root` (Task 2).
2. **A registry that is reordered or renamed but keeps the same roots.** The running watch is kept, because the roots are compared as a set. Test: `test_a_reordered_or_renamed_registry_keeps_the_watch` (Task 4).
3. **A nudge that arrives after the registry was emptied.** The watch keeps running, because no snapshot ran to restart it. The ids are still announced, nothing launches and nothing throws. Test: `test_a_nudge_after_the_registry_emptied_announces_and_launches_nothing` (Task 2).
4. **A nudge for a run that a failed root still holds.** The run is kept in that root's `runsByProject` list, so the nudge refreshes that root alone, not every root. Test: `test_a_nudge_for_a_run_kept_by_a_failed_root_refreshes_that_root` (Task 2).
5. **A root-set change that leaves no absolute root.** The old watch is stopped, none is launched, `watching` is false, and later good replies do not retry. Test: `test_a_restart_with_no_absolute_root_left_launches_no_watch` (Task 4).

## File Structure

- `core/stores/RunStore.qml` (modify). This is the whole behaviour.
  - Task 1 adds the request path: `requestSnapshot`, `launchSnapshot`, `dropSnapshots`, `snapshotEnded`, `snapshotState`, the `snapshotRoots` and `pendingSnapshot` aliases, and the `launched` argument of `applySnapshot` / `applyProjects`.
  - Task 2 rewrites `triggerNudges` (`listsRun`, `runsNudged`) and deletes the run-read path.
  - Task 3 adds `refreshLive`.
  - Task 4 rewrites `startWatch` (`watchableRoots`, `knownRunIds`, `sameRoots`, `watchState.roots`, the `watchRoots` alias) and adds the restart in `applyProjects`.
- `tests/core/stores/tst_run_store.qml` (modify). This is the store tier: new tests in three new sections, rewrites of the tests the new rules change, and removal of the run-read tests.

All four tasks change the same two files, in order. Each task's Find blocks match the file as the earlier tasks left it.

## Before you start

- [ ] **Step 0: Make sure the two files are at HEAD**

Run: `git diff --stat HEAD -- core/stores/RunStore.qml tests/core/stores/tst_run_store.qml`
Expected: no output.

If it lists either file, an earlier attempt left an uncommitted draft in this worktree. The Find blocks below match HEAD, not that draft. Save the draft outside the worktree, then put both files back to HEAD:

```bash
git diff HEAD -- core/stores/RunStore.qml tests/core/stores/tst_run_store.qml > "/tmp/3-2-runstore-draft-$(date +%s).patch"
git checkout HEAD -- core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
```

Every test name used below is a function in `tests/core/stores/tst_run_store.qml`. The helpers the new tests use already exist there: `make`, `registry`, `rootEntry`, `makeWithRoots`, `activeRoots`, `activeStore`, `makeWithProject`, `watchedStore`, `reply`, `entry`, `allReply`, `okEntry`, `failEntry`, `okReply`, `rec`, `ids`, `argv`, `fire`, `sendLine`, `nudge`, `capturedStore`, `capturedList`, `toastIds`, `logsReply`, `ctlOk`, `endWatch`, `watchError`, `spyC`, and the properties `rootA`, `rootB`, `rootC`, `snapCmd`, `capRoot`, `startedRun`, `doneRun` and `openCard`. Task 2 adds `threeRoots` and `threeReply`, and Task 4 adds the `watchCmd` property.

---

### Task 1: One snapshot in flight plus one pending request

Covers spec §1, the "no matched entry" rule of §2, the header sentence of §7, and spec tests 7 (requests), 8, 9 and 11's last bullet.

**Files:**
- Modify: `core/stores/RunStore.qml`: the header comment; the aliases after `snapshotRunner`; `refresh`; `stopLive`; `resetCursor`; `applySnapshot`; `applyProjects`; the `snapshotRunner` HelperRunner; a new `snapshotState` QtObject after `watchState`
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes (`core/stores/HelperRunner.qml`, unchanged): `busy: bool`, `seq: int` (bumped by every `run` and `cancel`), `current: Process`, `run(args: string[])` (stops the previous process), `cancel()` (bumps `seq`, so a late exit emits nothing). The stub `Process` in `tests/stubs/Quickshell/Io/Process.qml` has `command`, `running` and `signal exited(int)`. `reply(proc, text, code)` sets `outText` and emits `exited`.
- Produces:
  - `function refresh()`: requests `"all"`. With no usable root it calls `dropSnapshots()` and empties `runs`, `runsByProject` and `projectErrors`.
  - `function requestSnapshot(roots)`: `roots` is `"all"` or `string[]`. An idle runner launches at once. A busy runner merges into `pendingSnapshot`, where `"all"` wins and roots are unioned.
  - `function launchSnapshot(roots)`: launches the requested roots that are usable now, in registry order. With none it launches nothing.
  - `function dropSnapshots()`: cancels a busy runner, sets `snapshotRoots` to `[]` and `pendingSnapshot` to `null`.
  - `function snapshotEnded(stdout: string, exitCode: int)`: applies the reply, then launches the pending request.
  - `function applySnapshot(stdout, exitCode, launched: string[])` and `function applyProjects(entries, exitCode, launched: string[])`. `launched` is the roots the snapshot was launched with.
  - `readonly property alias snapshotRoots` (`string[]`, `[]` when idle) and `readonly property alias pendingSnapshot` (`null`, `"all"` or `string[]`).

- [ ] **Step 1: Write the failing tests**

Apply these edits to `tests/core/stores/tst_run_store.qml`, in order. Edit **d** removes `test_only_the_latest_refresh_is_applied`, because a second `refresh()` no longer stops the first. `test_a_request_during_a_snapshot_waits_as_the_one_pending_request` replaces it. Edits **c**, **f** and **h** answer the snapshot already in flight before asserting a new launch. Edits **b** and **g** assert the pending request where a new Process used to appear.

**a.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
// latest-wins rule, what a registry change does and what a project switch
// leaves alone. Built directly and driven through stubbed Process objects.
```

Replace it with:

```qml
// one-in-flight-plus-one-pending rule, what a registry change does and what a
// project switch leaves alone. Built directly and driven through stubbed
// Process objects.
```

**b.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB), rootEntry(tc.rootC)]
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC,
```

Replace it with:

```qml
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB), rootEntry(tc.rootC)]
    compare(store.pendingSnapshot, "all", "a registry change during a snapshot waits as the pending request")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")])]), 0)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC,
```

**c.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_with_no_project_open_the_panel_snapshots_every_root_and_watches() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var seq = store.snapshotRunner.seq
```

Replace it with:

```qml
  function test_with_no_project_open_the_panel_snapshots_every_root_and_watches() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var seq = store.snapshotRunner.seq
```

**d.** In `tests/core/stores/tst_run_store.qml`, delete this text, and the blank line right after it:

```qml
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
```

**e.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  // ---- live refresh (3.2)
```

Replace it with:

```qml
  // ---- one snapshot in flight plus one pending request (global 3.2)

  // 7 and Review Focus 1
  function test_a_request_during_a_snapshot_waits_as_the_one_pending_request() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var inFlight = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    var all = tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC
    compare(store.snapshotRoots.join("|"), [tc.rootA, tc.rootB, tc.rootC].join("|"), "the roots in flight")
    compare(store.pendingSnapshot, null, "nothing pending yet")
    store.requestSnapshot([tc.rootC])
    store.requestSnapshot([tc.rootB, tc.rootC])
    verify(store.snapshotRunner.current === inFlight, "the snapshot in flight is never replaced")
    compare(inFlight.running, true, "nor stopped")
    compare(store.snapshotRunner.seq, seq)
    compare(store.pendingSnapshot.join("|"), [tc.rootC, tc.rootB].join("|"), "the union of the roots")
    store.refresh()
    compare(store.pendingSnapshot, "all", "all wins over any roots")
    store.requestSnapshot([tc.rootB])
    compare(store.pendingSnapshot, "all", "and stays all")
    verify(store.snapshotRunner.current === inFlight)
    compare(store.snapshotRunner.seq, seq)
    reply(inFlight, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, []), okEntry(tc.rootC, [])]), 0)
    compare(ids(store.runs), "a1", "the reply is applied")
    compare(store.snapshotRunner.seq, seq + 1, "then exactly one follow-up launches")
    compare(argv(store.snapshotRunner.current), all)
    compare(store.pendingSnapshot, null)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, []),
                                                  okEntry(tc.rootC, [])]), 0)
    compare(store.snapshotRunner.seq, seq + 1, "answering the follow-up launches nothing more")
    compare(store.snapshotRunner.busy, false)
    compare(store.snapshotRoots.length, 0, "no roots in flight when idle")
  }

  // 7
  function test_a_pending_set_of_roots_launches_those_roots_in_registry_order() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var inFlight = store.snapshotRunner.current
    store.requestSnapshot([tc.rootC])
    store.requestSnapshot([tc.rootB])
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, []), okEntry(tc.rootC, [])]), 0)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB + "|" + tc.rootC, "B and C only, in registry order")
    compare(store.snapshotRoots.join("|"), tc.rootB + "|" + tc.rootC)
  }

  // 7
  function test_a_failed_or_garbage_reply_still_launches_the_pending_request() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var replies = [[JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }), 1],
                   ["Traceback (most recent call last):", 1], ["", 0],
                   [allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s.")]), 0]]
    for (var i = 0; i < replies.length; i++) {
      var label = JSON.stringify(replies[i][0])
      var seq = store.snapshotRunner.seq
      store.refresh()
      compare(store.snapshotRunner.seq, seq, label + ": waits")
      reply(store.snapshotRunner.current, replies[i][0], replies[i][1])
      compare(store.amStatus, "error", label + " is applied")
      compare(store.snapshotRunner.seq, seq + 1, label + ": then the follow-up launches")
      compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, label)
    }
  }

  // 8 and Review Focus 4
  function test_a_pending_request_resolves_against_the_registry_at_launch() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var inFlight = store.snapshotRunner.current
    store.requestSnapshot([tc.rootB])
    store.projectRoots = registry([tc.rootA, tc.rootC])
    compare(store.pendingSnapshot, "all", "the registry change itself requests every root")
    var seq = store.snapshotRunner.seq
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                              okEntry(tc.rootC, [])]), 0)
    compare(Object.keys(store.runsByProject).sort().join(","), [tc.rootA, tc.rootC].sort().join(","), "B's entry is ignored")
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.seq, seq + 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootC, "the registry as it is now")
  }

  // 8
  function test_a_request_for_roots_no_longer_usable_launches_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var seq = store.snapshotRunner.seq
    store.requestSnapshot(["/home/u/gone"])
    compare(store.snapshotRunner.seq, seq, "an idle runner launches nothing for a root that is not registered")
    compare(store.snapshotRunner.busy, false)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    store.requestSnapshot(["/home/u/gone"])
    compare(store.pendingSnapshot.join("|"), "/home/u/gone")
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(store.snapshotRunner.seq, seq + 1, "a pending request naming no usable root launches nothing")
    compare(store.snapshotRunner.busy, false)
    compare(store.pendingSnapshot, null)
  }

  // 8
  function test_an_emptied_registry_drops_the_snapshot_in_flight_and_the_pending_request() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var inFlight = store.snapshotRunner.current
    store.refresh()
    compare(store.pendingSnapshot, "all")
    store.projectRoots = []
    compare(inFlight.running, false, "the snapshot in flight is stopped")
    compare(store.snapshotRunner.busy, false)
    compare(store.pendingSnapshot, null, "the pending request is dropped")
    compare(store.snapshotRoots.length, 0)
    var seq = store.snapshotRunner.seq
    reply(inFlight, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    compare(store.snapshotRunner.seq, seq, "its late exit launches nothing")
    compare(store.runs.length, 0, "and applies nothing")
  }

  // 8
  function test_starting_over_stops_the_snapshot_in_flight_and_launches_every_root() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    verify(store.watchProc, "the watch runs")
    store.refresh()
    var old = store.snapshotRunner.current
    store.requestSnapshot([tc.rootB])
    // synthetic: a hello whose cursorReset is true.
    sendLine(store.watchProc, { hello: { schema: 2, am: "0.1.0", cursorReset: true } })
    compare(old.running, false, "the old store's snapshot is stopped")
    verify(store.snapshotRunner.current !== old, "one snapshot is launched at once")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, "of every root")
    compare(store.pendingSnapshot, null, "the pending request was dropped")
    var seq = store.snapshotRunner.seq
    reply(old, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)])]), 0)
    compare(store.runs.length, 0, "its late reply applies nothing")
    compare(store.snapshotRunner.seq, seq, "and launches nothing")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)]), okEntry(tc.rootB, [])]), 0)
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.snapshotRunner.seq, seq, "no follow-up")
  }

  // 9
  function test_closing_the_panel_drops_the_pending_request() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    var inFlight = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    store.refresh()
    compare(store.pendingSnapshot, "all")
    store.active = false
    compare(store.pendingSnapshot, null, "closing drops it")
    compare(inFlight.running, true, "the snapshot in flight runs to its end")
    reply(inFlight, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    compare(ids(store.runs), "a1", "and is applied")
    compare(store.snapshotRunner.seq, seq, "no follow-up")
    compare(store.snapshotRunner.busy, false)
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC])
    compare(store.snapshotRunner.seq, seq + 1, "a registry change while closed still requests every root")
  }

  // 11 (the roots-left bullet) and Review Focus 4
  function test_a_reply_for_roots_that_all_left_the_registry_changes_nothing() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    store.projectRoots = registry([tc.rootC])
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(store.amStatus, "ok", "not an error")
    compare(store.lastError, "")
    compare(store.stale, true, "stale is untouched")
    compare(store.staleTimer.running, false, "and so is the clock")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootC, "the pending request launches C")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [])]), 0)
    compare(store.amStatus, "error", "a reply matching nothing while C is still registered is still an error")
    compare(store.lastError, "The runs snapshot gave no usable result (exit 0).")
  }

  // ---- live refresh (3.2)
```

**f.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_activation_refreshes_every_root() {
    var store = makeWithProject(rootA); if (!store) return
    var seq = store.snapshotRunner.seq
```

Replace it with:

```qml
  function test_activation_refreshes_every_root() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var seq = store.snapshotRunner.seq
```

**g.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
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
    compare(fresh.command.length, 2)
    compare(store.watching, true)
  }
```

Replace it with:

```qml
    store.active = true
    var first = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    store.active = false
    store.active = true
    verify(store.snapshotRunner.current === first, "the snapshot in flight is kept")
    compare(store.snapshotRunner.seq, seq)
    compare(store.pendingSnapshot, "all", "the second opening waits as the pending request")
    compare(old.running, false, "the old watch stays dead")
    reply(first, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old, "the reply that lands while open starts a new watch")
    compare(fresh.running, true)
    compare(fresh.command.length, 2)
    compare(store.watching, true)
    compare(store.snapshotRunner.seq, seq + 1, "then the pending request launches")
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc === fresh, "and its reply keeps the watch")
  }
```

**h.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
```

Replace it with:

```qml
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
(`tests/run.sh` runs the whole pytest suite first, about two minutes, then the one QML file. Only the `== tests/core/stores/tst_run_store.qml` block matters here.)
Expected: `Totals: 259 passed, 10 failed`, plus `is not a function` lines for `requestSnapshot`. These fail:
  - `test_a_failed_or_garbage_reply_still_launches_the_pending_request`
  - `test_a_pending_request_resolves_against_the_registry_at_launch`
  - `test_a_pending_set_of_roots_launches_those_roots_in_registry_order`
  - `test_a_registry_change_drops_renames_adds_and_snapshots_again`
  - `test_a_request_during_a_snapshot_waits_as_the_one_pending_request`
  - `test_a_request_for_roots_no_longer_usable_launches_nothing`
  - `test_an_emptied_registry_drops_the_snapshot_in_flight_and_the_pending_request`
  - `test_closing_the_panel_drops_the_pending_request`
  - `test_reactivation_starts_a_new_watch`
  - `test_starting_over_stops_the_snapshot_in_flight_and_launches_every_root`

`test_a_reply_for_roots_that_all_left_the_registry_changes_nothing` already passes at this point, because a second `refresh()` kills the first snapshot today. It pins the rule once the snapshot is no longer killed.

- [ ] **Step 3: Write the implementation**

Apply these edits to `core/stores/RunStore.qml`, in order:

**a.** In `core/stores/RunStore.qml`, find:

```qml
// asked at all. While `active` (the panel is open) a long-lived
// runs-watch.py nudges it, "run X changed at seq N", and is never folded into
```

Replace it with:

```qml
// asked at all. One list snapshot is in flight at a time, plus at most one
// pending request (requestSnapshot): a request never stops the snapshot in
// flight, and when that one ends its reply is applied and the pending
// request launches. While `active` (the panel is open) a long-lived
// runs-watch.py nudges it, "run X changed at seq N", and is never folded into
```

**b.** In `core/stores/RunStore.qml`, find:

```qml
  readonly property alias snapshotRunner: snapshotRunner
```

Replace it with:

```qml
  readonly property alias snapshotRunner: snapshotRunner
  readonly property alias snapshotRoots: snapshotState.roots     // the roots of the snapshot in flight; [] when idle
  readonly property alias pendingSnapshot: snapshotState.pending // the pending request: null, "all" or [root, ...]
```

**c.** In `core/stores/RunStore.qml`, find:

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

Replace it with:

```qml
  // Requests a list snapshot of every usable root (requestSnapshot("all")),
  // whether or not a project is open. With no usable root nothing is
  // launched, the snapshot in flight is stopped, the pending request is
  // dropped, and the run list, runsByProject and projectErrors are emptied.
  function refresh() {
    if (store.usableRoots().length === 0) {
      store.dropSnapshots()
      store.runs = []
      store.runsByProject = {}
      store.projectErrors = {}
      return
    }
    store.requestSnapshot("all")
  }

  // Asks for a list snapshot of `roots` ([root, ...]) or of "all" roots. An
  // idle runner launches it at once (launchSnapshot). A busy one is never
  // stopped: the request joins the one pending request, "all" winning over
  // any roots, else the union of the roots.
  function requestSnapshot(roots) {
    if (!snapshotRunner.busy) {
      store.launchSnapshot(roots)
      return
    }
    var pending = snapshotState.pending
    if (pending === "all" || roots === "all") {
      snapshotState.pending = "all"
      return
    }
    var next = pending === null ? [] : pending.slice()
    for (var i = 0; i < roots.length; i++) {
      if (next.indexOf(roots[i]) < 0) next.push(roots[i])
    }
    snapshotState.pending = next
  }

  // runs-snapshot-all.py with the requested roots that are usable now, in
  // registry order, each once ("all": every usable root). None: nothing.
  function launchSnapshot(roots) {
    var usable = store.usableRoots()
    var list = []
    for (var i = 0; i < usable.length; i++) {
      if (roots === "all" || roots.indexOf(usable[i].root) >= 0) list.push(usable[i].root)
    }
    if (list.length === 0) return
    snapshotState.roots = list
    snapshotRunner.run(list)
  }

  // The snapshot in flight is stopped (its late exit changes nothing) and
  // the pending request is dropped.
  function dropSnapshots() {
    if (snapshotRunner.busy) snapshotRunner.cancel()
    snapshotState.roots = []
    snapshotState.pending = null
  }

  // The snapshot ended: its reply is applied, whatever it was, then the
  // pending request, if any, is launched against the registry as it is now.
  function snapshotEnded(stdout, exitCode) {
    var launched = snapshotState.roots
    snapshotState.roots = []
    store.applySnapshot(stdout, exitCode, launched)
    var next = snapshotState.pending
    snapshotState.pending = null
    if (next !== null) store.launchSnapshot(next)
  }
```

**d.** In `core/stores/RunStore.qml`, find:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // runs, the selection and amStatus stay for the next opening.
  function stopLive() {
    store.stopWatch()
```

Replace it with:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The runs, the selection and amStatus stay for the next
  // opening.
  function stopLive() {
    snapshotState.pending = null
    store.stopWatch()
```

**e.** In `core/stores/RunStore.qml`, find:

```qml
  // Starts over: the coverage (appliedSeq, asOfSeq) and the live state
  // (forgetLive) are forgotten and one list snapshot is launched.
  function resetCursor() {
    store.appliedSeq = {}
```

Replace it with:

```qml
  // Starts over: the snapshot in flight (the old store's) is stopped and the
  // pending request dropped, the coverage (appliedSeq, asOfSeq) and the live
  // state (forgetLive) are forgotten, and one list snapshot of every root is
  // launched.
  function resetCursor() {
    store.dropSnapshots()
    store.appliedSeq = {}
```

**f.** In `core/stores/RunStore.qml`, find:

```qml
  // One list snapshot reply. {ok: true, projects} goes to applyProjects. An
  // ok:false envelope (Usage, HelperError) or output that is not one keeps
  // the runs, runsByProject and projectErrors and only reports why this one
  // failed. Never reads a store_id. Never throws.
  function applySnapshot(stdout, exitCode) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.applyProjects(Array.isArray(envelope.projects) ? envelope.projects : [], exitCode)
```

Replace it with:

```qml
  // One list snapshot reply, for the roots it was launched with. {ok: true,
  // projects} goes to applyProjects. An ok:false envelope (Usage,
  // HelperError) or output that is not one keeps the runs, runsByProject and
  // projectErrors and only reports why this one failed. Never reads a
  // store_id. Never throws.
  function applySnapshot(stdout, exitCode, launched) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.applyProjects(Array.isArray(envelope.projects) ? envelope.projects : [], exitCode, launched)
```

**g.** In `core/stores/RunStore.qml`, find:

```qml
  // ignored. No matched entry at all is a reply with no usable result. Every
```

Replace it with:

```qml
  // ignored. No matched entry at all is a reply with no usable result --
  // unless none of the roots it was launched for (`launched`) is usable any
  // more, when it changes nothing. Every
```

**h.** In `core/stores/RunStore.qml`, find:

```qml
  function applyProjects(entries, exitCode) {
```

Replace it with:

```qml
  function applyProjects(entries, exitCode, launched) {
```

**i.** In `core/stores/RunStore.qml`, find:

```qml
    if (matched.length === 0) {
      store.amStatus = "error"
```

Replace it with:

```qml
    if (matched.length === 0) {
      var gone = true
      var roots = Array.isArray(launched) ? launched : []
      for (var g = 0; g < roots.length; g++) {
        if (store.hasKey(names, roots[g])) gone = false
      }
      if (gone && roots.length > 0) return
      store.amStatus = "error"
```

**j.** In `core/stores/RunStore.qml`, find:

```qml
  // The list snapshot of every usable root. No guard: its reply is matched to
  // the registry by root, whatever project is open.
  HelperRunner {
    id: snapshotRunner
    script: store.backendDir + "runs/runs-snapshot-all.py"
    onFinished: function(stdout, exitCode) { store.applySnapshot(stdout, exitCode) }
  }
```

Replace it with:

```qml
  // The one list snapshot in flight (requestSnapshot). No guard: its reply is
  // matched to the registry by root, whatever project is open. Only
  // refresh() with no usable root and resetCursor() stop it.
  HelperRunner {
    id: snapshotRunner
    script: store.backendDir + "runs/runs-snapshot-all.py"
    onFinished: function(stdout, exitCode) { store.snapshotEnded(stdout, exitCode) }
  }
```

**k.** In `core/stores/RunStore.qml`, find:

```qml
    property var proc: null
    property bool watching: false
  }
```

Replace it with:

```qml
    property var proc: null
    property bool watching: false
  }

  // The list snapshots' own state; kept apart so consumers cannot write it.
  // `roots` are the roots of the snapshot in flight ([] when idle);
  // `pending` the one pending request: null, "all" or [root, ...].
  QtObject {
    id: snapshotState
    property var roots: []
    property var pending: null
  }
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 269 passed, 0 failed, 0 skipped`, with no `TypeError` / `ReferenceError` / `is not a function` line.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): one list snapshot in flight plus one pending request"
```

---

### Task 2: Nudges announce their runs and refresh only their roots; the run reads go

Covers spec §3, the removal described in "Where this card and the parent spec disagree", §2's partial-reply cases, §6's partial good reply, §7's `triggerNudges` / `appliedSeq` / `storeId` comments, and spec tests 3, 4, 5, 6, 7 (two nudge windows) and 11. Also the plan's Review Focus 1, 3 and 4.

**Files:**
- Modify: `core/stores/RunStore.qml`: the header comment; the `appliedSeq` and `storeId` comments; a new `runsNudged` signal; the `readRunners` alias is removed; `triggerNudges` and a new `listsRun`; `forgetLive`; the `seeStore` comment; `trimSlashes` is removed; `applyProjects` (its comment and the row bookkeeping); the `// ---- run reads` section, the `readState` QtObject and the `readC` Component are removed
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes (Task 1): `requestSnapshot(roots: "all" | string[])`, `refresh()`, `snapshotRoots`, `pendingSnapshot`.
- Produces:
  - `signal runsNudged(var ids)`: `ids` is a `string[]`, each id once, in first-recorded order.
  - `function listsRun(root: string, id: string): bool`: whether `runsByProject[root]` holds a run with that id.
  - `triggerNudges()` with the new rule: take the nudges, emit `runsNudged`, then request either `"all"` or the union of the mapped roots.
- Removed: the `readRunners` alias, `readRun`, `dropReads`, `readReplied`, `keepNudge`, `applyRunRead`, `withRun`, `trimSlashes`, `readState` and `readC`. `store.readRunners` is `undefined` afterwards.

- [ ] **Step 1: Write the failing tests**

Apply these edits to `tests/core/stores/tst_run_store.qml`, in order.

Edit **c** adds the section `// ---- nudges announce their runs and refresh their roots (global 3.2)`, which holds the new tests. Its first two functions are the helpers `threeRoots` and `threeReply`. The four tests whose comment begins "Kept behaviour" re-pin, through nudge-driven partial snapshots, what the removed run-read tests covered: an escalation toasts once, a moved attempt refetches its logs, a moved run settles its request, and a nudge after a project switch is still handled.

Edits **i** and **j** rewrite the two start-over tests. With no run reads left, they hold a list snapshot in flight at the reset instead, and assert that it is stopped and that its late reply changes nothing.

**a.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
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
```

Replace it with:

```qml
  function test_a_list_covers_every_listed_run_at_0_and_nudges_follow_it() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    // A project is open: nudges ignore it.
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
    compare(store.snapshotRunner.seq, seq + 1, "a listed run costs one snapshot of its root, whatever its seq")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [rec("done")])]), 0)
    // synthetic: a run am started after the list.
    nudge(store, ["20261008T150000Z-0a1b2c3d", 1006])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 2, "an unlisted run costs one snapshot of every root")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }
```

**b.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  // 11 (the snapshot half; Task 3 pins the run read)
```

Replace it with:

```qml
  // 11
```

**c.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  // ---- live refresh (3.2)
```

Replace it with:

```qml
  // ---- nudges announce their runs and refresh their roots (global 3.2)

  // An active store with A, B and C registered and no project open, whose
  // first snapshot listed a1 under A, b1 under B and c1 under C (all done):
  // its watch runs and nothing is in flight.
  function threeRoots() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  // threeRoots()'s reply again: every root answers with its one done run.
  function threeReply() {
    return allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                     okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                     okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])])
  }

  // 3
  function test_a_debounce_firing_announces_its_run_ids_once() {
    var store = threeRoots(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runsNudged" })
    nudge(store, ["b1", 5, "a1", 6])
    nudge(store, ["b1", 7])
    compare(spy.count, 0, "nothing before the debounce")
    fire(store.debounceTimer)
    compare(spy.count, 1, "once per firing")
    compare(JSON.stringify(spy.signalArguments[0][0]), JSON.stringify(["b1", "a1"]), "each id once, in first-nudge order")
    reply(store.snapshotRunner.current, threeReply(), 0)
    // synthetic: a run no root lists.
    nudge(store, ["z9", 8])
    fire(store.debounceTimer)
    compare(spy.count, 2, "an unknown id is announced too")
    compare(JSON.stringify(spy.signalArguments[1][0]), JSON.stringify(["z9"]))
    reply(store.snapshotRunner.current, threeReply(), 0)
    store.refresh()
    reply(store.snapshotRunner.current, threeReply(), 0)
    store.livenessTimer.triggered()
    store.pollTimer.triggered()
    reply(store.snapshotRunner.current, threeReply(), 0)
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, threeReply(), 0)
    fire(store.debounceTimer)
    compare(spy.count, 2, "refresh(), a liveness tick, a poll tick, an opening and an empty firing announce nothing")
  }

  // 4
  function test_a_nudge_refreshes_only_the_roots_that_list_its_runs() {
    var store = threeRoots(); if (!store) return
    var seq = store.snapshotRunner.seq
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB, "of B only")
    compare(store.snapshotRoots.join("|"), tc.rootB)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    nudge(store, ["c1", 6, "a1", 7])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 2, "one snapshot for the window")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootC, "A and C, in registry order")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(store.snapshotRunner.seq, seq + 2, "nothing more")
    compare(store.readRunners, undefined, "there are no run reads")
  }

  // 4
  function test_a_run_listed_by_two_roots_refreshes_both() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("s1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("s1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [])]), 0)
    compare(store.runById("s1").project.root, tc.rootA, "A won the de-duplication")
    nudge(store, ["s1", 5])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, "every root that lists it")
  }

  // 5 and Review Focus 3
  function test_a_partial_reply_keeps_the_other_roots_as_they_were() {
    var store = threeRoots(); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  failEntry(tc.rootC, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(toastIds(store), "a1")
    fire(store.staleTimer)
    compare(store.stale, true)
    var a1 = store.runById("a1")
    var c1 = store.runById("c1")
    nudge(store, ["b1", 9])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB),
                                                                     entry("b2", "done", false, tc.rootB)])]), 0)
    compare(ids(store.runs), "a1,b1,b2,c1", "B's runs replaced, the others kept, in registry order")
    verify(store.runById("a1") === a1, "an unrefreshed root's run is the same object")
    verify(store.runById("c1") === c1)
    compare(store.projectErrors[tc.rootC], "AmTimeout: am did not answer within 60 s.", "C's error stays")
    compare(store.projectErrors[tc.rootB], undefined)
    compare(toastIds(store), "a1,b1", "only b1 alerts: the unrefreshed a1 does not alert again")
    compare(store.stale, false, "a good partial reply clears stale")
    compare(store.staleTimer.running, true, "and restarts the clock")
    compare(store.amStatus, "ok")
  }

  // 6
  function test_a_window_with_an_unknown_id_refreshes_every_root_once() {
    var store = threeRoots(); if (!store) return
    var seq = store.snapshotRunner.seq
    // synthetic: a run no root lists, beside a listed one.
    nudge(store, ["b1", 5, "z9", 6])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "exactly one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC)
  }

  // 7
  function test_two_nudge_windows_during_a_snapshot_follow_up_with_their_roots_only() {
    var store = threeRoots(); if (!store) return
    store.refresh()
    var inFlight = store.snapshotRunner.current
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    nudge(store, ["c1", 6])
    fire(store.debounceTimer)
    reply(inFlight, threeReply(), 0)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB + "|" + tc.rootC, "B and C only")
  }

  // 11
  function test_stale_follows_any_good_reply_full_or_partial() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    fire(store.staleTimer)
    compare(store.stale, true, "no good reply for 30 s")
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    compare(store.stale, false, "a partial reply with one ok entry clears it")
    compare(store.staleTimer.running, true, "and restarts the clock")
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.stale, true, "every entry failed: stale stays")
    compare(store.staleTimer.running, false, "and the clock is untouched")
  }

  // Kept behaviour: a refresh that escalates a run raises one toast.
  function test_a_nudge_refresh_that_escalates_a_run_raises_one_toast() {
    var store = threeRoots(); if (!store) return
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(store.toasts.length, 1)
    compare(store.toasts[0].id, "b1")
    compare(store.toasts[0].state, "escalated")
    nudge(store, ["b1", 6])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(store.toasts.length, 1, "still escalated: no second toast")
  }

  // Kept behaviour: a refresh that moves the selected attempt refetches its logs.
  function test_a_nudge_refresh_that_moves_the_selected_attempt_fetches_its_logs() {
    var store = capturedStore(); if (!store) return
    store.selectedRunId = tc.startedRun
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var seq = store.logsRunner.seq
    nudge(store, [tc.startedRun, 990])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    // synthetic: the captured list with the started run's open attempt (explore 1) ok.
    var value = JSON.parse(capturedList())
    value.projects[0].runs[0].status.stories[1].subtasks[1].phases[1].attempts[0].status = "ok"
    reply(store.snapshotRunner.current, JSON.stringify(value) + "\n", 0)
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches the logs again")
    compare(argv(store.logsRunner.current), "python3|/plugin/core/backend/runs/runs-logs.py|" + tc.capRoot + "|" + tc.startedRun + "|" + tc.openCard + "|explore|1")
  }

  // Kept behaviour: a refresh that moves a run settles its pending request.
  function test_a_nudge_refresh_that_moves_the_run_settles_its_pending_request() {
    var store = capturedStore(); if (!store) return
    compare(store.control("cancel", tc.startedRun), true)
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.pending[tc.startedRun], "cancel", "acknowledged, not yet settled")
    nudge(store, [tc.startedRun, 1005])
    fire(store.debounceTimer)
    // synthetic: status-escalated.json's data under the started run's id.
    reply(store.snapshotRunner.current, capturedList([], true), 0)
    compare(store.pending[tc.startedRun], undefined, "the refresh settled it")
  }

  // Kept behaviour: a nudge after a project switch is still handled.
  function test_a_nudge_after_a_project_switch_is_still_handled() {
    var store = threeRoots(); if (!store) return
    store.project = tc.rootA
    store.project = tc.rootB
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runsNudged" })
    nudge(store, ["a1", 5])
    fire(store.debounceTimer)
    compare(spy.count, 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "the nudged run's root, whatever project is open")
    store.project = ""
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)])]), 0)
    compare(store.runById("a1").status, "escalated", "applied with no project open")
  }

  // The plan's Review Focus 1
  function test_a_partial_reply_that_is_am_missing_empties_every_root() {
    var store = threeRoots(); if (!store) return
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB)
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootB, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing", "am is on PATH or it is not: the whole store")
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0, "A's and C's runs go too")
    compare(Object.keys(store.projectErrors).length, 0)
    compare(store.alertsArmed, false)
  }

  // The plan's Review Focus 3
  function test_a_nudge_after_the_registry_emptied_announces_and_launches_nothing() {
    var store = threeRoots(); if (!store) return
    var w = store.watchProc
    store.projectRoots = []
    compare(store.runs.length, 0)
    verify(store.watchProc === w, "no snapshot, so the watch is not restarted")
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runsNudged" })
    var seq = store.snapshotRunner.seq
    nudge(store, ["a1", 5])
    fire(store.debounceTimer)
    compare(spy.count, 1, "announced")
    compare(store.snapshotRunner.seq, seq, "no root to snapshot")
    compare(store.snapshotRunner.busy, false)
    compare(store.pendingSnapshot, null)
  }

  // The plan's Review Focus 4
  function test_a_nudge_for_a_run_kept_by_a_failed_root_refreshes_that_root() {
    var store = threeRoots(); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s."),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(ids(store.runs), "a1,b1,c1", "B keeps its run")
    var seq = store.snapshotRunner.seq
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB, "B, not every root")
  }

  // ---- live refresh (3.2)
```

**d.** In `tests/core/stores/tst_run_store.qml`, find:

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

Replace it with:

```qml
  function test_a_nudge_for_a_listed_run_always_costs_a_snapshot_of_its_root() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.startedRun, 1, tc.doneRun, 900])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot, whatever the seqs")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    compare(Object.keys(store.nudges).length, 0, "the nudges were taken")
  }
```

**e.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    compare(store.readRunners.length, 0, "and no run read in that trigger")
```

Replace it with:

```qml
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
```

**f.** In `tests/core/stores/tst_run_store.qml`, delete every line from this line:

```qml
  // ---- run reads
```

up to, but not including, this line:

```qml
  // 12 (the control half)
```

That removes the whole `// ---- run reads` section (`readCmd`, `runReply`, `readOf` and every `test_a_read_*` / `*_read*` test in it) and the three run-read tests at the top of `// ---- reads, requests and logs across a project switch (3.1)` (`test_a_read_with_no_project_open_launches_applies_and_keeps_its_project`, `test_a_read_in_flight_at_a_project_switch_still_applies`, `test_a_run_kept_by_a_failed_root_reads_back_from_its_row`) together with that section heading. Edit **g** puts a new heading back.

**g.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  // 12 (the control half)
```

Replace it with:

```qml
  // ---- requests and logs across a project switch (3.1)

  // 12 (the control half)
```

**h.** In `tests/core/stores/tst_run_store.qml`, delete every line from this line:

```qml
  // ---- run read refusals (4.1.3)
```

up to, but not including, this line:

```qml
  // ---- cursor reset
```

That removes the `// ---- run read refusals (4.1.3)` section: `test_a_read_of_a_run_am_does_not_know_relists`, `test_a_busy_store_on_a_read_keeps_the_run_and_retries_it` and `test_a_busy_read_keeps_a_newer_nudge`.

**i.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
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
    compare(Object.keys(store.runsByProject).length, 0, "every root's list is forgotten too")
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot")
    var list = store.snapshotRunner.current
    reply(proc, runReply(tc.doneRun, "status-done.json"), 0)
    compare(store.runs.length, 0, "the dropped read changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    reply(list, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the first list after a reset only arms")
    compare(store.alertsArmed, true)
    compare(store.appliedSeq[tc.startedRun], 0)
  }
```

Replace it with:

```qml
  function test_a_cursor_reset_starts_over_from_a_list_snapshot() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    store.refresh()
    var old = store.snapshotRunner.current
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    sendLine(store.watchProc, resetHello(true))
    compare(store.amSchema, 2, "still a hello")
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0, "every root's list is forgotten too")
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(old.running, false, "the old store's snapshot is stopped")
    var list = store.snapshotRunner.current
    verify(list !== old, "one list snapshot is launched")
    compare(argv(list), tc.snapCmd + "|" + tc.capRoot)
    reply(old, capturedList(), 0)
    compare(store.runs.length, 0, "the stopped snapshot's late reply changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    reply(list, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the first list after a reset only arms")
    compare(store.alertsArmed, true)
    compare(store.appliedSeq[tc.startedRun], 0)
  }
```

**j.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_a_hello_from_another_store_starts_over_from_a_list_snapshot() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var proc = readOf(store, tc.doneRun, 1005)
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    var seq = store.snapshotRunner.seq
    // A head above the cursor: cursorReset is false, yet the store changed.
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    compare(store.amSchema, 2, "still a hello")
    compare(store.storeId, otherStore())
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
    compare(store.storeId, otherStore(), "the dropped read names no store")
    reply(list, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.appliedSeq[tc.startedRun], 0)
    compare(store.snapshotRunner.seq, seq + 1, "its reply launches no further snapshot")
  }
```

Replace it with:

```qml
  function test_a_hello_from_another_store_starts_over_from_a_list_snapshot() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    store.refresh()
    var old = store.snapshotRunner.current
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    // A head above the cursor: cursorReset is false, yet the store changed.
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    compare(store.amSchema, 2, "still a hello")
    compare(store.storeId, otherStore())
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(old.running, false, "the old store's snapshot is stopped")
    var list = store.snapshotRunner.current
    verify(list !== old, "one list snapshot is launched")
    var seq = store.snapshotRunner.seq
    reply(old, capturedList(), 0)
    compare(store.runs.length, 0, "the stopped snapshot's late reply changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    reply(list, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.appliedSeq[tc.startedRun], 0)
    compare(store.snapshotRunner.seq, seq, "its reply launches no further snapshot")
  }
```

**k.** In `tests/core/stores/tst_run_store.qml`, delete this text, and the blank line right before it:

```qml
  // synthetic: runReply(run, name) with store_id `id` (the key absent when
  // undefined).
  function storeRead(run, name, id) {
    var value = JSON.parse(runReply(run, name))
    value.store_id = id
    return JSON.stringify(value) + "\n"
  }

  function test_a_run_read_from_another_store_is_not_applied_and_starts_over() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var proc = readOf(store, tc.startedRun, 1005)
    var seq = store.snapshotRunner.seq
    reply(proc, storeRead(tc.startedRun, "status-escalated.json", otherStore()), 0)
    compare(store.storeId, otherStore())
    compare(store.appliedSeq[tc.startedRun], undefined, "not applied: the coverage starts over")
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    compare(store.toasts.length, 0, "the escalation is not alerted")
    compare(store.lastError, "")
    compare(store.amStatus, "ok")
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot")
    reply(store.snapshotRunner.current, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
    compare(store.snapshotRunner.seq, seq + 1, "its reply launches no further snapshot")
  }

  function test_a_run_read_with_the_seen_or_a_first_store_id_is_applied() {
    var store = namedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    reply(readOf(store, tc.doneRun, 1005), runReply(tc.doneRun, "status-done.json"), 0)
    compare(store.appliedSeq[tc.doneRun], 1005, "the seen store")
    compare(store.storeId, fixtureStore())
    compare(store.snapshotRunner.seq, seq)
    var fresh = capturedStore(); if (!fresh) return
    var freshSeq = fresh.snapshotRunner.seq
    reply(readOf(fresh, tc.doneRun, 1005), runReply(tc.doneRun, "status-done.json"), 0)
    compare(fresh.appliedSeq[tc.doneRun], 1005, "a first store id")
    compare(fresh.storeId, fixtureStore(), "is recorded")
    compare(fresh.snapshotRunner.seq, freshSeq)
  }

  function test_a_run_read_without_a_store_id_is_applied() {
    var store = namedStore(); if (!store) return
    var bad = ["", 7, null, { id: "x" }, undefined]
    for (var i = 0; i < bad.length; i++) {
      var label = "store_id " + JSON.stringify(bad[i])
      var proc = readOf(store, tc.doneRun, 1006 + i)
      var seq = store.snapshotRunner.seq
      reply(proc, storeRead(tc.doneRun, "status-done.json", bad[i]), 0)
      compare(store.appliedSeq[tc.doneRun], 1005, label)
      compare(store.storeId, fixtureStore(), label)
      compare(store.runs.length, 2, label)
      compare(store.snapshotRunner.seq, seq, label + ": no list snapshot")
    }
  }

  function test_a_refused_run_read_naming_another_store_changes_no_store_id() {
    var store = namedStore(); if (!store) return
    var proc = readOf(store, tc.doneRun, 1005)
    // synthetic: am's StoreBusyError envelope carrying another store's id.
    reply(proc, JSON.stringify({ ok: false, store_id: otherStore(),
          error: { type: "StoreBusyError", message: "the am store is busy; try again" } }) + "\n", 1)
    compare(store.storeId, fixtureStore())
    compare(store.stale, true)
    compare(store.runs.length, 2)
  }

  // Review Focus 2.
  function test_a_superseded_run_read_naming_another_store_changes_nothing() {
    var store = namedStore(); if (!store) return
    var older = readOf(store, tc.doneRun, 1000)
    readOf(store, tc.doneRun, 1005)
    var seq = store.snapshotRunner.seq
    reply(older, storeRead(tc.doneRun, "status-done.json", otherStore()), 0)
    compare(store.storeId, fixtureStore())
    compare(store.runs.length, 2)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
  }
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
(`tests/run.sh` runs the whole pytest suite first, about two minutes, then the one QML file. Only the `== tests/core/stores/tst_run_store.qml` block matters here.)
Expected: `Totals: 249 passed, 11 failed`. These fail:
  - `test_a_debounce_firing_announces_its_run_ids_once`
  - `test_a_list_covers_every_listed_run_at_0_and_nudges_follow_it`
  - `test_a_nudge_after_a_project_switch_is_still_handled`
  - `test_a_nudge_after_the_registry_emptied_announces_and_launches_nothing`
  - `test_a_nudge_for_a_listed_run_always_costs_a_snapshot_of_its_root`
  - `test_a_nudge_for_a_run_kept_by_a_failed_root_refreshes_that_root`
  - `test_a_nudge_refreshes_only_the_roots_that_list_its_runs`
  - `test_a_partial_reply_keeps_the_other_roots_as_they_were`
  - `test_a_partial_reply_that_is_am_missing_empties_every_root`
  - `test_a_run_listed_by_two_roots_refreshes_both`
  - `test_two_nudge_windows_during_a_snapshot_follow_up_with_their_roots_only`

The other new tests already pass. Run reads still exist at this point, and those tests pin rules that hold either way: an unknown id refreshes every root, stale, and the kept behaviours.

- [ ] **Step 3: Write the implementation**

Apply these edits to `core/stores/RunStore.qml`, in order:

**a.** In `core/stores/RunStore.qml`, find:

```qml
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
```

Replace it with:

```qml
// runs-watch.py nudges it, "run X changed at seq N", and is never folded
// into state: once per debounce window the nudged run ids are announced
// (runsNudged) and the roots that list them are snapshotted, or every root
// when one id is unknown. A cursorReset hello starts over from a list
// snapshot, as does a hello naming a store_id other than the one last seen
// (storeId); the first store_id seen resets nothing. watchCursor is the
// watch's last cursor, held in memory only. Logs are fetched on a
// selection, on Refresh and when a snapshot changes the selected attempt's
// status -- never on a timer.
```

**b.** In `core/stores/RunStore.qml`, find:

```qml
  // Snapshot coverage. `asOfSeq` is 0: the list snapshot names no as_of_seq.
  // `appliedSeq` is {runId: seq}: 0 for every run the last list put in
  // `runs`, then the as_of_seq of each run read applied since. Both are
  // replaced, never changed in place.
```

Replace it with:

```qml
  // Snapshot coverage. `asOfSeq` is 0: the list snapshot names no as_of_seq.
  // `appliedSeq` is {runId: 0} for every run in `runs`: the run ids the store
  // knows. Both are replaced, never changed in place.
```

**c.** In `core/stores/RunStore.qml`, find:

```qml
  // am's store_id from the last hello or run read that named one; "" = none
  // yet. Replaced, never derived. A project switch, the watch ending and
  // AmMissing keep it.
```

Replace it with:

```qml
  // am's store_id from the last watch hello that named one; "" = none yet.
  // Replaced, never derived. A project switch, the watch ending and AmMissing
  // keep it.
```

**d.** In `core/stores/RunStore.qml`, find:

```qml
  signal dispatchStarted(var runId)
```

Replace it with:

```qml
  signal dispatchStarted(var runId)
  // A debounce window's nudged run ids, each once, in first-nudge order,
  // known to the store or not. Never for a snapshot the store started itself.
  // (`runs` already owns the runsChanged name.)
  signal runsNudged(var ids)
```

**e.** In `core/stores/RunStore.qml`, delete this text:

```qml
  readonly property alias readRunners: readState.runners  // in-flight run reads, oldest first
```

**f.** In `core/stores/RunStore.qml`, find:

```qml
  // The debounce fired: the nudges are taken. A nudge for a run appliedSeq
  // does not know costs one list snapshot, which covers every run, and no run
  // read. Otherwise each nudge newer than appliedSeq[run] for a run in `runs`
  // costs one run read, in nudge order. A nudge no newer than
  // appliedSeq[run], or for a run no longer in `runs`, is ignored.
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

Replace it with:

```qml
  // The debounce fired: the nudges are taken and, when there were any, their
  // run ids are announced once (runsNudged), then one snapshot is requested:
  // of every root when an id is listed by no usable root, else of every
  // usable root whose runsByProject list holds one of the ids. The seqs gate
  // nothing.
  function triggerNudges() {
    var ids = Object.keys(store.nudges)
    store.nudges = {}
    if (ids.length === 0) return
    store.runsNudged(ids)
    var usable = store.usableRoots()
    var roots = []
    for (var i = 0; i < ids.length; i++) {
      var listed = false
      for (var j = 0; j < usable.length; j++) {
        if (!store.listsRun(usable[j].root, ids[i])) continue
        listed = true
        if (roots.indexOf(usable[j].root) < 0) roots.push(usable[j].root)
      }
      if (!listed) {
        store.refresh()
        return
      }
    }
    store.requestSnapshot(roots)
  }

  // root's runsByProject list holds a run with this id.
  function listsRun(root, id) {
    var list = store.hasKey(store.runsByProject, root) ? store.runsByProject[root] : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] !== null && typeof list[i] === "object" && list[i].id === id) return true
    }
    return false
  }
```

**g.** In `core/stores/RunStore.qml`, find:

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
```

Replace it with:

```qml
  // The live state of the store last seen is forgotten: the cursor, the
  // nudges and their debounce, the runs and every root's list of them, and
  // the alerts (the next list snapshot only arms). Selection, logs, controls
  // and dispatch stay.
  function forgetLive() {
    store.watchCursor = 0
    store.nudges = {}
    debounceTimer.stop()
```

**h.** In `core/stores/RunStore.qml`, find:

```qml
  // A store id seen in a hello or a good run read. A non-empty string is
  // recorded as storeId; anything else is no store id and changes nothing.
```

Replace it with:

```qml
  // A store id seen in a hello. A non-empty string is recorded as storeId;
  // anything else is no store id and changes nothing.
```

**i.** In `core/stores/RunStore.qml`, delete this text, and the blank line right after it:

```qml
  // A path without its trailing "/" characters; a lone "/" stays "/".
  function trimSlashes(path) {
    var s = path
    while (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.slice(0, -1)
    return s
  }
```

**j.** In `core/stores/RunStore.qml`, find:

```qml
  // root's runs ([] when it had none) and records Runs.errorText of its
  // error; a usable root with no entry keeps both. `runs` is merged again,
  // asOfSeq is 0, appliedSeq {id: 0} for every run in it, and readState.rows
  // each kept run's `am runs` row: the winning root's from this reply, else
  // the row kept from before. With an entry ok, everything after a good
  // snapshot follows. With none, amStatus is "error" with the first failed
  // entry's sentence, and the alerts and `stale` stay as they are.
```

Replace it with:

```qml
  // root's runs ([] when it had none) and records Runs.errorText of its
  // error; a usable root with no entry keeps both. `runs` is merged again,
  // and asOfSeq is 0 and appliedSeq {id: 0} for every run in it. With an
  // entry ok, everything after a good snapshot follows. With none, amStatus
  // is "error" with the first failed entry's sentence, and the alerts and
  // `stale` stay as they are.
```

**k.** In `core/stores/RunStore.qml`, find:

```qml
    var errors = store.copyMap(store.projectErrors)
    var fresh = {}          // {root: {id: am runs row}} of this reply's ok entries
    var anyOk = false
```

Replace it with:

```qml
    var errors = store.copyMap(store.projectErrors)
    var anyOk = false
```

**l.** In `core/stores/RunStore.qml`, find:

```qml
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
```

Replace it with:

```qml
        var out = []
        for (var r = 0; r < list.length; r++) {
          var item = list[r]
          if (item === null || typeof item !== "object" || Array.isArray(item)) continue
          out.push(Runs.withProject(Runs.normalizeRun({ row: store.rowOf(item), status: item.status }), root, names[root]))
        }
        byProject[root] = out
        delete errors[root]
```

**m.** In `core/stores/RunStore.qml`, find:

```qml
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
```

Replace it with:

```qml
    var applied = {}
    var ids = Object.keys(merged.owner)
    for (var d = 0; d < ids.length; d++) applied[ids[d]] = 0
```

**n.** In `core/stores/RunStore.qml`, find:

```qml
    store.appliedSeq = applied
    readState.rows = keptRows
    store.runs = merged.runs
```

Replace it with:

```qml
    store.appliedSeq = applied
    store.runs = merged.runs
```

**o.** In `core/stores/RunStore.qml`, delete every line from this line:

```qml
  // ---- run reads
```

up to, but not including, this line:

```qml
  // ---- run controls (S2 4.1)
```

That removes the `// ---- run reads` section of the store: `readRun`, `dropReads`, `readReplied`, `keepNudge`, `applyRunRead` and `withRun` with their comments.

**p.** In `core/stores/RunStore.qml`, delete this text, and the blank line right after it:

```qml
  // The run reads' own state; kept apart so consumers cannot write it.
  // `runners` are the reads in flight, oldest first; `latest` is {runId:
  // runner}, the read whose reply counts; `rows` is {runId: am runs row} of
  // the runs in `runs`, which a run read rebuilds from.
  QtObject {
    id: readState
    property var runners: []
    property var latest: ({})
    property var rows: ({})
  }
```

**q.** In `core/stores/RunStore.qml`, delete this text, and the blank line right after it:

```qml
  // One HelperRunner per run read, so reads of different runs run in
  // parallel. Guard "": readReplied checks the latest read itself, so every
  // exit lands there and the runner always goes.
  Component {
    id: readC

    HelperRunner {
      id: rr
      property string runId: ""
      property int nudgeSeq: 0        // the nudge seq it was launched for
      script: store.backendDir + "runs/runs-snapshot.py"
      guard: ""
      onFinished: function(stdout, exitCode) { store.readReplied(rr, stdout) }
    }
  }
```


Then confirm that nothing refers to the removed names:

Run: `grep -n "readState\|readRun\|readC\b\|applyRunRead\|keepNudge\|withRun\|trimSlashes\|dropReads\|readReplied\|run read" core/stores/RunStore.qml`
Expected: no output.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 260 passed, 0 failed, 0 skipped`, with no `TypeError` / `ReferenceError` / `is not a function` line.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): a nudge announces its runs and refreshes only the roots that list them"
```

---

### Task 3: The liveness tick covers only the roots with a running run

Covers spec §4, §7's `livenessTimer` comment, spec test 10, test 7's liveness half, and the `test_liveness_tick_refreshes` rewrite.

**Files:**
- Modify: `core/stores/RunStore.qml`: a new `refreshLive` before `resetCursor`; the `livenessTimer` Timer
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `requestSnapshot(roots: string[])` (Task 1), `usableRoots()`, `runsByProject`, and `Runs.runState(run) === "running"` (`core/domain/runs.js`, unchanged).
- Produces: `function refreshLive()`, which requests the usable roots whose `runsByProject` list holds a running run, in registry order. With none it requests nothing. `livenessTimer.onTriggered` calls it.

- [ ] **Step 1: Write the failing tests**

Apply these edits to `tests/core/stores/tst_run_store.qml`, in order:

**a.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  // 11
  function test_stale_follows_any_good_reply_full_or_partial() {
```

Replace it with:

```qml
  // 7 and Review Focus 1
  function test_nudges_and_liveness_during_a_snapshot_give_one_follow_up() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var first = allReply([okEntry(tc.rootA, [entry("a1", "started", true)]), okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                          okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])])
    reply(store.snapshotRunner.current, first, 0)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    nudge(store, ["c1", 6])
    fire(store.debounceTimer)
    store.livenessTimer.triggered()
    verify(store.snapshotRunner.current === inFlight, "the snapshot in flight is kept")
    compare(inFlight.running, true)
    compare(store.snapshotRunner.seq, seq)
    compare(store.pendingSnapshot.join("|"), [tc.rootB, tc.rootC, tc.rootA].join("|"), "one pending request")
    reply(inFlight, first, 0)
    compare(store.snapshotRunner.seq, seq + 1, "one follow-up")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC,
            "the union, in registry order")
    reply(store.snapshotRunner.current, first, 0)
    compare(store.snapshotRunner.seq, seq + 1, "nothing more")
  }

  // 10
  function test_a_liveness_tick_refreshes_only_the_roots_with_a_running_run() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "started", true)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "started", false, tc.rootC)])]), 0)
    compare(store.livenessTimer.running, true)
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "A alone: C's run is dead, B's done")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "started", true)])]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "started", true)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "started", true, tc.rootC)])]), 0)
    store.livenessTimer.triggered()
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootC, "A and C")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(store.livenessTimer.running, false, "no running run: the timer is off")
    var idle = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, idle, "a forced tick launches nothing")
  }

  // 11
  function test_stale_follows_any_good_reply_full_or_partial() {
```

**b.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
    compare(store.snapshotRunner.seq, seq + 1, "each tick fetches a snapshot")
```

Replace it with:

```qml
    compare(store.snapshotRunner.seq, seq + 1, "each tick fetches a snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "of the root with the running run")
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
(`tests/run.sh` runs the whole pytest suite first, about two minutes, then the one QML file. Only the `== tests/core/stores/tst_run_store.qml` block matters here.)
Expected: `Totals: 260 passed, 2 failed`. These fail:
  - `test_a_liveness_tick_refreshes_only_the_roots_with_a_running_run`
  - `test_nudges_and_liveness_during_a_snapshot_give_one_follow_up`

`test_liveness_tick_refreshes` already passes: its store has one root, so "every root" and "the running root" are the same argv.

- [ ] **Step 3: Write the implementation**

Apply these edits to `core/stores/RunStore.qml`, in order:

**a.** In `core/stores/RunStore.qml`, find:

```qml
  // Starts over: the snapshot in flight (the old store's) is stopped and the
```

Replace it with:

```qml
  // The liveness tick: a snapshot of the usable roots whose runsByProject
  // list holds a running run, in registry order; none, nothing.
  function refreshLive() {
    var usable = store.usableRoots()
    var roots = []
    for (var i = 0; i < usable.length; i++) {
      var list = store.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []
      for (var j = 0; j < list.length; j++) {
        if (Runs.runState(list[j]) === "running") {
          roots.push(usable[i].root)
          break
        }
      }
    }
    if (roots.length > 0) store.requestSnapshot(roots)
  }

  // Starts over: the snapshot in flight (the old store's) is stopped and the
```

**b.** In `core/stores/RunStore.qml`, find:

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
```

Replace it with:

```qml
  // Only while the panel is open and a run is running: no timer while idle.
  // Each tick snapshots the roots with a running run (refreshLive).
  Timer {
    id: livenessTimer
    objectName: "livenessTimer"
    interval: 10000
    repeat: true
    running: store.active && store.hasRunningRun
    onTriggered: store.refreshLive()
  }
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 262 passed, 0 failed, 0 skipped`, with no `TypeError` / `ReferenceError` / `is not a function` line.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): the liveness tick refreshes only the roots with a running run"
```

---

### Task 4: The watch argv names every absolute root and every known run id, and restarts on a new root set

Covers spec §5, §7's header and `startWatch` comments, spec tests 1, 2 and 12, and the watch-argv rewrites. Also the plan's Review Focus 2 and 5. Ends with the full gate.

**Files:**
- Modify: `core/stores/RunStore.qml`: the header comment; the `watchTried` comment; a new `watchRoots` alias; `startWatch` plus the new `watchableRoots`, `knownRunIds` and `sameRoots`; `applyProjects` (its comment and the restart); the `watchState` QtObject
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `usableRoots()`, `runsByProject`, `stopWatch()` (bumps `watchSeq`, stops the process, sets `watching` false, forgets the hello) and `hasKey`.
- Produces:
  - `function watchableRoots(): string[]`: the usable roots, in registry order, that begin with `/`.
  - `function knownRunIds(): string[]`: run ids from the usable roots' `runsByProject` lists, in registry order then list order, each once. An id that is empty or begins with `-` or `/` is left out.
  - `function sameRoots(a: string[], b: string[]): bool`: compares the two lists as sets.
  - `startWatch()`: argv `["python3", backendDir + "runs/runs-watch.py"].concat(roots, knownRunIds())`. With no root it launches nothing, `watchTried` becomes true and `watching` stays false.
  - `readonly property alias watchRoots` (`string[]`): the roots the current watch was launched with, held in `watchState.roots`.
  - `applyProjects`: after a good reply while `active` and `watching`, if `!sameRoots(watchState.roots, watchableRoots())`, it calls `stopWatch()` then `startWatch()`.

- [ ] **Step 1: Write the failing tests**

Apply these edits to `tests/core/stores/tst_run_store.qml`, in order. Edits **b**–**e** rewrite the four tests that asserted the argument-free argv (`command.length === 2`). Edit **f** adds the section `// ---- the watch argv (global 3.2)`. Edit **g** changes the argv assertion that Task 1 left in `test_reactivation_starts_a_new_watch`.

**a.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
```

Replace it with:

```qml
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
  property string watchCmd: "python3|/plugin/core/backend/runs/runs-watch.py"
```

**b.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_watch_argv_after_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("b", "done", false)]), 0)
    compare(store.runs.length, 2)
    var w = store.watchProc
    verify(w, "the first good snapshot starts the watch")
    compare(w.objectName, "watchProc")
    compare(w.command.length, 2, "no project, no run ids, no --since-seq")
    compare(w.command[0], "python3")
    compare(w.command[1], "/plugin/core/backend/runs/runs-watch.py")
    compare(w.running, true)
    compare(store.watching, true)
  }
```

Replace it with:

```qml
  function test_watch_argv_after_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("b", "done", false)]), 0)
    compare(store.runs.length, 2)
    var w = store.watchProc
    verify(w, "the first good snapshot starts the watch")
    compare(w.objectName, "watchProc")
    compare(JSON.stringify(w.command), JSON.stringify(["python3", "/plugin/core/backend/runs/runs-watch.py", tc.rootA, "a", "b"]),
            "the root, then the run ids, and no --since-seq")
    compare(w.running, true)
    compare(store.watching, true)
  }
```

**c.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_watch_with_no_runs_watches_the_project_alone() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var w = store.watchProc
    verify(w, "an empty project is watched too: its first run must show up")
    compare(w.command.length, 2)
    compare(w.running, true)
    compare(store.watching, true)
  }
```

Replace it with:

```qml
  function test_watch_with_no_runs_watches_the_project_alone() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var w = store.watchProc
    verify(w, "an empty project is watched too: its first run must show up")
    compare(argv(w), tc.watchCmd + "|" + tc.rootA, "the root alone")
    compare(w.running, true)
    compare(store.watching, true)
  }
```

**d.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_failed_first_snapshot_does_not_start_watch() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n', 1)
    verify(!store.watchProc, "a failed snapshot starts no watch")
    compare(store.watching, false)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(store.watchProc.command.length, 2)
    compare(store.watching, true)
  }
```

Replace it with:

```qml
  function test_failed_first_snapshot_does_not_start_watch() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n', 1)
    verify(!store.watchProc, "a failed snapshot starts no watch")
    compare(store.watching, false)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(argv(store.watchProc), tc.watchCmd + "|" + tc.rootA + "|a")
    compare(store.watching, true)
  }
```

**e.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  function test_second_snapshot_does_not_restart_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("c", "started", true)]), 0)
    verify(store.watchProc === w, "the running watch is kept")
    compare(w.running, true)
    compare(w.command.length, 2, "its argv is not rewritten: the helper watches every run itself")
  }
```

Replace it with:

```qml
  function test_second_snapshot_does_not_restart_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("c", "started", true)]), 0)
    verify(store.watchProc === w, "the running watch is kept")
    compare(w.running, true)
    compare(argv(w), tc.watchCmd + "|" + tc.rootA + "|a", "its argv is not rewritten: the helper picks up a watched root's new runs itself")
  }
```

**f.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
  // ---- debounce

  // One stdout line of a watch
```

Replace it with:

```qml
  // ---- the watch argv (global 3.2)

  // 1 and Review Focus 2
  function test_the_watch_names_every_root_then_every_known_run_id() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    var w = store.watchProc
    verify(w, "the first good reply starts the watch")
    compare(JSON.stringify(w.command), JSON.stringify(["python3", "/plugin/core/backend/runs/runs-watch.py", tc.rootA, tc.rootB, "a1", "b1"]))
    compare(w.command[2], tc.rootA, "a root with a space is one argument")
    compare(store.watchRoots.join("|"), tc.rootA + "|" + tc.rootB)
  }

  // 1 and Review Focus 2
  function test_the_watch_leaves_out_ids_and_roots_the_helper_would_refuse() {
    var store = make(); if (!store) return
    store.active = true
    store.projectRoots = [rootEntry(tc.rootA), { root: "rel/proj", name: "rel" }, rootEntry(tc.rootB)]
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|rel/proj|" + tc.rootB,
            "the snapshot still names every usable root")
    // synthetic: run ids runs-watch.py would refuse or read as roots, and a run listed under two roots.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("", "done", false), entry("-x", "done", false),
                                                                     entry("/x", "done", false), entry("a1", "done", false)]),
                                                  okEntry("rel/proj", [entry("r1", "done", false, "rel/proj")]),
                                                  okEntry(tc.rootB, [entry("a1", "done", false, tc.rootB)])]), 0)
    compare(JSON.stringify(store.watchProc.command),
            JSON.stringify(["python3", "/plugin/core/backend/runs/runs-watch.py", tc.rootA, tc.rootB, "a1", "r1"]),
            "no relative root, no refused id, a1 once")
  }

  // 1
  function test_with_no_runs_the_watch_names_the_roots_alone() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(argv(store.watchProc), tc.watchCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // 2
  function test_with_no_absolute_root_no_watch_is_launched() {
    var store = make(); if (!store) return
    store.active = true
    store.projectRoots = [{ root: "rel/proj", name: "rel" }]
    var good = allReply([okEntry("rel/proj", [entry("r1", "done", false, "rel/proj")])])
    reply(store.snapshotRunner.current, good, 0)
    compare(store.amStatus, "ok")
    verify(!store.watchProc, "no root the helper reads as a root: no watch")
    compare(store.watching, false)
    var seq = store.watchSeq
    store.refresh()
    reply(store.snapshotRunner.current, good, 0)
    verify(!store.watchProc, "a second good reply does not try again")
    compare(store.watching, false)
    compare(store.watchSeq, seq)
  }

  // 12 and Review Focus 5
  function test_a_new_root_set_restarts_a_running_watch() {
    var store = activeRoots([tc.rootA]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    var first = store.watchProc
    compare(argv(first), tc.watchCmd + "|" + tc.rootA + "|a1")
    store.projectRoots = registry([tc.rootA, tc.rootC])
    verify(store.watchProc === first, "a registry change alone restarts nothing")
    var both = allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])])
    reply(store.snapshotRunner.current, both, 0)
    var second = store.watchProc
    verify(second !== first, "the good reply for the new roots restarts the watch")
    compare(first.running, false, "the old watch is stopped")
    compare(argv(second), tc.watchCmd + "|" + tc.rootA + "|" + tc.rootC + "|a1|c1", "with C and its run ids")
    compare(second.running, true)
    compare(store.watching, true)
    store.refresh()
    reply(store.snapshotRunner.current, both, 0)
    verify(store.watchProc === second, "the same roots keep the watch")
    store.projectRoots = registry([tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    var third = store.watchProc
    verify(third !== second, "removing C restarts it too")
    compare(second.running, false)
    compare(argv(third), tc.watchCmd + "|" + tc.rootA + "|a1")
  }

  // 12
  function test_a_watch_that_ended_is_not_restarted_by_a_new_root_set() {
    var types = [["HelperError", 1], ["SchemaMismatch", 1]]
    for (var i = 0; i < types.length; i++) {
      var label = types[i][0]
      var store = activeRoots([tc.rootA]); if (!store) return
      reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
      endWatch(store.watchProc, watchError(types[i][0], "m"), types[i][1])
      compare(store.watching, false, label)
      var seq = store.watchSeq
      store.projectRoots = registry([tc.rootA, tc.rootC])
      reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootC, [])]), 0)
      compare(store.watchSeq, seq, label + ": no watch is started until the next opening")
      compare(store.watching, false, label)
    }
  }

  // The plan's Review Focus 2
  function test_a_reordered_or_renamed_registry_keeps_the_watch() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    var good = allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])])
    reply(store.snapshotRunner.current, good, 0)
    var w = store.watchProc
    store.projectRoots = [{ root: tc.rootB, name: "bee" }, rootEntry(tc.rootA)]
    reply(store.snapshotRunner.current, good, 0)
    verify(store.watchProc === w, "the same roots in another order, under another name, keep the watch")
    compare(w.running, true)
    compare(store.watchRoots.join("|"), tc.rootA + "|" + tc.rootB, "the roots it was launched with")
  }

  // The plan's Review Focus 5
  function test_a_restart_with_no_absolute_root_left_launches_no_watch() {
    var store = make(); if (!store) return
    store.active = true
    store.projectRoots = [rootEntry(tc.rootA), { root: "rel/proj", name: "rel" }]
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry("rel/proj", [])]), 0)
    var w = store.watchProc
    compare(argv(w), tc.watchCmd + "|" + tc.rootA)
    store.projectRoots = [{ root: "rel/proj", name: "rel" }]
    reply(store.snapshotRunner.current, allReply([okEntry("rel/proj", [entry("r1", "done", false, "rel/proj")])]), 0)
    compare(w.running, false, "the old watch is stopped")
    compare(store.watching, false, "and none replaces it: no root the helper reads as a root")
    var seq = store.watchSeq
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry("rel/proj", [])]), 0)
    compare(store.watchSeq, seq, "later replies do not try again")
    compare(store.amStatus, "ok")
  }

  // ---- debounce

  // One stdout line of a watch
```

**g.** In `tests/core/stores/tst_run_store.qml`, find:

```qml
    compare(fresh.running, true)
    compare(fresh.command.length, 2)
```

Replace it with:

```qml
    compare(fresh.running, true)
    compare(argv(fresh), tc.watchCmd + "|" + tc.rootA + "|a")
```


- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh run_store`
(`tests/run.sh` runs the whole pytest suite first, about two minutes, then the one QML file. Only the `== tests/core/stores/tst_run_store.qml` block matters here.)
Expected: `Totals: 258 passed, 12 failed`. These fail:
  - `test_a_new_root_set_restarts_a_running_watch`
  - `test_a_reordered_or_renamed_registry_keeps_the_watch`
  - `test_a_restart_with_no_absolute_root_left_launches_no_watch`
  - `test_failed_first_snapshot_does_not_start_watch`
  - `test_reactivation_starts_a_new_watch`
  - `test_second_snapshot_does_not_restart_watch`
  - `test_the_watch_leaves_out_ids_and_roots_the_helper_would_refuse`
  - `test_the_watch_names_every_root_then_every_known_run_id`
  - `test_watch_argv_after_first_snapshot`
  - `test_watch_with_no_runs_watches_the_project_alone`
  - `test_with_no_absolute_root_no_watch_is_launched`
  - `test_with_no_runs_the_watch_names_the_roots_alone`

- [ ] **Step 3: Write the implementation**

Apply these edits to `core/stores/RunStore.qml`, in order:

**a.** In `core/stores/RunStore.qml`, find:

```qml
// request launches. While `active` (the panel is open) a long-lived
// runs-watch.py nudges it, "run X changed at seq N", and is never folded
// into state: once per debounce window the nudged run ids are announced
// (runsNudged) and the roots that list them are snapshotted, or every root
// when one id is unknown. A cursorReset hello starts over from a list
// snapshot, as does a hello naming a store_id other than the one last seen
// (storeId); the first store_id seen resets nothing. watchCursor is the
// watch's last cursor, held in memory only. Logs are fetched on a
// selection, on Refresh and when a snapshot changes the selected attempt's
// status -- never on a timer.
```

Replace it with:

```qml
// request launches. While `active` (the panel is open) a long-lived
// runs-watch.py, given every usable root that begins with "/" and every
// known run id (startWatch), nudges it, "run X changed at seq N", and is
// never folded into state: once per debounce window the nudged run ids are
// announced (runsNudged) and the roots that list them are snapshotted, or
// every root when one id is unknown. A cursorReset hello starts over from a
// list snapshot, as does a hello naming a store_id other than the one last
// seen (storeId); the first store_id seen resets nothing. watchCursor is
// the watch's last cursor, held in memory only. Logs are fetched on a
// selection, on Refresh and when a snapshot changes the selected attempt's
// status -- never on a timer.
```

**b.** In `core/stores/RunStore.qml`, find:

```qml
  // A watch has been started since the last activation: later snapshots never
  // start another (the helper picks up new runs itself), and a watch that
  // ended is not restarted until the next activation.
```

Replace it with:

```qml
  // A watch has been started (or found no root to watch) since the last
  // activation: a later good snapshot starts another only while the watch
  // runs and the usable "/" roots changed (the helper picks up a watched
  // root's new runs itself), and a watch that ended is not restarted until
  // the next activation.
```

**c.** In `core/stores/RunStore.qml`, find:

```qml
  readonly property alias watchProc: watchState.proc      // the current watch Process, or null
```

Replace it with:

```qml
  readonly property alias watchProc: watchState.proc      // the current watch Process, or null
  readonly property alias watchRoots: watchState.roots    // the roots the current watch was launched with
```

**d.** In `core/stores/RunStore.qml`, find:

```qml
  // runs-watch.py with no argument: every project's nudges, from now.
  // Long-lived, so a plain Process rather than the HelperRunner. It starts
  // with am's schema and version unknown until its own hello.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    store.forgetHello()
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq })
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py"]
    watchState.proc = proc
    watchState.watching = true
    proc.running = true
  }
```

Replace it with:

```qml
  // runs-watch.py ROOT... RUN...: the usable roots that begin with "/"
  // (watchableRoots), then the known run ids (knownRunIds), from now. No
  // root: no watch is launched, and watchTried keeps later snapshots from
  // trying again. Long-lived, so a plain Process rather than the
  // HelperRunner. It starts with am's schema and version unknown until its
  // own hello.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    store.forgetHello()
    var roots = store.watchableRoots()
    if (roots.length === 0) return
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq })
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py"].concat(roots, store.knownRunIds())
    watchState.proc = proc
    watchState.roots = roots
    watchState.watching = true
    proc.running = true
  }

  // The usable roots, in registry order, that begin with "/": runs-watch.py
  // reads any other argument as a run id.
  function watchableRoots() {
    return store.usableRoots().map(function(p) { return p.root }).filter(function(root) {
      return root.charAt(0) === "/"
    })
  }

  // Every run id the usable roots' runsByProject lists hold, in registry
  // order then list order, each once. An id that is empty or begins with "-"
  // or "/" is left out: runs-watch.py refuses or misreads it.
  function knownRunIds() {
    var usable = store.usableRoots()
    var out = []
    var seen = {}
    for (var i = 0; i < usable.length; i++) {
      var list = store.hasKey(store.runsByProject, usable[i].root) ? store.runsByProject[usable[i].root] : []
      for (var j = 0; j < list.length; j++) {
        var run = list[j]
        var id = run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
        if (id === "" || id.charAt(0) === "-" || id.charAt(0) === "/" || store.hasKey(seen, id)) continue
        seen[id] = true
        out.push(id)
      }
    }
    return out
  }

  // Two root lists hold the same roots, whatever their order.
  function sameRoots(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) {
      if (b.indexOf(a[i]) < 0) return false
    }
    return true
  }
```

**e.** In `core/stores/RunStore.qml`, find:

```qml
  // and asOfSeq is 0 and appliedSeq {id: 0} for every run in it. With an
  // entry ok, everything after a good snapshot follows. With none, amStatus
  // is "error" with the first failed entry's sentence, and the alerts and
  // `stale` stay as they are.
```

Replace it with:

```qml
  // and asOfSeq is 0 and appliedSeq {id: 0} for every run in it. With an
  // entry ok, everything after a good snapshot follows, and while active a
  // running watch whose roots are no longer the usable "/" roots is started
  // again. With none, amStatus is "error" with the first failed entry's
  // sentence, and the alerts and `stale` stay as they are.
```

**f.** In `core/stores/RunStore.qml`, find:

```qml
      if (!store.watchTried) store.startWatch()
      store.raiseAlerts(alerts)
```

Replace it with:

```qml
      if (!store.watchTried) store.startWatch()
      else if (store.watching && !store.sameRoots(watchState.roots, store.watchableRoots())) {
        store.stopWatch()
        store.startWatch()
      }
      store.raiseAlerts(alerts)
```

**g.** In `core/stores/RunStore.qml`, find:

```qml
  // What the watch Process aliases read; kept apart so consumers cannot write it.
  QtObject {
    id: watchState
    property var proc: null
    property bool watching: false
  }
```

Replace it with:

```qml
  // What the watch Process aliases read; kept apart so consumers cannot write it.
  // `roots` are the roots the current watch was launched with.
  QtObject {
    id: watchState
    property var proc: null
    property bool watching: false
    property var roots: []
  }
```


- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh run_store`
Expected: `Totals: 270 passed, 0 failed, 0 skipped`, with no `TypeError` / `ReferenceError` / `is not a function` line.

- [ ] **Step 5: Run the full gate**

Run: `bash tests/run.sh; echo "exit $?"`
Expected: pytest passes (`1304 passed`, or whatever count pytest reports at HEAD; this plan changes no Python). Every `== tests/...qml` block shows `Totals: N passed, 0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `is not a function` line is printed, and the last line is `exit 0`. `tst_app_runs.qml` and `tests/ui/**` pass unchanged. If one of them fails, it is a test that launched a second snapshot over a running one. Answer the first snapshot in that test before expecting the second (spec "Other tiers"), and change nothing else.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): the watch names every root and known run id and restarts on a new root set"
```

---

## Self-Review

**Spec coverage**

| Spec requirement | Task | Pinned by |
|---|---|---|
| §1 idle runner launches the usable requested roots in registry order; none usable, nothing | 1 | `test_a_pending_set_of_roots_launches_those_roots_in_registry_order`, `test_a_request_for_roots_no_longer_usable_launches_nothing` |
| §1 busy runner never stopped; one pending; `"all"` wins; union of roots | 1 | `test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| §1 the reply is applied first (ok, `ok:false`, garbage), then exactly one follow-up | 1 | `test_a_failed_or_garbage_reply_still_launches_the_pending_request` |
| §1 the pending request resolves against the registry at launch | 1 | `test_a_pending_request_resolves_against_the_registry_at_launch` |
| §1 empty registry: cancel, drop the pending request, empty the outputs | 1 | `test_an_emptied_registry_drops_the_snapshot_in_flight_and_the_pending_request` |
| §1 `stopLive` drops the pending request; the snapshot in flight is applied; a registry change while closed still requests all | 1 | `test_closing_the_panel_drops_the_pending_request` |
| §1 `resetCursor` cancels, drops the pending request and launches all at once | 1 | `test_starting_over_stops_the_snapshot_in_flight_and_launches_every_root`, `test_a_cursor_reset_starts_over_from_a_list_snapshot`, `test_a_hello_from_another_store_starts_over_from_a_list_snapshot` |
| §1 the trigger table: opening, registry, poll, reset → all | 1 | `test_reactivation_starts_a_new_watch`, `test_a_registry_change_drops_renames_adds_and_snapshots_again`, `test_a_debounce_firing_announces_its_run_ids_once` (poll tick) |
| §1 exposed in-flight roots and pending request | 1 | `snapshotRoots` / `pendingSnapshot` assertions throughout |
| §2 unnamed roots keep their runs (same objects) and errors; `runs` merged in registry order | 2 | `test_a_partial_reply_keeps_the_other_roots_as_they_were` |
| §2 no matched entry because every launched root left: no change | 1 | `test_a_reply_for_roots_that_all_left_the_registry_changes_nothing` |
| §2 partial reply, every matched entry `AmMissing` → `missing` | 2 | `test_a_partial_reply_that_is_am_missing_empties_every_root` |
| §2 unrefreshed runs never alert | 2 | `test_a_partial_reply_keeps_the_other_roots_as_they_were` |
| §2 `asOfSeq` 0, `appliedSeq` `{id: 0}` | 2 | `test_a_list_covers_every_listed_run_at_0_and_nudges_follow_it` |
| §3 take the nudges; `runsNudged` once, ids in order, unknown ids included, before the request, never for the store's own snapshots | 2 | `test_a_debounce_firing_announces_its_run_ids_once` |
| §3 map ids to every listing root; an unknown id → all, once | 2 | `test_a_nudge_refreshes_only_the_roots_that_list_its_runs`, `test_a_run_listed_by_two_roots_refreshes_both`, `test_a_window_with_an_unknown_id_refreshes_every_root_once` |
| §3 the seq gates nothing | 2 | `test_a_nudge_for_a_listed_run_always_costs_a_snapshot_of_its_root` |
| run-read path removed (`readRunners` gone) | 2 | `test_a_nudge_refreshes_only_the_roots_that_list_its_runs` (`readRunners === undefined`), the grep in Task 2 Step 3 |
| kept behaviours: toast, logs refetch, settle, nudge after a switch | 2 | the four `test_a_nudge_refresh_*` / `test_a_nudge_after_a_project_switch_is_still_handled` |
| §4 liveness: running roots only, never stacks | 3 | `test_a_liveness_tick_refreshes_only_the_roots_with_a_running_run`, `test_nudges_and_liveness_during_a_snapshot_give_one_follow_up` |
| §5 argv: `/` roots, then known ids, refused ids left out, one argv element per root | 4 | `test_the_watch_names_every_root_then_every_known_run_id`, `test_the_watch_leaves_out_ids_and_roots_the_helper_would_refuse`, `test_with_no_runs_the_watch_names_the_roots_alone` |
| §5 no root qualifies: no watch, no retry | 4 | `test_with_no_absolute_root_no_watch_is_launched`, `test_a_restart_with_no_absolute_root_left_launches_no_watch` |
| §5 restart on a new root set, after the good snapshot; same set keeps it; an ended watch is not restarted | 4 | `test_a_new_root_set_restarts_a_running_watch`, `test_a_reordered_or_renamed_registry_keeps_the_watch`, `test_a_watch_that_ended_is_not_restarted_by_a_new_root_set` |
| §6 stale: a partial good reply clears it; all-failed and dropped replies leave it | 2, 1 | `test_stale_follows_any_good_reply_full_or_partial`, `test_a_reply_for_roots_that_all_left_the_registry_changes_nothing` |
| §7 header and comments | 1–4 | the comment edits in each Step 3; the header is final after Task 4 |
| Existing tests that change | 1–4 | the rewrites in each Step 1; `test_only_the_latest_refresh_is_applied` and the run-read tests are removed, and none is skipped |
| Other tiers kept green | 4 | Step 5 (the end state was run against the full suite; no App or UI test needed a change) |

Gaps: none. The one departure is the signal name, explained at the top.

**Placeholder scan:** every code step is a literal Find / Replace pair or a literal line range to delete, taken from the files at HEAD `d0065fe`. Each pair was applied in order to a copy of HEAD, and the store tier was run after every RED and GREEN step. The counts above are what that replay printed.

**Type consistency:**
- `requestSnapshot(roots)` takes `"all" | string[]` in Tasks 1–3.
- `pendingSnapshot` is `null | "all" | string[]`, and `snapshotRoots` and `watchRoots` are `string[]`.
- `applySnapshot` and `applyProjects` both take a third argument, `launched`.
- `runsNudged` is the name in the store and in every test.
- `listsRun(root, id)` is used only by `triggerNudges`. `refreshLive()` is used only by `livenessTimer`.

**Review Focus:** all five lines have tests in their owning task (Task 2: 1, 3 and 4; Task 4: 2 and 5).
<!-- task-pipeline: validated -->
