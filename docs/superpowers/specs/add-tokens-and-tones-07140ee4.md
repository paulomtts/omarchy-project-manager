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
