# 3.3 RunStore: history rows in the filtered list — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `RunStore`'s filtered list (`groups` / `filteredRuns`) carry App's history runs after each project's snapshot runs, add the Finished chip's state and age rows with their toggles and reset on close, title search, `runFilterCounts` and a history fallback in `runById`; wire `historyRuns`, `titlesByRoot`, `finishedState` and `finishedAge` in `App.qml` and document it.

**Architecture:** `RunStore` gains plain inputs (`historyRuns`, `titlesByRoot`, `finishedState`, `finishedAge`, `nowMs`), one derived list `listedRuns` (`runs` then the new history ids, so the snapshot wins), and a `groups` binding that pipes `listedRuns` through the existing pure domain filters (`filterRuns` → `filterFinished` → `searchRuns` → `filterByProject` → `groupByProject`). Every snapshot member (`runs`, `appliedSeq`, the watch, …) stays untouched. App flattens `app.runHistory.historyByProject` into `historyRuns`, binds `titlesByRoot` from `app.runTitles`, and binds the history store's `finishedState`/`finishedAge` back to `app.runs`.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), the pure JS library `core/domain/runs.js` (no change), QtTest (`qmltestrunner`) with stubbed `Process` objects, pytest for the architecture/doc tests.

**Spec:** `docs/superpowers/specs/3-3-runstore-history-e3f027a4.md` (reproduced verbatim in the "Spec" section below; parent design `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`).

## Global Constraints

- Stores import only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`; App wires them by explicit properties (`tests/architecture/test_layers.py`). `RunStore.qml`'s imports do not change.
- No `core/domain/runs.js` change; no `RunHistoryStore.qml` change; no UI change.
- `historyRuns` default `[]`, `titlesByRoot` default `({})`, `finishedState` default `""`, `finishedAge` default `"all"`, `nowMs` default `0`.
- `runs`, `runsByProject`, `appliedSeq`, `knownRunIds`, `hasRunningRun`, `isFilterable`, `keepProjectFilter`, the watch, `snapshotReplied` and every other existing member stay snapshot-only; setting `historyRuns` emits no `snapshotReplied`, `runsNudged` or `projectFilterToggled`.
- `RunTitlesStore.runs`, `RunControlStore.runs`, `RunDispatchStore` and `RunAlertsStore` keep the snapshot `app.runs.runs`.
- No persisted history settings.
- Docstrings and comments state the contract only, no narrative.
- `docs/architecture.md`'s `RunStore.qml` bullet names every input App binds on it and every signal App routes (`tests/architecture/test_run_store_docs.py`).
- Verification: `bash tests/run.sh` green; no `TypeError`, `ReferenceError`, `Unable to assign`, `non-existent` or `is not a function` line in QML output.

## Review Focus

1. A selected history row's attempt logs: `fetchLogs` reaches the run through `runById`, so selecting a history run and an attempt must launch `runs-logs.py` with that run's own project root. Test: Task 1 `test_a_selected_history_run_fetches_its_logs_from_its_root`.
2. `historyRuns` set to something that is not an array (`null`, a string, a number, one bare object): the list is the snapshot alone, nothing throws. Test: Task 1 `test_a_history_that_is_not_an_array_lists_the_snapshot_alone`.
3. `nowMs` left at `0` (production: App never sets it): the age row measures against the current time, so a run started a moment ago is within 7 days and one started 8 days ago is not. Test: Task 2 `test_now_ms_0_measures_the_age_against_the_current_time`.
4. `titlesByRoot` that is not an object (`"garbage"`): the search still matches by id and by `runTitle`'s fallback title, nothing throws. Test: Task 2 `test_without_a_title_map_the_search_matches_ids_and_fallback_titles`.
5. `finishedState`/`finishedAge` assigned an unknown string directly (not through a toggle): under Finished every finished run is listed. Test: Task 2 `test_an_unknown_finished_state_or_age_narrows_nothing`.

---

## Spec

The spec this plan implements, verbatim from `docs/superpowers/specs/3-3-runstore-history-e3f027a4.md`:

### 3.3 RunStore: history rows in the filtered list (card e3f027a4)

Parent story: b477c51f "History and titles stores". Milestone design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**design** with line numbers). Siblings: 3.1 RunTitlesStore (done, `app.runTitles`),
3.2 RunHistoryStore (done, `app.runHistory`), 3.4 RunAlertsStore titled alerts (blocked
on this card, out of scope).

#### Inherited constraints

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

##### Divergence from the design, already settled by 3.2

The design (l.155-157) describes one global `historyRuns` list on RunHistoryStore. 3.2
shipped a per-root `historyByProject` (`{root: {runs, more, loading, error}}`,
`core/stores/RunHistoryStore.qml:40`) instead. This card does not change RunHistoryStore:
App flattens `historyByProject` into the flat `historyRuns` input RunStore takes.

#### Domain already in place (no change)

`core/domain/runs.js`: `runFilterCounts` (l.686, counts `finished`), `filterRuns(…,
"finished")` (l.700), `withinAge` (l.725), `filterFinished(runs, finishedState, finishedAge,
nowMs, utcOffsetMinutes)` (l.742), `searchRuns(runs, q, titlesByRoot)` (l.803),
`groupByProject` (l.425, keeps input order within a group), `displayOrder` (l.459),
`runById`. This card adds no domain function.

#### Observable behavior

##### New RunStore inputs and state (`core/stores/RunStore.qml`)

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

##### `groups` and `filteredRuns`

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

##### Toggles

- `toggleFinishedState(id)`: `id` `"done"`, `"escalated"` or `"cancelled"` that is not the
  current `finishedState` sets it; the current value again, `"all"`, `""` or any other value
  sets `""`. Emits `runFilterToggled()` once per call, changed or not.
- `toggleFinishedAge(id)`: `id` `"today"` or `"week"` that is not the current `finishedAge`
  sets it; the current value again, `"all"` or any other value sets `"all"`. Emits
  `runFilterToggled()` once per call.
- Neither toggle changes `runFilter`; `toggleRunFilter` changes neither value.
- A project switch keeps both values.

##### Panel close (`stopLive`)

The panel closing (`active` true → false) sets `finishedState` to `""` and `finishedAge`
to `"all"`, alongside the existing `projectFilter = ""`, with no `runFilterToggled`. The
chip (`runFilter`) and `searchQuery` stay, as today. `historyRuns` is App's input; RunStore
never clears it (RunHistoryStore drops its pages on close).

##### `runById(id)`

Returns the snapshot run with that id, else the `listedRuns` history run with that id,
else null (snapshot wins). So `Navigator.openRun`, `Shortcuts` run mode and the logs fetch
(`selectedRunId`) work for a selected history row. `runById` gains no other caller.

##### App wiring (`core/stores/App.qml`)

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

##### Docs (`docs/architecture.md`)

- `RunStore.qml` bullet (l.83): names `historyRuns` (App binds it from
  `app.runHistory.historyByProject`) and `titlesByRoot` (`app.runTitles.titlesByRoot`);
  the `finished` chip, `finishedState`/`finishedAge` with their toggles, their reset on
  close, `listedRuns`, `runFilterCounts`, the pipeline above, the display order (a
  project's history after its snapshot runs) and `runById`'s history fallback.
- `RunHistoryStore.qml` bullet (l.95): `finishedState` and `finishedAge` are bound to
  `app.runs.finishedState`/`finishedAge` (drop "are not bound yet").
- RunStore's header comment (`RunStore.qml:7-36`) gains the same contract in a sentence
  or two.

#### Error paths and odd inputs

| input | behavior |
|---|---|
| `historyRuns` not an array, or holding `null`/non-objects | ignored entries; `listedRuns` is `runs` plus the plain-object entries |
| history run with the id of a snapshot run | listed once, the snapshot object |
| the same id twice in `historyRuns` | listed once, the first |
| `titlesByRoot` `{}` or not an object | search matches ids, phase and state as before (fallback titles from `runTitle`) |
| `finishedState`/`finishedAge` set directly to an unknown string | `filterFinished` treats it as every state / all time |
| history run without `started_at` | hidden under Today/7 days when finished (`withinAge`), shown under All time |
| `nowMs` 0 | the current time at evaluation; the list does not re-evaluate as time passes alone |

#### Tests

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

#### Out of scope

- Any UI: the Finished chip, the state and age rows, Show older, titled rows, switching
  `RunsScreen.counts` or Panel's `runCounts` to `runFilterCounts`, `RunDetailScreen`'s own
  `runById` over `app.runs.runs` (cards 4.1, 4.2, 4.3).
- RunHistoryStore behavior (3.2), including its `--since` under Attention/Parked.
- RunTitlesStore fetching titles for history-only ids (3.1); `RunTitlesStore.runs` stays
  the snapshot.
- Titled alerts (3.4); README and user docs (4.4).
- Any `core/domain/runs.js` change.

---

## File Structure

Line numbers below are those of the files before this plan; a later task's line numbers shift by what earlier tasks inserted, so locate each edit by the quoted text it replaces.

- Modify `core/stores/RunStore.qml` — header comment, new inputs, `listedRuns`, `runFilterCounts`, the `groups` pipeline, `listed()`, the two toggles, `stopLive`'s reset, `runById`'s fallback (Tasks 1–4).
- Modify `tests/core/stores/tst_run_store.qml` — header comment and a new `// ---- history rows in the filtered list (3.3 history)` section appended at the end of the file (Tasks 1–3).
- Modify `core/stores/App.qml` — the `RunStore runs` block (`historyRuns`, `titlesByRoot`) and the `RunHistoryStore runHistory` block (`finishedState`, `finishedAge`) (Task 4).
- Modify `tests/core/stores/tst_app_runs.qml` — header comment, the updated `test_app_composes_run_history_wired_to_the_run_store` and three new tests (Task 4).
- Modify `docs/architecture.md` — the `RunStore.qml` bullet (line 83) and the `RunHistoryStore.qml` bullet (line 95) (Task 4).

## How to run the tests

- One QML test file: `bash tests/run.sh tst_run_store` (the argument filters QML test paths by substring, so this runs `tst_run_store.qml` only; the script always runs the whole pytest suite first). A QML test fails when the output shows a `FAIL!` line, or any `TypeError` / `ReferenceError` / `Unable to assign` / `non-existent` / `is not a function` line; the script then exits non-zero. Read the `Totals:` line.
- The App test: `bash tests/run.sh tst_app_runs`.
- pytest alone: `python3 -m pytest tests/architecture/test_run_store_docs.py -q`; if `python3` has no pytest, use `uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`.
- Everything: `bash tests/run.sh`.
- Wrap any run you fear may hang in `timeout 600`.

Facts the engineer needs:

- `tests/stubs/Quickshell/Io/Process.qml` stubs `Process`. A test answers a launch by setting `proc.outText` and calling `proc.exited(code)` (the test helper `reply(proc, text, code)` does this).
- `HelperRunner` (`core/stores/HelperRunner.qml`): `run(args)` bumps `seq`, sets `busy` and creates `current` with `command = ["python3", script].concat(args)`; `current` is `null` before the first `run()`.
- Helpers that already exist in `tests/core/stores/tst_run_store.qml` and that the new tests reuse (all are `TestCase` functions, callable unqualified anywhere in the file): `make()`, `makeWithRoots(roots)` (registered, not active, snapshot of every root in flight), `makeWithProject(root)`, `projectsStore(open)` (rootA..rootD, `allReply(projectEntries())` applied; rootB lists `b-esc1`, `b-park1`), `reply(proc, text, code)`, `entry(id, runStatus, live, root)` (started_at `2026-10-01T00:00:00Z`, milestone `m-<id>`, repo_dir `root` else rootA), `allReply(projects)`, `okEntry(root, runs)`, `okReply(entries)`, `rootEntry(root)` (rootA → "alpha", rootB → "beta", else "proj"), `ids(list)` (comma-joined ids), `groupText(store)` (`"name:attention/live/parked"` per group), `argv(proc)` (`command.join("|")`), and `Component { id: spyC; SignalSpy {} }`. Properties: `rootA` `"/home/u/my proj"`, `rootB` `"/home/u/b"`.
- `Runs.runState(run)`: `started` with a live lease → `running`, `started` otherwise → `dead`, `stopped` → `parked`, `cancelled`/`canceled` → `cancelled`, `done`/`escalated` as is.
- `Runs.groupByProject(runs)`: groups by `project.root`, input order kept inside a group; counts `{live, parked, attention}` (attention = escalated or dead); order: groups with attention > 0, then live > 0, then the rest, ties by name lower-cased.
- `Runs.filterRuns(runs, id)`: `attention` (escalated or dead), `live` (running), `parked`, `finished` (done, escalated, cancelled); anything else is every run.
- `Runs.filterFinished(runs, finishedState, finishedAge, nowMs, utcOffsetMinutes)`: keeps every non-finished run; keeps a finished run when its state matches `finishedState` (`done`/`escalated`/`cancelled`; anything else matches all) and `withinAge` holds (`today`: started at or after local midnight; `week`: at or after `nowMs - 7 days`; anything else: true; no `started_at`: false under today/week).
- `Runs.searchRuns(runs, q, titlesByRoot)`: case-insensitive substring over id, `runTitle(run, titlesByRoot[run root])`, current phase and state name. `runTitle` of a milestone run without a mapped title is `"milestone …" + milestone_id.slice(-8)`.
- `Runs.runFilterCounts(runs)` returns `{attention, live, parked, finished, all}` in that key order.
- `Runs.runById(runs, id)`: the first entry with that id, else `null`.

---

### Task 1: `historyRuns` and `listedRuns`: history rows after each project's snapshot runs, snapshot wins, `runById` falls back

**Files:**
- Modify: `core/stores/RunStore.qml:77-82` (the `groups` comment and binding), `:649-652` (`runById`), `:683-686` (`fetchLogs` comment)
- Test: `tests/core/stores/tst_run_store.qml` (append a section before the file's final `}`; header comment lines 1-11)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `RunStore.historyRuns: var` (default `[]`), `RunStore.listedRuns: readonly var`, `RunStore.listed(runs, history): array`, `RunStore.runById(id)` over `listedRuns`. Test helpers `histRun(id, root, status, startedAt, live)`, `historyStore()`, `historyPage()` used by Tasks 2 and 3.

- [ ] **Step 1: Write the failing tests**

Append this section to `tests/core/stores/tst_run_store.qml`, just before the file's last line (the closing `}` of `TestCase`, after `test_closing_and_switching_the_run_store_touch_no_dispatch`):

```qml

  // ---- history rows in the filtered list (3.3 history)

  // Run `id` of `root` as RunHistoryStore builds one: am status `status`,
  // milestone "m-<id>", started at `startedAt`, its lease live when `live`
  // (no lease otherwise), tagged with rootEntry(root)'s name.
  function histRun(id, root, status, startedAt, live) {
    var st = { run: { id: id, milestone_id: "m-" + id, status: status }, rows: [], stories: [], subtasks: [] }
    if (live) st.control = { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: true } }
    var raw = { row: { id: id, repo_dir: root, started_at: startedAt, status: status }, status: st }
    return Runs.withProject(Runs.normalizeRun(raw), root, tc.rootEntry(root).name)
  }

  // rootA ("alpha") and rootB ("beta") registered, no project open, the
  // snapshot answered: A lists a-live1 (running) and a-park1, B lists b-park1.
  function historyStore() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([
      okEntry(tc.rootA, [entry("a-live1", "started", true, tc.rootA), entry("a-park1", "stopped", false, tc.rootA)]),
      okEntry(tc.rootB, [entry("b-park1", "stopped", false, tc.rootB)])]), 0)
    return store
  }

  // History for historyStore(), interleaved by root: A's a-h1 (done), B's
  // b-h1 (escalated), A's a-h2 (parked).
  function historyPage() {
    return [histRun("a-h1", tc.rootA, "done", "2026-09-20T00:00:00Z"),
            histRun("b-h1", tc.rootB, "escalated", "2026-09-19T00:00:00Z"),
            histRun("a-h2", tc.rootA, "stopped", "2026-09-18T00:00:00Z")]
  }

  // H1
  function test_each_projects_history_follows_its_snapshot_runs() {
    var store = historyStore(); if (!store) return
    compare(groupText(store), "alpha:0/1/1,beta:0/0/1", "before any history")
    store.historyRuns = historyPage()
    compare(ids(store.listedRuns), "a-live1,a-park1,b-park1,a-h1,b-h1,a-h2")
    compare(groupText(store), "beta:1/0/1,alpha:0/1/2", "b-h1 counts in beta's attention, a-h2 in alpha's parked")
    compare(ids(store.filteredRuns), "b-park1,b-h1,a-live1,a-park1,a-h1,a-h2",
            "each group: its snapshot runs, then its history in historyRuns order")
    compare(ids(Runs.displayOrder(store.groups)), ids(store.filteredRuns))
    verify(store.filteredRuns[1] === store.historyRuns[1], "the history objects themselves")
  }

  // H2
  function test_the_snapshot_wins_and_odd_history_entries_are_skipped() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a-park1", "stopped", false, tc.rootA)]), 0)
    var seq = store.snapshotRunner.seq
    var applied = JSON.stringify(store.appliedSeq)
    var known = JSON.stringify(store.knownRunIds())
    var spies = ["snapshotReplied", "runsNudged", "projectFilterToggled", "runFilterToggled"].map(function(name) {
      return createTemporaryObject(spyC, tc, { target: store, signalName: name })
    })
    store.historyRuns = [null, 7, "x", [], histRun("a-park1", tc.rootA, "done", "2026-09-20T00:00:00Z"),
                         histRun("a-h1", tc.rootA, "started", "2026-09-19T00:00:00Z", true),
                         histRun("a-h1", tc.rootA, "done", "2026-09-18T00:00:00Z")]
    compare(ids(store.listedRuns), "a-park1,a-h1", "each id once")
    verify(store.listedRuns[0] === store.runs[0], "the snapshot's object wins")
    verify(store.listedRuns[1] === store.historyRuns[5], "the first of a duplicated history id")
    compare(Runs.runState(store.listedRuns[1]), "running")
    compare(ids(store.filteredRuns), "a-park1,a-h1")
    store.runFilter = "parked"
    compare(ids(store.filteredRuns), "a-park1", "the shared id is the snapshot's parked run")
    compare(ids(store.runs), "a-park1", "runs stays the snapshot")
    compare(store.hasRunningRun, false, "a running history run is not the snapshot's")
    compare(JSON.stringify(store.appliedSeq), applied)
    compare(JSON.stringify(store.knownRunIds()), known)
    compare(store.snapshotRunner.seq, seq, "no snapshot launched")
    for (var i = 0; i < spies.length; i++) compare(spies[i].count, 0, spies[i].signalName)
  }

  // Review Focus 2
  function test_a_history_that_is_not_an_array_lists_the_snapshot_alone() {
    var store = historyStore(); if (!store) return
    var values = [null, "runs", 3, ({ id: "a-h1" })]
    for (var i = 0; i < values.length; i++) {
      store.historyRuns = values[i]
      compare(ids(store.listedRuns), "a-live1,a-park1,b-park1", "historyRuns " + JSON.stringify(values[i]))
      compare(ids(store.filteredRuns), "a-live1,a-park1,b-park1")
    }
  }

  // H9
  function test_the_cursor_walks_snapshot_then_history_and_run_by_id_finds_both() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage().concat([histRun("a-park1", tc.rootA, "done", "2026-09-17T00:00:00Z")])
    var expected = ["b-park1", "b-h1", "a-live1", "a-park1", "a-h1", "a-h2"]
    compare(store.filteredRuns.length, expected.length)
    for (var i = 0; i < expected.length; i++) {
      compare(store.filteredRuns[i].id, expected[i], "row " + i)
      verify(store.runById(expected[i]) === store.filteredRuns[i], "runById(" + expected[i] + ")")
    }
    compare(store.runById("a-park1").status, "stopped", "a snapshot id is the snapshot's run")
    compare(store.runById("nope"), null)
  }

  // Review Focus 1
  function test_a_selected_history_run_fetches_its_logs_from_its_root() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage()
    store.selectedRunId = "b-h1"
    store.selectAttempt("c1", "spec", 1)
    compare(argv(store.logsRunner.current), "python3|/plugin/core/backend/runs/runs-logs.py|" + tc.rootB + "|b-h1|c1|spec|1")
    compare(store.logsLoading, true)
  }
```

Also extend the file's header comment (lines 1-11). Replace:

```qml
// project switch leaves alone, and the snapshotReplied it emits. Built
```

with:

```qml
// project switch leaves alone, the snapshotReplied it emits, and the Runs
// screen's list over the snapshot plus the history App hands it. Built
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL lines for `test_each_projects_history_follows_its_snapshot_runs`, `test_the_snapshot_wins_and_odd_history_entries_are_skipped`, `test_a_history_that_is_not_an_array_lists_the_snapshot_alone`, `test_the_cursor_walks_snapshot_then_history_and_run_by_id_finds_both` and `test_a_selected_history_run_fetches_its_logs_from_its_root` (`listedRuns` is undefined: a `TypeError` reading `.map` of undefined, or wrong ids / `null` from `runById`). Every other test passes.

- [ ] **Step 3: Add `historyRuns`, `listedRuns` and `listed()`, and feed `groups` from `listedRuns`**

In `core/stores/RunStore.qml`, replace lines 77-79:

```qml
  // The runs past the chip, the search and the project filter, grouped by
  // project in display order (Runs.groupByProject).
  readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery), store.projectFilter))
```

with:

```qml
  // Older runs, each built like a snapshot run
  // (Runs.withProject(Runs.normalizeRun(..), root, name)); App binds it. It
  // changes no snapshot member.
  property var historyRuns: []
  // `runs`, then each historyRuns entry that is a plain object whose id
  // neither `runs` nor an earlier entry lists, in historyRuns order.
  readonly property var listedRuns: store.listed(store.runs, store.historyRuns)
  // listedRuns past the chip, the search and the project filter, grouped by
  // project in display order (Runs.groupByProject).
  readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(store.listedRuns, store.runFilter), store.searchQuery), store.projectFilter))
```

Then replace `runById` (lines 649-652):

```qml
  // The run with this id in the snapshot, or null.
  function runById(id) {
    return Runs.runById(store.runs, id)
  }
```

with:

```qml
  // The run with this id in the snapshot, else in the listed history, or null.
  function runById(id) {
    return Runs.runById(store.listedRuns, id)
  }

  // A new array: `runs`, then each entry of `history` that is a plain object
  // whose id no entry before it lists. `runs` itself when `history` is not
  // an array.
  function listed(runs, history) {
    if (!Array.isArray(history)) return runs
    var out = runs.slice()
    var ids = runs.map(function(run) { return run.id })
    for (var i = 0; i < history.length; i++) {
      var run = history[i]
      if (run === null || typeof run !== "object" || Array.isArray(run) || ids.indexOf(run.id) >= 0) continue
      ids.push(run.id)
      out.push(run)
    }
    return out
  }
```

Then, in `fetchLogs`'s comment (lines 683-686), replace:

```qml
  // snapshot that changes it fetches again). Nothing launches for a run not
  // in the snapshot or one with no project root.
```

with:

```qml
  // snapshot that changes it fetches again). Nothing launches for a run
  // runById does not find or one with no project root.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: no `FAIL!` line, no `TypeError`/`ReferenceError` line; `Totals:` shows 0 failed.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore lists App's history runs after each project's snapshot runs, the snapshot winning"
```

---

### Task 2: The Finished chip's rows, title search and `runFilterCounts` in the `groups` pipeline

**Files:**
- Modify: `core/stores/RunStore.qml:62-66` (`runFilter` comment), the `groups` block written in Task 1
- Test: `tests/core/stores/tst_run_store.qml` (append to the 3.3 history section)

**Interfaces:**
- Consumes: `RunStore.historyRuns`, `RunStore.listedRuns` (Task 1); test helpers `histRun`, `historyStore`, `historyPage` (Task 1).
- Produces: `RunStore.titlesByRoot: var` (default `({})`), `RunStore.finishedState: string` (default `""`), `RunStore.finishedAge: string` (default `"all"`), `RunStore.nowMs: real` (default `0`), `RunStore.runFilterCounts: readonly var` (`{attention, live, parked, finished, all}`). Test helpers `fixedNow`, `fixedMidnight`, `fixedWeekAgo`, `iso(ms)`, `finishedStore()`.

- [ ] **Step 1: Write the failing tests**

Append to the 3.3 history section of `tests/core/stores/tst_run_store.qml` (still before the file's final `}`):

```qml

  // Noon local time on 2026-10-09: the age tests' clock; that day's local
  // midnight; the clock minus 7 days.
  readonly property real fixedNow: new Date(2026, 9, 9, 12, 0, 0).getTime()
  readonly property real fixedMidnight: new Date(2026, 9, 9, 0, 0, 0).getTime()
  readonly property real fixedWeekAgo: fixedNow - 7 * 86400000

  // `ms` as an ISO started_at.
  function iso(ms) { return new Date(ms).toISOString() }

  // rootA and rootB registered, the snapshot answered: A lists a-live1
  // (running), a-dead1, a-park1, a-done1 and a-esc1, B lists b-canc1
  // ("cancelled"); the history adds A's a-hdone, a-hcanc ("canceled") and
  // a-hpark, and B's b-hesc. Every run started before 2026-10-02; nowMs is
  // fixedNow.
  function finishedStore() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([
      okEntry(tc.rootA, [entry("a-live1", "started", true, tc.rootA), entry("a-dead1", "started", false, tc.rootA),
                         entry("a-park1", "stopped", false, tc.rootA), entry("a-done1", "done", false, tc.rootA),
                         entry("a-esc1", "escalated", false, tc.rootA)]),
      okEntry(tc.rootB, [entry("b-canc1", "cancelled", false, tc.rootB)])]), 0)
    store.nowMs = tc.fixedNow
    store.historyRuns = [histRun("a-hdone", tc.rootA, "done", "2026-09-20T00:00:00Z"),
                         histRun("a-hcanc", tc.rootA, "canceled", "2026-09-19T00:00:00Z"),
                         histRun("a-hpark", tc.rootA, "stopped", "2026-09-18T00:00:00Z"),
                         histRun("b-hesc", tc.rootB, "escalated", "2026-09-17T00:00:00Z")]
    return store
  }

  // H3
  function test_each_chip_lists_snapshot_and_history_runs() {
    var store = finishedStore(); if (!store) return
    compare(ids(store.filteredRuns), "a-live1,a-dead1,a-park1,a-done1,a-esc1,a-hdone,a-hcanc,a-hpark,b-canc1,b-hesc")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "a-dead1,a-esc1,b-hesc")
    store.runFilter = "live"
    compare(ids(store.filteredRuns), "a-live1")
    store.runFilter = "parked"
    compare(ids(store.filteredRuns), "a-park1,a-hpark")
    store.runFilter = "finished"
    compare(ids(store.filteredRuns), "a-done1,a-esc1,a-hdone,a-hcanc,b-canc1,b-hesc")
    compare(groupText(store), "alpha:1/0/0,beta:1/0/0")
  }

  // H3
  function test_run_filter_counts_cover_snapshot_and_history_in_the_project_filter() {
    var store = finishedStore(); if (!store) return
    var all = JSON.stringify({ attention: 3, live: 1, parked: 2, finished: 6, all: 10 })
    compare(JSON.stringify(store.runFilterCounts), all)
    store.runFilter = "live"
    store.searchQuery = "zzz"
    store.finishedState = "done"
    store.finishedAge = "today"
    compare(store.filteredRuns.length, 0)
    compare(JSON.stringify(store.runFilterCounts), all, "the chip, the search and the finished rows never narrow the counts")
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(JSON.stringify(store.runFilterCounts), JSON.stringify({ attention: 1, live: 0, parked: 0, finished: 2, all: 2 }))
  }

  // H4
  function test_the_finished_state_row_narrows_under_finished_only() {
    var store = finishedStore(); if (!store) return
    store.runFilter = "finished"
    store.finishedState = "done"
    compare(ids(store.filteredRuns), "a-done1,a-hdone")
    store.finishedState = "escalated"
    compare(ids(store.filteredRuns), "a-esc1,b-hesc")
    store.finishedState = "cancelled"
    compare(ids(store.filteredRuns), "a-hcanc,b-canc1", "both spellings")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "a-live1,a-dead1,a-park1,a-done1,a-esc1,a-hdone,a-hcanc,a-hpark,b-canc1,b-hesc",
            "All: the state row narrows nothing")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "a-dead1,a-esc1,b-hesc", "Attention: nothing either")
  }

  // Review Focus 5
  function test_an_unknown_finished_state_or_age_narrows_nothing() {
    var store = finishedStore(); if (!store) return
    store.runFilter = "finished"
    store.finishedState = "bogus"
    store.finishedAge = "fortnight"
    compare(ids(store.filteredRuns), "a-done1,a-esc1,a-hdone,a-hcanc,b-canc1,b-hesc")
  }

  // rootA alone, the snapshot answered with a-live1 (running), a-dead1 and
  // a-esc1, all started 2026-10-01T00:00:00Z; nowMs is fixedNow; the
  // history: t-after (done, a minute after midnight), t-before (done, a
  // minute before), w-in (escalated, a minute inside the 7 days), w-out
  // (done, a minute outside), h-park (parked) and h-live (running), both 8
  // days old, and h-nostart (done, no started_at).
  function ageStore() {
    var store = makeWithRoots([tc.rootA]); if (!store) return null
    reply(store.snapshotRunner.current, okReply([entry("a-live1", "started", true), entry("a-dead1", "started", false),
                                                 entry("a-esc1", "escalated", false)]), 0)
    store.nowMs = tc.fixedNow
    var old = tc.fixedWeekAgo - 86400000
    store.historyRuns = [histRun("t-after", tc.rootA, "done", iso(tc.fixedMidnight + 60000)),
                         histRun("t-before", tc.rootA, "done", iso(tc.fixedMidnight - 60000)),
                         histRun("w-in", tc.rootA, "escalated", iso(tc.fixedWeekAgo + 60000)),
                         histRun("w-out", tc.rootA, "done", iso(tc.fixedWeekAgo - 60000)),
                         histRun("h-park", tc.rootA, "stopped", iso(old)),
                         histRun("h-live", tc.rootA, "started", iso(old), true),
                         histRun("h-nostart", tc.rootA, "done", "")]
    return store
  }

  // H5
  function test_the_age_row_narrows_finished_runs_under_finished_and_all() {
    var store = ageStore(); if (!store) return
    store.runFilter = "finished"
    compare(ids(store.filteredRuns), "a-esc1,t-after,t-before,w-in,w-out,h-nostart", "all time")
    store.finishedAge = "today"
    compare(ids(store.filteredRuns), "t-after", "since local midnight; no started_at is hidden")
    store.finishedAge = "week"
    compare(ids(store.filteredRuns), "t-after,t-before,w-in", "the last 7 x 24 h")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "a-live1,a-dead1,t-after,t-before,w-in,h-park,h-live",
            "All: the age narrows finished runs only")
    store.finishedAge = "today"
    compare(ids(store.filteredRuns), "a-live1,a-dead1,t-after,h-park,h-live",
            "a running, dead or parked run is never hidden")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "a-dead1,a-esc1,w-in", "Attention: the age narrows nothing")
    store.runFilter = "parked"
    compare(ids(store.filteredRuns), "h-park", "Parked: nothing either")
    store.runFilter = "live"
    compare(ids(store.filteredRuns), "a-live1,h-live")
  }

  // Review Focus 3
  function test_now_ms_0_measures_the_age_against_the_current_time() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.nowMs, 0)
    store.historyRuns = [histRun("fresh", tc.rootA, "done", iso(Date.now())),
                         histRun("stale", tc.rootA, "done", iso(Date.now() - 8 * 86400000))]
    store.runFilter = "finished"
    store.finishedAge = "week"
    compare(ids(store.filteredRuns), "fresh")
  }

  // H8
  function test_the_search_matches_a_history_runs_title() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage()
    store.searchQuery = "widget"
    compare(store.filteredRuns.length, 0, "no title map: no title to match")
    var titles = {}
    titles[tc.rootA] = { "m-a-h2": "Ship the Widget" }
    store.titlesByRoot = titles
    compare(ids(store.filteredRuns), "a-h2")
    store.titlesByRoot = ({})
    compare(store.filteredRuns.length, 0)
  }

  // Review Focus 4
  function test_without_a_title_map_the_search_matches_ids_and_fallback_titles() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage()
    store.titlesByRoot = "garbage"
    store.searchQuery = "b-h1"
    compare(ids(store.filteredRuns), "b-h1")
    store.searchQuery = "milestone …m-a-h2"
    compare(ids(store.filteredRuns), "a-h2", "runTitle's fallback title")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL lines for the new tests: `runFilterCounts` is undefined (`JSON.stringify(undefined)` mismatches), `finishedState`/`finishedAge`/`nowMs`/`titlesByRoot` do not exist (a "Cannot assign to non-existent property" error or wrong ids), and the age/state rows narrow nothing. The Task 1 tests still pass.

- [ ] **Step 3: Add the inputs, `runFilterCounts` and the full `groups` pipeline**

In `core/stores/RunStore.qml`, replace the `runFilter` comment (lines 62-64):

```qml
  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and a project switch.
```

with:

```qml
  // The Runs screen's chip ("" means All, else "attention" | "live" |
  // "parked" | "finished") and search text. App binds searchQuery to the
  // navigation store; the chip survives a section switch and a project switch.
```

Then replace the `groups` comment and binding Task 1 left:

```qml
  // listedRuns past the chip, the search and the project filter, grouped by
  // project in display order (Runs.groupByProject).
  readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(store.listedRuns, store.runFilter), store.searchQuery), store.projectFilter))
```

with:

```qml
  // {root: {id: title}}, the titles the search matches; App binds it.
  property var titlesByRoot: ({})
  // The Finished chip's state row ("" is every finished state, else "done" |
  // "escalated" | "cancelled") and age row ("today" | "week" | "all", by
  // started_at against nowMs). The state row narrows finished runs under
  // Finished only, the age row under Finished and All; neither hides a run
  // that is not finished.
  property string finishedState: ""
  property string finishedAge: "all"
  // The age row's clock in ms; 0 is Date.now() whenever `groups` is
  // evaluated. Time passing alone re-evaluates nothing.
  property real nowMs: 0
  // The chip counts, {attention, live, parked, finished, all}, over
  // listedRuns in the project filter; the chip, the finished rows and the
  // search never narrow them.
  readonly property var runFilterCounts: Runs.runFilterCounts(Runs.filterByProject(store.listedRuns, store.projectFilter))
  // listedRuns past the chip, the finished rows, the search (titles from
  // titlesByRoot) and the project filter, grouped by project in display
  // order (Runs.groupByProject).
  readonly property var groups: {
    var now = store.nowMs > 0 ? store.nowMs : Date.now()
    var state = store.runFilter === "finished" ? store.finishedState : ""
    var age = store.runFilter === "finished" || store.runFilter === "" ? store.finishedAge : "all"
    var kept = Runs.filterFinished(Runs.filterRuns(store.listedRuns, store.runFilter), state, age, now, -new Date(now).getTimezoneOffset())
    return Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(kept, store.searchQuery, store.titlesByRoot), store.projectFilter))
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: no `FAIL!` line, no `TypeError`/`ReferenceError` line; `Totals:` shows 0 failed.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore narrows finished runs by state and age, searches titles and counts every chip"
```

---

### Task 3: `toggleFinishedState`, `toggleFinishedAge` and their reset when the panel closes

**Files:**
- Modify: `core/stores/RunStore.qml:67-68` (`runFilterToggled` comment), the `finishedState`/`finishedAge` comment from Task 2, `:221-225` (after `toggleRunFilter`), `:287-302` (`stopLive`)
- Test: `tests/core/stores/tst_run_store.qml` (append to the 3.3 history section)

**Interfaces:**
- Consumes: `RunStore.finishedState`, `RunStore.finishedAge` (Task 2); `RunStore.historyRuns`, `RunStore.listedRuns` and test helper `histRun` (Task 1).
- Produces: `RunStore.toggleFinishedState(id)`, `RunStore.toggleFinishedAge(id)`, both emitting `runFilterToggled()` once per call; `stopLive()` resets `finishedState` to `""` and `finishedAge` to `"all"`.

- [ ] **Step 1: Write the failing tests**

Append to the 3.3 history section of `tests/core/stores/tst_run_store.qml` (still before the file's final `}`):

```qml

  // H6
  function test_toggle_finished_state() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    var steps = [["done", "done"], ["escalated", "escalated"], ["escalated", ""], ["cancelled", "cancelled"],
                 ["all", ""], ["cancelled", "cancelled"], ["bogus", ""], ["", ""], ["done", "done"], [undefined, ""]]
    for (var i = 0; i < steps.length; i++) {
      store.toggleFinishedState(steps[i][0])
      compare(store.finishedState, steps[i][1], "toggleFinishedState(" + steps[i][0] + ")")
      compare(spy.count, i + 1, "one runFilterToggled per call, changed or not")
    }
    compare(store.runFilter, "", "the chip is untouched")
    compare(store.finishedAge, "all")
  }

  // H6
  function test_toggle_finished_age() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    var steps = [["today", "today"], ["week", "week"], ["week", "all"], ["today", "today"], ["all", "all"],
                 ["week", "week"], ["bogus", "all"], ["all", "all"]]
    for (var i = 0; i < steps.length; i++) {
      store.toggleFinishedAge(steps[i][0])
      compare(store.finishedAge, steps[i][1], "toggleFinishedAge(" + steps[i][0] + ")")
      compare(spy.count, i + 1, "one runFilterToggled per call, changed or not")
    }
    compare(store.runFilter, "", "the chip is untouched")
    compare(store.finishedState, "")
  }

  // H6
  function test_the_chip_and_the_finished_rows_are_independent_and_survive_a_project_switch() {
    var store = makeWithProject(rootA); if (!store) return
    store.toggleFinishedState("escalated")
    store.toggleFinishedAge("week")
    store.toggleRunFilter("finished")
    compare(store.runFilter, "finished")
    compare(store.finishedState, "escalated", "the chip leaves the state row")
    compare(store.finishedAge, "week", "and the age row")
    store.toggleRunFilter("finished")
    compare(store.runFilter, "")
    compare(store.finishedState, "escalated")
    compare(store.finishedAge, "week")
    store.project = rootB
    compare(store.finishedState, "escalated", "a project switch keeps the state row")
    compare(store.finishedAge, "week", "and the age row")
  }

  // H7
  function test_closing_the_panel_resets_the_finished_rows_and_keeps_the_chip() {
    var store = projectsStore(true); if (!store) return
    store.historyRuns = [histRun("a-h1", tc.rootA, "done", "2026-09-20T00:00:00Z")]
    store.toggleRunFilter("finished")
    store.searchQuery = "a-"
    store.toggleFinishedState("done")
    store.toggleFinishedAge("week")
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    store.active = false
    compare(store.finishedState, "")
    compare(store.finishedAge, "all")
    compare(store.projectFilter, "")
    compare(spy.count, 0, "no runFilterToggled")
    compare(store.runFilter, "finished", "the chip stays")
    compare(store.searchQuery, "a-", "the search stays")
    verify(ids(store.listedRuns).split(",").indexOf("a-h1") >= 0, "the history is App's input: kept")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL lines for the four new tests (`toggleFinishedState is not a function` / `toggleFinishedAge is not a function` `TypeError`, and in `test_closing_the_panel_resets_the_finished_rows_and_keeps_the_chip` the same error before the close). Tasks 1-2 tests still pass.

- [ ] **Step 3: Add the toggles and the reset on close**

In `core/stores/RunStore.qml`, replace the `runFilterToggled` comment (line 67):

```qml
  // The chip changed: a different list, so the cursor goes home (App's job).
```

with:

```qml
  // The chip, the finished-state row or the age row was chosen: a different
  // list, so the cursor goes home (App's job).
```

Replace the `finishedState`/`finishedAge` comment written in Task 2:

```qml
  // The Finished chip's state row ("" is every finished state, else "done" |
  // "escalated" | "cancelled") and age row ("today" | "week" | "all", by
  // started_at against nowMs). The state row narrows finished runs under
  // Finished only, the age row under Finished and All; neither hides a run
  // that is not finished.
```

with:

```qml
  // The Finished chip's state row ("" is every finished state, else "done" |
  // "escalated" | "cancelled") and age row ("today" | "week" | "all", by
  // started_at against nowMs). The state row narrows finished runs under
  // Finished only, the age row under Finished and All; neither hides a run
  // that is not finished. Set by toggleFinishedState and toggleFinishedAge;
  // a project switch keeps them, the panel closing resets them.
```

Insert right after `toggleRunFilter` (after line 225, the closing `}` of `toggleRunFilter`):

```qml

  // A state row button: "done", "escalated" or "cancelled" other than the
  // current one selects it; the current one again, or anything else, means
  // every finished state (""). Emits runFilterToggled once.
  function toggleFinishedState(id) {
    var known = id === "done" || id === "escalated" || id === "cancelled"
    store.finishedState = known && id !== store.finishedState ? id : ""
    store.runFilterToggled()
  }

  // An age row button: "today" or "week" other than the current one selects
  // it; the current one again, or anything else, means all time ("all").
  // Emits runFilterToggled once.
  function toggleFinishedAge(id) {
    var known = id === "today" || id === "week"
    store.finishedAge = known && id !== store.finishedAge ? id : "all"
    store.runFilterToggled()
  }
```

Replace `stopLive`'s comment and first line (lines 287-293):

```qml
  // The panel closed: no process and no timer is left running. The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The project filter is back to All projects, with no
  // projectFilterToggled. The runs, the selection, the chip and amStatus stay
  // for the next opening.
  function stopLive() {
    store.projectFilter = ""
```

with:

```qml
  // The panel closed: no process and no timer is left running. The
  // pending snapshot request is dropped; a snapshot in flight runs to its end
  // and is applied. The project filter is back to All projects and the
  // finished rows to every state and all time, with no projectFilterToggled
  // or runFilterToggled. The runs, the history, the selection, the chip, the
  // search and amStatus stay for the next opening.
  function stopLive() {
    store.projectFilter = ""
    store.finishedState = ""
    store.finishedAge = "all"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: no `FAIL!` line, no `TypeError`/`ReferenceError` line; `Totals:` shows 0 failed.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore toggles the finished-state and age rows and resets them on closing"
```

---

### Task 4: App wires history, titles and the finished rows; document RunStore's list

**Files:**
- Modify: `core/stores/App.qml:103-112` (the `RunStore runs` comment and block), `:167-175` (the `RunHistoryStore runHistory` comment and block)
- Modify: `core/stores/RunStore.qml:32-36` (header comment)
- Modify: `docs/architecture.md:83` (`RunStore.qml` bullet), `:95` (`RunHistoryStore.qml` bullet)
- Test: `tests/core/stores/tst_app_runs.qml` (header comment lines 14-16; `test_app_composes_run_history_wired_to_the_run_store` at line 901; three new tests); `tests/architecture/test_run_store_docs.py` (unchanged, must pass)

**Interfaces:**
- Consumes: `RunStore.historyRuns`, `titlesByRoot`, `finishedState`, `finishedAge`, `toggleFinishedState(id)`, `toggleFinishedAge(id)`, `listedRuns`, `runById` (Tasks 1-3); `RunHistoryStore.historyByProject`, `showOlder(root)`, `runnerFor(root)`, `finishedState`, `finishedAge`; `RunTitlesStore.titlesByRoot`.
- Produces: App bindings `app.runs.historyRuns`, `app.runs.titlesByRoot`, `app.runHistory.finishedState`, `app.runHistory.finishedAge`.

- [ ] **Step 1: Write the failing App tests**

In `tests/core/stores/tst_app_runs.qml`, replace the whole `test_app_composes_run_history_wired_to_the_run_store` function (line 901 to its closing `}` at line 923, just before the TestCase's final `}`) with:

```qml
  function test_app_composes_run_history_wired_to_the_run_store() {
    var app = make(); if (!app) return
    verify(app.runHistory, "App composes the history store as app.runHistory")
    compare(app.runHistory.backendDir, "/plugin/core/backend/")
    compare(JSON.stringify(app.runHistory.snapshotByProject), JSON.stringify(app.runs.runsByProject))
    compare(app.runHistory.finishedState, "")
    compare(app.runHistory.finishedAge, "all")
    compare(app.runHistory.active, false)
    compare(app.runs.historyRuns.length, 0, "no page yet")
    app.panelOpen = true
    compare(app.runHistory.active, true, "active follows app.panelOpen")
    var text = listReply([runningIn("r1")], [])
    reply(app.runs.snapshotRunner.current, text, 0)
    reply(app.runs.snapshotRunner.current, text, 0)
    compare(app.runs.runsByProject[tc.pA.root_path].length, 1)
    compare(JSON.stringify(app.runHistory.snapshotByProject), JSON.stringify(app.runs.runsByProject),
            "snapshotByProject follows app.runs.runsByProject after an ok snapshot reply")
    app.runs.toggleRunFilter("parked")
    compare(app.runHistory.runFilter, "parked", "runFilter follows app.runs.runFilter")
    app.runs.toggleRunFilter("all")
    compare(app.runHistory.runFilter, "")
    app.runs.toggleFinishedState("done")
    compare(app.runHistory.finishedState, "done", "finishedState follows app.runs.finishedState")
    app.runs.toggleFinishedAge("week")
    compare(app.runHistory.finishedAge, "week", "finishedAge follows app.runs.finishedAge")
    app.panelOpen = false
    compare(app.runHistory.active, false)
    compare(app.runHistory.finishedState, "", "the run store's reset on closing reaches the history store")
    compare(app.runHistory.finishedAge, "all")
  }

  // One runs-history.py entry: done run `id` of `root`, started 2026-09-01.
  function historyEntry(id, root) {
    return { id: id, repo_dir: root, started_at: "2026-09-01T00:00:00Z",
             status: { run: { id: id, milestone_id: "m-" + id, status: "done" }, rows: [], stories: [], subtasks: [] } }
  }

  // app.runHistory.showOlder(root), answered with an ok page of `entries`.
  function historyPage(app, root, entries) {
    app.runHistory.showOlder(root)
    reply(app.runHistory.runnerFor(root).current, JSON.stringify({ ok: true, runs: entries, more: false }) + "\n", 0)
  }

  function test_app_hands_the_run_store_every_history_page_flattened() {
    var app = openApp([escalatedIn("r1")], [escalatedIn("r2", tc.pB.root_path)]); if (!app) return
    historyPage(app, tc.pB.root_path, [historyEntry("h2", tc.pB.root_path)])
    historyPage(app, tc.pA.root_path, [historyEntry("h1", tc.pA.root_path), historyEntry("h3", tc.pA.root_path)])
    compare(Object.keys(app.runHistory.historyByProject).join(","), tc.pB.root_path + "," + tc.pA.root_path)
    compare(app.runs.historyRuns.map(function(r) { return r.id }).join(","), "h2,h1,h3",
            "root by root, in Object.keys order")
    verify(app.runs.historyRuns[0] === app.runHistory.historyByProject[tc.pB.root_path].runs[0],
           "the history store's own objects")
    compare(app.runs.filteredRuns.map(function(r) { return r.id }).join(","), "r1,h1,h3,r2,h2",
            "each project's history after its snapshot runs")
    compare(app.runs.runs.length, 2, "the snapshot stays snapshot-only")
    compare(app.runs.runById("h1").id, "h1")
  }

  function test_app_hands_the_run_store_the_run_titles() {
    var app = make(); if (!app) return
    compare(JSON.stringify(app.runs.titlesByRoot), JSON.stringify(app.runTitles.titlesByRoot))
    app.board.applyTreeData([{ id: "c1", title: "One", status: "todo", children: [] }])
    compare(app.runs.titlesByRoot[tc.pA.root_path].c1, "One", "titlesByRoot follows app.runTitles.titlesByRoot")
  }

  function test_a_finished_row_toggle_puts_the_cursor_home() {
    var app = make(); if (!app) return
    app.nav.cursorIndex = 3
    app.nav.scrollOnCursor = true
    app.runs.toggleFinishedState("escalated")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
    app.nav.cursorIndex = 2
    app.nav.scrollOnCursor = true
    app.runs.toggleFinishedAge("today")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
  }
```

In the header comment (lines 14-16), replace:

```qml
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag, and `app.runHistory`,
// which App feeds with the backend dir, the panel-open flag, the run store's
// per-project snapshot and its chip. The stores' own behaviour is tested in
```

with:

```qml
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag, and whose titles map
// App hands the run store, and `app.runHistory`, which App feeds with the
// backend dir, the panel-open flag, the run store's per-project snapshot, its
// chip and its finished rows, and whose pages App hands the run store
// flattened. The stores' own behaviour is tested in
```

- [ ] **Step 2: Run the App tests to verify they fail**

Run: `bash tests/run.sh tst_app_runs`
Expected: FAIL lines for `test_app_composes_run_history_wired_to_the_run_store` (`finishedState follows app.runs.finishedState`: `""` vs `"done"`), `test_app_hands_the_run_store_every_history_page_flattened` (`historyRuns` is `[]`: `""` vs `"h2,h1,h3"`) and `test_app_hands_the_run_store_the_run_titles` (`titlesByRoot` stays `{}`: a `TypeError` reading `.c1` of undefined). `test_a_finished_row_toggle_puts_the_cursor_home` already passes (the route exists since the toggles emit `runFilterToggled`).

- [ ] **Step 3: Wire App**

In `core/stores/App.qml`, replace the `RunStore runs` comment and its first bindings (lines 103-111):

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object) and the panel-open flag that starts and
  // stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
    searchQuery: app.nav.searchQuery
```

with:

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object), the panel-open flag that starts and
  // stops its watch, the run history's pages flattened root by root and the
  // run titles' map.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
    searchQuery: app.nav.searchQuery
    historyRuns: {
      var byProject = app.runHistory.historyByProject
      var roots = Object.keys(byProject)
      var out = []
      for (var i = 0; i < roots.length; i++) {
        var entry = byProject[roots[i]]
        if (entry !== null && typeof entry === "object" && Array.isArray(entry.runs)) out = out.concat(entry.runs)
      }
      return out
    }
    titlesByRoot: app.runTitles.titlesByRoot
```

Replace the `RunHistoryStore runHistory` comment and block (lines 167-175):

```qml
  // The run history never imports the run store: App hands it the backend
  // directory, the panel-open flag, the run store's per-project snapshot and
  // its chip. App routes no signal from it.
  readonly property RunHistoryStore runHistory: RunHistoryStore {
    backendDir: app.backendDir
    active: app.panelOpen
    snapshotByProject: app.runs.runsByProject
    runFilter: app.runs.runFilter
  }
```

with:

```qml
  // The run history never imports the run store: App hands it the backend
  // directory, the panel-open flag, the run store's per-project snapshot, its
  // chip and its finished rows. App routes no signal from it.
  readonly property RunHistoryStore runHistory: RunHistoryStore {
    backendDir: app.backendDir
    active: app.panelOpen
    snapshotByProject: app.runs.runsByProject
    runFilter: app.runs.runFilter
    finishedState: app.runs.finishedState
    finishedAge: app.runs.finishedAge
  }
```

- [ ] **Step 4: Run the App tests to verify they pass**

Run: `bash tests/run.sh tst_app_runs`
Expected: no `FAIL!` line, no `TypeError`/`ReferenceError`/binding-loop line; `Totals:` shows 0 failed. The pytest part of the run now FAILS `test_each_bullet_names_every_input_and_routed_signal_app_wires[RunStore]` (the doc bullet lacks `historyRuns` and `titlesByRoot`) — Step 5 fixes it.

- [ ] **Step 5: Document it**

In `docs/architecture.md` line 83 (the `RunStore.qml` bullet), replace:

```markdown
`active` (App's `panelOpen`, which the panel binds to its `opened`) and `searchQuery` (`app.nav.searchQuery`).
```

with:

```markdown
`active` (App's `panelOpen`, which the panel binds to its `opened`), `searchQuery` (`app.nav.searchQuery`), `historyRuns` (every `app.runHistory.historyByProject[root].runs`, concatenated in `Object.keys` order; `[]` when there is no page) and `titlesByRoot` (`app.runTitles.titlesByRoot`).
```

and append to the end of the same line 83 (after `so a snapshot only names the run ids the store knows.`), as part of the same bullet line:

```markdown
 The Runs screen's list: `runFilter` is `""` (All), `attention`, `live`, `parked` or `finished` (done, escalated or cancelled, either spelling). `finishedState` (`""` is every finished state, else `done`, `escalated` or `cancelled`; set by `toggleFinishedState(id)`) narrows finished runs under Finished only; `finishedAge` (`today` since local midnight, `week` the last 7×24 h, else `all`; set by `toggleFinishedAge(id)`) narrows finished runs by `started_at` under Finished and All, against `nowMs` (`0` is `Date.now()` when the list is evaluated); neither ever hides a run that is not finished. Each toggle emits `runFilterToggled()`; a project switch keeps both, and the panel closing resets them to `""` and `all` alongside the project filter, with no signal, while the chip and the search stay. `listedRuns` is `runs`, then each `historyRuns` entry that is a plain object whose id neither `runs` nor an earlier entry lists, so the snapshot wins an id both list; setting `historyRuns` changes neither `runs` nor any other snapshot member, and the store never clears it. `runFilterCounts` (`{attention, live, parked, finished, all}`) counts `listedRuns` in the project filter; the chip, the finished rows and the search never narrow it. `groups` is `listedRuns` through `Runs.filterRuns` (the chip), `Runs.filterFinished` (the finished rows), `Runs.searchRuns` (the search, which matches titles from `titlesByRoot`), `Runs.filterByProject` and `Runs.groupByProject`; `filteredRuns` (`Runs.displayOrder(groups)`) is the list the screen draws and the cursor indexes, so a project's history follows its snapshot runs, newest first. `runById(id)` returns the snapshot run with that id, else the listed history run, else `null`.
```

In `docs/architecture.md` line 95 (the `RunHistoryStore.qml` bullet), replace:

```markdown
`snapshotByProject` (`app.runs.runsByProject`) and `runFilter` (`app.runs.runFilter`); its inputs `finishedState` (default `""`, every finished state) and `finishedAge` (default `"all"`, all time) are not bound yet.
```

with:

```markdown
`snapshotByProject` (`app.runs.runsByProject`), `runFilter` (`app.runs.runFilter`), `finishedState` (`app.runs.finishedState`; `""` is every finished state) and `finishedAge` (`app.runs.finishedAge`; `"all"` is all time).
```

In `core/stores/RunStore.qml`, replace the header comment's lines 32-36:

```qml
// Each applied list snapshot reply is announced per project
// (snapshotReplied).
// The registry, the open project's root and the backend directory are handed
// to it from outside -- it never reaches for another store. App composes it
// as `app.runs` and binds `active` to the panel being open.
```

with:

```qml
// Each applied list snapshot reply is announced per project
// (snapshotReplied).
// The Runs screen's list (groups, filteredRuns) is listedRuns -- `runs`, then
// the ids of `historyRuns` that `runs` lacks -- past the chip, the
// finished-state and age rows, the search (titles from `titlesByRoot`) and
// the project filter, each project's history after its snapshot runs;
// runById falls back to the listed history. History changes no snapshot
// member.
// The registry, the open project's root, the history, the titles and the
// backend directory are handed to it from outside -- it never reaches for
// another store. App composes it as `app.runs` and binds `active` to the
// panel being open.
```

- [ ] **Step 6: Run the doc tests and the whole suite**

Run: `python3 -m pytest tests/architecture/test_run_store_docs.py -q` (or `uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`)
Expected: all pass.

Run: `bash tests/run.sh`
Expected: pytest all pass; every QML file prints `Totals:` with 0 failed; no `FAIL!`, `TypeError`, `ReferenceError`, `Unable to assign`, `non-existent` or `is not a function` line; exit code 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/App.qml core/stores/RunStore.qml tests/core/stores/tst_app_runs.qml docs/architecture.md
git commit -m "feat(runs): App hands RunStore the history pages and titles and RunHistoryStore the finished rows; document it"
```

---

## Spec coverage check

| Spec requirement | Task |
|---|---|
| `historyRuns` input, default `[]` | 1 |
| `listedRuns`: runs then plain-object history ids, snapshot wins, first duplicate wins, odd entries skipped | 1 (`test_the_snapshot_wins_and_odd_history_entries_are_skipped`, `test_a_history_that_is_not_an_array_lists_the_snapshot_alone`) |
| Snapshot members unchanged, no signals on `historyRuns` | 1 (same test: `runs`, `appliedSeq`, `knownRunIds`, `hasRunningRun`, snapshot seq, four spies) |
| Display order: snapshot runs then history per group, group counts include history | 1 (`test_each_projects_history_follows_its_snapshot_runs`) |
| `runById` snapshot then history | 1 (`test_the_cursor_walks_snapshot_then_history_and_run_by_id_finds_both`, logs test) |
| `titlesByRoot`, `finishedState`, `finishedAge`, `nowMs` inputs and defaults | 2 |
| `runFilter` widened to `finished` | 2 (comment; `test_each_chip_lists_snapshot_and_history_runs`) |
| `runFilterCounts` over listed runs in project filter, not narrowed by chip/rows/search | 2 |
| Pipeline steps 1-6, state under Finished only, age under Finished and All, never hide unfinished | 2 (`..._finished_state_row_...`, `..._age_row_...`) |
| `nowMs` 0 → `Date.now()` | 2 (Review Focus 3) |
| Unknown state/age → every state / all time | 2 (Review Focus 5) |
| Search by title, `titlesByRoot` `{}`/not an object | 2 |
| History run without `started_at` hidden under Today/7 days, shown under All time | 2 (`h-nostart`) |
| `toggleFinishedState` / `toggleFinishedAge` semantics, one signal per call, chip independent, project switch keeps | 3 |
| Panel close resets rows, keeps chip, search, history; no `runFilterToggled` | 3 |
| App: `historyRuns` flattened in `Object.keys` order, `titlesByRoot`, history store's `finishedState`/`finishedAge`, cursor home on toggles, other stores keep snapshot | 4 |
| Docs: RunStore bullet, RunHistoryStore bullet, RunStore header comment; `test_run_store_docs.py` passes | 4 |
| `bash tests/run.sh` green | 4 Step 6 |
<!-- task-pipeline: validated -->
