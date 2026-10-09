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
