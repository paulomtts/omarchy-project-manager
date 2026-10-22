# Rewire RunControls, the Runs row, the run screens and Panel to the new row design

Card: `d4e1b8b1` "Rewire RunControls/RunRow/RunsScreen/Panel; update detail tests", a subtask of
story `8e2ec6be`.

Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md`, cited below as
**RR** with line numbers. Sibling specs already merged on this branch:
`write-contract-stubs-6f9f8639.md` (**WS**, the action vocabularies and the `visibleActions`
table) and `store-reset-and-close-63efef4f.md` (**SC**, the store's reset control and Close
dialog state).

## Problem

The pieces of the redesign exist but nothing uses them:

- `core/domain/runs.js` has `runLevel` (~line 1238), `visibleActions` (~1260), `controls().close`
  (~1200) and the reset error sentences (~1286).
- `core/stores/RunControlStore.qml` accepts `reset` and holds the Close dialog state:
  `closeRunId`, `closeOpen`, `closeError`, `closeAsk(runId)` (~366), `closeKeep()` (~379),
  `closeConfirm()` (~387).
- `ui/components/RunLevelBadge.qml`, `RunStateBadge.qml`, `CloseRunDialog.qml` and the
  `warn` / `close` / `accent` tones of `ActionButton` exist, with their own tests.

`RunControls.qml` still shows Resume on escalated and dead runs, renders disabled buttons with
a reason line under them, and has no Close or Relaunch. The Runs row still has the state glyph,
the `…<8>` subtitle, the separate state caption and `Open project`. No screen emits a Close, and
Panel mounts no Close dialog.

## Goal

Wire the existing pieces so the user sees RR's row and buttons:

1. `RunControls` renders exactly `Runs.visibleActions(run)` (RR lines 64-76, 118-123).
2. The Runs row has RR's layout (RR lines 23-35, 60-62).
3. Close on any run surface opens the Close dialog; only its Close button resets the run
   (RR lines 101-116).
4. Relaunch on the Runs row reuses Run detail's relaunch path (RR line 121).

## Inherited constraints

- Layering (RR line 21; `tests/architecture/test_layers.py`): `ui/screens/**` and
  `ui/components/**` import no `core/stores`; they take `app` or props. `RunControls` takes props
  only and reads no `app`.
- Vocabularies (WS lines 72-80; `runs.js` comment above `controls`, ~line 1189): the UI says
  `pause`, `resume`, `cancel`, `close`, `relaunch`; the store says `pause`, `resume`, `cancel`,
  `reset`. UI `close` is store `reset`. `relaunch` is UI only and never reaches
  `app.runControl.control`. **No UI code calls `control("close", …)` or `control("reset", …)`;
  only `closeConfirm()` starts a reset.**
- The Close dialog's dismiss method is `closeKeep()`, not RR's `closeCancel()`, which already
  closes the cancel dialog (SC, "Deviation from RR").
- Button labels are exact: `Cancel`, `Pause`, `Close`, `Relaunch`, `Resume`; no ellipsis except
  a pending request's `requested…` label (RR line 66, RR line 97).
- Tones (RR lines 68-77): Cancel `danger`, Pause `warn`, Close `close`, Resume and Relaunch
  `accent`.
- The filter chips, group headers, Show older, `projectErrorC` and the cursor are unchanged, and
  their existing tests pass **unmodified** (RR lines 17-18, 133).
- Cancel still goes through `cancelRequested` and the typed `TypedConfirmDialog`, unchanged
  (RR line 78).
- Buttons on the Runs row show only while the row has the cursor (RR line 35).

## Decisions where RR is silent or does not fit the code

1. **The Close dialog is mounted by `Panel`, not by `RunsScreen`** (RR line 108 says
   `RunsScreen`). The cancel dialog it is meant to sit next to lives in `ui/Panel.qml`
   (`runCancelModal`, ~line 834), a screen sits inside the panel's scroll so a `z: 100` overlay
   in it would not cover the panel, and Run detail and Card detail need the same dialog. The
   screens emit `closeRequested(runId)` exactly as they emit `cancelRequested(runId)`; Panel
   answers with `app.runControl.closeAsk(runId)`.
2. **A pending request is the one exception to "no disabled buttons".** While a request is
   pending for the run, the button row shows only that request's button, labelled
   `<Word> requested…`, disabled, as a progress marker rather than an action. With nothing
   pending, no button is ever disabled.
3. **Run detail and Card detail hide `RunControls`' Relaunch** (new prop
   `relaunchShown: false`). Run detail already has a Relaunch in its stop-reason block
   (`RunDetailScreen.qml` ~391-394), gated by `offersRelaunch` and disabled outside the open
   project with its own reason; a second Relaunch would duplicate it. Card detail has no relaunch
   path, and a click on a run row there opens Run detail. On both screens an escalated or dead
   run therefore shows only Close; Resume disappears there as RR line 122 requires.
4. **Card detail is in scope** though the card title does not name it: it is the third consumer of
   `RunControls` (`CardDetailScreen.qml` ~296). Without wiring, its Close would reach
   `control("close", …)`, which the store refuses silently. It gets `closeRequested` like the
   other two screens.
5. **Row id** (RR line 32, open question 1 left at 8): the first 8 characters of
   `run.milestone_id` when that is a non-empty string; else the last 8 characters of `run.id`
   when that is a string; else `""`. Raw, no `…`. (am's run ids end with the milestone UUID's
   first 8 characters, so the fallback reads the same on real data.) `Runs.shortId` and
   `Runs.runSubtitle` are unchanged: the cancel dialog, Run detail and Card detail keep `…<8>`.
6. **Shortcuts:** `ui/Shortcuts.qml` treats the open Close dialog as a modal (no global
   shortcuts, run keys or `d` under it) and Escape closes it with `closeKeep()`. No new key
   starts a Close; `p` / `r` / `c` are unchanged.
7. **`openIn` is left blank** and `busy` is `false`: the store exposes neither (RR line 106
   allows omitting the sentence).
8. **Button position is unchanged**: the buttons stay where `ListRow.actions` puts them today.
   RR's diagram (line 28) is illustrative.

## Behavior

### `ui/components/RunControls.qml`

Props: `theme`, `run`, `pendingAction` (store vocabulary: `""`, `pause`, `resume`, `cancel`,
`reset`), `waiting`, `waitingText`, `errorText`, `wholeRun`, `showButtons` (all as today), and new
`relaunchShown` (bool, default `true`). Signal `actionRequested(string action)` with a UI action
name.

- **Shown actions.** `Runs.visibleActions(run)`, in that order, minus `relaunch` when
  `relaunchShown` is false. Per WS's table: running → Cancel, Pause; parked → Close, Resume;
  escalated and dead → Close, Relaunch; running in Integrate → none; parked in Integrate →
  Resume; escalated or dead in Integrate → Relaunch; done, cancelled, unknown, `null`,
  `undefined` → none.
- **Pending request.** With `pendingAction` not `""`, the row shows exactly one button: the
  pending action's (`reset` → the Close button), whatever the run's state now is, labelled
  `Pause requested…`, `Resume requested…`, `Cancel requested…` or `Close requested…`, disabled,
  tooltip `Waiting for the run to act on the request`. A click on it emits nothing. An unknown
  `pendingAction` (anything else non-empty) shows no button.
- **When the row shows.** `(showButtons && shown actions not empty) || a pending button shows`.
  Nothing to show → the button row is hidden; with no caption, waiting or error line the
  component is 0 tall.
- **Buttons.** objectNames `runControlCancel` (tone `danger`), `runControlPause` (`warn`),
  `runControlClose` (`close`), `runControlResume` (`accent`), `runControlRelaunch` (`accent`).
  Labels `Cancel`, `Pause`, `Close`, `Resume`, `Relaunch`; with `wholeRun` each gets ` run`
  (`Pause run`, `Close run`, …) as `Pause run` does today. No icon glyph (`iconText` empty;
  `runGlyphs.js` is no longer imported). Every shown non-pending button is enabled, has an empty
  tooltip, and a click emits `actionRequested(<name>)` once with `cancel`, `pause`, `close`,
  `resume` or `relaunch`.
- **Lines under the buttons.** `runControlCaption` ("applies to the whole run", while the button
  row shows and `wholeRun`), `runControlWaiting` and `runControlError` behave as today.
  `runControlReason` and the `resumable` / `pauseShown` / `resumeShown` / `reasonText` /
  `enabledOf` reason logic are removed.
- The header comment describes the new behavior (visibleActions, pending marker, relaunchShown,
  no reason line).

### `ui/screens/RunsScreen.qml` — the row (`RunRow`)

First line, left to right:

- `runRowId<i>` (caption, `dim`): the row id of decision 5.
- `runRowTitle<i>`: `Runs.runTitle(run, Runs.titlesOfRun(run, app.runTitles.titlesByRoot))` as
  today; it takes the width the others leave and elides.
- `runRowLevel<i>`: a `UI.RunLevelBadge` with `level: Runs.runLevel(run)`, always shown.
- `runRowStateBadge<i>`: a `UI.RunStateBadge` with `state: Runs.runState(run)`; visible for
  running and escalated only (the component's own rule).
- `runRowMeta<i>` (caption), right-aligned on the same line. Its text:
  - dead: `screen.stateText("dead", age)` unchanged — `dead - lease lost`,
    `dead - lease lost just now` or `dead - lease lost <age> ago` — in `urgent`.
  - every other state: the non-empty parts of [progress, phase, age] joined by ` · `, in `dim`.
    Progress is `done/total` when `total > 0`; phase is `Runs.currentPhase(run)`, else `parked`
    for a parked run; age is `Runs.runAgeText(run, nowMs)`. A parked run with 11 subtasks, none
    done, no started phase and a 5-day age reads `0/11 · parked · 5d`; a running one
    `3/8 · explore · 2h`. All parts empty → `""` and hidden.
  - `stateText` loses its parked branch (it returns `""` for every state but dead).

Second line: `runRowReason<i>`, `Runs.escalationReason(run)`, visible for escalated runs only,
flush left with the first line (no indent), colour `theme.warn` (today `urgent`), word-wrapped.

Removed: `runRowGlyph<i>`, the `runSubtitle` id, `runRowProgress<i>`, `runRowPhase<i>`,
`runRowAge<i>`, `runRowState<i>`, `runRowOpenProject<i>`, the row's `openTarget`, the functions
`openProjectTargetOf` and `registryEntryOf` (no other caller), and the `runGlyphs.js` import. The
screen no longer reads `app.projects`.

Actions under the row: one `RunControls` (`runRowControls<i>`), `showButtons: row.hasCursor`,
`relaunchShown: true`, other props as today.

### `RunsScreen.requestControl(action, run)` and relaunch

New signal `closeRequested(string runId)` next to `cancelRequested`.

- No run id → nothing.
- `cancel` → `cancelRequested(id)`; `close` → `closeRequested(id)`; `relaunch` →
  `screen.relaunch(run)`; anything else → `app.runControl.control(action, id)`.

`screen.relaunch(run)`, Run detail's path applied to a row's run:

1. `report = Runs.stopReport(run)`; no report or `report.relaunch` not an object → flash
   `This run has nothing to relaunch` and stop.
2. The run is not in the open project (its `project.root` and the open root, compared by
   `rootKey`, differ, or no project is open) → flash `Open this run's project to relaunch it`
   and stop.
3. The card `report.relaunch.cardId` is not an own key of `app.board.cardMap` → flash
   `The card to relaunch is no longer on the board` and stop.
4. Otherwise `app.runDispatch.relaunchOpenFor(card, app.board.cardMap, report.relaunch)`: the
   dispatch dialog opens prefilled; nothing starts until Start run.

Flashes go through `app.runControl.flash(text)` and show in the Runs footer as refused keys do.

### `ui/screens/RunDetailScreen.qml`

- New signal `closeRequested(string runId)`. `requestControl`: `cancel` → `cancelRequested`,
  `close` → `closeRequested`, `relaunch` → `screen.relaunch()` (defensive; not reachable with
  `relaunchShown: false`), else `control(action, id)`.
- `runDetailControls` gets `relaunchShown: false`. Layout, the stop-reason block and its Relaunch
  are unchanged.

### `ui/screens/CardDetailScreen.qml`

- New signal `closeRequested(string runId)`. `requestControl(action, run)`: `cancel` →
  `cancelRequested`, `close` → `closeRequested`, `relaunch` → nothing, else `control`.
- `cardRunControls<i>` gets `relaunchShown: false`. Layout unchanged.

### `ui/Panel.qml`

- `RunsScreen`, `RunDetailScreen` and `CardDetailScreen`:
  `onCloseRequested: function(runId) { appStores.runControl.closeAsk(runId) }`.
- A `CloseRunDialog` next to `runCancelModal`, `objectName: "runCloseModal"`, `anchors.fill:
  parent`, `shown: appStores.runControl.closeOpen`, `runTitle` the listed run's
  `Runs.runTitle(run, Runs.titlesOfRun(run, appStores.runTitles.titlesByRoot))` (`""` when the
  run is not listed, which reads `Close this run?`), `openIn: ""`, `busy: false`,
  `error: appStores.runControl.closeError`, `theme: panelTheme`,
  `onConfirmRequested: appStores.runControl.closeConfirm()`,
  `onCancelRequested: appStores.runControl.closeKeep()`.
- Focus: `focusItem` puts `closeOpen ? runCloseModal.focusItem` immediately before the
  `cancelOpen` entry; the `runControl` `Connections` adds `onCloseOpenChanged` →
  `root.focusForView()`, so the dialog takes the focus when it opens and gives it back on close.

### `ui/Shortcuts.qml`

- `modalOpen()` is true while `app.runControl.closeOpen`.
- `closeRequested()` (Escape): an open Close dialog is closed with `app.runControl.closeKeep()`,
  checked immediately before the cancel confirmation, matching the focus order.

### Docs

`docs/architecture.md` (the run-screens paragraph, ~line 186) and `README.md` (the Runs bullet,
~line 154) describe the new row (id, level and state badges, meta, warn reason line, no glyph,
no Open project), the button table, Close and its dialog, and Relaunch on the Runs row. Every
other sentence stays. `README.md` must still name no store (`tests/architecture/test_run_store_docs.py`
`README_TOKENS`: no `RunControlStore`, `RunStore`, …), and `docs/architecture.md` must keep every
`app.<handle>` and store fact that test checks; the RunsScreen sentence drops `app.projects` only if
nothing else there claims it.

## Error paths

| Situation | Observable result |
|---|---|
| Close clicked on a run the store refuses (`refusalOf("reset", id)` not empty: not listed, no repo, request pending, state changed) | `closeAsk` flashes the reason in the footer / `runDetailFlash`; no dialog. |
| Close dialog confirmed but the run changed under it | Dialog stays open with `closeError` in urgent (`closeDialogError`). |
| Reset started then failed in am | Dialog already closed; the row's `runControlError` shows `controlError(envelope, "reset")` (e.g. `This run cannot be closed (it is finished or already cancelled).`). |
| Relaunch on a run with no relaunch target / of another project / whose card left the board | Flash, nothing opens (sentences above). |
| `run` null, garbage or unknown state | `RunControls` shows nothing and is 0 tall; the row shows the `milestone` level badge, no state badge, an empty or partial meta, never throws. |
| Close and Cancel dialogs both requested | Each is its own store state; focus and Escape take the Close dialog first. |

## Out of scope

- Domain helpers (`runLevel`, `visibleActions`, `controls`, `controlError`), the store, the
  backend `run-control.py reset`, `RunLevelBadge`, `RunStateBadge`, `CloseRunDialog`, the
  `ActionButton` tones and theme tokens: sibling cards, already merged. Their tests are not
  edited.
- The filter chips, headers, Show older, cursor and their tests.
- A keyboard key for Close; changing `p` / `r` / `c`.
- `openIn` in the dialog; a busy state for a reset in flight.
- RR open question 1 (12-character id) and bulk selection.
- Run detail and Card detail layouts beyond the RunControls props above.

## Tests

`tests/run.sh` runs pytest then every `tests/**/tst_*.qml` with `qmltestrunner` against a mirrored
copy; it takes several minutes, so run it in the background (`timeout 900 bash tests/run.sh`).
A single QML file runs with `bash tests/run.sh <substring>` (pytest still runs first).

### Component tier — `tests/ui/components/tst_run_controls.qml` (rewrite)

The component's contract is its props and signal; these need no store or screen.

1. Each state shows exactly `visibleActions`' buttons in order: running → Cancel, Pause;
   parked → Close, Resume; escalated → Close, Relaunch; dead → Close, Relaunch (check visible
   children of `runControlButtons` in x order).
2. Integrate: running shows nothing (0 tall); parked shows Resume only; escalated/dead show
   Relaunch only.
3. done, cancelled, unknown, `null` show nothing and the component is 0 tall.
4. No pending request: every visible button is enabled, for every state of 1-2 (RR line 131,
   "no disabled button anywhere").
5. Resume is never visible on escalated or dead runs, including an escalated card run.
6. Labels exact and tones: Cancel/`danger`, Pause/`warn`, Close/`close`, Resume/`accent`,
   Relaunch/`accent`; `iconText` empty on all.
7. `wholeRun`: `Pause run`, `Cancel run`, `Close run`, `Resume run`; caption shows with the
   buttons only.
8. `relaunchShown: false`: escalated shows Close only; Integrate-escalated shows nothing.
9. Click on each shown button emits `actionRequested` once with its UI name (`close` for Close,
   `relaunch` for Relaunch; never `reset`).
10. Pending `reset` on a parked run: only `runControlClose`, `Close requested…`, disabled,
    tooltip `Waiting for the run to act on the request`; a click emits nothing.
11. Pending `pause` on a run now parked (state moved on): only `Pause requested…`; pending
    `resume` on a running run: only `Resume requested…`; pending `cancel`: only
    `Cancel requested…`.
12. Pending shows even with `showButtons: false`; `showButtons: false` and nothing pending hides
    the buttons but not the error line.
13. Pending unknown value (`"close"`, `"bogus"`) shows no button.
14. No object named `runControlReason` exists.
15. Waiting and error lines unchanged (keep today's two tests).
16. A null theme and null run do not throw (keep).

### Screen tier — `tests/ui/screens/tst_runs_screen.qml` (update; chip tests untouched)

Screens get a stub `app`; this tier checks the row and the screen's signals without Panel.

1. Row id: `milestone_id` `"e795ad19-c81f-…"` → `e795ad19`; no `milestone_id` → last 8 of
   `id` raw (existing `…live0001` expectations become `live0001`); non-string id and no
   milestone → `""`. No `…` anywhere in `runRowId<i>`.
2. Level badge: milestone, story (`story_id: "s1"`) and subtask (`workflow: "task"`) runs show
   `MILESTONE`, `STORY`, `SUBTASK` in `runRowLevel<i>`.
3. State badge: visible with `RUNNING` / `ESCALATED` for those states; not visible for parked,
   dead, done, cancelled.
4. Meta: running `3/8 · explore · <age>`; parked with no phase `0/11 · parked · <age>`;
   dead `dead - lease lost <age> ago` in urgent; a run with no subtasks, no phase and no start
   → hidden. Ages compared against `Runs.runAgeText(run, screen.nowMs)`.
5. Reason line: escalated only, colour `theme.warn`, `x` equal to the id's `x` (flush left).
6. Removed objects: no `runRowGlyph<i>`, `runRowOpenProject<i>`, `runRowState<i>`,
   `runRowProgress<i>`, `runRowPhase<i>`, `runRowAge<i>` for any row (replaces the glyph and
   Open project tests; the unknown-state test at ~1464 asserts the badges instead of the glyph).
7. Buttons only with the cursor: no `runRowControls<i>` button visible without the cursor; with
   it, the table's buttons.
8. `requestControl`: `cancel` emits `cancelRequested(id)` once; `close` emits
   `closeRequested(id)` once and calls no `control`; `pause`/`resume` call
   `app.runControl.control(action, id)`; `relaunch` never calls `control`.
9. Relaunch: no target → flash `This run has nothing to relaunch`; other project → flash
   `Open this run's project to relaunch it`; card gone → flash
   `The card to relaunch is no longer on the board`; card present → `relaunchOpenFor` called
   once with the card, the card map and the report's relaunch (stub records the call).
10. Every existing chip, header, Show older and cursor test passes unmodified.

### Screen tier — `tests/ui/screens/tst_run_detail_screen.qml` (update)

1. Escalated and dead runs: `runDetailControls` shows Close only (no Resume, no Relaunch); the
   stop block's Relaunch is unchanged.
2. Parked: Close and Resume; running: Cancel and Pause.
3. No `runControlReason`; no disabled button without a pending request.
4. Close emits `closeRequested(id)` once and calls no `control`.
5. Existing pending, waiting, error and stop-block tests keep passing (labels updated only where
   they asserted Resume on escalated/dead or the reason line).

### Screen tier — `tests/ui/screens/tst_card_detail_screen.qml` (update)

1. A card's escalated run row shows Close only; a parked one Close and Resume; a story card's
   labels read `Close run`.
2. Close emits `closeRequested(id)`; no `control` call.

### Flow tier — `tests/ui/tst_runs_flow.qml` (update; Panel with real stores, stubbed runners)

This tier proves the screen → Panel → store → dialog wiring, which no lower tier can.

1. On the Runs list, cursor on a parked run, click `runControlClose`: `runCloseModal` shows,
   titled `Close "<run title>"?`, and has the focus; no reset runner started.
2. `closeDialogKeep` dismisses it (`closeOpen` false), focus returns; Escape does the same.
3. `closeDialogAccept` starts exactly one `reset` request for that run (one new entry in
   `controlRunners`, its command naming `run-control.py`, `reset`, the run id and its repo as the
   store builds it; `pending[id] === "reset"`) and closes the dialog; the row then shows
   `Close requested…`.
4. A run that changes to running under the open dialog: Accept keeps it open with
   `A running run is cancelled, not closed` in `closeDialogError`, no runner.
5. Close on a running run is never offered (no `runControlClose`); a refused `closeAsk` (request
   pending) flashes in the footer and opens nothing.
6. While the Close dialog is open, a global shortcut and `p` / `r` / `c` do nothing.
7. Relaunch on an escalated run of the open project whose target card is on the board opens the
   dispatch dialog prefilled with the run's prefix and base.
8. From Run detail, Close opens the same dialog.
9. Existing cancel-flow tests pass unchanged; tests that clicked Resume on escalated/dead runs are
   changed to parked runs.

### Flow tier — `tests/ui/tst_shortcuts.qml` (add)

1. `modalOpen()` is true while `closeOpen`.
2. Escape with the Close dialog open calls `closeKeep()` and nothing else (no Back, no panel
   close).

### Real-data tier — `tests/ui/tst_runs_real_data.qml` (update)

1. `test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs` reads `runRowMeta0`
   (`3/8 · explore · <age>`) and `runRowMeta1` (`10/10 · <age>`) instead of the removed
   `runRowProgress` / `runRowPhase` objects; real fixtures show `MILESTONE`.

### Architecture tier — pytest, unchanged

`tests/architecture/test_layers.py`, `test_run_store_callers.py`, `test_run_store_docs.py` and
`test_icon_glyphs.py` pass with no edit: no store import in `ui/components` or `ui/screens`.
`tests/core/domain/tst_run_row_contract.qml` passes unmodified.

### Definition of done

`bash tests/run.sh` exits 0.
