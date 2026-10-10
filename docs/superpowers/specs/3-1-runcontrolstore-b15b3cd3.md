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
