# 4.3 Cancel confirmation and keyboard shortcuts (card b4bc1521)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2,
"the parent" below): "Control actions" (lines 29-53, cancel row line 35),
"Architecture" bullet 4 (lines 70-74), "UI" (lines 79-104), "Testing" (lines
157-160). Parent story f03629a7 ("Control store and UI"). Blocked by 4.2
(1c268d85, spec `4-2-runcontrols-1c268d85.md`), which is done on this branch.

This card makes Cancel actually cancel (after a typed `cancel`), and adds the
`p` / `r` / `c` keys with a footer flash for a refused key. Toasts and desktop
alerts are card 4.4 (22153f5f).

## Starting point

- `ui/components/TypedConfirmDialog.qml` already has `confirmWord` (line 33,
  default `"delete"`, matched trimmed and case-blind, also the placeholder),
  `typedText` / `typedEdited`, `error`, `busy`, `message`, `detail`,
  `confirmLabel`, the three objectName props (lines 25-27) and `focusItem`
  (line 34). Its dismiss button (`confirmCancel`, line 113) hard-codes the text
  `"Cancel"`. Escape in its field emits `cancelRequested` (line 92); Return /
  Enter emits `confirmRequested` only when the word matches (lines 93-95).
- `core/stores/RunStore.qml` `control(action, runId)` → bool (line 445): refuses
  no project, an unknown action, an unknown run, an action `Runs.controls` has
  disabled, a run with a request pending. **Confirming a cancel is the caller's
  job** (comment above line 445). `runById(id)` (line 242),
  `projectSwitched()` (line 217), `pending`, `lastControlError`.
- `core/domain/runs.js` `controls(run)` (line 666) → `{pause, resume, cancel}`
  each `{enabled, reason}`; reasons at lines 645-651, among them
  `"Integrate is running; it cannot be paused or cancelled"` (parent lines
  44-46). A run is in Integrate when it has a lease whose `accepting` is not
  `true` (`_inIntegrate`, line 658).
- `RunsScreen`, `RunDetailScreen` and `CardDetailScreen` each emit
  `cancelRequested(string runId)` for a Cancel click (4.2 spec D3) and **nothing
  handles it**: in `ui/Panel.qml` (instances at ~549, ~574, ~581) no handler is
  wired, so Cancel does nothing today.
- `ui/components/RunControls.qml` `tooltipOf` (line 86) says
  `"A request for this run is pending"` for a button disabled by another
  pending request.
- `ui/Shortcuts.qml`: `handleGlobalKey` (line 23) handles Ctrl chords only and
  returns false at once without Ctrl; its first line is the modal guard list.
  `closeRequested()` (line 38) is the Escape chain. The ORDER of guards is load
  bearing (file header, lines 6-8).
- Key routing in `ui/Panel.qml`: `globalKeys` (an `Item` whose
  `Keys.onPressed` calls `sc.handleGlobalKey`) receives every key forwarded by
  `keyCatcher` and by `searchField` (both `Keys.forwardTo: [globalKeys]`).
  `focusItem` (line ~166) gives the key catcher the focus on view `run` and
  the search field on view `runs`. So on the Runs list every letter goes to
  the search field unless something accepts it first.
- `Runs.searchRuns` (runs.js line 405) matches id, title, current phase and
  **run state**, case-blind. States `cancelled`, `parked`, `running` start
  with `c`, `p`, `r`: see D4.
- The Runs screen's footer is `runsFooter` (`RunsScreen.qml` lines 116-126,
  hidden while am is missing or the schema banner shows). Run detail has no
  footer.

## Scope

In scope:

- `core/stores/RunStore.qml`: the cancel dialog's state and functions, the
  footer flash, and `refusalOf` (D1, D2, D3).
- `ui/components/TypedConfirmDialog.qml`: a `dismissLabel` property (D5).
- `ui/Panel.qml`: a third `TypedConfirmDialog` for the run cancel, the
  `focusItem` chain, `cancelRequested` wired on the three run screens, and
  `globalKeys` calling the new run-key handler.
- `ui/Shortcuts.qml`: `handleRunKey(event)`, the cancel dialog in
  `handleGlobalKey`'s modal guard and in the Escape chain.
- `ui/screens/RunsScreen.qml` (flash in `runsFooter`) and
  `ui/screens/RunDetailScreen.qml` (a new flash line).
- `docs/architecture.md`: the `TypedConfirmDialog` entry (`dismissLabel`), the
  `Shortcuts.qml` description (line ~97), the run screens paragraph (line 150:
  Cancel now opens the confirmation; the flash).
- Tests listed under "Tests".

### Out of scope

- `RunToast`, `newAlerts`, `notify.py`, "Notify on escalation": card 4.4.
- The Resume confirm step / verify-set form (parent lines 34, 49-52): `r` and
  the Resume button call `control("resume", id)` straight away, as in 4.2.
- Keys on any view other than `runs` and `run` (a card's RUNS rows on view
  `entry` get the dialog through their Cancel button only, no keys). Parent
  line 102 names "the Runs screen and Run detail" only.
- A flash for a click on a disabled button: a disabled shell Button receives no
  click (4.2 spec D8). Only keys flash.
- Any change to `runs.js`, `RunControls.qml`, `ListRow.qml`, `App.qml`, or the
  backend helpers. No new component file.
- Changing `TypedConfirmDialog`'s behaviour for its existing callers: both
  existing instances keep `"Cancel"` as their dismiss text.

## Decisions

- **D1. The run store owns the cancel dialog.** Every panel dialog is driven by
  a store (`deleter.deleteTarget`, `memories.memoryDeleteOpen`,
  `board.archiveOpen`); `TypedConfirmDialog` "renders and emits only". The
  dialog's run, typed text and error live on `RunStore` (`app.runs`); stores
  know no UI (docs/architecture.md line 15). Panel renders it.
- **D2. One refusal rule for keys and the dialog: `refusalOf(action, runId)`.**
  It returns `""` when `control(action, runId)` would start a request, and
  otherwise the sentence saying why not, checked in this order: no project or
  a run not in the snapshot → `"This run is no longer in the snapshot"` (the
  Run detail missing line's wording); a request pending for the run →
  `"A request for this run is pending"` (RunControls' tooltip wording); the
  action disabled → `Runs.controls(run)[action].reason`. An action other than
  `pause` / `resume` / `cancel` → `"Unknown control"`. The keys flash it;
  `openCancel` and `confirmCancel` use it.
- **D3. The footer flash is store state with a timer.** `flashText` (string,
  `""` when none) set by `flash(text)`, cleared 3000 ms later by `flashTimer`
  (exposed as a readonly alias for tests, like `pendingTimer`). A new flash
  replaces the text and restarts the clock. A project switch clears it and
  stops the timer. The store keeps it because both run screens show it and the
  screens own no state (`RunsScreen.qml` header, lines 12-14).
- **D4. On the Runs list, `p` / `r` / `c` are shortcuts only while the search
  text is empty.** The search field holds the focus on view `runs`, and the
  parent asks for plain letters (line 102). With an empty search the key acts
  on the cursor row and is **not** typed. Once the search has any text, every
  letter types as before. Search is case-blind and a shortcut needs no
  modifier at all, so Shift+P / Shift+R / Shift+C always type: that is how a
  search for `parked`, `running` or `cancelled` starts. On view `run` the key
  catcher has the focus and no text is typed, so the keys always act.
- **D5. `TypedConfirmDialog` gains `dismissLabel` (default `"Cancel"`).** The
  parent's mock (line 98) reads `[ Keep running ] [ Cancel run ]`, and a
  dismiss button reading "Cancel" beside "Cancel run" would make the safe
  choice read like the destructive one. Parent lines 73-74 call `confirmWord`
  "the only change to an existing component"; that line is about 3.1's
  generalisation, and this is a second, additive property whose default leaves
  both existing callers exactly as they are. Its tests are appended, not
  rewritten (parent line 74).
- **D6. A refused confirm keeps the dialog open.** If the run changed under the
  open dialog (finished, entered Integrate, got another request pending,
  vanished), `confirmCancel` calls nothing, leaves the dialog open and shows
  `refusalOf("cancel", id)` as the dialog's `error`. Keep running / Escape
  closes it. A started request closes the dialog at once; what happens next is
  4.1/4.2's pending lifecycle (the row reads `Cancel requested…`, a refusal
  shows inline under the row).

## Behaviour

### `RunStore` (`core/stores/RunStore.qml`)

New state:

| name | type | meaning |
|---|---|---|
| `cancelRunId` | string, `""` | the run the cancel dialog asks about; `""` = closed |
| `cancelOpen` | readonly bool | `cancelRunId !== ""` |
| `cancelText` | string, `""` | the typed word (Panel binds the dialog's `typedText` to it) |
| `cancelError` | string, `""` | why the last confirm was refused |
| `flashText` | string, `""` | the footer flash |
| `flashTimer` | readonly alias | the 3000 ms one-shot that clears `flashText` |

New functions:

- `refusalOf(action, runId)` → string, as D2. Pure read; changes nothing.
- `flash(text)`: sets `flashText` and restarts `flashTimer`. `flash("")`
  clears it and stops the timer.
- `openCancel(runId)` → bool. When `refusalOf("cancel", runId)` is `""`: sets
  `cancelRunId`, empties `cancelText` and `cancelError`, returns true.
  Otherwise flashes the refusal, leaves any dialog as it is, returns false.
- `closeCancel()`: `cancelRunId`, `cancelText`, `cancelError` back to `""`.
- `confirmCancel()` → bool. Does nothing and returns false when the dialog is
  closed, or when `cancelText` trimmed and lower-cased is not `"cancel"` (the
  dialog gates this too; the store does not trust it). Else, when
  `refusalOf("cancel", cancelRunId)` is not `""`: sets `cancelError` to it,
  stays open, returns false (D6). Else calls `control("cancel", cancelRunId)`;
  true → `closeCancel()`, returns true; false → `cancelError` =
  `"The run could not be cancelled"`, stays open, returns false.
- `projectSwitched()` also calls `closeCancel()` and `flash("")`.

### `TypedConfirmDialog`

- New `property string dismissLabel: "Cancel"`; the `confirmCancel` button's
  text is `dismissLabel`. Nothing else changes.

### Panel (`ui/Panel.qml`)

- A third `TypedConfirmDialog`, after `memoryConfirm`: `id: runCancelModal`,
  `objectName: "runCancelModal"`, `backdropObjectName: "runCancelBackdrop"`,
  `cardObjectName: "runCancelCard"`, `fieldObjectName: "runCancelField"`,
  `anchors.fill: parent`, `theme: panelTheme`.
  - `shown: appStores.runs.cancelOpen`
  - `confirmWord: "cancel"`
  - `message`: `"Cancel run " + Runs.shortId({ id: appStores.runs.cancelRunId }) + "? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first."`
    (parent lines 93-96)
  - `detail`: the run's `Runs.runTitle` while it is in the snapshot, else `""`
  - `confirmLabel: "Cancel run"`, `dismissLabel: "Keep running"` (line 98)
  - `typedText: appStores.runs.cancelText`, `error: appStores.runs.cancelError`
  - `onTypedEdited: appStores.runs.cancelText = text`
  - `onConfirmRequested: appStores.runs.confirmCancel()`
  - `onCancelRequested: appStores.runs.closeCancel()` (button, backdrop, Escape)
- `focusItem`: `appStores.runs.cancelOpen ? runCancelModal.focusItem` added to
  the modal part of the chain, right after `milestones.dialogOpen` and before the
  memory-editor and `nav.dropdownOpen` entries, so the field takes
  the focus on open and the previous focus item (search field or key catcher)
  gets it back on close.
- `RunsScreen`, `RunDetailScreen`, `CardDetailScreen` instances:
  `onCancelRequested: function(runId) { appStores.runs.openCancel(runId) }`.
- `globalKeys.Keys.onPressed`: accepts the event when
  `sc.handleGlobalKey(event) || sc.handleRunKey(event)`.

### Shortcuts (`ui/Shortcuts.qml`)

- `handleGlobalKey`'s modal guard also returns false while
  `app.runs.cancelOpen`.
- `closeRequested()`: `app.runs.cancelOpen ? app.runs.closeCancel()` inserted in
  the modal part of the chain, before `nav.dropdownOpen`; nothing after it
  moves.
- New `handleRunKey(event)` → bool (true = handled; the caller accepts it).
  Returns false, touching nothing, unless **all** hold:
  - `event.modifiers === Qt.NoModifier` and `event.key` is `Qt.Key_P`,
    `Qt.Key_R` or `Qt.Key_C`;
  - a project is selected and `app.nav.viewMode` is `"runs"` or `"run"`;
  - no modal is open (the same list as `handleGlobalKey`'s guard, including
    `cancelOpen`) and `nav.dropdownOpen` is false;
  - on `"runs"`: `app.nav.searchQuery === ""` (D4);
  - there is a target run: on `"run"` `app.runs.runById(app.runs.selectedRunId)`,
    on `"runs"` `app.runs.filteredRuns[app.nav.cursorIndex]`; none → false
    (on the Runs list the letter then types into the empty search, as today).
  Then, with `action` = pause / resume / cancel for p / r / c:
  - `reason = app.runs.refusalOf(action, id)`; non-empty → `app.runs.flash(reason)`, true;
  - `cancel` → `app.runs.openCancel(id)`, true;
  - otherwise `app.runs.control(action, id)`, true.

### Screens

- `RunsScreen.runsFooter`: text is `app.runs.flashText` while it is non-empty,
  otherwise as today; visible as today **or** while `flashText` is non-empty.
- `RunDetailScreen`: a caption `objectName: "runDetailFlash"` at the end of
  `runDetailBody`, text `app.runs.flashText`, visible only while non-empty.

## Error paths and edge cases

| case | behaviour |
|---|---|
| `c` on a finished / unknown-state run | flash the controls reason (e.g. `The run has finished`); no dialog |
| `p` / `c` on a running run in Integrate | flash `Integrate is running; it cannot be paused or cancelled`; nothing pending, no runner |
| `r` on a running run | flash `The run is still running` |
| any key on a run with a request pending | flash `A request for this run is pending` |
| a key on an empty Runs list | not handled; the letter types into the search |
| wrong word typed | `Cancel run` disabled, Return does nothing, no runner |
| run changes under the open dialog | confirm refused, `cancelError` shown in the dialog, stays open (D6) |
| Ctrl+6 etc. while the dialog is open | ignored (modal guard) |
| Escape while the dialog is open | closes the dialog only; view unchanged |
| project switch while open | dialog closed, flash cleared |
| two keys in a row refused | second flash replaces the first and restarts the 3 s clock |

## Tests

All run under `bash tests/run.sh` (pytest + qmltestrunner with
`tests/stubs`). TDD: each appears failing before its code.

**Store tier — `tests/core/stores/tst_run_store.qml` (appended).** The store's
rules without any UI, so the refusal order and the dialog lifecycle are pinned
once, cheaply.
1. `refusalOf`: `""` for each allowed action; unknown run and no project →
   `This run is no longer in the snapshot`; pending → `A request for this run is pending`
   (wins over a disabled reason); Integrate → the Integrate reason for pause
   and cancel; finished → `The run has finished`; `"bogus"` → `Unknown control`.
2. `flash` sets `flashText`, the timer clears it (test sets
   `flashTimer.interval` small and waits), a second flash restarts it,
   `flash("")` clears and stops.
3. `openCancel` on a cancellable run opens with empty text and error; on an
   Integrate run returns false, stays closed, flashes the reason.
4. `confirmCancel` with `cancelText` `"cancle"` → false, no runner, still open;
   `" Cancel "` → true, `pending[id] === "cancel"`, `controlRunners.length === 1`,
   closed and emptied.
5. `confirmCancel` after the run turned `done` in a new snapshot → false,
   `cancelError === "The run has finished"`, still open, no runner.
6. `projectSwitched()` closes the dialog and clears the flash.

**Component tier — `tests/ui/tst_typed_confirm_dialog.qml` (appended).** Only
the new property; existing tests untouched (parent line 157).
7. `confirmCancel` text is `"Cancel"` by default and follows `dismissLabel`;
   clicking it still emits `cancelRequested`.

**Shortcuts tier — `tests/ui/tst_shortcuts.qml` (appended).** The key rules on
the real App + Navigator, without rendering, so each guard is one small test.
8. On `runs` with an empty search, cursor on a running run: `p` → true,
   pending pause; `c` → true, `cancelOpen`, `cancelRunId` = that run; `r` on it
   → true, flash `The run is still running`, nothing pending.
9. On `runs` with search text `"x"`: `p` → false, nothing changes.
10. Shift+P, Ctrl+C (with the dialog closed, Ctrl+C is not a chord either) and
    `Qt.Key_X` → false.
11. On `run` with a selected parked run: `r` → pending resume; on view
    `board` / `entry` → false.
12. With the cancel dialog open: `handleGlobalKey(Ctrl+6)` → false and the
    view stays; `handleRunKey(p)` → false; `closeRequested()` closes the dialog
    and leaves `viewMode` as it was; a second `closeRequested()` on `run` goes
    back as before.
13. With an empty Runs list: `p` → false.

**Screen tier — `tests/ui/screens/tst_runs_screen.qml`,
`tst_run_detail_screen.qml` (appended).** What a flash looks like on each
screen, with a plain app object.
14. `runsFooter` shows `flashText` while set, the watching text after; it is
    visible with a flash even while the schema banner shows.
15. `runDetailFlash` hidden with no flash, shows the text with one.

**Flow tier — `tests/ui/tst_runs_flow.qml` (appended after the file's last test).** The
whole Panel, because only here the dialog, focus and key routing meet (parent
lines 159-160).
16. Cancel with the wrong word, then the right one: hover row 0, click
    `runControlCancel` → `runCancelModal` shown, `p.focusItem` is
    `runCancelField`, `confirmCancel` reads `Keep running`, `confirmAccept`
    reads `Cancel run`, message names `…000000a1`. Type `cancle` → accept
    disabled, Return → no runner. Type `cancel` → accept enabled; click →
    `pending["run-0000000000a1"] === "cancel"`, one runner, dialog hidden,
    focus back on `searchField`, the row's Cancel reads `Cancel requested…`.
17. `c` through the real key path: focus in the empty search field,
    `keyClick(Qt.Key_C)` → dialog open and the search text still `""`;
    Escape → dialog closed, view still `runs`, nothing pending.
18. Integrate disables both: a running run whose lease has
    `accepting: false`. On the Runs list its Pause and Cancel buttons are
    disabled; `p` → flash equals the Integrate reason in `runsFooter`, no
    runner; `c` → no dialog, same flash. Open the run: the same on Run
    detail, shown in `runDetailFlash`.
19. A card's RUNS row Cancel opens the same dialog (view `entry`), and
    Keep running closes it with the card still open.

**Architecture tier — `tests/architecture` (unchanged, must stay green).** No
new component, no new glyph literal, no store import in `ui/screens` or
`ui/components`.

## Review focus (for the planner)

- A snapshot that changes the dialog's run while it is open (D6, test 5): the
  most likely real-world race, since cancel is usually wanted on a run that is
  moving.
- The Runs search field never receives a `p`/`r`/`c` that was handled (test
  17) and always receives one when the search has text or Shift is held (tests
  9-10).
- Escape with the dialog open must not also leave Run detail (test 12).
- The focus returns to the right item after the dialog closes on both views
  (tests 16, 17).
- A refused key on a pending run says the pending sentence, not the state's
  reason (test 1).
