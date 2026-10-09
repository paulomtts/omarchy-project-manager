# 4.2 RunsScreen: the grouped list — design

Card `8c17d03f`, a subtask of story `63a11d2f` ("Global runs UI"), blocked by `62267485`
(4.1, Runs without a project — done). Parent spec:
`docs/superpowers/specs/2026-10-05-runs-all-projects-design.md` (below: **parent**).

`ui/screens/RunsScreen.qml` today draws `app.runs.filteredRuns` as one flat list. This
subtask draws the same list grouped by project, with a header per project, an inline
error line for a project whose snapshot failed, and the empty states for "no project
registered" and "no runs". The store already computes everything the screen needs
(`groups`, `filteredRuns`, `projectErrors`, `projectRoots`, `projectFilter`); nothing in
`core/` changes.

## Inherited constraints

| constraint | source |
|---|---|
| Each group has a header: project name, counts of live / parked / needs-attention runs | parent L45-46 |
| Group order: attention first, then live, then name (case-blind), then root; a project with no runs is omitted | parent L46-48 (implemented by `Runs.groupByProject`, `core/domain/runs.js:395-447`) |
| The status filters (Needs attention / Live / Parked / All) apply across groups | parent L48-49 |
| `RunStore.filteredRuns` is the list in DISPLAY order; the screen, the navigator's cursor and `handleRunKey` all index that one list; group headers are not cursor targets | parent L50-52 |
| With one project selected in the project filter the list is flat (no group header) | parent L56-57 |
| No project registered: the "No projects registered" empty state | parent L166 |
| A registered root that no longer exists still lists its runs; nothing special | parent L164 |
| UI tests cover grouping and cursor order | parent L190-191 |
| Screens read `app.runs` and never import `core/stores`; reuse `FilterableList`, `ListRow`, `ListStatus`, `ThemedText`; no duplicated components; icon glyph rules | card; story `63a11d2f`; `docs/architecture.md` L165; `tests/architecture/` |
| Docstrings and comments state the contract only, no narrative | card |
| Tests first; `bash tests/run.sh` green | card |

**Deviation from the parent, recorded.** The parent (L136-137, L88-89) says there is one
list error and no per-project errors. The store as built on this branch keeps
`projectErrors` (`{root: sentence}`, `core/stores/RunStore.qml:50-51`, filled per failed
root at L1010-1013) and keeps a failed root's previous runs. The card asks the screen to
show those errors; this spec follows the card and the built store.

**Stale card item.** The card says the footer is hardcoded `am · schema 1 · `. It is
not: `RunsScreen.qml:142-157` already builds `am [<version>] [· schema N] · watching|not
watching` from `amVersion` / `amSchema`, covered by `tst_runs_screen.qml:373-512`. This
subtask does not touch the footer; those tests must stay green unchanged.

## Store surface the screen reads (all on `app.runs`, already present)

| property | shape | meaning |
|---|---|---|
| `groups` | `[{project:{root, name}, runs, counts:{live, parked, attention}}]` | the runs past the status chip, the search and the project filter, grouped and ordered (`RunStore.qml:80`). `root` has trailing `/` removed. A group with `root === ""` (runs carrying no project) is last. |
| `filteredRuns` | `run[]` | `Runs.displayOrder(groups)`: every group's runs in turn (`RunStore.qml:83`) |
| `projectErrors` | `{root: sentence}` | keyed by the **registry** root as written (may carry a trailing `/`) |
| `projectRoots` | `[{root, name}]` | the registry, in registry order |
| `projectFilter` | string | `""` = All projects, else a root with trailing `/` removed |
| `runFilter`, `searchQuery` (via `app.nav.searchQuery`) | string | unchanged |

**Root matching.** Wherever this spec compares a registry root (a `projectErrors` key or
a `projectRoots[i].root`) with a group root or `projectFilter`, both sides are compared
with every trailing `/` removed (`"/"` for a root of only slashes) — the rule
`Runs.withProject` uses.

## Behavior

### B1. Grouped list (project filter `""`)

1. The rows area shows, for each entry of `app.runs.groups` in order, a **group header**
   followed by that group's run rows.
2. A group whose `project.root` is `""` gets **no header**: its rows follow the previous
   group's rows directly. (The store never produces such a group from real data; stub
   runs without a `project` land there, so every existing row test keeps its indices.)
3. A header shows:
   - **name** — `project.name`; when that is `""`, the `project.root` instead.
   - **counts** — the group's `counts`, as the non-zero parts of
     `<live> live`, `<parked> parked`, `<attention> needs attention`, in that order,
     joined by ` · ` (e.g. `2 live · 1 needs attention`). All three zero → the counts text
     is `""` and hidden.
     The counts are those of the group as listed, i.e. after the status chip and the
     search (the store computes `groups` after both).
   - **error line** — when `projectErrors` has an entry for the group's root (root
     matching above): that sentence, in `theme.urgent`, caption, word-wrapped, directly
     under the name/counts and above the group's first run. No entry → hidden.
4. **Failed project with nothing listed.** For each registry entry of `projectRoots`
   (registry order; a root listed twice counts once) whose root has a `projectErrors`
   entry and has **no** group in `groups`, an extra group is shown after every group of
   `groups`: a header with the registry `name` (root when the name is `""`), no counts
   text, the error line, and no rows. These extra headers never add rows and never change
   `filteredRuns`.
5. Headers and error lines are **not** cursor targets: no cursor highlight, hovering
   them calls nothing on the navigator, clicking them opens nothing.

### B2. One index for every run row

1. A run row's index is its position in `app.runs.filteredRuns` (the global display
   order), never its position inside its group. The row reads its run as
   `app.runs.filteredRuns[index]` (the existing comment on why `modelData` is not used
   stays true).
2. Its `objectName` stays `runRow<index>`, and every per-row part keeps its
   `runRow<Part><index>` name (`runRowGlyph`, `runRowId`, `runRowTitle`, `runRowProgress`,
   `runRowPhase`, `runRowAge`, `runRowState`, `runRowReason`, `runRowControls`).
3. `hasCursor` is true exactly for the row whose index equals `app.nav.cursorIndex`;
   hovering a row calls `navigator.hoverCursor(index)`; clicking it calls
   `navigator.openRun(<that run's id>)`. So with groups A (2 runs) and B (1 run), the
   first run under B's header is `runRow2`, and cursor index 2 marks it.
4. Enter on the Runs list keeps going through `Shortcuts` / `Navigator`, which already read
   `filteredRuns[cursorIndex]` (`ui/Shortcuts.qml:70`, `ui/Navigator.qml:27`); since the
   screen's index is the same list's index, Enter opens the run that has the highlight.

### B3. Project filter selected (`projectFilter !== ""`)

1. No group header at all: the rows are `filteredRuns` in order, flat.
2. When `projectErrors` has an entry for the filtered root, that sentence shows once,
   above the first row, as a line named `runsProjectError` (`theme.urgent`, caption,
   word-wrapped). Otherwise that line is hidden. With `projectFilter === ""`,
   `runsProjectError` is always hidden.
3. The project filter chips themselves are 4.3's; this subtask only reads
   `projectFilter`.

### B4. Status line (`runsMessage`) and empty states

Exact strings:

| condition (first match wins) | `runsMessage` text |
|---|---|
| am missing | `am is not installed or not on PATH` (unchanged; no chips, no rows, no headers) |
| `filteredRuns` empty and `projectRoots` has no entry | `No projects registered.` — whatever the chip and the search |
| `filteredRuns` empty and the search is not empty | `No runs match “<query>”.` (unchanged) |
| `filteredRuns` empty and a status chip is set | `No <chip label> runs.` (unchanged) |
| `filteredRuns` empty | `No runs yet.` (replaces `No runs for this project yet.`) |
| otherwise | hidden |

The failed-project headers of B1.4 still show under the status line when `filteredRuns`
is empty (the status line speaks about runs; the error lines about projects).
`ListStatus` shows `filteredText` only while `filtered` is true, so `RunsScreen` binds
`filtered` to false and `emptyText` to `No projects registered.` when `projectRoots` has no
entry (and the usual chip/search wording otherwise).
"`projectRoots` has no entry" means `projectRoots` is not an array or has length 0.

### B5. Unchanged

Chips and their counts, the schema / stale / warning banners, the notify switch, the
footer, row content, row controls (`RunControls` in the row's actions, buttons while the
row has the cursor), cancel going through `cancelRequested`, stale dimming of rows. The
stale dimming does not apply to headers (they carry no run data that ages).

### B6. Header contract comment

The file's header comment changes from "the selected project's am runs" to the contract
for this screen: every registered project's runs grouped by project with a header each
(name, counts, the project's snapshot error), flat under a project filter, one
cursor index over `filteredRuns`.

## Object names (new)

| name | item |
|---|---|
| `runGroup<G>` | header item of the G-th header shown (0-based, counting B1.4 extra headers after the others; root-`""` groups take no G) |
| `runGroupName<G>` | its name text |
| `runGroupCounts<G>` | its counts text |
| `runGroupError<G>` | its error line |
| `runsProjectError` | B3.2's flat-list error line |

## Errors and edge cases

| case | behavior |
|---|---|
| a group's `project.name` is `""` | header names the root |
| a `projectErrors` key carries a trailing `/` (`"/home/u/b/"`) and the group root is `"/home/u/b"` | the error shows on that group (root matching) |
| a `projectErrors` key whose root is not in `projectRoots` and has no group | nothing shown for it |
| a failed project whose runs are all filtered out by a chip or the search | its B1.4 header with the error line shows, no rows |
| `groups` contains only the root-`""` group | no header at all; rows as before |
| a single registered project with runs, project filter `""` | one header above its rows (the flat list is only for a selected project filter) |
| a malformed run in a group | the row renders without throwing (existing `test_malformed_runs_render_without_throwing` keeps passing) |
| am missing | no headers, no `runsProjectError`, only the missing message |

## Out of scope

- The project filter chips, their counts and the status-chip counts within a project
  filter (4.3).
- The **Open project** row action (4.4).
- `RunIndicator`, the sidebar count, the toast's project name (4.5).
- `docs/architecture.md` and README wording (4.6).
- Any change to `core/` (`RunStore`, `runs.js`), `FilterableList`, `ListStatus`,
  `ListRow`, `Navigator`, `Shortcuts`, or the footer.

## Tests

Tier rationale: **screen tier** (`tests/ui/screens/tst_runs_screen.qml`) mounts
`RunsScreen` alone with a stub run store and a recorder navigator — the right place for
what the screen draws and which index each row carries. **Flow tier**
(`tests/ui/tst_runs_flow.qml`) mounts the real `Panel`, `Navigator`, `Shortcuts` and
`RunStore` — the only place a real Enter key travels through `handleSearchKey` to
`openRun`. **Architecture tier** (`tests/architecture`, existing, pytest) guards the
layering and duplicate-component rules; no new test there.

### Stub changes (screen tier)

The stub `runsC` gains the store's real derivation so the screen sees what the store
gives it:

- `property var projectRoots: [{ root: "/home/u/a", name: "alpha" }]` (default: one
  registered project, so existing empty-state tests see "No runs yet.")
- `property var projectErrors: ({})`
- `property string projectFilter: ""`
- `readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery), rs.projectFilter))`
- `readonly property var filteredRuns: Runs.displayOrder(rs.groups)`

A helper tags a run with a project: `Runs.withProject(run(...), root, name)`. Existing
sample runs stay untagged (root-`""` group, no header), so every existing test keeps its
row indices.

### New / changed tests

| # | test | tier | proves |
|---|---|---|---|
| 1 | `test_no_runs_says_so` (changed) and flow `test_an_empty_runs_list_ignores_enter` (changed, `tests/ui/tst_runs_flow.qml:182`) | screen, flow | text is `No runs yet.` (the flow test asserts the old `No runs for this project yet.` too; its registry must hold a project, else the text is `No projects registered.`) |
| 2 | `test_each_project_gets_a_header_with_its_name_and_counts` | screen | two projects → `runGroup0/1` visible, names, counts text `1 live · 1 needs attention`-style exact strings |
| 3 | `test_zero_counts_are_left_out_and_all_zero_hides_the_counts` | screen | a group of only done/cancelled runs → `runGroupCounts<G>` text `""`, not visible; a parked-only group → `1 parked` |
| 4 | `test_groups_and_rows_follow_the_display_order` | screen | projects "beta" (attention), "Alpha" (live), "gamma" (neither) → headers in that order, and `runRowId0..n` read the runs group by group, matching `filteredRuns` |
| 5 | `test_runs_without_a_project_get_no_header` | screen | untagged runs → `runGroup0` is null; `runRow0` exists |
| 6 | `test_a_failed_group_shows_its_error_under_its_header` | screen | `projectErrors["/home/u/b/"] = "AmTimeout: …"` with group root `/home/u/b` → `runGroupError<G>` visible, exact text, urgent colour; the other group's error line hidden |
| 7 | `test_a_failed_project_with_nothing_listed_still_shows_its_error` | screen | registry has b, b has an error and no runs → an extra `runGroup<last>` named b with the error and no counts; `filteredRuns` unchanged; and with a chip that hides all of b's runs the same header appears |
| 8 | `test_a_project_name_that_is_empty_shows_the_root` | screen | header name is the root |
| 9 | `test_a_project_filter_shows_a_flat_list_without_headers` | screen | `projectFilter = "/home/u/b"` → no `runGroup0`, rows are b's runs from `runRow0`; `runsProjectError` shows b's error when set, hidden when not, hidden with filter `""` |
| 10 | `test_no_projects_registered_says_so_whatever_the_chip` | screen | `projectRoots = []`, no runs → `No projects registered.`; still so with a status chip set and with a search |
| 11 | `test_the_cursor_on_the_first_run_past_a_header_marks_that_row` | screen | A (2 runs), B (1 run): `nav.cursorIndex = 2` → `runRow2.hasCursor`, its id is B's run, `runRow0/1` not; the header has no `hasCursor` |
| 12 | `test_hovering_a_header_moves_no_cursor_and_a_row_past_it_reports_its_global_index` | screen | hover `runGroup1` → `navi.hovered` stays -1; hover `runRow2` → 2 |
| 13 | `test_clicking_the_first_run_past_a_header_opens_that_run` | screen | tap `runRow2` → `navi.opened` is B's run id; tap `runGroup1` → nothing opened |
| 14 | `test_missing_am_shows_no_headers` | screen | `amStatus = "missing"` with grouped runs → no visible `runGroup0`, `runsProjectError` hidden |
| 15 | `test_enter_on_the_first_run_of_the_second_project_opens_it` | flow | registry alpha + beta, runs of both tagged (`project: {root, name}`), Ctrl+6, Down past alpha's runs, Return → `viewMode "run"`, `selectedRunId` is beta's first run in display order |

All existing tests in `tst_runs_screen.qml` and `tst_runs_flow.qml` stay green with only
the two assertions of row 1 changed. Verification: `python3 -m pytest tests/architecture -q`, then
`bash tests/run.sh` green.

## Notes for the planner

- `FilterableList`'s `Repeater` takes one `rowDelegate`; one way that keeps every
  constraint is to pass the screen a model of plain entries
  (`{kind: "header", g}` / `{kind: "run", i}` — scalars only, since a `Repeater`
  converts nested arrays) built from `app.runs.groups`, and have the delegate pick a
  header or a `RunRow` whose `index` is `i`. `FilterableList`'s `empty` must still be
  bound to `filteredRuns.length === 0`, not to that model's length. The planner may
  choose another approach that meets B1-B4.
- A header is defined inside `RunsScreen.qml` (an inline `component`), built from
  `ThemedText`; it must not be a `ListRow` (no cursor, no hover, no click).
