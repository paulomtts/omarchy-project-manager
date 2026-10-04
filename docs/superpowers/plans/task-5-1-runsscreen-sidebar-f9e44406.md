<!-- task-pipeline: validated -->
# 5.1 RunsScreen, sidebar row, Ctrl+6 (card f9e44406)

This spec narrows the "Runs screen (Ctrl+6)" and "Navigation" parts of `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` to this one subtask. Parent story: 8bb02694 "Runs screens and integration".

## Base state

Build and test in this worktree (`.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406`), not in the main checkout. The main checkout has none of the run code.

The worktree already contains:
- `core/domain/runs.js`, with `normalizeRun`, `runState`, `attention`, `escalationReason` and `errorText`.
- `core/stores/RunStore.qml`, composed as `app.runs`. It exposes `runs`, `selectedRunId`, `amStatus` (ok, missing, schema or error), `lastError`, `stale`, `watchWarning`, `watching` and `watchSchemaError`.
- `ui/components/runGlyphs.js`, with `glyphOf`.
- `Sidebar.qml`'s `runsAttention` and `runsAttentionText` properties, which are waiting for this card's row.

This card does not change `RunBadge`, `RunRollupBar`, `PhaseTimeline`, `RunIndicator` or the backend files. Its store and domain changes are limited to the additions listed under "Data the screen needs".

Note: the exploration summary given to this stage was cut off at 8000 characters, partway through its relevant-files list. That suggests the upstream stage ran past its brief. This spec covers only what the summary stated plus what I checked in the worktree's code (`ui/Shortcuts.qml`). It does not guess at the missing text.

## Scope

In scope:
- `ui/screens/RunsScreen.qml`.
- The Runs sidebar row.
- Ctrl+6.
- The "runs" and "run" view modes and the Navigator registration.
- Mounting the screen in Panel, with search.
- Enter opening the "run" mode, which renders empty until 5.2.
- The additive domain and store helpers listed below, and `App.qml` binding the search query.
- Two sentences in `docs/architecture.md`.
- Tests.

Out of scope, owned by siblings:
- 5.2 a3fe1e6a: the RunDetailScreen body, the tree, PhaseTimeline use and the logs fetch.
- 5.3 77f168a5: badges and the rollup on Board and Graph, and the CardDetail Runs section.
- RunIndicator click-to-filter (4.3 or 5.3).
- 5.4 0fa83ffa: the README and the full architecture write-up.

## Data the screen needs

The normalised run has only `id, repo_dir, milestone_id, status, lease, rows, tree`.

**`core/domain/runs.js`.** These additions are pure. They must never throw on garbage input.
- `normalizeRun` also keeps `started_at` (a string, `""` when absent). Update the exact-key assertion in `tests/core/domain/tst_runs.qml` to include it.
- `shortId(run)` returns `…` followed by the last 8 characters of the id. If the id is shorter, it uses whatever characters exist. If the id is not a string, it returns `…` alone.
- `runTitle(run)` returns `milestone_id`, falling back to `shortId`.
- `runProgress(run)` returns `{done, total}` over `tree.subtasks`. A subtask counts as done when its phases are non-empty and all `done`.
- `currentPhase(run)` returns the name of the first phase, in subtask order, whose status is `started`. It returns `""` when there is none.
- `ageText(iso, nowMs)` returns `just now` under a minute, then `Nm`, `Nh` or `Nd`, with no "ago" suffix. It returns `""` for an empty, unparsable or future value.
- `runAgeText(run, nowMs)` calls `ageText` on `lease.heartbeat_at` for dead runs (`""` when there is no lease) and on `started_at` for every other state.
- `runFilterCounts(runs)` returns `{attention, live, parked, all}`.
- `filterRuns(runs, id)` handles these ids:
  - `attention`: the result of `attention()`.
  - `live`: runs in state running.
  - `parked`: runs in state parked.
  - `all`, `""` or an unknown id: every run.
- `searchRuns(runs, q)` does a case-insensitive substring match on id, title, current phase and state name. When `q` is `""` it returns the input.

**`core/stores/RunStore.qml`.** These additions mirror ExtrasStore's issue filter.
- `property string runFilter: ""` (`""` means All).
- `property string searchQuery: ""`.
- `readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery)`.
- `toggleRunFilter(id)`: choosing the active filter returns to All.
- `projectSwitched` resets `runFilter` to `""`.

`App.qml` binds `runs.searchQuery` to `app.nav.searchQuery`. `filteredRuns` is the only filtering source: both the screen rows and `Navigator.currentList()` read it.

## Observable behaviour

### Screen

`RunsScreen.qml` has the same shape as `IssuesScreen.qml`:
- `property var app`, `navigator` and `theme`, and `signal revealRequested`.
- It is built from `FilterableList` with `chipsObjectName`, `chipPrefix` and `statusObjectName`, plus `ListRow`, `ListStatus`, `Chip`/`ChipRow`, `Badge` and `ThemedText`.
- It may import `core/domain/runs.js` and `ui/components/runGlyphs.js`. It must not import `core/stores`.

### Rows

There is one row per entry in `app.runs.filteredRuns`, in the store's order. Each row's objectName is `runRow<i>`, and its delegate is wired the same way as the Issues rows.

Each row shows:
- The glyph from `glyphOf(Runs.runState(run))`.
- The short id.
- The title.
- Progress as `done/total`, only when total > 0.
- The current phase, if not empty.
- The age (`runAgeText(run, Date.now())`), if not empty, for states other than dead and parked. Dead and parked rows show their age only inside the state text below, never twice. The screen reads `Date.now()` when `filteredRuns` changes; there is no timer, so ages refresh with each snapshot.

Some states change the row:
- **Escalated:** adds a second line with `Runs.escalationReason(run)`.
- **Dead:** reads `dead - lease lost <age> ago`, or `dead - lease lost` when there is no age.
- **Parked:** reads `parked <age>`, or `parked` when there is no age.

State is never shown by colour alone. The colours `#9b72cf` and `#d9534f` are never used. There is no new animation loop.

### Chips

The chips are "Needs attention N" (`attention`, which is escalated plus dead), "Live N" (`live`), "Parked N" (`parked`) and "All" (`all`, no count).
- Counts come from `runFilterCounts` over all runs and ignore the search text.
- "All" is active when `runFilter` is `""`.
- Clicking the active chip returns to All.
- The `/` search composes with the active chip.
- The cursor resets to 0 when the filter changes, as it does in Issues.
- When nothing matches, the ListStatus says "No runs match “<query>”." for a search and "No <chip label> runs." for a chip.

### Footer and banners

There is no am version. This differs from the card and main-spec text, because `runs-snapshot.py` does not emit a version. Showing one is a follow-up outside this card.
- The footer reads exactly `am · schema 1 · watching` when `watching` is true, and `am · schema 1 · not watching` when it is false.
- When `amStatus` is `error`, the footer shows `app.runs.lastError`.
- When `amStatus` is `schema`, a banner replaces the footer. It shows `watchSchemaError`, or `lastError` when that is empty.
- When `stale` is true, a banner reads "Run data is out of date" and the rows are dimmed to opacity 0.5.
- A non-empty `watchWarning` shows as one warning line.

### Empty and missing states

- `amStatus` `missing`: exactly one ListStatus, reading "am is not installed or not on PATH". There are no rows and no chips, because this goes through FilterableList's `error` input. The chips model is built from `runFilterCounts` with `tint: theme.dim` (the Issues chips need a tint).
- `amStatus` `ok` with no runs: a ListStatus reading "No runs for this project yet."

### Sidebar

- Add a NavRow with objectName `navRuns` and section `runs`, placed after Issues.
- It has `enabled: hasProject` and `countText: sidebar.runsAttentionText`.
- Its icon is a Nerd Font glyph written as a `\u` escape, like the existing rows, and it must pass `test_icon_glyphs.py`.
- Panel binds `runsAttention` to `Runs.attention(app.runs.runs).length`.
- Clicking the row shows the "runs" section.

### Shortcuts (`ui/Shortcuts.qml`)

- Ctrl+6 calls `navigator.showSection("runs")`. It sits after the `Qt.Key_5` line in `handleGlobalKey`.
- Update the comment that lists the chord order ("Board, Graph, Documents, Memories, Issues") to add Runs.
- Add `"run"` to the detail-mode list in `closeRequested()`, so Esc from "run" calls `goBack()`.
- Add `"run"` to the left-arrow `goBack` list in `handleMove`.

### NavigationStore

- `viewMode` gains `"runs"` and `"run"`.
- Both map to section `"runs"`, and `sectionTitle` is "Runs".

### Navigator

- `currentList()` returns `app.runs.filteredRuns` for "runs".
- `showSection("runs")` is supported. Add it to the nested viewMode ternary. As with the other sections, it resets the search; the chip filter persists.
- `buildCrumbs()` gives `Runs` for "runs" and `Runs › <shortId>` for "run". The section crumb is clickable in "run" mode (add "run" to its `clickable` list), like the other detail modes.
- Add `openRun(id)` and `restoreRunsList()`, mirroring `openIssue` and `restoreIssuesList`.
- `activateCursor()` on "runs" sets `app.runs.selectedRunId`, calls `pushReturn`, and sets viewMode to "run".
- `goBack()` handles "run" and restores "runs" with the same cursor and scroll position.
- j/k and the arrow keys move the cursor through the existing paths. `/` filters.

### Panel

- Mount RunsScreen with `app`, `navigator` and `theme`, next to IssuesScreen.
- Add "runs" to the search field's `visible` list (Panel.qml, the `searchField` visibility expression) and add the "runs" branch to its placeholder: "Search runs…". The refresh button's list is unchanged (it does not apply to runs).
- Add "run" to the detail-mode list in `focusItem`, so focus goes to `keyCatcher` rather than the hidden search field. Otherwise Esc in "run" would hit `handleSearchKey` and close the panel instead of calling `goBack`.
- The "run" mode may render empty but must not throw. `currentList()` returns `[]` for "run" (the existing fall-through), so Enter there is a no-op.

### Docs (`docs/architecture.md`)

- "Ctrl+1..5 follow the sidebar's order: Board, Graph, Documents, Memories, Issues" becomes "Ctrl+1..6 … Issues, Runs".
- "Sidebar's five nav rows" becomes "six".
- Nothing else changes.

## Error paths

- **Malformed run:** the domain helpers return defaults. The state is `unknown` and the row shows no glyph. Nothing throws.
- **Malformed or short id:** the row shows `…` plus whatever characters exist.
- **Enter on an empty list:** a no-op.
- **`missing`:** the store empties `runs`, so the Navigator list is empty and the cursor and Enter do nothing.
- **`error` or `schema`:** the store keeps the last good runs (`applySnapshot`), so the rows stay visible and navigable beside the footer or banner.
- **Project switch:** the store clears the runs and the filter, and the screen shows its empty state.
- **No project:** the sidebar row is disabled.

## Tests (write first)

Placement follows `docs/architecture.md` ("How to add", "Tests") and `tests/helpers/README.md`. UI tests use `../../helpers/find.js` and a stub `app` with normalised runs. The `tests/run.sh` output must contain no TypeError, ReferenceError, "non-existent", "Unable to assign" or "is not a function".

**`tests/ui/screens/tst_runs_screen.qml`** (UI tier, per-screen):
- Each state shows its glyph.
- The short id is formatted correctly.
- Title, progress, phase and age are shown, and empty values are omitted.
- An escalated row shows its reason line.
- A dead row reads `dead - lease lost N ago`, and a parked row reads `parked N`.
- Chip counts are correct, and each chip filters to the right rows.
- Clicking the active chip returns to All.
- A chip combined with search filters correctly, and the no-match texts are exact.
- The empty-state text is exact.
- With `missing`, there is exactly one ListStatus, with no chips or rows.
- Both footer texts are exact.
- `error` shows `lastError` in the footer.
- The `schema` banner shows, including its `lastError` fallback.
- The `stale` banner shows and the rows have opacity 0.5.
- The `watchWarning` line shows.
- A malformed run does not throw.

**`tests/ui/tst_shortcuts.qml`** (UI tier, keyboard):
- Ctrl+6 shows "runs".
- Ctrl+1..5 are unchanged.
- Esc and the left arrow in "run" call `goBack`.

**`tests/ui/tst_sidebar.qml`** (UI tier, sidebar):
- `navRuns` comes after `navIssues`.
- It is disabled without a project.
- It shows `‼N` when `runsAttention > 0` and no count at 0.

**`tests/ui/tst_sidebar_nav.qml`** (UI tier, navigation flow):
- Clicking `navRuns` sets viewMode "runs" and section "runs".

**`tests/ui/tst_navigator.qml`** (UI tier, navigator):
- `currentList()` for "runs" equals `filteredRuns`.
- Crumbs are correct for "runs" and "run".
- `activateCursor` sets `selectedRunId` and switches to "run".
- `goBack` from "run" restores the cursor.
- Enter on an empty list does nothing.

**`tests/ui/tst_runs_flow.qml`** (UI tier, cross-cutting Panel flow; this file is new):
- Ctrl+6, then a chip, then `/`, then j/k, then Enter to "run", then Esc back to "runs" with the same cursor.
- The search placeholder is "Search runs…".
- The "run" mode renders without errors.

**`tests/core/domain/tst_runs.qml`** (core domain tier):
- `normalizeRun` keeps `started_at`, and the key assertion is updated.
- `shortId`, `runTitle`, `runProgress`, `currentPhase`, `ageText`, `runFilterCounts`, `filterRuns` and `searchRuns` each return the right values, and each survives garbage input.

**`tests/core/stores/tst_run_store.qml`** (core store tier, headless):
- `filteredRuns` follows `runFilter` and `searchQuery`.
- `toggleRunFilter` toggles, and choosing the active filter returns to All.
- `projectSwitched` resets the filter.

**`tests/architecture/`** (architecture tier): must pass without changes. It covers:
- No `core/stores` imports in screens or components.
- No duplicate snippets and no type-name clashes.
- Every glyph is valid, including the new sidebar icon.

No `tests/contract` or `tests/core/backend` changes, because the backend is untouched.

---

# 5.1 RunsScreen, sidebar row, Ctrl+6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the read-only Runs list section (screen, sidebar row with attention count, Ctrl+6, "runs"/"run" view modes, Panel search) on top of the existing RunStore and run domain model.

**Architecture:** Pure helpers in `core/domain/runs.js` produce every row value, count, filter and search result. `RunStore` gains a chip filter, a search query (bound by `App` to the navigation store) and a `filteredRuns` list, which is the single source for both the screen rows and `Navigator.currentList()`. `RunsScreen.qml` is a presentational `FilterableList` like `IssuesScreen.qml`; `Navigator`, `Shortcuts`, `NavigationStore`, `Sidebar` and `Panel` register the new section the same way Issues is registered. The "run" detail mode exists for navigation only; its body is card 5.2.

**Tech Stack:** QML (Qt 6, Quickshell), `.pragma library` JavaScript, QtTest via `qmltestrunner`, pytest architecture tests, all driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/task-5-1-runsscreen-sidebar-f9e44406-design.md` (prepended verbatim above).

**Worktree (all paths below are relative to it):** `W=/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406`, branch `mon/task-5-1-runsscreen-sidebar-f9e44406`. Every command is written as `cd $W && …` with the path spelled out, because the shell's working directory resets between calls. Do not assume any code from sibling cards 5.2, 5.3 or 5.4 exists.

**Upstream note:** the exploration and spec summaries handed to this planning stage were both truncated (2000 and 8000 character caps), which suggests the upstream stages ran past their brief. This plan was written from the spec file on disk and the worktree's code, not from the truncated summaries.

## Global Constraints

- Build and test only in the worktree above; the main checkout has no run code.
- `ui/screens/**` and `ui/components/**` must not import `core/stores` (they receive `app` / `navigator` / `theme`); only `Panel.qml`, `Shortcuts.qml` and `Navigator.qml` may wire stores. Screens may import `core/domain/*.js` and `ui/components/runGlyphs.js`.
- `core/domain/*.js` stays `.pragma library`, pure, no Qt, and its new functions never throw on garbage input.
- `core/stores/*.qml` may import only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`.
- Never use the colours `#9b72cf` or `#d9534f`. No new animation loop and no new `Timer` (ages refresh with each snapshot).
- State is never shown by colour alone: every state has its glyph from `runGlyphs.js` `glyphOf`, and dead/parked rows spell their state out.
- Footer text is exactly `am · schema 1 · watching` / `am · schema 1 · not watching` (no am version: `runs-snapshot.py` emits none; showing one is a follow-up outside this card).
- Exact strings: `No runs for this project yet.`, `am is not installed or not on PATH`, `No runs match “<query>”.`, `No <chip label> runs.`, `Run data is out of date`, `Search runs…`, chip labels `Needs attention`, `Live`, `Parked`, `All`.
- Every private-use glyph in `ui/` must exist in an installed Nerd Font (`tests/architecture/test_icon_glyphs.py`); sidebar icons are written as `\u` escapes.
- No second copy of the guarded snippets (`Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:`, `CursorSurface {`) and no new QML file named like a shell or Controls type.
- Do not change `RunBadge`, `RunRollupBar`, `PhaseTimeline`, `RunIndicator`, `core/backend/**`, or the store/domain files beyond the additions this plan lists.
- `bash tests/run.sh` output must contain no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function`.

## Review Focus

1. A dead run whose last heartbeat is under a minute old must read `dead - lease lost just now`, never `dead - lease lost just now ago` (the spec's template would produce that). Pinned in Task 6 `test_dead_and_parked_rows_without_an_age`.
2. A run with a blank or non-string id, or a `null` entry in the list, must never open the "run" view or throw on Enter or click. Pinned in Task 4 `test_enter_on_an_empty_or_junk_runs_list_does_nothing` and `test_open_run_ignores_an_unknown_or_blank_id`, and Task 6 `test_malformed_runs_render_without_throwing`.
3. A search of only spaces must not hide every run. Pinned in Task 1 `test_search_runs` (`"   "` returns the input).
4. Leaving the Runs section and coming back resets the search but keeps the chip, so the user is not surprised by an empty list. Pinned in Task 4 `test_a_section_switch_resets_the_search_but_keeps_the_chip`.
5. While am is missing, no stale banner, schema banner, warning or footer may sit beside the single "am is not installed" message. Pinned in Task 6 `test_missing_am_is_one_message_with_no_chips_or_rows` (sets `stale` and `watchWarning` too).

Also worth a reviewer's eye: `normalizeRun` now carries `started_at`, so `cardRunState`'s existing `_isNewer` tie-break (which reads `started_at`) starts to apply to real snapshots, not only to hand-built test runs. That is the behaviour 1.2 designed for, but it changes which run a card badge follows when two runs touch a card.

---

### Task 1: Run row helpers in the domain model

**Files:**
- Modify: `core/domain/runs.js:43-51` (normalizeRun return) and append after line 272
- Test: `tests/core/domain/tst_runs.qml`

**Interfaces:**
- Consumes: existing `runState(run)`, `attention(runs)`, `_isObject`, `_arrayOr`, `_stringOr`, `_isFiniteNumber`, `_treeOf`, `_textOf` in `core/domain/runs.js`.
- Produces (all pure, never throw):
  - `normalizeRun(raw)` result gains `started_at: string` (`""` when absent).
  - `shortId(run) -> string` (`"…" + last 8 chars`, `"…"` when id is not a string).
  - `runTitle(run) -> string`.
  - `runProgress(run) -> { done: number, total: number }`.
  - `currentPhase(run) -> string`.
  - `ageText(iso, nowMs) -> string` (`"just now"`, `"Nm"`, `"Nh"`, `"Nd"` or `""`).
  - `runAgeText(run, nowMs) -> string`.
  - `runFilterCounts(runs) -> { attention, live, parked, all }`.
  - `filterRuns(runs, id) -> Array` (ids `attention` | `live` | `parked`; anything else is every run).
  - `searchRuns(runs, q) -> Array` (returns the input array itself when `q` is empty or only spaces).

- [ ] **Step 1: Update the exact-key assertions in `tests/core/domain/tst_runs.qml`**

In `checkDefaults`, replace:

```qml
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,status,tree", label)
    compare(r.id, "", label)
```

with:

```qml
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,started_at,status,tree", label)
    compare(r.started_at, "", label)
    compare(r.id, "", label)
```

In `test_normalize_full`, replace:

```qml
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,status,tree")
    compare(r.id, "r1")
```

with:

```qml
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,started_at,status,tree")
    compare(r.started_at, "2026-10-03T10:00:00Z")
    compare(r.id, "r1")
```

- [ ] **Step 2: Append the new helper tests to `tests/core/domain/tst_runs.qml`**

Insert before the file's final closing `}` (after `test_error_text`):

```qml
  // ---- 5.1: the Runs screen's helpers -----------------------------------------------------

  function test_normalize_keeps_started_at() {
    compare(Runs.normalizeRun(fullRaw()).started_at, "2026-10-03T10:00:00Z", "from the am runs row")
    compare(Runs.normalizeRun({ status: { run: { started_at: "2026-10-01T00:00:00Z" } } }).started_at,
            "2026-10-01T00:00:00Z", "falls back to am status")
    compare(Runs.normalizeRun({ row: { id: "r1" } }).started_at, "", "absent")
    compare(Runs.normalizeRun({ row: { started_at: null } }).started_at, "", "null")
  }

  function test_short_id() {
    compare(Runs.shortId({ id: "run-20261003-abcdef12" }), "…abcdef12", "the last 8 characters")
    compare(Runs.shortId({ id: "abc" }), "…abc", "a short id keeps what it has")
    compare(Runs.shortId({ id: "" }), "…", "empty id")
    var bad = [undefined, null, "x", 5, [], {}, { id: 7 }, { id: null }]
    for (var i = 0; i < bad.length; i++) compare(Runs.shortId(bad[i]), "…", "garbage " + i)
  }

  function test_run_title() {
    compare(Runs.runTitle(mkRun("run-0000abcd1234", "started", true, { milestone_id: "4bf4fb2f" })), "4bf4fb2f")
    compare(Runs.runTitle(mkRun("run-0000abcd1234", "started", true, { milestone_id: "" })), "…abcd1234",
            "falls back to the short id")
    compare(Runs.runTitle({ id: "r1", milestone_id: 5 }), "…r1", "a non-string milestone is no title")
    var bad = [undefined, null, "x", 5, []]
    for (var i = 0; i < bad.length; i++) compare(Runs.runTitle(bad[i]), "…", "garbage " + i)
  }

  function progressTree() {
    return { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "spec", status: "done" }, { name: "plan", status: "done" }] },
      { card_id: "t2", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] },
      { card_id: "t3", phases: [] },
      { card_id: "t4" },
      { card_id: "t5", phases: [{ name: "spec", status: "done" }, null] }
    ] }
  }

  function test_run_progress() {
    var p = Runs.runProgress(mkRun("r", "started", true, { tree: progressTree() }))
    compare(Object.keys(p).sort().join(","), "done,total")
    compare(p.done, 1, "only t1 has every phase done")
    compare(p.total, 5)
    var none = Runs.runProgress(mkRun("r", "started", true))
    compare(none.done + "/" + none.total, "0/0")
    var junk = Runs.runProgress({ tree: { subtasks: [null, "x", 5, { phases: "x" }] } })
    compare(junk.done, 0, "junk subtasks are never done")
    compare(junk.total, 1, "only object subtasks count")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" }, { tree: { subtasks: "y" } }]
    for (var i = 0; i < bad.length; i++) {
      var r = Runs.runProgress(bad[i])
      compare(r.done + "/" + r.total, "0/0", "garbage " + i)
    }
  }

  function test_current_phase() {
    compare(Runs.currentPhase(mkRun("r", "started", true, { tree: progressTree() })), "implement")
    var two = { stories: [], subtasks: [
      { card_id: "a", phases: [{ name: "spec", status: "done" }] },
      { card_id: "b", phases: [{ name: "review", status: "started" }] },
      { card_id: "c", phases: [{ name: "verify", status: "started" }] }
    ] }
    compare(Runs.currentPhase(mkRun("r", "started", true, { tree: two })), "review", "the first started phase in subtask order")
    compare(Runs.currentPhase(mkRun("r", "done", null, { tree: { stories: [], subtasks: [
      { phases: [{ name: "x", status: "done" }] }] } })), "", "none started")
    compare(Runs.currentPhase(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { phases: [{ status: "started" }, { name: "plan", status: "started" }] }] } })), "plan", "a nameless started phase is skipped")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" },
               { tree: { subtasks: [null, { phases: "x" }, { phases: [null, 5] }] } }]
    for (var i = 0; i < bad.length; i++) compare(Runs.currentPhase(bad[i]), "", "garbage " + i)
  }

  function test_age_text() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    compare(Runs.ageText("2026-10-04T11:59:30Z", now), "just now")
    compare(Runs.ageText("2026-10-04T12:00:00Z", now), "just now", "zero seconds")
    compare(Runs.ageText("2026-10-04T11:59:00Z", now), "1m")
    compare(Runs.ageText("2026-10-04T11:01:00Z", now), "59m")
    compare(Runs.ageText("2026-10-04T11:00:00Z", now), "1h")
    compare(Runs.ageText("2026-10-03T12:00:01Z", now), "23h")
    compare(Runs.ageText("2026-10-03T12:00:00Z", now), "1d")
    compare(Runs.ageText("2026-09-24T12:00:00Z", now), "10d")
    compare(Runs.ageText("2026-10-04T12:00:01Z", now), "", "the future")
    var bad = ["", "not a date", null, undefined, 5, {}, []]
    for (var i = 0; i < bad.length; i++) compare(Runs.ageText(bad[i], now), "", "garbage iso " + i)
    var badNow = [undefined, null, "x", NaN, Infinity]
    for (var j = 0; j < badNow.length; j++) compare(Runs.ageText("2026-10-04T11:00:00Z", badNow[j]), "", "garbage now " + j)
  }

  function test_run_age_text() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    compare(Runs.runAgeText(mkRun("r", "started", true, { started_at: "2026-10-04T10:00:00Z" }), now), "2h",
            "started_at for a live run")
    var dead = mkRun("d", "started", false, { started_at: "2026-10-01T00:00:00Z" })
    dead.lease.heartbeat_at = "2026-10-04T11:55:00Z"
    compare(Runs.runAgeText(dead, now), "5m", "the last heartbeat for a dead run")
    compare(Runs.runAgeText(mkRun("n", "started", null, { started_at: "2026-10-01T00:00:00Z" }), now), "",
            "a dead run with no lease has no age")
    compare(Runs.runAgeText(mkRun("p", "stopped", null, { started_at: "2026-10-03T12:00:00Z" }), now), "1d", "parked")
    compare(Runs.runAgeText(mkRun("e", "escalated", null), now), "", "no started_at")
    var bad = [undefined, null, "x", 5, [], {}, { status: "started", lease: { live: false, heartbeat_at: 5 } }]
    for (var i = 0; i < bad.length; i++) compare(Runs.runAgeText(bad[i], now), "", "garbage " + i)
  }

  function screenRuns() {
    return [
      mkRun("run-live-0001", "started", true, { milestone_id: "alpha", tree: { stories: [], subtasks: [
        { card_id: "t1", phases: [{ name: "implement", status: "started" }] }] } }),
      mkRun("run-esc-00002", "escalated", null, { milestone_id: "beta" }),
      mkRun("run-dead-0003", "started", false, { milestone_id: "gamma" }),
      mkRun("run-park-0004", "stopped", null, { milestone_id: "delta" }),
      mkRun("run-done-0005", "done", null, { milestone_id: "epsilon" })
    ]
  }

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  function test_run_filter_counts() {
    var c = Runs.runFilterCounts(screenRuns())
    compare(Object.keys(c).sort().join(","), "all,attention,live,parked")
    compare([c.attention, c.live, c.parked, c.all].join(","), "2,1,1,5")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) {
      var b = Runs.runFilterCounts(bad[i])
      compare([b.attention, b.live, b.parked, b.all].join(","), "0,0,0,0", "garbage " + i)
    }
  }

  function test_filter_runs() {
    var list = screenRuns()
    compare(ids(Runs.filterRuns(list, "attention")), "run-esc-00002,run-dead-0003")
    compare(ids(Runs.filterRuns(list, "live")), "run-live-0001")
    compare(ids(Runs.filterRuns(list, "parked")), "run-park-0004")
    var all = ids(list)
    compare(ids(Runs.filterRuns(list, "all")), all)
    compare(ids(Runs.filterRuns(list, "")), all)
    compare(ids(Runs.filterRuns(list, "bogus")), all, "an unknown id is All")
    compare(ids(Runs.filterRuns(list, undefined)), all)
    compare(ids(Runs.filterRuns(list, "constructor")), all)
    compare(Runs.filterRuns(list, "live")[0] === list[0], true, "the same objects")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.filterRuns(bad[i], "live").length, 0, "garbage " + i)
  }

  function test_search_runs() {
    var list = screenRuns()
    compare(Runs.searchRuns(list, "") === list, true, "no query returns the input itself")
    compare(Runs.searchRuns(list, "   ") === list, true, "a query of spaces hides nothing")
    compare(ids(Runs.searchRuns(list, "GAMMA")), "run-dead-0003", "title, any case")
    compare(ids(Runs.searchRuns(list, "esc-0")), "run-esc-00002", "id")
    compare(ids(Runs.searchRuns(list, "implem")), "run-live-0001", "current phase")
    compare(ids(Runs.searchRuns(list, "parked")), "run-park-0004", "state name")
    compare(ids(Runs.searchRuns(list, "dead")), "run-dead-0003", "dead is a state name too")
    compare(Runs.searchRuns(list, "zzz").length, 0)
    compare(ids(Runs.searchRuns([null, 5, list[1]], "beta")), "run-esc-00002", "junk entries never match")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.searchRuns(bad[i], "a").length, 0, "garbage " + i)
  }
```

- [ ] **Step 3: Run the domain test to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/core/domain/tst_runs.qml`
Expected: FAIL. `DomainRuns::test_normalize_full` and `test_normalize_garbage` fail on the key list (no `started_at`), and the new tests report `TypeError: Property 'shortId' of object [object Object] is not a function` (and likewise for the other new names).

- [ ] **Step 4: Keep `started_at` in `normalizeRun`**

In `core/domain/runs.js`, in the object `normalizeRun` returns, replace:

```js
    status: firstText(run.status, row.status),
    lease: lease,
```

with:

```js
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    lease: lease,
```

- [ ] **Step 5: Append the Runs-screen helpers to `core/domain/runs.js`**

Append at the end of the file (after `errorText`):

```js
// ---- Runs screen (5.1) -------------------------------------------------------------------
//
// What one row of the Runs screen shows, and the chip filters and the search
// over the list. Pure and never throwing, like the rest of this file.

function _subtasksOf(run) { return _arrayOr(_treeOf(run).subtasks) }

// "…" and the last 8 characters of the id (all of a shorter one); "…" alone
// when the id is not a string.
function shortId(run) {
  var id = _isObject(run) ? run.id : undefined
  return typeof id === "string" ? "…" + id.slice(-8) : "…"
}

// The run's milestone, else its short id.
function runTitle(run) {
  var milestone = _isObject(run) ? _stringOr(run.milestone_id) : ""
  return milestone !== "" ? milestone : shortId(run)
}

// How many of the run's subtasks are through. A subtask is done when it has
// phases and every one of them is `done`; only object subtasks count at all.
function runProgress(run) {
  var subtasks = _subtasksOf(run)
  var done = 0, total = 0
  for (var i = 0; i < subtasks.length; i++) {
    if (!_isObject(subtasks[i])) continue
    total += 1
    var phases = _arrayOr(subtasks[i].phases)
    var allDone = phases.length > 0
    for (var j = 0; allDone && j < phases.length; j++) allDone = _isObject(phases[j]) && phases[j].status === "done"
    if (allDone) done += 1
  }
  return { done: done, total: total }
}

// The name of the first `started` phase, in subtask order; "" when none is.
function currentPhase(run) {
  var subtasks = _subtasksOf(run)
  for (var i = 0; i < subtasks.length; i++) {
    var phases = _isObject(subtasks[i]) ? _arrayOr(subtasks[i].phases) : []
    for (var j = 0; j < phases.length; j++) {
      if (!_isObject(phases[j]) || phases[j].status !== "started") continue
      var name = _textOf(phases[j].name)
      if (name !== "") return name
    }
  }
  return ""
}

// How long ago an ISO time was, without "ago": "just now" under a minute, then
// "Nm", "Nh" or "Nd". "" for an empty, unparsable or future time, or a clock
// that is not a finite number.
function ageText(iso, nowMs) {
  if (typeof iso !== "string" || iso === "" || !_isFiniteNumber(nowMs)) return ""
  var t = Date.parse(iso)
  if (!isFinite(t)) return ""
  var diff = nowMs - t
  if (diff < 0) return ""
  if (diff < 60000) return "just now"
  if (diff < 3600000) return Math.floor(diff / 60000) + "m"
  if (diff < 86400000) return Math.floor(diff / 3600000) + "h"
  return Math.floor(diff / 86400000) + "d"
}

// A row's age: since the last heartbeat for a dead run ("" with no lease),
// since it started for every other state.
function runAgeText(run, nowMs) {
  if (runState(run) === "dead") return _isObject(run.lease) ? ageText(run.lease.heartbeat_at, nowMs) : ""
  return ageText(_isObject(run) ? run.started_at : "", nowMs)
}

function _withState(list, state) {
  var out = []
  for (var i = 0; i < list.length; i++) if (runState(list[i]) === state) out.push(list[i])
  return out
}

// The chip counts, over every run (the search never narrows them).
function runFilterCounts(runs) {
  var list = _arrayOr(runs)
  return {
    attention: attention(list).length,
    live: _withState(list, "running").length,
    parked: _withState(list, "parked").length,
    all: list.length
  }
}

// One chip's runs, same objects in input order. `all`, "" or any unknown id is
// every run.
function filterRuns(runs, id) {
  var list = _arrayOr(runs)
  if (id === "attention") return attention(list)
  if (id === "live") return _withState(list, "running")
  if (id === "parked") return _withState(list, "parked")
  return list
}

// Case-insensitive substring match on the id, title, current phase and state
// name. An empty (or all-space) query returns the input itself.
function searchRuns(runs, q) {
  var list = _arrayOr(runs)
  if (typeof q !== "string" || q.trim() === "") return list
  var needle = q.trim().toLowerCase()
  var out = []
  for (var i = 0; i < list.length; i++) {
    var run = list[i]
    if (!_isObject(run)) continue
    var hay = [_stringOr(run.id), runTitle(run), currentPhase(run), runState(run)].join("\n").toLowerCase()
    if (hay.indexOf(needle) >= 0) out.push(run)
  }
  return out
}
```

- [ ] **Step 6: Run the domain test to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/core/domain/tst_runs.qml`
Expected: `Totals: N passed, 0 failed` for `DomainRuns`, pytest green, no TypeError lines.

- [ ] **Step 7: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add core/domain/runs.js tests/core/domain/tst_runs.qml && git commit -m "feat(runs): row, filter and search helpers for the Runs screen"
```

---

### Task 2: Run filter and search in RunStore, wired by App

**Files:**
- Modify: `core/stores/RunStore.qml:20-33` (properties), `:172-184` (projectSwitched), new function after `refresh()`
- Modify: `core/stores/App.qml:100-107` (the `runs` block)
- Test: `tests/core/stores/tst_run_store.qml`, `tests/core/stores/tst_app_runs.qml`

**Interfaces:**
- Consumes: `Runs.filterRuns(runs, id)`, `Runs.searchRuns(runs, q)` from Task 1.
- Produces:
  - `RunStore.runFilter: string` (`""` = All, else `attention` | `live` | `parked`).
  - `RunStore.searchQuery: string`.
  - `RunStore.filteredRuns: var` (readonly array).
  - `RunStore.toggleRunFilter(id: string)`; `"all"` or the active id gives `""`.
  - `signal RunStore.runFilterToggled()`, emitted by every `toggleRunFilter` call.
  - App binds `runs.searchQuery: app.nav.searchQuery` and resets `app.nav.cursorIndex = 0`, `app.nav.scrollOnCursor = false` on `runFilterToggled`.

- [ ] **Step 1: Write the failing store tests**

In `tests/core/stores/tst_run_store.qml`, add a spy component right after `property string rootB: "/home/u/b"`:

```qml
  Component { id: spyC; SignalSpy {} }
```

Then insert before the file's final closing `}`:

```qml
  // ---- the Runs screen's filter and search (5.1)

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  function screenEntries() {
    return [entry("live1", "started", true), entry("esc1", "escalated", false),
            entry("dead1", "started", false), entry("park1", "stopped", false)]
  }

  function test_filtered_runs_follow_the_filter_and_the_search() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    compare(store.runFilter, "")
    compare(store.searchQuery, "")
    compare(ids(store.filteredRuns), "live1,esc1,dead1,park1")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "esc1,dead1")
    store.searchQuery = "DEAD"
    compare(ids(store.filteredRuns), "dead1", "the search composes with the filter")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "dead1")
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "live1,esc1,dead1,park1")
  }

  function test_toggle_run_filter_and_back_to_all() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    store.toggleRunFilter("live")
    compare(store.runFilter, "live")
    compare(spy.count, 1)
    store.toggleRunFilter("parked")
    compare(store.runFilter, "parked", "another chip replaces the filter")
    store.toggleRunFilter("parked")
    compare(store.runFilter, "", "the active chip again is All")
    store.toggleRunFilter("attention")
    store.toggleRunFilter("all")
    compare(store.runFilter, "", "the All chip is All")
    compare(spy.count, 5)
  }

  function test_a_project_switch_resets_the_filter() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    store.toggleRunFilter("attention")
    store.project = rootB
    compare(store.runFilter, "")
    compare(store.filteredRuns.length, 0)
  }
```

In `tests/core/stores/tst_app_runs.qml`, insert before the final closing `}`:

```qml
  // ---- the Runs screen's search and filter (5.1)

  function test_the_search_query_follows_the_navigation_store() {
    var app = makeBare(); if (!app) return
    app.nav.searchQuery = "gamma"
    compare(app.runs.searchQuery, "gamma")
    app.nav.searchQuery = ""
    compare(app.runs.searchQuery, "")
  }

  function test_a_filter_change_puts_the_cursor_home() {
    var app = makeBare(); if (!app) return
    app.nav.cursorIndex = 3
    app.nav.scrollOnCursor = true
    app.runs.toggleRunFilter("live")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
  }
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/core/stores/tst_run_store.qml && bash tests/run.sh tests/core/stores/tst_app_runs.qml`
Expected: FAIL. `filteredRuns` is undefined (`TypeError: Cannot call method 'map' of undefined`), `toggleRunFilter` "is not a function", and `app.runs.searchQuery` is undefined.

- [ ] **Step 3: Add the filter, search and list to `core/stores/RunStore.qml`**

After the line `property string watchWarning: ""    // the corrupt-journal chip; "" when there is none`, add:

```qml

  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and is reset by a project switch.
  property string runFilter: ""
  property string searchQuery: ""
  // The chip changed: a different list, so the cursor goes home (App's job).
  signal runFilterToggled()
  // The one filtered list: the screen's rows and the navigator's cursor list.
  readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery)
```

After the `refresh()` function, add:

```qml

  // A chip was chosen: the All chip, or the active one again, means All.
  function toggleRunFilter(id) {
    store.runFilter = id === "all" || id === store.runFilter ? "" : String(id || "")
    store.runFilterToggled()
  }
```

In `projectSwitched()`, replace:

```qml
    store.selectedRunId = ""
    store.lastError = ""
```

with:

```qml
    store.selectedRunId = ""
    store.runFilter = ""
    store.lastError = ""
```

- [ ] **Step 4: Wire the search query and the cursor reset in `core/stores/App.qml`**

Replace:

```qml
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
  }
```

with:

```qml
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    active: app.panelOpen
    searchQuery: app.nav.searchQuery
    onRunFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }
```

- [ ] **Step 5: Run the store tests to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/core/stores/tst_run_store.qml && bash tests/run.sh tests/core/stores/tst_app_runs.qml`
Expected: both report `0 failed`; pytest (including `tests/architecture/test_layers.py`) green.

- [ ] **Step 6: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add core/stores/RunStore.qml core/stores/App.qml tests/core/stores/tst_run_store.qml tests/core/stores/tst_app_runs.qml && git commit -m "feat(runs): run filter, search and filteredRuns in RunStore"
```

---

### Task 3: "runs" and "run" view modes in NavigationStore

**Files:**
- Modify: `core/stores/NavigationStore.qml:9-18`
- Test: `tests/core/stores/tst_navigation_store.qml`

**Interfaces:**
- Produces: `nav.viewMode` accepts `"runs"` and `"run"`; both give `nav.section === "runs"` and `nav.sectionTitle === "Runs"`.

- [ ] **Step 1: Write the failing test**

In `tests/core/stores/tst_navigation_store.qml`, after `test_the_issues_view_modes_share_one_section`, add:

```qml
  function test_the_runs_view_modes_share_one_section() {
    var nav = make(); if (!nav) return
    nav.viewMode = "runs"
    compare(nav.section, "runs")
    compare(nav.sectionTitle, "Runs")
    nav.viewMode = "run"
    compare(nav.section, "runs")
    compare(nav.sectionTitle, "Runs")
  }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/core/stores/tst_navigation_store.qml`
Expected: FAIL in `test_the_runs_view_modes_share_one_section` with `Actual: board`, `Expected: runs`.

- [ ] **Step 3: Map the modes to the section**

In `core/stores/NavigationStore.qml`, replace:

```qml
  property string viewMode: "board"   // "board" | "entry" | "documents" | "document" | "graph" | "memories" | "memory" | "issues" | "issue"

  readonly property string section: (viewMode === "documents" || viewMode === "document") ? "documents"
    : (viewMode === "memories" || viewMode === "memory") ? "memories"
    : (viewMode === "issues" || viewMode === "issue") ? "issues"
```

with:

```qml
  property string viewMode: "board"   // "board" | "entry" | "documents" | "document" | "graph" | "memories" | "memory" | "issues" | "issue" | "runs" | "run"

  readonly property string section: (viewMode === "documents" || viewMode === "document") ? "documents"
    : (viewMode === "memories" || viewMode === "memory") ? "memories"
    : (viewMode === "issues" || viewMode === "issue") ? "issues"
    : (viewMode === "runs" || viewMode === "run") ? "runs"
```

and replace:

```qml
    : section === "memories" ? "Memories" : section === "issues" ? "Issues" : "Board"
```

with:

```qml
    : section === "memories" ? "Memories" : section === "issues" ? "Issues" : section === "runs" ? "Runs" : "Board"
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/core/stores/tst_navigation_store.qml`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add core/stores/NavigationStore.qml tests/core/stores/tst_navigation_store.qml && git commit -m "feat(nav): runs and run view modes share the Runs section"
```

---

### Task 4: Navigator registration for Runs

**Files:**
- Modify: `ui/Navigator.qml` (import, `currentList`, `buildCrumbs`, `activateCursor`, `showSection`, new `openRun`/`restoreRunsList`, `goBack`)
- Test: `tests/ui/tst_navigator.qml`

**Interfaces:**
- Consumes: `app.runs.filteredRuns`, `app.runs.runs`, `app.runs.selectedRunId`, `app.runs.toggleRunFilter` (Task 2); `nav.section`/`sectionTitle` for "runs"/"run" (Task 3); `Runs.shortId(run)` (Task 1).
- Produces:
  - `navi.currentList()` returns `app.runs.filteredRuns` in "runs" (and `[]` in "run").
  - `navi.showSection("runs")`.
  - `navi.openRun(id)`: a no-op unless `id` is a non-empty string naming a run in `app.runs.runs`; otherwise sets `selectedRunId`, pushes the return slot, sets viewMode `"run"`, cursor 0.
  - `navi.restoreRunsList()`: clears `selectedRunId`, viewMode `"runs"`, restores cursor and scroll.
  - Crumbs: `[{label: "Runs"}]` in "runs"; `[{label: "Runs", clickable: true}, {label: Runs.shortId({id: selectedRunId}), clickable: false}]` in "run".
  - `navi.goBack()` from "run" calls `restoreRunsList()`.

- [ ] **Step 1: Write the failing navigator tests**

In `tests/ui/tst_navigator.qml`, insert before the final closing `}`:

```qml
  // ---- Runs (5.1)

  function runOf(id, status, live, milestone) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] } }
  }

  // The navigator in the Runs section with three runs. Selecting the project
  // launched a snapshot of a helper that does not exist here; it is cancelled
  // so its late exit can never touch the runs set below.
  function withRuns() {
    var n = make(); if (!n) return null
    n.app.runs.snapshotRunner.cancel()
    n.app.runs.runs = [runOf("run-0000000000a1", "started", true, "alpha"),
                       runOf("run-0000000000b2", "escalated", null, "beta"),
                       runOf("run-0000000000c3", "stopped", null, "gamma")]
    n.showSection("runs")
    wait(0)
    return n
  }
  function runIds(list) { return list.map(function(r) { return r ? r.id : "null" }).join(",") }
  function crumbLabels(crumbs) { return crumbs.map(function(c) { return c.label }).join(" > ") }

  function test_the_runs_section_lists_the_filtered_runs() {
    var n = withRuns(); if (!n) return
    compare(n.app.nav.viewMode, "runs")
    compare(runIds(n.currentList()), runIds(n.app.runs.filteredRuns))
    compare(n.currentList().length, 3)
    n.app.runs.toggleRunFilter("parked")
    compare(runIds(n.currentList()), "run-0000000000c3", "the list is the store's filtered one")
    compare(crumbLabels(n.crumbs), "Runs")
    compare(n.crumbs[0].clickable, false)
  }

  function test_enter_opens_a_run_and_back_restores_the_cursor_and_scroll() {
    var n = withRuns(); if (!n) return
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 120
    n.activateCursor()
    compare(n.app.runs.selectedRunId, "run-0000000000b2")
    compare(n.app.nav.viewMode, "run")
    compare(n.app.nav.section, "runs")
    compare(n.app.nav.cursorIndex, 0)
    compare(crumbLabels(n.crumbs), "Runs > …000000b2")
    compare(n.crumbs[0].clickable, true)
    compare(n.currentList().length, 0, "the run view has no cursor list yet")
    wait(0)
    compare(tc.flick.contentY, 0)
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.nav.cursorIndex, 1)
    compare(n.app.runs.selectedRunId, "")
    wait(0)
    compare(tc.flick.contentY, 120)
  }

  function test_the_section_crumb_of_an_open_run_goes_back() {
    var n = withRuns(); if (!n) return
    n.openRun("run-0000000000a1")
    compare(n.app.nav.viewMode, "run")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "runs")
  }

  function test_enter_on_an_empty_or_junk_runs_list_does_nothing() {
    var n = withRuns(); if (!n) return
    n.app.runs.runs = []
    n.activateCursor()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.selectedRunId, "")
    n.app.runs.runs = [{}, null]
    n.app.nav.cursorIndex = 0
    n.activateCursor()
    n.app.nav.cursorIndex = 1
    n.activateCursor()
    compare(n.app.nav.viewMode, "runs", "a run without an id opens nothing")
    compare(n.app.runs.selectedRunId, "")
  }

  function test_open_run_ignores_an_unknown_or_blank_id() {
    var n = withRuns(); if (!n) return
    var bad = ["", "nope", null, undefined, 5]
    for (var i = 0; i < bad.length; i++) {
      n.openRun(bad[i])
      compare(n.app.nav.viewMode, "runs", "id " + i)
      compare(n.app.runs.selectedRunId, "", "id " + i)
    }
  }

  function test_a_section_switch_resets_the_search_but_keeps_the_chip() {
    var n = withRuns(); if (!n) return
    n.app.runs.toggleRunFilter("attention")
    n.app.nav.searchQuery = "beta"
    n.showSection("board")
    n.showSection("runs")
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.nav.searchQuery, "")
    compare(n.app.runs.searchQuery, "")
    compare(n.app.runs.runFilter, "attention")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_navigator.qml`
Expected: FAIL. `showSection("runs")` lands on `board`, and `n.openRun` "is not a function".

- [ ] **Step 3: Implement the Runs registration in `ui/Navigator.qml`**

Add the import under `import "../core/domain/board.js" as Board`:

```qml
import "../core/domain/runs.js" as Runs
```

In `currentList()`, after the line `if (navi.app.nav.viewMode === "issue") return navi.app.extras.detailLinkList`, add:

```qml
    if (navi.app.nav.viewMode === "runs") return navi.app.runs.filteredRuns
```

In `buildCrumbs()`, replace:

```qml
                    clickable: mode === "entry" || mode === "document" || mode === "memory" || mode === "issue" }
```

with:

```qml
                    clickable: mode === "entry" || mode === "document" || mode === "memory" || mode === "issue" || mode === "run" }
    if (mode === "run")
      return [section, { label: Runs.shortId({ id: navi.app.runs.selectedRunId }), clickable: false }]
```

In `activateCursor()`, replace:

```qml
    else if (navi.app.nav.viewMode === "entry") navi.openBlocker(list[navi.app.nav.cursorIndex].id)
```

with:

```qml
    else if (navi.app.nav.viewMode === "entry") navi.openBlocker(list[navi.app.nav.cursorIndex].id)
    else if (navi.app.nav.viewMode === "runs") {
      var run = list[navi.app.nav.cursorIndex]
      navi.openRun(run ? run.id : "")
    }
```

In `showSection()`, replace:

```qml
      : name === "memories" ? "memories" : name === "issues" ? "issues" : "board"
```

with:

```qml
      : name === "memories" ? "memories" : name === "issues" ? "issues" : name === "runs" ? "runs" : "board"
```

After `restoreIssuesList()` (before `goBack()`), add:

```qml
  // ---- Runs: the runs themselves live in RunStore; the navigation and focus
  // work around them is here. The run view's body is card 5.2's.
  function openRun(id) {
    if (typeof id !== "string" || id === "") return
    var runs = navi.app.runs.runs
    var found = false
    for (var i = 0; i < runs.length && !found; i++) found = !!runs[i] && runs[i].id === id
    if (!found) return
    navi.app.runs.selectedRunId = id
    navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "run"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function restoreRunsList() {
    navi.app.runs.selectedRunId = ""
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = "runs"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }
```

In `goBack()`, after the line `if (navi.app.nav.viewMode === "document") { navi.restoreDocumentsList(); return }`, add:

```qml
    if (navi.app.nav.viewMode === "run") { navi.restoreRunsList(); return }
```

- [ ] **Step 4: Run them to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_navigator.qml`
Expected: `Navigator` reports `0 failed`, no TypeError lines.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add ui/Navigator.qml tests/ui/tst_navigator.qml && git commit -m "feat(nav): register the Runs section, openRun and restoreRunsList"
```

---

### Task 5: Ctrl+6, Escape and the left arrow from a run

**Files:**
- Modify: `ui/Shortcuts.qml:18-38` (comment, Ctrl+6, `closeRequested`) and `:47` (`handleMove`)
- Test: `tests/ui/tst_shortcuts.qml`

**Interfaces:**
- Consumes: `navigator.showSection("runs")`, `navigator.openRun(id)`, `navigator.goBack()` (Task 4).
- Produces: `handleGlobalKey` returns true for Ctrl+6 and shows "runs"; `closeRequested()` and `handleMove(-1, 0)` go back from "run".

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_shortcuts.qml`, insert before the `// ---- The search field` comment:

```qml
  // ---- Runs (5.1)

  function inRuns() {
    var s = make(); if (!s) return null
    // The snapshot the project selection launched cannot run here.
    s.app.runs.snapshotRunner.cancel()
    s.app.runs.runs = [{ id: "run-0000000000a1", repo_dir: "/home/u/a", milestone_id: "alpha", status: "escalated",
                         started_at: "", lease: null, rows: [], tree: { stories: [], subtasks: [] } }]
    s.navigator.showSection("runs")
    return s
  }

  function test_ctrl_6_opens_the_runs_section_after_the_first_five() {
    var s = make(); if (!s) return
    var wanted = ["board", "graph", "documents", "memories", "issues", "runs"]
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5, Qt.Key_6]
    for (var i = 0; i < digits.length; i++) {
      compare(s.handleGlobalKey(ctrl(digits[i])), true, wanted[i])
      compare(s.app.nav.section, wanted[i])
    }
    compare(s.app.nav.viewMode, "runs")
  }

  function test_ctrl_6_is_ignored_while_a_delete_is_being_confirmed() {
    var s = make(); if (!s) return
    s.app.deleter.openDelete(s.app.projects.selectedProject)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "board")
  }

  function test_escape_and_the_left_arrow_go_back_from_an_open_run() {
    var s = inRuns(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.nav.viewMode, "run")
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs")
    compare(tc.calls.indexOf("close"), -1, "Escape went back instead of closing the panel")
    s.navigator.openRun("run-0000000000a1")
    s.handleMove(-1, 0)
    compare(s.app.nav.viewMode, "runs")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_shortcuts.qml`
Expected: FAIL. Ctrl+6 returns `false`; Escape in "run" calls `close` and leaves viewMode `run`.

- [ ] **Step 3: Implement in `ui/Shortcuts.qml`**

Replace the comment:

```qml
  // move things underneath it. The digit chords follow the order the sidebar
  // lists its sections in (Board, Graph, Documents, Memories, Issues) --
  // renumbering one means renumbering the sidebar too.
```

with:

```qml
  // move things underneath it. The digit chords follow the order the sidebar
  // lists its sections in (Board, Graph, Documents, Memories, Issues, Runs) --
  // renumbering one means renumbering the sidebar too.
```

After the line `if (event.key === Qt.Key_5) { keys.navigator.showSection("issues"); return true }`, add:

```qml
    if (event.key === Qt.Key_6) { keys.navigator.showSection("runs"); return true }
```

In `closeRequested()`, replace:

```qml
keys.app.nav.viewMode === "issue") ? keys.navigator.goBack() : keys.actions.close()))
```

with:

```qml
keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
```

In `handleMove()`, replace:

```qml
keys.app.nav.viewMode === "issue")) { keys.navigator.goBack(); return }
```

with:

```qml
keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run")) { keys.navigator.goBack(); return }
```

- [ ] **Step 4: Run them to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_shortcuts.qml`
Expected: `Shortcuts` reports `0 failed`, including the unchanged `test_the_ctrl_digits_follow_the_order_of_the_sidebar_sections`.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add ui/Shortcuts.qml tests/ui/tst_shortcuts.qml && git commit -m "feat(keys): Ctrl+6 opens Runs; Escape and left arrow leave a run"
```

---

### Task 6: RunsScreen

**Files:**
- Create: `ui/screens/RunsScreen.qml`
- Test: `tests/ui/screens/tst_runs_screen.qml` (new)

**Interfaces:**
- Consumes from `app`: `app.nav.viewMode`, `app.nav.searchQuery`, `app.nav.cursorIndex`, `app.nav.scrollOnCursor`, `app.projects.selectedProject`, `app.runs.runs`, `app.runs.filteredRuns`, `app.runs.runFilter`, `app.runs.toggleRunFilter(id)`, `app.runs.amStatus`, `app.runs.lastError`, `app.runs.stale`, `app.runs.watchWarning`, `app.runs.watching`, `app.runs.watchSchemaError`. From `navigator`: `hoverCursor(index)`, `openRun(id)`. Domain: Task 1 helpers plus `Runs.runState`, `Runs.escalationReason`; `RunGlyphs.glyphOf`.
- Produces: `RunsScreen { app; navigator; theme; signal revealRequested(var item) }` with objectNames `runsView`, `runChips`, `runChip<id>` (`attention`, `live`, `parked`, `all`), `runsMessage`, `runRow<i>`, `runRowGlyph<i>`, `runRowId<i>`, `runRowTitle<i>`, `runRowProgress<i>`, `runRowPhase<i>`, `runRowAge<i>`, `runRowState<i>`, `runRowReason<i>`, `runsSchemaBanner`, `runsStaleBanner`, `runsWarning`, `runsFooter`.

Note: the glyph is drawn as a plain `ThemedText` rather than inside a `Badge`, so no pill or pulse is added (no new animation, and `RunBadge` stays untouched for 5.3).

- [ ] **Step 1: Write the failing screen test**

Create `tests/ui/screens/tst_runs_screen.qml`:

```qml
// tests/ui/screens/tst_runs_screen.qml
// ui/screens/RunsScreen.qml on its own: the rows it renders, the chips, the
// footer and banners, and the empty and missing states. A stub app: a REAL
// NavigationStore, plus a plain object carrying the RunStore properties the
// screen reads (the real store's `watching` is a read-only alias that cannot
// be set from a test), filtered through the same domain functions the store
// uses. The navigator is a recorder.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../core/domain/runs.js" as Runs
import "../../../ui/components/runGlyphs.js" as RG

TestCase {
  id: tc
  name: "RunsScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  readonly property int minute: 60000

  Component { id: hostC; Item { width: 500; height: 700 } }

  Component {
    id: runsC
    QtObject {
      id: rs
      property var runs: []
      property string runFilter: ""
      property string searchQuery: ""
      property string selectedRunId: ""
      property string amStatus: "ok"
      property string lastError: ""
      property bool stale: false
      property string watchWarning: ""
      property bool watching: true
      property string watchSchemaError: ""
      readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" } })
    }
  }

  Component {
    id: naviC
    QtObject {
      property string opened: ""
      property int hovered: -1
      function openRun(id) { opened = String(id) }
      function hoverCursor(index) { hovered = index }
    }
  }

  function make(list) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    runs.searchQuery = Qt.binding(function() { return nav.searchQuery })
    var app = appC.createObject(host, { nav: nav, runs: runs })
    var navi = naviC.createObject(host)
    var sC = Qt.createComponent("../../../ui/screens/RunsScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: navi })
    nav.viewMode = "runs"
    runs.runs = list || []
    wait(20)
    return { app: app, runs: runs, nav: nav, navi: navi, screen: screen }
  }

  function ago(ms) { return new Date(Date.now() - ms).toISOString() }

  // Two clicks inside the double-click interval (400 ms) make the second one a
  // double-click, which a MouseArea does not report as `clicked`. Every click in
  // this file goes through here so a test may click more than once.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // A normalised run, as RunStore holds them. live === null means no lease.
  function run(id, status, live, opts) {
    var o = opts || {}
    return { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "" : o.milestone,
             status: status, started_at: o.started_at || "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: o.heartbeat_at || "", accepting: true, live: live },
             rows: [], tree: o.tree || { stories: [], subtasks: [] } }
  }

  // 0 running, 1 escalated, 2 dead, 3 parked, 4 cancelled (nothing but an id), 5 done.
  function sample() {
    return [
      run("run-20261004-live0001", "started", true, { milestone: "alpha", started_at: ago(5 * tc.minute), tree: { stories: [], subtasks: [
        { card_id: "t1", phases: [{ name: "spec", status: "done" }] },
        { card_id: "t2", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] }] } }),
      run("run-20261004-escl0002", "escalated", null, { milestone: "beta", tree: { stories: [], subtasks: [
        { card_id: "t3", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } }),
      run("run-20261004-dead0003", "started", false, { milestone: "gamma", started_at: ago(180 * tc.minute),
                                                       heartbeat_at: ago(7 * tc.minute) }),
      run("run-20261004-park0004", "stopped", null, { milestone: "delta", started_at: ago(120 * tc.minute) }),
      run("run-20261004-canc0005", "cancelled", null, {}),
      run("run-20261004-done0006", "done", null, { milestone: "epsilon" })
    ]
  }

  // ---- rows

  function test_each_state_shows_its_glyph() {
    var s = make(sample()); if (!s) return
    var states = ["running", "escalated", "dead", "parked", "cancelled", "done"]
    for (var i = 0; i < states.length; i++) {
      var glyph = H.find(s.screen, "runRowGlyph" + i)
      verify(glyph, "row " + i)
      compare(String(glyph.text), RG.glyphOf(states[i]), states[i])
      compare(glyph.visible, true, states[i])
    }
  }

  function test_a_row_shows_short_id_title_progress_phase_and_age() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRowTitle0").text, "alpha")
    compare(H.find(s.screen, "runRowProgress0").text, "1/2")
    compare(H.find(s.screen, "runRowPhase0").text, "implement")
    compare(H.find(s.screen, "runRowAge0").text, "5m")
    compare(H.find(s.screen, "runRowAge0").visible, true)
    compare(H.find(s.screen, "runRowState0").visible, false)
  }

  function test_empty_values_are_left_out() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowTitle4").text, "…canc0005", "the title falls back to the short id")
    compare(H.find(s.screen, "runRowProgress4").visible, false)
    compare(H.find(s.screen, "runRowPhase4").visible, false)
    compare(H.find(s.screen, "runRowAge4").visible, false)
    compare(H.find(s.screen, "runRowReason4").visible, false)
    compare(H.find(s.screen, "runRowState4").visible, false)
  }

  function test_an_escalated_row_carries_its_reason() {
    var s = make(sample()); if (!s) return
    var reason = H.find(s.screen, "runRowReason1")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    compare(H.find(s.screen, "runRowReason0").visible, false, "only escalated rows")
  }

  function test_dead_and_parked_rows_name_their_state_with_the_age_once() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowState2").text, "dead - lease lost 7m ago")
    compare(H.find(s.screen, "runRowState2").visible, true)
    compare(H.find(s.screen, "runRowAge2").visible, false, "the age is not shown twice")
    compare(H.find(s.screen, "runRowState3").text, "parked 2h")
    compare(H.find(s.screen, "runRowAge3").visible, false)
  }

  function test_dead_and_parked_rows_without_an_age() {
    var s = make([run("run-x-dead0001", "started", null, {}), run("run-x-park0002", "stopped", null, {}),
                  run("run-x-just0003", "started", false, { heartbeat_at: ago(10000) })]); if (!s) return
    compare(H.find(s.screen, "runRowState0").text, "dead - lease lost")
    compare(H.find(s.screen, "runRowState1").text, "parked")
    compare(H.find(s.screen, "runRowState2").text, "dead - lease lost just now", "never \"just now ago\"")
  }

  function test_clicking_a_row_asks_the_navigator_to_open_that_run() {
    var s = make(sample()); if (!s) return
    tap(H.find(s.screen, "runRow2"))
    compare(s.navi.opened, "run-20261004-dead0003")
  }

  function test_hovering_a_row_moves_the_cursor_through_the_navigator() {
    var s = make(sample()); if (!s) return
    var row = H.find(s.screen, "runRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(s.navi.hovered, 1)
  }

  function test_the_cursor_row_follows_the_navigation_store() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = 2
    compare(H.find(s.screen, "runRow2").hasCursor, true)
    compare(H.find(s.screen, "runRow0").hasCursor, false)
  }

  // ---- chips and search

  function test_the_chips_carry_the_counts() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runChiplive").text, "Live 1")
    compare(H.find(s.screen, "runChipparked").text, "Parked 1")
    compare(H.find(s.screen, "runChipall").text, "All")
    compare(H.find(s.screen, "runChipall").active, true, "All is active with no filter")
  }

  function test_each_chip_filters_its_rows_and_the_active_one_returns_to_all() {
    var s = make(sample()); if (!s) return
    tap(H.find(s.screen, "runChipattention"))
    compare(s.runs.runFilter, "attention")
    compare(H.find(s.screen, "runChipattention").active, true)
    compare(H.find(s.screen, "runRowId0").text, "…escl0002")
    compare(H.find(s.screen, "runRowId1").text, "…dead0003")
    compare(H.find(s.screen, "runRow2"), null)
    tap(H.find(s.screen, "runChiplive"))
    compare(H.find(s.screen, "runRowId0").text, "…live0001")
    compare(H.find(s.screen, "runRow1"), null)
    tap(H.find(s.screen, "runChipparked"))
    compare(H.find(s.screen, "runRowId0").text, "…park0004")
    compare(H.find(s.screen, "runRow1"), null)
    tap(H.find(s.screen, "runChipparked"))
    compare(s.runs.runFilter, "", "the active chip again means All")
    verify(H.find(s.screen, "runRow5"), "every run is back")
    tap(H.find(s.screen, "runChiplive"))
    tap(H.find(s.screen, "runChipall"))
    compare(s.runs.runFilter, "")
  }

  function test_the_chip_counts_ignore_the_search() {
    var s = make(sample()); if (!s) return
    s.nav.searchQuery = "gamma"
    compare(H.find(s.screen, "runChipattention").text, "Needs attention 2")
    compare(H.find(s.screen, "runRowId0").text, "…dead0003")
    compare(H.find(s.screen, "runRow1"), null)
  }

  function test_a_chip_and_the_search_compose_and_the_no_match_wordings_are_exact() {
    var s = make(sample()); if (!s) return
    s.runs.toggleRunFilter("live")
    s.nav.searchQuery = "beta"
    compare(H.find(s.screen, "runRow0"), null, "beta is not live")
    compare(H.find(s.screen, "runsMessage").text, "No runs match “beta”.")
    s.nav.searchQuery = ""
    s.runs.runs = [sample()[1]]
    compare(H.find(s.screen, "runsMessage").text, "No Live runs.")
    s.runs.toggleRunFilter("attention")
    s.runs.runs = [sample()[0]]
    compare(H.find(s.screen, "runsMessage").text, "No Needs attention runs.")
  }

  // ---- empty and missing

  function test_no_runs_says_so() {
    var s = make([]); if (!s) return
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "No runs for this project yet.")
    compare(msg.visible, true)
  }

  function test_missing_am_is_one_message_with_no_chips_or_rows() {
    var s = make(sample()); if (!s) return
    s.runs.stale = true
    s.runs.watchWarning = "CorruptJournal: bad"
    s.runs.lastError = "AmMissing: am is not installed."
    s.runs.amStatus = "missing"
    wait(20)
    var msg = H.find(s.screen, "runsMessage")
    compare(msg.text, "am is not installed or not on PATH")
    compare(msg.visible, true)
    compare(H.find(s.screen, "runChips").visible, false)
    compare(H.find(s.screen, "runRow0"), null, "no rows even before the store empties them")
    compare(H.find(s.screen, "runsFooter").visible, false)
    compare(H.find(s.screen, "runsSchemaBanner").visible, false)
    compare(H.find(s.screen, "runsStaleBanner").visible, false)
    compare(H.find(s.screen, "runsWarning").visible, false)
  }

  // ---- footer and banners

  function test_the_footer_says_whether_the_runs_are_watched() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    compare(footer.text, "am · schema 1 · watching")
    compare(footer.visible, true)
    s.runs.watching = false
    compare(footer.text, "am · schema 1 · not watching")
  }

  function test_an_error_shows_the_last_error_in_the_footer_and_keeps_the_rows() {
    var s = make(sample()); if (!s) return
    s.runs.amStatus = "error"
    s.runs.lastError = "AmBadOutput: am status did not print JSON (exit 3)."
    compare(H.find(s.screen, "runsFooter").text, "AmBadOutput: am status did not print JSON (exit 3).")
    verify(H.find(s.screen, "runRow0"), "the last good runs stay")
  }

  function test_a_schema_mismatch_replaces_the_footer_with_a_banner() {
    var s = make(sample()); if (!s) return
    s.runs.amStatus = "schema"
    s.runs.watchSchemaError = "SchemaMismatch: schema 2"
    s.runs.lastError = "something else"
    var banner = H.find(s.screen, "runsSchemaBanner")
    compare(banner.visible, true)
    compare(banner.text, "SchemaMismatch: schema 2")
    compare(H.find(s.screen, "runsFooter").visible, false)
    verify(H.find(s.screen, "runRow0"), "the rows stay beside the banner")
    s.runs.watchSchemaError = ""
    compare(banner.text, "something else", "falls back to lastError")
    s.runs.amStatus = "ok"
    compare(banner.visible, false)
  }

  function test_stale_data_shows_a_banner_and_dims_the_rows() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runsStaleBanner").visible, false)
    compare(H.find(s.screen, "runRow0").opacity, 1)
    s.runs.stale = true
    compare(H.find(s.screen, "runsStaleBanner").visible, true)
    compare(H.find(s.screen, "runsStaleBanner").text, "Run data is out of date")
    compare(H.find(s.screen, "runRow0").opacity, 0.5)
  }

  function test_a_watch_warning_shows_one_line() {
    var s = make(sample()); if (!s) return
    var line = H.find(s.screen, "runsWarning")
    compare(line.visible, false)
    s.runs.watchWarning = "CorruptJournal: journal line 12 is not JSON"
    compare(line.visible, true)
    compare(line.text, "CorruptJournal: journal line 12 is not JSON")
  }

  // ---- robustness and visibility

  function test_malformed_runs_render_without_throwing() {
    var s = make([{}, { id: 42, status: 7, lease: "x", rows: "y", tree: null, milestone_id: {} },
                  run("run-20261004-good0007", "done", null, {})]); if (!s) return
    compare(H.find(s.screen, "runRowId0").text, "…")
    compare(H.find(s.screen, "runRowGlyph0").visible, false, "an unknown state has no glyph")
    compare(H.find(s.screen, "runRowId1").text, "…")
    compare(H.find(s.screen, "runRowTitle1").text, "…")
    compare(H.find(s.screen, "runRowProgress1").visible, false)
    compare(H.find(s.screen, "runRowId2").text, "…good0007")
    compare(H.find(s.screen, "runChipall").text, "All")
  }

  function test_the_screen_is_hidden_outside_its_section() {
    var s = make(sample()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "run"
    compare(s.screen.visible, false)
    s.nav.viewMode = "runs"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, false)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/screens/tst_runs_screen.qml`
Expected: FAIL in every test with a message naming `RunsScreen.qml` (the component cannot be loaded: "No such file or directory").

- [ ] **Step 3: Create `ui/screens/RunsScreen.qml`**

```qml
import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// The Runs section: the selected project's am runs, one row each (state glyph,
// short id, title, done/total, current phase, age), with Needs attention /
// Live / Parked / All chips -- clicking the active chip means All again -- and
// a footer that says whether the runs are watched. It reads the run store and
// asks the navigator to open a run or move the cursor; it owns no state of its
// own. Ages are read against the clock once per snapshot: there is no timer.
Column {
  id: screen
  objectName: "runsView"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)

  // Re-read whenever the list changes, i.e. with every snapshot.
  readonly property real nowMs: screen.app.runs.filteredRuns ? Date.now() : 0
  readonly property bool amMissing: screen.app.runs.amStatus === "missing"
  readonly property var counts: Runs.runFilterCounts(screen.app.runs.runs)

  visible: screen.app.nav.viewMode === "runs" && !!screen.app.projects.selectedProject
  spacing: Style.space(6)

  // A chip's wording, also used by the "No <chip> runs." line.
  function chipLabel(id) {
    return id === "attention" ? "Needs attention" : id === "live" ? "Live" : id === "parked" ? "Parked" : "All"
  }

  // A dead or parked run's state, spelled out with its age folded in so the
  // age shows once; "" for every other state.
  function stateText(state, age) {
    if (state === "dead")
      return age === "" ? "dead - lease lost" : age === "just now" ? "dead - lease lost just now" : "dead - lease lost " + age + " ago"
    if (state === "parked") return age === "" ? "parked" : "parked " + age
    return ""
  }

  UI.ThemedText {
    objectName: "runsSchemaBanner"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.amStatus === "schema"
    text: screen.app.runs.watchSchemaError !== "" ? screen.app.runs.watchSchemaError : screen.app.runs.lastError
    color: screen.theme.urgent
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runsStaleBanner"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.stale
    text: "Run data is out of date"
    color: screen.theme.urgent
  }

  UI.ThemedText {
    objectName: "runsWarning"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.watchWarning !== ""
    text: screen.app.runs.watchWarning
    elide: Text.ElideRight
  }

  UI.FilterableList {
    width: parent.width
    theme: screen.theme

    chipsObjectName: "runChips"
    chipPrefix: "runChip"
    statusObjectName: "runsMessage"
    chips: ["attention", "live", "parked", "all"].map(function(id) {
      var chip = { id: id, label: screen.chipLabel(id), tint: screen.theme.dim }
      if (id !== "all") chip.count = screen.counts[id]
      return chip
    })
    activeChip: screen.app.runs.runFilter === "" ? "all" : screen.app.runs.runFilter
    onChipToggled: function(id) { screen.app.runs.toggleRunFilter(id) }

    error: screen.amMissing ? "am is not installed or not on PATH" : ""
    empty: screen.app.runs.filteredRuns.length === 0
    filtered: screen.app.nav.searchQuery !== "" || screen.app.runs.runFilter !== ""
    filteredText: screen.app.nav.searchQuery !== ""
      ? "No runs match “" + screen.app.nav.searchQuery + "”."
      : "No " + screen.chipLabel(screen.app.runs.runFilter) + " runs."
    emptyText: "No runs for this project yet."

    model: screen.app.runs.filteredRuns
    rowDelegate: Component { RunRow {} }
  }

  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.amStatus !== "schema"
    text: screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
      ? screen.app.runs.lastError
      : "am · schema 1 · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }

  component RunRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "runRow" + row.index

    // The run is read back out of the store's list by position, NOT taken from
    // `modelData`: a Repeater hands the delegate a converted copy whose nested
    // arrays are no longer JS arrays (Array.isArray is false), so the domain
    // helpers that read `tree.subtasks` and `rows` would see an empty run and
    // the progress, phase and escalation reason would silently vanish.
    readonly property var run: screen.app.runs.filteredRuns[row.index]

    readonly property string runState: Runs.runState(row.run)
    readonly property var runProgress: Runs.runProgress(row.run)
    readonly property string runAge: Runs.runAgeText(row.run, screen.nowMs)

    width: screen.width
    theme: screen.theme
    opacity: screen.app.runs.stale ? 0.5 : 1
    cursorIndex: screen.app.nav.cursorIndex
    scrollOnCursor: screen.app.nav.scrollOnCursor
    onHovered: function(index) { screen.navigator.hoverCursor(index) }
    onActivated: screen.navigator.openRun(row.run ? row.run.id : "")
    onRevealRequested: function(item) { screen.revealRequested(item) }

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        id: rowGlyph
        objectName: "runRowGlyph" + row.index
        theme: screen.theme
        visible: text !== ""
        text: RunGlyphs.glyphOf(row.runState)
        color: row.runState === "escalated" || row.runState === "dead" ? screen.theme.urgent : screen.theme.foreground
      }

      UI.ThemedText {
        id: rowId
        objectName: "runRowId" + row.index
        variant: "caption"
        theme: screen.theme
        text: Runs.shortId(row.run)
      }

      UI.ThemedText {
        objectName: "runRowTitle" + row.index
        theme: screen.theme
        width: Math.max(0, parent.width - (rowGlyph.visible ? rowGlyph.width + parent.spacing : 0)
          - rowId.width - parent.spacing)
        text: Runs.runTitle(row.run)
        elide: Text.ElideRight
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      UI.ThemedText {
        objectName: "runRowProgress" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: row.runProgress.total > 0 ? row.runProgress.done + "/" + row.runProgress.total : ""
      }

      UI.ThemedText {
        objectName: "runRowPhase" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: Runs.currentPhase(row.run)
      }

      UI.ThemedText {
        objectName: "runRowAge" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: row.runState === "dead" || row.runState === "parked" ? "" : row.runAge
      }

      UI.ThemedText {
        objectName: "runRowState" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: screen.stateText(row.runState, row.runAge)
        color: row.runState === "dead" ? screen.theme.urgent : screen.theme.dim
      }
    }

    UI.ThemedText {
      objectName: "runRowReason" + row.index
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: row.runState === "escalated"
      text: Runs.escalationReason(row.run)
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/screens/tst_runs_screen.qml`
Expected: `RunsScreen` reports `0 failed`; no TypeError / ReferenceError lines; pytest (`test_layers.py`: no `core/stores` import in the screen, no guarded snippet) green.

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml && git commit -m "feat(runs): RunsScreen with chips, footer, banners and empty states"
```

---

### Task 7: The Runs sidebar row

**Files:**
- Modify: `ui/components/Sidebar.qml:24-29` (comment) and after line 108 (new NavRow)
- Test: `tests/ui/tst_sidebar.qml`, `tests/ui/tst_sidebar_nav.qml`

**Interfaces:**
- Consumes: existing `sidebar.runsAttentionText`, `NavRow.countText`, `sidebar.hasProject`; Panel already routes `sectionChosen(name)` to `navi.showSection(name)` and Task 4 supports `"runs"`.
- Produces: NavRow `navRuns` (label `Runs`, section `runs`, icon `"\uf04b"`, Nerd Font "play") with child objectNames `navIconRuns`, `navLabelRuns`, `navCountRuns`.

- [ ] **Step 1: Confirm the glyph is in an installed Nerd Font**

Run: `fc-list ':charset=f04b' family | grep 'Nerd Font'`
Expected: at least one line naming a Nerd Font family. If there is none, pick another Font Awesome code point that prints a Nerd Font family here (for example `f085`, cogs) and use it in every step below instead of `f04b`.

- [ ] **Step 2: Write the failing sidebar tests**

In `tests/ui/tst_sidebar.qml`, insert before the final closing `}`:

```qml
  // ---- the Runs row (5.1)

  function test_the_runs_row_comes_after_issues_with_its_own_icon() {
    var sb = make()
    var row = find(sb, "navRuns")
    verify(row, "the Runs nav row")
    compare(String(find(sb, "navLabelRuns").text), "Runs")
    compare(String(find(sb, "navIconRuns").text), "\uf04b")
    verify(row.y > find(sb, "navIssues").y, "Runs comes after Issues, so it is Ctrl+6")
    var others = ["navIconBoard", "navIconGraph", "navIconDocuments", "navIconMemories", "navIconIssues"]
    for (var i = 0; i < others.length; i++)
      verify(String(find(sb, others[i]).text) !== "\uf04b", others[i] + " draws a different glyph")
    compare(find(sb, "navIconRuns").font.pixelSize, find(sb, "navIconBoard").font.pixelSize)
    click(row)
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "runs")
  }

  function test_the_runs_row_is_disabled_without_a_project() {
    var sb = make()
    sb.selectedProject = null
    compare(find(sb, "navRuns").enabled, false)
    click(find(sb, "navRuns"))
    compare(sectionSpy.count, 0)
  }

  function test_the_runs_row_shows_the_attention_count() {
    var sb = make()
    var count = find(sb, "navCountRuns")
    verify(count, "the Runs count slot")
    compare(count.visible, false, "no count at 0")
    sb.runsAttention = 2
    wait(20)
    compare(count.visible, true)
    compare(String(count.text), "‼2")
    sb.runsAttention = 0
    wait(20)
    compare(count.visible, false)
  }
```

In `tests/ui/tst_sidebar_nav.qml`, add the helper import under `import QtTest`:

```qml
import "../helpers/find.js" as H
```

and add `visible: true` to the TestCase header, right after `when: windowShown` (this file has none, so its window items are not visible and `mouseClick` on the row is silently dropped; nothing else in the file is affected):

```qml
  when: windowShown
  visible: true
```

and insert before the final closing `}`:

```qml
  function test_clicking_the_runs_row_opens_the_runs_section() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA])
    // The snapshot the project selection launched cannot run here.
    p.app.runs.snapshotRunner.cancel()
    wait(50)
    var row = H.find(p, "navRuns")
    verify(row, "the Runs nav row")
    mouseClick(row, row.width / 2, row.height / 2)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.section, "runs")
  }
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_sidebar`
Expected: FAIL in `Sidebar::test_the_runs_row_*` and `SidebarNav::test_clicking_the_runs_row_opens_the_runs_section` with "the Runs nav row" / "the Runs count slot" verify failures.

- [ ] **Step 4: Add the row to `ui/components/Sidebar.qml`**

Replace the comment:

```qml
  // How many runs need attention (escalated plus dead), computed by the
  // owner. Rendered as `‼N` by runsAttentionText; card 5.1's Runs row binds
  // `countText: sidebar.runsAttentionText`. No row shows it yet.
```

with:

```qml
  // How many runs need attention (escalated plus dead), computed by the
  // owner. Rendered as `‼N` by runsAttentionText, which the Runs row shows as
  // its count.
```

After the line:

```qml
    NavRow { objectName: "navIssues"; label: "Issues"; iconText: "\uf188"; section: "issues"; enabled: sidebar.hasProject }
```

add:

```qml
    // Appended after Issues, so Runs is Ctrl+6. Its glyph is the Nerd Font
    // play symbol (U+F04B); its count is the runs that need attention.
    NavRow { objectName: "navRuns"; label: "Runs"; iconText: "\uf04b"; section: "runs"; enabled: sidebar.hasProject; countText: sidebar.runsAttentionText }
```

- [ ] **Step 5: Run them to verify they pass**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_sidebar`
Expected: `Sidebar` and `SidebarNav` report `0 failed`; pytest's `tests/architecture/test_icon_glyphs.py` passes with the new glyph.

- [ ] **Step 6: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add ui/components/Sidebar.qml tests/ui/tst_sidebar.qml tests/ui/tst_sidebar_nav.qml && git commit -m "feat(sidebar): Runs row after Issues with the attention count"
```

---

### Task 8: Mount the screen in Panel, with search, focus and the sidebar count

**Files:**
- Modify: `ui/Panel.qml` (import after line 8, a `Connections` after line 88, `focusItem` line 164, `Sidebar` block line 282, `searchField` lines 397 and 400, mount after line 540)
- Test: `tests/ui/tst_runs_flow.qml` (new)

**Interfaces:**
- Consumes: `RunsScreen` (Task 6), `Runs.attention(runs)`, `appStores.runs.runFilterToggled` (Task 2), Navigator/Shortcuts Runs support (Tasks 4, 5), `navRuns` (Task 7).
- Produces: Panel shows `RunsScreen` in "runs", the search field (placeholder `Search runs…`) in "runs" only, keyboard focus on `keyCatcher` in "run", `sidebar.runsAttention` bound to the attention count, and a scroll-to-top on a chip change.

- [ ] **Step 1: Write the failing flow test**

Create `tests/ui/tst_runs_flow.qml`:

```qml
// tests/ui/tst_runs_flow.qml
// What the panel does around the run store: Ctrl+6, a chip, the search field,
// the cursor, opening a run and coming back, the focus in a run, and the
// sidebar's attention count. The filters are tested in tests/core/; the rows
// in tests/ui/screens/tst_runs_screen.qml.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "RunsFlow"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  function run(id, status, live, milestone) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] } }
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    // Selecting the project starts a `brd export` and a runs snapshot that
    // cannot run here: both are disarmed so their late replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [run("run-0000000000a1", "started", true, "alpha"),
                       run("run-0000000000b2", "escalated", null, "beta"),
                       run("run-0000000000c3", "started", false, "gamma"),
                       run("run-0000000000d4", "stopped", null, "delta")]
    return p
  }
  function labels(crumbs) { return crumbs.map(function(c) { return c.label }).join(" > ") }
  function ids(list) { return list.map(function(r) { return r.id }).join(",") }
  function key(k) { return { modifiers: Qt.NoModifier, key: k, accepted: false } }

  function test_ctrl_6_opens_the_runs_section_with_its_search_field() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.sectionTitle, "Runs")
    compare(labels(p.navigator.crumbs), "Runs")
    wait(50)
    var field = H.find(p, "searchField")
    compare(field.visible, true)
    compare(String(field.placeholderText), "Search runs…")
    compare(p.focusItem.objectName, "searchField")
    var view = H.find(p, "runsView")
    verify(view, "the Runs screen is mounted")
    compare(view.visible, true)
    compare(H.find(p, "refreshButton").visible, false, "refresh does not apply to runs")
  }

  function test_chip_search_cursor_enter_and_escape() {
    var p = make(); if (!p) return
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    H.find(p, "runChipattention").clicked()
    compare(p.app.runs.runFilter, "attention")
    compare(ids(p.navigator.currentList()), "run-0000000000b2,run-0000000000c3")
    compare(p.app.nav.cursorIndex, 0)
    var field = H.find(p, "searchField")
    field.text = "gamma"
    compare(ids(p.navigator.currentList()), "run-0000000000c3", "the search composes with the chip")
    field.text = ""
    compare(p.navigator.currentList().length, 2)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 1)
    p.shortcuts.handleSearchKey(key(Qt.Key_Up))
    compare(p.app.nav.cursorIndex, 0)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000c3")
    compare(labels(p.navigator.crumbs), "Runs > …000000c3")
    compare(p.focusItem.objectName, "keyCatcher", "Escape in a run must reach the key catcher")
    compare(H.find(p, "runsView").visible, false)
    compare(field.visible, false)
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.cursorIndex, 1, "back on the row it left")
    compare(p.app.runs.runFilter, "attention", "the chip is kept")
    compare(p.app.runs.selectedRunId, "")
  }

  function test_the_left_arrow_and_the_crumb_also_leave_a_run() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000a1")
    p.shortcuts.handleMove(-1, 0)
    compare(p.app.nav.viewMode, "runs")
    p.navigator.openRun("run-0000000000a1")
    p.navigator.activateCrumb(0)
    compare(p.app.nav.viewMode, "runs")
  }

  function test_the_run_view_renders_and_enter_there_does_nothing() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000b2")
    wait(50)
    compare(p.navigator.currentList().length, 0)
    p.shortcuts.handleActivate()
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
  }

  function test_the_sidebar_shows_how_many_runs_need_attention() {
    var p = make(); if (!p) return
    wait(50)
    var count = H.find(p, "navCountRuns")
    verify(count, "the Runs count")
    compare(String(count.text), "‼2", "one escalated and one dead run")
    p.app.runs.runs = []
    compare(String(count.text), "")
  }

  function test_an_empty_runs_list_ignores_enter() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.app.runs.runs = []
    wait(50)
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "runs")
    compare(H.find(p, "runsMessage").text, "No runs for this project yet.")
  }

  function test_a_project_switch_clears_the_runs_and_the_filter() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.app.runs.toggleRunFilter("live")
    p.app.projects.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.runs.runs.length, 0)
    compare(p.app.runs.runFilter, "")
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_runs_flow.qml`
Expected: FAIL. `searchField` is not visible in "runs" (placeholder `Search cards…`), `runsView` and `runChipattention` are not found (`TypeError: Cannot call method 'clicked' of null`), `focusItem` is `searchField` in "run", and `navCountRuns` reads `""`.

- [ ] **Step 3: Wire the screen into `ui/Panel.qml`**

After `import "../core/domain/milestones.js" as Milestones`, add:

```qml
import "../core/domain/runs.js" as Runs
```

After the `Connections` block whose `target: appStores.extras` (ends with `function onStatusToggled() { Qt.callLater(root.scrollToTop) }` and `}`), add:

```qml

  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
  }
```

In `focusItem`, replace:

```qml
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "issue" || appStores.nav.viewMode === "graph" || !appStores.projects.selectedProject) ? keyCatcher
```

with:

```qml
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "issue" || appStores.nav.viewMode === "run" || appStores.nav.viewMode === "graph" || !appStores.projects.selectedProject) ? keyCatcher
```

In the `Sidebar { id: sidebar … }` block, after `documentsEnabled: root.documentsEnabled`, add:

```qml
        runsAttention: Runs.attention(appStores.runs.runs).length
```

In `TextField { id: searchField … }`, replace:

```qml
          visible: !!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues")
          width: parent.width
          foreground: root.foreground
          placeholderText: appStores.nav.viewMode === "documents" ? "Search documents…" : appStores.nav.viewMode === "memories" ? "Search memories…" : appStores.nav.viewMode === "issues" ? "Search issues…" : "Search cards…"
```

with:

```qml
          visible: !!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues" || appStores.nav.viewMode === "runs")
          width: parent.width
          foreground: root.foreground
          placeholderText: appStores.nav.viewMode === "documents" ? "Search documents…" : appStores.nav.viewMode === "memories" ? "Search memories…" : appStores.nav.viewMode === "issues" ? "Search issues…" : appStores.nav.viewMode === "runs" ? "Search runs…" : "Search cards…"
```

After the `IssueDetailScreen { … }` block inside `Column { id: column … }`, add:

```qml

          // The "run" view's body is card 5.2's; until then the run mode
          // shows nothing here.
          RunsScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_runs_flow.qml`
Expected: `RunsFlow` reports `0 failed`; no TypeError / ReferenceError / "Unable to assign" lines.

- [ ] **Step 5: Run the other Panel-level suites that share the edited lines**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh tests/ui/tst_`
Expected: every `tests/ui/tst_*.qml` suite reports `0 failed` (in particular `PanelToolbar`, `SidebarNav`, `IssuesFlow`, `BoardFlow`).

- [ ] **Step 6: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add ui/Panel.qml tests/ui/tst_runs_flow.qml && git commit -m "feat(panel): mount RunsScreen with search, run focus and attention count"
```

---

### Task 9: Architecture doc sentences and full verification

**Files:**
- Modify: `docs/architecture.md:80-81` and `:116`

**Interfaces:**
- Consumes: everything above.
- Produces: the two updated sentences; a fully green `bash tests/run.sh`.

- [ ] **Step 1: Update the chord sentence**

In `docs/architecture.md`, replace:

```markdown
events to store calls; Ctrl+1..5 follow the sidebar's order: Board, Graph,
Documents, Memories, Issues), `theme/Theme.qml` (colours and fonts from the shell).
```

with:

```markdown
events to store calls; Ctrl+1..6 follow the sidebar's order: Board, Graph,
Documents, Memories, Issues, Runs), `theme/Theme.qml` (colours and fonts from the shell).
```

- [ ] **Step 2: Update the nav-row sentence**

Replace:

```markdown
`Sidebar`'s five nav rows (Board, Graph, Documents, Memories, Issues) each lead with an
```

with:

```markdown
`Sidebar`'s six nav rows (Board, Graph, Documents, Memories, Issues, Runs) each lead with an
```

Change nothing else in the file (the full write-up is card 5.4).

- [ ] **Step 3: Run the whole suite**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && bash tests/run.sh`
Expected: exit status 0; pytest all passed (architecture tier unchanged and green, including `test_icon_glyphs.py` and `test_layers.py`); every QML suite prints `Totals: … 0 failed`; no line containing `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function`.

- [ ] **Step 4: Check the forbidden colours and the no-timer rule**

Run: `cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git diff -U0 mon/task-4-3-runindicator-and-042def68 -- ui core | grep -E '^\+' | grep -nE '9b72cf|d9534f|Timer \{|NumberAnimation|SequentialAnimation' || echo clean`
Expected: `clean` (only added lines are checked; `-U0` keeps existing Timers in context lines out of the match).

- [ ] **Step 5: Commit**

```bash
cd /home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-1-runsscreen-sidebar-f9e44406 && git add docs/architecture.md && git commit -m "docs: Ctrl+1..6 and six sidebar rows include Runs"
```
