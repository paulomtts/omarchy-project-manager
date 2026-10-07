# 2.3 Entry points for story cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, at the screen, keys and whole-panel tiers, that a story card dispatches from its card-detail Dispatch button and from `d` (reached from the board list through its milestone), and reword the one stale contract comment.

**Architecture:** The entry points (`CardDetailScreen.qml` button, `Shortcuts.qml` `handleDispatchKey`, `Panel.qml` `openDispatch`) are already level-free and the story plan/label/retarget are already merged in `runs.js`/`RunStore.qml`/`DispatchDialog.qml`. This plan adds QML tests in three tiers (screen, keys, Panel flow), each checked by a temporary mutation that must turn it red, and changes one comment. No production logic changes.

**Tech Stack:** Qt 6 QML, QtTest (`qmltestrunner`, offscreen), run by `bash tests/run.sh`; helpers in `tests/helpers/find.js` (`H.find(item, objectName)`).

**Spec:** `docs/superpowers/specs/2-3-entry-points-for-c6a09c52.md` (reproduced in full below). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (S7).

## Global Constraints

- Never edit `core/domain/runs.js`, `core/stores/RunStore.qml` or `ui/components/DispatchDialog.qml` (mutation checks touch `runs.js` temporarily and are always reverted with `git checkout --`; never committed).
- Never change the shape of an existing `roots()` fixture; a test needing extra cards applies its own tree via `app.board.applyTreeData(...)`.
- Do not put stories into the board list or change board-list layout or cursor movement.
- Target line strings exactly: `Target   Story "<story title>" (milestone "<milestone title>")` and `Target   Milestone "<title>"` (three spaces after `Target`).
- Offer text exactly: `Dispatch the milestone instead`. Finished refusal exactly: `The card is <status>`. `am` missing caption exactly: `am is not installed or not on PATH`.
- The button keeps `iconText: "▶"`; `tests/architecture` (`test_layers.py`, `test_icon_glyphs.py`) must stay green.
- `docs/architecture.md` and the README are out of scope (card 2.4).
- Verification: `bash tests/run.sh` is green.

## Review Focus

1. A `d` typed on a story's card detail must open the dialog and must not leak into any text field — pinned in Task 3 T6 `(key)` (`searchQuery` stays `""`) and T9 (focus is in `dispatchBase`).
2. A finished story must not launch any helper (no `am` preview against a done card) — pinned in Task 3 T8 (`dispatchDefaultsRunner.current` and `dispatchPreviewRunner.current` stay null).
3. A blocked story (brd status `blocked`, non-empty `blocked_by`) must not be refused up front by the plugin — pinned in Task 1 (`blocked-story` row emits its id), Task 2 T2 and Task 3 T7 (`previewing` before am replies).
4. After retargeting to the milestone, the dialog must stay open on the milestone, not close or fall back to the story — pinned in Task 3 T7 (`dispatchCardId` `m1`, dialog visible, state `previewing`).
5. With `am` missing, `d` on an open story must do nothing — pinned in Task 2 T5 (`am-missing-on-story` row).

---

## Spec (verbatim)

# 2.3 Entry points for story cards — design

Card: `c6a09c52` "2.3 Entry points for story cards" (story `99cd17e4` "Story dispatch UI").
Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (S7).
Blocked by `2b0955bc` (2.2 DispatchDialog: the story label and the blocked-story action),
which is merged into this branch (commits `e38f1e2`, `327b9e1`, `1c9e9c8`).

## Problem

S7 requires that a story can be dispatched from the same two entry points as every other
card: "the Dispatch button in the card detail of a story card, and the `d` key on a story in
the board list, exactly as for the other levels. The dialog target reads
`Story "<title>" (milestone "<title>")`" (S7 §Behaviour (story), lines 42-44). S7 §Testing
line 104-105 asks for `tests/ui/` coverage of "the Dispatch button and `d` key on a story, the
blocked-story inline refusal and its action, a finished story, a claimed story".

The layers under the entry points already do the story work:

- `core/domain/runs.js:905-914` `dispatchPlan`: a depth-1 card is offered as
  `{level: "story", flags: ["--story", id]}`; a card in a finished status is refused at every
  level with `The card is <status>`.
- `core/stores/RunStore.qml:945-993` `openDispatch`, `blockedSuggest`, `retargetToMilestone`.
- `ui/Panel.qml:304-340` `openDispatch(target)` / `launchDispatch(target)` take any card id.
- `ui/Shortcuts.qml:85-97` `handleDispatchKey` and `ui/screens/CardDetailScreen.qml:96-108`
  `cardDispatchButton` pass the card id on for every card, with no level special case.

So the card's deliverable is the entry-point tier proving this end to end, plus correcting
the one stale contract comment at the entry point. The card's premise ("today a story only
suggests its milestone") no longer holds on this branch. No production logic change is
expected. If a test written below fails against the current code, the fix goes in the
entry-point file it exercises (`CardDetailScreen.qml`, `Shortcuts.qml`, `Panel.qml`), and
never in `runs.js`, `RunStore.qml` or `DispatchDialog.qml` (see Out of scope).

## How a story is reached from the board list

The board list (`app.board.boardCards`, `core/stores/BoardStore.qml:139`) lists **root
cards only**: `Board.boardOrder(visibleBoardRoots, statuses)`. `indexTree`
(`core/domain/board.js:12-26`) gives every root depth 0, so a story (depth 1) is never a
board-list row and the cursor can never sit on one. "The `d` key on a story in the board
list" (S7 line 42-43) is therefore realised as this path: from the board list, put the cursor
on the milestone, activate it (card detail of the milestone), activate the story's link (card
detail of the story), then press bare `d` or click Dispatch. This spec fixes that path as
the board-list entry for a story. It does not add stories to the board list. That would be a
board-layout change S7 does not ask for.

## Behaviour

These rules are observable at the entry points and hold for every story card. They are the
same rules that already hold for milestones and subtasks.

1. **Card-detail Dispatch on a story.** The card detail of any story shows `▶ Dispatch`
   (`cardDispatchButton`), enabled while `am` is not missing. A click emits
   `dispatchRequested(<story id>)` and the screen opens nothing itself. This holds whatever
   the story's status (`todo`, `in_progress`, `blocked`, `done`, …) or `blocked_by`. The
   screen never decides by level or status. (S7 lines 42-44; S3 rule kept: "every card has it".)
2. **`d` on an open story.** On the card detail of a story (view mode `entry`), a bare `d`
   asks the panel to open the dispatch on that story (`actions.openDispatch(<story id>)`)
   and returns true. All the existing guards still apply unchanged: modifiers, no project,
   `am` missing, a modal or an open dispatch, and the open dropdown
   (`ui/Shortcuts.qml:79-97`).
3. **An open story through the Panel.** A story that is not finished opens
   `dispatchDialog` on itself. `dispatchCardId` is the story id, the target line reads
   `Target   Story "<story title>" (milestone "<milestone title>")`, the store is
   `previewing` with `dispatchTarget.level === "story"` and flags
   `["--story", <id>]`, and no milestone offer shows (`dispatchSuggest` hidden).
   (S7 lines 42-44.)
4. **A blocked story.** A story with unfinished blocker stories (brd status `blocked`
   and/or a non-empty `blocked_by`) opens exactly as in rule 3. The plugin does not refuse
   it up front, because `am` is the one that refuses. When the preview replies
   `StoryBlockedError`, the dialog shows am's message in `dispatchRefusal`, Start is
   disabled, and **Dispatch the milestone instead** (`dispatchSuggest`) is visible. Clicking
   it retargets the open dialog to the parent milestone: target line
   `Target   Milestone "<title>"`, flags `["--milestone", <milestone id>]`,
   `dispatchCardId` the milestone id. (S7 lines 55-61.)
5. **A finished story (card status terminal).** A story whose own status is `done`,
   `merged`, `canceled` or `archived` opens `dispatchDialog` already `refused`, with
   `dispatchRefusal` reading `The card is <status>`, Start disabled, no milestone offer, and
   no preview or defaults helper launched. The target line still names the story,
   `Target   Story "<title>" (milestone "<title>")`. (S7 lines 65-66: "Cards in terminal
   statuses … are refused with the reason, as at every level".)
6. **A story with nothing left to run.** A story that is not finished but whose preview
   comes back with no levels shows `Nothing left to run`. A claimed story shows am's
   `ClaimedError` message. Both are already pinned by `tests/ui/tst_dispatch_flow.qml:211-232`
   and are not re-tested here, except through the board-list path in T7. (S7 lines 62-64.)
7. **Without am.** While `app.runs.amStatus === "missing"`, the story's Dispatch button is
   disabled with `am is not installed or not on PATH`, and `d` on an open story returns
   false and asks nothing. This is the same as the other levels and is already pinned for a
   milestone (`tst_card_detail_screen.qml:488-500`, `tst_shortcuts.qml` `am-missing` row).
   This spec adds the story row for `d` (T5).

### Contract comment

`ui/screens/CardDetailScreen.qml:94-96` currently says the button on "a story or a finished
card opens a dialog that says why it cannot start (and offers a story's milestone)". That is
no longer the contract. Reword it to state the contract only: every card has the button and
it asks the owner to dispatch that card; without am it is disabled and the caption says why.
Do not mention levels, refusals or the milestone offer: those belong to the owner. The
`ui/Shortcuts.qml` header (lines 3-12) and the `handleDispatchKey` comment (lines 79-84)
already state a level-free contract and stay as they are.

## Error paths

| input | observable result |
|---|---|
| story, status `done`/`merged`/`canceled`/`archived` | dialog opens `refused`, `The card is <status>`, Start disabled, no offer, no helper launched |
| story, preview replies `StoryBlockedError` | `refused`, am's message verbatim, Start disabled, offer visible; the offer retargets to the milestone |
| story, preview replies no levels | `refused`, `Nothing left to run` (existing coverage) |
| story, preview replies `ClaimedError` | `refused`, am's message (existing coverage) |
| `am` missing | button disabled with caption; `d` returns false, nothing asked |
| `d` with a modifier, under a modal or the dropdown, or with no project | unchanged: `d` returns false (existing `test_d_is_left_alone`) |

## Tests

All tests are QML, run by `bash tests/run.sh` (qmltestrunner over a mirrored copy, helpers in
`tests/helpers/find.js`). Write the tests first. Most are expected to pass on their first run
because the entry points are already level-free. For each test that passes at once, confirm it
can fail by temporarily breaking the behaviour it pins and watching it go red. For example,
make `dispatchPlan` refuse depth 1 again, make `cardDispatchButton` skip `depth === 1`, or
make `handleDispatchKey` skip a story. Then revert the break. Never commit the break.

Fixture rule: the existing `roots()` in each file is shared by many tests. Do not change its
shape. A test that needs an extra card (a done story, a blocked story) applies its own tree
through `app.board.applyTreeData(...)` after `make()` / `onBoard()`, or adds a new sibling
that no existing assertion counts. Check each file's existing assertions before adding a
sibling.

### Screen tier — `tests/ui/screens/tst_card_detail_screen.qml`

This tier proves the screen alone: given a story card, it emits the id and decides nothing.
It runs without Panel, so it cannot assert on the dialog.

- **T1** Extend `test_every_card_has_a_dispatch_button_that_asks_the_owner_data`
  (`:463-465`) with two rows: `blocked-story` (a story with brd status `blocked` and a
  `blocked_by` naming another story) and `done-story` (a story with status `done`). Each row
  asserts the existing checks: the button is visible, its text is `Dispatch`, its `iconText`
  is `▶`, it is enabled, the caption is hidden, one click gives `dispatchRequested(<id>)`, and
  `dispatchState` stays `idle`. The existing `story` row (`s1`, which already has
  `blocked_by: ["x1", "ghost"]`) stays as it is. If the rows need cards outside `roots()`, give
  the data row a `tree` the test applies before opening the card.

### Keys tier — `tests/ui/tst_shortcuts.qml`

This tier proves `handleDispatchKey` alone, with `actions.openDispatch` recorded in
`tc.calls`. It isolates the guard and lookup logic from Panel.

- **T2** `test_d_on_an_open_story_asks_for_that_story_data/…`: rows `story` (`s1`,
  `todo`), `blocked-story` (status `blocked`, `blocked_by` another story) and `done-story`
  (status `done`). For each: open the card, bare `d` returns true, and `dispatched()` is
  exactly `dispatch:<id>`. This generalises `test_d_on_a_card_asks_for_that_cards_dispatch`
  (`:715-721`) to the three story kinds. It may replace that test or sit beside it.
- **T3** `test_d_reaches_a_story_from_the_board_list`: `onBoard()`, then cursor on `m1`
  and `navigator.activateCursor()` (card detail of `m1`), then `activateCursor()` again on its
  first link (card detail of `s1`), then bare `d`. Expect true and `dispatched()` equal to
  `dispatch:s1`. Before activating, assert `boardCards` holds no depth-1 card, which pins the
  "board list is roots only" premise above.
- **T4** `test_d_on_the_board_list_never_targets_a_story`: on the board list, `d` with the
  cursor on `m1` gives `dispatch:m1` (the milestone, never its story).
  `test_d_on_the_board_list_asks_for_the_cursor_cards_dispatch` (`:663-669`) already covers
  this; extend it with one assertion that `s1` is not in `boardCards`, instead of adding a
  new test.
- **T5** Add an `am-missing-on-story` row to `test_d_is_left_alone` (`:672-703`): open `s1`,
  set `amStatus` to `missing`, and `d` returns false with nothing dispatched.

### Panel flow tier — `tests/ui/tst_board_flow.qml`

This tier proves the whole path with a real `Panel.qml`: the user starts on the board list,
walks to a story, uses an entry point, and sees the mounted dialog. It is the only tier where
entry point, Panel, RunStore and DispatchDialog meet. Today this file has no dispatch
coverage. Use a new `make()`-style helper local to the dispatch tests, disarmed the way
`tests/ui/tst_dispatch_flow.qml:50-77` disarms helpers: `backendDir` pointing nowhere, the
export, snapshot and settings runners cancelled, and a stored `verify` in `runSettings`.
Fixture: `m1` (todo) holding `s1` (todo, one todo subtask), `s2` (status `blocked`,
`blocked_by: ["s1"]`, one todo subtask) and `s3` (status `done`, one done subtask), plus
`x1` (done milestone). Replies go through `proc.outText` and `proc.exited(0)` as in
`tst_dispatch_flow.qml:80-83`.
On `m1`'s card detail the links are its stories in order, the cursor starting on the first
(`s1`): reach `s2` with `moveCursor(1)` and `s3` with `moveCursor(2)` before `activateCursor()`;
assert `selectedCardId` after each step.

- **T6** `test_a_story_reached_from_the_board_list_dispatches_itself_data/…`, with rows
  `button` and `key`. On the board list, set the cursor on `m1` and activate it. Activate the
  `s1` link. Then either click `cardDispatchButton` or give the panel focus and `keyClick("d")`.
  Expect: `dispatchDialog` is visible, `dispatchCardId` is `s1`, `dispatchTarget` text is
  `Target   Story "<s1 title>" (milestone "<m1 title>")`,
  `app.runs.dispatchTarget.level` is `story`, its flags are `["--story","s1"]`, the state is
  `previewing`, and `dispatchSuggest` is hidden. For the `key` row, also check that no `d`
  was typed into any field (the search query stays `""`).
- **T7** `test_a_blocked_story_from_the_board_list_offers_its_milestone`: reach `s2` the
  same way (button). Answer the defaults lookup. Answer the preview with
  `{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s1"}}`.
  Expect: `dispatchRefusal` reads `Story blocked by s1`, `dispatchStart` is disabled, and
  `dispatchSuggest` is visible with the text `Dispatch the milestone instead`. Click the offer.
  Then expect: `dispatchCardId` is `m1`, the target line is `Target   Milestone "<m1 title>"`,
  the flags are `["--milestone","m1"]`, the state is `previewing`, and the dialog is still
  visible.
- **T8** `test_a_finished_story_from_the_board_list_is_refused_data/…`, with rows `button`
  and `key`. Reach `s3`, then use the entry point. Expect: the dialog is visible, the state is
  `refused`, `dispatchErrorType` is `Target`, `dispatchRefusal` reads `The card is done`,
  `dispatchStart` is disabled, `dispatchSuggest` is hidden, the target line names the story
  (`Target   Story "<s3 title>" (milestone "<m1 title>")`), and
  `app.runs.dispatchDefaultsRunner.current` and `dispatchPreviewRunner.current` launched
  nothing. Check this the way the existing tests detect a launch, or assert the state never
  passed through `previewing`.
- **T9** `test_escape_closes_a_story_dialog_and_leaves_the_story_open`: from T6's
  `key` path, one Escape closes the dialog (`dispatchState` `idle`, dialog hidden) and the
  view stays `entry` on `s1`. This pins that a story's dialog is a modal like any other, on
  the board-list path.

`tests/ui/tst_dispatch_flow.qml` is not required to change. Its existing story tests
(`:141-232`) already cover the card-detail button on `s1` for the open, blocked, empty and
claimed cases. Add a `done-story` case there only if T8 cannot express it in
`tst_board_flow.qml`.

### Architecture tier

`tests/architecture` (`test_layers.py`, `test_icon_glyphs.py`) must stay green. Nothing here
adds a component, an import from a screen into `core/stores`, or a glyph. The button keeps
`iconText: "▶"`.

## Out of scope

- `core/domain/runs.js`, `core/stores/RunStore.qml`, `ui/components/DispatchDialog.qml`:
  the story plan, label, retarget and dialog action are owned by 1.x/2.1/2.2 and already
  merged.
- Backend helpers (`dispatch-preview.py`, `start-run.py`, `viewer-state.py`) and the `am`
  contract tests: milestone 1 of S7.
- `docs/architecture.md` (including the stale story sentence at line 176) and the README:
  owned by sibling card **2.4 Docs: dispatch at every level** (`4c3d419e`).
- Putting stories into the board list, or any change to board-list layout or cursor
  movement.
- Dispatching several stories at once (S7 §Open, line 109).
- The Runs toolbar's `Start run` chip row, which offers roots only (`Panel.qml:318-329`).

## Verification

`bash tests/run.sh` is green: pytest, every QML test, and `tests/architecture`.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `ui/screens/CardDetailScreen.qml:94-96` | Modify (comment only) | The Dispatch button's contract comment: level-free. |
| `tests/ui/screens/tst_card_detail_screen.qml` | Modify | Screen tier: T1 (a blocked story and a done story emit their id). |
| `tests/ui/tst_shortcuts.qml` | Modify | Keys tier: T2, T3, T4, T5 (`d` on stories, the board-list path, `am` missing). |
| `tests/ui/tst_board_flow.qml` | Modify | Panel tier: T6, T7, T8, T9 (the board list → milestone → story → dialog path). |

No production logic changes. `core/domain/runs.js`, `core/stores/RunStore.qml` and
`ui/components/DispatchDialog.qml` must not be edited (spec, Out of scope). If a test fails
against the current code for a reason other than a typo in the test, the fix goes only in
`ui/screens/CardDetailScreen.qml`, `ui/Shortcuts.qml` or `ui/Panel.qml`.

### How to run tests

- One QML file: `bash tests/run.sh <substring of its path>`, e.g.
  `bash tests/run.sh tst_shortcuts`. The script runs pytest first (always), then every QML
  file whose path contains the substring. A failing QML test prints a `FAIL!` line with its
  name and a `Loc:` line; a passing file prints only its `Totals:` line.
- Everything: `bash tests/run.sh` (pytest, every QML test, `tests/architecture`).

### About "RED" in this plan

The spec says the entry points are already level-free, so most new tests are expected to
**pass on their first run**. For those, the RED step is a **mutation check**: temporarily
break the production behaviour the test pins (exact edit given), run, watch the new test
fail, then restore the file with `git checkout -- <file>`. Never commit a break. Before
each commit, `git status` must show only the files listed in that task's commit step.

---

### Task 1: Screen tier — a blocked and a done story emit their id; the contract comment

**Files:**
- Modify: `ui/screens/CardDetailScreen.qml:94-96` (comment only)
- Test: `tests/ui/screens/tst_card_detail_screen.qml` (fixture helper after `roots()` at `:28-34`; data rows at `:463-465`; test body at `:467-485`)

**Interfaces:**
- Consumes: `CardDetailScreen.dispatchRequested(id)` signal, the `cardDispatchButton` (`UI.ActionButton`, `text`, `iconText`, `enabled`) and `cardDispatchMissing` objects — all existing.
- Produces: `storyTree()` helper local to `tst_card_detail_screen.qml` (nothing used by other tasks).

- [ ] **Step 1: Add the story fixture**

In `tests/ui/screens/tst_card_detail_screen.qml`, directly after the closing `}` of
`function roots()` (line 34), add:

```qml
  // roots() plus two more stories under m1: s2 (brd status blocked, blocked
  // by s1) and s3 (done). Applied only by the tests that need them, so
  // roots()'s shape stays what the other tests count on.
  function storyTree() {
    return [
      card("m1", "Milestone one", "todo", "m desc", [
        card("s1", "Story one", "todo", "s desc",
          [card("t1", "Subtask one", "done", "t desc")], ["x1", "ghost"]),
        card("s2", "Blocked story", "blocked", "b desc",
          [card("t2", "Subtask two", "todo", "t desc")], ["s1"]),
        card("s3", "Done story", "done", "d desc",
          [card("t3", "Subtask three", "done", "t desc")])]),
      card("x1", "Other milestone", "in_progress", "x desc")]
  }
```

- [ ] **Step 2: Add the two rows and apply the tree when a row asks for it**

Replace the data function and the first lines of the test (`:463-470`):

```qml
  function test_every_card_has_a_dispatch_button_that_asks_the_owner_data() {
    return [{ tag: "milestone", id: "m1" }, { tag: "story", id: "s1" }, { tag: "done-subtask", id: "t1" }]
  }

  function test_every_card_has_a_dispatch_button_that_asks_the_owner(data) {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
```

with:

```qml
  function test_every_card_has_a_dispatch_button_that_asks_the_owner_data() {
    return [{ tag: "milestone", id: "m1" }, { tag: "story", id: "s1" }, { tag: "done-subtask", id: "t1" },
            { tag: "blocked-story", id: "s2", tree: true }, { tag: "done-story", id: "s3", tree: true }]
  }

  function test_every_card_has_a_dispatch_button_that_asks_the_owner(data) {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    if (data.tree) s.app.board.applyTreeData(storyTree())
```

The rest of the test body (`dispatchSpy.target = s` … `compare(s.app.runs.dispatchState, "idle", …)`)
stays exactly as it is. After `s.navigator.openCard(data.id)` and `wait(50)`, add one line
so a row can never silently open the wrong card:

```qml
    compare(s.app.board.selectedCardId, data.id)
```

The full test now reads:

```qml
  function test_every_card_has_a_dispatch_button_that_asks_the_owner(data) {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    if (data.tree) s.app.board.applyTreeData(storyTree())
    dispatchSpy.target = s
    dispatchSpy.clear()
    s.navigator.openCard(data.id)
    wait(50)
    compare(s.app.board.selectedCardId, data.id)
    var button = H.find(s, "cardDispatchButton")
    verify(button, "the Dispatch button")
    compare(button.visible, true)
    compare(String(button.text), "Dispatch")
    compare(String(button.iconText), "▶")
    compare(button.enabled, true)
    compare(H.find(s, "cardDispatchMissing").visible, false)
    mouseClick(button)
    compare(dispatchSpy.count, 1)
    compare(dispatchSpy.signalArguments[0][0], data.id)
    compare(s.app.runs.dispatchState, "idle", "the screen opens nothing itself")
  }
```

- [ ] **Step 3: Run the screen tests**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: PASS (`Totals:` with 0 failed). The new rows pass at once because the button is level-free.

- [ ] **Step 4: Mutation check — make the button skip stories, watch the rows go red**

Temporarily edit `ui/screens/CardDetailScreen.qml`, the button's handler:

```qml
      onClicked: if (detailCard.card && detailCard.card.depth !== 1) detailCard.dispatchRequested(detailCard.card.id)
```

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: FAIL in `test_every_card_has_a_dispatch_button_that_asks_the_owner(story)`,
`(blocked-story)` and `(done-story)` at `compare(dispatchSpy.count, 1)` (actual 0).

Restore: `git checkout -- ui/screens/CardDetailScreen.qml`

- [ ] **Step 5: Reword the contract comment**

In `ui/screens/CardDetailScreen.qml`, replace lines 94-96:

```qml
  // Every card has it: a story or a finished card opens a dialog that says
  // why it cannot start (and offers a story's milestone). Without am it is
  // disabled, and the caption says why.
```

with:

```qml
  // Every card has it, and a click asks the owner to dispatch this card.
  // Without am it is disabled, and the caption says why.
```

- [ ] **Step 6: Run the screen tests again**

Run: `bash tests/run.sh tst_card_detail_screen`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git status   # only the two files below
git add tests/ui/screens/tst_card_detail_screen.qml ui/screens/CardDetailScreen.qml
git commit -m "test(dispatch): a blocked or done story's Dispatch asks the owner for that story"
```

---

### Task 2: Keys tier — `d` on every kind of story, the board-list path, `am` missing

**Files:**
- Test: `tests/ui/tst_shortcuts.qml` (`onBoard()` at `:651-660`; `test_d_on_the_board_list_asks_for_the_cursor_cards_dispatch` at `:663-669`; `test_d_is_left_alone_data`/`test_d_is_left_alone` at `:672-703`; `test_d_on_a_card_asks_for_that_cards_dispatch` at `:715-721`)

**Interfaces:**
- Consumes: `Shortcuts.handleDispatchKey(event)` → bool; `actions.openDispatch(target)` recorded as `"dispatch:" + target` in `tc.calls`; existing helpers `onBoard()`, `dispatched()`, `plain(key)`, `card(id, title, status, children)`; `navigator.openCard(id)`, `navigator.activateCursor()`.
- Produces: `storyTree()` helper local to `tst_shortcuts.qml`.

- [ ] **Step 1: Add the story fixture and T2**

In `tests/ui/tst_shortcuts.qml`, directly after `function dispatched() { … }` (line 661), add:

```qml
  // m1 holding s1 (todo), s2 (brd status blocked, blocked by s1) and s3
  // (done), each with one subtask. card() has no blocked_by argument.
  function storyTree() {
    var s2 = card("s2", "Blocked story", "blocked", [card("t2", "Sub two", "todo")])
    s2.blocked_by = ["s1"]
    return [card("m1", "Milestone", "todo", [
      card("s1", "Story", "todo", [card("t1", "Sub one", "todo")]),
      s2,
      card("s3", "Done story", "done", [card("t3", "Sub three", "done")])])]
  }
```

Directly after `test_d_on_a_card_asks_for_that_cards_dispatch` (which stays as it is), add:

```qml
  // S7: d on an open story asks for that story, whatever its status.
  function test_d_on_an_open_story_asks_for_that_story_data() {
    return [{ tag: "story", id: "s1" }, { tag: "blocked-story", id: "s2" }, { tag: "done-story", id: "s3" }]
  }

  function test_d_on_an_open_story_asks_for_that_story(data) {
    var s = onBoard(); if (!s) return
    s.app.board.applyTreeData(storyTree())
    s.navigator.openCard(data.id)
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, data.id)
    compare(s.app.board.cardMap[data.id].depth, 1, "a story")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:" + data.id)
    compare(s.app.runs.dispatchState, "idle", "the key only asks the panel")
  }

  // S7: the board list holds roots only, so a story is reached through its
  // milestone's card detail; d there asks for the story.
  function test_d_reaches_a_story_from_the_board_list() {
    var s = onBoard(); if (!s) return
    compare(s.app.board.boardCards.map(function(c) { return c.id + ":" + c.depth }).join(","), "m1:0",
            "the board list holds roots only")
    s.navigator.activateCursor()
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m1")
    compare(s.app.nav.cursorIndex, 0)
    s.navigator.activateCursor()
    compare(s.app.board.selectedCardId, "s1")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:s1")
  }
```

- [ ] **Step 2: T4 — the board list never targets a story**

In `test_d_on_the_board_list_asks_for_the_cursor_cards_dispatch`, after
`compare(s.app.board.boardCards[0].id, "m1")`, add:

```qml
    compare(s.app.board.boardCards.map(function(c) { return c.id }).indexOf("s1"), -1, "a story is never a board-list row")
```

- [ ] **Step 3: T5 — `am` missing on an open story**

In `test_d_is_left_alone_data`, add the row `{ tag: "am-missing-on-story" }` after
`{ tag: "am-missing" }`:

```qml
  function test_d_is_left_alone_data() {
    return [
      { tag: "shift" }, { tag: "ctrl" }, { tag: "search-text" }, { tag: "no-project" }, { tag: "am-missing" },
      { tag: "am-missing-on-story" },
      { tag: "dropdown" }, { tag: "modal" }, { tag: "dispatch-open" }, { tag: "runs" }, { tag: "graph" },
      { tag: "documents" }, { tag: "empty-board" }, { tag: "cursor-past-the-end" }, { tag: "other-letter" }
    ]
  }
```

In `test_d_is_left_alone`'s `switch`, after the `case "am-missing": …` line, add:

```qml
    case "am-missing-on-story":
      s.navigator.openCard("s1")
      compare(s.app.nav.viewMode, "entry")
      s.app.runs.amStatus = "missing"
      break
```

- [ ] **Step 4: Run the keys tests**

Run: `bash tests/run.sh tst_shortcuts`
Expected: PASS. All new tests pass at once.

- [ ] **Step 5: Mutation check — make `d` skip stories**

Temporarily edit `ui/Shortcuts.qml` `handleDispatchKey`, after the line
`var id = card && typeof card.id === "string" ? card.id : ""`, add:

```qml
    if (card && card.depth === 1) return false
```

Run: `bash tests/run.sh tst_shortcuts`
Expected: FAIL in `test_d_on_an_open_story_asks_for_that_story(story)`, `(blocked-story)`,
`(done-story)`, `test_d_reaches_a_story_from_the_board_list` and the existing
`test_d_on_a_card_asks_for_that_cards_dispatch`, each at `compare(s.handleDispatchKey(...), true)`.

Restore: `git checkout -- ui/Shortcuts.qml`

- [ ] **Step 6: Mutation check — the `am` guard**

Temporarily edit `ui/Shortcuts.qml` `handleDispatchKey`, changing
`if (keys.app.runs.amStatus === "missing" || keys.modalOpen() || keys.app.nav.dropdownOpen) return false`
to
`if ((keys.app.runs.amStatus === "missing" && mode === "board") || keys.modalOpen() || keys.app.nav.dropdownOpen) return false`.

Run: `bash tests/run.sh tst_shortcuts`
Expected: FAIL in `test_d_is_left_alone(am-missing-on-story)` only.

Restore: `git checkout -- ui/Shortcuts.qml`

- [ ] **Step 7: Run again and commit**

Run: `bash tests/run.sh tst_shortcuts` — Expected: PASS.

```bash
git status   # only tests/ui/tst_shortcuts.qml
git add tests/ui/tst_shortcuts.qml
git commit -m "test(dispatch): d reaches every kind of story from the board list"
```

---

### Task 3: Panel tier — board list → milestone → story → the mounted dialog

**Files:**
- Test: `tests/ui/tst_board_flow.qml` (append after the last test, before the final `}`; uses `card()`, `ids()` at `:13-16` and `hostC` at `:10`)

**Interfaces:**
- Consumes: `Panel.qml` properties `app`, `navigator`, `opened`, `dispatchCardId`, `focusItem`; objects `cardDispatchButton`, `keyCatcher`, `dispatchDialog`, `dispatchTarget`, `dispatchRefusal`, `dispatchStart`, `dispatchSuggest`, `dispatchBase` (via `H.find`); `app.runs.dispatchState`, `dispatchTarget` (`{level, flags}`), `dispatchErrorType`, `dispatchDefaultsRunner.current`, `dispatchPreviewRunner.current` (a `HelperRunner`, `current` null until a launch), `snapshotRunner.cancel()`, `settingsLoadRunner.cancel()`, `runSettings`.
- Produces: helpers local to `tst_board_flow.qml`: `dispatchRoots()`, `makeDispatch()`, `reply(proc, text)`, `reachStory(p, steps, id)`, `useEntryPoint(p, how)`, `text(p, name)`, `flags(p)`.

- [ ] **Step 1: Add the helpers**

Append to `tests/ui/tst_board_flow.qml`, before the file's final `}`:

```qml
  // ---- Dispatch from the board list (S7: a story's entry points)

  // m1 holds s1 (todo), s2 (brd status blocked, blocked by s1) and s3 (done),
  // each with one subtask; x1 is a done milestone.
  function dispatchRoots() {
    return [
      card("m1", "Milestone", "todo", [
        card("s1", "Story one", "todo", [card("t1", "Sub one", "todo")]),
        card("s2", "Story two", "blocked", [card("t2", "Sub two", "todo")], ["s1"]),
        card("s3", "Story three", "done", [card("t3", "Sub three", "done")])]),
      card("x1", "Ex", "done")]
  }

  // A panel on project /x's board list, the cursor on m1. No helper may
  // really run here (start-run.py starts am): every script path leads
  // nowhere, the export, snapshot and settings runners are cancelled, and a
  // stored verify command lets a fresh form pass the store's checks.
  function makeDispatch() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.app.backendDir = "/plugin/core/backend/"
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/x", name: "proj" }])
    if (!p.app.projects.selectedProject) { fail("project /x is selected"); return null }
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.settingsLoadRunner.cancel()
    p.app.runs.runSettings = { verify: ["uv run pytest"] }
    p.app.board.applyTreeData(dispatchRoots())
    wait(50)
    p.navigator.showSection("board")
    p.app.nav.cursorIndex = 0
    return p
  }

  // A helper's reply, delivered the way its Process would deliver it.
  function reply(proc, text) {
    proc.outText = text
    proc.exited(0)
  }

  function text(p, name) { return String(H.find(p, name).text) }
  function flags(p) { return JSON.stringify(p.app.runs.dispatchTarget.flags) }

  // From the board list: the cursor card m1 opened, then the story `steps`
  // links down its children (0 = s1, 1 = s2, 2 = s3) opened. The board list
  // holds roots only, so this is how a story is reached.
  function reachStory(p, steps, id) {
    compare(ids(p.app.board.boardCards), "m1,x1", "the board list holds roots only")
    compare(p.app.board.boardCards[p.app.nav.cursorIndex].id, "m1")
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "m1")
    compare(p.app.board.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","),
            "child:s1,child:s2,child:s3")
    if (steps > 0) p.navigator.moveCursor(steps)
    compare(p.app.nav.cursorIndex, steps)
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, id)
    wait(50)
  }

  // The open card's entry point: a click on its Dispatch, or a bare d with
  // the card detail's key catcher holding the keyboard.
  function useEntryPoint(p, how) {
    if (how === "button") {
      H.find(p, "cardDispatchButton").clicked()
    } else {
      H.find(p, "keyCatcher").forceActiveFocus()
      keyClick("d")
    }
    wait(50)
  }
```

- [ ] **Step 2: T6 — an open story dispatches itself**

Append after the helpers:

```qml
  // S7: from the board list, a story's Dispatch and its d open the dialog on
  // the story itself.
  function test_a_story_reached_from_the_board_list_dispatches_itself_data() {
    return [{ tag: "button" }, { tag: "key" }]
  }

  function test_a_story_reached_from_the_board_list_dispatches_itself(data) {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 0, "s1")
    useEntryPoint(p, data.tag)
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "s1")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"Milestone\")")
    compare(p.app.runs.dispatchTarget.level, "story")
    compare(flags(p), JSON.stringify(["--story", "s1"]))
    compare(p.app.runs.dispatchState, "previewing")
    compare(H.find(p, "dispatchSuggest").visible, false, "no milestone offer")
    if (data.tag === "key") compare(p.app.nav.searchQuery, "", "the handled d was not typed")
  }
```

- [ ] **Step 3: T7 — a blocked story offers its milestone**

```qml
  // S7: am refuses a blocked story; the dialog offers its milestone, and the
  // offer retargets the open dialog.
  function test_a_blocked_story_from_the_board_list_offers_its_milestone() {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 1, "s2")
    useEntryPoint(p, "button")
    compare(p.dispatchCardId, "s2")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story two\" (milestone \"Milestone\")")
    compare(p.app.runs.dispatchState, "previewing", "the plugin does not refuse a blocked story up front")
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    compare(p.app.runs.dispatchState, "previewing")
    reply(p.app.runs.dispatchPreviewRunner.current,
          '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s1"}}')
    compare(p.app.runs.dispatchState, "refused")
    compare(text(p, "dispatchRefusal"), "Story blocked by s1")
    compare(H.find(p, "dispatchStart").enabled, false)
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true)
    compare(String(offer.text), "Dispatch the milestone instead")
    offer.clicked()
    compare(p.dispatchCardId, "m1")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"Milestone\"")
    compare(p.app.runs.dispatchTarget.level, "milestone")
    compare(flags(p), JSON.stringify(["--milestone", "m1"]))
    compare(p.app.runs.dispatchState, "previewing")
    compare(H.find(p, "dispatchDialog").visible, true)
  }
```

- [ ] **Step 4: T8 — a finished story is refused with its reason**

```qml
  // S7: a story in a terminal status is refused at once, as at every level,
  // and nothing is launched.
  function test_a_finished_story_from_the_board_list_is_refused_data() {
    return [{ tag: "button" }, { tag: "key" }]
  }

  function test_a_finished_story_from_the_board_list_is_refused(data) {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 2, "s3")
    useEntryPoint(p, data.tag)
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "s3")
    compare(p.app.runs.dispatchState, "refused")
    compare(p.app.runs.dispatchErrorType, "Target")
    compare(text(p, "dispatchRefusal"), "The card is done")
    compare(H.find(p, "dispatchStart").enabled, false)
    compare(H.find(p, "dispatchSuggest").visible, false, "no milestone offer")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story three\" (milestone \"Milestone\")")
    verify(!p.app.runs.dispatchDefaultsRunner.current, "no defaults lookup was launched")
    verify(!p.app.runs.dispatchPreviewRunner.current, "no preview was launched")
  }
```

- [ ] **Step 5: T9 — Escape closes a story's dialog and leaves the story open**

```qml
  // A story's dialog is a modal like any other: one Escape closes it and the
  // story stays open.
  function test_escape_closes_a_story_dialog_and_leaves_the_story_open() {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 0, "s1")
    useEntryPoint(p, "key")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.focusItem.objectName, "dispatchBase", "the dialog has the keyboard")
    keyClick(Qt.Key_Escape)
    compare(p.app.runs.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "entry", "that Escape closed the dialog only")
    compare(p.app.board.selectedCardId, "s1")
    compare(p.opened, true)
  }
```

- [ ] **Step 6: Run the board-flow tests**

Run: `bash tests/run.sh tst_board_flow`
Expected: PASS for all new tests and the two existing ones. If a test fails, read the
`Loc:` line: a wrong expectation in the test (e.g. a title typo) is fixed in the test; a
real entry-point defect is fixed only in `ui/Panel.qml`, `ui/Shortcuts.qml` or
`ui/screens/CardDetailScreen.qml`, never in `runs.js`, `RunStore.qml` or `DispatchDialog.qml`.

- [ ] **Step 7: Mutation check — stories refused by the plan**

Temporarily edit `core/domain/runs.js:912`:

```js
  if (level === "story") return _refusedPlan("story", "A story cannot be dispatched", null)
```

Run: `bash tests/run.sh tst_board_flow`
Expected: FAIL in `test_a_story_reached_from_the_board_list_dispatches_itself(button)` and
`(key)` (state `refused`, not `previewing`), and in
`test_a_blocked_story_from_the_board_list_offers_its_milestone` (state `refused` at once, and
`dispatchDefaultsRunner.current` is null so `reply` cannot answer it). T9 may or may not go red
here; it is pinned by Step 9 instead.

Restore: `git checkout -- core/domain/runs.js`

- [ ] **Step 8: Mutation check — finished stories not refused**

Temporarily delete line 910 of `core/domain/runs.js`
(`if (Board.isFinishedStatus(card.status)) return _refusedPlan(level, "The card is " + card.status, null)`).

Run: `bash tests/run.sh tst_board_flow`
Expected: FAIL in `test_a_finished_story_from_the_board_list_is_refused(button)` and `(key)`
at `compare(p.app.runs.dispatchState, "refused")`.

Restore: `git checkout -- core/domain/runs.js`

- [ ] **Step 9: Mutation check — the key path through the panel**

Temporarily edit `ui/Panel.qml` line ~390, the global key handler, removing
`|| sc.handleDispatchKey(event)` from
`if (sc.handleGlobalKey(event) || sc.handleRunKey(event) || sc.handleDispatchKey(event)) event.accepted = true`.

Run: `bash tests/run.sh tst_board_flow`
Expected: FAIL in the `(key)` rows of T6 and T8 and in T9 at
`compare(H.find(p, "dispatchDialog").visible, true)`; the `(button)` rows and T7 still pass.

Restore: `git checkout -- ui/Panel.qml`

- [ ] **Step 10: Full verification**

Run: `git status` — only `tests/ui/tst_board_flow.qml` modified (no leftover mutation).
Run: `bash tests/run.sh`
Expected: pytest green (including `tests/architecture`: `test_layers.py`, `test_icon_glyphs.py`),
every QML file's `Totals:` with 0 failed, exit status 0.

- [ ] **Step 11: Commit**

```bash
git add tests/ui/tst_board_flow.qml
git commit -m "test(dispatch): a story reached from the board list dispatches through the panel"
```
<!-- task-pipeline: validated -->
