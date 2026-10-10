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
