# Contract stubs and tests-first table for the Runs row redesign — design

Card: `6f9f8639` "Write contract stubs and table tests", the only subtask of story `e66a70e2`
"Contract: shared names and signatures". Parent design:
`docs/superpowers/specs/runs-screen-row-redesign-design.md`, cited below as **RR** with line
numbers.

## Purpose

Stories A–F of this milestone run in parallel after this card (A backend, B domain, C store,
D components, E theme, F wiring). They meet on a handful of names: action names, three domain
functions, and a fourth `controls()` entry. This card fixes those names and signatures in code,
as stubs that are safe to ship, and writes the expected-value table as tests that story B turns
on. After this card, every sibling can code against a function that exists and has its final
signature, and B's definition of done is a set of tests that already exist.

The card changes `core/domain/runs.js` (stubs only), `tests/core/domain/tst_runs.qml` (two
helpers), and adds `tests/core/domain/tst_run_row_contract.qml`. Nothing else.

## Inherited constraints

- `core/domain` is pure JS, no QML; the file is `.pragma library`, uses `var` and function
  declarations only, and its functions never throw and return fresh objects per call
  (RR line 21; `core/domain/runs.js` lines 1, 168-173, 1161-1163).
- `bash tests/run.sh` is green before and after (RR line 136). It fails on any `FAIL` line and on
  `TypeError`, `ReferenceError` or `is not a function` in QML test output (`tests/run.sh`).
- `tests/architecture/test_layers.py` passes (RR line 135).
- The top-level filters, their store properties and their tests are not touched (RR line 17).

## The names this card fixes

### Action names

Two vocabularies, never mixed (card description; RR lines 66-76, 84, 97, 110-116):

| Layer | Names |
|---|---|
| UI (`Runs.visibleActions`, `RunControls.actionRequested`, `RunsScreen.requestControl`) | `pause`, `resume`, `cancel`, `close`, `relaunch` |
| `Runs.controls()` keys | `pause`, `resume`, `cancel`, `close` |
| Store (`RunControlStore.control`, `refusalOf`) and backend (`run-control.py` `ACTIONS`) | `pause`, `resume`, `cancel`, `reset` |
| `Runs.controlError(error, action)` `action` argument | the store names: `pause`, `resume`, `cancel`, `reset` |

`close` (UI) is `reset` (store, backend, `am`). `relaunch` is UI only: it starts a fresh run and
has no `controls()` entry and no store control action.

A `runs.js` comment above `controls()` states this table in one paragraph, so B, C and F read it
next to the code.

### `runLevel(run)` (RR lines 39-48)

- Signature: `function runLevel(run)`, returns exactly one of `"subtask"`, `"story"`,
  `"milestone"`.
- **Stub (this card):** returns `"milestone"` for every input.
- Final behavior (story B; tested here, skipped until B): see the table below.
- Never throws, for any input including `undefined`, `null`, numbers, strings, arrays and
  `Object.create(null)`.

### `controls(run).close` (RR lines 87-89)

- `controls(run)` returns exactly four keys: `pause`, `resume`, `cancel`, `close`; each a fresh
  `{enabled, reason}`, `enabled === (reason === "")`, no object shared between entries or calls.
- **Stub (this card):** `close` is `{enabled: false, reason: "The run's state is unknown"}`
  (`_REASON_UNKNOWN`) for every input. Pause, resume and cancel are unchanged.
- Final behavior (story B): see the table below.

### `visibleActions(run)` (RR lines 68-76, 90)

- Signature: `function visibleActions(run)`, returns a fresh array of UI action names, left to
  right as rendered. Every element is one of `pause`, `resume`, `cancel`, `close`, `relaunch`; no
  duplicates.
- **Stub (this card):** returns a fresh `[]` for every input.
- Final behavior (story B): see the table below.

### `controlError(error, action)` (RR lines 91-93)

- Signature becomes `function controlError(error, action)`. `action` is optional; a missing,
  non-string or unrecognised `action` behaves exactly like today's one-argument call.
- **Stub (this card):** `action` is accepted and ignored. Every current result is unchanged, so
  the existing `test_control_error_*` tests pass untouched.
- Final behavior (story B): see the table below. Story C passes the request's action from
  `RunControlStore` (today `core/stores/RunControlStore.qml:207` calls `controlError(envelope)`).

## The table (final behavior, owned by story B)

States are `Runs.runState(run)` values. "Integrate" means `_inIntegrate(run)` (a lease object
whose `accepting !== true`). The state's reason wins over Integrate's, as for the existing
controls (`runs.js` lines 1182-1187).

### `controls(run).close` and `visibleActions(run)`

| State | Integrate | `close.reason` (`""` = enabled) | `visibleActions` |
|---|---|---|---|
| running | no | `A running run is cancelled, not closed` | `["cancel", "pause"]` |
| running | yes | `A running run is cancelled, not closed` | `[]` |
| parked | no | `""` | `["close", "resume"]` |
| parked | yes | `Integrate is running; it cannot be paused or cancelled` | `["resume"]` |
| escalated | no | `""` | `["close", "relaunch"]` |
| escalated | yes | `Integrate is running; it cannot be paused or cancelled` | `["relaunch"]` |
| escalated card run (`workflow` trimmed `"task"`) | no | `""` | `["close", "relaunch"]` |
| dead | no | `""` | `["close", "relaunch"]` |
| dead | yes | `Integrate is running; it cannot be paused or cancelled` | `["relaunch"]` |
| done | any | `The run has finished` | `[]` |
| cancelled (`cancelled` or `canceled`) | any | `The run is already cancelled` | `[]` |
| unknown (`""`, `"weird"`, `"STARTED"`, `undefined`, `null`, `5`, `"x"`, `{}`, `[]`, `Object.create(null)`) | any | `The run's state is unknown` | `[]` |

Rule behind the `visibleActions` column: take the state's list from RR's button table
(RR lines 68-74: running → cancel, pause; parked → close, resume; escalated and dead → close,
relaunch; anything else → none), then drop every entry that has a `controls(run)` entry whose
`enabled` is false. `relaunch` has no `controls()` entry and is never dropped. This is RR line 76
("a button that would be disabled is not rendered") applied to Integrate, which RR's table does
not show. The result never contains a disabled action, so the row never shows a disabled button.

Resume never appears on an escalated or dead run, even when `controls().resume` is enabled
(RR line 76).

### `runLevel(run)`

| Input | Result |
|---|---|
| `{workflow: "task"}`, also `"  task  "`, `"\ttask\n"` | `subtask` |
| `{workflow: "task", story_id: "s1"}` | `subtask` (workflow wins) |
| `{workflow: "milestone", story_id: "s1"}`, `{story_id: "s1"}` | `story` |
| `{story_id: "__proto__"}`, `{story_id: "constructor"}` | `story` |
| `{story_id: ""}`, `{story_id: "   "}`, `{story_id: null}`, `{story_id: 5}` | `milestone` |
| `{workflow: "Task"}`, `{workflow: "tasks"}`, `{workflow: "story"}` | `milestone` (case-sensitive, exact; only `story_id` makes a story, never the `workflow` string) |
| `{}`, `undefined`, `null`, `5`, `"task"`, `[]`, `Object.create(null)` | `milestone` |
| a prototype-less object with `workflow: "task"` | `subtask` |
| each `tests/fixtures/am/runs.json` row, normalised (`workflow: "milestone"`; `normalizeRun` gives `story_id: ""` for the fixtures' `null`) | `milestone` |
| a normalised run built with `story_id: "s1"` (synthetic: no fixture has one) | `story` |

A `story_id` counts only when it is a string that is non-empty after trimming.

### `controlError(error, action)`

| `error.type` | `action` | Sentence |
|---|---|---|
| `NotResettableError` | any, or missing | `This run cannot be closed (it is finished or already cancelled).` |
| `RunIsLiveError` | `reset` (also `"  reset  "` trimmed) | `Another am process is still driving this run. Pause it first.` |
| `RunIsLiveError` | `pause`, `resume`, `cancel`, missing, `"close"`, `5` | today's sentence: `Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died.` |
| any other known type | any | unchanged from today |

`NotResettableError` is a tenth entry in `_CONTROL_ERRORS`; B also updates
`test_control_error_table`'s count and rows in `tst_runs.qml`. `offersRelaunch` is unchanged:
`NotResettableError` does not offer relaunch.

## Tests

All QML tests run under `bash tests/run.sh` (qmltestrunner). Domain tests are QML `TestCase`
files importing `runs.js`, because that is the only harness that loads a `.pragma library` file
(tier: domain unit, `tests/core/domain/`).

### Changes to `tests/core/domain/tst_runs.qml` (always on)

- `checkControls(c, pause, resume, cancel, label)` keeps its signature. It asserts the keys are
  exactly `cancel,close,pause,resume` and that `c.close` is a well-formed action (keys exactly
  `enabled,reason`, `reason` a string, `enabled === (reason === "")`), without fixing its value.
  Every existing caller keeps passing, with the stub and with B's implementation. Tier: domain
  unit; it is the existing controls suite.
- `test_controls_shape` additionally asserts `close` is fresh per call and not shared with
  `pause`, `resume` or `cancel`, and that mutating an earlier result's `close` does not change a
  later one.

### New `tests/core/domain/tst_run_row_contract.qml`

One `TestCase` named `DomainRunRowContract`, importing `runs.js`, `amFixtures.js` as `F` and,
for fixture runs, the same `amRun` construction `tst_runs.qml` uses (copied, since QML test files
share no helpers beyond `tests/helpers/*.js`).

Contract tests (always on, pass against the stubs; tier: domain unit, because they pin the
signatures every sibling compiles against):

1. `test_contract_run_level_signature`: `typeof Runs.runLevel === "function"`; for every input in
   the garbage list (`undefined`, `null`, `5`, `"x"`, `true`, `{}`, `[]`, `Object.create(null)`,
   `{workflow: {}}`, `{story_id: {}}`, a run from a fixture) it returns one of the three level
   strings without throwing.
2. `test_contract_visible_actions_signature`: `typeof Runs.visibleActions === "function"`; for
   every run in the state list and the garbage list it returns an array (`Array.isArray`), fresh
   per call (two calls give `!==` arrays; pushing onto one does not
   change the next), every element in the five UI names, no duplicates.
3. `test_contract_controls_close_present`: for every run in the state list and the garbage list,
   `controls(run)` has exactly the keys `cancel,close,pause,resume`, `close` is a well-formed
   action, and `close` is fresh per call.
4. `test_contract_control_error_action_arg`: for every row of today's `controlErrorTable` (the
   nine types) and each of `undefined`, `"pause"`, `"resume"`, `"cancel"`, `5`, `null`,
   `controlError(envelope, action)` equals `controlError(envelope)`; no throw. (`"reset"` is
   excluded here because B changes it for `RunIsLiveError`.)
5. `test_contract_action_vocabulary`: the test file's own `uiActions` list is exactly
   `pause,resume,cancel,close,relaunch` and its `storeActions` list is exactly
   `pause,resume,cancel,reset`; every name in `visibleActions` output (any run) is in
   `uiActions`; every `controls()` key is in `uiActions` and is not `relaunch`. Tier: domain unit;
   it is the written-down contract other stories read.

Table tests (written now, skipped until story B; tier: domain unit, the expected-value table
above, one test per table):

- A `readonly property bool domainImplemented: false` at the top of the `TestCase`, with a
  comment: "Story B (runs.js domain) sets this to true; the table tests below are its definition
  of done." Each table test starts with
  `if (!domainImplemented) skip("runs.js domain not implemented yet (story B)")`.
6. `test_table_controls_close`: every row of the `controls(run).close` table, including both
   `cancelled` spellings, the Integrate rows, the escalated card run, all unknown inputs, and a
   normalised fixture run per state the fixtures provide.
7. `test_table_visible_actions`: every row of the `visibleActions` column, exact arrays compared
   with `join(",")`, plus "never contains an action whose `controls(run)` entry is disabled" over
   every run in the state and garbage lists.
8. `test_table_run_level`: every row of the `runLevel` table.
9. `test_table_control_error_reset`: every row of the `controlError` table.

Red check for the table (done once while implementing this card, not committed): set
`domainImplemented: true`, run `bash tests/run.sh tst_run_row_contract`, and confirm tests 6-9 FAIL
against the stubs (and 1-5 still pass); then set it back to `false`. This proves the table tests
are not vacuous before B relies on them.

### Not tested here

- Backend `reset` argv, `--verify` rejection, Usage text: story A
  (`tests/core/backend/runs/test_run_control.py`).
- Store `control("reset")`, `refusalOf("reset")`, close dialog state: story C.
- Components, theme, wiring, RunDetailScreen behaviour: stories D, E, F.

## Error paths

- Any input to the three stubs and to `controlError(error, action)` returns a value of the stated
  type; none throws. A `__proto__` or `constructor` value in `workflow`, `story_id` or `action` is
  an ordinary string.
- `RunControls.qml`, `RunControlStore.qml` and `RunDetailScreen.qml` keep working unchanged: they
  read `controls().pause/resume/cancel` only, and `controlError` with one argument still returns
  today's sentences. No UI shows `close` or calls the new functions in this card.

## Out of scope

- Real implementations of `runLevel`, `controls().close`, `visibleActions` and the reset
  sentences in `controlError`, plus the `_CONTROL_ERRORS` / `test_control_error_table` update —
  story B (`042b0d8e`).
- `run-control.py` `ACTIONS`, `USAGE`, docstring and its Python tests — story A (`cc7f1fd6`).
- `RunControlStore` (`reset` acceptance, `refusalOf` mapping `reset` → `controls().close`, close
  confirm fields, passing `action` to `controlError`) and `ControlFacts.pendingOf` docs — story C
  (`19aa24c1`).
- `RunLevelBadge`, `RunStateBadge`, `CloseRunDialog` — story D (`7997c2cf`).
- Theme tokens and `ActionButton` tones — story E (`8c7324d3`).
- `RunControls`, `RunRow`, `RunsScreen`, `Panel`/`App` wiring and `RunDetailScreen` test updates
  — story F (`8e2ec6be`).
- RR's open questions (id length, RR line 146; RunDetailScreen inclusion, RR line 147) are not
  decided here.
