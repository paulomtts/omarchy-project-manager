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

---

# TypedConfirmDialog `confirmWord` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `ui/components/TypedConfirmDialog.qml` a `confirmWord` property (default `"delete"`) that drives both the `confirmed` gate and the field's placeholder, test-first, with every new test appended to `tests/ui/tst_typed_confirm_dialog.qml`.

**Architecture:** `confirmed` stops calling `Projects.isDeleteConfirmed` and compares the trimmed, lower-cased field text with the trimmed, lower-cased `confirmWord` in a QML binding (an empty trimmed word never confirms). The placeholder binds to `confirmWord`. The now-unused `projects.js` import is dropped from the dialog; the test file imports `projects.js` instead and pins that the default word agrees with `Projects.isDeleteConfirmed` for every listed input. Everything downstream of `confirmed` (accept button `enabled`, Return/Enter handler) is untouched and becomes word-aware for free.

**Tech Stack:** QML (Qt 6 QtQuick), QtTest under `qmltestrunner`, driven by `tests/run.sh`.

**Spec:** `docs/superpowers/specs/3-1-typedconfirmdialog-bba42f66.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S3).

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/ctl/task-3-1-typedconfirmdialog-bba42f66`, branch `ctl/task-3-1-typedconfirmdialog-bba42f66`. Run every command from that directory.

**Running the tests:** `bash tests/run.sh tst_typed_confirm_dialog` runs pytest (all of it, always) and then only the QML files whose path contains `tst_typed_confirm_dialog`. It prints `== tests/ui/tst_typed_confirm_dialog.qml`, every `FAIL!` line with its `Loc:` line, the `Totals:` line, and any `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` line, and exits non-zero on any of them. `bash tests/run.sh` with no argument runs everything.

## Global Constraints

- New property: `property string confirmWord: "delete"` on `TypedConfirmDialog`.
- `confirmed` is true exactly when `String(field.text).trim().toLowerCase()` equals the trimmed, lower-cased `confirmWord` **and** that trimmed word is not `""`.
- `placeholderText` of the field is `dialog.confirmWord` as given (not trimmed, not lower-cased).
- The accept button stays `enabled: !dialog.busy && dialog.confirmed`; the Return/Enter handler stays `if (dialog.confirmed && !dialog.busy) dialog.confirmRequested(); event.accepted = true`; Escape stays `cancelRequested`.
- Drop `import "../../core/domain/projects.js" as Projects` from `ui/components/TypedConfirmDialog.qml` (it becomes unused).
- The dialog "Renders and emits only": no store access, no process, no side effect added.
- The five existing test functions in `tests/ui/tst_typed_confirm_dialog.qml` (lines 28-99) and its helpers stay byte for byte; new tests are appended after `test_busy_blocks_everything_and_errors_show`, before the file's final `}`. The only other edit to that file is one added import line.
- Do not touch `core/domain/projects.js`, `core/stores/ProjectDeleteStore.qml`, `ui/Panel.qml`, `docs/architecture.md`, `tests/core/domain/tst_projects.qml`, `tests/ui/tst_delete_flow.qml`, `tests/ui/tst_shortcuts_delete.qml`, or anything under `tests/architecture`.
- No new component, no icon glyph, no wording added to the dialog (the caller writes "Type … to confirm").
- No `TypeError`, `ReferenceError`, `Unable to assign` (or any other line `tests/run.sh` greps for) may appear in test output.
- Verification: `bash tests/run.sh` green.

## Review Focus

The spec's eight tests are all in Task 1. These five further inputs follow from the spec ("Unchanged" + "What follows from `confirmed`") but no spec test exercises them with a non-default word. Each has a named test appended in Task 1:

1. A cancel dialog while `busy` (the Cancel-run caller sets `busy` while `run-control.py` runs): `"cancel"` typed must leave accept disabled and Return must emit nothing. Pinned by `test_busy_blocks_a_cancel_word`.
2. An owner that keeps the typed text (`typedText`, like the project-delete store) with a cancel word: `d.typedText = "cancel"` must confirm, `"delete"` must not. Pinned by `test_the_owners_text_is_checked_against_the_word`.
3. Close and reopen a cancel dialog: the field is cleared (not confirmed after reopen) while the word survives, and typing it again confirms. Pinned by `test_reopening_keeps_the_word_and_clears_the_field`.
4. Keypad Enter (`Qt.Key_Enter`) on a cancel dialog emits `confirmRequested` exactly once, just like Return. Pinned by `test_keypad_enter_accepts_a_cancel_word`.
5. Escape on a cancel dialog with `"cancel"` already typed emits `cancelRequested` and never `confirmRequested` (the word "cancel" must not make Escape confirm). Pinned by `test_escape_still_cancels_with_a_cancel_word`.

## File Structure

- Modify: `ui/components/TypedConfirmDialog.qml` — drop the `projects.js` import (line 4), add `confirmWord` next to the other public properties, rewrite `confirmed` (line 33), bind `placeholderText` (line 78).
- Modify: `tests/ui/tst_typed_confirm_dialog.qml` — add the `projects.js` import after line 3; append thirteen test functions (one with a `_data` table) after line 99.

No other file changes.

---

### Task 1: `confirmWord` drives `confirmed` and the placeholder

**Files:**
- Modify: `ui/components/TypedConfirmDialog.qml:4`, `:29-33`, `:78`
- Test: `tests/ui/tst_typed_confirm_dialog.qml:3` (import), append after `:99`

**Interfaces:**
- Consumes: `Projects.isDeleteConfirmed(text)` from `core/domain/projects.js` (test file only, as the oracle for the default word). The existing test helpers `dialogC`, `make()`, `find(item, name)`, `confirmSpy`, `cancelSpy`.
- Produces: `TypedConfirmDialog.confirmWord` (`property string`, default `"delete"`). Sibling cards (the Cancel-run caller) will instantiate `UI.TypedConfirmDialog { confirmWord: "cancel" ... }`. `confirmed` (`readonly property bool`) keeps its name and type.

- [ ] **Step 1: Add the `projects.js` import to the test file**

In `tests/ui/tst_typed_confirm_dialog.qml`, the first lines are currently:

```qml
import QtQuick
import QtTest
import "../../ui/components"
TestCase {
```

Change them to (one inserted line, nothing else changes):

```qml
import QtQuick
import QtTest
import "../../ui/components"
import "../../core/domain/projects.js" as Projects
TestCase {
```

(The path is relative to `tests/ui/`; `tests/core/domain/tst_projects.qml` uses the same file with one more `../`.)

- [ ] **Step 2: Append the failing tests**

In `tests/ui/tst_typed_confirm_dialog.qml`, the file currently ends with:

```qml
    compare(find(d, "confirmError").visible, true)
    compare(find(d, "confirmError").text, "nope")
  }
}
```

Insert the following between that `  }` (end of `test_busy_blocks_everything_and_errors_show`) and the final `}` (end of `TestCase`). Do not change anything above it.

```qml

  // ---- confirmWord ---------------------------------------------------------

  function test_the_default_word_is_delete() {
    var d = make()
    d.shown = true
    compare(d.confirmWord, "delete")
    compare(find(d, "confirmTyped").placeholderText, "delete")
    find(d, "confirmTyped").text = "cancel"
    compare(d.confirmed, false)
    compare(find(d, "confirmAccept").enabled, false)
  }

  function test_the_default_word_agrees_with_projects_isDeleteConfirmed_data() {
    return [
      { tag: "delete", text: "delete" },
      { tag: "Delete-trailing-space", text: "Delete " },
      { tag: "DELETE-leading-space", text: " DELETE" },
      { tag: "del", text: "del" },
      { tag: "empty", text: "" },
      { tag: "deletex", text: "deletex" },
      { tag: "cancel", text: "cancel" }
    ]
  }

  function test_the_default_word_agrees_with_projects_isDeleteConfirmed(data) {
    var d = make()
    d.shown = true
    find(d, "confirmTyped").text = data.text
    compare(d.confirmed, Projects.isDeleteConfirmed(data.text))
    compare(find(d, "confirmAccept").enabled, Projects.isDeleteConfirmed(data.text))
  }

  function test_a_cancel_word_confirms_only_cancel() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped"), accept = find(d, "confirmAccept")
    field.text = "delete"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.text = " Cancel "
    compare(d.confirmed, true)
    compare(accept.enabled, true)
    field.text = "CANCEL"
    compare(d.confirmed, true)
    compare(accept.enabled, true)
    field.text = "cance"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.text = "cancel it"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
  }

  function test_a_cancel_word_accepts_by_click_and_by_return() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped"), accept = find(d, "confirmAccept")
    field.text = "cancel"
    mouseClick(accept, accept.width / 2, accept.height / 2)
    compare(confirmSpy.count, 1)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 2)
    field.text = "delete"
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 2)
  }

  function test_the_placeholder_follows_the_word() {
    var d = make()
    d.shown = true
    var field = find(d, "confirmTyped")
    d.confirmWord = "cancel"
    compare(field.placeholderText, "cancel")
    d.confirmWord = "remove"
    compare(field.placeholderText, "remove")
  }

  function test_changing_the_word_while_shown_re_evaluates() {
    var d = make()
    d.shown = true
    var accept = find(d, "confirmAccept")
    find(d, "confirmTyped").text = "cancel"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    d.confirmWord = "cancel"
    compare(d.confirmed, true)
    compare(accept.enabled, true)
    d.confirmWord = "delete"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
  }

  function test_the_word_is_matched_trimmed_and_case_blind() {
    var d = make()
    d.confirmWord = " Cancel "
    d.shown = true
    find(d, "confirmTyped").text = "cancel"
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
  }

  function test_an_empty_word_never_confirms_data() {
    return [
      { tag: "empty-word", word: "" },
      { tag: "blank-word", word: "  " }
    ]
  }

  function test_an_empty_word_never_confirms(data) {
    var d = make()
    d.confirmWord = data.word
    d.shown = true
    var field = find(d, "confirmTyped"), accept = find(d, "confirmAccept")
    compare(field.text, "")
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 0)
    field.text = "delete"
    compare(d.confirmed, false)
    compare(accept.enabled, false)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 0)
  }

  // ---- confirmWord: review focus --------------------------------------------

  function test_busy_blocks_a_cancel_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    d.busy = true
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, false)
    field.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(confirmSpy.count, 0)
  }

  function test_the_owners_text_is_checked_against_the_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    d.typedText = "cancel"
    compare(find(d, "confirmTyped").text, "cancel")
    compare(d.confirmed, true)
    compare(find(d, "confirmAccept").enabled, true)
    d.typedText = "delete"
    compare(d.confirmed, false)
    compare(find(d, "confirmAccept").enabled, false)
  }

  function test_reopening_keeps_the_word_and_clears_the_field() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    compare(d.confirmed, true)
    d.shown = false
    d.shown = true
    compare(field.text, "")
    compare(d.confirmWord, "cancel")
    compare(field.placeholderText, "cancel")
    compare(d.confirmed, false)
    field.text = "Cancel"
    compare(d.confirmed, true)
  }

  function test_keypad_enter_accepts_a_cancel_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    field.forceActiveFocus()
    keyClick(Qt.Key_Enter)
    compare(confirmSpy.count, 1)
  }

  function test_escape_still_cancels_with_a_cancel_word() {
    var d = make()
    d.confirmWord = "cancel"
    d.shown = true
    var field = find(d, "confirmTyped")
    field.text = "cancel"
    field.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancelSpy.count, 1)
    compare(confirmSpy.count, 0)
  }
```

Notes for the engineer:
- `test_..._data()` returning an array of objects with a `tag` is QtTest's data-driven form: the test function runs once per row, receiving the row as `data`, and each row is reported as `test_name(tag)`.
- `d.confirmWord = …` is set before `d.shown = true` where a test is about a cancel dialog; that is how a caller declares it. `test_changing_the_word_while_shown_re_evaluates` and `test_the_placeholder_follows_the_word` set it after, on purpose.
- In `test_busy_blocks_a_cancel_word`, `confirmed` stays `true` while busy (it is about the word only); `busy` gates the button and the key, exactly as in `test_busy_blocks_everything_and_errors_show`. The field is `enabled: !dialog.busy`, so `forceActiveFocus()` may not give it focus; either way no `confirmRequested` may be emitted, which is what the test checks.

- [ ] **Step 3: Run the tests and watch them fail**

Run: `bash tests/run.sh tst_typed_confirm_dialog`

Expected: non-zero exit, `Totals: 14 passed, 13 failed` for this file. The five existing tests still `PASS`. `FAIL!` lines for the new `confirmWord` tests: `test_the_default_word_is_delete` fails on `compare(d.confirmWord, "delete")` (actual `undefined`), and every test that assigns `d.confirmWord = …` fails with `Uncaught exception: Cannot assign to non-existent property "confirmWord"` (the `non-existent` text is also flagged by `tests/run.sh`). `test_the_default_word_agrees_with_projects_isDeleteConfirmed` (all seven rows) is expected to **pass** already: it is the regression guard that the new code must keep green, not a red test. If any of the five original tests fails, or the `Projects` import produces a "not found"/"is not a type" error, stop and fix the import path before continuing.

- [ ] **Step 4: Implement `confirmWord` in the dialog**

In `ui/components/TypedConfirmDialog.qml`:

(a) Delete line 4 so the imports read:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T
```

(b) Replace these lines (currently 29-33):

```qml
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  readonly property Item focusItem: field
  readonly property bool confirmed: Projects.isDeleteConfirmed(field.text)
```

with:

```qml
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  // The word the user has to type, matched trimmed and case-blind; it is also
  // the field's placeholder. A blank word never confirms.
  property string confirmWord: "delete"
  readonly property Item focusItem: field
  readonly property bool confirmed: {
    var word = dialog.confirmWord.trim().toLowerCase()
    return word !== "" && String(field.text).trim().toLowerCase() === word
  }
```

(c) Replace line 78 (inside `TextField { id: field … }`):

```qml
      placeholderText: "delete"
```

with:

```qml
      placeholderText: dialog.confirmWord
```

Nothing else in the file changes: the accept button's `enabled: !dialog.busy && dialog.confirmed` and the `Keys.onPressed` handler already read `confirmed`.

- [ ] **Step 5: Run the dialog tests and watch them pass**

Run: `bash tests/run.sh tst_typed_confirm_dialog`

Expected: exit 0; `Totals: 27 passed, 0 failed` for this file; no `FAIL!` line and no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` line. Every new test (including both `_data` rows of `test_an_empty_word_never_confirms` and all seven rows of the `isDeleteConfirmed` table) and the five original tests pass.

- [ ] **Step 6: Run the full suite (regression: project delete, memory delete, architecture)**

Run: `bash tests/run.sh`

Expected: exit 0. pytest green (this includes `tests/architecture`, which must still pass with the `projects.js` import gone from the dialog and present in the test). Every QML file's `Totals:` shows `0 failed`, in particular `tests/core/domain/tst_projects.qml`, `tests/ui/tst_delete_flow.qml` and `tests/ui/tst_shortcuts_delete.qml`, none of which were edited. No `TypeError` / `ReferenceError` / `Unable to assign` line anywhere.

Then confirm the existing tests are byte-for-byte unchanged and nothing outside scope moved:

Run: `git diff --stat`

Expected: exactly two files, `ui/components/TypedConfirmDialog.qml` and `tests/ui/tst_typed_confirm_dialog.qml`.

Run: `git diff -U0 tests/ui/tst_typed_confirm_dialog.qml | grep '^-' | grep -v '^---'`

Expected: no output (the test file only gained lines).

- [ ] **Step 7: Commit**

```bash
git add ui/components/TypedConfirmDialog.qml tests/ui/tst_typed_confirm_dialog.qml
git commit -m "feat(ui): TypedConfirmDialog takes a confirmWord (default \"delete\") that gates confirm and sets the placeholder (card bba42f66)"
```

---

## Self-Review

1. **Spec coverage.**
   - `property string confirmWord` default `"delete"` → Step 4(b); test 1.
   - Trimmed/lower-cased match, non-empty word → Step 4(b); tests 3, 7, 8.
   - Default agrees with `isDeleteConfirmed` for the seven inputs → test 2 (data-driven, also checks accept `enabled`).
   - `"cancel"` confirms `"cancel"`, `" Cancel "`, `"CANCEL"`, not `"delete"`, `"cance"`, `"cancel it"`, `""` → test 3 (non-empty cases) and Review Focus 3 (`""` after reopen is not confirmed).
   - Re-evaluates on text and on word change while shown → test 6, Review Focus 2.
   - Accept enabled iff `!busy && confirmed` → tests 2, 3, 6, 8; Review Focus 1.
   - Return/Enter emits once iff confirmed and not busy, key consumed; Escape cancels → tests 4, 8; Review Focus 1, 4, 5.
   - Click emits `confirmRequested` → test 4.
   - Placeholder is `confirmWord` as given and follows it → Step 4(c); tests 1, 5; Review Focus 3.
   - Unchanged behaviour (typed text sync, clear on close, busy, error, backdrop, object names) → five existing tests untouched; Review Focus 2, 3.
   - Drop unused `projects.js` import from the dialog → Step 4(a).
   - Out-of-scope files untouched → Global Constraints; Step 6 `git diff --stat`.
   - `bash tests/run.sh` green, no QML warnings → Step 6.
2. **Placeholder scan.** No TBD/TODO; every code step has the full code.
3. **Type consistency.** `confirmWord` (string), `confirmed` (bool), object names `confirmTyped`, `confirmAccept`, `confirmCancel` match the component; spies `confirmSpy`, `cancelSpy` and helpers `make()`, `find()` match the existing test file.
4. **Review Focus.** Five lines, each with a named test in Task 1, Step 2.
<!-- task-pipeline: validated -->
