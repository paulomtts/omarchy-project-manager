# 3.2 DispatchDialog: the target step — design

Card `f377621e` (subtask of story `7fad1523` "Dispatch from Runs UI"), after card 3.1
(`e04a0de6`, the project step). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (cited below as **P**, with line
numbers). Sibling spec this one extends: `docs/superpowers/specs/3-1-dispatchdialog-the-e04a0de6.md`
(cited as **S31**).

## Problem

The store already runs the Runs dispatch's target step (`core/stores/RunStore.qml:1866-2060`):

- `dispatchStep` is `"target"` after `dispatchProjectPick(root)`, `"form"` after
  `dispatchTargetPick(key)`, and `dispatchBack()` goes target → project and form → target
  (refused while starting).
- `dispatchTargetRows` holds `[{key, level, card, label, depth}]` from `Runs.dispatchTargets`
  (`core/domain/runs.js:1181-1213`): row 0 is always `{key: "board", level: "board", card:
  "board", label: "Whole board", depth: 0}`, then the offered milestones, stories and todo
  subtasks in tree order, `key` `"card:" + id`, `card` the brd card object (`id`, `title`,
  `status`, `depth`, …).
- `dispatchTargetLoading` is true while the tree read is in flight; the rows are `[]` meanwhile.
- `dispatchTargetKey` is the key `dispatchTargetPick` took; it is kept by Back from the form.

`ui/components/DispatchDialog.qml` renders only the project step (3.1) and S3's form. At
`step: "target"` it today shows the form area with no form. This card makes the dialog render the
target step, the Back paths, and the form step's Back.

## Goal

Given `step: "target"` and the rows, the dialog shows a filter field over the indented target list,
lets the user move a cursor with Up / Down from the filter field and pick with Enter or a click,
shows "Reading the board…" while the tree is read and "No target matches" for an empty list, and
goes back to the project step with Backspace in an empty filter or a Back button. At
`step: "form"` (a dialog opened from Runs) a Back button returns to the target step. A dialog
opened from a card (`step: ""`) shows no Back. The dialog renders and emits only
(`DispatchDialog.qml:7-16`): the owner maps the new signals onto `dispatchTargetPick(key)` and
`dispatchBack()` (that wiring is card 3.3).

## Inherited constraints

- Target list content and order come from the store; the dialog never reorders or drops a valid
  row: **P** 81-94.
- Rows indented by depth, with level labels: **P** 55-58 (flow diagram), **P** 88-89.
- A filter field at the top, the shared `FilterableList`, narrowing by title or short id; an empty
  match reads "No target matches": **P** 92-93.
- Heading `Dispatch · 2 Target in <project name>`: **P** 53.
- "Reading the board…" while the tree read is slower than the user; Back cancels it: **P** 235.
- Up / Down move the cursor and Enter picks; in step 2 the filter field has the focus and its
  arrows and Enter drive the list; Backspace in an empty filter goes back to step 1: **P** 119-121.
- Escape closes the dialog at any step: **P** 122-123.
- The form step has a Back button that returns to step 2 and keeps the picked target's row under
  the cursor: **P** 102-103, **P** 59 and 64 (the diagram's Back at steps 2 and 3).
- Built on `ModalCard`, `ListRow`, `FilterableList`, `ActionButton`; no new shared component and no
  second copy of one: **P** 221-224 and the card. `tests/architecture` (`test_layers.py`
  `test_no_second_copy_of_shared_visual_patterns` at line 298 with its `GUARDS` at line 246, the
  import allowlist at line 214, and `test_icon_glyphs.py`) stays green. In particular no
  `CursorSurface {}`, no `font.family:`, no `Qt.rgba(0, 0, 0, 0.55)`.
- Components receive props and never import stores (`docs/architecture.md` layering, line 11-14;
  `violations_screen` (`test_layers.py:144`) allows a component to import `core/domain/*.js`, e.g. `text.js`).
- Docstrings and comments state the contract only, no narrative (card; style as in
  `DispatchDialog.qml:314` "A pick: at the project step and on an enabled row only.").
- Verification: `bash tests/run.sh` green (card).

## Behaviour

### New inputs and outputs

| member | kind | default | meaning |
|---|---|---|---|
| `targetRows` | `var` property | `[]` | RunStore's `dispatchTargetRows`. Anything not array-like (null, undefined, an object, a string) reads as `[]`. |
| `targetLoading` | `bool` property | `false` | RunStore's `dispatchTargetLoading`. |
| `targetKey` | `string` property | `""` | RunStore's `dispatchTargetKey`: the row the cursor lands on when the target step is entered. |
| `projectName` | `string` property | `""` | The picked project's name, for the heading. |
| `targetCursor` | `readonly int` property | | The cursor's index in the **shown** (filtered) target rows; `-1` with no shown row, while loading, and at every other step. Not settable from outside. |
| `targetPicked(string key)` | signal | | The user picked a shown target row; once per pick, with that row's `key`. |
| `backRequested()` | signal | | The user asked to go back one step (Back button, or Backspace in an empty filter). |

`targetChosen(string id)` (the S3 target chips) is unchanged and is not used by this step.

**A valid row** is an object whose `key` is a non-empty string. Other entries of `targetRows`
give no row. Of a valid row:

- **level word**: `Milestone`, `Story` or `Subtask` for `level` `milestone` / `story` /
  `subtask`; `""` for `board` and for any other level.
- **title**: `Whole board` when `level` is `board`; otherwise `card.title` when `card` is an
  object and its `title` a string; else `""`.
- **short id**: the first 8 characters of `card.id` when `card` is an object and its `id` a
  string (the id form branch names and card references use, e.g. `f377621e`); else `""`. The
  board row has none.
- **depth**: `depth` when it is a whole number ≥ 0, else 0.

### The filter

- A single-line `TextField` (`dispatchTargetFilter`, from `qs.Ui`, the same control as
  `NewMilestoneDialog.qml:114`), full card width, placeholder `Filter by title or id…`.
- A valid row is **shown** when the trimmed, case-blind filter text is a substring of its title
  or of its short id — `Text.matchesQuery` (`core/domain/text.js:5`), so an empty or blank filter
  shows every valid row. The level word is not matched. Shown rows keep `targetRows` order.
- The filter text is cleared whenever the step becomes `"target"` (from the project step or from
  the form).

### What the target step shows

With `step === "target"`, top to bottom inside the existing `ModalCard`:

1. The heading (`dispatchHeading`): `Dispatch · 2 Target in <projectName>`, or
   `Dispatch · 2 Target` when `projectName` is `""`. The project step keeps
   `Dispatch · 1 Project` and every other step `Dispatch`.
2. The filter field (`dispatchTargetFilter`), visible also while loading.
3. The target list (`dispatchTargetList`), a vertically scrolling list capped in height (at most
   `Style.space(240)`, as the project list), holding a `UI.FilterableList` whose status line has
   `objectName` `dispatchTargetStatus`:
   - while `targetLoading`: the status reads `Reading the board…` and no row shows (whatever
     `targetRows` holds);
   - else with no shown row: the status reads `No target matches` (both the unfiltered empty and
     the filtered empty wording);
   - else: no status line, and one `UI.ListRow` per shown row, `objectName`
     `dispatchTargetRow<i>` where `i` is the index among the shown rows. Each row holds, on one
     line, indented from the row's left edge by `depth × Style.space(16)`:
     - `dispatchTargetLevel<i>`: the level word, caption, dim colour; not visible when the level
       word is `""`.
     - `dispatchTargetTitle<i>`: the title, theme foreground, elided on the right.
     - `dispatchTargetId<i>`: the short id, caption, dim colour; not visible when it is `""`.
   No status (todo etc.) is shown: every listed subtask is `todo` (**P** 89).
   The row under the cursor carries `ListRow`'s cursor highlight (`hasCursor`). The list keeps
   the cursor row scrolled into view when the cursor moves by keyboard.
4. The button row: **Back** (`dispatchBack`), then **Cancel** (`dispatchCancel`). Start
   (`dispatchStart`) is not visible.

Not visible at the target step: the project list and project empty line (3.1), and everything
**S31** hides at the project step — the target line (`dispatchTarget`), the target chips
(`dispatchTargetChoices`), the form (`dispatchForm`), the preview heading and every preview-area
line (`dispatchPreviewHeading`, `dispatchRefusal`, `dispatchSuggest`, `dispatchExitCode`,
`dispatchLogPath`, `dispatchLogTail`, `dispatchSubtaskNote`, `dispatchStory`, `dispatchBlocked`,
`dispatchChecking`, `dispatchSummary`, `dispatchIntegrate`), the cost warning (`dispatchWarning`)
and the confirm note (`dispatchConfirmNote`). The filter field and the target list are not visible
at any other step.

### The cursor

- When the step becomes `"target"`, and when the dialog is shown at that step: the filter is
  cleared, and the cursor goes to the shown row whose key is `targetKey` if there is one, else
  to shown row 0, else `-1`.
- When `targetRows`, `targetLoading` or the filter text changes at the target step: the cursor
  stays on the same key if that key is still shown; else it goes to the row whose key is
  `targetKey` if shown; else to shown row 0; else `-1`. While loading it is `-1`.
- When `targetKey` changes at the target step, the cursor goes to that row if it is shown;
  otherwise it stays.
- At every step other than `"target"` the cursor is `-1`.

### Keys (target step, on the filter field)

The filter field is the dialog's `focusItem` at the target step. At the project step `focusItem`
stays `dispatchProjectKeys`; at every other step it is unchanged (`form ? baseField : cancelButton`,
`DispatchDialog.qml:68`). Giving that item active focus when the step changes is the owner's job
(`Panel.focusItem`, card 3.3).

| key | effect | accepted |
|---|---|---|
| Down | cursor to the next shown row; stays on the last (no wrap) | yes |
| Up | cursor to the previous shown row; stays on the first (no wrap) | yes |
| Return / Enter | `targetPicked(key)` for the cursor row; nothing when the cursor is `-1` (loading, no match) | yes |
| Backspace with the filter text `""` | `backRequested()` once | yes |
| Backspace with filter text | deletes as a text field does; no signal | — |
| Escape | `cancel()`, so `cancelRequested()` unless `busy` | yes |
| any other key | typed into the filter as a text field does | — |

### Mouse (target step)

- A click on a shown row moves the cursor there and emits `targetPicked(key)` once.
- Hovering a shown row moves the cursor there.
- **Back** emits `backRequested()` once per click.
- Cancel and the backdrop emit `cancelRequested()` through `cancel()`, as today.

### The form step's Back

- With `step === "form"` (a dialog opened from Runs) the button row is **Back**
  (`dispatchBack`), **Cancel**, **Start run**; everything else at the form step renders exactly as
  at `step: ""`.
- Back is enabled unless `busy` (`dispatchState === "starting"`, where the store refuses
  `dispatchBack()`); a click emits `backRequested()` once.
- No key goes back from the form: Backspace in a form field edits that field only.
- Back to the target step keeps the picked row under the cursor through `targetKey` (see The
  cursor).

### Where Back shows

| step | Back |
|---|---|
| `""` (card entry, and every S3 test) | not visible |
| `"project"` | not visible (Cancel only, **S31**) |
| `"target"` | visible, enabled |
| `"form"` | visible, enabled unless `busy` |

### Unchanged

With `step` `""` or `"project"`, every existing behaviour and every existing test in
`tests/ui/components/tst_dispatch_dialog.qml` holds as is. `targetPicked` is never emitted outside
the target step; `backRequested` never at `""` or `"project"`; `projectChosen` never at the target
step.

## Errors and edge inputs

| input | behaviour |
|---|---|
| `targetRows` null / undefined / not array-like | reads as `[]`: `No target matches`, cursor `-1`, Enter emits nothing, Back and Backspace still work |
| an entry that is not an object, or has no non-empty string `key` | gives no row |
| `card` missing or not an object on a non-board row | title `""`, short id `""`; the row still shows and is pickable by key |
| `depth` missing, negative or not whole | indented as depth 0 |
| `targetLoading` true with rows present | `Reading the board…`, no rows, cursor `-1`, Enter emits nothing; Back and Backspace in an empty filter still emit `backRequested` (**P** 235: Back cancels the read) |
| loading ends with rows | cursor on `targetKey`'s row if shown, else row 0 |
| filter matching nothing | `No target matches`, cursor `-1`, Enter nothing; clearing it brings the rows and the cursor back to row 0 (or `targetKey`'s row) |
| `targetKey` naming no shown row | cursor on shown row 0 |
| step leaves `"target"` and comes back | filter cleared, cursor reset as on entry |
| setting every object prop to null and destroying the dialog at the target step | no warnings (`TypeError`, `ReferenceError`), as `tst_dispatch_dialog.qml:601` and `:1163` |

## Out of scope

- Binding `step`, `targetRows`, `targetLoading`, `targetKey`, `projectName`, `onTargetPicked`
  and `onBackRequested` in `ui/Panel.qml`, and giving `focusItem` active focus on a step change:
  card 3.3 (`d4fdb639`), with Runs toolbar gating and the `d` key.
- `docs/architecture.md` and README: card 3.4 (`d3df5c9d`).
- Any store, domain or backend change: `RunStore`, `runs.js` and `board-tree.py` are done.
- A heading for the form step (it stays `Dispatch`), a status column on target rows, and wrapping
  the cursor at the list's ends.
- The project step's behaviour (3.1), beyond keeping it green.

## Tests

All in `tests/ui/components/tst_dispatch_dialog.qml`, a new `// ---- target step` section after
the project step's, using the file's `make(over)` / `H.find` / `click` helpers and two new
`SignalSpy`s, on `targetPicked` and `backRequested`, wired and cleared in `make()`. **Tier: UI
component test** (qmltestrunner, offscreen, via `bash tests/run.sh`), because the deliverable is a
props-in / signals-out component: rendering, focus, filtering, key and mouse handling are only
observable on the live item, and no store or Panel is involved (the store's step machine is
already covered in `tests/core/stores/tst_run_store.qml`). The architecture tier
(`tests/architecture`, pytest) is not extended; it must stay green, which proves no shared visual
pattern was copied.

Fixture rows (as `Runs.dispatchTargets` builds them): `board` (depth 0); milestone
`M4 Run story` id `aaaa1111-…` depth 0; story `Story dispatch backend` id `bbbb2222-…` depth 1;
subtask `1.2 runs.js: targets` id `cccc3333-…` depth 2; subtask `1.3 dialog rows` id
`dddd4444-…` depth 2. `make({step: "target", targetRows: rows, projectName: "agent-manager"})`
gives the target step (the default `milestone()` props stay; the step hides them).

1. **Rows, level words, ids and order**: five `dispatchTargetRow<i>` in order; titles
   `Whole board`, `M4 Run story`, …; level words `""` (not visible) / `Milestone` / `Story` /
   `Subtask` / `Subtask`; short ids `aaaa1111` … and none on the board row.
2. **Rows are indented by depth**: the title's x within its row grows by `Style.space(16)` per
   depth step (board and milestone equal; story one step in; subtasks two).
3. **Only the target step's parts show**: heading `Dispatch · 2 Target in agent-manager`
   (`Dispatch · 2 Target` with `projectName: ""`); filter, list, Back and Cancel visible; Start,
   the project list and every S3 objectName above not visible (data-driven over the names).
4. **Loading**: `targetLoading: true` (with and without rows) shows `Reading the board…` in
   `dispatchTargetStatus`, no row, `targetCursor` `-1`, Enter emits nothing; setting it false
   with rows shows them with the cursor on row 0.
5. **Empty rows**: `targetRows` `[]`, null, undefined, `{}`, `"x"` (data-driven) show
   `No target matches`, no row, cursor `-1`, Enter emits nothing.
6. **Filter by title**: typing `dialog` (case variants, data-driven: `dialog`, `DIALOG`,
   `  dialog `) leaves only `1.3 dialog rows` as `dispatchTargetRow0`.
7. **Filter by short id**: typing `cccc33` leaves only the `1.2` subtask; typing `story` matches
   titles only (`M4 Run story`, `Story dispatch backend`), not the level word of other rows.
8. **No match**: `zzz` shows `No target matches`, cursor `-1`, Enter emits nothing; clearing the
   filter brings back five rows with the cursor on row 0.
9. **Cursor starts on row 0, or on targetKey**: entering with `targetKey: ""` puts it on 0;
   with `targetKey: "card:cccc3333-…"` on that row's index (3).
10. **Down / Up from the filter field**: Down moves 0→1→…→4 and stays at 4; Up stops at 0; the
    keys are accepted (the filter text is unchanged).
11. **Enter picks the cursor row**: Return and Enter (data-driven) emit `targetPicked` once with
    that row's key; after filtering, Enter picks the shown row's key, not the unfiltered index.
12. **Filter keeps the cursor on its key**: cursor on `1.3 dialog rows`, typing `rows` keeps it
    on that row (now index 0); typing a filter that hides it moves it to shown row 0.
13. **Click and hover**: a click on a row emits `targetPicked(key)` once and moves the cursor; a
    hover moves the cursor without emitting.
14. **Backspace in an empty filter goes back**: emits `backRequested` once; Backspace with text
    `ab` deletes one character and emits nothing; Backspace in the now-empty field then emits once.
15. **Back button at the target step**: a click emits `backRequested` once; works while
    `targetLoading` too.
16. **Escape cancels**: Escape on the filter emits `cancelRequested` once and no `backRequested`.
17. **Focus**: at the target step `focusItem` is `dispatchTargetFilter`; at `"project"` still
    `dispatchProjectKeys`; at `""` still `dispatchBase` with a form, `dispatchCancel` without.
18. **The filter is cleared on re-entry**: type `zz`, set step `"form"` then `"target"`: the
    filter is `""` and the rows show.
19. **Back from the form keeps the picked row**: rows set, step `"form"` with `targetKey:
    "card:dddd4444-…"`, then step `"target"`: the cursor is on that row (index 4) and the row
    is scrolled into view in a 30-row list.
20. **A long list keeps the cursor in view**: 30 rows, Down to the last; the list's `contentY` > 0
    and the last row lies inside the visible area.
21. **Back at each step**: `step: ""` — Back not visible; `"project"` — not visible;
    `"target"` — visible and enabled; `"form"` — visible, enabled, click emits `backRequested`
    once, Start and the form still show; `"form"` with `dispatchState: "starting"` — Back
    disabled, a click emits nothing.
22. **The card-opened dialog has no Back**: `make()` (step `""`) in every dispatch state
    (data-driven over `dispatchStates`): `dispatchBack` not visible; Backspace in `dispatchBase`
    edits the field and emits no `backRequested`.
23. **Signals stay in their step**: at `"project"` and `""`, Enter/Return on `focusItem` emit no
    `targetPicked`; at `"target"`, Enter emits no `projectChosen`.
24. **Rows arriving keep targetKey's row**: start loading with `targetKey` set, then deliver rows
    and stop loading: the cursor is on that key's row.
25. **Malformed rows**: a row with no `key`, a non-object entry, a row with `card: null` and a
    row with `depth: -1` — the first two give no row; the third shows with empty title and no
    id, pickable by key; the fourth is at depth 0.
26. **Teardown at the target step is quiet**: null every object prop (`theme`, `target`, `form`,
    `preview`, `targetRows`) and destroy, no warning.
27. Every existing test in the file passes unchanged.
