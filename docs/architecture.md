# Architecture

One rule: **`ui/` may use `core/`; `core/` never imports anything visual.**
`tests/architecture/test_layers.py` enforces it (allowlists, not denylists).
Design background: `docs/superpowers/specs/2026-09-24-core-ui-architecture-design.md`.

## Layers

| layer | may import | must not import |
|---|---|---|
| `core/domain/*.js` | other `core/domain` files, `vendor/canvas/*.js` (`.pragma library`, `.import "x.js" as X` only) | any QML, `Qt*`, `Quickshell*`, `qs.*` |
| `core/backend/**` | Python stdlib, `core/backend/common` | any QML |
| `core/*` | only `domain/`, `backend/`, `stores/` (no loose files); `backend/` has no `.js`/`.qml` | |
| `core/stores/*.qml` | `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js` | `QtQuick*`, `qs.*`, `ui/`, `vendor/`, sibling directories |
| `ui/**` | everything in `core/`, `qs.Ui`, `qs.Commons`, `QtQuick*`, `vendor/canvas` | `ui/screens/**` and `ui/components/**` must not import `core/stores` (they receive `app`/props); only `Panel`, `Shortcuts`, `Navigator` may |
| `vendor/**` | its own files, `qs.*`, `QtQuick*` | `core/`, `ui/` |

Repo root holds no `.qml`/`.js`/`.py` except `install.sh`. `ui/Panel.qml` is the
manifest entry point.

## Stores (`core/stores`)

- `App.qml` composes the stores below and wires them by explicit properties.
- `HelperRunner.qml` runs one helper script: latest run wins, stale-exit guard; emits raw stdout, stores parse it.
- `FilterState.qml` one active filter with toggle and cursor reset.
- `NavigationStore.qml` view mode, section, push/pop return positions, cursor, search, dropdown; `runReturnMode` (`"runs"` | `"entry"`) says where Back from an open run goes.
- `ProjectStore.qml` registry, selection, remembered project, DB watch path.
- `ProjectDeleteStore.qml` delete-project confirm/snapshot flow.
- `BoardStore.qml` cards, index, selection, board order, the issue map (`brd issue list`; an old brd without issues is just an empty map); owns the DB `FileView` and the 250ms `watchTimer` that debounces it, so a burst of writes costs one tree+issue+export fetch (`fetchBoard()` itself -- Refresh, a project switch -- stays immediate).
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
  map, for each node's open-issue count): the milestone graph and the story
  graph (`graph.js`'s `graphModel` / `storyGraphModel`). `graphView`
  ("milestone", the default, or "story") picks which one `currentNodes` /
  `currentEdges` / `currentGroups` / `currentGroupEdges` (the story view's
  box-to-box dependency) -- and so the canvas, the arrow keys and
  Enter -- work on; `setGraphView` refuses anything else, so one of the two
  chips is always active, and keeps the selection on a node of the new view.
  Nothing resets it, so the choice is remembered for the session and survives a
  project switch (the cursor still clears with the project). `showArchived`
  (off by default, set by the toolbar's Show archived chip through
  `setShowArchived`) decides whether both models are built from every card root
  or from `Graph.withoutArchived(cardRoots)`, which drops an archived card with
  its whole subtree; a selection that disappears moves to the first node. Plus
  the graph cursor and its movement.
- `DocumentsStore.qml` listing, category filter, open document, tagging, plus
  brd's registered documents (`brd doc list`, fetched only when the section
  opens because it syncs -- writes -- every backup; re-entering the section you
  are already in does not run it again, and a `source_path` that leaves the
  project -- absolute, or with a `..` segment -- is dropped). `mergedDocs` matches the
  listing and the registrations on the path relative to the project root; a
  registration whose file is gone stays in the list as `missing: true`. A failed
  listing leaves the registrations already shown in place.
- `ExtrasStore.qml` the read-only extras from one `brd export`: comments by
  entity, EXPLICIT refs both ways (the export's `refs[]` carry only the refs
  written with `--ref`; the origin `"link"` refs a `[[wikilink]]` creates are
  reported per entity by `brd show`/`brd issue list`, which this store does not
  read), and the rich issue list (body, close reason, comment
  count, and the cards an issue blocks, derived from the export's nested card
  tree because an exported issue carries no `blocks` of its own). Fetched with
  the board through `BoardStore.refetched()`, and any failure -- an old brd
  without `export`, a crash, garbage -- is simply empty extras, never an error.
  It never feeds the board: the blocker rows and the graph keep reading
  `BoardStore.issueMap` (`brd issue list`).
- `MemoriesStore.qml` listing, type filter, open/edit/create/delete a note.
- `MilestoneStore.qml` the New-milestone dialog and the one agent job
  (`idle -> running -> done|failed`): two `HelperRunner`s, both
  `run-setup-milestone.py` -- the run itself, and `--describe`, which the
  dialog asks for once per project as it opens. It never reaches for the board: `App` hands it `cardCount` and
  routes its `boardRefreshRequested()` to `board.fetchBoard()`. The spec
  runner's guard is the project the JOB is for, not the selected one, so a run
  that outlives a project switch is still recorded truthfully; `jobVisible`
  decides whose panel shows it.
- `RunStore.qml` the am run monitor's data: one snapshot of the selected
  project's am runs (`runs-snapshot.py`, normalized through `runs.js`), the
  selected run and `amStatus`. While the panel is open it runs `runs-watch.py`
  (250 ms debounce per burst of changes, 10 s liveness re-read while a run is
  running, a `stale` flag 30 s after the last good snapshot, and a 5 s fallback
  poll when the journal has a schema mismatch or is corrupt). It never reaches
  for another store: `App` hands it `project` (the selected project's root
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`).
  `amStatus` is `ok`, `missing` (an `AmMissing` snapshot: `runs` is emptied, so no run marks show), `schema` (the watch ended with `SchemaMismatch`: `watchSchemaError` holds the banner text, which stays up through the polling snapshots) or `error` (any other failed snapshot: the last good `runs` stay), with `lastError` saying why. A watch that ends with `CorruptJournal` sets `watchWarning` (the Runs screen's warning line) and starts the same 5 s poll.
  The Runs list is `filteredRuns`, `Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery)`: `runFilter` is `""` (All) or `attention` / `live` / `parked`, set by `toggleRunFilter(id)` (the All chip, or the active chip again, means All), which emits `runFilterToggled()` so the cursor and the scroll go home; `App` binds `searchQuery` to the navigation store's, and a project switch resets the chip.
  Run detail's output pane is a second `HelperRunner`, `logsRunner` (`runs-logs.py`, guarded by the project like the snapshot): `selectedAttempt` (`{ card_id, phase, attempt }` or null), `logsText` (`Runs.logTail` of the last good reply, at most 200 lines), `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError` and `logsStatus` (the attempt's status when its fetch was launched). Logs are fetched on demand only -- `selectAttempt(...)`, `openDefaultAttempt()` when a run is selected, `refreshLogs()` (the Refresh button), and after a snapshot that moved the selected attempt's status -- never on a timer and never as a live tail. A failed fetch sets `logsError` and keeps the last good text; another attempt starts from an empty pane.
  Run controls (S2 4.1): `control(action, runId)` starts a `pause`, `resume` or `cancel` of a run in `runs` and returns whether it did; it refuses without a project, for an action `Runs.controls(run)` disables, and for a run that already has a request in `pending`. Confirming a cancel is the caller's job. Each request gets its own `HelperRunner` (`controlRunners`, guarded by the project), so requests for different runs never stop each other and a reply for a project the user has left is dropped. Pause, cancel and a `--card` run's resume (`workflow` `task`) run `run-control.py ACTION RUN REPO`; any other resume first reads `viewer-state.py get-run-settings` and passes the stored verify set as `--verify` pairs, else `--allow-no-verification` when that was chosen, else refuses with a sentence. `pending` (`{runId: action}`) holds from the launch until a snapshot after am's `ok: true` reply shows the run gone, its state changed, or (pause, cancel) its am request handled; no snapshot settles a request still in flight. A failed request clears its entry and sets `lastControlError` (the `Runs.controlError` sentence) and `lastControlErrorRunId`, which no snapshot touches -- `lastError` stays the snapshot banner -- and which `dismissControlError()` or the next request clears. Every control reply re-snapshots. `stillWaiting` marks requests pending for 30 s or more (`pendingTimer`, 1 s, only while the panel is open), and `stillWaitingText` is the line the UI shows for them. Closing the panel keeps `pending`; a project switch empties it and the control error. The cancel confirmation is the store's too (S2 4.3): `refusalOf(action, runId)` is `""` when `control` would start and otherwise the sentence why not (`This run is no longer in the snapshot`, then `A request for this run is pending`, then the `Runs.controls` reason; `Unknown control` for another action); `openCancel(runId)` opens it (`cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`) or flashes the refusal, `closeCancel()` closes it, and `confirmCancel()` needs `cancelText` to be `cancel` (trimmed, case-blind), checks `refusalOf` again -- a run that changed under the dialog keeps it open with `cancelError` -- and only then calls `control("cancel", …)`. `flash(text)` sets `flashText`, which `flashTimer` clears 3 s later; a project switch closes the dialog and clears the flash. Alerts (S2 4.4): while `active`, every good snapshot is compared with the one before it through `Runs.newAlerts`, and each run that newly turned escalated or dead gets a toast in `toasts` (`{key, id, title, state, reason, expiresMs}`, oldest first, at most 3, one per run; `key` only grows, so a stale Dismiss never removes a newer toast). `alertsArmed` says the current `runs` may be compared against: the first good snapshot after an opening, a project switch or an `AmMissing` reply only arms, so reopening the panel never replays history, and a snapshot that lands after the panel closed raises nothing. A toast lasts `toastMs` (8000); `toastTimer` (250 ms, only while the panel is open and a toast shows) drops expired ones through `expireToasts(nowMs)`, and `dismissToast(key)` / `dismissAllToasts()` remove them. Closing the panel and a project switch empty `toasts`.

Other `ui/` pieces: `Navigator.qml` (screen switching; `openRun(id, from)` opens Run detail and records where Back goes in `runReturnMode`: from a card's RUNS row (`from` `"entry"`) the card stays open behind it and Back returns to it through `restoreCardFromRun()`, from the Runs list Back restores the list through `restoreRunsList()`), `Shortcuts.qml` (key
events to store calls; Ctrl+1..6 follow the sidebar's order: Board, Graph,
Documents, Memories, Issues, Runs; `handleRunKey` makes a bare `p` / `r` / `c`
pause, resume or cancel the run on Run detail, and the cursor row on the Runs
list while its search is empty -- a refused key flashes `refusalOf`'s sentence,
`c` only opens the cancel confirmation; `modalOpen()` is the one guard both the
chords and the run keys obey, and Escape closes the cancel confirmation before
the dropdown), `theme/Theme.qml` (colours and fonts from the shell).

Not every process goes through `HelperRunner`: `listProc` (`brd projects`), `treeProc` (`brd tree`), `issueProc` (`brd issue list`), `exportProc` (`brd export`), `brdDocsProc` (`brd doc list`), `saveStateProc`, `resolveDbPathProc` and `deleteProc` stay plain `Process` objects because they run the `brd` CLI or are fire-and-forget/single-owner with their own exit handling. `HelperRunner.run()` SIGTERMs a previous run of the same helper instead of letting it finish and dropping its reply (reachable for list-docs/list-memories refetches, and a set-doc-tag started in another project mid-flight); helpers write atomically, so at worst a stray `docs/.tmp-*` remains.

## Shared components (`ui/components`) - reuse before writing a second copy

`ThemedText` (text), `ActionButton` (bordered button), `Badge` (pill),
`Breadcrumbs` (the toolbar's location trail; `Navigator.crumbs` builds the list
and `Navigator.activateCrumb(index)` acts on a click, so the component stays
presentational),
`Chip` and `ChipRow` (filter chips), `CommentList` (the read-only brd comments
of one entity, used by the card detail and the issue detail),
`ModalCard` (dimmed backdrop and card),
`TypedConfirmDialog` (the typed-word modal: `confirmWord`, and `dismissLabel`
for the safe button -- `Cancel` unless the owner says otherwise, `Keep running`
for a run cancel), `ListRow` (hover / keyboard cursor / reveal; its
`actions` slot holds items under the content, stacked above the row's
MouseArea so a button there takes its own click -- a click anywhere in that
strip, a disabled button included, never activates the row -- and with nothing
in it the row is exactly as tall as before),
`ListStatus` (loading/error/empty), `FilterableList`, `TextAreaBox`,
`TagPicker`, `NewMemoryDialog`, `NewMilestoneDialog` (the from-spec modal),
`ArchiveFinishedDialog` (the confirm list behind the Board toolbar's
**Archive finished (N)** button), `MilestoneJobIndicator` (the toolbar strip while a milestone job runs, and its
result), `StatusPips` (one status circle per subtask on a story node, the
overflow as a `+N`; its single pulse animation runs only while the row is
visible AND holds an in-progress pip, so an idle graph animates nothing; `ringedIds` rings, with the pip's own border, the subtasks an am run is working on now -- `GraphScreen` picks each pip whose winning run is running and whose own am row is in the running bucket, and `GraphView` hands the list down),
`Pulse` (that one fade, shared: `level` swings 1 -> 0.3 -> 1 while the owner
keeps `running` true and is back at 1 the moment it stops; `StatusPips` and
`RunBadge` bind their opacity to it instead of declaring a second animation),
`RunBadge` (an am run state as a glyph in a `Badge` ring -- running ⟳, parked
⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔, from `runGlyphs.js` -- with a
subtask's phase beside it, or a parent's non-zero counts such as `⟳ 2 ⏸ 1`
instead; escalated in `urgent`, never `Board.statusColor`; it pulses only
while running, visible and `active`),
`RunRollupBar` (a milestone's or story's run rollup under its title: one
caption segment per non-zero count in the same glyphs, then `N pending`;
escalated in `urgent`; hidden when the rollup is null or its total is 0),
`PhaseTimeline` (one subtask's phases as a single static line such as `spec✔ → plan✔ → implement⟳ → verify· → review·`: done ✔, started ⟳ and failed ✖ from `runGlyphs.js`, pending a local ·; an unknown status shows the bare name, bad entries are skipped and missing or empty `phases` hide it; no colour-only state, no animation),
`RunIndicator` (a toolbar run strip built to sit beside `MilestoneJobIndicator`, not yet mounted -- `Panel`'s toolbar carries only `MilestoneJobIndicator`: one `ActionButton` per non-zero `running` / `parked` / `attention` prop, written glyph-then-count with no space such as `⟳2 ⏸1 ‼1`, glyphs from `runGlyphs.js` and counts clamped by its `countOf`; attention in `urgent`; hidden when all three are 0; static, no animation; presentation only -- the owner computes the counts, and a click emits `filterRequested(filter)` with `"live"`, `"parked"` or `"attention"` from the Runs filter set `attention` / `live` / `parked` / `all`, `all` being emitted by no segment),
`RunMark` (one card's run mark on the Board and the Graph: a `RunBadge` inside the wrapper that owns the dimming -- a dimmed winner (a finished run speaking for the card) or stale run data is drawn at half opacity and never pulses; the owner hands it `cardRunState` and `rollup`, or null for no mark, and never brd status),
`RunControls` (one run's `ActionButton`s -- Pause `⏸`, Resume `⟳`, Cancel `⊘` in `danger`, glyphs from `runGlyphs.js` -- with at most one of Pause and Resume: Pause on a running run, Resume on a parked, escalated or dead one, and a pending request keeps its own button reading `… requested…`; enabled and tooltip from `Runs.controls(run)`, every button disabled while a request is pending; a reason line repeats the shown disabled buttons' reasons, because a disabled shell Button gets no hover and so no tooltip; `wholeRun` adds `run` to the labels and an `applies to the whole run` caption; then the still-waiting line and the control error in `urgent`. A finished, unknown or missing run shows nothing and the component is 0 tall. Presentation only, like `RunIndicator`: the owner passes the run, `pendingAction`, `waiting`, `waitingText`, `errorText` and `showButtons`, and a click on an enabled button emits `actionRequested(action)`. `runControlFacts.js` reads `pending`, `stillWaiting` and the control error for one run with own-key checks, for the owners),
`Sidebar`, and the views
`DocumentsView`, `MemoriesView`, `MemoryNoteView`, `GraphView`.
`Sidebar`'s six nav rows (Board, Graph, Documents, Memories, Issues, Runs) each lead with an
icon glyph drawn in the theme's font; `tests/architecture/test_icon_glyphs.py`
checks every glyph literal in `ui/` and `vendor/` against the installed Nerd
Fonts, because a glyph the font does not have renders as an empty box.
`Sidebar.runsAttention` (int, default 0; the owner's escalated-plus-dead run count) derives `runsAttentionText` (`‼N` from `runGlyphs.js` when N > 0, otherwise empty), and `NavRow.countText` draws such a count after a row's label in `urgent` as `navCount<Section>`; the Runs row binds `countText: sidebar.runsAttentionText`, and `Panel` feeds `runsAttention` from `Runs.attention(runs).length`, so the Runs row reads `‼N` while N runs are escalated or dead.
`ui/screens/DocumentsToolbar.qml` is the Documents half of the panel's fixed
toolbar - the category chips of the list, and the path and type picker of an
open document - so only the document body scrolls.

The run screens read `app.runs` and never import `core/stores`. `ui/screens/RunsScreen.qml` (Ctrl+6) lists `filteredRuns`, one row each (state glyph, short id, title, done/total, current phase, age; a dead run's age is since its last heartbeat, and an escalated run adds `escalationReason`), under the Needs attention / Live / Parked / All chips with their `runFilterCounts`. Above the list it shows the schema banner, `Run data is out of date` while `stale`, and the `watchWarning` line. Below it the footer reads `am · schema 1 · watching` (or `not watching`), shows `lastError` instead when `amStatus` is `error`, and is hidden when am is missing or the schema banner shows. With am missing the list shows `am is not installed or not on PATH`. `ui/screens/RunDetailScreen.qml` (view mode `run`) shows the header (state, milestone, branch prefix, base, lease), the `runTree` story > subtask > phase > attempt tree plus the Integrate / Bases / Base rows (cards brd has closed are dimmed, never hidden), and the output pane: one attempt's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a Refresh button and `logsError` in `urgent`. `CardDetailScreen` adds a RUNS section: every run `runsTouching` the card, newest first, with glyph, short id, title, phase and age, dimmed while stale. A click opens Run detail with `from` `"entry"`; a merged or canceled card still lists its runs, and nothing is listed while am is missing. Each of the three run surfaces carries a `RunControls` per run: a Runs row in its `ListRow.actions`, showing the buttons while the row has the cursor (hover moves the cursor) or a request is pending; Run detail under the header, always; a card's RUNS row in its `actions`, always, as whole-run controls (`Pause run`, the caption) on a story or subtask card. The still-waiting and error lines show whenever they apply. Pause and Resume call `app.runs.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` -- confirming a cancel is the owner's job, and no screen calls `control("cancel", …)`. Panel answers every `cancelRequested` with `app.runs.openCancel(runId)`: a third `TypedConfirmDialog`, `runCancelModal`, asks for the word `cancel`, says that Cancel is final (no resume, only a relaunch; cards keep their status; a phase in flight finishes first) and reads `Keep running` / `Cancel run`; it takes the focus while open and gives it back on close, Escape closes only it, and only its confirm (`confirmCancel()`) calls `control("cancel", …)` -- a run that changed under it keeps it open with the reason. On the Runs list (search empty) and Run detail a bare `p` / `r` / `c` does the same as the buttons; a refused key flashes its sentence for 3 s in the Runs footer (shown even beside the schema banner) or in Run detail's `runDetailFlash` line, the last line of the run's body. `BoardScreen` and `GraphScreen` draw a `RunMark` per card (plus `RunRollupBar` under a Board card's title) from `cardRunState` / `rollup`, except on cards `Board.isClosedStatus` reports closed (merged, canceled, archived) and while am is missing -- a visibility rule in the screens, never a run state. Every age on these screens is read against the clock once per snapshot (or logs reply): there is no timer.

Run state is a separate channel from brd status: a glyph plus a ring (`RunBadge`'s `Badge`, or a `StatusPips` ring), never colour alone. `ui/components/runGlyphs.js` is the one glyph source -- running ⟳, parked ⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔ -- read by `RunBadge`, `RunRollupBar`, `PhaseTimeline`, `RunIndicator`, `RunMark`, `Sidebar` and the run screens. Escalated is drawn in the `urgent` token; merged purple and canceled red (`Board.statusColor`) are never used for a run state.

Refresh model: no timers while idle. `RunStore`'s watch, its debounce, the liveness re-read (only while a run is running), the fallback poll and the toast expiry (`toastTimer`, only while a toast shows) run only while the panel is open (`active`); closing it stops the watch process and every timer and starts nothing new (a one-shot snapshot or logs fetch already in flight runs to its end). Logs are fetched on demand, and `Pulse` animates a run badge only while it is running, visible and `active`.

Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
exit code), `text.js` (`matchesQuery`), `milestones.js` (the two helper
parsers, `agentMessage`, `formatElapsed`, the spec-list ordering and filter),
`brd-extras.js` (the `brd export` and `brd doc list` parsers, the issue
ordering/filtering and its wording, and `relativeTime` for a comment's age; the
export's `documents[]` carry every registered file's full content and are
dropped unread), `documents.js`'s `mergeRegistered` / `brdStateLabel` for
brd's registrations, and `runs.js`, the am run model: pure JS, never throws, and every input comes from `am`, never from a brd card. Normalizing: `normalizeRun` (an `am runs` row plus its `am status` data). State: `runState` (running = `started` with a live lease, dead = `started` without one, parked = `stopped`, plus escalated, cancelled and done; anything else is `unknown`), `cardRunState` (the newest non-terminal run touching a card speaks for it, else the newest touching run, dimmed; its `state` is running / dead / parked / escalated / none) and `glyphStateOf` (an am story, subtask, phase, attempt or row status as a `runGlyphs.js` key). Card mapping: `runsTouching` and `runTree`, through `run.milestone_id`, `stories[].card_id` and `subtasks[].card_id`, never through rows alone; the synthetic ids `integrate`, `bases` and `base-<story-id>` never match a card (Run detail shows them as rows of their own). Rollups and attention: `rollup` (counts from the winning run's am rows), `attention` (escalated or dead: "Needs attention") and `escalationReason`. Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`. Display text: `shortId`, `runTitle`, `runProgress`, `currentPhase`, `ageText`, `runAgeText`, `snapshotAgeText`, `errorText`. Logs: `logTail`, `defaultAttempt`, `attemptStatus`. Run state is never derived from brd status: `cardRunState` reads no brd status at all, and it is the screens that skip the cards `Board.isClosedStatus` reports closed (merged, canceled, archived);
Python: `core/backend/common`
(`json_line`, `safe_paths`, `atomic_write`, `frontmatter`).
`core/backend/milestones/` is the New-milestone backend:
`setup-milestone.md` (the prompt the agent is given),
`agents.py` (one adapter per coding agent: the exact argv, whether the run can
be restricted, and the `--help` lines that justify it) and
`run-setup-milestone.py`, which resolves the default agent through
`omarchy-default-agent`, spawns it in its own session (argv only, never a
shell), enforces `OPM_AGENT_TIMEOUT_SECONDS` (default 1800), kills the whole
process group on cancel or timeout, and logs to
`${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/agent-logs/`
(dir `0700`, file `0600`). Only `claude` runs restricted (read plus
`Bash(brd *)`); every other agent runs with full auto-approval, which the
dialog states before the run starts.
`core/backend/runs/` is the run-monitor backend, scoped to the open project. `runs-snapshot.py <project_root>` runs `am runs --repo-dir R`, then `am status <id> --repo-dir R` for every non-terminal run and the latest 10 terminal ones, and prints one JSON line (`{ok, runs, data_dir}` or an error; nothing in the UI shows `data_dir`). `runs-watch.py <project_root> [run_id ...]` is long-lived: it runs `am watch --all --follow`, checks that the hello line's schema is 1, drops journal lines written before it started (an S4 workaround until `am watch --from-now` exists), keeps the watched runs plus any run whose `run_upsert` names this project root, prints at most one debounced `{"changed": [...]}` line per 250 ms, and ends with an `AmMissing`, `SchemaMismatch`, `CorruptJournal` or `HelperError` envelope (exit 0 when it was stopped). `RunStore` runs it as a plain `Process`, not through `HelperRunner`. `runs-logs.py RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N` passthrough: no `--repo-dir` (am resolves the run by id), a 60 s timeout, exactly one JSON line. All three use only documented `am` commands, as argv lists, and never read am's SQLite database or its on-disk layout; am finds its journals under its own data dir, so the `XDG_DATA_HOME` it inherits matters.

When a thing is needed a second time it becomes shared **before** the second
use is written. The architecture test fails on a second copy of: the modal
backdrop `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`,
`font.family:`, `CursorSurface {`, and of `emit`/`inside`/`write_atomic`/
`split_frontmatter`/`frontmatter_of` in Python. It also rejects component
names that clash with shell (`qs.Ui`) or QtQuick/Controls types: the shell
would load its own type instead of ours.

## How to add

- **A screen**: `ui/screens/XScreen.qml` with `property var app`; use only shared
  components and `app` (never import `core/stores`); register it in `Navigator.qml`;
  add a test under `tests/ui/`.
- **A store**: `core/stores/XStore.qml` importing only `QtQml`/`Quickshell`/
  `Quickshell.Io` and `../domain/x.js`; run helpers through `HelperRunner`;
  compose it in `App.qml`; test headless under `tests/core/stores/`.
- **A helper script**: `core/backend/<domain>/name.py`, one JSON line on stdout,
  `sys.path` insert of its parent for `common`, no duplicated helpers; pytest
  under `tests/core/backend/<domain>/`; call it via `backendDir` from a store.

## Tests

- `bash tests/run.sh [filter]` - pytest, then every QML test against a mirror of the repo (`./run-tests.sh` delegates to it).
- `python3 -m pytest tests/architecture -q` - layer and duplication rules only.
- `python3 -m pytest tests/contract -q` - runs the installed `brd` in a throwaway
  project (its own `HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME` under a tmp dir, so no
  real board is read or written) and fails when brd's JSON shape drifts from what
  `core/domain/brd-extras.js` parses; skipped when `brd` is absent.
  `test_am_shapes.py` does the same for the installed `am`: hand-written schema 1
  journals under a throwaway `XDG_DATA_HOME`, pinning the `am runs`, `am status`
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses;
  skipped when `am` is absent.
- `bash tests/live-check.sh` - restarts the real shell and fails on plugin load errors in the journal (needs the desktop session).

## Documented exceptions

- `Panel.qml` shares a name with a shell type: it is loaded by manifest path.
- `vendor/canvas/Canvas.qml`: always used qualified.
- Panel-detail tone pill (`CardDetailScreen`) uses `radius: height / 2` itself, not `Badge`.
- `StatusPips` uses `radius: height / 2` too: a subtask pip is a small circle
  carrying no text, so neither `Badge` nor `Chip` fits.
- `GraphView`'s story boxes are an Item INSIDE the vendored canvas with `z: -1`,
  mirroring its camera (`panX`/`panY`/`zoom`): the canvas draws nodes and edges
  only, and the boxes must paint behind them. The canvas's own `fitAll()` frames
  the NODES, so `GraphView.fitAll()` unions the boxes in and hands the result to
  the canvas's public `fitBounds(rect)`.
- A box is never a rect from the model: `graph.js`'s `storyGroupRects` derives it
  from its own stories' CURRENT positions, so a story is always inside its box
  and a story dragged over another milestone's box is never adopted by it
  (membership is `milestoneId`, never geometry). Boxes may therefore overlap
  after a drag; **Organize** puts them back. To follow a drag frame by frame,
  `GraphView` READS the canvas's working positions (`canvas._positions`, via
  `Positions.key`) -- the one place this plugin reaches into the vendored
  canvas's bookkeeping, read-only. What the user arranged (a dropped story, a
  moved box) lives in `GraphView.arranged` and is handed back to the canvas as
  the nodes' own coordinates (`Graph.placedNodes`), which the canvas treats as
  pinned; a new `nodes` array (a board change) clears it, so a refresh resets an
  arranged story graph exactly as it resets a dragged node in the milestone view.
- The box-to-box edges reuse the vendored `CanvasEdges` unchanged, declared
  inside that box layer before the boxes: same curve, same anchors (a box's right
  border to the next box's left), thicker and at a lower opacity than a story
  edge, and with `hitWidth: 0` so a box edge never swallows a click or a pan.
  The one derivation behind them, `storyGraphModel`'s `groupEdges`, is also what
  ranks the boxes in the layout.
- The vendored `CanvasControls` are pointed at a small `QtObject` in `GraphView`
  rather than at the canvas: **Organize** and **Fit** are the view's (a story
  graph organizes per box, and framing has to take the boxes in), zoom and
  culling stay the canvas's own. Both views re-frame after Organize: the
  canvas's own `organize()` ends in `fitAll()`, and the story path re-fits with
  the boxes in.
- A box is dragged by its label strip only. The rest of a box is either a story,
  which drags itself, or empty space, where a drag has to stay the canvas's pan.
- The box `Repeater`'s model is the STABLE group list, never the live rects: a
  drag recomputes those on every pointer move, and a model change rebuilds the
  delegates -- which would destroy the very handler driving the gesture. Each box
  looks its own rect up by id instead. (The vendored `CanvasEdges` does rebuild
  its Shapes when its geometry changes; that is how the canvas already draws node
  edges during any drag, and it is not ours to change.)
- A box move is applied to the canvas's WORKING positions frame by frame
  (`canvas._moveNode`, the write counterpart of the read above) and committed to
  `arranged` ONCE, when the gesture ends: handing the canvas a new `nodes` array
  per pointer event would re-run the layout on every frame.
- **Touchpad wheel.** A two-finger slide must pan; a pinch zooms (the vendored
  canvas's `PinchHandler`, untouched). The canvas's own `WheelHandler` pans on a
  pixel delta and zooms on an angle delta, which is right for a mouse but not for
  a touchpad: Qt on Wayland may report a slide with an angle delta only, and the
  canvas would then read it as a mouse notch. `GraphView` therefore puts a
  `graphWheelLayer` Item IN FRONT of the canvas carrying wheel handlers only, so
  presses, drags, taps and the pinch still fall straight through. Its first
  handler is `acceptedDevices: PointerDevice.TouchPad` and blocking (the
  default), so the canvas never sees the same event twice and a mouse wheel
  never reaches it at all; it normalises the event to a pixel delta
  (`_touchpadPixels`: the event's own, else its angle delta at
  `_wheelNotchPixels` per 120) and forwards it to the canvas's one wheel entry
  point, `canvas._handleWheel`, so no camera arithmetic is reimplemented.
  Ctrl is forwarded untouched and still zooms about the cursor. The second
  handler is `blocking: false`, `enabled` only under `OPM_DEBUG_WHEEL=1`, and
  traces every wheel event the graph sees (device, deltas, phase, modifiers,
  inverted) to the shell log -- the only way to read the shape a real device
  delivers, since QtTest cannot synthesize a pixel delta or a touchpad device.
  `tst_graph_wheel.qml` drives the normalisation through `_handleTouchpadWheel`
  and checks that the panel's own Flickable/Column stack does not swallow a
  wheel on the way down.
- Every map in `graph.js` keyed by a card id goes through its `mapKey`, and the
  position maps (keyed by raw card id, because they cross into QML that way) are
  prototype-less and read with `hasOwnProperty`: brd can name a card
  `constructor`, `toString` or `__proto__`. The vendored `layout.js` has its own
  guard for that, but still mishandles the three ids whose names it uses
  internally as functions (`hasOwnProperty`, `isPrototypeOf`,
  `propertyIsEnumerable`) -- a pre-existing limitation of the vendored layout,
  in both graph views.
- `BoardCard` (BoardScreen) and Sidebar's project button, `NavRow`, `ProjectItem` use `CursorSurface` directly (and `bordered: true` for the two bordered ones).
- `TextAreaBox` sets `font.family` itself: it is a `Controls.TextArea`, not a `Text`, so it cannot be a `ThemedText`.
