# Theme tokens and ActionButton tones for the Runs row redesign: design

Card: `07140ee4` "Add tokens and tones + tests", the subtask of story E (`8c7324d3`, theme).
Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md`, cited below as **RR**
with line numbers. Contract card: `docs/superpowers/specs/write-contract-stubs-6f9f8639.md`, cited
as **WC**.

## Purpose

Stories D (components) and F (wiring) draw the level badges, the state badge, the Close dialog
and the new row buttons with colours that do not exist yet. This card adds those colours to the
shared `Theme` as named tokens with a light and a dark value, and teaches `ActionButton` the tone
names the buttons will use. After this card, D and F write `theme.levelStory` or
`tone: "close"` and get the right colour; nobody hard-codes a hex outside `ui/theme`.

The card changes `ui/theme/Theme.qml`, `ui/components/ActionButton.qml`,
`tests/ui/components/tst_theme.qml` and `tests/ui/components/tst_action_button.qml`. Nothing else.

## Inherited constraints

- Level colours are theme tokens named `levelMilestone`, `levelStory`, `levelSubtask` in
  `ui/theme`, with a dark variant (RR line 58). Values (RR lines 52-56):

  | Token | Light | Dark |
  |---|---|---|
  | `levelMilestone` | `#2b3f9e` | `#aab8ff` |
  | `levelStory` | `#4a67d6` | `#8196ee` |
  | `levelSubtask` | `#7f93d9` | `#5d70b8` |

- Amber is not used for levels (RR line 58).
- `closeTone` is orange, `#c4560a` light / `#ff9442` dark (RR line 77).
- `ActionButton` gains a `warn` tone next to the existing `danger`, and Resume/Relaunch use "the
  accent tone" (RR line 77). The state badge uses an "accent-green tint" for RUNNING and a "warn
  tint" for ESCALATED (RR line 62); the reason line is in "warn colour" (RR line 34). Pause is
  amber, Resume/Relaunch green, Cancel red, Close orange (RR lines 70-73).
- `ui/components/**` import no `core/stores` (RR line 21; `tests/architecture/test_layers.py`).
- `bash tests/run.sh` is green before and after (RR line 136). It fails on any `FAIL` line and on
  `TypeError`, `ReferenceError`, `Unable to assign`, `non-existent` or `is not a function` in QML
  output (`tests/run.sh` lines 31-35).
- Story E is theme only; components and wiring are D and F (WC lines 10-11, 219, 240).

## Decisions this card makes (the parent leaves them open)

1. **How "dark" is chosen.** Nothing in the plugin knows light from dark today, and the shell's
   `Cm.Color` exposes no such flag. `Theme` gains `property bool dark`, defaulting to "the
   foreground is light": the relative luminance of `foreground`
   (`0.2126·r + 0.7152·g + 0.0722·b` on Qt's 0-1 channels) is greater than `0.5`. Light text
   means a dark background. It is a plain property, so `Panel.qml` or a test may assign it
   outright; `Panel.qml` is not changed by this card and keeps the derived value, which follows
   the bar's foreground.
2. **`warn` and `accent` hexes.** RR names both tones but gives no hex. This card fixes them:

   | Token | Light | Dark | Why |
   |---|---|---|---|
   | `warn` | `#a86b00` | `#f2b84b` | amber (RR line 70: Pause is amber), distinct from `closeTone` orange |
   | `accent` | `#2f7d32` | `#7fb069` | green (RR lines 62, 71-73); the dark value is the green the board already uses for `done` (`core/domain/board.js` line 62) |

   `accent` is a fixed green, **not** the shell's `Cm.Color.accent`: the shell's accent changes
   with the Omarchy theme and defaults to a grey (`#cacccc`), which would not read as "go". No
   new `Cm.Color` field is read, so `tests/stubs/qs/Commons/Color.qml` is unchanged.
3. **Every token follows `dark` live.** Each of the six tokens is a binding on `theme.dark`, so
   flipping `dark` (or changing `foreground` across the 0.5 line) repaints everything bound to it.
   A caller may still assign a token directly; that replaces the binding, as for `foreground`
   today.

## Observable behaviour

### `Theme` (`ui/theme/Theme.qml`)

- Existing properties (`foreground`, `dim`, `urgent`, `fontFamily`, the four sizes) keep their
  names, types and defaults.
- New `property bool dark`: `true` when `foreground`'s luminance is above `0.5`, else `false`.
  With the test stub's `Cm.Color.foreground` (`#ddd`) a default `Theme` is dark; a `Theme` with
  `foreground: "#202020"` is light. Exactly `0.5` is light (strictly greater is dark).
- New `property color` tokens `levelMilestone`, `levelStory`, `levelSubtask`, `closeTone`, `warn`,
  `accent`, each equal to its dark hex when `dark` is true and its light hex otherwise (tables
  above).
- Setting `dark: false` on a Theme whose foreground is light gives the light values, and the
  reverse; the explicit value wins over the derived one.
- A short `//` comment above the new block says what `dark` means and that the token hexes come
  from the Runs row design (match the file's comment style: one or two lines of prose).

### `ActionButton` (`ui/components/ActionButton.qml`)

`tone` keeps its type (`string`) and default (`"normal"`). `foreground` maps:

| `tone` | `foreground` |
|---|---|
| `"normal"` | `palette.foreground` |
| `"danger"` | `palette.urgent` (unchanged) |
| `"warn"` | `palette.warn` |
| `"close"` | `palette.closeTone` |
| `"accent"` | `palette.accent` |
| anything else (`""`, `"Danger"`, `"green"`, `undefined`) | `palette.foreground` |

- The null-`palette` guard stays: with no palette, `foreground` is `Cm.Color.foreground` whatever
  the tone, and no read of `palette.*` happens (RR does not change the teardown rule documented
  at `ActionButton.qml` lines 13-16).
- Tone names are exact and case-sensitive.
- Changing `tone` on a live button, or changing the owner Theme's `dark`, updates `foreground`
  without recreating the button.
- With no `theme` given, the button's private fallback `Theme` supplies the tokens, so
  `tone: "close"` standalone is the dark `closeTone` under the test stub's `#ddd` foreground.
- The header comment's "urgent-coloured when it is destructive" grows to name the other tones in
  one line.
- `bordered`, `fontFamily`, `fontSize`, `verticalPadding`, `opacity` and `clicked` are unchanged.
- The one existing tone caller, `ui/components/RunIndicator.qml:69` (`tone: "danger"`), is
  untouched and keeps its colour.

## Error paths

- An unknown tone never throws and never paints `undefined`; it falls back to the foreground.
- `dark` reads only `foreground`'s channels, which a `color` property always has, so the
  derivation cannot throw whatever colour the bar supplies.
- Tearing a view down nulls `theme` and the fallback while bindings run once more; the guard keeps
  `foreground` a valid colour and the run prints no `TypeError` (checked by `tests/run.sh`).

## Tests

All tests are QML `TestCase`s run by `qmltestrunner` through `bash tests/run.sh`. They are
**component tier** (one QML component instantiated alone against the shell stubs): the behaviour
is property values on a single object, which a component test reads directly and no store,
backend or flow is involved. No Python test applies: nothing under `core/backend` changes.

### `tests/ui/components/tst_theme.qml` (TestCase `Theme`)

1. `test_a_light_foreground_makes_the_theme_dark`: default Theme (stub foreground `#ddd`) has
   `dark === true`.
2. `test_a_dark_foreground_makes_the_theme_light`: `foreground: "#202020"` gives `dark === false`.
3. `test_the_dark_tokens_carry_the_designs_dark_values`: with `dark: true`, the six tokens equal
   `#aab8ff`, `#8196ee`, `#5d70b8`, `#ff9442`, `#f2b84b`, `#7fb069` (compare with `Qt.color(...)`).
4. `test_the_light_tokens_carry_the_designs_light_values`: with `dark: false`, they equal
   `#2b3f9e`, `#4a67d6`, `#7f93d9`, `#c4560a`, `#a86b00`, `#2f7d32`.
5. `test_an_explicit_dark_wins_over_the_foreground`: `foreground: "#ffffff"; dark: false` gives
   the light `levelMilestone`; `foreground: "#000000"; dark: true` gives the dark one.
6. `test_the_tokens_follow_a_change_of_dark`: create with `dark: true`, set `dark = false`,
   `closeTone` becomes `#c4560a`.
7. `test_the_tokens_follow_the_foreground_across_the_line`: create default (dark), set
   `foreground = "#101010"`, `levelStory` becomes `#4a67d6` (the derived binding is live).
8. `test_amber_is_not_a_level_colour`: in both modes, none of the three level tokens equals `warn`
   or `closeTone` (RR line 58).
9. The four existing tests stay and pass unmodified.

### `tests/ui/components/tst_action_button.qml` (TestCase `ActionButton`)

Builds its own Themes with explicit `dark` so expected colours do not depend on the stub
foreground.

10. `test_the_warn_tone_uses_the_warn_colour`: `tone: "warn"` on the dark test Theme gives
    `#f2b84b`.
11. `test_the_close_tone_uses_the_close_colour`: `tone: "close"` gives `#ff9442`.
12. `test_the_accent_tone_uses_the_accent_colour`: `tone: "accent"` gives `#7fb069`.
13. `test_the_tones_take_the_light_values_on_a_light_theme`: with a `dark: false` Theme, `warn`,
    `close`, `accent` give `#a86b00`, `#c4560a`, `#2f7d32`.
14. `test_an_unknown_tone_uses_the_foreground`: `""`, `"Danger"`, `"Close"` and `"green"` each give
    the Theme's foreground.
15. `test_changing_the_tone_repaints_the_button`: a `"normal"` button set to `tone = "close"`
    gives the close colour; set back to `"normal"`, the foreground.
16. `test_a_button_without_a_theme_uses_its_own`: `tone: "close"` with no `theme` gives the dark
    `closeTone` (the fallback Theme under stub `#ddd`).
17. The existing four tests (style, danger, disabled dims, clicks) stay and pass unmodified.

Verification: `bash tests/run.sh tst_theme`, `bash tests/run.sh tst_action_button`, then the full
`bash tests/run.sh` green.

## Out of scope

- The 14% tint fill on buttons (RR line 66): the shell `Button` has a `background` property but
  the test stub `tests/stubs/qs/Ui/Button.qml` does not, and which buttons get it is a row/dialog
  decision. Story F (`RunControls`, row buttons) and story D (`CloseRunDialog`) set it, reading
  the tokens this card adds.
- `RunLevelBadge`, `RunStateBadge`, `CloseRunDialog` and their tints/borders: story D
  (`7997c2cf`).
- Choosing tones for each button in `RunControls`, the row's reason-line colour, `Panel.qml`
  wiring of `dark`: story F (`8e2ec6be`).
- `runLevel`, `controls().close`, `visibleActions`, `controlError` reset sentences: story B
  (`042b0d8e`).
- `run-control.py reset`: story A (`cc7f1fd6`). Store `reset` handling: story C (`19aa24c1`).
- Reading a dark/light flag from the Omarchy shell or `colors.toml`: not available today; the
  luminance rule stands in until the shell offers one.
- Changing `Cm.Color` or its test stub; changing any existing Theme default.

## Plan handoff notes

- One task is enough for each file pair, and the two may be one task: the Theme tokens must exist
  before the ActionButton tests can pass, so if split, Theme comes first.
- `compare()` on colours: compare against `Qt.color("#rrggbb")`, as the existing tests do.
- Luminance in QML: `theme.foreground.r` etc. are 0-1 reals on a `color` property.

---

# Theme tokens and ActionButton tones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `Theme` a derived `dark` flag and six light/dark colour tokens, and teach `ActionButton` the `warn`, `close` and `accent` tones that read them.

**Architecture:** `Theme.qml` gains `property bool dark` bound to the luminance of `foreground`, and six `property color` tokens each bound to `theme.dark ? <dark hex> : <light hex>`. `ActionButton.qml` extends its guarded `foreground` ternary chain with three more exact-match tone names that read those tokens off `palette`; every other tone falls back to `palette.foreground`.

**Tech Stack:** QML (Qt 6), QtTest `TestCase` run by `qmltestrunner` through `bash tests/run.sh`, against the shell stubs in `tests/stubs/qs`.

**Spec:** `docs/superpowers/specs/add-tokens-and-tones-07140ee4.md` (reproduced above this line).

## Global Constraints

- Touch only `ui/theme/Theme.qml`, `ui/components/ActionButton.qml`, `tests/ui/components/tst_theme.qml`, `tests/ui/components/tst_action_button.qml`.
- Token hexes (light / dark): `levelMilestone` `#2b3f9e` / `#aab8ff`; `levelStory` `#4a67d6` / `#8196ee`; `levelSubtask` `#7f93d9` / `#5d70b8`; `closeTone` `#c4560a` / `#ff9442`; `warn` `#a86b00` / `#f2b84b`; `accent` `#2f7d32` / `#7fb069`.
- `dark` is `0.2126·r + 0.7152·g + 0.0722·b` of `foreground` (0-1 channels) **strictly greater than** `0.5`.
- `accent` is the fixed green above, not `Cm.Color.accent`; no new `Cm.Color` field is read; `tests/stubs/qs/Commons/Color.qml` is unchanged.
- Existing `Theme` properties keep their names, types and defaults; `ActionButton`'s `tone` stays `string`, default `"normal"`; `bordered`, `fontFamily`, `fontSize`, `verticalPadding`, `opacity`, `clicked` unchanged.
- Tone names are exact and case-sensitive: `"normal"`, `"danger"`, `"warn"`, `"close"`, `"accent"`; anything else paints `palette.foreground`.
- The null-`palette` guard stays first: no palette → `Cm.Color.foreground`, no `palette.*` read.
- `ui/components/**` import no `core/stores`.
- `bash tests/run.sh` green before and after: no `FAIL` line, no `TypeError`, `ReferenceError`, `Unable to assign`, `non-existent`, `is not a function` in QML output.
- The existing four `tst_theme` tests and four `tst_action_button` tests stay unmodified and pass.
- Comments: one or two lines of `//` prose, matching the file's style.

## Review Focus

1. **A mid-grey foreground right at the line** (`#7f7f7f` vs `#808080`): a person expects a deterministic answer, light just below one half and dark just above; pinned by `test_the_line_sits_at_half_luminance` in Task 1.
2. **A transparent or fully-black bar foreground** (`"transparent"` is `#00000000`): `dark` must still compute (no throw) and give light tokens; pinned by `test_a_transparent_foreground_makes_the_theme_light` in Task 1.
3. **A caller that assigns a token directly, then the theme flips**: the assigned colour stays, the other tokens still follow `dark`; pinned by `test_an_assigned_token_stays_put_when_dark_changes` in Task 1.
4. **The owner Theme flips `dark` while a toned button is live**: the button repaints without being recreated; pinned by `test_flipping_the_themes_dark_repaints_the_button` in Task 2.
5. **A view drops its `theme` (set to `null`) while a toned button lives on**: the button falls back to its private Theme's token rather than painting `undefined` or throwing; pinned by `test_dropping_the_theme_falls_back_to_the_buttons_own` in Task 2.

---

### Task 1: `Theme` gains `dark` and the six colour tokens

**Files:**
- Modify: `ui/theme/Theme.qml:20-21` (append after `headingSize`, before the closing `}`)
- Test: `tests/ui/components/tst_theme.qml:31-35` (append after `test_it_carries_the_small_body_size_too`, before the closing `}`)

**Interfaces:**
- Consumes: nothing new (`Cm.Color.foreground` as today).
- Produces, on every `T.Theme` instance:
  - `property bool dark` — `true` when `foreground`'s luminance > 0.5; assignable.
  - `property color levelMilestone`, `levelStory`, `levelSubtask`, `closeTone`, `warn`, `accent` — each bound to `theme.dark`; assignable.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_theme.qml`, the file currently ends:

```qml
  function test_it_carries_the_small_body_size_too() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.smallSize, Style.font.bodySmall)
  }
}
```

Replace that ending with (the existing function kept as is, new functions added before the final `}`):

```qml
  function test_it_carries_the_small_body_size_too() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.smallSize, Style.font.bodySmall)
  }

  function tokensOf(theme) {
    return [theme.levelMilestone, theme.levelStory, theme.levelSubtask,
            theme.closeTone, theme.warn, theme.accent]
  }

  function compareTokens(theme, hexes) {
    var tokens = tokensOf(theme)
    for (var i = 0; i < hexes.length; ++i)
      compare(tokens[i], Qt.color(hexes[i]), "token " + i)
  }

  function test_a_light_foreground_makes_the_theme_dark() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.dark, true)
  }

  function test_a_dark_foreground_makes_the_theme_light() {
    var theme = createTemporaryObject(themeC, tc, { foreground: "#202020" })
    compare(theme.dark, false)
  }

  function test_the_line_sits_at_half_luminance() {
    compare(createTemporaryObject(themeC, tc, { foreground: "#7f7f7f" }).dark, false)
    compare(createTemporaryObject(themeC, tc, { foreground: "#808080" }).dark, true)
  }

  function test_a_transparent_foreground_makes_the_theme_light() {
    var theme = createTemporaryObject(themeC, tc, { foreground: "transparent" })
    compare(theme.dark, false)
    compare(theme.closeTone, Qt.color("#c4560a"))
  }

  function test_the_dark_tokens_carry_the_designs_dark_values() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    compareTokens(theme, ["#aab8ff", "#8196ee", "#5d70b8", "#ff9442", "#f2b84b", "#7fb069"])
  }

  function test_the_light_tokens_carry_the_designs_light_values() {
    var theme = createTemporaryObject(themeC, tc, { dark: false })
    compareTokens(theme, ["#2b3f9e", "#4a67d6", "#7f93d9", "#c4560a", "#a86b00", "#2f7d32"])
  }

  function test_an_explicit_dark_wins_over_the_foreground() {
    var light = createTemporaryObject(themeC, tc, { foreground: "#ffffff", dark: false })
    compare(light.levelMilestone, Qt.color("#2b3f9e"))
    var dark = createTemporaryObject(themeC, tc, { foreground: "#000000", dark: true })
    compare(dark.levelMilestone, Qt.color("#aab8ff"))
  }

  function test_the_tokens_follow_a_change_of_dark() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    compare(theme.closeTone, Qt.color("#ff9442"))
    theme.dark = false
    compare(theme.closeTone, Qt.color("#c4560a"))
  }

  function test_the_tokens_follow_the_foreground_across_the_line() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.levelStory, Qt.color("#8196ee"))
    theme.foreground = "#101010"
    compare(theme.dark, false)
    compare(theme.levelStory, Qt.color("#4a67d6"))
  }

  function test_an_assigned_token_stays_put_when_dark_changes() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    theme.closeTone = "#123456"
    theme.dark = false
    compare(theme.closeTone, Qt.color("#123456"))
    compare(theme.levelStory, Qt.color("#4a67d6"))
  }

  function test_amber_is_not_a_level_colour() {
    var modes = [true, false]
    for (var m = 0; m < modes.length; ++m) {
      var theme = createTemporaryObject(themeC, tc, { dark: modes[m] })
      var levels = [theme.levelMilestone, theme.levelStory, theme.levelSubtask]
      for (var i = 0; i < levels.length; ++i) {
        verify(!Qt.colorEqual(levels[i], theme.warn), "level " + i + " is warn, dark " + modes[m])
        verify(!Qt.colorEqual(levels[i], theme.closeTone), "level " + i + " is closeTone, dark " + modes[m])
      }
    }
  }
}
```

Notes for the engineer: `createTemporaryObject(component, parent, props)` sets `props` at creation, so `{ dark: true }` replaces the derived binding. Colours are compared against `Qt.color("#rrggbb")`, as the existing tests do. The test stub's `Cm.Color.foreground` is `#ddd`, so a default Theme is dark.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_theme`
(It runs the whole pytest suite first, which takes a couple of minutes, then the filtered QML test.)
Expected: 11 `FAIL!` lines under `== tests/ui/components/tst_theme.qml`, e.g. `test_a_light_foreground_makes_the_theme_dark() Compared values are not the same` and `test_an_assigned_token_stays_put_when_dark_changes() Uncaught exception: Cannot assign to non-existent property "closeTone"`; `Totals: 6 passed, 11 failed`. The four original tests still pass.

- [ ] **Step 3: Write the implementation**

In `ui/theme/Theme.qml`, the file currently ends:

```qml
  property real captionSize: Style.font.caption
  property real headingSize: Style.font.heading
}
```

Replace that ending with:

```qml
  property real captionSize: Style.font.caption
  property real headingSize: Style.font.heading

  // Dark means a dark background, read off a light foreground (luminance above
  // one half). The hexes come from the Runs row design, dark value first.
  property bool dark: 0.2126 * theme.foreground.r + 0.7152 * theme.foreground.g
    + 0.0722 * theme.foreground.b > 0.5
  property color levelMilestone: theme.dark ? "#aab8ff" : "#2b3f9e"
  property color levelStory: theme.dark ? "#8196ee" : "#4a67d6"
  property color levelSubtask: theme.dark ? "#5d70b8" : "#7f93d9"
  property color closeTone: theme.dark ? "#ff9442" : "#c4560a"
  property color warn: theme.dark ? "#f2b84b" : "#a86b00"
  property color accent: theme.dark ? "#7fb069" : "#2f7d32"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_theme`
Expected: pytest passes; under `== tests/ui/components/tst_theme.qml`, no `FAIL` line and `Totals: 17 passed, 0 failed`; exit status 0 (`echo $?` prints `0`).

- [ ] **Step 5: Commit**

```bash
git add ui/theme/Theme.qml tests/ui/components/tst_theme.qml
git commit -m "feat(theme): derive dark from the foreground and add the Runs row colour tokens"
```

---

### Task 2: `ActionButton` learns the `warn`, `close` and `accent` tones

**Files:**
- Modify: `ui/components/ActionButton.qml:7-9` (header comment), `ui/components/ActionButton.qml:23-24` (`foreground` binding)
- Test: `tests/ui/components/tst_action_button.qml:14-18` (new Themes and Components), end of file (new tests)

**Interfaces:**
- Consumes (from Task 1, on `T.Theme`): `property bool dark`, `property color warn`, `property color closeTone`, `property color accent`; existing `foreground`, `urgent`.
- Produces: `ActionButton.tone` accepts `"warn"` → `palette.warn`, `"close"` → `palette.closeTone`, `"accent"` → `palette.accent`, alongside `"normal"` and `"danger"`; any other string → `palette.foreground`.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_action_button.qml`, replace these lines:

```qml
  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }

  Component { id: normalC; UI.ActionButton { theme: tcTheme; text: "Save" } }
  Component { id: dangerC; UI.ActionButton { theme: tcTheme; text: "Delete"; tone: "danger" } }
  SignalSpy { id: clicks; signalName: "clicked" }
```

with:

```qml
  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }
  T.Theme { id: darkTheme; foreground: "#eeeeee"; dark: true }
  T.Theme { id: lightTheme; foreground: "#111111"; dark: false }

  Component { id: normalC; UI.ActionButton { theme: tcTheme; text: "Save" } }
  Component { id: dangerC; UI.ActionButton { theme: tcTheme; text: "Delete"; tone: "danger" } }
  Component { id: themeC; T.Theme {} }
  Component { id: toneC; UI.ActionButton { theme: darkTheme; text: "Go" } }
  Component { id: bareC; UI.ActionButton { text: "Close"; tone: "close" } }
  SignalSpy { id: clicks; signalName: "clicked" }
```

Then the file currently ends:

```qml
  function test_it_reports_clicks() {
    var button = make(normalC)
    mouseClick(button, button.width / 2, button.height / 2)
    compare(clicks.count, 1)
  }
}
```

Replace that ending with:

```qml
  function test_it_reports_clicks() {
    var button = make(normalC)
    mouseClick(button, button.width / 2, button.height / 2)
    compare(clicks.count, 1)
  }

  function test_the_warn_tone_uses_the_warn_colour() {
    var button = createTemporaryObject(toneC, tc, { tone: "warn" })
    compare(button.foreground, Qt.color("#f2b84b"))
  }

  function test_the_close_tone_uses_the_close_colour() {
    var button = createTemporaryObject(toneC, tc, { tone: "close" })
    compare(button.foreground, Qt.color("#ff9442"))
  }

  function test_the_accent_tone_uses_the_accent_colour() {
    var button = createTemporaryObject(toneC, tc, { tone: "accent" })
    compare(button.foreground, Qt.color("#7fb069"))
  }

  function test_the_tones_take_the_light_values_on_a_light_theme() {
    var expected = { "warn": "#a86b00", "close": "#c4560a", "accent": "#2f7d32" }
    for (var tone in expected) {
      var button = createTemporaryObject(toneC, tc, { theme: lightTheme, tone: tone })
      compare(button.foreground, Qt.color(expected[tone]), tone)
    }
  }

  function test_an_unknown_tone_uses_the_foreground() {
    var tones = ["", "Danger", "Close", "green"]
    for (var i = 0; i < tones.length; ++i) {
      var button = createTemporaryObject(toneC, tc, { tone: tones[i] })
      compare(button.foreground, Qt.color("#eeeeee"), "tone '" + tones[i] + "'")
    }
  }

  function test_changing_the_tone_repaints_the_button() {
    var button = createTemporaryObject(toneC, tc)
    compare(button.foreground, Qt.color("#eeeeee"))
    button.tone = "close"
    compare(button.foreground, Qt.color("#ff9442"))
    button.tone = "normal"
    compare(button.foreground, Qt.color("#eeeeee"))
  }

  function test_flipping_the_themes_dark_repaints_the_button() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    var button = createTemporaryObject(toneC, tc, { theme: theme, tone: "accent" })
    compare(button.foreground, Qt.color("#7fb069"))
    theme.dark = false
    compare(button.foreground, Qt.color("#2f7d32"))
  }

  function test_a_button_without_a_theme_uses_its_own() {
    var button = createTemporaryObject(bareC, tc)
    compare(button.foreground, Qt.color("#ff9442"))
  }

  function test_dropping_the_theme_falls_back_to_the_buttons_own() {
    var button = createTemporaryObject(toneC, tc, { theme: lightTheme, tone: "close" })
    compare(button.foreground, Qt.color("#c4560a"))
    button.theme = null
    compare(button.foreground, Qt.color("#ff9442"))
  }
}
```

Notes for the engineer: `darkTheme` and `lightTheme` set `dark` explicitly so expected colours do not depend on the stub foreground. The no-theme cases (`bareC`, and `theme = null`) use the button's private fallback Theme, which under the stub's `#ddd` foreground is dark, hence `#ff9442`. Do not test `tone: undefined`: `tone` is a `string` property, and assigning `undefined` prints `Unable to assign`, which `tests/run.sh` treats as a failure.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_action_button`
Expected, if Task 1 is already implemented: under `== tests/ui/components/tst_action_button.qml`, `FAIL!` lines for `test_the_warn_tone_uses_the_warn_colour`, `test_the_close_tone_uses_the_close_colour`, `test_the_accent_tone_uses_the_accent_colour`, `test_the_tones_take_the_light_values_on_a_light_theme`, `test_changing_the_tone_repaints_the_button`, `test_flipping_the_themes_dark_repaints_the_button`, `test_a_button_without_a_theme_uses_its_own`, `test_dropping_the_theme_falls_back_to_the_buttons_own` (each `Compared values are not the same`: the button paints the foreground). `test_an_unknown_tone_uses_the_foreground` and the four original tests pass already. (Without Task 1 the whole file fails to compile instead: `FAIL! ... tst_action_button::compile() Cannot assign to non-existent property "dark"`, `Totals: 0 passed, 1 failed`. Do Task 1 first.)

- [ ] **Step 3: Write the implementation**

In `ui/components/ActionButton.qml`, replace the header comment:

```qml
// The shell's Button with the style every action in the panel repeats: a
// bordered small button in the theme's font, urgent-coloured when it is
// destructive, dimmed while disabled.
```

with:

```qml
// The shell's Button with the style every action in the panel repeats: a
// bordered small button in the theme's font, coloured by its tone (danger,
// warn, close or accent; anything else is the foreground), dimmed while disabled.
```

Then replace the `foreground` binding:

```qml
  foreground: !button.palette ? Cm.Color.foreground
    : button.tone === "danger" ? button.palette.urgent : button.palette.foreground
```

with:

```qml
  foreground: !button.palette ? Cm.Color.foreground
    : button.tone === "danger" ? button.palette.urgent
    : button.tone === "warn" ? button.palette.warn
    : button.tone === "close" ? button.palette.closeTone
    : button.tone === "accent" ? button.palette.accent
    : button.palette.foreground
```

Leave the guard comment above `property var theme`, the `tone` declaration, `palette`, and every other line as they are.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_action_button`
Expected: no `FAIL` line, `Totals: 15 passed, 0 failed`, no `TypeError`/`Unable to assign` lines, exit status 0.

- [ ] **Step 5: Run the full suite**

Run: `timeout 900 bash tests/run.sh; echo "exit $?"`
Expected: pytest passes (including `tests/architecture/test_layers.py`); every `== tests/...` QML file shows `Totals: N passed, 0 failed`, including `tests/ui/components/tst_run_indicator.qml` (its `tone: "danger"` button is unchanged); no `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` lines; final line `exit 0`.

- [ ] **Step 6: Commit**

```bash
git add ui/components/ActionButton.qml tests/ui/components/tst_action_button.qml
git commit -m "feat(components): ActionButton warn, close and accent tones read the theme tokens"
```
<!-- task-pipeline: validated -->
