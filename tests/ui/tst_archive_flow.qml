// tests/ui/tst_archive_flow.qml
// What the panel does around Archive finished: the toolbar button (visible only
// on the Board list with a project and at least one candidate, labelled with
// the count), the confirm dialog hosted over the panel (rows, Archive all,
// Cancel, Escape, backdrop, focus, a failure keeping it open) and that nothing
// is run before the click. The rule is tested in tests/core/domain/tst_board.qml
// and the flow in tests/core/stores/tst_board_store.qml.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "ArchiveFlow"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property string nowIso: "2026-10-10T12:00:00+00:00"

  function aged(id, status, daysAgo, children) {
    return { id: id, title: "Title " + id, status: status, description: "", blocked_by: [],
             updated_at: new Date(Date.parse(nowIso) - daysAgo * 86400000).toISOString(), children: children || [] }
  }
  function finished() {
    return [aged("a", "done", 9, [aged("a1", "done", 9), aged("a2", "merged", 9)]),
            aged("b", "done", 4, [aged("b1", "done", 4)]),
            aged("c", "todo", 9, [aged("c1", "todo", 9)])]
  }

  function make(roots) {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    p.app.board.nowMs = Date.parse(nowIso)
    p.app.board.applyTreeData(roots === undefined ? finished() : roots)
    wait(50)
    return p
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  function test_the_button_shows_the_candidate_count() {
    var p = make(); if (!p) return
    var button = H.find(p, "archiveFinishedButton")
    verify(button, "the button")
    compare(button.visible, true)
    compare(button.bordered, true)
    compare(String(button.text), "Archive finished (2)")
  }

  function test_the_button_is_hidden_without_candidates() {
    var p = make([aged("c", "todo", 9, [aged("c1", "todo", 9)])]); if (!p) return
    compare(H.find(p, "archiveFinishedButton").visible, false)
  }

  function test_the_button_is_hidden_outside_the_board_list_and_without_a_project() {
    var p = make(); if (!p) return
    var button = H.find(p, "archiveFinishedButton")
    p.app.nav.viewMode = "graph"
    compare(button.visible, false)
    p.app.nav.viewMode = "board"
    compare(button.visible, true)
    p.app.projects.applyProjectsList([])
    compare(button.visible, false)
  }

  function test_clicking_opens_the_dialog_and_lists_each_candidate_oldest_first() {
    var p = make(); if (!p) return
    click(H.find(p, "archiveFinishedButton"))
    compare(p.app.board.archiveOpen, true)
    compare(p.app.board.archiveRunner.seq, 0, "nothing is written by opening")
    wait(50)
    var dialog = H.find(p, "archiveDialog")
    compare(dialog.visible, true)
    compare(String(H.find(p, "archiveRowTitle0").text), "Title a")
    compare(String(H.find(p, "archiveRowMeta0").text), "idle 9 days · 2 cards")
    compare(String(H.find(p, "archiveRowTitle1").text), "Title b")
    compare(String(H.find(p, "archiveRowMeta1").text), "idle 4 days · 1 card")
    verify(!H.find(p, "archiveRow2"), "only the two candidates")
    verify(p.focusItem === dialog.focusItem, "the dialog has the focus")
  }

  function test_archive_all_runs_the_helper_and_success_closes_the_dialog() {
    var p = make(); if (!p) return
    p.app.board.openArchive()
    wait(50)
    var confirm = H.find(p, "archiveConfirm")
    compare(String(confirm.text), "Archive all")
    click(confirm)
    compare(p.app.board.archiveBusy, true)
    compare(String(H.find(p, "archiveConfirm").text), "Archiving…")
    compare(H.find(p, "archiveConfirm").enabled, false)
    compare(H.find(p, "archiveCancel").enabled, false)
    var proc = p.app.board.archiveRunner.current
    proc.outText = '{"ok": true, "results": [{"id": "a", "ok": true}, {"id": "b", "ok": true}]}'
    proc.exited(0)
    wait(50)
    compare(p.app.board.archiveOpen, false)
    compare(H.find(p, "archiveDialog").visible, false)
  }

  function test_a_failure_shows_in_the_dialog_and_keeps_it_open() {
    var p = make(); if (!p) return
    p.app.board.openArchive()
    click(H.find(p, "archiveConfirm"))
    var proc = p.app.board.archiveRunner.current
    proc.outText = '{"ok": false, "results": [{"id": "a", "ok": true}, {"id": "b", "ok": false, "error": "locked"}]}'
    proc.exited(1)
    wait(50)
    var err = H.find(p, "archiveError")
    compare(err.visible, true)
    verify(String(err.text).indexOf("Title b") >= 0 && String(err.text).indexOf("locked") >= 0, err.text)
    compare(H.find(p, "archiveDialog").visible, true)
    compare(H.find(p, "archiveConfirm").enabled, true)
  }

  function test_cancel_backdrop_and_escape_all_cancel_without_writing() {
    var p = make(); if (!p) return
    p.app.board.openArchive()
    click(H.find(p, "archiveCancel"))
    compare(p.app.board.archiveOpen, false)
    p.app.board.openArchive()
    wait(50)
    mouseClick(H.find(p, "archiveBackdrop"), 2, 2)
    compare(p.app.board.archiveOpen, false)
    p.app.board.openArchive()
    wait(50)
    p.shortcuts.closeRequested()
    compare(p.app.board.archiveOpen, false)
    compare(p.opened, true, "the panel stays open")
    compare(p.app.board.archiveRunner.seq, 0)
  }

  function test_escape_key_in_the_dialog_cancels() {
    var p = make(); if (!p) return
    p.app.board.openArchive()
    wait(50)
    keyClick(Qt.Key_Escape)
    compare(p.app.board.archiveOpen, false)
  }

  function test_section_shortcuts_are_blocked_while_the_dialog_is_open() {
    var p = make(); if (!p) return
    p.app.board.openArchive()
    compare(p.shortcuts.handleGlobalKey({ key: Qt.Key_2, modifiers: Qt.ControlModifier, accepted: false }), false)
    p.navigator.showSection("graph")
    compare(p.app.nav.viewMode, "board")
  }
}
