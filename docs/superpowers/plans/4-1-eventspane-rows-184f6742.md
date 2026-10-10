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

---

# 4.1 EventsPane: rows, states and filter chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ui/components/EventsPane.qml`, the presentation component that draws a run's event rows, the All / Phases / Failures chips, the earlier-events count, the loading / empty / filtered-empty / error states and a bounded list that scrolls itself. Its test file, `tests/ui/components/tst_events_pane.qml`, is written first.

**Architecture:** One QML `Item` with a `Column`: a `ChipRow`, an error block, a `ThemedText` "earlier" line, a `ListStatus`, then a `ListView` of `ListRow` delegates. The pane filters its own rows (`RunEvents.filterRows`), resolves glyphs through `runGlyphs.js` and emits two signals. It never imports `core/stores`. The wheel hand-off between the list and the page needs no code. In Qt 6.11.2, a `ListView` with `boundsBehavior: Flickable.StopAtBounds` passes a wheel event on to the enclosing `Flickable` when it is at that end or its content fits. A plain `ListView` checked in a scratch run confirmed this, and Task 6's tests pin it.

**Tech Stack:** Qt 6.11.2 QML (QtQuick, QtTest via `/usr/lib/qt6/bin/qmltestrunner`), the repo's `qs.Commons` / `qs.Ui` stubs under `tests/stubs`, pytest for the architecture tests.

**Spec:** `docs/superpowers/specs/4-1-eventspane-rows-184f6742.md` (reproduced above).

## Global Constraints

- Only two files are created: `ui/components/EventsPane.qml` and `tests/ui/components/tst_events_pane.qml`. No other file changes (spec, Acceptance).
- Do not change `RunStore.qml`, `core/domain/runEvents.js`, `core/domain/runs.js`, `ui/components/runGlyphs.js`, `ChipRow`, `Chip`, `ListRow`, `ListStatus`, `ThemedText`, `ActionButton` or the backend helper. No docs change (4.4 owns docs).
- A component never imports `core/stores`. It may import `core/domain/*.js` (`import "../../core/domain/runEvents.js" as RunEvents`).
- Glyphs come from `RunGlyphs.glyphOf(key)`. A failure row uses `‼` (`RunGlyphs.glyphOf("escalated")`) and the `urgent` token, never red or purple.
- The failure statuses are exactly `failed`, `escalated`, `gate_failed`, `schema_invalid` and `harness_error`. Do not copy that set: ask `RunEvents.filterRows([row], "Failures")`.
- Filter values are the strings `All`, `Phases` and `Failures`. The default is `All`.
- Reuse the primitives: rows are `ListRow`, text is `ThemedText`, chips are `ChipRow`, the status line is `ListStatus` and the details toggle is `ActionButton`. Never write `CursorSurface {`, `font.family:` or `bordered: true` in the new file (`tests/architecture/test_layers.py` GUARDS).
- No private-use code points. Use only the BMP glyphs in `runGlyphs.js` and the plain `…` (U+2026).
- Comments state the contract only, with no narrative. The file header is a `//` block above the root that states the props and signals.
- `bash tests/run.sh` stays green. It fails on any qmltestrunner output matching `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`.
- Wording: `Loading events…`, `No events yet.`, `No events match the filter.`, `Events unreadable.`, `Details` / `Hide`, `… N earlier events` / `… 1 earlier event`.

## Review Focus

1. **A new `rows` array arrives while the user is scrolled to the middle of the list.** The store replaces `events` on every fetch, and replacing a `ListView`'s model puts it back at its top (seen in a scratch run). The user expects the list to stay where they were reading. → Task 7, `test_new_rows_keep_the_list_where_it_was`.
2. **A failure at a level other than attempt** (an escalated story, a failed run). It must still show `‼` in `urgent`, because the spec says "at any level". → Task 1, `test_failure_rows_use_urgent_and_the_double_bang` gives each failure status a different level.
3. **The error state while a filter hides every held row.** The error block shows and the line reads "No events match the filter.", not "No events yet." and not nothing. → Task 5, the `narrowed` case in `test_error_state_shows_the_headline_and_keeps_the_rows`.
4. **A row whose `attempt` is a numeric string (`"2"`) or negative.** It must not be clickable, and the cursor must stay the arrow. → Task 2, `test_a_row_without_an_attempt_emits_nothing` (row 4), and Task 1, `test_garbage_props_render_without_warnings` (seq 3, attempt -1).
5. **A touchpad wheel (pixel delta) over the list.** It follows the same hand-off as a mouse notch. QtTest cannot synthesize a pixel delta (`docs/architecture.md:318-338`), so no automated test can pin it. The plan writes no wheel code of its own: Qt's `Flickable` treats both deltas through the same bounds check. Check it by hand once 4.3 wires the pane into Run detail.

---

## File Structure

- Create `ui/components/EventsPane.qml`: the whole component (props, the derived `shownRows`, two signals, the column of chips / error / earlier / status / list). It is presentation only, with one responsibility.
- Create `tests/ui/components/tst_events_pane.qml`: one `TestCase` named `EventsPane`, with one test (or a small group) per state.

The repo's other QML test files follow the same pattern (`tst_phase_timeline.qml`, `tst_chip_row.qml`). `tests/run.sh` picks the new test up automatically, because it finds every `tst_*.qml` under `tests/`.

**Running the one test file** from the worktree root. This is the same runner and import path `tests/run.sh` uses, filtered to its failure, summary and rejected-warning lines:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"
```

The `Totals` count includes the two implicit `initTestCase` / `cleanupTestCase` passes.

**A testing gotcha the tests already handle:** `createTemporaryObject(component, parent, props)` sends `props` through a property map that turns a JS array into a list `Array.isArray` rejects, and `RunEvents.filterRows` then returns `[]`. The test helper `make()` therefore creates the pane first and assigns each prop afterwards. Keep it that way. An owner binds real arrays, so the component needs no workaround.

---

### Task 1: The pane draws its rows

**Files:**
- Create: `ui/components/EventsPane.qml`
- Create: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: `RunEvents.filterRows(rows, filter)` from `core/domain/runEvents.js` (returns the object entries matching filter; `[]` for a non-array). `RunGlyphs.glyphOf(key)` from `ui/components/runGlyphs.js` (`""` for an unknown key). `ListRow` (`index` stays -1, `hoverCursorShape`, `activated()`, `theme`, `palette`). `ThemedText` (`theme`, `variant`: `body` | `dim`).
- Produces: `EventsPane` with `property var theme`, `property var rows`, `readonly property var palette`, `readonly property var shownRows`, and the helpers `_field(row, key)`, `_isFailure(row)`, `_glyphOf(row)` and `_tint(failure, token)`. Children: `eventsList` (a `ListView`), delegates `eventsRow<seq>` containing `eventsRowTime`, `eventsRowGlyph`, `eventsRowLabel`, `eventsRowStatus`, `eventsRowDuration` and `eventsRowDetail`.

The file header comment describes the whole pane's contract, including the props that Tasks 3-6 add. Write it in full now, so the header is not rewritten five times.

In this task the list is as tall as its rows (`height: list.contentHeight`, `interactive: false`) and shows every row. Task 3 applies the filter, Task 6 bounds the height and Task 7 changes how the model is set.

- [ ] **Step 1: Write the failing test file**

Create `tests/ui/components/tst_events_pane.qml` with exactly this content:

```qml
// tests/ui/components/tst_events_pane.qml
// ui/components/EventsPane.qml: a run's event rows from props (time, glyph,
// label, status, duration, a phase's detail under it), the All / Phases /
// Failures chips, "… N earlier events", the loading / empty / filtered-empty
// line, the error block, a bounded list that scrolls itself and hands a wheel
// to the page at its ends, and attemptRequested for a row naming an attempt.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "EventsPane"
  when: windowShown
  visible: true
  width: 700; height: 600

  // Three distinct tokens, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: paneC; UI.EventsPane { width: 600 } }

  // A pane in testTheme unless props names a theme (null included). Props are
  // assigned after creation: createTemporaryObject's property map turns a JS
  // array into a list that Array.isArray rejects, and an owner binds real arrays.
  function make(props) {
    var p = props || {}
    if (!("theme" in p)) p.theme = testTheme
    var pane = createTemporaryObject(paneC, tc)
    for (var key in p) pane[key] = p[key]
    wait(30)
    return pane
  }

  // A complete row as RunEvents.eventRow returns it; `fields` overrides.
  function eventRow(seq, fields) {
    var row = { seq: seq, time: "12:00:00", level: "attempt", label: "row " + seq, status: "done",
                glyph: "done", duration: "", detail: "", card: "card-" + seq, phase: "implement",
                attempt: 1 }
    for (var key in fields) row[key] = fields[key]
    return row
  }

  function rowOf(pane, seq) { return H.find(pane, "eventsRow" + seq) }
  function part(pane, seq, name) { return H.find(rowOf(pane, seq), name) }
  function listOf(pane) { return H.find(pane, "eventsList") }

  // ---- rows ----------------------------------------------------------------

  function test_rows_render_time_glyph_label_status_duration() {
    var pane = make({ rows: [
      eventRow(4, { time: "12:01:05", level: "attempt", label: "Card A implement.2", status: "done",
                    glyph: "done", duration: "4.2s", card: "card-a", phase: "implement", attempt: 2 }),
      eventRow(7, { time: "12:01:09", level: "phase", label: "Card A verify", status: "started",
                    glyph: "running", duration: "", card: "card-a", phase: "verify", attempt: 0 })
    ] })
    compare(listOf(pane).count, 2)
    compare(part(pane, 4, "eventsRowTime").text, "12:01:05")
    compare(part(pane, 4, "eventsRowGlyph").text, RG.glyphOf("done"))
    compare(part(pane, 4, "eventsRowLabel").text, "Card A implement.2")
    compare(part(pane, 4, "eventsRowStatus").text, "done")
    compare(part(pane, 4, "eventsRowDuration").text, "4.2s")
    compare(part(pane, 7, "eventsRowTime").text, "12:01:09")
    compare(part(pane, 7, "eventsRowGlyph").text, RG.glyphOf("running"))
    compare(part(pane, 7, "eventsRowLabel").text, "Card A verify")
    compare(part(pane, 7, "eventsRowStatus").text, "started")
    compare(part(pane, 7, "eventsRowDuration").text, "", "an empty part is drawn empty")
    verify(rowOf(pane, 4).y < rowOf(pane, 7).y, "input order: the newest row at the bottom")
    compare(rowOf(pane, 4).index, -1, "rows are not keyboard-navigable")
    verify(Qt.colorEqual(part(pane, 4, "eventsRowTime").color, testTheme.dim), "the time is dim")
    verify(Qt.colorEqual(part(pane, 4, "eventsRowDuration").color, testTheme.dim), "the duration is dim")
  }

  function test_row_text_is_plain() {
    var pane = make({ rows: [eventRow(1, { label: "<b>x</b>" })] })
    var label = part(pane, 1, "eventsRowLabel")
    compare(label.textFormat, Text.PlainText, "a label is never read as markup")
    compare(label.text, "<b>x</b>")
  }

  function test_a_failed_phase_shows_its_detail_under_the_row() {
    var pane = make({ rows: [
      eventRow(1, { level: "phase", status: "failed", glyph: "dead", attempt: 0,
                    detail: "gate failed: pytest exited 1" }),
      eventRow(2, { level: "phase", status: "done", attempt: 0, detail: "" })
    ] })
    var detail = part(pane, 1, "eventsRowDetail")
    compare(detail.visible, true)
    compare(detail.text, "gate failed: pytest exited 1")
    compare(detail.wrapMode, Text.WordWrap)
    verify(Qt.colorEqual(detail.color, testTheme.urgent), "a failure's detail is urgent")
    verify(detail.y > part(pane, 1, "eventsRowLabel").y, "the detail sits under the row")
    compare(part(pane, 2, "eventsRowDetail").visible, false, "no detail, no second line")

    var plain = make({ rows: [eventRow(3, { level: "phase", status: "done", attempt: 0, detail: "note" })] })
    verify(Qt.colorEqual(part(plain, 3, "eventsRowDetail").color, testTheme.dim), "a non-failure detail is dim")
  }

  function test_failure_rows_use_urgent_and_the_double_bang() {
    var failures = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]
    var levels = ["attempt", "story", "phase", "subtask", "run"]
    var rows = []
    for (var i = 0; i < failures.length; i++)
      rows.push(eventRow(i + 1, { level: levels[i], status: failures[i], glyph: "dead" }))
    rows.push(eventRow(9, { level: "story", status: "done", glyph: "done", detail: "fine" }))
    var pane = make({ rows: rows })
    for (var j = 0; j < failures.length; j++) {
      compare(part(pane, j + 1, "eventsRowGlyph").text, RG.GLYPHS.escalated, failures[j] + " at level " + levels[j] + " shows ‼")
      var parts = ["eventsRowGlyph", "eventsRowLabel", "eventsRowStatus"]
      for (var k = 0; k < parts.length; k++)
        verify(Qt.colorEqual(part(pane, j + 1, parts[k]).color, testTheme.urgent), failures[j] + " " + parts[k])
    }
    compare(part(pane, 9, "eventsRowGlyph").text, RG.GLYPHS.done)
    var all = ["eventsRowTime", "eventsRowGlyph", "eventsRowLabel", "eventsRowStatus",
               "eventsRowDuration", "eventsRowDetail"]
    for (var m = 0; m < all.length; m++)
      verify(!Qt.colorEqual(part(pane, 9, all[m]).color, testTheme.urgent), "done " + all[m] + " is not urgent")
  }

  function test_unknown_glyph_key_shows_no_glyph() {
    var keys = ["bogus", "", "constructor", "__proto__"]
    var rows = []
    for (var i = 0; i < keys.length; i++) rows.push(eventRow(i + 1, { status: "", glyph: keys[i] }))
    var pane = make({ rows: rows })
    for (var j = 0; j < keys.length; j++)
      compare(part(pane, j + 1, "eventsRowGlyph").text, "", "glyph key " + JSON.stringify(keys[j]))
  }

  function test_garbage_props_render_without_warnings() {
    var pane = make({ theme: null, rows: [
      null, 5, "x", [],
      { seq: 1, time: 5, label: null, status: 7, duration: {}, detail: [], card: 3, phase: null,
        attempt: "2", glyph: "constructor" },
      { seq: 2 },
      { seq: 3, glyph: "__proto__", card: "c", phase: "p", attempt: -1 }
    ] })
    verify(pane.palette, "falls back to its own Theme")
    compare(listOf(pane).count, 3, "entries that are not objects are skipped")
    var parts = ["eventsRowTime", "eventsRowGlyph", "eventsRowLabel", "eventsRowStatus", "eventsRowDuration"]
    for (var s = 1; s <= 3; s++)
      for (var i = 0; i < parts.length; i++)
        compare(part(pane, s, parts[i]).text, "", "row " + s + " " + parts[i] + " is drawn empty")
    compare(part(pane, 1, "eventsRowDetail").visible, false)
    verify(Qt.colorEqual(part(pane, 2, "eventsRowLabel").color, pane.palette.foreground))
    pane.theme = testTheme
    pane.theme = null
    wait(30)
    verify(pane.palette, "back to its own Theme when the owner's goes away")
  }
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|unavailable|No such file"`
Expected: FAIL. The compile step reports `Type UI.EventsPane unavailable` and `ui/components/EventsPane.qml: No such file or directory`, then `Totals: 0 passed, 1 failed`.

- [ ] **Step 3: Write the component**

Create `ui/components/EventsPane.qml` with exactly this content:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../../core/domain/runEvents.js" as RunEvents
import "../theme" as T

// One run's event timeline. Presentation only: it draws its props and emits.
//   rows: RunEvents.eventRow rows, ascending seq, unfiltered.
//   filter: All | Phases | Failures. The pane shows RunEvents.filterRows(rows,
//     filter) as `shownRows`, oldest first, and never assigns `filter`.
//   dropped: events of the run not held; above 0 shows "… N earlier events".
//   status: idle | loading | ok | error. error shows errorText, with
//     errorMessage one Details click away, above the rows held.
//   maxListHeight: the list's height cap; past it the list scrolls itself and
//     a wheel at its ends reaches the enclosing Flickable.
//   filterRequested(filter): a chip was clicked.
//   attemptRequested(card, phase, attempt): a row with a non-empty card and
//     phase and an attempt above 0 was clicked.
Item {
  id: pane
  objectName: "eventsPane"

  // The owner's Theme, or none: `palette` then falls back to the pane's own.
  property var theme: null
  property var rows: []

  readonly property var palette: pane.theme || paneTheme
  readonly property var shownRows: RunEvents.filterRows(pane.rows, "All")

  // row[key] when row is an object and that field is a string, else "".
  function _field(row, key) {
    return row !== null && typeof row === "object" && typeof row[key] === "string" ? row[key] : ""
  }

  function _isFailure(row) { return RunEvents.filterRows([row], "Failures").length === 1 }

  function _glyphOf(row) {
    if (pane._isFailure(row)) return RunGlyphs.glyphOf("escalated")
    return RunGlyphs.glyphOf(row !== null && typeof row === "object" ? row.glyph : "")
  }

  // urgent on a failure row, else the palette's `token` colour.
  function _tint(failure, token) {
    if (!pane.palette) return Color.foreground
    return failure ? pane.palette.urgent : pane.palette[token]
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: pane.width
    spacing: Style.space(6)

    ListView {
      id: list
      objectName: "eventsList"
      visible: pane.shownRows.length > 0
      width: parent.width
      height: list.contentHeight
      interactive: false
      model: pane.shownRows

      delegate: ListRow {
        id: row
        required property var modelData
        readonly property bool failure: pane._isFailure(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: list.width
        theme: pane.palette

        Row {
          spacing: Style.space(8)

          ThemedText {
            objectName: "eventsRowTime"
            theme: pane.palette
            variant: "dim"
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "time")
          }
          ThemedText {
            objectName: "eventsRowGlyph"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._glyphOf(row.modelData)
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowLabel"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "label")
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowStatus"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "status")
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowDuration"
            theme: pane.palette
            variant: "dim"
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "duration")
          }
        }

        ThemedText {
          objectName: "eventsRowDetail"
          width: parent.width
          theme: pane.palette
          visible: text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: pane._field(row.modelData, "detail")
          color: pane._tint(row.failure, "dim")
        }
      }
    }
  }

  T.Theme { id: paneTheme }
}
```

Notes for the implementer:
- `ListRow` is used as the delegate with `required property var modelData` only. Do **not** declare `required index`: that would set `ListRow.index` and make the rows keyboard-navigable, which the spec forbids. The test asserts `index === -1`.
- Every text reads through `_field()`, so a missing or non-string field is `""`. Assigning `undefined` to a `Text.text` prints `Unable to assign [undefined] to QString`, which `tests/run.sh` rejects.
- `_isFailure` asks `RunEvents.filterRows([row], "Failures")`, so the failure set lives only in `runEvents.js`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 8 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): draw a run's event rows with glyph, failure tint and detail"
```

---

### Task 2: A row naming an attempt emits attemptRequested

**Files:**
- Modify: `ui/components/EventsPane.qml`
- Modify: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: Task 1's `EventsPane` (`_field`, the `ListRow` delegate `row` with `row.modelData` and `row.failure`). `ListRow.activated()` and `ListRow.hoverCursorShape`.
- Produces: `signal attemptRequested(string card, string phase, int attempt)`; `_namesAttempt(row)`, which is true when `card` and `phase` are non-empty strings and `attempt` is a finite number above 0; and the delegate property `row.namesAttempt`.

- [ ] **Step 1: Write the failing tests**

Edit 1 of 2 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
  Component { id: paneC; UI.EventsPane { width: 600 } }
```

with:

```qml
  Component { id: paneC; UI.EventsPane { width: 600 } }

  SignalSpy { id: attemptSpy; signalName: "attemptRequested" }
```

Edit 2 of 2 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
    for (var key in p) pane[key] = p[key]
    wait(30)
```

with:

```qml
    for (var key in p) pane[key] = p[key]
    attemptSpy.target = pane
    attemptSpy.clear()
    wait(30)
```

Then add these functions at the end of the `TestCase`, just before its closing `}` (the file's last line):

```qml
  // ---- clicks --------------------------------------------------------------

  function test_a_row_naming_an_attempt_emits_attemptRequested() {
    var pane = make({ rows: [eventRow(5, { card: "card-a", phase: "implement", attempt: 2 })] })
    compare(rowOf(pane, 5).hoverCursorShape, Qt.PointingHandCursor)
    mouseClick(rowOf(pane, 5))
    compare(attemptSpy.count, 1)
    compare(attemptSpy.signalArguments[0][0], "card-a")
    compare(attemptSpy.signalArguments[0][1], "implement")
    compare(attemptSpy.signalArguments[0][2], 2)
  }

  function test_a_row_without_an_attempt_emits_nothing() {
    var pane = make({ rows: [
      eventRow(1, { level: "phase", attempt: 0 }),
      eventRow(2, { card: "" }),
      eventRow(3, { phase: "" }),
      eventRow(4, { attempt: "2" }),
      eventRow(5, { level: "run", card: "", phase: "", attempt: 0, label: "run started", status: "started" })
    ] })
    for (var s = 1; s <= 5; s++) {
      compare(rowOf(pane, s).hoverCursorShape, Qt.ArrowCursor, "row " + s + " has the arrow")
      mouseClick(rowOf(pane, s))
      compare(attemptSpy.count, 0, "row " + s + " emits nothing")
    }
  }
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `test_a_row_naming_an_attempt_emits_attemptRequested` fails (`Actual 0, Expected 1`). `test_a_row_without_an_attempt_emits_nothing` fails on "row 1 has the arrow" (`Actual 13`, the pointing-hand cursor `ListRow` defaults to). `Totals: 8 passed, 2 failed`. The run also prints `Signal 'attemptRequested' not found` debug lines from the spy; they go away in Step 4.

- [ ] **Step 3: Implement**

Edit 1 of 3 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  readonly property var shownRows: RunEvents.filterRows(pane.rows, "All")
```

with:

```qml
  readonly property var shownRows: RunEvents.filterRows(pane.rows, "All")

  signal attemptRequested(string card, string phase, int attempt)
```

Edit 2 of 3 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  function _isFailure(row) { return RunEvents.filterRows([row], "Failures").length === 1 }
```

with:

```qml
  function _isFailure(row) { return RunEvents.filterRows([row], "Failures").length === 1 }

  function _namesAttempt(row) {
    return pane._field(row, "card") !== "" && pane._field(row, "phase") !== ""
      && typeof row.attempt === "number" && isFinite(row.attempt) && row.attempt > 0
  }
```

Edit 3 of 3 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
        readonly property bool failure: pane._isFailure(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: list.width
        theme: pane.palette
```

with:

```qml
        readonly property bool failure: pane._isFailure(row.modelData)
        readonly property bool namesAttempt: pane._namesAttempt(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: list.width
        theme: pane.palette
        hoverCursorShape: row.namesAttempt ? Qt.PointingHandCursor : Qt.ArrowCursor
        onActivated: if (row.namesAttempt)
          pane.attemptRequested(row.modelData.card, row.modelData.phase, row.modelData.attempt)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 10 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): a row naming an attempt emits attemptRequested, others do nothing"
```

---

### Task 3: Filter chips, and the pane applies the filter

**Files:**
- Modify: `ui/components/EventsPane.qml`
- Modify: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: `ChipRow` (`model: [{ id, label }]`, `active`, `chipPrefix`, `chosen(string id)`; a chip's objectName is `chipPrefix + id`, and with no `count` its text is its label). Task 1's `shownRows`.
- Produces: `property string filter: "All"`, `signal filterRequested(string filter)`, and `shownRows` = `RunEvents.filterRows(rows, filter)`. Children `eventsFilterChipAll`, `eventsFilterChipPhases` and `eventsFilterChipFailures`. Test helpers `mixedRows()` (seq 1 run started, 2 story escalated, 3 phase done, 4 attempt done, 5 attempt failed) and `seqsOf(pane)`, which Tasks 4 and 5 reuse.

- [ ] **Step 1: Write the failing tests**

Edit 1 of 2 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
  SignalSpy { id: attemptSpy; signalName: "attemptRequested" }
```

with:

```qml
  SignalSpy { id: filterSpy; signalName: "filterRequested" }
  SignalSpy { id: attemptSpy; signalName: "attemptRequested" }
```

Edit 2 of 2 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
    for (var key in p) pane[key] = p[key]
    attemptSpy.target = pane
```

with:

```qml
    for (var key in p) pane[key] = p[key]
    filterSpy.target = pane
    filterSpy.clear()
    attemptSpy.target = pane
```

Then add these functions at the end of the `TestCase`, just before its closing `}`:

```qml
  // ---- filter chips --------------------------------------------------------

  function mixedRows() {
    return [
      eventRow(1, { level: "run", label: "run started", status: "started", card: "", phase: "", attempt: 0 }),
      eventRow(2, { level: "story", label: "Story", status: "escalated", card: "", phase: "", attempt: 0 }),
      eventRow(3, { level: "phase", status: "done", attempt: 0 }),
      eventRow(4, { level: "attempt", status: "done" }),
      eventRow(5, { level: "attempt", status: "failed" })
    ]
  }

  function seqsOf(pane) { return pane.shownRows.map(function (r) { return r.seq }) }

  function test_filter_chips_mark_the_active_filter() {
    var ids = ["All", "Phases", "Failures"]
    for (var i = 0; i < ids.length; i++) {
      var pane = make({ rows: mixedRows(), filter: ids[i] })
      for (var j = 0; j < ids.length; j++) {
        var chip = H.find(pane, "eventsFilterChip" + ids[j])
        verify(chip, ids[j] + " chip exists")
        compare(chip.text, ids[j], "a chip shows its label and no count")
        compare(chip.active, i === j, "filter " + ids[i] + ": chip " + ids[j])
      }
    }
    var chips = make({ rows: [] })
    verify(H.find(chips, "eventsFilterChipAll").x < H.find(chips, "eventsFilterChipPhases").x, "All, then Phases")
    verify(H.find(chips, "eventsFilterChipPhases").x < H.find(chips, "eventsFilterChipFailures").x, "then Failures")
    var odd = make({ rows: mixedRows(), filter: "Bogus" })
    for (var k = 0; k < ids.length; k++)
      compare(H.find(odd, "eventsFilterChip" + ids[k]).active, false, "an unknown filter marks no chip")
    compare(listOf(odd).count, 5, "an unknown filter shows every row")
  }

  function test_a_chip_click_requests_its_filter_without_changing_it() {
    var pane = make({ rows: mixedRows() })
    mouseClick(H.find(pane, "eventsFilterChipFailures"))
    compare(filterSpy.count, 1)
    compare(filterSpy.signalArguments[0][0], "Failures")
    compare(pane.filter, "All", "the pane never assigns its filter")
    compare(listOf(pane).count, 5, "the rows shown are unchanged")
    mouseClick(H.find(pane, "eventsFilterChipAll"))
    compare(filterSpy.count, 2, "the active chip emits too")
    compare(filterSpy.signalArguments[1][0], "All")
  }

  function test_the_pane_applies_the_filter() {
    var pane = make({ rows: mixedRows() })
    compare(seqsOf(pane), [1, 2, 3, 4, 5])
    pane.filter = "Phases"
    wait(30)
    compare(seqsOf(pane), [3, 4, 5])
    compare(listOf(pane).count, 3)
    verify(!rowOf(pane, 1), "the run row is not drawn under Phases")
    pane.filter = "Failures"
    wait(30)
    compare(seqsOf(pane), [2, 5], "a failure at any level")
    compare(listOf(pane).count, 2)
  }
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: three FAILs. `test_filter_chips_mark_the_active_filter` and `test_the_pane_applies_the_filter` fail with `Cannot assign to non-existent property "filter"`. `test_a_chip_click_requests_its_filter_without_changing_it` fails with `mouseClick requires an Item or Window type`. `Totals: 10 passed, 3 failed`.

- [ ] **Step 3: Implement**

Edit 1 of 2 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  property var rows: []

  readonly property var palette: pane.theme || paneTheme
  readonly property var shownRows: RunEvents.filterRows(pane.rows, "All")

  signal attemptRequested(string card, string phase, int attempt)
```

with:

```qml
  property var rows: []
  property string filter: "All"

  readonly property var palette: pane.theme || paneTheme
  readonly property var shownRows: RunEvents.filterRows(pane.rows, pane.filter)

  signal filterRequested(string filter)
  signal attemptRequested(string card, string phase, int attempt)
```

Edit 2 of 2 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
    spacing: Style.space(6)

    ListView {
```

with:

```qml
    spacing: Style.space(6)

    ChipRow {
      width: parent.width
      theme: pane.palette
      chipPrefix: "eventsFilterChip"
      active: pane.filter
      model: [{ id: "All", label: "All" }, { id: "Phases", label: "Phases" },
              { id: "Failures", label: "Failures" }]
      onChosen: function(id) { pane.filterRequested(id) }
    }

    ListView {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 13 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): All / Phases / Failures chips request a filter the pane applies"
```

---

### Task 4: The earlier-events line and the status line

**Files:**
- Modify: `ui/components/EventsPane.qml`
- Modify: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: `ListStatus` (`loading`, `loadingText`, `error`, `empty`, `filtered`, `emptyText`, `filteredText`; its precedence is loading, then error, then empty, and an empty text hides it). Task 3's `mixedRows()` and `filter`.
- Produces: `property int dropped: 0`, `property string status: "idle"`, the internal `readonly property int _heldCount` (the count of object rows held, unfiltered), and the children `eventsEarlier` and `eventsStatus`. The test helper `statusOf(pane)`.

In this task `empty` is `shownRows.length === 0`. Task 5 narrows it so that an error with no rows says nothing.

- [ ] **Step 1: Write the failing tests**

Edit 1 of 1 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
  function listOf(pane) { return H.find(pane, "eventsList") }
```

with:

```qml
  function listOf(pane) { return H.find(pane, "eventsList") }
  function statusOf(pane) { return H.find(pane, "eventsStatus") }
```

Then add these functions at the end of the `TestCase`, just before its closing `}`:

```qml
  // ---- earlier events and the status line ----------------------------------

  function test_earlier_line_shows_the_dropped_count() {
    compare(H.find(make({ rows: mixedRows(), dropped: 0 }), "eventsEarlier").visible, false)
    compare(H.find(make({ rows: mixedRows(), dropped: -1 }), "eventsEarlier").visible, false)
    var one = H.find(make({ rows: mixedRows(), dropped: 1 }), "eventsEarlier")
    compare(one.visible, true)
    compare(one.text, "… 1 earlier event")
    var many = make({ rows: mixedRows(), dropped: 37 })
    compare(H.find(many, "eventsEarlier").text, "… 37 earlier events")
    verify(Qt.colorEqual(H.find(many, "eventsEarlier").color, testTheme.dim))
    verify(H.find(many, "eventsEarlier").y < listOf(many).y, "above the list")
    many.filter = "Failures"
    wait(30)
    compare(H.find(many, "eventsEarlier").visible, true, "independent of the filter")
    compare(H.find(many, "eventsEarlier").text, "… 37 earlier events")
  }

  function test_empty_state_says_no_events_yet() {
    var pane = make({ rows: [], status: "ok" })
    compare(statusOf(pane).visible, true)
    compare(statusOf(pane).text, "No events yet.")
    compare(listOf(pane).visible, false)
    compare(statusOf(make({ rows: [] })).text, "No events yet.", "idle too")

    var bad = [null, undefined, "x", 5, {}]
    var labels = ["null", "undefined", "\"x\"", "5", "{}"]
    for (var i = 0; i < bad.length; i++) {
      var shown = make({ rows: mixedRows(), status: "ok" })
      compare(listOf(shown).visible, true, labels[i] + " starts with rows")
      compare(statusOf(shown).visible, false, labels[i] + " starts with no status line")
      shown.rows = bad[i]
      wait(30)
      compare(shown.shownRows.length, 0, labels[i])
      compare(statusOf(shown).text, "No events yet.", labels[i] + " reads as empty")
      compare(listOf(shown).visible, false, labels[i] + " hides the list")
    }
  }

  function test_a_filter_that_empties_the_list_says_so() {
    var pane = make({ rows: [eventRow(1, { status: "done" })], filter: "Failures", status: "ok" })
    compare(statusOf(pane).text, "No events match the filter.")
    compare(listOf(pane).visible, false)
  }

  function test_loading_without_rows_shows_loading_and_with_rows_keeps_them() {
    var empty = make({ rows: [], status: "loading" })
    compare(statusOf(empty).text, "Loading events…")
    compare(statusOf(empty).visible, true)
    var held = make({ rows: mixedRows(), status: "loading" })
    compare(statusOf(held).visible, false, "no loading line over held rows")
    compare(listOf(held).visible, true)
    compare(listOf(held).count, 5)
  }
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: four FAILs, each with `Cannot assign to non-existent property "status"` or `"dropped"`. `Totals: 13 passed, 4 failed`.

- [ ] **Step 3: Implement**

Edit 1 of 3 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  property string filter: "All"
```

with:

```qml
  property string filter: "All"
  property int dropped: 0
  property string status: "idle"
```

Edit 2 of 3 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  readonly property var shownRows: RunEvents.filterRows(pane.rows, pane.filter)
```

with:

```qml
  readonly property var shownRows: RunEvents.filterRows(pane.rows, pane.filter)
  readonly property int _heldCount: RunEvents.filterRows(pane.rows, "All").length
```

Edit 3 of 3 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
      onChosen: function(id) { pane.filterRequested(id) }
    }
```

with:

```qml
      onChosen: function(id) { pane.filterRequested(id) }
    }

    ThemedText {
      objectName: "eventsEarlier"
      theme: pane.palette
      variant: "dim"
      visible: pane.dropped > 0
      text: "… " + pane.dropped + " earlier event" + (pane.dropped === 1 ? "" : "s")
    }

    ListStatus {
      objectName: "eventsStatus"
      width: parent.width
      theme: pane.palette
      loading: pane.status === "loading" && pane.shownRows.length === 0
      loadingText: "Loading events…"
      error: ""
      empty: pane.shownRows.length === 0
      filtered: pane._heldCount > 0
      emptyText: "No events yet."
      filteredText: "No events match the filter."
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 17 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): earlier-events count and the loading / empty / filtered-empty line"
```

---

### Task 5: The error block, with the raw message one click away

**Files:**
- Modify: `ui/components/EventsPane.qml`
- Modify: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: `ActionButton` (`text`, `theme`, `clicked()`; under the test stubs it is a 80x28 `Item` whose `MouseArea` emits `clicked`). Task 4's `status`, `_heldCount` and `eventsStatus`.
- Produces: `property string errorText: "Events unreadable."`, `property string errorMessage: ""`, the internal `property bool _errorExpanded`, and the children `eventsError`, `eventsErrorText`, `eventsErrorToggle` and `eventsErrorMessage`. `ListStatus.empty` becomes `shownRows.length === 0 && (_heldCount > 0 || status !== "error")`.

Do not put `anchors.*` on the items inside the error `Row`: a `Row` rejects vertical anchors and prints a warning.

- [ ] **Step 1: Write the failing tests**

Add these functions at the end of the `TestCase`, just before its closing `}`:

```qml
  // ---- error state ---------------------------------------------------------

  function test_error_state_shows_the_headline_and_keeps_the_rows() {
    var pane = make({ rows: mixedRows(), status: "error" })
    var block = H.find(pane, "eventsError")
    compare(block.visible, true)
    compare(H.find(pane, "eventsErrorText").text, "Events unreadable.")
    verify(Qt.colorEqual(H.find(pane, "eventsErrorText").color, testTheme.urgent))
    compare(listOf(pane).visible, true, "the rows held stay")
    compare(listOf(pane).count, 5)
    verify(block.y < listOf(pane).y, "the error sits above the rows")
    pane.errorText = "events unreadable"
    compare(H.find(pane, "eventsErrorText").text, "events unreadable")

    var states = ["idle", "loading", "ok"]
    for (var i = 0; i < states.length; i++) {
      pane.status = states[i]
      compare(H.find(pane, "eventsError").visible, false, "no error block while " + states[i])
    }

    var bare = make({ rows: [], status: "error" })
    compare(H.find(bare, "eventsError").visible, true)
    compare(statusOf(bare).visible, false, "an error with no rows does not say No events yet.")

    var narrowed = make({ rows: [eventRow(1, { status: "done" })], filter: "Failures", status: "error" })
    compare(H.find(narrowed, "eventsError").visible, true)
    compare(statusOf(narrowed).text, "No events match the filter.", "rows held but filtered out")
  }

  function test_the_raw_message_is_one_click_away() {
    var pane = make({ rows: mixedRows(), status: "error", errorMessage: "am events: exit 3: bad journal" })
    var toggle = H.find(pane, "eventsErrorToggle")
    var message = H.find(pane, "eventsErrorMessage")
    compare(toggle.visible, true)
    compare(toggle.text, "Details")
    compare(message.visible, false, "hidden at first")
    mouseClick(toggle)
    compare(message.visible, true)
    compare(message.text, "am events: exit 3: bad journal")
    compare(message.textFormat, Text.PlainText)
    compare(message.wrapMode, Text.WordWrap)
    compare(toggle.text, "Hide")
    mouseClick(toggle)
    compare(message.visible, false)
    compare(toggle.text, "Details")

    mouseClick(toggle)
    compare(message.visible, true)
    pane.status = "ok"
    pane.status = "error"
    compare(message.visible, false, "the next error starts collapsed")
    compare(toggle.text, "Details")

    var quiet = make({ rows: [], status: "error", errorMessage: "" })
    compare(H.find(quiet, "eventsErrorToggle").visible, false, "no message, no toggle")
    compare(H.find(quiet, "eventsErrorMessage").visible, false)
  }
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: two FAILs. `test_error_state_shows_the_headline_and_keeps_the_rows` fails with `Cannot read property 'visible' of null`. `test_the_raw_message_is_one_click_away` fails with `Cannot assign to non-existent property "errorMessage"`. `Totals: 17 passed, 2 failed`.

- [ ] **Step 3: Implement**

Edit 1 of 5 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  property string status: "idle"
```

with:

```qml
  property string status: "idle"
  property string errorText: "Events unreadable."
  property string errorMessage: ""
```

Edit 2 of 5 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  readonly property int _heldCount: RunEvents.filterRows(pane.rows, "All").length
```

with:

```qml
  readonly property int _heldCount: RunEvents.filterRows(pane.rows, "All").length
  property bool _errorExpanded: false
```

Edit 3 of 5 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  implicitHeight: column.implicitHeight
```

with:

```qml
  implicitHeight: column.implicitHeight
  onStatusChanged: if (pane.status !== "error") pane._errorExpanded = false
```

Edit 4 of 5 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
      onChosen: function(id) { pane.filterRequested(id) }
    }
```

with:

```qml
      onChosen: function(id) { pane.filterRequested(id) }
    }

    Column {
      objectName: "eventsError"
      visible: pane.status === "error"
      width: parent.width
      spacing: Style.space(4)

      Row {
        spacing: Style.space(8)

        ThemedText {
          objectName: "eventsErrorText"
          theme: pane.palette
          textFormat: Text.PlainText
          text: pane.errorText
          color: pane._tint(true, "urgent")
        }

        ActionButton {
          objectName: "eventsErrorToggle"
          theme: pane.palette
          visible: pane.errorMessage !== ""
          text: pane._errorExpanded ? "Hide" : "Details"
          onClicked: pane._errorExpanded = !pane._errorExpanded
        }
      }

      ThemedText {
        objectName: "eventsErrorMessage"
        width: parent.width
        theme: pane.palette
        variant: "dim"
        visible: pane._errorExpanded && pane.errorMessage !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: pane.errorMessage
      }
    }
```

Edit 5 of 5 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
      empty: pane.shownRows.length === 0
```

with:

```qml
      empty: pane.shownRows.length === 0 && (pane._heldCount > 0 || pane.status !== "error")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 19 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): error headline above the held rows, raw message behind Details"
```

---

### Task 6: A bounded list that scrolls itself and hands the wheel to the page

**Files:**
- Modify: `ui/components/EventsPane.qml`
- Modify: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: Task 1's `eventsList` `ListView`. QtTest's `mouseWheel(item, x, y, xDelta, yDelta, buttons, modifiers)`, where a negative `yDelta` scrolls down.
- Produces: `property real maxListHeight: Style.space(320)`. The list becomes `height: Math.min(contentHeight, maxListHeight)`, `clip: true`, vertical and `StopAtBounds`. Test fixtures: the `stackC` Flickable (`pane` alias, `maxListHeight: 200`) and the helpers `manyRows(n)` and `wheelOverList(stack, yDelta)`.

**The mechanism (settled empirically, Qt 6.11.2):** no `WheelHandler`. A vertical `ListView` with `boundsBehavior: Flickable.StopAtBounds` consumes a wheel only while it can move that way. At its top or bottom, or when its content fits, the event goes on to the enclosing `Flickable`. The rows' `ListRow` `MouseArea` has no `onWheel`, so it does not swallow the event either. Adding a `WheelHandler` here would be wrong: one that fires blocks the items behind it (`GraphView.qml:165-218`).

- [ ] **Step 1: Write the failing tests**

Edit 1 of 3 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
  Component { id: paneC; UI.EventsPane { width: 600 } }
```

with:

```qml
  Component { id: paneC; UI.EventsPane { width: 600 } }

  // The panel's own page around the pane: a vertical Flickable over a Column,
  // taller than the Flickable, as tst_graph_wheel.qml builds it.
  Component {
    id: stackC

    Flickable {
      width: 600; height: 400
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      property alias pane: eventsPane

      Column {
        id: column
        width: parent.width

        Item { width: parent.width; height: 100 }
        UI.EventsPane { id: eventsPane; width: parent.width; theme: testTheme; maxListHeight: 200 }
        Item { width: parent.width; height: 800 }
      }
    }
  }
```

Edit 2 of 3 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
  function rowOf(pane, seq) { return H.find(pane, "eventsRow" + seq) }
```

with:

```qml
  function manyRows(n) {
    var rows = []
    for (var i = 1; i <= n; i++) rows.push(eventRow(i, {}))
    return rows
  }

  function rowOf(pane, seq) { return H.find(pane, "eventsRow" + seq) }
```

Edit 3 of 3 in `tests/ui/components/tst_events_pane.qml` — replace this exact text:

```qml
  function statusOf(pane) { return H.find(pane, "eventsStatus") }
```

with:

```qml
  function statusOf(pane) { return H.find(pane, "eventsStatus") }

  function wheelOverList(stack, yDelta) {
    var list = listOf(stack.pane)
    var p = list.mapToItem(stack, list.width / 2, list.height / 2)
    mouseWheel(stack, p.x, p.y, 0, yDelta, Qt.NoButton, Qt.NoModifier)
  }
```

Then add these functions at the end of the `TestCase`, just before its closing `}`:

```qml
  // ---- the list: bounded height, own scrolling, wheel hand-off -------------

  function test_the_list_height_is_bounded() {
    var short = make({ rows: manyRows(3), maxListHeight: 300 })
    var list = listOf(short)
    verify(list.contentHeight > 0)
    compare(list.height, list.contentHeight, "a short list is exactly as tall as its rows")
    verify(list.height < short.maxListHeight)
    compare(list.clip, true)

    var long = make({ rows: manyRows(100), maxListHeight: 300 })
    var longList = listOf(long)
    compare(longList.height, 300, "a long list is capped")
    verify(longList.contentHeight > longList.height, "and scrolls inside itself")
    verify(long.implicitHeight >= longList.height, "the pane holds the capped list")
  }

  function test_a_wheel_in_the_middle_of_the_list_scrolls_only_the_list() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    var list = listOf(stack.pane)
    list.contentY = list.originY + 100
    wait(30)
    verify(!list.atYBeginning && !list.atYEnd, "the list starts in its middle")
    var before = list.contentY
    wheelOverList(stack, -120)
    tryVerify(function () { return list.contentY > before }, 1000, "the list scrolls down")
    compare(stack.contentY, 0, "the page does not move")
  }

  function test_a_wheel_down_at_the_list_bottom_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    var list = listOf(stack.pane)
    list.positionViewAtEnd()
    wait(30)
    verify(list.atYEnd, "the list starts at its bottom")
    var before = list.contentY
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
    compare(list.contentY, before, "the list stays at its bottom")
  }

  function test_a_wheel_up_at_the_list_top_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    stack.contentY = 50
    wait(30)
    var list = listOf(stack.pane)
    verify(list.atYBeginning, "the list starts at its top")
    wheelOverList(stack, 120)
    tryVerify(function () { return stack.contentY < 50 }, 1000, "the page scrolls up")
    verify(list.atYBeginning, "the list stays at its top")
  }

  function test_a_wheel_over_a_list_that_fits_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(3)
    wait(50)
    var list = listOf(stack.pane)
    verify(list.contentHeight <= list.height, "the rows fit")
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
  }
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|non-existent"`
Expected: the file does not compile, because the `stackC` fixture sets `maxListHeight`. The output shows `Cannot assign to non-existent property "maxListHeight"` and `Totals: 0 passed, 1 failed`.

- [ ] **Step 3: Implement**

Edit 1 of 2 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  property string errorMessage: ""
```

with:

```qml
  property string errorMessage: ""
  property real maxListHeight: Style.space(320)
```

Edit 2 of 2 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
      height: list.contentHeight
      interactive: false
      model: pane.shownRows
```

with:

```qml
      height: Math.min(list.contentHeight, pane.maxListHeight)
      clip: true
      orientation: ListView.Vertical
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds
      model: pane.shownRows
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 24 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

If a wheel test fails here, do not reach for a `WheelHandler` first. Check the fixture: the list must sit inside the `stackC` Flickable, and `wheelOverList` must map the list's centre into `stack` coordinates. All four wheel tests passed with exactly this component in the scratch run that settled the mechanism.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): bounded list scrolls itself; at its ends the wheel scrolls the page"
```

---

### Task 7: New rows keep the list where it was

**Files:**
- Modify: `ui/components/EventsPane.qml`
- Modify: `tests/ui/components/tst_events_pane.qml`

**Interfaces:**
- Consumes: Task 6's bounded `eventsList` and `manyRows(n)`.
- Produces: `_showRows()`, which sets `list.model` imperatively and restores `contentY` clamped to `[originY, originY + contentHeight - height]`. It is called from `onShownRowsChanged` and `Component.onCompleted`. The `model:` binding on the `ListView` is removed.

Why: the store hands over a new `events` array on every fetch, and replacing a `ListView`'s model resets it to its top, so a user reading mid-list would be thrown back to the oldest row on each live event. Following the newest row and the `Jump ↓` control remain 4.2's job. This task only stops the pane from scrolling on its own.

- [ ] **Step 1: Write the failing test**

Add this function at the end of the `TestCase`, just before its closing `}`:

```qml
  function test_new_rows_keep_the_list_where_it_was() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    list.contentY = list.originY + 300
    wait(30)
    var before = list.contentY
    pane.rows = manyRows(52)
    wait(50)
    compare(list.count, 52, "the new rows are shown")
    compare(list.contentY, before, "a new rows array does not move the list")
    pane.rows = manyRows(3)
    wait(50)
    compare(list.count, 3)
    compare(list.contentY, list.originY, "a list that now fits sits at its top")
  }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|Actual|Expected"`
Expected: `test_new_rows_keep_the_list_where_it_was` fails on "a new rows array does not move the list" with `Actual 0, Expected 300`. `Totals: 24 passed, 1 failed`.

- [ ] **Step 3: Implement**

Edit 1 of 2 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
      boundsBehavior: Flickable.StopAtBounds
      model: pane.shownRows
```

with:

```qml
      boundsBehavior: Flickable.StopAtBounds
```

Edit 2 of 2 in `ui/components/EventsPane.qml` — replace this exact text:

```qml
  implicitHeight: column.implicitHeight
  onStatusChanged: if (pane.status !== "error") pane._errorExpanded = false
```

with:

```qml
  // Hands shownRows to the list. A new model puts a ListView back at its top,
  // so the list keeps its scroll position instead, within its new bounds.
  function _showRows() {
    var y = list.contentY
    list.model = pane.shownRows
    list.forceLayout()
    list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
  }

  implicitHeight: column.implicitHeight
  onStatusChanged: if (pane.status !== "error") pane._errorExpanded = false
  onShownRowsChanged: pane._showRows()
  Component.onCompleted: pane._showRows()
```

After this edit, `ui/components/EventsPane.qml` reads exactly:

```qml
import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../../core/domain/runEvents.js" as RunEvents
import "../theme" as T

// One run's event timeline. Presentation only: it draws its props and emits.
//   rows: RunEvents.eventRow rows, ascending seq, unfiltered.
//   filter: All | Phases | Failures. The pane shows RunEvents.filterRows(rows,
//     filter) as `shownRows`, oldest first, and never assigns `filter`.
//   dropped: events of the run not held; above 0 shows "… N earlier events".
//   status: idle | loading | ok | error. error shows errorText, with
//     errorMessage one Details click away, above the rows held.
//   maxListHeight: the list's height cap; past it the list scrolls itself and
//     a wheel at its ends reaches the enclosing Flickable.
//   filterRequested(filter): a chip was clicked.
//   attemptRequested(card, phase, attempt): a row with a non-empty card and
//     phase and an attempt above 0 was clicked.
Item {
  id: pane
  objectName: "eventsPane"

  // The owner's Theme, or none: `palette` then falls back to the pane's own.
  property var theme: null
  property var rows: []
  property string filter: "All"
  property int dropped: 0
  property string status: "idle"
  property string errorText: "Events unreadable."
  property string errorMessage: ""
  property real maxListHeight: Style.space(320)

  readonly property var palette: pane.theme || paneTheme
  readonly property var shownRows: RunEvents.filterRows(pane.rows, pane.filter)
  readonly property int _heldCount: RunEvents.filterRows(pane.rows, "All").length
  property bool _errorExpanded: false

  signal filterRequested(string filter)
  signal attemptRequested(string card, string phase, int attempt)

  // row[key] when row is an object and that field is a string, else "".
  function _field(row, key) {
    return row !== null && typeof row === "object" && typeof row[key] === "string" ? row[key] : ""
  }

  function _isFailure(row) { return RunEvents.filterRows([row], "Failures").length === 1 }

  function _namesAttempt(row) {
    return pane._field(row, "card") !== "" && pane._field(row, "phase") !== ""
      && typeof row.attempt === "number" && isFinite(row.attempt) && row.attempt > 0
  }

  function _glyphOf(row) {
    if (pane._isFailure(row)) return RunGlyphs.glyphOf("escalated")
    return RunGlyphs.glyphOf(row !== null && typeof row === "object" ? row.glyph : "")
  }

  // urgent on a failure row, else the palette's `token` colour.
  function _tint(failure, token) {
    if (!pane.palette) return Color.foreground
    return failure ? pane.palette.urgent : pane.palette[token]
  }

  // Hands shownRows to the list. A new model puts a ListView back at its top,
  // so the list keeps its scroll position instead, within its new bounds.
  function _showRows() {
    var y = list.contentY
    list.model = pane.shownRows
    list.forceLayout()
    list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
  }

  implicitHeight: column.implicitHeight
  onStatusChanged: if (pane.status !== "error") pane._errorExpanded = false
  onShownRowsChanged: pane._showRows()
  Component.onCompleted: pane._showRows()

  Column {
    id: column
    width: pane.width
    spacing: Style.space(6)

    ChipRow {
      width: parent.width
      theme: pane.palette
      chipPrefix: "eventsFilterChip"
      active: pane.filter
      model: [{ id: "All", label: "All" }, { id: "Phases", label: "Phases" },
              { id: "Failures", label: "Failures" }]
      onChosen: function(id) { pane.filterRequested(id) }
    }

    Column {
      objectName: "eventsError"
      visible: pane.status === "error"
      width: parent.width
      spacing: Style.space(4)

      Row {
        spacing: Style.space(8)

        ThemedText {
          objectName: "eventsErrorText"
          theme: pane.palette
          textFormat: Text.PlainText
          text: pane.errorText
          color: pane._tint(true, "urgent")
        }

        ActionButton {
          objectName: "eventsErrorToggle"
          theme: pane.palette
          visible: pane.errorMessage !== ""
          text: pane._errorExpanded ? "Hide" : "Details"
          onClicked: pane._errorExpanded = !pane._errorExpanded
        }
      }

      ThemedText {
        objectName: "eventsErrorMessage"
        width: parent.width
        theme: pane.palette
        variant: "dim"
        visible: pane._errorExpanded && pane.errorMessage !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: pane.errorMessage
      }
    }

    ThemedText {
      objectName: "eventsEarlier"
      theme: pane.palette
      variant: "dim"
      visible: pane.dropped > 0
      text: "… " + pane.dropped + " earlier event" + (pane.dropped === 1 ? "" : "s")
    }

    ListStatus {
      objectName: "eventsStatus"
      width: parent.width
      theme: pane.palette
      loading: pane.status === "loading" && pane.shownRows.length === 0
      loadingText: "Loading events…"
      error: ""
      empty: pane.shownRows.length === 0 && (pane._heldCount > 0 || pane.status !== "error")
      filtered: pane._heldCount > 0
      emptyText: "No events yet."
      filteredText: "No events match the filter."
    }

    ListView {
      id: list
      objectName: "eventsList"
      visible: pane.shownRows.length > 0
      width: parent.width
      height: Math.min(list.contentHeight, pane.maxListHeight)
      clip: true
      orientation: ListView.Vertical
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds

      delegate: ListRow {
        id: row
        required property var modelData
        readonly property bool failure: pane._isFailure(row.modelData)
        readonly property bool namesAttempt: pane._namesAttempt(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: list.width
        theme: pane.palette
        hoverCursorShape: row.namesAttempt ? Qt.PointingHandCursor : Qt.ArrowCursor
        onActivated: if (row.namesAttempt)
          pane.attemptRequested(row.modelData.card, row.modelData.phase, row.modelData.attempt)

        Row {
          spacing: Style.space(8)

          ThemedText {
            objectName: "eventsRowTime"
            theme: pane.palette
            variant: "dim"
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "time")
          }
          ThemedText {
            objectName: "eventsRowGlyph"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._glyphOf(row.modelData)
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowLabel"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "label")
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowStatus"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "status")
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowDuration"
            theme: pane.palette
            variant: "dim"
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "duration")
          }
        }

        ThemedText {
          objectName: "eventsRowDetail"
          width: parent.width
          theme: pane.palette
          visible: text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: pane._field(row.modelData, "detail")
          color: pane._tint(row.failure, "dim")
        }
      }
    }
  }

  T.Theme { id: paneTheme }
}
```

- [ ] **Step 4: Run the test file to verify it passes**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"`
Expected: `Totals: 25 passed, 0 failed, 0 skipped, 0 blacklisted` and no other line.

- [ ] **Step 5: Run the whole gate**

Run: `bash tests/run.sh`
Expected: exit status 0. pytest reports all passed, including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`. Every `== tests/...` QML block shows a `Totals: ... 0 failed` line, and no rejected-warning line is printed. `git status --short` shows only the two new files, already committed, plus this spec and plan.

- [ ] **Step 6: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "fix(events-pane): a new rows array keeps the list's scroll position"
```
<!-- task-pipeline: validated -->
