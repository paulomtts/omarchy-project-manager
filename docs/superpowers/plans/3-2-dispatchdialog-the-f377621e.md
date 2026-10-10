# 3.2 DispatchDialog: the target step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ui/components/DispatchDialog.qml` renders RunStore's target step (`step: "target"`, `targetRows`, `targetLoading`, `targetKey`, `projectName`): a filter field over the depth-indented target list, a cursor driven by Up / Down / hover from the filter field, a pick by Enter or click emitted as `targetPicked(key)`, the loading and empty lines, and a Back (button, or Backspace in an empty filter) emitted as `backRequested()` — plus a Back button at the form step (`step: "form"`).

**Architecture:** The dialog stays props-in / signals-out. Two derived flags join `atProject`: `atTarget` and `atForm` (every step but the two pickers), and every form-step part switches from `!atProject` to `atForm`. The target step adds a `TextField` (`dispatchTargetFilter`, the step's `focusItem`) and a capped `Flickable` holding a `UI.FilterableList` whose rows are an inline `TargetRow: UI.ListRow` component. The filtering is a pure function of `targetRows`, `targetLoading`, the step and the filter text (`Text.matchesQuery` from `core/domain/text.js`); the cursor is a private `QtObject` (index + key) exposed read-only as `targetCursor`. No store, domain, Panel or shared-component change.

**Tech Stack:** Qt 6 QML, QtTest (`qmltestrunner`, offscreen) run by `bash tests/run.sh [filter]` (pytest first — the architecture tier included — then every `tst_*.qml` whose path contains the filter; it fails on any `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` in the QML output). Test helpers: `tests/helpers/find.js` (`H.find(item, objectName)`, which also searches a `Flickable`'s `contentItem`). Test stubs: `tests/stubs/qs/Ui/TextField.qml` is a plain `TextInput` with `foreground` / `placeholderText`; `tests/stubs/qs/Ui/Button.qml`'s `MouseArea` is disabled with the button (a disabled button's click emits nothing); `tests/stubs/qs/Commons/Style.qml`'s `space(n)` returns `n`, so `Style.space(16)` is `16` in tests.

**Spec:** `docs/superpowers/specs/3-2-dispatchdialog-the-f377621e.md` (reproduced in full below). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-from-runs-design.md` (**P**). Sibling: `docs/superpowers/specs/3-1-dispatchdialog-the-e04a0de6.md` (**S31**).

## Global Constraints

- Only two files change: `ui/components/DispatchDialog.qml` and `tests/ui/components/tst_dispatch_dialog.qml`. No change to `RunStore`, `runs.js`, `board-tree.py`, `ui/Panel.qml`, `docs/architecture.md` or the README (cards 3.3, 3.4).
- Built on `UI.ModalCard`, `UI.ListRow`, `UI.FilterableList`, `UI.ActionButton`, `UI.ThemedText`, `TextField` (from `qs.Ui`); no new shared component; no `CursorSurface {`, no `font.family:`, no `Qt.rgba(0, 0, 0, 0.55)`, no `bordered: true`, no `radius: height / 2` in the dialog. `tests/architecture` (`test_layers.py`, `test_icon_glyphs.py`) stays green.
- The dialog never imports a store. It may import `core/domain/text.js`; import it as `TextQuery` (`import "../../core/domain/text.js" as TextQuery`) — an alias `Text` would shadow QtQuick's `Text` type that `Text.ElideRight` / `Text.WordWrap` use.
- New API exactly: `property var targetRows: []`, `property bool targetLoading: false`, `property string targetKey: ""`, `property string projectName: ""`, `readonly property int targetCursor`, `signal targetPicked(string key)`, `signal backRequested()`. `targetChosen(string id)` is unchanged.
- Exact strings: heading `Dispatch · 2 Target in <projectName>` / `Dispatch · 2 Target` (empty name) at the target step, `Dispatch · 1 Project` at the project step, `Dispatch` at every other; placeholder `Filter by title or id…`; status `Reading the board…` and `No target matches`; level words `Milestone`, `Story`, `Subtask`; board title `Whole board`; Back button text `Back`.
- Exact objectNames: `dispatchTargetFilter`, `dispatchTargetList`, `dispatchTargetStatus`, `dispatchTargetRow<i>`, `dispatchTargetLine<i>`, `dispatchTargetLevel<i>`, `dispatchTargetTitle<i>`, `dispatchTargetId<i>`, `dispatchBack`.
- A valid row is an object whose `key` is a non-empty string; the short id is the first 8 characters of `card.id`; depth is `depth` when a whole number ≥ 0, else 0; indent `depth × Style.space(16)`; list height capped at `Style.space(240)`.
- `focusItem`: `dispatchProjectKeys` at `"project"`, `dispatchTargetFilter` at `"target"`, else `form ? baseField : cancelButton` as today.
- Back: not visible at `""` and `"project"`; visible and enabled at `"target"`; visible at `"form"`, enabled unless `busy`.
- At `step` `""` and `"project"` every existing behaviour and existing test holds. One existing assertion is about `step: "target"` and changes in Task 1: `test_the_project_step_heads_the_card_and_keeps_only_cancel` expected `Dispatch` there and now expects `Dispatch · 2 Target`.
- `targetPicked` never emitted outside the target step; `backRequested` never at `""` or `"project"`; `projectChosen` never at the target step.
- Comments state the contract only, no narrative (style: `DispatchDialog.qml:314` "A pick: at the project step and on an enabled row only.").
- Verification: `bash tests/run.sh` green.

## Deviation from the spec's test list (one)

- Spec test 2 says "the title's x within its row grows by `Style.space(16)` per depth step (board and milestone equal)". The level word sits before the title on the same line, so the milestone's title is pushed right by the `Milestone` caption while the board's (no level word) is not — the title's x cannot be equal for those two. The plan indents a per-row line (`dispatchTargetLine<i>`, a `Row` holding level / title / id) by `depth × Style.space(16)` and the test compares that line's `x` (0, 0, 16, 32, 32), which is the behaviour the spec states ("indented from the row's left edge by `depth × Style.space(16)`").

## Review Focus

1. A `depth` that is a fraction (`1.5`), `Infinity`, a numeric string (`"2"`) or `null`: the row is indented as depth 0, never by a huge or NaN offset — pinned in Task 2 (`test_malformed_target_rows`).
2. Focus left on `dispatchTargetFilter` after the owner moves to the form step: Down / Return / Backspace there must not emit `targetPicked` or `backRequested` — pinned in Task 3 (`test_keys_on_the_filter_after_leaving_the_target_step_do_nothing`).
3. A re-read (`targetLoading` going true again) while the cursor is on a row: the cursor is `-1`, Enter picks nothing, and when the read ends the cursor lands on `targetKey`'s row, else row 0 — pinned in Task 3 (`test_a_re_read_drops_the_cursor_until_the_rows_return`).
4. A filter of only spaces: shows every row (the trimmed query is empty), and the status line stays hidden — pinned in Task 2 (`test_the_filter_matches_titles_case_blind`, tag `blank`).
5. A very long title next to its level word and short id: the title elides on one line and the level word and id stay visible inside the row — pinned in Task 2 (`test_a_long_target_title_elides_and_keeps_its_id`).

---

## Spec (verbatim)

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

---

## File Structure

- Modify: `ui/components/DispatchDialog.qml` — the one component this card renders. New props, flags, functions, the filter field, the target list, the inline `TargetRow` component, the Back button.
- Modify: `tests/ui/components/tst_dispatch_dialog.qml` — two new `SignalSpy`s wired in `make()`, one changed assertion in the project-step heading test, and a new `// ---- the target step` section appended at the end of the file (after `test_hovering_an_enabled_row_moves_the_cursor`, before the final `}` closing `TestCase`).

Run one file's tests with: `bash tests/run.sh tst_dispatch_dialog` (pytest runs first, then only this QML file). A failing QML test prints `FAIL!  : DispatchDialog::<test>() ...` lines and a `Totals:` line.

---

### Task 1: The step flags, the target step's heading and the Back button

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (header comment lines 15-16; `step` prop lines 58-61; `atProject` line 65; `!dialog.atProject` at lines 83, 107, 109, 110, 112, 454, 464, 475, 623, 742, 755, 775; signals line 135; `cancel()` lines 171-173; heading line 360; button row lines 761-782)
- Test: `tests/ui/components/tst_dispatch_dialog.qml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `property string projectName: ""`; `readonly property bool atTarget` (`step === "target"`); `readonly property bool atForm` (`!atProject && !atTarget`); `readonly property bool canGoBack` (`atTarget || step === "form"`); `signal backRequested()`; `function back()` (emits `backRequested()` when `canGoBack && !busy`); the `dispatchBack` button (`id: backButton`); the `backs` `SignalSpy` in the test file wired in `make()`.

- [ ] **Step 1: Add the `backs` spy and write the failing tests**

In `tests/ui/components/tst_dispatch_dialog.qml`, after the line `SignalSpy { id: picks; signalName: "projectChosen" }` add:

```qml
  SignalSpy { id: backs; signalName: "backRequested" }
```

Replace the body of `make(over)`:

```qml
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, milestone(over))
    edits.target = d; starts.target = d; cancels.target = d; chosen.target = d; offers.target = d
    picks.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear(); picks.clear()
    d.shown = true
    wait(30)
    return d
  }
```

with:

```qml
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, milestone(over))
    edits.target = d; starts.target = d; cancels.target = d; chosen.target = d; offers.target = d
    picks.target = d; backs.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear(); picks.clear()
    backs.clear()
    d.shown = true
    wait(30)
    return d
  }
```

In `test_the_project_step_heads_the_card_and_keeps_only_cancel`, replace:

```qml
    d.step = "target"
    compare(heading.text, "Dispatch")
    compare(picks.count, 0)
```

with:

```qml
    d.step = "target"
    compare(heading.text, "Dispatch · 2 Target")
    compare(picks.count, 0)
```

At the end of the file, before the final `}` that closes `TestCase`, append:

```qml
  // ---- the target step --------------------------------------------------

  // 3
  function test_the_target_step_heads_the_card_with_back_and_cancel() {
    var d = make({ step: "target", projectName: "agent-manager" })
    var heading = H.find(d, "dispatchHeading")
    compare(heading.text, "Dispatch · 2 Target in agent-manager")
    verify(H.find(d, "dispatchBack").visible, "Back")
    verify(H.find(d, "dispatchBack").enabled, "Back is enabled")
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
    verify(!H.find(d, "dispatchProjectList").visible, "no project list")
    verify(!H.find(d, "dispatchProjectEmpty").visible, "no project empty line")
    d.projectName = ""
    compare(heading.text, "Dispatch · 2 Target")
    d.step = "form"
    compare(heading.text, "Dispatch")
    d.step = "project"
    compare(heading.text, "Dispatch · 1 Project")
  }

  // 3: every part the project step hides is hidden at the target step too.
  function test_the_target_step_hides_the_form_steps_parts_data() {
    return tc.test_the_project_step_hides_the_form_steps_parts_data()
  }

  function test_the_target_step_hides_the_form_steps_parts(data) {
    var d = make(data.over)
    if (data.arm) click(H.find(d, "dispatchStart"))
    verify(H.find(d, data.name).visible, "shown at the form step")
    d.step = "target"
    verify(!H.find(d, data.name).visible, "hidden at the target step")
    d.step = "form"
    verify(H.find(d, data.name).visible, "shown again at the form step")
  }

  // 15, 21
  function test_back_shows_at_the_target_and_form_steps_only() {
    var d = make()
    var back = H.find(d, "dispatchBack")
    verify(!back.visible, "no Back on a card-opened dialog")
    d.step = "project"
    verify(!back.visible, "no Back at the project step")
    d.step = "target"
    verify(back.visible, "Back at the target step")
    verify(back.enabled)
    click(back)
    compare(backs.count, 1)
    d.step = "form"
    verify(back.visible, "Back at the form step")
    verify(back.enabled)
    verify(H.find(d, "dispatchStart").visible, "the form step keeps Start")
    verify(H.find(d, "dispatchForm").visible, "and its form")
    click(back)
    compare(backs.count, 2)
    compare(cancels.count, 0)
    compare(starts.count, 0)
  }

  // 21
  function test_back_at_the_form_step_is_disabled_while_starting() {
    var d = make({ step: "form", dispatchState: "starting" })
    var back = H.find(d, "dispatchBack")
    verify(back.visible)
    verify(!back.enabled)
    click(back)
    compare(backs.count, 0)
    d.back()
    compare(backs.count, 0, "back() refuses while starting")
  }

  // 22
  function test_the_card_opened_dialog_has_no_back_data() {
    return tc.dispatchStates.map(function(s) { return { tag: s, state: s } })
  }

  function test_the_card_opened_dialog_has_no_back(data) {
    var d = make({ dispatchState: data.state })
    verify(!H.find(d, "dispatchBack").visible)
    var base = H.find(d, "dispatchBase")
    base.forceActiveFocus()
    base.cursorPosition = base.text.length
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 0)
    if (d.editable) compare(base.text, "mai", "Backspace edits the field")
    d.back()
    compare(backs.count, 0, "back() refuses at step \"\"")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — `test_the_target_step_heads_the_card_with_back_and_cancel` (heading is `Dispatch`, `dispatchBack` not found: `TypeError: Cannot read property 'visible' of null`), `test_the_target_step_hides_the_form_steps_parts` (parts still visible at `"target"`), the two Back tests, `test_the_card_opened_dialog_has_no_back` (`dispatchBack` null), and `test_the_project_step_heads_the_card_and_keeps_only_cancel` (`Dispatch` vs `Dispatch · 2 Target`). The SignalSpy on `backRequested` may also warn that the signal does not exist.

- [ ] **Step 3: Switch the form-step parts to `atForm`**

Run this first, while the line numbers still match the listing above (it rewrites only the form-step parts; `projectKey`'s `else if (!dialog.atProject) return` at line 330 and `pickProject`'s `!dialog.atProject ||` at line 316 stay):

```bash
sed -i '80,115s/!dialog\.atProject/dialog.atForm/g; 450,790s/!dialog\.atProject/dialog.atForm/g' ui/components/DispatchDialog.qml
grep -n 'atProject\|atForm' ui/components/DispatchDialog.qml
```

Expected grep output: `atForm` on the `canOffer`, `showRefusal`, `showSubtask`, `showChecking`, `showSummary` lines and on the `visible:` of `dispatchTarget`, `dispatchTargetChoices`, `dispatchForm`, `dispatchPreviewHeading`, `dispatchWarning`, `dispatchConfirmNote`, `dispatchStart`; `atProject` only in its declaration, `focusItem`, `pickProject`, `hoverProject`, `projectKey`, the heading, `dispatchProjectList`, the project `Repeater` model and `dispatchProjectEmpty`.

Then fix the two comments that mention the project step for the form-step parts. Replace:

```qml
  // The preview area shows exactly one of these, checked in this order; the
  // project step shows none.
```

with:

```qml
  // The preview area shows exactly one of these, checked in this order; the
  // two pickers show none.
```

and replace:

```qml
    // The cost warning shows in every state, a refused target's included; the
    // project step has none.
```

with:

```qml
    // The cost warning shows in every state, a refused target's included; the
    // two pickers have none.
```

- [ ] **Step 4: Add the flags, `projectName`, `backRequested` and `back()`**

Replace the header comment's last two lines:

```qml
// At step "project" it lists the projects instead (projectRows), with Cancel
// only; the owner maps projectChosen onto dispatchProjectPick.
```

with:

```qml
// At step "project" it lists the projects instead (projectRows), with Cancel
// only; the owner maps projectChosen onto dispatchProjectPick. At step
// "target" it lists the picked project's targets under a filter (targetRows),
// with Back and Cancel; the owner maps targetPicked onto dispatchTargetPick.
// Back shows at steps "target" and "form"; the owner maps backRequested onto
// dispatchBack.
```

Replace:

```qml
  // RunStore's dispatchStep. "project" shows the project list in place of the
  // target line, the form, the preview, the warning and Start; any other value
  // shows those.
  property string step: ""
```

with:

```qml
  // RunStore's dispatchStep. "project" shows the project list and "target"
  // the target list, each in place of the target line, the form, the preview,
  // the warning and Start; any other value shows those.
  property string step: ""
  // The picked project's name, for the target step's heading.
  property string projectName: ""
```

Replace:

```qml
  readonly property bool atProject: dialog.step === "project"
```

with:

```qml
  readonly property bool atProject: dialog.step === "project"
  readonly property bool atTarget: dialog.step === "target"
  // The form step's parts show at every step but the two pickers.
  readonly property bool atForm: !dialog.atProject && !dialog.atTarget
  // Back shows at the target step and at the form step a Runs dispatch reaches.
  readonly property bool canGoBack: dialog.atTarget || dialog.step === "form"
```

Replace:

```qml
  signal projectChosen(string root)
```

with:

```qml
  signal projectChosen(string root)
  signal backRequested()
```

Replace:

```qml
  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }
```

with:

```qml
  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }

  // Back one step: at the target step, and at the form step unless starting.
  function back() {
    if (dialog.canGoBack && !dialog.busy) dialog.backRequested()
  }
```

- [ ] **Step 5: The heading and the Back button**

Replace:

```qml
      text: dialog.atProject ? "Dispatch · 1 Project" : "Dispatch"
```

with:

```qml
      text: dialog.atProject ? "Dispatch · 1 Project"
        : !dialog.atTarget ? "Dispatch"
        : dialog.projectName !== "" ? "Dispatch · 2 Target in " + dialog.projectName
        : "Dispatch · 2 Target"
```

In the button `Row` at the end of the `ModalCard`, replace:

```qml
    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        id: cancelButton
```

with:

```qml
    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        id: backButton
        objectName: "dispatchBack"
        visible: dialog.canGoBack
        text: "Back"
        enabled: !dialog.busy
        theme: dialog.theme
        onClicked: dialog.back()
      }

      UI.ActionButton {
        id: cancelButton
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: pytest passes; `Totals: N passed, 0 failed` for `tst_dispatch_dialog.qml`; no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the target step heads the card and Back shows at the target and form steps"
```

---

### Task 2: The target list, its filter and its status line

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (imports at the top; props after `projectRows`; functions after `pickProject`/`hoverProject`/`projectKey`; new items in the `ModalCard` after `dispatchProjectEmpty`; inline component after the `ModalCard`)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (target step section)

**Interfaces:**
- Consumes (Task 1): `atTarget`, `backRequested()`, `backs` spy, `dispatchBack`.
- Produces: `property var targetRows: []`; `property bool targetLoading: false`; `function targetList()` → array (a copy; `[]` for anything not array-like); `function validTarget(row)` → bool; `function targetLevelWord(row)` → string; `function targetTitleOf(row)` → string; `function targetShortId(row)` → string; `function targetDepth(row)` → whole number ≥ 0; `function shownTargets()` → array of valid rows passing the filter, `[]` while loading or off the target step (always computed fresh — handlers call this, not the property); `readonly property var shownTargetRows: dialog.shownTargets()` (for bindings); items `targetFilter` (`dispatchTargetFilter`), `targetFlick` (`dispatchTargetList`), `targetColumn` (the `UI.FilterableList`); inline `component TargetRow: UI.ListRow` (`id: targetRow`); test helpers `targetFixture()`, `targetStep(over)`, `shownRowCount(d)`.

- [ ] **Step 1: Write the failing tests**

Append to the target step section (before the final `}`):

```qml
  // RunStore's dispatchTargetRows for one milestone, as Runs.dispatchTargets
  // builds them: the board row, then the tree in order.
  function targetFixture() {
    return [
      { key: "board", level: "board", card: "board", label: "Whole board", depth: 0 },
      { key: "card:aaaa1111-0000-4000-8000-000000000001", level: "milestone",
        card: { id: "aaaa1111-0000-4000-8000-000000000001", title: "M4 Run story", status: "todo", depth: 0 },
        label: "Milestone \"M4 Run story\"", depth: 0 },
      { key: "card:bbbb2222-0000-4000-8000-000000000002", level: "story",
        card: { id: "bbbb2222-0000-4000-8000-000000000002", title: "Story dispatch backend", status: "todo",
                depth: 1 },
        label: "Story \"Story dispatch backend\"", depth: 1 },
      { key: "card:cccc3333-0000-4000-8000-000000000003", level: "subtask",
        card: { id: "cccc3333-0000-4000-8000-000000000003", title: "1.2 runs.js: targets", status: "todo",
                depth: 2 },
        label: "Subtask \"1.2 runs.js: targets\"", depth: 2 },
      { key: "card:dddd4444-0000-4000-8000-000000000004", level: "subtask",
        card: { id: "dddd4444-0000-4000-8000-000000000004", title: "1.3 dialog rows", status: "todo", depth: 2 },
        label: "Subtask \"1.3 dialog rows\"", depth: 2 }
    ]
  }

  // The dialog at the target step over targetFixture(); `over` replaces any
  // prop. The mouse is parked on the backdrop so no row is hovered.
  function targetStep(over) {
    var d = make(Object.assign({ step: "target", targetRows: tc.targetFixture(), projectName: "agent-manager" },
                               over || {}))
    mouseMove(d, 1, 1)
    return d
  }

  // How many target rows are on screen: dispatchTargetRow0, 1, … up to the
  // first one missing. The wait lets a replaced row finish being deleted.
  function shownRowCount(d) {
    wait(0)
    var n = 0
    while (H.find(d, "dispatchTargetRow" + n)) n++
    return n
  }

  // 1
  function test_the_target_step_lists_each_row_with_its_level_and_id() {
    var d = targetStep()
    compare(shownRowCount(d), 5)
    var titles = ["Whole board", "M4 Run story", "Story dispatch backend", "1.2 runs.js: targets", "1.3 dialog rows"]
    var levels = ["", "Milestone", "Story", "Subtask", "Subtask"]
    var ids = ["", "aaaa1111", "bbbb2222", "cccc3333", "dddd4444"]
    for (var i = 0; i < 5; i++) {
      compare(H.find(d, "dispatchTargetTitle" + i).text, titles[i], "title " + i)
      var level = H.find(d, "dispatchTargetLevel" + i)
      compare(level.text, levels[i], "level " + i)
      compare(level.visible, levels[i] !== "", "level " + i + " visible")
      var id = H.find(d, "dispatchTargetId" + i)
      compare(id.text, ids[i], "id " + i)
      compare(id.visible, ids[i] !== "", "id " + i + " visible")
    }
    verify(!H.find(d, "dispatchTargetStatus").visible, "no status line over rows")
    verify(sameColour(H.find(d, "dispatchTargetLevel1").color, d.theme.dim), "the level word is dim")
    verify(sameColour(H.find(d, "dispatchTargetId1").color, d.theme.dim), "the id is dim")
    verify(sameColour(H.find(d, "dispatchTargetTitle1").color, d.theme.foreground), "the title is foreground")
  }

  // 2 (the line, not the title, is indented: see the plan's deviation note)
  function test_target_rows_are_indented_by_depth() {
    var d = targetStep()
    var want = [0, 0, 16, 32, 32]
    for (var i = 0; i < 5; i++)
      compare(H.find(d, "dispatchTargetLine" + i).x, want[i], "row " + i)
  }

  // 3
  function test_the_filter_and_the_list_show_only_at_the_target_step_data() {
    return [
      { tag: "card", step: "", shown: false },
      { tag: "project", step: "project", shown: false },
      { tag: "form", step: "form", shown: false },
      { tag: "target", step: "target", shown: true }
    ]
  }

  function test_the_filter_and_the_list_show_only_at_the_target_step(data) {
    var d = targetStep({ step: data.step })
    var filter = H.find(d, "dispatchTargetFilter")
    compare(filter.visible, data.shown)
    compare(H.find(d, "dispatchTargetList").visible, data.shown)
    compare(filter.placeholderText, "Filter by title or id…")
    compare(filter.width, H.find(d, "dispatchHeading").parent.width, "full card width")
    if (!data.shown) compare(shownRowCount(d), 0, "no rows off the target step")
  }

  // 4, 15
  function test_loading_reads_the_board_and_shows_no_row_data() {
    return [{ tag: "no-rows", rows: [] }, { tag: "rows", rows: tc.targetFixture() }]
  }

  function test_loading_reads_the_board_and_shows_no_row(data) {
    var d = targetStep({ targetRows: data.rows, targetLoading: true })
    var status = H.find(d, "dispatchTargetStatus")
    verify(status.visible)
    compare(status.text, "Reading the board…")
    compare(shownRowCount(d), 0)
    verify(H.find(d, "dispatchTargetFilter").visible, "the filter shows while loading")
    click(H.find(d, "dispatchBack"))
    compare(backs.count, 1, "Back cancels the read")
    d.targetRows = tc.targetFixture()
    d.targetLoading = false
    compare(shownRowCount(d), 5)
    verify(!status.visible)
  }

  // 5
  function test_an_empty_or_malformed_target_list_says_no_target_matches_data() {
    return [
      { tag: "empty", rows: [] },
      { tag: "null", rows: null },
      { tag: "undefined", rows: undefined },
      { tag: "object", rows: {} },
      { tag: "string", rows: "x" }
    ]
  }

  function test_an_empty_or_malformed_target_list_says_no_target_matches(data) {
    var d = targetStep({ targetRows: data.rows })
    var status = H.find(d, "dispatchTargetStatus")
    verify(status.visible)
    compare(status.text, "No target matches")
    compare(shownRowCount(d), 0)
    click(H.find(d, "dispatchBack"))
    compare(backs.count, 1)
  }

  // 6, Review Focus 4
  function test_the_filter_matches_titles_case_blind_data() {
    return [
      { tag: "lower", query: "dialog", titles: ["1.3 dialog rows"] },
      { tag: "upper", query: "DIALOG", titles: ["1.3 dialog rows"] },
      { tag: "padded", query: "  dialog ", titles: ["1.3 dialog rows"] },
      { tag: "blank", query: "   ",
        titles: ["Whole board", "M4 Run story", "Story dispatch backend", "1.2 runs.js: targets", "1.3 dialog rows"] }
    ]
  }

  function test_the_filter_matches_titles_case_blind(data) {
    var d = targetStep()
    H.find(d, "dispatchTargetFilter").text = data.query
    compare(shownRowCount(d), data.titles.length)
    for (var i = 0; i < data.titles.length; i++)
      compare(H.find(d, "dispatchTargetTitle" + i).text, data.titles[i])
    verify(!H.find(d, "dispatchTargetStatus").visible)
  }

  // 7
  function test_the_filter_matches_the_short_id_not_the_level_word() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    filter.text = "cccc33"
    compare(shownRowCount(d), 1)
    compare(H.find(d, "dispatchTargetTitle0").text, "1.2 runs.js: targets")
    filter.text = "story"
    compare(shownRowCount(d), 2)
    compare(H.find(d, "dispatchTargetTitle0").text, "M4 Run story")
    compare(H.find(d, "dispatchTargetTitle1").text, "Story dispatch backend")
    filter.text = "subtask"
    compare(shownRowCount(d), 0, "the level word is not matched")
    filter.text = "0000-4000"
    compare(shownRowCount(d), 0, "only the short id is matched, not the whole id")
  }

  // 8
  function test_a_filter_matching_nothing_says_no_target_matches() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    filter.text = "zzz"
    compare(shownRowCount(d), 0)
    compare(H.find(d, "dispatchTargetStatus").text, "No target matches")
    filter.text = ""
    compare(shownRowCount(d), 5)
    verify(!H.find(d, "dispatchTargetStatus").visible)
  }

  // 25, Review Focus 1
  function test_malformed_target_rows() {
    var rows = [
      { level: "subtask", card: { id: "ffff0000-x", title: "No key" }, depth: 2 },
      42,
      null,
      { key: "", level: "story", card: { id: "ffff1111-x", title: "Empty key" }, depth: 1 },
      { key: "card:nocard", level: "subtask", card: null, depth: 1 },
      { key: "card:neg", level: "story", card: { id: "eeee5555-0000", title: "Negative" }, depth: -1 },
      { key: "card:frac", level: "story", card: { id: "eeee6666-0000", title: "Fraction" }, depth: 1.5 },
      { key: "card:inf", level: "story", card: { id: "eeee7777-0000", title: "Infinite" }, depth: Infinity },
      { key: "card:text", level: "story", card: { id: "eeee8888-0000", title: "Text depth" }, depth: "2" },
      { key: "card:odd", level: "epic", card: { id: 7, title: 9 } }
    ]
    var d = targetStep({ targetRows: rows })
    compare(shownRowCount(d), 6, "no key, a number, null and an empty key give no row")
    compare(H.find(d, "dispatchTargetTitle0").text, "", "no card: no title")
    verify(!H.find(d, "dispatchTargetId0").visible, "no card: no id")
    compare(H.find(d, "dispatchTargetLevel0").text, "Subtask")
    compare(H.find(d, "dispatchTargetLine0").x, 16, "a valid depth still indents")
    for (var i = 1; i <= 4; i++)
      compare(H.find(d, "dispatchTargetLine" + i).x, 0, "row " + i + " reads as depth 0")
    compare(H.find(d, "dispatchTargetLevel5").text, "", "an unknown level has no word")
    verify(!H.find(d, "dispatchTargetLevel5").visible)
    compare(H.find(d, "dispatchTargetTitle5").text, "", "a non-string title reads as empty")
    compare(H.find(d, "dispatchTargetId5").text, "", "a non-string id reads as empty")
    compare(H.find(d, "dispatchTargetLine5").x, 0, "a missing depth reads as 0")
  }

  // Review Focus 5
  function test_a_long_target_title_elides_and_keeps_its_id() {
    var long = new Array(30).join("A very long subtask title ")
    var rows = [{ key: "card:long", level: "subtask", card: { id: "abcd1234-0000", title: long }, depth: 2 }]
    var d = targetStep({ targetRows: rows })
    var title = H.find(d, "dispatchTargetTitle0")
    var row = H.find(d, "dispatchTargetRow0")
    var id = H.find(d, "dispatchTargetId0")
    compare(title.elide, Text.ElideRight)
    verify(title.truncated, "the title is cut, not wrapped")
    compare(title.lineCount, 1)
    verify(id.visible)
    var idRight = id.mapToItem(row, id.width, 0).x
    verify(idRight <= row.width + 0.5, "the id stays inside the row")
    verify(H.find(d, "dispatchTargetLevel0").visible, "the level word stays")
  }

  // 26
  function test_nulling_every_object_prop_at_the_target_step_and_destroying_is_quiet() {
    var d = targetStep()
    d.theme = null
    d.target = null
    d.form = null
    d.preview = null
    d.targetRows = null
    wait(0)
    compare(H.find(d, "dispatchTargetStatus").text, "No target matches")
    compare(edits.count, 0)
    d.destroy()
    wait(0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — the new tests report `Could not set initial property targetRows` / `dispatchTargetRow0` not found (`shownRowCount` is 0), `TypeError: Cannot read property 'text' of null` on `dispatchTargetTitle0` / `dispatchTargetStatus`, and the run prints the `TypeError` lines.

- [ ] **Step 3: Import `text.js` and add the props**

Replace the imports:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T
```

with:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/text.js" as TextQuery
import "../components" as UI
import "../theme" as T
```

Replace:

```qml
  property var projectRows: []
```

with:

```qml
  property var projectRows: []
  // RunStore's dispatchTargetRows, [{key, level, card, label, depth}];
  // anything not array-like reads as [].
  property var targetRows: []
  // RunStore's dispatchTargetLoading: the tree is still being read.
  property bool targetLoading: false
```

Replace:

```qml
  readonly property bool hasEnabledProject: dialog.nextEnabledProject(0, 1) >= 0
```

with:

```qml
  readonly property bool hasEnabledProject: dialog.nextEnabledProject(0, 1) >= 0
  // The target rows the list shows; see shownTargets().
  readonly property var shownTargetRows: dialog.shownTargets()
```

- [ ] **Step 4: Add the row functions**

After the `projectKey(event)` function (the one ending `event.accepted = true\n  }` before the `dispatchProjectKeys` item), add:

```qml
  // The target rows: a list, or the array-like a list arrives as through
  // createObject; anything else (null, an object, a string) reads as [].
  function targetList() {
    var rows = dialog.targetRows
    if (!rows || typeof rows !== "object" || typeof rows.length !== "number") return []
    return Array.prototype.slice.call(rows)
  }

  // A row is an object whose key is a non-empty string; anything else gives no row.
  function validTarget(row) {
    return !!row && typeof row === "object" && typeof row.key === "string" && row.key !== ""
  }

  // "Milestone", "Story" or "Subtask"; "" for the board and any other level.
  function targetLevelWord(row) {
    switch (row.level) {
    case "milestone": return "Milestone"
    case "story": return "Story"
    case "subtask": return "Subtask"
    }
    return ""
  }

  // "Whole board" for the board; else the card's string title, or "".
  function targetTitleOf(row) {
    if (row.level === "board") return "Whole board"
    var card = row.card
    return !!card && typeof card === "object" && typeof card.title === "string" ? card.title : ""
  }

  // The first 8 characters of the card's string id, or "".
  function targetShortId(row) {
    var card = row.card
    return !!card && typeof card === "object" && typeof card.id === "string" ? card.id.slice(0, 8) : ""
  }

  // A whole number >= 0; anything else reads as 0.
  function targetDepth(row) {
    var depth = row.depth
    return typeof depth === "number" && Number.isInteger(depth) && depth >= 0 ? depth : 0
  }

  // The valid rows whose title or short id holds the filter text, in
  // targetRows order; none while loading and at every other step.
  function shownTargets() {
    if (!dialog.atTarget || dialog.targetLoading) return []
    var query = targetFilter.text
    return dialog.targetList().filter(function(row) {
      return dialog.validTarget(row)
        && (TextQuery.matchesQuery(dialog.targetTitleOf(row), query)
            || TextQuery.matchesQuery(dialog.targetShortId(row), query))
    })
  }
```

- [ ] **Step 5: Add the filter field and the list**

In the `ModalCard`, after the `dispatchProjectEmpty` `UI.ThemedText` (the one whose text is `"No projects registered" : "No project's board can be read"`) and before the `dispatchTarget` `UI.ThemedText`, add:

```qml
    TextField {
      id: targetFilter
      objectName: "dispatchTargetFilter"
      visible: dialog.atTarget
      width: parent.width
      foreground: dialog.foregroundColor
      placeholderText: "Filter by title or id…"
    }

    // The target step's rows, in the owner's order, narrowed by the filter.
    Flickable {
      id: targetFlick
      objectName: "dispatchTargetList"
      visible: dialog.atTarget
      width: parent.width
      height: Math.min(targetColumn.implicitHeight, Style.space(240))
      contentHeight: targetColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      UI.FilterableList {
        id: targetColumn
        width: targetFlick.width
        theme: dialog.theme
        statusObjectName: "dispatchTargetStatus"
        loading: dialog.targetLoading
        loadingText: "Reading the board…"
        empty: dialog.shownTargetRows.length === 0
        filtered: targetFilter.text.trim() !== ""
        emptyText: "No target matches"
        filteredText: "No target matches"
        model: dialog.shownTargetRows
        rowDelegate: Component { TargetRow {} }
      }
    }
```

After the `UI.ModalCard { ... }` block closes (its closing `  }` just before the dialog's final `}`), add the inline component:

```qml

  // One target row: the level word, the title and the short id on one line,
  // indented by depth.
  component TargetRow: UI.ListRow {
    id: targetRow
    required property var modelData
    required index
    objectName: "dispatchTargetRow" + targetRow.index
    width: targetFlick.width
    theme: dialog.theme

    Row {
      id: targetLine
      objectName: "dispatchTargetLine" + targetRow.index
      x: dialog.targetDepth(targetRow.modelData) * Style.space(16)
      width: Math.max(0, parent.width - targetLine.x)
      spacing: Style.space(8)

      UI.ThemedText {
        id: targetLevel
        objectName: "dispatchTargetLevel" + targetRow.index
        variant: "caption"
        theme: dialog.theme
        visible: targetLevel.text !== ""
        text: dialog.targetLevelWord(targetRow.modelData)
      }

      UI.ThemedText {
        objectName: "dispatchTargetTitle" + targetRow.index
        theme: dialog.theme
        width: Math.max(0, targetLine.width
          - (targetLevel.visible ? targetLevel.width + targetLine.spacing : 0)
          - (targetId.visible ? targetId.width + targetLine.spacing : 0))
        text: dialog.targetTitleOf(targetRow.modelData)
        color: dialog.foregroundColor
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: targetId
        objectName: "dispatchTargetId" + targetRow.index
        variant: "caption"
        theme: dialog.theme
        visible: targetId.text !== ""
        text: dialog.targetShortId(targetRow.modelData)
      }
    }
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: pytest passes (including `tests/architecture`); `Totals: N passed, 0 failed` for `tst_dispatch_dialog.qml`; no `TypeError`/`ReferenceError` lines. The level word and the id are dim through `ThemedText`'s `caption` variant (`ui/components/ThemedText.qml`), with no `color:` of their own.

- [ ] **Step 7: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit status 0; every QML file `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the target step lists the targets under a filter with its loading and empty lines"
```

---

### Task 3: The target step's cursor, keys and focus

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (props, `focusItem`, signals, handlers, cursor `QtObject`, target functions, the filter field, `TargetRow`)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (target step section; one new spy)

**Interfaces:**
- Consumes (Tasks 1-2): `atTarget`, `back()`, `shownTargets()`, `targetFilter`, `TargetRow`, `targetStep(over)`, `targetFixture()`, `shownRowCount(d)`, `backs` spy, `hostC` (the existing key-counting host component in the test file).
- Produces: `property string targetKey: ""`; `readonly property int targetCursor`; `signal targetPicked(string key)`; private `QtObject { id: targetCursorState; property int index: -1; property string key: "" }`; `function shownTargetIndex(rows, key)` → int; `function setTargetCursor(index)` (out-of-range → -1); `function landingTarget()` → int; `function resetTargetCursor()`; `function followTargetCursor()`; `function jumpToTargetKey()`; `function moveTargetCursor(by)`; `function pickTarget(index)`; `function targetFieldKey(event)`; the `targetPicks` spy in the test file wired in `make()`. Task 4 adds reveal calls inside `resetTargetCursor`, `followTargetCursor`, `jumpToTargetKey` and `moveTargetCursor`, and `onHovered` / `onActivated` on `TargetRow` calling `hoverTarget(index)` / `pickTarget(index)`.

- [ ] **Step 1: Add the `targetPicks` spy and write the failing tests**

After `SignalSpy { id: backs; signalName: "backRequested" }` add:

```qml
  SignalSpy { id: targetPicks; signalName: "targetPicked" }
```

In `make(over)`, replace:

```qml
    picks.target = d; backs.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear(); picks.clear()
    backs.clear()
```

with:

```qml
    picks.target = d; backs.target = d; targetPicks.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear(); picks.clear()
    backs.clear(); targetPicks.clear()
```

Append to the target step section (before the final `}`):

```qml
  // Types `text` into the item with the active focus, one key per character.
  function typeText(text) {
    for (var i = 0; i < text.length; i++) keyClick(text[i])
  }

  // 9
  function test_the_cursor_starts_on_row_0_or_on_target_key() {
    var d = targetStep()
    compare(d.targetCursor, 0)
    verify(H.find(d, "dispatchTargetRow0").hasCursor, "row 0 is highlighted")
    var e = targetStep({ targetKey: "card:cccc3333-0000-4000-8000-000000000003" })
    compare(e.targetCursor, 3)
    verify(H.find(e, "dispatchTargetRow3").hasCursor)
    var f = targetStep({ targetKey: "card:gone" })
    compare(f.targetCursor, 0, "a key naming no row lands on row 0")
    f.targetKey = "card:bbbb2222-0000-4000-8000-000000000002"
    compare(f.targetCursor, 2, "a new targetKey moves the cursor onto its row")
    f.targetKey = "card:gone"
    compare(f.targetCursor, 2, "a key naming no row leaves it")
    compare(make().targetCursor, -1, "no cursor at step \"\"")
    compare(targetStep({ step: "project" }).targetCursor, -1, "none at the project step")
    compare(targetStep({ step: "form" }).targetCursor, -1, "none at the form step")
  }

  // 10
  function test_down_and_up_move_the_cursor_from_the_filter_and_stop_at_the_ends() {
    var host = createTemporaryObject(hostC, tc)
    var d = host.dialog
    d.step = "target"
    d.targetRows = tc.targetFixture()
    d.shown = true
    wait(30)
    mouseMove(d, 1, 1)
    d.focusItem.forceActiveFocus()
    for (var i = 1; i <= 4; i++) {
      keyClick(Qt.Key_Down)
      compare(d.targetCursor, i)
    }
    keyClick(Qt.Key_Down)
    compare(d.targetCursor, 4, "Down on the last row stays")
    for (var k = 0; k < 5; k++) keyClick(Qt.Key_Up)
    compare(d.targetCursor, 0, "Up on the first row stays")
    compare(host.passed, 0, "Down and Up are accepted")
    compare(H.find(d, "dispatchTargetFilter").text, "", "the filter text is unchanged")
  }

  // 11
  function test_enter_picks_the_cursor_row_data() {
    return [{ tag: "return", key: Qt.Key_Return }, { tag: "enter", key: Qt.Key_Enter }]
  }

  function test_enter_picks_the_cursor_row(data) {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(data.key)
    compare(targetPicks.count, 1)
    compare(targetPicks.signalArguments[0][0], "card:aaaa1111-0000-4000-8000-000000000001")
    H.find(d, "dispatchTargetFilter").text = "dialog"
    compare(d.targetCursor, 0)
    keyClick(data.key)
    compare(targetPicks.count, 2)
    compare(targetPicks.signalArguments[1][0], "card:dddd4444-0000-4000-8000-000000000004",
            "the shown row's key, not the unfiltered row 0")
    compare(picks.count, 0, "no projectChosen at the target step")
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // 4, 5, 8: no cursor and no pick while loading, with no rows or no match.
  function test_with_no_shown_row_there_is_no_cursor_and_enter_picks_nothing_data() {
    return [
      { tag: "loading", over: { targetLoading: true }, filter: "" },
      { tag: "empty", over: { targetRows: [] }, filter: "" },
      { tag: "null", over: { targetRows: null }, filter: "" },
      { tag: "string", over: { targetRows: "x" }, filter: "" },
      { tag: "no-match", over: {}, filter: "zzz" }
    ]
  }

  function test_with_no_shown_row_there_is_no_cursor_and_enter_picks_nothing(data) {
    var d = targetStep(data.over)
    H.find(d, "dispatchTargetFilter").text = data.filter
    compare(d.targetCursor, -1)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(d.targetCursor, -1)
    compare(targetPicks.count, 0)
  }

  // 4
  function test_loading_ending_puts_the_cursor_on_row_0() {
    var d = targetStep({ targetLoading: true })
    compare(d.targetCursor, -1)
    d.targetLoading = false
    compare(d.targetCursor, 0)
  }

  // 8
  function test_clearing_a_filter_that_matched_nothing_brings_the_cursor_back() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    filter.text = "zzz"
    compare(d.targetCursor, -1)
    filter.text = ""
    compare(d.targetCursor, 0)
  }

  // 12
  function test_the_filter_keeps_the_cursor_on_its_key() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    for (var i = 0; i < 4; i++) keyClick(Qt.Key_Down)
    compare(d.targetCursor, 4, "on 1.3 dialog rows")
    typeText("rows")
    compare(H.find(d, "dispatchTargetFilter").text, "rows")
    compare(shownRowCount(d), 1)
    compare(d.targetCursor, 0, "still on 1.3 dialog rows, now row 0")
    H.find(d, "dispatchTargetFilter").text = "story"
    compare(H.find(d, "dispatchTargetTitle0").text, "M4 Run story")
    compare(d.targetCursor, 0, "its row is hidden: shown row 0")
  }

  // 14
  function test_backspace_in_an_empty_filter_goes_back() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 1)
    typeText("ab")
    keyClick(Qt.Key_Backspace)
    compare(filter.text, "a", "Backspace deletes one character")
    compare(backs.count, 1, "and emits nothing")
    keyClick(Qt.Key_Backspace)
    compare(filter.text, "")
    compare(backs.count, 1, "the last character is deleted, not a Back")
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 2, "Backspace in the now-empty field goes back")
    compare(cancels.count, 0)
  }

  // 4: Backspace in an empty filter still goes back while loading.
  function test_backspace_goes_back_while_loading() {
    var d = targetStep({ targetLoading: true })
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 1)
  }

  // 16
  function test_escape_on_the_filter_cancels() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    compare(backs.count, 0)
    compare(targetPicks.count, 0)
  }

  // 17
  function test_the_target_step_focuses_its_filter() {
    var d = targetStep()
    compare(d.focusItem, H.find(d, "dispatchTargetFilter"))
    d.step = "project"
    compare(d.focusItem, H.find(d, "dispatchProjectKeys"))
    d.step = ""
    compare(d.focusItem, H.find(d, "dispatchBase"))
    d.form = null
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  // 18
  function test_the_filter_is_cleared_on_re_entry() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    typeText("zz")
    compare(shownRowCount(d), 0)
    d.step = "form"
    d.step = "target"
    compare(H.find(d, "dispatchTargetFilter").text, "")
    compare(shownRowCount(d), 5)
    compare(d.targetCursor, 0)
    d.shown = false
    H.find(d, "dispatchTargetFilter").text = "zz"
    d.shown = true
    compare(H.find(d, "dispatchTargetFilter").text, "", "showing the dialog at the step clears it too")
  }

  // 19
  function test_back_from_the_form_keeps_the_picked_row() {
    var d = targetStep({ step: "form", targetKey: "card:dddd4444-0000-4000-8000-000000000004" })
    compare(d.targetCursor, -1)
    d.step = "target"
    compare(d.targetCursor, 4)
    verify(H.find(d, "dispatchTargetRow4").hasCursor)
  }

  // 23
  function test_signals_stay_in_their_step() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 0, "no targetPicked at the project step")
    compare(backs.count, 0)
    var e = make()
    e.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(targetPicks.count, 0, "no targetPicked at step \"\"")
    var f = targetStep()
    f.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 1)
    compare(picks.count, 0, "no projectChosen at the target step")
  }

  // 24
  function test_rows_arriving_keep_target_keys_row() {
    var d = targetStep({ targetRows: [], targetLoading: true,
                         targetKey: "card:cccc3333-0000-4000-8000-000000000003" })
    compare(d.targetCursor, -1)
    d.targetRows = tc.targetFixture()
    compare(d.targetCursor, -1, "still loading")
    d.targetLoading = false
    compare(d.targetCursor, 3)
  }

  // Review Focus 3
  function test_a_re_read_drops_the_cursor_until_the_rows_return() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(d.targetCursor, 2)
    d.targetLoading = true
    compare(d.targetCursor, -1)
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 0)
    d.targetLoading = false
    compare(d.targetCursor, 0, "no targetKey: row 0")
    d.targetLoading = true
    d.targetKey = "card:dddd4444-0000-4000-8000-000000000004"
    compare(d.targetCursor, -1, "a key arriving while loading does not move it")
    d.targetLoading = false
    compare(d.targetCursor, 4)
  }

  // Review Focus 2
  function test_keys_on_the_filter_after_leaving_the_target_step_do_nothing() {
    var d = targetStep()
    H.find(d, "dispatchTargetFilter").forceActiveFocus()
    d.step = "form"
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Backspace)
    compare(targetPicks.count, 0)
    compare(backs.count, 0)
    compare(d.targetCursor, -1)
  }

  // 25: a row without a card is still picked by its key.
  function test_a_row_without_a_card_is_picked_by_its_key() {
    var d = targetStep({ targetRows: [{ key: "card:nocard", level: "subtask", card: null, depth: 1 }] })
    compare(d.targetCursor, 0)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 1)
    compare(targetPicks.signalArguments[0][0], "card:nocard")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — `targetCursor` is `undefined` (compare fails `undefined` vs `0`), `Could not set initial property targetKey`, `focusItem` is `dispatchBase` at the target step, Down / Backspace on the filter do nothing, and the `targetPicked` spy reports the signal does not exist.

- [ ] **Step 3: Add the props, the signal, the cursor state and the handlers**

Replace:

```qml
  // RunStore's dispatchTargetLoading: the tree is still being read.
  property bool targetLoading: false
```

with:

```qml
  // RunStore's dispatchTargetLoading: the tree is still being read.
  property bool targetLoading: false
  // RunStore's dispatchTargetKey: the row the cursor lands on when the target
  // step is entered.
  property string targetKey: ""
```

Replace:

```qml
  readonly property Item focusItem: dialog.atProject ? projectKeys : dialog.form ? baseField : cancelButton
```

with:

```qml
  readonly property Item focusItem: dialog.atProject ? projectKeys
    : dialog.atTarget ? targetFilter
    : dialog.form ? baseField : cancelButton
```

Replace:

```qml
  readonly property int projectCursor: projectCursorState.index
```

with:

```qml
  readonly property int projectCursor: projectCursorState.index
  // The target step's cursor: an index in the shown target rows; -1 with no
  // shown row, while loading and at every other step.
  readonly property int targetCursor: targetCursorState.index
```

Replace:

```qml
  signal backRequested()
```

with:

```qml
  signal backRequested()
  signal targetPicked(string key)
```

Replace the handler block:

```qml
  onShownChanged: { arming.armed = false; dialog.syncFields(); dialog.resetProjectCursor() }
```

with:

```qml
  onShownChanged: { arming.armed = false; dialog.syncFields(); dialog.resetProjectCursor(); dialog.resetTargetCursor() }
```

Replace:

```qml
  onStepChanged: dialog.resetProjectCursor()
  onProjectRowsChanged: dialog.followProjectCursor()
  Component.onCompleted: { dialog.syncFields(); dialog.resetProjectCursor() }
```

with:

```qml
  onStepChanged: { dialog.resetProjectCursor(); dialog.resetTargetCursor() }
  onProjectRowsChanged: dialog.followProjectCursor()
  onTargetRowsChanged: dialog.followTargetCursor()
  onTargetLoadingChanged: dialog.followTargetCursor()
  onTargetKeyChanged: dialog.jumpToTargetKey()
  Component.onCompleted: { dialog.syncFields(); dialog.resetProjectCursor(); dialog.resetTargetCursor() }
```

After the `projectCursorState` `QtObject` add:

```qml

  // The target cursor's row and its key, so new rows or a new filter keep it
  // on the same target.
  QtObject {
    id: targetCursorState
    property int index: -1
    property string key: ""
  }
```

- [ ] **Step 4: Add the cursor, pick and key functions**

After `shownTargets()` (added in Task 2) add:

```qml

  // The index of the shown row whose key is `key`; -1 for none.
  function shownTargetIndex(rows, key) {
    for (var i = 0; i < rows.length; i++)
      if (rows[i].key === key) return i
    return -1
  }

  // The cursor onto a shown row, or off with -1; any other index is off.
  function setTargetCursor(index) {
    var rows = dialog.shownTargets()
    if (index < 0 || index >= rows.length) index = -1
    targetCursorState.index = index
    targetCursorState.key = index === -1 ? "" : rows[index].key
  }

  // targetKey's shown row, else shown row 0, else -1.
  function landingTarget() {
    var rows = dialog.shownTargets()
    var at = dialog.targetKey === "" ? -1 : dialog.shownTargetIndex(rows, dialog.targetKey)
    return at >= 0 ? at : rows.length > 0 ? 0 : -1
  }

  // Entering the target step clears the filter and lands the cursor; any
  // other step has no cursor.
  function resetTargetCursor() {
    if (dialog.atTarget) targetFilter.text = ""
    dialog.setTargetCursor(dialog.atTarget ? dialog.landingTarget() : -1)
  }

  // New rows, loading or filter text keep the cursor on its key while that
  // row is shown; else it lands as on entry.
  function followTargetCursor() {
    var at = targetCursorState.key === "" ? -1
      : dialog.shownTargetIndex(dialog.shownTargets(), targetCursorState.key)
    dialog.setTargetCursor(at >= 0 ? at : dialog.landingTarget())
  }

  // A new targetKey moves the cursor onto its row when that row is shown.
  function jumpToTargetKey() {
    if (!dialog.atTarget) return
    var at = dialog.shownTargetIndex(dialog.shownTargets(), dialog.targetKey)
    if (at >= 0) dialog.setTargetCursor(at)
  }

  // Down (1) / Up (-1): the next shown row that way; the cursor stays at
  // either end.
  function moveTargetCursor(by) {
    if (targetCursorState.index === -1) return
    var last = dialog.shownTargets().length - 1
    dialog.setTargetCursor(Math.max(0, Math.min(last, targetCursorState.index + by)))
  }

  // A pick: at the target step and on a shown row only.
  function pickTarget(index) {
    var rows = dialog.shownTargets()
    if (!dialog.atTarget || index < 0 || index >= rows.length) return
    dialog.setTargetCursor(index)
    dialog.targetPicked(rows[index].key)
  }

  // On the filter: Down / Up move the cursor, Return / Enter pick its row,
  // Backspace in an empty filter goes back, Escape cancels; any other key
  // edits the filter.
  function targetFieldKey(event) {
    if (event.key === Qt.Key_Escape) dialog.cancel()
    else if (!dialog.atTarget) return
    else if (event.key === Qt.Key_Down) dialog.moveTargetCursor(1)
    else if (event.key === Qt.Key_Up) dialog.moveTargetCursor(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dialog.pickTarget(targetCursorState.index)
    else if (event.key === Qt.Key_Backspace && targetFilter.text === "") dialog.back()
    else return
    event.accepted = true
  }
```

- [ ] **Step 5: Wire the filter field and the row highlight**

Replace the filter field:

```qml
    TextField {
      id: targetFilter
      objectName: "dispatchTargetFilter"
      visible: dialog.atTarget
      width: parent.width
      foreground: dialog.foregroundColor
      placeholderText: "Filter by title or id…"
    }
```

with:

```qml
    // The target step's keys: focusItem at that step.
    TextField {
      id: targetFilter
      objectName: "dispatchTargetFilter"
      visible: dialog.atTarget
      width: parent.width
      foreground: dialog.foregroundColor
      placeholderText: "Filter by title or id…"
      onTextChanged: dialog.followTargetCursor()
      Keys.onPressed: function(event) { dialog.targetFieldKey(event) }
    }
```

In `component TargetRow`, replace:

```qml
    width: targetFlick.width
    theme: dialog.theme

    Row {
      id: targetLine
```

with:

```qml
    width: targetFlick.width
    theme: dialog.theme
    cursorIndex: dialog.targetCursor

    Row {
      id: targetLine
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed`; no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the target step's cursor, keys and focus"
```

---

### Task 4: Click and hover on a target row, and the cursor kept in view

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (`moveProjectCursor`; `projectFlick`'s `reveal`; new `reveal`, `revealTargetCursor`, `hoverTarget`; a `Timer`; reveal calls in the Task 3 functions; `TargetRow` handlers)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (target step section)

**Interfaces:**
- Consumes (Tasks 2-3): `targetFlick`, `targetColumn`, `targetCursorState`, `setTargetCursor(index)`, `pickTarget(index)`, `resetTargetCursor()`, `followTargetCursor()`, `jumpToTargetKey()`, `moveTargetCursor(by)`, `TargetRow`, `targetStep(over)`, `targetFixture()`.
- Produces: `function reveal(flick, item)` (dialog-level; replaces `projectFlick.reveal(item)`); `function revealTargetCursor()`; `Timer { id: targetReveal }` (interval 0, runs `revealTargetCursor()` once the rows exist); `function hoverTarget(index)`; test helper `longTargets(n)`.

- [ ] **Step 1: Write the failing tests**

Append to the target step section (before the final `}`):

```qml
  // n rows: the board, then n - 1 subtasks at depth 1.
  function longTargets(n) {
    var rows = [{ key: "board", level: "board", card: "board", label: "Whole board", depth: 0 }]
    for (var i = 1; i < n; i++) {
      var id = "e" + ("000000" + i).slice(-7) + "-0000"
      rows.push({ key: "card:" + id, level: "subtask", card: { id: id, title: "subtask " + i, status: "todo" },
                  label: "Subtask \"subtask " + i + "\"", depth: 1 })
    }
    return rows
  }

  // 13
  function test_a_click_on_a_row_picks_it() {
    var d = targetStep()
    click(H.find(d, "dispatchTargetRow3"))
    compare(d.targetCursor, 3)
    compare(targetPicks.count, 1)
    compare(targetPicks.signalArguments[0][0], "card:cccc3333-0000-4000-8000-000000000003")
    compare(cancels.count, 0)
    compare(backs.count, 0)
  }

  // 13
  function test_hovering_a_row_moves_the_cursor() {
    var d = targetStep()
    var row = H.find(d, "dispatchTargetRow2")
    wait(30)
    mouseMove(row, row.width / 2, row.height / 2)
    tryCompare(d, "targetCursor", 2)
    verify(row.hasCursor)
    compare(targetPicks.count, 0)
    compare(row.hoverCursorShape, Qt.PointingHandCursor)
  }

  // 20
  function test_a_long_target_list_keeps_the_cursor_in_view() {
    var d = targetStep({ targetRows: tc.longTargets(30) })
    var list = H.find(d, "dispatchTargetList")
    verify(list.contentHeight > list.height, "the list scrolls")
    compare(list.contentY, 0)
    d.focusItem.forceActiveFocus()
    for (var k = 0; k < 29; k++) keyClick(Qt.Key_Down)
    compare(d.targetCursor, 29)
    var last = H.find(d, "dispatchTargetRow29")
    verify(list.contentY > 0, "the list scrolled")
    verify(last.y >= list.contentY, "the last row's top is in view")
    verify(last.y + last.height <= list.contentY + list.height + 0.5, "the last row's bottom is in view")
    for (var u = 0; u < 29; u++) keyClick(Qt.Key_Up)
    compare(d.targetCursor, 0)
    compare(list.contentY, 0, "back at the top")
  }

  // 19
  function test_back_from_the_form_scrolls_the_picked_row_into_view() {
    var rows = tc.longTargets(30)
    var d = targetStep({ step: "form", targetRows: rows, targetKey: rows[27].key })
    d.step = "target"
    compare(d.targetCursor, 27)
    var list = H.find(d, "dispatchTargetList")
    tryVerify(function() { return list.contentY > 0 }, 1000, "the list scrolled to the picked row")
    var row = H.find(d, "dispatchTargetRow27")
    verify(row.y >= list.contentY, "the row's top is in view")
    verify(row.y + row.height <= list.contentY + list.height + 0.5, "the row's bottom is in view")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — `test_a_click_on_a_row_picks_it` (`targetPicks.count` 0), `test_hovering_a_row_moves_the_cursor` (`targetCursor` stays 0), `test_a_long_target_list_keeps_the_cursor_in_view` (`contentY` stays 0), `test_back_from_the_form_scrolls_the_picked_row_into_view` (`tryVerify` times out).

- [ ] **Step 3: Hoist `reveal` to the dialog**

In `projectFlick`, delete:

```qml

      // Scrolls the least that shows the whole of `item`.
      function reveal(item) {
        if (!item) return
        if (item.y < projectFlick.contentY) projectFlick.contentY = item.y
        else if (item.y + item.height > projectFlick.contentY + projectFlick.height)
          projectFlick.contentY = item.y + item.height - projectFlick.height
      }
```

In `moveProjectCursor`, replace:

```qml
    projectFlick.reveal(projectRepeater.itemAt(next))
```

with:

```qml
    dialog.reveal(projectFlick, projectRepeater.itemAt(next))
```

Before `// Down (1) / Up (-1): the next enabled row that way, scrolled into view; the` (the comment above `moveProjectCursor`) add:

```qml
  // Scrolls `flick` the least that shows the whole of `item`.
  function reveal(flick, item) {
    if (!item) return
    if (item.y < flick.contentY) flick.contentY = item.y
    else if (item.y + item.height > flick.contentY + flick.height)
      flick.contentY = item.y + item.height - flick.height
  }

```

- [ ] **Step 4: Reveal the target cursor, and the row's hover and click**

After the `targetCursorState` `QtObject` add:

```qml

  // Rows a step change, a new key or new rows bring are laid out after the
  // change; the reveal waits for them.
  Timer {
    id: targetReveal
    interval: 0
    onTriggered: dialog.revealTargetCursor()
  }
```

After `jumpToTargetKey()` add (and keep the functions in this order: `jumpToTargetKey`, `revealTargetCursor`, `hoverTarget`, `moveTargetCursor`):

```qml

  // Scrolls the target list the least that shows the cursor's row. A row
  // being replaced can still be a child, so the last one with the name wins.
  function revealTargetCursor() {
    if (targetCursorState.index === -1) return
    targetColumn.forceLayout()
    var name = "dispatchTargetRow" + targetCursorState.index
    var kids = targetColumn.children
    for (var i = kids.length - 1; i >= 0; i--) {
      if (kids[i].objectName === name) {
        dialog.reveal(targetFlick, kids[i])
        return
      }
    }
  }

  // A hover moves the cursor onto a shown row.
  function hoverTarget(index) {
    if (dialog.atTarget) dialog.setTargetCursor(index)
  }
```

Replace `resetTargetCursor`, `followTargetCursor`, `jumpToTargetKey` and `moveTargetCursor` with these (each now reveals):

```qml
  // Entering the target step clears the filter and lands the cursor, scrolled
  // into view; any other step has no cursor.
  function resetTargetCursor() {
    if (dialog.atTarget) targetFilter.text = ""
    dialog.setTargetCursor(dialog.atTarget ? dialog.landingTarget() : -1)
    targetReveal.restart()
  }

  // New rows, loading or filter text keep the cursor on its key while that
  // row is shown; else it lands as on entry.
  function followTargetCursor() {
    var at = targetCursorState.key === "" ? -1
      : dialog.shownTargetIndex(dialog.shownTargets(), targetCursorState.key)
    dialog.setTargetCursor(at >= 0 ? at : dialog.landingTarget())
    targetReveal.restart()
  }

  // A new targetKey moves the cursor onto its row when that row is shown.
  function jumpToTargetKey() {
    if (!dialog.atTarget) return
    var at = dialog.shownTargetIndex(dialog.shownTargets(), dialog.targetKey)
    if (at === -1) return
    dialog.setTargetCursor(at)
    targetReveal.restart()
  }
```

```qml
  // Down (1) / Up (-1): the next shown row that way, scrolled into view; the
  // cursor stays at either end.
  function moveTargetCursor(by) {
    if (targetCursorState.index === -1) return
    var last = dialog.shownTargets().length - 1
    dialog.setTargetCursor(Math.max(0, Math.min(last, targetCursorState.index + by)))
    dialog.revealTargetCursor()
  }
```

In `component TargetRow`, replace:

```qml
    cursorIndex: dialog.targetCursor

    Row {
      id: targetLine
```

with:

```qml
    cursorIndex: dialog.targetCursor
    onHovered: function(index) { dialog.hoverTarget(index) }
    onActivated: dialog.pickTarget(targetRow.index)

    Row {
      id: targetLine
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed`; no `TypeError`/`ReferenceError` lines (the teardown tests included: the `Timer` is the dialog's child, so it never fires after the dialog is gone). The project step's `test_a_long_list_keeps_the_cursor_in_view` still passes through the hoisted `reveal`.

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit status 0; pytest (with `tests/architecture`) green; every QML file `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): a click or hover on a target row picks or moves the cursor, kept in view"
```

---

## Spec coverage check

| spec item | task |
|---|---|
| new props / signals table | 1 (`projectName`, `backRequested`), 2 (`targetRows`, `targetLoading`), 3 (`targetKey`, `targetCursor`, `targetPicked`) |
| valid row; level word; title; short id; depth | 2 |
| filter: control, placeholder, matching, order | 2; cleared on entry: 3 |
| heading; filter and list visibility; status lines; rows; Back + Cancel; Start hidden | 1, 2 |
| every S31-hidden part hidden at the target step | 1 |
| cursor: entry, follow, `targetKey` change, `-1` off-step | 3; scrolled into view: 4 |
| keys table | 3 |
| mouse | 4 (rows), 1 (Back), existing tests (Cancel, backdrop) |
| form step's Back; where Back shows | 1 |
| unchanged: `""` / `"project"` and signals per step | 1 (heading test edit), 3 (`test_signals_stay_in_their_step`) |
| errors and edge inputs table | 2 (malformed, null rows, loading with rows), 3 (loading ends, no match, key naming no row, re-entry), 2 (teardown) |
| tests 1-26 | 1: 3, 15, 21, 22 · 2: 1-8, 25, 26 · 3: 4, 5, 8-12, 14, 16-19, 23-25 · 4: 13, 19, 20 · 27: every run of the file |
<!-- task-pipeline: validated -->
