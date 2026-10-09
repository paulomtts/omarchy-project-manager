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
