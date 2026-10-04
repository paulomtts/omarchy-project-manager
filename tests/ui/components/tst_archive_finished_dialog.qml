import QtQuick
import QtTest
import "../../../ui/components"

TestCase {
  id: tc
  name: "ArchiveFinishedDialog"
  when: windowShown
  visible: true
  width: 600; height: 400

  Component { id: dialogC; ArchiveFinishedDialog { width: 560; height: 360 } }
  SignalSpy { id: confirmSpy; signalName: "confirmRequested" }
  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var d = createTemporaryObject(dialogC, tc)
    confirmSpy.target = d; cancelSpy.target = d
    confirmSpy.clear(); cancelSpy.clear()
    d.candidates = [{ id: "a", title: "Alpha", idleDays: 1, cardCount: 1 }, { id: "b", title: "Beta", idleDays: 12, cardCount: 7 }]
    d.shown = true
    return d
  }

  function test_rows_say_title_idle_days_and_card_count_with_plurals() {
    var d = make()
    compare(String(find(d, "archiveRowTitle0").text), "Alpha")
    compare(String(find(d, "archiveRowMeta0").text), "idle 1 day · 1 card")
    compare(String(find(d, "archiveRowMeta1").text), "idle 12 days · 7 cards")
  }

  function test_buttons_emit_and_busy_locks_everything() {
    var d = make()
    var ok = find(d, "archiveConfirm"), cancel = find(d, "archiveCancel")
    mouseClick(ok, ok.width / 2, ok.height / 2)
    compare(confirmSpy.count, 1)
    mouseClick(cancel, cancel.width / 2, cancel.height / 2)
    compare(cancelSpy.count, 1)
    d.busy = true
    compare(ok.enabled, false); compare(cancel.enabled, false)
    mouseClick(find(d, "archiveBackdrop"), 2, 2)
    compare(cancelSpy.count, 1, "the backdrop does not cancel while busy")
    d.busy = false
    mouseClick(find(d, "archiveBackdrop"), 2, 2)
    compare(cancelSpy.count, 2)
    mouseClick(find(d, "archiveCard"), 3, 3)
    compare(cancelSpy.count, 2)
  }

  function test_escape_cancels_and_error_is_shown() {
    var d = make()
    compare(find(d, "archiveError").visible, false)
    d.error = "Could not archive Beta: locked"
    compare(find(d, "archiveError").visible, true)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancelSpy.count, 1)
  }

  function test_no_candidates_cannot_confirm() {
    var d = make()
    d.candidates = []
    compare(find(d, "archiveConfirm").enabled, false)
  }
}
