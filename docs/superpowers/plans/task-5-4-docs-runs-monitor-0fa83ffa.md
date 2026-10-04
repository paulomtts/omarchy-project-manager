<!-- task-pipeline: validated -->
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

---

# 5.4 Docs: Runs Monitor in architecture.md and README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/architecture.md` and `README.md` describe the am run monitor as it was built in 1.1–5.3, while keeping every line of main's Archive finished / Show archived text.

**Architecture:** Docs-only. Five tasks: (1) port main's archive text onto this branch word for word, (2) extend the Stores / ui-pieces entries, (3) extend the shared-components and screens prose (RunMark, ringedIds, runGlyphs.js, the visual rule, the refresh model, the sidebar fix), (4) add the `runs.js` domain entry and the full `core/backend/runs/` paragraph, (5) add the README feature, shortcut, requirements and tests text. A final task runs the whole suite and the manual checks. No code, QML, Python or test file changes.

**Tech Stack:** Markdown. The gate is `bash tests/run.sh` (pytest, then qmltestrunner over every `tst_*.qml`).

**Spec:** `docs/superpowers/specs/task-5-4-docs-runs-monitor-0fa83ffa-design.md` (prepended above). Milestone spec: `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md`.

**Worktree / branch:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-4-docs-runs-monitor-0fa83ffa`, branch `mon/task-5-4-docs-runs-monitor-0fa83ffa`, cut from `mon/task-5-3-run-marks-on-board-77f168a5`. Run every command below from that worktree root. Every path in this plan is relative to it.

## Global Constraints

- Only `docs/architecture.md` and `README.md` change. No QML, JS, Python, test, manifest or other files.
- No control, dispatch or other new feature is described as existing: no pause, resume, cancel or start (S2/S3).
- Where the milestone spec and the code disagree, the code wins.
- Runs footer as built: `am · schema 1 · watching` (or `not watching`). Never mention an am version or a data dir in the footer.
- am missing: the Runs list shows `am is not installed or not on PATH`, and no run marks appear.
- `RunIndicator` exists but is not mounted. Never describe toolbar run counts or click-to-filter as live behaviour.
- Glyphs: running ⟳, parked ⏸, escalated ‼ (the `urgent` token), dead ✖, cancelled ⊘, done ✔. Glyph plus ring, never colour alone. Merged purple and canceled red are never used for a run state.
- All of main's archive text stays word for word: README "Archive finished" bullet and "besides New milestone and Archive finished.", and architecture's `archiveCandidates` block, `showArchived` block and `ArchiveFinishedDialog` entry.
- No sentence may say `core/` imports visual types, or that `ui/screens/**` / `ui/components/**` import `core/stores`.
- `tests/architecture/` must pass unchanged. No new test files anywhere (spec "Tests"). Each RED step below is a one-off shell check against the doc, not a committed test.
- New doc prose goes in as unwrapped lines (the docs already mix wrapped and long lines, for example the `PhaseTimeline` entry).

## Base reconciliation (decided here, as the spec asked)

Main's archive text is carried onto this branch **as text** (Task 1), copied word for word from `git show main:README.md` / `git show main:docs/architecture.md`. Merging `main` into this branch is not done: it would bring #7/#8's code (BoardStore archive flow, `archive-milestones.py`, `ArchiveFinishedDialog.qml`, GraphStore `showArchived`) onto a docs-only card. When the milestone's Integrate phase merges into main, both sides carry identical archive lines, so git takes them without a conflict.

## Spec-vs-code corrections this plan applies

- Spec item 2 says "`cardRunState` returns none for the terminal brd statuses merged, canceled and archived". **The code disagrees.** `core/domain/runs.js` `cardRunState(runs, cardId)` reads no brd status. Its `state` is `running | dead | parked | escalated | none` (cancelled and done also become `none`). The closed-card rule lives in the screens: `BoardScreen.hidesRunMarks(card)` and `GraphScreen.hidesRunMarks(status)` skip any card where `Board.isClosedStatus(status)` is true (merged, canceled, archived), and also every card while `amStatus === "missing"`. The docs say exactly that (Task 4 Step 2, Task 3 Step 2). `CardDetailScreen` still lists a closed card's runs as history.
- `runTitle(run)` returns the run's `milestone_id` (a card id, not a card title), else `shortId`. The README says "its milestone id".
- `runs-snapshot.py` does not check the journal schema. Only `runs-watch.py` does, so the schema banner appears once the watch has ended with `SchemaMismatch`.

## Review Focus

1. **A reader takes the "terminal statuses" claim literally and expects `cardRunState` to filter.** They should read that the screens hide the marks through `Board.isClosedStatus`. Pinned by Task 4 Step 1/3: the `isClosedStatus` check, plus a check that `returns none for the terminal` does not appear.
2. **Main's archive lines are lost when this branch is integrated.** Expected: every main line mentioning "rchiv" is still present, word for word. Pinned by Task 1 Steps 1/3 and re-run in Task 6 Step 4.
3. **A reader looks for a toolbar run indicator that does not exist.** Expected: the docs call `RunIndicator` "not yet mounted" and the README lists no toolbar run indicator. Pinned by Task 3 Step 3 (the `not yet mounted` check) and Task 5 Step 3 (no `toolbar` claim in the Runs bullet).
4. **A user expects an am version or data dir in the Runs footer.** Expected: the footer is documented only as `am · schema 1 · watching` / `not watching`. Pinned by Task 6 Step 3 (the `am <version>` / `data_dir` checks).
5. **Glyph literals added to the docs could trip `test_icon_glyphs.py`.** Expected: the guard scans only `ui/` and `vendor/`, so `.md` text is outside it. Pinned by each task's `python3 -m pytest tests/architecture -q` step and the full run in Task 6 Step 1.

---

### Task 1: Carry main's archive text onto this branch

**Files:**
- Modify: `docs/architecture.md` (BoardStore bullet ~L29, GraphStore bullet ~L39-40, shared-components list ~L96-97)
- Modify: `README.md` (before the "Card detail" bullet ~L125, Documents bullet ~L165)

**Interfaces:**
- Consumes: `main` branch (`git show main:README.md`, `git show main:docs/architecture.md`).
- Produces: both docs containing main's archive text word for word. Tasks 2–5 edit around it and must not change it.

- [ ] **Step 1: Run the failing check (RED)**

```bash
for f in README.md docs/architecture.md; do
  git show "main:$f" | grep -i 'archiv' | while IFS= read -r line; do
    grep -qxF -- "$line" "$f" || echo "MISSING in $f: $line"
  done
done
```

Expected: several `MISSING in README.md: ...` and `MISSING in docs/architecture.md: ...` lines, for example `MISSING in README.md: - **Archive finished** - in the Board list, **Archive finished (N)** appears`.

- [ ] **Step 2: Insert the BoardStore archive block in `docs/architecture.md`**

Replace this exact text:

```markdown
`fetchBoard()` itself -- Refresh, a project switch -- stays immediate).
- `GraphStore.qml` the two graph models from the board (card roots and issue
```

with:

```markdown
`fetchBoard()` itself -- Refresh, a project switch -- stays immediate).
  Also the Archive finished flow: `archiveCandidates` (`Board.archivable`: a
  milestone with at least one descendant, all descendants done/merged/canceled/
  archived, idle at least 2 days; `nowMs` pins the clock in tests),
  `archiveOpen` / `archiveBusy` / `archiveError`, and `openArchive()` /
  `archiveAll()` / `cancelArchive()`. The candidates are recomputed when the
  dialog opens and again at confirm time, and only those ids go to
  `boards/archive-milestones.py` through an `archiveRunner` `HelperRunner`
  (guarded by the project), which runs `brd update <id> --status archived` on
  the milestone card only and reports per id; one failure keeps the dialog open
  and leaves the others archived. The board refetches through its DB watch.
- `GraphStore.qml` the two graph models from the board (card roots and issue
```

- [ ] **Step 3: Insert the GraphStore `showArchived` block in `docs/architecture.md`**

Replace this exact text:

```markdown
  project switch (the cursor still clears with the project). Plus the graph
  cursor and its movement.
```

with:

```markdown
  project switch (the cursor still clears with the project). `showArchived`
  (off by default, set by the toolbar's Show archived chip through
  `setShowArchived`) decides whether both models are built from every card root
  or from `Graph.withoutArchived(cardRoots)`, which drops an archived card with
  its whole subtree; a selection that disappears moves to the first node. Plus
  the graph cursor and its movement.
```

- [ ] **Step 4: Insert the `ArchiveFinishedDialog` entry in `docs/architecture.md`**

Replace this exact text:

```markdown
`TagPicker`, `NewMemoryDialog`, `NewMilestoneDialog` (the from-spec modal),
`MilestoneJobIndicator` (the toolbar strip while a milestone job runs, and its
```

with:

```markdown
`TagPicker`, `NewMemoryDialog`, `NewMilestoneDialog` (the from-spec modal),
`ArchiveFinishedDialog` (the confirm list behind the Board toolbar's
**Archive finished (N)** button), `MilestoneJobIndicator` (the toolbar strip while a milestone job runs, and its
```

- [ ] **Step 5: Insert the README "Archive finished" bullet**

In `README.md`, replace this exact text:

```markdown
    is reviewed by the plugin - it writes cards to `brd` on your behalf.
- **Card detail** - kind and status badges (Milestone / Story / Subtask by
```

with:

```markdown
    is reviewed by the plugin - it writes cards to `brd` on your behalf.
- **Archive finished** - in the Board list, **Archive finished (N)** appears
  when N milestones are done with: not archived yet, at least one card under
  them, every card at any depth done, merged, canceled or archived, and nothing
  in the milestone or its cards updated in the last 2 days. Click it to review
  the list (title, idle days, card count); **Archive all** then runs
  `brd update <id> --status archived` on each milestone card only - its stories
  and subtasks are left alone. Cancel, Escape or a click on the backdrop writes
  nothing. A milestone that fails is named in the dialog, which stays open; the
  others stay archived. Like New milestone, this is a write the plugin does on
  your behalf, and only after that click.
- **Card detail** - kind and status badges (Milestone / Story / Subtask by
```

- [ ] **Step 6: Update the README Documents sentence**

In `README.md`, replace this exact text:

```markdown
  panel that is not a pure read of brd besides New milestone.
```

with:

```markdown
  panel that is not a pure read of brd besides New milestone and Archive finished.
```

- [ ] **Step 7: Re-run the check (GREEN)**

Run the Step 1 loop again.
Expected: no output.

- [ ] **Step 8: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass (they ignore `.md`, but this confirms nothing else moved).

- [ ] **Step 9: Commit**

```bash
git add README.md docs/architecture.md
git commit -m "docs: carry main's Archive finished and Show archived text onto the runs branch"
```

---

### Task 2: Stores and ui pieces (RunStore, NavigationStore, Navigator)

**Files:**
- Modify: `docs/architecture.md` (NavigationStore bullet ~L26, RunStore bullet ~L79-87 after Task 1, "Other `ui/` pieces" ~L89)

**Interfaces:**
- Consumes: the facts in `core/stores/RunStore.qml` (`amStatus`, `lastError`, `runFilter`, `toggleRunFilter`, `runFilterToggled`, `searchQuery`, `filteredRuns`, `watchWarning`, `watchSchemaError`, `logsRunner`, `selectedAttempt`, `logsText`, `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError`, `logsStatus`, `selectAttempt`, `openDefaultAttempt`, `refreshLogs`, `applyLogs`), `core/stores/NavigationStore.qml` (`runReturnMode`), and `ui/Navigator.qml` (`openRun(id, from)`, `restoreCardFromRun()`, `restoreRunsList()`).
- Produces: the doc names Tasks 3–5 refer back to (`filteredRuns`, `watchWarning`, `watchSchemaError`, `logsError`, `runReturnMode`).

- [ ] **Step 1: Run the failing check (RED)**

```bash
for s in logsRunner watchSchemaError watchWarning runFilterToggled runReturnMode restoreCardFromRun refreshLogs openDefaultAttempt logsError; do
  grep -q -- "$s" docs/architecture.md || echo "ABSENT $s"
done
```

Expected: an `ABSENT` line for each of the nine names.

- [ ] **Step 2: Extend the NavigationStore bullet**

Replace this exact text:

```markdown
- `NavigationStore.qml` view mode, section, push/pop return positions, cursor, search, dropdown.
```

with:

```markdown
- `NavigationStore.qml` view mode, section, push/pop return positions, cursor, search, dropdown; `runReturnMode` (`"runs"` | `"entry"`) says where Back from an open run goes.
```

- [ ] **Step 3: Extend the RunStore bullet**

Replace this exact text:

```markdown
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`).
```

with:

```markdown
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`).
  `amStatus` is `ok`, `missing` (an `AmMissing` snapshot: `runs` is emptied, so no run marks show), `schema` (the watch ended with `SchemaMismatch`: `watchSchemaError` holds the banner text, which stays up through the polling snapshots) or `error` (any other failed snapshot: the last good `runs` stay), with `lastError` saying why. A watch that ends with `CorruptJournal` sets `watchWarning` (the Runs screen's warning line) and starts the same 5 s poll.
  The Runs list is `filteredRuns`, `Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery)`: `runFilter` is `""` (All) or `attention` / `live` / `parked`, set by `toggleRunFilter(id)` (the All chip, or the active chip again, means All), which emits `runFilterToggled()` so the cursor and the scroll go home; `App` binds `searchQuery` to the navigation store's, and a project switch resets the chip.
  Run detail's output pane is a second `HelperRunner`, `logsRunner` (`runs-logs.py`, guarded by the project like the snapshot): `selectedAttempt` (`{ card_id, phase, attempt }` or null), `logsText` (`Runs.logTail` of the last good reply, at most 200 lines), `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError` and `logsStatus` (the attempt's status when its fetch was launched). Logs are fetched on demand only -- `selectAttempt(...)`, `openDefaultAttempt()` when a run is selected, `refreshLogs()` (the Refresh button), and after a snapshot that moved the selected attempt's status -- never on a timer and never as a live tail. A failed fetch sets `logsError` and keeps the last good text; another attempt starts from an empty pane.
```

- [ ] **Step 4: Extend the Navigator entry**

Replace this exact text:

```markdown
Other `ui/` pieces: `Navigator.qml` (screen switching), `Shortcuts.qml` (key
```

with:

```markdown
Other `ui/` pieces: `Navigator.qml` (screen switching; `openRun(id, from)` opens Run detail and records where Back goes in `runReturnMode`: from a card's RUNS row (`from` `"entry"`) the card stays open behind it and Back returns to it through `restoreCardFromRun()`, from the Runs list Back restores the list through `restoreRunsList()`), `Shortcuts.qml` (key
```

- [ ] **Step 5: Re-run the check (GREEN)**

Run the Step 1 loop again.
Expected: no output.

- [ ] **Step 6: Check the edited names against the code**

```bash
for s in logsRunner watchSchemaError watchWarning runFilterToggled toggleRunFilter filteredRuns selectedAttempt logsText logsTruncated logsFetchedMs logsLoading logsError logsStatus selectAttempt openDefaultAttempt refreshLogs; do
  grep -q -- "$s" core/stores/RunStore.qml || echo "NOT IN RunStore: $s"
done
grep -q runReturnMode core/stores/NavigationStore.qml || echo "NOT IN NavigationStore: runReturnMode"
for s in "function openRun(id, from)" "function restoreCardFromRun()" "function restoreRunsList()"; do
  grep -qF -- "$s" ui/Navigator.qml || echo "NOT IN Navigator: $s"
done
```

Expected: no output.

- [ ] **Step 7: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): RunStore status, filter, watch and logs fields; run return mode"
```

---

### Task 3: Shared components, run screens, visual rule, refresh model, sidebar fix

**Files:**
- Modify: `docs/architecture.md` (shared-components list: `StatusPips`, `RunIndicator`, a new `RunMark` entry; the Sidebar sentence; new paragraphs after the `DocumentsToolbar` sentence)

**Interfaces:**
- Consumes: `ui/components/RunMark.qml`, `ui/components/StatusPips.qml` (`ringedIds`), `ui/components/runGlyphs.js` (`GLYPHS`, `glyphOf`, `countOf`, `countsText`), `ui/components/Sidebar.qml` (`runsAttention`, `runsAttentionText`), `ui/Panel.qml` (`runsAttention: Runs.attention(appStores.runs.runs).length`, no `RunIndicator`), `ui/screens/RunsScreen.qml`, `ui/screens/RunDetailScreen.qml`, `ui/screens/CardDetailScreen.qml`, `ui/screens/BoardScreen.qml`, `ui/screens/GraphScreen.qml`. Uses the Task 2 names `filteredRuns`, `watchWarning`, `lastError`, `logsText`, `logsError`.
- Produces: nothing later tasks need.

- [ ] **Step 1: Run the failing check (RED)**

```bash
grep -q 'RunMark' docs/architecture.md || echo "ABSENT RunMark"
grep -q 'ringedIds' docs/architecture.md || echo "ABSENT ringedIds"
grep -q 'RunsScreen.qml' docs/architecture.md || echo "ABSENT RunsScreen"
grep -q 'RunDetailScreen.qml' docs/architecture.md || echo "ABSENT RunDetailScreen"
grep -q 'not yet mounted' docs/architecture.md || echo "ABSENT not-yet-mounted"
grep -q 'no timers while idle' docs/architecture.md || echo "ABSENT refresh model"
grep -q 'no current row sets it' docs/architecture.md && echo "STALE sidebar sentence present"
```

Expected: six `ABSENT ...` lines and `STALE sidebar sentence present`.

- [ ] **Step 2: Add `ringedIds` to the `StatusPips` entry**

Replace this exact text:

```markdown
visible AND holds an in-progress pip, so an idle graph animates nothing),
`Pulse` (that one fade, shared:
```

with:

```markdown
visible AND holds an in-progress pip, so an idle graph animates nothing; `ringedIds` rings, with the pip's own border, the subtasks an am run is working on now -- `GraphScreen` picks each pip whose winning run is running and whose own am row is in the running bucket, and `GraphView` hands the list down),
`Pulse` (that one fade, shared:
```

- [ ] **Step 3: Mark `RunIndicator` as not mounted and add `RunMark`**

Replace this exact text:

```markdown
`RunIndicator` (the toolbar's run strip beside `MilestoneJobIndicator`:
```

with:

```markdown
`RunIndicator` (a toolbar run strip built to sit beside `MilestoneJobIndicator`, not yet mounted -- `Panel`'s toolbar carries only `MilestoneJobIndicator`:
```

Then replace this exact text:

```markdown
`all` being emitted by no segment),
`Sidebar`, and the views
```

with:

```markdown
`all` being emitted by no segment),
`RunMark` (one card's run mark on the Board and the Graph: a `RunBadge` inside the wrapper that owns the dimming -- a dimmed winner (a finished run speaking for the card) or stale run data is drawn at half opacity and never pulses; the owner hands it `cardRunState` and `rollup`, or null for no mark, and never brd status),
`Sidebar`, and the views
```

- [ ] **Step 4: Correct the Sidebar sentence**

Replace this exact text:

```markdown
as `navCount<Section>`; no current row sets it, and the Runs row (story 5.x) binds `countText: sidebar.runsAttentionText`.
```

with:

```markdown
as `navCount<Section>`; the Runs row binds `countText: sidebar.runsAttentionText`, and `Panel` feeds `runsAttention` from `Runs.attention(runs).length`, so the Runs row reads `‼N` while N runs are escalated or dead.
```

- [ ] **Step 5: Add the run screens, visual rule and refresh model paragraphs**

Replace this exact text:

```markdown
open document - so only the document body scrolls.
Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
```

with:

```markdown
open document - so only the document body scrolls.

The run screens read `app.runs` and never import `core/stores`. `ui/screens/RunsScreen.qml` (Ctrl+6) lists `filteredRuns`, one row each (state glyph, short id, title, done/total, current phase, age; a dead run's age is since its last heartbeat, and an escalated run adds `escalationReason`), under the Needs attention / Live / Parked / All chips with their `runFilterCounts`. Above the list it shows the schema banner, `Run data is out of date` while `stale`, and the `watchWarning` line. Below it the footer reads `am · schema 1 · watching` (or `not watching`), shows `lastError` instead when `amStatus` is `error`, and is hidden when am is missing or the schema banner shows. With am missing the list shows `am is not installed or not on PATH`. `ui/screens/RunDetailScreen.qml` (view mode `run`) shows the header (state, milestone, branch prefix, base, lease), the `runTree` story > subtask > phase > attempt tree plus the Integrate / Bases / Base rows (cards brd has closed are dimmed, never hidden), and the output pane: one attempt's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a Refresh button and `logsError` in `urgent`. `CardDetailScreen` adds a RUNS section: every run `runsTouching` the card, newest first, with glyph, short id, title, phase and age, dimmed while stale. A click opens Run detail with `from` `"entry"`; a merged or canceled card still lists its runs, and nothing is listed while am is missing. `BoardScreen` and `GraphScreen` draw a `RunMark` per card (plus `RunRollupBar` under a Board card's title) from `cardRunState` / `rollup`, except on cards `Board.isClosedStatus` reports closed (merged, canceled, archived) and while am is missing -- a visibility rule in the screens, never a run state. Every age on these screens is read against the clock once per snapshot (or logs reply): there is no timer.

Run state is a separate channel from brd status: a glyph plus a ring (`RunBadge`'s `Badge`, or a `StatusPips` ring), never colour alone. `ui/components/runGlyphs.js` is the one glyph source -- running ⟳, parked ⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔ -- read by `RunBadge`, `RunRollupBar`, `PhaseTimeline`, `RunIndicator`, `RunMark`, `Sidebar` and the run screens. Escalated is drawn in the `urgent` token; merged purple and canceled red (`Board.statusColor`) are never used for a run state.

Refresh model: no timers while idle. `RunStore`'s watch, its debounce, the liveness re-read (only while a run is running) and the fallback poll run only while the panel is open (`active`); closing it stops every process and timer. Logs are fetched on demand, and `Pulse` animates a run badge only while it is running, visible and `active`.

Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
```

- [ ] **Step 6: Re-run the check (GREEN)**

Run the Step 1 commands again.
Expected: no output.

- [ ] **Step 7: Check the named strings against the code**

```bash
grep -qF 'am is not installed or not on PATH' ui/screens/RunsScreen.qml || echo "NO missing-am text"
grep -qF '"am · schema 1 · "' ui/screens/RunsScreen.qml || echo "NO footer text"
grep -qF 'Run data is out of date' ui/screens/RunsScreen.qml || echo "NO stale text"
grep -qF '"snapshot " + age + " ago"' ui/screens/RunDetailScreen.qml || echo "NO snapshot label"
grep -qF '" · last 200 lines"' ui/screens/RunDetailScreen.qml || echo "NO last-200 label"
grep -q 'RunIndicator' ui/Panel.qml && echo "RunIndicator IS mounted: fix the doc"
grep -qF 'runsAttention: Runs.attention(appStores.runs.runs).length' ui/Panel.qml || echo "NO runsAttention feed"
grep -q 'property var ringedIds' ui/components/StatusPips.qml || echo "NO ringedIds"
grep -q 'ringedIds: view.runRinged' ui/components/GraphView.qml || echo "NO GraphView ringedIds"
for g in running parked escalated dead cancelled done; do grep -q "^  $g:" ui/components/runGlyphs.js || echo "NO glyph $g"; done
grep -q 'opacity: mark.dimmed ? 0.5 : 1' ui/components/RunMark.qml || echo "NO RunMark dimming"
```

Expected: no output.

- [ ] **Step 8: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass (`test_icon_glyphs.py` scans only `ui/` and `vendor/`, so the glyphs in the `.md` are outside its scope).

- [ ] **Step 9: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): run screens, RunMark, ringedIds, runGlyphs.js, visual rule and refresh model"
```

---

### Task 4: `runs.js` domain entry and the `core/backend/runs/` paragraph

**Files:**
- Modify: `docs/architecture.md` (Domain helpers sentence ~"dropped unread), and `documents.js`'s"; the `core/backend/runs/` line)

**Interfaces:**
- Consumes: every top-level function in `core/domain/runs.js`, `Board.isClosedStatus` in `core/domain/board.js`, and the three helpers in `core/backend/runs/`.
- Produces: nothing later tasks need.

- [ ] **Step 1: Run the failing check (RED)**

```bash
for s in normalizeRun glyphStateOf snapshotAgeText defaultAttempt attemptStatus 'am watch --all --follow' 'S4 workaround' 'a 60 s timeout'; do
  grep -qF -- "$s" docs/architecture.md || echo "ABSENT $s"
done
```

Expected: exactly eight `ABSENT ...` lines, one per string. (`cardRunState`, `runsTouching`, `runFilterCounts`, `runTree` and `isClosedStatus` are left out on purpose: Task 3's screens paragraph already names them. `runs-watch.py` is in the 5.3 RunStore bullet, and Task 2 added `runs-logs.py`.)

- [ ] **Step 2: Add the `runs.js` entry**

Replace this exact text:

```markdown
dropped unread), and `documents.js`'s `mergeRegistered` / `brdStateLabel` for
brd's registrations;
```

with:

```markdown
dropped unread), `documents.js`'s `mergeRegistered` / `brdStateLabel` for
brd's registrations, and `runs.js`, the am run model: pure JS, never throws, and every input comes from `am`, never from a brd card. Normalizing: `normalizeRun` (an `am runs` row plus its `am status` data). State: `runState` (running = `started` with a live lease, dead = `started` without one, parked = `stopped`, plus escalated, cancelled and done; anything else is `unknown`), `cardRunState` (the newest non-terminal run touching a card speaks for it, else the newest touching run, dimmed; its `state` is running / dead / parked / escalated / none) and `glyphStateOf` (an am story, subtask, phase, attempt or row status as a `runGlyphs.js` key). Card mapping: `runsTouching` and `runTree`, through `run.milestone_id`, `stories[].card_id` and `subtasks[].card_id`, never through rows alone; the synthetic ids `integrate`, `bases` and `base-<story-id>` never match a card (Run detail shows them as rows of their own). Rollups and attention: `rollup` (counts from the winning run's am rows), `attention` (escalated or dead: "Needs attention") and `escalationReason`. Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`. Display text: `shortId`, `runTitle`, `runProgress`, `currentPhase`, `ageText`, `runAgeText`, `snapshotAgeText`, `errorText`. Logs: `logTail`, `defaultAttempt`, `attemptStatus`. Run state is never derived from brd status: `cardRunState` reads no brd status at all, and it is the screens that skip the cards `Board.isClosedStatus` reports closed (merged, canceled, archived);
```

- [ ] **Step 3: Replace the `core/backend/runs/` paragraph**

Replace this exact text:

```markdown
`core/backend/runs/` is the run-monitor backend: `runs-snapshot.py` runs `am runs`, then `am status` for every non-terminal run and the latest 10 terminal ones, and prints one JSON line (`{ok, runs, data_dir}` or an error).
```

with:

```markdown
`core/backend/runs/` is the run-monitor backend, scoped to the open project. `runs-snapshot.py <project_root>` runs `am runs --repo-dir R`, then `am status <id> --repo-dir R` for every non-terminal run and the latest 10 terminal ones, and prints one JSON line (`{ok, runs, data_dir}` or an error; nothing in the UI shows `data_dir`). `runs-watch.py <project_root> [run_id ...]` is long-lived: it runs `am watch --all --follow`, checks that the hello line's schema is 1, drops journal lines written before it started (an S4 workaround until `am watch --from-now` exists), keeps the watched runs plus any run whose `run_upsert` names this project root, prints at most one debounced `{"changed": [...]}` line per 250 ms, and ends with an `AmMissing`, `SchemaMismatch`, `CorruptJournal` or `HelperError` envelope (exit 0 when it was stopped). `RunStore` runs it as a plain `Process`, not through `HelperRunner`. `runs-logs.py RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N` passthrough: no `--repo-dir` (am resolves the run by id), a 60 s timeout, exactly one JSON line. All three use only documented `am` commands, as argv lists, and never read am's SQLite database or its on-disk layout; am finds its journals under its own data dir, so the `XDG_DATA_HOME` it inherits matters.
```

- [ ] **Step 4: Re-run the check (GREEN)**

Run the Step 1 loop again.
Expected: no output.

- [ ] **Step 5: Check every named export and helper fact against the code**

```bash
for f in normalizeRun runState cardRunState glyphStateOf runsTouching runTree rollup attention escalationReason runFilterCounts filterRuns searchRuns shortId runTitle runProgress currentPhase ageText runAgeText snapshotAgeText errorText logTail defaultAttempt attemptStatus; do
  grep -q "^function $f(" core/domain/runs.js || echo "NOT EXPORTED: $f"
done
grep -q 'function isClosedStatus' core/domain/board.js || echo "NO isClosedStatus"
grep -q '"watch", "--all", "--follow"' core/backend/runs/runs-watch.py || echo "NO am watch argv"
grep -q 'def is_backlog' core/backend/runs/runs-watch.py || echo "NO backlog drop"
grep -q 'WINDOW = 0.25' core/backend/runs/runs-watch.py || echo "NO 250 ms window"
grep -q 'AM_TIMEOUT = 60' core/backend/runs/runs-logs.py || echo "NO 60 s timeout"
grep -q 'No --repo-dir is sent' core/backend/runs/runs-logs.py || echo "runs-logs DOES send --repo-dir: fix the doc"
grep -q 'TERMINAL_LIMIT = 10' core/backend/runs/runs-snapshot.py || echo "NO 10 terminal cap"
grep -n 'returns none for the terminal' docs/architecture.md README.md && echo "SPEC-ERROR SENTENCE PRESENT"
```

Expected: no output.

- [ ] **Step 6: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): runs.js domain model and the runs-watch / runs-logs helpers"
```

---

### Task 5: README: Runs feature, Ctrl+6, am requirements, helpers, tests

**Files:**
- Modify: `README.md` (intro ~L8, Sections ~L32-33, Card detail ~L141-142 after Task 1, new Runs bullet after Issues, Breadcrumbs, Keyboard navigation, "The plugin runs `brd`" paragraph, Requires line, Tests block and paragraph)

**Interfaces:**
- Consumes: the same code facts Tasks 2–4 checked, and `tests/contract/test_am_shapes.py` (`pytest.mark.skipif(shutil.which("am") is None, ...)`, a throwaway `XDG_DATA_HOME`).
- Produces: nothing later tasks need.

- [ ] **Step 1: Run the failing check (RED)**

```bash
for s in 'Ctrl+6' '**Runs**' 'am watch --all --follow' 'am is not installed or not on PATH' 'test_am_shapes.py' 'am · schema 1 · watching' 'core/backend/runs/' 'XDG_DATA_HOME` the shell' 'snapshot <age> ago'; do
  grep -qF -- "$s" README.md || echo "ABSENT $s"
done
```

Expected: an `ABSENT` line for each of the nine strings.

- [ ] **Step 2: Intro and Sections**

Replace this exact text:

```markdown
delete, and its brd **Issues**. Cards and issues are read-only; the plugin's
```

with:

```markdown
delete, its brd **Issues**, and the **Runs** the `am` orchestrator makes on it (watched, never controlled). Cards and issues are read-only; the plugin's
```

Then replace this exact text:

```markdown
  (**Ctrl+3**), **Memories** (**Ctrl+4**) and **Issues** (**Ctrl+5**), also
```

with:

```markdown
  (**Ctrl+3**), **Memories** (**Ctrl+4**), **Issues** (**Ctrl+5**) and **Runs** (**Ctrl+6**), also
```

- [ ] **Step 3: Add the Runs feature bullet after Issues**

Replace this exact text:

```markdown
  panel never opens, closes or comments on an issue.
- **Documents** - lists every `.md` file under `docs/` (at most 500; a note says
```

with:

```markdown
  panel never opens, closes or comments on an issue.
- **Runs** (Ctrl+6) - the runs the `am` orchestrator has made on the open project only (`am runs --repo-dir <project>`), watched, never controlled: the plugin has no pause, resume, cancel or start. Each row shows the run's state glyph, short id, title (its milestone id), done/total subtasks, current phase and age; a dead run says `dead - lease lost <age> ago`, and an escalated one says why. **Needs attention** (escalated or dead), **Live** (running), **Parked** and **All** chips carry their counts, clicking the active one shows All again, and the search box matches a run's id, title, current phase and state. The footer reads `am · schema 1 · watching` (or `not watching`). Enter or a click opens **Run detail**: state, milestone, branch prefix, base and lease; the story > subtask > phase > attempt tree (plus the orchestrator's own Integrate / Bases / Base rows); and an output pane holding one attempt's `am logs` snapshot, labelled `snapshot <age> ago` and `· last 200 lines` when it was cut. It is never a live tail: **Refresh** fetches it again, and a failed fetch says why and keeps the last text. Run state is its own channel, never brd's status: a glyph in a ring -- running ⟳, parked ⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔ -- never colour alone. The same marks appear on **Board** cards, **Graph** nodes (a story node's pips are ringed for the subtasks a run is working on now) and in a card's RUNS section. A finished run speaking for a card, or run data with no good snapshot for 30 s, is drawn dimmed, and merged, canceled and archived cards get no live mark. The sidebar's Runs row shows `‼N` while N runs are escalated or dead. Nothing polls while the panel is closed. Requirements and failure modes are under Install.
- **Documents** - lists every `.md` file under `docs/` (at most 500; a note says
```

- [ ] **Step 4: Card detail RUNS section, Breadcrumbs, Keyboard navigation**

Replace this exact text:

```markdown
  brd comments (author, relative time, body, oldest first), or "No comments."
  They are read-only: the panel never writes a comment.
```

with:

```markdown
  brd comments (author, relative time, body, oldest first), or "No comments."
  They are read-only: the panel never writes a comment. When am runs touch the card, a **RUNS** section lists them (newest first: state glyph, short id, title, phase, age); a click opens Run detail, and Back returns to the card.
```

Then replace this exact text:

```markdown
  `Issues › <issue title>`. Click the section crumb to go back the way the old
```

with:

```markdown
  `Issues › <issue title>` and `Runs › …<last 8 characters of the run id>`. Click the section crumb to go back the way the old
```

Then replace this exact text:

```markdown
  keep it visible) through Board cards, documents or issues and, inside a card
```

with:

```markdown
  keep it visible) through Board cards, documents, issues or runs and, inside a card
```

- [ ] **Step 5: am commands, helpers and `XDG_DATA_HOME` in "The plugin runs `brd`" paragraph**

Replace this exact text:

```markdown
`milestones/setup-milestone.md` and resolves the agent's argv through
`milestones/agents.py`.
```

with:

```markdown
`milestones/setup-milestone.md` and resolves the agent's argv through
`milestones/agents.py`. For the run monitor it runs only `am` (`am runs`, `am status`, `am watch --all --follow` and `am logs`) through the helpers in `core/backend/runs/` (`runs/runs-snapshot.py`, `runs/runs-watch.py`, `runs/runs-logs.py`), and never reads am's SQLite database. am finds its journals under its own data dir, so the `XDG_DATA_HOME` the shell passes on to it matters.
```

- [ ] **Step 6: Requires line with the am requirements and error paths**

Replace this exact text:

```markdown
Requires `brd` on `PATH` to show anything. See <https://github.com/paulomtts/brd>.
```

with:

```markdown
Requires `brd` on `PATH` to show anything. See <https://github.com/paulomtts/brd>.

The run monitor also needs `am` on `PATH`. It is optional: without it the Runs screen says "am is not installed or not on PATH" and no run marks appear anywhere. `am` must speak journal schema 1; otherwise the Runs screen shows a schema-mismatch banner and the runs are polled every 5 s instead of watched. A corrupt journal shows a warning line and falls back to the same poll. If no good snapshot arrives for 30 s while the panel is open, the Runs screen says "Run data is out of date" and every run mark is dimmed.
```

- [ ] **Step 7: Tests section**

Replace this exact text:

```markdown
python3 -m pytest tests/contract -q   # brd's JSON shapes, against the installed brd
```

with:

```markdown
python3 -m pytest tests/contract -q   # brd's and am's JSON shapes, against the installed CLIs
```

Then replace this exact text:

```markdown
`brd` is not installed. `tests/run.sh` already includes it.
```

with:

```markdown
`brd` is not installed. `tests/run.sh` already includes it.
`tests/contract/test_am_shapes.py` does the same for `am`: hand-written schema 1 journals under a throwaway `XDG_DATA_HOME` pin the `am runs`, `am status` and `am watch` shapes the run helpers parse, and it is skipped when `am` is not installed.
```

- [ ] **Step 8: Re-run the check (GREEN)**

Run the Step 1 loop again.
Expected: no output.

- [ ] **Step 9: Check that the README makes no false claims**

```bash
grep -nF 'Cards and issues are read-only' README.md >/dev/null || echo "LOST read-only sentence"
grep -nE 'am <version>|data dir.*footer|footer.*data dir' README.md && echo "FOOTER OVERCLAIM"
awk '/^- \*\*Runs\*\* \(Ctrl\+6\)/' README.md | grep -qi 'toolbar' && echo "RUNS BULLET CLAIMS A TOOLBAR INDICATOR"
grep -q 'Qt.Key_6) { keys.navigator.showSection("runs")' ui/Shortcuts.qml || echo "NO Ctrl+6 in Shortcuts"
grep -q 'skipif(shutil.which("am") is None' tests/contract/test_am_shapes.py || echo "NO am skip"
```

Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add README.md
git commit -m "docs(readme): Runs monitor feature, Ctrl+6, am requirements and contract test"
```

---

### Task 6: Full verification and the spec's manual checks

**Files:**
- None modified (if a check fails, fix the doc text in the task that owns it and re-run that task's GREEN step and commit).

**Interfaces:**
- Consumes: the finished `README.md` and `docs/architecture.md`.
- Produces: the evidence that the card is done.

- [ ] **Step 1: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest reports all passed (with `tests/contract` am/brd tests skipped only when the CLI is absent), every `== tests/...tst_*.qml` block shows `Totals: N passed, 0 failed`, and the script exits 0.

- [ ] **Step 2: Confirm only the two docs changed on this branch**

Run: `git diff --name-only mon/task-5-3-run-marks-on-board-77f168a5...HEAD`
Expected: exactly `README.md`, `docs/architecture.md`, and this plan / spec under `docs/superpowers/` if the pipeline committed them. No `.qml`, `.js`, `.py` or `tests/` path.

- [ ] **Step 3: Footer, indicator and layering claims**

```bash
grep -nE 'am <version>' README.md docs/architecture.md && echo "VERSION CLAIM"
grep -n 'data_dir' README.md && echo "README NAMES data_dir"
grep -nE "toolbar's run strip beside" docs/architecture.md && echo "RunIndicator STILL DESCRIBED AS MOUNTED"
```

Expected: no output.

- [ ] **Step 4: Archive text matches main's word for word**

```bash
for f in README.md docs/architecture.md; do
  git show "main:$f" | grep -i 'archiv' | while IFS= read -r line; do
    grep -qxF -- "$line" "$f" || echo "MISSING in $f: $line"
  done
done
git diff main -- README.md docs/architecture.md | grep -E '^-[^-]' | grep -i 'archiv'
```

Expected: no output from either command.

- [ ] **Step 5: Hand-read both diffs once**

Run: `git diff mon/task-5-3-run-marks-on-board-77f168a5 -- README.md docs/architecture.md`
Expected: only the edits from Tasks 1–5; the existing `test_am_shapes.py` note in architecture "Tests" appears once; "How to add" is unchanged. Read every added line for the spec's layering check: no added sentence says `core/` imports a visual type, or that a screen or component imports `core/stores` (the run screens paragraph says they read `app.runs` and never import `core/stores`). This is a read, not a grep: the Layers table itself names `core/stores` next to `ui/screens/**`, so a pattern would flag correct text.
