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
