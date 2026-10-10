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

---

# 4.4 Runs row: Open project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every run row on the Runs screen an **Open project** button, shown on the cursor row of a run whose project is registered and is not the open one, that asks the navigator to choose that project.

**Architecture:** Everything is in `ui/screens/RunsScreen.qml`. Two pure screen functions resolve a run to its registry entry (`registryEntryOf(list, root)`, `openProjectTargetOf(run, open, list)`), each `RunRow` binds the result as `openTarget`, and a `UI.ActionButton` in the row's `actions` shows while `row.hasCursor && row.openTarget !== null` and calls `screen.navigator.chooseProject(row.openTarget)` on click. The switch to Board, Ctrl+6 back and the dirty-draft refusal are existing `Navigator` / `ProjectStore` / `App` behaviour; flow tests on the real `Panel` pin them.

**Tech Stack:** QML (Qt 6 Quick), QtTest via `qmltestrunner`; `bash tests/run.sh [filter]` runs the pytest architecture tier, then every `tst_*.qml` whose path contains the filter, and fails on `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` in the output.

**Spec:** `docs/superpowers/specs/4-4-runs-row-open-1044d421.md` (prepended above).

## Global Constraints

- Only `ui/screens/RunsScreen.qml`, `tests/ui/screens/tst_runs_screen.qml` and `tests/ui/tst_runs_flow.qml` change. No change to `Navigator`, `Panel`, `App.qml`, `ProjectStore` or `RunStore`.
- The button: `UI.ActionButton`, `objectName: "runRowOpenProject" + row.index`, text `Open project`, `theme: screen.theme`, no `iconText`, placed in the row's `actions` after `runRowControls`.
- Roots are compared through the screen's existing `rootKey()`; "first" registry entry means first in `app.projects.projects` list order.
- The click passes the registry entry object itself (not a copy, not `run.project`) to `screen.navigator.chooseProject`. Nothing else happens on click: no `openRun`, no `toggleProjectFilter`.
- Missing / non-array-like registry lists and non-object entries are skipped without a warning (the runner fails on `TypeError` / `ReferenceError` lines).
- Contract-only comments, like the rest of `RunsScreen.qml`; the header comment gains the Open project clause (B7).
- No new component file, no duplicated helper, no private-use glyph: `tests/architecture` stays green.
- Tests first; each must fail before its code exists (the pin tests named below are the exception and say so).
- `bash tests/run.sh` green at the end.

## Review Focus

1. **A dirty memory draft when Open project is clicked** — the switch is refused, the panel stays on Runs with the open project unchanged, and `memoryOpError` says why. Pinned in Task 2 (`test_open_project_with_a_dirty_memory_draft_stays_on_runs`, flow tier).
2. **A malformed `run.project`** (`null`, a string, an array, a non-string `root`) — the button stays hidden and nothing throws. Pinned in Task 1 (`test_a_malformed_run_project_hides_open_project_without_throwing`).
3. **Malformed registry entries** (`null`, numbers, strings, a non-string `root_path`, no `root_path`) ahead of a good one — skipped silently; the good entry is still found. Pinned in Task 1 (`test_malformed_registry_entries_are_skipped`).
4. **The open project or the registry changes while the cursor sits on a row** — the button follows at once (hides when the run's project becomes the open one or leaves the registry, shows again when it comes back). Pinned in Task 1 (`test_open_project_follows_the_open_project_and_the_registry`).
5. **Open project under a project filter** (flat list, no headers) — the button still shows on another project's run and the click leaves `projectFilter` alone. Pinned in Task 2 (`test_open_project_under_a_project_filter_leaves_the_filter_alone`).

---

### Task 1: The Open project button and when it shows

**Files:**
- Modify: `ui/screens/RunsScreen.qml:10-24` (header comment), `:151-155` (new functions after `chooseProject`), `:426-549` (`RunRow`: `openTarget`, the button, the `actions` comment)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stub `appC`, a helper, new tests at the end of the file)

**Interfaces:**
- Consumes: `screen.rootKey(path)`, `screen.sizeOf(list)`, `screen.openRoot` (all existing in `RunsScreen.qml`); `screen.app.projects.projects` (`[{root_path, name}]`).
- Produces (Task 2 relies on these):
  - `function registryEntryOf(list, root)` on `screen` → the first object entry of `list` whose `rootKey(root_path) === rootKey(root)`, or `null`.
  - `function openProjectTargetOf(run, open, list)` on `screen` → the registry entry for `run.project.root`, or `null` when the run has no project or its root (by `rootKey`) is `open`.
  - `readonly property var openTarget` on `RunRow` → `screen.openProjectTargetOf(row.run, screen.openRoot, screen.app.projects.projects)`.
  - The item `runRowOpenProject<index>` (a `UI.ActionButton`, `visible: row.hasCursor && row.openTarget !== null`), with no `onClicked` yet.
  - Test helper `openButton(s, i)` in `tst_runs_screen.qml` → row i's button, failing the test when it does not exist.

- [ ] **Step 1: Give the screen test's stub app a registry**

In `tests/ui/screens/tst_runs_screen.qml`, replace the `appC` component:

```qml
  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" } })
    }
  }
```

with:

```qml
  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      // The project registry, as ProjectStore holds it: alpha and beta. A test
      // that changes it assigns a whole new object, so bindings follow.
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" },
                                projects: [{ root_path: "/home/u/a", name: "alpha" },
                                           { root_path: "/home/u/b", name: "beta" }] })
    }
  }
```

- [ ] **Step 2: Write the failing tests**

Append at the end of `tests/ui/screens/tst_runs_screen.qml`, just before the file's final closing `}`:

```qml

  // ---- Open project (4.4)

  // Row i's Open project button; the test fails when the row has none.
  function openButton(s, i) {
    var b = H.find(s.screen, "runRowOpenProject" + i)
    verify(b, "row " + i + " has an Open project button")
    return b
  }

  // The stub registry: alpha's selected, `list` the registry.
  function registry(list) {
    return { selectedProject: { root_path: "/home/u/a", name: "alpha" }, projects: list }
  }

  // twoProjects(): rows 0 and 1 are alpha's, row 2 is beta's.
  // 1
  function test_open_project_shows_on_the_cursor_row_of_another_projects_run() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    compare(openButton(s, 2).text, "Open project")
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 0).visible, false, "alpha is the open project")
    compare(openButton(s, 2).visible, false, "beta's row lost the cursor")
  }

  // 2
  function test_open_project_is_hidden_off_the_cursor() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 0
    wait(20)
    var row = H.find(s.screen, "runRow2")
    compare(openButton(s, 2).visible, false)
    var before = row.height
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 2).visible, false)
    compare(row.height, before, "the row is as tall as before the cursor came")
  }

  // 3
  function test_open_project_is_hidden_for_the_open_project_with_a_trailing_slash() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a/"
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 0).visible, false)
    s.nav.cursorIndex = 1
    wait(20)
    compare(openButton(s, 1).visible, false)
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true, "beta is not the open project")
  }

  // 4
  function test_with_no_project_open_every_registered_projects_run_shows_open_project() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = ""
    s.nav.cursorIndex = 0
    wait(20)
    compare(openButton(s, 0).visible, true, "alpha's run")
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true, "beta's run")
  }

  // 5
  function test_open_project_is_hidden_for_a_run_with_no_project_or_an_unregistered_one() {
    var s = make([run("run-20261004-plain001", "started", true, {}),
                  tagged(run("run-c-live0009", "started", true, {}), "/home/u/c", "gamma")]); if (!s) return
    s.runs.project = "/home/u/a"
    for (var i = 0; i < 2; i++) {
      s.nav.cursorIndex = i
      wait(20)
      compare(openButton(s, i).visible, false, "row " + i)
    }
  }

  // 6
  function test_open_project_tolerates_a_missing_registry() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    var lists = [undefined, null, "abc", 7, ({ length: 1 })]
    for (var i = 0; i < lists.length; i++) {
      s.app.projects = registry(lists[i])
      compare(openButton(s, 2).visible, false, "registry " + i)
    }
    s.app.projects = { selectedProject: { root_path: "/home/u/a", name: "alpha" } }
    compare(openButton(s, 2).visible, false, "no projects key at all")
  }

  // Review Focus 2.
  function test_a_malformed_run_project_hides_open_project_without_throwing() {
    var bad = [run("run-x-null0001", "started", true, {}), run("run-x-strg0002", "started", true, {}),
               run("run-x-nort0003", "started", true, {}), run("run-x-arry0004", "started", true, {})]
    bad[0].project = null
    bad[1].project = "/home/u/b"
    bad[2].project = { root: 7, name: "beta" }
    bad[3].project = ["/home/u/b"]
    var s = make(bad.concat([{}])); if (!s) return
    s.runs.project = "/home/u/a"
    for (var i = 0; i < 5; i++) {
      s.nav.cursorIndex = i
      wait(20)
      compare(openButton(s, i).visible, false, "row " + i)
    }
  }

  // Review Focus 3.
  function test_malformed_registry_entries_are_skipped() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.app.projects = registry([null, 5, "/home/u/b", { root_path: 7 }, { name: "no root" }])
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, false, "no well-formed entry for beta")
    s.app.projects = registry([null, { root_path: 7 }, { root_path: "/home/u/b/", name: "beta" }])
    compare(openButton(s, 2).visible, true, "the well-formed entry past the bad ones")
  }

  // Review Focus 4.
  function test_open_project_follows_the_open_project_and_the_registry() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    s.runs.project = "/home/u/b"
    compare(openButton(s, 2).visible, false, "beta is open now")
    s.runs.project = "/home/u/a"
    compare(openButton(s, 2).visible, true)
    s.app.projects = registry([{ root_path: "/home/u/a", name: "alpha" }])
    compare(openButton(s, 2).visible, false, "beta left the registry")
    s.app.projects = registry([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])
    compare(openButton(s, 2).visible, true, "beta is back")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_runs_screen`
Expected: FAIL. Every new test fails with `row <i> has an Open project button` (the button does not exist yet); every existing test still passes.

- [ ] **Step 4: Add the registry lookup to the screen**

In `ui/screens/RunsScreen.qml`, right after the existing `chooseProject(id)` function (the one ending with `screen.app.runs.toggleProjectFilter(id === "all" ? "" : id === "this" ? screen.app.runs.project : id)` and its closing `}`), insert:

```qml

  // The first entry of the registry `list` ({root_path, name} objects, in
  // list order) whose root_path is `root`, both compared by rootKey; null
  // when `root` is "", `list` is not array-like or no entry matches. Entries
  // that are not objects are skipped.
  function registryEntryOf(list, root) {
    var want = screen.rootKey(root)
    if (want === "") return null
    for (var i = 0; i < screen.sizeOf(list); i++) {
      var entry = list[i]
      if (entry !== null && typeof entry === "object" && screen.rootKey(entry.root_path) === want) return entry
    }
    return null
  }

  // The registry entry Open project chooses for `run`: registryEntryOf
  // `list` for the run's project.root; null when the run has no project or
  // its project's root is `open` (the open project's, by rootKey).
  function openProjectTargetOf(run, open, list) {
    var project = run !== null && typeof run === "object" ? run.project : null
    var root = screen.rootKey(project !== null && typeof project === "object" ? project.root : "")
    return root === "" || root === open ? null : screen.registryEntryOf(list, root)
  }
```

- [ ] **Step 5: Bind the row's target and add the button**

In `ui/screens/RunsScreen.qml`, inside `component RunRow`, replace:

```qml
    readonly property string runState: Runs.runState(row.run)
```

with:

```qml
    // The registry entry Open project chooses (openProjectTargetOf); null
    // hides the button.
    readonly property var openTarget: screen.openProjectTargetOf(row.run, screen.openRoot, screen.app.projects.projects)

    readonly property string runState: Runs.runState(row.run)
```

Then replace the comment and the `actions` list:

```qml
    // Under the row: the buttons while it has the cursor (hover moves the
    // cursor, so that is hover or selected) or a request is pending, and the
    // waiting and error lines whenever they apply.
    actions: [
      UI.RunControls {
        objectName: "runRowControls" + row.index
        width: parent.width
        theme: screen.theme
        run: row.run
        pendingAction: ControlFacts.pendingOf(screen.app.runs.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runs.stillWaiting, row.run)
        waitingText: screen.app.runs.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runs.lastControlError, screen.app.runs.lastControlErrorRunId, row.run)
        wholeRun: false
        showButtons: row.hasCursor
        onActionRequested: function(action) { screen.requestControl(action, row.run) }
      }
    ]
```

with:

```qml
    // Under the row: the buttons while it has the cursor (hover moves the
    // cursor, so that is hover or selected) or a request is pending, and the
    // waiting and error lines whenever they apply; then Open project while it
    // has the cursor and openTarget is not null.
    actions: [
      UI.RunControls {
        objectName: "runRowControls" + row.index
        width: parent.width
        theme: screen.theme
        run: row.run
        pendingAction: ControlFacts.pendingOf(screen.app.runs.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runs.stillWaiting, row.run)
        waitingText: screen.app.runs.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runs.lastControlError, screen.app.runs.lastControlErrorRunId, row.run)
        wholeRun: false
        showButtons: row.hasCursor
        onActionRequested: function(action) { screen.requestControl(action, row.run) }
      },
      UI.ActionButton {
        objectName: "runRowOpenProject" + row.index
        theme: screen.theme
        text: "Open project"
        visible: row.hasCursor && row.openTarget !== null
      }
    ]
```

- [ ] **Step 6: Add the Open project clause to the header comment**

In `ui/screens/RunsScreen.qml`, replace these header lines:

```qml
// means All again -- and a footer says whether the runs are watched. It reads
// the run store and asks the navigator to open a run or move the cursor; it
// owns no state of its own. Ages are read against the clock once per
// snapshot: there is no timer.
```

with:

```qml
// means All again -- and a footer says whether the runs are watched. The row
// with the cursor shows Open project for a run of a registered project other
// than the open one; the button asks the navigator to choose that project. It
// reads the run store and the project registry and asks the navigator to open
// a run, choose a project or move the cursor; it owns no state of its own.
// Ages are read against the clock once per snapshot: there is no timer.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_runs_screen`
Expected: PASS — `Totals` with 0 failed, and no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line printed.

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs-screen): Open project shows on the cursor row of another registered project's run"
```

---

### Task 2: Clicking Open project chooses the run's project

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (`RunRow`'s `runRowOpenProject` button: `onClicked`)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stub `naviC`, new tests at the end), `tests/ui/tst_runs_flow.qml` (helpers and new tests at the end)

**Interfaces:**
- Consumes (from Task 1): `RunRow.openTarget` (the registry entry object or `null`); the item `runRowOpenProject<index>`; test helpers `openButton(s, i)` and `registry(list)` in `tst_runs_screen.qml`. Existing: `Navigator.chooseProject(project)` (`ui/Navigator.qml:133`), `Navigator.openRun(id, from)`, `Shortcuts.handleGlobalKey` / `handleSearchKey`, the flow file's `make()`, `runIn(...)`, `ids(list)`, `labels(crumbs)`, `key(k)`, `tc.pA`, `tc.pB`.
- Produces: `onClicked: screen.navigator.chooseProject(row.openTarget)` on the button. Stub navigator gains `property var chosen` and `function chooseProject(p)`.

- [ ] **Step 1: Give the screen test's stub navigator a chooseProject recorder**

In `tests/ui/screens/tst_runs_screen.qml`, replace the `naviC` component:

```qml
  Component {
    id: naviC
    QtObject {
      property string opened: ""
      property int hovered: -1
      function openRun(id) { opened = String(id) }
      function hoverCursor(index) { hovered = index }
    }
  }
```

with:

```qml
  Component {
    id: naviC
    QtObject {
      property string opened: ""
      property int hovered: -1
      // Every project chooseProject was given, in order.
      property var chosen: []
      function openRun(id) { opened = String(id) }
      function hoverCursor(index) { hovered = index }
      function chooseProject(p) { chosen = chosen.concat([p]) }
    }
  }
```

- [ ] **Step 2: Write the failing screen tests**

Append at the end of `tests/ui/screens/tst_runs_screen.qml`, after the Task 1 tests and just before the file's final closing `}`:

```qml

  // 7
  function test_open_project_click_chooses_the_registry_entry_and_does_not_open_the_run() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    tap(openButton(s, 2))
    compare(s.navi.chosen.length, 1)
    compare(s.navi.chosen[0].name, "beta")
    verify(s.navi.chosen[0] === s.app.projects.projects[1], "the registry's own beta entry")
    compare(s.navi.opened, "", "the button is not the row")
    compare(s.runs.projectToggles.length, 0, "the project filter is not touched")
    compare(s.runs.projectFilter, "")
  }

  // 8
  function test_open_project_picks_the_first_of_two_entries_with_one_root() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.app.projects = registry([{ root_path: "/home/u/a", name: "alpha" },
                               { root_path: "/home/u/b/", name: "beta-1" },
                               { root_path: "/home/u/b", name: "beta-2" }])
    s.nav.cursorIndex = 2
    wait(20)
    tap(openButton(s, 2))
    compare(s.navi.chosen.length, 1)
    compare(s.navi.chosen[0].name, "beta-1")
    verify(s.navi.chosen[0] === s.app.projects.projects[1], "the entry object itself")
  }

  // 9: a pin — the row's own click is unchanged, so this passes before the
  // button has a click handler.
  function test_a_row_click_still_opens_any_projects_run() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.nav.cursorIndex = 2
    wait(20)
    compare(openButton(s, 2).visible, true)
    tap(H.find(s.screen, "runRowTitle2"))
    compare(s.navi.opened, "run-b-live0003")
    compare(s.navi.chosen.length, 0)
  }

  // Review Focus 5.
  function test_open_project_under_a_project_filter_leaves_the_filter_alone() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    s.runs.toggleProjectFilter("/home/u/b")
    s.runs.projectToggles = []
    s.nav.cursorIndex = 0
    wait(20)
    compare(H.find(s.screen, "runRowId0").text, "…live0003", "beta's run, flat")
    tap(openButton(s, 0))
    compare(s.navi.chosen.length, 1)
    compare(s.navi.chosen[0].root_path, "/home/u/b")
    compare(s.runs.projectToggles.length, 0)
    compare(s.runs.projectFilter, "/home/u/b")
  }
```

- [ ] **Step 3: Write the failing flow tests**

Append at the end of `tests/ui/tst_runs_flow.qml`, just before the file's final closing `}`:

```qml

  // ---- Open project (4.4)

  // make() with pA and pB registered and pA open; filteredRuns is alpha's
  // run-0000000000b2 and run-0000000000c3, then beta's run-0000000000f6.
  function makeTwo() {
    var p = make(); if (!p) return null
    p.app.projects.applyProjectsList([pA, pB])
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [runIn("run-0000000000f6", "started", true, "zeta", "/home/u/b", "beta"),
                       runIn("run-0000000000b2", "escalated", null, "beta-ms", "/home/u/a", "alpha"),
                       runIn("run-0000000000c3", "started", false, "gamma", "/home/u/a", "alpha")]
    return p
  }

  // A project switch starts a `brd export` and two run-settings reads that
  // cannot run here: all are disarmed so their late replies change nothing.
  function disarmSwitch(p) {
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.runs.settingsLoadRunner.cancel()
    p.app.runs.runSettingsRunner.cancel()
  }

  function ctrl6(p) {
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
  }

  // Ctrl+6, then the cursor down to beta's run (index 2).
  function runsOnBeta(p) {
    ctrl6(p)
    compare(ids(p.app.runs.filteredRuns), "run-0000000000b2,run-0000000000c3,run-0000000000f6")
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 2)
  }

  // 10
  function test_open_project_on_another_projects_run_opens_its_board_and_ctrl_6_returns() {
    var p = makeTwo(); if (!p) return
    runsOnBeta(p)
    var button = H.find(p, "runRowOpenProject2")
    verify(button, "beta's row has Open project")
    compare(button.visible, true)
    wait(450)
    mouseClick(button)
    disarmSwitch(p)
    compare(p.app.projects.selectedProject.root_path, "/home/u/b")
    compare(p.app.nav.viewMode, "board")
    compare(labels(p.navigator.crumbs), "Board")
    ctrl6(p)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.project, "/home/u/b")
    compare(p.app.nav.cursorIndex, 0)
    compare(H.find(p, "runRowOpenProject0").visible, true, "alpha is no longer the open project")
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 2)
    compare(H.find(p, "runRowOpenProject2").visible, false, "beta is the open project now")
  }

  // 11: a pin — Run detail never switched the project, so this passes before
  // the button has a click handler.
  function test_run_detail_of_another_projects_run_keeps_the_open_project() {
    var p = makeTwo(); if (!p) return
    var open = p.app.projects.selectedProject
    runsOnBeta(p)
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f6")
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    verify(p.app.projects.selectedProject === open, "the same project object")
  }

  // Review Focus 1.
  function test_open_project_with_a_dirty_memory_draft_stays_on_runs() {
    var p = makeTwo(); if (!p) return
    runsOnBeta(p)
    p.app.memories.memoryEditing = true
    p.app.memories.memoryText = "saved"
    p.app.memories.memoryDraft = "edited"
    var button = H.find(p, "runRowOpenProject2")
    verify(button, "beta's row has Open project")
    wait(450)
    mouseClick(button)
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    compare(p.app.nav.viewMode, "runs")
    verify(p.app.memories.memoryOpError.indexOf("unsaved changes") >= 0, p.app.memories.memoryOpError)
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_runs_screen`
Expected: FAIL in `test_open_project_click_chooses_the_registry_entry_and_does_not_open_the_run`, `test_open_project_picks_the_first_of_two_entries_with_one_root` and `test_open_project_under_a_project_filter_leaves_the_filter_alone` (`chosen.length` is 0, expected 1). `test_a_row_click_still_opens_any_projects_run` and every earlier test PASS.

Run: `timeout 900 bash tests/run.sh tst_runs_flow`
Expected: FAIL in `test_open_project_on_another_projects_run_opens_its_board_and_ctrl_6_returns` (`selectedProject.root_path` is `/home/u/a`, expected `/home/u/b`) and `test_open_project_with_a_dirty_memory_draft_stays_on_runs` (`memoryOpError` is empty). `test_run_detail_of_another_projects_run_keeps_the_open_project` and every earlier test PASS.

- [ ] **Step 5: Make the button choose the project**

In `ui/screens/RunsScreen.qml`, inside `RunRow`'s `actions`, replace:

```qml
      UI.ActionButton {
        objectName: "runRowOpenProject" + row.index
        theme: screen.theme
        text: "Open project"
        visible: row.hasCursor && row.openTarget !== null
      }
```

with:

```qml
      UI.ActionButton {
        objectName: "runRowOpenProject" + row.index
        theme: screen.theme
        text: "Open project"
        visible: row.hasCursor && row.openTarget !== null
        onClicked: screen.navigator.chooseProject(row.openTarget)
      }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_runs_screen`
Expected: PASS, 0 failed, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line.

Run: `timeout 900 bash tests/run.sh tst_runs_flow`
Expected: PASS, 0 failed, no such line.

- [ ] **Step 7: Run the whole suite**

Run: `timeout 1800 bash tests/run.sh`
Expected: exit status 0; pytest (including `tests/architecture`) passes; every `== tests/...` block prints `Totals: ... 0 failed`; no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line.

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs-screen): Open project chooses the run's project through the navigator"
```
<!-- task-pipeline: validated -->
