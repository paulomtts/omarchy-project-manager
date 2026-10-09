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
