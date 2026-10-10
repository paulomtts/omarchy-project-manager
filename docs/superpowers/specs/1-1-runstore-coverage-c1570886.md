# 1.1 RunStore coverage map and missing characterization tests — design

Card: `c1570886` (subtask of story `db774a43`). Parent design:
`docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as "P l.N".

## Purpose

This is the first subtask of the RunStore split. Nothing moves yet. It produces two things:

1. **Appendix A** of the parent spec (P l.166-171). This replaces the stub there with the member
   map and the cross-concern call list, built from `core/stores/RunStore.qml` at this commit.
2. **Characterization tests** for every member or coupling that no test pins today. They test
   TODAY's behaviour. Store-level tests go in `tests/core/stores/tst_run_store.qml`, and
   couplings tested through `App` go in `tests/core/stores/tst_app_runs.qml`.

There are no production code changes. Every file under `core/` and `ui/` is left as it is.

## Inherited constraints

- Every member lands in exactly one store. Nothing is duplicated, and nothing is dropped unless
  no code or test reads it (P l.61-67, rule 1).
- The target stores and what each owns come from the responsibilities table (P l.52-57).
- `lastLine`, `parseEnvelope`, `copyMap`, `hasKey` and the lookup inside `runById` become
  pure `core/domain/` functions (P l.68-71, rule 2).
- The App routes for cross-concern calls are inputs and signals (P l.72-91, rule 3):
  - `snapshotReplied(root, outcome, previousRuns, runs)` is handled in ONE App handler.
    `runControl.settleAfterSnapshot()` runs first, only on `ok`, then
    `runAlerts.snapshotReplied(…)`.
  - `refreshRequested(roots)` comes from `RunControlStore` and `RunDispatchStore`.
  - `runSettingsWanted(root)`, `runSettingsSaveRequested(root, patch)` and
    `noticeRequested(text)` come from `RunDispatchStore`.
  - App binds `runs`, `project`, `active`, `backendDir`, `notifyOnEscalation`, `runSettings`,
    `projectRoots` and `cardMap` as the table lists them.
- Each store keeps its own lifecycle. A reset that `projectSwitched`, `startLive` or
  `stopLive` does for another concern moves into that store's own reaction (P l.92-97,
  rule 4).
- A test that crosses two concerns becomes an App-level test in `tst_app_runs.qml`. Examples:
  a snapshot settles a pending request, a snapshot raises a toast, and a control reply
  re-snapshots (P l.98-104, rule 5; P l.154-162).
- `tests/architecture` stays green (P l.105-106, rule 6).
- No behaviour change (P l.146-147). The tests pin today's behaviour, even where a later spec
  changes it.
- From the card:
  - follow the `docs/architecture.md` layering;
  - `bash tests/run.sh` is green;
  - TDD: tests first;
  - docstrings and comments state the contract only, with no narrative.

## Facts at this commit that differ from the parent spec

- **The queued sections do not exist yet.** The parent assumes that Dispatch from the Runs
  screen and Resume and recover are merged (P l.3-12, 32-42, 154-159). They are not on this
  branch. A grep of `*.qml`, `*.js` and `*.py` finds none of the following:
  - `dispatchRoot`, `dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`,
    `dispatchProject*`, `dispatchTarget*` (other than the existing `dispatchTarget` and
    `dispatchTargetLabel`), and their `board-tree.py` runners;
  - the `// ---- dispatch: project and target steps`, `// ---- resume dialog` and
    `// ---- relaunch` sections;
  - `resume*` (other than the existing `resumeWithSettings`), `relaunchOpenFor`,
    `lastControlErrorType`, the stopped-run attempt choice;
  - the S5 events state, `snapshotReplied`, `runsChanged(ids)`.

  Those names appear only in `2026-10-05-dispatch-from-runs-design.md` and
  `2026-10-05-resume-recover-design.md`. They cannot be characterized against today's
  behaviour, so this subtask adds **no tests** for them. Appendix A records them in a
  separate "Not present at this commit" table (below).
- **A dispatch start refreshes every root today.** `dispatchStartReplied` calls
  `store.refresh()` (`RunStore.qml:1729`), which snapshots every usable root, not only the
  started run's root. A Runs-opened start does not exist. The characterization pins
  "every usable root". The parent's "Runs-opened `started` refreshes `dispatchRoot` only"
  (P l.158-159) is listed as not present.
- **A control reply refreshes every root.** `controlReplied` calls `store.refresh()`
  (`:1208`).
- **The parent's line numbers are stale.** The Problem table (P l.19-30) cites cbe313c. Appendix
  A uses the line numbers of `RunStore.qml` at this commit (2038 lines). P l.99 says "127
  tests today", but the file has about 302 tests. That number is left as it is, since it is
  outside the appendix.

## Deliverable 1 — Appendix A

Replace only the body under `## Appendix A — member mapping` (P l.166-171). Keep the heading.
Nothing else in the parent spec changes. The appendix has four parts, in this order.

### A.1 Member map

One Markdown table with the columns `member | line | kind | target | tests that cover it`.

- **Rows.** There is one row for every top-level member of the root `Scope` in
  `RunStore.qml`: every `property` (including `readonly`), every `readonly property alias`,
  `signal`, `function`, `on<Signal>:` handler, `HelperRunner`, `Timer`, `QtObject` and
  `Component` declared at the store's top level (2-space indentation). A child item is listed
  under its `id` (`snapshotRunner`, `debounceTimer`, `watchState`, `controlC`, …). The
  readonly alias that exposes it is a separate row of kind `alias`, mapped to the same store.
  No top-level member may be missing. Self-check: the number of rows equals the number of
  top-level declarations found by
  `grep -nE '^  (readonly )?(property|signal|function)|^  on[A-Z]|^  (HelperRunner|Timer|QtObject|Component) \{' core/stores/RunStore.qml`.
- **`kind`** is one of: `property`, `readonly property`, `input property` (App binds it:
  `backendDir`, `project`, `active`, `searchQuery`, `projectRoots`), `alias`, `signal`,
  `function`, `handler`, `runner`, `timer`, `state object`, `component`.
- **`target`** is exactly one of `RunStore`, `RunControlStore`, `RunAlertsStore`,
  `RunDispatchStore`, `core/domain`. `core/domain` is only for the four rule-2 helpers
  (`lastLine`, `parseEnvelope`, `copyMap`, `hasKey`; P l.68-71).
  - An input property that several stores read stays in `RunStore`. The other stores get
    their own App binding (P l.72-79), which is a new input, not a duplicated member.
  - A function whose body serves several concerns is mapped to the store that keeps its
    name. The lines that belong to another concern are listed in A.3.
- **`tests that cover it`** names one or more tests as `file::test_name`, with the file
  relative to `tests/`. This includes tests that exercise a private function only through
  its observable effects (for example `watchLine` through the watch-line tests). A ui-suite
  test counts when it reads or drives the member. A row with no test is not allowed when the
  work is done: the test added under Deliverable 2 is named there, marked `(added)`.

The mapping is fixed as follows. Lines are `RunStore.qml` at this commit. The implementer
re-greps before writing and corrects any line that has drifted, never the target.

| target | members |
|---|---|
| `RunStore` | **inputs:** `projectRoots` 41, `project` 42, `backendDir` 43, `active` 44<br>**snapshot and runs state:** `runsByProject` 49, `projectErrors` 51, `runs` 54, `selectedRunId` 55, `amStatus` 56, `amSchema` 57, `amVersion` 58, `lastError` 59, `stale` 60, `watchWarning` 61<br>**list filter:** `runFilter` 66, `searchQuery` 67, `runFilterToggled` 69, `projectFilter` 74, `projectFilterToggled` 77, `groups` 80, `filteredRuns` 83<br>**watch state:** `asOfSeq` 88, `appliedSeq` 89, `watchCursor` 91, `nudges` 94, `storeId` 98, `watchTried` 105, `watchSeq` 106, `watchSchemaError` 107<br>**selection and logs:** `selectedAttempt` 111, `logsText`, `logsTruncated`, `logsFetchedMs`, `logsLoading`, `logsError`, `logsStatus` 112-117<br>**signals and derived:** `runsNudged` 193, `hasRunningRun` 222<br>**aliases:** `watching`, `watchProc`, `watchRoots`, `snapshotRunner`, `snapshotRoots`, `pendingSnapshot`, `debounceTimer`, `livenessTimer`, `staleTimer`, `pollTimer`, `logsRunner` 195-206<br>**functions:** `refresh` 234, `requestSnapshot` 249, `launchSnapshot` 268, `dropSnapshots` 281, `snapshotEnded` 289, `toggleRunFilter` 299, `toggleProjectFilter` 307, `projectRootOf` 316, `isFilterable` 323, `keepProjectFilter` 343, `startLive` 360, `stopLive` 375, `restartStale` 392, `stopWatch` 399, `startWatch` 412, `watchableRoots` 428, `knownRunIds` 437, `sameRoots` 455, `isCurrentWatch` 466, `watchLine` 481, `recordNudges` 504, `triggerNudges` 523, `listsRun` 546, `refreshLive` 556, `resetCursor` 575, `forgetLive` 587, `seeStore` 600, `forgetHello` 608, `watchExited` 618, `startPoll` 640, `stopPoll` 644, `usableRoots` 670, `taggedByProject` 689, `mergedRuns` 708, `registryChanged` 731, `runById` 753, `runRoot` 762, `selectAttempt` 772, `refreshLogs` 788, `fetchLogs` 796, `clearLogs` 808, `openDefaultAttempt` 820, `logsAfterSnapshot` 829, `applyLogs` 850, `rowOf` 891, `isSeq` 900, `applySnapshot` 909, `applyProjects` 939<br>**handlers:** `onRunsChanged` 349, `onActiveChanged` 351, `onProjectRootsChanged` 748, `onSelectedRunIdChanged` 841<br>**children:** `snapshotRunner` 1773, `logsRunner` 1782 (runners); `debounceTimer` 1837, `livenessTimer` 1847, `staleTimer` 1857, `pollTimer` 1866 (timers); `watchState` 1915, `snapshotState` 1925 (state objects); `watchC` 2022 (component) |
| `RunControlStore` | **control and cancel state:** `pending` 124, `stillWaiting` 125, `stillWaitingText` 126, `lastControlError` 127, `lastControlErrorRunId` 128, `cancelRunId` 133, `cancelOpen` 134, `cancelText` 135, `cancelError` 136, `flashText` 138<br>**settings state:** `notifyOnEscalation` 158, `notifySaved` 159, `notifyTouched` 160, `runSettings` 165<br>**aliases:** `controlRunners` 207, `pendingTimer` 208, `flashTimer` 209, `settingsLoadRunner` 211, `settingsSaveRunner` 212, `runSettingsRunner` 213<br>**functions:** `projectSwitched` 655 (its `resetDispatch()` line goes to A.3), `control` 1096, `launchControl` 1125, `requestOf` 1133, `settle` 1141, `failControl` 1161, `dismissControlError` 1167, `dropRunner` 1173, `controlReplied` 1183, `resumeWithSettings` 1216, `settleAfterSnapshot` 1244, `isHandled` 1259, `checkWaiting` 1271, `refusalOf` 1287, `flash` 1299, `openCancel` 1307, `closeCancel` 1319, `confirmCancel` 1328, `setNotifyOnEscalation` 1395, `applyGlobalSettings` 1407, `applyRunSettings` 1417, `notifySaveReplied` 1424<br>**handlers:** `onProjectChanged` 664<br>**children:** `settingsLoadRunner` 1792, `runSettingsRunner` 1803, `settingsSaveRunner` 1812 (runners); `pendingTimer` 1876, `flashTimer` 1886 (timers); `controlState` 1935 (state object); `controlC` 1974 (component) |
| `RunAlertsStore` | **state:** `armedRoots` 149, `alertsArmed` 150, `toasts` 151, `toastMs` 152<br>**aliases:** `toastTimer` 210, `notifyRunners` 214<br>**functions:** `alertsOf` 1056, `raiseAlerts` 1349, `expireToasts` 1364, `dismissToast` 1370, `dismissAllToasts` 1375, `notify` 1382, `dropNotifyRunner` 1388<br>**children:** `toastTimer` 1895 (timer); `toastState` 1943, `notifyState` 1949 (state objects); `notifyC` 1991 (component) |
| `RunDispatchStore` | **state:** `dispatchState`, `dispatchTarget`, `dispatchTargetLabel`, `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchErrorType`, `dispatchErrors`, `dispatchSuggest`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode` 173-186<br>**signal:** `dispatchStarted` 189<br>**aliases:** `dispatchDefaultsRunner` 215, `dispatchPreviewRunner` 216, `dispatchDebounceTimer` 217, `dispatchStartRunners` 218<br>**functions:** `clearDispatchError` 1437, `resetDispatch` 1450, `openDispatch` 1478, `closeDispatch` 1505, `blockedSuggest` 1514, `retargetToMilestone` 1523, `withField` 1530, `dispatchTargetArgs` 1537, `dispatchCommands` 1543, `dispatchOptionArgs` 1550, `dispatchDefaultsReplied` 1565, `checkDispatch` 1579, `dispatchPreviewReplied` 1603, `setDispatchField` 1638, `mergedPrefixes` 1656, `dispatchStart` 1669, `isHereStart` 1698, `dispatchStartReplied` 1709, `dispatchSaveReplied` 1757, `dropStartRunner` 1764<br>**children:** `dispatchDefaultsRunner` 1821, `dispatchPreviewRunner` 1829 (runners); `dispatchDebounceTimer` 1905 (timer); `dispatchBook` 1960 (state object); `dispatchStartC` 2007 (component) |
| `core/domain` | `lastLine` 870, `parseEnvelope` 880, `copyMap` 1080, `hasKey` 1088 |

If the re-grep finds a top-level member that is not in this table, the implementer maps it with
the responsibilities table (P l.52-57) and states the reason in one clause in its row.

### A.2 Not present at this commit

A second table with the columns `member or section | from milestone | target | note`. Each
row's note reads "not in `RunStore.qml` at this commit; mapped whole when it lands; no
characterization test". Rows:

| member or section | from milestone | target |
|---|---|---|
| `dispatchRoot` | Dispatch from the Runs screen | `RunDispatchStore` |
| `// ---- dispatch: project and target steps` (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, their two `board-tree.py` runners) | Dispatch from the Runs screen | `RunDispatchStore` |
| a Runs-opened start's `started` refreshing `[dispatchRoot]` only | Dispatch from the Runs screen | `RunDispatchStore` (`refreshRequested`) |
| `// ---- relaunch` (`relaunchOpenFor`, `relaunch*`) | Resume and recover | `RunDispatchStore` |
| `// ---- resume dialog` (`resume*`, `resumeOpenFor`, `resumeClose`, `resumeConfirm`, `resumeSaveRunner`) | Resume and recover | `RunControlStore` |
| `lastControlErrorType` | Resume and recover | `RunControlStore` |
| the stopped-run attempt choice | Resume and recover | `RunStore` |
| the events state | S5 | `RunStore` |
| `runsChanged(ids)` | S6 / milestone 4 | `RunStore` |
| `snapshotReplied(root, outcome, previousRuns, runs)` | this milestone (new, rule 3) | `RunStore` |
| the persisted `gseq` alert cursor | Alerts while the panel is closed | `RunAlertsStore` |

### A.3 Cross-concern calls

A table with the columns `caller (line) | callee or effect (line) | from → to | App route |
pinned by`. It lists every place where a member mapped to one store reads or writes a member
mapped to another. `pinned by` names at least one `file::test_name` per row (an existing test,
or an added one marked `(added)`). The cases below give the first four columns; the
implementer fills `pinned by` (lines at this commit):

| caller | callee or effect | from → to | App route |
|---|---|---|---|
| `applyProjects` (939) | `settleAfterSnapshot()` (1026) | RunStore → Control | `snapshotReplied` outcome `ok` → `runControl.settleAfterSnapshot()`, first in the handler |
| `applyProjects` | `alertsOf(…)` (1015), only while `active` | RunStore → Alerts | `snapshotReplied(root, outcome, previousRuns, runs)` → `runAlerts.snapshotReplied(…)` |
| `applyProjects` | `raiseAlerts(alerts)` (1044), arming the ok roots (1045-1047), only while `active` | RunStore → Alerts | same handler, after the settle |
| `applyProjects`, AmMissing branch | `armedRoots = {}` (979) | RunStore → Alerts | `snapshotReplied` outcome `missing` |
| `forgetLive` (587) | `armedRoots = {}` (593) | RunStore → Alerts | `snapshotReplied` outcome `missing` (forgetLive runs on that path) |
| `registryChanged` (731) | drops `armedRoots` entries for roots that left (738, 743) | RunStore → Alerts | App binds `projectRoots` to `RunAlertsStore`, which prunes on its own change |
| `startLive` (360) | `armedRoots = {}` (362) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction |
| `startLive` | `notifyTouched` reset unless a save is busy (363), `settingsLoadRunner.run(["get-global-settings"])` (364) | RunStore → Control | `RunControlStore`'s own `active` reaction |
| `stopLive` (375) | `armedRoots = {}` (385), `toasts = []` (386) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction |
| `stopLive` | `closeDispatch()` (388) | RunStore → Dispatch | `RunDispatchStore`'s own `active` reaction |
| `projectSwitched` (655) | `resetDispatch()` (659) | Control → Dispatch | `RunDispatchStore`'s own `project` reaction |
| `raiseAlerts` (1349) | reads `notifyOnEscalation` (1359) | Alerts → Control | App binds `runAlerts.notifyOnEscalation: runControl.notifyOnEscalation` |
| `controlReplied` (1183) | `refresh()` (1208) | Control → RunStore | `refreshRequested(roots)`; today the roots are every usable root |
| `control` (1096), `refusalOf` (1287) | `runById` (1098, 1289), `runRoot` (1109, 1292) | Control → RunStore | App binds `runs`; the lookup is the rule-2 domain function |
| `settleAfterSnapshot` (1244) | `runById` (1251) | Control → RunStore | App binds `runs` |
| `dispatchStartReplied` (1709) | `refresh()` (1729) | Dispatch → RunStore | `refreshRequested(roots)`; today every usable root |
| `dispatchStartReplied` | writes `runSettings` (1727) | Dispatch → Control | `runSettingsSaveRequested(root, patch)`, then `runSettings` comes back in as an input |
| `dispatchStartReplied` | runs `set-run-settings` through `viewer-state.py` on its own runner (1733) | Dispatch → Control | `runSettingsSaveRequested(root, patch)` |
| `dispatchSaveReplied` (1757) | `flash("Dispatch settings could not be saved")` (1759) | Dispatch → Control | `noticeRequested(text)` |
| `openDispatch` (1478) | reads `runSettings` and `runs` (`Runs.dispatchDefaults`, 1494) | Dispatch → Control, RunStore | App binds `runSettings` and `runs` |
| `openDispatch`, `checkDispatch` (1579) | read `project` (1479, 1499, 1594) | Dispatch → RunStore input | App binds `project` |

Calls inside one store are not listed. Examples: `openCancel` → `flash` (1310),
`confirmCancel` → `control`, `notifySaveReplied` → `flash` (1431), and `applyProjects` →
`logsAfterSnapshot` (1027). If the implementer finds another cross-store call while filling
A.1, it is added here with a route in the same style (P l.87-91).

### A.4 Tests added by this subtask

A list with one line per added test: `file::test_name — what it pins`. Every name here also
appears in an A.1 row or an A.3 row (as a fifth column, `pinned by`, which A.3 has: every
A.3 row names at least one test).

## Deliverable 2 — characterization tests

All tests pin today's behaviour and pass on the first green run once written. Because the
production code already exists, TDD's "red" step here means checking that each new test can
fail. Before committing a test, the implementer breaks the expectation once, by changing
the compared value, and confirms the test fails. A test that cannot fail is rewritten. No
`core/` or `ui/` file changes.

### 2a. App-level coupling tests (`tests/core/stores/tst_app_runs.qml`)

**Why this tier:** each test crosses two concerns that become two stores. Rule 5 (P
l.101-104) puts such a test in `tst_app_runs.qml`, built on a real `App` (`make()`, the
existing helper). Today it drives `app.runs` alone. After the split, only the property paths
change. The existing `make()` and `okReply` helpers are reused. New helpers go at the top of
the file, next to them, and are not copied from `tst_run_store.qml` into a shared file: two
test files may each have their own small fixture builders. Each helper gets a one-line
contract comment. Throughout, "the panel is open" means `app.panelOpen = true`, and a reply
is delivered by setting `outText` on the runner's `current` process and calling
`exited(code)`.

The required tests, named exactly:

1. `test_a_snapshot_through_app_settles_a_pending_request`
   - Setup: the panel is open; pA's snapshot lists a running, accepting run `r1`.
   - `app.runs.control("pause", "r1")` gives `pending.r1 === "pause"`.
   - Then an ok control reply arrives, followed by a snapshot in which `r1`'s control shows the
     pause request handled (the shape `tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled`
     uses).
   - Expect: `pending.r1` is `undefined`.
2. `test_a_snapshot_through_app_raises_one_toast_after_arming`
   - Setup: the panel is open. The first ok snapshot lists `r1` as running.
   - Expect after the first snapshot: no toast, and `alertsArmed` is true.
   - Then a second snapshot lists `r1` as escalated.
   - Expect: exactly one toast, with `id === "r1"`.
3. `test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms`
   - Setup: armed as in test 2.
   - An AmMissing reply gives `alertsArmed === false` and `runs.length === 0`.
   - Then an ok snapshot with an escalated `r1` arrives.
   - Expect: no toast, `alertsArmed` is true again.
4. `test_a_control_reply_through_app_snapshots_every_registered_root`
   - Setup: pA and pB are registered, the panel is open, and the snapshot is applied.
   - `control("pause", "r1")`, then an ok control reply.
   - Expect: `snapshotRunner.seq` goes up by one. The new snapshot's argv is
     `python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj|/home/u/b`.
5. `test_a_failed_control_reply_through_app_also_snapshots_every_root`
   - The same as test 4, but with an `ok:false` reply.
   - Expect: `lastControlError` is set, and the same re-snapshot of both roots happens.
6. `test_a_dispatch_start_through_app_snapshots_every_registered_root`
   - Setup: pA is open and pA and pB are registered.
   - The dispatch is driven to `ready` through `app.runs`: `openDispatch(card, cardMap)` with
     a one-milestone card map, then the defaults reply and an ok preview reply. Follow the
     steps of `tst_run_store.qml`'s `readyStore`.
   - Then `dispatchStart()` and an ok start reply with run id `r-1`.
   - Expect:
     - `dispatchStarted` fires once, with `"r-1"`;
     - a new snapshot names both roots (today: every usable root, not the started run's
       root);
     - the start runner's next process runs `set-run-settings` for `/home/u/my proj`.
7. `test_a_dispatch_settings_save_failure_through_app_flashes`
   - Continue test 6's flow. The `set-run-settings` reply is a failure.
   - Expect: `flashText === "Dispatch settings could not be saved"`.
8. `test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings`
   - Setup: pA is open, the panel is open, the dispatch is in `previewing` or `ready`, and
     `runSettings` is non-empty (from a `get-run-settings` reply for pA).
   - Also present before the switch: a toast, a pending request, and a flash.
   - Action: `app.projects.chooseProject(pB)`.
   - Expect:
     - `dispatchState === "idle"` and `runSettings` is `{}`;
     - `runSettingsRunner.current`'s argv ends `get-run-settings|/home/u/b`;
     - the toast, the pending request and the flash are unchanged;
     - no new snapshot is launched (`snapshotRunner.seq` is unchanged).
9. `test_opening_the_panel_through_app_reads_the_notify_switch`
   - Setup: `make()` with the panel closed.
   - Action: `app.panelOpen = true`.
   - Expect: `settingsLoadRunner.current`'s argv ends `get-global-settings`, and
     `notifyTouched === false`.
   - Then the reply `{"ok":true,"settings":{"notifyOnEscalation":true}}`, in the shape
     `tst_run_store.qml`'s notify tests use, gives `notifyOnEscalation === true`.
10. `test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch`
    - Setup: the panel is open, alerts are armed, there is one toast, and the dispatch is not
      idle.
    - Action: `app.panelOpen = false`.
    - Expect: `toasts.length === 0`, `alertsArmed === false`, and `dispatchState === "idle"`.
11. `test_an_escalation_through_app_notifies_only_with_the_switch_on`
    - Setup: armed as in test 2.
    - With `notifyOnEscalation` false, an escalated snapshot gives one toast and
      `notifyRunners.length === 0`.
    - With the switch set true by the global-settings reply, another run's escalation gives
      `notifyRunners.length === 1`.
12. `test_a_project_leaving_the_registry_through_app_loses_its_arming`
    - Setup: pA and pB are armed; this is observable as a later escalation in each raising a
      toast.
    - Action: `app.projects.applyProjectsList([pA])`.
    - Then `applyProjectsList([pA, pB])` again, and a snapshot where pB's run is escalated
      arrives.
    - Expect: no toast for pB, because it is re-armed rather than compared against its old
      runs.

The fixture text for each reply copies the exact shapes the matching `tst_run_store.qml` tests
use. The implementer locates them by test name and does not invent new envelope fields.

### 2b. Store-level gap tests (`tests/core/stores/tst_run_store.qml`)

**Why this tier:** these pin one concern's own behaviour. The test moves unchanged with its
member's store in later subtasks.

While filling A.1, any row whose member no existing test exercises gets one store-level test,
added to the section of `tst_run_store.qml` that covers its concern (P l.99-100 move
targets). The test drives only public inputs, functions and stubbed processes, never a private
function's return value directly. Exceptions are the members whose observable effect is only
their own value: `stillWaitingText`, `toastMs`, the timers' `interval`.

The implementer must check each of these candidates. Each is a test name to add **only if**
the check shows no existing test pins the behaviour:

- `test_a_snapshot_after_a_no_root_watch_attempt_does_not_retry` (`watchTried`): while
  active, with only non-absolute usable roots, a first ok snapshot launches no watch, and a
  second ok snapshot launches none either (`watchProc` stays null, `watching` false). It is
  reset by the next `startLive`.
- `test_a_dispatch_start_refreshes_every_usable_root` (`dispatchStartReplied` → `refresh`):
  the store-level twin of App test 6, with two registered roots. Add it only if no existing
  dispatch test has more than one root.
- `test_a_control_reply_refreshes_every_usable_root`: the store-level twin of App test 4,
  with the same condition.

These members are already covered and need no new test; the A.1 rows name the tests listed:

- `dismissControlError`: `:2915`.
- `closeCancel`: `:3220`, `:3261`.
- `dispatchSaveReplied`: `test_settings_write_failure_flashes`.
- `mergedPrefixes`: `test_a_story_start_saves_the_prefix_under_its_milestone`.
- `isHereStart`: `test_start_reply_after_switching_away_and_back_is_not_here`.
- `retargetToMilestone`.
- `hasRunningRun`: the liveness tests `:1661-1689`.
- `stopLive`: `test_deactivate_kills_watch_and_timers`.
- `projectSwitched`: `test_project_switch_resets_dispatch_and_drops_old_preview`.

The implementer confirms each one by reading the test, not by name alone.

### 2c. What the tests must not do

- They must not assert a behaviour from a later spec: no `dispatchRoot`, no `snapshotReplied`,
  no `refreshRequested`.
- They must not reach past `app.runs` into another store's internals, except the existing
  `app.projects`, `app.nav` and `app.panelOpen` inputs.
- They must not change or delete any existing test or its expectations.
- They must not add a shared helper file, which would duplicate existing patterns that
  `tests/architecture` guards.

## Error paths covered

- **AmMissing:** disarms every root and empties the runs (App test 3).
- **Failed control reply:** still re-snapshots every root (App test 5).
- **Failed dispatch settings write:** flashes (App test 7).
- **Project switch with a dispatch mid-flight:** resets it, and the other concerns' state is
  untouched (App test 8).
- **Registry shrink:** forgets the arming (App test 12).

## Out of scope

- Any production change in `core/` or `ui/`, including the rule-2 domain helpers. Those
  belong to the next subtask of story `db774a43`.
- Creating `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`, `snapshotReplied` or
  `refreshRequested`, the shims, or moving any test into `tst_run_control_store.qml`,
  `tst_run_alerts_store.qml` or `tst_run_dispatch_store.qml`. Those belong to later stories.
- Tests for members that are not present at this commit (A.2).
- Editing any part of the parent spec other than the Appendix A body. That includes the
  stale Problem line numbers and the "127 tests" figure.
- The ui suites under `tests/ui/`. They are read to fill the coverage column and are not
  changed.

## Verification

- `bash tests/run.sh` is green. It runs pytest, including `tests/architecture`, and every
  `tst_*.qml`. Its failure scan sees none of: `FAIL`, `TypeError`, `ReferenceError`,
  `non-existent`, `Unable to assign`, `is not a function`.
- `git diff --stat` touches only these files (besides this spec and its plan under
  `docs/superpowers/`):
  - `docs/superpowers/specs/2026-10-05-split-runstore-design.md`;
  - `tests/core/stores/tst_app_runs.qml`;
  - `tests/core/stores/tst_run_store.qml`, only if a 2b test was added.
- Appendix A self-checks:
  - the A.1 row count equals the grep count above;
  - every A.1 row has a non-empty tests column;
  - every A.3 row has a `pinned by` test;
  - every test named in A.4 exists in its file (`grep -n "function <name>("`).
