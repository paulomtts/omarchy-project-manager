import QtQuick
import QtTest
import "../../ui/components"
TestCase {
  id: tc
  name: "GraphView"
  when: windowShown
  visible: true
  width: 600; height: 400

  Component { id: viewC; GraphView { width: 560; height: 360 } }
  property var nodes: [
    { id: "m1", title: "First", status: "done", done: 1, total: 2, x: 0, y: 0, w: 230, h: 78 },
    { id: "m2", title: "Second", status: "todo", done: 0, total: 0, x: 320, y: 0, w: 230, h: 78 }
  ]
  property var edges: [{ id: "m1>m2", from: "m1", to: "m2" }]

  function find(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    var data = item.data || []
    for (var j = 0; j < data.length; j++) { var d = find(data[j], name); if (d) return d }
    return null
  }

  function test_milestone_nodes_are_instantiated_with_title_and_progress() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    wait(100)
    var first = find(v, "graphNodem1")
    verify(first, "node m1 exists")
    verify(first.width > 0 && first.height > 0)
    compare(find(first, "graphNodeTitle").text, "First")
    compare(find(first, "graphNodeProgress").text, "1/2 done")
    compare(find(find(v, "graphNodem2"), "graphNodeProgress").text, "No stories")
  }

  function test_the_current_node_is_marked() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.cursorId = "m2"
    wait(100)
    compare(find(v, "graphNodem2").current, true)
    compare(find(v, "graphNodem1").current, false)
  }

  function test_an_empty_graph_says_so() {
    var v = createTemporaryObject(viewC, tc)
    compare(find(v, "graphEmpty").visible, true)
    v.nodes = nodes
    compare(find(v, "graphEmpty").visible, false)
  }

  function test_a_milestone_blocked_by_open_issues_shows_a_marker() {
    var v = createTemporaryObject(viewC, tc)
    var withIssues = nodes.map(function(n) { return Object.assign({}, n) })
    withIssues[0].openIssues = 2
    withIssues[1].openIssues = 0
    v.nodes = withIssues
    v.edges = edges
    wait(100)
    var marker = find(find(v, "graphNodem1"), "graphNodeIssues")
    verify(marker, "the open-issue marker")
    compare(marker.visible, true)
    compare(marker.text, "\uF024 2 open issues")
    compare(find(find(v, "graphNodem1"), "graphNodeProgress").text, "1/2 done")
    compare(find(find(v, "graphNodem2"), "graphNodeIssues").visible, false)
    v.nodes = nodes.map(function(n) { return Object.assign({}, n, { openIssues: n.id === "m1" ? 1 : 0 }) })
    wait(50)
    compare(find(find(v, "graphNodem1"), "graphNodeIssues").text, "\uF024 1 open issue")
  }

  // ---- Story view: a node per story, pips instead of the progress text, and a
  // labelled box per milestone behind them.

  property var storyNodes: [
    { id: "s1", title: "First story", status: "in_progress", milestoneId: "m1", openIssues: 0,
      pips: [{ id: "t1", status: "done" }, { id: "t2", status: "in_progress" }], morePips: 2,
      x: 20, y: 40, w: 230, h: 78 },
    { id: "s2", title: "Second story", status: "blocked", milestoneId: "m2", openIssues: 1,
      pips: [], morePips: 0, x: 420, y: 40, w: 230, h: 78 }
  ]
  // Only id and title: where a box IS follows its own stories, live.
  property var storyGroups: [
    { id: "m1", title: "Milestone one" },
    { id: "m2", title: "Milestone two" }
  ]
  // What the two boxes above come out as: s1/s2 padded, with the label strip.
  property var boxOne: ({ x: 20 - 16, y: 40 - 30, w: 230 + 32, h: 78 + 46 })
  property var boxTwo: ({ x: 420 - 16, y: 40 - 30, w: 230 + 32, h: 78 + 46 })

  property var storyGroupEdges: [{ id: "m1>m2", from: "m1", to: "m2" }]

  function story() {
    var v = createTemporaryObject(viewC, tc)
    v.mode = "story"
    v.nodes = storyNodes
    v.edges = [{ id: "s1>s2", from: "s1", to: "s2" }]
    v.groups = storyGroups
    v.groupEdges = storyGroupEdges
    wait(100)
    return v
  }

  function box(v, id) { return find(v, "graphGroup" + id) }

  function test_a_box_edge_is_drawn_between_the_two_box_borders() {
    var v = story()
    var layer = find(v, "graphGroupEdges")
    verify(layer, "the box edge layer")
    compare(layer.segments.length, 1, "one edge per box dependency")
    var one = box(v, "m1")
    var two = box(v, "m2")
    var segment = layer.segments[0]
    compare(segment.id, "m1>m2")
    compare(segment.fromX, one.x + one.width, "it leaves m1's right border")
    compare(segment.fromY, one.y + one.height / 2)
    compare(segment.toX, two.x, "and arrives at m2's left border")
    compare(segment.toY, two.y + two.height / 2)
  }

  function test_the_box_edges_are_told_apart_from_the_story_edges() {
    var v = story()
    var boxes = find(v, "graphGroupEdges")
    var stories = find(find(v, "graphCanvas"), "canvasEdges")
    verify(boxes.strokeWidth > stories.strokeWidth, "a thicker line")
    verify(boxes.strokeColor.a < 1, "at a lower opacity")
    verify(find(v, "graphGroupLayer").z < 0, "behind the story nodes")
  }

  function test_the_milestone_view_draws_no_box_edges() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.groups = storyGroups
    v.groupEdges = storyGroupEdges
    wait(100)
    compare(find(v, "graphGroupLayer").visible, false, "the whole box layer, edges included, is hidden")
    verify(!find(v, "graphGroupLayer").visible)
  }

  // ---- The boxes contain their stories, wherever the stories are.

  // Where the canvas is actually drawing a node: the same working positions the
  // boxes follow. Moving one is what a drag does, frame by frame.
  function dragNode(v, id, x, y) {
    find(v, "graphCanvas")._moveNode(id, { x: x, y: y })
    wait(50)
  }

  function contains(b, node, at) {
    var x = at ? at.x : node.x
    var y = at ? at.y : node.y
    return b.x <= x && x + node.w <= b.x + b.width && b.y <= y && y + node.h <= b.y + b.height
  }

  function test_a_box_follows_the_story_that_is_dragged_out_of_it() {
    var v = story()
    dragNode(v, "s1", 900, 420)
    var one = box(v, "m1")
    verify(contains(one, storyNodes[0], { x: 900, y: 420 }), "s1 is still inside its own box")
    compare(one.x, 900 - 16, "m1 holds only s1, so its box went with it")
    compare(one.width, boxOne.w)
    compare(box(v, "m2").x, boxTwo.x, "another milestone's box does not adopt it")
    compare(box(v, "m2").width, boxTwo.w)
  }

  function test_the_box_edges_follow_the_boxes() {
    var v = story()
    dragNode(v, "s1", -400, 40)
    var one = box(v, "m1")
    var segment = find(v, "graphGroupEdges").segments[0]
    compare(segment.fromX, one.x + one.width, "still anchored on the live border")
  }

  // ---- Moving a whole box.

  function test_moving_a_box_moves_every_story_it_contains() {
    var v = story()
    var one = box(v, "m1")
    var x = one.x
    var y = one.y
    v.moveGroup("m1", 60, -25)
    wait(50)
    compare(v.livePositions.s1.x, storyNodes[0].x + 60)
    compare(v.livePositions.s1.y, storyNodes[0].y - 25)
    compare(v.livePositions.s2.x, storyNodes[1].x, "a story of another milestone stays put")
    compare(box(v, "m1").x, x + 60)
    compare(box(v, "m1").y, y - 25)
    compare(box(v, "m2").x, boxTwo.x)
  }

  function test_a_box_has_a_drag_handle_on_its_label_strip() {
    var v = story()
    var handle = find(v, "graphGroupHandlem1")
    verify(handle, "the header strip drags the box")
    verify(handle.height > 0 && handle.height <= 40, "and only the header strip")
  }

  // A drag is many small moves, and every one of them has to land: the box
  // delegate, and so the handler driving the gesture, must survive them all.
  function test_dragging_the_label_strip_moves_the_box_by_the_whole_pointer_delta() {
    var v = story()
    var handle = find(v, "graphGroupHandlem1")
    var zoom = find(v, "graphCanvas").zoom
    var at = handle.mapToItem(v, 20, handle.height / 2)
    var before = v.livePositions.s1
    mousePress(v, at.x, at.y)
    for (var i = 1; i <= 8; i++) mouseMove(v, at.x + i * 12, at.y + i * 5)
    mouseRelease(v, at.x + 96, at.y + 40)
    wait(50)
    verify(find(v, "graphGroupHandlem1") === handle, "the same handle drove the whole gesture")
    fuzzyCompare(v.livePositions.s1.x, before.x + 96 / zoom, 0.6)
    fuzzyCompare(v.livePositions.s1.y, before.y + 40 / zoom, 0.6)
    compare(v.livePositions.s2.x, storyNodes[1].x, "another milestone's story stays put")
  }

  function test_a_box_keeps_its_delegate_while_it_moves() {
    var v = story()
    var handle = find(v, "graphGroupHandlem1")
    var one = box(v, "m1")
    v.moveGroup("m1", 30, 15)
    wait(50)
    verify(box(v, "m1") === one, "the box item is updated, not rebuilt")
    verify(find(v, "graphGroupHandlem1") === handle)
    dragNode(v, "s1", 400, 300)
    verify(box(v, "m1") === one, "and a node drag does not rebuild it either")
  }

  function test_a_box_drag_lays_the_graph_out_once_not_once_per_pointer_move() {
    var v = story()
    var canvas = find(v, "graphCanvas")
    var handle = find(v, "graphGroupHandlem1")
    var at = handle.mapToItem(v, 20, handle.height / 2)
    var relayouts = 0
    canvas.nodesChanged.connect(function() { relayouts++ })
    mousePress(v, at.x, at.y)
    for (var i = 1; i <= 8; i++) mouseMove(v, at.x + i * 12, at.y)
    wait(50)
    compare(relayouts, 0, "a pointer move goes through the working positions only")
    mouseRelease(v, at.x + 96, at.y)
    wait(50)
    compare(relayouts, 1, "and the arrangement is committed once, at the end")
  }

  function test_organize_reframes_the_view_in_both_modes() {
    var v = story()
    var canvas = find(v, "graphCanvas")
    canvas.panX = 5000; canvas.panY = 5000; canvas.zoom = 3
    find(v, "organizeButton").clicked()
    wait(150)
    verify(canvas.panX !== 5000 && canvas.zoom !== 3, "the story view frames what it organized")
    var m = createTemporaryObject(viewC, tc)
    m.nodes = nodes.map(function(n) { return Object.assign({}, n, { x: 0, y: 0 }) })
    m.edges = edges
    wait(100)
    var milestoneCanvas = find(m, "graphCanvas")
    milestoneCanvas.panX = 5000; milestoneCanvas.panY = 5000; milestoneCanvas.zoom = 3
    find(m, "organizeButton").clicked()
    wait(150)
    verify(milestoneCanvas.panX !== 5000 && milestoneCanvas.zoom !== 3, "and so does the milestone view")
  }

  function test_a_moved_box_survives_a_live_refresh_no_worse_than_a_dragged_node() {
    var v = story()
    v.moveGroup("m1", 60, 0)
    wait(50)
    compare(v.livePositions.s1.x, storyNodes[0].x + 60)
    // A board change rebuilds the model: the layout the user arranged goes,
    // exactly as a dragged node's position does in the milestone view.
    v.nodes = storyNodes.map(function(n) { return Object.assign({}, n) })
    wait(50)
    compare(v.livePositions.s1.x, storyNodes[0].x)
  }

  // ---- Organize.

  function test_organize_lays_the_stories_out_inside_their_own_boxes() {
    var v = story()
    dragNode(v, "s1", 900, 420)
    find(v, "organizeButton").clicked()
    wait(100)
    verify(contains(box(v, "m1"), storyNodes[0], v.livePositions.s1), "s1 is back inside its box")
    verify(contains(box(v, "m2"), storyNodes[1], v.livePositions.s2))
    var one = box(v, "m1")
    var two = box(v, "m2")
    verify(one.x + one.width <= two.x || two.x + two.width <= one.x
           || one.y + one.height <= two.y || two.y + two.height <= one.y, "the boxes do not overlap")
  }

  function test_organize_still_lays_out_the_milestone_view() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes.map(function(n) { return Object.assign({}, n, { x: 0, y: 0 }) })
    v.edges = edges
    wait(100)
    find(v, "organizeButton").clicked()
    wait(100)
    verify(v.livePositions.m2.x > v.livePositions.m1.x, "the blocked milestone moved to the right")
  }

  function test_a_story_node_shows_its_title_and_a_pip_per_subtask() {
    var v = story()
    var first = find(v, "graphNodes1")
    verify(first, "a node per story")
    compare(find(first, "graphNodeTitle").text, "First story")
    var pips = find(first, "graphNodePips")
    verify(pips, "the pips")
    compare(pips.model.length, 2)
    compare(pips.more, 2)
    compare(pips.visible, true)
    verify(!find(first, "graphNodeProgress"), "the done/total text gives way to the pips")
    compare(find(find(v, "graphNodes2"), "graphNodePips").visible, false, "a story with no subtasks shows no pips")
  }

  function test_a_story_blocked_by_open_issues_is_flagged_like_a_milestone() {
    var v = story()
    var marker = find(find(v, "graphNodes2"), "graphNodeIssues")
    compare(marker.visible, true)
    compare(marker.text, "\uF024 1 open issue")
    compare(find(find(v, "graphNodes1"), "graphNodeIssues").visible, false)
  }

  function test_every_group_draws_a_labelled_box_around_its_stories() {
    var v = story()
    var box = find(v, "graphGroupm1")
    verify(box, "a box per milestone")
    compare(box.x, boxOne.x)
    compare(box.y, boxOne.y)
    compare(box.width, boxOne.w)
    compare(box.height, boxOne.h)
    compare(find(v, "graphGroupLabelm1").text, "Milestone one")
    compare(find(v, "graphGroupLabelm2").text, "Milestone two")
    verify(find(v, "graphGroupLayer").z < 0, "the boxes sit behind the nodes")
  }

  function test_the_milestone_view_draws_no_boxes() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.groups = storyGroups
    wait(100)
    compare(find(v, "graphGroupLayer").visible, false)
    verify(find(v, "graphNodem1"), "and keeps the milestone nodes")
  }

  function test_the_boxes_follow_the_canvas_camera() {
    var v = story()
    var layer = find(v, "graphGroupLayer")
    var canvas = find(v, "graphCanvas")
    canvas.panX = 37
    canvas.panY = -12
    canvas.zoom = 2
    wait(50)
    compare(layer.x, 37)
    compare(layer.y, -12)
    compare(layer.scale, 2)
  }

  function test_hiding_the_graph_stops_the_pips_pulsing() {
    var v = story()
    var pips = find(find(v, "graphNodes1"), "graphNodePips")
    compare(pips.pulsing, true, "a subtask is in progress")
    v.visible = false
    wait(60)
    compare(pips.pulsing, false, "a graph nobody is looking at animates nothing")
    v.visible = true
    wait(60)
    compare(pips.pulsing, true)
  }

  function test_the_fit_frames_the_boxes_and_not_only_the_nodes() {
    // A wide, short viewport: the node alone would be framed at a zoom that
    // pushes the box's label strip off the top edge.
    var v = createTemporaryObject(viewC, tc, { width: 600, height: 200 })
    v.mode = "story"
    // One milestone, one story: the box is the node plus its padding and the
    // strip that carries the label, and all of it has to be on screen.
    v.nodes = [{ id: "s1", title: "Only", status: "todo", milestoneId: "m1", openIssues: 0,
                 pips: [], morePips: 0, x: 16, y: 30, w: 230, h: 78 }]
    v.groups = [{ id: "m1", title: "Milestone one", x: 0, y: 0, w: 262, h: 124 }]
    wait(200)
    var box = find(v, "graphGroupm1")
    var topLeft = box.mapToItem(v, 0, 0)
    var bottomRight = box.mapToItem(v, box.width, box.height)
    verify(topLeft.x >= 0 && topLeft.y >= 0,
           "the box's label strip and padding are framed (" + topLeft.x + "," + topLeft.y + ")")
    verify(bottomRight.x <= v.width && bottomRight.y <= v.height,
           "and so is its far corner (" + bottomRight.x + "," + bottomRight.y + ")")
  }

  function test_an_empty_story_graph_says_so() {
    var v = createTemporaryObject(viewC, tc)
    v.mode = "story"
    wait(50)
    compare(find(v, "graphEmpty").visible, true)
    compare(find(v, "graphEmpty").text, "No stories in this project.")
  }

  // ---- 5.3: am run marks, handed in by GraphScreen.

  function runMark(state, dimmed) { return { state: state, runId: "r1", dimmed: dimmed === true, phase: "", attempt: 0 } }

  function test_run_marks_draw_a_badge_and_a_rollup_bar_on_a_milestone_node() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.runMarks = { m1: runMark("running") }
    v.runRollups = { m1: { running: 1, parked: 0, escalated: 0, done: 1, pending: 2, total: 4 } }
    wait(100)
    var first = find(v, "graphNodem1")
    var mark = find(first, "runMark")
    verify(mark, "the node carries a run mark")
    compare(mark.visible, true)
    compare(find(first, "runBadge").text, "⟳ 1 ✔ 1")
    var bar = find(first, "runRollupBar")
    compare(bar.visible, true)
    compare(find(bar, "runRollupPending").text, "2 pending")
    compare(find(first, "graphNodeTitle").text, "First", "the title stays")
    compare(find(first, "graphNodeProgress").text, "1/2 done", "and so does the brd progress")
    var second = find(v, "graphNodem2")
    compare(find(second, "runMark").visible, false, "a node with no entry draws no mark")
    compare(find(second, "runRollupBar").visible, false)
  }

  function test_without_run_props_no_node_draws_a_run_mark() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    wait(100)
    compare(find(find(v, "graphNodem1"), "runMark").visible, false)
    compare(find(find(v, "graphNodem1"), "runRollupBar").visible, false)
    var s = story()
    compare(find(find(s, "graphNodes1"), "runMark").visible, false)
    compare(find(find(s, "graphNodes1"), "statusPipt2").ringed, false)
  }

  function test_run_marks_draw_on_story_nodes_and_ring_the_running_pip() {
    var v = story()
    v.runMarks = { s1: runMark("escalated", true) }
    v.runRollups = { s1: { running: 0, parked: 0, escalated: 1, done: 0, pending: 0, total: 1 } }
    v.runRinged = ["t2"]
    wait(50)
    var first = find(v, "graphNodes1")
    var mark = find(first, "runMark")
    compare(mark.visible, true)
    compare(find(first, "runBadge").text, "‼ 1")
    verify(mark.opacity < 1, "a dimmed winner is drawn dimmed")
    compare(find(first, "runRollupBar").visible, true)
    verify(find(first, "runRollupBar").opacity < 1, "and so is its bar")
    var pips = find(first, "graphNodePips")
    compare(find(pips, "statusPipt2").ringed, true)
    compare(find(pips, "statusPipt1").ringed, false)
    compare(find(find(v, "graphNodes2"), "runMark").visible, false)
  }

  function test_stale_run_data_dims_the_node_marks() {
    var v = createTemporaryObject(viewC, tc)
    v.nodes = nodes
    v.edges = edges
    v.runMarks = { m1: runMark("running") }
    wait(100)
    var mark = find(find(v, "graphNodem1"), "runMark")
    compare(mark.opacity, 1)
    compare(find(mark, "runBadge").text, "⟳")
    compare(find(mark, "runBadge").pulsing, true)
    v.runStale = true
    wait(30)
    compare(mark.opacity, 0.5)
    compare(find(mark, "runBadge").pulsing, false)
  }

  function test_run_props_of_the_wrong_shape_draw_nothing() {
    var v = story()
    var withOdd = storyNodes.map(function(n) { return Object.assign({}, n) })
    withOdd[1].id = "constructor"
    v.nodes = withOdd
    wait(50)
    var bad = [null, "s1", ["s1"], 5]
    for (var i = 0; i < bad.length; i++) {
      v.runMarks = bad[i]
      v.runRollups = bad[i]
      v.runRinged = bad[i]
      wait(20)
      compare(find(find(v, "graphNodes1"), "runMark").visible, false, "bad " + i)
      compare(find(find(v, "graphNodes1"), "statusPipt2").ringed, false, "bad " + i)
    }
    v.runMarks = ({})
    v.runRollups = ({})
    wait(20)
    compare(find(find(v, "graphNodeconstructor"), "runMark").visible, false, "an inherited name is not an entry")
    compare(find(find(v, "graphNodeconstructor"), "runRollupBar").visible, false)
  }
}
