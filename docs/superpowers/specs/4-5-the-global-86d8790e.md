# 4.5 The global RunIndicator, sidebar count and toast project (card 86d8790e)

Narrowed from `docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (S6, "the
parent" below): "Behaviour", the indicators bullet (lines 69-72: "The toolbar `RunIndicator`,
the sidebar attention count and the escalation toasts / desktop notification cover every
registered project, and an alert names the project. `RunIndicator` exists but is NOT mounted
in `Panel` today: this milestone mounts it beside `MilestoneJobIndicator`"), "Architecture",
the UI bullet (lines 140-142: "project name on toasts; `RunIndicator` mounted, and it and the
sidebar count read `Runs.attention` / run counts over the global list") and "Testing"
(lines 190-193: "`RunIndicator` mounted and its counts, sidebar count and toasts across
projects"; line 190: "toast Open"). Parent story 63a11d2f. Blocked by 4.4 (1044d421, spec
`4-4-runs-row-open-1044d421.md`), done on this branch.

The panel's toolbar shows a run strip (`⟳2 ⏸1 ‼1`) that counts the runs of every registered
project, with or without an open project; clicking a segment shows the Runs list on that
status chip. The sidebar's Runs count is global. Every run toast names the run's project, and
its Open shows the run without changing the open project.

## Starting point (what exists, unchanged by this card unless B-items say so)

- `ui/components/RunIndicator.qml`: presentation only. Props `running`, `parked`,
  `attention`, `theme`; `signal filterRequested(string filter)` with `"live"` (running
  segment, `runIndicatorRunning`), `"parked"` (`runIndicatorParked`) or `"attention"`
  (`runIndicatorAttention`); root `objectName: "runIndicator"`; hidden when all three counts
  are 0. Its own component test is `tests/ui/components/tst_run_indicator.qml`. It is not
  referenced by `ui/Panel.qml`.
- `ui/Panel.qml` toolbar: `Column { id: toolbar; objectName: "panelToolbar" }`. Its first
  child is a `RowLayout` (the breadcrumbs with `Layout.fillWidth`, the Graph / Documents
  chips, `refreshButton`, `newMemoryButton`, `newMilestoneButton`, `archiveFinishedButton`,
  `startRunButton`). The next child is `UI.MilestoneJobIndicator` (its own row), then
  `searchField`.
- `appStores.runs.runs` (`core/stores/RunStore.qml`) is every registered project's runs,
  merged; a project switch leaves it alone (RunStore header comment, lines 6-13).
- `Runs.runFilterCounts(runs)` (`core/domain/runs.js:596`) returns
  `{attention, live, parked, all}`: `attention` is `Runs.attention(runs)` (escalated plus
  dead), `live` the runs in state `running`, `parked` those in state `parked`. The Runs
  screen's chips use the same function.
- `RunStore.runFilter` is the Runs screen's chip: `""` (All), `"attention"`, `"live"` or
  `"parked"`. `RunStore.toggleRunFilter(id)` TOGGLES: the id that is already active, or
  `"all"`, sets `""`. It always emits `runFilterToggled()`, which `App.qml:113` answers by
  putting the cursor at 0, and `Panel.qml:100` by scrolling to the top.
- `RunStore.projectFilter` (`""` is All projects) and `toggleProjectFilter(root)`, where `""`
  sets All projects and emits `projectFilterToggled()`.
- `Navigator.showSection("runs")` (`ui/Navigator.qml:173`) works with no project open. It
  returns without doing anything while a modal is open (delete, memory delete, new memory,
  milestone dialog, archive) or a memory draft is dirty. It resets the search.
- Sidebar: `Panel.qml` binds `runsAttention: Runs.attention(appStores.runs.runs).length`;
  `Sidebar.qml` renders it as `navCountRuns` text `‼N` (empty for 0).
- `RunStore.toasts` entries are `{key, id, title, state, reason, project, expiresMs}`;
  `project` is the run's project name, `""` when it is not a string (`RunStore.qml:146-148`,
  `:1356`). `ui/components/RunToast.qml` does not render `project`.
- `Panel.openToastRun(key, runId)` (`Panel.qml:239`): dismisses the toast, calls
  `navi.showSection("runs")`, flashes `This run is no longer in the snapshot` when
  `runById(runId)` is null, else `navi.openRun(runId, "runs")`. `Navigator.openRun` looks
  the id up in the global `app.runs.runs` and does not touch `selectedProject`.

## Behaviour

B1. **The indicator is mounted.** `ui/Panel.qml` mounts one `UI.RunIndicator` in the
    toolbar's first `RowLayout`, as its last item (after `startRunButton`), with
    `theme: panelTheme`. Its `objectName` stays `runIndicator`. It is a descendant of
    `panelToolbar`. It has no `visible` gate of its own in Panel. The component hides itself
    when every count is 0, so it shows in every view mode, with or without a selected
    project, whenever some listed run is running, parked or needs attention. The parent puts
    it "beside `MilestoneJobIndicator`" (line 72). The first toolbar row is the toolbar line
    that has room for a short strip; `MilestoneJobIndicator` keeps its own row underneath.

B2. **Its counts are global.** `running`, `parked` and `attention` are the `live`, `parked`
    and `attention` fields of `Runs.runFilterCounts(appStores.runs.runs)`. Panel computes
    the three counts in one readonly property, so the function runs once per change of
    `runs`. Neither the open project nor the Runs screen's `projectFilter`, `runFilter` or
    search changes these counts. A run of a project that is not registered is not in
    `runs`, so it is not counted (parent line 96).

B3. **A click shows Runs on that chip.** `filterRequested(filter)` calls a new Panel function
    `showRunsFiltered(filter)`:
    1. `navi.showSection("runs")`. If `appStores.nav.viewMode` is not `"runs"` afterwards
       (the navigator refused because a modal is open or a draft is dirty), stop. Nothing
       else changes.
    2. If `appStores.runs.projectFilter !== ""`, call `appStores.runs.toggleProjectFilter("")`
       (All projects). The list then holds what the indicator counted. The parent says
       indicators "cover every registered project" (line 69).
    3. If `appStores.runs.runFilter !== filter`, call `appStores.runs.toggleRunFilter(filter)`.
       When the chip is already `filter`, do NOT toggle: toggling would clear it to All. In
       both cases the chip is `filter` afterwards.
    The click works with no project open and from Run detail (`viewMode "run"` → `"runs"`).

B4. **The sidebar count is global.** No code change: `runsAttention` already reads
    `Runs.attention(appStores.runs.runs)`. Tests pin that the count covers runs of two
    registered projects, and that it shows with no project open.

B5. **Every toast names its project.** `RunToast` gets one `UI.ThemedText` per card,
    `objectName: "runToastProject" + index`, `variant: "caption"`, placed directly under the
    heading (`runToastHeading`) and above the `<title> escalated` line. Its text is exactly
    `textOf(entry.project)` (the project's name, e.g. `beta`, with no prefix and no glyph).
    It is `visible` only when that text is not `""`, so a hidden line takes no height. It
    elides on the right, like the title line. A bad entry (not an object, or `project` not a
    string) renders with the project line hidden and does not throw. The header comment
    (lines 7-17) gets the project line in its list of what a card reads.

B6. **Open keeps the open project.** No change to `openToastRun`. Tests pin that Open on a
    toast for a run of ANOTHER registered project (pA open, the run is pB's) shows Run detail
    for that run (`viewMode "run"`, `selectedRunId` its id), dismisses the toast, and leaves
    `app.projects.selectedProject` the same object (`===`). With no project open it stays
    `null`.

B7. **Docs.** `docs/architecture.md` is updated where it is now wrong. The `RunIndicator`
    entry (line 149) says that Panel mounts it at the end of the toolbar's first row, fed
    `Runs.runFilterCounts` over the global run list, and that a click shows Runs on that
    chip with All projects (instead of "not yet mounted"). The `RunToast` entry (line 152)
    lists the project name line. The paragraph on the run screens (line 165) says that the
    indicator and the sidebar count are global. Contract only, no history.

B8. **Comments.** Every new Panel property or function, and the mount itself, gets a
    contract-only comment in the file's style. There is no narrative. ("not mounted before",
    "this card" and the like are not allowed.)

## Errors and edge cases

| case | behaviour |
|---|---|
| no runs, or only finished ones | the indicator is hidden (component rule); the sidebar count is empty |
| no project open, runs listed | the indicator shows the global counts; its click opens Runs on the chip |
| runs in two projects, one open | the counts are the sum over both; the open project changes nothing |
| `projectFilter` narrowed to one project | the indicator still counts all; its click resets the filter to All projects |
| the indicator's chip is already the active chip | the click keeps that chip (no toggle to All) |
| a modal is open (e.g. delete confirmation) | `showSection` refuses; the click changes neither the view nor the chips |
| clicked from Run detail | the Runs list shows, on the chip |
| toast entry with `project` `""`, missing or not a string | the project line is hidden; the rest of the card renders |
| toast for a run of another project, Open | Run detail of that run; `selectedProject` unchanged |
| toast whose run left the snapshot, Open | existing behaviour: Runs list, flash `This run is no longer in the snapshot` |

## Out of scope

- Any change to `RunIndicator.qml` itself (its look, glyphs, signal or counts clamping), to
  `Navigator`, `RunStore`, `App.qml` or `core/domain/runs.js`.
- The desktop notification text (`RunStore.notify` / `notify.py`). The card asks for the
  project on the toast only.
- An Open project action on toasts or on the indicator (4.4 covers the row action).
- Hiding the indicator in any view mode, or animating it.
- A keyboard shortcut for the indicator.
- The Runs screen's chip counts, which remain project-filtered (`RunsScreen.qml:45`). The
  indicator's counts are global, and the two may differ while a project filter is active.

## Tests

All QML, run by `bash tests/run.sh` (qmltestrunner on a mirrored repo; the runner fails on
any `TypeError` / `ReferenceError` in output), plus `tests/architecture` (pytest: layering,
no duplicated components, icon glyph rules), which must stay green. Tests are written first
and must fail before the code exists.

### `tests/ui/components/tst_run_toast.qml` (component tier)

Why this tier: the project line is a rendering rule of a presentation-only component. Its
stub-free component test isolates it from the store. Extend the `toast(...)` helper with an
optional `project` argument (existing calls keep passing, with no project).

1. `test_each_toast_shows_its_project_under_the_heading`: two toasts, projects `alpha` and
   `beta`. `runToastProject0.text === "alpha"`, `runToastProject1.text === "beta"`, both
   visible; each project line's `y` is greater than its heading's `y` and less than its
   `runToastLine`'s `y`.
2. `test_a_toast_without_a_project_hides_the_project_line`: one toast with project `""` and
   one with `project: 7`. Both project lines are not visible. Their line texts still read
   `<title> escalated`.
3. Extend `test_bad_entries_render_without_throwing_and_keep_dismiss`: the non-object entry's
   `runToastProject0` exists and is not visible.

### `tests/ui/tst_panel_toolbar.qml` (panel tier)

Why this tier: mounting, the bindings to the real stores and the click's navigation can only
be seen on a real `Panel.qml`. The helpers `make()` and `H.find` are already there. Add `pB`
(`/home/u/b`, `beta`). Add a helper that sets `p.app.runs.runs` directly after
`p.app.runs.snapshotRunner.cancel()`, with runs carrying `project: {root, name}` (shape as
in `test_start_run_shows_only_on_the_runs_list`).

4. `test_the_run_indicator_is_mounted_in_the_toolbar_and_hidden_with_no_runs`:
   `H.find(p, "runIndicator")` exists and is under `panelToolbar` (`isUnder`). With
   `runs = []` it is not visible. With one running run it is visible and
   `runIndicatorRunning.text` is `⟳1` (glyph from `runGlyphs.js`, read through the component
   rather than hard-coded if the file's convention requires), and `runIndicator.width > 0`.
5. `test_the_run_indicator_counts_runs_across_two_projects`: registry `[pA, pB]`, pA open.
   Runs (pre-normalized like the existing toolbar test, so state comes from `Runs` rules):
   pA running, pB running, one pB run whose `Runs` state is `parked`, pA escalated, and pB
   dead (status `started` with a lease whose `live` is false, the shape that
   `tst_runs_flow.qml`'s sample counts as dead). Verify each run's state through
   `Runs.runFilterCounts` in the test before asserting on the indicator, so a fixture
   mistake fails loudly. `runIndicator.running === 2`, `parked === 1`, `attention === 2`. After `p.app.runs.toggleProjectFilter(pA.root_path)` the counts are
   unchanged.
6. `test_the_run_indicator_shows_with_no_project_open`: `selectedProject = null`, the same
   runs. Visible, with the same counts, in the view mode the panel is in.
7. `test_clicking_an_indicator_segment_shows_runs_on_that_chip`: on `board`, click
   `runIndicatorParked`. Then `viewMode === "runs"` and `runFilter === "parked"`. Click
   `runIndicatorParked` again: the chip is still `"parked"`. Click `runIndicatorAttention`:
   the chip is `"attention"`. Click `runIndicatorRunning`: the chip is `"live"`.
8. `test_an_indicator_click_resets_the_project_filter_and_works_with_no_project`: no
   project open, `projectFilter` set to pB's root through `toggleProjectFilter`, on Run
   detail of some run (`navigator.openRun(id, "runs")`). Click `runIndicatorRunning`. Then
   `viewMode "runs"`, `runFilter "live"`, `projectFilter ""`, `selectedProject` still
   `null`.
9. `test_an_indicator_click_under_a_modal_changes_nothing`: open the delete confirmation
   (`p.app.deleter.openDelete(pA)`), on `board`, `runFilter ""`. Click the indicator's
   segment through its signal (`runIndicator.filterRequested("parked")`, because the
   backdrop takes mouse clicks). Then `viewMode` is still `board` and `runFilter` is still
   `""`.

### `tests/ui/tst_runs_flow.qml` (flow tier)

Why this tier: the toast and the sidebar count go through the real RunStore snapshot,
arming and alert path into the Panel. Only the end-to-end flow shows that the project name
reaches the card. Add a `snapOkTwo(aEntries, bEntries)` helper whose reply lists
`{root: pA.root_path, ok: true, runs: aEntries}` and `{root: pB.root_path, ok: true, runs:
bEntries}`, plus an entry builder that sets `repo_dir` to pB's root. Register `[pA, pB]`.

10. `test_the_sidebar_count_covers_every_registered_project`: `makeTwo()`-style runs
    with one escalated run in pA and one dead run in pB, pA open: `navCountRuns.text` is
    `‼2`. After `selectedProject = null` it is still `‼2`.
11. `test_each_toast_names_its_project`: `withToast("board")` and
    `runToastProject0.text === "alpha"`. Then, with pB registered, a two-project baseline
    snapshot and a second one where pB's run escalates: the newest toast's
    `runToastProject<i>.text === "beta"`.
12. `test_toast_open_on_another_projects_run_keeps_the_open_project`: pA open, a toast for
    pB's escalated run. Keep `var before = p.app.projects.selectedProject`. Click
    `runToastOpen<i>`. Then `viewMode === "run"`, `selectedRunId` is pB's run id, the toast
    is gone, and `p.app.projects.selectedProject === before`. Back lands on the Runs list.
13. Extend `test_with_no_project_toast_open_shows_the_run`: before Open,
    `runToastProject0.text === "alpha"`; after Open, `selectedProject === null`.

### `tests/architecture` (pytest)

Why this tier: the repo's layering and glyph rules. No new test. They must pass unchanged.
Panel imports no new store, and the project line carries no glyph.

## Review focus (for the planner)

- `toggleRunFilter`'s toggle semantics. A second click on the same segment must not clear
  the chip (test 7).
- The indicator in a `RowLayout`: it needs a non-zero implicit width when visible and must
  not push the breadcrumbs below their `Layout.minimumWidth` on a 900 px panel. Test 4's
  visibility check covers mounting; a manual or geometric check that `runIndicator.width > 0`
  while visible belongs in test 4.
- The counts must not depend on `projectFilter` or `selectedProject` (tests 5, 6).
- A `project` value that is not a string must not throw in `RunToast` (tests 2, 3).
- A refused `showSection` must not leave the chips changed behind a modal (test 9).
