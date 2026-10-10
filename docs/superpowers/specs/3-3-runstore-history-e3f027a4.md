# 3.3 RunStore: history rows in the filtered list (card e3f027a4)

Parent story: b477c51f "History and titles stores". Milestone design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**design** with line numbers). Siblings: 3.1 RunTitlesStore (done, `app.runTitles`),
3.2 RunHistoryStore (done, `app.runHistory`), 3.4 RunAlertsStore titled alerts (blocked
on this card, out of scope).

## Inherited constraints

- Chips are Needs attention / Live / Parked / **Finished** / All; `filterRuns(runs,
  "finished")` keeps done, escalated, cancelled, canceled (design l.139-140).
- The finished-state row (All finished / Done / Escalated / Cancelled, `finishedState`)
  applies **under Finished** only (design l.141-142).
- The age row (Today / 7 days / All time, `finishedAge`, default All time) applies
  **under Finished and All** (design l.143-146). Age is `started_at`; Today is since local
  midnight, 7 days is the last 7×24 h.
- Age and finished-state filters never hide a run that is not finished (design l.147).
- History runs reach `RunStore.filteredRuns` through App as `historyRuns`; the display
  order puts a project's history after its snapshot runs, newest first, grouped by project
  like the snapshot (design l.168-170).
- History is never compared by `RunAlertsStore`; a resumed history run shows up in the
  snapshot, which wins (design l.170-172). The snapshot `runs` stays snapshot-only.
- `searchRuns(runs, q, titlesByRoot)` matches the title too (design l.107-108).
- No persisted history settings (design l.57).
- Run detail of a history run is the same screen (design l.192).
- Stores import only QtQml, Quickshell, Quickshell.Io and `../domain`; App wires them by
  explicit properties (story b477c51f; `docs/architecture.md` layering).
- Docstrings and comments state the contract only, no narrative (card).
- `docs/architecture.md`'s `RunStore.qml` bullet names every input App binds on it and every
  signal App routes (`tests/architecture/test_run_store_docs.py`).

### Divergence from the design, already settled by 3.2

The design (l.155-157) describes one global `historyRuns` list on RunHistoryStore. 3.2
shipped a per-root `historyByProject` (`{root: {runs, more, loading, error}}`,
`core/stores/RunHistoryStore.qml:40`) instead. This card does not change RunHistoryStore:
App flattens `historyByProject` into the flat `historyRuns` input RunStore takes.

## Domain already in place (no change)

`core/domain/runs.js`: `runFilterCounts` (l.686, counts `finished`), `filterRuns(…,
"finished")` (l.700), `withinAge` (l.725), `filterFinished(runs, finishedState, finishedAge,
nowMs, utcOffsetMinutes)` (l.742), `searchRuns(runs, q, titlesByRoot)` (l.803),
`groupByProject` (l.425, keeps input order within a group), `displayOrder` (l.459),
`runById`. This card adds no domain function.

## Observable behavior

### New RunStore inputs and state (`core/stores/RunStore.qml`)

| member | kind | default | meaning |
|---|---|---|---|
| `historyRuns` | `property var` | `[]` | older runs, each built like a snapshot run (`Runs.withProject(Runs.normalizeRun(..), root, name)`); App binds it |
| `titlesByRoot` | `property var` | `({})` | `{root: {id: title}}`; App binds it to `app.runTitles.titlesByRoot` |
| `finishedState` | `property string` | `""` | `"done"` \| `"escalated"` \| `"cancelled"`; `""` is every finished state |
| `finishedAge` | `property string` | `"all"` | `"today"` \| `"week"` \| `"all"` |
| `nowMs` | `property real` | `0` | the age filter's clock; `0` means `Date.now()` when `filteredRuns` is evaluated (BoardStore's `nowMs` convention, `core/stores/BoardStore.qml:21,74`) |
| `listedRuns` | `readonly property var` | — | `runs`, then every `historyRuns` entry that is a plain object whose `id` no `runs` entry has and no earlier `historyRuns` entry has, in `historyRuns` order |
| `runFilterCounts` | `readonly property var` | — | `Runs.runFilterCounts(Runs.filterByProject(listedRuns, projectFilter))`: `{attention, live, parked, finished, all}`; the chip, the finished rows, the age row and the search never narrow it |

`runFilter`'s comment widens to `"" | "attention" | "live" | "parked" | "finished"`.

`runs`, `runsByProject`, `appliedSeq`, `knownRunIds`, `hasRunningRun`, `isFilterable`,
`keepProjectFilter`, the watch, `snapshotReplied` and every other existing member stay
snapshot-only: setting `historyRuns` changes none of them and emits no `snapshotReplied`,
`runsNudged` or `projectFilterToggled`.

### `groups` and `filteredRuns`

`groups` is, in this order:

1. `listedRuns`
2. `Runs.filterRuns(…, runFilter)`
3. `Runs.filterFinished(…, S, A, now, -new Date(now).getTimezoneOffset())`, where
   `now` is `nowMs` when it is above 0, else `Date.now()`;
   `S` is `finishedState` when `runFilter === "finished"`, else `""`;
   `A` is `finishedAge` when `runFilter` is `"finished"` or `""`, else `"all"`
4. `Runs.searchRuns(…, searchQuery, titlesByRoot)`
5. `Runs.filterByProject(…, projectFilter)`
6. `Runs.groupByProject(…)`

`filteredRuns` stays `Runs.displayOrder(groups)`: the one list the screen draws and the
navigator's cursor (`app.nav.cursorIndex`) indexes. Consequences a test can observe:

- Within a project, every snapshot run precedes every history run; history keeps its
  `historyRuns` order (RunHistoryStore keeps it newest first).
- A history run whose id the snapshot also lists appears once, as the snapshot's object.
- Group order and each group's `counts` are `groupByProject`'s over the kept rows, history
  rows included.
- Under Attention, Live and Parked the finished-state and age values narrow nothing; under
  All only the age narrows, and only finished runs; under Finished both narrow.
- A running, dead or parked run (snapshot or history) is never hidden by state or age.

### Toggles

- `toggleFinishedState(id)`: `id` `"done"`, `"escalated"` or `"cancelled"` that is not the
  current `finishedState` sets it; the current value again, `"all"`, `""` or any other value
  sets `""`. Emits `runFilterToggled()` once per call, changed or not.
- `toggleFinishedAge(id)`: `id` `"today"` or `"week"` that is not the current `finishedAge`
  sets it; the current value again, `"all"` or any other value sets `"all"`. Emits
  `runFilterToggled()` once per call.
- Neither toggle changes `runFilter`; `toggleRunFilter` changes neither value.
- A project switch keeps both values.

### Panel close (`stopLive`)

The panel closing (`active` true → false) sets `finishedState` to `""` and `finishedAge`
to `"all"`, alongside the existing `projectFilter = ""`, with no `runFilterToggled`. The
chip (`runFilter`) and `searchQuery` stay, as today. `historyRuns` is App's input; RunStore
never clears it (RunHistoryStore drops its pages on close).

### `runById(id)`

Returns the snapshot run with that id, else the `listedRuns` history run with that id,
else null (snapshot wins). So `Navigator.openRun`, `Shortcuts` run mode and the logs fetch
(`selectedRunId`) work for a selected history row. `runById` gains no other caller.

### App wiring (`core/stores/App.qml`)

On `RunStore runs`:
- `historyRuns`: every `app.runHistory.historyByProject[root].runs` concatenated, in
  `Object.keys` order, `[]` when the map is empty (an entry whose `runs` is not an array
  contributes nothing).
- `titlesByRoot: app.runTitles.titlesByRoot`.

On `RunHistoryStore runHistory`:
- `finishedState: app.runs.finishedState`, `finishedAge: app.runs.finishedAge`.

`runFilterToggled` keeps its existing route (cursor home), so the two new toggles put the
cursor home. `RunTitlesStore.runs`, `RunControlStore.runs`, `RunDispatchStore` and
`RunAlertsStore` keep the snapshot `app.runs.runs`.

### Docs (`docs/architecture.md`)

- `RunStore.qml` bullet (l.83): names `historyRuns` (App binds it from
  `app.runHistory.historyByProject`) and `titlesByRoot` (`app.runTitles.titlesByRoot`);
  the `finished` chip, `finishedState`/`finishedAge` with their toggles, their reset on
  close, `listedRuns`, `runFilterCounts`, the pipeline above, the display order (a
  project's history after its snapshot runs) and `runById`'s history fallback.
- `RunHistoryStore.qml` bullet (l.95): `finishedState` and `finishedAge` are bound to
  `app.runs.finishedState`/`finishedAge` (drop "are not bound yet").
- RunStore's header comment (`RunStore.qml:7-36`) gains the same contract in a sentence
  or two.

## Error paths and odd inputs

| input | behavior |
|---|---|
| `historyRuns` not an array, or holding `null`/non-objects | ignored entries; `listedRuns` is `runs` plus the plain-object entries |
| history run with the id of a snapshot run | listed once, the snapshot object |
| the same id twice in `historyRuns` | listed once, the first |
| `titlesByRoot` `{}` or not an object | search matches ids, phase and state as before (fallback titles from `runTitle`) |
| `finishedState`/`finishedAge` set directly to an unknown string | `filterFinished` treats it as every state / all time |
| history run without `started_at` | hidden under Today/7 days when finished (`withinAge`), shown under All time |
| `nowMs` 0 | the current time at evaluation; the list does not re-evaluate as time passes alone |

## Tests

All in `tests/core/stores/tst_run_store.qml` (QtTest, TestCase `StoresRunStore`) unless
named otherwise. Tier: **store tests** (QML, qmltestrunner) because each asserts a
RunStore binding or function over its inputs, with no UI; the domain functions are already
covered in `tests/core/domain/tst_runs.qml`. History runs are built in the test the way
RunHistoryStore builds them (`Runs.withProject(Runs.normalizeRun({row, status}), root,
name)`) and assigned to `store.historyRuns`; `nowMs` is fixed.

1. **Display order with history** — two projects, snapshot runs in each, history for both:
   `filteredRuns` is each group's snapshot runs then its history runs in `historyRuns`
   order; groups ordered as `groupByProject` orders them (a history escalated run counts in
   its group's `attention`); `displayOrder(groups)` equals `filteredRuns`.
2. **Snapshot wins** — a history run sharing a snapshot id appears once and is the
   snapshot object; a duplicated history id appears once; non-object entries are skipped;
   `runs`, `appliedSeq`, `hasRunningRun` unchanged by `historyRuns`.
3. **Each chip over snapshot + history** — `""`, attention, live, parked, finished each
   list the expected ids from both sources; `runFilterCounts` over snapshot + history has
   the right `finished` and `all`; it follows `projectFilter`, not the search, chip or
   finished rows.
4. **Finished state row** — under Finished, each of done / escalated / cancelled (both
   spellings) narrows; under All and Attention it narrows nothing.
5. **Age row** — fixed `nowMs`; runs just before and after local midnight and around
   now − 7 days: Today and 7 days narrow finished runs under Finished and All, not under
   Attention/Parked; a parked or running history run is kept under Today.
6. **Toggles** — `toggleFinishedState`/`toggleFinishedAge` set, re-toggle back to the
   default, `"all"` and unknown ids give the default; each call emits `runFilterToggled`
   once; `runFilter` untouched; a project switch keeps both.
7. **Reset on close** — after `active` true → false, `finishedState === ""`,
   `finishedAge === "all"`, `projectFilter === ""`, no `runFilterToggled` emitted; `runFilter`
   and `searchQuery` kept.
8. **Search by title** — with `titlesByRoot` mapping a history run's milestone id to a
   title, a query on part of that title lists it; without the map it does not.
9. **Cursor order** — `filteredRuns[i]` walks snapshot then history per group;
   `runById(id)` of a history row returns that object; a snapshot id returns the snapshot
   object.

`tests/core/stores/tst_app_runs.qml` (store tier: App composition):

10. **App wiring** — update `test_app_composes_run_history_wired_to_the_run_store`:
    `app.runHistory.finishedState`/`finishedAge` follow `app.runs.toggleFinishedState` /
    `toggleFinishedAge`; `app.runs.historyRuns` is the flattened
    `app.runHistory.historyByProject` (set a page through the history store's runner reply
    or its stubbed process); `app.runs.titlesByRoot` equals `app.runTitles.titlesByRoot`;
    a finished toggle puts `app.nav.cursorIndex` at 0.

`tests/architecture` (pytest tier): `test_run_store_docs.py` must pass with the new App
inputs named in the doc bullet; no new test file.

Verification: `bash tests/run.sh` green.

## Out of scope

- Any UI: the Finished chip, the state and age rows, Show older, titled rows, switching
  `RunsScreen.counts` or Panel's `runCounts` to `runFilterCounts`, `RunDetailScreen`'s own
  `runById` over `app.runs.runs` (cards 4.1, 4.2, 4.3).
- RunHistoryStore behavior (3.2), including its `--since` under Attention/Parked.
- RunTitlesStore fetching titles for history-only ids (3.1); `RunTitlesStore.runs` stays
  the snapshot.
- Titled alerts (3.4); README and user docs (4.4).
- Any `core/domain/runs.js` change.
