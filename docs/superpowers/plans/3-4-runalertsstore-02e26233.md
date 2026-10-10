# 3.4 RunAlertsStore: titled alerts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toast and the desktop notification for a run that newly needs a human show the run's title from its project's titles map: `RunAlertsStore` gains a `titlesByRoot` input passed to `Runs.newAlerts`, App binds it to `app.runTitles.titlesByRoot`, and `docs/architecture.md` says so.

**Architecture:** `RunAlertsStore` gets one plain input, `property var titlesByRoot: ({})`, and passes it as the third argument of the existing `Runs.newAlerts(previousRuns, runs, titlesByRoot)` call in `snapshotReplied`. The domain function already titles each alert from `titlesByRoot[runRoot(run)]` and falls back to `milestone …<8>` for anything missing or malformed; `notify()` already sends `alert.title`. App binds the new input to the same map it gives `app.runs`.

**Tech Stack:** QML (QtQml, Quickshell, Quickshell.Io), the pure JS library `core/domain/runs.js` (no change), QtTest (`qmltestrunner`) with stubbed `Process` objects, pytest for the architecture/doc tests.

**Spec:** `docs/superpowers/specs/3-4-runalertsstore-02e26233.md` (reproduced verbatim in the "Spec" section below; parent design `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`).

## Global Constraints

- Stores never reach for another store; App hands in every input. `RunAlertsStore.qml`'s imports do not change (`QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/runs.js`).
- `titlesByRoot` is typed `{root: {id: title}}`; its default is `({})`.
- No change to `core/domain/runs.js`, `RunTitlesStore.qml`, `notify.py`, any UI file, `RunHistoryStore.qml` or `RunStore.qml`.
- Arming, ordering, keys, expiry, dismissal, the notify switch and the `project` field behave exactly as now; every existing test passes unchanged (for example the `"milestone …m-b1"` / `"milestone …m-a1"` asserts in `tst_run_alerts_store.qml` and `tst_app_runs.qml`).
- A `titlesByRoot` change re-titles no raised toast and raises nothing; only the next armed `ok` reply reads it.
- Comments state the contract only, with no narrative.
- `docs/architecture.md`'s `RunAlertsStore.qml` bullet names every input App binds on it (`tests/architecture/test_run_store_docs.py::test_each_bullet_names_every_input_and_routed_signal_app_wires`).
- Gate: `bash tests/run.sh` green (full suite, including `tests/architecture`); no `TypeError`, `ReferenceError`, `Unable to assign`, `non-existent` or `is not a function` line in QML output.

## Review Focus

1. A project map that exists but does not name the run (`{rootB: {"m-other": "Other"}}`): the toast falls back to `milestone …m-b1`, never another run's title. Test: Task 1 `test_without_a_map_for_the_runs_project_the_toast_falls_back_to_the_id` (fourth case).
2. A project entry that is not an object (`{rootB: null}`, `{rootB: "x"}`): fallback title, nothing throws. Test: Task 1 `test_without_a_map_for_the_runs_project_the_toast_falls_back_to_the_id` (fifth and sixth cases).
3. A map that arrives after a toast was raised is read by the very next armed `ok` reply: a new alert in that reply is titled while the older toast keeps its fallback title. Test: Task 1 `test_a_titles_change_retitles_no_raised_toast` (second half).
4. A dead run's notification is titled too (`TITLE|process died`), not only an escalation's. Test: Task 1 `test_the_notification_carries_the_runs_title` (second reply).
5. Closing and reopening the panel keeps `titlesByRoot` (the close resets arming and toasts, never the map): the first alert after re-arming is titled. Test: Task 1 `test_the_titles_map_outlives_closing_the_panel`.

---

## Spec

### 3.4 RunAlertsStore: titled alerts — design

Card: `02e26233` (subtask of story `b477c51f`, blocked by `e3f027a4`, which is done).
Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`, cited below
as "P l.N".

#### Purpose

A toast and the desktop notification for a run that newly needs a human show the run's
**title** (the milestone's, story's or card's title), not the `milestone …<last 8>` fallback,
whenever the run's project has a titles map, including projects that are not open
(P l.107-108, l.113-115). Nothing else about alerts changes: arming, ordering, keys, expiry,
dismissal, the notify switch and the `project` field all behave exactly as now.

#### What already exists (not touched by this card)

- `Runs.newAlerts(prevRuns, nextRuns, titlesByRoot)` (`core/domain/runs.js:1163`). It titles
  each alert `runTitle(run, _titlesFor(run, titlesByRoot))`. `_titlesFor`
  (`runs.js:794`) uses `titlesByRoot`'s own entry for `runRoot(run)` and gives `{}` for a
  missing or non-object map, which yields the fallback title (P l.99-103).
- `RunTitlesStore.titlesByRoot` (`{root: {id: title}}`, P l.80), composed by App as
  `app.runTitles` (`core/stores/App.qml:170`). App already hands it to `RunStore`
  (`App.qml:124`).
- `RunAlertsStore.notify(alert)` already passes `String(alert.title)` as the first argument
  to `notify.py`. A titled alert therefore yields a titled notification with no change there.

#### Inherited constraints

- Stores never reach for another store. App hands in every input (P l.8-10; `RunAlertsStore.qml`
  header; `docs/architecture.md:92`).
- Titles come from the run's project map, `titlesByRoot[runRoot(run)]`. A missing map is `{}`
  (P l.102-103).
- `newAlerts` uses titles for the toast and the desktop notification (P l.107-108, l.114-115).
- The test list names `tst_run_alerts_store.qml: titled toasts` (P l.223).
- `docs/architecture.md` layering applies, and `tests/architecture` must pass. Comments state
  the contract only, with no narrative.

#### Behavior

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

#### Error paths

Errors raise nothing. A `titlesByRoot` that is not an object, null, or holds a non-object entry
for a root falls back to the id title (rule 3) through the domain function. A run with no root
(`runRoot` gives `""`) also falls back.

#### Files

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

#### Tests

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

#### Out of scope

- Any change to `core/domain/runs.js` (`newAlerts`, `runTitle` and `_titlesFor` are done by
  sibling domain cards), to `RunTitlesStore`, or to `notify.py`.
- Toast UI rendering, and the title's display anywhere else (Runs rows, Run detail, Events,
  cancel dialog, card RUNS rows), which belong to sibling UI and store cards.
- Re-titling raised toasts when titles arrive later.
- History, filters and `RunHistoryStore`.

---

## File Structure

Line numbers below are those of the files before this plan; Task 2's line numbers in files Task 1 does not touch are unaffected. Locate each edit by the quoted text it replaces.

- Modify `core/stores/RunAlertsStore.qml` — header comment (lines 6-19), the new `titlesByRoot` property after `projectRoots` (line 26), the `snapshotReplied` comment (lines 43-48) and the `Runs.newAlerts` call (line 56) (Task 1).
- Modify `tests/core/stores/tst_run_alerts_store.qml` — header comment (lines 1-6), a new helper `titlesOf(root, titles)` and a new `// ---- titled alerts (history-and-titles 3.4)` section inserted after the S12 test (which ends at line 290) and before `// ---- through a RunStore wired the way App wires app.runAlerts` (line 294) (Task 1).
- Modify `core/stores/App.qml` — the comment and block of `readonly property RunAlertsStore runAlerts` (lines 156-165) (Task 2).
- Modify `tests/core/stores/tst_app_runs.qml` — header comment (lines 13-18) and a new test after `test_app_hands_the_run_store_the_run_titles` (lines 961-966) (Task 2).
- Modify `docs/architecture.md` — the `RunAlertsStore.qml` bullet (line 92) (Task 2).

## How to run the tests

- One QML test file: `bash tests/run.sh tst_run_alerts_store` (the argument filters QML test paths by substring, so this runs `tst_run_alerts_store.qml` only; the script always runs the whole pytest suite first). A QML test fails when the output shows a `FAIL!` line, or any `TypeError` / `ReferenceError` / `Unable to assign` / `non-existent` / `is not a function` line; the script then exits non-zero. Read the `Totals:` line.
- The App test: `bash tests/run.sh tst_app_runs`.
- pytest alone: `python3 -m pytest tests/architecture/test_run_store_docs.py -q`; if `python3` has no pytest, use `uv run --with pytest python3 -m pytest tests/architecture/test_run_store_docs.py -q`.
- Everything: `bash tests/run.sh`.
- Wrap any run you fear may hang in `timeout 600`.

Facts the engineer needs:

- Helpers that already exist in `tests/core/stores/tst_run_alerts_store.qml` (all `TestCase` functions, callable unqualified): `makeAlerts()` (a bare store, `backendDir: "/plugin/core/backend/"`), `armedAlerts(roots)` (an active store with each root armed by an empty ok reply, no toast), `runOf(id, runStatus, live, root)` (milestone id `"m-" + id`, `repo_dir` `root` else `rootA`, project name `"alpha"` for rootA, `"beta"` for rootB), `runningRun(id, root)`, `deadRun(id, root)`, `escalatedRun(id, root)`, `toastIdsOf(a)` (comma-joined toast ids), `argv(proc)` (`command.join("|")`), `reply(proc, text, code)`. Properties: `rootA` `"/home/u/my proj"`, `rootB` `"/home/u/b"`, `notifyCmd` `"python3|/plugin/core/backend/runs/notify.py|"`.
- `Runs.runTitle` of a milestone run: `titles[milestone_id]` when that is a usable string, else `"milestone …" + milestone_id.slice(-8)` (`"milestone …m-b1"` for `m-b1`). `newAlerts`'s reason for a dead run is `"process died"`, for an escalation with no reason am gives, `"escalated"`.
- `notify(alert)` runs `["python3", "<backendDir>runs/notify.py", String(alert.title), String(alert.reason)]` on its own `HelperRunner` in `notifyRunners` while `notifyOnEscalation` is on.
- Assigning a property a QML object does not declare throws a `TypeError` in the test run, so before Task 1's implementation every new store test fails at `a.titlesByRoot = ...`; that is the expected RED.
- `tests/core/stores/tst_app_runs.qml`'s `make()` builds a whole App with project `pA` (`{root_path: "/home/u/my proj", name: "alpha"}`) open; `app.board.applyTreeData(tree)` fills the open project's card map, which `app.runTitles` folds into `titlesByRoot[pA.root_path]`.
- `tests/architecture/test_run_store_docs.py::test_each_bullet_names_every_input_and_routed_signal_app_wires` reads every `    name:` line of App's `RunAlertsStore runAlerts { … }` block and requires the doc bullet to name each one backticked (`` `titlesByRoot` ``). Binding the App input without the doc edit therefore fails that test.

---

### Task 1: `RunAlertsStore` titles each alert from its project's map

**Files:**
- Modify: `core/stores/RunAlertsStore.qml:6-19, 26, 43-48, 56`
- Test: `tests/core/stores/tst_run_alerts_store.qml:1-6` and a new section inserted between lines 290 and 294

**Interfaces:**
- Consumes: `Runs.newAlerts(prevRuns, nextRuns, titlesByRoot)` (exists, `core/domain/runs.js:1163`).
- Produces: `RunAlertsStore.titlesByRoot` — `property var`, `{root: {id: title}}`, default `({})`. Task 2 binds it as `titlesByRoot: app.runTitles.titlesByRoot`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_alerts_store.qml`, replace the header comment lines

```qml
// The run alerts store: per-project arming, the toast queue, the toast expiry
// and the notify.py desktop notification. Built alone and driven through
// snapshotReplied, active and projectRoots; and, through a RunStore wired to
// it the way App wires them, a real snapshot reply turning into a toast.
```

with

```qml
// The run alerts store: per-project arming, the toast queue, the toast expiry,
// the toasts' titles and the notify.py desktop notification. Built alone and
// driven through snapshotReplied, active, projectRoots and titlesByRoot; and,
// through a RunStore wired to it the way App wires them, a real snapshot reply
// turning into a toast.
```

Then insert, directly after the closing `  }` of `test_notifications_follow_the_switch` (the S12 test, line 290) and before the `// ---- through a RunStore wired the way App wires app.runAlerts` line, this block (keep one blank line before it and two blank lines after it, as the file has now):

```qml

  // ---- titled alerts (history-and-titles 3.4)

  // The titles map {root: titles}, as App hands it over.
  function titlesOf(root, titles) {
    var m = {}
    m[root] = titles
    return m
  }

  // The title of the toast an armed rootB store raises for b1's escalation,
  // with titlesByRoot `titles` (left at its default when undefined).
  function escalationTitle(titles) {
    var a = armedAlerts([tc.rootB]); if (!a) return null
    if (titles !== undefined) a.titlesByRoot = titles
    a.snapshotReplied(tc.rootB, "ok", [runningRun("b1", tc.rootB)], [escalatedRun("b1", tc.rootB)])
    compare(a.toasts.length, 1, "one toast")
    return a.toasts[0].title
  }

  // T1
  function test_a_run_of_a_project_that_is_not_open_toasts_with_its_title() {
    var a = armedAlerts([tc.rootB]); if (!a) return
    a.titlesByRoot = titlesOf(tc.rootB, { "m-b1": "Ship it" })
    a.snapshotReplied(tc.rootB, "ok", [runningRun("b1", tc.rootB)], [escalatedRun("b1", tc.rootB)])
    compare(toastIdsOf(a), "b1")
    compare(a.toasts[0].title, "Ship it")
    compare(a.toasts[0].project, "beta")
    compare(a.toasts[0].state, "escalated")
  }

  // T2
  function test_without_a_map_for_the_runs_project_the_toast_falls_back_to_the_id() {
    var bare = makeAlerts(); if (!bare) return
    compare(JSON.stringify(bare.titlesByRoot), "{}", "the default is the empty map")
    compare(escalationTitle(undefined), "milestone …m-b1", "no map at all")
    compare(escalationTitle(titlesOf(tc.rootA, { "m-b1": "Wrong" })), "milestone …m-b1", "a map is per project")
    compare(escalationTitle("x"), "milestone …m-b1", "a titlesByRoot that is not an object")
    compare(escalationTitle(titlesOf(tc.rootB, { "m-other": "Other" })), "milestone …m-b1", "a map that does not name the run")
    compare(escalationTitle(titlesOf(tc.rootB, null)), "milestone …m-b1", "a null project entry")
    compare(escalationTitle(titlesOf(tc.rootB, "x")), "milestone …m-b1", "a project entry that is not an object")
  }

  // T3
  function test_the_notification_carries_the_runs_title() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.notifyOnEscalation = true
    a.titlesByRoot = titlesOf(tc.rootA, { "m-a1": "Ship it", "m-a2": "Second" })
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(a.notifyRunners.length, 1)
    compare(argv(a.notifyRunners[0].current), tc.notifyCmd + "Ship it|escalated")
    a.snapshotReplied(tc.rootA, "ok", [escalatedRun("a1"), runningRun("a2")], [escalatedRun("a1"), deadRun("a2")])
    compare(a.notifyRunners.length, 2)
    compare(argv(a.notifyRunners[1].current), tc.notifyCmd + "Second|process died", "a dead run's notification is titled too")
  }

  // T4
  function test_a_titles_change_retitles_no_raised_toast() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(a.toasts[0].title, "milestone …m-a1")
    var toasts = a.toasts
    a.titlesByRoot = titlesOf(tc.rootA, { "m-a1": "Ship it", "m-a2": "Second" })
    verify(a.toasts === toasts, "toasts is not replaced")
    compare(toastIdsOf(a), "a1", "nothing new is raised")
    compare(a.toasts[0].title, "milestone …m-a1", "the raised toast keeps its title")
    a.snapshotReplied(tc.rootA, "ok", [escalatedRun("a1"), runningRun("a2")], [escalatedRun("a1"), deadRun("a2")])
    compare(toastIdsOf(a), "a1,a2")
    compare(a.toasts[0].title, "milestone …m-a1", "still not re-titled")
    compare(a.toasts[1].title, "Second", "the next armed ok reply reads the new map")
  }

  // T4b
  function test_the_titles_map_outlives_closing_the_panel() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.titlesByRoot = titlesOf(tc.rootA, { "m-a1": "Ship it" })
    a.active = false
    a.active = true
    a.snapshotReplied(tc.rootA, "ok", [], [runningRun("a1")])
    compare(a.toasts.length, 0, "the reopening's first ok reply only arms")
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1")
    compare(a.toasts[0].title, "Ship it")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_alerts_store`
Expected: FAIL. `T1`, `T3`, `T4`, `T4b` and `T2` fail with a `TypeError` (assigning the undeclared `titlesByRoot`) or, for T2, `bare.titlesByRoot` undefined (`compare` of `undefined` with `"{}"`); the script exits non-zero. Every pre-existing test still passes.

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunAlertsStore.qml`:

a) Replace the header comment lines

```qml
// armed. `toasts` is {key, id, title, state, reason, project, expiresMs},
// oldest first, at most 3, and is replaced, never changed in place; `project`
// is the name of the run's project. The backend directory, the panel-open
// flag, the notify switch and the registry are handed to it from outside --
// it never reaches for another store. App composes it as `app.runAlerts` and
// routes the run store's snapshotReplied here.
```

with

```qml
// armed. `toasts` is {key, id, title, state, reason, project, expiresMs},
// oldest first, at most 3, and is replaced, never changed in place; `title`
// is the run's title from its project's map in titlesByRoot (the fallback
// title without one) and `project` is the name of the run's project. The
// backend directory, the panel-open flag, the notify switch, the registry and
// the run titles' map are handed to it from outside -- it never reaches for
// another store. App composes it as `app.runAlerts` and routes the run store's
// snapshotReplied here.
```

b) Replace

```qml
  property var projectRoots: []             // [{root, name}], the registry in its order; App binds it
```

with

```qml
  property var projectRoots: []             // [{root, name}], the registry in its order; App binds it
  property var titlesByRoot: ({})           // {root: {id: title}}; App binds it
```

c) Replace the `snapshotReplied` comment lines

```qml
  // One project's snapshot reply. "ok" while active: when `root` is armed,
  // Runs.newAlerts(previousRuns, runs) is raised (a non-array previousRuns
```

with

```qml
  // One project's snapshot reply. "ok" while active: when `root` is armed,
  // Runs.newAlerts(previousRuns, runs, titlesByRoot) is raised (a non-array previousRuns
```

d) Replace

```qml
      var found = Runs.newAlerts(Array.isArray(previousRuns) ? previousRuns : [], runs)
```

with

```qml
      var found = Runs.newAlerts(Array.isArray(previousRuns) ? previousRuns : [], runs, alerts.titlesByRoot)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_alerts_store`
Expected: PASS — the `Totals:` line shows 0 failed, no `TypeError`/`ReferenceError`/`Unable to assign`/`non-existent`/`is not a function` line, exit 0. The existing `"milestone …m-b1"` / `"milestone …m-a1"` asserts still pass.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunAlertsStore.qml tests/core/stores/tst_run_alerts_store.qml
git commit -m "feat(runs): RunAlertsStore titles each toast and notification from its project's titles map"
```

---

### Task 2: App hands the run alerts the run titles; document it

**Files:**
- Modify: `core/stores/App.qml:156-165`
- Modify: `docs/architecture.md:92`
- Test: `tests/core/stores/tst_app_runs.qml:13-18, 961-966`

**Interfaces:**
- Consumes: `RunAlertsStore.titlesByRoot` (Task 1, `property var`, `{root: {id: title}}`); `app.runTitles.titlesByRoot` (exists).
- Produces: `app.runAlerts.titlesByRoot` bound to `app.runTitles.titlesByRoot`.

- [ ] **Step 1: Write the failing test**

In `tests/core/stores/tst_app_runs.qml`, replace the header comment lines

```qml
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag, and whose titles map
// App hands the run store, and `app.runHistory`, which App feeds with the
// backend dir, the panel-open flag, the run store's per-project snapshot, its
// chip and its finished rows, and whose pages App hands the run store
// flattened. The stores' own behaviour is tested in
```

with

```qml
// `app.runTitles`, which App feeds with the registry, the open project's root
// and card map, the run list and the panel-open flag, and whose titles map
// App hands the run store and the run alerts, and `app.runHistory`, which App
// feeds with the backend dir, the panel-open flag, the run store's
// per-project snapshot, its chip and its finished rows, and whose pages App
// hands the run store flattened. The stores' own behaviour is tested in
```

Then insert, directly after the closing `  }` of `test_app_hands_the_run_store_the_run_titles` (line 966) and a blank line:

```qml
  function test_app_hands_the_run_alerts_the_run_titles() {
    var app = make(); if (!app) return
    compare(JSON.stringify(app.runAlerts.titlesByRoot), JSON.stringify(app.runTitles.titlesByRoot))
    app.board.applyTreeData([{ id: "c1", title: "One", status: "todo", children: [] }])
    compare(app.runAlerts.titlesByRoot[tc.pA.root_path].c1, "One", "titlesByRoot follows app.runTitles.titlesByRoot")
  }

```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash tests/run.sh tst_app_runs`
Expected: FAIL in `test_app_hands_the_run_alerts_the_run_titles`. App binds nothing yet, so `app.runAlerts.titlesByRoot` stays the store's default `{}` after `applyTreeData`: if `app.runTitles.titlesByRoot` already differs from `{}`, the first `compare` fails; otherwise the second line reads `.c1` of `undefined` and fails with a `TypeError`. Either way the script exits non-zero.

- [ ] **Step 3: Bind the input in App**

In `core/stores/App.qml`, replace

```qml
  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, run control's notify switch and the
  // registry, and routes every project's snapshot reply (runs.snapshotReplied)
  // here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runControl.notifyOnEscalation
    projectRoots: app.runs.projectRoots
  }
```

with

```qml
  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, run control's notify switch, the registry
  // and the run titles' map, and routes every project's snapshot reply
  // (runs.snapshotReplied) here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runControl.notifyOnEscalation
    projectRoots: app.runs.projectRoots
    titlesByRoot: app.runTitles.titlesByRoot
  }
```

- [ ] **Step 4: Run the App test and the doc test**

Run: `timeout 600 bash tests/run.sh tst_app_runs`
Expected: `tst_app_runs.qml` PASS (0 failed), but the pytest run at the start of the script FAILS `tests/architecture/test_run_store_docs.py::test_each_bullet_names_every_input_and_routed_signal_app_wires[RunAlertsStore]` with `missing == ['titlesByRoot']` — the doc does not name the new input yet.

- [ ] **Step 5: Document the input**

In `docs/architecture.md` line 92 (the `- \`RunAlertsStore.qml\`` bullet), make three replacements inside that one line:

a) Replace

```
`notifyOnEscalation` (`app.runControl.notifyOnEscalation`) and `projectRoots` (`app.runs.projectRoots`), and routes
```

with

```
`notifyOnEscalation` (`app.runControl.notifyOnEscalation`), `projectRoots` (`app.runs.projectRoots`) and `titlesByRoot` (`app.runTitles.titlesByRoot`, `{root: {id: title}}`), and routes
```

b) Replace

```
raises `Runs.newAlerts(previousRuns, runs)` (a non-array `previousRuns` counts as `[]`; a non-array `runs` raises nothing), in the order of `runs`, each with `project` the `project.name` of its run (`""` when it has none), and then arms the root;
```

with

```
raises `Runs.newAlerts(previousRuns, runs, titlesByRoot)` (a non-array `previousRuns` counts as `[]`; a non-array `runs` raises nothing), in the order of `runs`, each with `title` the run's title from its project's map in `titlesByRoot` (the fallback title `milestone …<8>`, `story …` or `card …` without one) and `project` the `project.name` of its run (`""` when it has none), and then arms the root; a `titlesByRoot` change re-titles no raised toast and raises nothing;
```

c) Replace

```
every raised alert also runs `notify.py TITLE REASON` on a
```

with

```
every raised alert also runs `notify.py TITLE REASON` (TITLE the toast's `title`) on a
```

- [ ] **Step 6: Run the full gate**

Run: `timeout 600 bash tests/run.sh`
Expected: PASS — pytest all green (including `tests/architecture/test_run_store_docs.py` and `tests/architecture/test_layers.py`), every QML file's `Totals:` line shows 0 failed, no `TypeError`/`ReferenceError`/`Unable to assign`/`non-existent`/`is not a function` line, exit 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/App.qml tests/core/stores/tst_app_runs.qml docs/architecture.md
git commit -m "feat(runs): App hands RunAlertsStore the run titles; document it"
```

---

## Spec coverage check

- Behavior 1 (property, default `{}`) — Task 1 Step 3b; T2 asserts the default.
- Behavior 2 (armed ok reply raises `newAlerts(..., titlesByRoot)`, title from the run's project map) — Task 1 Step 3d; T1.
- Behavior 3 (fallback for no map / non-object) — T2 (six cases).
- Behavior 4 (notify argv `TITLE REASON`) — T3 (escalated and dead).
- Behavior 5 (a change re-titles nothing, raises nothing; next armed ok reply reads it) — T4.
- Behavior 6 (App binding) — Task 2 Step 3; T5.
- Files: header + property + `snapshotReplied` comment + call (Task 1 Step 3a-d); App block and comment (Task 2 Step 3); `docs/architecture.md:92` (Task 2 Step 5).
- Error paths: non-object `titlesByRoot`, null / non-object entry — T2. A run with no root (`runRoot` `""`) falls back inside `_titlesFor`; the store cannot raise such a run through `armedAlerts` helpers (every `runOf` run has a root), and the domain tests own that path.
- Existing tests unchanged and passing — Task 1 Step 4, Task 2 Step 6.
<!-- task-pipeline: validated -->
