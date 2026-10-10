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

---

# 4.1 `TailScroll`: the shared follow-the-bottom view — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `EventsPane`'s bounded, self-scrolling, follow-the-bottom list with its `Jump ↓` line into a shared `ui/components/TailScroll.qml`, prove it with `tests/ui/components/tst_tail_scroll.qml`, and put `EventsPane` on it with its own tests passing (two position assertions in `tst_events_pane.qml` re-expressed in pane coordinates, nothing else edited).

**Architecture:** `TailScroll` is a prop-driven `Item` holding a `Column` of an inner `ListView` (model assigned imperatively inside a "this move is mine" guard, delegate = the owner's `rowDelegate`) and a Jump line with an `ActionButton`. It carries today's `_atBottom` / `_toBottom` / `_showRows` / `_jump` logic verbatim, renamed onto `tail`. `EventsPane` drops that logic and its `ListView` + Jump `Item`, and mounts one `TailScroll` in their place; its delegate reads the list width through `ListView.view`.

**Tech Stack:** QML (Qt 6 Quick), `qs.Commons` (`Style`), QtTest via `qmltestrunner` (offscreen), pytest architecture tests, `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-1-tailscroll-the-6672f312.md` (prepended above).

## Global Constraints

- `ui/components/**` must not import `core/stores`; components are prop-driven (`tests/architecture/test_layers.py:145`).
- No `font.family:`, `bordered: true`, `CursorSurface {`, `radius: height / 2`, `Qt.rgba(0, 0, 0, 0.55)` in `TailScroll.qml`; text is `ThemedText`, the button is `ActionButton`. No allow-list entry is added to `GUARDS`.
- No private-use code points in QML; `Jump ↓` is U+2193 and stays exactly `Jump ↓`.
- Header comments and docstrings state the contract only, no narrative.
- `TailScroll`: root `Item`, `objectName` default `"tailScroll"`; props `theme` (var, `null`), `model` (var, `[]`), `rowDelegate` (Component, `null`), `maxHeight` (real, `Style.space(320)`), `listName` (string, `"tailList"`), `jumpName` (string, `"tailJump"`), `following` (read-only bool, `true`); function `jump()`; no signals.
- Jump line spacing under the list: `Style.space(6)`.
- `tests/ui/screens/tst_run_detail_screen.qml` is not edited. `tests/ui/components/tst_events_pane.qml` is edited in exactly two lines — the "above the list" assertion in `test_earlier_line_shows_the_dropped_count` and the "the error sits above the rows" assertion in `test_error_state_shows_the_headline_and_keeps_the_rows` — re-expressed with `mapToItem(<pane>, 0, 0).y` on both sides (spec amendment: the list's own `y` is 0 inside TailScroll). **Note:** the spec's final check is relative to this branch's starting commit `965ba2b`, not `main` (this branch already differs from `main` in both files, which came in with earlier stories): `git diff --exit-code 965ba2b -- tests/ui/screens/tst_run_detail_screen.qml` prints nothing, and `git diff --numstat 965ba2b -- tests/ui/components/tst_events_pane.qml` prints `2	2	tests/ui/components/tst_events_pane.qml`.
- Verification: `bash tests/run.sh` green (pytest, then every `tst_*.qml`; a `TypeError` / `ReferenceError` / `Unable to assign` / `is not a function` line fails the run).

## Review Focus

1. **`maxHeight` raised past the content while scrolled up** — a person enlarging the pane expects every row to show (`contentY` at `originY`), `following` true, Jump hidden; without a clamp the list could keep a stale `contentY` with the rows pushed out of view. Pinned by `test_a_taller_cap_that_fits_the_rows_shows_them_all_and_follows` (Task 1), and the `onHeightChanged` clamp in Task 1's implementation.
2. **A model that is not a JS array** (an integer count model) — the spec says visibility is driven by `count`, "a model may be any ListView model"; a person expects it shown, followed to its bottom. Pinned by `test_an_integer_model_is_shown_and_followed` (Task 1).
3. **The same rows as a new array while scrolled up** — a store re-emitting identical rows must not move a reader's position. Pinned by `test_the_same_rows_as_a_new_array_keep_a_scrolled_up_list_put` (Task 1).
4. **Scrolled to the very top of a scrollable list, then a new model** — a ListView resets to its top on a new model, so the test must prove TailScroll keeps the top *because it is the clamped `contentY`* and keeps `following` false. Pinned by `test_a_list_scrolled_to_its_top_stays_there_through_a_new_model` (Task 1).
5. **No owner theme (`theme: null`)** — a person mounting TailScroll without a theme expects the Jump button drawn in the fallback palette with no warnings. Pinned by `test_without_a_theme_jump_uses_the_fallback_palette` (Task 1).

## File Structure

- Create `ui/components/TailScroll.qml` — the bounded follow-the-bottom list and its Jump line (B1-B7).
- Create `tests/ui/components/tst_tail_scroll.qml` — T1-T14 plus the five Review Focus tests.
- Modify `ui/components/EventsPane.qml` — replace the inline list, Jump line and scroll logic with one `TailScroll` (B8).
- Modify `docs/architecture.md` — the `TailScroll` entry and the `EventsPane` sentence (B9).

## How to run the tests

`bash tests/run.sh <substring>` runs the whole pytest suite first (a few seconds), then only the `tst_*.qml` files whose path contains `<substring>`. Its output lists `== tests/...` per file, then `FAIL!` lines with `Loc:` and a `Totals:` line. A file that fails to load prints a QML error and no `Totals` with passes. Exit status 0 means green.

---

### Task 1: `TailScroll` and its component test

**Files:**
- Create: `tests/ui/components/tst_tail_scroll.qml`
- Create: `ui/components/TailScroll.qml`

**Interfaces:**
- Consumes: `ActionButton` (`ui/components/ActionButton.qml`: props `theme`, `text`, signal `clicked`), `T.Theme` (`ui/theme/Theme.qml`), `Style.space(n)` from `qs.Commons`, `H.find(item, objectName)` from `tests/helpers/find.js`.
- Produces: `UI.TailScroll` with props `theme: var`, `model: var`, `rowDelegate: Component`, `maxHeight: real`, `listName: string`, `jumpName: string`, read-only `following: bool`, function `jump()`. Inner `ListView` objectName = `listName`; Jump `ActionButton` objectName = `jumpName`, text `Jump ↓`, its parent is the Jump line `Item` whose width is TailScroll's width. A delegate reads the list width as `ListView.view.width`. Task 2 relies on exactly these names.

- [ ] **Step 1: Write the failing test**

Create `tests/ui/components/tst_tail_scroll.qml` with exactly this content:

```qml
// tests/ui/components/tst_tail_scroll.qml
// ui/components/TailScroll.qml: a bounded list of model rows that scrolls
// itself, follows its bottom while there, keeps its place and shows Jump ↓
// while scrolled up, hands a wheel to the page at its ends, and is hidden
// with no rows.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "TailScroll"
  when: windowShown
  visible: true
  width: 700; height: 600

  // The test delegate's height; init() puts it back to 20.
  property real rowHeight: 20

  T.Theme { id: testTheme }

  // A row exactly tc.rowHeight tall, so content heights are exact.
  Component {
    id: rowC

    Rectangle {
      required property var modelData
      objectName: "tailRow" + modelData
      width: ListView.view ? ListView.view.width : 0
      height: tc.rowHeight
      color: "#444444"
    }
  }

  Component { id: tailC; UI.TailScroll { width: 400 } }

  // A page around the TailScroll: a vertical Flickable over a Column taller
  // than the Flickable, as tst_events_pane.qml builds it.
  Component {
    id: stackC

    Flickable {
      width: 400; height: 400
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      property alias tail: tailScroll

      Column {
        id: column
        width: parent.width

        Item { width: parent.width; height: 100 }
        UI.TailScroll { id: tailScroll; width: parent.width; theme: testTheme; rowDelegate: rowC; maxHeight: 200 }
        Item { width: parent.width; height: 800 }
      }
    }
  }

  // An owner's Column with spacing and a sibling below the TailScroll.
  Component {
    id: columnC

    Column {
      spacing: 10
      property alias tail: inColumn

      Item { width: 300; height: 40 }
      UI.TailScroll { id: inColumn; width: 300; theme: testTheme; rowDelegate: rowC }
      Item { width: 300; height: 30 }
    }
  }

  // The same Column without the TailScroll.
  Component {
    id: bareColumnC

    Column {
      spacing: 10

      Item { width: 300; height: 40 }
      Item { width: 300; height: 30 }
    }
  }

  function init() { tc.rowHeight = 20 }

  // A TailScroll in testTheme drawing rowC, unless props say otherwise. Props
  // are assigned after creation, in order: createTemporaryObject's property
  // map turns a JS array into a list, and an owner binds real arrays.
  function make(props) {
    var p = { theme: testTheme, rowDelegate: rowC }
    for (var k in props) p[k] = props[k]
    var tail = createTemporaryObject(tailC, tc)
    for (var key in p) tail[key] = p[key]
    wait(30)
    return tail
  }

  function rows(n) {
    var out = []
    for (var i = 1; i <= n; i++) out.push(i)
    return out
  }

  function listOf(tail) { return H.find(tail, "tailList") }
  function jumpOf(tail) { return H.find(tail, "tailJump") }

  function atBottom(list) {
    return Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // 50 rows (1000 px) capped at 200, scrolled 300 px below the top: away from the bottom.
  function scrolledUp() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    list.contentY = list.originY + 300
    wait(30)
    return tail
  }

  function wheelOverList(stack, yDelta) {
    var list = listOf(stack.tail)
    var p = list.mapToItem(stack, list.width / 2, list.height / 2)
    mouseWheel(stack, p.x, p.y, 0, yDelta, Qt.NoButton, Qt.NoModifier)
  }

  // ---- layout --------------------------------------------------------------

  // T1
  function test_the_list_height_is_bounded() {
    var short = make({ maxHeight: 300, model: rows(3) })
    var list = listOf(short)
    compare(list.contentHeight, 60)
    compare(list.height, list.contentHeight, "a short list is exactly as tall as its rows")
    verify(list.height < short.maxHeight)
    compare(list.clip, true)
    compare(list.width, short.width, "the list is TailScroll's full width")
    compare(short.following, true)
    compare(jumpOf(short).visible, false)

    var long = make({ maxHeight: 300, model: rows(100) })
    var longList = listOf(long)
    compare(longList.height, 300, "a long list is capped")
    verify(longList.contentHeight > longList.height, "and scrolls inside itself")
    compare(long.implicitHeight, 300, "following, no Jump line in the height")
  }

  // ---- following -----------------------------------------------------------

  // T2
  function test_a_long_model_opens_at_its_bottom() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "the list opens at its bottom")
    compare(tail.following, true)
  }

  // T3
  function test_a_new_model_at_the_bottom_is_followed() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    tryVerify(function () { return atBottom(list) }, 1000)
    tail.model = rows(52)
    wait(50)
    compare(list.count, 52)
    tryVerify(function () { return atBottom(list) }, 1000, "the newest row is in view")
    compare(tail.following, true)
  }

  // T4
  function test_scrolled_up_it_stays_put_and_shows_jump() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var jump = jumpOf(tail)
    compare(tail.following, false)
    compare(jump.visible, true)
    compare(jump.text, "Jump ↓")
    verify(jump.mapToItem(tail, 0, 0).y >= list.y + list.height, "Jump sits below the list")
    compare(Math.round(jump.x + jump.width), Math.round(jump.parent.width), "at the line's right edge")
    compare(Math.round(jump.parent.width), Math.round(tail.width), "the line is TailScroll's width")
    var before = list.contentY
    tail.model = rows(52)
    wait(50)
    compare(list.count, 52)
    compare(list.contentY, before, "a new model does not move a scrolled-up list")
    compare(tail.following, false)
    compare(jump.visible, true, "a new model does not hide Jump")
  }

  // T5
  function test_jump_returns_to_the_bottom_and_resumes_following() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var jump = jumpOf(tail)
    var withJump = tail.implicitHeight
    verify(withJump > list.height, "the Jump line is in the height")
    mouseClick(jump)
    tryVerify(function () { return atBottom(list) }, 1000, "the bottom is in view")
    compare(tail.following, true)
    compare(jump.visible, false)
    tryVerify(function () { return tail.implicitHeight < withJump }, 1000, "the Jump line leaves the height")
    compare(tail.implicitHeight, list.height)
    tail.model = rows(55)
    wait(50)
    compare(list.count, 55)
    tryVerify(function () { return atBottom(list) }, 1000, "the next model is followed")
  }

  // T6
  function test_calling_jump_does_what_the_click_does() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var withJump = tail.implicitHeight
    tail.jump()
    wait(30)
    verify(atBottom(list), "at the bottom")
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
    verify(tail.implicitHeight < withJump, "the Jump line leaves the height")
    tail.model = rows(55)
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the next model is followed")
  }

  // T7
  function test_scrolling_back_to_the_bottom_resumes_following() {
    var tail = scrolledUp()
    var list = listOf(tail)
    compare(tail.following, false)
    list.positionViewAtEnd()
    wait(30)
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
    tail.model = rows(52)
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the next model is followed")
  }

  // T8
  function test_a_model_that_now_fits_sits_at_its_top_and_follows() {
    var tail = scrolledUp()
    var list = listOf(tail)
    tail.model = rows(3)
    wait(50)
    compare(list.count, 3)
    compare(list.contentY, list.originY, "a list that now fits sits at its top")
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
  }

  // T9
  function test_taller_rows_and_a_smaller_cap_keep_a_following_list_at_its_bottom() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    tryVerify(function () { return atBottom(list) }, 1000)
    var tall = list.contentHeight
    tc.rowHeight = 30
    tryVerify(function () { return list.contentHeight > tall }, 1000, "the rows grow")
    tryVerify(function () { return atBottom(list) }, 1000, "the list stays at its bottom")
    compare(tail.following, true)
    tail.maxHeight = 100
    wait(30)
    compare(list.height, 100)
    tryVerify(function () { return atBottom(list) }, 1000, "a smaller cap keeps it at its bottom")
    compare(tail.following, true)
  }

  // T10
  function test_with_no_rows_it_is_hidden_and_following() {
    var empty = make({ maxHeight: 200, model: [] })
    compare(empty.visible, false)
    compare(listOf(empty).visible, false)
    compare(jumpOf(empty).visible, false)
    compare(empty.following, true)

    var tail = scrolledUp()
    var list = listOf(tail)
    compare(tail.following, false)
    tail.model = []
    wait(50)
    compare(list.count, 0)
    compare(tail.visible, false)
    compare(list.visible, false)
    compare(jumpOf(tail).visible, false)
    compare(tail.following, true, "an empty list is at its bottom")
    tail.model = rows(50)
    wait(50)
    compare(tail.visible, true)
    tryVerify(function () { return atBottom(list) }, 1000, "the rows come back at the bottom")
  }

  // T11
  function test_object_names() {
    var named = make({ model: rows(3) })
    compare(named.objectName, "tailScroll")
    verify(H.find(named, "tailList") !== null, "the default list name")
    verify(H.find(named, "tailJump") !== null, "the default Jump name")
    verify(H.find(named, "tailRow1") !== null, "rows come from rowDelegate")

    var renamed = make({ listName: "x", jumpName: "y", model: rows(3) })
    verify(H.find(renamed, "x") !== null, "listName names the list")
    verify(H.find(renamed, "y") !== null, "jumpName names the Jump button")
    compare(H.find(renamed, "tailList"), null)
    compare(H.find(renamed, "tailJump"), null)
  }

  // ---- wheel hand-off (T12) ------------------------------------------------

  function test_a_wheel_up_from_the_bottom_scrolls_the_list() {
    var stack = createTemporaryObject(stackC, tc)
    stack.tail.model = rows(50)
    wait(50)
    var list = listOf(stack.tail)
    verify(atBottom(list), "the list opens at its bottom")
    wheelOverList(stack, 120)
    tryVerify(function () { return !stack.tail.following }, 1000, "the wheel leaves the bottom")
    compare(stack.contentY, 0, "the page does not move")
  }

  function test_a_wheel_down_at_the_bottom_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.tail.model = rows(50)
    wait(50)
    var list = listOf(stack.tail)
    list.positionViewAtEnd()
    wait(30)
    verify(list.atYEnd, "the list starts at its bottom")
    var before = list.contentY
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
    compare(list.contentY, before, "the list stays at its bottom")
  }

  function test_a_wheel_over_a_list_that_fits_scrolls_the_page() {
    var stack = createTemporaryObject(stackC, tc)
    stack.tail.model = rows(3)
    wait(50)
    var list = listOf(stack.tail)
    verify(list.contentHeight <= list.height, "the rows fit")
    wheelOverList(stack, -120)
    tryVerify(function () { return stack.contentY > 0 }, 1000, "the page scrolls down")
  }

  // T13
  function test_an_empty_tail_scroll_takes_no_room_in_a_column() {
    var column = createTemporaryObject(columnC, tc)
    var bare = createTemporaryObject(bareColumnC, tc)
    wait(30)
    compare(bare.implicitHeight, 80)
    compare(column.implicitHeight, bare.implicitHeight, "neither height nor spacing")
    column.tail.model = rows(3)
    wait(30)
    compare(column.implicitHeight, 80 + 10 + 60, "with rows it takes its height and one spacing")
  }

  // T14
  function test_destroying_it_while_a_model_arrives_warns_nothing() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var tail = make({ maxHeight: 200, model: rows(50) })
    tail.model = rows(52)
    tail.destroy()
    wait(50)
  }

  // ---- Review Focus --------------------------------------------------------

  // Review Focus 1
  function test_a_taller_cap_that_fits_the_rows_shows_them_all_and_follows() {
    var tail = scrolledUp()
    var list = listOf(tail)
    compare(tail.following, false)
    tail.maxHeight = 2000
    wait(30)
    compare(list.height, list.contentHeight, "the rows fit")
    compare(list.contentY, list.originY, "every row is in view")
    compare(tail.following, true)
    compare(jumpOf(tail).visible, false)
  }

  // Review Focus 2
  function test_an_integer_model_is_shown_and_followed() {
    var tail = make({ maxHeight: 200, model: 30 })
    var list = listOf(tail)
    compare(list.count, 30)
    compare(tail.visible, true)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "at its bottom")
    compare(tail.following, true)
  }

  // Review Focus 3
  function test_the_same_rows_as_a_new_array_keep_a_scrolled_up_list_put() {
    var tail = scrolledUp()
    var list = listOf(tail)
    var before = list.contentY
    tail.model = rows(50)
    wait(50)
    compare(list.count, 50)
    compare(list.contentY, before)
    compare(tail.following, false)
    compare(jumpOf(tail).visible, true)
  }

  // Review Focus 4
  function test_a_list_scrolled_to_its_top_stays_there_through_a_new_model() {
    var tail = make({ maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    list.positionViewAtBeginning()
    wait(30)
    compare(list.contentY, list.originY)
    compare(tail.following, false, "the top of a list that scrolls is not its bottom")
    tail.model = rows(52)
    wait(50)
    compare(list.count, 52)
    compare(list.contentY, list.originY, "still at its top")
    compare(tail.following, false)
    compare(jumpOf(tail).visible, true)
  }

  // Review Focus 5
  function test_without_a_theme_jump_uses_the_fallback_palette() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var tail = make({ theme: null, maxHeight: 200, model: rows(50) })
    var list = listOf(tail)
    list.contentY = list.originY + 300
    wait(30)
    verify(tail.palette !== null && tail.palette !== undefined, "the fallback palette")
    compare(jumpOf(tail).visible, true)
    verify(jumpOf(tail).theme === tail.palette, "Jump draws in it")
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh tail_scroll`
Expected: pytest passes, then `== tests/ui/components/tst_tail_scroll.qml` fails to load with an error naming `TailScroll` (e.g. `TailScroll is not a type`); exit status non-zero.

- [ ] **Step 3: Write the implementation**

Create `ui/components/TailScroll.qml` with exactly this content:

```qml
import QtQuick
import qs.Commons
import "../theme" as T

// A bounded list that scrolls itself and follows its bottom. Presentation only.
//   model: the rows, any ListView model. rowDelegate draws one row and sizes
//     itself; the list's width is ListView.view.width.
//   maxHeight: the list's height cap; past it the list scrolls itself and a
//     wheel at its ends reaches the enclosing Flickable.
//   listName / jumpName: objectNames of the inner ListView and Jump button.
//   following (read-only): true while the list is at its bottom (its rows fit,
//     or contentY is within 1 px of it). While true, new or taller rows, a new
//     model and a new height keep the list at its bottom; otherwise a new model
//     or height keeps contentY within the new bounds. A scroll sets it to
//     whether the list is at its bottom. While false and the list can scroll,
//     "Jump ↓" under the list, or jump(), puts the list at its bottom and sets it.
//   With no rows it is not visible and takes no room in a Column.
Item {
  id: tail
  objectName: "tailScroll"

  // The owner's Theme, or none: `palette` then falls back to TailScroll's own.
  property var theme: null
  property var model: []
  property Component rowDelegate: null
  property real maxHeight: Style.space(320)
  property string listName: "tailList"
  property string jumpName: "tailJump"

  readonly property var palette: tail.theme || tailTheme
  readonly property bool following: tail._following
  property bool _following: true
  property bool _relayout: false

  // True when the list's rows fit or its contentY is within 1 px of its bottom.
  function _atBottom() {
    return list.contentHeight <= list.height
      || Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // y within the list's scroll bounds; a list that fits gets its top.
  function _clamped(y) {
    return Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
  }

  // Puts the list at its bottom; contentY moves made here are not a user scroll.
  function _toBottom() {
    tail._relayout = true
    list.forceLayout()
    list.positionViewAtEnd()
    tail._relayout = false
  }

  // Hands model to the list. A new model puts a ListView back at its top, so
  // a following list goes to its bottom and any other keeps its contentY,
  // within its new bounds.
  function _showRows() {
    tail._relayout = true
    var y = list.contentY
    list.model = tail.model
    list.forceLayout()
    if (tail._following) list.positionViewAtEnd()
    else list.contentY = tail._clamped(y)
    tail._relayout = false
    tail._following = tail._atBottom()
  }

  // Puts the list at its bottom and sets following.
  function jump() {
    tail._toBottom()
    tail._following = true
  }

  visible: list.count > 0
  implicitHeight: column.implicitHeight
  onModelChanged: tail._showRows()
  Component.onCompleted: tail._showRows()

  Column {
    id: column
    width: tail.width
    spacing: Style.space(6)

    ListView {
      id: list
      objectName: tail.listName
      visible: list.count > 0
      width: parent.width
      height: Math.min(list.contentHeight, tail.maxHeight)
      clip: true
      orientation: ListView.Vertical
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds
      delegate: tail.rowDelegate
      onContentYChanged: if (!tail._relayout) tail._following = tail._atBottom()
      onContentHeightChanged: if (tail._following && !tail._relayout) tail._toBottom()
      // A height that is not followed keeps contentY in bounds; that move is a scroll.
      onHeightChanged: {
        if (tail._relayout) return
        if (tail._following) tail._toBottom()
        else list.contentY = tail._clamped(list.contentY)
      }
    }

    Item {
      width: parent.width
      height: jumpButton.height
      visible: list.visible && list.contentHeight > list.height && !tail._following

      ActionButton {
        id: jumpButton
        objectName: tail.jumpName
        anchors.right: parent.right
        theme: tail.palette
        text: "Jump ↓"
        onClicked: tail.jump()
      }
    }
  }

  T.Theme { id: tailTheme }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/run.sh tail_scroll`
Expected: pytest passes (including `tests/architecture/test_layers.py` and `test_icon_glyphs.py` with the new file), `== tests/ui/components/tst_tail_scroll.qml` prints `Totals: N passed, 0 failed, 0 skipped` with no `FAIL!` and no `TypeError` / `ReferenceError` / `Unable to assign` / `is not a function` lines; exit status 0.

If `test_a_taller_cap_that_fits_the_rows_shows_them_all_and_follows` fails on `list.contentY`, the `onHeightChanged` clamp is not running: check that the `else` branch is present and is not inside the `_relayout` guard. If `test_an_integer_model_is_shown_and_followed` prints `Required property modelData was not initialized`, keep the test and change only the test delegate's `required property var modelData` to `property var modelData: index + 1` — no change to `TailScroll.qml`.

- [ ] **Step 5: Commit**

```bash
git add ui/components/TailScroll.qml tests/ui/components/tst_tail_scroll.qml
git commit -m "feat(components): TailScroll, a bounded list that follows its bottom and offers Jump ↓"
```

---

### Task 2: `EventsPane` on `TailScroll`, and the docs

**Files:**
- Modify: `ui/components/EventsPane.qml` (lines 38-44 properties, 72-103 scroll functions, 107-108 handlers, 184-277 list and Jump line)
- Modify: `docs/architecture.md` (the §"Shared components" paragraph starting line 119, the `EventsPane` entry around line 154)
- Modify: `tests/ui/components/tst_events_pane.qml:301` and `:355` (the two position assertions only)
- Test (unchanged, must pass): `tests/ui/screens/tst_run_detail_screen.qml`

**Interfaces:**
- Consumes: `UI.TailScroll` from Task 1 — props `theme`, `model`, `rowDelegate`, `maxHeight`, `listName`, `jumpName`, read-only `following`; the delegate reads `ListView.view.width`.
- Produces: `EventsPane` with unchanged props, signals and objectNames (`eventsList`, `eventsJump`, `eventsRow<seq>`, row parts), read-only `following` now `tail.following`.

This task is a refactor under existing tests: the RED step is proving the existing tests are green before the change (so a later failure is the refactor's), the GREEN step is the same tests green after.

Two assertions in `tst_events_pane.qml` compare a sibling's `y` in the pane's `Column` with `listOf(pane).y`. After this task the `ListView` is a child of `TailScroll`, where its `y` is 0, so those two comparisons could never hold. Step 1 re-expresses them in the pane's coordinate system *before* the refactor and proves them green against today's `EventsPane`, so they keep guarding the same claim ("above the list") across the change.

- [ ] **Step 1: Re-express the two position assertions in pane coordinates**

In `tests/ui/components/tst_events_pane.qml`, `test_earlier_line_shows_the_dropped_count` (line 301), replace the exact line

```qml
    verify(H.find(many, "eventsEarlier").y < listOf(many).y, "above the list")
```

with

```qml
    verify(H.find(many, "eventsEarlier").mapToItem(many, 0, 0).y < listOf(many).mapToItem(many, 0, 0).y, "above the list")
```

In `test_error_state_shows_the_headline_and_keeps_the_rows` (line 355), replace the exact line

```qml
    verify(block.y < listOf(pane).y, "the error sits above the rows")
```

with

```qml
    verify(block.mapToItem(pane, 0, 0).y < listOf(pane).mapToItem(pane, 0, 0).y, "the error sits above the rows")
```

Change nothing else in the file.

Check: `git diff --numstat -- tests/ui/components/tst_events_pane.qml`
Expected: `2	2	tests/ui/components/tst_events_pane.qml`

- [ ] **Step 2: Run the EventsPane tests before the refactor**

Run: `bash tests/run.sh events_pane && bash tests/run.sh run_detail`
Expected: both exit 0; `tst_events_pane.qml` and `tst_run_detail_screen.qml` print `Totals: N passed, 0 failed` (the re-expressed assertions pass against today's `EventsPane`). Note both N values.

- [ ] **Step 3: Replace `ui/components/EventsPane.qml`**

Write `ui/components/EventsPane.qml` with exactly this content (the header comment, props, helpers, chips, error block, earlier line and ListStatus are unchanged; the scroll logic and the `ListView` + Jump `Item` become one `TailScroll`; the delegate's `width` reads `ListView.view`):

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
//   following (read-only): true while the list is at its bottom. New rows keep
//     a following list at its bottom; otherwise the list keeps its contentY.
//     A scroll sets it to whether the list is at its bottom; a filter change
//     keeps it. While false and the list can scroll, "Jump ↓" under the list
//     puts it at its bottom and sets it.
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
  readonly property bool following: tail.following

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

  implicitHeight: column.implicitHeight
  onStatusChanged: if (pane.status !== "error") pane._errorExpanded = false

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

    TailScroll {
      id: tail
      width: parent.width
      theme: pane.palette
      model: pane.shownRows
      maxHeight: pane.maxListHeight
      listName: "eventsList"
      jumpName: "eventsJump"

      rowDelegate: ListRow {
        id: row
        required property var modelData
        readonly property bool failure: pane._isFailure(row.modelData)
        readonly property bool namesAttempt: pane._namesAttempt(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: row.ListView.view ? row.ListView.view.width : 0
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

Notes on this file:
- `rowDelegate: ListRow { ... }` is QML's inline-component shorthand for a `Component` property: the `ListRow` is wrapped in a `Component` created in `EventsPane`'s context, so `pane._isFailure`, `pane._tint`, `pane.palette` and `pane.attemptRequested` still resolve.
- `row.ListView.view` is the attached property on the delegate's root; it is guarded because a delegate being torn down can see a null view, and an unguarded read would print a `TypeError` that `test_destroying_the_pane_while_rows_arrive_warns_nothing` fails on.
- The `TailScroll` binds neither `visible` nor `height`: it hides itself with no rows, and its height defaults to its `implicitHeight`.

- [ ] **Step 4: Run the EventsPane tests after the change**

Run: `bash tests/run.sh events_pane && bash tests/run.sh run_detail`
Expected: both exit 0 with the same `Totals: N passed, 0 failed` counts as Step 2, and no `TypeError` / `ReferenceError` / `Unable to assign` / `is not a function` lines.

If `test_jump_shows_while_scrolled_up_and_stays_through_new_rows` fails on "at the line's right edge", check that the Jump `ActionButton`'s parent is TailScroll's Jump line `Item` (width `parent.width`), not the column. If a row test fails with rows of width 0, check that the delegate reads `row.ListView.view.width`.

- [ ] **Step 5: Update `docs/architecture.md`**

In the §"Shared components" paragraph, replace the exact text

```
`ListStatus` (loading/error/empty), `FilterableList`, `TextAreaBox`,
```

with

```
`ListStatus` (loading/error/empty), `FilterableList`,
`TailScroll` (a bounded, self-scrolling list of `model` rows drawn by `rowDelegate`, capped at `maxHeight`: while at its bottom (`following`, read-only) it follows new content; scrolled up it keeps its position and shows **Jump ↓**, which returns it to the bottom (also `jump()`); a wheel at its ends reaches the enclosing Flickable; `listName` / `jumpName` name the inner list and the Jump button; with no rows it is hidden and takes no room), `TextAreaBox`,
```

In the `EventsPane` entry, replace the exact text

```
The pane scrolls itself: its list scrolls past `maxListHeight`, and a wheel at the list's ends reaches the enclosing Flickable.
```

with

```
The pane scrolls itself: its list is a `TailScroll`, which scrolls past `maxListHeight`, and a wheel at the list's ends reaches the enclosing Flickable.
```

Leave the glyph-sources paragraph (`ui/components/runGlyphs.js` is the one glyph source …) unchanged.

Check: `grep -n 'its list is a .TailScroll.' docs/architecture.md` and `grep -n '^.TailScroll. (a bounded' docs/architecture.md`
Expected: each prints exactly one line.

- [ ] **Step 6: Run the whole suite and the test-diff check**

Run: `bash tests/run.sh`
Expected: exit 0; pytest all passed; every `== tests/...tst_*.qml` prints `Totals: N passed, 0 failed`; no `FAIL!`, `TypeError`, `ReferenceError`, `Unable to assign` or `is not a function` line.

Run: `git diff --exit-code 965ba2b -- tests/ui/screens/tst_run_detail_screen.qml`
Expected: no output, exit 0.

Run: `git diff --numstat 965ba2b -- tests/ui/components/tst_events_pane.qml`
Expected: exactly `2	2	tests/ui/components/tst_events_pane.qml` (the two re-expressed assertions, nothing else).

Run: `grep -nE '_atBottom|_toBottom|_showRows|_jump|_following|_relayout|onShownRowsChanged' ui/components/EventsPane.qml`
Expected: no output (exit 1) — all of the scroll logic left `EventsPane`.

- [ ] **Step 7: Commit**

```bash
git add tests/ui/components/tst_events_pane.qml ui/components/EventsPane.qml docs/architecture.md
git commit -m "refactor(components): EventsPane's list is a TailScroll"
```
<!-- task-pipeline: validated -->
