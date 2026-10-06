# 2.2 runs.js: rollup counts each real subtask once by its own status — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Runs.rollup(runs, card)` counts each real subtask of the winning run once, bucketed by the subtask's own `status`, and never reads `run.rows`, so the real am captures in `tests/fixtures/am/` roll up to the parent spec's acceptance numbers (e.g. `status-done.json` gives 10, not 140).

**Architecture:** One code change in `core/domain/runs.js`: `rollup`'s loop walks `tree.subtasks` instead of `run.rows`, keeping the same membership rule (`_isCardId`, milestone / story via `_storyHas` / subtask card) and the same `_bucketOf` table; two comments are reworded. `_winningRun`, `_storyHas`, `_isCardId`, `_findByCardId` are used unchanged. The "1.2: rollups" block of `tests/core/domain/tst_runs.qml` is replaced with tests built on the normalized captures plus labelled `synthetic:` edge cases. Four UI tests that hand-build normalized runs give their subtasks the `status` their rows already said, and one comment in `ui/screens/GraphScreen.qml` is reworded.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every `tst_*.qml` whose path contains the substring).

**Spec:** `docs/superpowers/specs/2-2-runs-js-rollup-28977403.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Code: only `rollup` and the comment above `_bucketOf` change in `core/domain/runs.js` (lines 271-313 today). `_bucketOf`'s mapping table, `_winningRun`, `_touches`, `_storyHas`, `_isCardId`, `_isSynthetic`, `_findByCardId`, `cardRunState`, `runsTouching`, `normalizeRun`, `runProgress`, `runTree`, `escalationReason`, `glyphStateOf` are **not edited**.
- `rollup(runs, card)` keeps its signature and returns a fresh `{running, parked, escalated, done, pending, total}` of non-negative integers, `total` = sum of the other five; never throws; all zeros when `card` is not an object, `card.id` is not a real card id, or no run touches the card.
- Bucket table (exact string match, no case folding): `running`, `started` → running; `parked`, `stopped` → parked; `escalated`, `failed` → escalated; `done` → done; anything else → pending.
- `run.rows` is never read by `rollup`; nor is any card field but `id`.
- `core/domain/runs.js` stays `.pragma library` with exactly `.import "board.js" as Board`; `docs/architecture.md` layering holds and `tests/architecture` passes.
- Docstrings and comments state the contract only, no narrative.
- Tests asserting behaviour on real data normalize a capture via `amRun(name)` (`tests/helpers/amFixtures.js` `F.load`, fresh parse per call). Hand-built normalized runs (`mkRun`) are allowed past `normalizeRun`; each hand-built edge case carries a `synthetic:` comment.
- Not changed: the normalized shape and its keys, `rows` granularity, `RunBadge`, `RunRollupBar`, `runGlyphs.js`, `GraphView.qml`, `BoardScreen.qml`, `GraphScreen.qml` code (only its one comment), the fixtures, the backend.
- UI test edits add a `status` to hand-built subtasks only; no assertion, row, or message changes.
- No QML test function name may end in `_data` (QtTest treats it as a data provider and never runs it).
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. A run that has rows but no (or an empty / non-array) `tree.subtasks` — e.g. a run snapshot whose tree did not normalize: a person expects no progress shown, not progress invented from attempt rows. Pinned in Task 1 by `test_rollup_never_reads_rows` (c) and the non-array case in `test_rollup_ignores_brd_and_garbage`.
2. A subtask with many attempt rows whose rows say something else than the subtask (14 rows per done subtask, a retried `started` subtask with 2 rows): expected one count, by the subtask's status. Pinned in Task 1 by `test_rollup_fixture_stories_and_subtasks` and `test_rollup_never_reads_rows` (a)/(b).
3. The Integrate resolver whose `card_id` is a real story's id (`status-done-integrate.json`): expected that story counts only its own real subtask, not the resolver. Pinned in Task 1 by the last row of `test_rollup_fixture_stories_and_subtasks`.
4. A run whose am process died (`status: started`, lease `live: false`) beside an older finished run: expected the dead run still speaks for the card (it is non-terminal), and its `started` subtask counts as running. Pinned in Task 1 by the `dead lease` assertion added to `test_rollup_uses_winning_run_only` (beyond the spec's list; it asserts today's `_winningRun` behaviour through `rollup`).
5. Status spellings am never prints (`RUNNING`, `Done`, `""`, a number, `null`, missing): expected pending, never a throw, never a wrong bucket. Pinned in Task 1 by `test_rollup_bucket_mapping`.

---

## Spec (prepended; headings demoted one level)

## 2.2 runs.js: rollup counts each real subtask once by its own status — design

Card `28977403`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `bd534ea9` (2.1, `normalizeRun`, merged on this branch at `c8ff43d`
and later). Parent spec: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`
(below: **parent**). Work breakdown item 2 (parent L324-326) lists, after
`normalizeRun`, "then `rollup`, …": this subtask is `Runs.rollup` only.

### Goal

`Runs.rollup(runs, card)` gives the run-progress counts of a brd card. Today it
walks the winning run's `rows` and counts one per row (`core/domain/runs.js:302-313`).
Real am rows are per attempt (parent L33-36), so on `status-done.json` it
counts 140 instead of 10 (parent L93, the `rollup` line of the consumer table).
After this subtask `rollup` counts each **real subtask** of the winning run
**once**, bucketed by **the subtask's own `status`**, and never reads `rows`.

### Inherited constraints

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

### Fixture facts this design relies on (checked 2026-10-05)

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

### Behavior

#### Signature and result (unchanged)

`rollup(runs, card)` returns a fresh `{running, parked, escalated, done,
pending, total}` of non-negative integers, `total` = the sum of the other five.
Never throws. All zeros when `card` is not an object, `card.id` is not a real
card id, or no run touches the card.

#### Which run

The winning run for `card.id`, exactly as today (`_winningRun`, `runs.js:214`):
newest non-terminal run touching the card, else the newest run touching it.
Losing runs contribute nothing. Unchanged.

#### Which subtasks

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

#### Which bucket

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

#### What is never read

- `run.rows`: a run with rows but no `tree.subtasks` rolls up to zeros; a
  subtask with many rows counts once; a row's status never changes a count.
- The brd card's own `status`, `children`, `counts` or any field but `id`.

#### Comments

- `_bucketOf`'s comment says it maps a subtask status (not an "am row status").
- `rollup`'s docstring states: counts for a brd card from the winning run's
  real subtasks, one each, by the subtask's own status; never rows, never brd
  status (`Board.subtreeCounts` is separate).
- `ui/screens/GraphScreen.qml:41-42`'s comment on `buildRunMarks` says a pip is
  ringed when its run is live and running and its own subtask status is in the
  running bucket (it currently says "its own am row"). Comment only; the code
  there is unchanged.

### Hand-built normalized runs in UI tests

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

### Tests

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

#### Real data (from `tests/fixtures/am/` via `amRun`, never hand-written)

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

#### Synthetic edge cases (hand-built normalized runs via `mkRun`, each labelled `synthetic:`)

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

#### Suite

`bash tests/run.sh` green: pytest (incl. `tests/architecture`) and every QML
test, including the four UI files above unchanged in their assertions.

### Out of scope

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

### Handoff to the planner

One task is enough: the `tst_runs.qml` rewrite (red on today's code), the
`rollup` / `_bucketOf` change, the GraphScreen comment and the four UI-test
fixture edits land together, since the UI tests go red the moment `rollup`
stops reading rows. Follow the writing-plans format; run
`bash tests/run.sh tst_runs` for the red/green steps and `bash tests/run.sh`
at the end.

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/domain/runs.js` | Modify `:271-313` (`_bucketOf` comment, `rollup` docstring and loop) | run-progress counts for a brd card |
| `tests/core/domain/tst_runs.qml` | Replace `:755-856` (the "1.2: rollups" block) | unit tests of `rollup` |
| `ui/screens/GraphScreen.qml` | Modify `:40-42` (comment only) | documents when a pip is ringed |
| `tests/ui/screens/tst_board_screen.qml` | Modify `:183-193` (add subtask `status`) | keeps board badge/bar assertions true |
| `tests/ui/screens/tst_graph_screen.qml` | Modify `:212-217` (add subtask `status`) | keeps graph rollup/ring assertions true |
| `tests/ui/tst_board_flow.qml` | Modify `:94-97` (add subtask `status`) | keeps board-flow badge assertion true |
| `tests/ui/tst_graph_flow.qml` | Modify `:201-206` (add subtask `status`) | keeps graph-flow badge/ring assertions true |

One task: the UI tests go red the moment `rollup` stops reading rows, so the code change, the unit tests and the UI fixture edits land in one commit.

---

### Task 1: `rollup` counts each real subtask once by its own status

**Files:**
- Modify: `core/domain/runs.js:271-313`
- Modify: `ui/screens/GraphScreen.qml:40-42` (comment only)
- Test: `tests/core/domain/tst_runs.qml:755-856` (replace block)
- Test: `tests/ui/screens/tst_board_screen.qml:183-193`
- Test: `tests/ui/screens/tst_graph_screen.qml:212-217`
- Test: `tests/ui/tst_board_flow.qml:94-97`
- Test: `tests/ui/tst_graph_flow.qml:201-206`

**Interfaces:**
- Consumes (unchanged, in `core/domain/runs.js`): `_winningRun(runs, cardId) -> {run, dimmed} | null`; `_treeOf(run) -> object`; `_arrayOr(v) -> array`; `_isObject(v) -> bool`; `_isCardId(id) -> bool`; `_findByCardId(list, cardId) -> object | null`; `_storyHas(story, subtask, storyId) -> bool`; `_bucketOf(status) -> "running"|"parked"|"escalated"|"done"|"pending"`. In `tst_runs.qml`: `amRun(name) -> {row, status}` (`:14`), `mkRun(id, status, live, opts) -> normalized run` (`:524`, `opts: {milestone_id, rows, tree, started_at}`; `live === null` means no lease).
- Produces: `Runs.rollup(runs, card) -> {running, parked, escalated, done, pending, total}` (same signature; new counting rule). Callers `ui/screens/BoardScreen.qml:80` and `ui/screens/GraphScreen.qml:53,58` are unchanged.

- [ ] **Step 1: Replace the "1.2: rollups" block in `tests/core/domain/tst_runs.qml`**

Delete everything from the line `  // ---- 1.2: rollups ---…` (line 755) through the closing `  }` of `test_rollup_rows_only_not_brd` (line 856, the line before the blank line and `  // ---- 1.2: attention ---…`). That removes `rollupRun`, `counts`, `test_rollup_milestone`, `test_rollup_story_membership`, `test_rollup_uses_winning_run_only`, `test_rollup_subtask_card`, `test_rollup_rows_only_not_brd`. Insert in its place exactly:

```qml
  // ---- 2.2: rollups -----------------------------------------------------------------------

  function counts(r) {
    return [r.running, r.parked, r.escalated, r.done, r.pending, r.total].join(",")
  }

  function test_rollup_fixture_milestones() {
    var cases = [
      ["status-started.json", "837c4431-7a24-4531-96a8-881698ea8c5e", "1,0,0,3,4,8"],
      ["status-done.json", "cb11063d-78b9-4537-8569-fb5c249519f8", "0,0,0,10,0,10"],
      ["status-escalated.json", "bcc4e411-504c-48f4-8712-198a5c04ec8b", "0,0,1,2,1,4"],
      ["status-escalated-integrate.json", "5a2d70ff-b0c8-4bb8-8a87-1cb2c679a754", "0,0,0,2,0,2"],
      ["status-done-integrate.json", "2f6878ac-7e83-449f-9b6c-3b1f65acd30e", "0,0,0,2,0,2"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var name = cases[i][0]
      var run = Runs.normalizeRun(amRun(name))
      compare(run.milestone_id, cases[i][1], name + " milestone id")
      var r = Runs.rollup([run], { id: run.milestone_id })
      compare(Object.keys(r).sort().join(","), "done,escalated,parked,pending,running,total", name)
      compare(counts(r), cases[i][2], name)
    }
  }

  function test_rollup_fixture_stories_and_subtasks() {
    var started = [Runs.normalizeRun(amRun("status-started.json"))]
    var done = [Runs.normalizeRun(amRun("status-done.json"))]
    var escalated = [Runs.normalizeRun(amRun("status-escalated.json"))]
    var doneIntegrate = [Runs.normalizeRun(amRun("status-done-integrate.json"))]
    var cases = [
      [started, "d3d879b9-cb74-41ca-9a37-63f477de9711", "1,0,0,1,1,3", "started: story"],
      [started, "299ec9c0-b935-4c44-a7a0-982a104cbfe5", "1,0,0,0,0,1", "started: subtask with 2 rows"],
      [done, "f03629a7-5912-4b36-82b2-12f3b567294a", "0,0,0,4,0,4", "done: story"],
      [done, "22153f5f-9632-4b5f-a7dd-664c39d89e5c", "0,0,0,1,0,1", "done: subtask with 14 rows"],
      [escalated, "3f5aadb9-67b1-49b9-aec5-fb0bf81e46f9", "0,0,1,0,0,1", "escalated: story"],
      [escalated, "eb8b1851-8245-45c3-9a29-d1fcefaad0b9", "0,0,1,0,0,1", "escalated: subtask with 12 rows"],
      [doneIntegrate, "b429248c-c69e-4df5-8f7d-52776253ea14", "0,0,0,1,0,1",
       "done-integrate: real story whose id the Integrate resolver carries"]
    ]
    for (var i = 0; i < cases.length; i++) {
      compare(counts(Runs.rollup(cases[i][0], { id: cases[i][1] })), cases[i][2], cases[i][3])
    }
  }

  function test_rollup_never_reads_rows() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    compare(run.milestone_id, "cb11063d-78b9-4537-8569-fb5c249519f8")
    var milestone = { id: run.milestone_id }
    compare(run.rows.length, 140, "rows are per attempt")
    compare(counts(Runs.rollup([run], milestone)), "0,0,0,10,0,10", "one count per subtask")

    // synthetic: every row of the normalized capture set to started
    for (var i = 0; i < run.rows.length; i++) run.rows[i].status = "started"
    compare(counts(Runs.rollup([run], milestone)), "0,0,0,10,0,10", "row status ignored")

    // synthetic: the normalized capture with no subtasks, its 140 rows kept
    run.tree.subtasks = []
    compare(run.rows.length, 140)
    compare(counts(Runs.rollup([run], milestone)), "0,0,0,0,0,0", "rows alone count nothing")
  }

  function test_rollup_bucket_mapping() {
    var cases = [
      ["running", "1,0,0,0,0,1"], ["started", "1,0,0,0,0,1"],
      ["parked", "0,1,0,0,0,1"], ["stopped", "0,1,0,0,0,1"],
      ["escalated", "0,0,1,0,0,1"], ["failed", "0,0,1,0,0,1"],
      ["done", "0,0,0,1,0,1"],
      ["pending", "0,0,0,0,1,1"], ["cancelled", "0,0,0,0,1,1"], ["queued", "0,0,0,0,1,1"],
      ["RUNNING", "0,0,0,0,1,1"], ["Done", "0,0,0,0,1,1"], ["", "0,0,0,0,1,1"],
      [5, "0,0,0,0,1,1"], [null, "0,0,0,0,1,1"]
    ]
    for (var i = 0; i < cases.length; i++) {
      // synthetic: milestone m1 with one subtask t1 in the given status
      var run = mkRun("r1", "started", true, {
        tree: { stories: [], subtasks: [{ card_id: "t1", status: cases[i][0], phases: [] }] }
      })
      compare(counts(Runs.rollup([run], { id: "m1" })), cases[i][1], "status " + JSON.stringify(cases[i][0]))
    }
    // synthetic: milestone m1 with one subtask t1 that has no status
    var missing = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [{ card_id: "t1", phases: [] }] } })
    compare(counts(Runs.rollup([missing], { id: "m1" })), "0,0,0,0,1,1", "missing status")
  }

  // synthetic: milestone m1; story s1 lists t1 (id string) and t2 ({card_id}); t3 belongs to s2
  // via story_id; t4 belongs to no story.
  function membershipRun(id, status, live) {
    return mkRun(id, status, live, {
      tree: {
        stories: [{ card_id: "s1", subtasks: ["t1", { card_id: "t2" }] }, { card_id: "s2", subtasks: [] }],
        subtasks: [
          { card_id: "t1", status: "started", phases: [] },
          { card_id: "t2", status: "stopped", phases: [] },
          { card_id: "t3", story_id: "s2", status: "failed", phases: [] },
          { card_id: "t4", status: "done", phases: [] }
        ]
      }
    })
  }

  function test_rollup_story_membership() {
    var runs = [membershipRun("r1", "started", true)]
    compare(counts(Runs.rollup(runs, { id: "s1" })), "1,1,0,0,0,2", "string and {card_id} entries")
    compare(counts(Runs.rollup(runs, { id: "s2" })), "0,0,1,0,0,1", "story_id membership")
    compare(counts(Runs.rollup(runs, { id: "m1" })), "1,1,1,1,0,4", "milestone counts every subtask")
    compare(counts(Runs.rollup(runs, { id: "t4" })), "0,0,0,1,0,1", "subtask card")
  }

  function test_rollup_excludes_non_real_subtasks() {
    // synthetic: garbage and synthetic-id subtasks beside one real t1; story s9 lists an unknown zz
    var run = mkRun("r1", "started", true, {
      tree: {
        stories: [{ card_id: "s9", subtasks: ["zz"] }],
        subtasks: [null, "x", 5, { card_id: "" }, { card_id: 7 },
                   { card_id: "integrate", status: "started" }, { card_id: "bases", status: "started" },
                   { card_id: "base-s1", status: "started" }, { card_id: "t1", status: "done", phases: [] }]
      }
    })
    compare(counts(Runs.rollup([run], { id: "m1" })), "0,0,0,1,0,1", "only t1 counts")
    compare(counts(Runs.rollup([run], { id: "integrate" })), "0,0,0,0,0,0", "integrate card")
    compare(counts(Runs.rollup([run], { id: "base-s1" })), "0,0,0,0,0,0", "base-* card")
    compare(counts(Runs.rollup([run], { id: "s9" })), "0,0,0,0,0,0", "story listing only an unknown id")
  }

  function test_rollup_uses_winning_run_only() {
    // synthetic: a live run of m1 (t1 started) and an older done run (t1, t2 done)
    var winner = mkRun("live", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "started", phases: [] }] }
    })
    var loser = mkRun("old", "done", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "done", phases: [] },
                                      { card_id: "t2", status: "done", phases: [] }] }
    })
    compare(counts(Runs.rollup([loser, winner], { id: "m1" })), "1,0,0,0,0,1", "milestone")
    compare(counts(Runs.rollup([loser, winner], { id: "t1" })), "1,0,0,0,0,1", "subtask")

    // synthetic: two finished runs, newest first, no started_at; the older one escalated with t1 failed
    var older = mkRun("older", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "failed", phases: [] }] }
    })
    compare(counts(Runs.rollup([loser, older], { id: "m1" })), "0,0,0,2,0,2", "all finished: newest wins")

    // synthetic: a started run whose lease is dead (t1 started) beside the done run
    var dead = mkRun("dead", "started", false, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "started", phases: [] }] }
    })
    compare(counts(Runs.rollup([loser, dead], { id: "m1" })), "1,0,0,0,0,1", "dead lease still wins")
  }

  function test_rollup_prototype_ids() {
    // synthetic: card ids that are Object.prototype member names
    var proto = mkRun("p", "started", true, {
      tree: { stories: [{ card_id: "__proto__", subtasks: ["constructor"] }],
              subtasks: [{ card_id: "constructor", status: "done", phases: [] },
                         { card_id: "toString", status: "started", phases: [] }] }
    })
    compare(counts(Runs.rollup([proto], { id: "constructor" })), "0,0,0,1,0,1", "constructor subtask")
    compare(counts(Runs.rollup([proto], { id: "__proto__" })), "0,0,0,1,0,1", "__proto__ story")
    compare(counts(Runs.rollup([proto], { id: "valueOf" })), "0,0,0,0,0,0", "absent valueOf")
  }

  function test_rollup_ignores_brd_and_garbage() {
    var runs = [membershipRun("r1", "started", true)]
    var card = { id: "s1", status: "done", children: ["t1", "t2", "t9"], counts: { done: 9 } }
    compare(counts(Runs.rollup(runs, card)), "1,1,0,0,0,2", "brd status, children and counts ignored")
    compare(counts(Runs.rollup(runs, card)), counts(Runs.rollup(runs, { id: "s1" })))
    compare(counts(Runs.rollup(runs, { id: "s9x" })), "0,0,0,0,0,0", "untouched card")

    var garbage = [[undefined, { id: "m1" }], [null, { id: "m1" }], ["x", { id: "m1" }], [runs, null],
                   [runs, "m1"], [runs, {}], [runs, { id: "" }], [runs, { id: 5 }], [runs, []]]
    for (var i = 0; i < garbage.length; i++) {
      compare(counts(Runs.rollup(garbage[i][0], garbage[i][1])), "0,0,0,0,0,0", "garbage " + i)
    }

    // synthetic: a junk tree, with a row naming t1
    var junk = [{ id: "j", status: "started", lease: { live: true }, milestone_id: "m1",
                  tree: { stories: "x", subtasks: [null, 5] }, rows: [{ card_id: "t1", status: "running" }] }]
    compare(counts(Runs.rollup(junk, { id: "m1" })), "0,0,0,0,0,0", "junk tree")

    // synthetic: tree.subtasks is an object, not an array, with a row naming t1
    var notArray = mkRun("n", "started", true, {
      tree: { stories: [], subtasks: { card_id: "t1", status: "started" } },
      rows: [{ card_id: "t1", status: "started" }]
    })
    compare(counts(Runs.rollup([notArray], { id: "m1" })), "0,0,0,0,0,0", "subtasks not an array")
  }
```

- [ ] **Step 2: Run the domain tests to verify they fail**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: the run exits non-zero. `FAIL!` lines name each of `test_rollup_fixture_milestones`, `test_rollup_fixture_stories_and_subtasks`, `test_rollup_never_reads_rows`, `test_rollup_bucket_mapping`, `test_rollup_story_membership`, `test_rollup_excludes_non_real_subtasks`, `test_rollup_uses_winning_run_only`, `test_rollup_prototype_ids`, `test_rollup_ignores_brd_and_garbage` (today's code counts rows, and the synthetic runs have none). Every other `DomainRuns` test passes. No `TypeError`/`ReferenceError` line is printed (a printed one means a typo in Step 1 — fix it before going on).

- [ ] **Step 3: Change `rollup` and the `_bucketOf` comment in `core/domain/runs.js`**

Replace the comment line above `_bucketOf` (line 271):

```js
// Which am row status lands in which rollup bucket; anything else is pending.
```

with:

```js
// Which subtask status lands in which rollup bucket; anything else is pending.
```

Leave the body of `_bucketOf` and all of `_storyHas` as they are. Replace the whole of `rollup` with its docstring (lines 290-313 today, from `// Run-progress counts for a brd card, from the winning run's am rows only …` through the closing `}`) with:

```js
// Run-progress counts for a brd card: the winning run's real subtasks, one each, by the
// subtask's own status. Never rows, never brd status (Board.subtreeCounts is separate).
function rollup(runs, card) {
  var counts = { running: 0, parked: 0, escalated: 0, done: 0, pending: 0, total: 0 }
  if (!_isObject(card)) return counts
  var cardId = card.id
  var win = _winningRun(runs, cardId)
  if (win === null) return counts
  var run = win.run
  var tree = _treeOf(run)
  var isMilestone = run.milestone_id === cardId
  var story = isMilestone ? null : _findByCardId(tree.stories, cardId)
  var subtasks = _arrayOr(tree.subtasks)
  for (var i = 0; i < subtasks.length; i++) {
    var subtask = subtasks[i]
    if (!_isObject(subtask) || !_isCardId(subtask.card_id)) continue
    if (!isMilestone) {
      var belongs = story !== null ? _storyHas(story, subtask, cardId) : subtask.card_id === cardId
      if (!belongs) continue
    }
    counts[_bucketOf(subtask.status)] += 1
    counts.total += 1
  }
  return counts
}
```

- [ ] **Step 4: Run the domain tests to verify they pass**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: exit 0; the `tests/core/domain/tst_runs.qml` `Totals:` line shows `0 failed`; no `FAIL!` line.

- [ ] **Step 5: Run the four UI tests to see them go red**

Run: `bash tests/run.sh tests/ui`
Expected: exit non-zero, with `FAIL!` lines in some of `tst_board_screen.qml`, `tst_graph_screen.qml`, `tst_board_flow.qml`, `tst_graph_flow.qml` (their hand-built subtasks have no `status`, so every subtask now buckets `pending`: e.g. a badge that expected `⟳ 1`, `runRollups.m1.running` expecting 1, `runRinged` expecting `t1`). Note which tests fail; Steps 6-9 fix exactly these.

- [ ] **Step 6: Give the hand-built subtasks in `tests/ui/screens/tst_board_screen.qml` their status**

In `withRuns` (lines 183-193), make these four replacements (rows unchanged):

```qml
          subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] },
```
→
```qml
          subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] }] },
```

```qml
        { stories: [], subtasks: [{ card_id: "m2", phases: [{ name: "review", status: "started" }] }] },
```
→
```qml
        { stories: [], subtasks: [{ card_id: "m2", status: "started", phases: [{ name: "review", status: "started" }] }] },
```

```qml
        { stories: [], subtasks: [{ card_id: "t4", phases: [] }] }, [{ card_id: "t4", status: "running" }]),
```
→
```qml
        { stories: [], subtasks: [{ card_id: "t4", status: "started", phases: [] }] }, [{ card_id: "t4", status: "running" }]),
```

```qml
        { stories: [], subtasks: [{ card_id: "t5", phases: [] }] }, [{ card_id: "t5", status: "stopped" }])]
```
→
```qml
        { stories: [], subtasks: [{ card_id: "t5", status: "stopped", phases: [] }] }, [{ card_id: "t5", status: "stopped" }])]
```

- [ ] **Step 7: Give the hand-built subtasks in `tests/ui/screens/tst_graph_screen.qml` their status**

In `withRuns` (lines 212-217) replace:

```qml
          subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] },
                     { card_id: "t2", phases: [] }] },
```
with:
```qml
          subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] },
                     { card_id: "t2", status: "pending", phases: [] }] },
```

- [ ] **Step 8: Give the hand-built subtask in `tests/ui/tst_board_flow.qml` its status**

At lines 94-97 replace:

```qml
        subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] },
```
with:
```qml
        subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] }] },
```

- [ ] **Step 9: Give the hand-built subtasks in `tests/ui/tst_graph_flow.qml` their status**

At lines 201-206 replace:

```qml
        subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] },
                   { card_id: "t2", phases: [] }] },
```
with:
```qml
        subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] },
                   { card_id: "t2", status: "pending", phases: [] }] },
```

- [ ] **Step 10: Reword the `buildRunMarks` comment in `ui/screens/GraphScreen.qml`**

Replace lines 40-42:

```qml
  // { marks: id -> Runs.cardRunState, rollups: id -> Runs.rollup, ringed: [pip id] }.
  // A pip is ringed when its run is live and running AND its own am row is in the
  // running bucket: the subtask am is working on now, not every subtask of the run.
```
with:
```qml
  // { marks: id -> Runs.cardRunState, rollups: id -> Runs.rollup, ringed: [pip id] }.
  // A pip is ringed when its run is live and running AND its own subtask status is in the
  // running bucket: the subtask am is working on now, not every subtask of the run.
```

No code line in `GraphScreen.qml` changes.

- [ ] **Step 11: Run the UI tests to verify they pass**

Run: `bash tests/run.sh tests/ui`
Expected: exit 0; every `Totals:` line shows `0 failed`; no `FAIL!` line.

- [ ] **Step 12: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0. pytest passes (including `tests/architecture` and `tests/contract`); every QML file's `Totals:` line shows `0 failed`; no `TypeError`/`ReferenceError` line.

Also check the diff touches only the seven files listed under **Files**:

Run: `git status --short`
Expected: ` M` lines for exactly `core/domain/runs.js`, `ui/screens/GraphScreen.qml`, `tests/core/domain/tst_runs.qml`, `tests/ui/screens/tst_board_screen.qml`, `tests/ui/screens/tst_graph_screen.qml`, `tests/ui/tst_board_flow.qml`, `tests/ui/tst_graph_flow.qml` (plus the spec/plan docs if not yet committed).

- [ ] **Step 13: Commit**

```bash
git add core/domain/runs.js ui/screens/GraphScreen.qml tests/core/domain/tst_runs.qml \
  tests/ui/screens/tst_board_screen.qml tests/ui/screens/tst_graph_screen.qml \
  tests/ui/tst_board_flow.qml tests/ui/tst_graph_flow.qml
git commit -m "feat(runs): rollup counts each real subtask once by its own status

rollup walks the winning run's tree.subtasks instead of its per-attempt
rows, so the am captures roll up to one count per real subtask (done: 10,
not 140). The UI tests' hand-built subtasks carry the status their rows
already said."
```

---

## Self-Review (against the spec)

- Signature/result, which run, which subtasks (object, real card id, milestone / story via `_storyHas` / subtask card), which bucket, never reads rows or brd fields: Step 3; pinned by tests 1-9 in Step 1.
- Comments (`_bucketOf`, `rollup` docstring, GraphScreen): Steps 3 and 10.
- Hand-built UI runs (four files, statuses per the spec table, rows untouched, assertions untouched): Steps 6-9.
- Tests 1-9 with the spec's exact expected counts and ids: Step 1 (test 7 gains one `dead lease` assertion from Review Focus 4).
- Suite green incl. `tests/architecture`: Step 12.
- Placeholders: none; every code step shows the code. Names: `counts`, `membershipRun`, `mkRun`, `amRun` are defined in the file or in Step 1; no test name ends in `_data`.
<!-- task-pipeline: validated -->
