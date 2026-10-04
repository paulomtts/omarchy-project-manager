// tests/ui/screens/tst_graph_screen.qml
// ui/screens/GraphScreen.qml on its own: the model it hands the GraphView, the
// cursor it marks, the node click that opens a card through the navigator, the
// centreOn handle Panel drives, and the height it takes from the viewport.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "GraphScreen"
  when: windowShown
  visible: true
  width: 600; height: 700

  Component { id: hostC; Item { width: 600; height: 700 } }
  Component { id: flickC; Flickable { width: 600; height: 300; contentWidth: 600; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  function card(id, title, status, children) {
    return { id: id, title: title, status: status, description: "d", blocked_by: [], children: children || [] }
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var appC = Qt.createComponent("../../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(host, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var flick = flickC.createObject(host)
    var nav = navC.createObject(host, { app: app, flick: flick, actions: ({
      focusForView: function() {},
      scrollToTop: function() { flick.contentY = 0 },
      scrollBy: function(px) { flick.contentY = flick.contentY + px },
      centerOnGraphNode: function(id) {}
    }) })
    var sC = Qt.createComponent("../../../ui/screens/GraphScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 600, viewportHeight: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    app.board.applyTreeData([
      card("m1", "First", "done", [card("s1", "Story", "done")]),
      card("m2", "Second", "todo")])
    return s
  }

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    var data = item.data || []
    for (var j = 0; j < data.length; j++) { var d = find(data[j], name); if (d) return d }
    return null
  }

  function test_the_graph_screen_shows_only_in_the_graph_view_with_a_project() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    s.navigator.showSection("graph")
    compare(s.visible, true)
    s.app.projects.selectedProject = null
    compare(s.visible, false)
  }

  function test_the_graph_view_gets_the_nodes_and_edges_the_graph_store_derives() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    verify(gv, "the GraphView is inside the screen")
    compare(gv.nodes.length, s.app.graph.graph.nodes.length)
    compare(gv.nodes.length, 2)
    verify(find(s, "graphNodem1"), "a node per milestone")
    compare(find(find(s, "graphNodem1"), "graphNodeTitle").text, "First")
  }

  function test_the_graph_cursor_marks_the_current_node() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    s.app.graph.graphCursor = "m2"
    wait(50)
    compare(find(s, "graphNodem2").current, true)
    compare(find(s, "graphNodem1").current, false)
  }

  function test_clicking_a_node_moves_the_cursor_and_opens_that_card() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    find(s, "graphView").nodeClicked("m2")
    compare(s.app.graph.graphCursor, "m2")
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m2")
  }

  function test_the_screen_exposes_the_graph_view_so_the_panel_can_centre_on_a_node() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    wait(100)
    verify(s.graphView, "the screen exposes its GraphView")
    compare(s.graphView.objectName, "graphView")
    s.graphView.centerOn("m2")
  }

  function test_the_graph_fills_what_is_left_of_the_viewport_below_it() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    s.y = 40
    s.viewportHeight = 500
    wait(50)
    compare(s.height, 500 - 40 - 12)
    s.viewportHeight = 60
    wait(50)
    compare(s.height, 240, "never smaller than the floor")
    compare(find(s, "graphView").height, s.height)
  }

  function test_the_story_view_draws_a_node_per_story_inside_its_milestone_box() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    s.app.board.applyTreeData([
      card("m1", "First", "in_progress", [card("s1", "Story one", "in_progress", [card("t1", "Sub", "in_progress")])]),
      card("m2", "Second", "todo", [card("s2", "Story two", "todo")]),
      card("m3", "Third", "todo")])
    s.app.graph.setGraphView("story")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.mode, "story")
    compare(gv.nodes.map(function(n) { return n.id }).join(","), "s1,s2")
    compare(gv.groups.map(function(g) { return g.id }).join(","), "m1,m2")
    compare(find(find(s, "graphNodes1"), "graphNodeTitle").text, "Story one")
    compare(find(s, "graphGroupLabelm1").text, "First")
    compare(find(find(s, "graphNodes1"), "graphNodePips").model.length, 1)
    verify(!find(s, "graphNodem1"), "no milestone nodes in the story view")
    s.app.graph.setGraphView("milestone")
    wait(100)
    compare(find(s, "graphView").mode, "milestone")
    verify(find(s, "graphNodem1"), "and back again")
  }

  function test_the_story_view_draws_the_box_to_box_dependency_from_the_board() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    var m2 = card("m2", "Second", "todo", [card("s2", "Story two", "todo")])
    m2.blocked_by = ["m1"]
    s.app.board.applyTreeData([card("m1", "First", "todo", [card("s1", "Story one", "todo")]), m2])
    s.app.graph.setGraphView("story")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.groupEdges.map(function(e) { return e.id }).join(","), "m1>m2")
    var drawn = find(s, "graphGroupEdges")
    compare(drawn.segments.length, 1, "and it is drawn between the two boxes")
    compare(drawn.segments[0].fromX, find(s, "graphGroupm1").x + find(s, "graphGroupm1").width)
    s.app.graph.setGraphView("milestone")
    wait(100)
    compare(find(s, "graphView").groupEdges.length, 0, "the milestone view draws its own edges only")
  }

  function test_clicking_a_story_node_opens_that_story_card() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    s.app.board.applyTreeData([card("m1", "First", "todo", [card("s1", "Story one", "todo")])])
    s.app.graph.setGraphView("story")
    wait(100)
    find(s, "graphView").nodeClicked("s1")
    compare(s.app.graph.graphCursor, "s1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "s1")
  }

  function test_open_issues_from_the_board_mark_the_milestone_they_block() {
    var s = make(); if (!s) return
    s.navigator.showSection("graph")
    var m2 = card("m2", "Second", "blocked")
    m2.blocked_by = ["i1", "i2"]
    s.app.board.applyTreeData([card("m1", "First", "done", [card("s1", "Story", "done")]), m2])
    s.app.board.issueProc.stdout.text = JSON.stringify({ ok: true, data: [
      { id: "i1", kind: "issue", title: "Broken build", status: "open" },
      { id: "i2", kind: "issue", title: "Old bug", status: "closed" }] })
    s.app.board.issueProc.stdout.streamFinished()
    wait(100)
    var marker = find(find(s, "graphNodem2"), "graphNodeIssues")
    compare(marker.visible, true)
    compare(marker.text, "\uF024 1 open issue")
    compare(find(find(s, "graphNodem1"), "graphNodeIssues").visible, false)
  }

  // ---- 5.3: the am run marks the screen hands the view.

  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }

  // m1 heads a live run working on t1 (t2 still pending); m2 is merged but a
  // live run still names it; m3 is untouched.
  function withRuns(s) {
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([
      card("m1", "First", "in_progress", [card("s1", "Story one", "in_progress",
        [card("t1", "Sub one", "in_progress"), card("t2", "Sub two", "todo")])]),
      card("m2", "Second", "merged", [card("s2", "Story two", "merged")]),
      card("m3", "Third", "todo", [card("s3", "Story three", "todo")])])
    s.app.runs.runs = [
      mkRun("run-a1", "started", true, "m1",
        { stories: [{ card_id: "s1", subtasks: ["t1", "t2"] }],
          subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] },
                     { card_id: "t2", phases: [] }] },
        [{ card_id: "t1", status: "running" }, { card_id: "t2", status: "pending" }]),
      mkRun("run-b2", "started", true, "m2", { stories: [{ card_id: "s2", subtasks: [] }], subtasks: [] }, [])]
    return s
  }

  function test_the_graph_view_gets_the_run_marks_from_the_run_store() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runMarks.m1.state, "running")
    compare(gv.runMarks.m1.runId, "run-a1")
    compare(gv.runRollups.m1.running, 1)
    compare(gv.runRollups.m1.pending, 1)
    compare(gv.runRollups.m1.total, 2)
    compare(gv.runMarks.m3.state, "none", "an untouched node is passed as none")
    compare(gv.runRinged.length, 0, "milestone nodes carry no pips")
    var badge = find(find(s, "graphNodem1"), "runBadge")
    verify(badge && badge.visible, "the milestone node draws the badge")
    compare(badge.text, "⟳ 1")
    compare(gv.runStale, false)
    s.app.runs.stale = true
    compare(gv.runStale, true, "stale reaches the view")
  }

  function test_a_merged_node_gets_no_run_mark_even_when_a_run_touches_it() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runMarks.m2, undefined, "the brd-status gate decides visibility")
    compare(gv.runRollups.m2, undefined)
    compare(find(find(s, "graphNodem2"), "runMark").visible, false)
  }

  function test_the_story_view_rings_only_the_subtask_a_live_run_is_working_on() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    s.app.graph.setGraphView("story")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runRinged.join(","), "t1", "t2 is in the run but its own row is pending")
    var pips = find(find(s, "graphNodes1"), "graphNodePips")
    compare(find(pips, "statusPipt1").ringed, true)
    compare(find(pips, "statusPipt2").ringed, false)
    compare(gv.runMarks.s1.state, "running")
    compare(gv.runRollups.s1.total, 2)
    compare(gv.runMarks.s2, undefined, "a merged story is gated too")
  }

  function test_am_missing_passes_no_run_marks() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.showSection("graph")
    s.app.graph.setGraphView("story")
    s.app.runs.amStatus = "missing"
    wait(100)
    var gv = find(s, "graphView")
    compare(Object.keys(gv.runMarks).length, 0)
    compare(Object.keys(gv.runRollups).length, 0)
    compare(gv.runRinged.length, 0)
    verify(find(s, "graphNodes1"), "the graph still renders")
    compare(find(find(s, "graphNodes1"), "runMark").visible, false)
  }

  function test_a_canceled_or_archived_node_gets_no_run_mark_either() {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([
      card("m1", "First", "canceled", [card("s1", "Story one", "canceled")]),
      card("m2", "Second", "archived", [card("s2", "Story two", "archived")]),
      card("m3", "Third", "in_progress", [card("s3", "Story three", "in_progress")])])
    s.app.runs.runs = [
      mkRun("run-a1", "started", true, "m1", { stories: [{ card_id: "s1", subtasks: [] }], subtasks: [] }, []),
      mkRun("run-b2", "started", true, "m2", { stories: [{ card_id: "s2", subtasks: [] }], subtasks: [] }, []),
      mkRun("run-c3", "started", true, "m3", { stories: [{ card_id: "s3", subtasks: [] }], subtasks: [] }, [])]
    s.navigator.showSection("graph")
    wait(100)
    var gv = find(s, "graphView")
    compare(gv.runMarks.m1, undefined, "canceled")
    compare(gv.runMarks.m2, undefined, "archived")
    compare(gv.runMarks.m3.state, "running", "a live node keeps its mark")
    compare(find(find(s, "graphNodem1"), "runMark").visible, false)
    compare(find(find(s, "graphNodem2"), "runMark").visible, false)
    compare(find(find(s, "graphNodem3"), "runMark").visible, true)
    s.app.graph.setGraphView("story")
    wait(100)
    compare(gv.runMarks.s1, undefined, "a canceled story")
    compare(gv.runMarks.s2, undefined, "an archived story")
    compare(gv.runMarks.s3.state, "running")
  }
}
