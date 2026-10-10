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
