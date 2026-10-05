// tests/ui/components/tst_run_controls.qml
// ui/components/RunControls.qml on its own, with plain run objects and no
// store: which of Pause / Resume / Cancel show for each run state, their
// labels, glyphs, enabled state and tooltips, the reason, caption, waiting and
// error lines, and the one signal a click emits.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunControls"
  when: windowShown
  visible: true
  width: 400; height: 300

  readonly property string integrate: "Integrate is running; it cannot be paused or cancelled"
  readonly property string waitingTip: "Waiting for the run to act on the request"
  readonly property string pendingTip: "A request for this run is pending"
  readonly property string waitText: "still waiting — the run may be between phases or dead"

  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }

  Component { id: controlsC; UI.RunControls { width: 300; theme: tcTheme } }
  SignalSpy { id: actionSpy; signalName: "actionRequested" }

  // A normalised run, as RunStore holds them. live === null means no lease;
  // accepting === false puts a leased run in Integrate.
  function run(id, status, live, accepting) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "M3", status: status, started_at: "",
             base_branch: "master", branch_prefix: "m3", workflow: "milestone",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: accepting !== false, live: live },
             requests: [], rows: [], tree: { stories: [], subtasks: [] } }
  }
  function running(accepting) { return run("run-x-live0001", "started", true, accepting) }
  function parked() { return run("run-x-park0002", "stopped", null) }
  function escalated() { return run("run-x-escl0003", "escalated", null) }
  function dead() { return run("run-x-dead0004", "started", false) }

  function make(props) {
    var c = createTemporaryObject(controlsC, tc, props || {})
    actionSpy.target = c
    actionSpy.clear()
    wait(20)
    return c
  }

  function part(c, name) { return H.find(c, "runControl" + name) }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // 1
  function test_a_running_run_shows_pause_and_cancel() {
    var c = make({ run: running() })
    var pause = part(c, "Pause"), resume = part(c, "Resume"), cancel = part(c, "Cancel")
    compare(pause.visible, true)
    compare(pause.enabled, true)
    compare(pause.text, "Pause")
    compare(pause.iconText, "⏸")
    compare(pause.iconText, RG.glyphOf("parked"))
    compare(pause.tooltipText, "")
    compare(cancel.visible, true)
    compare(cancel.enabled, true)
    compare(cancel.text, "Cancel")
    compare(cancel.iconText, "⊘")
    compare(cancel.iconText, RG.glyphOf("cancelled"))
    compare(cancel.tooltipText, "")
    compare(cancel.tone, "danger")
    compare(pause.tone, "normal")
    compare(resume.visible, false, "never both Pause and Resume")
    compare(part(c, "Reason").visible, false, "everything enabled: no reason line")
    compare(part(c, "Caption").visible, false)
    verify(c.height > 0)
  }

  // 2
  function test_parked_escalated_and_dead_runs_show_resume_and_cancel() {
    var cases = [["parked", parked()], ["escalated", escalated()], ["dead", dead()]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1] })
      var resume = part(c, "Resume")
      compare(resume.visible, true, cases[i][0])
      compare(resume.enabled, true, cases[i][0])
      compare(resume.text, "Resume", cases[i][0])
      compare(resume.iconText, "⟳", cases[i][0])
      compare(resume.iconText, RG.glyphOf("running"), cases[i][0])
      compare(resume.tooltipText, "", cases[i][0])
      compare(part(c, "Cancel").visible, true, cases[i][0])
      compare(part(c, "Cancel").enabled, true, cases[i][0])
      compare(part(c, "Pause").visible, false, cases[i][0])
      compare(part(c, "Reason").visible, false, cases[i][0])
    }
  }

  // 3
  function test_integrate_disables_pause_and_cancel_and_says_why_once() {
    var c = make({ run: running(false) })
    var pause = part(c, "Pause"), cancel = part(c, "Cancel")
    compare(pause.visible, true)
    compare(pause.enabled, false)
    compare(pause.tooltipText, tc.integrate)
    compare(cancel.visible, true)
    compare(cancel.enabled, false)
    compare(cancel.tooltipText, tc.integrate)
    compare(part(c, "Resume").visible, false)
    var reason = part(c, "Reason")
    compare(reason.visible, true)
    compare(reason.text, tc.integrate, "the one sentence, once")

    var e = escalated()
    e.lease = { pid: 1, host: "h", heartbeat_at: "", accepting: false, live: false }
    var c2 = make({ run: e })
    compare(part(c2, "Resume").enabled, true, "resume never looks at accepting")
    compare(part(c2, "Cancel").enabled, false)
    compare(part(c2, "Cancel").tooltipText, tc.integrate)
    compare(part(c2, "Reason").text, tc.integrate)
  }

  // 4 + Review Focus 3 (a malformed run)
  function test_finished_unknown_and_missing_runs_show_nothing() {
    var cases = [["done", run("run-x-done0005", "done", null)],
                 ["cancelled", run("run-x-canc0006", "cancelled", null)],
                 ["unknown", run("run-x-bogus007", "bogus", null)],
                 ["null", null],
                 ["malformed", { id: 5, status: 7, lease: "x", rows: "y", tree: null }]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1], wholeRun: true })
      compare(part(c, "Buttons").visible, false, cases[i][0])
      compare(part(c, "Pause").visible, false, cases[i][0])
      compare(part(c, "Resume").visible, false, cases[i][0])
      compare(part(c, "Cancel").visible, false, cases[i][0])
      compare(part(c, "Caption").visible, false, cases[i][0])
      compare(part(c, "Reason").visible, false, cases[i][0])
      compare(c.height, 0, cases[i][0])
    }
  }

  // 5
  function test_whole_run_labels_and_the_caption() {
    var c = make({ run: running(), wholeRun: true })
    compare(part(c, "Pause").text, "Pause run")
    compare(part(c, "Cancel").text, "Cancel run")
    var caption = part(c, "Caption")
    compare(caption.visible, true)
    compare(caption.text, "applies to the whole run")
    c.run = parked()
    compare(part(c, "Resume").text, "Resume run")
    c.wholeRun = false
    compare(caption.visible, false)
    compare(part(c, "Resume").text, "Resume")
    compare(part(c, "Cancel").text, "Cancel")
  }

  // 6
  function test_a_pending_request_disables_every_button() {
    var c = make({ run: running(), pendingAction: "pause" })
    var pause = part(c, "Pause"), cancel = part(c, "Cancel")
    compare(pause.visible, true)
    compare(pause.text, "Pause requested…")
    compare(pause.iconText, "⏸", "the icon does not change while pending")
    compare(pause.enabled, false)
    compare(pause.tooltipText, tc.waitingTip)
    compare(cancel.text, "Cancel")
    compare(cancel.enabled, false)
    compare(cancel.tooltipText, tc.pendingTip)
    compare(part(c, "Resume").visible, false)
    compare(part(c, "Reason").visible, false, "a pending request is not a disabled reason")

    c.pendingAction = "cancel"
    compare(cancel.text, "Cancel requested…")
    compare(cancel.tooltipText, tc.waitingTip)
    compare(pause.text, "Pause")
    compare(pause.enabled, false)
    compare(pause.tooltipText, tc.pendingTip)

    var d = make({ run: dead(), pendingAction: "resume" })
    compare(part(d, "Resume").text, "Resume requested…")
    compare(part(d, "Resume").enabled, false)
    compare(part(d, "Resume").tooltipText, tc.waitingTip)
    compare(part(d, "Cancel").enabled, false)
    compare(part(d, "Cancel").tooltipText, tc.pendingTip)
    compare(part(d, "Pause").visible, false)

    var integrate = make({ run: running(false), pendingAction: "pause" })
    compare(part(integrate, "Reason").visible, false, "no reason line while pending, even in Integrate")
  }

  // 7 + Review Focus 5
  function test_a_pending_request_shows_its_own_button_whatever_the_state() {
    var c = make({ run: parked(), pendingAction: "pause" })
    compare(part(c, "Pause").visible, true, "the pause slot keeps Pause until it settles")
    compare(part(c, "Pause").text, "Pause requested…")
    compare(part(c, "Resume").visible, false)

    var r = make({ run: running(), pendingAction: "resume" })
    compare(part(r, "Resume").visible, true)
    compare(part(r, "Resume").text, "Resume requested…")
    compare(part(r, "Pause").visible, false)

    var k = make({ run: run("run-x-canc0006", "cancelled", null), pendingAction: "cancel" })
    compare(part(k, "Buttons").visible, true)
    compare(part(k, "Cancel").visible, true)
    compare(part(k, "Cancel").text, "Cancel requested…")
    compare(part(k, "Cancel").enabled, false)
    compare(part(k, "Pause").visible, false)
    compare(part(k, "Resume").visible, false)
  }

  // 8
  function test_show_buttons_false_hides_the_buttons_but_not_a_pending_one_or_the_error() {
    var c = make({ run: running(), wholeRun: true, showButtons: false })
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Caption").visible, false)
    compare(c.height, 0)
    c.pendingAction = "pause"
    compare(part(c, "Buttons").visible, true)
    compare(part(c, "Pause").visible, true)
    compare(part(c, "Pause").text, "Pause requested…")
    compare(part(c, "Caption").visible, true)
    c.pendingAction = ""
    c.errorText = "The run is not running"
    wait(20)   // a Column re-lays out on the next polish, not synchronously
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Error").visible, true)
    verify(c.height > 0)
  }

  // 9
  function test_a_click_on_an_enabled_button_asks_for_its_action_once() {
    var c = make({ run: running() })
    tap(part(c, "Pause"))
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "pause")
    tap(part(c, "Cancel"))
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[1][0], "cancel")

    var p = make({ run: parked() })
    tap(part(p, "Resume"))
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "resume")
  }

  function test_a_click_on_a_disabled_button_asks_for_nothing() {
    var c = make({ run: running(false) })
    tap(part(c, "Pause"))
    tap(part(c, "Cancel"))
    compare(actionSpy.count, 0)
    var p = make({ run: running(), pendingAction: "pause" })
    tap(part(p, "Pause"))
    tap(part(p, "Cancel"))
    compare(actionSpy.count, 0)
  }

  // 10
  function test_the_waiting_line_needs_waiting_a_pending_action_and_a_text() {
    var c = make({ run: running(), waiting: true, waitingText: tc.waitText })
    var line = part(c, "Waiting")
    compare(line.visible, false, "nothing pending")
    c.pendingAction = "pause"
    compare(line.visible, true)
    compare(line.text, tc.waitText)
    compare(String(line.color), String(tcTheme.dim))   // Text.color is 8-bit; the theme's float colour is not, so compare the rendered hex
    c.waiting = false
    compare(line.visible, false)
    c.waiting = true
    c.waitingText = ""
    compare(line.visible, false)
  }

  function test_the_error_line_shows_the_error_in_urgent() {
    var c = make({ run: running() })
    var line = part(c, "Error")
    compare(line.visible, false)
    c.errorText = "The run is not running"
    compare(line.visible, true)
    compare(line.text, "The run is not running")
    compare(String(line.color), String(tcTheme.urgent))
    c.errorText = ""
    compare(line.visible, false)
  }

  // Review Focus 3: a view being torn down nulls theme and run while the
  // bindings still run once; tests/run.sh fails on any TypeError this prints.
  function test_a_null_theme_and_run_do_not_throw() {
    var c = make({ run: running(), errorText: "boom" })
    c.theme = null
    compare(part(c, "Pause").visible, true)
    compare(part(c, "Error").visible, true)
    c.run = null
    c.errorText = ""
    wait(20)
    compare(part(c, "Buttons").visible, false)
    compare(c.height, 0)
  }
}
