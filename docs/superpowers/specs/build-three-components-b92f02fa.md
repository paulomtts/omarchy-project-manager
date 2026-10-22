# Build three components + QML tests (story D, card b92f02fa)

Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md` (cited as **RR** with line
numbers). Story: "D: UI components" (`7997c2cf`): "RunLevelBadge, RunStateBadge, CloseRunDialog
(props only, no store imports)".

This card adds three presentation-only QML components and their QML tests. Nothing mounts them yet;
story F wires them into `RunsScreen`/`RunControls`/`Panel`.

## Inherited constraints

- `ui/components/**` imports no `core/stores` and takes props only (RR line 21;
  `tests/architecture/test_layers.py` lines ~145-152). These components also import no
  `core/domain` file: the level and the state arrive as strings.
- The level badge is a 4px-radius rectangle, the same shape for all three levels, differing only in
  border weight and tint; its text is the level upper-cased (RR lines 50-56). It may **not** be built
  on `Badge.qml` (RR line 62).
- Level colours (RR lines 52-58): MILESTONE `#2b3f9e` light / `#aab8ff` dark; STORY `#4a67d6` /
  `#8196ee`; SUBTASK `#7f93d9` / `#5d70b8`. Theme token names `levelMilestone`, `levelStory`,
  `levelSubtask`. Amber is never used for a level.
- The state badge shows only for RUNNING (accent-green tint) and ESCALATED (warn tint); parked, dead
  and every other state show no badge. No spinner, no ⚠/⏸/⟳ glyphs. It may be built on `Badge.qml`
  (RR lines 60-62).
- Close tone: orange `#c4560a` light / `#ff9442` dark, token `closeTone` (RR line 77).
- The Close dialog is a `ModalCard` over a dimmed backdrop with no typed confirmation (RR line 103);
  title `Close "<run title>"?` (RR line 105); body per RR line 106; buttons `Keep` (neutral) and
  `Close` (orange, `closeTone`); Escape and Keep dismiss (RR line 107).
- Duplication guards in `tests/architecture/test_layers.py` (lines 246-273) must keep passing: no new
  file may contain `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:`
  or `CursorSurface {`. So text goes through `ThemedText`, buttons through `ActionButton`, the
  backdrop through `ModalCard`.
- `bash tests/run.sh` is green before and after (RR line 136); it fails on any `FAIL` line and on
  `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or
  `is not a function` in QML output.
- House conventions: 2-space indent, no semicolons, a short prose comment above each component;
  `property var theme: null` plus `readonly property var palette: x.theme || ownTheme` with every
  `palette` read null-guarded (`Badge.qml` lines 9-16, `ActionButton.qml` lines 9-15). Dialogs instead
  default `property var theme: T.Theme {}` (`TypedConfirmDialog.qml` line 30,
  `ResumeVerifyDialog.qml` line 33) and expose `objectName`s for tests.

## Theme tokens: read when present, fall back otherwise

Story E (`8c7324d3`, "theme tokens and ActionButton tones") adds the tokens to `ui/theme/Theme.qml`
and the `ActionButton` tones, and runs in parallel with this card. **This card does not edit
`ui/theme/Theme.qml` or `ActionButton.qml`.** Each component instead reads a token from its theme
when the theme defines it, and otherwise uses a fixed fallback colour:

| Token | Used by | Fallback |
|---|---|---|
| `levelMilestone` | RunLevelBadge, milestone | `#aab8ff` |
| `levelStory` | RunLevelBadge, story | `#8196ee` |
| `levelSubtask` | RunLevelBadge, subtask | `#5d70b8` |
| `accent` | RunStateBadge, running | `#7ed491` |
| `warn` | RunStateBadge, escalated | `#f0b54a` |
| `closeTone` | CloseRunDialog, Close button | `#ff9442` |

- "Defined" means the theme object is non-null and reading the property does not give `undefined`.
  A defined token always wins, whatever its value.
- The level and close fallbacks are RR's dark values (the panel draws on the shell's dark popup
  background); picking light vs dark is the token's job once E lands. RR gives no hex for the
  accent and warn tones, so their fallbacks are this spec's choice (a green and an amber).
- A null theme (teardown) never throws: every read is guarded and yields the fallback.

## Component 1: `ui/components/RunLevelBadge.qml`

A `Rectangle` (not `Badge`) holding one `ThemedText`.

Properties and names:

- `property var theme: null`, `readonly property var palette: theme || <own T.Theme>`.
- `property string level: ""`: `subtask` | `story` | `milestone` (the value of `Runs.runLevel(run)`).
- `readonly property string shownLevel`: `level` when it is exactly `"subtask"` or `"story"`,
  otherwise `"milestone"` (mirrors `runLevel`'s "garbage gives milestone", RR line 48). Matching is
  exact: `"Story"`, `" story"`, `""`, `"epic"` all give `"milestone"`.
- `readonly property color levelColor`: the shown level's token or fallback (table above).
- `objectName: "runLevelBadge"`; the label's objectName is `"runLevelBadgeText"`.

Observable behaviour:

| shownLevel | label text | `border.width` | fill (`color`) |
|---|---|---|---|
| milestone | `MILESTONE` | 2 | `Qt.alpha(levelColor, 0.22)` |
| story | `STORY` | 1 | `Qt.alpha(levelColor, 0.12)` |
| subtask | `SUBTASK` | 1 | `"transparent"` (alpha 0) |

- `border.color` and the label colour are `levelColor` for every level.
- `radius` is `Style.space(4)` for every level, and is less than `height / 2` (a rectangle, not a
  pill).
- The label is a caption-variant `ThemedText` (theme font family and caption size).
- Size follows the label: width = label implicit width + `Style.space(12)`, height = label implicit
  height + `Style.space(4)`; both are > 0 for every level.
- Always visible: every run has a level.

## Component 2: `ui/components/RunStateBadge.qml`

A `Badge` (inherits `theme`, `palette`, `tint`, `text`, `textObjectName`, the 18% fill and pill
shape).

- `objectName: "runStateBadge"`, `textObjectName: "runStateBadgeText"`.
- The run state comes in through Item's own `state` string, used as plain text, as `RunBadge.qml`
  does (lines 8-9). Values are `Runs.runState` names.

| `state` | text | tint | visible |
|---|---|---|---|
| `running` | `RUNNING` | `accent` token or `#7ed491` | yes |
| `escalated` | `ESCALATED` | `warn` token or `#f0b54a` | yes |
| `parked`, `dead`, `done`, `cancelled`, `""`, `"Running"`, any other | `""` | (unpainted) | no |

- Matching is exact and case-sensitive.
- No glyph in the text, no `Pulse`, no opacity animation: `opacity` stays 1.
- Changing `state` on a live instance updates text, tint and visibility (e.g. `running` →
  `parked` hides it; `parked` → `escalated` shows `ESCALATED`).

## Component 3: `ui/components/CloseRunDialog.qml`

An `Item` that fills its owner, containing one `UI.ModalCard`. Renders and emits only: it reads its
props and never changes them.

Properties:

- `property bool shown: false`; `visible: shown`; `z: 100`; `objectName: "closeRunDialog"`.
- `property string runTitle: ""`: the run's title as the row shows it.
- `property string openIn: ""`: the id of another run in which a card of this run is still open.
  The owner fills it from `am reset`'s `open_in` reply field, or before the call from `Runs` data,
  or leaves it blank (RR line 106).
- `property string error: ""`: a refused reset's sentence.
- `property bool busy: false`: a reset in flight.
- `property var theme: T.Theme {}`.
- `readonly property color closeColor`: `closeTone` token or `#ff9442`.
- `readonly property Item focusItem`: the item holding keyboard focus for Escape.

Signals: `confirmRequested()`, `cancelRequested()`.

objectNames: `closeDialogBackdrop`, `closeDialogCard` (passed to `ModalCard`), `closeDialogTitle`,
`closeDialogBody`, `closeDialogOpenIn`, `closeDialogError`, `closeDialogKeep`, `closeDialogAccept`.

Content, top to bottom:

1. **Title** (`closeDialogTitle`, heading variant, bold, elided right): `Close "<runTitle>"?`; when
   `runTitle` is blank or whitespace only: `Close this run?`. The title is used verbatim otherwise
   (quotes or markup in it are plain text: `textFormat: Text.PlainText`).
2. **Body** (`closeDialogBody`, small variant, word-wrapped), exactly:
   `The run is recorded as cancelled. Nothing is deleted and no branch is touched.`
3. **Open-in line** (`closeDialogOpenIn`, small variant, word-wrapped), visible only when `openIn`
   is non-blank after trimming, exactly:
   `A card of this run is also open in run <openIn trimmed>; it stays continuable there.`
   Hidden (and not empty-spaced) when blank.
4. **Error** (`closeDialogError`, small variant, urgent colour, word-wrapped), visible only when
   `error !== ""`, text = `error`.
5. **Buttons** (a `Row`, `Keep` left of `Close`), both `ActionButton`s with the dialog's theme:
   - `closeDialogKeep`: text `Keep`, default (neutral) tone.
   - `closeDialogAccept`: text `Close`, `foreground` = `closeColor`.

Behaviour:

- **Close** click emits `confirmRequested()` exactly once per click while `!busy`.
- **Keep** click, a **backdrop** click and **Escape** each emit `cancelRequested()` exactly once.
- **Return/Enter** never confirms (Close is an explicit choice).
- **Busy:** while `busy`, both buttons are disabled, a Close or Keep click emits nothing, the
  backdrop does not dismiss (`ModalCard.dismissable: false`), and Escape emits nothing. Button texts
  do not change. When `busy` goes back to false all of the above work again.
- **Error:** setting `error` while shown shows it under the body; the dialog stays shown (it never
  changes `shown` itself), so a refused reset keeps its error visible (RR line 132).
- **Focus:** when `shown` becomes true the dialog gives `focusItem` active focus, so Escape works
  without the owner doing anything; `focusItem` is exposed so an owner can re-take focus.
  `focusItem` is a plain focus-scope `Item` carrying the `Keys.onPressed` handler (Escape cancels;
  Return/Enter are left unhandled), never one of the two buttons: a focused button would turn
  Return/Space into a click and break "Return never confirms".
- **Hidden:** with `shown: false` the dialog is invisible and Escape/clicks reach nothing.

## Error paths

- Any `level` / `state` string, including empty, wrong case, padded or unknown, renders per the
  tables above and never throws.
- A theme lacking the new tokens (today's `T.Theme`) renders the fallbacks; a theme that defines
  them renders the theme's values. `theme: null` on a badge falls back to its own Theme.
- Long titles elide; long `openIn` or `error` wrap. Neither breaks the button row.
- No component writes to its own input props.

## Tests

All three files are QML component tests: they need a QML engine to instantiate the components,
read rendered properties, click and press keys. They run under `qmltestrunner` offscreen through
`bash tests/run.sh` against `tests/stubs` (`Style.space(n)` returns `n`). Pattern: `TestCase` with
`when: windowShown`, `createTemporaryObject`, `import "../../helpers/find.js" as H`, SignalSpy,
`import "../../../ui/components" as UI`, `import "../../../ui/theme" as T` (as in
`tst_run_badge.qml` and `tst_resume_verify_dialog.qml`).

To test token-wins without depending on story E, tests pass a plain `QtObject` theme that declares
`foreground`, `dim`, `urgent`, `fontFamily`, `bodySize`, `smallSize`, `captionSize`, `headingSize`
plus the tokens with distinct colours; the fallback cases pass a `T.Theme {}` with token-free
`foreground`/`dim`/`urgent` overrides. (If E has already added the tokens to `T.Theme`, the
fallback case instead uses a `QtObject` theme without them; the test must build that theme itself
rather than rely on `T.Theme` lacking them.)

### `tests/ui/components/tst_run_level_badge.qml` (QML component tier)

1. `test_level_table` (data-driven, rows milestone / story / subtask): label text upper-cased,
   `border.width` 2/1/1, fill alpha 0.22/0.12/0, border and label colour equal `levelColor`.
2. `test_garbage_level_reads_milestone` (data: `""`, `"Story"`, `" story"`, `"epic"`,
   `"__proto__"`): `shownLevel === "milestone"`, text `MILESTONE`, border 2.
3. `test_same_rectangle_for_every_level`: radius equals `Style.space(4)` for all three and is
   `< height / 2`; width and height > 0.
4. `test_tokens_win_over_fallbacks`: with a token theme each level paints its token colour.
5. `test_fallbacks_without_tokens`: with a token-free theme the colours are `#aab8ff`, `#8196ee`,
   `#5d70b8`.
6. `test_label_uses_caption_font`: label font family and pixel size equal the theme's family and
   `captionSize`.
7. `test_level_change_updates_live`: `milestone` → `subtask` changes text, border and fill.
8. `test_not_a_badge`: the root has no `textObjectName`/`paddingY` property (it is not a `Badge`):
   `badge.paddingY === undefined`.

### `tests/ui/components/tst_run_state_badge.qml` (QML component tier)

1. `test_running`: visible, text `RUNNING`, tint = accent token (token theme) / `#7ed491`
   (fallback theme), radius = height/2 (Badge pill), `opacity === 1`.
2. `test_escalated`: visible, text `ESCALATED`, tint = warn token / `#f0b54a`.
3. `test_hidden_states` (data: `parked`, `dead`, `done`, `cancelled`, `""`, `"Running"`,
   `"stopped"`): `visible === false`, text `""`.
4. `test_no_glyphs`: for running and escalated the text contains none of `⟳ ⚠ ⏸`.
5. `test_state_change_updates_live`: running → parked hides; parked → escalated shows `ESCALATED`.
6. `test_object_names`: root `runStateBadge`, label found by `runStateBadgeText`.

### `tests/ui/components/tst_close_run_dialog.qml` (QML component tier)

1. `test_renders_the_wording`: shown dialog with `runTitle: "Fix login"`: card and backdrop found;
   title `Close "Fix login"?`; body text exact; open-in hidden; error hidden; Keep text `Keep`;
   Close text `Close`; Close `foreground` equals `closeColor`.
2. `test_blank_title` (data: `""`, `"   "`): title `Close this run?`.
3. `test_hidden_while_not_shown`: `visible` follows `shown`.
4. `test_open_in_line`: `openIn: " 4a51d663 "` shows
   `A card of this run is also open in run 4a51d663; it stays continuable there.`; `openIn: "  "`
   hides it.
5. `test_close_emits_confirm_once`: one click on Close → `confirmRequested` count 1,
   `cancelRequested` count 0.
6. `test_keep_backdrop_and_escape_cancel` (data: keep / backdrop / escape): each → exactly one
   `cancelRequested`, zero `confirmRequested`; Escape is pressed without the test setting focus.
7. `test_return_does_not_confirm`: Return and Enter emit nothing.
8. `test_busy_blocks_everything`: `busy: true` → both buttons disabled; Close, Keep, backdrop and
   Escape emit nothing; texts unchanged; after `busy = false` a Close click emits once.
9. `test_error_shows_and_dialog_stays`: setting `error` shows `closeDialogError` with that text in
   the theme's `urgent`; `shown` is still true; clearing it hides the line.
10. `test_close_tone_token_and_fallback`: token theme → Close foreground = its `closeTone`; token-free
    theme → `#ff9442`.
11. `test_never_writes_its_props`: after clicks on Close and Keep and Escape, `shown`, `error`,
    `runTitle`, `openIn`, `busy` are unchanged.

### Existing suites (regression tier)

- `tests/architecture/test_layers.py` (pytest): the new files import no store and trip no
  duplication guard.
- `bash tests/run.sh` green overall.

## Out of scope

- Theme tokens in `ui/theme/Theme.qml` (with dark variants) and the `ActionButton` `closeTone` /
  `warn` / accent tones and 14% tint fill: story E (`8c7324d3`). When E lands, F (or E) may switch
  the Close button to the new `ActionButton` tone; this card's explicit `foreground` stays correct
  meanwhile.
- `Runs.runLevel`, `controls().close`, `visibleActions`, reset error sentences: story B (`042b0d8e`).
- `RunControlStore` reset, `closeAsk`/`closeCancel`/`closeConfirm`, `closeRunId`/`closeOpen`, the
  `Close requested…` pending label: story C (`19aa24c1`).
- Backend `run-control.py reset`: story A (`cc7f1fd6`).
- Mounting the dialog in `RunsScreen`, `closeRequested(runId)`, `Panel`/`App` wiring, the new row
  layout and placing the badges, `RunControls` buttons, `RunDetailScreen` tests: story F
  (`8e2ec6be`).
- RR's open questions (id length, RR line 146; RunDetailScreen, RR line 147) do not affect these
  components.
