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

---

# RunLevelBadge, RunStateBadge and CloseRunDialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three presentation-only QML components (`RunLevelBadge`, `RunStateBadge`, `CloseRunDialog`) and their QML component tests. Nothing mounts them yet.

**Architecture:** Each component takes props only and imports neither `core/stores` nor `core/domain`. A tiny shared JS helper, `ui/components/themeToken.js`, reads a colour token from a theme when the theme defines it and otherwise returns a fixed fallback, so the components work before and after story E adds the tokens to `Theme.qml`. The level badge is a plain `Rectangle` with a `ThemedText`. The state badge is a `Badge`. The dialog is an `Item` wrapping `UI.ModalCard`, with a key-only focus item for Escape.

**Tech Stack:** Qt 6 QML (QtQuick), QtTest `TestCase` run by `qmltestrunner` offscreen through `bash tests/run.sh` against `tests/stubs`; pytest for `tests/architecture/test_layers.py`.

**Spec:** `docs/superpowers/specs/build-three-components-b92f02fa.md` (prepended above). Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md`.

## Global Constraints

- `ui/components/**` imports no `core/stores` (and these three import no `core/domain` either); props only.
- The level badge is not built on `Badge.qml`; it is a 4px-radius (`Style.space(4)`) rectangle, the same shape for every level.
- Fallback colours: `levelMilestone` `#aab8ff`, `levelStory` `#8196ee`, `levelSubtask` `#5d70b8`, `accent` `#7ed491`, `warn` `#f0b54a`, `closeTone` `#ff9442`. A defined token always wins, whatever its value. A null theme never throws.
- Do not edit `ui/theme/Theme.qml` or `ui/components/ActionButton.qml` (story E owns them).
- No new file may contain `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:` or `CursorSurface {` (duplication guards in `tests/architecture/test_layers.py`). Text goes through `ThemedText`, buttons through `ActionButton`, the backdrop through `ModalCard`.
- State badge: only `running` → `RUNNING` and `escalated` → `ESCALATED` show; no glyphs (`⟳ ⚠ ⏸`), no `Pulse`, `opacity` stays 1.
- Dialog wording, exactly: title `Close "<runTitle>"?` (blank/whitespace title → `Close this run?`); body `The run is recorded as cancelled. Nothing is deleted and no branch is touched.`; open-in `A card of this run is also open in run <openIn trimmed>; it stays continuable there.`; buttons `Keep` and `Close`.
- House style: 2-space indent, no semicolons, a short prose comment above each component; badges use `property var theme: null` plus `readonly property var palette: <id>.theme || <own T.Theme>`; the dialog uses `property var theme: T.Theme {}`.
- `bash tests/run.sh` is green at the end of every task. It fails on any `FAIL` line and on `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in QML output.

## Review Focus

1. **Escape after the dialog is hidden** (owner sets `shown: false` while the key item still holds focus): nothing is emitted. A hidden Qt Quick item keeps `activeFocus`, so without a `shown` guard in the key handler a stray Escape would cancel a dialog nobody sees (confirmed while prototyping this plan). Test: `test_escape_on_a_hidden_dialog_does_nothing` (Task 3).
2. **Re-opening the dialog** (`shown` false → true → false → true): it takes the focus each time, so Escape works the second time without the owner doing anything. Test: `test_reopening_takes_the_focus_again` (Task 3).
3. **Very long title / open-in / error**: the title elides on one line, the other two wrap, and the Close button stays inside the card. Test: `test_long_text_keeps_the_buttons_in_the_card` (Task 3).
4. **A theme swapped or nulled on a live component** (Panel rebinding its theme; teardown): colours repaint from the new theme and a null theme gives the component's own Theme or the fallback without a `TypeError`. Tests: `test_theme_swap_repaints`, `test_null_theme_uses_its_own_theme` (Task 1), `test_null_theme_uses_its_own_theme` (Task 2), `test_a_null_theme_and_destroy_are_quiet` (Task 3).
5. **A run title containing quotes or markup** (`<b>"x"</b>`): shown verbatim as plain text. Test: `test_title_is_plain_text` (Task 3).

## File Structure

- Create `ui/components/themeToken.js` — `.pragma library`; one function `token(theme, name, fallback)`. Shared by all three components (Task 1 creates it).
- Create `ui/components/RunLevelBadge.qml` — the level rectangle (Task 1).
- Create `ui/components/RunStateBadge.qml` — the RUNNING / ESCALATED pill on `Badge` (Task 2).
- Create `ui/components/CloseRunDialog.qml` — the Close dialog on `ModalCard` (Task 3).
- Create `tests/ui/components/tst_run_level_badge.qml`, `tests/ui/components/tst_run_state_badge.qml`, `tests/ui/components/tst_close_run_dialog.qml`.

`ui/components` has no `qmldir`; the directory import `import "../../../ui/components" as UI` picks up every `.qml` file in it, so no registration step is needed.

How to run things (from the repo root):

- One QML test file plus pytest: `timeout 600 bash tests/run.sh tst_run_level_badge` (the argument is a substring filter on QML test paths; pytest always runs in full). Exit status 0 means green.
- Just one QML file, faster, with full output: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_run_level_badge.qml`
- Architecture tests only: `timeout 300 python3 -m pytest tests/architecture/test_layers.py -q` (if `python3` has no pytest: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_layers.py -q`).
- Everything: `timeout 900 bash tests/run.sh`

Test conventions used below: `Style.space(n)` returns `n` in the stubs; `H.find(item, objectName)` (from `tests/helpers/find.js`) searches children and data depth-first. Colours are compared with `Qt.colorEqual(a, b)`. Each test file builds its own plain `QtObject` themes (one with the tokens, one without) so the fallback case holds whether or not story E has added the tokens to `T.Theme`.

---

### Task 1: `themeToken.js` and `RunLevelBadge`

**Files:**
- Create: `ui/components/themeToken.js`
- Create: `ui/components/RunLevelBadge.qml`
- Test: `tests/ui/components/tst_run_level_badge.qml`

**Interfaces:**
- Consumes: `ui/components/ThemedText.qml` (`theme`, `variant: "caption"`, `color`), `ui/theme/Theme.qml` (`T.Theme {}`), `qs.Commons` `Style.space(n)`.
- Produces:
  - `themeToken.js`: `function token(theme, name, fallback)` → `theme[name]` when `theme` is truthy and `theme[name] !== undefined`, else `fallback`. Imported as `import "themeToken.js" as Tokens` from a file in `ui/components`.
  - `RunLevelBadge` (`objectName: "runLevelBadge"`): `property var theme: null`, `property string level: ""`, `readonly property var palette`, `readonly property string shownLevel` (`"subtask" | "story" | "milestone"`), `readonly property color levelColor`; label `objectName: "runLevelBadgeText"`.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_level_badge.qml`:

```qml
// tests/ui/components/tst_run_level_badge.qml
// ui/components/RunLevelBadge.qml: a run's level as an upper-cased caption in
// a 4px-radius rectangle (not a Badge pill). The milestone has a 2px border and
// a 22% fill, the story 1px and 12%, the subtask 1px and no fill. A level
// token on the theme wins; without one the badge paints RR's dark colour.
import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunLevelBadge"
  when: windowShown
  visible: true
  width: 400; height: 200

  // A theme with the level tokens, each a colour nothing else uses.
  QtObject {
    id: tokenTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Token Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
    property color levelMilestone: "#102030"
    property color levelStory: "#405060"
    property color levelSubtask: "#708090"
  }

  // The same theme without the tokens, built here so the fallback case holds
  // whether or not T.Theme has grown the tokens.
  QtObject {
    id: plainTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Plain Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
  }

  Component { id: badgeC; UI.RunLevelBadge {} }
  Component { id: themeC; T.Theme {} }

  function make(props) {
    var badge = createTemporaryObject(badgeC, tc, props)
    wait(0)
    return badge
  }

  function labelOf(badge) { return H.find(badge, "runLevelBadgeText") }

  // 1
  function test_level_table_data() {
    return [
      { tag: "milestone", level: "milestone", text: "MILESTONE", border: 2, alpha: 0.22 },
      { tag: "story", level: "story", text: "STORY", border: 1, alpha: 0.12 },
      { tag: "subtask", level: "subtask", text: "SUBTASK", border: 1, alpha: 0 }
    ]
  }

  function test_level_table(data) {
    var badge = make({ theme: tokenTheme, level: data.level })
    compare(badge.objectName, "runLevelBadge")
    compare(badge.shownLevel, data.level)
    compare(labelOf(badge).text, data.text)
    compare(badge.border.width, data.border)
    fuzzyCompare(badge.color.a, data.alpha, 0.01)
    verify(Qt.colorEqual(badge.border.color, badge.levelColor), "the border is the level colour")
    verify(Qt.colorEqual(labelOf(badge).color, badge.levelColor), "the label is the level colour")
    compare(badge.visible, true)
  }

  // 2
  function test_garbage_level_reads_milestone_data() {
    return [
      { tag: "empty", level: "" },
      { tag: "capitalised", level: "Story" },
      { tag: "padded", level: " story" },
      { tag: "unknown", level: "epic" },
      { tag: "proto", level: "__proto__" }
    ]
  }

  function test_garbage_level_reads_milestone(data) {
    var badge = make({ theme: tokenTheme, level: data.level })
    compare(badge.shownLevel, "milestone")
    compare(labelOf(badge).text, "MILESTONE")
    compare(badge.border.width, 2)
    verify(Qt.colorEqual(badge.levelColor, tokenTheme.levelMilestone))
  }

  // 3
  function test_same_rectangle_for_every_level() {
    var levels = ["milestone", "story", "subtask"]
    for (var i = 0; i < levels.length; i++) {
      var badge = make({ theme: tokenTheme, level: levels[i] })
      compare(badge.radius, Style.space(4), levels[i])
      verify(badge.radius < badge.height / 2, levels[i] + " is a rectangle, not a pill")
      verify(badge.width > 0, levels[i] + " has a width")
      verify(badge.height > 0, levels[i] + " has a height")
    }
  }

  // 4
  function test_tokens_win_over_fallbacks() {
    verify(Qt.colorEqual(make({ theme: tokenTheme, level: "milestone" }).levelColor, "#102030"))
    verify(Qt.colorEqual(make({ theme: tokenTheme, level: "story" }).levelColor, "#405060"))
    verify(Qt.colorEqual(make({ theme: tokenTheme, level: "subtask" }).levelColor, "#708090"))
  }

  // 5
  function test_fallbacks_without_tokens() {
    verify(Qt.colorEqual(make({ theme: plainTheme, level: "milestone" }).levelColor, "#aab8ff"))
    verify(Qt.colorEqual(make({ theme: plainTheme, level: "story" }).levelColor, "#8196ee"))
    verify(Qt.colorEqual(make({ theme: plainTheme, level: "subtask" }).levelColor, "#5d70b8"))
  }

  // 6
  function test_label_uses_caption_font() {
    var label = labelOf(make({ theme: tokenTheme, level: "story" }))
    compare(label.font.family, "Token Sans")
    compare(label.font.pixelSize, 11)
  }

  // 7
  function test_level_change_updates_live() {
    var badge = make({ theme: tokenTheme, level: "milestone" })
    compare(labelOf(badge).text, "MILESTONE")
    badge.level = "subtask"
    compare(labelOf(badge).text, "SUBTASK")
    compare(badge.border.width, 1)
    compare(badge.color.a, 0)
    verify(Qt.colorEqual(badge.border.color, "#708090"))
  }

  // 8
  function test_not_a_badge() {
    var badge = make({ theme: tokenTheme, level: "story" })
    compare(badge.paddingY, undefined, "Badge's paddingY is not here")
    compare(badge.textObjectName, undefined, "nor Badge's textObjectName")
  }

  // Review Focus: a theme swapped on a live badge repaints it.
  function test_theme_swap_repaints() {
    var badge = make({ theme: tokenTheme, level: "story" })
    verify(Qt.colorEqual(badge.levelColor, "#405060"))
    badge.theme = plainTheme
    verify(Qt.colorEqual(badge.levelColor, "#8196ee"))
    verify(Qt.colorEqual(labelOf(badge).color, "#8196ee"))
    badge.theme = tokenTheme
    verify(Qt.colorEqual(badge.border.color, "#405060"))
  }

  // Review Focus: a null theme falls back to the badge's own Theme, quietly.
  function test_null_theme_uses_its_own_theme() {
    var own = createTemporaryObject(themeC, tc)
    var expected = own.levelStory === undefined ? "#8196ee" : own.levelStory
    var badge = make({ theme: tokenTheme, level: "story" })
    badge.theme = null
    wait(0)
    verify(Qt.colorEqual(badge.levelColor, expected))
    compare(labelOf(badge).text, "STORY")
    badge.destroy()
    wait(0)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_run_level_badge.qml`
Expected: FAIL — the file does not load, with an error like `RunLevelBadge is not a type` (no test functions run).

- [ ] **Step 3: Write the token helper**

Create `ui/components/themeToken.js`:

```js
.pragma library

// A colour token the theme may not define yet: the theme's value when the
// theme is an object and reading `name` on it gives something, else
// `fallback`. A defined token always wins, whatever its value. A null theme
// (a view being torn down) gives the fallback rather than throwing.
function token(theme, name, fallback) {
  if (!theme) return fallback
  var value = theme[name]
  return value === undefined ? fallback : value
}
```

- [ ] **Step 4: Write the component**

Create `ui/components/RunLevelBadge.qml`:

```qml
import QtQuick
import qs.Commons
import "../theme" as T
import "themeToken.js" as Tokens

// A run's level (milestone, story or subtask) as an upper-cased caption in a
// small 4px-radius rectangle. Every level is the same shape: the milestone has
// a 2px border and a 22% fill, the story a 1px border and a 12% fill, the
// subtask a 1px border and no fill. Not a Badge, which is a pill. Presentation
// only: `level` is Runs.runLevel's string, and anything but "subtask" or
// "story" reads as a milestone.
Rectangle {
  id: levelBadge
  objectName: "runLevelBadge"

  // The owner's Theme, or none: `palette` then falls back to the badge's own.
  // Both are objects, and tearing a view down nulls them while the bindings
  // below still run once, so every read of `palette` is guarded; the guard's
  // value is never painted.
  property var theme: null
  property string level: ""

  readonly property var palette: levelBadge.theme || levelTheme
  readonly property string shownLevel: (levelBadge.level === "subtask" || levelBadge.level === "story")
    ? levelBadge.level : "milestone"
  readonly property color levelColor: levelBadge.shownLevel === "subtask"
    ? Tokens.token(levelBadge.palette, "levelSubtask", "#5d70b8")
    : levelBadge.shownLevel === "story" ? Tokens.token(levelBadge.palette, "levelStory", "#8196ee")
    : Tokens.token(levelBadge.palette, "levelMilestone", "#aab8ff")

  width: label.implicitWidth + Style.space(12)
  height: label.implicitHeight + Style.space(4)
  radius: Style.space(4)
  border.width: levelBadge.shownLevel === "milestone" ? 2 : 1
  border.color: levelBadge.levelColor
  color: levelBadge.shownLevel === "milestone" ? Qt.alpha(levelBadge.levelColor, 0.22)
    : levelBadge.shownLevel === "story" ? Qt.alpha(levelBadge.levelColor, 0.12)
    : "transparent"

  ThemedText {
    id: label
    objectName: "runLevelBadgeText"
    anchors.centerIn: parent
    theme: levelBadge.palette
    variant: "caption"
    text: levelBadge.shownLevel.toUpperCase()
    color: levelBadge.levelColor
  }

  T.Theme { id: levelTheme }
}
```

Notes for the implementer:
- Do not set `font.family:` anywhere (a duplication guard forbids it outside `ThemedText.qml`); the caption font comes from `ThemedText`'s `variant: "caption"`.
- `radius: Style.space(4)` — never `radius: height / 2` (another guard; and it would be a pill).
- `shownLevel` matches exactly; do not trim or lower-case `level`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_run_level_badge.qml`
Expected: `Totals: 18 passed, 0 failed`, and no `TypeError` / `ReferenceError` / `Unable to assign` lines in the output.

- [ ] **Step 6: Run the gate for this file (pytest + this QML file)**

Run: `timeout 600 bash tests/run.sh tst_run_level_badge; echo "exit=$?"`
Expected: pytest all passed (including `tests/architecture/test_layers.py`), the QML file prints `Totals: 18 passed, 0 failed`, and `exit=0`.

- [ ] **Step 7: Commit**

```bash
git add ui/components/themeToken.js ui/components/RunLevelBadge.qml tests/ui/components/tst_run_level_badge.qml
git commit -m "feat(runs): RunLevelBadge, a level rectangle that reads theme tokens with fallbacks"
```

---

### Task 2: `RunStateBadge`

**Files:**
- Create: `ui/components/RunStateBadge.qml`
- Test: `tests/ui/components/tst_run_state_badge.qml`

**Interfaces:**
- Consumes: `ui/components/Badge.qml` (`theme`, `palette`, `text`, `tint`, `textObjectName`; pill `radius: height / 2`; 18% fill), `ui/components/themeToken.js` `token(theme, name, fallback)` from Task 1.
- Produces: `RunStateBadge` (`objectName: "runStateBadge"`, `textObjectName: "runStateBadgeText"`); input is Item's own `state` string; `text` is `"RUNNING"`, `"ESCALATED"` or `""`; `visible` is `text !== ""`; `tint` is the `accent` token / `#7ed491` (and `warn` / `#f0b54a` for escalated).

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_run_state_badge.qml`:

```qml
// tests/ui/components/tst_run_state_badge.qml
// ui/components/RunStateBadge.qml: RUNNING in the accent tint and ESCALATED in
// the warn tint, on the Badge pill; every other state shows nothing. No glyph,
// no pulse. A token on the theme wins; without one the badge paints its own
// green and amber.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunStateBadge"
  when: windowShown
  visible: true
  width: 400; height: 200

  // A theme with the accent and warn tokens, each a colour nothing else uses.
  QtObject {
    id: tokenTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Token Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
    property color accent: "#11aa22"
    property color warn: "#cc8800"
  }

  // The same theme without the tokens, built here so the fallback case holds
  // whether or not T.Theme has grown the tokens.
  QtObject {
    id: plainTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Plain Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
  }

  Component { id: badgeC; UI.RunStateBadge {} }
  Component { id: themeC; T.Theme {} }

  function make(props) {
    var badge = createTemporaryObject(badgeC, tc, props)
    wait(0)
    return badge
  }

  function textOf(badge) { return H.find(badge, "runStateBadgeText").text }

  // 1
  function test_running() {
    var badge = make({ theme: tokenTheme, state: "running" })
    compare(badge.visible, true)
    compare(textOf(badge), "RUNNING")
    verify(Qt.colorEqual(badge.tint, "#11aa22"), "the accent token")
    compare(badge.radius, badge.height / 2, "the Badge pill")
    compare(badge.opacity, 1)
    wait(120)
    compare(badge.opacity, 1, "it never fades")
    verify(Qt.colorEqual(make({ theme: plainTheme, state: "running" }).tint, "#7ed491"), "the fallback green")
  }

  // 2
  function test_escalated() {
    var badge = make({ theme: tokenTheme, state: "escalated" })
    compare(badge.visible, true)
    compare(textOf(badge), "ESCALATED")
    verify(Qt.colorEqual(badge.tint, "#cc8800"), "the warn token")
    verify(Qt.colorEqual(make({ theme: plainTheme, state: "escalated" }).tint, "#f0b54a"), "the fallback amber")
  }

  // 3
  function test_hidden_states_data() {
    return [
      { tag: "parked", state: "parked" },
      { tag: "dead", state: "dead" },
      { tag: "done", state: "done" },
      { tag: "cancelled", state: "cancelled" },
      { tag: "empty", state: "" },
      { tag: "capitalised", state: "Running" },
      { tag: "unknown", state: "stopped" }
    ]
  }

  function test_hidden_states(data) {
    var badge = make({ theme: tokenTheme, state: data.state })
    compare(badge.visible, false)
    compare(textOf(badge), "")
  }

  // 4
  function test_no_glyphs() {
    var states = ["running", "escalated"]
    var glyphs = ["⟳", "⚠", "⏸"]
    for (var i = 0; i < states.length; i++) {
      var text = textOf(make({ theme: tokenTheme, state: states[i] }))
      for (var j = 0; j < glyphs.length; j++)
        verify(text.indexOf(glyphs[j]) === -1, states[i] + " shows no " + glyphs[j])
    }
  }

  // 5
  function test_state_change_updates_live() {
    var badge = make({ theme: tokenTheme, state: "running" })
    compare(badge.visible, true)
    badge.state = "parked"
    compare(badge.visible, false)
    compare(textOf(badge), "")
    badge.state = "escalated"
    compare(badge.visible, true)
    compare(textOf(badge), "ESCALATED")
    verify(Qt.colorEqual(badge.tint, "#cc8800"))
  }

  // 6
  function test_object_names() {
    var badge = make({ theme: tokenTheme, state: "running" })
    compare(badge.objectName, "runStateBadge")
    verify(H.find(badge, "runStateBadgeText"), "the label")
  }

  // Review Focus: a null theme falls back to the badge's own Theme, quietly.
  function test_null_theme_uses_its_own_theme() {
    var own = createTemporaryObject(themeC, tc)
    var expected = own.accent === undefined ? "#7ed491" : own.accent
    var badge = make({ theme: tokenTheme, state: "running" })
    badge.theme = null
    wait(0)
    verify(Qt.colorEqual(badge.tint, expected))
    compare(textOf(badge), "RUNNING")
    badge.destroy()
    wait(0)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_run_state_badge.qml`
Expected: FAIL — the file does not load, with an error like `RunStateBadge is not a type`.

- [ ] **Step 3: Write the component**

Create `ui/components/RunStateBadge.qml`:

```qml
import QtQuick
import "themeToken.js" as Tokens

// The two run states the Runs row names in words: RUNNING in the accent tint
// and ESCALATED in the warn tint, on the Badge pill. Every other state (parked,
// dead, done, cancelled, anything unknown) shows no badge. No glyph and no
// pulse. Presentation only: `state` (Item's own string property, used as
// plain text) is a Runs.runState name, matched exactly.
Badge {
  id: stateBadge
  objectName: "runStateBadge"
  textObjectName: "runStateBadgeText"

  text: stateBadge.state === "running" ? "RUNNING"
    : stateBadge.state === "escalated" ? "ESCALATED"
    : ""
  tint: stateBadge.state === "escalated" ? Tokens.token(stateBadge.palette, "warn", "#f0b54a")
    : Tokens.token(stateBadge.palette, "accent", "#7ed491")
  visible: stateBadge.text !== ""
}
```

Notes for the implementer:
- No `Pulse`, no `opacity` binding, no glyphs. Do not import `runGlyphs.js`.
- `state` is Item's built-in string property; do not declare a new `state` property (it would fail to load).
- The pill shape and 18% fill come from `Badge`; do not set `radius` or `color` here.

- [ ] **Step 4: Run the test to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_run_state_badge.qml`
Expected: `Totals: 15 passed, 0 failed`, with no `TypeError` / `ReferenceError` lines.

- [ ] **Step 5: Run the gate for this file (pytest + this QML file)**

Run: `timeout 600 bash tests/run.sh tst_run_state_badge; echo "exit=$?"`
Expected: pytest all passed, the QML file prints `Totals: 15 passed, 0 failed`, and `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add ui/components/RunStateBadge.qml tests/ui/components/tst_run_state_badge.qml
git commit -m "feat(runs): RunStateBadge, RUNNING and ESCALATED on the Badge pill"
```

---

### Task 3: `CloseRunDialog`

**Files:**
- Create: `ui/components/CloseRunDialog.qml`
- Test: `tests/ui/components/tst_close_run_dialog.qml`

**Interfaces:**
- Consumes: `ui/components/ModalCard.qml` (`shown`, `dismissable`, `maxWidth`, `backdropObjectName`, `cardObjectName`, `dismissed()`; children go into its card's `Column`), `ui/components/ThemedText.qml`, `ui/components/ActionButton.qml` (`theme`, `text`, `enabled`, `foreground`, `clicked()`), `ui/components/themeToken.js` `token(theme, name, fallback)` from Task 1.
- Produces: `CloseRunDialog` (`objectName: "closeRunDialog"`, `z: 100`, `visible: shown`) with
  - props `shown: bool = false`, `runTitle: string = ""`, `openIn: string = ""`, `error: string = ""`, `busy: bool = false`, `theme: var = T.Theme {}`;
  - `readonly property color closeColor` (`closeTone` token or `#ff9442`), `readonly property color urgentColor`, `readonly property Item focusItem` (the key item, `objectName: "closeDialogKeys"`);
  - signals `confirmRequested()`, `cancelRequested()`;
  - objectNames `closeDialogBackdrop`, `closeDialogCard`, `closeDialogTitle`, `closeDialogBody`, `closeDialogOpenIn`, `closeDialogError`, `closeDialogKeep`, `closeDialogAccept`.
  Story F mounts it and wires `confirmRequested`/`cancelRequested` to the store.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_close_run_dialog.qml`:

```qml
// tests/ui/components/tst_close_run_dialog.qml
// ui/components/CloseRunDialog.qml: `Close "<title>"?` over a dimmed backdrop,
// what closing does, where else the run is open, the error in urgent, then
// Keep and an orange Close. Close confirms; Keep, the backdrop and Escape
// cancel; Return never confirms; busy blocks every way out and in.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "CloseRunDialog"
  when: windowShown
  visible: true
  width: 640; height: 480

  // A theme with the closeTone token, a colour nothing else uses.
  QtObject {
    id: tokenTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Token Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
    property color closeTone: "#aa5500"
  }

  // The same theme without the token, built here so the fallback case holds
  // whether or not T.Theme has grown it.
  QtObject {
    id: plainTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Plain Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
  }

  Component { id: dialogC; UI.CloseRunDialog { width: 640; height: 480 } }
  SignalSpy { id: confirms; signalName: "confirmRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  readonly property string bodyText: "The run is recorded as cancelled. Nothing is deleted and no branch is touched."

  // A shown dialog for "Fix login" in the token theme; `over` replaces any prop.
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, Object.assign({ shown: true, runTitle: "Fix login", theme: tokenTheme }, over || {}))
    confirms.target = d; cancels.target = d
    confirms.clear(); cancels.clear()
    wait(30)
    return d
  }
  // A freshly laid-out item is placed on the next frame: wait, so the click
  // lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  // 1
  function test_renders_the_wording() {
    var d = make()
    compare(d.visible, true)
    compare(d.objectName, "closeRunDialog")
    verify(H.find(d, "closeDialogCard"), "the modal card")
    verify(H.find(d, "closeDialogBackdrop"), "the backdrop")
    compare(H.find(d, "closeDialogTitle").text, "Close \"Fix login\"?")
    compare(H.find(d, "closeDialogBody").text, tc.bodyText)
    compare(H.find(d, "closeDialogBody").wrapMode, Text.WordWrap)
    compare(H.find(d, "closeDialogOpenIn").visible, false)
    compare(H.find(d, "closeDialogError").visible, false)
    compare(H.find(d, "closeDialogKeep").text, "Keep")
    var accept = H.find(d, "closeDialogAccept")
    compare(accept.text, "Close")
    verify(Qt.colorEqual(accept.foreground, d.closeColor), "Close is painted in the close tone")
  }

  // 2
  function test_blank_title_data() {
    return [
      { tag: "empty", title: "" },
      { tag: "spaces", title: "   " }
    ]
  }

  function test_blank_title(data) {
    var d = make({ runTitle: data.title })
    compare(H.find(d, "closeDialogTitle").text, "Close this run?")
  }

  // 3
  function test_hidden_while_not_shown() {
    var d = make({ shown: false })
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    d.shown = false
    compare(d.visible, false)
  }

  // 4
  function test_open_in_line() {
    var d = make({ openIn: " 4a51d663 " })
    var line = H.find(d, "closeDialogOpenIn")
    compare(line.visible, true)
    compare(line.text, "A card of this run is also open in run 4a51d663; it stays continuable there.")
    compare(line.wrapMode, Text.WordWrap)
    d.openIn = "  "
    compare(line.visible, false)
  }

  // 5
  function test_close_emits_confirm_once() {
    var d = make()
    click(H.find(d, "closeDialogAccept"))
    compare(confirms.count, 1)
    compare(cancels.count, 0)
  }

  // 6
  function test_keep_backdrop_and_escape_cancel_data() {
    return [
      { tag: "keep", way: "keep" },
      { tag: "backdrop", way: "backdrop" },
      { tag: "escape", way: "escape" }
    ]
  }

  function test_keep_backdrop_and_escape_cancel(data) {
    var d = make()
    if (data.way === "keep") click(H.find(d, "closeDialogKeep"))
    else if (data.way === "backdrop") mouseClick(H.find(d, "closeDialogBackdrop"), 2, 2)
    else keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    compare(confirms.count, 0)
    mouseClick(H.find(d, "closeDialogCard"), 3, 3)
    compare(cancels.count, 1, "a click on the card does not cancel")
  }

  // 7
  function test_return_does_not_confirm() {
    var d = make()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(confirms.count, 0)
    compare(cancels.count, 0)
  }

  // 8
  function test_busy_blocks_everything() {
    var d = make({ busy: true })
    var keep = H.find(d, "closeDialogKeep"), accept = H.find(d, "closeDialogAccept")
    compare(keep.enabled, false)
    compare(accept.enabled, false)
    click(accept)
    click(keep)
    mouseClick(H.find(d, "closeDialogBackdrop"), 2, 2)
    keyClick(Qt.Key_Escape)
    compare(confirms.count, 0)
    compare(cancels.count, 0)
    compare(keep.text, "Keep")
    compare(accept.text, "Close")
    d.busy = false
    compare(keep.enabled, true)
    compare(accept.enabled, true)
    click(accept)
    compare(confirms.count, 1)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1, "Escape works again")
  }

  // 9
  function test_error_shows_and_dialog_stays() {
    var d = make()
    var line = H.find(d, "closeDialogError")
    d.error = "The run is busy."
    compare(line.visible, true)
    compare(line.text, "The run is busy.")
    verify(Qt.colorEqual(line.color, tokenTheme.urgent), "in the theme's urgent")
    compare(line.wrapMode, Text.WordWrap)
    compare(d.shown, true)
    compare(d.visible, true)
    d.error = ""
    compare(line.visible, false)
  }

  // 10
  function test_close_tone_token_and_fallback() {
    var d = make()
    verify(Qt.colorEqual(H.find(d, "closeDialogAccept").foreground, "#aa5500"), "the token")
    var plain = make({ theme: plainTheme })
    verify(Qt.colorEqual(H.find(plain, "closeDialogAccept").foreground, "#ff9442"), "the fallback orange")
  }

  // 11
  function test_never_writes_its_props() {
    var d = make({ openIn: "4a51d663", error: "x" })
    click(H.find(d, "closeDialogAccept"))
    click(H.find(d, "closeDialogKeep"))
    keyClick(Qt.Key_Escape)
    compare(confirms.count, 1)
    compare(cancels.count, 2)
    compare(d.shown, true)
    compare(d.error, "x")
    compare(d.runTitle, "Fix login")
    compare(d.openIn, "4a51d663")
    compare(d.busy, false)
  }

  // Review Focus 1: once hidden, Escape reaches nothing.
  function test_escape_on_a_hidden_dialog_does_nothing() {
    var d = make()
    d.shown = false
    wait(0)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 0)
  }

  // Review Focus 2: a dialog shown again takes the focus again, unprompted.
  function test_reopening_takes_the_focus_again() {
    var d = make({ shown: false })
    d.shown = true
    wait(0)
    verify(d.focusItem.activeFocus, "showing it focuses the key item")
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    d.shown = false
    wait(0)
    d.shown = true
    wait(0)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 2)
  }

  // Review Focus 3: the focus item is the key item, never a button.
  function test_focus_item_is_not_a_button() {
    var d = make()
    verify(d.focusItem, "a focus item")
    compare(d.focusItem.objectName, "closeDialogKeys")
    verify(d.focusItem.activeFocus)
  }

  // Review Focus 4: a long title elides, a long open-in and error wrap, and
  // the buttons stay inside the card.
  function test_long_text_keeps_the_buttons_in_the_card() {
    var long = "word ".repeat(80)
    var d = make({ runTitle: long, openIn: long, error: long })
    wait(30)
    var card = H.find(d, "closeDialogCard"), title = H.find(d, "closeDialogTitle")
    compare(title.elide, Text.ElideRight)
    verify(title.truncated, "the title elides")
    compare(title.lineCount, 1)
    verify(H.find(d, "closeDialogOpenIn").lineCount > 1, "open-in wraps")
    verify(H.find(d, "closeDialogError").lineCount > 1, "the error wraps")
    var accept = H.find(d, "closeDialogAccept")
    var p = accept.mapToItem(card, 0, 0)
    verify(p.x + accept.width <= card.width, "Close is inside the card's width")
    verify(p.y + accept.height <= card.height, "Close is inside the card's height")
  }

  // Review Focus 5: a title with quotes or markup is shown verbatim.
  function test_title_is_plain_text() {
    var d = make({ runTitle: "<b>\"x\"</b>" })
    var title = H.find(d, "closeDialogTitle")
    compare(title.textFormat, Text.PlainText)
    compare(title.text, "Close \"<b>\"x\"</b>\"?")
  }

  // A null theme (teardown) paints the fallbacks and throws nothing.
  function test_a_null_theme_and_destroy_are_quiet() {
    var d = make()
    d.theme = null
    wait(0)
    verify(Qt.colorEqual(d.closeColor, "#ff9442"))
    d.destroy()
    wait(0)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_close_run_dialog.qml`
Expected: FAIL — the file does not load, with an error like `CloseRunDialog is not a type`.

- [ ] **Step 3: Write the component**

Create `ui/components/CloseRunDialog.qml`:

```qml
import QtQuick
import qs.Commons
import qs.Commons as Cm
import "../components" as UI
import "../theme" as T
import "themeToken.js" as Tokens

// The Close dialog over a dimmed backdrop: `Close "<runTitle>"?`, that the run
// is recorded as cancelled and nothing is deleted, where else a card of the
// run is still open (`openIn`), `error` in urgent, then Keep and an orange
// Close. No typed confirmation. Renders and emits only: reads shown, runTitle,
// openIn, error, busy and theme and never changes them. Emits
// confirmRequested() for a click on Close, and cancelRequested() for Keep, the
// backdrop or Escape; Return never confirms. While busy nothing emits.
// focusItem is a key-only item that takes the focus when the dialog is shown.
// objectNames: closeDialogBackdrop, closeDialogCard, closeDialogTitle,
// closeDialogBody, closeDialogOpenIn, closeDialogError, closeDialogKeep,
// closeDialogAccept.
Item {
  id: dialog
  objectName: "closeRunDialog"
  z: 100

  property bool shown: false
  // The run's title as the row shows it.
  property string runTitle: ""
  // Another run in which a card of this run is still open, or blank.
  property string openIn: ""
  property string error: ""
  property bool busy: false
  // Colours and fonts; null falls back to the shell's Color.
  property var theme: T.Theme {}

  readonly property color closeColor: Tokens.token(dialog.theme, "closeTone", "#ff9442")
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Cm.Color.urgent
  readonly property Item focusItem: keyItem

  signal confirmRequested()
  signal cancelRequested()

  visible: shown
  onShownChanged: dialog.takeFocus()
  Component.onCompleted: dialog.takeFocus()

  function takeFocus() {
    if (dialog.shown) keyItem.forceActiveFocus()
  }

  // Escape cancels unless busy, and is swallowed either way; Return and Enter
  // are left alone, so they never confirm. A hidden item keeps its focus, so
  // a hidden dialog leaves every key alone.
  Item {
    id: keyItem
    objectName: "closeDialogKeys"
    Keys.onPressed: function(event) {
      if (!dialog.shown || event.key !== Qt.Key_Escape) return
      if (!dialog.busy) dialog.cancelRequested()
      event.accepted = true
    }
  }

  UI.ModalCard {
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(440)
    backdropObjectName: "closeDialogBackdrop"
    cardObjectName: "closeDialogCard"
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      objectName: "closeDialogTitle"
      variant: "heading"
      theme: dialog.theme
      width: parent.width
      text: dialog.runTitle.trim() === "" ? "Close this run?" : "Close \"" + dialog.runTitle + "\"?"
      textFormat: Text.PlainText
      font.bold: true
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "closeDialogBody"
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: "The run is recorded as cancelled. Nothing is deleted and no branch is touched."
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "closeDialogOpenIn"
      variant: "small"
      theme: dialog.theme
      visible: dialog.openIn.trim() !== ""
      width: parent.width
      text: "A card of this run is also open in run " + dialog.openIn.trim() + "; it stays continuable there."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "closeDialogError"
      variant: "small"
      theme: dialog.theme
      visible: dialog.error !== ""
      width: parent.width
      text: dialog.error
      textFormat: Text.PlainText
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        objectName: "closeDialogKeep"
        text: "Keep"
        enabled: !dialog.busy
        theme: dialog.theme
        onClicked: if (!dialog.busy) dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "closeDialogAccept"
        text: "Close"
        enabled: !dialog.busy
        foreground: dialog.closeColor
        theme: dialog.theme
        onClicked: if (!dialog.busy) dialog.confirmRequested()
      }
    }
  }
}
```

Notes for the implementer:
- `focusItem` must be the plain key `Item`, never a button: a focused button turns Return/Space into a click, which would break "Return never confirms".
- Keep the `!dialog.shown` guard in the key handler: a hidden item keeps `activeFocus` in Qt Quick, so without it Escape on a hidden dialog still emits `cancelRequested()` (Review Focus 1).
- Focus is taken both in `onShownChanged` and in `Component.onCompleted` (a dialog created with `shown: true` gets no change signal).
- The Close button sets `foreground: dialog.closeColor` explicitly; do not add an ActionButton `tone` (story E owns ActionButton tones).
- Neither the backdrop colour nor `bordered:` appears here; both come from `ModalCard` and `ActionButton`.
- Never assign to `shown`, `runTitle`, `openIn`, `error` or `busy` inside this file.

- [ ] **Step 4: Run the test to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_close_run_dialog.qml`
Expected: `Totals: 22 passed, 0 failed`, with no `TypeError` / `ReferenceError` / `Unable to assign` lines.

- [ ] **Step 5: Run the whole suite**

Run: `timeout 900 bash tests/run.sh; echo "exit=$?"`
Expected: pytest all passed (including `tests/architecture/test_layers.py`: no store import, no duplication-guard hit), every QML file prints `0 failed`, and `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add ui/components/CloseRunDialog.qml tests/ui/components/tst_close_run_dialog.qml
git commit -m "feat(runs): CloseRunDialog, Keep or an orange Close over the modal card"
```

---

## Self-review against the spec

- Inherited constraints: no store/domain imports (all tasks; arch test in each gate); level badge a non-Badge 4px rectangle (Task 1, tests 3 and 8); level colours and tokens (Task 1, tests 4-5); state badge RUNNING/ESCALATED only, no glyph/pulse (Task 2, tests 1-5); close tone (Task 3, test 10); ModalCard dialog, title/body/buttons, Escape and Keep (Task 3, tests 1, 2, 6); duplication guards (each task's `tests/run.sh` gate); house conventions (code as given).
- Theme tokens read-when-present with fallbacks, null theme quiet: `themeToken.js` (Task 1); token/fallback tests in all three files; null-theme tests in all three.
- Component 1 table, garbage levels, radius, size, caption font, live change, always visible: Task 1 tests 1-8.
- Component 2 table, exact matching, opacity 1, live change, objectNames: Task 2 tests 1-6.
- Component 3 props, signals, objectNames, content order, Close/Keep/backdrop/Escape, Return, busy, error stays, focus, hidden: Task 3 tests 1-11 plus Review Focus tests.
- Error paths: wrong-case/padded/unknown strings (Task 1 test 2, Task 2 test 3); theme without tokens (fallback tests); long text (Review Focus 3); no prop writes (Task 3 test 11).
- Spec test lists: every numbered test in the spec's Tests section appears under the same name.
<!-- task-pipeline: validated -->
