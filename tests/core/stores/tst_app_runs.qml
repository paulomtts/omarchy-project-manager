// tests/core/stores/tst_app_runs.qml
// App's composition of the run monitor's store: `app.runs` exists, and its
// three inputs come from App -- the backend dir, the selected project's ROOT
// PATH (never the project object), and App's panel-open flag. The store's own
// behaviour is tested in tst_run_store.qml; here only the wiring is.
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresAppRuns"

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

  function okReply(ids) {
    var runs = ids.map(function(id) {
      return { id: id, workflow: "orchestrator", repo_dir: "/home/u/my proj", started_at: "2026-10-01T00:00:00Z",
               status: { run: { id: id, milestone_id: "m-" + id, status: "done" }, rows: [], stories: [], subtasks: [],
                         control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: false } } } }
    })
    return JSON.stringify({ ok: true, runs: runs, data_dir: "/home/u/.local/share" }) + "\n"
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
    verify(!app.runs.snapshotRunner.current, "no snapshot without a project")
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

  function test_the_snapshot_runs_for_the_selected_root_path() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    var proc = app.runs.snapshotRunner.current
    verify(proc, "selecting a project starts a snapshot")
    compare(proc.command[0], "python3")
    compare(proc.command[1], "/plugin/core/backend/runs/runs-snapshot.py")
    compare(proc.command.length, 2, "every project, filtered to the root path by the store")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  function test_clearing_the_selection_empties_project_and_runs() {
    var app = make(); if (!app) return
    verify(app.runs, "app.runs exists")
    var proc = app.runs.snapshotRunner.current
    proc.outText = okReply(["r1"])
    proc.exited(0)
    compare(app.runs.runs.length, 1)
    app.projects.clearSelection()
    compare(app.runs.project, "")
    compare(app.runs.runs.length, 0, "the previous project's runs are gone")
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
    verify(!app.runs.snapshotRunner.current, "no snapshot without a project")
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
}
