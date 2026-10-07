# 2.2 DispatchDialog: the story label and the blocked-story action — design

Card: `2b0955bc` (subtask of story `99cd17e4`, blocked by `5cf6e2f1`, which is done on this
branch). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md`
(S7), cited below as "S7 l.N". Sibling store spec:
`docs/superpowers/specs/2-1-runstore-dispatch-5cf6e2f1.md`, cited as "2.1 l.N".

## Purpose

The store side of the story dispatch is done (card 2.1). `RunStore` now exposes:

- `dispatchTargetLabel`, for example `Story "T" (milestone "M")` (`core/stores/RunStore.qml:115`);
- `dispatchSuggest`, the parent milestone `{id, title}`, non-null only in a blocked-story
  refusal (`RunStore.qml:121`);
- `retargetToMilestone()`, which reopens the dispatch on that milestone (`RunStore.qml:986-993`);
- the finished-story refusal `Nothing left to run` and the `ClaimedError` refusal, both as
  plain `refused` states.

The dialog does not show any of this correctly yet:

1. The target line is built from `target.level` and Panel's `targetTitle`. A story therefore
   reads `Story "T"`, without its milestone (`ui/components/DispatchDialog.qml:78-87`).
2. The offer button reads `Dispatch its milestone "<title>"` (`DispatchDialog.qml:66-69`). The
   spec wording is **Dispatch the milestone instead**.
3. Panel maps `suggestionRequested()` to `root.openDispatch(suggestion.id)` (`ui/Panel.qml:883`).
   It does not call the store's retarget.
4. There are no dialog tests for a blocked story, a finished story, or a claimed story.

## Inherited constraints

- The dialog target reads `Story "<title>" (milestone "<title>")` (S7 l.43-44). The store
  composes it as `dispatchTargetLabel` (2.1 l.71-90).
- Blocked story: the refusal shows inline, Start stays disabled, and an action **Dispatch the
  milestone instead** retargets the dialog to the parent milestone. The same holds after a
  refusal at Start (S7 l.55-61).
- Other refusals are shown inline as at the other levels. A finished story shows "Nothing left
  to run". A claimed story is a `ClaimedError` naming the holding run (S7 l.62-64).
- `DispatchDialog` is changed in place. There is no new component (S7 l.87-88).
- `tests/ui/` covers the blocked-story inline refusal and its action, a finished story, and a
  claimed story (S7 l.104-105). The Dispatch button and the `d` key belong to card 2.3.
- 2.1 hands this card three things: `DispatchDialog` showing `dispatchTargetLabel`, the action
  text, and Panel calling `retargetToMilestone()` instead of `openDispatch(suggest.id)`, plus
  their `tests/ui` tests (2.1 l.300-302).
- Card: the dialog is presentation only. It works through props and signals and never imports
  a store. Follow `docs/architecture.md` layering. `tests/architecture` must pass: no
  duplicated components, and the icon glyph rules (`tests/architecture/test_layers.py`,
  `test_icon_glyphs.py`). No new glyph is introduced. Verification: `bash tests/run.sh` is
  green. TDD: tests first. Docstrings and comments state the contract only, with no narrative.

## Behaviour

### `DispatchDialog` (`ui/components/DispatchDialog.qml`)

**Target label.** There is a new string property, `targetLabel`, with default `""`. It is the
owner's ready-made target text, which is RunStore's `dispatchTargetLabel`.

- When `targetLabel` is non-empty, the target line (`dispatchTarget`) reads
  `Target   <targetLabel>` verbatim. `target.level` and `targetTitle` are then ignored for this
  line.
- When `targetLabel` is `""`, the line keeps today's text, built from level and title. This is
  the fallback for a standalone instance and for owners that do not pass a label. Every
  existing row of `test_the_target_line_names_the_level` stays green unchanged.
- `targetLevel` keeps driving everything else: the preview heading, the subtask note and the
  cost warning. The label never changes which preview area is shown.

**Blocked-story action.** The offer button (`dispatchSuggest`) keeps:

- its objectName;
- its visibility rule, `canOffer`: state `refused` and `suggestion.id` a non-empty string;
- its signal: one click emits `suggestionRequested()` once, and nothing else.

Its text is always `Dispatch the milestone instead`, whatever `suggestion.title` is. The
milestone is already named on the target line. `offerText` is removed, or it becomes that
constant; the planner chooses. The `suggestion` comment states the new meaning: "a blocked
story's milestone `{id, title}`; with a refusal it shows the retarget action".

**Refusals that need no new rendering.** Each of these uses the existing refusal path:
`showRefusal`, the `dispatchRefusal` text verbatim in `urgent`, Start disabled, no summary and
no launch details.

| owner passes | target line | refusal text | Start | action |
|---|---|---|---|---|
| `refused`, story, error = am's `StoryBlockedError` message, `suggestion {id:"m1", title:"M one"}` | `Target   Story "Story one" (milestone "M one")` | the message verbatim | disabled | visible, `Dispatch the milestone instead` |
| `refused`, story, error `Nothing left to run`, `suggestion null` | the story label | `Nothing left to run` | disabled | hidden |
| `refused`, story, error naming the run (e.g. `Card s1 is claimed by run r-123 (ClaimedError)`), `suggestion null` | the story label | that message verbatim | disabled | hidden |

Clicking the disabled Start in any of these rows emits nothing.

**Header comment** (`DispatchDialog.qml:7-13`). The phrase "a refused story's milestone
(suggestionRequested)" is replaced by the contract: the owner may pass a ready target label
(`targetLabel`), and may pass a blocked story's milestone, whose action emits
`suggestionRequested()`.

### Panel wiring (`ui/Panel.qml`, the `DispatchDialog` mount at l.859-884)

Panel is the owner, and it already imports the stores. The dialog itself still imports none.

- `targetLabel: appStores.runs.dispatchTargetLabel`.
- `onSuggestionRequested` calls `appStores.runs.retargetToMilestone()`.
  - The handler reads `root.dispatchSuggestion.id` into a local before calling the store: a
    successful retarget clears the store's `dispatchSuggest`, so `root.dispatchSuggestion` is
    `null` afterwards.
  - When the call returns `true`, Panel's `dispatchCardId` becomes that saved id, so
    `dispatchCard`, `targetTitle` and `targetChoice` follow the milestone.
  - When it returns `false`, nothing in Panel changes.
  - Panel no longer calls `root.openDispatch(suggestion.id)` for the offer.
  - The handler keeps today's guard: nothing happens when `root.dispatchSuggestion` is null.
    That covers a milestone that is no longer on the board (`Panel.qml:277-280`).
- The `openDispatch` comment (`Panel.qml:302`) is corrected: "a story's offer" is no longer
  one of its callers.

### Docs

`docs/architecture.md:162`, the `DispatchDialog` entry, is updated:

- the target line uses the owner's `targetLabel` when it is given, for example
  `Story "<title>" (milestone "<title>")`;
- `a refused dialog with a suggestion {id, title} shows Dispatch the milestone instead, which
  emits suggestionRequested()`;
- Panel maps it onto `retargetToMilestone()`.

Nothing else in the docs changes. The broader four-level dispatch docs belong to card 2.4.

## Error paths

- `targetLabel` not passed, or `""`: the level/title text, as today.
- `suggestion` null, without an id, with an empty id or with a non-string id, or a state other
  than `refused`: the action is hidden, and a forced `clicked()` emits nothing. These are the
  existing rules, re-asserted with the new text.
- A `failed` dialog with a suggestion (in practice the store never sets one there): the action
  is hidden, because `canOffer` requires `refused`.
- `retargetToMilestone()` returns `false`, for example because the state moved on between
  render and click: Panel keeps its card id, and the dialog stays as the store leaves it.

## Tests

Tiers:

- **UI component**: `tests/ui/components/tst_dispatch_dialog.qml`. The dialog is created alone
  with `make(over)`. The `SignalSpy`s `offers`, `starts` and `cancels` are already there, and
  so is the `storyRefusal(over)` helper at about l.752. This is the tier for rendering and
  emitted signals with no store. It is the tier the card names.
- **UI flow**: `tests/ui/tst_dispatch_flow.qml`. The whole `Panel` runs with its real stores and
  fake helper replies (`reply(proc, text)`). It is the only tier that can prove that Panel binds
  `dispatchTargetLabel` and maps the action to `retargetToMilestone()`.

Everything runs under `bash tests/run.sh`, and a single file can be run with
`bash tests/run.sh tst_dispatch_dialog`.

### `tst_dispatch_dialog.qml` (UI component)

`storyRefusal` changes its defaults:

- `error` becomes a `StoryBlockedError`-style message, for example
  `Story "Story one" is blocked by "Story zero" (StoryBlockedError)`;
- `targetLabel: 'Story "Story one" (milestone "M one")'` is added.

1. **Label used verbatim.** `make({target:{level:"story"}, targetTitle:"Story one",
   targetLabel:'Story "Story one" (milestone "M one")'})`. The `dispatchTarget` text is
   `Target   Story "Story one" (milestone "M one")`. A second row checks that a label
   overrides the level text at another level: a milestone label `Milestone "M one"` with
   `targetTitle` `"other"` reads `Target   Milestone "M one"`.
2. **Empty label falls back.** The existing `test_the_target_line_names_the_level` rows pass
   unchanged, with no `targetLabel` passed. One extra row passes `targetLabel: ""` explicitly
   with level `story` and expects `Target   Story "Dispatch UI"`.
3. **Blocked story: refusal and action.** This replaces `test_a_refused_story_offers_its_milestone`.
   - `make(storyRefusal())`;
   - `dispatchRefusal` is visible, has the message verbatim and is in `theme.urgent`;
   - `dispatchStart.enabled` is `false`, and a click on Start gives `starts.count` 0;
   - `dispatchSuggest` is visible, with the text `Dispatch the milestone instead`;
   - one click gives `offers.count` 1, `starts.count` 0 and `cancels.count` 0;
   - the target line shows the story label.
4. **The action text ignores the title.** This replaces
   `test_an_untitled_milestone_offer_reads_without_a_title`. With `suggestion {id:"m1",
   title:""}` and with `{id:"m1", title:"M one"}`, the text is `Dispatch the milestone instead`
   both times.
5. **Visibility rules.** `test_the_offer_shows_only_for_a_refusal_with_a_milestone_id` is kept
   with its four rows. One row is added: `failed` with a suggestion, which is hidden and emits
   nothing.
6. **Finished story.** `make(storyRefusal({error:"Nothing left to run", suggestion:null}))`:
   - `dispatchRefusal` is visible with the text `Nothing left to run`;
   - Start is disabled;
   - `dispatchSuggest` is not visible;
   - `dispatchSummary` is not visible;
   - the target line is the story label.
7. **Claimed story.** `make(storyRefusal({error:"Card s1 is claimed by run r-123
   (ClaimedError)", suggestion:null}))`:
   - the refusal text is verbatim and contains `r-123`;
   - Start is disabled;
   - the action is hidden;
   - no launch details (`dispatchExitCode` and `dispatchLogPath` are hidden).

### `tst_dispatch_flow.qml` (UI flow)

8. **Story label through Panel.** Test 22, `test_a_story_opens_the_dialog_on_itself`, now
   expects `Target   Story "Story one" (milestone "M one")`. Its other assertions are kept: no
   suggestion and no offer while previewing.
9. **Blocked story retargets through the store.** This is a new test.
   - `dispatchCard(p, "s1")`, then reply to the `--defaults` lookup;
   - reply to the preview with `{"ok":false,"error":{"type":"StoryBlockedError","message":"Story
     blocked by s0"}}`;
   - the dialog shows the refusal text, Start is disabled, and `dispatchSuggest` is visible
     with `Dispatch the milestone instead`;
   - a click on it leaves `p.app.runs.dispatchTarget.level` at `milestone` (flags
     `--milestone m1`);
   - `p.dispatchCardId` is `m1`;
   - the target line reads `Target   Milestone "M one"`;
   - the state is `previewing`, and `dispatchSuggest` is hidden.
10. **Finished and claimed story through Panel.** One data-driven test with two rows. Each row
    opens `s1`, replies to the defaults, and then replies to the preview:
    - with an ok story payload with zero subtasks (`{"ok":true,"data":{"integrate":null,
      "levels":[]}}`), the dialog shows `Nothing left to run`;
    - with `{"ok":false,"error":{"type":"ClaimedError","message":"Card s1 is claimed by run
      r-other"}}`, the dialog shows that message.

    In both rows Start is disabled and the action is hidden.

Existing tests that must stay green: every other test in both files, `tst_run_store.qml`
(untouched), and `tests/architecture`.

## Review focus hints for the planner

- The retarget passes through idle (`openDispatch` resets first). Panel's
  `onDispatchOpenChanged` then clears `dispatchChoices` and refocuses. The offer only appears
  for a dialog opened from a card, so there is no row to lose. Check that the dialog stays
  shown and focus lands on the new form.
- `retargetToMilestone()` returning `false` must not move `dispatchCardId`. Otherwise
  `targetTitle` and `targetChoice` drift from the store's target.
- A double click on the action: the second click finds `previewing`, so `canOffer` is false
  and nothing is emitted.
- An offer whose suggestion title is a non-string, for example `7`: the text is still the
  constant, with no `TypeError` in the run output (`tests/run.sh` fails on one).
- A long story or milestone title: the target line keeps `elide: Text.ElideRight` and does not
  wrap the header.

## Out of scope

- `RunStore`, `runs.js` and the helpers: done in 2.1 and 1.x. They are reused unchanged.
- The Dispatch button in `CardDetailScreen` and the `d` key in `Shortcuts.qml` for a story,
  with their flow tests in `tst_card_detail_screen.qml`, `tst_shortcuts.qml` and
  `tst_board_flow.qml`: card 2.3.
- README and the four-level dispatch description in `docs/architecture.md`, beyond the
  `DispatchDialog` entry: card 2.4.
- Any new component, glyph or colour.
- Showing which blocker stories block the story beyond am's message.
- Dispatching several stories (S7 l.107-109).
