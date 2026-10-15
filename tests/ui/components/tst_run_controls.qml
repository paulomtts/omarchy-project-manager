// tests/ui/components/tst_run_controls.qml
// ui/components/RunControls.qml on its own, with plain run objects and no
// store: exactly Runs.visibleActions' buttons for each run state, in order,
// their labels and tones, the pending-request marker, relaunchShown, the
// caption, waiting and error lines, and the one signal a click emits.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunControls"
  when: windowShown
  visible: true
  width: 400; height: 300

  readonly property string waitingTip: "Waiting for the run to act on the request"
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
  function escalatedCard() {
    var r = escalated()
    r.workflow = "task"
    r.card_id = "t1"
    return r
  }
  // `r` in Integrate: a lease that is not accepting, its liveness kept.
  function integrate(r) {
    r.lease = { pid: 1, host: "h", heartbeat_at: "", accepting: false, live: r.lease ? r.lease.live === true : false }
    return r
  }

  function make(props) {
    var c = createTemporaryObject(controlsC, tc, props || {})
    actionSpy.target = c
    actionSpy.clear()
    wait(20)
    return c
  }

  function part(c, name) { return H.find(c, "runControl" + name) }

  // The visible buttons, left to right, by objectName without "runControl".
  function shown(c) {
    wait(20)   // a Row lays out on the next polish
    var row = part(c, "Buttons")
    var kids = []
    for (var i = 0; i < row.children.length; i++) {
      if (row.children[i].visible) kids.push(row.children[i])
    }
    kids.sort(function(a, b) { return a.x - b.x })
    return kids.map(function(b) { return b.objectName.replace("runControl", "") }).join(",")
  }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // 1 + 5
  function test_each_state_shows_exactly_its_visible_actions_in_order() {
    var cases = [["running", running(), "Cancel,Pause"], ["parked", parked(), "Close,Resume"],
                 ["escalated", escalated(), "Close,Relaunch"], ["dead", dead(), "Close,Relaunch"],
                 ["escalated card", escalatedCard(), "Close,Relaunch"]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1] })
      compare(shown(c), cases[i][2], cases[i][0])
      compare(part(c, "Buttons").visible, true, cases[i][0])
      verify(c.height > 0, cases[i][0])
    }
  }

  // 5
  function test_resume_never_shows_on_an_escalated_or_dead_run() {
    var cases = [["escalated", escalated()], ["dead", dead()], ["escalated card", escalatedCard()],
                 ["integrate escalated", integrate(escalated())], ["integrate dead", integrate(dead())]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1], wholeRun: true })
      compare(part(c, "Resume").visible, false, cases[i][0])
    }
  }

  // 2
  function test_integrate_keeps_only_resume_or_relaunch() {
    var r = make({ run: running(false), wholeRun: true })
    compare(shown(r), "", "running in Integrate")
    compare(part(r, "Buttons").visible, false)
    compare(part(r, "Caption").visible, false)
    compare(r.height, 0)
    compare(shown(make({ run: integrate(parked()) })), "Resume", "parked in Integrate")
    compare(shown(make({ run: integrate(escalated()) })), "Relaunch", "escalated in Integrate")
    compare(shown(make({ run: integrate(dead()) })), "Relaunch", "dead in Integrate")
  }

  // 3 + Review Focus 1 (a malformed run)
  function test_finished_unknown_and_missing_runs_show_nothing() {
    var cases = [["done", run("run-x-done0005", "done", null)],
                 ["cancelled", run("run-x-canc0006", "cancelled", null)],
                 ["unknown", run("run-x-bogus007", "bogus", null)],
                 ["null", null],
                 ["undefined", undefined],
                 ["malformed", { id: 5, status: 7, lease: "x", rows: "y", tree: null }]]
    for (var i = 0; i < cases.length; i++) {
      var c = make({ run: cases[i][1], wholeRun: true })
      compare(shown(c), "", cases[i][0])
      compare(part(c, "Buttons").visible, false, cases[i][0])
      compare(part(c, "Caption").visible, false, cases[i][0])
      compare(c.height, 0, cases[i][0])
    }
  }

  // 4
  function test_with_nothing_pending_every_shown_button_is_enabled() {
    var runs = [running(), parked(), escalated(), dead(), escalatedCard(), integrate(parked()), integrate(escalated())]
    var names = ["Cancel", "Close", "Pause", "Resume", "Relaunch"]
    for (var i = 0; i < runs.length; i++) {
      var c = make({ run: runs[i] })
      for (var n = 0; n < names.length; n++) {
        var b = part(c, names[n])
        if (!b.visible) continue
        compare(b.enabled, true, runs[i].id + " " + names[n])
        compare(b.tooltipText, "", runs[i].id + " " + names[n])
      }
    }
  }

  // 6
  function test_labels_tones_and_no_glyph() {
    var r = make({ run: running() })
    compare(part(r, "Cancel").text, "Cancel")
    compare(part(r, "Cancel").tone, "danger")
    compare(part(r, "Pause").text, "Pause")
    compare(part(r, "Pause").tone, "warn")
    var p = make({ run: parked() })
    compare(part(p, "Close").text, "Close")
    compare(part(p, "Close").tone, "close")
    compare(part(p, "Resume").text, "Resume")
    compare(part(p, "Resume").tone, "accent")
    var e = make({ run: escalated() })
    compare(part(e, "Relaunch").text, "Relaunch")
    compare(part(e, "Relaunch").tone, "accent")
    var names = ["Cancel", "Close", "Pause", "Resume", "Relaunch"]
    for (var n = 0; n < names.length; n++) compare(part(e, names[n]).iconText, "", names[n] + " has no glyph")
  }

  // 7
  function test_whole_run_labels_and_the_caption() {
    var c = make({ run: running(), wholeRun: true })
    compare(part(c, "Pause").text, "Pause run")
    compare(part(c, "Cancel").text, "Cancel run")
    var caption = part(c, "Caption")
    compare(caption.visible, true)
    compare(caption.text, "applies to the whole run")
    c.run = parked()
    compare(part(c, "Close").text, "Close run")
    compare(part(c, "Resume").text, "Resume run")
    c.run = escalated()
    compare(part(c, "Relaunch").text, "Relaunch run")
    c.showButtons = false
    compare(caption.visible, false, "the caption shows with the buttons only")
    c.showButtons = true
    c.wholeRun = false
    compare(caption.visible, false)
    compare(part(c, "Close").text, "Close")
  }

  // 8
  function test_relaunch_shown_false_drops_relaunch() {
    var c = make({ run: escalated(), relaunchShown: false })
    compare(shown(c), "Close")
    c.run = dead()
    compare(shown(c), "Close")
    c.run = parked()
    compare(shown(c), "Close,Resume", "nothing else changes")
    var i = make({ run: integrate(escalated()), relaunchShown: false, wholeRun: true })
    compare(shown(i), "")
    compare(part(i, "Buttons").visible, false)
    compare(i.height, 0)
  }

  // 9
  function test_a_click_asks_for_its_ui_action_once() {
    var c = make({ run: running() })
    tap(part(c, "Cancel"))
    tap(part(c, "Pause"))
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[0][0], "cancel")
    compare(actionSpy.signalArguments[1][0], "pause")

    var p = make({ run: parked() })
    tap(part(p, "Close"))
    tap(part(p, "Resume"))
    compare(actionSpy.count, 2)
    compare(actionSpy.signalArguments[0][0], "close", "never reset")
    compare(actionSpy.signalArguments[1][0], "resume")

    var e = make({ run: escalated() })
    tap(part(e, "Relaunch"))
    compare(actionSpy.count, 1)
    compare(actionSpy.signalArguments[0][0], "relaunch")
  }

  // 10
  function test_a_pending_reset_is_the_disabled_close_marker() {
    var c = make({ run: parked(), pendingAction: "reset" })
    compare(shown(c), "Close")
    var close = part(c, "Close")
    compare(close.text, "Close requested…")
    compare(close.enabled, false)
    compare(close.tooltipText, tc.waitingTip)
    tap(close)
    compare(actionSpy.count, 0, "the marker is not an action")
  }

  // 11 + Review Focus 5
  function test_a_pending_request_shows_only_its_own_marker_whatever_the_state() {
    var p = make({ run: parked(), pendingAction: "pause" })
    compare(shown(p), "Pause", "the run is parked now; Close and Resume wait")
    compare(part(p, "Pause").text, "Pause requested…")
    compare(part(p, "Pause").enabled, false)

    var r = make({ run: running(), pendingAction: "resume" })
    compare(shown(r), "Resume")
    compare(part(r, "Resume").text, "Resume requested…")

    var k = make({ run: running(), pendingAction: "cancel" })
    compare(shown(k), "Cancel")
    compare(part(k, "Cancel").text, "Cancel requested…")
    compare(part(k, "Cancel").enabled, false)
    compare(part(k, "Cancel").tooltipText, tc.waitingTip)

    var gone = make({ run: run("run-x-canc0006", "cancelled", null), pendingAction: "cancel" })
    compare(shown(gone), "Cancel", "a finished run still shows its pending marker")

    var whole = make({ run: running(), pendingAction: "pause", wholeRun: true })
    compare(part(whole, "Pause").text, "Pause requested…", "the marker never says run")
    tap(part(whole, "Pause"))
    compare(actionSpy.count, 0)
  }

  // 12
  function test_show_buttons_false_hides_the_buttons_but_not_a_marker_or_the_error() {
    var c = make({ run: running(), wholeRun: true, showButtons: false })
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Caption").visible, false)
    compare(c.height, 0)
    c.pendingAction = "pause"
    compare(shown(c), "Pause")
    compare(part(c, "Buttons").visible, true)
    compare(part(c, "Pause").text, "Pause requested…")
    compare(part(c, "Caption").visible, true)
    c.pendingAction = ""
    c.errorText = "The run is not running"
    wait(20)   // a Column re-lays out on the next polish, not synchronously
    compare(part(c, "Buttons").visible, false)
    compare(part(c, "Error").visible, true)
    verify(c.height > 0)
  }

  // 13
  function test_an_unknown_pending_value_shows_no_button() {
    var values = ["close", "bogus", "relaunch"]
    for (var i = 0; i < values.length; i++) {
      var c = make({ run: parked(), pendingAction: values[i] })
      compare(shown(c), "", values[i])
      compare(part(c, "Buttons").visible, false, values[i])
    }
  }

  // 14
  function test_there_is_no_reason_line() {
    var cases = [running(), running(false), parked(), escalated(), escalatedCard(), null]
    for (var i = 0; i < cases.length; i++) compare(part(make({ run: cases[i] }), "Reason"), null, "case " + i)
  }

  // 15
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

  // 15
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

  // 16: a view being torn down nulls theme and run while the bindings still
  // run once; tests/run.sh fails on any TypeError this prints.
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
