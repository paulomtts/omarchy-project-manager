# 4.1 Runs and Run detail without a project open — design

Card `62267485`, a subtask of story `63a11d2f`. Parent spec:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below: **parent**).
This subtask lifts the "a project must be selected" gates on the Runs list and Run
detail, and only those. The store side is already done on this branch: `RunStore`
has no project guard for snapshots, controls, logs or the notify setting (commits
`fec03d8`..`82fef13`, including `7b73964` "the notify switch saves to the global settings
with or without a project").

## Goal

With no project selected (`app.projects.selectedProject === null`), the user can reach
the Runs list, open a run, use p / r / c on it, open a toast's run, and flip Notify on
escalation. Every other section, key and chord behaves exactly as it does now.

## Inherited constraints

| constraint | source |
|---|---|
| The sidebar's Runs row is always enabled; `showSection("runs")` works with no project selected | parent L39-40 |
| Lift every project gate on the run surfaces, for Runs and Run detail only: `Navigator.showSection`, `visible` of `RunsScreen` and `RunDetailScreen`, Panel's focus choice, search field and key catcher, `Shortcuts.handleRunKey` (p / r / c), `Panel.openToastRun` | parent L40-44 |
| Every other section stays project-bound | parent L44 |
| The Notify on escalation switch is shown on the Runs screen with no project open too | parent L77-78 |
| Dispatch stays project-bound; the Runs toolbar's Start run works on the open project when one is open and is disabled with the tooltip "Open a project to dispatch" otherwise | parent L83-85 |
| `RunStore.project` is `""` with no project and is no longer a guard for anything about runs | parent L130-133 |
| UI tests: Runs reachable with no project (sidebar, Ctrl+6, toast Open, p / r / c), Start run disabled without a project, the notify switch with no project | parent L190-193 |
| Breadcrumbs read `Runs > <run short id>` | card |
| `docs/architecture.md` layering; `tests/architecture` passes (no store imports in `ui/screens` / `ui/components`, no duplicated components, icon glyph rules) | card |
| Docstrings and comments state the contract only, no narrative | card |
| Tests first; `bash tests/run.sh` green | card |

## Terms

- **No project**: `app.projects.selectedProject` is null (an empty registry, or a test
  that sets it to null).
- **Run views**: `nav.viewMode` `"runs"` (the list) and `"run"` (Run detail).
- **Bound sections**: Board, Graph, Documents, Memories, Issues (and their detail views
  `entry`, `document`, `memory`, `issue`).

## Behavior

### B1. Sidebar (`ui/components/Sidebar.qml`)

1. `navRuns` is enabled whether or not `selectedProject` is set; a click emits
   `sectionChosen("runs")`.
2. `navBoard`, `navGraph`, `navDocuments`, `navMemories`, `navIssues` and the delete row
   keep their `hasProject` gate unchanged: disabled with no project, and a click emits
   nothing.
3. The Runs attention count shows with no project exactly as with one.

### B2. Navigator (`ui/Navigator.qml`)

1. `showSection("runs")` with no project switches to the Runs list: `viewMode` becomes
   `"runs"`, the search resets, the dropdown closes, the focus is re-chosen, the list
   scrolls to the top — the same steps as with a project.
2. `showSection(name)` for any other name with no project does nothing (unchanged).
3. The modal and memory-edit guards still block `showSection("runs")` with or without a
   project (delete confirmation, memory delete, new memory, new milestone, archive, an
   unsaved memory edit).
4. `crumbs` with no project:
   - on `"runs"`: `[{label: "Runs", clickable: false}]`;
   - on `"run"`: `[{label: "Runs", clickable: true}, {label: Runs.shortId({id: selectedRunId}), clickable: false}]`;
   - on every other view: `[{label: "Project Manager", clickable: false}]` (unchanged).
   With a project, crumbs are unchanged.
5. `openRun(id, "runs")` and Back (Escape, Left arrow, the `Runs` crumb) from Run detail
   to the list work with no project exactly as with one.
6. `currentList()` on `"runs"` is `runs.filteredRuns` with or without a project
   (already true; asserted, not changed).

### B3. Screens

1. `RunsScreen.visible` is `viewMode === "runs"`; `RunDetailScreen.visible` is
   `viewMode === "run"`. Neither reads `selectedProject`.
2. The Notify on escalation row (`runsNotifyRow`, `runsNotifyToggle`, `runsNotifyLabel`)
   is visible on the Runs list with no project, and toggling it calls
   `runs.setNotifyOnEscalation(!runs.notifyOnEscalation)` (the store writes the global
   setting; `7b73964`). Its comment stops calling the setting "the project's".
3. Nothing else on either screen changes. In particular the empty-list text
   ("No runs for this project yet.") and grouping are not this card's (see Out of scope).

### B4. Panel (`ui/Panel.qml`)

1. **Focus**: with no project, on `"runs"` the focus item is `searchField`; on `"run"`
   it is `keyCatcher` (as with a project). With no project on any other view it stays
   `keyCatcher`. Modal and dropdown precedence is unchanged.
2. **Search field**: visible on `"runs"` whether or not a project is selected, with its
   placeholder "Search runs…"; on the bound sections it stays hidden with no project.
   Typing filters `runs.filteredRuns` and resets the cursor as today.
3. **"No projects registered with brd." placeholder**: hidden on the run views; with no
   project on any other view it shows as today (when `projects.loadError === ""`).
4. **Start run** (`startRunButton`): visible on `"runs"` with or without a project.
   - No project: disabled; `tooltipText` is exactly `"Open a project to dispatch"`. This
     check wins over the `am`-missing one.
   - A project and `runs.amStatus === "missing"`: disabled, tooltip
     `"am is not installed or not on PATH"` (unchanged).
   - A project and `am` present: enabled, tooltip `"Start an am run"`, a click opens the
     dispatch dialog on the whole board of the open project (unchanged).
   A click on the disabled button opens nothing.
5. **Toast Open** (`openToastRun(key, runId)`) with no project: the toast is dismissed,
   the panel shows the Runs list, then Run detail of that run; Back returns to the Runs
   list. A run no longer in the snapshot flashes "This run is no longer in the snapshot"
   on the Runs list (as with a project).
6. Every other `selectedProject` use in Panel (sidebar props, delete, Graph / Board
   toolbars and their visibility) is unchanged.

### B5. Shortcuts (`ui/Shortcuts.qml`)

1. `handleRunKey` no longer checks the project. With no project on `"runs"` (empty
   search) and `"run"`, bare p / r / c act on the cursor run / the open run exactly as with
   a project: a refusal flashes its reason, `c` opens the cancel dialog, p / r send the
   control (a pending entry for that run). Every other rule (modifiers, modal, dropdown,
   non-empty search, no target run, other views) is unchanged.
2. Ctrl+6 with no project opens the Runs list (via B2.1).
3. Ctrl+1..5 with no project still do nothing to `viewMode` (via B2.2) and return true
   as today.
4. `handleDispatchKey` (d) keeps its project check.
5. The comment above `handleRunKey` and the test comment "A run key needs a project" are
   updated to state the new contract.

### Error paths and edges

| case | behavior |
|---|---|
| no project, Runs list empty | the list's existing empty state; Enter and p / r / c do nothing (no target) |
| no project, `am` missing | the Runs screen's `missing` state as today; Start run disabled with "Open a project to dispatch" |
| no project, a modal open (cancel dialog) | Ctrl+6 and p / r / c are swallowed as today |
| a project is cleared while on a run view (`ProjectStore.cleared`) | unchanged: `App.qml` sets `viewMode` to `"board"`; this card does not change that |
| a project is selected while on a run view (`ProjectStore.selected`) | unchanged: Board opens (`App.qml`) |
| no project, Back from Run detail | the Runs list, cursor kept as `openRun` recorded it |

## Out of scope

- Grouped list, project filter chips, group headers, **Open project** action, the
  "No projects registered" empty state of the Runs list and its "for this project"
  wording (parent L45-64, L166): sibling cards of this story.
- Mounting `RunIndicator`, project names on toasts (parent L69-72): sibling cards.
- Any `RunStore` / backend change (done earlier on this branch).
- The behavior of `ProjectStore.selected` / `cleared` on the view mode.
- Dispatch from the board or a card with no project (stays project-bound).
- Docs (`docs/architecture.md`, README): the story's docs subtask.

## Tests (write first)

All QML tests run under `qmltestrunner` through `bash tests/run.sh <filter>`.

### `tests/ui/tst_sidebar.qml` — component tier (a bare `Sidebar`; the gate is a property of the component)

- S1 `test_the_runs_row_is_enabled_without_a_project` (replaces
  `test_the_runs_row_is_disabled_without_a_project`): `selectedProject = null`;
  `navRuns.enabled === true`; a click emits `sectionChosen("runs")` once.
- S2 `test_without_a_project_only_the_runs_row_is_enabled`: `navBoard`, `navGraph`,
  `navDocuments`, `navMemories`, `navIssues` disabled; clicking each emits nothing.

### `tests/ui/tst_sidebar_nav.qml` — UI flow tier (a real `Panel`: the click must travel sidebar → navigator → screens)

- N1 `test_clicking_the_runs_row_with_no_project_opens_the_runs_section`: no project;
  click `navRuns`; `viewMode === "runs"`, `runsView.visible`, `searchField.visible`.
- N2 `test_focus_item_with_no_project`: no project; focus is `keyCatcher` on the board;
  after `showSection("runs")` it is `searchField`; after opening a run it is
  `keyCatcher`.
- N3 `test_with_no_project_the_bound_rows_stay_disabled_and_inert`: clicking each bound
  row leaves `viewMode` unchanged; `showSection` of each bound name leaves it unchanged.

### `tests/ui/tst_runs_flow.qml` — UI flow tier (whole-panel behavior across store, navigator, screens and toolbar)

A `makeNoProject()` helper: `make()` then `p.app.projects.selectedProject = null`, with
the runs set after the clear.

- F1 `test_with_no_project_ctrl_6_opens_runs_with_search_and_no_placeholder`: Ctrl+6;
  `viewMode "runs"`, crumbs `"Runs"`, `runsView.visible`, `searchField` visible and
  focused with "Search runs…", the "No projects registered with brd." text not visible.
- F2 `test_with_no_project_a_run_opens_and_back_returns`: Enter on the cursor run;
  `runDetailView` visible, crumbs `"Runs > <shortId>"`; Escape returns to `"runs"`.
- F3 `test_with_no_project_the_search_filters_runs`: typing in `searchField` narrows
  `navigator.currentList()`.
- F4 `test_with_no_project_toast_open_shows_the_run`: from the board view, a toast's
  Open lands on Run detail of that run; Back lands on the Runs list; a toast for a run not
  in the snapshot flashes "This run is no longer in the snapshot".
- F5 `test_with_no_project_the_notify_switch_shows_and_toggles`: `runsNotifyRow` visible;
  clicking `runsNotifyToggle` flips `runs.notifyOnEscalation` and sets
  `runs.settingsSaveRunner.sent` to the new value (the `set-global-settings` request).
- F6 `test_start_run_without_a_project_is_disabled_with_why`: `startRunButton` visible,
  `enabled === false`, `tooltipText === "Open a project to dispatch"`, also with
  `amStatus "missing"`; a click opens no dispatch (`dispatchOpen` false).
- F7 `test_start_run_with_a_project_opens_the_dispatch`: with `pA` selected and `am`
  present, enabled, tooltip "Start an am run" (an existing test may already cover the
  click; extend it rather than duplicate).
- F8 `test_with_no_project_the_bound_sections_stay_shut`: Ctrl+1..5 leave `viewMode`
  unchanged; on the board view with no project the placeholder shows and the search field
  is hidden.

### `tests/ui/tst_shortcuts.qml` — UI flow tier (key routing through `Shortcuts` against real stores)

- K1 `test_without_a_project_the_run_keys_act_on_the_cursor_run` (replaces
  `test_without_a_project_the_run_keys_are_left_alone`): no project, `"runs"`, empty
  search; `p` returns true and leaves a pending pause for the cursor run; `c` returns true
  and opens the cancel dialog; a refused key returns true and flashes its reason.
- K2 `test_without_a_project_the_run_keys_act_on_the_open_run`: on `"run"`, `p` targets
  `selectedRunId`.
- K3 `test_ctrl_6_opens_runs_without_a_project_and_ctrl_1_to_5_do_not`.
- K4 the existing `test_d_is_left_alone` `no-project` row stays and passes (d stays
  project-bound).

### Existing tests that assert the old gate (change them in the same commit as the code)

- `tests/ui/screens/tst_runs_screen.qml` `test_the_screen_is_hidden_outside_its_section`
  and `tests/ui/screens/tst_run_detail_screen.qml`
  `test_the_screen_is_hidden_outside_the_run_view`: the closing "`selectedProject: null` →
  `screen.visible === false`" step becomes "→ still `true`"; the view-mode steps stay.
- `tests/ui/tst_panel_toolbar.qml` `test_start_run_shows_only_on_the_runs_list_of_a_project`
  (L317-319): the closing "no project → `button.visible === false`" becomes visible,
  disabled, tooltip `"Open a project to dispatch"`. Rename the test (it no longer reads
  "of a project").

### `tests/architecture` — pytest tier (layering and glyph rules; run by `tests/run.sh`)

No new test; must stay green (no store import added to a screen or component).

## Acceptance

`bash tests/run.sh` is green; the tests above exist and fail before the change; with no
project only the Runs row of the sidebar is enabled.
