# 1.1 runs.js: controls and controlError (card adff6c85)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2):
"Control actions" (lines 29-53), "Architecture" bullet 1 (lines 57-61), "Errors"
(lines 138-146) and "Testing" bullet 1 (lines 150-152). Parent story 7ad84a64.
No blockers.

## Starting point

`core/domain/runs.js` (`.pragma library`) already has:

- `normalizeRun(raw)` — `run.lease` is `null` or
  `{pid, host, heartbeat_at, accepting, live}`, where `accepting` and `live` are
  `=== true` of the raw value (runs.js:31-41).
- `runState(run)` — `running | dead | parked | escalated | cancelled | done | unknown`;
  `running` only for status `started` with `lease.live === true`, `dead` for
  `started` without a live lease, `parked` for `stopped` (runs.js:62-72).
- Private helpers `_isObject`, `_stringOr`, `_textOf` (runs.js:81-86, 244-247) and
  `errorText(error)` (runs.js:278-288), which reads both the
  `{ok:false, error:{type, message}}` envelope and the bare `{type, message}`.

`controls` and `controlError` do not exist anywhere yet. `_isNonTerminal`
(runs.js:112) means `running | dead` only and is **not** the cancel rule; do not
reuse or change it.

## Scope

Add two pure functions to `core/domain/runs.js` in a new section after
`attemptStatus` (banner `// ---- Run controls (S2 1.1) ----`), with tests in
`tests/core/domain/tst_runs.qml`. Tests first.

Constraints (inherited from the 1.x runs.js cards and `docs/architecture.md`
line 157: "pure JS, never throws, and every input comes from `am`"):

- `var`/`function` style, no ES6 `const`/`let`/arrows, `_`-prefixed private helpers,
  one comment block above each function. No imports. No glyph literals (all text
  is plain ASCII, so `tests/architecture/test_icon_glyphs.py` is unaffected).
- No function throws. Garbage input (`undefined`, `null`, numbers, strings, `{}`,
  `[]`, prototype-less objects) becomes the default result described below.
- Error types are matched with `===` against a fixed list (linear scan or
  `switch`), never by property lookup on a plain object, so a type of
  `constructor`, `__proto__` or `toString` falls through to the fallback.
- Existing functions and their tests are not changed.

### Out of scope

Everything else in S2, owned by sibling cards: `newAlerts(prev, next)` (spec
line 136, also in `runs.js` but not this card), `core/backend/runs/run-control.py`,
`RunStore.control` / `pending` / `lastError` / the 30 s timeout, the
`TypedConfirmDialog` `confirmWord` change, `ui/components/RunControls.qml`,
keyboard shortcuts, `RunToast.qml`, `notify.py`, contract tests, UI flow tests,
and edits to `docs/architecture.md`. The "button disabled while a request is
outstanding" rule (spec lines 42-43) is a store concern: `controls(run)` looks
at the run only, never at pending requests. No file under `ui/`, `core/stores/`
or `core/backend/` is touched.

## Behaviour

### `controls(run)` → `{pause, resume, cancel}`

Each value is `{enabled: boolean, reason: string}`, a fresh object on every call
(mutating one result never affects another). The returned object has exactly the
keys `pause`, `resume`, `cancel`; each action has exactly `enabled`, `reason`.
`reason` is `""` when `enabled` is true and one of the exact strings below when
it is false.

The state is `runState(run)`. **Integrate** (spec lines 44-46) means: `run.lease`
is an object and `run.lease.accepting !== true`.

Interpretation of the spec's "`accepting`" condition, pinned by tests: `accepting`
is only known when there is a lease. A run with `lease === null` (a parked or
escalated run whose lease was released, or a `started` run with no lease, which
`runState` calls dead) is **not** treated as being in Integrate, so its cancel
stays enabled; if `am` disagrees it refuses with `NotAcceptingError` and
`controlError` explains it. A `running` run always has a lease (runState
requires it), so for pause the literal rule "running and accepting" holds
exactly.

Reason strings (exact, no trailing period):

| name | text |
|---|---|
| INTEGRATE | `Integrate is running; it cannot be paused or cancelled` (verbatim, spec line 46) |
| FINISHED | `The run has finished` |
| UNKNOWN | `The run's state is unknown` |
| PAUSE_NOT_RUNNING | `Only a running run can be paused` |
| RESUME_RUNNING | `The run is still running` |
| RESUME_CANCELLED | `A cancelled run cannot be resumed` |
| CANCEL_CANCELLED | `The run is already cancelled` |

Decision table (Integrate column only matters where shown):

| state | pause | resume | cancel |
|---|---|---|---|
| running, not Integrate | enabled | RESUME_RUNNING | enabled |
| running, Integrate | INTEGRATE | RESUME_RUNNING | INTEGRATE |
| dead / parked / escalated, not Integrate (incl. lease null) | PAUSE_NOT_RUNNING | enabled | enabled |
| dead / parked / escalated, Integrate | PAUSE_NOT_RUNNING | enabled | INTEGRATE |
| cancelled (any lease) | FINISHED | RESUME_CANCELLED | CANCEL_CANCELLED |
| done (any lease) | FINISHED | FINISHED | FINISHED |
| unknown, and any garbage run (any lease) | UNKNOWN | UNKNOWN | UNKNOWN |

Precedence: the state reason wins over INTEGRATE (pause on a parked run in
Integrate says PAUSE_NOT_RUNNING; cancel on a done run says FINISHED). Resume
never looks at `accepting` (spec line 34; am's resume refuses a live lease with
`RunIsLiveError`, which is `controlError`'s job, not a gate here).

`run` may be a normalised run or anything else; `runState` already maps garbage to
`unknown`, and a lease that is not an object counts as no lease.

### `controlError(error)` → string

Reads the type as `errorText` does: if `error` is an object with `ok === true`,
return `""`; take `e = error.error` when that is an object, else `error`; the
type is `_textOf(e.type)` (trimmed `String`). Map:

| `type` | sentence |
|---|---|
| `UnknownRunError` | `The run no longer exists` |
| `NotRunningError` | `The run is not running` |
| `DeadRunError` | `The run's process has died; resume it instead` |
| `NotAcceptingError` | `Integrate is running; it cannot be paused or cancelled` (same text as INTEGRATE) |
| `RunIsLiveError` | `The run is still live; only a dead run can be resumed` |
| `NotResumableError` | `The run cannot be resumed` |
| `ClaimedError` | `Another run has already claimed this work` |
| `LockTimeoutError` | `am is busy; try again in a moment` |

Anything else (unknown or empty type, a non-object `error`, garbage) returns
`errorText(error)` unchanged — so an unknown type still shows
`"<type>: <message>"`, and garbage shows `"unknown error"`. The raw message
stays available to callers through `errorText` (spec line 61); `controlError`
does not include it for the eight known types. Type matching is exact and
case-sensitive after trimming (`" ClaimedError "` maps; `"claimederror"` does
not).

## Tests

Tier for all: pure domain QML `TestCase` in `tests/core/domain/tst_runs.qml`
(`TestCase { name: "DomainRuns" }`, `Runs` = runs.js), per `docs/architecture.md`
"Tests" (line 194) — both functions are pure and need no store, UI or backend.
Build runs with the existing `mkRun(id, status, live, opts)` helper
(tst_runs.qml:265); for Integrate set `run.lease.accepting = false` on the
result (or add an `accepting` opt to `mkRun` defaulting to `true`, without
changing existing callers).

| test | proves |
|---|---|
| `test_controls_shape` | keys are exactly `cancel,pause,resume`, each action's keys exactly `enabled,reason`; two calls return distinct objects; mutating one result leaves the next call unchanged |
| `test_controls_running` | running + accepting: pause and cancel enabled with `""`, resume RESUME_RUNNING; running + accepting false: pause and cancel INTEGRATE, resume unchanged |
| `test_controls_resumable_states` | for each of dead (`started`, live false), parked (`stopped`), escalated, each with lease accepting true, accepting false, and lease null: resume enabled; pause PAUSE_NOT_RUNNING; cancel enabled except accepting false → INTEGRATE. Also `started` with lease null (dead) → resume and cancel enabled |
| `test_controls_finished_states` | cancelled and done, each with accepting true, false and lease null: the table's reasons, all disabled |
| `test_controls_unknown_and_garbage` | status `""`, `"weird"`, and run `undefined`, `null`, `5`, `"x"`, `{}`, `[]`, `Runs.normalizeRun(undefined)`: all three disabled with UNKNOWN; never throws; a lease that is a string or array counts as no lease |
| `test_controls_from_normalized` | through `Runs.normalizeRun`: raw `accepting: "true"` or missing (normalised to false) puts a live started run in Integrate; raw `accepting: true` does not — pins that controls reads the normalised boolean |
| `test_control_error_table` | each of the 8 types, in envelope form, maps to its exact sentence |
| `test_control_error_shapes` | bare `{type, message}` maps the same as the envelope; type is trimmed; message is ignored for known types; case-sensitive (`"claimederror"` falls back) |
| `test_control_error_fallback` | unknown type gives `errorText` (`"Foo: bar"`, type-only, message-only); `ok:true` gives `""`; `undefined`, `null`, `"boom"`, `5`, `true`, `[]`, `{ok:false}` give `"unknown error"`; types `constructor`, `__proto__`, `toString`, `hasOwnProperty` fall back to `errorText`; a prototype-less type object does not throw |

Verification: `bash tests/run.sh` green (filter while iterating:
`bash tests/run.sh tst_runs`). Existing `tst_runs.qml` tests and the
`tests/architecture/` suite (layering, no duplicated components, icon glyph
rules) pass unchanged. There is no typecheck or lint step.

## Hand-off to the planner

**Files:**
- Modify: `core/domain/runs.js` (append section after `attemptStatus`, end of file)
- Test: `tests/core/domain/tst_runs.qml` (add `test_controls_*` / `test_control_error_*`
  before the closing brace; optionally extend `mkRun` with an `accepting` opt)

**Interfaces produced** (consumed later by RunStore / RunControls cards):
- `controls(run) -> {pause:{enabled:bool, reason:string}, resume:{...}, cancel:{...}}`
- `controlError(error) -> string`

Suggested tasks: (1) `controls` with its five tests; (2) `controlError` with its
three tests. Each is independently testable and reviewable.

## Review focus (inputs the tests above must not let slip)

1. Parked/escalated run with `lease: null` — cancel must stay enabled (not the
   Integrate reason).
2. Dead run whose lease says `accepting: false` — resume enabled, cancel INTEGRATE.
3. Error type that is an `Object.prototype` name — must fall back, never return
   a function or `undefined`.
4. `ok:true` envelope carrying an `error` — `""`, matching `errorText`.
5. Callers mutating a returned action object — later calls unaffected (no shared
   constants returned by reference).

---

# runs.js run controls and control error text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `controls(run)` and `controlError(error)` to `core/domain/runs.js`, test-first, with every test in `tests/core/domain/tst_runs.qml`.

**Architecture:** Both are pure, never-throwing functions appended to the existing `.pragma library` module in a new section after `attemptStatus` (the current end of the file). `controls` derives everything from the existing `runState(run)` plus one private `_inIntegrate(run)` check, and builds every action object fresh through `_action(reason)`. `controlError` reads the error type exactly as `errorText` does, matches it with `===` against a fixed array of `[type, sentence]` pairs by linear scan, and falls back to `errorText(error)` for anything else. Existing helpers `_isObject`, `_textOf`, `runState` and `errorText` are reused unchanged.

**Tech Stack:** QML JavaScript (`.pragma library`, `var`/function style, Qt 6 V4 engine), QtTest `TestCase` run by `qmltestrunner` through `tests/run.sh`, pytest architecture tests (must pass unchanged).

**Spec:** `docs/superpowers/specs/1-1-runs-js-controls-adff6c85.md` (prepended above). Parent design: `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2).

**Worktree / branch:** all paths are relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/ctl/task-1-1-runs-js-controls-adff6c85`, branch `ctl/task-1-1-runs-js-controls-adff6c85`. Run every command from that directory.

## Global Constraints

- `core/domain/runs.js` stays `.pragma library`; `var`/`function` style, no ES6 `const`/`let`/arrows, `_`-prefixed private helpers, one comment block above each function. No imports.
- No glyph literals: all text is plain ASCII (`tests/architecture/test_icon_glyphs.py` must stay green).
- No function throws. Garbage input (`undefined`, `null`, numbers, strings, `{}`, `[]`, prototype-less objects) becomes the default result.
- Error types are matched with `===` against a fixed list (linear scan), never by property lookup on a plain object, so `constructor`, `__proto__`, `toString` fall through to the fallback.
- Existing functions and their tests are not changed. `_isNonTerminal` is not the cancel rule; do not reuse or change it.
- No file under `ui/`, `core/stores/` or `core/backend/` is touched; `docs/architecture.md` is not edited. `newAlerts` is out of scope.
- Reason strings (exact, no trailing period): INTEGRATE `Integrate is running; it cannot be paused or cancelled`; FINISHED `The run has finished`; UNKNOWN `The run's state is unknown`; PAUSE_NOT_RUNNING `Only a running run can be paused`; RESUME_RUNNING `The run is still running`; RESUME_CANCELLED `A cancelled run cannot be resumed`; CANCEL_CANCELLED `The run is already cancelled`.
- Verification: `bash tests/run.sh` green (filter while iterating: `bash tests/run.sh tst_runs`). No typecheck, no lint.

## Review Focus

1. Parked/escalated (or dead) run with `lease: null` — a person expects Cancel to stay enabled, not to show the Integrate reason. Pinned by the "no lease" rows of `test_controls_resumable_states` (Task 1).
2. Dead run whose lease says `accepting: false` — Resume enabled, Cancel INTEGRATE, Pause PAUSE_NOT_RUNNING (state reason beats Integrate). Pinned by the "Integrate" row of `test_controls_resumable_states` (Task 1).
3. Error type that is an `Object.prototype` name (`constructor`, `__proto__`, `toString`, `hasOwnProperty`, `valueOf`) — must fall back to `errorText`, never return a function or `undefined`. Pinned by `test_control_error_fallback` (Task 2).
4. `ok:true` envelope carrying an `error` with a known type — `""`, matching `errorText`. Pinned by `test_control_error_fallback` (Task 2).
5. A caller mutating a returned action object (e.g. a store flipping `enabled` while a request is pending) — later calls unaffected, and no action shared between the three keys of one result. Pinned by `test_controls_shape` (Task 1).

## File Structure

- Modify: `core/domain/runs.js` — append a `// ---- Run controls (S2 1.1) ----` section after `attemptStatus` (currently lines 613-623, the end of the file). Task 1 adds the section banner, the reason constants, `_action`, `_inIntegrate` and `controls`; Task 2 appends `_CONTROL_ERRORS` and `controlError` below `controls`.
- Modify: `tests/core/domain/tst_runs.qml` — insert new properties, helpers and `test_*` functions immediately before the final line of the file, the lone `}` closing `TestCase { name: "DomainRuns" ... }` (currently line 1105, right after `test_runs_touching`). Existing content, including `mkRun` (line 267), is untouched.

---

### Task 1: `controls(run)`

**Files:**
- Modify: `core/domain/runs.js` (append after line 623, end of file)
- Test: `tests/core/domain/tst_runs.qml` (insert before the final `}`)

**Interfaces:**
- Consumes (existing, unchanged): `runState(run)` → `"running" | "dead" | "parked" | "escalated" | "cancelled" | "done" | "unknown"`; `_isObject(v)` → bool (true for non-null, non-array objects); test helper `mkRun(id, status, live, opts)` where `live === null` means `lease: null`, otherwise `lease = {pid:1, host:"h", heartbeat_at:"", accepting:true, live:live}`.
- Produces: `controls(run) -> {pause:{enabled:bool, reason:string}, resume:{enabled:bool, reason:string}, cancel:{enabled:bool, reason:string}}`; module constant `_REASON_INTEGRATE` (string, the INTEGRATE text) that Task 2 reuses for `NotAcceptingError`; test properties `ctlIntegrate`, `ctlFinished`, `ctlUnknown`, `ctlPauseNotRunning`, `ctlResumeRunning`, `ctlResumeCancelled`, `ctlCancelCancelled` (Task 2 uses `ctlIntegrate`).

- [ ] **Step 1: Write the failing tests**

Insert immediately before the final `}` of `tests/core/domain/tst_runs.qml` (i.e. after the closing `  }` of `test_runs_touching`):

```qml

  // ---- S2 1.1: run controls ----------------------------------------------------------------

  readonly property string ctlIntegrate: "Integrate is running; it cannot be paused or cancelled"
  readonly property string ctlFinished: "The run has finished"
  readonly property string ctlUnknown: "The run's state is unknown"
  readonly property string ctlPauseNotRunning: "Only a running run can be paused"
  readonly property string ctlResumeRunning: "The run is still running"
  readonly property string ctlResumeCancelled: "A cancelled run cannot be resumed"
  readonly property string ctlCancelCancelled: "The run is already cancelled"

  // mkRun with the lease's accepting flag set; live === null still means no lease.
  function ctlRun(status, live, accepting) {
    var r = mkRun("rc", status, live)
    if (r.lease !== null) r.lease.accepting = accepting
    return r
  }

  // One action of a controls() result: exactly {enabled, reason}; enabled iff reason is "".
  function checkAction(a, reason, label) {
    compare(Object.keys(a).sort().join(","), "enabled,reason", label + " keys")
    compare(a.enabled, reason === "", label + " enabled")
    compare(a.reason, reason, label + " reason")
  }

  // A whole controls() result; "" means that action is enabled.
  function checkControls(c, pause, resume, cancel, label) {
    compare(Object.keys(c).sort().join(","), "cancel,pause,resume", label + " keys")
    checkAction(c.pause, pause, label + " pause")
    checkAction(c.resume, resume, label + " resume")
    checkAction(c.cancel, cancel, label + " cancel")
  }

  function test_controls_shape() {
    var run = ctlRun("started", true, true)
    var a = Runs.controls(run)
    checkControls(a, "", ctlResumeRunning, "", "running")
    var b = Runs.controls(run)
    verify(a !== b, "a fresh result per call")
    verify(a.pause !== b.pause && a.resume !== b.resume && a.cancel !== b.cancel, "fresh actions per call")
    verify(a.pause !== a.resume && a.resume !== a.cancel && a.pause !== a.cancel, "no action shared within a result")
    a.pause.enabled = false
    a.pause.reason = "changed"
    a.resume.reason = "changed"
    delete a.cancel
    checkControls(Runs.controls(run), "", ctlResumeRunning, "", "after mutating an earlier result")

    var u = Runs.controls(undefined)
    verify(u.pause !== u.resume && u.resume !== u.cancel && u.pause !== u.cancel, "no action shared in an unknown result")
    u.pause.reason = "changed"
    u.resume.enabled = true
    checkControls(Runs.controls(null), ctlUnknown, ctlUnknown, ctlUnknown, "after mutating an unknown result")

    var d = Runs.controls(ctlRun("done", null, true))
    d.cancel.reason = ""
    d.cancel.enabled = true
    checkControls(Runs.controls(ctlRun("done", null, true)), ctlFinished, ctlFinished, ctlFinished, "after mutating a done result")
  }

  function test_controls_running() {
    compare(Runs.runState(ctlRun("started", true, true)), "running", "fixture")
    checkControls(Runs.controls(ctlRun("started", true, true)), "", ctlResumeRunning, "", "running, accepting")
    checkControls(Runs.controls(ctlRun("started", true, false)), ctlIntegrate, ctlResumeRunning, ctlIntegrate,
                  "running, Integrate")
  }

  function test_controls_resumable_states() {
    var states = [["started", "dead"], ["stopped", "parked"], ["escalated", "escalated"]]
    for (var i = 0; i < states.length; i++) {
      var status = states[i][0], label = states[i][1]
      compare(Runs.runState(ctlRun(status, false, true)), label, label + " fixture")
      compare(Runs.runState(ctlRun(status, null, true)), label, label + " fixture, no lease")
      checkControls(Runs.controls(ctlRun(status, false, true)), ctlPauseNotRunning, "", "", label + ", accepting")
      checkControls(Runs.controls(ctlRun(status, false, false)), ctlPauseNotRunning, "", ctlIntegrate,
                    label + ", Integrate")
      checkControls(Runs.controls(ctlRun(status, null, false)), ctlPauseNotRunning, "", "",
                    label + ", no lease is not Integrate")
    }
  }

  function test_controls_finished_states() {
    var leases = [[false, true, "accepting"], [false, false, "Integrate"], [true, false, "live, Integrate"],
                  [null, true, "no lease"]]
    for (var i = 0; i < leases.length; i++) {
      var live = leases[i][0], accepting = leases[i][1], label = leases[i][2]
      compare(Runs.runState(ctlRun("cancelled", live, accepting)), "cancelled", "fixture " + label)
      checkControls(Runs.controls(ctlRun("cancelled", live, accepting)),
                    ctlFinished, ctlResumeCancelled, ctlCancelCancelled, "cancelled, " + label)
      compare(Runs.runState(ctlRun("done", live, accepting)), "done", "fixture " + label)
      checkControls(Runs.controls(ctlRun("done", live, accepting)),
                    ctlFinished, ctlFinished, ctlFinished, "done, " + label)
    }
  }

  function test_controls_unknown_and_garbage() {
    var runs = [ctlRun("", true, true), ctlRun("weird", true, false), ctlRun("STARTED", true, true),
                ctlRun("weird", null, true), undefined, null, 5, "x", {}, [], Object.create(null),
                Runs.normalizeRun(undefined)]
    for (var i = 0; i < runs.length; i++)
      checkControls(Runs.controls(runs[i]), ctlUnknown, ctlUnknown, ctlUnknown, "unknown " + i)

    // A lease that is not an object counts as no lease: never Integrate.
    var arrayLease = []
    arrayLease.accepting = false
    var badLeases = ["x", 5, [], arrayLease]
    for (var j = 0; j < badLeases.length; j++) {
      checkControls(Runs.controls({ status: "stopped", lease: badLeases[j] }), ctlPauseNotRunning, "", "",
                    "parked, lease " + j)
      checkControls(Runs.controls({ status: "started", lease: badLeases[j] }), ctlPauseNotRunning, "", "",
                    "dead, lease " + j)
    }
  }

  function test_controls_from_normalized() {
    function raw(lease) {
      return { status: { run: { id: "r", status: "started" }, control: { lease: lease } } }
    }
    var stringTrue = Runs.normalizeRun(raw({ pid: 1, live: true, accepting: "true" }))
    compare(stringTrue.lease.accepting, false, "normalised to false")
    checkControls(Runs.controls(stringTrue), ctlIntegrate, ctlResumeRunning, ctlIntegrate, "accepting \"true\"")
    checkControls(Runs.controls(Runs.normalizeRun(raw({ pid: 1, live: true }))),
                  ctlIntegrate, ctlResumeRunning, ctlIntegrate, "accepting missing")
    checkControls(Runs.controls(Runs.normalizeRun(raw({ pid: 1, live: true, accepting: true }))),
                  "", ctlResumeRunning, "", "accepting true")
    checkControls(Runs.controls(Runs.normalizeRun(raw(null))), ctlPauseNotRunning, "", "", "no lease: dead")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes; under `== tests/core/domain/tst_runs.qml` the six `test_controls_*` functions print `FAIL!  : qmltestrunner::DomainRuns::test_controls_...() Uncaught exception: Property 'controls' of object [object Object] is not a function` (Totals: 52 passed, 6 failed); every existing test still passes; the script exits non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js` (after the closing `}` of `attemptStatus`, preceded by one blank line):

```js

// ---- Run controls (S2 1.1) ---------------------------------------------------------------
//
// Which of pause / resume / cancel a run allows, and the sentence for an am
// control error. Pure and never throwing, like the rest of this file. Whether a
// request is already outstanding is the store's business, not these functions'.

var _REASON_INTEGRATE = "Integrate is running; it cannot be paused or cancelled"
var _REASON_FINISHED = "The run has finished"
var _REASON_UNKNOWN = "The run's state is unknown"
var _REASON_PAUSE_NOT_RUNNING = "Only a running run can be paused"
var _REASON_RESUME_RUNNING = "The run is still running"
var _REASON_RESUME_CANCELLED = "A cancelled run cannot be resumed"
var _REASON_CANCEL_CANCELLED = "The run is already cancelled"

// A fresh {enabled, reason}: enabled exactly when there is no reason.
function _action(reason) { return { enabled: reason === "", reason: reason } }

// Integrate: the run holds a lease (an object) that is not accepting requests.
// With no lease, accepting is unknown, so the run is not treated as in Integrate.
function _inIntegrate(run) {
  return _isObject(run) && _isObject(run.lease) && run.lease.accepting !== true
}

// {pause, resume, cancel}, each a fresh {enabled, reason}; reason is "" when
// enabled. Pause needs a running run outside Integrate; resume needs dead,
// parked or escalated and never looks at accepting; cancel needs a run that has
// not finished and is not in Integrate. The state's reason wins over Integrate's.
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
    resume = ""
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
  return { pause: _action(pause), resume: _action(resume), cancel: _action(cancel) }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs`
Expected: pytest passes (including `tests/architecture/`); `tst_runs.qml` prints `Totals: 58 passed, 0 failed`, no `FAIL!` lines, no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): controls says which of pause, resume and cancel a run allows (card adff6c85)"
```

---

### Task 2: `controlError(error)` and full verification

**Files:**
- Modify: `core/domain/runs.js` (append after `controls`, end of file)
- Test: `tests/core/domain/tst_runs.qml` (insert before the final `}`, after `test_controls_from_normalized`)

**Interfaces:**
- Consumes: `_REASON_INTEGRATE` (Task 1); existing `_isObject(v)`, `_textOf(v)` (trimmed `String(v)`, `""` for null/undefined/unconvertible) and `errorText(error)` (`"type: message"`, either alone, `"unknown error"`, or `""` for `ok:true`); test property `ctlIntegrate` (Task 1).
- Produces: `controlError(error) -> string`.

- [ ] **Step 1: Write the failing tests**

Insert immediately before the final `}` of `tests/core/domain/tst_runs.qml` (after the closing `  }` of `test_controls_from_normalized`):

```qml

  // [type, sentence] for every am control error controlError knows.
  function controlErrorTable() {
    return [
      ["UnknownRunError", "The run no longer exists"],
      ["NotRunningError", "The run is not running"],
      ["DeadRunError", "The run's process has died; resume it instead"],
      ["NotAcceptingError", ctlIntegrate],
      ["RunIsLiveError", "The run is still live; only a dead run can be resumed"],
      ["NotResumableError", "The run cannot be resumed"],
      ["ClaimedError", "Another run has already claimed this work"],
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
  }

  function test_control_error_table() {
    var table = controlErrorTable()
    compare(table.length, 8)
    for (var i = 0; i < table.length; i++)
      compare(Runs.controlError({ ok: false, error: { type: table[i][0], message: "am said so" } }), table[i][1],
              table[i][0])
    compare(Runs.controlError({ ok: false, error: { type: "NotAcceptingError", message: "m" } }),
            "Integrate is running; it cannot be paused or cancelled", "same text as the Integrate reason")
  }

  function test_control_error_shapes() {
    var table = controlErrorTable()
    for (var i = 0; i < table.length; i++) {
      compare(Runs.controlError({ type: table[i][0], message: "x" }), table[i][1], "bare " + table[i][0])
      compare(Runs.controlError({ type: table[i][0] }), table[i][1], "bare, no message " + table[i][0])
    }
    compare(Runs.controlError({ ok: false, error: { type: "  ClaimedError  ", message: "m" } }),
            "Another run has already claimed this work", "type is trimmed")
    compare(Runs.controlError({ type: "\tLockTimeoutError\n" }), "am is busy; try again in a moment", "trimmed, bare")
    compare(Runs.controlError({ ok: false, error: { type: "DeadRunError", message: "pid 42 is gone" } }),
            "The run's process has died; resume it instead", "the message is not shown for a known type")
    compare(Runs.controlError({ ok: false, error: { type: "claimederror", message: "m" } }), "claimederror: m",
            "case-sensitive")
    compare(Runs.controlError({ type: "CLAIMEDERROR" }), "CLAIMEDERROR", "case-sensitive, bare")
    compare(Runs.controlError({ ok: false, type: "ClaimedError", error: { type: "Foo", message: "bar" } }), "Foo: bar",
            "the envelope's error wins over a stray outer type, as in errorText")
    var bare = Object.create(null)
    bare.type = "ClaimedError"
    compare(Runs.controlError(bare), "Another run has already claimed this work", "prototype-less bare error")
  }

  function test_control_error_fallback() {
    compare(Runs.controlError({ ok: false, error: { type: "Foo", message: "bar" } }), "Foo: bar", "unknown type")
    compare(Runs.controlError({ ok: false, error: { type: "Foo" } }), "Foo", "type only")
    compare(Runs.controlError({ ok: false, error: { message: "bar" } }), "bar", "message only")
    compare(Runs.controlError({ ok: true, error: { type: "ClaimedError", message: "m" } }), "", "ok:true with an error")
    compare(Runs.controlError({ ok: true }), "", "ok:true")

    var garbage = [undefined, null, "boom", 5, true, [], { ok: false }, {}, { ok: false, error: "ClaimedError" },
                   { ok: false, error: { type: "", message: "  " } }, Object.create(null)]
    for (var i = 0; i < garbage.length; i++)
      compare(Runs.controlError(garbage[i]), "unknown error", "garbage " + i)

    var protoNames = ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]
    for (var k = 0; k < protoNames.length; k++) {
      var name = protoNames[k]
      compare(Runs.controlError({ ok: false, error: { type: name, message: "m" } }), name + ": m", "envelope " + name)
      compare(Runs.controlError({ type: name }), name, "bare " + name)
      compare(typeof Runs.controlError({ type: name }), "string", "a string for " + name)
    }

    var noProto = Object.create(null)
    compare(Runs.controlError({ ok: false, error: { type: noProto, message: "m" } }), "m",
            "a prototype-less type object reads as no type")
    compare(Runs.controlError({ type: noProto }), "unknown error", "a prototype-less type object alone")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_runs`
Expected: the three `test_control_error_*` functions print `FAIL!  : qmltestrunner::DomainRuns::test_control_error_...() Uncaught exception: Property 'controlError' of object [object Object] is not a function` (Totals: 58 passed, 3 failed); all Task 1 and existing tests still pass; exit status non-zero.

- [ ] **Step 3: Write the implementation**

Append to the end of `core/domain/runs.js` (after the closing `}` of `controls`, preceded by one blank line):

```js

// [type, sentence] for each am control error, matched with === by linear scan so
// a type such as `constructor` or `__proto__` is just an unknown type.
var _CONTROL_ERRORS = [
  ["UnknownRunError", "The run no longer exists"],
  ["NotRunningError", "The run is not running"],
  ["DeadRunError", "The run's process has died; resume it instead"],
  ["NotAcceptingError", _REASON_INTEGRATE],
  ["RunIsLiveError", "The run is still live; only a dead run can be resumed"],
  ["NotResumableError", "The run cannot be resumed"],
  ["ClaimedError", "Another run has already claimed this work"],
  ["LockTimeoutError", "am is busy; try again in a moment"]
]

// The sentence for a failed pause / resume / cancel. Reads the type the way
// errorText does (envelope or bare, trimmed, case-sensitive); a known type gives
// its sentence without am's message, anything else gives errorText(error).
function controlError(error) {
  if (_isObject(error) && error.ok !== true) {
    var e = _isObject(error.error) ? error.error : error
    var type = _textOf(e.type)
    for (var i = 0; i < _CONTROL_ERRORS.length; i++) {
      if (_CONTROL_ERRORS[i][0] === type) return _CONTROL_ERRORS[i][1]
    }
  }
  return errorText(error)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_runs`
Expected: `tst_runs.qml` prints `Totals: 61 passed, 0 failed`, no `FAIL!`/`TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py` and `tests/architecture/test_icon_glyphs.py`); every `tst_*.qml` prints `Totals:` with 0 failed; no `FAIL!`, `TypeError` or `ReferenceError` lines; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): controlError turns an am control error into a sentence (card adff6c85)"
```

---

## Self-Review

- **Spec coverage:** `controls` decision table — running (Task 1 `test_controls_running`), dead/parked/escalated incl. lease null and Integrate (`test_controls_resumable_states`), cancelled/done any lease (`test_controls_finished_states`), unknown and garbage incl. non-object leases (`test_controls_unknown_and_garbage`), normalised boolean (`test_controls_from_normalized`), shape/fresh objects (`test_controls_shape`). Precedence (state reason over INTEGRATE) is pinned by the Integrate rows of the resumable and finished tests. `controlError` — eight types (`test_control_error_table`), bare form, trimming, message ignored, case sensitivity (`test_control_error_shapes`), unknown type, `ok:true`, garbage, prototype names, prototype-less type (`test_control_error_fallback`). Section banner and placement after `attemptStatus`: Task 1 Step 3. Verification `bash tests/run.sh`: Task 2 Step 5.
- **Placeholder scan:** none; every code step carries the full code.
- **Type consistency:** `controls`, `controlError`, `_action`, `_inIntegrate`, `_REASON_INTEGRATE`, `_CONTROL_ERRORS`, and test helpers `ctlRun`, `checkAction`, `checkControls`, `controlErrorTable`, `ctl*` properties are named identically wherever used.
- **Review Focus:** all five lines are pinned by named tests in their owning task.
<!-- task-pipeline: validated -->
