# 2.3 RunAlertsService: snapshot and notify (card 8a6996cc)

Narrowed from `docs/superpowers/specs/2026-10-05-alerts-panel-closed-design.md` (below "the
parent"): Behaviour, "What it says" (lines 92-96: wording from ONE snapshot of that run taken
when the alert line arrives; on snapshot failure the short run id and `escalated` /
`process died`) and "The switch" (lines 97-100: `get-global-settings` `notifyOnEscalation`,
read when an alert arrives; off drops the alert); Architecture, the `RunAlertsService.qml`
bullet (lines 148-154: on an alert line it reads `get-global-settings`, and when on takes the
run snapshot and runs `notify.py`, one `HelperRunner` per launch, as `notifyRunners` today);
Failure modes, row "snapshot of the project fails" (line 184); Testing, the
`tst_run_alerts_service.qml` items "switch off sends nothing; on, one snapshot of that run then
one `notify.py`; snapshot failure falls back" (lines 205-207). Parent story bd7304ee ("Alerts
service"). Blocked by f08d6600 (2.2, done: the service runs `runs-alerts.py` and emits
`alertReceived(alert)`).

This card makes **each `alertReceived` become at most one `notify.py` launch**. Nothing else
about the service changes.

## Starting point

- `core/stores/RunAlertsService.qml` (2.2): root `Scope`; imports `QtQml`, `Quickshell`,
  `Quickshell.Io`, `../domain/runs.js as Runs`. Public: `backendDir`, `status`, `lastError`,
  `helperProc`, `retryTimer`, `signal alertReceived(var alert)`. `helperLine` emits
  `alertReceived(alert)` with the parsed object `{run_id, root, project, state, ...}`
  (`run_id` a non-empty string, `state` `"escalated"` or `"dead"`; `root` and `project` are
  passed through unchecked). Nothing is connected to `alertReceived` yet.
- `core/stores/HelperRunner.qml`: `script`, `guard`, `current` (the newest `Process`),
  `run(args)` builds `["python3", script].concat(args)` and **stops the previous run** on the
  same runner; `signal finished(string stdout, int exitCode, string launchedGuard)` fires for the
  newest run only, when its guard still matches. Stdout is collected by a `StdioCollector`
  into the process's `outText`.
- Model to copy: `core/stores/RunAlertsStore.qml` `notify` / `dropNotifyRunner`, the
  `notifyState` `QtObject` and the `notifyC` Component (`HelperRunner { script: backendDir +
  "runs/notify.py"; guard: ""; onFinished: drop }`), exposed as `readonly property alias
  notifyRunners`. `RunAlertsStore` keeps its own notify path; removing it is a sibling card.
- Helpers (all print one JSON line):
  - `core/backend/projects/viewer-state.py get-global-settings` →
    `{"notifyOnEscalation": <bool>, ...}`; never fails. Reading model:
    `RunControlStore.applyGlobalSettings` (`core/stores/RunControlStore.qml` ~L345):
    `Results.parseEnvelope(stdout)`, on only when `settings.notifyOnEscalation === true`.
  - `core/backend/runs/runs-snapshot.py <project_root>` (docstring lines 1-32): `<project_root>`
    non-empty and not starting with `-`, else `Usage` exit 2; with no argument it snapshots
    **every** project. Prints `{"ok": true, "as_of_seq", "store_id", "runs": [{<am runs row>,
    "status": <am status data>}], "data_dir"}` (exit 0) or `{"ok": false, "error": {...}}`
    (exit 1 or 2). A run older than the selection (non-terminal runs plus the first 10 terminal
    ones of 200 rows) is absent from `runs`.
  - `core/backend/runs/notify.py TITLE BODY`: exactly two arguments.
- Domain (`core/domain/runs.js`): `normalizeRun({row, status})` (L45), `runById(runs, id)`
  (L1353), `alertNotification(run, state, project, runId)` → `{title, body}` (L1002; a run that
  is not an object with a non-empty string id falls back to `shortId({id: runId})`; `"dead"` →
  `"✖ <title> died"` / `"process died"`, otherwise `"‼ <title> escalated"` / the escalation
  reason, or `"escalated"` without a usable run; a non-empty string project appends
  `" · <project>"`). `RunStore.rowOf` (`core/stores/RunStore.qml` L762) strips the `status`
  key from a snapshot entry before `normalizeRun`; it is private to `RunStore`.
- `core/domain/results.js` `parseEnvelope(text)` (L44): the object on the last non-empty line,
  else `null`; never throws.
- Test stubs: `Process` spawns nothing; `StdioCollector` is `{waitForEnd, text, signal
  streamFinished()}`. A test plays a `HelperRunner`'s process by setting `proc.outText` and
  emitting `proc.exited(code)` (`tests/core/stores/tst_run_alerts_store.qml` L73-79, `argv` and
  `reply`).

## Constraints

- Layering (`docs/architecture.md:14`, `tests/architecture/test_layers.py`; parent line 149): a
  `core/stores/` file imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`.
  The service may add `import "../domain/results.js" as Results`. It may use `HelperRunner`
  unqualified (same directory, as `RunAlertsStore` does). It must not reach `RunStore` or any
  other store: the `rowOf` step is a private function of the service.
- No new component file, so no new QML type name (`tests/architecture` duplicate-component
  and icon-glyph rules keep passing with no allowlist edit).
- The service still builds with `createObject(null)` and no properties, and still declares none
  of `shell`, `manifest`, `omarchyPath`, `pluginRegistry`, `barWidgetRegistry`.
- The switch is read **at each alert**, never cached (parent lines 97-100).
- One snapshot per alert, of that alert's root only (card; parent lines 94-95).
- One `HelperRunner` per notification, `guard: ""`, exposed as `notifyRunners` (parent lines
  152-153).
- Two alerts never stop each other (card): no runner is shared between two alerts.
- Docstrings and comments state the contract only, no narrative. TDD: tests first.
- Verification: `bash tests/run.sh` green. Quick loop: `bash tests/run.sh
  tst_run_alerts_service` and `uv run --with pytest python3 -m pytest tests/architecture -q`.

## Behaviour

### Public surface (additions)

| member | kind | contract |
|---|---|---|
| `alertRunners` | `readonly property alias` to a private list | the per-alert `HelperRunner`s in flight (reading the settings or taking the snapshot), oldest first; `[]` when none. Each carries `alert` (the emitted object) and `step` (`"settings"` or `"snapshot"`) |
| `notifyRunners` | `readonly property alias` to a private list | the `notify.py` `HelperRunner`s in flight, oldest first; `[]` when none |

Both lists are replaced (never mutated in place) when a runner joins or leaves, as
`RunAlertsStore.notifyState.runners` is. Existing members are unchanged.

### Per alert

The service handles its own `alertReceived(alert)` (a handler on the root or a `Connections`);
each emission starts one independent pipeline:

1. **Settings.** A new `HelperRunner` (script `backendDir + "projects/viewer-state.py"`,
   `guard: ""`, parented to the service) joins `alertRunners` with `step: "settings"` and runs
   `["get-global-settings"]`. Its command is exactly
   `["python3", <backendDir>projects/viewer-state.py, "get-global-settings"]`.
2. **Switch.** On its `finished(stdout, exitCode)`: the alert goes on only when `exitCode` is
   `0` and `Results.parseEnvelope(stdout)` is an object whose `notifyOnEscalation` is exactly
   `true` (`===`). Otherwise (false, absent, the string `"true"`, `1`, unparsable stdout, empty
   stdout, non-zero exit) the alert is **dropped**: the runner leaves `alertRunners` and is
   destroyed; no snapshot, no `notify.py`, no `console.warn`.
3. **Snapshot.** When on, and `alert.root` is a non-empty string not starting with `-`: the
   same runner sets `step: "snapshot"`, its script becomes `backendDir +
   "runs/runs-snapshot.py"`, and it runs `[alert.root]` once. Command exactly
   `["python3", <backendDir>runs/runs-snapshot.py, <alert.root>]`. (Reusing the runner is safe:
   its settings run has already exited.) When `alert.root` fails that test, no snapshot is
   launched (never `runs-snapshot.py` with no argument, which would snapshot every project) and
   the run is null (step 4's fallback).
4. **The run.** On the snapshot's `finished(stdout, exitCode)` the run is
   `Runs.runById(list, alert.run_id)` where `list` is every entry of `envelope.runs` that is a
   non-null, non-array object, each turned into `Runs.normalizeRun({row: <entry without its
   "status" key, own keys only>, status: entry.status})`, in order. The run is **null** when
   `exitCode !== 0`, the envelope is `null`, `envelope.ok !== true`, `envelope.runs` is not an
   array, or no normalized entry has that id. The runner then leaves `alertRunners` and is
   destroyed.
5. **Notify.** `n = Runs.alertNotification(run, alert.state, project, alert.run_id)` with
   `project` = `alert.project` when it is a string, else `""`. A new `HelperRunner` (script
   `backendDir + "runs/notify.py"`, `guard: ""`, parented to the service) joins
   `notifyRunners` and runs `[String(n.title), String(n.body)]`: command exactly
   `["python3", <backendDir>runs/notify.py, <title>, <body>]` (length 4). Its reply is not read;
   on its `finished` it leaves `notifyRunners` and is destroyed.

Exactly one `notify.py` launch per alert that passes the switch, whatever the snapshot does;
zero for one that does not. Each alert's runners are its own, so a second alert arriving at any
step of the first stops nothing of the first (each `Process.running` stays `true` until the
test exits it). No handler throws, whatever `stdout` holds.

### Destruction

Runners are children of the service and go with it; nothing in this card adds work to
`Component.onDestruction`, and no `notify.py` is launched after the service is destroyed.

### Docs

- The header comment of `RunAlertsService.qml` gains, in contract form: on each
  `alertReceived` it reads `get-global-settings`, drops the alert unless `notifyOnEscalation`
  is exactly true, else snapshots the alert's root once and runs `notify.py` with
  `Runs.alertNotification` (null run when the snapshot fails or lacks the run); `alertRunners`
  and `notifyRunners` are the runners in flight.
- `docs/architecture.md:95`, the `RunAlertsService.qml` bullet, gains one sentence saying the
  same (switch read per alert, one snapshot of that root, one `notify.py` per alert on its own
  `HelperRunner`, `notifyRunners`).

## Tests

All in `tests/core/stores/tst_run_alerts_service.qml`, tier **QML store test** (qmltestrunner
with `tests/stubs`): the behaviour is the service's orchestration of stub processes, which only a
store-level test with stub `Process` objects can drive; the helpers' own output is already pinned
by their pytest tests, and `alertNotification` wording by `tests/core/domain/tst_runs.qml`.
Alerts are injected by emitting a `{"alert": {...}}` line on `helperProc.stdout` (the 2.2 path),
so the tests cover the wiring from line to notification. Test helpers: `argv(proc)` (command
joined with `|`), `reply(proc, text, code)` (set `outText`, emit `exited`), `settingsReply(on)`.
The expected `notify.py` title/body are computed in the test with `Runs.alertNotification` on the
same normalized run, so wording changes in `runs.js` do not break these tests.

1. `test_an_alert_reads_the_global_settings_first`: after one alert line, `alertRunners.length`
   is 1, its `step` is `"settings"`, its process's command is exactly `python3|<backendDir>
   projects/viewer-state.py|get-global-settings`, running; `notifyRunners` is empty.
2. `test_switch_off_sends_nothing` (data-driven over replies: `{"notifyOnEscalation": false}`,
   `{}`, `{"notifyOnEscalation": "true"}`, `{"notifyOnEscalation": 1}`, `"garbage"`, `""`, and
   `{"notifyOnEscalation": true}` with exit 1): after the settings reply, `alertRunners` and
   `notifyRunners` are both empty and no snapshot process was ever launched.
3. `test_switch_on_takes_one_snapshot_of_that_root`: settings `true` → the runner's `step` is
   `"snapshot"` and its command is exactly `python3|<backendDir>runs/runs-snapshot.py|<root>`;
   `notifyRunners` still empty (no notification before the snapshot answers).
4. `test_a_snapshot_with_the_run_notifies_with_its_title`: snapshot reply `{"ok": true, "runs":
   [<other run>, <the run, with a status object>]}` exit 0 → `alertRunners` empty,
   `notifyRunners.length` 1, command exactly `python3|<backendDir>runs/notify.py|<title>|<body>`
   (length 4) where title/body come from `alertNotification(<normalized run>, "escalated",
   <project>, <run_id>)`; title contains the run's title, not its short id; the process is
   running and its `launchGuard` is `""`.
5. `test_the_notify_runner_goes_when_it_exits`: replying to the notify process empties
   `notifyRunners`.
6. `test_a_failed_snapshot_falls_back_to_the_short_id` (data-driven: exit 1 with
   `{"ok": false, "error": {...}}`; exit 0 with garbage; exit 0 with `{"ok": true}` and no
   `runs`; exit 0 with `ok: true` and `runs` lacking the alert's run; exit 2 with an `ok: true`
   line): one `notify.py` with `alertNotification(null, "escalated", project, run_id)`, i.e. the
   short id and body `"escalated"`.
7. `test_a_dead_alert_says_process_died`: state `"dead"`, failed snapshot → title
   `alertNotification(null, "dead", ...)`'s (`✖ … died`), body `"process died"`.
8. `test_an_alert_without_a_usable_root_skips_the_snapshot` (data-driven: no `root`, `""`,
   `"-x"`, a number): settings `true` → no `runs-snapshot.py` process is launched, and one
   `notify.py` goes out with the null-run fallback.
9. `test_a_missing_project_name_is_not_appended` (data-driven: no `project`, `""`, a number):
   the title equals `alertNotification(..., "", ...)`'s (no `" · "`).
10. `test_two_alerts_never_stop_each_other`: alert A reaches the snapshot step, alert B arrives
    → `alertRunners.length` 2, A's snapshot process still `running`; both proceed to
    notification → `notifyRunners.length` 2, the first notify process still `running` after the
    second launches, each with its own alert's text.
11. `test_the_switch_is_read_again_for_each_alert`: alert 1 with settings `true` notifies; alert
    2 launches a new `get-global-settings` read, and with `false` sends nothing.

Existing 2.2 tests keep passing unchanged. `tests/architecture` (pytest tier: layer imports,
duplicate components, glyph rules) must pass with no edit.

## Out of scope

- The persisted cursor, `store_id`, `{"cursor": N}` and `gseq` handling, dismissal (sibling
  cards of story bd7304ee and later).
- Removing `notify.py` from `RunAlertsStore`, the Runs screen switch label/caption (sibling
  cards).
- `runs-snapshot.py --run RUN` (the parent allows `am status RUN`; the card fixes the root
  snapshot).
- De-duplicating notifications across alerts for the same run (the helper emits one alert per
  run and state).
- Any change to helpers in `core/backend/`, to `HelperRunner`, `runs.js` or `results.js`.

## For the planner

One plan task is enough (one file of code plus its test file and the two doc touches), but a
split into (a) settings read + drop, (b) snapshot + notify + fallback, (c) concurrency and docs
is reasonable if each carries its own red/green cycle. Follow the writing-plans format in the
brief.

Review focus the plan should pin (inputs this spec implies that are easy to miss):
- `alert.root` absent or flag-like: must never launch `runs-snapshot.py` with no argument
  (it would snapshot every project).
- A snapshot entry's `status` key is the `am status` object: stripping it from the row before
  `normalizeRun` is required, or the run's status reads `[object Object]`.
- A stale `finished` from a previous step on the reused runner must not double-advance: the
  runner's `step` decides what a `finished` means.
- `notifyOnEscalation` truthy but not `true` (`"true"`, `1`) is off.
- A second alert for the same run while the first is in flight is a second, independent
  pipeline (two notifications); nothing merges them.

---

# 2.3 RunAlertsService: snapshot and notify — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each `alertReceived(alert)` of `RunAlertsService` becomes at most one `notify.py` launch: read `get-global-settings` at each alert, drop the alert unless `notifyOnEscalation === true`, else snapshot the alert's root once and notify with `Runs.alertNotification`.

**Architecture:** The service handles its own `alertReceived` with `onAlertReceived`. Each alert gets its own `HelperRunner` (`alertRunners`, carrying `alert` and `step`) that first runs `viewer-state.py get-global-settings` and then, reused, `runs-snapshot.py <root>`; the runner's `step` decides what each `finished` means. Each notification gets one more `HelperRunner` of its own (`notifyRunners`, as `RunAlertsStore` does), so no runner is shared between two alerts.

**Tech Stack:** QML (Quickshell `Scope`, `Quickshell.Io`), plain JS domain modules (`core/domain/runs.js`, `core/domain/results.js`), qmltestrunner with `tests/stubs`, pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/2-3-runalertsservice-8a6996cc.md` (reproduced above).

## Global Constraints

- A `core/stores/` file imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`; the service adds exactly `import "../domain/results.js" as Results`.
- `HelperRunner` is used unqualified (same directory); the service never reaches `RunStore` or any other store (its `rowOf` is its own function).
- No new component file, no new QML type name; `tests/architecture` passes with no allowlist edit.
- The service still builds with `createObject(null)` and no properties, and declares none of `shell`, `manifest`, `omarchyPath`, `pluginRegistry`, `barWidgetRegistry`.
- The switch is read at each alert, never cached.
- One snapshot per alert, of that alert's root only; never `runs-snapshot.py` with no argument.
- One `HelperRunner` per notification, `guard: ""`, exposed as `notifyRunners`; no runner is shared between two alerts.
- `alertRunners` and `notifyRunners` are replaced, never mutated in place.
- Docstrings and comments state the contract only, no narrative. TDD: tests first.
- Verification: `bash tests/run.sh` green. Quick loop: `bash tests/run.sh tst_run_alerts_service` and `uv run --with pytest python3 -m pytest tests/architecture -q`.
- No change to `core/backend/`, `HelperRunner.qml`, `runs.js`, `results.js` or `RunAlertsStore.qml`.

## Review Focus

1. **`alert.root` absent, `""`, flag-like (`"-x"`) or not a string** — must never launch `runs-snapshot.py` (with no argument it snapshots every project); one `notify.py` with the null-run fallback goes out instead. Pinned by Task 2 `test_an_alert_without_a_usable_root_skips_the_snapshot`.
2. **A repeated or stale exit on the reused runner** — an exit replayed after the step advanced (or after the runner was dropped) must not launch a second snapshot or a second notification; the runner's `step` decides, and a dropped runner's `step` is `""`. Pinned by Task 2 `test_a_repeated_exit_never_advances_twice`.
3. **`notifyOnEscalation` truthy but not `true`** (`"true"`, `1`), unparsable or empty stdout, or `true` with a non-zero exit — off, silently. Pinned by Task 1 `test_switch_off_sends_nothing` (data rows) with `failOnWarning(/./)`.
4. **The same alert twice while the first is in flight** — two independent pipelines, two notifications, nothing merged. Pinned by Task 2 `test_the_same_alert_twice_notifies_twice`.
5. **A snapshot entry's `status` key is the `am status` object** — it must be stripped from the row before `normalizeRun`, or a run whose status object lacks `run.status` reads `"[object Object]"`. The notification text does not show a run's status, so no test can observe it through `notify.py`; Task 2's `rowOf` copies `RunStore.rowOf` exactly and the reviewer checks it. Also pinned indirectly: Task 2's fixtures carry a `status` object and the tests compute the expected run with the same stripping.

## File Structure

- Modify `core/stores/RunAlertsService.qml` — adds the per-alert pipeline: `onAlertReceived`, `startAlert`, `alertStepFinished`, `dropAlertRunner`, `snapshotRun`, `rowOf`, `notify`, `dropNotifyRunner`, the `pipelineState` `QtObject`, the `alertC` and `notifyC` `Component`s, the `Results` import, the two public aliases and the header comment.
- Modify `tests/core/stores/tst_run_alerts_service.qml` — adds the `Runs` import, helpers and the pipeline tests after the existing 2.2 tests (which stay unchanged).
- Modify `docs/architecture.md:95` — one sentence appended to the `RunAlertsService.qml` bullet.

---

### Task 1: An alert reads the global settings and is dropped unless the switch is on

**Files:**
- Modify: `core/stores/RunAlertsService.qml` (imports at lines 1-4; public aliases at lines 22-26; new functions after `helperExited`, line 97; new `QtObject` and `Component` before the closing `}` at line 132)
- Test: `tests/core/stores/tst_run_alerts_service.qml` (imports at lines 8-10; new helpers and tests before the closing `}` at line 425)

**Interfaces:**
- Consumes: `HelperRunner` (`script`, `guard`, `current`, `seq`, `run(args)`, `signal finished(string stdout, int exitCode, string launchedGuard)`); `Results.parseEnvelope(text)` → object or `null`; the service's existing `signal alertReceived(var alert)`.
- Produces:
  - `readonly property alias alertRunners` → `pipelineState.alertRunners` (array of `HelperRunner`, each with `property var alert` and `property string step`, `"settings"` | `"snapshot"` while listed, `""` once dropped).
  - `readonly property alias notifyRunners` → `pipelineState.notifyRunners` (array of `HelperRunner`; stays `[]` in this task).
  - `function startAlert(alert)`; `function alertStepFinished(runner, stdout, exitCode)`; `function dropAlertRunner(runner)`.
  - Test helpers `argv(proc)`, `reply(proc, text, code)`, `settingsReply(on)`, `alertOf(fields)`, `sendAlert(s, alert)`, `settingsCmd(s)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_alerts_service.qml`, add the domain import after `import Qt.labs.folderlistmodel` (line 10):

```qml
import "../../../core/domain/runs.js" as Runs
```

Extend the file's header comment (lines 1-7) by appending these lines after line 7 (`// the helper by emitting stdout.read(line) and exited(code) on helperProc.`):

```qml
// Each alert runs its own pipeline: get-global-settings, then (switch on) one
// runs-snapshot.py of the alert's root, then one notify.py. Tests play each
// HelperRunner's process with reply(proc, stdout, code).
```

Then, before the final closing `}` of the `TestCase` (after `test_an_alert_line_with_surrounding_whitespace_is_read`), add:

```qml
  // ---- the per-alert pipeline (2.3)

  property string runId: "20261010T025704Z-aaaaaaaa"

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // A get-global-settings reply with the switch at `on`.
  function settingsReply(on) { return JSON.stringify({ notifyOnEscalation: on }) }

  // An escalated alert for runId in /p/alpha, with `fields` laid over it.
  function alertOf(fields) {
    var a = { run_id: tc.runId, root: "/p/alpha", project: "alpha", state: "escalated" }
    for (var k in fields) a[k] = fields[k]
    return a
  }

  // One alert line of the current launch.
  function sendAlert(s, alert) { line(s, { alert: alert }) }

  function settingsCmd(s) {
    return "python3|" + s.backendDir + "projects/viewer-state.py|get-global-settings"
  }

  function test_an_alert_reads_the_global_settings_first() {
    var s = make(); if (!s) return
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 0)
    sendAlert(s, alertOf({}))
    compare(s.alertRunners.length, 1)
    var r = s.alertRunners[0]
    compare(r.step, "settings")
    compare(r.guard, "")
    compare(r.alert.run_id, tc.runId)
    compare(argv(r.current), settingsCmd(s))
    compare(r.current.running, true)
    compare(s.notifyRunners.length, 0)
    s.destroy()
  }

  function test_switch_off_sends_nothing_data() {
    return [
      { tag: "false", text: settingsReply(false), code: 0 },
      { tag: "absent", text: "{}", code: 0 },
      { tag: "the string true", text: settingsReply("true"), code: 0 },
      { tag: "one", text: settingsReply(1), code: 0 },
      { tag: "garbage", text: "garbage", code: 0 },
      { tag: "empty", text: "", code: 0 },
      { tag: "true but exit 1", text: settingsReply(true), code: 1 }
    ]
  }

  function test_switch_off_sends_nothing(data) {
    var s = make(); if (!s) return
    failOnWarning(/./)
    sendAlert(s, alertOf({}))
    var r = s.alertRunners[0]
    var settingsProc = r.current
    reply(settingsProc, data.text, data.code)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 0)
    // The runner's destroy() is deferred: in this block it still shows it never ran again.
    compare(r.seq, 1, "a second process was launched")
    compare(r.current, settingsProc)
    compare(r.step, "")
    s.destroy()
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_alerts_service`
Expected: FAIL lines for `test_an_alert_reads_the_global_settings_first` and every `test_switch_off_sends_nothing` row (e.g. `Actual (): undefined` / `TypeError: Cannot read property 'length' of undefined` on `s.alertRunners`); the 2.2 tests still pass.

- [ ] **Step 3: Write the minimal implementation**

In `core/stores/RunAlertsService.qml`, add after `import "../domain/runs.js" as Runs` (line 4):

```qml
import "../domain/results.js" as Results
```

Add after `readonly property alias retryTimer: retryTimer` (line 26):

```qml
  readonly property alias alertRunners: pipelineState.alertRunners    // per-alert settings / snapshot runners in flight, oldest first
  readonly property alias notifyRunners: pipelineState.notifyRunners  // notify.py runners in flight, oldest first
```

Add after `signal alertReceived(var alert)` (line 30):

```qml

  onAlertReceived: function(alert) { service.startAlert(alert) }
```

Add after the closing `}` of `function helperExited` (line 97):

```qml

  // One alert's pipeline, on a HelperRunner of its own: get-global-settings,
  // read at each alert.
  function startAlert(alert) {
    var runner = alertC.createObject(service, { alert: alert, script: service.backendDir + "projects/viewer-state.py" })
    pipelineState.alertRunners = pipelineState.alertRunners.concat([runner])
    runner.run(["get-global-settings"])
  }

  // The newest run of an alert's runner finished; its step says which run it
  // was. Settings: the alert goes on only on exit 0 with notifyOnEscalation
  // exactly true, else it is dropped. Never throws.
  function alertStepFinished(runner, stdout, exitCode) {
    if (runner.step === "settings") {
      var settings = exitCode === 0 ? Results.parseEnvelope(stdout) : null
      if (settings === null || settings.notifyOnEscalation !== true) {
        service.dropAlertRunner(runner)
        return
      }
    }
  }

  // The runner leaves alertRunners; its step becomes "" so no later exit
  // advances it.
  function dropAlertRunner(runner) {
    runner.step = ""
    pipelineState.alertRunners = pipelineState.alertRunners.filter(function(r) { return r !== runner })
    runner.destroy()
  }
```

Add before the `// One Process per launch, so each carries its launch number and envelope.` comment (line 116):

```qml
  // The runners in flight; kept apart so consumers cannot write them.
  QtObject {
    id: pipelineState
    property var alertRunners: []
    property var notifyRunners: []
  }

  // One HelperRunner per alert: settings first, then the snapshot. Guard "".
  Component {
    id: alertC

    HelperRunner {
      id: ar
      property var alert: null
      property string step: "settings"   // "settings" | "snapshot"; "" once dropped
      guard: ""
      onFinished: function(stdout, exitCode) { service.alertStepFinished(ar, stdout, exitCode) }
    }
  }

```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_alerts_service`
Expected: `Totals: … passed, 0 failed`, no `TypeError` / `ReferenceError` lines, exit status 0.

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunAlertsService.qml tests/core/stores/tst_run_alerts_service.qml
git commit -m "feat(alerts): RunAlertsService reads get-global-settings for each alert and drops it unless notifyOnEscalation is true"
```

---

### Task 2: Switch on: one snapshot of that root, then one `notify.py`, with the fallbacks; docs

**Files:**
- Modify: `core/stores/RunAlertsService.qml` (header comment lines 12-13 — line numbers as before Task 1; `function alertStepFinished` from Task 1; new functions after `dropAlertRunner`; new `Component` after `alertC`)
- Modify: `docs/architecture.md:95` (end of the `RunAlertsService.qml` bullet)
- Test: `tests/core/stores/tst_run_alerts_service.qml` (after Task 1's tests, before the closing `}`)

**Interfaces:**
- Consumes (Task 1): `alertRunners`, `notifyRunners`, `startAlert(alert)`, `alertStepFinished(runner, stdout, exitCode)`, `dropAlertRunner(runner)`, `pipelineState`, the `alertC` runner's `alert` / `step`; test helpers `argv`, `reply`, `settingsReply`, `alertOf`, `sendAlert`, `settingsCmd`, `tc.runId`. From `runs.js`: `normalizeRun({row, status})`, `runById(runs, id)`, `alertNotification(run, state, project, runId)` → `{title, body}`, `shortId(run)`, `hasKey(map, key)`.
- Produces: `function snapshotRun(stdout, exitCode, runId)` → normalized run or `null`; `function rowOf(entry)` → entry without its `status` key (own keys only); `function notify(alert, run)`; `function dropNotifyRunner(runner)`; the `notifyC` Component. Test helpers `snapshotCmd(s, root)`, `notifyCmd(s, n)`, `runEntry(id, milestone)`, `normalized(entry)`, `snapshotReply(entries)`, `toSnapshot(s, alert)`.

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_alerts_service.qml`, add after `test_switch_off_sends_nothing` (before the final closing `}`):

```qml
  function snapshotCmd(s, root) {
    return "python3|" + s.backendDir + "runs/runs-snapshot.py|" + root
  }

  // The notify.py command for notification n ({title, body}).
  function notifyCmd(s, n) {
    return "python3|" + s.backendDir + "runs/notify.py|" + n.title + "|" + n.body
  }

  // One runs-snapshot.py entry: the `am runs` row with its `status` replaced by
  // the `am status` object, whose one failed phase gives the escalation reason.
  function runEntry(id, milestone) {
    return {
      id: id, repo_dir: "/p/alpha", workflow: "milestone",
      status: {
        run: { id: id, milestone_id: milestone, status: "escalated" },
        stories: [{ card_id: "s1", subtasks: [{ card_id: "c1",
          phases: [{ name: "verify", status: "failed", detail: "verify failed in " + milestone }] }] }]
      }
    }
  }

  // The run the service must find for `entry`: its row without `status`, normalized.
  function normalized(entry) {
    var row = {}
    for (var k in entry) if (k !== "status") row[k] = entry[k]
    return Runs.normalizeRun({ row: row, status: entry.status })
  }

  function snapshotReply(entries) {
    return JSON.stringify({ ok: true, as_of_seq: 3, store_id: "st", runs: entries, data_dir: "/d" })
  }

  // Sends `alert`, answers its settings with true; returns its runner, now at the snapshot step.
  function toSnapshot(s, alert) {
    sendAlert(s, alert)
    var r = s.alertRunners[s.alertRunners.length - 1]
    reply(r.current, settingsReply(true), 0)
    return r
  }

  function test_switch_on_takes_one_snapshot_of_that_root() {
    var s = make(); if (!s) return
    var r = toSnapshot(s, alertOf({}))
    compare(s.alertRunners.length, 1)
    compare(s.alertRunners[0], r)
    compare(r.step, "snapshot")
    compare(argv(r.current), snapshotCmd(s, "/p/alpha"))
    compare(r.current.running, true)
    compare(r.seq, 2, "exactly one snapshot after the settings read")
    compare(s.notifyRunners.length, 0, "no notification before the snapshot answers")
    s.destroy()
  }

  function test_a_snapshot_with_the_run_notifies_with_its_title() {
    var s = make(); if (!s) return
    var r = toSnapshot(s, alertOf({}))
    var mine = runEntry(tc.runId, "M1")
    reply(r.current, snapshotReply([runEntry("20261010T000000Z-bbbbbbbb", "M0"), mine]), 0)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 1)
    var n = Runs.alertNotification(normalized(mine), "escalated", "alpha", tc.runId)
    var proc = s.notifyRunners[0].current
    compare(argv(proc), notifyCmd(s, n))
    compare(proc.command.length, 4)
    verify(n.title.indexOf("M1") >= 0, n.title)
    verify(n.title.indexOf(Runs.shortId({ id: tc.runId })) === -1, n.title)
    compare(n.body, "verify failed in M1")
    compare(proc.running, true)
    compare(proc.launchGuard, "")
    compare(s.notifyRunners[0].guard, "")
    s.destroy()
  }

  function test_the_notify_runner_goes_when_it_exits() {
    var s = make(); if (!s) return
    var r = toSnapshot(s, alertOf({}))
    reply(r.current, snapshotReply([runEntry(tc.runId, "M1")]), 0)
    compare(s.notifyRunners.length, 1)
    reply(s.notifyRunners[0].current, "", 0)
    compare(s.notifyRunners.length, 0)
    s.destroy()
  }

  function test_a_failed_snapshot_falls_back_to_the_short_id_data() {
    return [
      { tag: "ok false, exit 1", text: JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }), code: 1 },
      { tag: "garbage, exit 0", text: "garbage", code: 0 },
      { tag: "ok without runs", text: JSON.stringify({ ok: true }), code: 0 },
      { tag: "runs is not an array", text: JSON.stringify({ ok: true, runs: {} }), code: 0 },
      { tag: "runs lacks the run", text: JSON.stringify({ ok: true, runs: [null, [1], 7, { id: "other" }] }), code: 0 },
      { tag: "an ok line with exit 2", text: JSON.stringify({ ok: true, runs: [runEntry(tc.runId, "M1")] }), code: 2 }
    ]
  }

  function test_a_failed_snapshot_falls_back_to_the_short_id(data) {
    var s = make(); if (!s) return
    var r = toSnapshot(s, alertOf({}))
    reply(r.current, data.text, data.code)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 1)
    var n = Runs.alertNotification(null, "escalated", "alpha", tc.runId)
    verify(n.title.indexOf(Runs.shortId({ id: tc.runId })) >= 0, n.title)
    compare(n.body, "escalated")
    compare(argv(s.notifyRunners[0].current), notifyCmd(s, n))
    s.destroy()
  }

  function test_a_dead_alert_says_process_died() {
    var s = make(); if (!s) return
    var r = toSnapshot(s, alertOf({ state: "dead" }))
    reply(r.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }), 1)
    var n = Runs.alertNotification(null, "dead", "alpha", tc.runId)
    verify(n.title.indexOf("✖") === 0, n.title)
    compare(n.body, "process died")
    compare(s.notifyRunners.length, 1)
    compare(argv(s.notifyRunners[0].current), notifyCmd(s, n))
    s.destroy()
  }

  function test_an_alert_without_a_usable_root_skips_the_snapshot_data() {
    return [
      { tag: "no root", root: undefined },
      { tag: "empty root", root: "" },
      { tag: "flag-like root", root: "-x" },
      { tag: "a number", root: 42 }
    ]
  }

  function test_an_alert_without_a_usable_root_skips_the_snapshot(data) {
    var s = make(); if (!s) return
    var alert = alertOf({})
    if (data.root === undefined) delete alert.root
    else alert.root = data.root
    sendAlert(s, alert)
    var r = s.alertRunners[0]
    var settingsProc = r.current
    reply(settingsProc, settingsReply(true), 0)
    compare(r.seq, 1, "a runs-snapshot.py process was launched")
    compare(r.current, settingsProc)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 1)
    var n = Runs.alertNotification(null, "escalated", "alpha", tc.runId)
    compare(argv(s.notifyRunners[0].current), notifyCmd(s, n))
    s.destroy()
  }

  function test_a_missing_project_name_is_not_appended_data() {
    return [
      { tag: "no project", project: undefined },
      { tag: "empty project", project: "" },
      { tag: "a number", project: 7 }
    ]
  }

  function test_a_missing_project_name_is_not_appended(data) {
    var s = make(); if (!s) return
    var alert = alertOf({})
    if (data.project === undefined) delete alert.project
    else alert.project = data.project
    var r = toSnapshot(s, alert)
    var mine = runEntry(tc.runId, "M1")
    reply(r.current, snapshotReply([mine]), 0)
    var n = Runs.alertNotification(normalized(mine), "escalated", "", tc.runId)
    verify(n.title.indexOf(" · ") === -1, n.title)
    compare(argv(s.notifyRunners[0].current), notifyCmd(s, n))
    s.destroy()
  }

  function test_two_alerts_never_stop_each_other() {
    var s = make(); if (!s) return
    var idB = "20261010T030000Z-cccccccc"
    var a = toSnapshot(s, alertOf({}))
    var aSnap = a.current
    sendAlert(s, alertOf({ run_id: idB, root: "/p/beta", project: "beta" }))
    compare(s.alertRunners.length, 2)
    var b = s.alertRunners[1]
    verify(b !== a, "the second alert reused the first one's runner")
    compare(aSnap.running, true)
    compare(argv(b.current), settingsCmd(s))
    reply(b.current, settingsReply(true), 0)
    compare(argv(b.current), snapshotCmd(s, "/p/beta"))
    compare(aSnap.running, true)
    var mine = runEntry(tc.runId, "M1")
    reply(aSnap, snapshotReply([mine]), 0)
    compare(s.notifyRunners.length, 1)
    var first = s.notifyRunners[0].current
    compare(b.current.running, true)
    reply(b.current, "garbage", 1)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 2)
    compare(first.running, true)
    compare(argv(first), notifyCmd(s, Runs.alertNotification(normalized(mine), "escalated", "alpha", tc.runId)))
    compare(argv(s.notifyRunners[1].current), notifyCmd(s, Runs.alertNotification(null, "escalated", "beta", idB)))
    s.destroy()
  }

  function test_the_same_alert_twice_notifies_twice() {
    var s = make(); if (!s) return
    var a = toSnapshot(s, alertOf({}))
    var b = toSnapshot(s, alertOf({}))
    verify(a !== b, "one runner for two alerts")
    compare(s.alertRunners.length, 2)
    var mine = runEntry(tc.runId, "M1")
    reply(a.current, snapshotReply([mine]), 0)
    reply(b.current, snapshotReply([mine]), 0)
    compare(s.notifyRunners.length, 2)
    var n = Runs.alertNotification(normalized(mine), "escalated", "alpha", tc.runId)
    compare(argv(s.notifyRunners[0].current), notifyCmd(s, n))
    compare(argv(s.notifyRunners[1].current), notifyCmd(s, n))
    compare(s.notifyRunners[0].current.running, true)
    s.destroy()
  }

  function test_the_switch_is_read_again_for_each_alert() {
    var s = make(); if (!s) return
    var r = toSnapshot(s, alertOf({}))
    reply(r.current, snapshotReply([runEntry(tc.runId, "M1")]), 0)
    compare(s.notifyRunners.length, 1)
    sendAlert(s, alertOf({ run_id: "20261010T040000Z-dddddddd" }))
    compare(s.alertRunners.length, 1)
    var second = s.alertRunners[0]
    compare(second.step, "settings")
    compare(argv(second.current), settingsCmd(s))
    reply(second.current, settingsReply(false), 0)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 1, "the switch was off for the second alert")
    s.destroy()
  }

  // In one synchronous block, so the exited processes' deferred destroy() has not run yet.
  function test_a_repeated_exit_never_advances_twice() {
    var s = make(); if (!s) return
    sendAlert(s, alertOf({}))
    var r = s.alertRunners[0]
    var settingsProc = r.current
    reply(settingsProc, settingsReply(true), 0)
    var snapProc = r.current
    reply(settingsProc, settingsReply(true), 0)
    compare(r.seq, 2, "a stale settings exit launched a second snapshot")
    compare(r.current, snapProc)
    reply(snapProc, snapshotReply([runEntry(tc.runId, "M1")]), 0)
    compare(s.notifyRunners.length, 1)
    reply(snapProc, snapshotReply([runEntry(tc.runId, "M1")]), 0)
    compare(s.notifyRunners.length, 1, "a repeated snapshot exit notified twice")
    s.destroy()
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_alerts_service`
Expected: FAIL for every new Task 2 test (e.g. `test_switch_on_takes_one_snapshot_of_that_root`: `Actual (r.step): settings  Expected: snapshot`; the notify tests: `notifyRunners.length` `0` vs `1`, or `TypeError` reading `current` of `undefined`). Task 1 and 2.2 tests still pass.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunAlertsService.qml`, replace Task 1's whole `alertStepFinished` (comment included):

```qml
  // The newest run of an alert's runner finished; its step says which run it
  // was. Settings: the alert goes on only on exit 0 with notifyOnEscalation
  // exactly true, else it is dropped. Never throws.
  function alertStepFinished(runner, stdout, exitCode) {
    if (runner.step === "settings") {
      var settings = exitCode === 0 ? Results.parseEnvelope(stdout) : null
      if (settings === null || settings.notifyOnEscalation !== true) {
        service.dropAlertRunner(runner)
        return
      }
    }
  }
```

with:

```qml
  // The newest run of an alert's runner finished; its step says which run it
  // was. Settings: the alert goes on only on exit 0 with notifyOnEscalation
  // exactly true, else it is dropped. Then one runs-snapshot.py of the
  // alert's root when that is a non-empty string not starting with "-", else
  // straight to notify with a null run. Snapshot: notify with the alert's run
  // in the reply (null when absent). Any other step changes nothing. Never
  // throws.
  function alertStepFinished(runner, stdout, exitCode) {
    var alert = runner.alert
    if (runner.step === "settings") {
      var settings = exitCode === 0 ? Results.parseEnvelope(stdout) : null
      if (settings === null || settings.notifyOnEscalation !== true) {
        service.dropAlertRunner(runner)
        return
      }
      var root = alert.root
      if (typeof root !== "string" || root === "" || root.charAt(0) === "-") {
        service.dropAlertRunner(runner)
        service.notify(alert, null)
        return
      }
      runner.step = "snapshot"
      runner.script = service.backendDir + "runs/runs-snapshot.py"
      runner.run([root])
    } else if (runner.step === "snapshot") {
      service.dropAlertRunner(runner)
      service.notify(alert, service.snapshotRun(stdout, exitCode, alert.run_id))
    }
  }
```

Add after `function dropAlertRunner` (its closing `}`):

```qml

  // The run runId in one runs-snapshot.py reply, normalized; null unless the
  // exit is 0 and the last line is {"ok": true, "runs": [...]} holding it.
  // Entries that are not plain objects are skipped. Never throws.
  function snapshotRun(stdout, exitCode, runId) {
    if (exitCode !== 0) return null
    var envelope = Results.parseEnvelope(stdout)
    if (envelope === null || envelope.ok !== true || !Array.isArray(envelope.runs)) return null
    var runs = []
    for (var i = 0; i < envelope.runs.length; i++) {
      var entry = envelope.runs[i]
      if (entry === null || typeof entry !== "object" || Array.isArray(entry)) continue
      runs.push(Runs.normalizeRun({ row: service.rowOf(entry), status: entry.status }))
    }
    return Runs.runById(runs, runId)
  }

  // The `am runs` summary without its `status` key: the helper replaced the
  // summary's status string with the `am status` object, which normalizeRun
  // must never read as the row's status ("[object Object]").
  function rowOf(entry) {
    var row = {}
    for (var key in entry) {
      if (key !== "status" && Runs.hasKey(entry, key)) row[key] = entry[key]
    }
    return row
  }

  // One notify.py TITLE BODY for an alert, from Runs.alertNotification of run
  // (null: the short-id fallback), on a runner of its own so two never stop
  // each other. The reply is not read.
  function notify(alert, run) {
    var project = typeof alert.project === "string" ? alert.project : ""
    var n = Runs.alertNotification(run, alert.state, project, alert.run_id)
    var runner = notifyC.createObject(service)
    pipelineState.notifyRunners = pipelineState.notifyRunners.concat([runner])
    runner.run([String(n.title), String(n.body)])
  }

  function dropNotifyRunner(runner) {
    pipelineState.notifyRunners = pipelineState.notifyRunners.filter(function(r) { return r !== runner })
    runner.destroy()
  }
```

Add after the `alertC` `Component` (its closing `}`):

```qml

  // One HelperRunner per notification. Guard "". It goes when its process exits.
  Component {
    id: notifyC

    HelperRunner {
      id: nr
      script: service.backendDir + "runs/notify.py"
      guard: ""
      onFinished: service.dropNotifyRunner(nr)
    }
  }
```

Replace the header comment lines

```qml
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc) and emits alertReceived(alert) for each alert line.
```

with:

```qml
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc) and emits alertReceived(alert) for each alert line.
// Each alertReceived runs its own pipeline on a HelperRunner of its own
// (alertRunners; `step` "settings", then "snapshot"): viewer-state.py
// get-global-settings, read at each alert -- the alert is dropped unless
// notifyOnEscalation is exactly true --, then runs-snapshot.py of the
// alert's root, once (none when the root is not a non-empty string or
// starts with "-"), then notify.py TITLE BODY from Runs.alertNotification
// of that run (null when the snapshot fails or lacks it) on one more
// HelperRunner of its own (notifyRunners). No runner serves two alerts.
```

In `docs/architecture.md`, line 95 (the `RunAlertsService.qml` bullet), replace the bullet's ending

```
except a `SchemaMismatch` or `CorruptJournal` envelope, which stops it until the shell creates the service again; exit 0 is not relaunched, and each failure is one `console.warn` line.
```

with:

```
except a `SchemaMismatch` or `CorruptJournal` envelope, which stops it until the shell creates the service again; exit 0 is not relaunched, and each failure is one `console.warn` line. Each `alertReceived` runs its own pipeline: `viewer-state.py get-global-settings`, read at each alert (the alert is dropped unless `notifyOnEscalation` is exactly `true`), then one `runs-snapshot.py` of that alert's `root` (none when the root is not a non-empty string or starts with `-`), then one `notify.py TITLE BODY` from `Runs.alertNotification` (a null run when the snapshot fails or lacks the run), each on a `HelperRunner` of its own -- `alertRunners` for the settings read and the snapshot (`step` `settings` / `snapshot`), `notifyRunners` for the notification (guard `""`, dropped when it exits, its reply unread) -- so two alerts never stop each other.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_alerts_service`
Expected: `Totals: … passed, 0 failed`, no `TypeError` / `ReferenceError` lines.

Run: `uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass (no new import beyond `../domain/results.js`, no new component file).

Run: `bash tests/run.sh`
Expected: pytest green, every QML file `0 failed`, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunAlertsService.qml tests/core/stores/tst_run_alerts_service.qml docs/architecture.md
git commit -m "feat(alerts): RunAlertsService snapshots the alert's root once and runs notify.py per alert"
```

---

## Self-review (planner)

- **Spec coverage:** public surface `alertRunners` / `notifyRunners` (Task 1); per-alert steps 1-2 settings + switch (Task 1), steps 3-5 snapshot, run lookup, notify (Task 2); destruction — runners are children of the service (`createObject(service)`), nothing added to `Component.onDestruction` (Tasks 1-2); docs header + `docs/architecture.md:95` (Task 2); spec tests 1-2 (Task 1), 3-11 (Task 2), plus the Review Focus tests `test_a_repeated_exit_never_advances_twice` and `test_the_same_alert_twice_notifies_twice` (Task 2). The data row `runs is not an array` and the non-object entries in `runs lacks the run` extend spec test 6 with step 4's own null cases.
- **Placeholders:** none; Task 2 repeats Task 1's `alertStepFinished` text in full for the replacement.
- **Types:** `alertStepFinished(runner, stdout, exitCode)`, `dropAlertRunner(runner)`, `notify(alert, run)`, `snapshotRun(stdout, exitCode, runId)`, `rowOf(entry)`, `dropNotifyRunner(runner)`, `pipelineState.alertRunners` / `notifyRunners`, runner `alert` / `step` — same names in both tasks and tests.
- **Review Focus:** items 1-4 each have a test in the owning task; item 5 is unobservable through `notify.py` text and is pinned by code review of `rowOf`, stated in the item.
<!-- task-pipeline: validated -->
