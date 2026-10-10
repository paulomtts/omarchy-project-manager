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

---

# 3.1 RunStore: the selected run's events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` fetches the selected run's last 200 events once per selection through `runs-events.py RUN --tail 200`, holds them as `RunEvents.eventRow` rows (at most 500, ascending seq) with `eventsDropped`, `eventsCursor`, `eventsStatus`, `eventsError` and `eventsFilter`, and App hands it a `titles` map built from the open project's board.

**Architecture:** One new `HelperRunner` (`eventsRunner`, guard = the run id at launch) inside `core/stores/RunStore.qml`. `onSelectedRunIdChanged` resets the events state and launches (or, for `""`, cancels); `applyEvents` drops a reply whose guard is no longer `selectedRunId`, folds a good reply through `RunEvents.eventRow` / `RunEvents.foldEvents`, and turns anything else into an error that keeps the rows. `eventTitles()` merges `titles` with the selected run's tree story titles. `App.qml` binds `titles` from `app.board.cardMap`.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), plain JS domain libraries (`core/domain/runEvents.js`, `core/domain/runs.js`), QtTest via `qmltestrunner` with stubbed `Process` (`tests/stubs`).

**Spec:** `docs/superpowers/specs/3-1-runstore-the-2d3dfc27.md` (prepended above).

## Global Constraints

- Helper argv exactly `["python3", backendDir + "runs/runs-events.py", RUN, "--tail", "200"]`; `RUN` the selected id verbatim as one element; no project root argument; never `--since` in this card.
- Reply envelope: the helper's last non-blank stdout line parsed as a JSON object (`store.parseEnvelope`). Good: `{ok:true, events, last_seq, total}`; failure: `{ok:false, error:{type,message}}`.
- At most 500 rows held (`RunEvents.foldEvents(rows, events, 500)`), oldest (lowest seq) dropped.
- Rows are `RunEvents.eventRow(event, titles, -new Date().getTimezoneOffset())`; `null` rows skipped.
- `eventsStatus` is `idle | loading | ok | error`; a failure keeps `events`, `eventsDropped`, `eventsCursor`.
- Unusable reply text: `"The events snapshot gave no usable result (exit N)."`.
- One `HelperRunner`, latest wins, guarded by the run id, never by the open project; a project switch changes nothing.
- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js`; the run store never imports another store; App hands values in through properties.
- No icon glyph characters (private-use code points) in store code, comments or strings.
- Comments and docstrings state the contract only, no narrative.
- `bash tests/run.sh` green; tests first.
- Out of scope, do not touch: `ui/`, `core/backend/runs/runs-events.py`, `core/domain/runEvents.js`, `core/domain/runs.js`, `docs/architecture.md`.

## Running the tests

`bash tests/run.sh` runs all of pytest (about 2 minutes) and then every QML test. For the TDD loop, run one QML test function in place (no copy needed):

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner \
  -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_events_defaults
```

Several functions may be listed, space-separated. Without a function name the whole file runs. A `TypeError`/`ReferenceError` in the output counts as a failure (`tests/run.sh` greps for them). `bash tests/run.sh tst_run_store` runs pytest plus only that QML file. Never use `pkill`/`killall`; stop a stuck run with `timeout`.

Test-harness facts the steps rely on (all already in `tests/core/stores/tst_run_store.qml`):

- `make()` builds a `RunStore` with `backendDir: "/plugin/core/backend/"`, no registry, no project.
- `reply(proc, text, code)` sets `proc.outText = text` and emits `proc.exited(code)`.
- `argv(proc)` is `proc.command.join("|")`.
- `opened(status)` is a store with `rootA` open whose snapshot lists `treeEntry("r1", ...)` (the run tree from `tests/fixtures/am/status-started.json`) and with `selectedRunId = "r1"`; its default attempt's logs are in flight.
- `makeWithRoots(roots)`, `registry(roots)`, `rootA`, `rootB`, `openCard` exist.
- `F.load(name)` loads `tests/fixtures/am/<name>` freshly.
- `HelperRunner.run(args)` stops `current` (`running = false`), bumps `seq`, sets `busy`, creates a stub `Process` with `launchGuard: guard` and `command = ["python3", script].concat(args)`. Its exit emits `finished(stdout, exitCode, launchedGuard)` only when `launchSeq === runner.seq` and `launchGuard === runner.guard`. `cancel()` bumps `seq`, stops `current`, sets `busy = false`, and leaves `current` pointing at the stopped process.

Fixture facts: `tests/fixtures/am/watch-events.json` `data.events` holds 60 events, seq 1..60; seq 1 is `lease_acquired`, seq 2 is `run_upsert`, and the other 58 are `*_upsert` (59 upserts in all). `status-started.json`'s stories include `card_id "9f0f68fc-f231-4ef2-b646-00a7af925ea2"` title `"Dispatch domain"` and `card_id "7a7effb4-6ec5-4596-bcf1-be24546d4ac1"` title `"Dispatch backend"`; its subtasks carry no title.

## Review Focus

1. A `refreshEvents()` reply that overlaps the held rows — rows must dedupe by seq (the reply's row winning) and `eventsDropped` must not count the older rows already held as missing. Pinned in Task 2 by `test_a_refresh_folds_into_the_held_rows`.
2. A reply that is JSON but not a usable good envelope (`{ok:true}` with no or a non-array `events`, `ok` a string, a JSON array, blank stdout), and a good reply whose `events` holds `null`, numbers, strings or unknown kinds — the first must be an error that keeps the rows, the second must skip the junk without throwing. Pinned in Task 2 by `test_an_ok_reply_without_an_events_list_is_unusable`.
3. `total` or `last_seq` missing, a string, negative, fractional or smaller than the events received — `total` falls back to the events received (no negative or inflated `eventsDropped`), `eventsCursor` to the highest held seq. Pinned in Task 2 by `test_a_bad_total_or_last_seq_falls_back`.
4. Leaving Run detail and selecting the same run again while its first fetch is in flight — the first fetch's reply carries the same run id as guard, so only latest-wins can drop it; it must change nothing. Pinned in Task 2 by `test_a_reply_after_leaving_or_reselecting_is_dropped`.
5. `titles` set to `null`, or holding a number or `""` for a card — labels fall back to the short id, nothing throws; a later reply with a real title labels the same seq anew. Pinned in Task 3 by `test_titles_that_are_not_text_fall_back_to_the_short_id`.

---

### Task 1: Events state, selection reset and the `--tail 200` launch

**Files:**
- Modify: `core/stores/RunStore.qml` (header comment lines 28-30; property block after line 117; aliases after line 206; `projectSwitched` comment lines 646-651; `onSelectedRunIdChanged` lines 840-844; a new `HelperRunner` after the `logsRunner` block ending line 1787)
- Test: `tests/core/stores/tst_run_store.qml` (new section appended before the file's final `}`)

**Interfaces:**
- Consumes: `HelperRunner` (`core/stores/HelperRunner.qml`): `run(args)`, `cancel()`, `guard`, `busy`, `seq`, `current`.
- Produces (on `RunStore`):
  - `property var titles: ({})`, `property var events: []`, `property int eventsDropped: 0`, `property int eventsCursor: 0`, `property string eventsStatus: "idle"`, `property string eventsError: ""`, `property string eventsFilter: "All"`
  - `readonly property alias eventsRunner: eventsRunner`
  - `function selectEvents()` — the selection reset + launch / cancel
  - `function refreshEvents()` — fetch the selected run again, no reset
  - `function fetchEvents()` — `eventsStatus = "loading"`, `eventsRunner.guard = selectedRunId`, `eventsRunner.run([selectedRunId, "--tail", "200"])`
  - test helper `eventsCmd` = `"python3|/plugin/core/backend/runs/runs-events.py|"`

- [ ] **Step 1: Write the failing tests**

Append this section to `tests/core/stores/tst_run_store.qml`, directly before the file's final closing `}`:

```qml
  // ---- the selected run's events (3.1)

  property string eventsCmd: "python3|/plugin/core/backend/runs/runs-events.py|"

  // 1
  function test_events_defaults() {
    var store = make(); if (!store) return
    compare(JSON.stringify(store.events), "[]")
    compare(store.eventsDropped, 0)
    compare(store.eventsCursor, 0)
    compare(store.eventsStatus, "idle")
    compare(store.eventsError, "")
    compare(store.eventsFilter, "All")
    compare(JSON.stringify(store.titles), "{}")
    verify(!store.eventsRunner.current, "no events fetch at start")
  }

  // 2
  function test_selecting_a_run_fetches_its_last_200_events() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var proc = store.eventsRunner.current
    verify(proc, "a run the snapshot does not list is still fetched")
    compare(argv(proc), tc.eventsCmd + "r1|--tail|200")
    compare(proc.command.length, 5, "no project root argument")
    compare(proc.launchGuard, "r1", "guarded by the run id")
    compare(store.eventsStatus, "loading")
    compare(store.eventsRunner.busy, true)
    // synthetic: a run id with a space and a ";".
    store.selectedRunId = "r 2;x"
    compare(store.eventsRunner.current.command.length, 5)
    compare(store.eventsRunner.current.command[2], "r 2;x", "one argument, unchanged")
  }

  // 3 (the reset)
  function test_switching_runs_resets_the_events_and_stops_the_old_fetch() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var first = store.eventsRunner.current
    // synthetic: the state a reply would have left.
    store.events = [{ seq: 4 }]
    store.eventsDropped = 7
    store.eventsCursor = 9
    store.eventsStatus = "error"
    store.eventsError = "UnknownRunError: no run r1"
    store.eventsFilter = "Failures"
    store.selectedRunId = "r2"
    compare(JSON.stringify(store.events), "[]")
    compare(store.eventsDropped, 0)
    compare(store.eventsCursor, 0)
    compare(store.eventsError, "")
    compare(store.eventsStatus, "loading")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r2|--tail|200")
    compare(first.running, false, "r1's fetch was stopped")
    compare(store.eventsFilter, "Failures", "the filter is never touched")
  }

  // 9 (the reset)
  function test_leaving_run_detail_resets_and_launches_nothing() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var proc = store.eventsRunner.current
    // synthetic: the state a reply would have left.
    store.events = [{ seq: 4 }]
    store.eventsDropped = 7
    store.eventsCursor = 9
    store.eventsError = "AmMissing: am is not on PATH."
    store.eventsFilter = "Phases"
    store.selectedRunId = ""
    compare(JSON.stringify(store.events), "[]")
    compare(store.eventsDropped, 0)
    compare(store.eventsCursor, 0)
    compare(store.eventsError, "")
    compare(store.eventsStatus, "idle")
    compare(store.eventsRunner.busy, false)
    compare(proc.running, false, "r1's fetch was stopped")
    verify(store.eventsRunner.current === proc, "nothing new is launched")
    compare(store.eventsFilter, "Phases")
  }

  // 12
  function test_selecting_the_selected_run_again_does_nothing() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var proc = store.eventsRunner.current
    var seq = store.eventsRunner.seq
    // synthetic: the state a reply would have left.
    store.events = [{ seq: 4 }]
    store.eventsStatus = "ok"
    store.selectedRunId = "r1"
    compare(store.eventsRunner.seq, seq, "no new launch")
    verify(store.eventsRunner.current === proc)
    compare(store.events.length, 1, "no reset")
    compare(store.eventsStatus, "ok")
  }

  // Behavior: Selection 6
  function test_refresh_events_fetches_again_without_a_reset() {
    var store = make(); if (!store) return
    store.refreshEvents()
    verify(!store.eventsRunner.current, "no run selected: nothing is launched")
    compare(store.eventsStatus, "idle")
    store.selectedRunId = "r1"
    var first = store.eventsRunner.current
    // synthetic: the state a reply would have left.
    store.events = [{ seq: 4 }]
    store.eventsDropped = 7
    store.eventsCursor = 9
    store.eventsStatus = "error"
    store.eventsError = "AmMissing: am is not on PATH."
    store.refreshEvents()
    verify(store.eventsRunner.current !== first, "a new fetch")
    compare(first.running, false, "the older fetch was stopped")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--tail|200")
    compare(store.eventsRunner.current.launchGuard, "r1")
    compare(store.eventsStatus, "loading")
    compare(store.events.length, 1, "the rows stay until the reply")
    compare(store.eventsDropped, 7)
    compare(store.eventsCursor, 9)
    compare(store.eventsError, "AmMissing: am is not on PATH.", "the error stays until the reply")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_events_defaults StoresRunStore::test_selecting_a_run_fetches_its_last_200_events StoresRunStore::test_switching_runs_resets_the_events_and_stops_the_old_fetch StoresRunStore::test_leaving_run_detail_resets_and_launches_nothing StoresRunStore::test_selecting_the_selected_run_again_does_nothing StoresRunStore::test_refresh_events_fetches_again_without_a_reset
```
Expected: all six FAIL (e.g. `Compared values are not the same` on `JSON.stringify(store.events)` / `TypeError: Cannot read property 'current' of undefined` / `TypeError: Property 'refreshEvents' of object ... is not a function`).

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) Header comment — replace

```qml
// the watch's last cursor, held in memory only. Logs are fetched on a
// selection, on Refresh and when a snapshot changes the selected attempt's
// status -- never on a timer.
```

with

```qml
// the watch's last cursor, held in memory only. Logs are fetched on a
// selection, on Refresh and when a snapshot changes the selected attempt's
// status -- never on a timer. The selected run's events (runs-events.py RUN
// --tail 200) are fetched on a selection and on refreshEvents() -- never on
// a timer, and a project switch leaves them alone.
```

(b) After the line `  property string logsStatus: ""      // the attempt's status when its fetch was launched` add:

```qml

  // The selected run's event timeline (3.1). `titles` is the open project's
  // card id -> title map, handed in by App. `events` is RunEvents.eventRow
  // rows, ascending seq, at most 500, replaced, never changed in place.
  // A selection empties them and fetches the run's last 200 events; leaving
  // Run detail empties them and fetches nothing.
  property var titles: ({})
  property var events: []
  property int eventsDropped: 0       // the selected run's events not held
  property int eventsCursor: 0        // the highest seq seen for the selected run
  property string eventsStatus: "idle" // idle | loading | ok | error
  property string eventsError: ""     // why the last fetch failed; "" after a good one and after a reset
  property string eventsFilter: "All" // All | Phases | Failures, read by RunEvents.filterRows; the store never sets it
```

(c) After the line `  readonly property alias logsRunner: logsRunner` add:

```qml
  readonly property alias eventsRunner: eventsRunner
```

(d) In the `projectSwitched` comment replace

```qml
  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests (pending, stillWaiting,
```

with

```qml
  // Another project was opened, or none. The run list, the selection, the
  // logs, the events, the watch, the coverage, the requests (pending, stillWaiting,
```

(e) Replace

```qml
  // Another run (or none): the pane starts over on that run's default attempt.
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
  }
```

with

```qml
  // Another run (or none): the pane starts over on that run's default
  // attempt, and the events start over (selectEvents).
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
    store.selectEvents()
  }

  // ---- the selected run's events (3.1)

  // No events held; then the selected run's last 200 are fetched, or, with
  // no run selected, the fetch in flight is stopped and the status is idle.
  function selectEvents() {
    store.events = []
    store.eventsDropped = 0
    store.eventsCursor = 0
    store.eventsError = ""
    if (store.selectedRunId === "") {
      eventsRunner.cancel()
      store.eventsStatus = "idle"
      return
    }
    store.fetchEvents()
  }

  // The selected run fetched again; the rows, eventsDropped, eventsCursor and
  // eventsError stay until the reply. Nothing without a selected run.
  function refreshEvents() {
    if (store.selectedRunId === "") return
    store.fetchEvents()
  }

  // runs-events.py RUN --tail 200 for the selected run, guarded by its id.
  function fetchEvents() {
    store.eventsStatus = "loading"
    eventsRunner.guard = store.selectedRunId
    eventsRunner.run([store.selectedRunId, "--tail", "200"])
  }
```

(f) Directly after the `logsRunner` block

```qml
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    onBusyChanged: if (!logsRunner.busy) store.logsLoading = false
    onFinished: function(stdout, exitCode) { store.applyLogs(stdout, exitCode) }
  }
```

add

```qml

  // The selected run's events helper. Guard: the run id a fetch was launched
  // for, never the open project. A newer fetch wins over an older one.
  HelperRunner {
    id: eventsRunner
    script: store.backendDir + "runs/runs-events.py"
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: the six tests PASS, no `TypeError`/`ReferenceError` lines.

Then run the whole file to check nothing else moved:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"
```
Expected: `Totals: N passed, 0 failed, ...` and no other lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): selecting a run resets its events and fetches the last 200"
```

---

### Task 2: Applying an events reply

**Files:**
- Modify: `core/stores/RunStore.qml` (import block lines 1-4; the events section added in Task 1; the `eventsRunner` block added in Task 1)
- Test: `tests/core/stores/tst_run_store.qml` (import block lines 7-10; the events section added in Task 1)

**Interfaces:**
- Consumes: Task 1's `selectEvents()`, `refreshEvents()`, `fetchEvents()`, `eventsRunner`, the events properties; `store.parseEnvelope(text)` (object or null), `store.isSeq(value)` (non-negative integer), `Runs.errorText(envelope)` ("Type: message"); `RunEvents.eventRow(event, titles, utcOffsetMinutes)` (row or null), `RunEvents.foldEvents(rows, events, cap)` (`{rows, dropped}`).
- Produces (on `RunStore`):
  - `function applyEvents(stdout, exitCode, launchedGuard)` — applies a reply only while `launchedGuard === selectedRunId`
  - `function foldReply(envelope)` — the good-reply path; reads its labels from `store.titles` here (Task 3 switches it to `store.eventTitles()`)
  - `eventsRunner`'s `onFinished: function(stdout, exitCode, launchedGuard) { store.applyEvents(stdout, exitCode, launchedGuard) }`
- Produces (test helpers in `tst_run_store.qml`): `eventsReply(events, lastSeq, total)`, `attemptEvents(first, n)`, `seqs(rows)`, `heldStore()`.

- [ ] **Step 1: Write the failing tests**

(a) In `tests/core/stores/tst_run_store.qml`, replace the import block

```qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F
```

with

```qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../../core/domain/runEvents.js" as RunEvents
import "../../helpers/amFixtures.js" as F
```

(b) Append to the events section (after `test_refresh_events_fetches_again_without_a_reset`, still before the file's final `}`):

```qml
  // runs-events.py's good line: {"ok": true, "events", "last_seq", "total"}.
  function eventsReply(events, lastSeq, total) {
    return JSON.stringify({ ok: true, events: events, last_seq: lastSeq, total: total }) + "\n"
  }

  // `n` attempt_upsert journal events of card c1's explore attempt 1, seq
  // first .. first + n - 1.
  function attemptEvents(first, n) {
    var out = []
    for (var i = 0; i < n; i++) {
      out.push({ seq: first + i, gseq: 1000 + first + i, ts: "2026-10-08T14:38:07Z", run_id: "r1",
                 event: "attempt_upsert", story: "s1", card: "c1", phase: "explore", attempt: 1,
                 payload: { status: "ok", duration: 1.5 } })
    }
    return out
  }

  function seqs(rows) { return rows.map(function(r) { return r.seq }).join(",") }

  // r1 selected and its reply applied: events 8..10 of 10 (last_seq 10), so
  // three rows, eventsDropped 7, eventsCursor 10.
  function heldStore() {
    var store = make(); if (!store) return null
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    return store
  }

  // 4
  function test_a_good_reply_holds_one_row_per_upsert_event() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var list = F.load("watch-events.json").data.events
    reply(store.eventsRunner.current, eventsReply(list, 60, 475), 0)
    var want = list.filter(function(e) { return /_upsert$/.test(e.event) })
                   .map(function(e) { return e.seq }).join(",")
    compare(seqs(store.events), want, "only the *_upsert events, ascending seq")
    compare(store.events.length, 59)
    compare(JSON.stringify(store.events[0]),
            JSON.stringify(RunEvents.eventRow(list[1], {}, -new Date().getTimezoneOffset())),
            "a row is RunEvents.eventRow at the local offset")
    compare(store.eventsCursor, 60, "last_seq")
    compare(store.eventsDropped, 415, "475 - 60: the events the tail left out")
    compare(store.eventsStatus, "ok")
    compare(store.eventsError, "")
    compare(store.eventsRunner.busy, false)
  }

  // 6
  function test_one_reply_over_the_cap_keeps_the_newest_500() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 600), 600, 1000), 0)
    compare(store.events.length, 500)
    compare(store.events[0].seq, 101, "the lowest seqs were dropped")
    compare(store.events[499].seq, 600)
    compare(store.eventsDropped, 500, "1000 - 600 + 100")
    compare(store.eventsCursor, 600)
  }

  // 7
  function test_a_failure_keeps_the_rows() {
    var store = heldStore(); if (!store) return
    var held = JSON.stringify(store.events)
    compare(seqs(store.events), "8,9,10")
    store.refreshEvents()
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r1|--tail|200")
    compare(store.eventsStatus, "loading")
    compare(JSON.stringify(store.events), held, "the rows stay while refreshing")
    reply(store.eventsRunner.current,
          JSON.stringify({ ok: false, error: { type: "UnknownRunError", message: "no run r1" } }) + "\n", 0)
    compare(store.eventsStatus, "error")
    compare(store.eventsError, "UnknownRunError: no run r1")
    compare(JSON.stringify(store.events), held)
    compare(store.eventsDropped, 7)
    compare(store.eventsCursor, 10)

    store.refreshEvents()
    reply(store.eventsRunner.current, "not json\n", 1)
    compare(store.eventsStatus, "error")
    compare(store.eventsError, "The events snapshot gave no usable result (exit 1).")
    compare(JSON.stringify(store.events), held)

    store.refreshEvents()
    reply(store.eventsRunner.current,
          JSON.stringify({ ok: false, error: { type: "Usage", message: "runs-events.py RUN [--since SEQ] [--tail N]" } }) + "\n", 2)
    compare(store.eventsError, "Usage: runs-events.py RUN [--since SEQ] [--tail N]")
    compare(JSON.stringify(store.events), held)

    store.refreshEvents()
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    compare(store.eventsStatus, "ok")
    compare(store.eventsError, "", "a good reply clears the error")
  }

  // Review Focus 1
  function test_a_refresh_folds_into_the_held_rows() {
    var store = heldStore(); if (!store) return
    store.refreshEvents()
    var fresh = attemptEvents(9, 4)
    fresh[0].payload.status = "failed"
    reply(store.eventsRunner.current, eventsReply(fresh, 12, 12), 0)
    compare(seqs(store.events), "8,9,10,11,12", "one row per seq")
    compare(store.events[1].status, "failed", "the reply's row wins")
    compare(store.eventsDropped, 7, "events 1..7: the held seq 8 fills part of the gap")
    compare(store.eventsCursor, 12)
    compare(store.eventsStatus, "ok")
  }

  // Review Focus 2
  function test_an_ok_reply_without_an_events_list_is_unusable() {
    var store = heldStore(); if (!store) return
    var held = JSON.stringify(store.events)
    // synthetic: lines runs-events.py never prints.
    var bad = [JSON.stringify({ ok: true }), JSON.stringify({ ok: true, events: { seq: 1 } }),
               JSON.stringify({ ok: "yes", events: [] }), "[1, 2]", "", "   \n\n"]
    for (var i = 0; i < bad.length; i++) {
      store.refreshEvents()
      reply(store.eventsRunner.current, bad[i] + "\n", 0)
      compare(store.eventsStatus, "error", bad[i])
      compare(store.eventsError, "The events snapshot gave no usable result (exit 0).", bad[i])
      compare(JSON.stringify(store.events), held, bad[i])
      compare(store.eventsDropped, 7, bad[i])
      compare(store.eventsCursor, 10, bad[i])
    }
    // synthetic: junk and unknown kinds among the events are skipped.
    store.refreshEvents()
    reply(store.eventsRunner.current,
          eventsReply([null, 5, "x", [], { seq: 11, event: "lease_acquired", payload: {} }, attemptEvents(11, 1)[0]], 11, 11), 0)
    compare(store.eventsStatus, "ok")
    compare(seqs(store.events), "8,9,10,11")
    compare(store.eventsCursor, 11)
  }

  // Review Focus 3
  function test_a_bad_total_or_last_seq_falls_back() {
    // synthetic: totals runs-events.py never prints count the events received.
    var totals = [undefined, null, "10", 2, 2.5, -1]
    for (var i = 0; i < totals.length; i++) {
      var store = make(); if (!store) return
      store.selectedRunId = "r1"
      reply(store.eventsRunner.current,
            JSON.stringify({ ok: true, events: attemptEvents(8, 3), last_seq: 10, total: totals[i] }) + "\n", 0)
      compare(store.eventsStatus, "ok", String(totals[i]))
      compare(store.eventsDropped, 0, String(totals[i]))
    }
    // synthetic: a last_seq that is not a non-negative integer is ignored.
    var lasts = [undefined, null, "12", -1, 12.5, 3]
    for (var j = 0; j < lasts.length; j++) {
      var other = make(); if (!other) return
      other.selectedRunId = "r1"
      reply(other.eventsRunner.current,
            JSON.stringify({ ok: true, events: attemptEvents(8, 3), last_seq: lasts[j], total: 3 }) + "\n", 0)
      compare(other.eventsCursor, 10, "the highest held seq: " + String(lasts[j]))
    }
    var ahead = make(); if (!ahead) return
    ahead.selectedRunId = "r1"
    reply(ahead.eventsRunner.current, eventsReply(attemptEvents(8, 3), 12, 3), 0)
    compare(ahead.eventsCursor, 12, "last_seq above the rows")
  }

  // 3
  function test_switching_after_a_good_reply_starts_over() {
    var store = heldStore(); if (!store) return
    store.eventsFilter = "Failures"
    store.refreshEvents()
    var inFlight = store.eventsRunner.current
    store.selectedRunId = "r2"
    compare(JSON.stringify(store.events), "[]")
    compare(store.eventsDropped, 0)
    compare(store.eventsCursor, 0)
    compare(store.eventsError, "")
    compare(store.eventsStatus, "loading")
    compare(argv(store.eventsRunner.current), tc.eventsCmd + "r2|--tail|200")
    compare(inFlight.running, false, "r1's fetch was stopped")
    compare(store.eventsFilter, "Failures")
  }

  // 8
  function test_a_reply_for_a_run_no_longer_selected_is_dropped() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var p1 = store.eventsRunner.current
    store.selectedRunId = "r2"
    var p2 = store.eventsRunner.current
    reply(p1, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(store.eventsStatus, "loading", "r1's reply changes nothing")
    compare(store.events.length, 0)
    compare(store.eventsCursor, 0)
    compare(store.eventsDropped, 0)
    compare(store.eventsRunner.busy, true, "r2's fetch is still in flight")
    // The run-id check on its own, past the runner's latest-wins.
    store.applyEvents(eventsReply(attemptEvents(1, 3), 3, 3), 0, "r1")
    compare(store.eventsStatus, "loading")
    compare(store.events.length, 0)
    reply(p2, eventsReply(attemptEvents(5, 2), 6, 6), 0)
    compare(seqs(store.events), "5,6", "r2's reply lands")
    compare(store.eventsStatus, "ok")
  }

  // 9 (the late reply) and Review Focus 4
  function test_a_reply_after_leaving_or_reselecting_is_dropped() {
    var store = make(); if (!store) return
    store.selectedRunId = "r1"
    var p1 = store.eventsRunner.current
    store.selectedRunId = ""
    reply(p1, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(store.eventsStatus, "idle", "a late reply after leaving changes nothing")
    compare(store.events.length, 0)
    compare(store.eventsCursor, 0)
    store.selectedRunId = "r1"
    var p2 = store.eventsRunner.current
    verify(p2 !== p1)
    store.selectedRunId = ""
    store.selectedRunId = "r1"
    var p3 = store.eventsRunner.current
    reply(p2, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(store.eventsStatus, "loading", "the same run's superseded fetch changes nothing")
    compare(store.events.length, 0)
    reply(p3, eventsReply(attemptEvents(1, 3), 3, 3), 0)
    compare(seqs(store.events), "1,2,3")
    compare(store.eventsStatus, "ok")
  }

  // 10
  function test_a_project_switch_leaves_the_events_alone() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    store.project = tc.rootA
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(8, 3), 10, 10), 0)
    var held = JSON.stringify(store.events)
    var seq = store.eventsRunner.seq
    store.project = tc.rootB
    store.projectRoots = registry([tc.rootB])
    compare(JSON.stringify(store.events), held)
    compare(store.eventsDropped, 7)
    compare(store.eventsCursor, 10)
    compare(store.eventsStatus, "ok")
    compare(store.eventsError, "")
    compare(store.eventsRunner.seq, seq, "nothing is launched")

    store.refreshEvents()
    var proc = store.eventsRunner.current
    store.project = tc.rootA
    store.projectRoots = registry([tc.rootA, tc.rootB])
    compare(proc.running, true, "the fetch in flight is not stopped")
    verify(store.eventsRunner.current === proc)
    reply(proc, eventsReply(attemptEvents(11, 1), 11, 11), 0)
    compare(seqs(store.events), "8,9,10,11", "its reply lands")
    compare(store.eventsStatus, "ok")
  }

  // 11
  function test_an_events_reply_touches_nothing_else() {
    var store = opened(); if (!store) return
    var before = JSON.stringify({ amStatus: store.amStatus, lastError: store.lastError, runs: store.runs.length,
                                  selectedAttempt: store.selectedAttempt, logsText: store.logsText,
                                  logsLoading: store.logsLoading, logsError: store.logsError,
                                  logsStatus: store.logsStatus, logsSeq: store.logsRunner.seq })
    reply(store.eventsRunner.current,
          JSON.stringify({ ok: false, error: { type: "AmMissing", message: "am is not on PATH." } }) + "\n", 0)
    compare(store.eventsError, "AmMissing: am is not on PATH.")
    var after = JSON.stringify({ amStatus: store.amStatus, lastError: store.lastError, runs: store.runs.length,
                                 selectedAttempt: store.selectedAttempt, logsText: store.logsText,
                                 logsLoading: store.logsLoading, logsError: store.logsError,
                                 logsStatus: store.logsStatus, logsSeq: store.logsRunner.seq })
    compare(after, before, "an error reply")
    store.refreshEvents()
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 2), 2, 2), 0)
    compare(store.eventsStatus, "ok")
    after = JSON.stringify({ amStatus: store.amStatus, lastError: store.lastError, runs: store.runs.length,
                             selectedAttempt: store.selectedAttempt, logsText: store.logsText,
                             logsLoading: store.logsLoading, logsError: store.logsError,
                             logsStatus: store.logsStatus, logsSeq: store.logsRunner.seq })
    compare(after, before, "a good reply")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_a_good_reply_holds_one_row_per_upsert_event StoresRunStore::test_one_reply_over_the_cap_keeps_the_newest_500 StoresRunStore::test_a_failure_keeps_the_rows StoresRunStore::test_a_refresh_folds_into_the_held_rows StoresRunStore::test_an_ok_reply_without_an_events_list_is_unusable StoresRunStore::test_a_bad_total_or_last_seq_falls_back StoresRunStore::test_switching_after_a_good_reply_starts_over StoresRunStore::test_a_reply_for_a_run_no_longer_selected_is_dropped StoresRunStore::test_a_reply_after_leaving_or_reselecting_is_dropped StoresRunStore::test_a_project_switch_leaves_the_events_alone StoresRunStore::test_an_events_reply_touches_nothing_else
```
Expected: FAIL — no reply is applied yet (e.g. `test_a_good_reply_holds_one_row_per_upsert_event` fails on `seqs(store.events)` being `""`; `test_a_reply_for_a_run_no_longer_selected_is_dropped` fails with `TypeError: Property 'applyEvents' of object ... is not a function`). `test_switching_after_a_good_reply_starts_over` may already pass (it checks the Task 1 reset); that is expected.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) Replace the import block

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs
```

with

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs
import "../domain/runEvents.js" as RunEvents
```

(b) Directly after the `fetchEvents()` function added in Task 1, add:

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
    store.eventsStatus = "error"
    if (envelope !== null && envelope.ok === false) store.eventsError = Runs.errorText(envelope)
    else store.eventsError = "The events snapshot gave no usable result (exit " + exitCode + ")."
  }

  // A good reply. Its events become RunEvents.eventRow rows at the local UTC
  // offset (null rows skipped) folded into the held rows, at most 500.
  // eventsDropped: (total - received) less the held rows below the reply's
  // lowest seq, at least 0, plus the rows the cap removed; total is the
  // reply's when an integer >= received, else received. eventsCursor: the
  // highest of itself, a non-negative integer last_seq and the held rows' seqs.
  function foldReply(envelope) {
    var list = envelope.events
    var titles = store.titles
    var offset = -new Date().getTimezoneOffset()
    var fresh = []
    var lowest = null
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (e !== null && typeof e === "object" && typeof e.seq === "number" && isFinite(e.seq)
          && (lowest === null || e.seq < lowest)) lowest = e.seq
      var row = RunEvents.eventRow(e, titles, offset)
      if (row !== null) fresh.push(row)
    }
    var held = store.events
    var priorBelow = 0
    for (var h = 0; h < held.length; h++) {
      if (lowest !== null && held[h].seq < lowest) priorBelow += 1
    }
    var fold = RunEvents.foldEvents(held, fresh, 500)
    var received = list.length
    var total = Number.isInteger(envelope.total) && envelope.total >= received ? envelope.total : received
    var cursor = store.eventsCursor
    if (store.isSeq(envelope.last_seq) && envelope.last_seq > cursor) cursor = envelope.last_seq
    var rows = fold.rows
    if (rows.length > 0 && rows[rows.length - 1].seq > cursor) cursor = rows[rows.length - 1].seq
    store.events = rows
    store.eventsDropped = Math.max(0, total - received - priorBelow) + fold.dropped
    store.eventsCursor = cursor
    store.eventsStatus = "ok"
    store.eventsError = ""
  }
```

(c) Replace the `eventsRunner` block added in Task 1

```qml
  // The selected run's events helper. Guard: the run id a fetch was launched
  // for, never the open project. A newer fetch wins over an older one.
  HelperRunner {
    id: eventsRunner
    script: store.backendDir + "runs/runs-events.py"
  }
```

with

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

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: the eleven tests PASS, no `TypeError`/`ReferenceError` lines.

Then the whole file:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"
```
Expected: `Totals: N passed, 0 failed, ...` only.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): fold the selected run's events reply into capped rows; failures keep them"
```

---

### Task 3: Titles — the open project's map completed by the run's tree

**Files:**
- Modify: `core/stores/RunStore.qml` (the events section: a new `eventTitles()` after `fetchEvents()`; one line in `foldReply`)
- Test: `tests/core/stores/tst_run_store.qml` (the events section)

**Interfaces:**
- Consumes: Task 2's `foldReply(envelope)`, test helpers `eventsReply`, `attemptEvents`; existing `store.runById(id)` (normalized run or null; its `tree.stories[]` keep am's `card_id` and `title`), `store.hasKey(map, key)`; test helper `opened()`, `openCard`.
- Produces: `function eventTitles()` on `RunStore` — a fresh `{cardId: title}` object.

- [ ] **Step 1: Write the failing tests**

Append to the events section of `tests/core/stores/tst_run_store.qml` (still before the file's final `}`):

```qml
  // 5
  function test_titles_come_from_the_project_then_the_run_tree_then_the_short_id() {
    var store = opened(); if (!store) return
    var domain = "9f0f68fc-f231-4ef2-b646-00a7af925ea2"   // tree title "Dispatch domain"
    var backend = "7a7effb4-6ec5-4596-bcf1-be24546d4ac1"  // tree title "Dispatch backend"
    var stranger = "11111111-2222-3333-4444-5555deadbeef" // in neither map
    var t = {}
    t[tc.openCard] = "Open subtask"
    t[backend] = "Board story"
    store.titles = t
    var events = [
      { seq: 1, event: "story_upsert", story: domain, payload: { status: "pending" } },
      { seq: 2, event: "story_upsert", story: backend, payload: { status: "started" } },
      { seq: 3, event: "subtask_upsert", story: backend, card: tc.openCard, payload: { status: "started" } },
      { seq: 4, event: "phase_upsert", story: backend, card: stranger, phase: "explore",
        payload: { name: "explore", status: "started" } }
    ]
    reply(store.eventsRunner.current, eventsReply(events, 4, 4), 0)
    compare(store.events.map(function(r) { return r.label }).join("|"),
            "Dispatch domain|Board story|Open subtask|…deadbeef explore")
    compare(JSON.stringify(store.titles), JSON.stringify(t), "titles is never modified")
    store.titles = {}
    compare(store.events[0].label, "Dispatch domain", "held rows are not relabelled")
    compare(store.events[1].label, "Board story")
  }

  // Review Focus 5
  function test_titles_that_are_not_text_fall_back_to_the_short_id() {
    var store = make(); if (!store) return
    // synthetic: titles App never hands over.
    store.titles = null
    store.selectedRunId = "r1"
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 1), 1, 1), 0)
    compare(store.eventsStatus, "ok")
    compare(store.events[0].label, "…c1 explore.1")
    store.titles = { c1: 7 }
    store.refreshEvents()
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 1), 1, 1), 0)
    compare(store.events[0].label, "…c1 explore.1")
    store.titles = { c1: "" }
    store.refreshEvents()
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 1), 1, 1), 0)
    compare(store.events[0].label, "…c1 explore.1")
    store.titles = { c1: "Card one" }
    store.refreshEvents()
    reply(store.eventsRunner.current, eventsReply(attemptEvents(1, 1), 1, 1), 0)
    compare(store.events.length, 1)
    compare(store.events[0].label, "Card one explore.1", "the reply's row replaces the held one")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_titles_come_from_the_project_then_the_run_tree_then_the_short_id StoresRunStore::test_titles_that_are_not_text_fall_back_to_the_short_id
```
Expected: `test_titles_come_from_the_project_then_the_run_tree_then_the_short_id` FAILS — the first label is the short id `…af925ea2` instead of `Dispatch domain`, because the tree is not read yet. `test_titles_that_are_not_text_fall_back_to_the_short_id` may already pass (`eventRow` tolerates a null map); that is expected — it pins that `eventTitles()` keeps tolerating it.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) Directly after the `fetchEvents()` function (before `applyEvents`), add:

```qml

  // The labels for an events reply, a fresh object: every own key of
  // `titles` holding a non-empty string, then, for each story of the
  // selected run's tree with a string card_id and a non-empty string title,
  // that title where `titles` has none. `titles` is never modified.
  function eventTitles() {
    var out = {}
    var own = store.titles
    if (own !== null && typeof own === "object" && !Array.isArray(own)) {
      for (var key in own) {
        if (store.hasKey(own, key) && typeof own[key] === "string" && own[key] !== "") out[key] = own[key]
      }
    }
    var run = store.runById(store.selectedRunId)
    var tree = run !== null && typeof run === "object" && run.tree !== null && typeof run.tree === "object" ? run.tree : {}
    var stories = Array.isArray(tree.stories) ? tree.stories : []
    for (var i = 0; i < stories.length; i++) {
      var s = stories[i]
      if (s === null || typeof s !== "object") continue
      if (typeof s.card_id !== "string" || typeof s.title !== "string" || s.title === "") continue
      if (!store.hasKey(out, s.card_id)) out[s.card_id] = s.title
    }
    return out
  }
```

(b) In `foldReply`, replace the line

```qml
    var titles = store.titles
```

with

```qml
    var titles = store.eventTitles()
```

and in `foldReply`'s comment replace

```qml
  // A good reply. Its events become RunEvents.eventRow rows at the local UTC
  // offset (null rows skipped) folded into the held rows, at most 500.
```

with

```qml
  // A good reply. Its events become RunEvents.eventRow rows, labelled from
  // eventTitles() at the local UTC offset (null rows skipped), folded into
  // the held rows, at most 500.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: both PASS.

Then the whole file:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"
```
Expected: `Totals: N passed, 0 failed, ...` only.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): label event rows from the open project's titles, completed by the run's tree"
```

---

### Task 4: App hands the board's card titles to the run store

**Files:**
- Modify: `core/stores/App.qml:107-113` (the run store's comment and bindings)
- Test: `tests/core/stores/tst_app_runs.qml` (append before the final `}`)

**Interfaces:**
- Consumes: `RunStore.titles` (Task 1); `BoardStore.cardMap` (`core/stores/BoardStore.qml:24`, `{id: card}`, replaced on each board fetch).
- Produces: `app.runs.titles` bound to `{id: card.title}` for each `app.board.cardMap` card whose `title` is a string.

- [ ] **Step 1: Write the failing test**

Append to `tests/core/stores/tst_app_runs.qml`, directly before the file's final `}`:

```qml

  // ---- the event timeline's titles (run events 3.1)

  // 13
  function test_titles_follow_the_board() {
    var app = makeBare(); if (!app) return
    compare(JSON.stringify(app.runs.titles), "{}")
    app.board.cardMap = { c1: { title: "One" }, c2: { title: 7 } }
    compare(JSON.stringify(app.runs.titles), JSON.stringify({ c1: "One" }), "only string titles")
    app.board.cardMap = { c3: { title: "Three" } }
    compare(JSON.stringify(app.runs.titles), JSON.stringify({ c3: "Three" }), "a new board replaces the map")
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_app_runs.qml StoresAppRuns::test_titles_follow_the_board
```
Expected: FAIL — `only string titles`: actual `{}`, expected `{"c1":"One"}`.

- [ ] **Step 3: Write the implementation**

In `core/stores/App.qml` replace

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

with

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object), the open project's card id -> title map
  // (titles, from the board's cardMap) and the panel-open flag that starts
  // and stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    titles: {
      var map = app.board.cardMap || {}
      var out = {}
      var ids = Object.keys(map)
      for (var i = 0; i < ids.length; i++) {
        var card = map[ids[i]]
        if (card && typeof card.title === "string") out[ids[i]] = card.title
      }
      return out
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

Then the full gate:
```bash
timeout 600 bash tests/run.sh
```
Expected: pytest `... passed` (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`), every QML file `Totals: N passed, 0 failed`, no `TypeError`/`ReferenceError` lines, exit status 0 (`echo $?` prints `0`).

- [ ] **Step 5: Commit**

```bash
git add core/stores/App.qml tests/core/stores/tst_app_runs.qml
git commit -m "feat(app): hand the run store the open project's card titles"
```

---

## Spec coverage (self-review)

| spec item | task |
|---|---|
| State table: `titles`, `events`, `eventsDropped`, `eventsCursor`, `eventsStatus`, `eventsError`, `eventsFilter`, `eventsRunner` | Task 1 (test 1) |
| Selection 1: reset, `loading`, exact argv, id verbatim, run not in `runs` still fetched, logs behaviour unchanged | Task 1 (test 2; the existing logs tests stay green) |
| Selection 2: switching supersedes, stops the old process | Task 1 (reset), Task 2 (test 3, test 8) |
| Selection 3: leaving resets, idle, cancelled, late reply dropped, nothing launched | Task 1 (test 9 reset), Task 2 (late reply) |
| Selection 4: same id does nothing | Task 1 (test 12) |
| Selection 5: `eventsFilter` untouched | Task 1, Task 2 (test 3) |
| Selection 6: `refreshEvents()` | Task 1, Task 2 (test 7, Review Focus 1) |
| Stale reply: guard = run id, `launchedGuard === selectedRunId` | Task 2 (test 8, Review Focus 4) |
| Good reply: eventRow at local offset, null skipped, fold cap 500, dropped formula with `priorBelow`, cursor, ok | Task 2 (tests 4, 6, Review Focus 1-3) |
| Failure envelope: `Runs.errorText`, rows kept | Task 2 (test 7, test 11) |
| Unusable: no envelope / `ok` not boolean / no events array | Task 2 (test 7, Review Focus 2) |
| A reply touches nothing else | Task 2 (test 11) |
| Titles: `titles` non-empty strings, tree stories only where the map has none, short-id fallback, `titles` unmodified, no relabel | Task 3 (test 5, Review Focus 5) |
| Project switch and panel: nothing reset, launched or cancelled | Task 2 (test 10) |
| App: `titles` from `app.board.cardMap`, re-evaluates on replace, comment names `titles` | Task 4 (test 13) |
| Error paths table (AmMissing, UnknownRunError, CorruptJournal/StoreBusyError via `Runs.errorText`, Usage, not JSON, superseded, after leaving, > 500) | Task 2 |
| Unchanged gates: `test_layers.py`, `test_icon_glyphs.py`, `tst_run_events.qml` | Task 4 Step 4 (`bash tests/run.sh`) |
<!-- task-pipeline: validated -->
