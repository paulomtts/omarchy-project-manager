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
