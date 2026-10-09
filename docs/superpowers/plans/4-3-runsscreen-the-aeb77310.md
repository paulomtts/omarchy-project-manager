# 4.3 RunsScreen: the project filter chips — design

Card `aeb77310`, a subtask of story `63a11d2f` ("Global runs UI"), blocked by `8c17d03f`
(4.2, the grouped list — done on this branch). Parent spec:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below: **parent**).

`ui/screens/RunsScreen.qml` draws the grouped list and the status chips (Needs attention /
Live / Parked / All) but has no way to choose a project: `app.runs.projectFilter` is only
read. This subtask adds a row of **project chips** above the status chips, makes clicking
one go through the store's `toggleProjectFilter`, and makes the status-chip counts apply
within the project filter. The store already owns the filter's state and its rules
(`toggleProjectFilter`, `isFilterable`, `keepProjectFilter`, reset on panel close, cursor
home via `projectFilterToggled`); nothing in `core/` changes.

## Inherited constraints

| constraint | source |
|---|---|
| Chips: `All projects`, `This project` when a project is open, one chip per project that has runs | parent L53-54 |
| The choice survives section switches, resets to `All projects` when the panel closes, is never persisted; a project switch does not touch it | parent L54-56 (store-owned: `core/stores/RunStore.qml:70-77`) |
| With one project selected the list is flat (no group header) | parent L56-57 (built in 4.2, `RunsScreen.qml:104-111`) |
| A filtered project that leaves the registry, or has no runs any more, falls back to `All projects` | parent L57-58, L170 (store-owned: `RunStore.qml:337-349`) |
| `project` keeps its meaning, the open project's root (`""` when none); the `This project` chip reads it | parent L130-132 |
| The status filters apply across groups | parent L48-49 |
| UI tests cover the chips and their default | parent L190-191 |
| Group/chip order follows `Runs.groupByProject` (attention first, then live, then name case-blind, then root) | parent L46-48; `core/domain/runs.js:395-447` |
| Screens read `app.*` and never import `core/stores`; reuse `ChipRow` / `Chip`; no duplicated components; icon glyph rules | card; `docs/architecture.md`; `tests/architecture/test_layers.py`, `test_icon_glyphs.py` |
| Docstrings and comments state the contract only, no narrative | card |
| Tests first; `bash tests/run.sh` green | card |

## Store surface the screen reads (all on `app.runs`, already present)

| member | shape | meaning |
|---|---|---|
| `runs` | `run[]` | every listed run of every usable registered root, each tagged `project: {root, name}` (root with trailing `/` removed) — NOT narrowed by any chip, the search or the project filter |
| `project` | string | the open project's root; `""` when none is open (`RunStore.qml:42`) |
| `projectFilter` | string | `""` = All projects, else a filterable root, trailing `/` removed (`RunStore.qml:74`) |
| `toggleProjectFilter(root)` | function | `""` or the active root again → All; a root that is not filterable → All; emits `projectFilterToggled` once (`RunStore.qml:304-312`) |
| `groups`, `filteredRuns`, `runFilter`, `toggleRunFilter` | | unchanged (4.2) |

**Root matching.** `project` may carry trailing `/`; wherever this spec compares it with a
run's `project.root` or with `projectFilter`, it is compared through the screen's existing
`rootKey()` (`RunsScreen.qml:71-79`), the same rule `Runs.withProject` applies. A `project`
that is not a string is treated as `""`.

## Behavior

### C1. The project chip set

The project chip row is a `UI.ChipRow` named `runProjectChips`, chip prefix
`runProjectChip`, chip tint `theme.dim` (as the status chips). Its chips, in order:

1. **All projects** — id `all`, label `All projects`, **no count**.
2. **This project** — only when `rootKey(app.runs.project) !== ""`. Id `this`, label
   `This project`, count = the number of runs in `app.runs.runs` whose `project.root`
   equals `rootKey(app.runs.project)` (0 when it has none — the chip still shows).
3. **One chip per project that has runs**, in the order of
   `Runs.groupByProject(app.runs.runs)`, skipping the group whose root is `""` and
   skipping the open project's group (the `This project` chip stands for it; a project is
   never listed twice). Id = the group's `project.root`; label = `project.name`, or the
   root when the name is `""`; count = that group's run count (`runs.length`).

Chip text follows `ChipRow`: `<label> <count>` when there is a count, `<label>` otherwise.
So the chip objectNames are `runProjectChipall`, `runProjectChipthis` and
`runProjectChip<root>` (e.g. `runProjectChip/home/u/b`).

Every count here is a total over `app.runs.runs`: the status chip, the search and the
project filter never change a project chip's count, and a project chip never disappears
because a status chip or search hides its runs.

### C2. When the row shows

The row is visible exactly when all of:

- am is not missing (`amStatus !== "missing"`; the status chips hide then too), and
- either a project is open (`rootKey(app.runs.project) !== ""`), or **more than one**
  project (non-`""` root) has runs in `app.runs.runs`.

So: one project with runs and none open → hidden; no runs and none open → hidden; one
project with runs and a project open → shown (`All projects`, `This project`, and the
named chip when the open project is not that project); any project open with no runs
anywhere → shown (`All projects`, `This project 0`).

The row sits in the screen's column **above** the status chip row (`runChips`) and below
the banners (`runsSchemaBanner`, `runsStaleBanner`, `runsWarning`).

### C3. The active chip

| `projectFilter` | active chip |
|---|---|
| `""` (the default) | `all` |
| equal to `rootKey(app.runs.project)` (and that is not `""`) | `this` |
| any other root | the chip whose id is that root |

Exactly one chip is active at a time. A filter whose root has no chip on screen (cannot
happen with the real store, which falls back) leaves no chip active and must not throw.

### C4. Clicking

Clicking a chip calls `app.runs.toggleProjectFilter(target)` exactly once, where target is
`""` for `all`, `app.runs.project` for `this`, and the chip's id (the root) for a project
chip. The screen sets nothing itself; the store decides the outcome:

- a project chip → that project is the filter; the list goes flat (4.2's B3); clicking the
  same (now active) chip again → All projects, grouped again;
- `All projects` → All projects;
- `This project` with no runs → stays/returns to All projects (the store's
  non-filterable rule).

The cursor going home on a toggle is App's (`projectFilterToggled`; covered by
`tst_app_runs.qml:169`), not the screen's.

### C5. Status chips within the project filter

The status-chip counts (`Needs attention N`, `Live N`, `Parked N`) count the runs of
`Runs.filterByProject(app.runs.runs, app.runs.projectFilter)` — the filtered project's
runs only, or every run under All projects. They still ignore the search
(`test_the_chip_counts_ignore_the_search` keeps passing). The status chip and the project
filter compose: the rows are those past both (the store's `groups` already does this).

### C6. Fallback

When the filtered project vanishes (its runs are all gone or it leaves the registry) the
store sets `projectFilter` back to `""`. The screen then shows: `All projects` active, the
vanished project's chip gone, the list grouped again with headers, and the status counts
over every run. No screen-side logic beyond C1-C5 is needed; the test proves the screen
follows.

### C7. Contract comment

`RunsScreen.qml`'s header comment gains one sentence of contract: a project chip row
(All projects, This project when one is open, one chip per project with runs, with run
counts) above the status chips, hidden when only one project has runs and none is open;
the status chips count within the project filter.

## Object names (new)

| name | item |
|---|---|
| `runProjectChips` | the project `ChipRow` |
| `runProjectChipall` | All projects |
| `runProjectChipthis` | This project |
| `runProjectChip<root>` | a project's chip, root without trailing `/` |

## Edge cases

| case | behaviour |
|---|---|
| `app.runs.project` carries a trailing `/` (`"/home/u/a/"`) | `This project` counts `/home/u/a`'s runs; alpha has no named chip; `This project` is active when `projectFilter` is `/home/u/a` |
| `app.runs.project` is `undefined` / not a string | treated as no project open; no `This project` chip; no throw |
| the open project has no runs | `This project 0` shows; clicking it calls `toggleProjectFilter` and the store keeps All |
| two projects, names differing only in case ("beta", "Alpha") | chip order is that of `groupByProject` (attention, live, then name case-blind) |
| a project whose `name` is `""` | its chip label is the root |
| runs with no project (root `""`) | no chip for them; they count in no project chip and do not count toward "more than one project" |
| a status chip hides every run of a project | that project's chip stays, with its full count |
| am missing | `runProjectChips` hidden |
| am schema mismatch / stale / error | the row follows C2 like the status chips (the status chips stay visible in these states) |

## Out of scope

- Any change to `core/` (`RunStore`, `runs.js`, `App`): the filter's state, the toggle
  rules, the fallback, the reset on panel close and the cursor going home are already
  built and tested in the store/app tiers.
- `FilterableList`, `ChipRow`, `Chip` (reused unchanged).
- The **Open project** row action (4.4); `RunIndicator`, the sidebar count, the toast's
  project name (4.5); `docs/architecture.md` / README wording (4.6).
- Keyboard selection of project chips (no key is specified for it).

## Tests

Tier rationale: **screen tier** (`tests/ui/screens/tst_runs_screen.qml`) mounts
`RunsScreen` alone with a stub run store and a recorder navigator — the right place for
which chips render, their text, which is active, what a click asks of the store, and how
the screen follows a filter change. The store's own toggle/fallback rules are already
proven in `tests/core/stores/tst_run_store.qml` and the cursor reset in
`tst_app_runs.qml`; repeating them here would test the stub. **Architecture tier**
(`tests/architecture`, existing, pytest) guards that no component was duplicated; no new
test there.

### Stub changes (screen tier)

`runsC` gains, mirroring the real store:

- `property var project: ""` (a `var`, not a `string`: test 14 assigns `undefined` and a number, which a string property rejects)
- `property var projectToggles: []` — records each `toggleProjectFilter` argument.
- `function toggleProjectFilter(root)`: records `root`; `want` = root with trailing `/`
  removed; `next` = `""` when `want` is `""` or equals `projectFilter`, else `want`;
  `projectFilter` = `next` when some run in `runs` has `project.root === next`, else `""`.
- `onRunsChanged`: when `projectFilter !== ""` and no run in `runs` has that root,
  `projectFilter = ""` (the store's `keepProjectFilter`).

Existing tests keep their untagged `sample()` runs (no project → no project chips, row
hidden) and `project` defaults to `""`, so none of them changes.

### New / changed tests

| # | test | tier | proves |
|---|---|---|---|
| 1 | `test_project_chips_without_an_open_project` | screen | `twoProjects()`, `project ""` → `runProjectChips` visible; `runProjectChipall` text `All projects`; `runProjectChip/home/u/a` text `alpha 2`; `runProjectChip/home/u/b` text `beta 1`; no `runProjectChipthis`; alpha's chip is left of / before beta's (group order) |
| 2 | `test_an_open_project_adds_this_project_in_place_of_its_own_chip` | screen | `project "/home/u/a/"` → `runProjectChipthis` text `This project 2`; no `runProjectChip/home/u/a`; `runProjectChip/home/u/b` text `beta 1` |
| 3 | `test_all_projects_is_the_default` | screen | with `projectFilter ""`, `runProjectChipall.active` true, every other chip inactive |
| 4 | `test_the_row_hides_with_one_project_and_none_open` | screen | one project's runs, `project ""` → `runProjectChips` not visible; set `project` to that root → visible with `All projects` and `This project N`; untagged runs, `project ""` → hidden; no runs, `project` set → visible with `This project 0` |
| 5 | `test_a_project_chip_filters_and_clicking_it_again_returns_to_all` | screen | tap `runProjectChip/home/u/b` → `projectToggles` is `["/home/u/b"]`, that chip active, `runGroup0` null, `runRowId0` is `…live0003`, `runRow1` null; tap it again → `projectFilter ""`, `all` active, `runGroup0` back |
| 6 | `test_all_projects_and_this_project_ask_the_store` | screen | with a filter on b, tap `runProjectChipall` → toggle arg `""`, filter `""`; with `project "/home/u/a"`, tap `runProjectChipthis` → toggle arg `"/home/u/a"`, `this` active, rows are alpha's only |
| 7 | `test_this_project_with_no_runs_stays_on_all` | screen | `project "/home/u/c"` (no runs) → `This project 0`; tap it → one toggle call with `"/home/u/c"`, `all` still active, list still grouped |
| 8 | `test_status_chip_counts_apply_within_the_project_filter` | screen | `twoProjects()`: under All, `Needs attention 2`, `Live 1`; filter b → `Needs attention 0`, `Live 1`, `Parked 0`; filter a → `Needs attention 2`, `Live 0` |
| 9 | `test_a_status_chip_and_the_project_filter_compose_and_project_counts_stay_whole` | screen | filter a, then status chip `live` → no rows and `No Live runs.`; status `attention` under All → `runProjectChip/home/u/b` still shows `beta 1` |
| 10 | `test_a_vanished_filtered_project_falls_back_to_all_projects` | screen | filter b; replace `runs` with alpha's runs only → `projectFilter ""`, `runProjectChipall` active, `runProjectChip/home/u/b` gone, headers back (`runGroup0` is alpha), counts over every run |
| 11 | `test_the_project_chips_sit_above_the_status_chips` | screen | `topOf(runProjectChips) < topOf(runChips)` |
| 12 | `test_missing_am_hides_the_project_chips` | screen | `twoProjects()`, `amStatus "missing"` → `runProjectChips` not visible |
| 13 | `test_project_chip_labels_fall_back_to_the_root_and_follow_group_order` | screen | four projects: "gamma" `/home/u/g` (one done run), "Alpha" `/home/u/a` (live), "beta" `/home/u/b` (escalated), `name ""` `/home/u/n` (one parked run) → chip order beta, Alpha, `/home/u/n`, gamma (attention, live, then name case-blind with `""` first); the nameless chip's text is `/home/u/n 1` |
| 14 | `test_a_non_string_project_shows_no_this_chip_and_does_not_throw` | screen | `project` set to `undefined` (or a number) → no `runProjectChipthis`; chips as in #1 |

All existing tests in `tst_runs_screen.qml` stay green unchanged. Verification:
`bash tests/run.sh` green (it runs `tests/architecture` pytest first). A single file:
`bash tests/run.sh tst_runs_screen`.

## Notes for the planner

- Build the chip model in the screen as a `readonly property var` of scalar-only objects
  (`{id, label, count?, tint}`; `ChipRow`'s `Repeater` converts nested values), derived
  from `Runs.groupByProject(screen.app.runs.runs)` — not from `app.runs.groups`, which is
  already narrowed by the status chip, the search and the project filter. No new domain
  function is needed.
- The `ChipRow` goes directly in `RunsScreen`'s `Column`, before the `UI.FilterableList`;
  `FilterableList` stays unchanged. `onChosen` maps the id to a target root (C4) and calls
  `screen.app.runs.toggleProjectFilter(target)`.
- `counts` (`RunsScreen.qml:38`) becomes
  `Runs.runFilterCounts(Runs.filterByProject(screen.app.runs.runs, screen.app.runs.projectFilter))`.
- The tap helper (`tap()`, 450 ms wait) must be used for every click; the test window is
  500 px wide, so three or four chips fit, but long root labels may wrap — `ChipRow` is a
  `Flow`, which is fine; tests find chips by name, not position, except #11 and #1's order
  (compare `x`/`y` via `mapToItem`, or check the model order).

---

# 4.3 RunsScreen: the project filter chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project chip row (All projects / This project / one chip per project with runs) above the Runs screen's status chips, route clicks through `app.runs.toggleProjectFilter`, and make the status-chip counts count within the project filter.

**Architecture:** Everything is in `ui/screens/RunsScreen.qml`. The screen derives a scalar-only chip model from `Runs.groupByProject(app.runs.runs)` (never from `app.runs.groups`, which the status chip, the search and the project filter already narrow) and puts a `UI.ChipRow` straight into its `Column`, before the existing `UI.FilterableList`. The store owns the filter's state and every rule; the screen only reads `projectFilter`/`project` and calls `toggleProjectFilter`. Tests are screen-tier, in `tests/ui/screens/tst_runs_screen.qml`, against a stub run store that gains `project`, `toggleProjectFilter` and the store's fallback.

**Tech Stack:** QML (Qt 6 Quick), QtTest via `qmltestrunner`, the pure-JS domain module `core/domain/runs.js`; `bash tests/run.sh` runs the pytest architecture tier, then every `tst_*.qml`.

**Spec:** `docs/superpowers/specs/4-3-runsscreen-the-aeb77310.md` (prepended above).

## Global Constraints

- Nothing in `core/` changes (`RunStore`, `runs.js`, `App`); `FilterableList`, `ChipRow`, `Chip` are reused unchanged.
- Screens read `app.*` and never import `core/stores`; reuse `UI.ChipRow`; no duplicated components (`tests/architecture/test_layers.py`, `test_icon_glyphs.py`).
- Object names exactly: `runProjectChips` (the row), chip prefix `runProjectChip`, so `runProjectChipall`, `runProjectChipthis`, `runProjectChip<root>` (root without trailing `/`).
- Chip wording exactly: `All projects` (no count), `This project <n>`, `<name> <n>` (or `<root> <n>` when the name is `""`). Chip tint `theme.dim`.
- Root comparisons go through the screen's existing `rootKey()`; a `project` that is not a string is treated as `""`.
- Docstrings and comments state the contract only, no narrative.
- Tests first; every click in tests goes through `tap()`; `bash tests/run.sh` green. All existing tests in `tst_runs_screen.qml` stay green unchanged.

## Review Focus

1. **Many projects** — with six long-named projects the chip row wraps onto several lines; the status chips stay visible and below it, no chip off the right edge. Test: Task 1, `test_many_project_chips_wrap_and_keep_the_status_chips_below`.
2. **A new snapshot reorders the groups while a project filter is on** — the chip order follows the new group order and the filtered project's chip stays the active one (identity by root, not by position). Test: Task 2, `test_a_new_snapshot_reorders_the_chips_and_the_active_one_stays_active`.
3. **A search is typed** — the project chips keep every project and full counts even when a project's runs are all searched out, and the status counts under a project filter ignore the search. Test: Task 3, `test_the_search_changes_neither_project_chips_nor_status_counts`.
4. **The user opens the project that is already the filter** — that project is listed once, as `This project`, which becomes the active chip; closing it gives the named chip back, still active. Test: Task 2, `test_opening_the_filtered_project_moves_the_active_chip_to_this_project`.
5. **Runs with no project mixed with tagged runs** — they get no chip, count in the status chips under All projects and not under a project filter. Test: Task 3, `test_runs_without_a_project_count_under_all_projects_only`.

---

## File Structure

- Modify: `ui/screens/RunsScreen.qml` — header comment (C7); new properties `openRoot`, `allGroups`, `projectsWithRuns`, `projectChips`; new functions `projectsIn`, `projectChipsOf`, `activeProjectChipOf`, `chooseProject`; the `UI.ChipRow` named `runProjectChips` between `runsWarning` and the `UI.FilterableList`; `counts` narrowed by the project filter.
- Modify: `tests/ui/screens/tst_runs_screen.qml` — the `runsC` stub gains `project`, `projectToggles`, `toggleProjectFilter`, `hasRoot`, `onRunsChanged`; two helpers `projectChipIds`, `projectChipText`; a new `// ---- project chips (4.3)` section of tests at the end of the file (before the `TestCase`'s closing `}`).

Running the tests: `bash tests/run.sh tst_runs_screen` runs the pytest tier, then only `tests/ui/screens/tst_runs_screen.qml`. A failing QML test prints `FAIL!  : RunsScreen::<test name>() ...` followed by a `Loc:` line; a `TypeError` line also makes the script fail. A green run ends with `Totals: N passed, 0 failed, ...` and exit status 0.

---

### Task 1: The project chip set, when it shows, and where it sits

Covers spec C1, C2, C7 (chip-row sentence), tests 1, 2, 4, 11, 12, 13, 14, Review Focus 1.

**Files:**
- Modify: `ui/screens/RunsScreen.qml:10-20` (header comment), `:38-41` (new properties after `noProjects`), `:92-93` (new functions after `projectError`), `:184-186` (the `UI.ChipRow` between `runsWarning` and `UI.FilterableList`)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stub `runsC` at lines 24-72; helpers after `topOf` at line 136; new tests at the end)

**Interfaces:**
- Consumes: `Runs.groupByProject(runs)` → `[{ project: { root, name }, runs, counts }]` (attention, live, then name case-blind, then root; root `""` group last); the screen's `rootKey(path)`, `sizeOf(list)`, `amMissing`; `UI.ChipRow { model: [{ id, label, count?, tint }], chipPrefix, active, signal chosen(string id) }`.
- Produces (used by Tasks 2 and 3):
  - `readonly property string openRoot` — `rootKey(app.runs.project)`.
  - `readonly property var allGroups` — `Runs.groupByProject(app.runs.runs)`.
  - `readonly property int projectsWithRuns`.
  - `readonly property var projectChips` — `[{ id, label, count?, tint }]`.
  - `function projectsIn(groups) -> int`, `function projectChipsOf(groups, open) -> array`.
  - Item `UI.ChipRow { objectName: "runProjectChips" }`.
  - Stub (test side): `project` (var), `projectToggles` (array), `toggleProjectFilter(root)`, `hasRoot(root) -> bool`, `onRunsChanged` fallback. Test helpers `projectChipIds(s) -> string` (ids joined by `,`), `projectChipText(s, id) -> string | null`.

- [ ] **Step 1: Extend the stub run store**

In `tests/ui/screens/tst_runs_screen.qml`, inside `Component { id: runsC; QtObject { id: rs ... } }`, directly after the line

```qml
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
```

insert:

```qml
      // The open project's root ("" = none) and the project filter's toggle,
      // as the real store has them: toggleProjectFilter records its argument;
      // "", or the active root again, means All; a root no run has means All.
      // A `var`, not a `string`: a test assigns undefined and a number.
      property var project: ""
      property var projectToggles: []
      function toggleProjectFilter(root) {
        rs.projectToggles = rs.projectToggles.concat([root])
        var want = typeof root === "string" ? root.replace(/\/+$/, "") : ""
        var next = want === "" || want === rs.projectFilter ? "" : want
        rs.projectFilter = rs.hasRoot(next) ? next : ""
      }
      // Some run in `runs` has `root` as its project.root.
      function hasRoot(root) {
        if (root === "") return false
        for (var i = 0; i < rs.runs.length; i++) {
          var p = rs.runs[i] && rs.runs[i].project
          if (p && p.root === root) return true
        }
        return false
      }
      // The store's keepProjectFilter: a filter no run has any more is All.
      onRunsChanged: if (rs.projectFilter !== "" && !rs.hasRoot(rs.projectFilter)) rs.projectFilter = ""
```

- [ ] **Step 2: Add the two chip helpers**

In the same file, directly after

```qml
  function topOf(s, name) { return H.find(s.screen, name).mapToItem(s.screen, 0, 0).y }
```

insert:

```qml

  // The project chip row's chip ids, in model order, joined by ",".
  function projectChipIds(s) {
    var model = H.find(s.screen, "runProjectChips").model
    var ids = []
    for (var i = 0; i < model.length; i++) ids.push(model[i].id)
    return ids.join(",")
  }

  // A project chip's text; null when there is no such chip.
  function projectChipText(s, id) {
    var chip = H.find(s.screen, "runProjectChip" + id)
    return chip ? chip.text : null
  }
```

- [ ] **Step 3: Write the failing tests**

At the end of the file, before the final line `}` (the `TestCase`'s closing brace), after `test_the_notify_switch_reads_and_asks_the_store`, append:

```qml

  // ---- project chips (4.3)

  // 1
  function test_project_chips_without_an_open_project() {
    var s = make(twoProjects()); if (!s) return
    compare(shown(s, "runProjectChips"), true)
    compare(projectChipText(s, "all"), "All projects")
    compare(projectChipText(s, "/home/u/a"), "alpha 2")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    compare(H.find(s.screen, "runProjectChipthis"), null)
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b", "alpha (attention) before beta (live)")
    var a = H.find(s.screen, "runProjectChip/home/u/a")
    var b = H.find(s.screen, "runProjectChip/home/u/b")
    verify(a.mapToItem(s.screen, 0, 0).x < b.mapToItem(s.screen, 0, 0).x, "alpha is drawn left of beta")
  }

  // 2
  function test_an_open_project_adds_this_project_in_place_of_its_own_chip() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a/"
    compare(projectChipText(s, "this"), "This project 2")
    compare(H.find(s.screen, "runProjectChip/home/u/a"), null, "alpha is listed once, as This project")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    compare(projectChipIds(s), "all,this,/home/u/b")
  }

  // 4
  function test_the_row_hides_with_one_project_and_none_open() {
    var all = twoProjects()
    var s = make([all[0], all[2]]); if (!s) return
    compare(shown(s, "runProjectChips"), false, "one project with runs, none open")
    s.runs.project = "/home/u/a"
    compare(shown(s, "runProjectChips"), true)
    compare(projectChipIds(s), "all,this")
    compare(projectChipText(s, "this"), "This project 2")
    s.runs.project = "/home/u/b"
    compare(projectChipIds(s), "all,this,/home/u/a", "the open project is not the one with runs")
    compare(projectChipText(s, "this"), "This project 0")
    s.runs.project = ""
    s.runs.runs = sample()
    compare(shown(s, "runProjectChips"), false, "runs with no project are no project")
    s.runs.runs = []
    compare(shown(s, "runProjectChips"), false, "no runs, none open")
    s.runs.project = "/home/u/c"
    compare(shown(s, "runProjectChips"), true)
    compare(projectChipIds(s), "all,this")
    compare(projectChipText(s, "this"), "This project 0")
  }

  // 11
  function test_the_project_chips_sit_above_the_status_chips() {
    var s = make(twoProjects()); if (!s) return
    s.runs.watchWarning = "CorruptJournal: bad"
    wait(20)
    verify(topOf(s, "runsWarning") < topOf(s, "runProjectChips"), "below the banners")
    verify(topOf(s, "runProjectChips") < topOf(s, "runChips"), "above the status chips")
  }

  // 12
  function test_missing_am_hides_the_project_chips() {
    var s = make(twoProjects()); if (!s) return
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runProjectChips"), false)
    s.runs.amStatus = "schema"
    wait(20)
    compare(shown(s, "runProjectChips"), true, "a schema mismatch keeps them, as it keeps the status chips")
    s.runs.amStatus = "error"
    s.runs.stale = true
    wait(20)
    compare(shown(s, "runProjectChips"), true, "an error or stale data keeps them")
  }

  // 13
  function test_project_chip_labels_fall_back_to_the_root_and_follow_group_order() {
    var nameless = run("run-n-park0004", "stopped", null, {})
    nameless.project = { root: "/home/u/n", name: "" }
    var s = make([tagged(run("run-g-done0001", "done", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-a-live0002", "started", true, {}), "/home/u/a", "Alpha"),
                  tagged(run("run-b-escl0003", "escalated", null, {}), "/home/u/b", "beta"),
                  nameless]); if (!s) return
    compare(projectChipIds(s), "all,/home/u/b,/home/u/a,/home/u/n,/home/u/g",
            "attention, live, then name case-blind with the empty name first")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    compare(projectChipText(s, "/home/u/a"), "Alpha 1")
    compare(projectChipText(s, "/home/u/n"), "/home/u/n 1")
    compare(projectChipText(s, "/home/u/g"), "gamma 1")
  }

  // 14
  function test_a_non_string_project_shows_no_this_chip_and_does_not_throw() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = undefined
    compare(H.find(s.screen, "runProjectChipthis"), null)
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b")
    s.runs.project = 7
    compare(H.find(s.screen, "runProjectChipthis"), null)
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b")
  }

  // Review Focus 1.
  function test_many_project_chips_wrap_and_keep_the_status_chips_below() {
    var names = ["first-long-project-name", "second-long-project-name", "third-long-project-name",
                 "fourth-long-project-name", "fifth-long-project-name", "sixth-long-project-name"]
    var list = []
    for (var i = 0; i < names.length; i++)
      list.push(tagged(run("run-p" + i + "-done000" + i, "done", null, {}), "/home/u/p" + i, names[i]))
    var s = make(list); if (!s) return
    var row = H.find(s.screen, "runProjectChips")
    var first = H.find(s.screen, "runProjectChip/home/u/p0")
    verify(row.height > first.height * 2, "the chips wrap onto more lines")
    verify(topOf(s, "runProjectChips") + row.height <= topOf(s, "runChips"), "the status chips stay below")
    compare(shown(s, "runChips"), true)
    for (var p = 0; p < names.length; p++) {
      var chip = H.find(s.screen, "runProjectChip/home/u/p" + p)
      verify(chip.mapToItem(s.screen, 0, 0).x + chip.width <= s.screen.width, "chip " + p + " stays inside the screen")
    }
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: exit status 1; `FAIL!` lines for the eight new tests above (e.g. `FAIL!  : RunsScreen::test_project_chips_without_an_open_project() Compared values are not the same` / `TypeError: Cannot read property 'model' of null`), because `runProjectChips` does not exist yet. Every pre-existing test still passes (the stub additions change nothing they read).

- [ ] **Step 5: Implement the chip set in `ui/screens/RunsScreen.qml`**

5a. Replace the header comment (lines 10-20) with:

```qml
// The Runs section: every registered project's am runs, grouped by project
// with a header each (name; live, parked and needs-attention counts; the
// project's snapshot error), flat with no header under a project filter. Each
// run is one row (state glyph, short id, title, done/total, current phase,
// age) whose index is its position in the store's filteredRuns, the one list
// the cursor walks; headers are not cursor targets. A project chip row (All
// projects, This project when one is open, one chip per project with runs,
// with run counts) sits above the status chips, hidden when only one project
// has runs and none is open. Needs attention / Live / Parked / All chips
// apply across groups -- clicking the active chip means All again -- and a
// footer says whether the runs are watched. It reads the run store and asks
// the navigator to open a run or move the cursor; it owns no state of its
// own. Ages are read against the clock once per snapshot: there is no timer.
```

5b. Directly after

```qml
  readonly property bool noProjects: screen.sizeOf(screen.app.runs.projectRoots) === 0
```

insert:

```qml
  // The open project's root, by rootKey; "" when none is open.
  readonly property string openRoot: screen.rootKey(screen.app.runs.project)
  // Every listed run by project, whatever the status chip, the search or the
  // project filter: the project chips are counted from these.
  readonly property var allGroups: Runs.groupByProject(screen.app.runs.runs)
  // How many projects have runs.
  readonly property int projectsWithRuns: screen.projectsIn(screen.allGroups)
  // The project chip row's model (projectChipsOf).
  readonly property var projectChips: screen.projectChipsOf(screen.allGroups, screen.openRoot)
```

5c. Directly after the closing `}` of `function projectError(errors, root) { ... }` insert:

```qml

  // How many groups of `groups` have a root other than "".
  function projectsIn(groups) {
    var n = 0
    for (var g = 0; g < screen.sizeOf(groups); g++) {
      if (groups[g].project.root !== "") n++
    }
    return n
  }

  // The project chips, scalar values only (a Repeater converts nested ones):
  // All projects (id "all", no count); This project (id "this") when `open`
  // is not "", counting the runs of `open`'s group, 0 when it has none; then
  // one chip per group of `groups` (groupByProject output), in order, except
  // the root "" group and `open`'s: id its root, label its name else its
  // root, count its runs.
  function projectChipsOf(groups, open) {
    var tint = screen.theme.dim
    var named = []
    var openCount = 0
    for (var g = 0; g < screen.sizeOf(groups); g++) {
      var group = groups[g]
      var root = group.project.root
      if (root === "") continue
      if (root === open) {
        openCount = screen.sizeOf(group.runs)
        continue
      }
      named.push({ id: root, label: group.project.name !== "" ? group.project.name : root,
                   count: screen.sizeOf(group.runs), tint: tint })
    }
    var out = [{ id: "all", label: "All projects", tint: tint }]
    if (open !== "") out.push({ id: "this", label: "This project", count: openCount, tint: tint })
    return out.concat(named)
  }
```

5d. Between the `runsWarning` `UI.ThemedText { ... }` block and `UI.FilterableList {`, insert:

```qml

  // Shown while a project is open or more than one project has runs.
  UI.ChipRow {
    objectName: "runProjectChips"
    width: parent.width
    theme: screen.theme
    chipPrefix: "runProjectChip"
    visible: !screen.amMissing && (screen.openRoot !== "" || screen.projectsWithRuns > 1)
    model: screen.projectChips
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen`
Expected: exit status 0; `Totals: … 0 failed`; no `TypeError` lines. The pytest tier passes too (no new component, no `core/stores` import).

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs-screen): a project chip row above the status chips, with run counts"
```

---

### Task 2: The active project chip and what a click asks of the store

Covers spec C3, C4, C6, tests 3, 5, 6, 7, 10, Review Focus 2 and 4.

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (two functions after `projectChipsOf`; two lines in the `runProjectChips` `UI.ChipRow`)
- Test: `tests/ui/screens/tst_runs_screen.qml` (append to the `// ---- project chips (4.3)` section)

**Interfaces:**
- Consumes (from Task 1): `screen.openRoot`, `UI.ChipRow { objectName: "runProjectChips" }`, `screen.rootKey(path)`; stub `toggleProjectFilter(root)`, `projectToggles`, `project`, `onRunsChanged` fallback; helpers `projectChipIds(s)`, `projectChipText(s, id)`. Store: `app.runs.projectFilter` (string), `app.runs.project`, `app.runs.toggleProjectFilter(root)`.
- Produces: `function activeProjectChipOf(filter, open) -> string` (`"all"`, `"this"` or a root); `function chooseProject(id)` (calls `app.runs.toggleProjectFilter` once).

- [ ] **Step 1: Write the failing tests**

Append at the end of the file, before the `TestCase`'s closing `}`:

```qml

  // 3
  function test_all_projects_is_the_default() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/a"
    compare(s.runs.projectFilter, "")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChipthis").active, false)
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, false)
  }

  // 5
  function test_a_project_chip_filters_and_clicking_it_again_returns_to_all() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"/home/u/b\"]", "one call, with beta's root")
    compare(s.runs.projectFilter, "/home/u/b")
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, true)
    compare(H.find(s.screen, "runProjectChipall").active, false)
    compare(H.find(s.screen, "runGroup0"), null, "flat")
    compare(H.find(s.screen, "runRowId0").text, "…live0003")
    compare(H.find(s.screen, "runRow1"), null)
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    compare(s.runs.projectToggles.length, 2)
    compare(s.runs.projectFilter, "")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, false)
    compare(H.find(s.screen, "runGroupName0").text, "alpha", "grouped again")
  }

  // 6
  function test_all_projects_and_this_project_ask_the_store() {
    var s = make(twoProjects()); if (!s) return
    s.runs.toggleProjectFilter("/home/u/b")
    s.runs.projectToggles = []
    tap(H.find(s.screen, "runProjectChipall"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"\"]")
    compare(s.runs.projectFilter, "")
    s.runs.project = "/home/u/a"
    s.runs.projectToggles = []
    tap(H.find(s.screen, "runProjectChipthis"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"/home/u/a\"]")
    compare(s.runs.projectFilter, "/home/u/a")
    compare(H.find(s.screen, "runProjectChipthis").active, true)
    compare(H.find(s.screen, "runProjectChipall").active, false)
    compare(H.find(s.screen, "runRowId0").text, "…escl0001")
    compare(H.find(s.screen, "runRowId1").text, "…dead0002")
    compare(H.find(s.screen, "runRow2"), null, "alpha's runs only")
    s.runs.project = "/home/u/a/"
    compare(H.find(s.screen, "runProjectChipthis").active, true, "a trailing / on the open project still matches")
  }

  // 7
  function test_this_project_with_no_runs_stays_on_all() {
    var s = make(twoProjects()); if (!s) return
    s.runs.project = "/home/u/c"
    compare(projectChipText(s, "this"), "This project 0")
    tap(H.find(s.screen, "runProjectChipthis"))
    compare(JSON.stringify(s.runs.projectToggles), "[\"/home/u/c\"]")
    compare(s.runs.projectFilter, "")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChipthis").active, false)
    compare(H.find(s.screen, "runGroupName0").text, "alpha", "still grouped")
  }

  // 10
  function test_a_vanished_filtered_project_falls_back_to_all_projects() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    compare(s.runs.projectFilter, "/home/u/b")
    var all = twoProjects()
    s.runs.runs = [all[0], all[2]]
    compare(s.runs.projectFilter, "", "the store fell back")
    compare(H.find(s.screen, "runProjectChipall").active, true)
    compare(H.find(s.screen, "runProjectChip/home/u/b"), null, "beta's chip is gone")
    compare(H.find(s.screen, "runGroupName0").text, "alpha", "headers are back")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 0")
  }

  // Review Focus 2.
  function test_a_new_snapshot_reorders_the_chips_and_the_active_one_stays_active() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    s.runs.runs = [tagged(run("run-a-done0001", "done", null, {}), "/home/u/a", "alpha"),
                   tagged(run("run-b-escl0003", "escalated", null, {}), "/home/u/b", "beta")]
    compare(projectChipIds(s), "all,/home/u/b,/home/u/a", "beta needs attention now")
    compare(s.runs.projectFilter, "/home/u/b")
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, true)
    compare(H.find(s.screen, "runProjectChip/home/u/a").active, false)
    compare(H.find(s.screen, "runRowId0").text, "…escl0003")
  }

  // Review Focus 4.
  function test_opening_the_filtered_project_moves_the_active_chip_to_this_project() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runProjectChip/home/u/b"))
    s.runs.project = "/home/u/b"
    compare(s.runs.projectFilter, "/home/u/b", "a project switch does not touch the filter")
    compare(H.find(s.screen, "runProjectChip/home/u/b"), null, "beta is listed once, as This project")
    compare(H.find(s.screen, "runProjectChipthis").active, true)
    compare(projectChipText(s, "this"), "This project 1")
    compare(projectChipText(s, "/home/u/a"), "alpha 2")
    s.runs.project = ""
    compare(H.find(s.screen, "runProjectChip/home/u/b").active, true)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: exit status 1; `FAIL!` for each of the seven tests above — `test_all_projects_is_the_default` because no chip is active yet (`active` is `""`), the others because a tap calls nothing (`projectToggles` stays `[]`, `projectFilter` stays `""`). Task 1's tests and every older test still pass.

- [ ] **Step 3: Implement the active chip and the click**

3a. In `ui/screens/RunsScreen.qml`, directly after the closing `}` of `function projectChipsOf(groups, open) { ... }`, insert:

```qml

  // The project chip `filter` (the store's projectFilter) makes active: "all"
  // for "", "this" when it is `open`, else its root, which no chip has when
  // that project has no chip.
  function activeProjectChipOf(filter, open) {
    var key = screen.rootKey(filter)
    return key === "" ? "all" : key === open ? "this" : key
  }

  // A project chip was clicked: the store toggles its project filter with ""
  // for All projects, the open project for This project, else the chip's root.
  function chooseProject(id) {
    screen.app.runs.toggleProjectFilter(id === "all" ? "" : id === "this" ? screen.app.runs.project : id)
  }
```

3b. In the `runProjectChips` `UI.ChipRow`, after `model: screen.projectChips`, add:

```qml
    active: screen.activeProjectChipOf(screen.app.runs.projectFilter, screen.openRoot)
    onChosen: function(id) { screen.chooseProject(id) }
```

so the block reads:

```qml
  // Shown while a project is open or more than one project has runs.
  UI.ChipRow {
    objectName: "runProjectChips"
    width: parent.width
    theme: screen.theme
    chipPrefix: "runProjectChip"
    visible: !screen.amMissing && (screen.openRoot !== "" || screen.projectsWithRuns > 1)
    model: screen.projectChips
    active: screen.activeProjectChipOf(screen.app.runs.projectFilter, screen.openRoot)
    onChosen: function(id) { screen.chooseProject(id) }
  }
```

3c. In the header comment, replace the sentence

```qml
// has runs and none is open. Needs attention / Live / Parked / All chips
```

with

```qml
// has runs and none is open; clicking one asks the store to toggle its
// project filter. Needs attention / Live / Parked / All chips
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen`
Expected: exit status 0; `Totals: … 0 failed`; no `TypeError` lines.

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs-screen): the active project chip follows the filter and a click toggles it in the store"
```

---

### Task 3: Status-chip counts within the project filter

Covers spec C5, C7 (status-count sentence), tests 8, 9, Review Focus 3 and 5.

**Files:**
- Modify: `ui/screens/RunsScreen.qml:38` (`counts`) and the header comment
- Test: `tests/ui/screens/tst_runs_screen.qml` (append to the `// ---- project chips (4.3)` section)

**Interfaces:**
- Consumes: `Runs.filterByProject(runs, root)` (`""` keeps every run), `Runs.runFilterCounts(runs)` → `{ attention, live, parked, all }`; stub `toggleProjectFilter(root)`; helpers `projectChipIds(s)`, `projectChipText(s, id)`.
- Produces: `readonly property var counts` now over the project filter's runs (read only by the status chips in `UI.FilterableList.chips`).

- [ ] **Step 1: Write the failing tests**

Append at the end of the file, before the `TestCase`'s closing `}`:

```qml

  // 8
  function test_status_chip_counts_apply_within_the_project_filter() {
    var s = make(twoProjects()); if (!s) return
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    s.runs.toggleProjectFilter("/home/u/b")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 0")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    compare(H.find(s.screen, "runChipparked").text, "Parked 0")
    s.runs.toggleProjectFilter("/home/u/a")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 0")
  }

  // 9
  function test_a_status_chip_and_the_project_filter_compose_and_project_counts_stay_whole() {
    var s = make(twoProjects()); if (!s) return
    s.runs.toggleProjectFilter("/home/u/a")
    tap(H.find(s.screen, "runChiplive"))
    compare(H.find(s.screen, "runRow0"), null, "alpha has no live run")
    compare(H.find(s.screen, "runsMessage").text, "No Live runs.")
    s.runs.toggleProjectFilter("")
    tap(H.find(s.screen, "runChipattention"))
    compare(projectChipText(s, "/home/u/b"), "beta 1", "beta's chip keeps its full count")
    compare(projectChipText(s, "/home/u/a"), "alpha 2")
  }

  // Review Focus 3.
  function test_the_search_changes_neither_project_chips_nor_status_counts() {
    var s = make(twoProjects()); if (!s) return
    s.nav.searchQuery = "zeta"
    compare(H.find(s.screen, "runRowId0").text, "…live0003")
    compare(H.find(s.screen, "runRow1"), null)
    compare(projectChipText(s, "/home/u/a"), "alpha 2", "alpha's runs are all searched out; its chip stays")
    compare(projectChipText(s, "/home/u/b"), "beta 1")
    s.runs.toggleProjectFilter("/home/u/a")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2", "counts within the filter, not the search")
    compare(H.find(s.screen, "runRow0"), null)
  }

  // Review Focus 5.
  function test_runs_without_a_project_count_under_all_projects_only() {
    var s = make(sample().concat(twoProjects())); if (!s) return
    compare(projectChipIds(s), "all,/home/u/a,/home/u/b", "untagged runs get no chip")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 4")
    compare(H.find(s.screen, "runChiplive").text, "Live 2")
    compare(H.find(s.screen, "runChipparked").text, "Parked 1")
    s.runs.toggleProjectFilter("/home/u/a")
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 0")
    compare(H.find(s.screen, "runChipparked").text, "Parked 0")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: exit status 1; `FAIL!` for `test_status_chip_counts_apply_within_the_project_filter` (actual `Needs attention 2`, expected `Needs attention 0`) and `test_runs_without_a_project_count_under_all_projects_only` (actual `Needs attention 4`, expected `Needs attention 2`). `test_a_status_chip_and_the_project_filter_compose_and_project_counts_stay_whole` and `test_the_search_changes_neither_project_chips_nor_status_counts` already pass: they pin behaviour Tasks 1-2 built (the composition is the store's `groups`; the project chips count `app.runs.runs`) and must stay green after Step 3.

- [ ] **Step 3: Narrow the counts by the project filter**

3a. In `ui/screens/RunsScreen.qml`, replace

```qml
  readonly property var counts: Runs.runFilterCounts(screen.app.runs.runs)
```

with

```qml
  // The status chips' counts: the project filter's runs, whatever the search.
  readonly property var counts: Runs.runFilterCounts(Runs.filterByProject(screen.app.runs.runs, screen.app.runs.projectFilter))
```

3b. Replace the whole header comment (the `//` lines between the imports and `Column {`) with:

```qml
// The Runs section: every registered project's am runs, grouped by project
// with a header each (name; live, parked and needs-attention counts; the
// project's snapshot error), flat with no header under a project filter. Each
// run is one row (state glyph, short id, title, done/total, current phase,
// age) whose index is its position in the store's filteredRuns, the one list
// the cursor walks; headers are not cursor targets. A project chip row (All
// projects, This project when one is open, one chip per project with runs,
// with run counts) sits above the status chips, hidden when only one project
// has runs and none is open; clicking one asks the store to toggle its
// project filter. Needs attention / Live / Parked / All chips apply across
// groups and count within the project filter -- clicking the active chip
// means All again -- and a footer says whether the runs are watched. It reads
// the run store and asks the navigator to open a run or move the cursor; it
// owns no state of its own. Ages are read against the clock once per
// snapshot: there is no timer.
```

- [ ] **Step 4: Run the whole suite to verify everything passes**

Run: `bash tests/run.sh`
Expected: exit status 0; pytest passes; every `== tests/...` block reports `Totals: … 0 failed`; no `TypeError` / `ReferenceError` lines. In particular `test_the_chip_counts_ignore_the_search` and `tests/ui/tst_runs_flow.qml` (real store, untagged/tagged runs, project filter `""`) stay green.

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs-screen): the status chips count within the project filter"
```
<!-- task-pipeline: validated -->
