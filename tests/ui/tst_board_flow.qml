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
        subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] }] },
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

  // ---- Dispatch from the board list (S7: a story's entry points)

  // m1 holds s1 (todo), s2 (brd status blocked, blocked by s1) and s3 (done),
  // each with one subtask; x1 is a done milestone.
  function dispatchRoots() {
    return [
      card("m1", "Milestone", "todo", [
        card("s1", "Story one", "todo", [card("t1", "Sub one", "todo")]),
        card("s2", "Story two", "blocked", [card("t2", "Sub two", "todo")], ["s1"]),
        card("s3", "Story three", "done", [card("t3", "Sub three", "done")])]),
      card("x1", "Ex", "done")]
  }

  // A panel on project /x's board list, the cursor on m1. No helper may
  // really run here (start-run.py starts am): every script path leads
  // nowhere, the export, snapshot and settings runners are cancelled, and a
  // stored verify command lets a fresh form pass the store's checks.
  function makeDispatch() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.app.backendDir = "/plugin/core/backend/"
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/x", name: "proj" }])
    if (!p.app.projects.selectedProject) { fail("project /x is selected"); return null }
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runControl.settingsLoadRunner.cancel()
    p.app.runControl.runSettingsLoadRunner.cancel()
    p.app.runControl.applyRunSettings(p.app.runs.project, { verify: ["uv run pytest"] })
    p.app.board.applyTreeData(dispatchRoots())
    wait(50)
    p.navigator.showSection("board")
    p.app.nav.cursorIndex = 0
    return p
  }

  // A helper's reply, delivered the way its Process would deliver it.
  function reply(proc, text) {
    proc.outText = text
    proc.exited(0)
  }

  function text(p, name) { return String(H.find(p, name).text) }
  function flags(p) { return JSON.stringify(p.app.runDispatch.dispatchTarget.flags) }

  // From the board list: the cursor card m1 opened, then the story `steps`
  // links down its children (0 = s1, 1 = s2, 2 = s3) opened. The board list
  // holds roots only, so this is how a story is reached.
  function reachStory(p, steps, id) {
    compare(ids(p.app.board.boardCards), "m1,x1", "the board list holds roots only")
    compare(p.app.board.boardCards[p.app.nav.cursorIndex].id, "m1")
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "m1")
    compare(p.app.board.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","),
            "child:s1,child:s2,child:s3")
    if (steps > 0) p.navigator.moveCursor(steps)
    compare(p.app.nav.cursorIndex, steps)
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, id)
    wait(50)
  }

  // The open card's entry point: a click on its Dispatch, or a bare d with
  // the card detail's key catcher holding the keyboard.
  function useEntryPoint(p, how) {
    if (how === "button") {
      H.find(p, "cardDispatchButton").clicked()
    } else {
      H.find(p, "keyCatcher").forceActiveFocus()
      keyClick("d")
    }
    wait(50)
  }

  // S7: from the board list, a story's Dispatch and its d open the dialog on
  // the story itself.
  function test_a_story_reached_from_the_board_list_dispatches_itself_data() {
    return [{ tag: "button" }, { tag: "key" }]
  }

  function test_a_story_reached_from_the_board_list_dispatches_itself(data) {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 0, "s1")
    useEntryPoint(p, data.tag)
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "s1")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"Milestone\")")
    compare(p.app.runDispatch.dispatchTarget.level, "story")
    compare(flags(p), JSON.stringify(["--story", "s1"]))
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(H.find(p, "dispatchSuggest").visible, false, "no milestone offer")
    if (data.tag === "key") compare(p.app.nav.searchQuery, "", "the handled d was not typed")
  }

  // S7: am refuses a blocked story; the dialog offers its milestone, and the
  // offer retargets the open dialog.
  function test_a_blocked_story_from_the_board_list_offers_its_milestone() {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 1, "s2")
    useEntryPoint(p, "button")
    compare(p.dispatchCardId, "s2")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story two\" (milestone \"Milestone\")")
    compare(p.app.runDispatch.dispatchState, "previewing", "the plugin does not refuse a blocked story up front")
    reply(p.app.runDispatch.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    compare(p.app.runDispatch.dispatchState, "previewing")
    reply(p.app.runDispatch.dispatchPreviewRunner.current,
          '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s1"}}')
    compare(p.app.runDispatch.dispatchState, "refused")
    compare(text(p, "dispatchRefusal"), "Story blocked by s1")
    compare(H.find(p, "dispatchStart").enabled, false)
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true)
    compare(String(offer.text), "Dispatch the milestone instead")
    offer.clicked()
    compare(p.dispatchCardId, "m1")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"Milestone\"")
    compare(p.app.runDispatch.dispatchTarget.level, "milestone")
    compare(flags(p), JSON.stringify(["--milestone", "m1"]))
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(H.find(p, "dispatchDialog").visible, true)
  }

  // S7: a story in a terminal status is refused at once, as at every level,
  // and nothing is launched.
  function test_a_finished_story_from_the_board_list_is_refused_data() {
    return [{ tag: "button" }, { tag: "key" }]
  }

  function test_a_finished_story_from_the_board_list_is_refused(data) {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 2, "s3")
    useEntryPoint(p, data.tag)
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "s3")
    compare(p.app.runDispatch.dispatchState, "refused")
    compare(p.app.runDispatch.dispatchErrorType, "Target")
    compare(text(p, "dispatchRefusal"), "The card is done")
    compare(H.find(p, "dispatchStart").enabled, false)
    compare(H.find(p, "dispatchSuggest").visible, false, "no milestone offer")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story three\" (milestone \"Milestone\")")
    verify(!p.app.runDispatch.dispatchDefaultsRunner.current, "no defaults lookup was launched")
    verify(!p.app.runDispatch.dispatchPreviewRunner.current, "no preview was launched")
  }

  // A story's dialog is a modal like any other: one Escape closes it and the
  // story stays open.
  function test_escape_closes_a_story_dialog_and_leaves_the_story_open() {
    var p = makeDispatch(); if (!p) return
    reachStory(p, 0, "s1")
    useEntryPoint(p, "key")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.focusItem.objectName, "dispatchBase", "the dialog has the keyboard")
    keyClick(Qt.Key_Escape)
    compare(p.app.runDispatch.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "entry", "that Escape closed the dialog only")
    compare(p.app.board.selectedCardId, "s1")
    compare(p.opened, true)
  }
}
