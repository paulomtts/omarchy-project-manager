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
