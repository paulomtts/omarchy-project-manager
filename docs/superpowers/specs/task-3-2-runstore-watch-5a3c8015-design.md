# 3.2 RunStore: watch signal, debounce, liveness timer, stale flag (card 5a3c8015)

Narrows the "Refresh model", "Domain model" (stale) and "Errors and edge cases" sections of `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` to the live-refresh half of `core/stores/RunStore.qml`. Builds on 3.1 (snapshot, selection, amStatus), which is unchanged except where noted below.

## Scope

Files touched:
- `core/stores/RunStore.qml`: extend it.
- `tests/core/stores/tst_run_store.qml`: extend it. Tests are written first.
- `tests/stubs/Quickshell/Io/SplitParser.qml` plus a `SplitParser` line in `tests/stubs/Quickshell/Io/qmldir`: a new test stub with a `read(string data)` signal, so the watch's stdout can be fed line by line. This mirrors real Quickshell.Io's `SplitParser`.

Not touched: `App.qml` and `docs/architecture.md` (both belong to 3.3), BoardStore, `runs.js`, the python helpers, UI, the attempt-logs runner, and controls or dispatch. The store keeps the existing layer rule: it imports only QtQml, Quickshell, Quickshell.Io and `../domain/runs.js`. It gets `project` and `backendDir` only through properties. The snapshot still runs through the existing `snapshotRunner` (HelperRunner). The watch is the only plain `Process`. Update the 3.1 header comment so it no longer says "the live watch (3.2) comes later".

## Observable behavior

New public properties: `active` (bool, default false; App binds it to "panel open" in 3.3), `watching` (bool, read-only to consumers), `stale` (bool), `watchWarning` (string, "" when there is no warning). Each Timer and the watch Process is exposed as a `readonly property alias` with an `objectName`: `watchProc`, `debounceTimer`, `livenessTimer`, `staleTimer`, `pollTimer`. This follows BoardStore's `watchTimer` pattern (BoardStore.qml:135-141).

1. **Activation.** When `active` becomes true and `project` is not "", the store calls `refresh()`. The 3.1 `projectSwitched()` and `refresh()` behavior stays as it is.
2. **Watch start.** The first successful (`ok:true`) snapshot after an activation or project switch, while `active` is true and no fallback poll is running, starts `watchProc` with the command `["python3", backendDir + "runs/runs-watch.py", project, <run ids of that snapshot, in snapshot order>]`. `watching` becomes true. Later snapshots do not restart a watch that is already running, because the helper itself picks up new runs of the project.
3. **Debounce.** Each stdout line is parsed as JSON. A `{"changed":[...]}` line restarts `debounceTimer` (250 ms, `repeat: false`). When the timer fires, it calls `refresh()` once, so a burst of lines costs one snapshot. Blank, unparsable or unrecognised lines are ignored and never throw.
4. **Liveness.** `livenessTimer` (10 s, repeating) runs only while `active` is true and at least one run in `runs` has `Runs.runState(run) === "running"`. Each tick calls `refresh()`. In every other case the timer is stopped, so no timer runs while idle.
5. **Stale.** `stale` becomes true when the last good snapshot is more than 30 s old while `active` is true. `staleTimer` (30 s, non-repeating) runs only while active and is restarted on activation and on every `ok:true` snapshot. When it fires, `stale` becomes true. A good snapshot sets `stale` back to false. Failed snapshots do not restart the timer. When the store goes inactive, `stale` is set to false. `stale` is not a run state and it leaves `runs` unchanged.
6. **Deactivation.** When `active` becomes false, the store stops `watchProc` (`running = false`) and stops the debounce, liveness, stale and poll timers. `watching`, `stale` and `watchWarning` are cleared. `runs`, `selectedRunId` and `amStatus` stay as they are.
7. **Project switch.** The 3.1 behavior still applies: runs, selection and lastError are cleared, and a new snapshot is requested. In addition, the old watch is stopped, `watching` becomes false, pending debounce and poll timers stop, and `watchWarning` is cleared. The new project's watch starts after its first good snapshot (rule 2). Lines or an exit from the old watch that arrive after the switch or after deactivation are ignored. The store records the project the watch was launched for plus a launch counter (bumped on every start and every stop) and checks both on each line and each exit, which acts as a stale-exit guard. This also covers deactivate then re-activate on the same project: the old process's late exit must not clear `watching` of the new watch. In addition, `stale` is set to false and `staleTimer` is restarted (when `active`), because the old project's snapshot age says nothing about the new one.

## Error paths (watch helper)

The helper prints `{"ok":false,"error":{"type":...,"message":...}}` and then exits 1.
- `SchemaMismatch`: `amStatus = "schema"` and `lastError = Runs.errorText(envelope)`, which drives the banner. The store switches to the fallback poll.
- `CorruptJournal`: `watchWarning = Runs.errorText(envelope)`, which drives the warning chip. The store switches to the fallback poll.
- Fallback poll: `watching` becomes false. `pollTimer` (5 s, repeating) runs while `active` is true and calls `refresh()` on each tick. It replaces the watch signal: no watch is restarted while it runs. Liveness and stale rules continue to apply. The poll is cleared on deactivation or project switch. A later activation tries the watch again.
- The helper's envelope arrives as a stdout line; the store keeps the last envelope line it saw and applies the error paths at process exit (the exit code decides "no envelope"). Other types (`HelperError`, `AmMissing`, `Usage`), or a non-zero exit with no envelope: `watching` becomes false and `lastError` is set. The store starts no poll and no restart. While the fallback poll is running (`pollTimer.running`), `applySnapshot` must not reset `amStatus` from "schema" to "ok" nor clear the `lastError` the watch set, so the banner survives the polling snapshots. A project switch clears both (3.1 behavior). Deactivation stops the poll but leaves `amStatus` and `lastError` as they are (rule 6); the next good snapshot after re-activation then resets them normally, and the watch is tried again.
- Exit 0 means the watch was stopped (the store killed it, or `am` exited). `watching` becomes false and nothing else changes.

## Tests

Tier: every test below goes in `tests/core/stores/tst_run_store.qml`. This is the headless QML store tier, following the placement rule "A store: ... test headless under tests/core/stores/" and the monitor spec's Testing section, which assigns "debounce, liveness timer on/off, fallback to poll, stale flag, project switch clears runs" to this file. None of these tests go in the ui, contract, pytest backend or architecture tiers. The tests use the existing `make()`, `makeWithProject()`, `reply()`, `entry()` and `okReply()` helpers and the stubbed Process, and they feed watch lines through the new SplitParser stub's `read`. Each test starts timers by checking `running` and fires them by calling `triggered()` directly. No test sleeps.

1. `test_watch_not_started_before_first_snapshot`: after activation, `watchProc.running` stays false until the snapshot reply.
2. `test_watch_argv_after_first_snapshot`: after an ok reply with runs a and b, the command is `python3 <backendDir>runs/runs-watch.py <project> a b`, and both `running` and `watching` are true.
3. `test_watch_not_started_when_inactive`: an ok snapshot while `active` is false leaves the watch off.
4. `test_failed_first_snapshot_does_not_start_watch`.
5. `test_second_snapshot_does_not_restart_watch`.
6. `test_deactivate_kills_watch_and_timers`: `watchProc.running`, `watching` and all timers are false, and `runs` is unchanged.
7. `test_changed_line_starts_debounce`, then `test_burst_coalesces_to_one_snapshot`: three `changed` lines followed by one `triggered()` launch exactly one snapshot.
8. `test_garbage_watch_line_ignored`.
9. `test_liveness_on_with_running_run`, `test_liveness_off_without_running_run` (dead, parked and done runs), `test_liveness_off_when_inactive`, and `test_liveness_tick_refreshes`.
10. `test_stale_after_timer_fires`, `test_good_snapshot_clears_stale`, `test_failed_snapshot_keeps_stale_timer_running` (the timer is not restarted), and `test_stale_cleared_on_deactivate`.
11. `test_schema_mismatch_falls_back_to_poll`: amStatus is "schema", `pollTimer.running` is true, `watching` is false, and a poll tick triggers a refresh.
12. `test_corrupt_journal_sets_warning_and_polls`.
13. `test_poll_stops_on_deactivate`.
14. `test_other_watch_error_stops_watching_without_poll`.
15. `test_watch_exit_zero_only_clears_watching`.
16. `test_project_switch_stops_watch_and_clears_runs`: the old watch is off, runs are empty, and `watching` and `watchWarning` are cleared.
17. `test_new_project_watch_starts_after_its_snapshot`: the argv carries the new project.
18. `test_old_watch_lines_ignored_after_switch`.
19. `test_schema_banner_survives_poll_snapshots` (amStatus stays "schema" and lastError is kept across an ok snapshot while polling), `test_stale_exit_after_reactivation_ignored`, and `test_project_switch_resets_stale`.
20. The existing 3.1 tests stay green without changes.
