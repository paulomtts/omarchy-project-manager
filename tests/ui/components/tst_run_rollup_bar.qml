// tests/ui/components/tst_run_rollup_bar.qml
// ui/components/RunRollupBar.qml: a milestone/story's run rollup under its
// title, one caption segment per non-zero count (the RunBadge glyphs, then
// "N pending"), escalated in `urgent`, and nothing at all for an empty rollup.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunRollupBar"
  when: windowShown
  visible: true
  width: 400; height: 200

  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: barC; UI.RunRollupBar {} }

  function make(rollup, theme) {
    var bar = createTemporaryObject(barC, tc, { theme: theme || null, rollup: rollup })
    wait(30)
    return bar
  }

  function seg(bar, name) { return H.find(bar, name) }

  function test_segments() {
    var bar = make({ running: 2, parked: 1, escalated: 0, done: 3, pending: 0, total: 6 }, testTheme)
    compare(bar.objectName, "runRollupBar")
    compare(bar.visible, true)
    var running = seg(bar, "runRollupRunning")
    var parked = seg(bar, "runRollupParked")
    var done = seg(bar, "runRollupDone")
    verify(running && parked && done)
    compare(running.visible, true)
    compare(running.text, "⟳ 2")
    compare(parked.visible, true)
    compare(parked.text, "⏸ 1")
    compare(done.visible, true)
    compare(done.text, "✔ 3")
    compare(seg(bar, "runRollupEscalated").visible, false, "a zero count is not shown")
    compare(seg(bar, "runRollupPending").visible, false)
    verify(running.x < parked.x && parked.x < done.x, "running, parked, ..., done in that order")
  }

  function test_pending_segment() {
    var bar = make({ running: 1, pending: 4, total: 5 }, testTheme)
    var pending = seg(bar, "runRollupPending")
    compare(pending.visible, true)
    compare(pending.text, "4 pending")
    verify(seg(bar, "runRollupRunning").x < pending.x, "pending comes last")
  }

  function test_escalated_urgent() {
    var bar = make({ escalated: 2, total: 2 }, testTheme)
    var escalated = seg(bar, "runRollupEscalated")
    compare(escalated.visible, true)
    compare(escalated.text, "‼ 2")
    verify(Qt.colorEqual(escalated.color, testTheme.urgent))

    // No theme handed down: the bar's own fallback Theme, still urgent.
    var own = make({ escalated: 1, total: 1 })
    verify(own.palette, "falls back to its own Theme")
    var e = seg(own, "runRollupEscalated")
    verify(Qt.colorEqual(e.color, own.palette.urgent))
    var names = ["runRollupRunning", "runRollupParked", "runRollupEscalated", "runRollupDone", "runRollupPending"]
    for (var i = 0; i < names.length; i++) {
      var c = seg(own, names[i]).color
      verify(!Qt.colorEqual(c, "#9b72cf") && !Qt.colorEqual(c, "#d9534f"), names[i])
    }
  }

  function test_empty_hidden() {
    compare(make(null).visible, false, "no rollup, no bar")
    compare(make({ running: 0, parked: 0, escalated: 0, done: 0, pending: 0, total: 0 }).visible, false)
    var bar = make({ running: 1, total: 1 })
    compare(bar.visible, true)
    bar.rollup = null
    wait(30)
    compare(bar.visible, false, "clearing the rollup hides it")
  }

  function test_partial_rollup() {
    var bar = make({ running: 1, total: 1 }, testTheme)
    compare(bar.visible, true)
    compare(seg(bar, "runRollupRunning").text, "⟳ 1")
    compare(seg(bar, "runRollupParked").visible, false, "a missing field is 0")
    compare(seg(bar, "runRollupEscalated").visible, false)
    compare(seg(bar, "runRollupDone").visible, false)
    compare(seg(bar, "runRollupPending").visible, false)
    compare(make({}).visible, false, "no total: nothing to show")
    compare(make("garbage").visible, false, "a non-object is empty")
    compare(make({ running: -2, parked: "x", total: 3 }, testTheme).visible, true)
    var loose = make({ running: "2", parked: true, done: Infinity, pending: 1, total: "4" }, testTheme)
    compare(loose.visible, false, "a numeric-string total is garbage, so nothing to show")
    var strict = make({ running: "2", parked: true, done: Infinity, pending: 1, total: 4 }, testTheme)
    compare(seg(strict, "runRollupRunning").visible, false, "a numeric string is not a count")
    compare(seg(strict, "runRollupParked").visible, false, "a boolean is not a count")
    compare(seg(strict, "runRollupDone").visible, false, "Infinity is not a count")
    compare(seg(strict, "runRollupPending").text, "1 pending")
  }

}
