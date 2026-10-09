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

---

# 4.1 Runs and Run detail without a project open Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With no project selected, the Runs list and Run detail are reachable (sidebar, Ctrl+6, toast Open), p / r / c act on runs, and the Notify on escalation switch works; every other section stays project-bound and Start run is disabled with "Open a project to dispatch".

**Architecture:** Only UI files change. `Sidebar.qml` drops the `hasProject` gate from the Runs row. `RunsScreen.qml` / `RunDetailScreen.qml` drop `selectedProject` from `visible`. `Navigator.qml` lets `showSection("runs")` through with no project and builds `Runs` / `Runs > <short id>` crumbs on the run views. `Panel.qml` changes four bindings (focus item, search field, the "No projects registered" placeholder, Start run). `Shortcuts.qml` drops the project check from `handleRunKey`. No store, backend or domain file changes.

**Tech Stack:** QML (Qt 6, Quickshell stubs under `tests/stubs`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-1-runs-and-run-detail-62267485.md` (prepended above).

## Global Constraints

- Only Runs (`"runs"`) and Run detail (`"run"`) lose their project gate. Board, Graph, Documents, Memories, Issues (and `entry`, `document`, `memory`, `issue`) stay project-bound.
- Dispatch stays project-bound: `handleDispatchKey` keeps its project check; Start run is disabled with no project.
- Start run tooltip strings, verbatim: `"Open a project to dispatch"` (no project; wins over am missing), `"am is not installed or not on PATH"`, `"Start an am run"`.
- Breadcrumbs with no project: `"runs"` → `[{label: "Runs", clickable: false}]`; `"run"` → `[{label: "Runs", clickable: true}, {label: Runs.shortId({id: selectedRunId}), clickable: false}]`; any other view → `[{label: "Project Manager", clickable: false}]`.
- No change to `core/` (stores, domain, backend). `App.qml`'s `selected` / `cleared` handlers are untouched.
- `docs/architecture.md` layering: no store import added to `ui/screens` or `ui/components`; `tests/architecture` stays green. No new glyphs.
- Docstrings and comments state the contract only, no narrative.
- Tests first. Gate: `bash tests/run.sh` green.

## Review Focus

1. **Back from Run detail with no project by the Left arrow and the `Runs` crumb**, not only Escape: each lands on the Runs list. Test in Task 3 (`test_with_no_project_a_run_opens_and_back_returns`, its last lines).
2. **No project, an empty Runs list**: Enter does nothing and p / r / c return false with no flash, no dialog, no pending request. Test in Task 5 (`test_without_a_project_an_empty_runs_list_leaves_the_keys_alone`).
3. **No project, the cancel dialog open on Run detail**: Ctrl+6 and `p` are swallowed. Test in Task 5 (`test_without_a_project_the_cancel_dialog_swallows_ctrl_6_and_the_run_keys`).
4. **Choosing a project while on Run detail with no project**: the Board opens and Start run is hidden (App's `selected` handler, unchanged). Test in Task 3 (`test_with_no_project_choosing_a_project_on_a_run_opens_the_board`).
5. **Run detail with no project shows neither the search field nor the "No projects registered with brd." placeholder**, and focus is on the key catcher so Escape works. Test in Task 3 (`test_with_no_project_a_run_opens_and_back_returns`).

Tests for 2, 3 and 4 pass before the change too: they are guards that the lifted gates did not open anything else. Each step says which tests are expected to fail first.

---

## File Structure

- Modify `ui/components/Sidebar.qml` — the `navRuns` row (`enabled`) and its comment.
- Modify `ui/screens/RunsScreen.qml` — `visible` (line 35) and the Notify row's comment (117-118).
- Modify `ui/screens/RunDetailScreen.qml` — `visible` (line 40).
- Modify `ui/Navigator.qml` — `buildCrumbs()` (first lines) and `showSection()` (first line), each with a comment.
- Modify `ui/Panel.qml` — `focusItem` (line 187), the Start run button (531-540), `searchField.visible` (566), the "No projects registered with brd." text (631-637: gains `objectName: "noProjectsText"`).
- Modify `ui/Shortcuts.qml` — `handleRunKey` (line 66) and the comment above it (54-60).
- Tests:
  - `tests/ui/tst_sidebar.qml` — replace `test_the_runs_row_is_disabled_without_a_project`, add one test.
  - `tests/ui/screens/tst_runs_screen.qml` — `test_the_screen_is_hidden_outside_its_section`.
  - `tests/ui/screens/tst_run_detail_screen.qml` — `test_the_screen_is_hidden_outside_the_run_view`.
  - `tests/ui/tst_sidebar_nav.qml` — three tests.
  - `tests/ui/tst_runs_flow.qml` — a `sampleRuns()` / `makeNoProject()` helper, `withToast` gains a `noProject` argument, new tests.
  - `tests/ui/tst_shortcuts.qml` — replace `test_without_a_project_the_run_keys_are_left_alone`, add tests.
  - `tests/ui/tst_panel_toolbar.qml` — rename and change `test_start_run_shows_only_on_the_runs_list_of_a_project`.
  - `tests/ui/tst_dispatch_flow.qml` — two asserts added to `test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets` (spec F7).

Line numbers are from the starting commit (`82fef13`); find each edit by the quoted text.

## How to run the tests

- **One QML file, fast** (no pytest), from the worktree root:

  ```bash
  QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml 2>&1 | grep -E "^(FAIL|PASS|Totals)|Loc|Actual|Expected|TypeError|ReferenceError"
  ```

  To run single functions, append `<CaseName>::<test name>` after the `-input <file>` argument. Case names: `Sidebar` (`tst_sidebar.qml`), `SidebarNav` (`tst_sidebar_nav.qml`), `RunsFlow` (`tst_runs_flow.qml`), `Shortcuts` (`tst_shortcuts.qml`), `PanelToolbar` (`tst_panel_toolbar.qml`), `DispatchFlow` (`tst_dispatch_flow.qml`), `RunsScreen` (`screens/tst_runs_screen.qml`), `RunDetailScreen` (`screens/tst_run_detail_screen.qml`). Panel-level files print many `QWARN ... Cannot read property 'width' of null` lines: pre-existing, ignored by `tests/run.sh`.
- **One file through the real gate:** `timeout 900 bash tests/run.sh tst_runs_flow` (the argument is a substring of the test path; pytest runs first, about 2 min).
- **Full gate:** `timeout 1200 bash tests/run.sh` — pytest (including `tests/architecture`), then every `tst_*.qml`; non-zero exit on any failure or any `TypeError` / `ReferenceError` in the output.

Facts the tests rely on (all already in the repo):

- `tests/helpers/find.js` `H.find(item, objectName)` searches children, data and Flickable content.
- `Runs.shortId({id})` is `"…" + id.slice(-8)`: `run-0000000000a1` → `"…000000a1"`.
- Setting `app.projects.selectedProject = null` directly does **not** emit `ProjectStore.cleared`, so `viewMode` is untouched; the registry still lists the project, so `RunStore.projectRoots` keeps its root and snapshots still work. `RunStore.project` becomes `""`.
- `RunStore.openDispatch` already refuses with `project === ""`.
- The `ToggleSwitch` stub (`tests/stubs/qs/Ui/ToggleSwitch.qml`) has no size and no mouse area: tests emit `toggled()` directly, as `tst_runs_screen.qml` does.
- The `Button` stub's `MouseArea` is `enabled: parent.enabled`, so `mouseClick` on a disabled `ActionButton` emits nothing.

---

### Task 1: The sidebar's Runs row is enabled without a project

**Files:**
- Modify: `ui/components/Sidebar.qml` (the `navRuns` `NavRow` and the two comment lines above it)
- Test: `tests/ui/tst_sidebar.qml`

**Interfaces:**
- Consumes: nothing new.
- Produces: `navRuns.enabled === true` whatever `selectedProject` is; a click emits `sectionChosen("runs")`. Task 3's `tst_sidebar_nav` tests click it inside a real Panel.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_sidebar.qml`, replace the whole function

```qml
  function test_the_runs_row_is_disabled_without_a_project() {
    var sb = make()
    sb.selectedProject = null
    compare(find(sb, "navRuns").enabled, false)
    click(find(sb, "navRuns"))
    compare(sectionSpy.count, 0)
  }
```

with

```qml
  function test_the_runs_row_is_enabled_without_a_project() {
    var sb = make()
    sb.selectedProject = null
    compare(find(sb, "navRuns").enabled, true)
    click(find(sb, "navRuns"))
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "runs")
  }

  function test_without_a_project_only_the_runs_row_is_enabled() {
    var sb = make()
    sb.selectedProject = null
    var bound = ["navBoard", "navGraph", "navDocuments", "navMemories", "navIssues"]
    for (var i = 0; i < bound.length; i++) {
      compare(find(sb, bound[i]).enabled, false, bound[i])
      click(find(sb, bound[i]))
    }
    compare(sectionSpy.count, 0, "no bound row emits a section")
    compare(find(sb, "deleteButton").enabled, false)
    compare(find(sb, "navRuns").enabled, true)
  }
```

- [ ] **Step 2: Run them to verify the first fails**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_sidebar.qml Sidebar::test_the_runs_row_is_enabled_without_a_project Sidebar::test_without_a_project_only_the_runs_row_is_enabled 2>&1 | grep -E "^(FAIL|PASS|Totals)|Actual|Expected"`
Expected: `FAIL!  : Sidebar::test_the_runs_row_is_enabled_without_a_project()` (Actual `false`, Expected `true`) and `test_without_a_project_only_the_runs_row_is_enabled` FAILs on its last line (`navRuns` enabled is `false`).

- [ ] **Step 3: Implement**

In `ui/components/Sidebar.qml`, replace

```qml
    // Appended after Issues, so Runs is Ctrl+6. Its glyph is the Nerd Font
    // play symbol (U+F04B); its count is the runs that need attention.
    NavRow { objectName: "navRuns"; label: "Runs"; iconText: ""; section: "runs"; enabled: sidebar.hasProject; countText: sidebar.runsAttentionText }
```

with

```qml
    // Appended after Issues, so Runs is Ctrl+6. Its glyph is the Nerd Font
    // play symbol (U+F04B); its count is the runs that need attention. The
    // one row enabled with no project: runs are listed across every project.
    NavRow { objectName: "navRuns"; label: "Runs"; iconText: ""; section: "runs"; countText: sidebar.runsAttentionText }
```

- [ ] **Step 4: Run the file to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_sidebar.qml 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"`
Expected: `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add ui/components/Sidebar.qml tests/ui/tst_sidebar.qml
git commit -m "feat(sidebar): the Runs row is enabled without a project"
```

---

### Task 2: Runs and Run detail screens show without a project

**Files:**
- Modify: `ui/screens/RunsScreen.qml:35` (`visible`), `:117-118` (Notify row comment)
- Modify: `ui/screens/RunDetailScreen.qml:40` (`visible`)
- Test: `tests/ui/screens/tst_runs_screen.qml` (`test_the_screen_is_hidden_outside_its_section`), `tests/ui/screens/tst_run_detail_screen.qml` (`test_the_screen_is_hidden_outside_the_run_view`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `RunsScreen.visible === (app.nav.viewMode === "runs")`, `RunDetailScreen.visible === (app.nav.viewMode === "run")`. Task 3's Panel tests read `runsView.visible`, `runDetailView.visible` and `runsNotifyRow.visible`.

- [ ] **Step 1: Change the tests that assert the old gate**

In `tests/ui/screens/tst_runs_screen.qml`, replace

```qml
  function test_the_screen_is_hidden_outside_its_section() {
    var s = make(sample()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "run"
    compare(s.screen.visible, false)
    s.nav.viewMode = "runs"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, false)
  }
```

with

```qml
  function test_the_screen_is_hidden_outside_its_section() {
    var s = make(sample()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "run"
    compare(s.screen.visible, false)
    s.nav.viewMode = "runs"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, true, "no project: the Runs list still shows")
    compare(H.find(s.screen, "runsNotifyRow").visible, true, "and so does the notify switch")
  }
```

In `tests/ui/screens/tst_run_detail_screen.qml`, replace

```qml
    s.nav.viewMode = "run"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, false)
  }
```

with

```qml
    s.nav.viewMode = "run"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, true, "no project: Run detail still shows")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `for f in tests/ui/screens/tst_runs_screen.qml tests/ui/screens/tst_run_detail_screen.qml; do QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input $f 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"; done`
Expected: `FAIL!  : RunsScreen::test_the_screen_is_hidden_outside_its_section()` and `FAIL!  : RunDetailScreen::test_the_screen_is_hidden_outside_the_run_view()`, each Actual `false`, Expected `true`; everything else passes.

- [ ] **Step 3: Implement**

In `ui/screens/RunsScreen.qml` replace

```qml
  visible: screen.app.nav.viewMode === "runs" && !!screen.app.projects.selectedProject
```

with

```qml
  visible: screen.app.nav.viewMode === "runs"
```

and replace

```qml
  // The project's Notify on escalation setting: a desktop notification for
  // every run toast. Shown even while am is missing -- it is the project's.
```

with

```qml
  // The global Notify on escalation setting: a desktop notification for
  // every run toast. Shown with or without a project, and while am is missing.
```

In `ui/screens/RunDetailScreen.qml` replace

```qml
  visible: screen.app.nav.viewMode === "run" && !!screen.app.projects.selectedProject
```

with

```qml
  visible: screen.app.nav.viewMode === "run"
```

- [ ] **Step 4: Run them to verify they pass**

Run: `for f in tests/ui/screens/tst_runs_screen.qml tests/ui/screens/tst_run_detail_screen.qml; do QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input $f 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"; done`
Expected: both `Totals: N passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunsScreen.qml ui/screens/RunDetailScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(runs-screens): Runs and Run detail show without a project"
```

---

### Task 3: Navigator and Panel open the run views without a project

**Files:**
- Modify: `ui/Navigator.qml` — `buildCrumbs()` and `showSection()`
- Modify: `ui/Panel.qml` — `focusItem` (line 187), `searchField.visible` (566), the "No projects registered with brd." `UI.ThemedText` (631-637)
- Test: `tests/ui/tst_sidebar_nav.qml`, `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_shortcuts.qml`

**Interfaces:**
- Consumes: Task 1 (`navRuns` enabled), Task 2 (`runsView` / `runDetailView` / `runsNotifyRow` visibility follows `viewMode` only).
- Produces:
  - `navi.showSection("runs")` works with no project; any other name with no project returns early.
  - `navi.crumbs` per the Global Constraints.
  - `Panel.focusItem` is `searchField` on `"runs"` with or without a project.
  - `searchField.visible` is true on `"runs"` with or without a project.
  - A new `objectName: "noProjectsText"` on the placeholder; hidden on `"runs"` and `"run"`.
  - In `tst_runs_flow.qml`: `sampleRuns()`, `makeNoProject()`, `withToast(view, noProject)` — Task 4 uses `makeNoProject()`.

- [ ] **Step 1: Write the failing tests in `tests/ui/tst_sidebar_nav.qml`**

Append these three functions before the closing `}` of the `TestCase` (after `test_clicking_the_runs_row_opens_the_runs_section`):

```qml
  // ---- no project (4.1): Runs is the one section that needs none

  function aRun(id) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "alpha", status: "started", started_at: "",
             lease: null, rows: [], tree: { stories: [], subtasks: [] }, project: { root: "/home/u/a", name: "alpha" } }
  }

  function test_clicking_the_runs_row_with_no_project_opens_the_runs_section() {
    var p = make(); if (!p) return
    compare(p.app.projects.selectedProject, null)
    var row = H.find(p, "navRuns")
    compare(row.enabled, true)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.section, "runs")
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    compare(H.find(p, "searchField").visible, true)
  }

  function test_focus_item_with_no_project() {
    var p = make(); if (!p) return
    compare(p.app.projects.selectedProject, null)
    compare(p.app.nav.viewMode, "board")
    compare(p.focusItem.objectName, "keyCatcher")
    p.navigator.showSection("runs")
    compare(p.focusItem.objectName, "searchField")
    p.app.runs.runs = [aRun("run-0000000000a1")]
    p.navigator.openRun("run-0000000000a1", "runs")
    compare(p.app.nav.viewMode, "run")
    compare(p.focusItem.objectName, "keyCatcher")
  }

  function test_with_no_project_the_bound_rows_stay_disabled_and_inert() {
    var p = make(); if (!p) return
    compare(p.app.projects.selectedProject, null)
    p.navigator.showSection("runs")
    compare(p.app.nav.viewMode, "runs")
    var rows = ["navBoard", "navGraph", "navDocuments", "navMemories", "navIssues"]
    for (var i = 0; i < rows.length; i++) {
      var row = H.find(p, rows[i])
      compare(row.enabled, false, rows[i])
      mouseClick(row, row.width / 2, row.height / 2)
      compare(p.app.nav.viewMode, "runs", rows[i])
    }
    var names = ["board", "graph", "documents", "memories", "issues"]
    for (var j = 0; j < names.length; j++) {
      p.navigator.showSection(names[j])
      compare(p.app.nav.viewMode, "runs", names[j])
    }
  }
```

- [ ] **Step 2: Write the failing tests in `tests/ui/tst_runs_flow.qml`**

2a. Add the domain import under the existing imports:

```qml
import "../helpers/amFixtures.js" as F
import "../../core/domain/runs.js" as Runs
```

(the first line already exists; add only the second).

2b. In `make()`, replace

```qml
    p.app.runs.runs = [run("run-0000000000a1", "started", true, "alpha"),
                       run("run-0000000000b2", "escalated", null, "beta"),
                       run("run-0000000000c3", "started", false, "gamma"),
                       run("run-0000000000d4", "stopped", null, "delta")]
    return p
  }
```

with

```qml
    p.app.runs.runs = sampleRuns()
    return p
  }

  function sampleRuns() {
    return [run("run-0000000000a1", "started", true, "alpha"),
            run("run-0000000000b2", "escalated", null, "beta"),
            run("run-0000000000c3", "started", false, "gamma"),
            run("run-0000000000d4", "stopped", null, "delta")]
  }

  // make() with no project selected. The registry still lists pA, so the run
  // store keeps its root; the runs are set again after the clear.
  function makeNoProject() {
    var p = make(); if (!p) return null
    p.app.projects.selectedProject = null
    p.app.runs.runs = sampleRuns()
    return p
  }
```

2c. Replace the head of `withToast`

```qml
  function withToast(view) {
    var p = make(); if (!p) return null
```

with

```qml
  function withToast(view, noProject) {
    var p = noProject ? makeNoProject() : make(); if (!p) return null
```

2d. Append before the closing `}` of the `TestCase` (after `test_open_on_a_toast_whose_run_left_the_snapshot_flashes_why`):

```qml
  // ---- no project (4.1)

  // F1
  function test_with_no_project_ctrl_6_opens_runs_with_search_and_no_placeholder() {
    var p = makeNoProject(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    compare(p.app.nav.viewMode, "runs")
    compare(labels(p.navigator.crumbs), "Runs")
    compare(p.navigator.crumbs[0].clickable, false)
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    var field = H.find(p, "searchField")
    compare(field.visible, true)
    compare(String(field.placeholderText), "Search runs…")
    compare(p.focusItem.objectName, "searchField")
    compare(H.find(p, "noProjectsText").visible, false)
    compare(p.navigator.currentList().length, 4, "currentList() is the run list")
  }

  // F2 (and Review Focus 1, 5)
  function test_with_no_project_a_run_opens_and_back_returns() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    var id = p.navigator.currentList()[1].id
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, id)
    compare(labels(p.navigator.crumbs), "Runs > " + Runs.shortId({ id: id }))
    compare(p.navigator.crumbs[0].clickable, true)
    compare(p.navigator.crumbs[1].clickable, false)
    wait(50)
    compare(H.find(p, "runDetailView").visible, true)
    compare(H.find(p, "searchField").visible, false)
    compare(H.find(p, "noProjectsText").visible, false)
    compare(p.focusItem.objectName, "keyCatcher")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.cursorIndex, 1, "back on the row it left")
    compare(p.app.runs.selectedRunId, "")
    p.navigator.openRun(id, "runs")
    p.shortcuts.handleMove(-1, 0)
    compare(p.app.nav.viewMode, "runs", "the Left arrow goes back")
    p.navigator.openRun(id, "runs")
    p.navigator.activateCrumb(0)
    compare(p.app.nav.viewMode, "runs", "the Runs crumb goes back")
  }

  // F3
  function test_with_no_project_the_search_filters_runs() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    compare(p.navigator.currentList().length, 4)
    var field = H.find(p, "searchField")
    p.app.nav.cursorIndex = 2
    field.text = "gamma"
    compare(ids(p.navigator.currentList()), "run-0000000000c3")
    compare(p.app.nav.cursorIndex, 0, "typing resets the cursor")
    field.text = ""
    compare(p.navigator.currentList().length, 4)
  }

  // F4
  function test_with_no_project_toast_open_shows_the_run() {
    var p = withToast("board", true); if (!p) return
    compare(p.app.projects.selectedProject, null)
    compare(p.app.nav.viewMode, "board")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.runs.toasts.length, 0, "Open dismisses its toast")
    wait(50)
    compare(H.find(p, "runDetailView").visible, true)
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    // alpha dies, then leaves the snapshot: its toast outlives its row.
    feed(p, [snapEntry("run-0000000000a1", "started", false, "alpha"), snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runs.toasts.length, 1)
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runs.toasts.length, 1)
    p.app.nav.viewMode = "board"
    wait(50)
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.runs.toasts.length, 0)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.selectedRunId, "")
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    compare(H.find(p, "runsFooter").text, "This run is no longer in the snapshot")
  }

  // F5
  function test_with_no_project_the_notify_switch_shows_and_toggles() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    compare(H.find(p, "runsNotifyRow").visible, true)
    var was = p.app.runs.notifyOnEscalation
    H.find(p, "runsNotifyToggle").toggled()
    compare(p.app.runs.notifyOnEscalation, !was)
    compare(p.app.runs.settingsSaveRunner.sent, !was, "the set-global-settings request carries the new value")
    reply(p.app.runs.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
  }

  // F8
  function test_with_no_project_the_bound_sections_stay_shut() {
    var p = makeNoProject(); if (!p) return
    wait(50)
    compare(p.app.nav.viewMode, "board")
    compare(H.find(p, "noProjectsText").visible, true)
    compare(H.find(p, "searchField").visible, false)
    compare(p.focusItem.objectName, "keyCatcher")
    compare(labels(p.navigator.crumbs), "Project Manager")
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    compare(p.app.nav.viewMode, "runs")
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5]
    for (var i = 0; i < digits.length; i++) {
      compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: digits[i] }), true)
      compare(p.app.nav.viewMode, "runs", "Ctrl+" + (i + 1))
    }
  }

  // Review Focus 4: App's `selected` handler still opens the Board.
  function test_with_no_project_choosing_a_project_on_a_run_opens_the_board() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000a1", "runs")
    compare(p.app.nav.viewMode, "run")
    p.navigator.chooseProject(tc.pA)
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.runs.settingsLoadRunner.cancel()
    p.app.runs.runSettingsRunner.cancel()
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    compare(p.app.nav.viewMode, "board")
    compare(labels(p.navigator.crumbs), "Board")
    wait(50)
    compare(H.find(p, "startRunButton").visible, false)
    compare(H.find(p, "noProjectsText").visible, false)
  }
```

- [ ] **Step 3: Write the failing test in `tests/ui/tst_shortcuts.qml`**

Insert after `test_ctrl_6_is_ignored_while_a_delete_is_being_confirmed`:

```qml
  // K3
  function test_ctrl_6_opens_runs_without_a_project_and_ctrl_1_to_5_do_not() {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    s.app.projects.selectedProject = null
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5]
    for (var i = 0; i < digits.length; i++) {
      compare(s.handleGlobalKey(ctrl(digits[i])), true, "Ctrl+" + (i + 1) + " is still handled")
      compare(s.app.nav.viewMode, "board", "Ctrl+" + (i + 1))
    }
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), true)
    compare(s.app.nav.viewMode, "runs")
    for (var j = 0; j < digits.length; j++) {
      compare(s.handleGlobalKey(ctrl(digits[j])), true)
      compare(s.app.nav.viewMode, "runs", "Ctrl+" + (j + 1) + " from Runs")
    }
  }
```

- [ ] **Step 4: Run them to verify they fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_sidebar_nav.qml 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected|TypeError"
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_shortcuts.qml Shortcuts::test_ctrl_6_opens_runs_without_a_project_and_ctrl_1_to_5_do_not 2>&1 | grep -E "^(FAIL|PASS|Totals)|Actual|Expected"
```

Expected FAILs (everything else passes, including all pre-existing tests in these files):
- `SidebarNav::test_clicking_the_runs_row_with_no_project_opens_the_runs_section` (viewMode `"board"`, expected `"runs"`)
- `SidebarNav::test_focus_item_with_no_project` (focus `keyCatcher`, expected `searchField`)
- `SidebarNav::test_with_no_project_the_bound_rows_stay_disabled_and_inert` (viewMode `"board"`)
- `RunsFlow::test_with_no_project_ctrl_6_opens_runs_with_search_and_no_placeholder`
- `RunsFlow::test_with_no_project_a_run_opens_and_back_returns`
- `RunsFlow::test_with_no_project_the_search_filters_runs`
- `RunsFlow::test_with_no_project_toast_open_shows_the_run` (at the second `viewMode` `"runs"` compare, after the second Open: it stays `"board"`)
- `RunsFlow::test_with_no_project_the_notify_switch_shows_and_toggles` (`runsNotifyRow` not visible)
- `RunsFlow::test_with_no_project_the_bound_sections_stay_shut` (`noProjectsText` not found: a `TypeError` on `null`)
- `Shortcuts::test_ctrl_6_opens_runs_without_a_project_and_ctrl_1_to_5_do_not`

`RunsFlow::test_with_no_project_choosing_a_project_on_a_run_opens_the_board` already passes (a guard).

- [ ] **Step 5: Implement `Navigator.qml`**

In `ui/Navigator.qml` `buildCrumbs()`, replace

```qml
  function buildCrumbs() {
    if (!navi.app) return []
    if (!navi.app.projects.selectedProject) return [{ label: "Project Manager", clickable: false }]
    var mode = navi.app.nav.viewMode
    var section = { label: navi.app.nav.sectionTitle,
```

with

```qml
  // With no project the run views keep their trail (Runs, Runs > run); every
  // other view is just the panel's name.
  function buildCrumbs() {
    if (!navi.app) return []
    var mode = navi.app.nav.viewMode
    if (!navi.app.projects.selectedProject && mode !== "runs" && mode !== "run")
      return [{ label: "Project Manager", clickable: false }]
    var section = { label: navi.app.nav.sectionTitle,
```

In `showSection()`, replace

```qml
  function showSection(name) {
    if (!navi.app.projects.selectedProject || navi.app.deleter.deleteTarget || navi.app.memories.memoryDeleteOpen || navi.app.memories.newMemoryOpen || navi.app.milestones.dialogOpen || navi.app.board.archiveOpen) return
```

with

```qml
  // Runs is the one section that opens with no project; every other name
  // needs one. A modal or an unsaved memory edit blocks them all.
  function showSection(name) {
    if ((!navi.app.projects.selectedProject && name !== "runs") || navi.app.deleter.deleteTarget || navi.app.memories.memoryDeleteOpen || navi.app.memories.newMemoryOpen || navi.app.milestones.dialogOpen || navi.app.board.archiveOpen) return
```

- [ ] **Step 6: Implement `Panel.qml`**

6a. In `focusItem`, replace

```qml
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "issue" || appStores.nav.viewMode === "run" || appStores.nav.viewMode === "graph" || !appStores.projects.selectedProject) ? keyCatcher
```

with

```qml
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "issue" || appStores.nav.viewMode === "run" || appStores.nav.viewMode === "graph" || (!appStores.projects.selectedProject && appStores.nav.viewMode !== "runs")) ? keyCatcher
```

6b. In the `searchField` `TextField`, replace

```qml
          visible: !!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues" || appStores.nav.viewMode === "runs")
```

with

```qml
          // The Runs list searches with or without a project; the other lists need one.
          visible: appStores.nav.viewMode === "runs" || (!!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues"))
```

6c. Replace

```qml
          UI.ThemedText {
            variant: "dim"
            theme: panelTheme
            visible: !appStores.projects.selectedProject && appStores.projects.loadError === ""
            width: parent.width
            text: "No projects registered with brd."
```

with

```qml
          // Not on the run views: they list runs with or without a project.
          UI.ThemedText {
            objectName: "noProjectsText"
            variant: "dim"
            theme: panelTheme
            visible: !appStores.projects.selectedProject && appStores.projects.loadError === ""
              && appStores.nav.viewMode !== "runs" && appStores.nav.viewMode !== "run"
            width: parent.width
            text: "No projects registered with brd."
```

- [ ] **Step 7: Run them to verify they pass**

Run the three commands of Step 4 again (for `tst_shortcuts.qml` drop the `Shortcuts::…` filter so the whole file runs).
Expected: `Totals: N passed, 0 failed` for each file, no `TypeError`. Also run `tests/ui/tst_breadcrumb_trail.qml` and `tests/ui/tst_navigator.qml` the same way: both stay green.

- [ ] **Step 8: Commit**

```bash
git add ui/Navigator.qml ui/Panel.qml tests/ui/tst_sidebar_nav.qml tests/ui/tst_runs_flow.qml tests/ui/tst_shortcuts.qml
git commit -m "feat(navigator): Runs and Run detail open without a project, with their search, focus and crumbs"
```

---

### Task 4: Start run without a project is shown, disabled, and says why

**Files:**
- Modify: `ui/Panel.qml` — the `startRunButton` `UI.ActionButton` and the comment above it (lines 529-540)
- Test: `tests/ui/tst_runs_flow.qml` (F6), `tests/ui/tst_panel_toolbar.qml` (rename + change), `tests/ui/tst_dispatch_flow.qml` (F7: two asserts)

**Interfaces:**
- Consumes: Task 3's `makeNoProject()` in `tst_runs_flow.qml` and `showSection("runs")` with no project.
- Produces: `startRunButton.visible === (viewMode === "runs")`; `enabled === (!!selectedProject && amStatus !== "missing")`; `tooltipText` per the Global Constraints.

- [ ] **Step 1: Write the failing tests**

1a. Append to `tests/ui/tst_runs_flow.qml`, before the closing `}` (after the Task 3 tests):

```qml
  // F6
  function test_start_run_without_a_project_is_disabled_with_why() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch")
    mouseClick(button)
    compare(p.dispatchOpen, false, "a click opens nothing")
    compare(p.app.runs.dispatchState, "idle")
    p.app.runs.amStatus = "missing"
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch", "no project wins over am missing")
  }
```

1b. In `tests/ui/tst_panel_toolbar.qml`, rename `test_start_run_shows_only_on_the_runs_list_of_a_project` to `test_start_run_shows_only_on_the_runs_list`, and replace its last three lines

```qml
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, false, "no project")
  }
```

with

```qml
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, true, "no project: still shown")
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch")
  }
```

1c. F7 — the click with a project is already `DispatchFlow::test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets`; extend it rather than duplicate. In `tests/ui/tst_dispatch_flow.qml`, replace

```qml
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    button.clicked()
```

with

```qml
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    button.clicked()
```

- [ ] **Step 2: Run them to verify they fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_runs_flow.qml RunsFlow::test_start_run_without_a_project_is_disabled_with_why 2>&1 | grep -E "^(FAIL|PASS|Totals)|Actual|Expected"
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_panel_toolbar.qml PanelToolbar::test_start_run_shows_only_on_the_runs_list 2>&1 | grep -E "^(FAIL|PASS|Totals)|Actual|Expected"
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_dispatch_flow.qml DispatchFlow::test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets 2>&1 | grep -E "^(FAIL|PASS|Totals)|Actual|Expected"
```

Expected: the first two FAIL (`startRunButton` visible is `false`, expected `true`); the third PASSES (it pins the with-project behavior this task must keep).

- [ ] **Step 3: Implement**

In `ui/Panel.qml`, replace

```qml
          // The Runs list's way to start a run: the dialog opens on the whole
          // board with a row of targets. Disabled while am is missing.
          UI.ActionButton {
            objectName: "startRunButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "runs" && !!appStores.projects.selectedProject
            enabled: appStores.runs.amStatus !== "missing"
            iconText: "▶"
            text: "Start run"
            tooltipText: appStores.runs.amStatus === "missing" ? "am is not installed or not on PATH" : "Start an am run"
            onClicked: root.openRunsDispatch("board")
          }
```

with

```qml
          // The Runs list's way to start a run on the open project: the dialog
          // opens on its whole board with a row of targets. Shown with or
          // without a project; disabled with none or while am is missing, and
          // the tooltip says which (no project first).
          UI.ActionButton {
            objectName: "startRunButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "runs"
            enabled: !!appStores.projects.selectedProject && appStores.runs.amStatus !== "missing"
            iconText: "▶"
            text: "Start run"
            tooltipText: !appStores.projects.selectedProject ? "Open a project to dispatch"
              : appStores.runs.amStatus === "missing" ? "am is not installed or not on PATH" : "Start an am run"
            onClicked: root.openRunsDispatch("board")
          }
```

- [ ] **Step 4: Run them to verify they pass**

Run the three commands of Step 2 without the `Case::test` filters (whole files).
Expected: `Totals: N passed, 0 failed` for `tst_runs_flow.qml`, `tst_panel_toolbar.qml` and `tst_dispatch_flow.qml`.

- [ ] **Step 5: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml tests/ui/tst_panel_toolbar.qml tests/ui/tst_dispatch_flow.qml
git commit -m "feat(panel): Start run shows without a project, disabled with \"Open a project to dispatch\""
```

---

### Task 5: p / r / c act on runs without a project

**Files:**
- Modify: `ui/Shortcuts.qml` — `handleRunKey` (line 66) and its comment (54-60)
- Test: `tests/ui/tst_shortcuts.qml` — replace `test_without_a_project_the_run_keys_are_left_alone` (and its comment line `// A run key needs a project: with none, the letter is left alone.`), add three tests

**Interfaces:**
- Consumes: `inRunKeys()`, `normRun(id, status, live)`, `plain(key)`, `ctrl(key)` already in `tst_shortcuts.qml`; Task 3's `showSection("runs")` with no project (not needed by these tests, which enter Runs with a project and then clear it).
- Produces: `handleRunKey(event)` no longer reads `app.projects`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_shortcuts.qml`, replace

```qml
  // A run key needs a project: with none, the letter is left alone.
  function test_without_a_project_the_run_keys_are_left_alone() {
    var s = inRunKeys(); if (!s) return
    s.app.projects.selectedProject = null
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true)]
    compare(s.app.nav.viewMode, "runs")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(s.handleRunKey(plain(Qt.Key_C)), false)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
    compare(Object.keys(s.app.runs.pending).length, 0)
  }
```

with

```qml
  // A run key needs no project: a run carries its own repository.
  // K1
  function test_without_a_project_the_run_keys_act_on_the_cursor_run() {
    var s = inRunKeys(); if (!s) return
    s.app.projects.selectedProject = null
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true), normRun("run-0000000000b2", "stopped", null)]
    s.app.nav.cursorIndex = 0
    compare(s.app.nav.viewMode, "runs")
    compare(s.handleRunKey(plain(Qt.Key_R)), true, "a refused key is still handled")
    compare(s.app.runs.flashText, "The run is still running")
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.handleRunKey(plain(Qt.Key_C)), true)
    compare(s.app.runs.cancelOpen, true)
    compare(s.app.runs.cancelRunId, "run-0000000000a1")
    s.app.runs.closeCancel()
    compare(s.handleRunKey(plain(Qt.Key_P)), true)
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.controlRunners.length, 1)
  }

  // K2
  function test_without_a_project_the_run_keys_act_on_the_open_run() {
    var s = inRunKeys(); if (!s) return
    s.app.projects.selectedProject = null
    s.navigator.openRun("run-0000000000b2")
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_R)), true)
    compare(s.app.runs.pending["run-0000000000b2"], "resume")
    compare(s.app.runs.pending["run-0000000000a1"], undefined, "not the cursor row")
  }

  // Review Focus 2
  function test_without_a_project_an_empty_runs_list_leaves_the_keys_alone() {
    var s = inRunKeys(); if (!s) return
    s.app.projects.selectedProject = null
    s.app.runs.runs = []
    s.app.nav.cursorIndex = 0
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(s.handleRunKey(plain(Qt.Key_R)), false)
    compare(s.handleRunKey(plain(Qt.Key_C)), false)
    s.handleActivate()
    compare(s.app.nav.viewMode, "runs", "Enter opens nothing")
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
  }

  // Review Focus 3
  function test_without_a_project_the_cancel_dialog_swallows_ctrl_6_and_the_run_keys() {
    var s = inRunKeys(); if (!s) return
    s.app.projects.selectedProject = null
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.runs.openCancel("run-0000000000a1"), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.cancelOpen, true)
  }
```

- [ ] **Step 2: Run them to verify K1 and K2 fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_shortcuts.qml 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"`
Expected: `FAIL!  : Shortcuts::test_without_a_project_the_run_keys_act_on_the_cursor_run()` (Actual `false`, Expected `true`) and `FAIL!  : Shortcuts::test_without_a_project_the_run_keys_act_on_the_open_run()`; the two Review Focus guards and every other test pass.

- [ ] **Step 3: Implement**

In `ui/Shortcuts.qml`, replace

```qml
  // p / r / c with no modifier at all pause, resume or cancel a run: on Run
  // detail the open run, on the Runs list the cursor row -- there only while
  // the search is empty, since the search field has the focus and every letter
  // types once it holds text (Shift+letter always types). A refused key
  // flashes why; c opens the cancel confirmation. Returns true when it handled
  // the key; with no target run the letter is left alone.
  function handleRunKey(event) {
    if (event.modifiers !== Qt.NoModifier) return false
    var action = event.key === Qt.Key_P ? "pause" : event.key === Qt.Key_R ? "resume" : event.key === Qt.Key_C ? "cancel" : ""
    if (action === "") return false
    var mode = keys.app.nav.viewMode
    if (!keys.app.projects.selectedProject || (mode !== "runs" && mode !== "run")) return false
```

with

```qml
  // p / r / c with no modifier at all pause, resume or cancel a run, with or
  // without a project open: on Run detail the open run, on the Runs list the
  // cursor row -- there only while the search is empty, since the search field
  // has the focus and every letter types once it holds text (Shift+letter
  // always types). A refused key flashes why; c opens the cancel confirmation.
  // Returns true when it handled the key; with no target run the letter is
  // left alone.
  function handleRunKey(event) {
    if (event.modifiers !== Qt.NoModifier) return false
    var action = event.key === Qt.Key_P ? "pause" : event.key === Qt.Key_R ? "resume" : event.key === Qt.Key_C ? "cancel" : ""
    if (action === "") return false
    var mode = keys.app.nav.viewMode
    if (mode !== "runs" && mode !== "run") return false
```

Leave `handleDispatchKey` untouched (its `!keys.app.projects.selectedProject` check stays; `test_d_is_left_alone` row `no-project` keeps passing — spec K4).

- [ ] **Step 4: Run the file to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_shortcuts.qml 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"`
Expected: `Totals: N passed, 0 failed` (including every `test_d_is_left_alone` row).

- [ ] **Step 5: Run the full gate**

Run: `timeout 1200 bash tests/run.sh; echo "exit=$?"`
Expected: pytest passes (including `tests/architecture`), every `== tests/...qml` block prints a `Totals: … 0 failed` line with no `FAIL` and no `TypeError` / `ReferenceError` line, and `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add ui/Shortcuts.qml tests/ui/tst_shortcuts.qml
git commit -m "feat(shortcuts): p / r / c act on runs without a project"
```

---

## Self-review against the spec

**Coverage:**

| spec item | task |
|---|---|
| B1.1, B1.2 (Runs row enabled, bound rows gated) — S1, S2 | 1 |
| B1.3 (attention count with no project) | unchanged code; `navCountRuns` reads `runsAttentionText` only (existing `test_the_runs_row_shows_the_attention_count`) |
| B2.1, B2.2, B2.3 (`showSection`) — N1, N3, F1, F8, K3 | 3 (B2.3 guards: existing `test_ctrl_6_is_ignored_while_a_delete_is_being_confirmed`, the condition keeps every modal clause) |
| B2.4 crumbs — F1, F2, F8 | 3 |
| B2.5 openRun / Back (Escape, Left, crumb) — F2 | 3 |
| B2.6 `currentList()` — F1, F3 | 3 |
| B3.1 screen visibility; B3.2 notify row + comment — screen tests, F5 | 2, 3 |
| B4.1 focus — N2, F1, F2, F8 | 3 |
| B4.2 search field — F1, F3, F8 | 3 |
| B4.3 placeholder — F1, F2, F8 | 3 |
| B4.4 Start run — F6, toolbar test, F7 (dispatch test 21 + toolbar test) | 4 |
| B4.5 toast Open — F4 | 3 |
| B4.6 other `selectedProject` uses unchanged | no edit; guarded by existing toolbar / graph / delete tests |
| B5.1 handleRunKey — K1, K2; B5.5 comments | 5 |
| B5.2, B5.3 Ctrl+6 / Ctrl+1..5 — K3, F8 | 3 |
| B5.4 `d` stays bound — K4 (existing `no-project` row) | 5 (unchanged) |
| Error table: empty list, am missing, modal, cleared/selected, Back | 5 (RF2, RF3), 4 (F6), 3 (RF4), 3 (F2) |
| Existing tests asserting the old gate | 1 (tst_sidebar), 2 (screen tests), 4 (tst_panel_toolbar) |
| `tests/architecture` green | 5, Step 5 (no imports added) |

**Placeholders:** none; every code step carries the exact old and new text.

**Type consistency:** `makeNoProject()`, `sampleRuns()`, `withToast(view, noProject)` are defined in Task 3 and used in Tasks 3-4; `noProjectsText` is created in Task 3 Step 6c and read only from Task 3 on; `aRun(id)` lives in `tst_sidebar_nav.qml` only.

**Note:** F7 is not a new function in `tst_runs_flow.qml`: the spec says to extend an existing test that covers the click, which is `DispatchFlow::test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets` (Task 4 Step 1c), with the enabled/tooltip half already in `PanelToolbar::test_start_run_shows_only_on_the_runs_list`.
<!-- task-pipeline: validated -->
