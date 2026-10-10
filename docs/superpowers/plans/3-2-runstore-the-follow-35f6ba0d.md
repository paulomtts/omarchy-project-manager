# 3.2 RunStore: the follow-up fetch on a change — design

Card `35f6ba0d`, a subtask of story `59f54c51`, after card `2d3dfc27` (3.1, spec
`docs/superpowers/specs/3-1-runstore-the-2d3dfc27.md`, below: **3.1**). Parent
spec: `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (below:
**parent**, cited `L<n>`). The change signal comes from
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below: **S6**,
L138).

## Goal

While Run detail is open and the panel is open, `RunStore` keeps the selected
run's event rows current: each change announced for the selected run fetches the
events after the highest seq held (`--since eventsCursor`) and folds them into the
rows. Changes never interrupt a fetch in flight; they queue at most one follow-up
behind it. A finishing run gets its last events the same way. Closing the panel
starts nothing new.

## Card vs parent vs code: what governs

| topic | parent | card / code (governs) |
|---|---|---|
| change signal | `runsChanged(ids)` (L98; S6 L138) | `signal runsNudged(var ids)` (`core/stores/RunStore.qml:205-209`): `runs` already owns the `runsChanged` name. Emitted once per debounce window by `triggerNudges()` (`RunStore.qml:540-560`), ids each once in first-nudge order, known to the store or not, never for a snapshot the store started itself; it fires only while the watch runs, i.e. while `active` |
| forward fetch argv | `--after-seq eventsCursor` (L99) | `runs-events.py RUN --since SEQ` (card; `core/backend/runs/runs-events.py:3-17`): am's events after SEQ; reply `{ok:true, events, last_seq, total}`, `last_seq` the highest seq printed or SEQ when none, `total` the count printed |
| dedupe key / cursor | `gseq` (L61, L99) | `seq`, through `RunEvents.foldEvents` (`core/domain/runEvents.js:113-145`); `eventsCursor` the highest seq seen (3.1 "Card vs parent") |

## Inherited constraints

| constraint | source |
|---|---|
| The selected run's change signal triggers one forward fetch from `eventsCursor`; new rows are appended in order and deduplicated | parent L98-100; card |
| A change that arrives while a fetch is in flight runs after it, never instead of it; a new selection still wins (latest wins) | parent L100-101, L160; card |
| A reply for a run that is no longer selected is dropped | parent L101; 3.1 "Applying a reply / Stale" |
| No second watch process; the store's one watch is the only live signal | parent L39-40, L102 |
| Never replay a run from its start | parent L39-40, L94-95 |
| A run that finishes while Run detail is open gets its last fetch from the same signal | parent L104; card |
| The panel closing stops fetching with the rest of the store's live work | parent L105; card |
| An unreadable store keeps the rows and retries on the next nudge | parent L157 |
| At most 500 rows held, oldest dropped and counted | parent L82, L161; 3.1 "State" |
| The events runner is guarded by the run id, never the open project; a project switch changes nothing | parent L85-86, L177; 3.1 "Project switch and panel" |
| Stores import only `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js`; no store imports another | `docs/architecture.md:14`, `:23`; `tests/architecture/test_layers.py` |
| No icon glyph characters in store code, comments or strings | card; `tests/architecture/test_icon_glyphs.py` |
| Comments and docstrings state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

## Behavior

Everything below is on `RunStore`. "The change fetch" is defined in 2; "in
flight" means `eventsRunner.busy` is true.

### 1. A change for the selected run

On `runsNudged(ids)`:

- **Nothing happens** (no launch, nothing queued, no state changes) when any of
  these holds: `active` is false; `selectedRunId` is `""`; `ids` is not an array;
  `ids` does not contain `selectedRunId` (exact string match). Ids of other runs
  in the same list are irrelevant.
- **No fetch in flight:** the change fetch is launched now.
- **A fetch in flight** (the selection's `--tail 200`, a `refreshEvents()`, or an
  earlier change fetch): that fetch is left alone (same `eventsRunner.current`,
  still running, `eventsRunner.seq` unchanged) and one follow-up is queued. Any
  number of further changes for the selected run before that fetch ends queue
  nothing more: exactly one follow-up.
- The run's status is never read: a run whose `runs` entry is `done`,
  `escalated`, `stopped`, `cancelled`/`canceled`, or that `runs` does not list,
  is fetched like a running one. This is how a run that finishes while Run detail
  is open gets its last fetch: the nudge that announces the finish names it.

### 2. The change fetch

- With `eventsCursor > 0`: `eventsStatus` `loading`, `eventsRunner.guard` the
  selected run id, and one launch with argv exactly
  `["python3", backendDir + "runs/runs-events.py", RUN, "--since", String(eventsCursor)]`
  (`RUN` the selected id verbatim, one element). Rows, `eventsDropped`,
  `eventsCursor` and `eventsError` stay until the reply.
- With `eventsCursor` `0` (no good reply has raised it — the selection's fetch
  failed, or the run had no events): the selection's argv `RUN --tail 200`
  instead, with the same no-reset rules (this is what `refreshEvents()` launches).
  `--since 0` is never sent, so a change never replays a run from its start.

### 3. The queued follow-up

- When the in-flight fetch ends — its process exits and its reply has been
  applied, whatever the reply was (good, ignored per 4, failure envelope,
  unusable) — and a follow-up is queued: the queue is cleared, then, if `active`
  is still true and `selectedRunId` is non-empty, the change fetch (2) is
  launched once, computed from the state after that reply (so its `--since` is
  the cursor the reply just raised).
- A change for the selected run that arrives while the follow-up is in flight
  queues one more follow-up behind it (1).
- **A new selection wins.** Selecting another run, or leaving Run detail
  (`selectedRunId` `""`), clears the queue; the selection's own behaviour
  (3.1 "Selection" 1-3: reset, `--tail 200` or cancel) is unchanged. The old
  fetch's reply is dropped as in 3.1, and no follow-up is launched for the old
  run when it ends.
- **The panel closes** (`active` true -> false, `stopLive()`): the queue is
  cleared. A fetch in flight is not stopped; its reply is applied normally, and
  nothing is launched after it. While closed, a `runsNudged` emission starts
  nothing (1). Reopening the panel launches no events fetch by itself; the next
  change for the selected run fetches `--since eventsCursor`, which also covers
  the events recorded while the panel was closed.
- `refreshEvents()` while a fetch is in flight keeps 3.1's latest-wins (it
  supersedes the in-flight fetch); a queued follow-up stays queued and runs after
  the refresh's fetch ends.

### 4. Applying a reply (additions to 3.1 "Applying a reply")

The stale-reply rule, the failure and unusable paths, labels and titles are 3.1's,
unchanged. A failure on a change fetch keeps rows, `eventsDropped` and
`eventsCursor`, sets `error` and its message; the next change fetches again from
the unchanged cursor.

- **A reply behind the cursor is ignored.** A good envelope (`ok` true, `events`
  an array) whose `last_seq` is a non-negative integer below the current
  `eventsCursor`, on any fetch kind: `events`, `eventsDropped` and `eventsCursor`
  unchanged; `eventsStatus` `ok`, `eventsError` `""` (the read succeeded; the
  store already holds newer events). A `last_seq` equal to the cursor, or not a
  non-negative integer, is not "behind" and is folded as usual.
- **Which fold applies** follows the newest launch: the store records the kind
  (`--since` or `--tail`) at each launch, so a `refreshEvents()` that supersedes an
  in-flight `--since` fetch makes the next reply a `--tail` one. The reply carries
  no kind of its own, and `HelperRunner` emits `finished` only for the newest
  launch whose guard still matches, so the recorded kind is that reply's.
  The follow-up is launched from the `finished` handler, after `applyEvents`
  returns (`eventsRunner.busy` is already false there).
- **A reply to a `--since` fetch** is folded with `RunEvents.foldEvents(held,
  freshRows, 500)` (one row per seq, the reply's row winning over a held one with
  the same seq, ascending seq whatever order the reply lists them in, the lowest
  seqs dropped past 500), and:
  - `eventsDropped` = its value before the reply + `fold.dropped` (the reply
    counts only events after the cursor, so 3.1's `total - received - priorBelow`
    term does not apply and must not reset the count);
  - `eventsCursor` = the largest of its value, `last_seq`, and the highest held
    row seq (3.1's rule);
  - `eventsStatus` `ok`, `eventsError` `""`.
- A reply to a `--tail 200` fetch (selection, `refreshEvents()`, or a change
  fetch at cursor 0) keeps 3.1's fold and `eventsDropped` formula exactly.

### Untouched

A change fetch and its reply never touch `amStatus`, `lastError`, `runs`, the
logs state, `eventsFilter`, the snapshot or watch state. A project switch neither
queues, clears nor launches anything for events. `runs-events.py`,
`runEvents.js`, `runs.js`, `HelperRunner.qml` and `App.qml` are not changed.

## Error paths

| case | behaviour |
|---|---|
| change fetch answered by a refusal (`UnknownRunError`, `StoreBusyError`, `CorruptJournal`, `AmMissing`) | `error` with `Runs.errorText`; rows, dropped, cursor kept; the next change for the run fetches `--since` the same cursor |
| change fetch answered by no usable line | `error`, `The events snapshot gave no usable result (exit N).`; rows kept |
| selection's `--tail 200` failed, then a change | `--tail 200` again (cursor 0), never `--since 0` |
| reply with `last_seq` below the cursor | ignored as in 4; status `ok` |
| reply for a run no longer selected | dropped (3.1); no follow-up for that run |
| changes while closed | nothing |
| a burst of changes during one fetch | one follow-up |

## Tests

All new tests are QML store tests in `tests/core/stores/tst_run_store.qml`
(TestCase `StoresRunStore`), run by `qmltestrunner` through `bash tests/run.sh`,
next to the 3.1 events tests and reusing `eventsCmd`, `reply`, `argv`,
`eventsReply`, `attemptEvents`, `seqs` and `heldStore`. They are store tier
because every behaviour is store state reacting to a signal, a property change
and a stubbed `Process` exit (`tests/stubs`): no real process, clock, watch or
UI is involved. Changes are delivered by emitting `store.runsNudged([...])`
directly (the debounce path that emits it is already covered at
`tst_run_store.qml:843`, `:1077`, `:1108`); the store is made `active` first
unless the test is about the inactive case. Each test ships failing first.

1. **`--since` after a change** — held store (rows 8..10, cursor 10, dropped 7),
   active; `runsNudged(["r1"])` launches `eventsCmd + "r1|--since|10"`, guard
   `r1`, status `loading`, rows still held; reply events 11..12 (`last_seq` 12,
   `total` 2): rows `8,...,12`, cursor 12, `eventsDropped` 7 (not reset), status
   `ok`.
2. **other runs' ids do nothing** — held store, active: `runsNudged(["r2",
   "z9"])` launches nothing (`eventsRunner.seq` unchanged), state unchanged;
   `runsNudged(["r2", "r1"])` does launch.
3. **no selection, not active, bad ids do nothing** — `selectedRunId` `""` +
   `runsNudged(["r1"])`: nothing; held store with `active` false +
   `runsNudged(["r1"])`: nothing; `runsNudged("r1")` (not an array): nothing.
4. **a change during a fetch gives exactly one follow-up** — select `r1`
   (active), its `--tail 200` in flight; three `runsNudged(["r1"])`: same
   `current`, still running, same `seq`; reply the tail (events 8..10,
   `last_seq` 10): exactly one new launch, `eventsCmd + "r1|--since|10"`;
   replying to it launches nothing more.
5. **a change during a follow-up queues one more** — from 4's follow-up in
   flight, one `runsNudged(["r1"])`; its reply (11..12) launches
   `--since|12`.
6. **the follow-up runs after a failed reply** — a change queued while the
   fetch is in flight; that fetch answered by an `UnknownRunError` envelope:
   status `error` then the follow-up launches with the unchanged cursor.
7. **a new selection wins over the queue** — `r1` fetch in flight, a change
   queued; select `r2`: `r2|--tail|200` launched; `r2`'s reply launches nothing
   more (the queue was cleared); likewise leaving Run detail: nothing launched,
   runner idle.
8. **closing the panel starts nothing new** — change queued while a fetch is in
   flight; `active` false: the in-flight process still running; its reply is
   applied (rows folded) and nothing is launched after it; a `runsNudged(["r1"])`
   while closed launches nothing; after reopening, the next change launches
   `--since` the current cursor.
9. **the finish case** — active store whose snapshot lists `r1` as `done`
   (selected, rows held): `runsNudged(["r1"])` launches `--since cursor`, and its
   reply's final events (a `run_upsert` with status `done`) are appended.
10. **out-of-order and duplicate rows** — held rows 8..10; a `--since 10` reply
    listing seqs `12, 9, 11, 12` with the later 12 and the 9 carrying a different
    status: rows `8,9,10,11,12`, ascending, one per seq, the reply's 9 and its
    last 12 win.
11. **a reply behind the cursor is ignored** — held store (cursor 10), a
    synthetic `refreshEvents()` reply with `last_seq` 6 and events 4..6: rows,
    dropped and cursor unchanged; status `ok`, error `""` (also from a prior
    `error` status). A reply with `last_seq` equal to the cursor is folded.
12. **cursor 0 never sends `--since 0`** — select `r1`, answer with a refusal
    (cursor 0); a change launches `r1|--tail|200`.
13. **the cap counts on a `--since` reply** — rows 1..500 held (cursor 500,
    dropped 0) and a `--since 500` reply of 20 events: rows 21..520,
    `eventsDropped` 20.

Unchanged gates that must stay green: every 3.1 events test,
the `runsNudged` emission tests, `tests/architecture/test_layers.py`,
`tests/architecture/test_icon_glyphs.py`, `tests/core/domain/tst_run_events.qml`.

## Out of scope

- `ui/components/EventsPane.qml`, `RunDetailScreen` wiring, tabs, `e` key,
  filter chips, follow/jump (sibling UI cards; parent L124-149).
- Paging earlier events (`--before-seq`, `eventsHasEarlier`, `eventsOldestSeq`;
  parent L96-97).
- Any change to how or when `runsNudged` is emitted, the watch, the debounce, or
  the snapshot (S6's).
- A fetch on reopening the panel or on a project switch.
- Relabelling held rows; any change to `runs-events.py`, `runEvents.js`,
  `runs.js`, `HelperRunner.qml`, `App.qml`, `tst_app_runs.qml`.
- Updating the RunStore paragraph in `docs/architecture.md`.

---

# 3.2 RunStore: the follow-up fetch on a change Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the panel is open, `RunStore` answers each `runsNudged(ids)` that names the selected run with one `runs-events.py RUN --since eventsCursor` fetch (or `--tail 200` with no cursor yet), folds the reply into the held rows without resetting `eventsDropped`, ignores replies behind the cursor, and queues at most one follow-up behind a fetch in flight.

**Architecture:** All in `core/stores/RunStore.qml`. A private `QtObject eventsState` records the newest launch's kind (`"tail"` / `"since"`) and whether one follow-up is queued. `onRunsNudged` calls `nudgeEvents(ids)`, which launches `fetchNewEvents()` or queues; the `eventsRunner`'s `onFinished` applies the reply, then calls `followUpEvents()`. `selectEvents()` and `stopLive()` clear the queue. `foldReply` picks the `eventsDropped` formula from the recorded kind; `applyEvents` ignores a good reply whose `last_seq` lies below the cursor.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), `core/domain/runEvents.js` (`foldEvents`, `eventRow`), QtTest via `qmltestrunner` with stubbed `Process` (`tests/stubs`).

**Spec:** `docs/superpowers/specs/3-2-runstore-the-follow-35f6ba0d.md` (prepended above).

## Global Constraints

- Change-fetch argv exactly `["python3", backendDir + "runs/runs-events.py", RUN, "--since", String(eventsCursor)]`; `RUN` the selected id verbatim as one element; no project root argument.
- With `eventsCursor` `0` a change launches the selection's argv `RUN --tail 200`; `--since 0` is never sent.
- At most one fetch in flight on `eventsRunner` and at most one queued follow-up; a change never stops the fetch in flight.
- At most 500 rows held (`RunEvents.foldEvents(held, fresh, 500)`), lowest seqs dropped and counted.
- A `--since` reply: `eventsDropped` = prior value + `fold.dropped`. A `--tail 200` reply: 3.1's `Math.max(0, total - received - priorBelow) + fold.dropped`, unchanged.
- A good reply whose `last_seq` is a non-negative integer below `eventsCursor` changes no rows/dropped/cursor; status `ok`, error `""`.
- Unusable reply text: `"The events snapshot gave no usable result (exit N)."` (3.1, unchanged).
- The events runner is guarded by the run id, never by the open project; a project switch queues, clears and launches nothing.
- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js`; no store imports another.
- No icon glyph characters (private-use code points) in store code, comments or strings.
- Comments and docstrings state the contract only, no narrative.
- `bash tests/run.sh` green; tests first.
- Do not touch: `core/backend/runs/runs-events.py`, `core/domain/runEvents.js`, `core/domain/runs.js`, `core/stores/HelperRunner.qml`, `core/stores/App.qml`, `tests/core/stores/tst_app_runs.qml`, `ui/`, `docs/architecture.md`.

## Running the tests

`bash tests/run.sh` runs all of pytest (about 2 minutes) and then every QML test. For the TDD loop, run QML test functions in place (no copy needed):

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_a_change_fetches_since_the_cursor
```

Several functions may be listed, space-separated. Without a function name the whole file runs. A `TypeError`/`ReferenceError` in the output counts as a failure (`tests/run.sh` greps for them). `bash tests/run.sh tst_run_store` runs pytest plus only that QML file. Never use `pkill`/`killall`; stop a stuck run with `timeout`.

Test-harness facts the steps rely on (all already in `tests/core/stores/tst_run_store.qml`):

- `make()` builds a `RunStore` with `backendDir: "/plugin/core/backend/"`, no registry, no project, `active` false.
- `reply(proc, text, code)` sets `proc.outText = text` and emits `proc.exited(code)`. A process that has exited is destroyed afterwards: read `proc.running` only before replying to it.
- `argv(proc)` is `proc.command.join("|")`; `tc.eventsCmd` is `"python3|/plugin/core/backend/runs/runs-events.py|"`.
- `eventsReply(events, lastSeq, total)` is runs-events.py's good line; `attemptEvents(first, n)` is `n` `attempt_upsert` events of card `c1`, seq `first..first+n-1`, payload `{status: "ok", duration: 1.5}`; `seqs(rows)` joins the rows' seqs with `,`.
- `heldStore()`: `r1` selected and its `--tail 200` answered with events 8..10, `last_seq` 10, `total` 10: rows `8,9,10`, `eventsDropped` 7, `eventsCursor` 10, status `ok`, `active` false.
- `threeRoots()`: an active store with rootA/B/C registered, its snapshot answered (runs `a1`, `b1`, `c1`, each `status: "done"`), the watch started. `nudge(store, [id, seq, ...])` feeds one `{"changed": [...]}` watch line; `fire(timer)` fires a timer; `fire(store.debounceTimer)` emits `runsNudged` with the nudged ids.
- `store.active = true` runs `startLive()` (settings load, snapshot refresh); it launches nothing on `eventsRunner`.
- `HelperRunner.run(args)` stops `current`, bumps `seq`, sets `busy`, launches a stub `Process` carrying `launchGuard: guard`. Its exit releases `busy` and emits `finished(stdout, exitCode, launchedGuard)` only when it is the newest launch (`launchSeq === seq`) and `launchGuard === guard`; `busy` is already false when `finished` is emitted. `cancel()` bumps `seq`, stops `current`, sets `busy = false`.
- `Runs` and `RunEvents` are imported in the test file.

## Review Focus

1. `refreshEvents()` while a change fetch is in flight with a follow-up queued — the refresh must supersede the change fetch, its reply must use the `--tail` dropped formula (the newest launch's kind), and the queued follow-up must run after it from the raised cursor. Pinned in Task 3 by `test_a_refresh_supersedes_a_change_fetch_and_the_follow_up_waits`.
2. The panel closed before a fetch with a queued follow-up ends — the queue must not survive the closing, so the fetch's end launches nothing; reopening launches no events fetch of its own (`startLive()` loads settings, refreshes the snapshot and restarts the stale timer — `restartStale()` touches only `stale` and `staleTimer`, never `selectEvents()`), and the next change fetches `--since` the held cursor. Pinned in Task 3 by `test_closing_the_panel_starts_nothing_new`.
3. A `--since` reply whose `last_seq` is missing, a string, negative or fractional — it is not "behind", is folded, the cursor comes from the held rows and `eventsDropped` is kept. Pinned in Task 1 by `test_a_change_reply_with_a_bad_last_seq_is_folded`.
4. The store's own debounce emission (a watch line, then the debounce firing) for a run that has finished — it must reach the change fetch exactly like a direct `runsNudged`, with the run's status never read. Pinned in Task 1 by `test_a_finished_run_gets_its_last_events_from_the_watch`.
5. Nudged ids that repeat the selected id, mix in non-strings, or a selected id with a space and `;` — one launch, the id passed verbatim as one argument. Pinned in Task 1 by `test_a_change_for_other_runs_fetches_nothing` and `test_a_change_passes_the_run_id_verbatim`.

---

### Task 1: A change for the selected run fetches `--since` the cursor

**Files:**
- Modify: `core/stores/RunStore.qml` — header comment (lines 31-33), events property comment (lines 122-127), `fetchEvents()` (lines 889-894), new `nudgeEvents()` / `onRunsNudged` / `fetchNewEvents()` after `refreshEvents()` (after line 887), `foldReply()` (lines 937-974), new `QtObject { id: eventsState }` after `snapshotState` (after line 2068)
- Test: `tests/core/stores/tst_run_store.qml` (append at the end of the file, before the final `}`)

**Interfaces:**
- Consumes: `store.runsNudged(var ids)` signal (`RunStore.qml:209`); `eventsRunner` (`HelperRunner`), `store.fetchEvents()`, `store.applyEvents(stdout, exitCode, launchedGuard)`, `store.foldReply(envelope)`, `store.isSeq(value)`; `RunEvents.foldEvents(rows, events, cap) -> {rows, dropped}`.
- Produces: `function nudgeEvents(ids)` (no return); `function fetchNewEvents()` (no return); private `eventsState.kind` (`"tail"` | `"since"`, set at every events launch). Task 3 extends `nudgeEvents` and `eventsState`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/stores/tst_run_store.qml`, just before the file's final closing `}`:

```qml
  // ---- the follow-up fetch on a change (3.2)

  // heldStore()'s rows (8..10, cursor 10, dropped 7) with the panel open.
  function activeHeld() {
    var store = make(); if (!store) return null
    store.active = true
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    return store
  }

  // 1
  function test_a_change_fetches_since_the_cursor() {
    var store = activeHeld(); if (!store) return
    var others = JSON.stringify({ amStatus: store.amStatus, lastError: store.lastError, runs: store.runs.length,
                                  logsSeq: store.logsRunner.seq, filter: store.eventsFilter })
    store.runsNudged(["r1"])
    var proc = store.eventsRunner.current
    compare(argv(proc), tc.eventsCmd + "r1|--since|10")
    compare(proc.command.length, 5, "no project root argument")
    compare(proc.launchGuard, "r1", "guarded by the run id")
    compare(store.eventsStatus, "loading")
    compare(seqs(store.events), "8,9,10", "the rows stay until the reply")
    compare(store.eventsDropped, 7)
    compare(store.eventsCursor, 10)
    reply(proc, eventsReply(attemptEvents(11, 2), 12, 2), 0)
    compare(seqs(store.events), "8,9,10,11,12")
    compare(store.eventsCursor, 12)
    compare(store.eventsDropped, 7, "a --since reply counts only events after the cursor")
    compare(store.eventsStatus, "ok")
    compare(store.eventsError, "")
    compare(JSON.stringify({ amStatus: store.amStatus, lastError: store.lastError, runs: store.runs.length,
                             logsSeq: store.logsRunner.seq, filter: store.eventsFilter }),
            others, "nothing else is touched")
  }

  // 2 and Review Focus 5
  function test_a_change_for_other_runs_fetches_nothing() {
    var store = activeHeld(); if (!store) return
    var held = JSON.stringify(store.events)
    var seq = store.eventsRunner.seq
    store.runsNudged(["r2", "z9"])
    compare(store.eventsRunner.seq, seq, "nothing is launched")
    compare(JSON.stringify(store.events), held)
    compare(store.eventsStatus, "ok")
    compare(store.eventsCursor, 10)
    compare(store.eventsDropped, 7)
    // synthetic: the selected id twice, among other ids and non-strings.
    store.runsNudged(["r2", "r1", null, 5, "r1"])
    compare(store.eventsRunner.seq, seq + 1, "one launch")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|10")
  }

  // Review Focus 5
  function test_a_change_passes_the_run_id_verbatim() {
    var store = make(); if (!store) return
    store.active = true
    // synthetic: a run id with a space and a ";".
    store.selectedRunId = "r 2;x"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 2), 2, 2), 0)
    store.runsNudged(["r 2;x"])
    var proc = store.eventsRunner.current
    compare(proc.command.length, 5)
    compare(proc.command[2], "r 2;x", "one argument, unchanged")
    compare(proc.command[3], "--since")
    compare(proc.command[4], "2")
  }

  // 3
  function test_no_selection_a_closed_panel_or_bad_ids_fetch_nothing() {
    var store = make(); if (!store) return
    store.active = true
    store.runsNudged(["r1"])
    verify(!store.eventsRunner.current, "no run selected: nothing is launched")
    compare(store.eventsStatus, "idle")
    var closed = heldStore(); if (!closed) return
    var seq = closed.eventsRunner.seq
    closed.runsNudged(["r1"])
    compare(closed.eventsRunner.seq, seq, "the panel is closed")
    compare(closed.eventsStatus, "ok")
    var open = activeHeld(); if (!open) return
    seq = open.eventsRunner.seq
    // synthetic: ids that are not a list.
    var bad = ["r1", null, undefined, { r1: true }, 7]
    for (var i = 0; i < bad.length; i++) {
      open.runsNudged(bad[i])
      compare(open.eventsRunner.seq, seq, String(bad[i]))
      compare(open.eventsStatus, "ok", String(bad[i]))
    }
    open.runsNudged(["r1"])
    compare(open.eventsRunner.seq, seq + 1, "a list naming the selected run launches")
    compare(argv(open.eventsRunner.current), tc.eventsCmd + "r1|--since|10")
  }

  // 9 and Review Focus 4
  function test_a_finished_run_gets_its_last_events_from_the_watch() {
    var store = threeRoots(); if (!store) return
    compare(Runs.runState(store.runById("a1")), "done")
    store.selectedRunId = "a1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    nudge(store, ["a1", 11])
    fire(store.debounceTimer)
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "a1|--since|10")
    reply(store.eventsRunner.current,
          eventsReply([{ seq: 11, gseq: 1011, ts: "2026-10-08T14:40:00Z", run_id: "a1", event: "run_upsert",
                         payload: { status: "done" } }], 11, 1), 0)
    compare(seqs(store.events), "8,9,10,11")
    compare(store.events[3].level, "run")
    compare(store.events[3].label, "run done")
    compare(store.events[3].status, "done")
    compare(store.eventsCursor, 11)
    compare(store.eventsDropped, 7)
  }

  // 10
  function test_a_change_reply_out_of_order_with_repeats_folds_one_row_per_seq() {
    var store = activeHeld(); if (!store) return
    store.runsNudged(["r1"])
    // synthetic: am lists each seq once, ascending; this reply does neither.
    var first12 = attemptEvents(12, 1)[0]
    var nine = attemptEvents(9, 1)[0]
    nine.payload.status = "failed"
    var eleven = attemptEvents(11, 1)[0]
    var last12 = attemptEvents(12, 1)[0]
    last12.payload.status = "escalated"
    reply(store.eventsRunner.current, eventsReply([first12, nine, eleven, last12], 12, 4), 0)
    compare(seqs(store.events), "8,9,10,11,12", "ascending, one row per seq")
    compare(store.events[1].status, "failed", "the reply's 9 wins over the held one")
    compare(store.events[4].status, "escalated", "the reply's last 12 wins")
    compare(store.eventsCursor, 12)
    compare(store.eventsDropped, 7)
  }

  // 12
  function test_a_change_with_no_cursor_fetches_the_last_200() {
    var store = make(); if (!store) return
    store.active = true
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current,
          JSON.stringify({ ok: false, error: { type: "UnknownRunError", message: "no run r1" } }) + "\n", 0)
    compare(store.eventsCursor, 0)
    var seq = store.eventsRunner.seq
    store.runsNudged(["r1"])
    compare(store.eventsRunner.seq, seq + 1, "a fetch is launched")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--tail|200", "never --since 0")
    compare(store.eventsStatus, "loading")
    compare(store.eventsError, "UnknownRunError: no run r1", "the error stays until the reply")
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    compare(store.eventsDropped, 7, "a --tail reply keeps 3.1's count")
    compare(store.eventsCursor, 10)

    var empty = make(); if (!empty) return
    empty.active = true
    empty.selectedRunId = "r1"
    reply(empty.eventsRunner.current, eventsReply([], 0, 0), 0)
    compare(empty.eventsCursor, 0, "a run with no events")
    var emptySeq = empty.eventsRunner.seq
    empty.runsNudged(["r1"])
    compare(empty.eventsRunner.seq, emptySeq + 1)
    compare(argv(empty.eventsRunner.current), tc.eventsCmd + "r1|--tail|200")
  }

  // 13
  function test_the_cap_counts_on_a_change_reply() {
    var store = make(); if (!store) return
    store.active = true
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 500), 500, 500), 0)
    compare(store.events.length, 500)
    compare(store.eventsDropped, 0)
    store.runsNudged(["r1"])
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|500")
    reply(store.eventsRunner.current, eventsReply(attemptEvents(501, 20), 520, 20), 0)
    compare(store.events.length, 500)
    compare(store.events[0].seq, 21, "the lowest seqs were dropped")
    compare(store.events[499].seq, 520)
    compare(store.eventsDropped, 20)
    compare(store.eventsCursor, 520)
  }

  // Review Focus 3
  function test_a_change_reply_with_a_bad_last_seq_is_folded() {
    var store = activeHeld(); if (!store) return
    store.runsNudged(["r1"])
    // synthetic: last_seq values runs-events.py never prints.
    reply(store.eventsRunner.current,
          JSON.stringify({ ok: true, events: attemptEvents(11, 1), total: 1 }) + "\n", 0)
    compare(seqs(store.events), "8,9,10,11")
    compare(store.eventsCursor, 11, "the highest held seq")
    compare(store.eventsDropped, 7)
    var lasts = [null, "5", -1, 2.5]
    for (var i = 0; i < lasts.length; i++) {
      store.runsNudged(["r1"])
      compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|11", String(lasts[i]))
      reply(store.eventsRunner.current,
            JSON.stringify({ ok: true, events: [], last_seq: lasts[i], total: 0 }) + "\n", 0)
      compare(store.eventsStatus, "ok", String(lasts[i]))
      compare(seqs(store.events), "8,9,10,11", String(lasts[i]))
      compare(store.eventsCursor, 11, String(lasts[i]))
      compare(store.eventsDropped, 7, String(lasts[i]))
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml \
  StoresRunStore::test_a_change_fetches_since_the_cursor StoresRunStore::test_a_change_for_other_runs_fetches_nothing \
  StoresRunStore::test_a_change_passes_the_run_id_verbatim StoresRunStore::test_no_selection_a_closed_panel_or_bad_ids_fetch_nothing \
  StoresRunStore::test_a_finished_run_gets_its_last_events_from_the_watch \
  StoresRunStore::test_a_change_reply_out_of_order_with_repeats_folds_one_row_per_seq \
  StoresRunStore::test_a_change_with_no_cursor_fetches_the_last_200 StoresRunStore::test_the_cap_counts_on_a_change_reply \
  StoresRunStore::test_a_change_reply_with_a_bad_last_seq_is_folded
```
Expected: all 9 FAIL — nothing is launched on a change (e.g. `test_a_change_fetches_since_the_cursor`: actual `...r1|--tail|200`, expected `...r1|--since|10`; seq-count assertions off by one).

- [ ] **Step 3: Add the private launch state**

In `core/stores/RunStore.qml`, right after the `snapshotState` `QtObject` (the block ending at line 2068: `property var pending: null` / `}`), insert:

```qml

  // The selected run's events fetches' own state; kept apart so consumers
  // cannot write it. `kind` is the newest launch's: "tail" (RUN --tail 200)
  // or "since" (RUN --since eventsCursor).
  QtObject {
    id: eventsState
    property string kind: "tail"
  }
```

- [ ] **Step 4: Record the kind in `fetchEvents()` and add the change fetch**

Replace `fetchEvents()` (lines 889-894):

```qml
  // runs-events.py RUN --tail 200 for the selected run, guarded by its id.
  function fetchEvents() {
    store.eventsStatus = "loading"
    eventsRunner.guard = store.selectedRunId
    eventsRunner.run([store.selectedRunId, "--tail", "200"])
  }
```

with:

```qml
  // runs-events.py RUN --tail 200 for the selected run, guarded by its id.
  function fetchEvents() {
    store.eventsStatus = "loading"
    eventsRunner.guard = store.selectedRunId
    eventsState.kind = "tail"
    eventsRunner.run([store.selectedRunId, "--tail", "200"])
  }

  // A debounce window's run ids (runsNudged). While active, with ids an array
  // holding selectedRunId: the change fetch (fetchNewEvents), unless a fetch
  // is in flight, which is left alone. The run's status is never read.
  function nudgeEvents(ids) {
    if (!store.active || store.selectedRunId === "" || !Array.isArray(ids)) return
    if (ids.indexOf(store.selectedRunId) < 0) return
    if (eventsRunner.busy) return
    store.fetchNewEvents()
  }

  onRunsNudged: function(ids) { store.nudgeEvents(ids) }

  // The change fetch: runs-events.py RUN --since eventsCursor, guarded by the
  // run id; with eventsCursor 0, fetchEvents (--tail 200). The rows,
  // eventsDropped, eventsCursor and eventsError stay until the reply.
  function fetchNewEvents() {
    if (store.eventsCursor <= 0) {
      store.fetchEvents()
      return
    }
    store.eventsStatus = "loading"
    eventsRunner.guard = store.selectedRunId
    eventsState.kind = "since"
    eventsRunner.run([store.selectedRunId, "--since", String(store.eventsCursor)])
  }
```

Note: the function must not be called `eventsChanged` — that name is the `events` property's change signal.

- [ ] **Step 5: Pick the dropped formula from the launch kind in `foldReply()`**

In `foldReply(envelope)` replace its comment (lines 937-943):

```qml
  // A good reply. Its events become RunEvents.eventRow rows, labelled from
  // eventTitles() at the local UTC offset (null rows skipped), folded into
  // the held rows, at most 500.
  // eventsDropped: (total - received) less the held rows below the reply's
  // lowest seq, at least 0, plus the rows the cap removed; total is the
  // reply's when an integer >= received, else received. eventsCursor: the
  // highest of itself, a non-negative integer last_seq and the held rows' seqs.
```

with:

```qml
  // A good reply. Its events become RunEvents.eventRow rows, labelled from
  // eventTitles() at the local UTC offset (null rows skipped), folded into
  // the held rows, at most 500.
  // eventsDropped, after a --tail launch: (total - received) less the held
  // rows below the reply's lowest seq, at least 0, plus the rows the cap
  // removed; total is the reply's when an integer >= received, else
  // received. After a --since launch: its value plus the rows the cap
  // removed. eventsCursor: the highest of itself, a non-negative integer
  // last_seq and the held rows' seqs.
```

and replace the line (line 970):

```qml
    store.eventsDropped = Math.max(0, total - received - priorBelow) + fold.dropped
```

with:

```qml
    if (eventsState.kind === "since") store.eventsDropped = store.eventsDropped + fold.dropped
    else store.eventsDropped = Math.max(0, total - received - priorBelow) + fold.dropped
```

- [ ] **Step 6: Update the contract comments**

In the header comment, replace lines 31-33:

```qml
// status -- never on a timer. The selected run's events (runs-events.py RUN
// --tail 200) are fetched on a selection and on refreshEvents() -- never on
// a timer, and a project switch leaves them alone.
```

with:

```qml
// status -- never on a timer. The selected run's events (runs-events.py RUN
// --tail 200) are fetched on a selection and on refreshEvents(), and, while
// `active`, the ones after eventsCursor (RUN --since eventsCursor) on each
// runsNudged naming the selected run -- never on a timer, and a project
// switch leaves them alone.
```

In the events property comment, replace lines 125-126:

```qml
  // A selection empties them and fetches the run's last 200 events; leaving
  // Run detail empties them and fetches nothing.
```

with:

```qml
  // A selection empties them and fetches the run's last 200 events; leaving
  // Run detail empties them and fetches nothing. While active, a runsNudged
  // naming the selected run fetches the events after eventsCursor.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run the Step 2 command again.
Expected: all 9 PASS, no `TypeError`/`ReferenceError` lines.

Then run the whole store file (3.1 events tests and the `runsNudged` emission tests must stay green):
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"
```
Expected: only a `Totals: ... 0 failed` line.

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): a change for the selected run fetches its events since the cursor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: A reply behind the cursor is ignored

**Files:**
- Modify: `core/stores/RunStore.qml` — `applyEvents()` (lines 920-935 before Task 1; find it by `function applyEvents(stdout, exitCode, launchedGuard)`)
- Test: `tests/core/stores/tst_run_store.qml` (append after Task 1's tests, before the final `}`)

**Interfaces:**
- Consumes: `store.isSeq(value)` (`RunStore.qml:1030`, a non-negative integer number), `store.foldReply(envelope)`, `heldStore()`, `eventsReply`, `attemptEvents`, `seqs`.
- Produces: `applyEvents(stdout, exitCode, launchedGuard)` keeps its signature; a good envelope with `isSeq(last_seq) && last_seq < eventsCursor` sets `eventsStatus "ok"`, `eventsError ""` and returns without folding.

- [ ] **Step 1: Write the failing test**

Append before the file's final `}`:

```qml
  // 11
  function test_a_reply_behind_the_cursor_is_ignored() {
    var store = heldStore(); if (!store) return
    var held = JSON.stringify(store.events)
    store.refreshEvents()
    reply(store.eventsRunner.current,
          JSON.stringify({ ok: false, error: { type: "StoreBusyError", message: "the store is busy" } }) + "\n", 0)
    compare(store.eventsStatus, "error")
    store.refreshEvents()
    // synthetic: a reply whose last_seq lies below the cursor.
    reply(store.eventsRunner.current, eventsReply(attemptEvents(4, 3), 6, 6), 0)
    compare(JSON.stringify(store.events), held, "the rows are unchanged")
    compare(store.eventsDropped, 7)
    compare(store.eventsCursor, 10)
    compare(store.eventsStatus, "ok", "the read succeeded")
    compare(store.eventsError, "")
    store.refreshEvents()
    var again = attemptEvents(9, 2)
    again[0].payload.status = "failed"
    reply(store.eventsRunner.current, eventsReply(again, 10, 10), 0)
    compare(store.events[1].status, "failed", "a last_seq equal to the cursor is folded")
    compare(seqs(store.events), "8,9,10")
    compare(store.eventsCursor, 10)
    compare(store.eventsDropped, 7, "10 - 2 - 1 held below")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_a_reply_behind_the_cursor_is_ignored
```
Expected: FAIL at "the rows are unchanged" (the reply was folded: rows `4,...,10`).

- [ ] **Step 3: Ignore a good reply behind the cursor**

In `applyEvents`, replace its comment and body:

```qml
  // One events reply, applied only while `launchedGuard` is still the
  // selected run. ok true with an events array: foldReply. ok false: error
  // with Runs.errorText. Anything else: error, "no usable result". A failure
  // keeps events, eventsDropped and eventsCursor. Never touches any other
  // state.
  function applyEvents(stdout, exitCode, launchedGuard) {
    if (launchedGuard !== store.selectedRunId) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true && Array.isArray(envelope.events)) {
      store.foldReply(envelope)
      return
    }
```

with:

```qml
  // One events reply, applied only while `launchedGuard` is still the
  // selected run. ok true with an events array: foldReply, unless its
  // last_seq is a non-negative integer below eventsCursor, which keeps
  // events, eventsDropped and eventsCursor. Either way ok, no error. ok
  // false: error with Runs.errorText. Anything else: error, "no usable
  // result". A failure keeps events, eventsDropped and eventsCursor. Never
  // touches any other state.
  function applyEvents(stdout, exitCode, launchedGuard) {
    if (launchedGuard !== store.selectedRunId) return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true && Array.isArray(envelope.events)) {
      if (store.isSeq(envelope.last_seq) && envelope.last_seq < store.eventsCursor) {
        store.eventsStatus = "ok"
        store.eventsError = ""
        return
      }
      store.foldReply(envelope)
      return
    }
```

(The three lines after it — `store.eventsStatus = "error"` and the two `eventsError` lines — stay as they are.)

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command again. Expected: PASS.
Then the whole store file:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"
```
Expected: only a `Totals: ... 0 failed` line.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): an events reply behind the cursor keeps the held rows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: One queued follow-up behind the fetch in flight; a selection or a closing clears it

**Files:**
- Modify: `core/stores/RunStore.qml` — `eventsState` (added in Task 1), `nudgeEvents()` (Task 1), new `followUpEvents()` after `fetchNewEvents()`, `eventsRunner`'s `onFinished` and comment (lines 1919-1926 before Task 1; find by `id: eventsRunner`), `selectEvents()` (lines 867-880), `stopLive()` and its comment (lines 386-406)
- Test: `tests/core/stores/tst_run_store.qml` (append before the final `}`)

**Interfaces:**
- Consumes: `nudgeEvents(ids)`, `fetchNewEvents()`, `eventsState.kind` (Task 1); `applyEvents(...)` (Task 2); `activeHeld()` (Task 1 tests).
- Produces: `eventsState.followUp` (bool, private); `function followUpEvents()` (no return), called from `eventsRunner.onFinished` after `applyEvents`.

- [ ] **Step 1: Write the failing queue tests**

Append before the file's final `}`:

```qml
  // An open panel with r1 selected: its --tail 200 fetch in flight.
  function activeSelected() {
    var store = make(); if (!store) return null
    store.active = true
    store.selectedRunId = "r1"
    return store
  }

  // 4
  function test_changes_during_a_fetch_queue_one_follow_up() {
    var store = activeSelected(); if (!store) return
    var tail = store.eventsRunner.current
    var seq = store.eventsRunner.seq
    store.runsNudged(["r1"])
    store.runsNudged(["r1"])
    store.runsNudged(["r2", "r1"])
    verify(store.eventsRunner.current === tail, "the fetch in flight is left alone")
    compare(tail.running, true)
    compare(store.eventsRunner.seq, seq)
    reply(tail, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    compare(seqs(store.events), "8,9,10", "its reply is applied")
    compare(store.eventsRunner.seq, seq + 1, "exactly one follow-up")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|10")
    compare(store.eventsStatus, "loading")
    reply(store.eventsRunner.current, eventsReply([], 10, 0), 0)
    compare(store.eventsRunner.seq, seq + 1, "nothing more")
    compare(store.eventsRunner.busy, false)
    compare(store.eventsStatus, "ok")
  }

  // 5
  function test_a_change_during_the_follow_up_queues_one_more() {
    var store = activeSelected(); if (!store) return
    store.runsNudged(["r1"])
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    var followUp = store.eventsRunner.current
    compare(argv(followUp), tc.eventsCmd + "r1|--since|10")
    var seq = store.eventsRunner.seq
    store.runsNudged(["r1"])
    verify(store.eventsRunner.current === followUp, "the follow-up is left alone")
    reply(followUp, eventsReply(attemptEvents(11, 2), 12, 2), 0)
    compare(seqs(store.events), "8,9,10,11,12")
    compare(store.eventsRunner.seq, seq + 1)
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|12", "from the cursor the reply raised")
  }

  // 6
  function test_the_follow_up_runs_after_a_failed_reply() {
    var store = activeHeld(); if (!store) return
    store.runsNudged(["r1"])
    var first = store.eventsRunner.current
    store.runsNudged(["r1"])
    reply(first, JSON.stringify({ ok: false, error: { type: "UnknownRunError", message: "no run r1" } }) + "\n", 0)
    compare(store.eventsError, "UnknownRunError: no run r1", "the failure was applied")
    verify(store.eventsRunner.current !== first, "then the follow-up launched")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|10", "from the unchanged cursor")
    compare(store.eventsStatus, "loading")
    compare(seqs(store.events), "8,9,10")
    compare(store.eventsDropped, 7)
    var second = store.eventsRunner.current
    store.runsNudged(["r1"])
    reply(second, "not json\n", 1)
    compare(store.eventsError, "The events snapshot gave no usable result (exit 1).")
    verify(store.eventsRunner.current !== second, "an unusable reply is followed up too")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|10")
    reply(store.eventsRunner.current, eventsReply(attemptEvents(11, 1), 11, 1), 0)
    compare(store.eventsStatus, "ok")
    compare(store.eventsError, "")
    compare(seqs(store.events), "8,9,10,11")
  }

  // Review Focus 1
  function test_a_refresh_supersedes_a_change_fetch_and_the_follow_up_waits() {
    var store = activeHeld(); if (!store) return
    store.runsNudged(["r1"])
    var change = store.eventsRunner.current
    store.runsNudged(["r1"])
    store.refreshEvents()
    var refresh = store.eventsRunner.current
    compare(argv(refresh), tc.eventsCmd + "r1|--tail|200")
    compare(change.running, false, "latest wins")
    var seq = store.eventsRunner.seq
    reply(change, eventsReply(attemptEvents(11, 1), 11, 1), 0)
    compare(store.eventsRunner.seq, seq, "the superseded fetch's exit launches nothing")
    compare(seqs(store.events), "8,9,10", "and is not applied")
    reply(refresh, eventsReply(attemptEvents(11, 2), 12, 20), 0)
    compare(seqs(store.events), "8,9,10,11,12")
    compare(store.eventsDropped, 15, "a --tail reply: 20 - 2 - 3 held below")
    compare(store.eventsRunner.seq, seq + 1, "the queued follow-up runs after the refresh")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|12")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml \
  StoresRunStore::test_changes_during_a_fetch_queue_one_follow_up \
  StoresRunStore::test_a_change_during_the_follow_up_queues_one_more \
  StoresRunStore::test_the_follow_up_runs_after_a_failed_reply \
  StoresRunStore::test_a_refresh_supersedes_a_change_fetch_and_the_follow_up_waits
```
Expected: all 4 FAIL at their "follow-up" assertions (`eventsRunner.seq` one short: a change during a fetch is dropped).

- [ ] **Step 3: Queue the follow-up and launch it after the reply**

In `eventsState`, replace:

```qml
  // The selected run's events fetches' own state; kept apart so consumers
  // cannot write it. `kind` is the newest launch's: "tail" (RUN --tail 200)
  // or "since" (RUN --since eventsCursor).
  QtObject {
    id: eventsState
    property string kind: "tail"
  }
```

with:

```qml
  // The selected run's events fetches' own state; kept apart so consumers
  // cannot write it. `kind` is the newest launch's: "tail" (RUN --tail 200)
  // or "since" (RUN --since eventsCursor). `followUp`: one change fetch
  // waits behind the fetch in flight.
  QtObject {
    id: eventsState
    property string kind: "tail"
    property bool followUp: false
  }
```

Replace `nudgeEvents` (from Task 1):

```qml
  // A debounce window's run ids (runsNudged). While active, with ids an array
  // holding selectedRunId: the change fetch (fetchNewEvents), unless a fetch
  // is in flight, which is left alone. The run's status is never read.
  function nudgeEvents(ids) {
    if (!store.active || store.selectedRunId === "" || !Array.isArray(ids)) return
    if (ids.indexOf(store.selectedRunId) < 0) return
    if (eventsRunner.busy) return
    store.fetchNewEvents()
  }
```

with:

```qml
  // A debounce window's run ids (runsNudged). While active, with ids an array
  // holding selectedRunId: the change fetch (fetchNewEvents), or, while a
  // fetch is in flight, one follow-up queued behind it (followUpEvents); the
  // fetch in flight is left alone. The run's status is never read.
  function nudgeEvents(ids) {
    if (!store.active || store.selectedRunId === "" || !Array.isArray(ids)) return
    if (ids.indexOf(store.selectedRunId) < 0) return
    if (eventsRunner.busy) {
      eventsState.followUp = true
      return
    }
    store.fetchNewEvents()
  }
```

Right after `fetchNewEvents()` (from Task 1) add:

```qml

  // The fetch in flight ended and its reply is applied: a queued follow-up is
  // taken and, while active with a run selected, the change fetch launches
  // from the state that reply left.
  function followUpEvents() {
    if (!eventsState.followUp) return
    eventsState.followUp = false
    if (store.active && store.selectedRunId !== "") store.fetchNewEvents()
  }
```

Replace the `eventsRunner` block:

```qml
  // The selected run's events helper. Guard: the run id a fetch was launched
  // for, never the open project. A newer fetch wins over an older one, and a
  // reply is applied only while its run is still the selected one.
  HelperRunner {
    id: eventsRunner
    script: store.backendDir + "runs/runs-events.py"
    onFinished: function(stdout, exitCode, launchedGuard) { store.applyEvents(stdout, exitCode, launchedGuard) }
  }
```

with:

```qml
  // The selected run's events helper. Guard: the run id a fetch was launched
  // for, never the open project. A newer fetch wins over an older one, and a
  // reply is applied only while its run is still the selected one; then a
  // queued follow-up launches (followUpEvents).
  HelperRunner {
    id: eventsRunner
    script: store.backendDir + "runs/runs-events.py"
    onFinished: function(stdout, exitCode, launchedGuard) {
      store.applyEvents(stdout, exitCode, launchedGuard)
      store.followUpEvents()
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command again. Expected: all 4 PASS.

- [ ] **Step 5: Write the failing clearing tests**

Append before the file's final `}`:

```qml
  // 7
  function test_a_new_selection_clears_the_queue() {
    var store = activeSelected(); if (!store) return
    var p1 = store.eventsRunner.current
    store.runsNudged(["r1"])
    store.selectedRunId = "r2"
    var p2 = store.eventsRunner.current
    compare(argv(p2), tc.eventsCmd + "r2|--tail|200")
    var seq = store.eventsRunner.seq
    reply(p1, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(store.eventsRunner.seq, seq, "r1's late exit launches nothing")
    reply(p2, eventsReply(attemptEvents(5, 2), 6, 6), 0)
    compare(seqs(store.events), "5,6")
    compare(store.eventsRunner.seq, seq, "no follow-up: the queue went with r1")
    compare(store.eventsRunner.busy, false)

    store.selectedRunId = "r1"
    var p3 = store.eventsRunner.current
    store.runsNudged(["r1"])
    store.selectedRunId = ""
    compare(store.eventsRunner.busy, false)
    seq = store.eventsRunner.seq
    reply(p3, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(store.eventsRunner.seq, seq, "nothing is launched after leaving")
    compare(store.eventsStatus, "idle")
    store.selectedRunId = "r1"
    var p4 = store.eventsRunner.current
    seq = store.eventsRunner.seq
    reply(p4, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(seqs(store.events), "1,2,3")
    compare(store.eventsRunner.seq, seq, "the queue went with leaving")
  }

  // 8 and Review Focus 2
  function test_closing_the_panel_starts_nothing_new() {
    var store = activeSelected(); if (!store) return
    var tail = store.eventsRunner.current
    store.runsNudged(["r1"])
    store.active = false
    compare(tail.running, true, "the fetch in flight is not stopped")
    verify(store.eventsRunner.current === tail)
    var seq = store.eventsRunner.seq
    reply(tail, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    compare(seqs(store.events), "8,9,10", "its reply is applied")
    compare(store.eventsStatus, "ok")
    compare(store.eventsRunner.seq, seq, "nothing is launched after it")
    store.runsNudged(["r1"])
    compare(store.eventsRunner.seq, seq, "a change while closed starts nothing")
    store.active = true
    compare(store.eventsRunner.seq, seq, "reopening launches no events fetch")
    compare(store.eventsRunner.busy, false)
    compare(seqs(store.events), "8,9,10", "reopening keeps the rows")
    store.runsNudged(["r1"])
    compare(store.eventsRunner.seq, seq + 1)
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--since|10")

    var change = store.eventsRunner.current
    store.runsNudged(["r1"])
    store.active = false
    reply(change, eventsReply(attemptEvents(11, 1), 11, 1), 0)
    compare(seqs(store.events), "8,9,10,11", "its reply is applied")
    compare(store.eventsRunner.seq, seq + 1, "a change queued before a closing does not outlive it")
  }
```

- [ ] **Step 6: Run the clearing tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml \
  StoresRunStore::test_a_new_selection_clears_the_queue StoresRunStore::test_closing_the_panel_starts_nothing_new
```
Expected: both FAIL — `test_a_new_selection_clears_the_queue` at "no follow-up: the queue went with r1" (r2's reply launched `r2|--since|6`); `test_closing_the_panel_starts_nothing_new` at "nothing is launched after it" (the queued change ran after the tail reply).

- [ ] **Step 7: Clear the queue on a selection and on closing**

In `selectEvents()` replace:

```qml
  // No events held; then the selected run's last 200 are fetched, or, with
  // no run selected, the fetch in flight is stopped and the status is idle.
  function selectEvents() {
    store.events = []
```

with:

```qml
  // No events held and no follow-up queued; then the selected run's last 200
  // are fetched, or, with no run selected, the fetch in flight is stopped and
  // the status is idle.
  function selectEvents() {
    eventsState.followUp = false
    store.events = []
```

In `stopLive()` replace its comment and first lines:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The project filter is back to All projects, with no
  // projectFilterToggled. The runs, the selection, the chip and amStatus stay
  // for the next opening.
  function stopLive() {
    store.projectFilter = ""
    snapshotState.pending = null
```

with:

```qml
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The queued events follow-up is dropped; an events fetch
  // in flight runs to its end and is applied. The project filter is back to
  // All projects, with no projectFilterToggled. The runs, the selection, the
  // events, the chip and amStatus stay for the next opening.
  function stopLive() {
    store.projectFilter = ""
    snapshotState.pending = null
    eventsState.followUp = false
```

- [ ] **Step 8: Run the tests to verify they pass**

Run the Step 6 command, then the Step 2 command. Expected: all PASS.

- [ ] **Step 9: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest green (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`), every QML file's `Totals` line with `0 failed`, exit status 0, no `TypeError`/`ReferenceError` lines.

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): changes during an events fetch queue one follow-up; a selection or closing clears it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Spec coverage (self-review)

| spec item | task / test |
|---|---|
| Behavior 1: nothing when inactive, no selection, ids not an array, ids without the selected id | Task 1: `test_no_selection_a_closed_panel_or_bad_ids_fetch_nothing`, `test_a_change_for_other_runs_fetches_nothing` |
| Behavior 1: no fetch in flight launches now; in flight queues exactly one | Task 1: `test_a_change_fetches_since_the_cursor`; Task 3: `test_changes_during_a_fetch_queue_one_follow_up` |
| Behavior 1: status never read (finish case) | Task 1: `test_a_finished_run_gets_its_last_events_from_the_watch` |
| Behavior 2: `--since` argv, guard, loading, no reset; cursor 0 uses `--tail 200` | Task 1: `test_a_change_fetches_since_the_cursor`, `test_a_change_passes_the_run_id_verbatim`, `test_a_change_with_no_cursor_fetches_the_last_200` |
| Behavior 3: follow-up after any reply, from the raised cursor; one more during a follow-up | Task 3: tests 4, 5, 6 |
| Behavior 3: new selection / leaving clears the queue | Task 3: `test_a_new_selection_clears_the_queue` |
| Behavior 3: panel closes clears the queue, in-flight applied, closed nudges nothing, reopen launches nothing | Task 3: `test_closing_the_panel_starts_nothing_new` |
| Behavior 3: refresh keeps latest-wins, queue stays | Task 3: `test_a_refresh_supersedes_a_change_fetch_and_the_follow_up_waits` |
| Behavior 4: behind-cursor ignored, equal folded | Task 2: `test_a_reply_behind_the_cursor_is_ignored` |
| Behavior 4: fold follows newest launch kind; `--since` dropped formula; cursor rule | Task 1 (kind, formula); Task 3 refresh test; Task 1 tests 1, 10, 13, RF3 |
| Untouched state | Task 1: `test_a_change_fetches_since_the_cursor` "nothing else is touched"; project switch: 3.1's `test_a_project_switch_leaves_the_events_alone` stays green, no code path in `projectSwitched()` changed |
| Error paths table | refusal: Task 3 test 6; unusable: Task 3 test 6; tail-failed then change: Task 1 test 12; behind: Task 2; stale run: Task 3 test 7; closed: Task 3 test 8; burst: Task 3 test 4 |
| Unchanged gates | Task 1 Step 7, Task 2 Step 4, Task 3 Step 9 |
<!-- task-pipeline: validated -->
