// tests/core/domain/tst_graph.qml
import QtQuick
import QtTest
import "../../../core/domain/graph.js" as Graph

TestCase {
  name: "DomainGraph"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function graphRoots() {
    return [
      makeCard("m1", "done", [makeCard("s1", "done", []), makeCard("s2", "todo", [])]),
      makeCard("m2", "todo", [makeCard("s3", "todo", [])], ["m1"]),
      makeCard("m3", "blocked", [], ["m2", "ghost"]),
      makeCard("m4", "in_progress", [])
    ]
  }

  function test_graph_model_has_a_node_per_milestone_with_progress() {
    var g = Graph.graphModel(graphRoots())
    compare(g.nodes.map(function(n) { return n.id }).join(","), "m1,m2,m3,m4")
    compare(g.nodes[0].title, "m1")
    compare(g.nodes[0].status, "done")
    compare(g.nodes[0].done, 1)
    compare(g.nodes[0].total, 2)
    compare(g.nodes[2].status, "blocked")
    compare(g.nodes[3].total, 0)
  }

  function test_graph_edges_run_from_blocker_to_blocked_and_skip_unknown_ids() {
    var g = Graph.graphModel(graphRoots())
    compare(g.edges.map(function(e) { return e.from + ">" + e.to }).join(","), "m1>m2,m2>m3")
    compare(g.edges[0].id, "m1>m2")
  }

  function test_graph_nodes_are_positioned_and_sized_by_the_layout() {
    var g = Graph.graphModel(graphRoots())
    for (var i = 0; i < g.nodes.length; i++) {
      verify(isFinite(g.nodes[i].x) && isFinite(g.nodes[i].y), "node " + i)
      compare(g.nodes[i].w, Graph.GRAPH_NODE_W)
      compare(g.nodes[i].h, Graph.GRAPH_NODE_H)
    }
    verify(g.nodes[1].x > g.nodes[0].x, "blocked milestone sits to the right of its blocker")
    verify(g.nodes[2].x > g.nodes[1].x)
  }

  function test_graph_model_of_nothing_is_empty() {
    compare(Graph.graphModel([]).nodes.length, 0)
    compare(Graph.graphModel(undefined).edges.length, 0)
  }

  function test_graph_move_picks_the_nearest_node_in_the_direction() {
    var nodes = [
      { id: "a", x: 0, y: 0, w: 100, h: 50 },
      { id: "b", x: 300, y: 0, w: 100, h: 50 },
      { id: "c", x: 300, y: 200, w: 100, h: 50 },
      { id: "d", x: 600, y: 10, w: 100, h: 50 }
    ]
    compare(Graph.graphMove(nodes, "a", "right"), "b")
    compare(Graph.graphMove(nodes, "b", "right"), "d")
    compare(Graph.graphMove(nodes, "b", "left"), "a")
    compare(Graph.graphMove(nodes, "b", "down"), "c")
    compare(Graph.graphMove(nodes, "c", "up"), "b")
    compare(Graph.graphMove(nodes, "a", "left"), "a")
    compare(Graph.graphMove(nodes, "d", "down"), "c")
  }

  function test_graph_move_starts_at_the_first_node_when_nothing_is_selected() {
    var nodes = [{ id: "a", x: 0, y: 0 }, { id: "b", x: 300, y: 0 }]
    compare(Graph.graphMove(nodes, "", "right"), "a")
    compare(Graph.graphMove(nodes, "gone", "left"), "a")
    compare(Graph.graphMove([], "", "right"), "")
  }

  function test_open_issue_count_counts_only_open_issue_blockers() {
    var issues = { i1: { id: "i1", title: "A", status: "open" },
                   i2: { id: "i2", title: "B", status: "closed" },
                   i3: { id: "i3", title: "C", status: "open" } }
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i1", "i2", "i3", "m9", "ghost"]), issues), 2)
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i2"]), issues), 0, "a closed issue adds nothing")
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i1", "i1"]), issues), 1, "an id counts once")
    compare(Graph.openIssueCount(makeCard("m", "todo", []), issues), 0)
    compare(Graph.openIssueCount(makeCard("m", "todo", [], ["i1"]), undefined), 0)
    compare(Graph.openIssueCount(undefined, issues), 0)
  }

  function test_open_issue_label_says_how_many_open_issues_block_a_milestone() {
    compare(Graph.openIssueLabel(0), "")
    compare(Graph.openIssueLabel(1), "1 open issue")
    compare(Graph.openIssueLabel(2), "2 open issues")
  }

  function test_graph_nodes_carry_their_open_issue_count_and_issues_draw_no_edges() {
    var issues = { i1: { id: "i1", title: "A", status: "open" },
                   i2: { id: "i2", title: "B", status: "closed" } }
    var roots = graphRoots()
    roots[2].blocked_by = ["m2", "ghost", "i1", "i2"]
    var g = Graph.graphModel(roots, issues)
    compare(g.nodes.map(function(n) { return n.openIssues }).join(","), "0,0,1,0")
    compare(g.edges.map(function(e) { return e.from + ">" + e.to }).join(","), "m1>m2,m2>m3")
    compare(Graph.graphModel(graphRoots()).nodes[0].openIssues, 0, "no issue map: nothing open")
  }

  function test_open_issues_mark_only_a_milestone_brd_reports_as_blocked() {
    var issues = { i1: { id: "i1", title: "A", status: "open" } }
    var roots = [makeCard("m1", "in_progress", [], ["i1"]), makeCard("m2", "done", [], ["i1"]),
                 makeCard("m3", "todo", [], ["i1"]), makeCard("m4", "blocked", [], ["i1"])]
    var g = Graph.graphModel(roots, issues)
    compare(g.nodes.map(function(n) { return n.openIssues }).join(","), "0,0,0,1")
  }

  // ---- Story view: one node per story, every milestone at once, boxed by milestone.

  function storyRoots() {
    return [
      makeCard("m1", "in_progress", [
        makeCard("s1", "done", [makeCard("t1", "done", []), makeCard("t2", "in_progress", [])]),
        makeCard("s2", "todo", [])
      ]),
      makeCard("m2", "todo", [
        makeCard("s3", "blocked", [makeCard("t3", "blocked", [])], ["s1", "i1", "ghost", "t1"])
      ]),
      makeCard("m3", "todo", [])
    ]
  }

  function rectsOverlap(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
  }

  function test_the_story_graph_has_one_node_per_story_of_every_milestone() {
    var g = Graph.storyGraphModel(storyRoots())
    compare(g.nodes.map(function(n) { return n.id }).join(","), "s1,s2,s3")
    compare(g.nodes[0].title, "s1")
    compare(g.nodes[0].status, "done")
    compare(g.nodes[0].milestoneId, "m1")
    compare(g.nodes[2].milestoneId, "m2")
    compare(g.nodes[0].w, Graph.STORY_NODE_W)
    compare(g.nodes[0].h, Graph.STORY_NODE_H)
  }

  function test_story_edges_link_stories_only_and_cross_milestones() {
    var g = Graph.storyGraphModel(storyRoots())
    // s1 is a story of m1, s3 one of m2: the edge crosses two groups. A
    // milestone, a subtask, an issue or an unknown id is not a story link.
    compare(g.edges.map(function(e) { return e.from + ">" + e.to }).join(","), "s1>s3")
    compare(g.edges[0].id, "s1>s3")
    compare(g.nodes[0].milestoneId !== g.nodes[2].milestoneId, true)
  }

  function test_each_story_carries_a_pip_per_subtask_with_its_status() {
    var g = Graph.storyGraphModel(storyRoots())
    compare(g.nodes[0].pips.map(function(p) { return p.status }).join(","), "done,in_progress")
    compare(g.nodes[0].pips[0].id, "t1")
    compare(g.nodes[0].morePips, 0)
    compare(g.nodes[1].pips.length, 0, "a story with no subtasks has no pips")
    compare(g.nodes[2].pips.map(function(p) { return p.status }).join(","), "blocked")
  }

  function test_a_subtask_blocked_by_an_open_issue_pips_as_blocked() {
    var issues = { i1: { id: "i1", title: "A", status: "open" },
                   i2: { id: "i2", title: "B", status: "closed" } }
    var roots = [makeCard("m1", "todo", [makeCard("s1", "todo", [
      makeCard("t1", "todo", [], ["i1"]), makeCard("t2", "todo", [], ["i2"]), makeCard("t3", "blocked", [])])])]
    var g = Graph.storyGraphModel(roots, issues)
    compare(g.nodes[0].pips.map(function(p) { return p.status }).join(","), "blocked,todo,blocked")
  }

  function test_more_subtasks_than_fit_become_a_plus_n() {
    function subs(n) {
      var out = []
      for (var i = 0; i < n; i++) out.push(makeCard("t" + i, "todo", []))
      return out
    }
    var atCap = Graph.storyGraphModel([makeCard("m", "todo", [makeCard("s", "todo", subs(Graph.STORY_PIP_CAP))])])
    compare(atCap.nodes[0].pips.length, Graph.STORY_PIP_CAP, "exactly the cap still fits")
    compare(atCap.nodes[0].morePips, 0)
    var over = Graph.storyGraphModel([makeCard("m", "todo", [makeCard("s", "todo", subs(Graph.STORY_PIP_CAP + 3))])])
    compare(over.nodes[0].pips.length, Graph.STORY_PIP_CAP - 1, "one slot goes to the +N")
    compare(over.nodes[0].morePips, 4)
    compare(over.nodes[0].pips.length + over.nodes[0].morePips, Graph.STORY_PIP_CAP + 3)
  }

  function test_a_story_blocked_by_open_issues_carries_the_count() {
    var issues = { i1: { id: "i1", title: "A", status: "open" }, i2: { id: "i2", title: "B", status: "closed" } }
    var roots = [makeCard("m1", "todo", [makeCard("s1", "blocked", [], ["i1", "i2"]),
                                         makeCard("s2", "todo", [], ["i1"])])]
    var g = Graph.storyGraphModel(roots, issues)
    compare(g.nodes[0].openIssues, 1)
    compare(g.nodes[1].openIssues, 0, "only a story brd reports as blocked is flagged")
  }

  function test_every_group_is_labelled_encloses_its_stories_and_overlaps_no_other() {
    var g = Graph.storyGraphModel(storyRoots())
    compare(g.groups.map(function(gr) { return gr.id }).join(","), "m1,m2", "a milestone with no stories draws no box")
    compare(g.groups[0].title, "m1")
    var boxes = {}
    g.groups.forEach(function(gr) {
      verify(isFinite(gr.x) && isFinite(gr.y) && gr.w > 0 && gr.h > 0, gr.id)
      boxes[gr.id] = gr
    })
    g.nodes.forEach(function(n) {
      var box = boxes[n.milestoneId]
      verify(box.x <= n.x && n.x + n.w <= box.x + box.w, n.id + " fits its box horizontally")
      verify(box.y <= n.y && n.y + n.h <= box.y + box.h, n.id + " fits its box vertically")
    })
    verify(!rectsOverlap(g.groups[0], g.groups[1]), "groups do not overlap")
  }

  function test_story_nodes_are_positioned_so_the_keyboard_can_walk_them() {
    var g = Graph.storyGraphModel(storyRoots())
    g.nodes.forEach(function(n) { verify(isFinite(n.x) && isFinite(n.y), n.id) })
    // s3 is blocked by s1, so it sits to its right and the arrow keys find it.
    compare(Graph.graphMove(g.nodes, "s1", "right"), "s3")
    compare(Graph.graphMove(g.nodes, "s3", "left"), "s1")
    compare(Graph.graphMove(g.nodes, "", "right"), "s1")
  }

  function test_a_repeated_blocker_draws_one_edge_only() {
    var milestones = Graph.graphModel([makeCard("m1", "done", []), makeCard("m2", "todo", [], ["m1", "m1"])])
    compare(milestones.edges.map(function(e) { return e.id }).join(","), "m1>m2")
    var stories = Graph.storyGraphModel([
      makeCard("m1", "todo", [makeCard("s1", "done", []), makeCard("s2", "todo", [], ["s1", "s1"])]),
      makeCard("m2", "todo", [makeCard("s3", "todo", [], ["s1", "s1"])])])
    compare(stories.edges.map(function(e) { return e.id }).join(","), "s1>s2,s1>s3")
    // A blocker named after an Object.prototype member is still just an
    // unknown id: it links nothing.
    compare(Graph.graphModel([makeCard("m1", "todo", [], ["constructor"])]).edges.length, 0)
    compare(Graph.storyGraphModel([makeCard("m1", "todo", [makeCard("s1", "todo", [], ["toString"])])]).edges.length, 0)
  }

  // ---- Box-to-box dependency: the milestone-level reading of the story view.

  function test_box_edges_come_from_the_milestone_blocked_by_links() {
    // No story links at all: the boxes are joined by what brd says about the
    // milestones themselves -- the very links the milestone view draws.
    var g = Graph.storyGraphModel([
      makeCard("m1", "todo", [makeCard("s1", "todo", [])]),
      makeCard("m2", "todo", [makeCard("s2", "todo", [])], ["m1", "ghost", "s1"]),
      makeCard("m3", "todo", [], ["m1"])])
    compare(g.groupEdges.map(function(e) { return e.id }).join(","), "m1>m2",
            "a milestone with no box, an unknown id and a story id link nothing")
    compare(g.groupEdges[0].from, "m1")
    compare(g.groupEdges[0].to, "m2")
    compare(g.edges.length, 0, "and no story edge was invented")
  }

  function test_box_edges_are_also_derived_from_the_story_links() {
    var g = Graph.storyGraphModel(storyRoots())
    // s1 (m1) blocks s3 (m2): milestone-level nothing is declared, yet the two
    // boxes depend on each other.
    compare(g.groupEdges.map(function(e) { return e.id }).join(","), "m1>m2")
  }

  function test_many_story_links_between_two_boxes_draw_one_box_edge() {
    var g = Graph.storyGraphModel([
      makeCard("m1", "todo", [makeCard("s1", "todo", []), makeCard("s2", "todo", [])]),
      makeCard("m2", "todo", [makeCard("s3", "todo", [], ["s1", "s2"]),
                              makeCard("s4", "todo", [], ["s1"])], ["m1"])])
    compare(g.edges.length, 3, "three story links")
    compare(g.groupEdges.map(function(e) { return e.id }).join(","), "m1>m2",
            "declared and derived, deduplicated into one box edge")
  }

  function test_a_box_never_links_to_itself() {
    var g = Graph.storyGraphModel([
      makeCard("m1", "todo", [makeCard("s1", "todo", []), makeCard("s2", "todo", [], ["s1"])], ["m1"])])
    compare(g.edges.map(function(e) { return e.id }).join(","), "s1>s2")
    compare(g.groupEdges.length, 0, "a link inside one box is no box dependency")
  }

  function test_the_boxes_are_ranked_by_the_box_edges() {
    var g = Graph.storyGraphModel([
      makeCard("m1", "todo", [makeCard("s1", "todo", [])]),
      makeCard("m2", "todo", [makeCard("s2", "todo", [])], ["m1"])])
    verify(g.groups[1].x > g.groups[0].x, "the blocked milestone's box sits to the right")
  }

  // ---- Live boxes: the box is its stories' bounding box, wherever they are.

  function test_a_group_box_is_the_bounding_box_of_its_stories() {
    var nodes = [{ id: "s1", milestoneId: "m1", x: 100, y: 50, w: 200, h: 80 },
                 { id: "s2", milestoneId: "m1", x: 400, y: 200, w: 200, h: 80 },
                 { id: "s3", milestoneId: "m2", x: 0, y: 0, w: 200, h: 80 }]
    var groups = [{ id: "m1", title: "One" }, { id: "m2", title: "Two" }]
    var rects = Graph.storyGroupRects(groups, nodes, {})
    compare(rects.length, 2)
    compare(rects[0].id, "m1")
    compare(rects[0].title, "One")
    compare(rects[0].x, 100 - Graph.GROUP_PAD)
    compare(rects[0].y, 50 - Graph.GROUP_HEADER)
    compare(rects[0].w, (600 - 100) + 2 * Graph.GROUP_PAD)
    compare(rects[0].h, (280 - 50) + Graph.GROUP_HEADER + Graph.GROUP_PAD)
  }

  function test_a_box_follows_the_story_that_was_dragged_out_of_it() {
    var nodes = [{ id: "s1", milestoneId: "m1", x: 0, y: 0, w: 200, h: 80 },
                 { id: "s2", milestoneId: "m2", x: 600, y: 0, w: 200, h: 80 }]
    var groups = [{ id: "m1", title: "One" }, { id: "m2", title: "Two" }]
    // s1 is dragged far away: its box grows to keep containing it, and the
    // other milestone's box does not adopt it.
    var rects = Graph.storyGroupRects(groups, nodes, { s1: { x: 900, y: 400 } })
    verify(rects[0].x <= 900 && 900 + 200 <= rects[0].x + rects[0].w, "s1 is inside its own box")
    verify(rects[0].y <= 400 && 400 + 80 <= rects[0].y + rects[0].h)
    compare(rects[1].x, 600 - Graph.GROUP_PAD, "m2's box is untouched by another milestone's story")
    compare(rects[1].w, 200 + 2 * Graph.GROUP_PAD)
  }

  function test_a_group_with_no_placed_story_draws_no_box() {
    compare(Graph.storyGroupRects([{ id: "m1", title: "One" }], [], {}).length, 0)
    compare(Graph.storyGroupRects([{ id: "m1", title: "One" }],
                                  [{ id: "s1", milestoneId: "m1", x: NaN, y: 0, w: 10, h: 10 }], {}).length, 0)
    compare(Graph.storyGroupRects(undefined, undefined, undefined).length, 0)
  }

  function test_the_model_boxes_are_the_bounding_boxes_of_the_placed_stories() {
    var g = Graph.storyGraphModel(storyRoots())
    var rects = Graph.storyGroupRects(g.groups, g.nodes, {})
    compare(JSON.stringify(rects), JSON.stringify(g.groups),
            "one derivation: the model's own boxes are what the live one computes")
  }

  // ---- Moving a whole box, and the positions that override the layout.

  function test_moving_a_box_shifts_exactly_its_own_stories() {
    var nodes = [{ id: "s1", milestoneId: "m1", x: 0, y: 0, w: 200, h: 80 },
                 { id: "s2", milestoneId: "m1", x: 300, y: 100, w: 200, h: 80 },
                 { id: "s3", milestoneId: "m2", x: 600, y: 0, w: 200, h: 80 }]
    var at = Graph.moveGroupPositions(nodes, "m1", 40, -10, {})
    compare(at.s1.x, 40)
    compare(at.s1.y, -10)
    compare(at.s2.x, 340)
    compare(at.s2.y, 90)
    verify(at.s3 === undefined, "another milestone's story stays where it is")
    // Moving again starts from where the stories are NOW, not from the model.
    var again = Graph.moveGroupPositions(nodes, "m1", 10, 10, at)
    compare(again.s1.x, 50)
    compare(again.s1.y, 0)
    compare(Graph.moveGroupPositions(nodes, "m1", NaN, 0, at).s1.x, 40, "a junk delta moves nothing")
    compare(Graph.moveGroupPositions(nodes, "nope", 10, 0, {}).s1, undefined)
  }

  function test_a_position_override_replaces_the_laid_out_one() {
    var nodes = [{ id: "s1", milestoneId: "m1", x: 0, y: 0, w: 200, h: 80 },
                 { id: "s2", milestoneId: "m1", x: 300, y: 100, w: 200, h: 80 }]
    var placed = Graph.placedNodes(nodes, { s1: { x: 12, y: 34 } })
    compare(placed[0].x, 12)
    compare(placed[0].y, 34)
    compare(placed[0].w, 200, "everything else about the node is kept")
    compare(placed[1].x, 300)
    compare(nodes[0].x, 0, "the caller's own nodes are never written")
    compare(Graph.placedNodes(undefined, undefined).length, 0)
    var kept = Graph.withPosition({ s1: { x: 1, y: 2 } }, "s2", 5, 6)
    compare(kept.s1.x, 1)
    compare(kept.s2.y, 6)
    compare(Graph.withPosition({}, "s1", NaN, 0).s1, undefined, "a junk drop is no position")
  }

  // A card is named by brd, so a card CAN be called after an Object.prototype
  // member. No map here may confuse one with what every object already has.
  function test_ids_named_after_object_members_are_ordinary_ids() {
    var roots = [
      makeCard("constructor", "todo", [makeCard("toString", "todo", [])]),
      makeCard("__proto__", "todo", [makeCard("valueOf", "todo", [], ["toString"])], ["constructor"])]
    var g = Graph.storyGraphModel(roots)
    compare(g.nodes.map(function(n) { return n.id }).join(","), "toString,valueOf")
    compare(g.nodes[1].milestoneId, "__proto__")
    compare(g.edges.map(function(e) { return e.id }).join(","), "toString>valueOf")
    compare(g.groups.map(function(gr) { return gr.id }).join(","), "constructor,__proto__")
    compare(g.groupEdges.map(function(e) { return e.id }).join(","), "constructor>__proto__",
            "declared and derived, still one box edge")
    g.groups.forEach(function(gr) {
      verify(isFinite(gr.x) && isFinite(gr.y) && gr.w > 0 && gr.h > 0, gr.id + " is a real box")
    })
    verify(g.groups[1].x > g.groups[0].x, "and the box edge ranked the two boxes")
    compare(JSON.stringify(Graph.storyGroupRects(g.groups, g.nodes, {})), JSON.stringify(g.groups))
    var moved = Graph.moveGroupPositions(g.nodes, "__proto__", 10, 0, {})
    compare(moved.valueOf.x, g.nodes[1].x + 10, "and its stories move with its box")
  }

  function test_adopting_where_one_box_ended_up_touches_that_box_only() {
    var nodes = [{ id: "s1", milestoneId: "m1", x: 0, y: 0, w: 200, h: 80 },
                 { id: "s2", milestoneId: "m2", x: 600, y: 0, w: 200, h: 80 }]
    var live = { s1: { x: 40, y: 40 }, s2: { x: 700, y: 0 } }
    var at = Graph.adoptGroupPositions(nodes, "m1", { s9: { x: 1, y: 2 } }, live)
    compare(at.s1.x, 40)
    compare(at.s1.y, 40)
    compare(at.s9.x, 1, "what was already arranged is kept")
    verify(at.s2 === undefined, "another box's stories are not adopted")
    compare(Graph.adoptGroupPositions(nodes, "m1", {}, { s1: { x: NaN, y: 0 } }).s1, undefined)
    compare(Graph.adoptGroupPositions(nodes, "m1", {}, {}).s1, undefined, "nothing live, nothing adopted")
  }

  function test_the_story_graph_is_deterministic_and_empty_of_nothing() {
    var once = JSON.stringify(Graph.storyGraphModel(storyRoots()))
    var twice = JSON.stringify(Graph.storyGraphModel(storyRoots()))
    compare(once, twice)
    var empty = Graph.storyGraphModel([])
    compare(empty.nodes.length, 0)
    compare(empty.edges.length, 0)
    compare(empty.groups.length, 0)
    compare(empty.groupEdges.length, 0)
    compare(Graph.storyGraphModel(undefined).nodes.length, 0)
    compare(Graph.storyGraphModel([makeCard("m1", "todo", [])]).groups.length, 0)
  }

  function archivedRoots() {
    return [
      makeCard("m1", "done", [makeCard("s1", "done", [makeCard("t1", "done", [])]),
                              makeCard("s2", "archived", [makeCard("t2", "done", [])])]),
      makeCard("m2", "archived", [makeCard("s3", "done", [])], []),
      makeCard("m3", "todo", [makeCard("s4", "todo", [])], ["m2", "m1"])
    ]
  }

  function test_without_archived_drops_archived_cards_at_every_depth() {
    var kept = Graph.withoutArchived(archivedRoots())
    compare(kept.map(function(c) { return c.id }).join(","), "m1,m3", "an archived milestone goes, with its children")
    compare(kept[0].children.map(function(c) { return c.id }).join(","), "s1", "an archived story goes, with its subtasks")
    compare(kept[0].children[0].children.length, 1, "live subtasks stay")
  }

  function test_without_archived_does_not_mutate_its_input() {
    var roots = archivedRoots()
    Graph.withoutArchived(roots)
    compare(roots.length, 3)
    compare(roots[0].children.length, 2)
  }

  function test_without_archived_handles_nothing_and_all_archived() {
    compare(Graph.withoutArchived(null).length, 0)
    compare(Graph.withoutArchived([makeCard("a", "archived", [])]).length, 0)
  }

  function test_the_graph_has_no_edge_to_a_hidden_archived_milestone() {
    var shown = Graph.graphModel(archivedRoots())
    verify(shown.edges.some(function(e) { return e.from === "m2" }), "visible when archived are shown")
    var hidden = Graph.graphModel(Graph.withoutArchived(archivedRoots()))
    compare(hidden.edges.map(function(e) { return e.id }).join(","), "m1>m3", "only the live blocker's edge is left")
  }
}
