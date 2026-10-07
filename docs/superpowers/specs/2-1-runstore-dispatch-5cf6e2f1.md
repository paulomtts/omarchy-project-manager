# 2.1 RunStore dispatch: the story target, the retarget and the keyed prefix — design

Card: `5cf6e2f1` (subtask of story `99cd17e4`). Parent design:
`docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (S7), cited below as
"S7 l.N".

## Purpose

`RunStore`'s dispatch state machine (`core/stores/RunStore.qml`, the "dispatch (S3 3.1)"
block) already opens a story as `{command: 'story', flags: ['--story', id], level: 'story'}`
(card 1.2), and its helpers already accept `story ID` (card 1.4). What the store still lacks:

1. a target label naming the story's milestone;
2. the story variant of the preview summary (the store calls `Runs.previewSummary` without the
   level today, so a story preview is read as a milestone one);
3. the prefix default that reads the Runs snapshot (the store does not pass `store.runs` to
   `Runs.dispatchDefaults` today);
4. saving the prefix used at Start under the milestone's id (`prefixByMilestone`);
5. the `StoryBlockedError` refusal, from the preview or from Start, with
   `retargetToMilestone()`;
6. a finished story ("Nothing left to run") refused inline.

## Inherited constraints

- The dialog target reads `Story "<title>" (milestone "<title>")` (S7 l.43-44).
- Story preview: `N subtasks · rooted on <branch>`, with no Integrate line and no
  "already done" count (S7 l.45-48). `Runs.previewSummary(data, "story")` already produces it
  (`core/domain/runs.js:1139-1141`).
- Prefix default order: newest run of the milestone in the Runs snapshot, then the per-project
  run settings keyed by milestone id, then S3's prefix history, then the milestone's stem. The
  same default serves the milestone level (S7 l.49-54). `Runs.dispatchDefaults(project, card,
  cardMap, runs)` already implements the order (`core/domain/runs.js:1004-1032`).
- `prefixByMilestone` sits next to the prefix history. S3's history stays as the fallback
  (S7 l.85-86). `viewer-state.py set-run-settings` merges the map per milestone id (card 1.5,
  `docs/superpowers/specs/1-5-viewer-state-py-02ca6d9d.md`). The caller picks the key, and
  the key is always a milestone card id.
- Blocked story: `am` refuses with `StoryBlockedError`. The refusal shows inline, Start stays
  disabled, and an action retargets the dialog to the parent milestone. This holds whether the
  refusal comes from the preview or from Start. After a Start refusal the dialog returns to
  the refused state with the same action (S7 l.55-61).
- Other refusals (`ClaimedError`, no match, finished story) are shown inline as at the other
  levels. A finished story shows "Nothing left to run". A `ClaimedError` names the run that
  holds the cards (S7 l.62-64).
- Terminal-status cards are refused with the reason (S7 l.65-66). `Runs.dispatchPlan` already
  refuses them with `The card is <status>`.
- Only the `RunStore` dispatch state machine changes here. "No new component" (S7 l.87-88).
- `tst_run_store.qml` covers the retarget from a preview refusal and from a start refusal, and
  prefix persistence by milestone (S7 l.102-103).
- Card: follow the `docs/architecture.md` layering. `tests/architecture` must pass: no
  duplicated components, icon glyph rules. The store imports only `core/domain` and backend
  helpers, never `ui`. Verification: `bash tests/run.sh` green. TDD: tests first. Docstrings
  and comments state the contract only, with no narrative.

## Behaviour

### Domain helpers (`core/domain/runs.js`, pure, never throwing)

The store needs a story's milestone. Today only the private `_milestoneOf` walk finds it. Two
public functions are added; the store composes nothing it could get from them.

- **`dispatchMilestone(card, cardMap)`** returns a fresh `{id, title}` of the milestone card
  that `_milestoneOf(card, cardMap)` reaches, or `null`. It is `null` in these cases:
  - the walk gives `null`: no card, a missing link, a cycle, or no `cardMap`;
  - the card reached does not have `depth` exactly `0`, for example a story whose `parentId`
    is empty;
  - the card's id is not a dispatchable id (a non-empty string not starting with `-`).

  `title` is the card's title when it is a string, else `""`. For a milestone card the result
  is the card itself. For a story, it is its parent. For a subtask, it is its root milestone.
  `"board"` gives `null`.
- **`dispatchLabel(card, cardMap)`** returns the dialog's target text. In the formats below,
  `T` is the card's title when it is a string, else `""`, and `M` is
  `dispatchMilestone(...).title`.

  | card | label |
  |---|---|
  | `"board"` | `Whole board` |
  | not an object, or no dispatchable id | `No card` |
  | depth 0 | `Milestone "T"` |
  | depth 1, `dispatchMilestone` non-null | `Story "T" (milestone "M")` |
  | depth 1, `dispatchMilestone` null | `Story "T"` |
  | depth ≥ 2 (whole number) | `Subtask "T"` |
  | any other depth | `"T"` |

  The label does not depend on the card's status, so a refused target is labelled too.

### Store state

- New public property **`dispatchTargetLabel`** (string): set by `openDispatch` to
  `Runs.dispatchLabel(card, cardMap)` for every opening, including refused ones. It is `""`
  while idle and is cleared by `resetDispatch`.
- `dispatchSuggest` keeps its type (`{id, title}` or `null`) and gets a new meaning: it is the
  parent milestone that `retargetToMilestone()` would open. It is non-null **only** in the
  blocked-story refusal described below. `openDispatch`'s refused path no longer copies
  `plan.suggest` into it, because `dispatchPlan` never suggests anymore (card 1.2). It is
  cleared together with the refusal. `clearDispatchError` clears it, so `setDispatchField` and
  `resetDispatch` drop it.
- Internal bookkeeping (`dispatchBook`, not writable by consumers): at each `openDispatch`
  the store records `cardMap` and the target's milestone card (the `cardMap` entry whose id is
  `dispatchMilestone(card, cardMap).id`, or `null`). `resetDispatch` forgets both.
- `checkDispatchIdle` in the tests also checks `dispatchTargetLabel === ""`.

### Opening

- `openDispatch(card, cardMap)` keeps its refusals: no project, or a start in flight. It
  computes the form defaults with `Runs.dispatchDefaults({defaultBranch: "", settings:
  store.runSettings}, card, cardMap, store.runs)`. The prefix of a story or milestone target is
  then, in order, the newest snapshot run of the milestone, `runSettings.prefixByMilestone[<id>]`,
  `prefixHistory[0]`, and the stem.
- A done or otherwise terminal story stays `refused` with `The card is <status>`, type
  `Target`, and `dispatchSuggest` `null`. It is labelled as usual.

### Preview

- `dispatchPreviewReplied` reads an ok reply with
  `Runs.previewSummary(envelope.data, store.dispatchTarget.level)`.
- **Finished story:** when the target level is `story` and the summary is
  `Nothing left to run` (the story variant's sentence for zero subtasks), the state becomes
  `refused` with `dispatchError` `Nothing left to run`, `dispatchErrorType` `Empty`,
  `dispatchPreview` `null` and `dispatchSuggest` `null`. Start is refused, since it only works
  from `ready`. Other levels keep their behaviour: a milestone with zero subtasks is still
  `ready`.
- **Blocked story at preview:** an error envelope with `error.type` `StoryBlockedError` and a
  non-blank message gives `refused` with that message verbatim and type `StoryBlockedError`, as
  today. In addition, `dispatchSuggest` is set to the recorded milestone as `{id, title}` when
  the target level is `story` and the milestone is known. Otherwise it stays `null`.
- **Claimed story at preview:** a `ClaimedError` gives `refused` with am's message verbatim
  (the message names the other run's id) and type `ClaimedError`, with `dispatchSuggest`
  `null`. This is unchanged from the other levels.

### Start

- **Saved settings:** when the target level is `story` or `milestone` and the recorded
  milestone is known, the `saved` object fixed at Start also carries
  `prefixByMilestone: {<milestone id>: <prefix sent>}` (the trimmed prefix). It is the last key
  in the JSON, after `parallelism`. Subtask and board starts carry no `prefixByMilestone`, and
  their saved JSON is byte-for-byte what it is today.
- **Local merge on success:** when a successful start is this dispatch's, `runSettings` takes
  the saved values as today, except `prefixByMilestone`. That key is merged: the result is a
  fresh object with the stored map's own entries (when the stored value is an object), plus the
  saved entry, which overrides an existing one. This matches the helper's per-key merge, so
  the next opening's default reads the new prefix without a reload. The same runner then
  writes `set-run-settings ROOT <savedJson>`, as today.
- **Blocked story at Start:** a failure reply for this dispatch whose `error.type` is
  `StoryBlockedError` puts the state in `refused`, not `failed`, with:
  - `dispatchError` set to am's message (`The launch could not be read` when it is blank);
  - `dispatchErrorType` set to `StoryBlockedError`;
  - `dispatchLog` and `dispatchLogTail` set to `""`, and `dispatchExitCode` set to `null`;
  - `dispatchSuggest` set as at preview.

  The form stays as it was. Nothing is saved, so there is no `set-run-settings` and
  `runSettings` is unchanged. The runner is dropped.
- Every other start failure, `ClaimedError` included, stays `failed` with the log fields, as
  today.

### `retargetToMilestone()`

- Returns `bool`. It works only when `dispatchState` is `refused` and `dispatchSuggest` is
  non-null, which is the blocked-story refusal. In that case it returns
  `openDispatch(<recorded milestone card>, <recorded cardMap>)`. That is a fresh opening of the
  parent milestone: target `milestone` with `--milestone <id>`, label `Milestone "<title>"`,
  defaults recomputed (so the user's edits to the story's form are not carried over), the
  `--defaults` lookup, then the milestone preview.
- Refused, returning `false` with nothing changed, in every other state: idle, previewing,
  ready, starting, started, failed. It is also refused for any other refusal: Form, Target,
  Empty, ClaimedError, or a `StoryBlockedError` with no known milestone.

### Edits after a blocked refusal

`setDispatchField` from the blocked refusal works as from any refusal: back to `previewing`,
with the refusal and `dispatchSuggest` cleared and a re-preview after 400 ms. If am refuses
again, the refusal and the action come back.

### Docs

`docs/architecture.md`, the RunStore Dispatch paragraph (l.101), is updated to match:
- a story is offered (`--story`);
- `dispatchTargetLabel`;
- the story preview and the finished-story refusal (`Empty`);
- `dispatchDefaults` with `runs`;
- `prefixByMilestone` saved for story and milestone starts and merged locally;
- `StoryBlockedError` from the preview or from Start giving `refused` with `dispatchSuggest`;
- `retargetToMilestone()`.

## Error paths (summary)

| situation | state | error / type | suggest |
|---|---|---|---|
| terminal-status story | refused | `The card is done` / `Target` | null |
| story preview with zero subtasks | refused | `Nothing left to run` / `Empty` | null |
| preview `StoryBlockedError`, milestone known | refused | am's message / `StoryBlockedError` | `{id, title}` |
| preview `StoryBlockedError`, story with no milestone | refused | am's message / `StoryBlockedError` | null |
| preview `ClaimedError` | refused | am's message / `ClaimedError` | null |
| Start `StoryBlockedError` | refused (no log fields, nothing saved) | am's message / `StoryBlockedError` | as at preview |
| Start `ClaimedError` or other failure | failed (log fields) | as today | null |

## Tests

Tiers: **QML unit (domain)** is `tests/core/domain/tst_runs.qml`, for pure functions with no
store. **QML store** is `tests/core/stores/tst_run_store.qml`, where `RunStore` runs with
fake `HelperRunner` processes (`reply(proc, text, code)`). It is the only tier that can see
state transitions, the argv and the saved JSON. All tests run under `bash tests/run.sh`. No UI
test is added, because the dialog and Panel wiring belong to 2.2.

### `tst_runs.qml` (domain)

1. `dispatchMilestone`:
   - a story maps to `{id: "m1", title: "M3 Document runs"}`;
   - a milestone maps to itself;
   - a subtask maps to its root;
   - a story whose `parentId` is `""` maps to `null`;
   - a missing parent, a cycle, no cardMap, `"board"` and a non-object all map to `null`;
   - a non-string title gives `""`;
   - the result is a fresh object.
2. `dispatchLabel` covers each row of the table, including:
   - `Story "Dispatch store" (milestone "M3 Document runs")`;
   - an orphan story as `Story "T"`;
   - a done story still labelled.

### `tst_run_store.qml` (store)

3. **Label:** opening `s1` sets `dispatchTargetLabel` to
   `Story "Dispatch store" (milestone "M3 Document runs")`. `m1` gives `Milestone "M3 Document
   runs"`. `closeDispatch()` sets it back to `""`, through the extended `checkDispatchIdle`.
4. **Story preview argv and variant:** after the defaults reply, the preview argv is
   `ROOT|story|s1|--base-branch|main|--branch-prefix|old|...`. An ok story payload gives
   `ready` with the summary `2 subtasks · rooted on <base>` and integrate `""`.
5. **Prefix from the snapshot:** with a snapshot run whose `milestone_id` is `m1` and
   `branch_prefix` is `m3-live`, opening `s1` gives `form.prefix` `m3-live`. With no such run
   and `runSettings.prefixByMilestone` `{m1: "m3-map"}`, it gives `m3-map`, which beats
   `prefixHistory`.
6. **Keyed prefix saved (story):** a ready `s1` and a successful Start write
   `set-run-settings ROOT {"verify":[…],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}`.
   `runSettings.prefixByMilestone` keeps a pre-existing `{m9: "x"}` entry and gains `m1`.
7. **Keyed prefix saved (milestone, and not for subtask or board):** an `m1` start carries
   `"prefixByMilestone":{"m1":"old"}`. The existing `savedJson` property and the `bare` case
   at about l.3185 are updated to it. A `t1` start's saved JSON has no `prefixByMilestone`
   key.
8. **Retarget from a preview refusal:**
   - the `s1` preview replies `{ok:false,error:{type:"StoryBlockedError",message:"…"}}`;
   - this gives `refused`, the message verbatim, type `StoryBlockedError`, and
     `dispatchSuggest` `{id:"m1", title:"M3 Document runs"}`;
   - `retargetToMilestone()` returns `true`;
   - after it: target level `milestone` with flags `--milestone m1`, the label, `previewing`,
     a `--defaults` lookup, then after its reply a preview with argv `milestone|m1`;
   - `dispatchSuggest` is `null`.
9. **Retarget from a start refusal:**
   - a ready `s1` gets Start, and the start runner replies with a `StoryBlockedError` failure
     envelope that carries `log`, `log_tail` and `exit_code`;
   - the state is `refused` (not `failed`), with the message and type, `dispatchLog` `""`,
     `dispatchLogTail` `""`, `dispatchExitCode` `null`, and the suggest set;
   - nothing is saved: no `set-run-settings` argv, `runSettings` unchanged, and
     `dispatchStartRunners` is empty;
   - `retargetToMilestone()` opens `m1` as in test 8.
10. **Retarget refused:** `retargetToMilestone()` returns `false` and leaves every dispatch
    field unchanged in each of these states:
    - idle;
    - ready;
    - a `ClaimedError` refusal;
    - a Form refusal;
    - a Target refusal (done story);
    - `failed`;
    - a `StoryBlockedError` refusal of a story whose milestone is not in the map
      (`dispatchSuggest` `null`);
    - after `closeDispatch()` following a blocked refusal.
11. **Claimed story:**
    - a preview `ClaimedError` whose message names `r-other` gives `refused` with that message
      verbatim, type `ClaimedError`, and suggest `null`;
    - a Start `ClaimedError` from a ready story gives `failed` with the log fields, as at the
      other levels.
12. **Finished story:**
    - an `s1` preview payload with no subtasks gives `refused`, `Nothing left to run`, type
      `Empty`, and preview `null`. `dispatchStart()` returns `false`;
    - a milestone payload with no subtasks is still `ready`;
    - a story card with status `done` gives `refused`, `The card is done`, type `Target`,
      suggest `null`, and the label set.
13. **Edit after a blocked refusal:** `setDispatchField("prefix", "x")` from the blocked
    refusal gives `previewing`, `dispatchSuggest` `null`, and the error cleared. The re-preview
    after the debounce sends `--branch-prefix x`.

Existing tests that must stay green unchanged: the story opening test (test 4, about l.2642),
the start and failure tests apart from the `savedJson` updates in test 7, and
`tests/ui/tst_dispatch_flow.qml` test 22 (no suggestion when a story opens).

## Review focus hints for the planner

- A start reply that lands after `closeDispatch()` or a project switch
  (`isHereStart` is false) with `StoryBlockedError`: nothing changes, as today.
- A stored `runSettings.prefixByMilestone` that is not an object (for example `[]` or a
  string): the local merge starts from `{}` and does not throw.
- A prefix with surrounding spaces: the keyed value is the trimmed prefix, the same one sent
  as `--branch-prefix`.
- `retargetToMilestone()` called twice: the second call is refused, because the state is now
  `previewing`.
- The recorded milestone and cardMap are the ones from the opening. A board refresh while the
  dialog is open does not change where the retarget goes.

## Out of scope

- `DispatchDialog` showing `dispatchTargetLabel`, the "Dispatch the milestone instead" action
  text, and Panel calling `retargetToMilestone()` instead of `openDispatch(suggest.id)`, plus
  their `tests/ui` tests. These belong to sibling card 2.2.
- `CardDetailScreen` and `Shortcuts.qml` entry points (2.2 and later siblings).
- `Runs.dispatchPlan`, `previewSummary` and `dispatchDefaults`, the helpers `dispatch-preview.py`
  and `start-run.py`, and `viewer-state.py`. These are done (cards 1.2-1.5) and are reused
  unchanged.
- Saving a keyed prefix for subtask or board starts.
- Dispatching several stories at once (S7 l.107-109).
