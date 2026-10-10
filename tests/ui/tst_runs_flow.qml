// tests/ui/tst_runs_flow.qml
// What the panel does around the run store: Ctrl+6, a chip, the search field,
// the cursor, opening a run and coming back, the focus in a run, and the
// sidebar's attention count. The filters are tested in tests/core/; the rows
// in tests/ui/screens/tst_runs_screen.qml.
import QtQuick
import QtTest
import "../helpers/find.js" as H
import "../helpers/amFixtures.js" as F
import "../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "RunsFlow"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function run(id, status, live, milestone) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: milestone, status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] }, project: { root: "/home/u/a", name: "alpha" } }
  }

  // run(), in the project at `root` named `name`.
  function runIn(id, status, live, milestone, root, name) {
    var r = run(id, status, live, milestone)
    r.repo_dir = root
    r.project = { root: root, name: name }
    return r
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    // Selecting the project starts a `brd export`, a runs snapshot and a run
    // settings read that cannot run here: all three are disarmed so their late
    // replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runControl.settingsLoadRunner.cancel()
    p.app.runControl.runSettingsLoadRunner.cancel()
    p.app.runs.runs = sampleRuns()
    return p
  }

  function sampleRuns() {
    return [run("run-0000000000a1", "started", true, "alpha"),
            run("run-0000000000b2", "escalated", null, "beta"),
            run("run-0000000000c3", "started", false, "gamma"),
            run("run-0000000000d4", "stopped", null, "delta")]
  }

  // make() with no project selected. The registry still lists pA, so the run
  // store keeps its root; the runs are set again after the clear.
  function makeNoProject() {
    var p = make(); if (!p) return null
    p.app.projects.selectedProject = null
    p.app.runs.runs = sampleRuns()
    return p
  }
  function labels(crumbs) { return crumbs.map(function(c) { return c.label }).join(" > ") }
  function ids(list) { return list.map(function(r) { return r.id }).join(",") }
  function key(k) { return { modifiers: Qt.NoModifier, key: k, accepted: false } }

  function test_ctrl_6_opens_the_runs_section_with_its_search_field() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.sectionTitle, "Runs")
    compare(labels(p.navigator.crumbs), "Runs")
    wait(50)
    var field = H.find(p, "searchField")
    compare(field.visible, true)
    compare(String(field.placeholderText), "Search runs…")
    compare(p.focusItem.objectName, "searchField")
    var view = H.find(p, "runsView")
    verify(view, "the Runs screen is mounted")
    compare(view.visible, true)
    compare(H.find(p, "refreshButton").visible, false, "refresh does not apply to runs")
  }

  function test_chip_search_cursor_enter_and_escape() {
    var p = make(); if (!p) return
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    H.find(p, "runChipattention").clicked()
    compare(p.app.runs.runFilter, "attention")
    compare(ids(p.navigator.currentList()), "run-0000000000b2,run-0000000000c3")
    compare(p.app.nav.cursorIndex, 0)
    var field = H.find(p, "searchField")
    field.text = "gamma"
    compare(ids(p.navigator.currentList()), "run-0000000000c3", "the search composes with the chip")
    field.text = ""
    compare(p.navigator.currentList().length, 2)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 1)
    p.shortcuts.handleSearchKey(key(Qt.Key_Up))
    compare(p.app.nav.cursorIndex, 0)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000c3")
    compare(labels(p.navigator.crumbs), "Runs > …000000c3")
    compare(p.focusItem.objectName, "keyCatcher", "Escape in a run must reach the key catcher")
    compare(H.find(p, "runsView").visible, false)
    compare(field.visible, false)
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.cursorIndex, 1, "back on the row it left")
    compare(p.app.runs.runFilter, "attention", "the chip is kept")
    compare(p.app.runs.selectedRunId, "")
  }

  function test_the_finished_chip_and_its_rows_set_the_real_store() {
    var p = make(); if (!p) return
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    H.find(p, "runChipfinished").clicked()
    compare(p.app.runs.runFilter, "finished")
    wait(20)
    compare(H.find(p, "runStateChips").visible, true)
    H.find(p, "runStateChipdone").clicked()
    compare(p.app.runs.finishedState, "done")
    compare(H.find(p, "runStateChipdone").active, true)
    H.find(p, "runAgeChipweek").clicked()
    compare(p.app.runs.finishedAge, "week")
    compare(H.find(p, "runAgeChipweek").active, true)
  }

  // A different chip is a different list: the panel scrolls back to its top.
  // The list stays taller than the panel either way, so nothing but that
  // scroll can bring the content back up.
  function test_a_chip_scrolls_the_panel_back_to_the_top() {
    var p = make(); if (!p) return
    var many = []
    for (var i = 0; i < 40; i++) many.push(run("run-live-" + (1000 + i), "started", true, "m" + i))
    many.push(run("run-0000000000d4", "stopped", null, "delta"))
    p.app.runs.runs = many
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    var flick = H.find(p, "panelFlick")
    verify(flick, "the panel's flickable")
    verify(flick.contentHeight > flick.height + 40, "the list overflows the panel")
    flick.contentY = 40
    wait(50)
    compare(flick.contentY, 40)
    H.find(p, "runChiplive").clicked()
    wait(50)
    verify(flick.contentHeight > flick.height + 40, "the filtered list still overflows")
    compare(flick.contentY, 0)
  }

  function test_the_left_arrow_and_the_crumb_also_leave_a_run() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000a1")
    p.shortcuts.handleMove(-1, 0)
    compare(p.app.nav.viewMode, "runs")
    p.navigator.openRun("run-0000000000a1")
    p.navigator.activateCrumb(0)
    compare(p.app.nav.viewMode, "runs")
  }

  function test_the_run_view_renders_and_enter_there_does_nothing() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000b2")
    wait(50)
    compare(p.navigator.currentList().length, 0)
    p.shortcuts.handleActivate()
    p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
  }

  function test_the_sidebar_shows_how_many_runs_need_attention() {
    var p = make(); if (!p) return
    wait(50)
    var count = H.find(p, "navCountRuns")
    verify(count, "the Runs count")
    compare(String(count.text), "‼2", "one escalated and one dead run")
    p.app.runs.runs = []
    compare(String(count.text), "")
  }

  function test_an_empty_runs_list_ignores_enter() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.app.runs.runs = []
    wait(50)
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "runs")
    compare(H.find(p, "runsMessage").text, "No runs yet.", "the registry holds alpha")
  }

  // alpha (two runs that need attention) is listed before beta (one live
  // run): the cursor's third position is beta's first run, under beta's header.
  function test_enter_on_the_first_run_of_the_second_project_opens_it() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB])
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [runIn("run-0000000000f6", "started", true, "zeta", "/home/u/b", "beta"),
                       runIn("run-0000000000b2", "escalated", null, "beta-ms", "/home/u/a", "alpha"),
                       runIn("run-0000000000c3", "started", false, "gamma", "/home/u/a", "alpha")]
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
    compare(ids(p.app.runs.filteredRuns), "run-0000000000b2,run-0000000000c3,run-0000000000f6")
    compare(H.find(p, "runGroupName1").text, "beta")
    compare(p.app.nav.cursorIndex, 0)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 2)
    compare(H.find(p, "runRow2").hasCursor, true, "the highlight is on beta's run")
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f6")
  }

  function test_a_project_that_leaves_the_registry_takes_its_runs_with_it() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    p.app.projects.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.runs.runs.length, 0)
  }

  // ---- Run detail (5.2)

  // A started run with one story s1 > subtask t1 whose implement phase is on
  // its second attempt.
  function treeRun(id) {
    var r = run(id, "started", true, "alpha")
    r.tree = { stories: [{ card_id: "s1", subtasks: ["t1"] }], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] }] }
    return r
  }

  // The panel on the detail view of treeRun("run-0000000000e5"), its default
  // attempt's logs in flight.
  function openDetail() {
    var p = make(); if (!p) return null
    p.app.runs.runs = [treeRun("run-0000000000e5")]
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000e5")
    wait(50)
    return p
  }

  // A fresh logs-attempt.json `am logs` reply, as one JSON line, whose stdout
  // artifact text is `text`.
  function logsOk(text) {
    var envelope = F.load("logs-attempt.json")
    // synthetic: the text is the test's; the envelope is the capture's.
    envelope.data.artifacts.stdout.text = text
    return JSON.stringify(envelope) + "\n"
  }

  function test_opening_a_run_shows_it_and_fetches_its_default_attempt() {
    var p = openDetail(); if (!p) return
    compare(p.app.nav.viewMode, "run")
    var view = H.find(p, "runDetailView")
    verify(view, "the Run detail screen is mounted")
    compare(view.visible, true)
    compare(H.find(p, "runsView").visible, false)
    compare(H.find(p, "runDetailTitle").text, "milestone …alpha", "the open board has no card alpha")
    compare(H.find(p, "runDetailId").text, "…000000e5")
    var proc = p.app.runs.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    verify(String(proc.command[1]).indexOf("core/backend/runs/runs-logs.py") > 0, String(proc.command[1]))
    compare(proc.command.slice(2).join("|"), "/home/u/a|run-0000000000e5|t1|implement|2")
    proc.outText = logsOk("3 passed\n")
    proc.exited(0)
    compare(H.find(p, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(p, "runOutputText").text, "3 passed")
    compare(p.navigator.currentList().length, 0, "no keyboard list in the run view")
  }

  function test_escape_returns_to_runs_and_clears_the_logs() {
    var p = openDetail(); if (!p) return
    var proc = p.app.runs.logsRunner.current
    proc.outText = logsOk("3 passed\n")
    proc.exited(0)
    compare(p.app.runs.logsText, "3 passed")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.selectedRunId, "")
    compare(p.app.runs.selectedAttempt, null)
    compare(p.app.runs.logsText, "")
    compare(H.find(p, "runDetailView").visible, false)
    compare(H.find(p, "runsView").visible, true)
  }

  function test_a_project_switch_on_the_run_view_leaves_it_and_the_late_logs_land() {
    var p = openDetail(); if (!p) return
    var proc = p.app.runs.logsRunner.current
    p.app.projects.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.nav.viewMode, "board")
    compare(H.find(p, "runDetailView").visible, false)
    proc.outText = logsOk("late\n")
    proc.exited(0)
    compare(p.app.runs.logsText, "late", "the late reply is applied")
    compare(p.app.runs.logsLoading, false)
  }

  // ---- run controls (S2 4.2): pause -> requested -> parked, then a refused resume

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // One run of a runs-snapshot-all.py entry: the `am runs` summary whose
  // `status` the helper replaced with the `am status` data. workflow "task"
  // makes a resume skip the run-settings read.
  function snapEntry(id, runStatus, live, milestone) {
    var control = live === null ? {} : { lease: { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live } }
    return { id: id, workflow: "task", repo_dir: "/home/u/a", started_at: "",
             status: { run: { id: id, status: runStatus, milestone_id: milestone },
                       rows: [], stories: [], subtasks: [], control: control } }
  }

  // runs-snapshot-all.py's reply: pA's entry lists `entries`.
  function snapOk(entries) {
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: entries }], data_dir: "/d" }) + "\n"
  }

  function controlOf(p, name) { return H.find(H.find(p, "runRowControls0"), "runControl" + name) }

  // 22
  function test_pause_is_requested_then_settled_by_a_parked_snapshot_and_a_refusal_shows_inline() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    verify(row, "the running run's row")
    mouseMove(row, row.width / 2, row.height / 2)
    compare(p.app.nav.cursorIndex, 0)
    wait(50)

    var pause = controlOf(p, "Pause")
    compare(pause.visible, true)
    compare(pause.enabled, true)
    mouseClick(pause)
    compare(p.app.nav.viewMode, "runs", "the button did not open the run")
    compare(p.app.runControl.pending["run-0000000000a1"], "pause")
    compare(pause.text, "Pause requested…")
    compare(pause.enabled, false)
    compare(p.app.runControl.controlRunners.length, 1)

    reply(p.app.runControl.controlRunners[0].current,
          JSON.stringify({ ok: true, data: { run_id: "run-0000000000a1", command: "pause", requested_at: "t1" } }) + "\n", 0)
    compare(p.app.runControl.pending["run-0000000000a1"], "pause", "acknowledged, still pending until a snapshot")
    var snap = p.app.runs.snapshotRunner.current
    verify(snap, "the ok reply fetched the runs again")
    reply(snap, snapOk([snapEntry("run-0000000000a1", "stopped", null, "alpha"),
                        snapEntry("run-0000000000b2", "escalated", null, "beta")]), 0)
    compare(p.app.runControl.pending["run-0000000000a1"], undefined, "parked: the request settled")
    wait(50)

    var resume = controlOf(p, "Resume")
    compare(resume.visible, true, "the parked run's row offers Resume")
    compare(resume.enabled, true)
    compare(controlOf(p, "Pause").visible, false)

    wait(450)
    mouseClick(resume)
    compare(p.app.runControl.pending["run-0000000000a1"], "resume")
    compare(p.app.runControl.controlRunners.length, 1)
    reply(p.app.runControl.controlRunners[0].current,
          JSON.stringify({ ok: false, error: { type: "NotAcceptingError", message: "run is in integrate" } }) + "\n", 0)
    var error = controlOf(p, "Error")
    compare(error.visible, true)
    compare(error.text, "Integrate is running; it cannot be paused or cancelled")
    compare(controlOf(p, "Resume").enabled, true, "the buttons come back")
    compare(controlOf(p, "Resume").text, "Resume")
    compare(H.find(H.find(p, "runRowControls1"), "runControlError").visible, false, "only under that run")
  }

  // ---- cancel confirmation and the run keys (S2 4.3)

  function cancelModal(p) { return H.find(p, "runCancelModal") }
  // An item of the run cancel dialog (the delete dialog has the same names).
  function inModal(p, name) { return H.find(cancelModal(p), name) }

  // 16 (and Review Focus: the focus comes back)
  function test_cancel_asks_for_the_typed_word_then_cancels_and_gives_the_focus_back() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    mouseMove(row, row.width / 2, row.height / 2)
    wait(50)
    var cancel = controlOf(p, "Cancel")
    compare(cancel.enabled, true)
    mouseClick(cancel)
    wait(50)
    var modal = cancelModal(p)
    verify(modal, "the run cancel dialog")
    compare(modal.visible, true)
    compare(p.app.runControl.cancelRunId, "run-0000000000a1")
    compare(p.app.nav.viewMode, "runs", "the click did not open the run")
    compare(p.focusItem.objectName, "runCancelField")
    var field = inModal(p, "runCancelField")
    verify(field.activeFocus, "the field has the keyboard")
    compare(String(field.placeholderText), "cancel")
    compare(inModal(p, "confirmCancel").text, "Keep running")
    var accept = inModal(p, "confirmAccept")
    compare(accept.text, "Cancel run")
    compare(modal.message, "Cancel run …000000a1? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first.")
    compare(modal.detail, "milestone …alpha")

    field.text = "cancle"
    compare(p.app.runControl.cancelText, "cancle")
    compare(accept.enabled, false)
    keyClick(Qt.Key_Return)
    compare(p.app.runControl.controlRunners.length, 0)
    compare(modal.visible, true)

    field.text = "cancel"
    compare(accept.enabled, true)
    wait(450)
    mouseClick(accept)
    compare(p.app.runControl.pending["run-0000000000a1"], "cancel")
    compare(p.app.runControl.controlRunners.length, 1)
    compare(modal.visible, false)
    wait(50)
    compare(p.focusItem.objectName, "searchField")
    verify(H.find(p, "searchField").activeFocus, "the focus is back in the search field")
    compare(controlOf(p, "Cancel").text, "Cancel requested…")
  }

  // make(): the open project is /home/u/a, whose map mirrors its board.
  function test_the_cancel_dialog_detail_is_the_runs_title() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData([{ id: "alpha", title: "Alpha work", status: "todo", description: "",
                                 blocked_by: [], children: [] }])
    compare(p.app.runTitles.titlesByRoot["/home/u/a"].alpha, "Alpha work", "the open project's map")
    compare(p.app.runControl.openCancel("run-0000000000a1"), true)
    wait(50)
    var modal = cancelModal(p)
    compare(modal.visible, true)
    compare(modal.detail, "Alpha work")
    compare(modal.message, "Cancel run …000000a1? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first.")
    p.app.runControl.closeCancel()
  }

  // makeTwo(): run-0000000000f6 is beta's (/home/u/b), milestone zeta.
  function test_the_cancel_dialog_detail_of_another_projects_run_reads_its_own_map() {
    var p = makeTwo(); if (!p) return
    p.app.runTitles.titlesRunner.cancel()
    var maps = Runs.copyMap(p.app.runTitles.titlesByRoot)
    maps["/home/u/a"] = { zeta: "Alpha zeta" }
    maps["/home/u/b"] = { zeta: "Beta zeta" }
    p.app.runTitles.titlesByRoot = maps
    compare(p.app.runControl.openCancel("run-0000000000f6"), true)
    wait(50)
    compare(cancelModal(p).detail, "Beta zeta")
    p.app.runControl.closeCancel()
  }

  // 17 (Review Focus: a handled letter never types; Escape closes only the dialog)
  function test_c_in_the_empty_search_opens_the_dialog_without_typing_and_escape_closes_it() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    compare(p.app.nav.cursorIndex, 0)
    keyClick("c")
    compare(p.app.runControl.cancelOpen, true)
    compare(p.app.runControl.cancelRunId, "run-0000000000a1")
    compare(field.text, "", "the handled letter was not typed")
    compare(p.app.nav.searchQuery, "")
    wait(50)
    compare(p.focusItem.objectName, "runCancelField")
    keyClick(Qt.Key_Escape)
    compare(p.app.runControl.cancelOpen, false)
    compare(p.app.nav.viewMode, "runs")
    compare(Object.keys(p.app.runControl.pending).length, 0)
    compare(p.opened, true, "the panel stays open")
    wait(50)
    verify(field.activeFocus, "the focus is back in the search field")
    keyClick("C", Qt.ShiftModifier)
    compare(field.text, "C", "Shift+C types")
    compare(p.app.runControl.cancelOpen, false)
    keyClick("p")
    compare(field.text, "Cp", "with search text a bare letter types too")
    compare(Object.keys(p.app.runControl.pending).length, 0)
  }

  // 18
  function test_integrate_disables_pause_and_cancel_and_a_key_says_why() {
    var p = make(); if (!p) return
    var r = run("run-0000000000a1", "started", true, "alpha")
    r.lease.accepting = false
    p.app.runs.runs = [r]
    p.navigator.showSection("runs")
    wait(50)
    var row = H.find(p, "runRow0")
    mouseMove(row, row.width / 2, row.height / 2)
    wait(50)
    compare(controlOf(p, "Pause").enabled, false)
    compare(controlOf(p, "Cancel").enabled, false)
    var reason = "Integrate is running; it cannot be paused or cancelled"
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), true)
    compare(H.find(p, "runsFooter").text, reason)
    compare(p.app.runControl.controlRunners.length, 0)
    p.app.runControl.flash("")
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), true)
    compare(p.app.runControl.cancelOpen, false)
    compare(cancelModal(p).visible, false)
    compare(H.find(p, "runsFooter").text, reason)

    p.navigator.openRun("run-0000000000a1")
    wait(50)
    var detail = H.find(p, "runDetailControls")
    compare(H.find(detail, "runControlPause").enabled, false)
    compare(H.find(detail, "runControlCancel").enabled, false)
    p.app.runControl.flash("")
    compare(H.find(p, "runDetailFlash").visible, false)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_P)), true)
    compare(H.find(p, "runDetailFlash").visible, true)
    compare(H.find(p, "runDetailFlash").text, reason)
    compare(p.shortcuts.handleRunKey(key(Qt.Key_C)), true)
    compare(p.app.runControl.cancelOpen, false)
    compare(p.app.runControl.controlRunners.length, 0)
    compare(Object.keys(p.app.runControl.pending).length, 0)
  }

  // 19 (and Review Focus 5)
  function test_a_cards_runs_row_cancel_opens_the_same_dialog_and_keep_running_closes_it() {
    var p = make(); if (!p) return
    p.app.board.applyTreeData([{ id: "alpha", title: "Alpha", status: "in_progress", description: "d", blocked_by: [], children: [] }])
    p.app.runs.runs = [run("run-0000000000a1", "started", true, "alpha")]
    wait(50)
    p.navigator.openCard("alpha")
    wait(50)
    compare(p.app.nav.viewMode, "entry")
    var cancel = H.find(H.find(p, "cardRunControls0"), "runControlCancel")
    verify(cancel, "the card's RUNS row carries the run's Cancel")
    compare(cancel.enabled, true)
    mouseClick(cancel)
    wait(50)
    compare(cancelModal(p).visible, true)
    compare(p.app.runControl.cancelRunId, "run-0000000000a1")
    compare(p.focusItem.objectName, "runCancelField")
    inModal(p, "runCancelField").text = "cancel"
    compare(inModal(p, "confirmAccept").enabled, true)
    wait(450)
    mouseClick(inModal(p, "confirmCancel"))
    compare(p.app.runControl.cancelOpen, false)
    compare(cancelModal(p).visible, false)
    compare(p.app.nav.viewMode, "entry", "the card is still open")
    compare(p.app.board.selectedCardId, "alpha")
    compare(p.app.runControl.controlRunners.length, 0)
    wait(50)
    compare(p.focusItem.objectName, "keyCatcher")

    wait(450)
    mouseClick(cancel)
    wait(50)
    compare(cancelModal(p).visible, true)
    compare(inModal(p, "runCancelField").text, "", "the old word does not carry over")
    compare(inModal(p, "confirmAccept").enabled, false)
  }

  // ---- run toasts (S2 4.4)

  // The next snapshot of project A lists `entries`.
  function feed(p, entries) {
    p.app.runs.refresh()
    reply(p.app.runs.snapshotRunner.current, snapOk(entries), 0)
  }

  // On `view`: a baseline snapshot (it only arms the alerts), then one where
  // beta (b2) has escalated -- one toast.
  function withToast(view, noProject) {
    var p = noProject ? makeNoProject() : make(); if (!p) return null
    p.navigator.showSection(view)
    feed(p, [snapEntry("run-0000000000a1", "started", true, "alpha"), snapEntry("run-0000000000b2", "started", true, "beta")])
    compare(p.app.runAlerts.toasts.length, 0, "the baseline raises nothing")
    feed(p, [snapEntry("run-0000000000a1", "started", true, "alpha"), snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runAlerts.toasts.length, 1)
    wait(50)
    return p
  }

  // runs-snapshot-all.py's reply: pA's entry lists `aEntries`, pB's `bEntries`.
  function snapOkTwo(aEntries, bEntries) {
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: aEntries },
                                                 { root: tc.pB.root_path, ok: true, runs: bEntries }],
                            data_dir: "/d" }) + "\n"
  }

  // snapEntry(), in project B.
  function snapEntryB(id, runStatus, live, milestone) {
    var e = snapEntry(id, runStatus, live, milestone)
    e.repo_dir = tc.pB.root_path
    return e
  }

  // The next snapshot of projects A and B.
  function feedTwo(p, aEntries, bEntries) {
    p.app.runs.refresh()
    reply(p.app.runs.snapshotRunner.current, snapOkTwo(aEntries, bEntries), 0)
  }

  // Registers pB beside pA (pA stays open). The registry change launches a
  // snapshot that cannot run here: it is cancelled.
  function registerB(p) {
    p.app.projects.applyProjectsList([pA, pB])
    p.app.runs.snapshotRunner.cancel()
  }

  // 4.5 (11)
  function test_each_toast_names_its_project() {
    var p = withToast("board"); if (!p) return
    compare(H.find(p, "runToastProject0").text, "alpha")
    compare(H.find(p, "runToastProject0").visible, true)
    registerB(p)
    var aEntries = [snapEntry("run-0000000000a1", "started", true, "alpha"),
                    snapEntry("run-0000000000b2", "escalated", null, "beta")]
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "started", true, "zeta")])
    compare(p.app.runAlerts.toasts.length, 1, "beta's first entry only arms it")
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "escalated", null, "zeta")])
    compare(p.app.runAlerts.toasts.length, 2)
    wait(50)
    compare(H.find(p, "runToastLine1").text, "milestone …zeta escalated")
    compare(H.find(p, "runToastProject1").text, "beta")
    compare(H.find(p, "runToastProject0").text, "alpha", "the older toast keeps its project")
  }

  // 4.5 (10), a pin
  function test_the_sidebar_count_covers_every_registered_project() {
    var p = make(); if (!p) return
    registerB(p)
    p.app.runs.runs = [runIn("run-0000000000b2", "escalated", null, "beta-ms", "/home/u/a", "alpha"),
                       runIn("run-0000000000f6", "started", false, "zeta", "/home/u/b", "beta")]
    wait(50)
    var count = H.find(p, "navCountRuns")
    verify(count, "the Runs count")
    compare(String(count.text), "‼2", "alpha's escalated run and beta's dead one")
    p.app.projects.selectedProject = null
    wait(50)
    compare(p.app.runs.runs.length, 2, "closing the project leaves the runs alone")
    compare(String(count.text), "‼2", "with no project open")
    compare(count.visible, true)
  }

  // 4.5 (12), a pin
  function test_toast_open_on_another_projects_run_keeps_the_open_project() {
    var p = make(); if (!p) return
    registerB(p)
    var before = p.app.projects.selectedProject
    verify(before !== null && before.root_path === "/home/u/a", "pA is open")
    var aEntries = [snapEntry("run-0000000000a1", "started", true, "alpha")]
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "started", true, "zeta")])
    compare(p.app.runAlerts.toasts.length, 0, "the baseline raises nothing")
    feedTwo(p, aEntries, [snapEntryB("run-0000000000f6", "escalated", null, "zeta")])
    compare(p.app.runAlerts.toasts.length, 1)
    wait(50)
    compare(H.find(p, "runToastProject0").text, "beta")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f6")
    compare(p.app.runAlerts.toasts.length, 0, "Open dismisses its toast")
    verify(p.app.projects.selectedProject === before, "the same project object")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
    verify(p.app.projects.selectedProject === before)
  }

  // 26 (parent line 160: toast Open navigates)
  function test_toast_open_navigates_to_the_run_and_back_goes_to_the_runs_list() {
    var p = withToast("board"); if (!p) return
    compare(p.app.nav.viewMode, "board")
    var toast = H.find(p, "runToast0")
    verify(toast, "the toast card")
    compare(toast.visible, true)
    compare(H.find(p, "runToastLine0").text, "milestone …beta escalated")
    var kc = H.find(p, "keyCatcher")
    var pt = toast.mapToItem(kc, 0, 0)
    verify(pt.x + toast.width <= kc.width && pt.x + toast.width >= kc.width - 40, "against the right edge")
    verify(pt.y + toast.height <= kc.height && pt.y + toast.height >= kc.height - 40, "against the bottom edge")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.runAlerts.toasts.length, 0, "Open dismisses its toast")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
    compare(p.opened, true)
  }

  // 27 (Review focus: the search field's Escape does not go through closeRequested)
  function test_escape_in_the_empty_runs_search_dismisses_the_toast_and_keeps_the_panel_open() {
    var p = withToast("runs"); if (!p) return
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    compare(field.text, "")
    keyClick(Qt.Key_Escape)
    compare(p.app.runAlerts.toasts.length, 0)
    compare(p.opened, true, "the panel stays open")
    compare(p.app.nav.viewMode, "runs")
  }

  // 28
  function test_dismiss_removes_only_that_toast() {
    var p = withToast("runs"); if (!p) return
    feed(p, [snapEntry("run-0000000000a1", "started", false, "alpha"), snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runAlerts.toasts.length, 2)
    wait(50)
    mouseClick(H.find(p, "runToastDismiss0"))
    compare(p.app.runAlerts.toasts.length, 1)
    compare(p.app.runAlerts.toasts[0].id, "run-0000000000a1")
    wait(50)
    compare(H.find(p, "runToastLine0").text, "milestone …alpha died")
  }

  // 29
  function test_with_the_setting_on_an_escalation_also_notifies() {
    var p = make(); if (!p) return
    compare(p.app.runControl.setNotifyOnEscalation(true), true)
    reply(p.app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(p.app.runControl.notifySaved, true)
    feed(p, [snapEntry("run-0000000000b2", "started", true, "beta")])
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runAlerts.notifyRunners.length, 1)
    var cmd = p.app.runAlerts.notifyRunners[0].current.command
    compare(cmd[1], p.pluginDir + "core/backend/runs/notify.py")
    compare(cmd[cmd.length - 2], "milestone …beta")
    compare(cmd[cmd.length - 1], "escalated")
    p.app.runControl.setNotifyOnEscalation(false)
    reply(p.app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta"), snapEntry("run-0000000000c3", "escalated", null, "gamma")])
    compare(p.app.runAlerts.toasts.length, 2)
    compare(p.app.runAlerts.notifyRunners.length, 1, "off: no new launch")
  }

  // 30
  function test_open_on_a_toast_whose_run_left_the_snapshot_flashes_why() {
    var p = withToast("board"); if (!p) return
    feed(p, [snapEntry("run-0000000000a1", "started", true, "alpha")])
    compare(p.app.runAlerts.toasts.length, 1, "the toast outlives its run's row")
    wait(50)
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.runAlerts.toasts.length, 0)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.selectedRunId, "")
    compare(H.find(p, "runsFooter").text, "This run is no longer in the snapshot")
  }

  // ---- no project (4.1)

  // F1
  function test_with_no_project_ctrl_6_opens_runs_with_search_and_no_placeholder() {
    var p = makeNoProject(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    compare(p.app.nav.viewMode, "runs")
    compare(labels(p.navigator.crumbs), "Runs")
    compare(p.navigator.crumbs[0].clickable, false)
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    var field = H.find(p, "searchField")
    compare(field.visible, true)
    compare(String(field.placeholderText), "Search runs…")
    compare(p.focusItem.objectName, "searchField")
    compare(H.find(p, "noProjectsText").visible, false)
    compare(p.navigator.currentList().length, 4, "currentList() is the run list")
  }

  // F2 (and Review Focus 1, 5)
  function test_with_no_project_a_run_opens_and_back_returns() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    var id = p.navigator.currentList()[1].id
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, id)
    compare(labels(p.navigator.crumbs), "Runs > " + Runs.shortId({ id: id }))
    compare(p.navigator.crumbs[0].clickable, true)
    compare(p.navigator.crumbs[1].clickable, false)
    wait(50)
    compare(H.find(p, "runDetailView").visible, true)
    compare(H.find(p, "searchField").visible, false)
    compare(H.find(p, "noProjectsText").visible, false)
    compare(p.focusItem.objectName, "keyCatcher")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.cursorIndex, 1, "back on the row it left")
    compare(p.app.runs.selectedRunId, "")
    p.navigator.openRun(id, "runs")
    p.shortcuts.handleMove(-1, 0)
    compare(p.app.nav.viewMode, "runs", "the Left arrow goes back")
    p.navigator.openRun(id, "runs")
    p.navigator.activateCrumb(0)
    compare(p.app.nav.viewMode, "runs", "the Runs crumb goes back")
  }

  // F3
  function test_with_no_project_the_search_filters_runs() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    compare(p.navigator.currentList().length, 4)
    var field = H.find(p, "searchField")
    p.app.nav.cursorIndex = 2
    field.text = "gamma"
    compare(ids(p.navigator.currentList()), "run-0000000000c3")
    compare(p.app.nav.cursorIndex, 0, "typing resets the cursor")
    field.text = ""
    compare(p.navigator.currentList().length, 4)
  }

  // F4
  function test_with_no_project_toast_open_shows_the_run() {
    var p = withToast("board", true); if (!p) return
    compare(p.app.projects.selectedProject, null)
    compare(p.app.nav.viewMode, "board")
    compare(H.find(p, "runToastProject0").text, "alpha")
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000b2")
    compare(p.app.runAlerts.toasts.length, 0, "Open dismisses its toast")
    compare(p.app.projects.selectedProject, null, "Open opens no project")
    wait(50)
    compare(H.find(p, "runDetailView").visible, true)
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    // alpha dies, then leaves the snapshot: its toast outlives its row.
    feed(p, [snapEntry("run-0000000000a1", "started", false, "alpha"), snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runAlerts.toasts.length, 1)
    feed(p, [snapEntry("run-0000000000b2", "escalated", null, "beta")])
    compare(p.app.runAlerts.toasts.length, 1)
    p.app.nav.viewMode = "board"
    wait(50)
    mouseClick(H.find(p, "runToastOpen0"))
    compare(p.app.runAlerts.toasts.length, 0)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.selectedRunId, "")
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    compare(H.find(p, "runsFooter").text, "This run is no longer in the snapshot")
  }

  // F5
  function test_with_no_project_the_notify_switch_shows_and_toggles() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    compare(H.find(p, "runsNotifyRow").visible, true)
    var was = p.app.runControl.notifyOnEscalation
    H.find(p, "runsNotifyToggle").toggled()
    compare(p.app.runControl.notifyOnEscalation, !was)
    compare(p.app.runControl.settingsSaveRunner.sent, !was, "the set-global-settings request carries the new value")
    reply(p.app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
  }

  // F8
  function test_with_no_project_the_bound_sections_stay_shut() {
    var p = makeNoProject(); if (!p) return
    wait(50)
    compare(p.app.nav.viewMode, "board")
    compare(H.find(p, "noProjectsText").visible, true)
    compare(H.find(p, "searchField").visible, false)
    compare(p.focusItem.objectName, "keyCatcher")
    compare(labels(p.navigator.crumbs), "Project Manager")
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    compare(p.app.nav.viewMode, "runs")
    var digits = [Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_5]
    for (var i = 0; i < digits.length; i++) {
      compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: digits[i] }), true)
      compare(p.app.nav.viewMode, "runs", "Ctrl+" + (i + 1))
    }
  }

  // Review Focus 4: App's `selected` handler still opens the Board.
  function test_with_no_project_choosing_a_project_on_a_run_opens_the_board() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000a1", "runs")
    compare(p.app.nav.viewMode, "run")
    p.navigator.chooseProject(tc.pA)
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.runControl.settingsLoadRunner.cancel()
    p.app.runControl.runSettingsLoadRunner.cancel()
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    compare(p.app.nav.viewMode, "board")
    compare(labels(p.navigator.crumbs), "Board")
    wait(50)
    compare(H.find(p, "startRunButton").visible, false)
    compare(H.find(p, "noProjectsText").visible, false)
  }

  // F6
  function test_start_run_without_a_project_is_disabled_with_why() {
    var p = makeNoProject(); if (!p) return
    p.navigator.showSection("runs")
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch")
    mouseClick(button)
    compare(p.dispatchOpen, false, "a click opens nothing")
    compare(p.app.runDispatch.dispatchState, "idle")
    p.app.runs.amStatus = "missing"
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch", "no project wins over am missing")
  }

  // ---- Open project (4.4)

  // make() with pA and pB registered and pA open; filteredRuns is alpha's
  // run-0000000000b2 and run-0000000000c3, then beta's run-0000000000f6.
  function makeTwo() {
    var p = make(); if (!p) return null
    p.app.projects.applyProjectsList([pA, pB])
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [runIn("run-0000000000f6", "started", true, "zeta", "/home/u/b", "beta"),
                       runIn("run-0000000000b2", "escalated", null, "beta-ms", "/home/u/a", "alpha"),
                       runIn("run-0000000000c3", "started", false, "gamma", "/home/u/a", "alpha")]
    return p
  }

  // A project switch starts a `brd export` and two run-settings reads that
  // cannot run here: all are disarmed so their late replies change nothing.
  function disarmSwitch(p) {
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.runControl.settingsLoadRunner.cancel()
    p.app.runControl.runSettingsLoadRunner.cancel()
  }

  function ctrl6(p) {
    p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 })
    wait(50)
  }

  // Ctrl+6, then the cursor down to beta's run (index 2).
  function runsOnBeta(p) {
    ctrl6(p)
    compare(ids(p.app.runs.filteredRuns), "run-0000000000b2,run-0000000000c3,run-0000000000f6")
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 2)
  }

  // 10
  function test_open_project_on_another_projects_run_opens_its_board_and_ctrl_6_returns() {
    var p = makeTwo(); if (!p) return
    runsOnBeta(p)
    var button = H.find(p, "runRowOpenProject2")
    verify(button, "beta's row has Open project")
    compare(button.visible, true)
    wait(450)
    mouseClick(button)
    disarmSwitch(p)
    compare(p.app.projects.selectedProject.root_path, "/home/u/b")
    compare(p.app.nav.viewMode, "board")
    compare(labels(p.navigator.crumbs), "Board")
    ctrl6(p)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.project, "/home/u/b")
    compare(p.app.nav.cursorIndex, 0)
    compare(H.find(p, "runRowOpenProject0").visible, true, "alpha is no longer the open project")
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    p.shortcuts.handleSearchKey(key(Qt.Key_Down))
    compare(p.app.nav.cursorIndex, 2)
    compare(H.find(p, "runRowOpenProject2").visible, false, "beta is the open project now")
  }

  // 11: a pin — Run detail never switched the project, so this passes before
  // the button has a click handler.
  function test_run_detail_of_another_projects_run_keeps_the_open_project() {
    var p = makeTwo(); if (!p) return
    var open = p.app.projects.selectedProject
    runsOnBeta(p)
    p.shortcuts.handleSearchKey(key(Qt.Key_Return))
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-0000000000f6")
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    verify(p.app.projects.selectedProject === open, "the same project object")
  }

  // Review Focus 1.
  function test_open_project_with_a_dirty_memory_draft_stays_on_runs() {
    var p = makeTwo(); if (!p) return
    runsOnBeta(p)
    p.app.memories.memoryEditing = true
    p.app.memories.memoryText = "saved"
    p.app.memories.memoryDraft = "edited"
    var button = H.find(p, "runRowOpenProject2")
    verify(button, "beta's row has Open project")
    wait(450)
    mouseClick(button)
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    compare(p.app.nav.viewMode, "runs")
    verify(p.app.memories.memoryOpError.indexOf("unsaved changes") >= 0, p.app.memories.memoryOpError)
  }
}
