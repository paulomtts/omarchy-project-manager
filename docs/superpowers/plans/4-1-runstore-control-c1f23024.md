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

---

# 4.1 RunStore control(), pending, lastControlError Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `RunStore` a `control(action, runId)` API that launches pause / resume / cancel through one `HelperRunner` per request, tracks `pending` until a snapshot settles it, marks long waits in `stillWaiting`, and reports failures in `lastControlError` / `lastControlErrorRunId`.

**Architecture:** `runs.js` `normalizeRun` gains `workflow` and `requests` so the store can tell a `--card` run apart and see `handled_at`. `RunStore.qml` gains a `Component` of `HelperRunner`s (each carrying `runId`, `action`, a request `token` and the project it was made in), an internal `controlState` (`runners`, `requests`, `nextToken`), a settle pass in `applySnapshot`'s ok path, extra clearing in `projectSwitched`, and a 1 s `pendingTimer`. Nothing outside these two files, their two test files and `docs/architecture.md` changes.

**Tech Stack:** QML (Qt 6, `QtQml`, Quickshell `Scope`/`Process` stubbed in `tests/stubs`), a `.pragma library` JS domain module, QtTest via `qmltestrunner`, all run by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-1-runstore-control-c1f23024.md` (reproduced in full above this plan).

## Global Constraints

- `core/stores/RunStore.qml` keeps importing only `QtQml`, `Quickshell`, `Quickshell.Io` and `"../domain/runs.js" as Runs` (`tests/architecture/test_layers.py`).
- No new Python. No edit to `core/stores/HelperRunner.qml`, `core/stores/App.qml`, any backend helper or `tests/contract/test_am_shapes.py`.
- `pending` and `stillWaiting` are always **reassigned** with a fresh object, never mutated in place.
- Snapshots never touch `lastControlError` / `lastControlErrorRunId`; control code never touches the snapshot `lastError` / `amStatus`.
- `stillWaitingText` is exactly `still waiting — the run may be between phases or dead`.
- No-verify refusal is exactly `Resume needs verify commands: none are stored for this project, and running without verification was not chosen.`
- Garbled settings is exactly `The run settings gave no usable result (exit N).`; garbled control reply is exactly `The run control gave no usable result (exit N).`
- Pause/cancel argv is exactly `["python3", backendDir + "runs/run-control.py", action, runId, project]`; settings argv is exactly `["python3", backendDir + "projects/viewer-state.py", "get-run-settings", project]`.
- Existing tests in `tst_run_store.qml`, `tst_app_runs.qml` and `tst_runs.qml` stay as they are, except the two key-list strings in `tst_runs.qml` (lines 33 and 52). New tests are appended.
- Verification is `bash tests/run.sh`, which also fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign` or `is not a function` in QML output.

## Review Focus

1. **Leaving a project and coming back (A → B → A) before an old reply lands**: the old reply must not settle, fail or re-snapshot a newer request for the same run (the request token). Test in Task 4 (`test_an_old_reply_after_returning_to_the_project_changes_nothing`).
2. **A resume still going after 10 s answers `{"ok": true, "data": {"detached": true}}` with no `requested_at`**: it must stay pending without an error and settle on the state change. Test in Task 4 (`test_a_resume_settles_when_the_run_state_changes`).
3. **A stored `verify` with a non-string element** (a damaged settings reply): it is not a verify set, so the opt-out or the refusal sentence applies; nothing is stringified into argv. Test in Task 3 (`test_a_verify_set_with_a_non_string_is_not_used`).
4. **Damaged `control.requests` elements** (non-object elements, numbers, booleans, objects as field values): `normalizeRun` never throws and skips or stringifies them. Test in Task 1 (`test_normalize_requests_garbage`).
5. **Closing and reopening the panel with a request pending**: `pending` and the in-flight runner survive, the timer stops and starts again. Test in Task 5 (`test_the_pending_timer_runs_only_while_active_with_something_pending`).

## File Structure

- `core/domain/runs.js` — `normalizeRun` gains `workflow` and `requests` (Task 1).
- `tests/core/domain/tst_runs.qml` — two key lists updated, three tests appended (Task 1).
- `core/stores/RunStore.qml` — control surface, runners, reply handling (Task 2), resume settings step (Task 3), settling and project switch (Task 4), still-waiting timer (Task 5).
- `tests/core/stores/tst_run_store.qml` — one import added, control tests appended (Tasks 2-5).
- `docs/architecture.md` — one paragraph on the control state (Task 5).

---

### Task 1: `normalizeRun` gains `workflow` and `requests`

**Files:**
- Modify: `core/domain/runs.js:6-55`
- Test: `tests/core/domain/tst_runs.qml` (lines 33 and 52, plus new tests before the final `}`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Runs.normalizeRun(raw)` output gains `workflow: string` (`row.workflow`, else `status.run.workflow`, else `""`) and `requests: Array<{command: string, requested_at: string, handled_at: string}>` (from `status.control.requests`; `""` for missing/null fields; non-object elements skipped; `[]` when missing or not an array). Tasks 2-4 read `run.workflow` and `run.requests` on store runs.

- [ ] **Step 1: Update the two key-list assertions**

In `tests/core/domain/tst_runs.qml`, line 33 (inside `checkDefaults`) and line 52 (inside `test_normalize_full`) both read:

```js
"base_branch,branch_prefix,id,lease,milestone_id,repo_dir,rows,started_at,status,tree"
```

Change **both** strings to:

```js
"base_branch,branch_prefix,id,lease,milestone_id,repo_dir,requests,rows,started_at,status,tree,workflow"
```

Nothing else in either function changes.

- [ ] **Step 2: Append the new domain tests**

In `tests/core/domain/tst_runs.qml`, insert these functions just before the file's last line (the `}` that closes `TestCase`):

```js
  // ---- S2 4.1: workflow and control requests ----------------------------------------------

  function test_normalize_workflow() {
    compare(Runs.normalizeRun(fullRaw()).workflow, "orchestrator", "from the am runs row")
    var raw = fullRaw()
    delete raw.row.workflow
    raw.status.run.workflow = "task"
    compare(Runs.normalizeRun(raw).workflow, "task", "falls back to the am status run")
    raw.row.workflow = "milestone"
    compare(Runs.normalizeRun(raw).workflow, "milestone", "the row wins")
    raw.row.workflow = ""
    compare(Runs.normalizeRun(raw).workflow, "task", "an empty row value falls back")
    delete raw.row.workflow
    delete raw.status.run.workflow
    compare(Runs.normalizeRun(raw).workflow, "", "neither gives empty")
    compare(Runs.normalizeRun({ row: { workflow: null }, status: { run: { workflow: null } } }).workflow, "", "nulls")
    compare(Runs.normalizeRun(undefined).workflow, "", "garbage")
  }

  function test_normalize_requests() {
    var raw = fullRaw()
    raw.status.control.requests = [
      { command: "pause", requested_at: "2026-10-03T10:00:00Z", handled_at: "2026-10-03T10:00:05Z" },
      { command: "resume", requested_at: "2026-10-03T11:00:00Z", handled_at: null },
      { command: "cancel", requested_at: "2026-10-03T12:00:00Z" }
    ]
    var r = Runs.normalizeRun(raw)
    compare(Array.isArray(r.requests), true)
    compare(r.requests.length, 3)
    compare(Object.keys(r.requests[0]).sort().join(","), "command,handled_at,requested_at")
    compare(r.requests[0].command, "pause")
    compare(r.requests[0].requested_at, "2026-10-03T10:00:00Z")
    compare(r.requests[0].handled_at, "2026-10-03T10:00:05Z")
    compare(r.requests[1].command, "resume", "order is kept")
    compare(r.requests[1].handled_at, "", "null means not handled")
    compare(r.requests[2].command, "cancel")
    compare(r.requests[2].handled_at, "", "missing means not handled")
    r.requests[0].command = "x"
    compare(raw.status.control.requests[0].command, "pause", "the elements are fresh objects")
    compare(Runs.normalizeRun(fullRaw()).requests.length, 0, "no requests key under control")
  }

  // Review Focus 4.
  function test_normalize_requests_garbage() {
    var raw = fullRaw()
    raw.status.control.requests = [null, "pause", 7, ["pause"], true,
                                   { command: 5, requested_at: true, handled_at: { a: 1 } }, {}]
    var r = Runs.normalizeRun(raw)
    compare(r.requests.length, 2, "non-object elements are skipped")
    compare(r.requests[0].command, "5")
    compare(r.requests[0].requested_at, "true")
    compare(r.requests[0].handled_at, "[object Object]")
    compare(r.requests[1].command, "")
    compare(r.requests[1].requested_at, "")
    compare(r.requests[1].handled_at, "")

    var noControl = fullRaw()
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).requests.length, 0, "no control")
    var values = ["x", { a: 1 }, null, 5]
    for (var i = 0; i < values.length; i++) {
      var bad = fullRaw()
      bad.status.control.requests = values[i]
      var out = Runs.normalizeRun(bad)
      compare(Array.isArray(out.requests), true, "requests " + i)
      compare(out.requests.length, 0, "requests " + i)
    }
    compare(Runs.normalizeRun({ status: { control: "y" } }).requests.length, 0, "control not an object")
  }
```

- [ ] **Step 3: Run the domain tests to verify they fail**

Run: `bash tests/run.sh tst_runs.qml`
Expected: FAIL lines for `DomainRuns::test_normalize_full`, `DomainRuns::test_normalize_garbage` (the key lists), `DomainRuns::test_normalize_workflow` and `DomainRuns::test_normalize_requests*` (`workflow`/`requests` are `undefined`).

- [ ] **Step 4: Implement in `normalizeRun`**

In `core/domain/runs.js`, replace the header comment lines 6-12 with:

```js
// Input shape for normalizeRun (provisional until the runs-snapshot helper
// exists; pinned by tests/core/domain/tst_runs.qml):
//   raw = {
//     row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
//     status: { run: {..., workflow}, rows: [...], stories: [...], subtasks: [...],
//               control: { lease: { pid, host, heartbeat_at, accepting, live },
//                          requests: [{ command, requested_at, handled_at }] }, ... }  // `am status` data, may be absent
//   }
// `workflow` is the row's, else the am status run's ("task" for a --card run).
// `requests` are am's control requests in the order made; handled_at "" means
// the run has not acted on it yet.
```

Then, after the `lease` block (after line 41, before `return {`), add:

```js
  var requests = []
  var rawRequests = arrayOr(control.requests)
  for (var i = 0; i < rawRequests.length; i++) {
    var q = rawRequests[i]
    if (!isObject(q)) continue
    requests.push({ command: text(q.command), requested_at: text(q.requested_at), handled_at: text(q.handled_at) })
  }
```

And in the returned object, add two keys after `branch_prefix: ...,`:

```js
    workflow: firstText(row.workflow, run.workflow),
```

and after `lease: lease,`:

```js
    requests: requests,
```

- [ ] **Step 5: Run the domain tests to verify they pass**

Run: `bash tests/run.sh tst_runs.qml`
Expected: `Totals: N passed, 0 failed` for `tests/core/domain/tst_runs.qml`, no `TypeError` lines.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): normalizeRun keeps the run's workflow and its am control requests (card c1f23024)"
```

---

### Task 2: `control()` for pause and cancel, one runner per request, the reply

**Files:**
- Modify: `core/stores/RunStore.qml` (header comment lines 9-13, properties after line 57, aliases after line 66, new functions before the `snapshotRunner` `HelperRunner` at line 405, new `QtObject` + `Component` at the end of the file)
- Test: `tests/core/stores/tst_run_store.qml` (one import after line 7, new tests before the final `}`)

**Interfaces:**
- Consumes: `Runs.controls(run)` → `{pause, resume, cancel}` each `{enabled, reason}`; `Runs.controlError(envelope)` → string; `Runs.runState(run)` → string; existing `store.runById(id)`, `store.parseEnvelope(text)`, `store.refresh()`; `HelperRunner` (`script`, `guard`, `busy`, `seq`, `current`, `run(args)`, `finished(stdout, exitCode, launchedGuard)`).
- Produces (later tasks rely on these exact names):
  - `property var pending` (`{runId: action}`), `property var stillWaiting` (`{runId: true}`), `readonly property string stillWaitingText`, `property string lastControlError`, `property string lastControlErrorRunId`, `readonly property alias controlRunners`.
  - `function control(action, runId)` → bool; `function dismissControlError()`.
  - Internal: `copyMap(map)`, `hasKey(map, key)`, `launchControl(runner, extra)`, `requestOf(runner)` → request or null, `settle(runId)`, `failControl(runId, sentence)`, `dropRunner(runner)`, `controlReplied(runner, stdout, exitCode)`.
  - `controlState.requests[runId]` = `{token, action, baseline, launchedMs, acknowledged, requestedAt}`; `controlState.runners`; `controlState.nextToken`.
  - Runner component `controlC`: a `HelperRunner` with `runId`, `action`, `token`, `madeFor`.

- [ ] **Step 1: Add the Runs import to the store test**

In `tests/core/stores/tst_run_store.qml`, after line 7 (`import QtTest`) add:

```qml
import "../../../core/domain/runs.js" as Runs
```

- [ ] **Step 2: Append the helpers and failing tests**

Insert before the file's last line (the `}` closing `TestCase`):

```js
  // ---- run controls (S2 4.1)

  property string ctlCmd: "python3|/plugin/core/backend/runs/run-control.py|"

  // entry() for the control tests: the run's workflow ("milestone" unless
  // given), its am control requests, and whether its lease accepts requests.
  function ctlEntry(id, runStatus, live, workflow, requests, accepting) {
    var e = entry(id, runStatus, live)
    e.workflow = workflow || "milestone"
    e.status.control.requests = requests || []
    if (accepting === false) e.status.control.lease.accepting = false
    return e
  }

  function running(id) { return ctlEntry(id, "started", true) }
  function dead(id) { return ctlEntry(id, "started", false) }

  // Project A whose first snapshot listed `entries`. Not active: no watch.
  function ctlStore(entries) {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    return store
  }

  function ctlOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  function test_control_defaults() {
    var store = make(); if (!store) return
    compare(Object.keys(store.pending).length, 0)
    compare(Object.keys(store.stillWaiting).length, 0)
    compare(store.stillWaitingText, "still waiting — the run may be between phases or dead")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.controlRunners.length, 0)
  }

  function test_pause_and_cancel_launch_the_exact_argv() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    compare(store.control("pause", "r1"), true)
    compare(store.control("cancel", "r2"), true)
    compare(store.controlRunners.length, 2)
    compare(store.controlRunners[0].runId, "r1")
    compare(store.controlRunners[0].action, "pause")
    var pause = store.controlRunners[0].current
    compare(pause.command.length, 5)
    compare(argv(pause), tc.ctlCmd + "pause|r1|/home/u/my proj")
    compare(pause.command[4], "/home/u/my proj", "the root with a space is one argument")
    compare(pause.running, true)
    compare(pause.launchGuard, "/home/u/my proj")
    var cancel = store.controlRunners[1].current
    compare(cancel.command.length, 5)
    compare(argv(cancel), tc.ctlCmd + "cancel|r2|/home/u/my proj")
  }

  function test_control_sets_pending_as_a_new_object() {
    var store = ctlStore([running("r1")]); if (!store) return
    var before = store.pending
    var spy = spyC.createObject(tc, { target: store, signalName: "pendingChanged" })
    compare(store.control("pause", "r1"), true)
    compare(spy.count, 1)
    compare(store.pending.r1, "pause")
    compare(before.r1, undefined, "the old object was not changed in place")
  }

  function test_an_ok_reply_keeps_pending_and_refreshes() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var snap = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", effective: true,
      requested_at: "t1", already_requested: false, message: "pause requested" }), 0)
    compare(store.pending.r1, "pause", "pending until a snapshot settles it")
    compare(store.lastControlError, "")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")
    verify(store.snapshotRunner.current !== snap)
    compare(store.controlRunners.length, 0)
  }

  function test_an_ok_false_reply_clears_pending_and_says_why() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    var seq = store.snapshotRunner.seq
    var text = ctlFail("NotAcceptingError", "run r1 is in integrate")
    reply(store.controlRunners[0].current, text, 0)
    compare(store.pending.r1, undefined, "the buttons come back")
    compare(store.lastControlError, Runs.controlError(JSON.parse(text)))
    compare(store.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastError, "", "the snapshot banner is not the control error")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")

    store.control("cancel", "r2")
    var failed = ctlFail("AmFailed", "am: database is locked")
    reply(store.controlRunners[0].current, failed, 0)
    compare(store.lastControlError, Runs.controlError(JSON.parse(failed)))
    verify(store.lastControlError !== "", "AmFailed says something")
    compare(store.lastControlErrorRunId, "r2")
  }

  function test_garbled_control_output_names_the_exit_code() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("cancel", "r1")
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, "Traceback (most recent call last):\nboom\n", 1)
    compare(store.pending.r1, undefined)
    compare(store.lastControlError, "The run control gave no usable result (exit 1).")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.snapshotRunner.seq, seq + 1)
  }

  function test_an_unknown_run_error_survives_the_snapshot_that_drops_the_row() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("cancel", "r1")
    reply(store.controlRunners[0].current, ctlFail("UnknownRunError", "no run r1"), 0)
    compare(store.lastControlError, "The run no longer exists")
    reply(store.snapshotRunner.current, okReply([running("r2")]), 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r2", "the row is dropped")
    compare(store.lastControlError, "The run no longer exists", "a snapshot never clears the control error")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastError, "")
    snapshot(store, [running("r2")])
    compare(store.lastControlError, "The run no longer exists")
    compare(store.lastError, "")
  }

  function test_control_refusals_launch_nothing() {
    var bare = make(); if (!bare) return
    compare(bare.control("pause", "r1"), false, "no project")
    compare(bare.controlRunners.length, 0)

    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false),
                          ctlEntry("r3", "started", true, "milestone", [], false)]); if (!store) return
    compare(store.control("stop", "r1"), false, "unknown action")
    compare(store.control("Pause", "r1"), false, "actions are exact")
    compare(store.control("", "r1"), false, "empty action")
    compare(store.control("pause", ""), false, "empty id")
    compare(store.control("pause", 7), false, "an id that is not a string")
    compare(store.control("pause", "nope"), false, "a run not in the snapshot")
    compare(store.control("pause", "r2"), false, "pause on a parked run is disabled")
    compare(store.control("cancel", "r3"), false, "cancel during Integrate is disabled")
    compare(store.control("pause", "r3"), false, "pause during Integrate is disabled")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.control("pause", "r1"), true)
    compare(store.control("pause", "r1"), false, "no double fire")
    compare(store.control("cancel", "r1"), false, "one request per run at a time")
    compare(store.controlRunners.length, 1)
    compare(Object.keys(store.pending).join(","), "r1")
  }

  function test_two_runs_in_flight_at_once_both_apply() {
    var store = ctlStore([running("a"), running("b")]); if (!store) return
    store.control("pause", "a")
    store.control("cancel", "b")
    compare(store.controlRunners.length, 2)
    var ra = store.controlRunners[0], rb = store.controlRunners[1]
    compare(ra.current.running, true, "cancelling b did not stop a's pause")
    compare(rb.current.running, true)
    reply(ra.current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.controlRunners.length, 1)
    compare(store.controlRunners[0].runId, "b")
    compare(store.pending.a, "pause")
    compare(store.pending.b, "cancel")
    reply(rb.current, ctlFail("NotRunningError", "not running"), 0)
    compare(store.controlRunners.length, 0)
    compare(store.pending.a, "pause")
    compare(store.pending.b, undefined)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "b")
  }

  function test_a_finished_request_leaves_control_runners() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.controlRunners.length, 0, "an applied reply")

    var other = ctlStore([running("r1")]); if (!other) return
    other.control("pause", "r1")
    var proc = other.controlRunners[0].current
    other.project = rootB
    compare(other.controlRunners.length, 1, "a launched request still completes in am")
    var seq = other.snapshotRunner.seq
    reply(proc, ctlOk({ requested_at: "t1" }), 0)
    compare(other.controlRunners.length, 0, "a reply dropped by the guard still removes its runner")
    compare(other.snapshotRunner.seq, seq, "a dropped reply does not re-snapshot")
  }

  function test_a_new_request_and_dismiss_clear_the_control_error() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlError, "am is busy; try again in a moment")
    compare(store.control("pause", "r1"), true, "the failed request no longer blocks the run")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlErrorRunId, "r1")
    store.dismissControlError()
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
  }
```

- [ ] **Step 3: Run the store tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL lines for every new `StoresRunStore::test_control_*`, `test_pause_*`, `test_an_ok_*`, … (`store.control is not a function`, `pending` undefined). Existing tests still pass.

- [ ] **Step 4: Add the public properties and the alias**

In `core/stores/RunStore.qml`, replace the header comment lines 9-13

```qml
// (runs-logs.py), and whether `am` could be asked at all. Two HelperRunners
// (snapshot, attempt logs) plus, while `active` (the panel is open), a
// long-lived runs-watch.py that says which runs changed; each burst of changes
// costs one debounced snapshot. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
```

with

```qml
// (runs-logs.py), and whether `am` could be asked at all. Two HelperRunners
// (snapshot, attempt logs) plus, while `active` (the panel is open), a
// long-lived runs-watch.py that says which runs changed; each burst of changes
// costs one debounced snapshot. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
// Pause, resume and cancel (control()) each get a HelperRunner of their own.
```

After line 57 (`property string logsStatus: ""      // the attempt's status when its fetch was launched`) add:

```qml

  // Run controls (S2 4.1). `pending` holds the requests not yet settled,
  // {runId: action}; `stillWaiting` the pending ones 30 s or more old,
  // {runId: true}. Both are replaced, never changed in place, so bindings see
  // every change. The control error is its own pair of fields: a snapshot never
  // touches it, and the snapshot's lastError never carries a control refusal.
  property var pending: ({})
  property var stillWaiting: ({})
  readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about
```

After line 66 (`readonly property alias logsRunner: logsRunner`) add:

```qml
  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
```

- [ ] **Step 5: Add the control functions**

In `core/stores/RunStore.qml`, immediately before the comment block that precedes the `snapshotRunner` `HelperRunner` (the line `// The guard is the project root, so a snapshot launched for a project the`), insert:

```qml
  // ---- run controls (S2 4.1)

  // A copy of a {key: value} map, so a change is a new object.
  function copyMap(map) {
    var out = {}
    for (var key in map) {
      if (Object.prototype.hasOwnProperty.call(map, key)) out[key] = map[key]
    }
    return out
  }

  function hasKey(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key)
  }

  // Starts a pause, resume or cancel of one run of this project and returns
  // whether it started. Refused: no project, an unknown action, a run that is
  // not in the snapshot, an action Runs.controls says is disabled, or a run
  // that already has a request pending. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (store.project === "") return false
    if (action !== "pause" && action !== "resume" && action !== "cancel") return false
    if (typeof runId !== "string" || runId === "") return false
    var run = store.runById(runId)
    if (run === null) return false
    if (!Runs.controls(run)[action].enabled) return false
    if (store.hasKey(store.pending, runId)) return false
    store.dismissControlError()
    controlState.nextToken += 1
    var requests = store.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = store.copyMap(store.pending)
    p[runId] = action
    store.pending = p
    var runner = controlC.createObject(store, { runId: runId, action: action,
                                                token: controlState.nextToken, madeFor: store.project })
    controlState.runners = controlState.runners.concat([runner])
    store.launchControl(runner, [])
    return true
  }

  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // then `extra` (a resume's verify arguments).
  function launchControl(runner, extra) {
    runner.script = store.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, store.project].concat(extra))
  }

  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled, emptied by a project switch
  // or replaced by a newer request.
  function requestOf(runner) {
    if (!store.hasKey(controlState.requests, runner.runId)) return null
    var req = controlState.requests[runner.runId]
    return req.token === runner.token ? req : null
  }

  // The request for runId is over: its pending entry, its still-waiting mark
  // and its bookkeeping go.
  function settle(runId) {
    if (store.hasKey(store.pending, runId)) {
      var p = store.copyMap(store.pending)
      delete p[runId]
      store.pending = p
    }
    if (store.hasKey(store.stillWaiting, runId)) {
      var w = store.copyMap(store.stillWaiting)
      delete w[runId]
      store.stillWaiting = w
    }
    if (store.hasKey(controlState.requests, runId)) {
      var r = store.copyMap(controlState.requests)
      delete r[runId]
      controlState.requests = r
    }
  }

  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run.
  function failControl(runId, sentence) {
    store.settle(runId)
    store.lastControlError = sentence
    store.lastControlErrorRunId = runId
  }

  function dismissControlError() {
    store.lastControlError = ""
    store.lastControlErrorRunId = ""
  }

  // A runner's request is over: it leaves controlRunners and is destroyed.
  function dropRunner(runner) {
    controlState.runners = controlState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // One run-control.py reply, for the project the request was made in. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence. Either way the runs are fetched again. A reply for a request that
  // is no longer the pending one changes nothing.
  function controlReplied(runner, stdout, exitCode) {
    var req = store.requestOf(runner)
    if (req === null) {
      store.dropRunner(runner)
      return
    }
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var data = envelope.data
      var requestedAt = data !== null && typeof data === "object" && typeof data.requested_at === "string" ? data.requested_at : ""
      var requests = store.copyMap(controlState.requests)
      requests[runner.runId] = { token: req.token, action: req.action, baseline: req.baseline,
                                 launchedMs: req.launchedMs, acknowledged: true, requestedAt: requestedAt }
      controlState.requests = requests
    } else if (envelope !== null && envelope.ok === false) {
      store.failControl(runner.runId, Runs.controlError(envelope))
    } else {
      store.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").")
    }
    store.dropRunner(runner)
    store.refresh()
  }

```

- [ ] **Step 6: Add the control state and the runner component**

In `core/stores/RunStore.qml`, after the `watchState` `QtObject` block (after its closing `}`, before `// One Process per watch launch, ...`), insert:

```qml
  // The control requests' own state; kept apart so consumers cannot write it.
  // `requests` is {runId: {token, action, baseline, launchedMs, acknowledged,
  // requestedAt}}: the run's state when the request started, when it started,
  // whether am acknowledged it, and the requested_at am gave it.
  QtObject {
    id: controlState
    property var runners: []
    property var requests: ({})
    property int nextToken: 0
  }

  // One HelperRunner per control request, so requests for different runs never
  // stop each other. Guarded by the project like the others: a reply for a
  // project the user has left is dropped, and its runner goes when its process
  // exits (the runner clears `busy` on that exit but emits no `finished`). No
  // onGuardChanged: the snapshot runner's already runs projectSwitched().
  Component {
    id: controlC

    HelperRunner {
      id: cr
      property string runId: ""
      property string action: ""
      property int token: 0
      property string madeFor: ""         // the project the request was made in
      guard: store.project
      onFinished: function(stdout, exitCode) { store.controlReplied(cr, stdout, exitCode) }
      onBusyChanged: if (!cr.busy && cr.guard !== cr.madeFor) store.dropRunner(cr)
    }
  }
```

- [ ] **Step 7: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: N passed, 0 failed` for `tests/core/stores/tst_run_store.qml`; no `TypeError` / `ReferenceError` / `is not a function` lines. Also run `bash tests/run.sh tst_app_runs` — expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): RunStore.control() pauses and cancels a run through its own HelperRunner and tracks pending and the control error (card c1f23024)"
```

---

### Task 3: A milestone resume reads the run settings first

**Files:**
- Modify: `core/stores/RunStore.qml` (`control()` last lines, `controlReplied()`, new `resumeWithSettings()`, the `controlC` component)
- Test: `tests/core/stores/tst_run_store.qml` (append before the final `}`)

**Interfaces:**
- Consumes: from Task 1 `run.workflow`; from Task 2 `launchControl(runner, extra)`, `failControl(runId, sentence)`, `dropRunner(runner)`, `requestOf(runner)`, `controlReplied(...)`, `store.parseEnvelope(text)`, test helpers `ctlStore`, `ctlEntry`, `dead`, `ctlCmd`, `argv`, `reply`.
- Produces: runner property `settingsStep: bool`; `function resumeWithSettings(runner, stdout, exitCode)`.

- [ ] **Step 1: Append the failing resume tests**

Insert before the final `}` of `tests/core/stores/tst_run_store.qml`:

```js
  property string settingsCmd: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/my proj"
  property string noVerifySentence: "Resume needs verify commands: none are stored for this project, and running without verification was not chosen."

  // viewer-state.py get-run-settings: one bare object, not an envelope.
  function settingsReply(verify, allow) {
    return JSON.stringify({ verify: verify, allowNoVerification: allow, notifyOnEscalation: false }) + "\n"
  }

  function test_milestone_resume_reads_the_settings_then_passes_the_verify_set() {
    var store = ctlStore([dead("r1")]); if (!store) return
    compare(store.control("resume", "r1"), true)
    compare(store.controlRunners.length, 1)
    var runner = store.controlRunners[0]
    compare(argv(runner.current), tc.settingsCmd)
    compare(runner.current.command.length, 4)
    compare(store.pending.r1, "resume")
    reply(runner.current, settingsReply(["a", "-b c"], true), 0)
    compare(store.controlRunners.length, 1, "the same request goes on to run-control")
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a|--verify|-b c")
    compare(proc.command.length, 9, "each verify command is one argument")
    compare(proc.command[8], "-b c")
    compare(proc.command.indexOf("--allow-no-verification"), -1, "a stored verify set wins over the opt-out")
    compare(store.pending.r1, "resume")
  }

  function test_milestone_resume_with_the_opt_out_passes_allow_no_verification() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    reply(store.controlRunners[0].current, settingsReply([], true), 0)
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--allow-no-verification")
    compare(proc.command.length, 6)
  }

  function test_milestone_resume_with_nothing_stored_launches_nothing() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, settingsReply([], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.lastControlError, tc.noVerifySentence)
    compare(store.lastControlErrorRunId, "r1")
    compare(store.snapshotRunner.seq, seq, "nothing was asked of am, so no snapshot")
  }

  function test_garbled_run_settings_end_the_resume() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    reply(runner.current, "oops\n", 2)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.lastControlError, "The run settings gave no usable result (exit 2).")
    compare(store.lastControlErrorRunId, "r1")
  }

  function test_a_card_run_resume_skips_the_settings() {
    var store = ctlStore([ctlEntry("r1", "started", false, "task"),
                          ctlEntry("r2", "started", false, "orchestrator")]); if (!store) return
    compare(store.control("resume", "r1"), true)
    compare(store.controlRunners.length, 1)
    var runner = store.controlRunners[0]
    compare(runner.seq, 1, "one launch only")
    compare(argv(runner.current), tc.ctlCmd + "resume|r1|/home/u/my proj")
    compare(runner.current.command.length, 5)
    compare(store.control("resume", "r2"), true)
    compare(argv(store.controlRunners[1].current), tc.settingsCmd, "any workflow but task follows the milestone rule")
  }

  // Review Focus 3.
  function test_a_verify_set_with_a_non_string_is_not_used() {
    var store = ctlStore([dead("r1"), dead("r2")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    reply(runner.current, settingsReply(["a", 5], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.lastControlError, tc.noVerifySentence)
    store.control("resume", "r2")
    reply(store.controlRunners[0].current, settingsReply(["a", 5], true), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|r2|/home/u/my proj|--allow-no-verification")
  }
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL for the six new resume tests (the first launch is run-control, not viewer-state). All earlier tests still pass.

- [ ] **Step 3: Route a milestone resume through the settings**

In `core/stores/RunStore.qml`, in `control()`, replace

```js
    controlState.runners = controlState.runners.concat([runner])
    store.launchControl(runner, [])
    return true
```

with

```js
    controlState.runners = controlState.runners.concat([runner])
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses the project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", store.project])
    } else {
      store.launchControl(runner, [])
    }
    return true
```

In `controlReplied()`, replace

```js
    var req = store.requestOf(runner)
    if (req === null) {
      store.dropRunner(runner)
      return
    }
    var envelope = store.parseEnvelope(stdout)
```

with

```js
    var req = store.requestOf(runner)
    if (req === null) {
      store.dropRunner(runner)
      return
    }
    if (runner.settingsStep) {
      runner.settingsStep = false
      store.resumeWithSettings(runner, stdout, exitCode)
      return
    }
    var envelope = store.parseEnvelope(stdout)
```

Immediately after `controlReplied()`'s closing `}`, add:

```js
  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification; with
  // neither, or no readable reply, run-control is never launched and the
  // request ends with a sentence -- no re-snapshot, nothing was asked of am.
  function resumeWithSettings(runner, stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    if (settings === null) {
      store.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").")
      store.dropRunner(runner)
      return
    }
    var verify = Array.isArray(settings.verify) ? settings.verify : []
    var usable = verify.length > 0
    for (var i = 0; i < verify.length; i++) {
      if (typeof verify[i] !== "string") usable = false
    }
    if (usable) {
      var extra = []
      for (var j = 0; j < verify.length; j++) extra.push("--verify", verify[j])
      store.launchControl(runner, extra)
    } else if (settings.allowNoVerification === true) {
      store.launchControl(runner, ["--allow-no-verification"])
    } else {
      store.failControl(runner.runId, "Resume needs verify commands: none are stored for this project, and running without verification was not chosen.")
      store.dropRunner(runner)
    }
  }
```

In the `controlC` component, after `property string madeFor: ""         // the project the request was made in` add:

```qml
      property bool settingsStep: false   // reading the run settings; run-control comes next
```

and replace the comment line above `Component {`

```qml
  // onGuardChanged: the snapshot runner's already runs projectSwitched().
```

with

```qml
  // onGuardChanged: the snapshot runner's already runs projectSwitched(). A
  // milestone resume uses its runner twice: viewer-state.py, then run-control.py.
```

- [ ] **Step 4: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: N passed, 0 failed`; no `TypeError` lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a milestone resume passes the project's stored verify set or opt-out, or refuses with a sentence (card c1f23024)"
```

---

### Task 4: Snapshots settle acknowledged requests; a project switch empties the control state

**Files:**
- Modify: `core/stores/RunStore.qml` (`projectSwitched()` lines 203-217, `applySnapshot()` ok path, new `settleAfterSnapshot()` and `isHandled()`)
- Test: `tests/core/stores/tst_run_store.qml` (append before the final `}`)

**Interfaces:**
- Consumes: from Task 1 `run.requests[i].{command, requested_at, handled_at}`; from Task 2 `controlState.requests[runId].{acknowledged, baseline, action, requestedAt}`, `settle(runId)`, `hasKey`, `dismissControlError()`; test helpers from Tasks 2-3 plus existing `snapshot(store, entries)`.
- Produces: `function settleAfterSnapshot()`, `function isHandled(run, req)` → bool.

- [ ] **Step 1: Append the failing settle and switch tests**

Insert before the final `}` of `tests/core/stores/tst_run_store.qml`:

```js
  // One am control request row.
  function amRequest(command, requestedAt, handledAt) {
    return { command: command, requested_at: requestedAt, handled_at: handledAt }
  }

  // A pause of `id` that am acknowledged; requestedAt "" leaves it out of the reply.
  function pauseAcked(store, id, requestedAt) {
    compare(store.control("pause", id), true)
    var data = { run_id: id, command: "pause" }
    if (requestedAt !== "") data.requested_at = requestedAt
    reply(store.controlRunners[store.controlRunners.length - 1].current, ctlOk(data), 0)
  }

  function test_a_pause_settles_when_its_request_is_handled() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", null)])])
    compare(store.pending.r1, "pause", "not handled yet")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [amRequest("pause", "t0", "t0h"), amRequest("pause", "t1", "")])])
    compare(store.pending.r1, "pause", "an older handled pause is another request")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [amRequest("pause", "t0", "t0h"), amRequest("pause", "t1", "t1h")])])
    compare(store.pending.r1, undefined, "handled")
  }

  function test_without_requested_at_the_last_request_of_that_command_decides() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
      [amRequest("pause", "t0", "t0h"), amRequest("cancel", "t1", "t1h"), amRequest("pause", "t2", null)])])
    compare(store.pending.r1, "pause", "the last pause is not handled; a handled cancel is another request")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
      [amRequest("pause", "t0", "t0h"), amRequest("pause", "t2", "t2h")])])
    compare(store.pending.r1, undefined)
  }

  // Review Focus 2.
  function test_a_resume_settles_when_the_run_state_changes() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    reply(store.controlRunners[0].current, settingsReply(["make test"], false), 0)
    reply(store.controlRunners[0].current, ctlOk({ action: "resume", run_id: "r1", detached: true }), 0)
    compare(store.pending.r1, "resume", "a detached resume is acknowledged, not failed")
    compare(store.lastControlError, "")
    snapshot(store, [ctlEntry("r1", "started", false, "milestone", [amRequest("resume", "t1", "t1h")])])
    compare(store.pending.r1, "resume", "still dead; resume never reads a request row")
    snapshot(store, [running("r1")])
    compare(store.pending.r1, undefined, "dead -> running")
  }

  function test_a_request_settles_when_its_run_vanishes() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    snapshot(store, [running("r2")])
    compare(store.pending.r1, undefined)
  }

  // D5.
  function test_a_snapshot_never_settles_a_request_in_flight() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var runner = store.controlRunners[0]
    snapshot(store, [ctlEntry("r1", "stopped", false)])
    compare(store.pending.r1, "pause", "the reply has not come back yet")
    snapshot(store, [])
    compare(store.pending.r1, "pause", "not even when the run vanished")
    reply(runner.current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.pending.r1, "pause")
    snapshot(store, [ctlEntry("r1", "stopped", false)])
    compare(store.pending.r1, undefined, "settled once acknowledged")
  }

  function test_a_failed_snapshot_settles_nothing() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "AmFailed", message: "boom" } }) + "\n", 0)
    compare(store.pending.r1, "pause")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    compare(store.pending.r1, "pause")
  }

  function test_a_project_switch_empties_the_control_state_and_drops_the_old_reply() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    store.control("cancel", "r2")
    var proc = store.controlRunners[0].current
    reply(store.controlRunners[1].current, ctlFail("NotRunningError", "x"), 0)
    compare(store.lastControlErrorRunId, "r2")
    store.stillWaiting = { r1: true }
    store.project = rootB
    compare(Object.keys(store.pending).length, 0)
    compare(Object.keys(store.stillWaiting).length, 0)
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.controlRunners.length, 1, "the launched request is not stopped")
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotAcceptingError", "x"), 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.lastControlError, "", "the old reply changes nothing")
    compare(store.snapshotRunner.seq, seq, "no extra snapshot for B")
    compare(store.controlRunners.length, 0)
  }

  // Review Focus 1: A -> B -> A before the old reply lands.
  function test_an_old_reply_after_returning_to_the_project_changes_nothing() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var oldProc = store.controlRunners[0].current
    store.project = rootB
    store.project = rootA
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(store.control("pause", "r1"), true, "pending was emptied, so the run can be asked again")
    compare(store.controlRunners.length, 2)
    var seq = store.snapshotRunner.seq
    reply(oldProc, ctlFail("NotAcceptingError", "x"), 0)
    compare(store.pending.r1, "pause", "the old reply does not settle the new request")
    compare(store.lastControlError, "")
    compare(store.snapshotRunner.seq, seq, "and does not re-snapshot")
    compare(store.controlRunners.length, 1)
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t2" }), 0)
    compare(store.pending.r1, "pause")
    compare(store.controlRunners.length, 0)
  }
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL for `test_a_pause_settles_*`, `test_without_requested_at_*`, `test_a_resume_settles_*`, `test_a_request_settles_*`, `test_a_snapshot_never_settles_*` (last compare), `test_a_project_switch_empties_*` and `test_an_old_reply_after_returning_*` (pending not emptied, so the second `control` returns false). `test_a_failed_snapshot_settles_nothing` may already pass.

- [ ] **Step 3: Settle after a good snapshot**

In `core/stores/RunStore.qml` `applySnapshot()`, replace

```js
      store.runs = out
      store.logsAfterSnapshot()
```

with

```js
      store.runs = out
      store.settleAfterSnapshot()
      store.logsAfterSnapshot()
```

After `resumeWithSettings()`'s closing `}` (in the run controls section), add:

```js
  // After every good snapshot: an acknowledged request is settled when its run
  // is gone, when the run's state moved since the request started, or (pause,
  // cancel) when am marks its request handled. A request still in flight is
  // never settled by a snapshot: its buttons stay off until the reply.
  function settleAfterSnapshot() {
    var ids = Object.keys(store.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (!store.hasKey(controlState.requests, id)) continue
      var req = controlState.requests[id]
      if (!req.acknowledged) continue
      var run = store.runById(id)
      if (run === null || Runs.runState(run) !== req.baseline
          || (req.action !== "resume" && store.isHandled(run, req))) store.settle(id)
    }
  }

  // The run's am request row for this request has a handled_at: the row with
  // the requested_at am's reply gave, else the last row of the same command.
  function isHandled(run, req) {
    var list = Array.isArray(run.requests) ? run.requests : []
    var match = null
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (req.requestedAt !== "" ? row.requested_at === req.requestedAt : row.command === req.action) match = row
    }
    return match !== null && match.handled_at !== ""
  }
```

- [ ] **Step 4: Empty the control state on a project switch**

In `projectSwitched()`, replace

```js
    store.lastError = ""
    store.amStatus = "ok"
    if (store.project !== "") store.refresh()
```

with

```js
    store.lastError = ""
    store.amStatus = "ok"
    // Control requests already launched still complete in am; their replies
    // are dropped by their runners' guard. Nothing of the old project's stays.
    store.pending = {}
    store.stillWaiting = {}
    controlState.requests = {}
    store.dismissControlError()
    if (store.project !== "") store.refresh()
```

- [ ] **Step 5: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: N passed, 0 failed`; no `TypeError` lines.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): a snapshot settles an acknowledged control request, and a project switch empties the control state (card c1f23024)"
```

---

### Task 5: Still waiting after 30 s, the pending timer, the architecture doc

**Files:**
- Modify: `core/stores/RunStore.qml` (alias after the `controlRunners` alias, new `checkWaiting()`, new `Timer` after `pollTimer`)
- Modify: `docs/architecture.md` (after line 94, the `logsRunner` paragraph)
- Test: `tests/core/stores/tst_run_store.qml` (append before the final `}`)

**Interfaces:**
- Consumes: from Task 2 `pending`, `stillWaiting`, `stillWaitingText`, `controlState.requests[runId].launchedMs`, `hasKey`; from Task 4 settling; test helpers `ctlStore`, `running`, `ctlEntry`, `amRequest`, `ctlOk`, `ctlFail`, `activeStore`, `snapshot`.
- Produces: `readonly property alias pendingTimer` (`objectName: "pendingTimer"`), `function checkWaiting(nowMs)`.

- [ ] **Step 1: Append the failing tests**

Insert before the final `}` of `tests/core/stores/tst_run_store.qml`:

```js
  function test_a_request_is_still_waiting_after_30_seconds() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    store.checkWaiting(Date.now() + 29000)
    compare(store.stillWaiting.r1, undefined, "29 s is not yet")
    store.checkWaiting(Date.now() + 30000)
    compare(store.stillWaiting.r1, true)
    compare(store.stillWaiting.r2, undefined, "only pending runs")
    compare(store.stillWaitingText, "still waiting — the run may be between phases or dead")
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.stillWaiting.r1, true, "acknowledged but not settled: still waiting")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", "t1h")]), running("r2")])
    compare(store.stillWaiting.r1, undefined, "settling removes it")
    compare(Object.keys(store.stillWaiting).length, 0)
  }

  // Review Focus 5 and D6.
  function test_the_pending_timer_runs_only_while_active_with_something_pending() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(store.pendingTimer.running, false, "nothing pending")
    compare(store.pendingTimer.interval, 1000)
    compare(store.pendingTimer.repeat, true)
    store.control("pause", "r1")
    compare(store.pendingTimer.running, true)
    store.pendingTimer.triggered()
    compare(store.stillWaiting.r1, undefined, "a fresh request is not waiting yet")
    store.active = false
    compare(store.pendingTimer.running, false, "no timer while the panel is closed")
    compare(store.pending.r1, "pause", "closing the panel keeps pending")
    compare(store.controlRunners.length, 1, "and the request in flight")
    store.active = true
    compare(store.pendingTimer.running, true, "reopening starts it again")
    reply(store.controlRunners[0].current, ctlFail("NotRunningError", "x"), 0)
    compare(store.pendingTimer.running, false, "nothing pending any more")

    var idle = ctlStore([running("r1")]); if (!idle) return
    idle.control("pause", "r1")
    compare(idle.pendingTimer.running, false, "an inactive store runs no timer")
  }
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL for the two new tests (`store.checkWaiting is not a function`, `pendingTimer` undefined).

- [ ] **Step 3: Implement `checkWaiting` and the timer**

In `core/stores/RunStore.qml`, after the line `readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first` add:

```qml
  readonly property alias pendingTimer: pendingTimer
```

After `isHandled()`'s closing `}` add:

```js
  // Marks the pending requests launched 30 s or more before nowMs (the timer
  // passes Date.now()); the UI shows stillWaitingText for them.
  function checkWaiting(nowMs) {
    var out = {}
    var ids = Object.keys(store.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (store.hasKey(controlState.requests, id) && nowMs - controlState.requests[id].launchedMs >= 30000) out[id] = true
    }
    store.stillWaiting = out
  }
```

After the `pollTimer` `Timer` block (after its closing `}`), add:

```qml
  // Only while the panel is open and a control request is pending: closing the
  // panel keeps `pending` but leaves no timer running.
  Timer {
    id: pendingTimer
    objectName: "pendingTimer"
    interval: 1000
    repeat: true
    running: store.active && Object.keys(store.pending).length > 0
    onTriggered: store.checkWaiting(Date.now())
  }
```

- [ ] **Step 4: Run the store tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: N passed, 0 failed`; no `TypeError` lines.

- [ ] **Step 5: Document the control state**

In `docs/architecture.md`, after line 94 (the paragraph starting `  Run detail's output pane is a second \`HelperRunner\`, \`logsRunner\``), insert this line (two leading spaces, like its neighbours):

```markdown
  Run controls (S2 4.1): `control(action, runId)` starts a `pause`, `resume` or `cancel` of a run in `runs` and returns whether it did; it refuses without a project, for an action `Runs.controls(run)` disables, and for a run that already has a request in `pending`. Confirming a cancel is the caller's job. Each request gets its own `HelperRunner` (`controlRunners`, guarded by the project), so requests for different runs never stop each other and a reply for a project the user has left is dropped. Pause, cancel and a `--card` run's resume (`workflow` `task`) run `run-control.py ACTION RUN REPO`; any other resume first reads `viewer-state.py get-run-settings` and passes the stored verify set as `--verify` pairs, else `--allow-no-verification` when that was chosen, else refuses with a sentence. `pending` (`{runId: action}`) holds from the launch until a snapshot after am's `ok: true` reply shows the run gone, its state changed, or (pause, cancel) its am request handled; no snapshot settles a request still in flight. A failed request clears its entry and sets `lastControlError` (the `Runs.controlError` sentence) and `lastControlErrorRunId`, which no snapshot touches -- `lastError` stays the snapshot banner -- and which `dismissControlError()` or the next request clears. Every control reply re-snapshots. `stillWaiting` marks requests pending for 30 s or more (`pendingTimer`, 1 s, only while the panel is open), and `stillWaitingText` is the line the UI shows for them. Closing the panel keeps `pending`; a project switch empties it and the control error.
```

- [ ] **Step 6: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture/test_layers.py`), every `tst_*.qml` prints `Totals: N passed, 0 failed`, no `TypeError` / `ReferenceError` / `non-existent` / `Unable to assign` / `is not a function` lines, and the script exits 0.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml docs/architecture.md
git commit -m "feat(runs): RunStore marks a control request still waiting after 30 s while the panel is open (card c1f23024)"
```

---

## Self-Review

**Spec coverage.**
- Public surface table: `control` (T2), `pending` (T2), `stillWaiting` / `stillWaitingText` (T2 defaults, T5 behaviour), `lastControlError` / `lastControlErrorRunId` / `dismissControlError` (T2), `controlRunners` (T2), `pendingTimer` / `checkWaiting` (T5).
- `control()` guard order 1-5 → T2 `test_control_refusals_launch_nothing`; clearing the error, pending, baseline, launch time → T2.
- Pause/cancel argv → T2 test 4. Resume card vs milestone, verify pairs, opt-out, refusal, garbled settings → T3 tests 5-9.
- Control reply ok / ok:false / garbled, re-snapshot, token, runner removal on applied and dropped replies → T2 tests 10-14, 22, 23, 27; token → T4 RF1.
- Settling rules 1-3, resume rows ignored, stillWaiting removal, failed snapshots → T4 tests 15-20, T5 test 24.
- Still waiting and timer, D6 → T5 tests 24-25.
- Project switch → T4 test 26 and RF1. D1 (snapshot `lastError` untouched) → T2 tests 12 and 14.
- Domain `workflow` / `requests` and the header comment → T1. `docs/architecture.md` paragraph → T5.
- Architecture tier: imports unchanged; no new Python → Global Constraints and T5 step 6.

**Placeholder scan.** Every code step has full code; no "TBD", "similar to", or undefined helpers. Test helpers (`ctlEntry`, `running`, `dead`, `ctlStore`, `ctlOk`, `ctlFail`, `settingsReply`, `amRequest`, `pauseAcked`) are each defined in the task that first uses them; `entry`, `okReply`, `reply`, `argv`, `snapshot`, `activeStore`, `spyC`, `make`, `makeWithProject`, `rootA`, `rootB` already exist in the file.

**Type consistency.** `controlState.requests[runId]` is `{token, action, baseline, launchedMs, acknowledged, requestedAt}` everywhere (T2 create, T2 ack rewrite, T4 settle read, T5 `launchedMs`). Runner properties `runId`, `action`, `token`, `madeFor` (T2) and `settingsStep` (T3) match their uses. `requestOf`, `settle`, `failControl`, `dropRunner`, `launchControl`, `resumeWithSettings`, `settleAfterSnapshot`, `isHandled`, `checkWaiting` names are the same in every task.

**Review Focus.** Five lines above, each with its test in the owning task (T4, T4, T3, T1, T5).
<!-- task-pipeline: validated -->
