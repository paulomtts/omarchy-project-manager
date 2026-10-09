<!-- The spec this plan implements, verbatim. The plan follows the rule below. -->

# 3.2 ResumeVerifyDialog in Panel (card ad383829)

Narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md`
(the parent): "Resume asks for the verify commands" (lines 165-196), the "UI"
bullet of "Architecture" (lines 279-282), the first two rows of "Errors and edge
cases" (lines 291-292) and "Testing" (lines 321 and 323-324). Parent story
215a0691. Blocked by 09dc2110 (3.1 `VerifyCommandsField`, done).

## Inherited constraints

- The dialog: "Resume run …<short id>" heading, the two sentences, the verify
  editor, the opt-out, the "Saved for this project…" line, `Cancel` and
  `⟳ Resume` (parent lines 175-185).
- "Resume is enabled when the form passes the verify rule of
  `Runs.validateDispatch` (at least one non-blank command, or the opt-out
  ticked …)" (parent lines 187-188).
- "a run that changed under the dialog keeps it open with `resumeError`"
  (parent lines 189-190; table row line 292).
- "`r` and the Resume buttons go through the same `control("resume", …)`, so
  they open the dialog too. The dialog takes the focus while open and gives it
  back on close; Escape closes only it." (parent lines 196-198.)
- "the new `ui/components/ResumeVerifyDialog.qml` (on `ModalCard`), which
  `Panel` mounts like the cancel confirmation" (parent lines 280-282).
- Components render and emit only; they never import `core/stores`
  (`docs/architecture.md`; `tests/architecture/test_layers.py`). Only `Panel`,
  `Shortcuts` and `Navigator` touch `app.*`.
- Reuse before writing a second copy (`docs/architecture.md`, "Shared
  components"; `GUARDS` in `tests/architecture/test_layers.py`): the dialog is
  built from `UI.ModalCard`, `UI.ThemedText`, `UI.VerifyCommandsField` and
  `UI.ActionButton`; no `Qt.rgba(0, 0, 0, 0.55)`, no `radius: height/2`, no
  `font.family:`, no local copy of the verify rows. `⟳` (U+27F3) is not a
  private-use code point, so `tests/architecture/test_icon_glyphs.py` accepts
  it; no other glyph is introduced.
- No local QML type may share a name with a shell/Controls type
  (`tests/architecture`).
- Docstrings and comments state the contract only, no narrative (card).
- UI strings use `…`, never `...`.
- Verification: `bash tests/run.sh` green; it also fails on `TypeError`,
  `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item`
  or `is not a function` in QML test output. TDD: tests first (card).

## Starting point (already done by sibling cards)

- `core/stores/RunStore.qml` lines 1381-1462, `// ---- resume dialog`:
  `resumeRunId` (`""` = closed), `resumeVerify` (var list, blanks allowed),
  `resumeAllowNoVerification`, `resumeError`, `resumeOpenFor(runId)`,
  `resumeClose()`, `resumeConfirm()` (refuses with `resumeError` and stays open
  on a failed verify rule or a `refusalOf("resume", id)`; else launches
  run-control with `--verify` pairs in order, blanks dropped, or
  `--allow-no-verification`, saves on `resumeSaveRunner`, closes).
- `resumeWithSettings` (lines 1251-1275) already calls `resumeOpenFor` when a
  non-`task` run's project has no stored set and no opt-out, so `r`
  (`ui/Shortcuts.qml` `handleRunKey`, lines 62-78) and the Resume buttons
  already open the store's dialog state. Only the UI is missing.
- `ui/components/VerifyCommandsField.qml` (3.1): props `theme`, `commands`,
  `allowNoVerification`, `editable`, `objectNamePrefix`; signals
  `commandsEdited(list)`, `allowNoVerificationEdited(on)`, `keyPressed(event)`;
  inner names `<P>VerifyLabel`, `<P>Verify<i>`, `<P>VerifyRemove<i>`,
  `<P>VerifyAdd`, `<P>NoVerify`. Its chip reads `run without any verification`.
- `ui/Panel.qml` mounts `runCancelModal` (lines 822-843), lists it in the
  `focusItem` chain (line 184) and refocuses on `onCancelOpenChanged`
  (line 101). `ui/Shortcuts.qml` closes it in `closeRequested()` (line 45) and
  counts it in `modalOpen()` (lines 49-53).

## Scope

- Create `ui/components/ResumeVerifyDialog.qml`.
- Create `tests/ui/components/tst_resume_verify_dialog.qml`.
- Modify `ui/Panel.qml`: mount the dialog, focus chain, refocus on open/close.
- Modify `ui/Shortcuts.qml`: Escape chain and `modalOpen()`.
- Modify `tests/ui/tst_runs_flow.qml`: new cases (below).
- Modify `docs/architecture.md`: a `ResumeVerifyDialog` entry in the shared
  components list and one sentence where the run screens paragraph describes
  `runCancelModal`, saying Panel mounts `resumeVerifyDialog` the same way.

### Out of scope

- Any change to `RunStore` (state, `resumeOpenFor` / `resumeClose` /
  `resumeConfirm`, the save, the flash): done by sibling cards. If a test here
  shows a store defect, it is reported, not fixed here.
- Any change to `VerifyCommandsField`, including a configurable opt-out text.
  The mock-up's `Resume without any verification` (parent line 180) is not
  adopted: the dialog shows the field's own `run without any verification`
  chip, as 3.1's spec deferred (its "Out of scope"). The chip is the opt-out;
  there is no checkbox.
- `StopReasonBlock`, Why-it-stopped, Relaunch, `controlError` sentences
  (parent lines 124-164, 200-232): other cards of the story.
- Showing a stored set before a one-click resume (parent "Open", line 336).
- `DispatchDialog`, `tst_dispatch_dialog.qml`, `tst_verify_commands_field.qml`:
  unchanged.

## Behaviour

### The component's interface

`ResumeVerifyDialog` is an `Item` (owner fills its parent), `z: 100`,
`visible: shown`, default `objectName: "resumeVerifyDialog"`, wrapping one
`UI.ModalCard` (`anchors.fill: parent`, `shown: true`,
`backdropObjectName: "resumeDialogBackdrop"`,
`cardObjectName: "resumeDialogCard"`). Presentation only: it imports no store
and no `core/` module.

Properties (owner → dialog):

| property | type | default | meaning |
|---|---|---|---|
| `shown` | bool | `false` | the dialog is visible |
| `runLabel` | string | `""` | the run as the heading names it; Panel passes `Runs.shortId({ id: resumeRunId })` (e.g. `…4a51d663`) |
| `commands` | var | `[]` | the typed commands, passed to the field as is |
| `allowNoVerification` | bool | `false` | the opt-out, passed to the field |
| `error` | string | `""` | why the last confirm was refused |
| `theme` | var | `T.Theme {}` | colours and fonts |

Read-only:

- `focusItem` (Item): the first verify row (`resumeVerify0`).
- `canResume` (bool): true exactly when `allowNoVerification` is true or
  `commands` is a list (or list-like) holding at least one element that is a
  string with non-whitespace content. Anything else for `commands` (missing,
  `null`, a string, a number) holds no command. This mirrors the verify rule
  of `Runs.validateDispatch`; the dialog computes it from its own props.

Signals (dialog → owner):

- `commandsEdited(var commands)`: forwarded unchanged from the field.
- `allowNoVerificationEdited(bool on)`: forwarded unchanged from the field.
- `confirmRequested()`: a click on Resume while it is enabled.
- `cancelRequested()`: a click on Cancel, a click on the backdrop, or Escape
  in a verify row.

The dialog never changes `commands`, `allowNoVerification` or `error` itself.

### What it shows, top to bottom

1. Heading, `resumeDialogTitle`: `Resume run ` + `runLabel`.
2. Body, `resumeDialogBody`, word-wrapped: `am does not record the verify
   commands. They run for every subtask without a checkpoint, merged bases and
   Integrate.`
3. `UI.VerifyCommandsField`, `objectNamePrefix: "resume"`, full card width,
   `editable: true`, `theme`, `commands`, `allowNoVerification` from the
   dialog. Its `Verify` caption, rows (`resumeVerify<i>`), `✕`, `+`
   (`resumeVerifyAdd`) and opt-out chip (`resumeNoVerify`) behave as 3.1
   specifies.
4. Saved line, `resumeDialogSaved`, word-wrapped: `Saved for this project and
   reused by later resumes and dispatches.`
5. Error, `resumeDialogError`, colour `theme.urgent`, word-wrapped, visible
   only when `error` is not `""`, text `error` verbatim.
6. A row: `Cancel` (`resumeDialogCancel`, `UI.ActionButton`, always enabled),
   then `Resume` (`resumeDialogAccept`, `UI.ActionButton`, `iconText: "⟳"`,
   text `Resume`, `enabled: canResume`).

### Keys

- Escape in any verify row emits `cancelRequested()` and accepts the event.
- Any other key in a row is left to the row (typing, Return does nothing to
  the dialog: only a click on Resume confirms, as in the dispatch dialog).

### Panel

- Mounted beside `runCancelModal`, in the same parent, as
  `ResumeVerifyDialog { id: resumeDialog; objectName: "resumeVerifyDialog";
  anchors.fill: parent; … }` with:
  - `shown: appStores.runs.resumeRunId !== ""`
  - `runLabel: Runs.shortId({ id: appStores.runs.resumeRunId })`
  - `commands: appStores.runs.resumeVerify`,
    `allowNoVerification: appStores.runs.resumeAllowNoVerification`,
    `error: appStores.runs.resumeError`, `theme: panelTheme`
  - `onCommandsEdited` → `appStores.runs.resumeVerify = commands`
  - `onAllowNoVerificationEdited` → `appStores.runs.resumeAllowNoVerification = on`
  - `onConfirmRequested` → `appStores.runs.resumeConfirm()`
  - `onCancelRequested` → `appStores.runs.resumeClose()`
- Focus: the `focusItem` chain gains
  `: appStores.runs.resumeRunId !== "" ? resumeDialog.focusItem` directly after
  the `cancelOpen` line; the `appStores.runs` `Connections` gains
  `onResumeRunIdChanged() { root.focusForView() }`. Opening puts the keyboard
  in the first verify row; closing (Cancel, Escape, backdrop, a confirmed
  resume) returns it to what the view would focus without the dialog (the
  search field on the Runs list, the key catcher on Run detail).
- A refused confirm keeps the dialog open, shows `resumeError`, and keeps the
  typed rows (the store does not clear `resumeVerify` on a refusal).

### Shortcuts

- `closeRequested()`: `keys.app.runs.resumeRunId !== "" ?
  keys.app.runs.resumeClose()` is inserted directly after the `cancelOpen`
  branch and before the toasts branch. Escape that reaches the panel with the
  dialog open closes only the dialog: no Back, no panel close, no toast
  dismissed.
- `modalOpen()` also returns true while `keys.app.runs.resumeRunId !== ""`, so
  `p` / `r` / `c`, `d` and the Ctrl chords do nothing under the dialog.
- No other guard is reordered (the file's own rule, lines 7-9).

## Errors and edge cases

| case | behaviour |
|---|---|
| all rows blank, opt-out off | Resume disabled; the store would refuse anyway |
| rows only whitespace (`"   "`) | Resume disabled |
| opt-out on, rows blank | Resume enabled; confirm launches with `--allow-no-verification` |
| run changed under the dialog (store refuses) | dialog stays open with `resumeError` in urgent, rows kept |
| `commands` `null` / a string | one empty row (the field's rule), Resume disabled unless opt-out |
| `r` / `p` / `c` / `d` / Ctrl+6 while open | nothing happens; a letter typed in a row is typed |
| Escape in a row | closes only the dialog; panel open, view unchanged, nothing pending |
| backdrop click | closes the dialog |
| a second `resumeOpenFor` replaces the run | heading shows the new run, rows reset to one empty row, focus in row 0 |
| a `task` run's `r` | no dialog (store rule, unchanged) |
| `theme` set to `null`, dialog destroyed | no error output |

## Tests

### New: `tests/ui/components/tst_resume_verify_dialog.qml`

Tier: QML component test (qmltestrunner via `tests/run.sh`). Why: the
contract is the dialog's rendered items and signals in isolation; no store
or process is involved. Modelled on `tst_dispatch_dialog.qml` /
`tst_verify_commands_field.qml`: `TestCase { when: windowShown; visible: true }`,
`Component` + `createTemporaryObject`, `SignalSpy` on each signal, `H.find`
from `../../helpers/find.js`, `wait(30)` before clicking freshly laid-out
items.

1. **renders the wording**: `shown: true`, `runLabel: "…4a51d663"` → visible;
   `resumeDialogTitle` `Resume run …4a51d663`; `resumeDialogBody` and
   `resumeDialogSaved` exactly the sentences above; `resumeVerifyLabel`,
   `resumeVerify0`, `resumeVerifyAdd`, `resumeNoVerify` found;
   `resumeDialogCancel` text `Cancel`; `resumeDialogAccept` text `Resume`,
   `iconText` `⟳`; `resumeDialogError` not visible.
2. **hidden while not shown**: `shown: false` → `visible` false.
3. **Resume follows the verify rule** (data-driven): `[]` false, `[""]` false,
   `["  "]` false, `null` false, `"x"` (a string) false, `["", "a"]` true,
   `[]` with `allowNoVerification: true` true; `canResume` and
   `resumeDialogAccept.enabled` agree each time.
4. **edits are forwarded**: set `resumeVerify0.text = "bash tests/run.sh"` →
   one `commandsEdited(["bash tests/run.sh"])`; click `resumeNoVerify` → one
   `allowNoVerificationEdited(true)`; neither changes the dialog's own
   `commands` / `allowNoVerification`.
5. **Resume confirms only when enabled**: with `commands: []` a click on
   Resume emits nothing; with `["a"]` it emits one `confirmRequested`.
6. **Cancel, backdrop and Escape cancel**: a click on `resumeDialogCancel` →
   one `cancelRequested`; a click on `resumeDialogBackdrop` (outside the card)
   → another; focus `resumeVerify0`, `keyClick(Qt.Key_Escape)` → another; no
   `confirmRequested` in any.
7. **Return does not confirm**: `["a"]`, focus row 0, `keyClick(Qt.Key_Return)`
   → no `confirmRequested`.
8. **error shows in urgent**: `error: "Another am process…"` →
   `resumeDialogError` visible, text verbatim, colour `theme.urgent`; set
   back to `""` → hidden.
9. **focusItem is the first row**: `focusItem.objectName === "resumeVerify0"`.
10. **null theme and destroy are quiet**: set `theme` and `commands` to `null`,
    destroy → no error output (checked by `tests/run.sh`'s grep).

### Modified: `tests/ui/tst_runs_flow.qml`

Tier: QML Panel-level flow test. Why: focus hand-over, the Escape chain,
`modalOpen()` and the store wiring exist only when `Panel`, `Shortcuts` and
the real `RunStore` are put together; only this tier observes them. Built with
the file's `make()`, `reply()`, `key()` helpers. The sample run
`run-0000000000b2` is escalated and has no `workflow` field (so it is not a
`task` run and takes the milestone resume path); a case may build its own run
with `workflow: "milestone"` instead.

11. **`r` with no stored set opens the dialog; Resume launches with the typed
    commands**: Runs list, cursor on the escalated milestone run, search
    empty, `keyClick("r")` → one control runner reading `get-run-settings`;
    reply with a bare settings object `{verify: [], allowNoVerification:
    false}` → `resumeVerifyDialog` visible, `resumeRunId` the run's id, nothing
    pending, heading `Resume run …000000b2`; `p.focusItem.objectName ===
    "resumeVerify0"` and it has `activeFocus`; the search field text is still
    `""`. Type `bash tests/run.sh` into row 0, click `+`, type `uv run pytest`
    into row 1, `wait(450)`, click Resume → the dialog is hidden, `pending` for
    the run is `resume`, a control runner's argv ends with
    `resume|<id>|/home/u/a|--verify|bash tests/run.sh|--verify|uv run pytest`
    (run-control.py), `resumeSaveRunner` was started with `set-run-settings`,
    and after `wait(50)` the focus is back in the search field.
12. **Escape closes only the dialog and the run keys are dead under it**: open
    the dialog as in 11 (or via `p.app.runs.resumeOpenFor(id)` after the
    cursor is set); `keyClick("p")` and `keyClick("c")` in row 0 type into the
    row and start nothing (`pending` empty, `cancelOpen` false);
    `p.shortcuts.modalOpen()` is true; `keyClick(Qt.Key_Escape)` →
    `resumeRunId` `""`, dialog hidden, view mode still `runs`, panel still
    `opened`, nothing pending, focus back in the search field.
13. **a refused confirm keeps the dialog**: open the dialog, type a command,
    make the run unresumable under it (replace `p.app.runs.runs` with the run
    `started` and live), click Resume → dialog still visible,
    `resumeDialogError` visible with the store's `refusalOf` sentence, row 0
    still holds the typed command, no run-control launched.

### Existing: `tests/architecture`, `tests/ui/tst_shortcuts.qml`

Tier: pytest architecture guards / QML. Why: the new component must import
no store, duplicate no guarded pattern and add no unknown glyph; the existing
Shortcuts tests build a real `App` and must stay green with the extra
`modalOpen()` term. Not edited.

## Plan hand-off notes

- Order: the component test file first (fails: component missing), then the
  component; then the flow cases (fail: no dialog in Panel), then Panel and
  Shortcuts; then `docs/architecture.md`. Run `bash tests/run.sh
  resume_verify_dialog`, `bash tests/run.sh runs_flow`, `bash tests/run.sh
  shortcuts`, then the full `bash tests/run.sh`.
- Escape inside a row reaches the dialog through the field's `keyPressed`;
  copy `DispatchDialog.fieldKey` (lines 147-151): Escape →
  `cancelRequested()`, `event.accepted = true`; other keys untouched.
- The flow test's argv check: read how existing tests join a runner's argv
  (`tests/core/stores/tst_run_store.qml`, `argv(runner.current)`, and the
  `settingsReply` shape at lines 3125-3128) and reuse that pattern.
- The dialog's header comment states its contract: what it shows, the props
  it reads, the signals it emits, its objectNames, that it never changes its
  inputs.

---

# 3.2 ResumeVerifyDialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the store's existing Resume dialog state a face: a presentation-only `ResumeVerifyDialog` mounted by `Panel`, with the focus hand-over and the Escape / modal guards in `Shortcuts`.

**Architecture:** `ui/components/ResumeVerifyDialog.qml` is an `Item` wrapping one `UI.ModalCard` holding a heading, two sentences, a `UI.VerifyCommandsField` (prefix `resume`), an error line and Cancel / `⟳ Resume`. It reads props and emits signals only. `Panel` binds it to `appStores.runs.resume*` and maps its signals onto `resumeClose()` / `resumeConfirm()` and the two field properties; `Shortcuts` treats `resumeRunId !== ""` as an open modal.

**Tech Stack:** QML (Qt 6 Quick, Quickshell `qs.Commons` / `qs.Ui` stubs in tests), QtTest via `qmltestrunner` driven by `bash tests/run.sh`, pytest architecture guards.

**Spec:** `docs/superpowers/specs/3-2-resumeverifydialog-ad383829.md` (prepended above, verbatim).

## Global Constraints

- Components render and emit only; `ui/components/ResumeVerifyDialog.qml` imports no `core/` module and no store (`tests/architecture/test_layers.py`).
- Built from `UI.ModalCard`, `UI.ThemedText`, `UI.VerifyCommandsField`, `UI.ActionButton`; no `Qt.rgba(0, 0, 0, 0.55)`, no `radius: height/2`, no `font.family:`, no `bordered: true`, no `CursorSurface {`, no local copy of the verify rows.
- The only new glyph is `⟳` (U+27F3) as `iconText`.
- No local QML type shares a name with a shell/Controls type.
- Comments state the contract only, no narrative.
- UI strings use `…`, never `...`.
- No change to `core/stores/RunStore.qml`, `ui/components/VerifyCommandsField.qml`, `ui/components/DispatchDialog.qml`, `tests/ui/components/tst_dispatch_dialog.qml`, `tests/ui/components/tst_verify_commands_field.qml`.
- In `ui/Shortcuts.qml` no existing guard is reordered; the new branches are inserted only where the spec says.
- `bash tests/run.sh` green, and its output carries no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item`, `is not a function`.
- Exact strings: heading `Resume run ` + runLabel; body `am does not record the verify commands. They run for every subtask without a checkpoint, merged bases and Integrate.`; saved line `Saved for this project and reused by later resumes and dispatches.`; buttons `Cancel` and `Resume` (`iconText: "⟳"`).

## Review Focus

1. **The first verify row is recreated when the row count changes** (the field's `Repeater` model is an int): `focusItem` must always be the live `resumeVerify0`, not a stale or destroyed row — pinned in Task 1 (`test_focus_item_follows_the_rows_as_they_are_made_again`).
2. **Escape that reaches the panel (not a row) while a run toast shows** must close only the dialog, keep the toast and the panel — pinned in Task 2 (`test_escape_at_the_panel_closes_only_the_resume_dialog_and_keeps_the_toast`).
3. **A Ctrl chord (Ctrl+1 / Ctrl+6) or `r` under the dialog** must do nothing — pinned in Task 2 (`test_global_chords_and_run_keys_are_dead_under_the_resume_dialog`).
4. **A second `resumeOpenFor` while open** must show the new run, one empty row, focus in row 0 — pinned in Task 2 (`test_a_second_open_replaces_the_run_and_resets_the_rows`).
5. **Opt-out ticked with blank rows, and closing on Run detail** must launch with `--allow-no-verification`, save `allowNoVerification: true`, and give the focus back to the key catcher on Run detail — pinned in Task 2 (`test_the_opt_out_resumes_without_verification` and `test_closing_on_run_detail_gives_the_focus_back_to_the_key_catcher`).

## File Structure

- Create `ui/components/ResumeVerifyDialog.qml` — the dialog, presentation only.
- Create `tests/ui/components/tst_resume_verify_dialog.qml` — component tests 1-10 plus Review Focus 1.
- Modify `ui/Panel.qml` — mount the dialog beside `runCancelModal` (after line 843), extend the `focusItem` chain (after line 184), refocus on `resumeRunIdChanged` (in the `appStores.runs` `Connections`, line 98-107).
- Modify `ui/Shortcuts.qml` — `closeRequested()` (line 45) and `modalOpen()` (lines 49-53).
- Modify `tests/ui/tst_runs_flow.qml` — flow tests 11-13 plus Review Focus 2-5.
- Modify `docs/architecture.md` — shared components entry (after line 154) and one sentence in the run screens paragraph (line 166).

---

### Task 1: ResumeVerifyDialog component

**Files:**
- Create: `ui/components/ResumeVerifyDialog.qml`
- Test: `tests/ui/components/tst_resume_verify_dialog.qml`

**Interfaces:**
- Consumes: `UI.ModalCard` (props `shown`, `dismissable`, `maxWidth`, `maxHeight`, `backdropObjectName`, `cardObjectName`; signal `dismissed()`; default property puts children in the card's column), `UI.VerifyCommandsField` (props `theme`, `commands`, `allowNoVerification`, `editable`, `objectNamePrefix`; signals `commandsEdited(var commands)`, `allowNoVerificationEdited(bool on)`, `keyPressed(var event)`; inner names `resumeVerifyLabel`, `resumeVerify<i>`, `resumeVerifyRemove<i>`, `resumeVerifyAdd`, `resumeNoVerify`), `UI.ThemedText` (`variant`, `theme`, `text`), `UI.ActionButton` (`text`, `iconText`, `enabled`, `theme`, signal `clicked()`).
- Produces: QML type `ResumeVerifyDialog` (file `ui/components/ResumeVerifyDialog.qml`), default `objectName: "resumeVerifyDialog"`. Props `shown: bool = false`, `runLabel: string = ""`, `commands: var = []`, `allowNoVerification: bool = false`, `error: string = ""`, `theme: var = T.Theme {}`. Read-only `focusItem: Item` (the live `resumeVerify0`), `canResume: bool`. Signals `commandsEdited(var commands)`, `allowNoVerificationEdited(bool on)`, `confirmRequested()`, `cancelRequested()`. Inner objectNames `resumeDialogBackdrop`, `resumeDialogCard`, `resumeDialogTitle`, `resumeDialogBody`, `resumeDialogSaved`, `resumeDialogError`, `resumeDialogCancel`, `resumeDialogAccept`, plus the field's `resume…` names.

- [ ] **Step 1: Write the failing test file**

Create `tests/ui/components/tst_resume_verify_dialog.qml`:

```qml
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "ResumeVerifyDialog"
  when: windowShown
  visible: true
  width: 640; height: 700

  Component { id: dialogC; UI.ResumeVerifyDialog { width: 640; height: 700 } }
  SignalSpy { id: edits; signalName: "commandsEdited" }
  SignalSpy { id: optOuts; signalName: "allowNoVerificationEdited" }
  SignalSpy { id: confirms; signalName: "confirmRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  readonly property string bodyText: "am does not record the verify commands. They run for every subtask without a checkpoint, merged bases and Integrate."
  readonly property string savedText: "Saved for this project and reused by later resumes and dispatches."

  // A shown dialog for run …4a51d663 with no commands; `over` replaces any prop.
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, Object.assign({ shown: true, runLabel: "…4a51d663", commands: [] }, over || {}))
    edits.target = d; optOuts.target = d; confirms.target = d; cancels.target = d
    edits.clear(); optOuts.clear(); confirms.clear(); cancels.clear()
    wait(30)
    return d
  }
  // A freshly laid-out item is placed on the next frame: wait, so the click
  // lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  // 1
  function test_renders_the_wording() {
    var d = make()
    compare(d.visible, true)
    compare(d.objectName, "resumeVerifyDialog")
    verify(H.find(d, "resumeDialogCard"), "the modal card")
    verify(H.find(d, "resumeDialogBackdrop"), "the backdrop")
    compare(H.find(d, "resumeDialogTitle").text, "Resume run …4a51d663")
    compare(H.find(d, "resumeDialogBody").text, tc.bodyText)
    compare(H.find(d, "resumeDialogBody").wrapMode, Text.WordWrap)
    compare(H.find(d, "resumeDialogSaved").text, tc.savedText)
    compare(H.find(d, "resumeDialogSaved").wrapMode, Text.WordWrap)
    verify(H.find(d, "resumeVerifyLabel"), "the Verify caption")
    verify(H.find(d, "resumeVerify0"), "the first verify row")
    verify(H.find(d, "resumeVerifyAdd"), "the + button")
    verify(H.find(d, "resumeNoVerify"), "the opt-out chip")
    compare(H.find(d, "resumeNoVerify").text, "run without any verification")
    compare(H.find(d, "resumeDialogCancel").text, "Cancel")
    var accept = H.find(d, "resumeDialogAccept")
    compare(accept.text, "Resume")
    compare(accept.iconText, "⟳")
    compare(H.find(d, "resumeDialogError").visible, false)
  }

  // 2
  function test_hidden_while_not_shown() {
    var d = make({ shown: false })
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
  }

  // 3
  function test_resume_follows_the_verify_rule_data() {
    return [
      { tag: "empty-list", commands: [], allow: false, can: false },
      { tag: "one-blank", commands: [""], allow: false, can: false },
      { tag: "only-spaces", commands: ["  "], allow: false, can: false },
      { tag: "null", commands: null, allow: false, can: false },
      { tag: "a-string", commands: "x", allow: false, can: false },
      { tag: "blank-then-command", commands: ["", "a"], allow: false, can: true },
      { tag: "opt-out-no-rows", commands: [], allow: true, can: true }
    ]
  }

  function test_resume_follows_the_verify_rule(data) {
    var d = make({ commands: data.commands, allowNoVerification: data.allow })
    compare(d.canResume, data.can)
    compare(H.find(d, "resumeDialogAccept").enabled, data.can)
  }

  // 4
  function test_edits_are_forwarded_and_change_nothing_here() {
    var d = make()
    H.find(d, "resumeVerify0").text = "bash tests/run.sh"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["bash tests/run.sh"])
    click(H.find(d, "resumeNoVerify"))
    compare(optOuts.count, 1)
    compare(optOuts.signalArguments[0][0], true)
    compare(d.commands.length, 0, "the dialog never changes its commands")
    compare(d.allowNoVerification, false, "nor its opt-out")
    compare(confirms.count, 0)
    compare(cancels.count, 0)
  }

  // 5
  function test_resume_confirms_only_when_enabled() {
    var d = make({ commands: [] })
    click(H.find(d, "resumeDialogAccept"))
    compare(confirms.count, 0)
    d.commands = ["a"]
    wait(450)
    click(H.find(d, "resumeDialogAccept"))
    compare(confirms.count, 1)
    compare(cancels.count, 0)
  }

  // 6
  function test_cancel_backdrop_and_escape_cancel() {
    var d = make({ commands: ["a"] })
    click(H.find(d, "resumeDialogCancel"))
    compare(cancels.count, 1)
    mouseClick(H.find(d, "resumeDialogBackdrop"), 2, 2)
    compare(cancels.count, 2)
    mouseClick(H.find(d, "resumeDialogCard"), 3, 3)
    compare(cancels.count, 2, "a click on the card does not cancel")
    H.find(d, "resumeVerify0").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 3)
    compare(confirms.count, 0)
  }

  // 7
  function test_return_does_not_confirm() {
    var d = make({ commands: ["a"] })
    compare(d.canResume, true)
    H.find(d, "resumeVerify0").forceActiveFocus()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(confirms.count, 0)
    compare(cancels.count, 0)
  }

  // 8
  function test_error_shows_in_urgent() {
    var d = make({ error: "Another am process…" })
    var line = H.find(d, "resumeDialogError")
    compare(line.visible, true)
    compare(line.text, "Another am process…")
    compare(line.color, d.theme.urgent)
    compare(line.wrapMode, Text.WordWrap)
    d.error = ""
    compare(line.visible, false)
  }

  // 9
  function test_focus_item_is_the_first_row() {
    var d = make()
    verify(d.focusItem, "a focus item")
    compare(d.focusItem.objectName, "resumeVerify0")
  }

  // Review Focus 1: the field makes its rows again when their count changes.
  function test_focus_item_follows_the_rows_as_they_are_made_again() {
    var d = make()
    d.commands = ["a", "b"]
    wait(0)
    compare(d.focusItem, H.find(d, "resumeVerify0"))
    compare(d.focusItem.text, "a")
    d.commands = []
    wait(0)
    compare(d.focusItem, H.find(d, "resumeVerify0"))
    compare(d.focusItem.text, "")
    d.focusItem.forceActiveFocus()
    verify(d.focusItem.activeFocus, "the live row takes the keyboard")
  }

  // 10
  function test_a_null_theme_and_commands_and_destroy_are_quiet() {
    var d = make({ commands: ["a"] })
    d.theme = null
    d.commands = null
    wait(0)
    compare(d.canResume, false)
    compare(edits.count, 0)
    d.destroy()
    wait(0)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh resume_verify_dialog`
Expected: FAIL — the `== tests/ui/components/tst_resume_verify_dialog.qml` block reports that `ResumeVerifyDialog` is not a type (`UI.ResumeVerifyDialog is not a type` / `non-existent`), exit status 1.

- [ ] **Step 3: Write the component**

Create `ui/components/ResumeVerifyDialog.qml`:

```qml
import QtQuick
import qs.Commons
import "../components" as UI
import "../theme" as T

// The Resume dialog over a dimmed backdrop: `Resume run <runLabel>`, why am
// needs the verify commands, a VerifyCommandsField (prefix `resume`), that the
// set is saved for the project, `error` in urgent, then Cancel and `⟳ Resume`.
// Renders and emits only: reads shown, runLabel, commands, allowNoVerification,
// error and theme and never changes them. Emits commandsEdited(commands) and
// allowNoVerificationEdited(on) as the field does, confirmRequested() for a
// click on Resume while canResume, and cancelRequested() for Cancel, the
// backdrop or Escape in a verify row; Return never confirms. canResume is the
// verify rule of Runs.validateDispatch: the opt-out, or a string command with
// non-whitespace content. focusItem is the first verify row. objectNames:
// resumeDialogBackdrop, resumeDialogCard, resumeDialogTitle, resumeDialogBody,
// resumeVerify…, resumeDialogSaved, resumeDialogError, resumeDialogCancel,
// resumeDialogAccept.
Item {
  id: dialog
  objectName: "resumeVerifyDialog"
  z: 100

  property bool shown: false
  // The run as the heading names it, e.g. `…4a51d663`.
  property string runLabel: ""
  // A list, or the array-like a list arrives as; anything else holds no command.
  property var commands: []
  property bool allowNoVerification: false
  property string error: ""
  // Colours and fonts; null falls back to the shell's Color.
  property var theme: T.Theme {}

  // Read through the field's children, so a row made again is picked up.
  readonly property Item focusItem: dialog.firstRow(verifyField.children)
  readonly property bool canResume: dialog.allowNoVerification || dialog.holdsCommand(dialog.commands)
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent

  signal commandsEdited(var commands)
  signal allowNoVerificationEdited(bool on)
  signal confirmRequested()
  signal cancelRequested()

  visible: shown

  function holdsCommand(list) {
    if (!list || typeof list !== "object" || typeof list.length !== "number") return false
    for (var i = 0; i < list.length; i++) {
      if (typeof list[i] === "string" && list[i].trim() !== "") return true
    }
    return false
  }

  // The `resumeVerify0` text field among the field's rows; null before it exists.
  function firstRow(rows) {
    for (var i = 0; i < rows.length; i++) {
      var kids = rows[i] ? rows[i].children : []
      for (var j = 0; j < kids.length; j++) {
        if (kids[j].objectName === "resumeVerify0") return kids[j]
      }
    }
    return null
  }

  // Escape in a verify row cancels; every other key is left to the row.
  function rowKey(event) {
    if (event.key !== Qt.Key_Escape) return
    dialog.cancelRequested()
    event.accepted = true
  }

  UI.ModalCard {
    anchors.fill: parent
    shown: true
    maxWidth: Style.space(520)
    maxHeight: dialog.height - Style.space(48)
    backdropObjectName: "resumeDialogBackdrop"
    cardObjectName: "resumeDialogCard"
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      objectName: "resumeDialogTitle"
      variant: "heading"
      theme: dialog.theme
      width: parent.width
      text: "Resume run " + dialog.runLabel
      font.bold: true
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "resumeDialogBody"
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: "am does not record the verify commands. They run for every subtask without a checkpoint, merged bases and Integrate."
      wrapMode: Text.WordWrap
    }

    UI.VerifyCommandsField {
      id: verifyField
      width: parent.width
      objectNamePrefix: "resume"
      theme: dialog.theme
      commands: dialog.commands
      allowNoVerification: dialog.allowNoVerification
      editable: true
      onCommandsEdited: function(commands) { dialog.commandsEdited(commands) }
      onAllowNoVerificationEdited: function(on) { dialog.allowNoVerificationEdited(on) }
      onKeyPressed: function(event) { dialog.rowKey(event) }
    }

    UI.ThemedText {
      objectName: "resumeDialogSaved"
      variant: "caption"
      theme: dialog.theme
      width: parent.width
      text: "Saved for this project and reused by later resumes and dispatches."
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "resumeDialogError"
      variant: "small"
      theme: dialog.theme
      visible: dialog.error !== ""
      width: parent.width
      text: dialog.error
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        objectName: "resumeDialogCancel"
        text: "Cancel"
        theme: dialog.theme
        onClicked: dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "resumeDialogAccept"
        iconText: "⟳"
        text: "Resume"
        enabled: dialog.canResume
        theme: dialog.theme
        onClicked: if (dialog.canResume) dialog.confirmRequested()
      }
    }
  }
}
```

- [ ] **Step 4: Run the component tests to verify they pass**

Run: `bash tests/run.sh resume_verify_dialog`
Expected: pytest passes (architecture guards included: no store import, no guarded pattern, `⟳` accepted by `test_icon_glyphs.py`); the `tst_resume_verify_dialog.qml` block prints `Totals: N passed, 0 failed` with no `FAIL` line and no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `anchors on an item` / `is not a function` line; exit status 0.

`focusItem` is re-read on the field's `childrenChanged`: the `Repeater` unparents a row it removes, so a row made again replaces the old one in `children`. Do not change `VerifyCommandsField` to expose its rows (out of scope).

- [ ] **Step 5: Run the dispatch and field tests to confirm nothing shared moved**

Run: `bash tests/run.sh components/tst_`
Expected: every `tests/ui/components/tst_*.qml` block reports `0 failed`; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add ui/components/ResumeVerifyDialog.qml tests/ui/components/tst_resume_verify_dialog.qml
git commit -m "feat(ui): ResumeVerifyDialog asks for the verify commands of a resume"
```

---

### Task 2: Panel mounts the dialog; Shortcuts treat it as a modal

**Files:**
- Modify: `ui/Panel.qml:98-107` (the `appStores.runs` `Connections`), `ui/Panel.qml:184` (the `focusItem` chain), `ui/Panel.qml:843` (after `runCancelModal`)
- Modify: `ui/Shortcuts.qml:45` (`closeRequested()`), `ui/Shortcuts.qml:49-53` (`modalOpen()`)
- Test: `tests/ui/tst_runs_flow.qml` (a new section at the end of the file, before the `TestCase`'s final `}`; it reuses the file's `make()`, `run()`, `sampleRuns()`, `reply()`, `key()` and `withToast()`)

**Interfaces:**
- Consumes: `ResumeVerifyDialog` from Task 1 (props `shown`, `runLabel`, `commands`, `allowNoVerification`, `error`, `theme`; `focusItem`; signals `commandsEdited(var commands)`, `allowNoVerificationEdited(bool on)`, `confirmRequested()`, `cancelRequested()`). From `RunStore` (unchanged): `resumeRunId: string`, `resumeVerify: var`, `resumeAllowNoVerification: bool`, `resumeError: string`, `resumeOpenFor(runId) -> bool`, `resumeClose()`, `resumeConfirm() -> bool`, `resumeSaveRunner` (a `HelperRunner` with `seq` and `current.command`), `controlRunners` (list; each `.current.command` an argv array), `refusalOf(action, runId) -> string`, `pending` (object). `Runs.shortId({id}) -> "…" + last 8`.
- Produces: in `Panel`, the mounted dialog `objectName: "resumeVerifyDialog"`, `id: resumeDialog`; `Panel.focusItem` returns `resumeDialog.focusItem` while `resumeRunId !== ""` (unless a modal earlier in the chain is open). In `Shortcuts`, `modalOpen()` true while `resumeRunId !== ""`; `closeRequested()` calls `resumeClose()` while it is open, ahead of toasts.

- [ ] **Step 1: Write the failing flow tests**

In `tests/ui/tst_runs_flow.qml`, insert this block directly before the file's final closing `}` (the `TestCase`'s):

```qml
  // ---- the Resume dialog (3.2)

  function resumeDialog(p) { return H.find(p, "resumeVerifyDialog") }
  function argv(proc) { return proc.command.join("|") }
  function endsWith(text, tail) { return text.slice(-tail.length) === tail }
  // filteredRuns' index of the run `id`: the cursor row that names it.
  function indexOfRun(p, id) { return p.app.runs.filteredRuns.map(function(r) { return r.id }).indexOf(id) }

  // The Runs list with the cursor on the escalated milestone run, `r` in the
  // empty search, and get-run-settings answering with nothing stored.
  function openResumeByKey(p) {
    p.navigator.showSection("runs")
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    p.app.nav.cursorIndex = indexOfRun(p, "run-0000000000b2")
    keyClick("r")
    compare(p.app.runs.controlRunners.length, 1, "one runner reads the run settings")
    verify(argv(p.app.runs.controlRunners[0].current).indexOf("get-run-settings") >= 0,
           "the runner reads get-run-settings")
    reply(p.app.runs.controlRunners[0].current,
          JSON.stringify({ verify: [], allowNoVerification: false }) + "\n", 0)
    wait(50)
    return field
  }

  // 11
  function test_r_with_no_stored_set_opens_the_dialog_and_resume_launches_with_the_typed_commands() {
    var p = make(); if (!p) return
    var field = openResumeByKey(p)
    var dialog = resumeDialog(p)
    verify(dialog, "the Resume dialog is mounted")
    compare(dialog.visible, true)
    compare(p.app.runs.resumeRunId, "run-0000000000b2")
    compare(Object.keys(p.app.runs.pending).length, 0, "nothing pending")
    compare(H.find(p, "resumeDialogTitle").text, "Resume run …000000b2")
    compare(p.focusItem.objectName, "resumeVerify0")
    verify(p.focusItem.activeFocus, "row 0 has the keyboard")
    compare(field.text, "", "the handled r was not typed")

    H.find(p, "resumeVerify0").text = "bash tests/run.sh"
    compare(p.app.runs.resumeVerify.length, 1)
    compare(p.app.runs.resumeVerify[0], "bash tests/run.sh")
    mouseClick(H.find(p, "resumeVerifyAdd"))
    wait(50)
    var row1 = H.find(p, "resumeVerify1")
    verify(row1, "+ added a row")
    row1.text = "uv run pytest"
    compare(p.app.runs.resumeVerify.length, 2)
    wait(450)
    var accept = H.find(p, "resumeDialogAccept")
    compare(accept.enabled, true)
    mouseClick(accept)

    compare(dialog.visible, false)
    compare(p.app.runs.resumeRunId, "")
    compare(p.app.runs.pending["run-0000000000b2"], "resume")
    compare(p.app.runs.controlRunners.length, 1)
    var launched = argv(p.app.runs.controlRunners[0].current)
    verify(endsWith(launched, "run-control.py|resume|run-0000000000b2|/home/u/a|--verify|bash tests/run.sh|--verify|uv run pytest"),
           "run-control got the typed commands in order: " + launched)
    compare(p.app.runs.resumeSaveRunner.seq, 1, "the set was saved")
    verify(argv(p.app.runs.resumeSaveRunner.current).indexOf("set-run-settings|/home/u/a|") >= 0,
           "saved for the run's project")
    wait(50)
    compare(p.focusItem.objectName, "searchField")
    verify(field.activeFocus, "the focus is back in the search field")
  }

  // 12
  function test_escape_closes_only_the_resume_dialog_and_the_run_keys_are_dead_under_it() {
    var p = make(); if (!p) return
    var field = openResumeByKey(p)
    var row0 = H.find(p, "resumeVerify0")
    verify(row0.activeFocus, "row 0 has the keyboard")
    compare(p.shortcuts.modalOpen(), true)
    keyClick("p")
    keyClick("c")
    compare(row0.text, "pc", "the letters were typed into the row")
    compare(Object.keys(p.app.runs.pending).length, 0)
    compare(p.app.runs.cancelOpen, false)
    compare(p.app.runs.controlRunners.length, 0)
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.resumeRunId, "")
    compare(resumeDialog(p).visible, false)
    compare(p.app.nav.viewMode, "runs")
    compare(p.opened, true, "the panel stays open")
    compare(Object.keys(p.app.runs.pending).length, 0)
    compare(p.shortcuts.modalOpen(), false)
    wait(50)
    verify(field.activeFocus, "the focus is back in the search field")
    compare(field.text, "")
  }

  // 13
  function test_a_refused_confirm_keeps_the_dialog_with_the_reason_and_the_rows() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    compare(p.app.runs.resumeOpenFor("run-0000000000b2"), true)
    wait(50)
    H.find(p, "resumeVerify0").text = "bash tests/run.sh"
    p.app.runs.runs = [run("run-0000000000b2", "started", true, "beta")]
    var reason = p.app.runs.refusalOf("resume", "run-0000000000b2")
    verify(reason !== "", "a live run cannot be resumed")
    wait(450)
    mouseClick(H.find(p, "resumeDialogAccept"))
    compare(resumeDialog(p).visible, true)
    compare(p.app.runs.resumeRunId, "run-0000000000b2")
    var error = H.find(p, "resumeDialogError")
    compare(error.visible, true)
    compare(error.text, reason)
    compare(H.find(p, "resumeVerify0").text, "bash tests/run.sh", "the typed row is kept")
    compare(p.app.runs.controlRunners.length, 0, "run-control was never launched")
    compare(p.app.runs.resumeSaveRunner.seq, 0, "nothing saved")
  }

  // Review Focus 2
  function test_escape_at_the_panel_closes_only_the_resume_dialog_and_keeps_the_toast() {
    var p = withToast("runs"); if (!p) return
    p.app.runs.runs = sampleRuns()
    compare(p.app.runs.resumeOpenFor("run-0000000000b2"), true)
    wait(50)
    p.shortcuts.closeRequested()
    compare(p.app.runs.resumeRunId, "")
    compare(resumeDialog(p).visible, false)
    compare(p.app.runs.toasts.length, 1, "the toast is kept")
    compare(p.opened, true)
    compare(p.app.nav.viewMode, "runs")
  }

  // Review Focus 3
  function test_global_chords_and_run_keys_are_dead_under_the_resume_dialog() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    p.app.nav.cursorIndex = indexOfRun(p, "run-0000000000b2")
    compare(p.app.runs.resumeOpenFor("run-0000000000b2"), true)
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_1 }), false)
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), false)
    compare(p.app.nav.viewMode, "runs")
    compare(p.shortcuts.handleRunKey(key(Qt.Key_R)), false)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), false)
    compare(p.app.runs.controlRunners.length, 0)
    compare(p.app.runs.cancelOpen, false)
    compare(p.app.runs.resumeRunId, "run-0000000000b2")
  }

  // Review Focus 4
  function test_a_second_open_replaces_the_run_and_resets_the_rows() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    p.app.runs.resumeOpenFor("run-0000000000b2")
    wait(50)
    H.find(p, "resumeVerify0").text = "a"
    mouseClick(H.find(p, "resumeVerifyAdd"))
    wait(50)
    verify(H.find(p, "resumeVerify1"), "two rows")
    compare(p.app.runs.resumeOpenFor("run-0000000000d4"), true)
    wait(50)
    compare(H.find(p, "resumeDialogTitle").text, "Resume run …000000d4")
    compare(H.find(p, "resumeVerify0").text, "")
    verify(!H.find(p, "resumeVerify1"), "one empty row again")
    compare(p.focusItem.objectName, "resumeVerify0")
    verify(p.focusItem.activeFocus, "row 0 has the keyboard")
  }

  // Review Focus 5
  function test_the_opt_out_resumes_without_verification() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    p.app.runs.resumeOpenFor("run-0000000000b2")
    wait(50)
    var accept = H.find(p, "resumeDialogAccept")
    compare(accept.enabled, false, "blank rows, no opt-out")
    mouseClick(H.find(p, "resumeNoVerify"))
    compare(p.app.runs.resumeAllowNoVerification, true)
    compare(accept.enabled, true)
    wait(450)
    mouseClick(accept)
    compare(p.app.runs.resumeRunId, "")
    compare(p.app.runs.controlRunners.length, 1)
    var launched = argv(p.app.runs.controlRunners[0].current)
    verify(endsWith(launched, "run-control.py|resume|run-0000000000b2|/home/u/a|--allow-no-verification"),
           "run-control got the opt-out: " + launched)
    verify(endsWith(argv(p.app.runs.resumeSaveRunner.current),
                    "set-run-settings|/home/u/a|" + JSON.stringify({ verify: [], allowNoVerification: true })),
           "the opt-out was saved")
  }

  // Review Focus 5
  function test_closing_on_run_detail_gives_the_focus_back_to_the_key_catcher() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000b2")
    wait(50)
    compare(p.app.runs.resumeOpenFor("run-0000000000b2"), true)
    wait(50)
    compare(p.focusItem.objectName, "resumeVerify0")
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.resumeRunId, "")
    compare(p.app.nav.viewMode, "run", "Escape closed only the dialog")
    wait(50)
    compare(p.focusItem.objectName, "keyCatcher")
    verify(p.focusItem.activeFocus, "the key catcher has the keyboard")
  }
```

- [ ] **Step 2: Run the flow tests to verify they fail**

Run: `bash tests/run.sh runs_flow`
Expected: FAIL — the new cases fail with `the Resume dialog is mounted` / `null` lookups for `resumeVerify0` / `resumeDialogAccept` (no dialog in Panel), and `modalOpen()` / `handleGlobalKey` cases fail on `true !== false`. The existing cases still pass. Exit status 1.

- [ ] **Step 3: Refocus when the dialog opens or closes**

In `ui/Panel.qml`, in the `appStores.runs` `Connections` (lines 94-107), replace:

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation takes the focus when it
  // opens and gives it back when it closes. A started dispatch closes its
  // dialog and goes to the run; the run is usually not in the snapshot yet,
  // so every new list may hold the run the navigator still waits for.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
```

with:

```qml
  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation and the Resume dialog
  // take the focus when they open and give it back when they close. A started
  // dispatch closes its dialog and goes to the run; the run is usually not in
  // the snapshot yet, so every new list may hold the run the navigator still
  // waits for.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onCancelOpenChanged() { root.focusForView() }
    function onResumeRunIdChanged() { root.focusForView() }
```

- [ ] **Step 4: Put the dialog in the focus chain**

In `ui/Panel.qml`, replace:

```qml
    : appStores.runs.cancelOpen ? runCancelModal.focusItem
```

with:

```qml
    : appStores.runs.cancelOpen ? runCancelModal.focusItem
    : appStores.runs.resumeRunId !== "" ? resumeDialog.focusItem
```

- [ ] **Step 5: Mount the dialog beside the cancel confirmation**

In `ui/Panel.qml`, directly after the closing `}` of the `TypedConfirmDialog { id: runCancelModal … }` block (the line after `onCancelRequested: appStores.runs.closeCancel()`), insert:

```qml

      // The Resume dialog: a milestone resume with no stored verify set asks
      // for the commands through the run store; only its confirm resumes.
      ResumeVerifyDialog {
        id: resumeDialog
        objectName: "resumeVerifyDialog"
        anchors.fill: parent
        shown: appStores.runs.resumeRunId !== ""
        runLabel: Runs.shortId({ id: appStores.runs.resumeRunId })
        commands: appStores.runs.resumeVerify
        allowNoVerification: appStores.runs.resumeAllowNoVerification
        error: appStores.runs.resumeError
        theme: panelTheme
        onCommandsEdited: function(commands) { appStores.runs.resumeVerify = commands }
        onAllowNoVerificationEdited: function(on) { appStores.runs.resumeAllowNoVerification = on }
        onConfirmRequested: appStores.runs.resumeConfirm()
        onCancelRequested: appStores.runs.resumeClose()
      }
```

- [ ] **Step 6: Escape closes the dialog before the toasts; it counts as a modal**

In `ui/Shortcuts.qml`, in `closeRequested()` (line 45), replace the fragment:

```
keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts()
```

with:

```
keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.resumeRunId !== "" ? keys.app.runs.resumeClose() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts()
```

(only that fragment of the one-line expression changes; everything before and after it stays byte for byte).

Then replace `modalOpen()`:

```qml
  // A modal is open: the global shortcuts, the run keys and d do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen
              || keys.app.runs.dispatchState !== "idle")
  }
```

with:

```qml
  // A modal is open: the global shortcuts, the run keys and d do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen
              || keys.app.runs.dispatchState !== "idle" || keys.app.runs.resumeRunId !== "")
  }
```

And in the comment above `closeRequested()`, replace:

```qml
  // dispatch closes like the other modals; while its start is in flight
  // closeDispatch() refuses, so that Escape does nothing at all.
```

with:

```qml
  // dispatch closes like the other modals; while its start is in flight
  // closeDispatch() refuses, so that Escape does nothing at all. The Resume
  // dialog closes after the cancel confirmation and before the toasts.
```

- [ ] **Step 7: Run the flow and Shortcuts tests to verify they pass**

Run: `bash tests/run.sh runs_flow`
Expected: the `tst_runs_flow.qml` block prints `Totals: N passed, 0 failed`, no `FAIL` line, no error-pattern line; exit status 0.

Run: `bash tests/run.sh shortcuts`
Expected: `tst_shortcuts.qml` `0 failed`; exit status 0.

If `test_r_with_no_stored_set_…` fails at `p.focusItem.activeFocus` while `p.focusItem.objectName` is right, the `focusForView` call ran before the dialog became visible: confirm `shown` is bound to `resumeRunId !== ""` exactly (Step 5) — the binding updates synchronously on the property change, before `Qt.callLater` runs.

- [ ] **Step 8: Commit**

```bash
git add ui/Panel.qml ui/Shortcuts.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(ui): Panel mounts the Resume dialog; Escape and the modal guard cover it"
```

---

### Task 3: Architecture doc and the full suite

**Files:**
- Modify: `docs/architecture.md:154` (shared components list), `docs/architecture.md:166` (run screens paragraph)

**Interfaces:**
- Consumes: the names from Tasks 1-2 (`ResumeVerifyDialog`, `resumeVerifyDialog`, `resumeRunId`, `resumeVerify`, `resumeAllowNoVerification`, `resumeError`, `resumeOpenFor`, `resumeClose`, `resumeConfirm`).
- Produces: documentation only.

- [ ] **Step 1: Add the shared component entry**

In `docs/architecture.md`, directly after the line that starts with `` `DispatchDialog` (the dispatch modal: `` and ends with `` Panel mounts it as `dispatchDialog`), `` (line 154), insert this new line:

```markdown
`ResumeVerifyDialog` (the Resume modal for a milestone resume with no stored verify set: `Resume run <runLabel>`, the sentence that am does not record the verify commands and runs them for every subtask without a checkpoint, merged bases and Integrate, a `VerifyCommandsField` (prefix `resume`; its `run without any verification` chip is the opt-out), `Saved for this project and reused by later resumes and dispatches.`, `error` in `urgent`, then Cancel and `⟳ Resume`. Presentation only: the owner passes `runLabel`, `commands`, `allowNoVerification`, `error` and `theme` and maps `commandsEdited(commands)` and `allowNoVerificationEdited(on)` (forwarded from the field), `confirmRequested()` (a click on Resume while `canResume`, the verify rule of `Runs.validateDispatch`: the opt-out or a non-blank command; Return never confirms) and `cancelRequested()` (Cancel, the backdrop, Escape in a verify row); it never changes its inputs. `focusItem` is the first verify row. Panel mounts it as `resumeVerifyDialog`),
```

- [ ] **Step 2: Add the run screens sentence**

In `docs/architecture.md`, replace the unique text:

```
-- a run that changed under it keeps it open with the reason.
```

with:

```
-- a run that changed under it keeps it open with the reason. Panel mounts `resumeVerifyDialog` (a `ResumeVerifyDialog`) the same way for `app.runs.resumeRunId`: `r` or a Resume button on a milestone run with no stored verify set opens it, it takes the focus while open and gives it back on close, Escape closes only it, a refused confirm keeps it open with `resumeError` and the typed rows, and only its confirm (`resumeConfirm()`) resumes.
```

- [ ] **Step 3: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest all passed; every QML block `0 failed`; no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` line; exit status 0.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: ResumeVerifyDialog in the shared components and the run screens"
```

---

## Self-review

- **Spec coverage.** Component interface (props, `focusItem`, `canResume`, signals, objectNames) → Task 1 Step 3. "What it shows" 1-6 → Task 1 Step 3, pinned by tests 1 and 8. Keys (Escape cancels, Return does not) → `rowKey`, tests 6 and 7. Panel mount, bindings, signal mapping → Task 2 Step 5; focus chain → Step 4; refocus → Step 3; refused confirm keeps rows → test 13. Shortcuts `closeRequested` and `modalOpen` → Step 6, tests 12 and Review Focus 2-3. Docs → Task 3. Tests 1-10 → Task 1; 11-13 → Task 2. Edge-case table: all-blank / whitespace / null / string → test 3; opt-out with blank rows → test 3 and Review Focus 5; run changed → test 13; p/r/c/d/Ctrl under dialog → test 12 and Review Focus 3 (`d` is guarded by the same `modalOpen()`); Escape in a row → test 12; backdrop → test 6; second `resumeOpenFor` → Review Focus 4; task run's `r` is a store rule left unchanged (store tests already cover it); null theme / destroy → test 10.
- **Placeholders.** None: every code step has the full code; the docs steps carry the exact text.
- **Type consistency.** `focusItem`, `canResume`, `commandsEdited`, `allowNoVerificationEdited`, `confirmRequested`, `cancelRequested`, `resumeDialog` / `resumeVerifyDialog` match across Tasks 1-3; the store names match `core/stores/RunStore.qml` lines 1381-1462.
- **Review Focus.** Five lines, each with its test in the owning task.
<!-- task-pipeline: validated -->
