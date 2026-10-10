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
