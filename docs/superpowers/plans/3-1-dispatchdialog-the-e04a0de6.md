# 3.1 DispatchDialog: the project step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ui/components/DispatchDialog.qml` renders RunStore's project step (`step: "project"`, `projectRows`): one row per project, a cursor over the enabled rows driven by Up / Down / hover, a pick by Enter or click emitted as `projectChosen(root)`, the two empty states, and Cancel only.

**Architecture:** The dialog stays props-in / signals-out. Two new props (`step`, `projectRows`), one derived flag (`atProject`) that hides every form-step part, a `Flickable` of `UI.ListRow`s plus an empty-state line inside the existing `UI.ModalCard`, a private cursor (`QtObject` holding index and root) exposed read-only as `projectCursor`, and a key item (`dispatchProjectKeys`) that becomes `focusItem` at the project step. No store, domain, Panel or shared-component change.

**Tech Stack:** Qt 6 QML, QtTest (`qmltestrunner`, offscreen) run by `bash tests/run.sh` (pytest first — the architecture tier included — then every `tst_*.qml` whose path contains the filter); helpers in `tests/helpers/find.js` (`H.find(item, objectName)`, which also searches a `Flickable`'s `contentItem`).

**Spec:** `docs/superpowers/specs/3-1-dispatchdialog-the-e04a0de6.md` (reproduced in full below). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (**P**).

## Global Constraints

- Only two files change: `ui/components/DispatchDialog.qml` and `tests/ui/components/tst_dispatch_dialog.qml`. No change to `RunStore`, `runs.js`, `board-tree.py`, `ui/Panel.qml`, `ui/Shortcuts.qml`, `docs/architecture.md` or the README (cards 3.2–3.4).
- Built on `UI.ModalCard`, `UI.ListRow`, `UI.ActionButton`, `UI.ThemedText`; no new shared component, no `CursorSurface {`, no `font.family:`, no `Qt.rgba(0, 0, 0, 0.55)` in the dialog. `tests/architecture` (`test_layers.py`, `test_icon_glyphs.py`) stays green.
- The dialog never imports a store; it renders and emits only.
- Exact strings: heading `Dispatch · 1 Project` at the project step, `Dispatch` at every other; open caption `open`; empty lines `No projects registered` and `No project's board can be read`.
- Exact objectNames: `dispatchProjectList`, `dispatchProjectRow<i>`, `dispatchProjectName<i>`, `dispatchProjectOpen<i>`, `dispatchProjectReason<i>`, `dispatchProjectEmpty`, `dispatchProjectKeys`.
- New API exactly: `property string step: ""`, `property var projectRows: []`, `signal projectChosen(string root)`, `readonly property int projectCursor`.
- A row is enabled only when `enabled === true`; `name` / `reason` / `root` that are not strings read as `""`; `open` counts only when `=== true`.
- List height capped at `Style.space(240)`.
- At every `step` other than `"project"` every existing behaviour and existing test holds unchanged; `projectChosen` is never emitted outside the project step.
- Comments state the contract only, no narrative.
- Verification: `bash tests/run.sh` green (it also greps the QML output for `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`, which fail the run).

## Review Focus

1. Focus left on `dispatchProjectKeys` after the owner moves on to another step: Return must not emit `projectChosen` there — pinned in Task 3 (`test_enter_after_leaving_the_project_step_picks_nothing`).
2. The registry shrinking so the cursor index points past the end of the new list: the cursor must land on the first enabled row, or `-1` with none — pinned in Task 3 (`test_rows_shrinking_past_the_cursor_put_it_on_the_first_enabled_row`).
3. A row with a `null` name, a non-string reason, `enabled: "yes"`, or a `null` row in the list: renders `""` (never `null`/`undefined`), counts as disabled, no warning — pinned in Task 2 (`test_a_malformed_row_reads_as_empty_and_disabled`).
4. A very long project name next to the `open` caption: elided on one line, the caption still shown — pinned in Task 2 (`test_a_long_project_name_elides_on_one_line`).
5. Escape at the project step while `busy` (`dispatchState: "starting"`): emits nothing, like every other Escape in the dialog — pinned in Task 3 (`test_escape_at_the_project_step_does_nothing_while_starting`).

---

## Spec (verbatim)

# 3.1 DispatchDialog: the project step — design

Card `e04a0de6` (subtask of story `7fad1523` "Dispatch from Runs UI"). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (cited below as **P**, with line
numbers).

## Problem

The store already runs the Runs dispatch's project step: `RunStore.dispatchStep` is `"project"`
after `dispatchOpenFromRuns()`, `dispatchProjectRows` holds `[{root, name, open, enabled, reason}]`
(built by `Runs.dispatchProjects`, `core/domain/runs.js:517`, open row first, then by name), and
`dispatchProjectPick(root)` takes an enabled row (`core/stores/RunStore.qml:1866-1960`). A failed
tree read already sends the store back to `"project"` with the reason on that row.

`ui/components/DispatchDialog.qml` knows none of this. It renders only S3's form (target line,
form, preview, warning, Cancel / Start). This card makes the dialog render the project step.

## Goal

Given `step: "project"` and the rows, the dialog shows one row per project, lets the user move a
cursor over the enabled rows with Up / Down and pick with Enter or a click, shows the two empty
states, and closes with Escape or Cancel. It renders and emits only, like the rest of the dialog
(`DispatchDialog.qml:7-14`): the owner maps the new signal onto `dispatchProjectPick(root)`.

## Inherited constraints

- Rows, order, open mark, disabled rows with their reason, cursor on the first enabled row,
  disabled rows skipped by the cursor and ignoring clicks: **P** 67-75.
- Empty states "No projects registered" and "No project's board can be read", with only Cancel:
  **P** 76-79.
- Up / Down over enabled rows, Enter picks; Escape closes at any step like every modal:
  **P** 119-123.
- Built on `ModalCard`, `ListRow`, `ActionButton`; no new shared component and no second copy of
  one: **P** 221-224, and the card. `tests/architecture` (`test_layers.py`
  `test_no_second_copy_of_shared_visual_patterns`, line 298; the import allowlist, line 214;
  `test_icon_glyphs.py`) must stay green.
- Screens and components receive props and never import stores (story `7fad1523`,
  `docs/architecture.md` layering).
- Docstrings and comments state the contract only, no narrative (card).
- Verification: `bash tests/run.sh` green (card).

## Behaviour

### New inputs and output

| member | kind | default | meaning |
|---|---|---|---|
| `step` | `string` property | `""` | RunStore's `dispatchStep`. Only `"project"` changes what the dialog shows in this card. Every other value, `""` included, renders exactly as today. |
| `projectRows` | `var` property | `[]` | RunStore's `dispatchProjectRows`. Anything that is not an array-like (null, undefined, an object, a string) reads as `[]`. |
| `projectChosen(string root)` | signal | | The user picked an enabled row. Emitted once per pick, with that row's `root`. |
| `projectCursor` | `readonly int` property | | The cursor's row index in `projectRows`, `-1` when there is no enabled row. Exposed for tests and for the owner; not settable from outside. |

A row is **enabled** only when its `enabled` is exactly `true`. `name` and `reason` that are not
strings read as `""`; `open` counts only when exactly `true`.

### What the project step shows

With `step === "project"`, top to bottom inside the existing `ModalCard`:

1. The heading (`dispatchHeading`) reads `Dispatch · 1 Project` (**P** 45). At every other step
   it stays `Dispatch`.
2. The project list (`dispatchProjectList`), a vertically scrolling list capped in height (at most
   about `Style.space(240)`, as `ArchiveFinishedDialog`'s list), holding one `UI.ListRow` per row
   in `projectRows` order, `objectName` `dispatchProjectRow<i>`. Each row shows:
   - `dispatchProjectName<i>`: the row's `name`, elided on the right. Colour: the theme's
     foreground for an enabled row, the theme's dim colour for a disabled one.
   - `dispatchProjectOpen<i>`: the caption `open`, visible only when the row's `open` is true.
   - `dispatchProjectReason<i>`: a caption with the row's `reason`, visible only for a disabled
     row, dim colour, word-wrapped.
   The row under the cursor carries `ListRow`'s cursor highlight (`hasCursor`). The list keeps the
   cursor row scrolled into view when the cursor moves by keyboard.
3. The empty-state line (`dispatchProjectEmpty`), visible only when there is no enabled row:
   - `projectRows` empty: `No projects registered`, and the list shows nothing.
   - rows present, none enabled: `No project's board can be read`. The disabled rows stay listed,
     dimmed with their reasons, so the user sees why.
4. The button row with **Cancel** (`dispatchCancel`) only. Start (`dispatchStart`) is not visible.

Not visible at the project step: the target line (`dispatchTarget`), the target chips
(`dispatchTargetChoices`), the form (`dispatchForm`), the preview heading and every preview-area
line (`dispatchPreviewHeading`, `dispatchRefusal`, `dispatchSuggest`, `dispatchExitCode`,
`dispatchLogPath`, `dispatchLogTail`, `dispatchSubtaskNote`, `dispatchStory`, `dispatchBlocked`,
`dispatchChecking`, `dispatchSummary`, `dispatchIntegrate`), the cost warning (`dispatchWarning`)
and the confirm note (`dispatchConfirmNote`). The project list and empty line are not visible at
any other step.

### The cursor

- When the step becomes `"project"`, and when the dialog is shown at that step, the cursor goes to
  the first enabled row (`-1` with none).
- When `projectRows` changes while at the project step (the probe's reply, a failed tree read, a
  registry change), the cursor stays on the same `root` if that root still has an enabled row;
  otherwise it goes to the first enabled row (`-1` with none).
- The cursor is never on a disabled row.

### Keys (project step)

The project step's key item (`dispatchProjectKeys`) is the dialog's `focusItem` at that step. At
every other step `focusItem` is unchanged (`form ? baseField : cancelButton`,
`DispatchDialog.qml:57`).

| key | effect | accepted |
|---|---|---|
| Down | cursor to the next enabled row below it; stays put on the last enabled row (no wrap) | yes |
| Up | cursor to the previous enabled row above it; stays put on the first (no wrap) | yes |
| Return / Enter | `projectChosen(root)` for the cursor row; nothing when the cursor is `-1` | yes |
| Escape | `cancel()`, so `cancelRequested()` unless `busy` (`DispatchDialog.qml:145-147`) | yes |
| any other key | nothing | no (left to the owner) |

### Mouse (project step)

- A click on an enabled row moves the cursor there and emits `projectChosen(root)` once.
- Hovering an enabled row moves the cursor there.
- A click on, or a hover over, a disabled row does nothing: no signal, the cursor stays.
- Cancel and the backdrop emit `cancelRequested()` through `cancel()`, as today
  (`DispatchDialog.qml:235`, `:560`). A click on the card itself does nothing.

### Unchanged

With `step` other than `"project"` every existing behaviour and every existing test of
`tests/ui/components/tst_dispatch_dialog.qml` holds as is. `projectChosen` is never emitted
outside the project step.

## Errors and edge inputs

| input | behaviour |
|---|---|
| `projectRows` null / undefined / not array-like | reads as `[]`: "No projects registered", Cancel only |
| a row whose `enabled` is missing or not `true` | disabled: dimmed, skipped by the cursor; its reason caption shows the reason (an empty reason leaves the caption empty; the domain always supplies one, `runs.js` falls back to `unreachable`) |
| rows shrink under the cursor (registry change) | cursor follows its root, else first enabled row, else `-1` |
| the only enabled row becomes disabled (failed tree read) | cursor `-1`, "No project's board can be read" if no other enabled row |
| Enter with cursor `-1` | nothing emitted |
| step leaves `"project"` and comes back | cursor starts over on the first enabled row |
| setting every object prop to null and destroying the dialog at the project step | no warnings (`TypeError`, `ReferenceError`), matching the existing teardown test (`tst_dispatch_dialog.qml:599`) |

## Out of scope

- The target step (`"target"`), its `FilterableList`, "Reading the board…", Back buttons and
  Backspace to step 1: card 3.2 (`f377621e`).
- Binding `step`, `projectRows` and `onProjectChosen` in `ui/Panel.qml`, the dialog showing and
  taking focus with no project open (`Panel.dispatchOpen` reads `dispatchState`), Runs toolbar
  Start run gating and the `d` key in `ui/Shortcuts.qml`: card 3.3 (`d4fdb639`).
- `docs/architecture.md` and README: card 3.4 (`d3df5c9d`).
- Any store, domain or backend change: `RunStore`, `runs.js` and `board-tree.py` are done.
- Showing the root path to tell apart two projects with the same name.

## Tests

All in `tests/ui/components/tst_dispatch_dialog.qml`, a new `// ---- project step` section,
using the file's `make(over)` / `H.find` / `click` helpers and a new `SignalSpy` on
`projectChosen`. **Tier: UI component test** (qmltestrunner, offscreen, via `bash tests/run.sh`),
because the deliverable is a props-in / signals-out component: rendering, focus, key and mouse
handling are only observable on the live item, and no store or Panel is involved. The
architecture tier (`tests/architecture`, pytest) is not extended; it must stay green, which proves
no shared visual pattern was copied.

Fixture rows: `omarchy-project-manager` (open, enabled), `agent-manager` (enabled), `ori`
(enabled), `py-ai-toolkit` (disabled, reason `board unreachable: no .brd`), in that order; a
second set with a disabled row first.

1. **Rows and marks**: one `dispatchProjectRow<i>` per row in order; names verbatim; the `open`
   caption only on the open row; the reason caption only on the disabled row, with its text.
2. **Disabled rows are dimmed**: a disabled row's name colour is the theme's dim colour, an
   enabled row's the foreground.
3. **Only the project step's parts show**: at `step: "project"` the heading is
   `Dispatch · 1 Project`, Cancel is visible, and the target line, chips, form, preview heading,
   warning and Start are not; at `step: ""` the project list and empty line are not visible and
   the heading is `Dispatch` (data-driven over the hidden objectNames).
4. **Cursor starts on the first enabled row**: with the disabled row first, `projectCursor` is 1
   and row 1 has `hasCursor`.
5. **Down / Up skip disabled rows and stop at the ends**: with a disabled row between two enabled
   ones, Down jumps over it; Down on the last enabled row and Up on the first leave the cursor.
6. **Enter picks the cursor row**: Return and Enter (data-driven) emit `projectChosen` once with
   that row's root.
7. **A click on an enabled row picks it**: cursor moves, `projectChosen(root)` once.
8. **A disabled row ignores click and hover**: no `projectChosen`, cursor unchanged.
9. **Hover moves the cursor over enabled rows.**
10. **Empty registry**: `projectRows: []`, and null / undefined / `{}` / `"x"` (data-driven), show
    `No projects registered`, no row, Cancel only, `projectCursor` `-1`, Enter emits nothing.
11. **Every board unreachable**: all rows disabled show `No project's board can be read`, the rows
    with their reasons, Cancel only, `projectCursor` `-1`, Enter emits nothing.
12. **Escape cancels**: Escape on `focusItem` emits `cancelRequested` once; Cancel and the
    backdrop click each emit it once.
13. **Focus**: at the project step `focusItem` is `dispatchProjectKeys`; at `step: ""` it is still
    `dispatchBase` with a form and `dispatchCancel` without one.
14. **Rows change under the cursor**: moving the cursor to `ori`, then replacing `projectRows`
    with a reordered list keeps the cursor on `ori`; replacing it with `ori` disabled moves the
    cursor to the first enabled row; leaving and re-entering the step resets it to the first
    enabled row.
15. **A long list keeps the cursor in view**: 30 enabled rows, Down to the last; the list's
    `contentY` is greater than 0 and the last row lies inside the visible area.
16. **Other keys pass through**: a letter key on `focusItem` is not accepted and emits nothing.
17. **Teardown at the project step is quiet**: null every object prop and destroy, no warning.
18. Every existing test in the file passes unchanged.

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `ui/components/DispatchDialog.qml` | modify | New props `step`, `projectRows`; `atProject` hides the form step's parts; the project list, empty line, cursor, key item and mouse handling. |
| `tests/ui/components/tst_dispatch_dialog.qml` | modify | A `picks` spy in `make()`, and a new `// ---- the project step` section at the end of the file. |

### How to run tests

`bash tests/run.sh tst_dispatch_dialog` — runs the whole pytest suite (architecture tier included), then only `tests/ui/components/tst_dispatch_dialog.qml`. A failing QML test prints a line starting `FAIL!  : DispatchDialog::<test>(<tag>)` followed by a `   Loc:` line; the last line is `Totals: N passed, M failed, ...`. Exit status non-zero means red. A run takes under a minute; wrap with `timeout 600` if anything hangs.

All new tests go at the end of `tests/ui/components/tst_dispatch_dialog.qml`, **before the TestCase's closing `}` (the file's last line)**, in the order the tasks add them.

---

### Task 1: The project step hides the form step and heads the card

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (header comment lines 7-14; props after line 55; `canOffer` lines 69-70; preview flags lines 91-99; signals lines 114-118; heading line 241; `dispatchTarget` 245-251; `dispatchTargetChoices` 254-264; `dispatchForm` 266-270; `dispatchPreviewHeading` 412-418; `dispatchWarning` 528-539; `dispatchConfirmNote` 541-549; `dispatchStart` 563-570)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (spies lines 17-21, `make` lines 38-45, new section at the end)

**Interfaces:**
- Consumes: nothing new.
- Produces: `property string step: ""`, `property var projectRows: []`, `readonly property bool atProject` (`step === "project"`), `signal projectChosen(string root)`. Test helpers `fixtureRows()`, `disabledFirstRows()`, `projectStep(over)` (returns a shown dialog at `step: "project"` over `fixtureRows()`, `over` replaces any prop), spy `picks` on `projectChosen`.

- [ ] **Step 1: Add the `picks` spy to the test file**

In `tests/ui/components/tst_dispatch_dialog.qml`, replace

```qml
  SignalSpy { id: offers; signalName: "suggestionRequested" }
```

with

```qml
  SignalSpy { id: offers; signalName: "suggestionRequested" }
  SignalSpy { id: picks; signalName: "projectChosen" }
```

and in `make(over)` replace

```qml
    edits.target = d; starts.target = d; cancels.target = d; chosen.target = d; offers.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear()
```

with

```qml
    edits.target = d; starts.target = d; cancels.target = d; chosen.target = d; offers.target = d
    picks.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear(); picks.clear()
```

- [ ] **Step 2: Write the failing tests**

Append before the TestCase's closing `}`:

```qml

  // ---- the project step -------------------------------------------------

  // RunStore's dispatchProjectRows: the open project first, then by name; one
  // board unreadable.
  function fixtureRows() {
    return [
      { root: "/home/u/Code/omarchy-project-manager", name: "omarchy-project-manager", open: true,
        enabled: true, reason: "" },
      { root: "/home/u/Code/agent-manager", name: "agent-manager", open: false, enabled: true, reason: "" },
      { root: "/home/u/Code/ori", name: "ori", open: false, enabled: true, reason: "" },
      { root: "/home/u/Code/py-ai-toolkit", name: "py-ai-toolkit", open: false, enabled: false,
        reason: "board unreachable: no .brd" }
    ]
  }

  // A disabled row first, and one between two enabled rows.
  function disabledFirstRows() {
    return [
      { root: "/r/a", name: "a", open: false, enabled: false, reason: "board unreachable: no .brd" },
      { root: "/r/b", name: "b", open: false, enabled: true, reason: "" },
      { root: "/r/c", name: "c", open: false, enabled: false, reason: "board unreachable: tree read failed" },
      { root: "/r/d", name: "d", open: false, enabled: true, reason: "" }
    ]
  }

  // The dialog at the project step over fixtureRows(); `over` replaces any prop.
  function projectStep(over) {
    return make(Object.assign({ step: "project", projectRows: tc.fixtureRows() }, over || {}))
  }

  // 3: each part shows at the form step, hides at the project step, and comes
  // back when the step leaves.
  function test_the_project_step_hides_the_form_steps_parts_data() {
    var refused = storyRefusal()
    var failed = { dispatchState: "failed", error: "am exited before the run appeared", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "Traceback" }
    var sub = { target: { level: "subtask", offered: true }, targetTitle: "Do it", preview: null,
                storyTitle: "Control store", blockedText: "Blocked by 3.1 RunStore dispatch (done)" }
    return [
      { tag: "target", name: "dispatchTarget", over: {} },
      { tag: "target-choices", name: "dispatchTargetChoices",
        over: { targetChoices: tc.boardChoices, targetChoice: "board" } },
      { tag: "form", name: "dispatchForm", over: {} },
      { tag: "preview-heading", name: "dispatchPreviewHeading", over: {} },
      { tag: "refusal", name: "dispatchRefusal", over: refused },
      { tag: "suggest", name: "dispatchSuggest", over: refused },
      { tag: "exit-code", name: "dispatchExitCode", over: failed },
      { tag: "log-path", name: "dispatchLogPath", over: failed },
      { tag: "log-tail", name: "dispatchLogTail", over: failed },
      { tag: "subtask-note", name: "dispatchSubtaskNote", over: sub },
      { tag: "story", name: "dispatchStory", over: sub },
      { tag: "blocked", name: "dispatchBlocked", over: sub },
      { tag: "checking", name: "dispatchChecking", over: { dispatchState: "previewing", preview: null } },
      { tag: "summary", name: "dispatchSummary", over: {} },
      { tag: "integrate", name: "dispatchIntegrate", over: {} },
      { tag: "warning", name: "dispatchWarning", over: {} },
      { tag: "confirm-note", name: "dispatchConfirmNote", over: subtask(), arm: true },
      { tag: "start", name: "dispatchStart", over: {} }
    ]
  }

  function test_the_project_step_hides_the_form_steps_parts(data) {
    var d = make(data.over)
    if (data.arm) click(H.find(d, "dispatchStart"))
    verify(H.find(d, data.name).visible, "shown at the form step")
    d.step = "project"
    verify(!H.find(d, data.name).visible, "hidden at the project step")
    d.step = ""
    verify(H.find(d, data.name).visible, "shown again once the step leaves")
  }

  // 3
  function test_the_project_step_heads_the_card_and_keeps_only_cancel() {
    var d = projectStep()
    var heading = H.find(d, "dispatchHeading")
    compare(heading.text, "Dispatch · 1 Project")
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
    d.step = ""
    compare(heading.text, "Dispatch")
    d.step = "target"
    compare(heading.text, "Dispatch")
    compare(picks.count, 0)
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL. The dialog has no `step` yet, so `test_the_project_step_hides_the_form_steps_parts(<every tag>)` fails at `d.step = "project"` (a `non-existent property` error, or the part stays visible), and `test_the_project_step_heads_the_card_and_keeps_only_cancel` fails on the heading (`Dispatch`, not `Dispatch · 1 Project`) or on the initial `step` property. The `picks` SignalSpy may also warn that `projectChosen` does not exist. Every pre-existing test still passes.

- [ ] **Step 4: Add the props, the signal and `atProject`**

In `ui/components/DispatchDialog.qml` replace the header comment

```qml
// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does. The
// owner may pass a ready target label (targetLabel), a row of targets
// (targetChosen), a blocked story's milestone, whose action emits
// suggestionRequested(), and a Start that takes two clicks (confirmFirst).
```

with

```qml
// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does. The
// owner may pass a ready target label (targetLabel), a row of targets
// (targetChosen), a blocked story's milestone, whose action emits
// suggestionRequested(), and a Start that takes two clicks (confirmFirst).
// At step "project" it lists the projects instead (projectRows), with Cancel
// only; the owner maps projectChosen onto dispatchProjectPick.
```

Replace

```qml
  property bool confirmFirst: false
  readonly property bool armed: arming.armed
```

with

```qml
  property bool confirmFirst: false
  readonly property bool armed: arming.armed
  // RunStore's dispatchStep. "project" shows the project list in place of the
  // target line, the form, the preview, the warning and Start; any other value
  // shows those.
  property string step: ""
  // RunStore's dispatchProjectRows, [{root, name, open, enabled, reason}];
  // anything not array-like reads as [].
  property var projectRows: []
  readonly property bool atProject: dialog.step === "project"
```

Replace

```qml
  readonly property bool canOffer: dialog.dispatchState === "refused" && !!dialog.suggestion
    && typeof dialog.suggestion.id === "string" && dialog.suggestion.id !== ""
```

with

```qml
  readonly property bool canOffer: !dialog.atProject && dialog.dispatchState === "refused" && !!dialog.suggestion
    && typeof dialog.suggestion.id === "string" && dialog.suggestion.id !== ""
```

Replace

```qml
  // The preview area shows exactly one of these, checked in this order.
  readonly property bool showRefusal: dialog.dispatchState === "refused" || dialog.dispatchState === "failed"
  readonly property bool showSubtask: !dialog.showRefusal && dialog.targetLevel === "subtask"
  readonly property bool showChecking: !dialog.showRefusal && !dialog.showSubtask
    && dialog.dispatchState === "previewing"
  readonly property bool showSummary: !dialog.showRefusal && !dialog.showSubtask
    && ["ready", "starting", "started"].indexOf(dialog.dispatchState) >= 0
  // A failed launch adds its exit code, log path and tail under the sentence.
  readonly property bool showLaunch: dialog.dispatchState === "failed"
```

with

```qml
  // The preview area shows exactly one of these, checked in this order; the
  // project step shows none.
  readonly property bool showRefusal: !dialog.atProject
    && (dialog.dispatchState === "refused" || dialog.dispatchState === "failed")
  readonly property bool showSubtask: !dialog.atProject && !dialog.showRefusal && dialog.targetLevel === "subtask"
  readonly property bool showChecking: !dialog.atProject && !dialog.showRefusal && !dialog.showSubtask
    && dialog.dispatchState === "previewing"
  readonly property bool showSummary: !dialog.atProject && !dialog.showRefusal && !dialog.showSubtask
    && ["ready", "starting", "started"].indexOf(dialog.dispatchState) >= 0
  // A failed launch adds its exit code, log path and tail under the sentence.
  readonly property bool showLaunch: dialog.showRefusal && dialog.dispatchState === "failed"
```

Replace

```qml
  signal targetChosen(string id)
  signal suggestionRequested()
```

with

```qml
  signal targetChosen(string id)
  signal suggestionRequested()
  signal projectChosen(string root)
```

- [ ] **Step 5: Gate the heading and the form step's items**

In `DispatchDialog.qml`, in the `dispatchHeading` item replace

```qml
      text: "Dispatch"
```

with

```qml
      text: dialog.atProject ? "Dispatch · 1 Project" : "Dispatch"
```

In `dispatchTarget` replace

```qml
      objectName: "dispatchTarget"
      theme: dialog.theme
      width: parent.width
```

with

```qml
      objectName: "dispatchTarget"
      theme: dialog.theme
      visible: !dialog.atProject
      width: parent.width
```

In `dispatchTargetChoices` replace

```qml
      visible: dialog.hasChoices
```

with

```qml
      visible: dialog.hasChoices && !dialog.atProject
```

In `dispatchForm` replace

```qml
      objectName: "dispatchForm"
      visible: !!dialog.form
```

with

```qml
      objectName: "dispatchForm"
      visible: !!dialog.form && !dialog.atProject
```

In `dispatchPreviewHeading` replace

```qml
      objectName: "dispatchPreviewHeading"
      variant: "caption"
      theme: dialog.theme
```

with

```qml
      objectName: "dispatchPreviewHeading"
      variant: "caption"
      theme: dialog.theme
      visible: !dialog.atProject
```

Replace the warning's comment and opening lines

```qml
    // The cost warning shows in every state, a refused target's included.
    UI.ThemedText {
      objectName: "dispatchWarning"
      variant: "small"
      theme: dialog.theme
```

with

```qml
    // The cost warning shows in every state, a refused target's included; the
    // project step has none.
    UI.ThemedText {
      objectName: "dispatchWarning"
      variant: "small"
      theme: dialog.theme
      visible: !dialog.atProject
```

In `dispatchConfirmNote` replace

```qml
      visible: arming.armed
```

with

```qml
      visible: arming.armed && !dialog.atProject
```

In `dispatchStart` replace

```qml
        objectName: "dispatchStart"
        iconText: "▶"
```

with

```qml
        objectName: "dispatchStart"
        visible: !dialog.atProject
        iconText: "▶"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: PASS — no `FAIL` line, `Totals: ... 0 failed`, pytest green, exit status 0.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the project step hides the form step and heads the card"
```

---

### Task 2: The project list and its empty states

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (a derived flag after `atProject`; four functions after `syncFields()`; the list and empty line right after the `dispatchHeading` item)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (append to the project-step section)

**Interfaces:**
- Consumes: `step`, `projectRows`, `atProject` (Task 1); test helpers `fixtureRows()`, `projectStep(over)`, spy `picks` (Task 1).
- Produces:
  - `function projectList()` → JS array (`[]` for anything not array-like).
  - `function projectText(row, key)` → string (`""` for a missing row or a non-string value).
  - `function rowEnabled(row)` → bool (`!!row && row.enabled === true`).
  - `function nextEnabledProject(from, by)` → int: the first enabled index from `from` stepping `by` (1 or -1), `-1` for none.
  - `readonly property bool hasEnabledProject`.
  - Items `projectFlick` (objectName `dispatchProjectList`, the `Flickable`), `projectColumn`, `projectRepeater`, delegate `UI.ListRow` id `projectRow` with `readonly property bool usable`, and `dispatchProjectEmpty`.

- [ ] **Step 1: Write the failing tests**

Append to the project-step section:

```qml

  // 1
  function test_the_project_step_lists_each_project_with_its_marks() {
    var d = projectStep()
    var rows = tc.fixtureRows()
    verify(H.find(d, "dispatchProjectList").visible, "the list")
    for (var i = 0; i < rows.length; i++) {
      verify(H.find(d, "dispatchProjectRow" + i), "row " + i)
      compare(H.find(d, "dispatchProjectName" + i).text, rows[i].name)
      compare(H.find(d, "dispatchProjectOpen" + i).visible, i === 0, "open mark on row " + i)
      compare(H.find(d, "dispatchProjectReason" + i).visible, i === 3, "reason on row " + i)
    }
    compare(H.find(d, "dispatchProjectRow4"), null)
    compare(H.find(d, "dispatchProjectOpen0").text, "open")
    compare(H.find(d, "dispatchProjectReason3").text, "board unreachable: no .brd")
    verify(!H.find(d, "dispatchProjectEmpty").visible, "no empty line")
  }

  // 2
  function test_a_disabled_rows_name_is_dimmed() {
    var d = projectStep()
    compare(H.find(d, "dispatchProjectName3").color, d.theme.dim)
    compare(H.find(d, "dispatchProjectName0").color, d.theme.foreground)
    compare(H.find(d, "dispatchProjectName2").color, d.theme.foreground)
  }

  // 3
  function test_the_list_and_the_empty_line_show_only_at_the_project_step_data() {
    return [{ tag: "none", step: "" }, { tag: "target", step: "target" }, { tag: "other", step: "whatever" }]
  }

  function test_the_list_and_the_empty_line_show_only_at_the_project_step(data) {
    var full = make({ step: data.step, projectRows: tc.fixtureRows() })
    verify(!H.find(full, "dispatchProjectList").visible, "no list")
    compare(H.find(full, "dispatchProjectRow0"), null)
    var empty = make({ step: data.step, projectRows: [] })
    verify(!H.find(empty, "dispatchProjectEmpty").visible, "no empty line")
  }

  // 10
  function test_an_empty_or_malformed_registry_says_no_projects_data() {
    return [
      { tag: "empty", rows: [] },
      { tag: "null", rows: null },
      { tag: "undefined", rows: undefined },
      { tag: "object", rows: {} },
      { tag: "string", rows: "x" }
    ]
  }

  function test_an_empty_or_malformed_registry_says_no_projects(data) {
    var d = projectStep({ projectRows: data.rows })
    var empty = H.find(d, "dispatchProjectEmpty")
    verify(empty.visible, "the empty line")
    compare(empty.text, "No projects registered")
    compare(H.find(d, "dispatchProjectRow0"), null)
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
  }

  // 11
  function test_every_board_unreachable_lists_the_rows_with_their_reasons() {
    var rows = tc.fixtureRows()
    for (var i = 0; i < rows.length; i++) {
      rows[i].enabled = false
      rows[i].reason = "board unreachable: " + rows[i].name
    }
    var d = projectStep({ projectRows: rows })
    var empty = H.find(d, "dispatchProjectEmpty")
    verify(empty.visible, "the empty line")
    compare(empty.text, "No project's board can be read")
    for (var j = 0; j < rows.length; j++) {
      verify(H.find(d, "dispatchProjectRow" + j), "row " + j)
      var reason = H.find(d, "dispatchProjectReason" + j)
      verify(reason.visible, "reason " + j)
      compare(reason.text, "board unreachable: " + rows[j].name)
      compare(H.find(d, "dispatchProjectName" + j).color, d.theme.dim)
    }
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
  }

  // Review Focus 3
  function test_a_malformed_row_reads_as_empty_and_disabled() {
    var d = projectStep({ projectRows: [
      { root: "/r/a", name: null, open: "yes", enabled: true },
      { root: "/r/b", name: "b", enabled: "yes", reason: 7 },
      null
    ] })
    compare(H.find(d, "dispatchProjectName0").text, "")
    verify(!H.find(d, "dispatchProjectOpen0").visible, "open only when exactly true")
    verify(!H.find(d, "dispatchProjectReason0").visible, "row 0 is enabled")
    compare(H.find(d, "dispatchProjectName1").text, "b")
    verify(H.find(d, "dispatchProjectReason1").visible, "enabled that is not true is disabled")
    compare(H.find(d, "dispatchProjectReason1").text, "")
    compare(H.find(d, "dispatchProjectName1").color, d.theme.dim)
    verify(H.find(d, "dispatchProjectRow2"), "a null row is still a row")
    compare(H.find(d, "dispatchProjectName2").text, "")
    verify(!H.find(d, "dispatchProjectEmpty").visible, "row 0 is enabled")
  }

  // Review Focus 4
  function test_a_long_project_name_elides_on_one_line() {
    var long = new Array(30).join("a-very-long-project-name-")
    var d = projectStep({ projectRows: [{ root: "/r/l", name: long, open: true, enabled: true, reason: "" }] })
    var name = H.find(d, "dispatchProjectName0")
    compare(name.text, long)
    compare(name.elide, Text.ElideRight)
    verify(name.truncated, "the name is cut, not wrapped")
    compare(name.lineCount, 1)
    verify(H.find(d, "dispatchProjectOpen0").visible, "the open mark stays")
  }

  // 17
  function test_nulling_every_object_prop_at_the_project_step_and_destroying_is_quiet() {
    var d = projectStep()
    d.theme = null
    d.target = null
    d.form = null
    d.preview = null
    d.projectRows = null
    wait(0)
    compare(H.find(d, "dispatchProjectEmpty").text, "No projects registered")
    compare(picks.count, 0)
    d.destroy()
    wait(0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — every new test fails on `H.find(...)` returning `null` (`TypeError: Cannot read property 'visible' of null` / `'text' of null`), since no `dispatchProjectList`, `dispatchProjectRow<i>` or `dispatchProjectEmpty` exists yet. Task 1's tests and every older test still pass.

- [ ] **Step 3: Add the row helpers and `hasEnabledProject`**

In `DispatchDialog.qml` replace

```qml
  readonly property bool atProject: dialog.step === "project"
```

with

```qml
  readonly property bool atProject: dialog.step === "project"
  readonly property bool hasEnabledProject: dialog.nextEnabledProject(0, 1) >= 0
```

Then, right after the closing `}` of `function syncFields()` (and before `UI.ModalCard {`), add:

```qml

  // The project rows: a list, or the array-like a list arrives as through
  // createObject; anything else (null, an object, a string) reads as [].
  function projectList() {
    var rows = dialog.projectRows
    if (!rows || typeof rows !== "object" || typeof rows.length !== "number") return []
    return Array.prototype.slice.call(rows)
  }

  // A row's text field; a missing row or a non-string value reads as "".
  function projectText(row, key) {
    return row && typeof row[key] === "string" ? row[key] : ""
  }

  // Only a row whose enabled is exactly true takes the cursor or a pick.
  function rowEnabled(row) {
    return !!row && row.enabled === true
  }

  // The first enabled row from `from` on, stepping by `by` (1 or -1); -1 for none.
  function nextEnabledProject(from, by) {
    var rows = dialog.projectList()
    for (var i = from; i >= 0 && i < rows.length; i += by)
      if (dialog.rowEnabled(rows[i])) return i
    return -1
  }
```

- [ ] **Step 4: Add the list and the empty line**

In `DispatchDialog.qml`, right after the `dispatchHeading` item — i.e. replace

```qml
      text: dialog.atProject ? "Dispatch · 1 Project" : "Dispatch"
      font.bold: true
    }
```

with

```qml
      text: dialog.atProject ? "Dispatch · 1 Project" : "Dispatch"
      font.bold: true
    }

    // The project step's rows, in the owner's order.
    Flickable {
      id: projectFlick
      objectName: "dispatchProjectList"
      visible: dialog.atProject
      width: parent.width
      height: Math.min(projectColumn.implicitHeight, Style.space(240))
      contentHeight: projectColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: projectColumn
        width: projectFlick.width
        spacing: Style.space(2)

        Repeater {
          id: projectRepeater
          model: dialog.atProject ? dialog.projectList() : []

          UI.ListRow {
            id: projectRow
            required property var modelData
            required index
            readonly property bool usable: dialog.rowEnabled(projectRow.modelData)
            objectName: "dispatchProjectRow" + projectRow.index
            width: projectColumn.width
            theme: dialog.theme

            Row {
              width: parent.width
              spacing: Style.space(8)

              UI.ThemedText {
                objectName: "dispatchProjectName" + projectRow.index
                theme: dialog.theme
                width: Math.max(0, parent.width - (openMark.visible ? openMark.width + parent.spacing : 0))
                text: dialog.projectText(projectRow.modelData, "name")
                color: projectRow.usable ? dialog.foregroundColor : dialog.dimColor
                elide: Text.ElideRight
              }

              UI.ThemedText {
                id: openMark
                objectName: "dispatchProjectOpen" + projectRow.index
                variant: "caption"
                theme: dialog.theme
                visible: !!projectRow.modelData && projectRow.modelData.open === true
                text: "open"
              }
            }

            UI.ThemedText {
              objectName: "dispatchProjectReason" + projectRow.index
              variant: "caption"
              theme: dialog.theme
              visible: !projectRow.usable
              width: parent.width
              text: dialog.projectText(projectRow.modelData, "reason")
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    UI.ThemedText {
      objectName: "dispatchProjectEmpty"
      theme: dialog.theme
      visible: dialog.atProject && !dialog.hasEnabledProject
      width: parent.width
      text: dialog.projectList().length === 0 ? "No projects registered" : "No project's board can be read"
      wrapMode: Text.WordWrap
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: PASS — no `FAIL` line, no `TypeError`/`ReferenceError` line, `Totals: ... 0 failed`, pytest (architecture tier) green, exit status 0.

- [ ] **Step 6: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the project step lists the projects and its two empty states"
```

---

### Task 3: The cursor, its keys and the focus

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (`focusItem` line 57; a `projectCursor` prop; the change handlers lines 120-127; a `QtObject` after `arming`; five functions after `nextEnabledProject`; a key item before `UI.ModalCard`; `cursorIndex` on the row; a `reveal` function in the `Flickable`)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (append to the project-step section)

**Interfaces:**
- Consumes: `projectList()`, `projectText(row, key)`, `rowEnabled(row)`, `nextEnabledProject(from, by)`, `projectFlick`, `projectRepeater`, `projectRow` (Task 2); `cancel()`, `busy` (existing); helpers `fixtureRows()`, `disabledFirstRows()`, `projectStep(over)`, spies `picks`, `cancels` (Task 1).
- Produces:
  - `readonly property int projectCursor` (row index, `-1` with no enabled row or outside the project step).
  - `function setProjectCursor(index)` — onto an enabled row, `-1` takes it off, a disabled/out-of-range index is ignored.
  - `function resetProjectCursor()`, `function followProjectCursor()`, `function moveProjectCursor(by)`.
  - `function pickProject(index)` — at the project step and for an enabled row only: cursor there, then `projectChosen(root)`.
  - `function projectKey(event)`.
  - Item `projectKeys` (objectName `dispatchProjectKeys`), `focusItem` at the project step.
  - `projectFlick.reveal(item)`.

- [ ] **Step 1: Write the failing tests**

Append to the project-step section:

```qml

  // A dialog inside an owner that counts the keys the dialog leaves to it.
  Component {
    id: hostC
    Item {
      id: host
      property alias dialog: hosted
      property int passed: 0
      width: 640; height: 700
      Keys.onPressed: function(event) { host.passed++ }
      UI.DispatchDialog { id: hosted; width: 640; height: 700 }
    }
  }

  // 4
  function test_the_cursor_starts_on_the_first_enabled_row() {
    var d = projectStep({ projectRows: tc.disabledFirstRows() })
    compare(d.projectCursor, 1)
    verify(H.find(d, "dispatchProjectRow1").hasCursor, "row 1 is highlighted")
    verify(!H.find(d, "dispatchProjectRow0").hasCursor, "the disabled row never is")
    compare(projectStep().projectCursor, 0)
    compare(make().projectCursor, -1, "no cursor outside the project step")
  }

  // 5
  function test_down_and_up_skip_disabled_rows_and_stop_at_the_ends() {
    var d = projectStep({ projectRows: tc.disabledFirstRows() })
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Up)
    compare(d.projectCursor, 1, "Up on the first enabled row stays")
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 3, "Down jumps over the disabled row")
    verify(H.find(d, "dispatchProjectRow3").hasCursor)
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 3, "Down on the last enabled row stays")
    keyClick(Qt.Key_Up)
    compare(d.projectCursor, 1)
    compare(picks.count, 0)
  }

  // 6
  function test_enter_picks_the_cursor_row_data() {
    return [{ tag: "return", key: Qt.Key_Return }, { tag: "enter", key: Qt.Key_Enter }]
  }

  function test_enter_picks_the_cursor_row(data) {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(data.key)
    compare(picks.count, 1)
    compare(picks.signalArguments[0][0], "/home/u/Code/agent-manager")
    compare(cancels.count, 0)
    compare(starts.count, 0)
  }

  // 10, 11
  function test_without_an_enabled_row_there_is_no_cursor_and_enter_picks_nothing_data() {
    var off = tc.fixtureRows()
    for (var i = 0; i < off.length; i++) off[i].enabled = false
    return [
      { tag: "empty", rows: [] },
      { tag: "null", rows: null },
      { tag: "undefined", rows: undefined },
      { tag: "object", rows: {} },
      { tag: "string", rows: "x" },
      { tag: "all-disabled", rows: off }
    ]
  }

  function test_without_an_enabled_row_there_is_no_cursor_and_enter_picks_nothing(data) {
    var d = projectStep({ projectRows: data.rows })
    compare(d.projectCursor, -1)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(d.projectCursor, -1)
    compare(picks.count, 0)
  }

  // 12
  function test_escape_cancel_and_the_backdrop_cancel_the_project_step() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    click(H.find(d, "dispatchCancel"))
    compare(cancels.count, 2)
    mouseClick(H.find(d, "dispatchBackdrop"), 2, 2)
    compare(cancels.count, 3)
    mouseClick(H.find(d, "dispatchCard"), 3, 3)
    compare(cancels.count, 3, "the card itself does nothing")
    compare(picks.count, 0)
  }

  // Review Focus 5
  function test_escape_at_the_project_step_does_nothing_while_starting() {
    var d = projectStep({ dispatchState: "starting" })
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 0)
    compare(picks.count, 0)
  }

  // 13
  function test_the_project_step_focuses_its_key_item() {
    var d = projectStep()
    compare(d.focusItem, H.find(d, "dispatchProjectKeys"))
    d.step = ""
    compare(d.focusItem, H.find(d, "dispatchBase"))
    d.form = null
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  // 14
  function test_the_cursor_follows_its_root_when_the_rows_change() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 2, "on ori")
    var rows = tc.fixtureRows()
    d.projectRows = [rows[3], rows[2], rows[0], rows[1]]
    compare(d.projectCursor, 1, "still on ori")
    verify(H.find(d, "dispatchProjectRow1").hasCursor)
    var off = tc.fixtureRows()
    off[2].enabled = false
    off[2].reason = "board unreachable: tree read failed"
    d.projectRows = off
    compare(d.projectCursor, 0, "ori disabled: the first enabled row")
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 1)
    d.step = ""
    compare(d.projectCursor, -1)
    d.step = "project"
    compare(d.projectCursor, 0, "a new project step starts over")
    compare(picks.count, 0)
  }

  // Review Focus 2
  function test_rows_shrinking_past_the_cursor_put_it_on_the_first_enabled_row() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 2)
    d.projectRows = [tc.fixtureRows()[1]]
    compare(d.projectCursor, 0)
    d.projectRows = [tc.fixtureRows()[3]]
    compare(d.projectCursor, -1, "the only row left is disabled")
    compare(H.find(d, "dispatchProjectEmpty").text, "No project's board can be read")
  }

  // 15
  function test_a_long_list_keeps_the_cursor_in_view() {
    var rows = []
    for (var i = 0; i < 30; i++)
      rows.push({ root: "/r/p" + i, name: "project " + i, open: false, enabled: true, reason: "" })
    var d = projectStep({ projectRows: rows })
    var list = H.find(d, "dispatchProjectList")
    verify(list.contentHeight > list.height, "the list scrolls")
    compare(list.contentY, 0)
    d.focusItem.forceActiveFocus()
    for (var k = 0; k < 29; k++) keyClick(Qt.Key_Down)
    compare(d.projectCursor, 29)
    var last = H.find(d, "dispatchProjectRow29")
    verify(list.contentY > 0, "the list scrolled")
    verify(last.y >= list.contentY, "the last row's top is in view")
    verify(last.y + last.height <= list.contentY + list.height + 0.5, "the last row's bottom is in view")
  }

  // 16
  function test_other_keys_pass_through_to_the_owner() {
    var host = createTemporaryObject(hostC, tc)
    var d = host.dialog
    picks.target = d; cancels.target = d
    picks.clear(); cancels.clear()
    d.step = "project"
    d.projectRows = tc.fixtureRows()
    d.shown = true
    wait(30)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_A)
    compare(host.passed, 1, "a letter is not accepted")
    keyClick(Qt.Key_Down)
    compare(host.passed, 1, "Down is accepted")
    compare(d.projectCursor, 1)
    compare(picks.count, 0)
    compare(cancels.count, 0)
  }

  // Review Focus 1
  function test_enter_after_leaving_the_project_step_picks_nothing() {
    var d = projectStep()
    H.find(d, "dispatchProjectKeys").forceActiveFocus()
    d.step = "target"
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(picks.count, 0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — the cursor tests fail on `compare(d.projectCursor, …)` (`projectCursor` is `undefined`), the key tests on `d.focusItem` not being `dispatchProjectKeys` / Escape not cancelling, `test_the_project_step_focuses_its_key_item` on `H.find(d, "dispatchProjectKeys")` being `null`, `test_a_long_list_keeps_the_cursor_in_view` on `projectCursor`. Tasks 1–2 and older tests still pass. `test_enter_after_leaving_the_project_step_picks_nothing` fails because `H.find(d, "dispatchProjectKeys")` is `null`.

- [ ] **Step 3: Add the cursor state, `projectCursor` and the new `focusItem`**

In `DispatchDialog.qml` replace

```qml
  readonly property Item focusItem: dialog.form ? baseField : cancelButton
```

with

```qml
  readonly property Item focusItem: dialog.atProject ? projectKeys : dialog.form ? baseField : cancelButton
  // The project step's cursor: a row index in projectRows, never a disabled
  // row; -1 with no enabled row and at every other step.
  readonly property int projectCursor: projectCursorState.index
```

Replace

```qml
  onShownChanged: { arming.armed = false; dialog.syncFields() }
  onFormChanged: { arming.armed = false; dialog.syncFields() }
  onDispatchStateChanged: arming.armed = false
  onTargetChanged: arming.armed = false
  onConfirmFirstChanged: arming.armed = false
  Component.onCompleted: dialog.syncFields()

  QtObject {
    id: arming
    property bool armed: false
  }
```

with

```qml
  onShownChanged: { arming.armed = false; dialog.syncFields(); dialog.resetProjectCursor() }
  onFormChanged: { arming.armed = false; dialog.syncFields() }
  onDispatchStateChanged: arming.armed = false
  onTargetChanged: arming.armed = false
  onConfirmFirstChanged: arming.armed = false
  onStepChanged: dialog.resetProjectCursor()
  onProjectRowsChanged: dialog.followProjectCursor()
  Component.onCompleted: { dialog.syncFields(); dialog.resetProjectCursor() }

  QtObject {
    id: arming
    property bool armed: false
  }

  // The cursor's row and its root, so new rows keep it on the same project.
  QtObject {
    id: projectCursorState
    property int index: -1
    property string root: ""
  }
```

- [ ] **Step 4: Add the cursor and key functions**

Right after the closing `}` of `function nextEnabledProject(from, by)` add:

```qml

  // The cursor onto an enabled row, or off with -1; any other index is ignored.
  function setProjectCursor(index) {
    if (index !== -1 && !dialog.rowEnabled(dialog.projectList()[index])) return
    projectCursorState.index = index
    projectCursorState.root = index === -1 ? "" : dialog.projectText(dialog.projectList()[index], "root")
  }

  // The project step starts on the first enabled row; any other step has no cursor.
  function resetProjectCursor() {
    dialog.setProjectCursor(dialog.atProject ? dialog.nextEnabledProject(0, 1) : -1)
  }

  // New rows keep the cursor on its root while that root has an enabled row.
  function followProjectCursor() {
    var rows = dialog.projectList()
    if (dialog.atProject && projectCursorState.index !== -1) {
      for (var i = 0; i < rows.length; i++) {
        if (dialog.rowEnabled(rows[i]) && dialog.projectText(rows[i], "root") === projectCursorState.root) {
          dialog.setProjectCursor(i)
          return
        }
      }
    }
    dialog.resetProjectCursor()
  }

  // Down (1) / Up (-1): the next enabled row that way, scrolled into view; the
  // cursor stays at either end.
  function moveProjectCursor(by) {
    if (projectCursorState.index === -1) return
    var next = dialog.nextEnabledProject(projectCursorState.index + by, by)
    if (next === -1) return
    dialog.setProjectCursor(next)
    projectFlick.reveal(projectRepeater.itemAt(next))
  }

  // A pick: at the project step and on an enabled row only.
  function pickProject(index) {
    if (!dialog.atProject || !dialog.rowEnabled(dialog.projectList()[index])) return
    dialog.setProjectCursor(index)
    dialog.projectChosen(dialog.projectText(dialog.projectList()[index], "root"))
  }

  // Down / Up move the cursor, Return / Enter pick its row, Escape cancels;
  // any other key is left to the owner.
  function projectKey(event) {
    if (event.key === Qt.Key_Escape) dialog.cancel()
    else if (!dialog.atProject) return
    else if (event.key === Qt.Key_Down) dialog.moveProjectCursor(1)
    else if (event.key === Qt.Key_Up) dialog.moveProjectCursor(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dialog.pickProject(projectCursorState.index)
    else return
    event.accepted = true
  }
```

- [ ] **Step 5: Add the key item, the row highlight and the reveal**

Right before `  UI.ModalCard {` add:

```qml
  // The project step's keys: focusItem at that step.
  Item {
    id: projectKeys
    objectName: "dispatchProjectKeys"
    Keys.onPressed: function(event) { dialog.projectKey(event) }
  }

```

In the `Flickable` replace

```qml
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: projectColumn
```

with

```qml
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      // Scrolls the least that shows the whole of `item`.
      function reveal(item) {
        if (!item) return
        if (item.y < projectFlick.contentY) projectFlick.contentY = item.y
        else if (item.y + item.height > projectFlick.contentY + projectFlick.height)
          projectFlick.contentY = item.y + item.height - projectFlick.height
      }

      Column {
        id: projectColumn
```

In the row delegate replace

```qml
            objectName: "dispatchProjectRow" + projectRow.index
            width: projectColumn.width
            theme: dialog.theme
```

with

```qml
            objectName: "dispatchProjectRow" + projectRow.index
            width: projectColumn.width
            theme: dialog.theme
            cursorIndex: dialog.projectCursor
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: PASS — no `FAIL` line, no `TypeError`/`ReferenceError` line, `Totals: ... 0 failed`, exit status 0.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the project step's cursor, keys and focus"
```

---

### Task 4: Click and hover on the project rows

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (one function after `pickProject`; three lines on the row delegate)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (append to the project-step section)

**Interfaces:**
- Consumes: `setProjectCursor(index)`, `pickProject(index)`, `projectCursor`, `atProject`, `projectRow.usable` (Tasks 2–3); `ListRow`'s `hovered(int index)`, `activated()`, `hoverCursorShape` (`ui/components/ListRow.qml:23,34-35`); test helpers `projectStep(over)`, `click(item)`, spies `picks`, `cancels`.
- Produces: `function hoverProject(index)`.

- [ ] **Step 1: Write the failing tests**

Append to the project-step section:

```qml

  // 7
  function test_a_click_on_an_enabled_row_picks_it() {
    var d = projectStep()
    click(H.find(d, "dispatchProjectRow2"))
    compare(d.projectCursor, 2)
    compare(picks.count, 1)
    compare(picks.signalArguments[0][0], "/home/u/Code/ori")
    compare(cancels.count, 0)
  }

  // 8
  function test_a_disabled_row_ignores_hover_and_click() {
    var d = projectStep()
    var row = H.find(d, "dispatchProjectRow3")
    wait(30)
    mouseMove(row, row.width / 2, row.height / 2)
    wait(30)
    compare(d.projectCursor, 0)
    click(row)
    compare(d.projectCursor, 0)
    compare(picks.count, 0)
    compare(cancels.count, 0)
    compare(row.hoverCursorShape, Qt.ArrowCursor)
  }

  // 9
  function test_hovering_an_enabled_row_moves_the_cursor() {
    var d = projectStep()
    var row = H.find(d, "dispatchProjectRow2")
    wait(30)
    mouseMove(row, row.width / 2, row.height / 2)
    tryCompare(d, "projectCursor", 2)
    verify(row.hasCursor)
    compare(picks.count, 0)
    compare(row.hoverCursorShape, Qt.PointingHandCursor)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — `test_a_click_on_an_enabled_row_picks_it` (`picks.count` 0, cursor 0), `test_hovering_an_enabled_row_moves_the_cursor` (`projectCursor` stays 0), and `test_a_disabled_row_ignores_hover_and_click` on `hoverCursorShape` (`Qt.PointingHandCursor`, ListRow's default). Everything else passes.

- [ ] **Step 3: Add `hoverProject`**

In `DispatchDialog.qml`, right after the closing `}` of `function pickProject(index)` add:

```qml

  // A hover moves the cursor onto an enabled row; a disabled row is ignored.
  function hoverProject(index) {
    if (dialog.atProject) dialog.setProjectCursor(index)
  }
```

- [ ] **Step 4: Wire the row's hover and click**

In the row delegate replace

```qml
            theme: dialog.theme
            cursorIndex: dialog.projectCursor
```

with

```qml
            theme: dialog.theme
            cursorIndex: dialog.projectCursor
            hoverCursorShape: projectRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHovered: function(index) { dialog.hoverProject(index) }
            onActivated: dialog.pickProject(projectRow.index)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_dispatch_dialog`
Expected: PASS — no `FAIL` line, `Totals: ... 0 failed`, exit status 0.

- [ ] **Step 6: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: exit status 0 — pytest (including `tests/architecture/test_layers.py::test_no_second_copy_of_shared_visual_patterns`, `test_layers_import_only_what_their_allowlist_permits` and `test_icon_glyphs.py`) passes, every `tst_*.qml` prints `Totals: ... 0 failed`, and no `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` line is printed.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): a click or hover on a project row picks or moves the cursor"
```

---

## Spec coverage

| spec item | task |
|---|---|
| `step`, `projectRows`, `projectChosen`, `projectCursor` (readonly) | 1, 3 |
| enabled only when `enabled === true`; non-string `name`/`reason` read `""`; `open` only `=== true` | 2 (`test_a_malformed_row_reads_as_empty_and_disabled`) |
| heading `Dispatch · 1 Project` / `Dispatch` | 1 |
| list: one `ListRow` per row, name / open / reason, dim colour, elide, capped height | 2 |
| cursor highlight, keep cursor row in view on keyboard moves | 3 (`hasCursor` asserts, test 15) |
| empty states with Cancel only | 2 (10, 11), 3 (cursor `-1`, Enter nothing) |
| every form-step part hidden at the project step; list and empty line hidden elsewhere | 1 (test 3), 2 |
| cursor reset on step entry / show; follows root on new rows; never on a disabled row | 3 (4, 14, shrink) |
| keys Down / Up / Return / Enter / Escape; others not accepted | 3 (5, 6, 12, 16) |
| `focusItem` per step | 3 (13) |
| mouse click / hover on enabled and disabled rows; Cancel / backdrop / card | 4 (7, 8, 9), 3 (12) |
| teardown quiet | 2 (17) |
| existing tests unchanged | every task's run (18) |
<!-- task-pipeline: validated -->
