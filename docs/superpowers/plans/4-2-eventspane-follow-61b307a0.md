# 4.2 EventsPane: follow the newest row and Jump (card 61b307a0) — design

Narrows `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` ("the parent
spec") to one behaviour of one presentation component. Parent story 55a2dc57 "Events UI".
Builds on 4.1 (card 184f6742, `docs/superpowers/specs/4-1-eventspane-rows-184f6742.md`),
which built `ui/components/EventsPane.qml` with the newest row at the bottom but no
auto-scroll and no Jump control (4.1 spec, "Out of scope", 4.2 bullet).

## Scope

In scope:

- `ui/components/EventsPane.qml`: a follow state; the list follows new rows while it is
  scrolled to its bottom; a `Jump ↓` button when it is not; the follow state kept across a
  filter change. The file's header comment gains the contract for these (contract only).
- `tests/ui/components/tst_events_pane.qml`: new tests, written first (TDD); the header
  comment names follow/Jump; existing tests adjusted only where they assumed the list
  starts at its top (see "Changes to existing tests").

Out of scope:

- A "Load earlier" control or `--before-seq` paging. The parent spec draws
  `[Load earlier] [Jump ↓]` on one line (parent spec line 135) but the store has no
  backward paging (4.1 spec, "Out of scope", last bullet). Jump is placed alone on that line.
- 4.3: wiring the pane into `ui/screens/RunDetailScreen.qml`, the tabs, the `e` key,
  binding to `app.runs`, handling `attemptRequested`.
- 4.4: `docs/architecture.md` and README.
- Keeping the visible rows steady when the store's 500-row cap drops the oldest rows
  while the list is scrolled up (parent spec line 161). The list keeps its `contentY`, as
  it does today.
- Keyboard access to Jump beyond what `ActionButton` already gives.
- Any change to `RunStore.qml`, `core/domain/*.js`, `ActionButton`, `ListRow`, `ChipRow`,
  `ListStatus`, `ThemedText`, or the wheel hand-off mechanism 4.1 built.

## Inherited constraints

- "Newest at the bottom; the list follows new rows while it is scrolled to the bottom,
  and a `Jump ↓` appears when it is not" (parent spec lines 143-144).
- The list has its own bounded height and its own scrolling; a wheel at its ends hands
  over to the page (parent spec lines 141-143). This must keep working (4.1's four wheel
  tests stay green).
- Testing: `tests/ui/` covers "follow/jump" (parent spec line 178).
- The bottom line carries `[Jump ↓]` at its right (parent spec line 135).
- Layering: a component receives props and never imports `core/stores` (parent spec
  lines 69-70; `docs/architecture.md`; `tests/architecture/test_layers.py`).
- No duplicated components (`tests/architecture/test_layers.py` GUARDS): the button is an
  `ActionButton` (the one bordered button), its text and any label are `ThemedText` /
  `ActionButton.text`; no `bordered: true`, `font.family:` or `CursorSurface {` in the pane.
- No private-use code points (`tests/architecture/test_icon_glyphs.py`). `↓` is U+2193, a
  BMP arrow, not private use; it is written literally in the text `Jump ↓`.
- Comments and docstrings state the contract only, no narrative (card).
- `bash tests/run.sh` green; it fails on qmltestrunner output matching
  `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`.

## Interface

No new public props or signals. Additions:

| objectName | what |
|---|---|
| `eventsJump` | the `Jump ↓` `ActionButton`, `theme: pane.palette` |

A read-only property is exposed so tests and the owner can read the state:

```
readonly property bool following   // true while the list is at its bottom (see below)
```

(The implementation may back it with a private writable `_following`; the public name is
`following`.)

## Observable behaviour

Terms: the list's **bottom** is `contentY == originY + contentHeight - height` (within
1 px); a list whose content fits (`contentHeight <= height`) or that has no rows is always at
its bottom. The list **can scroll** when `contentHeight > height`.

### Follow state

- `following` is `true` when the pane is created.
- A scroll of the list that is not the pane's own re-layout — a wheel, a drag, or the owner
  or a test setting `contentY` / calling `positionViewAt*` — sets `following` to whether the
  list is now at its bottom. Scrolling up away from the bottom clears it; scrolling back
  down to the bottom by hand sets it again ("following resumes once at the bottom again").
- The pane's own re-layout on a new `shownRows` (the model swap that moves a `ListView` to
  its top, and the restore that follows) never reads as the user leaving the bottom.

### New rows (`shownRows` changes)

- `following` true: after the new rows are laid out, the list is at its bottom, so the
  newest row is in view. This holds for the first rows shown (a pane created with, or
  first given, more rows than fit opens at its bottom), for appended rows, and for a list
  that grows from fitting to capped.
- `following` false: the list keeps its `contentY`, clamped to its new bounds (4.1's
  behaviour, `test_new_rows_keep_the_list_where_it_was`). It does not move toward the new
  rows.
- After the re-layout, `following` is whether the list is at its bottom. So a scrolled-up
  list whose clamp lands it at its bottom (the rows shrank, or now fit) follows again;
  otherwise the state is unchanged.

### Filter change

A filter change reaches the list the same way (`filter` → `shownRows`), so the rules above
apply and the follow state carries over:

- following before the change → the filtered list is shown at its bottom, still following;
- scrolled up before the change, and the new list still reaches past the old `contentY`
  → the list keeps its `contentY`, not following, Jump still shown.

The filter never resets the state to following.

### Jump ↓

- `eventsJump` is visible exactly when the list is visible (`shownRows` non-empty), can
  scroll, and `following` is false.
- It sits on its own line below the list, at the line's right edge; the pane's
  `implicitHeight` includes that line only while Jump is visible.
- Text: `Jump ↓`.
- A click puts the list at its bottom (the newest row in view), sets `following` true and
  hides Jump. Rows appended after that are followed.
- A click does not emit `filterRequested` or `attemptRequested` and does not move the
  enclosing page.

### Unchanged

- The wheel hand-off at the list's ends, the bounded height, row order, filter chips,
  states and error block are 4.1's and behave as before.

### Error paths (no warning, no throw)

- `rows` empty, `null` or garbage (4.1's list): no list, no Jump, `following` true.
- All rows filtered out while scrolled up: no list, no Jump; when rows show again they
  appear at the bottom (an empty list is at its bottom, so `following` became true).
- Rows whose delegates differ in height (a detail line under some rows): following still
  lands on the true bottom (the last row's bottom edge at the list's bottom edge), not on
  an estimate. `ListView.positionViewAtEnd()` after `forceLayout()` is the expected means.
- Destroying the pane while rows are arriving: no `TypeError`.

## Tests

All in `tests/ui/components/tst_events_pane.qml` — tier: QML UI component test, because
the deliverable is presentation behaviour of one QML component driven by props and user
scrolling; there is no domain logic (JS unit tier) and no store or backend (integration
tiers belong to 4.3 and the store cards). Use the file's helpers: `make(props)`,
`eventRow`, `manyRows(n)`, `listOf(pane)`, `stackC`, `wheelOverList`, `H.find`, and
`tryVerify` / `tryCompare` after a rows change or a wheel (layout and Flickable motion are
asynchronous). `atBottom(list)` may be added as a helper: `Math.abs(list.contentY -
(list.originY + list.contentHeight - list.height)) <= 1`. Panes use `maxListHeight: 200`
with `manyRows(50)` so the list scrolls.

New tests:

1. `test_a_long_list_opens_at_its_newest_row` — `make({ rows: manyRows(50), maxListHeight:
   200 })`: list at its bottom, `following` true, `eventsJump` not visible.
2. `test_appending_while_at_the_bottom_follows` — from (1), `rows = manyRows(52)`: count
   52, list at its bottom, `following` true, Jump not visible.
3. `test_appending_while_scrolled_up_does_not_move_and_shows_jump` — 50 rows, set
   `contentY = originY + 300`: `following` false, Jump visible with text `Jump ↓`;
   `rows = manyRows(52)`: `contentY` unchanged, Jump still visible.
4. `test_jump_returns_to_the_bottom_and_resumes_following` — scrolled up as in (3),
   `mouseClick(eventsJump)`: list at its bottom, `following` true, Jump hidden;
   then `rows = manyRows(55)`: list at its bottom (the append is followed).
5. `test_scrolling_back_to_the_bottom_resumes_following` — scrolled up, then
   `list.positionViewAtEnd()`: `following` true, Jump hidden; an append follows.
6. `test_a_wheel_up_from_the_bottom_stops_following` — in `stackC`, 50 rows (opens at the
   bottom), `wheelOverList(stack, 120)`: `following` becomes false, Jump visible, the page
   does not move.
7. `test_a_filter_change_keeps_following` — rows mixing failure and non-failure rows so
   that both `All` and `Phases` scroll; at the bottom, set `filter = "Phases"`: list at
   its bottom, `following` true; append rows: followed.
8. `test_a_filter_change_keeps_a_scrolled_up_list_scrolled_up` — same rows, `contentY =
   originY + 100` (below the Phases list's bottom too), set `filter = "Phases"`:
   `following` false, `contentY` unchanged, Jump visible; back to `All`: still not
   following.
9. `test_a_list_that_fits_shows_no_jump` — `manyRows(3)`: Jump not visible, `following`
   true; `rows = manyRows(4)`: still no Jump, `following` true.
10. `test_rows_with_detail_lines_follow_to_the_true_bottom` — 50 rows, every 3rd with a
    multi-line `detail`, append: the last row's delegate bottom (mapped into the list)
    equals the list's height within 1 px.

Changes to existing tests (new default: a long list opens at its bottom):

- `test_a_wheel_up_at_the_list_top_scrolls_the_page`: position the list at its top
  (`list.positionViewAtBeginning()`, `wait`) before asserting `atYBeginning`.
- `test_a_wheel_down_at_the_list_bottom_scrolls_the_page`,
  `test_a_wheel_in_the_middle_of_the_list_scrolls_only_the_list` and
  `test_new_rows_keep_the_list_where_it_was` already position the list explicitly and
  must pass unchanged.

Architecture tier (existing, unchanged): `tests/architecture/test_layers.py` and
`test_icon_glyphs.py` guard the button and the arrow; no new architecture test.

## Acceptance

- Only `ui/components/EventsPane.qml` and `tests/ui/components/tst_events_pane.qml`
  change (besides this spec and its plan).
- `bash tests/run.sh` is green, with no rejected warnings in `tst_events_pane.qml`'s output.

---

# 4.2 EventsPane: follow the newest row and Jump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ui/components/EventsPane.qml`'s list follow the newest row while it is scrolled to its bottom, keep a scrolled-up list where it is, keep that state across a filter change, and add a `Jump ↓` button that returns the list to its bottom.

**Architecture:** The pane holds a private `_following` (exposed as read-only `following`). `_showRows()` already swaps the model and restores `contentY`. It now calls `positionViewAtEnd()` instead when following, and recomputes `_following` afterwards. A `_relayout` flag marks the pane's own scrolls so the list's `onContentYChanged` reads only outside scrolls (wheel, drag, `contentY`, `positionViewAt*`) as the user moving. While following, a change in the list's `contentHeight` or `height` (delegates sizing late, the list growing to its cap) re-pins it to the bottom. Jump is an `ActionButton` inside an `Item` line under the list. The `Item` is visible only while the list shows, can scroll and is not following, so the `Column` counts the line's height only then.

**Tech Stack:** Qt 6.11.2 QML (QtQuick, QtTest via `/usr/lib/qt6/bin/qmltestrunner`), the repo's `qs.Commons` / `qs.Ui` stubs under `tests/stubs`, pytest for the architecture tests.

**Spec:** `docs/superpowers/specs/4-2-eventspane-follow-61b307a0.md` (reproduced above).

## Global Constraints

- Only `ui/components/EventsPane.qml` and `tests/ui/components/tst_events_pane.qml` change (spec, Acceptance).
- Do not change `RunStore.qml`, `core/domain/*.js`, `ActionButton`, `ListRow`, `ChipRow`, `ListStatus`, `ThemedText`, or the wheel hand-off. The hand-off has no code of its own: it is the `ListView`'s `boundsBehavior: Flickable.StopAtBounds`, so leave that line as it is.
- No new public props or signals. Two names are added: the read-only `following` property and the objectName `eventsJump`.
- A component never imports `core/stores`.
- The button is an `ActionButton` with `theme: pane.palette`. Never write `bordered: true`, `font.family:` or `CursorSurface {` in the pane (`tests/architecture/test_layers.py` GUARDS).
- The button text is exactly `Jump ↓`, with `↓` (U+2193) written literally. No private-use code points (`tests/architecture/test_icon_glyphs.py`).
- Comments and docstrings state the contract only, with no narrative.
- `bash tests/run.sh` stays green. It fails on any qmltestrunner output matching `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`. Never use `anchors` on an item placed directly in a `Column`. The Jump `ActionButton` anchors inside a plain `Item`, which is allowed.
- Bottom means `contentY == originY + contentHeight - height` within 1 px. A list whose content fits, or that has no rows, is always at its bottom.

## Review Focus

1. **Delegates that size themselves after the list has been positioned** (a wrapped `detail` line, fonts loading late). A following list must land on the true last row, not on the `ListView`'s estimated `contentHeight`. → Task 1, `test_rows_with_detail_lines_follow_to_the_true_bottom`. The `onContentHeightChanged` re-pin is what makes `test_a_long_list_opens_at_its_newest_row` pass; this was checked in a scratch run.
2. **The pane's own model swap read as the user scrolling.** Replacing the model moves the list to its top, which would clear `following` on every live event. → Task 1, `test_appending_while_at_the_bottom_follows` and `test_a_filter_change_keeps_following`, both guarded by the `_relayout` flag.
3. **Every row filtered out while scrolled up, then shown again.** The rows must come back at the bottom, with no stale Jump. → Task 1, `test_rows_filtered_out_while_scrolled_up_come_back_at_the_bottom`; Task 2, the `Failures` / `All` steps of `test_jump_shows_exactly_while_a_list_that_scrolls_is_not_following`.
4. **The pane destroyed while a rows change is being handled** (leaving Run detail while events stream). No `TypeError`. → Task 1, `test_destroying_the_pane_while_rows_arrive_warns_nothing`, using `failOnWarning`. This test is a guard and passes before and after the change.
5. **A touchpad (pixel-delta) scroll up from the bottom.** QtTest cannot synthesize a pixel delta (`docs/architecture.md`, wheel notes), so no automated test pins it. The plan reads every `contentY` change that is not the pane's own as a user scroll, whatever caused it, so a touchpad goes through the same path as the mouse wheel in `test_a_wheel_up_from_the_bottom_stops_following`. Check it by hand once 4.3 wires the pane into Run detail.

---

## File Structure

- Modify `ui/components/EventsPane.qml`: the follow state and its handlers (Task 1), then the Jump line (Task 2). It stays one presentation component with one responsibility.
- Modify `tests/ui/components/tst_events_pane.qml`: a "following the newest row" section (Task 1), a "Jump" section (Task 2), and one existing test adjusted (Task 1).

**Running the one test file** from the worktree root. This is the same runner and import path `tests/run.sh` uses, filtered to its failure, summary and rejected-warning lines:

```bash
QT_QPA_PLATFORM=offscreen timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"
```

The `Totals` count includes the two implicit `initTestCase` / `cleanupTestCase` passes. Before this plan, the file reports `Totals: 25 passed, 0 failed`.

**Testing gotchas the tests already handle:**
- Layout and `Flickable` motion are asynchronous. After a rows change or a wheel, use `wait(50)` and then `tryVerify` / `compare`, as the existing tests do.
- `make(props)` assigns props after creation. Keep it that way: `createTemporaryObject`'s property map turns a JS array into a list that `Array.isArray` rejects.
- `H.find` returns `null` for a missing objectName. Before Task 2, `jumpOf(pane).visible` therefore throws `Cannot read property 'visible' of null`, which is the expected RED.

---

### Task 1: The list follows the newest row while it is at its bottom

**Files:**
- Modify: `ui/components/EventsPane.qml:14-16` (header), `:36` (properties), `:64-71` (`_showRows`), `:161` (list handlers)
- Test: `tests/ui/components/tst_events_pane.qml:1-6` (header), `:446-457` (`test_a_wheel_up_at_the_list_top_scrolls_the_page`), end of file (new section)

**Interfaces:**
- Consumes: 4.1's `_showRows()` (called from `onShownRowsChanged` and `Component.onCompleted`), the `ListView` `id: list`, the test helpers `make`, `eventRow`, `manyRows`, `rowOf`, `listOf`, `stackC`, `wheelOverList`.
- Produces:
  - `readonly property bool following` on the pane (public).
  - Private: `property bool _following: true`, `property bool _relayout: false`, `function _atBottom()` → `bool`, `function _toBottom()` → nothing (puts the list at its bottom with `_relayout` set).
  - Test helpers used by Task 2: `atBottom(list)` → `bool`, `scrolledUp()` → a pane of `manyRows(50)`, `maxListHeight: 200`, with its list at `originY + 300`.

- [ ] **Step 1: Write the failing tests**

Edit 1 of 3 in `tests/ui/components/tst_events_pane.qml` (header). Replace this exact text:

```qml
// to the page at its ends, and attemptRequested for a row naming an attempt.
import QtQuick
```

with:

```qml
// to the page at its ends, and attemptRequested for a row naming an attempt.
// The list follows the newest row while it is at its bottom.
import QtQuick
```

Edit 2 of 3. A long list now opens at its bottom, so this test puts the list at its top itself. Replace this exact text:

```qml
    stack.contentY = 50
    wait(30)
    var list = listOf(stack.pane)
    verify(list.atYBeginning, "the list starts at its top")
```

with:

```qml
    stack.contentY = 50
    var list = listOf(stack.pane)
    list.positionViewAtBeginning()
    wait(30)
    verify(list.atYBeginning, "the list starts at its top")
```

Edit 3 of 3. Insert the following just before the `TestCase`'s closing `}` (the last line of the file), after `test_new_rows_keep_the_list_where_it_was`:

```qml

  // ---- following the newest row --------------------------------------------

  function atBottom(list) {
    return Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // A pane of 50 rows whose list is scrolled 300 px below its top, away from its bottom.
  function scrolledUp() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    list.contentY = list.originY + 300
    wait(30)
    return pane
  }

  // n rows where every 4th is a story row: Phases drops those, and still scrolls.
  function storyAndPhaseRows(n) {
    var rows = []
    for (var i = 1; i <= n; i++)
      rows.push(eventRow(i, i % 4 === 0 ? { level: "story", card: "", phase: "", attempt: 0 } : {}))
    return rows
  }

  function test_a_long_list_opens_at_its_newest_row() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "the list opens at its bottom")
    compare(pane.following, true)
  }

  function test_appending_while_at_the_bottom_follows() {
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    var list = listOf(pane)
    pane.rows = manyRows(52)
    wait(50)
    compare(list.count, 52)
    tryVerify(function () { return atBottom(list) }, 1000, "the newest row is in view")
    compare(pane.following, true)
  }

  function test_scrolling_up_stops_following_and_new_rows_do_not_move_the_list() {
    var pane = scrolledUp()
    var list = listOf(pane)
    compare(pane.following, false)
    var before = list.contentY
    pane.rows = manyRows(52)
    wait(50)
    compare(list.count, 52)
    compare(list.contentY, before, "the list does not move toward the new rows")
    compare(pane.following, false)
  }

  function test_scrolling_back_to_the_bottom_resumes_following() {
    var pane = scrolledUp()
    var list = listOf(pane)
    compare(pane.following, false)
    list.positionViewAtEnd()
    wait(30)
    compare(pane.following, true)
    pane.rows = manyRows(52)
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the append is followed")
  }

  function test_a_wheel_up_from_the_bottom_stops_following() {
    var stack = createTemporaryObject(stackC, tc)
    stack.pane.rows = manyRows(50)
    wait(50)
    verify(atBottom(listOf(stack.pane)), "the list opens at its bottom")
    wheelOverList(stack, 120)
    tryVerify(function () { return !stack.pane.following }, 1000, "the wheel leaves the bottom")
    compare(stack.contentY, 0, "the page does not move")
  }

  function test_a_filter_change_keeps_following() {
    var pane = make({ rows: storyAndPhaseRows(60), maxListHeight: 200 })
    var list = listOf(pane)
    tryVerify(function () { return atBottom(list) }, 1000)
    pane.filter = "Phases"
    wait(50)
    compare(list.count, 45)
    verify(list.contentHeight > list.height, "the Phases list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "the filtered list is at its bottom")
    compare(pane.following, true)
    pane.rows = storyAndPhaseRows(63)
    wait(50)
    compare(list.count, 48)
    tryVerify(function () { return atBottom(list) }, 1000, "the append is followed")
  }

  function test_a_filter_change_keeps_a_scrolled_up_list_scrolled_up() {
    var pane = make({ rows: storyAndPhaseRows(60), maxListHeight: 200 })
    var list = listOf(pane)
    list.contentY = list.originY + 100
    wait(30)
    compare(pane.following, false)
    var before = list.contentY
    pane.filter = "Phases"
    wait(50)
    compare(list.count, 45)
    compare(pane.following, false)
    compare(list.contentY, before, "the list keeps its contentY")
    pane.filter = "All"
    wait(50)
    compare(pane.following, false, "the filter never resets to following")
  }

  function test_rows_filtered_out_while_scrolled_up_come_back_at_the_bottom() {
    var pane = scrolledUp()
    var list = listOf(pane)
    pane.filter = "Failures"
    wait(50)
    compare(list.visible, false)
    compare(pane.following, true, "an empty list is at its bottom")
    pane.filter = "All"
    wait(50)
    tryVerify(function () { return atBottom(list) }, 1000, "the rows come back at the bottom")
  }

  function test_rows_with_detail_lines_follow_to_the_true_bottom() {
    function detailed(n) {
      var rows = []
      for (var i = 1; i <= n; i++)
        rows.push(eventRow(i, i % 3 === 0 ? { detail: "line one of a long reason\nline two\nline three" } : {}))
      return rows
    }
    var pane = make({ rows: detailed(50), maxListHeight: 200 })
    var list = listOf(pane)
    pane.rows = detailed(52)
    wait(50)
    tryVerify(function () {
      var last = rowOf(pane, 52)
      return last && Math.abs(last.mapToItem(list, 0, last.height).y - list.height) <= 1
    }, 1000, "the last row's bottom edge is the list's bottom edge")
    compare(pane.following, true)
  }

  function test_destroying_the_pane_while_rows_arrive_warns_nothing() {
    failOnWarning(/TypeError|ReferenceError|is not a function/)
    var pane = make({ rows: manyRows(50), maxListHeight: 200 })
    pane.rows = manyRows(52)
    pane.destroy()
    wait(50)
  }
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"
```

Expected: `Totals: 26 passed, 9 failed`. The nine failures are `test_a_long_list_opens_at_its_newest_row`, `test_appending_while_at_the_bottom_follows`, `test_scrolling_up_stops_following_and_new_rows_do_not_move_the_list`, `test_scrolling_back_to_the_bottom_resumes_following`, `test_a_wheel_up_from_the_bottom_stops_following`, `test_a_filter_change_keeps_following`, `test_a_filter_change_keeps_a_scrolled_up_list_scrolled_up`, `test_rows_filtered_out_while_scrolled_up_come_back_at_the_bottom` and `test_rows_with_detail_lines_follow_to_the_true_bottom`. They fail on `following` being `undefined` or on the list not being at its bottom. `test_destroying_the_pane_while_rows_arrive_warns_nothing` already passes: it is a guard. The adjusted `test_a_wheel_up_at_the_list_top_scrolls_the_page` passes.

- [ ] **Step 3: Implement the follow state**

Edit 1 of 4 in `ui/components/EventsPane.qml` (header contract). Replace this exact text:

```qml
//     a wheel at its ends reaches the enclosing Flickable.
//   filterRequested(filter): a chip was clicked.
```

with:

```qml
//     a wheel at its ends reaches the enclosing Flickable.
//   following (read-only): true while the list is at its bottom. New rows keep
//     a following list at its bottom; otherwise the list keeps its contentY.
//     A scroll sets it to whether the list is at its bottom; a filter change
//     keeps it.
//   filterRequested(filter): a chip was clicked.
```

Edit 2 of 4. Replace this exact text:

```qml
  property bool _errorExpanded: false

  signal filterRequested(string filter)
```

with:

```qml
  property bool _errorExpanded: false
  readonly property bool following: pane._following
  property bool _following: true
  property bool _relayout: false

  signal filterRequested(string filter)
```

Edit 3 of 4. Replace this exact text:

```qml
  // Hands shownRows to the list. A new model puts a ListView back at its top,
  // so the list keeps its scroll position instead, within its new bounds.
  function _showRows() {
    var y = list.contentY
    list.model = pane.shownRows
    list.forceLayout()
    list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
  }
```

with:

```qml
  // True when the list's rows fit or its contentY is within 1 px of its bottom.
  function _atBottom() {
    return list.contentHeight <= list.height
      || Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // Puts the list at its bottom; contentY moves made here are not a user scroll.
  function _toBottom() {
    pane._relayout = true
    list.forceLayout()
    list.positionViewAtEnd()
    pane._relayout = false
  }

  // Hands shownRows to the list. A new model puts a ListView back at its top,
  // so a following list goes to its bottom and any other keeps its scroll
  // position, within its new bounds.
  function _showRows() {
    pane._relayout = true
    var y = list.contentY
    list.model = pane.shownRows
    list.forceLayout()
    if (pane._following) list.positionViewAtEnd()
    else list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
    pane._relayout = false
    pane._following = pane._atBottom()
  }
```

Edit 4 of 4. Replace this exact text:

```qml
      boundsBehavior: Flickable.StopAtBounds

      delegate: ListRow {
```

with:

```qml
      boundsBehavior: Flickable.StopAtBounds
      onContentYChanged: if (!pane._relayout) pane._following = pane._atBottom()
      onContentHeightChanged: if (pane._following && !pane._relayout) pane._toBottom()
      onHeightChanged: if (pane._following && !pane._relayout) pane._toBottom()

      delegate: ListRow {
```

Why both re-pin handlers are needed: `positionViewAtEnd()` positions against the delegates created so far. Delegates that size themselves afterwards change `contentHeight`, and the list's `height` (bound to `Math.min(contentHeight, maxListHeight)`) changes with it. Without the two handlers, `test_a_long_list_opens_at_its_newest_row` and `test_a_filter_change_keeps_following` fail.

- [ ] **Step 4: Run the tests to make sure they pass**

Run:

```bash
QT_QPA_PLATFORM=offscreen timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"
```

Expected: `Totals: 35 passed, 0 failed`, with no other lines. In particular, 4.1's four wheel tests and `test_new_rows_keep_the_list_where_it_was` still pass.

- [ ] **Step 5: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): the list follows the newest row while it is at its bottom"
```

---

### Task 2: Jump ↓ returns a scrolled-up list to its bottom

**Files:**
- Modify: `ui/components/EventsPane.qml` (header contract, a `_jump()` function after `_showRows()`, a Jump line after the `ListView` inside `column`)
- Test: `tests/ui/components/tst_events_pane.qml` (header, end of file: new "Jump" section)

**Interfaces:**
- Consumes: from Task 1, `_following`, `_toBottom()`, `following`, and the test helpers `atBottom(list)` and `scrolledUp()`.
- Produces: an `ActionButton` with `objectName: "eventsJump"` and text `Jump ↓`, and the private `function _jump()`.

- [ ] **Step 1: Write the failing tests**

Edit 1 of 2 in `tests/ui/components/tst_events_pane.qml`. Replace this exact text:

```qml
// The list follows the newest row while it is at its bottom.
```

with:

```qml
// The list follows the newest row while it is at its bottom; Jump ↓ under a
// list that is not following returns it there.
```

Edit 2 of 2. Insert the following just before the `TestCase`'s closing `}` (the last line of the file), after `test_destroying_the_pane_while_rows_arrive_warns_nothing`:

```qml

  // ---- Jump ----------------------------------------------------------------

  function jumpOf(pane) { return H.find(pane, "eventsJump") }

  function test_jump_shows_while_scrolled_up_and_stays_through_new_rows() {
    var pane = scrolledUp()
    var list = listOf(pane)
    var jump = jumpOf(pane)
    compare(jump.visible, true)
    compare(jump.text, "Jump ↓")
    verify(jump.mapToItem(pane, 0, 0).y >= list.y + list.height, "Jump sits below the list")
    compare(Math.round(jump.x + jump.width), Math.round(jump.parent.width), "at the line's right edge")
    pane.rows = manyRows(52)
    wait(50)
    compare(jump.visible, true, "new rows do not hide it")
  }

  function test_jump_returns_to_the_bottom_and_resumes_following() {
    var pane = scrolledUp()
    var list = listOf(pane)
    var jump = jumpOf(pane)
    var withJump = pane.implicitHeight
    mouseClick(jump)
    tryVerify(function () { return atBottom(list) }, 1000, "the newest row is in view")
    compare(pane.following, true)
    compare(jump.visible, false)
    tryVerify(function () { return pane.implicitHeight < withJump }, 1000, "the Jump line is gone from the pane's height")
    compare(filterSpy.count, 0)
    compare(attemptSpy.count, 0)
    pane.rows = manyRows(55)
    wait(50)
    compare(list.count, 55)
    tryVerify(function () { return atBottom(list) }, 1000, "the append is followed")
  }

  function test_jump_shows_exactly_while_a_list_that_scrolls_is_not_following() {
    var stack = createTemporaryObject(stackC, tc)
    var pane = stack.pane
    pane.rows = manyRows(50)
    wait(50)
    var list = listOf(pane)
    compare(jumpOf(pane).visible, false, "hidden at the bottom")
    wheelOverList(stack, 120)
    tryVerify(function () { return !pane.following }, 1000)
    compare(jumpOf(pane).visible, true, "shown once a wheel leaves the bottom")
    compare(stack.contentY, 0, "the page does not move")
    pane.filter = "Phases"
    wait(50)
    compare(jumpOf(pane).visible, true, "a filter change keeps it")
    list.positionViewAtEnd()
    wait(30)
    compare(jumpOf(pane).visible, false, "hidden once scrolled back to the bottom")
    list.contentY = list.originY + 100
    wait(30)
    compare(jumpOf(pane).visible, true)
    pane.filter = "Failures"
    wait(50)
    compare(jumpOf(pane).visible, false, "no list, no Jump")
    pane.filter = "All"
    wait(50)
    compare(jumpOf(pane).visible, false, "the rows come back at the bottom")
  }

  function test_a_list_that_fits_shows_no_jump() {
    var pane = make({ rows: manyRows(3), maxListHeight: 200 })
    compare(jumpOf(pane).visible, false)
    compare(pane.following, true)
    pane.rows = manyRows(4)
    wait(50)
    compare(jumpOf(pane).visible, false)
    compare(pane.following, true)
  }

  function test_empty_or_garbage_rows_show_no_jump_and_follow() {
    var bad = [[], null, "x"]
    for (var i = 0; i < bad.length; i++) {
      var pane = make({ rows: bad[i], maxListHeight: 200 })
      compare(jumpOf(pane).visible, false, JSON.stringify(bad[i]))
      compare(pane.following, true, JSON.stringify(bad[i]))
    }
  }
```

(`manyRows` rows all have level `attempt` and status `done`. `Phases` therefore keeps every row, so the list keeps its `contentY`, and `Failures` keeps none.)

- [ ] **Step 2: Run the tests to make sure they fail**

Run:

```bash
QT_QPA_PLATFORM=offscreen timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"
```

Expected: `Totals: 35 passed, 5 failed`. The five new tests fail on `Cannot read property 'visible' of null`, or on `TypeError: mouseClick requires an Item or Window type` for the click test, because there is no `eventsJump` yet.

- [ ] **Step 3: Implement Jump**

Edit 1 of 3 in `ui/components/EventsPane.qml` (header contract). Replace this exact text:

```qml
//     A scroll sets it to whether the list is at its bottom; a filter change
//     keeps it.
```

with:

```qml
//     A scroll sets it to whether the list is at its bottom; a filter change
//     keeps it. While false and the list can scroll, "Jump ↓" under the list
//     puts it at its bottom and sets it.
```

Edit 2 of 3. Replace this exact text:

```qml
    pane._relayout = false
    pane._following = pane._atBottom()
  }

  implicitHeight: column.implicitHeight
```

with:

```qml
    pane._relayout = false
    pane._following = pane._atBottom()
  }

  function _jump() {
    pane._toBottom()
    pane._following = true
  }

  implicitHeight: column.implicitHeight
```

Edit 3 of 3. The `ListView` is the last child of `column`. Replace this exact text, which is the end of the last row `ThemedText`, the delegate, the `ListView`, `column`, and the pane's own theme:

```qml
          color: pane._tint(row.failure, "dim")
        }
      }
    }
  }

  T.Theme { id: paneTheme }
```

with:

```qml
          color: pane._tint(row.failure, "dim")
        }
      }
    }

    Item {
      width: parent.width
      height: jump.height
      visible: list.visible && list.contentHeight > list.height && !pane._following

      ActionButton {
        id: jump
        objectName: "eventsJump"
        anchors.right: parent.right
        theme: pane.palette
        text: "Jump ↓"
        onClicked: pane._jump()
      }
    }
  }

  T.Theme { id: paneTheme }
```

The `Item` is a child of the `Column`, so it carries no anchors. The `ActionButton` anchors inside the `Item`, which avoids the `anchors on an item` warning. A `Column` skips invisible children, so the pane's `implicitHeight` includes this line only while Jump shows. The button's own `visible` reads `false` while its parent is hidden.

- [ ] **Step 4: Run the tests to make sure they pass**

Run:

```bash
QT_QPA_PLATFORM=offscreen timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/components/tst_events_pane.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function"
```

Expected: `Totals: 40 passed, 0 failed`, with no other lines.

- [ ] **Step 5: Run the whole suite**

Run: `timeout 600 bash tests/run.sh; echo "exit $?"`
Expected: pytest passes (including `tests/architecture/test_layers.py` and `test_icon_glyphs.py`), every `== tests/...qml` block shows `0 failed`, no rejected-warning lines are printed, and the last line is `exit 0`.

- [ ] **Step 6: Commit**

```bash
git add ui/components/EventsPane.qml tests/ui/components/tst_events_pane.qml
git commit -m "feat(events-pane): Jump ↓ returns a scrolled-up list to its bottom"
```
<!-- task-pipeline: validated -->
