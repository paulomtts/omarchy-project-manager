// tests/core/stores/tst_app_runs.qml
// App's composition of the run monitor's store: `app.runs` exists, and its
// inputs come from App -- the backend dir, the registry's roots and names,
// the selected project's ROOT PATH (never the project object), and App's
// panel-open flag -- and the couplings between the run monitor's concerns,
// driven through App. The store's own behaviour is tested in tst_run_store.qml.
import QtQuick
import QtTest

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
    reply(app.runs.runSettingsRunner.current, dispatchSettings(), 0)
    reply(app.runs.snapshotRunner.current, listReply([], []), 0)
    var cards = dispatchCards()
    compare(app.runs.openDispatch(cards.m1, cards), true)
    reply(app.runs.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(app.runs.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(app.runs.dispatchState, "ready")
    return app
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
    compare(app.runs.control("pause", "r1"), true)
    compare(app.runs.pending.r1, "pause")
    reply(app.runs.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.pending.r1, "pause", "am has it; a snapshot settles it")
    reply(app.runs.snapshotRunner.current,
          listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: null }])], []), 0)
    compare(app.runs.pending.r1, "pause", "not handled yet")
    snapshot(app, listReply([runEntry("r1", "started", true, tc.pA.root_path, [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])], []))
    compare(app.runs.pending.r1, undefined, "the handled request is settled")
  }

  function test_a_snapshot_through_app_raises_one_toast_after_arming() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.toasts.length, 0, "the first snapshots only arm")
    compare(app.runs.alertsArmed, true)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runs.toasts.length, 1)
    compare(app.runs.toasts[0].id, "r1")
  }

  function test_am_missing_through_app_disarms_and_the_next_snapshot_only_rearms() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.alertsArmed, true)
    snapshot(app, missingReply())
    compare(app.runs.amStatus, "missing")
    compare(app.runs.alertsArmed, false)
    compare(app.runs.runs.length, 0)
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runs.toasts.length, 0, "the first good snapshot after am came back only arms")
    compare(app.runs.alertsArmed, true)
  }

  function test_a_control_reply_through_app_snapshots_every_registered_root() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runs.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", requested_at: "t1" }), 0)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root, not only the run's")
  }

  function test_a_failed_control_reply_through_app_also_snapshots_every_root() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    compare(app.runs.control("pause", "r1"), true)
    var seq = app.runs.snapshotRunner.seq
    reply(app.runs.controlRunners[0].current, ctlFail("NotAcceptingError", "run r1 is in integrate"), 0)
    compare(app.runs.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(app.runs.pending.r1, undefined)
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll)
  }

  function test_a_dispatch_start_through_app_snapshots_every_registered_root() {
    var app = readyApp(); if (!app) return
    var spy = createTemporaryObject(spyC, tc, { target: app.runs, signalName: "dispatchStarted" })
    compare(app.runs.dispatchStart(), true)
    var runner = app.runs.dispatchStartRunners[0]
    var seq = app.runs.snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runs.dispatchState, "started")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(app.runs.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(app.runs.snapshotRunner.current), tc.snapAll, "of every registered root, not only the started run's")
    var save = runner.current
    compare(save.command.length, 5)
    compare(save.command.slice(0, 4).join("|"), tc.viewerCmd + "set-run-settings|/home/u/my proj")
  }

  function test_a_dispatch_settings_save_failure_through_app_flashes() {
    var app = readyApp(); if (!app) return
    compare(app.runs.dispatchStart(), true)
    var runner = app.runs.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(app.runs.flashText, "")
    reply(runner.current, ctlFail("Invalid", "x"), 1)
    compare(app.runs.flashText, "Dispatch settings could not be saved")
    compare(app.runs.dispatchState, "started", "the run still started")
    compare(app.runs.dispatchStartRunners.length, 0)
  }

  function test_a_project_switch_through_app_resets_the_dispatch_and_reloads_run_settings() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    reply(app.runs.runSettingsRunner.current, dispatchSettings(), 0)
    compare(app.runs.runSettings.parallelism, 4)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runs.toasts.length, 1)
    compare(app.runs.control("pause", "r2"), true)
    app.runs.flash("kept")
    var cards = dispatchCards()
    compare(app.runs.openDispatch(cards.m1, cards), true)
    reply(app.runs.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(app.runs.dispatchState, "previewing")
    var seq = app.runs.snapshotRunner.seq
    app.projects.chooseProject(pB)
    compare(app.runs.dispatchState, "idle")
    compare(Object.keys(app.runs.runSettings).length, 0)
    compare(argv(app.runs.runSettingsRunner.current), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(app.runs.toasts.length, 1, "the toast stays")
    compare(app.runs.toasts[0].id, "r1")
    compare(app.runs.pending.r2, "pause", "the request stays")
    compare(app.runs.flashText, "kept", "the flash stays")
    compare(app.runs.snapshotRunner.seq, seq, "no snapshot is launched")
  }

  function test_opening_the_panel_through_app_reads_the_notify_switch() {
    var app = make(); if (!app) return
    verify(!app.runs.settingsLoadRunner.current, "a closed panel reads nothing")
    app.runs.setNotifyOnEscalation(false)
    compare(app.runs.notifyTouched, true)
    reply(app.runs.settingsSaveRunner.current, JSON.stringify({ ok: true }) + "\n", 0)
    app.panelOpen = true
    compare(argv(app.runs.settingsLoadRunner.current), tc.viewerCmd + "get-global-settings")
    compare(app.runs.notifyTouched, false, "the opening's load is not too late")
    reply(app.runs.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runs.notifyOnEscalation, true)
  }

  function test_closing_the_panel_through_app_empties_toasts_disarms_and_closes_the_dispatch() {
    var app = openApp([runningIn("r1")], []); if (!app) return
    snapshot(app, listReply([escalatedIn("r1")], []))
    compare(app.runs.toasts.length, 1)
    var cards = dispatchCards()
    compare(app.runs.openDispatch(cards.m1, cards), true)
    compare(app.runs.dispatchState, "previewing")
    app.panelOpen = false
    compare(app.runs.toasts.length, 0)
    compare(app.runs.alertsArmed, false)
    compare(app.runs.dispatchState, "idle")
  }

  function test_an_escalation_through_app_notifies_only_with_the_switch_on() {
    var app = openApp([runningIn("r1"), runningIn("r2")], []); if (!app) return
    compare(app.runs.notifyOnEscalation, false)
    snapshot(app, listReply([escalatedIn("r1"), runningIn("r2")], []))
    compare(app.runs.toasts.length, 1)
    compare(app.runs.notifyRunners.length, 0, "the switch is off: a toast only")
    reply(app.runs.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(app.runs.notifyOnEscalation, true)
    snapshot(app, listReply([escalatedIn("r1"), escalatedIn("r2")], []))
    compare(app.runs.toasts.length, 2)
    compare(app.runs.notifyRunners.length, 1, "one notification, for r2")
    compare(argv(app.runs.notifyRunners[0].current), tc.notifyCmd + "m-r2|escalated")
  }

  function test_a_project_leaving_the_registry_through_app_loses_its_arming() {
    var app = openApp([runningIn("a1")], [runningIn("b1", tc.pB.root_path)]); if (!app) return
    compare(Object.keys(app.runs.armedRoots).sort().join(","), [tc.pA.root_path, tc.pB.root_path].sort().join(","))
    app.projects.applyProjectsList([pA])
    compare(Object.keys(app.runs.armedRoots).join(","), tc.pA.root_path, "pB's arming goes with it")
    reply(app.runs.snapshotRunner.current, listReply([runningIn("a1")], null), 0)
    app.projects.applyProjectsList([pA, pB])
    reply(app.runs.snapshotRunner.current, listReply([escalatedIn("a1")], [escalatedIn("b1", tc.pB.root_path)]), 0)
    compare(app.runs.toasts.length, 1, "pB's first entry back only re-arms it")
    compare(app.runs.toasts[0].id, "a1", "pA stayed armed")
    compare(Object.keys(app.runs.armedRoots).length, 2)
  }
}
