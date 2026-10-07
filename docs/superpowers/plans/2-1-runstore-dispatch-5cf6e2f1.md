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

---

# 2.1 RunStore dispatch: the story target, the retarget and the keyed prefix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore`'s dispatch state machine labels its target, previews a story with the story summary, refuses a finished story, defaults the prefix from the Runs snapshot, saves the Start prefix under the milestone id, and turns `StoryBlockedError` (from the preview or from Start) into a refusal that `retargetToMilestone()` turns into a fresh milestone dispatch.

**Architecture:** Two pure helpers are added to `core/domain/runs.js` (`dispatchMilestone`, `dispatchLabel`), next to the private `_milestoneOf` walk they reuse. `core/stores/RunStore.qml` calls them from `openDispatch`, records the opening's `cardMap` and milestone card in its private `dispatchBook`, and changes four handlers in place: `dispatchPreviewReplied` (level-aware summary, finished story, blocked suggestion), `dispatchStart` (keyed prefix in `saved`), `dispatchStartReplied` (local per-key merge, blocked Start refused) and a new `retargetToMilestone()`. `docs/architecture.md` l.101 is brought in line last.

**Tech Stack:** QML (Qt 6, Quickshell `Scope`) with a `.pragma library` JavaScript domain module. Tests are QtQuickTest `TestCase` files run by `qmltestrunner`, with `HelperRunner` processes stubbed by `tests/stubs` (`reply(proc, text, code)` sets `outText` and emits `exited`).

**Spec:** `docs/superpowers/specs/2-1-runstore-dispatch-5cf6e2f1.md` (prepended above).

## Global Constraints

- Only `core/domain/runs.js`, `core/stores/RunStore.qml`, `docs/architecture.md` and the two test files `tests/core/domain/tst_runs.qml` and `tests/core/stores/tst_run_store.qml` change. No new component, no `ui/` change (S7 l.87-88). `Runs.dispatchPlan`, `previewSummary`, `dispatchDefaults` and the Python helpers are reused unchanged.
- The store imports only `core/domain` and backend helpers, never `ui`.
- Domain functions are pure and never throw; every object they return is fresh.
- Exact label formats: `Whole board`, `No card`, `Milestone "T"`, `Story "T" (milestone "M")`, `Story "T"`, `Subtask "T"`, `"T"`.
- Exact sentences: `Nothing left to run` (type `Empty`), `The card is <status>` (type `Target`), `The launch could not be read` (blank Start message), `The preview could not be read` (unchanged).
- `prefixByMilestone` is the last key of the saved JSON, after `parallelism`, and only for `story` or `milestone` starts whose milestone is known. Subtask and board saved JSON is byte-for-byte what it is today: `{"verify":[…],"allowNoVerification":…,"prefixHistory":[…],"parallelism":…}`.
- The keyed value is the trimmed prefix, the same one sent as `--branch-prefix`.
- Docstrings and comments state the contract only, with no narrative (no "now", "new", "no longer", "used to").
- `tests/architecture` must pass (no duplicated helpers, icon glyph rules), and `bash tests/run.sh` must be green apart from the pre-existing `tests/contract/test_brd_shapes.py` failures (see "How to run the tests").

## Review Focus

1. A Start reply carrying `StoryBlockedError` that lands after a project switch, or after switching away and back and opening another target (`isHereStart` false). A person expects the dialog they now see to be untouched and the runner to go. Pinned in `test_a_late_blocked_start_reply_changes_nothing` (Task 6).
2. A stored `runSettings.prefixByMilestone` that is not an object (`[]`, `"x"`, `["a"]`, `7`, `null`). A person expects the local merge to start from `{}`, not throw, and keep only the new entry. Pinned in `test_a_stored_map_that_is_not_an_object_merges_from_nothing` (Task 5).
3. A prefix typed with surrounding spaces. A person expects the keyed value to be the trimmed prefix sent as `--branch-prefix`, not the raw text. Pinned in `test_the_keyed_prefix_is_the_trimmed_one_sent` (Task 5).
4. `retargetToMilestone()` pressed twice (a double click). A person expects one milestone opening; the second call is refused because the state is `previewing`. Pinned in `test_retarget_goes_once_to_the_milestone_recorded_at_the_opening` (Task 4).
5. A board refresh while the refused dialog is open (the caller's `cardMap` replaces `m1` with a renamed card). A person expects the retarget to go to the milestone recorded at the opening, with the story's form edits dropped. Pinned in `test_retarget_goes_once_to_the_milestone_recorded_at_the_opening` (Task 4).

## How to run the tests

`bash tests/run.sh` runs pytest first and stops on a pytest failure. On this machine 4 tests in `tests/contract/test_brd_shapes.py` already fail (a `KeyError` from the installed `brd`'s export shape), so the script never reaches QML. Run the QML files directly instead; the command mirrors what `tests/run.sh` does per file:

- Domain file: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|^   Loc|TypeError|ReferenceError"`
- Store file: the same with `-input tests/core/stores/tst_run_store.qml`.
- One test: append the test name, e.g. `... -input tests/core/stores/tst_run_store.qml StoresRunStore::test_open_sets_the_target_label`. The domain `TestCase` is `DomainRuns`, the store one `StoresRunStore`.
- UI dispatch flow (must stay green): `-input tests/ui/tst_dispatch_flow.qml`.
- Architecture: `uv run --with pytest python3 -m pytest tests/architecture -q`.
- Everything at the end: `bash tests/run.sh` (10-minute timeout); Task 7 Step 4 gives the per-file fallback when it stops on the 4 `test_brd_shapes.py` failures.

Before Task 1: `tst_runs.qml` has 163 passing, `tst_run_store.qml` 191 passing.

A `TypeError` or `ReferenceError` line in a QML run is a failure even when Totals says passed, except `TypeError: Cannot read property 'width' of null` from `ui/screens/*.qml`, which UI tests already print and `tests/run.sh` filters out.

The code in this plan was dry-run task by task in a scratch copy before it was handed over: 169 domain and 208 store tests passed at the end, `tests/ui/tst_dispatch_flow.qml` 20/20, `tests/architecture` green.

---

### Task 1: `Runs.dispatchMilestone` and `Runs.dispatchLabel`

**Files:**
- Modify: `core/domain/runs.js` (insert after `_milestoneOf`, which ends at about l.936, before the `_stemOf` comment)
- Test: `tests/core/domain/tst_runs.qml` (append before the file's last `}`)

**Interfaces:**
- Consumes: the private `_milestoneOf(card, cardMap)`, `_isDispatchId(id)`, `_isObject(v)`, `_stringOr(v)`, `_isWholeNumber(v)` already in `runs.js`; the test helper `mkCard(id, depth, status, parentId, title)` already in `tst_runs.qml` (l.2457).
- Produces:
  - `Runs.dispatchMilestone(card, cardMap)` → fresh `{id: string, title: string}` or `null`.
  - `Runs.dispatchLabel(card, cardMap)` → `string`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/domain/tst_runs.qml`, just before the final `}` of the `TestCase`:

```qml
  // ---- 2.1: the dispatch target's milestone and label -------------------------------------

  // Milestone m1, its story s1, the story's subtask t1, an orphan story o1
  // (parentId ""), a story g1 whose parent is not in the map, and their map.
  function labelCards() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Dispatch store")
    var t = mkCard("t1", 2, "todo", "s1", "RunStore dispatch")
    var o = mkCard("o1", 1, "todo", "", "Orphan")
    var g = mkCard("g1", 1, "todo", "gone", "Lost")
    return { m: m, s: s, t: t, o: o, g: g, map: { m1: m, s1: s, t1: t, o1: o, g1: g } }
  }

  function test_dispatchMilestone_levels() {
    var f = labelCards()
    var m1 = '{"id":"m1","title":"M3 Document runs"}'
    compare(JSON.stringify(Runs.dispatchMilestone(f.s, f.map)), m1, "story")
    compare(JSON.stringify(Runs.dispatchMilestone(f.m, f.map)), m1, "milestone")
    compare(JSON.stringify(Runs.dispatchMilestone(f.m)), m1, "milestone without cardMap")
    compare(JSON.stringify(Runs.dispatchMilestone(f.t, f.map)), m1, "subtask")
  }

  function test_dispatchMilestone_null() {
    var f = labelCards()
    compare(Runs.dispatchMilestone(f.o, f.map), null, "a story whose parentId is empty")
    compare(Runs.dispatchMilestone(f.g, f.map), null, "a missing parent")
    var a = mkCard("a1", 1, "todo", "b1", "A")
    var b = mkCard("b1", 1, "todo", "a1", "B")
    compare(Runs.dispatchMilestone(a, { a1: a, b1: b }), null, "a cycle")
    compare(Runs.dispatchMilestone(f.s), null, "no cardMap")
    compare(Runs.dispatchMilestone("board", f.map), null, "the board")
    var values = [undefined, null, 0, "m1", [], true]
    for (var i = 0; i < values.length; i++) compare(Runs.dispatchMilestone(values[i], f.map), null, "card " + i)
    compare(Runs.dispatchMilestone(mkCard("-m", 0, "todo", null, "M"), {}), null, "an id read as a flag")
    compare(Runs.dispatchMilestone(mkCard("", 0, "todo", null, "M"), {}), null, "an empty id")
    compare(Runs.dispatchMilestone(mkCard("s1", 1, "todo", "-m", "S"), { "-m": mkCard("-m", 0, "todo", null, "M") }), null,
            "a root whose id is read as a flag")
    var root = { id: "r1", title: "R", parentId: "" }
    compare(Runs.dispatchMilestone(mkCard("s1", 1, "todo", "r1", "S"), { r1: root }), null, "a root without depth 0")
  }

  function test_dispatchMilestone_title_and_fresh() {
    var m = { id: "m1", depth: 0, status: "todo", parentId: null, title: 5 }
    var s = mkCard("s1", 1, "todo", "m1", "S")
    compare(JSON.stringify(Runs.dispatchMilestone(s, { m1: m, s1: s })), '{"id":"m1","title":""}', "a title that is not a string")
    compare(Runs.dispatchMilestone({ id: "m1", depth: 0 }).title, "", "no title key")
    var f = labelCards()
    var a = Runs.dispatchMilestone(f.s, f.map)
    var b = Runs.dispatchMilestone(f.s, f.map)
    verify(a !== b, "distinct objects")
    verify(a !== f.m, "not the card itself")
    compare(Object.keys(a).sort().join(","), "id,title", "only id and title")
    var before = JSON.stringify(f.map)
    a.title = "x"
    compare(JSON.stringify(f.map), before, "the cards are unchanged")
  }

  function test_dispatchLabel_rows() {
    var f = labelCards()
    compare(Runs.dispatchLabel("board", f.map), "Whole board", "board")
    compare(Runs.dispatchLabel(f.m, f.map), 'Milestone "M3 Document runs"', "milestone")
    compare(Runs.dispatchLabel(f.s, f.map), 'Story "Dispatch store" (milestone "M3 Document runs")', "story")
    compare(Runs.dispatchLabel(f.o, f.map), 'Story "Orphan"', "orphan story")
    compare(Runs.dispatchLabel(f.g, f.map), 'Story "Lost"', "a story whose parent is missing")
    compare(Runs.dispatchLabel(f.s), 'Story "Dispatch store"', "a story without cardMap")
    compare(Runs.dispatchLabel(f.t, f.map), 'Subtask "RunStore dispatch"', "subtask")
    compare(Runs.dispatchLabel(mkCard("t5", 5, "todo", "t1", "Deep"), f.map), 'Subtask "Deep"', "depth 5")
  }

  function test_dispatchLabel_no_card_and_odd_depths() {
    var values = [undefined, null, 0, "m1", [], true, {}, mkCard("", 0, "todo", null, "M"), mkCard("-x", 0, "todo", null, "M")]
    for (var i = 0; i < values.length; i++) compare(Runs.dispatchLabel(values[i], {}), "No card", "card " + i)
    var depths = [undefined, null, -1, 1.5, "1", NaN, Infinity]
    for (var j = 0; j < depths.length; j++) {
      compare(Runs.dispatchLabel({ id: "x1", title: "X", depth: depths[j] }, {}), '"X"', "depth " + j)
    }
  }

  function test_dispatchLabel_titles_and_status() {
    var f = labelCards()
    compare(Runs.dispatchLabel(mkCard("s2", 1, "done", "m1", "Finished story"), f.map),
            'Story "Finished story" (milestone "M3 Document runs")', "a done story is labelled")
    compare(Runs.dispatchLabel(mkCard("m2", 0, "done", null, "M2"), {}), 'Milestone "M2"', "a done milestone is labelled")
    compare(Runs.dispatchLabel({ id: "m3", depth: 0, title: 7 }, {}), 'Milestone ""', "a title that is not a string")
    var untitled = { id: "m4", depth: 0, parentId: null }
    compare(Runs.dispatchLabel(mkCard("s4", 1, "todo", "m4", null), { m4: untitled }), 'Story "" (milestone "")', "no titles")
    var before = JSON.stringify(f.map)
    Runs.dispatchLabel(f.s, f.map)
    Runs.dispatchMilestone(f.t, f.map)
    compare(JSON.stringify(f.map), before, "the inputs are unchanged")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: the six new `test_dispatchMilestone_*` / `test_dispatchLabel_*` tests FAIL with `TypeError: Property 'dispatchMilestone' of object [object Object] is not a function` (or `dispatchLabel`); the other 163 pass.

- [ ] **Step 3: Write the implementation**

In `core/domain/runs.js`, insert right after the closing `}` of `_milestoneOf` (the line before the comment `// The branch-prefix stem of a milestone title: ...`):

```js

// The milestone {id, title}, fresh, of the card _milestoneOf reaches from
// card: card itself at depth 0, a story's parent, a subtask's root. null when
// the walk gives null, the card reached does not have depth exactly 0, or its
// id is not a dispatch id. title is the card's title when it is a string, else "".
function dispatchMilestone(card, cardMap) {
  var milestone = _milestoneOf(card, cardMap)
  if (milestone === null || milestone.depth !== 0 || !_isDispatchId(milestone.id)) return null
  return { id: milestone.id, title: _stringOr(milestone.title) }
}

// The dispatch dialog's target text: `Whole board` for "board"; `No card`
// for a non-object card or one without a dispatch id; else, with T the
// card's title (a string, else ""), `Milestone "T"` at depth 0, `Story "T"
// (milestone "M")` at depth 1 with M dispatchMilestone's title (`Story "T"`
// when it is null), `Subtask "T"` at a whole depth >= 2, and `"T"` for any
// other depth. The card's status is not read.
function dispatchLabel(card, cardMap) {
  if (card === "board") return "Whole board"
  if (!_isObject(card) || !_isDispatchId(card.id)) return "No card"
  var title = _stringOr(card.title)
  if (card.depth === 0) return "Milestone \"" + title + "\""
  if (card.depth === 1) {
    var milestone = dispatchMilestone(card, cardMap)
    return milestone !== null ? "Story \"" + title + "\" (milestone \"" + milestone.title + "\")" : "Story \"" + title + "\""
  }
  if (_isWholeNumber(card.depth) && card.depth >= 2) return "Subtask \"" + title + "\""
  return "\"" + title + "\""
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `Totals: 169 passed, 0 failed` (163 + 6), no `TypeError`.

Then: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass (no duplicated helper).

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): dispatchMilestone and dispatchLabel name a dispatch target"
```

---

### Task 2: the store labels the target, records the opening and defaults the prefix from the snapshot

**Files:**
- Modify: `core/stores/RunStore.qml` (dispatch properties at l.113-125; `clearDispatchError` l.902-911; `resetDispatch` l.912-933; `openDispatch` l.934-959; `dispatchBook` QtObject at about l.1349-1354)
- Test: `tests/core/stores/tst_run_store.qml` (`checkDispatchIdle` at about l.2565; new tests appended before the file's last `}`)

**Interfaces:**
- Consumes: `Runs.dispatchMilestone(card, cardMap)` and `Runs.dispatchLabel(card, cardMap)` from Task 1; `Runs.dispatchDefaults(project, card, cardMap, runs)` (existing); `store.hasKey(map, key)` (existing, l.557).
- Produces:
  - `RunStore.dispatchTargetLabel` (string property): `Runs.dispatchLabel` of the opened target; `""` while idle.
  - `dispatchBook.cardMap` (var) and `dispatchBook.milestone` (var: the `cardMap` entry of the target's milestone, or `null`), set by every `openDispatch`, cleared by `resetDispatch`. Tasks 4-6 read them.
  - `clearDispatchError()` also clears `dispatchSuggest`.
  - Test helper `keyedSettings(map)` → the `dispatchSettings()` JSON line with `prefixByMilestone: map` added. Task 5 uses it.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, extend `checkDispatchIdle` (about l.2565). Add as its last line, after the `dispatchExitCode` compare:

```qml
    compare(store.dispatchTargetLabel, "", label + ": target label")
```

Then append before the file's last `}`:

```qml
  // ---- dispatch: story target, retarget and keyed prefix (2.1)

  // get-run-settings like dispatchSettings(), with prefixByMilestone set to map.
  function keyedSettings(map) {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true, prefixByMilestone: map }) + "\n"
  }

  // 2.1 test 3
  function test_open_sets_the_target_label() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    store.openDispatch(cards.t1, cards)
    compare(store.dispatchTargetLabel, 'Subtask "RunStore dispatch"')
    store.openDispatch("board", cards)
    compare(store.dispatchTargetLabel, "Whole board")
    store.openDispatch(null, cards)
    compare(store.dispatchTargetLabel, "No card", "a refused opening is labelled too")
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
  }

  // 2.1 test 5
  function test_story_prefix_reads_the_snapshot_then_the_keyed_map() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, keyedSettings({ m9: "m9-map" }), 0)
    store.runs = [{ id: "r-old", milestone_id: "m1", branch_prefix: "m3-old", started_at: "2026-10-01T00:00:00Z" },
                  { id: "r-live", milestone_id: "m1", branch_prefix: " m3-live ", started_at: "2026-10-06T00:00:00Z" },
                  { id: "r-other", milestone_id: "m2", branch_prefix: "m2-x", started_at: "2026-10-07T00:00:00Z" }]
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the milestone's newest snapshot run wins")
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the same default serves the milestone")

    var keyed = makeWithProject(rootA); if (!keyed) return
    reply(keyed.settingsLoadRunner.current, keyedSettings({ m1: "m3-map" }), 0)
    keyed.openDispatch(cards.s1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "the keyed map beats the prefix history")
    keyed.openDispatch(cards.t1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "a subtask reads its root milestone's entry")
  }

  // 2.1 test 12 (the done story)
  function test_a_done_story_is_refused_and_labelled() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    cards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    compare(store.openDispatch(cards.s1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: every test that calls `checkDispatchIdle` FAILs (`dispatchTargetLabel` is `undefined`, not `""`), as do `test_open_sets_the_target_label`, `test_a_done_story_is_refused_and_labelled` (label) and `test_story_prefix_reads_the_snapshot_then_the_keyed_map` (`old` instead of `m3-live`).

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) Under `property var dispatchTarget: null ...` (l.114) add:

```qml
  property string dispatchTargetLabel: "" // Runs.dispatchLabel of the opened target; "" while idle
```

and replace the `dispatchSuggest` line (l.120):

```qml
  property var dispatchSuggest: null    // a refused story's milestone {id, title}
```

with:

```qml
  property var dispatchSuggest: null    // a blocked story's milestone {id, title}, which retargetToMilestone() opens; else null
```

(b) Replace `clearDispatchError` with:

```qml
  // No refusal, failure or suggestion to show.
  function clearDispatchError() {
    store.dispatchError = ""
    store.dispatchErrorType = ""
    store.dispatchErrors = []
    store.dispatchLog = ""
    store.dispatchLogTail = ""
    store.dispatchExitCode = null
    store.dispatchSuggest = null
  }
```

(c) Replace `resetDispatch` with:

```qml
  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    dispatchBook.cardMap = null
    dispatchBook.milestone = null
    store.dispatchState = "idle"
    store.dispatchTarget = null
    store.dispatchTargetLabel = ""
    store.dispatchForm = null
    store.dispatchPreview = null
    store.clearDispatchError()
    store.dispatchRunId = ""
    store.dispatchMessage = ""
  }
```

(d) Replace `openDispatch` (comment included) with:

```qml
  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or
  // "board", with its {id: card} map, and returns whether it may be started.
  // Refused (false, nothing changes) without a project or while a start is in
  // flight. Every opening sets dispatchTargetLabel and records cardMap and
  // cardMap's entry for the target's milestone (Runs.dispatchMilestone), or
  // null. A target dispatchPlan does not offer is `refused` at once; any
  // other starts from dispatchDefaults with this project's runSettings and
  // the Runs snapshot, and looks up the default branch before anything is
  // checked.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    var milestone = Runs.dispatchMilestone(card, cardMap)
    var isMap = cardMap !== null && typeof cardMap === "object"
    dispatchBook.cardMap = cardMap
    dispatchBook.milestone = milestone !== null && isMap && store.hasKey(cardMap, milestone.id) ? cardMap[milestone.id] : null
    store.dispatchTarget = plan
    store.dispatchTargetLabel = Runs.dispatchLabel(card, cardMap)
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: store.runSettings }, card, cardMap, store.runs)
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", store.project])
    return true
  }
```

(e) Replace the `dispatchBook` QtObject (and its comment) with:

```qml
  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet; `cardMap` and `milestone` are the opening's card map
  // and its entry for the target's milestone card (null when unknown).
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property bool baseTouched: false
    property bool defaultsPending: false
    property var cardMap: null
    property var milestone: null
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `Totals: 194 passed, 0 failed` (191 + 3), no `TypeError`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_dispatch_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError" | grep -v "width' of null"`
Expected: 0 failed (test 22 still sees `dispatchSuggest` `null` on a story).

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore labels the dispatch target and defaults the prefix from the snapshot"
```

---

### Task 3: the story preview and the finished story

**Files:**
- Modify: `core/stores/RunStore.qml` (`checkDispatch` comment at about l.1018-1021; `dispatchPreviewReplied` at about l.1036-1060)
- Test: `tests/core/stores/tst_run_store.qml` (append before the file's last `}`)

**Interfaces:**
- Consumes: `Runs.previewSummary(data, level)` (existing; `level === "story"` gives `{board: false, integrate: "", summary: "<N> subtask(s) · rooted on <base>" | "Nothing left to run"}`); test helpers `dispatchStore()`, `dispatchCards()`, `defaultsOk(branch)`, `previewOk(data)`, `previewingStore()`, `ctlFail(type, message)`, `argv(proc)` (existing).
- Produces:
  - Store: an ok story preview whose summary is `Nothing left to run` gives `refused`, `dispatchError` `Nothing left to run`, `dispatchErrorType` `Empty`, `dispatchPreview` `null`.
  - Test helpers used by Tasks 4-6: `storyDryRun()`, `storyPreviewingStore()`, property `storyPreviewArgs`.

- [ ] **Step 1: Write the failing tests**

Append before the file's last `}`:

```qml
  // `am run --story s1 --dry-run` data: one level, story s1 with 2 subtasks rooted on main.
  function storyDryRun() {
    return {
      max_concurrent: 4,
      levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
        { id: "t1", title: "RunStore dispatch", status: "todo", branch: "old-t1", base: "main" },
        { id: "t2", title: "Docs", status: "todo", branch: "old-t2", base: "old-t1" }] }] }],
      already_done: [],
      integrate: null
    }
  }

  // Project A with story s1 opened and its default branch `main` read: the
  // first preview is in flight.
  function storyPreviewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string storyPreviewArgs: "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 2.1 test 4
  function test_story_preview_argv_and_story_summary() {
    var store = storyPreviewingStore(); if (!store) return
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a story is previewed")
    compare(argv(proc), tc.previewCmd + tc.storyPreviewArgs)
    reply(proc, previewOk(storyDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 subtasks · rooted on main")
    compare(store.dispatchPreview.integrate, "")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 2.1 test 12 (the preview half)
  function test_a_finished_story_preview_is_refused() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [],
      already_done: [{ kind: "story", id: "s1", title: "Dispatch store" }], integrate: null }), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "Nothing left to run")
    compare(store.dispatchErrorType, "Empty")
    compare(store.dispatchPreview, null)
    compare(store.dispatchSuggest, null)
    compare(store.dispatchStart(), false, "Start only works from ready")
    compare(store.dispatchStartRunners.length, 0)

    var milestone = previewingStore(); if (!milestone) return
    reply(milestone.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [], already_done: [], integrate: null }), 0)
    compare(milestone.dispatchState, "ready", "a milestone with nothing left keeps its behaviour")
    compare(milestone.dispatchPreview.summary, "0 levels · 0 subtasks")
  }

  // 2.1 test 11 (the preview half)
  function test_a_claimed_story_preview_names_the_other_run() {
    var store = storyPreviewingStore(); if (!store) return
    var message = "story s1 is claimed by run r-other (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchPreview, null)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `test_story_preview_argv_and_story_summary` FAILs (summary `1 level · 2 subtasks`), `test_a_finished_story_preview_is_refused` FAILs (state `ready`). `test_a_claimed_story_preview_names_the_other_run` PASSes already: it pins behaviour shared with the other levels.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, in the `checkDispatch` comment replace:

```qml
  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone or the
  // board is previewed. Waits for the defaults lookup, whose reply checks.
```

with:

```qml
  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone, a story
  // or the board is previewed. Waits for the defaults lookup, whose reply checks.
```

Replace `dispatchPreviewReplied`'s comment and its ok branch, i.e. from `// The newest preview's reply` down to the first `return` + `}` of the ok branch:

```qml
  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with its summary; am's refusal:
  // its message verbatim; anything else cannot be read.
  function dispatchPreviewReplied(stdout) {
    if (store.dispatchState !== "previewing") return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.dispatchPreview = Runs.previewSummary(envelope.data)
      store.dispatchState = "ready"
      return
    }
```

with:

```qml
  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with Runs.previewSummary for the
  // target's level, except a story with nothing left, refused as `Nothing
  // left to run` (Empty); am's refusal: its message verbatim; anything else
  // cannot be read.
  function dispatchPreviewReplied(stdout) {
    if (store.dispatchState !== "previewing") return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var level = store.dispatchTarget.level
      var preview = Runs.previewSummary(envelope.data, level)
      if (level === "story" && preview.summary === "Nothing left to run") {
        store.dispatchState = "refused"
        store.dispatchError = preview.summary
        store.dispatchErrorType = "Empty"
        return
      }
      store.dispatchPreview = preview
      store.dispatchState = "ready"
      return
    }
```

The rest of the function (the refusal branch) is unchanged in this task.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `Totals: 197 passed, 0 failed`; `test_preview_ok_goes_ready_with_summary` (milestone) still passes.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore previews a story with its summary and refuses a finished one"
```

---

### Task 4: `StoryBlockedError` at preview and `retargetToMilestone()`

**Files:**
- Modify: `core/stores/RunStore.qml` (`dispatchPreviewReplied` refusal branch; new `blockedSuggest()` and `retargetToMilestone()` after `closeDispatch`)
- Test: `tests/core/stores/tst_run_store.qml` (append before the file's last `}`)

**Interfaces:**
- Consumes: `dispatchBook.cardMap`, `dispatchBook.milestone`, `store.dispatchTargetLabel`, `clearDispatchError()` clearing `dispatchSuggest` (Task 2); `Runs.dispatchMilestone` (Task 1); `storyPreviewingStore()`, `storyPreviewArgs` (Task 3); `readyStore()`, `previewArgs`, `fire(timer)`, `ctlFail`, `checkDispatchIdle` (existing).
- Produces:
  - `RunStore.blockedSuggest()` → `{id, title}` or `null`: the suggestion a `StoryBlockedError` refusal carries. Task 6 calls it.
  - `RunStore.retargetToMilestone()` → `bool`.
  - Test helpers used by Task 6: property `blockedMessage`, `dispatchFields(store)`, `checkRetargetRefused(store, label)`.

- [ ] **Step 1: Write the failing tests**

Append before the file's last `}`:

```qml
  property string blockedMessage: "story s1 is blocked by s0 (todo); dispatch milestone m1 instead"

  // Every dispatch field, as one string to compare before and after.
  function dispatchFields(store) {
    return JSON.stringify([store.dispatchState, store.dispatchTarget, store.dispatchTargetLabel, store.dispatchForm,
                           store.dispatchPreview, store.dispatchError, store.dispatchErrorType, store.dispatchErrors,
                           store.dispatchSuggest, store.dispatchRunId, store.dispatchMessage, store.dispatchLog,
                           store.dispatchLogTail, store.dispatchExitCode])
  }

  // retargetToMilestone() returns false, changes no dispatch field and launches no lookup.
  function checkRetargetRefused(store, label) {
    var before = dispatchFields(store)
    var lookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), false, label)
    compare(dispatchFields(store), before, label + ": nothing changed")
    verify(store.dispatchDefaultsRunner.current === lookup, label + ": no lookup")
  }

  // 2.1 test 8
  function test_retarget_from_a_blocked_preview() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, tc.blockedMessage, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStart(), false, "Start stays refused")
    var storyLookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    var lookup = store.dispatchDefaultsRunner.current
    verify(lookup !== storyLookup, "a fresh --defaults lookup")
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/my proj")
    reply(lookup, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "the milestone is previewed")
  }

  // 2.1 test 10
  function test_retarget_refused_outside_a_blocked_refusal() {
    var cards = dispatchCards()
    var idle = dispatchStore(); if (!idle) return
    checkRetargetRefused(idle, "idle")
    checkDispatchIdle(idle, "idle after the refusal")

    var ready = readyStore(); if (!ready) return
    checkRetargetRefused(ready, "ready")

    var claimed = storyPreviewingStore(); if (!claimed) return
    reply(claimed.dispatchPreviewRunner.current, ctlFail("ClaimedError", "story s1 is claimed by run r-other"), 0)
    checkRetargetRefused(claimed, "ClaimedError")

    var form = dispatchStore(); if (!form) return
    form.openDispatch("board", cards)
    reply(form.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(form.dispatchErrorType, "Form")
    checkRetargetRefused(form, "Form")

    var target = dispatchStore(); if (!target) return
    var doneCards = dispatchCards()
    doneCards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    target.openDispatch(doneCards.s1, doneCards)
    compare(target.dispatchErrorType, "Target")
    checkRetargetRefused(target, "Target")

    var failed = readyStore(); if (!failed) return
    failed.dispatchStart()
    reply(failed.dispatchStartRunners[0].current, ctlFail("AmExited", "am run exited at once (exit 2)"), 0)
    compare(failed.dispatchState, "failed")
    checkRetargetRefused(failed, "failed")

    var orphan = dispatchStore(); if (!orphan) return
    var orphanCards = dispatchCards()
    orphanCards.o1 = { id: "o1", title: "Orphan", status: "todo", parentId: "", depth: 1 }
    orphan.openDispatch(orphanCards.o1, orphanCards)
    reply(orphan.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(orphan.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|o1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(orphan.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", "story o1 is blocked"), 0)
    compare(orphan.dispatchState, "refused")
    compare(orphan.dispatchErrorType, "StoryBlockedError")
    compare(orphan.dispatchSuggest, null, "no milestone to offer")
    compare(orphan.dispatchTargetLabel, 'Story "Orphan"')
    checkRetargetRefused(orphan, "a blocked story with no milestone")

    var closed = storyPreviewingStore(); if (!closed) return
    reply(closed.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(closed.closeDispatch(), true)
    checkRetargetRefused(closed, "closed after a blocked refusal")
    checkDispatchIdle(closed, "still idle")
  }

  // 2.1 test 13
  function test_an_edit_after_a_blocked_refusal_previews_again() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.setDispatchField("prefix", "x"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    checkRetargetRefused(store, "previewing after the edit")
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|x|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}', "the action comes back")
  }

  // 2.1 Review Focus 4 and 5
  function test_retarget_goes_once_to_the_milestone_recorded_at_the_opening() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    cards.m1 = { id: "m1", title: "M4 Renamed", status: "todo", parentId: "", depth: 0 }
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"', "the milestone recorded at the opening")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchForm.parallelism, 4, "the story's edits are not carried over")
    compare(store.dispatchForm.prefix, "old")
    checkRetargetRefused(store, "the second call, while previewing")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: the four new tests FAIL — `test_retarget_from_a_blocked_preview` on the `dispatchSuggest` compare (`null`), the other three with `TypeError: Property 'retargetToMilestone' of object ... is not a function` (or on the suggest compare first).

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) In `dispatchPreviewReplied`'s refusal branch, replace:

```qml
    if (message.trim() !== "") {
      store.dispatchError = message
      store.dispatchErrorType = typeof err.type === "string" ? err.type : ""
    } else {
```

with:

```qml
    if (message.trim() !== "") {
      store.dispatchError = message
      store.dispatchErrorType = typeof err.type === "string" ? err.type : ""
      if (store.dispatchErrorType === "StoryBlockedError") store.dispatchSuggest = store.blockedSuggest()
    } else {
```

and extend the function's comment's last sentence so it reads:

```qml
  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with Runs.previewSummary for the
  // target's level, except a story with nothing left, refused as `Nothing
  // left to run` (Empty); am's refusal: its message verbatim, and for a
  // StoryBlockedError the blockedSuggest() milestone; anything else cannot
  // be read.
```

(b) Right after `closeDispatch()` add:

```qml
  // The milestone a StoryBlockedError refusal offers: the recorded milestone
  // card as Runs.dispatchMilestone's {id, title} when the target is a story
  // and its milestone is known, else null.
  function blockedSuggest() {
    if (store.dispatchTarget === null || store.dispatchTarget.level !== "story" || dispatchBook.milestone === null) return null
    return Runs.dispatchMilestone(dispatchBook.milestone, dispatchBook.cardMap)
  }

  // From a blocked story's refusal (`refused` with a dispatchSuggest), opens
  // the dispatch afresh on the milestone card and cardMap recorded at the
  // story's opening and returns openDispatch's result. Refused (false,
  // nothing changes) in any other state or refusal.
  function retargetToMilestone() {
    if (store.dispatchState !== "refused" || store.dispatchSuggest === null) return false
    return store.openDispatch(dispatchBook.milestone, dispatchBook.cardMap)
  }
```

`openDispatch` resets `dispatchBook` before it reads its arguments again, but both arguments are evaluated before the call, so the recorded values are the ones passed.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `Totals: 201 passed, 0 failed`, no `TypeError`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_dispatch_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError" | grep -v "width' of null"`
Expected: 0 failed.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a blocked story preview offers its milestone through retargetToMilestone"
```

---

### Task 5: Start saves the prefix under the milestone id and merges it locally

**Files:**
- Modify: `core/stores/RunStore.qml` (`dispatchStart` at about l.1086-1107; the ok branch of `dispatchStartReplied` at about l.1118-1145; new `mergedPrefixes(stored, entry)` before `dispatchStart`)
- Test: `tests/core/stores/tst_run_store.qml` (the `savedJson` property at about l.3041; the `bare` expectation in `test_prefix_history_dedups_and_caps_at_20` at about l.3184-3186; new tests appended before the file's last `}`)

**Interfaces:**
- Consumes: `dispatchBook.milestone` (Task 2); `keyedSettings(map)` (Task 2); `storyPreviewingStore()`, `storyDryRun()`, `storyPreviewArgs` (Task 3); `readyStore()`, `startOk(runId, message)`, `startCmd`, `viewerCmd`, `fire` (existing).
- Produces:
  - `saved` (and so `runner.savedJson`) carries `prefixByMilestone: {<milestone id>: <trimmed prefix>}` as its last key for a story or milestone start whose milestone is known.
  - `RunStore.mergedPrefixes(stored, entry)` → a fresh object: `stored`'s own entries when it is a non-array object, then `entry`'s.
  - Test helper `storyReadyStore()`, used by Task 6.

- [ ] **Step 1: Write the failing tests**

(a) Replace the `savedJson` property (about l.3041):

```qml
  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4}'
```

with:

```qml
  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}'
```

(b) In `test_prefix_history_dedups_and_caps_at_20`, replace the `bare` expectation:

```qml
    compare(argv(bareRunner.current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4}')
```

with:

```qml
    compare(argv(bareRunner.current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4,"prefixByMilestone":{"m1":"m3"}}')
```

(c) Append before the file's last `}`:

```qml
  // Project A with story s1's preview landed: Start is allowed.
  function storyReadyStore() {
    var store = storyPreviewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    return store
  }

  // 2.1 test 6
  function test_a_story_start_saves_the_prefix_under_its_milestone() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, keyedSettings({ m9: "x" }), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + tc.storyPreviewArgs)
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" +
            '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}')
    var map = store.runSettings.prefixByMilestone
    compare(Object.keys(map).sort().join(","), "m1,m9", "merged locally")
    compare(map.m9, "x", "the stored entry is kept")
    compare(map.m1, "old")
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
  }

  // 2.1 test 7
  function test_milestone_starts_key_the_prefix_and_subtask_or_board_starts_do_not() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(runner.current.command[4], tc.savedJson, "a milestone start keys its own id")
    compare(store.runSettings.prefixByMilestone.m1, "old")

    var plain = '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4}'
    var cards = dispatchCards()
    var subtask = dispatchStore(); if (!subtask) return
    subtask.openDispatch(cards.t1, cards)
    reply(subtask.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(subtask.dispatchStart(), true)
    var subtaskRunner = subtask.dispatchStartRunners[0]
    reply(subtaskRunner.current, startOk("r-2", ""), 0)
    compare(argv(subtaskRunner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a subtask start keys nothing")
    compare(subtask.runSettings.prefixByMilestone, undefined, "nothing keyed locally")

    var board = dispatchStore(); if (!board) return
    board.openDispatch("board", cards)
    reply(board.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    board.setDispatchField("prefix", "old")
    fire(board.dispatchDebounceTimer)
    reply(board.dispatchPreviewRunner.current, previewOk({ board: true, levels: [] }), 0)
    compare(board.dispatchState, "ready")
    compare(board.dispatchStart(), true)
    var boardRunner = board.dispatchStartRunners[0]
    reply(boardRunner.current, startOk("r-3", ""), 0)
    compare(argv(boardRunner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a board start keys nothing")
  }

  // 2.1 Review Focus 2
  function test_a_stored_map_that_is_not_an_object_merges_from_nothing() {
    var stored = [[], "x", ["a"], 7, null]
    for (var i = 0; i < stored.length; i++) {
      var store = makeWithProject(rootA); if (!store) return
      reply(store.settingsLoadRunner.current, keyedSettings(stored[i]), 0)
      var cards = dispatchCards()
      store.openDispatch(cards.s1, cards)
      reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
      compare(store.dispatchState, "started", "stored " + i)
      compare(Object.keys(store.runSettings.prefixByMilestone).join(","), "m1", "stored " + i + ": only the new entry")
      compare(store.runSettings.prefixByMilestone.m1, "old", "stored " + i)
    }
  }

  // 2.1 Review Focus 3
  function test_the_keyed_prefix_is_the_trimmed_one_sent() {
    var store = storyPreviewingStore(); if (!store) return
    store.setDispatchField("prefix", "  m3-spaced ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3-spaced", "sent trimmed")
    compare(runner.savedJson, '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3-spaced","old"],' +
                              '"parallelism":4,"prefixByMilestone":{"m1":"m3-spaced"}}')
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.runSettings.prefixByMilestone.m1, "m3-spaced")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected FAIL: the four new tests (no `prefixByMilestone` in the saved JSON; `Object.keys(undefined)` in Review Focus 2 shows as a `TypeError`), plus the existing tests that compare against `savedJson` or the `bare` string: `test_start_ok_with_run_id_emits_and_saves`, `test_prefix_history_dedups_and_caps_at_20`, `test_start_result_belongs_to_its_project`, `test_start_reply_after_switching_away_and_back_is_not_here`.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`:

(a) Just before the `dispatchStart` comment add:

```qml
  // A fresh {milestone id: prefix} map: stored's own entries when stored is
  // an object that is not an array, then entry's, which override them, as
  // set-run-settings merges prefixByMilestone.
  function mergedPrefixes(stored, entry) {
    var merged = stored !== null && typeof stored === "object" && !Array.isArray(stored) ? store.copyMap(stored) : {}
    for (var id in entry) merged[id] = entry[id]
    return merged
  }
```

(b) Replace `dispatchStart` (comment included) with:

```qml
  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), the parallelism and, for a story or milestone whose milestone
  // card is known, prefixByMilestone {<milestone id>: prefix sent}.
  function dispatchStart() {
    if (store.dispatchState !== "ready") return false
    var form = store.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(store.runSettings.prefixHistory) ? store.runSettings.prefixHistory : []
    for (var i = 0; i < stored.length && history.length < 20; i++) {
      var p = stored[i]
      if (typeof p === "string" && p.trim() !== "" && p !== prefix) history.push(p)
    }
    var saved = { verify: store.dispatchCommands(form), allowNoVerification: form.allowNoVerification === true,
                  prefixHistory: history, parallelism: form.parallelism }
    var level = store.dispatchTarget.level
    if ((level === "story" || level === "milestone") && dispatchBook.milestone !== null) {
      var keyed = {}
      keyed[dispatchBook.milestone.id] = prefix
      saved.prefixByMilestone = keyed
    }
    var runner = dispatchStartC.createObject(store, { madeFor: store.project, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    store.dispatchState = "starting"
    runner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
    return true
  }
```

(c) In `dispatchStartReplied`'s ok branch, replace:

```qml
        for (var key in saved) settings[key] = saved[key]
```

with:

```qml
        for (var key in saved) {
          settings[key] = key === "prefixByMilestone" ? store.mergedPrefixes(settings.prefixByMilestone, saved[key]) : saved[key]
        }
```

and in its comment replace `the saved values in runSettings,` with `the saved values in runSettings (prefixByMilestone merged per milestone id),`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `Totals: 205 passed, 0 failed`, no `TypeError`.

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/tst_dispatch_flow.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError" | grep -v "width' of null"`
Expected: `Totals: 20 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a story or milestone start saves its prefix under the milestone id"
```

---

### Task 6: `StoryBlockedError` at Start is a refusal

**Files:**
- Modify: `core/stores/RunStore.qml` (the failure branch and comment of `dispatchStartReplied`)
- Test: `tests/core/stores/tst_run_store.qml` (append before the file's last `}`)

**Interfaces:**
- Consumes: `store.blockedSuggest()` and `retargetToMilestone()` (Task 4); `storyReadyStore()` (Task 5); `blockedMessage`, `checkDispatchIdle`, `previewArgs`, `spyC`, `ctlFail`, `dispatchSettings()` (existing / Task 4).
- Produces: a here start reply whose `error.type` is `StoryBlockedError` gives `refused` with `dispatchError` (am's message, else `The launch could not be read`), `dispatchErrorType` `StoryBlockedError`, empty log fields, `dispatchExitCode` `null`, `dispatchSuggest` `blockedSuggest()`; nothing saved, runner dropped.

- [ ] **Step 1: Write the failing tests**

Append before the file's last `}`:

```qml
  // A StoryBlockedError start failure, with the log fields start-run.py adds.
  function startBlocked() {
    return JSON.stringify({ ok: false, error: { type: "StoryBlockedError", message: tc.blockedMessage },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: story s1 is blocked" }) + "\n"
  }

  // 2.1 test 9
  function test_retarget_from_a_blocked_start() {
    var store = storyReadyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    var settingsBefore = JSON.stringify(store.runSettings)
    compare(store.dispatchStart(), true)
    var seq = store.snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startBlocked(), 0)
    compare(store.dispatchState, "refused", "a blocked story is refused, not failed")
    compare(store.dispatchError, tc.blockedMessage)
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(store.dispatchLog, "")
    compare(store.dispatchLogTail, "")
    compare(store.dispatchExitCode, null)
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStartRunners.length, 0, "the runner is dropped: no set-run-settings")
    compare(JSON.stringify(store.runSettings), settingsBefore, "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays")
    compare(spy.count, 0)
    compare(store.snapshotRunner.seq, seq, "no re-snapshot")
    compare(store.dispatchStart(), false, "Start stays refused")
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs)

    var blank = storyReadyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, ctlFail("StoryBlockedError", "  "), 0)
    compare(blank.dispatchState, "refused")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(blank.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
  }

  // 2.1 test 11 (the start half)
  function test_a_claimed_story_start_fails_with_the_log() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, JSON.stringify({ ok: false,
      error: { type: "ClaimedError", message: "story s1 is claimed by run r-other" },
      log: "/home/u/.local/state/am-run.log", exit_code: 1, log_tail: "claimed" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "story s1 is claimed by run r-other")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "claimed")
    compare(store.dispatchExitCode, 1)
    compare(store.dispatchSuggest, null)
    compare(store.retargetToMilestone(), false)
  }

  // 2.1 Review Focus 1
  function test_a_late_blocked_start_reply_changes_nothing() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    store.project = rootB
    checkDispatchIdle(store, "B after the switch")
    reply(proc, startBlocked(), 0)
    checkDispatchIdle(store, "B after A's blocked reply")
    compare(store.dispatchStartRunners.length, 0, "the runner goes")

    var back = storyReadyStore(); if (!back) return
    back.dispatchStart()
    var backProc = back.dispatchStartRunners[0].current
    back.project = rootB
    back.project = rootA
    reply(back.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(back.openDispatch(cards.m1, cards), true)
    reply(backProc, startBlocked(), 0)
    compare(back.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(back.dispatchError, "")
    compare(back.dispatchErrorType, "")
    compare(back.dispatchSuggest, null)
    compare(back.dispatchTargetLabel, 'Milestone "M3 Document runs"')
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `test_retarget_from_a_blocked_start` FAILs (state `failed`, not `refused`). `test_a_claimed_story_start_fails_with_the_log` and `test_a_late_blocked_start_reply_changes_nothing` PASS already: they pin behaviour this task must keep.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, in `dispatchStartReplied` replace the failure block:

```qml
    if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      store.dispatchState = "failed"
      store.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      store.dispatchErrorType = isErr && typeof err.type === "string" ? err.type : ""
      store.dispatchLog = typeof failure.log === "string" ? failure.log : ""
      store.dispatchLogTail = typeof failure.log_tail === "string" ? failure.log_tail : ""
      store.dispatchExitCode = typeof failure.exit_code === "number" ? failure.exit_code : null
    }
    store.dropStartRunner(runner)
```

with:

```qml
    if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      var type = isErr && typeof err.type === "string" ? err.type : ""
      var blocked = type === "StoryBlockedError"
      store.dispatchState = blocked ? "refused" : "failed"
      store.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      store.dispatchErrorType = type
      store.dispatchLog = !blocked && typeof failure.log === "string" ? failure.log : ""
      store.dispatchLogTail = !blocked && typeof failure.log_tail === "string" ? failure.log_tail : ""
      store.dispatchExitCode = !blocked && typeof failure.exit_code === "number" ? failure.exit_code : null
      store.dispatchSuggest = blocked ? store.blockedSuggest() : null
    }
    store.dropStartRunner(runner)
```

and replace the function's comment with:

```qml
  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values in runSettings (prefixByMilestone
  // merged per milestone id), a re-snapshot and dispatchStarted(id or null);
  // a StoryBlockedError gives `refused` with am's message, no log fields and
  // the blockedSuggest() milestone; anything else gives `failed` with what
  // the helper said. After any successful start, wherever it was made, the
  // same runner writes the saved values for the project it was made in.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError"`
Expected: `Totals: 208 passed, 0 failed`; `test_start_failure_goes_failed_with_log`, `test_start_unreadable_goes_failed` and `test_failed_then_change_previews_again` still pass.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a blocked story at Start is refused with the milestone retarget"
```

---

### Task 7: `docs/architecture.md` and full verification

**Files:**
- Modify: `docs/architecture.md:101` (the RunStore "Dispatch (S3 3.1)" paragraph)

**Interfaces:**
- Consumes: every name produced by Tasks 1-6.
- Produces: documentation only.

- [ ] **Step 1: Edit the opening sentence**

In `docs/architecture.md`, replace:

```
A story, a finished card or no card goes straight to `refused` (`dispatchErrorType` `Target`, `dispatchSuggest` the story's milestone); otherwise `dispatchTarget` is `Runs.dispatchPlan`'s result, `dispatchForm` (`{base, prefix, verify, parallelism, allowNoVerification}`) starts from `Runs.dispatchDefaults` with `runSettings` -- the current project's whole `get-run-settings` reply, `{}` until it lands and after a project switch -- and
```

with:

```
Every opening sets `dispatchTargetLabel` to `Runs.dispatchLabel` (`Milestone "T"`, `Story "T" (milestone "M")`, `Subtask "T"`, `Whole board`; `""` while idle) and records the card map and the target's milestone card. A finished card or no card goes straight to `refused` (`dispatchErrorType` `Target`, `The card is <status>`); otherwise `dispatchTarget` is `Runs.dispatchPlan`'s result -- a milestone (`--milestone`), a story (`--story`), a subtask (`--card`) or the board --, `dispatchForm` (`{base, prefix, verify, parallelism, allowNoVerification}`) starts from `Runs.dispatchDefaults` with `runSettings` -- the current project's whole `get-run-settings` reply, `{}` until it lands and after a project switch -- and the Runs snapshot `runs` (the prefix is the newest snapshot run of the target's milestone, then `runSettings.prefixByMilestone[<milestone id>]`, then the prefix history, then the milestone's stem), and
```

- [ ] **Step 2: Edit the preview sentence**

Replace:

```
and a milestone or the board runs `dispatch-preview.py ROOT TARGET [--base-branch B] --branch-prefix P --max-concurrent N [--verify CMD]... [--allow-no-verification]` on `dispatchPreviewRunner` (latest wins; every change cancels it), giving `ready` with `dispatchPreview` (`Runs.previewSummary`) or `refused` with am's message verbatim (`The preview could not be read` when there is none).
```

with:

```
and a milestone, a story or the board runs `dispatch-preview.py ROOT TARGET [--base-branch B] --branch-prefix P --max-concurrent N [--verify CMD]... [--allow-no-verification]` on `dispatchPreviewRunner` (latest wins; every change cancels it), giving `ready` with `dispatchPreview` (`Runs.previewSummary` for the target's level: a story reads `N subtasks · rooted on <branch>`, with no Integrate line) or `refused` with am's message verbatim (`The preview could not be read` when there is none); a story with nothing left is `refused` with `Nothing left to run` (`Empty`). A `StoryBlockedError`, from the preview or from Start, is `refused` -- never `failed`: no log fields, nothing saved -- with am's message and `dispatchSuggest` the story's milestone `{id, title}` (`null` when it is unknown); every other refusal leaves `dispatchSuggest` `null`, and a field change clears it. `retargetToMilestone()` works only from that refusal: it opens the dispatch afresh on the milestone and card map recorded at the story's opening (defaults, `--defaults` lookup, milestone preview) and returns false in any other state.
```

- [ ] **Step 3: Edit the start sentences**

Replace:

```
a failed one sets `failed` with
```

with:

```
any other failed one sets `failed` with
```

Then replace:

```
`prefixHistory` (the prefix first, at most 20) and `parallelism`, fixed when Start was pressed,
```

with:

```
`prefixHistory` (the prefix first, at most 20), `parallelism` and, for a story or milestone start whose milestone is known, `prefixByMilestone` (`{<milestone id>: prefix}`, the store's own `runSettings` merging it per milestone id at once), fixed when Start was pressed,
```

- [ ] **Step 4: Run the full verification**

Run: `bash tests/run.sh` (timeout 10 minutes).
Expected: green. If it stops on the 4 pre-existing `tests/contract/test_brd_shapes.py` failures only (this card touches no Python), run every QML file:

```bash
for f in $(find tests -name 'tst_*.qml' | sort); do echo "== $f"; QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input "$f" 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError|non-existent|Unable to assign|is not a function" | grep -v "width' of null"; done
```

Expected: every `Totals:` line shows `0 failed` and no `TypeError` / `ReferenceError` / `is not a function` line, except `tests/ui/tst_plugin_dir.qml`, which fails 1 test when run from the worktree rather than from `run.sh`'s mirror (it checks the mirror's path; it fails the same way before this card). Then `uv run --with pytest python3 -m pytest tests/architecture -q` passes.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: RunStore dispatch covers the story target, the retarget and the keyed prefix"
```

---

## Self-review (planner)

- **Spec coverage.** Domain helpers → Task 1 (tests 1-2). `dispatchTargetLabel`, `dispatchBook` record, `clearDispatchError` clearing the suggest, refused path no longer copying `plan.suggest`, `dispatchDefaults` with `store.runs`, `checkDispatchIdle` → Task 2 (tests 3, 5, 12 done-story). Level-aware preview, finished story `Empty`, claimed preview → Task 3 (tests 4, 11 preview, 12 preview). Blocked preview suggest, `retargetToMilestone()` and its refusals, edit after a blocked refusal → Task 4 (tests 8, 10, 13). Keyed `saved` for story/milestone only, last key, local merge, `savedJson` and `bare` updates → Task 5 (tests 6, 7). Blocked Start refused with no log fields, nothing saved, runner dropped; claimed Start still `failed` → Task 6 (tests 9, 11 start). Docs paragraph → Task 7. Test 10's "failed" case uses an `AmExited` start failure, available since before Task 4.
- **Placeholders.** None: every step has its code or exact text; Task 5 Step 4 names the one fallback and its exact code.
- **Type consistency.** `dispatchMilestone`/`dispatchLabel` (Task 1) are the names Task 2 calls; `dispatchBook.cardMap`/`milestone` (Task 2) are read by `blockedSuggest()` (Task 4) and `dispatchStart` (Task 5); `blockedSuggest()` (Task 4) is called in Task 6; test helpers `keyedSettings` (2), `storyDryRun`/`storyPreviewingStore`/`storyPreviewArgs` (3), `blockedMessage`/`dispatchFields`/`checkRetargetRefused` (4), `storyReadyStore` (5) are each defined before use.
- **Review Focus.** Each of the five lines has a named test in its owning task (Tasks 4, 5, 6).
- **Known risk.** The local merge reads `runSettings.prefixByMilestone` back through a `var` property; tests do not assert key order there (they sort keys). The `["a"]` case of Review Focus 2 passed in the dry run, so `Array.isArray` sees the list.
<!-- task-pipeline: validated -->
