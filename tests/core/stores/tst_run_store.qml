// tests/core/stores/tst_run_store.qml
// The run monitor's store: the snapshot helper's exact argv, how its one JSON
// line becomes normalized runs and an amStatus, the latest-wins and project
// guards, and what a project switch clears. Built directly (App composes the
// store only in 3.3) and driven through stubbed Process objects.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "StoresRunStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string logsCmd: "python3|/plugin/core/backend/runs/runs-logs.py|"
  // The started capture's open subtask (explore attempt 1 is started) and a
  // done subtask of it (spec attempt 1 is ok).
  readonly property string openCard: "299ec9c0-b935-4c44-a7a0-982a104cbfe5"
  readonly property string doneCard: "5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff"

  Component { id: spyC; SignalSpy {} }

  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // A store with project A set, so its first snapshot is already in flight.
  function makeWithProject(root) {
    var store = make(); if (!store) return null
    store.project = root
    return store
  }

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data.
  function entry(id, runStatus, live) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
      status: {
        run: run,
        rows: [],
        stories: [],
        subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
  }

  function okReply(entries) {
    return JSON.stringify({ ok: true, runs: entries, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // ---- defaults and the snapshot command

  function test_defaults_and_no_process_without_a_project() {
    var store = make(); if (!store) return
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.project, "")
    verify(!store.snapshotRunner.current, "no snapshot while there is no project")
    store.refresh()
    verify(!store.snapshotRunner.current, "refresh() with no project does nothing")
  }

  function test_setting_the_project_starts_a_snapshot_with_the_exact_argv() {
    var store = makeWithProject(rootA); if (!store) return
    var proc = store.snapshotRunner.current
    verify(proc, "a snapshot was launched")
    compare(proc.command.length, 3)
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command[2], "/home/u/my proj", "the path with a space is one argument")
    compare(proc.running, true)
    compare(proc.launchGuard, "/home/u/my proj", "the launch is guarded by the NEW project")
  }

  // ---- project changes

  function test_a_project_switch_clears_runs_selection_and_error_and_refreshes() {
    var store = makeWithProject(rootA); if (!store) return
    var procA = store.snapshotRunner.current
    store.runs = [{ id: "r1" }]
    store.selectedRunId = "r1"
    store.lastError = "boom"
    store.amStatus = "error"
    store.project = rootB
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.lastError, "")
    compare(store.amStatus, "ok")
    var procB = store.snapshotRunner.current
    verify(procB !== procA, "a new snapshot was launched")
    compare(procB.command[2], "/home/u/b")
    compare(procB.launchGuard, "/home/u/b")
    compare(procA.running, false, "A's snapshot is stopped")
  }

  function test_clearing_the_project_clears_state_and_launches_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var procA = store.snapshotRunner.current
    var seqBefore = store.snapshotRunner.seq
    store.runs = [{ id: "r1" }]
    store.selectedRunId = "r1"
    store.project = ""
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.amStatus, "ok")
    compare(store.snapshotRunner.seq, seqBefore, "no snapshot is launched")
    compare(store.snapshotRunner.current, procA, "the runner was not asked to run again")
  }

  // ---- ok snapshots

  function test_an_ok_reply_fills_runs_with_normalized_runs() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true), entry("r2", "", false)]), 0)
    compare(store.runs.length, 2)
    compare(store.runs[0].id, "r1")
    compare(store.runs[0].status, "started", "the status comes from the nested am status data")
    compare(store.runs[0].milestone_id, "m-r1")
    verify(store.runs[0].lease !== null, "the lease comes from the nested control data")
    compare(store.runs[0].lease.live, true)
    compare(store.runs[0].lease.pid, 42)
    compare(store.runs[1].id, "r2")
    // r2's am status has no run.status: normalizeRun falls back to the row's
    // status, which must not be the status OBJECT the helper put there.
    verify(store.runs[1].status !== "[object Object]", "the summary's overwritten status is not used")
    compare(store.runs[1].status, "")
    compare(store.runs[1].lease.live, false)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  function test_an_ok_reply_without_runs_is_ok_and_empty() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.runs.length, 1)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.runs.length, 0, "runs: [] empties the list")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": true, "data_dir": "/x"}\n', 0)
    compare(store.runs.length, 0, "an absent runs key is an empty list, not an error")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  function test_only_the_latest_refresh_is_applied() {
    var store = makeWithProject(rootA); if (!store) return
    store.refresh()
    var first = store.snapshotRunner.current
    store.refresh()
    var second = store.snapshotRunner.current
    verify(first !== second, "the second refresh launched its own process")
    compare(first.running, false, "the older snapshot is stopped")
    reply(second, okReply([entry("new", "started", true)]), 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "new")
    reply(first, okReply([entry("old", "started", true), entry("old2", "done", false)]), 0)
    compare(store.runs.length, 1, "a late exit of the older snapshot changes nothing")
    compare(store.runs[0].id, "new")
  }

  function test_a_project_switch_drops_the_old_projects_late_result() {
    var store = makeWithProject(rootA); if (!store) return
    var procA = store.snapshotRunner.current
    reply(procA, okReply([entry("a1", "started", true)]), 0)
    compare(store.runs[0].id, "a1")
    store.selectedRunId = "a1"
    store.refresh()
    var procA2 = store.snapshotRunner.current
    store.project = rootB
    compare(store.runs.length, 0, "cleared at once")
    compare(store.selectedRunId, "", "the selection belongs to the old project")
    var procB = store.snapshotRunner.current
    verify(procB !== procA2, "a snapshot for B was launched")
    compare(procB.command[2], "/home/u/b")
    reply(procA2, okReply([entry("a2", "started", true)]), 0)
    compare(store.runs.length, 0, "A's late reply changes nothing")
    compare(store.amStatus, "ok")
    reply(procB, okReply([entry("b1", "done", false)]), 0)
    compare(store.runs.length, 1, "B's reply is applied")
    compare(store.runs[0].id, "b1")
  }

  function test_a_refresh_in_the_same_project_keeps_the_selection() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    store.selectedRunId = "r1"
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r1", "done", false)]), 0)
    compare(store.selectedRunId, "r1")
    compare(store.runs[0].status, "done")
  }

  function test_the_last_non_empty_line_is_the_reply() {
    var store = makeWithProject(rootA); if (!store) return
    var text = "warning: something chatty\n" + okReply([entry("r1", "started", true)]) + "\n  \n"
    reply(store.snapshotRunner.current, text, 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r1")
    compare(store.amStatus, "ok")
  }

  function test_malformed_runs_are_skipped_without_throwing() {
    var store = makeWithProject(rootA); if (!store) return
    var mixed = JSON.stringify({ ok: true, runs: [null, 3, "x", [1], entry("r1", "started", true), { id: "r2" }] })
    reply(store.snapshotRunner.current, mixed, 0)
    compare(store.runs.length, 2, "only the object entries are kept")
    compare(store.runs[0].id, "r1")
    compare(store.runs[1].id, "r2", "an entry without status data still normalizes")
    compare(store.runs[1].lease, null)
    compare(store.amStatus, "ok")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": true, "runs": {"r1": {}}}', 0)
    compare(store.runs.length, 0, "a runs value that is not an array is empty")
    compare(store.amStatus, "ok")
  }

  // ---- errors

  // A store whose first snapshot loaded r1, ready for the next reply.
  function loaded() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.runs.length, 1)
    store.refresh()
    return store
  }

  function test_am_missing_sets_missing_and_clears_the_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}\n', 1)
    compare(store.amStatus, "missing")
    compare(store.runs.length, 0, "no badges while am is missing")
    compare(store.lastError, "AmMissing: am is not installed.")
  }

  function test_another_ok_false_keeps_the_previous_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmBadOutput", "message": "am status did not print JSON (exit 3)."}}\n', 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1, "the previous runs stay")
    compare(store.runs[0].id, "r1")
    compare(store.lastError, "AmBadOutput: am status did not print JSON (exit 3).")
  }

  function test_garbage_stdout_keeps_the_previous_runs_and_names_the_exit_code() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, "Traceback (most recent call last):\n  oops {not json", 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r1")
    verify(store.lastError !== "", "the reason is shown")
    verify(store.lastError.indexOf("exit 1") >= 0, "the exit code is named: " + store.lastError)
    store.refresh()
    reply(store.snapshotRunner.current, "", 7)
    compare(store.amStatus, "error", "empty stdout is an error too")
    compare(store.runs.length, 1)
    verify(store.lastError.indexOf("exit 7") >= 0, "the exit code is named: " + store.lastError)
  }

  function test_json_that_is_not_an_envelope_is_an_error() {
    var store = loaded(); if (!store) return
    var shapes = ["[]", '"x"', "null", "{}", '{"ok": "yes"}']
    for (var i = 0; i < shapes.length; i++) {
      reply(store.snapshotRunner.current, shapes[i], 0)
      compare(store.amStatus, "error", shapes[i] + " is not a usable reply")
      compare(store.runs.length, 1, shapes[i] + " keeps the previous runs")
      verify(store.lastError.indexOf("exit 0") >= 0, "the exit code is named: " + store.lastError)
      store.refresh()
    }
  }

  function test_ok_false_without_an_error_object_is_unknown_error() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false}', 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1)
    compare(store.lastError, "unknown error")
  }

  function test_a_good_reply_after_an_error_restores_ok() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "The runs snapshot failed: boom"}}', 1)
    compare(store.amStatus, "error")
    verify(store.lastError !== "")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r2", "done", false)]), 0)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r2")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmMissing", "message": "am is not installed."}}', 1)
    compare(store.amStatus, "missing")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.amStatus, "ok", "missing recovers too")
    compare(store.lastError, "")
  }

  // ---- live refresh (3.2)

  // An active store (the panel is open) with project `root`: its first snapshot
  // is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.project = root
    return store
  }

  // An active store on project A whose first snapshot listed `entries`, so its
  // watch is running.
  function watchedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  // ---- activation and watch start

  function test_activation_refreshes_the_project() {
    var store = makeWithProject(rootA); if (!store) return
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel fetches a fresh snapshot")
    compare(store.snapshotRunner.current.command[2], "/home/u/my proj")
  }

  function test_activation_without_a_project_launches_nothing() {
    var store = make(); if (!store) return
    store.active = true
    verify(!store.snapshotRunner.current, "no snapshot without a project")
    verify(!store.watchProc, "no watch without a project")
    compare(store.watching, false)
  }

  function test_watch_not_started_before_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    verify(store.snapshotRunner.current, "the first snapshot is in flight")
    verify(!store.watchProc, "no watch before the first snapshot reply")
    compare(store.watching, false)
  }

  function test_watch_argv_after_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    var noId = { workflow: "orchestrator" }
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), noId, entry("b", "done", false)]), 0)
    compare(store.runs.length, 3)
    var w = store.watchProc
    verify(w, "the first good snapshot starts the watch")
    compare(w.objectName, "watchProc")
    compare(w.command.length, 5, "a run without an id adds no empty argument")
    compare(w.command[0], "python3")
    compare(w.command[1], "/plugin/core/backend/runs/runs-watch.py")
    compare(w.command[2], "/home/u/my proj", "the path with a space is one argument")
    compare(w.command[3], "a")
    compare(w.command[4], "b")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_watch_with_no_runs_watches_the_project_alone() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var w = store.watchProc
    verify(w, "an empty project is watched too: its first run must show up")
    compare(w.command.length, 3)
    compare(w.command[2], "/home/u/my proj")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_watch_not_started_when_inactive() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.runs.length, 1)
    verify(!store.watchProc, "a closed panel never watches")
    compare(store.watching, false)
  }

  function test_failed_first_snapshot_does_not_start_watch() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n', 1)
    verify(!store.watchProc, "a failed snapshot starts no watch")
    compare(store.watching, false)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(store.watchProc.command[3], "a")
    compare(store.watching, true)
  }

  function test_second_snapshot_does_not_restart_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("c", "started", true)]), 0)
    verify(store.watchProc === w, "the running watch is kept")
    compare(w.running, true)
    compare(w.command.length, 4, "its argv is not rewritten: the helper picks up new runs itself")
  }

  // ---- debounce

  // One stdout line of a watch: an object is sent as its JSON, a string as is.
  function sendLine(proc, value) {
    proc.stdout.read(typeof value === "string" ? value : JSON.stringify(value))
  }

  function test_changed_line_starts_debounce() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var t = store.debounceTimer
    compare(t.objectName, "debounceTimer")
    compare(t.interval, 250)
    compare(t.repeat, false)
    compare(t.running, false, "idle until a line arrives")
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    compare(t.running, true)
    compare(store.snapshotRunner.seq, seq, "a line alone launches no snapshot")
  }

  function test_burst_coalesces_to_one_snapshot() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: ["a"] })
    sendLine(store.watchProc, { changed: ["b"] })
    sendLine(store.watchProc, '{"changed": ["a", "c"]}')
    compare(store.snapshotRunner.seq, seq, "no snapshot during the burst")
    store.debounceTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the burst cost exactly one snapshot")
    compare(store.snapshotRunner.current.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
  }

  function test_garbage_watch_line_ignored() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var lines = ["", "   ", "not json {", "[]", "null", "3", '"changed"', "{}", '{"hello": 1}', '{"changed": "a"}', '{"changed": null}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.debounceTimer.running, false, JSON.stringify(lines[i]) + " is ignored")
    }
    compare(store.watching, true, "the watch keeps running")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  // ---- liveness

  function test_liveness_on_with_running_run() {
    var store = watchedStore([entry("a", "done", false), entry("b", "started", true)]); if (!store) return
    var t = store.livenessTimer
    compare(t.objectName, "livenessTimer")
    compare(t.interval, 10000)
    compare(t.repeat, true)
    compare(t.running, true, "a started run with a live lease is re-read")
  }

  function test_liveness_off_without_running_run() {
    var store = watchedStore([entry("d", "started", false), entry("p", "stopped", true), entry("f", "done", false)]); if (!store) return
    compare(store.livenessTimer.running, false, "dead, parked and done runs need no liveness re-read")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("d", "started", true)]), 0)
    compare(store.livenessTimer.running, true, "it starts once a run is running")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("d", "done", false)]), 0)
    compare(store.livenessTimer.running, false, "and stops when none is")
  }

  function test_liveness_off_when_inactive() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.livenessTimer.running, false, "no timer while the panel is closed")
    store.active = true
    compare(store.livenessTimer.running, true, "opening the panel with a running run starts it")
  }

  function test_liveness_tick_refreshes() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "each tick fetches a snapshot")
  }

  // ---- deactivation

  function test_deactivate_kills_watch_and_timers() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    store.selectedRunId = "a"
    var w = store.watchProc
    sendLine(w, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    compare(store.livenessTimer.running, true)
    store.active = false
    compare(w.running, false, "the watch is killed")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "the pending refresh is dropped")
    compare(store.livenessTimer.running, false)
    compare(store.runs.length, 1, "the runs stay for the next opening")
    compare(store.runs[0].id, "a")
    compare(store.selectedRunId, "a")
    compare(store.amStatus, "ok")
  }

  function test_reactivation_starts_a_new_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    store.active = true
    var first = store.snapshotRunner.current
    store.active = false
    store.active = true
    var second = store.snapshotRunner.current
    verify(first !== second, "each opening fetches its own snapshot")
    compare(old.running, false, "the old watch stays dead")
    reply(first, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc === old, "the superseded opening's late reply starts nothing")
    compare(store.watching, false)
    reply(second, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old, "the latest opening's first good snapshot starts a new watch")
    compare(fresh.running, true)
    compare(fresh.command[3], "a")
    compare(store.watching, true)
  }

  // ---- stale

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  function test_stale_timer_runs_only_while_active() {
    var store = makeWithProject(rootA); if (!store) return
    var t = store.staleTimer
    compare(t.objectName, "staleTimer")
    compare(t.interval, 30000)
    compare(t.repeat, false)
    compare(t.running, false, "no stale clock while the panel is closed")
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(t.running, false, "a good snapshot while closed starts no clock")
    store.active = true
    compare(t.running, true, "opening the panel starts the clock")
    compare(store.stale, false)
  }

  function test_stale_after_timer_fires() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "a good snapshot (re)starts the clock")
    fire(store.staleTimer)
    compare(store.stale, true)
    compare(store.runs.length, 1, "stale is not a run state: the runs are untouched")
    compare(store.runs[0].status, "done")
  }

  function test_good_snapshot_clears_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the clock counts from this snapshot")
  }

  function test_failed_snapshot_keeps_stale_timer_running() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var failure = '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n'
    store.refresh()
    reply(store.snapshotRunner.current, failure, 1)
    compare(store.staleTimer.running, true, "a failed snapshot leaves the clock running")
    compare(store.stale, false)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, failure, 1)
    compare(store.stale, true, "a failed snapshot does not clear stale")
    compare(store.staleTimer.running, false, "nor restart the clock")
  }

  function test_stale_cleared_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.active = false
    compare(store.stale, false)
    compare(store.staleTimer.running, false)
    compare(store.runs.length, 1)
  }

  function test_project_switch_resets_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.project = rootB
    compare(store.stale, false, "A's snapshot age says nothing about B")
    compare(store.staleTimer.running, true, "B's clock starts now")
  }

  function test_snapshot_landing_after_deactivation_starts_nothing() {
    var store = activeStore(rootA); if (!store) return
    var proc = store.snapshotRunner.current
    store.active = false
    reply(proc, okReply([entry("a", "started", true)]), 0)
    compare(store.runs.length, 1, "the runs are still applied")
    verify(!store.watchProc, "no watch for a closed panel")
    compare(store.watching, false)
    compare(store.staleTimer.running, false)
    compare(store.livenessTimer.running, false)
  }

  // ---- project switch and the launch guard

  function test_project_switch_stops_watch_and_clears_runs() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, true)
    store.project = rootB
    compare(old.running, false, "the old project's watch is stopped")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "its pending refresh is dropped")
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.current.command[2], "/home/u/b", "B's snapshot is requested")
  }

  function test_new_project_watch_starts_after_its_snapshot() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.project = rootB
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true)]), 0)
    var w = store.watchProc
    verify(w !== old, "B gets its own watch")
    compare(w.command.length, 4)
    compare(w.command[2], "/home/u/b")
    compare(w.command[3], "b1")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_old_watch_lines_ignored_after_switch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.project = rootB
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "the old watch's late line is dropped")
    reply(store.snapshotRunner.current, okReply([entry("b1", "started", true)]), 0)
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "even once B's watch runs")
    sendLine(store.watchProc, { changed: ["b1"] })
    compare(store.debounceTimer.running, true, "B's own lines still count")
  }

  function test_killed_watch_lines_ignored_after_deactivation() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "a killed watch's late line is dropped")
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc !== old)
    sendLine(old, { changed: ["a"] })
    compare(store.debounceTimer.running, false, "same project, but an older launch")
  }

  function test_clearing_the_project_while_active_stops_everything() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    var seq = store.snapshotRunner.seq
    store.project = ""
    compare(old.running, false, "the watch is stopped")
    compare(store.watching, false)
    compare(store.staleTimer.running, false, "nothing to be stale about")
    compare(store.livenessTimer.running, false, "no runs, no liveness")
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.seq, seq, "no snapshot without a project")
  }

  // ---- watch exit and the fallback poll

  function watchError(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } })
  }

  // The watch prints its last line (none when `line` is ""), then exits.
  function endWatch(proc, line, code) {
    if (line !== "") sendLine(proc, line)
    proc.exited(code)
  }

  function test_schema_mismatch_falls_back_to_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var t = store.pollTimer
    compare(t.objectName, "pollTimer")
    compare(t.interval, 5000)
    compare(t.repeat, true)
    compare(t.running, false, "no poll while the watch works")
    var msg = "am watch speaks journal schema 2; this helper reads schema 1."
    endWatch(store.watchProc, watchError("SchemaMismatch", msg), 1)
    compare(store.amStatus, "schema")
    compare(store.lastError, "SchemaMismatch: " + msg)
    compare(store.watching, false)
    compare(t.running, true)
    var seq = store.snapshotRunner.seq
    t.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "a poll tick fetches a snapshot")
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.watching, false, "the poll replaces the watch: none is restarted")
    compare(t.running, true)
  }

  function test_schema_banner_survives_poll_snapshots() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    store.pollTimer.triggered()
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.runs[0].status, "done", "the polled snapshot is applied")
    compare(store.amStatus, "schema", "the banner stays while polling")
    compare(store.lastError, "SchemaMismatch: schema 2")
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the stale rule still applies while polling")
  }

  function test_corrupt_journal_sets_warning_and_polls() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "journal line 12 is not JSON"), 1)
    compare(store.watchWarning, "CorruptJournal: journal line 12 is not JSON")
    compare(store.amStatus, "ok", "a warning chip, not a banner")
    compare(store.lastError, "")
    compare(store.watching, false)
    compare(store.pollTimer.running, true)
    var seq = store.snapshotRunner.seq
    store.pollTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1)
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.watchWarning, "CorruptJournal: journal line 12 is not JSON", "the chip stays while polling")
    compare(store.amStatus, "ok")
    compare(store.watching, false)
  }

  function test_poll_stops_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.pollTimer.running, true)
    store.active = false
    compare(store.pollTimer.running, false)
    compare(store.amStatus, "schema", "deactivation leaves amStatus as it is")
    compare(store.lastError, "SchemaMismatch: schema 2")
    store.active = true
    compare(store.pollTimer.running, false, "the next opening tries the watch first")
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.amStatus, "ok", "a good snapshot after re-opening resets the status")
    compare(store.lastError, "")
    compare(store.watching, true, "and the watch is tried again")
  }

  function test_corrupt_warning_cleared_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.watchWarning, "CorruptJournal: bad")
    store.active = false
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
  }

  function test_other_watch_error_stops_watching_without_poll() {
    var cases = [["HelperError", 1], ["AmMissing", 1], ["Usage", 2]]
    for (var i = 0; i < cases.length; i++) {
      var type = cases[i][0]
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      endWatch(store.watchProc, watchError(type, "m"), cases[i][1])
      compare(store.watching, false, type)
      compare(store.lastError, type + ": m")
      compare(store.amStatus, "ok", type + " is not a schema banner")
      compare(store.watchWarning, "", type + " is not a warning chip")
      compare(store.pollTimer.running, false, type + " starts no poll")
      store.refresh()
      reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
      compare(store.watching, false, type + ": no restart until the next opening")
    }
  }

  function test_watch_exit_without_envelope_names_the_exit_code() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, "", 137)
    compare(store.watching, false)
    verify(store.lastError.indexOf("exit 137") >= 0, "the exit code is named: " + store.lastError)
    compare(store.pollTimer.running, false)
    compare(store.amStatus, "ok")
  }

  function test_watch_exit_zero_only_clears_watching() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    sendLine(store.watchProc, { changed: ["a"] })
    endWatch(store.watchProc, "", 0)
    compare(store.watching, false)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
    compare(store.debounceTimer.running, true, "the pending refresh still happens")
    compare(store.livenessTimer.running, true)
    compare(store.runs.length, 1)
  }

  function test_stale_exit_after_reactivation_ignored() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old)
    compare(store.watching, true)
    old.exited(0)
    compare(store.watching, true, "the killed watch's late exit does not end the new one")
    compare(fresh.running, true)
  }

  function test_old_watch_exit_ignored_after_switch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.project = rootB
    endWatch(old, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.amStatus, "ok", "A's watch says nothing about B")
    compare(store.lastError, "")
    compare(store.pollTimer.running, false)
  }

  function test_project_switch_clears_warning_and_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.pollTimer.running, true)
    store.project = rootB
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
    compare(store.watching, false)
    reply(store.snapshotRunner.current, okReply([entry("b1", "done", false)]), 0)
    compare(store.watching, true, "B's watch is tried")
    compare(store.watchProc.command[2], "/home/u/b")
  }

  // ---- the Runs screen's filter and search (5.1)

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  function screenEntries() {
    return [entry("live1", "started", true), entry("esc1", "escalated", false),
            entry("dead1", "started", false), entry("park1", "stopped", false)]
  }

  function test_filtered_runs_follow_the_filter_and_the_search() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    compare(store.runFilter, "")
    compare(store.searchQuery, "")
    compare(ids(store.filteredRuns), "live1,esc1,dead1,park1")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "esc1,dead1")
    store.searchQuery = "DEAD"
    compare(ids(store.filteredRuns), "dead1", "the search composes with the filter")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "dead1")
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "live1,esc1,dead1,park1")
  }

  function test_toggle_run_filter_and_back_to_all() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    store.toggleRunFilter("live")
    compare(store.runFilter, "live")
    compare(spy.count, 1)
    store.toggleRunFilter("parked")
    compare(store.runFilter, "parked", "another chip replaces the filter")
    store.toggleRunFilter("parked")
    compare(store.runFilter, "", "the active chip again is All")
    store.toggleRunFilter("attention")
    store.toggleRunFilter("all")
    compare(store.runFilter, "", "the All chip is All")
    compare(spy.count, 5)
  }

  function test_a_project_switch_resets_the_filter() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    store.toggleRunFilter("attention")
    store.project = rootB
    compare(store.runFilter, "")
    compare(store.filteredRuns.length, 0)
  }

  // ---- attempt logs (5.2)

  // A snapshot entry of the started capture: runs.json's first `am runs` row
  // whose `status` is status-started.json's `am status` data. Its open attempt
  // is openCard explore 1 and doneCard spec 1 is an earlier, ok attempt. The
  // run id and repo dir are the test's; so is the open attempt's status, in
  // am's attempt vocabulary (started, ok).
  function treeEntry(id, status) {
    var e = F.load("runs.json").data.runs[0]
    e.id = id
    e.repo_dir = tc.rootA
    e.status = F.load("status-started.json").data
    e.status.run.id = id
    e.status.stories[1].subtasks[1].phases[1].attempts[0].status = status
    return e
  }

  // A fresh logs-attempt.json `am logs` reply, as one JSON line, whose stdout
  // artifact text is `stdout` and, when given, whose stderr artifact text is
  // `stderr` (else the capture's null).
  function logsReply(stdout, stderr) {
    var envelope = F.load("logs-attempt.json")
    // synthetic: the texts are the test's; the envelope is the capture's.
    envelope.data.artifacts.stdout.text = stdout
    if (stderr !== undefined) envelope.data.artifacts.stderr.text = stderr
    return JSON.stringify(envelope) + "\n"
  }

  function argv(proc) { return proc.command.join("|") }

  // Project A's snapshot listed r1 (treeEntry) and r1 is the selected run, so
  // its default attempt's logs are in flight.
  function opened(status) {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", status || "started")]), 0)
    store.selectedRunId = "r1"
    return store
  }

  function test_logs_defaults() {
    var store = make(); if (!store) return
    compare(store.selectedAttempt, null)
    compare(store.logsText, "")
    compare(store.logsTruncated, false)
    compare(store.logsFetchedMs, 0)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.logsStatus, "")
    verify(!store.logsRunner.current, "no logs fetch at start")
  }

  function test_selecting_a_run_fetches_its_default_attempt() {
    var store = opened(); if (!store) return
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(argv(proc), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
    compare(proc.launchGuard, "/home/u/my proj", "guarded by the project")
    compare(store.selectedAttempt.card_id, tc.openCard)
    compare(store.selectedAttempt.phase, "explore")
    compare(store.selectedAttempt.attempt, 1)
    compare(store.logsStatus, "started", "the status the fetch was launched for")
    compare(store.logsLoading, true)
  }

  function test_select_attempt_and_refresh_launch_the_exact_argv() {
    var store = opened(); if (!store) return
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.doneCard + "|spec|1")
    compare(store.logsStatus, "ok")
    var first = store.logsRunner.current
    var seq = store.logsRunner.seq
    store.refreshLogs()
    compare(store.logsRunner.seq, seq + 1, "Refresh fetches again")
    verify(store.logsRunner.current !== first)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.doneCard + "|spec|1")
  }

  function test_no_logs_launch_without_project_run_or_selection() {
    var bare = make(); if (!bare) return
    bare.selectAttempt(tc.doneCard, "spec", 1)
    verify(!bare.logsRunner.current, "no project")
    compare(bare.selectedAttempt, null)
    bare.refreshLogs()
    verify(!bare.logsRunner.current)

    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), entry("r2", "started", true)]), 0)
    store.selectAttempt(tc.doneCard, "spec", 1)
    verify(!store.logsRunner.current, "no run selected")
    compare(store.selectedAttempt, null)
    store.selectedRunId = "r2"
    verify(!store.logsRunner.current, "a run with no attempt selects nothing")
    compare(store.selectedAttempt, null)
    store.refreshLogs()
    verify(!store.logsRunner.current, "no selection")
    store.selectAttempt(tc.doneCard, "spec", 0)
    store.selectAttempt(tc.doneCard, "", 1)
    store.selectAttempt("", "spec", 1)
    store.selectAttempt(tc.doneCard, "spec", "1")
    verify(!store.logsRunner.current, "not a real attempt")
  }

  function test_an_ok_logs_reply_sets_text_truncation_and_time() {
    var store = opened(); if (!store) return
    var before = Date.now()
    reply(store.logsRunner.current, logsReply("collecting...\n3 passed\n"), 0)
    var after = Date.now()
    compare(store.logsText, "collecting...\n3 passed")
    compare(store.logsTruncated, false)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    verify(store.logsFetchedMs >= before && store.logsFetchedMs <= after, "fetched now: " + store.logsFetchedMs)
    var lines = []
    for (var i = 0; i < 250; i++) lines.push("line " + i)
    store.refreshLogs()
    reply(store.logsRunner.current, logsReply(lines.join("\n") + "\n", "boom\n"), 0)
    var shown = store.logsText.split("\n")
    compare(shown.length, 201, "the last 200 stdout lines, then stderr")
    compare(shown[0], "line 50")
    compare(shown[199], "line 249")
    compare(shown[200], "boom")
    compare(store.logsTruncated, true)
  }

  function test_a_real_logs_reply_shows_the_attempts_output() {
    var store = opened(); if (!store) return
    var envelope = F.load("logs-attempt.json")
    reply(store.logsRunner.current, JSON.stringify(envelope) + "\n", 0)
    compare(store.logsText, envelope.data.artifacts.stdout.text.slice(0, -1), "the attempt's stdout")
    compare(store.logsText.split("\n").length, 19)
    compare(store.logsTruncated, false)
    compare(store.logsError, "")
    compare(store.logsLoading, false)
  }

  function test_logs_failures_keep_the_text_and_never_touch_am_status() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var types = ["AmMissing", "AmBadOutput", "HelperError", "Usage", "UnknownRunError"]
    for (var i = 0; i < types.length; i++) {
      store.refreshLogs()
      reply(store.logsRunner.current, JSON.stringify({ ok: false, error: { type: types[i], message: "m" } }) + "\n",
            types[i] === "Usage" ? 2 : 0)
      compare(store.logsError, types[i] + ": m", types[i])
      compare(store.logsText, "kept", types[i] + " keeps the last text")
      compare(store.logsLoading, false)
      compare(store.amStatus, "ok", types[i] + " is not a snapshot failure")
      compare(store.lastError, "")
      compare(store.runs.length, 1)
    }
    store.refreshLogs()
    reply(store.logsRunner.current, "Traceback (most recent call last):\n  oops {not json", 1)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 1).")
    store.refreshLogs()
    reply(store.logsRunner.current, "", 0)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 0).")
    store.refreshLogs()
    reply(store.logsRunner.current, "[]", 0)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 0).")
    compare(store.logsText, "kept")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refreshLogs()
    reply(store.logsRunner.current, logsReply("new\n"), 0)
    compare(store.logsError, "", "a good reply clears the error")
    compare(store.logsText, "new")
  }

  function test_only_the_latest_logs_fetch_is_applied() {
    var store = opened(); if (!store) return
    var first = store.logsRunner.current
    store.selectAttempt(tc.doneCard, "spec", 1)
    var second = store.logsRunner.current
    compare(first.running, false, "the older fetch is stopped")
    reply(second, logsReply("spec text\n"), 0)
    compare(store.logsText, "spec text")
    reply(first, logsReply("explore text\n"), 0)
    compare(store.logsText, "spec text", "a late reply for an older selection changes nothing")
  }

  // Review Focus 1.
  function test_selecting_another_attempt_clears_the_old_text_but_refresh_keeps_it() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("first\n"), 0)
    store.refreshLogs()
    compare(store.logsText, "first", "a refresh keeps the text until its reply")
    compare(store.logsLoading, true)
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(store.logsText, "", "another attempt's text is never shown under this heading")
    compare(store.logsFetchedMs, 0)
    compare(store.logsError, "")
    compare(store.logsTruncated, false)
    compare(store.logsLoading, true)
  }

  function test_changing_the_selected_run_resets_to_its_default_attempt() {
    var store = makeWithProject(rootA); if (!store) return
    // r2 is the done capture: runs.json's second row with status-done.json's
    // `am status`, under the test's run id and repo dir.
    var r2 = F.load("runs.json").data.runs[1]
    r2.id = "r2"
    r2.repo_dir = tc.rootA
    r2.status = F.load("status-done.json").data
    r2.status.run.id = "r2"
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), r2]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("r1 text\n"), 0)
    store.selectAttempt(tc.doneCard, "spec", 1)
    store.selectedRunId = "r2"
    compare(store.selectedAttempt.card_id, "22153f5f-9632-4b5f-a7dd-664c39d89e5c")
    compare(store.selectedAttempt.phase, "review")
    compare(store.selectedAttempt.attempt, 1)
    compare(store.logsText, "")
    compare(store.logsFetchedMs, 0)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r2|22153f5f-9632-4b5f-a7dd-664c39d89e5c|review|1")
    var pending = store.logsRunner.current
    store.selectedRunId = ""
    compare(store.selectedAttempt, null, "clearing the run clears the selection")
    compare(store.logsText, "")
    compare(store.logsLoading, false)
    compare(store.logsStatus, "")
    compare(pending.running, false, "the pending fetch is stopped")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "", "and its late reply is dropped")
  }

  function test_a_project_switch_clears_the_logs_and_drops_the_late_reply() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    store.refreshLogs()
    var pending = store.logsRunner.current
    store.project = rootB
    compare(store.selectedAttempt, null)
    compare(store.logsText, "")
    compare(store.logsTruncated, false)
    compare(store.logsFetchedMs, 0)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.logsStatus, "")
    compare(store.logsRunner.guard, "/home/u/b")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "", "A's late logs reply changes nothing")
  }

  function test_logs_add_no_timer_and_none_runs_while_idle() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var timers = []
    for (var i = 0; i < store.data.length; i++) {
      var o = store.data[i]
      if (o && typeof o.interval === "number" && typeof o.repeat === "boolean") timers.push(o.objectName)
    }
    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer,toastTimer", "the logs add no timer")
    compare(store.debounceTimer.running, false)
    compare(store.livenessTimer.running, false)
    compare(store.staleTimer.running, false)
    compare(store.pollTimer.running, false)
    compare(store.pendingTimer.running, false)
  }

  // The next snapshot of project A lists `entries`.
  function snapshot(store, entries) {
    store.refresh()
    reply(store.snapshotRunner.current, okReply(entries), 0)
  }

  function test_a_snapshot_that_changes_the_attempt_status_fetches_once() {
    var store = opened("started"); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var seq = store.logsRunner.seq
    snapshot(store, [treeEntry("r1", "started")])
    compare(store.logsRunner.seq, seq, "an unchanged status fetches nothing")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}', 1)
    compare(store.logsRunner.seq, seq, "a failed snapshot fetches nothing")
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches the logs again")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
    compare(store.logsStatus, "ok")
    compare(store.logsText, "a", "the text stays until the new reply")
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "only once")
  }

  function test_a_snapshot_without_a_selected_run_fetches_no_logs() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    snapshot(store, [treeEntry("r1", "ok")])
    verify(!store.logsRunner.current, "nothing is selected")
  }

  // Review Focus 2.
  function test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears() {
    var store = makeWithProject(rootA); if (!store) return
    // synthetic: the run before any attempt exists; shape kept
    var bare = treeEntry("r1", "started")
    var stories = bare.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) stories[i].subtasks[j].phases = []
    }
    bare.status.rows = []
    reply(store.snapshotRunner.current, okReply([bare]), 0)
    store.selectedRunId = "r1"
    compare(store.selectedAttempt, null)
    verify(!store.logsRunner.current)
    snapshot(store, [treeEntry("r1", "started")])
    verify(store.selectedAttempt, "the first attempt is picked once it exists")
    compare(store.selectedAttempt.attempt, 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
  }

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

  // ---- cancel confirmation and the footer flash (S2 4.3)

  property string integrateReason: "Integrate is running; it cannot be paused or cancelled"

  // A running run whose lease is not accepting requests: am is in Integrate.
  function integrate(id) { return ctlEntry(id, "started", true, "milestone", [], false) }

  // 1 (and Review Focus 4)
  function test_refusal_of_says_why_a_control_would_not_start() {
    var bare = make(); if (!bare) return
    compare(bare.refusalOf("pause", "r1"), "This run is no longer in the snapshot", "no project")
    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false), integrate("r3"),
                          ctlEntry("r4", "done", false), running("r5"), running("constructor")]); if (!store) return
    compare(store.refusalOf("pause", "r1"), "")
    compare(store.refusalOf("cancel", "r1"), "")
    compare(store.refusalOf("resume", "r2"), "")
    compare(store.refusalOf("cancel", "r2"), "")
    compare(store.refusalOf("pause", "nope"), "This run is no longer in the snapshot")
    compare(store.refusalOf("pause", ""), "This run is no longer in the snapshot")
    compare(store.refusalOf("pause", "r3"), tc.integrateReason)
    compare(store.refusalOf("cancel", "r3"), tc.integrateReason)
    compare(store.refusalOf("cancel", "r4"), "The run has finished")
    compare(store.refusalOf("resume", "r1"), "The run is still running")
    compare(store.refusalOf("bogus", "r1"), "Unknown control")
    compare(store.refusalOf("pause", "constructor"), "", "an id like constructor is not pending")
    compare(store.refusalOf("resume", "constructor"), "The run is still running")
    compare(store.control("pause", "r5"), true)
    compare(store.refusalOf("pause", "r5"), "A request for this run is pending")
    compare(store.refusalOf("resume", "r5"), "A request for this run is pending", "pending wins over the state's reason")
    compare(store.controlRunners.length, 1, "refusalOf starts nothing")
  }

  // 2
  function test_a_flash_clears_itself_and_a_new_one_restarts_the_clock() {
    var store = make(); if (!store) return
    compare(store.flashText, "")
    compare(store.flashTimer.interval, 3000)
    compare(store.flashTimer.repeat, false)
    compare(store.flashTimer.running, false)
    store.flashTimer.interval = 500
    store.flash("first")
    compare(store.flashText, "first")
    compare(store.flashTimer.running, true)
    wait(300)
    store.flash("second")
    compare(store.flashText, "second", "the new text replaces the old")
    wait(300)
    compare(store.flashText, "second", "the clock restarted with the second flash")
    tryCompare(store, "flashText", "", 2000)
    compare(store.flashTimer.running, false)
    store.flash("third")
    store.flash("")
    compare(store.flashText, "")
    compare(store.flashTimer.running, false, "flash(\"\") stops the clock")
  }

  // 3
  function test_open_cancel_opens_only_for_a_cancellable_run() {
    var store = ctlStore([running("r1"), integrate("r3")]); if (!store) return
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    store.cancelText = "left over"
    store.cancelError = "old"
    compare(store.openCancel("r1"), true)
    compare(store.cancelOpen, true)
    compare(store.cancelRunId, "r1")
    compare(store.cancelText, "", "the dialog opens empty")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    store.closeCancel()
    compare(store.cancelOpen, false)
    compare(store.openCancel("r3"), false)
    compare(store.cancelOpen, false, "an Integrate run gets no dialog")
    compare(store.flashText, tc.integrateReason)
    compare(store.controlRunners.length, 0)
  }

  // 4 (and Review Focus 1)
  function test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes() {
    var store = ctlStore([running("r1")]); if (!store) return
    compare(store.confirmCancel(), false, "nothing is open")
    store.openCancel("r1")
    store.cancelText = "cancle"
    compare(store.confirmCancel(), false)
    compare(store.controlRunners.length, 0)
    compare(store.cancelOpen, true)
    compare(store.cancelError, "", "a wrong word is not an error")
    store.cancelText = " Cancel "
    compare(store.confirmCancel(), true)
    compare(store.pending.r1, "cancel")
    compare(store.controlRunners.length, 1)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|r1|/home/u/my proj")
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.confirmCancel(), false, "a second confirm finds the dialog closed")
    compare(store.controlRunners.length, 1)
  }

  // 5 (D6, Review Focus 2)
  function test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.openCancel("r2")
    store.cancelText = "cancel"
    store.control("pause", "r2")
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "A request for this run is pending")
    compare(store.cancelOpen, true)
    compare(store.controlRunners.length, 1, "only the pause")
    store.closeCancel()

    store.openCancel("r1")
    store.cancelText = "cancel"
    snapshot(store, [ctlEntry("r1", "done", false)])
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "The run has finished")
    compare(store.cancelOpen, true, "the dialog stays for the user to read why")
    compare(store.cancelRunId, "r1")
    compare(store.pending.r1, undefined)
    snapshot(store, [])
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "This run is no longer in the snapshot")
    compare(store.cancelOpen, true)
    compare(store.controlRunners.length, 1, "no cancel was ever launched")
  }

  // 6
  function test_a_project_switch_closes_the_dialog_and_clears_the_flash() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.openCancel("r1")
    store.cancelText = "can"
    store.cancelError = "x"
    store.flash("The run has finished")
    store.project = rootB
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    compare(store.flashTimer.running, false)
  }

  // ---- alerts: the toasts (S2 4.4)

  function escalated(id) { return entry(id, "escalated", false) }
  function toastIds(store) { return store.toasts.map(function(t) { return t.id }).join(",") }

  // An active store on project A whose first snapshot listed `entries`: that
  // snapshot only armed the alerts.
  function armedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    compare(store.alertsArmed, true, "the first good snapshot while open arms the alerts")
    compare(store.toasts.length, 0, "and raises nothing")
    return store
  }

  // 1
  function test_no_toast_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    compare(store.alertsArmed, false)
    compare(store.toasts.length, 0)
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false, "a closed panel never arms")
  }

  // 2
  function test_a_run_that_turns_escalated_raises_one_toast() {
    var store = activeStore(rootA); if (!store) return
    compare(store.toastMs, 8000)
    reply(store.snapshotRunner.current, okReply([escalated("a"), running("b")]), 0)
    compare(store.toasts.length, 0, "the first snapshot after opening never replays history")
    compare(store.alertsArmed, true)
    var before = Date.now()
    snapshot(store, [escalated("a"), escalated("b")])
    compare(store.toasts.length, 1)
    var t = store.toasts[0]
    compare(t.id, "b")
    compare(t.title, "m-b")
    compare(t.state, "escalated")
    compare(t.reason, Runs.escalationReason(store.runById("b")))
    compare(t.reason, "escalated")
    compare(typeof t.key, "number")
    verify(t.expiresMs >= before + 8000 && t.expiresMs <= Date.now() + 8000, "it expires 8 s from now")
  }

  // 3
  function test_a_run_still_escalated_raises_nothing_again() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    var key = store.toasts[0].key
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    compare(store.toasts[0].key, key, "the same toast, not a new one")
  }

  // 4 (Review focus: reopening never replays history)
  function test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), running("b")])
    compare(store.toasts.length, 1)
    store.active = false
    compare(store.toasts.length, 0, "a toast never outlives the panel opening")
    compare(store.alertsArmed, false)
    store.active = true
    compare(store.alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("a"), dead("b")]), 0)
    compare(store.toasts.length, 0, "b died while the panel was closed: not replayed")
    compare(store.alertsArmed, true)
    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(toastIds(store), "c")
  }

  // Review Focus 1 (D3)
  function test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    var late = store.snapshotRunner.current
    store.active = false
    reply(late, okReply([escalated("a")]), 0)
    compare(store.runs[0].status, "escalated", "the snapshot itself is still applied")
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false)
  }

  // 5
  function test_am_missing_disarms_and_a_failed_snapshot_does_not() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "AmMissing", message: "am is not installed" } }) + "\n", 1)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 0, "the first good snapshot after am came back raises nothing")
    compare(store.alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "b", "the one after that compares normally")

    var other = armedStore([running("x")]); if (!other) return
    other.refresh()
    reply(other.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(other.alertsArmed, true, "a failed snapshot keeps the baseline")
    other.refresh()
    reply(other.snapshotRunner.current, "garbage\n", 1)
    compare(other.alertsArmed, true)
    snapshot(other, [escalated("x")])
    compare(toastIds(other), "x")
  }

  // 6
  function test_five_alerts_in_one_snapshot_leave_the_last_three_toasts() {
    var store = armedStore([]); if (!store) return
    snapshot(store, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(toastIds(store), "r3,r4,r5")
    verify(store.toasts[0].key < store.toasts[1].key && store.toasts[1].key < store.toasts[2].key, "keys only grow")
    compare(store.toasts[0].state, "dead")
    compare(store.toasts[0].reason, "process died")
  }

  // 7
  function test_a_run_that_alerts_again_replaces_its_own_toast() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    var oldKey = store.toasts[0].key
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a", "a's old toast went and its new one is the newest")
    compare(store.toasts[1].state, "dead")
    compare(store.toasts[1].reason, "process died")
    verify(store.toasts[1].key > oldKey, "a new key")
  }

  // 8
  function test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    var timer = store.toastTimer
    compare(timer.objectName, "toastTimer")
    compare(timer.interval, 250)
    compare(timer.repeat, true)
    compare(timer.running, false, "no toast: no timer")
    snapshot(store, [escalated("a"), running("b")])
    compare(timer.running, true)
    var aExpires = store.toasts[0].expiresMs
    store.toastMs = 60000
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    store.expireToasts(aExpires - 1)
    compare(toastIds(store), "a,b", "not yet")
    store.expireToasts(aExpires)
    compare(toastIds(store), "b", "expiresMs <= now goes")
    store.dismissAllToasts()
    compare(timer.running, false, "nothing left: no timer")
    store.toastMs = 50
    snapshot(store, [escalated("a"), dead("b")])
    compare(store.toasts.length, 1)
    tryVerify(function() { return store.toasts.length === 0 }, 2000, "the timer dropped the expired toast")
    compare(timer.running, false)
  }

  // 9 (and Review Focus 2)
  function test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    var keyA = store.toasts[0].key
    store.dismissToast(-12345)
    compare(toastIds(store), "a,b", "an unknown key changes nothing")
    store.dismissToast(keyA)
    compare(toastIds(store), "b")
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a")
    store.dismissToast(keyA)
    compare(toastIds(store), "b,a", "a's stale key leaves its newer toast")
    store.dismissAllToasts()
    compare(store.toasts.length, 0)
  }

  // 10 (the toast half; Task 2 pins the setting half)
  function test_a_project_switch_empties_the_toasts_and_disarms() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    store.project = rootB
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("z")]), 0)
    compare(store.toasts.length, 0, "B's first snapshot raises nothing")
    compare(store.alertsArmed, true)
  }

  // ---- alerts: the setting and the desktop notifications (S2 4.4)

  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  function runSettings(notify) {
    return JSON.stringify({ verify: [], allowNoVerification: false, notifyOnEscalation: notify }) + "\n"
  }

  // 10 (the setting half)
  function test_a_project_switch_resets_the_switch_and_loads_the_new_projects_setting() {
    var store = makeWithProject(rootA); if (!store) return
    var loadA = store.settingsLoadRunner.current
    verify(loadA, "selecting a project loads its run settings")
    compare(argv(loadA), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    compare(loadA.command.length, 4)
    compare(loadA.launchGuard, "/home/u/my proj")
    reply(loadA, runSettings(true), 0)
    compare(store.notifyOnEscalation, true)
    store.project = rootB
    compare(store.notifyOnEscalation, false, "off until B's own reply")
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    var loadB = store.settingsLoadRunner.current
    verify(loadB !== loadA, "a new load")
    compare(argv(loadB), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(loadB.launchGuard, "/home/u/b", "the launch is guarded by the NEW project")
    var seq = store.settingsLoadRunner.seq
    store.project = ""
    compare(store.settingsLoadRunner.seq, seq, "no project: nothing is loaded")
    compare(store.settingsLoadRunner.guard, "")
  }

  // 11
  function test_the_load_reply_sets_the_switch_and_a_garbled_one_leaves_it_off() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, runSettings(true), 0)
    compare(store.notifyOnEscalation, true)
    compare(store.notifySaved, true)
    var other = makeWithProject(rootA); if (!other) return
    reply(other.settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(other.notifyOnEscalation, false)
    compare(other.notifySaved, false)
    var third = makeWithProject(rootA); if (!third) return
    reply(third.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: "yes" }) + "\n", 0)
    compare(third.notifyOnEscalation, false, "only a real true turns it on")
  }

  // Review Focus 3
  function test_a_late_load_reply_for_the_old_project_is_dropped() {
    var store = makeWithProject(rootA); if (!store) return
    var loadA = store.settingsLoadRunner.current
    store.project = rootB
    reply(loadA, runSettings(true), 0)
    compare(store.notifyOnEscalation, false, "A's setting never shows in B")
    compare(store.notifySaved, false)
  }

  // 12
  function test_with_the_setting_on_each_alert_launches_its_own_notification() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    compare(store.notifyRunners.length, 0)
    store.notifyOnEscalation = true
    snapshot(store, [escalated("a"), dead("b")])
    compare(store.notifyRunners.length, 2, "one runner per alert")
    var first = store.notifyRunners[0].current, second = store.notifyRunners[1].current
    compare(argv(first), tc.notifyCmd + "m-a|escalated")
    compare(argv(second), tc.notifyCmd + "m-b|process died")
    compare(first.running, true, "the second launch did not stop the first")
    compare(second.running, true)
    compare(first.launchGuard, "")
    reply(first, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(store.notifyRunners.length, 1)
    reply(second, "garbage\n", 1)
    compare(store.notifyRunners.length, 0, "a failed notification goes too")
    compare(toastIds(store), "a,b", "the replies change nothing else")
    compare(store.flashText, "")

    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(store.notifyRunners.length, 1)
    var proc = store.notifyRunners[0].current
    store.project = rootB
    compare(proc.running, true, "a project switch does not stop a launched notification")
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(store.notifyRunners.length, 0)

    var off = armedStore([running("a")]); if (!off) return
    snapshot(off, [escalated("a")])
    compare(off.toasts.length, 1)
    compare(off.notifyRunners.length, 0, "setting off: toasts only")

    var five = armedStore([]); if (!five) return
    five.notifyOnEscalation = true
    snapshot(five, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(five.toasts.length, 3)
    compare(five.notifyRunners.length, 5, "every alert notifies, even those whose toast was capped away")
  }

  // 1 (the notification half)
  function test_no_notification_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    store.notifyOnEscalation = true
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(store.notifyRunners.length, 0)
    compare(store.toasts.length, 0)
  }

  // 13
  function test_the_switch_saves_at_once_and_a_failed_save_puts_it_back() {
    var store = makeWithProject(rootA); if (!store) return
    compare(store.setNotifyOnEscalation(true), true)
    compare(store.notifyOnEscalation, true, "the switch flips at once")
    compare(store.notifyTouched, true)
    var save = store.settingsSaveRunner.current
    verify(save, "a save was launched")
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + 'set-run-settings|/home/u/my proj|{"notifyOnEscalation":true}')
    compare(save.launchGuard, "/home/u/my proj")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true)
    compare(store.flashText, "")
    compare(store.setNotifyOnEscalation(false), true)
    compare(store.notifyOnEscalation, false)
    compare(argv(store.settingsSaveRunner.current), tc.viewerCmd + 'set-run-settings|/home/u/my proj|{"notifyOnEscalation":false}')
    reply(store.settingsSaveRunner.current, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, true, "back to the value last saved")
    compare(store.notifySaved, true)
    compare(store.flashText, "Notify on escalation could not be saved")
    store.flash("")
    store.setNotifyOnEscalation(false)
    reply(store.settingsSaveRunner.current, "garbage\n", 1)
    compare(store.notifyOnEscalation, true, "an unreadable reply is a failure too")
    compare(store.flashText, "Notify on escalation could not be saved")
  }

  // Review Focus 4
  function test_a_save_reply_for_a_project_the_user_left_changes_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    store.setNotifyOnEscalation(true)
    var save = store.settingsSaveRunner.current
    store.project = rootB
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.flashText, "", "no flash about A in B")
  }

  // 14
  function test_a_load_reply_after_the_user_toggled_is_ignored() {
    var store = makeWithProject(rootA); if (!store) return
    var load = store.settingsLoadRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, runSettings(false), 0)
    compare(store.notifyOnEscalation, true)
  }

  // 15
  function test_without_a_project_the_switch_does_nothing() {
    var store = make(); if (!store) return
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    compare(store.notifyRunners.length, 0)
    compare(store.setNotifyOnEscalation(true), false)
    compare(store.notifyOnEscalation, false)
    compare(store.notifyTouched, false)
    verify(!store.settingsSaveRunner.current, "nothing was launched")
    verify(!store.settingsLoadRunner.current, "nothing was loaded")
  }

  // ---- dispatch (S3 3.1)

  property string previewCmd: "python3|/plugin/core/backend/runs/dispatch-preview.py|"
  property string startCmd: "python3|/plugin/core/backend/runs/start-run.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // 35
  function test_run_settings_kept_even_after_notify_touched() {
    var store = makeWithProject(rootA); if (!store) return
    compare(Object.keys(store.runSettings).length, 0, "{} until the reply")
    var load = store.settingsLoadRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, dispatchSettings(), 0)
    compare(store.notifyOnEscalation, true, "the switch keeps the user's value")
    compare(store.runSettings.prefixHistory.length, 1)
    compare(store.runSettings.prefixHistory[0], "old")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.confirmDispatch, true)
    compare(store.runSettings.verify[0], "uv run pytest")
    compare(store.runSettings.notifyOnEscalation, false, "the object is kept as it was read")
  }

  function test_run_settings_follow_the_project() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    compare(store.runSettings.parallelism, 4)
    store.project = rootB
    compare(Object.keys(store.runSettings).length, 0, "a project switch forgets A's settings")
    reply(store.settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(Object.keys(store.runSettings).length, 0, "an unreadable reply is {}")
    var other = makeWithProject(rootA); if (!other) return
    reply(other.settingsLoadRunner.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(other.runSettings.parallelism, 9)
  }

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // Project A with its run settings read (dispatchSettings).
  function dispatchStore() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    return store
  }

  // Every dispatch field at its "none" value.
  function checkDispatchIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
    compare(store.dispatchTarget, null, label + ": target")
    compare(store.dispatchForm, null, label + ": form")
    compare(store.dispatchPreview, null, label + ": preview")
    compare(store.dispatchError, "", label + ": error")
    compare(store.dispatchErrorType, "", label + ": error type")
    compare(store.dispatchErrors.length, 0, label + ": errors")
    compare(store.dispatchSuggest, null, label + ": suggest")
    compare(store.dispatchRunId, "", label + ": run id")
    compare(store.dispatchMessage, "", label + ": message")
    compare(store.dispatchLog, "", label + ": log")
    compare(store.dispatchLogTail, "", label + ": log tail")
    compare(store.dispatchExitCode, null, label + ": exit code")
  }

  // 1 (dispatchStart() from idle is checked in Task 5's test 21)
  function test_dispatch_starts_idle() {
    var store = make(); if (!store) return
    checkDispatchIdle(store, "fresh")
    compare(store.dispatchStartRunners.length, 0)
    compare(store.dispatchDebounceTimer.running, false)
    verify(!store.dispatchDefaultsRunner.current)
    verify(!store.dispatchPreviewRunner.current)
    compare(store.closeDispatch(), true, "closing an idle dispatch is fine")
    checkDispatchIdle(store, "after close")
  }

  // 2
  function test_open_without_project_is_refused() {
    var store = make(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), false)
    checkDispatchIdle(store, "no project")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
  }

  // 3
  function test_open_milestone_goes_previewing_and_asks_defaults() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, JSON.stringify({ verify: ["uv run pytest", "  "], allowNoVerification: true,
      notifyOnEscalation: false, prefixHistory: [], parallelism: 6, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTarget.command, "milestone")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(proc.command[3], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.base, "", "no base until the lookup replies")
    compare(form.prefix, "m3")
    compare(form.verify.length, 1, "the stored non-blank commands")
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 6)
    compare(form.allowNoVerification, false, "the opt-out is never pre-ticked")
    verify(!store.dispatchPreviewRunner.current, "no preview before the default branch is known")
    compare(store.dispatchDebounceTimer.running, false)
  }

  function test_open_before_the_settings_reply_starts_from_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.verify.length, 0)
    compare(store.dispatchForm.parallelism, 4)
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    compare(store.dispatchForm.verify.length, 0, "a late settings reply does not touch the open form")
    compare(store.runSettings.verify[0], "uv run pytest", "but it is kept for the next opening")
  }

  // 4
  function test_open_story_is_refused_with_its_milestone() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.s1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchError, "A story is dispatched through its milestone")
    compare(store.dispatchSuggest.id, "m1")
    compare(store.dispatchSuggest.title, "M3 Document runs")
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchForm, null, "a refused target has no form")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
    verify(!store.dispatchPreviewRunner.current)
  }

  // 5
  function test_open_done_card_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.d1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.openDispatch(null, cards), false)
    compare(store.dispatchError, "No card to dispatch")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  function test_close_and_reopen_drop_the_pending_lookup() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var first = store.dispatchDefaultsRunner.current
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
    compare(first.running, false, "the lookup is stopped")
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchState, "refused")
    compare(store.openDispatch(cards.m1, cards), true, "opening again replaces a refused target")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchSuggest, null)
    verify(store.dispatchDefaultsRunner.current !== first, "a fresh lookup per opening")
  }

  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  // Project A with milestone m1 opened and its default branch `main` read: the
  // first preview is in flight.
  function previewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest"

  // 6
  function test_defaults_reply_sets_base_and_launches_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchDebounceTimer.running, false, "the check runs at once, no debounce")
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a preview was launched")
    compare(argv(proc), tc.previewCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.command[2], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.command[12], "uv run pytest", "a command with spaces is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  // 8 + Review Focus 2
  function test_defaults_failure_sends_no_base() {
    var replies = [JSON.stringify({ ok: false, error: { type: "NoDefaultBranch", message: "detached HEAD" } }) + "\n",
                   "Traceback: boom\n",
                   defaultsOk("   "),
                   JSON.stringify({ ok: true, data: { default_branch: null, source: "" } }) + "\n",
                   JSON.stringify({ ok: true }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      store.openDispatch(cards.m1, cards)
      reply(store.dispatchDefaultsRunner.current, replies[i], 1)
      compare(store.dispatchForm.base, "", "reply " + i + " leaves base blank")
      var proc = store.dispatchPreviewRunner.current
      verify(proc, "reply " + i + ": the check still runs")
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest",
              "reply " + i + ": no --base-branch pair")
    }
    var padded = dispatchStore(); if (!padded) return
    var map = dispatchCards()
    padded.openDispatch(map.m1, map)
    reply(padded.dispatchDefaultsRunner.current, defaultsOk("  main \n"), 0)
    compare(padded.dispatchForm.base, "main", "the branch is trimmed")
    compare(padded.dispatchPreviewRunner.current.command[6], "main")
  }

  // 10
  function test_preview_ok_goes_ready_with_summary() {
    var store = previewingStore(); if (!store) return
    compare(store.dispatchPreview, null)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done")
    compare(store.dispatchPreview.integrate, "Integrate → m3-integrate")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 11
  function test_preview_refusal_goes_refused_verbatim() {
    var store = previewingStore(); if (!store) return
    var message = "milestone m1 is claimed by run 20261005T010000Z-abcd (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchPreview, null)
    var untyped = previewingStore(); if (!untyped) return
    reply(untyped.dispatchPreviewRunner.current,
          JSON.stringify({ ok: false, error: { type: 7, message: "dependency cycle: s1 -> s2 -> s1" } }) + "\n", 0)
    compare(untyped.dispatchState, "refused")
    compare(untyped.dispatchError, "dependency cycle: s1 -> s2 -> s1")
    compare(untyped.dispatchErrorType, "", "a type that is not a string is unknown")
  }

  // 12
  function test_preview_unreadable_goes_refused() {
    var replies = ["", "Traceback: boom\n", "[1, 2]\n",
                   JSON.stringify({ ok: false, error: { type: "X", message: "  " } }) + "\n",
                   JSON.stringify({ ok: false, error: "boom" }) + "\n",
                   JSON.stringify({ ok: false, error: null }) + "\n",
                   JSON.stringify({ ok: "yes" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = previewingStore(); if (!store) return
      reply(store.dispatchPreviewRunner.current, replies[i], 1)
      compare(store.dispatchState, "refused", "reply " + i)
      compare(store.dispatchError, "The preview could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchPreview, null, "reply " + i)
    }
  }

  // 14
  function test_invalid_form_is_refused_without_launch() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch("board", cards), true)
    compare(store.dispatchTarget.level, "board")
    compare(store.dispatchForm.prefix, "", "the board has no milestone title to stem")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Form")
    compare(store.dispatchErrors.length, 1)
    compare(store.dispatchErrors[0].field, "prefix")
    compare(store.dispatchError, "Enter a branch prefix")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  // 20 (the preview half)
  function test_subtask_goes_ready_without_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), true)
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "m3", "the stem of the subtask's milestone")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview, null, "am has no dry run for one card")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  function test_a_closed_dispatch_drops_the_late_defaults_reply() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var lookup = store.dispatchDefaultsRunner.current
    store.closeDispatch()
    reply(lookup, defaultsOk("main"), 0)
    checkDispatchIdle(store, "after the late reply")
    verify(!store.dispatchPreviewRunner.current, "no preview")
  }

  // 7
  function test_defaults_reply_keeps_a_user_set_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("base", "develop"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "develop", "the user's base wins over the lookup")
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
  }

  // 9
  function test_debounce_waits_for_defaults() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("prefix", "m3b"), true)
    compare(store.dispatchDebounceTimer.running, true)
    fire(store.dispatchDebounceTimer)
    verify(!store.dispatchPreviewRunner.current, "nothing launched before the default branch is known")
    compare(store.dispatchState, "previewing")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the defaults reply checks the form")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3b|--max-concurrent|4|--verify|uv run pytest")

    var early = dispatchStore(); if (!early) return
    early.openDispatch(cards.m1, cards)
    early.setDispatchField("parallelism", 2)
    reply(early.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(early.dispatchDebounceTimer.running, false, "the defaults reply's check replaces the pending one")
    compare(early.dispatchPreviewRunner.current.command[10], "2")
  }

  // 13
  function test_board_preview_argv() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch("board", cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused", "the board starts with no prefix")
    compare(store.setDispatchField("prefix", " all "), true)
    fire(store.dispatchDebounceTimer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the board is previewed")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|board|--base-branch|main|--branch-prefix|all|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 12)
    var board = { board: true, levels: [{ level: 0, milestones: [{ milestone_id: "m1", title: "M3", branch_prefix: "m3",
                                                                   base_branch: "main", plan: dispatchDryRun() }] }] }
    reply(proc, previewOk(board), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "1 milestone, 3 subtasks")
    compare(store.dispatchPreview.board, true)
  }

  // 15 + Review Focus 1
  function test_allow_no_verification_flag() {
    var store = previewingStore(); if (!store) return
    store.setDispatchField("verify", [])
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "no command and no opt-out")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "previewing")
    var proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--allow-no-verification")
    store.setDispatchField("verify", ["", "  ", "-x make check", "uv run pytest"])
    fire(store.dispatchDebounceTimer)
    proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
    compare(proc.command[12], "-x make check", "a command that starts with a dash is one verbatim argument")
    store.setDispatchField("allowNoVerification", "yes")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchPreviewRunner.current.command[store.dispatchPreviewRunner.current.command.length - 1], "uv run pytest",
            "only a real true sends the opt-out")
  }

  // Review Focus 4 (the form half)
  function test_a_verify_value_that_is_not_a_list_is_refused_not_thrown() {
    var store = previewingStore(); if (!store) return
    compare(store.setDispatchField("verify", "uv run pytest"), true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    store.setDispatchField("parallelism", "4")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "the store converts nothing")
    compare(store.dispatchErrors[0].field, "parallelism")
    store.setDispatchField("parallelism", 4)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--allow-no-verification")
  }

  // 16
  function test_change_restarts_400ms_debounce_and_one_preview_per_burst() {
    var store = previewingStore(); if (!store) return
    var timer = store.dispatchDebounceTimer
    compare(timer.objectName, "dispatchDebounceTimer")
    compare(timer.interval, 400)
    compare(timer.repeat, false)
    var first = store.dispatchPreviewRunner.current
    compare(store.setDispatchField("prefix", "a"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("prefix", "ab"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("parallelism", 2), true)
    compare(store.dispatchState, "previewing")
    compare(timer.running, true)
    verify(store.dispatchPreviewRunner.current === first, "nothing launched during the burst")
    compare(first.running, false, "the preview in flight was cancelled")
    fire(timer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc !== first, "one preview for the burst")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|ab|--max-concurrent|2|--verify|uv run pytest")
  }

  // 17
  function test_latest_preview_wins() {
    var store = previewingStore(); if (!store) return
    var first = store.dispatchPreviewRunner.current
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    var second = store.dispatchPreviewRunner.current
    verify(second !== first, "a second preview")
    reply(first, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "previewing", "the older preview's reply is dropped")
    compare(store.dispatchPreview, null)
    reply(second, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    verify(store.dispatchPreview !== null)
  }

  // 18
  function test_change_after_ready_drops_preview_and_goes_previewing() {
    var store = previewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    var form = store.dispatchForm
    var list = ["make test"]
    compare(store.setDispatchField("verify", list), true)
    list.push("rm -rf /")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchPreview, null)
    compare(form.verify[0], "uv run pytest", "the old form was not changed in place")
    compare(store.dispatchForm.verify.length, 1, "verify is copied")
    compare(store.dispatchForm.verify[0], "make test")
    compare(store.dispatchForm.prefix, "m3", "the other fields are kept")
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchDebounceTimer.running, true)
  }

  // 19
  function test_set_unknown_field_or_while_idle_is_refused() {
    var store = dispatchStore(); if (!store) return
    compare(store.setDispatchField("prefix", "x"), false, "idle")
    compare(store.dispatchForm, null)
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "A story is dispatched through its milestone")
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("branch", "x"), false, "unknown field")
    compare(store.setDispatchField("__proto__", {}), false)
    compare(store.dispatchForm.prefix, "m3", "nothing changed")
    compare(store.dispatchForm.branch, undefined)
    compare(store.dispatchDebounceTimer.running, false)
  }

  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // Project A with milestone m1's preview landed: Start is allowed.
  function readyStore() {
    var store = previewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    return store
  }

  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3","old"],"parallelism":4}'

  // 20 (the start half)
  function test_subtask_start_argv_uses_card() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.t1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchStart(), true)
    var proc = store.dispatchStartRunners[0].current
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 13)
  }

  // 21 + Review Focus 3
  function test_start_refused_unless_ready() {
    var store = dispatchStore(); if (!store) return
    compare(store.dispatchStart(), false, "idle")
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchStart(), false, "previewing")
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchStart(), false, "refused")
    compare(store.dispatchStartRunners.length, 0, "no start runner")
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStart(), false, "a fresh store")
    var ready = readyStore(); if (!ready) return
    compare(ready.dispatchStart(), true)
    compare(ready.dispatchStart(), false, "a second Start while starting")
    compare(ready.dispatchStartRunners.length, 1, "one launch for a double click")
  }

  // 22
  function test_start_argv_and_starting() {
    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    compare(store.dispatchState, "starting")
    compare(store.dispatchStartRunners.length, 1)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/my proj")
    compare(runner.guard, "", "a preview or a project switch never stops a start")
    var proc = runner.current
    compare(argv(proc), tc.startCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.running, true)
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done", "the preview stays up while starting")
  }

  // 23
  function test_change_and_close_refused_while_starting() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    compare(store.setDispatchField("prefix", "x"), false)
    compare(store.dispatchForm.prefix, "m3")
    compare(store.closeDispatch(), false)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchDebounceTimer.running, false)
  }

  // 24
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-1")
    compare(store.dispatchMessage, "")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py|/home/u/my proj")
    compare(store.dispatchStartRunners.length, 1, "the same runner writes the settings")
    verify(store.dispatchStartRunners[0] === runner)
    var save = runner.current
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson)
    compare(store.runSettings.prefixHistory.join(","), "m3,old")
    compare(store.runSettings.verify.join(","), "uv run pytest")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.allowNoVerification, false)
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0, "the runner goes after the write")
    compare(store.flashText, "")
    compare(store.dispatchState, "started")
  }

  // 25 + Review Focus 5 (run id half)
  function test_start_ok_without_run_id_emits_null() {
    var ids = [null, "", 42]
    for (var i = 0; i < ids.length; i++) {
      var store = readyStore(); if (!store) return
      var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk(ids[i], "started, run not visible yet"), 0)
      compare(store.dispatchState, "started", "run_id " + i)
      compare(store.dispatchRunId, "", "run_id " + i)
      compare(store.dispatchMessage, "started, run not visible yet")
      compare(spy.count, 1)
      compare(spy.signalArguments[0][0], null, "run_id " + i + ": not visible yet")
    }
  }

  // 26 + Review Focus 4 (the history half)
  function test_prefix_history_dedups_and_caps_at_20() {
    var store = makeWithProject(rootA); if (!store) return
    var history = ["a", "m3", "", "  ", 7, "b"]
    for (var i = 0; i < 25; i++) history.push("p" + i)
    reply(store.settingsLoadRunner.current, JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false,
      notifyOnEscalation: false, prefixHistory: history, parallelism: 4, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "  m3 ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3", "the prefix is sent trimmed")
    reply(runner.current, startOk("r-1", ""), 0)
    var expected = ["m3", "a", "b"]
    for (var j = 0; j < 17; j++) expected.push("p" + j)
    var saved = JSON.parse(runner.current.command[4])
    compare(saved.prefixHistory.length, 20)
    compare(saved.prefixHistory.join(","), expected.join(","))
    compare(store.runSettings.prefixHistory.join(","), expected.join(","))

    var bare = makeWithProject(rootA); if (!bare) return
    reply(bare.settingsLoadRunner.current, "Traceback: boom\n", 1)
    bare.openDispatch(cards.m1, cards)
    reply(bare.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    bare.setDispatchField("verify", ["make test"])
    fire(bare.dispatchDebounceTimer)
    reply(bare.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(bare.dispatchStart(), true)
    var bareRunner = bare.dispatchStartRunners[0]
    reply(bareRunner.current, startOk("r-2", ""), 0)
    compare(argv(bareRunner.current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4}')
  }

  // 27
  function test_start_failure_goes_failed_with_log() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, JSON.stringify({ ok: false, error: { type: "AmExited", message: "am run exited at once (exit 2)" },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: milestone m1 not found" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "am run exited at once (exit 2)")
    compare(store.dispatchErrorType, "AmExited")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "error: milestone m1 not found")
    compare(store.dispatchExitCode, 2)
    compare(spy.count, 0)
    compare(store.dispatchStartRunners.length, 0, "no settings write after a failed start")
    compare(store.runSettings.prefixHistory.join(","), "old", "nothing saved")
    compare(store.dispatchForm.prefix, "m3", "the form stays for another try")
  }

  // 28 + Review Focus 5 (exit code half)
  function test_start_unreadable_goes_failed() {
    var replies = ["", "Traceback: boom\n", JSON.stringify({ ok: "maybe" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, replies[i], 1)
      compare(store.dispatchState, "failed", "reply " + i)
      compare(store.dispatchError, "The launch could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchLog, "", "reply " + i)
      compare(store.dispatchExitCode, null, "reply " + i)
      compare(store.dispatchStartRunners.length, 0, "reply " + i)
    }
    var blank = readyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, JSON.stringify({ ok: false, error: { type: "SpawnFailed", message: " " },
      log: "/tmp/l", exit_code: "2", log_tail: 5 }) + "\n", 0)
    compare(blank.dispatchState, "failed")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "SpawnFailed")
    compare(blank.dispatchLog, "/tmp/l")
    compare(blank.dispatchLogTail, "", "a log tail that is not a string")
    compare(blank.dispatchExitCode, null, "an exit code that is not a number")
  }

  // 29
  function test_failed_then_change_previews_again() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, ctlFail("ClaimedError", "claimed by r-0"), 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchStart(), false, "a failed start is not retried without a new check")
    compare(store.setDispatchField("prefix", "m3-retry"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchLog, "")
    compare(store.dispatchExitCode, null)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3-retry|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 1)
  }

  // 30
  function test_settings_write_failure_flashes() {
    var replies = [JSON.stringify({ ok: false, error: { type: "Invalid", message: "x" } }) + "\n", "garbage\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      var runner = store.dispatchStartRunners[0]
      reply(runner.current, startOk("r-1", ""), 0)
      reply(runner.current, replies[i], 1)
      compare(store.flashText, "Dispatch settings could not be saved", "reply " + i)
      compare(store.dispatchState, "started", "the run still started")
      compare(store.dispatchStartRunners.length, 0)
      compare(store.notifyOnEscalation, false, "the notify switch is untouched")
      verify(!store.settingsSaveRunner.current, "the notify switch's runner is not used")
    }
  }

  function test_started_refuses_changes_and_reopening_starts_over() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.setDispatchField("prefix", "x"), false, "started")
    compare(store.dispatchStart(), false, "started")
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRunId, "")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchForm.verify[0], "uv run pytest", "the next form starts from the saved values")
  }

  // 31
  function test_project_switch_resets_dispatch_and_drops_old_preview() {
    var store = previewingStore(); if (!store) return
    var preview = store.dispatchPreviewRunner.current
    store.project = rootB
    checkDispatchIdle(store, "after the switch")
    compare(Object.keys(store.runSettings).length, 0)
    compare(preview.running, false, "A's preview is stopped")
    reply(preview, previewOk(dispatchDryRun()), 0)
    checkDispatchIdle(store, "after A's late preview")

    var pending = previewingStore(); if (!pending) return
    pending.setDispatchField("prefix", "x")
    compare(pending.dispatchDebounceTimer.running, true)
    pending.project = rootB
    compare(pending.dispatchDebounceTimer.running, false, "no check is left pending")
    checkDispatchIdle(pending, "switch during a burst")

    var cleared = previewingStore(); if (!cleared) return
    cleared.project = ""
    checkDispatchIdle(cleared, "no project")
  }

  // 32
  function test_start_result_belongs_to_its_project() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var startProc = runner.current
    store.project = rootB
    checkDispatchIdle(store, "B after the switch from starting")
    compare(startProc.running, true, "the start is not stopped")
    compare(store.dispatchStartRunners.length, 1)
    var seq = store.snapshotRunner.seq
    reply(startProc, startOk("r-1", ""), 0)
    checkDispatchIdle(store, "B after A's start landed")
    compare(spy.count, 0)
    compare(store.snapshotRunner.seq, seq, "no refresh for B")
    compare(Object.keys(store.runSettings).length, 0, "B's settings do not take A's values")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(runner.current, "garbage\n", 1)
    compare(store.flashText, "", "no flash about A in B")
    compare(store.dispatchStartRunners.length, 0)
  }

  // 32b
  function test_start_reply_after_switching_away_and_back_is_not_here() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    store.project = rootB
    store.project = rootA
    checkDispatchIdle(store, "back in A")
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(store.dispatchRunId, "")
    compare(spy.count, 0)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
  }

  // 33
  function test_start_in_other_project_does_not_stop_the_first() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var procA = store.dispatchStartRunners[0].current
    store.project = rootB
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true, "B's dispatch opens while A's start is in flight")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 2)
    compare(store.dispatchStartRunners[0].madeFor, "/home/u/my proj")
    compare(store.dispatchStartRunners[1].madeFor, "/home/u/b")
    compare(procA.running, true, "A's start is still running")
    var procB = store.dispatchStartRunners[1].current
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
    reply(procA, startOk("r-a", ""), 0)
    compare(store.dispatchState, "starting", "A's reply does not land in B's dialog")
    reply(procB, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
  }

  // 34
  function test_panel_close_closes_dispatch_but_not_a_start() {
    var store = activeStore(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    store.active = false
    checkDispatchIdle(store, "closed from ready")

    store.active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "x")
    compare(store.dispatchDebounceTimer.running, true)
    store.active = false
    compare(store.dispatchDebounceTimer.running, false, "no timer while idle")
    checkDispatchIdle(store, "closed during a burst")

    store.active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    store.active = false
    compare(store.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started", "it lands normally")
    compare(store.dispatchRunId, "r-1")
  }
}
