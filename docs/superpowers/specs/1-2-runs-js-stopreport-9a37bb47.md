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
