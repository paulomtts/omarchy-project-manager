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

---

# 4.2 RunControls, wired into the run screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pause / Resume / Cancel buttons (plus their reason, caption, still-waiting and error lines) under each actionable run on the Runs screen, Run detail and the card detail's RUNS section, with Pause/Resume going to `app.runs.control()` and Cancel only asking (`cancelRequested(runId)`).

**Architecture:** A new presentation-only `ui/components/RunControls.qml` takes the run and the store-derived facts as props and emits `actionRequested(action)`. `ui/components/ListRow.qml` gains an `actions` slot stacked above its MouseArea so buttons in a row take their own clicks. A tiny `.pragma library` helper `ui/components/runControlFacts.js` reads `pending` / `stillWaiting` / the control error for one run with own-key checks, so the three screens share one copy of that lookup instead of three.

**Tech Stack:** QML (Qt 6, Quickshell shell `qs.Ui` / `qs.Commons`), `.pragma library` JS, QtTest via `qmltestrunner` (stubs in `tests/stubs`), pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/4-2-runcontrols-1c268d85.md` (prepended above).

## Global Constraints

- `RunControls.qml` imports only `QtQuick`, `qs.Commons`, `../../core/domain/runs.js`, `runGlyphs.js`, `../components`, `../theme` -- never `core/stores` (D1; `tests/architecture/test_layers.py`).
- Every button is a `UI.ActionButton` (no new `bordered: true`), every text a `UI.ThemedText` (no `font.family:`).
- Glyphs only from `runGlyphs.js`: Pause `glyphOf("parked")` (`⏸`), Resume `glyphOf("running")` (`⟳`), Cancel `glyphOf("cancelled")` (`⊘`). No new glyph literal in `ui/`.
- The pending ellipsis is the single character `…` (U+2026): `Pause requested…`, `Resume requested…`, `Cancel requested…`.
- Exact strings: `applies to the whole run`; `Waiting for the run to act on the request`; `A request for this run is pending`; reasons joined by ` · `.
- No screen ever calls `control("cancel", …)`; Cancel emits the screen's `cancelRequested(string runId)` (D3).
- No change to `core/stores/RunStore.qml`, `core/domain/runs.js`, `core/stores/App.qml`, or any backend helper.
- `bash tests/run.sh` must stay green: it fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in the QML output.
- Every existing `tst_list_row.qml` and screen test keeps passing unchanged (the `actions` slot must not move existing rows).
- Commit subjects follow the repo style: `feat(runs): … (card 1c268d85)`.

## Review Focus

1. **A click on a disabled button inside a row** (e.g. Pause during Integrate) -- a person expects nothing to happen; without care the click falls through the disabled button's MouseArea to the row's and opens the run. Pinned in Task 1 (`test_clicking_a_disabled_action_does_not_activate_the_row`).
2. **A run id that is an `Object.prototype` name** (`constructor`, `__proto__`) -- expected to read as "nothing pending, no error". Pinned in Task 3 (`tst_run_control_facts.qml` and `test_a_run_id_like_constructor_is_not_pending`).
3. **Teardown / missing data: `theme` or `run` null, or a malformed run** (`status: 7`, `lease: "x"`) -- expected: nothing shown, no TypeError in the output. Pinned in Task 2 (`test_a_null_theme_and_run_do_not_throw`, malformed run in `test_finished_unknown_and_missing_runs_show_nothing`).
4. **Hover on a row whose actions strip has content** -- the row must still report `hovered(index)` and keep the cursor while it grows under the mouse. Pinned in Task 1 (`test_hovering_a_row_with_actions_reports_its_index`) and Task 6's flow.
5. **A pending cancel whose run already reads `cancelled`** (the snapshot arrived before the store settled it) -- expected: only `Cancel requested…` shows, disabled, no Pause/Resume. Pinned in Task 2 (`test_a_pending_request_shows_its_own_button_whatever_the_state`).

## Deviation from the spec's file list

The spec's Scope lists `RunControls.qml`, `ListRow.qml` and the three screens. This plan adds one small file, `ui/components/runControlFacts.js` (+ its test `tests/ui/components/tst_run_control_facts.qml`), so the own-key lookups the spec requires ("Lookups use own-property checks so a run id such as `constructor` reads as not pending") are written once instead of three times across `RunsScreen`, `RunDetailScreen` and `CardDetailScreen` (docs/architecture.md line 103: reuse before writing a second copy). Each binding still reads `app.runs.pending` / `app.runs.stillWaiting` itself and hands the map to the helper, per the spec's review focus.

## File Structure

| File | Responsibility |
|---|---|
| `ui/components/ListRow.qml` (modify) | new `actions` slot: a column under the content, stacked above the row's MouseArea, swallowing clicks that miss a button |
| `ui/components/RunControls.qml` (create) | one run's buttons and lines; presentation only |
| `ui/components/runControlFacts.js` (create) | `runIdOf`, `pendingOf`, `waitingOf`, `errorOf`: own-key reads of the store's per-run facts |
| `ui/screens/RunsScreen.qml` (modify) | `RunRow.actions` holds a `RunControls`; `cancelRequested(runId)`; `requestControl()` |
| `ui/screens/RunDetailScreen.qml` (modify) | `runDetailControls` after `runDetailReason`; `cancelRequested(runId)`; `requestControl()` |
| `ui/screens/CardDetailScreen.qml` (modify) | `CardRunRow.actions` holds a `RunControls` (`wholeRun` on story/subtask cards); `cancelRequested(runId)`; `requestControl()` |
| `tests/ui/components/tst_list_row.qml` (append) | the `actions` slot |
| `tests/ui/components/tst_run_controls.qml` (create) | the component, with plain runs |
| `tests/ui/components/tst_run_control_facts.qml` (create) | the helper |
| `tests/ui/screens/tst_runs_screen.qml`, `tst_run_detail_screen.qml`, `tst_card_detail_screen.qml` (append) | each screen's binding and forwarding |
| `tests/ui/tst_runs_flow.qml` (append) | pause → requested → parked → refused resume, whole panel |
| `docs/architecture.md` (modify) | `RunControls`, `ListRow.actions`, where the controls appear |

## How to run tests

- One QML file (also runs pytest first, ~60 s): `bash tests/run.sh <substring of the test path>`, e.g. `bash tests/run.sh tst_list_row`. Output shows `== <file>`, any `FAIL` lines with `Loc` and a `Totals:` line; exit status 1 on a failure or on a TypeError/ReferenceError line.
- Faster loop for one file (no pytest, no error grep -- always finish with `tests/run.sh`):
  `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_list_row.qml`
- Everything: `bash tests/run.sh`.

Test conventions in this repo: `H.find(root, objectName)` (`tests/helpers/find.js`) is a depth-first search returning the FIRST match or `null`; several rows each hold a `runControlPause`, so always search inside the right `runRowControls<i>` / `cardRunControls<i>` first. Two `mouseClick`s inside 400 ms make the second a double-click, which a MouseArea does not report as `clicked`: every test that clicks more than once goes through a `tap(item)` helper that waits 450 ms first. The stub `tests/stubs/qs/Ui/Button.qml` is an 80×28 Item whose MouseArea is `enabled: parent.enabled`; it renders no tooltip, so tooltips are asserted as the `tooltipText` property.

---

### Task 1: `ListRow` gains an `actions` slot

**Files:**
- Modify: `ui/components/ListRow.qml` (whole file, 53 lines)
- Test: `tests/ui/components/tst_list_row.qml` (append before the final `}`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `ListRow.actions` -- a list property (`property alias actions: actionsColumn.data`); owners write `actions: [ SomeItem { width: parent.width; … } ]`, where `parent` is the actions column (its width is the row's width minus `2 * contentMargin`). `ListRow.actionsExtent` (readonly real): `0` when no action item has a height, else the actions column's height plus the content column's spacing. A row with nothing (or nothing visible) in `actions` has `implicitHeight === content.implicitHeight + Style.spacing.rowPaddingX`, exactly as today.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ui/components/tst_list_row.qml`, inside `TestCase { … }` just before its closing `}`:

```qml
  // ---- the actions slot (S2 4.2, D2)

  Component {
    id: actionRowC
    UI.ListRow {
      width: 300
      theme: tcTheme
      UI.ThemedText { objectName: "rowLabel"; theme: tcTheme; width: parent.width; text: "a row" }
      actions: [
        UI.ActionButton { objectName: "rowButton"; theme: tcTheme; text: "Go" }
      ]
    }
  }

  SignalSpy { id: buttonSpy; signalName: "clicked" }

  function makeWithAction() {
    var row = createTemporaryObject(actionRowC, tc)
    var spies = [hoverSpy, activateSpy, revealSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = row; spies[i].clear() }
    buttonSpy.target = H.find(row, "rowButton")
    buttonSpy.clear()
    wait(20)
    return row
  }

  function test_an_empty_actions_slot_leaves_the_row_as_it_was() {
    var row = make()
    var label = H.find(row, "rowLabel")
    compare(row.actionsExtent, 0)
    compare(row.implicitHeight, label.implicitHeight + Style.spacing.rowPaddingX)
    fuzzyCompare(label.parent.y, (row.height - label.parent.height) / 2, 0.5, "the content stays centred")
  }

  function test_an_action_sits_under_the_content_and_adds_its_height_and_the_spacing() {
    var row = makeWithAction()
    var label = H.find(row, "rowLabel")
    var button = H.find(row, "rowButton")
    verify(button)
    fuzzyCompare(row.implicitHeight, label.implicitHeight + button.height + Style.space(2) + Style.spacing.rowPaddingX, 0.01)
    fuzzyCompare(label.parent.y, Style.spacing.rowPaddingX / 2, 0.5, "the content keeps its top inset")
    var b = button.mapToItem(row, 0, 0)
    var l = label.mapToItem(row, 0, 0)
    verify(b.y >= l.y + label.height, "the button is under the content")
    fuzzyCompare(b.x, Style.space(10), 0.5, "inside the content margin")
  }

  function test_a_hidden_action_takes_no_room() {
    var row = makeWithAction()
    var label = H.find(row, "rowLabel")
    H.find(row, "rowButton").visible = false
    wait(20)   // a Column re-lays out on the next polish, not synchronously
    compare(row.actionsExtent, 0)
    compare(row.implicitHeight, label.implicitHeight + Style.spacing.rowPaddingX)
  }

  function test_clicking_an_action_does_not_activate_the_row() {
    var row = makeWithAction()
    mouseClick(H.find(row, "rowButton"))
    compare(buttonSpy.count, 1)
    compare(activateSpy.count, 0)
  }

  function test_clicking_the_content_still_activates_a_row_with_actions() {
    var row = makeWithAction()
    mouseClick(H.find(row, "rowLabel"))
    compare(activateSpy.count, 1)
    compare(buttonSpy.count, 0)
  }

  // Review Focus 1: a disabled button lets the click through its own
  // MouseArea; the strip must still keep it from the row.
  function test_clicking_a_disabled_action_does_not_activate_the_row() {
    var row = makeWithAction()
    var button = H.find(row, "rowButton")
    button.enabled = false
    mouseClick(button)
    compare(buttonSpy.count, 0)
    compare(activateSpy.count, 0)
  }

  // Review Focus 4.
  function test_hovering_a_row_with_actions_reports_its_index() {
    var row = makeWithAction()
    row.index = 4
    // The mouse keeps its position between tests: park it outside the row (the
    // TestCase is 400x300, the row 300 wide) so the move into the content is an
    // enter.
    mouseMove(tc, 390, 290)
    mouseMove(row, row.width / 2, 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 4)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_list_row`
Expected: FAIL. The `actionRowC` component cannot be created (`Cannot assign to non-existent property "actions"`), so every `makeWithAction()` test fails (null row / TypeError), and `test_an_empty_actions_slot_leaves_the_row_as_it_was` fails on `row.actionsExtent` (`undefined` vs `0`). The eight existing tests still pass.

- [ ] **Step 3: Implement the slot**

Replace the whole of `ui/components/ListRow.qml` with:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../theme" as T

// One row of a keyboard-navigable list: the cursor highlight, the reveal a
// keyboard move asks for, and the hover/click handling every list row in the
// panel shares. The declared children go into the row's content column; the
// items in `actions` go into a second column under it, stacked above the row's
// MouseArea, so a button there takes its own click and the row does not
// activate for it.
CursorSurface {
  id: row

  // -1 means "not a row of the list": it never takes the cursor and never
  // reports a hover (the card detail's link rows use that for a link that is
  // not in the cursor's list).
  property int index: -1
  property int cursorIndex: -1
  property bool scrollOnCursor: false
  property var theme: null
  property real contentMargin: Style.space(10)
  property int hoverCursorShape: Qt.PointingHandCursor

  default property alias content: contentColumn.data
  // Buttons and the lines that go with them, under the content.
  property alias actions: actionsColumn.data
  readonly property var palette: row.theme || rowTheme
  // The actions' share of the row: nothing at all while no action item has a
  // height, so a row without actions is exactly as tall as it always was.
  readonly property real actionsExtent: actionsColumn.implicitHeight > 0
    ? actionsColumn.implicitHeight + contentColumn.spacing : 0

  signal hovered(int index)
  signal activated()
  signal revealRequested(var item)

  implicitHeight: contentColumn.implicitHeight + row.actionsExtent + Style.spacing.rowPaddingX
  hasCursor: row.index >= 0 && row.cursorIndex === row.index
  foreground: row.palette ? row.palette.foreground : Color.foreground
  onHasCursorChanged: if (hasCursor && row.scrollOnCursor) row.revealRequested(row)

  Column {
    id: contentColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -row.actionsExtent / 2
    anchors.leftMargin: row.contentMargin
    anchors.rightMargin: row.contentMargin
    spacing: Style.space(2)
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.hoverCursorShape
    onEntered: if (row.index >= 0) row.hovered(row.index)
    onClicked: row.activated()
  }

  // Above the row's MouseArea. A click anywhere in this strip stays in it: a
  // button takes it, and a disabled button or the gap beside one never opens
  // the row.
  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: contentColumn.bottom
    anchors.topMargin: row.actionsExtent > 0 ? contentColumn.spacing : 0
    anchors.leftMargin: row.contentMargin
    anchors.rightMargin: row.contentMargin
    height: actionsColumn.implicitHeight

    MouseArea { anchors.fill: parent }

    Column {
      id: actionsColumn
      width: parent.width
      spacing: contentColumn.spacing
    }
  }

  T.Theme { id: rowTheme }
}
```

Why this geometry: with `E = actionsExtent`, the row is `C + E + P` tall (content, actions, padding). Centring the content with offset `-E/2` puts its top at `P/2` -- the same place `anchors.verticalCenter` alone put it when `E` was 0 -- and the actions column starts one spacing under the content, leaving `P/2` below. With `E = 0` the offset is 0 and nothing moves.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_list_row`
Expected: `Totals: 17 passed, 0 failed` (15 tests plus initTestCase/cleanupTestCase), no TypeError lines, exit 0.

Then make sure no existing row moved: `bash tests/run.sh tests/ui` — every file `0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ui/components/ListRow.qml tests/ui/components/tst_list_row.qml
git commit -m "feat(ui): ListRow gains an actions slot under its content whose buttons take their own clicks (card 1c268d85)"
```

---

### Task 2: `RunControls` component

**Files:**
- Create: `ui/components/RunControls.qml`
- Test: `tests/ui/components/tst_run_controls.qml` (new)

**Interfaces:**
- Consumes: `Runs.runState(run)` → `"running"|"parked"|"escalated"|"dead"|"cancelled"|"done"|"unknown"`; `Runs.controls(run)` → `{pause, resume, cancel}` each `{enabled: bool, reason: string}` (`core/domain/runs.js`); `RunGlyphs.glyphOf(state)` (`ui/components/runGlyphs.js`); `UI.ActionButton` (`theme`, `tone`, `text`, `iconText`, `tooltipText`, `enabled`, signal `clicked()`); `UI.ThemedText` (`theme`, `variant`).
- Produces: `UI.RunControls` (a `Column`) with props `theme` (var, default `T.Theme {}`), `run` (var, `null`), `pendingAction` (string, `""`), `waiting` (bool, `false`), `waitingText` (string, `""`), `errorText` (string, `""`), `wholeRun` (bool, `false`), `showButtons` (bool, `true`); signal `actionRequested(string action)` with `"pause"|"resume"|"cancel"`. Children by `objectName`: `runControlButtons` (the Row), `runControlPause`, `runControlResume`, `runControlCancel`, `runControlCaption`, `runControlReason`, `runControlWaiting`, `runControlError`. Height 0 when nothing shows.

- [ ] **Step 1: Write the failing tests**

Create `tests/ui/components/tst_run_controls.qml`:

```qml
// tests/ui/components/tst_run_controls.qml
// ui/components/RunControls.qml on its own, with plain run objects and no
// store: which of Pause / Resume / Cancel show for each run state, their
// labels, glyphs, enabled state and tooltips, the reason, caption, waiting and
// error lines, and the one signal a click emits.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunControls"
  when: windowShown
  visible: true
  width: 400; height: 300

  readonly property string integrate: "Integrate is running; it cannot be paused or cancelled"
  readonly property string waitingTip: "Waiting for the run to act on the request"
  readonly property string pendingTip: "A request for this run is pending"
  readonly property string waitText: "still waiting — the run may be between phases or dead"

  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }

  Component { id: controlsC; UI.RunControls { width: 300; theme: tcTheme } }
  SignalSpy { id: actionSpy; signalName: "actionRequested" }

  // A normalised run, as RunStore holds them. live === null means no lease;
  // accepting === false puts a leased run in Integrate.
  function run(id, status, live, accepting) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "M3", status: status, started_at: "",
             base_branch: "master", branch_prefix: "m3", workflow: "milestone",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: accepting !== false, live: live },
             requests: [], rows: [], tree: { stories: [], subtasks: [] } }
  }
  function running(accepting) { return run("run-x-live0001", "started", true, accepting) }
  function parked() { return run("run-x-park0002", "stopped", null) }
  function escalated() { return run("run-x-escl0003", "escalated", null) }
  function dead() { return run("run-x-dead0004", "started", false) }

  function make(props) {
    var c = createTemporaryObject(controlsC, tc, props || {})
    actionSpy.target = c
    actionSpy.clear()
    wait(20)
    return c
  }

  function part(c, name) { return H.find(c, "runControl" + name) }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // 1
  function test_a_running_run_shows_pause_and_cancel() {
    var c = make({ run: running() })
    var pause = part(c, "Pause"), resume = part(c, "Resume"), cancel = part(c, "Cancel")
    compare(pause.visible, true)
    compare(pause.enabled, true)
    compare(pause.text, "Pause")
    compare(pause.iconText, "⏸")
    compare(pause.iconText, RG.glyphOf("parked"))
    compare(pause.tooltipText, "")
    compare(cancel.visible, true)
    compare(cancel.enabled, true)
    compare(cancel.text, "Cancel")
    compare(cancel.iconText, "⊘")
    compare(cancel.iconText, RG.glyphOf("cancelled"))
    compare(cancel.tooltipText, "")
    compare(cancel.tone, "danger")
    compare(pause.tone, "normal")
    compare(resume.visible, false, "never both Pause and Resume")
    compare(part(c, "Reason").visible, false, "everything enabled: no reason line")
    compare(part(c, "Caption").visible, false)
    verify(c.height > 0)
  }

  // 2
  function test_parked_escalated_and_dead_runs_show_resume_and_cancel() {
    var cases = [["parked", parked()], ["escalated", escalated()], ["dead", dead()]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1] })
      var resume = part(c, "Resume")
      compare(resume.visible, true, cases[i][0])
      compare(resume.enabled, true, cases[i][0])
      compare(resume.text, "Resume", cases[i][0])
      compare(resume.iconText, "⟳", cases[i][0])
      compare(resume.iconText, RG.glyphOf("running"), cases[i][0])
      compare(resume.tooltipText, "", cases[i][0])
      compare(part(c, "Cancel").visible, true, cases[i][0])
      compare(part(c, "Cancel").enabled, true, cases[i][0])
      compare(part(c, "Pause").visible, false, cases[i][0])
      compare(part(c, "Reason").visible, false, cases[i][0])
    }
  }

  // 3
  function test_integrate_disables_pause_and_cancel_and_says_why_once() {
    var c = make({ run: running(false) })
    var pause = part(c, "Pause"), cancel = part(c, "Cancel")
    compare(pause.visible, true)
    compare(pause.enabled, false)
    compare(pause.tooltipText, tc.integrate)
    compare(cancel.visible, true)
    compare(cancel.enabled, false)
    compare(cancel.tooltipText, tc.integrate)
    compare(part(c, "Resume").visible, false)
    var reason = part(c, "Reason")
    compare(reason.visible, true)
    compare(reason.text, tc.integrate, "the one sentence, once")

    var e = escalated()
    e.lease = { pid: 1, host: "h", heartbeat_at: "", accepting: false, live: false }
    var c2 = make({ run: e })
    compare(part(c2, "Resume").enabled, true, "resume never looks at accepting")
    compare(part(c2, "Cancel").enabled, false)
    compare(part(c2, "Cancel").tooltipText, tc.integrate)
    compare(part(c2, "Reason").text, tc.integrate)
  }

  // 4 + Review Focus 3 (a malformed run)
  function test_finished_unknown_and_missing_runs_show_nothing() {
    var cases = [["done", run("run-x-done0005", "done", null)],
                 ["cancelled", run("run-x-canc0006", "cancelled", null)],
                 ["unknown", run("run-x-bogus007", "bogus", null)],
                 ["null", null],
                 ["malformed", { id: 5, status: 7, lease: "x", rows: "y", tree: null }]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1], wholeRun: true })
      compare(part(c, "Buttons").visible, false, cases[i][0])
      compare(part(c, "Pause").visible, false, cases[i][0])
      compare(part(c, "Resume").visible, false, cases[i][0])
      compare(part(c, "Cancel").visible, false, cases[i][0])
      compare(part(c, "Caption").visible, false, cases[i][0])
      compare(part(c, "Reason").visible, false, cases[i][0])
      compare(c.height, 0, cases[i][0])
    }
  }

  // 5
  function test_whole_run_labels_and_the_caption() {
    var c = make({ run: running(), wholeRun: true })
    compare(part(c, "Pause").text, "Pause run")
    compare(part(c, "Cancel").text, "Cancel run")
    var caption = part(c, "Caption")
    compare(caption.visible, true)
    compare(caption.text, "applies to the whole run")
    c.run = parked()
    compare(part(c, "Resume").text, "Resume run")
    c.wholeRun = false
    compare(caption.visible, false)
    compare(part(c, "Resume").text, "Resume")
    compare(part(c, "Cancel").text, "Cancel")
  }

  // 6
  function test_a_pending_request_disables_every_button() {
    var c = make({ run: running(), pendingAction: "pause" })
    var pause = part(c, "Pause"), cancel = part(c, "Cancel")
    compare(pause.visible, true)
    compare(pause.text, "Pause requested…")
    compare(pause.iconText, "⏸", "the icon does not change while pending")
    compare(pause.enabled, false)
    compare(pause.tooltipText, tc.waitingTip)
    compare(cancel.text, "Cancel")
    compare(cancel.enabled, false)
    compare(cancel.tooltipText, tc.pendingTip)
    compare(part(c, "Resume").visible, false)
    compare(part(c, "Reason").visible, false, "a pending request is not a disabled reason")

    c.pendingAction = "cancel"
    compare(cancel.text, "Cancel requested…")
    compare(cancel.tooltipText, tc.waitingTip)
    compare(pause.text, "Pause")
    compare(pause.enabled, false)
    compare(pause.tooltipText, tc.pendingTip)

    var d = make({ run: dead(), pendingAction: "resume" })
    compare(part(d, "Resume").text, "Resume requested…")
    compare(part(d, "Resume").enabled, false)
    compare(part(d, "Resume").tooltipText, tc.waitingTip)
    compare(part(d, "Cancel").enabled, false)
    compare(part(d, "Cancel").tooltipText, tc.pendingTip)
    compare(part(d, "Pause").visible, false)

    var integrate = make({ run: running(false), pendingAction: "pause" })
    compare(part(integrate, "Reason").visible, false, "no reason line while pending, even in Integrate")
  }

  // 7 + Review Focus 5
  function test_a_pending_request_shows_its_own_button_whatever_the_state() {
    var c = make({ run: parked(), pendingAction: "pause" })
    compare(part(c, "Pause").visible, true, "the pause slot keeps Pause until it settles")
    compare(part(c, "Pause").text, "Pause requested…")
    compare(part(c, "Resume").visible, false)

    var r = make({ run: running(), pendingAction: "resume" })
    compare(part(r, "Resume").visible, true)
    compare(part(r, "Resume").text, "Resume requested…")
    compare(part(r, "Pause").visible, false)

    var k = make({ run: run("run-x-canc0006", "cancelled", null), pendingAction: "cancel" })
    compare(part(k, "Buttons").visible, true)
    compare(part(k, "Cancel").visible, true)
    compare(part(k, "Cancel").text, "Cancel requested…")
    compare(part(k, "Cancel").enabled, false)
    compare(part(k, "Pause").visible, false)
    compare(part(k, "Resume").visible, false)
  }

  // 8
  function test_show_buttons_false_hides_the_buttons_but_not_a_pending_one_or_the_error() {
    var c = make({ run: running(), wholeRun: true, showButtons: false })
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Caption").visible, false)
    compare(c.height, 0)
    c.pendingAction = "pause"
    compare(part(c, "Buttons").visible, true)
    compare(part(c, "Pause").visible, true)
    compare(part(c, "Pause").text, "Pause requested…")
    compare(part(c, "Caption").visible, true)
    c.pendingAction = ""
    c.errorText = "The run is not running"
    wait(20)   // a Column re-lays out on the next polish, not synchronously
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Error").visible, true)
    verify(c.height > 0)
  }

  // 9
  function test_a_click_on_an_enabled_button_asks_for_its_action_once() {
    var c = make({ run: running() })
    tap(part(c, "Pause"))
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "pause")
    tap(part(c, "Cancel"))
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "cancel")

    var p = make({ run: parked() })
    tap(part(p, "Resume"))
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "resume")
  }

  function test_a_click_on_a_disabled_button_asks_for_nothing() {
    var c = make({ run: running(false) })
    tap(part(c, "Pause"))
    tap(part(c, "Cancel"))
    compare(actionSpy.count, 0)
    var p = make({ run: running(), pendingAction: "pause" })
    tap(part(p, "Pause"))
    tap(part(p, "Cancel"))
    compare(actionSpy.count, 0)
  }

  // 10
  function test_the_waiting_line_needs_waiting_a_pending_action_and_a_text() {
    var c = make({ run: running(), waiting: true, waitingText: tc.waitText })
    var line = part(c, "Waiting")
    compare(line.visible, false, "nothing pending")
    c.pendingAction = "pause"
    compare(line.visible, true)
    compare(line.text, tc.waitText)
    compare(String(line.color), String(tcTheme.dim))   // Text.color is 8-bit; the theme's float colour is not, so compare the rendered hex
    c.waiting = false
    compare(line.visible, false)
    c.waiting = true
    c.waitingText = ""
    compare(line.visible, false)
  }

  function test_the_error_line_shows_the_error_in_urgent() {
    var c = make({ run: running() })
    var line = part(c, "Error")
    compare(line.visible, false)
    c.errorText = "The run is not running"
    compare(line.visible, true)
    compare(line.text, "The run is not running")
    compare(String(line.color), String(tcTheme.urgent))
    c.errorText = ""
    compare(line.visible, false)
  }

  // Review Focus 3: a view being torn down nulls theme and run while the
  // bindings still run once; tests/run.sh fails on any TypeError this prints.
  function test_a_null_theme_and_run_do_not_throw() {
    var c = make({ run: running(), errorText: "boom" })
    c.theme = null
    compare(part(c, "Pause").visible, true)
    compare(part(c, "Error").visible, true)
    c.run = null
    c.errorText = ""
    wait(20)
    compare(part(c, "Buttons").visible, false)
    compare(c.height, 0)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_controls`
Expected: FAIL -- every test fails because `UI.RunControls` does not exist (`RunControls is not a type` / `createTemporaryObject` returns null, then `TypeError: Cannot read property … of null`), exit 1.

- [ ] **Step 3: Implement the component**

Create `ui/components/RunControls.qml`:

```qml
import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// One run's Pause / Resume / Cancel buttons and the lines under them: why a
// shown button is disabled, "applies to the whole run" on a story or subtask
// card, the store's still-waiting line and the control error for this run.
//
// Presentation only, like RunIndicator: it imports no store. The owner passes
// the run and what the store says about it (the action pending for it, whether
// that request is 30 s old, the control error for this run) and decides when
// the buttons show (`showButtons`); a click on an enabled button emits
// actionRequested("pause" | "resume" | "cancel"), and confirming a cancel is
// the owner's business. What a run allows is Runs.controls(run); a pending
// request disables every button.
//
// At most one of Pause and Resume shows: Pause on a running run, Resume on a
// parked, escalated or dead one, and a pending pause or resume keeps its own
// button until it settles. A finished, unknown or missing run shows no
// buttons, and with nothing to show the component is 0 tall.
//
// A disabled shell Button gets no hover, so its tooltip never shows: the
// reasons of the shown disabled buttons are also written out once, in the
// reason line.
Column {
  id: controls

  property var theme: T.Theme {}
  // One normalised run, as RunStore.runs holds them, or null.
  property var run: null
  // "" or the action pending for this run.
  property string pendingAction: ""
  // That request is 30 s or more old.
  property bool waiting: false
  property string waitingText: ""
  // The control error for THIS run; "" otherwise.
  property string errorText: ""
  // The controls sit on a story or subtask card: the labels say "run".
  property bool wholeRun: false
  // The owner's rule for showing the buttons; a pending request shows anyway.
  property bool showButtons: true

  signal actionRequested(string action)

  readonly property string runState: Runs.runState(controls.run)
  readonly property var allowed: Runs.controls(controls.run)
  readonly property bool requestPending: controls.pendingAction !== ""
  readonly property bool resumable: controls.runState === "parked" || controls.runState === "escalated"
    || controls.runState === "dead"
  readonly property bool buttonsShown: (controls.showButtons && (controls.runState === "running" || controls.resumable))
    || controls.requestPending
  readonly property bool pauseShown: controls.pendingAction === "pause"
    || (controls.pendingAction !== "resume" && controls.runState === "running")
  readonly property bool resumeShown: controls.pendingAction === "resume"
    || (controls.pendingAction !== "pause" && controls.resumable)
  // The distinct reasons of the shown disabled buttons, in button order.
  readonly property string reasonText: {
    if (!controls.buttonsShown || controls.requestPending || !controls.allowed) return ""
    var shown = []
    if (controls.pauseShown) shown.push("pause")
    if (controls.resumeShown) shown.push("resume")
    shown.push("cancel")
    var out = []
    for (var i = 0; i < shown.length; i++) {
      var a = controls.allowed[shown[i]]
      if (a && !a.enabled && a.reason !== "" && out.indexOf(a.reason) < 0) out.push(a.reason)
    }
    return out.join(" · ")
  }

  spacing: Style.space(2)

  function labelOf(action, word) {
    if (controls.pendingAction === action) return word + " requested…"
    return controls.wholeRun ? word + " run" : word
  }

  function enabledOf(action) {
    var a = controls.allowed ? controls.allowed[action] : null
    return !controls.requestPending && !!a && a.enabled === true
  }

  function tooltipOf(action) {
    if (controls.requestPending)
      return controls.pendingAction === action ? "Waiting for the run to act on the request" : "A request for this run is pending"
    var a = controls.allowed ? controls.allowed[action] : null
    return a ? a.reason : ""
  }

  Row {
    objectName: "runControlButtons"
    visible: controls.buttonsShown
    spacing: Style.space(6)

    UI.ActionButton {
      id: pauseButton
      objectName: "runControlPause"
      theme: controls.theme
      visible: controls.pauseShown
      text: controls.labelOf("pause", "Pause")
      iconText: RunGlyphs.glyphOf("parked")
      enabled: controls.enabledOf("pause")
      tooltipText: controls.tooltipOf("pause")
      onClicked: if (pauseButton.enabled) controls.actionRequested("pause")
    }

    UI.ActionButton {
      id: resumeButton
      objectName: "runControlResume"
      theme: controls.theme
      visible: controls.resumeShown
      text: controls.labelOf("resume", "Resume")
      iconText: RunGlyphs.glyphOf("running")
      enabled: controls.enabledOf("resume")
      tooltipText: controls.tooltipOf("resume")
      onClicked: if (resumeButton.enabled) controls.actionRequested("resume")
    }

    UI.ActionButton {
      id: cancelButton
      objectName: "runControlCancel"
      theme: controls.theme
      tone: "danger"
      text: controls.labelOf("cancel", "Cancel")
      iconText: RunGlyphs.glyphOf("cancelled")
      enabled: controls.enabledOf("cancel")
      tooltipText: controls.tooltipOf("cancel")
      onClicked: if (cancelButton.enabled) controls.actionRequested("cancel")
    }
  }

  UI.ThemedText {
    objectName: "runControlCaption"
    variant: "caption"
    theme: controls.theme
    visible: controls.buttonsShown && controls.wholeRun
    text: "applies to the whole run"
  }

  UI.ThemedText {
    objectName: "runControlReason"
    variant: "caption"
    theme: controls.theme
    width: parent.width
    visible: controls.reasonText !== ""
    text: controls.reasonText
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runControlWaiting"
    variant: "caption"
    theme: controls.theme
    width: parent.width
    visible: controls.waiting && controls.requestPending && controls.waitingText !== ""
    text: controls.waitingText
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runControlError"
    variant: "caption"
    theme: controls.theme
    width: parent.width
    visible: controls.errorText !== ""
    text: controls.errorText
    color: controls.theme ? controls.theme.urgent : Color.urgent
    wrapMode: Text.WordWrap
  }
}
```

Notes for the implementer: do not name a property `state` -- every `Item` already has one. The `caption` variant of `ThemedText` already paints in the theme's `dim`, so the reason and waiting lines need no `color`. The width of the text lines is the column's: every owner sets `width: parent.width` on `RunControls`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_controls`
Expected: `Totals: 15 passed, 0 failed` (13 tests plus init/cleanup), no TypeError lines, exit 0.

Then: `uv run --with pytest python3 -m pytest tests/architecture -q` (or `python3 -m pytest tests/architecture -q` when pytest is installed) → all pass (imports, no `bordered: true`, no `font.family:`, no new Nerd Font glyph).

- [ ] **Step 5: Commit**

```bash
git add ui/components/RunControls.qml tests/ui/components/tst_run_controls.qml
git commit -m "feat(runs): RunControls shows a run's pause, resume and cancel buttons with their reasons, pending, waiting and error lines (card 1c268d85)"
```

---

### Task 3: Shared per-run lookups, and the Runs screen's rows get controls

**Files:**
- Create: `ui/components/runControlFacts.js`
- Test: `tests/ui/components/tst_run_control_facts.qml` (new)
- Modify: `ui/screens/RunsScreen.qml` (imports lines 1-6; signals after line 22; `RunRow` lines 115-220)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stub `runsC` lines 24-41; new tests appended before the final `}`)

**Interfaces:**
- Consumes: `UI.RunControls` (Task 2: props `run`, `pendingAction`, `waiting`, `waitingText`, `errorText`, `wholeRun`, `showButtons`, `theme`; signal `actionRequested(string action)`); `ListRow.actions` (Task 1); `app.runs.pending` (`{runId: action}`), `app.runs.stillWaiting` (`{runId: true}`), `app.runs.stillWaitingText` (string), `app.runs.lastControlError` (string), `app.runs.lastControlErrorRunId` (string), `app.runs.control(action, runId)` → bool.
- Produces: `runControlFacts.js` functions `runIdOf(run)` → string (`""` unless `run.id` is a string), `pendingOf(pending, run)` → string, `waitingOf(stillWaiting, run)` → bool, `errorOf(errorText, errorRunId, run)` → string. `RunsScreen` signal `cancelRequested(string runId)` and function `requestControl(action, run)`. `RunsScreen` rows hold `runRowControls<index>`.

- [ ] **Step 1: Write the failing helper test**

Create `tests/ui/components/tst_run_control_facts.qml`:

```qml
// tests/ui/components/tst_run_control_facts.qml
// ui/components/runControlFacts.js: the store's per-run control facts read
// with own-key checks, so an id such as `constructor` or `__proto__` is just an
// id with nothing pending.
import QtQuick
import QtTest
import "../../../ui/components/runControlFacts.js" as Facts

TestCase {
  name: "RunControlFacts"

  function test_run_id_of() {
    compare(Facts.runIdOf({ id: "r1" }), "r1")
    compare(Facts.runIdOf({ id: 5 }), "")
    compare(Facts.runIdOf({}), "")
    compare(Facts.runIdOf(null), "")
    compare(Facts.runIdOf("r1"), "")
  }

  function test_pending_of() {
    var r = { id: "r1" }
    compare(Facts.pendingOf({ r1: "pause" }, r), "pause")
    compare(Facts.pendingOf({ r2: "pause" }, r), "")
    compare(Facts.pendingOf({ r1: 5 }, r), "", "only a string is an action")
    compare(Facts.pendingOf({ r1: "pause" }, null), "")
    compare(Facts.pendingOf(null, r), "")
    compare(Facts.pendingOf(undefined, r), "")
    compare(Facts.pendingOf({ "": "pause" }, { id: "" }), "", "no id, nothing pending")
  }

  // Review Focus 2.
  function test_inherited_names_are_not_pending_waiting_or_in_error() {
    var names = ["constructor", "__proto__", "toString", "hasOwnProperty"]
    for (var i = 0; i < names.length; i++) {
      var r = { id: names[i] }
      compare(Facts.pendingOf({}, r), "", names[i])
      compare(Facts.waitingOf({}, r), false, names[i])
    }
  }

  function test_waiting_of() {
    var r = { id: "r1" }
    compare(Facts.waitingOf({ r1: true }, r), true)
    compare(Facts.waitingOf({ r1: "yes" }, r), false, "only true is waiting")
    compare(Facts.waitingOf({ r2: true }, r), false)
    compare(Facts.waitingOf(null, r), false)
    compare(Facts.waitingOf({ r1: true }, null), false)
  }

  function test_error_of() {
    var r = { id: "r1" }
    compare(Facts.errorOf("The run is not running", "r1", r), "The run is not running")
    compare(Facts.errorOf("The run is not running", "r2", r), "", "another run's error")
    compare(Facts.errorOf("boom", "", { id: "" }), "", "no id matches no error")
    compare(Facts.errorOf("boom", "r1", null), "")
    compare(Facts.errorOf("", "r1", r), "")
    compare(Facts.errorOf(undefined, "r1", r), "")
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh tst_run_control_facts`
Expected: FAIL -- the import `runControlFacts.js` cannot be found (`Script … unavailable` / every test `TypeError: … Facts.runIdOf is not a function` or ReferenceError), exit 1.

- [ ] **Step 3: Implement the helper**

Create `ui/components/runControlFacts.js`:

```js
.pragma library

// What the run store says about one run's controls, read out of its maps with
// own-key checks: a run id such as `constructor` or `__proto__` is just an id
// with nothing pending. The screens pass the store's maps in from their own
// bindings, so every replacement of `pending` or `stillWaiting` re-runs them.

function runIdOf(run) {
  return run !== null && typeof run === "object" && typeof run.id === "string" ? run.id : ""
}

function _has(map, key) {
  return key !== "" && map !== null && typeof map === "object" && Object.prototype.hasOwnProperty.call(map, key)
}

// The action pending for the run ("pause" | "resume" | "cancel"), or "".
function pendingOf(pending, run) {
  var id = runIdOf(run)
  return _has(pending, id) && typeof pending[id] === "string" ? pending[id] : ""
}

// The run's pending request is 30 s or more old.
function waitingOf(stillWaiting, run) {
  var id = runIdOf(run)
  return _has(stillWaiting, id) && stillWaiting[id] === true
}

// The control error when it is about this run, else "".
function errorOf(errorText, errorRunId, run) {
  var id = runIdOf(run)
  return id !== "" && errorRunId === id && typeof errorText === "string" ? errorText : ""
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh tst_run_control_facts`
Expected: `Totals: 7 passed, 0 failed`, exit 0.

- [ ] **Step 5: Write the failing Runs screen tests**

In `tests/ui/screens/tst_runs_screen.qml`, extend the stub store `runsC` (lines 24-41). Replace:

```qml
      property string watchSchemaError: ""
      readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
```

with:

```qml
      property string watchSchemaError: ""
      readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(rs.runs, rs.runFilter), rs.searchQuery)
      function toggleRunFilter(id) { rs.runFilter = id === "all" || id === rs.runFilter ? "" : id }
      // The control surface the rows read (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
```

Then append, before the final `}` of the TestCase:

```qml
  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  // A part of row i's RunControls; search inside the row's controls, since
  // every row has a runControlPause.
  function ctl(s, i, name) { return H.find(H.find(s.screen, "runRowControls" + i), "runControl" + name) }

  // 13
  function test_a_rows_buttons_show_only_while_it_has_the_cursor() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = 0
    wait(20)
    compare(ctl(s, 0, "Pause").visible, true)
    compare(ctl(s, 0, "Cancel").visible, true)
    compare(ctl(s, 3, "Resume").visible, false, "the parked row has no cursor")
    s.nav.cursorIndex = 3
    wait(20)
    compare(ctl(s, 0, "Pause").visible, false)
    compare(ctl(s, 3, "Resume").visible, true)
    s.runs.pending = { "run-20261004-live0001": "pause" }
    compare(ctl(s, 0, "Pause").visible, true, "a pending request keeps its button")
    compare(ctl(s, 0, "Pause").text, "Pause requested…")
    compare(ctl(s, 0, "Pause").enabled, false)
    s.nav.cursorIndex = 5
    wait(20)
    compare(H.find(s.screen, "runRowControls5").height, 0, "a done run shows nothing under the cursor")
  }

  // 14
  function test_pause_and_resume_go_to_the_store_and_do_not_open_the_run() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = 0
    wait(20)
    tap(ctl(s, 0, "Pause"))
    compare(s.runs.controlCalls.join(","), "pause|run-20261004-live0001")
    compare(s.navi.opened, "", "the button is not the row")
    s.nav.cursorIndex = 3
    wait(20)
    tap(ctl(s, 3, "Resume"))
    compare(s.runs.controlCalls.join(","), "pause|run-20261004-live0001,resume|run-20261004-park0004")
    compare(s.navi.opened, "")
  }

  // 15
  function test_cancel_asks_the_owner_and_never_the_store() {
    var s = make(sample()); if (!s) return
    cancelSpy.target = s.screen
    cancelSpy.clear()
    s.nav.cursorIndex = 0
    wait(20)
    tap(ctl(s, 0, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-20261004-live0001")
    compare(s.runs.controlCalls.length, 0)
    compare(s.navi.opened, "")
  }

  // 16
  function test_the_error_and_waiting_lines_show_under_their_own_run_only() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = -1
    s.runs.lastControlError = "The run is not running"
    s.runs.lastControlErrorRunId = "run-20261004-escl0002"
    wait(20)
    compare(ctl(s, 1, "Error").visible, true, "whether or not the row has the cursor")
    compare(ctl(s, 1, "Error").text, "The run is not running")
    compare(ctl(s, 0, "Error").visible, false)
    compare(ctl(s, 2, "Error").visible, false)
    s.runs.pending = { "run-20261004-dead0003": "resume" }
    s.runs.stillWaiting = { "run-20261004-dead0003": true }
    compare(ctl(s, 2, "Waiting").visible, true)
    compare(ctl(s, 2, "Waiting").text, "still waiting — the run may be between phases or dead")
    compare(ctl(s, 2, "Resume").text, "Resume requested…")
    compare(ctl(s, 0, "Waiting").visible, false)
  }

  // Review Focus 2.
  function test_a_run_id_like_constructor_is_not_pending() {
    var s = make([run("constructor", "started", true, {}), run("__proto__", "stopped", null, {})]); if (!s) return
    s.nav.cursorIndex = 0
    wait(20)
    compare(ctl(s, 0, "Pause").text, "Pause")
    compare(ctl(s, 0, "Pause").enabled, true)
    compare(ctl(s, 0, "Waiting").visible, false)
    compare(ctl(s, 0, "Error").visible, false)
    s.nav.cursorIndex = 1
    wait(20)
    compare(ctl(s, 1, "Resume").text, "Resume")
    compare(ctl(s, 1, "Resume").enabled, true)
  }
```

- [ ] **Step 6: Run them to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: the five new tests FAIL (`runRowControls0` is not found, so `ctl()` returns null and `.visible` throws `TypeError: Cannot read property 'visible' of null`); the existing tests still pass; exit 1.

- [ ] **Step 7: Wire the controls into `RunsScreen.qml`**

Imports (lines 1-6) become:

```qml
import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T
```

Replace:

```qml
  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)
```

with:

```qml
  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)
  // A run's Cancel was clicked. Cancelling needs a typed confirmation, which is
  // the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)
```

After the `stateText` function (ends at line 45), add:

```qml

  // A row's control button: pause and resume go straight to the store, a
  // cancel only asks (cancelRequested).
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else screen.app.runs.control(action, id)
  }
```

In `component RunRow`, after the last child (the `runRowReason` `UI.ThemedText`, which ends just before the component's closing `}`), add:

```qml

    // Under the row: the buttons while it has the cursor (hover moves the
    // cursor, so that is hover or selected) or a request is pending, and the
    // waiting and error lines whenever they apply.
    actions: [
      UI.RunControls {
        objectName: "runRowControls" + row.index
        width: parent.width
        theme: screen.theme
        run: row.run
        pendingAction: ControlFacts.pendingOf(screen.app.runs.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runs.stillWaiting, row.run)
        waitingText: screen.app.runs.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runs.lastControlError, screen.app.runs.lastControlErrorRunId, row.run)
        wholeRun: false
        showButtons: row.hasCursor
        onActionRequested: function(action) { screen.requestControl(action, row.run) }
      }
    ]
```

The row's existing `opacity: screen.app.runs.stale ? 0.5 : 1` already dims the controls while stale; do not disable them separately (the store's `control()` guards).

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen`
Expected: `0 failed`, no TypeError lines, exit 0. Also `bash tests/run.sh tst_runs_flow` → `0 failed` (the panel mounts the screen).

- [ ] **Step 9: Commit**

```bash
git add ui/components/runControlFacts.js tests/ui/components/tst_run_control_facts.qml ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): a Runs row shows its run's controls while it has the cursor; cancel only asks (card 1c268d85)"
```

---

### Task 4: Run detail shows the run's controls

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (imports lines 1-7; signal after line 26; a function after `syntheticAt`; a `UI.RunControls` after `runDetailReason`, ~line 200)
- Test: `tests/ui/screens/tst_run_detail_screen.qml` (stub `runsC` lines 22-41; tests appended before the final `}`)

**Interfaces:**
- Consumes: `UI.RunControls` (Task 2), `ControlFacts.runIdOf/pendingOf/waitingOf/errorOf` (Task 3), the store fields listed in Task 3.
- Produces: `RunDetailScreen` signal `cancelRequested(string runId)`, function `requestControl(action)`, child `runDetailControls`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/screens/tst_run_detail_screen.qml`, extend the stub `runsC`. Replace:

```qml
      function refreshLogs() { rs.refreshed += 1 }
    }
  }
```

with:

```qml
      function refreshLogs() { rs.refreshed += 1 }
      // The control surface the header reads (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
    }
  }
```

Append before the final `}` of the TestCase:

```qml
  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function ctl(s, name) { return H.find(H.find(s.screen, "runDetailControls"), "runControl" + name) }

  // 17
  function test_a_running_run_offers_pause_and_cancel_without_hover() {
    var s = make(detail()); if (!s) return
    compare(ctl(s, "Pause").visible, true)
    compare(ctl(s, "Pause").text, "Pause")
    compare(ctl(s, "Cancel").visible, true)
    compare(ctl(s, "Resume").visible, false)
    compare(ctl(s, "Caption").visible, false, "Run detail is the run itself, not a card")
  }

  function test_a_parked_run_offers_resume() {
    var s = make([run("run-x-park0002", "stopped", null, {})], "run-x-park0002"); if (!s) return
    compare(ctl(s, "Resume").visible, true)
    compare(ctl(s, "Resume").enabled, true)
    compare(ctl(s, "Pause").visible, false)
  }

  function test_pause_goes_to_the_store_and_cancel_only_asks() {
    var s = make(detail()); if (!s) return
    cancelSpy.target = s.screen
    cancelSpy.clear()
    tap(ctl(s, "Pause"))
    compare(s.runs.controlCalls.join(","), "pause|run-20261004-19efcddc")
    tap(ctl(s, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-20261004-19efcddc")
    compare(s.runs.controlCalls.length, 1, "cancel never reaches the store")
  }

  function test_the_runs_own_error_and_waiting_lines() {
    var s = make(detail()); if (!s) return
    s.runs.lastControlError = "The run no longer exists"
    s.runs.lastControlErrorRunId = "run-other"
    compare(ctl(s, "Error").visible, false, "another run's error")
    s.runs.lastControlErrorRunId = "run-20261004-19efcddc"
    compare(ctl(s, "Error").visible, true)
    compare(ctl(s, "Error").text, "The run no longer exists")
    s.runs.pending = { "run-20261004-19efcddc": "pause" }
    s.runs.stillWaiting = { "run-20261004-19efcddc": true }
    compare(ctl(s, "Pause").text, "Pause requested…")
    compare(ctl(s, "Waiting").visible, true)
  }

  // 18
  function test_a_done_run_shows_no_controls() {
    var s = make([run("run-x-done0003", "done", null, {})], "run-x-done0003"); if (!s) return
    compare(ctl(s, "Buttons").visible, false)
    compare(H.find(s.screen, "runDetailControls").height, 0)
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: the five new tests FAIL (`runDetailControls` not found → `TypeError: Cannot read property 'visible' of null`); existing tests pass; exit 1.

- [ ] **Step 3: Wire the controls into `RunDetailScreen.qml`**

Imports (lines 1-7) become:

```qml
import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T
```

Replace:

```qml
  // The panel scrolls; Panel wires this like every other screen's.
  signal revealRequested(var item)
```

with:

```qml
  // The panel scrolls; Panel wires this like every other screen's.
  signal revealRequested(var item)
  // The run's Cancel was clicked. Cancelling needs a typed confirmation, which
  // is the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)
```

After the `syntheticAt` function, add:

```qml

  // A control button: pause and resume go straight to the store, a cancel
  // only asks (cancelRequested).
  function requestControl(action) {
    var id = ControlFacts.runIdOf(screen.run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else screen.app.runs.control(action, id)
  }
```

Directly after the `runDetailReason` `UI.ThemedText { … }` block and before `Repeater { model: screen.tree.stories.length … }`, add:

```qml

    UI.RunControls {
      objectName: "runDetailControls"
      width: parent.width
      theme: screen.theme
      run: screen.run
      pendingAction: ControlFacts.pendingOf(screen.app.runs.pending, screen.run)
      waiting: ControlFacts.waitingOf(screen.app.runs.stillWaiting, screen.run)
      waitingText: screen.app.runs.stillWaitingText
      errorText: ControlFacts.errorOf(screen.app.runs.lastControlError, screen.app.runs.lastControlErrorRunId, screen.run)
      wholeRun: false
      showButtons: true
      onActionRequested: function(action) { screen.requestControl(action) }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: `0 failed`, no TypeError lines, exit 0. Also `bash tests/run.sh tst_runs_flow` → `0 failed` (the real `RunStore` carries every field the screen now reads).

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(runs): Run detail shows the run's controls under its header; cancel only asks (card 1c268d85)"
```

---

### Task 5: The card detail's RUNS rows get whole-run controls

**Files:**
- Modify: `ui/screens/CardDetailScreen.qml` (imports lines 1-8; signal after line 23; a function after `nowMs`, ~line 35; `CardRunRow` lines 187-241)
- Test: `tests/ui/screens/tst_card_detail_screen.qml` (append before the final `}`)

**Interfaces:**
- Consumes: `UI.RunControls` (Task 2), `ControlFacts.*` (Task 3), the real `App` / `RunStore` (`app.runs.pending`, `app.runs.controlRunners` -- in-flight requests, each with `.runId` and `.action`, `app.runs.project`), `detailCard.card.depth` (0 milestone, 1 story, 2+ subtask; `Board.kindLabel`).
- Produces: `CardDetailScreen` (`detailCard`) signal `cancelRequested(string runId)`, function `requestControl(action, run)`; each `CardRunRow` holds `cardRunControls<modelData>`.

- [ ] **Step 1: Write the failing tests**

Append before the final `}` of `tests/ui/screens/tst_card_detail_screen.qml` (after `test_clicking_a_run_row_opens_run_detail_and_back_returns_to_the_card`):

```qml

  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function rc(s, i, name) { return H.find(H.find(s, "cardRunControls" + i), "runControl" + name) }

  // 19
  function test_a_story_cards_live_run_offers_whole_run_controls() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(rc(s, 0, "Pause").visible, true)
    compare(rc(s, 0, "Pause").text, "Pause run")
    compare(rc(s, 0, "Cancel").text, "Cancel run")
    compare(rc(s, 0, "Resume").visible, false)
    compare(rc(s, 0, "Caption").visible, true)
    compare(rc(s, 0, "Caption").text, "applies to the whole run")
    compare(rc(s, 1, "Buttons").visible, false, "the done run is history: no controls")
    compare(H.find(s, "cardRunControls1").height, 0)
  }

  function test_a_subtask_card_also_says_whole_run() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("t1")
    wait(50)
    compare(rc(s, 0, "Pause").text, "Pause run")
    compare(rc(s, 0, "Caption").visible, true)
  }

  // 20
  function test_a_milestone_cards_run_rows_use_the_plain_labels() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("m1")
    wait(50)
    compare(rc(s, 0, "Pause").text, "Pause")
    compare(rc(s, 0, "Cancel").text, "Cancel")
    compare(rc(s, 0, "Caption").visible, false)
  }

  // 21
  function test_pause_run_starts_a_request_without_opening_the_run() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(s.app.runs.project, "/home/u/a", "control() refuses without a project")
    mouseClick(rc(s, 0, "Pause"))
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.controlRunners.length, 1)
    compare(s.app.runs.controlRunners[0].action, "pause")
    compare(s.app.runs.controlRunners[0].runId, "run-0000000000a1")
    compare(s.app.nav.viewMode, "entry", "the button is not the row")
    compare(rc(s, 0, "Pause").text, "Pause requested…")
    compare(rc(s, 0, "Pause").enabled, false)
  }

  function test_cancel_run_asks_the_owner_and_starts_nothing() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    cancelSpy.target = s
    cancelSpy.clear()
    mouseClick(rc(s, 0, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-0000000000a1")
    compare(s.app.runs.controlRunners.length, 0)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.nav.viewMode, "entry")
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: the five new tests FAIL (`cardRunControls0` not found → `TypeError: Cannot read property 'visible' of null`); existing tests pass; exit 1.

- [ ] **Step 3: Wire the controls into `CardDetailScreen.qml`**

Imports (lines 1-8) become:

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T
```

Replace:

```qml
  // The panel scrolls; a link row that takes the cursor asks for it here.
  signal revealRequested(var item)
```

with:

```qml
  // The panel scrolls; a link row that takes the cursor asks for it here.
  signal revealRequested(var item)
  // A run's Cancel was clicked. Cancelling needs a typed confirmation, which is
  // the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)
```

After `readonly property real nowMs: detailCard.touchingRuns ? Date.now() : 0`, add:

```qml

  // A run row's control button: pause and resume go straight to the store, a
  // cancel only asks (cancelRequested).
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") detailCard.cancelRequested(id)
    else detailCard.app.runs.control(action, id)
  }
```

In `component CardRunRow`, after its `Row { … }` (the last child, ending just before the component's closing `}`), add:

```qml

    // A story or subtask card shares its run with its siblings: the labels say
    // so ("Pause run") and the caption spells it out. A finished run shows
    // nothing, so a merged card's history reads as before.
    actions: [
      UI.RunControls {
        objectName: "cardRunControls" + runRow.modelData
        width: parent.width
        theme: detailCard.theme
        run: runRow.run
        pendingAction: ControlFacts.pendingOf(detailCard.app.runs.pending, runRow.run)
        waiting: ControlFacts.waitingOf(detailCard.app.runs.stillWaiting, runRow.run)
        waitingText: detailCard.app.runs.stillWaitingText
        errorText: ControlFacts.errorOf(detailCard.app.runs.lastControlError, detailCard.app.runs.lastControlErrorRunId, runRow.run)
        wholeRun: !!detailCard.card && detailCard.card.depth >= 1
        showButtons: true
        onActionRequested: function(action) { detailCard.requestControl(action, runRow.run) }
      }
    ]
```

Also update the `CardRunRow` header comment's last sentence. Replace:

```qml
  // phase and age. Mouse-activated only (`index` stays -1): the keyboard's link
  // list is the card's brd links. A click opens Run detail, whose Back comes
  // back here; a run that vanished meanwhile opens nothing.
```

with:

```qml
  // phase and age, and its RunControls under them. Mouse-activated only
  // (`index` stays -1): the keyboard's link list is the card's brd links. A
  // click opens Run detail, whose Back comes back here; a run that vanished
  // meanwhile opens nothing. A click on a control button never opens the run.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: `0 failed`, no TypeError lines, exit 0 (including the existing `test_clicking_a_run_row_opens_run_detail_and_back_returns_to_the_card`, which clicks the done run's row: it has no controls, so its centre is still the row).

- [ ] **Step 5: Commit**

```bash
git add ui/screens/CardDetailScreen.qml tests/ui/screens/tst_card_detail_screen.qml
git commit -m "feat(runs): a card's RUNS rows show their run's controls, as whole-run controls on a story or subtask (card 1c268d85)"
```

---

### Task 6: The pause flow through the whole panel, and the architecture doc

**Files:**
- Test: `tests/ui/tst_runs_flow.qml` (append before the final `}`)
- Modify: `docs/architecture.md` (line 112 `ListRow` entry; the `RunMark` entry ending line 133; the run screens paragraph, line 145)

**Interfaces:**
- Consumes: everything above, through the real `Panel` → `App` → `RunStore`: `p.app.runs.controlRunners[i].current` (the request's Process; set `outText`, call `exited(code)`), `p.app.runs.snapshotRunner.current` (the snapshot Process the ok reply launched), `p.app.runs.pending`.
- Produces: nothing new.

This task's test exercises code that Tasks 1-5 already built, so it is expected to pass on first run; it is the integration check the spec's flow tier asks for (parent spec line 159). If it fails, the failure is a real integration bug in Tasks 1-5: fix it there (with its own failing unit test first), not in this test.

- [ ] **Step 1: Write the flow test**

Append before the final `}` of `tests/ui/tst_runs_flow.qml`:

```qml

  // ---- run controls (S2 4.2): pause -> requested -> parked, then a refused resume

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // One runs-snapshot.py entry: the `am runs` summary whose `status` the
  // helper replaced with the `am status` data. workflow "task" makes a resume
  // skip the run-settings read.
  function snapEntry(id, runStatus, live, milestone) {
    var control = live === null ? {} : { lease: { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live } }
    return { id: id, workflow: "task", repo_dir: "/home/u/a", started_at: "",
             status: { run: { id: id, status: runStatus, milestone_id: milestone },
                       rows: [], stories: [], subtasks: [], control: control } }
  }

  function snapOk(entries) { return JSON.stringify({ ok: true, runs: entries, data_dir: "/d" }) + "\n" }

  function controlOf(p, name) { return H.find(H.find(p, "runRowControls0"), "runControl" + name) }

  // 22
  function test_pause_is_requested_then_settled_by_a_parked_snapshot_and_a_refusal_shows_inline() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    verify(row, "the running run's row")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(p.app.nav.cursorIndex, 0)
    wait(50)

    var pause = controlOf(p, "Pause")
    compare(pause.visible, true)
    compare(pause.enabled, true)
    mouseClick(pause)
    compare(p.app.nav.viewMode, "runs", "the button did not open the run")
    compare(p.app.runs.pending["run-0000000000a1"], "pause")
    compare(pause.text, "Pause requested…")
    compare(pause.enabled, false)
    compare(p.app.runs.controlRunners.length, 1)

    reply(p.app.runs.controlRunners[0].current,
          JSON.stringify({ ok: true, data: { run_id: "run-0000000000a1", command: "pause", requested_at: "t1" } }) + "\n", 0)
    compare(p.app.runs.pending["run-0000000000a1"], "pause", "acknowledged, still pending until a snapshot")
    var snap = p.app.runs.snapshotRunner.current
    verify(snap, "the ok reply fetched the runs again")
    reply(snap, snapOk([snapEntry("run-0000000000a1", "stopped", null, "alpha"),
                        snapEntry("run-0000000000b2", "escalated", null, "beta")]), 0)
    compare(p.app.runs.pending["run-0000000000a1"], undefined, "parked: the request settled")
    wait(50)

    var resume = controlOf(p, "Resume")
    compare(resume.visible, true, "the parked run's row offers Resume")
    compare(resume.enabled, true)
    compare(controlOf(p, "Pause").visible, false)

    wait(450)
    mouseClick(resume)
    compare(p.app.runs.pending["run-0000000000a1"], "resume")
    compare(p.app.runs.controlRunners.length, 1)
    reply(p.app.runs.controlRunners[0].current,
          JSON.stringify({ ok: false, error: { type: "NotAcceptingError", message: "run is in integrate" } }) + "\n", 0)
    var error = controlOf(p, "Error")
    compare(error.visible, true)
    compare(error.text, "Integrate is running; it cannot be paused or cancelled")
    compare(controlOf(p, "Resume").enabled, true, "the buttons come back")
    compare(controlOf(p, "Resume").text, "Resume")
    compare(H.find(H.find(p, "runRowControls1"), "runControlError").visible, false, "only under that run")
  }
```

- [ ] **Step 2: Run it**

Run: `bash tests/run.sh tst_runs_flow`
Expected: `0 failed`, no TypeError lines, exit 0.

- [ ] **Step 3: Update `docs/architecture.md`**

Replace (line 112):

```
`TypedConfirmDialog`, `ListRow` (hover / keyboard cursor / reveal),
```

with:

```
`TypedConfirmDialog`, `ListRow` (hover / keyboard cursor / reveal; its
`actions` slot holds items under the content, stacked above the row's
MouseArea so a button there takes its own click -- a click anywhere in that
strip, a disabled button included, never activates the row -- and with nothing
in it the row is exactly as tall as before),
```

Replace the end of the `RunMark` entry (line 133):

```
`RunMark` (one card's run mark on the Board and the Graph: a `RunBadge` inside the wrapper that owns the dimming -- a dimmed winner (a finished run speaking for the card) or stale run data is drawn at half opacity and never pulses; the owner hands it `cardRunState` and `rollup`, or null for no mark, and never brd status),
```

with:

```
`RunMark` (one card's run mark on the Board and the Graph: a `RunBadge` inside the wrapper that owns the dimming -- a dimmed winner (a finished run speaking for the card) or stale run data is drawn at half opacity and never pulses; the owner hands it `cardRunState` and `rollup`, or null for no mark, and never brd status),
`RunControls` (one run's `ActionButton`s -- Pause `⏸`, Resume `⟳`, Cancel `⊘` in `danger`, glyphs from `runGlyphs.js` -- with at most one of Pause and Resume: Pause on a running run, Resume on a parked, escalated or dead one, and a pending request keeps its own button reading `… requested…`; enabled and tooltip from `Runs.controls(run)`, every button disabled while a request is pending; a reason line repeats the shown disabled buttons' reasons, because a disabled shell Button gets no hover and so no tooltip; `wholeRun` adds `run` to the labels and an `applies to the whole run` caption; then the still-waiting line and the control error in `urgent`. A finished, unknown or missing run shows nothing and the component is 0 tall. Presentation only, like `RunIndicator`: the owner passes the run, `pendingAction`, `waiting`, `waitingText`, `errorText` and `showButtons`, and a click on an enabled button emits `actionRequested(action)`. `runControlFacts.js` reads `pending`, `stillWaiting` and the control error for one run with own-key checks, for the owners),
```

In the run screens paragraph (line 145), replace:

```
A click opens Run detail with `from` `"entry"`; a merged or canceled card still lists its runs, and nothing is listed while am is missing.
```

with:

```
A click opens Run detail with `from` `"entry"`; a merged or canceled card still lists its runs, and nothing is listed while am is missing. Each of the three run surfaces carries a `RunControls` per run: a Runs row in its `ListRow.actions`, showing the buttons while the row has the cursor (hover moves the cursor) or a request is pending; Run detail under the header, always; a card's RUNS row in its `actions`, always, as whole-run controls (`Pause run`, the caption) on a story or subtask card. The still-waiting and error lines show whenever they apply. Pause and Resume call `app.runs.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` -- confirming a cancel is the owner's job, and no screen calls `control("cancel", …)`.
```

- [ ] **Step 4: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest all passed (including `tests/architecture`), every QML file `0 failed`, no TypeError / ReferenceError / `Unable to assign` / `is not a function` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/ui/tst_runs_flow.qml docs/architecture.md
git commit -m "test(runs): pause through the panel is requested, settled by a parked snapshot, and a refused resume shows inline; document RunControls (card 1c268d85)"
```

---

## Self-Review

**Spec coverage.**
- D1 presentation only → Task 2 (no store import; architecture tier run in Task 2 Step 4 and Task 6 Step 4).
- D2 `ListRow.actions` → Task 1 (tests 11, 12 + disabled click + hover).
- D3 cancel only asks → Tasks 3/4/5 (`cancelRequested`, tests 15, 17, cancel test in Task 5); no `control("cancel")` anywhere.
- D4 one slot → Task 2 tests 1, 2, 7.
- D5 finished runs show nothing; Integrate is not finished → Task 2 tests 3, 4; Task 4 test 18; Task 5 test 19.
- D6 glyphs → Task 2 test 1, 2.
- D7 hover/selected on Runs, always elsewhere, pending keeps buttons, lines always → Task 3 tests 13, 16; Tasks 4, 5.
- D8 reason line → Task 2 test 3, 6.
- Behaviour tables (labels, enabled/tooltip) → Task 2 tests 5, 6.
- Errors table: null run (Task 2 test 4 + null test), refused `control()` (the stub returns true; the real store's refusal changes nothing in the UI because every binding reads the store, covered by Task 5's project assertion), `ok:false` re-enables and shows the sentence (Task 6), error of another run (Task 3 test 16, Task 4, Task 6), pending > 30 s (Task 3 test 16, Task 4), Integrate (Task 2 test 3), project switch (bindings only; the store's own tests cover the emptying).
- Spec tests 1-22 → Task 2 (1-10), Task 1 (11-12), Task 3 (13-16), Task 4 (17-18), Task 5 (19-21), Task 6 (22).
- Docs → Task 6 Step 3.

**Placeholder scan.** No TBD/TODO; every code step carries its code.

**Type consistency.** `RunControls` props/signal and child objectNames are the same in Tasks 2-6; `ControlFacts.runIdOf/pendingOf/waitingOf/errorOf` signatures match between Task 3's definition and Tasks 3-5's uses; `requestControl(action, run)` in RunsScreen/CardDetailScreen and `requestControl(action)` in RunDetailScreen (which has one run, `screen.run`); `cancelRequested(string runId)` on all three screens.

**Review Focus.** Five lines above, each with a named test in its owning task.
<!-- task-pipeline: validated -->
