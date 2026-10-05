// tests/ui/tst_navigator.qml
// ui/Navigator.qml on its own: the return-stack bookkeeping (cursor AND scroll
// position) around an open card, document and memory note, and the unsaved-draft
// guards on a section switch and a project switch. The panel-level flows keep
// their own tests; this one drives the navigator directly, with a real App and a
// real Flickable, and with Panel's UI-only effects supplied as plain functions.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "Navigator"
  when: windowShown
  width: 400; height: 700

  Component { id: flickC; Flickable { width: 200; height: 100; contentWidth: 200; contentHeight: 1000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "README.md", "title": "Readme", "size": 100},' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200}], "truncated": false}'
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-a/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "d", "type": "feedback", "size": 10, "indexed": true}]}'

  property var calls: []
  property var flick: null

  function card(id, title, status, children) {
    return { id: id, title: title, status: status, description: "d", blocked_by: [], children: children || [] }
  }

  // The effects Panel owns, reproduced here so the scroll bookkeeping is real.
  function makeActions() {
    return {
      focusForView: function() { tc.calls.push("focus") },
      scrollToTop: function() { tc.calls.push("top"); if (tc.flick) tc.flick.contentY = 0 },
      scrollBy: function(px) {
        tc.calls.push("by:" + px)
        if (tc.flick) tc.flick.contentY = Math.max(0, Math.min(tc.flick.contentY + px,
          Math.max(0, tc.flick.contentHeight - tc.flick.height)))
      },
      centerOnGraphNode: function(id) { tc.calls.push("center:" + id) }
    }
  }

  function make() {
    tc.calls = []
    var appC = Qt.createComponent("../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    tc.flick = createTemporaryObject(flickC, tc)
    var n = navC.createObject(tc, { app: app, flick: tc.flick, actions: makeActions() })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA, pB])
    return n
  }

  function test_leaving_a_card_restores_the_board_cursor_and_the_scroll_position() {
    var n = make(); if (!n) return
    n.app.board.applyTreeData([card("m1", "Milestone", "todo"), card("b1", "Blk", "blocked")])
    wait(50)
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 150
    n.openCard("b1")
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.nav.cursorIndex, 0)
    wait(0)
    compare(tc.flick.contentY, 0)
    n.restoreListView()
    compare(n.app.nav.viewMode, "board")
    compare(n.app.nav.cursorIndex, 1)
    wait(0)
    compare(tc.flick.contentY, 150)
  }

  function test_leaving_a_document_restores_the_list_cursor_and_the_scroll_position() {
    var n = make(); if (!n) return
    n.showSection("documents")
    n.app.docs.applyDocsResult(docList, 0)
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 220
    n.openDoc("docs/specs/Design Doc.md")
    compare(n.app.nav.viewMode, "document")
    compare(n.app.nav.cursorIndex, 0)
    wait(0)
    compare(tc.flick.contentY, 0)
    n.restoreDocumentsList()
    compare(n.app.nav.viewMode, "documents")
    compare(n.app.nav.cursorIndex, 1)
    compare(n.app.docs.selectedDocPath, "")
    wait(0)
    compare(tc.flick.contentY, 220)
  }

  function test_leaving_a_memory_note_restores_the_list_cursor_and_the_scroll_position() {
    var n = make(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 90
    n.openMemory("feedback_a.md")
    compare(n.app.nav.viewMode, "memory")
    compare(n.app.nav.cursorIndex, 0)
    wait(0)
    compare(tc.flick.contentY, 0)
    n.restoreMemoriesList()
    compare(n.app.nav.viewMode, "memories")
    compare(n.app.nav.cursorIndex, 1)
    compare(n.app.memories.selectedMemory, "")
    wait(0)
    compare(tc.flick.contentY, 90)
  }

  function test_an_unsaved_draft_blocks_a_section_switch() {
    var n = make(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    n.app.memories.setMemoryText("body")
    n.app.memories.startMemoryEdit()
    n.app.memories.memoryDraft = "body plus more"
    n.showSection("board")
    compare(n.app.nav.viewMode, "memory")
    n.app.memories.memoryDraft = "body"
    n.showSection("board")
    compare(n.app.nav.viewMode, "board")
  }

  function test_an_unsaved_draft_blocks_a_project_switch_with_a_message() {
    var n = make(); if (!n) return
    n.showSection("memories")
    n.app.memories.applyMemoriesResult(memList, 0)
    n.openMemory("user_role.md")
    n.app.memories.setMemoryText("body")
    n.app.memories.startMemoryEdit()
    n.app.memories.memoryDraft = "body plus more"
    var before = n.app.projects.selectedProject.root_path
    n.chooseProject(pB)
    compare(n.app.projects.selectedProject.root_path, before)
    compare(n.app.memories.memoryOpError,
      "You have unsaved changes. Save them, or choose Cancel to discard, before switching project.")
  }

  function test_the_graph_cursor_move_asks_the_panel_to_centre_on_the_new_node() {
    var n = make(); if (!n) return
    n.app.board.applyTreeData([card("m1", "Milestone", "todo", [card("s1", "Story", "todo")])])
    wait(50)
    n.showSection("graph")
    compare(n.app.nav.viewMode, "graph")
    var start = n.app.graph.graphCursor
    verify(start !== "", "the graph starts on a node")
    tc.calls = []
    n.moveGraph("down")
    var centred = tc.calls.filter(function(c) { return c.indexOf("center:") === 0 })
    compare(centred.join(","), "center:" + n.app.graph.graphCursor)
  }

  function test_a_graph_move_with_no_graph_centres_on_nothing() {
    var n = make(); if (!n) return
    n.showSection("graph")
    tc.calls = []
    n.moveGraph("down")
    compare(tc.calls.filter(function(c) { return c.indexOf("center:") === 0 }).join(","), "")
  }

  function test_the_dropdown_stays_shut_while_a_delete_is_being_confirmed() {
    var n = make(); if (!n) return
    n.app.deleter.openDelete(n.app.projects.selectedProject)
    n.toggleDropdown()
    compare(n.app.nav.dropdownOpen, false)
  }

  // ---- Runs (5.1)

  function runOf(id, status, live, milestone) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] } }
  }

  // The navigator in the Runs section with three runs. Selecting the project
  // launched a snapshot of a helper that does not exist here; it is cancelled
  // so its late exit can never touch the runs set below.
  function withRuns() {
    var n = make(); if (!n) return null
    n.app.runs.snapshotRunner.cancel()
    n.app.runs.runs = [runOf("run-0000000000a1", "started", true, "alpha"),
                       runOf("run-0000000000b2", "escalated", null, "beta"),
                       runOf("run-0000000000c3", "stopped", null, "gamma")]
    n.showSection("runs")
    wait(0)
    return n
  }
  function runIds(list) { return list.map(function(r) { return r ? r.id : "null" }).join(",") }
  function crumbLabels(crumbs) { return crumbs.map(function(c) { return c.label }).join(" > ") }

  function test_the_runs_section_lists_the_filtered_runs() {
    var n = withRuns(); if (!n) return
    compare(n.app.nav.viewMode, "runs")
    compare(runIds(n.currentList()), runIds(n.app.runs.filteredRuns))
    compare(n.currentList().length, 3)
    n.app.runs.toggleRunFilter("parked")
    compare(runIds(n.currentList()), "run-0000000000c3", "the list is the store's filtered one")
    compare(crumbLabels(n.crumbs), "Runs")
    compare(n.crumbs[0].clickable, false)
  }

  function test_enter_opens_a_run_and_back_restores_the_cursor_and_scroll() {
    var n = withRuns(); if (!n) return
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 120
    n.activateCursor()
    compare(n.app.runs.selectedRunId, "run-0000000000b2")
    compare(n.app.nav.viewMode, "run")
    compare(n.app.nav.section, "runs")
    compare(n.app.nav.cursorIndex, 0)
    compare(crumbLabels(n.crumbs), "Runs > …000000b2")
    compare(n.crumbs[0].clickable, true)
    compare(n.currentList().length, 0, "the run view has no cursor list yet")
    wait(0)
    compare(tc.flick.contentY, 0)
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.nav.cursorIndex, 1)
    compare(n.app.runs.selectedRunId, "")
    wait(0)
    compare(tc.flick.contentY, 120)
  }

  function test_the_section_crumb_of_an_open_run_goes_back() {
    var n = withRuns(); if (!n) return
    n.openRun("run-0000000000a1")
    compare(n.app.nav.viewMode, "run")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "runs")
  }

  function test_enter_on_an_empty_or_junk_runs_list_does_nothing() {
    var n = withRuns(); if (!n) return
    n.app.runs.runs = []
    n.activateCursor()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.selectedRunId, "")
    n.app.runs.runs = [{}, null]
    n.app.nav.cursorIndex = 0
    n.activateCursor()
    n.app.nav.cursorIndex = 1
    n.activateCursor()
    compare(n.app.nav.viewMode, "runs", "a run without an id opens nothing")
    compare(n.app.runs.selectedRunId, "")
  }

  function test_open_run_ignores_an_unknown_or_blank_id() {
    var n = withRuns(); if (!n) return
    var bad = ["", "nope", null, undefined, 5]
    for (var i = 0; i < bad.length; i++) {
      n.openRun(bad[i])
      compare(n.app.nav.viewMode, "runs", "id " + i)
      compare(n.app.runs.selectedRunId, "", "id " + i)
    }
  }

  function test_a_section_switch_resets_the_search_but_keeps_the_chip() {
    var n = withRuns(); if (!n) return
    n.app.runs.toggleRunFilter("attention")
    n.app.nav.searchQuery = "beta"
    n.showSection("board")
    n.showSection("runs")
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.nav.searchQuery, "")
    compare(n.app.runs.searchQuery, "")
    compare(n.app.runs.runFilter, "attention")
  }

  // ---- Runs opened from a card (5.3)

  function cardRuns() {
    var n = make(); if (!n) return null
    n.app.runs.snapshotRunner.cancel()
    n.app.board.applyTreeData([card("m1", "Milestone", "todo"), card("m2", "Other", "todo")])
    n.app.runs.runs = [runOf("run-0000000000a1", "started", true, "m2")]
    wait(50)
    return n
  }

  function test_a_run_opened_from_a_card_comes_back_to_that_card() {
    var n = cardRuns(); if (!n) return
    n.app.nav.cursorIndex = 1
    tc.flick.contentY = 80
    n.openCard("m2")
    wait(0)
    compare(n.app.nav.viewMode, "entry")
    n.openRun("run-0000000000a1", "entry")
    wait(0)
    compare(n.app.nav.viewMode, "run")
    compare(n.app.runs.selectedRunId, "run-0000000000a1")
    compare(n.app.nav.runReturnMode, "entry")
    compare(n.app.nav.returnMode, "board", "the card's own way back is untouched")
    compare(n.app.nav.returnCursor, 1)
    compare(n.app.nav.returnScrollY, 80)
    compare(crumbLabels(n.crumbs), "Runs > …000000a1", "accepted: the run view still reads Runs")
    n.goBack()
    wait(0)
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.board.selectedCardId, "m2")
    compare(n.app.runs.selectedRunId, "")
    compare(n.app.nav.runReturnMode, "runs")
    compare(n.app.nav.cursorIndex, 0)
    n.goBack()
    compare(n.app.nav.viewMode, "board", "Back from the card still reaches its list")
    compare(n.app.nav.cursorIndex, 1)
    wait(0)
    compare(tc.flick.contentY, 80)
  }

  function test_the_section_crumb_of_a_run_opened_from_a_card_also_lands_on_the_card() {
    var n = cardRuns(); if (!n) return
    n.openCard("m2")
    n.openRun("run-0000000000a1", "entry")
    n.activateCrumb(0)
    compare(n.app.nav.viewMode, "entry")
    compare(n.app.board.selectedCardId, "m2")
  }

  function test_a_plain_open_resets_the_return_to_the_runs_list() {
    var n = cardRuns(); if (!n) return
    n.openCard("m2")
    n.openRun("run-0000000000a1", "entry")
    compare(n.app.nav.runReturnMode, "entry")
    n.openRun("run-0000000000a1")
    compare(n.app.nav.runReturnMode, "runs", "every open says where Back goes")
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
  }

  function test_back_from_a_card_run_whose_card_is_gone_returns_to_the_list() {
    var n = cardRuns(); if (!n) return
    n.openCard("m2")
    n.openRun("run-0000000000a1", "entry")
    n.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    compare(n.app.nav.viewMode, "run", "the run view does not follow the board")
    n.goBack()
    compare(n.app.nav.viewMode, "board", "no blank card: Back goes on to the card's list")
    compare(n.app.nav.runReturnMode, "runs")
    compare(n.app.runs.selectedRunId, "")
  }

  function test_an_unknown_run_from_a_card_opens_nothing() {
    var n = cardRuns(); if (!n) return
    n.openCard("m1")
    var bad = ["", "gone", null, undefined, 5]
    for (var i = 0; i < bad.length; i++) {
      n.openRun(bad[i], "entry")
      compare(n.app.nav.viewMode, "entry", "id " + i)
      compare(n.app.nav.runReturnMode, "runs", "id " + i)
      compare(n.app.runs.selectedRunId, "", "id " + i)
    }
  }

  // ---- After a dispatch (S3 4.2)

  // The board of project A, with run-a in the snapshot.
  function startedRuns() {
    var n = make(); if (!n) return null
    n.app.runs.snapshotRunner.cancel()
    n.app.runs.runs = [runOf("run-a", "started", true, "m1")]
    n.showSection("board")
    return n
  }

  // 11
  function test_a_start_without_a_run_id_goes_to_the_runs_list_and_says_so() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun(null)
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.flashText, "Started — waiting for the run to appear")
    compare(n.awaitedRunId, "")
  }

  // 12
  function test_a_listed_run_opens_at_once_and_back_lands_on_the_runs_list() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-a")
    compare(n.app.nav.viewMode, "run")
    compare(n.app.runs.selectedRunId, "run-a")
    compare(n.awaitedRunId, "")
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
  }

  // 13
  function test_an_unlisted_run_is_awaited_and_opens_when_a_snapshot_lists_it() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.flashText, "Started — opening the run when it appears")
    compare(n.awaitedRunId, "run-b")
    compare(n.awaitedProject, "/home/u/a")
    n.app.runs.runs = n.app.runs.runs.concat([runOf("run-b", "started", true, "m1")])
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "run")
    compare(n.app.runs.selectedRunId, "run-b")
    compare(n.awaitedRunId, "")
    n.goBack()
    compare(n.app.nav.viewMode, "runs")
  }

  // 14
  function test_leaving_the_runs_list_forgets_the_awaited_run() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.showSection("board")
    n.app.runs.runs = n.app.runs.runs.concat([runOf("run-b", "started", true, "m1")])
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "board")
    compare(n.app.runs.selectedRunId, "")
    compare(n.awaitedRunId, "")
    n.showSection("runs")
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs", "forgotten for good")
  }

  // 15
  function test_a_snapshot_without_the_run_keeps_waiting() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.app.runs.runs = [runOf("run-c", "started", true, "m1")]
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs")
    compare(n.awaitedRunId, "run-b")
  }

  function test_another_project_forgets_the_awaited_run() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.chooseProject(tc.pB)
    n.showSection("runs")
    n.app.runs.snapshotRunner.cancel()
    n.app.runs.runs = [runOf("run-b", "started", true, "m1")]
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.selectedRunId, "")
    compare(n.awaitedRunId, "")
  }

  // Review Focus 3
  function test_a_second_start_replaces_the_awaited_run() {
    var n = startedRuns(); if (!n) return
    n.openStartedRun("run-b")
    n.openStartedRun(null)
    compare(n.awaitedRunId, "")
    n.app.runs.runs = n.app.runs.runs.concat([runOf("run-b", "started", true, "m1")])
    n.openAwaitedRun()
    compare(n.app.nav.viewMode, "runs")
    compare(n.app.runs.selectedRunId, "")
  }
}
