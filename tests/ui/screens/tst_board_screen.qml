// tests/ui/screens/tst_board_screen.qml
// ui/screens/BoardScreen.qml on its own: the status sections and their counts,
// the derived-blocked-in-todo rule, the empty/no-match messages, and the
// hover/click forwarding to the navigator. Built on the REAL core/stores App
// and the REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "BoardScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var reveals: []

  function card(id, title, status, children, blockedBy) {
    return { id: id, title: title, status: status, description: "d",
      blocked_by: blockedBy || [], children: children || [] }
  }

  function make() {
    tc.reveals = []
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
    var sC = Qt.createComponent("../../../ui/screens/BoardScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    s.revealRequested.connect(function(item) { tc.reveals.push(item) })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    return s
  }

  // Every visible piece of text the screen renders, in tree order.
  function texts(item, out) {
    out = out || []
    if (item.visible === false) return out
    if (item.text !== undefined && String(item.text) !== "") out.push(String(item.text))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) texts(kids[i], out)
    return out
  }

  // Every rendered board card, in tree order (they are the items with cardIndex).
  function cards(item, out) {
    out = out || []
    if (item.cardIndex !== undefined && item.title !== undefined && item.progress !== undefined) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) cards(kids[i], out)
    return out
  }

  function test_the_board_screen_shows_only_in_the_board_view_with_a_project() {
    var s = make(); if (!s) return
    compare(s.visible, true)
    s.app.nav.viewMode = "graph"
    compare(s.visible, false)
    s.app.nav.viewMode = "board"
    compare(s.visible, true)
    s.app.projects.selectedProject = null
    compare(s.visible, false)
  }

  function test_cards_are_grouped_into_status_sections_with_counts() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([
      card("m1", "Milestone one", "todo", [card("s1", "Story", "done")]),
      card("m2", "Milestone two", "in_progress"),
      card("m3", "Milestone three", "done")])
    wait(50)
    var t = texts(s)
    verify(t.indexOf("Todo (1)") >= 0, "Todo header: " + t.join(" | "))
    verify(t.indexOf("In Progress (1)") >= 0, "In Progress header: " + t.join(" | "))
    verify(t.indexOf("Done (1)") >= 0, "Done header: " + t.join(" | "))
    verify(t.indexOf("Milestone one") >= 0)
    verify(t.indexOf("1/1 done") >= 0, "the subtree progress: " + t.join(" | "))
  }

  function test_a_blocked_root_is_listed_under_todo_and_labelled_blocked() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo"), card("b1", "Blocked one", "blocked")])
    wait(50)
    var t = texts(s)
    verify(t.indexOf("Todo (2)") >= 0, "both roots in Todo: " + t.join(" | "))
    verify(t.indexOf("Blocked") >= 0, "the blocked label: " + t.join(" | "))
  }

  function test_an_empty_board_says_so_and_a_search_with_no_match_says_so() {
    var s = make(); if (!s) return
    wait(50)
    verify(texts(s).indexOf("This project's board is empty.") >= 0)
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo")])
    wait(50)
    verify(texts(s).indexOf("This project's board is empty.") < 0)
    s.app.nav.searchQuery = "zzz"
    wait(50)
    verify(texts(s).indexOf("No cards match “zzz”.") >= 0, texts(s).join(" | "))
  }

  function test_clicking_a_card_opens_it_through_the_navigator() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo"), card("m2", "Milestone two", "todo")])
    wait(50)
    var list = cards(s)
    compare(list.length, 2)
    compare(list[1].title, "Milestone two")
    mouseClick(list[1])
    compare(s.app.board.selectedCardId, "m2")
    compare(s.app.nav.viewMode, "entry")
  }

  function test_a_card_blocked_by_an_open_issue_carries_an_issue_badge() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("b1", "Blocked one", "blocked", [], ["i1"])])
    s.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    wait(50)
    var badge = H.find(s, "boardCardIssues0")
    verify(badge, "the issue badge of the first board card")
    compare(badge.visible, true)
    compare(badge.text, "1 open issue")
    s.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "closed" }])
    wait(50)
    compare(H.find(s, "boardCardIssues0").visible, false, "a closed issue no longer flags the card")
  }

  function test_hovering_a_card_moves_the_cursor_through_the_navigator() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo"), card("m2", "Milestone two", "todo")])
    wait(50)
    var list = cards(s)
    compare(list.length, 2)
    compare(s.app.nav.cursorIndex, 0)
    mouseMove(list[1], list[1].width / 2, list[1].height / 2)
    compare(s.app.nav.cursorIndex, 1)
    compare(list[1].hasCursor, true)
  }

  // ---- 5.3: am run marks on the board's cards.

  // A normalised run (runs.js normalizeRun's shape), built directly. live === null: no lease.
  function mkRun(id, status, live, milestone, tree, rows) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: rows || [], tree: tree || { stories: [], subtasks: [] } }
  }

  // The roots and the runs that touch them:
  //   m1 milestone of a live run with one running subtask row -> counts + bar
  //   m2 a root am runs as a subtask, phase `review`          -> glyph + phase
  //   m3 touched by nothing                                    -> nothing
  //   m4 merged, yet the milestone of a live run               -> nothing (brd-status gate)
  //   m5 milestone of a parked run                             -> dimmed counts
  function withRuns() {
    var s = make(); if (!s) return null
    s.app.runs.snapshotRunner.cancel()
    s.app.board.applyTreeData([
      card("m1", "Milestone one", "in_progress", [card("s1", "Story", "in_progress", [card("t1", "Sub", "in_progress")])]),
      card("m2", "Solo task", "todo"),
      card("m3", "Untouched", "todo"),
      card("m4", "Merged one", "merged"),
      card("m5", "Parked one", "in_progress")])
    s.app.runs.runs = [
      mkRun("run-a1", "started", true, "m1",
        { stories: [{ card_id: "s1", subtasks: ["t1"] }],
          subtasks: [{ card_id: "t1", status: "started", phases: [{ name: "implement", status: "started" }] }] },
        [{ card_id: "t1", status: "running" }]),
      mkRun("run-b2", "started", true, "mX",
        { stories: [], subtasks: [{ card_id: "m2", status: "started", phases: [{ name: "review", status: "started" }] }] },
        [{ card_id: "m2", status: "running" }]),
      mkRun("run-c3", "started", true, "m4",
        { stories: [], subtasks: [{ card_id: "t4", status: "started", phases: [] }] }, [{ card_id: "t4", status: "running" }]),
      mkRun("run-d4", "stopped", null, "m5",
        { stories: [], subtasks: [{ card_id: "t5", status: "stopped", phases: [] }] }, [{ card_id: "t5", status: "stopped" }])]
    wait(50)
    return s
  }
  function cardTitled(s, title) { return cards(s).filter(function(c) { return c.title === title })[0] }
  function badgeText(c) { var b = H.find(c, "runBadgeText"); return b ? b.text : "" }

  function test_a_card_am_runs_as_a_subtask_shows_its_glyph_and_phase() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Solo task")
    var mark = H.find(c, "runMark")
    verify(mark, "the card carries a run mark")
    compare(mark.visible, true)
    compare(badgeText(c), "⟳ review")
    compare(H.find(c, "runBadge").pulsing, true, "a live running subtask pulses")
    compare(H.find(c, "runRollupBar").visible, false, "a subtask has no rollup bar")
  }

  function test_a_milestone_card_shows_counts_and_a_rollup_bar() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Milestone one")
    compare(H.find(c, "runMark").visible, true)
    compare(badgeText(c), "⟳ 1")
    compare(H.find(c, "runBadge").pulsing, false, "the counts form never pulses")
    compare(H.find(c, "runMark").opacity, 1)
    var bar = H.find(c, "runRollupBar")
    compare(bar.visible, true)
    compare(H.find(bar, "runRollupRunning").text, "⟳ 1")
  }

  function test_an_untouched_card_shows_no_run_mark() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Untouched")
    compare(H.find(c, "runMark").visible, false)
    compare(H.find(c, "runRollupBar").visible, false)
  }

  function test_a_merged_or_canceled_card_shows_no_run_mark_even_when_a_run_touches_it() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Merged one")
    verify(c, "the merged card is on the board")
    compare(H.find(c, "runMark").visible, false)
    compare(H.find(c, "runRollupBar").visible, false)
    s.app.board.applyTreeData([card("m4", "Merged one", "canceled")])
    wait(50)
    compare(H.find(cardTitled(s, "Merged one"), "runMark").visible, false, "canceled too")
    s.app.board.applyTreeData([card("m4", "Merged one", "in_progress")])
    wait(50)
    compare(H.find(cardTitled(s, "Merged one"), "runMark").visible, true,
            "the gate is visibility only: the same run shows once the card is live again")
  }

  function test_a_dimmed_winner_is_drawn_dimmed_and_does_not_pulse() {
    var s = withRuns(); if (!s) return
    var c = cardTitled(s, "Parked one")
    var mark = H.find(c, "runMark")
    compare(mark.visible, true)
    compare(badgeText(c), "⏸ 1")
    verify(mark.opacity < 1, "a finished run speaking for the card is dimmed")
    compare(H.find(c, "runBadge").active, false)
    compare(H.find(c, "runBadge").pulsing, false)
    verify(H.find(c, "runRollupBar").opacity < 1, "its rollup bar is dimmed with it")
  }

  function test_am_missing_hides_every_run_mark() {
    var s = withRuns(); if (!s) return
    s.app.runs.amStatus = "missing"
    wait(50)
    var all = cards(s)
    compare(all.length, 5)
    for (var i = 0; i < all.length; i++) {
      compare(H.find(all[i], "runMark").visible, false, all[i].title)
      compare(H.find(all[i], "runRollupBar").visible, false, all[i].title)
    }
    verify(texts(s).indexOf("Milestone one") >= 0, "the board still renders")
  }

  function test_stale_run_data_dims_the_marks() {
    var s = withRuns(); if (!s) return
    s.app.runs.stale = true
    wait(50)
    var solo = cardTitled(s, "Solo task")
    verify(H.find(solo, "runMark").opacity < 1)
    compare(H.find(solo, "runBadge").pulsing, false, "stale data does not pulse")
    verify(H.find(cardTitled(s, "Milestone one"), "runMark").opacity < 1)
    s.app.runs.stale = false
    wait(50)
    compare(H.find(solo, "runMark").opacity, 1)
    compare(H.find(solo, "runBadge").pulsing, true)
  }
}
