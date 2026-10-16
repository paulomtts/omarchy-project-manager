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

---

# runLevel, close control, visibleActions and reset errors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four stubs in `core/domain/runs.js` (`controls(run).close`, `visibleActions`, `runLevel`, `controlError`'s `action`) with their real behavior, and turn on the table tests in `tst_run_row_contract.qml` that define "done".

**Architecture:** Five tasks, one function per task, each with its own red/green cycle in `tests/core/domain/tst_runs.qml`. (1) `controls().close` (plus a one-off red check that the contract table tests fail against the stubs). (2) `visibleActions`, which reads `controls()`. (3) `runLevel`. (4) `controlError`'s `NotResettableError` entry and `RunIsLiveError`-on-`reset` sentence. (5) Flip `domainImplemented` to `true` in `tst_run_row_contract.qml` and run the whole gate.

**Tech Stack:** Qt 6 QML / JavaScript (`.pragma library`, ES5: `var` and function declarations only), QtTest `TestCase` run by `qmltestrunner`. The gate is `bash tests/run.sh` (pytest over `tests/`, then every `tst_*.qml`; it fails on any `FAIL` line and on `TypeError`, `ReferenceError` or `is not a function` in QML output).

**Spec:** `docs/superpowers/specs/implement-runlevel-ad1501fd.md` (prepended above). Parent designs: `docs/superpowers/specs/runs-screen-row-redesign-design.md` (RR) and `docs/superpowers/specs/write-contract-stubs-6f9f8639.md` (CS).

**Worktree / branch:** run every command from the worktree root
`/home/mtts/Code/omarchy-project-manager/.claude/worktrees/runs-row-v5/task-implement-runlevel-ad1501fd`
(branch `runs-row-v5/task-implement-runlevel-ad1501fd`). Every path below is relative to it.

**How to run one QML test file:** `timeout 600 bash tests/run.sh <substring>` runs the whole pytest suite first (a few minutes), then only the QML files whose path contains `<substring>`. It prints `== <path>`, any `FAIL` lines with their `   Loc` lines, and a `Totals:` line per file; exit status 0 means green. Use `core/domain/tst_runs.qml` as the substring for `tst_runs.qml` (a bare `tst_runs` would also match `tests/ui/tst_runs_flow.qml` and others). For a fast inner loop, run one file directly; this also prints `SKIP` lines and the actual/expected values of each failure:
`QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
(substitute `tst_run_row_contract.qml` as needed). Each task's final check still uses `bash tests/run.sh`.

## Global Constraints

- `core/domain/runs.js` stays `.pragma library`, ES5 (`var`, function declarations; no `let`, `const` or arrow functions), 2-space indent, no semicolons, a `//` comment block above each function.
- Functions never throw and return fresh objects and arrays per call.
- Exact strings: `A running run is cancelled, not closed`; `This run cannot be closed (it is finished or already cancelled).`; `Another am process is still driving this run. Pause it first.`
- The state's reason wins over Integrate's. "Integrate" means `_inIntegrate(run)`.
- Comparisons on `type`, `action`, `workflow` and `story_id` are `===` on strings (or a linear scan), so `__proto__` and `constructor` are ordinary strings.
- The two action vocabularies are never mixed: UI `close` is store/backend `reset`; `relaunch` is UI only and has no `controls()` entry.
- `bash tests/run.sh` green; `tests/architecture/test_layers.py` passes.
- Commit style: `feat(runs): ...`, `test(runs): ...`.
- Touch only `core/domain/runs.js`, `tests/core/domain/tst_run_row_contract.qml`, `tests/core/domain/tst_runs.qml`.

## Review Focus

1. **`action` that is not a string (`5`, `{}`, `["reset"]`) or differs in case (`"Reset"`)** — must give today's `RunIsLiveError` sentence, never the reset one, never a throw. `String(["reset"])` is `"reset"`, so a `_textOf(action)` reading would be wrong; the code checks `typeof action === "string"`. Pinned by Task 4's `test_control_error_reset_action`.
2. **`story_id` that is a non-string (`5`, `true`, `{}`, `["s1"]`)** — must be `"milestone"`, not `"story"` via coercion. Pinned by Task 3's `test_run_level_edges`.
3. **Escalated card run in and out of Integrate** — close follows Integrate only while resume stays disabled; `visibleActions` still shows `relaunch`. Pinned by Task 1's `test_controls_close_by_state` and Task 5's `test_table_controls_close` / `test_table_visible_actions`.
4. **Appending `NotResettableError` anywhere but last** — would shift `controlErrorTable()[5]`/`[6]` and silently weaken `test_offers_relaunch_agrees_with_control_error`. Pinned by Task 4, which appends it last in both `_CONTROL_ERRORS` and `controlErrorTable()`, and whose `test_control_error_table` compares each row in order.
5. **Fresh results** — `visibleActions` must not return a shared array or one tied to a cached `controls()` result. Pinned by Task 2's `test_visible_actions_fresh`.

---

### Task 1: `controls(run).close`

**Files:**
- Modify: `core/domain/runs.js:1165-1223` (the `_REASON_*` constants, the comment above `controls()`, and its body)
- Test: `tests/core/domain/tst_runs.qml:2762-2809` (the `ctl*` constants and `checkControls` comment), and a new test after `test_controls_escalated_card_run_fresh` (ends near line 2984)

**Interfaces:**
- Consumes: `runState(run)`, `_inIntegrate(run)`, `_action(reason)`, `_REASON_INTEGRATE`, `_REASON_FINISHED`, `_REASON_CANCEL_CANCELLED`, `_REASON_UNKNOWN` (all in `runs.js`); test helpers `ctlRun(status, live, accepting)`, `ctlRunOf(status, live, accepting, workflow)`, `checkAction(a, reason, label)` (all in `tst_runs.qml`).
- Produces: `controls(run).close` is a fresh `{enabled, reason}` with the reasons in the spec's close table. New `runs.js` constant `_REASON_CLOSE_RUNNING`. New `tst_runs.qml` property `ctlCloseRunning`. Task 2's `visibleActions` reads `controls(run).close.enabled`.

- [ ] **Step 1: Red check of the contract table tests (not committed)**

In `tests/core/domain/tst_run_row_contract.qml` line 16, change

```qml
  readonly property bool domainImplemented: false
```

to

```qml
  readonly property bool domainImplemented: true
```

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_run_row_contract.qml`
Expected: exactly four `FAIL!` lines, for `test_table_controls_close`, `test_table_visible_actions`, `test_table_run_level` and `test_table_control_error_reset`; the five `test_contract_*` tests PASS.

Then restore the file:

```bash
git checkout -- tests/core/domain/tst_run_row_contract.qml
git status --short   # must not list tst_run_row_contract.qml
```

- [ ] **Step 2: Write the failing test**

In `tests/core/domain/tst_runs.qml`, after the line

```qml
  readonly property string ctlResumeEscalatedCard: "An escalated card run cannot be resumed; relaunch it"
```

add

```qml
  readonly property string ctlCloseRunning: "A running run is cancelled, not closed"
```

Replace the comment above `checkControls`:

```qml
  // A whole controls() result; "" means that action is enabled. `close` must be
  // present and well formed; its value belongs to the Runs row redesign's own
  // tests (tst_run_row_contract.qml).
```

with

```qml
  // A whole controls() result; "" means that action is enabled. `close` must be
  // present and well formed; its value is pinned by test_controls_close_by_state
  // and by the Runs row redesign's own tests (tst_run_row_contract.qml).
```

Then insert this test immediately after the closing `}` of `test_controls_escalated_card_run_fresh` (before the comment `// [type, sentence] for every am control error controlError knows.`):

```qml

  function test_controls_close_by_state() {
    // [label, run, close reason ("" = enabled)]
    var cases = [
      ["running", ctlRun("started", true, true), ctlCloseRunning],
      ["running, Integrate", ctlRun("started", true, false), ctlCloseRunning],
      ["parked", ctlRun("stopped", false, true), ""],
      ["parked, no lease", ctlRun("stopped", null, false), ""],
      ["parked, Integrate", ctlRun("stopped", false, false), ctlIntegrate],
      ["escalated", ctlRun("escalated", false, true), ""],
      ["escalated, no lease", ctlRun("escalated", null, false), ""],
      ["escalated, Integrate", ctlRun("escalated", false, false), ctlIntegrate],
      ["escalated card run", ctlRunOf("escalated", false, true, "task"), ""],
      ["escalated card run, no lease", ctlRunOf("escalated", null, false, "task"), ""],
      ["escalated card run, Integrate", ctlRunOf("escalated", false, false, "task"), ctlIntegrate],
      ["dead", ctlRun("started", false, true), ""],
      ["dead, no lease", ctlRun("started", null, false), ""],
      ["dead, Integrate", ctlRun("started", false, false), ctlIntegrate],
      ["done", ctlRun("done", false, true), ctlFinished],
      ["done, Integrate", ctlRun("done", false, false), ctlFinished],
      ["done, live, Integrate", ctlRun("done", true, false), ctlFinished],
      ["cancelled", ctlRun("cancelled", false, true), ctlCancelCancelled],
      ["cancelled, Integrate", ctlRun("cancelled", false, false), ctlCancelCancelled],
      ["canceled, no lease", ctlRun("canceled", null, true), ctlCancelCancelled],
      ["canceled, live, Integrate", ctlRun("canceled", true, false), ctlCancelCancelled],
      ["unknown", ctlRun("weird", true, true), ctlUnknown],
      ["unknown, Integrate", ctlRun("weird", true, false), ctlUnknown],
      ["undefined", undefined, ctlUnknown],
      ["null", null, ctlUnknown],
      ["{}", {}, ctlUnknown]
    ]
    for (var i = 0; i < cases.length; i++)
      checkAction(Runs.controls(cases[i][1]).close, cases[i][2], cases[i][0] + " close")
    // Close does not care about the card-run case; resume still does.
    var card = Runs.controls(ctlRunOf("escalated", false, true, "task"))
    checkAction(card.resume, ctlResumeEscalatedCard, "escalated card run resume")
    checkAction(card.close, "", "escalated card run close")
  }
```

- [ ] **Step 3: Run test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: one `FAIL!  : qmltestrunner::DomainRuns::test_controls_close_by_state()` line, first at `running close enabled` or `running close reason` (the stub gives `The run's state is unknown`); every other test passes.

- [ ] **Step 4: Write minimal implementation**

In `core/domain/runs.js`, after

```js
var _REASON_CANCEL_CANCELLED = "The run is already cancelled"
```

add

```js
var _REASON_CLOSE_RUNNING = "A running run is cancelled, not closed"
```

Replace the first paragraph of the comment above `controls()`:

```js
// {pause, resume, cancel, close}, each a fresh {enabled, reason}; reason is ""
// when enabled. Pause needs a running run outside Integrate; resume needs dead,
// parked or escalated, except an escalated card run (workflow "task", trimmed),
// and never looks at accepting; cancel needs a run that has not finished and is
// not in Integrate. The state's reason wins over Integrate's. Close is a stub
// until story B (042b0d8e): always disabled with the unknown-state reason.
```

with

```js
// {pause, resume, cancel, close}, each a fresh {enabled, reason}; reason is ""
// when enabled. Pause needs a running run outside Integrate; resume needs dead,
// parked or escalated, except an escalated card run (workflow "task", trimmed),
// and never looks at accepting; cancel needs a run that has not finished and is
// not in Integrate; close needs dead, parked or escalated, escalated card runs
// included, outside Integrate (a running run is cancelled, not closed). The
// state's reason wins over Integrate's.
```

(The second paragraph, "Action names come in two vocabularies ...", stays as it is.)

Replace the body of `controls()`:

```js
function controls(run) {
  var state = runState(run)
  var integrate = _inIntegrate(run)
  var pause, resume, cancel
  if (state === "running") {
    pause = integrate ? _REASON_INTEGRATE : ""
    resume = _REASON_RESUME_RUNNING
    cancel = integrate ? _REASON_INTEGRATE : ""
  } else if (state === "dead" || state === "parked" || state === "escalated") {
    pause = _REASON_PAUSE_NOT_RUNNING
    resume = state === "escalated" && _textOf(run.workflow) === "task" ? _REASON_RESUME_ESCALATED_CARD : ""
    cancel = integrate ? _REASON_INTEGRATE : ""
  } else if (state === "cancelled") {
    pause = _REASON_FINISHED
    resume = _REASON_RESUME_CANCELLED
    cancel = _REASON_CANCEL_CANCELLED
  } else if (state === "done") {
    pause = _REASON_FINISHED
    resume = _REASON_FINISHED
    cancel = _REASON_FINISHED
  } else {
    pause = _REASON_UNKNOWN
    resume = _REASON_UNKNOWN
    cancel = _REASON_UNKNOWN
  }
  return { pause: _action(pause), resume: _action(resume), cancel: _action(cancel), close: _action(_REASON_UNKNOWN) }
}
```

with

```js
function controls(run) {
  var state = runState(run)
  var integrate = _inIntegrate(run)
  var pause, resume, cancel, close
  if (state === "running") {
    pause = integrate ? _REASON_INTEGRATE : ""
    resume = _REASON_RESUME_RUNNING
    cancel = integrate ? _REASON_INTEGRATE : ""
    close = _REASON_CLOSE_RUNNING
  } else if (state === "dead" || state === "parked" || state === "escalated") {
    pause = _REASON_PAUSE_NOT_RUNNING
    resume = state === "escalated" && _textOf(run.workflow) === "task" ? _REASON_RESUME_ESCALATED_CARD : ""
    cancel = integrate ? _REASON_INTEGRATE : ""
    close = integrate ? _REASON_INTEGRATE : ""
  } else if (state === "cancelled") {
    pause = _REASON_FINISHED
    resume = _REASON_RESUME_CANCELLED
    cancel = _REASON_CANCEL_CANCELLED
    close = _REASON_CANCEL_CANCELLED
  } else if (state === "done") {
    pause = _REASON_FINISHED
    resume = _REASON_FINISHED
    cancel = _REASON_FINISHED
    close = _REASON_FINISHED
  } else {
    pause = _REASON_UNKNOWN
    resume = _REASON_UNKNOWN
    cancel = _REASON_UNKNOWN
    close = _REASON_UNKNOWN
  }
  return { pause: _action(pause), resume: _action(resume), cancel: _action(cancel), close: _action(close) }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `timeout 600 bash tests/run.sh core/domain/tst_runs.qml; echo "exit $?"`
Expected: pytest passes; `== tests/core/domain/tst_runs.qml`, no `FAIL` lines, a `Totals:` line with `0 failed`, and `exit 0`.

Then: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_run_row_contract.qml`
Expected: `0 failed` (the table tests still SKIP; the contract tests pass with the real close).

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): implement controls().close by run state and Integrate"
```

---

### Task 2: `visibleActions(run)`

**Files:**
- Modify: `core/domain/runs.js` (the comment above `visibleActions()` and its body, right after `runLevel()`)
- Test: `tests/core/domain/tst_runs.qml` (a new test right after `test_controls_close_by_state` from Task 1)

**Interfaces:**
- Consumes: `runState(run)`, `controls(run)` with the real `close` from Task 1 (`runs.js`); `ctlRun(status, live, accepting)` (`tst_runs.qml`).
- Produces: `visibleActions(run)` returns a fresh array of UI action names (`"cancel"`, `"pause"`, `"close"`, `"resume"`, `"relaunch"`), left to right as rendered. New `runs.js` table `_ACTIONS_BY_STATE`.

- [ ] **Step 1: Write the failing test**

In `tests/core/domain/tst_runs.qml`, insert immediately after the closing `}` of `test_controls_close_by_state`:

```qml

  function test_visible_actions_fresh() {
    var run = ctlRun("stopped", false, true)
    var a = Runs.visibleActions(run)
    var b = Runs.visibleActions(run)
    compare(a.join(","), "close,resume", "parked")
    verify(a !== b, "a fresh array per call")
    a.push("pause")
    a[0] = "bogus"
    compare(b.join(","), "close,resume", "the second result after mutating the first")
    compare(Runs.visibleActions(run).join(","), "close,resume", "a third call after mutating the first")
    var c = Runs.controls(run)
    c.close.enabled = false
    c.close.reason = "changed"
    c.resume.enabled = false
    delete c.pause
    compare(Runs.visibleActions(run).join(","), "close,resume", "after mutating a controls() result")
    checkAction(Runs.controls(run).close, "", "controls() close after mutating an earlier result")
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: one `FAIL!  : qmltestrunner::DomainRuns::test_visible_actions_fresh() 'parked'` (actual `""`, expected `close,resume`); every other test passes.

- [ ] **Step 3: Write minimal implementation**

In `core/domain/runs.js`, replace

```js
// The UI actions the Runs row shows for a run, a fresh array, left to right as
// rendered: the state's buttons (running: cancel, pause; parked: close, resume;
// escalated and dead: close, relaunch; anything else: none) minus every one
// whose controls(run) entry is disabled. relaunch has no controls() entry and
// is never dropped. Stub until story B (042b0d8e): always a fresh []. Never
// throws.
function visibleActions(run) {
  return []
}
```

with

```js
// [state, UI actions] for the Runs row, left to right as rendered. A state not
// listed shows no actions.
var _ACTIONS_BY_STATE = [
  ["running", ["cancel", "pause"]],
  ["parked", ["close", "resume"]],
  ["escalated", ["close", "relaunch"]],
  ["dead", ["close", "relaunch"]]
]

// The UI actions the Runs row shows for a run, a fresh array, left to right as
// rendered: the state's buttons (running: cancel, pause; parked: close, resume;
// escalated and dead: close, relaunch; anything else: none) minus every one
// whose controls(run) entry is disabled. relaunch has no controls() entry and
// is never dropped, and resume is never shown on an escalated or dead run.
// controls(run) is computed once per call. Never throws.
function visibleActions(run) {
  var state = runState(run)
  var allowed = controls(run)
  var out = []
  for (var i = 0; i < _ACTIONS_BY_STATE.length; i++) {
    if (_ACTIONS_BY_STATE[i][0] !== state) continue
    var names = _ACTIONS_BY_STATE[i][1]
    for (var j = 0; j < names.length; j++) {
      if (names[j] === "relaunch" || allowed[names[j]].enabled) out.push(names[j])
    }
  }
  return out
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/run.sh core/domain/tst_runs.qml; echo "exit $?"`
Expected: no `FAIL` lines, `Totals:` with `0 failed`, `exit 0`.

Then: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_run_row_contract.qml`
Expected: `0 failed` (`test_contract_visible_actions_signature` and `test_contract_action_vocabulary` now see real, non-empty arrays and still pass).

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): implement visibleActions from the run state and controls()"
```

---

### Task 3: `runLevel(run)`

**Files:**
- Modify: `core/domain/runs.js` (the comment above `runLevel()` and its body, right after `controls()`)
- Test: `tests/core/domain/tst_runs.qml` (a new test right after `test_visible_actions_fresh` from Task 2)

**Interfaces:**
- Consumes: `_isObject(v)`, `_textOf(v)` (`runs.js`).
- Produces: `runLevel(run)` returns `"subtask"`, `"story"` or `"milestone"`.

- [ ] **Step 1: Write the failing test**

In `tests/core/domain/tst_runs.qml`, insert immediately after the closing `}` of `test_visible_actions_fresh`:

```qml

  function test_run_level_edges() {
    // [label, run, level]: input shapes the contract table does not list.
    var cases = [
      ["array workflow, read as controls() reads it", { workflow: ["task"] }, "subtask"],
      ["task with a blank story", { workflow: "task", story_id: "" }, "subtask"],
      ["object workflow", { workflow: {} }, "milestone"],
      ["prototype-less workflow", { workflow: Object.create(null) }, "milestone"],
      ["object story_id", { story_id: {} }, "milestone"],
      ["prototype-less story_id", { story_id: Object.create(null) }, "milestone"],
      ["array story_id", { story_id: ["s1"] }, "milestone"],
      ["boolean story_id", { story_id: true }, "milestone"],
      ["number story_id", { story_id: 5 }, "milestone"],
      ["padded story_id", { story_id: " s1 " }, "story"],
      ["tab and newline story_id", { story_id: "\ts1\n" }, "story"],
      ["an array run", ["task"], "milestone"],
      ["true", true, "milestone"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var level = Runs.runLevel(cases[i][1])
      compare(typeof level, "string", cases[i][0] + ": a string")
      compare(level, cases[i][2], cases[i][0])
    }
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: one `FAIL!  : qmltestrunner::DomainRuns::test_run_level_edges() 'array workflow, read as controls() reads it'` (actual `milestone`, expected `subtask`); every other test passes.

- [ ] **Step 3: Write minimal implementation**

In `core/domain/runs.js`, replace

```js
// The run's level in the milestone tree: "subtask" for a card run (workflow
// "task", trimmed, case-sensitive), else "story" when story_id is a string that
// is non-empty after trimming, else "milestone". Stub until story B (042b0d8e):
// always "milestone". Never throws.
function runLevel(run) {
  return "milestone"
}
```

with

```js
// The run's level in the milestone tree: "subtask" for a card run (workflow
// "task", read as controls() reads it: trimmed, case-sensitive), else "story"
// when story_id is a string that is non-empty after trimming (a number or any
// other non-string is no story id), else "milestone". Anything that is not an
// object is "milestone". Never throws.
function runLevel(run) {
  if (!_isObject(run)) return "milestone"
  if (_textOf(run.workflow) === "task") return "subtask"
  if (typeof run.story_id === "string" && run.story_id.trim() !== "") return "story"
  return "milestone"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/run.sh core/domain/tst_runs.qml; echo "exit $?"`
Expected: no `FAIL` lines, `Totals:` with `0 failed`, `exit 0`.

Then: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_run_row_contract.qml`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): implement runLevel from workflow and story_id"
```

---

### Task 4: `controlError(error, action)` — `NotResettableError` and `RunIsLiveError` on reset

**Files:**
- Modify: `core/domain/runs.js` (`_CONTROL_ERRORS`, a new `_LIVE_ON_RESET` constant, the comment above `controlError()` and its body)
- Test: `tests/core/domain/tst_runs.qml` (`controlErrorTable()`, `test_control_error_table`, and a new test right after `test_control_error_fallback`)

**Interfaces:**
- Consumes: `_controlErrorType(error)`, `errorText(error)` (`runs.js`); `controlErrorTable()` (`tst_runs.qml`).
- Produces: `_CONTROL_ERRORS` has ten entries, `NotResettableError` last; `controlError(error, action)` gives `Another am process is still driving this run. Pause it first.` for `RunIsLiveError` when `action` is a string that is `"reset"` after trimming. New `tst_runs.qml` property `ctlLiveReset`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, after the line

```qml
  readonly property string ctlCloseRunning: "A running run is cancelled, not closed"
```

(added in Task 1) add

```qml
  readonly property string ctlLiveReset: "Another am process is still driving this run. Pause it first."
```

In `controlErrorTable()`, replace the last row

```qml
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
```

with

```qml
      ["LockTimeoutError", "am is busy; try again in a moment"],
      ["NotResettableError", "This run cannot be closed (it is finished or already cancelled)."]
    ]
```

(It goes last so `controlErrorTable()[5]` and `[6]`, which `test_offers_relaunch_agrees_with_control_error` reads as the relaunch sentences, do not move.)

In `test_control_error_table`, replace

```qml
    compare(table.length, 9)
```

with

```qml
    compare(table.length, 10)
```

Then insert immediately after the closing `}` of `test_control_error_fallback`:

```qml

  function test_control_error_reset_action() {
    compare(controlErrorTable()[4][0], "RunIsLiveError", "table row 4 is RunIsLiveError")
    var liveSentence = controlErrorTable()[4][1]
    var live = [["envelope", { ok: false, error: { type: "RunIsLiveError", message: "m" } }],
                ["bare", { type: "RunIsLiveError" }]]
    var resetActions = ["reset", "  reset  "]
    var otherActions = ["Reset", "close", "pause", undefined, null, 5, {}, ["reset"], "__proto__", "constructor"]
    for (var i = 0; i < live.length; i++) {
      for (var j = 0; j < resetActions.length; j++)
        compare(Runs.controlError(live[i][1], resetActions[j]), ctlLiveReset, live[i][0] + ", reset " + j)
      for (var k = 0; k < otherActions.length; k++)
        compare(Runs.controlError(live[i][1], otherActions[k]), liveSentence, live[i][0] + ", other action " + k)
      compare(Runs.controlError(live[i][1]), liveSentence, live[i][0] + ", no action")
    }
    var others = [["NotResettableError", "This run cannot be closed (it is finished or already cancelled)."],
                  ["ClaimedError", "Another run has already claimed this work"]]
    for (var m = 0; m < others.length; m++) {
      var envelope = { ok: false, error: { type: others[m][0], message: "m" } }
      compare(Runs.controlError(envelope), others[m][1], others[m][0] + ", no action")
      compare(Runs.controlError(envelope, "reset"), others[m][1], others[m][0] + ", reset")
      compare(Runs.controlError({ type: others[m][0] }, "reset"), others[m][1], others[m][0] + ", bare, reset")
    }
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_runs.qml`
Expected: three `FAIL!` lines: `test_control_error_table` (`NotResettableError`: actual `NotResettableError: am said so`), `test_control_error_shapes` (`bare NotResettableError`: actual `NotResettableError: x`) and `test_control_error_reset_action` (`envelope, reset 0`: actual is today's `RunIsLiveError` sentence). Every other test passes, including `test_control_sentences_are_ascii`, `test_offers_relaunch_table` and `test_offers_relaunch_agrees_with_control_error`, which iterate the table too.

- [ ] **Step 3: Write minimal implementation**

In `core/domain/runs.js`, replace the end of `_CONTROL_ERRORS`

```js
  ["ClaimedError", "Another run has already claimed this work"],
  ["LockTimeoutError", "am is busy; try again in a moment"]
]
```

with

```js
  ["ClaimedError", "Another run has already claimed this work"],
  ["LockTimeoutError", "am is busy; try again in a moment"],
  ["NotResettableError", "This run cannot be closed (it is finished or already cancelled)."]
]

// RunIsLiveError's sentence on a reset: close takes a paused run, so pausing is
// the way forward, not waiting or resuming.
var _LIVE_ON_RESET = "Another am process is still driving this run. Pause it first."
```

Replace

```js
// The sentence for a failed pause / resume / cancel / reset. A known type gives
// its sentence without am's message; anything else gives errorText(error).
// `action` is the store's action name (pause, resume, cancel, reset) and is
// optional; it is accepted and ignored until story B (042b0d8e) gives reset its
// own sentences.
function controlError(error, action) {
  var type = _controlErrorType(error)
  for (var i = 0; i < _CONTROL_ERRORS.length; i++) {
```

with

```js
// The sentence for a failed pause / resume / cancel / reset. A known type gives
// its sentence without am's message; anything else gives errorText(error).
// `action` is the store's action name (pause, resume, cancel, reset) and is
// optional. It is read only when it is a string, trimmed and case-sensitive:
// on "reset", a RunIsLiveError gives its own sentence. Every other type, and
// every other action, gives the same sentence as with no action.
function controlError(error, action) {
  var type = _controlErrorType(error)
  if (type === "RunIsLiveError" && typeof action === "string" && action.trim() === "reset") return _LIVE_ON_RESET
  for (var i = 0; i < _CONTROL_ERRORS.length; i++) {
```

(The rest of `controlError` and all of `offersRelaunch` stay as they are.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/run.sh core/domain/tst_runs.qml; echo "exit $?"`
Expected: no `FAIL` lines, `Totals:` with `0 failed`, `exit 0`.

Then: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_run_row_contract.qml`
Expected: `0 failed` (`test_contract_control_error_action_arg` keeps its own nine-row table and never passes `"reset"`).

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): give controlError the NotResettableError and RunIsLiveError-on-reset sentences"
```

---

### Task 5: Turn on the Runs row table tests

**Files:**
- Modify: `tests/core/domain/tst_run_row_contract.qml:7-16` (file header comment, the flag and its comment)

**Interfaces:**
- Consumes: the real `controls(run).close` (Task 1), `visibleActions` (Task 2), `runLevel` (Task 3), `controlError(error, action)` (Task 4).
- Produces: nothing new; `domainImplemented` is `true`, so `test_table_controls_close`, `test_table_visible_actions`, `test_table_run_level` and `test_table_control_error_reset` run.

- [ ] **Step 1: Flip the flag and update the comments**

In `tests/core/domain/tst_run_row_contract.qml`, replace

```qml
// The Runs row redesign's shared contract (card 6f9f8639): the action
// vocabularies, and the signatures of runLevel, visibleActions,
// controls().close and controlError(error, action). The contract tests run
// against whatever runs.js has, stubs included. Fixture runs are built from
// tests/fixtures/am/ via amRun, as in tst_runs.qml.
TestCase {
  name: "DomainRunRowContract"

  // Story B (runs.js domain) sets this to true; the table tests below are its definition of done.
  readonly property bool domainImplemented: false
```

with

```qml
// The Runs row redesign's shared contract (card 6f9f8639): the action
// vocabularies, and runLevel, visibleActions, controls().close and
// controlError(error, action). The contract tests pin the signatures and the
// result shapes; the table tests pin the values runs.js gives. Fixture runs are
// built from tests/fixtures/am/ via amRun, as in tst_runs.qml.
TestCase {
  name: "DomainRunRowContract"

  // True since runs.js implements the domain (story B, card ad1501fd); the table tests below are its definition of done.
  readonly property bool domainImplemented: true
```

The four `if (!domainImplemented) skip(...)` lines and every test body stay unchanged.

- [ ] **Step 2: Run the contract file**

Run: `QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_run_row_contract.qml`
Expected: no `SKIP` and no `FAIL!` lines; the four `test_table_*` lines say `PASS`; `0 failed, 0 skipped`.

If a `test_table_*` row fails, the bug is in `runs.js` (Tasks 1-4), not in the table: fix `runs.js`, add the missing case to the matching `tst_runs.qml` test, and re-run. Do not edit the table.

- [ ] **Step 3: Run the whole gate**

Run: `timeout 900 bash tests/run.sh; echo "exit $?"`
Expected: pytest passes (including `tests/architecture/test_layers.py`); every `== tests/...` QML file has a `Totals:` line with `0 failed`; no `FAIL`, `TypeError`, `ReferenceError` or `is not a function` lines; `exit 0`.

Also: `grep -n "stub\|Stub\|accepted and ignored\|story B (042b0d8e)" core/domain/runs.js`
Expected: no output (every stub comment is gone).

- [ ] **Step 4: Commit**

```bash
git add tests/core/domain/tst_run_row_contract.qml
git commit -m "test(runs): turn on the Runs row table tests now that runs.js implements them"
```
<!-- task-pipeline: validated -->
