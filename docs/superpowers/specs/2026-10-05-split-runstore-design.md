# Split RunStore — design

Status: proposed; retargeted to the new `am` (nudges and cursors, one global snapshot;
`2026-10-06-am-snapshots-cursors-design.md`, row spl). A behaviour-preserving refactor. Lands after the Resume and recover milestone
(`2026-10-05-resume-recover-design.md`) and before Alerts while the panel is closed. By then the
S3 (`2026-10-03-am-run-dispatch-design.md`), S7 (`2026-10-05-dispatch-story-level-design.md`),
S6 (`2026-10-05-runs-all-projects-design.md`), S5
(`2026-10-05-run-events-timeline-design.md`), Dispatch from the Runs screen
(`2026-10-05-dispatch-from-runs-design.md`) and Resume and recover milestones are merged on
main, and `RunStore.qml` carries all of them. The store names
here (`RunStore`, `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`) are assumed by
later specs, so do not rename them.

## Problem

`core/stores/RunStore.qml` is 1028 lines on main today (cbe313c), and it is one `Scope` that
holds seven concerns. Grounded in today's file:

| concern | state | functions | runners / timers |
|---|---|---|---|
| snapshot | `runs`, `amStatus`, `lastError`, `stale` (25-29) | `refresh` (126), `applySnapshot` (431), `rowOf` (417), `projectSwitched` (253) | `snapshotRunner` (838), `staleTimer` (898) |
| watch | `watchWarning`, `watchTried`, `watchSeq`, `watchSchemaError` (30, 46-48), `watching` / `watchProc` (98-99); after milestone 4 also `asOfSeq`, `appliedSeq`, `watchCursor` | `startLive`/`stopLive` (144-163), `startWatch` (181; after milestone 4 it passes no run ids and no project), `watchLine` (205), `watchExited` (220), poll (242-249) | `watchC` (1011), `debounceTimer` (879), `livenessTimer` (888), `pollTimer` (907) |
| list filter | `runFilter`, `searchQuery`, `filteredRuns` (35-40), `runFilterToggled` (38) | `toggleRunFilter` (132) | |
| selection and logs | `selectedRunId` (26), `selectedAttempt` … `logsStatus` (52-58) | `runById` (291), `selectAttempt` (303) … `applyLogs` (376) | `logsRunner` (850) |
| control | `pending`, `stillWaiting`, `stillWaitingText`, `lastControlError*` (65-69) | `control` (501) … `checkWaiting` (680), `resumeWithSettings` (625) | `controlC` (981), `controlState` (956), `pendingTimer` (917) |
| cancel dialog and flash | `cancelRunId`, `cancelOpen`, `cancelText`, `cancelError`, `flashText` (74-79) | `refusalOf` (695), `flash` (705), `openCancel` … `confirmCancel` (713-748) | `flashTimer` (927) |
| alerts | `alertsArmed`, `toasts`, `toastMs` (87-89) | `raiseAlerts` (755), `expireToasts`, `dismissToast`, `dismissAllToasts`, `notify` (770-797) | `toastTimer` (936), `toastState` (964), `notifyC` (999), `notifyState` (970) |
| run settings | `notifyOnEscalation`, `notifySaved`, `notifyTouched` (94-96) | `setNotifyOnEscalation` (801), `applyRunSettings` (813), `notifySaveReplied` (823) | `settingsLoadRunner` (861), `settingsSaveRunner` (870) |

Shared private helpers: `lastLine` (396), `parseEnvelope` (406), `copyMap` (485), `hasKey`
(493). The queued milestones add more concerns to the same file: S3 the dispatch state
machine (form, preview, start) and S7 its story target and retarget; S6 `projectRoots`, the
per-project snapshot, `runsChanged(ids)`, per-project alert arming and the global notify
setting; S5 the events state; Dispatch from the Runs screen `dispatchRoot` and the project and
target steps (a `// ---- dispatch: project and target steps` section: `dispatchStep`,
`dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*` and their two
`board-tree.py` runners); Resume and recover the stopped-run attempt choice in the selection,
`lastControlErrorType` beside the control error pair, the Resume dialog (a `// ---- resume
dialog` section: `resume*`, with its own `resumeSaveRunner`) and the relaunch (a
`// ---- relaunch` section: `relaunchOpenFor`). Each later milestone (Alerts while the panel is
closed, Live run output, Run history) would edit the same file again. Agents working on it
read 1500+ lines of unrelated state, and every change risks a neighbour.

## Decision

Four stores in `core/stores/`, composed by `App.qml` and wired only through explicit
properties and App-level signal handlers. A store never imports or names a sibling. The one
temporary exception is the shim handles in "Migration" below, which follow
`ProjectDeleteStore.projects` (`core/stores/ProjectDeleteStore.qml:13`), and the last story
removes them.

| store | `App` property | owns |
|---|---|---|
| `RunStore` | `app.runs` | the snapshot (every project, one `am runs --all-projects` call after S6 and milestone 4), the watch (nudges, no run-id argv) with its `asOfSeq`, `appliedSeq` and `watchCursor` and its `runsChanged(ids)` signal, `amStatus` / `lastError` / `stale` / `watchWarning`, the list filter (status chips, S6 project filter, search), the selection (`selectedRunId`, `runById`, Resume and recover's stopped-run attempt choice), the attempt logs, the S5 events |
| `RunControlStore` | `app.runControl` | `control()`, `pending`, `stillWaiting`, the control error (with Resume and recover's `lastControlErrorType`), `refusalOf`, the cancel confirmation, the flash, the resume verify read, the Resume dialog (the `resume*` section: its state, `resumeOpenFor` / `resumeClose` / `resumeConfirm`, `resumeSaveRunner`), and every run or global settings read and write through `viewer-state.py` (`get/set-run-settings`, S6 `get/set-global-settings`), so the notify switch and the stored verify set live here |
| `RunAlertsStore` | `app.runAlerts` | `newAlerts` arming (per project after S6), the toast queue, the toast expiry, the desktop notification (`notify.py`), and the persisted last-seen `gseq` alert cursor (with the `store_id` it belongs to; dismissing an alert advances it). The cursor's read and write through `viewer-state.py` global settings reach `RunControlStore` as an App-routed signal, the way `RunDispatchStore`'s settings requests do (to be confirmed in Appendix A) |
| `RunDispatchStore` | `app.runDispatch` | the S3 dispatch state machine (`idle → previewing → ready / refused → starting → started / failed`), the form, the debounced preview, `dispatchStart()`, the S7 story target and `retargetToMilestone()`, the default-branch lookup, Dispatch from the Runs screen's `dispatchRoot` and project and target steps (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, their runners), and Resume and recover's relaunch (the `relaunch*` section) |

Rules:

1. **Every member lands in exactly one store.** A property, function, signal, runner, timer or
   component that is in `RunStore.qml` when this milestone starts goes to exactly one store.
   Nothing is duplicated, and nothing is dropped unless no code or test reads it. The first
   subtask writes the full list as Appendix A of this spec, from the code at that time. The
   concern table in Problem covers only what exists on main today; the members the queued
   milestones add (named in Problem) are in Appendix A too, each delimited section mapped
   whole to the store the responsibilities table names.
2. **No duplicated helpers.** `lastLine` / `parseEnvelope` / `copyMap` / `hasKey` and the run
   lookup inside `runById` become pure functions in `core/domain/` before anything moves.
   `results.js` already holds the one-JSON-line reading (`parseJsonLine`). Each store imports
   them, and none keeps a private copy.
3. **Inputs come from App.** Each store gets only what it reads:

   | store | properties App binds | signals App routes |
   |---|---|---|
   | `RunStore` | `backendDir`, `project` (open root), `active`, `searchQuery`, `projectRoots` (S6), `titles` (S5) | out: `runFilterToggled`, `runsChanged(ids)`, `snapshotReplied(root, outcome, previousRuns, runs)` |
   | `RunControlStore` | `backendDir`, `project`, `active`, `runs` (`app.runs.runs`) | in: `settleAfterSnapshot()`; out: `refreshRequested(roots)` |
   | `RunAlertsStore` | `backendDir`, `active`, `notifyOnEscalation` (`app.runControl.notifyOnEscalation`) | in: `snapshotReplied(…)` |
   | `RunDispatchStore` | `backendDir`, `project`, `runs`, `projectRoots` (S6, read by the project step), `cardMap` (`app.board.cardMap`), `runSettings` (from `RunControlStore`) | out: `dispatchStarted(runId)` (S3, unchanged), `refreshRequested(roots)` (a start asks for `[dispatchRoot]`), `runSettingsWanted(root)`, `runSettingsSaveRequested(root, patch)` (`root` is `dispatchRoot`), `noticeRequested(text)` |

   `snapshotReplied` is new. `RunStore` emits it once per project reply, after the reply's own
   state is applied. `outcome` is `ok`, `missing` (AmMissing) or `failed`, and `previousRuns`
   are that project's runs before the reply. Before S6 there is one "project" (`store.project`);
   after milestone 4 the snapshot is one global reply, so it fires once per reply.
   App handles it in ONE handler, in today's order: `runControl.settleAfterSnapshot()` on `ok`,
   then `runAlerts.snapshotReplied(…)`. This replaces the direct calls in `applySnapshot`
   (444, 458) and the `alertsArmed = false` on AmMissing (472). Any direct call from one
   concern into another found at execution time becomes a signal routed by App in the same
   way. Examples: a control reply's `store.refresh()` (617), a dispatch "Started — waiting for
   the run to appear" toast, and the notify save failure's `flash` (830), which stays inside
   `RunControlStore` because the flash moves there.
4. **Lifecycle stays per store.** Each store reacts to `active` and to the project itself, as
   `RunStore` does today in `startLive` / `stopLive` / `projectSwitched`. A reset that
   `projectSwitched` does today for another concern (pending, cancel, toasts, the switch:
   268-285, the parts S6 left) moves into the owning store's own reaction. The timers keep
   their `running:` conditions (`pendingTimer` 922, `toastTimer` 941), each bound to its own
   store's `active`.
5. **Behaviour is pinned by tests that exist before the move.** Every subtask that moves code
   moves its tests with it, from `tests/core/stores/tst_run_store.qml` (127 tests today) into
   `tst_run_control_store.qml`, `tst_run_alerts_store.qml` and `tst_run_dispatch_store.qml`.
   Only construction and the wiring of inputs change, never an expectation. A test that crosses
   two concerns becomes an App-level test in `tests/core/stores/tst_app_runs.qml`. Examples: a
   snapshot settles a pending request, a snapshot raises a toast, and a control reply
   re-snapshots.
6. **`tests/architecture` stays green** at every subtask: store imports, no duplicated shared
   patterns, layer allowlists.

## Migration (shims)

`ui/` and its tests reach the store as `app.runs.X` today: the screens, `Navigator`,
`Shortcuts`, `Panel` (`appStores.runs.*`, for example `ui/Panel.qml:174`, 229-239) and test-only
aliases (`app.runs.controlRunners`, `notifyRunners`, `settingsLoadRunner`,
`settingsSaveRunner`, `raiseAlerts` in `tests/ui/tst_runs_flow.qml`, `tst_shortcuts.qml` and
`tests/ui/screens/tst_card_detail_screen.qml`). The extractions keep that surface unchanged, so
`ui/` is not touched until the last story:

- The callers the queued milestones add go the same way: Resume and recover's
  `ResumeVerifyDialog` in `Panel` (`resume*`), `RunDetailScreen` / `StopReasonBlock`
  (`relaunchOpenFor`, `lastControlErrorType`), and Dispatch from the Runs screen's
  `DispatchDialog` steps, `RunsScreen` **Start run** and `Shortcuts` `d`
  (`dispatchOpenFromRuns`, `dispatchStep`, `dispatchProject*`, `dispatchTarget*`).
- When a member moves, `RunStore` keeps a shim of the same name. A property is a read-only
  binding through a handle (`property var controlStore: null`, set by App). A function is a
  one-line forward that returns the target's result. A signal is re-emitted. A shim property
  must notify like the original, because `ui/Panel.qml:98` connects to `onCancelOpenChanged`.
- Shims hold no state and no logic, and the comment above them says only "Moved to X; removed
  by the last story".
- The last story first moves every `ui/` and `tests/ui/` caller to `app.runControl`,
  `app.runAlerts` and `app.runDispatch`, then deletes the shims and the handles. An App test
  then asserts that `RunStore` has none of the moved members.

## Where later work lands

Dispatch from the Runs screen and Resume and recover land BEFORE this milestone, in
`RunStore.qml`'s delimited sections (Problem); this milestone moves them as the
responsibilities table says. The milestones after it land in the new stores:

| milestone | store |
|---|---|
| Alerts while the panel is closed | `RunAlertsStore` |
| Live run output | `RunStore` (the logs) |
| Run history and titles | `RunStore` |

## Non-goals

- No behaviour change: no new state, no renamed public member (until the shims go), no new
  helper argv, and no change to which process starts when.
- No UI change apart from the callers' paths in the last story.
- No change to `HelperRunner`, the backend helpers or `runs.js` semantics. Rule 2 only moves
  helper functions into the domain.

## Testing

- **Characterization first.** The first subtask lists, for every member in Appendix A, the tests
  that pin its behaviour, and adds tests for anything that is uncovered. That includes the
  sections Dispatch from the Runs screen and Resume and recover added (`dispatch*` steps,
  `resume*`, `relaunch*`, `lastControlErrorType`, the stopped-run attempt choice). The likely
  gaps are the cross-concern couplings in rule 3, each pinned at App level, among them a
  Runs-opened dispatch's `started` refreshing `dispatchRoot` only.
- Each extraction: the moved tests pass unchanged against the new store. The App test proves
  the wiring: a snapshot settles a pending request, raises a toast and re-arms; a control reply
  refreshes; dispatch `started` re-snapshots. The ui suites pass untouched through the shims.
- The last story: the ui suites pass against the new paths, and the App test asserts that the
  shims are gone.

## Appendix A — member mapping

Produced by the first subtask from the code at execution time: one row per member of
`RunStore.qml` (properties, readonly aliases, functions, signals, runners, timers, components),
with columns `member | kind | target store | tests that cover it`, plus a list of every
cross-concern call (caller → callee, line), each with its App route.
