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
