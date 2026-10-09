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
