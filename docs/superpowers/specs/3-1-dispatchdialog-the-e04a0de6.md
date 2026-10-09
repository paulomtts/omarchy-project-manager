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
