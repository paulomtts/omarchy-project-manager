// tests/core/stores/tst_run_alerts_service.qml
// The service entry point: it builds as the shell's ensureService builds it
// (createObject(null), no properties), declares none of the properties the
// shell injects, and its backendDir is the plugin's real core/backend/.
// It keeps runs-alerts.py running under the restart policy and turns its alert
// lines into alertReceived. The stub Process spawns nothing: each test plays
// the helper by emitting stdout.read(line) and exited(code) on helperProc.
// Each alert runs its own pipeline: get-global-settings, then (switch on) one
// runs-snapshot.py of the alert's root, then one notify.py. Tests play each
// HelperRunner's process with reply(proc, stdout, code).
import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunAlertsService"
  when: windowShown
  width: 400; height: 400

  Component { id: hostC; Item { width: 400; height: 400 } }
  Component { id: spyC; SignalSpy { signalName: "alertReceived" } }

  // A directory listing is the only filesystem read QML offers here.
  FolderListModel { id: folder; showDirs: true; showFiles: true; showDotAndDotDot: false }

  function fileExists(path) {
    var slash = path.lastIndexOf("/")
    var dir = path.substring(0, slash)
    var name = path.substring(slash + 1)
    folder.folder = "file://" + dir
    // The model loads asynchronously and still lists the previous folder (at
    // first, the working directory) for a while: poll until it lists entries
    // of `dir` itself or the budget runs out.
    for (var t = 0; t < 40; t++) {
      if (folder.status === FolderListModel.Ready && folder.count > 0
          && String(folder.get(0, "filePath")).indexOf(dir + "/") === 0) break
      tc.wait(20)
    }
    for (var i = 0; i < folder.count; i++)
      if (folder.get(i, "fileName") === name) return true
    return false
  }

  // Built exactly as the shell builds a third-party service: no parent, no properties.
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsService.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(null)
  }

  function test_it_loads_and_instantiates_without_a_parent_or_properties() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsService.qml")
    compare(comp.status, Component.Ready, comp.errorString())
    var s = comp.createObject(null)
    verify(s !== null, "createObject(null) returned null")
    s.destroy()
  }

  function test_it_can_be_created_again_after_it_was_destroyed() {
    var a = make(); if (!a) return
    var dir = a.backendDir
    a.destroy()
    wait(0)
    var b = make(); if (!b) return
    compare(b.backendDir, dir)
    b.destroy()
  }

  function test_backend_dir_is_the_absolute_core_backend_of_the_plugin() {
    var s = make(); if (!s) return
    var dir = s.backendDir
    s.destroy()
    verify(dir.indexOf("/") === 0, "not an absolute path: " + dir)
    verify(dir.indexOf("file:") === -1, "still a URL: " + dir)
    verify(dir.endsWith("/core/backend/"), dir)
    verify(fileExists(dir + "runs/runs-alerts.py"), "no runs/runs-alerts.py under " + dir)
  }

  function test_backend_dir_is_what_the_panel_hands_app() {
    var s = make(); if (!s) return
    var dir = s.backendDir
    s.destroy()
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    verify(p !== null, "Panel did not build")
    compare(dir, p.app.backendDir)
  }

  function test_the_shell_injects_nothing() {
    var s = make(); if (!s) return
    verify("backendDir" in s, "the in-operator sees no declared property")
    verify(!("shell" in s), "declares shell")
    verify(!("manifest" in s), "declares manifest")
    verify(!("omarchyPath" in s), "declares omarchyPath")
    verify(!("pluginRegistry" in s), "declares pluginRegistry")
    verify(!("barWidgetRegistry" in s), "declares barWidgetRegistry")
    s.destroy()
  }

  // One stdout line of the current launch: a string as is, anything else as JSON.
  function line(s, obj) {
    s.helperProc.stdout.read(typeof obj === "string" ? obj : JSON.stringify(obj))
  }

  function envelope(type) {
    return { ok: false, error: { type: type, message: "the " + type + " message" } }
  }

  function retryWarning(type) {
    return "RunAlertsService: " + type + ": the " + type + " message -- retrying in 300 s"
  }

  function stopWarning(type) {
    return "RunAlertsService: " + type + ": the " + type + " message -- stopped"
  }

  function alertSpy(s) {
    return createTemporaryObject(spyC, tc, { target: s })
  }

  function test_it_launches_the_helper_on_creation() {
    var s = make(); if (!s) return
    compare(s.status, "watching")
    verify(s.helperProc !== null, "no helperProc")
    compare(s.helperProc.running, true)
    compare(s.helperProc.command, ["python3", s.backendDir + "runs/runs-alerts.py"])
    compare(s.retryTimer.running, false)
    compare(s.lastError, "")
    s.destroy()
  }

  // A retryable envelope + exit 1: one warn, waiting 300 s, then the timer
  // relaunches a new process with the same command.
  function retryableFailure_waits_then_relaunches(type) {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning(type))
    var first = s.helperProc
    line(s, envelope(type))
    first.exited(1)
    compare(s.status, "waiting")
    compare(s.retryTimer.running, true)
    compare(s.retryTimer.interval, 300000)
    compare(s.retryTimer.repeat, false)
    compare(s.lastError, type + ": the " + type + " message")
    compare(s.helperProc, null)
    s.retryTimer.triggered()
    compare(s.status, "watching")
    verify(s.helperProc !== null, "no relaunch")
    verify(s.helperProc !== first, "the old process came back")
    compare(s.helperProc.command, ["python3", s.backendDir + "runs/runs-alerts.py"])
    compare(s.helperProc.running, true)
    compare(s.retryTimer.running, false)
    compare(s.lastError, type + ": the " + type + " message")
    s.destroy()
  }

  function test_am_missing_waits_then_relaunches() {
    retryableFailure_waits_then_relaunches("AmMissing")
  }

  function test_helper_error_waits_then_relaunches() {
    retryableFailure_waits_then_relaunches("HelperError")
  }

  function test_store_busy_waits_like_helper_error() {
    retryableFailure_waits_then_relaunches("StoreBusyError")
  }

  function test_a_non_zero_exit_without_envelope_waits() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning("RunAlertsService: runs-alerts.py exited 2 -- retrying in 300 s")
    s.helperProc.exited(2)
    compare(s.status, "waiting")
    compare(s.retryTimer.running, true)
    compare(s.lastError, "runs-alerts.py exited 2")
    compare(s.helperProc, null)
    s.destroy()
  }

  // A fatal envelope + exit 1: one warn, stopped for good.
  function fatalFailure_stops(type) {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(stopWarning(type))
    line(s, envelope(type))
    s.helperProc.exited(1)
    compare(s.status, "stopped")
    compare(s.retryTimer.running, false)
    compare(s.helperProc, null)
    compare(s.lastError, type + ": the " + type + " message")
    s.retryTimer.triggered()
    compare(s.helperProc, null)
    compare(s.status, "stopped")
    s.destroy()
  }

  function test_schema_mismatch_stops() {
    fatalFailure_stops("SchemaMismatch")
  }

  function test_corrupt_journal_stops() {
    fatalFailure_stops("CorruptJournal")
  }

  function test_exit_zero_is_not_relaunched() {
    failOnWarning(/RunAlertsService/)
    var s = make(); if (!s) return
    s.helperProc.exited(0)
    compare(s.status, "stopped")
    compare(s.retryTimer.running, false)
    compare(s.helperProc, null)
    compare(s.lastError, "")
    s.destroy()

    var t = make(); if (!t) return
    line(t, envelope("AmMissing"))
    t.helperProc.exited(0)
    compare(t.status, "stopped")
    compare(t.retryTimer.running, false)
    compare(t.lastError, "")
    t.retryTimer.triggered()
    compare(t.helperProc, null)
    t.destroy()
  }

  function test_the_last_envelope_decides() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    line(s, envelope("SchemaMismatch"))
    line(s, envelope("AmMissing"))
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    compare(s.lastError, "AmMissing: the AmMissing message")
    s.destroy()
  }

  function test_the_timer_runs_only_while_waiting() {
    var s = make(); if (!s) return
    ignoreWarning(retryWarning("HelperError"))
    ignoreWarning(stopWarning("CorruptJournal"))
    failOnWarning(/RunAlertsService/)
    compare(s.retryTimer.running, false)
    line(s, envelope("HelperError"))
    s.helperProc.exited(1)
    compare(s.retryTimer.running, true)
    s.retryTimer.triggered()
    compare(s.status, "watching")
    compare(s.retryTimer.running, false)
    line(s, envelope("CorruptJournal"))
    s.helperProc.exited(1)
    compare(s.status, "stopped")
    compare(s.retryTimer.running, false)
    s.destroy()
  }

  // In one synchronous block, so p1's deferred destroy() has not run yet.
  function test_a_replaced_launch_is_ignored() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    var p1 = s.helperProc
    line(s, envelope("AmMissing"))
    p1.exited(1)
    s.retryTimer.triggered()
    var p2 = s.helperProc
    verify(p2 !== null && p2 !== p1, "no new launch")
    p1.stdout.read(JSON.stringify(envelope("SchemaMismatch")))
    p1.exited(1)
    compare(s.status, "watching")
    compare(s.helperProc, p2)
    compare(s.retryTimer.running, false)
    compare(s.lastError, "AmMissing: the AmMissing message")
    s.destroy()
  }

  function test_destruction_stops_the_helper() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    var proc = s.helperProc
    var recorded = []
    proc.runningChanged.connect(function() { recorded.push(proc.running) })
    s.destroy()
    wait(0)
    compare(recorded, [false])
  }

  function test_destruction_while_waiting_warns_nothing() {
    var s = make(); if (!s) return
    failOnWarning(/./)
    ignoreWarning(retryWarning("HelperError"))
    line(s, envelope("HelperError"))
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    s.destroy()
    wait(0)
  }

  function test_a_timer_fire_while_watching_launches_nothing() {
    var s = make(); if (!s) return
    var proc = s.helperProc
    s.retryTimer.triggered()
    compare(s.status, "watching")
    compare(s.helperProc, proc)
    compare(s.retryTimer.running, false)
    s.destroy()
  }

  function test_a_malformed_envelope_waits() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning("RunAlertsService: unknown error -- retrying in 300 s")
    line(s, { ok: false })
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    compare(s.lastError, "unknown error")
    s.destroy()

    var t = make(); if (!t) return
    ignoreWarning("RunAlertsService: unknown error -- retrying in 300 s")
    line(t, { ok: false, error: "boom" })
    t.helperProc.exited(1)
    compare(t.status, "waiting")
    compare(t.retryTimer.running, true)
    t.destroy()
  }

  function test_a_failed_relaunch_waits_again() {
    var s = make(); if (!s) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    ignoreWarning(retryWarning("HelperError"))
    line(s, envelope("AmMissing"))
    s.helperProc.exited(1)
    s.retryTimer.triggered()
    line(s, envelope("HelperError"))
    s.helperProc.exited(1)
    compare(s.status, "waiting")
    compare(s.retryTimer.running, true)
    compare(s.lastError, "HelperError: the HelperError message")
    compare(s.helperProc, null)
    s.destroy()
  }

  function test_two_services_are_independent() {
    var a = make(); if (!a) return
    var b = make(); if (!b) return
    failOnWarning(/RunAlertsService/)
    ignoreWarning(retryWarning("AmMissing"))
    verify(a.helperProc !== b.helperProc, "one process for two services")
    line(a, envelope("AmMissing"))
    a.helperProc.exited(1)
    compare(a.status, "waiting")
    compare(b.status, "watching")
    compare(b.retryTimer.running, false)
    compare(b.lastError, "")
    verify(b.helperProc !== null, "b lost its process")
    a.destroy()
    b.destroy()
  }

  function test_an_alert_line_emits_alert_received() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    line(s, { alert: { run_id: "r1", root: "/p/one", project: "one", state: "escalated" } })
    line(s, { alert: { run_id: "r2", root: "/p/two", project: "two", state: "dead", gseq: 7 } })
    compare(spy.count, 2)
    compare(spy.signalArguments[0][0], { run_id: "r1", root: "/p/one", project: "one", state: "escalated" })
    compare(spy.signalArguments[1][0], { run_id: "r2", root: "/p/two", project: "two", state: "dead", gseq: 7 })
    compare(s.status, "watching")
    s.destroy()
  }

  function test_other_lines_are_ignored() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    failOnWarning(/./)
    var lines = ["", "   ", "not json", "[1]", "null", "42", "\"x\"",
                 { cursor: 3 }, { alert: null }, { alert: [] }, { alert: "r" },
                 { alert: { state: "escalated" } },
                 { alert: { run_id: "", state: "dead" } },
                 { alert: { run_id: 5, state: "dead" } },
                 { alert: { run_id: "r", state: "running" } },
                 { alert: { run_id: "r" } },
                 { hello: {} }, { ok: true }]
    for (var i = 0; i < lines.length; i++) line(s, lines[i])
    compare(spy.count, 0)
    compare(s.status, "watching")
    compare(s.lastError, "")
    // A valid line afterwards still counts: the handler survived all of the above.
    line(s, { alert: { run_id: "r", state: "dead" } })
    compare(spy.count, 1)
    s.destroy()
  }

  // In one synchronous block, so p1's deferred destroy() has not run yet.
  function test_a_replaced_launch_emits_no_alert() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    ignoreWarning(retryWarning("AmMissing"))
    var p1 = s.helperProc
    line(s, envelope("AmMissing"))
    p1.exited(1)
    s.retryTimer.triggered()
    p1.stdout.read(JSON.stringify({ alert: { run_id: "old", state: "escalated" } }))
    compare(spy.count, 0)
    line(s, { alert: { run_id: "new", state: "escalated" } })
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0].run_id, "new")
    s.destroy()
  }

  function test_an_alert_line_with_surrounding_whitespace_is_read() {
    var s = make(); if (!s) return
    var spy = alertSpy(s)
    line(s, "  " + JSON.stringify({ alert: { run_id: "r1", state: "escalated" } }) + "\r")
    line(s, "\t" + JSON.stringify({ alert: { run_id: "r2", state: "dead" } }) + "  ")
    compare(spy.count, 2)
    compare(spy.signalArguments[0][0].run_id, "r1")
    compare(spy.signalArguments[1][0].run_id, "r2")
    s.destroy()
  }

  // ---- the per-alert pipeline (2.3)

  property string runId: "20261010T025704Z-aaaaaaaa"

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // A get-global-settings reply with the switch at `on`.
  function settingsReply(on) { return JSON.stringify({ notifyOnEscalation: on }) }

  // An escalated alert for runId in /p/alpha, with `fields` laid over it.
  function alertOf(fields) {
    var a = { run_id: tc.runId, root: "/p/alpha", project: "alpha", state: "escalated" }
    for (var k in fields) a[k] = fields[k]
    return a
  }

  // One alert line of the current launch.
  function sendAlert(s, alert) { line(s, { alert: alert }) }

  function settingsCmd(s) {
    return "python3|" + s.backendDir + "projects/viewer-state.py|get-global-settings"
  }

  function test_an_alert_reads_the_global_settings_first() {
    var s = make(); if (!s) return
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 0)
    sendAlert(s, alertOf({}))
    compare(s.alertRunners.length, 1)
    var r = s.alertRunners[0]
    compare(r.step, "settings")
    compare(r.guard, "")
    compare(r.alert.run_id, tc.runId)
    compare(argv(r.current), settingsCmd(s))
    compare(r.current.running, true)
    compare(s.notifyRunners.length, 0)
    s.destroy()
  }

  function test_switch_off_sends_nothing_data() {
    return [
      { tag: "false", text: settingsReply(false), code: 0 },
      { tag: "absent", text: "{}", code: 0 },
      { tag: "the string true", text: settingsReply("true"), code: 0 },
      { tag: "one", text: settingsReply(1), code: 0 },
      { tag: "garbage", text: "garbage", code: 0 },
      { tag: "empty", text: "", code: 0 },
      { tag: "true but exit 1", text: settingsReply(true), code: 1 }
    ]
  }

  function test_switch_off_sends_nothing(data) {
    var s = make(); if (!s) return
    failOnWarning(/./)
    sendAlert(s, alertOf({}))
    var r = s.alertRunners[0]
    var settingsProc = r.current
    reply(settingsProc, data.text, data.code)
    compare(s.alertRunners.length, 0)
    compare(s.notifyRunners.length, 0)
    // The runner's destroy() is deferred: in this block it still shows it never ran again.
    compare(r.seq, 1, "a second process was launched")
    compare(r.current, settingsProc)
    compare(r.step, "")
    s.destroy()
  }
}
