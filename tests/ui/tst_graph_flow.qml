import QtQuick
import QtTest
import "../helpers/find.js" as H
TestCase {
  id: tc
  name: "GraphFlow"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function card(id, status, children, blockedBy) {
    return { id: id, title: "T " + id, description: "", status: status, blocked_by: blockedBy || [],
             created_at: "", updated_at: "", children: children || [] }
  }
  function roots() {
    return [card("m1", "done", [card("s1", "done")]), card("m2", "todo", [], ["m1"]), card("m3", "todo", [], ["m2"])]
  }
  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA, pB])
    p.app.board.applyTreeData(roots())
    return p
  }
  function named(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }
  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }

  function test_the_graph_section_shows_and_selects_the_first_milestone() {
    var p = make(); if (!p) return
    p.navigator.showSection("graph")
    compare(p.app.nav.viewMode, "graph")
    compare(p.app.nav.section, "graph")
    compare(p.app.nav.sectionTitle, "Graph")
    compare(p.app.graph.graphCursor, "m1")
    compare(p.app.graph.graph.nodes.length, 3)
  }

  function test_ctrl_2_shows_the_graph() {
    var p = make(); if (!p) return
    var event = { key: Qt.Key_2, modifiers: Qt.ControlModifier, accepted: false }
    compare(p.shortcuts.handleGlobalKey(event), true)
    compare(p.app.nav.viewMode, "graph")
  }

  function test_key_catcher_moves_and_activates_in_the_graph() {
    var p = make(); if (!p) return
    p.navigator.showSection("graph")
    var kc = p.focusItem
    compare(kc.objectName, "keyCatcher")
    kc.moveRequested(1, 0)
    compare(p.app.graph.graphCursor, "m2")
    kc.moveRequested(-1, 0)
    compare(p.app.graph.graphCursor, "m1")
    kc.activateRequested()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "m1")
    compare(p.app.nav.section, "graph")
  }

  function test_back_from_a_card_returns_to_the_graph_with_the_selection() {
    var p = make(); if (!p) return
    p.navigator.showSection("graph")
    p.navigator.moveGraph("right")
    p.navigator.activateGraphNode()
    compare(p.app.nav.viewMode, "entry")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "graph")
    compare(p.app.graph.graphCursor, "m2")
  }

  function test_back_from_a_board_card_still_returns_to_the_board() {
    var p = make(); if (!p) return
    p.navigator.openCard("m2")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board")
  }

  function test_the_graph_view_receives_the_model_and_clicks_open_the_card() {
    var p = make(); if (!p) return
    p.navigator.showSection("graph")
    var gv = find(p, "graphView")
    verify(gv, "graphView")
    compare(gv.nodes.length, 3)
    compare(gv.edges.length, 2)
    gv.nodeClicked("m2")
    compare(p.app.graph.graphCursor, "m2")
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "m2")
  }

  // ---- The Milestone | Story switch in the toolbar.

  function storyRoots() {
    return [card("m1", "in_progress", [card("s1", "done", [card("t1", "done")]), card("s2", "todo")]),
            card("m2", "todo", [card("s3", "todo", [], ["s1"])])]
  }

  function test_the_toolbar_offers_the_two_graph_views_with_one_always_active() {
    var p = make(); if (!p) return
    p.navigator.showSection("graph")
    var row = find(p, "graphViewChips")
    verify(row, "the view switch")
    compare(find(p, "graphViewChipmilestone").active, true, "Milestone is the default")
    compare(find(p, "graphViewChipstory").active, false)
    row.chosen("story")
    compare(p.app.graph.graphView, "story")
    compare(find(p, "graphViewChipstory").active, true)
    compare(find(p, "graphViewChipmilestone").active, false)
    row.chosen("milestone")
    compare(find(p, "graphViewChipmilestone").active, true)
  }

  function test_the_story_view_reaches_the_canvas_and_opens_a_story_card() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData(storyRoots())
    p.navigator.showSection("graph")
    find(p, "graphViewChips").chosen("story")
    wait(100)
    var gv = find(p, "graphView")
    compare(gv.mode, "story")
    compare(gv.nodes.length, 3)
    compare(gv.groups.length, 2)
    compare(p.app.graph.graphCursor, "s1")
    var kc = p.focusItem
    kc.moveRequested(1, 0)
    compare(p.app.graph.graphCursor, "s3", "the arrow keys walk the story graph")
    kc.activateRequested()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "s3")
  }

  function test_back_from_a_story_returns_to_the_story_view_and_its_selection() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData(storyRoots())
    p.navigator.showSection("graph")
    find(p, "graphViewChips").chosen("story")
    p.navigator.moveGraph("right")
    p.navigator.activateGraphNode()
    compare(p.app.nav.viewMode, "entry")
    compare(p.app.board.selectedCardId, "s3")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "graph")
    compare(p.app.graph.graphView, "story", "Back comes back to the view it left")
    compare(p.app.graph.graphCursor, "s3")
    wait(100)
    compare(find(p, "graphView").mode, "story")
  }

  function test_entering_the_graph_seeds_the_cursor_from_the_view_on_show() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData(storyRoots())
    p.app.graph.setGraphView("story")
    p.app.graph.graphCursor = ""
    p.navigator.showSection("graph")
    compare(p.app.graph.graphCursor, "s1", "the first node of the CURRENT view")
  }

  function test_the_popup_is_at_least_eighty_percent_of_the_screen_tall() {
    var p = make(); if (!p) return
    var panel = named(p, "mainPanel")
    verify(panel, "mainPanel")
    verify(panel.contentHeight >= 0.8 * panel.screenH, "height " + panel.contentHeight)
  }

  function test_the_popup_is_about_eighty_percent_of_the_screen_wide() {
    var p = make(); if (!p) return
    var panel = named(p, "mainPanel")
    verify(panel.contentWidth >= 0.8 * panel.screenW - 1, "width " + panel.contentWidth)
  }

  // ---- am run marks (5.3)

  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }

  function test_a_story_node_shows_the_run_badge_the_rollup_and_the_ringed_pip() {
    var p = make(); if (!p) return
    p.app.runs.snapshotRunner.cancel()
    p.app.board.applyTreeData([card("m1", "in_progress",
      [card("s1", "in_progress", [card("t1", "in_progress"), card("t2", "todo")])])])
    p.app.runs.runs = [mkRun("run-0000000000a1", "started", true, "m1",
      { stories: [{ card_id: "s1", subtasks: ["t1", "t2"] }],
        subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] },
                   { card_id: "t2", status: "pending", phases: [] }] },
      [{ card_id: "t1", status: "running" }, { card_id: "t2", status: "pending" }])]
    p.navigator.showSection("graph")
    find(p, "graphViewChips").chosen("story")
    wait(200)
    var gv = H.find(p, "graphView")
    compare(gv.runRinged.join(","), "t1", "only the subtask am is working on is ringed")
    var node = H.find(p, "graphNodes1")
    verify(node, "the story node is drawn")
    compare(H.find(node, "runMark").visible, true)
    compare(H.find(node, "runBadge").text, "⟳ 1")
    var bar = H.find(node, "runRollupBar")
    compare(bar.visible, true)
    compare(H.find(bar, "runRollupPending").text, "1 pending")
    compare(H.find(node, "statusPipt1").ringed, true)
    compare(H.find(node, "statusPipt2").ringed, false)
  }
}
