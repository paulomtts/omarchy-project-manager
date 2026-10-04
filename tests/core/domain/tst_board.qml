// tests/core/domain/tst_board.qml
import QtQuick
import QtTest
import "../../../core/domain/board.js" as Board

TestCase {
  name: "DomainBoard"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function test_index_tree_on_empty_forest() {
    var result = Board.indexTree([])
    compare(Object.keys(result.cardMap).length, 0)
  }

  function test_index_tree_builds_a_flat_map_of_every_card() {
    var leaf = makeCard("c2", "todo")
    var mid = makeCard("c1", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var result = Board.indexTree([root])

    compare(Object.keys(result.cardMap).length, 3)
    compare(result.cardMap["c2"].id, "c2")
    compare(result.cardMap["c1"].id, "c1")
    compare(result.cardMap["root"].id, "root")
  }

  function test_index_tree_annotates_parent_id() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "todo", [child])
    var result = Board.indexTree([root])
    compare(result.cardMap["root"].parentId, null)
    compare(result.cardMap["child"].parentId, "root")
  }

  function test_index_tree_handles_multiple_roots() {
    var result = Board.indexTree([makeCard("a", "todo"), makeCard("b", "todo")])
    compare(Object.keys(result.cardMap).length, 2)
    compare(result.cardMap["a"].parentId, null)
    compare(result.cardMap["b"].parentId, null)
  }

  function test_subtree_counts_on_childless_card() {
    var counts = Board.subtreeCounts(makeCard("solo", "todo"))
    compare(counts.done, 0)
    compare(counts.total, 0)
  }

  // A card's own status must never be folded into its descendant count --
  // the parent here is "done" but every descendant is still "todo".
  function test_subtree_counts_ignores_own_status_counts_descendants_only() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "done", [child])
    var counts = Board.subtreeCounts(root)
    compare(counts.done, 0)
    compare(counts.total, 1)
  }

  function test_subtree_counts_counts_nested_descendants_recursively() {
    var grandchild1 = makeCard("g1", "done")
    var grandchild2 = makeCard("g2", "todo")
    var child = makeCard("child", "in_progress", [grandchild1, grandchild2])
    var root = makeCard("root", "todo", [child])
    var counts = Board.subtreeCounts(root)
    compare(counts.total, 3)
    compare(counts.done, 1)
  }

  // ---- search --------------------------------------------------------

  function test_subtree_matches_on_own_title() {
    var card = makeCard("root", "todo")
    card.title = "Fix the parser"
    compare(Board.subtreeMatches(card, "parser"), true)
    compare(Board.subtreeMatches(card, "nope"), false)
  }

  // Keeping ancestors of a match visible: a non-matching root whose
  // grandchild matches must still report true.
  function test_subtree_matches_true_for_ancestor_of_a_nested_match() {
    var grandchild = makeCard("g", "todo")
    grandchild.title = "Deep task about parsers"
    var child = makeCard("c", "todo", [grandchild])
    child.title = "Middle"
    var root = makeCard("root", "todo", [child])
    root.title = "Top"
    compare(Board.subtreeMatches(root, "parsers"), true)
    compare(Board.subtreeMatches(child, "parsers"), true)
  }

  function test_subtree_matches_false_when_nothing_in_subtree_matches() {
    var child = makeCard("c", "todo")
    child.title = "Unrelated"
    var root = makeCard("root", "todo", [child])
    root.title = "Also unrelated"
    compare(Board.subtreeMatches(root, "parsers"), false)
  }

  function test_subtree_matches_false_for_undefined_card() {
    compare(Board.subtreeMatches(undefined, "x"), false)
  }

  // ---- colors, kinds, board order, detail links --------------------------

  function test_status_color_maps_known_statuses() {
    compare(Board.statusColor("done", "#111111"), "#7fb069")
    compare(Board.statusColor("blocked", "#111111"), "#e8954a")
    compare(Board.statusColor("in_progress", "#111111"), "#5fa8d3")
  }

  function test_status_color_merged_is_purple_and_canceled_is_red() {
    compare(Board.statusColor("merged", "#111111"), "#9b72cf")
    compare(Board.statusColor("canceled", "#111111"), "#d9534f")
  }

  function test_status_color_archived_has_a_color_of_its_own() {
    var fallback = "#8a8f98"
    var archived = Board.statusColor("archived", fallback)
    compare(archived, "#3fb59a")
    verify(archived !== fallback, "not the neutral grey todo falls back to")
    ;["todo", "done", "blocked", "in_progress", "merged", "canceled"].forEach(function(status) {
      verify(Board.statusColor(status, fallback).toLowerCase() !== archived, "differs from " + status)
    })
  }

  function test_subtree_counts_skip_archived_like_canceled() {
    var root = makeCard("r", "todo", [
      makeCard("a", "done"), makeCard("b", "archived"),
      makeCard("c", "canceled"), makeCard("d", "todo")])
    var counts = Board.subtreeCounts(root)
    compare(counts.done, 1)
    compare(counts.total, 2)
  }

  function test_subtree_counts_treat_merged_as_done_and_skip_canceled() {
    var root = makeCard("r", "todo", [
      makeCard("a", "done"), makeCard("b", "merged"),
      makeCard("c", "canceled"), makeCard("d", "todo")])
    var counts = Board.subtreeCounts(root)
    compare(counts.done, 2)
    compare(counts.total, 3)
  }

  function test_is_closed_status_names_the_statuses_brd_has_closed() {
    compare(Board.isClosedStatus("merged"), true)
    compare(Board.isClosedStatus("canceled"), true)
    compare(Board.isClosedStatus("archived"), true, "should brd ever report it")
    var open = ["todo", "in_progress", "done", "blocked", "cancelled", "", null, undefined, 5, {}]
    for (var i = 0; i < open.length; i++)
      compare(Board.isClosedStatus(open[i]), false, "open " + i)
  }

  function test_status_color_falls_back_for_todo_and_unknown() {
    compare(Board.statusColor("todo", "#111111"), "#111111")
    compare(Board.statusColor("weird", "#111111"), "#111111")
    compare(Board.statusColor(undefined, "#111111"), "#111111")
  }

  function test_kind_label_by_depth() {
    compare(Board.kindLabel(0), "Milestone")
    compare(Board.kindLabel(1), "Story")
    compare(Board.kindLabel(2), "Subtask")
    compare(Board.kindLabel(7), "Subtask")
    compare(Board.kindLabel(undefined), "Card")
    compare(Board.kindLabel(-1), "Card")
  }

  function test_index_tree_annotates_depth() {
    var leaf = makeCard("leaf", "todo")
    var mid = makeCard("mid", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var map = Board.indexTree([root]).cardMap
    compare(map["root"].depth, 0)
    compare(map["mid"].depth, 1)
    compare(map["leaf"].depth, 2)
  }

  function test_effective_status_folds_blocked_into_todo() {
    compare(Board.effectiveStatus(makeCard("a", "blocked")), "todo")
    compare(Board.effectiveStatus(makeCard("a", "done")), "done")
    compare(Board.effectiveStatus(undefined), "todo")
  }

  function test_board_order_groups_by_section_in_order() {
    var a = makeCard("a", "done")
    var b = makeCard("b", "todo")
    var c = makeCard("c", "blocked")
    var d = makeCard("d", "in_progress")
    var ids = Board.boardOrder([a, b, c, d], ["todo", "in_progress", "done"]).map(function(x) { return x.id })
    compare(ids.join(","), "b,c,d,a")
  }

  function test_board_order_empty() {
    compare(Board.boardOrder([], ["todo", "in_progress", "done"]).length, 0)
  }

  function test_detail_links_orders_parent_blockers_children() {
    var kid = makeCard("kid", "todo")
    var dep = makeCard("dep", "todo")
    var mid = makeCard("mid", "todo", [kid], ["dep", "ghost"])
    var root = makeCard("root", "todo", [mid])
    var map = Board.indexTree([root, dep]).cardMap
    var links = Board.detailLinks(map["mid"], map)
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:root,blocker:dep,child:kid")
  }

  function test_detail_links_skips_dangling_blockers_and_missing_parent() {
    var card = makeCard("c", "todo", [], ["ghost"])
    var map = Board.indexTree([card]).cardMap
    compare(Board.detailLinks(card, map).length, 0)
    compare(Board.detailLinks(undefined, {}).length, 0)
  }

  function test_ancestor_ids_walk_from_the_outermost_card_down() {
    var leaf = makeCard("t1", "todo")
    var mid = makeCard("s1", "todo", [leaf])
    var root = makeCard("m1", "todo", [mid])
    var map = Board.indexTree([root]).cardMap
    compare(Board.ancestorIds("t1", map).join(","), "m1,s1")
    compare(Board.ancestorIds("s1", map).join(","), "m1")
    compare(Board.ancestorIds("m1", map).length, 0)
    compare(Board.ancestorIds("nope", map).length, 0)
  }

  function test_index_issues_keeps_id_title_and_open_or_closed_status() {
    var map = Board.indexIssues([
      { id: "i1", kind: "issue", title: "Broken build", body: "b", status: "open", blocks: ["c1"] },
      { id: "i2", kind: "issue", title: "Old bug", status: "closed", close_reason: "fixed" },
      { title: "no id" }
    ])
    compare(Object.keys(map).sort().join(","), "i1,i2")
    compare(map.i1.id, "i1")
    compare(map.i1.title, "Broken build")
    compare(map.i1.status, "open")
    compare(map.i2.status, "closed")
    compare(map.i1.body, undefined, "only what a blocker row needs")
  }

  function test_index_issues_of_nothing_is_empty() {
    compare(Object.keys(Board.indexIssues(undefined)).length, 0)
    compare(Object.keys(Board.indexIssues(null)).length, 0)
    compare(Object.keys(Board.indexIssues([])).length, 0)
  }

  function test_open_issue_counting_moved_here_and_ignores_closed_ones() {
    var issueMap = { i1: { id: "i1", title: "A", status: "open" },
                     i2: { id: "i2", title: "B", status: "closed" },
                     i3: { id: "i3", title: "C", status: "open" } }
    var card = makeCard("c", "blocked", [], ["i1", "i2", "i3", "other"])
    compare(Board.openIssueCount(card, issueMap), 2)
    compare(Board.openIssueLabel(card, issueMap), "2 open issues")
    compare(Board.openIssueLabel(makeCard("d", "blocked", [], ["i1"]), issueMap), "1 open issue")
    compare(Board.openIssueLabel(makeCard("e", "todo", [], []), issueMap), "")
    compare(Board.openIssueLabel(null, issueMap), "")
    compare(Board.openIssueCount(card, null), 0)
    compare(Board.openIssueCount(makeCard("f", "blocked", [], ["i1", "i1"]), issueMap), 1,
            "an id counts once, as the graph model has always counted it")
  }

  function test_resolved_card_prefers_a_card_then_an_issue_then_the_bare_id() {
    var cardMap = { c1: { id: "c1", title: "Card one", status: "todo" } }
    var issueMap = { i1: { id: "i1", title: "Broken build", status: "open" },
                     i2: { id: "i2", title: "Old bug", status: "closed" },
                     c1: { id: "c1", title: "An issue with a card's id", status: "open" } }
    var card = Board.resolvedCard("c1", cardMap, issueMap)
    compare(card.title, "Card one")
    compare(card.status, "todo")
    compare(card.inBoard, true)
    compare(card.kind, undefined)
    var open = Board.resolvedCard("i1", cardMap, issueMap)
    compare(open.id, "i1")
    compare(open.title, "Broken build")
    compare(open.status, "open")
    compare(open.kind, "issue")
    compare(open.inBoard, false)
    compare(Board.resolvedCard("i2", cardMap, issueMap).status, "closed")
    var ghost = Board.resolvedCard("ghost", cardMap, issueMap)
    compare(ghost.title, "ghost")
    compare(ghost.status, "")
    compare(ghost.inBoard, false)
    compare(ghost.kind, undefined)
    compare(Board.resolvedCard("ghost", cardMap, undefined).title, "ghost")
  }

  function test_issue_blocker_label_names_the_issue_state() {
    compare(Board.issueBlockerLabel("open"), "Issue · open")
    compare(Board.issueBlockerLabel("closed"), "Issue · closed")
  }

  // Without an issue map there is nothing to resolve an issue blocker against,
  // so it is as unopenable as a dangling id. The three-argument form below is
  // what the card detail actually calls.
  function test_detail_links_skip_issue_blockers_like_dangling_ids() {
    var c1 = { id: "c1", title: "C", status: "todo", blocked_by: ["x1", "i1"], children: [] }
    var x1 = { id: "x1", title: "X", status: "done", blocked_by: [], children: [] }
    var links = Board.detailLinks(c1, { c1: c1, x1: x1 })
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","), "blocker:x1")
  }

  // An issue blocker the issue map knows IS navigable -- it opens in the Issues
  // section -- so it takes a keyboard link row, in blocked_by order.
  function test_detail_links_list_the_issue_blockers_the_issue_map_knows() {
    var c1 = { id: "c1", title: "C", status: "todo", blocked_by: ["x1", "i1", "ghost"], children: [] }
    var x1 = { id: "x1", title: "X", status: "done", blocked_by: [], children: [] }
    var cardMap = { c1: c1, x1: x1 }
    var issueMap = Board.indexIssues([{ id: "i1", title: "Broken build", status: "open" }])
    var links = Board.detailLinks(c1, cardMap, issueMap)
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","), "blocker:x1,blocker:i1")
    // A closed issue stays in blocked_by and stays readable, so it stays a row.
    var closed = Board.indexIssues([{ id: "i1", title: "Broken build", status: "closed" }])
    compare(Board.detailLinks(c1, cardMap, closed).length, 2)
    // An id in neither map is still left out.
    compare(Board.detailLinks(c1, cardMap, {}).map(function(l) { return l.id }).join(","), "x1")
  }

  // ---- Board.archivable

  readonly property string nowIso: "2026-10-10T12:00:00+00:00"
  function ageCard(id, status, updated, children) {
    var c = makeCard(id, status, children)
    c.updated_at = updated
    return c
  }
  function days(n) {   // an ISO time n days (may be fractional) before nowIso
    return new Date(Date.parse(nowIso) - n * 86400000).toISOString()
  }
  function ids(list) { return list.map(function(c) { return c.id }) }
  function arch(roots) { return Board.archivable(roots, new Date(nowIso)) }

  function test_archivable_takes_a_finished_old_milestone() {
    var m = ageCard("m", "done", days(5), [ageCard("s", "done", days(5), [ageCard("t", "merged", days(5))])])
    m.title = "Milestone M"
    var out = arch([m])
    compare(out.length, 1)
    compare(out[0].id, "m")
    compare(out[0].title, "Milestone M")
    compare(out[0].idleDays, 5)
    compare(out[0].cardCount, 2)
  }

  function test_archivable_boundary_is_two_days() {
    var young = ageCard("y", "done", days(1.99), [ageCard("a", "done", days(5))])
    var exact = ageCard("e", "done", days(2), [ageCard("b", "done", days(5))])
    compare(ids(arch([young])).length, 0)
    compare(ids(arch([exact])).join(), "e")
    compare(arch([ageCard("one", "done", days(1), [ageCard("c", "done", days(1))])]).length, 0)
  }

  function test_archivable_min_age_is_a_parameter() {
    var m = ageCard("m", "done", days(1), [ageCard("a", "done", days(1))])
    compare(Board.archivable([m], new Date(nowIso), 1).length, 1)
    compare(Board.archivable([m], new Date(nowIso), 3).length, 0)
  }

  function test_archivable_every_finished_status_counts() {
    var m = ageCard("m", "todo", days(9), [
      ageCard("a", "done", days(9)), ageCard("b", "merged", days(9)),
      ageCard("c", "canceled", days(9)), ageCard("d", "archived", days(9))])
    compare(ids(arch([m])).join(), "m")
  }

  function test_archivable_any_unfinished_descendant_blocks() {
    var statuses = ["todo", "in_progress", "blocked"]
    statuses.forEach(function(st) {
      var m = ageCard("m", "done", days(9), [ageCard("a", "done", days(9)), ageCard("b", st, days(9))])
      compare(arch([m]).length, 0, st)
    })
  }

  function test_archivable_looks_at_every_depth() {
    var deep = ageCard("d", "in_progress", days(9))
    var m = ageCard("m", "done", days(9), [ageCard("s", "done", days(9), [ageCard("t", "done", days(9), [deep])])])
    compare(arch([m]).length, 0)
    deep.status = "done"
    var out = arch([m])
    compare(out.length, 1)
    compare(out[0].cardCount, 3)
  }

  function test_archivable_skips_empty_and_already_archived_milestones() {
    var empty = ageCard("e", "done", days(30))
    var archived = ageCard("a", "archived", days(30), [ageCard("x", "done", days(30))])
    compare(arch([empty, archived]).length, 0)
  }

  function test_archivable_milestone_status_itself_does_not_matter_unless_archived() {
    var todo = ageCard("t", "todo", days(9), [ageCard("x", "done", days(9))])
    compare(ids(arch([todo])).join(), "t")
  }

  function test_archivable_idle_is_measured_from_the_newest_update_in_the_subtree() {
    var m = ageCard("m", "done", days(9), [ageCard("s", "done", days(9), [ageCard("t", "done", days(0.5))])])
    compare(arch([m]).length, 0, "a recent grandchild keeps it alive")
    var m2 = ageCard("m2", "done", days(0.5), [ageCard("s", "done", days(9))])
    compare(arch([m2]).length, 0, "a recent milestone card keeps it alive")
    var m3 = ageCard("m3", "done", days(4), [ageCard("s", "done", days(7))])
    compare(arch([m3])[0].idleDays, 4)
  }

  function test_archivable_unreadable_timestamps_are_never_candidates() {
    var m = ageCard("m", "done", days(9), [ageCard("s", "done", "")])
    compare(arch([m]).length, 0)
    var n = ageCard("n", "done", "garbage", [ageCard("s", "done", days(9))])
    compare(arch([n]).length, 0)
  }

  function test_archivable_orders_oldest_first_and_tolerates_junk_input() {
    var a = ageCard("a", "done", days(3), [ageCard("x", "done", days(3))])
    var b = ageCard("b", "done", days(10), [ageCard("x2", "done", days(10))])
    var c = ageCard("c", "done", days(6), [ageCard("x3", "done", days(6))])
    compare(ids(arch([a, b, c])).join(), "b,c,a")
    compare(Board.archivable(null, new Date(nowIso)).length, 0)
    compare(Board.archivable([], new Date(nowIso)).length, 0)
  }

  function test_archivable_accepts_a_millisecond_now() {
    var m = ageCard("m", "done", days(5), [ageCard("s", "done", days(5))])
    compare(Board.archivable([m], Date.parse(nowIso)).length, 1)
  }
}
