# 4.1 RunStore: control(), pending, lastError (card c1f23024)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-controls-design.md` (S2,
"the parent" below): "Control actions" (lines 29-53), "Architecture" bullet 3
(lines 65-69), "Errors" (lines 138-146) and "Testing" bullet 2 (lines 153-154).
Parent story f03629a7 ("Control store and UI"). Everything this card builds on is
already on this branch: `Runs.controls` / `Runs.controlError` (card adff6c85),
`run-control.py` (b661b0a4), `viewer-state.py get-run-settings` (a36aac36).

This card is the store half only. The buttons, the inline error, the cancel
dialog, the keys and the toasts are sibling cards 4.2-4.4 and read what this card
exposes.

## Starting point

- `core/stores/RunStore.qml` (491 lines) has no control code. It already has a
  `lastError` (line 27), but that is the **snapshot banner**: `applySnapshot`
  sets it to `""` on every good snapshot (line 380) and to the failure text on a
  bad one (lines 392, 402), `watchExited` writes it (lines 180, 186),
  `projectSwitched` clears it (line 214), and `ui/screens/RunsScreen.qml` lines
  52 and 109-110 show it as the screen's banner. See "Decisions" D1.
- `core/stores/HelperRunner.qml`: one script, **latest run wins**. `run()` stops
  the previous Process, and `finished(stdout, exitCode, launchedGuard)` fires
  only when the exit is from the newest launch **and** its launch guard still
  equals `guard`. A single shared runner would kill a pause on run A when the user
  cancels run B straight after (D2).
- `core/domain/runs.js` `normalizeRun` (lines 17-52) returns exactly
  `{id, repo_dir, milestone_id, status, started_at, base_branch, branch_prefix,
  lease, rows, tree}`. It drops two things this card needs: the run's
  `workflow` and the run's control `requests` (D3, D4).
  `tests/core/domain/tst_runs.qml` lines 33 and 52 pin that key list.
- `am`'s own contract (agent-manager README, the "am status" section):
  `am status` data has `control: {lease: {...} | null, requests: [{command,
  requested_at, handled_at}], claims: [...]}`. `requests` covers every life of
  the run in the order made; `handled_at` is `null` until the run has acted on
  the request. An `am runs` row has `workflow`, which is `milestone` or `task`.
  A `--card` run is `task`.
  `am pause|cancel` answer `{"ok": true, "data": {run_id, command, effective,
  requested_at, already_requested, message}}`. A repeat request returns the
  **existing** row's `requested_at` with `already_requested: true`.
- `run-control.py <pause|resume|cancel> RUN REPO [--verify CMD]...
  [--allow-no-verification]` prints one JSON line and exits 0 for every refusal
  or error. It exits 2 only for Usage. Only resume accepts the two options. A
  resume still going after 10 s prints `{"ok": true, "data": {"action":
  "resume", "run_id": RUN, "detached": true}}`. If am exits non-zero without an
  envelope, the helper prints its own `AmFailed` envelope, whose message is the
  tail of am's stderr (parent line 143).
- `viewer-state.py get-run-settings <root>` always exits 0 and prints one
  **bare** object (not an envelope): `{"verify": [...], "allowNoVerification":
  bool, "notifyOnEscalation": bool}`.

## Scope

In scope:

- `core/stores/RunStore.qml`: the control API, the per-request runners, the
  pending lifecycle, the 30 s still-waiting state and the control error.
- `core/domain/runs.js` `normalizeRun`: two new keys, `workflow` and `requests`.
  This is the minimum the store needs to tell a `--card` run from a milestone run
  and to see `handled_at`.
- `tests/core/stores/tst_run_store.qml` and `tests/core/domain/tst_runs.qml`:
  new tests are appended. The only edits to existing tests are the two key-list
  assertions in `tst_runs.qml` (lines 33 and 52), which gain the two keys.
- `docs/architecture.md`: the `RunStore.qml` paragraph (lines 83-94) gains one
  paragraph describing the control state.

### Out of scope

- `ui/components/RunControls.qml`, the inline error under a row, "Pause
  requested…", and wiring into Runs rows, Run detail and `CardDetailScreen`: card
  4.2 (1c268d85).
- The cancel `TypedConfirmDialog`, `p`/`r`/`c` in `Shortcuts.qml`, and flashing a
  disabled action's reason: card 4.3 (b4bc1521). This store's `control("cancel",
  id)` launches straight away. Confirming first is the caller's job.
- `RunToast.qml`, `newAlerts` wiring, `notify.py` and the "Notify on escalation"
  setting: card 4.4 (22153f5f).
- The verify-fields form and the "no verification" opt-out UI that the parent
  opens when no verify set is stored (lines 50-52). This store only refuses with
  a sentence (see "Resume and the verify set"). Writing settings
  (`set-run-settings`) is not done here.
- The Resume confirm step that shows "the verify set about to be reused"
  (parent line 34) is UI and belongs to 4.2/4.3. The store does not expose the
  settings for it.
- "Offers Resume if the lease is dead" on a long wait (parent line 144):
  `controls(run).resume` already says this, and the UI shows it.
- Any backend helper, `HelperRunner.qml`, `App.qml` (it already composes
  `RunStore` at line 106 and needs no new bindings) and
  `tests/contract/test_am_shapes.py`.

## Decisions

- **D1. Control errors get their own fields; the snapshot's `lastError` is left
  alone.** The card says "lastError via controlError". The parent (line 65)
  speaks of a `lastError` as if it were new, but one already exists and is the
  banner. Writing control errors there would show a single run's refusal as the
  screen's banner. The re-snapshot this card requires (parent line 66) would also
  erase it at once, which breaks "show the error once" (parent line 145). So the
  control error is `lastControlError` (the `Runs.controlError` sentence) plus
  `lastControlErrorRunId` (which run it belongs to). Snapshots never touch them.
  The snapshot `lastError` keeps its current behaviour exactly.
- **D2. One `HelperRunner` per request.** Each control request creates its own
  `HelperRunner`, guarded by `store.project`, so each launch's guard is the
  project the request was for (parent line 146). Requests for different runs
  never cancel each other. A reply for a project the user has left is dropped by
  the runner's own guard. This keeps "through HelperRunner" from the card without
  inheriting its latest-wins rule across runs.
  The runner is made from a `Component` (a `HelperRunner` with extra `runId`,
  `action` and request-token properties) parented to the store. A runner has one
  `script`, so a milestone resume sets `script` to `viewer-state.py` for the
  settings step and then to `run-control.py` before the second `run()` on the
  same runner. The runner's `guard` is bound to `store.project`, and it has no
  `onGuardChanged` (the snapshot runner's already runs `projectSwitched()`).
- **D3. A `--card` run is `workflow === "task"`.** `normalizeRun` gains
  `workflow`: `row.workflow`, falling back to `status.run.workflow`, as text,
  `""` when absent. Only `"task"` counts as a card run. A milestone run, or one
  whose workflow is unknown or empty, follows the milestone rule. This is safe
  because `am resume` accepts `--verify` on both workflows (it ignores it on a
  task run), so passing it is never wrong.
- **D4. `requests` are read from `control.requests`.** `normalizeRun` gains
  `requests`: for each element of `status.control.requests` that is an object,
  one fresh `{command, requested_at, handled_at}`, each converted to text, with
  `""` for a missing or null value. So `handled_at === ""` means not handled.
  Non-object elements are skipped. A missing or non-array value gives `[]`. Order
  is kept.
- **D5. Pending clears only after the reply.** While the helper is in flight,
  snapshots never clear `pending`. A watch-driven snapshot during a slow resume
  must not re-enable the buttons and invite a second request. The clearing rules
  below apply once the reply has been acknowledged (`ok: true`).
- **D6. Closing the panel keeps pending.** `stopLive` leaves `pending`, the
  control error and any in-flight request alone. The request is durable in am.
  Reopening refreshes, and the next snapshot settles it. The still-waiting timer
  stops while the panel is closed (stopLive's "no timer left running" rule,
  RunStore.qml lines 104-113).

## Behaviour

### New public surface on `RunStore`

| member | type | meaning |
|---|---|---|
| `control(action, runId)` | function → bool | starts a request. Returns whether it started |
| `pending` | `var` object `{runId: action}` | requests not yet settled. Always a fresh object on change, so bindings update |
| `stillWaiting` | `var` object `{runId: true}` | pending requests that are 30 s or more old |
| `stillWaitingText` | readonly string | exactly `still waiting — the run may be between phases or dead` (parent line 69) |
| `lastControlError` | string | `""`, or the sentence for the last failed request |
| `lastControlErrorRunId` | string | the run that sentence is about, `""` with no error |
| `dismissControlError()` | function | clears both error fields |
| `controlRunners` | readonly `var` list | in-flight request runners, oldest first. Each has `runId`, `action` and the `HelperRunner` API (`current.command`, …). This is the test hook, like `snapshotRunner` |
| `pendingTimer` | readonly alias | the still-waiting Timer (`objectName: "pendingTimer"`) |
| `checkWaiting(nowMs)` | function | recomputes `stillWaiting` against `nowMs`. The timer calls it with `Date.now()`, and tests call it directly |

### `control(action, runId)`

It does nothing and returns `false` when any of these holds, checked in this
order:

1. `project === ""`;
2. `action` is not exactly `"pause"`, `"resume"` or `"cancel"`;
3. `runId` is not a non-empty string, or no run in `runs` has that id;
4. `Runs.controls(run)[action].enabled` is `false` (parent lines 33-35, 44-46.
   The store enforces what the buttons show);
5. `pending[runId]` already exists (parent lines 42-43: no double fires).

Otherwise it:

- clears `lastControlError` and `lastControlErrorRunId`;
- sets `pending[runId] = action` (a new object), records the run's
  `Runs.runState` at this moment as the request's **baseline**, and records the
  launch time. The baseline and launch time are internal, not exposed;
- starts the request (next two sections) and returns `true`.

### Pause and cancel

The request's runner launches exactly
`["python3", backendDir + "runs/run-control.py", action, runId, project]`. The
project root is the REPO argument and is one argv element even with spaces. No
other arguments are passed.

### Resume and the verify set (parent lines 49-53)

- **Card run** (`run.workflow === "task"`): launches
  `["python3", backendDir + "runs/run-control.py", "resume", runId, project]`.
  The settings are not read.
- **Any other run**: first launches
  `["python3", backendDir + "projects/viewer-state.py", "get-run-settings", project]`
  on the request's runner. Its reply decides:
  - `verify` is a non-empty array of strings: launches run-control with
    `"--verify", cmd` pairs in the stored order after `project`.
    `allowNoVerification` is then ignored;
  - otherwise, `allowNoVerification === true`: launches it with a single
    `"--allow-no-verification"` after `project`;
  - otherwise (nothing stored): run-control is **not** launched. `pending[runId]`
    is removed, `lastControlError` becomes exactly
    `Resume needs verify commands: none are stored for this project, and running without verification was not chosen.`,
    `lastControlErrorRunId` becomes `runId`, and nothing is re-snapshotted;
  - a reply that is not a JSON object on its last non-blank line: run-control is
    not launched, `pending[runId]` is removed, and `lastControlError` becomes
    `The run settings gave no usable result (exit N).` (N is the exit code),
    following `applyLogs`' wording (RunStore.qml line 322).

### The control reply

The last non-blank stdout line is parsed the way `parseEnvelope` already does.
The reply only acts if the request is still the one pending for that run (a
request token, so a dropped-then-reissued request cannot be settled by an old
reply).

- `{"ok": true, ...}` (including resume's `detached: true`): `pending[runId]`
  stays, the request is marked **acknowledged**, and if `data.requested_at` is a
  non-empty string it is remembered as the request's id.
- `{"ok": false, "error": ...}`: `pending[runId]` is removed (buttons re-enable,
  parent line 142). `lastControlError = Runs.controlError(envelope)` and
  `lastControlErrorRunId = runId`. This includes `AmFailed`, whose text comes from
  `controlError`'s `errorText` fallback (parent line 143), `AmMissing` and
  `Usage`.
- No usable envelope: `pending[runId]` is removed, and `lastControlError` becomes
  `The run control gave no usable result (exit N).`
- In all three cases, `refresh()` is called straight after (parent line 66). For
  an `UnknownRunError` this snapshot drops the row, while the error stays
  (parent line 145).
- After its reply, applied or dropped by the guard, the request leaves
  `controlRunners` and its runner is destroyed. `HelperRunner` emits `finished`
  only for a reply its guard accepts, so a dropped reply is seen through `busy`
  going `false` instead (the runner clears `busy` on every newest exit, before
  it decides to emit). The store therefore removes a runner either at the end of
  its `finished` handling (applied) or when `busy` becomes `false` and its
  `launchGuard` no longer equals the project it was made for (dropped). It must
  not remove it on every `busy` change: `busy` also drops to `false` just before
  an accepted `finished`, and between the two steps of a milestone resume.

### Settling pending on a snapshot

After every good snapshot (`applySnapshot`'s `ok: true` path), for each runId in
`pending` whose request is acknowledged (D5), the entry is removed when any of
these holds:

1. no run in the new `runs` has that id (vanished);
2. `Runs.runState(run)` differs from the request's baseline (parent line 67: "or
   the run's state changes");
3. for pause and cancel: the matching request in `run.requests` has a non-empty
   `handled_at` (parent line 67). The matching request is the one whose
   `requested_at` equals the reply's remembered `requested_at`. If the reply gave
   none, it is the **last** request whose `command` equals the action.

Resume has no request row. It settles by rule 1 or 2 only. Removing an entry also
removes it from `stillWaiting`. Failed snapshots settle nothing.

### Still waiting (parent lines 68-69, 144)

- `checkWaiting(nowMs)` sets `stillWaiting` (a fresh object) to exactly the
  runIds in `pending` whose launch time is at least 30 000 ms before `nowMs`.
- `pendingTimer`: interval 1000 ms, repeating, running exactly while `active` and
  `pending` is not empty. Each tick calls `checkWaiting(Date.now())`.
- The text the UI shows is `stillWaitingText`.

### Project switch (parent line 146)

`projectSwitched()` additionally empties `pending`, `stillWaiting`, the internal
baselines, launch times and request ids, and both control-error fields. In-flight
runners are **not** stopped, because a control request already launched still
completes in am. Their replies are dropped by the guard, change nothing and do
not re-snapshot. A milestone resume still in its settings step is the one case
that does not complete: its reply is dropped, so run-control is never launched
and nothing is requested. That is intended (the user has left that project). Nothing
else in `projectSwitched` changes.

### Untouched behaviour

Snapshots, the watch, the poll, logs, the snapshot `lastError` / `amStatus`, and
`stopLive` / `startLive` (except for the timer's binding in D6) behave exactly as
today. Every existing test in `tst_run_store.qml`, `tst_app_runs.qml` and
`tst_runs.qml` passes, the two key lists aside.

### Domain: `normalizeRun` (D3, D4)

The output gains `workflow` (string) and `requests` (array). All other keys and
their rules are unchanged. It still never throws. The header comment's input
shape lists `row.workflow` and `status.control.requests`.

## Tests

All tests are written first. `bash tests/run.sh` runs pytest and then every
`tst_*.qml` through qmltestrunner (offscreen, `tests/stubs` Quickshell). Store
tests drive the stubbed Process objects: set `outText`, then call
`exited(code)`. Runs are seeded with the existing `okReply([...])` helper, using
an `entry(...)` variant that sets `workflow` and `control.requests`.

**Domain tier, `tests/core/domain/tst_runs.qml`.** This is pure logic, so it is
tested without a store:

1. `normalizeRun` full raw gives `workflow` from the row, falling back to
   `status.run.workflow`. With neither it gives `""`.
2. `requests` maps `control.requests` to fresh `{command, requested_at,
   handled_at}`, in order. Null `handled_at` becomes `""`. Non-object elements
   are skipped. Missing `control`, missing `requests`, or a non-array value give
   `[]`.
3. The two existing key-list assertions include `requests` and `workflow`.

**Store tier, `tests/core/stores/tst_run_store.qml`.** These test behaviour
that needs the store's state and its processes:

4. Pause argv is exactly `python3 | …/runs/run-control.py | pause | RUN |
   /home/u/my proj` (5 elements). Same for cancel.
5. Milestone resume reads settings first, with argv `python3 |
   …/projects/viewer-state.py | get-run-settings | <project>`. Then
   `verify: ["a", "-b c"]` gives `… resume RUN <project> --verify a --verify -b
   c` in order, and `--allow-no-verification` is absent even when that flag is
   true.
6. Milestone resume with `verify: []` and `allowNoVerification: true` gives
   `… --allow-no-verification`.
7. Milestone resume with neither: no run-control runner is launched, `pending` is
   empty, `lastControlError` is the exact sentence, the run id is set, and no new
   snapshot is launched.
8. Garbled settings reply: no run-control launch, pending cleared, `The run
   settings gave no usable result (exit N).`
9. A `task` run's resume launches run-control directly with no verify arguments,
   and no viewer-state runner exists.
10. `control()` returns `true` and sets `pending[id] === action` on launch.
    `pending` is a new object, which a SignalSpy on `pendingChanged` sees.
11. An `ok: true` reply keeps pending and launches a new snapshot (the
    `snapshotRunner.current` Process changes).
12. An `ok: false` reply (`NotAcceptingError`) removes pending, sets
    `lastControlError === Runs.controlError(envelope)` and the run id, and
    re-snapshots.
13. Garbled control stdout removes pending, gives `The run control gave no usable
    result (exit 1).`, and re-snapshots.
14. `UnknownRunError`: the next snapshot without the run drops the row, while
    `lastControlError` survives that snapshot. A plain good snapshot also leaves
    `lastControlError` alone, and the snapshot `lastError` stays `""`.
15. Settling: an acknowledged pause clears when a snapshot's matching request
    (same `requested_at`) has `handled_at`. It stays while `handled_at` is `""`.
    An older handled pause request with a different `requested_at` does not
    clear it.
16. Settling with no `requested_at` in the reply: the last `pause` request
    decides.
17. Settling by state change: a resume acknowledged on a `dead` run clears when
    the run becomes `running`. It stays while it is still `dead`.
18. Settling by vanishing: the run is absent from the next good snapshot.
19. D5: a snapshot showing a state change while the request is still in flight
    leaves pending set.
20. A failed snapshot (`ok: false`) settles nothing.
21. Guards in order: no project, bad action, empty or unknown id, a disabled
    action (pause on a parked run, cancel during Integrate with `accepting:
    false`), and a second control on a pending run all return `false` and launch
    nothing.
22. Two runs in flight at once: pause A then cancel B. Both runners stay in
    `controlRunners`, and replying to A first then B applies both.
23. A finished request leaves `controlRunners`, both when its reply is applied
    and when the project changed first (the stub `exited(code)` runs with no
    `finished` signal, so the removal rides on `busy`).
24. `checkWaiting(Date.now() + 29 000)` gives no entry (the launch time is
    internal, so tests offset from `Date.now()`), and `checkWaiting(Date.now()
    + 30 000)` gives `stillWaiting[id] === true`. Settling removes it.
    `stillWaitingText` is the exact string.
25. `pendingTimer` runs only while `active` and something is pending. It stops on
    `stopLive`, while `pending` survives `stopLive` (D6).
26. Project switch with a request in flight: `pending`, `stillWaiting` and the
    control error are emptied. The old reply then arrives and changes nothing:
    no pending, no error, and no extra snapshot for the new project.
27. A new `control()` clears a previous `lastControlError`, and
    `dismissControlError()` clears both fields.

**Architecture tier.** `tests/architecture` passes unchanged. `RunStore.qml`
keeps importing only QtQml, Quickshell, Quickshell.Io and `../domain/runs.js`
(`tests/architecture/test_layers.py`). No new Python is added.

## Review focus for the planner

- Every map property (`pending`, `stillWaiting`) must be **reassigned**, never
  mutated in place, or QML bindings will not see the change.
- A runner whose reply is dropped by the guard must still leave
  `controlRunners`, so nothing leaks across project switches.
- `requests` element fields may be absent or not strings in a damaged status.
  `normalizeRun` must never throw on them.
- The `--verify` value may start with `-`. It is one argv element after
  `--verify`, never split or quoted.
