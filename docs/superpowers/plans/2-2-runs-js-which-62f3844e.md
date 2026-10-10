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

---

# 2.2 `runs.js`: which selection is live, steps included Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In `core/domain/runs.js`, list a step entry for every started-or-finished deterministic phase in `runTree`, let `defaultAttempt` open a started step, and add `isLiveSelection(run, sel)`.

**Architecture:** Three pure changes in one `.pragma library` ES5 file. One private predicate `_isStepPhase(p)` and one status list `_STARTED_OR_FINISHED` decide what a step is and when it shows; `_subtaskNode` pushes `{phase, attempt: 0, step: true, status}` before a step phase's own attempts; `defaultAttempt` returns `{card_id, phase, attempt: 0, step: true}` for a started step; `isLiveSelection` combines `runState` with `_findPhase` (step) or `attemptStatus` (agent).

**Tech Stack:** QML JavaScript (V4, `.pragma library`), QtTest via `qmltestrunner`, the `tests/run.sh` gate (pytest incl. `tests/architecture`, then every `tst_*.qml`).

**Spec:** `docs/superpowers/specs/2-2-runs-js-which-62f3844e.md` (reproduced above).

## Global Constraints

- `core/domain/runs.js` stays `.pragma library`, pure, never throws; no function mutates its arguments; no new `.import`.
- Style: ES5, `var`, `function`, private helpers prefixed `_`; reuse `_isObject`, `_stringOr`, `_isCardId`, `_findPhase`, `_findByCardId`, `_subtasksOf`, `_newestAttempt`, `attemptStatus`, `runState`.
- Docstrings and comments state the contract only, no narrative.
- A step phase is `kind === "deterministic"` exactly. "Started or finished" is a phase `status` in `started, done, failed, escalated, stopped, cancelled, canceled`.
- Step entry shape and key order: `{phase, attempt: 0, step: true, status}`. Agent entries keep `{phase, attempt, status}` with **no** `step` key.
- Step selection shape and key order: `{card_id, phase, attempt: 0, step: true}`. Agent selections keep `{card_id, phase, attempt}`.
- `isLiveSelection` always returns a boolean.
- `phases` entries of a node stay `{name, status}`; `currentPhase`/`currentAttempt`, `normalizeRun`, `attemptStatus`, `cardRunState` unchanged.
- Tests go in `tests/core/domain/tst_runs.qml`; every edit of a capture copy carries a `// synthetic:` comment. Only the two index literals change in `tests/ui/screens/tst_run_detail_screen.qml`.
- Files touched: `core/domain/runs.js`, `tests/core/domain/tst_runs.qml`, `tests/ui/screens/tst_run_detail_screen.qml`. Nothing else (no docs, no stores, no UI).
- Gate: `bash tests/run.sh` green. TDD: tests first.

## Review Focus

1. A deterministic phase whose name repeats (a re-run `verify`: one `done`, then one `started`) — `runTree` lists one step entry per phase object; `isLiveSelection` reads the first phase of that name (as `_findPhase` does), so a step selection of it is not live. Pinned in `test_run_tree_step_entries_rule` (Task 1) and `test_is_live_selection_step_flag` (Task 3).
2. A started step in a dead run (the lease lost mid-`verify`, or no `control` at all) — not live. Pinned in `test_fixture_is_live_selection_by_run_state` (Task 3).
3. A cancelled run (`cancelled` and `canceled`) whose attempt still reads `started` — not live. Pinned in `test_fixture_is_live_selection_by_run_state` (Task 3).
4. A selection object with extra keys or `step: false` — `step: false` takes the agent branch, extra keys are ignored. Pinned in `test_is_live_selection_step_flag` (Task 3).
5. A run in `unknown` state (an unrecognised run status) with a started attempt and a started step — not live. Pinned in `test_fixture_is_live_selection_by_run_state` (Task 3).

## File map

- Modify `core/domain/runs.js`: add `_STARTED_OR_FINISHED` and `_isStepPhase` after `_syntheticLabel` (`runs.js:728-732`); change `_subtaskNode` (`runs.js:734-765`, comment included); change `defaultAttempt` (`runs.js:820-847`, comment included); add `isLiveSelection` after `attemptStatus` (`runs.js:849-858`).
- Modify `tests/core/domain/tst_runs.qml`: new helpers and tests; `test_fixture_run_tree_open_attempt` line 693 `7` → `14`.
- Modify `tests/ui/screens/tst_run_detail_screen.qml`: line 286 `"1_0_6"` → `"1_0_11"`, line 291 `"runAttemptLabel1_0_0"` → `"runAttemptLabel1_0_1"`.

## Commands

All from the worktree root.

- Domain tests only (~1 s):
  `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml 2>&1 | grep -E '^FAIL|Totals|^   Loc'`
- One domain test function: append the function name after the file, e.g.
  `... -input tests/core/domain/tst_runs.qml test_run_tree_step_entries_rule 2>&1 | grep -E '^FAIL|Totals|^   Loc'`
- Run detail UI tests (~10 s):
  `timeout 300 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/ui/screens/tst_run_detail_screen.qml 2>&1 | grep -E '^FAIL|Totals|^   Loc'`
- Gate (pytest including `tests/architecture`, then every QML test; a few minutes):
  `timeout 900 bash tests/run.sh`

Baseline before Task 1: `tst_runs.qml` reports `Totals: 201 passed, 0 failed`; `tst_run_detail_screen.qml` reports `Totals: 38 passed, 0 failed`.

---

### Task 1: Step entries in `runTree`

**Files:**
- Modify: `core/domain/runs.js:728-765` (new `_STARTED_OR_FINISHED`, `_isStepPhase`; `_subtaskNode`)
- Test: `tests/core/domain/tst_runs.qml` (new helpers `rawSubtask`, `startedStepRaw`, `entries`; tests 1, 2, 4, 8; line 693 edit)
- Modify: `tests/ui/screens/tst_run_detail_screen.qml:286,291`

**Interfaces:**
- Consumes: `_isObject(v)`, `_stringOr(v)`, `_attemptNumber(a)`, `_newestAttempt(p)` (all existing in `runs.js`); test helpers `amRun(name)`, `fixtureRuns()`, `treeNode(tree, cardId)`, `opensOn(node)`, `mkRun(id, status, live, opts)` (existing in `tst_runs.qml`).
- Produces (runs.js, private): `var _STARTED_OR_FINISHED = ["started", "done", "failed", "escalated", "stopped", "cancelled", "canceled"]`; `function _isStepPhase(p)` → boolean (`_isObject(p) && p.kind === "deterministic"`). `runTree(run)` nodes' `attempts` gain `{phase: string, attempt: 0, step: true, status: string}` entries.
- Produces (tst_runs.qml helpers, used by Tasks 2 and 3): `rawSubtask(raw, cardId)` → the raw am subtask object or `null`; `startedStepRaw(name)` → a raw `amRun("status-started.json")` whose subtask `2280a6ab-9c40-434b-9729-63fd1f373754` has `explore` `done` (attempt 1 `ok`) and a deterministic phase `name` `started` appended; `entries(node)` → `"phase.attempt[:step]:status"` per attempts entry, comma-joined.

- [ ] **Step 1: Write the helpers and the failing tests**

In `tests/core/domain/tst_runs.qml`, directly after the closing `}` of `test_fixture_run_tree_started_deterministic_phase` (it ends right before `function test_state_running() {`), insert:

```qml
  // ---- Live output 2.2: step entries, a started step, live selections ------------------------

  // The am subtask with this card id in a raw amRun's stories, else null.
  function rawSubtask(raw, cardId) {
    var stories = raw.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) {
        if (stories[i].subtasks[j].card_id === cardId) return stories[i].subtasks[j]
      }
    }
    return null
  }

  // status-started.json, raw, with 2280a6ab's explore finished and a
  // deterministic phase `name` started after it.
  function startedStepRaw(name) {
    var raw = amRun("status-started.json")
    var subtask = rawSubtask(raw, "2280a6ab-9c40-434b-9729-63fd1f373754")
    // synthetic: explore finished (phase done, attempt 1 ok) and a deterministic phase in flight -- no capture has one
    subtask.phases[1].status = "done"
    subtask.phases[1].attempts[0].status = "ok"
    subtask.phases.push({ name: name, kind: "deterministic", status: "started", started_at: "", ended_at: null, detail: null, attempts: [] })
    return raw
  }

  // "phase.attempt[:step]:status" for each attempts entry of a tree node, comma-joined.
  function entries(node) {
    return node.attempts.map(function(a) {
      return a.phase + "." + a.attempt + (a.step === true ? ":step" : "") + ":" + a.status
    }).join(",")
  }

  function test_fixture_normalized_phases_keep_kind() {
    var names = ["status-started.json", "status-done.json", "status-escalated.json", "status-done-integrate.json"]
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      var raw = amRun(names[i])
      var subtasks = runs[i].tree.subtasks
      var checked = 0
      for (var j = 0; j < subtasks.length; j++) {
        var am = rawSubtask(raw, subtasks[j].card_id)
        verify(am !== null, names[i] + " " + subtasks[j].card_id + " is in the capture")
        var phases = subtasks[j].phases
        for (var k = 0; k < phases.length; k++) {
          var label = names[i] + " " + subtasks[j].card_id + " " + phases[k].name
          verify(phases[k].kind === "agent" || phases[k].kind === "deterministic", label + " kind " + phases[k].kind)
          compare(phases[k].kind, am.phases[k].kind, label + " matches the capture")
          checked++
        }
      }
      verify(checked > 0, names[i] + " has phases")
    }
  }

  function test_fixture_run_tree_step_entries() {
    var done = amRun("status-done.json")
    var tree = Runs.runTree(Runs.normalizeRun(done))
    var nodes = 0
    for (var i = 0; i < tree.stories.length; i++) {
      for (var j = 0; j < tree.stories[i].subtasks.length; j++) {
        var node = tree.stories[i].subtasks[j]
        var am = rawSubtask(done, node.card_id)
        var stepNames = am.phases.filter(function(p) { return p.kind === "deterministic" })
                                 .map(function(p) { return p.name }).join(",")
        compare(stepNames, "worktree,mark_in_progress,plan_check,mark_validated,docs_commit,verify,mark_done", node.card_id + " capture")
        compare(node.attempts.length, 14, node.card_id + " attempts")
        var steps = node.attempts.filter(function(a) { return a.step === true })
        compare(steps.length, 7, node.card_id + " steps")
        compare(steps.map(function(a) { return a.phase }).join(","), stepNames, node.card_id + " steps in phase order")
        for (var s = 0; s < steps.length; s++) {
          compare(Object.keys(steps[s]).join(","), "phase,attempt,step,status", node.card_id + " step shape")
          compare(steps[s].attempt, 0, node.card_id + " " + steps[s].phase)
          compare(steps[s].status, "done", node.card_id + " " + steps[s].phase)
        }
        var agents = node.attempts.filter(function(a) { return !("step" in a) })
        compare(agents.length, 7, node.card_id + " agent attempts")
        for (var g = 0; g < agents.length; g++)
          compare(Object.keys(agents[g]).join(","), "phase,attempt,status", node.card_id + " agent shape")
        nodes++
      }
    }
    compare(nodes, 10, "every done subtask is a node")

    var escalated = Runs.runTree(Runs.normalizeRun(amRun("status-escalated.json")))
    var node10 = treeNode(escalated, "10e26d57-374c-48d3-bc45-09389b42cfac")
    compare(entries(node10),
            "worktree.0:step:done,explore.1:ok,mark_in_progress.0:step:done,plan_check.0:step:done," +
            "spec.1:ok,validate_spec.1:ok,plan.1:ok,validate_plan.1:ok," +
            "mark_validated.0:step:done,docs_commit.0:step:done,implement.1:ok,review.1:gate_failed")
    compare(node10.attempts[11].phase + "." + node10.attempts[11].attempt, "review.1")
    compare(node10.attempts[1].phase + "." + node10.attempts[1].attempt, "explore.1")
  }

  function test_fixture_run_tree_started_step_entry() {
    var node = treeNode(Runs.runTree(Runs.normalizeRun(startedStepRaw("verify"))), "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(entries(node), "worktree.0:step:done,explore.1:ok,verify.0:step:started")
    compare(opensOn(node), "verify/0")
  }
```

Directly after the closing `}` of `test_run_tree_open_attempt_rule` (right before `function at(d)`), insert:

```qml
  function test_run_tree_step_entries_rule() {
    function det(name, status) { return { name: name, kind: "deterministic", status: status, attempts: [] } }
    function other(name, kind) { return { name: name, kind: kind, status: "done", attempts: [] } }
    // synthetic: hand-built normalized subtasks, one per case of the step-entry rule
    var run = mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "a", phases: [
        det("s1", "started"), det("s2", "done"), det("s3", "failed"), det("s4", "escalated"),
        det("s5", "stopped"), det("s6", "cancelled"), det("s7", "canceled"),
        det("p1", "pending"), det("p2", ""), det("p3", "running"), det("p4", null), det("p5", 5),
        det("p6", "Started"), det("p7", "constructor"), { name: "p8", kind: "deterministic", attempts: [] },
        other("k1", "agent"), { name: "k2", status: "done", attempts: [] }, other("k3", "Deterministic"), other("k4", 5),
        { name: "x", kind: "deterministic", status: "done", attempts: [{ n: 1, status: "ok" }] },
        det("", "done"), { kind: "deterministic", status: "done", attempts: [] }, { name: 7, kind: "deterministic", status: "done" }
      ] },
      { card_id: "b", phases: [det("verify", "done"), det("verify", "started")] }
    ] } })
    var before = JSON.stringify(run)
    var t = Runs.runTree(run)
    compare(JSON.stringify(run), before, "the run is not mutated")
    var a = treeNode(t, "a")
    compare(entries(a),
            "s1.0:step:started,s2.0:step:done,s3.0:step:failed,s4.0:step:escalated," +
            "s5.0:step:stopped,s6.0:step:cancelled,s7.0:step:canceled,x.0:step:done,x.1:ok")
    compare(Object.keys(a.attempts[0]).join(","), "phase,attempt,step,status", "step entry key order")
    compare(Object.keys(a.attempts[8]).join(","), "phase,attempt,status", "a step phase's own attempt has no step key")
    compare(Object.keys(a.phases[0]).join(","), "name,status", "phases entries carry no kind")
    compare(opensOn(a), "s1/0", "the current-phase rule is unchanged")
    compare(entries(treeNode(t, "b")), "verify.0:step:done,verify.0:step:started", "one step entry per phase object")
  }
```

In `test_fixture_run_tree_open_attempt`, change line 693:

```qml
        compare(node.attempts.length, 7, node.card_id + " attempts")
```

to:

```qml
        compare(node.attempts.length, 14, node.card_id + " attempts")
```

In `tests/ui/screens/tst_run_detail_screen.qml`, change line 286:

```qml
    compare(key, "1_0_6", "where the capture puts review.1 of " + card)
```

to:

```qml
    compare(key, "1_0_11", "where the capture puts review.1 of " + card)
```

and line 291:

```qml
    var ok = H.find(s.screen, "runAttemptLabel1_0_0")
```

to:

```qml
    var ok = H.find(s.screen, "runAttemptLabel1_0_1")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the domain tests (Commands).
Expected: `test_fixture_normalized_phases_keep_kind` PASSES (it pins what `normalizeRun` already does). FAIL for `test_fixture_run_tree_step_entries` (`node.attempts.length` actual 7, expected 14), `test_fixture_run_tree_started_step_entry` (entries without `worktree.0:step:done` / `verify.0:step:started`), `test_run_tree_step_entries_rule` (entries is `x.1:ok` only), `test_fixture_run_tree_open_attempt` (actual 7, expected 14). `Totals: 201 passed, 4 failed`.

Run the Run detail UI tests (Commands).
Expected: FAIL in `test_a_gate_failed_attempt_of_real_am_shows_the_dead_glyph_in_urgent` (`key` actual `1_0_6`, expected `1_0_11`). `Totals: 37 passed, 1 failed`.

- [ ] **Step 3: Write the implementation**

In `core/domain/runs.js`, directly after `_syntheticLabel` (the function ending `return id.length > 5 ? "Base " + id.slice(5) : "Base"` and its `}`), insert:

```js
// am's phase statuses other than pending: the phase has started or finished.
var _STARTED_OR_FINISHED = ["started", "done", "failed", "escalated", "stopped", "cancelled", "canceled"]

// A phase am runs itself: kind exactly "deterministic".
function _isStepPhase(p) { return _isObject(p) && p.kind === "deterministic" }
```

Replace the comment and body of `_subtaskNode` (currently `runs.js:734-765`) with:

```js
// One subtask as the detail tree shows it. Its own status, else its last am
// row's; phases with a name only. Attempts in phase order: for a step phase
// (kind "deterministic") that has started or finished, one step entry
// {phase, attempt: 0, step: true, status}; then every attempt object of the
// phase as {phase, attempt, status} (attempt 0 when it has no number). The
// current phase is the first started one, else the last one with a numbered
// attempt, else the last; the current attempt is that phase's newest number,
// 0 when it has none.
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
    if (_isStepPhase(p) && _STARTED_OR_FINISHED.indexOf(p.status) >= 0)
      attempts.push({ phase: p.name, attempt: 0, step: true, status: p.status })
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

(`indexOf` uses `===`, so a non-string `status` such as `null` or `5` matches nothing.)

- [ ] **Step 4: Run the tests to verify they pass**

Run the domain tests. Expected: `Totals: 205 passed, 0 failed`.
Run the Run detail UI tests. Expected: `Totals: 38 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(domain): runTree lists a step entry for each started or finished deterministic phase"
```

---

### Task 2: `defaultAttempt` opens a started step

**Files:**
- Modify: `core/domain/runs.js` — `defaultAttempt` and its comment (currently `runs.js:820-847`, a few lines lower after Task 1)
- Test: `tests/core/domain/tst_runs.qml` (tests 5, 9)

**Interfaces:**
- Consumes: `_isStepPhase(p)` (Task 1, runs.js); `startedStepRaw(name)` and `fixtureRuns()` (tst_runs.qml; `startedStepRaw` from Task 1); `mkRun`, `at(d)` (existing).
- Produces: `defaultAttempt(run)` → `{card_id: string, phase: string, attempt: 0, step: true}` for a started step, `{card_id, phase, attempt: number}` (no `step` key) for an agent attempt, or `null`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, directly after the closing `}` of `test_fixture_run_tree_started_step_entry` (Task 1), insert:

```qml
  function test_fixture_default_attempt_on_a_started_step() {
    compare(JSON.stringify(Runs.defaultAttempt(Runs.normalizeRun(startedStepRaw("verify")))),
            JSON.stringify({ card_id: "2280a6ab-9c40-434b-9729-63fd1f373754", phase: "verify", attempt: 0, step: true }))
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      var d = Runs.defaultAttempt(runs[i])
      verify(d !== null, "a default for " + runs[i].id)
      verify(!("step" in d), "an agent attempt carries no step key: " + runs[i].id)
    }
  }
```

Directly after the closing `}` of `test_default_attempt` (right before `function test_attempt_status() {`), insert:

```qml
  function test_default_attempt_prefers_the_first_started_phase() {
    function step(name, status) { return { name: name, kind: "deterministic", status: status, attempts: [] } }
    function agent(name, status, attempts) { return { name: name, kind: "agent", status: status, attempts: attempts } }
    function dflt(subtasks, rows) {
      // synthetic: hand-built normalized subtasks for the default-attempt rule
      var run = mkRun("r", "started", true, { rows: rows || [], tree: { stories: [], subtasks: subtasks } })
      var before = JSON.stringify(run)
      var d = Runs.defaultAttempt(run)
      compare(JSON.stringify(run), before, "the run is not mutated")
      return JSON.stringify(d)
    }
    compare(dflt([{ card_id: "a", phases: [step("worktree", "done"), step("verify", "started")] },
                  { card_id: "b", phases: [agent("implement", "started", [{ n: 1, status: "started" }])] }]),
            JSON.stringify({ card_id: "a", phase: "verify", attempt: 0, step: true }),
            "a started step of an earlier subtask wins over a later numbered attempt")
    compare(dflt([{ card_id: "a", phases: [agent("plan", "started", []), step("verify", "started")] }]),
            JSON.stringify({ card_id: "a", phase: "verify", attempt: 0, step: true }),
            "a started agent phase without numbers is passed over for a later started step")
    compare(dflt([{ card_id: "a", phases: [agent("implement", "started", [{ n: 2, status: "started" }]), step("verify", "started")] }]),
            JSON.stringify({ card_id: "a", phase: "implement", attempt: 2 }),
            "a started agent attempt before a started step wins, with no step key")
    compare(dflt([{ card_id: "integrate", phases: [step("integrate", "started")] }]), "null",
            "a bookkeeping id with a started step is never a card")
    compare(dflt([{ card_id: "a", phases: [step("", "started"), step("verify", "running"), step("verify", "done")] }],
                 [{ card_id: "a", phase: "verify", attempt: null, status: "done" }]), "null",
            "an unnamed or not-started step is not chosen, and the row fallback never yields a step")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the domain tests (Commands).
Expected: FAIL for `test_fixture_default_attempt_on_a_started_step` (actual is the row fallback's `explore` attempt, or another non-step value, not the `verify` step) and `test_default_attempt_prefers_the_first_started_phase` (first case actual `{"card_id":"b","phase":"implement","attempt":1}`). `Totals: 205 passed, 2 failed`.

- [ ] **Step 3: Write the implementation**

In `core/domain/runs.js`, replace the comment and the subtask loop of `defaultAttempt` so the whole function reads:

```js
// The selection the output pane opens on: the first started phase, in subtask
// and phase order, that is a step ({card_id, phase, attempt: 0, step: true})
// or an agent phase with a numbered attempt ({card_id, phase, attempt}, its
// newest number); else, walking the flat rows from the last, the newest
// attempt of a real card's row phase (the row's own number or the tree's,
// whichever is higher); else null.
function defaultAttempt(run) {
  var subtasks = _subtasksOf(run)
  for (var i = 0; i < subtasks.length; i++) {
    var t = subtasks[i]
    if (!_isObject(t) || !_isCardId(t.card_id)) continue
    var phases = _arrayOr(t.phases)
    for (var j = 0; j < phases.length; j++) {
      var p = phases[j]
      if (!_isObject(p) || p.status !== "started" || typeof p.name !== "string" || p.name === "") continue
      if (_isStepPhase(p)) return { card_id: t.card_id, phase: p.name, attempt: 0, step: true }
      var n = _newestAttempt(p)
      if (n > 0) return { card_id: t.card_id, phase: p.name, attempt: n }
    }
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = rows.length - 1; r >= 0; r--) {
    var row = rows[r]
    if (!_isObject(row) || !_isCardId(row.card_id)) continue
    var phase = _stringOr(row.phase)
    if (phase === "") continue
    var newest = Math.max(_attemptNumber(row), _newestAttempt(_findPhase(_findByCardId(subtasks, row.card_id), phase)))
    if (newest > 0) return { card_id: row.card_id, phase: phase, attempt: newest }
  }
  return null
}
```

(The only code change is the `if (_isStepPhase(p)) return …` line; the row fallback is unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

Run the domain tests. Expected: `Totals: 207 passed, 0 failed` (`test_default_attempt` and `test_fixture_current_phase_and_default_attempt` stay green unchanged).

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(domain): defaultAttempt opens the first started phase, step or agent"
```

---

### Task 3: `isLiveSelection`

**Files:**
- Modify: `core/domain/runs.js` — add `isLiveSelection` directly after `attemptStatus`
- Test: `tests/core/domain/tst_runs.qml` (tests 6, 7, 10, 11)

**Interfaces:**
- Consumes: `runState(run)`, `attemptStatus(run, cardId, phase, attempt)`, `_isObject`, `_isCardId`, `_findPhase`, `_findByCardId`, `_subtasksOf` (runs.js, existing); test helpers `startedStepRaw`, `rawSubtask` (Task 1), `cancelSpellings()`, `detailRun()`, `mkRun` (existing).
- Produces: `isLiveSelection(run, sel)` → boolean. Public; the later `RunOutputStore` card calls it.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, directly after the closing `}` of `test_fixture_default_attempt_on_a_started_step` (Task 2), insert:

```qml
  function test_fixture_is_live_selection_by_run_state() {
    var card = "2280a6ab-9c40-434b-9729-63fd1f373754"
    var explore = { card_id: card, phase: "explore", attempt: 1 }
    var verifyStep = { card_id: card, phase: "verify", attempt: 0, step: true }
    // [label, synthetic edit of the capture copy, runState, live]
    var cases = [
      ["running", function(raw) {}, "running", true],
      // synthetic: the lease edited to not live
      ["lease not live", function(raw) { raw.status.control.lease.live = false }, "dead", false],
      // synthetic: am's control removed, so no lease
      ["no control", function(raw) { delete raw.status.control }, "dead", false],
      // synthetic: the run status edited to stopped
      ["stopped", function(raw) { raw.status.run.status = "stopped" }, "parked", false],
      // synthetic: the run status edited to escalated
      ["escalated", function(raw) { raw.status.run.status = "escalated" }, "escalated", false],
      // synthetic: the run status edited to done
      ["done", function(raw) { raw.status.run.status = "done" }, "done", false],
      // synthetic: the run status edited to a status am does not give
      ["unknown", function(raw) { raw.status.run.status = "weird" }, "unknown", false]
    ]
    var spellings = cancelSpellings()
    for (var c = 0; c < spellings.length; c++) {
      // synthetic: the run status edited to a cancelled spelling
      cases.push([spellings[c], (function(s) { return function(raw) { raw.status.run.status = s } })(spellings[c]), "cancelled", false])
    }
    for (var i = 0; i < cases.length; i++) {
      var agentRaw = amRun("status-started.json")
      cases[i][1](agentRaw)
      var agentRun = Runs.normalizeRun(agentRaw)
      compare(Runs.runState(agentRun), cases[i][2], cases[i][0] + ": the edit gives the state")
      compare(Runs.isLiveSelection(agentRun, explore), cases[i][3], cases[i][0] + ": explore.1, attempt started")

      var stepRaw = startedStepRaw("verify")
      cases[i][1](stepRaw)
      var stepRun = Runs.normalizeRun(stepRaw)
      compare(Runs.runState(stepRun), cases[i][2], cases[i][0] + ": the edit gives the state (step)")
      compare(Runs.isLiveSelection(stepRun, verifyStep), cases[i][3], cases[i][0] + ": the verify step, phase started")
    }
  }

  function test_fixture_is_live_selection_by_attempt_status() {
    var card = "2280a6ab-9c40-434b-9729-63fd1f373754"
    var explore = { card_id: card, phase: "explore", attempt: 1 }
    var statuses = [["started", true], ["ok", false], ["gate_failed", false], ["schema_invalid", false],
                    ["harness_error", false], ["", false]]
    for (var i = 0; i < statuses.length; i++) {
      var raw = amRun("status-started.json")
      var attempt = rawSubtask(raw, card).phases[1].attempts[0]
      compare(rawSubtask(raw, card).phases[1].name + "." + attempt.n, "explore.1", "the capture's explore.1")
      // synthetic: explore.1's status edited
      attempt.status = statuses[i][0]
      compare(Runs.isLiveSelection(Runs.normalizeRun(raw), explore), statuses[i][1], "attempt status '" + statuses[i][0] + "'")
    }
    var started = Runs.normalizeRun(amRun("status-started.json"))
    compare(Runs.isLiveSelection(started, { card_id: "5560d0fe-2b8e-4ef9-ad71-96b50ee89daa", phase: "review", attempt: 1 }), false,
            "a finished attempt of a running run")
    compare(Runs.isLiveSelection(started, { card_id: card, phase: "worktree", attempt: 0, step: true }), false,
            "a done step of a running run")
    var escalated = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(Runs.isLiveSelection(escalated, { card_id: "10e26d57-374c-48d3-bc45-09389b42cfac", phase: "review", attempt: 1 }), false,
            "the escalated capture's gate_failed review.1")
  }
```

Directly after the closing `}` of `test_attempt_status` (right before the `// ---- 5.3: the runs that touch one card` comment line), insert:

```qml
  function test_is_live_selection_garbage() {
    var results = []
    function live(run, sel, label) {
      var r = Runs.isLiveSelection(run, sel)
      results.push([r, label])
      return r
    }
    var run = detailRun()
    var good = { card_id: "t1", phase: "implement", attempt: 2 }
    compare(live(run, good, "baseline"), true, "the baseline selection is live")

    var badRuns = [undefined, null, "x", 5, [], {}, { tree: "x" }]
    for (var i = 0; i < badRuns.length; i++) compare(live(badRuns[i], good, "run " + i), false, "garbage run " + i)

    var badSels = [undefined, null, "x", 5, [], {},
      { card_id: "", phase: "implement", attempt: 2 }, { card_id: 7, phase: "implement", attempt: 2 },
      { card_id: null, phase: "implement", attempt: 2 }, { phase: "implement", attempt: 2 },
      { card_id: "t1", attempt: 2 }, { card_id: "t1", phase: "", attempt: 2 }, { card_id: "t1", phase: 5, attempt: 2 },
      { card_id: "t1", phase: null, attempt: 2, step: true },
      { card_id: "zz", phase: "implement", attempt: 2 }, { card_id: "zz", phase: "implement", attempt: 0, step: true },
      { card_id: "t1", phase: "verify", attempt: 2 }, { card_id: "t1", phase: "verify", attempt: 0, step: true },
      { card_id: "t1", phase: "implement", attempt: "2" }, { card_id: "t1", phase: "implement", attempt: 0 },
      { card_id: "t1", phase: "implement", attempt: -2 }, { card_id: "t1", phase: "implement", attempt: NaN },
      { card_id: "t1", phase: "implement", attempt: Infinity }, { card_id: "t1", phase: "implement" }]
    for (var j = 0; j < badSels.length; j++) compare(live(run, badSels[j], "sel " + j), false, "garbage selection " + j)

    // synthetic: bookkeeping ids carrying a started attempt and a started step
    var books = mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "integrate", phases: [{ name: "integrate", status: "started", attempts: [{ n: 1, status: "started" }] }] },
      { card_id: "bases", phases: [{ name: "bases", kind: "deterministic", status: "started", attempts: [{ n: 1, status: "started" }] }] },
      { card_id: "base-s1", phases: [{ name: "base", status: "started", attempts: [{ n: 1, status: "started" }] }] }] } })
    var ids = [["integrate", "integrate"], ["bases", "bases"], ["base-s1", "base"]]
    for (var k = 0; k < ids.length; k++) {
      compare(live(books, { card_id: ids[k][0], phase: ids[k][1], attempt: 1 }, ids[k][0]), false, ids[k][0] + " attempt")
      compare(live(books, { card_id: ids[k][0], phase: ids[k][1], attempt: 0, step: true }, ids[k][0] + " step"), false, ids[k][0] + " step")
    }

    var before = JSON.stringify(run) + JSON.stringify(good)
    live(run, good, "again")
    compare(JSON.stringify(run) + JSON.stringify(good), before, "neither argument is mutated")
    for (var r = 0; r < results.length; r++) compare(typeof results[r][0], "boolean", "a boolean: " + results[r][1])
  }

  function test_is_live_selection_step_flag() {
    // synthetic: a running run with a started agent phase, a started step and a re-run step
    var run = mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [
        { name: "spec", kind: "agent", status: "done", attempts: [{ n: 1, status: "ok" }] },
        { name: "implement", kind: "agent", status: "started", attempts: [{ n: 1, status: "gate_failed" }, { n: 2, status: "started" }] }] },
      { card_id: "t2", phases: [
        { name: "worktree", kind: "deterministic", status: "done", attempts: [] },
        { name: "verify", kind: "deterministic", status: "started", attempts: [] }] },
      { card_id: "t3", phases: [
        { name: "verify", kind: "deterministic", status: "done", attempts: [] },
        { name: "verify", kind: "deterministic", status: "started", attempts: [] }] }] } })
    var cases = [
      [{ card_id: "t1", phase: "implement", attempt: 2 }, true, "a started attempt"],
      [{ card_id: "t1", phase: "implement", attempt: 0, step: true }, true, "step: true reads the phase, which is started"],
      [{ card_id: "t1", phase: "implement", attempt: 0 }, false, "attempt 0 without step"],
      [{ card_id: "t1", phase: "implement", attempt: 2, step: "true" }, true, "step \"true\" is the agent branch"],
      [{ card_id: "t1", phase: "implement", attempt: 0, step: "true" }, false, "step \"true\" with attempt 0"],
      [{ card_id: "t1", phase: "implement", attempt: 0, step: 1 }, false, "step 1 with attempt 0"],
      [{ card_id: "t1", phase: "implement", attempt: 2, step: false, extra: "x" }, true, "step false and extra keys: the agent branch"],
      [{ card_id: "t1", phase: "implement", attempt: 1 }, false, "a gate_failed attempt of a started phase"],
      [{ card_id: "t1", phase: "spec", attempt: 0, step: true }, false, "a done phase as a step"],
      [{ card_id: "t2", phase: "verify", attempt: 0, step: true }, true, "a started step"],
      [{ card_id: "t2", phase: "verify", attempt: 5, step: true }, true, "a step selection's attempt is not read"],
      [{ card_id: "t2", phase: "verify", attempt: "x", step: true }, true, "not even a non-number"],
      [{ card_id: "t2", phase: "verify", attempt: 0 }, false, "a started step without step: true"],
      [{ card_id: "t2", phase: "worktree", attempt: 0, step: true }, false, "a done step"],
      [{ card_id: "t3", phase: "verify", attempt: 0, step: true }, false, "a repeated name reads the first phase, which is done"]
    ]
    for (var i = 0; i < cases.length; i++)
      compare(Runs.isLiveSelection(run, cases[i][0]), cases[i][1], cases[i][2])
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the domain tests (Commands).
Expected: FAIL for all four new tests with `TypeError: Property 'isLiveSelection' of object [object Object] is not a function` (or similar). `Totals: 207 passed, 4 failed`.

- [ ] **Step 3: Write the implementation**

In `core/domain/runs.js`, directly after the closing `}` of `attemptStatus` (before the `// ---- Run controls (S2 1.1)` comment line), insert:

```js

// Whether a selection is in flight: the run is running and the selection names
// a real card and a phase, and, with `step: true`, the card's first phase of
// that name is started (`attempt` is not read), else the attempt
// {card_id, phase, attempt} is started. Always a boolean.
function isLiveSelection(run, sel) {
  if (runState(run) !== "running" || !_isObject(sel)) return false
  if (!_isCardId(sel.card_id) || typeof sel.phase !== "string" || sel.phase === "") return false
  if (sel.step === true) {
    var p = _findPhase(_findByCardId(_subtasksOf(run), sel.card_id), sel.phase)
    return p !== null && p.status === "started"
  }
  return attemptStatus(run, sel.card_id, sel.phase, sel.attempt) === "started"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the domain tests. Expected: `Totals: 211 passed, 0 failed`.

- [ ] **Step 5: Run the full gate**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every `== tests/...tst_*.qml` block prints `Totals: … 0 failed`, no `TypeError`/`ReferenceError` lines, exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(domain): isLiveSelection says whether a selection is in flight in a running run"
```

---

## Spec coverage

| spec item | task |
|---|---|
| B1 step entries, shape, key order, position, own attempts after, agent entries unchanged, pending/unknown/unnamed none, `phases` unchanged, current-phase rule unchanged | Task 1 (tests 2, 3, 4, 8) |
| `kind` carried through normalization (pinned) | Task 1 (test 1) |
| `tst_run_detail_screen.qml` literals `1_0_6`→`1_0_11`, `1_0_0`→`1_0_1` | Task 1 |
| B2 started step preferred, agent unchanged and without `step` key, unnumbered agent passed over, row fallback never a step, bookkeeping null, garbage null | Task 2 (tests 5, 9; existing `test_default_attempt`) |
| B3 `isLiveSelection`: run state, selection validation, step branch via `_findPhase`, agent branch via `attemptStatus`, boolean | Task 3 (tests 6, 7, 10, 11) |
| Error paths (garbage run/sel, bookkeeping ids, bad phase, `step` truthy not `true`, missing card/phase) | Task 3 (tests 10, 11); runTree garbage: existing `test_run_tree_garbage` and test 8 |
| Pure / no mutation | tests 8, 9, 10 compare `JSON.stringify` before and after |

Note on test 4: `startedStepRaw` also sets explore's attempt 1 to `ok` (a finished agent phase's attempt), so its entries read `explore.1:ok`; the spec's "explore.1 done" names the phase's state.
<!-- task-pipeline: validated -->
