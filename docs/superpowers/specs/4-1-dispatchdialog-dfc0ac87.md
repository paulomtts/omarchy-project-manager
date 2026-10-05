# 4.1 DispatchDialog (card dfc0ac87)

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

## Starting point

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

## Scope

In scope:

- New `ui/components/DispatchDialog.qml`.
- New `tests/ui/components/tst_dispatch_dialog.qml`.
- `docs/architecture.md`: `DispatchDialog` added to the "Shared components"
  list (line ~112 onward), in the style of the `RunControls` / `RunToast`
  entries: what it shows, what it emits, presentation only.

### Out of scope

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

## Decisions

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

## Behaviour — `ui/components/DispatchDialog.qml`

An `Item`, `objectName: "dispatchDialog"`, `z: 100`, `visible: shown`, wrapping
`UI.ModalCard { anchors.fill: parent; shown: true; maxWidth: Style.space(520);
maxHeight: dialog.height - Style.space(48); backdropObjectName:
"dispatchBackdrop"; cardObjectName: "dispatchCard" }`.

### Props

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

### Layout, top to bottom (objectNames)

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

### Dismissal

- Backdrop click (`ModalCard.dismissed`) emits `cancelRequested()` unless
  `busy` (`dismissable: !busy`).
- Escape in any of the dialog's text fields emits `cancelRequested()` unless
  `busy`; the event is accepted either way.
- Return/Enter in a field does nothing beyond the field's default (D7).

## Errors and edge cases

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

## Tests

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

## Review focus for the planner

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
