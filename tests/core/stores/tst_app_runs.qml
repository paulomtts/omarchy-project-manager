// tests/core/stores/tst_app_runs.qml
// App's composition of the run monitor's store: `app.runs` exists, and its
// inputs come from App -- the backend dir, the registry's roots and names,
// the selected project's ROOT PATH (never the project object), and App's
// panel-open flag -- and the couplings between the run monitor's concerns,
// driven through App, including `app.runAlerts`, which App feeds with the run
// store's snapshotReplied, and `app.runControl`, whose requests App settles on
// each ok snapshotReplied and whose refreshRequested App routes to the run
// store, and `app.runDispatch`, which App feeds with the run store's project
// and run list and run control's run settings, and whose refreshRequested,
// noticeRequested, runSettingsWanted and runSettingsSaveRequested App routes,
// as it routes run control's runSettingsSaveFailed back to the dispatch. The
// stores' own behaviour is tested in
// tst_run_store.qml, tst_run_alerts_store.qml, tst_run_control_store.qml and
// tst_run_dispatch_store.qml.
import QtQuick
import QtTest
import "../../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "StoresAppRuns"

  Component { id: spyC; SignalSpy {} }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  // App with no project selected yet: applyProjectsList auto-selects the first
  // project once the stored state is loaded, so that is a separate step.
  function makeBare() {
    var comp = Qt.createComponent("../../../core/stores/App.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // App with pA auto-selected.
  function make() {
    var app = makeBare(); if (!app) return null
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    return app
  }

  // runs-snapshot-all.py's reply: pA's entry lists runs `ids`.
  function okReply(ids) {
    var runs = ids.map(function(id) {
      return { id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
               status: { run: { id: id, milestone_id: "m-" + id, status: "done" }, rows: [], stories: [], subtasks: [],
                         control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: false } } } }
    })
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: runs }],
                            data_dir: "/home/u/.local/share" }) + "\n"
  }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // One snapshot entry: run `id` of `root` with am status `runStatus`, its
  // lease live or not, and its am control requests ([] when omitted).
  function runEntry(id, runStatus, live, root, requests) {
    return { id: id, workflow: "milestone", repo_dir: root, started_at: "2026-10-01T00:00:00Z",
             status: { run: { id: id, milestone_id: "m-" + id, status: runStatus }, rows: [], stories: [], subtasks: [],
                       control: { requests: requests || [],
                                  lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } } } }
  }

  // A running run of `root` (pA when omitted).
  function runningIn(id, root) { return runEntry(id, "started", true, root || tc.pA.root_path) }

  // An escalated run of `root` (pA when omitted).
  function escalatedIn(id, root) { return runEntry(id, "escalated", false, root || tc.pA.root_path) }

  // runs-snapshot-all.py's reply: pA's entry lists aRuns, pB's lists bRuns; no pB entry when bRuns is null.
  function listReply(aRuns, bRuns) {
    var projects = [{ root: tc.pA.root_path, ok: true, runs: aRuns }]
    if (bRuns !== null) projects.push({ root: tc.pB.root_path, ok: true, runs: bRuns })
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // runs-snapshot-all.py's reply where both roots' entries are AmMissing.
  function missingReply() {
    var error = { type: "AmMissing", message: "am is not installed." }
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: false, error: error },
                                                 { root: tc.pB.root_path, ok: false, error: error }],
                            data_dir: "/home/u/.local/share" }) + "\n"
  }

  // The next snapshot of every root, answered with `text`.
  function snapshot(app, text) {
    app.runs.refresh()
    reply(app.runs.snapshotRunner.current, text, 0)
  }

  // make() with the panel open and both snapshots answered with aRuns and
  // bRuns: make()'s, then the one the opening queued behind it. Armed, nothing raised.
  function openApp(aRuns, bRuns) {
    var app = make(); if (!app) return null
    app.panelOpen = true
    var text = listReply(aRuns, bRuns)
    reply(app.runs.snapshotRunner.current, text, 0)
    verify(app.runs.snapshotRunner.busy, "the opening queued a snapshot behind make()'s")
    reply(app.runs.snapshotRunner.current, text, 0)
    compare(app.runs.snapshotRunner.busy, false)
    return app
  }

  // run-control.py's ok reply.
  function ctlOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // The argv of a snapshot of both registered roots.
  property string snapAll: "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj|/home/u/b"

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // run-control.py's refusal.
  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  // The argv prefix of a viewer-state.py command.
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // The --defaults reply: the default branch `branch`, read from origin/HEAD.
  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  // The dry-run preview's ok reply carrying `data`.
  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  // The dispatch start's ok reply: run `runId` started, with `message`.
  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // make() with pA's run settings read, make()'s snapshot answered with no
  // runs, and milestone m1's dispatch ready: its default branch read and its preview landed.
  function readyApp() {
    var app = make(); if (!app) return null
    reply(app.runControl.runSettingsLoadRunner.current, dispatchSettings(), 0)
    reply(app.runs.snapshotRunner.current, listReply([], []), 0)
    var cards = dispatchCards()
    compare(app.runDispatch.openDispatch(cards.m1, cards), true)
    reply(app.runDispatch.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(app.runDispatch.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(app.runDispatch.dispatchState, "ready")
    return app
  }

  // run control's newest run settings save in flight; null when none.
  function saveOf(app) {
    var saves = app.runControl.runSettingsRunners.filter(function(r) { return r.saving })
    return saves.length > 0 ? saves[saves.length - 1] : null
  }

  // The argv prefix of a notify.py command.
  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"

  function test_app_composes_a_run_store_with_no_project_and_closed() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "App composes the run store as app.runs")
    verify(app.runs.snapshotRunner, "it is a RunStore")
    compare(app.projects.selectedProject, null)
    compare(app.runs.backendDir, app.backendDir)
    compare(app.runs.backendDir, "/plugin/core/backend/")
    compare(app.runs.project, "", "a null selectedProject becomes an empty root path")
    compare(app.panelOpen, false)
    compare(app.runs.active, false)
    verify(!app.runs.snapshotRunner.current, "no snapshot without a registered project")
    compare(app.runs.watching, false)
  }

  function test_the_backend_dir_follows_app() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.backendDir = "/other/core/backend/"
    compare(app.runs.backendDir, "/other/core/backend/")
  }

  function test_the_project_is_the_selected_root_path_string() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    compare(app.projects.selectedProject.root_path, pA.root_path, "pA was auto-selected")
    compare(typeof app.runs.project, "string")
    compare(app.runs.project, "/home/u/my proj")
    app.projects.chooseProject(pB)
    compare(app.runs.project, "/home/u/b")
  }

  // 13
  function test_project_roots_follow_the_registry() {
    var app = make(); if (!app) return
    compare(JSON.stringify(app.runs.projectRoots),
            JSON.stringify([{ root: tc.pA.root_path, name: "alpha" }, { root: tc.pB.root_path, name: "beta" }]))
    var spy = createTemporaryObject(spyC, tc, { target: app.runs, signalName: "projectRootsChanged" })
    app.projects.chooseProject(pB)
    compare(app.runs.project, "/home/u/b")
    compare(spy.count, 0, "selecting a project does not change it")
    app.projects.clearSelection()
    compare(spy.count, 0, "nor does clearing the selection")
    app.projects.applyProjectsList([pB])
    compare(JSON.stringify(app.runs.projectRoots), JSON.stringify([{ root: tc.pB.root_path, name: "beta" }]),
            "a new list replaces it")
  }

  // 14
  function test_the_snapshot_names_every_registered_root() {
    var app = make(); if (!app) return
    var proc = app.runs.snapshotRunner.current
    verify(proc, "the registry starts a snapshot")
    compare(proc.command.join("|"), "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj|/home/u/b")
    compare(proc.launchGuard, "", "the snapshot has no guard")
  }

  // 14
  function test_clearing_the_selection_keeps_the_runs() {
    var app = make(); if (!app) return
    var proc = app.runs.snapshotRunner.current
    proc.outText = okReply(["r1"])
    proc.exited(0)
    compare(app.runs.runs.length, 1)
    app.projects.clearSelection()
    compare(app.runs.project, "")
    compare(app.runs.runs.length, 1, "the run list is every registered project's")
  }

  function test_active_follows_panel_open() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.panelOpen = true
    compare(app.runs.active, true)
    app.panelOpen = false
    compare(app.runs.active, false)
  }

  function test_opening_with_no_project_launches_nothing() {
    var app = makeBare(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.panelOpen = true
    compare(app.runs.active, true)
    verify(!app.runs.snapshotRunner.current, "no snapshot without a registered project")
    compare(app.runs.watching, false)
  }

  function test_panel_close_through_app_stops_the_watch() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    app.panelOpen = true
    var proc = app.runs.snapshotRunner.current
    proc.outText = okReply(["r1"])
    proc.exited(0)
    compare(app.runs.watching, true, "the first good snapshot while open starts the watch")
    var watch = app.runs.watchProc
    verify(watch, "a watch process")
    app.panelOpen = false
    compare(app.runs.watching, false)
    compare(watch.running, false, "closing the panel stops the watch")
  }

  // ---- the Runs screen's search and filter (5.1)

  function test_the_search_query_follows_the_navigation_store() {
    var app = makeBare(); if (!app) return
    app.nav.searchQuery = "gamma"
    compare(app.runs.searchQuery, "gamma")
    app.nav.searchQuery = ""
    compare(app.runs.searchQuery, "")
  }

  function test_a_filter_change_puts_the_cursor_home() {
    var app = makeBare(); if (!app) return
    app.nav.cursorIndex = 3
    app.nav.scrollOnCursor = true
    app.runs.toggleRunFilter("live")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
  }

  // ---- the project filter (3.3)

  // 11
  function test_a_project_filter_toggle_puts_the_cursor_home() {
    var app = makeBare(); if (!app) return
    app.nav.cursorIndex = 3
    app.nav.scrollOnCursor = true
    app.runs.toggleProjectFilter("")
    compare(app.nav.cursorIndex, 0)
    compare(app.nav.scrollOnCursor, false)
  }

  // ---- couplings between the run monitor's concerns, through App

  function test_a_snapshot_through_app_settles_a_pending_request() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    compare(app.runControl.pending.r1, "pause")
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runControl.pending.r1, "pause", "am has it; a snapshot settles it")
    reply(app.runs.snapshotRunner.current,
          listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: null }])], []), 0)
    compare(app.runControl.pending.r1, "pause", "not handled yet")
    snapshot(app, listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])], []))
    compare(app.runControl.pending.r1, undefined, "the handled request is settled")
  }

  function test_a_snapshot_through_app_raises_one_toast_after_arming() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runAlerts.toasts.length, 0, "the first snapshots only arm")
    compare(app.runAlerts.alertsArmed, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runAlerts.toasts[0].id, "r1")
  }

  function test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runAlerts.alertsArmed, true)
    snapshot(app, missingReply())
    compare(app.runs.amStatus, "missing")
    compare(app.runAlerts.alertsArmed, false)
    compare(app.runs.runs.length, 0)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 0, "the first good snapshot after am came back only arms")
    compare(app.runAlerts.alertsArmed, true)
  }

  function test_a_control_reply_through_app_snapshots_every_registered_root() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root, not only the run's")
  }

  function test_a_failed_control_reply_through_app_also_snapshots_every_root() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runControl.controlRunners[0].current, ctlFail("NotAcceptingError", "run r1 is in integrate"), 0)
    compare(app.runControl.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(app.runControl.pending.r1, undefined)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll)
  }

  function test_a_dispatch_start_through_app_snapshots_its_root_only() {
    var app = readyApp(); if (!app) return
    var spy = createTemporaryObject(spyC, tc, { target: app.runDispatch, signalName: "dispatchStarted" })
    compare(app.runDispatch.dispatchStart(), true)
    var runner = app.runDispatch.dispatchStartRunners[0]
    var seq = app.runs.snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runDispatch.dispatchState, "started")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/my proj",
            "of the dispatch's root only")
    var save = saveOf(app).current
    compare(save.command.length, 5)
    compare(save.command.slice(0, 4).join("|"), tc.viewerCmd + "set-run-settings|/home/u/my proj")
  }

  function test_a_dispatch_settings_save_failure_through_app_flashes() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    var runner = app.runDispatch.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runControl.flashText, "")
    reply(saveOf(app).current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "Dispatch settings could not be saved")
    compare(app.runDispatch.dispatchState, "started", "the run still started")
    compare(app.runDispatch.dispatchStartRunners.length, 0)
  }

  // App routes run control's runSettingsLoaded to the dispatch: an opening
  // for another root reads that root's run settings through run control, and
  // its reply fills the form.
  function test_a_dispatch_for_another_root_reads_its_settings_through_run_control() {
    var app = make(); if (!app) return
    reply(app.runControl.runSettingsLoadRunner.current, dispatchSettings(), 0)
    verify(app.runDispatch.projectRoots === app.runs.projectRoots, "the run store's registry")
    var cards = dispatchCards()
    app.runDispatch.dispatchRoot = tc.pB.root_path
    compare(app.runDispatch.dispatchOpenFor(cards.m1, cards), true)
    var read = app.runControl.runSettingsLoadRunner
    verify(read, "run control reads B's run settings")
    compare(argv(read.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(read.current, JSON.stringify({ verify: ["make test"], parallelism: 2, prefixHistory: ["bpre"] }) + "\n", 0)
    compare(app.runDispatch.dispatchRunSettings.prefixHistory[0], "bpre")
    compare(app.runDispatch.dispatchForm.verify.join(","), "make test")
    compare(app.runControl.runSettingsOf(tc.pB.root_path).parallelism, 2, "run control keeps B's settings")
    compare(app.runDispatch.runSettings.parallelism, 4, "the open project's are untouched")
  }

  function test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    reply(app.runControl.runSettingsLoadRunner.current, dispatchSettings(), 0)
    compare(app.runControl.runSettingsOf(app.runs.project).parallelism, 4)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runControl.control("pause", "r2"), true)
    app.runControl.flash("kept")
    var cards = dispatchCards()
    compare(app.runDispatch.openDispatch(cards.m1, cards), true)
    reply(app.runDispatch.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(app.runDispatch.dispatchState, "previewing")
    var seq = app.runs.snapshotRunner.seq
    app.projects.chooseProject(pB)
    compare(app.runDispatch.dispatchState, "idle")
    compare(Object.keys(app.runControl.runSettingsOf(app.runs.project)).length, 0)
    compare(argv(app.runControl.runSettingsLoadRunner.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(app.runAlerts.toasts.length, 1, "the toast stays")
    compare(app.runAlerts.toasts[0].id, "r1")
    compare(app.runControl.pending.r2, "pause", "the request stays")
    compare(app.runControl.flashText, "kept", "the flash stays")
    compare(app.runs.snapshotRunner.seq, seq, "no snapshot is launched")
  }

  function test_opening_the_panel_through_app_reads_the_notify_switch() {
    var app = make(); if (!app) return
    verify(!app.runControl.settingsLoadRunner.current, "a closed panel reads nothing")
    app.runControl.setNotifyOnEscalation(false)
    compare(app.runControl.notifyTouched, true)
    reply(app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    app.panelOpen = true
    compare(argv(app.runControl.settingsLoadRunner.current), tc.viewerCmd + "get-global-settings")
    compare(app.runControl.notifyTouched, false, "the opening's load is not too late")
    reply(app.runControl.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
  }

  function test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    var cards = dispatchCards()
    compare(app.runDispatch.openDispatch(cards.m1, cards), true)
    compare(app.runDispatch.dispatchState, "previewing")
    app.panelOpen = false
    compare(app.runAlerts.toasts.length, 0)
    compare(app.runAlerts.alertsArmed, false)
    compare(app.runDispatch.dispatchState, "idle")
  }

  function test_an_escalation_through_app_notifies_only_with_the_switch_on() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    compare(app.runControl.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runAlerts.notifyRunners.length, 0, "the switch is off: a toast only")
    reply(app.runControl.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runAlerts.toasts.length, 2)
    compare(app.runAlerts.notifyRunners.length, 1, "one notification, for r2")
    compare(argv(app.runAlerts.notifyRunners[0].current), tc.notifyCmd + "m-r2|escalated")
  }

  function test_a_project_leaving_the_registry_through_app_loses_its_arming() {
    var app = openApp([runningIn("a1")], [runningIn("b1", tc.pB.root_path)]); if (!app) return
    compare(Object.keys(app.runAlerts.armedRoots).sort().join(","), [tc.pA.root_path, tc.pB.root_path].sort().join(","))
    app.projects.applyProjectsList([pA])
    compare(Object.keys(app.runAlerts.armedRoots).join(","), tc.pA.root_path, "pB's arming goes with it")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("a1")], null), 0)
    app.projects.applyProjectsList([pA, pB])
    reply(app.runs.snapshotRunner.current, listReply([escalatedIn("a1")], [escalatedIn("b1", tc.pB.root_path)]), 0)
    compare(app.runAlerts.toasts.length, 1, "pB's first entry back only re-arms it")
    compare(app.runAlerts.toasts[0].id, "a1", "pA stayed armed")
    compare(Object.keys(app.runAlerts.armedRoots).length, 2)
  }

  // ---- the run store keeps none of the moved members (split-runstore 5.2)

  // The members that moved out of the run store, by the store that owns them,
  // in the order of MOVED in tests/architecture/test_run_store_callers.py.
  // runSettings and runSettingsRunner have other names on run control.
  property var movedToControl: ["pending", "stillWaiting", "stillWaitingText", "lastControlError",
    "lastControlErrorRunId", "cancelRunId", "cancelOpen", "cancelText", "cancelError", "flashText",
    "controlRunners", "pendingTimer", "flashTimer", "notifyOnEscalation", "notifySaved", "notifyTouched",
    "settingsLoadRunner", "settingsSaveRunner", "control", "refusalOf", "flash", "openCancel", "closeCancel",
    "confirmCancel", "setNotifyOnEscalation", "lastControlErrorType", "resumeRunId", "resumeVerify",
    "resumeAllowNoVerification", "resumeError", "resumeOpenFor", "resumeClose", "resumeConfirm", "resumeSaveRunner"]
  property var renamedOnControl: ["runSettings", "runSettingsRunner"]
  property var movedToAlerts: ["armedRoots", "alertsArmed", "toasts", "toastMs", "toastTimer", "notifyRunners",
    "raiseAlerts", "expireToasts", "dismissToast", "dismissAllToasts", "notify"]
  property var movedToDispatch: ["dispatchState", "dispatchTarget", "dispatchTargetLabel", "dispatchForm",
    "dispatchPreview", "dispatchError", "dispatchErrorType", "dispatchErrors", "dispatchSuggest", "dispatchRunId",
    "dispatchMessage", "dispatchLog", "dispatchLogTail", "dispatchExitCode", "dispatchDefaultsRunner",
    "dispatchPreviewRunner", "dispatchDebounceTimer", "dispatchStartRunners", "dispatchStarted", "openDispatch",
    "closeDispatch", "retargetToMilestone", "setDispatchField", "dispatchStart", "checkDispatch", "dispatchRoot",
    "dispatchRunSettings", "dispatchOpenFor", "dispatchStep", "dispatchProjectProbe", "dispatchProjectRows",
    "dispatchProjectRunner", "dispatchTargetCardMap", "dispatchTargetRows", "dispatchTargetLoading",
    "dispatchTargetKey", "dispatchTargetRunner", "dispatchProjectFailures", "dispatchOpenFromRuns",
    "dispatchProjectPick", "dispatchTargetPick", "dispatchBack", "relaunchOpenFor"]
  // The handles the run store once read the moved members through.
  property var runStoreHandles: ["controlStore", "alertsStore", "dispatchStore"]

  // The names of `names` that `obj` answers to (present) or does not (absent).
  function answered(obj, names, present) {
    return names.filter(function(name) { return (typeof obj[name] !== "undefined") === present })
  }

  function test_the_run_store_has_none_of_the_moved_members() {
    var app = makeBare(); if (!app) return
    var names = tc.movedToControl.concat(tc.renamedOnControl, tc.movedToAlerts, tc.movedToDispatch, tc.runStoreHandles)
    compare(names.length, 93, "90 moved members and 3 handles")
    compare(answered(app.runs, names, true).join(", "), "", "the run store still answers to these")
    compare(answered(app.runs, ["runs", "project", "refresh", "requestSnapshot", "snapshotReplied", "runsChanged"],
                     false).join(", "), "", "members that stay are still there")
  }

  function test_each_owner_answers_to_its_moved_members() {
    var app = makeBare(); if (!app) return
    compare(answered(app.runControl, tc.movedToControl, false).join(", "), "", "run control lacks these")
    compare(answered(app.runControl, ["runSettingsLoadRunner", "runSettingsOf", "applyRunSettings"], false).join(", "), "",
            "run control lacks the renamed run settings members")
    compare(answered(app.runAlerts, tc.movedToAlerts, false).join(", "), "", "the alerts lack these")
    compare(answered(app.runDispatch, tc.movedToDispatch, false).join(", "), "", "the dispatch lacks these")
  }

  // ---- app.runAlerts (split-runstore 2.2)

  // A1
  function test_app_composes_run_alerts_wired_to_the_run_store() {
    var app = makeBare(); if (!app) return
    verify(app.runAlerts, "App composes the alerts store")
    compare(app.runAlerts.backendDir, "/plugin/core/backend/")
    app.backendDir = "/other/"
    compare(app.runAlerts.backendDir, "/other/", "backendDir follows App")
    compare(app.runAlerts.active, false)
    app.panelOpen = true
    compare(app.runAlerts.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runAlerts.active, false)
    compare(app.runAlerts.notifyOnEscalation, false)
    app.runControl.setNotifyOnEscalation(true)
    compare(app.runAlerts.notifyOnEscalation, true, "the switch follows run control's")
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    compare(app.runAlerts.projectRoots.length, 2)
    verify(app.runAlerts.projectRoots === app.runs.projectRoots, "the run store's registry")
  }

  // A2
  function test_a_snapshot_through_app_toasts_on_run_alerts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runAlerts.toasts.length, 0, "the first snapshots only arm")
    compare(app.runAlerts.alertsArmed, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runAlerts.toasts[0].id, "r1")
    compare(app.runAlerts.toasts[0].project, "alpha")
  }

  // A3
  function test_am_missing_through_app_disarms_run_alerts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runAlerts.alertsArmed, true)
    snapshot(app, missingReply())
    compare(app.runAlerts.alertsArmed, false)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 0, "the first good snapshot after am came back only arms")
    compare(app.runAlerts.alertsArmed, true)
  }

  // A4
  function test_closing_the_panel_through_app_empties_run_alerts() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    app.panelOpen = false
    compare(app.runAlerts.toasts.length, 0)
    compare(app.runAlerts.alertsArmed, false)
  }

  // ---- app.runControl (split-runstore 3.1)

  // A1
  function test_app_composes_run_control_wired_to_the_run_store() {
    var app = makeBare(); if (!app) return
    verify(app.runControl, "App composes the control store")
    compare(app.runControl.backendDir, "/plugin/core/backend/")
    app.backendDir = "/other/"
    compare(app.runControl.backendDir, "/other/", "backendDir follows App")
    compare(app.runControl.active, false)
    app.panelOpen = true
    compare(app.runControl.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runControl.active, false)
    compare(app.runControl.project, "", "no project selected yet")
    app.projects.applyStoredState('{"last_project": null}', 0)
    app.projects.applyProjectsList([pA, pB])
    compare(app.runControl.project, pA.root_path, "the selected project's root path")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("r1")], []), 0)
    compare(app.runControl.runs.length, 1)
    verify(app.runControl.runs === app.runs.runs, "the run store's merged list")
    app.projects.chooseProject(pB)
    compare(app.runControl.project, "/home/u/b", "the project follows the selection")
  }

  // A2
  function test_a_snapshot_through_app_settles_on_run_control() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    compare(app.runControl.pending.r1, "pause")
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runControl.controlRunners.length, 0)
    compare(app.runControl.pending.r1, "pause", "am has it; a snapshot settles it")
    reply(app.runs.snapshotRunner.current,
          listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: null }])], []), 0)
    compare(app.runControl.pending.r1, "pause", "not handled yet")
    snapshot(app, listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])], []))
    compare(app.runControl.pending.r1, undefined, "the handled request is settled")
  }

  // A3
  function test_a_control_reply_through_app_snapshots_every_root_from_run_control() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root")
  }

  // A4
  function test_a_refresh_request_for_some_roots_snapshots_only_those() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.snapshotRunner.busy, false)
    var seq = app.runs.snapshotRunner.seq
    app.runControl.refreshRequested([tc.pB.root_path])
    compare(app.runs.snapshotRunner.seq, seq + 1)
    compare(argv(app.runs.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot-all.py|/home/u/b", "pB alone")
  }

  // A5
  function test_only_an_ok_snapshot_through_app_settles() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    var fail = { type: "AmFailed", message: "boom" }
    reply(app.runs.snapshotRunner.current,
          JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: false, error: fail },
                                                { root: tc.pB.root_path, ok: false, error: fail }],
                           data_dir: "/home/u/.local/share" }) + "\n", 0)
    compare(app.runs.amStatus, "error")
    compare(app.runControl.pending.r1, "pause", "a failed reply settles nothing")
    snapshot(app, missingReply())
    compare(app.runs.amStatus, "missing")
    compare(app.runControl.pending.r1, "pause", "an AmMissing reply settles nothing")
    snapshot(app, listReply([], []))
    compare(app.runControl.pending.r1, undefined, "the next ok reply shows the run gone and settles it")
  }

  // A6 (Review Focus: the "all" route)
  function test_a_control_reply_with_no_project_registered_launches_no_snapshot() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runControl.control("pause", "r1"), true)
    app.projects.applyProjectsList([])
    compare(app.runs.runs.length, 0, "the emptied registry emptied the lists")
    var seq = app.runs.snapshotRunner.seq
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runControl.controlRunners.length, 0)
    compare(app.runs.snapshotRunner.seq, seq, "refresh() with no usable root launches nothing")
    compare(app.runs.runs.length, 0)
  }

  // A7 (Review Focus: a failed root before an ok root)
  function test_a_reply_with_a_failed_root_before_an_ok_root_settles() {
    var app = openApp([runningIn("r1")], [runningIn("b1", tc.pB.root_path)]); if (!app) return
    compare(app.runControl.control("pause", "b1"), true)
    reply(app.runControl.controlRunners[0].current, ctlOk({ run_id: "b1", command: "pause", requested_at: "t1" }), 0)
    var handled = runEntry("b1", "started", true, tc.pB.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])
    reply(app.runs.snapshotRunner.current,
          JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: false, error: { type: "AmFailed", message: "boom" } },
                                                { root: tc.pB.root_path, ok: true, runs: [handled] }],
                           data_dir: "/home/u/.local/share" }) + "\n", 0)
    compare(app.runs.amStatus, "ok")
    compare(app.runControl.pending.b1, undefined, "settled on pB's ok emission")
  }

  // ---- the notify switch on app.runControl (split-runstore 3.2)

  // A8
  function test_the_alerts_switch_is_run_controls() {
    var app = makeBare(); if (!app) return
    app.panelOpen = true
    var load = app.runControl.settingsLoadRunner.current
    verify(load, "the opening loads the switch on run control")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runControl.notifyOnEscalation, true)
    compare(app.runAlerts.notifyOnEscalation, true, "the alerts input follows run control's")
    compare(app.runControl.notifyOnEscalation, true)
  }

  // A9
  function test_with_run_controls_switch_on_an_escalation_launches_notify() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    reply(app.runControl.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runAlerts.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runAlerts.toasts.length, 1)
    compare(app.runAlerts.notifyRunners.length, 1, "the switch is on: a notification")
    compare(argv(app.runAlerts.notifyRunners[0].current), tc.notifyCmd + "m-r1|escalated")
    reply(app.runAlerts.notifyRunners[0].current, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(app.runAlerts.notifyRunners.length, 0)
    compare(app.runControl.setNotifyOnEscalation(false), true)
    reply(app.runControl.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(app.runAlerts.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runAlerts.toasts.length, 2, "r2's escalation is raised")
    compare(app.runAlerts.notifyRunners.length, 0, "the switch is off: a toast only")
  }

  // ---- app.runDispatch (split-runstore 4.1)

  // A-D1
  function test_app_composes_run_dispatch_wired_to_the_run_store() {
    var app = make(); if (!app) return
    verify(app.runDispatch, "App composes the dispatch store")
    compare(app.runDispatch.backendDir, "/plugin/core/backend/")
    compare(app.runDispatch.project, "/home/u/my proj")
    compare(app.runDispatch.active, false)
    app.panelOpen = true
    compare(app.runDispatch.active, true, "active follows panelOpen")
    app.panelOpen = false
    compare(app.runDispatch.active, false)
    verify(app.runDispatch.runs === app.runs.runs, "the run store's merged list")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("r1")], []), 0)
    compare(app.runDispatch.runs.length, 1)
    verify(app.runDispatch.runs === app.runs.runs)
    reply(app.runControl.runSettingsLoadRunner.current, dispatchSettings(), 0)
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project), "the run store's run settings")
    compare(app.runDispatch.runSettings.parallelism, 4)
    app.projects.chooseProject(pB)
    compare(app.runDispatch.project, "/home/u/b", "the project follows the selection")
  }

  // A-D2 and Review Focus 3
  function test_a_start_through_app_writes_the_run_settings_back_and_keeps_the_binding() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(app.runDispatch.dispatchState, "started")
    compare(app.runControl.runSettingsOf(app.runs.project).prefixByMilestone.m1, "old", "the start's values reach the run store")
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project), "the binding survives the write")
    app.projects.chooseProject(pB)
    compare(Object.keys(app.runControl.runSettingsOf(app.runs.project)).length, 0)
    compare(Object.keys(app.runDispatch.runSettings).length, 0, "B's form will not start from A's settings")
    reply(app.runControl.runSettingsLoadRunner.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(app.runDispatch.runSettings.parallelism, 9)
  }

  // A-D3 and Review Focus 2
  function test_a_start_through_app_announces_started_once() {
    var app = readyApp(); if (!app) return
    var onDispatch = createTemporaryObject(spyC, tc, { target: app.runDispatch, signalName: "dispatchStarted" })
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(onDispatch.count, 1)
    compare(onDispatch.signalArguments[0][0], "r-1")
  }

  // A-D4
  function test_a_dispatch_notice_through_app_is_run_controls_flash() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    var runner = app.runDispatch.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runControl.flashText, "")
    reply(saveOf(app).current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "Dispatch settings could not be saved")
    compare(app.runControl.flashTimer.running, true)
  }

  // A-D5 and Review Focus 5
  function test_closing_the_panel_through_app_keeps_a_start_in_flight() {
    var app = readyApp(); if (!app) return
    app.panelOpen = true
    compare(app.runDispatch.dispatchState, "ready", "opening the panel leaves the dispatch")
    compare(app.runDispatch.dispatchStart(), true)
    var proc = app.runDispatch.dispatchStartRunners[0].current
    app.panelOpen = false
    compare(app.runDispatch.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(app.runDispatch.dispatchState, "started", "it lands normally")
  }

  // A-S1
  function test_the_dispatch_reads_its_run_settings_from_run_control() {
    var app = make(); if (!app) return
    var load = app.runControl.runSettingsLoadRunner
    verify(load, "selecting a project asks run control for its run settings")
    compare(argv(load.current), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    reply(load.current, dispatchSettings(), 0)
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf("/home/u/my proj"))
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project), "the run store's shim reads the same object")
    compare(app.runDispatch.runSettings.parallelism, 4)
  }

  // A-S2
  function test_a_start_through_app_saves_through_run_control() {
    var app = readyApp(); if (!app) return
    compare(app.runControl.runSettingsRunners.length, 0, "the load has replied")
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(app.runControl.runSettingsRunners.length, 1, "exactly one save")
    var save = saveOf(app)
    verify(save)
    compare(argv(save.current).indexOf(tc.viewerCmd + "set-run-settings|/home/u/my proj|"), 0)
    compare(app.runControl.runSettingsOf("/home/u/my proj").prefixByMilestone.m1, "old")
    verify(app.runDispatch.runSettings === app.runControl.runSettingsOf("/home/u/my proj"))
    compare(app.runDispatch.dispatchStartRunners.length, 0)
  }

  // A-S3 and Review Focus 3
  function test_a_project_switch_through_app_loads_each_projects_settings_apart() {
    var app = make(); if (!app) return
    var loadA = app.runControl.runSettingsLoadRunner
    app.projects.chooseProject(pB)
    compare(app.runControl.runSettingsRunners.length, 2, "A's load is not stopped")
    var loadB = app.runControl.runSettingsLoadRunner
    compare(argv(loadB.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(loadA.current, dispatchSettings(), 0)
    compare(Object.keys(app.runDispatch.runSettings).length, 0, "A's late reply is A's")
    compare(app.runControl.runSettingsOf("/home/u/my proj").parallelism, 4)
    reply(loadB.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(app.runDispatch.runSettings.parallelism, 9)
    app.projects.chooseProject(pA)
    compare(Object.keys(app.runDispatch.runSettings).length, 0, "A's old entry is not shown before its reply")
    reply(app.runControl.runSettingsLoadRunner.current, JSON.stringify({ parallelism: 6 }) + "\n", 0)
    compare(app.runDispatch.runSettings.parallelism, 6)
  }

  // A-S5 and Review Focus 5
  function test_a_save_failure_after_switching_away_flashes_nothing() {
    var app = readyApp(); if (!app) return
    compare(app.runDispatch.dispatchStart(), true)
    reply(app.runDispatch.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    var save = saveOf(app)
    verify(save)
    app.projects.chooseProject(pB)
    reply(save.current, ctlFail("Invalid", "x"), 1)
    compare(app.runControl.flashText, "")
  }

  // ---- the event timeline's titles (run events 3.1)

  // 13
  function test_titles_follow_the_board() {
    var app = makeBare(); if (!app) return
    compare(JSON.stringify(app.runs.titles), "{}")
    app.board.cardMap = { c1: { title: "One" }, c2: { title: 7 } }
    compare(JSON.stringify(app.runs.titles), JSON.stringify({ c1: "One" }), "only string titles")
    app.board.cardMap = { c3: { title: "Three" } }
    compare(JSON.stringify(app.runs.titles), JSON.stringify({ c3: "Three" }), "a new board replaces the map")
  }
  // ---- the live output store (live output 3.2)

  readonly property string startedId: "20261008T143823Z-e795ad19"
  readonly property string openCard: "2280a6ab-9c40-434b-9729-63fd1f373754"

  // The started capture as a runs-snapshot-all.py entry: runs.json's first row
  // whose `status` is status-started.json's data. With `step`, openCard's
  // explore is finished and a deterministic `verify` phase is started.
  function startedEntry(step) {
    var e = F.load("runs.json").data.runs[0]
    e.status = F.load("status-started.json").data
    if (step) {
      var subtask = e.status.stories[1].subtasks[1]
      // synthetic: a deterministic phase in flight -- no capture has one
      subtask.phases[1].status = "done"
      subtask.phases[1].attempts[0].status = "ok"
      subtask.phases.push({ name: "verify", kind: "deterministic", status: "started", started_at: "",
                            ended_at: null, detail: null, attempts: [] })
    }
    return e
  }

  // runs-snapshot-all.py's reply: pA's entry lists `entries` as given.
  function entriesReply(entries) {
    return JSON.stringify({ ok: true, projects: [{ root: tc.pA.root_path, ok: true, runs: entries }],
                            data_dir: "/home/u/.local/share" }) + "\n"
  }

  // App with pA selected and its snapshot listing the started capture (`step`
  // as in startedEntry) applied.
  function withStarted(step) {
    var app = make(); if (!app) return null
    var proc = app.runs.snapshotRunner.current
    proc.outText = entriesReply([startedEntry(step)])
    proc.exited(0)
    return app
  }

  // A1
  function test_app_composes_a_run_output_store() {
    var app = makeBare(); if (!app) return
    verify(app.runOutput, "App composes it as app.runOutput")
    compare(app.runOutput.followStatus, "idle")
    compare(app.runOutput.backendDir, "/plugin/core/backend/")
    app.backendDir = "/other/core/backend/"
    compare(app.runOutput.backendDir, "/other/core/backend/")
    compare(app.runOutput.active, false)
    app.panelOpen = true
    compare(app.runOutput.active, true)
    app.panelOpen = false
    compare(app.runOutput.active, false)
    compare(app.runOutput.inRunDetail, false, "board")
    app.nav.viewMode = "run"
    compare(app.runOutput.inRunDetail, true)
    app.nav.viewMode = "runs"
    compare(app.runOutput.inRunDetail, false, "the Runs list is not Run detail")
  }

  // A2
  function test_run_and_selection_follow_the_run_store() {
    var app = withStarted(false); if (!app) return
    compare(app.runOutput.run, null, "no run selected")
    compare(app.runOutput.selection, null)
    app.runs.selectedRunId = tc.startedId
    verify(app.runOutput.run === app.runs.runById(tc.startedId), "the selected run")
    compare(JSON.stringify(app.runOutput.selection), JSON.stringify(app.runs.selectedAttempt))
    compare(JSON.stringify(app.runOutput.selection), JSON.stringify({ card_id: tc.openCard, phase: "explore", attempt: 1 }))
    var before = app.runOutput.run
    app.runs.refresh()
    var proc = app.runs.snapshotRunner.current
    proc.outText = entriesReply([startedEntry(false)])
    proc.exited(0)
    verify(app.runOutput.run !== before, "a snapshot hands a new run object")
    verify(app.runOutput.run === app.runs.runById(tc.startedId))
    app.runs.selectAttempt("5560d0fe-2b8e-4ef9-ad71-96b50ee89daa", "spec", 1)
    compare(JSON.stringify(app.runOutput.selection), JSON.stringify(app.runs.selectedAttempt))
    app.runs.selectedRunId = ""
    compare(app.runOutput.run, null)
  }

  // A3
  function test_snapshot_wanted_refreshes_the_logs() {
    var app = withStarted(true); if (!app) return
    app.runs.selectedRunId = tc.startedId
    compare(JSON.stringify(app.runs.selectedAttempt),
            JSON.stringify({ card_id: tc.openCard, phase: "verify", attempt: 0, step: true }))
    var first = app.runs.logsRunner.current
    verify(first, "the step's logs were asked for")
    first.outText = ""
    first.exited(1)
    compare(app.runs.logsRunner.busy, false)
    app.runOutput.snapshotWanted()
    var fetch = app.runs.logsRunner.current
    verify(fetch !== first, "one new runs-logs.py fetch")
    compare(fetch.command.join("|"), "python3|/plugin/core/backend/runs/runs-logs.py|/home/user/Code/omarchy-project-manager|"
            + tc.startedId + "|" + tc.openCard + "|verify|0")
  }

  // A4
  function test_the_selected_live_attempt_is_followed_until_the_panel_closes() {
    var app = withStarted(false); if (!app) return
    app.panelOpen = true
    app.nav.viewMode = "run"
    app.runs.selectedRunId = tc.startedId
    var proc = app.runOutput.followProc
    verify(proc, "the default attempt, explore.1, is followed")
    compare(proc.running, true)
    compare(proc.command.join("|"), "python3|/plugin/core/backend/runs/runs-logs-follow.py|/home/user/Code/omarchy-project-manager|"
            + tc.startedId + "|" + tc.openCard + "|explore|1")
    app.panelOpen = false
    compare(proc.running, false, "closing the panel stops it")
    compare(app.runOutput.followProc, null)
  }
}
