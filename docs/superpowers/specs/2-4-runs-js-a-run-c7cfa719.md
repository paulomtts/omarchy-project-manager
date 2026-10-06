# 2.4 runs.js: a Run detail subtask opens on an attempt that exists — design

Card `c7cfa719`, a subtask of story `21f9cd5a` ("Normalize real am status"),
blocked by `8ad57065` (2.3, `runProgress`, committed at `cf72f02`). Parent spec:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below:
**parent**). Work breakdown item 2 (parent L324-326) lists "`normalizeRun` …,
then `rollup`, `runProgress`, `runTree`'s open attempt, …": this subtask is
`runTree`'s open attempt only, i.e. the `currentPhase` / `currentAttempt` of
each subtask node built by `_subtaskNode` (`core/domain/runs.js:584-613`).

## Goal

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

## Inherited constraints

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

## Fixture facts this design relies on (checked 2026-10-05)

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

## Behavior

Only the two derived fields of a subtask node change. `card_id`, `status`,
`phases`, `attempts`, the node's key set, `runTree`'s grouping, its synthetic
rows and every other `runs.js` function are unchanged.

### Phases considered

The phases of the node are `subtask.phases` in order, skipping any element that
is not an object or whose `name` is not a non-empty string (the same filter that
builds `node.phases` today). Phases skipped here are never current.

### `currentPhase`

The `name` of the first of these that applies:

1. the first considered phase whose `status` is exactly `"started"`;
2. otherwise the **last** considered phase (by position, not by attempt number)
   that has at least one numbered attempt — an attempt object whose `n` (or
   legacy `attempt`) is a finite number `> 0`, as `_attemptNumber` reads it;
3. otherwise the last considered phase;
4. otherwise (no considered phase) `""`.

### `currentAttempt`

The highest attempt number among the current phase's attempts (`_newestAttempt`
of that phase); `0` when the phase has no numbered attempt or there is no
current phase. A `started` phase wins at step 1 even when it has no attempts, so
a started deterministic phase gives its own name and attempt `0`.

### Error paths

Never throws. `attempts` that is not an array, attempt elements that are not
objects, non-numeric / zero / negative / non-finite `n`: none of these make a
phase "numbered". A `status` that is not the string `"started"` (including
`"running"`, `null`, a number) never wins step 1.

### Consumers

No UI code changes. `RunDetailScreen.qml` keeps rendering `phase.attempt` when
`currentAttempt > 0` and selecting `(card_id, currentPhase, currentAttempt)` on
click; after this subtask a finished subtask's label reads `… · done · review.1`
and its click selects `review` 1.

### Contract comment

The comment above `_subtaskNode` (`runs.js:584-587`) states the new rule as a
contract: current phase is the first started one, else the last with a numbered
attempt, else the last; current attempt is that phase's newest number, 0 when it
has none. No narrative.

## Tests

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

## Out of scope

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

## Plan handoff

The plan follows the writing-plans format with one task (tests 1-3 red, the
`_subtaskNode` change and its contract comment, all green, screen suite checked,
commit). Review Focus candidates: a phase whose attempts are all unnumbered
placed after a numbered one; a started phase listed after numbered ones; a
subtask whose only phases are unnamed; a phase with a numbered attempt whose
`status` is `failed` (the escalated case — `status-escalated.json` `eb8b1851…`
ends on `review` failed `[1]` → `review` / 1); a node with phases `[]`.
