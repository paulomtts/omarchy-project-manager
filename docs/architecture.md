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
- `RunStore.qml` the am run monitor's data: a list snapshot of every project's am runs (`runs-snapshot.py` with no argument) kept to the rows whose project is the selected one (`project.repo_dir`, else the row's `repo_dir`, compared with a trailing `/` ignored) and normalized through `runs.js`, plus the selected run and `amStatus`. It never reaches for another store: `App` hands it `project` (the selected project's root path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which the panel binds to its `opened`).
  Nudges, never folded into state: while `active`, the first good list snapshot starts `runs-watch.py` with no argument -- no `--since-seq`, so the watch begins at am's default position and the store never resumes from `watchCursor` -- whose `changed` lines say "run X changed at seq N". The store keeps the highest `seq` per run in `nudges` and takes them once per 250 ms debounce window (`debounceTimer`): a nudge for a run `appliedSeq` does not know costs one list snapshot and no run read; otherwise each nudge newer than `appliedSeq[run]` for a run in `runs` costs one run read (`runs-snapshot.py --run RUN` on a `HelperRunner` of its own, `readRunners`; a newer read of the same run supersedes an older one still in flight); any other nudge is ignored. `asOfSeq` is the last good list snapshot's `as_of_seq` (`0` before one); `appliedSeq` (`{runId: seq}`) is the `as_of_seq` of the list snapshot or run read that last covered each run, of every project the list named; `watchCursor` is the watch's last `{"cursor": C}`, held in memory only and never passed back to the helper; `storeId` is the last non-empty `store_id` a hello, a list snapshot or a run read named.
  A run read's reply: `UnknownRunError` launches one list snapshot; `StoreBusyError` sets `stale` and keeps the nudge for the next window; any other failure changes nothing; a reply naming another store starts over (below). A good reply for a run still in `runs` that no newer snapshot covers rebuilds that run from its remembered `am runs` row and the reply's status, sets `appliedSeq[run]`, leaves `asOfSeq`, `amStatus` and `lastError` alone, and then raises alerts, settles pending controls, refreshes logs and restarts the stale clock as a list snapshot does.
  Starting over: a hello with `cursorReset` true, or a hello or a run read naming a `store_id` other than `storeId`, clears `appliedSeq`, `asOfSeq`, `watchCursor`, `nudges`, the run reads in flight, `runs` and `alertsArmed`, then takes one list snapshot. A list snapshot naming another store first forgets the same live state and is applied as the new store's full snapshot, with no toast. The first `store_id` seen resets nothing, and `storeId` survives a project switch, a watch end and `AmMissing`. A project switch clears `nudges`, `appliedSeq` and `asOfSeq` and drops the run reads in flight.
  `amSchema` (the schema from the current watch's hello; `0` = unknown) and `amVersion` (am's version from it; `""` = unknown) are set from the watch's `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}` line -- `schema` when it is an integer of 1 or more, else `0`; `am` when it is a string, else `""`; `head` is not read -- and go back to unknown when a watch starts, stops or exits. Timers: the 250 ms debounce, a 10 s liveness re-read of the list while a run is running, a `stale` flag 30 s after the last good list snapshot or applied run read, and a 5 s fallback poll after a watch ended with `SchemaMismatch` or `CorruptJournal`.
  `amStatus` is `ok`, `missing` (an `AmMissing` list snapshot: `runs`, `appliedSeq` and `asOfSeq` are emptied, so no run marks show), `schema` (the watch ended with `SchemaMismatch`: `watchSchemaError` holds the banner text, which stays up through the polling snapshots) or `error` (any other failed list snapshot: the last good `runs` stay), with `lastError` saying why. A list snapshot whose reply is `SchemaMismatch` -- an am whose `am runs` has no `as_of_seq` -- is `error`, with `lastError` saying the plugin needs the newer am, and starts no watch: only a good list snapshot starts one. A `StoreBusyError` list snapshot only sets `stale`. A watch that ends with `CorruptJournal` sets `watchWarning` (the Runs screen's warning line) and starts the same 5 s poll.
  The Runs list is `filteredRuns`, `Runs.searchRuns(Runs.filterRuns(runs, runFilter), searchQuery)`: `runFilter` is `""` (All) or `attention` / `live` / `parked`, set by `toggleRunFilter(id)` (the All chip, or the active chip again, means All), which emits `runFilterToggled()` so the cursor and the scroll go home; `App` binds `searchQuery` to the navigation store's, and a project switch resets the chip.
  Run detail's output pane is a second `HelperRunner`, `logsRunner` (`runs-logs.py` with the project root first, then the run, card, phase and attempt; guarded by the project like the snapshot): `selectedAttempt` (`{ card_id, phase, attempt }` or null), `logsText` (`Runs.logTail` of the last good reply, at most 200 lines), `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError` and `logsStatus` (the attempt's status when its fetch was launched). Logs are fetched on demand only -- `selectAttempt(...)`, `openDefaultAttempt()` when a run is selected, `refreshLogs()` (the Refresh button), and after a snapshot that moved the selected attempt's status -- never on a timer and never as a live tail. A failed fetch sets `logsError` and keeps the last good text; another attempt starts from an empty pane.
  Run controls (S2 4.1): `control(action, runId)` starts a `pause`, `resume` or `cancel` of a run in `runs` and returns whether it did; it refuses without a project, for an action `Runs.controls(run)` disables, and for a run that already has a request in `pending`. Confirming a cancel is the caller's job. Each request gets its own `HelperRunner` (`controlRunners`, guarded by the project), so requests for different runs never stop each other and a reply for a project the user has left is dropped. Pause, cancel and a `--card` run's resume (`workflow` `task`) run `run-control.py ACTION RUN REPO`; any other resume first reads `viewer-state.py get-run-settings` and passes the stored verify set as `--verify` pairs, else `--allow-no-verification` when that was chosen, else refuses with a sentence. `pending` (`{runId: action}`) holds from the launch until a snapshot after am's `ok: true` reply shows the run gone, its state changed, or (pause, cancel) its am request handled; no snapshot settles a request still in flight. A failed request clears its entry and sets `lastControlError` (the `Runs.controlError` sentence) and `lastControlErrorRunId`, which no snapshot touches -- `lastError` stays the snapshot banner -- and which `dismissControlError()` or the next request clears. Every control reply re-snapshots. `stillWaiting` marks requests pending for 30 s or more (`pendingTimer`, 1 s, only while the panel is open), and `stillWaitingText` is the line the UI shows for them. Closing the panel keeps `pending`; a project switch empties it and the control error. The cancel confirmation is the store's too (S2 4.3): `refusalOf(action, runId)` is `""` when `control` would start and otherwise the sentence why not (`This run is no longer in the snapshot`, then `A request for this run is pending`, then the `Runs.controls` reason; `Unknown control` for another action); `openCancel(runId)` opens it (`cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`) or flashes the refusal, `closeCancel()` closes it, and `confirmCancel()` needs `cancelText` to be `cancel` (trimmed, case-blind), checks `refusalOf` again -- a run that changed under the dialog keeps it open with `cancelError` -- and only then calls `control("cancel", …)`. `flash(text)` sets `flashText`, which `flashTimer` clears 3 s later; a project switch closes the dialog and clears the flash. Alerts (S2 4.4): while `active`, every good list snapshot and every applied run read is compared with the runs before it through `Runs.newAlerts`, and each run that newly turned escalated or dead gets a toast in `toasts` (`{key, id, title, state, reason, expiresMs}`, oldest first, at most 3, one per run; `key` only grows, so a stale Dismiss never removes a newer toast). `alertsArmed` says the current `runs` may be compared against: the first good list snapshot after an opening, a project switch, a start-over or an `AmMissing` reply only arms, so reopening the panel never replays history, and a snapshot that lands after the panel closed raises nothing. A toast lasts `toastMs` (8000); `toastTimer` (250 ms, only while the panel is open and a toast shows) drops expired ones through `expireToasts(nowMs)`, and `dismissToast(key)` / `dismissAllToasts()` remove them. Closing the panel and a project switch empty `toasts`. "Notify on escalation" is per project and off by default: a project switch resets `notifyOnEscalation` and reads `viewer-state.py get-run-settings` on `settingsLoadRunner` (its guard is set by `projectSwitched()` itself, so the launch carries the new project); `setNotifyOnEscalation(on)` flips it at once and writes `set-run-settings ROOT {"notifyOnEscalation": …}` on `settingsSaveRunner` (latest wins); a failed save puts the switch back to `notifySaved` and flashes `Notify on escalation could not be saved`, and a load reply that lands after the user changed the switch (`notifyTouched`) is ignored. With it on, every raised alert also runs `notify.py TITLE REASON` on a `HelperRunner` of its own (`notifyRunners`; dropped when it exits, its reply unread, not stopped by a project switch).
  Dispatch (S3 3.1): the store also starts am runs. `openDispatch(card, cardMap)` takes a brd card as `Board.indexTree()` leaves it (or `"board"`) and its `{id: card}` map; it refuses without a project or while a start is in flight. Every opening sets `dispatchTargetLabel` to `Runs.dispatchLabel` (`Milestone "T"`, `Story "T" (milestone "M")`, `Subtask "T"`, `Whole board`; `""` while idle) and records the card map and the target's milestone card. A finished card or no card goes straight to `refused` (`dispatchErrorType` `Target`, `The card is <status>`); otherwise `dispatchTarget` is `Runs.dispatchPlan`'s result -- a milestone (`--milestone`), a story (`--story`), a subtask (`--card`) or the board --, `dispatchForm` (`{base, prefix, verify, parallelism, allowNoVerification}`) starts from `Runs.dispatchDefaults` with `runSettings` -- the current project's whole `get-run-settings` reply, `{}` until it lands and after a project switch -- and the Runs snapshot `runs` (the prefix is the newest snapshot run of the target's milestone, then `runSettings.prefixByMilestone[<milestone id>]`, then the prefix history, then the milestone's stem), and `dispatch-preview.py --defaults ROOT` (`dispatchDefaultsRunner`) fills `base` once per opening unless the user set it. `dispatchState` is `idle`, `previewing`, `ready`, `refused`, `starting`, `started` or `failed`. The form is checked with `Runs.validateDispatch` when that lookup replies and 400 ms after the last `setDispatchField(name, value)` (`dispatchDebounceTimer`): an invalid form is `refused` (`Form`, `dispatchErrors`) and launches nothing, a subtask is `ready` at once (am has no dry run for one card), and a milestone, a story or the board runs `dispatch-preview.py ROOT TARGET [--base-branch B] --branch-prefix P --max-concurrent N [--verify CMD]... [--allow-no-verification]` on `dispatchPreviewRunner` (latest wins; every change cancels it), giving `ready` with `dispatchPreview` (`Runs.previewSummary` for the target's level: a story reads `N subtasks · rooted on <branch>`, with no Integrate line) or `refused` with am's message verbatim (`The preview could not be read` when there is none); a story with nothing left is `refused` with `Nothing left to run` (`Empty`). A `StoryBlockedError`, from the preview or from Start, is `refused` -- never `failed`: no log fields, nothing saved -- with am's message and `dispatchSuggest` the story's milestone `{id, title}` (`null` when it is unknown); every other refusal leaves `dispatchSuggest` `null`, and a field change clears it. `retargetToMilestone()` works only from that refusal: it opens the dispatch afresh on the milestone and card map recorded at the story's opening (defaults, `--defaults` lookup, milestone preview) and returns false in any other state. `dispatchStart()` works only from `ready`: it runs `start-run.py ROOT TARGET` with the same options on a `HelperRunner` of its own (`dispatchStartRunners`, guard `""`, `madeFor` the project) that no preview, project switch or other Start stops; while `starting`, `setDispatchField`, `openDispatch` and `closeDispatch()` are refused. A successful start for the dispatch still open in its project sets `started`, `dispatchRunId` (`""` while am does not list the run yet) and `dispatchMessage`, re-snapshots and emits `dispatchStarted(runId)` (`null` when not visible yet); any other failed one sets `failed` with `dispatchError`, `dispatchErrorType`, `dispatchLog`, `dispatchLogTail` and `dispatchExitCode`. After any successful start the same runner writes `set-run-settings` for the project it was made in -- `verify`, `allowNoVerification`, `prefixHistory` (the prefix first, at most 20), `parallelism` and, for a story or milestone start whose milestone is known, `prefixByMilestone` (`{<milestone id>: prefix}`, the store's own `runSettings` merging it per milestone id at once), fixed when Start was pressed, never through `settingsSaveRunner` -- and flashes `Dispatch settings could not be saved` when that fails while the dispatch is still that start's. `closeDispatch()`, a project switch (even from `starting`) and closing the panel (except while `starting`) put the dispatch back to `idle`.

Other `ui/` pieces: `Navigator.qml` (screen switching; `openRun(id, from)` opens Run detail and records where Back goes in `runReturnMode`: from a card's RUNS row (`from` `"entry"`) the card stays open behind it and Back returns to it through `restoreCardFromRun()`, from the Runs list Back restores the list through `restoreRunsList()`; after a dispatch `openStartedRun(runId)` shows the Runs list and opens the run when the snapshot already lists it, else remembers it (`awaitedRunId`, `awaitedProject`) and flashes `Started — opening the run when it appears` -- `openAwaitedRun()`, called on every change of `app.runs.runs`, opens it once it is listed while the panel is still on that project's Runs list and forgets it anywhere else; a start with no run id flashes `Started — waiting for the run to appear`), `Shortcuts.qml` (key
events to store calls; Ctrl+1..6 follow the sidebar's order: Board, Graph,
Documents, Memories, Issues, Runs; `handleRunKey` makes a bare `p` / `r` / `c`
pause, resume or cancel the run on Run detail, and the cursor row on the Runs
list while its search is empty -- a refused key flashes `refusalOf`'s sentence,
`c` only opens the cancel confirmation; `handleDispatchKey` makes a bare `d`
open the dispatch dialog -- never start anything -- for the board list's cursor
card while its search is empty, or for the open card, and leaves the letter
alone without a project, while am is missing, or under a modal or the open
dropdown; `modalOpen()` is the one guard the chords, the run keys and `d` obey,
and an open dispatch counts as a modal; Escape closes the dispatch dialog (and
does nothing at all while its start is in flight), then the cancel
confirmation, then
dismisses the run toasts, before the dropdown; in the search field Escape
dismisses the toasts before it clears the search or closes the panel -- a toast
is not a modal, so it never blocks the chords or the run keys),
`theme/Theme.qml` (colours and fonts from the shell).

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
`RunToast` (the run toasts, oldest at the top: per toast `‼ Run needs you` or `✖ Run needs you` in `urgent` from `runGlyphs.js`, `<title> escalated` or `<title> died`, the reason, and Open / Dismiss `ActionButton`s; presentation only -- the owner passes `toasts` and handles `openRequested(key, runId)` and `dismissRequested(key)`, Open does not dismiss by itself; empty, it is hidden and 0 tall),
`DispatchDialog` (the dispatch modal: `Target   …` for the board, a milestone, a story or a subtask, the owner's `targetLabel` verbatim when it is given, such as `Story "<title>" (milestone "<title>")`; a form of Base and Prefix text fields, one Verify field per command with `+` and `✕`, a `run without any verification` `Chip` and a Parallel field; a Preview area showing exactly one of the refusal verbatim in `urgent` (with `Exit code N`, `Log: path` and the log tail's last six lines for a failed launch), a subtask's no-dry-run note with the owner's story and blocked-by lines, `Checking…`, or am's summary and integrate line; the cost warning in every state, the board's naming every open milestone; Cancel and `▶ Start run`, Start enabled only in `ready`. Presentation only, like `TypedConfirmDialog`: the owner passes RunStore's `dispatchState`, `dispatchTarget`, `dispatchForm`, `dispatchPreview`, error, log, tail and exit code, and maps `fieldEdited(name, value)` -- `value` the whole field, the whole list for `verify`, emitted only when it differs from `form`, so feeding the new form back echoes nothing -- `startRequested()` (a click on Start only; Return never starts) and `cancelRequested()` (Cancel, the backdrop, Escape in a field; none while starting) onto `setDispatchField`, `dispatchStart` and `closeDispatch`. The verify rows are counted, not listed, so typing never recreates the row under the cursor. Three owner-driven extras (S3 4.2): `targetChoices` / `targetChoice` draw a `ChipRow` of targets under the target line and emit `targetChosen(id)` for a chip other than the active one (busy while starting); a `refused` dialog with a `suggestion` `{id, title}` shows `Dispatch the milestone instead`, which emits `suggestionRequested()` and which Panel maps onto `retargetToMilestone()`; with `confirmFirst` the first click on Start only arms it (`armed`: Start reads `Confirm start` and `Click Confirm start to start this subtask.` shows), the second emits `startRequested()`, and any change of state, target, form, `confirmFirst` or visibility disarms it. Panel mounts it as `dispatchDialog`),
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

The run screens read `app.runs` and never import `core/stores`. `ui/screens/RunsScreen.qml` (Ctrl+6) lists `filteredRuns`, one row each (state glyph, short id, title, done/total, current phase, age; a dead run's age is since its last heartbeat, and an escalated run adds `escalationReason`), under the Needs attention / Live / Parked / All chips with their `runFilterCounts`. Above the list it shows the schema banner, `Run data is out of date` while `stale`, and the `watchWarning` line. Below it the footer reads `am <version> · schema N · watching` (or `not watching`) while the watch's hello is known (`amVersion`, `amSchema`; `am · schema N · …` when the hello named no version), and `am · watching` / `am · not watching` without one -- the version shows only with a known schema; it shows a non-empty `lastError` instead when `amStatus` is `error`, and is hidden when am is missing or the schema banner shows; a refused run key's flash replaces all of it while it lasts, even where the footer is otherwise hidden. With am missing the list shows `am is not installed or not on PATH`. Directly above the footer a `ToggleSwitch` reads `Notify on escalation` (`app.runs.notifyOnEscalation`, changed through `setNotifyOnEscalation`), shown also while am is missing: the setting is the project's. `ui/screens/RunDetailScreen.qml` (view mode `run`) shows the header (state, milestone, branch prefix, base, lease), the `runTree` story > subtask > phase > attempt tree plus the Integrate / Bases / Base rows (cards brd has closed are dimmed, never hidden), and the output pane: one attempt's `logsText`, labelled `snapshot <age> ago` plus `· last 200 lines` when it was cut, never a live tail, with a Refresh button and `logsError` in `urgent`. `CardDetailScreen` adds a RUNS section: every run `runsTouching` the card, newest first, with glyph, short id, title, phase and age, dimmed while stale. A click opens Run detail with `from` `"entry"`; a merged or canceled card still lists its runs, and nothing is listed while am is missing. Each of the three run surfaces carries a `RunControls` per run: a Runs row in its `ListRow.actions`, showing the buttons while the row has the cursor (hover moves the cursor) or a request is pending; Run detail under the header, always; a card's RUNS row in its `actions`, always, as whole-run controls (`Pause run`, the caption) on a story or subtask card. The still-waiting and error lines show whenever they apply. Pause and Resume call `app.runs.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` -- confirming a cancel is the owner's job, and no screen calls `control("cancel", …)`. Panel answers every `cancelRequested` with `app.runs.openCancel(runId)`: a third `TypedConfirmDialog`, `runCancelModal`, asks for the word `cancel`, says that Cancel is final (no resume, only a relaunch; cards keep their status; a phase in flight finishes first) and reads `Keep running` / `Cancel run`; it takes the focus while open and gives it back on close, Escape closes only it, and only its confirm (`confirmCancel()`) calls `control("cancel", …)` -- a run that changed under it keeps it open with the reason. On the Runs list (search empty) and Run detail a bare `p` / `r` / `c` does the same as the buttons; a refused key flashes its sentence for 3 s in the Runs footer (shown even beside the schema banner) or in Run detail's `runDetailFlash` line, the last line of the run's body. Panel mounts one `RunToast` (`runToast`) at the bottom right of its content, `z: 50` -- above the screens, below the dialogs, whose backdrop covers it: Dismiss calls `dismissToast(key)`; Open dismisses the toast, shows the Runs section and opens the run from there, so Back lands on the Runs list -- or, for a run that has left the snapshot, stays on the list and flashes `This run is no longer in the snapshot`. `BoardScreen` and `GraphScreen` draw a `RunMark` per card (plus `RunRollupBar` under a Board card's title) from `cardRunState` / `rollup`, except on cards `Board.isClosedStatus` reports closed (merged, canceled, archived) and while am is missing -- a visibility rule in the screens, never a run state. Every age on these screens is read against the clock once per snapshot (or logs reply): there is no timer.

Panel owns the dispatch (S3 4.2). Three entry points open `dispatchDialog`, never start anything, and are disabled (`am is not installed or not on PATH`) while am is missing: `CardDetailScreen`'s `▶ Dispatch` on every card (its `dispatchRequested(cardId)`; a finished card -- `done`, `merged`, `canceled` or `archived` -- opens a dialog already `refused` with `The card is <status>`, a story opens on its own target (`--story`, S7), and only a story am refuses as blocked offers its milestone, through the dialog's `Dispatch the milestone instead` (`dispatchSuggestion`, `RunStore.retargetToMilestone()`)), a bare `d` on the board list or a card (`Shortcuts.handleDispatchKey`), and the Runs toolbar's `▶ Start run` (`startRunButton`), which opens the whole board with a chip row of `Whole board` plus every milestone `Runs.dispatchPlan` offers. `root.openDispatch(target)` / `root.openRunsDispatch(target)` keep the card id (`dispatchCardId`; a refused plan does not carry it) and call `app.runs.openDispatch`; Panel composes a subtask's `Story   "<title>"` and `Blocked by: …` lines and binds `confirmFirst` to a subtask target, so a subtask's Start takes two clicks. The dialog takes the focus when it opens and gives it back when it closes -- never on a re-preview. Cancel, the backdrop, Escape and a project switch all close it (except while starting) and drop the chip row -- closing the panel does not: the store keeps an open dispatch, and the dialog and its chips are still there when the panel reopens; a chip or the milestone offer re-targets it. On `dispatchStarted` Panel closes it and calls `navi.openStartedRun(runId)`; a failed launch keeps it open with the failure.

Run state is a separate channel from brd status: a glyph plus a ring (`RunBadge`'s `Badge`, or a `StatusPips` ring), never colour alone. `ui/components/runGlyphs.js` is the one glyph source -- running ⟳, parked ⏸, escalated ‼, dead ✖, cancelled ⊘, done ✔ -- read by `RunBadge`, `RunRollupBar`, `PhaseTimeline`, `RunIndicator`, `RunMark`, `Sidebar` and the run screens. Escalated is drawn in the `urgent` token; merged purple and canceled red (`Board.statusColor`) are never used for a run state.

Refresh model: no timers while idle. A watch nudge costs one run read of that run (`runs-snapshot.py --run RUN`), or one list snapshot for a run the store does not know -- never a re-read per event. `RunStore`'s watch, its debounce, the liveness re-read (only while a run is running), the fallback poll, the toast expiry (`toastTimer`, only while a toast shows) and the dispatch debounce (`dispatchDebounceTimer`, only while a form change waits to be checked; closing the panel closes the dispatch unless a start is in flight) run only while the panel is open (`active`); closing it stops the watch process and every timer and starts nothing new (a one-shot snapshot or logs fetch already in flight runs to its end). Logs are fetched on demand, and `Pulse` animates a run badge only while it is running, visible and `active`.

Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
exit code), `text.js` (`matchesQuery`), `milestones.js` (the two helper
parsers, `agentMessage`, `formatElapsed`, the spec-list ordering and filter),
`brd-extras.js` (the `brd export` and `brd doc list` parsers, the issue
ordering/filtering and its wording, and `relativeTime` for a comment's age; the
export's `documents[]` carry every registered file's full content and are
dropped unread), `documents.js`'s `mergeRegistered` / `brdStateLabel` for
brd's registrations, and `runs.js`, the am run model: pure JS, never throws, and every input comes from `am`, never from a brd card. Normalizing: `normalizeRun` (an `am runs` row plus its `am status` data) returns copies, never am's objects: the scalars `id`, `repo_dir`, `started_at`, `base_branch`, `branch_prefix` and `workflow` prefer the `am runs` row, `status` and `milestone_id` the `am status` run; `lease` (`pid`, `host`, `heartbeat_at`, `accepting`, `live`; null when am gave none) and `requests` (`{command, requested_at, handled_at}`, in the order made); `tree.stories`, every story in am's order including the synthetic `integrate` and `bases`, each with `subtasks` as card-id strings; `tree.subtasks`, the subtasks of the real stories only, flattened in am's order, each with `story_id`; and `rows`, one per am row in am's order (am lists one per attempt; `attempt` is null when am's is not a number, as for a phase without attempts) as `{story_id, card_id, phase, attempt, status}` renamed from am's `story`, `subtask`, `phase`, `attempt` and `state`, with an Integrate resolver's rows (a synthetic story with a real card id) dropped. State: `runState` (running = `started` with a live lease, dead = `started` without one, parked = `stopped`, plus escalated, cancelled (`cancelled` or `canceled`) and done; anything else is `unknown`), `cardRunState` (the newest non-terminal run touching a card speaks for it, else the newest touching run, dimmed; its `state` is running / dead / parked / escalated / none) and `glyphStateOf` (an am story, subtask, phase, attempt or row status as a `runGlyphs.js` key: `cancelled` and `canceled` are both cancelled, the attempt outcome `ok` is done, and `gate_failed`, `schema_invalid` and `harness_error` are dead). Card mapping: `runsTouching` and `runTree`, through `run.milestone_id`, `stories[].card_id` and `subtasks[].card_id`, never through rows alone; the synthetic ids `integrate`, `bases` and `base-<story-id>` never match a card (Run detail shows them as rows of their own). Rollups and attention: `rollup` (counts the winning run's real subtasks, one each, by the subtask's own status; never rows), `attention` (escalated or dead: "Needs attention") and `escalationReason` (the first failed phase's detail, else its latest attempt detail, else `escalated at <phase>`; with no failed phase, `escalated at <phase>` of the last row with a phase whose status is `failed`, `escalated`, `gate_failed`, `schema_invalid` or `harness_error`, else `escalated`). Filter and search: `runFilterCounts`, `filterRuns`, `searchRuns`. Display text: `shortId`, `runTitle`, `runProgress`, `currentPhase`, `ageText`, `runAgeText`, `snapshotAgeText`, `errorText`. Logs: `logTail`, `defaultAttempt`, `attemptStatus`. Run state is never derived from brd status: `cardRunState` reads no brd status at all, and it is the screens that skip the cards `Board.isClosedStatus` reports closed (merged, canceled, archived);
Python: `core/backend/common`
(`json_line`, `safe_paths`, `atomic_write`, `frontmatter`, and `am_runs`, the
am calls and snapshot shared by the run helpers).
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
`core/backend/runs/` is the run-monitor backend. `runs-snapshot.py` has three modes: no argument runs `am runs --all-projects --limit 200` (every project's runs; the mode `RunStore` uses), `<project_root>` runs `am runs --repo-dir R --limit 200` (one project; `RunStore` does not use it), and `--run RUN` runs `am status RUN` alone, never with `--repo-dir`; any other argv is a `Usage` error (exit 2) and am is not run. The list modes then run `am status <id>` for every non-terminal run and the first 10 terminal ones (terminal: `done`, `escalated`, `stopped`, `cancelled` or `canceled`) in am's newest-first order. It prints exactly one JSON line on every path: `{ok, as_of_seq, store_id, runs: [{...am runs row, status: <am status data>}], data_dir}`, or for `--run` `{ok, run, as_of_seq, store_id, status, data_dir}` (`store_id` is `""` when am's is not a string; nothing in the UI shows `data_dir`), or an error: `Usage`, `AmMissing`, `AmBadOutput`, `SchemaMismatch` (am data without a non-negative integer `as_of_seq`: "the plugin needs the newer am") or `HelperError`; am's own `ok: false` envelope (`StoreBusyError`, `UnknownRunError`, `RepoDirError`, ...) is re-emitted unchanged. A failure stops at the failing am call, so a list is never partial; each am call gets 60 s. `runs-snapshot-all.py <root> [<root> ...]` prints `{ok: true, projects: [{root, ok, runs | error}], data_dir}` with one entry per root in argv order, each built by `common/am_runs` like the one-project mode; it runs up to 4 roots at once, gives each am call 60 s, and reports a root's failure (`RootMissing`, `AmMissing`, `AmTimeout`, `HelperError`, or am's or `am_runs`' own error) in that root's entry only; no roots, or a root that is empty or starts with `-`, is `Usage` (exit 2). `runs-watch.py <root> [<root> ...] [run_id ...] [--since-seq N]` (at least one root; an argument beginning with `/` is a root, any other non-flag argument is a run id, N is one or more ASCII digits, and no root, a second `--since-seq`, or an empty or other `-`-prefixed argument is `Usage`, exit 2; roots and run ids never reach am) is long-lived: it runs `am watch --all-projects --follow` (plus `--since-seq N` when given) and prints the first hello as `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}` (`am` and `storeId` are `""` when not strings, `cursorReset` is true only for a JSON true); every hello must carry an integer `schema` of 1 or more and a non-negative integer `head`, else `SchemaMismatch` (`am watch sent no head; the plugin needs the newer am.` for a missing `head`). It watches the argv run ids plus every run whose `run_upsert` `payload.repo_dir` names the same directory (realpath) as any root, from that `run_upsert` on. A nudge is a line for a watched run whose `event` is one of its `EVENTS` (`run_upsert`, `story_upsert`, `subtask_upsert`, `phase_upsert`, `attempt_upsert`, `lease_acquired`, `lease_taken_over`, `control_requested`, `control_handled`, `claim_conflict`), with a non-empty `run_id` and an integer `gseq` of 1 or more; every other line is ignored, and event contents are never forwarded. It prints at most one `{"changed": [{"run", "seq"}, ...]}` per 250 ms window, never empty, one entry per run carrying its highest `gseq` in the window, followed directly by `{"cursor": C}` (the highest kept `gseq` since the helper started). It ends with an `{ok: false, error}` line and exit 1 -- `SchemaMismatch`, `CorruptJournal` (am exited 3, unless its refusal is a `StoreBusyError`), `HelperError`, `AmMissing`, or am's own refusal envelope re-emitted unchanged -- and with exit 0 when am exits 0, on SIGINT or SIGTERM, or when its stdout closes. `RunStore` runs it as a plain `Process`, not through `HelperRunner`. `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. All three use only documented `am` commands, as argv lists, and never read am's SQLite database or its on-disk layout; am finds its journals under its own data dir, so the `XDG_DATA_HOME` it inherits matters.

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
  `test_am_shapes.py` does the same for the installed `am`: am runs
  hermetically (its own `HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME` under tmp),
  events are seeded only through am commands (a real story run on a scratch
  board, which escalates at its first agent phase because no agent CLI is
  reachable), and it pins the `am runs`, `am status` and `am watch` (one-shot
  and `--follow`) shapes `core/backend/runs/*` parses: the schema 2 journal
  line and hello key sets, `gseq`, `head`, `cursor_reset` and `store_id`, with
  the `--follow` hello's schema accepted as 1 or 2; skipped when `am` is absent.
  Its story tests (S7) build a real git repo and brd board under tmp
  and run am with a `PATH` holding only am, brd and git, so no agent CLI is
  reachable; they pin `am run --help` listing `--story`, the
  `am run --story --dry-run` payload (one level, no integrate), the
  `StoryBlockedError` refusal at dry run and at a detached start (which records
  no run), and `story_id` on a story run's `am runs` row. When am is present
  they fail, never skip, if `am run` lacks `--story` or if brd or git is
  absent: the panel's story dispatch needs an am with `--story`.
  `test_am_fixtures.py` pins the committed captures in
  `tests/fixtures/am/`: each level's exact key set (keys starting with `_`
  ignored), the run and attempt status vocabularies, no top-level `subtasks` in
  `am status` data, a `_note` on every capture naming agent-manager 0.2.0, one
  `store_id` shared by the captures, strictly increasing `gseq`, and an events
  page's `head` at least its last `gseq`. Its live check runs the `am` first on
  `PATH` with `HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME` under a scratch dir,
  never the user's data dir: it requires `as_of_seq` in `am runs` data and
  `head` in the first line of `am watch --all --follow`, failing with "the
  plugin needs the newer am" when either is missing, and checks any rows and
  the newest row's `am status` against the capture key sets exactly; it is
  skipped only when `am` is absent.
- `tests/fixtures/am/` holds real captured am payloads, captured 2026-10-08
  from agent-manager 0.2.0 on a scratch store, as each `_note` says:
  `runs.json`, five `status-*.json`, `watch-events.json`, `watch-hello.json`
  (`schema_1` the historical capture, `schema_2` the current one),
  `logs-attempt.json` and `events.json` (an `am events RUN` page with `head`);
  keys starting with `_` are annotations readers ignore.
  Tests of code that reads am output (`normalizeRun`, `logTail`, the `runs-*`
  helpers, `run-control.py`, `RunStore`'s list snapshot, run read, logs and
  watch handling) build their input from these fixtures; a hand-written am
  payload is used only for a synthetic edge case and is marked with a
  `synthetic:` comment. Tests of
  code that takes a normalized run may build it by hand. A test that edits a
  fixture edits a fresh copy. Python reads them with `json.load`, QML with
  `tests/helpers/amFixtures.js` (see `tests/helpers/README.md`).
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
