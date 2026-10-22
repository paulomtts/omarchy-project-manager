# Implement runLevel, close control, visibleActions and reset errors — design

Card: `ad1501fd` "Implement runLevel, close control, visibleActions, errors + tests", the domain
subtask of story `042b0d8e` (story B, `core/domain/runs.js`).

Parent designs, cited by section and line:

- **RR**: `docs/superpowers/specs/runs-screen-row-redesign-design.md`.
- **CS**: `docs/superpowers/specs/write-contract-stubs-6f9f8639.md` (card `6f9f8639`), which fixed
  the names and signatures as stubs and wrote the expected-value tables as skipped tests. Its
  section "The table (final behavior, owned by story B)" (CS lines 83-144) is this card's
  definition of done.

## Purpose

Today `runs.js` ships four stubs: `controls(run).close` is always disabled with the unknown-state
reason, `runLevel(run)` is always `"milestone"`, `visibleActions(run)` is always `[]`, and
`controlError(error, action)` ignores `action`. This card replaces them with the behavior CS's
table fixes, and turns on the table tests CS left skipped. After this card, stories C (store) and
F (wiring) can rely on the real answers.

## Inherited constraints

- `core/domain` is pure JS with no QML (RR line 21). `runs.js` is `.pragma library`, ES5: `var`
  and function declarations only, no `let`/`const`/arrow functions; functions never throw and
  return fresh objects and arrays per call (CS lines 22-24).
- `bash tests/run.sh` is green after the change (RR line 136; CS line 25). It fails on any `FAIL`
  line and on `TypeError`, `ReferenceError` or `is not a function` in QML test output.
- `tests/architecture/test_layers.py` passes (RR line 135).
- The state's reason wins over Integrate's, as for the existing controls (CS lines 86-88;
  `core/domain/runs.js` comment above `controls()`).
- "Integrate" means `_inIntegrate(run)`: a lease object whose `accepting !== true` (CS lines 86-87).
- Comparisons on `type`, `action`, `workflow` and `story_id` are `===` on strings (or a linear
  scan), so `__proto__` and `constructor` are ordinary strings (CS lines 223-224).
- The two action vocabularies are never mixed: UI `close` is store/backend `reset`; `relaunch` is
  UI only and has no `controls()` entry (CS lines 32-47).

## Behavior

### `controls(run).close` (RR lines 87-89; CS lines 89-104)

`controls(run)` still returns exactly `pause`, `resume`, `cancel`, `close`, each a fresh
`{enabled, reason}` with `enabled === (reason === "")`. Pause, resume and cancel do not change.
`close.reason` by `runState(run)`:

| State | Integrate | `close.reason` |
|---|---|---|
| running | either | `A running run is cancelled, not closed` |
| parked, escalated, dead | no | `""` (enabled) |
| parked, escalated, dead | yes | `Integrate is running; it cannot be paused or cancelled` |
| done | either | `The run has finished` |
| cancelled (`cancelled` or `canceled`) | either | `The run is already cancelled` |
| anything else, including garbage input | either | `The run's state is unknown` |

An escalated card run (`workflow` trimmed `"task"`) has close enabled outside Integrate: unlike
resume, close does not care about the card-run case (CS line 98).

The running reason is a new named constant next to the other `_REASON_*` constants; the others
reuse `_REASON_INTEGRATE`, `_REASON_FINISHED`, `_REASON_CANCEL_CANCELLED` and `_REASON_UNKNOWN`.

### `visibleActions(run)` (RR lines 66-76, 90; CS lines 89-115)

Returns a fresh array, left to right as rendered:

1. Take the state's list: running → `cancel, pause`; parked → `close, resume`; escalated and
   dead → `close, relaunch`; anything else → none (RR lines 68-74).
2. Drop every entry whose `controls(run)` entry has `enabled === false`. `relaunch` has no
   `controls()` entry and is never dropped.

Resulting table (CS lines 91-104):

| State | Integrate | `visibleActions` |
|---|---|---|
| running | no | `["cancel", "pause"]` |
| running | yes | `[]` |
| parked | no | `["close", "resume"]` |
| parked | yes | `["resume"]` |
| escalated (incl. card run) | no | `["close", "relaunch"]` |
| escalated, dead | yes | `["relaunch"]` |
| dead | no | `["close", "relaunch"]` |
| done, cancelled, unknown, garbage | either | `[]` |

Resume never appears on escalated or dead runs even when `controls().resume` is enabled
(RR line 76). The result never holds a disabled action and never a duplicate. `controls(run)` is
computed once per call.

### `runLevel(run)` (RR lines 37-48; CS lines 49-56, 116-131)

- `run` not an object (`_isObject` false: `undefined`, `null`, numbers, strings, arrays) →
  `"milestone"`.
- `run.workflow`, read the way `controls()` reads it (`_textOf`: String-coerced and trimmed),
  is exactly `"task"` → `"subtask"`. Case-sensitive: `"Task"`, `"tasks"`, `"story"` do not match.
  Workflow wins over `story_id`.
- Else `typeof run.story_id === "string"` and it is non-empty after trimming → `"story"`.
  A number, `null`, an object, `""` or whitespace is not a story id (`{story_id: 5}` →
  `"milestone"`; `_textOf` must not be used for `story_id`, since it would turn `5` into `"5"`).
- Else `"milestone"`.
- Works on prototype-less objects (`Object.create(null)` with `workflow: "task"` → `"subtask"`).
- Every normalised fixture run in `tests/fixtures/am/runs.json` is `"milestone"` (`normalizeRun`
  gives `story_id: ""` for the fixtures' `null`; CS line 128).

### `controlError(error, action)` (RR lines 91-93; CS lines 74-81, 133-144)

- `_CONTROL_ERRORS` gains a tenth entry, appended last:
  `NotResettableError` → `This run cannot be closed (it is finished or already cancelled).`,
  for any `action`, missing included, envelope or bare, type trimmed, case-sensitive — the same
  reading as the other nine.
- `RunIsLiveError` with `action` a string that is `"reset"` after trimming →
  `Another am process is still driving this run. Pause it first.`
- `RunIsLiveError` with any other `action` (`pause`, `resume`, `cancel`, `close`, missing,
  `null`, `5`, `{}`, `"__proto__"`, `"constructor"`, `"Reset"`) → today's sentence, unchanged.
- Every other type, known or unknown, and every non-error input → exactly today's result for
  every `action`.
- `offersRelaunch` is unchanged: `NotResettableError` does not offer relaunch.

### Comments

The doc comments above `controls()`, `runLevel()`, `visibleActions()` and `controlError()` stop
saying "stub until story B" / "accepted and ignored" and describe the real behavior, in the file's
existing voice.

## Error paths

- No input to `controls`, `runLevel`, `visibleActions` or `controlError` throws; each returns its
  stated type (CS lines 223-224).
- `RunControlStore.qml:207` still calls `controlError(envelope)` with one argument and keeps
  getting today's sentences (story C adds the argument). `RunControls.qml` and
  `RunDetailScreen.qml` read only `pause/resume/cancel` and are unaffected.

## Tests

All tests are domain unit tests: QML `TestCase` files under `tests/core/domain/`, run by
`bash tests/run.sh` (qmltestrunner), because that is the only harness that loads a
`.pragma library` file (CS lines 146-150).

### `tests/core/domain/tst_run_row_contract.qml`

- Flip `readonly property bool domainImplemented` from `false` to `true` (line 16). This turns on
  the four table tests that are this card's definition of done, unchanged:
  1. `test_table_controls_close` — every `close.reason` row above, both cancelled spellings,
     Integrate rows, the escalated card run, all unknown inputs, normalised fixture runs.
  2. `test_table_visible_actions` — every `visibleActions` row as an exact `join(",")`, plus "no
     action whose `controls(run)` entry is disabled" over every state and garbage run.
  3. `test_table_run_level` — every `runLevel` row.
  4. `test_table_control_error_reset` — the `NotResettableError` and `RunIsLiveError`/`reset`
     rows.
- Update the comment on the flag and the file header so they no longer describe stubs.
- The five `test_contract_*` tests stay as they are and keep passing. In particular
  `test_contract_control_error_action_arg` keeps its own nine-row table and excludes `"reset"`,
  so it still holds.

Red check: before touching `runs.js`, flip the flag alone and run
`bash tests/run.sh tst_run_row_contract`; tests 1-4 FAIL against the stubs. Then implement.

### `tests/core/domain/tst_runs.qml` (always on)

5. `test_control_error_table`: `controlErrorTable()` gains the `NotResettableError` row (appended
   last, so `test_offers_relaunch_agrees_with_control_error`'s indices 5 and 6 stay the relaunch
   sentences) and the count becomes `10`. `test_control_error_shapes` and
   `test_offers_relaunch_agrees_with_control_error` iterate that table, so the new type gets
   envelope, bare, no-message and "does not offer relaunch" coverage without further edits.
   Tier: domain unit; it is the existing error-sentence suite.
6. New `test_control_error_reset_action`: `RunIsLiveError` with `"reset"` and `"  reset  "` gives
   the reset sentence, envelope and bare; with `"Reset"`, `"close"`, `"pause"`, `undefined`,
   `null`, `5`, `{}`, `["reset"]`, `"__proto__"` and `"constructor"` gives today's sentence;
   `NotResettableError` and `ClaimedError` give the same sentence with and without `"reset"`.
   Tier: domain unit; pins the per-action lookup at its edges (non-string, case, array).
7. New `test_controls_close_by_state`: using the existing `ctlRun` / `ctlRunOf` helpers and `ctl*` constants
   (adding `ctlCloseRunning`), assert `close.reason` for running, parked, escalated, escalated
   card run, dead, done, both cancelled spellings and unknown, with and without Integrate.
   Tier: domain unit; keeps the close column next to the pause/resume/cancel tests it mirrors.
8. New `test_run_level_edges`: `{workflow: ["task"]}` → `"subtask"` (matches how `controls()`
   reads workflow); `{workflow: {}}`, `{story_id: {}}`, `{story_id: ["s1"]}`, `{story_id: true}`
   → `"milestone"`; `{story_id: " s1 "}` → `"story"`; results never throw. Tier: domain unit;
   input shapes the CS table does not list.
9. New `test_visible_actions_fresh`: for a parked run, two calls give `!==` arrays and pushing
   onto the first does not change the second; mutating `controls(run)` results between calls does
   not change `visibleActions`. Tier: domain unit; the never-shared-result rule.

### Not tested here

- `run-control.py reset` — story A.
- `RunControlStore` `reset`, `refusalOf("reset")`, close dialog state, passing `action` to
  `controlError` — story C.
- `RunLevelBadge`, `RunStateBadge`, `CloseRunDialog` — story D. Theme tones — story E.
  `RunControls`, `RunRow`, `RunsScreen`, `Panel`/`App` wiring — story F.

## Handoff to the planner

### Global Constraints

- `core/domain/runs.js` stays `.pragma library`, ES5 (`var`, function declarations), 2-space
  indent, no semicolons, `//` comment block above each function.
- Exact strings: `A running run is cancelled, not closed`;
  `This run cannot be closed (it is finished or already cancelled).`;
  `Another am process is still driving this run. Pause it first.`
- `bash tests/run.sh` green; `tests/architecture/test_layers.py` passes.
- Commit style: `feat(runs): ...`, `test(runs): ...`.
- Touch only `core/domain/runs.js`, `tests/core/domain/tst_run_row_contract.qml`,
  `tests/core/domain/tst_runs.qml`.

### Review Focus

1. `action` that is not a string (`5`, `{}`, `["reset"]`) or differs in case (`"Reset"`): must
   give today's `RunIsLiveError` sentence, never the reset one, never a throw (test 6).
2. `story_id` that is a non-string (`5`, `true`, `{}`, `["s1"]`): must be `"milestone"`, not
   `"story"` via coercion (test 8).
3. Escalated card run in and out of Integrate: close follows Integrate only, while resume stays
   disabled; `visibleActions` must still show `relaunch` (tests 1, 2, 7).
4. Appending `NotResettableError` anywhere but last would shift `controlErrorTable()[5]`/`[6]` and
   silently weaken `test_offers_relaunch_agrees_with_control_error` (test 5).
5. Fresh results: `visibleActions` must not return a shared array or one tied to a cached
   `controls()` result (test 9).

## Out of scope

- `run-control.py` `ACTIONS`, `USAGE`, docstring, Python tests — story A (`cc7f1fd6`).
- `RunControlStore` changes, including `RunControlStore.qml:207` passing `action` — story C
  (`19aa24c1`).
- New components — story D (`7997c2cf`); theme tokens and `ActionButton` tones — story E
  (`8c7324d3`); `RunControls`/`RunRow`/`RunsScreen`/`RunDetailScreen` wiring — story F
  (`8e2ec6be`).
- The top-level filters and their tests (RR line 17).
- RR's open questions (RR lines 146-147).
