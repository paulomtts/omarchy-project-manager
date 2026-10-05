// tests/ui/screens/tst_card_detail_screen.qml
// ui/screens/CardDetailScreen.qml on its own: the parent/blocker/child link
// rows, the kind and status badges, the description fallback, a blocker that is
// not in this board, the click that opens a link through the navigator, and the
// card's comments as the extras store holds them.
// REAL core/stores App and REAL ui/Navigator.qml -- no bespoke mocks.
import QtQuick
import QtTest
import "../../helpers/find.js" as H

TestCase {
  id: tc
  name: "CardDetailScreen"
  when: windowShown
  visible: true
  width: 500; height: 700

  Component { id: hostC; Item { width: 500; height: 700 } }
  Component { id: flickC; Flickable { width: 500; height: 300; contentWidth: 500; contentHeight: 2000 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  function card(id, title, status, description, children, blockedBy) {
    return { id: id, title: title, status: status, description: description,
      blocked_by: blockedBy || [], children: children || [] }
  }

  function roots() {
    return [
      card("m1", "Milestone one", "todo", "m desc", [
        card("s1", "Story one", "todo", "s desc",
          [card("t1", "Subtask one", "done", "t desc")], ["x1", "ghost"])]),
      card("x1", "Other milestone", "in_progress", "x desc")]
  }

  function make() {
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
    var sC = Qt.createComponent("../../../ui/screens/CardDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var s = sC.createObject(host, { app: app, navigator: nav, width: 500 })
    app.projects.stateLoaded = true
    app.projects.stateReadOk = true
    app.projects.applyProjectsList([pA])
    app.board.applyTreeData(roots())
    return s
  }

  function texts(item, out) {
    out = out || []
    if (item.visible === false) return out
    if (item.text !== undefined && String(item.text) !== "") out.push(String(item.text))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) texts(kids[i], out)
    return out
  }

  // The clickable link rows: the items that carry a `resolved` descriptor.
  function links(item, out) {
    out = out || []
    if (item.resolved !== undefined && item.rowIndex !== undefined && item.visible !== false) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) links(kids[i], out)
    return out
  }

  function test_the_card_detail_shows_only_for_an_open_card_that_is_in_the_board() {
    var s = make(); if (!s) return
    compare(s.visible, false)
    s.navigator.openCard("s1")
    compare(s.app.nav.viewMode, "entry")
    compare(s.visible, true)
    s.app.board.selectedCardId = "nope"
    compare(s.visible, false)
  }

  function test_the_open_card_renders_its_title_badges_and_description() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var t = texts(s)
    verify(t.indexOf("Story one") >= 0, t.join(" | "))
    verify(t.indexOf("Story") >= 0, "the kind badge by depth: " + t.join(" | "))
    verify(t.indexOf("Todo") >= 0, "the status badge: " + t.join(" | "))
    verify(t.indexOf("s desc") >= 0, t.join(" | "))
  }

  function test_a_card_without_a_description_says_so() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo", "")])
    s.navigator.openCard("m1")
    wait(50)
    verify(texts(s).indexOf("No description.") >= 0, texts(s).join(" | "))
  }

  function test_the_parent_blocker_and_child_links_are_listed_with_their_sections() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var t = texts(s)
    verify(t.indexOf("BLOCKED BY") >= 0, t.join(" | "))
    verify(t.indexOf("CHILDREN") >= 0, t.join(" | "))
    var rows = links(s)
    var titles = rows.map(function(r) { return r.prefix + r.resolved.title })
    compare(titles.join(","), "↑ Milestone one,Other milestone,ghost,Subtask one")
  }

  function test_a_blocker_that_is_not_in_this_board_is_marked_and_not_openable() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var rows = links(s)
    var ghost = rows.filter(function(r) { return r.resolved.title === "ghost" })[0]
    verify(ghost, "the unresolved blocker row")
    compare(ghost.resolved.inBoard, false)
    compare(ghost.rowIndex, -1)
    verify(texts(ghost).join(" | ").indexOf("ghost (not in this board)") >= 0, texts(ghost).join(" | "))
    mouseClick(ghost)
    compare(s.app.board.selectedCardId, "s1")
  }

  function test_clicking_a_child_link_opens_that_card() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var rows = links(s)
    var child = rows.filter(function(r) { return r.resolved.title === "Subtask one" })[0]
    verify(child, "the child row")
    mouseClick(child)
    compare(s.app.board.selectedCardId, "t1")
  }

  function test_clicking_the_parent_link_opens_the_parent_card() {
    var s = make(); if (!s) return
    s.navigator.openCard("s1")
    wait(50)
    var rows = links(s)
    compare(rows[0].prefix, "↑ ")
    mouseClick(rows[0])
    compare(s.app.board.selectedCardId, "m1")
  }

  function test_an_issue_blocker_shows_its_title_and_state_and_opens_the_issue() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([
      card("m1", "Milestone one", "todo", "m desc", [], ["x1", "i1", "i2", "ghost"]),
      card("x1", "Other milestone", "in_progress", "x desc")])
    s.app.board.applyIssueData([
      { id: "i1", kind: "issue", title: "Broken build", status: "open" },
      { id: "i2", kind: "issue", title: "Old bug", status: "closed" }])
    s.navigator.openCard("m1")
    wait(50)
    var rows = links(s)
    compare(rows.map(function(r) { return r.resolved.title }).join(","), "Other milestone,Broken build,Old bug,ghost")
    var open = rows[1]
    var closed = rows[2]
    compare(open.rowIndex, 1, "a known issue takes a keyboard link row")
    compare(closed.rowIndex, 2)
    compare(s.app.board.detailLinkList.map(function(l) { return l.id }).join(","), "x1,i1,i2")
    var openText = texts(open).join(" | ")
    verify(openText.indexOf("Broken build") >= 0, openText)
    verify(openText.indexOf("Issue · open") >= 0, openText)
    verify(openText.indexOf("not in this board") < 0, openText)
    verify(texts(closed).join(" | ").indexOf("Issue · closed") >= 0, texts(closed).join(" | "))
    verify(closed.opacity < 1, "a closed issue is dimmed")
    compare(open.opacity, 1)
    compare(rows[0].opacity, 1)
    // The README promises this row opens in the Issues section.
    s.app.extras.applyExportResult(JSON.stringify({ ok: true, data: {
      issues: [{ id: "i1", title: "Broken build", body: "b", status: "open", close_reason: null,
                 blocks: ["m1"], created_at: "2026-09-20T10:00:00+00:00",
                 updated_at: "2026-09-24T10:00:00+00:00" }], comments: [], refs: [] } }), 0)
    wait(50)
    mouseClick(open)
    compare(s.app.nav.viewMode, "issue")
    compare(s.app.extras.selectedIssueId, "i1")
    compare(s.app.board.selectedCardId, "m1", "the card stays open behind the issue")
    s.navigator.goBack()
    compare(s.app.nav.viewMode, "entry", "Back from that issue returns to the card")
    compare(s.app.board.selectedCardId, "m1")
    compare(s.app.extras.selectedIssueId, "")
  }

  // An issue the export never carried cannot be opened: the row is inert rather
  // than switching to a blank Issues detail.
  function test_an_issue_blocker_the_extras_never_carried_does_not_open() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "todo", "m desc", [], ["i1"])])
    s.app.board.applyIssueData([{ id: "i1", kind: "issue", title: "Broken build", status: "open" }])
    s.navigator.openCard("m1")
    wait(50)
    var row = links(s).filter(function(r) { return r.resolved.title === "Broken build" })[0]
    verify(row, "the issue blocker row")
    mouseClick(row)
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.extras.selectedIssueId, "")
  }

  function test_the_card_detail_lists_the_cards_comments() {
    var s = make(); if (!s) return          // s.app is the real App, s is the CardDetailScreen
    s.app.extras.applyExportResult(JSON.stringify({ ok: true, data: { issues: [], refs: [],
      comments: [{ id: "k1", entity_id: "m1", author: "paulo", body: "note", created_at: "2026-09-24T09:00:00+00:00" }] } }), 0)
    s.app.nav.viewMode = "entry"
    s.app.board.openCard("m1")
    compare(H.find(s, "cardComments").comments.length, 1)
    compare(H.find(s, "commentBody0").text, "note")
  }

  // The fixture's own cards are not blocked, so this test gives itself a blocked
  // root; the badge is about the card's status plus its open blockers.
  function test_the_card_detail_flags_an_open_issue_next_to_blocked() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("b1", "Blocked one", "blocked", "b desc", [], ["i1"])])
    s.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    s.app.nav.viewMode = "entry"
    s.app.board.openCard("b1")
    wait(50)
    var badge = H.find(s, "cardDetailIssueBadge")
    verify(badge, "the issue badge")
    compare(badge.visible, true)
    compare(badge.text, "1 open issue")
    s.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "closed" }])
    wait(50)
    compare(H.find(s, "cardDetailIssueBadge").visible, false)
  }

  function test_a_card_without_comments_says_so() {
    var s = make(); if (!s) return
    s.app.nav.viewMode = "entry"
    s.app.board.openCard("m1")
    compare(H.find(s, "commentsEmpty").visible, true)
  }
  // ---- RUNS (5.3)

  function mkRun(id, status, live, milestone, tree, startedAt) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: startedAt || "",
             base_branch: "", branch_prefix: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: tree || { stories: [], subtasks: [] } }
  }
  function hoursAgo(h) { return new Date(Date.now() - h * 3600000).toISOString() }

  // am's order, newest first:
  //   …a1 live, milestone m1, story s1 with subtask t1 in `implement`, 2 h old
  //   …b2 escalated, milestone x1 only
  //   …c3 done, milestone m1, story s1, 30 h old
  function withRuns(s) {
    s.app.runs.snapshotRunner.cancel()
    s.app.runs.runs = [
      mkRun("run-0000000000a1", "started", true, "m1",
            { stories: [{ card_id: "s1", subtasks: ["t1"] }],
              subtasks: [{ card_id: "t1", phases: [{ name: "implement", status: "started" }] }] }, hoursAgo(2)),
      mkRun("run-0000000000b2", "escalated", null, "x1", null, hoursAgo(5)),
      mkRun("run-0000000000c3", "done", null, "m1",
            { stories: [{ card_id: "s1", subtasks: [] }], subtasks: [] }, hoursAgo(30))]
    return s
  }

  function test_the_runs_section_lists_the_runs_that_touch_the_card() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    var header = H.find(s, "cardRunsHeader")
    verify(header, "the RUNS header")
    compare(header.visible, true)
    compare(header.text, "RUNS")
    var first = H.find(s, "cardRunRow0")
    verify(first, "a row per touching run, newest first")
    compare(H.find(first, "runBadge").text, "⟳")
    compare(H.find(first, "cardRunId0").text, "…000000a1")
    compare(H.find(first, "cardRunTitle0").text, "m1")
    compare(H.find(first, "cardRunPhase0").text, "implement")
    compare(H.find(first, "cardRunAge0").text, "2h")
    var second = H.find(s, "cardRunRow1")
    verify(second, "the finished run is history and still listed")
    compare(H.find(second, "runBadge").text, "✔")
    compare(H.find(second, "cardRunId1").text, "…000000c3")
    compare(H.find(second, "cardRunPhase1").visible, false, "no phase is started")
    compare(H.find(second, "cardRunAge1").text, "1d")
    verify(!H.find(s, "cardRunRow2"), "the escalated run of x1 does not touch s1")
    compare(first.index, -1, "a RUNS row is not in the keyboard's link list")
  }

  function test_an_escalated_run_row_reads_urgent() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("x1")
    wait(50)
    var row = H.find(s, "cardRunRow0")
    verify(row)
    compare(H.find(row, "runBadge").text, "‼")
    verify(Qt.colorEqual(H.find(row, "runBadge").tint, s.theme.urgent))
    verify(!H.find(s, "cardRunRow1"))
  }

  function test_the_runs_section_follows_a_new_snapshot() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, true)
    s.app.runs.runs = [s.app.runs.runs[1]]
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, false, "no run touches s1 any more")
    compare(s.touchingRuns.length, 0)
    verify(texts(s).indexOf("Story one") >= 0, "the card itself still renders")
  }

  function test_the_runs_section_is_hidden_when_no_run_touches_the_card() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("t1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, true, "t1 is a subtask of the live run")
    s.app.board.applyTreeData([card("z1", "Lonely", "todo", "z desc")])
    s.navigator.openCard("z1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, false)
    verify(!H.find(s, "cardRunRow0"))
  }

  function test_the_runs_section_is_hidden_while_am_is_missing() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    s.app.runs.amStatus = "missing"
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, false)
    compare(s.touchingRuns.length, 0)
    verify(texts(s).indexOf("Story one") >= 0, "the card still renders")
  }

  function test_stale_run_data_dims_the_rows_and_stops_the_pulse() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    var row = H.find(s, "cardRunRow0")
    compare(row.opacity, 1)
    compare(H.find(row, "runBadge").pulsing, true)
    s.app.runs.stale = true
    wait(50)
    verify(row.opacity < 1)
    compare(H.find(row, "runBadge").pulsing, false)
  }

  function test_a_merged_card_still_lists_its_runs() {
    var s = make(); if (!s) return
    s.app.board.applyTreeData([card("m1", "Milestone one", "merged", "m desc")])
    withRuns(s)
    s.navigator.openCard("m1")
    wait(50)
    compare(H.find(s, "cardRunsHeader").visible, true, "history: the brd-status gate is the Board's and the Graph's only")
    compare(s.touchingRuns.length, 2)
  }

  function test_clicking_a_run_row_opens_run_detail_and_back_returns_to_the_card() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    mouseClick(H.find(s, "cardRunRow1"))
    compare(s.app.nav.viewMode, "run")
    compare(s.app.runs.selectedRunId, "run-0000000000c3")
    compare(s.app.nav.runReturnMode, "entry", "opened as openRun(id, \"entry\")")
    s.navigator.goBack()
    compare(s.app.nav.viewMode, "entry")
    compare(s.app.board.selectedCardId, "s1")
    compare(s.app.runs.selectedRunId, "")
  }

  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function rc(s, i, name) { return H.find(H.find(s, "cardRunControls" + i), "runControl" + name) }

  // 19
  function test_a_story_cards_live_run_offers_whole_run_controls() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(rc(s, 0, "Pause").visible, true)
    compare(rc(s, 0, "Pause").text, "Pause run")
    compare(rc(s, 0, "Cancel").text, "Cancel run")
    compare(rc(s, 0, "Resume").visible, false)
    compare(rc(s, 0, "Caption").visible, true)
    compare(rc(s, 0, "Caption").text, "applies to the whole run")
    compare(rc(s, 1, "Buttons").visible, false, "the done run is history: no controls")
    compare(H.find(s, "cardRunControls1").height, 0)
  }

  function test_a_subtask_card_also_says_whole_run() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("t1")
    wait(50)
    compare(rc(s, 0, "Pause").text, "Pause run")
    compare(rc(s, 0, "Caption").visible, true)
  }

  // 20
  function test_a_milestone_cards_run_rows_use_the_plain_labels() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("m1")
    wait(50)
    compare(rc(s, 0, "Pause").text, "Pause")
    compare(rc(s, 0, "Cancel").text, "Cancel")
    compare(rc(s, 0, "Caption").visible, false)
  }

  // 21
  function test_pause_run_starts_a_request_without_opening_the_run() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    compare(s.app.runs.project, "/home/u/a", "control() refuses without a project")
    mouseClick(rc(s, 0, "Pause"))
    compare(s.app.runs.pending["run-0000000000a1"], "pause")
    compare(s.app.runs.controlRunners.length, 1)
    compare(s.app.runs.controlRunners[0].action, "pause")
    compare(s.app.runs.controlRunners[0].runId, "run-0000000000a1")
    compare(s.app.nav.viewMode, "entry", "the button is not the row")
    compare(rc(s, 0, "Pause").text, "Pause requested…")
    compare(rc(s, 0, "Pause").enabled, false)
  }

  function test_cancel_run_asks_the_owner_and_starts_nothing() {
    var s = make(); if (!s) return
    withRuns(s)
    s.navigator.openCard("s1")
    wait(50)
    cancelSpy.target = s
    cancelSpy.clear()
    mouseClick(rc(s, 0, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-0000000000a1")
    compare(s.app.runs.controlRunners.length, 0)
    compare(Object.keys(s.app.runs.pending).length, 0)
    compare(s.app.nav.viewMode, "entry")
  }
}
