// tests/core/stores/tst_board_store.qml
// The card tree (`brd tree`), what the Board shows after the search, the open
// card and the database watch -- driven through App so the wiring to the
// project and navigation stores is exercised too.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresBoardStore"

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  SignalSpy { id: refetchSpy; signalName: "refetched" }

  function card(id, title, status, children, blockedBy) {
    return { id: id, title: title, status: status, description: "d", blocked_by: blockedBy || [], children: children || [] }
  }
  function ids(list) { return list.map(function(x) { return x.id }).join(",") }

  function roots() {
    var t1 = card("t1", "Task1", "blocked", [], ["x1"])
    var t2 = card("t2", "Task2", "done")
    var s1 = card("s1", "Story", "in_progress", [t1, t2])
    var m1 = card("m1", "Milestone", "todo", [s1])
    var x1 = card("x1", "Ex", "done")
    var b1 = card("b1", "Blk", "blocked")
    return [m1, x1, b1]
  }

  function make() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var app = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    return app
  }

  function test_the_tree_is_fetched_in_the_projects_directory() {
    var app = make(); if (!app) return
    var proc = app.board.treeProc
    verify(proc, "treeProc exists")
    compare(proc.command[0], "brd")
    compare(proc.command[1], "tree")
    compare(proc.workingDirectory, "/home/u/a")
    compare(proc.running, true)
  }

  function test_a_parsed_tree_fills_the_board_section_by_section() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    compare(app.board.cardRoots.length, 3)
    compare(ids(app.board.boardCards), "m1,b1,x1")
    compare(ids(app.board.boardColumn("todo")), "m1,b1")
    compare(ids(app.board.boardColumn("done")), "x1")
    compare(app.board.boardIndexOf("x1"), 2)
    compare(app.board.boardIndexOf("nope"), -1)
    compare(app.board.cardMap["t1"].title, "Task1")
  }

  function test_the_tree_output_is_parsed_and_applied() {
    var app = make(); if (!app) return
    app.board.treeProc.stdout.text = '{"data": [{"id": "m1", "title": "M", "status": "todo", "blocked_by": [], "children": []}]}'
    app.board.treeProc.stdout.streamFinished()
    compare(app.board.cardRoots.length, 1)
    compare(app.projects.loadError, "")
  }

  function test_an_unreadable_tree_empties_the_board_and_reports_it() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.board.treeProc.stdout.text = "not json"
    app.board.treeProc.stdout.streamFinished()
    compare(app.board.cardRoots.length, 0)
    compare(app.projects.loadError, "Could not load the board for this project.")
    app.board.applyTreeData(roots())
    app.projects.loadError = ""
    app.board.treeProc.exited(1)
    compare(app.board.cardRoots.length, 0)
    compare(app.projects.loadError, "Could not load the board for this project.")
  }

  function test_the_search_hides_cards_whose_subtree_does_not_match() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.nav.searchQuery = "Task1"
    compare(ids(app.board.visibleBoardRoots), "m1")
    compare(ids(app.board.boardCards), "m1")
    app.nav.searchQuery = ""
    compare(app.board.visibleBoardRoots.length, 3)
  }

  function test_the_detail_links_of_the_open_card_are_listed_in_order() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    compare(app.board.detailLinkList.length, 0, "no links outside the card view")
    app.nav.viewMode = "entry"
    compare(app.board.openCard("s1"), true)
    compare(app.board.detailLinkList.map(function(l) { return l.section }).join(","), "parent,child,child")
    compare(app.board.openCard("t1"), true)
    compare(app.board.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:s1,blocker:x1")
    compare(app.board.linkIndex("blocker", "x1"), 1)
    compare(app.board.linkIndex("child", "x1"), -1)
  }

  function test_opening_an_unknown_card_changes_nothing() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    compare(app.board.openCard("m1"), true)
    compare(app.board.selectedCardId, "m1")
    compare(app.board.openCard("gone"), false)
    compare(app.board.selectedCardId, "m1")
  }

  function test_a_card_that_leaves_the_tree_asks_for_the_list_view() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.nav.viewMode = "entry"
    app.board.openCard("m1")
    var spy = Qt.createQmlObject('import QtTest; SignalSpy {}', tc)
    spy.target = app.board
    spy.signalName = "listViewRequested"
    app.board.applyTreeData([card("x1", "Ex", "done")])
    compare(spy.count, 1)
    app.board.applyTreeData([card("x1", "Ex", "done")])
    compare(spy.count, 2)
  }

  function test_a_card_still_in_the_tree_keeps_the_card_view() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.nav.viewMode = "entry"
    app.board.openCard("x1")
    var spy = Qt.createQmlObject('import QtTest; SignalSpy {}', tc)
    spy.target = app.board
    spy.signalName = "listViewRequested"
    app.board.applyTreeData(roots())
    compare(spy.count, 0)
  }

  function test_the_database_is_watched_and_a_change_refetches_the_board() {
    var app = make(); if (!app) return
    var db = app.board.dbFile
    verify(db, "dbFile exists")
    compare(db.watchChanges, true)
    app.projects.resolveDbPathProc.stdout.text = "/home/u/a/.brd/brd.db\n"
    app.projects.resolveDbPathProc.stdout.streamFinished()
    compare(db.path, "/home/u/a/.brd/brd.db")
    app.board.treeProc.running = false
    db.fileChanged()
    tryCompare(app.board.treeProc, "running", true)
  }

  // A brd write touches the database several times in a row; each touch must
  // not cost a tree + issue + export fetch. The watch is debounced, so a burst
  // settles into exactly one refetch.
  function test_a_burst_of_database_changes_refetches_the_board_once() {
    var app = make(); if (!app) return
    var spy = refetchSpy
    spy.target = app.board
    spy.clear()
    app.board.treeProc.running = false
    app.board.dbFile.fileChanged()
    app.board.dbFile.fileChanged()
    app.board.dbFile.fileChanged()
    compare(spy.count, 0, "nothing is fetched while the writes are still arriving")
    compare(app.board.treeProc.running, false)
    tryCompare(spy, "count", 1)
    compare(app.board.treeProc.running, true)
    wait(400)
    compare(spy.count, 1, "the burst cost exactly one fetch")
  }

  // Refresh and a project switch are the user asking, not the watch: they fetch
  // straight away.
  function test_refresh_and_a_project_switch_still_fetch_immediately() {
    var app = make(); if (!app) return
    app.board.treeProc.running = false
    app.board.fetchBoard()
    compare(app.board.treeProc.running, true, "Refresh is immediate")
    app.board.treeProc.running = false
    app.projects.chooseProject(pB)
    compare(app.board.treeProc.running, true, "a project switch is immediate")
  }

  function test_a_project_change_refetches_the_board() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.board.treeProc.running = false
    app.projects.chooseProject(pB)
    compare(app.board.treeProc.workingDirectory, "/home/u/b")
    compare(app.board.treeProc.running, true)
  }

  function test_an_empty_registry_empties_the_board() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.projects.applyProjectsList([])
    compare(app.projects.selectedProject, null)
    compare(app.board.cardRoots.length, 0)
  }

  function test_the_status_wording_and_resolved_cards_are_unchanged() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    compare(app.board.statuses.join(","), "todo,in_progress,done,merged,canceled")
    compare(app.board.statusText("in_progress"), "In progress")
    compare(app.board.statusText("blocked"), "Blocked")
    compare(app.board.statusText("todo"), "Todo")
    compare(app.board.statusText("done"), "Done")
    compare(app.board.statusText("weird"), "weird")
    compare(app.board.statusLabel("in_progress"), "In Progress")
    compare(app.board.statusLabel("todo"), "Todo")
    compare(app.board.statusLabel("merged"), "Merged")
    compare(app.board.statusLabel("canceled"), "Canceled")
    compare(app.board.statusText("merged"), "Merged")
    compare(app.board.statusText("canceled"), "Canceled")
    compare(app.board.statusLabel("anything"), "Done")
    var known = app.board.resolvedCard("s1")
    compare(known.title, "Story")
    compare(known.inBoard, true)
    var missing = app.board.resolvedCard("nope")
    compare(missing.title, "nope")
    compare(missing.status, "")
    compare(missing.inBoard, false)
  }

  function test_the_issues_are_fetched_with_the_tree_in_the_projects_directory() {
    var app = make(); if (!app) return
    var proc = app.board.issueProc
    verify(proc, "issueProc exists")
    compare(proc.command.join(" "), "brd issue list")
    compare(proc.workingDirectory, "/home/u/a")
    compare(proc.running, true)
    proc.running = false
    app.board.dbFile.fileChanged()
    tryCompare(proc, "running", true, 2000, "a database change refetches the issues too")
    proc.running = false
    app.projects.chooseProject(pB)
    compare(proc.workingDirectory, "/home/u/b")
    compare(proc.running, true)
  }

  function test_the_issue_list_fills_the_issue_map_and_resolves_issue_blockers() {
    var app = make(); if (!app) return
    app.board.applyTreeData(roots())
    app.board.issueProc.stdout.text = JSON.stringify({ ok: true, data: [
      { id: "i1", kind: "issue", title: "Broken build", body: "", status: "open", blocks: ["t1"] },
      { id: "i2", kind: "issue", title: "Old bug", body: "", status: "closed", blocks: [] }] })
    app.board.issueProc.stdout.streamFinished()
    compare(Object.keys(app.board.issueMap).sort().join(","), "i1,i2")
    compare(app.board.issueMap.i1.title, "Broken build")
    var open = app.board.resolvedCard("i1")
    compare(open.title, "Broken build")
    compare(open.status, "open")
    compare(open.kind, "issue")
    compare(open.inBoard, false)
    compare(app.board.resolvedCard("i2").status, "closed")
    compare(app.board.resolvedCard("s1").inBoard, true)
    compare(app.board.resolvedCard("nope").title, "nope")
    compare(app.projects.loadError, "")
  }

  // The open card's keyboard link rows include an issue blocker the issue map
  // knows, so the cursor can land on it and open the Issues section.
  function test_the_detail_links_of_a_card_include_its_known_issue_blockers() {
    var app = make(); if (!app) return
    app.board.applyTreeData([card("c1", "Card", "blocked", [], ["x1", "i1", "ghost"]),
                             card("x1", "Other", "done")])
    app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    app.nav.viewMode = "entry"
    app.board.openCard("c1")
    compare(app.board.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","),
            "blocker:x1,blocker:i1")
    compare(app.board.linkIndex("blocker", "i1"), 1)
    compare(app.board.linkIndex("blocker", "ghost"), -1)
  }

  function test_an_old_brd_without_issues_leaves_an_empty_map_and_no_error() {
    var app = make(); if (!app) return
    app.board.applyIssueData([{ id: "i1", title: "Stale", status: "open" }])
    app.board.issueProc.stdout.text = '{"ok": false, "error": {"type": "UsageError", "message": "no such command"}}'
    app.board.issueProc.stdout.streamFinished()
    compare(Object.keys(app.board.issueMap).length, 0)
    app.board.applyIssueData([{ id: "i1", title: "Stale", status: "open" }])
    app.board.issueProc.stdout.text = "Usage: brd [OPTIONS] COMMAND"
    app.board.issueProc.stdout.streamFinished()
    compare(Object.keys(app.board.issueMap).length, 0)
    app.board.applyIssueData([{ id: "i1", title: "Stale", status: "open" }])
    app.board.issueProc.exited(2)
    compare(Object.keys(app.board.issueMap).length, 0)
    compare(app.projects.loadError, "")
  }

  function test_an_empty_registry_empties_the_issues() {
    var app = make(); if (!app) return
    app.board.applyIssueData([{ id: "i1", title: "Stale", status: "open" }])
    app.projects.applyProjectsList([])
    compare(Object.keys(app.board.issueMap).length, 0)
  }
}
