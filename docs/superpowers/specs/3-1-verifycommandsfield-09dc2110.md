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
