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

---

# 2.2 DispatchDialog: the story label and the blocked-story action — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `DispatchDialog` shows RunStore's `dispatchTargetLabel` on its target line and reads `Dispatch the milestone instead` on its blocked-story action, and Panel maps that action onto `appStores.runs.retargetToMilestone()`.

**Architecture:** The dialog stays presentation only: a new `targetLabel` string prop overrides the level/title target text when non-empty, and the offer button's text becomes a constant. Panel (the owner, which already imports the stores) binds `targetLabel` to `appStores.runs.dispatchTargetLabel` and replaces its `openDispatch(suggestion.id)` handler with a call to the store's retarget, moving `dispatchCardId` only when the retarget succeeds.

**Tech Stack:** Qt 6 QML (Quickshell plugin), QtTest via `qmltestrunner`, pytest architecture tests, all run by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/2-2-dispatchdialog-the-2b0955bc.md` (prepended above).

## Global Constraints

- The dialog is presentation only: it works through props and signals and never imports a store (`docs/architecture.md` layering; `tests/architecture/test_layers.py`).
- `DispatchDialog` is changed in place. No new component, glyph or colour (`tests/architecture`, `test_icon_glyphs.py`).
- Story target text: `Story "<title>" (milestone "<title>")`, from RunStore's `dispatchTargetLabel`.
- Action text, exactly: `Dispatch the milestone instead`.
- Docstrings and comments state the contract only, with no narrative.
- TDD: every test is written and seen failing before its code.
- Verification: `bash tests/run.sh` is green (it also fails on any `TypeError` / `ReferenceError` in QML output).
- `RunStore.qml`, `runs.js` and the helpers are not changed.

## Review Focus

1. A double click on the action: the second click finds `previewing`, `canOffer` is false, nothing is emitted, and Panel's card id stays on the milestone. Pinned in Task 2 (component: `test_a_second_click_after_the_owner_moves_on_emits_nothing`) and Task 3 (flow: the second `clicked()` in `test_a_blocked_story_retargets_to_its_milestone`).
2. `retargetToMilestone()` returning `false`, or Panel having no suggestion: `dispatchCardId`, `targetTitle` and the target line stay on the story. Pinned in Task 3 (`test_a_refused_retarget_leaves_the_story_dialog`).
3. Focus after the retarget passes through idle: the dialog stays shown and the keyboard lands on the new form's Base field. Pinned in Task 3 (focus asserts in `test_a_blocked_story_retargets_to_its_milestone`).
4. A suggestion whose title is a non-string (`7`) or missing: the action text is still the constant, and no `TypeError` reaches the run output. Pinned in Task 2 (`test_the_action_text_ignores_the_title` rows `non-string-title`, `no-title`).
5. A long story/milestone label: the target line keeps `elide: Text.ElideRight` and stays one line, so the header does not wrap. Pinned in Task 1 (`test_a_long_label_elides_on_one_line`).

**Known knock-on (not in the spec's test list):** with Panel binding `targetLabel`, `test_a_card_dropped_from_the_board_while_open_leaves_a_working_dialog` in `tests/ui/tst_dispatch_flow.qml` (l.257) no longer reads `Target   Subtask ""`: the store computed `Subtask "Do it"` at open and keeps it while the dispatch is open. Task 3 updates that one assertion to `Target   Subtask "Do it"`; the test's intent (a working dialog) is unchanged.

---

## File Structure

- Modify `ui/components/DispatchDialog.qml` — `targetLabel` prop, `targetText` override, constant action text, header and `suggestion` comments; `offerText` removed.
- Modify `tests/ui/components/tst_dispatch_dialog.qml` — label tests, blocked/finished/claimed refusal tests, action-text tests.
- Modify `ui/Panel.qml` — `targetLabel` binding, `onSuggestionRequested` handler, `openDispatch` comment.
- Modify `tests/ui/tst_dispatch_flow.qml` — test 22 label, retarget flow, finished/claimed flow, refused-retarget flow, card-dropped assertion.
- Modify `docs/architecture.md:162` — the `DispatchDialog` entry.

Run a single QML file with `bash tests/run.sh tst_dispatch_dialog` (filter is a substring of the test path; pytest runs first every time and must pass too).

---

### Task 1: `targetLabel` on the dialog's target line

**Files:**
- Modify: `ui/components/DispatchDialog.qml:27-28` (props), `:78-87` (`targetText`)
- Test: `tests/ui/components/tst_dispatch_dialog.qml:64-87` (the target line section)

**Interfaces:**
- Consumes: nothing new.
- Produces: `DispatchDialog.targetLabel` — `property string targetLabel: ""`. When non-empty, `dispatchTarget.text === "Target   " + targetLabel`. Task 3 binds it in Panel.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_dispatch_dialog.qml`, add a row to `test_the_target_line_names_the_level_data` (the existing function at l.66). Replace the whole function with:

```qml
  function test_the_target_line_names_the_level_data() {
    return [
      { tag: "milestone", level: "milestone", title: "Document milestone runs",
        text: "Target   Milestone \"Document milestone runs\"" },
      { tag: "board", level: "board", title: "", text: "Target   Whole board" },
      { tag: "subtask", level: "subtask", title: "RunStore dispatch", text: "Target   Subtask \"RunStore dispatch\"" },
      { tag: "story", level: "story", title: "Dispatch UI", text: "Target   Story \"Dispatch UI\"" },
      { tag: "unknown-level", level: "", title: "Loose card", text: "Target   \"Loose card\"" },
      { tag: "no-level-no-title", level: "", title: "", text: "Target   No card" },
      { tag: "story-empty-label", level: "story", title: "Dispatch UI", label: "",
        text: "Target   Story \"Dispatch UI\"" }
    ]
  }

  function test_the_target_line_names_the_level(data) {
    var over = { target: { level: data.level }, targetTitle: data.title }
    if (data.label !== undefined) over.targetLabel = data.label
    var d = make(over)
    compare(H.find(d, "dispatchTarget").text, data.text)
  }
```

Directly after `test_a_null_target_without_a_title_is_no_card` (ends at l.86), add:

```qml
  function test_the_owners_label_is_the_target_line_verbatim_data() {
    return [
      { tag: "story", level: "story", title: "Story one", label: "Story \"Story one\" (milestone \"M one\")",
        text: "Target   Story \"Story one\" (milestone \"M one\")" },
      { tag: "milestone-over-another-title", level: "milestone", title: "other", label: "Milestone \"M one\"",
        text: "Target   Milestone \"M one\"" }
    ]
  }

  function test_the_owners_label_is_the_target_line_verbatim(data) {
    var d = make({ target: { level: data.level }, targetTitle: data.title, targetLabel: data.label })
    compare(H.find(d, "dispatchTarget").text, data.text)
  }

  function test_the_label_leaves_the_level_driven_areas_alone() {
    var d = make({ target: { level: "subtask" }, targetTitle: "Do it", targetLabel: "Milestone \"M one\"",
                   dispatchState: "previewing", preview: null })
    compare(H.find(d, "dispatchPreviewHeading").text, "Preview")
    verify(H.find(d, "dispatchSubtaskNote").visible, "the subtask note follows the level")
    compare(H.find(d, "dispatchWarning").text, "⚠ This starts agents and spends tokens.")
  }

  function test_a_long_label_elides_on_one_line() {
    var long = "Story \"" + new Array(40).join("A very long story title ") + "\" (milestone \"M one\")"
    var d = make({ target: { level: "story" }, targetTitle: "x", targetLabel: long })
    var line = H.find(d, "dispatchTarget")
    compare(line.elide, Text.ElideRight)
    compare(line.text, "Target   " + long)
    verify(line.truncated, "the label is cut, not wrapped")
    compare(line.lineCount, 1)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — `Cannot assign to non-existent property "targetLabel"` (caught by run.sh's `non-existent` grep) and failures in `test_the_owners_label_is_the_target_line_verbatim`, `test_the_label_leaves_the_level_driven_areas_alone`, `test_a_long_label_elides_on_one_line`, and the `story-empty-label` row.

- [ ] **Step 3: Write the minimal implementation**

In `ui/components/DispatchDialog.qml`, after the `targetTitle` prop (l.27-28), insert:

```qml
  // The owner's ready-made target text (RunStore's dispatchTargetLabel); ""
  // builds it from the level and targetTitle. Only the target line reads it.
  property string targetLabel: ""
```

Replace `targetText` (l.78-87) with:

```qml
  readonly property string targetText: {
    if (dialog.targetLabel !== "") return dialog.targetLabel
    var quoted = "\"" + dialog.targetTitle + "\""
    switch (dialog.targetLevel) {
    case "board": return "Whole board"
    case "milestone": return "Milestone " + quoted
    case "story": return "Story " + quoted
    case "subtask": return "Subtask " + quoted
    }
    return dialog.targetTitle !== "" ? quoted : "No card"
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `Totals: N passed, 0 failed` for `tst_dispatch_dialog.qml`, no error lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): the dialog's target line takes the owner's targetLabel"
```

---

### Task 2: `Dispatch the milestone instead` and the story refusals

**Files:**
- Modify: `ui/components/DispatchDialog.qml:7-13` (header), `:45-46` (`suggestion` comment), `:66-69` (`offerText`, removed), `:430-437` (`dispatchSuggest`)
- Test: `tests/ui/components/tst_dispatch_dialog.qml:751-800` (the story offer section)

**Interfaces:**
- Consumes: `targetLabel` from Task 1.
- Produces: `dispatchSuggest.text === "Dispatch the milestone instead"` whenever `canOffer`; `suggestionRequested()` unchanged (emitted once per click while `canOffer`). `offerText` no longer exists — nothing else references it (checked: only `DispatchDialog.qml:66,434`).

- [ ] **Step 1: Write the failing tests**

In `tests/ui/components/tst_dispatch_dialog.qml`, replace the whole section from `// ---- the story's milestone offer (S3 4.2)` (l.751) through the end of `test_an_untitled_milestone_offer_reads_without_a_title` (l.795) with:

```qml
  // ---- the story's refusals and the blocked story's action (S7) -----------

  function storyRefusal(over) {
    return Object.assign({ dispatchState: "refused", target: { level: "story", offered: true }, targetTitle: "Story one",
                           targetLabel: "Story \"Story one\" (milestone \"M one\")",
                           form: null, preview: null,
                           error: "Story \"Story one\" is blocked by \"Story zero\" (StoryBlockedError)",
                           suggestion: { id: "m1", title: "M one" } }, over || {})
  }

  // 3
  function test_a_blocked_story_shows_the_refusal_and_the_milestone_action() {
    var d = make(storyRefusal())
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Story one\" (milestone \"M one\")")
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Story \"Story one\" is blocked by \"Story zero\" (StoryBlockedError)")
    compare(refusal.color, d.theme.urgent)
    var start = H.find(d, "dispatchStart")
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0, "a disabled Start emits nothing")
    var offer = H.find(d, "dispatchSuggest")
    verify(offer, "the action")
    compare(offer.visible, true)
    compare(offer.text, "Dispatch the milestone instead")
    click(offer)
    compare(offers.count, 1)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // Review Focus 1
  function test_a_second_click_after_the_owner_moves_on_emits_nothing() {
    var d = make(storyRefusal())
    var offer = H.find(d, "dispatchSuggest")
    click(offer)
    compare(offers.count, 1)
    d.dispatchState = "previewing"
    d.suggestion = null
    offer.clicked()
    compare(offers.count, 1, "the second click finds no refusal")
    compare(offer.visible, false)
  }

  // 4, Review Focus 4
  function test_the_action_text_ignores_the_title_data() {
    return [
      { tag: "titled", suggestion: { id: "m1", title: "M one" } },
      { tag: "untitled", suggestion: { id: "m1", title: "" } },
      { tag: "non-string-title", suggestion: { id: "m1", title: 7 } },
      { tag: "no-title", suggestion: { id: "m1" } }
    ]
  }

  function test_the_action_text_ignores_the_title(data) {
    var d = make(storyRefusal({ suggestion: data.suggestion }))
    var offer = H.find(d, "dispatchSuggest")
    compare(offer.visible, true)
    compare(offer.text, "Dispatch the milestone instead")
  }

  // 5
  function test_the_offer_shows_only_for_a_refusal_with_a_milestone_id_data() {
    return [
      { tag: "ready", over: { dispatchState: "ready" } },
      { tag: "no-suggestion", over: { suggestion: null } },
      { tag: "empty-id", over: { suggestion: { id: "", title: "M one" } } },
      { tag: "non-string-id", over: { suggestion: { id: 7, title: "M one" } } },
      { tag: "failed", over: { dispatchState: "failed" } }
    ]
  }

  function test_the_offer_shows_only_for_a_refusal_with_a_milestone_id(data) {
    var d = make(storyRefusal(data.over))
    var offer = H.find(d, "dispatchSuggest")
    compare(offer.visible, false)
    offer.clicked()
    compare(offers.count, 0, "a hidden offer emits nothing")
  }

  // 6
  function test_a_finished_story_says_nothing_is_left_to_run() {
    var d = make(storyRefusal({ error: "Nothing left to run", suggestion: null }))
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Story one\" (milestone \"M one\")")
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Nothing left to run")
    var start = H.find(d, "dispatchStart")
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0)
    compare(H.find(d, "dispatchSuggest").visible, false)
    compare(H.find(d, "dispatchSummary").visible, false)
  }

  // 7
  function test_a_claimed_story_names_the_holding_run() {
    var d = make(storyRefusal({ error: "Card s1 is claimed by run r-123 (ClaimedError)", suggestion: null }))
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Story one\" (milestone \"M one\")")
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Card s1 is claimed by run r-123 (ClaimedError)")
    verify(String(refusal.text).indexOf("r-123") >= 0, "the holding run")
    var start = H.find(d, "dispatchStart")
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0)
    compare(H.find(d, "dispatchSuggest").visible, false)
    compare(H.find(d, "dispatchExitCode").visible, false)
    compare(H.find(d, "dispatchLogPath").visible, false)
  }
```

Note the `storyRefusal` default `target.offered` changes from `false` to `true`: a blocked story is offered by `dispatchPlan` and refused at preview, which is what the store now produces. Nothing in the dialog reads `offered`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: FAIL — `test_a_blocked_story_shows_the_refusal_and_the_milestone_action` (`Actual: Dispatch its milestone "M one"`, `Expected: Dispatch the milestone instead`) and all four rows of `test_the_action_text_ignores_the_title` (each reads `Dispatch its milestone…`). The finished, claimed, second-click and visibility tests already pass: they pin existing rules with the new defaults.

- [ ] **Step 3: Write the minimal implementation**

In `ui/components/DispatchDialog.qml`:

Replace the header comment (l.7-13) with:

```qml
// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does. The
// owner may pass a ready target label (targetLabel), a row of targets
// (targetChosen), a blocked story's milestone, whose action emits
// suggestionRequested(), and a Start that takes two clicks (confirmFirst).
```

Replace the `suggestion` comment and prop (l.45-46) with:

```qml
  // A blocked story's milestone {id, title}; with a refusal it shows the
  // retarget action.
  property var suggestion: null
```

Delete the `offerText` property (l.66-69):

```qml
  readonly property string offerText: {
    var title = dialog.suggestion && typeof dialog.suggestion.title === "string" ? dialog.suggestion.title : ""
    return title !== "" ? "Dispatch its milestone \"" + title + "\"" : "Dispatch its milestone"
  }
```

Replace the `dispatchSuggest` button (l.430-437) with:

```qml
    // A blocked story's retarget onto its milestone, which the target line
    // already names.
    UI.ActionButton {
      objectName: "dispatchSuggest"
      visible: dialog.canOffer
      text: "Dispatch the milestone instead"
      theme: dialog.theme
      onClicked: if (dialog.canOffer) dialog.suggestionRequested()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch_dialog`
Expected: `tst_dispatch_dialog.qml` Totals with 0 failed, no `TypeError` lines, exit 0. Then `grep -rn offerText ui tests` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add ui/components/DispatchDialog.qml tests/ui/components/tst_dispatch_dialog.qml
git commit -m "feat(dispatch): a blocked story's action reads Dispatch the milestone instead"
```

---

### Task 3: Panel binds the label and retargets through the store; docs

**Files:**
- Modify: `ui/Panel.qml:302` (`openDispatch` comment), `:864-883` (the `DispatchDialog` mount)
- Modify: `docs/architecture.md:162` (the `DispatchDialog` entry)
- Test: `tests/ui/tst_dispatch_flow.qml:140-150` (test 22), `:250-262` (card-dropped), new tests after test 22

**Interfaces:**
- Consumes: `DispatchDialog.targetLabel` (Task 1); `dispatchSuggest` text (Task 2); `appStores.runs.dispatchTargetLabel` (string, `""` while idle), `appStores.runs.retargetToMilestone()` → `bool` (true: the dispatch reopened on the recorded milestone, `dispatchSuggest` cleared; false: nothing changed) from `core/stores/RunStore.qml:986-993`; Panel's `root.dispatchSuggestion` (`{id, title}` or null, `Panel.qml:277-280`) and `root.dispatchCardId`.
- Produces: nothing later tasks rely on.

- [ ] **Step 1: Write the failing tests**

In `tests/ui/tst_dispatch_flow.qml`, in test 22 `test_a_story_opens_the_dialog_on_itself` (l.141), change the target assertion line to:

```qml
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"M one\")")
```

Directly after test 22 (after its closing `}` at l.150), add:

```qml
  // A story's preview refused with `previewText`, after its defaults lookup.
  function refuseStory(p, previewText) {
    dispatchCard(p, "s1")
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    compare(p.app.runs.dispatchState, "previewing")
    reply(p.app.runs.dispatchPreviewRunner.current, previewText)
    compare(p.app.runs.dispatchState, "refused")
  }

  // 9, Review Focus 1 and 3
  function test_a_blocked_story_retargets_to_its_milestone() {
    var p = make(); if (!p) return
    refuseStory(p, '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s0"}}')
    compare(text(p, "dispatchRefusal"), "Story blocked by s0")
    compare(H.find(p, "dispatchStart").enabled, false)
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true)
    compare(String(offer.text), "Dispatch the milestone instead")
    offer.clicked()
    compare(p.app.runs.dispatchTarget.level, "milestone")
    compare(JSON.stringify(p.app.runs.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(p.dispatchCardId, "m1")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(p.app.runs.dispatchState, "previewing")
    compare(offer.visible, false)
    compare(H.find(p, "dispatchDialog").visible, true)
    offer.clicked()
    compare(p.dispatchCardId, "m1", "a second click changes nothing")
    compare(p.app.runs.dispatchTarget.level, "milestone")
    compare(p.app.runs.dispatchState, "previewing")
    wait(50)
    compare(p.focusItem.objectName, "dispatchBase")
    verify(H.find(p, "dispatchBase").activeFocus, "the retargeted form has the keyboard")
    toReady(p)
    compare(H.find(p, "dispatchStart").enabled, true)
  }

  // Review Focus 2
  function test_a_refused_retarget_leaves_the_story_dialog() {
    var p = make(); if (!p) return
    var dialog = H.find(p, "dispatchDialog")
    dispatchCard(p, "s1")
    compare(p.dispatchSuggestion, null)
    dialog.suggestionRequested()
    compare(p.dispatchCardId, "s1", "no suggestion: nothing happens")
    compare(p.app.runs.dispatchTarget.level, "story")
    p.app.runs.closeDispatch()
    refuseStory(p, '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s0"}}')
    verify(p.dispatchSuggestion !== null, "the milestone is offered")
    // The state moved on between render and click: the store refuses.
    p.app.runs.dispatchState = "previewing"
    dialog.suggestionRequested()
    compare(p.dispatchCardId, "s1")
    compare(p.app.runs.dispatchTarget.level, "story")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"M one\")")
    p.app.runs.closeDispatch()
  }

  // 10
  function test_a_finished_or_claimed_story_says_why_data() {
    return [
      { tag: "finished", preview: '{"ok":true,"data":{"integrate":null,"levels":[]}}',
        text: "Nothing left to run" },
      { tag: "claimed", preview: '{"ok":false,"error":{"type":"ClaimedError","message":"Card s1 is claimed by run r-other"}}',
        text: "Card s1 is claimed by run r-other" }
    ]
  }

  function test_a_finished_or_claimed_story_says_why(data) {
    var p = make(); if (!p) return
    refuseStory(p, data.preview)
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"M one\")")
    compare(text(p, "dispatchRefusal"), data.text)
    compare(H.find(p, "dispatchStart").enabled, false)
    compare(H.find(p, "dispatchSuggest").visible, false)
  }
```

In `test_a_card_dropped_from_the_board_while_open_leaves_a_working_dialog` (l.250), change

```qml
    compare(text(p, "dispatchTarget"), "Target   Subtask \"\"")
```

to

```qml
    compare(text(p, "dispatchTarget"), "Target   Subtask \"Do it\"", "the store's label from the opening")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_dispatch_flow`
Expected: FAIL — test 22 (`Actual: Target   Story "Story one"`), both rows of `test_a_finished_or_claimed_story_says_why` (the same story label), the card-dropped test (`Actual: Target   Subtask ""`), and `test_a_refused_retarget_leaves_the_story_dialog` (`Actual: m1`, `Expected: s1`: today's handler opens the milestone without asking the store). `test_a_blocked_story_retargets_to_its_milestone` may already pass, because today's `openDispatch("m1")` reaches the same end state; it pins that the store's retarget keeps it.

- [ ] **Step 3: Write the minimal implementation**

In `ui/Panel.qml`, replace the `openDispatch` comment (l.302):

```qml
  // A card id or "board": the card detail's Dispatch, d, and a story's offer.
  // None of them shows the target row.
```

with:

```qml
  // A card id or "board": the card detail's Dispatch and d. Neither shows the
  // target row.
```

In the `DispatchDialog` mount, after `targetTitle: …` (l.866), add:

```qml
        targetLabel: appStores.runs.dispatchTargetLabel
```

Replace the handler line (l.883)

```qml
        onSuggestionRequested: if (root.dispatchSuggestion) root.openDispatch(root.dispatchSuggestion.id)
```

with:

```qml
        // The store reopens on the milestone and clears its suggestion; the
        // card follows only when it did.
        onSuggestionRequested: {
          if (!root.dispatchSuggestion) return
          var milestoneId = root.dispatchSuggestion.id
          if (appStores.runs.retargetToMilestone()) root.dispatchCardId = milestoneId
        }
```

In `docs/architecture.md:162`, in the `DispatchDialog` entry, replace

```
`DispatchDialog` (the dispatch modal: `Target   …` for the board, a milestone, a story or a subtask;
```

with

```
`DispatchDialog` (the dispatch modal: `Target   …` for the board, a milestone, a story or a subtask, the owner's `targetLabel` verbatim when it is given, such as `Story "<title>" (milestone "<title>")`;
```

and replace

```
a `refused` dialog with a `suggestion` `{id, title}` shows `Dispatch its milestone "<title>"`, which emits `suggestionRequested()`;
```

with

```
a `refused` dialog with a `suggestion` `{id, title}` shows `Dispatch the milestone instead`, which emits `suggestionRequested()` and which Panel maps onto `retargetToMilestone()`;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_dispatch`
Expected: `tst_dispatch_dialog.qml` and `tst_dispatch_flow.qml` both 0 failed, no error lines, exit 0.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every `tst_*.qml` reports 0 failed, no `TypeError`/`ReferenceError`/`non-existent` lines, exit status 0 (`echo $?` → `0`).

- [ ] **Step 6: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_dispatch_flow.qml docs/architecture.md
git commit -m "feat(dispatch): Panel shows the store's target label and retargets a blocked story"
```
<!-- task-pipeline: validated -->
