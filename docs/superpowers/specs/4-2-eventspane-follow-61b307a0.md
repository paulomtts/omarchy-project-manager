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
