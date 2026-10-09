// tests/ui/screens/tst_run_detail_screen.qml
// ui/screens/RunDetailScreen.qml on its own: the header, the story > subtask >
// attempt tree with its bookkeeping rows, the Output / Events tabs with the
// output pane and the events pane, and the missing-run line. A stub app: a
// REAL NavigationStore, a plain object carrying the RunStore properties the
// screen reads (with recorders for selectAttempt, refreshLogs and
// setDetailTab), and a board whose cardMap lends titles and brd statuses.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components/runGlyphs.js" as RG
import "../../helpers/amFixtures.js" as F
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "RunDetailScreen"
  when: windowShown
  visible: true
  width: 500; height: 900

  Component { id: hostC; Item { width: 500; height: 900 } }

  Component {
    id: runsC
    QtObject {
      id: rs
      property var runs: []
      property string selectedRunId: ""
      property var selectedAttempt: null
      property string logsText: ""
      property bool logsTruncated: false
      property real logsFetchedMs: 0
      property bool logsLoading: false
      property string logsError: ""
      property string amStatus: "ok"
      property string flashText: ""
      property var selected: null
      property int refreshed: 0
      function selectAttempt(cardId, phase, attempt) {
        rs.selected = [cardId, phase, attempt]
        rs.selectedAttempt = { card_id: cardId, phase: phase, attempt: attempt }
      }
      function refreshLogs() { rs.refreshed += 1 }
      // The events and the tab (4.3). setDetailTab records every call and,
      // as the store does, takes only output and events.
      property var events: []
      property int eventsDropped: 0
      property string eventsStatus: "idle"
      property string eventsError: ""
      property string eventsFilter: "All"
      property string detailTab: "output"
      property var tabCalls: []
      function setDetailTab(tab) {
        rs.tabCalls = rs.tabCalls.concat([tab])
        if (tab !== "output" && tab !== "events") return false
        rs.detailTab = tab
        return true
      }
      // The control surface the header reads (S2 4.2). `control` only records.
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property var controlCalls: []
      function control(action, id) {
        rs.controlCalls = rs.controlCalls.concat([action + "|" + id])
        return true
      }
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" } })
      property var board: ({ cardMap: {
        s1: { id: "s1", title: "Runs screens", status: "in_progress" },
        t1: { id: "t1", title: "RunDetailScreen", status: "in_progress" },
        t2: { id: "t2", title: "Old work", status: "merged" },
        s2: { id: "s2", title: "Dropped story", status: "canceled" },
        t3: { id: "t3", title: "Shelved", status: "archived" }
      } })
    }
  }

  function make(list, selectedId, attempt) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs })
    var sC = Qt.createComponent("../../../ui/screens/RunDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: null })
    nav.viewMode = "run"
    runs.runs = list || []
    runs.selectedRunId = selectedId === undefined ? "run-20261004-19efcddc" : selectedId
    runs.selectedAttempt = attempt === undefined ? null : attempt
    wait(20)
    return { app: app, runs: runs, nav: nav, screen: screen }
  }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // A normalised run, as RunStore holds them. live === null means no lease.
  function run(id, status, live, opts) {
    var o = opts || {}
    return { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "M3" : o.milestone,
             base_branch: o.base === undefined ? "master" : o.base,
             branch_prefix: o.prefix === undefined ? "m3" : o.prefix,
             status: status, started_at: "",
             lease: live === null ? null : { pid: 4121, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: o.rows || [], tree: o.tree || { stories: [], subtasks: [] } }
  }

  function detailTree() {
    return { stories: [{ card_id: "s1", status: "started", subtasks: ["t1", "t2"] },
                       { card_id: "s2", status: "cancelled", subtasks: ["t3"] }],
             subtasks: [
               { card_id: "t1", status: "started", phases: [
                 { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
                 { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] },
               { card_id: "t2", status: "done", phases: [{ name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] }] },
               { card_id: "t3", phases: [] }] }
  }

  function detail() { return [run("run-20261004-19efcddc", "started", true, { tree: detailTree() })] }
  function sel(card, phase, n) { return { card_id: card, phase: phase, attempt: n } }

  // One am run as RunStore hands it to normalizeRun, fresh on every call: the
  // fixture's `am runs` row (runs.json's entry with the same run id, else the
  // fixture's own _am_runs_row) without `status`, and the fixture's `am status`
  // data.
  function amRun(name) {
    var fixture = F.load(name)
    var runs = F.load("runs.json").data.runs
    var row = fixture._am_runs_row
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].id === fixture.data.run.id) row = runs[i]
    }
    delete row.status
    return { row: row, status: fixture.data }
  }

  // ---- header

  function test_the_header_names_the_run_its_state_and_its_branches() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runDetailTitle").text, "Run …19efcddc")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("running") + " running")
    compare(H.find(s.screen, "runDetailMeta").text, "Milestone M3 · prefix m3 · base master · lease pid 4121 live")
    compare(H.find(s.screen, "runDetailReason").visible, false, "only an escalated run has a reason")
  }

  function test_a_dead_lease_and_no_lease() {
    var s = make([run("run-x-dead0001", "started", false, {})], "run-x-dead0001"); if (!s) return
    compare(H.find(s.screen, "runDetailMeta").text, "Milestone M3 · prefix m3 · base master · lease pid 4121 not live")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("dead") + " dead")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent), "dead is urgent")
    s.runs.runs = [run("run-x-dead0001", "stopped", null, { milestone: "", prefix: "", base: "" })]
    compare(H.find(s.screen, "runDetailMeta").text, "no lease", "empty parts are left out")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("parked") + " parked")
  }

  function test_an_escalated_run_shows_its_reason_in_urgent() {
    var s = make([run("run-x-escl0002", "escalated", null, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } })],
      "run-x-escl0002"); if (!s) return
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("escalated") + " escalated")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent))
    var reason = H.find(s.screen, "runDetailReason")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    verify(Qt.colorEqual(reason.color, s.screen.theme.urgent))
  }

  // ---- tree

  function test_story_and_subtask_rows_carry_glyph_title_status_and_phase() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " s1 Runs screens · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " t1 RunDetailScreen · started · implement.2")
    compare(H.find(s.screen, "runSubtaskLabel0_1").text, RG.glyphOf("done") + " t2 Old work · done · spec.1")
    compare(H.find(s.screen, "runStory1").text, RG.glyphOf("cancelled") + " s2 Dropped story · cancelled")
    compare(H.find(s.screen, "runSubtaskLabel1_0").text, "t3 Shelved", "no status, no phase: just the card")
  }

  function test_terminal_brd_cards_are_dimmed_not_hidden() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_1").visible, true, "merged is listed")
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5)
    compare(H.find(s.screen, "runStory1").visible, true, "canceled is listed")
    compare(H.find(s.screen, "runStory1").opacity, 0.5)
    compare(H.find(s.screen, "runSubtask1_0").opacity, 0.5, "archived too")
    compare(H.find(s.screen, "runStory0").opacity, 1)
  }

  function test_the_timeline_and_attempts_show_under_the_selected_subtask_only() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    var tl = H.find(s.screen, "runTimeline0_0")
    compare(tl.visible, true)
    compare(tl.text, "spec" + RG.GLYPHS.done + " → implement" + RG.GLYPHS.running)
    compare(H.find(s.screen, "runTimeline0_1").visible, false)
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("done") + " spec.1 done")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "  " + RG.glyphOf("dead") + " implement.1 failed")
    var chosen = H.find(s.screen, "runAttemptLabel0_0_2")
    compare(chosen.text, "› " + RG.glyphOf("running") + " implement.2 started", "a marker, not colour alone")
    compare(chosen.font.bold, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_1").font.bold, false)
    compare(H.find(s.screen, "runAttempt0_1_0"), null, "another subtask's attempts stay folded")
  }

  function test_no_selection_shows_no_attempt_rows() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runAttempt0_0_0"), null)
    compare(H.find(s.screen, "runTimeline0_0").visible, false)
    compare(H.find(s.screen, "runOutputNone").visible, true)
    compare(H.find(s.screen, "runOutputNone").text, "No attempt selected")
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
  }

  function test_clicking_an_attempt_selects_it() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected.join("|"), "t1|spec|1")
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text.indexOf("› "), 0, "the clicked row is marked")
    compare(H.find(s.screen, "runAttemptLabel0_0_2").text.indexOf("  "), 0)
  }

  // Review Focus 4.
  function test_clicking_a_subtask_selects_its_current_attempt() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runSubtask0_1"))
    compare(s.runs.selected.join("|"), "t2|spec|1")
    verify(H.find(s.screen, "runAttempt0_1_0"), "its attempts unfold")
    compare(H.find(s.screen, "runAttempt0_0_0"), null, "the other subtask folds")
    s.runs.selected = null
    tap(H.find(s.screen, "runSubtask1_0"))
    compare(s.runs.selected, null, "a subtask with no attempt selects nothing")
  }

  function test_failed_and_escalated_tree_rows_are_drawn_urgent() {
    var tree = { stories: [{ card_id: "s1", status: "escalated", subtasks: ["t1", "t2"] }],
                 subtasks: [
                   { card_id: "t1", status: "failed", phases: [{ name: "implement", status: "started",
                     attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] },
                   { card_id: "t2", status: "done", phases: [] },
                   { card_id: "integrate", status: "dead" }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, sel("t1", "implement", 2)); if (!s) return
    var urgent = s.screen.theme.urgent, fg = s.screen.theme.foreground
    verify(!Qt.colorEqual(urgent, fg), "the theme tells the two apart")
    verify(Qt.colorEqual(H.find(s.screen, "runStory0").color, urgent), "an escalated story")
    verify(Qt.colorEqual(H.find(s.screen, "runSubtaskLabel0_0").color, urgent), "a failed subtask")
    verify(Qt.colorEqual(H.find(s.screen, "runSubtaskLabel0_1").color, fg), "a done subtask is not urgent")
    verify(Qt.colorEqual(H.find(s.screen, "runAttemptLabel0_0_0").color, urgent), "a failed attempt")
    verify(Qt.colorEqual(H.find(s.screen, "runAttemptLabel0_0_1").color, fg), "a started attempt is not urgent")
    verify(Qt.colorEqual(H.find(s.screen, "runSynthetic0").color, urgent), "a dead bookkeeping row")
  }

  // Real am: review.1 of 10e26d57 is the gate_failed attempt that escalated
  // status-escalated.json; explore.1 of the same subtask is ok.
  function test_a_gate_failed_attempt_of_real_am_shows_the_dead_glyph_in_urgent() {
    var run = Runs.normalizeRun(amRun("status-escalated.json"))
    var card = "10e26d57-374c-48d3-bc45-09389b42cfac"
    var key = ""
    var stories = Runs.runTree(run).stories
    for (var si = 0; si < stories.length; si++) {
      for (var ti = 0; ti < stories[si].subtasks.length; ti++) {
        var t = stories[si].subtasks[ti]
        if (t.card_id !== card) continue
        for (var ai = 0; ai < t.attempts.length; ai++) {
          if (t.attempts[ai].phase === "review" && t.attempts[ai].attempt === 1) key = si + "_" + ti + "_" + ai
        }
      }
    }
    compare(key, "1_0_6", "where the capture puts review.1 of " + card)
    var s = make([run], run.id, sel(card, "review", 1)); if (!s) return
    var failed = H.find(s.screen, "runAttemptLabel" + key)
    compare(failed.text, "› " + RG.glyphOf("dead") + " review.1 gate_failed")
    verify(Qt.colorEqual(failed.color, s.screen.theme.urgent), "a gate_failed attempt is urgent")
    var ok = H.find(s.screen, "runAttemptLabel1_0_0")
    compare(ok.text, "  " + RG.glyphOf("done") + " explore.1 ok")
    verify(Qt.colorEqual(ok.color, s.screen.theme.foreground), "an ok attempt is not urgent")
  }

  // Review Focus 3.
  function test_an_unnumbered_attempt_is_listed_but_not_clickable() {
    var tree = { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ status: "started" }, { n: 1, status: "failed" }] }] }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("running") + " implement.? started")
    s.runs.selected = null
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected, null)
  }

  function test_bookkeeping_rows_only_when_present() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSynthetic0"), null)
    var tree = detailTree()
    tree.stories.push({ card_id: "base-s1", status: "done" })
    s.runs.runs = [run("run-20261004-19efcddc", "started", true,
                       { tree: tree, rows: [{ card_id: "integrate", phase: "integrate", status: "" }] })]
    compare(H.find(s.screen, "runSynthetic0").text, RG.glyphOf("done") + " Base s1 done")
    compare(H.find(s.screen, "runSynthetic1").text, "Integrate not started")
    compare(H.find(s.screen, "runStory2"), null, "a bookkeeping id is never a story row")
  }

  // ---- output pane

  function test_the_output_pane_is_a_labelled_snapshot_never_live() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "collecting...\n3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    var heading = H.find(s.screen, "runOutputHeading")
    var age = H.find(s.screen, "runOutputAge")
    compare(heading.text, "Output · t1 implement.2")
    compare(age.text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputText").text, "collecting...\n3 passed")
    s.runs.logsTruncated = true
    compare(age.text, "snapshot 14s ago · last 200 lines")
    compare(heading.text.indexOf("live"), -1)
    compare(age.text.indexOf("live"), -1)
    compare(H.find(s.screen, "runOutputRefresh").text, "Refresh")
  }

  function test_loading_then_an_error_that_keeps_the_text() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsLoading = true
    compare(H.find(s.screen, "runOutputAge").text, "loading…")
    s.runs.logsLoading = false
    s.runs.logsText = "old text"
    s.runs.logsError = "AmMissing: am is not installed."
    var err = H.find(s.screen, "runOutputError")
    compare(err.visible, true)
    compare(err.text, "AmMissing: am is not installed.")
    verify(Qt.colorEqual(err.color, s.screen.theme.urgent))
    compare(H.find(s.screen, "runOutputText").visible, true, "the last text stays")
    compare(H.find(s.screen, "runOutputText").text, "old text")
    compare(H.find(s.screen, "runStory0").visible, true, "the tree stays as the snapshot left it")
  }

  function test_refresh_asks_the_store_again() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runOutputRefresh"))
    compare(s.runs.refreshed, 1)
  }

  // ---- missing, malformed, visibility

  function test_a_run_no_longer_in_the_snapshot() {
    var s = make(detail(), "run-gone"); if (!s) return
    var msg = H.find(s.screen, "runDetailMissing")
    compare(msg.visible, true)
    compare(msg.text, "This run is no longer in the snapshot")
    compare(H.find(s.screen, "runDetailBody").visible, false)
  }

  function test_a_malformed_run_renders_without_throwing() {
    var odd = { id: "run-20261004-19efcddc", status: 7, lease: "x", rows: "y",
                tree: { stories: "x", subtasks: [null, 5, { card_id: 7 }, { card_id: "t9", phases: "x" }] } }
    var s = make([odd]); if (!s) return
    compare(H.find(s.screen, "runDetailMissing").visible, false)
    compare(H.find(s.screen, "runStory0").text, "Other")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, "t9")
    compare(H.find(s.screen, "runOutputNone").visible, true)
  }

  function test_the_screen_is_hidden_outside_the_run_view() {
    var s = make(detail()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "runs"
    compare(s.screen.visible, false)
    s.nav.viewMode = "run"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, true, "no project: Run detail still shows")
  }

  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function ctl(s, name) { return H.find(H.find(s.screen, "runDetailControls"), "runControl" + name) }

  // 17
  function test_a_running_run_offers_pause_and_cancel_without_hover() {
    var s = make(detail()); if (!s) return
    compare(ctl(s, "Pause").visible, true)
    compare(ctl(s, "Pause").text, "Pause")
    compare(ctl(s, "Cancel").visible, true)
    compare(ctl(s, "Resume").visible, false)
    compare(ctl(s, "Caption").visible, false, "Run detail is the run itself, not a card")
  }

  function test_a_parked_run_offers_resume() {
    var s = make([run("run-x-park0002", "stopped", null, {})], "run-x-park0002"); if (!s) return
    compare(ctl(s, "Resume").visible, true)
    compare(ctl(s, "Resume").enabled, true)
    compare(ctl(s, "Pause").visible, false)
  }

  function test_pause_goes_to_the_store_and_cancel_only_asks() {
    var s = make(detail()); if (!s) return
    cancelSpy.target = s.screen
    cancelSpy.clear()
    tap(ctl(s, "Pause"))
    compare(s.runs.controlCalls.join(","), "pause|run-20261004-19efcddc")
    tap(ctl(s, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-20261004-19efcddc")
    compare(s.runs.controlCalls.length, 1, "cancel never reaches the store")
  }

  function test_the_runs_own_error_and_waiting_lines() {
    var s = make(detail()); if (!s) return
    s.runs.lastControlError = "The run no longer exists"
    s.runs.lastControlErrorRunId = "run-other"
    compare(ctl(s, "Error").visible, false, "another run's error")
    s.runs.lastControlErrorRunId = "run-20261004-19efcddc"
    compare(ctl(s, "Error").visible, true)
    compare(ctl(s, "Error").text, "The run no longer exists")
    s.runs.pending = { "run-20261004-19efcddc": "pause" }
    s.runs.stillWaiting = { "run-20261004-19efcddc": true }
    compare(ctl(s, "Pause").text, "Pause requested…")
    compare(ctl(s, "Waiting").visible, true)
  }

  // 18
  function test_a_done_run_shows_no_controls() {
    var s = make([run("run-x-done0003", "done", null, {})], "run-x-done0003"); if (!s) return
    compare(ctl(s, "Buttons").visible, false)
    compare(H.find(s.screen, "runDetailControls").height, 0)
  }

  // ---- the flash line (S2 4.3)

  // 15
  function test_the_flash_line_shows_only_while_there_is_a_flash() {
    var s = make(detail()); if (!s) return
    var line = H.find(s.screen, "runDetailFlash")
    verify(line, "the flash line")
    compare(line.visible, false)
    s.runs.flashText = "Integrate is running; it cannot be paused or cancelled"
    compare(line.visible, true)
    compare(line.text, "Integrate is running; it cannot be paused or cancelled")
    s.runs.flashText = ""
    compare(line.visible, false)
  }

  // ---- the Output / Events tabs (4.3)

  // A complete row as RunEvents.eventRow returns it; `fields` overrides.
  function eventRow(seq, fields) {
    var row = { seq: seq, time: "12:00:00", level: "attempt", label: "row " + seq, status: "done",
                glyph: "done", duration: "", detail: "", card: "card-" + seq, phase: "implement",
                attempt: 1 }
    for (var key in fields) row[key] = fields[key]
    return row
  }

  function rowsUpTo(n) {
    var rows = []
    for (var i = 1; i <= n; i++) rows.push(eventRow(i, {}))
    return rows
  }

  function shown(s, name) { return H.find(s.screen, name).visible }

  // 6
  function test_run_detail_opens_on_the_output_tab() {
    var s = make(detail()); if (!s) return
    var output = H.find(s.screen, "runTaboutput")
    verify(output, "the Output chip")
    compare(output.text, "Output")
    compare(output.active, true)
    verify(H.find(s.screen, "runTabevents"), "the Events chip")
    compare(H.find(s.screen, "runTabevents").active, false)
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
  }

  // 7
  function test_the_events_chip_counts_rows_held_plus_dropped() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runTabevents").text, "Events 0", "none")
    s.runs.events = rowsUpTo(3)
    s.runs.eventsDropped = 40
    compare(H.find(s.screen, "runTabevents").text, "Events 43")
    s.runs.events = rowsUpTo(5)
    compare(H.find(s.screen, "runTabevents").text, "Events 45")
    s.runs.events = []
    s.runs.eventsDropped = 0
    compare(H.find(s.screen, "runTabevents").text, "Events 0")
  }

  // 8
  function test_the_chips_switch_the_tabs() {
    var s = make(detail()); if (!s) return
    tap(H.find(s.screen, "runTabevents"))
    compare(s.runs.tabCalls.join(","), "events")
    compare(shown(s, "eventsPane"), true)
    compare(shown(s, "runOutputPane"), false)
    compare(H.find(s.screen, "runTabevents").active, true)
    tap(H.find(s.screen, "runTabevents"))
    compare(s.runs.detailTab, "events", "the active chip changes nothing")
    compare(shown(s, "eventsPane"), true)
    tap(H.find(s.screen, "runTaboutput"))
    compare(s.runs.detailTab, "output")
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
    compare(H.find(s.screen, "runTaboutput").active, true)
  }

  // 9
  function test_the_events_pane_shows_the_store_state() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = rowsUpTo(2)
    s.runs.eventsDropped = 3
    s.runs.eventsStatus = "ok"
    var pane = H.find(s.screen, "eventsPane")
    compare(JSON.stringify(pane.rows), JSON.stringify(s.runs.events))
    compare(pane.filter, "All")
    compare(pane.dropped, 3)
    compare(pane.status, "ok")
    compare(pane.errorMessage, "")
    verify(H.find(pane, "eventsRow2"), "the store's rows are drawn")
    compare(H.find(pane, "eventsErrorText").visible, false)
    s.runs.eventsStatus = "error"
    s.runs.eventsError = "AmMissing: am is not on PATH."
    compare(pane.status, "error")
    compare(pane.errorMessage, "AmMissing: am is not on PATH.")
    compare(H.find(pane, "eventsErrorText").visible, true)
  }

  // 10
  function test_a_filter_chip_sets_the_store_filter() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(1, { level: "phase", glyph: "dead", status: "failed" }), eventRow(2, {})]
    var pane = H.find(s.screen, "eventsPane")
    tap(H.find(pane, "eventsFilterChipFailures"))
    compare(s.runs.eventsFilter, "Failures")
    compare(pane.filter, "Failures", "the pane follows the store")
    compare(H.find(pane, "eventsFilterChipFailures").active, true)
  }

  // 11
  function test_a_row_naming_an_attempt_selects_it_and_shows_output() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(5, { card: "t1", phase: "implement", attempt: 1 })]
    wait(30)
    tap(H.find(s.screen, "eventsRow5"))
    compare(s.runs.selected.join("|"), "t1|implement|1")
    compare(s.runs.detailTab, "output")
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.1")
  }

  // 12
  function test_a_row_without_an_attempt_changes_nothing() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(6, { attempt: 0 })]
    wait(30)
    tap(H.find(s.screen, "eventsRow6"))
    compare(s.runs.selected, null)
    compare(s.runs.detailTab, "events")
    compare(s.runs.tabCalls.join(","), "events", "no tab call from the row")
  }

  // 13
  function test_a_missing_run_shows_no_tabs() {
    var s = make(detail(), "run-gone"); if (!s) return
    compare(shown(s, "runDetailBody"), false)
    compare(shown(s, "runTabs"), false)
    compare(shown(s, "runDetailMissing"), true)
  }

  // 14 and Review Focus 3
  function test_garbage_events_count_as_none() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail()); if (!s) return
    s.runs.eventsDropped = 2
    s.runs.events = null
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "null")
    s.runs.events = "abcdefghi"
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "a string")
    s.runs.events = { length: 9 }
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "an object with a length")
    s.runs.setDetailTab("events")
    compare(shown(s, "eventsPane"), true)
  }

  // Review Focus 1
  function test_rows_that_arrive_while_output_shows_open_at_the_newest() {
    var s = make(detail()); if (!s) return
    s.runs.events = rowsUpTo(60)
    wait(30)
    tap(H.find(s.screen, "runTabevents"))
    wait(30)
    var pane = H.find(s.screen, "eventsPane")
    var list = H.find(pane, "eventsList")
    verify(list.contentHeight > list.height, "the list scrolls")
    compare(pane.following, true)
    verify(Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1, "at the newest row")
    compare(H.find(pane, "eventsJump").visible, false)
  }

  // Review Focus 2
  function test_switching_tabs_keeps_the_output_and_the_filter() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.eventsFilter = "Failures"
    tap(H.find(s.screen, "runTabevents"))
    tap(H.find(s.screen, "runTaboutput"))
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(s.runs.selected, null, "no attempt was selected")
    compare(s.runs.refreshed, 0, "nothing was fetched")
    compare(s.runs.eventsFilter, "Failures")
  }
}
