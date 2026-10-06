# 2.3 runs.js: runProgress counts subtasks whose own status is done — design

Card `8ad57065`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `28977403` (2.2, `rollup`, committed at `7960638`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 2 (parent L324-326) lists "`normalizeRun` …,
then `rollup`, `runProgress`, …": this subtask is `Runs.runProgress` only.

## Goal

`Runs.runProgress(run)` gives the `done/total` the Runs screen shows on a run's
row (`ui/screens/RunsScreen.qml:169,221`). Today (`core/domain/runs.js:395-409`)
it counts every object in `tree.subtasks` as total and calls a subtask done when
it has phases and every recorded phase is `done`. Real am records phases as they
are reached (parent L28-30), so a subtask between two phases (its last recorded
phase `done`, the next not yet recorded) counts as done while am says it is
`started` (parent L100). After this subtask `runProgress` counts **real
subtasks** (objects whose `card_id` is a real card id) as total, and done = those
whose **own `status` is `done`**. It never reads `phases`.

## Inherited constraints

| constraint | source |
|---|---|
| Decision 3: `runProgress` counts real subtasks and those whose own status is `done`; the plugin's total leaves Integrate resolvers out, so it can be lower than `am runs`' `progress.subtasks.total` | parent L155-160 |
| Phases are recorded as they are reached (a pending subtask has `[]`) | parent L28-30 |
| Consumer table: `runProgress` today is "every recorded phase done"; once fixed by phases a subtask between two phases would count as done | parent L100, L115 |
| Subtask statuses: `pending, started, done, failed, escalated, stopped, cancelled` | parent L37-38 |
| Decision 2: subtasks of synthetic stories (`integrate`, `bases`) are not in `tree.subtasks`; `base-*` ids are no card | parent L148-154 |
| Normalized `tree.subtasks[]`: `{card_id, branch, base_branch, status, worktree_path, phases, story_id}`, real stories only, am's order | parent L190-197 |
| Acceptance: `runProgress` per fixture: started 3/8, done 10/10, escalated 2/4, escalated-integrate 2/2, done-integrate 2/2 | parent L211-217 |
| Each fixture run is `normalizeRun({row: <its am runs entry without status>, status: <fixture>.data})` | parent L207-209 |
| Open question kept as decided: done-integrate is 2/2 here, 3/3 in am | parent L335-337 |
| Tests of code past `normalizeRun` may build normalized runs by hand; a test asserting behaviour on real data normalizes a fixture; an edit to a fixture inside a test is made on a fresh copy and labelled `synthetic:` | parent L257-267, card |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)` (fresh parse each call) | parent L269-274 |
| Not changed: the normalized shape; `RunsScreen.qml` layout | parent L306-317 |
| `docs/architecture.md` layering (`core/domain/*.js` is `.pragma library`, no QML/Qt imports); `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

## Fixture facts this design relies on (checked 2026-10-05)

Real subtasks of each normalized fixture run, in am's order, with their own
`status` and whether every recorded phase is `done`:

| fixture | real subtasks: status (all phases done?) | status `done` |
|---|---|---|
| `status-started.json` | `5eb7ec0c` done (yes) · `45cc9067` done (yes) · `a19ca446` done (yes) · `299ec9c0` started (no: `worktree` done, `explore` started) · `fdb5feb1`, `66a6b6c0`, `dfc0ac87`, `46141e11` pending (`[]`) | 3 of 8 |
| `status-done.json` | 10 subtasks, all done (yes) | 10 of 10 |
| `status-escalated.json` | `c5e41536` done · `231a23cc` done · `eb8b1851` escalated · `ca31fde7` pending | 2 of 4 |
| `status-escalated-integrate.json` | `1f04eab4` done · `0e01b1ba` done | 2 of 2 |
| `status-done-integrate.json` | `40b96a6b` done · `5d5114f9` done (the `integrate` resolver `b429248c…` is not in `tree.subtasks`; am's `_am_runs_row.progress.subtasks` is 3/3) | 2 of 2 |

On these five captures the old rule and the new rule give the **same** numbers
(every captured subtask with status `done` has all phases done and no other
subtask does). The acceptance tests therefore pass on today's code; the tests
that fail first are the `synthetic:` ones (tests 2-4 below), which is where the
two rules differ.

Full ids used by the tests:

- started: `299ec9c0-b935-4c44-a7a0-982a104cbfe5` (status `started`, phases
  `worktree` done, `explore` started).
- done: `22153f5f-9632-4b5f-a7dd-664c39d89e5c` (status `done`).

## Behavior

### Signature and result (unchanged)

`runProgress(run)` returns a fresh `{done, total}` of non-negative integers,
`done <= total`. Never throws. `{done: 0, total: 0}` when `run` is not an object,
`run.tree` is not an object, or `run.tree.subtasks` is not an array.

### Which subtasks count (total)

Walk `run.tree.subtasks` (via `_subtasksOf`) once. An element adds 1 to `total`
when:

1. it is an object, and
2. its `card_id` is a real card id (`_isCardId`, `runs.js:180`: a non-empty
   string other than `integrate`, `bases` and `base-*`).

Anything else (`null`, a string, a number, an array element that is no object,
an object with a missing / empty / non-string `card_id`, or a synthetic id)
counts nowhere. This is the same filter `rollup` applies (`runs.js:305`). A
subtask listed twice counts twice (`normalizeRun` never produces that; no
de-duplication is added).

### Which subtasks are done

A counted subtask adds 1 to `done` when its `status` is exactly the string
`done` (no case folding: `Done`, `DONE`, `" done"` are not done). Nothing else
makes a subtask done:

- `phases` is never read: a subtask whose recorded phases are all `done` but
  whose status is `started` (or `pending`, `escalated`, …) is not done; a
  subtask whose status is `done` is done whatever its `phases` hold (missing,
  `[]`, a non-array, or containing a non-`done` phase).
- `run.rows`, `run.status` and the lease are never read.

### Comments

`runProgress`'s docstring states the contract only: counts of the run's real
subtasks (object, real card id) and of those whose own `status` is `done`. It no
longer mentions phases.

### What does not change

- `currentPhase` (`runs.js:412+`) keeps reading phases.
- `RunsScreen.qml`: still shows `done/total` when `total > 0`, else nothing.

## Hand-built normalized runs in UI tests

`tests/ui/screens/tst_runs_screen.qml` `sample()` (:121-132) builds normalized
runs by hand whose subtasks carry `phases` but no `status`. Under the new rule
row 0 would read `0/2` instead of `1/2` (assertion :168). Each subtask gets the
`status` its phases describe, in am's spelling; `phases` stay as they are
(`currentPhase` and the escalation reason still read them):

| run → subtask | added `status` |
|---|---|
| `run-20261004-live0001` → `t1` | `done` |
| `run-20261004-live0001` → `t2` | `started` |
| `run-20261004-escl0002` → `t3` | `escalated` |

Assertions this keeps meaningful: `runRowProgress0` is `1/2` (:168);
`runRowPhase0` is `implement`; `runRowProgress4` hidden (:178, no subtasks);
`runRowProgress1` hidden on the malformed-run test (:375, `tree: null`).
No other test file asserts a `done/total` text or calls `runProgress`
(`tests/ui/tst_runs_flow.qml`, `tests/ui/screens/tst_run_detail_screen.qml`
checked).

## Tests

All in `tests/core/domain/tst_runs.qml` unless stated. Tier: **QML unit**
(`qmltestrunner` via `tests/run.sh`): `runProgress` is a pure `.pragma library`
function, so a unit test on its inputs is the cheapest test that pins it. The
`tst_runs_screen.qml` edit is **QML screen** tier and exists only to keep an
existing assertion true for the right reason.

The existing `test_run_progress` (:1083-1098) is replaced by the tests below.
`progressTree()` (:1073-1081) stays as it is: it is now used only by
`test_current_phase` (:1101), which is unchanged. `amRun` (:14), `mkRun` (:524)
are reused as they are; `fixtureRuns()` (:28) is not used here because it lacks
`status-escalated-integrate.json`.

### Real data (from `tests/fixtures/am/` via `amRun`, never hand-written)

1. `test_run_progress_fixtures` — for each fixture,
   `runProgress(normalizeRun(amRun(f)))`, compared as `"done/total"`:

   | fixture | expected |
   |---|---|
   | `status-started.json` | `3/8` |
   | `status-done.json` | `10/10` |
   | `status-escalated.json` | `2/4` |
   | `status-escalated-integrate.json` | `2/2` |
   | `status-done-integrate.json` | `2/2` |

   Also asserts the result's keys are exactly `done,total`. Passes on today's
   code too (see fixture facts); it pins the acceptance numbers.

### Fixture copies edited in the test (each labelled `synthetic:`)

2. `test_run_progress_reads_status_not_phases` — on fresh normalized copies:
   (a) `synthetic: between two phases` — `status-started.json`, subtask
   `299ec9c0…`'s `phases` cut to its first (`worktree`, `done`), status left
   `started`: `3/8` (today: `4/8`); (b) `synthetic:` `status-done.json`,
   subtask `22153f5f…`'s `status` set to `started`, phases left all `done`:
   `9/10` (today: `10/10`); (c) `synthetic:` `status-done.json`, subtask
   `22153f5f…`'s `phases` set to `[]`: `10/10` (today: `9/10`); (d)
   `synthetic:` `status-escalated.json`, every subtask's `phases` set to `"x"`:
   `2/4` (today: `0/4`).

### Synthetic edge cases (hand-built normalized runs via `mkRun`, each labelled `synthetic:`)

3. `test_run_progress_status_spelling` — one subtask `t1` per run with status
   `done` → `1/1`; each of `started`, `pending`, `failed`, `escalated`,
   `stopped`, `cancelled`, `Done`, `DONE`, `" done"`, `""`, `5`, `true`,
   `null`, missing → `0/1`.
4. `test_run_progress_counts_real_subtasks_only` — `tree.subtasks` =
   `[null, "x", 5, [], {}, { status: "done" }, { card_id: "", status: "done" },
   { card_id: 7, status: "done" }, { card_id: "integrate", status: "done" },
   { card_id: "bases", status: "done" }, { card_id: "base-s1", status: "done" },
   { card_id: "t1", status: "done" }, { card_id: "t2", status: "started" }]` →
   `1/2` (today: `0/9`; arrays are not objects). A run whose only subtasks are synthetic ids →
   `0/0`. The old junk case `[null, "x", 5, { phases: "x" }]` → `0/0` (today
   `0/1`).
5. `test_run_progress_garbage` — kept from today: `mkRun` with no subtasks →
   `0/0`; `undefined`, `null`, `"x"`, `5`, `[]`, `{}`, `{tree: "x"}`,
   `{tree: {subtasks: "y"}}` → `0/0`; plus `{tree: {subtasks: null}}` and
   `{tree: null}` → `0/0`.

### Screen

6. `tests/ui/screens/tst_runs_screen.qml` — `sample()` edited as in "Hand-built
   normalized runs"; no assertion changes. Goes red (`0/2`) once `runProgress`
   changes if the edit is missing, so the edit lands in the same commit.

### Suite

`bash tests/run.sh` green: pytest (incl. `tests/architecture`) and every QML
test.

## Out of scope

- `rollup` (2.2, done), `normalizeRun` (2.1, done), `currentPhase`,
  `runTree`'s open attempt, `escalationReason`, `glyphStateOf` (later
  subtasks of this story).
- `_isCardId`, `_isSynthetic`, `_subtasksOf`: used, not changed.
- Switching to `am runs`' `progress` counts (parent "Open questions",
  L335-337).
- `RunsScreen.qml` code and layout; any change to the normalized shape.
- `docs/architecture.md`: it lists `runProgress` (`:184`) without a done rule;
  no edit (docs are work breakdown item 5).
- Other hand-built-run tests (`tst_run_store.qml`, `tst_run_detail_screen.qml`,
  `tst_runs_flow.qml`): they do not assert `runProgress`.

## Handoff to the planner

One task is enough: the `tst_runs.qml` tests (tests 2-4 red on today's code,
1 and 5 green), the `runProgress` change with its docstring, and the
`tst_runs_screen.qml` `sample()` edit land together, since the screen test goes
red the moment `runProgress` stops reading phases. Follow the writing-plans
format; run `bash tests/run.sh tst_runs` for the red/green steps and
`bash tests/run.sh` at the end.
