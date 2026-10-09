// tests/ui/tst_shortcuts.qml
// ui/Shortcuts.qml on its own: the Ctrl chords the panel-level tests do not
// reach (Ctrl+N, Ctrl+E and the two memory modals' guards), the Escape ordering
// chain, the arrow handling and the search field's keys. Panel keeps its own
// tests for the same keys arriving through the key catcher.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "Shortcuts"
  when: windowShown
  width: 400; height: 700

  Component { id: flickC; Flickable { width: 200; height: 100; contentWidth: 200; contentHeight: 1000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-a/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true},' +
    '{"file": "feedback_a.md", "name": "Terse", "description": "d", "type": "feedback", "size": 10, "indexed": true}]}'

  // i1 blocks a card of this board (one link row), i2 blocks nothing.
  property string exportLine: JSON.stringify({ ok: true, data: {
    issues: [{ id: "i1", title: "Broken build", body: "b", status: "open", close_reason: null,
               blocks: ["m1"], created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" },
             { id: "i2", title: "Lonely", body: "b", status: "open", close_reason: null,
               blocks: [], created_at: "2026-09-19T10:00:00+00:00", updated_at: "2026-09-19T10:00:00+00:00" }],
    comments: [], refs: [] } })

  property var calls: []
  property var flick: null
  property bool atEnd: true

  function ctrl(key) { return { modifiers: Qt.ControlModifier, key: key, accepted: false } }
  function plain(key) { return { modifiers: Qt.NoModifier, key: key, accepted: false } }
  function shift(key) { return { modifiers: Qt.ShiftModifier, key: key, accepted: false } }
  function card(id, title, status, children) {
    return { id: id, title: title, status: status, description: "d", blocked_by: [], children: children || [] }
  }

  function make() {
    tc.calls = []
    tc.atEnd = true
    var appC = Qt.createComponent("../../core/stores/App.qml")
    if (appC.status !== Component.Ready) { fail(appC.errorString()); return null }
    var app = appC.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var navC = Qt.createComponent("../../ui/Navigator.qml")
    if (navC.status !== Component.Ready) { fail(navC.errorString()); return null }
    var scC = Qt.createComponent("../../ui/Shortcuts.qml")
    if (scC.status !== Component.Ready) { fail(scC.errorString()); return null }
    tc.flick = createTemporaryObject(flickC, tc)
    var navActions = {
      focusForView: function() {},
      scrollToTop: function() { if (tc.flick) tc.flick.contentY = 0 },
      scrollBy: function(px) { tc.calls.push("by:" + px) },
      centerOnGraphNode: function(id) {}
    }
    var n = navC.createObject(tc, { app: app, flick: tc.flick, actions: navActions })
    var s = scC.createObject(tc, { app: app, navigator: n, actions: {
      close: function() { tc.calls.push("close") },
      scrollBy: navActions.scrollBy,
      switchPanel: function(direction) { tc.calls.push("switch:" + direction) },
      searchAtEnd: function() { return tc.atEnd },
      openDispatch: function(target) { tc.calls.push("dispatch:" + target) }
    } })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA, pB])
    return s
  }

  function inIssues() {
    var s = make(); if (!s) return null
    s.app.board.applyTreeData([card("m1", "Milestone", "blocked")])
    s.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    wait(50)
    if (s.app.extras.exportProc) {
      s.app.extras.exportProc.running = false
      s.app.extras.exportProc.launchGuard = "stale"
    }
    s.app.extras.extrasLoading = false
    s.app.extras.applyExportResult(exportLine, 0)
    s.navigator.showSection("issues")
    return s
  }

  function inMemories() {
    var s = make(); if (!s) return null
    s.navigator.showSection("memories")
    s.app.memories.applyMemoriesResult(memList, 0)
    return s
  }

  // ---- Ctrl chords

  // The digits follow the sidebar's order: Board, Graph, Documents, Memories,
  // Issues.
  function test_the_ctrl_digits_follow_the_order_of_the_sidebar_sections() {
    var s = make(); if (!s) return
    var wanted = ["board", "graph", "documents", "memories", "issues"]
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5]
    for (var i = 0; i < digits.length; i++) {
      compare(s.handleGlobalKey(ctrl(digits[i])), true, wanted[i])
      compare(s.app.nav.section, wanted[i])
    }
  }

  function test_ctrl_n_opens_the_new_memory_dialog_only_in_the_memories_list() {
    var s = inMemories(); if (!s) return
    s.navigator.showSection("board")
    compare(s.handleGlobalKey(ctrl(Qt.Key_N)), false)
    compare(s.app.memories.newMemoryOpen, false)
    s.navigator.showSection("memories")
    compare(s.handleGlobalKey(ctrl(Qt.Key_N)), true)
    compare(s.app.memories.newMemoryOpen, true)
  }

  function test_ctrl_e_starts_editing_only_in_an_open_note() {
    var s = inMemories(); if (!s) return
    compare(s.handleGlobalKey(ctrl(Qt.Key_E)), false)
    compare(s.app.memories.memoryEditing, false)
    s.navigator.openMemory("user_role.md")
    s.app.memories.setMemoryText("body")
    compare(s.handleGlobalKey(ctrl(Qt.Key_E)), true)
    compare(s.app.memories.memoryEditing, true)
  }

  function test_the_ctrl_shortcuts_are_blocked_while_the_new_memory_dialog_is_open() {
    var s = inMemories(); if (!s) return
    s.app.memories.openNewMemory()
    compare(s.app.memories.newMemoryOpen, true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_P)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_N)), false)
    compare(s.app.nav.dropdownOpen, false)
    compare(s.app.nav.viewMode, "memories")
  }

  function test_the_ctrl_shortcuts_are_blocked_while_a_memory_delete_is_being_confirmed() {
    var s = inMemories(); if (!s) return
    s.navigator.openMemory("user_role.md")
    s.app.memories.requestMemoryDelete()
    compare(s.app.memories.memoryDeleteOpen, true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_P)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_4)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_E)), false)
    compare(s.app.nav.viewMode, "memory")
  }

  // ---- Escape ordering

  function test_escape_cancels_the_delete_confirmation_before_anything_else() {
    var s = inMemories(); if (!s) return
    s.app.memories.memoryDeleteOpen = true
    s.app.memories.newMemoryOpen = true
    s.app.deleter.openDelete(s.app.projects.selectedProject)
    s.closeRequested()
    compare(!!s.app.deleter.deleteTarget, false)
    compare(s.app.memories.memoryDeleteOpen, true)
    compare(s.app.memories.newMemoryOpen, true)
    compare(tc.calls.indexOf("close"), -1)
  }

  function test_escape_cancels_the_memory_delete_before_the_new_memory_dialog() {
    var s = inMemories(); if (!s) return
    s.app.nav.dropdownOpen = true
    s.app.memories.newMemoryOpen = true
    s.app.memories.memoryDeleteOpen = true
    s.closeRequested()
    compare(s.app.memories.memoryDeleteOpen, false)
    compare(s.app.memories.newMemoryOpen, true)
    compare(s.app.nav.dropdownOpen, true)
  }

  function test_escape_cancels_the_new_memory_dialog_before_the_dropdown() {
    var s = inMemories(); if (!s) return
    s.app.nav.dropdownOpen = true
    s.app.memories.newMemoryOpen = true
    s.closeRequested()
    compare(s.app.memories.newMemoryOpen, false)
    compare(s.app.nav.dropdownOpen, true)
  }

  function test_escape_closes_the_dropdown_before_going_back() {
    var s = inMemories(); if (!s) return
    s.navigator.openMemory("user_role.md")
    s.navigator.toggleDropdown()
    compare(s.app.nav.dropdownOpen, true)
    s.closeRequested()
    compare(s.app.nav.dropdownOpen, false)
    compare(s.app.nav.viewMode, "memory")
    compare(tc.calls.indexOf("close"), -1)
  }

  function test_escape_goes_back_from_an_open_note_before_closing_the_panel() {
    var s = inMemories(); if (!s) return
    s.navigator.openMemory("user_role.md")
    s.closeRequested()
    compare(s.app.nav.viewMode, "memories")
    compare(tc.calls.indexOf("close"), -1)
  }

  function test_escape_closes_the_panel_from_a_list() {
    var s = inMemories(); if (!s) return
    s.closeRequested()
    verify(tc.calls.indexOf("close") >= 0, "the panel was asked to close")
  }

  // ---- Arrows and activation

  function test_the_left_arrow_goes_back_from_an_open_note() {
    var s = inMemories(); if (!s) return
    s.navigator.openMemory("user_role.md")
    s.handleMove(-1, 0)
    compare(s.app.nav.viewMode, "memories")
  }

  function test_the_arrows_scroll_a_card_that_has_no_links() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    wait(50)
    s.navigator.openCard("m1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.detailLinkList.length, 0)
    tc.calls = []
    s.handleMove(0, 1)
    compare(tc.calls.length, 1)
    verify(String(tc.calls[0]).indexOf("by:") === 0, "the card scrolled instead of moving a cursor")
  }

  function test_the_arrows_move_the_cursor_in_a_card_that_has_links() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone", "todo", [card("s1", "Story", "todo")])])
    wait(50)
    s.navigator.openCard("m1")
    verify(s.app.board.detailLinkList.length > 0, "the card has links")
    tc.calls = []
    s.handleMove(0, 1)
    compare(tc.calls.length, 0)
  }

  function test_the_arrows_do_nothing_in_a_list_view() {
    var s = inMemories(); if (!s) return
    tc.calls = []
    s.handleMove(0, 1)
    s.handleMove(1, 0)
    compare(tc.calls.length, 0)
    compare(s.app.nav.viewMode, "memories")
  }

  function test_activate_opens_the_cursor_card_in_an_entry() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone", "todo", [card("s1", "Story", "todo")])])
    wait(50)
    s.navigator.openCard("m1")
    s.handleActivate()
    compare(s.app.board.selectedCardId, "s1")
  }

  // ---- An open issue is a keyboard view exactly like a card

  function test_the_left_arrow_goes_back_from_an_open_issue() {
    var s = inIssues(); if (!s) return
    s.navigator.openIssue("i1")
    s.handleMove(-1, 0)
    compare(s.app.nav.viewMode, "issues")
  }

  function test_the_arrows_move_the_cursor_in_an_issue_that_has_links() {
    var s = inIssues(); if (!s) return
    s.navigator.openIssue("i1")
    verify(s.app.extras.detailLinkList.length > 0, "the issue has links")
    tc.calls = []
    s.handleMove(0, 1)
    compare(tc.calls.length, 0, "the cursor moved instead of scrolling")
  }

  function test_the_arrows_scroll_an_issue_that_has_no_links() {
    var s = inIssues(); if (!s) return
    s.navigator.openIssue("i2")
    compare(s.app.extras.detailLinkList.length, 0)
    tc.calls = []
    s.handleMove(0, 1)
    compare(tc.calls.length, 1)
    verify(String(tc.calls[0]).indexOf("by:") === 0, "the issue scrolled instead of moving a cursor")
  }

  function test_activate_and_the_right_arrow_follow_the_cursor_link_of_an_issue() {
    var s = inIssues(); if (!s) return
    s.navigator.openIssue("i1")
    s.handleActivate()
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m1")
    s.navigator.goBack()
    compare(s.app.nav.viewMode, "issues")
    s.navigator.openIssue("i1")
    s.handleMove(1, 0)
    compare(s.app.board.selectedCardId, "m1")
  }

  function test_escape_goes_back_from_an_open_issue_before_closing_the_panel() {
    var s = inIssues(); if (!s) return
    s.navigator.openIssue("i1")
    s.closeRequested()
    compare(s.app.nav.viewMode, "issues")
    compare(tc.calls.indexOf("close"), -1)
  }

  // ---- Runs (5.1)

  function inRuns() {
    var s = make(); if (!s) return null
    // The snapshot the project selection launched cannot run here.
    s.app.runs.snapshotRunner.cancel()
    s.app.runs.runs = [{ id: "run-0000000000a1", repo_dir: "/home/u/a", milestone_id: "alpha", status: "escalated",
                         started_at: "", lease: null, rows: [], tree: { stories: [], subtasks: [] },
                         project: { root: "/home/u/a", name: "alpha" } }]
    s.navigator.showSection("runs")
    return s
  }

  function test_ctrl_6_opens_the_runs_section_after_the_first_five() {
    var s = make(); if (!s) return
    var wanted = ["board", "graph", "documents", "memories", "issues", "runs"]
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5, Qt.Key_6]
    for (var i = 0; i < digits.length; i++) {
      compare(s.handleGlobalKey(ctrl(digits[i])), true, wanted[i])
      compare(s.app.nav.section, wanted[i])
    }
    compare(s.app.nav.viewMode, "runs")
  }

  function test_ctrl_6_is_ignored_while_a_delete_is_being_confirmed() {
    var s = make(); if (!s) return
    s.app.deleter.openDelete(s.app.projects.selectedProject)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "board")
  }

  // K3
  function test_ctrl_6_opens_runs_without_a_project_and_ctrl_1_to_5_do_not() {
    var s = make(); if (!s) return
    s.app.runs.snapshotRunner.cancel()
    s.app.projects.selectedProject = null
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5]
    for (var i = 0; i < digits.length; i++) {
      compare(s.handleGlobalKey(ctrl(digits[i])), true, "Ctrl+" + (i + 1) + " is still handled")
      compare(s.app.nav.viewMode, "board", "Ctrl+" + (i + 1))
    }
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), true)
    compare(s.app.nav.viewMode, "runs")
    for (var j = 0; j < digits.length; j++) {
      compare(s.handleGlobalKey(ctrl(digits[j])), true)
      compare(s.app.nav.viewMode, "runs", "Ctrl+" + (j + 1) + " from Runs")
    }
  }

  function test_escape_and_the_left_arrow_go_back_from_an_open_run() {
    var s = inRuns(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.nav.viewMode, "run")
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs")
    compare(tc.calls.indexOf("close"), -1, "Escape went back instead of closing the panel")
    s.navigator.openRun("run-0000000000a1")
    s.handleMove(-1, 0)
    compare(s.app.nav.viewMode, "runs")
  }

  // ---- The search field

  function test_escape_in_the_search_field_clears_the_query_before_closing_the_panel() {
    var s = make(); if (!s) return
    s.app.nav.searchQuery = "abc"
    var e = plain(Qt.Key_Escape)
    s.handleSearchKey(e)
    compare(e.accepted, true)
    compare(s.app.nav.searchQuery, "")
    compare(tc.calls.indexOf("close"), -1)
    var e2 = plain(Qt.Key_Escape)
    s.handleSearchKey(e2)
    compare(e2.accepted, true)
    verify(tc.calls.indexOf("close") >= 0, "the panel was asked to close")
  }

  function test_the_right_arrow_activates_only_at_the_end_of_the_search_text() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    wait(50)
    tc.atEnd = false
    var e = plain(Qt.Key_Right)
    s.handleSearchKey(e)
    compare(e.accepted, false)
    compare(s.app.nav.viewMode, "board")
    tc.atEnd = true
    var e2 = plain(Qt.Key_Right)
    s.handleSearchKey(e2)
    compare(e2.accepted, true)
    compare(s.app.nav.viewMode, "entry")
  }

  function test_the_up_and_down_arrows_move_the_search_cursor() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "A", "todo"), card("m2", "B", "todo")])
    wait(50)
    var e = plain(Qt.Key_Down)
    s.handleSearchKey(e)
    compare(e.accepted, true)
    compare(s.app.nav.cursorIndex, 1)
    var e2 = plain(Qt.Key_Up)
    s.handleSearchKey(e2)
    compare(e2.accepted, true)
    compare(s.app.nav.cursorIndex, 0)
  }

  function test_enter_in_the_search_field_activates_the_cursor() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "A", "todo")])
    wait(50)
    var e = plain(Qt.Key_Return)
    s.handleSearchKey(e)
    compare(e.accepted, true)
    compare(s.app.nav.viewMode, "entry")
  }

  function test_tab_in_the_search_field_switches_panel() {
    var s = make(); if (!s) return
    var e = plain(Qt.Key_Tab)
    s.handleSearchKey(e)
    compare(e.accepted, true)
    compare(tc.calls.join(","), "switch:1")
    tc.calls = []
    var e2 = shift(Qt.Key_Tab)
    s.handleSearchKey(e2)
    compare(tc.calls.join(","), "switch:-1")
    tc.calls = []
    var e3 = plain(Qt.Key_Backtab)
    s.handleSearchKey(e3)
    compare(tc.calls.join(","), "switch:-1")
  }

  function test_an_unrelated_key_is_left_to_the_search_field() {
    var s = make(); if (!s) return
    var e = plain(Qt.Key_A)
    s.handleSearchKey(e)
    compare(e.accepted, false)
    compare(tc.calls.length, 0)
  }

  // ---- Run keys (S2 4.3)

  // A normalised run, as RunStore holds them. live === null means no lease.
  function normRun(id, status, live) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "m", status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] }, project: { root: "/home/u/a", name: "alpha" } }
  }

  // The Runs list of project A: row 0 running, row 1 parked; cursor on row 0.
  function inRunKeys() {
    var s = make(); if (!s) return null
    // The snapshot the project selection launched cannot run here.
    s.app.runs.snapshotRunner.cancel()
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true), normRun("run-0000000000b2", "stopped", null)]
    s.navigator.showSection("runs")
    s.app.nav.cursorIndex = 0
    return s
  }

  // 8
  function test_c_r_and_p_act_on_the_cursor_run_while_the_search_is_empty() {
    var s = inRunKeys(); if (!s) return
    compare(s.handleRunKey(plain(Qt.Key_R)), true, "a refused key is still handled")
    compare(s.app.runs.flashText, "The run is still running")
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.handleRunKey(plain(Qt.Key_C)), true)
    compare(s.app.runs.cancelOpen, true)
    compare(s.app.runs.cancelRunId, "run-0000000000a1")
    compare(Object.keys(s.app.runs.pending).length, 0, "c only asks")
    s.app.runs.closeCancel()
    compare(s.handleRunKey(plain(Qt.Key_P)), true)
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.controlRunners.length, 1)
    compare(s.handleRunKey(plain(Qt.Key_C)), true)
    compare(s.app.runs.cancelOpen, false, "a run with a request pending gets no dialog")
    compare(s.app.runs.flashText, "A request for this run is pending")
  }

  // 9
  function test_with_search_text_the_letters_are_left_to_the_search_field() {
    var s = inRunKeys(); if (!s) return
    s.app.nav.searchQuery = "run-"
    compare(s.app.runs.filteredRuns.length, 2, "the search still lists both runs")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(s.handleRunKey(plain(Qt.Key_C)), false)
    compare(s.handleRunKey(plain(Qt.Key_R)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
  }

  // 10
  function test_only_a_bare_p_r_or_c_is_a_run_key() {
    var s = inRunKeys(); if (!s) return
    compare(s.handleRunKey(shift(Qt.Key_P)), false, "Shift+P types: that is how a search for parked starts")
    compare(s.handleRunKey(shift(Qt.Key_C)), false)
    compare(s.handleRunKey(ctrl(Qt.Key_C)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_C)), false, "and Ctrl+C is no chord either")
    compare(s.handleRunKey(plain(Qt.Key_X)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
  }

  // 11
  function test_on_run_detail_the_keys_act_on_the_open_run_and_nowhere_else() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000b2")
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_R)), true)
    compare(s.app.runs.pending["run-0000000000b2"], "resume")
    s.navigator.goBack()
    s.navigator.showSection("board")
    compare(s.app.nav.viewMode, "board")
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "board")
    s.app.board.applyTreeData([card("m1", "Milestone", "todo")])
    wait(20)
    s.navigator.openCard("m1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "entry")
    compare(s.app.runs.pending["run-0000000000a1"], undefined)
    compare(s.app.runs.flashText, "")
  }

  // 12
  function test_the_cancel_dialog_swallows_the_keys_and_escape_closes_only_it() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.runs.openCancel("run-0000000000a1"), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "run")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
    s.closeRequested()
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.nav.viewMode, "run", "Escape closed the dialog only")
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs", "the next Escape goes back as before")
    compare(tc.calls.indexOf("close"), -1)
  }

  // 13 (and Review Focus 3)
  function test_no_target_run_leaves_the_letter_to_the_search() {
    var s = inRunKeys(); if (!s) return
    s.app.nav.cursorIndex = 1
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true)]
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "the cursor is past the end of the shrunk list")
    s.app.runs.runs = []
    s.app.nav.cursorIndex = 0
    compare(s.handleRunKey(plain(Qt.Key_P)), false, "an empty list")
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.runs.flashText, "")
  }

  function test_the_open_dropdown_swallows_the_run_keys() {
    var s = inRunKeys(); if (!s) return
    s.navigator.toggleDropdown()
    compare(s.app.nav.dropdownOpen, true)
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(Object.keys(s.app.runs.pending).length, 0)
  }

  // A run key needs a project: with none, the letter is left alone.
  function test_without_a_project_the_run_keys_are_left_alone() {
    var s = inRunKeys(); if (!s) return
    s.app.projects.selectedProject = null
    s.app.runs.runs = [normRun("run-0000000000a1", "started", true)]
    compare(s.app.nav.viewMode, "runs")
    compare(s.handleRunKey(plain(Qt.Key_P)), false)
    compare(s.handleRunKey(plain(Qt.Key_C)), false)
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.flashText, "")
    compare(Object.keys(s.app.runs.pending).length, 0)
  }

  // ---- run toasts (S2 4.4)

  function alertOf(id) { return { id: id, title: "m", state: "escalated", reason: "escalated" } }

  // 21
  function test_escape_dismisses_the_toasts_before_going_back_from_a_run() {
    var s = inRunKeys(); if (!s) return
    s.navigator.openRun("run-0000000000a1")
    compare(s.app.nav.viewMode, "run")
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1"), alertOf("run-0000000000b2")])
    compare(s.app.runs.toasts.length, 2)
    s.closeRequested()
    compare(s.app.runs.toasts.length, 0)
    compare(s.app.nav.viewMode, "run", "that Escape went to the toasts")
    s.closeRequested()
    compare(s.app.nav.viewMode, "runs", "the next one goes back as before")
    compare(tc.calls.indexOf("close"), -1)
  }

  // Review Focus 5
  function test_escape_on_the_board_dismisses_the_toasts_and_keeps_the_panel_open() {
    var s = inRunKeys(); if (!s) return
    s.navigator.showSection("board")
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    s.closeRequested()
    compare(s.app.runs.toasts.length, 0)
    compare(tc.calls.indexOf("close"), -1, "the panel stays open")
    compare(s.app.nav.viewMode, "board")
    s.closeRequested()
    verify(tc.calls.indexOf("close") !== -1, "with no toast left Escape closes the panel as before")
  }

  // 22
  function test_the_cancel_dialog_closes_before_the_toasts() {
    var s = inRunKeys(); if (!s) return
    s.app.runs.raiseAlerts([alertOf("run-0000000000b2")])
    compare(s.app.runs.openCancel("run-0000000000a1"), true)
    s.closeRequested()
    compare(s.app.runs.cancelOpen, false)
    compare(s.app.runs.toasts.length, 1, "the toasts stay")
    s.closeRequested()
    compare(s.app.runs.toasts.length, 0)
    compare(s.app.nav.viewMode, "runs")
    compare(tc.calls.indexOf("close"), -1)
  }

  // 23
  function test_escape_in_the_search_field_dismisses_the_toasts_first() {
    var s = inRunKeys(); if (!s) return
    s.app.nav.searchQuery = "x"
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    var e = plain(Qt.Key_Escape)
    s.handleSearchKey(e)
    compare(e.accepted, true)
    compare(s.app.runs.toasts.length, 0)
    compare(s.app.nav.searchQuery, "x", "the search is kept")
    compare(tc.calls.indexOf("close"), -1)
    s.handleSearchKey(plain(Qt.Key_Escape))
    compare(s.app.nav.searchQuery, "", "the next Escape clears the search")
    compare(tc.calls.indexOf("close"), -1)
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    var e2 = plain(Qt.Key_Escape)
    s.handleSearchKey(e2)
    compare(e2.accepted, true)
    compare(s.app.runs.toasts.length, 0)
    compare(tc.calls.indexOf("close"), -1, "an empty search with toasts showing does not close the panel")
  }

  // 24
  function test_toasts_are_not_a_modal() {
    var s = inRunKeys(); if (!s) return
    s.navigator.showSection("board")
    s.app.runs.raiseAlerts([alertOf("run-0000000000a1")])
    compare(s.modalOpen(), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), true)
    compare(s.app.nav.viewMode, "runs")
    s.app.nav.cursorIndex = 0
    compare(s.handleRunKey(plain(Qt.Key_P)), true)
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.toasts.length, 1, "the keys leave the toasts alone")
  }

  // ---- d: the dispatch dialog (S3 4.2)

  // Project A's board list: milestone m1 (story s1 under it) under the cursor,
  // the search empty, am installed.
  function onBoard() {
    var s = make(); if (!s) return null
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([card("m1", "Milestone", "todo", [card("s1", "Story", "todo")])])
    wait(20)
    s.navigator.showSection("board")
    s.app.nav.cursorIndex = 0
    return s
  }
  function dispatched() { return tc.calls.filter(function(c) { return c.indexOf("dispatch:") === 0 }) }

  // m1 holding s1 (todo), s2 (brd status blocked, blocked by s1) and s3
  // (done), each with one subtask. card() has no blocked_by argument.
  function storyTree() {
    var s2 = card("s2", "Blocked story", "blocked", [card("t2", "Sub two", "todo")])
    s2.blocked_by = ["s1"]
    return [card("m1", "Milestone", "todo", [
      card("s1", "Story", "todo", [card("t1", "Sub one", "todo")]),
      s2,
      card("s3", "Done story", "done", [card("t3", "Sub three", "done")])])]
  }

  // 6
  function test_d_on_the_board_list_asks_for_the_cursor_cards_dispatch() {
    var s = onBoard(); if (!s) return
    compare(s.app.board.boardCards[0].id, "m1")
    compare(s.app.board.boardCards.map(function(c) { return c.id }).indexOf("s1"), -1, "a story is never a board-list row")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:m1")
    compare(s.app.runs.dispatchState, "idle", "the key only asks the panel")
  }

  // 7 (and Review Focus 1)
  function test_d_is_left_alone_data() {
    return [
      { tag: "shift" }, { tag: "ctrl" }, { tag: "search-text" }, { tag: "no-project" }, { tag: "am-missing" },
      { tag: "am-missing-on-story" },
      { tag: "dropdown" }, { tag: "modal" }, { tag: "dispatch-open" }, { tag: "runs" }, { tag: "graph" },
      { tag: "documents" }, { tag: "empty-board" }, { tag: "cursor-past-the-end" }, { tag: "other-letter" }
    ]
  }

  function test_d_is_left_alone(data) {
    var s = onBoard(); if (!s) return
    var e = plain(Qt.Key_D)
    switch (data.tag) {
    case "shift": e = shift(Qt.Key_D); break
    case "ctrl": e = ctrl(Qt.Key_D); break
    case "search-text": s.app.nav.searchQuery = "mile"; break
    case "no-project": s.app.projects.selectedProject = null; s.app.nav.viewMode = "board"; break
    case "am-missing": s.app.runs.amStatus = "missing"; break
    case "am-missing-on-story":
      s.navigator.openCard("s1")
      compare(s.app.nav.viewMode, "entry")
      s.app.runs.amStatus = "missing"
      break
    case "dropdown": s.navigator.toggleDropdown(); break
    case "modal": s.app.runs.cancelRunId = "run-0000000000a1"; break
    case "dispatch-open": s.app.runs.dispatchState = "ready"; break
    case "runs": s.navigator.showSection("runs"); break
    case "graph": s.navigator.showSection("graph"); break
    case "documents": s.navigator.showSection("documents"); break
    case "empty-board": s.app.board.applyTreeData([]); break
    case "cursor-past-the-end": s.app.nav.cursorIndex = 5; break
    case "other-letter": e = plain(Qt.Key_E); break
    }
    compare(s.handleDispatchKey(e), false)
    compare(dispatched().length, 0)
  }

  // 8
  function test_d_on_a_card_asks_for_that_cards_dispatch() {
    var s = onBoard(); if (!s) return
    s.navigator.openCard("s1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:s1")
  }

  // S7: d on an open story asks for that story, whatever its status.
  function test_d_on_an_open_story_asks_for_that_story_data() {
    return [{ tag: "story", id: "s1" }, { tag: "blocked-story", id: "s2" }, { tag: "done-story", id: "s3" }]
  }

  function test_d_on_an_open_story_asks_for_that_story(data) {
    var s = onBoard(); if (!s) return
    s.app.board.applyTreeData(storyTree())
    s.navigator.openCard(data.id)
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, data.id)
    compare(s.app.board.cardMap[data.id].depth, 1, "a story")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:" + data.id)
    compare(s.app.runs.dispatchState, "idle", "the key only asks the panel")
  }

  // S7: the board list holds roots only, so a story is reached through its
  // milestone's card detail; d there asks for the story.
  function test_d_reaches_a_story_from_the_board_list() {
    var s = onBoard(); if (!s) return
    compare(s.app.board.boardCards.map(function(c) { return c.id + ":" + c.depth }).join(","), "m1:0",
            "the board list holds roots only")
    s.navigator.activateCursor()
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "m1")
    compare(s.app.nav.cursorIndex, 0)
    s.navigator.activateCursor()
    compare(s.app.board.selectedCardId, "s1")
    compare(s.handleDispatchKey(plain(Qt.Key_D)), true)
    compare(dispatched().join(","), "dispatch:s1")
  }

  // 9
  function test_an_open_dispatch_is_a_modal() {
    var s = onBoard(); if (!s) return
    compare(s.modalOpen(), false)
    s.app.runs.dispatchState = "ready"
    compare(s.modalOpen(), true)
    compare(s.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(s.handleGlobalKey(ctrl(Qt.Key_6)), false)
    compare(s.app.nav.viewMode, "board")
  }

  // 10
  function test_escape_closes_an_open_dispatch_before_anything_else() {
    var s = onBoard(); if (!s) return
    s.navigator.openCard("s1")
    compare(s.app.runs.openDispatch(s.app.board.cardMap["s1"], s.app.board.cardMap), true, "a story opens on itself")
    compare(s.app.runs.dispatchState, "previewing")
    s.closeRequested()
    compare(s.app.runs.dispatchState, "idle")
    compare(s.app.nav.viewMode, "entry", "that Escape closed the dialog only")
    compare(tc.calls.indexOf("close"), -1)
    s.closeRequested()
    compare(s.app.nav.viewMode, "board", "the next one goes back as before")
  }

  // 10
  function test_escape_while_a_start_is_in_flight_does_nothing() {
    var s = onBoard(); if (!s) return
    s.navigator.openCard("s1")
    s.app.runs.dispatchState = "starting"
    s.closeRequested()
    compare(s.app.runs.dispatchState, "starting")
    compare(s.app.nav.viewMode, "entry", "no Back")
    compare(tc.calls.indexOf("close"), -1, "no panel close")
  }
}
