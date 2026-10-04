<!-- task-pipeline: validated -->
# 3.3 Compose RunStore in App.qml (card e82dd5ac)

Parent story: 779eb1bf "RunStore". Milestone design: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` (architecture diagram `app.runs` -> RunStore; "Receives project (root path) and backendDir through explicit properties from App.qml; never reaches for BoardStore"; refresh model: panel opens or project changes -> snapshot, panel closes -> watch killed; "Update docs/architecture.md (store list, shortcuts) in the same change").

Siblings 3.1 (6768ae0b, snapshot/selection/amStatus) and 3.2 (5a3c8015, watch/debounce/liveness/stale) are done. This card only composes and wires.

## Prerequisite

The base must already contain `core/stores/RunStore.qml`, `core/domain/runs.js`, `core/backend/runs/*` and `tests/core/stores/tst_run_store.qml` from 3.1/3.2. This worktree (`.claude/worktrees/mon/task-3-3-compose-runstore-in-e82dd5ac`) has them. If a base lacks `RunStore.qml`, stop: App.qml cannot load it, and porting 3.1/3.2 is out of scope.

## Scope

1. `core/stores/App.qml`:
   - Add `property bool panelOpen: false`. It is App's input for "the panel is open". App has no such input today.
   - Add `readonly property RunStore runs: RunStore { ... }`, following the docs/memories/milestones blocks. Wire it only through explicit properties:
     - `backendDir: app.backendDir`
     - `project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""`. RunStore.project is a root-path string. ProjectStore.selectedProject is `{root_path, name}` or null, and the object must never be passed.
     - `active: app.panelOpen`
   - Add a short comment like the milestone one: the run store never imports the project or board store, and App hands it the root path and the panel-open flag.
   - App.qml keeps importing only `QtQml`.
2. `ui/Panel.qml`: on the existing `Core.App { id: appStores; ... }` line (line 44), add `panelOpen: root.opened`. Leave the existing `onOpenedChanged` handler as it is.
3. `docs/architecture.md`, "Stores (`core/stores`)" list: add one `RunStore.qml` entry after the `MilestoneStore.qml` entry and before "Other `ui/` pieces". It says: snapshot of the selected project's am runs (runs-snapshot.py through runs.js), selection, amStatus, the watch while the panel is open (250 ms debounce, 10 s liveness, stale flag, schema/corrupt fallback poll), and that it receives `project` (root path), `backendDir` and `active` from App. Do not add Ctrl+6 or shortcut text. That belongs to the later UI cards.
4. Optional: replace the "Composing it into App (3.3) comes later." sentence in RunStore.qml's header comment with a statement of the current fact. Comment only, no logic change.

## Observable behavior

- `app.runs` exists and is a RunStore. Constructing App with no project selected loads cleanly: `runs.project === ""`, `runs.active === false`, and no snapshot or watch starts.
- `app.runs.backendDir` follows `app.backendDir`.
- After `app.projects.chooseProject(pA)`, `app.runs.project === pA.root_path`. Switching to pB updates it to pB's root path. `app.projects.clearSelection()` sets it back to `""`, and RunStore's own 3.1 clearing applies.
- `app.runs.active` follows `app.panelOpen`. In a real panel it follows `Panel.opened`, so opening the panel starts RunStore's activation path (snapshot plus watch, per 3.1/3.2) and closing it stops the watch.
- The load raises no binding errors, TypeErrors, ReferenceErrors or "Unable to assign" messages, all of which `tests/run.sh` treats as failures. In particular a null `selectedProject` must not throw.

## Error paths

- `selectedProject` is null at startup or after a clear: the ternary yields `""`. RunStore's `refresh()` already no-ops on `""`.
- `selectedProject` has no `root_path`: this is not expected from ProjectStore. No extra guard is added beyond the null check.
- No new failure modes. am missing, schema or corrupt-journal handling stays inside RunStore (3.1/3.2).

## Out of scope

- Any RunStore.qml logic, runs.js, or `core/backend/runs/*`.
- RunsScreen, RunDetailScreen, the sidebar row, Ctrl+6, Navigator registration, Run* components, and shortcut docs.
- Making RunStore reach for ProjectStore or BoardStore. Adding signal routing between RunStore and other stores.

## Tests (TDD: write them first and watch them fail)

Placement follows `docs/architecture.md` "How to add" / "Tests": a store and its App composition are tested headless under `tests/core/stores/`, and anything that needs `ui/Panel.qml` goes under `tests/ui/`. Neither `tests/contract/` (brd/am JSON shape drift only) nor `tests/core/backend/` (pytest for helpers) applies.

1. `tests/core/stores/tst_app_runs.qml` (new; tier: tests/core/stores, a headless store test driven through App, like `tst_milestone_store.qml`). Create App via `Qt.createComponent("../../../core/stores/App.qml")` with `backendDir: "/plugin/core/backend/"`. Do not copy the milestone test's `make()` verbatim: `applyProjectsList` auto-selects the first project (`chooseProject` in `core/domain/projects.js` falls back to `list[0]`) once the stored state is loaded, so the "no project" assertions must run before the list is applied.
   - Right after creation: `app.runs` is non-null, `runs.backendDir === app.backendDir`, `runs.project === ""` and `runs.active === false`. A `null` `selectedProject` does not throw.
   - Then `applyStoredState('{"last_project": null}', 0)` and `applyProjectsList([pA, pB])`: pA is auto-selected, so `runs.project === pA.root_path`, a string and not the object.
   - After `chooseProject(pB)` it equals pB's root path. (`chooseProject(pA)` would be a no-op while pA is already selected.)
   - After `clearSelection()`, `runs.project === ""`.
   - Setting `app.panelOpen = true` makes `runs.active` true, and `false` makes it false again.
2. `tests/ui/tst_plugin_dir.qml` or a similar existing Panel-level test (tier: tests/ui, because it needs `ui/Panel.qml`). Add one case: after `p.opened = true`, `p.app.runs.active === true`, and after `p.opened = false` it is `false`. This guards the Panel.qml binding. Prefer extending an existing Panel test that already toggles `p.opened`, such as `tst_sidebar_nav.qml`, over creating a new file. A new `tests/ui/tst_panel_runs.qml` is also acceptable.
3. Architecture tests (tier: tests/architecture, existing, unchanged): `python3 -m pytest tests/architecture -q` stays green. App.qml still imports only `QtQml`, and RunStore's import allowlist is untouched.

Verification: `bash ./tests/run.sh` passes. There is no typecheck or lint.

---

# Compose RunStore in App.qml Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compose the existing RunStore into `core/stores/App.qml` as `app.runs`, wired to the backend dir, the selected project's root path and a new `panelOpen` flag that `ui/Panel.qml` drives from `root.opened`, and list the store in `docs/architecture.md`.

**Architecture:** App is the only place stores are wired together. It gains one input (`panelOpen: false`) and one composed store (`runs`), whose three inputs are bound from App properties only, so RunStore never reaches for ProjectStore or BoardStore. Panel sets `panelOpen: root.opened` on its existing `Core.App` declaration. No RunStore logic changes.

**Tech Stack:** QML (Qt 6, QtQml/QtQuick), QtTest via `qmltestrunner` with Quickshell stubs in `tests/stubs`, pytest for `tests/architecture`, all driven by `bash ./tests/run.sh`.

**Spec:** `docs/superpowers/specs/task-3-3-compose-runstore-in-e82dd5ac-design.md` (reproduced verbatim above).

All paths below are relative to the worktree root `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-3-3-compose-runstore-in-e82dd5ac` (branch `mon/task-3-3-compose-runstore-in-e82dd5ac`, cut from `mon/task-3-2-runstore-watch-5a3c8015`). Run every command from that directory.

## Global Constraints

- Prerequisite check before Task 1: `core/stores/RunStore.qml`, `core/domain/runs.js`, `core/backend/runs/` and `tests/core/stores/tst_run_store.qml` must exist in the worktree. If `RunStore.qml` is missing, stop and escalate: porting 3.1/3.2 is out of scope.
- `core/stores/App.qml` keeps importing only `QtQml`.
- `project` is bound to `app.projects.selectedProject ? app.projects.selectedProject.root_path : ""`. Never pass the `selectedProject` object.
- `active` is bound to `app.panelOpen`. The new App property is named `panelOpen` and defaults to `false`.
- `backendDir` is bound to `app.backendDir`.
- Do not modify RunStore.qml logic, `core/domain/runs.js` or `core/backend/runs/*`. The only RunStore.qml change allowed is the header-comment sentence "Composing it into App (3.3) comes later."
- No UI: no RunsScreen, RunDetailScreen, sidebar row, Ctrl+6, Navigator registration, Run* components or shortcut docs.
- Leave Panel.qml's existing `onOpenedChanged` handler untouched.
- `tests/run.sh` fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `is not a function` in QML output, so every binding must be null-safe.

## Review Focus

- Panel opened with no project selected: `runs.active` becomes true but no snapshot and no watch may start (`refresh()` no-ops on `""`). Pinned in Task 1 (`test_opening_with_no_project_launches_nothing`).
- The snapshot command must carry the root path string, not `[object Object]`, when a project is chosen through App. Pinned in Task 1 (`test_the_snapshot_runs_for_the_selected_root_path`).
- Clearing the selection through App must also drop the runs the previous project showed (3.1's switch clearing, reached through the binding). Pinned in Task 1 (`test_clearing_the_selection_empties_project_and_runs`).
- Closing the panel through App must stop a running watch (3.2's `stopLive`, reached through `panelOpen`). Pinned in Task 1 (`test_panel_close_through_app_stops_the_watch`).
- A real Panel toggling `opened` must reach `app.runs.active` in both directions. Pinned in Task 2.

---

### Task 1: Compose RunStore in App with `panelOpen`

**Files:**
- Create: `tests/core/stores/tst_app_runs.qml`
- Modify: `core/stores/App.qml:9` (add `panelOpen`) and `core/stores/App.qml:97-98` (add the `runs` block after the `milestones` block)

**Interfaces:**
- Consumes: `RunStore` (existing, `core/stores/RunStore.qml`): `property string project`, `property string backendDir`, `property bool active`, `property var runs`, `readonly property alias snapshotRunner` (a HelperRunner with `current`, whose Process has `command`, `outText`, `exited(int)`), `readonly property alias watching`, `readonly property alias watchProc`. `ProjectStore`: `selectedProject` (`{root_path, name}` or null), `applyStoredState(text, exitCode)`, `applyProjectsList(list)`, `chooseProject(project)`, `clearSelection()`.
- Produces: `App.panelOpen: bool` (default `false`), `App.runs: RunStore` (readonly). Task 2 relies on both names.

- [ ] **Step 0: Confirm the prerequisite**

Check that these exist in the worktree: `core/stores/RunStore.qml`, `core/domain/runs.js`, `core/backend/runs/runs-snapshot.py`, `core/backend/runs/runs-watch.py`, `tests/core/stores/tst_run_store.qml`. If `RunStore.qml` is missing, stop and escalate.

- [ ] **Step 1: Write the failing test**

Create `tests/core/stores/tst_app_runs.qml`:

```qml
// tests/core/stores/tst_app_runs.qml
// App's composition of the run monitor's store: `app.runs` exists, and its
// three inputs come from App -- the backend dir, the selected project's ROOT
// PATH (never the project object), and App's panel-open flag. The store's own
// behaviour is tested in tst_run_store.qml; here only the wiring is.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresAppRuns"

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  // App with no project selected yet: applyProjectsList auto-selects the first
  // project once the stored state is loaded, so that is a separate step.
  function makeBare() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // App with pA auto-selected.
  function make() {
    var app = makeBare(); if (!app) return null
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    return app
  }

  function okReply(ids) {
    var runs = ids.map(function(id) {
      return { id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
               status: { run: { id: id, milestone_id: "m-" + id, status: "done" }, rows: [], stories: [], subtasks: [],
                         control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: false } } } }
    })
    return JSON.stringify({ ok: true, runs: runs, data_dir: "/home/u/.local/share" }) + "\n"
  }

  function test_app_composes_a_run_store_with_no_project_and_closed() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "App composes the run store as app.runs")
    verify(app.runs.snapshotRunner, "it is a RunStore")
    compare(app.projects.selectedProject, null)
    compare(app.runs.backendDir, app.backendDir)
    compare(app.runs.backendDir, "/plugin/core/backend/")
    compare(app.runs.project, "", "a null selectedProject becomes an empty root path")
    compare(app.panelOpen, false)
    compare(app.runs.active, false)
    verify(!app.runs.snapshotRunner.current, "no snapshot without a project")
    compare(app.runs.watching, false)
  }

  function test_the_backend_dir_follows_app() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.backendDir = "/other/core/backend/"
    compare(app.runs.backendDir, "/other/core/backend/")
  }

  function test_the_project_is_the_selected_root_path_string() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    compare(app.projects.selectedProject.root_path, pA.root_path, "pA was auto-selected")
    compare(typeof app.runs.project, "string")
    compare(app.runs.project, "/home/u/my proj")
    app.projects.chooseProject(pB)
    compare(app.runs.project, "/home/u/b")
  }

  function test_the_snapshot_runs_for_the_selected_root_path() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    var proc = app.runs.snapshotRunner.current
    verify(proc, "selecting a project starts a snapshot")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command[2], "/home/u/my proj")
  }

  function test_clearing_the_selection_empties_project_and_runs() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    var proc = app.runs.snapshotRunner.current
    proc.outText = okReply(["r1"])
    proc.exited(0)
    compare(app.runs.runs.length, 1)
    app.projects.clearSelection()
    compare(app.runs.project, "")
    compare(app.runs.runs.length, 0, "the previous project's runs are gone")
  }

  function test_active_follows_panel_open() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.panelOpen = true
    compare(app.runs.active, true)
    app.panelOpen = false
    compare(app.runs.active, false)
  }

  function test_opening_with_no_project_launches_nothing() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.panelOpen = true
    compare(app.runs.active, true)
    verify(!app.runs.snapshotRunner.current, "no snapshot without a project")
    compare(app.runs.watching, false)
  }

  function test_panel_close_through_app_stops_the_watch() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.panelOpen = true
    var proc = app.runs.snapshotRunner.current
    proc.outText = okReply(["r1"])
    proc.exited(0)
    compare(app.runs.watching, true, "the first good snapshot while open starts the watch")
    var watch = app.runs.watchProc
    verify(watch, "a watch process")
    app.panelOpen = false
    compare(app.runs.watching, false)
    compare(watch.running, false, "closing the panel stops the watch")
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash ./tests/run.sh tst_app_runs`
Expected: the pytest part passes, then `== tests/core/stores/tst_app_runs.qml` reports `FAIL!` lines such as `app.runs exists` / `App composes the run store as app.runs` (App has no `runs` property yet), and the script exits non-zero.

- [ ] **Step 3: Add `panelOpen` to App**

In `core/stores/App.qml`, replace:

```qml
  property string backendDir: ""
```

with:

```qml
  property string backendDir: ""
  property bool panelOpen: false   // the panel is open; Panel.qml binds it to its `opened`
```

- [ ] **Step 4: Compose `runs` in App**

In `core/stores/App.qml`, replace:

```qml
    onBoardRefreshRequested: app.board.fetchBoard()
  }

  readonly property GraphStore graph: GraphStore {
```

with:

```qml
    onBoardRefreshRequested: app.board.fetchBoard()
  }

  // The run store never imports the project or board store: App hands it the
  // selected project's root path (never the project object) and the panel-open
  // flag that starts and stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
  }

  readonly property GraphStore graph: GraphStore {
```

Leave `import QtQml` as the only import.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash ./tests/run.sh tst_app_runs`
Expected: `Totals: 10 passed, 0 failed` for `tst_app_runs.qml` (8 test functions plus initTestCase/cleanupTestCase), no TypeError/ReferenceError/"Unable to assign" lines, exit status 0.

- [ ] **Step 6: Run the store tier to check App's other consumers**

Run: `bash ./tests/run.sh tests/core/stores`
Expected: every `tests/core/stores/tst_*.qml` file reports `0 failed`, no flagged error lines, exit 0.

- [ ] **Step 7: Commit**

```bash
git add tests/core/stores/tst_app_runs.qml core/stores/App.qml
git commit -m "feat(app): compose RunStore as app.runs, wired to root path and panelOpen"
```

---

### Task 2: Panel drives `app.panelOpen` from `opened`

**Files:**
- Modify: `ui/Panel.qml:44`
- Test: `tests/ui/tst_sidebar_nav.qml` (add one case before the final `}` at line 182)

**Interfaces:**
- Consumes: `App.panelOpen: bool` and `App.runs: RunStore` from Task 1; the Panel stub's `property bool opened` (`tests/stubs/qs/Ui/Panel.qml:4`); `tst_sidebar_nav.qml`'s existing `make()` (sets `p.opened = true`).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

In `tests/ui/tst_sidebar_nav.qml`, insert this function right after `test_opening_the_panel_resets_transient_state` (after line 134):

```qml

  // App's panel-open flag is how the run store knows to watch: it must follow
  // the real panel both ways.
  function test_the_panel_open_flag_reaches_the_run_store() {
    var p = make(); if (!p) return
    verify(p.app.runs, "App composes the run store")
    compare(p.opened, true)
    compare(p.app.panelOpen, true)
    compare(p.app.runs.active, true)
    p.opened = false
    compare(p.app.panelOpen, false)
    compare(p.app.runs.active, false)
    p.opened = true
    compare(p.app.runs.active, true)
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash ./tests/run.sh tst_sidebar_nav`
Expected: `FAIL!  : SidebarNav::test_the_panel_open_flag_reaches_the_run_store()` (Task 1 is already applied, so `p.app.runs` exists and the first failing check is the `p.app.panelOpen` compare, `Actual (): false` / `Expected (): true`; the other cases still pass); exit non-zero.

- [ ] **Step 3: Bind `panelOpen` in Panel.qml**

In `ui/Panel.qml`, replace line 44:

```qml
  Core.App { id: appStores; backendDir: root.pluginDir + "core/backend/" }
```

with:

```qml
  Core.App { id: appStores; backendDir: root.pluginDir + "core/backend/"; panelOpen: root.opened }
```

Do not touch `onOpenedChanged` (line 212).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash ./tests/run.sh tst_sidebar_nav`
Expected: `tst_sidebar_nav.qml` reports `0 failed`, no flagged error lines, exit 0.

- [ ] **Step 5: Run the ui tier**

Run: `bash ./tests/run.sh tests/ui`
Expected: every `tests/ui/**/tst_*.qml` reports `0 failed`, no flagged error lines, exit 0.

- [ ] **Step 6: Commit**

```bash
git add tests/ui/tst_sidebar_nav.qml ui/Panel.qml
git commit -m "feat(panel): drive app.panelOpen from the panel's opened state"
```

---

### Task 3: Document the store and refresh RunStore's header comment

**Files:**
- Modify: `docs/architecture.md:68-69` (new entry after the `MilestoneStore.qml` entry, before "Other `ui/` pieces")
- Modify: `core/stores/RunStore.qml:11-12` (header comment only)

**Interfaces:**
- Consumes: the names `app.runs`, `panelOpen`, `project`, `backendDir`, `active` from Tasks 1-2.
- Produces: nothing.

This task changes no behaviour, so it has no new RED test; its gate is the full suite including `tests/architecture`.

- [ ] **Step 1: Add the RunStore entry to the Stores list**

In `docs/architecture.md`, replace:

```markdown
  that outlives a project switch is still recorded truthfully; `jobVisible`
  decides whose panel shows it.

Other `ui/` pieces:
```

with:

```markdown
  that outlives a project switch is still recorded truthfully; `jobVisible`
  decides whose panel shows it.
- `RunStore.qml` the am run monitor's data: one snapshot of the selected
  project's am runs (`runs-snapshot.py`, normalized through `runs.js`), the
  selected run and `amStatus`. While the panel is open it runs `runs-watch.py`
  (250 ms debounce per burst of changes, 10 s liveness re-read while a run is
  running, a `stale` flag 30 s after the last good snapshot, and a 5 s fallback
  poll when the journal has a schema mismatch or is corrupt). It never reaches
  for another store: `App` hands it `project` (the selected project's root
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`).

Other `ui/` pieces:
```

Do not add Ctrl+6 or any shortcut text.

- [ ] **Step 2: Reword RunStore's stale header sentence (comment only)**

In `core/stores/RunStore.qml`, replace:

```qml
// handed to it from outside -- it never reaches for another store. Composing
// it into App (3.3) comes later.
```

with:

```qml
// handed to it from outside -- it never reaches for another store. App
// composes it as `app.runs` and binds `active` to the panel being open.
```

And replace line 18:

```qml
  property bool active: false         // App binds this to "panel open" (3.3)
```

with:

```qml
  property bool active: false         // App binds this to "panel open" (app.panelOpen)
```

No other change to RunStore.qml.

- [ ] **Step 3: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q` (if `python3` has no pytest: `uv run --with pytest python3 -m pytest tests/architecture -q`)
Expected: all passed, 0 failed.

- [ ] **Step 4: Run the full suite**

Run: `bash ./tests/run.sh`
Expected: pytest reports all passed, every `== tests/...tst_*.qml` block reports `0 failed`, no TypeError/ReferenceError/non-existent/"Unable to assign"/"is not a function" lines, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md core/stores/RunStore.qml
git commit -m "docs(architecture): list RunStore and how App wires it"
```
