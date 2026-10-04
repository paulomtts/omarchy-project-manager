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
- `NavigationStore.qml` view mode, section, push/pop return positions, cursor, search, dropdown.
- `ProjectStore.qml` registry, selection, remembered project, DB watch path.
- `ProjectDeleteStore.qml` delete-project confirm/snapshot flow.
- `BoardStore.qml` cards, index, selection, board order, the issue map (`brd issue list`; an old brd without issues is just an empty map); owns the DB `FileView` and the 250ms `watchTimer` that debounces it, so a burst of writes costs one tree+issue+export fetch (`fetchBoard()` itself -- Refresh, a project switch -- stays immediate).
- `GraphStore.qml` the two graph models from the board (card roots and issue
  map, for each node's open-issue count): the milestone graph and the story
  graph (`graph.js`'s `graphModel` / `storyGraphModel`). `graphView`
  ("milestone", the default, or "story") picks which one `currentNodes` /
  `currentEdges` / `currentGroups` / `currentGroupEdges` (the story view's
  box-to-box dependency) -- and so the canvas, the arrow keys and
  Enter -- work on; `setGraphView` refuses anything else, so one of the two
  chips is always active, and keeps the selection on a node of the new view.
  Nothing resets it, so the choice is remembered for the session and survives a
  project switch (the cursor still clears with the project). Plus the graph
  cursor and its movement.
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

Other `ui/` pieces: `Navigator.qml` (screen switching), `Shortcuts.qml` (key
events to store calls; Ctrl+1..5 follow the sidebar's order: Board, Graph,
Documents, Memories, Issues), `theme/Theme.qml` (colours and fonts from the shell).

Not every process goes through `HelperRunner`: `listProc` (`brd projects`), `treeProc` (`brd tree`), `issueProc` (`brd issue list`), `exportProc` (`brd export`), `brdDocsProc` (`brd doc list`), `saveStateProc`, `resolveDbPathProc` and `deleteProc` stay plain `Process` objects because they run the `brd` CLI or are fire-and-forget/single-owner with their own exit handling. `HelperRunner.run()` SIGTERMs a previous run of the same helper instead of letting it finish and dropping its reply (reachable for list-docs/list-memories refetches, and a set-doc-tag started in another project mid-flight); helpers write atomically, so at worst a stray `docs/.tmp-*` remains.

## Shared components (`ui/components`) - reuse before writing a second copy

`ThemedText` (text), `ActionButton` (bordered button), `Badge` (pill),
`Breadcrumbs` (the toolbar's location trail; `Navigator.crumbs` builds the list
and `Navigator.activateCrumb(index)` acts on a click, so the component stays
presentational),
`Chip` and `ChipRow` (filter chips), `CommentList` (the read-only brd comments
of one entity, used by the card detail and the issue detail),
`ModalCard` (dimmed backdrop and card),
`TypedConfirmDialog`, `ListRow` (hover / keyboard cursor / reveal),
`ListStatus` (loading/error/empty), `FilterableList`, `TextAreaBox`,
`TagPicker`, `NewMemoryDialog`, `NewMilestoneDialog` (the from-spec modal),
`MilestoneJobIndicator` (the toolbar strip while a milestone job runs, and its
result), `StatusPips` (one status circle per subtask on a story node, the
overflow as a `+N`; its single pulse animation runs only while the row is
visible AND holds an in-progress pip, so an idle graph animates nothing),
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
`RunIndicator` (the toolbar's run strip beside `MilestoneJobIndicator`: one `ActionButton` per non-zero `running` / `parked` / `attention` prop, written glyph-then-count with no space such as `⟳2 ⏸1 ‼1`, glyphs from `runGlyphs.js` and counts clamped by its `countOf`; attention in `urgent`; hidden when all three are 0; static, no animation; presentation only -- the owner computes the counts, and a click emits `filterRequested(filter)` with `"live"`, `"parked"` or `"attention"` from the Runs filter set `attention` / `live` / `parked` / `all`, `all` being emitted by no segment),
`Sidebar`, and the views
`DocumentsView`, `MemoriesView`, `MemoryNoteView`, `GraphView`.
`Sidebar`'s five nav rows (Board, Graph, Documents, Memories, Issues) each lead with an
icon glyph drawn in the theme's font; `tests/architecture/test_icon_glyphs.py`
checks every glyph literal in `ui/` and `vendor/` against the installed Nerd
Fonts, because a glyph the font does not have renders as an empty box.
`ui/screens/DocumentsToolbar.qml` is the Documents half of the panel's fixed
toolbar - the category chips of the list, and the path and type picker of an
open document - so only the document body scrolls.
Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
exit code), `text.js` (`matchesQuery`), `milestones.js` (the two helper
parsers, `agentMessage`, `formatElapsed`, the spec-list ordering and filter),
`brd-extras.js` (the `brd export` and `brd doc list` parsers, the issue
ordering/filtering and its wording, and `relativeTime` for a comment's age; the
export's `documents[]` carry every registered file's full content and are
dropped unread), and `documents.js`'s `mergeRegistered` / `brdStateLabel` for
brd's registrations;
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
`core/backend/runs/` is the run-monitor backend: `runs-snapshot.py` runs `am runs`, then `am status` for every non-terminal run and the latest 10 terminal ones, and prints one JSON line (`{ok, runs, data_dir}` or an error).

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
