// tests/core/stores/tst_graph_store.qml
// The milestone dependency graph: its model, and the keyboard selection that
// walks it. Driven through App so the board -> graph wiring is exercised too.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresGraphStore"

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
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    app.board.applyTreeData(roots())
    app.graph.graphCursor = "m1"
    return app
  }

  function test_the_model_follows_the_board() {
    var app = make(); if (!app) return
    compare(app.graph.graph.nodes.length, 3, "one node per milestone")
    compare(app.graph.graph.edges.length, 2)
    app.board.applyTreeData([card("m1", "todo")])
    compare(app.graph.graph.nodes.length, 1)
    compare(app.graph.graph.edges.length, 0)
    app.board.applyTreeData([])
    compare(app.graph.graph.nodes.length, 0)
  }

  function test_arrow_keys_move_the_selection_along_the_dependency_chain() {
    var app = make(); if (!app) return
    compare(app.graph.moveGraph("right"), "m2")
    compare(app.graph.graphCursor, "m2")
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m3")
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m3")
    app.graph.moveGraph("left")
    compare(app.graph.graphCursor, "m2")
  }

  function test_an_unknown_selection_recovers_to_the_first_milestone() {
    var app = make(); if (!app) return
    app.graph.graphCursor = "gone"
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m1")
  }

  function test_moving_an_empty_graph_selects_nothing() {
    var app = make(); if (!app) return
    app.board.applyTreeData([])
    compare(app.graph.moveGraph("right"), "")
    compare(app.graph.graphCursor, "m1", "an empty graph leaves the selection alone")
  }

  function test_switching_project_clears_the_graph_selection() {
    var app = make(); if (!app) return
    app.graph.moveGraph("right")
    compare(app.graph.graphCursor, "m2")
    app.projects.selectProject(pB)
    compare(app.graph.graphCursor, "")
  }

  function test_activating_a_node_reports_the_selected_card() {
    var app = make(); if (!app) return
    app.graph.moveGraph("right")
    compare(app.graph.activateGraphNode(), "m2")
    app.graph.graphCursor = ""
    compare(app.graph.activateGraphNode(), "")
  }

  // ---- The two views: Milestone (the default) and Story.

  function storyRoots() {
    return [card("m1", "in_progress", [card("s1", "done", [card("t1", "done")]), card("s2", "todo")]),
            card("m2", "todo", [card("s3", "todo", [], ["s1"])])]
  }

  function test_the_milestone_view_is_the_default_and_drives_the_current_model() {
    var app = make(); if (!app) return
    compare(app.graph.graphView, "milestone")
    compare(app.graph.currentNodes.length, app.graph.graph.nodes.length)
    compare(app.graph.currentEdges.length, app.graph.graph.edges.length)
    compare(app.graph.currentGroups.length, 0, "the milestone view has no group boxes")
    compare(app.graph.currentGroupEdges.length, 0, "and no box-to-box edges")
  }

  function test_the_story_view_serves_the_box_to_box_edges() {
    var app = make(); if (!app) return
    app.board.applyTreeData(storyRoots())
    app.graph.setGraphView("story")
    // s3 (m2) is blocked by s1 (m1): the two boxes depend on each other.
    compare(app.graph.currentGroupEdges.map(function(e) { return e.id }).join(","), "m1>m2")
    compare(app.graph.storyGraph.groupEdges.length, 1)
    app.graph.setGraphView("milestone")
    compare(app.graph.currentGroupEdges.length, 0)
  }

  function test_the_story_view_serves_the_story_model_and_its_groups() {
    var app = make(); if (!app) return
    app.board.applyTreeData(storyRoots())
    app.graph.setGraphView("story")
    compare(app.graph.graphView, "story")
    compare(app.graph.currentNodes.map(function(n) { return n.id }).join(","), "s1,s2,s3")
    compare(app.graph.currentEdges.map(function(e) { return e.id }).join(","), "s1>s3")
    compare(app.graph.currentGroups.map(function(g) { return g.id }).join(","), "m1,m2")
    compare(app.graph.storyGraph.nodes.length, 3)
  }

  function test_an_unknown_view_is_refused() {
    var app = make(); if (!app) return
    app.graph.setGraphView("nonsense")
    compare(app.graph.graphView, "milestone", "one of the two is always active")
    app.graph.setGraphView("story")
    app.graph.setGraphView("")
    compare(app.graph.graphView, "story")
  }

  function test_switching_view_puts_the_cursor_on_a_node_of_that_view() {
    var app = make(); if (!app) return
    app.board.applyTreeData(storyRoots())
    app.graph.graphCursor = "m2"
    app.graph.setGraphView("story")
    compare(app.graph.graphCursor, "s1", "a milestone is no node of the story graph")
    app.graph.graphCursor = "s3"
    app.graph.setGraphView("story")
    compare(app.graph.graphCursor, "s3", "the same view again leaves the selection alone")
    app.graph.setGraphView("milestone")
    compare(app.graph.graphCursor, "m1")
  }

  function test_the_arrow_keys_walk_the_story_graph() {
    var app = make(); if (!app) return
    app.board.applyTreeData(storyRoots())
    app.graph.setGraphView("story")
    compare(app.graph.graphCursor, "s1")
    compare(app.graph.moveGraph("right"), "s3", "s3 is blocked by s1, so it sits to its right")
    compare(app.graph.activateGraphNode(), "s3")
    compare(app.graph.moveGraph("left"), "s1")
  }

  function test_the_chosen_view_survives_a_project_switch() {
    var app = make(); if (!app) return
    app.board.applyTreeData(storyRoots())
    app.graph.setGraphView("story")
    app.projects.selectProject(pB)
    compare(app.graph.graphView, "story", "the view is remembered for the session, not per project")
    compare(app.graph.graphCursor, "", "the selection still goes")
  }

  function test_the_model_counts_open_issues_from_the_board() {
    var app = make(); if (!app) return
    app.board.applyTreeData([card("m1", "blocked", [], ["i1", "i2"]), card("m2", "todo")])
    compare(app.graph.graph.nodes[0].openIssues, 0, "no issues known yet")
    app.board.applyIssueData([{ id: "i1", title: "A", status: "open" }, { id: "i2", title: "B", status: "closed" }])
    compare(app.graph.graph.nodes[0].openIssues, 1)
    compare(app.graph.graph.nodes[1].openIssues, 0)
  }

  function archivedBoard() {
    return [card("m1", "done", [card("s1", "done"), card("s2", "archived")]),
            card("m2", "archived", [card("s3", "done")]),
            card("m3", "todo", [card("s4", "todo")], ["m1"])]
  }

  function test_archived_cards_are_hidden_by_default_in_both_views() {
    var app = make(); if (!app) return
    app.board.applyTreeData(archivedBoard())
    compare(app.graph.showArchived, false, "off by default")
    compare(app.graph.graph.nodes.map(function(n) { return n.id }).join(","), "m1,m3")
    app.graph.setGraphView("story")
    compare(app.graph.currentNodes.map(function(n) { return n.id }).sort().join(","), "s1,s4",
            "no archived story, and none under an archived milestone")
  }

  function test_showing_archived_brings_them_back_and_hiding_removes_them_again() {
    var app = make(); if (!app) return
    app.board.applyTreeData(archivedBoard())
    app.graph.setShowArchived(true)
    compare(app.graph.graph.nodes.length, 3)
    app.graph.setGraphView("story")
    compare(app.graph.currentNodes.length, 4, "s1, s2, s3, s4")
    app.graph.setShowArchived(false)
    compare(app.graph.currentNodes.length, 2)
  }

  function test_hiding_archived_moves_a_selection_that_disappeared() {
    var app = make(); if (!app) return
    app.board.applyTreeData(archivedBoard())
    app.graph.setShowArchived(true)
    app.graph.graphCursor = "m2"
    app.graph.setShowArchived(false)
    verify(app.graph.graphCursor !== "m2", "the cursor left the hidden node")
    compare(app.graph.graphCursor, "m1", "it lands on the first visible node")
  }

  function test_the_archived_choice_is_remembered_across_a_board_refresh() {
    var app = make(); if (!app) return
    app.graph.setShowArchived(true)
    app.board.applyTreeData(archivedBoard())
    compare(app.graph.showArchived, true)
  }
}
