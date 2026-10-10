# 3.1 RunStore: the selected run's events — design

Card `2d3dfc27`, a subtask of story `59f54c51`. Parent spec:
`docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (below:
**parent**, cited `L<n>`). Builds on `core/domain/runEvents.js` (cards 1.x) and
`core/backend/runs/runs-events.py` (card 2.1, spec
`docs/superpowers/specs/2-1-runs-events-py-one-4f30a6e0.md`, below: **2.1**).

## Goal

`RunStore` holds the selected run's event timeline: when a run is selected it
fetches that run's last 200 events once through `runs-events.py`, turns them into
timeline rows, and exposes the rows, how many events it does not hold, the
highest seq, a fetch status and error, and a filter value. `App` hands the store a
card id -> title map built from the open project's board. Nothing in `ui/` reads
any of it yet.

## Card vs parent: what governs

| topic | parent | card / reality (governs) |
|---|---|---|
| helper argv | `runs-events.py RUN [--after-seq N] [--before-seq N] [--tail N] [--limit K]` (L77) | `runs-events.py RUN [--since SEQ] [--tail N]` (2.1 "Behavior"; `core/backend/runs/runs-events.py:2-4`). This card uses only `RUN --tail 200`. |
| helper reply | `{ok, events, head}` (L78) | `{ok:true, events, last_seq, total}` or `{ok:false, error:{type,message}}`, exit 0; Usage exits 2 with a line (`runs-events.py:11-37`) |
| fold function | `mergeRows` deduping by `gseq` (L73) | `RunEvents.foldEvents(rows, events, cap)` deduping by `seq` (`core/domain/runEvents.js:113-145`) |
| cursor | `eventsCursor` highest `gseq` (L83) | highest `seq` (card) |
| dropped count | `eventsHasEarlier`, `eventsOldestSeq` (L82-84) | `eventsDropped` (card); `eventsHasEarlier`, `eventsOldestSeq` are not part of this card |

## Inherited constraints

| constraint | source |
|---|---|
| Selecting a run resets the events and fetches the last 200 with `--tail 200`; never replays from the start | parent L94-95; card |
| Leaving Run detail or switching runs clears the events and stops fetching | parent L103; card |
| A reply for a run that is no longer selected is dropped | parent L101; card |
| One `HelperRunner`, latest wins, not guarded by the open project; a project switch changes nothing | parent L85-86, L160, L177; card |
| At most 500 rows held, oldest (lowest seq) dropped | parent L82, L161; `runEvents.js:113-120` default cap 500 |
| `titles` is handed in by App: the open project's card id -> title map; the run's own story titles from its `am status` tree complete it; a subtask of a project that is not open shows its short card id | parent L86-89; card |
| Rows are `RunEvents.eventRow(event, titles, utcOffsetMinutes)`; the store passes the local offset `-new Date().getTimezoneOffset()` | parent L72-76; card; `runEvents.js:58-99` |
| `eventsStatus` is `idle | loading | ok | error`; a failure keeps the rows | parent L84, L157; card |
| Unknown events and keys are ignored | parent L62, L159; `eventRow` returns `null` for them |
| Stores import only `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js`; the run store never imports another store, App hands values in through properties | `docs/architecture.md:14`, `:23`; `tests/architecture/test_layers.py`; `core/stores/App.qml:107-110` |
| No icon glyph characters in store code, comments or strings | card; `tests/architecture/test_icon_glyphs.py` |
| Comments and docstrings state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

## Behavior

### State (all on `RunStore`)

| property | type, default | meaning |
|---|---|---|
| `titles` | `var`, `{}` | card id -> title, handed in by App |
| `events` | `var`, `[]` | the held rows, ascending `seq`, at most 500; replaced, never changed in place |
| `eventsDropped` | `int`, `0` | events of the selected run the store does not hold: `(total - events received) + rows dropped by the cap` |
| `eventsCursor` | `int`, `0` | the highest seq seen for the selected run |
| `eventsStatus` | `string`, `"idle"` | `idle` (no run selected, or reset), `loading` (a fetch is in flight), `ok` (the last reply was good), `error` (the last reply failed) |
| `eventsError` | `string`, `""` | why the last fetch failed; `""` after a good one and after a reset |
| `eventsFilter` | `string`, `"All"` | the timeline filter value (`All`, `Phases`, `Failures`, read by `RunEvents.filterRows`); the store never changes it |
| `eventsRunner` | readonly alias | the events `HelperRunner`, for tests |

### Selection

1. **Selecting a run** (`selectedRunId` changes to a non-empty id): `events` `[]`,
   `eventsDropped` `0`, `eventsCursor` `0`, `eventsError` `""`, then
   `eventsStatus` `loading` and one launch on the events runner with argv
   exactly `["python3", backendDir + "runs/runs-events.py", RUN, "--tail", "200"]`
   (`RUN` the selected id verbatim, one element whatever characters it holds; no
   project root argument). The run need not be in `runs`: a selected run the
   snapshot does not list is still fetched. The selection's existing logs
   behaviour (`clearLogs`, `openDefaultAttempt`, `RunStore.qml:840-844`) is
   unchanged.
2. **Switching runs** (another non-empty id): as 1; the previous fetch is
   superseded (its process stopped) and its reply, if it still arrives, changes
   nothing.
3. **Leaving Run detail** (`selectedRunId` becomes `""`): the reset of 1,
   `eventsStatus` `idle`, the runner cancelled (busy false); a late reply changes
   nothing, and nothing is launched.
4. Setting `selectedRunId` to the value it already holds does nothing (no reset,
   no launch).
5. `eventsFilter` is not touched by selection, switching or leaving.
6. **`refreshEvents()`** fetches the selected run again with the same argv as 1,
   without the reset: `eventsStatus` `loading`, rows, dropped, cursor and error
   kept until the reply; its reply is folded into the held rows (dedupe by seq).
   With no run selected it does nothing. It exists so that "a failure keeps the
   rows" is observable for a run that already holds rows (the card's
   "error keeps rows"); no UI calls it in this card.

### Applying a reply

The reply's envelope is the helper's last non-blank stdout line parsed as a JSON
object (the store's existing `parseEnvelope`, `RunStore.qml:862-876`).

- **Stale.** A reply whose fetch was launched for a run id other than the current
  `selectedRunId` changes no state at all. The store sets `eventsRunner.guard`
  to the run id at each launch and applies a reply only when its `launchedGuard`
  (the `finished` signal's third argument) still equals `selectedRunId`; the
  runner's latest-wins already drops a superseded process's exit, and the guard
  check is the additional run-id check (never a project guard).
- **Good** — envelope `ok === true` and `events` an array:
  - each element through `RunEvents.eventRow(element, effectiveTitles,
    -new Date().getTimezoneOffset())`; `null` results (unknown kinds, non-objects)
    are skipped;
  - `fold = RunEvents.foldEvents(events, rowsOfThisReply, 500)` (the held rows
    are `[]` after a selection, so a first fetch replaces); `events` becomes
    `fold.rows`;
  - `received` = the reply's `events.length`; `total` = the reply's `total` when
    it is an integer `>= received`, else `received`;
    `eventsDropped = max(0, (total - received) - priorBelow) + fold.dropped`
    (replacing the previous value), `priorBelow` the number of rows held before
    this reply whose seq is below the lowest `seq` among the reply's events (0
    for a first fetch, so it is `(total - received) + fold.dropped` there; on a
    `refreshEvents()` reply the older rows already held fill part of the gap);
  - `eventsCursor` = the largest of its current value, the reply's `last_seq`
    when that is a non-negative integer, and the highest `seq` among the held rows;
  - `eventsStatus` `ok`, `eventsError` `""`.
- **Failure envelope** — `ok === false`: `eventsStatus` `error`, `eventsError`
  `Runs.errorText(envelope)` (e.g. `UnknownRunError: …`, `AmMissing: …`,
  `CorruptJournal: …`); `events`, `eventsDropped`, `eventsCursor` unchanged.
- **Unusable** — no envelope, or `ok` not a boolean, or `ok === true` without an
  array `events`: as a failure, with `eventsError`
  `"The events snapshot gave no usable result (exit N)."`, `N` the exit code.
- A reply never touches `amStatus`, `lastError`, `runs`, the logs state or any
  other store state.

### Titles

`effectiveTitles` for a reply is a fresh object: every own key of `titles`
whose value is a non-empty string, then, for each story object in
`runById(selectedRunId).tree.stories` with a string `card_id` and a non-empty
string `title`, that title **only where the open project's map has none** (the
open project's title wins; the tree completes it). When the run is not in `runs`
the tree adds nothing. An id in neither map gets `eventRow`'s fallback, the
short id `"…" + last 8 characters` (`runs.js:528-531`). `titles` itself is never
modified. Rows are labelled when their reply is applied; a later change of
`titles` or of the tree does not relabel held rows.

### Project switch and panel

Changing `project` (or `projectRoots`) neither resets the events nor launches a
fetch nor cancels one; a reply launched before the switch is applied normally.
`active` is not read by the events state in this card.

### App

`App.qml`'s `RunStore` gets `titles` bound to a map built from
`app.board.cardMap` (`BoardStore.qml:24`, id -> card): `{id: card.title}` for
each card whose `title` is a string. The binding re-evaluates whenever
`cardMap` is replaced. The run store still imports no other store; App's comment
above the run store (`App.qml:107-110`) names `titles` among the values it hands
in.

## Error paths

| case | behaviour |
|---|---|
| am missing (`AmMissing`) | `eventsStatus` error, `eventsError` `AmMissing: …`, rows kept |
| unknown run (`UnknownRunError`) | error status with that sentence; rows kept (they were reset on selection, so normally none) |
| journal unreadable (`CorruptJournal`, `StoreBusyError`) | error status with that sentence; rows kept |
| helper Usage (exit 2 with a line) | error status, `Usage: …` |
| stdout empty / not JSON / a crash | error status, `The events snapshot gave no usable result (exit N).` |
| reply for a superseded selection | dropped |
| reply after leaving Run detail | dropped |
| more than 500 rows in one reply | lowest seqs dropped, counted in `eventsDropped` |

## Tests

All new tests are QML store tests run by `qmltestrunner` through
`bash tests/run.sh`, against stubbed `Process` objects (`tests/stubs`), because
the behaviour is store state reacting to a property change and a helper reply —
no real process, clock or time zone is involved. Each test ships failing first.

`tests/core/stores/tst_run_store.qml` (TestCase `StoresRunStore`), new
`eventsCmd` constant `"python3|/plugin/core/backend/runs/runs-events.py|"`:

1. **defaults** — a fresh store: `events` `[]`, `eventsDropped` 0,
   `eventsCursor` 0, `eventsStatus` `idle`, `eventsError` `""`, `eventsFilter`
   `All`, `titles` `{}`, no events launch.
2. **the first fetch argv** — selecting `r1` launches `eventsCmd + "r1|--tail|200"`,
   `eventsStatus` `loading`; a run id with a space and `;` reaches argv as one
   element unchanged.
3. **reset on selection** — after a good reply for `r1` (rows held, dropped and
   cursor non-zero), selecting `r2` empties rows, zeroes dropped and cursor,
   clears the error, is `loading`, launches `r2`'s argv, and stops `r1`'s
   process; the filter set to `Failures` before survives.
4. **a good reply** — events built from `tests/fixtures/am/watch-events.json`
   (mixed kinds): rows are exactly the `*_upsert` events, ascending seq;
   `eventsCursor` = `last_seq`; `eventsStatus` `ok`; `eventsDropped` =
   `total - received`.
5. **titles fallback** — with `titles` holding a subtask id, a reply whose
   events name that subtask, a story listed in the selected run's tree (title
   from the tree), a story id in both maps (open project's title wins), and a
   subtask in neither (label `"…" + last 8`). Uses a run from the recorded
   `status-started.json` tree (`treeEntry`).
6. **cap and dropped** — one reply of 600 `attempt_upsert` events with `total`
   1000: 500 rows held, the lowest is seq 101, `eventsDropped` 500
   (`1000 - 600 + 100`).
7. **error keeps rows** — select `r1`, good reply (rows held), `refreshEvents()`
   (status `loading`, rows still held, argv again `eventsCmd + "r1|--tail|200"`),
   then a refusal envelope (`UnknownRunError`): status `error`, `eventsError`
   `UnknownRunError: …`, rows, dropped and cursor unchanged. A further
   `refreshEvents()` answered with `not json` at exit 1 gives
   `The events snapshot gave no usable result (exit 1).` with the rows still held.
8. **a stale reply dropped** — select `r1`, keep its process, select `r2`;
   replying to `r1`'s process changes nothing (status still `loading`, no rows);
   `r2`'s reply lands.
9. **leaving clears and drops** — select `r1`, set `selectedRunId` `""`: reset,
   `idle`, runner not busy, `r1`'s process stopped; a late reply to it changes
   nothing.
10. **a project switch changes nothing** — with rows held, switching `project`
    to another root keeps every events property and launches nothing; with a
    fetch in flight, the switch does not stop it and its reply lands.
11. **a reply touches nothing else** — an error reply leaves `amStatus`,
    `lastError` and the logs state as they were.
12. **re-selecting the same id** — no reset, no new launch.

`tests/core/stores/tst_app_runs.qml` (TestCase `StoresAppRuns`, wiring only):

13. **titles follows the board** — setting `app.board.cardMap` to
    `{c1: {title: "One"}, c2: {title: 7}}` gives `app.runs.titles`
    `{c1: "One"}`; replacing `cardMap` with `{c3: {title: "Three"}}` gives
    `{c3: "Three"}`.

Unchanged gates that must stay green: `tests/architecture/test_layers.py`
(store import allowlist), `tests/architecture/test_icon_glyphs.py`,
`tests/core/domain/tst_run_events.qml`.

## Out of scope

- `ui/components/EventsPane.qml`, `RunDetailScreen` wiring, the Output/Events
  tabs, the `e` key, filter chips UI, follow/jump (sibling UI cards; parent
  L124-149).
- Paging earlier events (`--before-seq`, `eventsHasEarlier`, `eventsOldestSeq`;
  parent L96-97).
- Live append on watch nudges / `runsNudged` / `--since eventsCursor`, the
  follow-up-after-in-flight rule, and the final fetch of a finishing run (parent
  L98-104).
- Stopping events work when the panel closes (parent L105).
- Relabelling held rows when `titles` or the tree changes.
- Any change to `runs-events.py`, `runEvents.js` or `runs.js`.
- Updating the RunStore paragraph in `docs/architecture.md`.
