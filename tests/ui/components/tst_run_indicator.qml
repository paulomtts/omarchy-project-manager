// tests/ui/components/tst_run_indicator.qml
// ui/components/RunIndicator.qml: the toolbar's run strip. One ActionButton
// segment per non-zero count (running, parked, attention), each the shared
// runGlyphs glyph immediately followed by the count; attention reads in
// `urgent`; a click asks for the matching Runs filter; nothing at all when
// every count is 0 or garbage.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunIndicator"
  when: windowShown
  visible: true
  width: 400; height: 200

  // foreground and urgent differ, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: indicatorC; UI.RunIndicator {} }
  SignalSpy { id: filters; signalName: "filterRequested" }

  function make(props) {
    var ind = createTemporaryObject(indicatorC, tc, props || {})
    filters.target = ind
    filters.clear()
    wait(30)
    return ind
  }
  function seg(ind, name) { return H.find(ind, name) }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }
  function xOf(ind, item) { return item.mapToItem(ind, 0, 0).x }

  function test_no_counts_hides_the_indicator() {
    var ind = make({})
    compare(ind.objectName, "runIndicator")
    compare(ind.visible, false, "the defaults are all 0")
    compare(make({ running: 0, parked: 0, attention: 0 }).visible, false)
  }

  function test_garbage_counts_hide_the_indicator() {
    compare(make({ running: -1, parked: NaN, attention: "3" }).visible, false,
      "negative, NaN and a numeric string are all 0")
    compare(make({ running: undefined, parked: null, attention: Infinity }).visible, false,
      "undefined, null and Infinity are all 0")
    compare(make({ running: true, parked: -Infinity, attention: -5 }).visible, false)
  }

  function test_segments_read_glyph_then_count_in_order() {
    var ind = make({ running: 2, parked: 1, attention: 1, theme: testTheme })
    compare(ind.visible, true)
    var running = seg(ind, "runIndicatorRunning")
    var parked = seg(ind, "runIndicatorParked")
    var attention = seg(ind, "runIndicatorAttention")
    verify(running && parked && attention, "three segments")
    compare(running.visible, true)
    compare(parked.visible, true)
    compare(attention.visible, true)
    compare(String(running.text), RG.glyphOf("running") + "2")
    compare(String(parked.text), RG.glyphOf("parked") + "1")
    compare(String(attention.text), RG.glyphOf("escalated") + "1")
    compare(String(running.text), "⟳2", "the shared running glyph, no space")
    verify(xOf(ind, running) < xOf(ind, parked) && xOf(ind, parked) < xOf(ind, attention),
      "running, parked, attention in that order")
  }

  function test_only_the_parked_segment_shows_for_parked_only() {
    var ind = make({ parked: 1, theme: testTheme })
    compare(ind.visible, true)
    compare(seg(ind, "runIndicatorParked").visible, true)
    compare(String(seg(ind, "runIndicatorParked").text), RG.glyphOf("parked") + "1")
    compare(seg(ind, "runIndicatorRunning").visible, false, "a zero count is not shown")
    compare(seg(ind, "runIndicatorAttention").visible, false)
  }

  function test_a_zero_middle_count_is_skipped_and_order_holds() {
    var ind = make({ running: 1, parked: 0, attention: 4, theme: testTheme })
    compare(seg(ind, "runIndicatorParked").visible, false)
    var running = seg(ind, "runIndicatorRunning")
    var attention = seg(ind, "runIndicatorAttention")
    compare(String(attention.text), RG.glyphOf("escalated") + "4")
    verify(xOf(ind, running) < xOf(ind, attention), "running still leads attention")
  }

  function test_clicks_ask_for_the_matching_runs_filter() {
    var ind = make({ running: 2, parked: 1, attention: 1, theme: testTheme })
    click(seg(ind, "runIndicatorRunning"))
    click(seg(ind, "runIndicatorParked"))
    click(seg(ind, "runIndicatorAttention"))
    compare(filters.count, 3)
    compare(filters.signalArguments[0][0], "live")
    compare(filters.signalArguments[1][0], "parked")
    compare(filters.signalArguments[2][0], "attention")
  }

  function test_attention_reads_urgent_and_the_rest_foreground() {
    var ind = make({ running: 1, parked: 1, attention: 1, theme: testTheme })
    verify(Qt.colorEqual(seg(ind, "runIndicatorAttention").foreground, testTheme.urgent), "attention is urgent")
    verify(Qt.colorEqual(seg(ind, "runIndicatorRunning").foreground, testTheme.foreground), "running is foreground")
    verify(Qt.colorEqual(seg(ind, "runIndicatorParked").foreground, testTheme.foreground), "parked is foreground")
    var names = ["runIndicatorRunning", "runIndicatorParked", "runIndicatorAttention"]
    for (var i = 0; i < names.length; i++) {
      var c = seg(ind, names[i]).foreground
      verify(!Qt.colorEqual(c, "#9b72cf") && !Qt.colorEqual(c, "#d9534f"), names[i])
    }
  }

  function test_a_standalone_instance_uses_its_default_theme() {
    var ind = make({ running: 1, attention: 2 })
    verify(ind.theme, "falls back to its own Theme")
    compare(ind.visible, true)
    verify(Qt.colorEqual(seg(ind, "runIndicatorAttention").foreground, ind.theme.urgent))
    verify(Qt.colorEqual(seg(ind, "runIndicatorRunning").foreground, ind.theme.foreground))
  }

  function test_live_count_changes_hide_and_show_it() {
    var ind = make({ running: 2, theme: testTheme })
    compare(ind.visible, true)
    ind.running = 0
    wait(30)
    compare(ind.visible, false, "the last run finished: nothing to show")
    ind.attention = 1
    wait(30)
    compare(ind.visible, true)
    compare(seg(ind, "runIndicatorAttention").visible, true)
    compare(seg(ind, "runIndicatorRunning").visible, false)
  }

  function test_a_null_theme_falls_back_without_errors() {
    var own = make({ attention: 1 })
    var ind = make({ running: 1, attention: 1, theme: null })
    compare(ind.visible, true)
    verify(Qt.colorEqual(seg(ind, "runIndicatorAttention").foreground, own.theme.urgent),
      "ActionButton's own Theme still paints attention urgent")
  }
}
