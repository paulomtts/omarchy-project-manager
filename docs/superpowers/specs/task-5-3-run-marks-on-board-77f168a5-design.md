# 5.3 Run marks on Board, Graph and card detail (card 77f168a5)

Narrows `2026-10-03-am-run-monitor-design.md` § "On existing screens (additions only)" to one subtask. Parent: 8bb02694 "Runs screens and integration". Builds on the 5.2 worktree state (branch `mon/task-5-2-rundetailscreen-a3fe1e6a`, 51000ac). This worktree already holds that state. Paths below are relative to the worktree root.

## Scope

In scope:

1. **Board.** Each `BoardCard` in `ui/screens/BoardScreen.qml` that a run touches gets a `UI.RunBadge`. On a subtask (depth >= 2) the badge shows the glyph plus the current phase. On a milestone or story (depth 0/1) it shows `counts` from `Runs.rollup`. Milestone and story cards also get a `UI.RunRollupBar` under the title.
2. **Graph.** Story and milestone nodes in `ui/components/GraphView.qml` (milestoneDelegate, storyDelegate) get a `RunBadge` and a `RunRollupBar` under the node title. The story node's `StatusPips` rings the pip of each subtask whose run state is live `running`.
3. **StatusPips.** Add one new optional input, `ringedIds` (array of pip ids, default `[]`). A ringed pip gets a border on the existing pip Rectangle; this adds no new rectangle and no new `radius: height / 2`. With the default, the output is unchanged.
4. **Card detail.** `ui/screens/CardDetailScreen.qml` gets a **RUNS** `PanelSectionHeader` and one row per run that touches the card, newest first. Each row shows the state glyph, `Runs.runTitle` / `shortId`, `Runs.currentPhase` and `Runs.runAgeText`. Clicking a row calls `navigator.openRun(id)`. It reuses `UI.ListRow`, `ThemedText` and `RunBadge` and adds no new pill.
5. **Domain helper.** Add `Runs.runsTouching(runs, cardId)` to `core/domain/runs.js`. It is a public wrapper over `_touches` that returns the runs in input order and `[]` for a bad id or bad input. The file has no public helper that does this today.
6. **Return path.** Run detail opened from card detail goes Back to that card, not to the Runs list. This mirrors `issueReturnMode`:
   - Add `runReturnMode: "runs" | "entry"` on NavigationStore.
   - `openRun` takes an optional `from`. It sets `runReturnMode = from === "entry" ? "entry" : "runs"` on every call (so a Runs-list open always resets it). With `from === "entry"` it does not `pushReturn`.
   - `goBack` in `"run"` mode with `runReturnMode === "entry"` clears `selectedRunId`, restores `viewMode = "entry"` on the same `selectedCardId` (cursor 0, scroll top) and resets the mode to `"runs"`.
   - The existing Runs-list path is unchanged.

Out of scope: RunIndicator/toolbar, docs (5.4), RunsScreen/sidebar (5.1), RunDetailScreen body (5.2), `Board.subtreeCounts` and the existing "n/m done" text (both unchanged), and milestone group boxes in the story-mode graph. Keyboard cursor reach of the RUNS rows is also out: `board.detailLinkList` stays brd-only and RUNS rows are mouse-activated (`rowIndex: -1`). This is flagged as an open question below.

## Observable behaviour

- **Data flow and layers.** Screens read `app.runs.runs`, `app.runs.amStatus` and `app.runs.stale` via `app`. GraphScreen computes the marks and passes them to GraphView as new props, because GraphView has no `app`:
  - `runMarks`: map cardId → `cardRunState`.
  - `runRollups`: map cardId → `rollup`.
  - `runRinged`: array of subtask ids.

  No file under `ui/screens/**` or `ui/components/**` imports `core/stores`. Screens may import `core/domain/runs.js`.
- **Run state comes from am only.** Use `Runs.cardRunState(runs, card.id)` and `Runs.rollup(runs, card)`, never brd status.
  - A card with `state === "none"` and a zero rollup total shows no badge and no bar. `RunRollupBar` hides itself at `total === 0`.
  - `cardRunState().state` is only `running | dead | parked | escalated | none`; it is never `done` or `cancelled`. A subtask whose winning run is finished therefore shows no badge. Only parked/escalated runs are "dimmed" winners among subtasks (a parent in a finished run still gets a counts badge from `rollup`, whose `done` count is non-zero).
  - A `dimmed` winner renders the badge with reduced opacity and does not pulse (`active: false`). `RunBadge` binds its own `opacity` to its Pulse, so a screen must not assign `opacity` on the `RunBadge` itself; apply dimming (dimmed or `stale`) through an enclosing wrapper Item's `opacity` (as `RunsScreen` does for `stale`).
- **brd-status gate (visibility only).** Cards whose brd status is `merged` or `canceled` (or `archived`, if brd reports it) get no badge and no rollup bar on Board or Graph. `cardRunState` and `rollup` take no brd status (`(runs, cardId)` / `(runs, card)`), so the screen must apply this gate. It decides visibility only and is never used to derive a run state. The Card detail RUNS list is not gated, because it is history.
- **am missing / stale.**
  - With `amStatus === "missing"`: no badges, no bars, no rings, and no RUNS section.
  - With `stale === true`: marks are drawn dimmed.
  - In both cases the screens render normally otherwise.
- **Visual channel.**
  - States are shown with a glyph from `runGlyphs.js` plus the ring. Colour is never the only signal.
  - Escalated uses `theme.urgent`. Neither `#9b72cf` nor `#d9534f` is used.
  - There is no new animation loop. `RunBadge` uses its own Pulse, which runs only when the badge is visible and `active`. StatusPips' pulse is unchanged.
- **RUNS section.**
  - The header is hidden when no run touches the card.
  - Clicking a row whose run id has vanished does nothing, because `openRun` returns early.
  - Back from that Run detail lands on the same card.
  - While in Run detail opened from a card, `nav.section` is `"runs"` (sidebar and the first crumb read Runs); clicking that crumb calls `goBack()` and so also lands on the card. This is accepted, not changed here.
  - Back again from the card follows the card's original return (list or graph), which this card does not change.
- **Stable objectNames.**
  - Reused: `runBadge`, `runBadgeText`, `runRollupBar`, `runRollupRunning/Parked/Escalated/Done/Pending`.
  - New: `cardRunsHeader`, `cardRunRow<n>`, and `statusPip<id>` (unchanged) with a readable `ringed` property.

## Error paths

- Malformed or empty `runs`, a non-object card, or an unknown id: the helpers return `none` / zero / `[]`, and the screens draw nothing extra.
- A card that a run touches only through `rows` (not its tree) is not "touched", per `_touches`.
- A missing `ringedIds` or a non-array value is treated as `[]`.

## Tests (written first)

Placement follows docs/architecture.md "Tests": by layer, mirroring source paths.

| Test | File | Tier (per rule) |
|---|---|---|
| `runsTouching`: milestone/story/subtask match, rows-only does not match, input order kept, bad id/input → `[]` | tests/core/domain/tst_runs.qml (extend) | pure domain helper |
| StatusPips: default draws no ring; `ringedIds` rings only listed pips; existing pulse cases unchanged | tests/ui/components/tst_status_pips.qml (extend) | shared component |
| GraphView: `runMarks`/`runRollups`/`runRinged` props draw a badge and bar on story and milestone nodes; empty props draw none | tests/ui/tst_graph_view.qml (extend, at its existing location) | shared component test as it sits today |
| BoardScreen: subtask card shows glyph+phase; story/milestone card shows counts and bar; untouched card shows none; merged/canceled card shows none even when touched; dimmed winner dimmed and not pulsing; `amStatus: missing` hides all; `stale` dims | tests/ui/screens/tst_board_screen.qml (extend) | screen |
| GraphScreen: passes the run props to GraphView from `app.runs`; the gate and `missing` apply | tests/ui/screens/tst_graph_screen.qml (extend) | screen |
| CardDetailScreen: RUNS header and rows (state, phase, age) for touching runs; hidden when none or am missing; row click calls `navigator.openRun(id, "entry")` | tests/ui/screens/tst_card_detail_screen.qml (extend) | screen |
| Navigator: `openRun(id, "entry")` sets `runReturnMode`, skips `pushReturn`; `goBack` returns to the card; default path still restores the Runs list | tests/ui/tst_navigator.qml (extend) | cross-screen navigation (existing location) |
| Flow: board → card → run row → Run detail → Back lands on the card; badges on the board reflect the run | tests/ui/tst_board_flow.qml (extend) | cross-screen user flow |
| Flow: graph node shows badge, rollup and ringed pip for a running subtask | tests/ui/tst_graph_flow.qml (extend) | cross-screen user flow |
| Layer, duplicate and glyph rules still pass (no store import in screens/components, no second `radius: height / 2`, `bordered: true` or `CursorSurface {`, glyphs valid) | tests/architecture/test_layers.py, test_icon_glyphs.py (run, not changed) | architecture |

## Open questions / notes for the plan stage

- Keyboard reach of the RUNS rows would mean `Navigator.currentList()` appending run rows for `"entry"`, plus an `activateCursor` branch. That goes beyond "minimal", so it is deferred unless the plan stage finds it cheap.
- The upstream exploration summary was truncated at 8000 characters, mid-way through the test-placement rule. The rest of that rule was taken from docs/architecture.md and the existing tests tree, not guessed.
- The "skip merged/canceled/archived" rule came from the exploration findings, but it does not appear in `2026-10-03-am-run-monitor-design.md`. Confirm it before implementing. No `archived` status exists in core/.
