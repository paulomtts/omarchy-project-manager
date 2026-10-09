# 4.4 Runs row: Open project (card 1044d421)

Narrowed from `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (S6, "the
parent" below): "Behaviour", the Run detail bullet (lines 59-64), "Architecture", the UI
bullet (lines 140-142, "**Open project** action") and "Testing" (lines 190-193, "**Open
project**"). Parent story 63a11d2f. Blocked by 4.3 (aeb77310, spec
`4-3-runsscreen-the-aeb77310.md`, the project filter chips), which is done on this branch.

A run row gets an **Open project** button. Clicking it selects the run's project through
the navigator; the panel then shows that project's Board, and Ctrl+6 brings the user back
to Runs. Opening a run (Run detail) still works for a run of any project and does not
switch the open project.

## Starting point (what exists, unchanged by this card)

- `ui/screens/RunsScreen.qml`, `component RunRow: UI.ListRow`: its `actions` holds one
  `UI.RunControls` (`objectName: "runRowControls" + row.index`, `showButtons: row.hasCursor`).
  `ListRow.actions` is an alias for a Column under the content (`ui/components/ListRow.qml:27`,
  `:77`). The strip above the row's MouseArea keeps every click inside it
  (`ListRow.qml:63-69`), so clicking a button in it never opens the row. `RunRow.onActivated`
  calls `screen.navigator.openRun(run.id)` with no `from`.
- `screen.openRoot` is `screen.rootKey(screen.app.runs.project)`: the open project's root,
  `""` when no project is open. `screen.rootKey` strips trailing slashes. The parent says
  `RunStore.project` "KEEPS its meaning, the open project's root" (lines 130-131).
- A run's project is `run.project = {root, name}` (`Runs.withProject`, parent lines 122-124).
  A run with no `project`, or with `project.root === ""`, belongs to no registered project.
- The registry is `app.projects.projects`, a list of `{root_path, name}`
  (`core/stores/ProjectStore.qml:17`).
- `Navigator.chooseProject(project)` (`ui/Navigator.qml:133`): if a memory draft is dirty
  it sets `memoryOpError` and does not switch. Otherwise it closes the dropdown, calls
  `app.projects.chooseProject(project)` and focuses the view. `ProjectStore.chooseProject`
  (`ProjectStore.qml:87`) only selects when the root is different. Its `selected` signal
  makes `App.qml`'s `onSelected` set `nav.viewMode = "board"`, reset the search and fetch
  the board (parent line 63: "the existing `ProjectStore.onSelected` behaviour").
- `Navigator.openRun(id, from)` (`ui/Navigator.qml:335`) opens any listed run. It sets
  `viewMode "run"` and `selectedRunId` and does not touch `selectedProject` (parent lines
  59-61).
- Ctrl+6 (`Shortcuts.handleGlobalKey`, `Navigator.showSection("runs")`) opens Runs whether
  or not a project is open (parent lines 39-44, built by an earlier card).
- `UI.ActionButton` (`ui/components/ActionButton.qml`): the panel's bordered small shell
  Button, with `theme`, `tone`, `text`, `iconText`, `tooltipText` and `clicked`.

## Behaviour

B1. **The button.** Every run row gets a `UI.ActionButton` with
    `objectName: "runRowOpenProject" + row.index`, text `Open project` and
    `theme: screen.theme`. It goes in the row's `actions`, after `runRowControls`. It has no
    icon glyph (`iconText` left empty), so the glyph rule in
    `tests/architecture/test_icon_glyphs.py` has nothing new to check.

B2. **When it shows.** The button is `visible` only when all of these hold:
    - the row has the cursor (`row.hasCursor`; hover moves the cursor, the same rule as the
      row's controls, `RunsScreen.qml` comment above `actions`);
    - the run has a project: `rootKey(run.project.root) !== ""`;
    - that project is not the open one: `rootKey(run.project.root) !== screen.openRoot`;
    - the registry has an entry for it (B3).

    If any of these fails, the button is not visible and takes no height. A row without the
    cursor is then exactly as tall as it is today, because `ListRow.actionsExtent` is 0 when
    no action item has height.

B3. **The registry entry.** The run's project resolves to the first entry `e` of
    `screen.app.projects.projects` (in list order) with
    `rootKey(e.root_path) === rootKey(run.project.root)`. "First" matches the parent's rule
    for two registrations of one repository (lines 136-137). If the list is missing, is not
    array-like, or has no matching entry, there is no entry and B2 hides the button. Missing
    lists and non-object entries are skipped without a warning, following the file's
    `sizeOf` convention: the test runner fails on `TypeError` / `ReferenceError` in output.

B4. **The click.** Clicking a visible button calls `screen.navigator.chooseProject(e)` with
    the registry entry object from B3 itself (not a copy and not `run.project`). Nothing
    else happens: the row is not activated, `openRun` is not called, and the project filter
    does not change. Everything after that is existing behaviour (Starting point):
    `selectedProject` becomes `e`, `viewMode` becomes `"board"`, the search resets, and a
    dirty memory draft blocks the switch with `memoryOpError`.

B5. **Coming back.** After the switch, Ctrl+6 shows Runs (`viewMode "runs"`). The newly
    open project's runs no longer show the button, because their root is now
    `screen.openRoot`. The other projects' runs still do.

B6. **Run detail does not switch.** Clicking a row, or pressing Enter on it, still calls
    `navigator.openRun(run.id)` for a run of any project. Run detail opens
    (`viewMode "run"`, `selectedRunId` the run's id) and `app.projects.selectedProject`
    stays the same object. This card does not change it; a test pins it (parent line 59).

B7. **Contract comments.** The RunsScreen header comment (lines 10-24) gets one clause
    saying that a row with the cursor shows Open project for a run of a registered project
    other than the open one, and that the button asks the navigator to choose that project.
    New functions and properties get contract-only comments, like the rest of the file.

## Errors and edge cases

| case | behaviour |
|---|---|
| no project open (`openRoot ""`) | the button shows on the cursor row of every run whose project is registered |
| the run's project is the open one, trailing slash on either side | hidden (roots compared by `rootKey`) |
| the run has no `project` / `project.root ""` | hidden |
| the run's root is not in `app.projects.projects` (left the registry) | hidden; nothing is called |
| `app.projects.projects` missing or not array-like (the screen test's stub before it is extended) | hidden; no warning in the output |
| two registry entries with one root | the first one is chosen |
| the row has no cursor | hidden |
| a memory draft is dirty | `Navigator.chooseProject` refuses as it does today; the panel stays on Runs |
| clicking the button | does not open the run (the actions strip keeps the click) |

## Out of scope

- A keyboard shortcut for Open project. The card asks only for a button.
- Any change to `Navigator`, `Panel`, `App.qml`, `ProjectStore` or `RunStore`. The switch,
  the Board and Ctrl+6 are existing behaviour.
- An Open project action on Run detail, toasts, `RunIndicator` or group headers. Toast
  project names belong to a sibling card (parent line 141).
- Changing the project filter on a switch. The parent says "a project switch does not touch
  it" (line 56).
- Docs (`docs/architecture.md` and similar). The docs card of this milestone covers them.

## Tests

All QML, run by `bash tests/run.sh` (qmltestrunner on a mirrored repo). Tests are written
first and must fail before the code exists.

### `tests/ui/screens/tst_runs_screen.qml` (screen tier)

Why this tier: visibility rules and the call made on click. The screen with stub app and
navigator isolates them from the real stores.

Stub changes: `appC.projects` gets a `projects` list
`[{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }]`.
`naviC` gets `property var chosen: []` and `function chooseProject(p) { chosen = chosen.concat([p]) }`.
Existing tests must still pass unchanged.

1. `test_open_project_shows_on_the_cursor_row_of_another_projects_run`: `twoProjects()`,
   `runs.project = "/home/u/a"`. The cursor on beta's row shows `runRowOpenProject<i>` with
   text `Open project`. With the cursor on an alpha row, that row's button is hidden.
2. `test_open_project_is_hidden_off_the_cursor`: beta's row without the cursor has the
   button hidden. Measure beta's row height with the cursor elsewhere, move the cursor
   onto it and then away again: the height is the same as the first measurement.
3. `test_open_project_is_hidden_for_the_open_project_with_a_trailing_slash`:
   `runs.project = "/home/u/a/"`. The cursor on an alpha row hides the button.
4. `test_with_no_project_open_every_registered_projects_run_shows_open_project`:
   `runs.project = ""`. The cursor on an alpha row and on a beta row both show it.
5. `test_open_project_is_hidden_for_a_run_with_no_project_or_an_unregistered_one`: a plain
   `run()` (no `project`) and a run tagged `/home/u/c` (not in the registry). Both are
   hidden under the cursor.
6. `test_open_project_tolerates_a_missing_registry`: `app.projects.projects` set to
   `undefined`. The button is hidden; no warning (the runner's output check catches one).
7. `test_open_project_click_chooses_the_registry_entry_and_does_not_open_the_run`: click
   (`tap`) beta's button. `navi.chosen.length === 1` and `navi.chosen[0]` is the registry's
   beta entry object (`===`). `navi.opened === ""`. `runs.projectToggles` is empty.
8. `test_open_project_picks_the_first_of_two_entries_with_one_root`: the registry lists
   `/home/u/b/` (name `beta-1`) then `/home/u/b` (name `beta-2`). The click chooses the
   `beta-1` entry.
9. `test_a_row_click_still_opens_any_projects_run`: clicking beta's row content (not the
   button) records `navi.opened` as beta's run id and `navi.chosen` stays empty.

### `tests/ui/tst_runs_flow.qml` (flow tier, real `Panel`)

Why this tier: the switch to Board, Ctrl+6 back to Runs and "Run detail does not switch"
come from the real Navigator, ProjectStore and App. Only the full panel proves them.

Setup per test: `make()`, then `p.app.projects.applyProjectsList([pA, pB])`, cancel
`snapshotRunner`, and set `p.app.runs.runs` to the mixed list from
`test_enter_on_the_first_run_of_the_second_project_opens_it` (alpha's two runs, beta's
`run-0000000000f6`). After any project switch, disarm `exportProc`, `settingsLoadRunner`
and `runSettingsRunner` as `test_with_no_project_choosing_a_project_on_a_run_opens_the_board`
does.

10. `test_open_project_on_another_projects_run_opens_its_board_and_ctrl_6_returns`: Ctrl+6,
    move the cursor to beta's run (index 2), click `runRowOpenProject2`. Then
    `selectedProject.root_path === "/home/u/b"`, `viewMode === "board"` and the crumbs read
    `Board`. Ctrl+6 then gives `viewMode === "runs"`. Now beta is open: with the cursor on
    beta's row its button is hidden, and with the cursor on an alpha row that row's button
    is visible.
11. `test_run_detail_of_another_projects_run_keeps_the_open_project`: Ctrl+6, cursor on
    beta's run, Enter (or `navigator.openRun("run-0000000000f6")`). Then
    `viewMode === "run"`, `selectedRunId === "run-0000000000f6"` and
    `selectedProject.root_path === "/home/u/a"`.

### Architecture tier

`tests/architecture` (pytest, part of `tests/run.sh`) must stay green. There is no new
component file, no duplicated helper, and no new private-use glyph.

## Verification

`bash tests/run.sh` green, with no `TypeError` / `ReferenceError` / `non-existent` /
`Unable to assign` / `is not a function` lines in the output.
