# 5.4 Docs: runs monitor in architecture and README (card 0fa83ffa)

Parent: story 8bb02694 "Runs screens and integration". Milestone spec: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md`. Blocked by 5.3 (77f168a5), which is done.

## Scope

Docs only. Edit `docs/architecture.md` and `README.md` so they describe the run monitor as it was **built** in 1.1 to 5.3, not as the milestone spec promised it. Change no QML, JS, Python, tests or other files. Add no control, dispatch or other feature (S2/S3 stay out).

Where the spec and the code disagree, the code wins. Before writing a sentence, read the file it is about: `core/domain/runs.js`, `core/stores/RunStore.qml`, `core/backend/runs/runs-snapshot.py`, `runs-watch.py`, `runs-logs.py`, `ui/screens/RunsScreen.qml`, `RunDetailScreen.qml`, `CardDetailScreen.qml`, `ui/components/RunMark.qml`, `runGlyphs.js`, `Sidebar.qml`, `ui/Panel.qml`, `ui/Shortcuts.qml`.

Known spec-vs-built differences the docs must follow:
- The Runs footer reads `am · schema 1 · watching`, or `not watching` (RunsScreen `runsFooter`). When `amStatus` is `error` and there is a `lastError`, it shows that error instead. It is hidden when am is missing or the schema banner shows. It shows **no am version and no data dir**. `runs-snapshot.py` emits `data_dir`, but nothing in the UI shows it. Do not claim a version or data dir in the footer. Say only what is true: am keeps its journals under its data dir, so the `XDG_DATA_HOME` that am sees matters.
- When am is missing, the Runs list shows the error `am is not installed or not on PATH`, and no run marks appear.
- `RunIndicator` is built but not mounted in Panel, so the docs must not describe toolbar counts or click-to-filter as live behaviour. The `am missing` error path therefore has no indicator counts to mention.

## Precondition: the base must have main's Archive docs

This worktree (branch from 5.3, old main f10da0e) predates main's commits #7 and #8. Its `README.md` and `docs/architecture.md` lack main's **Archive finished** text (README ~L125-133 and ~L175) and its **Show archived** / `showArchived` / `archiveCandidates` text (architecture ~L30-52, ~L102). The finished docs must contain both the run monitor text and all of main's archive text, unchanged. Diffed against current main, the result must show no removed archive lines. How the base is reconciled is for the plan stage.

## docs/architecture.md: what to add or correct

Keep the existing layering and section order (Layers, Stores, Other ui pieces, Shared components, Domain helpers / backend prose, How to add, Tests, Documented exceptions). Extend the entries that 5.3 already wrote. Do not write second copies of them.

1. **RunStore bullet** (~L69-77). Keep what is there and add:
   - `amStatus` values `ok | missing | schema | error`, with `lastError`.
   - `runFilter` / `toggleRunFilter`, `searchQuery`, and `filteredRuns` (`searchRuns(filterRuns(...))`).
   - `watchWarning` (the corrupt-journal chip) and `watchSchemaError` (the schema banner, which stays up during the 5 s poll).
   - The attempt-logs runner (`runs-logs.py` via `logsRunner`): `selectedAttempt`, `logsText` (a `logTail`), `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError`, `logsStatus`, and `openDefaultAttempt` / `refreshLogs`.
   - Logs are fetched on demand and are never live.
   - Run-open return mode: verified, it is NOT in RunStore. `NavigationStore.runReturnMode` (`"runs" | "entry"`) is set by `Navigator.openRun(id, from)`; a run opened from a card (`from === "entry"`) goes Back to that card via `restoreCardFromRun()`. Document it under the NavigationStore/Navigator entries, not RunStore.
2. **Domain helpers**: add a `runs.js` entry. It is pure JS. Describe its role in groups, not as a bare export dump:
   - normalizing: `normalizeRun`
   - state: `runState`, `cardRunState`, `glyphStateOf`
   - card mapping: `runsTouching`, `runTree`
   - rollups and attention: `rollup`, `attention`, `escalationReason`
   - filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`
   - display text: `shortId`, `runTitle`, `runProgress`, `currentPhase`, `ageText`, `runAgeText`, `snapshotAgeText`, `errorText`
   - logs: `logTail`, `defaultAttempt`, `attemptStatus`

   State the rules:
   - Run states: running = started with a live lease. dead = started with no live lease. parked = stopped. Also escalated, cancelled and done.
   - "Needs attention" = escalated or dead.
   - Card mapping uses `stories[].card_id`, `subtasks[].card_id` and `run.milestone_id`. The synthetic ids `integrate`, `bases` and `base-<story-id>` never match a card.
   - `cardRunState` returns none for the terminal brd statuses merged, canceled and archived.
   - Run state is never derived from brd status.
3. **`core/backend/runs/` paragraph** (~L146). Keep the `runs-snapshot.py` sentence and add `--repo-dir` (scope = the open project). Add:
   - `runs-watch.py`: long-lived `am watch --all --follow`. It checks that the hello line's schema is 1, drops backlog lines older than its start (an S4 workaround), prints debounced `{"changed": [...]}` lines, and ends with an `AmMissing` / `SchemaMismatch` / `CorruptJournal` / `HelperError` envelope.
   - `runs-logs.py`: a one-shot `am logs RUN CARD --phase P --attempt N` passthrough. It sends no `--repo-dir`, uses a 60 s timeout and prints exactly one JSON line.
   - All three helpers use only documented `am` commands and never read am's SQLite.
4. **Screens and components**:
   - Describe `ui/screens/RunsScreen.qml`: chips Needs attention / Live / Parked / All with counts, rows, the footer, and the missing-am error. Ages are recomputed per snapshot, with no timer.
   - Describe `ui/screens/RunDetailScreen.qml`: header, phases, and the output pane labelled `snapshot <age> ago`, plus `· last 200 lines` when it was cut.
   - Describe the Runs section in `CardDetailScreen.qml`.
   - Add `RunMark` to the shared components list: the Board/Graph wrapper around `RunBadge` that owns the dimming (a dimmed winner or stale data is drawn at half opacity and never pulses).
   - Add the use of `StatusPips` `ringedIds` by the screens.
   - Name `ui/components/runGlyphs.js` as the one glyph source.
5. **Sidebar sentence** (~L120): correct the stale "no current row sets it". Panel now feeds `runsAttention` from `Runs.attention(runs).length`, and the Runs row shows `‼N`. Panel does NOT mount `RunIndicator` (verified: `ui/Panel.qml` has no reference; only `MilestoneJobIndicator` is in the toolbar). Do not claim a toolbar indicator is wired. Describe `RunIndicator` only as the existing component (already documented at ~L113) and, if mentioned, say it is not yet mounted in the toolbar.
6. **Visual rule**: run state is a separate channel from brd status. It is shown as a glyph plus a ring, never by colour alone. The glyphs are running ⟳, parked ⏸, escalated ‼ (the `urgent` token), dead ✖, cancelled ⊘ and done ✔. Merged purple and canceled red are not used for run states.
7. **Refresh model**: no timers while idle. The watch, the debounce, the liveness re-read and the fallback poll run only while the panel is open.
8. **How to add**: change nothing unless the runs work added a rule. The existing helper/store/screen recipes already cover `core/backend/runs/`.
9. **Tests**: keep the `test_am_shapes.py` note and do not duplicate it.

## README.md: what to add or correct

Keep everything already there, including "Cards and issues are read-only" and all archive text.

- **Runs feature entry**:
  - The Runs screen, with filter chips Needs attention / Live / Parked / All and search.
  - The footer as built: `am · schema 1 · watching`.
  - Run detail, with its output pane: one attempt's `am logs` snapshot, labelled with its age and `last 200 lines` when cut. It is never live.
  - Run marks on Board, Graph and card detail. Merged, canceled and archived cards get no live mark.
  - Do NOT list a toolbar run indicator as a feature: `RunIndicator.qml` exists but is not mounted anywhere (checked `ui/Panel.qml`).
  - The sidebar `‼N` count of escalated plus dead runs.
  - The monitor is read-only: no pause, resume, cancel or start (that is S2/S3).
  - Scope: the open project only (`--repo-dir`).
- **Shortcuts**: add Ctrl+6 = Runs wherever the Ctrl+1..5 list appears.
- **"The plugin runs `brd` ..." paragraph** (~L210):
  - Add that it runs only `am runs`, `am status`, `am watch --all --follow` and `am logs`, and never reads am's SQLite.
  - Add that am finds its journals under its data dir, so the `XDG_DATA_HOME` it inherits matters.
- **Requires line** (~L245): `am` on `PATH` for the run monitor (optional; without it the plugin shows "am is not installed or not on PATH" and no badges), speaking journal schema 1 (otherwise a schema-mismatch banner and a 5 s poll).
- **Helper list**: add `core/backend/runs/*` (the three helpers).
- **Tests section** (~L293): add `tests/contract/test_am_shapes.py`, which pins am's JSON shapes and is skipped when `am` is absent.

## Error paths the docs must state

- am missing: the list shows an error and no marks.
- Schema not 1: a banner, and a 5 s poll in place of the watch.
- Corrupt journal: the `watchWarning` chip and the poll.
- No good snapshot for 30 s while open: `stale`, and marks are dimmed.
- A log fetch fails: `logsError` is shown and the last good text is kept. Verify this against `applyLogs` before writing it.

## Tests

No behaviour changes, so no new behaviour tests and no new files in `tests/core/**`, `tests/ui/**` or `tests/contract/**`.

- **Gate (existing, unchanged)**: `bash tests/run.sh` is fully green, including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`. The architecture tier must pass unchanged. Glyph literals in `.md` files are outside `test_icon_glyphs.py`'s `ui/` and `vendor/` scope.
- **Doc-drift guard**: not in scope (the findings don't call for one). If one is ever added, its only valid tier is `tests/architecture/`, never `tests/ui/` or `tests/core/`.
- **Manual review checks** (not automated):
  - Every symbol, path, string and shortcut the new text names exists in the code.
  - The text does not mention an am version or data dir in the footer.
  - The archive text is identical to main's.
  - No sentence says core/ imports visual types, or that screens/components import `core/stores`.

## Note on inputs

The exploration summary was capped at 8000 characters and cut off after its key-file list. Anything it said after that point is unknown and was not guessed at. The spec-vs-built footer difference above was found by reading `RunsScreen.qml` directly. The summary had asked for the spec's `am <version>` and data-dir footer.
