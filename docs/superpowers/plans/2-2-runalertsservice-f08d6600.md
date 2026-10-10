# 2.2 RunAlertsService: runs the helper (card f08d6600)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): Architecture, the helper's output lines (lines 141-145) and the `RunAlertsService.qml`
bullet (lines 148-158: plain `Process`, restart policy, `status`, `lastError`, one
`console.warn` per failure); Failure modes, rows `am` not installed, old `am`, store unreadable
and store busy (lines 177-180); Resource use when idle (lines 166-171: no timer while idle);
Testing, the `tst_run_alerts_service.qml` restart-policy items (lines 205-206). Parent story
bd7304ee ("Alerts service"). Blocked by c2d6e450 (2.1, done: the manifest declares the service
and `RunAlertsService.qml` exists with `backendDir` only).

This card makes the service **keep `runs-alerts.py` running** under the parent's restart
policy and **turn its alert lines into a signal**. It does nothing with an alert: no settings
read, no snapshot, no `notify.py`, no cursor.

## Starting point

- `core/stores/RunAlertsService.qml`: root `QtObject` (imports `QtQml` only) with
  `readonly property string backendDir`, derived from its own URL (`<plugin>/core/backend/`,
  absolute, trailing `/`). Created by the shell with `createObject(null)`, no properties.
- `tests/core/stores/tst_run_alerts_service.qml`: six tests (load, recreate, `backendDir`
  shape, `backendDir` equals Panel's, the shell injects nothing). They must keep passing.
- `core/backend/runs/runs-alerts.py` (docstring lines 1-53): takes **no argument** (any argument
  is a Usage error, exit 2). Prints, one JSON object per line:
  `{"alert": {"run_id", "root", "project", "state": "escalated"|"dead"}}`, or
  `{"ok": false, "error": {"type", "message"}}` then exits 1 with type `SchemaMismatch`,
  `CorruptJournal`, `HelperError`, `AmMissing`, or an `am` envelope re-emitted unchanged
  (e.g. `StoreBusyError`). Exits 0 on SIGTERM, SIGINT, a closed stdout or `am` exiting 0.
  The parent's cursor argument and `{"cursor": N}` / `gseq` are not implemented in the helper
  yet and are not this card's (see Out of scope).
- Convention model: `RunStore.qml` `startWatch` (line ~325), `isCurrentWatch` (line ~379),
  `watchLine` (line ~394), `watchExited` (line ~535) and the `watchC` Component (line ~1018):
  one `Process` per launch created from a `Component`, a `launchSeq` guard against a late line
  or exit from an old launch, the last `ok: false` line kept on the process as `envelope` and
  read at exit, timers with an `objectName` exposed through `readonly property alias`.
- Test stubs (`tests/stubs/Quickshell/Io/`): `Process` is a bare `QtObject` with `command`,
  `running`, `workingDirectory`, `stdout`, `stderr` and `signal exited(int exitCode)`; it spawns
  nothing. `SplitParser` has `splitMarker` and `signal read(string data)`. `Scope` is an `Item`.
  So the "fake helper" in tests is the stub `Process` itself: the test reads the current
  process through the service, emits `stdout.read(line)` and `exited(code)` on it.

## Constraints

- Layering (`docs/architecture.md:14`, enforced by `tests/architecture/test_layers.py`):
  a `core/stores/` file imports only `QtQml`, `Quickshell`, `Quickshell.Io` and
  `../domain/*.js` (parent line 149). `tests/architecture` must pass with no allowlist edit; no
  new QML type name may clash with a shell/Controls name (the service declares no new component
  file).
- The root may change from `QtObject` to `Scope` (from `Quickshell`) to hold the `Process`
  Component and the `Timer`, as every other store does; the 2.1 spec left that call to this
  card. It must still build with `createObject(null)` and no properties, and must still declare
  none of `shell`, `manifest`, `omarchyPath`, `pluginRegistry`, `barWidgetRegistry`
  (existing `test_the_shell_injects_nothing`).
- Composed by the shell, not by `App.qml` (parent line 150): `App.qml`, `ui/Panel.qml` and every
  other store are untouched.
- A plain `Process`, not a `HelperRunner` (parent lines 150-151: long-lived).
- Restart policy (parent lines 154-157, failure table lines 177-180): `AmMissing` and
  `HelperError` relaunch after **300 s**; `StoreBusyError` relaunches like `HelperError`;
  `SchemaMismatch` and `CorruptJournal` stop it until the service is created again; a SIGTERM
  exit (exit 0) is not relaunched.
- `status` is `watching` | `waiting` | `stopped`; `lastError` is a property; each failure is
  **one** `console.warn` line (parent lines 156-158).
- No timer runs while nothing is waited for (parent lines 168-169; card: "a Timer that runs only
  while waiting").
- Card: docstrings and comments state the contract only, no narrative. TDD: tests first.
- Verification: `bash tests/run.sh` green. Quick loop: `bash tests/run.sh tst_run_alerts_service`
  (it still runs pytest first) and
  `uv run --with pytest python3 -m pytest tests/architecture -q`.

## Behaviour

### Public surface

| member | kind | contract |
|---|---|---|
| `backendDir` | `readonly property string` | unchanged from 2.1 |
| `status` | `readonly property string` | `"watching"` while a launched helper has not exited; `"waiting"` between a retryable failure and the relaunch; `"stopped"` after a clean exit or a fatal failure |
| `lastError` | `readonly property string` | `""` until the first failure; then the text of the most recent failure (see Exit handling). A relaunch and a clean exit leave it as it is |
| `helperProc` | `readonly property alias` (or readonly var) | the current launch's `Process` while `status` is `watching`; `null` otherwise |
| `retryTimer` | `readonly property alias` to a `Timer` with `objectName: "retryTimer"` | `interval` 300000, `repeat` false; `running` is true exactly while `status` is `"waiting"` |
| `alertReceived(var alert)` | signal | one emission per valid alert line of the current launch (see Lines) |

"Readonly" means a consumer cannot assign it; the service changes it internally (as `RunStore`
does through a private `QtObject` holding the writable state, e.g. `watchState`). Assigning to
them from tests must not be attempted (a caught `TypeError` line trips `tests/run.sh`).

### Launch

- On `Component.onCompleted` the service launches the helper once.
- A launch creates a **new** `Process` (one per launch, from a `Component`, parented to the
  service) with `command` exactly `["python3", backendDir + "runs/runs-alerts.py"]` (no
  argument: the helper refuses any), a `stdout` `SplitParser`, a launch number one higher than
  the previous launch's, and sets `running = true`. `status` becomes `"watching"`,
  `helperProc` that process, `retryTimer` stopped.
- Only the current launch counts: a line or an exit from a process whose launch number is not the
  current one changes nothing and emits nothing.
- A process is destroyed (`destroy()`) after its exit has been handled.

### Lines

For each stdout line of the current launch:

1. Trim; a blank line is ignored.
2. `JSON.parse` inside `try`/`catch`; text that is not JSON is ignored.
3. A value that is not a non-null, non-array object is ignored.
4. `value.ok === false`: the value is kept on that process as its envelope (a later one replaces an
   earlier one); nothing is emitted.
5. `value.alert` is a non-null, non-array object whose `run_id` is a non-empty string and whose
   `state` is `"escalated"` or `"dead"`: `alertReceived(value.alert)` is emitted with that
   object as parsed (other keys -- `root`, `project`, a future `gseq` -- passed through untouched).
6. Anything else (an alert object failing step 5, `{"cursor": N}`, unknown keys) is ignored.

The handler never throws, whatever the line; nothing is logged for an ignored line.

### Exit handling

On `exited(code)` of the current launch (the envelope is the last `ok: false` line it printed,
or none):

| exit | `status` after | `retryTimer` | `lastError` | `console.warn` |
|---|---|---|---|---|
| `0` (SIGTERM, SIGINT, closed stdout, `am` exited 0) | `"stopped"` | stopped | unchanged | none |
| non-zero, envelope type `SchemaMismatch` or `CorruptJournal` | `"stopped"` | stopped | `Runs.errorText(envelope)` (`"<type>: <message>"`) | one line |
| non-zero, any other envelope type (`AmMissing`, `HelperError`, `StoreBusyError`, any other) | `"waiting"` | started (300 s) | `Runs.errorText(envelope)` | one line |
| non-zero, no envelope | `"waiting"` | started (300 s) | `"runs-alerts.py exited <code>"` | one line |

- `Runs` is `../domain/runs.js` (`errorText`, `core/domain/runs.js:507`), an allowed import.
- The warn line is exactly `"RunAlertsService: " + lastError + " -- retrying in 300 s"` when
  waiting, `"RunAlertsService: " + lastError + " -- stopped"` when stopped. One failure is one
  call to `console.warn` with that one string.
- `helperProc` is `null` after any exit.
- When `retryTimer` fires while `status` is `"waiting"` the service launches again (Launch above);
  `lastError` keeps the failure that caused the wait. A fire in any other status launches
  nothing.
- `"stopped"` is final for this instance: nothing launches again until the shell creates the
  service anew (plugin reload or shell restart, parent line 186).

### Destruction

On `Component.onDestruction`: `retryTimer` stops and the current process, if any, gets
`running = false` (Quickshell sends it SIGTERM; the helper exits 0). The process's late exit, if
it is delivered at all, relaunches nothing and warns nothing (the launch-number guard, or the
process being destroyed with its parent, both suffice). No `console.warn` on destruction.

### Docs

`docs/architecture.md`, the existing `RunAlertsService.qml` bullet (line 95) gains the contract
above in one or two sentences: it runs `runs-alerts.py` as a plain `Process` from creation to
destruction; `status` / `lastError`; the 300 s relaunch for every failure but `SchemaMismatch` /
`CorruptJournal`, which stop it, and none after exit 0; `retryTimer` runs only while waiting; one
`console.warn` per failure; `alertReceived(alert)` per alert line, every other line ignored. The
bullet must stay after `RunDispatchStore.qml` and must not name any token
`tests/architecture/test_run_store_docs.py` rejects (`RunStore`, `app.runAlerts`, ...); run that
test.

## Error paths

- Non-JSON, blank, array, `null`, number, string, an `alert` with a missing/empty `run_id` or an
  unknown `state`: ignored, no signal, no throw, no log.
- Several `ok: false` lines before the exit: the last one decides the policy.
- An envelope line followed by exit 0: exit 0 wins (stopped, no warn, `lastError` unchanged).
- Non-zero exit with no envelope (python crash, Usage exit 2): treated as retryable.
- A late line or exit from a replaced launch: ignored.
- A `Process` that never starts (no `python3`) is not observable through the stubs; see Review
  Focus.

## Tests

All in `tests/core/stores/tst_run_alerts_service.qml` (tier: **QML store test**, headless
`qmltestrunner` with `tests/stubs`; why: the behaviour is a QML object's reaction to its
`Process` signals and a `Timer`, which only the QML engine runs, and the stub `Process` is the
fake helper -- no real process is spawned). Each test builds the service with the existing
`make()` (`createObject(null)`) and destroys it at the end. The helper `line(s, obj)` emits
`s.helperProc.stdout.read(JSON.stringify(obj))`; `SignalSpy` on `alertReceived`. Warning
assertions use `ignoreWarning(<exact string or RegExp>)` (fails the test when the warning does not
come) together with `failOnWarning(/RunAlertsService/)` (fails on any further one), so "one warn"
is proved exactly.

| # | test | proves |
|---|---|---|
| 1 | `test_it_launches_the_helper_on_creation` | after `make()`: `status === "watching"`, `helperProc` non-null, `helperProc.running === true`, `helperProc.command` deep-equals `["python3", s.backendDir + "runs/runs-alerts.py"]`, `retryTimer.running === false`, `lastError === ""` |
| 2 | `test_am_missing_waits_then_relaunches` | envelope `AmMissing` + `exited(1)` → `status "waiting"`, `retryTimer.running`, `retryTimer.interval === 300000`, `lastError === "AmMissing: <message>"`, `helperProc === null`, exactly one warn `RunAlertsService: AmMissing: <message> -- retrying in 300 s`; then `retryTimer.triggered()` → `status "watching"`, a new non-null `helperProc` (not the old object) with the same command, `running`, `retryTimer.running === false`, `lastError` unchanged |
| 3 | `test_helper_error_waits_then_relaunches` | same as 2 with `HelperError` |
| 4 | `test_store_busy_waits_like_helper_error` | `StoreBusyError` envelope + `exited(1)` → `waiting`, timer running, one warn |
| 5 | `test_a_non_zero_exit_without_envelope_waits` | `exited(2)` with no line → `waiting`, `lastError === "runs-alerts.py exited 2"`, one warn |
| 6 | `test_schema_mismatch_stops` | envelope + `exited(1)` → `status "stopped"`, timer not running, `helperProc === null`, `lastError` the errorText, one warn ending ` -- stopped`; `retryTimer.triggered()` afterwards launches nothing (`helperProc` stays null, status stays stopped) |
| 7 | `test_corrupt_journal_stops` | same as 6 with `CorruptJournal` |
| 8 | `test_exit_zero_is_not_relaunched` | `exited(0)` → `stopped`, timer not running, `lastError === ""`, `failOnWarning(/RunAlertsService/)` with no ignore (no warn); also after an earlier envelope line: exit 0 still stops without warn |
| 9 | `test_the_last_envelope_decides` | a `SchemaMismatch` line then an `AmMissing` line then `exited(1)` → `waiting` |
| 10 | `test_the_timer_runs_only_while_waiting` | `retryTimer.running` false while watching, true while waiting, false after the relaunch, false after a stop |
| 11 | `test_an_alert_line_emits_alert_received` | an `escalated` and a `dead` alert line → spy count 2, `spy.signalArguments[i][0]` has the same `run_id`, `root`, `project`, `state` (and an extra key such as `gseq` passed through) |
| 12 | `test_other_lines_are_ignored` | `""`, `"   "`, `"not json"`, `"[1]"`, `"null"`, `"42"`, `"\"x\""`, `{"cursor": 3}`, `{"alert": null}`, `{"alert": []}`, `{"alert": {"state": "escalated"}}`, `{"alert": {"run_id": "", "state": "dead"}}`, `{"alert": {"run_id": "r", "state": "running"}}`, `{"hello": {}}` → spy count 0, `status` still `watching`, no warning (`failOnWarning(/./)`); `tests/run.sh`'s grep catches any `TypeError` |
| 13 | `test_a_replaced_launch_is_ignored` | in one synchronous block, with no `wait` (so `p1`'s deferred `destroy()` has not run yet): keep the first process `p1`; `AmMissing` line + `p1.exited(1)` (one warn ignored); `retryTimer.triggered()`; then an alert line and another `AmMissing` line + `exited(1)` on `p1` → spy count 0, `status` still `watching`, `helperProc` the new process, no second warn |
| 14 | `test_destruction_stops_the_helper` | connect to `s.helperProc.runningChanged` and record `running`; `s.destroy()`; `wait(0)` → recorded `false`; no warn (`failOnWarning(/RunAlertsService/)`) |
| 15 | `test_destruction_while_waiting_warns_nothing` | fail retryably (one warn ignored), destroy, `wait(0)` → no further warn, no error output |
| 16 | existing six tests | still pass unchanged (`test_the_shell_injects_nothing` with the new root type) |
| 17 | `tests/architecture` (pytest, existing) | layer imports, name clashes, `test_run_store_docs.py` against the edited `docs/architecture.md` |

`bash tests/run.sh` must be green; its QML pass also fails on any `TypeError` / `ReferenceError`
/ `non-existent` / `Unable to assign` / `is not a function` line, which covers a line handler that
throws and a stub property the service relies on but the stub lacks (use only `command`,
`running`, `stdout`, `exited` on `Process`).

## Review Focus (for the planner)

- A real Quickshell `Process` that fails to start (no `python3`) may never emit `exited`; the
  stubs cannot show it. `status` would stay `watching` forever. Acceptable for this card (python3
  is a hard dependency of the plugin); the planner should not invent behaviour for it, but the
  implementation must not crash on it.
- Writing a `readonly` alias from tests or from the service's own code: keep writable state in a
  private `QtObject` (as `RunStore`'s `watchState`) so the public properties stay readonly.
- `retryTimer.running` must not be a binding a JS `start()`/`stop()` silently breaks; pick one
  mechanism (explicit `start()`/`stop()` at each transition is recommended) and test 10 pins it.
- A process destroyed inside its own `onExited` handler: handle the exit fully before `destroy()`.
- The `Scope` stub is an `Item`; real `Scope` is not. Nothing visual may be relied on.

## Out of scope

- Reading `get-global-settings`, the run snapshot, `Runs.alertNotification`, `notify.py`
  launches (card 2.3).
- `RunAlertsStore` dropping `notify.py`; the Runs screen switch label (card 2.4 and later).
- The persisted cursor, passing a cursor or `store_id` to the helper, `{"cursor": N}` lines,
  dismissal, `cursor_reset` (later milestone cards; the helper takes no argument today).
- Any change to `runs-alerts.py`, `App.qml`, `ui/Panel.qml`, `manifest.json` or another store.
- Surfacing `status` / `lastError` in the panel (parent Open, lines 222-225).

---

# 2.2 RunAlertsService: runs the helper — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `core/stores/RunAlertsService.qml` keeps `runs-alerts.py` running under the parent's restart policy and emits `alertReceived(alert)` for each valid alert line.

**Architecture:** The root becomes a `Scope` holding one `Process` `Component` (one process per launch, tagged with a launch number), a 300 s single-shot `retryTimer` started and stopped explicitly at each transition, and a private `QtObject` (`alertsState`) holding the writable state the public readonly aliases expose -- the `RunStore` watch pattern (`startWatch` / `watchLine` / `watchExited` / `watchC`). Exit handling reads the last `ok: false` line kept on the process as `envelope`.

**Tech Stack:** QML (Qt 6.11, `QtQml`, `Quickshell`, `Quickshell.Io`), `core/domain/runs.js` (`Runs.errorText`), QtTest `qmltestrunner` with `tests/stubs`, pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/2-2-runalertsservice-f08d6600.md` (prepended above).

## Global Constraints

- `core/stores/*.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`; `tests/architecture` must pass with no allowlist edit.
- Built with `createObject(null)` and no properties; declares none of `shell`, `manifest`, `omarchyPath`, `pluginRegistry`, `barWidgetRegistry`.
- `App.qml`, `ui/Panel.qml`, `manifest.json`, `runs-alerts.py` and every other store are untouched.
- A plain `Process`, not a `HelperRunner`; `command` exactly `["python3", backendDir + "runs/runs-alerts.py"]`.
- Use only `command`, `running`, `stdout`, `exited` on `Process` (the stub has nothing the service may need beyond these).
- `AmMissing`, `HelperError`, `StoreBusyError`, any other envelope type and a non-zero exit with no envelope relaunch after **300 s**; `SchemaMismatch` and `CorruptJournal` stop; exit 0 stops with no warning.
- `status` is `"watching"` | `"waiting"` | `"stopped"`; `"stopped"` is final for the instance.
- Warn lines, exactly: `"RunAlertsService: " + lastError + " -- retrying in 300 s"` / `"RunAlertsService: " + lastError + " -- stopped"`; one `console.warn` per failure.
- No timer runs while nothing is waited for.
- Comments and docs state the contract only, no narrative.
- Verification: `bash tests/run.sh` green (its QML pass also fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `is not a function` line).

## Review Focus

1. `retryTimer` fires while a helper is already running (`watching`) -- e.g. a stray `triggered()`: a second helper must not launch; the current `helperProc` stays. (Task 1, `test_a_timer_fire_while_watching_launches_nothing`)
2. The helper prints a malformed envelope (`{"ok": false}` with no `error`, or `error` a string) and exits non-zero: no throw, retryable, `lastError` `"unknown error"`. (Task 1, `test_a_malformed_envelope_waits`)
3. `am` stays missing across relaunches: each failed relaunch warns once more, replaces `lastError` and waits 300 s again -- the policy repeats, it does not give up or go quiet. (Task 1, `test_a_failed_relaunch_waits_again`)
4. Two services alive at once (a plugin reload creates the new one before the old is gone): one's failure must not move the other. (Task 1, `test_two_services_are_independent`)
5. An alert line with surrounding whitespace or a trailing `\r`: still read as an alert. (Task 2, `test_an_alert_line_with_surrounding_whitespace_is_read`)

Not testable through the stubs (spec Review Focus): a real `Process` that never starts may never emit `exited`; `status` would stay `watching`. No behaviour is added for it.

## File Structure

- Modify `core/stores/RunAlertsService.qml` -- the whole service: launch, line parsing, exit policy, timer, destruction.
- Modify `tests/core/stores/tst_run_alerts_service.qml` -- the QML store tests (the existing six stay unchanged).
- Modify `docs/architecture.md:95` -- the `RunAlertsService.qml` bullet gains the contract.

Quick loops (both are needed: `tests/run.sh` runs the full pytest suite first, ~2 min):

- QML only, fast: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_alerts_service.qml 2>&1 | grep -E "^(FAIL|PASS|Totals)|^   Loc|TypeError|ReferenceError"`
- Architecture: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
- Gate: `timeout 600 bash tests/run.sh tst_run_alerts_service` and, at the end, `timeout 900 bash tests/run.sh`

(`test_backend_dir_is_what_the_panel_hands_app` prints `BoardScreen.qml:59:7: TypeError: Cannot read property 'width' of null` QWARN lines; they predate this card and `tests/run.sh` filters them out. Ignore them in the fast loop.)

---

### Task 1: The service launches `runs-alerts.py` and applies the restart policy

**Files:**
- Modify: `core/stores/RunAlertsService.qml` (whole file, 13 lines today)
- Test: `tests/core/stores/tst_run_alerts_service.qml` (append before the final `}`)

**Interfaces:**
- Consumes: `Runs.errorText(envelope)` from `core/domain/runs.js:507` → `"<type>: <message>"`, `"<type>"`, `"<message>"` or `"unknown error"`.
- Produces (Task 2 relies on these exact names):
  - `readonly property alias status` (string), `lastError` (string), `helperProc` (the current `Process` or `null`), `retryTimer` (the `Timer`, `objectName: "retryTimer"`).
  - `function launch()`, `function isCurrent(proc) → bool`, `function helperLine(proc, data)`, `function helperExited(proc, exitCode)`.
  - Private `QtObject { id: alertsState; status; lastError; proc; launchSeq }`, `Component { id: helperC; Process { id: hp; launchSeq; envelope; stdout: SplitParser { onRead → service.helperLine(hp, data) }; onExited → service.helperExited(hp, exitCode); hp.destroy() } }`.
  - Test helpers: `line(s, obj)`, `envelope(type)`, `retryWarning(type)`, `stopWarning(type)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_alerts_service.qml`, replace the header comment (lines 2-4):

```qml
// The service entry point: it builds as the shell's ensureService builds it
// (createObject(null), no properties), declares none of the properties the
// shell injects, and its backendDir is the plugin's real core/backend/.
```

with:

```qml
// The service entry point: it builds as the shell's ensureService builds it
// (createObject(null), no properties), declares none of the properties the
// shell injects, and its backendDir is the plugin's real core/backend/.
// It keeps runs-alerts.py running under the restart policy. The stub Process
// spawns nothing: each test plays the helper by emitting stdout.read(line)
// and exited(code) on helperProc.
```

Then, after the last existing test (`test_the_shell_injects_nothing`, whose body ends with `    s.destroy()\n  }`), and before the file's final closing `}`, insert:

```qml

  // One stdout line of the current launch: a string as is, anything else as JSON.
  function line(s, obj) {
    s.helperProc.stdout.read(typeof obj === "string" ? obj : JSON.stringify(obj))
  }

  function envelope(type) {
    return { ok: false, error: { type: type, message: "the " + type + " message" } }
  }

  function retryWarning(type) {
    return "RunAlertsService: " + type + ": the " + type + " message -- retrying in 300 s"
  }

  function stopWarning(type) {
    return "RunAlertsService: " + type + ": the " + type + " message -- stopped"
  }

  function test_it_launches_the_helper_on_creation() {
    var s = make(); if (!s) return
    compare(s.status, "watching")
    verify(s.helperProc !== null, "no helperProc")
    compare(s.helperProc.running, true)
    compare(s.helperProc.command, ["python3", s.backendDir + "runs/runs-alerts.py"])
    compare(s.retryTimer.running, false)
    compare(s.lastError, "")
    s.destroy()
  }

  // A retryable envelope + exit 1: one warn, waiting 300 s, then the timer
  // relaunches a new process with the same command.
  function retryableFailure_waits_then_relaunches(type) {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning(type))
    var first = s.helperProc
    line(s, envelope(type))
    first.exited(1)
    compare(s.status, "waiting")
    compare(s.retryTimer.running, true)
    compare(s.retryTimer.interval, 300000)
    compare(s.retryTimer.repeat, false)
    compare(s.lastError, type + ": the " + type + " message")
    compare(s.helperProc, null)
    s.retryTimer.triggered()
    compare(s.status, "watching")
    verify(s.helperProc !== null, "no relaunch")
    verify(s.helperProc !== first, "the old process came back")
    compare(s.helperProc.command, ["python3", s.backendDir + "runs/runs-alerts.py"])
    compare(s.helperProc.running, true)
    compare(s.retryTimer.running, false)
    compare(s.lastError, type + ": the " + type + " message")
    s.destroy()
  }

  function test_am_missing_waits_then_relaunches() {
    retryableFailure_waits_then_relaunches("AmMissing")
  }

  function test_helper_error_waits_then_relaunches() {
    retryableFailure_waits_then_relaunches("HelperError")
  }

  function test_store_busy_waits_like_helper_error() {
    retryableFailure_waits_then_relaunches("StoreBusyError")
  }

  function test_a_non_zero_exit_without_envelope_waits() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning("RunAlertsService: runs-alerts.py exited 2 -- retrying in 300 s")
    s.helperProc.exited(2)
    compare(s.status, "waiting")
    compare(s.retryTimer.running, true)
    compare(s.lastError, "runs-alerts.py exited 2")
    compare(s.helperProc, null)
    s.destroy()
  }

  // A fatal envelope + exit 1: one warn, stopped for good.
  function fatalFailure_stops(type) {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(stopWarning(type))
    line(s, envelope(type))
    s.helperProc.exited(1)
    compare(s.status, "stopped")
    compare(s.retryTimer.running, false)
    compare(s.helperProc, null)
    compare(s.lastError, type + ": the " + type + " message")
    s.retryTimer.triggered()
    compare(s.helperProc, null)
    compare(s.status, "stopped")
    s.destroy()
  }

  function test_schema_mismatch_stops() {
    fatalFailure_stops("SchemaMismatch")
  }

  function test_corrupt_journal_stops() {
    fatalFailure_stops("CorruptJournal")
  }

  function test_exit_zero_is_not_relaunched() {
    failOnWarning(/RunAlertsService/)
    var s = make(); if (!s) return
    s.helperProc.exited(0)
    compare(s.status, "stopped")
    compare(s.retryTimer.running, false)
    compare(s.helperProc, null)
    compare(s.lastError, "")
    s.destroy()

    var t = make(); if (!t) return
    line(t, envelope("AmMissing"))
    t.helperProc.exited(0)
    compare(t.status, "stopped")
    compare(t.retryTimer.running, false)
    compare(t.lastError, "")
    t.retryTimer.triggered()
    compare(t.helperProc, null)
    t.destroy()
  }

  function test_the_last_envelope_decides() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    line(s, envelope("SchemaMismatch"))
    line(s, envelope("AmMissing"))
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    compare(s.lastError, "AmMissing: the AmMissing message")
    s.destroy()
  }

  function test_the_timer_runs_only_while_waiting() {
    var s = make(); if (!s) return
    ignoreWarning(retryWarning("HelperError"))
    ignoreWarning(stopWarning("CorruptJournal"))
    failOnWarning(/RunAlertsService/)
    compare(s.retryTimer.running, false)
    line(s, envelope("HelperError"))
    s.helperProc.exited(1)
    compare(s.retryTimer.running, true)
    s.retryTimer.triggered()
    compare(s.status, "watching")
    compare(s.retryTimer.running, false)
    line(s, envelope("CorruptJournal"))
    s.helperProc.exited(1)
    compare(s.status, "stopped")
    compare(s.retryTimer.running, false)
    s.destroy()
  }

  // In one synchronous block, so p1's deferred destroy() has not run yet.
  function test_a_replaced_launch_is_ignored() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    var p1 = s.helperProc
    line(s, envelope("AmMissing"))
    p1.exited(1)
    s.retryTimer.triggered()
    var p2 = s.helperProc
    verify(p2 !== null && p2 !== p1, "no new launch")
    p1.stdout.read(JSON.stringify(envelope("SchemaMismatch")))
    p1.exited(1)
    compare(s.status, "watching")
    compare(s.helperProc, p2)
    compare(s.retryTimer.running, false)
    compare(s.lastError, "AmMissing: the AmMissing message")
    s.destroy()
  }

  function test_destruction_stops_the_helper() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    var proc = s.helperProc
    var recorded = []
    proc.runningChanged.connect(function() { recorded.push(proc.running) })
    s.destroy()
    wait(0)
    compare(recorded, [false])
  }

  function test_destruction_while_waiting_warns_nothing() {
    var s = make(); if (!s) return
    failOnWarning(/./)
    ignoreWarning(retryWarning("HelperError"))
    line(s, envelope("HelperError"))
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    s.destroy()
    wait(0)
  }

  function test_a_timer_fire_while_watching_launches_nothing() {
    var s = make(); if (!s) return
    var proc = s.helperProc
    s.retryTimer.triggered()
    compare(s.status, "watching")
    compare(s.helperProc, proc)
    compare(s.retryTimer.running, false)
    s.destroy()
  }

  function test_a_malformed_envelope_waits() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning("RunAlertsService: unknown error -- retrying in 300 s")
    line(s, { ok: false })
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    compare(s.lastError, "unknown error")
    s.destroy()

    var t = make(); if (!t) return
    ignoreWarning("RunAlertsService: unknown error -- retrying in 300 s")
    line(t, { ok: false, error: "boom" })
    t.helperProc.exited(1)
    compare(t.status, "waiting")
    compare(t.retryTimer.running, true)
    t.destroy()
  }

  function test_a_failed_relaunch_waits_again() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    ignoreWarning(retryWarning("HelperError"))
    line(s, envelope("AmMissing"))
    s.helperProc.exited(1)
    s.retryTimer.triggered()
    line(s, envelope("HelperError"))
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    compare(s.retryTimer.running, true)
    compare(s.lastError, "HelperError: the HelperError message")
    compare(s.helperProc, null)
    s.destroy()
  }

  function test_two_services_are_independent() {
    var a = make(); if (!a) return
    var b = make(); if (!b) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    verify(a.helperProc !== b.helperProc, "one process for two services")
    line(a, envelope("AmMissing"))
    a.helperProc.exited(1)
    compare(a.status, "waiting")
    compare(b.status, "watching")
    compare(b.retryTimer.running, false)
    compare(b.lastError, "")
    verify(b.helperProc !== null, "b lost its process")
    a.destroy()
    b.destroy()
  }
```

Note on `ignoreWarning` / `failOnWarning`: an ignored warning that never comes fails the test, and `failOnWarning` fails on any other matching warning, so each test proves its warns exactly. Calling `s.retryTimer.triggered()` emits the Timer's signal synchronously, so no 300 s wait.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_alerts_service.qml 2>&1 | grep -E "^(FAIL|PASS|Totals)"`
Expected: `Totals: 7 passed, 17 failed` -- the six existing tests PASS; all 17 new `test_*` FAIL (`test_it_launches_the_helper_on_creation`: `Compared values are not the same`; `test_two_services_are_independent`: `'one process for two services' returned FALSE`; the rest: `Uncaught exception: Cannot read property 'stdout' of undefined` or `Cannot call method 'exited' of undefined`, since `helperProc` does not exist yet).

- [ ] **Step 3: Write the implementation**

Replace the whole of `core/stores/RunAlertsService.qml` with:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The plugin's `service` entry point (manifest.json entryPoints.service). The
// shell creates one per shell, with no parent, while the plugin is enabled,
// and destroys it with the plugin; App does not compose it. `backendDir` is
// the absolute path of <plugin>/core/backend/, with a trailing "/" and no
// file:// scheme, derived from this file's own URL -- the same string
// ui/Panel.qml hands App as backendDir.
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc). `status` is "watching" while a launched helper has not
// exited, "waiting" between a retryable failure and the relaunch 300 s later
// (retryTimer, which runs only then), "stopped" after exit 0 or a
// SchemaMismatch / CorruptJournal failure; "stopped" is final for this
// instance. `lastError` is the most recent failure's text; each failure is
// one console.warn line.
Scope {
  id: service

  readonly property string backendDir: Qt.resolvedUrl("../backend/").toString().replace(/^file:\/\//, "")   // <plugin>/core/backend/
  readonly property alias status: alertsState.status        // "watching" | "waiting" | "stopped"
  readonly property alias lastError: alertsState.lastError  // "" until the first failure
  readonly property alias helperProc: alertsState.proc      // the current launch's Process while watching, else null
  readonly property alias retryTimer: retryTimer

  Component.onCompleted: service.launch()

  Component.onDestruction: {
    alertsState.launchSeq += 1
    retryTimer.stop()
    if (alertsState.proc) alertsState.proc.running = false
  }

  // runs-alerts.py, no argument, on a new Process with the next launch number.
  function launch() {
    alertsState.launchSeq += 1
    retryTimer.stop()
    var proc = helperC.createObject(service, { launchSeq: alertsState.launchSeq })
    proc.command = ["python3", service.backendDir + "runs/runs-alerts.py"]
    alertsState.proc = proc
    alertsState.status = "watching"
    proc.running = true
  }

  // A line or exit counts only from the newest launch.
  function isCurrent(proc) {
    return proc.launchSeq === alertsState.launchSeq
  }

  // One stdout line of the current launch. {"ok": false, ...} is kept as the
  // envelope its exit explains. Anything else is ignored. Never throws.
  function helperLine(proc, data) {
    if (!service.isCurrent(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (value.ok === false) proc.envelope = value
  }

  // The current launch ended. Exit 0: stopped, no warning. Otherwise the last
  // envelope line decides: SchemaMismatch and CorruptJournal stop, anything
  // else (or no envelope) waits 300 s for a relaunch.
  function helperExited(proc, exitCode) {
    if (!service.isCurrent(proc)) return
    alertsState.proc = null
    if (exitCode === 0) {
      alertsState.status = "stopped"
      return
    }
    var envelope = proc.envelope
    var err = envelope ? envelope.error : null
    var type = err !== null && typeof err === "object" ? err.type : ""
    alertsState.lastError = envelope ? Runs.errorText(envelope) : "runs-alerts.py exited " + exitCode
    if (type === "SchemaMismatch" || type === "CorruptJournal") {
      alertsState.status = "stopped"
      console.warn("RunAlertsService: " + alertsState.lastError + " -- stopped")
    } else {
      alertsState.status = "waiting"
      retryTimer.start()
      console.warn("RunAlertsService: " + alertsState.lastError + " -- retrying in 300 s")
    }
  }

  Timer {
    id: retryTimer
    objectName: "retryTimer"
    interval: 300000
    repeat: false
    onTriggered: if (alertsState.status === "waiting") service.launch()
  }

  // What the public aliases read; kept apart so consumers cannot write it.
  QtObject {
    id: alertsState
    property string status: "stopped"
    property string lastError: ""
    property var proc: null
    property int launchSeq: 0
  }

  // One Process per launch, so each carries its launch number and envelope.
  Component {
    id: helperC

    Process {
      id: hp
      objectName: "alertsProc"
      property int launchSeq: 0
      property var envelope: null       // the last {"ok": false, ...} line it printed
      stdout: SplitParser { onRead: function(data) { service.helperLine(hp, data) } }
      onExited: function(exitCode) {
        service.helperExited(hp, exitCode)
        hp.destroy()
      }
    }
  }
}
```

Why each piece:
- The private object is named `alertsState`, not `state`: under the test stubs `Scope` is an `Item`, which already has a `state` property.
- `retryTimer` has no `running:` binding; `launch()` stops it and `helperExited` starts it, so a JS `start()`/`stop()` never breaks a binding.
- `Component.onDestruction` bumps `launchSeq` first, so a late `exited` from the stopped helper fails `isCurrent` and warns nothing.
- `hp.destroy()` comes after `helperExited` has read `proc.envelope`; `destroy()` is deferred anyway.

- [ ] **Step 3b: Check what the tests see when a guard is missing (sanity, then restore)**

Temporarily replace `    if (alertsState.proc) alertsState.proc.running = false` with `    // x` and run the fast QML loop: `test_destruction_stops_the_helper` must FAIL. Restore the line. Temporarily replace the first line of `helperExited`'s body (`    if (!service.isCurrent(proc)) return`) with `    // y`: `test_a_replaced_launch_is_ignored` must FAIL. Restore it. Run `git diff --stat` and confirm only the two intended files changed.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_alerts_service.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 24 passed, 0 failed` (23 test functions; qmltestrunner's total counts one extra) and no `TypeError` line other than the pre-existing `BoardScreen.qml:59:7 ... 'width' of null`.

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass (the new imports `Quickshell`, `Quickshell.Io`, `../domain/runs.js` are allowed for `core/stores/`).

Run: `timeout 600 bash tests/run.sh tst_run_alerts_service`
Expected: pytest all pass, then `== tests/core/stores/tst_run_alerts_service.qml` / `Totals: 24 passed, 0 failed`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunAlertsService.qml tests/core/stores/tst_run_alerts_service.qml
git commit -m "feat(alerts): RunAlertsService keeps runs-alerts.py running under the restart policy"
```

---

### Task 2: Alert lines become `alertReceived(alert)`

**Files:**
- Modify: `core/stores/RunAlertsService.qml` (header comment, a new `signal`, `helperLine`)
- Test: `tests/core/stores/tst_run_alerts_service.qml`

**Interfaces:**
- Consumes (from Task 1): `helperLine(proc, data)`, `isCurrent(proc)`, `alertsState`, `helperProc`, `retryTimer`, test helpers `line(s, obj)`, `envelope(type)`, `retryWarning(type)`, `make()`.
- Produces: `signal alertReceived(var alert)` -- the parsed alert object as is (card 2.3 connects to it).

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_alerts_service.qml`, replace the header comment lines

```qml
// It keeps runs-alerts.py running under the restart policy. The stub Process
// spawns nothing: each test plays the helper by emitting stdout.read(line)
// and exited(code) on helperProc.
```

with

```qml
// It keeps runs-alerts.py running under the restart policy and turns its alert
// lines into alertReceived. The stub Process spawns nothing: each test plays
// the helper by emitting stdout.read(line) and exited(code) on helperProc.
```

After the line `  Component { id: hostC; Item { width: 400; height: 400 } }` add:

```qml
  Component { id: spyC; SignalSpy { signalName: "alertReceived" } }
```

After the `stopWarning(type)` helper function add:

```qml

  function alertSpy(s) {
    return createTemporaryObject(spyC, tc, { target: s })
  }
```

Before the file's final closing `}`, after `test_two_services_are_independent`, insert:

```qml

  function test_an_alert_line_emits_alert_received() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    line(s, { alert: { run_id: "r1", root: "/p/one", project: "one", state: "escalated" } })
    line(s, { alert: { run_id: "r2", root: "/p/two", project: "two", state: "dead", gseq: 7 } })
    compare(spy.count, 2)
    compare(spy.signalArguments[0][0], { run_id: "r1", root: "/p/one", project: "one", state: "escalated" })
    compare(spy.signalArguments[1][0], { run_id: "r2", root: "/p/two", project: "two", state: "dead", gseq: 7 })
    compare(s.status, "watching")
    s.destroy()
  }

  function test_other_lines_are_ignored() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    failOnWarning(/./)
    var lines = ["", "   ", "not json", "[1]", "null", "42", "\"x\"",
                 { cursor: 3 }, { alert: null }, { alert: [] }, { alert: "r" },
                 { alert: { state: "escalated" } },
                 { alert: { run_id: "", state: "dead" } },
                 { alert: { run_id: 5, state: "dead" } },
                 { alert: { run_id: "r", state: "running" } },
                 { alert: { run_id: "r" } },
                 { hello: {} }, { ok: true }]
    for (var i = 0; i < lines.length; i++) line(s, lines[i])
    compare(spy.count, 0)
    compare(s.status, "watching")
    compare(s.lastError, "")
    // A valid line afterwards still counts: the handler survived all of the above.
    line(s, { alert: { run_id: "r", state: "dead" } })
    compare(spy.count, 1)
    s.destroy()
  }

  // In one synchronous block, so p1's deferred destroy() has not run yet.
  function test_a_replaced_launch_emits_no_alert() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    ignoreWarning(retryWarning("AmMissing"))
    var p1 = s.helperProc
    line(s, envelope("AmMissing"))
    p1.exited(1)
    s.retryTimer.triggered()
    p1.stdout.read(JSON.stringify({ alert: { run_id: "old", state: "escalated" } }))
    compare(spy.count, 0)
    line(s, { alert: { run_id: "new", state: "escalated" } })
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0].run_id, "new")
    s.destroy()
  }

  function test_an_alert_line_with_surrounding_whitespace_is_read() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    line(s, "  " + JSON.stringify({ alert: { run_id: "r1", state: "escalated" } }) + "\r")
    line(s, "\t" + JSON.stringify({ alert: { run_id: "r2", state: "dead" } }) + "  ")
    compare(spy.count, 2)
    compare(spy.signalArguments[0][0].run_id, "r1")
    compare(spy.signalArguments[1][0].run_id, "r2")
    s.destroy()
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_alerts_service.qml 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `test_an_alert_line_emits_alert_received`, `test_other_lines_are_ignored` (its final `spy.count` 1), `test_a_replaced_launch_emits_no_alert` and `test_an_alert_line_with_surrounding_whitespace_is_read` FAIL (`Compared values are not the same`, count 0 -- the service has no `alertReceived` signal yet): `Totals: 24 passed, 4 failed`.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunAlertsService.qml`, replace the header comment lines

```qml
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc). `status` is "watching" while a launched helper has not
// exited, "waiting" between a retryable failure and the relaunch 300 s later
// (retryTimer, which runs only then), "stopped" after exit 0 or a
// SchemaMismatch / CorruptJournal failure; "stopped" is final for this
// instance. `lastError` is the most recent failure's text; each failure is
// one console.warn line.
```

with

```qml
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc) and emits alertReceived(alert) for each alert line.
// `status` is "watching" while a launched helper has not exited, "waiting"
// between a retryable failure and the relaunch 300 s later (retryTimer, which
// runs only then), "stopped" after exit 0 or a SchemaMismatch /
// CorruptJournal failure; "stopped" is final for this instance. `lastError`
// is the most recent failure's text; each failure is one console.warn line.
```

After the line `  readonly property alias retryTimer: retryTimer` add:

```qml

  // One emission per valid alert line of the current launch: the parsed
  // {run_id, root, project, state, ...} object, untouched.
  signal alertReceived(var alert)
```

Replace the whole `helperLine` function and its comment:

```qml
  // One stdout line of the current launch. {"ok": false, ...} is kept as the
  // envelope its exit explains. Anything else is ignored. Never throws.
  function helperLine(proc, data) {
    if (!service.isCurrent(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (value.ok === false) proc.envelope = value
  }
```

with:

```qml
  // One stdout line of the current launch. {"ok": false, ...} is kept as the
  // envelope its exit explains. {"alert": {run_id: non-empty string, state:
  // "escalated" | "dead", ...}} emits alertReceived with that object.
  // Anything else is ignored. Never throws.
  function helperLine(proc, data) {
    if (!service.isCurrent(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (value.ok === false) { proc.envelope = value; return }
    var alert = value.alert
    if (alert === null || typeof alert !== "object" || Array.isArray(alert)) return
    if (typeof alert.run_id !== "string" || alert.run_id === "") return
    if (alert.state !== "escalated" && alert.state !== "dead") return
    service.alertReceived(alert)
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_alerts_service.qml 2>&1 | grep -E "^(FAIL|Totals)|TypeError|ReferenceError"`
Expected: `Totals: 28 passed, 0 failed`; no `TypeError` other than the pre-existing `BoardScreen.qml:59:7 ... 'width' of null`.

Run: `timeout 600 bash tests/run.sh tst_run_alerts_service`
Expected: pytest all pass, `Totals: 28 passed, 0 failed`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunAlertsService.qml tests/core/stores/tst_run_alerts_service.qml
git commit -m "feat(alerts): RunAlertsService emits alertReceived for each alert line of runs-alerts.py"
```

---

### Task 3: `docs/architecture.md` states the service's contract

**Files:**
- Modify: `docs/architecture.md:95` (the `- \`RunAlertsService.qml\`` bullet; it stays one line, after the `RunDispatchStore.qml` bullet)
- Test: `tests/architecture/test_run_store_docs.py` (existing; no edit)

**Interfaces:**
- Consumes: the public names of Tasks 1-2: `helperProc`, `alertReceived(alert)`, `status`, `lastError`, `retryTimer`.
- Produces: nothing code depends on.

- [ ] **Step 1: Edit the bullet**

In `docs/architecture.md`, the line starting `- \`RunAlertsService.qml\` the manifest's \`service\` entry point:` ends with:

```markdown
and declares none of the properties the shell injects.
```

Append to that same line (one space, then):

```markdown
From creation to destruction it keeps `runs-alerts.py` running as a plain `Process` (`helperProc`, no argument) and emits `alertReceived(alert)` for each `{"alert": {...}}` line whose `run_id` is a non-empty string and whose `state` is `escalated` or `dead`, ignoring every other line; `status` is `watching`, `waiting` or `stopped` and `lastError` the latest failure's text. A non-zero exit relaunches after 300 s (`retryTimer`, which runs only while `waiting`), except a `SchemaMismatch` or `CorruptJournal` envelope, which stops it until the shell creates the service again; exit 0 is not relaunched, and each failure is one `console.warn` line.
```

The bullet must not name `RunStore`, `app.runAlerts`, `app.runs`, `shim`, `controlStore`, `alertsStore` or `dispatchStore` (the edit above names none).

- [ ] **Step 2: Run the docs and architecture tests**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass (including `test_run_store_docs.py`: bullet order and forbidden tokens).

- [ ] **Step 3: Run the full gate**

Run: `timeout 900 bash tests/run.sh`
Expected: pytest all pass, every `== tests/...qml` block shows `Totals: N passed, 0 failed`, no extra `TypeError`/`ReferenceError` lines, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(alerts): RunAlertsService runs runs-alerts.py, relaunches after 300 s and emits alertReceived"
```

---

## Self-review (planner)

- Spec coverage: Public surface → Task 1 (`status`, `lastError`, `helperProc`, `retryTimer`) and Task 2 (`alertReceived`); Launch → Task 1 (`launch`, `onCompleted`, per-launch `Process`, launch number); Lines 1-6 → Task 1 (envelope) and Task 2 (alert); Exit handling table rows 1-4 → Task 1 tests 2-9; timer fire in other status → Task 1 tests 6 and `test_a_timer_fire_while_watching_launches_nothing`; Destruction → Task 1 tests 14-15; Docs → Task 3; spec tests 1-17 → all present (13 split: the policy half in Task 1, the alert half in Task 2 as `test_a_replaced_launch_emits_no_alert`); existing six tests untouched.
- Placeholders: none; every code step carries the code.
- Names: `alertsState`, `helperC`, `hp`, `launch`, `isCurrent`, `helperLine`, `helperExited`, `retryTimer`, `alertReceived`, `line`, `envelope`, `retryWarning`, `stopWarning`, `alertSpy` are used identically across tasks.
- The plan's code blocks were applied verbatim to this repo and run (Qt 6.11.2), then reverted: Task 1 RED `7 passed, 17 failed`, GREEN `24 passed`; Task 2 RED `24 passed, 4 failed`, GREEN `28 passed`; `tests/architecture` passed with the Task 3 text, and the two guard mutations of Task 1 Step 3b each failed their test.
<!-- task-pipeline: validated -->
