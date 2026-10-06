# 2.2 runs.js: rollup counts each real subtask once by its own status — design

Card `28977403`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `bd534ea9` (2.1, `normalizeRun`, merged on this branch at `c8ff43d`
and later). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326) lists, after
`normalizeRun`, "then `rollup`, …": this subtask is `Runs.rollup` only.

## Goal

`Runs.rollup(runs, card)` gives the run-progress counts of a brd card. Today it
walks the winning run's `rows` and counts one per row (`core/domain/runs.js:302-313`).
Real am rows are per attempt (parent L33-36), so on `status-done.json` it
counts 140 instead of 10 (parent L93, the `rollup` line of the consumer table).
After this subtask `rollup` counts each **real subtask** of the winning run
**once**, bucketed by **the subtask's own `status`**, and never reads `rows`.

## Inherited constraints

| constraint | source |
|---|---|
| Decision 3: rows stay per attempt; nothing counts them as subtasks. `rollup` counts each real subtask of the winning run once, by the subtask's own `status` | parent L155-157 |
| Subtask statuses: `pending, started, done, failed, escalated, stopped, cancelled` | parent L37-38 |
| Decision 2: subtasks of synthetic stories (`integrate`, `bases`) are not in `tree.subtasks`. An Integrate resolver's `card_id` is a real story's id | parent L148-154, L40-44 |
| Normalized `tree.subtasks[]`: `{card_id, branch, base_branch, status, worktree_path, phases, story_id}`, real stories only, am's order. `tree.stories[].subtasks` is a list of id strings | parent L190-197 |
| Acceptance: `rollup(milestone)` r/p/e/d/pend/total per fixture: started 1/0/0/3/4/8, done 0/0/0/10/0/10, escalated 0/0/1/2/1/4, escalated-integrate 0/0/0/2/0/2, done-integrate 0/0/0/2/0/2 | parent L211-217 |
| Each fixture run is `normalizeRun({row: <its am runs entry without status>, status: <fixture>.data})`; the entry is in `runs.json` or the fixture's `_am_runs_row` | parent L207-209 |
| Tests of code past `normalizeRun` may build normalized runs by hand; a test asserting behaviour on real data normalizes a fixture. A hand-built edge case carries a `synthetic:` comment | parent L257-267, card |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)` (fresh parse each call) | parent L269-274 |
| Not changed: the normalized shape and its keys; `rows` keeps per-attempt granularity; `RunBadge`, `RunRollupBar`, `runGlyphs.js` | parent L306-317 |
| `docs/architecture.md` layering (`core/domain/*.js` is `.pragma library`, no QML/Qt imports, `docs/architecture.md:9-11`); `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

## Fixture facts this design relies on (checked 2026-10-05)

Subtask statuses per am story, in am's order (`I` = the `integrate` story,
whose subtask is not in `tree.subtasks`):

| fixture | milestone_id (from `am runs`) | stories → subtask statuses | rows |
|---|---|---|---|
| `status-started.json` | `837c4431-7a24-4531-96a8-881698ea8c5e` | `1c665cfd` done, done · `d3d879b9` done, started, pending · `3d877d1f` pending · `c56468c7` pending, pending | 44 |
| `status-done.json` | `cb11063d-78b9-4537-8569-fb5c249519f8` | 2 + 3 + 1 + 4 subtasks, all done | 140 |
| `status-escalated.json` | `bcc4e411-504c-48f4-8712-198a5c04ec8b` | `d76ef984` done, done · `3f5aadb9` escalated · `6436569d` pending | 40 |
| `status-escalated-integrate.json` | `5a2d70ff-b0c8-4bb8-8a87-1cb2c679a754` | `376e06e2` done · `aeb34ef8` done | 28 |
| `status-done-integrate.json` | `2f6878ac-7e83-449f-9b6c-3b1f65acd30e` | `2f88f774` done · `b429248c` done · `I` (`b429248c…`) done | 30 (28 after normalize) |

Ids used by the tests below:

- started: story `d3d879b9-cb74-41ca-9a37-63f477de9711`; its `started` subtask
  `299ec9c0-b935-4c44-a7a0-982a104cbfe5` has 2 rows.
- done: story `f03629a7-5912-4b36-82b2-12f3b567294a` (4 subtasks); subtask
  `22153f5f-9632-4b5f-a7dd-664c39d89e5c` has 14 rows.
- escalated: story `3f5aadb9-67b1-49b9-aec5-fb0bf81e46f9`; subtask
  `eb8b1851-8245-45c3-9a29-d1fcefaad0b9` (escalated, 12 rows).
- done-integrate: `b429248c-c69e-4df5-8f7d-52776253ea14` is both a real story
  (one subtask, `5d5114f9…`, done) and the Integrate resolver's `card_id`.

Every count in the tables below follows from these statuses; today's code gives
different numbers on all of them (it counts rows), so each fixture test fails
first.

## Behavior

### Signature and result (unchanged)

`rollup(runs, card)` returns a fresh `{running, parked, escalated, done,
pending, total}` of non-negative integers, `total` = the sum of the other five.
Never throws. All zeros when `card` is not an object, `card.id` is not a real
card id, or no run touches the card.

### Which run

The winning run for `card.id`, exactly as today (`_winningRun`, `runs.js:214`):
newest non-terminal run touching the card, else the newest run touching it.
Losing runs contribute nothing. Unchanged.

### Which subtasks

Walk the winning run's `tree.subtasks` (a non-array is `[]`) once, in order.
An element counts only when:

1. it is an object, and
2. its `card_id` is a real card id (`_isCardId`: non-empty string, not
   `integrate`, `bases`, `base-*`), and
3. it belongs to the card:
   - the card is the run's milestone (`run.milestone_id === card.id`): every
     subtask belongs;
   - else the card is a story of the run (`_findByCardId(tree.stories,
     card.id)` not null): the subtask belongs when `_storyHas(story, subtask,
     card.id)` (its `story_id` equals the story's id, or the story's
     `subtasks` list names it as an id string or `{card_id}`);
   - else (the card is a subtask): the subtask belongs when its `card_id` is
     `card.id`.

Each counting element adds 1 to `total` and 1 to its bucket. A subtask listed
twice in `tree.subtasks` counts twice (`normalizeRun` never produces that; no
de-duplication is added).

### Which bucket

`_bucketOf(subtask.status)`, exact string match, no case folding:

| subtask `status` | bucket |
|---|---|
| `running`, `started` | running |
| `parked`, `stopped` | parked |
| `escalated`, `failed` | escalated |
| `done` | done |
| anything else (`pending`, `cancelled`, `queued`, `RUNNING`, `Done`, `""`, a number, missing) | pending |

The mapping table itself is unchanged; only its input changes from a row's
status to a subtask's status.

### What is never read

- `run.rows`: a run with rows but no `tree.subtasks` rolls up to zeros; a
  subtask with many rows counts once; a row's status never changes a count.
- The brd card's own `status`, `children`, `counts` or any field but `id`.

### Comments

- `_bucketOf`'s comment says it maps a subtask status (not an "am row status").
- `rollup`'s docstring states: counts for a brd card from the winning run's
  real subtasks, one each, by the subtask's own status; never rows, never brd
  status (`Board.subtreeCounts` is separate).
- `ui/screens/GraphScreen.qml:41-42`'s comment on `buildRunMarks` says a pip is
  ringed when its run is live and running and its own subtask status is in the
  running bucket (it currently says "its own am row"). Comment only; the code
  there is unchanged.

## Hand-built normalized runs in UI tests

These tests build normalized runs by hand with `rows` and subtasks without a
`status`. Under the new rule their subtasks would all bucket `pending`, so each
subtask gets the `status` that names what its row said, in am's spelling. Rows
stay as they are. No assertion changes; each test still passes for the same
reason.

| file | run → subtask: added `status` |
|---|---|
| `tests/ui/screens/tst_board_screen.qml` `withRuns` (:183-193) | run-a1 `t1`: `started` · run-b2 `m2`: `started` · run-c3 `t4`: `started` · run-d4 `t5`: `stopped` |
| `tests/ui/screens/tst_graph_screen.qml` `withRuns` (:212-217) | run-a1 `t1`: `started`, `t2`: `pending` |
| `tests/ui/tst_board_flow.qml` (:94-97) | `t1`: `started` |
| `tests/ui/tst_graph_flow.qml` (:201-206) | `t1`: `started`, `t2`: `pending` |

Assertions these keep meaningful: board milestone badge `⟳ 1` and its rollup bar
running `⟳ 1`; parked milestone `⏸ 1`; graph `runRollups.m1` running 1 /
pending 1 / total 2, `runRollups.s1.total` 2; `runRinged` = `t1` only
(`GraphScreen.buildRunMarks` rings a pip when `rollup(pip).running > 0`);
board-flow badge `⟳ 1`; graph-flow story badge `⟳ 1`, `1 pending`, pip `t1`
ringed and `t2` not.

## Tests

All in `tests/core/domain/tst_runs.qml` unless stated. Tier: **QML unit**
(`qmltestrunner` via `tests/run.sh`): `rollup` is a pure `.pragma library`
function, so a unit test against its inputs is the cheapest test that pins it.
The UI-test edits above are **QML screen/flow** tier and exist only to keep
existing assertions true. The old "1.2: rollups" block (`:755-856`:
`rollupRun`, `test_rollup_milestone`, `test_rollup_story_membership`,
`test_rollup_uses_winning_run_only`, `test_rollup_subtask_card`,
`test_rollup_rows_only_not_brd`) is replaced; the `counts(r)` helper (`:783`,
`"r,p,e,d,pend,total"`) is kept, and `mkRun` (`:524`) and `amRun` (`:14`) are
reused as they are.

### Real data (from `tests/fixtures/am/` via `amRun`, never hand-written)

1. `test_rollup_fixture_milestones` — for each fixture,
   `rollup([normalizeRun(amRun(f))], {id: <its milestone_id>})`:

   | fixture | expected `counts` |
   |---|---|
   | `status-started.json` | `1,0,0,3,4,8` |
   | `status-done.json` | `0,0,0,10,0,10` |
   | `status-escalated.json` | `0,0,1,2,1,4` |
   | `status-escalated-integrate.json` | `0,0,0,2,0,2` |
   | `status-done-integrate.json` | `0,0,0,2,0,2` |

   The milestone id is read from the normalized run (`run.milestone_id`), and
   the test also asserts it equals the literal in the fixture facts table so a
   blank id cannot pass vacuously. Also asserts the result's keys are exactly
   `done,escalated,parked,pending,running,total`.
2. `test_rollup_fixture_stories_and_subtasks` — story and subtask cards on real
   runs:

   | run | card id | expected |
   |---|---|---|
   | started | `d3d879b9…` (story) | `1,0,0,1,1,3` |
   | started | `299ec9c0…` (subtask, 2 rows) | `1,0,0,0,0,1` |
   | done | `f03629a7…` (story) | `0,0,0,4,0,4` |
   | done | `22153f5f…` (subtask, 14 rows) | `0,0,0,1,0,1` |
   | escalated | `3f5aadb9…` (story) | `0,0,1,0,0,1` |
   | escalated | `eb8b1851…` (subtask, 12 rows) | `0,0,1,0,0,1` |
   | done-integrate | `b429248c…` (real story and resolver id) | `0,0,0,1,0,1` |

   The last row proves the Integrate resolver is not counted for the story
   whose id it carries.
3. `test_rollup_never_reads_rows` — on `normalizeRun(amRun("status-done.json"))`:
   (a) milestone rollup is `0,0,0,10,0,10` while `run.rows.length` is 140;
   (b) `synthetic:` set every row's `status` to `started` on that normalized
   run: the milestone rollup is still `0,0,0,10,0,10`; (c) `synthetic:` set
   `tree.subtasks` to `[]` keeping the 140 rows: `0,0,0,0,0,0`.

### Synthetic edge cases (hand-built normalized runs via `mkRun`, each labelled `synthetic:`)

4. `test_rollup_bucket_mapping` — one run per status, one subtask `t1`,
   milestone `m1`: `running`, `started` → running; `parked`, `stopped` →
   parked; `escalated`, `failed` → escalated; `done` → done; `pending`,
   `cancelled`, `queued`, `RUNNING`, `Done`, `""`, `5`, `null`, missing →
   pending. Each `total` is 1.
5. `test_rollup_story_membership` — milestone `m1`; story `s1` lists `t1` (id
   string) and `{card_id: "t2"}`; story `s2` lists nothing, `t3` has `story_id:
   "s2"`; `t4` belongs to no story; statuses `t1` started, `t2` stopped, `t3`
   failed, `t4` done. `s1` → `1,1,0,0,0,2`; `s2` → `0,0,1,0,0,1`; `m1` →
   `1,1,1,1,0,4`; `t4` (subtask card) → `0,0,0,1,0,1`.
6. `test_rollup_excludes_non_real_subtasks` — `tree.subtasks` also holds `null`,
   `"x"`, `5`, `{card_id: ""}`, `{card_id: 7}`, `{card_id: "integrate", status:
   "started"}`, `{card_id: "bases", …}`, `{card_id: "base-s1", status:
   "started"}` beside one real `t1` done: milestone → `0,0,0,1,0,1`;
   `rollup(…, {id: "integrate"})` and `{id: "base-s1"}` → zeros. A story `s9`
   listed in `tree.stories` with an unknown id `zz` in its list and no
   subtask `zz` → zeros.
7. `test_rollup_uses_winning_run_only` — live run (`t1` started) and an older
   done run (`t1` done, `t2` done): milestone and `t1` → `1,0,0,0,0,1`; two
   finished runs listed newest first, no `started_at` (newer done with `t1`,
   `t2` done; older escalated with `t1` failed): `0,0,0,2,0,2`.
8. `test_rollup_prototype_ids` — story `__proto__` listing `constructor`;
   subtasks `constructor` done and `toString` started: `constructor` →
   `0,0,0,1,0,1`; `__proto__` → `0,0,0,1,0,1`; `valueOf` (absent) → zeros.
9. `test_rollup_ignores_brd_and_garbage` — card `{id: "s1", status: "done",
   children: [...], counts: {done: 9}}` on test 5's run gives the same as `{id:
   "s1"}`; untouched `{id: "s9x"}` → zeros; garbage `(runs, card)` pairs
   `[undefined,{id:"m1"}]`, `[null,…]`, `["x",…]`, `[runs,null]`, `[runs,"m1"]`,
   `[runs,{}]`, `[runs,{id:""}]`, `[runs,{id:5}]`, `[runs,[]]` → zeros; a run
   whose `tree` is `{stories: "x", subtasks: [null, 5]}` with rows naming `t1`
   → zeros; a run whose `tree.subtasks` is not an array → zeros.

### Suite

`bash tests/run.sh` green: pytest (incl. `tests/architecture`) and every QML
test, including the four UI files above unchanged in their assertions.

## Out of scope

- `normalizeRun` (2.1, done), `runProgress`, `runTree`'s open attempt,
  `escalationReason`, `glyphStateOf` (the story's later subtasks).
- `cardRunState`, `_winningRun`, `_touches`, `runsTouching`, `_storyHas`,
  `_isCardId` / `_isSynthetic`: used, not changed.
- Any change to the normalized shape or to `rows` (parent L306-309).
- `RunBadge`, `RunRollupBar`, `runGlyphs.js`, `GraphView.qml`, `BoardScreen.qml`
  and `GraphScreen.qml` code (only `GraphScreen.qml`'s one comment changes).
- Other hand-built-run tests (`tst_run_store.qml`, `tst_runs_screen.qml`,
  `tst_run_detail_screen.qml`): they do not read `rollup`.
- Switching to `am runs`' `progress` counts (parent "Open questions").

## Handoff to the planner

One task is enough: the `tst_runs.qml` rewrite (red on today's code), the
`rollup` / `_bucketOf` change, the GraphScreen comment and the four UI-test
fixture edits land together, since the UI tests go red the moment `rollup`
stops reading rows. Follow the writing-plans format; run
`bash tests/run.sh tst_runs` for the red/green steps and `bash tests/run.sh`
at the end.
