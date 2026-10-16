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

---

# Rewire RunControls, the Runs row, the run screens and Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the user see RR's Runs row and buttons: `RunControls` renders exactly `Runs.visibleActions(run)`, the Runs row gets the id / level / state / meta layout, Close on any run surface opens a Panel-mounted Close dialog whose Close button is the only thing that resets a run, and Relaunch on a Runs row reuses Run detail's relaunch path.

**Architecture:** Pure QML wiring of pieces that already exist and are tested (`Runs.visibleActions`, `Runs.runLevel`, `RunControlStore.closeAsk/closeKeep/closeConfirm`, `RunLevelBadge`, `RunStateBadge`, `CloseRunDialog`, the `ActionButton` tones). `RunControls` stays props-only; the three screens emit `closeRequested(runId)` beside `cancelRequested(runId)`; `Panel` answers with `closeAsk` and mounts the dialog next to `runCancelModal`; `Shortcuts` treats the dialog as a modal.

**Tech Stack:** QML (Qt 6, Quickshell `qs.*` modules, stubbed under `tests/stubs` for tests), plain JS libraries (`core/domain/runs.js`), QtTest via `qmltestrunner`, pytest for the architecture tier. All tests run through `bash tests/run.sh [substring]`.

**Spec:** `docs/superpowers/specs/rewire-runcontrols-d4e1b8b1.md` (reproduced above). Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md` (RR).

## Global Constraints

- Layering: `ui/screens/**` and `ui/components/**` import no `core/stores`; `RunControls` takes props only and reads no `app`.
- Vocabularies: the UI says `pause`, `resume`, `cancel`, `close`, `relaunch`; the store says `pause`, `resume`, `cancel`, `reset`. No UI code calls `control("close", …)` or `control("reset", …)`; only `closeConfirm()` starts a reset. `relaunch` never reaches `app.runControl.control`.
- The Close dialog's dismiss method is `closeKeep()` (not `closeCancel()`, which closes the cancel dialog).
- Button labels exact: `Cancel`, `Pause`, `Close`, `Relaunch`, `Resume`; ` run` appended with `wholeRun`; the only ellipsis is a pending request's `<Word> requested…`.
- Tones: Cancel `danger`, Pause `warn`, Close `close`, Resume and Relaunch `accent`. No icon glyph on any run control button.
- Filter chips, group headers, Show older, `projectErrorC` and the cursor are unchanged. Their tests pass with no change except the expected `runRowId<i>` strings: the row id format changes, and spec test 1 makes those literals follow it. Task 2 Step 1 lists each of those edits, scoped to its own function.
- Cancel still goes through `cancelRequested` and the typed `TypedConfirmDialog`, unchanged.
- Buttons on a Runs row show only while the row has the cursor (or a request is pending).
- `Runs.shortId` and `Runs.runSubtitle` are unchanged: the cancel dialog, Run detail and Card detail keep `…<8>`.
- Never `pkill`/`killall`; run the suite with `timeout` (`timeout 900 bash tests/run.sh`).
- `tests/run.sh` fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` line in a QML test's output. No new binding may print one, even for a garbage run.
- Definition of done: `bash tests/run.sh` exits 0.

## Review Focus

1. **A garbage run on a Runs row** (non-object fields, a numeric id, a non-string `milestone_id`, no project): the row renders with id `""` or the id's tail, the `MILESTONE` badge, no state badge, an empty or partial meta, and prints no TypeError. Pinned in Task 2 (`test_malformed_runs_render_without_throwing`).
2. **A relaunch target whose card id is a prototype key** (`constructor`) or missing from the board, and an open root spelled with a trailing `/`: the first flashes `The card to relaunch is no longer on the board`, and the trailing `/` still counts as the run's project. Neither throws. Pinned in Task 3 (`test_relaunch_refusals_flash_why_and_open_nothing`, `test_relaunch_opens_the_prefilled_dispatch_for_a_run_of_the_open_project`).
3. **The run changes state under an open Close dialog** (now running): Close keeps the dialog open with `A running run is cancelled, not closed` and starts no runner. Pinned in Task 5 (`test_a_run_that_starts_running_under_the_dialog_keeps_it_open_with_why`).
4. **Close and Cancel dialogs both open**: the Close dialog has the focus, the first Escape closes only it, and the next Escape closes the cancel confirmation. Pinned in Task 5 (`test_with_both_dialogs_open_the_close_dialog_takes_the_focus_and_escape_first`, `test_escape_closes_the_close_dialog_before_the_cancel_confirmation`).
5. **A pending request outlives the state it was made in** (a pause pending on a run that is now parked, a reset pending): only that request's disabled marker shows, never the new state's buttons beside it. Pinned in Task 1 (`test_a_pending_request_shows_only_its_own_marker_whatever_the_state`) and Task 5 (`Close requested…` on the row after Accept).

---

## File map

| File | Change | Task |
|---|---|---|
| `ui/components/RunControls.qml` | Rewrite: visibleActions, pending marker, `relaunchShown`, five buttons, no reason line, no glyphs | 1 |
| `tests/ui/components/tst_run_controls.qml` | Rewrite | 1 |
| `tests/ui/tst_runs_flow.qml` | Integrate test now expects hidden buttons | 1 |
| `ui/screens/RunsScreen.qml` | New row layout, `rowIdOf`, `metaText`, `stateText` without parked, Open project and glyph removed | 2 |
| `tests/ui/screens/tst_runs_screen.qml` | Row tests rewritten, id literals updated, Open project section removed | 2 |
| `tests/ui/tst_runs_real_data.qml` | Reads `runRowMeta*`, level badge, card id vs row id | 2 |
| `tests/ui/tst_runs_flow.qml` | Two Open project tests removed | 2 |
| `ui/screens/RunsScreen.qml` | `closeRequested`, `requestControl` routing, `relaunch(run)` | 3 |
| `tests/ui/screens/tst_runs_screen.qml` | Stub `flash`, board, dispatch; close / routing / relaunch tests | 3 |
| `ui/screens/RunDetailScreen.qml`, `ui/screens/CardDetailScreen.qml` | `closeRequested`, routing, `relaunchShown: false` | 4 |
| `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/screens/tst_card_detail_screen.qml` | New control tests | 4 |
| `ui/Panel.qml` | `onCloseRequested` ×3, `runCloseModal`, focus chain, Connections | 5 |
| `ui/Shortcuts.qml` | `modalOpen()` and Escape know the Close dialog | 5 |
| `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_shortcuts.qml` | Close dialog flow and keys | 5 |
| `docs/architecture.md`, `README.md` | Describe the new row, buttons, Close, Relaunch | 6 |

How to run tests (every task): `bash tests/run.sh <substring>` runs pytest (about a minute), then only the QML test files whose path contains `<substring>`. A file passes when its `Totals:` line shows `0 failed` and no `TypeError`/`ReferenceError`/… line is printed. The script exits non-zero otherwise.

---

### Task 1: RunControls renders exactly `Runs.visibleActions`

**Files:**
- Modify (rewrite): `ui/components/RunControls.qml`
- Test (rewrite): `tests/ui/components/tst_run_controls.qml`
- Modify: `tests/ui/tst_runs_flow.qml` (function `test_integrate_disables_pause_and_cancel_and_a_key_says_why`, ~line 525)

**Interfaces:**
- Consumes: `Runs.visibleActions(run)` → fresh array of UI action names, from `core/domain/runs.js`. `UI.ActionButton` has `tone` (`danger` | `warn` | `close` | `accent` | anything else), `text`, `iconText`, `tooltipText`, `enabled` and `clicked()`.
- Produces: `RunControls` props `theme`, `run`, `pendingAction` (`""` | `pause` | `resume` | `cancel` | `reset`), `waiting`, `waitingText`, `errorText`, `wholeRun`, `showButtons`, **`relaunchShown` (bool, default `true`)**. Signal `actionRequested(string action)` with `cancel` | `pause` | `close` | `resume` | `relaunch`. objectNames: `runControlButtons` (the Row), `runControlCancel`, `runControlClose`, `runControlPause`, `runControlResume`, `runControlRelaunch`, `runControlCaption`, `runControlWaiting`, `runControlError`. There is no `runControlReason`. Read-only helpers other tasks may read: `shownActions` (array), `requestPending` (bool), `pendingButton` (string UI name or `""`), `buttonsShown` (bool).

- [ ] **Step 1: Write the failing tests (rewrite the component test file)**

Replace the whole content of `tests/ui/components/tst_run_controls.qml` with:

```qml
// tests/ui/components/tst_run_controls.qml
// ui/components/RunControls.qml on its own, with plain run objects and no
// store: exactly Runs.visibleActions' buttons for each run state, in order,
// their labels and tones, the pending-request marker, relaunchShown, the
// caption, waiting and error lines, and the one signal a click emits.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunControls"
  when: windowShown
  visible: true
  width: 400; height: 300

  readonly property string waitingTip: "Waiting for the run to act on the request"
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
  function escalatedCard() {
    var r = escalated()
    r.workflow = "task"
    r.card_id = "t1"
    return r
  }
  // `r` in Integrate: a lease that is not accepting, its liveness kept.
  function integrate(r) {
    r.lease = { pid: 1, host: "h", heartbeat_at: "", accepting: false, live: r.lease ? r.lease.live === true : false }
    return r
  }

  function make(props) {
    var c = createTemporaryObject(controlsC, tc, props || {})
    actionSpy.target = c
    actionSpy.clear()
    wait(20)
    return c
  }

  function part(c, name) { return H.find(c, "runControl" + name) }

  // The visible buttons, left to right, by objectName without "runControl".
  function shown(c) {
    wait(20)   // a Row lays out on the next polish
    var row = part(c, "Buttons")
    var kids = []
    for (var i = 0; i < row.children.length; i++) {
      if (row.children[i].visible) kids.push(row.children[i])
    }
    kids.sort(function(a, b) { return a.x - b.x })
    return kids.map(function(b) { return b.objectName.replace("runControl", "") }).join(",")
  }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // 1 + 5
  function test_each_state_shows_exactly_its_visible_actions_in_order() {
    var cases = [["running", running(), "Cancel,Pause"], ["parked", parked(), "Close,Resume"],
                 ["escalated", escalated(), "Close,Relaunch"], ["dead", dead(), "Close,Relaunch"],
                 ["escalated card", escalatedCard(), "Close,Relaunch"]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1] })
      compare(shown(c), cases[i][2], cases[i][0])
      compare(part(c, "Buttons").visible, true, cases[i][0])
      verify(c.height > 0, cases[i][0])
    }
  }

  // 5
  function test_resume_never_shows_on_an_escalated_or_dead_run() {
    var cases = [["escalated", escalated()], ["dead", dead()], ["escalated card", escalatedCard()],
                 ["integrate escalated", integrate(escalated())], ["integrate dead", integrate(dead())]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1], wholeRun: true })
      compare(part(c, "Resume").visible, false, cases[i][0])
    }
  }

  // 2
  function test_integrate_keeps_only_resume_or_relaunch() {
    var r = make({ run: running(false), wholeRun: true })
    compare(shown(r), "", "running in Integrate")
    compare(part(r, "Buttons").visible, false)
    compare(part(r, "Caption").visible, false)
    compare(r.height, 0)
    compare(shown(make({ run: integrate(parked()) })), "Resume", "parked in Integrate")
    compare(shown(make({ run: integrate(escalated()) })), "Relaunch", "escalated in Integrate")
    compare(shown(make({ run: integrate(dead()) })), "Relaunch", "dead in Integrate")
  }

  // 3 + Review Focus 1 (a malformed run)
  function test_finished_unknown_and_missing_runs_show_nothing() {
    var cases = [["done", run("run-x-done0005", "done", null)],
                 ["cancelled", run("run-x-canc0006", "cancelled", null)],
                 ["unknown", run("run-x-bogus007", "bogus", null)],
                 ["null", null],
                 ["undefined", undefined],
                 ["malformed", { id: 5, status: 7, lease: "x", rows: "y", tree: null }]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1], wholeRun: true })
      compare(shown(c), "", cases[i][0])
      compare(part(c, "Buttons").visible, false, cases[i][0])
      compare(part(c, "Caption").visible, false, cases[i][0])
      compare(c.height, 0, cases[i][0])
    }
  }

  // 4
  function test_with_nothing_pending_every_shown_button_is_enabled() {
    var runs = [running(), parked(), escalated(), dead(), escalatedCard(), integrate(parked()), integrate(escalated())]
    var names = ["Cancel", "Close", "Pause", "Resume", "Relaunch"]
    for (var i = 0; i < runs.length; i++) {
      var c = make({ run: runs[i] })
      for (var n = 0; n < names.length; n++) {
        var b = part(c, names[n])
        if (!b.visible) continue
        compare(b.enabled, true, runs[i].id + " " + names[n])
        compare(b.tooltipText, "", runs[i].id + " " + names[n])
      }
    }
  }

  // 6
  function test_labels_tones_and_no_glyph() {
    var r = make({ run: running() })
    compare(part(r, "Cancel").text, "Cancel")
    compare(part(r, "Cancel").tone, "danger")
    compare(part(r, "Pause").text, "Pause")
    compare(part(r, "Pause").tone, "warn")
    var p = make({ run: parked() })
    compare(part(p, "Close").text, "Close")
    compare(part(p, "Close").tone, "close")
    compare(part(p, "Resume").text, "Resume")
    compare(part(p, "Resume").tone, "accent")
    var e = make({ run: escalated() })
    compare(part(e, "Relaunch").text, "Relaunch")
    compare(part(e, "Relaunch").tone, "accent")
    var names = ["Cancel", "Close", "Pause", "Resume", "Relaunch"]
    for (var n = 0; n < names.length; n++) compare(part(e, names[n]).iconText, "", names[n] + " has no glyph")
  }

  // 7
  function test_whole_run_labels_and_the_caption() {
    var c = make({ run: running(), wholeRun: true })
    compare(part(c, "Pause").text, "Pause run")
    compare(part(c, "Cancel").text, "Cancel run")
    var caption = part(c, "Caption")
    compare(caption.visible, true)
    compare(caption.text, "applies to the whole run")
    c.run = parked()
    compare(part(c, "Close").text, "Close run")
    compare(part(c, "Resume").text, "Resume run")
    c.run = escalated()
    compare(part(c, "Relaunch").text, "Relaunch run")
    c.showButtons = false
    compare(caption.visible, false, "the caption shows with the buttons only")
    c.showButtons = true
    c.wholeRun = false
    compare(caption.visible, false)
    compare(part(c, "Close").text, "Close")
  }

  // 8
  function test_relaunch_shown_false_drops_relaunch() {
    var c = make({ run: escalated(), relaunchShown: false })
    compare(shown(c), "Close")
    c.run = dead()
    compare(shown(c), "Close")
    c.run = parked()
    compare(shown(c), "Close,Resume", "nothing else changes")
    var i = make({ run: integrate(escalated()), relaunchShown: false, wholeRun: true })
    compare(shown(i), "")
    compare(part(i, "Buttons").visible, false)
    compare(i.height, 0)
  }

  // 9
  function test_a_click_asks_for_its_ui_action_once() {
    var c = make({ run: running() })
    tap(part(c, "Cancel"))
    tap(part(c, "Pause"))
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[0][0], "cancel")
    compare(actionSpy.signalArguments[1][0], "pause")

    var p = make({ run: parked() })
    tap(part(p, "Close"))
    tap(part(p, "Resume"))
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[0][0], "close", "never reset")
    compare(actionSpy.signalArguments[1][0], "resume")

    var e = make({ run: escalated() })
    tap(part(e, "Relaunch"))
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "relaunch")
  }

  // 10
  function test_a_pending_reset_is_the_disabled_close_marker() {
    var c = make({ run: parked(), pendingAction: "reset" })
    compare(shown(c), "Close")
    var close = part(c, "Close")
    compare(close.text, "Close requested…")
    compare(close.enabled, false)
    compare(close.tooltipText, tc.waitingTip)
    tap(close)
    compare(actionSpy.count, 0, "the marker is not an action")
  }

  // 11 + Review Focus 5
  function test_a_pending_request_shows_only_its_own_marker_whatever_the_state() {
    var p = make({ run: parked(), pendingAction: "pause" })
    compare(shown(p), "Pause", "the run is parked now; Close and Resume wait")
    compare(part(p, "Pause").text, "Pause requested…")
    compare(part(p, "Pause").enabled, false)

    var r = make({ run: running(), pendingAction: "resume" })
    compare(shown(r), "Resume")
    compare(part(r, "Resume").text, "Resume requested…")

    var k = make({ run: running(), pendingAction: "cancel" })
    compare(shown(k), "Cancel")
    compare(part(k, "Cancel").text, "Cancel requested…")
    compare(part(k, "Cancel").enabled, false)
    compare(part(k, "Cancel").tooltipText, tc.waitingTip)

    var gone = make({ run: run("run-x-canc0006", "cancelled", null), pendingAction: "cancel" })
    compare(shown(gone), "Cancel", "a finished run still shows its pending marker")

    var whole = make({ run: running(), pendingAction: "pause", wholeRun: true })
    compare(part(whole, "Pause").text, "Pause requested…", "the marker never says run")
    tap(part(whole, "Pause"))
    compare(actionSpy.count, 0)
  }

  // 12
  function test_show_buttons_false_hides_the_buttons_but_not_a_marker_or_the_error() {
    var c = make({ run: running(), wholeRun: true, showButtons: false })
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Caption").visible, false)
    compare(c.height, 0)
    c.pendingAction = "pause"
    compare(shown(c), "Pause")
    compare(part(c, "Buttons").visible, true)
    compare(part(c, "Pause").text, "Pause requested…")
    compare(part(c, "Caption").visible, true)
    c.pendingAction = ""
    c.errorText = "The run is not running"
    wait(20)   // a Column re-lays out on the next polish, not synchronously
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Error").visible, true)
    verify(c.height > 0)
  }

  // 13
  function test_an_unknown_pending_value_shows_no_button() {
    var values = ["close", "bogus", "relaunch"]
    for (var i = 0; i < values.length; i++) {
      var c = make({ run: parked(), pendingAction: values[i] })
      compare(shown(c), "", values[i])
      compare(part(c, "Buttons").visible, false, values[i])
    }
  }

  // 14
  function test_there_is_no_reason_line() {
    var cases = [running(), running(false), parked(), escalated(), escalatedCard(), null]
    for (var i = 0; i < cases.length; i++) compare(part(make({ run: cases[i] }), "Reason"), null, "case " + i)
  }

  // 15
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

  // 15
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

  // 16: a view being torn down nulls theme and run while the bindings still
  // run once; tests/run.sh fails on any TypeError this prints.
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
Expected: FAIL. Among others, `test_each_state_shows_exactly_its_visible_actions_in_order` fails on `Close,Resume` vs `Resume,Cancel` or a null `runControlClose`, `test_labels_tones_and_no_glyph` fails on the Pause tone `normal`, and `test_there_is_no_reason_line` fails because `runControlReason` exists.

- [ ] **Step 3: Rewrite `ui/components/RunControls.qml`**

Replace the whole file with:

```qml
import QtQuick
import qs.Commons
import qs.Commons as Cm
import "../../core/domain/runs.js" as Runs
import "../components" as UI
import "../theme" as T

// One run's buttons and the lines under them: "applies to the whole run" on a
// story or subtask card, the store's still-waiting line and the control error
// for this run.
//
// Presentation only, like RunIndicator: it imports no store. The owner passes
// the run and what the store says about it (the action pending for it, whether
// that request is 30 s old, the control error for this run) and decides when
// the buttons show (`showButtons`); a click emits actionRequested with the
// UI's name -- cancel, pause, close, resume or relaunch, never the store's
// reset -- and what that click does is the owner's business.
//
// The buttons are exactly Runs.visibleActions(run), left to right: running
// Cancel, Pause; parked Close, Resume; escalated and dead Close, Relaunch;
// Integrate drops Pause, Cancel and Close; anything else shows nothing.
// `relaunchShown: false` drops Relaunch (Run detail has its own; a card has
// no relaunch path). No button is ever disabled, with one exception: while
// a request is pending, only that request's button shows (a pending reset is
// the Close button), labelled `<Word> requested…`, disabled, as a progress
// marker; an unknown pending action shows no button at all. With nothing to
// show the component is 0 tall. There is no reason line: nothing shown is
// disabled for a reason.
Column {
  id: controls

  property var theme: T.Theme {}
  // One normalised run, as RunStore.runs holds them, or null.
  property var run: null
  // "" or the store's action pending for this run: pause, resume, cancel or reset.
  property string pendingAction: ""
  // That request is 30 s or more old.
  property bool waiting: false
  property string waitingText: ""
  // The control error for THIS run; "" otherwise.
  property string errorText: ""
  // The controls sit on a story or subtask card: the labels say "run".
  property bool wholeRun: false
  // The owner's rule for showing the buttons; a pending marker shows anyway.
  property bool showButtons: true
  // Whether Relaunch may show at all.
  property bool relaunchShown: true

  signal actionRequested(string action)

  // The UI actions this run shows, in order (Runs.visibleActions, minus
  // relaunch when relaunchShown is false).
  readonly property var shownActions: {
    var all = Runs.visibleActions(controls.run)
    return controls.relaunchShown ? all : all.filter(function(a) { return a !== "relaunch" })
  }
  readonly property bool requestPending: controls.pendingAction !== ""
  // The UI button of the pending request: reset is Close; "" when nothing is
  // pending or the pending value is unknown.
  readonly property string pendingButton: controls.pendingAction === "reset" ? "close"
    : controls.pendingAction === "pause" || controls.pendingAction === "resume" || controls.pendingAction === "cancel"
      ? controls.pendingAction : ""
  readonly property bool buttonsShown: controls.requestPending ? controls.pendingButton !== ""
    : controls.showButtons && controls.shownActions.length > 0

  spacing: Style.space(2)

  // Whether the button for `action` (a UI name) shows.
  function shows(action) {
    if (controls.requestPending) return controls.pendingButton === action
    return controls.showButtons && controls.shownActions.indexOf(action) >= 0
  }

  function labelOf(action, word) {
    if (controls.pendingButton === action) return word + " requested…"
    return controls.wholeRun ? word + " run" : word
  }

  // A click: nothing while a request is pending (the marker is no action).
  function ask(action) {
    if (!controls.requestPending) controls.actionRequested(action)
  }

  // At most one of Cancel and Close ever shows, so this fixed order renders
  // every visibleActions list left to right.
  Row {
    objectName: "runControlButtons"
    visible: controls.buttonsShown
    spacing: Style.space(6)

    UI.ActionButton {
      objectName: "runControlCancel"
      theme: controls.theme
      tone: "danger"
      visible: controls.shows("cancel")
      text: controls.labelOf("cancel", "Cancel")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("cancel")
    }

    UI.ActionButton {
      objectName: "runControlClose"
      theme: controls.theme
      tone: "close"
      visible: controls.shows("close")
      text: controls.labelOf("close", "Close")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("close")
    }

    UI.ActionButton {
      objectName: "runControlPause"
      theme: controls.theme
      tone: "warn"
      visible: controls.shows("pause")
      text: controls.labelOf("pause", "Pause")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("pause")
    }

    UI.ActionButton {
      objectName: "runControlResume"
      theme: controls.theme
      tone: "accent"
      visible: controls.shows("resume")
      text: controls.labelOf("resume", "Resume")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("resume")
    }

    UI.ActionButton {
      objectName: "runControlRelaunch"
      theme: controls.theme
      tone: "accent"
      visible: controls.shows("relaunch")
      text: controls.labelOf("relaunch", "Relaunch")
      enabled: !controls.requestPending
      tooltipText: ""
      onClicked: controls.ask("relaunch")
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
    color: controls.theme ? controls.theme.urgent : Cm.Color.urgent
    wrapMode: Text.WordWrap
  }
}
```

- [ ] **Step 4: Run the component tests to verify they pass**

Run: `bash tests/run.sh tst_run_controls`
Expected: `Totals: … 0 failed` for `tests/ui/components/tst_run_controls.qml`, and no TypeError line.

- [ ] **Step 5: Update the flow test that asserted disabled Integrate buttons**

The old design showed Pause and Cancel disabled in Integrate. `visibleActions` hides them, so the test now asserts that they are hidden. In `tests/ui/tst_runs_flow.qml`, replace the function `test_integrate_disables_pause_and_cancel_and_a_key_says_why` (from its `// 18` comment line through its closing `  }`) with:

```qml
  // 18
  function test_integrate_hides_pause_and_cancel_and_a_key_says_why() {
    var p = make(); if (!p) return
    var r = run("run-0000000000a1", "started", true, "alpha")
    r.lease.accepting = false
    p.app.runs.runs = [r]
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    mouseMove(row, row.width / 2, row.height / 2)
    wait(50)
    compare(controlOf(p, "Pause").visible, false)
    compare(controlOf(p, "Cancel").visible, false)
    compare(H.find(p, "runRowControls0").height, 0, "Integrate shows no button")
    var reason = "Integrate is running; it cannot be paused or cancelled"
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), true)
    compare(H.find(p, "runsFooter").text, reason)
    compare(p.app.runControl.controlRunners.length, 0)
    p.app.runControl.flash("")
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), true)
    compare(p.app.runControl.cancelOpen, false)
    compare(cancelModal(p).visible, false)
    compare(H.find(p, "runsFooter").text, reason)

    p.navigator.openRun("run-0000000000a1")
    wait(50)
    var detail = H.find(p, "runDetailControls")
    compare(H.find(detail, "runControlPause").visible, false)
    compare(H.find(detail, "runControlCancel").visible, false)
    p.app.runControl.flash("")
    compare(H.find(p, "runDetailFlash").visible, false)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), true)
    compare(H.find(p, "runDetailFlash").visible, true)
    compare(H.find(p, "runDetailFlash").text, reason)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), true)
    compare(p.app.runControl.cancelOpen, false)
    compare(p.app.runControl.controlRunners.length, 0)
    compare(Object.keys(p.app.runControl.pending).length, 0)
  }
```

- [ ] **Step 6: Run every run-control consumer to verify nothing else regressed**

Run: `bash tests/run.sh tst_run` (matches `tst_run_controls`, `tst_runs_screen`, `tst_run_detail_screen`, `tst_runs_flow`, `tst_runs_real_data`, …) and then `bash tests/run.sh tst_card_detail`.
Expected: every listed file reports `0 failed` and no TypeError line. (The parked, running and pending cases those files assert keep their buttons and labels. Escalated and dead runs now show Close and Relaunch there, and no existing assertion covers them.)

- [ ] **Step 7: Commit**

```bash
git add ui/components/RunControls.qml tests/ui/components/tst_run_controls.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(components): RunControls renders Runs.visibleActions with a pending marker"
```

---

### Task 2: The Runs row layout (id, title, level and state badges, meta, warn reason)

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (header comment lines 11-42; imports lines 4-9; functions `registryEntryOf`, `openProjectTargetOf` lines 225-246; `stateText` lines 350-357; `component RunRow` lines 692-828)
- Test: `tests/ui/screens/tst_runs_screen.qml`
- Test: `tests/ui/tst_runs_real_data.qml`
- Test: `tests/ui/tst_runs_flow.qml` (remove two Open project tests)

**Interfaces:**
- Consumes: from Task 1, `RunControls.relaunchShown`. From `runs.js`: `runLevel(run)`, `runState`, `runProgress(run)` → `{done, total}`, `currentPhase(run)`, `runAgeText(run, nowMs)`, `runTitle`, `titlesOfRun`, `escalationReason`. `UI.RunLevelBadge` has `theme` and `level`, with inner text objectName `runLevelBadgeText`. `UI.RunStateBadge` has `theme` and `state`, with inner text objectName `runStateBadgeText`, and is visible only for running and escalated.
- Produces: `RunsScreen.rowIdOf(run)` → string; `RunsScreen.metaText(run, nowMs)` → string; `RunsScreen.stateText(state, age)` (dead only, `""` otherwise). Row objectNames: `runRowLine<i>` (the first line's Item), `runRowId<i>`, `runRowTitle<i>`, `runRowLevel<i>`, `runRowStateBadge<i>`, `runRowMeta<i>`, `runRowReason<i>`, `runRowControls<i>`. Removed: `runRowGlyph<i>`, `runRowProgress<i>`, `runRowPhase<i>`, `runRowAge<i>`, `runRowState<i>`, `runRowOpenProject<i>`.

- [ ] **Step 1: Update the row-id literals in the existing chip, header, Show older and cursor tests**

Those tests identify rows by `runRowId<i>`. The row id is now the first 8 characters of `milestone_id`, else the last 8 of `id`, with no `…`. Only the expected strings change. Save this script as `/tmp/rowids.py`, outside the worktree, and run `python3 /tmp/rowids.py` from the worktree root:

```python
import pathlib

p = pathlib.Path("tests/ui/screens/tst_runs_screen.qml")
src = p.read_text()

# (function name, old text, new text): each replaced inside that function only.
EDITS = [
    ("test_the_open_and_another_project_title_from_their_own_maps", '"…live0001"', '"m1"'),
    ("test_the_open_and_another_project_title_from_their_own_maps", '"…live0002"', '"m1"'),
    ("test_without_a_map_the_row_falls_back", '"…live0003"', '"zeta"'),
    ("test_a_long_title_never_pushes_the_short_id_off_the_row", '"…live0003"', '"zeta"'),
    ("test_an_unreachable_project_header_says_titles_unavailable", '"…live0003"', '"zeta"'),
    ("test_show_older_takes_no_index_and_the_cursor_walks_runs_only",
     "Runs.runSubtitle(s.runs.filteredRuns[i])", "s.runs.filteredRuns[i].id.slice(-8)"),
    ("test_each_chip_filters_its_rows_and_the_active_one_returns_to_all", '"…escl0002"', '"beta"'),
    ("test_each_chip_filters_its_rows_and_the_active_one_returns_to_all", '"…dead0003"', '"gamma"'),
    ("test_each_chip_filters_its_rows_and_the_active_one_returns_to_all", '"…live0001"', '"alpha"'),
    ("test_each_chip_filters_its_rows_and_the_active_one_returns_to_all", '"…park0004"', '"delta"'),
    ("test_the_chip_counts_ignore_the_search", '"…dead0003"', '"gamma"'),
    ("test_groups_and_rows_follow_the_display_order",
     "Runs.shortId(s.runs.filteredRuns[i])", "s.runs.filteredRuns[i].id.slice(-8)"),
    ("test_runs_without_a_project_get_no_header", '"…done0006"', '"epsilon"'),
    ("test_the_cursor_on_the_first_run_past_a_header_marks_that_row", '"…live0003"', '"zeta"'),
    ("test_a_new_snapshot_reorders_headers_rows_and_the_cursor", '"…escl0001"', '"escl0001"'),
    ("test_a_new_snapshot_reorders_headers_rows_and_the_cursor", '"…escl0006"', '"escl0006"'),
    ("test_a_new_snapshot_reorders_headers_rows_and_the_cursor", '"…live0005"', '"live0005"'),
    ("test_a_project_filter_shows_a_flat_list_without_headers", '"…live0003"', '"zeta"'),
    ("test_a_project_chip_filters_and_clicking_it_again_returns_to_all", '"…live0003"', '"zeta"'),
    ("test_all_projects_and_this_project_ask_the_store", '"…escl0001"', '"escl0001"'),
    ("test_all_projects_and_this_project_ask_the_store", '"…dead0002"', '"dead0002"'),
    ("test_a_new_snapshot_reorders_the_chips_and_the_active_one_stays_active", '"…escl0003"', '"escl0003"'),
    ("test_the_search_changes_neither_project_chips_nor_status_counts", '"…live0003"', '"zeta"'),
]

for name, old, new in EDITS:
    start = src.index("  function " + name + "(")
    end = src.index("\n  }\n", start) + len("\n  }\n")
    body = src[start:end]
    assert old in body, (name, old)
    src = src[:start] + body.replace(old, new) + src[end:]

p.write_text(src)
print("ok", len(EDITS))
```

Expected output: `ok 23`. The mapping follows the fixtures. In `sample()` the runs carry milestones `alpha`, `beta`, `gamma`, `delta`, `""` and `epsilon`, so `canc0005` falls back to its id. In `twoProjects()` only `run-b-live0003` has a milestone (`zeta`). The `doneRuns()` runs and the runs built with `{}` have none.

- [ ] **Step 2: Write the failing row tests**

In `tests/ui/screens/tst_runs_screen.qml`:

(a) Remove the import line `import "../../../ui/components/runGlyphs.js" as RG` (line 13). After this step nothing in the file uses `RG`.

(b) Replace the three functions `test_each_state_shows_its_glyph`, `test_runs_that_need_attention_are_drawn_urgent` and `test_a_row_shows_short_id_title_progress_phase_and_age`, and also `test_empty_values_are_left_out`. That is everything from the line `  function test_each_state_shows_its_glyph() {` through the closing `  }` of `test_empty_values_are_left_out`, including the comment above `test_runs_that_need_attention_are_drawn_urgent`. The replacement:

```qml
  // `n` real subtasks t0…t<n-1>, the first `done` of them done; when `phase`
  // is not "", it is started on the first subtask that is not done.
  function subtaskTree(n, done, phase) {
    var out = []
    for (var i = 0; i < n; i++) {
      var st = { card_id: "t" + i, status: i < done ? "done" : "todo", phases: [] }
      if (i === done && phase !== "") st.phases = [{ name: phase, status: "started" }]
      out.push(st)
    }
    return { stories: [], subtasks: out }
  }

  // filteredRuns' index of the run whose id is `id` (compared with ===); -1 when none.
  function rowIndexOf(s, id) {
    for (var i = 0; i < s.runs.filteredRuns.length; i++) {
      if (s.runs.filteredRuns[i] && s.runs.filteredRuns[i].id === id) return i
    }
    return -1
  }

  // Spec 1: the milestone's first 8, else the run id's last 8, else "".
  function test_the_row_id_is_the_milestone_prefix_else_the_run_ids_tail() {
    var odd = run("run-x-live0003", "started", true, {})
    odd.id = 42
    var s = make([run("run-x-live0001", "started", true, { milestone: "e795ad19-c81f-43ec-bdda-ef61ab5f860b" }),
                  run("run-20261004-live0002", "started", true, {}), odd]); if (!s) return
    compare(H.find(s.screen, "runRowId" + rowIndexOf(s, "run-x-live0001")).text, "e795ad19")
    compare(H.find(s.screen, "runRowId" + rowIndexOf(s, "run-20261004-live0002")).text, "live0002")
    var oddId = H.find(s.screen, "runRowId" + rowIndexOf(s, 42))
    compare(oddId.text, "")
    compare(oddId.visible, false)
    for (var i = 0; i < 3; i++)
      verify(String(H.find(s.screen, "runRowId" + i).text).indexOf("…") < 0, "no … in row " + i)
    compare(s.screen.rowIdOf(null), "")
    compare(s.screen.rowIdOf({ id: "abc", milestone_id: "" }), "abc", "a short id is all of it")
  }

  // Spec 2.
  function test_the_level_badge_names_milestone_story_and_subtask_runs() {
    var story = run("run-x-stor0002", "started", true, { milestone: "M1" })
    story.story_id = "s1"
    var task = run("run-x-task0003", "started", true, { milestone: "M1" })
    task.workflow = "task"
    task.card_id = "t1"
    var s = make([run("run-x-mile0001", "started", true, { milestone: "M1" }), story, task]); if (!s) return
    var want = { "run-x-mile0001": "MILESTONE", "run-x-stor0002": "STORY", "run-x-task0003": "SUBTASK" }
    for (var i = 0; i < 3; i++) {
      var badge = H.find(s.screen, "runRowLevel" + i)
      verify(badge, "row " + i)
      compare(badge.visible, true, "always shown")
      compare(H.find(badge, "runLevelBadgeText").text, want[s.runs.filteredRuns[i].id])
    }
  }

  // Spec 3. sample(): 0 running, 1 escalated, 2 dead, 3 parked, 4 cancelled, 5 done.
  function test_the_state_badge_shows_for_running_and_escalated_only() {
    var s = make(sample()); if (!s) return
    var want = ["RUNNING", "ESCALATED", "", "", "", ""]
    for (var i = 0; i < 6; i++) {
      var badge = H.find(s.screen, "runRowStateBadge" + i)
      verify(badge, "row " + i)
      compare(badge.visible, want[i] !== "", "row " + i)
      if (want[i] !== "") compare(H.find(badge, "runStateBadgeText").text, want[i])
    }
  }

  // Spec 4.
  function test_the_meta_reads_progress_then_phase_then_age_on_the_right() {
    var s = make([run("run-x-live0001", "started", true, { started_at: ago(120 * tc.minute), tree: subtaskTree(8, 3, "explore") }),
                  run("run-x-park0002", "stopped", null, { started_at: ago(5 * 1440 * tc.minute), tree: subtaskTree(11, 0, "") })]); if (!s) return
    var live = H.find(s.screen, "runRowMeta0")
    compare(live.text, "3/8 · explore · " + Runs.runAgeText(s.runs.filteredRuns[0], s.screen.nowMs))
    compare(live.text, "3/8 · explore · 2h")
    compare(String(live.color), String(s.screen.theme.dim))
    var parked = H.find(s.screen, "runRowMeta1")
    compare(parked.text, "0/11 · parked · " + Runs.runAgeText(s.runs.filteredRuns[1], s.screen.nowMs))
    compare(parked.text, "0/11 · parked · 5d")
    var line = H.find(s.screen, "runRowLine0")
    compare(Math.round(live.mapToItem(s.screen, 0, 0).x + live.width),
            Math.round(line.mapToItem(s.screen, 0, 0).x + line.width), "right-aligned on the first line")
    verify(Math.abs(live.mapToItem(s.screen, 0, 0).y - H.find(s.screen, "runRowTitle0").mapToItem(s.screen, 0, 0).y) < live.height,
           "on the title's line")
  }

  function test_the_sample_rows_meta() {
    var s = make(sample()); if (!s) return
    compare(H.find(s.screen, "runRowMeta0").text, "1/2 · implement · 5m")
    compare(H.find(s.screen, "runRowMeta1").text, "0/1", "escalated: no started phase, no start")
    compare(H.find(s.screen, "runRowMeta2").text, "dead - lease lost 7m ago")
    verify(Qt.colorEqual(H.find(s.screen, "runRowMeta2").color, s.screen.theme.urgent), "the dead line is urgent")
    compare(H.find(s.screen, "runRowMeta3").text, "parked · 2h")
    compare(String(H.find(s.screen, "runRowMeta3").color), String(s.screen.theme.dim), "every other meta is dim")
    compare(H.find(s.screen, "runRowMeta4").visible, false, "no subtasks, no phase, no start: hidden")
    compare(H.find(s.screen, "runRowMeta5").visible, false)
  }

  // Spec 6.
  function test_the_old_row_parts_are_gone() {
    var s = make(sample().concat(twoProjects())); if (!s) return
    s.runs.project = "/home/u/a"
    var names = ["runRowGlyph", "runRowOpenProject", "runRowState", "runRowProgress", "runRowPhase", "runRowAge"]
    for (var i = 0; i < s.runs.filteredRuns.length; i++) {
      s.nav.cursorIndex = i
      wait(20)
      for (var n = 0; n < names.length; n++) compare(H.find(s.screen, names[n] + i), null, names[n] + i)
    }
  }

  // Review Focus: a long title leaves the badges and the meta on the row.
  function test_a_long_title_leaves_the_badges_and_the_meta_on_the_row() {
    var long = ""
    for (var i = 0; i < 40; i++) long += "a very long run title "
    var s = make([tagged(run("run-a-live0001", "started", true, { milestone: "zeta", started_at: ago(5 * tc.minute),
                                                                 tree: subtaskTree(8, 3, "explore") }), "/home/u/a", "alpha")]); if (!s) return
    s.titles.titlesByRoot = { "/home/u/a": { zeta: long } }
    wait(20)
    var title = H.find(s.screen, "runRowTitle0")
    compare(title.elide, Text.ElideRight)
    verify(title.width < title.implicitWidth, "the title is elided")
    var names = ["runRowId0", "runRowLevel0", "runRowStateBadge0", "runRowMeta0"]
    for (var n = 0; n < names.length; n++) {
      var item = H.find(s.screen, names[n])
      compare(item.visible, true, names[n])
      var right = item.mapToItem(s.screen, 0, 0).x + item.width
      verify(right <= s.screen.width, names[n] + " stays on the row: right edge " + right)
    }
    var state = H.find(s.screen, "runRowStateBadge0")
    verify(state.mapToItem(s.screen, 0, 0).x + state.width <= H.find(s.screen, "runRowMeta0").mapToItem(s.screen, 0, 0).x,
           "the badges never overlap the meta")
  }
```

(c) Replace the function `test_a_row_reads_its_title_then_its_short_id_in_dim` (keep the `// twoProjects(): …` comment above it) with:

```qml
  function test_a_row_reads_its_id_in_dim_then_its_title() {
    var s = make(twoProjects()); if (!s) return
    s.titles.titlesByRoot = { "/home/u/b": { zeta: "Ship zeta" } }
    wait(20)
    var title = H.find(s.screen, "runRowTitle2")
    var id = H.find(s.screen, "runRowId2")
    compare(title.text, "Ship zeta")
    compare(id.text, "zeta")
    compare(id.visible, true)
    compare(String(id.color), String(s.screen.theme.dim), "the id is dim")
    verify(id.x < title.x, "the id comes first")
    verify(title.x < H.find(s.screen, "runRowLevel2").x, "the level badge follows the title")
  }
```

(d) Replace the function `test_an_escalated_row_carries_its_reason` with (spec 5):

```qml
  function test_an_escalated_row_carries_its_reason_in_warn_flush_left() {
    var s = make(sample()); if (!s) return
    var reason = H.find(s.screen, "runRowReason1")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    verify(Qt.colorEqual(reason.color, s.screen.theme.warn), "warn, not urgent")
    compare(reason.mapToItem(s.screen, 0, 0).x, H.find(s.screen, "runRowId1").mapToItem(s.screen, 0, 0).x, "flush left with the id")
    compare(H.find(s.screen, "runRowReason0").visible, false, "only escalated rows")
    compare(H.find(s.screen, "runRowReason2").visible, false, "not a dead row")
  }
```

(e) Replace the two functions `test_dead_and_parked_rows_name_their_state_with_the_age_once` and `test_dead_and_parked_rows_without_an_age` with:

```qml
  function test_dead_and_parked_rows_without_an_age() {
    var s = make([run("run-x-dead0001", "started", null, {}), run("run-x-park0002", "stopped", null, {}),
                  run("run-x-just0003", "started", false, { heartbeat_at: ago(10000) })]); if (!s) return
    compare(H.find(s.screen, "runRowMeta0").text, "dead - lease lost")
    compare(H.find(s.screen, "runRowMeta1").text, "parked")
    compare(H.find(s.screen, "runRowMeta2").text, "dead - lease lost just now", "never \"just now ago\"")
    compare(s.screen.stateText("parked", "2h"), "", "stateText names dead runs only")
    compare(s.screen.stateText("running", "2h"), "")
  }
```

(f) Replace the function `test_malformed_runs_render_without_throwing` with (Review Focus 1):

```qml
  function test_malformed_runs_render_without_throwing() {
    var s = make([{}, { id: 42, status: 7, lease: "x", rows: "y", tree: null, milestone_id: {} },
                  run("run-20261004-good0007", "done", null, {}),
                  { id: "run-x-objm0008", status: "stopped", milestone_id: {}, tree: "z" }]); if (!s) return
    compare(H.find(s.screen, "runRowId0").text, "")
    compare(H.find(s.screen, "runRowId0").visible, false)
    compare(H.find(H.find(s.screen, "runRowLevel0"), "runLevelBadgeText").text, "MILESTONE")
    compare(H.find(s.screen, "runRowStateBadge0").visible, false, "an unknown state has no state badge")
    compare(H.find(s.screen, "runRowMeta0").visible, false)
    compare(H.find(s.screen, "runRowId1").text, "")
    compare(H.find(s.screen, "runRowTitle1").text, "…")
    compare(H.find(s.screen, "runRowMeta1").visible, false)
    compare(H.find(s.screen, "runRowId2").text, "good0007")
    compare(H.find(s.screen, "runRowId3").text, "objm0008", "a non-string milestone id falls back to the run id")
    compare(H.find(s.screen, "runRowMeta3").text, "parked")
    compare(H.find(s.screen, "runChipall").text, "All")
  }
```

(g) After the existing test `test_a_run_id_like_constructor_is_not_pending`, add (spec 7):

```qml
  // Row i's visible control buttons, left to right, by label.
  function shownButtons(s, i) {
    wait(20)
    var row = H.find(H.find(s.screen, "runRowControls" + i), "runControlButtons")
    var kids = []
    for (var k = 0; k < row.children.length; k++) {
      if (row.children[k].visible) kids.push(row.children[k])
    }
    kids.sort(function(a, b) { return a.x - b.x })
    return kids.map(function(b) { return b.text }).join(",")
  }

  // Spec 7.
  function test_the_buttons_follow_the_cursor_and_the_table() {
    var s = make(sample()); if (!s) return
    s.nav.cursorIndex = -1
    wait(20)
    for (var i = 0; i < 6; i++) compare(H.find(s.screen, "runRowControls" + i).height, 0, "row " + i + " without the cursor")
    var want = ["Cancel,Pause", "Close,Relaunch", "Close,Relaunch", "Close,Resume", "", ""]
    for (var j = 0; j < 6; j++) {
      s.nav.cursorIndex = j
      compare(shownButtons(s, j), want[j], "row " + j)
      for (var o = 0; o < 6; o++) {
        if (o !== j) compare(H.find(s.screen, "runRowControls" + o).height, 0, "row " + o + " while row " + j + " has the cursor")
      }
    }
  }
```

(h) Delete the whole Open project section: from the line `  // ---- Open project (4.4)` through the closing `  }` of the last test, `test_open_project_under_a_project_filter_leaves_the_filter_alone`. Keep the final `}` that closes the `TestCase`. That removes `openButton`, `registry` and every `test_open_project_*` / `test_a_row_click_still_opens_any_projects_run` / `test_malformed_registry_entries_are_skipped` / `test_a_malformed_run_project_hides_open_project_without_throwing` function in that section.

- [ ] **Step 3: Update the real-data test**

In `tests/ui/tst_runs_real_data.qml`:

Add after `import "../helpers/amFixtures.js" as F`:

```qml
import "../../core/domain/runs.js" as Runs
```

In `test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs`, replace the five lines from `compare(H.find(p, "runRowProgress0").text, "3/8")` through `compare(H.find(p, "runRowPhase1").visible, false)` with:

```qml
    var nowMs = H.find(p, "runsView").nowMs
    var age0 = Runs.runAgeText(p.app.runs.filteredRuns[0], nowMs)
    var age1 = Runs.runAgeText(p.app.runs.filteredRuns[1], nowMs)
    compare(H.find(p, "runRowMeta0").text, ["3/8", "explore", age0].filter(function(x) { return x !== "" }).join(" · "))
    compare(H.find(p, "runRowMeta1").text, ["10/10", age1].filter(function(x) { return x !== "" }).join(" · "))
    compare(H.find(H.find(p, "runRowLevel0"), "runLevelBadgeText").text, "MILESTONE")
    compare(H.find(H.find(p, "runRowLevel1"), "runLevelBadgeText").text, "MILESTONE")
    compare(H.find(p, "runRowId0").text, "e795ad19", "the milestone's first 8")
```

In `test_the_running_subtasks_card_lists_the_started_run_at_its_phase`, replace

```qml
    var shortId = String(H.find(p, "runRowId0").text)
    verify(shortId !== "", "the Runs list names the started run")
```

with

```qml
    var rowId = String(H.find(p, "runRowId0").text)
    verify(rowId !== "", "the Runs list names the started run")
```

and replace `compare(H.find(p, "cardRunId0").text, shortId)` with:

```qml
    compare(H.find(p, "cardRunId0").text, "…" + rowId, "the card keeps …<8>; am's run id ends with the milestone's first 8")
```

- [ ] **Step 4: Remove the flow tests of the removed Open project button**

In `tests/ui/tst_runs_flow.qml`:
- Delete the function `test_open_project_on_another_projects_run_opens_its_board_and_ctrl_6_returns`, together with its `// 10` comment line.
- Delete the function `test_open_project_with_a_dirty_memory_draft_stays_on_runs`, together with its `// Review Focus 1.` comment line.
- Change the section comment `  // ---- Open project (4.4)` to `  // ---- another project's runs (4.4)`.
- Keep `makeTwo`, `disarmSwitch`, `ctrl6`, `runsOnBeta` and `test_run_detail_of_another_projects_run_keeps_the_open_project`. They are still used.

- [ ] **Step 5: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen` and then `bash tests/run.sh tst_runs_real_data`.
Expected: FAIL. `runRowLevel0`, `runRowMeta0` and `runRowStateBadge0` are not found, so those compares fail with a null item. The id literals fail on `…alpha` vs `alpha`. `rowIdOf` is not a function (the script prints a TypeError).

- [ ] **Step 6: Implement the row in `ui/screens/RunsScreen.qml`**

(a) Delete the import line `import "../components/runGlyphs.js" as RunGlyphs` (line 5).

(b) Replace the header comment (lines 11-42, from `// The Runs section: every registered project's am runs, grouped by project` through `// Ages are read against the clock once per snapshot: there is no timer.`) with:

```qml
// The Runs section: every registered project's am runs, grouped by project
// with a header each (name; live, parked and needs-attention counts; the
// project's snapshot error; a dim `titles unavailable` while its titles
// cannot be read), flat with no header under a project filter. Each run is
// one row whose index is its position in the store's filteredRuns, the one
// list the cursor walks; headers are not cursor targets. A row's first line
// reads, left to right, its id in dim (rowIdOf), its title (from the run's
// own project's map in app.runTitles; it takes the width the others leave
// and elides), a RunLevelBadge, a RunStateBadge for a running or escalated
// run, and on the right its meta (metaText: done/total, phase, age; a dead
// run's lease line in urgent); an escalated run's reason follows flush left
// in warn. A project chip row (All
// projects, This project when one is open, one chip per project with runs,
// with run counts) sits above the status chips, hidden when only one project
// has runs and none is open; clicking one asks the store to toggle its
// project filter. Needs attention / Live / Parked / Finished / All chips
// apply across groups and carry the store's runFilterCounts -- clicking the
// active chip means All again. Under them, while am is present, a state row
// (All finished / Done / Escalated / Cancelled) under Finished and an age
// row (Today / 7 days / All time) under Finished and All ask the store to
// toggle its finished state and age. After each project's last run (after
// the last run under a project filter) a Show older button -- not a row,
// never a cursor target -- asks app.runHistory for that project's next older
// page; it shows while am is present, the chip has statuses to page and the
// project's history entry is loading, failed or has more, or, with no entry,
// its snapshot lists terminalLimit terminal runs; it reads `Loading older
// runs…` and takes no click while its page is in flight, and a failed
// page's sentence shows under it in urgent. A footer says whether the runs
// are watched. The row with the cursor shows RunControls' buttons
// (Runs.visibleActions). It reads the run store, the run history and the
// run titles and asks the navigator to open a run or move the cursor, the
// run titles to read every project's titles again and the run history for
// older runs; it owns no state of its own.
// Ages are read against the clock once per snapshot: there is no timer.
```

(c) Delete the functions `registryEntryOf` and `openProjectTargetOf`, with their comments (lines 225-246, from `  // The first entry of the registry \`list\`` through the closing `  }` of `openProjectTargetOf`).

(d) Replace `stateText` (lines 350-357, from `  // A dead or parked run's state, spelled out` through its closing `  }`) with:

```qml
  // A dead run's state, spelled out with its age folded in so the age shows
  // once; "" for every other state.
  function stateText(state, age) {
    if (state === "dead")
      return age === "" ? "dead - lease lost" : age === "just now" ? "dead - lease lost just now" : "dead - lease lost " + age + " ago"
    return ""
  }

  // A row's id: the first 8 characters of the run's milestone_id when that is
  // a non-empty string, else the last 8 of its id when that is a string, else
  // "". Raw, with no "…" (am's run ids end with the milestone's first 8).
  function rowIdOf(run) {
    if (run === null || typeof run !== "object") return ""
    if (typeof run.milestone_id === "string" && run.milestone_id !== "") return run.milestone_id.slice(0, 8)
    return typeof run.id === "string" ? run.id.slice(-8) : ""
  }

  // A row's meta: a dead run's stateText with its age; any other run's
  // non-empty parts of done/total (with subtasks), its current phase (else
  // "parked" for a parked run) and its age, joined by " · ".
  function metaText(run, nowMs) {
    var state = Runs.runState(run)
    var age = Runs.runAgeText(run, nowMs)
    if (state === "dead") return screen.stateText(state, age)
    var progress = Runs.runProgress(run)
    var phase = Runs.currentPhase(run)
    if (phase === "" && state === "parked") phase = "parked"
    var parts = []
    if (progress.total > 0) parts.push(progress.done + "/" + progress.total)
    if (phase !== "") parts.push(phase)
    if (age !== "") parts.push(age)
    return parts.join(" · ")
  }
```

(e) Replace the whole `component RunRow: UI.ListRow { … }` block (from `  // A run's row; \`index\` is the run's position in filteredRuns.` through the `  }` before the file's final `}`) with:

```qml
  // A run's row; `index` is the run's position in filteredRuns.
  component RunRow: UI.ListRow {
    id: row
    objectName: "runRow" + row.index

    // The run is read back out of the store's list by position, NOT taken from
    // `modelData`: a Repeater hands the delegate a converted copy whose nested
    // arrays are no longer JS arrays (Array.isArray is false), so the domain
    // helpers that read `tree.subtasks` and `rows` would see an empty run and
    // the progress, phase and escalation reason would silently vanish.
    readonly property var run: screen.app.runs.filteredRuns[row.index]

    readonly property string runState: Runs.runState(row.run)

    width: screen.width
    theme: screen.theme
    opacity: screen.app.runs.stale ? 0.5 : 1
    cursorIndex: screen.app.nav.cursorIndex
    scrollOnCursor: screen.app.nav.scrollOnCursor
    onHovered: function(index) { screen.navigator.hoverCursor(index) }
    onActivated: screen.navigator.openRun(row.run ? row.run.id : "")
    onRevealRequested: function(item) { screen.revealRequested(item) }

    // The first line: id, title, level and state badges, then the meta on
    // the right. The title takes the width the others leave and elides.
    Item {
      id: rowLine
      objectName: "runRowLine" + row.index
      width: parent.width
      height: Math.max(rowLeft.height, rowMeta.visible ? rowMeta.height : 0)

      Row {
        id: rowLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        UI.ThemedText {
          id: rowId
          objectName: "runRowId" + row.index
          anchors.verticalCenter: parent.verticalCenter
          variant: "caption"
          theme: screen.theme
          visible: text !== ""
          text: screen.rowIdOf(row.run)
          color: screen.theme.dim
        }

        UI.ThemedText {
          objectName: "runRowTitle" + row.index
          anchors.verticalCenter: parent.verticalCenter
          theme: screen.theme
          width: Math.max(0, Math.min(implicitWidth, rowLine.width
            - (rowId.visible ? rowId.width + rowLeft.spacing : 0)
            - rowLevel.width - rowLeft.spacing
            - (rowStateBadge.visible ? rowStateBadge.width + rowLeft.spacing : 0)
            - (rowMeta.visible ? rowMeta.width + rowLeft.spacing : 0)))
          text: Runs.runTitle(row.run, Runs.titlesOfRun(row.run, screen.app.runTitles.titlesByRoot))
          elide: Text.ElideRight
        }

        UI.RunLevelBadge {
          id: rowLevel
          objectName: "runRowLevel" + row.index
          anchors.verticalCenter: parent.verticalCenter
          theme: screen.theme
          level: Runs.runLevel(row.run)
        }

        UI.RunStateBadge {
          id: rowStateBadge
          objectName: "runRowStateBadge" + row.index
          anchors.verticalCenter: parent.verticalCenter
          theme: screen.theme
          state: row.runState
        }
      }

      UI.ThemedText {
        id: rowMeta
        objectName: "runRowMeta" + row.index
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: screen.metaText(row.run, screen.nowMs)
        color: row.runState === "dead" ? screen.theme.urgent : screen.theme.dim
      }
    }

    UI.ThemedText {
      objectName: "runRowReason" + row.index
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: row.runState === "escalated"
      text: Runs.escalationReason(row.run)
      color: screen.theme.warn
      wrapMode: Text.WordWrap
    }

    // Under the row: the buttons while it has the cursor (hover moves the
    // cursor, so that is hover or selected) or a request is pending, and the
    // waiting and error lines whenever they apply.
    actions: [
      UI.RunControls {
        objectName: "runRowControls" + row.index
        width: parent.width
        theme: screen.theme
        run: row.run
        pendingAction: ControlFacts.pendingOf(screen.app.runControl.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runControl.stillWaiting, row.run)
        waitingText: screen.app.runControl.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runControl.lastControlError, screen.app.runControl.lastControlErrorRunId, row.run)
        wholeRun: false
        showButtons: row.hasCursor
        relaunchShown: true
        onActionRequested: function(action) { screen.requestControl(action, row.run) }
      }
    ]
  }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen`, then `bash tests/run.sh tst_runs_real_data`, then `bash tests/run.sh tst_runs_flow`.
Expected: each file `0 failed`, no TypeError/ReferenceError/`anchors on an item` line.

- [ ] **Step 8: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/tst_runs_real_data.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(runs): RunsScreen row reads id, title, level and state badges, and meta"
```

---

### Task 3: RunsScreen routes Close and Relaunch

**Files:**
- Modify: `ui/screens/RunsScreen.qml` (signals ~line 52-55; `requestControl` ~line 359-366)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stubs `controlC`, `appC`, `make()`; new tests)

**Interfaces:**
- Consumes: `app.runControl.flash(text)`, `app.runControl.control(action, id)`, `app.board.cardMap` (`{id: card}`), `app.runDispatch.relaunchOpenFor(card, cardMap, relaunch)`, `Runs.stopReport(run)` → `null` or `{…, relaunch: null | {level, cardId, prefix, base}}`, `screen.rootKey(path)`, `screen.openRoot`.
- Produces: `RunsScreen` signal `closeRequested(string runId)`; `RunsScreen.requestControl(action, run)` (`cancel` → `cancelRequested`, `close` → `closeRequested`, `relaunch` → `relaunch(run)`, else `app.runControl.control(action, id)`); `RunsScreen.relaunch(run)`. Task 5's Panel connects `onCloseRequested`.

- [ ] **Step 1: Extend the test stubs**

In `tests/ui/screens/tst_runs_screen.qml`:

(a) In `Component { id: controlC … }`, after the `function control(action, id) { … }` block, add:

```qml
      // The footer flash (S2 4.3). `flash` records and shows the text.
      property var flashes: []
      function flash(text) {
        rc.flashes = rc.flashes.concat([text])
        rc.flashText = text
      }
```

(b) After the `historyC` component, add:

```qml
  // The dispatch surface Relaunch reaches: relaunchOpenFor only records.
  Component {
    id: dispatchC
    QtObject {
      id: rd
      property var relaunchCalls: []
      function relaunchOpenFor(card, cardMap, relaunch) {
        rd.relaunchCalls = rd.relaunchCalls.concat([{ card: card, cardMap: cardMap, relaunch: relaunch }])
        return true
      }
    }
  }
```

(c) In `Component { id: appC … }`, after `property var runHistory: null`, add:

```qml
      property var runDispatch: null
      // The open project's board: the card a relaunch opens on.
      property var board: ({ cardMap: { M1: { id: "M1", title: "Milestone one", status: "in_progress" } } })
```

(d) In `make(list)`, after `var history = historyC.createObject(host)`, add `var dispatch = dispatchC.createObject(host)`. Change the `appC.createObject(...)` call to:

```qml
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles, runHistory: history,
                                        runDispatch: dispatch })
```

Change the return line to:

```qml
    return { app: app, runs: runs, control: control, titles: titles, history: history, dispatch: dispatch, nav: nav, navi: navi, screen: screen }
```

- [ ] **Step 2: Write the failing tests**

In `tests/ui/screens/tst_runs_screen.qml`, after the existing `test_cancel_asks_the_owner_and_never_the_store`, add:

```qml
  SignalSpy { id: closeSpy; signalName: "closeRequested" }

  // Spec 8: Close only asks the owner.
  function test_close_asks_the_owner_and_never_the_store() {
    var s = make(sample()); if (!s) return
    closeSpy.target = s.screen
    closeSpy.clear()
    s.nav.cursorIndex = 3
    wait(20)
    tap(ctl(s, 3, "Close"))
    compare(closeSpy.count, 1)
    compare(closeSpy.signalArguments[0][0], "run-20261004-park0004")
    compare(s.control.controlCalls.length, 0, "no control(close) and no control(reset)")
    compare(s.navi.opened, "", "the button is not the row")
  }

  // Spec 8.
  function test_request_control_routes_each_ui_action() {
    var s = make(sample()); if (!s) return
    closeSpy.target = s.screen
    closeSpy.clear()
    cancelSpy.target = s.screen
    cancelSpy.clear()
    var parked = s.runs.filteredRuns[3]
    s.screen.requestControl("cancel", parked)
    s.screen.requestControl("close", parked)
    s.screen.requestControl("pause", parked)
    s.screen.requestControl("resume", parked)
    s.screen.requestControl("relaunch", parked)
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-20261004-park0004")
    compare(closeSpy.count, 1)
    compare(closeSpy.signalArguments[0][0], "run-20261004-park0004")
    compare(s.control.controlCalls.join(","), "pause|run-20261004-park0004,resume|run-20261004-park0004",
            "relaunch never reaches control()")
    s.screen.requestControl("close", null)
    s.screen.requestControl("close", { id: 7 })
    s.screen.requestControl("relaunch", { status: "escalated" })
    compare(closeSpy.count, 1, "no run id: nothing")
    compare(s.control.controlCalls.length, 2)
  }

  // An escalated milestone run of project A whose relaunch target is
  // `milestone` (M1, on the stub board, by default).
  function relaunchable(milestone) {
    var r = tagged(run("run-a-escl0009", "escalated", null, { milestone: milestone === undefined ? "M1" : milestone }),
                   "/home/u/a", "alpha")
    r.branch_prefix = "old-m1"
    r.base_branch = "release"
    return r
  }

  // Spec 9 + Review Focus 2 (a trailing / on the open root).
  function test_relaunch_opens_the_prefilled_dispatch_for_a_run_of_the_open_project() {
    var s = make([relaunchable()]); if (!s) return
    s.runs.project = "/home/u/a/"
    s.nav.cursorIndex = 0
    wait(20)
    compare(ctl(s, 0, "Relaunch").visible, true)
    tap(ctl(s, 0, "Relaunch"))
    compare(s.dispatch.relaunchCalls.length, 1)
    var call = s.dispatch.relaunchCalls[0]
    verify(call.card === s.app.board.cardMap.M1, "the board's own card")
    verify(call.cardMap === s.app.board.cardMap, "the board's card map")
    compare(JSON.stringify(call.relaunch), '{"level":"milestone","cardId":"M1","prefix":"old-m1","base":"release"}')
    compare(s.control.flashes.length, 0)
    compare(s.control.controlCalls.length, 0, "relaunch never reaches control()")
    compare(s.navi.opened, "", "the button is not the row")
  }

  // Spec 9 + Review Focus 2 (a prototype-key card id).
  function test_relaunch_refusals_flash_why_and_open_nothing() {
    var s = make([relaunchable("")]); if (!s) return
    s.runs.project = "/home/u/a"
    s.screen.relaunch(s.runs.filteredRuns[0])
    compare(s.control.flashText, "This run has nothing to relaunch")
    s.runs.runs = [relaunchable("M404")]
    s.screen.relaunch(s.runs.filteredRuns[0])
    compare(s.control.flashText, "The card to relaunch is no longer on the board")
    s.runs.runs = [relaunchable("constructor")]
    s.screen.relaunch(s.runs.filteredRuns[0])
    compare(s.control.flashText, "The card to relaunch is no longer on the board", "a prototype key is no card")
    s.runs.runs = [relaunchable()]
    s.runs.project = "/home/u/b"
    s.screen.relaunch(s.runs.filteredRuns[0])
    compare(s.control.flashText, "Open this run's project to relaunch it")
    s.runs.project = ""
    s.screen.relaunch(s.runs.filteredRuns[0])
    compare(s.control.flashText, "Open this run's project to relaunch it", "no project open")
    var orphan = relaunchable()
    delete orphan.project
    s.runs.runs = [orphan]
    s.runs.project = "/home/u/a"
    s.screen.relaunch(s.runs.filteredRuns[0])
    compare(s.control.flashText, "Open this run's project to relaunch it", "a run with no project")
    s.screen.relaunch(null)
    compare(s.control.flashText, "This run has nothing to relaunch")
    compare(s.control.flashes.length, 7)
    compare(s.dispatch.relaunchCalls.length, 0)
    compare(s.control.controlCalls.length, 0)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs_screen`
Expected: FAIL. `closeSpy` cannot attach because `closeRequested` does not exist yet, so the count stays 0. `control()` records `close|run-20261004-park0004` and `relaunch|…`, and `s.screen.relaunch is not a function` prints a TypeError.

- [ ] **Step 4: Implement the routing in `ui/screens/RunsScreen.qml`**

(a) After `signal cancelRequested(string runId)` (and its comment), add:

```qml
  // A run's Close was clicked. Closing (am's reset) asks first, in a dialog
  // that is the owner's; nothing here resets a run.
  signal closeRequested(string runId)
```

(b) Replace `requestControl` and its comment (from `  // A row's control button: pause and resume go straight to the store, a` through its closing `  }`) with:

```qml
  // A row's control button, by its UI name: pause and resume go straight to
  // the store, cancel and close only ask the owner (cancelRequested,
  // closeRequested), and relaunch opens the dispatch (relaunch). No run id:
  // nothing.
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else if (action === "close") screen.closeRequested(id)
    else if (action === "relaunch") screen.relaunch(run)
    else screen.app.runControl.control(action, id)
  }

  // Relaunch from a row, Run detail's path applied to the row's run: a run
  // with a relaunch target, in the open project (roots by rootKey), whose
  // card is an own key of the open board's cardMap opens the dispatch dialog
  // prefilled (relaunchOpenFor); nothing starts until Start run. Otherwise
  // it flashes why and opens nothing.
  function relaunch(run) {
    var report = Runs.stopReport(run)
    if (!report || report.relaunch === null || typeof report.relaunch !== "object") {
      screen.app.runControl.flash("This run has nothing to relaunch")
      return
    }
    var project = run.project !== null && typeof run.project === "object" ? run.project : null
    var root = screen.rootKey(project !== null ? project.root : "")
    if (screen.openRoot === "" || root !== screen.openRoot) {
      screen.app.runControl.flash("Open this run's project to relaunch it")
      return
    }
    var map = screen.app.board ? screen.app.board.cardMap : null
    var cardId = report.relaunch.cardId
    if (!map || typeof map !== "object" || !Object.prototype.hasOwnProperty.call(map, cardId)) {
      screen.app.runControl.flash("The card to relaunch is no longer on the board")
      return
    }
    screen.app.runDispatch.relaunchOpenFor(map[cardId], map, report.relaunch)
  }
```

(c) In the header comment rewritten in Task 2, replace the two sentences

```
// are watched. The row with the cursor shows RunControls' buttons
// (Runs.visibleActions). It reads the run store, the run history and the
// run titles and asks the navigator to open a run or move the cursor, the
// run titles to read every project's titles again and the run history for
// older runs; it owns no state of its own.
```

with

```
// are watched. The row with the cursor shows RunControls' buttons
// (Runs.visibleActions): Pause and Resume go to the store, Cancel and Close
// ask the owner (cancelRequested, closeRequested) and Relaunch opens the
// dispatch prefilled, as Run detail's does (relaunch). It reads the run
// store, the run history, the run titles and the open board and asks the
// navigator to open a run or move the cursor, the run titles to read every
// project's titles again, the run history for older runs, run control to
// flash a refused relaunch and the dispatch to open one; it owns no state of
// its own.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs_screen` and `bash tests/run.sh tst_runs_flow`
Expected: both `0 failed`, no TypeError line.

- [ ] **Step 6: Commit**

```bash
git add ui/screens/RunsScreen.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): Runs row Close asks the owner and Relaunch opens the dispatch"
```

---

### Task 4: Run detail and Card detail emit `closeRequested` and hide RunControls' Relaunch

**Files:**
- Modify: `ui/screens/RunDetailScreen.qml` (signal ~line 48-50; `requestControl` ~line 261-268; `runDetailControls` ~line 397-409)
- Modify: `ui/screens/CardDetailScreen.qml` (signal ~line 25-27; `requestControl` ~line 44-51; `cardRunControls` ~line 296-308)
- Test: `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/screens/tst_card_detail_screen.qml`

**Interfaces:**
- Consumes: Task 1's `RunControls.relaunchShown`; `RunDetailScreen.relaunch()` (existing, no argument).
- Produces: `RunDetailScreen` signal `closeRequested(string runId)`; `CardDetailScreen` signal `closeRequested(string runId)`. Task 5's Panel connects both.

- [ ] **Step 1: Write the failing Run detail tests**

In `tests/ui/screens/tst_run_detail_screen.qml`, after `test_a_done_run_shows_no_controls`, add:

```qml
  SignalSpy { id: closeSpy; signalName: "closeRequested" }

  // runDetailControls' visible buttons, left to right, by label.
  function detailButtons(s) {
    wait(20)
    var row = H.find(H.find(s.screen, "runDetailControls"), "runControlButtons")
    var kids = []
    for (var k = 0; k < row.children.length; k++) {
      if (row.children[k].visible) kids.push(row.children[k])
    }
    kids.sort(function(a, b) { return a.x - b.x })
    return kids.map(function(b) { return b.text }).join(",")
  }

  // Detail 1: escalated and dead runs show Close only; the stop block keeps its Relaunch.
  function test_escalated_and_dead_runs_offer_close_only() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    compare(detailButtons(s), "Close")
    compare(ctl(s, "Resume").visible, false)
    compare(ctl(s, "Relaunch").visible, false)
    s.runs.runs = [run("run-x-dead0005", "started", false, {})]
    s.runs.selectedRunId = "run-x-dead0005"
    compare(detailButtons(s), "Close")
    s.runs.runs = [escalatedRun({ workflow: "task", card: "t1" })]
    s.runs.selectedRunId = "run-x-escl0002"
    compare(detailButtons(s), "Close")
    compare(part(s, "stopRelaunch").visible, true, "the stop block's Relaunch is unchanged")
    compare(part(s, "stopRelaunch").enabled, true)
  }

  // Detail 2 + 3.
  function test_parked_and_running_runs_show_the_table_all_enabled() {
    var s = make([run("run-x-park0002", "stopped", null, {})], "run-x-park0002"); if (!s) return
    compare(detailButtons(s), "Close,Resume")
    compare(ctl(s, "Close").enabled, true)
    compare(ctl(s, "Resume").enabled, true)
    compare(H.find(s.screen, "runControlReason"), null)
    var r = make(detail()); if (!r) return
    compare(detailButtons(r), "Cancel,Pause")
    compare(ctl(r, "Cancel").enabled, true)
    compare(ctl(r, "Pause").enabled, true)
  }

  // Detail 4.
  function test_close_only_asks_the_owner() {
    var s = make([run("run-x-park0002", "stopped", null, {})], "run-x-park0002"); if (!s) return
    closeSpy.target = s.screen
    closeSpy.clear()
    tap(ctl(s, "Close"))
    compare(closeSpy.count, 1)
    compare(closeSpy.signalArguments[0][0], "run-x-park0002")
    compare(s.control.controlCalls.length, 0, "no control(close) and no control(reset)")
  }

  // requestControl("relaunch") is defensive (RunControls hides Relaunch here):
  // it takes the stop block's path, never control().
  function test_a_relaunch_request_takes_the_stop_blocks_path() {
    var s = make([run("run-x-canc0004", "cancelled", null, {})], "run-x-canc0004"); if (!s) return
    s.screen.requestControl("relaunch")
    compare(s.dispatch.relaunchCalls.length, 1)
    compare(s.control.controlCalls.length, 0)
  }
```

- [ ] **Step 2: Write the failing Card detail tests**

In `tests/ui/screens/tst_card_detail_screen.qml`, after `test_cancel_run_asks_the_owner_and_starts_nothing`, add:

```qml
  SignalSpy { id: closeSpy; signalName: "closeRequested" }

  // …e5 escalated and …f6 parked, both of milestone m1 and touching story s1.
  function withStoppedRuns(s) {
    s.app.runs.snapshotRunner.cancel()
    var tree = { stories: [{ card_id: "s1", subtasks: [] }], subtasks: [] }
    s.app.runs.runs = [mkRun("run-0000000000e5", "escalated", null, "m1", tree, hoursAgo(1)),
                       mkRun("run-0000000000f6", "stopped", null, "m1", tree, hoursAgo(3))]
    return s
  }

  // Row i's visible control buttons, left to right, by label.
  function cardButtons(s, i) {
    wait(20)
    var row = H.find(H.find(s, "cardRunControls" + i), "runControlButtons")
    var kids = []
    for (var k = 0; k < row.children.length; k++) {
      if (row.children[k].visible) kids.push(row.children[k])
    }
    kids.sort(function(a, b) { return a.x - b.x })
    return kids.map(function(b) { return b.text }).join(",")
  }

  // Card 1.
  function test_a_stopped_runs_row_offers_close_and_never_relaunch() {
    var s = make(); if (!s) return
    withStoppedRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(cardButtons(s, 0), "Close run", "escalated: Close only, as a whole-run control")
    compare(cardButtons(s, 1), "Close run,Resume run", "parked")
    compare(rc(s, 0, "Relaunch").visible, false)
    compare(rc(s, 0, "Resume").visible, false)
    s.navigator.openCard("m1")
    wait(50)
    compare(cardButtons(s, 0), "Close", "a milestone card's labels are plain")
  }

  // Card 2.
  function test_close_run_asks_the_owner_and_starts_nothing() {
    var s = make(); if (!s) return
    withStoppedRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    closeSpy.target = s
    closeSpy.clear()
    mouseClick(rc(s, 1, "Close"))
    compare(closeSpy.count, 1)
    compare(closeSpy.signalArguments[0][0], "run-0000000000f6")
    compare(s.app.runControl.controlRunners.length, 0)
    compare(Object.keys(s.app.runControl.pending).length, 0)
    compare(s.app.nav.viewMode, "entry", "the button is not the row")
    s.requestControl("relaunch", s.app.runs.runs[0])
    compare(s.app.runControl.controlRunners.length, 0, "relaunch does nothing here")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_detail_screen` and `bash tests/run.sh tst_card_detail_screen`
Expected: FAIL. Escalated shows `Close,Relaunch` (not yet hidden), `closeSpy.count` is 0, and Run detail's `control()` records `close|run-x-park0002`.

- [ ] **Step 4: Implement Run detail**

In `ui/screens/RunDetailScreen.qml`:

(a) After `signal cancelRequested(string runId)` (and its comment), add:

```qml
  // The run's Close was clicked. Closing (am's reset) asks first, in a
  // dialog that is the owner's; nothing here resets a run.
  signal closeRequested(string runId)
```

(b) Replace `requestControl` and its two-line comment with:

```qml
  // A control button, by its UI name: pause and resume go straight to the
  // store, cancel and close only ask the owner (cancelRequested,
  // closeRequested). relaunch takes the stop block's path (relaunch); the
  // controls here never show it.
  function requestControl(action) {
    var id = ControlFacts.runIdOf(screen.run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else if (action === "close") screen.closeRequested(id)
    else if (action === "relaunch") screen.relaunch()
    else screen.app.runControl.control(action, id)
  }
```

(c) In the `UI.RunControls { objectName: "runDetailControls" … }` block, add after `showButtons: true`:

```qml
      // The stop block has this run's Relaunch, gated by offersRelaunch.
      relaunchShown: false
```

- [ ] **Step 5: Implement Card detail**

In `ui/screens/CardDetailScreen.qml`:

(a) After `signal cancelRequested(string runId)` (and its comment), add:

```qml
  // A run's Close was clicked. Closing (am's reset) asks first, in a dialog
  // that is the owner's; nothing here resets a run.
  signal closeRequested(string runId)
```

(b) Replace `requestControl` and its two-line comment with:

```qml
  // A run row's control button, by its UI name: pause and resume go straight
  // to the store, cancel and close only ask the owner (cancelRequested,
  // closeRequested); relaunch does nothing here (a card has no relaunch path;
  // a click on the row opens Run detail).
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") detailCard.cancelRequested(id)
    else if (action === "close") detailCard.closeRequested(id)
    else if (action !== "relaunch") detailCard.app.runControl.control(action, id)
  }
```

(c) In the `UI.RunControls { objectName: "cardRunControls" + runRow.modelData … }` block, add after `showButtons: true`:

```qml
        relaunchShown: false
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_detail_screen`, `bash tests/run.sh tst_card_detail_screen`, `bash tests/run.sh tst_runs_flow`
Expected: each `0 failed`, no TypeError line.

- [ ] **Step 7: Commit**

```bash
git add ui/screens/RunDetailScreen.qml ui/screens/CardDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml tests/ui/screens/tst_card_detail_screen.qml
git commit -m "feat(runs): Run detail and Card detail ask the owner to Close and hide Relaunch"
```

---

### Task 5: Panel mounts the Close dialog; Shortcuts treats it as a modal

**Files:**
- Modify: `ui/Panel.qml` (Connections ~line 105-109; `focusItem` ~line 188-198; `CardDetailScreen` ~line 732-740; `RunsScreen` ~line 759-766; `RunDetailScreen` ~line 768-775; after `runCancelModal` ~line 856)
- Modify: `ui/Shortcuts.qml` (`closeRequested` ~line 46-48; `modalOpen` ~line 53-58)
- Test: `tests/ui/tst_runs_flow.qml`, `tests/ui/tst_shortcuts.qml`

**Interfaces:**
- Consumes: Tasks 3-4's `closeRequested(string runId)` on `RunsScreen`, `RunDetailScreen` and `CardDetailScreen`. Store: `appStores.runControl.closeAsk(runId)` → bool (flashes and returns false on refusal), `closeKeep()`, `closeConfirm()` → bool, `closeOpen` (readonly bool), `closeRunId`, `closeError`. `CloseRunDialog` props `shown`, `runTitle`, `openIn`, `error`, `busy`, `theme`; signals `confirmRequested()`, `cancelRequested()`; `focusItem` (objectName `closeDialogKeys`); children `closeDialogTitle`, `closeDialogError`, `closeDialogKeep`, `closeDialogAccept`.
- Produces: Panel item `runCloseModal`; `Shortcuts.modalOpen()` true while `closeOpen`; Escape calls `closeKeep()` before the cancel confirmation.

- [ ] **Step 1: Write the failing Shortcuts tests**

In `tests/ui/tst_shortcuts.qml`, after `test_the_cancel_dialog_closes_before_the_toasts`, add:

```qml
  // Close dialog 1 + 2.
  function test_the_close_dialog_is_a_modal_and_escape_closes_only_it() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000b2")
    compare(s.modalOpen(), false)
    compare(s.app.runControl.closeAsk("run-0000000000b2"), true)
    compare(s.modalOpen(), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_R)), false)
    compare(Object.keys(s.app.runControl.pending).length, 0)
    s.closeRequested()
    compare(s.app.runControl.closeOpen, false)
    compare(s.app.nav.viewMode, "run", "Escape closed the dialog only")
    compare(tc.calls.indexOf("close"), -1)
    compare(s.app.runControl.controlRunners.length, 0, "closeKeep starts nothing")
    compare(s.modalOpen(), false)
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs", "the next Escape goes back as before")
  }

  // Review Focus 4.
  function test_escape_closes_the_close_dialog_before_the_cancel_confirmation() {
    var s = inRunKeys(); if (!s) return
    compare(s.app.runControl.openCancel("run-0000000000a1"), true)
    compare(s.app.runControl.closeAsk("run-0000000000b2"), true)
    s.closeRequested()
    compare(s.app.runControl.closeOpen, false)
    compare(s.app.runControl.cancelOpen, true, "the cancel confirmation is next")
    s.closeRequested()
    compare(s.app.runControl.cancelOpen, false)
    compare(s.app.nav.viewMode, "runs")
    compare(tc.calls.indexOf("close"), -1)
  }
```

- [ ] **Step 2: Write the failing flow tests**

In `tests/ui/tst_runs_flow.qml`, after `test_closing_on_run_detail_gives_the_focus_back_to_the_key_catcher` (it sits in the Resume section, where `indexOfRun`, `argv` and `endsWith` are defined), add:

```qml
  // ---- the Close dialog (RR)

  function closeModal(p) { return H.find(p, "runCloseModal") }

  // The Runs list with the cursor on run `id`.
  function runsCursorOn(p, id) {
    p.navigator.showSection("runs")
    wait(50)
    p.app.nav.cursorIndex = indexOfRun(p, id)
    wait(50)
  }

  // A part of run `id`'s row controls.
  function rowControl(p, id, name) {
    return H.find(H.find(p, "runRowControls" + indexOfRun(p, id)), "runControl" + name)
  }

  // Flow 1 + 2.
  function test_close_on_a_parked_row_opens_the_dialog_and_keep_and_escape_dismiss_it() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData([{ id: "delta", title: "Delta work", status: "todo", description: "",
                                 blocked_by: [], children: [] }])
    runsCursorOn(p, "run-0000000000d4")
    var close = rowControl(p, "run-0000000000d4", "Close")
    compare(close.visible, true)
    compare(close.enabled, true)
    mouseClick(close)
    wait(50)
    var modal = closeModal(p)
    verify(modal, "the Close dialog is mounted")
    compare(modal.visible, true)
    compare(p.app.runControl.closeRunId, "run-0000000000d4")
    compare(H.find(modal, "closeDialogTitle").text, "Close \"Delta work\"?")
    compare(p.focusItem.objectName, "closeDialogKeys")
    verify(H.find(modal, "closeDialogKeys").activeFocus, "the dialog has the keyboard")
    compare(p.app.runControl.controlRunners.length, 0, "asking starts nothing")
    compare(p.app.nav.viewMode, "runs", "the click did not open the run")

    wait(450)
    mouseClick(H.find(modal, "closeDialogKeep"))
    compare(p.app.runControl.closeOpen, false)
    compare(modal.visible, false)
    wait(50)
    compare(p.focusItem.objectName, "searchField", "the focus comes back")

    p.app.runControl.closeAsk("run-0000000000d4")
    wait(50)
    compare(modal.visible, true)
    keyClick(Qt.Key_Escape)
    compare(p.app.runControl.closeOpen, false)
    compare(p.app.nav.viewMode, "runs")
    compare(p.opened, true, "the panel stays open")
    compare(p.app.runControl.controlRunners.length, 0)
    wait(50)
    compare(p.focusItem.objectName, "searchField")
  }

  // Flow 3 + 5 (a refused closeAsk).
  function test_close_accept_starts_one_reset_and_the_row_reads_close_requested() {
    var p = make(); if (!p) return
    runsCursorOn(p, "run-0000000000d4")
    mouseClick(rowControl(p, "run-0000000000d4", "Close"))
    wait(50)
    compare(H.find(closeModal(p), "closeDialogTitle").text, "Close \"milestone …delta\"?")
    wait(450)
    mouseClick(H.find(closeModal(p), "closeDialogAccept"))
    compare(p.app.runControl.controlRunners.length, 1)
    var runner = p.app.runControl.controlRunners[0]
    compare(runner.action, "reset")
    compare(runner.runId, "run-0000000000d4")
    var command = argv(runner.current)
    verify(command.indexOf("runs/run-control.py") >= 0, command)
    verify(endsWith(command, "reset|run-0000000000d4|/home/u/a"), command)
    compare(p.app.runControl.pending["run-0000000000d4"], "reset")
    compare(p.app.runControl.closeOpen, false)
    wait(50)
    var marker = rowControl(p, "run-0000000000d4", "Close")
    compare(marker.visible, true)
    compare(marker.text, "Close requested…")
    compare(marker.enabled, false)
    compare(rowControl(p, "run-0000000000d4", "Resume").visible, false)

    H.find(p, "runsView").closeRequested("run-0000000000d4")
    compare(p.app.runControl.closeOpen, false, "a refused closeAsk opens nothing")
    compare(H.find(p, "runsFooter").text, "A request for this run is pending")
    compare(p.app.runControl.controlRunners.length, 1)
  }

  // Flow 4 + Review Focus 3.
  function test_a_run_that_starts_running_under_the_dialog_keeps_it_open_with_why() {
    var p = make(); if (!p) return
    runsCursorOn(p, "run-0000000000d4")
    mouseClick(rowControl(p, "run-0000000000d4", "Close"))
    wait(50)
    compare(p.app.runControl.closeOpen, true)
    var runs = sampleRuns()
    runs[3] = run("run-0000000000d4", "started", true, "delta")
    p.app.runs.runs = runs
    wait(450)
    mouseClick(H.find(closeModal(p), "closeDialogAccept"))
    compare(p.app.runControl.closeOpen, true)
    var error = H.find(closeModal(p), "closeDialogError")
    compare(error.visible, true)
    compare(error.text, "A running run is cancelled, not closed")
    compare(p.app.runControl.controlRunners.length, 0)
    compare(Object.keys(p.app.runControl.pending).length, 0)
    p.app.runControl.closeKeep()
  }

  // Flow 5.
  function test_a_running_row_never_offers_close() {
    var p = make(); if (!p) return
    runsCursorOn(p, "run-0000000000a1")
    compare(rowControl(p, "run-0000000000a1", "Close").visible, false)
    compare(rowControl(p, "run-0000000000a1", "Cancel").visible, true)
    compare(rowControl(p, "run-0000000000a1", "Pause").visible, true)
  }

  // Flow 6.
  function test_global_chords_and_run_keys_are_dead_under_the_close_dialog() {
    var p = make(); if (!p) return
    runsCursorOn(p, "run-0000000000d4")
    compare(p.app.runControl.closeAsk("run-0000000000d4"), true)
    wait(50)
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_1 }), false)
    compare(p.app.nav.viewMode, "runs")
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), false)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_R)), false)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), false)
    compare(p.shortcuts.handleDispatchKey(key(Qt.Key_D)), false)
    compare(p.app.runControl.cancelOpen, false)
    compare(Object.keys(p.app.runControl.pending).length, 0)
    compare(p.app.runControl.controlRunners.length, 0)
    p.app.runControl.closeKeep()
  }

  // Review Focus 4.
  function test_with_both_dialogs_open_the_close_dialog_takes_the_focus_and_escape_first() {
    var p = make(); if (!p) return
    runsCursorOn(p, "run-0000000000d4")
    compare(p.app.runControl.openCancel("run-0000000000a1"), true)
    compare(p.app.runControl.closeAsk("run-0000000000d4"), true)
    wait(50)
    compare(p.focusItem.objectName, "closeDialogKeys")
    keyClick(Qt.Key_Escape)
    compare(p.app.runControl.closeOpen, false)
    compare(p.app.runControl.cancelOpen, true)
    wait(50)
    compare(p.focusItem.objectName, "runCancelField")
    p.app.runControl.closeCancel()
  }

  // Flow 7.
  function test_relaunch_on_an_escalated_row_opens_the_prefilled_dispatch_dialog() {
    var p = make(); if (!p) return
    p.app.backendDir = "/plugin/core/backend/"
    p.app.runControl.applyRunSettings(p.app.runs.project, { verify: ["uv run pytest"] })
    p.app.board.applyTreeData([{ id: "m1", title: "M one", status: "todo", description: "d", children: [] }])
    var r = run("run-0000000000e5", "escalated", null, "m1")
    r.branch_prefix = "old-m1"
    r.base_branch = "release"
    p.app.runs.runs = [r]
    runsCursorOn(p, "run-0000000000e5")
    var relaunch = rowControl(p, "run-0000000000e5", "Relaunch")
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    mouseClick(relaunch)
    compare(p.app.runDispatch.dispatchState, "previewing")
    wait(50)
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(H.find(p, "dispatchPrefix").text, "old-m1")
    compare(H.find(p, "dispatchBase").text, "release")
    compare(p.app.runControl.controlRunners.length, 0, "relaunch is not a control request")
    compare(p.app.nav.viewMode, "runs", "the click did not open the run")
  }

  // Flow 8 (and Card detail, the third surface).
  function test_close_on_run_detail_and_on_a_card_opens_the_same_dialog() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000d4")
    wait(50)
    var detail = H.find(p, "runDetailControls")
    compare(H.find(detail, "runControlRelaunch").visible, false)
    var close = H.find(detail, "runControlClose")
    compare(close.visible, true)
    mouseClick(close)
    wait(50)
    compare(closeModal(p).visible, true)
    compare(p.app.runControl.closeRunId, "run-0000000000d4")
    compare(p.focusItem.objectName, "closeDialogKeys")
    keyClick(Qt.Key_Escape)
    compare(p.app.runControl.closeOpen, false)
    compare(p.app.nav.viewMode, "run", "Escape closed only the dialog")
    wait(50)
    compare(p.focusItem.objectName, "keyCatcher")

    p.app.board.applyTreeData([{ id: "delta", title: "Delta work", status: "todo", description: "d",
                                 blocked_by: [], children: [] }])
    wait(50)
    p.navigator.openCard("delta")
    wait(50)
    compare(p.app.nav.viewMode, "entry")
    var cardClose = H.find(H.find(p, "cardRunControls0"), "runControlClose")
    verify(cardClose, "the card's RUNS row carries the run's Close")
    wait(450)
    mouseClick(cardClose)
    wait(50)
    compare(closeModal(p).visible, true)
    compare(p.app.runControl.closeRunId, "run-0000000000d4")
    p.app.runControl.closeKeep()
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_shortcuts` and `bash tests/run.sh tst_runs_flow`
Expected: FAIL. `modalOpen()` is false under the Close dialog, Escape goes Back instead of `closeKeep()`, and `runCloseModal` is not found, so `closeModal(p)` is null.

- [ ] **Step 4: Implement Shortcuts**

In `ui/Shortcuts.qml`:

(a) In `closeRequested()`, insert the Close dialog immediately before the cancel confirmation. In the one-line ternary, replace

```
keys.app.runControl.cancelOpen ? keys.app.runControl.closeCancel()
```

with

```
keys.app.runControl.closeOpen ? keys.app.runControl.closeKeep() : keys.app.runControl.cancelOpen ? keys.app.runControl.closeCancel()
```

and change that function's comment line `// refuses, so that Escape does nothing at all. The Resume dialog closes` / `// after the cancel confirmation and before the toasts.` to read:

```
  // refuses, so that Escape does nothing at all. The Close dialog closes
  // (closeKeep) right before the cancel confirmation, matching Panel's focus
  // order; the Resume dialog after the cancel confirmation and before the
  // toasts.
```

(b) Replace `modalOpen()` with:

```qml
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runControl.cancelOpen
              || keys.app.runControl.closeOpen
              || keys.app.runDispatch.dispatchState !== "idle" || keys.app.runDispatch.dispatchStep !== ""
              || keys.app.runControl.resumeRunId !== "")
  }
```

- [ ] **Step 5: Implement Panel**

In `ui/Panel.qml`:

(a) In the `Connections { target: appStores.runControl … }` block, add after `function onCancelOpenChanged() { root.focusForView() }`:

```qml
    function onCloseOpenChanged() { root.focusForView() }
```

(b) In `readonly property Item focusItem:`, insert immediately before the line `    : appStores.runControl.cancelOpen ? runCancelModal.focusItem`:

```qml
    : appStores.runControl.closeOpen ? runCloseModal.focusItem
```

(c) In the `CardDetailScreen { … }` block, add after its `onCancelRequested` line:

```qml
            onCloseRequested: function(runId) { appStores.runControl.closeAsk(runId) }
```

Add the same line after the `onCancelRequested` line of the `RunsScreen { … }` block and of the `RunDetailScreen { … }` block.

(d) Immediately after the closing `}` of the `TypedConfirmDialog { id: runCancelModal … }` block, before the `// The Resume dialog:` comment, add:

```qml
      // The Close dialog (RR): any run surface's Close asks the run store
      // (closeAsk), which opens it or flashes why not; only its Close button
      // resets the run (closeConfirm); Keep, the backdrop and Escape dismiss
      // it (closeKeep). Its focus comes before the cancel confirmation's.
      CloseRunDialog {
        id: runCloseModal
        objectName: "runCloseModal"
        // The run the dialog asks about; null when it is not listed.
        readonly property var closeRun: appStores.runs.runById(appStores.runControl.closeRunId)
        anchors.fill: parent
        shown: appStores.runControl.closeOpen
        runTitle: runCloseModal.closeRun
          ? Runs.runTitle(runCloseModal.closeRun, Runs.titlesOfRun(runCloseModal.closeRun, appStores.runTitles.titlesByRoot))
          : ""
        openIn: ""
        busy: false
        error: appStores.runControl.closeError
        theme: panelTheme
        onConfirmRequested: appStores.runControl.closeConfirm()
        onCancelRequested: appStores.runControl.closeKeep()
      }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_shortcuts`, `bash tests/run.sh tst_runs_flow`, `bash tests/run.sh tst_panel`, `bash tests/run.sh tst_close_run_dialog`
Expected: each file `0 failed`, no TypeError/ReferenceError line. (`tst_panel` may match no file; that is fine.)

- [ ] **Step 7: Commit**

```bash
git add ui/Panel.qml ui/Shortcuts.qml tests/ui/tst_runs_flow.qml tests/ui/tst_shortcuts.qml
git commit -m "feat(panel): mount the Close dialog and treat it as a modal"
```

---

### Task 6: Docs, and the whole suite

**Files:**
- Modify: `docs/architecture.md` (line 169, the `RunControls` sentence; line 186, the run-screens paragraph)
- Modify: `README.md` (line 154, the **Runs** bullet)

**Interfaces:**
- Consumes: the behaviour of Tasks 1-5.
- Produces: docs that `tests/architecture/test_run_store_docs.py` still accepts (README names no store; every `app.<handle>` fact stays).

Each edit below replaces one exact sentence. These lines are very long single lines, so use the Edit tool with the quoted old text as `old_string`, verbatim.

- [ ] **Step 1: Run the docs tests first (they pass now, and must still pass after)**

Run: `python3 -m pytest tests/architecture -q` (or `uv run --with pytest python3 -m pytest tests/architecture -q` if `python3` has no pytest)
Expected: all pass.

- [ ] **Step 2: Edit `docs/architecture.md` line 169**

Replace:

```
`RunControls` (one run's `ActionButton`s -- Pause `⏸`, Resume `⟳`, Cancel `⊘` in `danger`, glyphs from `runGlyphs.js` -- with at most one of Pause and Resume: Pause on a running run, Resume on a parked, escalated or dead one, and a pending request keeps its own button reading `… requested…`; enabled and tooltip from `Runs.controls(run)`, every button disabled while a request is pending; a reason line repeats the shown disabled buttons' reasons, because a disabled shell Button gets no hover and so no tooltip; `wholeRun` adds `run` to the labels and an `applies to the whole run` caption; then the still-waiting line and the control error in `urgent`. A finished, unknown or missing run shows nothing and the component is 0 tall. Presentation only, like `RunIndicator`: the owner passes the run, `pendingAction`, `waiting`, `waitingText`, `errorText` and `showButtons`, and a click on an enabled button emits `actionRequested(action)`.
```

with:

```
`RunControls` (one run's `ActionButton`s, exactly `Runs.visibleActions(run)` left to right -- running: Cancel in `danger`, Pause in `warn`; parked: Close in `close`, Resume in `accent`; escalated and dead: Close, Relaunch in `accent`; Integrate drops Pause, Cancel and Close; done, cancelled, unknown or missing: none -- with no glyph and no disabled button, except that while a request is pending only that request's button shows (a pending `reset` is the Close button), labelled `<Word> requested…` and disabled as a progress marker; `relaunchShown: false` drops Relaunch; `wholeRun` adds `run` to the labels and an `applies to the whole run` caption; then the still-waiting line and the control error in `urgent`. There is no reason line. With nothing to show the component is 0 tall. Presentation only, like `RunIndicator`: the owner passes the run, `pendingAction`, `waiting`, `waitingText`, `errorText`, `showButtons` and `relaunchShown`, and a click emits `actionRequested(action)` with the UI's `cancel`, `pause`, `close`, `resume` or `relaunch`, never `reset`.
```

- [ ] **Step 3: Edit `docs/architecture.md` line 186 (five sentences)**

(a) Replace

```
`RunsScreen` also `app.runHistory`; Run detail also `app.runDispatch` for Relaunch
```

with

```
`RunsScreen` also `app.runHistory`, and `app.board` and `app.runDispatch` for a row's Relaunch; Run detail also `app.runDispatch` for Relaunch
```

(b) Replace

```
Each run is one row (state glyph; title, `runTitle` with the run's own project map `titlesOfRun(run, app.runTitles.titlesByRoot)`; the short id, `runSubtitle`, in `dim`; done/total, current phase, age; a dead run's age is since its last heartbeat, and an escalated run adds `escalationReason`) whose index is its position in `filteredRuns`.
```

with

```
Each run is one row whose index is its position in `filteredRuns`. Its first line reads, left to right, the row id in `dim` (`rowIdOf`: the first 8 characters of `milestone_id`, else the last 8 of the run id, raw, no `…`), the title (`runTitle` with the run's own project map `titlesOfRun(run, app.runTitles.titlesByRoot)`, taking the width the others leave and eliding), a `RunLevelBadge` (`Runs.runLevel`), a `RunStateBadge` for a running or escalated run, and, right-aligned, the meta (`metaText`: done/total, the current phase or `parked` for a parked run, and the age, joined by ` · ` in `dim`; a dead run's `dead - lease lost <age> ago` in `urgent`, its age since its last heartbeat); an escalated run's `escalationReason` follows on a second line, flush left, in `warn`. There is no state glyph and no `Open project`.
```

(c) Replace

```
The row with the cursor shows `Open project` for a run of a registered project other than the open one, which asks the navigator to choose that project (`navigator.chooseProject`).
```

with

```
The row with the cursor shows its `RunControls` buttons (Cancel and Pause, Close and Resume, or Close and Relaunch). Its Relaunch takes Run detail's path: with no relaunch target it flashes `This run has nothing to relaunch`, outside the open project `Open this run's project to relaunch it`, and when the target card is not an own key of `app.board.cardMap` `The card to relaunch is no longer on the board`; otherwise `app.runDispatch.relaunchOpenFor(card, cardMap, relaunch)` opens the dispatch dialog prefilled, and nothing starts until Start run.
```

(d) Replace

```
Each of the three run surfaces carries a `RunControls` per run: a Runs row in its `ListRow.actions`, showing the buttons while the row has the cursor (hover moves the cursor) or a request is pending; Run detail under the header, always; a card's RUNS row in its `actions`, always, as whole-run controls (`Pause run`, the caption) on a story or subtask card.
```

with

```
Each of the three run surfaces carries a `RunControls` per run: a Runs row in its `ListRow.actions`, showing the buttons while the row has the cursor (hover moves the cursor) or a request is pending, Relaunch included; Run detail under the header, always, with `relaunchShown: false` (its stop block has the run's Relaunch), so an escalated or dead run shows Close only; a card's RUNS row in its `actions`, always, with `relaunchShown: false`, as whole-run controls (`Pause run`, `Close run`, the caption) on a story or subtask card.
```

(e) Replace

```
Pause and Resume call `app.runControl.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` -- confirming a cancel is the owner's job, and no screen calls `control("cancel", …)`.
```

with

```
Pause and Resume call `app.runControl.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` and Close its `closeRequested(runId)` -- confirming either is the owner's job, and no screen calls `control("cancel", …)`, `control("close", …)` or `control("reset", …)`.
```

(f) Immediately after the sentence that ends `and only its confirm (\`confirmCancel()\`) calls \`control("cancel", …)\` -- a run that changed under it keeps it open with the reason.` and before ` Panel mounts \`resumeVerifyDialog\``, insert (with one leading space):

```
 Panel answers every `closeRequested` with `app.runControl.closeAsk(runId)`, which flashes the refusal (`refusalOf("reset", id)`) or opens `runCloseModal`, a `CloseRunDialog` beside `runCancelModal`: `Close "<title>"?` (the run's `runTitle`, `Close this run?` when it is not listed), that the run is recorded as cancelled and nothing is deleted, `closeError` in `urgent`, then Keep and an orange Close; `openIn` is blank and `busy` false. It takes the focus while open (before the cancel confirmation in `focusItem`, through `onCloseOpenChanged`) and gives it back on close; Keep, the backdrop and Escape call `closeKeep()`, and only its Close (`closeConfirm()`) starts a reset -- a run that changed under it keeps it open with the reason. `Shortcuts.modalOpen()` is true while it is open, and Escape closes it right before the cancel confirmation.
```

- [ ] **Step 4: Edit `README.md` line 154 (two sentences)**

(a) Replace

```
a run of any registered project can also be paused, resumed or cancelled from the panel, which acts on the run's own repository whatever project is open, and the row under the cursor offers **Open project** for a run of another registered project, which opens that project.
```

with

```
a run of any registered project can also be paused, resumed, cancelled, closed or relaunched from the panel, which acts on the run's own repository whatever project is open. The row under the cursor shows the buttons its state allows, and only those: a running run **Cancel** and **Pause**, a parked one **Close** and **Resume**, an escalated or dead one **Close** and **Relaunch** (a run in Integrate drops Pause, Cancel and Close). No button is ever shown disabled, except that while a request is pending its button reads `<Word> requested…` until the run acts on it. **Close** asks first, in a dialog (`Close "<title>"?`, **Keep** / **Close**): the run is recorded as cancelled, nothing is deleted and no branch is touched; only the dialog's **Close** closes it, and **Keep** or Escape dismisses it. **Relaunch** on a row opens the dispatch dialog prefilled with the run's branch prefix and base, as Run detail's does; it needs the run's project open and its card still on the board, and says why otherwise. Run detail and a card's RUNS rows show the same buttons without **Relaunch** (Run detail keeps its own under **Why it stopped**).
```

(b) Replace

```
Each row shows the run's state glyph and its title -- the title of the run's milestone, story or card on that project's own board, else the kind and the id's last 8 characters (`milestone …<8>`) -- with the short id dimmed after it, then done/total subtasks, current phase and age; a dead run says `dead - lease lost <age> ago`, and an escalated one says why.
```

with

```
Each row shows the run's id dimmed (the first 8 characters of its milestone id, else the last 8 of the run id), its title -- the title of the run's milestone, story or card on that project's own board, else the kind and the id's last 8 characters (`milestone …<8>`) -- a badge naming its level (MILESTONE, STORY or SUBTASK), a RUNNING or ESCALATED badge for those two states, and on the right done/total subtasks, current phase (`parked` for a parked run) and age; a dead run says `dead - lease lost <age> ago` there instead, and an escalated one says why on a second line.
```

- [ ] **Step 5: Verify the edits landed and the docs tests still pass**

Run: `grep -c "Open project" README.md docs/architecture.md` → Expected: `README.md:0` and `docs/architecture.md:0`.
Run: `grep -c "closeRequested" docs/architecture.md` → Expected: a number ≥ 1.
Run: `python3 -m pytest tests/architecture -q` → Expected: all pass (README still names no store; every `app.<handle>` fact kept).

- [ ] **Step 6: Run the whole suite (definition of done)**

Run in the background: `timeout 900 bash tests/run.sh > /tmp/run-d4e1b8b1.log 2>&1; echo exit=$?`
Expected: `exit=0`. Every `Totals:` line in the log shows `0 failed`, and `grep -E "TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function" /tmp/run-d4e1b8b1.log` prints nothing.

- [ ] **Step 7: Commit**

```bash
git add docs/architecture.md README.md
git commit -m "docs(runs): describe the new Runs row, its buttons, Close and Relaunch"
```

---

## Self-review (done while writing; kept for the executor)

- **Spec coverage.** RunControls → Task 1. RunRow layout, row id, meta, `stateText`, removals → Task 2. `requestControl`, `closeRequested` and `relaunch(run)` on RunsScreen → Task 3. Run detail and Card detail → Task 4. Panel dialog, focus, Connections, the three `onCloseRequested`, and Shortcuts → Task 5. Docs → Task 6. Every test tier the spec lists has its tests: component 1-16 (Task 1); runs screen 1-10 (Tasks 2-3, item 10 through the id-literal script); run detail 1-5 (Task 4); card detail 1-2 (Task 4); flow 1-9 (Tasks 1, 2, 5); shortcuts 1-2 (Task 5); real data (Task 2); architecture (Task 6 Step 5).
- **Deviation noted.** Spec Tests §10 asks for the chip / header / Show older / cursor tests to pass "unmodified". That cannot hold for their `runRowId<i>` literals, because the spec itself changes the row id format (spec test 1: "existing `…live0001` expectations become …"). Task 2 Step 1 changes only those literals, function-scoped, and no other line of those tests. Two more existing tests change because the spec changes what they assert: `test_integrate_disables_…` in the flow tier (Integrate buttons are now hidden, not disabled) and the real-data card/row id comparison (the row id has no `…`).
- **Type consistency.** The UI names `cancel` / `pause` / `close` / `resume` / `relaunch` and the store names `pause` / `resume` / `cancel` / `reset` are used the same way in every task. `closeRequested(string runId)` has the same signature on all three screens. `relaunchShown` is the same name in Tasks 1, 2 and 4. The objectNames in Task 2 match those Task 5 reads (`runRowControls<i>`, `runControlClose`, `runsView`, `runsFooter`).
<!-- task-pipeline: validated -->
