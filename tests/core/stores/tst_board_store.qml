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
    compare(app.board.statuses.join(","), "todo,in_progress,done,merged,canceled,archived")
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
    compare(app.board.statusLabel("archived"), "Archived")
    compare(app.board.statusText("archived"), "Archived")
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

  // ---- Archive finished

  property string archNow: "2026-10-10T12:00:00+00:00"
  function aged(id, status, daysAgo, children) {
    var c = card(id, id, status, children)
    c.updated_at = new Date(Date.parse(archNow) - daysAgo * 86400000).toISOString()
    return c
  }
  function archApp(roots) {
    var app = make(); if (!app) return null
    app.board.nowMs = Date.parse(archNow)
    app.board.applyTreeData(roots || [
      aged("old", "done", 9, [aged("o1", "done", 9)]),
      aged("older", "done", 20, [aged("o2", "merged", 20, [aged("o3", "canceled", 20)])]),
      aged("young", "done", 1, [aged("y1", "done", 1)]),
      aged("open", "todo", 20, [aged("p1", "todo", 20)])
    ])
    return app
  }
  function archFinish(app, out, code) {
    var proc = app.board.archiveRunner.current
    verify(proc, "the helper ran")
    proc.outText = out
    proc.exited(code)
  }

  function test_archive_candidates_follow_the_board_oldest_first() {
    var app = archApp(); if (!app) return
    compare(ids(app.board.archiveCandidates), "older,old")
    app.board.applyTreeData([])
    compare(app.board.archiveCandidates.length, 0)
  }

  function test_open_recomputes_from_the_current_board_and_runs_nothing() {
    var app = archApp(); if (!app) return
    var b = app.board
    b.applyTreeData([aged("m", "done", 5, [aged("a", "done", 5)])])
    b.openArchive()
    compare(b.archiveOpen, true)
    compare(ids(b.archiveCandidates), "m")
    compare(b.archiveRunner.seq, 0, "opening writes nothing")
    compare(b.archiveBusy, false)
  }

  function test_open_with_no_candidates_or_no_project_stays_closed() {
    var app = archApp([aged("young", "done", 1, [aged("y", "done", 1)])]); if (!app) return
    app.board.openArchive()
    compare(app.board.archiveOpen, false)
    var bare = make(); bare.projects.applyProjectsList([])
    bare.board.openArchive()
    compare(bare.board.archiveOpen, false)
  }

  function test_cancel_closes_and_clears_without_running() {
    var app = archApp(); if (!app) return
    app.board.openArchive()
    app.board.archiveError = "x"
    app.board.cancelArchive()
    compare(app.board.archiveOpen, false)
    compare(app.board.archiveError, "")
    compare(app.board.archiveRunner.seq, 0)
  }

  function test_confirm_passes_only_the_current_candidates_to_the_helper() {
    var app = archApp(); if (!app) return
    var b = app.board
    b.openArchive()
    // the board changes while the dialog is open: "old" gets a todo child
    b.applyTreeData([
      aged("old", "done", 9, [aged("o1", "done", 9), aged("o9", "todo", 9)]),
      aged("older", "done", 20, [aged("o2", "done", 20)])])
    b.archiveAll()
    compare(b.archiveBusy, true)
    var cmd = b.archiveRunner.current.command
    compare(cmd[0], "python3")
    verify(String(cmd[1]).endsWith("/plugin/core/backend/boards/archive-milestones.py"))
    compare(cmd[2], "/home/u/a")
    compare(cmd.slice(3).join(), "older")
  }

  function test_busy_blocks_cancel_and_a_second_confirm() {
    var app = archApp(); if (!app) return
    var b = app.board
    b.openArchive(); b.archiveAll()
    var proc = b.archiveRunner.current
    b.archiveAll(); b.cancelArchive()
    compare(b.archiveRunner.seq, 1)
    compare(b.archiveOpen, true)
    verify(proc === b.archiveRunner.current)
  }

  function test_success_closes_the_dialog() {
    var app = archApp(); if (!app) return
    var b = app.board
    b.openArchive(); b.archiveAll()
    archFinish(app, '{"ok": true, "results": [{"id": "older", "ok": true}, {"id": "old", "ok": true}]}', 0)
    compare(b.archiveBusy, false)
    compare(b.archiveOpen, false)
    compare(b.archiveError, "")
  }

  function test_a_failure_keeps_the_dialog_open_and_names_the_milestone() {
    var app = archApp(); if (!app) return
    var b = app.board
    b.openArchive(); b.archiveAll()
    archFinish(app, '{"ok": false, "results": [{"id": "older", "ok": true}, {"id": "old", "ok": false, "error": "locked"}]}', 1)
    compare(b.archiveBusy, false)
    compare(b.archiveOpen, true)
    verify(b.archiveError.indexOf("old") >= 0 && b.archiveError.indexOf("locked") >= 0, b.archiveError)
    verify(b.archiveError.indexOf("older") < 0 || b.archiveError.indexOf("older: ") < 0, "the archived one is not reported as failed")
    // the board refetch drops the archived one; a retry carries only what is left
    b.applyTreeData([aged("old", "done", 9, [aged("o1", "done", 9)])])
    b.archiveAll()
    compare(b.archiveError, "")
    compare(b.archiveRunner.current.command.slice(3).join(), "old")
  }

  function test_a_helper_that_cannot_run_is_an_error_too() {
    var app = archApp(); if (!app) return
    app.board.openArchive(); app.board.archiveAll()
    archFinish(app, "", 127)
    compare(app.board.archiveOpen, true)
    verify(app.board.archiveError !== "")
  }

  function test_switching_project_closes_and_drops_a_late_answer() {
    var app = archApp(); if (!app) return
    var b = app.board
    b.openArchive(); b.archiveAll()
    var proc = b.archiveRunner.current
    app.projects.chooseProject(pB)
    compare(b.archiveOpen, false)
    proc.outText = '{"ok": false, "results": [{"id": "old", "ok": false, "error": "late"}]}'
    proc.exited(1)
    compare(b.archiveError, "")
    compare(b.archiveBusy, false)
  }
}
