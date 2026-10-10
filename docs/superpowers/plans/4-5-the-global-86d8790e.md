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

---

# 4.5 The global RunIndicator, sidebar count and toast project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every run toast names its project, Panel mounts the `RunIndicator` in its toolbar with counts over every registered project's runs, a click on a segment shows the Runs list on that chip with All projects, and tests pin that the sidebar count and a toast's Open are global and keep the open project.

**Architecture:** `ui/components/RunToast.qml` gains one caption line per card (`runToastProject<i>`) reading `entry.project`. `ui/Panel.qml` gains a readonly `runCounts` (`Runs.runFilterCounts(appStores.runs.runs)`), a `UI.RunIndicator` as the last item of the toolbar's first `RowLayout` bound to it, and a function `showRunsFiltered(filter)` that calls `navi.showSection("runs")`, stops if the navigator refused, resets the project filter to All and sets (never toggles off) the chip. The sidebar count and `openToastRun` already behave globally; flow tests pin them. `docs/architecture.md` is brought in line.

**Tech Stack:** QML (Qt 6 Quick), QtTest via `qmltestrunner`. `bash tests/run.sh [filter]` runs the pytest tier (including `tests/architecture`), then every `tst_*.qml` whose path contains the filter, against a mirrored copy of the repo; it fails on any `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` line in the output.

**Spec:** `docs/superpowers/specs/4-5-the-global-86d8790e.md` (prepended above).

## Global Constraints

- Only these files change: `ui/Panel.qml`, `ui/components/RunToast.qml`, `docs/architecture.md`, `tests/ui/components/tst_run_toast.qml`, `tests/ui/tst_panel_toolbar.qml`, `tests/ui/tst_runs_flow.qml`.
- No change to `ui/components/RunIndicator.qml`, `ui/Navigator.qml`, `core/stores/RunStore.qml`, `App.qml`, `core/domain/runs.js`, or the desktop notification (`RunStore.notify` / `notify.py`).
- The indicator keeps `objectName: "runIndicator"`, gets `theme: panelTheme`, has no `visible` binding in Panel, and is the last item of the toolbar's first `RowLayout` (after `startRunButton`).
- Counts: `running` / `parked` / `attention` are the `live` / `parked` / `attention` fields of ONE readonly Panel property `runCounts: Runs.runFilterCounts(appStores.runs.runs)`.
- `showRunsFiltered(filter)`: `navi.showSection("runs")`; return if `appStores.nav.viewMode !== "runs"`; `toggleProjectFilter("")` only when `projectFilter !== ""`; `toggleRunFilter(filter)` only when `runFilter !== filter`.
- Toast project line: `UI.ThemedText`, `objectName: "runToastProject" + card.index`, `variant: "caption"`, directly under `runToastHeading` and above `runToastLine`, text exactly `stack.textOf(card.entry.project)`, `visible: text !== ""`, `elide: Text.ElideRight`, no prefix, no glyph.
- Comments are contract only, in the file's style: no "not mounted before", "this card", "now" or other history.
- Tests first; each must fail before its code exists. The pins named in Task 4 (and test 9 in Task 3) pass on arrival and say so.
- `tests/architecture` stays green: no new store import in Panel, no new component file, no glyph in the project line.
- `bash tests/run.sh` green at the end.

## Review Focus

1. **A click on the segment whose chip is already active** — the chip stays on that filter instead of toggling to All. Pinned in Task 3 (`test_clicking_an_indicator_segment_shows_runs_on_that_chip`, second click on Parked).
2. **A search typed on the Runs list, then an indicator click** — the list must show every run the indicator counted, so the search is cleared (`showSection` resets it). Pinned in Task 3 (`test_clicking_an_indicator_segment_shows_runs_on_that_chip`, `nav.searchQuery` set to `zzz` before the second click, `""` after).
3. **A toast `project` that is `""`, a number, missing, or the entry not an object** — the project line is hidden and nothing throws. Pinned in Task 1 (`test_a_toast_without_a_project_hides_the_project_line`, extended `test_bad_entries_render_without_throwing_and_keep_dismiss`).
4. **A long project name** — the project line stays one elided line inside the 320 px card instead of wrapping or overflowing. Pinned in Task 1 (`test_a_long_project_name_elides_on_one_line`).
5. **The indicator on a busy toolbar row** — visible with a non-zero width, its right edge inside the toolbar, and it hides again when the runs go away. Pinned in Task 2 (`test_the_run_indicator_is_mounted_in_the_toolbar_and_hidden_with_no_runs`).

(A refused `showSection` behind a modal is test 9, Task 3; counts independent of the project filter and the open project are tests 5 and 6, Task 2.)

---

### Task 1: Every run toast names its project

**Files:**
- Modify: `ui/components/RunToast.qml:7-17` (header comment), `:79-88` (new `ThemedText` after `runToastHeading`)
- Modify: `docs/architecture.md:152` (the `RunToast` entry)
- Test: `tests/ui/components/tst_run_toast.qml` (the `toast` helper, two new tests, one extended test)
- Test: `tests/ui/tst_runs_flow.qml` (new helpers after `withToast`, one new test, one extended test)

**Interfaces:**
- Consumes: `RunStore.toasts` entries `{key, id, title, state, reason, project, expiresMs}` (exists; `project` is the run's project name).
- Produces: per toast card an item `runToastProject<index>` (a `Text`) whose `text` is the entry's `project` when it is a string, else `""`, and which is visible only when that text is not `""`. Flow-test helpers in `tests/ui/tst_runs_flow.qml` used by Task 4: `snapOkTwo(aEntries, bEntries)`, `snapEntryB(id, runStatus, live, milestone)`, `feedTwo(p, aEntries, bEntries)`, `registerB(p)`.

- [ ] **Step 1: Write the failing component tests**

In `tests/ui/components/tst_run_toast.qml`, replace the `toast` helper:

```qml
  // One RunStore toast.
  function toast(key, id, title, state, reason) {
    return { key: key, id: id, title: title, state: state, reason: reason, expiresMs: Date.now() + 8000 }
  }
```

with:

```qml
  // One RunStore toast; `project` is optional (undefined when left out).
  function toast(key, id, title, state, reason, project) {
    return { key: key, id: id, title: title, state: state, reason: reason, project: project,
             expiresMs: Date.now() + 8000 }
  }
```

In `test_bad_entries_render_without_throwing_and_keep_dismiss`, after the line

```qml
    compare(part(c, "runToastReason", 0).visible, false)
```

add:

```qml
    verify(part(c, "runToastProject", 0), "a non-object entry still has its project line")
    compare(part(c, "runToastProject", 0).visible, false)
    compare(part(c, "runToastProject", 1).visible, false, "an entry with no project")
```

Then add these tests at the end of the TestCase (before its closing `}`):

```qml
  // 4.5: the project line
  function test_each_toast_shows_its_project_under_the_heading() {
    var c = make([toast(1, "run-a", "M3", "escalated", "r", "alpha"),
                  toast(2, "run-b", "M4", "dead", "process died", "beta")])
    compare(part(c, "runToastProject", 0).text, "alpha")
    compare(part(c, "runToastProject", 1).text, "beta")
    for (var i = 0; i < 2; i++) {
      var project = part(c, "runToastProject", i)
      compare(project.visible, true)
      verify(project.y > part(c, "runToastHeading", i).y, "under the heading")
      verify(project.y < part(c, "runToastLine", i).y, "above the title line")
    }
    compare(part(c, "runToastLine", 0).text, "M3 escalated")
    compare(part(c, "runToastLine", 1).text, "M4 died")
  }

  function test_a_toast_without_a_project_hides_the_project_line() {
    var c = make([toast(1, "run-a", "A", "escalated", "r", ""),
                  toast(2, "run-b", "B", "escalated", "r", 7)])
    compare(part(c, "runToastProject", 0).visible, false)
    compare(part(c, "runToastProject", 0).text, "")
    compare(part(c, "runToastProject", 1).visible, false, "a project that is not a string")
    compare(part(c, "runToastProject", 1).text, "")
    compare(part(c, "runToastLine", 0).text, "A escalated")
    compare(part(c, "runToastLine", 1).text, "B escalated")
  }

  // Review Focus 4
  function test_a_long_project_name_elides_on_one_line() {
    var name = ""
    for (var i = 0; i < 20; i++) name += "a-very-long-project-name-"
    var c = make([toast(1, "run-a", "A", "escalated", "r", name)])
    var project = part(c, "runToastProject", 0)
    compare(project.text, name)
    compare(project.visible, true)
    compare(project.elide, Text.ElideRight)
    compare(project.truncated, true)
    verify(project.width <= c.width, "inside the card")
    verify(project.height < 2 * part(c, "runToastLine", 0).height, "one line, not wrapped")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_run_toast`
Expected: FAIL in `test_each_toast_shows_its_project_under_the_heading`, `test_a_toast_without_a_project_hides_the_project_line`, `test_a_long_project_name_elides_on_one_line` and `test_bad_entries_render_without_throwing_and_keep_dismiss` (no `runToastProject0`: `part()` returns null, so reading `.text` / `.visible` throws a `TypeError`).

- [ ] **Step 3: Write the failing flow tests**

In `tests/ui/tst_runs_flow.qml`, directly after the `withToast` function (it ends with `return p\n  }`), add:

```qml
  // runs-snapshot-all.py's reply: pA's entry lists `aEntries`, pB's `bEntries`.
  function snapOkTwo(aEntries, bEntries) {
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: aEntries },
                                                 { root: tc.pB.root_path, ok: true, runs: bEntries }],
                            data_dir: "/d" }) + "\n"
  }

  // snapEntry(), in project B.
  function snapEntryB(id, runStatus, live, milestone) {
    var e = snapEntry(id, runStatus, live, milestone)
    e.repo_dir = tc.pB.root_path
    return e
  }

  // The next snapshot of projects A and B.
  function feedTwo(p, aEntries, bEntries) {
    p.app.runs.refresh()
    reply(p.app.runs.snapshotRunner.current, snapOkTwo(aEntries, bEntries), 0)
  }

  // Registers pB beside pA (pA stays open). The registry change launches a
  // snapshot that cannot run here: it is cancelled.
  function registerB(p) {
    p.app.projects.applyProjectsList([pA, pB])
    p.app.runs.snapshotRunner.cancel()
  }

  // 4.5 (11)
  function test_each_toast_names_its_project() {
    var p = withToast("board"); if (!p) return
    compare(H.find(p, "runToastProject0").text, "alpha")
    compare(H.find(p, "runToastProject0").visible, true)
    registerB(p)
    var aEntries = [snapEntry("run-0000000000a1", "started", true, "alpha"),
                    snapEntry("run-0000000000b2", "escalated", null, "beta")]
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "started", true, "zeta")])
    compare(p.app.runs.toasts.length, 1, "beta's first entry only arms it")
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "escalated", null, "zeta")])
    compare(p.app.runs.toasts.length, 2)
    wait(50)
    compare(H.find(p, "runToastLine1").text, "zeta escalated")
    compare(H.find(p, "runToastProject1").text, "beta")
    compare(H.find(p, "runToastProject0").text, "alpha", "the older toast keeps its project")
  }
```

In `test_with_no_project_toast_open_shows_the_run`, replace its opening lines:

```qml
    var p = withToast("board", true); if (!p) return
    compare(p.app.projects.selectedProject, null)
    compare(p.app.nav.viewMode, "board")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.runs.toasts.length, 0, "Open dismisses its toast")
```

with:

```qml
    var p = withToast("board", true); if (!p) return
    compare(p.app.projects.selectedProject, null)
    compare(p.app.nav.viewMode, "board")
    compare(H.find(p, "runToastProject0").text, "alpha")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.runs.toasts.length, 0, "Open dismisses its toast")
    compare(p.app.projects.selectedProject, null, "Open opens no project")
```

- [ ] **Step 4: Run them to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_runs_flow`
Expected: FAIL in `test_each_toast_names_its_project` and `test_with_no_project_toast_open_shows_the_run` (`H.find(p, "runToastProject0")` is null: `TypeError` reading `text`). Every other test in the file passes.

- [ ] **Step 5: Add the project line to RunToast**

In `ui/components/RunToast.qml`, replace the header comment's first paragraph:

```qml
// The run toasts: one card per run that newly needs a human, oldest at the
// top and newest at the bottom, closest to the corner the owner puts it in.
// Each card reads `‼ Run needs you` (or `✖` for a dead run, from runGlyphs.js)
// in `urgent`, `<title> escalated` or `<title> died`, the reason, and Open /
// Dismiss.
```

with:

```qml
// The run toasts: one card per run that newly needs a human, oldest at the
// top and newest at the bottom, closest to the corner the owner puts it in.
// Each card reads `‼ Run needs you` (or `✖` for a dead run, from runGlyphs.js)
// in `urgent`, the run's project name (hidden when `project` is empty or not a
// string), `<title> escalated` or `<title> died`, the reason, and Open /
// Dismiss.
```

Then, between the `runToastHeading` text and the `runToastLine` text, i.e. replace:

```qml
          font.bold: true
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastLine" + card.index
```

with:

```qml
          font.bold: true
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastProject" + card.index
          variant: "caption"
          theme: stack.theme
          width: parent.width
          visible: text !== ""
          text: stack.textOf(card.entry.project)
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastLine" + card.index
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_run_toast`
Expected: PASS, `0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line.

Run: `timeout 900 bash tests/run.sh tst_runs_flow`
Expected: PASS, `0 failed`, no such line.

- [ ] **Step 7: Update the RunToast entry in docs/architecture.md**

In `docs/architecture.md` (line 152, the `RunToast` entry), replace:

```
per toast `‼ Run needs you` or `✖ Run needs you` in `urgent` from `runGlyphs.js`, `<title> escalated` or `<title> died`, the reason, and Open / Dismiss `ActionButton`s;
```

with:

```
per toast `‼ Run needs you` or `✖ Run needs you` in `urgent` from `runGlyphs.js`, the run's project name as a caption line (`runToastProject<i>`, hidden when `project` is empty or not a string), `<title> escalated` or `<title> died`, the reason, and Open / Dismiss `ActionButton`s;
```

- [ ] **Step 8: Commit**

```bash
git add ui/components/RunToast.qml docs/architecture.md tests/ui/components/tst_run_toast.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(run-toast): every run toast names its project under the heading"
```

---

### Task 2: The RunIndicator is mounted with global counts

**Files:**
- Modify: `ui/Panel.qml:235-249` (new `runCounts` property after `openToastRun`), `:532-547` (the indicator after `startRunButton`, inside the first `RowLayout`)
- Test: `tests/ui/tst_panel_toolbar.qml` (two imports, `pB`, helpers, three tests at the end)

**Interfaces:**
- Consumes: `Runs.runFilterCounts(runs)` → `{attention, live, parked, all}` (`core/domain/runs.js:596`, already imported in Panel as `Runs`); `UI.RunIndicator` props `running`, `parked`, `attention`, `theme`, signal `filterRequested(string filter)`.
- Produces: `Panel.runCounts` (readonly `var`, `{attention, live, parked, all}`); an item `runIndicator` under `panelToolbar`. Toolbar-test helpers used by Task 3: `runOf(id, root, name, status, live)`, `setRuns(p, list)`, `twoProjectRuns()`, `makeTwo()`, `widen(p)`, `tap(item)`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_panel_toolbar.qml`, replace the imports:

```qml
import QtQuick
import QtTest
import "../helpers/find.js" as H
```

with:

```qml
import QtQuick
import QtTest
import "../helpers/find.js" as H
import "../../core/domain/runs.js" as Runs
import "../../ui/components/runGlyphs.js" as RG
```

After the `pA` property, add:

```qml
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
```

Then add at the end of the TestCase (before its closing `}`):

```qml
  // ---- the run indicator (4.5)

  // One normalized run of the project at `root` named `name`; `status` and
  // `live` (null: no lease) give its Runs state.
  function runOf(id, root, name, status, live) {
    return { id: id, repo_dir: root, milestone_id: "m-" + id.slice(-2), status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] }, project: { root: root, name: name } }
  }

  // The run list, set directly; a snapshot launched by a registry change or
  // a project switch is cancelled first, so its reply never lands.
  function setRuns(p, list) {
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = list
  }

  // alpha: one running, one escalated. beta: one running, one parked, one dead.
  function twoProjectRuns() {
    return [runOf("run-0000000000a1", pA.root_path, "alpha", "started", true),
            runOf("run-0000000000a2", pA.root_path, "alpha", "escalated", null),
            runOf("run-0000000000b1", pB.root_path, "beta", "started", true),
            runOf("run-0000000000b2", pB.root_path, "beta", "stopped", null),
            runOf("run-0000000000b3", pB.root_path, "beta", "started", false)]
  }

  // make() with pA and pB registered (pA open) and twoProjectRuns().
  function makeTwo() {
    var p = make(); if (!p) return null
    p.app.projects.applyProjectsList([pA, pB])
    setRuns(p, twoProjectRuns())
    return p
  }

  // The test Panel is 380 wide, narrower than the toolbar with the strip.
  function widen(p) {
    var panel = H.find(p, "mainPanel")
    panel.width = 840; panel.height = 600
    wait(50)
  }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item, item.width / 2, item.height / 2)
  }

  function test_the_run_indicator_is_mounted_in_the_toolbar_and_hidden_with_no_runs() {
    var p = make(); if (!p) return
    widen(p)
    var ind = H.find(p, "runIndicator")
    verify(ind, "the run indicator")
    verify(isUnder(ind, "panelToolbar"), "inside the fixed toolbar")
    verify(!isUnder(ind, "panelFlick"), "and not inside the scrolling content")
    setRuns(p, [])
    compare(ind.visible, false, "no runs")
    setRuns(p, [runOf("run-0000000000a1", pA.root_path, "alpha", "started", true)])
    wait(50)
    compare(ind.visible, true)
    var running = H.find(p, "runIndicatorRunning")
    compare(String(running.text), RG.glyphOf("running") + "1")
    compare(String(running.text), "⟳1")
    verify(ind.width > 0, "a visible strip has a width")
    var toolbar = H.find(p, "panelToolbar")
    var right = ind.mapToItem(toolbar, 0, 0).x + ind.width
    verify(right <= toolbar.width + 0.5, "inside the toolbar: right edge " + right + " of " + toolbar.width)
    setRuns(p, [runOf("run-0000000000d4", pA.root_path, "alpha", "done", null)])
    compare(ind.visible, false, "only finished runs")
  }

  function test_the_run_indicator_counts_runs_across_two_projects() {
    var runs = twoProjectRuns()
    var states = runs.map(function(r) { return Runs.runState(r) }).join(",")
    compare(states, "running,escalated,running,parked,dead", "the fixture's states")
    var counts = Runs.runFilterCounts(runs)
    compare(counts.live, 2)
    compare(counts.parked, 1)
    compare(counts.attention, 2)
    var p = makeTwo(); if (!p) return
    compare(p.app.projects.selectedProject.root_path, pA.root_path, "pA is open")
    var ind = H.find(p, "runIndicator")
    compare(ind.visible, true)
    compare(ind.running, 2)
    compare(ind.parked, 1)
    compare(ind.attention, 2)
    p.app.runs.toggleProjectFilter(pA.root_path)
    compare(p.app.runs.projectFilter, pA.root_path, "the Runs list is narrowed to alpha")
    compare(ind.running, 2)
    compare(ind.parked, 1)
    compare(ind.attention, 2)
  }

  function test_the_run_indicator_shows_with_no_project_open() {
    var p = makeTwo(); if (!p) return
    p.app.projects.selectedProject = null
    setRuns(p, twoProjectRuns())
    wait(50)
    var ind = H.find(p, "runIndicator")
    compare(ind.visible, true, "in " + p.app.nav.viewMode)
    compare(ind.running, 2)
    compare(ind.parked, 1)
    compare(ind.attention, 2)
    p.navigator.showSection("runs")
    wait(50)
    compare(ind.visible, true, "on the Runs list")
    compare(ind.running, 2)
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_panel_toolbar`
Expected: FAIL in the three new tests: `verify(ind, "the run indicator")` fails (`runIndicator` is not mounted). The state check at the top of `test_the_run_indicator_counts_runs_across_two_projects` passes before the failure (if it fails, the fixture is wrong, not the code). Every other test in the file passes.

- [ ] **Step 3: Add `runCounts` to Panel**

In `ui/Panel.qml`, directly after the `openToastRun` function (it ends with `navi.openRun(runId, "runs")\n  }`), add:

```qml

  // The toolbar RunIndicator's counts: Runs.runFilterCounts over every
  // registered project's runs, whatever project is open and whatever the
  // Runs list's project filter, chip or search.
  readonly property var runCounts: Runs.runFilterCounts(appStores.runs.runs)
```

- [ ] **Step 4: Mount the indicator**

In `ui/Panel.qml`, replace the end of `startRunButton` and of the first `RowLayout`:

```qml
            onClicked: root.openRunsDispatch("board")
          }
        }
```

with:

```qml
            onClicked: root.openRunsDispatch("board")
          }

          // The am run strip, last in the row, over every registered project's
          // runs (runCounts), with or without an open project and in every view;
          // it hides itself while no run is running, parked or needs attention.
          UI.RunIndicator {
            objectName: "runIndicator"
            theme: panelTheme
            running: root.runCounts.live
            parked: root.runCounts.parked
            attention: root.runCounts.attention
          }
        }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_panel_toolbar`
Expected: PASS, `0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line.

- [ ] **Step 6: Run the other Panel suites**

Run: `timeout 900 bash tests/run.sh tests/ui/tst_`
Expected: PASS for every `tests/ui/tst_*.qml` file, `0 failed` each, no such line (the extra toolbar item must not break the existing toolbar, runs-flow or panel tests).

- [ ] **Step 7: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_panel_toolbar.qml
git commit -m "feat(panel): mount the RunIndicator in the toolbar with counts over every registered project"
```

---

### Task 3: An indicator click shows Runs on that chip with All projects

**Files:**
- Modify: `ui/Panel.qml` (new `showRunsFiltered` function after `runCounts`; `onFilterRequested` on the indicator)
- Modify: `docs/architecture.md:149` (the `RunIndicator` entry), `:165` (the run screens paragraph)
- Test: `tests/ui/tst_panel_toolbar.qml` (three tests at the end)

**Interfaces:**
- Consumes: `Panel.runCounts`, the `runIndicator` item and the toolbar-test helpers `setRuns`, `twoProjectRuns`, `makeTwo`, `widen`, `tap` (Task 2); `navi.showSection(name)` (refuses silently under a modal or a dirty draft); `RunStore.projectFilter`, `toggleProjectFilter(root)`, `runFilter`, `toggleRunFilter(id)` (toggles: the active id or `"all"` sets `""`).
- Produces: `Panel.showRunsFiltered(filter: string)` → no return value.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_panel_toolbar.qml`, add at the end of the TestCase (before its closing `}`):

```qml
  // Review Focus 1, 2
  function test_clicking_an_indicator_segment_shows_runs_on_that_chip() {
    var p = makeTwo(); if (!p) return
    widen(p)
    p.navigator.showSection("board")
    wait(50)
    compare(p.app.runs.runFilter, "")
    tap(H.find(p, "runIndicatorParked"))
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.runFilter, "parked")
    wait(50)
    p.app.nav.searchQuery = "zzz"
    tap(H.find(p, "runIndicatorParked"))
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.runFilter, "parked", "the active chip is kept, not toggled to All")
    compare(p.app.nav.searchQuery, "", "the search is cleared, so the list holds what was counted")
    tap(H.find(p, "runIndicatorAttention"))
    compare(p.app.runs.runFilter, "attention")
    tap(H.find(p, "runIndicatorRunning"))
    compare(p.app.runs.runFilter, "live")
    compare(p.app.projects.selectedProject.root_path, pA.root_path, "the open project is kept")
  }

  function test_an_indicator_click_resets_the_project_filter_and_works_with_no_project() {
    var p = makeTwo(); if (!p) return
    widen(p)
    p.app.projects.selectedProject = null
    setRuns(p, twoProjectRuns())
    p.navigator.showSection("runs")
    p.app.runs.toggleProjectFilter(pB.root_path)
    compare(p.app.runs.projectFilter, pB.root_path)
    p.navigator.openRun("run-0000000000b1", "runs")
    compare(p.app.nav.viewMode, "run")
    wait(50)
    tap(H.find(p, "runIndicatorRunning"))
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.runFilter, "live")
    compare(p.app.runs.projectFilter, "", "All projects, as the indicator counts")
    compare(p.app.projects.selectedProject, null)
  }

  // A pin: passes before showRunsFiltered exists (nothing handles the
  // signal yet) and must keep passing after it.
  function test_an_indicator_click_under_a_modal_changes_nothing() {
    var p = makeTwo(); if (!p) return
    p.navigator.showSection("board")
    compare(p.app.runs.runFilter, "")
    p.app.deleter.openDelete(pA)
    verify(p.app.deleter.deleteTarget, "the delete confirmation is open")
    // The backdrop takes mouse clicks, so the segment is asked through its signal.
    H.find(p, "runIndicator").filterRequested("parked")
    compare(p.app.nav.viewMode, "board")
    compare(p.app.runs.runFilter, "")
    compare(p.app.runs.projectFilter, "")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_panel_toolbar`
Expected: FAIL in `test_clicking_an_indicator_segment_shows_runs_on_that_chip` (`viewMode` is still `board`) and `test_an_indicator_click_resets_the_project_filter_and_works_with_no_project` (`viewMode` is still `run`). `test_an_indicator_click_under_a_modal_changes_nothing` passes (a pin). Every other test passes.

- [ ] **Step 3: Add `showRunsFiltered` to Panel**

In `ui/Panel.qml`, directly after the `runCounts` property added in Task 2, add:

```qml

  // A RunIndicator segment: the Runs list over every registered project (All
  // projects), on that segment's chip -- "live", "parked" or "attention". The
  // chip is set, never toggled off: a click on the active chip keeps it.
  // Nothing changes while the navigator refuses the section (a modal is open
  // or a memory draft is dirty).
  function showRunsFiltered(filter) {
    navi.showSection("runs")
    if (appStores.nav.viewMode !== "runs") return
    if (appStores.runs.projectFilter !== "") appStores.runs.toggleProjectFilter("")
    if (appStores.runs.runFilter !== filter) appStores.runs.toggleRunFilter(filter)
  }
```

- [ ] **Step 4: Connect the indicator's click**

In `ui/Panel.qml`, replace the indicator mounted in Task 2:

```qml
          // The am run strip, last in the row, over every registered project's
          // runs (runCounts), with or without an open project and in every view;
          // it hides itself while no run is running, parked or needs attention.
          UI.RunIndicator {
            objectName: "runIndicator"
            theme: panelTheme
            running: root.runCounts.live
            parked: root.runCounts.parked
            attention: root.runCounts.attention
          }
```

with:

```qml
          // The am run strip, last in the row, over every registered project's
          // runs (runCounts), with or without an open project and in every view;
          // it hides itself while no run is running, parked or needs attention.
          // A segment shows the Runs list on its chip (showRunsFiltered).
          UI.RunIndicator {
            objectName: "runIndicator"
            theme: panelTheme
            running: root.runCounts.live
            parked: root.runCounts.parked
            attention: root.runCounts.attention
            onFilterRequested: function(filter) { root.showRunsFiltered(filter) }
          }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_panel_toolbar`
Expected: PASS, `0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line.

- [ ] **Step 6: Update docs/architecture.md**

In the `RunIndicator` entry (line 149), replace:

```
`RunIndicator` (a toolbar run strip built to sit beside `MilestoneJobIndicator`, not yet mounted -- `Panel`'s toolbar carries only `MilestoneJobIndicator`: one `ActionButton`
```

with:

```
`RunIndicator` (the toolbar's run strip, beside `MilestoneJobIndicator`: one `ActionButton`
```

and, at the end of the same entry, replace:

```
`all` being emitted by no segment),
```

with:

```
`all` being emitted by no segment; `Panel` mounts it as `runIndicator`, the last item of the toolbar's first row, fed the `live` / `parked` / `attention` of `Runs.runFilterCounts` over the global run list (`runCounts`), and a click shows the Runs list on that chip with All projects),
```

In the run screens paragraph (line 165), replace:

```
stays on the list and flashes `This run is no longer in the snapshot`. `BoardScreen`
```

with:

```
stays on the list and flashes `This run is no longer in the snapshot`; Open never changes the open project. The toolbar's `runIndicator` and the sidebar's Runs count read the global run list -- every registered project's runs, with or without an open project, whatever the Runs list's project filter, chip or search -- so they may differ from the Runs chips' counts while a project filter is active. A click on an indicator segment (`showRunsFiltered`) shows the Runs list with All projects and that segment's chip set, never toggled off; while the navigator refuses the section it changes nothing. `BoardScreen`
```

Check that each `old` string above occurs exactly once: `grep -c 'not yet mounted' docs/architecture.md` → `1` before, `0` after; `grep -c 'Open never changes the open project' docs/architecture.md` → `1` after.

- [ ] **Step 7: Commit**

```bash
git add ui/Panel.qml docs/architecture.md tests/ui/tst_panel_toolbar.qml
git commit -m "feat(panel): a RunIndicator segment shows the Runs list on its chip with All projects"
```

---

### Task 4: Pin the global sidebar count and a toast's Open across projects

**Files:**
- Test: `tests/ui/tst_runs_flow.qml` (two tests, after `test_each_toast_names_its_project`)

**Interfaces:**
- Consumes: `runIn(id, status, live, milestone, root, name)` (exists), `snapEntry`, and Task 1's `registerB(p)`, `snapEntryB(id, runStatus, live, milestone)`, `feedTwo(p, aEntries, bEntries)`; `runToastProject<i>` (Task 1).
- Produces: nothing new.

Both tests are pins of existing behaviour (B4, B6): they pass on arrival, because `runsAttention` already reads the global list and `openToastRun` never touches `selectedProject`. To see each one can fail, temporarily change `Runs.attention(appStores.runs.runs).length` in `ui/Panel.qml` to `0` (test 10 must fail), and temporarily add `appStores.projects.selectedProject = null` as the first line of `openToastRun` (test 12 must fail); revert both before committing.

- [ ] **Step 1: Write the pin tests**

In `tests/ui/tst_runs_flow.qml`, directly after `test_each_toast_names_its_project`, add:

```qml
  // 4.5 (10), a pin
  function test_the_sidebar_count_covers_every_registered_project() {
    var p = make(); if (!p) return
    registerB(p)
    p.app.runs.runs = [runIn("run-0000000000b2", "escalated", null, "beta-ms", "/home/u/a", "alpha"),
                       runIn("run-0000000000f6", "started", false, "zeta", "/home/u/b", "beta")]
    wait(50)
    var count = H.find(p, "navCountRuns")
    verify(count, "the Runs count")
    compare(String(count.text), "‼2", "alpha's escalated run and beta's dead one")
    p.app.projects.selectedProject = null
    wait(50)
    compare(p.app.runs.runs.length, 2, "closing the project leaves the runs alone")
    compare(String(count.text), "‼2", "with no project open")
    compare(count.visible, true)
  }

  // 4.5 (12), a pin
  function test_toast_open_on_another_projects_run_keeps_the_open_project() {
    var p = make(); if (!p) return
    registerB(p)
    var before = p.app.projects.selectedProject
    verify(before !== null && before.root_path === "/home/u/a", "pA is open")
    var aEntries = [snapEntry("run-0000000000a1", "started", true, "alpha")]
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "started", true, "zeta")])
    compare(p.app.runs.toasts.length, 0, "the baseline raises nothing")
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "escalated", null, "zeta")])
    compare(p.app.runs.toasts.length, 1)
    wait(50)
    compare(H.find(p, "runToastProject0").text, "beta")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f6")
    compare(p.app.runs.toasts.length, 0, "Open dismisses its toast")
    verify(p.app.projects.selectedProject === before, "the same project object")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
    verify(p.app.projects.selectedProject === before)
  }
```

- [ ] **Step 2: Run them and check they can fail**

Run: `timeout 900 bash tests/run.sh tst_runs_flow`
Expected: PASS, `0 failed` (pins).

Then make the two temporary breaks described above, run `timeout 900 bash tests/run.sh tst_runs_flow` again and confirm `test_the_sidebar_count_covers_every_registered_project` and `test_toast_open_on_another_projects_run_keeps_the_open_project` FAIL. Revert both breaks: `git diff --stat ui/Panel.qml` must print nothing.

- [ ] **Step 3: Run the whole suite**

Run: `timeout 1800 bash tests/run.sh`
Expected: exit status 0; pytest (including `tests/architecture`) passes; every `== tests/...` block prints `Totals: ... 0 failed`; no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` line.

- [ ] **Step 4: Commit**

```bash
git add tests/ui/tst_runs_flow.qml
git commit -m "test(runs-flow): the sidebar count and a toast's Open hold across registered projects"
```
<!-- task-pipeline: validated -->
