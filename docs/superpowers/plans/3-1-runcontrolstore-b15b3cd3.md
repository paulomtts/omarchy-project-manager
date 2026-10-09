# 3.1 RunControlStore: control requests, cancel dialog and flash — design

Card: `b15b3cd3` (subtask of story `1159cc4e` "Extract RunControlStore"; sibling 3.2 `e546c85f`
"RunControlStore: run and global settings"). Parent design:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N". Line
numbers into `core/stores/RunStore.qml` and the test files are from the files at the start of
this card (commit `84260c6`, RunStore.qml 1917 lines). Appendix A's line numbers (P l.168) are
from an older 2038-line file and are not used here.

## Purpose

This is a pure refactor. The run controls, the cancel confirmation and the footer flash leave
`RunStore` for a new store, `core/stores/RunControlStore.qml`, which App composes as
`app.runControl` (P l.55). The new store never names `RunStore`. It reads the runs through an
input App binds. It asks for a re-snapshot with a signal, `refreshRequested(roots)`, which App
routes. App's existing `snapshotReplied` handler settles the pending requests
(`settleAfterSnapshot()`) on an `ok` outcome, before the alerts call (P l.77, l.85-91).
`RunStore` keeps stateless shims under the old names (P l.122-127), so `ui/` and `tests/ui/`
do not change.

Nothing a user can see or a helper can receive changes. The same argv launches at the same
moments, the same sentences appear, the same requests settle on the same snapshots, and a
control reply re-snapshots the same roots.

## Card assumptions that do not hold at this commit

- **No resume dialog and no `lastControlErrorType` exist.** The card asks to move "Resume and
  recover's whole `// ---- resume dialog` section (`resume*` state, `resumeOpenFor` /
  `resumeClose` / `resumeConfirm`, `resumeSaveRunner`)" and "the control error pair with
  `lastControlErrorType`". A search of `core/` and `ui/` finds none of them. Appendix A.2 says
  the same: "not in `RunStore.qml` at this commit" (P l.415-416). Nothing is moved for them,
  and nothing is invented: this is a pure refactor with no new state (P l.146). The resume
  verify read does exist, and it moves whole: `control()`'s settings step plus
  `resumeWithSettings`, on the request's own runner.
- **The settings members are 3.2's, not 3.1's.** Appendix A maps `notifyOnEscalation`,
  `notifySaved`, `notifyTouched`, `runSettings`, `setNotifyOnEscalation`,
  `applyGlobalSettings`, `applyRunSettings`, `notifySaveReplied`, `settingsLoadRunner`,
  `runSettingsRunner` and `settingsSaveRunner` to `RunControlStore` (P l.231-234, 357-360,
  383-385). Sibling card 3.2 ("run and global settings") owns that move, along with
  `startLive`'s two settings lines, `projectSwitched`'s run-settings reset and the rebinding of
  `runAlerts.notifyOnEscalation`. This card leaves all of them in `RunStore`, byte-unchanged.
- **No `RunDispatchStore` exists yet.** The dispatch code is still in `RunStore.qml`. Its one
  call into this card's members, `dispatchSaveReplied`'s
  `store.flash("Dispatch settings could not be saved")` (RunStore.qml 1673), stays as written
  and goes through the `flash` shim. The same is true of 3.2's `notifySaveReplied`
  `store.flash(...)` (1345). The App routes for those calls (`noticeRequested`, P l.79, l.445)
  belong to the dispatch story and to 3.2.

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped
  unless no code or test reads it (P l.61-67).
- No duplicated helpers. Shared logic comes from `core/domain/`, and a store keeps no private
  copy (P l.68-71). This forces one domain addition: `Runs.runRoot`. See "Domain" below.
- Inputs come from App. `RunControlStore` gets `backendDir`, `project`, `active` and `runs`
  (`app.runs.runs`). It takes `settleAfterSnapshot()` in and sends `refreshRequested(roots)`
  out (P l.77).
- App handles `snapshotReplied` in ONE handler, in today's order:
  `runControl.settleAfterSnapshot()` on `ok`, then `runAlerts.snapshotReplied(…)`. This
  replaces the direct call in `applyProjects` (P l.85-88, A.3 P l.427). A control reply's
  `refresh()` becomes `refreshRequested(roots)`, and today the roots are every usable root
  (P l.89, A.3 P l.439).
- `control`, `refusalOf` and `settleAfterSnapshot` read the run lookup through the `runs`
  input. The lookup is the domain function (A.3 P l.440-441).
- Lifecycle stays per store. `pendingTimer` keeps its `running:` condition, bound to the new
  store's own `active` (P l.92-97). This card's members need no `active` or `project`
  reaction. `startLive` and `projectSwitched` touch only 3.2's members, and a project switch
  keeps the requests, the dialog, the flash and the control error (RunStore.qml 655-660).
- A store never imports or names a sibling. The one exception is the shim handle (P l.46-50).
- Shims: a property is a binding through a handle (`property var controlStore: null`, set by
  App). A function is a one-line forward that returns the target's result. A shim property
  notifies like the original, because `ui/Panel.qml:101` handles `onCancelOpenChanged`. Shims
  hold no state and no logic. The comment above them says only "Moved to RunControlStore;
  removed by the last story" (P l.122-127). There is one forced exception, for the two members
  that `ui/` or `tests/ui/` write. See "Writable shims".
- Tests move with their members. Only construction and the wiring of inputs change, never an
  expectation. A test that crosses two concerns is pinned at App level (P l.98-104,
  l.160-162).
- `tests/architecture` stays green (P l.105-106).
- No behaviour change, no renamed public member, no new helper argv, no change to which
  process starts when, and no UI change (P l.146-150).
- From the card:
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative;
  - `tests/ui` passes untouched.

## The members that move

Every row below leaves `RunStore.qml` and lands in `RunControlStore.qml` with an unchanged body.
The only edits are `store.` → the new root id (`control`), and the two lookups:
`store.runById(x)` → `Runs.runById(control.runs, x)` and `store.runRoot(r)` → `Runs.runRoot(r)`.
`store.refresh()` in `controlReplied` becomes `control.refreshRequested("all")`.

| member | RunStore.qml today | Appendix A row |
|---|---|---|
| run-controls comment block | 121-125 | rewritten as part of the store's contract comment |
| `pending` | 126 | P l.217 |
| `stillWaiting` | 127 | P l.218 |
| `stillWaitingText` (readonly) | 128 | P l.219 |
| `lastControlError` | 129 | P l.220 |
| `lastControlErrorRunId` | 130 | P l.221 |
| cancel/flash comment block | 132-134, 139 | into the contract comment |
| `cancelRunId` | 135 | P l.222 |
| `cancelOpen` (readonly, `cancelRunId !== ""`) | 136 | P l.223 |
| `cancelText` | 137 | P l.224 |
| `cancelError` | 138 | P l.225 |
| `flashText` | 140 | P l.226 |
| `controlRunners` alias (`controlState.runners`) | 216 | P l.262 |
| `pendingTimer` alias | 217 | P l.263 |
| `flashTimer` alias | 218 | P l.264 |
| `control` | 1057-1081 | P l.334 |
| `launchControl` | 1086-1089 | P l.335 |
| `requestOf` | 1094-1098 | P l.336 |
| `settle` | 1102-1118 | P l.337 |
| `failControl` | 1122-1126 | P l.338 |
| `dismissControlError` | 1128-1131 | P l.339 |
| `dropRunner` | 1134-1137 | P l.340 |
| `controlReplied` | 1144-1170 | P l.341 |
| `resumeWithSettings` | 1177-1199 | P l.342 |
| `settleAfterSnapshot` | 1205-1216 | P l.343 |
| `isHandled` | 1220-1228 | P l.344 |
| `checkWaiting` | 1232-1240 | P l.345 |
| `refusalOf` | 1248-1256 | P l.346 |
| `flash` | 1260-1264 | P l.347 |
| `openCancel` | 1268-1278 | P l.348 |
| `closeCancel` | 1280-1284 | P l.349 |
| `confirmCancel` | 1289-1303 | P l.350 |
| `pendingTimer` Timer | 1789-1797 | P l.392; `running: control.active && Object.keys(control.pending).length > 0` |
| `flashTimer` Timer | 1800-1806 | P l.393 |
| `controlState` QtObject | 1836-1844 | P l.398 |
| `controlC` Component | 1883-1899 | P l.402; `onFinished` calls `control.controlReplied(cr, …)` |

The only change inside `RunStore`'s own code is one line removed from `applyProjects`:
`store.settleAfterSnapshot()` (1009). The `projectSwitched` doc comment (655-660) drops the
clause listing the control members it keeps, because they are no longer its members. The
file's header comment drops "Pause, resume and cancel (control()) each get a HelperRunner of
their own." (32). `runById` stays a `RunStore` member (P l.315), unchanged. `runRoot` stays a
`RunStore` member (P l.316), and its body becomes `return Runs.runRoot(run)`.

## Domain: `Runs.runRoot(run)`

`runRoot` is read by `RunStore`'s logs (`fetchLogs`, 799-800) and by the moved `control` and
`refusalOf`. Two private copies would break P l.68-71, so it moves to `core/domain/runs.js`
beside `runById`. The behaviour is identical to today's body (RunStore.qml 762-766):

- `run.project.root` when `run` is a non-null object whose `project` is a non-null object whose
  `root` is a string (that string is returned as it is, so `""` stays `""`);
- `""` otherwise: `null`, `undefined`, a non-object, no `project`, a `project` that is not an
  object, or a `root` that is not a string.

The comment says only this contract.

## Behaviour: `RunControlStore`

### Inputs (bound by App)

| property | type | App binds | default |
|---|---|---|---|
| `backendDir` | string | `app.backendDir` | `""` |
| `project` | string | `app.runs.project` (the open project's root path) | `""` |
| `active` | bool | `app.panelOpen` | `false` |
| `runs` | var | `app.runs.runs` | `[]` |

`project` is bound now because the card and P l.77 name it, and 3.2's run-settings read uses
it. In 3.1 a change of `project` changes nothing in this store.

### Signal out

`signal refreshRequested(var roots)`: a re-snapshot is wanted. `roots` is `"all"` (every usable
root, the `RunStore.requestSnapshot` vocabulary) or `[root, ...]`. In 3.1 the store emits only
`"all"`, exactly once at the end of every `controlReplied` call that applied a reply. That
covers ok, `ok: false` and garbled replies, in the position of today's `store.refresh()`, after
`dropRunner`. It is not emitted for a stale reply (`requestOf` null), for a settings-step reply
that goes on to run-control, or for a settings-step failure.

### Unchanged from RunStore

Everything below behaves exactly as `RunStore` does today. The contract text is today's
`docs/architecture.md` run-controls paragraph (line 91, up to "a project switch keeps the dialog
and the flash"), restated for the new store:

- `control(action, runId)`: `refusalOf` first. On success it clears the control error, records
  the request in `controlState`, adds `pending[runId]` (a new object), creates a `controlC`
  runner with `repoDir: run.repo_dir` and `projectRoot: Runs.runRoot(run)`, and returns true. A
  resume of a run whose `workflow` is not `task` first runs
  `projects/viewer-state.py get-run-settings <projectRoot>` on that same runner
  (`settingsStep`). Every other control runs `runs/run-control.py ACTION RUN REPO`.
- `resumeWithSettings`: a non-empty all-string verify set becomes `--verify` pairs. Otherwise
  `allowNoVerification === true` becomes `--allow-no-verification`. Otherwise the request fails
  with the no-verify sentence and nothing is launched. An unreadable reply fails with "The run
  settings gave no usable result (exit N).".
- `controlReplied`: an `ok: true` reply marks the request acknowledged with its
  `requested_at`. `ok: false` fails it with `Runs.controlError`. Anything else fails it with
  "The run control gave no usable result (exit N).". The runner is dropped, then
  `refreshRequested("all")` is emitted.
- `settleAfterSnapshot()`: for each pending, acknowledged request it reads
  `Runs.runById(control.runs, id)`. The request settles when the run is gone, when its state
  differs from the baseline, or (pause, cancel) when `isHandled` is true. It never settles a
  request that is in flight or not acknowledged. A second call with the same `runs` changes
  nothing more.
- `checkWaiting(nowMs)`, `stillWaitingText`, `pendingTimer` (1000 ms, repeat, only while
  `active` and something is pending, objectName `pendingTimer`).
- `refusalOf(action, runId)`, with the same sentences in the same order.
- `flash(text)`, and `flashTimer` (3000 ms, no repeat, objectName `flashTimer`, clears
  `flashText`).
- `openCancel`, `closeCancel` and `confirmCancel`.
- Replies are applied whatever project is open, and no control runner has a guard.

## Behaviour: `RunStore`

### Removed

All the members in the table above, plus the `store.settleAfterSnapshot()` call in
`applyProjects`. `RunStore` no longer settles requests itself. A snapshot settles them only
through App's route, or through the test harness's route that mirrors it.

### Shims

They sit under one comment, `// Moved to RunControlStore; removed by the last story`, next to
the alerts shims:

| name | shim | without a handle |
|---|---|---|
| `controlStore` | `property var controlStore: null` (the handle App sets) | — |
| `pending` | `readonly property var` through the handle | `({})` |
| `stillWaiting` | `readonly property var` | `({})` |
| `stillWaitingText` | `readonly property string` | `""` |
| `lastControlError` | `readonly property string` | `""` |
| `lastControlErrorRunId` | `readonly property string` | `""` |
| `cancelRunId` | **writable** `property string`, see below | `""` |
| `cancelOpen` | `readonly property bool` | `false` |
| `cancelText` | **writable** `property string`, see below | `""` |
| `cancelError` | `readonly property string` | `""` |
| `flashText` | `readonly property string` | `""` |
| `controlRunners` | `readonly property var` | `[]` |
| `pendingTimer` | `readonly property var` (the Timer) | `null` |
| `flashTimer` | `readonly property var` (the Timer) | `null` |
| `control(a, id)`, `refusalOf(a, id)`, `flash(t)`, `openCancel(id)`, `closeCancel()`, `confirmCancel()` | one-line forward returning the target's result | returns `undefined`, does nothing |

Every shim checks `store.controlStore` first. `tests/run.sh` fails a file whose output contains
`TypeError`, so a shim with no handle must not throw. Each property shim is a binding, so its
`…Changed` signal fires whenever the control store's value changes. That includes
`cancelOpenChanged`, which `ui/Panel.qml:101` handles.

The moved members that get **no shim** are the ones no code or test outside `RunStore.qml` and
the moved tests reaches: `launchControl`, `requestOf`, `settle`, `failControl`,
`dismissControlError`, `dropRunner`, `controlReplied`, `resumeWithSettings`,
`settleAfterSnapshot`, `isHandled` and `checkWaiting`. Before deleting, the planner greps
`ui/`, `tests/ui/`, `tst_app_runs.qml`, `tst_run_alerts_store.qml` and the tests that stay in
`tst_run_store.qml`. Any hit gets a forward shim instead.

### Writable shims (`cancelText`, `cancelRunId`)

Two callers outside the stores write these members, and they must keep working with `ui/` and
`tests/ui/` untouched:

- `ui/Panel.qml:840`, `onTypedEdited: function(text) { appStores.runs.cancelText = text }` (in
  production: every keystroke in the cancel dialog);
- `tests/ui/tst_shortcuts.qml:777`, `s.app.runs.cancelRunId = "run-0000000000a1"`.

Assigning a read-only property prints a `TypeError` and fails the gate. These two shims are
therefore plain properties with the read binding, and they carry a change handler:

1. Let `target` be the handle's value, or `""` with no handle. If the shim's value equals
   `target`, do nothing. This is the case for every change that comes through the binding.
2. Otherwise the change came from a write. With a handle, write the value to the handle's
   member.
3. Restore the read binding (`Qt.binding`).

After step 3 the shim reads the handle again and holds no value of its own. A write with no
handle snaps back to `""` and does not throw. A later change on the control store, such as
`closeCancel()`, reaches the shim. Step 1 makes the handler re-entrant-safe: restoring the
binding gives a value equal to `target`, so the handler stops. This departs from P l.122-123
("a property is a read-only binding"). The departure is forced by "`ui/` is not touched until
the last story" (P l.115) and by the card's "tests/ui pass untouched". The last story removes
it with the other shims, once `Panel.qml` writes `app.runControl.cancelText`.

## Behaviour: `App`

```qml
// The run controls never import the run store: App hands them the backend
// directory, the open project's root, the panel-open flag and the run list,
// settles their requests on each ok snapshot reply and routes their
// refreshRequested to the run store.
readonly property RunControlStore runControl: RunControlStore {
  backendDir: app.backendDir
  project: app.runs.project
  active: app.panelOpen
  runs: app.runs.runs
  onRefreshRequested: function(roots) {
    if (roots === "all") app.runs.refresh()
    else app.runs.requestSnapshot(roots)
  }
}
```

`"all"` goes to `refresh()`, not `requestSnapshot("all")`. That is the exact call
`controlReplied` makes today, including `refresh()`'s empty-registry branch (drop the snapshot
and empty the lists).

`app.runs` gains `controlStore: app.runControl`, and its existing handler becomes:

```qml
onSnapshotReplied: function(root, outcome, previousRuns, runs) {
  if (outcome === "ok") app.runControl.settleAfterSnapshot()
  app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs)
}
```

The comment above `app.runs` adds the control store to the list of what its shims read.
`runAlerts.notifyOnEscalation` stays bound to `app.runs.notifyOnEscalation`, because 3.2
rebinds it.

## Equivalence argument (for the reviewer)

- **Settle inputs.** Today `settleAfterSnapshot()` runs once per reply with any ok entry, after
  `store.runs = merged.runs`. Now it runs on each `ok` emission. Every emission follows the
  whole reply's state, including `runs` (P l.81-82; `emitReplied` is the last statement on the
  ok path, RunStore.qml 1028). The `runs` input is a binding, so it is already the merged list
  when the first emission fires. The input to the first settle is therefore today's input.
- **Repeat calls.** A reply with several ok roots now settles once per ok root. The first call
  settles exactly what today's single call settles. Later calls see the same `runs`. Settled
  ids are gone from `pending`, and the remaining ids failed the same test against the same
  data. So they change nothing, and `pending` keeps its identity: `settle` only replaces a map
  when it deletes a key.
- **Which outcomes settle.** Today settle runs only on the `anyOk` path. Now it runs only on
  `ok` emissions, which exist only on the `anyOk` path. The all-failed path, AmMissing, a
  reply with no matched entry and garbage settle nothing, then and now.
- **Order inside the reply.** Today settle runs before `logsAfterSnapshot`, the
  `amStatus`/`lastError` update, `stale`, the stale clock and the watch start. Now it runs
  after them. None of those steps reads `pending`, `stillWaiting` or `controlState`, and
  `settle` writes nothing they read. Within the handler, settle still comes before
  `runAlerts.snapshotReplied`, which reads none of the control state (P l.85).
- **Re-snapshot.** `refreshRequested("all")` is emitted synchronously where `store.refresh()`
  was called, and App routes it to that same `refresh()`.
- **The flash from RunStore's remaining code.** `dispatchSaveReplied` and `notifySaveReplied`
  call `store.flash(...)`, which is now the shim and lands on the control store's `flashText`
  and `flashTimer`. The App and the `tst_run_store` harness both set the handle.

## Tests

TDD: each new test is written first and fails before its code exists. Everything runs through
`bash tests/run.sh` (qmltestrunner, offscreen, stubs from `tests/stubs`). A single file runs
with `bash tests/run.sh tst_run_control_store`. There are five tiers:

- **domain unit**: `tests/core/domain/tst_runs.qml`. Pure function, no store.
- **store unit**: `tests/core/stores/tst_run_control_store.qml`, a new file, TestCase name
  `StoresRunControlStore`. It pins the moved behaviour against a real reply flow and the new
  store built alone.
- **RunStore unit**: `tests/core/stores/tst_run_store.qml`. It pins the shims and the removed
  coupling.
- **App wiring**: `tests/core/stores/tst_app_runs.qml`. It pins the cross-concern routes.
- **UI and architecture**: `tests/ui/**` (untouched) and `pytest tests` (architecture,
  contract, install).

### Harness shared by `tst_run_store.qml` and `tst_run_control_store.qml`

`wireControl(store)` creates a `RunControlStore`
(`Qt.createComponent("../../../core/stores/RunControlStore.qml")`, parent `tc`) and wires it
the way App does:

- `backendDir` copied;
- `project`, `active` and `runs` as `Qt.binding`s to the RunStore's own;
- `store.controlStore = c`;
- `store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok")
  c.settleAfterSnapshot() })`;
- `c.refreshRequested.connect(function(roots) { if (roots === "all") store.refresh(); else
  store.requestSnapshot(roots) })`.

The harness records the pair in `controlPairs`, and `controlOf(store)` returns the paired
control store. `make()` calls `wireControl(store)` **before** `wireAlerts(store)`, so the two
`snapshotReplied` connections run in App's order: settle, then alerts. `tst_run_store.qml`'s
`make()` gains that call. Every test that stays there is otherwise unchanged and reads the
control members through the shims.

`tst_run_alerts_store.qml` is not changed. Its RunStores have no control handle, so their
`flashText` shim reads `""`. Its one read of that member (874) expects `""`, so the test still
passes.

### Moved tests (store unit tier: they move whole, with every expectation kept)

These leave `tst_run_store.qml` and land in `tst_run_control_store.qml` under the same names.
In the moved bodies, only one thing changes: each read, write or call of a moved member
(`pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`,
`cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `flashText`, `controlRunners`,
`pendingTimer`, `flashTimer`, `control`, `refusalOf`, `flash`, `openCancel`, `closeCancel`,
`confirmCancel`, `dismissControlError`, `checkWaiting`) goes to `controlOf(store)` instead of
`store`. That includes the helper `pauseAcked`. RunStore members (`snapshotRunner`, `refresh`,
`runs`, `runById`, `project`, `active`, `lastError`) stay on `store`. Snapshots and control
replies are still driven through stubbed processes, because the behaviour under test is a real
reply settling a real request.

- The whole `// ---- run controls (S2 4.1)` block (2729-3164), 26 tests, from
  `test_control_defaults` to
  `test_the_pending_timer_runs_only_while_active_with_something_pending`.
- The whole `// ---- cancel confirmation and the footer flash (S2 4.3)` block (3166-3293), 5
  tests: `test_refusal_of_says_why_a_control_would_not_start`,
  `test_a_flash_clears_itself_and_a_new_one_restarts_the_clock`,
  `test_open_cancel_opens_only_for_a_cancellable_run`,
  `test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes` and
  `test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm`.
- The control tests of `// ---- control and logs for a run of any project (3.5)`
  (5061-5244), 11 tests:
  - `test_pause_and_cancel_pass_the_runs_repo_dir_with_or_without_a_project`
  - `test_a_task_runs_resume_passes_its_repo_dir_with_no_settings_step`
  - `test_a_milestone_resume_reads_its_own_projects_settings`
  - `test_the_resume_keeps_the_repository_it_was_asked_for`
  - `test_a_run_with_no_repository_or_no_project_root_is_refused`
  - `test_a_request_for_another_projects_run_survives_a_switch_and_its_reply_shows_on_that_run`
  - `test_a_request_made_with_no_project_open_is_answered_after_one_opens`
  - `test_a_control_reply_refreshes_every_usable_root`
  - `test_open_cancel_on_a_run_with_no_repository_flashes_why`
  - `test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests`
  - `test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms`

  The four logs tests of that section (5246 onward) stay.

The new file copies the helpers these tests use from `tst_run_store.qml`. The 2.2 precedent
copied them the same way (P l.98-104). The helpers are: `rootA`, `rootB`, `snapCmd`,
`ctlCmd`, `settingsCmd`, `settingsCmdB`, `noVerifySentence`, `integrateReason`, `bRepo`,
`spyC`, `make`, `makeWithProject`, `makeWithRoots`, `activeStore`, `rootEntry`, `registry`,
`reply`, `entry`, `okReply`, `allReply`, `okEntry`, `argv`, `snapshot`, `ctlEntry`, `running`,
`dead`, `integrate`, `ctlStore`, `ctlOk`, `ctlFail`, `settingsReply`, `amRequest`,
`pauseAcked`, `bWork`, `crossStore` and `held`. A helper copies only what the moved tests
need, and the planner checks each one against its use. `ctlEntry`, `running`, `dead`, `ctlOk`
and `argv` stay in `tst_run_store.qml` too, because tests that remain use them (434, 1077).
Helpers that only moved tests use leave `tst_run_store.qml`.

### Tests that stay in `tst_run_store.qml` unchanged (RunStore unit tier)

These mainly pin RunStore behaviour, and they reach control members through the shims. They
stay byte-identical and pass through `make()`'s wiring. They double as end-to-end pins of the
shims and of the settle route:

- 427 `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone` (`control`,
  `controlRunners`, `pending`);
- 1076 `test_a_nudge_refresh_that_moves_the_run_settles_its_pending_request` (settles through
  the harness route);
- 3395, 3428 (3.2's switch tests: the save failure's `flash` lands through the shim);
- 4108, 4255, 4326 (dispatch: `flashText` and `test_settings_write_failure_flashes`).

**The one changed expectation.** `test_logs_add_no_timer_and_none_runs_while_idle` (2636) lists
the RunStore's own Timer children. `flashTimer` and `pendingTimer` are no longer among them,
so the expected string becomes
`"debounceTimer,dispatchDebounceTimer,livenessTimer,pollTimer,staleTimer"`. Its
`store.pendingTimer.running` read (2651) still passes through the shim. The timers did not
disappear. They moved, and new test C2 pins them on the new store. The 2.2 cut-over changed
the same expectation for `toastTimer`.

### New tests: domain unit tier (`tst_runs.qml`)

- D1 `test_run_root_is_the_projects_root_string`: `{project: {root: "/a"}}` gives `"/a"`, and
  `{project: {root: ""}}` gives `""`.
- D2 `test_run_root_of_anything_else_is_empty`: `null`, `undefined`, `5`, `"x"`, `{}`,
  `{project: null}`, `{project: "x"}`, `{project: {}}` and `{project: {root: 7}}` all give
  `""`.

### New tests: store unit tier (`tst_run_control_store.qml`, `RunControlStore` built alone)

These pin the new interface directly, with no RunStore involved. The store is created with
`backendDir: "/plugin/core/backend/"`. Its `runs` are set directly to runs built with
`Runs.withProject(Runs.normalizeRun(...), root, name)` (the file's `held` helper).

- C1 `test_a_bare_control_store_has_nothing_pending_and_nothing_open`: `pending` and
  `stillWaiting` are `{}`, `stillWaitingText` is today's sentence, the error pair is `""`,
  `cancelRunId`, `cancelText`, `cancelError` and `flashText` are `""`, `cancelOpen` is false,
  `controlRunners` is `[]`, and `project`, `backendDir`, `active` and `runs` have their
  defaults. `pendingTimer` is objectName `pendingTimer`, interval 1000, repeat, not running.
  `flashTimer` is objectName `flashTimer`, interval 3000, no repeat, not running.
- C2 `test_the_pending_and_flash_timers_are_the_stores_only_timers`: the Timer children are
  exactly `"flashTimer,pendingTimer"`.
- C3 `test_control_and_refusal_read_the_runs_input`: with `runs` empty, `refusalOf("pause",
  "r1")` is "This run is no longer in the snapshot". After `runs = [held(running("r1"),
  rootA)]`, `control("pause", "r1")` launches `run-control.py|pause|r1|<repo_dir>`. A
  milestone resume of a dead run reads `get-run-settings|<project.root>`.
- C4 `test_every_applied_control_reply_asks_for_one_refresh_of_all`: a `refreshRequested` spy.
  An ok reply, an `ok: false` reply and a garbled reply each add exactly one emission with
  argument `"all"`, after the runner was dropped (`controlRunners` is already shorter when the
  spy's handler runs).
- C5 `test_no_refresh_for_a_stale_reply_or_a_resume_settings_step`: a reply to a superseded
  runner emits nothing. A settings-step reply that goes on to run-control emits nothing. A
  settings-step failure (nothing stored, and unreadable) emits nothing.
- C6 `test_settle_after_snapshot_reads_the_runs_input`: an acknowledged pause. With `runs`
  showing its request handled, `settleAfterSnapshot()` settles it. Another acknowledged pause
  settles when `runs` no longer lists the run. With `runs` unchanged, a second
  `settleAfterSnapshot()` leaves `pending` the same object (`verify(===)`).
- C7 `test_the_pending_timer_follows_the_stores_own_active`: pending plus `active` true means
  running. `active` false means stopped, with `pending` kept.
- C8 `test_a_project_change_changes_nothing_here`: with a request pending, an open dialog, a
  flash and a control error, setting `project` to `"/x"` and then `""` leaves `pending`,
  `stillWaiting`, `cancelRunId`, `cancelText`, `flashText`, the error pair and
  `controlRunners` as they were (identity for the maps), and launches nothing.

### New tests: RunStore unit tier (`tst_run_store.qml`)

- R1 `test_without_a_control_store_the_shims_are_empty_and_inert`: a RunStore made without
  `wireControl` reads the "without a handle" column. `control(...)`, `refusalOf(...)`,
  `flash("x")`, `openCancel("r1")`, `closeCancel()` and `confirmCancel()` return `undefined`.
  Writing `cancelText = "x"` and `cancelRunId = "r1"` reads back `""`. No `TypeError` is
  printed, because the gate greps for it.
- R2 `test_the_shims_follow_the_control_store_and_notify`: with `wireControl`,
  `store.pending === controlOf(store).pending`. `pendingChanged`, `cancelOpenChanged` and
  `flashTextChanged` spies on the RunStore each fire when `controlOf(store).control(...)`,
  `.openCancel(...)` and `.flash(...)` run.
- R3 `test_writing_the_cancel_text_and_run_id_shims_reaches_the_control_store`:
  - `store.cancelRunId = "r1"` makes the control store's `cancelRunId` `"r1"`, and
    `store.cancelOpen` true;
  - `store.cancelText = "can"` makes the control store's `cancelText` `"can"`;
  - after `controlOf(store).closeCancel()`, `store.cancelRunId` and `store.cancelText` read `""`
    (the binding is back);
  - after `controlOf(store).openCancel(...)` and a write through the control store, the shim
    follows;
  - a repeated write of the same value changes nothing.
- R4 `test_a_snapshot_settles_nothing_without_the_route`: a RunStore with a control store
  whose handle is set but with no `snapshotReplied` → settle connection. After an acknowledged
  pause, a snapshot showing the request handled leaves it pending. This pins that
  `applyProjects` no longer calls into the control store.

### New tests: App wiring tier (`tst_app_runs.qml`)

The existing tests at 318, 352 and 361 stay byte-identical. They already pin "a snapshot
settles a pending request" and "a control reply re-snapshots" through App, and they now pass
through the shims and App's routes. Added under `// ---- app.runControl (split-runstore 3.1)`:

- A1 `test_app_composes_run_control_wired_to_the_run_store`: `app.runControl` exists.
  `app.runs.controlStore === app.runControl`. `backendDir` follows App, and `active` follows
  `panelOpen`. `project` follows the selected project's root path (`""` before one is
  selected). After a snapshot, `app.runControl.runs === app.runs.runs`.
- A2 `test_a_snapshot_through_app_settles_on_run_control`: the 318 scenario, asserting on
  `app.runControl.pending` and `app.runControl.controlRunners`. It also checks
  `app.runs.pending === app.runControl.pending`.
- A3 `test_a_control_reply_through_app_snapshots_every_root_from_run_control`: the request is
  started with `app.runControl.control(...)` and answered on
  `app.runControl.controlRunners[0]`. `app.runs.snapshotRunner.seq` goes up by one, with the
  argv of every registered root.
- A4 `test_a_refresh_request_for_some_roots_snapshots_only_those`:
  `app.runControl.refreshRequested([pB.root_path])` on an idle runner launches a snapshot of
  pB alone.
- A5 `test_only_an_ok_snapshot_through_app_settles`: an acknowledged pause stays pending through
  a failed reply (`ok: false` entries for every root) and through an AmMissing reply, and
  settles on the next ok reply that shows the run gone.

### UI and architecture tiers

- `tests/ui/**` is unedited and passes. That proves the shims for `Panel` (the cancel dialog,
  its writes to `cancelText`, `onCancelOpenChanged`, `flash`), `Shortcuts` (`refusalOf`,
  `flash`, `openCancel`, `control`, `cancelOpen`, `closeCancel`), `Navigator` (`flash`), the
  screens (`pending`, `stillWaiting`, `stillWaitingText`, the error pair, `flashText`), and the
  test aliases `controlRunners` (`tst_runs_flow`, `tst_shortcuts`, `tst_card_detail_screen`)
  and the `cancelRunId` write (`tst_shortcuts.qml:777`).
- `pytest tests` passes, which includes `tests/architecture`. `RunControlStore.qml` imports
  only `QtQml`, `Quickshell`, `Quickshell.Io`, `"../domain/results.js" as Results` and
  `"../domain/runs.js" as Runs` (the store allowlist, `tests/architecture/test_layers.py`). Its
  name clashes with no shell or Controls type.

## Docs

`docs/architecture.md` is updated to match the contract:

- The `RunStore.qml` paragraph (line 91) loses the run-controls, cancel-confirmation and flash
  text. It says instead that `RunStore` keeps the moved names as shims through `controlStore`
  (`cancelText` and `cancelRunId` writable, a write forwarded), and that a snapshot settles
  requests only through App's `snapshotReplied` route. The notify-switch text stays, because it
  is 3.2's.
- A new `RunControlStore.qml` bullet, after `RunStore.qml`'s, holds the moved text: inputs
  (`backendDir`, `project`, `active`, `runs`), `control`, the resume verify read, `pending` and
  settling (`settleAfterSnapshot`, called by App on each `ok` reply before the alerts),
  `stillWaiting` and `pendingTimer`, the control error pair, `refusalOf`, the cancel
  confirmation, `flash` and `flashTimer`, `refreshRequested(roots)` (`"all"` → `refresh()`, a
  list → `requestSnapshot`), and that a project switch changes nothing here.
- The refresh-model line (172) names `RunControlStore`'s `pendingTimer` (only while a request
  is pending) beside `RunAlertsStore`'s `toastTimer`.

## Out of scope

- 3.2's members and couplings: `notifyOnEscalation`, `notifySaved`, `notifyTouched`,
  `runSettings`, `setNotifyOnEscalation`, `applyGlobalSettings`, `applyRunSettings`,
  `notifySaveReplied`, the three settings runners and their aliases, `startLive`'s settings
  lines, `projectSwitched`'s run-settings reset, rebinding `runAlerts.notifyOnEscalation`, and
  the settings tests (`// ---- alerts: the setting and the desktop notifications`,
  3300-3480).
- The resume dialog (`resume*`, `resumeSaveRunner`) and `lastControlErrorType`: absent at this
  commit (P l.415-416).
- `RunDispatchStore`, its `refreshRequested`, `runSettingsSaveRequested` and
  `noticeRequested`, and the routes for dispatch's `flash` and `runSettings` (P l.79,
  l.442-447).
- Moving `ui/` or `tests/ui/` callers to `app.runControl`, and deleting the shims and the
  handle. That is the last story (P l.128-130).
- Any change to `HelperRunner`, `run-control.py`, `viewer-state.py`, `Runs.controls`,
  `Runs.controlError` or `Runs.runById`.

## Handoff to the planner

### File structure

- Modify `core/domain/runs.js`: add `runRoot(run)` beside `runById`.
- Create `core/stores/RunControlStore.qml`: a `Scope` (root id `control`) with the inputs, the
  `refreshRequested` signal, the moved state, aliases, functions, `pendingTimer`, `flashTimer`,
  `controlState` and `controlC`. Its header comment states the contract, modelled on
  `RunAlertsStore.qml`'s.
- Modify `core/stores/RunStore.qml`: remove the moved members and the `settleAfterSnapshot()`
  call, change `runRoot` to forward to `Runs.runRoot`, add the shims, and trim the header and
  `projectSwitched` comments.
- Modify `core/stores/App.qml`: add `runControl`, `controlStore: app.runControl`, the settle
  line in `onSnapshotReplied`, and the comments.
- Create `tests/core/stores/tst_run_control_store.qml`.
- Modify `tests/core/stores/tst_run_store.qml`: add `wireControl`, `controlOf` and `make()`'s
  call, move the tests out, add R1-R4, update the timer list, and update the header comment.
- Modify `tests/core/domain/tst_runs.qml`: add D1-D2.
- Modify `tests/core/stores/tst_app_runs.qml`: add A1-A5, and mention `app.runControl` in the
  header comment.
- Modify `docs/architecture.md`.

### Suggested task order

Each task ends green on `bash tests/run.sh`:

1. `Runs.runRoot` with D1-D2, and `RunStore.runRoot` forwarding to it. No behaviour change.
2. `RunControlStore.qml` with C1-C8, built alone. RunStore is untouched, so the two stores
   briefly run side by side. Only tests construct the new store, and nothing is wired yet.
   C1-C8 need the moved function bodies, so this task copies them in. Task 3 deletes the
   originals, so at the end of the card each member exists once.
3. The cut-over, which a reviewer must see as one change:
   - `wireControl` and `controlOf` in `tst_run_store`;
   - the moved tests and their helpers in the new file;
   - the moved RunStore members and the direct settle call deleted;
   - the shims added, with R1-R4;
   - the timer-list expectation updated;
   - App's `runControl`, handle and handler, with A1-A5.
4. `docs/architecture.md`.

### Review Focus candidates

- **Writable shim loops or stale values.** A `cancelText` write must reach the control store
  and then follow it again. Typing `c`, `ca`, `can` in the dialog, then `closeCancel()`, must
  leave both stores at `""`. A handler that skips step 1 recurses. One that skips step 3 shows
  the old text when the dialog reopens.
- **A null handle printing `TypeError`.** That fails `tests/run.sh` even when every assert
  passes (R1, and `tst_run_alerts_store.qml:874` with no control store).
- **Settle on the wrong outcome or at the wrong time.** A reply listing a failed root before an
  ok root must settle once the ok emission comes. `failed` and `missing` must never settle
  (A5). The `runs` input must already be the merged list at the first emission (C6, A2).
- **The `"all"` route.** `refreshRequested("all")` must call `refresh()`, not
  `requestSnapshot("all")`, so an emptied registry still empties the lists and launches
  nothing. A list must go to `requestSnapshot` (A4).
- **Signal connection order in the test harness.** `wireControl` must run before `wireAlerts`
  in `make()`, so tests see App's settle-then-alerts order.

---

# 3.1 RunControlStore: Control Requests, Cancel Dialog and Flash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the run controls, the cancel confirmation and the footer flash out of `core/stores/RunStore.qml` into a new `core/stores/RunControlStore.qml` composed by App as `app.runControl`, settled by App on each `ok` `snapshotReplied` and re-snapshotting through a `refreshRequested(roots)` signal, with stateless shims left on `RunStore` so `ui/` and `tests/ui/` do not change.

**Architecture:** `RunControlStore` is a `Scope` (root id `control`) with four inputs bound by App (`backendDir`, `project`, `active`, `runs`), one entry point for snapshot results (`settleAfterSnapshot()`) and one signal out (`refreshRequested(roots)`). Its run lookups go through the domain (`Runs.runById(control.runs, id)`, and a new `Runs.runRoot(run)` that `RunStore`'s logs also use). `RunStore` keeps read-only property shims and one-line function forwards through a `property var controlStore: null` handle; the two members `ui/` and `tests/ui/` write (`cancelText`, `cancelRunId`) are writable shims that forward a write to the control store.

**Tech Stack:** QML (Qt 6, Quickshell `Scope`, `HelperRunner`, QtQml `Binding`), the pure JS domain `core/domain/runs.js` and `core/domain/results.js`, QtTest via `qmltestrunner` driven by `bash tests/run.sh` (offscreen, stubs from `tests/stubs`), pytest for `tests/architecture`.

**Spec:** `docs/superpowers/specs/3-1-runcontrolstore-b15b3cd3.md` (prepended above).

## Global Constraints

- Pure refactor: no behaviour change, no renamed public member, no new helper argv, no change to which process starts when, no UI change.
- Every member lands in exactly one store; nothing duplicated; nothing dropped unless no code or test reads it.
- No duplicated helpers: shared logic comes from `core/domain/` (`Runs.runById`, `Runs.runRoot`, `Runs.hasKey`, `Runs.copyMap`, `Runs.runState`, `Runs.controls`, `Runs.controlError`, `Results.parseEnvelope`); the new store keeps no private copy.
- `core/stores/RunControlStore.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io`, `"../domain/results.js" as Results` and `"../domain/runs.js" as Runs`.
- A store never imports or names a sibling; the one exception is the shim handle `property var controlStore: null`, set by App.
- Shims: a property follows the handle through a binding; a function is a one-line forward that returns the target's result; the comment above them says only `// Moved to RunControlStore; removed by the last story`. A shim with no handle must not throw (`tests/run.sh` fails a file whose output contains `TypeError`).
- App handles `snapshotReplied` in ONE handler: `runControl.settleAfterSnapshot()` on `ok`, then `runAlerts.snapshotReplied(…)`. `refreshRequested("all")` goes to `app.runs.refresh()`; a list goes to `app.runs.requestSnapshot(roots)`.
- `pendingTimer` keeps `running: control.active && Object.keys(control.pending).length > 0`.
- 3.2's members (`notifyOnEscalation`, `notifySaved`, `notifyTouched`, `runSettings`, `setNotifyOnEscalation`, `applyGlobalSettings`, `applyRunSettings`, `notifySaveReplied`, the settings runners) stay in `RunStore`, byte-unchanged.
- Tests move with their members; only construction and the wiring of inputs change, never an expectation (the one changed expectation is the timer list in `test_logs_add_no_timer_and_none_runs_while_idle`).
- `tests/ui/**` is not edited and passes; `tests/architecture` stays green; `bash tests/run.sh` is green.
- TDD: tests first. Docstrings and comments state the contract only, with no narrative.

## Deviation from the spec (writable shims)

The spec's writable shims (`cancelText`, `cancelRunId`) restore their read binding with `Qt.binding` inside the change handler. QML removes a property's binding on **any** write, including a write of the value the property already holds, and a same-value write emits no change signal, so the handler never runs and the shim silently stops following the control store. This was reproduced while validating this plan: with the spec's design, `store.cancelText = "typed"` (already `"typed"`) followed by `controlStore.cancelText = "other"` left `store.cancelText` at `"typed"`. The plan therefore keeps each writable shim as a plain `property string` driven by a QtQml `Binding` element (`Binding { target: store; property: "cancelText"; value: … }`), which re-applies the control store's value whenever it changes whatever was written in between. The handler keeps the spec's steps 1 and 2 (equal to the target: do nothing; otherwise forward the write to the handle) and, with no handle, writes `""` back instead of restoring a binding. Everything the spec requires of these shims holds: they read the handle, a differing write reaches the control store, a write with no handle snaps back to `""` without throwing, a later control-store change such as `closeCancel()` reaches the shim, and the handler is re-entrant-safe. R3 pins the same-value case.

## Review Focus

- **A write of the value a writable shim already holds.** Typing in the cancel dialog, a repeated identical write, then `closeCancel()` must leave both stores at `""`, and the shim must keep following the control store after the repeated write. Pinned by R3 (`test_writing_the_cancel_text_and_run_id_shims_reaches_the_control_store`, Task 3).
- **A shim read or called through a null handle.** A RunStore with no `controlStore` must read `{}` / `""` / `false` / `[]` / `null`, its function shims must return `undefined`, and a write to `cancelText` / `cancelRunId` must snap back, all without printing `TypeError`. Pinned by R1 (Task 3); `tst_run_alerts_store.qml:874` (a RunStore with no control store reading `flashText`) stays untouched and green.
- **Settling on the wrong outcome or the wrong emission.** `failed` and `missing` replies must never settle; a reply listing a failed root before an ok root must still settle on the ok emission; a second settle on the same `runs` must change nothing. Pinned by A5 and A7 (Task 3) and C6 (Task 2).
- **The `"all"` route.** `refreshRequested("all")` must reach `refresh()` — with an emptied registry it launches nothing — and a list must reach `requestSnapshot` for those roots only. Pinned by A3, A4 and A6 (Task 3).
- **Shim change signals.** `ui/Panel.qml:101` handles `onCancelOpenChanged` to move focus; every property shim must notify when the control store's value changes. Pinned by R2 (`pendingChanged`, `cancelOpenChanged`, `flashTextChanged`, Task 3).

---

## File Structure

- Modify `core/domain/runs.js` — add `runRoot(run)` beside `runById` (Task 1).
- Modify `tests/core/domain/tst_runs.qml` — D1-D2 (Task 1).
- Modify `core/stores/RunStore.qml` — `runRoot` forwards to `Runs.runRoot` (Task 1); the control members, aliases, timers, `controlState`, `controlC` and the direct settle call go, the shims arrive, the header and `projectSwitched` comments are trimmed (Task 3).
- Create `core/stores/RunControlStore.qml` — the run controls, the cancel confirmation and the footer flash (Task 2).
- Create `tests/core/stores/tst_run_control_store.qml` — test case `StoresRunControlStore`: C1-C8 on the bare store (Task 2), then the 42 moved tests driven through a wired RunStore (Task 3).
- Modify `tests/core/stores/tst_run_store.qml` — `wireControl` / `controlOf` harness, R1-R4, the moved tests and their own helpers removed, the timer-list expectation (Task 3).
- Modify `core/stores/App.qml` — `runControl`, the handle and the handler (Task 3).
- Modify `tests/core/stores/tst_app_runs.qml` — A1-A7 (Task 3).
- Modify `docs/architecture.md` (Task 4).

How to run tests: `bash tests/run.sh <substring>` runs pytest (about two minutes) and then every QML test whose path contains `<substring>`; a QML file passes when its `Totals:` line shows `0 failed` and the script prints no `TypeError` / `ReferenceError` / `Unable to assign` line. The script's exit status is non-zero on any failure. Run from the worktree root. Wrap long runs in `timeout`, e.g. `timeout 900 bash tests/run.sh`.

---

### Task 1: `Runs.runRoot`, and `RunStore.runRoot` forwarding to it

**Files:**
- Modify: `core/domain/runs.js` (the `// ---- Store helpers (split-runstore 2.1)` section, between `runById` and `hasKey`, ~line 1348)
- Modify: `core/stores/RunStore.qml` (`runRoot`, ~lines 761-766)
- Test: `tests/core/domain/tst_runs.qml` (append before the final `}`)

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Tasks 2 and 3): `Runs.runRoot(run)` → string: `run.project.root` when `run` is a non-null object whose `project` is a non-null object whose `root` is a string (returned as it is, so `""` stays `""`); `""` otherwise.

- [ ] **Step 1: Write the failing tests**

In `tests/core/domain/tst_runs.qml`, the file ends with `test_copy_map_of_nothing_is_empty` and then the TestCase's closing `}`. Insert immediately before that final `}`:

```qml
  // D1
  function test_run_root_is_the_projects_root_string() {
    compare(Runs.runRoot({ project: { root: "/a" } }), "/a")
    compare(Runs.runRoot({ project: { root: "" } }), "", "an empty root stays empty")
  }

  // D2
  function test_run_root_of_anything_else_is_empty() {
    var others = [null, undefined, 5, "x", {}, { project: null }, { project: "x" }, { project: {} }, { project: { root: 7 } }]
    for (var i = 0; i < others.length; i++) compare(Runs.runRoot(others[i]), "", JSON.stringify(others[i]))
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_runs.qml`
Expected: FAIL — `test_run_root_is_the_projects_root_string` and `test_run_root_of_anything_else_is_empty` fail with `TypeError: Property 'runRoot' of object [object Object] is not a function` (or similar); the script exits non-zero.

- [ ] **Step 3: Add `runRoot` to the domain**

In `core/domain/runs.js`, find:

```js
// Whether `map` has `key` as an own property; false for a null or undefined map.
function hasKey(map, key) {
```

and replace it with:

```js
// `run.project.root` when `run` is a non-null object whose `project` is a
// non-null object whose `root` is a string (returned as it is, so "" stays
// ""); "" otherwise.
function runRoot(run) {
  var p = run !== null && typeof run === "object" ? run.project : null
  if (p === null || typeof p !== "object" || typeof p.root !== "string") return ""
  return p.root
}

// Whether `map` has `key` as an own property; false for a null or undefined map.
function hasKey(map, key) {
```

- [ ] **Step 4: Make `RunStore.runRoot` forward to it**

In `core/stores/RunStore.qml`, find:

```qml
  function runRoot(run) {
    var p = run !== null && typeof run === "object" ? run.project : null
    if (p === null || typeof p !== "object" || typeof p.root !== "string") return ""
    return p.root
  }
```

and replace it with:

```qml
  function runRoot(run) {
    return Runs.runRoot(run)
  }
```

(The comment above it, `// The run's project root when it is a non-empty string, else "".`, stays.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_runs.qml`
Expected: PASS — `tests/core/domain/tst_runs.qml` reports `Totals: 217 passed, 0 failed`; exit 0.

Run: `timeout 900 bash tests/run.sh tst_run_store`
Expected: PASS — `Totals: 293 passed, 0 failed` (the logs tests that read `runRoot` are unchanged); exit 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runs.js core/stores/RunStore.qml tests/core/domain/tst_runs.qml
git commit -m "feat(domain): Runs.runRoot, and RunStore.runRoot forwards to it"
```

---

### Task 2: `RunControlStore.qml`, built alone, with C1-C8

The new store is a copy of `RunStore`'s control code with `store.` → `control.`, `store.runById(x)` → `Runs.runById(control.runs, x)`, `store.runRoot(r)` → `Runs.runRoot(r)`, and `store.refresh()` in `controlReplied` → `control.refreshRequested("all")`. `RunStore` is not touched in this task, so the two copies briefly coexist; Task 3 deletes the originals. Nothing composes the new store yet.

**Files:**
- Create: `core/stores/RunControlStore.qml`
- Create: `tests/core/stores/tst_run_control_store.qml`

**Interfaces:**
- Consumes: `Runs.runRoot(run)` (Task 1); `Runs.runById`, `Runs.hasKey`, `Runs.copyMap`, `Runs.runState`, `Runs.controls`, `Runs.controlError` from `core/domain/runs.js`; `Results.parseEnvelope` from `core/domain/results.js`; `HelperRunner` (same directory: `script`, `run(args)`, `current`, `seq`, signal `finished(stdout, exitCode)`).
- Produces (used by Tasks 3 and 4):
  - inputs: `property string backendDir: ""`, `property string project: ""`, `property bool active: false`, `property var runs: []`
  - `signal refreshRequested(var roots)` — emitted only as `refreshRequested("all")`
  - state: `property var pending: ({})`, `property var stillWaiting: ({})`, `readonly property string stillWaitingText`, `property string lastControlError: ""`, `property string lastControlErrorRunId: ""`, `property string cancelRunId: ""`, `readonly property bool cancelOpen`, `property string cancelText: ""`, `property string cancelError: ""`, `property string flashText: ""`
  - `readonly property alias controlRunners` (array of HelperRunner, each with `runId`, `action`, `token`, `repoDir`, `projectRoot`, `settingsStep`), `readonly property alias pendingTimer` (Timer, `objectName: "pendingTimer"`), `readonly property alias flashTimer` (Timer, `objectName: "flashTimer"`)
  - `control(action, runId)` → bool, `refusalOf(action, runId)` → string, `flash(text)`, `openCancel(runId)` → bool, `closeCancel()`, `confirmCancel()` → bool, `settleAfterSnapshot()`, `checkWaiting(nowMs)`, `dismissControlError()`, `settle(runId)`, and the internals `launchControl`, `requestOf`, `failControl`, `dropRunner`, `controlReplied`, `resumeWithSettings`, `isHandled`
  - test helpers in `tst_run_control_store.qml`: `makeControl()`, `reply(proc, text, code)`, `argv(proc)`, `entry`, `ctlEntry`, `running`, `dead`, `held(e, root)`, `ctlOk`, `ctlFail`, `settingsReply`, `amRequest`, properties `rootA`, `rootB`, `ctlCmd`, `settingsCmd`, `noVerifySentence`, and `spyC`

- [ ] **Step 1: Write the failing tests**

Create `tests/core/stores/tst_run_control_store.qml` with exactly this content:

```qml
// tests/core/stores/tst_run_control_store.qml
// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation and the footer flash. Built alone and driven through its
// `runs` input, settleAfterSnapshot() and stubbed Process objects.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunControlStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string ctlCmd: "python3|/plugin/core/backend/runs/run-control.py|"
  property string settingsCmd: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/my proj"
  property string noVerifySentence: "Resume needs verify commands: none are stored for this project, and running without verification was not chosen."

  Component { id: spyC; SignalSpy {} }

  // A RunControlStore built alone, with nothing bound.
  function makeControl() {
    var comp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data. Its repo_dir is `root`, else rootA.
  function entry(id, runStatus, live, root) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: root || tc.rootA, started_at: "2026-10-01T00:00:00Z",
      status: {
        run: run,
        rows: [],
        stories: [],
        subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
  }

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

  // A run as the store holds it, built from snapshot entry `e`: normalized,
  // with no project root unless `root` is given.
  function held(e, root) {
    var row = {}
    for (var k in e) if (k !== "status") row[k] = e[k]
    var run = Runs.normalizeRun({ row: row, status: e.status })
    return root === undefined ? run : Runs.withProject(run, root, "")
  }

  function ctlOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  // viewer-state.py get-run-settings: one bare object, not an envelope.
  function settingsReply(verify, allow) {
    return JSON.stringify({ verify: verify, allowNoVerification: allow, notifyOnEscalation: false }) + "\n"
  }

  // One am control request row.
  function amRequest(command, requestedAt, handledAt) {
    return { command: command, requested_at: requestedAt, handled_at: handledAt }
  }

  // ---- the store alone (split-runstore 3.1)

  // C1
  function test_a_bare_control_store_has_nothing_pending_and_nothing_open() {
    var c = makeControl(); if (!c) return
    compare(JSON.stringify(c.pending), "{}")
    compare(JSON.stringify(c.stillWaiting), "{}")
    compare(c.stillWaitingText, "still waiting — the run may be between phases or dead")
    compare(c.lastControlError, "")
    compare(c.lastControlErrorRunId, "")
    compare(c.cancelRunId, "")
    compare(c.cancelOpen, false)
    compare(c.cancelText, "")
    compare(c.cancelError, "")
    compare(c.flashText, "")
    compare(c.controlRunners.length, 0)
    compare(c.project, "")
    compare(c.backendDir, "/plugin/core/backend/")
    compare(c.active, false)
    compare(c.runs.length, 0)
    compare(c.pendingTimer.objectName, "pendingTimer")
    compare(c.pendingTimer.interval, 1000)
    compare(c.pendingTimer.repeat, true)
    compare(c.pendingTimer.running, false)
    compare(c.flashTimer.objectName, "flashTimer")
    compare(c.flashTimer.interval, 3000)
    compare(c.flashTimer.repeat, false)
    compare(c.flashTimer.running, false)
  }

  // C2
  function test_the_pending_and_flash_timers_are_the_stores_only_timers() {
    var c = makeControl(); if (!c) return
    var timers = []
    for (var i = 0; i < c.data.length; i++) {
      var o = c.data[i]
      if (o && typeof o.interval === "number" && typeof o.repeat === "boolean") timers.push(o.objectName)
    }
    compare(timers.sort().join(","), "flashTimer,pendingTimer")
  }

  // C3
  function test_control_and_refusal_read_the_runs_input() {
    var c = makeControl(); if (!c) return
    compare(c.refusalOf("pause", "r1"), "This run is no longer in the snapshot")
    compare(c.control("pause", "r1"), false)
    c.runs = [held(running("r1"), tc.rootA), held(dead("r2"), tc.rootB)]
    compare(c.refusalOf("pause", "r1"), "")
    compare(c.control("pause", "r1"), true)
    compare(c.controlRunners.length, 1)
    compare(argv(c.controlRunners[0].current), tc.ctlCmd + "pause|r1|/home/u/my proj")
    compare(c.control("resume", "r2"), true)
    compare(argv(c.controlRunners[1].current), "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/b",
            "a milestone resume reads the settings of the run's project.root")
  }

  // C4
  function test_every_applied_control_reply_asks_for_one_refresh_of_all() {
    var c = makeControl(); if (!c) return
    c.runs = [held(running("r1"), tc.rootA), held(running("r2"), tc.rootA), held(running("r3"), tc.rootA)]
    var seen = []
    c.refreshRequested.connect(function(roots) { seen.push({ roots: roots, runners: c.controlRunners.length }) })
    c.control("pause", "r1")
    c.control("pause", "r2")
    c.control("cancel", "r3")
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(seen.length, 1, "an ok reply")
    reply(c.controlRunners[0].current, ctlFail("NotRunningError", "x"), 0)
    compare(seen.length, 2, "an ok: false reply")
    reply(c.controlRunners[0].current, "garbage\n", 1)
    compare(seen.length, 3, "a garbled reply")
    for (var i = 0; i < seen.length; i++) {
      compare(seen[i].roots, "all")
      compare(seen[i].runners, 2 - i, "the runner was dropped first")
    }
  }

  // C5
  function test_no_refresh_for_a_stale_reply_or_a_resume_settings_step() {
    var c = makeControl(); if (!c) return
    c.runs = [held(running("r1"), tc.rootA), held(dead("r2"), tc.rootA), held(dead("r3"), tc.rootA), held(dead("r4"), tc.rootA)]
    var spy = createTemporaryObject(spyC, tc, { target: c, signalName: "refreshRequested" })
    c.control("pause", "r1")
    var stale = c.controlRunners[0]
    c.settle("r1")
    reply(stale.current, ctlOk({ requested_at: "t1" }), 0)
    compare(spy.count, 0, "a reply to a request no longer pending")
    compare(c.controlRunners.length, 0, "its runner still goes")
    c.control("resume", "r2")
    reply(c.controlRunners[0].current, settingsReply(["a"], false), 0)
    compare(c.controlRunners.length, 1, "the settings step went on to run-control")
    compare(spy.count, 0, "a settings step that goes on")
    c.control("resume", "r3")
    reply(c.controlRunners[1].current, settingsReply([], false), 0)
    compare(c.lastControlError, tc.noVerifySentence)
    compare(spy.count, 0, "a settings step with nothing stored")
    c.control("resume", "r4")
    reply(c.controlRunners[1].current, "oops\n", 2)
    compare(c.lastControlError, "The run settings gave no usable result (exit 2).")
    compare(spy.count, 0, "an unreadable settings step")
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t2" }), 0)
    compare(spy.count, 1, "the run-control reply after the settings step")
  }

  // C6
  function test_settle_after_snapshot_reads_the_runs_input() {
    var c = makeControl(); if (!c) return
    c.runs = [held(running("r1"), tc.rootA), held(running("r2"), tc.rootA)]
    c.control("pause", "r1")
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    c.control("pause", "r2")
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t2" }), 0)
    compare(Object.keys(c.pending).sort().join(","), "r1,r2", "acknowledged, not settled")
    c.runs = [held(ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", "t1h")]), tc.rootA),
              held(running("r2"), tc.rootA)]
    c.settleAfterSnapshot()
    compare(Object.keys(c.pending).join(","), "r2", "r1's request is handled")
    var before = c.pending
    c.settleAfterSnapshot()
    verify(c.pending === before, "a second call with the same runs changes nothing")
    c.runs = []
    c.settleAfterSnapshot()
    compare(Object.keys(c.pending).length, 0, "r2 left the runs")
  }

  // C7
  function test_the_pending_timer_follows_the_stores_own_active() {
    var c = makeControl(); if (!c) return
    c.runs = [held(running("r1"), tc.rootA)]
    c.active = true
    compare(c.pendingTimer.running, false, "nothing pending")
    c.control("pause", "r1")
    compare(c.pendingTimer.running, true)
    c.active = false
    compare(c.pendingTimer.running, false)
    compare(c.pending.r1, "pause", "closing keeps pending")
    c.active = true
    compare(c.pendingTimer.running, true)
  }

  // C8
  function test_a_project_change_changes_nothing_here() {
    var c = makeControl(); if (!c) return
    c.runs = [held(running("r1"), tc.rootA), held(running("r2"), tc.rootA), held(running("r3"), tc.rootA)]
    c.control("pause", "r3")
    c.control("pause", "r2")
    reply(c.controlRunners[1].current, ctlFail("NotRunningError", "not running"), 0)
    c.checkWaiting(Date.now() + 30000)
    c.openCancel("r1")
    c.cancelText = "can"
    c.flash("The run has finished")
    var pending = c.pending, waiting = c.stillWaiting, runners = c.controlRunners
    var seq = c.controlRunners[0].seq
    c.project = "/x"
    c.project = ""
    verify(c.pending === pending, "pending")
    verify(c.stillWaiting === waiting, "stillWaiting")
    compare(c.stillWaiting.r3, true)
    compare(c.cancelRunId, "r1")
    compare(c.cancelText, "can")
    compare(c.flashText, "The run has finished")
    compare(c.lastControlError, "The run is not running")
    compare(c.lastControlErrorRunId, "r2")
    verify(c.controlRunners === runners, "controlRunners")
    compare(c.controlRunners.length, 1)
    compare(c.controlRunners[0].seq, seq, "nothing launched")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_run_control_store`
Expected: FAIL — every test fails at `makeControl()` with the `fail(comp.errorString())` message naming `RunControlStore.qml` (the file does not exist); exit non-zero.

- [ ] **Step 3: Write the store**

Create `core/stores/RunControlStore.qml` with exactly this content:

```qml
import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// The run controls (S2 4.1), the cancel confirmation (S2 4.3) and the footer
// flash, for a run of any registered project. control(action, runId) starts a
// pause, resume or cancel of a run in `runs`, each on a HelperRunner of its
// own; `pending` ({runId: action}) holds a request until settleAfterSnapshot()
// sees it settled, `stillWaiting` ({runId: true}) the pending ones 30 s or
// more old. Both are replaced, never changed in place. The control error is
// its own pair of fields, which no snapshot touches. Every applied control
// reply asks for a re-snapshot of every root: refreshRequested("all"). The
// backend directory, the open project's root, the panel-open flag and the
// run list are handed to it from outside -- it never reaches for another
// store. App composes it as `app.runControl`, calls settleAfterSnapshot() on
// each ok snapshotReplied of the run store, and routes refreshRequested
// there. A project switch changes nothing here.
Scope {
  id: control

  property string backendDir: ""      // <plugin>/core/backend/
  property string project: ""         // the open project's root path; "" when none is open
  property bool active: false         // App binds this to "panel open" (app.panelOpen)
  property var runs: []               // the run store's merged run list; App binds it

  // A re-snapshot is wanted: "all" (every usable root) or [root, ...].
  signal refreshRequested(var roots)

  property var pending: ({})
  property var stillWaiting: ({})
  readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about

  // The cancel confirmation: the run it asks about ("" = closed), the typed
  // word and why the last confirm was refused.
  property string cancelRunId: ""
  readonly property bool cancelOpen: control.cancelRunId !== ""
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""

  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer

  // Starts a pause, resume or cancel of one run in `runs`, of any project, and
  // returns whether it started: only when refusalOf(action, runId) is "".
  // The request acts on the run's repo_dir; a milestone resume reads the run
  // settings of the run's project.root. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (control.refusalOf(action, runId) !== "") return false
    var run = Runs.runById(control.runs, runId)
    control.dismissControlError()
    controlState.nextToken += 1
    var requests = Runs.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = Runs.copyMap(control.pending)
    p[runId] = action
    control.pending = p
    var runner = controlC.createObject(control, { runId: runId, action: action, token: controlState.nextToken,
                                                  repoDir: run.repo_dir, projectRoot: Runs.runRoot(run) })
    controlState.runners = controlState.runners.concat([runner])
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses its project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = control.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", runner.projectRoot])
    } else {
      control.launchControl(runner, [])
    }
    return true
  }

  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // REPO the repo_dir the request was made with, then `extra` (a resume's
  // verify arguments).
  function launchControl(runner, extra) {
    runner.script = control.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, runner.repoDir].concat(extra))
  }

  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled or replaced by a newer
  // request.
  function requestOf(runner) {
    if (!Runs.hasKey(controlState.requests, runner.runId)) return null
    var req = controlState.requests[runner.runId]
    return req.token === runner.token ? req : null
  }

  // The request for runId is over: its pending entry, its still-waiting mark
  // and its bookkeeping go.
  function settle(runId) {
    if (Runs.hasKey(control.pending, runId)) {
      var p = Runs.copyMap(control.pending)
      delete p[runId]
      control.pending = p
    }
    if (Runs.hasKey(control.stillWaiting, runId)) {
      var w = Runs.copyMap(control.stillWaiting)
      delete w[runId]
      control.stillWaiting = w
    }
    if (Runs.hasKey(controlState.requests, runId)) {
      var r = Runs.copyMap(controlState.requests)
      delete r[runId]
      controlState.requests = r
    }
  }

  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run.
  function failControl(runId, sentence) {
    control.settle(runId)
    control.lastControlError = sentence
    control.lastControlErrorRunId = runId
  }

  function dismissControlError() {
    control.lastControlError = ""
    control.lastControlErrorRunId = ""
  }

  // A runner's request is over: it leaves controlRunners and is destroyed.
  function dropRunner(runner) {
    controlState.runners = controlState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // One run-control.py reply, whatever project is open. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence. Either way the runner goes, then refreshRequested("all"). A
  // reply for a request that is no longer the pending one changes nothing.
  function controlReplied(runner, stdout, exitCode) {
    var req = control.requestOf(runner)
    if (req === null) {
      control.dropRunner(runner)
      return
    }
    if (runner.settingsStep) {
      runner.settingsStep = false
      control.resumeWithSettings(runner, stdout, exitCode)
      return
    }
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var data = envelope.data
      var requestedAt = data !== null && typeof data === "object" && typeof data.requested_at === "string" ? data.requested_at : ""
      var requests = Runs.copyMap(controlState.requests)
      requests[runner.runId] = { token: req.token, action: req.action, baseline: req.baseline,
                                 launchedMs: req.launchedMs, acknowledged: true, requestedAt: requestedAt }
      controlState.requests = requests
    } else if (envelope !== null && envelope.ok === false) {
      control.failControl(runner.runId, Runs.controlError(envelope))
    } else {
      control.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").")
    }
    control.dropRunner(runner)
    control.refreshRequested("all")
  }

  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification; with
  // neither, or no readable reply, run-control is never launched and the
  // request ends with a sentence -- no re-snapshot, nothing was asked of am.
  function resumeWithSettings(runner, stdout, exitCode) {
    var settings = Results.parseEnvelope(stdout)
    if (settings === null) {
      control.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").")
      control.dropRunner(runner)
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
      control.launchControl(runner, extra)
    } else if (settings.allowNoVerification === true) {
      control.launchControl(runner, ["--allow-no-verification"])
    } else {
      control.failControl(runner.runId, "Resume needs verify commands: none are stored for this project, and running without verification was not chosen.")
      control.dropRunner(runner)
    }
  }

  // After every good snapshot: an acknowledged request is settled when its run
  // is gone from `runs`, when the run's state moved since the request started,
  // or (pause, cancel) when am marks its request handled. A request still in
  // flight is never settled by a snapshot: its buttons stay off until the reply.
  function settleAfterSnapshot() {
    var ids = Object.keys(control.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (!Runs.hasKey(controlState.requests, id)) continue
      var req = controlState.requests[id]
      if (!req.acknowledged) continue
      var run = Runs.runById(control.runs, id)
      if (run === null || Runs.runState(run) !== req.baseline
          || (req.action !== "resume" && control.isHandled(run, req))) control.settle(id)
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

  // Marks the pending requests launched 30 s or more before nowMs (the timer
  // passes Date.now()); the UI shows stillWaitingText for them.
  function checkWaiting(nowMs) {
    var out = {}
    var ids = Object.keys(control.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (Runs.hasKey(controlState.requests, id) && nowMs - controlState.requests[id].launchedMs >= 30000) out[id] = true
    }
    control.stillWaiting = out
  }

  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in `runs`, then a run with no repo_dir, then a resume
  // (not of a task run) of a run with no project root, then a request already
  // pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = typeof runId !== "string" || runId === "" ? null : Runs.runById(control.runs, runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (typeof run.repo_dir !== "string" || run.repo_dir === "") return "This run has no repository"
    if (action === "resume" && run.workflow !== "task" && Runs.runRoot(run) === "") return "This run's project is not known"
    if (Runs.hasKey(control.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action].reason
  }

  // Shows text in the footers for 3 s; a new flash replaces it and restarts
  // the clock, flash("") clears it.
  function flash(text) {
    control.flashText = String(text || "")
    if (control.flashText === "") flashTimer.stop()
    else flashTimer.restart()
  }

  // Opens the cancel confirmation for a run that can be cancelled now;
  // otherwise flashes why not and leaves any dialog as it is.
  function openCancel(runId) {
    var reason = control.refusalOf("cancel", runId)
    if (reason !== "") {
      control.flash(reason)
      return false
    }
    control.cancelText = ""
    control.cancelError = ""
    control.cancelRunId = runId
    return true
  }

  function closeCancel() {
    control.cancelRunId = ""
    control.cancelText = ""
    control.cancelError = ""
  }

  // The dialog's confirm. The typed word is checked again here (the dialog
  // gates it too), then the run is checked again: one that changed under the
  // open dialog keeps it open with the reason. A started cancel closes it.
  function confirmCancel() {
    if (control.cancelRunId === "") return false
    if (String(control.cancelText).trim().toLowerCase() !== "cancel") return false
    var reason = control.refusalOf("cancel", control.cancelRunId)
    if (reason !== "") {
      control.cancelError = reason
      return false
    }
    if (!control.control("cancel", control.cancelRunId)) {
      control.cancelError = "The run could not be cancelled"
      return false
    }
    control.closeCancel()
    return true
  }

  // Only while the panel is open and a control request is pending: closing the
  // panel keeps `pending` but leaves no timer running.
  Timer {
    id: pendingTimer
    objectName: "pendingTimer"
    interval: 1000
    repeat: true
    running: control.active && Object.keys(control.pending).length > 0
    onTriggered: control.checkWaiting(Date.now())
  }

  // Clears the footer flash 3 s after the last flash().
  Timer {
    id: flashTimer
    objectName: "flashTimer"
    interval: 3000
    repeat: false
    onTriggered: control.flashText = ""
  }

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
  // stop each other. No guard: a reply is applied whatever project is open.
  // A milestone resume uses its runner twice: viewer-state.py, then
  // run-control.py.
  Component {
    id: controlC

    HelperRunner {
      id: cr
      property string runId: ""
      property string action: ""
      property int token: 0
      property string repoDir: ""         // the run's repo_dir when the request was made
      property string projectRoot: ""     // the run's project.root then; "" when it had none
      property bool settingsStep: false   // reading the run settings; run-control comes next
      onFinished: function(stdout, exitCode) { control.controlReplied(cr, stdout, exitCode) }
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_run_control_store`
Expected: PASS — `Totals: 10 passed, 0 failed` (8 tests plus initTestCase/cleanupTestCase), no `TypeError` line; exit 0.

- [ ] **Step 5: Run the architecture tests**

Run: `uv run --with pytest python3 -m pytest tests/architecture -q` (or `python3 -m pytest tests/architecture -q` when pytest is installed)
Expected: PASS — `12 passed`. The new store's imports are on the store allowlist and its name clashes with no shell or Controls type.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunControlStore.qml tests/core/stores/tst_run_control_store.qml
git commit -m "feat(runs): RunControlStore with control requests, the cancel dialog and the flash, built alone"
```

---

### Task 3: The cut-over — the controls move to `RunControlStore`, shims on `RunStore`, App wiring

One change a reviewer sees whole: the tests move, the RunStore control members and the direct settle call go, the shims arrive, and App composes and routes.

**Files:**
- Modify: `tests/core/stores/tst_run_store.qml` (header comment, `make()` at lines 33-40, the timer list at ~line 2646, R1-R4 appended, the moved tests and their own helpers removed)
- Modify: `tests/core/stores/tst_run_control_store.qml` (header comment; the wired-RunStore section appended before the final `}`)
- Modify: `tests/core/stores/tst_app_runs.qml` (header comment; A1-A7 appended before the final `}`)
- Modify: `core/stores/RunStore.qml`
- Modify: `core/stores/App.qml`

**Interfaces:**
- Consumes: Task 1's `Runs.runRoot`; Task 2's `RunControlStore` members; `RunStore.snapshotReplied(root, outcome, previousRuns, runs)`, `RunStore.refresh()`, `RunStore.requestSnapshot(roots)` (unchanged).
- Produces (read by `ui/`, `tests/ui/` and the last story):
  - `RunStore.controlStore` (`property var`, default `null`)
  - read-only shims on `RunStore`: `pending` (var, `({})` without handle), `stillWaiting` (var, `({})`), `stillWaitingText` (string, `""`), `lastControlError` (string, `""`), `lastControlErrorRunId` (string, `""`), `cancelOpen` (bool, `false`), `cancelError` (string, `""`), `flashText` (string, `""`), `controlRunners` (var, `[]`), `pendingTimer` (var, `null`), `flashTimer` (var, `null`)
  - writable shims on `RunStore`: `cancelRunId`, `cancelText` (string, `""` without handle; a differing write goes to the handle)
  - function shims on `RunStore`: `control(action, runId)`, `refusalOf(action, runId)`, `flash(text)`, `openCancel(runId)`, `closeCancel()`, `confirmCancel()` — each returns the target's result, or `undefined` without a handle
  - `App.runControl` (`readonly property RunControlStore`)
  - test helpers in `tst_run_store.qml` and `tst_run_control_store.qml`: `wireControl(store)` → RunControlStore, `controlOf(store)` → RunControlStore | null

- [ ] **Step 1: Wire the RunStore tests and write R1-R4**

In `tests/core/stores/tst_run_store.qml`:

(a) Find the header comment's last lines:

```qml
// project switch leaves alone, and the snapshotReplied it emits. Built
// directly, wired to a RunAlertsStore the way App wires app.runAlerts, and
// driven through stubbed Process objects. The alerts themselves are tested in
// tst_run_alerts_store.qml.
```

and replace them with:

```qml
// project switch leaves alone, and the snapshotReplied it emits. Built
// directly, wired to a RunControlStore and a RunAlertsStore the way App wires
// app.runControl and app.runAlerts, and driven through stubbed Process
// objects. The run controls are tested in tst_run_control_store.qml, the
// alerts in tst_run_alerts_store.qml.
```

(b) Find:

```qml
  // A RunStore wired to its own RunAlertsStore (wireAlerts).
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireAlerts(store)
    return store
  }
```

and replace it with (`wireControl` runs first so the two `snapshotReplied` connections run in App's order: settle, then alerts):

```qml
  // A RunStore wired to its own RunControlStore (wireControl), then to its
  // own RunAlertsStore (wireAlerts): App's snapshotReplied order.
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireControl(store)
    wireAlerts(store)
    return store
  }

  // Every {store, control} pair wireControl made.
  property var controlPairs: []

  // A RunControlStore wired to `store` the way App wires app.runControl:
  // backendDir copied; project, active and runs bound to the run store's own;
  // store.controlStore set; an ok snapshotReplied settles its requests; its
  // refreshRequested goes to refresh() ("all") or requestSnapshot(roots).
  function wireControl(store) {
    var comp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var c = comp.createObject(tc, { backendDir: store.backendDir })
    c.project = Qt.binding(function() { return store.project })
    c.active = Qt.binding(function() { return store.active })
    c.runs = Qt.binding(function() { return store.runs })
    store.controlStore = c
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
    c.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    tc.controlPairs = tc.controlPairs.concat([{ store: store, control: c }])
    return c
  }

  // The RunControlStore wireControl paired with `store`; null when none.
  function controlOf(store) {
    for (var i = 0; i < tc.controlPairs.length; i++) {
      if (tc.controlPairs[i].store === store) return tc.controlPairs[i].control
    }
    return null
  }
```

(c) In `test_logs_add_no_timer_and_none_runs_while_idle`, find:

```qml
    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer", "the logs add no timer")
```

and replace it with:

```qml
    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,livenessTimer,pollTimer,staleTimer", "the logs add no timer")
```

(The `store.pendingTimer.running` read a few lines below stays: it now goes through the shim.)

(d) Append these four tests immediately before the file's final `}` (after `test_every_shim_function_forwards_to_the_alerts_store`):

```qml
  // ---- the run control shims (split-runstore 3.1)

  // R1
  function test_without_a_control_store_the_shims_are_empty_and_inert() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    compare(store.controlStore, null)
    compare(JSON.stringify(store.pending), "{}")
    compare(JSON.stringify(store.stillWaiting), "{}")
    compare(store.stillWaitingText, "")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.cancelRunId, "")
    compare(store.cancelOpen, false)
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    compare(JSON.stringify(store.controlRunners), "[]")
    compare(store.pendingTimer, null)
    compare(store.flashTimer, null)
    compare(store.control("pause", "r1"), undefined)
    compare(store.refusalOf("pause", "r1"), undefined)
    compare(store.flash("x"), undefined)
    compare(store.openCancel("r1"), undefined)
    compare(store.closeCancel(), undefined)
    compare(store.confirmCancel(), undefined)
    store.cancelText = "x"
    compare(store.cancelText, "", "a write with no handle snaps back")
    store.cancelRunId = "r1"
    compare(store.cancelRunId, "")
    compare(store.cancelOpen, false)
    compare(store.flashText, "")
  }

  // R2
  function test_the_shims_follow_the_control_store_and_notify() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([running("r1"), running("r2")]), 0)
    var c = controlOf(store)
    verify(store.controlStore === c, "the handle is the paired control store")
    verify(store.pending === c.pending)
    var pendingSpy = createTemporaryObject(spyC, tc, { target: store, signalName: "pendingChanged" })
    var openSpy = createTemporaryObject(spyC, tc, { target: store, signalName: "cancelOpenChanged" })
    var flashSpy = createTemporaryObject(spyC, tc, { target: store, signalName: "flashTextChanged" })
    compare(c.control("pause", "r1"), true)
    compare(pendingSpy.count, 1, "the shim notifies like the original")
    verify(store.pending === c.pending)
    compare(store.pending.r1, "pause")
    verify(store.controlRunners === c.controlRunners)
    compare(store.controlRunners.length, 1)
    compare(c.openCancel("r2"), true)
    compare(openSpy.count, 1)
    compare(store.cancelOpen, true)
    compare(store.cancelRunId, "r2")
    c.flash("hello")
    compare(flashSpy.count, 1)
    compare(store.flashText, "hello")
    verify(store.pendingTimer === c.pendingTimer)
    verify(store.flashTimer === c.flashTimer)
    compare(store.stillWaitingText, c.stillWaitingText)
    compare(store.refusalOf("pause", "r1"), "A request for this run is pending", "a function shim returns the target's result")
    compare(store.confirmCancel(), false)
    store.closeCancel()
    compare(c.cancelOpen, false, "a forward reaches the control store")
    compare(openSpy.count, 2)
  }

  // R3
  function test_writing_the_cancel_text_and_run_id_shims_reaches_the_control_store() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([running("r1"), running("r2")]), 0)
    var c = controlOf(store)
    store.cancelRunId = "r1"
    compare(c.cancelRunId, "r1", "the write reached the control store")
    compare(store.cancelOpen, true)
    store.cancelText = "c"
    store.cancelText = "ca"
    store.cancelText = "can"
    compare(c.cancelText, "can")
    compare(store.cancelText, "can")
    c.closeCancel()
    compare(store.cancelRunId, "", "the binding is back")
    compare(store.cancelText, "")
    compare(c.openCancel("r2"), true)
    compare(store.cancelRunId, "r2", "the shim follows the control store again")
    c.cancelText = "typed"
    compare(store.cancelText, "typed")
    var spy = createTemporaryObject(spyC, tc, { target: c, signalName: "cancelTextChanged" })
    store.cancelText = "typed"
    compare(spy.count, 0, "a repeated write of the same value changes nothing")
    c.cancelText = "other"
    compare(store.cancelText, "other", "and the shim still follows the control store")
    store.cancelText = " Cancel "
    compare(c.cancelText, " Cancel ")
    compare(spy.count, 2)
    store.cancelRunId = "r2"
    compare(store.confirmCancel(), true, "the written word is the control store's")
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "", "the run id shim follows after a repeated write too")
    compare(store.cancelText, "")
  }

  // R4
  function test_a_snapshot_settles_nothing_without_the_route() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var cc = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (cc.status !== Component.Ready) { fail(cc.errorString()); return }
    var c = cc.createObject(tc, { backendDir: "/plugin/core/backend/" })
    c.runs = Qt.binding(function() { return store.runs })
    store.controlStore = c
    store.projectRoots = [rootEntry(rootA)]
    store.project = rootA
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(c.control("pause", "r1"), true)
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])])
    compare(store.amStatus, "ok")
    compare(c.pending.r1, "pause", "the run store no longer settles requests itself")
    compare(store.pending.r1, "pause")
  }
```

- [ ] **Step 2: Write the App wiring tests (A1-A7)**

In `tests/core/stores/tst_app_runs.qml`:

(a) Find the header comment's last lines:

```qml
// driven through App, including `app.runAlerts`, which App feeds with the run
// store's snapshotReplied. The stores' own behaviour is tested in
// tst_run_store.qml and tst_run_alerts_store.qml.
```

and replace them with:

```qml
// driven through App, including `app.runAlerts`, which App feeds with the run
// store's snapshotReplied, and `app.runControl`, whose requests App settles on
// each ok snapshotReplied and whose refreshRequested App routes to the run
// store. The stores' own behaviour is tested in tst_run_store.qml,
// tst_run_alerts_store.qml and tst_run_control_store.qml.
```

(b) Insert immediately before the file's final `}` (after `test_closing_the_panel_through_app_empties_run_alerts`):

```qml
  // ---- app.runControl (split-runstore 3.1)

  // A1
  function test_app_composes_run_control_wired_to_the_run_store() {
    var app = makeBare(); if (!app) return
    verify(app.runControl, "App composes the control store")
    verify(app.runs.controlStore === app.runControl, "the run store's shim handle")
    compare(app.runControl.backendDir, "/plugin/core/backend/")
    app.backendDir = "/other/"
    compare(app.runControl.backendDir, "/other/", "backendDir follows App")
    compare(app.runControl.active, false)
    app.panelOpen = true
    compare(app.runControl.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runControl.active, false)
    compare(app.runControl.project, "", "no project selected yet")
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    compare(app.runControl.project, pA.root_path, "the selected project's root path")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("r1")], []), 0)
    compare(app.runControl.runs.length, 1)
    verify(app.runControl.runs === app.runs.runs, "the run store's merged list")
  }

  // A2
  function test_a_snapshot_through_app_settles_on_run_control() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    compare(app.runControl.pending.r1, "pause")
    verify(app.runs.pending === app.runControl.pending, "the run store's shim reads the same map")
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runControl.controlRunners.length, 0)
    compare(app.runControl.pending.r1, "pause", "am has it; a snapshot settles it")
    reply(app.runs.snapshotRunner.current,
          listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: null }])], []), 0)
    compare(app.runControl.pending.r1, "pause", "not handled yet")
    snapshot(app, listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])], []))
    compare(app.runControl.pending.r1, undefined, "the handled request is settled")
    verify(app.runs.pending === app.runControl.pending)
  }

  // A3
  function test_a_control_reply_through_app_snapshots_every_root_from_run_control() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root")
  }

  // A4
  function test_a_refresh_request_for_some_roots_snapshots_only_those() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.snapshotRunner.busy, false)
    var seq = app.runs.snapshotRunner.seq
    app.runControl.refreshRequested([tc.pB.root_path])
    compare(app.runs.snapshotRunner.seq, seq + 1)
    compare(argv(app.runs.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/b", "pB alone")
  }

  // A5
  function test_only_an_ok_snapshot_through_app_settles() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    var fail = { type: "AmFailed", message: "boom" }
    reply(app.runs.snapshotRunner.current,
          JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: false, error: fail },
                                                { root: tc.pB.root_path, ok: false, error: fail }],
                           data_dir: "/home/u/.local/share" }) + "\n", 0)
    compare(app.runs.amStatus, "error")
    compare(app.runControl.pending.r1, "pause", "a failed reply settles nothing")
    snapshot(app, missingReply())
    compare(app.runs.amStatus, "missing")
    compare(app.runControl.pending.r1, "pause", "an AmMissing reply settles nothing")
    snapshot(app, listReply([], []))
    compare(app.runControl.pending.r1, undefined, "the next ok reply shows the run gone and settles it")
  }

  // A6 (Review Focus: the "all" route)
  function test_a_control_reply_with_no_project_registered_launches_no_snapshot() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    app.projects.applyProjectsList([])
    compare(app.runs.runs.length, 0, "the emptied registry emptied the lists")
    var seq = app.runs.snapshotRunner.seq
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runControl.controlRunners.length, 0)
    compare(app.runs.snapshotRunner.seq, seq, "refresh() with no usable root launches nothing")
    compare(app.runs.runs.length, 0)
  }

  // A7 (Review Focus: a failed root before an ok root)
  function test_a_reply_with_a_failed_root_before_an_ok_root_settles() {
    var app = openApp([runningIn("r1")], [runningIn("b1", tc.pB.root_path)]); if (!app) return
    compare(app.runControl.control("pause", "b1"), true)
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "b1", command: "pause", requested_at: "t1" }), 0)
    var handled = runEntry("b1", "started", true, tc.pB.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])
    reply(app.runs.snapshotRunner.current,
          JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: false, error: { type: "AmFailed", message: "boom" } },
                                                { root: tc.pB.root_path, ok: true, runs: [handled] }],
                           data_dir: "/home/u/.local/share" }) + "\n", 0)
    compare(app.runs.amStatus, "ok")
    compare(app.runControl.pending.b1, undefined, "settled on pB's ok emission")
  }
```

The existing tests `test_a_snapshot_through_app_settles_a_pending_request`, `test_a_control_reply_through_app_snapshots_every_registered_root` and `test_a_failed_control_reply_through_app_also_snapshots_every_root` stay byte-identical; they now pass through the shims and App's routes.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_run_store; timeout 900 bash tests/run.sh tst_app_runs`
Expected: FAIL — in `tst_run_store.qml`, every test built through `make()` fails with `Uncaught exception: Cannot assign to non-existent property "controlStore"` (`wireControl` assigns a handle `RunStore` does not have yet), and R1 fails on `compare(store.controlStore, null)`; in `tst_app_runs.qml`, A1-A7 fail because `app.runControl` is undefined. Both runs exit non-zero.

- [ ] **Step 4: Move the control tests into `tst_run_control_store.qml`**

In `tests/core/stores/tst_run_control_store.qml`:

(a) Find the header comment:

```qml
// tests/core/stores/tst_run_control_store.qml
// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation and the footer flash. Built alone and driven through its
// `runs` input, settleAfterSnapshot() and stubbed Process objects.
```

and replace it with:

```qml
// tests/core/stores/tst_run_control_store.qml
// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation and the footer flash. Built alone and driven through its
// `runs` input and settleAfterSnapshot(); and, through a RunStore wired to it
// the way App wires them, a real snapshot reply settling a real request.
// Stubbed Process objects stand in for every helper.
```

(b) Insert this block immediately before the file's final `}` (after `test_a_project_change_changes_nothing_here`). The 42 moved test bodies are byte-identical to their `tst_run_store.qml` originals except that every read, write or call of `pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`, `cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `flashText`, `controlRunners`, `pendingTimer`, `flashTimer`, `control`, `refusalOf`, `flash`, `openCancel`, `closeCancel`, `confirmCancel`, `dismissControlError` or `checkWaiting` on a run store goes through `controlOf(<store>)` (including the `pendingChanged` spy's target, the `tryCompare` on `flashText`, and the helper `pauseAcked`). RunStore members (`snapshotRunner`, `refresh`, `runs`, `runById`, `project`, `active`, `lastError`) stay on the store. The helpers the file already has from Task 2 (`reply`, `argv`, `entry`, `ctlEntry`, `running`, `dead`, `held`, `ctlOk`, `ctlFail`, `settingsReply`, `amRequest`, `rootA`, `rootB`, `ctlCmd`, `settingsCmd`, `noVerifySentence`) are not repeated:

```qml
  // ---- through a RunStore wired the way App wires app.runControl

  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"

  // A RunStore wired to its own RunControlStore (wireControl).
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireControl(store)
    return store
  }

  // Every {store, control} pair wireControl made.
  property var controlPairs: []

  // A RunControlStore wired to `store` the way App wires app.runControl:
  // backendDir copied; project, active and runs bound to the run store's own;
  // store.controlStore set; an ok snapshotReplied settles its requests; its
  // refreshRequested goes to refresh() ("all") or requestSnapshot(roots).
  function wireControl(store) {
    var comp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var c = comp.createObject(tc, { backendDir: store.backendDir })
    c.project = Qt.binding(function() { return store.project })
    c.active = Qt.binding(function() { return store.active })
    c.runs = Qt.binding(function() { return store.runs })
    store.controlStore = c
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
    c.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    tc.controlPairs = tc.controlPairs.concat([{ store: store, control: c }])
    return c
  }

  // The RunControlStore wireControl paired with `store`; null when none.
  function controlOf(store) {
    for (var i = 0; i < tc.controlPairs.length; i++) {
      if (tc.controlPairs[i].store === store) return tc.controlPairs[i].control
    }
    return null
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // A store with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var store = make(); if (!store) return null
    store.projectRoots = registry(roots)
    return store
  }

  // A store with one registered project, `root`, open: its first snapshot (of
  // that root alone) is in flight.
  function makeWithProject(root) {
    var store = make(); if (!store) return null
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // An active store (the panel is open) with project `root` registered and
  // open: its first snapshot is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir. The store ignores a root it has not registered.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // The next snapshot of project A lists `entries`.
  function snapshot(store, entries) {
    store.refresh()
    reply(store.snapshotRunner.current, okReply(entries), 0)
  }

  // ---- run controls (S2 4.1)

  // Project A whose first snapshot listed `entries`. Not active: no watch.
  function ctlStore(entries) {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    return store
  }

  function test_control_defaults() {
    var store = make(); if (!store) return
    compare(Object.keys(controlOf(store).pending).length, 0)
    compare(Object.keys(controlOf(store).stillWaiting).length, 0)
    compare(controlOf(store).stillWaitingText, "still waiting — the run may be between phases or dead")
    compare(controlOf(store).lastControlError, "")
    compare(controlOf(store).lastControlErrorRunId, "")
    compare(controlOf(store).controlRunners.length, 0)
  }

  function test_pause_and_cancel_launch_the_exact_argv() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    compare(controlOf(store).control("pause", "r1"), true)
    compare(controlOf(store).control("cancel", "r2"), true)
    compare(controlOf(store).controlRunners.length, 2)
    compare(controlOf(store).controlRunners[0].runId, "r1")
    compare(controlOf(store).controlRunners[0].action, "pause")
    var pause = controlOf(store).controlRunners[0].current
    compare(pause.command.length, 5)
    compare(argv(pause), tc.ctlCmd + "pause|r1|/home/u/my proj")
    compare(pause.command[4], "/home/u/my proj", "the root with a space is one argument")
    compare(pause.running, true)
    compare(pause.launchGuard, "", "no guard")
    var cancel = controlOf(store).controlRunners[1].current
    compare(cancel.command.length, 5)
    compare(argv(cancel), tc.ctlCmd + "cancel|r2|/home/u/my proj")
  }

  function test_control_sets_pending_as_a_new_object() {
    var store = ctlStore([running("r1")]); if (!store) return
    var before = controlOf(store).pending
    var spy = spyC.createObject(tc, { target: controlOf(store), signalName: "pendingChanged" })
    compare(controlOf(store).control("pause", "r1"), true)
    compare(spy.count, 1)
    compare(controlOf(store).pending.r1, "pause")
    compare(before.r1, undefined, "the old object was not changed in place")
  }

  function test_an_ok_reply_keeps_pending_and_refreshes() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).control("pause", "r1")
    var snap = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    reply(controlOf(store).controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", effective: true,
      requested_at: "t1", already_requested: false, message: "pause requested" }), 0)
    compare(controlOf(store).pending.r1, "pause", "pending until a snapshot settles it")
    compare(controlOf(store).lastControlError, "")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")
    verify(store.snapshotRunner.current !== snap)
    compare(controlOf(store).controlRunners.length, 0)
  }

  function test_an_ok_false_reply_clears_pending_and_says_why() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    controlOf(store).control("pause", "r1")
    var seq = store.snapshotRunner.seq
    var text = ctlFail("NotAcceptingError", "run r1 is in integrate")
    reply(controlOf(store).controlRunners[0].current, text, 0)
    compare(controlOf(store).pending.r1, undefined, "the buttons come back")
    compare(controlOf(store).lastControlError, Runs.controlError(JSON.parse(text)))
    compare(controlOf(store).lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(controlOf(store).lastControlErrorRunId, "r1")
    compare(store.lastError, "", "the snapshot banner is not the control error")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")

    controlOf(store).control("cancel", "r2")
    var failed = ctlFail("AmFailed", "am: database is locked")
    reply(controlOf(store).controlRunners[0].current, failed, 0)
    compare(controlOf(store).lastControlError, Runs.controlError(JSON.parse(failed)))
    verify(controlOf(store).lastControlError !== "", "AmFailed says something")
    compare(controlOf(store).lastControlErrorRunId, "r2")
  }

  function test_garbled_control_output_names_the_exit_code() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).control("cancel", "r1")
    var seq = store.snapshotRunner.seq
    reply(controlOf(store).controlRunners[0].current, "Traceback (most recent call last):\nboom\n", 1)
    compare(controlOf(store).pending.r1, undefined)
    compare(controlOf(store).lastControlError, "The run control gave no usable result (exit 1).")
    compare(controlOf(store).lastControlErrorRunId, "r1")
    compare(store.snapshotRunner.seq, seq + 1)
  }

  function test_an_unknown_run_error_survives_the_snapshot_that_drops_the_row() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    controlOf(store).control("cancel", "r1")
    reply(controlOf(store).controlRunners[0].current, ctlFail("UnknownRunError", "no run r1"), 0)
    compare(controlOf(store).lastControlError, "The run no longer exists")
    reply(store.snapshotRunner.current, okReply([running("r2")]), 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r2", "the row is dropped")
    compare(controlOf(store).lastControlError, "The run no longer exists", "a snapshot never clears the control error")
    compare(controlOf(store).lastControlErrorRunId, "r1")
    compare(store.lastError, "")
    snapshot(store, [running("r2")])
    compare(controlOf(store).lastControlError, "The run no longer exists")
    compare(store.lastError, "")
  }

  function test_control_refusals_launch_nothing() {
    var bare = make(); if (!bare) return
    compare(controlOf(bare).control("pause", "r1"), false, "a run not in the snapshot")
    compare(controlOf(bare).controlRunners.length, 0)

    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false),
                          ctlEntry("r3", "started", true, "milestone", [], false)]); if (!store) return
    compare(controlOf(store).control("stop", "r1"), false, "unknown action")
    compare(controlOf(store).control("Pause", "r1"), false, "actions are exact")
    compare(controlOf(store).control("", "r1"), false, "empty action")
    compare(controlOf(store).control("pause", ""), false, "empty id")
    compare(controlOf(store).control("pause", 7), false, "an id that is not a string")
    compare(controlOf(store).control("pause", "nope"), false, "a run not in the snapshot")
    compare(controlOf(store).control("pause", "r2"), false, "pause on a parked run is disabled")
    compare(controlOf(store).control("cancel", "r3"), false, "cancel during Integrate is disabled")
    compare(controlOf(store).control("pause", "r3"), false, "pause during Integrate is disabled")
    compare(controlOf(store).controlRunners.length, 0)
    compare(Object.keys(controlOf(store).pending).length, 0)
    compare(controlOf(store).control("pause", "r1"), true)
    compare(controlOf(store).control("pause", "r1"), false, "no double fire")
    compare(controlOf(store).control("cancel", "r1"), false, "one request per run at a time")
    compare(controlOf(store).controlRunners.length, 1)
    compare(Object.keys(controlOf(store).pending).join(","), "r1")
  }

  function test_two_runs_in_flight_at_once_both_apply() {
    var store = ctlStore([running("a"), running("b")]); if (!store) return
    controlOf(store).control("pause", "a")
    controlOf(store).control("cancel", "b")
    compare(controlOf(store).controlRunners.length, 2)
    var ra = controlOf(store).controlRunners[0], rb = controlOf(store).controlRunners[1]
    compare(ra.current.running, true, "cancelling b did not stop a's pause")
    compare(rb.current.running, true)
    reply(ra.current, ctlOk({ requested_at: "t1" }), 0)
    compare(controlOf(store).controlRunners.length, 1)
    compare(controlOf(store).controlRunners[0].runId, "b")
    compare(controlOf(store).pending.a, "pause")
    compare(controlOf(store).pending.b, "cancel")
    reply(rb.current, ctlFail("NotRunningError", "not running"), 0)
    compare(controlOf(store).controlRunners.length, 0)
    compare(controlOf(store).pending.a, "pause")
    compare(controlOf(store).pending.b, undefined)
    compare(controlOf(store).lastControlError, "The run is not running")
    compare(controlOf(store).lastControlErrorRunId, "b")
  }

  function test_a_finished_request_leaves_control_runners() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).control("pause", "r1")
    reply(controlOf(store).controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(controlOf(store).controlRunners.length, 0, "an applied reply")

    var other = ctlStore([running("r1")]); if (!other) return
    controlOf(other).control("pause", "r1")
    var proc = controlOf(other).controlRunners[0].current
    other.project = rootB
    compare(controlOf(other).controlRunners.length, 1, "a launched request still completes in am")
    var seq = other.snapshotRunner.seq
    reply(proc, ctlOk({ requested_at: "t1" }), 0)
    compare(controlOf(other).controlRunners.length, 0, "a reply after a switch is applied and removes its runner")
    compare(other.snapshotRunner.seq, seq + 1, "and re-snapshots")
  }

  function test_a_new_request_and_dismiss_clear_the_control_error() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).control("pause", "r1")
    reply(controlOf(store).controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(controlOf(store).lastControlError, "am is busy; try again in a moment")
    compare(controlOf(store).control("pause", "r1"), true, "the failed request no longer blocks the run")
    compare(controlOf(store).lastControlError, "")
    compare(controlOf(store).lastControlErrorRunId, "")
    reply(controlOf(store).controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(controlOf(store).lastControlErrorRunId, "r1")
    controlOf(store).dismissControlError()
    compare(controlOf(store).lastControlError, "")
    compare(controlOf(store).lastControlErrorRunId, "")
  }

  function test_milestone_resume_reads_the_settings_then_passes_the_verify_set() {
    var store = ctlStore([dead("r1")]); if (!store) return
    compare(controlOf(store).control("resume", "r1"), true)
    compare(controlOf(store).controlRunners.length, 1)
    var runner = controlOf(store).controlRunners[0]
    compare(argv(runner.current), tc.settingsCmd)
    compare(runner.current.command.length, 4)
    compare(controlOf(store).pending.r1, "resume")
    reply(runner.current, settingsReply(["a", "-b c"], true), 0)
    compare(controlOf(store).controlRunners.length, 1, "the same request goes on to run-control")
    var proc = controlOf(store).controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a|--verify|-b c")
    compare(proc.command.length, 9, "each verify command is one argument")
    compare(proc.command[8], "-b c")
    compare(proc.command.indexOf("--allow-no-verification"), -1, "a stored verify set wins over the opt-out")
    compare(controlOf(store).pending.r1, "resume")
  }

  function test_milestone_resume_with_the_opt_out_passes_allow_no_verification() {
    var store = ctlStore([dead("r1")]); if (!store) return
    controlOf(store).control("resume", "r1")
    reply(controlOf(store).controlRunners[0].current, settingsReply([], true), 0)
    var proc = controlOf(store).controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--allow-no-verification")
    compare(proc.command.length, 6)
  }

  function test_milestone_resume_with_nothing_stored_launches_nothing() {
    var store = ctlStore([dead("r1")]); if (!store) return
    controlOf(store).control("resume", "r1")
    var runner = controlOf(store).controlRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, settingsReply([], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(controlOf(store).controlRunners.length, 0)
    compare(Object.keys(controlOf(store).pending).length, 0)
    compare(controlOf(store).lastControlError, tc.noVerifySentence)
    compare(controlOf(store).lastControlErrorRunId, "r1")
    compare(store.snapshotRunner.seq, seq, "nothing was asked of am, so no snapshot")
  }

  function test_garbled_run_settings_end_the_resume() {
    var store = ctlStore([dead("r1")]); if (!store) return
    controlOf(store).control("resume", "r1")
    var runner = controlOf(store).controlRunners[0]
    reply(runner.current, "oops\n", 2)
    compare(runner.seq, 1, "run-control was never launched")
    compare(controlOf(store).controlRunners.length, 0)
    compare(Object.keys(controlOf(store).pending).length, 0)
    compare(controlOf(store).lastControlError, "The run settings gave no usable result (exit 2).")
    compare(controlOf(store).lastControlErrorRunId, "r1")
  }

  function test_a_card_run_resume_skips_the_settings() {
    var store = ctlStore([ctlEntry("r1", "started", false, "task"),
                          ctlEntry("r2", "started", false, "orchestrator")]); if (!store) return
    compare(controlOf(store).control("resume", "r1"), true)
    compare(controlOf(store).controlRunners.length, 1)
    var runner = controlOf(store).controlRunners[0]
    compare(runner.seq, 1, "one launch only")
    compare(argv(runner.current), tc.ctlCmd + "resume|r1|/home/u/my proj")
    compare(runner.current.command.length, 5)
    compare(controlOf(store).control("resume", "r2"), true)
    compare(argv(controlOf(store).controlRunners[1].current), tc.settingsCmd, "any workflow but task follows the milestone rule")
  }

  // Review Focus 3.
  function test_a_verify_set_with_a_non_string_is_not_used() {
    var store = ctlStore([dead("r1"), dead("r2")]); if (!store) return
    controlOf(store).control("resume", "r1")
    var runner = controlOf(store).controlRunners[0]
    reply(runner.current, settingsReply(["a", 5], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(controlOf(store).lastControlError, tc.noVerifySentence)
    controlOf(store).control("resume", "r2")
    reply(controlOf(store).controlRunners[0].current, settingsReply(["a", 5], true), 0)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "resume|r2|/home/u/my proj|--allow-no-verification")
  }

  // A pause of `id` that am acknowledged; requestedAt "" leaves it out of the reply.
  function pauseAcked(store, id, requestedAt) {
    compare(controlOf(store).control("pause", id), true)
    var data = { run_id: id, command: "pause" }
    if (requestedAt !== "") data.requested_at = requestedAt
    reply(controlOf(store).controlRunners[controlOf(store).controlRunners.length - 1].current, ctlOk(data), 0)
  }

  function test_a_pause_settles_when_its_request_is_handled() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", null)])])
    compare(controlOf(store).pending.r1, "pause", "not handled yet")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [amRequest("pause", "t0", "t0h"), amRequest("pause", "t1", "")])])
    compare(controlOf(store).pending.r1, "pause", "an older handled pause is another request")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [amRequest("pause", "t0", "t0h"), amRequest("pause", "t1", "t1h")])])
    compare(controlOf(store).pending.r1, undefined, "handled")
  }

  function test_without_requested_at_the_last_request_of_that_command_decides() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
      [amRequest("pause", "t0", "t0h"), amRequest("cancel", "t1", "t1h"), amRequest("pause", "t2", null)])])
    compare(controlOf(store).pending.r1, "pause", "the last pause is not handled; a handled cancel is another request")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
      [amRequest("pause", "t0", "t0h"), amRequest("pause", "t2", "t2h")])])
    compare(controlOf(store).pending.r1, undefined)
  }

  // Review Focus 2.
  function test_a_resume_settles_when_the_run_state_changes() {
    var store = ctlStore([dead("r1")]); if (!store) return
    controlOf(store).control("resume", "r1")
    reply(controlOf(store).controlRunners[0].current, settingsReply(["make test"], false), 0)
    reply(controlOf(store).controlRunners[0].current, ctlOk({ action: "resume", run_id: "r1", detached: true }), 0)
    compare(controlOf(store).pending.r1, "resume", "a detached resume is acknowledged, not failed")
    compare(controlOf(store).lastControlError, "")
    snapshot(store, [ctlEntry("r1", "started", false, "milestone", [amRequest("resume", "t1", "t1h")])])
    compare(controlOf(store).pending.r1, "resume", "still dead; resume never reads a request row")
    snapshot(store, [running("r1")])
    compare(controlOf(store).pending.r1, undefined, "dead -> running")
  }

  function test_a_request_settles_when_its_run_vanishes() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    snapshot(store, [running("r2")])
    compare(controlOf(store).pending.r1, undefined)
  }

  // D5.
  function test_a_snapshot_never_settles_a_request_in_flight() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).control("pause", "r1")
    var runner = controlOf(store).controlRunners[0]
    snapshot(store, [ctlEntry("r1", "stopped", false)])
    compare(controlOf(store).pending.r1, "pause", "the reply has not come back yet")
    snapshot(store, [])
    compare(controlOf(store).pending.r1, "pause", "not even when the run vanished")
    reply(runner.current, ctlOk({ requested_at: "t1" }), 0)
    compare(controlOf(store).pending.r1, "pause")
    snapshot(store, [ctlEntry("r1", "stopped", false)])
    compare(controlOf(store).pending.r1, undefined, "settled once acknowledged")
  }

  function test_a_failed_snapshot_settles_nothing() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "AmFailed", message: "boom" } }) + "\n", 0)
    compare(controlOf(store).pending.r1, "pause")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    compare(controlOf(store).pending.r1, "pause")
  }

  // Review Focus 1: A -> B -> A before the old reply lands.
  function test_a_reply_after_returning_to_the_project_is_applied() {
    var store = ctlStore([running("r1")]); if (!store) return
    controlOf(store).control("pause", "r1")
    var proc = controlOf(store).controlRunners[0].current
    store.project = rootB
    store.project = rootA
    compare(controlOf(store).pending.r1, "pause", "the request is still pending")
    compare(controlOf(store).control("pause", "r1"), false, "so the run cannot be asked again")
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotAcceptingError", "x"), 0)
    compare(controlOf(store).pending.r1, undefined, "its reply is this project's again and settles it")
    compare(controlOf(store).lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(store.snapshotRunner.seq, seq + 1, "and re-snapshots")
    compare(controlOf(store).controlRunners.length, 0)
  }

  function test_a_request_is_still_waiting_after_30_seconds() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    controlOf(store).control("pause", "r1")
    controlOf(store).checkWaiting(Date.now() + 29000)
    compare(controlOf(store).stillWaiting.r1, undefined, "29 s is not yet")
    controlOf(store).checkWaiting(Date.now() + 30000)
    compare(controlOf(store).stillWaiting.r1, true)
    compare(controlOf(store).stillWaiting.r2, undefined, "only pending runs")
    compare(controlOf(store).stillWaitingText, "still waiting — the run may be between phases or dead")
    reply(controlOf(store).controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(controlOf(store).stillWaiting.r1, true, "acknowledged but not settled: still waiting")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", "t1h")]), running("r2")])
    compare(controlOf(store).stillWaiting.r1, undefined, "settling removes it")
    compare(Object.keys(controlOf(store).stillWaiting).length, 0)
  }

  // Review Focus 5 and D6.
  function test_the_pending_timer_runs_only_while_active_with_something_pending() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(controlOf(store).pendingTimer.running, false, "nothing pending")
    compare(controlOf(store).pendingTimer.interval, 1000)
    compare(controlOf(store).pendingTimer.repeat, true)
    controlOf(store).control("pause", "r1")
    compare(controlOf(store).pendingTimer.running, true)
    controlOf(store).pendingTimer.triggered()
    compare(controlOf(store).stillWaiting.r1, undefined, "a fresh request is not waiting yet")
    store.active = false
    compare(controlOf(store).pendingTimer.running, false, "no timer while the panel is closed")
    compare(controlOf(store).pending.r1, "pause", "closing the panel keeps pending")
    compare(controlOf(store).controlRunners.length, 1, "and the request in flight")
    store.active = true
    compare(controlOf(store).pendingTimer.running, true, "reopening starts it again")
    reply(controlOf(store).controlRunners[0].current, ctlFail("NotRunningError", "x"), 0)
    compare(controlOf(store).pendingTimer.running, false, "nothing pending any more")

    var idle = ctlStore([running("r1")]); if (!idle) return
    controlOf(idle).control("pause", "r1")
    compare(controlOf(idle).pendingTimer.running, false, "an inactive store runs no timer")
  }

  // ---- cancel confirmation and the footer flash (S2 4.3)

  property string integrateReason: "Integrate is running; it cannot be paused or cancelled"

  // A running run whose lease is not accepting requests: am is in Integrate.
  function integrate(id) { return ctlEntry(id, "started", true, "milestone", [], false) }

  // 1 (and Review Focus 4)
  function test_refusal_of_says_why_a_control_would_not_start() {
    var bare = make(); if (!bare) return
    compare(controlOf(bare).refusalOf("pause", "r1"), "This run is no longer in the snapshot", "not in the snapshot")
    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false), integrate("r3"),
                          ctlEntry("r4", "done", false), running("r5"), running("constructor")]); if (!store) return
    compare(controlOf(store).refusalOf("pause", "r1"), "")
    compare(controlOf(store).refusalOf("cancel", "r1"), "")
    compare(controlOf(store).refusalOf("resume", "r2"), "")
    compare(controlOf(store).refusalOf("cancel", "r2"), "")
    compare(controlOf(store).refusalOf("pause", "nope"), "This run is no longer in the snapshot")
    compare(controlOf(store).refusalOf("pause", ""), "This run is no longer in the snapshot")
    compare(controlOf(store).refusalOf("pause", "r3"), tc.integrateReason)
    compare(controlOf(store).refusalOf("cancel", "r3"), tc.integrateReason)
    compare(controlOf(store).refusalOf("cancel", "r4"), "The run has finished")
    compare(controlOf(store).refusalOf("resume", "r1"), "The run is still running")
    compare(controlOf(store).refusalOf("bogus", "r1"), "Unknown control")
    compare(controlOf(store).refusalOf("pause", "constructor"), "", "an id like constructor is not pending")
    compare(controlOf(store).refusalOf("resume", "constructor"), "The run is still running")
    compare(controlOf(store).control("pause", "r5"), true)
    compare(controlOf(store).refusalOf("pause", "r5"), "A request for this run is pending")
    compare(controlOf(store).refusalOf("resume", "r5"), "A request for this run is pending", "pending wins over the state's reason")
    compare(controlOf(store).controlRunners.length, 1, "refusalOf starts nothing")
  }

  // 2
  function test_a_flash_clears_itself_and_a_new_one_restarts_the_clock() {
    var store = make(); if (!store) return
    compare(controlOf(store).flashText, "")
    compare(controlOf(store).flashTimer.interval, 3000)
    compare(controlOf(store).flashTimer.repeat, false)
    compare(controlOf(store).flashTimer.running, false)
    controlOf(store).flashTimer.interval = 500
    controlOf(store).flash("first")
    compare(controlOf(store).flashText, "first")
    compare(controlOf(store).flashTimer.running, true)
    wait(300)
    controlOf(store).flash("second")
    compare(controlOf(store).flashText, "second", "the new text replaces the old")
    wait(300)
    compare(controlOf(store).flashText, "second", "the clock restarted with the second flash")
    tryCompare(controlOf(store), "flashText", "", 2000)
    compare(controlOf(store).flashTimer.running, false)
    controlOf(store).flash("third")
    controlOf(store).flash("")
    compare(controlOf(store).flashText, "")
    compare(controlOf(store).flashTimer.running, false, "flash(\"\") stops the clock")
  }

  // 3
  function test_open_cancel_opens_only_for_a_cancellable_run() {
    var store = ctlStore([running("r1"), integrate("r3")]); if (!store) return
    compare(controlOf(store).cancelOpen, false)
    compare(controlOf(store).cancelRunId, "")
    compare(controlOf(store).cancelText, "")
    compare(controlOf(store).cancelError, "")
    controlOf(store).cancelText = "left over"
    controlOf(store).cancelError = "old"
    compare(controlOf(store).openCancel("r1"), true)
    compare(controlOf(store).cancelOpen, true)
    compare(controlOf(store).cancelRunId, "r1")
    compare(controlOf(store).cancelText, "", "the dialog opens empty")
    compare(controlOf(store).cancelError, "")
    compare(controlOf(store).flashText, "")
    controlOf(store).closeCancel()
    compare(controlOf(store).cancelOpen, false)
    compare(controlOf(store).openCancel("r3"), false)
    compare(controlOf(store).cancelOpen, false, "an Integrate run gets no dialog")
    compare(controlOf(store).flashText, tc.integrateReason)
    compare(controlOf(store).controlRunners.length, 0)
  }

  // 4 (and Review Focus 1)
  function test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes() {
    var store = ctlStore([running("r1")]); if (!store) return
    compare(controlOf(store).confirmCancel(), false, "nothing is open")
    controlOf(store).openCancel("r1")
    controlOf(store).cancelText = "cancle"
    compare(controlOf(store).confirmCancel(), false)
    compare(controlOf(store).controlRunners.length, 0)
    compare(controlOf(store).cancelOpen, true)
    compare(controlOf(store).cancelError, "", "a wrong word is not an error")
    controlOf(store).cancelText = " Cancel "
    compare(controlOf(store).confirmCancel(), true)
    compare(controlOf(store).pending.r1, "cancel")
    compare(controlOf(store).controlRunners.length, 1)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "cancel|r1|/home/u/my proj")
    compare(controlOf(store).cancelOpen, false)
    compare(controlOf(store).cancelRunId, "")
    compare(controlOf(store).cancelText, "")
    compare(controlOf(store).cancelError, "")
    compare(controlOf(store).confirmCancel(), false, "a second confirm finds the dialog closed")
    compare(controlOf(store).controlRunners.length, 1)
  }

  // 5 (D6, Review Focus 2)
  function test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    controlOf(store).openCancel("r2")
    controlOf(store).cancelText = "cancel"
    controlOf(store).control("pause", "r2")
    compare(controlOf(store).confirmCancel(), false)
    compare(controlOf(store).cancelError, "A request for this run is pending")
    compare(controlOf(store).cancelOpen, true)
    compare(controlOf(store).controlRunners.length, 1, "only the pause")
    controlOf(store).closeCancel()

    controlOf(store).openCancel("r1")
    controlOf(store).cancelText = "cancel"
    snapshot(store, [ctlEntry("r1", "done", false)])
    compare(controlOf(store).confirmCancel(), false)
    compare(controlOf(store).cancelError, "The run has finished")
    compare(controlOf(store).cancelOpen, true, "the dialog stays for the user to read why")
    compare(controlOf(store).cancelRunId, "r1")
    compare(controlOf(store).pending.r1, undefined)
    snapshot(store, [])
    compare(controlOf(store).confirmCancel(), false)
    compare(controlOf(store).cancelError, "This run is no longer in the snapshot")
    compare(controlOf(store).cancelOpen, true)
    compare(controlOf(store).controlRunners.length, 1, "no cancel was ever launched")
  }

  // ---- control for a run of any project (3.5)

  property string bRepo: "/home/u/b-work"
  property string settingsCmdB: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/b"

  // `e` with its repo_dir moved to bRepo: a run of rootB whose repository is
  // not the registry root (the store tags it by the entry's root).
  function bWork(e) {
    e.repo_dir = tc.bRepo
    return e
  }

  // rootA and rootB registered, `open` the open project ("" for none), and
  // the first snapshot listed aRuns under A and bRuns under B.
  function crossStore(open, aRuns, bRuns) {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    store.project = open
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, aRuns), okEntry(tc.rootB, bRuns)]), 0)
    return store
  }

  // 1
  function test_pause_and_cancel_pass_the_runs_repo_dir_with_or_without_a_project() {
    var store = crossStore("", [running("a1")], [bWork(running("b1")), bWork(running("b2"))]); if (!store) return
    compare(store.project, "")
    compare(controlOf(store).control("pause", "b1"), true, "no project open is not a refusal")
    var pause = controlOf(store).controlRunners[0].current
    compare(argv(pause), tc.ctlCmd + "pause|b1|/home/u/b-work")
    compare(pause.command.length, 5)
    compare(pause.launchGuard, "", "no guard")
    compare(controlOf(store).control("cancel", "a1"), true)
    compare(argv(controlOf(store).controlRunners[1].current), tc.ctlCmd + "cancel|a1|/home/u/my proj")
    store.project = rootA
    compare(controlOf(store).control("pause", "b2"), true)
    compare(argv(controlOf(store).controlRunners[2].current), tc.ctlCmd + "pause|b2|/home/u/b-work", "never the open project's root")
  }

  // 2
  function test_a_task_runs_resume_passes_its_repo_dir_with_no_settings_step() {
    var store = crossStore(rootA, [running("a1")], [bWork(ctlEntry("b1", "started", false, "task"))]); if (!store) return
    compare(controlOf(store).control("resume", "b1"), true)
    var runner = controlOf(store).controlRunners[0]
    compare(runner.seq, 1, "one launch only")
    compare(argv(runner.current), tc.ctlCmd + "resume|b1|/home/u/b-work")
    compare(runner.current.command.length, 5)
  }

  // 3
  function test_a_milestone_resume_reads_its_own_projects_settings() {
    var store = crossStore(rootA, [running("a1")], [bWork(dead("b1"))]); if (!store) return
    compare(controlOf(store).control("resume", "b1"), true)
    var runner = controlOf(store).controlRunners[0]
    compare(argv(runner.current), tc.settingsCmdB, "B's run settings, not A's")
    compare(runner.current.command.length, 4)
    compare(runner.current.launchGuard, "")
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "resume|b1|/home/u/b-work|--verify|a")
  }

  // 4
  function test_the_resume_keeps_the_repository_it_was_asked_for() {
    var store = crossStore(rootA, [running("a1")], [bWork(dead("b1"))]); if (!store) return
    controlOf(store).control("resume", "b1")
    var runner = controlOf(store).controlRunners[0]
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [])]), 0)
    compare(store.runById("b1"), null, "the run left the snapshot")
    compare(controlOf(store).pending.b1, "resume", "a request in flight is never settled by a snapshot")
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "resume|b1|/home/u/b-work|--verify|a")
    compare(controlOf(store).pending.b1, "resume")
  }

  // 5
  function test_a_run_with_no_repository_or_no_project_root_is_refused() {
    var store = make(); if (!store) return
    var noRepo = held(running("r1"), rootA)
    noRepo.repo_dir = ""
    store.runs = [noRepo, held(dead("r2")), held(ctlEntry("r3", "started", false, "task"))]
    var actions = ["pause", "resume", "cancel"]
    for (var i = 0; i < actions.length; i++) {
      compare(controlOf(store).refusalOf(actions[i], "r1"), "This run has no repository", actions[i])
      compare(controlOf(store).control(actions[i], "r1"), false, actions[i])
    }
    compare(controlOf(store).refusalOf("resume", "r2"), "This run's project is not known")
    compare(controlOf(store).control("resume", "r2"), false)
    compare(controlOf(store).controlRunners.length, 0, "nothing launched")
    compare(Object.keys(controlOf(store).pending).length, 0)
    compare(controlOf(store).refusalOf("cancel", "r2"), "", "a cancel needs no project root")
    compare(controlOf(store).control("cancel", "r2"), true)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "cancel|r2|/home/u/my proj")
    compare(controlOf(store).refusalOf("resume", "r3"), "", "a task run's resume needs no project root")
    compare(controlOf(store).control("resume", "r3"), true)
    compare(argv(controlOf(store).controlRunners[1].current), tc.ctlCmd + "resume|r3|/home/u/my proj")
    compare(controlOf(store).controlRunners[1].seq, 1)
    compare(controlOf(store).controlRunners.length, 2)
  }

  // 6
  function test_a_request_for_another_projects_run_survives_a_switch_and_its_reply_shows_on_that_run() {
    var store = crossStore(rootA, [running("a1")],
                           [bWork(running("b1")), bWork(running("b2")), bWork(dead("b3"))]); if (!store) return
    compare(controlOf(store).control("pause", "b1"), true)
    var proc = controlOf(store).controlRunners[0].current
    store.project = rootB
    store.project = ""
    compare(controlOf(store).pending.b1, "pause", "a switch settles nothing")
    compare(controlOf(store).controlRunners.length, 1)
    var seq = store.snapshotRunner.seq
    reply(proc, ctlOk({ requested_at: "t1" }), 0)
    compare(controlOf(store).pending.b1, "pause", "acknowledged: pending until a snapshot settles it")
    compare(store.snapshotRunner.seq, seq + 1, "and re-snapshots")
    compare(controlOf(store).controlRunners.length, 0)

    compare(controlOf(store).control("pause", "b2"), true)
    var proc2 = controlOf(store).controlRunners[0].current
    store.project = rootA
    reply(proc2, ctlFail("NotRunningError", "not running"), 0)
    compare(controlOf(store).pending.b2, undefined)
    compare(controlOf(store).lastControlError, "The run is not running")
    compare(controlOf(store).lastControlErrorRunId, "b2", "the error shows on that run")

    compare(controlOf(store).control("resume", "b3"), true)
    var runner = controlOf(store).controlRunners[0]
    store.project = rootB
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "resume|b3|/home/u/b-work|--verify|a",
            "the settings reply after a switch launches run-control")
  }

  // Review Focus 5.
  function test_a_request_made_with_no_project_open_is_answered_after_one_opens() {
    var store = crossStore("", [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(controlOf(store).control("pause", "b1"), true)
    var proc = controlOf(store).controlRunners[0].current
    store.project = rootA
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotRunningError", "not running"), 0)
    compare(controlOf(store).pending.b1, undefined)
    compare(controlOf(store).lastControlError, "The run is not running")
    compare(controlOf(store).lastControlErrorRunId, "b1")
    compare(store.snapshotRunner.seq, seq + 1)
  }

  // A control reply re-snapshots every usable root, not only the run's.
  function test_a_control_reply_refreshes_every_usable_root() {
    var store = crossStore(rootA, [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(controlOf(store).control("pause", "a1"), true)
    var seq = store.snapshotRunner.seq
    reply(controlOf(store).controlRunners[0].current, ctlOk({ run_id: "a1", command: "pause", requested_at: "t1" }), 0)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // Review Focus 2.
  function test_open_cancel_on_a_run_with_no_repository_flashes_why() {
    var store = make(); if (!store) return
    var run = held(running("r1"), rootA)
    run.repo_dir = ""
    store.runs = [run]
    compare(controlOf(store).openCancel("r1"), false)
    compare(controlOf(store).cancelOpen, false)
    compare(controlOf(store).flashText, "This run has no repository")
    compare(controlOf(store).controlRunners.length, 0)
  }

  // 7
  function test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests() {
    var store = ctlStore([running("r1"), running("r2"), running("r3")]); if (!store) return
    controlOf(store).control("pause", "r3")
    controlOf(store).control("pause", "r2")
    reply(controlOf(store).controlRunners[1].current, ctlFail("NotRunningError", "not running"), 0)
    compare(controlOf(store).lastControlErrorRunId, "r2")
    controlOf(store).checkWaiting(Date.now() + 30000)
    compare(controlOf(store).stillWaiting.r3, true)
    controlOf(store).openCancel("r1")
    controlOf(store).cancelText = "can"
    controlOf(store).cancelError = "x"
    controlOf(store).flash("The run has finished")
    store.project = rootB
    compare(controlOf(store).cancelOpen, true)
    compare(controlOf(store).cancelRunId, "r1")
    compare(controlOf(store).cancelText, "can")
    compare(controlOf(store).cancelError, "x")
    compare(controlOf(store).flashText, "The run has finished")
    compare(controlOf(store).flashTimer.running, true)
    compare(controlOf(store).lastControlError, "The run is not running")
    compare(controlOf(store).lastControlErrorRunId, "r2")
    compare(controlOf(store).pending.r3, "pause")
    compare(controlOf(store).stillWaiting.r3, true)
    compare(controlOf(store).controlRunners.length, 1)
    compare(controlOf(store).controlRunners[0].runId, "r3")
  }

  // Review Focus 1.
  function test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms() {
    var store = crossStore(rootA, [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(controlOf(store).openCancel("b1"), true)
    store.project = ""
    compare(controlOf(store).cancelRunId, "b1", "the dialog is kept")
    controlOf(store).cancelText = "cancel"
    compare(controlOf(store).confirmCancel(), true)
    compare(argv(controlOf(store).controlRunners[0].current), tc.ctlCmd + "cancel|b1|/home/u/b-work")
    compare(controlOf(store).cancelOpen, false)
  }
```

(The file must end with the TestCase's closing `}` on its own line after `test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms`.)

Check the result:

Run: `grep -c "function test_" tests/core/stores/tst_run_control_store.qml`
Expected: `50` (8 from Task 2 + 42 moved).

- [ ] **Step 5: Remove the moved tests from `tst_run_store.qml`**

Save this script as `/tmp/remove_control_tests.py` (outside the repository; do not commit it) and run it from the worktree root with `python3 /tmp/remove_control_tests.py`:

```python
# Removes the control tests and the helpers only they use from tst_run_store.qml.
SRC = "tests/core/stores/tst_run_store.qml"
MOVED = [
    "test_control_defaults",
    "test_pause_and_cancel_launch_the_exact_argv",
    "test_control_sets_pending_as_a_new_object",
    "test_an_ok_reply_keeps_pending_and_refreshes",
    "test_an_ok_false_reply_clears_pending_and_says_why",
    "test_garbled_control_output_names_the_exit_code",
    "test_an_unknown_run_error_survives_the_snapshot_that_drops_the_row",
    "test_control_refusals_launch_nothing",
    "test_two_runs_in_flight_at_once_both_apply",
    "test_a_finished_request_leaves_control_runners",
    "test_a_new_request_and_dismiss_clear_the_control_error",
    "test_milestone_resume_reads_the_settings_then_passes_the_verify_set",
    "test_milestone_resume_with_the_opt_out_passes_allow_no_verification",
    "test_milestone_resume_with_nothing_stored_launches_nothing",
    "test_garbled_run_settings_end_the_resume",
    "test_a_card_run_resume_skips_the_settings",
    "test_a_verify_set_with_a_non_string_is_not_used",
    "test_a_pause_settles_when_its_request_is_handled",
    "test_without_requested_at_the_last_request_of_that_command_decides",
    "test_a_resume_settles_when_the_run_state_changes",
    "test_a_request_settles_when_its_run_vanishes",
    "test_a_snapshot_never_settles_a_request_in_flight",
    "test_a_failed_snapshot_settles_nothing",
    "test_a_reply_after_returning_to_the_project_is_applied",
    "test_a_request_is_still_waiting_after_30_seconds",
    "test_the_pending_timer_runs_only_while_active_with_something_pending",
    "test_refusal_of_says_why_a_control_would_not_start",
    "test_a_flash_clears_itself_and_a_new_one_restarts_the_clock",
    "test_open_cancel_opens_only_for_a_cancellable_run",
    "test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes",
    "test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm",
    "test_pause_and_cancel_pass_the_runs_repo_dir_with_or_without_a_project",
    "test_a_task_runs_resume_passes_its_repo_dir_with_no_settings_step",
    "test_a_milestone_resume_reads_its_own_projects_settings",
    "test_the_resume_keeps_the_repository_it_was_asked_for",
    "test_a_run_with_no_repository_or_no_project_root_is_refused",
    "test_a_request_for_another_projects_run_survives_a_switch_and_its_reply_shows_on_that_run",
    "test_a_request_made_with_no_project_open_is_answered_after_one_opens",
    "test_a_control_reply_refreshes_every_usable_root",
    "test_open_cancel_on_a_run_with_no_repository_flashes_why",
    "test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests",
    "test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms",
    "ctlStore",
    "settingsReply",
    "amRequest",
    "pauseAcked",
    "integrate",
    "bWork",
]
LINES = [
    '  property string ctlCmd: "python3|/plugin/core/backend/runs/run-control.py|"',
    '  property string settingsCmd: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/my proj"',
    '  property string noVerifySentence: "Resume needs verify commands: none are stored for this project, and running without verification was not chosen."',
    "  // ---- cancel confirmation and the footer flash (S2 4.3)",
    '  property string integrateReason: "Integrate is running; it cannot be paused or cancelled"',
    '  property string bRepo: "/home/u/b-work"',
    '  property string settingsCmdB: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/b"',
]
HEADERS = {
    "  // ---- run controls (S2 4.1)":
        "  // ---- run controls (S2 4.1): the helpers the tests here share; the control tests are in tst_run_control_store.qml",
    "  // ---- control and logs for a run of any project (3.5)":
        "  // ---- logs for a run of any project (3.5); its control tests are in tst_run_control_store.qml",
}


def block(lines, name):
    """(start, end) of `  function name(` with the comment lines right above it; end exclusive."""
    idx = [i for i, l in enumerate(lines) if l.startswith("  function " + name + "(")]
    assert len(idx) == 1, (name, idx)
    i = idx[0]
    start = i
    while start > 0 and lines[start - 1].startswith("  //") and not lines[start - 1].startswith("  // ----"):
        start -= 1
    if lines[i].rstrip().endswith("}") and lines[i].count("{") == lines[i].count("}"):
        return start, i + 1
    end = i + 1
    while lines[end] != "  }":
        end += 1
    return start, end + 1


def cut(lines, start, end):
    if end < len(lines) and lines[end] == "":
        end += 1
    del lines[start:end]


lines = open(SRC).read().split("\n")
for name in MOVED:
    cut(lines, *block(lines, name))
for exact in LINES:
    i = lines.index(exact)
    cut(lines, i, i + 1)
for old, new in HEADERS.items():
    lines[lines.index(old)] = new
open(SRC, "w").write("\n".join(lines))
```

It deletes the 42 moved tests (the whole `// ---- run controls (S2 4.1)` and `// ---- cancel confirmation and the footer flash (S2 4.3)` test blocks, and the eleven control tests of `// ---- control and logs for a run of any project (3.5)`) and the helpers only they use (`ctlCmd`, `ctlStore`, `settingsCmd`, `noVerifySentence`, `settingsReply`, `amRequest`, `pauseAcked`, `integrateReason`, `integrate`, `bRepo`, `settingsCmdB`, `bWork`). It keeps `ctlEntry`, `running`, `dead`, `ctlOk`, `ctlFail` (used by `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone`, `test_a_nudge_refresh_that_moves_the_run_settles_its_pending_request` and the dispatch tests), `held` and `crossStore` (used by the four logs tests of the 3.5 section). Check the result:

Run: `grep -c "function test_" tests/core/stores/tst_run_store.qml`
Expected: `253` (291 before this card, + 4 from Step 1, − 42 moved).

Run: `grep -nE "ctlStore|pauseAcked|amRequest|settingsReply|noVerifySentence|integrateReason|settingsCmdB|bWork\(|integrate\(" tests/core/stores/tst_run_store.qml`
Expected: no output.

- [ ] **Step 6: Replace RunStore's control members with the shims**

Save this script as `/tmp/edit_run_store.py` (outside the repository; do not commit it) and run it from the worktree root with `python3 /tmp/edit_run_store.py`. Every `rep` asserts its text occurs exactly once, so a mismatch stops the script before it writes:

```python
SRC = "core/stores/RunStore.qml"
s = open(SRC).read()


def rep(old, new):
    global s
    assert s.count(old) == 1, old[:100]
    s = s.replace(old, new)


def cut_between(start_marker, end_marker):
    """Deletes from the line that starts with start_marker up to (not including) end_marker."""
    global s
    a = s.index(start_marker)
    b = s.index(end_marker, a)
    s = s[:a] + s[b:]


# The header: the control sentence goes.
rep("""// Pause, resume and cancel (control()) each get a HelperRunner of their own.
""", "")

# The state and the shims.
rep("""  // Run controls (S2 4.1). `pending` holds the requests not yet settled,
  // {runId: action}; `stillWaiting` the pending ones 30 s or more old,
  // {runId: true}. Both are replaced, never changed in place, so bindings see
  // every change. The control error is its own pair of fields: a snapshot never
  // touches it, and the snapshot's lastError never carries a control refusal.
  property var pending: ({})
  property var stillWaiting: ({})
  readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about

  // The cancel confirmation (S2 4.3). Panel renders it; the store keeps the
  // run it asks about ("" = closed), the typed word and why the last confirm
  // was refused.
  property string cancelRunId: ""
  readonly property bool cancelOpen: store.cancelRunId !== ""
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""

""", """  // Moved to RunControlStore; removed by the last story
  property var controlStore: null
  readonly property var pending: store.controlStore ? store.controlStore.pending : ({})
  readonly property var stillWaiting: store.controlStore ? store.controlStore.stillWaiting : ({})
  readonly property string stillWaitingText: store.controlStore ? store.controlStore.stillWaitingText : ""
  readonly property string lastControlError: store.controlStore ? store.controlStore.lastControlError : ""
  readonly property string lastControlErrorRunId: store.controlStore ? store.controlStore.lastControlErrorRunId : ""
  property string cancelRunId: ""
  Binding { target: store; property: "cancelRunId"; value: store.controlStore ? store.controlStore.cancelRunId : "" }
  onCancelRunIdChanged: {
    var target = store.controlStore ? store.controlStore.cancelRunId : ""
    if (store.cancelRunId === target) return
    if (store.controlStore) store.controlStore.cancelRunId = store.cancelRunId
    else store.cancelRunId = ""
  }
  readonly property bool cancelOpen: store.controlStore ? store.controlStore.cancelOpen : false
  property string cancelText: ""
  Binding { target: store; property: "cancelText"; value: store.controlStore ? store.controlStore.cancelText : "" }
  onCancelTextChanged: {
    var target = store.controlStore ? store.controlStore.cancelText : ""
    if (store.cancelText === target) return
    if (store.controlStore) store.controlStore.cancelText = store.cancelText
    else store.cancelText = ""
  }
  readonly property string cancelError: store.controlStore ? store.controlStore.cancelError : ""
  readonly property string flashText: store.controlStore ? store.controlStore.flashText : ""
  readonly property var controlRunners: store.controlStore ? store.controlStore.controlRunners : []
  readonly property var pendingTimer: store.controlStore ? store.controlStore.pendingTimer : null
  readonly property var flashTimer: store.controlStore ? store.controlStore.flashTimer : null
  function control(action, runId) { return store.controlStore ? store.controlStore.control(action, runId) : undefined }
  function refusalOf(action, runId) { return store.controlStore ? store.controlStore.refusalOf(action, runId) : undefined }
  function flash(text) { return store.controlStore ? store.controlStore.flash(text) : undefined }
  function openCancel(runId) { return store.controlStore ? store.controlStore.openCancel(runId) : undefined }
  function closeCancel() { return store.controlStore ? store.controlStore.closeCancel() : undefined }
  function confirmCancel() { return store.controlStore ? store.controlStore.confirmCancel() : undefined }

""")

# The aliases.
rep("""  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer
""", "")

# projectSwitched's comment.
rep("""  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage, the requests (pending, stillWaiting,
  // controlRunners), the control error, the cancel dialog, the footer flash
  // and the notify switch belong to every registered project and stay, and
  // no snapshot is launched. Reset: the run settings""",
"""  // Another project was opened, or none. The run list, the selection, the
  // logs, the watch, the coverage and the notify switch belong to every
  // registered project and stay, and no snapshot is launched. Reset: the run settings""")

# applyProjects no longer settles.
rep("""    store.settleAfterSnapshot()
    store.logsAfterSnapshot()""", """    store.logsAfterSnapshot()""")

# The two control sections, whole.
cut_between("  // ---- run controls (S2 4.1)\n", "  // ---- the notify switch (S2 4.4)\n")

# The timers, the bookkeeping and the runner component.
rep("""  // Only while the panel is open and a control request is pending: closing the
  // panel keeps `pending` but leaves no timer running.
  Timer {
    id: pendingTimer
    objectName: "pendingTimer"
    interval: 1000
    repeat: true
    running: store.active && Object.keys(store.pending).length > 0
    onTriggered: store.checkWaiting(Date.now())
  }

  // Clears the footer flash 3 s after the last flash().
  Timer {
    id: flashTimer
    objectName: "flashTimer"
    interval: 3000
    repeat: false
    onTriggered: store.flashText = ""
  }

""", "")
rep("""  // The control requests' own state; kept apart so consumers cannot write it.
  // `requests` is {runId: {token, action, baseline, launchedMs, acknowledged,
  // requestedAt}}: the run's state when the request started, when it started,
  // whether am acknowledged it, and the requested_at am gave it.
  QtObject {
    id: controlState
    property var runners: []
    property var requests: ({})
    property int nextToken: 0
  }

""", "")
cut_between("  // One HelperRunner per control request, so requests for different runs never\n",
            "  // One HelperRunner per Start.")

open(SRC, "w").write(s)
```

The shims land right above the existing `// Moved to RunAlertsStore; removed by the last story` block. `runById` and `runRoot` stay `RunStore` members (the logs and the dispatch use them). Check the result:

Run: `grep -nE "controlState|controlC|settleAfterSnapshot|checkWaiting|controlReplied|resumeWithSettings|isHandled|launchControl|requestOf|failControl|dismissControlError|dropRunner\(" core/stores/RunStore.qml`
Expected: no output.

Run: `grep -n "store.flash(" core/stores/RunStore.qml`
Expected: two lines — `notifySaveReplied`'s and `dispatchSaveReplied`'s; both now go through the `flash` shim.

- [ ] **Step 7: Compose and route in App**

In `core/stores/App.qml`:

(a) Find:

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object), the panel-open flag that starts and
  // stops its watch, and the alerts store its shims read (alertsStore).
```

and replace it with:

```qml
  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object), the panel-open flag that starts and
  // stops its watch, and the stores its shims read (controlStore,
  // alertsStore).
```

(b) Find:

```qml
    alertsStore: app.runAlerts
```

and replace it with:

```qml
    alertsStore: app.runAlerts
    controlStore: app.runControl
```

(c) Find:

```qml
    onSnapshotReplied: function(root, outcome, previousRuns, runs) {
      app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs)
    }
  }
```

and replace it with:

```qml
    onSnapshotReplied: function(root, outcome, previousRuns, runs) {
      if (outcome === "ok") app.runControl.settleAfterSnapshot()
      app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs)
    }
  }

  // The run controls never import the run store: App hands them the backend
  // directory, the open project's root, the panel-open flag and the run list,
  // settles their requests on each ok snapshot reply and routes their
  // refreshRequested to the run store.
  readonly property RunControlStore runControl: RunControlStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
  }
```

`"all"` goes to `refresh()`, not `requestSnapshot("all")`: that is the exact call `controlReplied` made, including `refresh()`'s empty-registry branch.

- [ ] **Step 8: Run the four store test files**

Run: `timeout 900 bash tests/run.sh core/stores/tst_run; timeout 900 bash tests/run.sh tst_app_runs`
Expected: PASS — `tst_run_alerts_store.qml` `Totals: 38 passed, 0 failed`; `tst_run_control_store.qml` `Totals: 52 passed, 0 failed`; `tst_run_store.qml` `Totals: 255 passed, 0 failed`; `tst_app_runs.qml` `Totals: 37 passed, 0 failed`; no `TypeError` line; both runs exit 0.

- [ ] **Step 9: Run the whole suite**

Run: `timeout 900 bash tests/run.sh`
Expected: PASS — pytest green (including `tests/architecture`), every QML file `0 failed`, `tests/ui/**` untouched and green; exit 0.

Run: `git status --short tests/ui ui`
Expected: no output (nothing under `ui/` or `tests/ui/` changed).

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml core/stores/App.qml tests/core/stores/tst_run_store.qml tests/core/stores/tst_run_control_store.qml tests/core/stores/tst_app_runs.qml
git commit -m "refactor(runs): controls move to RunControlStore, RunStore keeps shims, App settles and routes refreshRequested"
```

---

### Task 4: `docs/architecture.md`

**Files:**
- Modify: `docs/architecture.md` (the `RunStore.qml` bullet's lines 88 and 91; a new `RunControlStore.qml` bullet before `RunAlertsStore.qml`'s; the refresh-model line ~172)

**Interfaces:**
- Consumes: the members and routes of Tasks 2 and 3, as named there.
- Produces: nothing code reads.

- [ ] **Step 1: Apply the edit**

Save this script as `/tmp/edit_docs.py` (outside the repository; do not commit it) and run it from the worktree root with `python3 /tmp/edit_docs.py`. It moves the run-controls text (from `control(action, runId)` to `a project switch keeps the dialog and the flash.`) out of the `RunStore.qml` bullet into a new `RunControlStore.qml` bullet, rewriting its two sentences about the snapshot and the re-snapshot, puts a shim sentence in its place, drops "settles controls" from the snapshot sentence, and names `pendingTimer` in the refresh model:

```python
SRC = "docs/architecture.md"
s = open(SRC).read()


def rep(old, new):
    global s
    assert s.count(old) == 1, old[:100]
    s = s.replace(old, new)


start = "  Run controls (S2 4.1): `control(action, runId)` starts"
end = "a project switch keeps the dialog and the flash. "
a = s.index(start)
b = s.index(end, a) + len(end)
moved = s[a + len("  Run controls (S2 4.1): "):b - 1]
s = s[:a] + ("  Run controls, the cancel confirmation and the footer flash (S2 4.1, 4.3) are `RunControlStore`'s. "
             "`RunStore` keeps `pending`, `stillWaiting`, `stillWaitingText`, `lastControlError`, `lastControlErrorRunId`, "
             "`cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `flashText`, `controlRunners`, `pendingTimer`, "
             "`flashTimer`, `control`, `refusalOf`, `flash`, `openCancel`, `closeCancel` and `confirmCancel` as shims "
             "through `controlStore` (the handle App sets; without one they are empty and do nothing) until the last "
             "story of the split removes them: each property follows the control store's, `cancelText` and "
             "`cancelRunId` are writable (a write goes to the control store, and the shim then follows it again), and "
             "each function forwards and returns the control store's result. A snapshot settles requests only through "
             "App's `snapshotReplied` route; `RunStore` never settles one itself. ") + s[b:]

for old, new in [
    ("Every control reply re-snapshots.",
     "Every applied control reply emits `refreshRequested(\"all\")` once, after its runner is dropped; a reply to a "
     "request no longer pending, a resume's settings step and a failed settings step emit nothing."),
    ("holds from the launch until a snapshot after am's `ok: true` reply shows the run gone,",
     "holds from the launch until a `settleAfterSnapshot()` after am's `ok: true` reply finds the run gone from `runs`,"),
]:
    assert moved.count(old) == 1, old
    moved = moved.replace(old, new)

bullet = ("- `RunControlStore.qml` the run controls (S2 4.1), the cancel confirmation (S2 4.3) and the footer flash, for a "
          "run of any registered project. It never reaches for another store: `App` composes it as `app.runControl` and "
          "hands it `backendDir`, `project` (`app.runs.project`; a change of it changes nothing here), `active` (App's "
          "`panelOpen`) and `runs` (`app.runs.runs`), calls its `settleAfterSnapshot()` on each "
          "`app.runs.snapshotReplied` whose outcome is `ok`, before the alerts, and routes its "
          "`refreshRequested(roots)` to the run store: `\"all\"` to `refresh()`, a list of roots to "
          "`requestSnapshot(roots)`. " + moved + "\n")
rep("- `RunAlertsStore.qml` the run toasts,", bullet + "- `RunAlertsStore.qml` the run toasts,")

rep("Only a reply with an ok entry settles controls and refreshes logs and,",
    "Only a reply with an ok entry refreshes logs and,")
rep("and `RunAlertsStore`'s toast expiry (`toastTimer`, only while a toast shows), run only while the panel is open",
    "`RunControlStore`'s still-waiting clock (`pendingTimer`, only while a request is pending) and `RunAlertsStore`'s "
    "toast expiry (`toastTimer`, only while a toast shows), run only while the panel is open")
open(SRC, "w").write(s)
```

- [ ] **Step 2: Verify the docs match the code**

Run: `grep -c "RunControlStore" docs/architecture.md`
Expected: `3` or more (the RunStore bullet's shim sentence, the new bullet, the refresh model).

Run: `grep -n "settles controls\|Every control reply re-snapshots" docs/architecture.md`
Expected: no output.

Read the new `RunControlStore.qml` bullet and check each name it uses against `core/stores/RunControlStore.qml`: `backendDir`, `project`, `active`, `runs`, `settleAfterSnapshot`, `refreshRequested`, `control`, `controlRunners`, `pending`, `lastControlError`, `lastControlErrorRunId`, `dismissControlError`, `stillWaiting`, `pendingTimer`, `stillWaitingText`, `refusalOf`, `openCancel`, `cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `closeCancel`, `confirmCancel`, `flash`, `flashText`, `flashTimer`.

Run: `timeout 900 bash tests/run.sh tst_app_runs`
Expected: PASS (pytest and `tst_app_runs.qml` green); exit 0.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): RunControlStore and the RunStore control shims"
```
<!-- task-pipeline: validated -->
