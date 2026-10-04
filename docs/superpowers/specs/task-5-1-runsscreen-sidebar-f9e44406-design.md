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
