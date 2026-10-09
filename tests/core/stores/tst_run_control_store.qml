// tests/core/stores/tst_run_control_store.qml
// The run controls store: control requests and their settling, the resume
// verify read, the still-waiting clock, the control error, the cancel
// confirmation, the footer flash and the notify switch. Built alone and
// driven through its `runs` and `active` inputs and settleAfterSnapshot();
// and, through a RunStore wired to it the way App wires them, a real
// snapshot reply settling a real request and each opening reading the switch.
// Stubbed Process objects stand in for every helper.
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
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"
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

  // C9
  function test_a_bare_control_store_has_the_switch_off_and_untouched() {
    var c = makeControl(); if (!c) return
    compare(c.notifyOnEscalation, false)
    compare(c.notifySaved, false)
    compare(c.notifyTouched, false)
    verify(c.settingsLoadRunner, "the load runner exists")
    verify(c.settingsSaveRunner, "the save runner exists")
    verify(!c.settingsLoadRunner.current, "nothing is loaded")
    verify(!c.settingsSaveRunner.current, "nothing is saved")
    compare(c.settingsSaveRunner.sent, false)
  }

  // C10 and Review Focus 5
  function test_the_stores_own_active_loads_the_switch_and_closing_launches_nothing() {
    var c = makeControl(); if (!c) return
    c.active = true
    var load = c.settingsLoadRunner.current
    verify(load, "the opening loads the switch")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    compare(load.command.length, 3)
    compare(load.launchGuard, "")
    var seq = c.settingsLoadRunner.seq
    c.active = false
    compare(c.settingsLoadRunner.seq, seq, "closing launches nothing")
    c.project = "/x"
    compare(c.settingsLoadRunner.seq, seq, "a project change launches no load")
    verify(!c.settingsSaveRunner.current, "and no save")
    c.active = true
    compare(c.settingsLoadRunner.seq, seq + 1, "each opening loads once")
  }

  // C11 and Review Focus 3
  function test_a_failed_save_flashes_on_this_store() {
    var c = makeControl(); if (!c) return
    c.flash("The run has finished")
    compare(c.setNotifyOnEscalation(true), true)
    compare(c.notifyOnEscalation, true)
    var save = c.settingsSaveRunner.current
    compare(argv(save), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}')
    compare(save.command.length, 4)
    compare(save.launchGuard, "")
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(c.notifyOnEscalation, false, "back to the value last saved")
    compare(c.flashText, "Notify on escalation could not be saved", "it replaces the flash showing")
    compare(c.flashTimer.running, true)
  }

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

  // ---- the notify switch (S2 4.4)

  // 8 and Review Focus 5
  function test_the_global_switch_loads_on_each_opening_with_no_project() {
    var idle = make(); if (!idle) return
    verify(!controlOf(idle).settingsLoadRunner.current, "a closed panel loads nothing")
    idle.project = tc.rootA
    verify(!controlOf(idle).settingsLoadRunner.current, "a project switch launches no global load")

    var store = make(); if (!store) return
    store.active = true
    var load = controlOf(store).settingsLoadRunner.current
    verify(load, "opening the panel loads the switch, with no project and no registry")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    compare(load.command.length, 3)
    compare(load.launchGuard, "")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true)
    compare(controlOf(store).notifySaved, true)
    store.project = tc.rootB
    compare(controlOf(store).notifyOnEscalation, true, "a project switch leaves the switch alone")
    compare(controlOf(store).notifySaved, true)
    compare(controlOf(store).notifyTouched, false)
    var seq = controlOf(store).settingsLoadRunner.seq
    store.project = ""
    compare(controlOf(store).settingsLoadRunner.seq, seq, "and launches no global load")
    store.active = false
    store.active = true
    compare(controlOf(store).settingsLoadRunner.seq, seq + 1, "each opening loads once")
    reply(controlOf(store).settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(controlOf(store).notifyOnEscalation, false, "an unreadable reply leaves it off")
    compare(controlOf(store).notifySaved, false)
    store.active = false
    store.active = true
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: "yes" }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, false, "only a real true turns it on")
    store.active = false
    store.active = true
    reply(controlOf(store).settingsLoadRunner.current, "{}\n", 0)
    compare(controlOf(store).notifyOnEscalation, false)
    store.active = false
    store.active = true
    var late = controlOf(store).settingsLoadRunner.current
    store.active = false
    reply(late, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true, "a reply after the panel closed still lands")
    store.active = true
    var older = controlOf(store).settingsLoadRunner.current
    store.active = false
    store.active = true
    reply(older, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true, "an earlier opening's reply is dropped")
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, false, "the newest opening's reply lands")
  }

  // 13
  function test_the_switch_saves_globally_and_a_failed_save_puts_it_back() {
    var store = make(); if (!store) return
    compare(controlOf(store).notifyOnEscalation, false)
    compare(controlOf(store).notifySaved, false)
    compare(controlOf(store).notifyTouched, false)
    compare(store.notifyRunners.length, 0)
    compare(controlOf(store).setNotifyOnEscalation(true), true, "no project and no registry: it still works")
    compare(controlOf(store).notifyOnEscalation, true, "the switch flips at once")
    compare(controlOf(store).notifyTouched, true)
    var save = controlOf(store).settingsSaveRunner.current
    verify(save, "a save was launched")
    compare(save.command.length, 4)
    compare(argv(save), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}')
    compare(save.launchGuard, "")
    verify(!controlOf(store).settingsLoadRunner.current, "a closed panel loads nothing")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(controlOf(store).notifySaved, true)
    compare(controlOf(store).flashText, "")
    compare(controlOf(store).setNotifyOnEscalation(false), true)
    compare(controlOf(store).notifyOnEscalation, false)
    compare(argv(controlOf(store).settingsSaveRunner.current), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":false}')
    reply(controlOf(store).settingsSaveRunner.current, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(controlOf(store).notifyOnEscalation, true, "back to the value last saved")
    compare(controlOf(store).notifySaved, true)
    compare(controlOf(store).flashText, "Notify on escalation could not be saved")
    controlOf(store).flash("")
    controlOf(store).setNotifyOnEscalation(false)
    reply(controlOf(store).settingsSaveRunner.current, "garbage\n", 1)
    compare(controlOf(store).notifyOnEscalation, true, "an unreadable reply is a failure too")
    compare(controlOf(store).flashText, "Notify on escalation could not be saved")
  }

  // 10
  function test_a_save_reply_survives_a_project_switch() {
    var store = makeWithProject(rootA); if (!store) return
    controlOf(store).setNotifyOnEscalation(true)
    var save = controlOf(store).settingsSaveRunner.current
    store.project = rootB
    compare(controlOf(store).notifyOnEscalation, true, "the switch is viewer-wide")
    compare(controlOf(store).notifyTouched, true)
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(controlOf(store).notifyOnEscalation, false, "rolled back to the value last saved")
    compare(controlOf(store).notifySaved, false)
    compare(controlOf(store).flashText, "Notify on escalation could not be saved")
    controlOf(store).flash("")
    controlOf(store).setNotifyOnEscalation(true)
    var second = controlOf(store).settingsSaveRunner.current
    store.project = ""
    reply(second, JSON.stringify({ ok: true }) + "\n", 0)
    compare(controlOf(store).notifySaved, true, "an ok reply after a switch is applied")
    compare(controlOf(store).notifyOnEscalation, true)
  }

  // 11
  function test_a_save_in_flight_survives_a_reopening() {
    var store = make(); if (!store) return
    store.active = true
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    controlOf(store).setNotifyOnEscalation(true)
    var save = controlOf(store).settingsSaveRunner.current
    store.active = false
    store.active = true
    compare(controlOf(store).notifyTouched, true, "a save is in flight: the touch stays")
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true, "the new load cannot undo the user's choice")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(controlOf(store).notifySaved, true, "the save reply settles notifySaved")
    store.active = false
    store.active = true
    compare(controlOf(store).notifyTouched, false, "no save in flight: the next opening reads again")
    reply(controlOf(store).settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, false)
    compare(controlOf(store).notifySaved, false)
  }

  // 14
  function test_a_load_reply_after_the_user_toggled_is_ignored() {
    var store = makeWithProject(rootA); if (!store) return
    store.active = true
    var load = controlOf(store).settingsLoadRunner.current
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    controlOf(store).setNotifyOnEscalation(true)
    reply(load, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(controlOf(store).notifyOnEscalation, true)
    compare(controlOf(store).notifyTouched, true)
  }
}
