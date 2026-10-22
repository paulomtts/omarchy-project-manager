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

---

# Contract stubs and table tests for the Runs row redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the Runs row redesign's shared names into `core/domain/runs.js` as safe stubs (`runLevel`, `visibleActions`, `controls().close`, `controlError(error, action)`), and write the expected-value table as tests that skip until story B turns them on.

**Architecture:** Three tasks. (1) `controls()` gains a fourth `close` entry, stubbed to the unknown reason, with the action-vocabulary comment; `tst_runs.qml`'s `checkControls` and `test_controls_shape` learn about `close` without fixing its value. (2) `runLevel` and `visibleActions` stubs and the optional `action` argument of `controlError`, pinned by the five always-on contract tests in a new `tst_run_row_contract.qml`. (3) The four table tests in the same file, behind `domainImplemented: false`, with a one-off red check that they fail against the stubs.

**Tech Stack:** Qt 6 QML / JavaScript (`.pragma library`, `var` and function declarations only), QtTest `TestCase` run by `qmltestrunner`. The gate is `bash tests/run.sh` (pytest over `tests/`, then every `tst_*.qml`; it fails on any `FAIL` line and on `TypeError`, `ReferenceError` or `is not a function` in QML output).

**Spec:** `docs/superpowers/specs/write-contract-stubs-6f9f8639.md` (prepended above). Parent design: `docs/superpowers/specs/runs-screen-row-redesign-design.md` (RR).

**Worktree / branch:** run every command from the worktree root
`/home/mtts/Code/omarchy-project-manager/.claude/worktrees/runs-row-v5/task-write-contract-stubs-6f9f8639`
(branch `runs-row-v5/task-write-contract-stubs-6f9f8639`). Every path below is relative to it.

**How to run one QML test file:** `bash tests/run.sh <substring>` runs the whole pytest suite first (a few minutes), then only the QML files whose path contains `<substring>`. It prints `== <path>`, any `FAIL` lines with their `   Loc` lines, and a `Totals:` line per file. Exit status 0 means green. Use a `timeout 600` prefix so a stuck run cannot hang the session. For a faster inner loop you may run one file directly, which also prints `SKIP` lines and actual/expected values:
`QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 timeout 300 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/<file>.qml`
— but each task's final check uses `bash tests/run.sh`.

## Global Constraints

- `core/domain` is pure JS, no QML; `runs.js` is `.pragma library`, uses `var` and function declarations only, and its functions never throw and return fresh objects per call.
- `bash tests/run.sh` is green before and after.
- `tests/architecture/test_layers.py` passes.
- The top-level filters, their store properties and their tests are not touched.
- The card changes `core/domain/runs.js` (stubs only), `tests/core/domain/tst_runs.qml` (two helpers), and adds `tests/core/domain/tst_run_row_contract.qml`. Nothing else.
- UI action names: `pause`, `resume`, `cancel`, `close`, `relaunch`. `controls()` keys: `pause`, `resume`, `cancel`, `close`. Store/backend action names: `pause`, `resume`, `cancel`, `reset`. `controlError(error, action)`'s `action` uses the store names. `close` (UI) is `reset` (store, backend, `am`); `relaunch` is UI only.
- Stubs: `runLevel` returns `"milestone"`; `visibleActions` returns a fresh `[]`; `controls(run).close` is `{enabled: false, reason: "The run's state is unknown"}`; `controlError`'s `action` is accepted and ignored.
- The table tests start with `if (!domainImplemented) skip("runs.js domain not implemented yet (story B)")`, and `domainImplemented` is committed as `false`.
- Never `git commit` the red-check edit (`domainImplemented: true`).

## Review Focus

1. **A `__proto__` or `constructor` string in `workflow`, `story_id` or `action`** — must behave as an ordinary string (spec, Error paths). Pinned by: Task 2's garbage list (`{workflow: "__proto__"}`, `{story_id: "constructor"}`) and `test_contract_control_error_action_arg`'s `"__proto__"` / `"constructor"` actions; Task 3's `runLevel` rows `{story_id: "__proto__"}` / `{story_id: "constructor"}`.
2. **A value `String()` cannot convert (a prototype-less object) as `workflow` or `story_id`** — the stubs and B's code must still return a level / an array and not throw, the way `_textOf` already guards `workflow`. Pinned by: Task 2's garbage list entries `{workflow: Object.create(null)}` and `{story_id: Object.create(null)}`, run through all three new functions and `controls()`.
3. **A caller that mutates a returned `visibleActions` array or `controls().close` object** (a QML view pushing into or editing a result) — later calls must be unaffected. Pinned by: Task 1's `test_controls_shape` additions and Task 2's `test_contract_visible_actions_signature` / `test_contract_controls_close_present` freshness checks.
4. **Today's one-argument `controlError` callers** (`core/stores/RunControlStore.qml:207`, the store tests) — every sentence unchanged. Pinned by: Task 2's `test_contract_control_error_action_arg` (one-arg vs two-arg equality over the nine known types, an unknown type and garbage errors) and the untouched `test_control_error_*` tests in `tst_runs.qml`, which Task 2 Step 6 runs.
5. **Existing `checkControls` callers in `tst_runs.qml` against the new fourth key** — every existing controls test must keep passing with the stub and with B's real `close`. Pinned by: Task 1, which makes `checkControls` require `close` but only check its form, and runs the whole `tst_runs.qml`.

---

### Task 1: `controls()` gains a stubbed `close` entry

**Files:**
- Modify: `core/domain/runs.js:1183-1214` (the comment above `controls()` and its `return`)
- Test: `tests/core/domain/tst_runs.qml:2792-2825` (`checkControls` and `test_controls_shape`)

**Interfaces:**
- Consumes: `_action(reason)` (`runs.js:1175`), `_REASON_UNKNOWN` (`runs.js:1167`).
- Produces: `controls(run)` returns exactly `{pause, resume, cancel, close}`, each a fresh `{enabled, reason}`; `close` is `{enabled: false, reason: "The run's state is unknown"}` for every input until story B. A new test helper `checkWellFormed(a, label)` in `tst_runs.qml`.

- [ ] **Step 1: Write the failing test**

In `tests/core/domain/tst_runs.qml`, replace the block from the comment line `// A whole controls() result; "" means that action is enabled.` through the end of `test_controls_shape()` (currently lines 2792-2825) with:

```qml
  // An action whose value is not fixed here: exactly {enabled, reason}, reason a
  // string, enabled iff reason is "".
  function checkWellFormed(a, label) {
    compare(Object.keys(a).sort().join(","), "enabled,reason", label + " keys")
    compare(typeof a.reason, "string", label + " reason is a string")
    compare(a.enabled, a.reason === "", label + " enabled")
  }

  // A whole controls() result; "" means that action is enabled. `close` must be
  // present and well formed; its value belongs to the Runs row redesign's own
  // tests (tst_run_row_contract.qml).
  function checkControls(c, pause, resume, cancel, label) {
    compare(Object.keys(c).sort().join(","), "cancel,close,pause,resume", label + " keys")
    checkAction(c.pause, pause, label + " pause")
    checkAction(c.resume, resume, label + " resume")
    checkAction(c.cancel, cancel, label + " cancel")
    checkWellFormed(c.close, label + " close")
  }

  function test_controls_shape() {
    var run = ctlRun("started", true, true)
    var a = Runs.controls(run)
    checkControls(a, "", ctlResumeRunning, "", "running")
    var b = Runs.controls(run)
    verify(a !== b, "a fresh result per call")
    verify(a.pause !== b.pause && a.resume !== b.resume && a.cancel !== b.cancel, "fresh actions per call")
    verify(a.close !== b.close, "a fresh close per call")
    verify(a.pause !== a.resume && a.resume !== a.cancel && a.pause !== a.cancel, "no action shared within a result")
    verify(a.close !== a.pause && a.close !== a.resume && a.close !== a.cancel, "close shared with no other action")
    var closeBefore = b.close.reason
    a.pause.enabled = false
    a.pause.reason = "changed"
    a.resume.reason = "changed"
    a.close.enabled = !a.close.enabled
    a.close.reason = "changed"
    delete a.cancel
    var after = Runs.controls(run)
    checkControls(after, "", ctlResumeRunning, "", "after mutating an earlier result")
    compare(after.close.reason, closeBefore, "close unchanged after mutating an earlier result")

    var u = Runs.controls(undefined)
    verify(u.pause !== u.resume && u.resume !== u.cancel && u.pause !== u.cancel, "no action shared in an unknown result")
    verify(u.close !== u.pause && u.close !== u.resume && u.close !== u.cancel, "close shared with no other unknown action")
    var unknownClose = Runs.controls(null).close.reason
    u.pause.reason = "changed"
    u.resume.enabled = true
    u.close.reason = "changed"
    u.close.enabled = !u.close.enabled
    var u2 = Runs.controls(null)
    checkControls(u2, ctlUnknown, ctlUnknown, ctlUnknown, "after mutating an unknown result")
    compare(u2.close.reason, unknownClose, "unknown close unchanged after mutating an earlier result")

    var d = Runs.controls(ctlRun("done", null, true))
    d.cancel.reason = ""
    d.cancel.enabled = true
    checkControls(Runs.controls(ctlRun("done", null, true)), ctlFinished, ctlFinished, ctlFinished, "after mutating a done result")
  }
```

Leave `checkAction` (just above) and every other test untouched.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash tests/run.sh domain/tst_runs.qml`
Expected: exit status 1, with 14 `FAIL!` lines ending in `keys`, one per test that calls `checkControls`, for example `FAIL!  : qmltestrunner::DomainRuns::test_controls_shape() running keys` (actual `cancel,pause,resume`, expected `cancel,close,pause,resume`). `Totals: 324 passed, 14 failed, 0 skipped` (counts may differ by a few if the file changed; what matters is that only `checkControls` callers fail).

- [ ] **Step 3: Write minimal implementation**

In `core/domain/runs.js`, replace the comment block above `controls()` (the five lines starting `// {pause, resume, cancel}, each a fresh {enabled, reason}; reason is "" when`) with:

```js
// {pause, resume, cancel, close}, each a fresh {enabled, reason}; reason is ""
// when enabled. Pause needs a running run outside Integrate; resume needs dead,
// parked or escalated, except an escalated card run (workflow "task", trimmed),
// and never looks at accepting; cancel needs a run that has not finished and is
// not in Integrate. The state's reason wins over Integrate's. Close is a stub
// until story B (042b0d8e): always disabled with the unknown-state reason.
//
// Action names come in two vocabularies, never mixed. The UI (visibleActions,
// RunControls.actionRequested, RunsScreen.requestControl) says pause, resume,
// cancel, close and relaunch; controls() has keys pause, resume, cancel and
// close. The store (RunControlStore.control, refusalOf) and the backend
// (run-control.py ACTIONS) say pause, resume, cancel and reset, and so does the
// `action` argument of controlError(error, action). UI `close` is store, backend
// and am `reset`. `relaunch` is UI only: it starts a fresh run, so it has no
// controls() entry and no store control action.
```

Then replace the last line of `controls()`:

```js
  return { pause: _action(pause), resume: _action(resume), cancel: _action(cancel) }
```

with:

```js
  return { pause: _action(pause), resume: _action(resume), cancel: _action(cancel), close: _action(_REASON_UNKNOWN) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash tests/run.sh domain/tst_runs.qml`
Expected: exit status 0; `Totals: N passed, 0 failed, 0 skipped` for `tests/core/domain/tst_runs.qml`; no `FAIL`, `TypeError` or `ReferenceError` lines.

- [ ] **Step 5: Run the other suites that read `controls()`**

Run: `timeout 600 bash tests/run.sh tst_run_`
Expected: exit status 0 (store and component tests such as `tst_run_control_store.qml`, `tst_run_controls.qml` and `tst_run_detail_screen.qml` read only `pause`/`resume`/`cancel` and are unaffected).

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): stub controls().close and document the action vocabularies"
```

---

### Task 2: `runLevel`, `visibleActions` and `controlError(error, action)` stubs, with the contract tests

**Files:**
- Modify: `core/domain/runs.js` (insert two functions after `controls()`, before the `// [type, sentence] for each am control error` comment; change `controlError`'s signature and comment, currently lines 1238-1246)
- Create: `tests/core/domain/tst_run_row_contract.qml`

**Interfaces:**
- Consumes: `controls(run)` with its `close` key (Task 1); `Runs.normalizeRun(raw)`; `F.load(name)` from `tests/helpers/amFixtures.js`.
- Produces:
  - `function runLevel(run)` → one of `"subtask"`, `"story"`, `"milestone"`; stub returns `"milestone"`.
  - `function visibleActions(run)` → a fresh array of UI action names; stub returns `[]`.
  - `function controlError(error, action)` → string; `action` ignored for now.
  - In `tst_run_row_contract.qml` (used by Task 3): properties `domainImplemented` (not yet, Task 3 adds it), `reasonIntegrate`, `reasonFinished`, `reasonUnknown`, `reasonCancelled`, `reasonRunning`; helpers `uiActions()`, `storeActions()`, `levels()`, `amRun(name)`, `runOf(status, live, accepting, workflow)`, `cancelledRun(spelling)`, `fixtureRun(name)`, `rowTable()` → `[[label, run, closeReason, visibleJoined], ...]`, `garbageRuns()` → `[[label, run], ...]`, `allRuns()` → `[[label, run], ...]`, `controlErrorTable()` → `[[type, sentence], ...]` (nine rows).

- [ ] **Step 1: Write the failing test**

Create `tests/core/domain/tst_run_row_contract.qml` with exactly:

```qml
// tests/core/domain/tst_run_row_contract.qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

// The Runs row redesign's shared contract (card 6f9f8639): the action
// vocabularies, and the signatures of runLevel, visibleActions,
// controls().close and controlError(error, action). The contract tests run
// against whatever runs.js has, stubs included. Fixture runs are built from
// tests/fixtures/am/ via amRun, as in tst_runs.qml.
TestCase {
  name: "DomainRunRowContract"

  readonly property string reasonIntegrate: "Integrate is running; it cannot be paused or cancelled"
  readonly property string reasonFinished: "The run has finished"
  readonly property string reasonUnknown: "The run's state is unknown"
  readonly property string reasonCancelled: "The run is already cancelled"
  readonly property string reasonRunning: "A running run is cancelled, not closed"

  // The UI's action names, left to right as RR's button table lists them.
  function uiActions() { return ["pause", "resume", "cancel", "close", "relaunch"] }
  // The store's and the backend's action names; also controlError's `action`.
  function storeActions() { return ["pause", "resume", "cancel", "reset"] }
  function levels() { return ["subtask", "story", "milestone"] }

  // One am run as RunStore hands it to normalizeRun, fresh on every call: the
  // fixture's `am runs` row (runs.json's entry with the same run id, else the
  // fixture's own _am_runs_row) without `status`, and the fixture's `am status`
  // data. Copied from tst_runs.qml.
  function amRun(name) {
    var fixture = F.load(name)
    var runs = F.load("runs.json").data.runs
    var row = fixture._am_runs_row
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].id === fixture.data.run.id) row = runs[i]
    }
    delete row.status
    return { row: row, status: fixture.data }
  }

  function fixtureRun(name) { return Runs.normalizeRun(amRun(name)) }

  // The status-done.json run, normalized, with am's run status set to spelling.
  // Its control.lease is null, so no Integrate reason interferes.
  function cancelledRun(spelling) {
    var raw = amRun("status-done.json")
    raw.status.run.status = spelling
    return Runs.normalizeRun(raw)
  }

  // A normalised-shape run. live === null means no lease; otherwise the lease's
  // live and accepting flags are as given (accepting !== true is Integrate).
  // workflow is set only when given.
  function runOf(status, live, accepting, workflow) {
    var r = {
      id: "rc", repo_dir: "/r", milestone_id: "m1", status: status,
      lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: accepting, live: live },
      rows: [], tree: { stories: [], subtasks: [] }
    }
    if (workflow !== undefined) r.workflow = workflow
    return r
  }

  // [label, run, close reason ("" = enabled), visibleActions joined with ","]:
  // the spec's controls(run).close / visibleActions table, one row per state,
  // lease and Integrate case, plus a normalised fixture run per state the
  // fixtures provide.
  function rowTable() {
    return [
      ["running", runOf("started", true, true), reasonRunning, "cancel,pause"],
      ["running, Integrate", runOf("started", true, false), reasonRunning, ""],
      ["parked", runOf("stopped", false, true), "", "close,resume"],
      ["parked, no lease", runOf("stopped", null, false), "", "close,resume"],
      ["parked, Integrate", runOf("stopped", false, false), reasonIntegrate, "resume"],
      ["escalated", runOf("escalated", false, true), "", "close,relaunch"],
      ["escalated, no lease", runOf("escalated", null, false), "", "close,relaunch"],
      ["escalated, Integrate", runOf("escalated", false, false), reasonIntegrate, "relaunch"],
      ["escalated card run", runOf("escalated", false, true, "task"), "", "close,relaunch"],
      ["escalated card run, padded", runOf("escalated", false, true, "  task  "), "", "close,relaunch"],
      ["escalated card run, tab and newline", runOf("escalated", false, true, "\ttask\n"), "", "close,relaunch"],
      ["dead", runOf("started", false, true), "", "close,relaunch"],
      ["dead, no lease", runOf("started", null, false), "", "close,relaunch"],
      ["dead, Integrate", runOf("started", false, false), reasonIntegrate, "relaunch"],
      ["done", runOf("done", false, true), reasonFinished, ""],
      ["done, Integrate", runOf("done", false, false), reasonFinished, ""],
      ["done, live, Integrate", runOf("done", true, false), reasonFinished, ""],
      ["done, no lease", runOf("done", null, true), reasonFinished, ""],
      ["cancelled", runOf("cancelled", false, true), reasonCancelled, ""],
      ["cancelled, Integrate", runOf("cancelled", false, false), reasonCancelled, ""],
      ["canceled, no lease", runOf("canceled", null, true), reasonCancelled, ""],
      ["canceled, live, Integrate", runOf("canceled", true, false), reasonCancelled, ""],
      ["unknown, empty status", runOf("", true, true), reasonUnknown, ""],
      ["unknown, weird, Integrate", runOf("weird", true, false), reasonUnknown, ""],
      ["unknown, STARTED", runOf("STARTED", true, true), reasonUnknown, ""],
      ["unknown, undefined", undefined, reasonUnknown, ""],
      ["unknown, null", null, reasonUnknown, ""],
      ["unknown, 5", 5, reasonUnknown, ""],
      ["unknown, x", "x", reasonUnknown, ""],
      ["unknown, {}", {}, reasonUnknown, ""],
      ["unknown, []", [], reasonUnknown, ""],
      ["unknown, prototype-less", Object.create(null), reasonUnknown, ""],
      ["fixture started", fixtureRun("status-started.json"), reasonRunning, "cancel,pause"],
      ["fixture done", fixtureRun("status-done.json"), reasonFinished, ""],
      ["fixture done-integrate", fixtureRun("status-done-integrate.json"), reasonFinished, ""],
      ["fixture escalated", fixtureRun("status-escalated.json"), "", "close,relaunch"],
      ["fixture escalated-integrate", fixtureRun("status-escalated-integrate.json"), "", "close,relaunch"],
      ["fixture cancelled", cancelledRun("cancelled"), reasonCancelled, ""],
      ["fixture canceled", cancelledRun("canceled"), reasonCancelled, ""]
    ]
  }

  // [label, run]: inputs no caller should send, which must still give a value
  // of the stated type without throwing.
  function garbageRuns() {
    return [
      ["undefined", undefined], ["null", null], ["5", 5], ["x", "x"], ["true", true], ["{}", {}], ["[]", []],
      ["prototype-less", Object.create(null)],
      ["object workflow", { workflow: {} }],
      ["object story_id", { story_id: {} }],
      ["prototype-less workflow", { workflow: Object.create(null) }],
      ["prototype-less story_id", { story_id: Object.create(null) }],
      ["__proto__ workflow", { workflow: "__proto__" }],
      ["constructor story_id", { story_id: "constructor" }],
      ["normalised garbage", Runs.normalizeRun(undefined)],
      ["fixture run", fixtureRun("status-started.json")]
    ]
  }

  // [label, run] for every row of rowTable() and every garbage run.
  function allRuns() {
    var out = []
    var table = rowTable()
    for (var i = 0; i < table.length; i++) out.push([table[i][0], table[i][1]])
    var garbage = garbageRuns()
    for (var j = 0; j < garbage.length; j++) out.push(["garbage " + garbage[j][0], garbage[j][1]])
    return out
  }

  // [type, sentence] for every am control error controlError knows today.
  // Copied from tst_runs.qml.
  function controlErrorTable() {
    return [
      ["UnknownRunError", "The run no longer exists"],
      ["NotRunningError", "The run is not running"],
      ["DeadRunError", "The run's process has died, so nobody can act on this request. Resume picks the run up."],
      ["NotAcceptingError", reasonIntegrate],
      ["RunIsLiveError", "Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died."],
      ["NotResumableError", "am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work."],
      ["CheckpointMismatchError", "The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase."],
      ["ClaimedError", "Another run has already claimed this work"],
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
  }

  // ---- Contract tests: always on --------------------------------------------------------

  function test_contract_run_level_signature() {
    compare(typeof Runs.runLevel, "function")
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var level = Runs.runLevel(runs[i][1])
      verify(levels().indexOf(level) >= 0, runs[i][0] + ": a level, got " + level)
    }
  }

  function test_contract_visible_actions_signature() {
    compare(typeof Runs.visibleActions, "function")
    var ui = uiActions()
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var label = runs[i][0], run = runs[i][1]
      var a = Runs.visibleActions(run)
      var b = Runs.visibleActions(run)
      verify(Array.isArray(a), label + ": an array")
      verify(a !== b, label + ": a fresh array per call")
      var seen = []
      for (var j = 0; j < a.length; j++) {
        verify(ui.indexOf(a[j]) >= 0, label + ": " + a[j] + " is a UI action")
        verify(seen.indexOf(a[j]) < 0, label + ": " + a[j] + " appears once")
        seen.push(a[j])
      }
      a.push("pause")
      a.push("bogus")
      compare(Runs.visibleActions(run).join(","), b.join(","), label + ": unchanged after pushing onto an earlier result")
    }
  }

  function test_contract_controls_close_present() {
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var label = runs[i][0], run = runs[i][1]
      var a = Runs.controls(run)
      var b = Runs.controls(run)
      compare(Object.keys(a).sort().join(","), "cancel,close,pause,resume", label + ": keys")
      compare(Object.keys(a.close).sort().join(","), "enabled,reason", label + ": close keys")
      compare(typeof a.close.reason, "string", label + ": close reason is a string")
      compare(a.close.enabled, a.close.reason === "", label + ": close enabled iff no reason")
      verify(a.close !== b.close, label + ": a fresh close per call")
      verify(a.close !== a.pause && a.close !== a.resume && a.close !== a.cancel, label + ": close not shared")
      var before = b.close.reason
      a.close.reason = "changed"
      a.close.enabled = !a.close.enabled
      compare(Runs.controls(run).close.reason, before, label + ": close unchanged after mutating an earlier result")
    }
  }

  function test_contract_control_error_action_arg() {
    var errors = []
    var table = controlErrorTable()
    compare(table.length, 9)
    for (var i = 0; i < table.length; i++) {
      errors.push(["envelope " + table[i][0], { ok: false, error: { type: table[i][0], message: "am said so" } }])
      errors.push(["bare " + table[i][0], { type: table[i][0] }])
    }
    errors.push(["unknown type", { ok: false, error: { type: "Foo", message: "bar" } }])
    errors.push(["ok:true", { ok: true }])
    errors.push(["undefined", undefined])
    errors.push(["null", null])
    errors.push(["x", "x"])
    var actions = [undefined, "pause", "resume", "cancel", "close", 5, null, {}, "__proto__", "constructor"]
    for (var j = 0; j < errors.length; j++) {
      var one = Runs.controlError(errors[j][1])
      compare(typeof one, "string", errors[j][0] + ": a string")
      for (var k = 0; k < actions.length; k++)
        compare(Runs.controlError(errors[j][1], actions[k]), one, errors[j][0] + ", action " + k)
    }
  }

  function test_contract_action_vocabulary() {
    var ui = uiActions(), store = storeActions()
    compare(ui.join(","), "pause,resume,cancel,close,relaunch", "UI vocabulary")
    compare(store.join(","), "pause,resume,cancel,reset", "store and backend vocabulary")
    verify(ui.indexOf("reset") < 0, "the UI never says reset")
    verify(store.indexOf("close") < 0 && store.indexOf("relaunch") < 0, "the store never says close or relaunch")
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var label = runs[i][0], run = runs[i][1]
      var shown = Runs.visibleActions(run)
      for (var j = 0; j < shown.length; j++)
        verify(ui.indexOf(shown[j]) >= 0, label + ": visible " + shown[j] + " is a UI action")
      var keys = Object.keys(Runs.controls(run))
      for (var k = 0; k < keys.length; k++) {
        verify(ui.indexOf(keys[k]) >= 0, label + ": controls key " + keys[k] + " is a UI action")
        verify(keys[k] !== "relaunch", label + ": relaunch has no controls() entry")
      }
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash tests/run.sh tst_run_row_contract`
Expected: exit status 1 and three `FAIL!` lines:
`FAIL!  : qmltestrunner::DomainRunRowContract::test_contract_run_level_signature() Compared values are not the same` (`typeof` is `undefined`, not `function`),
the same for `test_contract_visible_actions_signature()`, and
`... test_contract_action_vocabulary() Uncaught exception: Property 'visibleActions' of object [object Object] is not a function`.
`Totals: 4 passed, 3 failed, 0 skipped`. `test_contract_controls_close_present()` and `test_contract_control_error_action_arg()` already pass (Task 1 added `close`; JS ignores an extra argument).

- [ ] **Step 3: Write minimal implementation**

In `core/domain/runs.js`, directly after the closing `}` of `controls()` and its following blank line, before `// [type, sentence] for each am control error, matched with === by linear scan so`, insert:

```js
// The run's level in the milestone tree: "subtask" for a card run (workflow
// "task", trimmed, case-sensitive), else "story" when story_id is a string that
// is non-empty after trimming, else "milestone". Stub until story B (042b0d8e):
// always "milestone". Never throws.
function runLevel(run) {
  return "milestone"
}

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

Then replace `controlError`'s comment and signature:

```js
// The sentence for a failed pause / resume / cancel. A known type gives its
// sentence without am's message; anything else gives errorText(error).
function controlError(error) {
```

with:

```js
// The sentence for a failed pause / resume / cancel / reset. A known type gives
// its sentence without am's message; anything else gives errorText(error).
// `action` is the store's action name (pause, resume, cancel, reset) and is
// optional; it is accepted and ignored until story B (042b0d8e) gives reset its
// own sentences.
function controlError(error, action) {
```

The body of `controlError` is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash tests/run.sh tst_run_row_contract`
Expected: exit status 0; `Totals: 7 passed, 0 failed, 0 skipped` for `tests/core/domain/tst_run_row_contract.qml` (the five tests plus QtTest's `initTestCase` and `cleanupTestCase`); no `FAIL`, `TypeError`, `ReferenceError` or `is not a function` lines.

- [ ] **Step 5: Confirm the existing `controlError` tests still pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs.qml`
Expected: exit status 0; no `FAIL` lines (all `test_control_error_*` tests unchanged and green).

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_run_row_contract.qml
git commit -m "feat(runs): stub runLevel, visibleActions and controlError's action, with contract tests"
```

---

### Task 3: The table tests, skipped until story B

**Files:**
- Modify: `tests/core/domain/tst_run_row_contract.qml` (add a property at the top of the `TestCase`, two sentence properties, and four tests at the end)

**Interfaces:**
- Consumes: from Task 2's test file: `rowTable()`, `allRuns()`, `controlErrorTable()`, `fixtureRun(name)`, `reasonRunning`, `reasonIntegrate`, `reasonFinished`, `reasonCancelled`, `reasonUnknown`; from `runs.js`: `controls`, `visibleActions`, `runLevel`, `controlError(error, action)`, `offersRelaunch`, `normalizeRun`.
- Produces: `readonly property bool domainImplemented: false` — the switch story B flips; tests `test_table_controls_close`, `test_table_visible_actions`, `test_table_run_level`, `test_table_control_error_reset`.

- [ ] **Step 1: Write the table tests (already enabled, to see them fail)**

In `tests/core/domain/tst_run_row_contract.qml`, directly after the line `  name: "DomainRunRowContract"` and its blank line, insert:

```qml
  // Story B (runs.js domain) sets this to true; the table tests below are its definition of done.
  readonly property bool domainImplemented: true

  readonly property string sentenceNotResettable: "This run cannot be closed (it is finished or already cancelled)."
  readonly property string sentenceLiveReset: "Another am process is still driving this run. Pause it first."

```

(`true` is temporary, for the red check in Step 2; Step 3 sets it to `false`.)

Then, before the final closing `}` of the `TestCase` (after `test_contract_action_vocabulary`), insert:

```qml

  // ---- Table tests: story B's definition of done ----------------------------------------

  function test_table_controls_close() {
    if (!domainImplemented) skip("runs.js domain not implemented yet (story B)")
    var table = rowTable()
    for (var i = 0; i < table.length; i++) {
      var close = Runs.controls(table[i][1]).close
      compare(close.reason, table[i][2], table[i][0] + ": close reason")
      compare(close.enabled, table[i][2] === "", table[i][0] + ": close enabled")
    }
  }

  function test_table_visible_actions() {
    if (!domainImplemented) skip("runs.js domain not implemented yet (story B)")
    var table = rowTable()
    for (var i = 0; i < table.length; i++)
      compare(Runs.visibleActions(table[i][1]).join(","), table[i][3], table[i][0] + ": visible actions")
    var runs = allRuns()
    for (var j = 0; j < runs.length; j++) {
      var shown = Runs.visibleActions(runs[j][1])
      var c = Runs.controls(runs[j][1])
      for (var k = 0; k < shown.length; k++) {
        if (shown[k] === "relaunch") continue
        verify(c[shown[k]].enabled, runs[j][0] + ": " + shown[k] + " is shown, so it is enabled")
      }
      verify(shown.indexOf("resume") < 0 || ["escalated", "dead"].indexOf(Runs.runState(runs[j][1])) < 0,
             runs[j][0] + ": resume is never shown on an escalated or dead run")
    }
  }

  function test_table_run_level() {
    if (!domainImplemented) skip("runs.js domain not implemented yet (story B)")
    var noProtoTask = Object.create(null)
    noProtoTask.workflow = "task"
    var table = [
      ["task", { workflow: "task" }, "subtask"],
      ["padded task", { workflow: "  task  " }, "subtask"],
      ["tab and newline task", { workflow: "\ttask\n" }, "subtask"],
      ["task with a story: workflow wins", { workflow: "task", story_id: "s1" }, "subtask"],
      ["milestone workflow with a story", { workflow: "milestone", story_id: "s1" }, "story"],
      ["story only", { story_id: "s1" }, "story"],
      ["__proto__ story", { story_id: "__proto__" }, "story"],
      ["constructor story", { story_id: "constructor" }, "story"],
      ["empty story", { story_id: "" }, "milestone"],
      ["blank story", { story_id: "   " }, "milestone"],
      ["null story", { story_id: null }, "milestone"],
      ["number story", { story_id: 5 }, "milestone"],
      ["Task", { workflow: "Task" }, "milestone"],
      ["tasks", { workflow: "tasks" }, "milestone"],
      ["story workflow", { workflow: "story" }, "milestone"],
      ["{}", {}, "milestone"],
      ["undefined", undefined, "milestone"],
      ["null", null, "milestone"],
      ["5", 5, "milestone"],
      ["the string task", "task", "milestone"],
      ["[]", [], "milestone"],
      ["prototype-less", Object.create(null), "milestone"],
      ["prototype-less task", noProtoTask, "subtask"],
      ["normalised story (synthetic: no fixture has one)",
       Runs.normalizeRun({ row: { id: "r", workflow: "milestone", story_id: "s1" } }), "story"]
    ]
    var rows = F.load("runs.json").data.runs
    for (var r = 0; r < rows.length; r++) {
      var run = Runs.normalizeRun({ row: rows[r] })
      compare(run.workflow, "milestone", "runs.json row " + r + " precondition: workflow")
      compare(run.story_id, "", "runs.json row " + r + " precondition: story_id")
      table.push(["runs.json row " + r, run, "milestone"])
    }
    var captures = ["status-started.json", "status-done.json", "status-escalated.json",
                    "status-done-integrate.json", "status-escalated-integrate.json"]
    for (var c = 0; c < captures.length; c++)
      table.push([captures[c], fixtureRun(captures[c]), "milestone"])
    for (var i = 0; i < table.length; i++)
      compare(Runs.runLevel(table[i][1]), table[i][2], table[i][0])
  }

  function test_table_control_error_reset() {
    if (!domainImplemented) skip("runs.js domain not implemented yet (story B)")
    var sentenceLive = controlErrorTable()[4][1]
    compare(controlErrorTable()[4][0], "RunIsLiveError", "table row 4 is RunIsLiveError")

    var notResettable = [["envelope", { ok: false, error: { type: "NotResettableError", message: "m" } }],
                         ["bare", { type: "NotResettableError" }]]
    var anyAction = [undefined, "reset", "  reset  ", "pause", "resume", "cancel", "close", 5, null]
    for (var i = 0; i < notResettable.length; i++) {
      compare(Runs.controlError(notResettable[i][1]), sentenceNotResettable, notResettable[i][0] + ", missing action")
      for (var j = 0; j < anyAction.length; j++)
        compare(Runs.controlError(notResettable[i][1], anyAction[j]), sentenceNotResettable,
                notResettable[i][0] + ", action " + j)
      compare(Runs.offersRelaunch(notResettable[i][1]), false, notResettable[i][0] + ": no relaunch offer")
    }

    var live = [["envelope", { ok: false, error: { type: "RunIsLiveError", message: "m" } }],
                ["bare", { type: "RunIsLiveError" }]]
    var resetActions = ["reset", "  reset  "]
    var otherActions = ["pause", "resume", "cancel", undefined, "close", 5]
    for (var k = 0; k < live.length; k++) {
      for (var a = 0; a < resetActions.length; a++)
        compare(Runs.controlError(live[k][1], resetActions[a]), sentenceLiveReset, live[k][0] + ", reset " + a)
      for (var b = 0; b < otherActions.length; b++)
        compare(Runs.controlError(live[k][1], otherActions[b]), sentenceLive, live[k][0] + ", other action " + b)
      compare(Runs.controlError(live[k][1]), sentenceLive, live[k][0] + ", missing action")
    }

    var table = controlErrorTable()
    var everyAction = [undefined, "reset", "pause", "resume", "cancel", "close", 5]
    for (var t = 0; t < table.length; t++) {
      if (table[t][0] === "RunIsLiveError") continue
      for (var e = 0; e < everyAction.length; e++)
        compare(Runs.controlError({ ok: false, error: { type: table[t][0], message: "m" } }, everyAction[e]),
                table[t][1], table[t][0] + ", action " + e)
    }
  }
```

- [ ] **Step 2: Run the red check: the table tests fail against the stubs**

Run: `timeout 600 bash tests/run.sh tst_run_row_contract`
Expected: exit status 1, `Totals: 7 passed, 4 failed, 0 skipped`, with exactly four `FAIL!` lines (each prefixed `qmltestrunner::DomainRunRowContract::`), one for each of
`test_table_controls_close()` (first row `running: close reason`: actual `The run's state is unknown`, expected `A running run is cancelled, not closed`),
`test_table_visible_actions()` (`running: visible actions`: actual `""`, expected `cancel,pause`),
`test_table_run_level()` (`task`: actual `milestone`, expected `subtask`) and
`test_table_control_error_reset()` (`envelope, missing action`: actual `NotResettableError: m`, expected `This run cannot be closed (it is finished or already cancelled).`).
The five `test_contract_*` tests pass. No `TypeError` or `ReferenceError` line. If any table test passes, or fails for another reason (for example a `TypeError`), fix the test before going on: that proves it is not vacuous.

- [ ] **Step 3: Turn the table tests off**

In `tests/core/domain/tst_run_row_contract.qml`, change

```qml
  readonly property bool domainImplemented: true
```

to

```qml
  readonly property bool domainImplemented: false
```

- [ ] **Step 4: Run test to verify it passes with the table tests skipped**

Run: `timeout 600 bash tests/run.sh tst_run_row_contract`
Expected: exit status 0; `Totals: 7 passed, 0 failed, 4 skipped` for `tests/core/domain/tst_run_row_contract.qml` (the four table tests report `SKIP   : ... runs.js domain not implemented yet (story B)`; `tests/run.sh` does not print SKIP lines). Also confirm `grep -n "domainImplemented: false" tests/core/domain/tst_run_row_contract.qml` prints one line.

- [ ] **Step 5: Run the whole gate**

Run: `timeout 900 bash tests/run.sh`
Expected: exit status 0 (pytest green, including `tests/architecture/test_layers.py`; every QML file `0 failed`; no `TypeError`, `ReferenceError` or `is not a function` lines). Then `git status --short` lists only `tests/core/domain/tst_run_row_contract.qml` as modified (plus the untracked spec/plan docs, which are not yours to commit).

- [ ] **Step 6: Commit**

```bash
git add tests/core/domain/tst_run_row_contract.qml
git commit -m "test(runs): Runs row table tests, skipped until story B implements the domain"
```
<!-- task-pipeline: validated -->
