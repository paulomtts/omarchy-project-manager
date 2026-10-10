# 1.2 runs.js: stopReport (card 9a37bb47)

Narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md` (the "resume and
recover" design, here **RR**): "Why it stopped (Run detail)" (lines 124-163, above all the
four state bullets at 141-148 and the failed-output bullet at 156-160), "Relaunch" (lines
200-215, the target rule at 206-208), "Architecture" bullet `stopReport` (lines 243-248), the
`cancelled`/`canceled` edge case (line 298) and "Testing" bullet 1 (lines 302-306). Parent
story 7d1f5810. Blocked by d567a725 (1.1, `controls` / `controlError` / `offersRelaunch`),
which is merged on this branch (`80205bd`).

## Starting point

`core/domain/runs.js` (`.pragma library`, pure, never throws) already has everything the
report reads:

- `normalizeRun(raw)` (`runs.js:45-142`): the aligned model. It keeps `id`, `repo_dir`,
  `milestone_id`, `status`, `started_at`, `base_branch`, `branch_prefix`, `workflow`,
  `lease` (`pid`, `host`, `heartbeat_at`, `accepting`, `live`), `project`, `requests`,
  `rows` (`{story_id, card_id, phase, attempt, status}`) and `tree` (`stories`: copies of
  am's stories, `title` and `status` included, `subtasks` reduced to id strings, the
  synthetic `integrate` and `bases` stories kept; `subtasks`: the real stories' subtasks,
  flattened, each a copy with `story_id`, its `status` and its `phases` with `attempts`).
  It does **not** keep the `am runs` row's `card_id` or `story_id` (both present on every
  row, `tests/fixtures/am/runs.json`, and `story_id` on am status's `run` too).
- `runState(run)` (`runs.js:150-161`): `stopped` → `parked`, `cancelled` and `canceled` →
  `cancelled`, `started` with a lease that is not live (or none) → `dead`, `escalated`,
  `done`, `running`, else `unknown`.
- Private helpers: `_isObject`, `_arrayOr`, `_stringOr`, `_treeOf`, `_copyOf`,
  `_isSynthetic` / `_isCardId` (`:195-199`), `_findByCardId` (`:201`), `_textOf` (`:466`),
  `_FAILURE_STATUSES` (`:472`), `_subtasksOf` (`:524`), `_attemptNumber` /
  `_newestAttempt` (`:694-707`, 0 when a phase has no numbered attempt), `_findPhase`
  (`:710`), `_syntheticLabel` (`:728`: `Integrate`, `Bases`, `Base <id after "base-">`),
  the label `runTree` gives a synthetic node (`:772-818`).
- `escalationReason(run)` (`:478-503`): the detail rule this card reuses (a failed phase's
  `detail`, else its attempts' `detail` from the last attempt back).

## Scope

1. `normalizeRun` gains two output scalars, `card_id` and `story_id` (text; the row's, else
   am status run's; `""` when neither has one). This is the minimum the `relaunch` rule needs
   (RR 206-208: "a `task` run its card, a story run (S7) its story"); without it the
   normalized run does not name a card or story run's target.
2. A new function `stopReport(run)` in a new section `// ---- Why it stopped (RR 1.2)`
   placed after `offersRelaunch` (`runs.js:952-955`) and before `// ---- Run alerts`.

Both changes are tested in `tests/core/domain/tst_runs.qml`. Tests first.

Constraints (inherited):

- `runs.js` is a hot file: the diff stays inside `normalizeRun`'s return object and header
  comment, and the new section (RR 236-237).
- File style (`docs/architecture.md` line 157 and the sibling 1.1 spec
  `1-1-runs-js-resume-d567a725.md`): `var` / `function`, no `const` / `let` / arrows,
  private names prefixed `_`, one contract-only comment above each function (no
  narrative), plain ASCII strings (no glyph such as the escalated mark in any headline;
  `tests/architecture/test_icon_glyphs.py`). No UI import; `tests/architecture` must pass.
- Reads only the normalized run, never brd status (RR 248). No events.
- Never throws; never mutates its input; every object and array it returns is fresh (no
  reference into the run).
- Ids are compared with `===` by linear scan, so `__proto__`, `constructor` behave like any
  other id.

### Out of scope

Everything else in RR, owned by sibling cards: `stopComment` and am's note, the store's
attempt choice on selection (`selectAttempt` accepting 0, opening `stopReport(run).attempt`),
`runs-logs.py` attempt 0, `lastControlErrorType`, the resume dialog, `relaunchOpenFor`,
`StopReasonBlock`, `RunDetailScreen` wiring, deciding when Relaunch is offered (the report
only names the target), and docs. No file under `ui/`, `core/stores/` or `core/backend/` is
touched. `controls`, `controlError`, `offersRelaunch`, `escalationReason`, `defaultAttempt`,
`runTree` and every other existing function keep their behaviour.

## Behaviour

### `normalizeRun`: `card_id` and `story_id`

- `card_id`: `firstText(row.card_id, run.card_id)` where `run` is am status's `run`;
  `story_id`: `firstText(row.story_id, run.story_id)`. Same text rule as the other scalars:
  `null` / `undefined` → `""`, anything else `String(v)`.
- On every recorded fixture both are `""` (milestone runs: `card_id: null`,
  `story_id: null` on the row and in `run`).
- The output key set becomes
  `base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow`.
  The header comment's "Output scalars" sentence names the two: `card_id` and `story_id` are
  the row's, else the am status run's.

### `stopReport(run)`

Returns `null` unless `runState(run)` is `escalated`, `parked`, `dead` or `cancelled` (so
`null` for `running`, `done`, `unknown`, and for anything that is not a run object). Else a
fresh object with exactly these keys:

| key | type | meaning |
|---|---|---|
| `state` | string | `runState(run)`: `escalated`, `parked`, `dead` or `cancelled` |
| `headline` | string | one sentence, per state below |
| `cardId` | string | the real subtask card the report names, else `""` |
| `storyId` | string | that subtask's `story_id`; for a synthetic node, the node's id; else `""` |
| `storyTitle` | string | the trimmed `title` of the tree story whose `card_id === storyId`; for a synthetic node, its `runTree` label; else `""` |
| `phase` | string | the named phase, else `""` |
| `detail` | string | trimmed detail text, else `""` (only `escalated` sets it) |
| `heartbeatAt` | string | `dead` only: the text of `run.lease.heartbeat_at` (`""` without a lease); `""` for the other states |
| `attempt` | object or null | `{card_id, phase, attempt}` the output pane opens, or `null` |
| `parked` | array of strings | the `card_id` of every real subtask (`_isCardId`) whose `status === "stopped"`, in tree order, for every state |
| `relaunch` | object or null | the relaunch target, below, for every state |

"Real subtask" means an object in `tree.subtasks` with `_isCardId(card_id)`. `attempt.attempt`
is the phase's newest numbered attempt (`_newestAttempt`), **0 when the phase records none**
(a deterministic step such as `verify`, RR 50-56 and 156-160); `attempt` is `null` when the
report names no real card and phase.

#### Escalated (RR 141-143)

The subject is chosen in this order; the first that matches wins:

1. **The escalated subtask.** The first real subtask whose `status === "escalated"`, else
   the first real subtask with a phase whose `status === "failed"`.
   - `phase`: its first phase with `status === "failed"` and a non-empty string `name`;
     else the `phase` of its last row (`run.rows`, walked from the end, `card_id` equal)
     whose `status` is in `_FAILURE_STATUSES` and whose `phase` is non-empty; else `""`.
   - `detail`: when that phase is in the subtask's tree, its trimmed `detail`, else the
     trimmed `detail` of its attempts from the last back (the first non-empty) — the same
     rule as `escalationReason`; else `""`.
   - `attempt`: `{card_id, phase, attempt: max(_newestAttempt(tree phase), the row's
     attempt when the phase came from a row)}` when `phase !== ""`, else `null`.
   - `headline`: `Escalated at <phase>`, or `Escalated` when `phase === ""`.
2. **A synthetic node** (RR 142-143: `integrate`, `base-<story id>`, named as Run detail's
   tree names it). The last row, from the end, whose `card_id` is synthetic
   (`_isSynthetic`) and whose `status` is in `_FAILURE_STATUSES`: node = its `card_id`,
   `phase` = its `phase`. Else the first object story in `tree.stories` whose `card_id` is
   synthetic and whose `status` is `escalated` or in `_FAILURE_STATUSES`: node = its
   `card_id`, `phase` = `""`.
   - `cardId` `""` (a node is not a card), `storyId` the node id, `storyTitle`
     `_syntheticLabel(node)`, `detail` `""`, `attempt` `null`.
   - `headline`: `Escalated at <label>` (e.g. `Escalated at Integrate`, `Escalated at Base
     bf8154fc-…`).
3. **Nothing named.** `cardId`, `storyId`, `storyTitle`, `phase`, `detail` `""`, `attempt`
   `null`, `headline` `Escalated`. (The recorded `status-escalated-integrate.json` lands
   here: am records no synthetic story, row or failed phase for its Integrate failure.)

On `status-escalated.json` this gives `cardId` `10e26d57-374c-48d3-bc45-09389b42cfac`,
`storyId` `bf8154fc-e65c-46f5-b6e8-92b616a6e62b`, `storyTitle` `Story B: blocked by story A`,
`phase` `review`, `detail` the review phase's recorded `detail` verbatim (trimmed),
`attempt` `{card_id: "10e26d57-…", phase: "review", attempt: 1}`, `headline`
`Escalated at review`, `heartbeatAt` `""`, `parked` `[]`, `relaunch` `{level: "milestone",
cardId: "f18d342f-4887-4cd8-a86e-dd2755237c2c", prefix: "m3", base: "main"}`.

#### Dead (RR 145-146)

- `headline`: `The run's process died`.
- `heartbeatAt`: `_textOf(run.lease.heartbeat_at)` when `run.lease` is an object, else `""`.
- In flight: the first real subtask (tree order) with a phase whose `status === "started"`
  and whose `name` is a non-empty string: `cardId`, `storyId`, `storyTitle` from it,
  `phase` that phase's name, `attempt` `{card_id, phase, attempt: _newestAttempt(phase)}`
  (0 when it has none). With none in flight: those `""` and `attempt` `null`.
- `detail` `""`.

On `status-started.json` with the lease made not live: `cardId`
`2280a6ab-9c40-434b-9729-63fd1f373754`, `storyId` `7a7effb4-6ec5-4596-bcf1-be24546d4ac1`,
`storyTitle` `Dispatch backend`, `phase` `explore`, `attempt` `{…, phase: "explore",
attempt: 1}`, `heartbeatAt` `2026-10-08T14:38:28.740774+00:00`.

#### Parked (RR 144)

`headline` `Paused at a phase boundary`; `cardId`, `storyId`, `storyTitle`, `phase`,
`detail`, `heartbeatAt` `""`; `attempt` `null`; `parked` as above.

#### Cancelled (RR 147-148, 298)

Both `cancelled` and `canceled` statuses. `headline` exactly `Cancelled. A cancelled run
cannot be resumed, only relaunched; cards keep their status`; the other fields as for
Parked.

#### `relaunch` (RR 206-208, 247-248)

From the normalized run, `workflow` read trimmed and case-sensitive:

| `workflow` | `level` | `cardId` |
|---|---|---|
| `task` | `card` | `run.card_id` |
| `story` | `story` | `run.story_id` |
| anything else (`milestone`, `""`, unknown) | `milestone` | `run.milestone_id` |

`prefix` is `_textOf(run.branch_prefix)`, `base` `_textOf(run.base_branch)` (either may be
`""`). `relaunch` is `null` when the chosen `cardId`, trimmed, is not a real card id
(`_isCardId`: empty, `integrate`, `bases`, `base-*`, or not a string) — "the run does not
name its target". A fresh object per call.

## Error paths

- Not a run (`undefined`, `null`, numbers, strings, booleans, arrays, `{}`) → `null`.
- A stopped run with a broken tree (`tree` missing or not an object, `subtasks` not an
  array, `subtasks: [null, {phases: "x"}, {card_id: 5}]`, phases / attempts that are not
  arrays or hold non-objects, rows that are not objects, a `title` that is not a string, a
  `lease` that is not an object) → a report with the defaults above for whatever cannot be
  read; never throws.
- A run status with surrounding spaces or other case (`" stopped"`, `"Escalated"`) is
  `unknown` per `runState` → `null`.
- The input is never modified: `JSON.stringify(run)` is the same before and after.

## Tests

Tier: QML unit tests in `tests/core/domain/tst_runs.qml`, run by `qmltestrunner` through
`bash tests/run.sh` (fast loop: `bash tests/run.sh tst_runs`). Both changes are pure
functions of a `.pragma library` file with no I/O, so the domain unit tier is the right and
only tier (RR "Testing" bullet 1, lines 302-306); no consumer changes in this card, so no
store, backend or UI test is needed. Inputs come from the recorded fixtures through
`amRun(name)` and `Runs.normalizeRun`; every edit to a recorded input is marked
`// synthetic: …` as the file's existing tests do. New tests go in a new section
`// ---- RR 1.2: why it stopped` at the end of the file; the two `normalizeRun` key-list
assertions are updated in place.

normalizeRun (domain unit):

1. `checkDefaults` (`tst_runs.qml:33-49`) and `test_normalize_scalars_from_fixture`
   (`:230-240`): the key list above; `card_id` and `story_id` `""` by default and on the
   recorded `status-started.json`.
2. `card_id` / `story_id` from the row (synthetic: row `card_id: "c-1"`, `story_id: "s-1"`),
   from am status's run when the row has none (synthetic: `status.run.story_id: "s-2"`,
   `status.run.card_id: "c-2"`), the row winning when both have one, `null` → `""`.

stopReport (domain unit):

3. **Escalated, recorded** — `status-escalated.json`: every field as listed under
   Escalated, `Object.keys(report).sort()` equal to the eleven keys.
4. **Escalated, detail from the attempt** — synthetic: the review phase's `detail` set to
   `null` and its attempt given `detail: "from the attempt"` → `detail` `from the attempt`.
5. **Escalated, failed step (attempt 0)** — synthetic: on `status-escalated.json`'s
   escalated subtask, the review phase set `done` and a `verify` phase
   `{name: "verify", kind: "deterministic", status: "failed", detail: "VerifyError: …",
   attempts: []}` appended → `phase` `verify`, `attempt` `{card_id, phase: "verify",
   attempt: 0}`, `headline` `Escalated at verify`.
6. **Escalated, phase from a row** — synthetic: the escalated subtask's failed phase set to
   `done` (no failed phase left); its `gate_failed` review row remains → `phase` `review`,
   `attempt.attempt` 1, `detail` the review phase's `detail`.
7. **Synthetic node, story** — synthetic: `status-done-integrate.json` with run status
   `escalated` and its `integrate` story's status `escalated` → `cardId` `""`, `storyId`
   `integrate`, `storyTitle` `Integrate`, `headline` `Escalated at Integrate`, `attempt`
   `null`.
8. **Synthetic node, base row** — synthetic: an escalated run whose subtasks are all done
   and whose rows end with `{story_id: "bases", card_id: "base-s1", phase: "merge",
   status: "failed"}` → `storyId` `base-s1`, `storyTitle` `Base s1`, `phase` `merge`,
   `headline` `Escalated at Base s1`.
9. **Escalated, nothing named** — recorded `status-escalated-integrate.json` → `headline`
   `Escalated`, `cardId` / `storyId` / `phase` / `detail` `""`, `attempt` `null`,
   `relaunch` `{level: "milestone", cardId: "76043cd6-2077-47d4-afbb-c0ab60e62416",
   prefix: "m4", base: "main"}`.
10. **Dead** — synthetic: `status-started.json` with `lease.live` false → the fields under
    Dead; and with `lease` removed (`control.lease` deleted) → `heartbeatAt` `""`, the same
    subtask and phase.
11. **Dead, nothing in flight** — synthetic: dead `status-started.json` with the in-flight
    explore phase set `done` → `cardId` `""`, `phase` `""`, `attempt` `null`.
12. **Parked** — synthetic: `status-started.json` with run status `stopped` and subtask
    `2280a6ab-…` status `stopped` → `state` `parked`, `headline` `Paused at a phase
    boundary`, `parked` `["2280a6ab-9c40-434b-9729-63fd1f373754"]`, `attempt` `null`,
    `relaunch` level `milestone`, prefix `dsp`, base `main`.
13. **Cancelled, both spellings** — synthetic: the same with run status `cancelled`, then
    `canceled` → `state` `cancelled`, the exact cancelled headline, the same `parked`.
14. **Escalated lists parked too** — synthetic: `status-escalated.json` with subtask
    `460aaaa9-…` status `stopped` → `parked` `["460aaaa9-0520-40f7-aaa5-f162afab8bc0"]`.
15. **Task run** — synthetic: `status-escalated.json` with row `workflow: "task"` and row
    `card_id: "10e26d57-374c-48d3-bc45-09389b42cfac"` → `relaunch` `{level: "card",
    cardId: that id, prefix: "m3", base: "main"}`; with no `card_id` → `relaunch` `null`.
16. **Story run** — synthetic: `workflow: "story"`, row `story_id:
    "bf8154fc-e65c-46f5-b6e8-92b616a6e62b"` → `relaunch` level `story` with that id; with
    no `story_id` → `null`.
17. **Milestone run without a milestone** — synthetic: `milestone_id` `""` on both row and
    status → `relaunch` `null`; `milestone_id: "integrate"` → `null`.
18. **Null for running, done, unknown** — recorded `status-started.json` (running),
    `status-done.json` (done), and synthetic statuses `""`, `"bogus"`, `" stopped"`.
19. **Garbage** — `undefined`, `null`, `0`, `"escalated"`, `true`, `[]`, `{}` → `null`;
    `{status: "escalated"}`, `{status: "stopped", tree: "x"}`,
    `{status: "escalated", tree: {subtasks: [null, {phases: "x"}, {card_id: 5}], stories: [null]}, rows: [null, 3]}`,
    `{status: "started", lease: "x"}` → a report, no throw, with the defaults.
20. **Fresh and untouched** — two calls on one run give reports that are not the same
    objects (`attempt`, `parked`, `relaunch` distinct), mutating a report leaves the next
    call's report unchanged, and `JSON.stringify(run)` is unchanged by the call.

## Hand-off to the planner

Two tasks, each its own test cycle and commit, in this order:

- **Task 1: `normalizeRun` carries `card_id` and `story_id`** — tests 1-2, the return object
  and the header comment.
- **Task 2: `stopReport`** — tests 3-20, the new section with `stopReport` and its private
  helpers (`_`-prefixed, e.g. the escalated subject, the in-flight subtask, the story title,
  the relaunch target).

Verification for each task and at the end: `bash tests/run.sh` green (pytest, including
`tests/architecture`, then every `tst_*.qml`).

---

# 1.2 runs.js: stopReport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `normalizeRun` carries the run's `card_id` and `story_id`, and a new pure `stopReport(run)` says why a stopped run stopped (state, headline, the card / story / phase it names, the attempt the output pane opens, the parked cards and the relaunch target).

**Architecture:** Both changes live in `core/domain/runs.js` (`.pragma library`, pure, never throws). Task 1 adds two scalars to `normalizeRun`'s return object and its header comment. Task 2 adds a new section `// ---- Why it stopped (RR 1.2)` between `offersRelaunch` and `// ---- Run alerts (S2 1.2)`: four headline vars, ten `_`-prefixed helpers and the public `stopReport`. It reuses the file's existing private helpers (`_isObject`, `_arrayOr`, `_stringOr`, `_treeOf`, `_subtasksOf`, `_isSynthetic`, `_isCardId`, `_findByCardId`, `_textOf`, `_FAILURE_STATUSES`, `_attemptNumber`, `_newestAttempt`, `_findPhase`, `_syntheticLabel`) and `runState`. Tests go first, in a new section `// ---- RR 1.2: why it stopped` at the end of `tests/core/domain/tst_runs.qml`.

**Tech Stack:** QML/JS (`.pragma library`, ES5 style: `var`/`function`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-2-runs-js-stopreport-9a37bb47.md` (copied in full at the top of this file). It is narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md`.

## Global Constraints

- Change only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml`. Do not touch any file under `ui/`, `core/stores/` or `core/backend/`.
- The `runs.js` diff stays inside `normalizeRun`'s return object and header comment, and the new section between `offersRelaunch` and `// ---- Run alerts (S2 1.2)`. Do not edit `escalationReason`, `defaultAttempt`, `runTree`, `controls`, `controlError`, `offersRelaunch` or any other existing function.
- Style: `var`/`function` only, no `const`/`let`/arrow functions. Private names start with `_`. One contract-only comment above each function (no narrative).
- Plain ASCII strings only: no glyph (no `‼`, `…` or curly quote) in any headline (`tests/architecture/test_icon_glyphs.py`).
- No UI import. `tests/architecture` must pass.
- Reads only the normalised run, never brd status. No events.
- Never throws; never mutates its input; every object and array `stopReport` returns is fresh (no reference into the run).
- Ids are compared with `===` by linear scan, so `__proto__` and `constructor` behave like any other id.
- Headlines, verbatim: `Escalated`, `Escalated at <phase or label>`, `The run's process died`, `Paused at a phase boundary`, `Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status`.
- `normalizeRun` output keys, verbatim: `base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow`.
- `stopReport` keys, verbatim: `attempt,cardId,detail,headline,heartbeatAt,parked,phase,relaunch,state,storyId,storyTitle`.
- Process safety: never use `pkill`/`killall`/pattern kills. Wrap long runs in `timeout`.

## Review Focus

1. **Another card's failed row.** An escalated subtask with no failed phase and no failed row of its own must not borrow the phase of a later failed row that belongs to a different card: it is named with phase `""`, headline `Escalated`, `attempt` null. Pinned in Task 2, `test_stopReport_other_cards_row`.
2. **am's row is ahead of the tree.** When the phase comes from a row whose `attempt` is higher than the tree phase's newest attempt (am wrote the row, the tree lags), the output pane must open the row's attempt. Pinned in Task 2, `test_stopReport_row_attempt_newer`.
3. **Order of the escalated subject.** An escalated subtask later in the tree wins over an earlier subtask that only has a failed phase; with no escalated subtask, the first failed-phase subtask in tree order is named, with its own story title. Pinned in Task 2, `test_stopReport_escalated_order`.
4. **Synthetic node precedence.** A failed synthetic row wins over a failed synthetic story; a synthetic story that is `done` or a synthetic row that is `ok` is never named. Pinned in Task 2, `test_stopReport_synthetic_precedence`.
5. **Story title edge cases.** A padded title is trimmed; a subtask whose `story_id` is `constructor` or `__proto__` and matches no story gets `storyTitle` `""` (no prototype lookup). Pinned in Task 2, `test_stopReport_story_title_edges`.

Already checked: the assertions on `normalizeRun`'s key list are `tests/core/domain/tst_runs.qml:34` and `:232`; no store or UI test lists its keys. A third assertion breaks too: `test_normalize_unknown_keys_ignored` (`:570-574`) asserts the row's `story_id` and `card_id` are NOT output keys. Task 1, Step 1 updates it (verified by running the plan's code in a scratch copy: it is the only existing test that fails). On every recorded fixture both `card_id` and `story_id` are `null` (or absent) on the row and in `run`, so existing consumers see `""`.

## Test commands

- Fast loop: `timeout 600 bash tests/run.sh domain/tst_runs`. This runs pytest, then only `tests/core/domain/tst_runs.qml`. Read the `== tests/core/domain/tst_runs.qml` block: its `FAIL!` lines, any `TypeError` line and the `Totals:` line.
- Full gate: `timeout 1200 bash tests/run.sh`. It must exit 0 with `0 failed` on every `Totals:` line.

## Fixture facts the tests rely on

(From `tests/fixtures/am/`; `amRun(name)` returns `{row, status}` where `status` is the fixture's `data`.)

- `status-escalated.json`: run id `20261008T143755Z-f18d342f`; row is `_am_runs_row` (milestone `f18d342f-4887-4cd8-a86e-dd2755237c2c`, prefix `m3`, base `main`, `workflow: "milestone"`, `card_id: null`, `story_id: null`); no lease. `status.stories[0]` = `c16cfbe3-…` "Story A: the first level" (subtasks `f6ac3b15-77df-4921-a9c0-0b442db53bb5`, `618d1b92-…`, all phases done, attempts `n: 1`); `status.stories[1]` = `bf8154fc-e65c-46f5-b6e8-92b616a6e62b` "Story B: blocked by story A", status `escalated`, `subtasks[0]` = `10e26d57-374c-48d3-bc45-09389b42cfac` status `escalated` with 12 phases; `phases[11]` is `review`, status `failed`, its `detail` below, `attempts: [{n: 1, status: "gate_failed", …}]`; `phases[1]` is `explore`, done, one attempt `n: 1`. `status.stories[2].subtasks[0]` = `460aaaa9-0520-40f7-aaa5-f162afab8bc0`, `pending`. The last entry of `status.rows` is `{story: bf8154fc-…, subtask: 10e26d57-…, phase: "review", attempt: 1, state: "gate_failed"}`. Normalized `tree.subtasks` order: `f6ac3b15`, `618d1b92`, `10e26d57`, `460aaaa9` (so index 2 is the escalated subtask).
- The review detail, verbatim: `phase 'review' gate 'review_blockers_gate' failed: blocked=review, detail=review left 1 unresolved blocker(s): the review-fail marker names m3/task-b1-only-subtask-of-10e26d57`.
- `status-started.json`: row from `runs.json` (milestone `e795ad19-c81f-43ec-bdda-ef61ab5f860b`, prefix `dsp`, base `main`); `status.control.lease` `{live: true, heartbeat_at: "2026-10-08T14:38:28.740774+00:00", …}`. `status.stories[1]` = `7a7effb4-6ec5-4596-bcf1-be24546d4ac1` "Dispatch backend"; its `subtasks[1]` = `2280a6ab-9c40-434b-9729-63fd1f373754`, status `started`, `phases[1]` = `explore`, status `started`, one attempt `n: 1`. No other phase is started.
- `status-escalated-integrate.json`: row `_am_runs_row` (milestone `76043cd6-2077-47d4-afbb-c0ab60e62416`, prefix `m4`, base `main`); two real subtasks, all done; no synthetic story and no synthetic row.
- `status-done-integrate.json`: row `_am_runs_row` (milestone `f7f73454-b9c5-464a-b8d4-659dd5b353af`, prefix `m3`, base `main`); `status.stories[2]` is the synthetic `integrate` story, status `done`; its rows are dropped by `normalizeRun` (real-card subtasks under `integrate`).

---

### Task 1: `normalizeRun` carries `card_id` and `story_id`

**Files:**
- Modify: `core/domain/runs.js:9-14` (header comment: input lines), `core/domain/runs.js:24-26` (header comment: "Output scalars" sentence), `core/domain/runs.js:127-141` (return object)
- Test: `tests/core/domain/tst_runs.qml:33-49` (`checkDefaults`), `tests/core/domain/tst_runs.qml:230-249` (`test_normalize_scalars_from_fixture`), `tests/core/domain/tst_runs.qml:557-580` (`test_normalize_unknown_keys_ignored`), and a new section at the end of the file (before the final `}` of the `TestCase`)

**Interfaces:**
- Consumes: `normalizeRun`'s local helpers `firstText(a, b)` and `text(v)` (`runs.js:49-50`); the test helper `amRun(name)` (`tst_runs.qml:14-23`).
- Produces: `normalizeRun(raw)` output gains `card_id` (string) and `story_id` (string): the `am runs` row's value, else `am status` `run`'s value, `""` when neither has one; non-null non-string values become `String(v)`. Task 2's `_relaunchOf` reads `run.card_id`, `run.story_id`, `run.milestone_id`, `run.workflow`, `run.branch_prefix`, `run.base_branch`.

- [ ] **Step 1: Update the key-list assertions, the not-kept assertion and add the default checks**

In `tests/core/domain/tst_runs.qml`, inside `function checkDefaults(r, label)`, replace the line

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow", label)
```

with

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow", label)
```

and, in the same function, directly after the line `    compare(r.branch_prefix, "", label)`, add:

```qml
    compare(r.card_id, "", label)
    compare(r.story_id, "", label)
```

Inside `function test_normalize_scalars_from_fixture()`, replace the line

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,tree,workflow")
```

with

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow")
```

and, in the same function, directly after the line `    compare(r.branch_prefix, "dsp")`, add:

```qml
    compare(r.card_id, "", "a milestone run names no card")
    compare(r.story_id, "", "a milestone run names no story")
```

In `function test_normalize_unknown_keys_ignored()` (`tst_runs.qml:557-580`), replace the line

```qml
    var rowKeys = ["story_id", "card_id", "progress"]
```

with

```qml
    var rowKeys = ["progress"]
```

and, directly after the closing `}` of the `for (var i …)` loop that follows it (before `var statusKeys`), add:

```qml
    verify(hasOwn(fixture.row, "story_id") && hasOwn(fixture.row, "card_id"), "the capture's row carries story_id and card_id")
    verify(keys.indexOf("story_id") >= 0 && keys.indexOf("card_id") >= 0, "row story_id and card_id are kept (RR 1.2)")
```

- [ ] **Step 2: Write the failing test in a new section**

At the end of `tests/core/domain/tst_runs.qml`, directly after the closing `}` of `function test_display_order_garbage() { ... }` and before the final `}` that closes the `TestCase`, add:

```qml

  // ---- RR 1.2: why it stopped -------------------------------------------------------------

  function test_normalize_card_and_story_ids() {
    var recorded = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(recorded.card_id, "", "recorded escalated: card_id null")
    compare(recorded.story_id, "", "recorded escalated: story_id null")

    // synthetic: the row names a card and a story
    var fromRow = amRun("status-started.json")
    fromRow.row.card_id = "c-1"
    fromRow.row.story_id = "s-1"
    var r = Runs.normalizeRun(fromRow)
    compare(r.card_id, "c-1", "row card_id")
    compare(r.story_id, "s-1", "row story_id")

    // synthetic: only am status's run names them
    var fromStatus = amRun("status-started.json")
    fromStatus.status.run.card_id = "c-2"
    fromStatus.status.run.story_id = "s-2"
    r = Runs.normalizeRun(fromStatus)
    compare(r.card_id, "c-2", "status run card_id")
    compare(r.story_id, "s-2", "status run story_id")

    // synthetic: both name them; the row wins
    var both = amRun("status-started.json")
    both.row.card_id = "c-1"
    both.row.story_id = "s-1"
    both.status.run.card_id = "c-2"
    both.status.run.story_id = "s-2"
    r = Runs.normalizeRun(both)
    compare(r.card_id, "c-1", "row wins card_id")
    compare(r.story_id, "s-1", "row wins story_id")

    // synthetic: null on both sides, and numbers
    r = Runs.normalizeRun({ row: { card_id: null, story_id: null }, status: { run: { card_id: null, story_id: null } } })
    compare(r.card_id, "", "null card_id")
    compare(r.story_id, "", "null story_id")
    r = Runs.normalizeRun({ row: { card_id: 7 }, status: { run: { story_id: 8 } } })
    compare(r.card_id, "7", "number card_id is text")
    compare(r.story_id, "8", "number story_id is text")
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: FAIL. `FAIL!` lines for `test_normalize_scalars_from_fixture`, `test_normalize_unknown_keys_ignored` and every test that calls `checkDefaults` (the key list lacks `card_id` / `story_id`), and for `test_normalize_card_and_story_ids` (`Actual (): undefined` vs `Expected (): ""`, or similar).

- [ ] **Step 4: Update the header comment**

In `core/domain/runs.js`, replace the two input lines

```js
//     row:    one `am runs` entry without its `status`:
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, card_id, lease, progress, project: { id, repo_dir } }
//     status: `am status` data, may be absent:
//             { as_of_seq, store_id,
//               run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at },
```

with

```js
//     row:    one `am runs` entry without its `status`:
//             { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//               milestone_id, card_id, story_id, lease, progress, project: { id, repo_dir } }
//     status: `am status` data, may be absent:
//             { as_of_seq, store_id,
//               run: { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at,
//                      card_id, story_id },
```

and replace

```js
// Output scalars: id, repo_dir, started_at, base_branch, branch_prefix and
// workflow are the row's, else the am status run's; status and milestone_id are
// the am status run's, else the row's. `lease` keeps pid, host, heartbeat_at,
```

with

```js
// Output scalars: id, repo_dir, started_at, base_branch, branch_prefix and
// workflow are the row's, else the am status run's; status and milestone_id are
// the am status run's, else the row's; card_id and story_id are the row's, else
// the am status run's. `lease` keeps pid, host, heartbeat_at,
```

- [ ] **Step 5: Add the two scalars to the return object**

In `core/domain/runs.js`, inside `normalizeRun`'s `return { … }`, replace

```js
    workflow: firstText(row.workflow, run.workflow),
    lease: lease,
```

with

```js
    workflow: firstText(row.workflow, run.workflow),
    card_id: firstText(row.card_id, run.card_id),
    story_id: firstText(row.story_id, run.story_id),
    lease: lease,
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: PASS. The `tst_runs.qml` `Totals:` line shows `0 failed`, and no `TypeError` line.

- [ ] **Step 7: Run the full gate**

Run: `timeout 1200 bash tests/run.sh`
Expected: exit 0; pytest passes (including `tests/architecture`); every `Totals:` line shows `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): normalizeRun keeps the run's card_id and story_id"
```

---

### Task 2: `stopReport(run)`

**Files:**
- Modify: `core/domain/runs.js` — insert the new section between the closing `}` of `function offersRelaunch(error)` (`runs.js:952-955` before Task 1; about `:956-959` after it) and the line `// ---- Run alerts (S2 1.2) ---…`
- Test: `tests/core/domain/tst_runs.qml` — the `// ---- RR 1.2: why it stopped` section Task 1 created: add the test properties and helpers directly after the section header line, and the tests after `test_normalize_card_and_story_ids`

**Interfaces:**
- Consumes: from Task 1, `normalizeRun` output keys `card_id`, `story_id` (strings). Existing in `runs.js`: `runState(run)`, `_isObject(v)`, `_arrayOr(v)`, `_stringOr(v)`, `_treeOf(run)`, `_subtasksOf(run)`, `_isSynthetic(id)`, `_isCardId(id)`, `_findByCardId(list, cardId)`, `_textOf(v)`, `_FAILURE_STATUSES`, `_attemptNumber(a)`, `_newestAttempt(phase)`, `_findPhase(subtask, name)`, `_syntheticLabel(id)`. Test helper `amRun(name)`.
- Produces: `stopReport(run)` → `null`, or a fresh object `{state: string, headline: string, cardId: string, storyId: string, storyTitle: string, phase: string, detail: string, heartbeatAt: string, attempt: {card_id: string, phase: string, attempt: number} | null, parked: string[], relaunch: {level: "card"|"story"|"milestone", cardId: string, prefix: string, base: string} | null}`. Sibling cards (store, `StopReasonBlock`, Relaunch) call `Runs.stopReport(run)` by this name.

- [ ] **Step 1: Add the test properties and helpers**

In `tests/core/domain/tst_runs.qml`, directly after the line `  // ---- RR 1.2: why it stopped -------------------------------------------------------------` (added in Task 1), add:

```qml

  readonly property string stopEscCard: "10e26d57-374c-48d3-bc45-09389b42cfac"
  readonly property string stopEscStory: "bf8154fc-e65c-46f5-b6e8-92b616a6e62b"
  readonly property string stopEscStoryTitle: "Story B: blocked by story A"
  readonly property string stopEscMilestone: "f18d342f-4887-4cd8-a86e-dd2755237c2c"
  readonly property string stopEscPending: "460aaaa9-0520-40f7-aaa5-f162afab8bc0"
  readonly property string stopReviewDetail: "phase 'review' gate 'review_blockers_gate' failed: blocked=review, detail=review left 1 unresolved blocker(s): the review-fail marker names m3/task-b1-only-subtask-of-10e26d57"
  readonly property string stopStartedCard: "2280a6ab-9c40-434b-9729-63fd1f373754"
  readonly property string stopStartedStory: "7a7effb4-6ec5-4596-bcf1-be24546d4ac1"
  readonly property string stopStartedMilestone: "e795ad19-c81f-43ec-bdda-ef61ab5f860b"
  readonly property string stopHeartbeat: "2026-10-08T14:38:28.740774+00:00"
  readonly property string stopHeadlineDead: "The run's process died"
  readonly property string stopHeadlineParked: "Paused at a phase boundary"
  readonly property string stopHeadlineCancelled: "Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status"

  // The report stopReport gives when nothing is named, with `over`'s keys replacing the defaults.
  function stopWant(over) {
    var want = { state: "", headline: "", cardId: "", storyId: "", storyTitle: "", phase: "", detail: "",
                 heartbeatAt: "", attempt: null, parked: [], relaunch: null }
    var keys = Object.keys(over)
    for (var i = 0; i < keys.length; i++) want[keys[i]] = over[keys[i]]
    return want
  }

  // a and b, null or flat objects, have the same keys and the same values.
  function compareFlat(a, b, label) {
    if (b === null) { compare(a, null, label); return }
    verify(a !== null && typeof a === "object", label + ": an object")
    compare(Object.keys(a).sort().join(","), Object.keys(b).sort().join(","), label + ": keys")
    var keys = Object.keys(b)
    for (var i = 0; i < keys.length; i++) compare(a[keys[i]], b[keys[i]], label + ": " + keys[i])
  }

  // A stopReport result equals `want` (a stopWant): exactly the eleven keys, every value.
  function checkReport(rep, want, label) {
    verify(rep !== null && typeof rep === "object", label + ": a report")
    compare(Object.keys(rep).sort().join(","),
            "attempt,cardId,detail,headline,heartbeatAt,parked,phase,relaunch,state,storyId,storyTitle", label + ": keys")
    var keys = ["state", "headline", "cardId", "storyId", "storyTitle", "phase", "detail", "heartbeatAt"]
    for (var i = 0; i < keys.length; i++) compare(rep[keys[i]], want[keys[i]], label + ": " + keys[i])
    compareFlat(rep.attempt, want.attempt, label + ": attempt")
    compare(Array.isArray(rep.parked), true, label + ": parked is an array")
    compare(JSON.stringify(rep.parked), JSON.stringify(want.parked), label + ": parked")
    compareFlat(rep.relaunch, want.relaunch, label + ": relaunch")
  }

  // The recorded escalated run's relaunch target.
  function stopEscRelaunch() { return { level: "milestone", cardId: stopEscMilestone, prefix: "m3", base: "main" } }

  // The recorded started run's relaunch target.
  function stopStartedRelaunch() { return { level: "milestone", cardId: stopStartedMilestone, prefix: "dsp", base: "main" } }

  // The report on the recorded escalated run, with `over`'s keys replacing it.
  function stopEscWant(over) {
    var want = stopWant({ state: "escalated", headline: "Escalated at review", cardId: stopEscCard, storyId: stopEscStory,
                          storyTitle: stopEscStoryTitle, phase: "review", detail: stopReviewDetail,
                          attempt: { card_id: stopEscCard, phase: "review", attempt: 1 }, relaunch: stopEscRelaunch() })
    var keys = Object.keys(over)
    for (var i = 0; i < keys.length; i++) want[keys[i]] = over[keys[i]]
    return want
  }

  // amRun("status-started.json") with its lease no longer live: a dead run.
  function deadStartedRaw() {
    var raw = amRun("status-started.json")
    raw.status.control.lease.live = false
    return raw
  }

  // The report on deadStartedRaw(), with `over`'s keys replacing it.
  function stopDeadWant(over) {
    var want = stopWant({ state: "dead", headline: stopHeadlineDead, cardId: stopStartedCard, storyId: stopStartedStory,
                          storyTitle: "Dispatch backend", phase: "explore", heartbeatAt: stopHeartbeat,
                          attempt: { card_id: stopStartedCard, phase: "explore", attempt: 1 }, relaunch: stopStartedRelaunch() })
    var keys = Object.keys(over)
    for (var i = 0; i < keys.length; i++) want[keys[i]] = over[keys[i]]
    return want
  }
```

- [ ] **Step 2: Write the failing tests (spec tests 3-20)**

Directly after the closing `}` of `function test_normalize_card_and_story_ids() { ... }` (still before the `TestCase`'s final `}`), add:

```qml

  function test_stopReport_escalated_recorded() {
    checkReport(Runs.stopReport(Runs.normalizeRun(amRun("status-escalated.json"))), stopEscWant({}), "recorded escalated")
  }

  function test_stopReport_escalated_detail_from_attempt() {
    // synthetic: the review phase's detail removed, its attempt given one
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].detail = null
    raw.status.stories[1].subtasks[0].phases[11].attempts[0].detail = "  from the attempt \n"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({ detail: "from the attempt" }), "detail from the attempt")
  }

  function test_stopReport_escalated_failed_step() {
    // synthetic: review done, a failed deterministic verify step appended
    var raw = amRun("status-escalated.json")
    var subtask = raw.status.stories[1].subtasks[0]
    subtask.phases[11].status = "done"
    subtask.phases.push({ name: "verify", kind: "deterministic", status: "failed",
                          detail: "VerifyError: 2 tests failed", attempts: [] })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ headline: "Escalated at verify", phase: "verify", detail: "VerifyError: 2 tests failed",
                              attempt: { card_id: stopEscCard, phase: "verify", attempt: 0 } }), "failed step, attempt 0")
  }

  function test_stopReport_escalated_phase_from_row() {
    // synthetic: the failed review phase set done; its gate_failed row remains
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "phase from the row")
  }

  function test_stopReport_synthetic_story() {
    // synthetic: the done-integrate capture made escalated, its integrate story escalated
    var raw = amRun("status-done-integrate.json")
    raw.status.run.status = "escalated"
    raw.status.stories[2].status = "escalated"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated at Integrate", storyId: "integrate", storyTitle: "Integrate",
                           relaunch: { level: "milestone", cardId: "f7f73454-b9c5-464a-b8d4-659dd5b353af", prefix: "m3", base: "main" } }),
                "integrate story")
  }

  function test_stopReport_synthetic_base_row() {
    // synthetic: an escalated run, every subtask done, whose rows end with a failed base merge
    var raw = amRun("status-escalated-integrate.json")
    raw.status.rows.push({ story: "bases", subtask: "base-s1", phase: "merge", attempt: null, state: "failed" })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated at Base s1", storyId: "base-s1", storyTitle: "Base s1",
                           phase: "merge",
                           relaunch: { level: "milestone", cardId: "76043cd6-2077-47d4-afbb-c0ab60e62416", prefix: "m4", base: "main" } }),
                "base row")
  }

  function test_stopReport_escalated_nothing_named() {
    checkReport(Runs.stopReport(Runs.normalizeRun(amRun("status-escalated-integrate.json"))),
                stopWant({ state: "escalated", headline: "Escalated",
                           relaunch: { level: "milestone", cardId: "76043cd6-2077-47d4-afbb-c0ab60e62416", prefix: "m4", base: "main" } }),
                "recorded escalated integrate")
  }

  function test_stopReport_dead() {
    var dead = Runs.normalizeRun(deadStartedRaw())
    compare(Runs.runState(dead), "dead", "fixture")
    checkReport(Runs.stopReport(dead), stopDeadWant({}), "dead, lease not live")

    // synthetic: no lease at all
    var raw = amRun("status-started.json")
    delete raw.status.control.lease
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopDeadWant({ heartbeatAt: "" }), "dead, no lease")
  }

  function test_stopReport_dead_nothing_in_flight() {
    // synthetic: the dead capture's in-flight explore phase set done
    var raw = deadStartedRaw()
    raw.status.stories[1].subtasks[1].phases[1].status = "done"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopDeadWant({ cardId: "", storyId: "", storyTitle: "", phase: "", attempt: null }), "dead, nothing in flight")
  }

  function test_stopReport_parked() {
    // synthetic: the started capture stopped, its in-flight subtask stopped
    var raw = amRun("status-started.json")
    raw.status.run.status = "stopped"
    raw.status.stories[1].subtasks[1].status = "stopped"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "parked", headline: stopHeadlineParked, parked: [stopStartedCard], relaunch: stopStartedRelaunch() }),
                "parked")
  }

  function test_stopReport_cancelled_both_spellings() {
    var spellings = ["cancelled", "canceled"]
    for (var i = 0; i < spellings.length; i++) {
      // synthetic: the started capture cancelled, its in-flight subtask stopped
      var raw = amRun("status-started.json")
      raw.status.run.status = spellings[i]
      raw.status.stories[1].subtasks[1].status = "stopped"
      checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                  stopWant({ state: "cancelled", headline: stopHeadlineCancelled, parked: [stopStartedCard], relaunch: stopStartedRelaunch() }),
                  spellings[i])
    }
  }

  function test_stopReport_escalated_lists_parked() {
    // synthetic: the escalated capture's pending subtask stopped
    var raw = amRun("status-escalated.json")
    raw.status.stories[2].subtasks[0].status = "stopped"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({ parked: [stopEscPending] }), "escalated lists parked")
  }

  function test_stopReport_task_run() {
    // synthetic: the escalated capture as a task run of its escalated card
    var raw = amRun("status-escalated.json")
    raw.row.workflow = "task"
    raw.row.card_id = stopEscCard
    var task = { level: "card", cardId: stopEscCard, prefix: "m3", base: "main" }
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({ relaunch: task }), "task run")

    // synthetic: padded workflow and card id
    var padded = amRun("status-escalated.json")
    padded.row.workflow = "  task "
    padded.row.card_id = "  " + stopEscCard + "\n"
    compareFlat(Runs.stopReport(Runs.normalizeRun(padded)).relaunch, task, "padded task run")

    // synthetic: a task run that names no card
    var noCard = amRun("status-escalated.json")
    noCard.row.workflow = "task"
    compare(Runs.stopReport(Runs.normalizeRun(noCard)).relaunch, null, "task run without a card")

    // synthetic: workflow is case-sensitive: "Task" is a milestone run
    var upper = amRun("status-escalated.json")
    upper.row.workflow = "Task"
    upper.row.card_id = stopEscCard
    compareFlat(Runs.stopReport(Runs.normalizeRun(upper)).relaunch, stopEscRelaunch(), "Task is not task")
  }

  function test_stopReport_story_run() {
    // synthetic: the escalated capture as a story run of its escalated story
    var raw = amRun("status-escalated.json")
    raw.row.workflow = "story"
    raw.row.story_id = stopEscStory
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ relaunch: { level: "story", cardId: stopEscStory, prefix: "m3", base: "main" } }), "story run")

    // synthetic: a story run that names no story
    var noStory = amRun("status-escalated.json")
    noStory.row.workflow = "story"
    compare(Runs.stopReport(Runs.normalizeRun(noStory)).relaunch, null, "story run without a story")

    // synthetic: a story run whose story is bookkeeping
    var bases = amRun("status-escalated.json")
    bases.row.workflow = "story"
    bases.row.story_id = "bases"
    compare(Runs.stopReport(Runs.normalizeRun(bases)).relaunch, null, "story run of bases")
  }

  function test_stopReport_milestone_run_without_milestone() {
    var ids = ["", "integrate", "base-x"]
    for (var i = 0; i < ids.length; i++) {
      // synthetic: the milestone id blanked or made bookkeeping on both sides
      var raw = amRun("status-escalated.json")
      raw.row.milestone_id = ids[i]
      raw.status.run.milestone_id = ids[i]
      compare(Runs.stopReport(Runs.normalizeRun(raw)).relaunch, null, "milestone_id \"" + ids[i] + "\"")
    }
  }

  function test_stopReport_null_unless_stopped() {
    compare(Runs.stopReport(Runs.normalizeRun(amRun("status-started.json"))), null, "running")
    compare(Runs.stopReport(Runs.normalizeRun(amRun("status-done.json"))), null, "done")
    var statuses = ["", "bogus", " stopped", "Escalated"]
    for (var i = 0; i < statuses.length; i++) {
      // synthetic: run statuses that are unknown to runState
      var raw = amRun("status-escalated.json")
      raw.status.run.status = statuses[i]
      compare(Runs.stopReport(Runs.normalizeRun(raw)), null, "status \"" + statuses[i] + "\"")
    }
  }

  function test_stopReport_garbage() {
    var notRuns = [undefined, null, 0, "escalated", true, [], {}]
    for (var i = 0; i < notRuns.length; i++) compare(Runs.stopReport(notRuns[i]), null, "not a run " + i)

    // synthetic: stopped runs with nothing readable
    checkReport(Runs.stopReport({ status: "escalated" }), stopWant({ state: "escalated", headline: "Escalated" }), "bare escalated")
    checkReport(Runs.stopReport({ status: "stopped", tree: "x" }), stopWant({ state: "parked", headline: stopHeadlineParked }), "tree not an object")
    checkReport(Runs.stopReport({ status: "escalated",
                                  tree: { subtasks: [null, { phases: "x" }, { card_id: 5 }], stories: [null] }, rows: [null, 3] }),
                stopWant({ state: "escalated", headline: "Escalated" }), "broken tree and rows")
    checkReport(Runs.stopReport({ status: "started", lease: "x" }), stopWant({ state: "dead", headline: stopHeadlineDead }), "lease not an object")
    checkReport(Runs.stopReport({ status: "escalated", tree: { subtasks: "x" } }), stopWant({ state: "escalated", headline: "Escalated" }), "subtasks not an array")

    // synthetic: a real escalated subtask with broken phases, attempts, rows, title and ids
    var broken = { status: "escalated", workflow: 5, milestone_id: 7,
                   tree: { stories: [null, { card_id: "s1", title: 5 }],
                           subtasks: [{ card_id: "t1", story_id: "s1", status: "escalated",
                                        phases: [null, 3, { name: "review", status: "failed", attempts: "x" }] }] },
                   rows: [null, 3, { card_id: "t1", phase: "review", attempt: "x", status: "failed" }] }
    checkReport(Runs.stopReport(broken),
                stopWant({ state: "escalated", headline: "Escalated at review", cardId: "t1", storyId: "s1", phase: "review",
                           attempt: { card_id: "t1", phase: "review", attempt: 0 } }), "broken escalated subtask")

    // synthetic: a dead run with a numeric heartbeat and odd attempts
    var deadOdd = { status: "started", lease: { live: false, heartbeat_at: 42 },
                    tree: { subtasks: [{ card_id: "t1", phases: [{ name: "plan", status: "started", attempts: [null, "x", { n: 2 }] }] }] } }
    checkReport(Runs.stopReport(deadOdd),
                stopWant({ state: "dead", headline: stopHeadlineDead, cardId: "t1", phase: "plan", heartbeatAt: "42",
                           attempt: { card_id: "t1", phase: "plan", attempt: 2 } }), "dead, odd attempts")
  }

  function test_stopReport_fresh_and_untouched() {
    var run = Runs.normalizeRun(amRun("status-escalated.json"))
    // synthetic: a stopped subtask so parked is not empty
    run.tree.subtasks[3].status = "stopped"
    var before = JSON.stringify(run)
    var a = Runs.stopReport(run)
    var b = Runs.stopReport(run)
    compare(JSON.stringify(run), before, "the run is unchanged")
    verify(a !== b, "a new report per call")
    verify(a.attempt !== b.attempt, "a new attempt per call")
    verify(a.parked !== b.parked, "a new parked list per call")
    verify(a.relaunch !== b.relaunch, "a new relaunch per call")
    a.headline = "x"
    a.attempt.phase = "x"
    a.parked.push("x")
    a.relaunch.cardId = "x"
    compare(JSON.stringify(run), before, "mutating a report leaves the run unchanged")
    checkReport(Runs.stopReport(run), stopEscWant({ parked: [stopEscPending] }), "after mutating an earlier report")
  }
```

- [ ] **Step 3: Write the Review Focus tests**

Directly after the closing `}` of `function test_stopReport_fresh_and_untouched() { ... }`, add:

```qml

  function test_stopReport_other_cards_row() {
    // synthetic: review set done, and the last (gate_failed review) row moved to another card
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    raw.status.rows[raw.status.rows.length - 1].subtask = stopEscPending
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ headline: "Escalated", phase: "", detail: "", attempt: null }), "another card's failed row")
  }

  function test_stopReport_row_attempt_newer() {
    // synthetic: review set done, its gate_failed row a second attempt the tree has not recorded
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    raw.status.rows[raw.status.rows.length - 1].attempt = 2
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ attempt: { card_id: stopEscCard, phase: "review", attempt: 2 } }), "row attempt wins")
  }

  function test_stopReport_escalated_order() {
    // synthetic: an earlier subtask's explore phase failed; the later escalated subtask still wins
    var raw = amRun("status-escalated.json")
    raw.status.stories[0].subtasks[0].phases[1].status = "failed"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "escalated status wins")

    // synthetic: with no escalated subtask, the first subtask with a failed phase is named
    raw.status.stories[1].subtasks[0].status = "started"
    var cardA = "f6ac3b15-77df-4921-a9c0-0b442db53bb5"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ headline: "Escalated at explore", cardId: cardA, storyId: "c16cfbe3-ca4f-4f27-8bdb-f595620296c6",
                              storyTitle: "Story A: the first level", phase: "explore", detail: "",
                              attempt: { card_id: cardA, phase: "explore", attempt: 1 } }), "first failed phase in tree order")
  }

  function test_stopReport_synthetic_precedence() {
    var relaunch = { level: "milestone", cardId: "f7f73454-b9c5-464a-b8d4-659dd5b353af", prefix: "m3", base: "main" }
    // synthetic: escalated, but the integrate story is done and a synthetic row is ok
    var raw = amRun("status-done-integrate.json")
    raw.status.run.status = "escalated"
    raw.status.rows.push({ story: "bases", subtask: "base-s1", phase: "merge", attempt: null, state: "ok" })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated", relaunch: relaunch }), "done story and ok row are not named")

    // synthetic: a failed synthetic row wins over an escalated synthetic story
    raw.status.stories[2].status = "escalated"
    raw.status.rows.push({ story: "bases", subtask: "base-s1", phase: "merge", attempt: null, state: "failed" })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated at Base s1", storyId: "base-s1", storyTitle: "Base s1",
                           phase: "merge", relaunch: relaunch }), "row wins over story")
  }

  function test_stopReport_story_title_edges() {
    // synthetic: a padded story title
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].title = "  " + stopEscStoryTitle + " \n"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "padded title")

    var ids = ["constructor", "__proto__", "toString"]
    for (var i = 0; i < ids.length; i++) {
      // synthetic: the escalated subtask's story id set to a name no story has
      var run = Runs.normalizeRun(amRun("status-escalated.json"))
      run.tree.subtasks[2].story_id = ids[i]
      checkReport(Runs.stopReport(run), stopEscWant({ storyId: ids[i], storyTitle: "" }), "story id " + ids[i])
    }
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: FAIL. Every `test_stopReport_*` test fails with `TypeError: Property 'stopReport' of object [object Object] is not a function` (run.sh echoes the `TypeError` line). `test_normalize_card_and_story_ids` and the older tests still pass.

- [ ] **Step 5: Write the implementation**

In `core/domain/runs.js`, find the end of `offersRelaunch`:

```js
function offersRelaunch(error) {
  var type = _controlErrorType(error)
  return type === "NotResumableError" || type === "CheckpointMismatchError"
}
```

Directly after that closing `}` (and before the blank lines and `// ---- Run alerts (S2 1.2) ---…`), insert:

```js

// ---- Why it stopped (RR 1.2) -------------------------------------------------------------
//
// What Run detail says about a stopped run: its state, one headline, the card,
// story and phase it names, the attempt the output pane opens, the parked cards
// and the relaunch target. Reads only the normalised run, never brd status.
// Pure and never throwing, like the rest of this file.

var _HEADLINE_ESCALATED = "Escalated"
var _HEADLINE_DEAD = "The run's process died"
var _HEADLINE_PARKED = "Paused at a phase boundary"
var _HEADLINE_CANCELLED = "Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status"

// The run's real subtasks: the objects in tree.subtasks with a real card id, in tree order.
function _realSubtasksOf(run) {
  var subtasks = _subtasksOf(run)
  var out = []
  for (var i = 0; i < subtasks.length; i++) {
    if (_isObject(subtasks[i]) && _isCardId(subtasks[i].card_id)) out.push(subtasks[i])
  }
  return out
}

// The trimmed title of the tree story whose card_id is storyId; "" when storyId
// is "", no story has it or its title is not a string.
function _storyTitleOf(run, storyId) {
  if (storyId === "") return ""
  var story = _findByCardId(_treeOf(run).stories, storyId)
  return story !== null && typeof story.title === "string" ? story.title.trim() : ""
}

// A fresh subject that names nothing.
function _noSubject() {
  return { cardId: "", storyId: "", storyTitle: "", phase: "", detail: "", attempt: null }
}

// A fresh subject for a real subtask at `phase` ("" for none): attempt is
// {card_id, phase, attempt} when phase is not "", else null.
function _subtaskSubject(run, subtask, phase, detail, attempt) {
  var storyId = _stringOr(subtask.story_id)
  return {
    cardId: subtask.card_id,
    storyId: storyId,
    storyTitle: _storyTitleOf(run, storyId),
    phase: phase,
    detail: detail,
    attempt: phase !== "" ? { card_id: subtask.card_id, phase: phase, attempt: attempt } : null
  }
}

// Does the subtask have a phase object whose status is `failed`?
function _hasFailedPhase(subtask) {
  var phases = _arrayOr(subtask.phases)
  for (var i = 0; i < phases.length; i++) {
    if (_isObject(phases[i]) && phases[i].status === "failed") return true
  }
  return false
}

// The subtask's first phase whose status is `failed` and whose name is a
// non-empty string, or null.
function _failedPhaseOf(subtask) {
  var phases = _arrayOr(subtask.phases)
  for (var i = 0; i < phases.length; i++) {
    var p = phases[i]
    if (_isObject(p) && p.status === "failed" && typeof p.name === "string" && p.name !== "") return p
  }
  return null
}

// The first real subtask whose status is `escalated`, else the first with a
// failed phase, else null.
function _escalatedSubtaskOf(subtasks) {
  for (var i = 0; i < subtasks.length; i++) {
    if (subtasks[i].status === "escalated") return subtasks[i]
  }
  for (var j = 0; j < subtasks.length; j++) {
    if (_hasFailedPhase(subtasks[j])) return subtasks[j]
  }
  return null
}

// The last row of cardId whose status is in _FAILURE_STATUSES and whose phase
// is a non-empty string, or null.
function _lastFailedRowOf(run, cardId) {
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var i = rows.length - 1; i >= 0; i--) {
    var row = rows[i]
    if (_isObject(row) && row.card_id === cardId && _FAILURE_STATUSES.indexOf(row.status) >= 0 &&
        _stringOr(row.phase) !== "") return row
  }
  return null
}

// A phase's trimmed detail, else the first non-empty trimmed detail of its
// attempts from the last back; "" when there is none or phase is not an object.
function _phaseDetailOf(phase) {
  if (!_isObject(phase)) return ""
  var detail = _textOf(phase.detail)
  var attempts = _arrayOr(phase.attempts)
  for (var k = attempts.length - 1; detail === "" && k >= 0; k--) {
    if (_isObject(attempts[k])) detail = _textOf(attempts[k].detail)
  }
  return detail
}

// The synthetic node an escalated run stopped at: {id, phase} of the last row
// whose card_id is synthetic and whose status is in _FAILURE_STATUSES, else
// {id, phase: ""} of the first tree story whose card_id is synthetic and whose
// status is in _FAILURE_STATUSES; null when neither.
function _escalatedNodeOf(run) {
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var i = rows.length - 1; i >= 0; i--) {
    var row = rows[i]
    if (_isObject(row) && _isSynthetic(row.card_id) && _FAILURE_STATUSES.indexOf(row.status) >= 0) {
      return { id: row.card_id, phase: _stringOr(row.phase) }
    }
  }
  var stories = _arrayOr(_treeOf(run).stories)
  for (var j = 0; j < stories.length; j++) {
    var s = stories[j]
    if (_isObject(s) && _isSynthetic(s.card_id) && _FAILURE_STATUSES.indexOf(s.status) >= 0) return { id: s.card_id, phase: "" }
  }
  return null
}

// What an escalated run names: its escalated subtask at the failed phase (from
// the tree, else from the subtask's last failed row), else a synthetic node by
// its runTree label, else nothing.
function _escalatedSubject(run, subtasks) {
  var subtask = _escalatedSubtaskOf(subtasks)
  if (subtask !== null) {
    var failed = _failedPhaseOf(subtask)
    var row = failed === null ? _lastFailedRowOf(run, subtask.card_id) : null
    var phase = failed !== null ? failed.name : row !== null ? row.phase : ""
    var inTree = failed !== null ? failed : _findPhase(subtask, phase)
    var attempt = Math.max(_newestAttempt(inTree), row !== null ? _attemptNumber(row) : 0)
    return _subtaskSubject(run, subtask, phase, _phaseDetailOf(inTree), attempt)
  }
  var node = _escalatedNodeOf(run)
  if (node === null) return _noSubject()
  return { cardId: "", storyId: node.id, storyTitle: _syntheticLabel(node.id), phase: node.phase, detail: "", attempt: null }
}

// What a dead run names: the first real subtask with a `started` phase whose
// name is a non-empty string, at that phase's newest attempt (0 when it has
// none); else nothing.
function _inFlightSubject(run, subtasks) {
  for (var i = 0; i < subtasks.length; i++) {
    var phases = _arrayOr(subtasks[i].phases)
    for (var j = 0; j < phases.length; j++) {
      var p = phases[j]
      if (_isObject(p) && p.status === "started" && typeof p.name === "string" && p.name !== "") {
        return _subtaskSubject(run, subtasks[i], p.name, "", _newestAttempt(p))
      }
    }
  }
  return _noSubject()
}

// The card_id of every real subtask whose status is `stopped`, in tree order.
function _parkedCardsOf(subtasks) {
  var out = []
  for (var i = 0; i < subtasks.length; i++) {
    if (subtasks[i].status === "stopped") out.push(subtasks[i].card_id)
  }
  return out
}

// What Relaunch starts again, a fresh {level, cardId, prefix, base}: workflow
// (trimmed, case-sensitive) `task` is the run's card_id, `story` its story_id,
// anything else its milestone_id. null when that id is not a string or,
// trimmed, not a real card id.
function _relaunchOf(run) {
  var workflow = _textOf(run.workflow)
  var level = workflow === "task" ? "card" : workflow === "story" ? "story" : "milestone"
  var id = level === "card" ? run.card_id : level === "story" ? run.story_id : run.milestone_id
  if (typeof id !== "string" || !_isCardId(id.trim())) return null
  return { level: level, cardId: id.trim(), prefix: _textOf(run.branch_prefix), base: _textOf(run.base_branch) }
}

// Why a run stopped: null unless runState(run) is escalated, parked, dead or
// cancelled; else a fresh {state, headline, cardId, storyId, storyTitle, phase,
// detail, heartbeatAt, attempt, parked, relaunch}. Escalated names its
// escalated subtask, else a synthetic node; dead names its in-flight phase and
// the lease's heartbeat_at; parked and cancelled name no card. parked and
// relaunch are given for every state. Never mutates the run.
function stopReport(run) {
  var state = runState(run)
  if (state !== "escalated" && state !== "parked" && state !== "dead" && state !== "cancelled") return null
  var subtasks = _realSubtasksOf(run)
  var subject = state === "escalated" ? _escalatedSubject(run, subtasks)
              : state === "dead" ? _inFlightSubject(run, subtasks) : _noSubject()
  var headline
  if (state === "escalated") {
    var at = subject.cardId !== "" ? subject.phase : subject.storyTitle
    headline = at !== "" ? _HEADLINE_ESCALATED + " at " + at : _HEADLINE_ESCALATED
  } else {
    headline = state === "dead" ? _HEADLINE_DEAD : state === "parked" ? _HEADLINE_PARKED : _HEADLINE_CANCELLED
  }
  return {
    state: state,
    headline: headline,
    cardId: subject.cardId,
    storyId: subject.storyId,
    storyTitle: subject.storyTitle,
    phase: subject.phase,
    detail: subject.detail,
    heartbeatAt: state === "dead" && _isObject(run.lease) ? _textOf(run.lease.heartbeat_at) : "",
    attempt: subject.attempt,
    parked: _parkedCardsOf(subtasks),
    relaunch: _relaunchOf(run)
  }
}
```

Notes for the implementer (do not paste these into the file):
- `runState` returns `unknown` for anything that is not an object, so after the first `if` `run` is an object and `run.workflow`, `run.lease` and friends are safe to read.
- A synthetic node id is always a string (`_isSynthetic` is true only for strings), so `_syntheticLabel(node.id)` is safe.
- In the escalated branch a real subtask with phase `""` gives `at === ""` and so the bare `Escalated`, even though it names a card.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: PASS. The `tst_runs.qml` `Totals:` line shows `0 failed`, and no `TypeError` line.

- [ ] **Step 7: Run the full gate**

Run: `timeout 1200 bash tests/run.sh`
Expected: exit 0; pytest passes (including `tests/architecture/test_icon_glyphs.py` and `test_layers.py`); every `Totals:` line shows `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): stopReport says why a stopped run stopped"
```

---

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| Scope 1, normalizeRun `card_id` / `story_id`, key list, header comment | Task 1, Steps 1-5 |
| Scope 2, `stopReport` in `// ---- Why it stopped (RR 1.2)` after `offersRelaunch`, before Run alerts | Task 2, Step 5 |
| Tests 1-2 | Task 1, Steps 1-2 |
| Test 3 escalated recorded | `test_stopReport_escalated_recorded` |
| Test 4 detail from the attempt | `test_stopReport_escalated_detail_from_attempt` |
| Test 5 failed step, attempt 0 | `test_stopReport_escalated_failed_step` |
| Test 6 phase from a row | `test_stopReport_escalated_phase_from_row` |
| Test 7 synthetic story | `test_stopReport_synthetic_story` |
| Test 8 synthetic base row | `test_stopReport_synthetic_base_row` |
| Test 9 nothing named | `test_stopReport_escalated_nothing_named` |
| Test 10 dead (live false, no lease) | `test_stopReport_dead` |
| Test 11 dead, nothing in flight | `test_stopReport_dead_nothing_in_flight` |
| Test 12 parked | `test_stopReport_parked` |
| Test 13 cancelled, both spellings | `test_stopReport_cancelled_both_spellings` |
| Test 14 escalated lists parked | `test_stopReport_escalated_lists_parked` |
| Test 15 task run | `test_stopReport_task_run` |
| Test 16 story run | `test_stopReport_story_run` |
| Test 17 milestone run without a milestone | `test_stopReport_milestone_run_without_milestone` |
| Test 18 null for running, done, unknown | `test_stopReport_null_unless_stopped` |
| Test 19 garbage | `test_stopReport_garbage` |
| Test 20 fresh and untouched | `test_stopReport_fresh_and_untouched` |
| Error paths (broken tree, non-string title, lease not an object, padded status) | `test_stopReport_garbage`, `test_stopReport_null_unless_stopped` |
| Ids by `===` (`__proto__`, `constructor`) | `test_stopReport_story_title_edges` |
| Verification `bash tests/run.sh` per task and at the end | Task 1 Step 7, Task 2 Step 7 |
<!-- task-pipeline: validated -->
