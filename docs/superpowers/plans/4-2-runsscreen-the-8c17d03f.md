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

---

# 4.2 RunsScreen: the grouped list Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ui/screens/RunsScreen.qml` draws `app.runs.filteredRuns` grouped by project — a header per project (name, counts, snapshot error), a header for a failed project with nothing listed, a flat list under a project filter — with one cursor index over `filteredRuns`, and the new empty-state wording.

**Architecture:** The screen computes one scalar-only `entries` list (`{kind: "header", g, name, counts, error}`, `{kind: "run", i}`, `{kind: "projectError", text}`) from `app.runs.groups`, `filteredRuns`, `projectRoots`, `projectErrors` and `projectFilter`, and hands it to `FilterableList` as its model. The row delegate is a `Loader` that loads a header (an inline `RunGroupHeader`, built from `ThemedText`, not a `ListRow`), a `RunRow` whose `index` is the run's position in `filteredRuns`, or the flat-list error line. `FilterableList.empty` stays bound to `filteredRuns.length === 0`. Nothing in `core/` changes.

**Tech Stack:** QML (Qt 6 / Quickshell), QtTest via `qmltestrunner` (`tests/run.sh`), pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/4-2-runsscreen-the-8c17d03f.md` (prepended above).

## Global Constraints

- Screens read `app.runs` and never import `core/stores`; reuse `FilterableList`, `ListRow`, `ListStatus`, `ThemedText`; no duplicated components; icon glyph rules (`tests/architecture`).
- No change to `core/` (`RunStore`, `runs.js`), `FilterableList`, `ListStatus`, `ListRow`, `Navigator`, `Shortcuts`, or the footer.
- Docstrings and comments state the contract only, no narrative.
- Tests first; `python3 -m pytest tests/architecture -q` and `bash tests/run.sh` green.
- `tests/run.sh` fails a QML file whose output contains `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` — every binding below is guarded so none of these print.
- Exact strings: `No projects registered.`, `No runs yet.`, `No runs match “<query>”.`, `No <chip label> runs.`, `am is not installed or not on PATH`; counts parts `<n> live`, `<n> parked`, `<n> needs attention` joined by ` · `.
- Object names: `runGroup<G>`, `runGroupName<G>`, `runGroupCounts<G>`, `runGroupError<G>`, `runsProjectError`; run rows keep `runRow<i>` and `runRow<Part><i>` with `i` the index in `filteredRuns`.
- Root matching: both sides with every trailing `/` removed (`"/"` for a root of only slashes).

## Review Focus

1. **The search narrows a group** — the header counts are the counts of the runs still listed, not of the project's runs (Task 2, `test_the_counts_are_those_of_the_runs_listed_after_the_search`).
2. **A new snapshot reorders the groups** — headers, rows and the cursor highlight follow the new order with no stale index (Task 2, `test_a_new_snapshot_reorders_headers_rows_and_the_cursor`).
3. **Stale data** dims the rows but not the headers (Task 2, `test_stale_data_dims_rows_but_not_headers`).
4. **A malformed `projectErrors`** (`null`, a non-string sentence) or a malformed registry entry renders without throwing and shows no error line (Task 3, `test_malformed_errors_and_registry_entries_show_nothing_and_do_not_throw`).
5. **A registry root listed twice** (`/home/u/b` and `/home/u/b/`) with an error and no runs gives one failed-project header, not two (Task 3, `test_a_root_registered_twice_gets_one_failed_header`).

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `ui/screens/RunsScreen.qml` | modify | the entries list, the `RunEntry` delegate, the `RunGroupHeader` component, the status-line wording, the header comment |
| `tests/ui/screens/tst_runs_screen.qml` | modify | stub store gains `projectRoots`, `projectErrors`, `projectFilter`, `groups`, `filteredRuns = displayOrder(groups)`; new screen tests |
| `tests/ui/tst_runs_flow.qml` | modify | the empty-list wording; Enter on the first run of the second project |

## How to run the tests

- One QML file (runs the full pytest suite first, then only the QML files whose path contains the filter):
  `bash tests/run.sh tst_runs_screen` / `bash tests/run.sh tst_runs_flow`
- In the output, `FAIL!  : RunsScreen::test_name() ...` lines name failures; `Totals:` gives counts; any `TypeError`/`Unable to assign` line also fails the run.
- Everything: `python3 -m pytest tests/architecture -q` then `bash tests/run.sh`.

---

### Task 1: Stub store derivation and the empty-state wording

**Files:**
- Modify: `tests/ui/screens/tst_runs_screen.qml:25-66` (stub `runsC`), `:291-296` (`test_no_runs_says_so`), add a test after it
- Modify: `tests/ui/tst_runs_flow.qml:182-190` (`test_an_empty_runs_list_ignores_enter`)
- Modify: `ui/screens/RunsScreen.qml:29-37` (new `noProjects` property), `:105-111` (status bindings)

**Interfaces:**
- Consumes: `Runs.groupByProject`, `Runs.filterByProject`, `Runs.searchRuns`, `Runs.filterRuns`, `Runs.displayOrder` (`core/domain/runs.js`).
- Produces: stub `runsC` with `projectRoots` (default `[{ root: "/home/u/a", name: "alpha" }]`), `projectErrors` (default `{}`), `projectFilter` (default `""`), readonly `groups`, readonly `filteredRuns`. Screen: `function sizeOf(list): int`, `readonly property bool noProjects`.

- [ ] **Step 1: Give the stub the store's derivation**

In `tests/ui/screens/tst_runs_screen.qml`, inside `QtObject { id: rs ... }`, replace the line

```qml
      readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery)
```

with

```qml
      // The registry, the per-root snapshot errors and the project filter, as
      // the real store holds them; groups and filteredRuns derive exactly as
      // the store's do.
      property var projectRoots: [{ root: "/home/u/a", name: "alpha" }]
      property var projectErrors: ({})
      property string projectFilter: ""
      readonly property var groups: Runs.groupByProject(Runs.filterByProject(Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery), rs.projectFilter))
      readonly property var filteredRuns: Runs.displayOrder(rs.groups)
```

- [ ] **Step 2: Write the failing screen tests**

Replace `test_no_runs_says_so` (currently asserting `"No runs for this project yet."`) with:

```qml
  function test_no_runs_says_so() {
    var s = make([]); if (!s) return
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "No runs yet.")
    compare(msg.visible, true)
  }

  function test_no_projects_registered_says_so_whatever_the_chip() {
    var s = make([]); if (!s) return
    s.runs.projectRoots = []
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "No projects registered.")
    compare(msg.visible, true)
    s.runs.toggleRunFilter("live")
    compare(msg.text, "No projects registered.", "a chip does not change it")
    s.nav.searchQuery = "beta"
    compare(msg.text, "No projects registered.", "nor does a search")
    s.runs.projectRoots = null
    compare(msg.text, "No projects registered.", "a registry that is not a list is empty")
    s.runs.projectRoots = [{ root: "/home/u/a", name: "alpha" }]
    compare(msg.text, "No runs match “beta”.", "a registered project brings the usual wording back")
    s.nav.searchQuery = ""
    compare(msg.text, "No Live runs.")
  }
```

- [ ] **Step 3: Change the flow test's wording**

In `tests/ui/tst_runs_flow.qml`, in `test_an_empty_runs_list_ignores_enter`, replace

```qml
    compare(H.find(p, "runsMessage").text, "No runs for this project yet.")
```

with

```qml
    compare(H.find(p, "runsMessage").text, "No runs yet.", "the registry holds alpha")
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: `FAIL!  : RunsScreen::test_no_runs_says_so()` (actual `No runs for this project yet.`) and `FAIL!  : RunsScreen::test_no_projects_registered_says_so_whatever_the_chip()`; every other test in the file passes (untagged runs form the root-`""` group, so row indices are unchanged).

Run: `bash tests/run.sh tst_runs_flow`
Expected: `FAIL!  : RunsFlow::test_an_empty_runs_list_ignores_enter()`.

- [ ] **Step 5: Implement the wording**

In `ui/screens/RunsScreen.qml`, after `readonly property var counts: Runs.runFilterCounts(screen.app.runs.runs)` add:

```qml
  // The registry is empty: the status line says so whatever the chip or the
  // search.
  readonly property bool noProjects: screen.sizeOf(screen.app.runs.projectRoots) === 0
```

After `function chipLabel(id) { ... }` add:

```qml
  // The length of a list or array-like object; 0 for anything else.
  function sizeOf(list) {
    return list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
  }
```

In the `UI.FilterableList { ... }` block replace

```qml
    filtered: screen.app.nav.searchQuery !== "" || screen.app.runs.runFilter !== ""
```

with

```qml
    filtered: !screen.noProjects && (screen.app.nav.searchQuery !== "" || screen.app.runs.runFilter !== "")
```

and replace

```qml
    emptyText: "No runs for this project yet."
```

with

```qml
    emptyText: screen.noProjects ? "No projects registered." : "No runs yet."
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen` then `bash tests/run.sh tst_runs_flow`
Expected: `Totals:` with `0 failed` for both, and no `TypeError` lines.

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs-screen): \"No projects registered.\" and \"No runs yet.\" empty states"
```

---

### Task 2: The grouped list — headers, counts, one index over `filteredRuns`

**Files:**
- Modify: `ui/screens/RunsScreen.qml` — header comment (`:10-15`), new functions `countsText` / `entriesOf`, new property `entries`, `FilterableList` `model` / `rowDelegate` (`:113-114`), `RunRow` (`:159-170`), new components `RunEntry`, `RunGroupHeader`
- Modify: `tests/ui/screens/tst_runs_screen.qml` — helpers and new tests (add a `// ---- groups` section after `test_the_cursor_row_follows_the_navigation_store`)
- Modify: `tests/ui/tst_runs_flow.qml` — `pB` property, `runIn` helper, new test after `test_an_empty_runs_list_ignores_enter`

**Interfaces:**
- Consumes: Task 1's stub (`projectRoots`, `projectErrors`, `projectFilter`, `groups`, `filteredRuns`) and screen `sizeOf(list)`.
- Produces (screen): `function countsText(counts): string`; `function entriesOf(groups, runs, roots, errors, filter): [entry]` where entry is `{kind: "header", g: int, name: string, counts: string, error: string}` or `{kind: "run", i: int}` (Task 3 adds `{kind: "projectError", text: string}` and fills `error`); `readonly property var entries`; inline components `RunEntry` (a `Loader`, `required property var modelData`, `readonly property var fact`) and `RunGroupHeader` (a `Column` with `property int g`, `property string name`, `property string counts`, `property string error`). `RunRow` no longer has required properties; its `index` is set by `RunEntry`.
- Produces (tests): `tagged(run, root, name)`, `shown(s, name)`, `top(s, name)`, `twoProjects()` helpers in `tst_runs_screen.qml`.

- [ ] **Step 1: Add the test helpers**

In `tests/ui/screens/tst_runs_screen.qml`, after `function sample() { ... }` add:

```qml
  // `r` as the store holds it: tagged with the registered project at `root`.
  function tagged(r, root, name) { return Runs.withProject(r, root, name) }

  // The item exists and is visible.
  function shown(s, name) {
    var item = H.find(s.screen, name)
    return !!item && item.visible
  }

  // An item's top edge in the screen's coordinates.
  function top(s, name) { return H.find(s.screen, name).mapToItem(s.screen, 0, 0).y }

  // Project A (/home/u/a, "alpha") with an escalated and a dead run, project
  // B (/home/u/b, "beta") with one live run. Display order: A (attention)
  // then B (live), so filteredRuns is escl0001, dead0002, live0003.
  function twoProjects() {
    return [tagged(run("run-a-escl0001", "escalated", null, {}), "/home/u/a", "alpha"),
            tagged(run("run-b-live0003", "started", true, { milestone: "zeta" }), "/home/u/b", "beta"),
            tagged(run("run-a-dead0002", "started", false, {}), "/home/u/a", "alpha")]
  }
```

- [ ] **Step 2: Write the failing screen tests**

After `test_the_cursor_row_follows_the_navigation_store` add:

```qml
  // ---- groups

  function test_each_project_gets_a_header_with_its_name_and_counts() {
    var s = make([tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha"),
                  tagged(run("run-a-escl0002", "escalated", null, {}), "/home/u/a", "alpha"),
                  tagged(run("run-b-park0003", "stopped", null, {}), "/home/u/b", "beta"),
                  tagged(run("run-b-live0004", "started", true, {}), "/home/u/b", "beta")]); if (!s) return
    compare(shown(s, "runGroup0"), true)
    compare(shown(s, "runGroup1"), true)
    compare(H.find(s.screen, "runGroup2"), null)
    compare(H.find(s.screen, "runGroupName0").text, "alpha")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 live · 1 needs attention")
    compare(H.find(s.screen, "runGroupCounts0").visible, true)
    compare(H.find(s.screen, "runGroupName1").text, "beta")
    compare(H.find(s.screen, "runGroupCounts1").text, "1 live · 1 parked")
    verify(top(s, "runGroup0") < top(s, "runRow0"), "alpha's header above alpha's first run")
    verify(top(s, "runRow1") < top(s, "runGroup1"), "beta's header after alpha's runs")
    verify(top(s, "runGroup1") < top(s, "runRow2"), "beta's header above beta's first run")
    compare(H.find(s.screen, "runGroupError0").visible, false, "no snapshot error")
  }

  function test_zero_counts_are_left_out_and_all_zero_hides_the_counts() {
    var s = make([tagged(run("run-g-done0001", "done", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-g-canc0002", "cancelled", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-d-park0003", "stopped", null, {}), "/home/u/d", "delta")]); if (!s) return
    compare(H.find(s.screen, "runGroupName0").text, "delta")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 parked")
    compare(H.find(s.screen, "runGroupName1").text, "gamma")
    compare(H.find(s.screen, "runGroupCounts1").text, "")
    compare(H.find(s.screen, "runGroupCounts1").visible, false)
  }

  function test_groups_and_rows_follow_the_display_order() {
    var s = make([tagged(run("run-g-done0001", "done", null, {}), "/home/u/g", "gamma"),
                  tagged(run("run-A-live0002", "started", true, {}), "/home/u/A", "Alpha"),
                  tagged(run("run-b-dead0003", "started", false, {}), "/home/u/b", "beta"),
                  tagged(run("run-A-park0004", "stopped", null, {}), "/home/u/A", "Alpha")]); if (!s) return
    compare(H.find(s.screen, "runGroupName0").text, "beta", "attention first")
    compare(H.find(s.screen, "runGroupName1").text, "Alpha", "then live")
    compare(H.find(s.screen, "runGroupName2").text, "gamma", "then the rest")
    compare(s.runs.filteredRuns.map(function(r) { return r.id }).join(","),
            "run-b-dead0003,run-A-live0002,run-A-park0004,run-g-done0001")
    for (var i = 0; i < 4; i++)
      compare(H.find(s.screen, "runRowId" + i).text, Runs.shortId(s.runs.filteredRuns[i]), "row " + i)
    compare(H.find(s.screen, "runRow4"), null)
    verify(top(s, "runRow0") < top(s, "runGroup1"))
    verify(top(s, "runGroup1") < top(s, "runRow1"))
    verify(top(s, "runRow2") < top(s, "runGroup2"))
    verify(top(s, "runGroup2") < top(s, "runRow3"))
  }

  function test_runs_without_a_project_get_no_header() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runGroup0"), null)
    verify(H.find(s.screen, "runRow0"), "the rows are there")
    compare(H.find(s.screen, "runRowId5").text, "…done0006")
  }

  function test_a_project_name_that_is_empty_shows_the_root() {
    var r = run("run-z-live0001", "started", true, {})
    r.project = { root: "/home/u/z", name: "" }
    var s = make([r]); if (!s) return
    compare(H.find(s.screen, "runGroupName0").text, "/home/u/z")
  }

  function test_the_cursor_on_the_first_run_past_a_header_marks_that_row() {
    var s = make(twoProjects()); if (!s) return
    s.nav.cursorIndex = 2
    compare(H.find(s.screen, "runRow2").hasCursor, true)
    compare(H.find(s.screen, "runRowId2").text, "…live0003", "B's run")
    compare(H.find(s.screen, "runRow0").hasCursor, false)
    compare(H.find(s.screen, "runRow1").hasCursor, false)
    verify(H.find(s.screen, "runGroup1").hasCursor !== true, "a header never has the cursor")
  }

  function test_hovering_a_header_moves_no_cursor_and_a_row_past_it_reports_its_global_index() {
    var s = make(twoProjects()); if (!s) return
    var header = H.find(s.screen, "runGroup1")
    mouseMove(header, header.width / 2, header.height / 2)
    // A row created under a resting pointer may report a hover of its own;
    // only the moves over the header count here.
    s.navi.hovered = -1
    mouseMove(header, header.width / 4, header.height / 2)
    compare(s.navi.hovered, -1)
    var row = H.find(s.screen, "runRow2")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(s.navi.hovered, 2)
  }

  function test_clicking_the_first_run_past_a_header_opens_that_run() {
    var s = make(twoProjects()); if (!s) return
    tap(H.find(s.screen, "runGroup1"))
    compare(s.navi.opened, "", "a header opens nothing")
    tap(H.find(s.screen, "runRow2"))
    compare(s.navi.opened, "run-b-live0003")
  }

  function test_missing_am_shows_no_headers() {
    var s = make(twoProjects()); if (!s) return
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runGroup0"), false)
    compare(shown(s, "runsProjectError"), false)
    compare(H.find(s.screen, "runsMessage").text, "am is not installed or not on PATH")
  }

  // Review Focus 1.
  function test_the_counts_are_those_of_the_runs_listed_after_the_search() {
    var s = make(twoProjects()); if (!s) return
    compare(H.find(s.screen, "runGroupCounts0").text, "2 needs attention")
    s.nav.searchQuery = "escl"
    compare(H.find(s.screen, "runGroupName0").text, "alpha")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 needs attention")
    compare(H.find(s.screen, "runGroup1"), null, "beta has nothing listed")
    s.nav.searchQuery = ""
    s.runs.toggleRunFilter("live")
    compare(H.find(s.screen, "runGroupName0").text, "beta", "the chip applies across groups")
    compare(H.find(s.screen, "runGroupCounts0").text, "1 live")
    compare(H.find(s.screen, "runGroup1"), null)
  }

  // Review Focus 2.
  function test_a_new_snapshot_reorders_headers_rows_and_the_cursor() {
    var s = make(twoProjects()); if (!s) return
    s.nav.cursorIndex = 0
    compare(H.find(s.screen, "runRowId0").text, "…escl0001")
    s.runs.runs = [tagged(run("run-a-live0005", "started", true, {}), "/home/u/a", "alpha"),
                   tagged(run("run-b-escl0006", "escalated", null, {}), "/home/u/b", "beta")]
    compare(H.find(s.screen, "runGroupName0").text, "beta")
    compare(H.find(s.screen, "runGroupName1").text, "alpha")
    compare(H.find(s.screen, "runRowId0").text, "…escl0006")
    compare(H.find(s.screen, "runRow0").hasCursor, true)
    compare(H.find(s.screen, "runRowId1").text, "…live0005")
    compare(H.find(s.screen, "runRow1").hasCursor, false)
    compare(H.find(s.screen, "runRow2"), null)
  }

  // Review Focus 3.
  function test_stale_data_dims_rows_but_not_headers() {
    var s = make(twoProjects()); if (!s) return
    s.runs.stale = true
    compare(H.find(s.screen, "runRow0").opacity, 0.5)
    compare(H.find(s.screen, "runGroup0").opacity, 1)
  }
```

- [ ] **Step 3: Write the failing flow test**

In `tests/ui/tst_runs_flow.qml`, after `property var pA: ({ root_path: "/home/u/a", name: "alpha" })` add:

```qml
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
```

After `function run(id, status, live, milestone) { ... }` add:

```qml
  // run(), in the project at `root` named `name`.
  function runIn(id, status, live, milestone, root, name) {
    var r = run(id, status, live, milestone)
    r.repo_dir = root
    r.project = { root: root, name: name }
    return r
  }
```

After `test_an_empty_runs_list_ignores_enter` add:

```qml
  // alpha (two runs that need attention) is listed before beta (one live
  // run): the cursor's third position is beta's first run, under beta's header.
  function test_enter_on_the_first_run_of_the_second_project_opens_it() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB])
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [runIn("run-0000000000f6", "started", true, "zeta", "/home/u/b", "beta"),
                       runIn("run-0000000000b2", "escalated", null, "beta-ms", "/home/u/a", "alpha"),
                       runIn("run-0000000000c3", "started", false, "gamma", "/home/u/a", "alpha")]
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    compare(ids(p.app.runs.filteredRuns), "run-0000000000b2,run-0000000000c3,run-0000000000f6")
    compare(H.find(p, "runGroupName1").text, "beta")
    compare(p.app.nav.cursorIndex, 0)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 2)
    compare(H.find(p, "runRow2").hasCursor, true, "the highlight is on beta's run")
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f6")
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: FAIL (a failed `compare`, or a `TypeError` from reading a property of a null `runGroup*`) for `test_each_project_gets_a_header_with_its_name_and_counts`, `test_zero_counts_are_left_out_and_all_zero_hides_the_counts`, `test_groups_and_rows_follow_the_display_order`, `test_a_project_name_that_is_empty_shows_the_root`, `test_the_cursor_on_the_first_run_past_a_header_marks_that_row`, `test_hovering_a_header_moves_no_cursor_and_a_row_past_it_reports_its_global_index`, `test_clicking_the_first_run_past_a_header_opens_that_run`, `test_the_counts_are_those_of_the_runs_listed_after_the_search`, `test_a_new_snapshot_reorders_headers_rows_and_the_cursor`, `test_stale_data_dims_rows_but_not_headers`. `test_runs_without_a_project_get_no_header` and `test_missing_am_shows_no_headers` already pass: they guard what must not change (no header for untagged runs; nothing under a missing am).

Run: `bash tests/run.sh tst_runs_flow`
Expected: `FAIL!  : RunsFlow::test_enter_on_the_first_run_of_the_second_project_opens_it()` at `runGroupName1` (null → TypeError).

- [ ] **Step 5: Implement the header comment, counts and entries**

In `ui/screens/RunsScreen.qml` replace the header comment (lines 10-15, from `// The Runs section: the selected project's am runs,` through `// own. Ages are read against the clock once per snapshot: there is no timer.`) with:

```qml
// The Runs section: every registered project's am runs, grouped by project
// with a header each (name; live, parked and needs-attention counts; the
// project's snapshot error), flat with no header under a project filter. Each
// run is one row (state glyph, short id, title, done/total, current phase,
// age) whose index is its position in the store's filteredRuns, the one list
// the cursor walks; headers are not cursor targets. Needs attention / Live /
// Parked / All chips apply across groups -- clicking the active chip means All
// again -- and a footer says whether the runs are watched. It reads the run
// store and asks the navigator to open a run or move the cursor; it owns no
// state of its own. Ages are read against the clock once per snapshot: there
// is no timer.
```

After `readonly property bool noProjects: ...` (Task 1) add:

```qml
  // What the list draws, in order (entriesOf).
  readonly property var entries: screen.entriesOf(screen.app.runs.groups, screen.app.runs.filteredRuns,
    screen.app.runs.projectRoots, screen.app.runs.projectErrors, screen.app.runs.projectFilter)
```

After `function sizeOf(list) { ... }` (Task 1) add:

```qml
  // A group's counts: the non-zero parts of "<n> live", "<n> parked" and
  // "<n> needs attention", in that order, joined by " · "; "" when all are zero.
  function countsText(counts) {
    var c = counts !== null && typeof counts === "object" ? counts : {}
    var parts = []
    if (c.live > 0) parts.push(c.live + " live")
    if (c.parked > 0) parts.push(c.parked + " parked")
    if (c.attention > 0) parts.push(c.attention + " needs attention")
    return parts.join(" · ")
  }

  // The list's entries, scalar values only (a Repeater converts nested ones):
  // { kind: "header", g, name, counts, error } and { kind: "run", i }, i the
  // run's index in `runs` (filteredRuns, which is displayOrder of `groups`).
  // Each group of `groups` in turn: a header unless its root is "", then its
  // runs. g counts the headers from 0; name is the project's name, else its
  // root.
  function entriesOf(groups, runs, roots, errors, filter) {
    var out = []
    var g = 0
    var i = 0
    for (var n = 0; n < screen.sizeOf(groups); n++) {
      var group = groups[n]
      var root = group.project.root
      if (root !== "")
        out.push({ kind: "header", g: g++, name: group.project.name !== "" ? group.project.name : root,
                   counts: screen.countsText(group.counts), error: "" })
      for (var j = 0; j < screen.sizeOf(group.runs); j++) out.push({ kind: "run", i: i++ })
    }
    return out
  }
```

- [ ] **Step 6: Implement the delegate and the header**

In the `UI.FilterableList { ... }` block replace

```qml
    model: screen.app.runs.filteredRuns
    rowDelegate: Component { RunRow {} }
```

with

```qml
    model: screen.entries
    rowDelegate: Component { RunEntry {} }
```

Replace the start of `component RunRow` — the lines

```qml
  component RunRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "runRow" + row.index
```

with

```qml
  // One entry of `entries`: a project's header or a run's row.
  component RunEntry: Loader {
    id: entry
    required property var modelData
    readonly property var fact: entry.modelData !== null && typeof entry.modelData === "object" ? entry.modelData : ({})

    width: screen.width
    sourceComponent: entry.fact.kind === "header" ? headerC : entry.fact.kind === "run" ? rowC : null

    Component {
      id: headerC
      RunGroupHeader {
        g: typeof entry.fact.g === "number" ? entry.fact.g : 0
        name: typeof entry.fact.name === "string" ? entry.fact.name : ""
        counts: typeof entry.fact.counts === "string" ? entry.fact.counts : ""
        error: typeof entry.fact.error === "string" ? entry.fact.error : ""
      }
    }

    Component {
      id: rowC
      RunRow { index: typeof entry.fact.i === "number" ? entry.fact.i : -1 }
    }
  }

  // A project's header: its name, its counts and, when its snapshot failed,
  // the error. Not a row: no cursor, no hover, no click.
  component RunGroupHeader: Column {
    id: header
    property int g: 0
    property string name: ""
    property string counts: ""
    property string error: ""
    readonly property real innerWidth: Math.max(0, header.width - header.leftPadding - header.rightPadding)

    objectName: "runGroup" + header.g
    width: screen.width
    leftPadding: Style.space(10)
    rightPadding: Style.space(10)
    topPadding: Style.space(4)
    spacing: Style.space(2)

    Row {
      width: header.innerWidth
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "runGroupName" + header.g
        theme: screen.theme
        font.bold: true
        width: Math.max(0, Math.min(implicitWidth,
          parent.width - (groupCounts.visible ? groupCounts.width + parent.spacing : 0)))
        text: header.name
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: groupCounts
        objectName: "runGroupCounts" + header.g
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: header.counts
      }
    }

    UI.ThemedText {
      objectName: "runGroupError" + header.g
      variant: "caption"
      theme: screen.theme
      width: header.innerWidth
      visible: text !== ""
      text: header.error
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }
  }

  // A run's row; `index` is the run's position in filteredRuns.
  component RunRow: UI.ListRow {
    id: row
    objectName: "runRow" + row.index
```

Leave the rest of `RunRow` unchanged, including the comment on why the run is read from `screen.app.runs.filteredRuns[row.index]` and not from `modelData`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen` then `bash tests/run.sh tst_runs_flow`
Expected: `0 failed` in both `Totals:` lines and no `TypeError` / `Unable to assign` lines. Every pre-existing test (rows, chips, controls, footer, malformed runs) still passes with unchanged indices.

If `test_hovering_a_header_moves_no_cursor...` reports a hover index other than -1, the mouse landed on a row: check that `RunGroupHeader` is not a `ListRow` and has no `MouseArea`.

- [ ] **Step 8: Run the architecture tests**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass (no store import, no duplicated component, no private-use glyphs).

- [ ] **Step 9: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs-screen): runs grouped by project with a header each, one cursor index over filteredRuns"
```

---

### Task 3: Snapshot errors — per group, failed projects with nothing listed, the flat project filter

**Files:**
- Modify: `ui/screens/RunsScreen.qml` — new functions `rootKey`, `projectError`; replace `entriesOf` (Task 2); `RunEntry` gains the `projectError` kind
- Modify: `tests/ui/screens/tst_runs_screen.qml` — new tests after the Task 2 `// ---- groups` tests

**Interfaces:**
- Consumes: Task 2's `entriesOf(groups, runs, roots, errors, filter)`, `RunEntry` (`entry.fact`), `RunGroupHeader.error`, `sizeOf`, `countsText`; test helpers `tagged`, `shown`, `top`, `twoProjects`.
- Produces: `function rootKey(path): string`; `function projectError(errors, root): string`; entry kind `{kind: "projectError", text}` rendered as `ThemedText` `runsProjectError`.

- [ ] **Step 1: Write the failing tests**

After the Task 2 tests (after `test_stale_data_dims_rows_but_not_headers`) add:

```qml
  // ---- snapshot errors

  function test_a_failed_group_shows_its_error_under_its_header() {
    var s = make(twoProjects()); if (!s) return
    s.runs.projectErrors = { "/home/u/b/": "AmTimeout: am status timed out." }
    var line = H.find(s.screen, "runGroupError1")
    compare(line.visible, true)
    compare(line.text, "AmTimeout: am status timed out.")
    verify(Qt.colorEqual(line.color, s.screen.theme.urgent), "drawn urgent")
    compare(line.wrapMode, Text.WordWrap)
    compare(H.find(s.screen, "runGroupError0").visible, false, "alpha did not fail")
    verify(top(s, "runGroupName1") < top(s, "runGroupError1"), "under the name")
    verify(top(s, "runGroupError1") < top(s, "runRow2"), "above the group's first run")
  }

  function test_a_failed_project_with_nothing_listed_still_shows_its_error() {
    var s = make([tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha")]); if (!s) return
    s.runs.projectRoots = [{ root: "/home/u/a", name: "alpha" }, { root: "/home/u/b", name: "beta" }]
    s.runs.projectErrors = { "/home/u/b": "AmFailed: boom", "/home/u/zzz": "AmFailed: not registered" }
    compare(H.find(s.screen, "runGroupName0").text, "alpha")
    compare(H.find(s.screen, "runGroupName1").text, "beta")
    compare(H.find(s.screen, "runGroupCounts1").visible, false, "no counts")
    compare(H.find(s.screen, "runGroupError1").text, "AmFailed: boom")
    compare(H.find(s.screen, "runGroupError1").visible, true)
    compare(H.find(s.screen, "runGroup2"), null, "an error for an unregistered root shows nothing")
    compare(s.runs.filteredRuns.length, 1, "the extra header adds no run")
    compare(H.find(s.screen, "runRow1"), null)
    s.runs.runs = [tagged(run("run-a-live0001", "started", true, {}), "/home/u/a", "alpha"),
                   tagged(run("run-b-live0002", "started", true, {}), "/home/u/b", "beta")]
    s.runs.toggleRunFilter("parked")
    compare(s.runs.filteredRuns.length, 0)
    compare(H.find(s.screen, "runsMessage").text, "No Parked runs.")
    compare(H.find(s.screen, "runGroupName0").text, "beta", "beta's runs are all filtered out; its error still shows")
    compare(H.find(s.screen, "runGroupError0").text, "AmFailed: boom")
    compare(H.find(s.screen, "runGroup1"), null, "alpha did not fail")
  }

  function test_a_project_filter_shows_a_flat_list_without_headers() {
    var s = make(twoProjects()); if (!s) return
    s.runs.projectFilter = "/home/u/b"
    compare(H.find(s.screen, "runGroup0"), null)
    compare(H.find(s.screen, "runRowId0").text, "…live0003")
    compare(H.find(s.screen, "runRow1"), null)
    compare(shown(s, "runsProjectError"), false)
    s.runs.projectErrors = { "/home/u/b/": "AmTimeout: am status timed out." }
    var line = H.find(s.screen, "runsProjectError")
    compare(line.visible, true)
    compare(line.text, "AmTimeout: am status timed out.")
    verify(Qt.colorEqual(line.color, s.screen.theme.urgent))
    compare(line.wrapMode, Text.WordWrap)
    verify(top(s, "runsProjectError") < top(s, "runRow0"), "above the first row")
    compare(H.find(s.screen, "runGroup0"), null, "still no header")
    s.runs.projectFilter = ""
    compare(shown(s, "runsProjectError"), false, "only under a project filter")
    compare(H.find(s.screen, "runGroupError1").text, "AmTimeout: am status timed out.")
    s.runs.amStatus = "missing"
    wait(20)
    compare(shown(s, "runGroup0"), false)
    compare(shown(s, "runGroup1"), false)
    s.runs.projectFilter = "/home/u/b"
    compare(shown(s, "runsProjectError"), false, "am missing hides it too")
  }

  // Review Focus 4.
  function test_malformed_errors_and_registry_entries_show_nothing_and_do_not_throw() {
    var s = make(twoProjects()); if (!s) return
    s.runs.projectRoots = [null, "x", { root: 7 }, { root: "/home/u/c", name: 3 }, { root: "/home/u/a", name: "alpha" }]
    s.runs.projectErrors = { "/home/u/b": null, "/home/u/a": 42, "/home/u/c": "AmFailed: c" }
    compare(H.find(s.screen, "runGroupError0").visible, false, "a non-string error is no error")
    compare(H.find(s.screen, "runGroupError1").visible, false)
    compare(H.find(s.screen, "runGroupName2").text, "/home/u/c", "a non-string name falls back to the root")
    compare(H.find(s.screen, "runGroupError2").text, "AmFailed: c")
    compare(H.find(s.screen, "runGroup3"), null)
    s.runs.projectErrors = null
    compare(H.find(s.screen, "runGroupError0").visible, false)
    compare(H.find(s.screen, "runGroup2"), null)
    s.runs.projectFilter = "/home/u/b"
    compare(shown(s, "runsProjectError"), false)
  }

  // Review Focus 5.
  function test_a_root_registered_twice_gets_one_failed_header() {
    var s = make([]); if (!s) return
    s.runs.projectRoots = [{ root: "/home/u/b", name: "beta" }, { root: "/home/u/b/", name: "beta again" }]
    s.runs.projectErrors = { "/home/u/b": "AmFailed: boom" }
    compare(H.find(s.screen, "runGroupName0").text, "beta", "the first registration's name")
    compare(H.find(s.screen, "runGroup1"), null)
    compare(H.find(s.screen, "runsMessage").text, "No runs yet.", "the status line still speaks about runs")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: FAIL for `test_a_failed_group_shows_its_error_under_its_header` (`runGroupError1` hidden), `test_a_failed_project_with_nothing_listed_still_shows_its_error` (`runGroupName1` null), `test_a_project_filter_shows_a_flat_list_without_headers` (`runGroup0` is beta's header, not null), `test_malformed_errors_and_registry_entries_show_nothing_and_do_not_throw` (`runGroupName2` null), `test_a_root_registered_twice_gets_one_failed_header` (`runGroupName0` null). Task 1 and 2 tests still pass.

- [ ] **Step 3: Implement root matching and error lookup**

In `ui/screens/RunsScreen.qml`, after `function countsText(counts) { ... }` add:

```qml
  // A root as the store compares roots: every trailing "/" removed, "/" for a
  // root of only slashes, "" for a non-string.
  function rootKey(path) {
    if (typeof path !== "string") return ""
    var end = path.length
    while (end > 0 && path.charAt(end - 1) === "/") end--
    if (end === 0) return path === "" ? "" : "/"
    return path.substring(0, end)
  }

  // The snapshot error `errors` ({root: sentence}) holds for `root`, keys and
  // root compared by rootKey; "" when there is none, when `root` is "", or
  // when the sentence is not a string.
  function projectError(errors, root) {
    var want = screen.rootKey(root)
    if (want === "" || errors === null || typeof errors !== "object") return ""
    var keys = Object.keys(errors)
    for (var k = 0; k < keys.length; k++) {
      if (screen.rootKey(keys[k]) === want && typeof errors[keys[k]] === "string") return errors[keys[k]]
    }
    return ""
  }
```

- [ ] **Step 4: Replace `entriesOf`**

Replace the whole Task 2 `entriesOf` function and its comment (from `// The list's entries, scalar values only` through the function's closing `}`) with:

```qml
  // The list's entries, scalar values only (a Repeater converts nested ones):
  // { kind: "header", g, name, counts, error }, { kind: "run", i } with i the
  // run's index in `runs` (filteredRuns, which is displayOrder of `groups`),
  // and { kind: "projectError", text }.
  // Under a project filter: the filtered project's error when it has one,
  // then every run, flat. Otherwise each group of `groups` in turn: a header
  // unless its root is "", then its runs; then, for each root of the registry
  // `roots` (in order, once) with an error and no group, a header with no
  // counts and no runs. g counts the headers from 0; name is the project's
  // name, else its root; error is projectError's.
  function entriesOf(groups, runs, roots, errors, filter) {
    var out = []
    if (typeof filter === "string" && filter !== "") {
      var flatError = screen.projectError(errors, filter)
      if (flatError !== "") out.push({ kind: "projectError", text: flatError })
      for (var r = 0; r < screen.sizeOf(runs); r++) out.push({ kind: "run", i: r })
      return out
    }
    var listed = Object.create(null)
    var g = 0
    var i = 0
    for (var n = 0; n < screen.sizeOf(groups); n++) {
      var group = groups[n]
      var root = group.project.root
      if (root !== "") {
        listed[root] = true
        out.push({ kind: "header", g: g++, name: group.project.name !== "" ? group.project.name : root,
                   counts: screen.countsText(group.counts), error: screen.projectError(errors, root) })
      }
      for (var j = 0; j < screen.sizeOf(group.runs); j++) out.push({ kind: "run", i: i++ })
    }
    for (var e = 0; e < screen.sizeOf(roots); e++) {
      var project = roots[e]
      if (project === null || typeof project !== "object") continue
      var key = screen.rootKey(project.root)
      if (key === "" || listed[key]) continue
      var error = screen.projectError(errors, key)
      if (error === "") continue
      listed[key] = true
      out.push({ kind: "header", g: g++, name: typeof project.name === "string" && project.name !== "" ? project.name : key,
                 counts: "", error: error })
    }
    return out
  }
```

- [ ] **Step 5: Render the `projectError` entry**

In `component RunEntry`, replace

```qml
    sourceComponent: entry.fact.kind === "header" ? headerC : entry.fact.kind === "run" ? rowC : null
```

with

```qml
    sourceComponent: entry.fact.kind === "header" ? headerC
      : entry.fact.kind === "run" ? rowC
      : entry.fact.kind === "projectError" ? projectErrorC
      : null
```

and after the `Component { id: rowC ... }` block (still inside `RunEntry`) add:

```qml
    // The filtered project's snapshot error, above its runs.
    Component {
      id: projectErrorC
      UI.ThemedText {
        objectName: "runsProjectError"
        variant: "caption"
        theme: screen.theme
        width: screen.width
        text: typeof entry.fact.text === "string" ? entry.fact.text : ""
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }
    }
```

Change the `RunEntry` comment `// One entry of \`entries\`: a project's header or a run's row.` to:

```qml
  // One entry of `entries`: a project's header, a run's row or the filtered
  // project's error line.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen` then `bash tests/run.sh tst_runs_flow`
Expected: `0 failed` in both, no `TypeError` / `Unable to assign` lines.

- [ ] **Step 7: Full verification**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass.

Run: `bash tests/run.sh`
Expected: exit status 0; every `Totals:` line shows `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs-screen): a project's snapshot error under its header, and a flat list under a project filter"
```

---

## Self-review against the spec

| spec item | task / test |
|---|---|
| B1.1 header + rows per group | T2 `test_each_project_gets_a_header_with_its_name_and_counts` |
| B1.2 root-`""` group no header | T2 `test_runs_without_a_project_get_no_header` |
| B1.3 name / root fallback | T2 `test_a_project_name_that_is_empty_shows_the_root` |
| B1.3 counts, zero parts, all-zero hidden, after chip and search | T2 tests 2, 3, RF1 |
| B1.3 error line under name, urgent, caption, wrap; root matching | T3 `test_a_failed_group_shows_its_error_under_its_header` |
| B1.4 failed project with nothing listed, registry order, once, no rows | T3 tests 7, RF5 |
| B1.5 headers not cursor targets | T2 tests 11, 12, 13 |
| B2 one index over filteredRuns, names kept, hover/click/cursor | T2 tests 4, 11, 12, 13, RF2; existing row tests |
| B2.4 Enter opens the highlighted run | T2 flow `test_enter_on_the_first_run_of_the_second_project_opens_it` |
| B3 flat list under project filter, `runsProjectError` | T3 `test_a_project_filter_shows_a_flat_list_without_headers` |
| B4 status strings, `No projects registered.` whatever chip/search, `No runs yet.` | T1 tests 1, 10; flow wording |
| B4 failed headers still show with an empty list | T3 test 7 (chip empties the list), RF5 |
| B5 unchanged; stale dimming not on headers | existing tests; T2 RF3 |
| B6 header comment | T2 Step 5 |
| am missing: no headers, no `runsProjectError` | T2 test 14, T3 test 9 |
| unregistered error key shows nothing | T3 test 7 |
| malformed run renders | existing `test_malformed_runs_render_without_throwing` |
<!-- task-pipeline: validated -->
