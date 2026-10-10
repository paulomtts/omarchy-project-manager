// tests/core/stores/tst_app_runs.qml
// App's composition of the run monitor's store: `app.runs` exists, and its
// inputs come from App -- the backend dir, the registry's roots and names,
// the selected project's ROOT PATH (never the project object), and App's
// panel-open flag. The store's own behaviour is tested in tst_run_store.qml;
// here only the wiring is.
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
