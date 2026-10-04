# 4.2 RunControls, wired into the run screens (card 1c268d85)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2,
"the parent" below): "Control actions" (lines 29-53), "Architecture" bullet 5
(lines 75-77), "UI" (lines 79-107), "Errors" (lines 138-146). Parent story
f03629a7 ("Control store and UI"). Everything this card reads is already on this
branch: `Runs.controls` / `Runs.controlError` (card adff6c85) and the store's
control API (card c1f23024, spec `4-1-runstore-control-c1f23024.md`).

This card is the buttons and the lines under them. The cancel confirmation and
the keys are card 4.3 (b4bc1521); toasts and desktop alerts are card 4.4
(22153f5f).

## Starting point

- `core/domain/runs.js` `controls(run)` (lines ~660-690) returns `{pause, resume,
  cancel}`, each a fresh `{enabled, reason}`, `reason` `""` when enabled. It
  knows nothing about pending requests.
- `core/stores/RunStore.qml` exposes `control(action, runId)` → bool (line 445;
  it refuses a disabled action, a run already pending, an unknown run, no
  project; **confirming a cancel is the caller's job**), `pending` `{runId:
  action}` (line 65), `stillWaiting` `{runId: true}` (line 66),
  `stillWaitingText` (line 67), `lastControlError` and `lastControlErrorRunId`
  (lines 68-69). The store's `lastError` is the snapshot banner, **not** the
  control error (4.1 spec, D1). The card text's "inline error from lastError"
  means `lastControlError`, shown only under the run named by
  `lastControlErrorRunId`.
- `ui/components/ActionButton.qml` wraps the shell `Button` (props `theme`,
  `tone` `"normal"|"danger"`, `text`, `iconText`, `tooltipText`, `enabled`;
  dimmed to 0.5 while disabled). The real shell Button shows `tooltipText` only
  while hovered (`/usr/share/omarchy/shell/Ui/Button.qml` line 131); the test
  stub `tests/stubs/qs/Ui/Button.qml` has plain props and a MouseArea that
  emits `clicked` only while enabled.
- `ui/components/runGlyphs.js` holds the one glyph per run state (plain BMP,
  never Nerd Font code points): parked `⏸`, cancelled `⊘`, running `⟳`. The
  parent's mock (lines 84-90) draws Pause as `⏸` and Cancel as `⊘`.
- `ui/components/ListRow.qml`: the row's `MouseArea` (lines 44-50) is declared
  **after** the content column, so it is stacked above every declared child. A
  button placed in a row's content today never receives a real click: the
  row's MouseArea takes it and fires `activated` (which opens the run). See D2.
- Run rows: `ui/screens/RunsScreen.qml` `RunRow` (lines 115-220, a `UI.ListRow`,
  `objectName: "runRow" + index`, run read back from `filteredRuns[index]`);
  `ui/screens/CardDetailScreen.qml` `CardRunRow` (lines 187-241, a `UI.ListRow`
  with `index` -1, `objectName: "cardRunRow" + modelData`); Run detail's header
  in `runDetailBody` (`ui/screens/RunDetailScreen.qml` lines ~159-200).
- Card kind: `Board.kindLabel(card.depth)` (`core/domain/board.js` line 78):
  depth 0 Milestone, 1 Story, 2+ Subtask.

## Scope

In scope:

- New `ui/components/RunControls.qml` and its test
  `tests/ui/components/tst_run_controls.qml`.
- `ui/components/ListRow.qml`: a new `actions` slot (D2) and its tests in
  `tests/ui/components/tst_list_row.qml` (appended).
- Wiring into `RunsScreen.qml`, `RunDetailScreen.qml`, `CardDetailScreen.qml`,
  with tests appended to `tests/ui/screens/tst_runs_screen.qml`,
  `tst_run_detail_screen.qml`, `tst_card_detail_screen.qml`, and one flow in
  `tests/ui/tst_runs_flow.qml`.
- `docs/architecture.md`: `RunControls` in the "Shared components" list (lines
  103-135), the `ListRow` entry mentions `actions`, and the run screens
  paragraph (line 145) says where the controls appear.

### Out of scope

- The cancel `TypedConfirmDialog` and `p` / `r` / `c` in `Shortcuts.qml`, and
  flashing a disabled action's reason in the footer (parent lines 92-104):
  card 4.3. This card **never calls `control("cancel", …)`**; the Cancel
  button only asks for a cancel (D3).
- `RunToast`, `newAlerts`, `notify.py`, "Notify on escalation": card 4.4.
- The Resume confirm step that shows the verify set about to be reused, and
  the verify-fields form when none is stored (parent lines 34, 49-52). Resume
  calls `control("resume", id)` straight away; when the store refuses for a
  missing verify set, its sentence shows as the inline error like any other.
- "am failed to run + stderr tail on expand" and "the raw message one click
  away" (parent lines 61, 143): the store keeps only the sentence, so the line
  shows the sentence. No expand.
- Showing a control error for a run that has vanished from the snapshot (parent
  line 145): its row is gone, so the line has nowhere to sit. Not shown here.
- Any change to `RunStore.qml`, `runs.js`, `App.qml`, backend helpers.
- A dismiss button for the error line: the store clears it on the next
  `control()` and on a project switch.

## Decisions

- **D1. RunControls is presentation only.** Like `RunIndicator` (its header,
  docs/architecture.md line 132), it imports no store. The owner passes the run
  and the store-derived facts as props, and the component emits
  `actionRequested(action)`. `ui/` may import `core/domain/runs.js` and
  `runGlyphs.js`. This keeps it testable with plain objects and keeps
  `tests/architecture` green.
- **D2. `ListRow` gains an `actions` slot stacked above its MouseArea.** A
  second content area (`property alias actions: <column>.data`) laid out
  directly under the declared content, inside the same margins, and stacked
  above the row's MouseArea so its buttons receive clicks and the row does not
  fire `activated` for them. A click on the ordinary content still activates
  the row. With nothing in `actions` (every existing row), the row's
  `implicitHeight` and the content column's geometry are exactly as today.
  This is a change to a shared component, not a second row component
  (architecture: reuse before writing a second copy, docs/architecture.md line
  103).
- **D3. Cancel only asks.** The parent requires a typed confirmation before
  cancel (line 35, lines 92-99) and the store leaves confirming to the caller.
  Until 4.3 lands the dialog, each screen re-emits a Cancel click as its own
  new signal `cancelRequested(string runId)`, which nothing in the panel
  handles yet. Pause and Resume go straight to `app.runs.control(action,
  run.id)` (parent line 33: no confirmation; line 34's confirm step is out of
  scope above).
- **D4. Pause and Resume share one slot.** The mock shows `[⏸ Pause] [⊘ Cancel]`
  on a running run (line 85) and no Resume. So at most one of Pause and Resume
  shows: Pause on a running run, Resume on a parked, escalated or dead run.
  A pending pause or resume keeps its own button in that slot until it
  settles, whatever the state.
- **D5. Finished runs show no buttons.** A `done` or `cancelled` run, a run with
  an unknown state and a null run show no buttons and no caption (every action
  is disabled with "The run has finished" or similar, and three dead buttons
  per finished row are noise). Integrate is **not** a finished state: a running
  run in Integrate shows Pause and Cancel disabled with
  "Integrate is running; it cannot be paused or cancelled" (parent lines
  44-46).
- **D6. Glyphs come from `runGlyphs.js`.** Pause's icon is `glyphOf("parked")`
  (`⏸`), Resume's `glyphOf("running")` (`⟳`), Cancel's `glyphOf("cancelled")`
  (`⊘`), matching the mock. No new glyph literal enters `ui/`, so
  `tests/architecture/test_icon_glyphs.py` has nothing new to check.
- **D7. On the Runs screen the buttons show on the hovered or selected row.**
  Parent line 82: "Runs row, hover or selected". Hovering a row already moves
  the cursor to it (`navigator.hoverCursor`), so "the row has the cursor"
  covers both. The buttons also stay while a request is pending for that row
  (the mock's "After Pause", lines 88-90). The error and still-waiting lines
  show whenever they apply, cursor or not. On Run detail and in the card
  detail's Runs section the buttons always show (subject to D5).
- **D8. A disabled button's reason is also written out.** In the real shell a
  disabled `Button` gets no hover: `enabled: false` propagates to its
  `MouseArea` (`/usr/share/omarchy/shell/Ui/Button.qml` lines 131, 193-196), so
  its tooltip never appears. The card asks for "disabled with the reason as
  tooltip", so `tooltipText` still carries the reason (and 4.3's footer flash
  can reuse it), but RunControls also shows a caption line with the reasons of
  its visible disabled buttons, so the Integrate case (parent lines 44-46) is
  readable without hovering.

## Behaviour

### `ui/components/RunControls.qml`

A `Column`. Props (all with the defaults shown):

| prop | type | meaning |
|---|---|---|
| `theme` | var, `T.Theme {}` | colours and font |
| `run` | var, `null` | one normalised run, as `RunStore.runs` holds them |
| `pendingAction` | string, `""` | `""`, or the action pending for this run (`pending[run.id]`) |
| `waiting` | bool, `false` | the pending request is 30 s or more old (`stillWaiting[run.id] === true`) |
| `waitingText` | string, `""` | the store's `stillWaitingText` |
| `errorText` | string, `""` | the control error for **this** run, `""` otherwise |
| `wholeRun` | bool, `false` | the controls sit on a story or subtask card |
| `showButtons` | bool, `true` | the owner's hover/selected rule (D7) |

Signal: `actionRequested(string action)`, `action` exactly `"pause"`,
`"resume"` or `"cancel"`, emitted on a click of an enabled button and never
for a disabled one.

Children, by `objectName`:

- `runControlPause`, `runControlResume`, `runControlCancel`: three
  `UI.ActionButton`s in one row, in that order. Cancel has `tone: "danger"`.
- `runControlCaption`: a caption `UI.ThemedText`, exactly
  `applies to the whole run`.
- `runControlReason`: a caption `UI.ThemedText` in `theme.dim`, word-wrapped
  (D8).
- `runControlWaiting`: a caption `UI.ThemedText` in `theme.dim`, text
  `waitingText`.
- `runControlError`: a caption `UI.ThemedText` in `theme.urgent`, word-wrapped,
  text `errorText`.

Let `state = Runs.runState(run)`, `c = Runs.controls(run)`,
`actionable = state` is one of `running`, `parked`, `escalated`, `dead`.

**Visibility.**

- The button row and the caption show exactly when `showButtons && actionable`,
  or when `pendingAction !== ""` (a pending request always shows its button,
  D7). The caption additionally needs `wholeRun`.
- Within the button row: Pause shows when `pendingAction === "pause"`, or
  `pendingAction` is not `"resume"` and `state === "running"`. Resume shows when
  `pendingAction === "resume"`, or `pendingAction` is not `"pause"` and `state`
  is `parked`, `escalated` or `dead`. Never both (D4). Cancel shows whenever
  the button row shows.
- `runControlWaiting` shows exactly when `waiting && pendingAction !== "" &&
  waitingText !== ""`.
- `runControlError` shows exactly when `errorText !== ""`.
- `runControlReason` shows exactly when the button row shows,
  `pendingAction === ""`, and at least one visible button is disabled. Its text
  is the distinct non-empty `reason`s of the visible disabled buttons, in button
  order, joined by ` · ` (Integrate on a running run gives the one sentence
  once).
- With nothing visible the component's height is 0 (a finished run's row is as
  tall as today).

**Labels** (`text`):

| | normal | `wholeRun` | while that action is pending |
|---|---|---|---|
| Pause | `Pause` | `Pause run` | `Pause requested…` |
| Resume | `Resume` | `Resume run` | `Resume requested…` |
| Cancel | `Cancel` | `Cancel run` | `Cancel requested…` |

The ellipsis is the single character `…` (U+2026), as in the parent mock (line
90). `iconText` is per D6 and does not change while pending.

**Enabled and tooltip.**

- While `pendingAction !== ""`: every button is disabled; the pending one's
  `tooltipText` is `Waiting for the run to act on the request`, the others'
  is `A request for this run is pending` (parent lines 42-43: no double fires).
- Otherwise each button's `enabled` is `c[action].enabled` and its
  `tooltipText` is `c[action].reason` (`""` when enabled). So the Integrate
  reason, "Only a running run can be paused", etc. are the tooltips verbatim.

### `ListRow.actions` (D2)

- `actions` is a list slot; items declared into it are laid out in a column
  under the content, inside `contentMargin`, separated from the content by the
  content column's spacing only when at least one action item is visible.
- `implicitHeight` = content + visible actions (+ that spacing) +
  `Style.spacing.rowPaddingX`. With no visible action item it is exactly
  `content.implicitHeight + Style.spacing.rowPaddingX` (today's value, line 29).
- A real mouse click on a button in `actions` reaches the button and does **not**
  emit the row's `activated`. A click on the content area still emits
  `activated`. Hover over the row still emits `hovered(index)` on entry.

### Runs screen (`RunsScreen.qml`)

- Each `RunRow` puts a `UI.RunControls` (`objectName: "runRowControls" +
  index`) in its `actions`, with `run: row.run`, `pendingAction:
  app.runs.pending[run.id] || ""`, `waiting: app.runs.stillWaiting[run.id] ===
  true`, `waitingText: app.runs.stillWaitingText`, `errorText:
  app.runs.lastControlErrorRunId === run.id ? app.runs.lastControlError : ""`,
  `wholeRun: false`, `showButtons: row.hasCursor`. Lookups use own-property
  checks so a run id such as `constructor` reads as not pending.
- `actionRequested("pause"|"resume")` calls `app.runs.control(action,
  run.id)`. `actionRequested("cancel")` emits the screen's new
  `cancelRequested(string runId)`.
- A stale run list (`app.runs.stale`) keeps the row's existing half opacity;
  the buttons are not separately disabled (the store's `control()` still
  guards).

### Run detail (`RunDetailScreen.qml`)

- A `UI.RunControls` with `objectName: "runDetailControls"` in `runDetailBody`,
  directly after `runDetailReason` and before the story tree, bound the same
  way to `screen.run`, `showButtons: true`, `wholeRun: false`.
- The same forwarding: pause/resume to `app.runs.control`, cancel to the
  screen's new `cancelRequested(string runId)`.

### Card detail (`CardDetailScreen.qml`)

- Each `CardRunRow` puts a `UI.RunControls` (`objectName: "cardRunControls" +
  modelData`) in its `actions`, bound to `runRow.run`, `showButtons: true`,
  `wholeRun: card.depth >= 1` (a story or subtask card, `Board.kindLabel`
  `Story`/`Subtask`; a milestone card shows the plain labels and no caption).
- The same forwarding, to `detailCard.cancelRequested(string runId)`.
- A finished run touching the card shows no controls (D5), so a merged card's
  run history looks as today.

## Errors and edge cases

| case | behaviour |
|---|---|
| `run` is null (row index past the list during a model change) | nothing visible, no TypeError in the output (`tests/run.sh` fails on one) |
| the store refuses `control()` (returns false) | nothing changes in the UI; buttons keep their state |
| `ok:false` reply | the store clears `pending` and sets the error; the row's buttons re-enable and `runControlError` shows the sentence (parent line 142) |
| error belongs to another run | not shown under this run |
| pending > 30 s | `runControlWaiting` shows `still waiting — the run may be between phases or dead`; on a dead run Resume becomes available once the request settles (parent line 144) |
| Integrate | Pause and Cancel visible, disabled, tooltip = the Integrate reason, and `runControlReason` shows it once; Resume hidden |
| project switch | the store empties pending and the error; the controls follow by binding |

## Tests

All written first. `bash tests/run.sh` runs pytest, then every `tst_*.qml`
through qmltestrunner with `tests/stubs` (offscreen); it fails on any
TypeError, ReferenceError, "Unable to assign" or "is not a function" in the
output. Tooltips are asserted as the `tooltipText` property: the stub Button
does not render hover tooltips.

**Component tier, `tests/ui/components/tst_run_controls.qml`** (new). The
component is presentation only, so it is tested with plain run objects, no
store. Runs are built like `tst_run_detail_screen.qml`'s `run(id, status,
live, …)` helper, with a lease `accepting` flag.

1. Running run: Pause and Cancel visible, enabled, labels `Pause` / `Cancel`,
   `iconText` `⏸` / `⊘`, empty tooltips; Resume hidden; Cancel tone `danger`.
2. Parked, escalated and dead runs: Resume (`⟳`) and Cancel visible and
   enabled; Pause hidden.
3. Running run in Integrate (`lease.accepting: false`): Pause and Cancel
   disabled, both tooltips exactly `Integrate is running; it cannot be paused
   or cancelled`; `runControlReason` shows that sentence exactly once.
   An escalated run in Integrate: Resume enabled, Cancel disabled, the reason
   line is the Integrate sentence.
4. Done, cancelled, unknown state and null run: buttons and caption hidden,
   component height 0.
5. `wholeRun: true`: labels `Pause run`, `Resume run`, `Cancel run`, caption
   visible with the exact text; `wholeRun: false` hides the caption.
6. `pendingAction: "pause"` on a running run: Pause reads `Pause requested…`,
   all buttons disabled, the tooltips are the two pending sentences, and
   `runControlReason` is hidden. Same for
   `"cancel"` (`Cancel requested…`) and `"resume"` on a dead run.
   A running run with everything enabled hides `runControlReason`.
7. Pending pause on a run already shown as parked: the Pause slot shows Pause
   (`Pause requested…`), not Resume (D4).
8. `showButtons: false` hides the buttons and caption, but a pending request
   shows its button anyway; the error line still shows.
9. Clicking (mouseClick) an enabled Pause, Resume, Cancel emits
   `actionRequested` once with `"pause"`, `"resume"`, `"cancel"`. Clicking a
   disabled button emits nothing.
10. `runControlWaiting` shows the text only with `waiting` and a pending
    action; `runControlError` shows `errorText` in `theme.urgent` and hides
    when it is `""`.

**Component tier, `tests/ui/components/tst_list_row.qml`** (appended). D2 is
a shared component's behaviour, tested on the component:

11. A row with nothing in `actions` keeps `implicitHeight === label +
    rowPaddingX` (the existing test stays unchanged and passing).
12. A row with an `ActionButton` in `actions`: `implicitHeight` grows by the
    button's height plus the spacing; a mouseClick on the button emits its
    `clicked` once and the row's `activated` zero times; a mouseClick on the
    content label still emits `activated` once.

**Screen tier.** Each screen's binding to the store and its forwarding:

`tests/ui/screens/tst_runs_screen.qml` (the stub runs object gains `pending`,
`stillWaiting`, `stillWaitingText`, `lastControlError`,
`lastControlErrorRunId` and a recording `control(action, id)` returning true):

13. The buttons of a row show only while it has the cursor
    (`nav.cursorIndex`), and stay shown while that run is pending.
14. Clicking Pause on a running row calls `control("pause", <id>)` exactly
    once and does not open the run (`navigator.opened` stays `""`); Resume on a
    parked row calls `control("resume", <id>)`.
15. Clicking Cancel emits the screen's `cancelRequested(<id>)` once and calls
    `control` zero times.
16. `lastControlError` with `lastControlErrorRunId` of row 1 shows under row 1
    only; `stillWaiting` for a pending run shows the waiting line under it.

`tests/ui/screens/tst_run_detail_screen.qml`:

17. `runDetailControls` shows Pause and Cancel for a running run without any
    hover, Resume for a parked one; Pause click calls `control("pause", id)`;
    Cancel emits `cancelRequested(id)`.
18. A done run shows no buttons.

`tests/ui/screens/tst_card_detail_screen.qml` (real `App`, runs set with the
existing `withRuns(s)` helper, `control` observed through
`app.runs.controlRunners`):

19. On a story card (`s1`), the running run's row shows `Pause run` /
    `Cancel run` and the caption; the done run's row shows no controls.
20. On a milestone card (`m1`, depth 0), the labels are plain and there is no
    caption.
21. Clicking `Pause run` starts a request (`app.runs.pending[id] === "pause"`,
    one control runner) and does not navigate to Run detail
    (`app.nav.viewMode` stays `"entry"`). `RunStore.control()` refuses with no
    project (`store.project === ""`), and `withRuns(s)` sets only `runs`, so the
    test must give the store a project first (as `tst_runs_flow.qml` does) or
    the request is silently refused. The `mkRun` runs carry no `workflow`
    field, so a resume here would take the settings-read step; the test uses
    Pause.

**Flow tier, `tests/ui/tst_runs_flow.qml`** (appended; the whole panel with
the real store, replies driven through `controlRunners` and the snapshot
runner, as the existing flow does): pause → requested → parked, the parent's
first flow (line 159):

22. Open Runs, hover a running row, click Pause: the button reads `Pause
    requested…` and is disabled; reply `ok: true`; a snapshot with the run
    parked settles it, and the row shows Resume enabled. Then an `ok: false`
    `NotAcceptingError` reply to a second request shows its sentence under
    that row and re-enables the buttons.

**Architecture tier.** `tests/architecture` passes unchanged:
`RunControls.qml` imports only QtQuick, `qs.Commons`, `../../core/domain/runs.js`,
`runGlyphs.js`, `../components` and `../theme` (no `core/stores`), uses
`ActionButton` for every button (no new `bordered: true`), `ThemedText` for
every text (no `font.family:`), and adds no glyph literal.

## Review focus for the planner

- `pending` / `stillWaiting` are replaced on change, so bindings must read
  them through `app.runs.pending[...]` in the binding itself, not a cached
  copy.
- A Repeater's `modelData` copy loses nested arrays; the controls must take the
  run the row already reads back by position (`row.run`, `runRow.run`).
- The `actions` slot must not move the content of existing rows: every existing
  `tst_list_row.qml` and screen test keeps passing unchanged.
- During teardown `run` and `theme` can be null while bindings still run once
  (ActionButton's header comment); every read is guarded.
- The tooltip is only seen on hover in the real shell, and never on a disabled
  button (D8). The reason must be both the `tooltipText` and the reason line.
