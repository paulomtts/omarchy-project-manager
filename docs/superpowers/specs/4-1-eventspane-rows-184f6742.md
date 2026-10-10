# 4.1 EventsPane: rows, states and filter chips (card 184f6742) — design

Narrows `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (S5, "the parent
spec") to one presentation component. Parent story 55a2dc57 "Events UI". The store side
(`RunStore` events state, `core/domain/runEvents.js`) is built and read-only here.

## Scope

In scope:

- New `ui/components/EventsPane.qml`: presentation only. Renders the selected run's event
  rows from props, the All / Phases / Failures filter chips, the "… N earlier events" line,
  the loading, empty and error states, its own bounded and scrollable list with the wheel
  hand-off to the page, and emits `attemptRequested` for a row that names an attempt.
- New `tests/ui/components/tst_events_pane.qml`, written first (TDD). One file, one test
  (or a small group) per state.

Out of scope (sibling cards own it):

- 4.2: following the newest row while scrolled to the bottom, the `Jump ↓` button, keeping
  the follow state across a filter change. 4.1 places the newest row at the bottom (the
  rows' order) but does not auto-scroll on append and adds no Jump control.
- 4.3: wiring into `ui/screens/RunDetailScreen.qml`, the Output / Events tabs and the
  Events tab count, the `e` key in `ui/Shortcuts.qml`, binding the pane to `app.runs`,
  handling `attemptRequested` (select the attempt, load its output, switch tabs), and
  clearing the events on leaving Run detail.
- 4.4: `docs/architecture.md` and README. 4.1 changes no docs.
- Any change to `RunStore.qml`, `core/domain/runEvents.js`, `core/domain/runs.js`,
  `ui/components/runGlyphs.js`, `ChipRow`, `Chip`, `ListRow`, `ListStatus`, `ThemedText`,
  `ActionButton`, the backend helper.
- A "Load earlier" control or `--before-seq` paging: the store as built has no backward
  paging (it keeps `eventsDropped`, a count). The parent spec's `eventsHasEarlier` /
  `eventsOldestSeq` (parent spec lines 82-84, 96-97) were not built; the pane only shows the
  count.

## Inherited constraints

- Layering: a component receives props and never imports `core/stores`
  (parent spec lines 69-70; `docs/architecture.md`; enforced by
  `tests/architecture/test_layers.py::violations_screen`). A component may import
  `core/domain/*.js` (`test_layers.py` line 198 accepts `import "../../core/domain/…js"`
  from `ui/components/`).
- Glyph source: the row's `glyph` is a `runGlyphs.js` state key; "The UI resolves the
  character, so `core/domain` imports nothing from `ui/`" (parent spec lines 115-117). The
  pane resolves it through `RunGlyphs.glyphOf(key)`.
- Failures (`failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`) use the
  `urgent` token with the `‼` glyph, never red/purple (parent spec lines 121-122). The set
  is the one `runEvents.js` uses (`_FAILURES`, `core/domain/runEvents.js:141`).
- A phase's `detail` (why it failed) is shown under the row (parent spec lines 118-119).
- "The page itself scrolls (the panel's flickable), so the list has its own bounded height
  and its own scrolling: a wheel over the list scrolls the list, and at its ends the page
  takes over. Newest at the bottom" (parent spec lines 141-143).
- "Clicking a row that names an attempt … a row without an attempt does nothing" (parent
  spec lines 145-146). The selecting and tab switching are 4.3's; 4.1 only emits.
- "Empty: \"No events yet.\" Error: `errorText` with the raw message one click away"
  (parent spec line 149). Errors table: `am events` exit 3 shows "events unreadable" with
  the message and the pane keeps its rows (parent spec line 157).
- Filter values are the strings `All`, `Phases`, `Failures`, exactly as
  `RunEvents.filterRows` reads them (`runEvents.js:141-160`) and as the store holds them
  (`RunStore.qml:136`, `eventsFilter`, default `All`).
- No duplicated components (`test_layers.py` GUARDS): no `CursorSurface {` outside
  `ListRow.qml`, no `font.family:` outside `ThemedText.qml`, no `bordered: true` outside
  `ActionButton.qml`. Rows are `ListRow`s, text is `ThemedText`, chips are `ChipRow`, the
  status line is `ListStatus`, the details toggle is an `ActionButton`.
- No private-use code points (`tests/architecture/test_icon_glyphs.py`): only the BMP
  glyphs in `runGlyphs.js` and the plain `…` (U+2026).
- Comments state the contract only, no narrative (card). File header is a `//` block above
  the root stating props and signals, as `PhaseTimeline.qml` and `ChipRow.qml` do.
- `bash tests/run.sh` green; it fails on any qmltestrunner output matching
  `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`.

## Interface

```
EventsPane (root: Item, objectName "eventsPane")
  property var theme: null          // owner's Theme; falls back to a local T.Theme
  property var rows: []             // RunEvents.eventRow rows, ascending seq, UNFILTERED (the store's `events`)
  property string filter: "All"     // All | Phases | Failures (the store's `eventsFilter`)
  property int dropped: 0           // events of the run not held (the store's `eventsDropped`)
  property string status: "idle"    // idle | loading | ok | error (the store's `eventsStatus`)
  property string errorText: "Events unreadable."   // the error headline
  property string errorMessage: ""  // the raw message (the store's `eventsError`)
  property real maxListHeight: Style.space(320)     // the list's height cap
  readonly property var shownRows   // RunEvents.filterRows(rows, filter)

  signal filterRequested(string filter)
  signal attemptRequested(string card, string phase, int attempt)
```

The pane applies the filter itself (`shownRows`), so the owner binds the store's held rows
and filter straight through and the empty / filtered-empty distinction is the pane's. It
never assigns `filter`; a chip click only emits `filterRequested`.

objectNames the tests find by (via `tests/helpers/find.js`):

| objectName | what |
|---|---|
| `eventsPane` | root |
| `eventsFilterChipAll`, `eventsFilterChipPhases`, `eventsFilterChipFailures` | the chips (`ChipRow` `chipPrefix: "eventsFilterChip"`, ids = the filter strings) |
| `eventsEarlier` | the "… N earlier events" line |
| `eventsStatus` | the `ListStatus` line (loading / empty / filtered empty) |
| `eventsError` | the error block (headline + toggle + message) |
| `eventsErrorText` | the headline |
| `eventsErrorToggle` | the details `ActionButton` |
| `eventsErrorMessage` | the raw message |
| `eventsList` | the list (`ListView`) |
| `eventsRow<seq>` | a row delegate (`ListRow`) |
| `eventsRowTime`, `eventsRowGlyph`, `eventsRowLabel`, `eventsRowStatus`, `eventsRowDuration`, `eventsRowDetail` | the parts inside a row |

## Observable behaviour

### Layout (top to bottom)

1. The filter chips, All / Phases / Failures, in that order.
2. The error block, only in the error state.
3. The "… N earlier events" line, only when `dropped > 0`.
4. The status line, only when it has text.
5. The list, only when `shownRows` is non-empty.

The pane's `implicitHeight` is the sum of the visible parts; its `implicitWidth` follows
the owner's width (the owner sets `width`).

### Rows

- One row per entry of `shownRows`, in that order (ascending seq: oldest first, newest at
  the bottom).
- A row reads, left to right: `time` (dim), the glyph, `label`, `status`, `duration` (dim).
  An empty part is drawn empty (no placeholder text). Text is plain (`Text.PlainText`), so a
  label containing `<b>` shows literally.
- Glyph: for a failure row `‼` (`RunGlyphs.glyphOf("escalated")`); otherwise
  `RunGlyphs.glyphOf(row.glyph)`, which is `""` for an unknown or empty key.
- Failure row: `row.status` is a string in {`failed`, `escalated`, `gate_failed`,
  `schema_invalid`, `harness_error`}, at any level. Its glyph, label and status are drawn in
  `palette.urgent`; a non-failure row draws none of its parts in `urgent`.
- Detail: when `row.detail` is a non-empty string, a second line under the row shows it
  (wrapping, in `urgent` on a failure row, else dim). No detail, no second line (the
  `eventsRowDetail` item is not visible).
- A row with `card !== ""`, `phase !== ""` and `attempt > 0` (a number) names an attempt:
  a click on it emits `attemptRequested(card, phase, attempt)` once, and its hover cursor is
  the pointing hand. Any other row: a click emits nothing and the cursor is the arrow.
- Rows are not keyboard-navigable (`ListRow.index` stays -1): no cursor highlight.

### Filter chips

- Three chips, labels `All`, `Phases`, `Failures`, no counts.
- The chip whose id equals `filter` is active; with a `filter` outside the three, none is
  active and the rows shown are all of them (what `filterRows` does).
- Clicking a chip emits `filterRequested(<its id>)`, including the already active one. The
  pane does not change `filter` itself, so the rows shown change only when the owner sets
  `filter`.

### Earlier events

- `dropped > 0`: a dim line `… N earlier events` (`… 1 earlier event` for one) above the
  list. `dropped <= 0`: not visible. It does not depend on the filter.

### Status line (`ListStatus`)

Precedence is `ListStatus`'s own (loading, then error, then empty); the pane passes
`error: ""` because the error has its own block.

- `loading`: `status === "loading"` and `shownRows` is empty → "Loading events…". While
  loading with rows held, the rows stay and no loading line shows.
- empty: `rows` holds no row and the state is not loading or error → "No events yet."
- filtered empty: `rows` holds rows but `shownRows` is empty → "No events match the filter."
- otherwise not visible.

### Error state

- `status === "error"`: the error block is visible; its headline is `errorText` in
  `urgent`. The rows held stay visible under it (parent spec line 157).
- When `errorMessage` is non-empty, an `ActionButton` "Details" sits beside the headline.
  The raw message is hidden until it is clicked; then the message (plain text, wrapping) is
  shown and the button reads "Hide"; a second click hides it again. With `errorMessage`
  empty the button is not visible.
- Leaving the error state (any other `status`) hides the block and collapses the message,
  so the next error starts collapsed.
- `status === "error"` with no rows: the error block shows, and the empty line does not.

### The list: bounded height, own scrolling, wheel hand-off

- The list is a `ListView` with `clip: true`, vertical only, `boundsBehavior:
  Flickable.StopAtBounds`. Its height is `min(contentHeight, maxListHeight)`: a short list
  is exactly as tall as its rows; a long one is capped and scrolls inside itself.
- A vertical wheel over the list:
  - moves the list when the list can still move that way (not at its top for a wheel up,
    not at its bottom for a wheel down), and the page (an enclosing Flickable) does not
    move;
  - when the list is already at that end, or its content fits (nothing to scroll), the
    event reaches the enclosing Flickable, which scrolls instead.
- The mechanism (a `WheelHandler` that accepts only when the list can move, or Qt 6.11's
  own `Flickable` wheel propagation at the bounds) is the plan's choice, settled
  empirically by the tests below; `GraphView.qml:165-218` and `docs/architecture.md:318-338`
  record that a `WheelHandler` that fires blocks the items behind it and a non-accepted
  wheel propagates. A touchpad (pixel delta) wheel follows the same rule as a mouse notch.

### Error paths (no warning, no throw)

All of these render without any of the qmltestrunner messages `tests/run.sh` rejects:

- `rows` is `null`, `undefined`, a string, a number or a plain object → no rows (treated as
  empty; `filterRows` returns `[]`), "No events yet.".
- Entries that are not objects are skipped (`filterRows` does it).
- A row missing `time`, `label`, `status`, `duration`, `detail`, `card`, `phase` or
  `attempt`, or carrying a non-string in one of them → that part is drawn empty; no
  attempt (attempt not a positive number) → not clickable.
- `glyph` an unknown key or an inherited name (`"constructor"`) → no glyph (non-failure).
- `dropped` negative → no earlier line.
- `theme` null → the local `T.Theme` fallback.
- Destroying the pane while bound (the test's temporary objects) → no `TypeError`.

## Tests

All in `tests/ui/components/tst_events_pane.qml` — tier: QML UI component test, because
the deliverable is a QML presentation component whose contract is what it draws and emits
from props; it has no domain logic of its own to unit-test in JS and no store or backend
to integrate (those tiers are owned by 3.x and 4.3). Pattern of
`tests/ui/components/tst_phase_timeline.qml` / `tst_chip_row.qml`: `TestCase { when:
windowShown; visible: true }`, `Component { id: paneC; UI.EventsPane {} }`,
`createTemporaryObject`, `H.find(item, objectName)`, `SignalSpy`, a test `T.Theme` with
distinct `foreground` / `dim` / `urgent`, and `RunGlyphs` imported from
`../../../ui/components/runGlyphs.js` so expected glyphs are not literals.

1. `test_rows_render_time_glyph_label_status_duration` — an attempt row and a phase row:
   each part's text; glyph is `RunGlyphs.glyphOf(row.glyph)`; rows appear in input order.
2. `test_a_failed_phase_shows_its_detail_under_the_row` — detail visible with the text; a
   row without detail has no visible detail line.
3. `test_failure_rows_use_urgent_and_the_double_bang` — one row per failure status
   (`failed`, `escalated`, `gate_failed`, `schema_invalid`, `harness_error`): glyph `‼`,
   glyph / label / status colour `urgent`; a `done` row: glyph `✔`, no part in `urgent`.
4. `test_unknown_glyph_key_shows_no_glyph`.
5. `test_filter_chips_mark_the_active_filter` — for each of the three values; an unknown
   filter marks none and shows every row.
6. `test_a_chip_click_requests_its_filter_without_changing_it` — `filterRequested` with
   the id, `filter` unchanged, rows unchanged.
7. `test_the_pane_applies_the_filter` — Phases shows only phase/attempt rows, Failures
   only failure rows.
8. `test_earlier_line_shows_the_dropped_count` — `dropped` 0 / -1 hidden, 1 singular,
   37 plural, independent of the filter.
9. `test_empty_state_says_no_events_yet` — `rows: []`, and the garbage `rows` values from
   Error paths.
10. `test_a_filter_that_empties_the_list_says_so` — filtered-empty wording, not "No events
    yet.".
11. `test_loading_without_rows_shows_loading_and_with_rows_keeps_them`.
12. `test_error_state_shows_the_headline_and_keeps_the_rows` — headline text and `urgent`,
    rows still shown; no error block outside the error state.
13. `test_the_raw_message_is_one_click_away` — hidden at first, Details shows it, Hide
    hides it; no toggle when `errorMessage` is empty; leaving and re-entering the error
    state starts collapsed.
14. `test_a_row_naming_an_attempt_emits_attemptRequested` — click → one emission with
    `(card, phase, attempt)`.
15. `test_a_row_without_an_attempt_emits_nothing` — attempt 0, empty card, empty phase:
    no emission each.
16. `test_the_list_height_is_bounded` — 3 rows: list height equals content height, below
    `maxListHeight`; 100 rows: list height equals `maxListHeight` and contentHeight is
    larger.
17. Wheel hand-off, with the pane inside a `stackC`-style enclosing Flickable built as in
    `tests/ui/tst_graph_wheel.qml:24-52` (vertical Flickable, `StopAtBounds`, Column,
    content taller than the Flickable) and `mouseWheel(stack, x, y, 0, ±120, Qt.NoButton,
    Qt.NoModifier)` over the list; assertions with `tryVerify` / `tryCompare` because a
    Flickable wheel may animate:
    - `test_a_wheel_in_the_middle_of_the_list_scrolls_only_the_list`;
    - `test_a_wheel_down_at_the_list_bottom_scrolls_the_page`;
    - `test_a_wheel_up_at_the_list_top_scrolls_the_page` (page first positioned below its
      top);
    - `test_a_wheel_over_a_list_that_fits_scrolls_the_page`.
18. `test_garbage_props_render_without_warnings` — the Error paths list, plus `theme`
    null; the run's warning filter is the assertion.

Architecture tier (existing, unchanged): `tests/architecture/test_layers.py` and
`test_icon_glyphs.py` must pass with the new file — they are the guard for layering,
duplicated primitives and glyphs, so no new architecture test is added.

## Acceptance

- `ui/components/EventsPane.qml` and `tests/ui/components/tst_events_pane.qml` exist; no
  other file changes (except this spec and its plan).
- `bash tests/run.sh` is green, with no rejected warnings in the new test's output.
