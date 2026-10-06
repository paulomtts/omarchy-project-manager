# 1.2 runs.js: the story target and its preview summary — design

Card: `a2a74eda` (subtask of story `5c0430d9` "Story dispatch logic and backend", milestone
`5d48ef7a` "Dispatch at story level"). Blocked by `d9f3d392` (1.1, done: the contract test
that records the installed `am run --story` payloads).

Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (below,
"the parent spec"). Previous pins of the functions changed here:
`docs/superpowers/specs/1-1-runs-js-5eb7ec0c.md` (S3 `dispatchPlan`) and
`docs/superpowers/specs/1-2-runs-js-45cc9067.md` (S3 `previewSummary`). Everything those two
pin and this spec does not change stays as pinned.

## Goal

Two pure functions in `core/domain/runs.js` learn the story level:

1. `dispatchPlan(card, cardMap)` OFFERS a story card as an `am run --story ID` target instead
   of refusing it with its milestone as a suggestion.
2. `previewSummary(dryRunData, level)` reads an `am run --story … --dry-run` payload when the
   caller says the target is a story: `N subtasks · rooted on <branch>`, no Integrate line, no
   "stories already done" count, and `Nothing left to run` for a story with nothing to run.

## Inherited constraints

| constraint | source |
|---|---|
| A story is dispatched with `am run --story ID`; subtask, milestone and board unchanged | parent spec, Goal table, lines 27-34 |
| Story preview summary reads `N subtasks · rooted on <branch>`, `<branch>` = the first subtask's `base`; no Integrate line (`integrate` is null); no "stories already done" count | parent spec, Behaviour (story), lines 45-48 |
| A finished story shows "Nothing left to run" | parent spec, lines 62-64 |
| Cards in `done`, `merged`, `canceled`, `archived` are refused with the reason, at every level | parent spec, lines 65-66 |
| `dispatchPlan` returns the story command for a story card, replacing the "suggest its milestone" result; `previewSummary` gains the story variant | parent spec, Architecture, lines 78-80 |
| `tst_runs.qml` covers `dispatchPlan` for a story (and terminal-status stories) and the `previewSummary` story variant | parent spec, Testing, lines 97-98 |
| `runs.js` is `.pragma library`, pure, never throws, own-key lookups only, ES5 (`var`, no arrow functions) | `runs.js` header and the S3 dispatch section comment, `core/domain/runs.js:862-869` |
| Layering per `docs/architecture.md`; `tests/architecture` stays green (no new component here) | card description |
| Comments and docstrings state the contract only, no narrative | card description |
| `bash tests/run.sh` is green with this subtask alone (stacked on 1.1) | card description; milestone card rules |

### Deviation from the parent spec's notation (deliberate)

The parent spec (line 78) and the card write the result as `{command:'story',
flags:{story:id}}`. The plan shape S3 merged, and every consumer of it, uses `flags` as an
ARRAY of argv words: `_offeredPlan` (`runs.js:891-893`), the `checkPlan` test helper
(`tst_runs.qml:2462-2471`, asserts `Array.isArray(flags)` and the exact key set), and
`RunStore.dispatchTargetArgs` (`core/stores/RunStore.qml:975-979`, reads `plan.flags[1]` as the
target id). This spec keeps the array convention: `flags` is `["--story", id]`. The parent
spec's `{story:id}` is read as "the story flag carrying the card id", which the array encodes.
With it, `dispatchTargetArgs` yields `["story", id]` with no store change.

## Behaviour

### `dispatchPlan(card, cardMap)`

The decision order of S3 (`1-1-runs-js-5eb7ec0c.md`) is kept; only the story branch changes.

1. `"board"` → the board plan (unchanged).
2. Not an object, or no valid dispatch id → refused, level `""`, `No card to dispatch`
   (unchanged).
3. `depth` not a whole number ≥ 0 → refused, level `""`, `The card's level is unknown`
   (unchanged).
4. Level from depth: 0 milestone, 1 story, ≥ 2 subtask (unchanged).
5. Status exactly one of `done`, `merged`, `canceled`, `archived` (`Board.isFinishedStatus`)
   → refused at that level with `The card is <status>` and `suggest: null` (unchanged; this
   already covers stories and stays pinned by `test_dispatchPlan_finished`).
6. **Story (depth 1), not finished → offered:**

   ```
   { command: "story", flags: ["--story", card.id], level: "story",
     offered: true, reason: "", suggest: null }
   ```

   `card.parentId` and `cardMap` no longer affect a story's plan: a story with no parent, a
   non-string parent, or a parent missing from / not an object in `cardMap` is offered the same
   way. (Resolving the milestone is `dispatchDefaults`' and the store's job, not this
   function's.)
7. Milestone → `["--milestone", id]`, subtask → command `card`, `["--card", id]` (unchanged).

Every returned plan is a fresh object with a fresh `flags` array (unchanged rule, now also for
the story plan). The sentence `A story is dispatched through its milestone` disappears from
`runs.js`; no plan carries a non-null `suggest` any more. The `suggest` key itself stays in the
plan shape (the key set `command, flags, level, offered, reason, suggest` is unchanged) because
the store and dialog read it; what replaces the milestone offer for a *blocked* story is the
store's retarget, card 2.1.

The comment above `dispatchPlan` states the new contract (a story is offered with
`--story`; a finished card is refused at every level) and drops the "story is refused with
its milestone as the suggestion" sentence. The section header's pointer to
`1-1-runs-js-5eb7ec0c.md` stays and this spec is added next to it.

### `previewSummary(dryRunData, level)`

A second, optional argument `level` selects the variant. Only the exact string `"story"`
selects the story variant; `undefined`, `"milestone"`, `"board"`, `"Story"`, `" story"`, `1`
and anything else leave the S3 behaviour exactly as pinned in `1-2-runs-js-45cc9067.md`
(milestone/board chosen from the payload, `board === true`).

Why an argument and not the payload's shape: a story payload (`integrate: null`, one level,
one story) is indistinguishable from a milestone payload whose `integrate` is null or absent,
and S3 already pins that such a milestone payload gives the milestone summary with no
Integrate line (`tst_runs.qml:3065-3083`, `test_previewSummary_integrate`). The caller knows
the target (`RunStore.dispatchTarget.level`); passing it is card 2.1's change
(`RunStore.qml:1043`), not this one's.

Story variant, for `dryRunData` the envelope's `data` (never the `{ok, data}` envelope):

- **Unreadable** — `dryRunData` not an object, or `levels` not an array → `{board: false,
  integrate: "", summary: ""}`, the same fresh result as S3 (`_unreadablePreview`). `Nothing
  left to run` is never given for an unreadable payload.
- **Subtask count `S`** — the object entries of `levels[].stories[].subtasks`, skipping
  non-object levels and stories (the same count as S3's `_planSubtasks`). All levels count,
  though `am` gives at most one.
- **`S === 0`** → `{board: false, integrate: "", summary: "Nothing left to run"}`.
- **`S > 0`** → `summary` is `<S> subtask` when `S === 1`, else `<S> subtasks`; then
  ` · rooted on <base>` (U+00B7 between single spaces) when the **first counted subtask** (the
  first object subtask, walking object levels, then object stories, then object subtasks, in
  array order) has a `base` that is a string non-blank after trimming; `<base>` is that string
  trimmed. Otherwise the summary is the count alone. Only the first counted subtask is
  consulted: a blank first base does not fall back to the second subtask's.
- **Never in the story variant:** an Integrate line (`integrate` is `""` even when the payload
  carries an `integrate` object with a branch), a stories-already-done count (`already_done`
  is not read at all), and `board: true` (the result's `board` is `false` even if the payload
  has `board: true`).
- Keys of the result are exactly `board, integrate, summary`; the object is fresh on every
  call; the input is not modified.

The comment above `previewSummary` adds the story variant and the meaning of `level`; the
section header's pointer gains this spec.

### Payload shapes the story variant is built from

From the installed `am` as recorded in 1.1 (`tests/contract/test_am_shapes.py:174`,
`STORY_DATA_KEYS`, and `test_story_dry_run_previews_one_level_with_no_integrate`, lines
262-278) and from `am`'s own code (`agent-manager/src/agent_manager/cli.py` `dry_run_story`,
`dag.compute_levels`):

- **Story with work** (recorded in 1.1): keys exactly `already_done, integrate, levels,
  max_concurrent`; `max_concurrent: 1`; `integrate: null`; `already_done: []`; one level
  `{level: 0, concurrent: 1, stories: [{story, title, root, subtasks: [...]}]}`; each subtask
  `{id, title, status, branch, base}`; the first subtask's `base` is the base branch
  (`master` in the contract board), the second's `base` is the first's `branch`.
- **Partly done story**: `levels[0].stories[0].subtasks` lists only the remaining subtasks;
  the first one's `base` is the done subtask's branch it stacks on, which is what the summary
  shows. `already_done` holds `kind: "subtask"` entries (not counted).
- **Finished story** (no remaining subtasks; not recorded in 1.1, read from `am`'s source:
  `compute_levels` drops a story with no remaining subtasks, and `already_done_entries` lists it
  as one `kind: "story"` entry): `levels: []`, `already_done: [{kind: "story", id, title}]`,
  `integrate: null`, `max_concurrent: 1`. The parent spec's precondition (lines 12-18) is
  about `--story` existing; this shape is pinned only by the fixture below, so a future `am`
  change to it would show up in 1.1's contract tests first if they are extended, not here.

## Fallout in other tests (required for a green suite)

Offering a story changes what the store and the UI do with one, so tests that pin the S3
refusal break. This card updates them to the new contract and nothing more; no production
file other than `core/domain/runs.js` changes.

- `tests/core/stores/tst_run_store.qml`
  - `test_open_story_is_refused_with_its_milestone` (#4, ~line 2642): becomes
    `test_open_story_is_offered_with_the_story_flag`: `openDispatch(cards.s1, cards)` returns
    `true`, `dispatchState` is `"previewing"`, `dispatchTarget` has level `"story"`, command
    `"story"`, flags `["--story", "s1"]`, `dispatchSuggest` is `null`, `dispatchError` is `""`,
    a form exists, and the defaults lookup runner is running.
  - `test_close_and_reopen_drop_the_pending_lookup` (~line 2672),
    `test_set_unknown_field_or_while_idle_is_refused` (#19, ~line 3011) and
    `test_start_refused_unless_ready` (~line 3060, the `"refused"` step) use the story only to
    obtain a refused target. They switch to the done card `cards.d1` (refused with `The card is
    done`), keeping their intent.
- `tests/ui/tst_dispatch_flow.qml`
  - `test_a_story_offers_its_milestone_and_the_offer_reopens_on_it` (#22, ~line 141) and
    `test_a_story_whose_milestone_left_the_board_offers_nothing` (~line 161): a story no
    longer produces the milestone offer, so both are replaced by one test: Dispatch on story
    `s1` opens the dialog in `"previewing"` with `Target   Story "Story one"` and the offer
    (`dispatchSuggest`) not visible. The blocked-story retarget action and its UI tests are
    cards 2.1-2.3. Update the file's header comment line that mentions "the story's milestone
    offer".
- `tests/ui/tst_shortcuts.qml` `test_escape_closes_an_open_dispatch_before_anything_else`
  (~line 727): `openDispatch` on story `s1` now returns `true` with `dispatchState`
  `"previewing"`; the rest of the test (Escape closes the dialog first) is unchanged.
- `tests/ui/components/tst_dispatch_dialog.qml` drives the dialog with literal props (a refused
  story target with the old sentence) and does not call `runs.js`; it is left unchanged.

Any other test that turns red under `bash tests/run.sh` because a story is now offered is
updated the same way (assert the offered story, or move a "needs a refused target" test to a
done card) and listed in the plan.

## Tests (TDD: written first, failing, then the code)

All in the QML tier, `tests/core/domain/tst_runs.qml` unless stated, run by
`bash tests/run.sh` through `qmltestrunner`. The tier: `runs.js` is a `.pragma library` QML-JS
module with no I/O, so its unit tests live in the QML domain tier where it is imported
directly; the store/UI tests above are their existing tiers.

New fixtures in `tst_runs.qml`, next to `dryRunMilestone()`:

- `dryRunStory()` — the 1.1 recorded shape: `{max_concurrent: 1, levels: [{level: 0,
  concurrent: 1, stories: [{story: "s1", title: "Story one", root: "master", subtasks:
  [planSubtask("p", "c1", "master"), planSubtask("p", "c2", "p-c1")]}]}], already_done: [],
  integrate: null}`.
- `dryRunStoryDone()` — `{max_concurrent: 1, levels: [], already_done: [{kind: "story", id:
  "s1", title: "Story one"}], integrate: null}`.

`dispatchPlan` (rewrite `test_dispatchPlan_story`, keep the rest):

1. `test_dispatchPlan_story` — `mkCard("s1", 1, "todo", "m1", "Story")` with a cardMap holding
   `m1` → `checkPlan(..., true, "story", "story", ["--story", "s1"], "", null, ...)`; the same
   for statuses `in_progress`, `blocked`, `undefined`.
2. `test_dispatchPlan_story_ignores_parent` — no cardMap; cardMap without `m1`; `m1` not an
   object; parentId `null`, `""`, `5`, `"__proto__"` → all the same offered story plan, all
   `suggest: null`.
3. `test_dispatchPlan_story_fresh` — two calls give distinct objects and distinct `flags`
   arrays; pushing onto / overwriting `flags[1]` of one does not leak into the next call;
   `cardMap` unchanged (`JSON.stringify` before/after).
4. `test_dispatchPlan_finished` — kept as is (depth 1 included for all four statuses, `The
   card is <status>`, `suggest: null`); add one line that a finished story is refused even with
   a parent in cardMap (no suggest). Covers the "refused at every level" requirement.
5. `test_dispatchPlan_shape` — kept; its story input now yields an offered plan, and the
   "distinct flags arrays" check now exercises a non-empty story `flags`.
6. Existing tests whose story assertions pin the old refusal (`test_dispatchPlan_garbage` loop
   over cardMaps, ~2592-2599; `test_dispatchPlan_proto_ids`, ~2602-2610;
   `test_dispatchPlan_odd_titles`, ~2612-2618) are rewritten to assert the offered story plan
   (cardMap and parent title no longer matter), or removed where their only subject was the
   suggestion's title, with the plan saying which.

`previewSummary` story variant:

7. `test_previewSummary_story` — `previewSummary(dryRunStory(), "story")` →
   `checkSummary(r, false, "2 subtasks · rooted on master", "", ...)`; fresh object per
   call; mutating one result does not leak.
8. `test_previewSummary_story_singular` — one subtask → `1 subtask · rooted on master`.
9. `test_previewSummary_story_nothing_left` — `dryRunStoryDone()` → `Nothing left to run`,
   integrate `""`; also a readable payload whose levels hold only an empty story / empty
   subtasks / garbage entries → `Nothing left to run`.
10. `test_previewSummary_story_ignores_integrate_and_done` — `dryRunStory()` with `integrate:
    {branch: "p-integrate"}`, with `already_done` holding `kind: "story"` and `kind:
    "subtask"` entries, and with `board: true` → still `false`, `2 subtasks · rooted on
    master`, `""`.
11. `test_previewSummary_story_base` — first counted subtask's base `"  main \n"` → `rooted
    on main`; base `""`, `"  "`, `5`, `null`, absent → `2 subtasks` alone (no fallback to the
    second subtask's base); garbage before the first object subtask (`null` level, `"x"` story,
    `7` subtask) is skipped and the first OBJECT subtask's base is used; a partly done story
    whose first listed subtask's base is `p-c1` → `rooted on p-c1`.
12. `test_previewSummary_story_unreadable` — the S3 unreadable values (`undefined`, `null`, `0`,
    `"x"`, `[]`, `{}`, `{levels: "x"}`, the `{ok, data}` envelope) with `"story"` → `false, "",
    ""`, never `Nothing left to run`; a prototype-less payload object is read.
13. `test_previewSummary_level_argument` — `dryRunMilestone()` and `dryRunBoard()` with `level`
    `undefined`, `"milestone"`, `"board"`, `"Story"`, `" story"`, `1` give exactly their S3
    results; `dryRunMilestone()` with `"story"` gives the story variant (`5 subtasks ·
    rooted on main`, `""`), proving the argument, not the shape, selects it.
14. `test_dispatch_form_preview_inputs_unchanged` — extended: `dryRunStory()` and
    `dryRunStoryDone()` are unchanged after `previewSummary(..., "story")`.

Existing `previewSummary` tests (milestone, board, integrate, edges, unreadable) stay as they
are and must stay green: they prove the one-argument behaviour is unchanged.

## Out of scope

- `dispatchDefaults` and the four-step prefix default (card 1.3, `aba87499`).
- `dispatch-preview.py` / `start-run.py` accepting the `story` kind, run-id discovery by
  `story_id` (card 1.4, `65fb51cf`). Until 1.4 lands, a story preview launched from the panel
  reaches a helper that does not know the `story` kind and is refused through the existing
  preview-refusal path; that is the expected state of this stacked branch.
- `prefixByMilestone` in `viewer-state.py` (card 1.5, `02ca6d9d`).
- `RunStore` passing `dispatchTarget.level` to `previewSummary`, the target label, the
  blocked-story retarget, prefix persistence (card 2.1, `5cf6e2f1`).
- `DispatchDialog` story label and blocked-story action (card 2.2), entry points (card 2.3),
  docs/README (card 2.4).
- Removing the now-unused suggestion plumbing (`RunStore.dispatchSuggest`,
  `DispatchDialog.suggestion`, `Panel.dispatchSuggestion`): left in place for 2.1/2.2 to reuse
  or remove.
- Any change to `am` or to the 1.1 contract tests.

## Verification

- `bash tests/run.sh` green (pytest tiers including `tests/architecture`, then every
  `tst_*.qml` offscreen). No typecheck or lint command exists in this repo.
- `grep -n "dispatched through its milestone" core/domain/runs.js` finds nothing.

---

# 1.2 runs.js: the story target and its preview summary — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `dispatchPlan` offers a story card as `am run --story ID`, and `previewSummary(dryRunData, "story")` summarises a story dry run as `N subtasks · rooted on <branch>` / `Nothing left to run`.

**Architecture:** Two pure functions in `core/domain/runs.js` (a `.pragma library` QML-JS module) change; their unit tests live in `tests/core/domain/tst_runs.qml`. Task 1 changes `dispatchPlan` and updates the store/UI tests that pinned the old story refusal. Task 2 adds the story variant of `previewSummary`, selected only by an explicit second argument `level === "story"`.

**Tech Stack:** QML JavaScript (ES5, `.pragma library`), QtTest via `qmltestrunner`, `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-2-runs-js-the-story-a2a74eda.md` (prepended above).

## Global Constraints

- `runs.js` is `.pragma library`, pure, never throws, own-key lookups only, ES5 (`var`, no arrow functions, no `let`/`const`).
- Comments and docstrings state the contract only, no narrative (no "now", "used to", "no longer").
- A story is dispatched with `am run --story ID`; the plan is `{command: "story", flags: ["--story", id], level: "story", offered: true, reason: "", suggest: null}` — `flags` is an ARRAY of argv words.
- The plan key set stays exactly `command, flags, level, offered, reason, suggest`; every plan and every `flags` array is fresh per call.
- Cards in `done`, `merged`, `canceled`, `archived` are refused with `The card is <status>` and `suggest: null`, at every level.
- Story summary: `<S> subtask` / `<S> subtasks`, then ` · rooted on <base>` (U+00B7 `·` between single spaces); `Nothing left to run` when `S === 0`; no Integrate line, no "stories already done" count, `board: false`.
- Only the exact string `"story"` selects the story variant of `previewSummary`.
- The sentence `A story is dispatched through its milestone` must not appear in `core/domain/runs.js`.
- No production file other than `core/domain/runs.js` changes.
- `bash tests/run.sh` is green at the end of each task.

## Review Focus

1. A story whose `parentId` is null, non-string, `__proto__`, or missing from / not an object in `cardMap` (or with no `cardMap`) — a person expects it offered exactly like any story, never a crash or a stale suggestion. Pinned by `test_dispatchPlan_story_ignores_parent` and `test_dispatchPlan_proto_ids` (Task 1).
2. A story payload whose first subtask's `base` is blank or not a string while the second subtask has one — a person expects the count alone, not a misleading branch taken from a later subtask. Pinned by `test_previewSummary_story_base` (Task 2).
3. A story payload that carries an `integrate` branch, `already_done` stories, or `board: true` — a person expects none of that in a story's preview. Pinned by `test_previewSummary_story_ignores_integrate_and_done` (Task 2).
4. An unreadable payload (the `{ok, data}` envelope, `levels` not an array) with `level "story"` — a person expects empty lines, never the false claim `Nothing left to run`. Pinned by `test_previewSummary_story_unreadable` (Task 2).
5. A near-miss `level` (`"Story"`, `" story"`, `1`, `null`) — a person expects the existing milestone/board summary, untouched. Pinned by `test_previewSummary_level_argument` (Task 2).

## How to run the tests

`bash tests/run.sh <filter>` runs all pytest tiers, then only the `tst_*.qml` files whose path contains `<filter>`. It prints `FAIL!` lines with their `Loc:` and a `Totals:` line per QML file, and exits non-zero on any failure. With no filter it runs everything.

---

### Task 1: `dispatchPlan` offers a story with `--story`

**Files:**
- Modify: `core/domain/runs.js:863-921` (S3 1.1 dispatch section: drop `_DISPATCH_STORY`, the story branch and its comment)
- Test: `tests/core/domain/tst_runs.qml:2473-2626` (dispatchPlan tests)
- Test: `tests/core/stores/tst_run_store.qml:2641-2655, 2672-2689, 3009-3026, 3053-3068`
- Test: `tests/ui/tst_dispatch_flow.qml:1-7, 140-172`
- Test: `tests/ui/tst_shortcuts.qml:726-737`

**Interfaces:**
- Consumes: `_offeredPlan(level, command, flags)`, `_refusedPlan(level, reason, suggest)`, `Board.isFinishedStatus(status)` — all already in `runs.js`.
- Produces: `dispatchPlan(card, cardMap)` returns for a non-finished depth-1 card `{command: "story", flags: ["--story", card.id], level: "story", offered: true, reason: "", suggest: null}`. `RunStore.dispatchTargetArgs()` (unchanged) then yields `["story", id]`. `RunStore.openDispatch(storyCard, cardMap)` returns `true` and goes `"previewing"`.

- [ ] **Step 1: Rewrite the story tests in `tests/core/domain/tst_runs.qml`**

Replace the whole `test_dispatchPlan_story` function (currently lines 2516-2540) with these three functions:

```qml
  function test_dispatchPlan_story() {
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs") }
    var statuses = ["todo", "in_progress", "blocked", undefined]
    for (var i = 0; i < statuses.length; i++) {
      var story = mkCard("s1", 1, statuses[i], "m1", "Story")
      map.s1 = story
      checkPlan(Runs.dispatchPlan(story, map), true, "story", "story", ["--story", "s1"], "", null,
                "status " + statuses[i])
    }
  }

  // Review Focus 1.
  function test_dispatchPlan_story_ignores_parent() {
    var story = mkCard("s1", 1, "todo", "m1", "Story")
    var maps = [undefined, { s1: story }, { m1: "M3" }, { m1: mkCard("m1", 0, "todo", null, Object.create(null)) },
                { m1: mkCard("m1", 0, "todo", null, 7) }, { m1: mkCard("m1", 0, "todo", null, null) }]
    for (var i = 0; i < maps.length; i++) {
      checkPlan(Runs.dispatchPlan(story, maps[i]), true, "story", "story", ["--story", "s1"], "", null, "cardMap " + i)
    }
    var parents = [null, "", 5, "__proto__", undefined]
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs") }
    for (var j = 0; j < parents.length; j++) {
      checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "todo", parents[j], "S"), map), true, "story", "story",
                ["--story", "s1"], "", null, "parentId " + parents[j])
    }
  }

  function test_dispatchPlan_story_fresh() {
    var story = mkCard("s1", 1, "todo", "m1", "Story")
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs"), s1: story }
    var before = JSON.stringify(map)
    var a = Runs.dispatchPlan(story, map)
    var b = Runs.dispatchPlan(story, map)
    verify(a !== b, "distinct objects")
    verify(a.flags !== b.flags, "distinct flags arrays")
    a.flags.push("--evil")
    a.flags[1] = "x"
    compare(JSON.stringify(b.flags), JSON.stringify(["--story", "s1"]), "the other result is untouched")
    compare(JSON.stringify(Runs.dispatchPlan(story, map).flags), JSON.stringify(["--story", "s1"]), "mutation does not leak")
    compare(JSON.stringify(map), before, "cardMap unchanged")
  }
```

In `test_dispatchPlan_finished`, after the line
`compare(Runs.dispatchPlan(mkCard("s1", 1, "done", "m1", "S"), map).reason, "The card is done", "exact sentence")`
add:

```qml
    checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "blocked", "m1", "S"), map), true, "story", "story",
              ["--story", "s1"], "", null, "blocked is not finished")
    checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "merged", "m1", "S"), { m1: map.m1, s1: mkCard("s1", 1, "merged", "m1", "S") }),
              false, "story", "", [], "The card is merged", null, "a finished story with its milestone in cardMap")
```

In `test_dispatchPlan_shape`, after the `board flags fresh` line, add:

```qml
    var story = Runs.dispatchPlan(inputs[1])
    compare(JSON.stringify(story.flags), JSON.stringify(["--story", "s1"]), "the story input is offered")
```

In `test_dispatchPlan_garbage`, replace everything from `var story = mkCard("s1", 1, "todo", "m1", "S")` to the end of the function (the `maps` loop, the `bare` cardMap and its `suggest.title` compare) with:

```qml
    var story = mkCard("s1", 1, "todo", "m1", "S")
    var bare = Object.create(null)
    bare.m1 = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var maps = [null, "x", [], Object.create(null), bare]
    for (var j = 0; j < maps.length; j++) {
      checkPlan(Runs.dispatchPlan(story, maps[j]), true, "story", "story", ["--story", "s1"], "", null, "cardMap " + j)
    }
  }
```

Replace `test_dispatchPlan_proto_ids` (story parent ids) with:

```qml
  function test_dispatchPlan_proto_ids() {
    var ids = ["__proto__", "constructor", "toString"]
    for (var i = 0; i < ids.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "todo", ids[i], "S"), { m1: mkCard("m1", 0, "todo", null, "M") }),
                true, "story", "story", ["--story", "s1"], "", null, "parentId " + ids[i])
      checkPlan(Runs.dispatchPlan(mkCard(ids[i], 1, "todo", "m1", "S")), true, "story", "story",
                ["--story", ids[i]], "", null, "story id " + ids[i])
    }
  }
```

Delete `test_dispatchPlan_odd_titles` and its `// Review Focus 4.` comment line entirely: its only subject was the suggestion's title, and its odd milestone titles (`Object.create(null)`, `7`, `null`) are now inputs of `test_dispatchPlan_story_ignores_parent` above.

- [ ] **Step 2: Run the domain tests to verify they fail**

Run: `bash tests/run.sh tst_runs.qml`
Expected: FAIL. `test_dispatchPlan_story`, `test_dispatchPlan_story_ignores_parent`, `test_dispatchPlan_story_fresh`, `test_dispatchPlan_finished` ("blocked is not finished offered"), `test_dispatchPlan_shape`, `test_dispatchPlan_garbage`, `test_dispatchPlan_proto_ids` report `FAIL!` — e.g. `Compared values are not the same Actual (): false Expected (): true` on `status todo offered`. `test_dispatchPlan_story_fresh` fails at `the other result is untouched` (`[]` vs `["--story","s1"]`).

- [ ] **Step 3: Update the store tests in `tests/core/stores/tst_run_store.qml`**

Replace `test_open_story_is_refused_with_its_milestone` (the `// 4` test) with:

```qml
  // 4
  function test_open_story_is_offered_with_the_story_flag() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.s1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchTarget.command, "story")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--story", "s1"]))
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    verify(store.dispatchForm, "an offered target has a form")
    compare(store.dispatchForm.prefix, "m3", "the story's milestone names the prefix")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.running, true)
  }
```

In `test_close_and_reopen_drop_the_pending_lookup`, change

```qml
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchState, "refused")
```

to

```qml
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchState, "refused")
```

In `test_set_unknown_field_or_while_idle_is_refused` (`// 19`), change

```qml
    store.openDispatch(cards.s1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "A story is dispatched through its milestone")
```

to

```qml
    store.openDispatch(cards.d1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
```

In `test_start_refused_unless_ready` (`// 21`), change

```qml
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchStart(), false, "refused")
```

to

```qml
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchStart(), false, "refused")
```

- [ ] **Step 4: Update the UI tests**

In `tests/ui/tst_dispatch_flow.qml`, change the header comment line

```qml
// the mounted dialog; the story's milestone offer, the subtask's lines and
```

to

```qml
// the mounted dialog; a story opening on itself, the subtask's lines and
```

Replace both `test_a_story_offers_its_milestone_and_the_offer_reopens_on_it` (with its `// 22` comment) and `test_a_story_whose_milestone_left_the_board_offers_nothing` (with its `// A story whose milestone is not on the board: the refusal, no offer.` comment) with:

```qml
  // 22
  function test_a_story_opens_the_dialog_on_itself() {
    var p = make(); if (!p) return
    dispatchCard(p, "s1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "s1")
    compare(p.app.runs.dispatchState, "previewing")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\"")
    compare(p.app.runs.dispatchSuggest, null)
    compare(H.find(p, "dispatchSuggest").visible, false, "no milestone offer")
  }
```

In `tests/ui/tst_shortcuts.qml` `test_escape_closes_an_open_dispatch_before_anything_else`, change

```qml
    compare(s.app.runs.openDispatch(s.app.board.cardMap["s1"], s.app.board.cardMap), false, "a story is refused at once")
    compare(s.app.runs.dispatchState, "refused")
```

to

```qml
    compare(s.app.runs.openDispatch(s.app.board.cardMap["s1"], s.app.board.cardMap), true, "a story opens on itself")
    compare(s.app.runs.dispatchState, "previewing")
```

- [ ] **Step 5: Run the store and UI tests to verify the new story assertions fail**

Run: `bash tests/run.sh tst_run_store.qml; bash tests/run.sh tst_dispatch_flow.qml; bash tests/run.sh tst_shortcuts.qml`
Expected: FAIL in `test_open_story_is_offered_with_the_story_flag` (`Actual (): false Expected (): true`), `test_a_story_opens_the_dialog_on_itself` (state `refused` vs `previewing`) and `test_escape_closes_an_open_dispatch_before_anything_else` (`false` vs `true`). The three `d1` switches already pass.

- [ ] **Step 6: Implement in `core/domain/runs.js`**

Delete the line

```js
var _DISPATCH_STORY = "A story is dispatched through its milestone"
```

Replace the comment above `dispatchPlan` and the function itself (from `// What the dispatch dialog may start for card.` through the closing `}` of `dispatchPlan`) with:

```js
// What the dispatch dialog may start for card. "board" is the whole board;
// otherwise card is a brd card: depth 0 milestone (--milestone), 1 story
// (--story), 2+ subtask (--card). A finished card is refused at every level.
// cardMap is accepted and not read. Decision order and sentences are pinned in
// docs/superpowers/specs/1-1-runs-js-5eb7ec0c.md and
// docs/superpowers/specs/1-2-runs-js-the-story-a2a74eda.md.
function dispatchPlan(card, cardMap) {
  if (card === "board") return _offeredPlan("board", "board", ["--board"])
  if (!_isObject(card) || !_isDispatchId(card.id)) return _refusedPlan("", _DISPATCH_NO_CARD, null)
  if (!_isWholeNumber(card.depth) || card.depth < 0) return _refusedPlan("", _DISPATCH_UNKNOWN_LEVEL, null)
  var level = card.depth === 0 ? "milestone" : (card.depth === 1 ? "story" : "subtask")
  if (Board.isFinishedStatus(card.status)) return _refusedPlan(level, "The card is " + card.status, null)
  if (level === "milestone") return _offeredPlan("milestone", "milestone", ["--milestone", card.id])
  if (level === "story") return _offeredPlan("story", "story", ["--story", card.id])
  return _offeredPlan("subtask", "card", ["--card", card.id])
}
```

Leave `_ownCard` in place: `_milestoneOf` still uses it.

- [ ] **Step 7: Run the full suite to verify everything passes**

Run: `bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`; no `TypeError`/`ReferenceError` lines. Then run `grep -n "dispatched through its milestone" core/domain/runs.js` — expected: no output (exit 1).

If any other test turns red because a story is now offered (for instance `test_escape_closes_the_dialog_and_gives_the_focus_back` in `tests/ui/tst_dispatch_flow.qml`, which dispatches `s1` and now sees `previewing` rather than `refused`), update it the way the spec says — assert the offered story, or switch a "needs a refused target" test to the done card (`d1` in the store tests, `m9` in `tst_dispatch_flow.qml`) — re-run `bash tests/run.sh`, and list the test in the commit message body.

- [ ] **Step 8: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/core/stores/tst_run_store.qml tests/ui/tst_dispatch_flow.qml tests/ui/tst_shortcuts.qml
git commit -m "feat(runs): dispatchPlan offers a story as am run --story"
```

---

### Task 2: `previewSummary` story variant

**Files:**
- Modify: `core/domain/runs.js:985-1081` (S3 1.2 section header, new `_firstPlanSubtask` and `_storyPreview` helpers, `previewSummary` comment and signature)
- Test: `tests/core/domain/tst_runs.qml:2936-3150` (new fixtures after `dryRunMilestone()`, new tests after `test_previewSummary_edges`, extended `test_dispatch_form_preview_inputs_unchanged`)

**Interfaces:**
- Consumes: `_isObject`, `_objectsOf(list)`, `_planSubtasks(plan)`, `_countOf(n, singular, plural)`, `_textOf(v)`, `_unreadablePreview()` — all already in `runs.js`.
- Produces: `previewSummary(dryRunData, level)` — `level === "story"` gives `{board: false, integrate: "", summary}` with `summary` `"<S> subtask(s)[ · rooted on <base>]"` or `"Nothing left to run"`; any other `level` keeps the one-argument behaviour. Card 2.1 will call `Runs.previewSummary(data, store.dispatchTarget.level)` from `RunStore.qml`.

- [ ] **Step 1: Add the story fixtures to `tests/core/domain/tst_runs.qml`**

Directly after the closing `}` of `dryRunMilestone()` add:

```qml
  // `am run --story s1 --dry-run` data as recorded in 1.1: one level, one story,
  // 2 subtasks stacked on master, no Integrate.
  function dryRunStory() {
    return {
      max_concurrent: 1,
      levels: [
        { level: 0, concurrent: 1, stories: [
          { story: "s1", title: "Story one", root: "master",
            subtasks: [planSubtask("p", "c1", "master"), planSubtask("p", "c2", "p-c1")] }
        ] }
      ],
      already_done: [],
      integrate: null
    }
  }

  // `am run --story s1 --dry-run` data for a finished story: no level, the story already done.
  function dryRunStoryDone() {
    return { max_concurrent: 1, levels: [], already_done: [{ kind: "story", id: "s1", title: "Story one" }], integrate: null }
  }
```

- [ ] **Step 2: Write the failing story tests**

Directly after the closing `}` of `test_previewSummary_edges()` (before `test_dispatch_form_preview_inputs_unchanged`) add:

```qml
  function test_previewSummary_story() {
    checkSummary(Runs.previewSummary(dryRunStory(), "story"), false, "2 subtasks · rooted on master", "", "story")
    var a = Runs.previewSummary(dryRunStory(), "story")
    var b = Runs.previewSummary(dryRunStory(), "story")
    verify(a !== b, "distinct objects")
    a.summary = "changed"
    a.board = true
    checkSummary(Runs.previewSummary(dryRunStory(), "story"), false, "2 subtasks · rooted on master", "",
                 "mutation does not leak")
  }

  function test_previewSummary_story_singular() {
    var one = dryRunStory()
    one.levels[0].stories[0].subtasks = [planSubtask("p", "c1", "master")]
    checkSummary(Runs.previewSummary(one, "story"), false, "1 subtask · rooted on master", "", "one subtask")
  }

  function test_previewSummary_story_nothing_left() {
    checkSummary(Runs.previewSummary(dryRunStoryDone(), "story"), false, "Nothing left to run", "", "finished story")
    var payloads = [
      { levels: [] },
      { levels: [{ level: 0, concurrent: 1, stories: [] }] },
      { levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "master", subtasks: [] }] }] },
      { levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "master" }] }] },
      { levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "master", subtasks: "x" }] }] },
      { levels: [null, "x", [], { level: 0, stories: ["x", null, [], { story: "s1", subtasks: [null, 7, "x", []] }] }] }
    ]
    for (var i = 0; i < payloads.length; i++) {
      checkSummary(Runs.previewSummary(payloads[i], "story"), false, "Nothing left to run", "", "payload " + i)
    }
  }

  // Review Focus 3.
  function test_previewSummary_story_ignores_integrate_and_done() {
    var full = "2 subtasks · rooted on master"
    var integrated = dryRunStory()
    integrated.integrate = { branch: "p-integrate", worktree: "/repo/.worktrees/p-integrate", order: [] }
    checkSummary(Runs.previewSummary(integrated, "story"), false, full, "", "integrate branch")
    var done = dryRunStory()
    done.already_done = [{ kind: "story", id: "s9", title: "Story nine" },
                         { kind: "subtask", id: "c0", title: "Subtask c0", story: "s1" }]
    checkSummary(Runs.previewSummary(done, "story"), false, full, "", "already done")
    var board = dryRunStory()
    board.board = true
    checkSummary(Runs.previewSummary(board, "story"), false, full, "", "board true")
  }

  // Review Focus 2.
  function test_previewSummary_story_base() {
    var padded = dryRunStory()
    padded.levels[0].stories[0].subtasks[0].base = "  main \n"
    checkSummary(Runs.previewSummary(padded, "story"), false, "2 subtasks · rooted on main", "", "base trimmed")
    var bases = ["", "  ", 5, null]
    for (var i = 0; i < bases.length; i++) {
      var d = dryRunStory()
      d.levels[0].stories[0].subtasks[0].base = bases[i]
      checkSummary(Runs.previewSummary(d, "story"), false, "2 subtasks", "", "base " + i + " (no fallback)")
    }
    var absent = dryRunStory()
    delete absent.levels[0].stories[0].subtasks[0].base
    checkSummary(Runs.previewSummary(absent, "story"), false, "2 subtasks", "", "base absent")
    var garbage = dryRunStory()
    garbage.levels[0].stories[0].subtasks.unshift(7, null, [], "c0")
    garbage.levels[0].stories.unshift("x", null, [], { story: "s0", title: "Empty", root: "main", subtasks: [] })
    garbage.levels.unshift(null, "x", [], { level: 9, stories: "x" })
    checkSummary(Runs.previewSummary(garbage, "story"), false, "2 subtasks · rooted on master", "",
                 "the first object subtask's base")
    var partly = dryRunStory()
    partly.levels[0].stories[0].subtasks = [planSubtask("p", "c2", "p-c1"), planSubtask("p", "c3", "p-c2")]
    partly.already_done = [{ kind: "subtask", id: "c1", title: "Subtask c1", story: "s1" }]
    checkSummary(Runs.previewSummary(partly, "story"), false, "2 subtasks · rooted on p-c1", "", "partly done")
  }

  // Review Focus 4.
  function test_previewSummary_story_unreadable() {
    var values = [undefined, null, 0, true, "x", [], Object.create(null), {}, { levels: "x" }, { levels: {} },
                  { ok: true, data: dryRunStory() }, { ok: true, data: dryRunStoryDone() }]
    for (var i = 0; i < values.length; i++) {
      checkSummary(Runs.previewSummary(values[i], "story"), false, "", "", "value " + i)
    }
    var bare = Object.create(null)
    bare.levels = dryRunStory().levels
    checkSummary(Runs.previewSummary(bare, "story"), false, "2 subtasks · rooted on master", "", "prototype-less payload")
  }

  // Review Focus 5.
  function test_previewSummary_level_argument() {
    var levels = [undefined, "milestone", "board", "Story", " story", "story ", 1, null]
    for (var i = 0; i < levels.length; i++) {
      checkSummary(Runs.previewSummary(dryRunMilestone(), levels[i]), false,
                   "2 levels · 5 subtasks · 3 stories already done", "Integrate → m3-integrate",
                   "milestone with level " + levels[i])
      checkSummary(Runs.previewSummary(dryRunBoard(), levels[i]), true, "3 milestones, 7 subtasks", "",
                   "board with level " + levels[i])
    }
    checkSummary(Runs.previewSummary(dryRunStory()), false, "1 level · 2 subtasks", "", "a story payload alone is a milestone")
    checkSummary(Runs.previewSummary(dryRunStoryDone()), false, "0 levels · 0 subtasks · 1 story already done", "",
                 "a finished story payload alone is a milestone")
    checkSummary(Runs.previewSummary(dryRunMilestone(), "story"), false, "5 subtasks · rooted on main", "",
                 "the argument selects the story variant")
  }
```

Then replace the whole `test_dispatch_form_preview_inputs_unchanged` function with:

```qml
  function test_dispatch_form_preview_inputs_unchanged() {
    var form = validForm()
    var milestone = dryRunMilestone()
    var board = dryRunBoard()
    var story = dryRunStory()
    var storyDone = dryRunStoryDone()
    var before = JSON.stringify([form, milestone, board, story, storyDone])
    Runs.validateDispatch(form)
    Runs.validateDispatch(formWith("prefix", ""))
    Runs.previewSummary(milestone)
    Runs.previewSummary(board)
    Runs.previewSummary(story, "story")
    Runs.previewSummary(storyDone, "story")
    Runs.previewSummary(milestone, "story")
    compare(JSON.stringify([form, milestone, board, story, storyDone]), before, "form and payloads unchanged")
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify", "no key added to the form")
    compare(Object.keys(story).sort().join(","), "already_done,integrate,levels,max_concurrent", "no key added to the story payload")
  }
```

- [ ] **Step 3: Run the domain tests to verify they fail**

Run: `bash tests/run.sh tst_runs.qml`
Expected: FAIL. `test_previewSummary_story`, `_story_singular`, `_story_nothing_left`, `_story_ignores_integrate_and_done`, `_story_base` report `FAIL!` with the milestone summary as actual (e.g. `Actual (): 1 level · 2 subtasks Expected (): 2 subtasks · rooted on master`); `test_previewSummary_story_unreadable` fails only at `prototype-less payload`; `test_previewSummary_level_argument` fails only at `the argument selects the story variant`. `test_dispatch_form_preview_inputs_unchanged` and every older `previewSummary` test pass.

- [ ] **Step 4: Implement in `core/domain/runs.js`**

Replace the S3 1.2 section header comment

```js
// ---- Dispatch form and preview (S3 1.2) --------------------------------------------------
//
// The dispatch form's own checks, and the one-line summary of an `am run
// --dry-run` payload (the envelope's data, milestone or board). Pure and never
// throwing, like the rest of this file. Rules, sentences and payload shapes are
// pinned in docs/superpowers/specs/1-2-runs-js-45cc9067.md.
```

with

```js
// ---- Dispatch form and preview (S3 1.2) --------------------------------------------------
//
// The dispatch form's own checks, and the one-line summary of an `am run
// --dry-run` payload (the envelope's data, milestone, story or board). Pure and
// never throwing, like the rest of this file. Rules, sentences and payload
// shapes are pinned in docs/superpowers/specs/1-2-runs-js-45cc9067.md and
// docs/superpowers/specs/1-2-runs-js-the-story-a2a74eda.md.
```

Directly after `function _unreadablePreview() { ... }` (and its comment) add:

```js
// The first object subtask of a dry-run plan, walking object levels, then
// object stories, then object subtasks, in order; null when there is none.
function _firstPlanSubtask(plan) {
  var levels = _objectsOf(plan.levels)
  for (var i = 0; i < levels.length; i++) {
    var stories = _objectsOf(levels[i].stories)
    for (var j = 0; j < stories.length; j++) {
      var subtasks = _objectsOf(stories[j].subtasks)
      if (subtasks.length > 0) return subtasks[0]
    }
  }
  return null
}

// The story preview of a readable `am run --story --dry-run` payload: "<S>
// subtask(s)", then " · rooted on <base>" when the first object subtask's
// base is a non-blank string (trimmed); "Nothing left to run" when S is 0.
// integrate, already_done and board are not read.
function _storyPreview(plan) {
  var count = _planSubtasks(plan)
  if (count === 0) return { board: false, integrate: "", summary: "Nothing left to run" }
  var first = _firstPlanSubtask(plan)
  var base = first !== null && typeof first.base === "string" ? _textOf(first.base) : ""
  var summary = _countOf(count, "subtask", "subtasks")
  if (base !== "") summary += " · rooted on " + base
  return { board: false, integrate: "", summary: summary }
}
```

Replace the comment above `previewSummary` and its first two lines

```js
// The dispatch dialog's preview lines for `am run --dry-run` data (never the
// {ok, data} envelope). A board payload (board exactly true) gives "<N>
// milestone(s), <M> subtask(s)" and no Integrate line; a milestone payload
// gives "<L> level(s) · <S> subtask(s)", then " · <D> stor(y|ies) already
// done" when D > 0, and "Integrate → <branch>" when integrate.branch is a
// non-blank string. Only subtasks listed in levels count. No array levels
// means unreadable: board false and both lines "".
function previewSummary(dryRunData) {
  if (!_isObject(dryRunData) || !Array.isArray(dryRunData.levels)) return _unreadablePreview()
```

with

```js
// The dispatch dialog's preview lines for `am run --dry-run` data (never the
// {ok, data} envelope). level is the target's level: exactly "story" gives the
// story preview ("<S> subtask(s) · rooted on <base>", or "Nothing left to
// run"; never an Integrate line, a done count or board true). Any other level
// reads the payload: a board payload (board exactly true) gives "<N>
// milestone(s), <M> subtask(s)" and no Integrate line; a milestone payload
// gives "<L> level(s) · <S> subtask(s)", then " · <D> stor(y|ies) already
// done" when D > 0, and "Integrate → <branch>" when integrate.branch is a
// non-blank string. Only subtasks listed in levels count. No array levels
// means unreadable at every level: board false and both lines "".
function previewSummary(dryRunData, level) {
  if (!_isObject(dryRunData) || !Array.isArray(dryRunData.levels)) return _unreadablePreview()
  if (level === "story") return _storyPreview(dryRunData)
```

The rest of `previewSummary` stays exactly as it is.

- [ ] **Step 5: Run the full suite to verify everything passes**

Run: `bash tests/run.sh`
Expected: exit 0; every `Totals:` line shows `0 failed`; no `TypeError`/`ReferenceError` lines.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): previewSummary story variant (N subtasks · rooted on <branch>)"
```

---

## Self-review (planner)

**Spec coverage.**
- Behaviour `dispatchPlan` 1-5, 7 unchanged → existing tests kept (`_board`, `_bad_id`, `_unknown_level`, `_milestone`, `_subtask`, `_finished`); 6 (story offered, parent/cardMap ignored, fresh) → Task 1 Steps 1, 6. Comment and `_DISPATCH_STORY` removal → Task 1 Step 6; grep check → Task 1 Step 7.
- `previewSummary` level argument, unreadable, count, `Nothing left to run`, singular/plural, first-counted-subtask base with no fallback, trimmed, no Integrate / done count / board true, fresh result, input unmodified → Task 2 Steps 2, 4 (tests 7-14 of the spec map to `test_previewSummary_story`, `_story_singular`, `_story_nothing_left`, `_story_ignores_integrate_and_done`, `_story_base`, `_story_unreadable`, `_level_argument`, `test_dispatch_form_preview_inputs_unchanged`).
- Spec tests 1-6: `test_dispatchPlan_story`, `_story_ignores_parent`, `_story_fresh`, `_finished` (+ finished story with parent in cardMap), `_shape` (story flags non-empty), `_garbage` and `_proto_ids` rewritten to the offered plan; `_odd_titles` removed, its titles folded into `_story_ignores_parent`.
- Fallout: `tst_run_store.qml` #4 rewritten, close/reopen, #19, #21 switched to `d1`; `tst_dispatch_flow.qml` two tests replaced by one, header updated; `tst_shortcuts.qml` updated; `tst_dispatch_dialog.qml` untouched; unknown further fallout handled in Task 1 Step 7.
- Section header pointers → Task 1 Step 6 (dispatchPlan comment cites both specs; the S3 1.1 section header itself has no spec pointer, so the pointer lives on the function comment as before) and Task 2 Step 4.

**Placeholder scan.** No TBD/TODO; every code step carries the code.

**Type consistency.** Plan shape and `flags` array match `checkPlan`; `previewSummary(dryRunData, level)`, `_firstPlanSubtask(plan)`, `_storyPreview(plan)` are used only where defined; fixtures `dryRunStory()` / `dryRunStoryDone()` are defined in Task 2 Step 1 before use.

**Review Focus.** All five lines have a pinning test in their owning task.
<!-- task-pipeline: validated -->
