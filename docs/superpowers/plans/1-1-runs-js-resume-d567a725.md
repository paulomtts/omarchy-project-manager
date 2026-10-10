# 1.1 runs.js: resume refusals in user terms (card d567a725)

Narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md` (the
"resume and recover" design, here **RR**): "What `am` does" (lines 80-105, above all the
escalated-`task` rule at 91-94 and the refusal list at 95-101), "Refusals in user terms"
(lines 216-232), "Architecture" bullet `core/domain/runs.js` (lines 236-242) and "Testing"
bullet 1 (lines 302-303). Parent story 7d1f5810. No blockers.

## Starting point

`core/domain/runs.js` (`.pragma library`), section `// ---- Run controls (S2 1.1)`
(`runs.js:860-940`), already has:

- `_REASON_*` string vars (`runs.js:866-872`), `_action(reason)`, `_inIntegrate(run)` and
  `controls(run)` (`runs.js:887-914`). `controls` gives resume `""` (enabled) for the states
  `dead`, `parked` and `escalated` alike (`runs.js:895-898`).
- `_CONTROL_ERRORS`, a `[type, sentence]` array scanned with `===` (`runs.js:917-926`), and
  `controlError(error)` (`runs.js:931-940`), which reads the type as: `error` is an object
  (`_isObject`) whose `ok !== true`; `e` is `error.error` when that is an object, else
  `error`; type is `_textOf(e.type)` (trimmed `String`, `""` for null/undefined or an
  unconvertible value). Unknown types fall back to `errorText(error)`.
- `normalizeRun` sets a top-level trimmed string `workflow` (`runs.js:135`). Every recorded
  fixture under `tests/fixtures/am/` has `workflow: "milestone"`; none is a `task` run.
- `runState(run)` maps `status: "escalated"` to `escalated` (`runs.js:150-161`).

The only consumers outside the file are `core/stores/RunStore.qml` (`Runs.controlError` for
the failure sentence, `Runs.controls(...).resume.reason` for a refused resume). They need no
change: they pass through whatever text these functions return.

## Scope

Change `controls` and `controlError` and add `offersRelaunch` in the existing
`// ---- Run controls (S2 1.1)` section of `core/domain/runs.js`, with tests in
`tests/core/domain/tst_runs.qml`. Tests first.

Constraints:

- `runs.js` is a hot file: the diff stays inside `controls`, `_CONTROL_ERRORS`,
  `controlError`'s neighbourhood and one new `_REASON_*` var (RR line 237-238).
- File style (inherited from the S2 1.1 card spec `1-1-runs-js-controls-adff6c85.md` and
  `docs/architecture.md` line 157, "pure JS, never throws, and every input comes from
  `am`"): `var`/`function`, no `const`/`let`/arrows, `_`-prefixed private names, one
  contract-only comment above each function (no narrative). Plain ASCII text only, so the
  icon-glyph architecture tests are unaffected; no new component.
- No function throws on any input.
- Error types are still matched with `===` by linear scan, never by property lookup, so
  `constructor`, `__proto__`, `toString` are unknown types.

### Out of scope

Everything else in RR, owned by sibling cards: `stopReport`, `stopComment`,
`defaultAttempt`/attempt-0 selection, `RunStore`'s `lastControlErrorType`, the resume dialog
and its section, `relaunchOpenFor`, `VerifyCommandsField`, `ResumeVerifyDialog`,
`StopReasonBlock`, `RunDetailScreen` wiring, the backend logs change, UI flow tests and docs.
No file under `ui/`, `core/stores/` or `core/backend/` is touched. The sentences for
`UnknownRunError`, `NotRunningError`, `NotAcceptingError`, `ClaimedError` and
`LockTimeoutError` are not changed. `controls` for every state other than `escalated` is not
changed, and neither are pause and cancel for any run.

## Behaviour

### `controls(run)`: escalated card runs

A run is an **escalated card run** when `runState(run) === "escalated"` and
`_textOf(run.workflow) === "task"` (trimmed, case-sensitive; RR lines 91-94: am never
resumes an escalated subtask of a `task` run, `NotResumableError`).

| run | pause | resume | cancel |
|---|---|---|---|
| escalated card run | `Only a running run can be paused` (unchanged) | **disabled**: `An escalated card run cannot be resumed; relaunch it` (RR line 232) | as today: `Integrate is running; it cannot be paused or cancelled` when `_inIntegrate(run)`, else enabled |
| escalated, any other `workflow` (`"milestone"`, `""`, missing, `"Task"`, `"tasks"`, a number, an object) | unchanged | unchanged: enabled | unchanged |
| `dead` or `parked` with `workflow: "task"` | unchanged | unchanged: enabled (a killed or stopped card run is resumable, RR line 82) | unchanged |
| every other state | unchanged | unchanged | unchanged |

The new reason is a private var `_REASON_RESUME_ESCALATED_CARD` with exactly that text.
The result keeps its shape: a fresh `{pause, resume, cancel}` of fresh `{enabled, reason}`
per call, `enabled === (reason === "")`.

### `controlError(error)`: new sentences

`_CONTROL_ERRORS` becomes, in this order (RR lines 222-227 for the four changed/added rows):

| type | sentence |
|---|---|
| `UnknownRunError` | The run no longer exists |
| `NotRunningError` | The run is not running |
| `DeadRunError` | The run's process has died, so nobody can act on this request. Resume picks the run up. |
| `NotAcceptingError` | Integrate is running; it cannot be paused or cancelled |
| `RunIsLiveError` | Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died. |
| `NotResumableError` | am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work. |
| `CheckpointMismatchError` (new) | The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase. |
| `ClaimedError` | Another run has already claimed this work |
| `LockTimeoutError` | am is busy; try again in a moment |

Sentences are copied verbatim, including the final period where the table has one.
Everything else about `controlError` is unchanged: envelope and bare both read, the type
trimmed and case-sensitive, a known type returns its sentence without am's message, the
envelope's `error` wins over a stray outer `type`, an `ok: true` input and anything unknown
or garbage return `errorText(error)`.

### `offersRelaunch(error)` (new)

Placed directly after `controlError`. Returns the boolean `true` exactly when the type
`controlError` would read is `NotResumableError` or `CheckpointMismatchError` (RR lines
225-226, 229-230, 240-242); `false` (the boolean, never `undefined`, `null` or another
falsy value) for everything else. Reading the type is exactly `controlError`'s:

- `error` must be an object (`_isObject`: not null, not an array) with `ok !== true`;
  otherwise `false`.
- `e` is `error.error` when that is an object, else `error` itself.
- the type is `_textOf(e.type)`: trimmed, case-sensitive; a prototype-less type object
  reads as `""`.
- matched with `===` against the two names, so `__proto__`, `constructor` and the like are
  `false`.

So: `{ok:false, error:{type:"NotResumableError", message:"m"}}` → `true`;
`{type:" CheckpointMismatchError "}` → `true`; `{ok:false, type:"NotResumableError",
error:{type:"Foo"}}` → `false` (the envelope's error wins); `{ok:false,
error:"NotResumableError"}` → `false` (the error is not an object, so the outer object is
read, and it has no type); `{ok:true, error:{type:"NotResumableError"}}` → `false`;
`notresumableerror` → `false`; `RunIsLiveError`, `DeadRunError` and every other table type →
`false`. Never throws.

## Error paths

None of the three functions throws. Garbage (`undefined`, `null`, numbers, strings,
booleans, `[]`, `{}`, prototype-less objects, `normalizeRun(undefined)`) gives the existing
defaults for `controls` and `controlError`, and `false` for `offersRelaunch`.

## Tests (all in `tests/core/domain/tst_runs.qml`, section `// ---- S2 1.1: run controls`)

Tier: QML unit tests run by `qmltestrunner` through `bash tests/run.sh`. These are pure
functions of a `.pragma library` file with no I/O, so the domain unit tier is the right and
only tier (RR "Testing" bullet 1, lines 302-303); no store, backend or UI test is needed
because no consumer's behaviour changes beyond the text it passes through.

Helpers: add `readonly property string ctlResumeEscalatedCard: "An escalated card run cannot
be resumed; relaunch it"` beside the other `ctl*` strings; build an escalated card run by
setting `workflow` on a `ctlRun(...)` result (`mkRun` takes no workflow) or on a copy of the
normalized `status-escalated.json` fixture (`Runs.normalizeRun(amRun("status-escalated.json"))`,
then `r.workflow = "task"`). Reuse `checkControls`/`checkAction`.

1. **Escalated task run, synthetic** — `ctlRun("escalated", false, true)` with
   `workflow: "task"`: pause `ctlPauseNotRunning`, resume `ctlResumeEscalatedCard`
   (disabled), cancel `""`; with `accepting: false`: cancel `ctlIntegrate`; with no lease:
   cancel `""`; with `workflow: "  task  "`: same as `"task"`.
2. **Escalated task run, from the fixture** — the normalized `status-escalated.json` with
   `workflow` set to `"task"`: resume `ctlResumeEscalatedCard`, pause `ctlPauseNotRunning`,
   cancel `""` (its lease is null).
3. **Escalated milestone run unchanged** — the normalized `status-escalated.json` as recorded
   (`workflow: "milestone"`): resume `""`, pause `ctlPauseNotRunning`, cancel `""`.
4. **Other workflows stay resumable** — escalated with `workflow` `""`, missing, `"Task"`,
   `"TASK"`, `"tasks"`, `5`, `{}`, `null`, a prototype-less object: resume `""`.
5. **Only escalated is affected** — `workflow: "task"` on dead (`started`, not live), parked
   (`stopped`): resume `""`; running: `ctlResumeRunning`; cancelled (both spellings):
   `ctlResumeCancelled`; done: `ctlFinished`.
6. **Fresh result** — two calls on the same escalated card run give distinct result and
   action objects, and mutating the first does not change the second.
7. **Every sentence** — `controlErrorTable()` updated to the nine rows above (length 9);
   the existing `test_control_error_table` (envelope) and `test_control_error_shapes` (bare,
   bare without message) cover each row; update the `DeadRunError` "message is not shown"
   assertion to the new sentence. Existing fallback and prototype-name tests stay as they
   are and still pass.
8. **offersRelaunch, every table type** — for each of the nine types, envelope
   `{ok:false, error:{type, message:"m"}}` and bare `{type}` give `true` for
   `NotResumableError` and `CheckpointMismatchError` and `false` for the other seven;
   `typeof` the result is `"boolean"` in every case.
9. **offersRelaunch, reading** — trimmed (`"  NotResumableError\n"` envelope and bare →
   `true`); case-sensitive (`"notresumableerror"`, `"CHECKPOINTMISMATCHERROR"` → `false`);
   prototype-less bare error with `type: "CheckpointMismatchError"` → `true`; envelope wins
   over a stray outer type (`{ok:false, type:"NotResumableError", error:{type:"Foo"}}` →
   `false`, and `{ok:false, type:"Foo", error:{type:"NotResumableError"}}` → `true`);
   `{ok:true, error:{type:"NotResumableError"}}` → `false`; `{ok:false,
   error:"NotResumableError"}` → `false`.
10. **offersRelaunch, unknown and garbage** — unknown type `"Foo"`; `""`; prototype names
    (`constructor`, `__proto__`, `toString`, `hasOwnProperty`, `valueOf`) envelope and bare;
    a prototype-less type object; `undefined`, `null`, `"NotResumableError"` (a string),
    `5`, `true`, `[]`, `{}`, `{ok:false}`, `{ok:true}`, `Object.create(null)`, an array with
    a `type` property set to `"NotResumableError"` → all `false`, `typeof` `"boolean"`.

Existing tests that must keep passing unchanged: `test_controls_shape`,
`test_controls_running`, `test_controls_resumable_states` (its `ctlRun` has no workflow, so
escalated stays resumable), `test_controls_finished_states`,
`test_fixture_cancel_spellings_controls`, `test_controls_unknown_and_garbage`,
`test_controls_from_normalized`, `test_control_error_fallback`.

## Verification

`bash tests/run.sh` green (pytest, then every `tst_*.qml`, including `tests/architecture`).
Fast loop: `bash tests/run.sh tst_runs`.

---

# 1.1 runs.js: resume refusals in user terms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refuse resume on an escalated `task` run in `controls`, rewrite the am refusal sentences in `controlError` (plus a new `CheckpointMismatchError` row), and add `offersRelaunch(error)`. All three are pure functions in `core/domain/runs.js`.

**Architecture:** Every change stays in the `// ---- Run controls (S2 1.1)` section of `core/domain/runs.js` (`.pragma library`, pure, never throws). `controls` gets one extra condition in its dead/parked/escalated branch. `_CONTROL_ERRORS` gets new sentences and a ninth row. A private `_controlErrorType(error)` holds the type reading that `controlError` already does, so the new `offersRelaunch` reads the type the same way. Tests go first, in the `// ---- S2 1.1: run controls` section of `tests/core/domain/tst_runs.qml`.

**Tech Stack:** QML/JS (`.pragma library`, ES5 style: `var`/`function`), QtTest via `qmltestrunner`, driven by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-1-runs-js-resume-d567a725.md` (copied in full at the top of this file). It is narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md`.

## Global Constraints

- Change only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml`. Do not touch any file under `ui/`, `core/stores/` or `core/backend/`.
- The `runs.js` diff stays inside `controls`, `_CONTROL_ERRORS`, `controlError`'s neighbourhood and one new `_REASON_*` var.
- Style: `var`/`function` only, no `const`/`let`/arrow functions. Private names start with `_`. Each function gets one comment above it that states its contract, with no narrative.
- Plain ASCII text only. Add no new component.
- No function throws on any input.
- Error types are matched with `===` by a linear scan, never by property lookup. `constructor`, `__proto__` and `toString` are unknown types.
- New refusal reason, verbatim: `An escalated card run cannot be resumed; relaunch it`
- Sentences, verbatim: `DeadRunError` → `The run's process has died, so nobody can act on this request. Resume picks the run up.`; `RunIsLiveError` → `Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died.`; `NotResumableError` → `am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work.`; `CheckpointMismatchError` → `The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase.`
- Leave these sentences as they are: `UnknownRunError`, `NotRunningError`, `NotAcceptingError`, `ClaimedError`, `LockTimeoutError`.
- Process safety: never use `pkill`/`killall`/pattern kills. Wrap long runs in `timeout`.

## Review Focus

1. **`workflow` reaches the run only through `normalizeRun`.** In real am output the workflow comes from the `am runs` row or from `am status` `run.workflow`, often padded or present on only one side. An escalated run with `workflow: "task"` on either side must refuse resume. Pinned in Task 1, `test_controls_escalated_card_run_normalized`.
2. **An escalated card run whose lease is still live.** A lease left over from a crashed process can still say `live: true`. Resume must stay refused, and the state stays `escalated` because the lease only matters for `started`. Pinned in Task 1, inside `test_controls_escalated_card_run`.
3. **Non-ASCII text in the new sentences.** A curly apostrophe pasted into "run's" would break the plain-ASCII rule and the icon-glyph architecture tests. Pinned in Task 2, `test_control_sentences_are_ascii`.
4. **`offersRelaunch` on what RunStore actually holds.** RunStore passes in a `JSON.parse`d am reply. A reply whose JSON has an own `"__proto__"` key must not be read through the prototype. Pinned in Task 3, `test_offers_relaunch_parsed_json`.
5. **`offersRelaunch` and `controlError` must agree.** The UI will show a Relaunch button next to the sentence. When `offersRelaunch` is true, the sentence must be one of the two Relaunch sentences, on every input. Pinned in Task 3, `test_offers_relaunch_agrees_with_control_error`.

Already checked (no task needed): no test or file outside the two in scope hardcodes the old sentences. `tests/core/stores/tst_run_store.qml:2801,2810` compares against `Runs.controlError(...)` itself. The Cancel modal text in `ui/Panel.qml:833` / `tests/ui/tst_runs_flow.qml:407` is a different string and is not touched.

## Test commands

- Fast loop: `timeout 600 bash tests/run.sh domain/tst_runs`. This runs pytest, then only `tests/core/domain/tst_runs.qml`. Read the `== tests/core/domain/tst_runs.qml` block: its `FAIL!` lines and the `Totals:` line.
- Full gate: `timeout 1200 bash tests/run.sh`. It must exit 0 with `0 failed` on every `Totals:` line.

---

### Task 1: `controls` refuses resume on an escalated card run

**Files:**
- Modify: `core/domain/runs.js:866-872` (add one `_REASON_*` var), `core/domain/runs.js:885-898` (`controls` comment and the dead/parked/escalated branch)
- Test: `tests/core/domain/tst_runs.qml` (S2 1.1 section: add a `ctl*` string after line 2151, add a helper after `ctlRun` at lines 2154-2158, and add tests after `test_controls_from_normalized`, which ends near line 2280)

**Interfaces:**
- Consumes: the existing `runState(run)`, `_textOf(v)`, `_inIntegrate(run)` and `_action(reason)` in `runs.js`, and the existing test helpers `mkRun`, `ctlRun(status, live, accepting)`, `checkControls(c, pause, resume, cancel, label)`, `amRun(name)`, `cancelSpellings()`.
- Produces: `controls(run)` keeps its signature and returns `{pause, resume, cancel}`. `resume.reason` is `"An escalated card run cannot be resumed; relaunch it"` when `runState(run) === "escalated"` and `_textOf(run.workflow) === "task"`. Test helpers `ctlResumeEscalatedCard` (string property) and `ctlRunOf(status, live, accepting, workflow)`.

- [ ] **Step 1: Add the test helpers**

In `tests/core/domain/tst_runs.qml`, add this line directly after `readonly property string ctlCancelCancelled: "The run is already cancelled"`:

```qml
  readonly property string ctlResumeEscalatedCard: "An escalated card run cannot be resumed; relaunch it"
```

Add this function directly after the closing `}` of `function ctlRun(status, live, accepting) { ... }`:

```qml
  // ctlRun with a `workflow` (mkRun sets none); an escalated "task" run is an escalated card run.
  function ctlRunOf(status, live, accepting, workflow) {
    var r = ctlRun(status, live, accepting)
    r.workflow = workflow
    return r
  }
```

- [ ] **Step 2: Write the failing tests**

Add these functions directly after the closing `}` of `function test_controls_from_normalized() { ... }`, before the `// [type, sentence] for every am control error controlError knows.` comment:

```qml
  function test_controls_escalated_card_run() {
    var run = ctlRunOf("escalated", false, true, "task")
    compare(Runs.runState(run), "escalated", "fixture")
    checkControls(Runs.controls(run), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, accepting")
    checkControls(Runs.controls(ctlRunOf("escalated", false, false, "task")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, ctlIntegrate, "task, Integrate")
    checkControls(Runs.controls(ctlRunOf("escalated", null, false, "task")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, no lease is not Integrate")
    checkControls(Runs.controls(ctlRunOf("escalated", false, true, "  task  ")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, padded")
    checkControls(Runs.controls(ctlRunOf("escalated", false, true, "\ttask\n")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, tab and newline")
    var liveRun = ctlRunOf("escalated", true, true, "task")
    compare(Runs.runState(liveRun), "escalated", "a live lease does not change an escalated state")
    checkControls(Runs.controls(liveRun), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, live lease")
  }

  function test_controls_escalated_card_run_from_fixture() {
    var r = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(r.workflow, "milestone", "recorded workflow")
    r.workflow = "task"
    compare(r.lease, null, "the capture has no lease")
    checkControls(Runs.controls(r), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "escalated capture as a task run")
  }

  function test_controls_escalated_milestone_run_unchanged() {
    var r = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(r.workflow, "milestone", "recorded workflow")
    compare(Runs.runState(r), "escalated", "recorded state")
    checkControls(Runs.controls(r), ctlPauseNotRunning, "", "", "escalated milestone capture")
  }

  function test_controls_escalated_card_run_normalized() {
    // synthetic: the workflow from only the `am runs` row, or only `am status`
    var fromRow = Runs.normalizeRun({ row: { id: "r", status: "escalated", workflow: " task " } })
    checkControls(Runs.controls(fromRow), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "workflow on the row")
    var fromStatus = Runs.normalizeRun({ status: { run: { id: "r", status: "escalated", workflow: "task" } } })
    checkControls(Runs.controls(fromStatus), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "workflow in am status")
    var rowWins = Runs.normalizeRun({ row: { id: "r", workflow: "milestone" },
                                      status: { run: { id: "r", status: "escalated", workflow: "task" } } })
    checkControls(Runs.controls(rowWins), ctlPauseNotRunning, "", "", "the row's milestone workflow wins")
  }

  function test_controls_escalated_other_workflows_resumable() {
    var noProto = Object.create(null)
    var workflows = ["", "Task", "TASK", "tasks", "task run", "milestone", 5, {}, null, undefined, noProto]
    for (var i = 0; i < workflows.length; i++)
      checkControls(Runs.controls(ctlRunOf("escalated", false, true, workflows[i])), ctlPauseNotRunning, "", "",
                    "escalated, workflow " + i)
    checkControls(Runs.controls(ctlRun("escalated", false, true)), ctlPauseNotRunning, "", "",
                  "escalated, workflow missing")
  }

  function test_controls_task_run_other_states() {
    checkControls(Runs.controls(ctlRunOf("started", false, true, "task")), ctlPauseNotRunning, "", "", "dead task run")
    checkControls(Runs.controls(ctlRunOf("started", null, true, "task")), ctlPauseNotRunning, "", "",
                  "dead task run, no lease")
    checkControls(Runs.controls(ctlRunOf("stopped", false, true, "task")), ctlPauseNotRunning, "", "", "parked task run")
    checkControls(Runs.controls(ctlRunOf("started", true, true, "task")), "", ctlResumeRunning, "", "running task run")
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++)
      checkControls(Runs.controls(ctlRunOf(spellings[i], false, true, "task")),
                    ctlFinished, ctlResumeCancelled, ctlCancelCancelled, spellings[i] + " task run")
    checkControls(Runs.controls(ctlRunOf("done", false, true, "task")), ctlFinished, ctlFinished, ctlFinished,
                  "done task run")
    checkControls(Runs.controls(ctlRunOf("weird", true, true, "task")), ctlUnknown, ctlUnknown, ctlUnknown,
                  "unknown task run")
  }

  function test_controls_escalated_card_run_fresh() {
    var run = ctlRunOf("escalated", false, true, "task")
    var a = Runs.controls(run)
    var b = Runs.controls(run)
    verify(a !== b, "a fresh result per call")
    verify(a.pause !== b.pause && a.resume !== b.resume && a.cancel !== b.cancel, "fresh actions per call")
    verify(a.pause !== a.resume && a.resume !== a.cancel && a.pause !== a.cancel, "no action shared within a result")
    a.resume.enabled = true
    a.resume.reason = ""
    delete a.pause
    checkControls(b, ctlPauseNotRunning, ctlResumeEscalatedCard, "", "the second result after mutating the first")
    checkControls(Runs.controls(run), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "a third call")
  }
```

- [ ] **Step 3: Run the tests and confirm the new ones fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: in the `== tests/core/domain/tst_runs.qml` block, these show `FAIL!`: `test_controls_escalated_card_run`, `test_controls_escalated_card_run_from_fixture`, `test_controls_escalated_card_run_normalized` and `test_controls_escalated_card_run_fresh`. Each fails on a `resume reason` compare, with actual `""` and expected `An escalated card run cannot be resumed; relaunch it`. `test_controls_escalated_milestone_run_unchanged`, `test_controls_escalated_other_workflows_resumable` and `test_controls_task_run_other_states` pass already, because they guard behaviour that must not change. There must be no `TypeError`/`ReferenceError` lines.

- [ ] **Step 4: Implement**

In `core/domain/runs.js`, add this var directly after `var _REASON_RESUME_CANCELLED = "A cancelled run cannot be resumed"`:

```js
var _REASON_RESUME_ESCALATED_CARD = "An escalated card run cannot be resumed; relaunch it"
```

Replace the comment above `function controls(run)` and the dead/parked/escalated branch. Before:

```js
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
```

After:

```js
// {pause, resume, cancel}, each a fresh {enabled, reason}; reason is "" when
// enabled. Pause needs a running run outside Integrate; resume needs dead,
// parked or escalated, except an escalated card run (workflow "task", trimmed),
// and never looks at accepting; cancel needs a run that has not finished and is
// not in Integrate. The state's reason wins over Integrate's.
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
```

Leave the rest of `controls` as it is. `run.workflow` is safe to read here: `runState` returns `"escalated"` only for an object. `_textOf` gives `""` for null/undefined and for a prototype-less object (`String()` throws on it, and `_textOf` catches that), and `"[object Object]"` for `{}`, so neither one matches `"task"`.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: `Totals: N passed, 0 failed` for `tests/core/domain/tst_runs.qml`, with no `TypeError`/`ReferenceError` lines. These existing tests still pass: `test_controls_shape`, `test_controls_running`, `test_controls_resumable_states`, `test_controls_finished_states`, `test_fixture_cancel_spellings_controls`, `test_controls_unknown_and_garbage` and `test_controls_from_normalized`.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): refuse resume on an escalated card run"
```

---

### Task 2: `controlError` speaks the refusals in user terms

**Files:**
- Modify: `core/domain/runs.js` (`_CONTROL_ERRORS`, currently lines 917-926)
- Test: `tests/core/domain/tst_runs.qml` (`controlErrorTable()`, `test_control_error_table`, and one assertion in `test_control_error_shapes`; add one new test)

**Interfaces:**
- Consumes: `controlError(error)`, unchanged in shape.
- Produces: `_CONTROL_ERRORS` with nine rows in the spec's order, and the test helper `controlErrorTable()` returning the same nine `[type, sentence]` pairs. Task 3 uses `controlErrorTable()`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, replace the whole `controlErrorTable` function with:

```qml
  // [type, sentence] for every am control error controlError knows.
  function controlErrorTable() {
    return [
      ["UnknownRunError", "The run no longer exists"],
      ["NotRunningError", "The run is not running"],
      ["DeadRunError", "The run's process has died, so nobody can act on this request. Resume picks the run up."],
      ["NotAcceptingError", ctlIntegrate],
      ["RunIsLiveError", "Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died."],
      ["NotResumableError", "am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work."],
      ["CheckpointMismatchError", "The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase."],
      ["ClaimedError", "Another run has already claimed this work"],
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
  }
```

In `test_control_error_table`, change `compare(table.length, 8)` to:

```qml
    compare(table.length, 9)
```

In `test_control_error_shapes`, replace:

```qml
    compare(Runs.controlError({ ok: false, error: { type: "DeadRunError", message: "pid 42 is gone" } }),
            "The run's process has died; resume it instead", "the message is not shown for a known type")
```

with:

```qml
    compare(Runs.controlError({ ok: false, error: { type: "DeadRunError", message: "pid 42 is gone" } }),
            "The run's process has died, so nobody can act on this request. Resume picks the run up.",
            "the message is not shown for a known type")
```

Add this test directly after the closing `}` of `test_control_error_fallback`, before the `// ---- S2 1.2: run alerts` comment:

```qml
  function test_control_sentences_are_ascii() {
    var texts = [Runs.controls(ctlRunOf("escalated", false, true, "task")).resume.reason]
    var table = controlErrorTable()
    for (var i = 0; i < table.length; i++)
      texts.push(Runs.controlError({ ok: false, error: { type: table[i][0], message: "m" } }))
    for (var j = 0; j < texts.length; j++) {
      for (var k = 0; k < texts[j].length; k++)
        verify(texts[j].charCodeAt(k) < 128, "plain ASCII: text " + j + " at " + k)
    }
  }
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: `test_control_error_table` fails with `FAIL!` on its first changed row (`DeadRunError`). Actual is `The run's process has died; resume it instead`, expected is the new sentence. `test_control_error_shapes` fails on `bare DeadRunError`. `test_control_sentences_are_ascii` passes already (it is a guard). `test_control_error_fallback` passes.

- [ ] **Step 3: Implement**

In `core/domain/runs.js`, replace the whole `var _CONTROL_ERRORS = [ ... ]` array (keep its comment) with:

```js
var _CONTROL_ERRORS = [
  ["UnknownRunError", "The run no longer exists"],
  ["NotRunningError", "The run is not running"],
  ["DeadRunError", "The run's process has died, so nobody can act on this request. Resume picks the run up."],
  ["NotAcceptingError", _REASON_INTEGRATE],
  ["RunIsLiveError", "Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died."],
  ["NotResumableError", "am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work."],
  ["CheckpointMismatchError", "The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase."],
  ["ClaimedError", "Another run has already claimed this work"],
  ["LockTimeoutError", "am is busy; try again in a moment"]
]
```

Type the apostrophes as ASCII `'` (U+0027), not a typographic quote.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: `Totals: N passed, 0 failed` for `tests/core/domain/tst_runs.qml`, including `test_control_error_table`, `test_control_error_shapes`, `test_control_error_fallback` and `test_control_sentences_are_ascii`.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): am control refusals in user terms, add CheckpointMismatchError"
```

---

### Task 3: `offersRelaunch(error)`

**Files:**
- Modify: `core/domain/runs.js` (the comment and body of `controlError`, plus a new private `_controlErrorType` directly above it and a new `offersRelaunch` directly after it)
- Test: `tests/core/domain/tst_runs.qml` (new helper and tests after `test_control_sentences_are_ascii`)

**Interfaces:**
- Consumes: `_isObject(v)`, `_textOf(v)`, `errorText(error)` and `_CONTROL_ERRORS` from `runs.js`, plus the test helper `controlErrorTable()` from Task 2.
- Produces: `offersRelaunch(error) -> boolean`. It returns `true` exactly when the type read is `"NotResumableError"` or `"CheckpointMismatchError"`, and `false` otherwise (always a real boolean). Also `_controlErrorType(error) -> string`, private: the trimmed type, or `""` when `error` is not an object or has `ok === true`. `controlError(error)` keeps its behaviour and now calls `_controlErrorType`. Test helper `checkRelaunch(error, want, label)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, add these directly after the closing `}` of `test_control_sentences_are_ascii`:

```qml
  // offersRelaunch(error) is exactly the boolean `want`, never another falsy or truthy value.
  function checkRelaunch(error, want, label) {
    var got = Runs.offersRelaunch(error)
    compare(typeof got, "boolean", label + " is a boolean")
    compare(got, want, label)
  }

  function test_offers_relaunch_table() {
    var table = controlErrorTable()
    var offered = 0
    for (var i = 0; i < table.length; i++) {
      var type = table[i][0]
      var want = type === "NotResumableError" || type === "CheckpointMismatchError"
      if (want) offered++
      checkRelaunch({ ok: false, error: { type: type, message: "m" } }, want, "envelope " + type)
      checkRelaunch({ type: type }, want, "bare " + type)
      checkRelaunch({ type: type, message: "m" }, want, "bare with message " + type)
    }
    compare(offered, 2, "two types offer relaunch")
  }

  function test_offers_relaunch_reading() {
    checkRelaunch({ ok: false, error: { type: "  NotResumableError\n", message: "m" } }, true, "trimmed envelope")
    checkRelaunch({ type: "  NotResumableError\n" }, true, "trimmed bare")
    checkRelaunch({ type: " CheckpointMismatchError " }, true, "trimmed bare checkpoint")
    checkRelaunch({ ok: false, error: { type: "notresumableerror", message: "m" } }, false, "case-sensitive envelope")
    checkRelaunch({ type: "CHECKPOINTMISMATCHERROR" }, false, "case-sensitive bare")
    var bare = Object.create(null)
    bare.type = "CheckpointMismatchError"
    checkRelaunch(bare, true, "prototype-less bare error")
    checkRelaunch({ ok: false, type: "NotResumableError", error: { type: "Foo" } }, false,
                  "the envelope's error wins over a stray outer type")
    checkRelaunch({ ok: false, type: "Foo", error: { type: "NotResumableError" } }, true,
                  "the envelope's error is read")
    checkRelaunch({ ok: true, error: { type: "NotResumableError" } }, false, "ok:true")
    checkRelaunch({ ok: false, error: "NotResumableError" }, false, "a string error reads the outer object")
  }

  function test_offers_relaunch_unknown_and_garbage() {
    checkRelaunch({ ok: false, error: { type: "Foo", message: "bar" } }, false, "unknown type")
    checkRelaunch({ ok: false, error: { type: "", message: "bar" } }, false, "empty type")
    checkRelaunch({ type: "" }, false, "empty bare type")
    var protoNames = ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]
    for (var k = 0; k < protoNames.length; k++) {
      checkRelaunch({ ok: false, error: { type: protoNames[k], message: "m" } }, false, "envelope " + protoNames[k])
      checkRelaunch({ type: protoNames[k] }, false, "bare " + protoNames[k])
    }
    var noProto = Object.create(null)
    checkRelaunch({ ok: false, error: { type: noProto, message: "m" } }, false, "prototype-less type object, envelope")
    checkRelaunch({ type: noProto }, false, "prototype-less type object, bare")
    var arrayError = []
    arrayError.type = "NotResumableError"
    var garbage = [undefined, null, "NotResumableError", 5, true, [], {}, { ok: false }, { ok: true },
                   Object.create(null), arrayError]
    for (var i = 0; i < garbage.length; i++)
      checkRelaunch(garbage[i], false, "garbage " + i)
  }

  function test_offers_relaunch_parsed_json() {
    // synthetic: am's reply text as RunStore parses it
    checkRelaunch(JSON.parse('{"ok": false, "error": {"type": "NotResumableError", "message": "run r1 is cancelled"}}'),
                  true, "parsed NotResumableError")
    checkRelaunch(JSON.parse('{"ok": false, "error": {"type": "CheckpointMismatchError", "message": "m"}}'),
                  true, "parsed CheckpointMismatchError")
    checkRelaunch(JSON.parse('{"ok": false, "error": {"type": "RunIsLiveError", "message": "run r1 is live"}}'),
                  false, "parsed RunIsLiveError")
    checkRelaunch(JSON.parse('{"__proto__": {"type": "NotResumableError"}}'), false,
                  "an own __proto__ key is not read as the prototype")
    checkRelaunch(JSON.parse('{"ok": false, "error": {"__proto__": {"type": "NotResumableError"}}}'), false,
                  "an own __proto__ key inside the envelope")
  }

  function test_offers_relaunch_agrees_with_control_error() {
    var relaunchSentences = [controlErrorTable()[5][1], controlErrorTable()[6][1]]
    var noProto = Object.create(null)
    noProto.type = "NotResumableError"
    var inputs = [undefined, null, "x", 5, [], {}, { ok: true }, { ok: false }, noProto,
                  { type: "Foo" }, { ok: false, error: "CheckpointMismatchError" },
                  { ok: false, type: "NotResumableError", error: { type: "Foo" } },
                  { ok: false, type: "Foo", error: { type: "CheckpointMismatchError" } }]
    var table = controlErrorTable()
    for (var i = 0; i < table.length; i++) {
      inputs.push({ ok: false, error: { type: table[i][0], message: "m" } })
      inputs.push({ type: " " + table[i][0] + " " })
    }
    for (var j = 0; j < inputs.length; j++) {
      var sentence = Runs.controlError(inputs[j])
      var isRelaunchSentence = sentence === relaunchSentences[0] || sentence === relaunchSentences[1]
      compare(Runs.offersRelaunch(inputs[j]), isRelaunchSentence, "input " + j + ": " + sentence)
    }
  }
```

`controlErrorTable()[5]` is `NotResumableError` and `[6]` is `CheckpointMismatchError`, in the order Task 2 set.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: all five `test_offers_relaunch_*` tests show `FAIL!`, and the run prints a `TypeError: Property 'offersRelaunch' of object [object Object] is not a function` line (`tests/run.sh` turns that into a non-zero exit).

- [ ] **Step 3: Implement**

In `core/domain/runs.js`, replace the comment and the whole `function controlError(error) { ... }` with:

```js
// The trimmed, case-sensitive type of an am control error, envelope or bare, the
// way errorText reads it; "" when error is not an object or is ok:true.
function _controlErrorType(error) {
  if (!_isObject(error) || error.ok === true) return ""
  var e = _isObject(error.error) ? error.error : error
  return _textOf(e.type)
}

// The sentence for a failed pause / resume / cancel. A known type gives its
// sentence without am's message; anything else gives errorText(error).
function controlError(error) {
  var type = _controlErrorType(error)
  for (var i = 0; i < _CONTROL_ERRORS.length; i++) {
    if (_CONTROL_ERRORS[i][0] === type) return _CONTROL_ERRORS[i][1]
  }
  return errorText(error)
}

// Whether a failed control call is answered by relaunching: true exactly when
// its type (read as controlError reads it) is NotResumableError or
// CheckpointMismatchError, false for anything else.
function offersRelaunch(error) {
  var type = _controlErrorType(error)
  return type === "NotResumableError" || type === "CheckpointMismatchError"
}
```

When the type is `""`, no `_CONTROL_ERRORS` row matches, so `controlError` still falls through to `errorText(error)` exactly as before.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `timeout 600 bash tests/run.sh domain/tst_runs`
Expected: `Totals: N passed, 0 failed` for `tests/core/domain/tst_runs.qml`, with no `TypeError`/`ReferenceError` lines. `test_control_error_table`, `test_control_error_shapes` and `test_control_error_fallback` still pass after the refactor.

- [ ] **Step 5: Run the full gate**

Run: `timeout 1200 bash tests/run.sh; echo "exit=$?"`
Expected: pytest passes. Every `== ...` block shows `Totals: ... 0 failed`, including `tests/architecture`, `tests/core/stores/tst_run_store.qml`, `tests/ui/tst_runs_flow.qml` and `tests/ui/tst_runs_real_data.qml`. The output ends with `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): offersRelaunch for NotResumableError and CheckpointMismatchError"
```
<!-- task-pipeline: validated -->
