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

Built from `core/stores/RunStore.qml` at the commit of subtask 1.1 (2038 lines). Line numbers are that
file's. Test names are `file::test_name`, with the file relative to `tests/`; `(added)` marks a test
subtask 1.1 added.

### A.1 Member map

One row per top-level declaration of the root `Scope`: 225 rows, the count of
`grep -nE '^  (readonly )?(property|signal|function)|^  on[A-Z]|^  (HelperRunner|Timer|QtObject|Component) \{' core/stores/RunStore.qml`.
A child item is listed under its `id`; the readonly alias that exposes it is its own row of kind
`alias`, mapped to the same store.

| member | line | kind | target | tests that cover it |
|---|---|---|---|---|
| `projectRoots` | 41 | input property | RunStore | `core/stores/tst_app_runs.qml::test_project_roots_follow_the_registry` |
| `project` | 42 | input property | RunStore | `core/stores/tst_app_runs.qml::test_the_project_is_the_selected_root_path_string` |
| `backendDir` | 43 | input property | RunStore | `core/stores/tst_app_runs.qml::test_the_backend_dir_follows_app` |
| `active` | 44 | input property | RunStore | `core/stores/tst_app_runs.qml::test_active_follows_panel_open` |
| `runsByProject` | 49 | property | RunStore | `core/stores/tst_run_store.qml::test_runs_merge_every_root_in_registry_order_with_its_project` |
| `projectErrors` | 51 | property | RunStore | `core/stores/tst_run_store.qml::test_a_failing_root_keeps_its_runs_and_says_why` |
| `runs` | 54 | property | RunStore | `core/stores/tst_run_store.qml::test_runs_merge_every_root_in_registry_order_with_its_project` |
| `selectedRunId` | 55 | property | RunStore | `core/stores/tst_run_store.qml::test_selecting_a_run_fetches_its_default_attempt` |
| `amStatus` | 56 | property | RunStore | `core/stores/tst_run_store.qml::test_am_missing_sets_missing_and_clears_the_runs` |
| `amSchema` | 57 | property | RunStore | `core/stores/tst_run_store.qml::test_hello_sets_schema_and_version` |
| `amVersion` | 58 | property | RunStore | `core/stores/tst_run_store.qml::test_hello_sets_schema_and_version` |
| `lastError` | 59 | property | RunStore | `core/stores/tst_run_store.qml::test_garbage_stdout_keeps_the_previous_runs_and_names_the_exit_code` |
| `stale` | 60 | property | RunStore | `core/stores/tst_run_store.qml::test_stale_after_timer_fires` |
| `watchWarning` | 61 | property | RunStore | `core/stores/tst_run_store.qml::test_corrupt_journal_sets_warning_and_polls` |
| `runFilter` | 66 | property | RunStore | `core/stores/tst_run_store.qml::test_toggle_run_filter_and_back_to_all` |
| `searchQuery` | 67 | input property | RunStore | `core/stores/tst_app_runs.qml::test_the_search_query_follows_the_navigation_store`<br>`core/stores/tst_run_store.qml::test_filtered_runs_follow_the_filter_and_the_search` |
| `runFilterToggled` | 69 | signal | RunStore | `core/stores/tst_run_store.qml::test_toggle_run_filter_and_back_to_all`<br>`core/stores/tst_app_runs.qml::test_a_filter_change_puts_the_cursor_home` |
| `projectFilter` | 74 | property | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal` |
| `projectFilterToggled` | 77 | signal | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal`<br>`core/stores/tst_app_runs.qml::test_a_project_filter_toggle_puts_the_cursor_home` |
| `groups` | 80 | readonly property | RunStore | `core/stores/tst_run_store.qml::test_the_list_reads_project_by_project_in_display_order` |
| `filteredRuns` | 83 | readonly property | RunStore | `core/stores/tst_run_store.qml::test_filtered_runs_follow_the_filter_and_the_search` |
| `asOfSeq` | 88 | property | RunStore | `core/stores/tst_run_store.qml::test_am_missing_in_every_entry_empties_everything` |
| `appliedSeq` | 89 | property | RunStore | `core/stores/tst_run_store.qml::test_a_list_reply_lists_the_roots_runs_and_covers_them_at_0` |
| `watchCursor` | 91 | property | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_line_sets_the_watch_cursor` |
| `nudges` | 94 | property | RunStore | `core/stores/tst_run_store.qml::test_nudges_keep_the_highest_seq_per_run` |
| `storeId` | 98 | property | RunStore | `core/stores/tst_run_store.qml::test_a_store_id_starts_as_none` |
| `watchTried` | 105 | property | RunStore | `core/stores/tst_run_store.qml::test_with_no_absolute_root_no_watch_is_launched`<br>`core/stores/tst_run_store.qml::test_reactivation_starts_a_new_watch` |
| `watchSeq` | 106 | property | RunStore | `core/stores/tst_run_store.qml::test_with_no_absolute_root_no_watch_is_launched` |
| `watchSchemaError` | 107 | property | RunStore | `core/stores/tst_run_store.qml::test_schema_banner_survives_poll_snapshots` |
| `selectedAttempt` | 111 | property | RunStore | `core/stores/tst_run_store.qml::test_selecting_a_run_fetches_its_default_attempt` |
| `logsText` | 112 | property | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `logsTruncated` | 113 | property | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `logsFetchedMs` | 114 | property | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `logsLoading` | 115 | property | RunStore | `core/stores/tst_run_store.qml::test_logs_defaults` |
| `logsError` | 116 | property | RunStore | `core/stores/tst_run_store.qml::test_logs_failures_keep_the_text_and_never_touch_am_status` |
| `logsStatus` | 117 | property | RunStore | `core/stores/tst_run_store.qml::test_a_snapshot_that_changes_the_attempt_status_fetches_once` |
| `pending` | 124 | property | RunControlStore | `core/stores/tst_run_store.qml::test_control_sets_pending_as_a_new_object` |
| `stillWaiting` | 125 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_request_is_still_waiting_after_30_seconds` |
| `stillWaitingText` | 126 | readonly property | RunControlStore | `core/stores/tst_run_store.qml::test_control_defaults` |
| `lastControlError` | 127 | property | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_false_reply_clears_pending_and_says_why` |
| `lastControlErrorRunId` | 128 | property | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_false_reply_clears_pending_and_says_why` |
| `cancelRunId` | 133 | property | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `cancelOpen` | 134 | readonly property | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `cancelText` | 135 | property | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `cancelError` | 136 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm` |
| `flashText` | 138 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `armedRoots` | 149 | property | RunAlertsStore | `core/stores/tst_run_store.qml::test_a_root_that_leaves_the_registry_loses_its_arming` |
| `alertsArmed` | 150 | readonly property | RunAlertsStore | `core/stores/tst_run_store.qml::test_am_missing_disarms_and_a_failed_snapshot_does_not` |
| `toasts` | 151 | property | RunAlertsStore | `core/stores/tst_run_store.qml::test_a_run_that_turns_escalated_raises_one_toast` |
| `toastMs` | 152 | property | RunAlertsStore | `core/stores/tst_run_store.qml::test_a_run_that_turns_escalated_raises_one_toast`<br>`core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `notifyOnEscalation` | 158 | property | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `notifySaved` | 159 | property | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `notifyTouched` | 160 | property | RunControlStore | `core/stores/tst_run_store.qml::test_a_load_reply_after_the_user_toggled_is_ignored` |
| `runSettings` | 165 | property | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `dispatchState` | 173 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_dispatch_starts_idle` |
| `dispatchTarget` | 174 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchTargetLabel` | 175 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_sets_the_target_label` |
| `dispatchForm` | 176 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchPreview` | 177 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_preview_ok_goes_ready_with_summary` |
| `dispatchError` | 178 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_preview_refusal_goes_refused_verbatim` |
| `dispatchErrorType` | 179 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_done_card_is_refused` |
| `dispatchErrors` | 180 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_invalid_form_is_refused_without_launch` |
| `dispatchSuggest` | 181 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_from_a_blocked_preview` |
| `dispatchRunId` | 182 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `dispatchMessage` | 183 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `dispatchLog` | 184 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_failure_goes_failed_with_log` |
| `dispatchLogTail` | 185 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_failure_goes_failed_with_log` |
| `dispatchExitCode` | 186 | property | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_failure_goes_failed_with_log` |
| `dispatchStarted` | 189 | signal | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `runsNudged` | 193 | signal | RunStore | `core/stores/tst_run_store.qml::test_a_debounce_firing_announces_its_run_ids_once` |
| `watching` | 195 | alias | RunStore | `core/stores/tst_app_runs.qml::test_panel_close_through_app_stops_the_watch` |
| `watchProc` | 196 | alias | RunStore | `core/stores/tst_app_runs.qml::test_panel_close_through_app_stops_the_watch` |
| `watchRoots` | 197 | alias | RunStore | `core/stores/tst_run_store.qml::test_a_reordered_or_renamed_registry_keeps_the_watch` |
| `snapshotRunner` | 198 | alias | RunStore | `core/stores/tst_app_runs.qml::test_the_snapshot_names_every_registered_root` |
| `snapshotRoots` | 199 | alias | RunStore | `core/stores/tst_run_store.qml::test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| `pendingSnapshot` | 200 | alias | RunStore | `core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `debounceTimer` | 202 | alias | RunStore | `core/stores/tst_run_store.qml::test_changed_line_starts_debounce` |
| `livenessTimer` | 203 | alias | RunStore | `core/stores/tst_run_store.qml::test_liveness_on_with_running_run` |
| `staleTimer` | 204 | alias | RunStore | `core/stores/tst_run_store.qml::test_stale_timer_runs_only_while_active` |
| `pollTimer` | 205 | alias | RunStore | `core/stores/tst_run_store.qml::test_schema_mismatch_falls_back_to_poll` |
| `logsRunner` | 206 | alias | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `controlRunners` | 207 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_a_finished_request_leaves_control_runners` |
| `pendingTimer` | 208 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_the_pending_timer_runs_only_while_active_with_something_pending` |
| `flashTimer` | 209 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `toastTimer` | 210 | alias | RunAlertsStore | `core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `settingsLoadRunner` | 211 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `settingsSaveRunner` | 212 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `runSettingsRunner` | 213 | alias | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `notifyRunners` | 214 | alias | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dispatchDefaultsRunner` | 215 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchPreviewRunner` | 216 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_defaults_reply_sets_base_and_launches_preview` |
| `dispatchDebounceTimer` | 217 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_restarts_400ms_debounce_and_one_preview_per_burst` |
| `dispatchStartRunners` | 218 | alias | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `hasRunningRun` | 222 | readonly property | RunStore | `core/stores/tst_run_store.qml::test_liveness_on_with_running_run`<br>`core/stores/tst_run_store.qml::test_liveness_off_without_running_run` |
| `refresh` | 234 | function | RunStore | `core/stores/tst_run_store.qml::test_the_snapshot_names_every_usable_root_in_registry_order` |
| `requestSnapshot` | 249 | function | RunStore | `core/stores/tst_run_store.qml::test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| `launchSnapshot` | 268 | function | RunStore | `core/stores/tst_run_store.qml::test_a_pending_set_of_roots_launches_those_roots_in_registry_order` |
| `dropSnapshots` | 281 | function | RunStore | `core/stores/tst_run_store.qml::test_an_emptied_registry_drops_the_snapshot_in_flight_and_the_pending_request` |
| `snapshotEnded` | 289 | function | RunStore | `core/stores/tst_run_store.qml::test_a_failed_or_garbage_reply_still_launches_the_pending_request` |
| `toggleRunFilter` | 299 | function | RunStore | `core/stores/tst_run_store.qml::test_toggle_run_filter_and_back_to_all` |
| `toggleProjectFilter` | 307 | function | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal` |
| `projectRootOf` | 316 | function | RunStore | `core/stores/tst_run_store.qml::test_a_root_registered_with_a_trailing_slash_is_filtered_by_either_spelling` |
| `isFilterable` | 323 | function | RunStore | `core/stores/tst_run_store.qml::test_toggle_project_filter_and_its_signal` |
| `keepProjectFilter` | 343 | function | RunStore | `core/stores/tst_run_store.qml::test_the_registry_dropping_the_filtered_root_falls_back_to_all` |
| `onRunsChanged` | 349 | handler | RunStore | `core/stores/tst_run_store.qml::test_a_reply_that_leaves_the_project_without_runs_falls_back_to_all` |
| `onActiveChanged` | 351 | handler | RunStore | `core/stores/tst_app_runs.qml::test_active_follows_panel_open`<br>`core/stores/tst_run_store.qml::test_activation_refreshes_every_root` |
| `startLive` | 360 | function | RunStore | `core/stores/tst_run_store.qml::test_activation_refreshes_every_root`<br>`core/stores/tst_app_runs.qml::test_opening_the_panel_through_app_reads_the_notify_switch` (added) |
| `stopLive` | 375 | function | RunStore | `core/stores/tst_run_store.qml::test_deactivate_kills_watch_and_timers`<br>`core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (added) |
| `restartStale` | 392 | function | RunStore | `core/stores/tst_run_store.qml::test_stale_timer_runs_only_while_active` |
| `stopWatch` | 399 | function | RunStore | `core/stores/tst_run_store.qml::test_deactivate_kills_watch_and_timers` |
| `startWatch` | 412 | function | RunStore | `core/stores/tst_run_store.qml::test_watch_argv_after_first_snapshot` |
| `watchableRoots` | 428 | function | RunStore | `core/stores/tst_run_store.qml::test_with_no_absolute_root_no_watch_is_launched` |
| `knownRunIds` | 437 | function | RunStore | `core/stores/tst_run_store.qml::test_the_watch_names_every_root_then_every_known_run_id` |
| `sameRoots` | 455 | function | RunStore | `core/stores/tst_run_store.qml::test_a_reordered_or_renamed_registry_keeps_the_watch` |
| `isCurrentWatch` | 466 | function | RunStore | `core/stores/tst_run_store.qml::test_old_watch_hello_ignored`<br>`core/stores/tst_run_store.qml::test_killed_watch_lines_ignored_after_deactivation` |
| `watchLine` | 481 | function | RunStore | `core/stores/tst_run_store.qml::test_changed_line_starts_debounce`<br>`core/stores/tst_run_store.qml::test_garbage_watch_line_ignored` |
| `recordNudges` | 504 | function | RunStore | `core/stores/tst_run_store.qml::test_invalid_changed_entries_are_ignored` |
| `triggerNudges` | 523 | function | RunStore | `core/stores/tst_run_store.qml::test_a_debounce_firing_announces_its_run_ids_once` |
| `listsRun` | 546 | function | RunStore | `core/stores/tst_run_store.qml::test_a_nudge_refreshes_only_the_roots_that_list_its_runs` |
| `refreshLive` | 556 | function | RunStore | `core/stores/tst_run_store.qml::test_a_liveness_tick_refreshes_only_the_roots_with_a_running_run` |
| `resetCursor` | 575 | function | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_reset_starts_over_from_a_list_snapshot` |
| `forgetLive` | 587 | function | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_reset_starts_over_from_a_list_snapshot` |
| `seeStore` | 600 | function | RunStore | `core/stores/tst_run_store.qml::test_the_first_store_id_a_hello_names_resets_nothing`<br>`core/stores/tst_run_store.qml::test_a_hello_from_another_store_starts_over_from_a_list_snapshot` |
| `forgetHello` | 608 | function | RunStore | `core/stores/tst_run_store.qml::test_hello_reset_on_deactivate` |
| `watchExited` | 618 | function | RunStore | `core/stores/tst_run_store.qml::test_other_watch_error_stops_watching_without_poll` |
| `startPoll` | 640 | function | RunStore | `core/stores/tst_run_store.qml::test_schema_mismatch_falls_back_to_poll` |
| `stopPoll` | 644 | function | RunStore | `core/stores/tst_run_store.qml::test_poll_stops_on_deactivate` |
| `projectSwitched` | 655 | function | RunControlStore | `core/stores/tst_run_store.qml::test_project_switch_resets_dispatch_and_drops_old_preview`<br>`core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `onProjectChanged` | 664 | handler | RunControlStore | `core/stores/tst_app_runs.qml::test_the_project_is_the_selected_root_path_string`<br>`core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `usableRoots` | 670 | function | RunStore | `core/stores/tst_run_store.qml::test_the_snapshot_names_every_usable_root_in_registry_order` |
| `taggedByProject` | 689 | function | RunStore | `core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `mergedRuns` | 708 | function | RunStore | `core/stores/tst_run_store.qml::test_a_run_listed_under_two_roots_is_listed_once_under_the_first` |
| `registryChanged` | 731 | function | RunStore | `core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `onProjectRootsChanged` | 748 | handler | RunStore | `core/stores/tst_app_runs.qml::test_project_roots_follow_the_registry`<br>`core/stores/tst_run_store.qml::test_a_registry_change_drops_renames_adds_and_snapshots_again` |
| `runById` | 753 | function | RunStore | `core/stores/tst_run_store.qml::test_refusal_of_says_why_a_control_would_not_start` |
| `runRoot` | 762 | function | RunStore | `core/stores/tst_run_store.qml::test_logs_argv_leads_with_the_runs_project_root` |
| `selectAttempt` | 772 | function | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `refreshLogs` | 788 | function | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `fetchLogs` | 796 | function | RunStore | `core/stores/tst_run_store.qml::test_no_logs_launch_without_a_run_or_a_selection` |
| `clearLogs` | 808 | function | RunStore | `core/stores/tst_run_store.qml::test_changing_the_selected_run_resets_to_its_default_attempt` |
| `openDefaultAttempt` | 820 | function | RunStore | `core/stores/tst_run_store.qml::test_selecting_a_run_fetches_its_default_attempt` |
| `logsAfterSnapshot` | 829 | function | RunStore | `core/stores/tst_run_store.qml::test_a_snapshot_that_changes_the_attempt_status_fetches_once` |
| `onSelectedRunIdChanged` | 841 | handler | RunStore | `core/stores/tst_run_store.qml::test_changing_the_selected_run_resets_to_its_default_attempt` |
| `applyLogs` | 850 | function | RunStore | `core/stores/tst_run_store.qml::test_an_ok_logs_reply_sets_text_truncation_and_time` |
| `lastLine` | 870 | function | core/domain | `core/stores/tst_run_store.qml::test_the_last_non_empty_line_is_the_reply` |
| `parseEnvelope` | 880 | function | core/domain | `core/stores/tst_run_store.qml::test_json_that_is_not_an_envelope_is_an_error` |
| `rowOf` | 891 | function | RunStore | `core/stores/tst_run_store.qml::test_an_ok_reply_fills_runs_with_normalized_runs` |
| `isSeq` | 900 | function | RunStore | `core/stores/tst_run_store.qml::test_a_cursor_line_sets_the_watch_cursor` |
| `applySnapshot` | 909 | function | RunStore | `core/stores/tst_run_store.qml::test_a_whole_call_failure_or_garbage_keeps_everything` |
| `applyProjects` | 939 | function | RunStore | `core/stores/tst_run_store.qml::test_a_failing_root_keeps_its_runs_and_says_why`<br>`core/stores/tst_run_store.qml::test_am_missing_in_every_entry_empties_everything` |
| `alertsOf` | 1056 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_an_escalation_in_another_project_raises_one_toast_with_its_project` |
| `copyMap` | 1080 | function | core/domain | `core/stores/tst_run_store.qml::test_control_sets_pending_as_a_new_object` |
| `hasKey` | 1088 | function | core/domain | `core/stores/tst_run_store.qml::test_a_run_listed_under_two_roots_is_listed_once_under_the_first` |
| `control` | 1096 | function | RunControlStore | `core/stores/tst_run_store.qml::test_pause_and_cancel_launch_the_exact_argv` |
| `launchControl` | 1125 | function | RunControlStore | `core/stores/tst_run_store.qml::test_pause_and_cancel_launch_the_exact_argv` |
| `requestOf` | 1133 | function | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_reply_keeps_pending_and_refreshes`<br>`core/stores/tst_run_store.qml::test_two_runs_in_flight_at_once_both_apply` |
| `settle` | 1141 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled` |
| `failControl` | 1161 | function | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_false_reply_clears_pending_and_says_why` |
| `dismissControlError` | 1167 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_new_request_and_dismiss_clear_the_control_error` |
| `dropRunner` | 1173 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_finished_request_leaves_control_runners` |
| `controlReplied` | 1183 | function | RunControlStore | `core/stores/tst_run_store.qml::test_an_ok_reply_keeps_pending_and_refreshes`<br>`core/stores/tst_app_runs.qml::test_a_control_reply_through_app_snapshots_every_registered_root` (added) |
| `resumeWithSettings` | 1216 | function | RunControlStore | `core/stores/tst_run_store.qml::test_milestone_resume_reads_the_settings_then_passes_the_verify_set` |
| `settleAfterSnapshot` | 1244 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_settles_a_pending_request` (added) |
| `isHandled` | 1259 | function | RunControlStore | `core/stores/tst_run_store.qml::test_without_requested_at_the_last_request_of_that_command_decides` |
| `checkWaiting` | 1271 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_request_is_still_waiting_after_30_seconds` |
| `refusalOf` | 1287 | function | RunControlStore | `core/stores/tst_run_store.qml::test_refusal_of_says_why_a_control_would_not_start` |
| `flash` | 1299 | function | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `openCancel` | 1307 | function | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run` |
| `closeCancel` | 1319 | function | RunControlStore | `core/stores/tst_run_store.qml::test_open_cancel_opens_only_for_a_cancellable_run`<br>`core/stores/tst_run_store.qml::test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm` |
| `confirmCancel` | 1328 | function | RunControlStore | `core/stores/tst_run_store.qml::test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes` |
| `raiseAlerts` | 1349 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_five_alerts_in_one_snapshot_leave_the_last_three_toasts` |
| `expireToasts` | 1364 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `dismissToast` | 1370 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties` |
| `dismissAllToasts` | 1375 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties` |
| `notify` | 1382 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dropNotifyRunner` | 1388 | function | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `setNotifyOnEscalation` | 1395 | function | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `applyGlobalSettings` | 1407 | function | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `applyRunSettings` | 1417 | function | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `notifySaveReplied` | 1424 | function | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `clearDispatchError` | 1437 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_failed_then_change_previews_again` |
| `resetDispatch` | 1450 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_close_and_reopen_drop_the_pending_lookup`<br>`core/stores/tst_run_store.qml::test_project_switch_resets_dispatch_and_drops_old_preview` |
| `openDispatch` | 1478 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `closeDispatch` | 1505 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_close_and_reopen_drop_the_pending_lookup` |
| `blockedSuggest` | 1514 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_from_a_blocked_preview` |
| `retargetToMilestone` | 1523 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_from_a_blocked_preview`<br>`core/stores/tst_run_store.qml::test_retarget_refused_outside_a_blocked_refusal` |
| `withField` | 1530 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_after_ready_drops_preview_and_goes_previewing` |
| `dispatchTargetArgs` | 1537 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_board_preview_argv` |
| `dispatchCommands` | 1543 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `dispatchOptionArgs` | 1550 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_allow_no_verification_flag`<br>`core/stores/tst_run_store.qml::test_defaults_failure_sends_no_base` |
| `dispatchDefaultsReplied` | 1565 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_defaults_reply_sets_base_and_launches_preview` |
| `checkDispatch` | 1579 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_invalid_form_is_refused_without_launch`<br>`core/stores/tst_run_store.qml::test_subtask_goes_ready_without_preview` |
| `dispatchPreviewReplied` | 1603 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_preview_ok_goes_ready_with_summary` |
| `setDispatchField` | 1638 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_restarts_400ms_debounce_and_one_preview_per_burst` |
| `mergedPrefixes` | 1656 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_a_story_start_saves_the_prefix_under_its_milestone`<br>`core/stores/tst_run_store.qml::test_a_stored_map_that_is_not_an_object_merges_from_nothing` |
| `dispatchStart` | 1669 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `isHereStart` | 1698 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_reply_after_switching_away_and_back_is_not_here` |
| `dispatchStartReplied` | 1709 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves`<br>`core/stores/tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` (added) |
| `dispatchSaveReplied` | 1757 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_settings_write_failure_flashes` |
| `dropStartRunner` | 1764 | function | RunDispatchStore | `core/stores/tst_run_store.qml::test_settings_write_failure_flashes` |
| `snapshotRunner` | 1773 | runner | RunStore | `core/stores/tst_run_store.qml::test_the_snapshot_names_every_usable_root_in_registry_order` |
| `logsRunner` | 1782 | runner | RunStore | `core/stores/tst_run_store.qml::test_select_attempt_and_refresh_launch_the_exact_argv` |
| `settingsLoadRunner` | 1792 | runner | RunControlStore | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project` |
| `runSettingsRunner` | 1803 | runner | RunControlStore | `core/stores/tst_run_store.qml::test_run_settings_follow_the_project` |
| `settingsSaveRunner` | 1812 | runner | RunControlStore | `core/stores/tst_run_store.qml::test_the_switch_saves_globally_and_a_failed_save_puts_it_back` |
| `dispatchDefaultsRunner` | 1821 | runner | RunDispatchStore | `core/stores/tst_run_store.qml::test_open_milestone_goes_previewing_and_asks_defaults` |
| `dispatchPreviewRunner` | 1829 | runner | RunDispatchStore | `core/stores/tst_run_store.qml::test_defaults_reply_sets_base_and_launches_preview` |
| `debounceTimer` | 1837 | timer | RunStore | `core/stores/tst_run_store.qml::test_changed_line_starts_debounce` |
| `livenessTimer` | 1847 | timer | RunStore | `core/stores/tst_run_store.qml::test_liveness_on_with_running_run` |
| `staleTimer` | 1857 | timer | RunStore | `core/stores/tst_run_store.qml::test_stale_timer_runs_only_while_active` |
| `pollTimer` | 1866 | timer | RunStore | `core/stores/tst_run_store.qml::test_schema_mismatch_falls_back_to_poll` |
| `pendingTimer` | 1876 | timer | RunControlStore | `core/stores/tst_run_store.qml::test_the_pending_timer_runs_only_while_active_with_something_pending` |
| `flashTimer` | 1886 | timer | RunControlStore | `core/stores/tst_run_store.qml::test_a_flash_clears_itself_and_a_new_one_restarts_the_clock` |
| `toastTimer` | 1895 | timer | RunAlertsStore | `core/stores/tst_run_store.qml::test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts` |
| `dispatchDebounceTimer` | 1905 | timer | RunDispatchStore | `core/stores/tst_run_store.qml::test_change_restarts_400ms_debounce_and_one_preview_per_burst` |
| `watchState` | 1915 | state object | RunStore | `core/stores/tst_app_runs.qml::test_panel_close_through_app_stops_the_watch` |
| `snapshotState` | 1925 | state object | RunStore | `core/stores/tst_run_store.qml::test_a_request_during_a_snapshot_waits_as_the_one_pending_request` |
| `controlState` | 1935 | state object | RunControlStore | `core/stores/tst_run_store.qml::test_a_finished_request_leaves_control_runners` |
| `toastState` | 1943 | state object | RunAlertsStore | `core/stores/tst_run_store.qml::test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties` |
| `notifyState` | 1949 | state object | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dispatchBook` | 1960 | state object | RunDispatchStore | `core/stores/tst_run_store.qml::test_retarget_goes_once_to_the_milestone_recorded_at_the_opening` |
| `controlC` | 1974 | component | RunControlStore | `core/stores/tst_run_store.qml::test_pause_and_cancel_launch_the_exact_argv` |
| `notifyC` | 1991 | component | RunAlertsStore | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification` |
| `dispatchStartC` | 2007 | component | RunDispatchStore | `core/stores/tst_run_store.qml::test_start_argv_and_starting` |
| `watchC` | 2022 | component | RunStore | `core/stores/tst_run_store.qml::test_watch_argv_after_first_snapshot` |

### A.2 Not present at this commit

| member or section | from milestone | target | note |
|---|---|---|---|
| `dispatchRoot` | Dispatch from the Runs screen | RunDispatchStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `// ---- dispatch: project and target steps` (`dispatchStep`, `dispatchOpenFromRuns`, `dispatchBack`, `dispatchProject*`, `dispatchTarget*`, their two `board-tree.py` runners) | Dispatch from the Runs screen | RunDispatchStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| a Runs-opened start's `started` refreshing `[dispatchRoot]` only | Dispatch from the Runs screen | RunDispatchStore (`refreshRequested`) | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `// ---- relaunch` (`relaunchOpenFor`, `relaunch*`) | Resume and recover | RunDispatchStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `// ---- resume dialog` (`resume*`, `resumeOpenFor`, `resumeClose`, `resumeConfirm`, `resumeSaveRunner`) | Resume and recover | RunControlStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `lastControlErrorType` | Resume and recover | RunControlStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| the stopped-run attempt choice | Resume and recover | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| the events state | S5 | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `runsChanged(ids)` | S6 / milestone 4 | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| `snapshotReplied(root, outcome, previousRuns, runs)` | this milestone (new, rule 3) | RunStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |
| the persisted `gseq` alert cursor | Alerts while the panel is closed | RunAlertsStore | not in `RunStore.qml` at this commit; mapped whole when it lands; no characterization test |

### A.3 Cross-concern calls

| caller (line) | callee or effect (line) | from → to | App route | pinned by |
|---|---|---|---|---|
| `applyProjects` (939) | `settleAfterSnapshot()` (1026) | RunStore → Control | `snapshotReplied` outcome `ok` → `runControl.settleAfterSnapshot()`, first in the handler | `core/stores/tst_run_store.qml::test_a_pause_settles_when_its_request_is_handled`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_settles_a_pending_request` (added) |
| `applyProjects` (939) | `alertsOf(…)` (1015), only while `active` | RunStore → Alerts | `snapshotReplied(root, outcome, previousRuns, runs)` → `runAlerts.snapshotReplied(…)` | `core/stores/tst_run_store.qml::test_a_run_that_turns_escalated_raises_one_toast`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_raises_one_toast_after_arming` (added) |
| `applyProjects` (939) | `raiseAlerts(alerts)` (1044), arming the ok roots (1045-1047), only while `active` | RunStore → Alerts | same handler, after the settle | `core/stores/tst_run_store.qml::test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first`<br>`core/stores/tst_app_runs.qml::test_a_snapshot_through_app_raises_one_toast_after_arming` (added) |
| `applyProjects`, AmMissing branch (969) | `armedRoots = {}` (979) | RunStore → Alerts | `snapshotReplied` outcome `missing` | `core/stores/tst_run_store.qml::test_am_missing_disarms_and_a_failed_snapshot_does_not`<br>`core/stores/tst_app_runs.qml::test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms` (added) |
| `forgetLive` (587) | `armedRoots = {}` (593) | RunStore → Alerts | `snapshotReplied` outcome `missing` (forgetLive runs on that path) | `core/stores/tst_run_store.qml::test_a_cursor_reset_starts_over_from_a_list_snapshot`<br>`core/stores/tst_run_store.qml::test_a_hello_from_another_store_starts_over_from_a_list_snapshot` |
| `registryChanged` (731) | drops `armedRoots` entries for roots that left (738, 743) | RunStore → Alerts | App binds `projectRoots` to `RunAlertsStore`, which prunes on its own change | `core/stores/tst_run_store.qml::test_a_root_that_leaves_the_registry_loses_its_arming`<br>`core/stores/tst_app_runs.qml::test_a_project_leaving_the_registry_through_app_loses_its_arming` (added) |
| `startLive` (360) | `armedRoots = {}` (362) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first` |
| `startLive` (360) | `notifyTouched` reset unless a save is busy (363), `settingsLoadRunner.run(["get-global-settings"])` (364) | RunStore → Control | `RunControlStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_the_global_switch_loads_on_each_opening_with_no_project`<br>`core/stores/tst_run_store.qml::test_a_save_in_flight_survives_a_reopening`<br>`core/stores/tst_app_runs.qml::test_opening_the_panel_through_app_reads_the_notify_switch` (added) |
| `stopLive` (375) | `armedRoots = {}` (385), `toasts = []` (386) | RunStore → Alerts | `RunAlertsStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first`<br>`core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (added) |
| `stopLive` (375) | `closeDispatch()` (388) | RunStore → Dispatch | `RunDispatchStore`'s own `active` reaction | `core/stores/tst_run_store.qml::test_panel_close_closes_dispatch_but_not_a_start`<br>`core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` (added) |
| `projectSwitched` (655) | `resetDispatch()` (659) | Control → Dispatch | `RunDispatchStore`'s own `project` reaction | `core/stores/tst_run_store.qml::test_project_switch_resets_dispatch_and_drops_old_preview`<br>`core/stores/tst_app_runs.qml::test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` (added) |
| `raiseAlerts` (1349) | reads `notifyOnEscalation` (1359) | Alerts → Control | App binds `runAlerts.notifyOnEscalation: runControl.notifyOnEscalation` | `core/stores/tst_run_store.qml::test_with_the_setting_on_each_alert_launches_its_own_notification`<br>`core/stores/tst_app_runs.qml::test_an_escalation_through_app_notifies_only_with_the_switch_on` (added) |
| `controlReplied` (1183) | `refresh()` (1208) | Control → RunStore | `refreshRequested(roots)`; today the roots are every usable root | `core/stores/tst_run_store.qml::test_a_control_reply_refreshes_every_usable_root` (added)<br>`core/stores/tst_app_runs.qml::test_a_control_reply_through_app_snapshots_every_registered_root` (added)<br>`core/stores/tst_app_runs.qml::test_a_failed_control_reply_through_app_also_snapshots_every_root` (added) |
| `control` (1096), `refusalOf` (1287) | `runById` (1098, 1289), `runRoot` (1109, 1292) | Control → RunStore | App binds `runs`; the lookup is the rule-2 domain function | `core/stores/tst_run_store.qml::test_refusal_of_says_why_a_control_would_not_start`<br>`core/stores/tst_run_store.qml::test_a_run_with_no_repository_or_no_project_root_is_refused` |
| `settleAfterSnapshot` (1244) | `runById` (1251) | Control → RunStore | App binds `runs` | `core/stores/tst_run_store.qml::test_a_request_settles_when_its_run_vanishes` |
| `dispatchStartReplied` (1709) | `refresh()` (1729) | Dispatch → RunStore | `refreshRequested(roots)`; today every usable root | `core/stores/tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` (added)<br>`core/stores/tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` (added) |
| `dispatchStartReplied` (1709) | writes `runSettings` (1727) | Dispatch → Control | `runSettingsSaveRequested(root, patch)`, then `runSettings` comes back in as an input | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves` |
| `dispatchStartReplied` (1709) | runs `set-run-settings` through `viewer-state.py` on its own runner (1733) | Dispatch → Control | `runSettingsSaveRequested(root, patch)` | `core/stores/tst_run_store.qml::test_start_ok_with_run_id_emits_and_saves`<br>`core/stores/tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` (added) |
| `dispatchSaveReplied` (1757) | `flash("Dispatch settings could not be saved")` (1759) | Dispatch → Control | `noticeRequested(text)` | `core/stores/tst_run_store.qml::test_settings_write_failure_flashes`<br>`core/stores/tst_app_runs.qml::test_a_dispatch_settings_save_failure_through_app_flashes` (added) |
| `openDispatch` (1478) | reads `runSettings` and `runs` (`Runs.dispatchDefaults`, 1494) | Dispatch → Control, RunStore | App binds `runSettings` and `runs` | `core/stores/tst_run_store.qml::test_story_prefix_reads_the_snapshot_then_the_keyed_map`<br>`core/stores/tst_run_store.qml::test_open_before_the_settings_reply_starts_from_nothing` |
| `openDispatch` (1478), `checkDispatch` (1579) | read `project` (1479, 1499, 1594) | Dispatch → RunStore input | App binds `project` | `core/stores/tst_run_store.qml::test_open_without_project_is_refused`<br>`core/stores/tst_run_store.qml::test_board_preview_argv` |

Calls inside one store are not listed (for example `openCancel` → `flash` (1310), `confirmCancel` →
`control`, `notifySaveReplied` → `flash` (1431), `applyProjects` → `logsAfterSnapshot` (1027)).

### A.4 Tests added by this subtask

- `core/stores/tst_app_runs.qml::test_a_snapshot_through_app_settles_a_pending_request` — an acknowledged pause stays pending until a snapshot shows its request handled, then settles.
- `core/stores/tst_app_runs.qml::test_a_snapshot_through_app_raises_one_toast_after_arming` — the opening's first snapshots only arm; a later escalation raises exactly one toast.
- `core/stores/tst_app_runs.qml::test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms` — AmMissing empties the runs and disarms; the next good snapshot re-arms and raises nothing.
- `core/stores/tst_app_runs.qml::test_a_control_reply_through_app_snapshots_every_registered_root` — an ok control reply re-snapshots both registered roots.
- `core/stores/tst_app_runs.qml::test_a_failed_control_reply_through_app_also_snapshots_every_root` — an ok:false control reply sets the control error and still re-snapshots both roots.
- `core/stores/tst_app_runs.qml::test_a_dispatch_start_through_app_snapshots_every_registered_root` — a started dispatch emits `dispatchStarted("r-1")`, re-snapshots both roots and writes `set-run-settings` for its project.
- `core/stores/tst_app_runs.qml::test_a_dispatch_settings_save_failure_through_app_flashes` — a failed `set-run-settings` after a start flashes "Dispatch settings could not be saved".
- `core/stores/tst_app_runs.qml::test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings` — a switch resets the dispatch and `runSettings`, reads the new project's settings, keeps the toast, the request and the flash, and launches no snapshot.
- `core/stores/tst_app_runs.qml::test_opening_the_panel_through_app_reads_the_notify_switch` — opening reads `get-global-settings` with `notifyTouched` cleared, and a true reply turns the switch on.
- `core/stores/tst_app_runs.qml::test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch` — closing empties the toasts, disarms and closes a previewing dispatch.
- `core/stores/tst_app_runs.qml::test_an_escalation_through_app_notifies_only_with_the_switch_on` — an escalation only toasts while the switch is off and also notifies once it is on.
- `core/stores/tst_app_runs.qml::test_a_project_leaving_the_registry_through_app_loses_its_arming` — a root that leaves the registry loses its arming; on its return its first entry only re-arms.
- `core/stores/tst_run_store.qml::test_a_control_reply_refreshes_every_usable_root` — store level: a control reply re-snapshots every usable root.
- `core/stores/tst_run_store.qml::test_a_dispatch_start_refreshes_every_usable_root` — store level: a started dispatch re-snapshots every usable root.
