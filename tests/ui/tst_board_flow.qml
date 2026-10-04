import QtQuick
import QtTest
import "../helpers/find.js" as H
TestCase {
  id: testCase
  name: "BoardFlow"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  function card(id, title, status, children, blockedBy) {
    return { id: id, title: title, status: status, description: "d", blocked_by: blockedBy || [], children: children || [] }
  }
  function ids(list) { return list.map(function(x) { return x.id }).join(",") }

  function test_board_and_detail_flow() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/x", name: "proj" }])
    var t1 = card("t1", "Task1", "blocked", [], ["x1"])
    var t2 = card("t2", "Task2", "done")
    var s1 = card("s1", "Story", "in_progress", [t1, t2])
    var m1 = card("m1", "Milestone", "todo", [s1])
    var x1 = card("x1", "Ex", "done")
    var b1 = card("b1", "Blk", "blocked")
    p.app.board.applyTreeData([m1, x1, b1])
    wait(50)
    compare(ids(p.app.board.boardCards), "m1,b1,x1")
    p.navigator.moveCursor(1); compare(p.app.nav.cursorIndex, 1)
    p.navigator.moveCursor(5); compare(p.app.nav.cursorIndex, 2)
    p.navigator.moveCursor(-1)
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry"); compare(p.app.board.selectedCardId, "b1")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board"); compare(p.app.nav.cursorIndex, 1)
    p.app.nav.cursorIndex = 0
    p.navigator.activateCursor(); compare(p.app.board.selectedCardId, "m1")
    p.navigator.activateCursor(); compare(p.app.board.selectedCardId, "s1")
    compare(p.app.board.detailLinkList.map(function(l) { return l.section }).join(","), "parent,child,child")
    p.navigator.moveCursor(1); p.navigator.activateCursor(); compare(p.app.board.selectedCardId, "t1")
    compare(p.app.board.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:s1,blocker:x1")
    p.app.board.applyTreeData([x1])
    compare(p.app.nav.viewMode, "board")
  }

  // ---- am run marks (5.3)

  // A normalised run (runs.js normalizeRun's shape), built directly.
  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/x", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }
  function allNamed(item, name, out) {
    out = out || []
    if (!item) return out
    if (item.objectName === name) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) allNamed(kids[i], name, out)
    return out
  }
  // The text of every run badge actually on screen.
  function shownBadges(p) {
    return allNamed(p, "runBadge").filter(function(b) { return b.visible }).map(function(b) { return b.text })
  }

  function test_a_run_marks_the_board_and_its_card_row_opens_run_detail_and_comes_back() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/x", name: "proj" }])
    // The export and the runs snapshot cannot run here: disarm them so their
    // late replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    var t1 = card("t1", "Task1", "in_progress")
    var s1 = card("s1", "Story", "in_progress", [t1])
    var m1 = card("m1", "Milestone", "in_progress", [s1])
    var x1 = card("x1", "Ex", "done")
    p.app.board.applyTreeData([m1, x1])
    p.app.runs.runs = [mkRun("run-0000000000a1", "started", true, "m1",
      { stories: [{ card_id: "s1", subtasks: ["t1"] }],
        subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] },
      [{ card_id: "t1", status: "running" }])]
    wait(50)
    compare(shownBadges(p).join(","), "⟳ 1", "the milestone the run heads carries its counts, and nothing else does")

    p.navigator.openCard("m1")
    wait(50)
    compare(H.find(p, "cardRunsHeader").visible, true)
    var row = H.find(p, "cardRunRow0")
    verify(row, "the card lists the run")
    row.activated()
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000a1")
    compare(p.app.nav.runReturnMode, "entry")

    p.navigator.goBack()
    compare(p.app.nav.viewMode, "entry", "Back from that run lands on the card")
    compare(p.app.board.selectedCardId, "m1")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board", "and Back again reaches the board")
  }
}
