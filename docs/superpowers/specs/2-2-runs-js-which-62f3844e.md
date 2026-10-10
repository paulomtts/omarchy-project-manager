# 2.2 `runs.js`: which selection is live, steps included — spec

Card `62f3844e-5ea5-43a5-baa3-b3f585b27f65`, subtask of story `674c29f7-7a71-4dd8-9fc9-683eb7c53d90`
(Live run output). Blocked by 2.1 (`logStream.js`, done). Parent design:
`docs/superpowers/specs/2026-10-05-live-output-design.md` (below: **LO**).

## Purpose

Three pure changes in `core/domain/runs.js`, the domain half of "which attempt is live"
(LO lines 98-110):

1. `runTree` lists a **step entry** for each deterministic phase that has started or finished,
   so a running `verify` has a row to select.
2. `defaultAttempt` opens the first started phase, **step or agent**, so a run whose subtask is
   in `verify` opens `verify`.
3. A new `isLiveSelection(run, sel)` says whether the selection is in flight in a running run
   (the later `RunOutputStore` follows exactly those selections, LO lines 171-173).

## Starting point

- `normalizeRun` (`runs.js:45-148`) copies each subtask's phases verbatim through `_copyOf`
  (`runs.js:179`), so every normalized phase already carries am's `kind` (`"agent"` or
  `"deterministic"`). No normalization change is needed; the card's "carry `kind` through the
  normalized phase if it is not already there" is satisfied today and is pinned by a test.
- `_subtaskNode` (`runs.js:739-765`) builds a node's `attempts` from each phase's attempt objects
  only (`{phase, attempt, status}`, phase order). Deterministic phases have `attempts: []` in
  every recorded capture, so they contribute nothing.
- `defaultAttempt` (`runs.js:824-847`) returns the newest numbered attempt of the first started
  phase that has one, else falls back to the flat rows. A started step (no numbered attempt) is
  skipped.
- `attemptStatus` (`runs.js:850-858`) and `runState` (`runs.js:150-161`) exist; `isLiveSelection`
  does not.
- Recorded fixtures (`tests/fixtures/am/status-*.json`): every deterministic phase is `done`
  with `attempts: []`. `status-started.json` (state `running`) has one started phase, the agent
  phase `explore` (attempt 1 `started`) of subtask `2280a6ab-9c40-434b-9729-63fd1f373754`, whose
  phases are `worktree` (deterministic, done) then `explore`. No capture has a started step or a
  subtask whose current phase is `verify`; tests build one from a capture copy, marked
  `// synthetic:` as `test_fixture_run_tree_started_deterministic_phase` does
  (`tests/core/domain/tst_runs.qml:725-745`).

## Inherited constraints

| constraint | source |
|---|---|
| `Runs.isLiveSelection(run, sel)` is pure: true when the run's state is `running` and the selection is in flight — an agent attempt whose status is `started`, or a step whose phase status is `started`. Everything else (an ended attempt; a parked, dead, escalated, cancelled/canceled or done run) is not live. | LO lines 100-103 |
| A step selection is `{card_id, phase, attempt: 0, step: true}`; attempt 0 means "the step's latest". | LO lines 105-106 |
| The Run detail tree lists a step row for every deterministic phase that has started (`verify ⟳`, `docs_commit ✔`). | LO lines 106-108 |
| `Runs.defaultAttempt` prefers the current started phase, step or agent, so opening a run whose subtask is in `verify` opens `verify`. | LO lines 109-110 |
| Deterministic phases are `kind: "deterministic"` and carry `attempts: []`. | LO lines 33-36 |
| Run, story, subtask and phase status vocabulary: `pending, started, done, failed, escalated, stopped, cancelled, canceled`; attempt vocabulary: `started, ok, schema_invalid, gate_failed, harness_error`. | `docs/superpowers/plans/1-1-contract-test-the-f1f0e802.md:224` (the contract test's pinned vocabulary) |
| `runState`: `started` + live lease is `running`; `cancelled` and `canceled` are both `cancelled`. | `runs.js:144-161` |
| Tests in `tests/core/domain/tst_runs.qml`: step rows in `runTree`, `defaultAttempt` on a started step, `isLiveSelection` for every state, `cancelled` and `canceled`. | LO lines 240-241; card |
| Domain file: `.pragma library`, pure, never throws; imports only other `core/domain` or `vendor/canvas` `.js` files. | `docs/architecture.md:11`; `tests/architecture/test_layers.py` |
| Docstrings and comments state the contract only, no narrative; `bash tests/run.sh` green (including `tests/architecture`); TDD, tests first. | card description |

## Behaviour

No function below throws on any input or mutates its arguments.

**Terms.** A *step phase* is a phase object whose `kind` is exactly the string
`"deterministic"`; any other `kind` (absent, `"agent"`, a non-string) is an agent phase, as
today. A phase has *started or finished* when its `status` is one of `started`, `done`,
`failed`, `escalated`, `stopped`, `cancelled`, `canceled` — every phase status of am's
vocabulary except `pending`. `pending`, `""`, any other string and any non-string are not.

### B1. `runTree(run)`: step entries

For each subtask node (`_subtaskNode`), while walking the named phases in order:

- A step phase that has started or finished adds one entry to the node's `attempts`, at that
  phase's position in phase order:
  `{phase: <name>, attempt: 0, step: true, status: <phase status>}` (key order as written).
- Any attempt objects the step phase itself carries are still listed after its step entry,
  unchanged (am gives none today).
- Agent phases contribute exactly what they do today; agent entries get **no** `step` key, so
  their shape stays `{phase, attempt, status}`.
- A step phase that is `pending`, has no or an unknown status, or has an empty/non-string name
  adds no entry.
- Unchanged: `phases` entries stay `{name, status}` (no `kind` is added there), and
  `currentPhase` / `currentAttempt` keep their current rule (`runs.js:734-738`).

Examples: in `status-done.json` each of the ten subtask nodes now has 14 `attempts` (7 agent
attempts, 7 `done` step entries) instead of 7. In `status-escalated.json`, subtask
`10e26d57-374c-48d3-bc45-09389b42cfac` lists, in order: `worktree` step, `explore.1`,
`mark_in_progress` step, `plan_check` step, `spec.1`, `validate_spec.1`, `plan.1`,
`validate_plan.1`, `mark_validated` step, `docs_commit` step, `implement.1`, `review.1`
(`gate_failed`) — review.1 at index 11, explore.1 at index 1.

### B2. `defaultAttempt(run)`: a started step

Walk real-card subtasks (`_isCardId`) in order and their phases in order; take the **first**
phase whose `status` is exactly `"started"` and whose `name` is a non-empty string, among those
that qualify:

- a step phase qualifies always → `{card_id, phase, attempt: 0, step: true}`;
- an agent phase qualifies when it has a numbered attempt → `{card_id, phase, attempt: n}`
  (newest number, no `step` key), exactly as today;
- an agent phase with no numbered attempt does not qualify and the walk continues (today's
  behaviour, pinned by `tst_runs.qml:2081-2084`).

When no phase qualifies, the flat-row fallback (`runs.js:837-846`) is unchanged; it never
yields a step (a step's row has no attempt number). Garbage still gives `null`.

### B3. `isLiveSelection(run, sel)` → boolean (new)

Placed after `attemptStatus`. Returns `true` exactly when all hold, `false` otherwise (always a
boolean, never throws):

1. `runState(run) === "running"`;
2. `sel` is an object (`_isObject`), `sel.card_id` passes `_isCardId`, and `sel.phase` is a
   non-empty string;
3. if `sel.step === true` (strictly): the subtask with `sel.card_id` has a phase named
   `sel.phase` (`_findPhase`, the first with that name) whose `status === "started"`;
   `sel.attempt` is not read;
   otherwise: `attemptStatus(run, sel.card_id, sel.phase, sel.attempt) === "started"` (so
   `sel.attempt` must be a finite number above 0).

Consequences pinned by tests: a started attempt (or started step) in a `dead`, `parked`,
`escalated`, `done`, `cancelled`/`canceled` or `unknown` run is not live; an attempt status of
`ok`, `gate_failed`, `schema_invalid`, `harness_error` or `""` is not live; a step selection of
a `done` step is not live; a selection without `step: true` and with attempt 0 is not live.

## Error paths

- `runTree`, `defaultAttempt`: existing garbage tests (`tst_runs.qml:2014-2028`, `2099-2101`)
  keep passing; a phase with `kind: "deterministic"` and a non-string `status` adds no entry.
- `isLiveSelection`: `run` or `sel` `undefined`, `null`, a string, a number, an array → `false`;
  `sel.card_id` a bookkeeping id (`integrate`, `bases`, `base-*`), `""`, non-string → `false`;
  `sel.phase` missing/empty/non-string → `false`; `sel.step` truthy but not `true` (`"true"`,
  `1`) → the agent branch; a card or phase not in the tree → `false`.

## Interim effects (accepted, owned by sibling cards)

- `RunStore.selectAttempt` rejects attempt 0 (`core/stores/RunStore.qml:797-813`), so a run
  whose default is a step opens with no selection until the RunStore card wires step selections
  (LO line 248, "`tst_run_store.qml`: selecting a step"). Before this card, such a run opened on
  the row fallback's attempt. No recorded fixture is in that situation, so no store or UI test
  changes for it.
- `RunDetailScreen` renders every `attempts` entry as an `AttemptRow`, so step entries show as
  `<glyph> verify.? done` and are not clickable (attempt 0) until the UI card (LO line 212).
- `tests/ui/screens/tst_run_detail_screen.qml:286` and `:291` hard-code attempt-row indexes of
  `status-escalated.json`'s subtask `10e26d57…` that step entries shift: `"1_0_6"` becomes
  `"1_0_11"` and `"runAttemptLabel1_0_0"` (explore.1) becomes `"runAttemptLabel1_0_1"`. These
  index-only updates are in scope; nothing else in that test changes.

## Tests

All new tests go in `tests/core/domain/tst_runs.qml` (tier: domain unit test, run by
`qmltestrunner` through `tests/run.sh`; `runs.js` is a `.pragma library` file only the QML
engine loads, and every behaviour here is a pure function's return value). Use the file's
helpers: `amRun(name)` (fresh fixture copy, line 15), `fixtureRuns()`, `treeNode(tree, cardId)`
(line 672), `at(d)` (line 2077), `mkRun(id, status, live, opts)` (line 871), `cancelledRun`
(line 822). Every edit of a capture copy carries a `// synthetic:` comment saying what was
changed. A helper `startedStepRun(phaseName)` may be added: `status-started.json` with
`2280a6ab…`'s `explore` set to `done` and a deterministic phase
`{name, kind: "deterministic", status: "started", started_at: "", ended_at: null, detail: null,
attempts: []}` appended (same keys as its neighbours, as at line 739).

Fixture-based (recorded status fixtures):

1. `test_fixture_normalized_phases_keep_kind` — for each `fixtureRuns()` run, every phase of
   every `tree.subtasks[]` has `kind` `"agent"` or `"deterministic"`, matching the capture.
2. `test_fixture_run_tree_step_entries` — `status-done.json`: every node has 14 `attempts`;
   7 have `step === true`, `attempt === 0`, `status === "done"`, and their phases are the 7
   deterministic phase names in phase order; agent entries have no `step` key
   (`!("step" in entry)`). `status-escalated.json` `10e26d57…`: the full `phase.attempt` order of
   B1 with `step` flags.
3. Update `test_fixture_run_tree_open_attempt` (line 693): `node.attempts.length` 7 → 14;
   the `opensOn` expectations stay as they are (current-phase rule unchanged).
4. `test_fixture_run_tree_started_step_entry` — `startedStepRun("verify")`: `2280a6ab…`'s
   attempts read `worktree` step `done`, `explore.1` `done`… then a `verify` step `started`;
   `opensOn` is `verify/0`.
5. `test_fixture_default_attempt_on_a_started_step` — `startedStepRun("verify")`:
   `defaultAttempt` deep-equals `{card_id: "2280a6ab-…", phase: "verify", attempt: 0, step: true}`
   (compare `JSON.stringify`). `test_fixture_current_phase_and_default_attempt` (line 608)
   stays green unchanged and its agent results carry no `step` key.
6. `test_fixture_is_live_selection_by_run_state` — the explore.1 selection of
   `status-started.json` and a `verify` step selection of `startedStepRun("verify")`: `true` when
   running; `false` after a synthetic edit to each other state: lease `live: false` (dead),
   no `control` (dead), run status `stopped` (parked), `escalated`, `done`, `cancelled`,
   `canceled` (both through the existing spelling list `cancelSpellings()`), and an unknown status.
7. `test_fixture_is_live_selection_by_attempt_status` — running `status-started.json` with
   explore.1's status set (synthetic) to each of `started` (true), `ok`, `gate_failed`,
   `schema_invalid`, `harness_error`, `""` (false); a finished attempt of the same running run
   (`5560d0fe…` review.1, `ok`) is false; a `done` step (`worktree` of `2280a6ab…`) selected
   as a step is false; the escalated capture's `10e26d57…` review.1 (`gate_failed`) is false.

Synthetic (`mkRun` trees):

8. `test_run_tree_step_entries_rule` — one subtask with phases: deterministic `started`,
   `done`, `failed`, `escalated`, `stopped`, `cancelled`, `canceled` → one entry each;
   deterministic `pending`, `""`, `"running"`, `null`, `5` → none; `kind` `"agent"`, absent,
   `"Deterministic"`, `5` with status `done` and no attempts → none; a deterministic phase
   carrying `attempts: [{n: 1, status: "ok"}]` → its step entry then `x.1`; an unnamed
   deterministic phase → none. Existing `test_run_tree` (line 1967) stays green unchanged.
9. `test_default_attempt_prefers_the_first_started_phase` — a subtask whose first started phase
   is a step wins over a later subtask's numbered agent attempt; a subtask with a started agent
   phase without numbers then a started step yields the step; a started agent attempt before a
   started step yields the agent attempt; a bookkeeping id with a started step yields `null`.
   Existing `test_default_attempt` (line 2079) stays green unchanged.
10. `test_is_live_selection_garbage` — the error paths above, each `false`, and the result's
    `typeof` is `"boolean"` for every case.
11. `test_is_live_selection_step_flag` — on a running `mkRun` with a started phase `implement`
    (attempt 2 `started`): `{…, attempt: 2}` true; `{…, attempt: 0, step: true}` true (phase
    started); `{…, attempt: 0}` false; `{…, attempt: 2, step: "true"}` true (agent branch);
    a started deterministic phase selected without `step` and attempt 0 → false.

UI test kept green (tier: UI test, `tests/ui/screens/tst_run_detail_screen.qml`, already in
the suite): only the two index literals named under Interim effects change.

## Out of scope

- `RunStore` / `RunOutputStore`: selecting a step, `selectAttempt` accepting attempt 0,
  following, snapshot logs for a step (LO lines 157-190, 245-248: sibling cards).
- `RunDetailScreen`: the step row's label (`verify` with its phase glyph, no attempt number),
  making step rows clickable, the output pane, `TailScroll` (LO lines 192-212, 249-250).
- `runs-logs.py` / `runs-logs-follow.py` (ATTEMPT `0` omits `--attempt`) and the contract test
  (LO lines 112-135, 231-236, 242-244).
- Adding `kind` to the node's `phases` entries, or any `normalizeRun` change.
- `currentPhase` / `currentAttempt`, `cardRunState`, `attemptStatus` behaviour.
- `docs/architecture.md` and README wording (the story's docs work).

## Handoff to the planner

Follow the `writing-plans` format. Files: modify `core/domain/runs.js` (`_subtaskNode`
`739-765`, `defaultAttempt` `820-847`, add `isLiveSelection` after `attemptStatus` `849-858`,
with a contract-only comment above each changed function), `tests/core/domain/tst_runs.qml`,
and the two literals in `tests/ui/screens/tst_run_detail_screen.qml`. Style: ES5, `var`,
private helpers prefixed `_` (e.g. one `_isStepPhase(p)` and a status set for "started or
finished"), reuse `_isObject`, `_stringOr`, `_isCardId`, `_findPhase`, `_findByCardId`,
`_subtasksOf`. Run one QML file with `bash tests/run.sh tst_runs` (pytest runs first); the gate
is the full `bash tests/run.sh`.

Suggested tasks (each with its own test cycle):

1. Step entries in `runTree`: tests 1-4, 8, and the two `tst_run_detail_screen.qml` literals
   (they fail as soon as step entries land, so they belong to this task).
2. `defaultAttempt` step preference: tests 5, 9.
3. `isLiveSelection`: tests 6, 7, 10, 11.

Review Focus candidates: a deterministic phase whose name repeats (a re-run `verify`) — one step
entry per phase object, and `isLiveSelection` reads the first by name as `_findPhase` does; a
started step in a dead run (lease lost mid-`verify`) is not live; a cancelled run whose attempt
still reads `started`; a selection object carrying extra keys (`step: false`); a run in
`unknown` state with a started attempt.
