# 2.4 runs.js: a Run detail subtask opens on an attempt that exists — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Run detail subtask node opens on its first `started` phase, else on its last phase that has a numbered attempt, else on its last phase, so a finished subtask opens on `review.1` instead of `mark_done` with attempt 0.

**Architecture:** One function changes in `core/domain/runs.js`: `_subtaskNode` (lines 584-613 today, contract comment at 584-587 included) tracks a third candidate, `numbered` (the last considered phase whose `_newestAttempt` is `> 0`), and picks `started`, else `numbered`, else `last`. `_newestAttempt` and `_attemptNumber` are used unchanged. `tests/core/domain/tst_runs.qml` gains three tests (real fixtures, a `synthetic:` edit of a fresh fixture copy, a hand-built rule table) and one helper; `test_run_tree` stays as is.

**Tech Stack:** Qt 6 QML / V4 JavaScript (`.pragma library`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh [path-substring]` (pytest runs first, then every `tst_*.qml` whose path contains the substring; `core/domain/tst_runs` matches only `tests/core/domain/tst_runs.qml`).

**Spec:** `docs/superpowers/specs/2-4-runs-js-a-run-c7cfa719.md` (prepended below, headings demoted one level; executors read both).

## Global Constraints

- Code: only `_subtaskNode` and the comment above it change in `core/domain/runs.js` (lines 584-613 today). `runTree`, `_newestAttempt`, `_attemptNumber`, `defaultAttempt`, `attemptStatus`, `cardRunState`, `currentPhase` (run-level, `runs.js:410`), `escalationReason`, `glyphStateOf`, `normalizeRun` are **not edited**.
- A node keeps exactly the keys `card_id, status, phases, attempts, currentPhase, currentAttempt`; `card_id`, `status`, `phases`, `attempts` are computed exactly as today.
- Considered phases: elements of `subtask.phases` in order that are objects with a non-empty string `name` (today's filter). Skipped phases are never current.
- `currentPhase`: name of the first considered phase whose `status === "started"`; else the **last by position** considered phase with `_newestAttempt(p) > 0`; else the last considered phase; else `""`.
- `currentAttempt`: `_newestAttempt(current)`; `0` when the phase has no numbered attempt or there is no current phase. A started phase with no attempts wins with attempt `0`.
- A numbered attempt is an object whose `attempt` or `n` is a finite number `> 0` (`_attemptNumber`). Non-array `attempts`, non-object attempts, `0`, negative, string, `Infinity` numbers never make a phase numbered. A `status` other than the exact string `"started"` (`"running"`, `null`, a number) never wins the first rule.
- Never throws. `core/domain/runs.js` stays `.pragma library` with exactly `.import "board.js" as Board`; `docs/architecture.md` layering holds and `tests/architecture` passes.
- Docstrings and comments state the contract only, no narrative.
- Tests asserting behaviour on real data normalize a capture via `amRun(name)` (`tests/helpers/amFixtures.js` `F.load`, fresh parse per call). An edit to a fixture inside a test is made on a fresh `amRun` copy, keeps the shape (same keys as neighbouring elements) and carries a `// synthetic:` comment. Hand-built normalized runs (`mkRun`) are allowed past `normalizeRun` and are labelled `synthetic:`.
- Not changed: the normalized shape, the tree node's keys, `RunDetailScreen.qml`, `PhaseTimeline`, `docs/architecture.md`, the fixtures, the existing `test_run_tree`.
- `tests/ui/screens/tst_run_detail_screen.qml`: no edit expected; edit only an assertion that fails because it depended on the old fallback.
- No QML test function name may end in `_data` (QtTest treats it as a data provider and never runs it).
- `bash tests/run.sh` green at the end; tests first (red before green). Never `git stash`.

## Review Focus

1. A finished subtask whose trailing deterministic phases (`verify`, `mark_done`) have no attempts, or only an unnumbered attempt, after a numbered agent phase: a person expects it to open on that agent phase's newest attempt (`review.1`), not on attempt 0. Pinned in Task 1 by `test_fixture_run_tree_open_attempt` (every `status-done.json` node) and `test_run_tree_open_attempt_rule` case `a` (`mark_done` with `[{status: "done"}]`).
2. A `started` phase listed after numbered phases (an agent or deterministic phase in flight later in the subtask): expected to open on the started phase, attempt 0 when it has none. Pinned in Task 1 by `test_fixture_run_tree_started_deterministic_phase` and `test_run_tree_open_attempt_rule` case `e`.
3. An escalated subtask whose last phase failed with a numbered attempt (`status-escalated.json` `eb8b1851…` ends on `review` failed `[1]`): expected `review` / 1, so its failing attempt opens. Pinned in Task 1 by `test_fixture_run_tree_open_attempt` (escalated part).
4. A subtask whose phases are all unnamed / non-objects, or whose `phases` is `[]` or missing: expected `""` / 0, never a throw. Pinned in Task 1 by `test_fixture_run_tree_open_attempt` (four pending nodes) and `test_run_tree_open_attempt_rule` cases `f` and `g`.
5. A status spelled `"running"` (not am's `"started"`) on a later phase: expected not to win the first rule; the node opens on the last numbered phase. Pinned in Task 1 by `test_run_tree_open_attempt_rule` case `h`.

---

## Spec (prepended; headings demoted one level)

## 2.4 runs.js: a Run detail subtask opens on an attempt that exists — design

Card `c7cfa719`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `8ad57065` (2.3, `runProgress`, committed at `cf72f02`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 2 (parent L324-326) lists "`normalizeRun` …,
then `rollup`, `runProgress`, `runTree`'s open attempt, …": this subtask is
`runTree`'s open attempt only, i.e. the `currentPhase` / `currentAttempt` of
each subtask node built by `_subtaskNode` (`core/domain/runs.js:584-613`).

### Goal

Run detail opens a subtask on its node's `currentPhase` / `currentAttempt`:
the row label shows `phase.attempt` (`ui/screens/RunDetailScreen.qml:106-109`)
and a click selects that attempt only when `currentAttempt > 0`
(`RunDetailScreen.qml:364-365`). Today a node with no `started` phase opens on
its **last** phase. Real am ends every finished subtask with deterministic
phases (`verify`, `mark_done`) that never have attempts (parent L29-30), so a
finished subtask opens on `mark_done` with attempt 0: its label has no attempt
and clicking it does nothing (parent L105, L122). After this subtask the node
opens on the first `started` phase, else the **last phase that has a numbered
attempt** (the attempt `am logs` would show by default), else the last phase.

### Inherited constraints

| constraint | source |
|---|---|
| Decision 4: a tree node's current phase is its first `started` phase, else its last phase with a numbered attempt (am logs' own default), else its last phase | parent L160-162 |
| Phases are recorded as they are reached (a pending subtask has `[]`); deterministic phases never have attempts | parent L28-30 |
| An attempt's number is `n` | parent L31-32 |
| Consumer table: `_subtaskNode` "opens on the first started phase else the LAST phase": a finished subtask opens on `mark_done.0` | parent L105 |
| Consumer table: `RunDetailScreen.qml:364-365` reads a node's `currentPhase/currentAttempt`; a finished subtask cannot be opened | parent L122 |
| Acceptance: `runTree` of `status-done.json` — each node `done`, current `review.1`, 7 attempts, 14 phases | parent L224-226 |
| Acceptance: the started run's `299ec9c0…` is at `explore`, attempt 1 | parent L213, L221-222 |
| Tests of `runs.js` helpers past `normalizeRun` may build normalized runs by hand; a test asserting behaviour on real data normalizes a fixture; an edit to a fixture inside a test is made on a fresh copy, labelled, and never changes the shape | parent L257-267, card |
| QML loads fixtures with `tests/helpers/amFixtures.js` `load(name)` (fresh parse each call) | parent L269-274 |
| Not changed: the normalized shape and the tree node's keys; screen layouts; deterministic-phase logs (`am logs` without an attempt number) | parent L306-317 |
| `docs/architecture.md` layering (`core/domain/*.js` is pure JS, never throws); `tests/architecture` passes | card |
| Docstrings and comments state the contract only, no narrative | card |
| `bash tests/run.sh` green; tests first | card |

### Fixture facts this design relies on (checked 2026-10-05)

Phases (name, kind, status, attempt numbers) of the subtasks the tests read:

- `status-done.json`: all 10 subtasks are `done` with the same 14 phases:
  `worktree` d done `[]`, `explore` a done `[1]`, `mark_in_progress` d,
  `plan_check` d, `spec` a `[1]`, `validate_spec` a `[1]`, `plan` a `[1]`,
  `validate_plan` a `[1]`, `mark_validated` d, `docs_commit` d, `implement` a
  `[1]`, `review` a `[1]`, `verify` d `[]`, `mark_done` d `[]`. No phase is
  `started`. Old rule: `mark_done` / 0. New rule: `review` / 1.
- `status-started.json`: `5eb7ec0c`, `45cc9067`, `a19ca446` are as above
  (`review` / 1); `299ec9c0-b935-4c44-a7a0-982a104cbfe5` is `started` with
  `worktree` d done `[]`, `explore` a **started** `[1]` (`explore` / 1 under both
  rules); `fdb5feb1`, `66a6b6c0`, `dfc0ac87`, `46141e11` are `pending` with
  phases `[]` (`""` / 0 under both rules).
- No capture contains a `started` deterministic phase. The test for it edits a
  fresh copy of `status-started.json` and is labelled `synthetic:`.

So the `status-done.json` assertions fail on today's code; the
`status-started.json` assertions and the started-deterministic case pass on it
and pin that the change keeps them.

### Behavior

Only the two derived fields of a subtask node change. `card_id`, `status`,
`phases`, `attempts`, the node's key set, `runTree`'s grouping, its synthetic
rows and every other `runs.js` function are unchanged.

#### Phases considered

The phases of the node are `subtask.phases` in order, skipping any element that
is not an object or whose `name` is not a non-empty string (the same filter that
builds `node.phases` today). Phases skipped here are never current.

#### `currentPhase`

The `name` of the first of these that applies:

1. the first considered phase whose `status` is exactly `"started"`;
2. otherwise the **last** considered phase (by position, not by attempt number)
   that has at least one numbered attempt — an attempt object whose `n` (or
   legacy `attempt`) is a finite number `> 0`, as `_attemptNumber` reads it;
3. otherwise the last considered phase;
4. otherwise (no considered phase) `""`.

#### `currentAttempt`

The highest attempt number among the current phase's attempts (`_newestAttempt`
of that phase); `0` when the phase has no numbered attempt or there is no
current phase. A `started` phase wins at step 1 even when it has no attempts, so
a started deterministic phase gives its own name and attempt `0`.

#### Error paths

Never throws. `attempts` that is not an array, attempt elements that are not
objects, non-numeric / zero / negative / non-finite `n`: none of these make a
phase "numbered". A `status` that is not the string `"started"` (including
`"running"`, `null`, a number) never wins step 1.

#### Consumers

No UI code changes. `RunDetailScreen.qml` keeps rendering `phase.attempt` when
`currentAttempt > 0` and selecting `(card_id, currentPhase, currentAttempt)` on
click; after this subtask a finished subtask's label reads `… · done · review.1`
and its click selects `review` 1.

#### Contract comment

The comment above `_subtaskNode` (`runs.js:584-587`) states the new rule as a
contract: current phase is the first started one, else the last with a numbered
attempt, else the last; current attempt is that phase's newest number, 0 when it
has none. No narrative.

### Tests

All in `tests/core/domain/tst_runs.qml` (tier: QML unit, run by
`tests/run.sh` under `qmltestrunner`). Why this tier: `_subtaskNode` is pure
domain JS reached only through `Runs.runTree`; the existing `runTree` tests live
here, fixtures load through `amFixtures.js`, and no UI or process boundary is
involved.

1. **`test_fixture_run_tree_open_attempt`** (real data; fails first).
   `Runs.runTree(Runs.normalizeRun(amRun("status-done.json")))`: every node in
   every `stories[].subtasks` (10 nodes) has `currentPhase === "review"` and
   `currentAttempt === 1`. `status-started.json`: node `299ec9c0-b935-4c44-a7a0-982a104cbfe5`
   is `explore` / 1; the three done nodes are `review` / 1; the four pending
   nodes are `""` / 0. Find nodes by `card_id` across `stories[].subtasks`
   (a small local helper; `subtaskOf` at `tst_runs.qml:1086` reads
   `run.tree.subtasks`, not the tree).
2. **`test_fixture_run_tree_started_deterministic_phase`** (synthetic edit of
   real data; guard). Fresh `amRun("status-started.json")`; in its `status`
   locate the `299ec9c0…` subtask; `// synthetic: a deterministic phase in
   flight after a finished agent phase — no capture has one` set `explore`'s
   `status` to `"done"` and append `{ name: "mark_in_progress", kind:
   "deterministic", status: "started", started_at: "", ended_at: null, detail:
   null, attempts: [] }` (same keys as its neighbours: shape unchanged).
   Normalize, `runTree`: that node is `mark_in_progress` / 0.
3. **`test_run_tree_open_attempt_rule`** (hand-built normalized run via
   `mkRun`, allowed past `normalizeRun` by parent L262-265; fails first).
   Subtasks under one story:
   - `a`: `spec` done `[{n: 2}]`, `implement` done `[{n: 1}]`, `verify` done
     `[]`, `mark_done` done `[{status: "done"}]` → `implement` / 1 (last
     numbered by position, not the higher `n: 2`; an unnumbered attempt does
     not count; trailing deterministic phases are passed over).
   - `b`: `plan` started `[]`, `review` done `[{n: 1}]` → `plan` / 0 (started
     wins over a later numbered phase).
   - `c`: `spec` done `[{n: 1}]`, `{ name: "", status: "done", attempts: [{n:
     3}] }`, `null`, `review` done `[{n: 0}, {n: -1}, {n: "2"}, {n: Infinity},
     null]` → `spec` / 1 (unnamed / non-object phases are never current; bad
     numbers do not make a phase numbered).
   - `d`: `worktree` done `[]`, `explore` done `"x"` → `explore` / 0 (nothing
     numbered: the last phase).
4. **Existing `test_run_tree`** (`tst_runs.qml:1418-1455`) stays as is and must
   still pass: `t1` `implement` / 2 (started), `t2` `spec` / 0 (no numbered
   attempt: last phase; its message "no started phase: the last named one"
   stays true), `t4` `review` / 0 (unnumbered attempt).

`tests/ui/screens/tst_run_detail_screen.qml`: no edit expected. Its trees go
through `Runs.runTree` (`RunDetailScreen.qml:34`), but every subtask there whose
open attempt it asserts either has a `started` phase (`t1` → `implement.2`) or
ends on its only, numbered phase (`t2` → `spec.1`), and `t3` has `[]` (selects
nothing): both rules agree. Run it; edit only an assertion that fails because it
depended on the old fallback.

Verification: `bash tests/run.sh` green (pytest architecture/contract/install,
then every QML suite).

### Out of scope

- `defaultAttempt`, `attemptStatus`, `cardRunState`, `currentPhase` (the
  run-level `runs.js:410` one) and their `_newestAttempt` uses
  (`runs.js:681,691`): unchanged.
- `escalationReason` (2.5), `glyphStateOf` (2.6), `logTail` /
  `runs-logs.py --repo-dir` / `RunStore` (story 3), cancel spellings and watch
  schemas (story 4), docs (story 5): sibling cards.
- Opening deterministic-phase logs (parent L316) and Integrate resolver attempts
  in Run detail (parent L339-341).
- `RunDetailScreen.qml` and `PhaseTimeline` code; `docs/architecture.md` (it
  states no open rule for tree nodes).

### Plan handoff

The plan follows the writing-plans format with one task (tests 1-3 red, the
`_subtaskNode` change and its contract comment, all green, screen suite checked,
commit). Review Focus candidates: a phase whose attempts are all unnumbered
placed after a numbered one; a started phase listed after numbered ones; a
subtask whose only phases are unnamed; a phase with a numbered attempt whose
`status` is `failed` (the escalated case — `status-escalated.json` `eb8b1851…`
ends on `review` failed `[1]` → `review` / 1); a node with phases `[]`.

---

## File Structure

| file | change | responsibility |
|---|---|---|
| `core/domain/runs.js` | Modify `_subtaskNode` and its contract comment (lines 584-613 today) | builds one Run detail tree node; picks the phase/attempt it opens on |
| `tests/core/domain/tst_runs.qml` | Add helpers `treeNode`, `opensOn` and tests `test_fixture_run_tree_open_attempt`, `test_fixture_run_tree_started_deterministic_phase` after `test_fixture_run_tree_grouping` (ends at line 450 today); add `test_run_tree_open_attempt_rule` after `test_run_tree_garbage` (ends at line 1479 today) | pins the open rule on real captures and on a hand-built rule table |
| `tests/ui/screens/tst_run_detail_screen.qml` | Run only; no edit expected | the screen still selects the node's attempt |

One task: the three tests are red/green against the same few lines of `_subtaskNode`; a reviewer cannot meaningfully accept one without the other.

---

### Task 1: `_subtaskNode` opens on the last numbered phase when none is started

**Files:**
- Modify: `core/domain/runs.js:584-613` (`_subtaskNode` and the comment above it)
- Test: `tests/core/domain/tst_runs.qml` (new helpers + 3 new tests; existing `test_run_tree` at :1418-1455 untouched)
- Check: `tests/ui/screens/tst_run_detail_screen.qml` (run, no edit expected)

**Interfaces:**
- Consumes (unchanged, already in `core/domain/runs.js`): `_isObject(v)`, `_arrayOr(v)`, `_stringOr(v)`, `_attemptNumber(attemptObj) -> number` (the attempt's `attempt` or `n` when a finite number `> 0`, else `0`), `_newestAttempt(phaseObj) -> number` (highest `_attemptNumber` of `phase.attempts`, `0` when none), `_lastRowStatus(run, id) -> string`. Test side: `amRun(name)` (`tst_runs.qml:15`, returns `{ row, status }` where `status` is the fixture's raw `data`, real subtasks nested in `status.stories[].subtasks[]`), `mkRun(id, status, live, opts)` (`tst_runs.qml:524`), `Runs.normalizeRun(raw)`, `Runs.runTree(run) -> { stories: [{ card_id, label, status, other, subtasks: [node] }], synthetic: [...] }`.
- Produces: `_subtaskNode(run, subtask)` still returns `{ card_id, status, phases, attempts, currentPhase: string, currentAttempt: number }`; only `currentPhase` / `currentAttempt` follow the new rule. Test helpers `treeNode(tree, cardId) -> node | null` and `opensOn(node) -> "phase/attempt"` (local to `tst_runs.qml`).

- [ ] **Step 1: Write the two fixture tests (real data + synthetic edit)**

In `tests/core/domain/tst_runs.qml`, insert right after the closing `}` of `test_fixture_run_tree_grouping` (the line after `for (var k = 0; k < it.stories.length; k++) compare(it.stories[k].other, false, "no Other group " + k)`, line 449-450 today), before `function test_state_running() {`:

```qml

  // The node with this card id in any group of a runTree result, else null.
  function treeNode(tree, cardId) {
    for (var i = 0; i < tree.stories.length; i++) {
      var subtasks = tree.stories[i].subtasks
      for (var j = 0; j < subtasks.length; j++) {
        if (subtasks[j].card_id === cardId) return subtasks[j]
      }
    }
    return null
  }

  // "phase/attempt" a tree node opens on.
  function opensOn(node) { return node === null ? "null" : node.currentPhase + "/" + node.currentAttempt }

  function test_fixture_run_tree_open_attempt() {
    var done = Runs.runTree(Runs.normalizeRun(amRun("status-done.json")))
    var count = 0
    for (var i = 0; i < done.stories.length; i++) {
      for (var j = 0; j < done.stories[i].subtasks.length; j++) {
        var node = done.stories[i].subtasks[j]
        compare(node.status, "done", node.card_id)
        compare(node.phases.length, 14, node.card_id + " phases")
        compare(node.attempts.length, 7, node.card_id + " attempts")
        compare(opensOn(node), "review/1", node.card_id + ": the last phase with a numbered attempt, past verify and mark_done")
        count++
      }
    }
    compare(count, 10, "every done subtask is a node")

    var started = Runs.runTree(Runs.normalizeRun(amRun("status-started.json")))
    var expected = [
      ["5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff", "review/1"],
      ["45cc9067-d6b3-441f-b8d2-6602a81311d2", "review/1"],
      ["a19ca446-659e-4735-86ed-5a583c1730bf", "review/1"],
      ["299ec9c0-b935-4c44-a7a0-982a104cbfe5", "explore/1"],
      ["fdb5feb1-0907-40b2-9937-d9b4cc2875f0", "/0"],
      ["66a6b6c0-5032-4598-b80c-0afb0d0d46b5", "/0"],
      ["dfc0ac87-978b-4419-87c2-61f10b9d0cd1", "/0"],
      ["46141e11-da16-4aa2-8e1a-10e0e23e6980", "/0"]
    ]
    for (var k = 0; k < expected.length; k++)
      compare(opensOn(treeNode(started, expected[k][0])), expected[k][1], "started run " + expected[k][0])

    var escalated = Runs.runTree(Runs.normalizeRun(amRun("status-escalated.json")))
    var expectedEscalated = [
      ["c5e41536-7e1b-448b-aa2d-55e9550e63b2", "review/1"],
      ["231a23cc-91bc-4516-924d-5b19476d5237", "review/1"],
      ["eb8b1851-8245-45c3-9a29-d1fcefaad0b9", "review/1"],
      ["ca31fde7-d22a-43a3-b3da-b1d2d6f9f41e", "/0"]
    ]
    for (var e = 0; e < expectedEscalated.length; e++)
      compare(opensOn(treeNode(escalated, expectedEscalated[e][0])), expectedEscalated[e][1], "escalated run " + expectedEscalated[e][0])
  }

  function test_fixture_run_tree_started_deterministic_phase() {
    var raw = amRun("status-started.json")
    var subtask = null
    for (var i = 0; i < raw.status.stories.length; i++) {
      var list = raw.status.stories[i].subtasks
      for (var j = 0; j < list.length; j++) {
        if (list[j].card_id === "299ec9c0-b935-4c44-a7a0-982a104cbfe5") subtask = list[j]
      }
    }
    verify(subtask !== null, "the started subtask is in the capture")
    compare(subtask.phases.length, 2)
    compare(subtask.phases[1].name + ":" + subtask.phases[1].status, "explore:started")
    // synthetic: a deterministic phase in flight after a finished agent phase -- no capture has one
    subtask.phases[1].status = "done"
    var added = { name: "mark_in_progress", kind: "deterministic", status: "started", started_at: "", ended_at: null, detail: null, attempts: [] }
    compare(Object.keys(added).sort().join(","), Object.keys(subtask.phases[0]).sort().join(","), "same keys as its neighbours")
    subtask.phases.push(added)

    var node = treeNode(Runs.runTree(Runs.normalizeRun(raw)), "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(opensOn(node), "mark_in_progress/0", "a started phase wins over an earlier numbered one, attempt 0 without attempts")
  }
```

- [ ] **Step 2: Write the hand-built rule-table test**

In `tests/core/domain/tst_runs.qml`, insert right after the closing `}` of `test_run_tree_garbage` (after the line `compare(odd.stories[1].subtasks[0].attempts.length, 0)` and its `}`, lines 1478-1479 today), before `function at(d) {`:

```qml

  function test_run_tree_open_attempt_rule() {
    // synthetic: hand-built normalized subtasks, one per case of the open rule
    var t = Runs.runTree(mkRun("r", "done", null, { tree: {
      stories: [{ card_id: "s1", subtasks: ["a", "b", "c", "d", "e", "f", "g", "h", "i"] }],
      subtasks: [
        { card_id: "a", status: "done", phases: [
          { name: "spec", status: "done", attempts: [{ n: 2 }] },
          { name: "implement", status: "done", attempts: [{ n: 1 }] },
          { name: "verify", status: "done", attempts: [] },
          { name: "mark_done", status: "done", attempts: [{ status: "done" }] }] },
        { card_id: "b", status: "started", phases: [
          { name: "plan", status: "started", attempts: [] },
          { name: "review", status: "done", attempts: [{ n: 1 }] }] },
        { card_id: "c", status: "done", phases: [
          { name: "spec", status: "done", attempts: [{ n: 1 }] },
          { name: "", status: "done", attempts: [{ n: 3 }] },
          null,
          { name: "review", status: "done", attempts: [{ n: 0 }, { n: -1 }, { n: "2" }, { n: Infinity }, null] }] },
        { card_id: "d", status: "done", phases: [
          { name: "worktree", status: "done", attempts: [] },
          { name: "explore", status: "done", attempts: "x" }] },
        { card_id: "e", status: "started", phases: [
          { name: "spec", status: "done", attempts: [{ n: 1 }] },
          { name: "implement", status: "started", attempts: [] }] },
        { card_id: "f", status: "pending", phases: [null, { name: "" }, { name: 5, status: "started", attempts: [{ n: 1 }] }] },
        { card_id: "g", status: "pending" },
        { card_id: "h", status: "started", phases: [
          { name: "spec", status: "done", attempts: [{ n: 1 }] },
          { name: "implement", status: "running", attempts: [] },
          { name: "review", status: null, attempts: [] },
          { name: "verify", status: 5, attempts: [] }] },
        { card_id: "i", status: "done", phases: [
          { name: "spec", status: "done", attempts: [{ attempt: 2, status: "done" }] },
          { name: "verify", status: "done", attempts: [] }] }
      ] } }))
    compare(cardIds(t.stories[0].subtasks), "a,b,c,d,e,f,g,h,i")
    compare(opensOn(treeNode(t, "a")), "implement/1", "the last numbered phase by position, not the highest n; unnumbered and empty trailing phases passed over")
    compare(opensOn(treeNode(t, "b")), "plan/0", "a started phase wins over a later numbered one")
    compare(opensOn(treeNode(t, "c")), "spec/1", "unnamed and non-object phases are never current; bad numbers are not numbered")
    compare(opensOn(treeNode(t, "d")), "explore/0", "nothing numbered: the last phase")
    compare(opensOn(treeNode(t, "e")), "implement/0", "a started phase after a numbered one wins")
    compare(opensOn(treeNode(t, "f")), "/0", "only unnamed phases: no current phase")
    compare(opensOn(treeNode(t, "g")), "/0", "no phases")
    compare(opensOn(treeNode(t, "h")), "spec/1", "only the exact status started wins the first rule")
    compare(opensOn(treeNode(t, "i")), "spec/2", "a legacy attempt number counts")
  }
```

- [ ] **Step 3: Run the domain suite to verify the new tests fail**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: pytest passes, then under `== tests/core/domain/tst_runs.qml`:
- `FAIL!  : DomainRuns::test_fixture_run_tree_open_attempt() Compared values are not the same` — `Actual: "mark_done/0"`, `Expected: "review/1"` (first done node).
- `FAIL!  : DomainRuns::test_run_tree_open_attempt_rule() Compared values are not the same` — `Actual: "mark_done/0"`, `Expected: "implement/1"` (case `a`).
- `test_fixture_run_tree_started_deterministic_phase` and `test_run_tree` PASS (both rules agree on them).
- `Totals:` shows exactly 2 failed. If any other test fails, or a `TypeError` / `ReferenceError` line is printed, fix the test code before going on.

- [ ] **Step 4: Change `_subtaskNode` and its contract comment**

In `core/domain/runs.js`, replace the whole block from the comment line `// One subtask as the detail tree shows it. Its own status, else its last am` through the closing `}` of `_subtaskNode` (lines 584-613 today), which currently reads:

```js
// One subtask as the detail tree shows it. Its own status, else its last am
// row's; phases with a name only; every attempt object (attempt 0 when it has
// no number); the current phase is the first started one, else the last.
function _subtaskNode(run, subtask) {
  var phases = [], attempts = []
  var started = null, last = null
  var list = _arrayOr(subtask.phases)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!_isObject(p) || typeof p.name !== "string" || p.name === "") continue
    phases.push({ name: p.name, status: _stringOr(p.status) })
    if (started === null && p.status === "started") started = p
    last = p
    var tries = _arrayOr(p.attempts)
    for (var k = 0; k < tries.length; k++) {
      if (_isObject(tries[k])) attempts.push({ phase: p.name, attempt: _attemptNumber(tries[k]), status: _stringOr(tries[k].status) })
    }
  }
  var current = started !== null ? started : last
  var own = _stringOr(subtask.status)
  return {
    card_id: subtask.card_id,
    status: own !== "" ? own : _lastRowStatus(run, subtask.card_id),
    phases: phases,
    attempts: attempts,
    currentPhase: current === null ? "" : current.name,
    currentAttempt: _newestAttempt(current)
  }
}
```

with:

```js
// One subtask as the detail tree shows it. Its own status, else its last am
// row's; phases with a name only; every attempt object (attempt 0 when it has
// no number). The current phase is the first started one, else the last one
// with a numbered attempt, else the last; the current attempt is that phase's
// newest number, 0 when it has none.
function _subtaskNode(run, subtask) {
  var phases = [], attempts = []
  var started = null, numbered = null, last = null
  var list = _arrayOr(subtask.phases)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!_isObject(p) || typeof p.name !== "string" || p.name === "") continue
    phases.push({ name: p.name, status: _stringOr(p.status) })
    if (started === null && p.status === "started") started = p
    if (_newestAttempt(p) > 0) numbered = p
    last = p
    var tries = _arrayOr(p.attempts)
    for (var k = 0; k < tries.length; k++) {
      if (_isObject(tries[k])) attempts.push({ phase: p.name, attempt: _attemptNumber(tries[k]), status: _stringOr(tries[k].status) })
    }
  }
  var current = started !== null ? started : numbered !== null ? numbered : last
  var own = _stringOr(subtask.status)
  return {
    card_id: subtask.card_id,
    status: own !== "" ? own : _lastRowStatus(run, subtask.card_id),
    phases: phases,
    attempts: attempts,
    currentPhase: current === null ? "" : current.name,
    currentAttempt: _newestAttempt(current)
  }
}
```

Nothing else in `runs.js` changes.

- [ ] **Step 5: Run the domain suite to verify everything passes**

Run: `bash tests/run.sh core/domain/tst_runs`
Expected: pytest passes; `tests/core/domain/tst_runs.qml` prints `Totals: N passed, 0 failed` with no `FAIL!` line and no `TypeError` / `ReferenceError` line. `test_run_tree` still passes (`t1` `implement`/2, `t2` `spec`/0, `t4` `review`/0).

- [ ] **Step 6: Run the Run detail screen suite**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: `tests/ui/screens/tst_run_detail_screen.qml` prints `Totals: N passed, 0 failed`. No edit is expected (its `t1` opens on `implement.2` via a started phase, `t2` on its only numbered phase `spec.1`, `t3` has no phases). If an assertion fails, edit only that assertion, and only when it depended on the old "else the last phase" fallback (the node now opens on its last numbered phase); never change `RunDetailScreen.qml`.

- [ ] **Step 7: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit code 0; pytest (including `tests/architecture`) passes; every `== tests/...tst_*.qml` block prints `Totals: … 0 failed` and no `TypeError` / `ReferenceError` / `is not a function` lines.

- [ ] **Step 8: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): a Run detail subtask opens on its last numbered attempt

A tree node's current phase is its first started phase, else its last
phase with a numbered attempt, else its last phase, so a finished
subtask opens on review.1 instead of mark_done with no attempt."
```

(Add `tests/ui/screens/tst_run_detail_screen.qml` to `git add` only if Step 6 required an edit.)

---

## Self-Review

- **Spec coverage:** Behavior "Phases considered" → the unchanged filter in Step 4, pinned by case `c`/`f`. `currentPhase` rules 1-4 → Step 4 `current = started ?? numbered ?? last`, pinned by cases `b`/`e` (1), `a`/`c`/`i` and fixtures (2), `d` (3), `f`/`g` and pending nodes (4). `currentAttempt` → `_newestAttempt(current)` unchanged, pinned by `mark_in_progress/0`, `plan/0`. Error paths → cases `c`, `d`, `f`, `h`. Consumers → Step 6. Contract comment → Step 4. Tests 1-3 of the spec → Steps 1-2 (escalated fixture added from the spec's Review Focus candidates). Test 4 (existing `test_run_tree`) → Step 5. Verification → Step 7.
- **Placeholders:** none; every step has its code or command.
- **Type consistency:** `treeNode(tree, cardId)` and `opensOn(node)` are defined in Step 1 and used in Steps 1-2; `cardIds` (`tst_runs.qml:1409`) and `mkRun` (`:524`) exist; `numbered` is used only in Step 4.
- **Review Focus:** all five lines are pinned in Task 1 tests (see each line).
<!-- task-pipeline: validated -->
