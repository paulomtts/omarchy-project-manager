// tests/ui/components/tst_run_mark.qml
// ui/components/RunMark.qml: one card's am run mark as the Board and the Graph
// draw it -- a RunBadge inside the wrapper that dims it. A subtask shows its
// glyph and phase; a milestone or story its non-zero counts, else its run's
// glyph; nothing at all for no run. A dimmed winner or stale data is drawn at
// half opacity by the wrapper and never pulses.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunMark"
  when: windowShown
  visible: true
  width: 400; height: 200

  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: markC; UI.RunMark {} }

  function make(props) {
    var p = props || {}
    p.theme = testTheme
    var mark = createTemporaryObject(markC, tc, p)
    wait(30)
    return mark
  }
  // A Runs.cardRunState-shaped object.
  function st(state, opts) {
    var o = opts || {}
    return { state: state, runId: "r1", dimmed: o.dimmed === true, phase: o.phase || "", attempt: 0 }
  }
  // A Runs.rollup-shaped object.
  function counts(c) {
    return { running: c.running || 0, parked: c.parked || 0, escalated: c.escalated || 0,
             done: c.done || 0, pending: c.pending || 0, total: c.total || 0 }
  }
  function textOf(mark) { return H.find(mark, "runBadgeText").text }

  function test_a_subtask_shows_its_glyph_and_phase_and_pulses_while_running() {
    var mark = make({ runState: st("running", { phase: "implement" }), rollup: counts({ running: 1, total: 1 }), subtask: true })
    compare(mark.objectName, "runMark")
    compare(mark.visible, true)
    compare(textOf(mark), "⟳ implement", "a subtask never shows counts")
    compare(mark.opacity, 1)
    compare(H.find(mark, "runBadge").pulsing, true)
  }

  function test_a_dead_subtask_reads_dead_and_does_not_pulse() {
    var mark = make({ runState: st("dead", { phase: "review" }), subtask: true })
    compare(textOf(mark), "✖ review")
    compare(H.find(mark, "runBadge").pulsing, false)
  }

  function test_a_parent_shows_its_counts_and_never_pulses() {
    var mark = make({ runState: st("running"), rollup: counts({ running: 2, parked: 1, pending: 3, total: 6 }) })
    compare(mark.showCounts, true)
    compare(textOf(mark), "⟳ 2 ⏸ 1")
    compare(H.find(mark, "runBadge").pulsing, false)
  }

  function test_a_parent_without_counts_shows_its_runs_glyph() {
    var mark = make({ runState: st("escalated"), rollup: counts({ pending: 2, total: 2 }) })
    compare(textOf(mark), "‼", "pending alone has no count glyph: the run's state speaks")
    verify(Qt.colorEqual(H.find(mark, "runBadge").tint, testTheme.urgent), "escalated reads in urgent")
    var running = make({ runState: st("running"), rollup: counts({}) })
    compare(textOf(running), "⟳")
  }

  function test_nothing_to_show_hides_the_mark() {
    compare(make({}).visible, false, "no run state and no rollup")
    compare(make({ runState: st("none"), rollup: counts({}) }).visible, false)
    compare(make({ runState: st("none"), rollup: counts({ done: 2, total: 2 }), subtask: true }).visible, false,
            "a subtask whose run finished shows nothing")
    var garbage = [null, undefined, "running", 5, [], { state: 7 }]
    for (var i = 0; i < garbage.length; i++)
      compare(make({ runState: garbage[i], rollup: garbage[i] }).visible, false, "garbage " + i)
  }

  function test_a_dimmed_winner_is_drawn_at_half_opacity_by_the_wrapper() {
    var mark = make({ runState: st("parked", { dimmed: true, phase: "plan" }), subtask: true })
    compare(textOf(mark), "⏸ plan")
    compare(mark.dimmed, true)
    compare(mark.opacity, 0.5)
    compare(H.find(mark, "runBadge").active, false)
    compare(H.find(mark, "runBadge").opacity, 1, "the badge's own opacity is left to its pulse")
  }

  function test_stale_data_dims_and_stops_the_pulse() {
    var mark = make({ runState: st("running", { phase: "implement" }), subtask: true, stale: true })
    compare(mark.opacity, 0.5)
    compare(H.find(mark, "runBadge").pulsing, false)
    mark.stale = false
    wait(30)
    compare(mark.opacity, 1)
    compare(H.find(mark, "runBadge").pulsing, true)
  }

  function test_the_owner_can_switch_the_pulse_off() {
    var mark = make({ runState: st("running"), subtask: true, active: false })
    compare(H.find(mark, "runBadge").pulsing, false)
  }
}
