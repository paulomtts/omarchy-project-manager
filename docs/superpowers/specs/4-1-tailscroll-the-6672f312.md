# 4.1 `TailScroll`: the shared follow-the-bottom view — spec

Card `6672f312-5301-4a94-a055-607b805a9b63`, subtask of story `1e0d855b-47b6-4f27-a098-746aafcb885a`
(Live run output), blocked by nothing. Parent design:
`docs/superpowers/specs/2026-10-05-live-output-design.md` (below: **LO**).

## Purpose

`ui/components/EventsPane.qml` holds, inline, a bounded list that scrolls itself, follows new
content while at its bottom, shows `Jump ↓` when scrolled up, and hands a wheel at its ends to the
enclosing Flickable. The live output pane (a later card) needs the same behaviour. This card moves
that behaviour, unchanged, into a new shared component `ui/components/TailScroll.qml`, makes
`EventsPane` use it, and proves it with a new component test. `EventsPane`'s observable behaviour
does not change: its existing tests pass, unchanged except two position assertions that compare
sibling `y` values against the list's `y` and now compare positions mapped into the pane (see
"`EventsPane` tests" below).

## Inherited constraints

| constraint | source |
|---|---|
| The output text's bounded scrolling uses the follow-the-bottom list the Events pane introduced, **extracted first** into a shared component named `TailScroll`. | LO lines 208-209 |
| It follows new content while scrolled to the bottom; scrolled up it stays put and shows `Jump ↓`. | LO lines 209-210 |
| `tests/ui/` covers `TailScroll` (follow, Jump). | LO line 249 |
| `ui/components/**` must not import `core/stores`; components are prop-driven. | `docs/architecture.md` line 15; `tests/architecture/test_layers.py:145` |
| No second copy of shared visual patterns: no `font.family:`, `bordered: true`, `CursorSurface {`, `radius: height / 2`, modal `Qt.rgba(0, 0, 0, 0.55)` outside their allowed files. Text is `ThemedText`, the button is `ActionButton`. | `tests/architecture/test_layers.py:246-280` (`GUARDS`) |
| Glyphs come from `runGlyphs.js`; no private-use code points in QML. `Jump ↓` is U+2193, a plain arrow, allowed. | `tests/architecture/test_icon_glyphs.py`; `docs/architecture.md` line 175 |
| Shared components are listed in `docs/architecture.md` §"Shared components" (line 119 on), reuse before a second copy. | `docs/architecture.md` line 119 |
| Header comments and docstrings state the contract only, no narrative. | card |
| Verification: `bash tests/run.sh` green (pytest, then every `tst_*.qml`; a `TypeError`/`ReferenceError`/`Unable to assign`/`is not a function` line fails the run). | card; `tests/run.sh` |

## Behaviour

### B1. `TailScroll`'s interface

`ui/components/TailScroll.qml`, root `Item`, `objectName` default `"tailScroll"`. Props:

| name | type | default | meaning |
|---|---|---|---|
| `theme` | var | `null` | the owner's Theme; `palette` falls back to TailScroll's own `T.Theme` (same pattern as `EventsPane.qml:28-38`) |
| `model` | var | `[]` | the rows, handed to an inner `ListView` |
| `rowDelegate` | Component | `null` | the row delegate (the name matches `FilterableList.rowDelegate`, `ui/components/FilterableList.qml:16`) |
| `maxHeight` | real | `Style.space(320)` | the list's height cap |
| `listName` | string | `"tailList"` | `objectName` of the inner ListView |
| `jumpName` | string | `"tailJump"` | `objectName` of the Jump `ActionButton` |
| `following` | bool, read-only | `true` | true while the list is at its bottom (B3) |

Function `jump()`: B5. TailScroll emits no signals.

A delegate sizes itself; TailScroll does not set a delegate's width. A delegate reads the list's
width through the `ListView.view` attached property.

### B2. Layout

- The list is exactly as tall as its content up to `maxHeight`, then `maxHeight`, and clips; it
  is the full width of TailScroll.
- The Jump line sits under the list, `Style.space(6)` below it (the spacing `EventsPane`'s column
  uses today, `EventsPane.qml:113`), the button at the line's right edge, text `Jump ↓`.
- `implicitHeight` is the list's height, plus the spacing and the Jump line while Jump is shown.
- With no rows (the inner list's `count` is 0) TailScroll is not visible, so an owner's `Column`
  gives it neither height nor spacing, and the list and Jump both report `visible: false`.
  An owner does not bind TailScroll's `visible`.

### B3. Following

- `following` starts `true`. An empty list and a list whose content fits count as at the bottom.
- "At the bottom" is: content fits, or `contentY` within 1 px of `originY + contentHeight - height`
  (today's `_atBottom`, `EventsPane.qml:72-76`).
- A user scroll (any `contentY` change TailScroll did not make itself — wheel, drag, an owner or
  test setting `contentY`, `positionViewAtEnd()`) sets `following` to whether the list is at its
  bottom afterwards.
- While `following`, a change of the list's content height (rows added, a row growing or rewrapping)
  or of its height (`maxHeight`, width changes) keeps the list at its bottom. The moves TailScroll
  makes itself never change `following`.

### B4. A new `model`

Assigning `model` (a new array, even with the same rows) replaces the list's rows. A new model would
put a ListView back at its top, so:

- while `following`, the list goes to its bottom;
- otherwise it keeps its `contentY`, clamped into `[originY, originY + contentHeight - height]`
  (so a list that now fits sits at its top);
- afterwards `following` is recomputed as at-the-bottom (B3). A model change never sets a
  scrolled-up, still-scrollable list back to following; a model that leaves nothing to scroll does.

This is today's `_showRows` (`EventsPane.qml:86-98`), triggered by a `model` change and once on
completion.

### B5. Jump

- Jump is shown exactly while the list is visible, its content is taller than its height, and
  `following` is false.
- A click on Jump, or a call to `jump()`, puts the list at its bottom and sets `following`; Jump
  then hides and `implicitHeight` shrinks by the Jump line.

### B6. Wheel hand-off

The list flicks vertically with `Flickable.StopAtBounds`: a wheel in its middle scrolls only the
list; a wheel down at its bottom, up at its top, or over a list that fits reaches the enclosing
Flickable. No custom wheel code (today's `EventsPane.qml:190-193`).

### B7. Lifetime

Destroying TailScroll (or its owner) while a new model is arriving prints no warning.

### B8. `EventsPane` on `TailScroll`

- `EventsPane`'s `ListView` and Jump `Item` (`EventsPane.qml:184-277`) are replaced by one
  `TailScroll` in the same place in its column, with `theme: pane.palette`,
  `model: pane.shownRows`, `maxHeight: pane.maxListHeight`, `listName: "eventsList"`,
  `jumpName: "eventsJump"`, and the existing `ListRow` delegate as `rowDelegate` (its `width`
  now from `ListView.view.width`; every other line of it unchanged).
- `following` stays a read-only property of `EventsPane`, now reading TailScroll's.
- `_atBottom`, `_toBottom`, `_showRows`, `_jump`, `_following`, `_relayout`,
  `onShownRowsChanged` and the `_showRows()` call in `Component.onCompleted` leave `EventsPane`.
- The header comment's `maxListHeight` and `following` lines keep stating the same contract.
- Every observable of `EventsPane` stays: the objectNames `eventsList`, `eventsJump`, `eventsRow<seq>`
  and the row parts; `pane.following`; `pane.implicitHeight` (Jump line included while shown);
  Jump's position under the list at the right edge; list visibility; wheel hand-off; the filter
  semantics (a filter change keeps following, keeps a scrolled-up list's clamped `contentY`, and an
  empty filtered list counts as at its bottom).

### B9. Documentation

- `docs/architecture.md` §"Shared components" (line 119 on): add a `TailScroll` entry (bounded,
  self-scrolling list of `model` rows through `rowDelegate`, capped at `maxHeight`; follows new
  content while at its bottom; scrolled up it keeps its position and shows **Jump ↓**; a wheel at
  its ends reaches the enclosing Flickable; `listName` / `jumpName` name the inner list and button;
  hidden with no rows).
- `docs/architecture.md` line 154 (`EventsPane`): say its list is a `TailScroll`; the behaviour
  text stays.
- Line 175 (glyph sources) does not change.

## Tests

### New: `tests/ui/components/tst_tail_scroll.qml`

**Tier: QML component test (`qmltestrunner`, run by `tests/run.sh`, offscreen).** TailScroll's
contract is scroll geometry, visibility and mouse/wheel input on a live `ListView`; only a
rendered QML scene exercises it, and every other component in `ui/components` is tested this way.

Pattern from `tests/ui/components/tst_events_pane.qml`: `TestCase` `when: windowShown`,
`import "../../helpers/find.js" as H`, `import "../../../ui/components" as UI`,
`import "../../../ui/theme" as T`, a `T.Theme { id: testTheme }`, a `make(props)` that creates
from a `Component` with `createTemporaryObject` and assigns props **after** creation (a property map
turns a JS array into a list), then `wait(30)`. The test's delegate is a fixed-height `Rectangle`
(e.g. 20 px, `objectName: "tailRow" + modelData`, `width: ListView.view.width`) over models of
integers `rows(n) = [1..n]`, so content heights are exact. Helpers `atBottom(list)` (as
`tst_events_pane.qml:490-492`) and `scrolledUp()` (50 rows, `maxHeight` 200, `contentY = originY +
300`). The wheel tests use a page `Flickable` around a `Column` holding a spacer, the TailScroll
and a tall spacer, as `tst_events_pane.qml:27-51` does.

| # | test | proves |
|---|---|---|
| T1 | a short model: list height equals `contentHeight` (< `maxHeight`), `clip` true, `following` true, Jump hidden; a long model: height equals `maxHeight`, content taller | B2, B5 |
| T2 | a long model opens at its bottom with `following` true | B3, B4 |
| T3 | **follows at the bottom**: from the bottom, assign `rows(52)` → count 52, at the bottom, `following` true | B4 |
| T4 | **stays put and shows Jump when scrolled up**: `scrolledUp()` → `following` false, Jump visible with text `Jump ↓`, below the list (`mapToItem(tail).y >= list.y + list.height`), right edge at its line's right edge; assign `rows(52)` → `contentY` unchanged, `following` false, Jump still visible | B3, B4, B5 |
| T5 | **Jump returns and resumes following**: from `scrolledUp()`, record `implicitHeight`, click Jump → at the bottom, `following` true, Jump hidden, `implicitHeight` smaller; assign `rows(55)` → at the bottom | B5, B3 |
| T6 | `jump()` called directly does the same as the click | B5 |
| T7 | scrolling back to the bottom by hand (`positionViewAtEnd()`) sets `following`, and the next model is followed | B3 |
| T8 | scrolled up, a model that now fits (`rows(3)`) puts `contentY` at `originY` and sets `following` true; Jump hidden | B4, B5 |
| T9 | while following, raising the delegate height (a `rowHeight` property on the test's root bound by the delegate) keeps the list at its bottom; while following, a smaller `maxHeight` keeps it at its bottom | B3 |
| T10 | an empty model (`[]`), and a long model then `[]`: TailScroll not visible, list and Jump `visible` false, `following` true; then `rows(50)` again → at the bottom | B2, B3, B4 |
| T11 | objectNames: defaults `tailList` / `tailJump` resolve with `H.find`; with `listName: "x"`, `jumpName: "y"` those resolve and the defaults do not | B1 |
| T12 | wheel hand-off in the page Flickable: a wheel up from the bottom scrolls the list (`following` false, page `contentY` 0); at the bottom a wheel down scrolls the page; over a list that fits a wheel scrolls the page | B6, B3 |
| T13 | in a `Column` with `spacing` and a sibling below, an empty TailScroll adds no height: the column's `implicitHeight` equals that of the same column without it | B2 |
| T14 | `failOnWarning(/TypeError\|ReferenceError\|is not a function/)`: assign a new model and destroy TailScroll in the same turn, `wait(50)` | B7 |

### `EventsPane` tests: two assertions re-expressed, the rest unchanged

**Tier: QML component and screen tests (same runner).** `tests/ui/screens/tst_run_detail_screen.qml`
is **not edited**. `tests/ui/components/tst_events_pane.qml` is edited in exactly two lines and
nothing else; both files pass. They already pin B8: objectNames `eventsList`/`eventsJump`,
`pane.following`, `pane.implicitHeight` with and without Jump, Jump's position, wheel hand-off,
filter semantics, rewrap, detail rows, garbage `rows`.

**Amendment (decided at plan validation).** Two assertions compare a sibling's `y` in the pane's
`Column` against `listOf(pane).y`: `test_earlier_line_shows_the_dropped_count` ("above the list")
and `test_error_state_shows_the_headline_and_keeps_the_rows` ("the error sits above the rows").
Once the `ListView` is TailScroll's child its `y` is 0 inside TailScroll, so those comparisons can
never hold, whatever the extraction shape that keeps a separate `TailScroll` item. They are
re-expressed to compare both items' positions mapped into the pane
(`item.mapToItem(pane, 0, 0).y`), which states the same claim ("above the list") in one coordinate
system. The edit lands before the refactor and is seen green against today's `EventsPane`, so it
cannot hide a regression. No other line of either file changes.

### Architecture tests

**Tier: pytest (`tests/architecture`).** `test_layers.py` (no store import from `ui/components`;
the `GUARDS`) and `test_icon_glyphs.py` pass with `TailScroll.qml` added; no allow-list entry is
added for it.

## Out of scope

- The live output pane, its labels (`⟳ live`, `waiting for output`, `ended · <status>`,
  `snapshot <age> ago`), the end line, the step row, Refresh only for a snapshot: sibling cards of
  story 4 (LO lines 194-213, 249-250).
- Any content type other than a `model` + `rowDelegate` list (e.g. a single `Text` body): the output
  pane's card decides how its text becomes rows.
- `RunOutputStore`, `core/domain/logStream.js`, backend helpers: other stories.
- Any change to `EventsPane`'s props, rows, chips, error block, `… N earlier events`, `ListStatus`
  line, or its tests beyond the two re-expressed position assertions.
- Restyling the Jump button or changing its text.

## Hand-off to the planner

Files:

- Create `ui/components/TailScroll.qml` (B1-B7).
- Create `tests/ui/components/tst_tail_scroll.qml` (T1-T14), written first and seen failing (the
  component does not exist).
- Modify `tests/ui/components/tst_events_pane.qml`: the two position assertions only (see the
  amendment above), green before the refactor.
- Modify `ui/components/EventsPane.qml` (B8), checked by `tst_events_pane.qml` and the unchanged
  `tst_run_detail_screen.qml`.
- Modify `docs/architecture.md` (B9).

Suggested tasks (TDD, one commit each): (1) TailScroll with T1-T14; (2) EventsPane on TailScroll,
running `bash tests/run.sh events_pane` and `bash tests/run.sh run_detail` before and after, plus
the docs paragraph. Final check: `bash tests/run.sh` green, `tst_run_detail_screen.qml` has no
diff, and `tst_events_pane.qml`'s diff is exactly the two re-expressed assertions.

Notes for the implementer:

- Assign the inner ListView's `model` imperatively in TailScroll's model handler (not by binding),
  inside the "this move is mine" guard, as `_showRows` does today; a bound model would reset the
  list before the handler can restore `contentY`.
- `rowDelegate` is created in the owner's context, so `EventsPane`'s delegate keeps reaching
  `pane._isFailure`, `pane._tint` and the rest.
- TailScroll's root `visible` and the list's `visible` are driven by the list's `count`, not by the
  `model`'s `length` (a model may be any ListView model).
