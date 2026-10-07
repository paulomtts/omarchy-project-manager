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
