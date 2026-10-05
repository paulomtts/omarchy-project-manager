# 4.3 Cancel confirmation and keyboard shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cancel on any run surface asks for a typed `cancel` and only then cancels; on the Runs list and Run detail the bare keys `p` / `r` / `c` pause, resume or cancel the run, and a refused key flashes why in a footer line for 3 s.

**Architecture:** `RunStore` (`app.runs`) owns the cancel dialog's state (`cancelRunId`, `cancelText`, `cancelError`), the one refusal rule (`refusalOf`) and the footer flash (`flashText` + `flashTimer`). `TypedConfirmDialog` gains an additive `dismissLabel`. `Shortcuts.handleRunKey` turns the three letters into store calls, behind the same modal guard as the Ctrl chords; `Panel` renders a third `TypedConfirmDialog`, wires the three screens' `cancelRequested`, moves the focus in and out of the dialog, and lets `globalKeys` try the run keys after the Ctrl chords. The two run screens only read `flashText`.

**Tech Stack:** QML (Qt 6 / Quickshell), JavaScript domain modules, QtTest via `qmltestrunner` with `tests/stubs`, run by `bash tests/run.sh [filter]` (pytest runs first; then every `tst_*.qml` whose path contains the filter).

**Spec:** `docs/superpowers/specs/4-3-cancel-confirmation-b4bc1521.md` (copied verbatim below, headings demoted one level).

---

## The spec (verbatim)

## 4.3 Cancel confirmation and keyboard shortcuts (card b4bc1521)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2,
"the parent" below): "Control actions" (lines 29-53, cancel row line 35),
"Architecture" bullet 4 (lines 70-74), "UI" (lines 79-104), "Testing" (lines
157-160). Parent story f03629a7 ("Control store and UI"). Blocked by 4.2
(1c268d85, spec `4-2-runcontrols-1c268d85.md`), which is done on this branch.

This card makes Cancel actually cancel (after a typed `cancel`), and adds the
`p` / `r` / `c` keys with a footer flash for a refused key. Toasts and desktop
alerts are card 4.4 (22153f5f).

### Starting point

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

### Scope

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

#### Out of scope

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

### Decisions

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

### Behaviour

#### `RunStore` (`core/stores/RunStore.qml`)

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

#### `TypedConfirmDialog`

- New `property string dismissLabel: "Cancel"`; the `confirmCancel` button's
  text is `dismissLabel`. Nothing else changes.

#### Panel (`ui/Panel.qml`)

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

#### Shortcuts (`ui/Shortcuts.qml`)

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

#### Screens

- `RunsScreen.runsFooter`: text is `app.runs.flashText` while it is non-empty,
  otherwise as today; visible as today **or** while `flashText` is non-empty.
- `RunDetailScreen`: a caption `objectName: "runDetailFlash"` at the end of
  `runDetailBody`, text `app.runs.flashText`, visible only while non-empty.

### Error paths and edge cases

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

### Tests

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

### Review focus (for the planner)

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

---

## Global Constraints

- No new component file. No change to `core/domain/runs.js`, `ui/components/RunControls.qml`, `ui/components/ListRow.qml`, `core/stores/App.qml` or anything under `core/backend/`.
- No store import in `ui/screens` or `ui/components`; no new glyph literal (`tests/architecture` must stay green).
- `TypedConfirmDialog`'s two existing instances keep the dismiss text `"Cancel"` (`dismissLabel` defaults to `"Cancel"`); its existing tests are not edited, only appended to.
- Exact strings: `This run is no longer in the snapshot`, `A request for this run is pending`, `Unknown control`, `The run could not be cancelled`, `Keep running`, `Cancel run`, confirm word `cancel`, message `"Cancel run " + Runs.shortId({ id: cancelRunId }) + "? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first."`
- The flash lasts 3000 ms; a new flash replaces the text and restarts the clock; a project switch clears it.
- Run keys: only with `event.modifiers === Qt.NoModifier`, only `Qt.Key_P` / `Qt.Key_R` / `Qt.Key_C`, only on view `runs` (and only while the search text is `""`) or view `run`.
- The ORDER of the guards in `ui/Shortcuts.qml` is load bearing: insert, never reorder.
- Resume stays one step (`control("resume", id)`), as in 4.2. Keys exist on views `runs` and `run` only.
- Every existing test keeps passing; new tests are appended at the end of their files. The two screen-test stubs get one new property (`flashText`) because the screens now read it.
- Commit messages follow the repo's style: `feat(runs): … (card b4bc1521)` / `test(runs): … (card b4bc1521)`.

## Review Focus

1. **Confirm fired twice** (Return held, or Return then a click): the second `confirmCancel()` finds the dialog closed and starts nothing — one runner, one pending entry. Pinned in Task 2, test 4.
2. **The dialog's run vanishes from the snapshot while it is open** (not just finishes): confirm is refused with `This run is no longer in the snapshot`, the dialog stays. Pinned in Task 2, test 5.
3. **The Runs cursor past the end of a list that shrank** (cursor on row 3, a snapshot leaves one run): `p` finds no target, is not handled, and the letter types into the search as before — nothing flashes, nothing starts. Pinned in Task 3, test 13.
4. **A run id such as `constructor` or `__proto__`** in `refusalOf` with nothing pending: the pending check uses own keys, so it reads the state's reason, never the pending sentence. Pinned in Task 2, test 1.
5. **Reopening the dialog after typing and Keep running**: the field is empty and `Cancel run` is disabled again; the old word never carries over. Pinned in Task 5, test 19.

---

## File map

| file | change | responsibility |
|---|---|---|
| `ui/components/TypedConfirmDialog.qml` | modify | `dismissLabel` for the safe button |
| `core/stores/RunStore.qml` | modify | `refusalOf`, the flash, the cancel dialog's state and lifecycle |
| `ui/Shortcuts.qml` | modify | `modalOpen()`, `handleRunKey(event)`, the cancel dialog in the modal guard and the Escape chain |
| `ui/screens/RunsScreen.qml` | modify | the flash in `runsFooter` |
| `ui/screens/RunDetailScreen.qml` | modify | the `runDetailFlash` line |
| `ui/Panel.qml` | modify | `runCancelModal`, focus chain, focus on open/close, `cancelRequested` wiring, `globalKeys` |
| `docs/architecture.md` | modify | `TypedConfirmDialog`, `RunStore`, `Shortcuts.qml`, run screens paragraph |
| `tests/ui/tst_typed_confirm_dialog.qml` | append | test 7 |
| `tests/core/stores/tst_run_store.qml` | append | tests 1-6 |
| `tests/ui/tst_shortcuts.qml` | append | tests 8-13 |
| `tests/ui/screens/tst_runs_screen.qml`, `tests/ui/screens/tst_run_detail_screen.qml` | stub property + append | tests 14, 15 |
| `tests/ui/tst_runs_flow.qml` | append | tests 16-19 |

How to read test output: `bash tests/run.sh <filter>` prints `== tests/...` per QML file, then any `FAIL!  : <Case>::<test>` lines with a `   Loc:` line, then `Totals: N passed, M failed, …`. Lines containing `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` are echoed and make the script exit 1.

---

### Task 1: `TypedConfirmDialog.dismissLabel`

**Files:**
- Modify: `ui/components/TypedConfirmDialog.qml:33-34` (new property) and `:114-121` (the `confirmCancel` button)
- Modify: `docs/architecture.md:112` (the `TypedConfirmDialog` entry)
- Test: `tests/ui/tst_typed_confirm_dialog.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes: nothing.
- Produces: `TypedConfirmDialog.dismissLabel: string` (default `"Cancel"`), the text of the button `objectName: "confirmCancel"`. Task 5 sets it to `"Keep running"`.

- [ ] **Step 1: Write the failing test**

Append inside the `TestCase` of `tests/ui/tst_typed_confirm_dialog.qml`, after `test_escape_still_cancels_with_a_cancel_word` (before the last `}` of the file):

```qml
  // 4.3 D5: the safe button's text is the owner's, "Cancel" unless it says
  // otherwise, and it still only cancels.
  function test_the_dismiss_button_reads_its_label_and_still_cancels() {
    var d = make()
    d.shown = true
    var dismiss = find(d, "confirmCancel")
    compare(dismiss.text, "Cancel")
    d.dismissLabel = "Keep running"
    compare(dismiss.text, "Keep running")
    mouseClick(dismiss, dismiss.width / 2, dismiss.height / 2)
    compare(cancelSpy.count, 1)
    compare(confirmSpy.count, 0)
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh tst_typed_confirm_dialog`
Expected: FAIL — `FAIL!  : TypedConfirmDialog::test_the_dismiss_button_reads_its_label_and_still_cancels()` (the button still reads `Cancel`, and/or a `non-existent property "dismissLabel"` error line).

- [ ] **Step 3: Write minimal implementation**

In `ui/components/TypedConfirmDialog.qml`, after `property string confirmWord: "delete"` (line 33) add:

```qml
  // The safe button's text. A run cancel says "Keep running", so the way out
  // never reads like the destructive "Cancel run" beside it.
  property string dismissLabel: "Cancel"
```

and in the `confirmCancel` button replace `text: "Cancel"` with:

```qml
        text: dialog.dismissLabel
```

In `docs/architecture.md` line 112 replace

```
`TypedConfirmDialog`, `ListRow` (hover / keyboard cursor / reveal; its
```

with

```
`TypedConfirmDialog` (the typed-word modal: `confirmWord`, and `dismissLabel`
for the safe button -- `Cancel` unless the owner says otherwise, `Keep running`
for a run cancel), `ListRow` (hover / keyboard cursor / reveal; its
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh tst_typed_confirm_dialog`
Expected: PASS — `Totals:` with `0 failed`, and no error lines.

- [ ] **Step 5: Commit**

```bash
git add ui/components/TypedConfirmDialog.qml tests/ui/tst_typed_confirm_dialog.qml docs/architecture.md
git commit -m "feat(runs): TypedConfirmDialog takes a dismissLabel, Cancel by default (card b4bc1521)"
```

---

### Task 2: `RunStore` — `refusalOf`, the flash and the cancel dialog

**Files:**
- Modify: `core/stores/RunStore.qml` — properties after line 69, alias after line 80, `projectSwitched()` (lines 217-237), new functions after `checkWaiting` (after line 632), new `Timer` after `pendingTimer` (after line 704)
- Modify: `docs/architecture.md:95` (the "Run controls (S2 4.1)" paragraph of `RunStore`)
- Test: `tests/core/stores/tst_run_store.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes: existing `RunStore.control(action, runId) → bool`, `runById(id) → run|null`, `hasKey(map, key) → bool`, `pending`, `project`, `Runs.controls(run)[action].reason`.
- Produces (used by Tasks 3, 4, 5):
  - `cancelRunId: string` (`""` = closed), `readonly cancelOpen: bool`, `cancelText: string`, `cancelError: string`
  - `flashText: string`, `readonly property alias flashTimer` (a `Timer`, 3000 ms, one-shot)
  - `refusalOf(action: string, runId: string) → string` (`""` = would start)
  - `flash(text: string)`
  - `openCancel(runId: string) → bool`, `closeCancel()`, `confirmCancel() → bool`

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/core/stores/tst_run_store.qml`, after `test_the_pending_timer_runs_only_while_active_with_something_pending` (before the file's last `}`). `ctlEntry`, `running`, `ctlStore`, `snapshot`, `argv`, `ctlCmd`, `rootB` already exist in this file.

```qml
  // ---- cancel confirmation and the footer flash (S2 4.3)

  property string integrateReason: "Integrate is running; it cannot be paused or cancelled"

  // A running run whose lease is not accepting requests: am is in Integrate.
  function integrate(id) { return ctlEntry(id, "started", true, "milestone", [], false) }

  // 1 (and Review Focus 4)
  function test_refusal_of_says_why_a_control_would_not_start() {
    var bare = make(); if (!bare) return
    compare(bare.refusalOf("pause", "r1"), "This run is no longer in the snapshot", "no project")
    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false), integrate("r3"),
                          ctlEntry("r4", "done", false), running("r5"), running("constructor")]); if (!store) return
    compare(store.refusalOf("pause", "r1"), "")
    compare(store.refusalOf("cancel", "r1"), "")
    compare(store.refusalOf("resume", "r2"), "")
    compare(store.refusalOf("cancel", "r2"), "")
    compare(store.refusalOf("pause", "nope"), "This run is no longer in the snapshot")
    compare(store.refusalOf("pause", ""), "This run is no longer in the snapshot")
    compare(store.refusalOf("pause", "r3"), tc.integrateReason)
    compare(store.refusalOf("cancel", "r3"), tc.integrateReason)
    compare(store.refusalOf("cancel", "r4"), "The run has finished")
    compare(store.refusalOf("resume", "r1"), "The run is still running")
    compare(store.refusalOf("bogus", "r1"), "Unknown control")
    compare(store.refusalOf("pause", "constructor"), "", "an id like constructor is not pending")
    compare(store.refusalOf("resume", "constructor"), "The run is still running")
    compare(store.control("pause", "r5"), true)
    compare(store.refusalOf("pause", "r5"), "A request for this run is pending")
    compare(store.refusalOf("resume", "r5"), "A request for this run is pending", "pending wins over the state's reason")
    compare(store.controlRunners.length, 1, "refusalOf starts nothing")
  }

  // 2
  function test_a_flash_clears_itself_and_a_new_one_restarts_the_clock() {
    var store = make(); if (!store) return
    compare(store.flashText, "")
    compare(store.flashTimer.interval, 3000)
    compare(store.flashTimer.repeat, false)
    compare(store.flashTimer.running, false)
    store.flashTimer.interval = 500
    store.flash("first")
    compare(store.flashText, "first")
    compare(store.flashTimer.running, true)
    wait(300)
    store.flash("second")
    compare(store.flashText, "second", "the new text replaces the old")
    wait(300)
    compare(store.flashText, "second", "the clock restarted with the second flash")
    tryCompare(store, "flashText", "", 2000)
    compare(store.flashTimer.running, false)
    store.flash("third")
    store.flash("")
    compare(store.flashText, "")
    compare(store.flashTimer.running, false, "flash(\"\") stops the clock")
  }

  // 3
  function test_open_cancel_opens_only_for_a_cancellable_run() {
    var store = ctlStore([running("r1"), integrate("r3")]); if (!store) return
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    store.cancelText = "left over"
    store.cancelError = "old"
    compare(store.openCancel("r1"), true)
    compare(store.cancelOpen, true)
    compare(store.cancelRunId, "r1")
    compare(store.cancelText, "", "the dialog opens empty")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    store.closeCancel()
    compare(store.cancelOpen, false)
    compare(store.openCancel("r3"), false)
    compare(store.cancelOpen, false, "an Integrate run gets no dialog")
    compare(store.flashText, tc.integrateReason)
    compare(store.controlRunners.length, 0)
  }

  // 4 (and Review Focus 1)
  function test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes() {
    var store = ctlStore([running("r1")]); if (!store) return
    compare(store.confirmCancel(), false, "nothing is open")
    store.openCancel("r1")
    store.cancelText = "cancle"
    compare(store.confirmCancel(), false)
    compare(store.controlRunners.length, 0)
    compare(store.cancelOpen, true)
    compare(store.cancelError, "", "a wrong word is not an error")
    store.cancelText = " Cancel "
    compare(store.confirmCancel(), true)
    compare(store.pending.r1, "cancel")
    compare(store.controlRunners.length, 1)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|r1|/home/u/my proj")
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.confirmCancel(), false, "a second confirm finds the dialog closed")
    compare(store.controlRunners.length, 1)
  }

  // 5 (D6, Review Focus 2)
  function test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.openCancel("r2")
    store.cancelText = "cancel"
    store.control("pause", "r2")
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "A request for this run is pending")
    compare(store.cancelOpen, true)
    compare(store.controlRunners.length, 1, "only the pause")
    store.closeCancel()

    store.openCancel("r1")
    store.cancelText = "cancel"
    snapshot(store, [ctlEntry("r1", "done", false)])
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "The run has finished")
    compare(store.cancelOpen, true, "the dialog stays for the user to read why")
    compare(store.cancelRunId, "r1")
    compare(store.pending.r1, undefined)
    snapshot(store, [])
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "This run is no longer in the snapshot")
    compare(store.cancelOpen, true)
    compare(store.controlRunners.length, 1, "no cancel was ever launched")
  }

  // 6
  function test_a_project_switch_closes_the_dialog_and_clears_the_flash() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.openCancel("r1")
    store.cancelText = "can"
    store.cancelError = "x"
    store.flash("The run has finished")
    store.project = rootB
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    compare(store.flashTimer.running, false)
  }
```

Note on test 5: the pause on `r2` stays in flight (no reply is given), so `controlRunners.length` stays 1 for the rest of the test; the snapshots settle nothing for it (a request in flight is never settled by a snapshot).

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL — the six new tests fail with `TypeError: Property 'refusalOf' of object … is not a function` (and similar for `flash`, `openCancel`, `confirmCancel`), or `flashTimer` undefined; every older test still passes.

- [ ] **Step 3: Write minimal implementation**

In `core/stores/RunStore.qml`:

(a) After `property string lastControlErrorRunId: "" // the run that sentence is about` (line 69) add:

```qml

  // The cancel confirmation (S2 4.3). Panel renders it; the store keeps the
  // run it asks about ("" = closed), the typed word and why the last confirm
  // was refused.
  property string cancelRunId: ""
  readonly property bool cancelOpen: store.cancelRunId !== ""
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""
```

(b) After `readonly property alias pendingTimer: pendingTimer` (line 80) add:

```qml
  readonly property alias flashTimer: flashTimer
```

(c) In `projectSwitched()`, after `store.dismissControlError()` (line 235) and before `if (store.project !== "") store.refresh()` add:

```qml
    store.closeCancel()
    store.flash("")
```

(d) After the closing `}` of `checkWaiting(nowMs)` (line 632) add:

```qml

  // ---- cancel confirmation and the footer flash (S2 4.3)

  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in the snapshot (or no project), then a request already
  // pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = store.project === "" || typeof runId !== "string" || runId === "" ? null : store.runById(runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (store.hasKey(store.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action].reason
  }

  // Shows text in the footers for 3 s; a new flash replaces it and restarts
  // the clock, flash("") clears it.
  function flash(text) {
    store.flashText = String(text || "")
    if (store.flashText === "") flashTimer.stop()
    else flashTimer.restart()
  }

  // Opens the cancel confirmation for a run that can be cancelled now;
  // otherwise flashes why not and leaves any dialog as it is.
  function openCancel(runId) {
    var reason = store.refusalOf("cancel", runId)
    if (reason !== "") {
      store.flash(reason)
      return false
    }
    store.cancelText = ""
    store.cancelError = ""
    store.cancelRunId = runId
    return true
  }

  function closeCancel() {
    store.cancelRunId = ""
    store.cancelText = ""
    store.cancelError = ""
  }

  // The dialog's confirm. The typed word is checked again here (the dialog
  // gates it too), then the run is checked again: one that changed under the
  // open dialog keeps it open with the reason. A started cancel closes it.
  function confirmCancel() {
    if (store.cancelRunId === "") return false
    if (String(store.cancelText).trim().toLowerCase() !== "cancel") return false
    var reason = store.refusalOf("cancel", store.cancelRunId)
    if (reason !== "") {
      store.cancelError = reason
      return false
    }
    if (!store.control("cancel", store.cancelRunId)) {
      store.cancelError = "The run could not be cancelled"
      return false
    }
    store.closeCancel()
    return true
  }
```

(e) After the `pendingTimer` `Timer { … }` block (ends line 704) add:

```qml

  // Clears the footer flash 3 s after the last flash().
  Timer {
    id: flashTimer
    objectName: "flashTimer"
    interval: 3000
    repeat: false
    onTriggered: store.flashText = ""
  }
```

(f) In `docs/architecture.md` line 95, replace the paragraph's last sentence

```
Closing the panel keeps `pending`; a project switch empties it and the control error.
```

with

```
Closing the panel keeps `pending`; a project switch empties it and the control error. The cancel confirmation is the store's too (S2 4.3): `refusalOf(action, runId)` is `""` when `control` would start and otherwise the sentence why not (`This run is no longer in the snapshot`, then `A request for this run is pending`, then the `Runs.controls` reason; `Unknown control` for another action); `openCancel(runId)` opens it (`cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`) or flashes the refusal, `closeCancel()` closes it, and `confirmCancel()` needs `cancelText` to be `cancel` (trimmed, case-blind), checks `refusalOf` again -- a run that changed under the dialog keeps it open with `cancelError` -- and only then calls `control("cancel", …)`. `flash(text)` sets `flashText`, which `flashTimer` clears 3 s later; a project switch closes the dialog and clears the flash.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: PASS — `Totals:` with `0 failed`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): RunStore says why a control would be refused, flashes it, and owns the cancel confirmation (card b4bc1521)"
```

---

### Task 3: `Shortcuts` — the run keys, the modal guard and the Escape chain

**Files:**
- Modify: `ui/Shortcuts.qml:4-9` (header comment), `:23-24` (`handleGlobalKey`'s first line), `:38-40` (`closeRequested`), new functions after `closeRequested`
- Modify: `docs/architecture.md:99` (the `Shortcuts.qml` description's end)
- Test: `tests/ui/tst_shortcuts.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes (Task 2): `app.runs.cancelOpen`, `app.runs.closeCancel()`, `app.runs.refusalOf(action, id)`, `app.runs.flash(text)`, `app.runs.openCancel(id)`; existing `app.runs.control(action, id)`, `app.runs.runById(id)`, `app.runs.filteredRuns`, `app.runs.selectedRunId`, `app.nav.viewMode`, `app.nav.searchQuery`, `app.nav.cursorIndex`, `app.nav.dropdownOpen`, `app.projects.selectedProject`.
- Produces: `Shortcuts.handleRunKey(event) → bool` (Task 5 calls it from `globalKeys`); `Shortcuts.modalOpen() → bool`.

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/ui/tst_shortcuts.qml`, after `test_an_unrelated_key_is_left_to_the_search_field` (before the file's last `}`). `make`, `plain`, `shift`, `ctrl`, `card` and `tc.calls` already exist.

```qml
  // ---- Run keys (S2 4.3)

  // A normalised run, as RunStore holds them. live === null means no lease.
  function normRun(id, status, live) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "m", status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] } }
  }

  // The Runs list of project A: row 0 running, row 1 parked; cursor on row 0.
  function inRunKeys() {
    var s = make(); if (!s) return null
    // The snapshot the project selection launched cannot run here.
    s.app.runs.snapshotRunner.cancel()
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true), normRun("run-0000000000b2", "stopped", null)]
    s.navigator.showSection("runs")
    s.app.nav.cursorIndex = 0
    return s
  }

  // 8
  function test_c_r_and_p_act_on_the_cursor_run_while_the_search_is_empty() {
    var s = inRunKeys(); if (!s) return
    compare(s.handleRunKey(plain(Qt.Key_R)), true, "a refused key is still handled")
    compare(s.app.runs.flashText, "The run is still running")
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.handleRunKey(plain(Qt.Key_C)), true)
    compare(s.app.runs.cancelOpen, true)
    compare(s.app.runs.cancelRunId, "run-0000000000a1")
    compare(Object.keys(s.app.runs.pending).length, 0, "c only asks")
    s.app.runs.closeCancel()
    compare(s.handleRunKey(plain(Qt.Key_P)), true)
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.controlRunners.length, 1)
    compare(s.handleRunKey(plain(Qt.Key_C)), true)
    compare(s.app.runs.cancelOpen, false, "a run with a request pending gets no dialog")
    compare(s.app.runs.flashText, "A request for this run is pending")
  }

  // 9
  function test_with_search_text_the_letters_are_left_to_the_search_field() {
    var s = inRunKeys(); if (!s) return
    s.app.nav.searchQuery = "run-"
    compare(s.app.runs.filteredRuns.length, 2, "the search still lists both runs")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(s.handleRunKey(plain(Qt.Key_C)), false)
    compare(s.handleRunKey(plain(Qt.Key_R)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
  }

  // 10
  function test_only_a_bare_p_r_or_c_is_a_run_key() {
    var s = inRunKeys(); if (!s) return
    compare(s.handleRunKey(shift(Qt.Key_P)), false, "Shift+P types: that is how a search for parked starts")
    compare(s.handleRunKey(shift(Qt.Key_C)), false)
    compare(s.handleRunKey(ctrl(Qt.Key_C)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_C)), false, "and Ctrl+C is no chord either")
    compare(s.handleRunKey(plain(Qt.Key_X)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
  }

  // 11
  function test_on_run_detail_the_keys_act_on_the_open_run_and_nowhere_else() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000b2")
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_R)), true)
    compare(s.app.runs.pending["run-0000000000b2"], "resume")
    s.navigator.goBack()
    s.navigator.showSection("board")
    compare(s.app.nav.viewMode, "board")
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "board")
    s.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    wait(20)
    s.navigator.openCard("m1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "entry")
    compare(s.app.runs.pending["run-0000000000a1"], undefined)
    compare(s.app.runs.flashText, "")
  }

  // 12
  function test_the_cancel_dialog_swallows_the_keys_and_escape_closes_only_it() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.runs.openCancel("run-0000000000a1"), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    s.closeRequested()
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.nav.viewMode, "run", "Escape closed the dialog only")
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs", "the next Escape goes back as before")
    compare(tc.calls.indexOf("close"), -1)
  }

  // 13 (and Review Focus 3)
  function test_no_target_run_leaves_the_letter_to_the_search() {
    var s = inRunKeys(); if (!s) return
    s.app.nav.cursorIndex = 1
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true)]
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "the cursor is past the end of the shrunk list")
    s.app.runs.runs = []
    s.app.nav.cursorIndex = 0
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "an empty list")
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.flashText, "")
  }

  function test_the_open_dropdown_swallows_the_run_keys() {
    var s = inRunKeys(); if (!s) return
    s.navigator.toggleDropdown()
    compare(s.app.nav.dropdownOpen, true)
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_shortcuts`
Expected: FAIL — the new tests fail with `TypeError: Property 'handleRunKey' of object … is not a function`; test 12 also fails at `compare(s.app.nav.viewMode, "run", "Escape closed the dialog only")` (or earlier at `handleRunKey`). Older tests pass.

- [ ] **Step 3: Write minimal implementation**

In `ui/Shortcuts.qml`:

(a) Replace the header's first line

```qml
// Every key the panel reacts to, in one place: the Ctrl chords, the Escape
// chain, the arrows the key catcher reports, and the search field's own keys.
```

with

```qml
// Every key the panel reacts to, in one place: the Ctrl chords, the run keys
// (p / r / c), the Escape chain, the arrows the key catcher reports, and the
// search field's own keys.
```

(b) Replace the first line of `handleGlobalKey`

```qml
    if (!(event.modifiers & Qt.ControlModifier) || keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen) return false
```

with

```qml
    if (!(event.modifiers & Qt.ControlModifier) || keys.modalOpen()) return false
```

and in its comment above, replace `Ignored while a delete confirmation is open so a stray Ctrl+P cannot` with `Ignored while a modal is open (modalOpen) so a stray Ctrl+P cannot`.

(c) In `closeRequested()` replace

```
keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : (keys.app.nav.dropdownOpen
```

with

```
keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : (keys.app.nav.dropdownOpen
```

(nothing else in that line changes).

(d) After the closing `}` of `closeRequested()` add:

```qml

  // A modal is open: the global shortcuts and the run keys do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen)
  }

  // p / r / c with no modifier at all pause, resume or cancel a run: on Run
  // detail the open run, on the Runs list the cursor row -- there only while
  // the search is empty, since the search field has the focus and every letter
  // types once it holds text (Shift+letter always types). A refused key
  // flashes why; c opens the cancel confirmation. Returns true when it handled
  // the key; with no target run the letter is left alone.
  function handleRunKey(event) {
    if (event.modifiers !== Qt.NoModifier) return false
    var action = event.key === Qt.Key_P ? "pause" : event.key === Qt.Key_R ? "resume" : event.key === Qt.Key_C ? "cancel" : ""
    if (action === "") return false
    var mode = keys.app.nav.viewMode
    if (!keys.app.projects.selectedProject || (mode !== "runs" && mode !== "run")) return false
    if (keys.modalOpen() || keys.app.nav.dropdownOpen) return false
    if (mode === "runs" && keys.app.nav.searchQuery !== "") return false
    var run = mode === "run" ? keys.app.runs.runById(keys.app.runs.selectedRunId) : keys.app.runs.filteredRuns[keys.app.nav.cursorIndex]
    var id = run && typeof run.id === "string" ? run.id : ""
    if (id === "") return false
    var reason = keys.app.runs.refusalOf(action, id)
    if (reason !== "") keys.app.runs.flash(reason)
    else if (action === "cancel") keys.app.runs.openCancel(id)
    else keys.app.runs.control(action, id)
    return true
  }
```

(e) In `docs/architecture.md` line 99 replace

```
Documents, Memories, Issues, Runs), `theme/Theme.qml` (colours and fonts from the shell).
```

with

```
Documents, Memories, Issues, Runs; `handleRunKey` makes a bare `p` / `r` / `c`
pause, resume or cancel the run on Run detail, and the cursor row on the Runs
list while its search is empty -- a refused key flashes `refusalOf`'s sentence,
`c` only opens the cancel confirmation; `modalOpen()` is the one guard both the
chords and the run keys obey, and Escape closes the cancel confirmation before
the dropdown), `theme/Theme.qml` (colours and fonts from the shell).
```

(Check the exact text of that line with `sed -n 97,99p docs/architecture.md` first; the replaced fragment is the end of the `Shortcuts.qml` parenthesis.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_shortcuts`
Expected: PASS — `Totals:` with `0 failed`, no error lines. Then run `bash tests/run.sh tst_archive_flow` and `bash tests/run.sh tst_panel_toolbar` to confirm the guard refactor broke no modal: `0 failed` each.

- [ ] **Step 5: Commit**

```bash
git add ui/Shortcuts.qml tests/ui/tst_shortcuts.qml docs/architecture.md
git commit -m "feat(runs): p, r and c act on the Runs cursor row or the open run, refused keys flash why, and the cancel confirmation is a modal (card b4bc1521)"
```

---

### Task 4: The flash on the Runs footer and on Run detail

**Files:**
- Modify: `ui/screens/RunsScreen.qml:116-126` (`runsFooter`)
- Modify: `ui/screens/RunDetailScreen.qml` (a new caption after the `runOutputPane` Column, as the last child of `runDetailBody`)
- Test: `tests/ui/screens/tst_runs_screen.qml` (stub property + append), `tests/ui/screens/tst_run_detail_screen.qml` (stub property + append)

**Interfaces:**
- Consumes (Task 2): `app.runs.flashText: string`.
- Produces: `runsFooter` shows the flash; new item `objectName: "runDetailFlash"` (Task 5's flow test reads both).

- [ ] **Step 1: Write the failing tests**

(a) In `tests/ui/screens/tst_runs_screen.qml`, inside the `runsC` stub `QtObject`, after `property string watchSchemaError: ""` add:

```qml
      property string flashText: ""
```

and append inside the `TestCase`, after `test_a_run_id_like_constructor_is_not_pending` (before the file's last `}`):

```qml
  // ---- the footer flash (S2 4.3)

  // 14
  function test_a_flash_takes_the_footer_and_then_gives_it_back() {
    var s = make(sample()); if (!s) return
    var footer = H.find(s.screen, "runsFooter")
    s.runs.flashText = "The run has finished"
    compare(footer.text, "The run has finished")
    compare(footer.visible, true)
    s.runs.flashText = ""
    compare(footer.text, "am · schema 1 · watching")
    s.runs.amStatus = "error"
    s.runs.lastError = "AmFailed: boom"
    s.runs.flashText = "The run is still running"
    compare(footer.text, "The run is still running", "the flash wins over the error line")
    s.runs.flashText = ""
    compare(footer.text, "AmFailed: boom")
    s.runs.amStatus = "schema"
    s.runs.watchSchemaError = "SchemaMismatch: schema 2"
    compare(footer.visible, false)
    s.runs.flashText = "A request for this run is pending"
    compare(footer.visible, true, "a flash shows even beside the schema banner")
    compare(footer.text, "A request for this run is pending")
    s.runs.flashText = ""
    compare(footer.visible, false)
  }
```

(b) In `tests/ui/screens/tst_run_detail_screen.qml`, inside the `runsC` stub `QtObject`, after `property string amStatus: "ok"` add:

```qml
      property string flashText: ""
```

and append inside the `TestCase`, after `test_a_done_run_shows_no_controls` (before the file's last `}`):

```qml
  // ---- the flash line (S2 4.3)

  // 15
  function test_the_flash_line_shows_only_while_there_is_a_flash() {
    var s = make(detail()); if (!s) return
    var line = H.find(s.screen, "runDetailFlash")
    verify(line, "the flash line")
    compare(line.visible, false)
    s.runs.flashText = "Integrate is running; it cannot be paused or cancelled"
    compare(line.visible, true)
    compare(line.text, "Integrate is running; it cannot be paused or cancelled")
    s.runs.flashText = ""
    compare(line.visible, false)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh screens/tst_run`
Expected: FAIL — `RunsScreen::test_a_flash_takes_the_footer_and_then_gives_it_back()` (the footer still reads the watching text) and `RunDetailScreen::test_the_flash_line_shows_only_while_there_is_a_flash()` (`the flash line` not found). Older tests pass.

- [ ] **Step 3: Write minimal implementation**

(a) In `ui/screens/RunsScreen.qml` replace the `runsFooter` block

```qml
  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.amStatus !== "schema"
    text: screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
      ? screen.app.runs.lastError
      : "am · schema 1 · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }
```

with

```qml
  // The watch line, or why the last run key was refused while that flash
  // lasts; a flash shows even where the footer is otherwise hidden.
  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: (!screen.amMissing && screen.app.runs.amStatus !== "schema") || screen.app.runs.flashText !== ""
    text: screen.app.runs.flashText !== ""
      ? screen.app.runs.flashText
      : screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
        ? screen.app.runs.lastError
        : "am · schema 1 · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }
```

(b) In `ui/screens/RunDetailScreen.qml`, inside `Column { objectName: "runDetailBody" … }`, after the closing `}` of the `Column { objectName: "runOutputPane" … }` block (the last child of `runDetailBody`), add:

```qml

    // Why the last run key was refused, while that flash lasts.
    UI.ThemedText {
      objectName: "runDetailFlash"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: text !== ""
      text: screen.app.runs.flashText
      wrapMode: Text.WordWrap
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh screens/tst_run`
Expected: PASS — both files `0 failed`, no error lines.

- [ ] **Step 5: Commit**

```bash
git add ui/screens/RunsScreen.qml ui/screens/RunDetailScreen.qml tests/ui/screens/tst_runs_screen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(runs): the Runs footer and Run detail show the flash of a refused run key (card b4bc1521)"
```

---

### Task 5: Panel — the run cancel dialog, its focus, `cancelRequested` and the run keys

**Files:**
- Modify: `ui/Panel.qml:94-97` (runs `Connections`), `:167-175` (`focusItem`), `:264-267` (`globalKeys`), `:549-587` (three screen instances), after `:625` (new dialog after `memoryConfirm`)
- Modify: `docs/architecture.md:150` (the run screens paragraph)
- Test: `tests/ui/tst_runs_flow.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes: Task 1 `dismissLabel`; Task 2 `cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `openCancel(id)`, `closeCancel()`, `confirmCancel()`, `flash(text)`; Task 3 `sc.handleRunKey(event)`; Task 4 `runsFooter` / `runDetailFlash`; existing `cancelRequested(string runId)` on `RunsScreen`, `RunDetailScreen`, `CardDetailScreen`.
- Produces: `runCancelModal` (backdrop `runCancelBackdrop`, card `runCancelCard`, field `runCancelField`).

- [ ] **Step 1: Write the failing tests**

Append inside the `TestCase` of `tests/ui/tst_runs_flow.qml`, after `test_pause_is_requested_then_settled_by_a_parked_snapshot_and_a_refusal_shows_inline` (before the file's last `}`). `make`, `run`, `key`, `controlOf` already exist in this file.

```qml
  // ---- cancel confirmation and the run keys (S2 4.3)

  function cancelModal(p) { return H.find(p, "runCancelModal") }
  // An item of the run cancel dialog (the delete dialog has the same names).
  function inModal(p, name) { return H.find(cancelModal(p), name) }

  // 16 (and Review Focus: the focus comes back)
  function test_cancel_asks_for_the_typed_word_then_cancels_and_gives_the_focus_back() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    mouseMove(row, row.width / 2, row.height / 2)
    wait(50)
    var cancel = controlOf(p, "Cancel")
    compare(cancel.enabled, true)
    mouseClick(cancel)
    wait(50)
    var modal = cancelModal(p)
    verify(modal, "the run cancel dialog")
    compare(modal.visible, true)
    compare(p.app.runs.cancelRunId, "run-0000000000a1")
    compare(p.app.nav.viewMode, "runs", "the click did not open the run")
    compare(p.focusItem.objectName, "runCancelField")
    var field = inModal(p, "runCancelField")
    verify(field.activeFocus, "the field has the keyboard")
    compare(String(field.placeholderText), "cancel")
    compare(inModal(p, "confirmCancel").text, "Keep running")
    var accept = inModal(p, "confirmAccept")
    compare(accept.text, "Cancel run")
    compare(modal.message, "Cancel run …000000a1? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first.")
    compare(modal.detail, "alpha")

    field.text = "cancle"
    compare(p.app.runs.cancelText, "cancle")
    compare(accept.enabled, false)
    keyClick(Qt.Key_Return)
    compare(p.app.runs.controlRunners.length, 0)
    compare(modal.visible, true)

    field.text = "cancel"
    compare(accept.enabled, true)
    wait(450)
    mouseClick(accept)
    compare(p.app.runs.pending["run-0000000000a1"], "cancel")
    compare(p.app.runs.controlRunners.length, 1)
    compare(modal.visible, false)
    wait(50)
    compare(p.focusItem.objectName, "searchField")
    verify(H.find(p, "searchField").activeFocus, "the focus is back in the search field")
    compare(controlOf(p, "Cancel").text, "Cancel requested…")
  }

  // 17 (Review Focus: a handled letter never types; Escape closes only the dialog)
  function test_c_in_the_empty_search_opens_the_dialog_without_typing_and_escape_closes_it() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    compare(p.app.nav.cursorIndex, 0)
    keyClick("c")
    compare(p.app.runs.cancelOpen, true)
    compare(p.app.runs.cancelRunId, "run-0000000000a1")
    compare(field.text, "", "the handled letter was not typed")
    compare(p.app.nav.searchQuery, "")
    wait(50)
    compare(p.focusItem.objectName, "runCancelField")
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.cancelOpen, false)
    compare(p.app.nav.viewMode, "runs")
    compare(Object.keys(p.app.runs.pending).length, 0)
    compare(p.opened, true, "the panel stays open")
    wait(50)
    verify(field.activeFocus, "the focus is back in the search field")
    keyClick("C", Qt.ShiftModifier)
    compare(field.text, "C", "Shift+C types")
    compare(p.app.runs.cancelOpen, false)
    keyClick("p")
    compare(field.text, "Cp", "with search text a bare letter types too")
    compare(Object.keys(p.app.runs.pending).length, 0)
  }

  // 18
  function test_integrate_disables_pause_and_cancel_and_a_key_says_why() {
    var p = make(); if (!p) return
    var r = run("run-0000000000a1", "started", true, "alpha")
    r.lease.accepting = false
    p.app.runs.runs = [r]
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    mouseMove(row, row.width / 2, row.height / 2)
    wait(50)
    compare(controlOf(p, "Pause").enabled, false)
    compare(controlOf(p, "Cancel").enabled, false)
    var reason = "Integrate is running; it cannot be paused or cancelled"
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), true)
    compare(H.find(p, "runsFooter").text, reason)
    compare(p.app.runs.controlRunners.length, 0)
    p.app.runs.flash("")
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), true)
    compare(p.app.runs.cancelOpen, false)
    compare(cancelModal(p).visible, false)
    compare(H.find(p, "runsFooter").text, reason)

    p.navigator.openRun("run-0000000000a1")
    wait(50)
    var detail = H.find(p, "runDetailControls")
    compare(H.find(detail, "runControlPause").enabled, false)
    compare(H.find(detail, "runControlCancel").enabled, false)
    p.app.runs.flash("")
    compare(H.find(p, "runDetailFlash").visible, false)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), true)
    compare(H.find(p, "runDetailFlash").visible, true)
    compare(H.find(p, "runDetailFlash").text, reason)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), true)
    compare(p.app.runs.cancelOpen, false)
    compare(p.app.runs.controlRunners.length, 0)
    compare(Object.keys(p.app.runs.pending).length, 0)
  }

  // 19 (and Review Focus 5)
  function test_a_cards_runs_row_cancel_opens_the_same_dialog_and_keep_running_closes_it() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData([{ id: "alpha", title: "Alpha", status: "in_progress", description: "d", blocked_by: [], children: [] }])
    p.app.runs.runs = [run("run-0000000000a1", "started", true, "alpha")]
    wait(50)
    p.navigator.openCard("alpha")
    wait(50)
    compare(p.app.nav.viewMode, "entry")
    var cancel = H.find(H.find(p, "cardRunControls0"), "runControlCancel")
    verify(cancel, "the card's RUNS row carries the run's Cancel")
    compare(cancel.enabled, true)
    mouseClick(cancel)
    wait(50)
    compare(cancelModal(p).visible, true)
    compare(p.app.runs.cancelRunId, "run-0000000000a1")
    compare(p.focusItem.objectName, "runCancelField")
    inModal(p, "runCancelField").text = "cancel"
    compare(inModal(p, "confirmAccept").enabled, true)
    wait(450)
    mouseClick(inModal(p, "confirmCancel"))
    compare(p.app.runs.cancelOpen, false)
    compare(cancelModal(p).visible, false)
    compare(p.app.nav.viewMode, "entry", "the card is still open")
    compare(p.app.board.selectedCardId, "alpha")
    compare(p.app.runs.controlRunners.length, 0)
    wait(50)
    compare(p.focusItem.objectName, "keyCatcher")

    wait(450)
    mouseClick(cancel)
    wait(50)
    compare(cancelModal(p).visible, true)
    compare(inModal(p, "runCancelField").text, "", "the old word does not carry over")
    compare(inModal(p, "confirmAccept").enabled, false)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run.sh tst_runs_flow`
Expected: FAIL — tests 16 and 19 fail at `verify(modal, "the run cancel dialog")` / `compare(cancelModal(p).visible, true)` (no `runCancelModal`, nothing handles `cancelRequested`); test 17 fails at `compare(p.app.runs.cancelOpen, true)` (the `c` typed into the search); test 18 fails at `cancelModal(p).visible` (null) or later. Older tests pass.

- [ ] **Step 3: Write minimal implementation**

In `ui/Panel.qml`:

(a) Replace the runs `Connections` (lines 92-97)

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
  }
```

with

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation takes the focus when it
  // opens and gives it back when it closes.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
  }
```

(b) In `focusItem`, after the line

```qml
    : appStores.milestones.dialogOpen ? newMilestoneDialog.focusItem
```

add

```qml
    : appStores.runs.cancelOpen ? runCancelModal.focusItem
```

(c) Replace the `globalKeys` item

```qml
    Item {
      id: globalKeys
      Keys.onPressed: function(event) { if (sc.handleGlobalKey(event)) event.accepted = true }
    }
```

with

```qml
    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail). An accepted key is not typed into the search field.
    Item {
      id: globalKeys
      Keys.onPressed: function(event) { if (sc.handleGlobalKey(event) || sc.handleRunKey(event)) event.accepted = true }
    }
```

(d) In each of the three instances `CardDetailScreen { … }`, `RunsScreen { … }` and `RunDetailScreen { … }`, after the line `onRevealRequested: function(item) { root.scrollItemIntoView(item) }` add:

```qml
            onCancelRequested: function(runId) { appStores.runs.openCancel(runId) }
```

(e) After the `memoryConfirm` `TypedConfirmDialog { … }` block (ends line 625) add:

```qml

      // Run cancel confirmation (S2 4.3): any run surface's Cancel, or c,
      // opens it through the run store; only its confirm cancels.
      TypedConfirmDialog {
        id: runCancelModal
        objectName: "runCancelModal"
        anchors.fill: parent
        backdropObjectName: "runCancelBackdrop"
        cardObjectName: "runCancelCard"
        fieldObjectName: "runCancelField"
        shown: appStores.runs.cancelOpen
        confirmWord: "cancel"
        message: "Cancel run " + Runs.shortId({ id: appStores.runs.cancelRunId }) + "? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first."
        detail: appStores.runs.runById(appStores.runs.cancelRunId) ? Runs.runTitle(appStores.runs.runById(appStores.runs.cancelRunId)) : ""
        confirmLabel: "Cancel run"
        dismissLabel: "Keep running"
        error: appStores.runs.cancelError
        typedText: appStores.runs.cancelText
        theme: panelTheme
        onTypedEdited: function(text) { appStores.runs.cancelText = text }
        onConfirmRequested: appStores.runs.confirmCancel()
        onCancelRequested: appStores.runs.closeCancel()
      }
```

(f) In `docs/architecture.md` line 150 replace

```
Pause and Resume call `app.runs.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` -- confirming a cancel is the owner's job, and no screen calls `control("cancel", …)`.
```

with

```
Pause and Resume call `app.runs.control(action, id)`; Cancel only emits the screen's `cancelRequested(runId)` -- confirming a cancel is the owner's job, and no screen calls `control("cancel", …)`. Panel answers every `cancelRequested` with `app.runs.openCancel(runId)`: a third `TypedConfirmDialog`, `runCancelModal`, asks for the word `cancel`, says that Cancel is final (no resume, only a relaunch; cards keep their status; a phase in flight finishes first) and reads `Keep running` / `Cancel run`; it takes the focus while open and gives it back on close, Escape closes only it, and only its confirm (`confirmCancel()`) calls `control("cancel", …)` -- a run that changed under it keeps it open with the reason. On the Runs list (search empty) and Run detail a bare `p` / `r` / `c` does the same as the buttons; a refused key flashes its sentence for 3 s in the Runs footer (shown even beside the schema banner) or in Run detail's `runDetailFlash` line, the last line of the run's body.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh tst_runs_flow`
Expected: PASS — `Totals:` with `0 failed`, no error lines.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest passes; every QML file reports `0 failed`; no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` lines; exit status 0 (`echo $?` → `0`). In particular `tests/architecture`, `tst_panel_toolbar`, `tst_archive_flow`, `tst_board_flow`, `tst_card_detail_screen` and `tst_typed_confirm_dialog` stay green.

- [ ] **Step 6: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml docs/architecture.md
git commit -m "feat(runs): Cancel on any run surface asks for a typed cancel in its own dialog, and p, r and c reach the run keys (card b4bc1521)"
```

---

## Self-review against the spec

- **D1** (store owns the dialog): Task 2 (`cancelRunId` / `cancelOpen` / `cancelText` / `cancelError`, `openCancel` / `closeCancel` / `confirmCancel`); Panel only renders (Task 5e).
- **D2** (`refusalOf`, order and wordings): Task 2 implementation + test 1; used by keys (Task 3) and dialog (Task 2 `openCancel` / `confirmCancel`).
- **D3** (flash + `flashTimer` alias, 3000 ms, restart, project switch): Task 2 + tests 2, 6.
- **D4** (letters only with empty search; Shift always types; view `run` always): Task 3 tests 9, 10; real key path Task 5 test 17.
- **D5** (`dismissLabel`, default `Cancel`, appended test): Task 1 test 7; existing instances untouched.
- **D6** (refused confirm keeps the dialog open): Task 2 test 5.
- **Panel**: dialog props (5e), `focusItem` placement after `milestones.dialogOpen` (5b), focus on open/close (5a — needed because nothing else calls `focusForView()` when `cancelOpen` changes; the test stub `KeyboardPanel` does not apply `focusTarget`), three `onCancelRequested` (5d), `globalKeys` (5c).
- **Shortcuts**: modal guard and Escape chain (Task 3 b, c; test 12), `handleRunKey` with every listed condition (Task 3 d; tests 8-13 + dropdown test).
- **Screens**: Task 4 (tests 14, 15). **Docs**: Tasks 1, 2, 3, 5.
- **Edge-case table**: finished/unknown flash (test 1, 8), Integrate (tests 1, 3, 18), `r` on running (test 8), pending (tests 1, 8), empty list (test 13), wrong word (tests 4, 16), run changes (test 5), Ctrl+6 under dialog (test 12), Escape (tests 12, 17), project switch (test 6), two flashes (test 2).
- Out of scope respected: no `runs.js`, `RunControls.qml`, `ListRow.qml`, `App.qml` or backend change; no keys on other views (test 11).
<!-- task-pipeline: validated -->
