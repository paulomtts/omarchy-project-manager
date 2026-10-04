# 3.1 TypedConfirmDialog: a `confirmWord` property (card bba42f66)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md`
(S3): "Design" bullet on `TypedConfirmDialog` (lines 70-74), the cancel
confirmation sketch (lines 92-98) and "Testing" (lines 157-158). Parent story
f27e3b01. Not blocked by any card.

## Inherited constraints

- "`TypedConfirmDialog` is written for project delete (it validates with
  `Projects.isDeleteConfirmed`). Generalise it: a `confirmWord` property
  (default keeps today's behaviour) and `Projects.isDeleteConfirmed` stays for
  its caller." (parent lines 70-73).
- "Cancel asks for the word `cancel`." (parent line 73) — this card makes the
  word configurable; the Cancel caller itself is a sibling card.
- "This is the only change to an existing component; its tests are extended,
  not rewritten." (parent lines 73-74). The five existing tests in
  `tests/ui/tst_typed_confirm_dialog.qml` stay as they are, byte for byte.
- "Extended `TypedConfirmDialog` tests: default word unchanged for project
  delete, `cancel` word for runs." (parent lines 157-158).
- Shared components are reused, not copied (`docs/architecture.md` lines
  103-111, which lists `TypedConfirmDialog`); `tests/architecture` must stay
  green (card). No new component and no icon glyph is introduced.
- The dialog "Renders and emits only" (its header comment,
  `ui/components/TypedConfirmDialog.qml` lines 8-9): no store access, no
  process, no side effect is added.
- Verification: `bash tests/run.sh` green, which also fails on any
  `TypeError`, `ReferenceError` or `Unable to assign` in QML test output
  (`tests/run.sh` lines 31-32). TDD: tests first (card).

## Starting point

- `ui/components/TypedConfirmDialog.qml` hard-wires the word twice:
  line 33 `readonly property bool confirmed: Projects.isDeleteConfirmed(field.text)`
  and line 78 `placeholderText: "delete"`.
- Both gates read `confirmed`: the Return/Enter handler on the field
  (lines 88-91) and the accept button's `enabled` (line 121).
- `Projects.isDeleteConfirmed(text)` (`core/domain/projects.js` lines 31-35):
  `String(text ?? "").trim().toLowerCase() === "delete"` (undefined/null count
  as `""`). It is also used by `core/stores/ProjectDeleteStore.qml` line 49 and
  tested in `tests/core/domain/tst_projects.qml` line 24.
- Callers: `ui/Panel.qml` line 590 (`deleteModal`, project delete, typed text
  owned by `appStores.deleter`) and line 612 (`memoryConfirm`, memory delete).
  Neither sets a word; both messages already say "Type delete".

## Scope

Modify `ui/components/TypedConfirmDialog.qml` and extend
`tests/ui/tst_typed_confirm_dialog.qml`. Nothing else.

### Out of scope

- The Cancel-run caller: opening a `TypedConfirmDialog` with
  `confirmWord: "cancel"`, its message/labels ("Keep running" / "Cancel run"),
  `RunControls.qml`, `RunStore.control`, `Shortcuts.qml` wiring (parent lines
  57-76, 92-104): sibling cards of story f27e3b01.
- `core/domain/projects.js`: `isDeleteConfirmed` is not changed, renamed or
  removed; `ProjectDeleteStore.qml` keeps calling it.
- `ui/Panel.qml`: neither existing caller is edited.
- `tests/core/domain/tst_projects.qml`, `tests/ui/tst_delete_flow.qml`,
  `tests/ui/tst_shortcuts_delete.qml`: untouched; they must keep passing as the
  regression proof that project delete is unchanged.
- The dialog's `message`, `detail`, labels and layout: the caller writes the
  "Type … to confirm" wording; the dialog adds none.
- `docs/architecture.md`: left for the story's docs card.

## Behaviour

### The property

- `TypedConfirmDialog` gains `property string confirmWord`, default
  `"delete"`.

### When the dialog counts as confirmed

`confirmed` is true exactly when the field's text, with surrounding whitespace
removed and lower-cased, equals `confirmWord` with surrounding whitespace
removed and lower-cased — and that trimmed word is not empty.

- Default word: `confirmed` agrees with `Projects.isDeleteConfirmed(field.text)`
  for every input (`"delete"`, `"Delete "`, `" DELETE"`, `"del"`, `""`,
  `"deletex"`, `"cancel"`). Project delete and memory delete behave exactly as
  today.
- `confirmWord: "cancel"`: `"cancel"`, `" Cancel "`, `"CANCEL"` confirm;
  `"delete"`, `"cance"`, `"cancel it"`, `""` do not.
- A word given in any case or with surrounding spaces (`" Cancel "`) is matched
  the same way as `"cancel"`.
- An empty or whitespace-only `confirmWord` never confirms, not even an empty
  field: a mistyped caller must not end up with an accept button that is
  enabled before the user types anything.
- `confirmed` re-evaluates whenever either the field's text or `confirmWord`
  changes, including while the dialog is shown.

### What follows from `confirmed` (unchanged rules, now word-aware)

- The accept button (`confirmAccept`) is enabled iff `!busy && confirmed`.
- Return or Enter in the field emits `confirmRequested` once iff
  `confirmed && !busy`; otherwise it emits nothing. The key is consumed either
  way. Escape still emits `cancelRequested`.
- Clicking the enabled accept button emits `confirmRequested`.

### Placeholder

- The field's `placeholderText` is `confirmWord` as given (so `"delete"` by
  default, `"cancel"` for a cancel caller), and follows it when it changes.

### Unchanged

- `typedText` / `typedEdited` syncing, clearing on close and re-sync on open,
  busy blocking, error display, backdrop dismissal, object names.

## Tests

All new tests go in `tests/ui/tst_typed_confirm_dialog.qml`, appended after
the five existing functions, reusing its `dialogC`, `make()`, `find()` and
spies. Tier: QML component test under `qmltestrunner` (run by
`tests/run.sh`), because every behaviour here is a QML binding or key handler
inside the component; there is no logic outside QML to unit-test. Where a test
needs a cancel dialog it sets `d.confirmWord = "cancel"` on the instance from
`make()`.

1. `test_the_default_word_is_delete` — `confirmWord === "delete"`, the
   placeholder is `"delete"`, and typing `"cancel"` does not confirm.
2. `test_the_default_word_agrees_with_projects_isDeleteConfirmed` — a
   data-driven table (`"delete"`, `"Delete "`, `" DELETE"`, `"del"`, `""`,
   `"deletex"`, `"cancel"`): `d.confirmed === Projects.isDeleteConfirmed(text)`
   for each. The test file imports `../../core/domain/projects.js as Projects`.
   Proves project delete is unchanged at the component level.
3. `test_a_cancel_word_confirms_only_cancel` — with `confirmWord = "cancel"`:
   `"delete"` → not confirmed and accept disabled; `" Cancel "` and `"CANCEL"`
   → confirmed and accept enabled; `"cance"` and `"cancel it"` → not.
4. `test_a_cancel_word_accepts_by_click_and_by_return` — with `"cancel"`
   typed: clicking `confirmAccept` emits `confirmRequested` once; then, with
   the field focused (`forceActiveFocus()`), `keyClick(Qt.Key_Return)` emits it
   a second time. With `"delete"` typed, Return emits nothing.
5. `test_the_placeholder_follows_the_word` — `confirmTyped.placeholderText`
   is `"cancel"` after setting the word, and changes again when the word does.
6. `test_changing_the_word_while_shown_re_evaluates` — shown, field
   `"cancel"`, default word → not confirmed; set `confirmWord = "cancel"` →
   confirmed and accept enabled; set it back to `"delete"` → not.
7. `test_the_word_is_matched_trimmed_and_case_blind` — `confirmWord =
   " Cancel "`, field `"cancel"` → confirmed.
8. `test_an_empty_word_never_confirms` — `confirmWord = ""` and `"  "`: with
   the field empty and with `"delete"` typed, `confirmed` is false, accept is
   disabled, and Return emits nothing.

Regression (no edits, must stay green): the five existing tests in the same
file, `tests/core/domain/tst_projects.qml`, `tests/ui/tst_delete_flow.qml`,
`tests/ui/tst_shortcuts_delete.qml`, and `tests/architecture`.

## Notes for the planner

- One task is enough: one property, two bindings, one test file. Folding the
  tests into a single red → green cycle per behaviour group is fine.
- The dialog compares in QML (`String(field.text).trim().toLowerCase()` against
  the trimmed, lower-cased `confirmWord`); once `confirmed` no longer calls
  `Projects.isDeleteConfirmed`, drop the dialog's now-unused `projects.js`
  import. Test 2 is what keeps the two rules in step.
- No QML warning may appear in the test output (`tests/run.sh` treats
  `Unable to assign`, `TypeError`, `ReferenceError` as failures).
