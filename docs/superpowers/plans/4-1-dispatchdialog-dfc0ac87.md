# 4.1 DispatchDialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A presentation-only `ui/components/DispatchDialog.qml` modal that shows a dispatch target, the store's dispatch form, am's preview (or the refusal, or a launch failure) and the cost warning, and emits `fieldEdited(name, value)`, `startRequested()` and `cancelRequested()` — Start only from `ready`, never on Return.

**Architecture:** One new QML component built like `TypedConfirmDialog` / `NewMilestoneDialog`: an `Item` wrapping `UI.ModalCard`, every value passed in as a prop by the owner (card 4.2 will bind RunStore's `dispatch*` values), no store import. Field texts are synced imperatively from `form` (never bound) and emit only when they differ from `form`, so the owner replacing `form` on every edit never echoes. The verify rows' `Repeater` is driven by a row *count*, so typing never recreates the row under the cursor.

**Tech Stack:** QML (Qt 6 / Quickshell shell types from `qs.Ui`, stubbed in `tests/stubs`), QtTest via `qmltestrunner`, run by `bash tests/run.sh [filter]` (pytest runs first, then every `tst_*.qml` whose path contains the filter; the run fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in the output).

**Spec:** `docs/superpowers/specs/4-1-dispatchdialog-dfc0ac87.md` (copied verbatim below, headings demoted one level).

---

## The spec (verbatim)

## 4.1 DispatchDialog (card dfc0ac87)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3,
"the parent" below): "Dispatch levels" (lines 30-41), the wireframe (lines
54-65), the Flow bullets (lines 71-85), "Architecture" UI bullet (lines
118-121), "Safety" (lines 123-134), "Errors" (lines 136-145), "Testing" (line
157). Parent story c56468c7 ("Dispatch UI"). Everything this card reads is
already on this branch: the store's dispatch API (S3 3.1, spec
`3-1-runstore-dispatch-66a6b6c0.md`, `core/stores/RunStore.qml` lines 105-126
and 876-1150) and the domain functions `Runs.dispatchPlan`,
`dispatchDefaults`, `validateDispatch`, `previewSummary`
(`core/domain/runs.js` lines 787-1010).

This card is the dialog and its component tests only. Mounting it in
`Panel.qml`, the entry points (card detail button, key `d`, Runs toolbar),
the story → milestone offer, the subtask's extra confirm and the navigation
after `started` are sibling card 4.2 (46141e11).

### Starting point

- `ui/components/ModalCard.qml`: backdrop + centred card; props `shown`,
  `dismissable`, `maxWidth`, `maxHeight`, `backdropObjectName`,
  `cardObjectName`; children go into the card's `Column`; `dismissed()` on a
  backdrop click while `dismissable`.
- `ui/components/TypedConfirmDialog.qml`: the closest analogue — an `Item`
  (`z: 100`, `visible: shown`) wrapping `UI.ModalCard { anchors.fill: parent;
  shown: true }`, `theme: T.Theme {}`, `readonly property Item focusItem`,
  owner-held field text synced without echo (`onTextChanged: if (text !==
  owner value) emit`), Escape on the field cancels.
- `ui/components/ActionButton.qml` (shell `Button`, `theme`, `tone`
  `normal|danger`, `text`, `iconText`, dimmed while disabled) and
  `ui/components/Chip.qml` (`text`, `tint`, `active`, `busy`, `theme`,
  `clicked()`; a busy chip swallows clicks).
- The store, not the dialog, owns state, debouncing and the
  "Start only from ready" rule (`setDispatchField` lines 1036-1054,
  `dispatchStart` line 1062: refused unless `ready`). The dialog renders what
  it is given and emits.
- Store values the owner (card 4.2) will bind to the dialog's props:
  `dispatchState` (`idle|previewing|ready|refused|starting|started|failed`),
  `dispatchTarget` (`{command, flags, level, offered, reason, suggest}`,
  `level` `board|milestone|story|subtask|""`), `dispatchForm` (`{base, prefix,
  verify: [string], parallelism, allowNoVerification}`, **null** for a target
  refused at open), `dispatchPreview` (`{board, integrate, summary}`),
  `dispatchError`, `dispatchErrorType`, `dispatchLog`, `dispatchLogTail`,
  `dispatchExitCode` (number or null).
- Test stubs (`tests/stubs/qs/Ui`): `TextField` is a plain `TextInput` with
  `foreground`/`placeholderText`; `Button` is an `Item` with a `MouseArea`
  enabled only while the button is. `tests/run.sh` fails on any TypeError,
  ReferenceError, "Unable to assign" or "is not a function" in the output.
- No shared checkbox, combo box or number field exists in `ui/`. The parent
  forbids a new shared component unless a second user appears (line 119-120).

### Scope

In scope:

- New `ui/components/DispatchDialog.qml`.
- New `tests/ui/components/tst_dispatch_dialog.qml`.
- `docs/architecture.md`: `DispatchDialog` added to the "Shared components"
  list (line ~112 onward), in the style of the `RunControls` / `RunToast`
  entries: what it shows, what it emits, presentation only.

#### Out of scope

- Any change to `Panel.qml`, `CardDetailScreen.qml`, `RunsScreen.qml`,
  `Shortcuts.qml`, `Navigator.qml`, `App.qml`, `RunStore.qml`, `runs.js` or a
  backend helper. Mounting, `focusItem` in Panel's focus chain, `modalOpen()`,
  key `d`, the Runs toolbar target picker: card 4.2.
- The story case's "offer its milestone" button (`dispatchSuggest`), and the
  subtask's extra confirm click (parent lines 125-126): card 4.2. Here a
  refused story shows its refusal sentence like any refusal.
- Composing the subtask's story title and `blocked_by` sentence: the owner
  passes them as strings (D5); 4.2 computes them.
- Turning `ClaimedError`'s other run id into a link (parent lines 128-129):
  the sentence is shown verbatim; no parsing.
- Showing `started` (the owner closes the dialog and navigates, 4.2) and the
  "Started — waiting for the run to appear" toast (parent line 144).
- The "Confirm dispatches" per-viewer setting (parent lines 82-85) and a
  read-only mode (lines 166-167).
- A base-branch dropdown: the wireframe's `[ main ▾ ]` is a text field (D3).

### Decisions

- **D1. Presentation only.** Like `TypedConfirmDialog` and `RunControls`, the
  dialog imports no store (`tests/architecture/test_layers.py`). The owner
  passes the store's values as props and maps the signals onto
  `setDispatchField(name, value)`, `dispatchStart()` and `closeDispatch()`.
- **D2. One field signal, 1:1 with the store.** `fieldEdited(string name, var
  value)` with `name` exactly one of `base`, `prefix`, `verify`,
  `parallelism`, `allowNoVerification`, and `value` the whole new field value
  (for `verify`, the whole new array). Edits are emitted only when they differ
  from the current `form` value, so an owner pushing a new `form` never echoes
  back.
- **D3. Plain text fields.** Base, prefix, each verify command and
  parallelism are shell `TextField`s. No combo box, no spin box.
- **D4. The opt-out is a `Chip`.** "run without any verification" is a
  `UI.Chip` whose `active` is `form.allowNoVerification`; a click emits the
  opposite. This uses a component the card names and adds no checkbox.
- **D5. Subtask facts come from the owner.** am has no dry run for one card
  (parent line 35; the store goes `ready` at once, RunStore line 1005). For a
  subtask the Preview area shows a fixed note plus `storyTitle` and
  `blockedText`, strings the owner composes.
- **D6. Verify rows survive typing.** The verify repeater's model is the row
  count, `max(1, form.verify.length)`. Typing in a row emits a same-length
  array, so the count does not change and the row (and its focus and cursor)
  is not recreated when the owner's new `form` comes back.
- **D7. Return never starts.** Dispatch spends money (parent lines 133-134);
  only a click on Start emits `startRequested`. Escape cancels, like the
  backdrop, except while starting.
- **D8. Glyphs.** `⚠` (U+26A0), `▶` (U+25B6), `✕` (U+2715) and `→` are plain
  BMP characters, not private-use, so `tests/architecture/test_icon_glyphs.py`
  has nothing to check. No Nerd Font code point enters the file.
- **D9. `dispatchState`, not `state`.** `Item` already has `state`; the
  dialog's prop takes the store's name instead.

### Behaviour — `ui/components/DispatchDialog.qml`

An `Item`, `objectName: "dispatchDialog"`, `z: 100`, `visible: shown`, wrapping
`UI.ModalCard { anchors.fill: parent; shown: true; maxWidth: Style.space(520);
maxHeight: dialog.height - Style.space(48); backdropObjectName:
"dispatchBackdrop"; cardObjectName: "dispatchCard" }`.

#### Props

| prop | type, default | meaning |
|---|---|---|
| `shown` | bool, `false` | visible |
| `theme` | var, `T.Theme {}` | colours and font, passed to every child |
| `dispatchState` | string, `"idle"` | the store's `dispatchState` (not `state`: that is `Item`'s own states property) |
| `target` | var, `null` | `dispatchTarget` |
| `targetTitle` | string, `""` | the target card's title (`""` for the board) |
| `form` | var, `null` | `dispatchForm` |
| `preview` | var, `null` | `dispatchPreview` |
| `error` | string, `""` | `dispatchError` |
| `logPath` | string, `""` | `dispatchLog` |
| `logTail` | string, `""` | `dispatchLogTail` |
| `exitCode` | var, `null` | `dispatchExitCode` |
| `storyTitle` | string, `""` | a subtask's story title (D5) |
| `blockedText` | string, `""` | a subtask's `blocked_by` sentence (D5) |
| `readonly focusItem` | Item | the base field while the form shows, else the Cancel button |
| `readonly canStart` | bool | `dispatchState === "ready"` |
| `readonly busy` | bool | `dispatchState === "starting"` |
| `readonly editable` | bool | `form !== null` and `dispatchState` is `previewing`, `ready`, `refused` or `failed` |

Every read of `target`, `form`, `preview` and `theme` is guarded against null
(teardown and a target refused at open). Unknown or missing keys read as
empty.

Signals: `fieldEdited(string name, var value)`, `startRequested()`,
`cancelRequested()`.

#### Layout, top to bottom (objectNames)

1. `dispatchHeading` — heading `ThemedText`, `Dispatch`.
2. `dispatchTarget` — `ThemedText`, `Target   <text>` where text by
   `target.level`: `board` → `Whole board`; `milestone` → `Milestone
   "<targetTitle>"`; `subtask` → `Subtask "<targetTitle>"`; `story` →
   `Story "<targetTitle>"`; anything else (including null `target`) →
   `"<targetTitle>"` when the title is non-empty, else `No card`.
3. The form — shown only when `form !== null`:
   - `dispatchBase` (TextField, label `Base`, placeholder `main`) and
     `dispatchPrefix` (TextField, label `Prefix`) on one row. Text from
     `form.base` / `form.prefix`. Editing emits `fieldEdited("base", text)` /
     `fieldEdited("prefix", text)` verbatim (no trimming: the store trims).
   - Label `Verify`, then one row per verify command (D6),
     `dispatchVerify<i>` (TextField, placeholder `uv run pytest`, text
     `form.verify[i]` or `""`). Editing row i emits `fieldEdited("verify",
     a)` where `a` is a fresh copy of `form.verify` (padded to the row count
     with `""`) with entry i replaced. `dispatchVerifyRemove<i>` (ActionButton
     `✕`) shows on every row while there are 2 or more rows and emits the
     array without entry i. `dispatchVerifyAdd` (ActionButton `+`) emits the
     array with `""` appended (padded first, so with an empty stored set the
     first click gives `["", ""]`).
   - `dispatchNoVerify` — Chip, text `run without any verification`,
     `active: form.allowNoVerification === true`, click emits
     `fieldEdited("allowNoVerification", !active)`. Its `tint` is
     `theme.urgent` while active.
   - `dispatchParallel` — TextField, label `Parallel`, trailing caption
     `stories at once`, text `String(form.parallelism)`. Editing emits
     `fieldEdited("parallelism", v)` where `v` is the integer when the trimmed
     text is all digits (`/^[0-9]+$/`), else the trimmed text as a string
     (the store's `validateDispatch` then refuses it with its own sentence).
   - While `!editable` every field is disabled, `+` / `✕` disabled, the chip
     `busy`.
   - A field's text is re-synced from `form` whenever `form` changes and the
     text differs (no echo, D2).
4. `dispatchPreviewHeading` — caption `Preview  (am run --dry-run)` for
   `board` and `milestone`; `Preview` otherwise.
5. The Preview area, exactly one of (checked in this order):
   - `dispatchState === "refused"` or `"failed"`: `dispatchRefusal` — `ThemedText`
     in `theme.urgent`, word-wrapped, text `error` **verbatim**. When `failed`
     also: `dispatchExitCode` caption `Exit code <n>` when `exitCode` is a
     number; `dispatchLogPath` caption `Log: <logPath>` when non-empty;
     `dispatchLogTail` caption (monospace not required, word-wrapped) with
     `logTail` when non-empty.
   - `target.level === "subtask"` (any other state): `dispatchSubtaskNote`
     caption `No preview: am has no dry run for one subtask`, then
     `dispatchStory` `Story   "<storyTitle>"` when non-empty, then
     `dispatchBlocked` with `blockedText` when non-empty.
   - `dispatchState === "previewing"`: `dispatchChecking` caption `Checking…`.
   - `dispatchState === "ready"` (or `starting`/`started`) with a preview:
     `dispatchSummary` = `preview.summary`, `dispatchIntegrate` =
     `preview.integrate` (hidden when `""`). When both are `""`:
     `dispatchSummary` reads `am accepted the plan; it could not be
     summarised here`.
6. `dispatchWarning` — **always visible** in every state, including a
   refused target and a null form: `⚠ This starts agents and spends tokens.`;
   for `target.level === "board"`: `⚠ This starts agents on every open
   milestone and spends tokens.` (parent line 170). Colour `theme.urgent`.
7. Buttons row: `dispatchCancel` (ActionButton `Cancel`, enabled `!busy`,
   emits `cancelRequested()`), `dispatchStart` (ActionButton, `iconText` `▶`,
   text `Start run`, `Starting…` while `busy`; `enabled: canStart`; emits
   `startRequested()` on click).

#### Dismissal

- Backdrop click (`ModalCard.dismissed`) emits `cancelRequested()` unless
  `busy` (`dismissable: !busy`).
- Escape in any of the dialog's text fields emits `cancelRequested()` unless
  `busy`; the event is accepted either way.
- Return/Enter in a field does nothing beyond the field's default (D7).

### Errors and edge cases

| case | behaviour |
|---|---|
| target refused at open (story, done card, no card): `form` null, `dispatchState` `refused` | Target line, refusal sentence verbatim, warning, Cancel enabled, Start disabled; no form fields; no TypeError |
| form refusal (`Form`) | the store's first sentence verbatim in `dispatchRefusal`; fields stay editable |
| am refusal (`ClaimedError`, cycle, unknown milestone) | `error` verbatim; Start disabled |
| launch failure | `error`, `Exit code N`, `Log: path`, the tail; fields editable again (store allows edits from `failed`); Start disabled |
| `previewing` | `Checking…`; Start disabled |
| `starting` | Start reads `Starting…` disabled; Cancel, backdrop, Escape and every field disabled |
| `preview` null in `ready` | summary fallback sentence, no TypeError |
| `form.verify` missing or not an array | read as `[]`: one empty row |
| `theme` / `target` / `form` null during teardown | no TypeError in the output |

### Tests

All written first, in `tests/ui/components/tst_dispatch_dialog.qml`
(**component tier**: the dialog is presentation only, so it is driven with plain
prop objects and `SignalSpy`, no store, the way `tests/ui/components/tst_new_milestone_dialog.qml`
and `tests/ui/tst_typed_confirm_dialog.qml` do; `when: windowShown`, `visible: true`,
`createTemporaryObject`, `H.find` by objectName, `mouseClick` on
`ActionButton`/`Chip`). Field edits are driven by assigning the
`TextField`'s `text` (the stub is a `TextInput`), and Escape by `keyClick`
with the field focused.

A helper builds a milestone dialog: `dispatchState: "ready"`, `target: {level:
"milestone", offered: true, …}`, `targetTitle: "Document milestone runs"`,
`form: {base: "main", prefix: "m3", verify: ["uv run pytest"], parallelism: 4,
allowNoVerification: false}`, `preview: {board: false, summary: "2 levels · 5
subtasks · 3 stories already done", integrate: "Integrate → m3-integrate"}`.

1. Hidden until `shown`; card and backdrop found as `dispatchCard` /
   `dispatchBackdrop`; heading `Dispatch`.
2. Target text per level: milestone `Target   Milestone "Document milestone
   runs"`, board `Whole board`, subtask `Subtask "…"`, story `Story "…"`,
   null target and empty title `No card`.
3. Ready: `dispatchSummary` and `dispatchIntegrate` show the two lines
   exactly; `dispatchStart` enabled with text `Start run` and `iconText` `▶`.
   An empty `integrate` hides `dispatchIntegrate`; both empty shows the
   fallback sentence.
4. **Start disabled unless ready**: for each of `previewing`, `refused`,
   `starting`, `started`, `failed`, `idle`, `dispatchStart.enabled` is false
   and a `mouseClick` on it emits no `startRequested`. In `ready` a click
   emits it exactly once.
5. **Refusal inline verbatim**: `dispatchState: "refused"`, `error: "Card m1 is
   claimed by run r-123 (ClaimedError)"` → `dispatchRefusal.visible`, text
   identical, colour `theme.urgent`; summary hidden; Start disabled.
6. Target refused at open: `form: null`, `dispatchState: "refused"`, `target.level:
   "story"`, `error: "A story is dispatched through its milestone"` → no
   `dispatchBase` visible (or found), refusal shown, warning visible, Cancel
   enabled, Start disabled.
7. **Cost warning always visible**: in each of the seven states, with and
   without a form, `dispatchWarning.visible` and text `⚠ This starts agents and
   spends tokens.`; the board target shows the board sentence.
8. Previewing shows `Checking…` and no summary.
9. Failed: `Exit code 2`, `Log: /tmp/x.log`, the tail text shown; with
   `exitCode: null` and empty log, those three are hidden.
10. Subtask (`ready`): `dispatchSubtaskNote` text exact, `dispatchStory`
    `Story   "Control store"`, `dispatchBlocked` = `blockedText`; the preview
    heading reads `Preview` (no `am run --dry-run`); Start enabled.
11. Base and prefix edits emit `fieldEdited("base", "dev")` /
    `("prefix", "m4")` once each; assigning a new `form` with a different base
    updates the field and emits nothing (no echo).
12. Verify: editing row 0 emits `("verify", ["uv run pytest -x"])`; `+` emits
    `["uv run pytest", ""]`; with an empty stored set one empty row shows and
    `+` emits `["", ""]`; with two rows `dispatchVerifyRemove1` emits
    `["a"]`; with one row no remove button is visible.
13. Verify row identity (D6): after an edit and the owner feeding back a
    same-length `form`, `H.find(d, "dispatchVerify0")` is the same object as
    before.
14. No-verification chip: click emits `("allowNoVerification", true)`; with
    `allowNoVerification: true` it is `active` and a click emits `false`.
15. Parallelism: `"6"` emits the number `6` (`typeof` number); `"abc"` emits
    the string `"abc"`; `""` emits `""`.
16. Cancel button emits `cancelRequested` once; backdrop click emits it;
    Escape in `dispatchPrefix` emits it.
17. Starting: Start reads `Starting…` and is disabled; Cancel disabled;
    backdrop click and Escape emit nothing; fields and `+` disabled; chip
    `busy` (a click emits nothing).
18. Return in a field while `ready` emits no `startRequested`.
19. `focusItem` is `dispatchBase` with a form and `dispatchCancel` without.
20. Null `theme`, `target`, `form`, `preview` after creation, and destroying
    the dialog, produce no warnings (the run fails on TypeError otherwise).

**Architecture tier** (`tests/architecture`, unchanged, must pass): the file
imports only `QtQuick`, `qs.Commons`, `qs.Ui`, `../components`, `../theme`
(no `core/stores`); contains no `Qt.rgba(0, 0, 0, 0.55)`, `radius: height /
2`, `bordered: true`, `font.family:` or `CursorSurface {`; its name clashes
with no shell or Controls type; it adds no private-use glyph.

The full gate is `bash tests/run.sh`.

### Review focus for the planner

- Feedback loops: the owner replaces `form` on every edit; fields must
  compare before emitting and must not be bound so that a re-sync re-emits.
- Verify rows recreated on every keystroke (model bound to the array instead
  of its count) lose focus mid-typing; test 13 pins it.
- `form` null with a refused target must render without TypeError — every
  `form.x` read is guarded.
- The ModalCard's `maxHeight` clips: with many verify rows and a log tail the
  buttons must still be inside the card in a 640×700 test window (assert
  `dispatchStart` is within `dispatchCard`'s bounds with 4 verify rows and a
  3-line tail).
- The prop is `dispatchState`, never `state`: `state` is `Item`'s own
  states property, and redeclaring it breaks the dialog.

---

## Global Constraints

- Files touched: create `ui/components/DispatchDialog.qml`, create `tests/ui/components/tst_dispatch_dialog.qml`, modify `docs/architecture.md`. Nothing else (no `Panel.qml`, `RunStore.qml`, `runs.js`, screens, shortcuts or backend).
- `DispatchDialog.qml` imports exactly `QtQuick`, `qs.Commons`, `qs.Ui`, `"../components" as UI`, `"../theme" as T` — no `core/stores`, no domain module (`tests/architecture/test_layers.py`).
- The file must not contain `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:` or `CursorSurface {` (duplication guards in `test_layers.py`). Use `UI.ModalCard`, `UI.ActionButton`, `UI.Chip`, `UI.ThemedText` and shell `TextField` instead.
- No new shared component (parent spec lines 119-120): no checkbox, combo box or spin box.
- Glyphs are BMP only: `⚠` (U+26A0), `▶` (U+25B6), `✕` (U+2715), `→`, `…`. No private-use (Nerd Font) code point.
- The state prop is `dispatchState`, **never** `state` (Item's own states property).
- `objectName`s exactly as the spec: `dispatchDialog`, `dispatchBackdrop`, `dispatchCard`, `dispatchHeading`, `dispatchTarget`, `dispatchBase`, `dispatchPrefix`, `dispatchVerify<i>`, `dispatchVerifyRemove<i>`, `dispatchVerifyAdd`, `dispatchNoVerify`, `dispatchParallel`, `dispatchPreviewHeading`, `dispatchRefusal`, `dispatchExitCode`, `dispatchLogPath`, `dispatchLogTail`, `dispatchSubtaskNote`, `dispatchStory`, `dispatchBlocked`, `dispatchChecking`, `dispatchSummary`, `dispatchIntegrate`, `dispatchWarning`, `dispatchCancel`, `dispatchStart`.
- Copy, verbatim: `Dispatch`; `Target   ` (three spaces) + `Whole board` / `Milestone "<t>"` / `Story "<t>"` / `Subtask "<t>"` / `"<t>"` / `No card`; `Base` (placeholder `main`), `Prefix`, `Verify` (placeholder `uv run pytest`), `+`, `✕`, `run without any verification`, `Parallel`, `stories at once`; `Preview  (am run --dry-run)` (two spaces) / `Preview`; `Exit code <n>`; `Log: <path>`; `No preview: am has no dry run for one subtask`; `Story   "<storyTitle>"` (three spaces); `Checking…`; `am accepted the plan; it could not be summarised here`; `⚠ This starts agents and spends tokens.`; `⚠ This starts agents on every open milestone and spends tokens.`; `Cancel`; `Start run` / `Starting…` with `iconText` `▶`.
- `fieldEdited` names are exactly `base`, `prefix`, `verify`, `parallelism`, `allowNoVerification`; `base`/`prefix` values verbatim (untrimmed); `verify` the whole array.
- Return/Enter never emits `startRequested`; only a click on an enabled Start does.
- Commit messages follow the repo style `<File>: <what> (S3 4.1)` and end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- The full gate is `bash tests/run.sh` (exit 0).

## Review Focus

1. **The owner feeding its new `form` back after every edit** — the field must keep what the user typed and emit nothing more; this includes a padded parallelism (` 6 ` sent as `6`, the owner's `6` must not rewrite the text) and a parallelism the owner holds as the string `"6"`. Pinned in Task 3 (`test_the_owner_feeding_an_edit_back_changes_nothing`, `test_a_padded_number_is_sent_trimmed_and_kept_as_typed`, `test_a_parallelism_the_owner_holds_as_text_echoes_nothing`, `test_opening_a_form_into_a_mounted_dialog_echoes_nothing`).
2. **Verify rows recreated mid-typing** (Repeater bound to the array instead of its count) — the user loses focus after every keystroke. Pinned in Task 4 (`test_a_verify_row_survives_the_owner_feeding_its_edit_back`).
3. **A target refused at open (`form` null) and teardown nulls** — every `form.x` / `target.x` / `preview.x` / `theme.x` read guarded, no TypeError. Pinned in Task 2 (`test_a_target_refused_at_open_shows_the_refusal_and_no_form`) and Task 3 (`test_nulling_every_object_prop_and_destroying_is_quiet`).
4. **A long failure pushing the buttons out of the clipped card** — the store's tail is up to 20 lines / 2000 chars (`start-run.py` `TAIL_LINES = 20`); the dialog shows only the last 6 lines so Start and Cancel stay inside `dispatchCard` in a 640×700 window. Pinned in Task 2 (`test_a_twenty_line_tail_keeps_its_last_six_lines_and_the_buttons_in_the_card`) and Task 4 (`test_the_buttons_stay_inside_the_card_with_four_commands_and_a_failure`).
5. **A malformed or partial form** (`verify` missing, a string, or null; keys missing; `preview` `{}`) — reads as empty, one empty verify row, no TypeError, no echo. Pinned in Task 2 (`test_an_empty_or_missing_preview_falls_back_to_one_sentence`), Task 3 (`test_a_partial_form_reads_as_empty_fields`) and Task 4 (`test_a_missing_or_malformed_verify_reads_as_one_empty_row`).

---

## File map

| file | responsibility |
|---|---|
| `ui/components/DispatchDialog.qml` (create) | the modal: props in, three signals out; layout, field sync, verify rows |
| `tests/ui/components/tst_dispatch_dialog.qml` (create) | component-tier tests, plain props + `SignalSpy`, no store |
| `docs/architecture.md` (modify, "Shared components", after the `RunToast` entry ~line 150) | one entry describing `DispatchDialog` |

Test helpers already present: `tests/helpers/find.js` (`H.find(item, objectName)`, depth-first over `children`, `data` and `contentItem`; `null` when absent). Shell stubs: `tests/stubs/qs/Ui/TextField.qml` is a `TextInput` with `foreground` / `placeholderText` (assign `.text` to simulate typing); `Button.qml` is an `Item` with `text`, `iconText` and a `MouseArea` enabled only while the button is. `Style.space(n)` returns `n` in the stubs; `Style.spacing.md` is 8.

How to run one QML test file: `bash tests/run.sh tst_dispatch_dialog` (pytest runs first; then only paths containing the filter). Read the `FAIL` / `Totals` lines, and any TypeError lines the script echoes.

---

### Task 1: The dialog shell — target line, cost warning, Start only from ready, Cancel and the backdrop

**Files:**
- Create: `ui/components/DispatchDialog.qml`
- Create: `tests/ui/components/tst_dispatch_dialog.qml`

**Interfaces:**
- Consumes: `UI.ModalCard` (`shown`, `dismissable`, `maxWidth`, `maxHeight`, `backdropObjectName`, `cardObjectName`, `dismissed()`), `UI.ThemedText` (`theme`, `variant`), `UI.ActionButton` (`theme`, `text`, `iconText`, `enabled`, `clicked()`), `T.Theme` (`foreground`, `dim`, `urgent`), `Color.foreground`, `Color.urgent`, `Style.space(n)`, `Style.spacing.md`.
- Produces (used by Tasks 2-4 and by card 4.2):
  - props `shown: bool`, `theme: var`, `dispatchState: string`, `target: var`, `targetTitle: string`, `form: var`, `preview: var`, `error: string`, `logPath: string`, `logTail: string`, `exitCode: var`, `storyTitle: string`, `blockedText: string`;
  - readonly `focusItem: Item` (Task 1: always `cancelButton`; Task 3 changes it), `canStart: bool`, `busy: bool`, `targetLevel: string`, `foregroundColor: color`, `urgentColor: color`, `targetText: string`;
  - ids `cancelButton`, `modal`; function `cancel()` (emits `cancelRequested()` unless `busy`);
  - signals `fieldEdited(string name, var value)`, `startRequested()`, `cancelRequested()`.
  - test helpers in the test file: `dispatchStates`, `milestoneForm(over)`, `milestone(over)`, `make(over)`, `click(item)`, spies `edits`, `starts`, `cancels`.

- [ ] **Step 1: Write the failing tests**

Create `tests/ui/components/tst_dispatch_dialog.qml`:

```qml
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "DispatchDialog"
  when: windowShown
  visible: true
  width: 640; height: 700

  // Not `states`: TestCase is an Item, and Item already has one.
  readonly property var dispatchStates: ["idle", "previewing", "ready", "refused", "starting", "started", "failed"]

  Component { id: dialogC; UI.DispatchDialog { width: 640; height: 700 } }
  SignalSpy { id: edits; signalName: "fieldEdited" }
  SignalSpy { id: starts; signalName: "startRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  function milestoneForm(over) {
    return Object.assign({ base: "main", prefix: "m3", verify: ["uv run pytest"], parallelism: 4,
                           allowNoVerification: false }, over || {})
  }
  // The spec's milestone dialog, ready to start; `over` replaces any prop.
  function milestone(over) {
    return Object.assign({
      dispatchState: "ready",
      target: { level: "milestone", offered: true, reason: "", suggest: null },
      targetTitle: "Document milestone runs",
      form: milestoneForm(),
      preview: { board: false, summary: "2 levels · 5 subtasks · 3 stories already done",
                 integrate: "Integrate → m3-integrate" }
    }, over || {})
  }
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, milestone(over))
    edits.target = d; starts.target = d; cancels.target = d
    edits.clear(); starts.clear(); cancels.clear()
    d.shown = true
    wait(30)
    return d
  }
  // A form that just appeared is laid out on the next frame: wait for it, so
  // the click lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  // ---- shell ------------------------------------------------------------

  function test_it_is_hidden_until_shown_and_heads_the_card() {
    var d = createTemporaryObject(dialogC, tc)
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    verify(H.find(d, "dispatchCard"), "the modal card")
    verify(H.find(d, "dispatchBackdrop"), "the backdrop")
    compare(H.find(d, "dispatchHeading").text, "Dispatch")
    compare(d.dispatchState, "idle")
    compare(d.state, "", "dispatchState never shadows Item.state")
  }

  // ---- the target line --------------------------------------------------

  function test_the_target_line_names_the_level_data() {
    return [
      { tag: "milestone", level: "milestone", title: "Document milestone runs",
        text: "Target   Milestone \"Document milestone runs\"" },
      { tag: "board", level: "board", title: "", text: "Target   Whole board" },
      { tag: "subtask", level: "subtask", title: "RunStore dispatch", text: "Target   Subtask \"RunStore dispatch\"" },
      { tag: "story", level: "story", title: "Dispatch UI", text: "Target   Story \"Dispatch UI\"" },
      { tag: "unknown-level", level: "", title: "Loose card", text: "Target   \"Loose card\"" },
      { tag: "no-level-no-title", level: "", title: "", text: "Target   No card" }
    ]
  }

  function test_the_target_line_names_the_level(data) {
    var d = make({ target: { level: data.level }, targetTitle: data.title })
    compare(H.find(d, "dispatchTarget").text, data.text)
  }

  function test_a_null_target_without_a_title_is_no_card() {
    var d = make({ target: null, targetTitle: "" })
    compare(H.find(d, "dispatchTarget").text, "Target   No card")
  }

  // ---- Start only from ready ----------------------------------------------

  function test_start_is_disabled_unless_ready_data() {
    return [
      { tag: "idle", state: "idle" },
      { tag: "previewing", state: "previewing" },
      { tag: "refused", state: "refused" },
      { tag: "starting", state: "starting" },
      { tag: "started", state: "started" },
      { tag: "failed", state: "failed" }
    ]
  }

  function test_start_is_disabled_unless_ready(data) {
    var d = make({ dispatchState: data.state })
    var start = H.find(d, "dispatchStart")
    compare(d.canStart, false)
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0)
  }

  function test_start_in_ready_emits_once_with_its_label_and_glyph() {
    var d = make()
    var start = H.find(d, "dispatchStart")
    compare(d.canStart, true)
    compare(start.enabled, true)
    compare(start.text, "Start run")
    compare(start.iconText, "▶")
    click(start)
    compare(starts.count, 1)
    compare(cancels.count, 0)
  }

  // ---- the cost warning -------------------------------------------------

  function test_the_cost_warning_shows_in_every_state_data() {
    var rows = []
    for (var i = 0; i < tc.dispatchStates.length; i++) {
      rows.push({ tag: tc.dispatchStates[i] + "-form", state: tc.dispatchStates[i], withForm: true })
      rows.push({ tag: tc.dispatchStates[i] + "-no-form", state: tc.dispatchStates[i], withForm: false })
    }
    return rows
  }

  function test_the_cost_warning_shows_in_every_state(data) {
    var d = make({ dispatchState: data.state, form: data.withForm ? milestoneForm() : null })
    var warning = H.find(d, "dispatchWarning")
    verify(warning.visible, "the warning")
    compare(warning.text, "⚠ This starts agents and spends tokens.")
    compare(warning.color, d.theme.urgent)
  }

  function test_the_board_warning_names_every_open_milestone() {
    var d = make({ target: { level: "board" }, targetTitle: "" })
    compare(H.find(d, "dispatchWarning").text, "⚠ This starts agents on every open milestone and spends tokens.")
  }

  // ---- cancelling -------------------------------------------------------

  function test_cancel_and_the_backdrop_cancel_but_the_card_does_not() {
    var d = make()
    click(H.find(d, "dispatchCancel"))
    compare(cancels.count, 1)
    mouseClick(H.find(d, "dispatchBackdrop"), 2, 2)
    compare(cancels.count, 2)
    mouseClick(H.find(d, "dispatchCard"), 3, 3)
    compare(cancels.count, 2)
    compare(starts.count, 0)
  }

  function test_starting_locks_start_cancel_and_the_backdrop() {
    var d = make({ dispatchState: "starting" })
    var start = H.find(d, "dispatchStart"), cancel = H.find(d, "dispatchCancel")
    compare(d.busy, true)
    compare(start.text, "Starting…")
    compare(start.enabled, false)
    compare(cancel.enabled, false)
    click(start)
    click(cancel)
    mouseClick(H.find(d, "dispatchBackdrop"), 2, 2)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  function test_without_a_form_the_focus_goes_to_cancel() {
    var d = make({ form: null, dispatchState: "refused" })
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: the `== tests/ui/components/tst_dispatch_dialog.qml` block fails — qmltestrunner reports that `UI.DispatchDialog` is not a type (the component does not exist yet); the script exits non-zero.

- [ ] **Step 3: Write the minimal implementation**

Create `ui/components/DispatchDialog.qml`:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does.
Item {
  id: dialog
  objectName: "dispatchDialog"
  z: 100

  property bool shown: false
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  // RunStore's dispatchState. Not `state`: Item already has one.
  property string dispatchState: "idle"
  // RunStore's dispatchTarget: {command, flags, level, offered, reason, suggest}.
  property var target: null
  // The target card's title; "" for the board.
  property string targetTitle: ""
  // RunStore's dispatchForm: {base, prefix, verify, parallelism,
  // allowNoVerification}; null for a target refused at open.
  property var form: null
  // RunStore's dispatchPreview: {board, integrate, summary}.
  property var preview: null
  property string error: ""
  property string logPath: ""
  property string logTail: ""
  property var exitCode: null
  // am has no dry run for one subtask, so the owner composes these instead.
  property string storyTitle: ""
  property string blockedText: ""

  readonly property Item focusItem: cancelButton
  readonly property bool canStart: dialog.dispatchState === "ready"
  readonly property bool busy: dialog.dispatchState === "starting"

  // Every object prop is read guarded: a refused target has no form, and
  // tearing a view down nulls them while these bindings still run once.
  readonly property string targetLevel: dialog.target && typeof dialog.target.level === "string"
    ? dialog.target.level : ""
  readonly property color foregroundColor: dialog.theme ? dialog.theme.foreground : Color.foreground
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent
  readonly property string targetText: {
    var quoted = "\"" + dialog.targetTitle + "\""
    switch (dialog.targetLevel) {
    case "board": return "Whole board"
    case "milestone": return "Milestone " + quoted
    case "story": return "Story " + quoted
    case "subtask": return "Subtask " + quoted
    }
    return dialog.targetTitle !== "" ? quoted : "No card"
  }

  signal fieldEdited(string name, var value)
  signal startRequested()
  signal cancelRequested()

  visible: shown

  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }

  UI.ModalCard {
    id: modal
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(520)
    maxHeight: dialog.height - Style.space(48)
    backdropObjectName: "dispatchBackdrop"
    cardObjectName: "dispatchCard"
    onDismissed: dialog.cancel()

    UI.ThemedText {
      objectName: "dispatchHeading"
      variant: "heading"
      theme: dialog.theme
      text: "Dispatch"
      font.bold: true
    }

    UI.ThemedText {
      objectName: "dispatchTarget"
      theme: dialog.theme
      width: parent.width
      text: "Target   " + dialog.targetText
      elide: Text.ElideRight
    }

    // The cost warning shows in every state, a refused target's included.
    UI.ThemedText {
      objectName: "dispatchWarning"
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: dialog.targetLevel === "board"
        ? "⚠ This starts agents on every open milestone and spends tokens."
        : "⚠ This starts agents and spends tokens."
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        id: cancelButton
        objectName: "dispatchCancel"
        text: "Cancel"
        enabled: !dialog.busy
        theme: dialog.theme
        onClicked: dialog.cancel()
      }

      UI.ActionButton {
        objectName: "dispatchStart"
        iconText: "▶"
        text: dialog.busy ? "Starting…" : "Start run"
        enabled: dialog.canStart
        theme: dialog.theme
        onClicked: if (dialog.canStart) dialog.startRequested()
      }
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed` for `tst_dispatch_dialog.qml`, no TypeError lines, exit 0.

- [ ] **Step 5: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q` (or `uv run --with pytest python3 -m pytest tests/architecture -q` when `python3` has no pytest)
Expected: all pass (imports, guards, name clash, glyphs).

- [ ] **Step 6: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "DispatchDialog.qml: the target, the cost warning and Start only from ready (S3 4.1)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The Preview area — refusal, launch failure, subtask facts, Checking…, summary

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (property block before `signal fieldEdited`; layout before the `// The cost warning …` comment)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes (Task 1): `targetLevel`, `urgentColor`, `theme`, `dispatchState`, `preview`, `error`, `exitCode`, `logPath`, `logTail`, `storyTitle`, `blockedText`; test helpers `make`, `milestoneForm`, `click`, spies.
- Produces: readonly `showRefusal`, `showSubtask`, `showChecking`, `showSummary`, `showLaunch` (bool), `integrateText`, `summaryText`, `tailText` (string); objectNames `dispatchPreviewHeading`, `dispatchRefusal`, `dispatchExitCode`, `dispatchLogPath`, `dispatchLogTail`, `dispatchSubtaskNote`, `dispatchStory`, `dispatchBlocked`, `dispatchChecking`, `dispatchSummary`, `dispatchIntegrate`.

- [ ] **Step 1: Write the failing tests**

Append these functions to `tests/ui/components/tst_dispatch_dialog.qml`, just before the file's final `}`:

```qml
  // ---- the preview area -------------------------------------------------

  function test_ready_shows_what_am_would_do() {
    var d = make()
    compare(H.find(d, "dispatchPreviewHeading").text, "Preview  (am run --dry-run)")
    var summary = H.find(d, "dispatchSummary"), integrate = H.find(d, "dispatchIntegrate")
    verify(summary.visible, "the summary")
    compare(summary.text, "2 levels · 5 subtasks · 3 stories already done")
    verify(integrate.visible, "the integrate line")
    compare(integrate.text, "Integrate → m3-integrate")
    verify(!H.find(d, "dispatchRefusal").visible, "no refusal")
    verify(!H.find(d, "dispatchChecking").visible, "not checking")
    verify(!H.find(d, "dispatchSubtaskNote").visible, "no subtask note")
  }

  function test_an_empty_integrate_line_is_hidden() {
    var d = make({ preview: { board: false, summary: "1 level · 2 subtasks", integrate: "" } })
    compare(H.find(d, "dispatchSummary").text, "1 level · 2 subtasks")
    verify(!H.find(d, "dispatchIntegrate").visible)
  }

  function test_an_empty_or_missing_preview_falls_back_to_one_sentence_data() {
    return [
      { tag: "both-empty", preview: { board: false, summary: "", integrate: "" } },
      { tag: "null", preview: null },
      { tag: "no-keys", preview: {} }
    ]
  }

  function test_an_empty_or_missing_preview_falls_back_to_one_sentence(data) {
    var d = make({ preview: data.preview })
    var summary = H.find(d, "dispatchSummary")
    verify(summary.visible)
    compare(summary.text, "am accepted the plan; it could not be summarised here")
    verify(!H.find(d, "dispatchIntegrate").visible)
  }

  function test_starting_and_started_keep_the_summary_data() {
    return [{ tag: "starting", state: "starting" }, { tag: "started", state: "started" }]
  }

  function test_starting_and_started_keep_the_summary(data) {
    var d = make({ dispatchState: data.state })
    verify(H.find(d, "dispatchSummary").visible)
    compare(H.find(d, "dispatchSummary").text, "2 levels · 5 subtasks · 3 stories already done")
  }

  function test_the_preview_heading_names_the_dry_run_for_board_and_milestone_only_data() {
    return [
      { tag: "board", level: "board", text: "Preview  (am run --dry-run)" },
      { tag: "milestone", level: "milestone", text: "Preview  (am run --dry-run)" },
      { tag: "story", level: "story", text: "Preview" },
      { tag: "subtask", level: "subtask", text: "Preview" },
      { tag: "none", level: "", text: "Preview" }
    ]
  }

  function test_the_preview_heading_names_the_dry_run_for_board_and_milestone_only(data) {
    var d = make({ target: { level: data.level } })
    compare(H.find(d, "dispatchPreviewHeading").text, data.text)
  }

  function test_a_refusal_shows_inline_verbatim() {
    var d = make({ dispatchState: "refused", error: "Card m1 is claimed by run r-123 (ClaimedError)" })
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Card m1 is claimed by run r-123 (ClaimedError)")
    compare(refusal.color, d.theme.urgent)
    verify(!H.find(d, "dispatchSummary").visible, "no summary")
    verify(!H.find(d, "dispatchExitCode").visible, "no launch details for a refusal")
    compare(H.find(d, "dispatchStart").enabled, false)
  }

  function test_a_refusal_shows_no_launch_details() {
    var d = make({ dispatchState: "refused", error: "No such milestone", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "boom" })
    verify(!H.find(d, "dispatchExitCode").visible)
    verify(!H.find(d, "dispatchLogPath").visible)
    verify(!H.find(d, "dispatchLogTail").visible)
  }

  function test_a_target_refused_at_open_shows_the_refusal_and_no_form() {
    var d = make({ dispatchState: "refused", form: null, preview: null,
                   target: { level: "story", offered: false, reason: "A story is dispatched through its milestone" },
                   targetTitle: "Dispatch UI", error: "A story is dispatched through its milestone" })
    var base = H.find(d, "dispatchBase")
    verify(!base || !base.visible, "no form field")
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Dispatch UI\"")
    verify(H.find(d, "dispatchRefusal").visible)
    compare(H.find(d, "dispatchRefusal").text, "A story is dispatched through its milestone")
    verify(H.find(d, "dispatchWarning").visible)
    compare(H.find(d, "dispatchCancel").enabled, true)
    compare(H.find(d, "dispatchStart").enabled, false)
  }

  function test_previewing_says_checking() {
    var d = make({ dispatchState: "previewing", preview: null })
    var checking = H.find(d, "dispatchChecking")
    verify(checking.visible)
    compare(checking.text, "Checking…")
    verify(!H.find(d, "dispatchSummary").visible)
    verify(!H.find(d, "dispatchRefusal").visible)
  }

  function test_a_failed_launch_shows_the_exit_code_the_log_and_its_tail() {
    var d = make({ dispatchState: "failed", error: "am exited before the run appeared", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "Traceback\nValueError: bad base" })
    compare(H.find(d, "dispatchRefusal").text, "am exited before the run appeared")
    verify(H.find(d, "dispatchRefusal").visible)
    verify(H.find(d, "dispatchExitCode").visible)
    compare(H.find(d, "dispatchExitCode").text, "Exit code 2")
    verify(H.find(d, "dispatchLogPath").visible)
    compare(H.find(d, "dispatchLogPath").text, "Log: /tmp/x.log")
    verify(H.find(d, "dispatchLogTail").visible)
    compare(H.find(d, "dispatchLogTail").text, "Traceback\nValueError: bad base")
    verify(!H.find(d, "dispatchSummary").visible)
    compare(H.find(d, "dispatchStart").enabled, false)
  }

  function test_a_failure_without_a_code_or_a_log_hides_those_lines() {
    var d = make({ dispatchState: "failed", error: "start-run.py failed", exitCode: null, logPath: "", logTail: "" })
    verify(H.find(d, "dispatchRefusal").visible)
    verify(!H.find(d, "dispatchExitCode").visible)
    verify(!H.find(d, "dispatchLogPath").visible)
    verify(!H.find(d, "dispatchLogTail").visible)
  }

  function test_an_exit_code_of_zero_still_shows() {
    var d = make({ dispatchState: "failed", error: "the run never appeared", exitCode: 0 })
    verify(H.find(d, "dispatchExitCode").visible)
    compare(H.find(d, "dispatchExitCode").text, "Exit code 0")
  }

  function test_a_twenty_line_tail_keeps_its_last_six_lines_and_the_buttons_in_the_card() {
    var lines = []
    for (var i = 1; i <= 20; i++) lines.push("line " + i)
    var d = make({ dispatchState: "failed", error: "am exited", exitCode: 1, logPath: "/tmp/x.log",
                   logTail: lines.join("\n") })
    compare(H.find(d, "dispatchLogTail").text, "line 15\nline 16\nline 17\nline 18\nline 19\nline 20")
    var card = H.find(d, "dispatchCard"), cancel = H.find(d, "dispatchCancel")
    var p = cancel.mapToItem(card, 0, 0)
    verify(p.y >= 0 && p.y + cancel.height <= card.height,
           "Cancel ends at " + (p.y + cancel.height) + ", the card at " + card.height)
  }

  function test_a_subtask_has_no_dry_run_and_shows_the_owners_facts() {
    var d = make({ target: { level: "subtask", offered: true }, targetTitle: "RunStore dispatch", preview: null,
                   storyTitle: "Control store", blockedText: "Blocked by 3.1 RunStore dispatch (done)" })
    var note = H.find(d, "dispatchSubtaskNote")
    verify(note.visible)
    compare(note.text, "No preview: am has no dry run for one subtask")
    verify(H.find(d, "dispatchStory").visible)
    compare(H.find(d, "dispatchStory").text, "Story   \"Control store\"")
    verify(H.find(d, "dispatchBlocked").visible)
    compare(H.find(d, "dispatchBlocked").text, "Blocked by 3.1 RunStore dispatch (done)")
    compare(H.find(d, "dispatchPreviewHeading").text, "Preview")
    verify(!H.find(d, "dispatchSummary").visible, "no am summary for a subtask")
    compare(H.find(d, "dispatchStart").enabled, true)
  }

  function test_a_subtask_without_a_story_or_blockers_shows_only_the_note() {
    var d = make({ target: { level: "subtask" }, targetTitle: "RunStore dispatch", storyTitle: "", blockedText: "" })
    verify(H.find(d, "dispatchSubtaskNote").visible)
    verify(!H.find(d, "dispatchStory").visible)
    verify(!H.find(d, "dispatchBlocked").visible)
  }

  function test_a_refused_subtask_shows_the_refusal_not_the_note() {
    var d = make({ dispatchState: "refused", target: { level: "subtask" }, error: "This card is done",
                   storyTitle: "Control store" })
    verify(H.find(d, "dispatchRefusal").visible)
    verify(!H.find(d, "dispatchSubtaskNote").visible)
    verify(!H.find(d, "dispatchStory").visible)
  }

  function test_a_previewing_subtask_shows_the_note_not_checking() {
    var d = make({ dispatchState: "previewing", target: { level: "subtask" } })
    verify(H.find(d, "dispatchSubtaskNote").visible)
    verify(!H.find(d, "dispatchChecking").visible)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL on the new tests — e.g. `test_ready_shows_what_am_would_do` fails with `TypeError: Cannot read property 'text' of null` (no `dispatchPreviewHeading` yet); the Task 1 tests still pass.

- [ ] **Step 3: Add the preview properties**

In `ui/components/DispatchDialog.qml`, replace

```qml
  signal fieldEdited(string name, var value)
```

with

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
  readonly property string integrateText: dialog.preview && typeof dialog.preview.integrate === "string"
    ? dialog.preview.integrate : ""
  readonly property string summaryText: {
    var summary = dialog.preview && typeof dialog.preview.summary === "string" ? dialog.preview.summary : ""
    return summary === "" && dialog.integrateText === ""
      ? "am accepted the plan; it could not be summarised here" : summary
  }
  // The tail's last lines only: the log holds the rest, and the card keeps its
  // buttons in view (start-run.py sends up to 20 lines).
  readonly property string tailText: {
    var lines = dialog.logTail.split("\n")
    return lines.slice(Math.max(0, lines.length - 6)).join("\n")
  }

  signal fieldEdited(string name, var value)
```

- [ ] **Step 4: Add the preview layout**

In the same file, replace

```qml
    // The cost warning shows in every state, a refused target's included.
```

with

```qml
    UI.ThemedText {
      objectName: "dispatchPreviewHeading"
      variant: "caption"
      theme: dialog.theme
      text: dialog.targetLevel === "board" || dialog.targetLevel === "milestone"
        ? "Preview  (am run --dry-run)" : "Preview"
    }

    // A refusal (the store's, am's or a failed launch's) verbatim: no parsing.
    UI.ThemedText {
      objectName: "dispatchRefusal"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showRefusal
      width: parent.width
      text: dialog.error
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchExitCode"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showLaunch && typeof dialog.exitCode === "number"
      text: "Exit code " + dialog.exitCode
    }

    UI.ThemedText {
      objectName: "dispatchLogPath"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showLaunch && dialog.logPath !== ""
      width: parent.width
      text: "Log: " + dialog.logPath
      elide: Text.ElideMiddle
    }

    UI.ThemedText {
      objectName: "dispatchLogTail"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showLaunch && dialog.logTail !== ""
      width: parent.width
      text: dialog.tailText
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }

    UI.ThemedText {
      objectName: "dispatchSubtaskNote"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showSubtask
      width: parent.width
      text: "No preview: am has no dry run for one subtask"
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchStory"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSubtask && dialog.storyTitle !== ""
      width: parent.width
      text: "Story   \"" + dialog.storyTitle + "\""
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "dispatchBlocked"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSubtask && dialog.blockedText !== ""
      width: parent.width
      text: dialog.blockedText
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchChecking"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showChecking
      text: "Checking…"
    }

    UI.ThemedText {
      objectName: "dispatchSummary"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSummary && dialog.summaryText !== ""
      width: parent.width
      text: dialog.summaryText
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchIntegrate"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSummary && dialog.integrateText !== ""
      width: parent.width
      text: dialog.integrateText
      elide: Text.ElideRight
    }

    // The cost warning shows in every state, a refused target's included.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed`, no TypeError lines, exit 0.

- [ ] **Step 6: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "DispatchDialog.qml: the preview, a refusal verbatim and a failed launch's log (S3 4.1)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The form — Base, Prefix, the no-verification chip, Parallel; sync without echo; Escape; editable

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (`focusItem`; property block after `busy` and after `urgentColor`; handlers and functions after `visible: shown`; the form `Column` before `dispatchPreviewHeading`)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes (Task 1): `form`, `dispatchState`, `theme`, `foregroundColor`, `urgentColor`, `cancel()`, `cancelButton`, `fieldEdited`; test helpers.
- Produces: readonly `editable: bool`, `dimColor: color`; `focusItem` = `baseField` while `form` is truthy, else `cancelButton`; functions `fieldKey(event)` (Escape → `cancel()`, accepted), `formText(name) -> string` (missing/null → `""`), `parallelValue(text) -> number|string`, `syncFields()`; ids `baseField`, `prefixField`, `parallelField`, `noVerifyChip`; objectNames `dispatchForm`, `dispatchBase`, `dispatchPrefix`, `dispatchNoVerify`, `dispatchParallel`. Task 4 inserts the verify rows between the Base/Prefix row and the chip, and extends `syncFields()`.

- [ ] **Step 1: Write the failing tests**

Append these functions to `tests/ui/components/tst_dispatch_dialog.qml`, just before the file's final `}`:

```qml
  // ---- base and prefix --------------------------------------------------

  function test_base_and_prefix_show_the_form_and_report_edits() {
    var d = make()
    var base = H.find(d, "dispatchBase"), prefix = H.find(d, "dispatchPrefix")
    verify(base.visible, "the base field")
    compare(base.text, "main")
    compare(base.placeholderText, "main")
    compare(prefix.text, "m3")
    compare(edits.count, 0, "showing the form echoes nothing")
    base.text = "dev"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "base")
    compare(edits.signalArguments[0][1], "dev")
    prefix.text = "m4"
    compare(edits.count, 2)
    compare(edits.signalArguments[1][0], "prefix")
    compare(edits.signalArguments[1][1], "m4")
  }

  function test_edits_go_out_verbatim_the_store_trims() {
    var d = make()
    H.find(d, "dispatchBase").text = " dev "
    compare(edits.signalArguments[0][1], " dev ")
  }

  function test_a_new_form_from_the_owner_updates_the_fields_and_echoes_nothing() {
    var d = make()
    d.form = milestoneForm({ base: "release", prefix: "m9", parallelism: 2 })
    compare(H.find(d, "dispatchBase").text, "release")
    compare(H.find(d, "dispatchPrefix").text, "m9")
    compare(H.find(d, "dispatchParallel").text, "2")
    compare(edits.count, 0)
  }

  function test_the_owner_feeding_an_edit_back_changes_nothing() {
    var d = make()
    var base = H.find(d, "dispatchBase")
    base.text = "dev"
    compare(edits.count, 1)
    d.form = milestoneForm({ base: "dev" })
    compare(base.text, "dev")
    compare(edits.count, 1)
  }

  function test_opening_a_form_into_a_mounted_dialog_echoes_nothing() {
    var d = make({ dispatchState: "idle", form: null })
    d.dispatchState = "ready"
    d.form = milestoneForm()
    compare(H.find(d, "dispatchBase").text, "main")
    compare(H.find(d, "dispatchPrefix").text, "m3")
    compare(H.find(d, "dispatchParallel").text, "4")
    compare(edits.count, 0)
  }

  function test_a_partial_form_reads_as_empty_fields() {
    var d = make({ form: null })
    d.form = {}
    compare(H.find(d, "dispatchBase").text, "")
    compare(H.find(d, "dispatchPrefix").text, "")
    compare(H.find(d, "dispatchParallel").text, "")
    compare(H.find(d, "dispatchNoVerify").active, false)
    compare(edits.count, 0)
  }

  // ---- the no-verification chip -----------------------------------------

  function test_the_no_verification_chip_flips_the_opt_out() {
    var d = make()
    var chip = H.find(d, "dispatchNoVerify")
    compare(chip.text, "run without any verification")
    compare(chip.active, false)
    click(chip)
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "allowNoVerification")
    compare(edits.signalArguments[0][1], true)
    d.form = milestoneForm({ allowNoVerification: true })
    compare(chip.active, true)
    compare(chip.tint, d.theme.urgent)
    click(chip)
    compare(edits.count, 2)
    compare(edits.signalArguments[1][0], "allowNoVerification")
    compare(edits.signalArguments[1][1], false)
  }

  // ---- parallelism ------------------------------------------------------

  function test_parallelism_is_a_number_when_it_is_all_digits() {
    var d = make()
    var field = H.find(d, "dispatchParallel")
    compare(field.text, "4")
    field.text = "6"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "parallelism")
    compare(edits.signalArguments[0][1], 6)
    compare(typeof edits.signalArguments[0][1], "number")
    field.text = "abc"
    compare(edits.count, 2)
    compare(edits.signalArguments[1][1], "abc")
    compare(typeof edits.signalArguments[1][1], "string")
    field.text = ""
    compare(edits.count, 3)
    compare(edits.signalArguments[2][1], "")
  }

  function test_a_padded_number_is_sent_trimmed_and_kept_as_typed() {
    var d = make()
    var field = H.find(d, "dispatchParallel")
    field.text = " 6 "
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], 6)
    d.form = milestoneForm({ parallelism: 6 })
    compare(field.text, " 6 ", "the owner's 6 agrees, so the typing stays")
    compare(edits.count, 1)
  }

  function test_a_parallelism_the_owner_holds_as_text_echoes_nothing() {
    var d = make({ form: null })
    d.form = milestoneForm({ parallelism: "6" })
    compare(H.find(d, "dispatchParallel").text, "6")
    compare(edits.count, 0)
  }

  // ---- keys -------------------------------------------------------------

  function test_escape_in_a_field_cancels() {
    var d = make()
    H.find(d, "dispatchPrefix").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    H.find(d, "dispatchParallel").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 2)
    compare(starts.count, 0)
  }

  function test_return_in_a_field_never_starts_data() {
    return [{ tag: "base", name: "dispatchBase" }, { tag: "prefix", name: "dispatchPrefix" },
            { tag: "parallel", name: "dispatchParallel" }]
  }

  function test_return_in_a_field_never_starts(data) {
    var d = make()
    compare(d.canStart, true)
    H.find(d, data.name).forceActiveFocus()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // ---- editable ---------------------------------------------------------

  function test_fields_are_editable_only_where_the_store_takes_edits_data() {
    return [
      { tag: "idle", state: "idle", editable: false },
      { tag: "previewing", state: "previewing", editable: true },
      { tag: "ready", state: "ready", editable: true },
      { tag: "refused", state: "refused", editable: true },
      { tag: "starting", state: "starting", editable: false },
      { tag: "started", state: "started", editable: false },
      { tag: "failed", state: "failed", editable: true }
    ]
  }

  function test_fields_are_editable_only_where_the_store_takes_edits(data) {
    var d = make({ dispatchState: data.state })
    compare(d.editable, data.editable)
    compare(H.find(d, "dispatchBase").enabled, data.editable)
    compare(H.find(d, "dispatchPrefix").enabled, data.editable)
    compare(H.find(d, "dispatchParallel").enabled, data.editable)
    compare(H.find(d, "dispatchNoVerify").busy, !data.editable)
  }

  function test_without_a_form_nothing_is_editable() {
    var d = make({ form: null, dispatchState: "refused" })
    compare(d.editable, false)
  }

  function test_starting_disables_the_fields_the_chip_and_escape() {
    var d = make()
    var prefix = H.find(d, "dispatchPrefix")
    prefix.forceActiveFocus()
    d.dispatchState = "starting"
    compare(H.find(d, "dispatchBase").enabled, false)
    compare(prefix.enabled, false)
    compare(H.find(d, "dispatchParallel").enabled, false)
    var chip = H.find(d, "dispatchNoVerify")
    compare(chip.busy, true)
    click(chip)
    compare(edits.count, 0)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 0)
  }

  // ---- focus and teardown -----------------------------------------------

  function test_with_a_form_the_focus_goes_to_base() {
    var d = make()
    compare(d.focusItem, H.find(d, "dispatchBase"))
    d.form = null
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  function test_nulling_every_object_prop_and_destroying_is_quiet() {
    var d = make()
    d.theme = null
    d.target = null
    d.form = null
    d.preview = null
    wait(0)
    compare(edits.count, 0)
    verify(H.find(d, "dispatchWarning").visible)
    compare(H.find(d, "dispatchTarget").text, "Target   \"Document milestone runs\"")
    d.destroy()
    wait(0)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL on the new tests — e.g. `test_base_and_prefix_show_the_form_and_report_edits` with `TypeError: Cannot read property 'visible' of null` (no `dispatchBase` yet); earlier tests still pass.

- [ ] **Step 3: Point the focus at Base while there is a form**

In `ui/components/DispatchDialog.qml`, replace

```qml
  readonly property Item focusItem: cancelButton
```

with

```qml
  readonly property Item focusItem: dialog.form ? baseField : cancelButton
```

- [ ] **Step 4: Add `editable` and `dimColor`**

Replace

```qml
  readonly property bool busy: dialog.dispatchState === "starting"
```

with

```qml
  readonly property bool busy: dialog.dispatchState === "starting"
  // The store takes edits in these states (setDispatchField); never while a
  // start is in flight, and never without a form.
  readonly property bool editable: !!dialog.form
    && ["previewing", "ready", "refused", "failed"].indexOf(dialog.dispatchState) >= 0
```

and replace

```qml
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent
```

with

```qml
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent
  readonly property color dimColor: dialog.theme ? dialog.theme.dim : Color.foreground
```

- [ ] **Step 5: Add the sync handlers and the field functions**

Replace

```qml
  visible: shown

  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }
```

with

```qml
  visible: shown
  onShownChanged: dialog.syncFields()
  onFormChanged: dialog.syncFields()
  Component.onCompleted: dialog.syncFields()

  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }

  // Escape in any field cancels (not while starting); Return is left alone,
  // so it never starts a run.
  function fieldKey(event) {
    if (event.key !== Qt.Key_Escape) return
    dialog.cancel()
    event.accepted = true
  }

  // A form value as its field shows it; a missing key reads as "".
  function formText(name) {
    var value = dialog.form ? dialog.form[name] : undefined
    return value === undefined || value === null ? "" : String(value)
  }

  // All digits is the number; anything else goes out as the trimmed text, and
  // the store's validateDispatch refuses it with its own sentence.
  function parallelValue(text) {
    var trimmed = String(text).trim()
    return /^[0-9]+$/.test(trimmed) ? parseInt(trimmed, 10) : trimmed
  }

  // Owner -> fields, never bound: a field emits only when it says something
  // other than the form, and these assignments make the two agree, so a new
  // form from the owner echoes nothing.
  function syncFields() {
    if (baseField.text !== dialog.formText("base")) baseField.text = dialog.formText("base")
    if (prefixField.text !== dialog.formText("prefix")) prefixField.text = dialog.formText("prefix")
    if (dialog.parallelValue(parallelField.text) !== dialog.parallelValue(dialog.formText("parallelism")))
      parallelField.text = dialog.formText("parallelism")
  }
```

- [ ] **Step 6: Add the form layout**

Replace

```qml
    UI.ThemedText {
      objectName: "dispatchPreviewHeading"
```

with

```qml
    Column {
      objectName: "dispatchForm"
      visible: !!dialog.form
      width: parent.width
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        UI.ThemedText {
          id: baseLabel
          variant: "caption"
          theme: dialog.theme
          text: "Base"
        }

        TextField {
          id: baseField
          objectName: "dispatchBase"
          width: Math.max(0, (parent.width - baseLabel.width - prefixLabel.width - 3 * parent.spacing) / 2)
          foreground: dialog.foregroundColor
          placeholderText: "main"
          enabled: dialog.editable
          // Verbatim: the store trims.
          onTextChanged: if (text !== dialog.formText("base")) dialog.fieldEdited("base", text)
          Keys.onPressed: function(event) { dialog.fieldKey(event) }
        }

        UI.ThemedText {
          id: prefixLabel
          variant: "caption"
          theme: dialog.theme
          text: "Prefix"
        }

        TextField {
          id: prefixField
          objectName: "dispatchPrefix"
          width: baseField.width
          foreground: dialog.foregroundColor
          enabled: dialog.editable
          onTextChanged: if (text !== dialog.formText("prefix")) dialog.fieldEdited("prefix", text)
          Keys.onPressed: function(event) { dialog.fieldKey(event) }
        }
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

      Row {
        spacing: Style.space(8)

        UI.ThemedText {
          variant: "caption"
          theme: dialog.theme
          text: "Parallel"
        }

        TextField {
          id: parallelField
          objectName: "dispatchParallel"
          width: Style.space(48)
          foreground: dialog.foregroundColor
          enabled: dialog.editable
          // Compared as values, so the owner's 6 agrees with a typed " 6 ".
          onTextChanged: {
            var value = dialog.parallelValue(text)
            if (value !== dialog.parallelValue(dialog.formText("parallelism")))
              dialog.fieldEdited("parallelism", value)
          }
          Keys.onPressed: function(event) { dialog.fieldKey(event) }
        }

        UI.ThemedText {
          variant: "caption"
          theme: dialog.theme
          text: "stories at once"
        }
      }
    }

    UI.ThemedText {
      objectName: "dispatchPreviewHeading"
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed`, no TypeError / ReferenceError lines, exit 0.

- [ ] **Step 8: Run the architecture tier**

Run: `python3 -m pytest tests/architecture -q` (or the `uv run --with pytest` form)
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "DispatchDialog.qml: the form, synced from the owner without an echo (S3 4.1)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The verify rows, the card's fit, and the architecture entry

**Files:**
- Modify: `ui/components/DispatchDialog.qml` (properties after `editable`; functions after `parallelValue`; `syncFields()`; the verify UI before the chip)
- Modify: `docs/architecture.md` (Shared components, after the `RunToast` entry, before `` `Sidebar`, and the views ``)
- Test: `tests/ui/components/tst_dispatch_dialog.qml` (append before the file's final `}`)

**Interfaces:**
- Consumes (Tasks 1-3): `form`, `editable`, `theme`, `foregroundColor`, `fieldKey(event)`, `syncFields()`, `fieldEdited`.
- Produces: readonly `verifyRows: int` (`max(1, storedVerify().length)`); functions `storedVerify() -> array` (a copy of `form.verify` when it is a list or array-like, else `[]`; read from `form` directly — see the note below), `verifyAt(index) -> string`, `verifyPadded() -> array`, `editVerify(index, text)`, `removeVerify(index)`, `addVerify()`; id `verifyRepeater` whose delegates expose `sync()`; objectNames `dispatchVerifyLabel`, `dispatchVerify<i>`, `dispatchVerifyRemove<i>`, `dispatchVerifyAdd`.

**Two traps this task's code avoids (both were hit while checking this plan against the real test runner):**
- A prop object passed through `createObject` / `createTemporaryObject` arrives with its nested arrays as list wrappers, for which `Array.isArray` is `false`. `storedVerify()` therefore accepts any non-string object with a numeric `length` and copies it with `Array.prototype.slice.call`.
- Inside `onFormChanged`, a *bound* property derived from `form` (e.g. a `readonly property var verifyList: …form.verify…`) can still hold the previous value, so `syncFields()` would write the old command back into the row. Every function the sync calls reads `dialog.form` directly; only the Repeater's `verifyRows` count is a binding.

- [ ] **Step 1: Write the failing tests**

Append these functions to `tests/ui/components/tst_dispatch_dialog.qml`, just before the file's final `}`:

```qml
  // ---- verify rows ------------------------------------------------------

  function test_editing_a_verify_row_sends_the_whole_list() {
    var d = make()
    var row0 = H.find(d, "dispatchVerify0")
    compare(row0.text, "uv run pytest")
    compare(row0.placeholderText, "uv run pytest")
    compare(edits.count, 0)
    row0.text = "uv run pytest -x"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "verify")
    compare(edits.signalArguments[0][1], ["uv run pytest -x"])
  }

  function test_plus_adds_an_empty_command() {
    var d = make()
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "verify")
    compare(edits.signalArguments[0][1], ["uv run pytest", ""])
    d.form = milestoneForm({ verify: ["uv run pytest", ""] })
    verify(H.find(d, "dispatchVerify1"), "the new row")
    compare(H.find(d, "dispatchVerify1").text, "")
    verify(H.find(d, "dispatchVerifyRemove0").visible)
    verify(H.find(d, "dispatchVerifyRemove1").visible)
    compare(edits.count, 1, "the new row echoes nothing")
  }

  function test_an_empty_set_shows_one_empty_row_and_plus_gives_two() {
    var d = make({ form: null })
    d.form = milestoneForm({ verify: [] })
    compare(H.find(d, "dispatchVerify0").text, "")
    verify(!H.find(d, "dispatchVerify1"), "one row only")
    verify(!H.find(d, "dispatchVerifyRemove0").visible, "no remove on the only row")
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], ["", ""])
  }

  function test_remove_drops_that_row() {
    var d = make()
    d.form = milestoneForm({ verify: ["a", "b"] })
    compare(edits.count, 0)
    compare(H.find(d, "dispatchVerify0").text, "a")
    compare(H.find(d, "dispatchVerify1").text, "b")
    click(H.find(d, "dispatchVerifyRemove1"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], ["a"])
    click(H.find(d, "dispatchVerifyRemove0"))
    compare(edits.count, 2)
    compare(edits.signalArguments[1][1], ["b"])
  }

  function test_editing_the_second_row_keeps_the_first() {
    var d = make()
    d.form = milestoneForm({ verify: ["a", "b"] })
    H.find(d, "dispatchVerify1").text = "b2"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], ["a", "b2"])
  }

  function test_one_row_has_no_remove_button() {
    var d = make()
    var remove = H.find(d, "dispatchVerifyRemove0")
    verify(!remove || !remove.visible)
  }

  function test_a_verify_row_survives_the_owner_feeding_its_edit_back() {
    var d = make()
    var row0 = H.find(d, "dispatchVerify0")
    row0.forceActiveFocus()
    row0.text = "uv run pytest -x"
    compare(edits.count, 1)
    d.form = milestoneForm({ verify: ["uv run pytest -x"] })
    verify(H.find(d, "dispatchVerify0") === row0, "the same row, not a new one")
    compare(row0.text, "uv run pytest -x")
    verify(row0.activeFocus, "still focused")
    compare(edits.count, 1)
  }

  function test_a_missing_or_malformed_verify_reads_as_one_empty_row_data() {
    return [
      { tag: "missing", form: { base: "main", prefix: "m3", parallelism: 4 } },
      { tag: "a-string", form: { base: "main", verify: "uv run pytest" } },
      { tag: "null", form: { base: "main", verify: null } }
    ]
  }

  function test_a_missing_or_malformed_verify_reads_as_one_empty_row(data) {
    var d = make({ form: null })
    d.form = data.form
    compare(H.find(d, "dispatchVerify0").text, "")
    verify(!H.find(d, "dispatchVerify1"), "one row only")
    compare(edits.count, 0)
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.signalArguments[0][1], ["", ""])
  }

  function test_escape_in_a_verify_row_cancels() {
    var d = make()
    H.find(d, "dispatchVerify0").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
  }

  function test_starting_disables_the_verify_rows_and_plus() {
    var d = make()
    d.form = milestoneForm({ verify: ["a", "b"] })
    d.dispatchState = "starting"
    compare(H.find(d, "dispatchVerify0").enabled, false)
    compare(H.find(d, "dispatchVerifyRemove0").enabled, false)
    compare(H.find(d, "dispatchVerifyAdd").enabled, false)
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.count, 0)
  }

  // ---- the card's fit ---------------------------------------------------

  function test_the_buttons_stay_inside_the_card_with_four_commands_and_a_failure() {
    var d = make({ dispatchState: "failed", error: "am exited before the run appeared", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "one\ntwo\nthree",
                   form: milestoneForm({ verify: ["a", "b", "c", "d"] }) })
    verify(H.find(d, "dispatchVerify3"), "four rows")
    var card = H.find(d, "dispatchCard")
    var names = ["dispatchStart", "dispatchCancel"]
    for (var i = 0; i < names.length; i++) {
      var button = H.find(d, names[i])
      var p = button.mapToItem(card, 0, 0)
      verify(p.y >= 0 && p.y + button.height <= card.height,
             names[i] + " ends at " + (p.y + button.height) + ", the card at " + card.height)
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL on the new tests — e.g. `test_editing_a_verify_row_sends_the_whole_list` with `TypeError: Cannot read property 'text' of null` (no `dispatchVerify0` yet); earlier tests still pass.

- [ ] **Step 3: Add the verify properties**

In `ui/components/DispatchDialog.qml`, replace

```qml
  readonly property bool editable: !!dialog.form
    && ["previewing", "ready", "refused", "failed"].indexOf(dialog.dispatchState) >= 0
```

with

```qml
  readonly property bool editable: !!dialog.form
    && ["previewing", "ready", "refused", "failed"].indexOf(dialog.dispatchState) >= 0
  // The verify rows are counted, not listed: typing in a row sends a list of
  // the same length, so the row (its focus, its cursor) is never recreated.
  readonly property int verifyRows: Math.max(1, dialog.storedVerify().length)
```

- [ ] **Step 4: Add the verify functions and sync the rows**

Replace

```qml
  // Owner -> fields, never bound: a field emits only when it says something
```

with

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

  // Owner -> fields, never bound: a field emits only when it says something
```

Then replace

```qml
    if (dialog.parallelValue(parallelField.text) !== dialog.parallelValue(dialog.formText("parallelism")))
      parallelField.text = dialog.formText("parallelism")
  }
```

with

```qml
    if (dialog.parallelValue(parallelField.text) !== dialog.parallelValue(dialog.formText("parallelism")))
      parallelField.text = dialog.formText("parallelism")
    // New rows sync themselves when the Repeater makes them.
    for (var i = 0; i < verifyRepeater.count; i++) {
      var row = verifyRepeater.itemAt(i)
      if (row) row.sync()
    }
  }
```

- [ ] **Step 5: Add the verify layout**

Replace

```qml
      // The opt-out from verification is a chip, so the form adds no checkbox.
```

with

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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed`, no TypeError / ReferenceError / `is not a function` lines, exit 0.

- [ ] **Step 7: Describe the component in `docs/architecture.md`**

In `docs/architecture.md`, "Shared components" section, replace

```markdown
`Sidebar`, and the views
`DocumentsView`, `MemoriesView`, `MemoryNoteView`, `GraphView`.
```

with

```markdown
`DispatchDialog` (the dispatch modal: `Target   …` for the board, a milestone, a story or a subtask; a form of Base and Prefix text fields, one Verify field per command with `+` and `✕`, a `run without any verification` `Chip` and a Parallel field; a Preview area showing exactly one of the refusal verbatim in `urgent` (with `Exit code N`, `Log: path` and the log tail's last six lines for a failed launch), a subtask's no-dry-run note with the owner's story and blocked-by lines, `Checking…`, or am's summary and integrate line; the cost warning in every state, the board's naming every open milestone; Cancel and `▶ Start run`, Start enabled only in `ready`. Presentation only, like `TypedConfirmDialog`: the owner passes RunStore's `dispatchState`, `dispatchTarget`, `dispatchForm`, `dispatchPreview`, error, log, tail and exit code, and maps `fieldEdited(name, value)` -- `value` the whole field, the whole list for `verify`, emitted only when it differs from `form`, so feeding the new form back echoes nothing -- `startRequested()` (a click on Start only; Return never starts) and `cancelRequested()` (Cancel, the backdrop, Escape in a field; none while starting) onto `setDispatchField`, `dispatchStart` and `closeDispatch`. The verify rows are counted, not listed, so typing never recreates the row under the cursor. Not yet mounted: card 4.2 mounts it),
`Sidebar`, and the views
`DocumentsView`, `MemoriesView`, `MemoryNoteView`, `GraphView`.
```

- [ ] **Step 8: Run the full gate**

Run: `bash tests/run.sh`
Expected: pytest all pass (architecture tier included: imports, duplication guards, name clash, glyphs), every `tst_*.qml` reports `0 failed`, no TypeError lines, exit status 0 (`echo $?` prints `0`).

- [ ] **Step 9: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml docs/architecture.md
git commit -m "DispatchDialog.qml: verify rows that survive typing; architecture.md lists the dialog (S3 4.1)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review against the spec

**Spec coverage** (spec "Tests" numbering → plan test):

| spec | where |
|---|---|
| 1 hidden until shown, card/backdrop, heading | Task 1 `test_it_is_hidden_until_shown_and_heads_the_card` |
| 2 target text per level, null target | Task 1 `test_the_target_line_names_the_level`, `test_a_null_target_without_a_title_is_no_card` |
| 3 ready summary/integrate, Start label/glyph, empty integrate, both-empty fallback | Task 2 `test_ready_shows_what_am_would_do`, `test_an_empty_integrate_line_is_hidden`, `test_an_empty_or_missing_preview_falls_back_to_one_sentence`; Task 1 `test_start_in_ready_emits_once_with_its_label_and_glyph` |
| 4 Start disabled unless ready, no emission; ready emits once | Task 1 `test_start_is_disabled_unless_ready`, `test_start_in_ready_emits_once_with_its_label_and_glyph` |
| 5 refusal verbatim in urgent, summary hidden | Task 2 `test_a_refusal_shows_inline_verbatim` |
| 6 target refused at open | Task 2 `test_a_target_refused_at_open_shows_the_refusal_and_no_form` (meaningful for the form from Task 3 on; re-run every task) |
| 7 warning in all seven states ± form; board sentence | Task 1 `test_the_cost_warning_shows_in_every_state`, `test_the_board_warning_names_every_open_milestone` |
| 8 previewing → Checking… | Task 2 `test_previewing_says_checking` |
| 9 failed details shown / hidden | Task 2 `test_a_failed_launch_shows_the_exit_code_the_log_and_its_tail`, `test_a_failure_without_a_code_or_a_log_hides_those_lines` |
| 10 subtask note, story, blocked, heading `Preview`, Start enabled | Task 2 `test_a_subtask_has_no_dry_run_and_shows_the_owners_facts` |
| 11 base/prefix edits; new form updates without echo | Task 3 `test_base_and_prefix_show_the_form_and_report_edits`, `test_a_new_form_from_the_owner_updates_the_fields_and_echoes_nothing` |
| 12 verify edit, `+`, empty set, remove, single row no remove | Task 4 `test_editing_a_verify_row_sends_the_whole_list`, `test_plus_adds_an_empty_command`, `test_an_empty_set_shows_one_empty_row_and_plus_gives_two`, `test_remove_drops_that_row`, `test_one_row_has_no_remove_button` |
| 13 verify row identity (D6) | Task 4 `test_a_verify_row_survives_the_owner_feeding_its_edit_back` |
| 14 chip | Task 3 `test_the_no_verification_chip_flips_the_opt_out` |
| 15 parallelism number / string / "" | Task 3 `test_parallelism_is_a_number_when_it_is_all_digits` |
| 16 Cancel, backdrop, Escape | Task 1 `test_cancel_and_the_backdrop_cancel_but_the_card_does_not`; Task 3 `test_escape_in_a_field_cancels`; Task 4 `test_escape_in_a_verify_row_cancels` |
| 17 starting locks everything | Task 1 `test_starting_locks_start_cancel_and_the_backdrop`; Task 3 `test_starting_disables_the_fields_the_chip_and_escape`; Task 4 `test_starting_disables_the_verify_rows_and_plus` |
| 18 Return never starts | Task 3 `test_return_in_a_field_never_starts` |
| 19 focusItem | Task 1 `test_without_a_form_the_focus_goes_to_cancel`; Task 3 `test_with_a_form_the_focus_goes_to_base` |
| 20 nulls and destroy quiet | Task 3 `test_nulling_every_object_prop_and_destroying_is_quiet` (run.sh fails on any TypeError) |
| Review focus: buttons inside the card, 640×700, 4 rows + 3-line tail | Task 4 `test_the_buttons_stay_inside_the_card_with_four_commands_and_a_failure` |
| Architecture tier unchanged, passes | Task 1 Step 5, Task 3 Step 8, Task 4 Step 8 |
| `docs/architecture.md` entry | Task 4 Step 7 |
| D9 `dispatchState` not `state` | Task 1 props; `compare(d.state, "")` in the first test |
| `editable` states table | Task 3 `test_fields_are_editable_only_where_the_store_takes_edits` |

**One addition beyond the spec's letter, made deliberately:** the log tail shows its last six lines (`tailText`), because `start-run.py` sends up to 20 lines and the spec's review focus requires the buttons to stay inside the clipped card. The 3-line tail of spec test 9 is unaffected (shown whole).

**Checked against the runner:** every task's code and tests were applied mechanically, in order, to a scratch copy of this branch and run with `qmltestrunner` against `tests/stubs` (97 test rows green at the end, no TypeError / ReferenceError output). That check found and fixed the two verify-row traps noted in Task 4 and the need for `click()` to wait a frame after a form appears.

**Placeholder scan:** every code step carries the full code; no TBD / "similar to" / "add error handling".

**Type consistency:** `targetLevel`, `urgentColor`, `dimColor`, `foregroundColor`, `editable`, `busy`, `canStart`, `cancel()`, `fieldKey(event)`, `formText(name)`, `parallelValue(text)`, `syncFields()`, `storedVerify()`, `verifyRows`, `verifyAt(i)`, `verifyPadded()`, `editVerify(i, text)`, `removeVerify(i)`, `addVerify()`, `verifyRepeater`, ids `baseField` / `prefixField` / `parallelField` / `cancelButton` — each defined once, used with the same name and arity in later tasks. Test helpers `make`, `milestone`, `milestoneForm`, `click`, `dispatchStates`, spies `edits` / `starts` / `cancels` are defined in Task 1 and reused verbatim.

**Edit anchors** (each `replace` block's old text occurs exactly once in the file at that point): Task 2 — `  signal fieldEdited(string name, var value)`, `    // The cost warning shows in every state, a refused target's included.`; Task 3 — `  readonly property Item focusItem: cancelButton`, `  readonly property bool busy: …`, `  readonly property color urgentColor: …`, the `visible: shown` + `cancel()` block, `    UI.ThemedText {\n      objectName: "dispatchPreviewHeading"`; Task 4 — the `editable` block, `  // Owner -> fields, never bound: …`, the last two lines of `syncFields()`, `      // The opt-out from verification is a chip, …`.
<!-- task-pipeline: validated -->
