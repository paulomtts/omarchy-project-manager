# 3.4 RunAlertsStore: titled alerts — design

Card: `02e26233` (subtask of story `b477c51f`, blocked by `e3f027a4`, which is done).
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below
as "P l.N".

## Purpose

A toast and the desktop notification for a run that newly needs a human show the run's
**title** (the milestone's, story's or card's title), not the `milestone …<last 8>` fallback,
whenever the run's project has a titles map, including projects that are not open
(P l.107-108, l.113-115). Nothing else about alerts changes: arming, ordering, keys, expiry,
dismissal, the notify switch and the `project` field all behave exactly as now.

## What already exists (not touched by this card)

- `Runs.newAlerts(prevRuns, nextRuns, titlesByRoot)` (`core/domain/runs.js:1163`). It titles
  each alert `runTitle(run, _titlesFor(run, titlesByRoot))`. `_titlesFor`
  (`runs.js:794`) uses `titlesByRoot`'s own entry for `runRoot(run)` and gives `{}` for a
  missing or non-object map, which yields the fallback title (P l.99-103).
- `RunTitlesStore.titlesByRoot` (`{root: {id: title}}`, P l.80), composed by App as
  `app.runTitles` (`core/stores/App.qml:170`). App already hands it to `RunStore`
  (`App.qml:124`).
- `RunAlertsStore.notify(alert)` already passes `String(alert.title)` as the first argument
  to `notify.py`. A titled alert therefore yields a titled notification with no change there.

## Inherited constraints

- Stores never reach for another store. App hands in every input (P l.8-10; `RunAlertsStore.qml`
  header; `docs/architecture.md:92`).
- Titles come from the run's project map, `titlesByRoot[runRoot(run)]`. A missing map is `{}`
  (P l.102-103).
- `newAlerts` uses titles for the toast and the desktop notification (P l.107-108, l.114-115).
- The test list names `tst_run_alerts_store.qml: titled toasts` (P l.223).
- `docs/architecture.md` layering applies, and `tests/architecture` must pass. Comments state
  the contract only, with no narrative.

## Behavior

1. `RunAlertsStore` gains `property var titlesByRoot: ({})`, typed `{root: {id: title}}`. App
   binds it. The default is the empty object.
2. When `snapshotReplied(root, "ok", previousRuns, runs)` arrives for an armed root while
   `active`, it raises `Runs.newAlerts(previousRuns-or-[], runs, titlesByRoot)`. Each raised
   toast's `title` is therefore `Runs.runTitle(run, titlesByRoot[runRoot(run)] or {})`.
3. A run whose project has no map, or any `titlesByRoot` that is not a plain object, gets the
   fallback title `milestone …<last 8>` (or `story …` / `card …`). This is unchanged from today.
4. With `notifyOnEscalation` on, the `notify.py` argv is `TITLE REASON`, and TITLE is the toast's
   title from rule 2.
5. Changing `titlesByRoot` re-titles no toast that is already raised, and it raises nothing
   new. Only the next armed `ok` reply reads it.
6. App binds `runAlerts.titlesByRoot: app.runTitles.titlesByRoot`, the same map it gives
   `app.runs.titlesByRoot`.

## Error paths

Errors raise nothing. A `titlesByRoot` that is not an object, null, or holds a non-object entry
for a root falls back to the id title (rule 3) through the domain function. A run with no root
(`runRoot` gives `""`) also falls back.

## Files

- `core/stores/RunAlertsStore.qml`: add the property next to `projectRoots`, with a trailing
  comment in the existing style (`// {root: {id: title}}; App binds it`). Pass
  `alerts.titlesByRoot` as `newAlerts`' third argument at line 57. Update the header comment
  (lines 6-19): list the titles map among what App hands in, and say a toast's `title` is the
  run's title from its project's map. Update the `snapshotReplied` comment (lines 44-49) to
  `Runs.newAlerts(previousRuns, runs, titlesByRoot)`.
- `core/stores/App.qml` (`runAlerts` block, about lines 156-165): add
  `titlesByRoot: app.runTitles.titlesByRoot`, and make the comment above it name the run
  titles' map.
- `docs/architecture.md:92` (the `RunAlertsStore` bullet): add `titlesByRoot`
  (`app.runTitles.titlesByRoot`) to what App hands it. The raised call becomes
  `Runs.newAlerts(previousRuns, runs, titlesByRoot)`, and a toast's and the notification's title
  is the run's title.

## Tests

Write every test first and watch it fail before the implementation. The gate is `bash tests/run.sh`
(full suite, including `tests/architecture`).

In `tests/core/stores/tst_run_alerts_store.qml` (tier: QML store unit test, because the
behavior is the store's wiring of its own input into `newAlerts`, and the existing helpers
`armedAlerts`, `runningRun`, `escalatedRun`, `argv` and `notifyCmd` drive it in isolation).
`runOf(id, …, root)` builds `milestone_id: "m-" + id` with `repo_dir: root`, so the map key is
`"m-<id>"`:

- **T1 `test_a_run_of_a_project_that_is_not_open_toasts_with_its_title`**: run
  `armedAlerts([rootB])`, then `titlesByRoot = {[rootB]: {"m-b1": "Ship it"}}` and
  `snapshotReplied(rootB, "ok", [runningRun("b1", rootB)], [escalatedRun("b1", rootB)])`.
  `toasts[0].title` is `"Ship it"`, `project` is `"beta"` and `state` is `"escalated"`. The store
  has no "open project" notion, so rootB stands in for a project that is not open.
- **T2 `test_without_a_map_for_the_runs_project_the_toast_falls_back_to_the_id`**: run it
  with the default `titlesByRoot` and get `"milestone …m-b1"`. Run it again with a map only
  for rootA (`{[rootA]: {"m-b1": "Wrong"}}`) and still get `"milestone …m-b1"`, because a map
  is per project. Run it a third time with a non-object `titlesByRoot` (`"x"`) and get the
  fallback, with no throw.
- **T3 `test_the_notification_carries_the_runs_title`**: set `notifyOnEscalation = true` and
  `titlesByRoot = {[rootA]: {"m-a1": "Ship it"}}`. `argv(notifyRunners[0].current)` equals
  `notifyCmd + "Ship it|escalated"`.
- **T4 `test_a_titles_change_retitles_no_raised_toast`**: raise a toast with no map, then set
  `titlesByRoot`. `toasts` stays the same array, with the same title, and nothing new is raised.

In `tests/core/stores/tst_app_runs.qml` (tier: App composition test, because only App can
show the binding, and it sits beside the existing
`test_app_hands_the_run_store_the_run_titles` at about line 961):

- **T5 `test_app_hands_the_run_alerts_the_run_titles`**: check that
  `JSON.stringify(app.runAlerts.titlesByRoot)` equals `app.runTitles.titlesByRoot`'s.
  After `app.board.applyTreeData([{id: "c1", title: "One", …}])`,
  `app.runAlerts.titlesByRoot[pA.root_path].c1 === "One"`.

Existing tests that assert `"milestone …m-b1"` / `"milestone …m-a1"` (for example
`tst_run_alerts_store.qml:149, :281` and `tst_app_runs.qml:481`) keep passing, because no map
names those runs.

## Out of scope

- Any change to `core/domain/runs.js` (`newAlerts`, `runTitle` and `_titlesFor` are done by
  sibling domain cards), to `RunTitlesStore`, or to `notify.py`.
- Toast UI rendering, and the title's display anywhere else (Runs rows, Run detail, Events,
  cancel dialog, card RUNS rows), which belong to sibling UI and store cards.
- Re-titling raised toasts when titles arrive later.
- History, filters and `RunHistoryStore`.
