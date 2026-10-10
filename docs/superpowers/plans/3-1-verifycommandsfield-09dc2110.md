<!-- The spec this plan implements, verbatim. The plan follows the rule below. -->

# 3.1 VerifyCommandsField: the shared verify editor (card 09dc2110)

Narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md`
(the parent): the "UI" bullet of the design (lines 279-282) and "Testing"
(line 321). Parent story 215a0691. Not blocked by any card.

## Inherited constraints

- "the verify editor of S3's `DispatchDialog` becomes a shared
  `ui/components/VerifyCommandsField.qml` (rule: shared before the second use)
  used by `DispatchDialog` and the new `ui/components/ResumeVerifyDialog.qml`"
  (parent lines 279-281). This card does the first half only: the component
  and `DispatchDialog` using it.
- "`tests/ui/components/`: `VerifyCommandsField` (add, remove, opt-out)"
  (parent line 321); the card adds "edit": the new test file covers add,
  edit, remove and opt-out.
- No behaviour change (card): every existing test in
  `tests/ui/components/tst_dispatch_dialog.qml` stays green **unchanged**,
  byte for byte. That file is the regression proof.
- Components render and emit only; they never import `core/` or stores
  (`tests/architecture/test_layers.py`, layer allowlist,
  `test_layers_import_only_what_their_allowlist_permits`, line 214).
- Reuse before writing a second copy (`docs/architecture.md`, "Shared
  components (`ui/components`)" section, line 115 onward; enforced by the
  `GUARDS` table in `tests/architecture/test_layers.py` lines 244-275): the
  field is built from `UI.ThemedText`, `TextField` (from `qs.Ui`),
  `UI.ActionButton` and `UI.Chip`. It contains no `radius: height/2`, no
  `bordered: true`, no `font.family:`, no `CursorSurface {` and no
  `Qt.rgba(0, 0, 0, 0.55)`. It introduces no icon glyph beyond the `+` and `✕`
  text the dialog already uses (`tests/architecture/test_icon_glyphs.py`).
- Docstrings and comments state the contract only, no narrative (card).
- Verification: `bash tests/run.sh` green; it also fails on any `TypeError`,
  `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item`
  or `is not a function` in QML test output (`tests/run.sh` lines 31-32).
  TDD: tests first (card).

## Starting point

`ui/components/DispatchDialog.qml` owns the verify editor inline:

- helpers `storedVerify`, `verifyAt`, `verifyPadded`, `editVerify`,
  `removeVerify`, `addVerify` (lines 174-209) and `verifyRows` (line 66);
- the `Verify` caption, objectName `dispatchVerifyLabel` (lines 313-318);
- `Repeater verifyRepeater` of rows: a `TextField` `dispatchVerify<i>`
  (placeholder `uv run pytest`, Escape goes to `dialog.fieldKey(event)`) and an
  `ActionButton` `dispatchVerifyRemove<i>` (`✕`, visible only with two or more
  rows) (lines 321-358);
- `ActionButton` `dispatchVerifyAdd` (`+`, lines 360-366);
- the opt-out `Chip` `dispatchNoVerify`, text `run without any verification`,
  `active` from `form.allowNoVerification === true`, `busy: !editable`, tint
  `urgent` when active else `dim` (lines 368-378). It is a **chip**, not a
  checkbox (the card's word "checkbox" names the opt-out; the chip stays —
  no behaviour change);
- `syncFields()` re-syncs every row on `shown`/`form` change (lines 214-224,
  122-127).

No test calls these helpers; the tests reach the editor only by objectName
through `tests/helpers/find.js`, which searches into child components'
`children`/`data`, so items inside a nested component are found.

## Scope

- Create `ui/components/VerifyCommandsField.qml`.
- Create `tests/ui/components/tst_verify_commands_field.qml`.
- Modify `ui/components/DispatchDialog.qml`: the inline editor and its helpers
  are replaced by one `UI.VerifyCommandsField`.
- Modify `docs/architecture.md`: add a `VerifyCommandsField` entry to the
  shared-components list, and in the `DispatchDialog` entry (line 153) say its
  verify editor is a `VerifyCommandsField`.

### Out of scope

- `ui/components/ResumeVerifyDialog.qml`, its tests, its Panel mounting and
  any `RunStore` resume-dialog state (parent lines 165-196, 268-271, 281):
  later sibling cards of story 215a0691.
- A configurable opt-out text (the Resume mock-up reads `Resume without any
  verification`, parent line 180): the Resume dialog's card adds it if it
  needs it. This card ships the one text the dispatch uses.
- Validation of the commands (`Runs.validateDispatch`): stays in the store;
  the field emits whatever the user typed.
- `ui/Panel.qml`, `core/`, `RunStore`: unchanged.
- `tests/ui/components/tst_dispatch_dialog.qml`: not edited.
- Any change of layout, text, colour, objectName or signal of the dispatch
  dialog as its tests observe it.

## Behaviour

### The component's interface

`VerifyCommandsField` is a column (width set by its owner) holding, top to
bottom: the `Verify` caption, one row per command, the `+` button, the
opt-out chip.

Properties (owner → field):

| property | type | default | meaning |
|---|---|---|---|
| `theme` | var | `T.Theme {}` | colours and fonts; `null` falls back to `Color.*` like the dialog does |
| `commands` | var | `[]` | the stored command list; a list or the array-like a list arrives as through `createObject`; anything else (missing, `null`, a string, a number) reads as `[]` |
| `allowNoVerification` | bool | `false` | the stored opt-out; the chip is active exactly when this is `true` |
| `editable` | bool | `true` | false disables every row, every remove, `+`, and makes the chip `busy` |
| `objectNamePrefix` | string | `"field"` | prefix of every inner objectName (below), so each owner keeps its own test names |

Read-only: `rows` (int) — `max(1, number of stored commands)`.

Inner objectNames, `P` the prefix: `PVerifyLabel`, `PVerify<i>`,
`PVerifyRemove<i>`, `PVerifyAdd`, `PNoVerify`. With `objectNamePrefix:
"dispatch"` they are exactly today's dispatch names.

Signals (field → owner):

- `commandsEdited(var commands)` — the whole new list (a fresh JS array of
  strings).
- `allowNoVerificationEdited(bool on)` — the new opt-out value.
- `keyPressed(var event)` — every key press in a command row, forwarded
  unhandled; the owner decides (the dispatch cancels on Escape and sets
  `event.accepted`).

Function: `sync()` — sets every row's text to the stored command at its
index, touching only rows whose text differs; emits nothing.

### Rows

- The field shows `rows` rows. Row `i` shows the stored command `i` as text
  (`""` for `undefined`/`null`, `String(value)` otherwise), placeholder
  `uv run pytest`.
- Rows are counted, not listed: a change of `commands` that keeps the length
  keeps every row item (its focus and cursor); only the text of a row whose
  text differs from the new stored value is set.
- A change of `commands` syncs the rows; a newly made row syncs itself.
  Syncing emits nothing.
- An empty, missing or malformed `commands` shows exactly one empty row.

### Edits

The list sent is always the stored commands padded with `""` to `rows`, as
strings, then:

- **edit**: typing in row `i` emits `commandsEdited` with element `i`
  replaced by the row's text — only when that text differs from stored
  command `i`. Feeding the emitted list back as `commands` echoes nothing.
- **add**: a click on `+` emits the padded list with `""` appended
  (`[]` → `["", ""]`, `["a"]` → `["a", ""]`).
- **remove**: `✕` shows on every row only when `rows >= 2`; a click on row
  `i`'s emits the padded list with element `i` spliced out.
- **opt-out**: a click on the chip emits `allowNoVerificationEdited(!active)`.
  The field never changes `commands` or `allowNoVerification` itself: the
  owner feeds the new value back.

### Not editable

With `editable` false: rows, removes and `+` are `enabled: false` (clicks
emit nothing); the chip is `busy` (clicks emit nothing — `Chip`'s own rule).

### DispatchDialog with the field

- One `UI.VerifyCommandsField` replaces the caption, Repeater, `+` and chip,
  at the same place in the form, `width` the form column's,
  `objectNamePrefix: "dispatch"`, `theme: dialog.theme`,
  `editable: dialog.editable`.
- `commands` reads `dialog.form.verify` guarded (`null` without a form);
  `allowNoVerification` is `!!dialog.form && dialog.form.allowNoVerification === true`.
- `commandsEdited(list)` → `fieldEdited("verify", list)`;
  `allowNoVerificationEdited(on)` → `fieldEdited("allowNoVerification", on)`;
  `keyPressed(event)` → `dialog.fieldKey(event)`.
- `syncFields()` calls the field's `sync()` in place of the row loop, so a
  `shown` or `form` change still resets the rows to the form.
- Ordering: `DispatchDialog.onFormChanged` runs `syncFields()` possibly before
  the field's bound `commands` has taken the new `form.verify`, so `sync()` may
  read the previous list. This is harmless and must stay so: setting a row's
  text to the previous stored value emits nothing (the edit rule compares with
  the field's own stored value), and the field's own `commands` change then
  syncs again to the new list. The field never reads `form`; the existing
  `tst_dispatch_dialog.qml` form-swap tests prove no echo.
- The dialog's verify helpers (`storedVerify` … `addVerify`, `verifyRows`) and
  the chip's colour props move into the field. `dialog.urgentColor` stays
  (the refusal and the cost warning read it); `dialog.dimColor` is read by the
  chip alone and is removed. The field derives its own foreground, urgent and
  dim colours from `theme`, falling back to `Color.*` when it is `null`, as the
  dialog's `foregroundColor` / `urgentColor` / `dimColor` do.
- Nulling `theme`, `form`, `target`, `preview` and destroying the dialog stays
  quiet (no `TypeError` in the output).

## Errors and edge cases

| case | behaviour |
|---|---|
| `commands` missing / `null` / a string | one empty row; `+` emits `["", ""]` |
| `commands` contains `null` | that row shows `""`; an emitted list holds `""` there |
| owner feeds back the edit just emitted | same row item, still focused, no second emit |
| owner never feeds back (`commandsEdited` ignored) | the row keeps the typed text until the next `commands` change or `sync()` |
| a single row | no `✕` |
| `editable` false | nothing emits; chip `busy` |
| `theme` set to `null` | renders with `Color.*`, no error |
| Escape in a row of the dispatch dialog | dispatch cancels (unchanged; not while starting) |

## Tests

### New: `tests/ui/components/tst_verify_commands_field.qml`

Tier: QML component test (qmltestrunner, picked up by `tests/run.sh` as any
`tests/**/tst_*.qml`). Why: the contract is the field's rendered items and
signals in isolation; no store or process is involved, so a unit test of the
component alone is the cheapest tier that observes it. Modelled on
`tst_chip.qml` (`TestCase`, `when: windowShown`, `createTemporaryObject`,
`SignalSpy` for `commandsEdited`, `allowNoVerificationEdited`, `keyPressed`,
`H.find` from `../../helpers/find.js`, `UI` from `../../../ui/components`).
Default prefix, so names are `fieldVerify0` etc.

1. **renders one row per command**: `commands: ["a", "b"]` → `fieldVerify0`
   `a`, `fieldVerify1` `b`, no `fieldVerify2`; caption `fieldVerifyLabel`
   reads `Verify`; placeholder `uv run pytest`; no emit.
2. **missing/malformed reads as one empty row** (data-driven: `[]`, `null`,
   `"uv run pytest"`, unset): one row, text `""`, no remove visible, no emit.
3. **edit sends the whole list**: `["a", "b"]`, set `fieldVerify1.text = "b2"`
   → one `commandsEdited(["a", "b2"])`.
4. **an edit fed back echoes nothing and keeps the row**: focus row 0, type,
   feed the emitted list back as `commands` → same item, still `activeFocus`,
   one emit only.
5. **a new `commands` from the owner echoes nothing**: assign a new list →
   rows show it, no emit.
6. **add**: `["a"]` + click `fieldVerifyAdd` → `["a", ""]`; feed back → row 1
   exists, empty, both removes visible, still one emit. `[]` + add →
   `["", ""]`.
7. **remove**: `["a", "b"]`, click `fieldVerifyRemove1` → `["a"]`; click
   `fieldVerifyRemove0` → `["b"]`; one row has no visible remove.
8. **opt-out**: chip `fieldNoVerify` text `run without any verification`,
   inactive by default; click → `allowNoVerificationEdited(true)`, chip still
   inactive until fed back; `allowNoVerification: true` → active, click →
   `false`.
9. **not editable**: `editable: false` → rows, removes, `+` disabled, chip
   `busy`; clicking `+`, a remove and the chip emits nothing.
10. **keys are forwarded**: focus a row, `keyClick(Qt.Key_Escape)` → one
    `keyPressed`; the key is captured inside a handler (`onKeyPressed`), since
    a `SignalSpy` argument is the live event object and is not safe to read
    afterwards. It is `Qt.Key_Escape`.
11. **objectNamePrefix renames every inner item**: `objectNamePrefix:
    "resume"` → `resumeVerifyLabel`, `resumeVerify0`, `resumeVerifyRemove0`
    (with two commands), `resumeVerifyAdd`, `resumeNoVerify` found, no
    `fieldVerify0`.
12. **null theme and destroy are quiet**: set `theme`, `commands` to `null`,
    destroy → no error output (checked by `tests/run.sh`'s grep).

### Existing, unchanged: `tests/ui/components/tst_dispatch_dialog.qml`

Tier: QML component test. Why: it is the "no behaviour change" proof — the
verify-row tests (lines 613-720), the chip tests (lines 456-470), the
editability tests (lines 550-590) and the four-command fit test pass against
the dialog now built on the field. Not edited.

### Existing: `tests/architecture`

Tier: pytest architecture guards. Why: the field must import no store and
add no second copy of a guarded visual pattern or an unknown glyph.

## Plan hand-off notes

- Write the new test file first and watch it fail (component missing), then
  the component, then switch `DispatchDialog` over and run
  `bash tests/run.sh dispatch_dialog` and `bash tests/run.sh verify_commands`,
  then the full `bash tests/run.sh`.
- Keep the field's header comment to its contract: what it shows, the
  properties it reads, the signals it emits, that it never changes its own
  inputs.

---

# 3.1 VerifyCommandsField Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `DispatchDialog`'s inline verify-commands editor into a shared `ui/components/VerifyCommandsField.qml` and make `DispatchDialog` use it with no behaviour change.

**Architecture:** `VerifyCommandsField` is a presentational `Column` (caption, a `Repeater` of counted rows, `+`, an opt-out `Chip`) that reads `commands` / `allowNoVerification` / `editable` / `theme` / `objectNamePrefix` and emits `commandsEdited(list)`, `allowNoVerificationEdited(on)` and `keyPressed(event)`; it never changes its own inputs. `DispatchDialog` mounts one with `objectNamePrefix: "dispatch"`, maps its signals onto `fieldEdited` / `fieldKey`, and its `syncFields()` calls the field's `sync()`.

**Tech Stack:** QML (Qt 6, QtQuick), `qs.Commons` (`Color`, `Style`), `qs.Ui` (`TextField`), QtTest via `qmltestrunner`, pytest architecture guards; everything runs through `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/3-1-verifycommandsfield-09dc2110.md` (prepended above).

## Global Constraints

- No behaviour change: `tests/ui/components/tst_dispatch_dialog.qml` stays green and is **not edited**, byte for byte.
- Components render and emit only; `VerifyCommandsField.qml` imports no `core/` and no store (`tests/architecture/test_layers.py::test_layers_import_only_what_their_allowlist_permits`).
- The field is built from `UI.ThemedText`, `TextField` (from `qs.Ui`), `UI.ActionButton` and `UI.Chip`. It contains no `radius: height/2`, no `bordered: true`, no `font.family:`, no `CursorSurface {` and no `Qt.rgba(0, 0, 0, 0.55)`.
- No icon glyph beyond the `+` and `✕` text the dialog already uses (`tests/architecture/test_icon_glyphs.py`).
- Docstrings and comments state the contract only, no narrative.
- Inner objectNames, `P` the prefix: `PVerifyLabel`, `PVerify<i>`, `PVerifyRemove<i>`, `PVerifyAdd`, `PNoVerify`; default prefix `"field"`.
- Texts verbatim: caption `Verify`, placeholder `uv run pytest`, chip `run without any verification`, buttons `+` and `✕`.
- Verification: `bash tests/run.sh` green; it also fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in QML test output.
- TDD: tests first. Never use `pkill`/`killall`; stop a stuck run with `timeout`.

## Review Focus

1. **A list whose element is `null`** (`["a", null]`): the row shows `""` and an edit of another row emits `""` in that slot, never `"null"` — pinned in Task 1 (`test_a_null_command_reads_as_empty_and_goes_out_as_empty`).
2. **The owner never feeds an edit back, then calls `sync()`**: the row returns to the stored command and nothing is emitted — pinned in Task 1 (`test_sync_resets_an_unfed_row_and_emits_nothing`).
3. **A remove fed back shrinks the rows**: `["a", "b"]` → remove row 0 → owner feeds `["b"]` → one row reading `b`, no `fieldVerify1`, one emit total — pinned in Task 1 (`test_a_remove_fed_back_leaves_the_remaining_command`).
4. **The dialog's `onFormChanged` syncing before the field's bound `commands` updates** (the stale read the spec calls harmless): a fed-back edit keeps the same focused row and echoes nothing — pinned by the unchanged `tst_dispatch_dialog.qml::test_a_verify_row_survives_the_owner_feeding_its_edit_back` and `test_plus_adds_an_empty_command`, run in Task 2 Step 4; the field re-syncs on its own `onCommandsChanged`, which Task 1 implements.
5. **`theme` nulled while mounted, then destroyed**: renders with `Color.*`, no `TypeError` — pinned in Task 1 (`test_a_null_theme_and_destroy_are_quiet`) and in Task 2 by the unchanged `test_nulling_every_object_prop_and_destroying_is_quiet`.

---

## File Structure

- Create `ui/components/VerifyCommandsField.qml` — the shared verify editor (one responsibility: show the stored commands and emit the user's edits).
- Create `tests/ui/components/tst_verify_commands_field.qml` — the field's component tests.
- Modify `ui/components/DispatchDialog.qml` — drop the verify helpers, `verifyRows`, `dimColor` and the inline editor; mount `UI.VerifyCommandsField`.
- Modify `docs/architecture.md` — add the `VerifyCommandsField` entry; the `DispatchDialog` entry names it.

---

### Task 1: VerifyCommandsField component

**Files:**
- Create: `ui/components/VerifyCommandsField.qml`
- Test: `tests/ui/components/tst_verify_commands_field.qml`

**Interfaces:**
- Consumes: `UI.ThemedText` (`variant`, `theme`, `text`), `TextField` from `qs.Ui` (`foreground`, `placeholderText`, `text`, `enabled`), `UI.ActionButton` (`text`, `theme`, `enabled`, `clicked()`), `UI.Chip` (`theme`, `text`, `active`, `busy`, `tint`, `clicked()`), `T.Theme` (`foreground`, `urgent`, `dim`), `Color.foreground` / `Color.urgent`, `Style.space(n)`.
- Produces (Task 2 relies on these exact names):
  - `property var theme` (default `T.Theme {}`), `property var commands` (default `[]`), `property bool allowNoVerification` (default `false`), `property bool editable` (default `true`), `property string objectNamePrefix` (default `"field"`)
  - `readonly property int rows`
  - `signal commandsEdited(var commands)`, `signal allowNoVerificationEdited(bool on)`, `signal keyPressed(var event)`
  - `function sync()`

- [ ] **Step 1: Write the failing test file**

Create `tests/ui/components/tst_verify_commands_field.qml`:

```qml
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "VerifyCommandsField"
  when: windowShown
  visible: true
  width: 480; height: 400

  Component { id: fieldC; UI.VerifyCommandsField { width: 480 } }
  SignalSpy { id: edits; signalName: "commandsEdited" }
  SignalSpy { id: optOuts; signalName: "allowNoVerificationEdited" }
  SignalSpy { id: keys; signalName: "keyPressed" }

  property int lastKey: -1

  function make(props) {
    var f = createTemporaryObject(fieldC, tc, props || {})
    edits.target = f; optOuts.target = f; keys.target = f
    edits.clear(); optOuts.clear(); keys.clear()
    tc.lastKey = -1
    wait(30)
    return f
  }
  // A row that just appeared is laid out on the next frame: wait for it, so
  // the click lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  function test_it_renders_one_row_per_command() {
    var f = make({ commands: ["a", "b"] })
    compare(H.find(f, "fieldVerifyLabel").text, "Verify")
    compare(H.find(f, "fieldVerify0").text, "a")
    compare(H.find(f, "fieldVerify1").text, "b")
    verify(!H.find(f, "fieldVerify2"), "two rows only")
    compare(H.find(f, "fieldVerify0").placeholderText, "uv run pytest")
    compare(f.rows, 2)
    compare(edits.count, 0)
  }

  function test_missing_or_malformed_commands_read_as_one_empty_row_data() {
    return [
      { tag: "empty", props: { commands: [] } },
      { tag: "null", props: { commands: null } },
      { tag: "a-string", props: { commands: "uv run pytest" } },
      { tag: "a-number", props: { commands: 3 } },
      { tag: "unset", props: {} }
    ]
  }

  function test_missing_or_malformed_commands_read_as_one_empty_row(data) {
    var f = make(data.props)
    compare(f.rows, 1)
    compare(H.find(f, "fieldVerify0").text, "")
    verify(!H.find(f, "fieldVerify1"), "one row only")
    var remove = H.find(f, "fieldVerifyRemove0")
    verify(!remove || !remove.visible, "no remove on the only row")
    compare(edits.count, 0)
  }

  function test_an_edit_sends_the_whole_list() {
    var f = make({ commands: ["a", "b"] })
    H.find(f, "fieldVerify1").text = "b2"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a", "b2"])
  }

  function test_an_edit_fed_back_echoes_nothing_and_keeps_the_row() {
    var f = make({ commands: ["a"] })
    var row0 = H.find(f, "fieldVerify0")
    row0.forceActiveFocus()
    row0.text = "a2"
    compare(edits.count, 1)
    f.commands = edits.signalArguments[0][0]
    verify(H.find(f, "fieldVerify0") === row0, "the same row, not a new one")
    compare(row0.text, "a2")
    verify(row0.activeFocus, "still focused")
    compare(edits.count, 1)
  }

  function test_a_new_list_from_the_owner_echoes_nothing() {
    var f = make({ commands: ["a"] })
    f.commands = ["x", "y"]
    compare(H.find(f, "fieldVerify0").text, "x")
    compare(H.find(f, "fieldVerify1").text, "y")
    compare(edits.count, 0)
  }

  function test_plus_appends_an_empty_command() {
    var f = make({ commands: ["a"] })
    click(H.find(f, "fieldVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a", ""])
    f.commands = ["a", ""]
    verify(H.find(f, "fieldVerify1"), "the new row")
    compare(H.find(f, "fieldVerify1").text, "")
    verify(H.find(f, "fieldVerifyRemove0").visible)
    verify(H.find(f, "fieldVerifyRemove1").visible)
    compare(edits.count, 1, "the new row echoes nothing")
  }

  function test_plus_on_an_empty_list_gives_two_empty_commands() {
    var f = make({ commands: [] })
    click(H.find(f, "fieldVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["", ""])
  }

  function test_remove_drops_that_row() {
    var f = make({ commands: ["a", "b"] })
    click(H.find(f, "fieldVerifyRemove1"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a"])
    click(H.find(f, "fieldVerifyRemove0"))
    compare(edits.count, 2)
    compare(edits.signalArguments[1][0], ["b"])
  }

  function test_a_remove_fed_back_leaves_the_remaining_command() {
    var f = make({ commands: ["a", "b"] })
    click(H.find(f, "fieldVerifyRemove0"))
    compare(edits.signalArguments[0][0], ["b"])
    f.commands = ["b"]
    wait(0)
    compare(H.find(f, "fieldVerify0").text, "b")
    verify(!H.find(f, "fieldVerify1"), "one row only")
    verify(!H.find(f, "fieldVerifyRemove0").visible, "no remove on the only row")
    compare(edits.count, 1)
  }

  function test_one_row_has_no_remove() {
    var f = make({ commands: ["a"] })
    var remove = H.find(f, "fieldVerifyRemove0")
    verify(!remove || !remove.visible)
  }

  function test_a_null_command_reads_as_empty_and_goes_out_as_empty() {
    var f = make({ commands: ["a", null] })
    compare(H.find(f, "fieldVerify1").text, "")
    compare(edits.count, 0)
    H.find(f, "fieldVerify0").text = "a2"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], ["a2", ""])
  }

  function test_sync_resets_an_unfed_row_and_emits_nothing() {
    var f = make({ commands: ["a"] })
    var row0 = H.find(f, "fieldVerify0")
    row0.text = "typed"
    compare(edits.count, 1)
    compare(row0.text, "typed", "kept until the owner says otherwise")
    f.sync()
    compare(row0.text, "a")
    compare(edits.count, 1)
  }

  function test_the_opt_out_chip_emits_the_flip_and_waits_for_the_owner() {
    var f = make({ commands: ["a"] })
    var chip = H.find(f, "fieldNoVerify")
    compare(chip.text, "run without any verification")
    compare(chip.active, false)
    click(chip)
    compare(optOuts.count, 1)
    compare(optOuts.signalArguments[0][0], true)
    compare(chip.active, false, "the field never changes its own input")
    f.allowNoVerification = true
    compare(chip.active, true)
    click(chip)
    compare(optOuts.count, 2)
    compare(optOuts.signalArguments[1][0], false)
    compare(edits.count, 0)
  }

  function test_not_editable_disables_everything_and_emits_nothing() {
    var f = make({ commands: ["a", "b"], editable: false })
    compare(H.find(f, "fieldVerify0").enabled, false)
    compare(H.find(f, "fieldVerify1").enabled, false)
    compare(H.find(f, "fieldVerifyRemove0").enabled, false)
    compare(H.find(f, "fieldVerifyAdd").enabled, false)
    compare(H.find(f, "fieldNoVerify").busy, true)
    click(H.find(f, "fieldVerifyAdd"))
    click(H.find(f, "fieldVerifyRemove0"))
    click(H.find(f, "fieldNoVerify"))
    compare(edits.count, 0)
    compare(optOuts.count, 0)
  }

  function test_keys_in_a_row_are_forwarded() {
    var f = make({ commands: ["a"] })
    f.keyPressed.connect(function(event) { tc.lastKey = event.key })
    H.find(f, "fieldVerify0").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(keys.count, 1)
    compare(tc.lastKey, Qt.Key_Escape)
  }

  function test_the_prefix_renames_every_inner_item() {
    var f = make({ commands: ["a", "b"], objectNamePrefix: "resume" })
    verify(H.find(f, "resumeVerifyLabel"))
    verify(H.find(f, "resumeVerify0"))
    verify(H.find(f, "resumeVerifyRemove0"))
    verify(H.find(f, "resumeVerifyAdd"))
    verify(H.find(f, "resumeNoVerify"))
    verify(!H.find(f, "fieldVerify0"), "no default names left")
  }

  function test_a_null_theme_and_destroy_are_quiet() {
    var f = make({ commands: ["a", "b"], allowNoVerification: true })
    f.theme = null
    wait(0)
    compare(H.find(f, "fieldVerify0").text, "a")
    f.commands = null
    wait(0)
    compare(H.find(f, "fieldVerify0").text, "")
    compare(edits.count, 0)
    f.destroy()
    wait(0)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash tests/run.sh verify_commands`
Expected: FAIL — the `== tests/ui/components/tst_verify_commands_field.qml` section reports `VerifyCommandsField is not a type` (component missing), and the script exits non-zero.

- [ ] **Step 3: Write the component**

Create `ui/components/VerifyCommandsField.qml`:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// The verify editor: a `Verify` caption, one text row per stored command, `+`,
// and the `run without any verification` chip. Reads `commands` and
// `allowNoVerification` and never changes them: an edit, `+` or `✕` emits
// commandsEdited(list), the whole list of rows padded with "" and as strings;
// the chip emits allowNoVerificationEdited(!active); every key pressed in a row
// goes out unhandled as keyPressed(event). A row emits only when its text
// differs from the stored command, so feeding a list back echoes nothing.
// Inner objectNames start with objectNamePrefix: <P>VerifyLabel, <P>Verify<i>,
// <P>VerifyRemove<i>, <P>VerifyAdd, <P>NoVerify.
Column {
  id: field
  spacing: Style.space(8)

  // Colours and fonts; null falls back to the shell's Color.
  property var theme: T.Theme {}
  // A list, or the array-like a list arrives as through createObject; anything
  // else reads as [].
  property var commands: []
  property bool allowNoVerification: false
  // False disables every row, remove and `+`, and makes the chip busy.
  property bool editable: true
  property string objectNamePrefix: "field"

  // The rows are counted, not listed: a list of the same length keeps every
  // row (its focus, its cursor).
  readonly property int rows: Math.max(1, field.stored().length)

  readonly property color foregroundColor: field.theme ? field.theme.foreground : Color.foreground
  readonly property color urgentColor: field.theme ? field.theme.urgent : Color.urgent
  readonly property color dimColor: field.theme ? field.theme.dim : Color.foreground

  signal commandsEdited(var commands)
  signal allowNoVerificationEdited(bool on)
  signal keyPressed(var event)

  onCommandsChanged: field.sync()

  function stored() {
    var list = field.commands
    if (!list || typeof list !== "object" || typeof list.length !== "number") return []
    return Array.prototype.slice.call(list)
  }

  function commandAt(index) {
    var value = field.stored()[index]
    return value === undefined || value === null ? "" : String(value)
  }

  // A fresh copy of the stored commands, padded with "" to the rows shown.
  function padded() {
    var list = []
    for (var i = 0; i < field.rows; i++) list.push(field.commandAt(i))
    return list
  }

  function edit(index, text) {
    var list = field.padded()
    list[index] = text
    field.commandsEdited(list)
  }

  function remove(index) {
    var list = field.padded()
    list.splice(index, 1)
    field.commandsEdited(list)
  }

  function add() {
    var list = field.padded()
    list.push("")
    field.commandsEdited(list)
  }

  // Sets every row's text to its stored command, touching only rows that
  // differ; emits nothing. New rows sync themselves when they are made.
  function sync() {
    for (var i = 0; i < rowRepeater.count; i++) {
      var row = rowRepeater.itemAt(i)
      if (row) row.sync()
    }
  }

  UI.ThemedText {
    objectName: field.objectNamePrefix + "VerifyLabel"
    variant: "caption"
    theme: field.theme
    text: "Verify"
  }

  Repeater {
    id: rowRepeater
    model: field.rows

    Row {
      id: commandRow
      required property int index
      width: parent ? parent.width : 0
      spacing: Style.space(8)

      function sync() {
        var want = field.commandAt(commandRow.index)
        if (commandField.text !== want) commandField.text = want
      }

      Component.onCompleted: commandRow.sync()

      TextField {
        id: commandField
        objectName: field.objectNamePrefix + "Verify" + commandRow.index
        width: Math.max(0, commandRow.width - (removeButton.visible ? removeButton.width + commandRow.spacing : 0))
        foreground: field.foregroundColor
        placeholderText: "uv run pytest"
        enabled: field.editable
        onTextChanged: if (text !== field.commandAt(commandRow.index)) field.edit(commandRow.index, text)
        Keys.onPressed: function(event) { field.keyPressed(event) }
      }

      UI.ActionButton {
        id: removeButton
        objectName: field.objectNamePrefix + "VerifyRemove" + commandRow.index
        visible: field.rows >= 2
        text: "✕"
        enabled: field.editable
        theme: field.theme
        onClicked: field.remove(commandRow.index)
      }
    }
  }

  UI.ActionButton {
    objectName: field.objectNamePrefix + "VerifyAdd"
    text: "+"
    enabled: field.editable
    theme: field.theme
    onClicked: field.add()
  }

  // The opt-out from verification is a chip, not a checkbox.
  UI.Chip {
    id: noVerifyChip
    objectName: field.objectNamePrefix + "NoVerify"
    theme: field.theme
    text: "run without any verification"
    active: field.allowNoVerification
    busy: !field.editable
    tint: noVerifyChip.active ? field.urgentColor : field.dimColor
    onClicked: field.allowNoVerificationEdited(!noVerifyChip.active)
  }
}
```

Notes for the implementer:
- `rows` depends on `commands` through `stored()`; QML records `field.commands` as a dependency because `stored()` reads it inside the binding.
- `padded()` uses `field.rows` (= `max(1, stored length)`), which equals the old `verifyPadded()` loop bound.
- A Repeater row's `parent` is the `Column`, so `width: parent ? parent.width : 0` takes the field's width.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash tests/run.sh verify_commands`
Expected: pytest passes, then `== tests/ui/components/tst_verify_commands_field.qml` prints `Totals: N passed, 0 failed` with no `FAIL!` line and no `TypeError`/`ReferenceError`/`non-existent`/`Unable to assign`/`is not a function` line; exit status 0.

If `test_keys_in_a_row_are_forwarded` reports `keys.count` 0, check that `Keys.onPressed` is on the `TextField` and that the test calls `forceActiveFocus()` on `fieldVerify0` before `keyClick` — the `qs.Ui` test stub `TextField` is a `TextInput`, so it takes focus directly.

- [ ] **Step 5: Run the architecture guards**

Run: `timeout 300 python3 -m pytest tests/architecture -q` (or `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q` if `python3` has no pytest)
Expected: all pass (no store import, no guarded pattern, `+`/`✕` only).

- [ ] **Step 6: Commit**

```bash
git add ui/components/VerifyCommandsField.qml tests/ui/components/tst_verify_commands_field.qml
git commit -m "feat(ui): VerifyCommandsField, the shared verify-commands editor"
```

---

### Task 2: DispatchDialog uses VerifyCommandsField; docs

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (lines 64-66 `verifyRows`, line 78 `dimColor`, lines 169-209 verify helpers, lines 211-225 `syncFields`, lines 313-378 inline editor)
- Modify: `docs/architecture.md:153` and the shared-components list (lines 114-155)
- Test (unchanged, the regression proof): `tests/ui/components/tst_dispatch_dialog.qml`

**Interfaces:**
- Consumes (from Task 1): `UI.VerifyCommandsField` with `theme`, `commands`, `allowNoVerification`, `editable`, `objectNamePrefix`, `commandsEdited(var commands)`, `allowNoVerificationEdited(bool on)`, `keyPressed(var event)`, `sync()`.
- Produces: nothing new. `DispatchDialog`'s public props, signals and objectNames (`dispatchVerifyLabel`, `dispatchVerify<i>`, `dispatchVerifyRemove<i>`, `dispatchVerifyAdd`, `dispatchNoVerify`) are unchanged. `dialog.urgentColor` stays; `dialog.dimColor`, `dialog.verifyRows` and the helpers `storedVerify`, `verifyAt`, `verifyPadded`, `editVerify`, `removeVerify`, `addVerify` are removed (no test or other file reads them — confirm with the grep in Step 1).

- [ ] **Step 1: Confirm nothing outside the dialog reads what is removed**

Run: `grep -rn "verifyRows\|storedVerify\|verifyAt\|verifyPadded\|editVerify\|removeVerify\|addVerify\|dimColor\|verifyRepeater\|noVerifyChip" ui core tests --include=*.qml --include=*.js`
Expected: matches only in `ui/components/DispatchDialog.qml` (and the new `ui/components/VerifyCommandsField.qml`'s own `dimColor` / `noVerifyChip`). If anything else (for example `ui/Panel.qml`) reads `dispatchDialog.dimColor` or a helper, stop and report it — the spec says only the chip reads them.

- [ ] **Step 2: Establish the baseline (the regression proof is green before the change)**

Run: `timeout 600 bash tests/run.sh dispatch_dialog`
Expected: `== tests/ui/components/tst_dispatch_dialog.qml` with `Totals: N passed, 0 failed`; exit 0. Record N. This test file is the failing-test-first guard for this refactor: it must give the same `N passed, 0 failed` after Step 3, without editing it.

- [ ] **Step 3: Replace the inline editor with the field**

In `ui/components/DispatchDialog.qml`:

(a) Delete these lines (64-66):

```qml
  // The verify rows are counted, not listed: typing in a row sends a list of
  // the same length, so the row (its focus, its cursor) is never recreated.
  readonly property int verifyRows: Math.max(1, dialog.storedVerify().length)
```

(b) Delete this line (78), keeping `foregroundColor` and `urgentColor` above it:

```qml
  readonly property color dimColor: dialog.theme ? dialog.theme.dim : Color.foreground
```

(c) Delete the verify helpers block (from the comment `// The stored commands: a list, or the array-like a list arrives as through` through the closing `}` of `function addVerify()`), i.e. exactly:

```qml
  // The stored commands: a list, or the array-like a list arrives as through
  // createObject; anything else (missing, a string, null) reads as []. Read
  // straight from `form`, never through a bound property, which a formChanged
  // handler could still find holding the previous list.
  function storedVerify() {
    var verify = dialog.form ? dialog.form.verify : null
    if (!verify || typeof verify !== "object" || typeof verify.length !== "number") return []
    return Array.prototype.slice.call(verify)
  }

  function verifyAt(index) {
    var value = dialog.storedVerify()[index]
    return value === undefined || value === null ? "" : String(value)
  }

  // A fresh copy of the stored commands, padded with "" to the rows shown.
  function verifyPadded() {
    var stored = dialog.storedVerify(), list = []
    for (var i = 0; i < Math.max(1, stored.length); i++)
      list.push(stored[i] === undefined || stored[i] === null ? "" : String(stored[i]))
    return list
  }

  function editVerify(index, text) {
    var list = dialog.verifyPadded()
    list[index] = text
    dialog.fieldEdited("verify", list)
  }

  function removeVerify(index) {
    var list = dialog.verifyPadded()
    list.splice(index, 1)
    dialog.fieldEdited("verify", list)
  }

  function addVerify() {
    var list = dialog.verifyPadded()
    list.push("")
    dialog.fieldEdited("verify", list)
  }

```

(d) In `syncFields()`, replace:

```qml
    // New rows sync themselves when the Repeater makes them.
    for (var i = 0; i < verifyRepeater.count; i++) {
      var row = verifyRepeater.itemAt(i)
      if (row) row.sync()
    }
```

with:

```qml
    verifyField.sync()
```

(e) Replace the whole inline editor — from

```qml
      UI.ThemedText {
        objectName: "dispatchVerifyLabel"
```

through the end of the `UI.Chip { id: noVerifyChip ... }` block, i.e. exactly:

```qml
      UI.ThemedText {
        objectName: "dispatchVerifyLabel"
        variant: "caption"
        theme: dialog.theme
        text: "Verify"
      }

      Repeater {
        id: verifyRepeater
        model: dialog.verifyRows

        Row {
          id: verifyRow
          required property int index
          width: parent ? parent.width : 0
          spacing: Style.space(8)

          function sync() {
            var want = dialog.verifyAt(verifyRow.index)
            if (verifyField.text !== want) verifyField.text = want
          }

          Component.onCompleted: verifyRow.sync()

          TextField {
            id: verifyField
            objectName: "dispatchVerify" + verifyRow.index
            width: Math.max(0, verifyRow.width - (removeButton.visible ? removeButton.width + verifyRow.spacing : 0))
            foreground: dialog.foregroundColor
            placeholderText: "uv run pytest"
            enabled: dialog.editable
            onTextChanged: if (text !== dialog.verifyAt(verifyRow.index)) dialog.editVerify(verifyRow.index, text)
            Keys.onPressed: function(event) { dialog.fieldKey(event) }
          }

          UI.ActionButton {
            id: removeButton
            objectName: "dispatchVerifyRemove" + verifyRow.index
            visible: dialog.verifyRows >= 2
            text: "✕"
            enabled: dialog.editable
            theme: dialog.theme
            onClicked: dialog.removeVerify(verifyRow.index)
          }
        }
      }

      UI.ActionButton {
        objectName: "dispatchVerifyAdd"
        text: "+"
        enabled: dialog.editable
        theme: dialog.theme
        onClicked: dialog.addVerify()
      }

      // The opt-out from verification is a chip, so the form adds no checkbox.
      UI.Chip {
        id: noVerifyChip
        objectName: "dispatchNoVerify"
        theme: dialog.theme
        text: "run without any verification"
        active: !!dialog.form && dialog.form.allowNoVerification === true
        busy: !dialog.editable
        tint: noVerifyChip.active ? dialog.urgentColor : dialog.dimColor
        onClicked: dialog.fieldEdited("allowNoVerification", !noVerifyChip.active)
      }
```

with:

```qml
      UI.VerifyCommandsField {
        id: verifyField
        width: parent.width
        objectNamePrefix: "dispatch"
        theme: dialog.theme
        commands: dialog.form ? dialog.form.verify : null
        allowNoVerification: !!dialog.form && dialog.form.allowNoVerification === true
        editable: dialog.editable
        onCommandsEdited: function(commands) { dialog.fieldEdited("verify", commands) }
        onAllowNoVerificationEdited: function(on) { dialog.fieldEdited("allowNoVerification", on) }
        onKeyPressed: function(event) { dialog.fieldKey(event) }
      }
```

The field's own `spacing: Style.space(8)` equals the form column's, so the caption, rows, `+` and chip keep their positions.

- [ ] **Step 4: Run the dispatch dialog tests (unchanged) and the field tests**

Run: `timeout 600 bash tests/run.sh dispatch_dialog`
Expected: `Totals: N passed, 0 failed` with the same N as Step 2, no error-pattern lines, exit 0. `git diff --stat tests/ui/components/tst_dispatch_dialog.qml` prints nothing.

Run: `timeout 600 bash tests/run.sh verify_commands`
Expected: `Totals: … passed, 0 failed`, exit 0.

If `test_a_verify_row_survives_the_owner_feeding_its_edit_back` or `test_plus_adds_an_empty_command` fails with an extra emit, the field's row is comparing with something other than `field.commandAt(index)` — the edit rule must compare with the field's own `commands`, never `form`.

- [ ] **Step 5: Update `docs/architecture.md`**

(a) In the shared-components list, replace:

```markdown
`RunToast` (the run toasts, oldest at the top:
```

with:

```markdown
`VerifyCommandsField` (the verify editor shared by dialogs: a `Verify` caption, one `TextField` per stored command (placeholder `uv run pytest`) with a `✕` on every row once there are two, `+`, and the `run without any verification` `Chip`, `urgent` while active; presentation only -- the owner passes `commands` (anything but a list reads as `[]`, shown as one empty row), `allowNoVerification`, `editable` (false disables the rows and buttons and makes the chip busy), `theme` and `objectNamePrefix` (inner names `<P>VerifyLabel`, `<P>Verify<i>`, `<P>VerifyRemove<i>`, `<P>VerifyAdd`, `<P>NoVerify`), and handles `commandsEdited(commands)` -- the whole list, rows padded with `""`, emitted only when a row differs from `commands`, so feeding it back echoes nothing -- `allowNoVerificationEdited(on)` and `keyPressed(event)` (every key in a row, unhandled); the field never changes its own inputs, and `sync()` resets the rows to `commands`. The rows are counted, not listed, so typing never recreates the row under the cursor),
`RunToast` (the run toasts, oldest at the top:
```

(b) In the `DispatchDialog` entry (line 153), replace:

```markdown
a form of Base and Prefix text fields, one Verify field per command with `+` and `✕`, a `run without any verification` `Chip` and a Parallel field;
```

with:

```markdown
a form of Base and Prefix text fields, a `VerifyCommandsField` (prefix `dispatch`: one Verify field per command with `+` and `✕`, and the `run without any verification` `Chip`) and a Parallel field;
```

and replace:

```markdown
The verify rows are counted, not listed, so typing never recreates the row under the cursor.
```

with:

```markdown
Escape in a verify row reaches `fieldKey` through the field's `keyPressed`.
```

- [ ] **Step 6: Run the full suite**

Run: `timeout 1200 bash tests/run.sh`
Expected: pytest all pass; every `== tests/...tst_*.qml` section shows `0 failed`; no `TypeError`/`ReferenceError`/`non-existent`/`Unable to assign`/`anchors on an item`/`is not a function` line; exit status 0.

- [ ] **Step 7: Commit**

```bash
git add ui/components/DispatchDialog.qml docs/architecture.md
git commit -m "refactor(ui): DispatchDialog's verify editor is a VerifyCommandsField"
```

---

## Self-review

- **Spec coverage:** component interface (props, `rows`, names, signals, `sync()`) → Task 1 Step 3; rows/edits/not-editable rules and all twelve spec tests → Task 1 Step 1 (tests 1-12 map to `test_it_renders_one_row_per_command`, `test_missing_or_malformed…` (adds `a-number`), `test_an_edit_sends_the_whole_list`, `test_an_edit_fed_back…`, `test_a_new_list_from_the_owner…`, `test_plus_appends…` + `test_plus_on_an_empty_list…`, `test_remove_drops_that_row` + `test_one_row_has_no_remove`, `test_the_opt_out_chip…`, `test_not_editable…`, `test_keys_in_a_row_are_forwarded`, `test_the_prefix_renames…`, `test_a_null_theme_and_destroy_are_quiet`); DispatchDialog mounting, signal mapping, `syncFields()` → `sync()`, helpers and `dimColor` removed, `urgentColor` kept → Task 2 Step 3; unchanged dispatch tests → Task 2 Steps 2 and 4; docs → Task 2 Step 5; architecture guards → Task 1 Step 5 and Task 2 Step 6.
- **Placeholders:** none; every code step carries the code.
- **Type consistency:** `commandsEdited(var commands)`, `allowNoVerificationEdited(bool on)`, `keyPressed(var event)`, `sync()`, `objectNamePrefix` are spelled identically in Task 1's component, its tests and Task 2's mounting.
- **Review Focus:** each of the five lines has a named test in Task 1 or an unchanged dispatch test run in Task 2.
<!-- task-pipeline: validated -->
