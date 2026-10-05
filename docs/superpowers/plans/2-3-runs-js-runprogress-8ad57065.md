# 2.3 runs.js: runProgress counts subtasks whose own status is done — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Runs.runProgress(run)` counts the run's real subtasks (object, real card id) as `total` and those whose own `status` is exactly `done` as `done`, never reading `phases`, so a subtask between two phases no longer counts as done.

**Architecture:** One function changes in `core/domain/runs.js` (`runProgress`, lines 395-409 today, docstring included): the loop applies the same real-subtask filter `rollup` uses (`_isObject` + `_isCardId`) and tests `subtask.status === "done"`. `_subtasksOf`, `_isCardId`, `_isObject` are used unchanged. In `tests/core/domain/tst_runs.qml` the old `test_run_progress` is replaced by five tests (fixture acceptance numbers, `synthetic:` edits of normalized captures, status spellings, real-subtask filter, garbage). `tests/ui/screens/tst_runs_screen.qml` `sample()` gives its hand-built subtasks the `status` their phases describe so `runRowProgress0` stays `1/2`.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every `tst_*.qml` whose path contains the substring; `tst_runs` matches `tst_runs.qml`, `tst_runs_screen.qml` and `tst_runs_flow.qml`).

**Spec:** `docs/superpowers/specs/2-3-runs-js-runprogress-8ad57065.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Code: only `runProgress` and its docstring change in `core/domain/runs.js` (lines 395-409 today). `currentPhase`, `rollup`, `_isCardId`, `_isSynthetic`, `_subtasksOf`, `_isObject`, `normalizeRun`, `runTree`, `escalationReason`, `glyphStateOf` are **not edited**.
- `runProgress(run)` keeps its signature and returns a fresh `{done, total}` of non-negative integers, `done <= total`; never throws; `{done: 0, total: 0}` when `run` is not an object, `run.tree` is not an object, or `run.tree.subtasks` is not an array.
- Total: an element of `run.tree.subtasks` counts when it is an object (not an array, not null) and its `card_id` is a real card id (`_isCardId`: non-empty string other than `integrate`, `bases`, `base-*`). No de-duplication.
- Done: a counted subtask whose `status` is exactly the string `done` (no case folding, no trimming). `phases`, `run.rows`, `run.status` and the lease are never read.
- `core/domain/runs.js` stays `.pragma library` with exactly `.import "board.js" as Board`; `docs/architecture.md` layering holds and `tests/architecture` passes.
- Docstrings and comments state the contract only, no narrative; `runProgress`'s docstring no longer mentions phases.
- Tests asserting behaviour on real data normalize a capture via `amRun(name)` (`tests/helpers/amFixtures.js` `F.load`, fresh parse per call). Hand-built normalized runs (`mkRun`) are allowed past `normalizeRun`; each hand-built or edited case carries a `synthetic:` comment.
- Not changed: the normalized shape, `RunsScreen.qml` code and layout, `docs/architecture.md`, the fixtures, `progressTree()` and `test_current_phase` in `tst_runs.qml`.
- The `tst_runs_screen.qml` edit adds a `status` to hand-built subtasks only; `phases` stay; no assertion changes.
- No QML test function name may end in `_data` (QtTest treats it as a data provider and never runs it).
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. A subtask between two phases (status `started`, its last recorded phase `done`, the next not recorded yet) — the case this subtask exists for: a person expects it not done. Pinned in Task 1 by `test_run_progress_reads_status_not_phases` (a) on the real `status-started.json` subtask `299ec9c0…`, and by the `started`/`pending`/… rows of `test_run_progress_status_spelling`, whose subtask has every recorded phase `done`.
2. A subtask am calls `done` whose `phases` are empty, missing or not a list (e.g. a trimmed or older am output): expected done all the same. Pinned in Task 1 by `test_run_progress_reads_status_not_phases` (c)/(d) and the `done` row of `test_run_progress_status_spelling` without phases.
3. The Integrate resolver of `status-done-integrate.json` (am counts 3/3): expected the row to read `2/2`, never more done than real subtasks. Pinned in Task 1 by `test_run_progress_fixtures`.
4. Bookkeeping or malformed subtask entries (`integrate`, `bases`, `base-*`, missing / empty / numeric `card_id`, arrays, `null`): expected to count nowhere, never inflate the total. Pinned in Task 1 by `test_run_progress_counts_real_subtasks_only`.
5. Status spellings am never prints (`Done`, `DONE`, `" done"`, `""`, a number, `true`, `null`, missing): expected not done, never a throw. Pinned in Task 1 by `test_run_progress_status_spelling`.

---

## Spec (prepended; headings demoted one level)

## 2.3 runs.js: runProgress counts subtasks whose own status is done — design

Card `8ad57065`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `28977403` (2.2, `rollup`, committed at `7960638`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 2 (parent L324-326) lists "`normalizeRun` …,
then `rollup`, `runProgress`, …": this subtask is `Runs.runProgress` only.

### Goal

`Runs.runProgress(run)` gives the `done/total` the Runs screen shows on a run's
row (`ui/screens/RunsScreen.qml:169,221`). Today (`core/domain/runs.js:395-409`)
it counts every object in `tree.subtasks` as total and calls a subtask done when
it has phases and every recorded phase is `done`. Real am records phases as they
are reached (parent L28-30), so a subtask between two phases (its last recorded
phase `done`, the next not yet recorded) counts as done while am says it is
`started` (parent L100). After this subtask `runProgress` counts **real
subtasks** (objects whose `card_id` is a real card id) as total, and done = those
whose **own `status` is `done`**. It never reads `phases`.

### Inherited constraints

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

### Fixture facts this design relies on (checked 2026-10-05)

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

### Behavior

#### Signature and result (unchanged)

`runProgress(run)` returns a fresh `{done, total}` of non-negative integers,
`done <= total`. Never throws. `{done: 0, total: 0}` when `run` is not an object,
`run.tree` is not an object, or `run.tree.subtasks` is not an array.

#### Which subtasks count (total)

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

#### Which subtasks are done

A counted subtask adds 1 to `done` when its `status` is exactly the string
`done` (no case folding: `Done`, `DONE`, `" done"` are not done). Nothing else
makes a subtask done:

- `phases` is never read: a subtask whose recorded phases are all `done` but
  whose status is `started` (or `pending`, `escalated`, …) is not done; a
  subtask whose status is `done` is done whatever its `phases` hold (missing,
  `[]`, a non-array, or containing a non-`done` phase).
- `run.rows`, `run.status` and the lease are never read.

#### Comments

`runProgress`'s docstring states the contract only: counts of the run's real
subtasks (object, real card id) and of those whose own `status` is `done`. It no
longer mentions phases.

#### What does not change

- `currentPhase` (`runs.js:412+`) keeps reading phases.
- `RunsScreen.qml`: still shows `done/total` when `total > 0`, else nothing.

### Hand-built normalized runs in UI tests

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

### Tests

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

#### Real data (from `tests/fixtures/am/` via `amRun`, never hand-written)

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

#### Fixture copies edited in the test (each labelled `synthetic:`)

2. `test_run_progress_reads_status_not_phases` — on fresh normalized copies:
   (a) `synthetic: between two phases` — `status-started.json`, subtask
   `299ec9c0…`'s `phases` cut to its first (`worktree`, `done`), status left
   `started`: `3/8` (today: `4/8`); (b) `synthetic:` `status-done.json`,
   subtask `22153f5f…`'s `status` set to `started`, phases left all `done`:
   `9/10` (today: `10/10`); (c) `synthetic:` `status-done.json`, subtask
   `22153f5f…`'s `phases` set to `[]`: `10/10` (today: `9/10`); (d)
   `synthetic:` `status-escalated.json`, every subtask's `phases` set to `"x"`:
   `2/4` (today: `0/4`).

#### Synthetic edge cases (hand-built normalized runs via `mkRun`, each labelled `synthetic:`)

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

#### Screen

6. `tests/ui/screens/tst_runs_screen.qml` — `sample()` edited as in "Hand-built
   normalized runs"; no assertion changes. Goes red (`0/2`) once `runProgress`
   changes if the edit is missing, so the edit lands in the same commit.

#### Suite

`bash tests/run.sh` green: pytest (incl. `tests/architecture`) and every QML
test.

### Out of scope

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

### Handoff to the planner

One task is enough: the `tst_runs.qml` tests (tests 2-4 red on today's code,
1 and 5 green), the `runProgress` change with its docstring, and the
`tst_runs_screen.qml` `sample()` edit land together, since the screen test goes
red the moment `runProgress` stops reading phases. Follow the writing-plans
format; run `bash tests/run.sh tst_runs` for the red/green steps and
`bash tests/run.sh` at the end.

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/domain/runs.js` | Modify `:395-409` (`runProgress` docstring and body) | the Runs screen's `done/total` for one run |
| `tests/core/domain/tst_runs.qml` | Replace `:1083-1098` (`test_run_progress`) | unit tests of `runProgress` |
| `tests/ui/screens/tst_runs_screen.qml` | Modify `:123-127` (`sample()`: add subtask `status`) | keeps `runRowProgress0` = `1/2` true for the right reason |

One task: the screen test goes red (`0/2`) the moment `runProgress` stops reading phases, so the code change, the unit tests and the screen fixture edit land in one commit.

---

### Task 1: `runProgress` counts real subtasks by their own status

**Files:**
- Modify: `core/domain/runs.js:395-409`
- Test: `tests/core/domain/tst_runs.qml:1083-1098` (replace `test_run_progress`)
- Test: `tests/ui/screens/tst_runs_screen.qml:123-127`

**Interfaces:**
- Consumes (unchanged, in `core/domain/runs.js`): `_subtasksOf(run) -> Array` (`:380`), `_isObject(v) -> bool` (`:168`, false for arrays and null), `_isCardId(id) -> bool` (`:180`). Test helpers in `tst_runs.qml`: `amRun(name) -> {row, status}` (`:14`), `mkRun(id, status, live, opts) -> normalized run` (`:524`; `opts.tree` sets the tree).
- Produces: `Runs.runProgress(run) -> {done: int, total: int}` (same signature as today). New test-local helpers in `tst_runs.qml`: `progressText(p) -> "done/total"`, `subtaskOf(run, cardId) -> subtask object | null`.

- [ ] **Step 1: Replace `test_run_progress` with the new tests**

In `tests/core/domain/tst_runs.qml`, delete the whole `test_run_progress` function (lines 1083-1098 today, from `  function test_run_progress() {` through its closing `  }`, just before `  function test_current_phase() {`). Leave `progressTree()` (lines 1073-1081) exactly as it is: `test_current_phase` still uses it. In place of the deleted function insert:

```qml
  // "done/total" of a runProgress result.
  function progressText(p) { return p.done + "/" + p.total }

  // The subtask of a normalized run with this card id, else null.
  function subtaskOf(run, cardId) {
    var subtasks = run.tree.subtasks
    for (var i = 0; i < subtasks.length; i++) {
      if (subtasks[i].card_id === cardId) return subtasks[i]
    }
    return null
  }

  function test_run_progress_fixtures() {
    var cases = [
      ["status-started.json", "3/8"],
      ["status-done.json", "10/10"],
      ["status-escalated.json", "2/4"],
      ["status-escalated-integrate.json", "2/2"],
      ["status-done-integrate.json", "2/2"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var p = Runs.runProgress(Runs.normalizeRun(amRun(cases[i][0])))
      compare(Object.keys(p).sort().join(","), "done,total", cases[i][0])
      compare(progressText(p), cases[i][1], cases[i][0])
    }
  }

  function test_run_progress_reads_status_not_phases() {
    // synthetic: between two phases -- the started subtask's phases cut to its first, `worktree` done
    var started = Runs.normalizeRun(amRun("status-started.json"))
    var between = subtaskOf(started, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(between.status, "started")
    compare(between.phases.length, 2)
    between.phases = [between.phases[0]]
    compare(between.phases[0].name + ":" + between.phases[0].status, "worktree:done")
    compare(progressText(Runs.runProgress(started)), "3/8", "every recorded phase done, status started")

    // synthetic: a done subtask's status set to started, its phases left all done
    var stalled = Runs.normalizeRun(amRun("status-done.json"))
    var restarted = subtaskOf(stalled, "22153f5f-9632-4b5f-a7dd-664c39d89e5c")
    compare(restarted.status, "done")
    restarted.status = "started"
    compare(progressText(Runs.runProgress(stalled)), "9/10", "status started is not done")

    // synthetic: a done subtask's phases emptied
    var bare = Runs.normalizeRun(amRun("status-done.json"))
    var emptied = subtaskOf(bare, "22153f5f-9632-4b5f-a7dd-664c39d89e5c")
    compare(emptied.status, "done")
    emptied.phases = []
    compare(progressText(Runs.runProgress(bare)), "10/10", "status done without phases is done")

    // synthetic: every subtask's phases replaced by a string
    var garbled = Runs.normalizeRun(amRun("status-escalated.json"))
    for (var i = 0; i < garbled.tree.subtasks.length; i++) garbled.tree.subtasks[i].phases = "x"
    compare(progressText(Runs.runProgress(garbled)), "2/4", "phases not a list")
  }

  function test_run_progress_status_spelling() {
    var cases = [
      ["done", "1/1"],
      ["started", "0/1"], ["pending", "0/1"], ["failed", "0/1"], ["escalated", "0/1"],
      ["stopped", "0/1"], ["cancelled", "0/1"],
      ["Done", "0/1"], ["DONE", "0/1"], [" done", "0/1"], ["", "0/1"],
      [5, "0/1"], [true, "0/1"], [null, "0/1"]
    ]
    for (var i = 0; i < cases.length; i++) {
      // synthetic: one subtask t1 in the given status, every recorded phase done
      var run = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [
        { card_id: "t1", status: cases[i][0], phases: [{ name: "spec", status: "done" }] }] } })
      compare(progressText(Runs.runProgress(run)), cases[i][1], "status " + JSON.stringify(cases[i][0]))
    }
    // synthetic: one subtask t1 with no status, every recorded phase done
    var missing = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "spec", status: "done" }] }] } })
    compare(progressText(Runs.runProgress(missing)), "0/1", "missing status")
    // synthetic: one done subtask t1 with no phases key
    var noPhases = mkRun("r1", "done", null, { tree: { stories: [], subtasks: [{ card_id: "t1", status: "done" }] } })
    compare(progressText(Runs.runProgress(noPhases)), "1/1", "done without phases")
  }

  function test_run_progress_counts_real_subtasks_only() {
    // synthetic: garbage, id-less and synthetic-id subtasks beside a real done t1 and a real started t2
    var mixed = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [
      null, "x", 5, [], {}, { status: "done" }, { card_id: "", status: "done" },
      { card_id: 7, status: "done" }, { card_id: "integrate", status: "done" },
      { card_id: "bases", status: "done" }, { card_id: "base-s1", status: "done" },
      { card_id: "t1", status: "done" }, { card_id: "t2", status: "started" }] } })
    compare(progressText(Runs.runProgress(mixed)), "1/2", "only t1 and t2 count")

    // synthetic: only synthetic-id subtasks, all done
    var bookkeeping = mkRun("r1", "done", null, { tree: { stories: [], subtasks: [
      { card_id: "integrate", status: "done" }, { card_id: "bases", status: "done" },
      { card_id: "base-s1", status: "done" }] } })
    compare(progressText(Runs.runProgress(bookkeeping)), "0/0", "bookkeeping ids are no subtasks")

    // synthetic: junk subtasks only
    var junk = Runs.runProgress({ tree: { subtasks: [null, "x", 5, { phases: "x" }] } })
    compare(progressText(junk), "0/0", "junk subtasks never count")
  }

  function test_run_progress_garbage() {
    // synthetic: a hand-built run with no subtasks
    compare(progressText(Runs.runProgress(mkRun("r", "started", true))), "0/0", "no subtasks")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" }, { tree: { subtasks: "y" } },
               { tree: { subtasks: null } }, { tree: null }]
    for (var i = 0; i < bad.length; i++) {
      var p = Runs.runProgress(bad[i])
      compare(Object.keys(p).sort().join(","), "done,total", "garbage " + i)
      compare(progressText(p), "0/0", "garbage " + i)
    }
  }
```

- [ ] **Step 2: Give the Runs screen's hand-built subtasks their status**

In `tests/ui/screens/tst_runs_screen.qml`, `sample()` (lines 121-132 today), replace these lines (123-127):

```qml
      run("run-20261004-live0001", "started", true, { milestone: "alpha", started_at: ago(5 * tc.minute), tree: { stories: [], subtasks: [
        { card_id: "t1", phases: [{ name: "spec", status: "done" }] },
        { card_id: "t2", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] }] } }),
      run("run-20261004-escl0002", "escalated", null, { milestone: "beta", tree: { stories: [], subtasks: [
        { card_id: "t3", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } }),
```

with:

```qml
      run("run-20261004-live0001", "started", true, { milestone: "alpha", started_at: ago(5 * tc.minute), tree: { stories: [], subtasks: [
        { card_id: "t1", status: "done", phases: [{ name: "spec", status: "done" }] },
        { card_id: "t2", status: "started", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] }] } }),
      run("run-20261004-escl0002", "escalated", null, { milestone: "beta", tree: { stories: [], subtasks: [
        { card_id: "t3", status: "escalated", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } }),
```

No other line of the file changes; no assertion changes.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes; `tst_runs.qml` reports FAILs, at least:
- `test_run_progress_reads_status_not_phases` — `"4/8"` vs `"3/8"` (between two phases);
- `test_run_progress_status_spelling` — `"1/1"` vs `"0/1"` for `"started"`;
- `test_run_progress_counts_real_subtasks_only` — `"0/9"` vs `"1/2"`.
`test_run_progress_fixtures` and `test_run_progress_garbage` PASS (the old rule gives the same numbers on the captures). `tst_runs_screen.qml` and `tst_runs_flow.qml` PASS (today's `runProgress` ignores `status`). If any of the three named tests passes, stop: the test does not exercise the new rule.

- [ ] **Step 4: Change `runProgress`**

In `core/domain/runs.js`, replace lines 395-409 today:

```js
// How many of the run's subtasks are through. A subtask is done when it has
// phases and every one of them is `done`; only object subtasks count at all.
function runProgress(run) {
  var subtasks = _subtasksOf(run)
  var done = 0, total = 0
  for (var i = 0; i < subtasks.length; i++) {
    if (!_isObject(subtasks[i])) continue
    total += 1
    var phases = _arrayOr(subtasks[i].phases)
    var allDone = phases.length > 0
    for (var j = 0; allDone && j < phases.length; j++) allDone = _isObject(phases[j]) && phases[j].status === "done"
    if (allDone) done += 1
  }
  return { done: done, total: total }
}
```

with:

```js
// Counts of the run's real subtasks (an object with a real card id) and of those whose own
// `status` is `done`.
function runProgress(run) {
  var subtasks = _subtasksOf(run)
  var done = 0, total = 0
  for (var i = 0; i < subtasks.length; i++) {
    var subtask = subtasks[i]
    if (!_isObject(subtask) || !_isCardId(subtask.card_id)) continue
    total += 1
    if (subtask.status === "done") done += 1
  }
  return { done: done, total: total }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes; every `tst_runs.qml`, `tst_runs_screen.qml` and `tst_runs_flow.qml` test passes (`Totals: … 0 failed` for each), no `TypeError`/`ReferenceError` lines, exit 0.

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest (including `tests/architecture`) passes; every QML file prints `Totals: … 0 failed`; exit status 0 (`echo $?` prints `0`).

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/ui/screens/tst_runs_screen.qml
git commit -m "feat(runs): runProgress counts real subtasks by their own status

runProgress counts subtasks with a real card id and calls one done when
am's own status says done, never by its phases, so a subtask between two
phases no longer reads as done. The Runs screen test's hand-built
subtasks carry the status their phases describe."
```

---

## Self-Review (against the spec)

- **Spec coverage.** Behavior/signature and garbage → `test_run_progress_garbage` + Step 4. Which subtasks count → `test_run_progress_counts_real_subtasks_only`, `_isCardId` filter in Step 4. Which are done (exact `done`, phases / rows / status / lease unread) → `test_run_progress_status_spelling`, `test_run_progress_reads_status_not_phases`; Step 4 reads only `card_id` and `status`. Comments → Step 4 docstring (no phases). What does not change → `currentPhase` and `progressTree()` untouched (Step 1), `RunsScreen.qml` untouched. Hand-built runs in UI tests → Step 2, exactly the spec's table. Tests 1-6 → Steps 1-2. Suite → Step 6. Acceptance numbers 3/8, 10/10, 2/4, 2/2, 2/2 → `test_run_progress_fixtures`.
- **Red/green.** Old rule on test 2 (a) gives 4/8, (b) 10/10, (c) 9/10, (d) 0/4; test 3 non-done statuses with an all-done phase give 1/1 and `done` without phases gives 0/1; test 4 gives 0/9, the bookkeeping case 0/3, junk 0/1. Tests 1 and 5 pass on old code by design (spec: fixture facts).
- **Beyond the spec.** Test 3's subtasks carry one all-done phase and add a `done`-without-`phases` case, so the spelling rows also prove phases are ignored; test 5 also checks the result keys per garbage input. Both stay within the spec's rules.
- **Placeholders / names.** None; `progressText`, `subtaskOf`, `amRun`, `mkRun`, `Runs.normalizeRun`, `Runs.runProgress` are used with one spelling throughout; no test name ends in `_data`.
<!-- task-pipeline: validated -->
