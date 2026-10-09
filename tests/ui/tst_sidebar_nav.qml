import QtQuick
import QtTest
import "../helpers/find.js" as H
TestCase {
  id: tc
  name: "SidebarNav"
  when: windowShown
  visible: true
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property var pC: ({ root_path: "/home/u/c", name: "gamma" })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    return p
  }
  function names(list) { return list.map(function(x) { return x.name }).join(",") }

  function test_first_project_is_selected_when_the_list_arrives() {
    var p = make(); if (!p) return
    compare(p.app.nav.viewMode, "board")
    compare(p.app.projects.selectedProject, null)
    p.app.projects.applyProjectsList([pA, pB, pC])
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
    compare(p.app.nav.viewMode, "board")
  }

  function test_stored_project_wins_over_the_first() {
    var p = make(); if (!p) return
    p.app.projects.storedProject = "/home/u/c"
    p.app.projects.applyProjectsList([pA, pB, pC])
    compare(p.app.projects.selectedProject.root_path, "/home/u/c")
  }

  function test_current_project_is_kept_when_the_list_refreshes() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB, pC])
    p.navigator.chooseProject(pB)
    p.app.projects.applyProjectsList([pA, pB, pC])
    compare(p.app.projects.selectedProject.root_path, "/home/u/b")
  }

  function test_vanished_current_project_falls_back() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB, pC])
    p.navigator.chooseProject(pB)
    p.app.projects.applyProjectsList([pA, pC])
    compare(p.app.projects.selectedProject.root_path, "/home/u/a")
  }

  function test_empty_registry_clears_the_selection() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB])
    p.app.board.applyTreeData([{ id: "x", title: "X", status: "todo", blocked_by: [], children: [] }])
    p.app.projects.applyProjectsList([])
    compare(p.app.projects.selectedProject, null)
    compare(p.app.board.cardRoots.length, 0)
    compare(p.app.nav.viewMode, "board")
    p.navigator.showSection("board")
    compare(p.app.nav.viewMode, "board")
  }

  function test_choose_project_switches_persists_and_closes_the_dropdown() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB, pC])
    p.navigator.toggleDropdown()
    compare(p.app.nav.dropdownOpen, true)
    p.navigator.chooseProject(pC)
    compare(p.app.nav.dropdownOpen, false)
    compare(p.app.projects.selectedProject.root_path, "/home/u/c")
    compare(p.app.projects.storedProject, "/home/u/c")
    compare(p.app.nav.viewMode, "board")
  }

  function test_dropdown_keyboard() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB, pC])
    p.navigator.toggleDropdown()
    compare(p.app.nav.dropdownCursor, 0)              // starts on the current project
    p.navigator.moveDropdown(1); compare(p.app.nav.dropdownCursor, 1)
    p.navigator.moveDropdown(9); compare(p.app.nav.dropdownCursor, 2)
    p.navigator.moveDropdown(-9); compare(p.app.nav.dropdownCursor, 0)
    p.app.nav.dropdownQuery = "gam"
    compare(names(p.app.projects.filteredProjects), "gamma")
    p.app.nav.dropdownCursor = 0
    p.navigator.acceptDropdown()
    compare(p.app.projects.selectedProject.root_path, "/home/u/c")
    compare(p.app.nav.dropdownOpen, false)
    compare(p.app.nav.dropdownQuery, "")
  }

  function test_dropdown_opens_on_the_current_project_and_toggles_closed() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB, pC])
    p.navigator.chooseProject(pB)
    p.navigator.toggleDropdown()
    compare(p.app.nav.dropdownCursor, 1)
    p.navigator.toggleDropdown()
    compare(p.app.nav.dropdownOpen, false)
  }

  function test_dropdown_cannot_open_during_delete_confirmation() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB])
    p.app.deleter.openDelete(p.app.projects.selectedProject)
    p.navigator.toggleDropdown()
    compare(p.app.nav.dropdownOpen, false)
  }

  function test_back_from_the_board_does_nothing_and_from_a_card_returns_to_the_board() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA])
    p.app.board.applyTreeData([{ id: "m", title: "M", status: "todo", blocked_by: [], children: [] }])
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board")
    p.app.nav.cursorIndex = 0; p.navigator.activateCursor()
    compare(p.app.nav.viewMode, "entry")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board")
  }

  function test_opening_the_panel_resets_transient_state() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA, pB])
    p.navigator.toggleDropdown(); p.app.nav.dropdownQuery = "x"
    p.opened = false; p.opened = true
    compare(p.app.nav.dropdownOpen, false); compare(p.app.nav.dropdownQuery, "")
  }

  // App's panel-open flag is how the run store knows to watch: it must follow
  // the real panel both ways.
  function test_the_panel_open_flag_reaches_the_run_store() {
    var p = make(); if (!p) return
    verify(p.app.runs, "App composes the run store")
    compare(p.opened, true)
    compare(p.app.panelOpen, true)
    compare(p.app.runs.active, true)
    p.opened = false
    compare(p.app.panelOpen, false)
    compare(p.app.runs.active, false)
    p.opened = true
    compare(p.app.runs.active, true)
  }

  function test_focus_item_follows_state() {
    var p = make(); if (!p) return
    compare(p.focusItem.objectName, "keyCatcher")
    p.app.projects.applyProjectsList([pA])
    compare(p.focusItem.objectName, "searchField")
    p.navigator.toggleDropdown()
    compare(p.focusItem.objectName, "filterField")
    p.navigator.closeDropdown()
    p.app.deleter.openDelete(p.app.projects.selectedProject)
    compare(p.focusItem.objectName, "confirmField")
    p.app.deleter.cancelDelete()
    compare(p.focusItem.objectName, "searchField")
    p.app.board.applyTreeData([{ id: "m", title: "M", status: "todo", blocked_by: [], children: [] }])
    p.app.nav.cursorIndex = 0; p.navigator.activateCursor()
    compare(p.focusItem.objectName, "keyCatcher")
  }

  function findIn(item, name) {
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = findIn(kids[i], name); if (r) return r }
    return null
  }
  function insideFlick(item) {
    for (var it = item; it; it = it.parent) if (it.objectName === "panelFlick") return true
    return false
  }

  function test_the_toolbar_stays_outside_the_scrolling_area() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }])
    var kc = host
    var toolbar = findIn(kc, "panelToolbar")
    var flick = findIn(kc, "panelFlick")
    verify(toolbar, "panelToolbar")
    verify(flick, "panelFlick")
    verify(!insideFlick(toolbar), "toolbar is not inside the flickable")
    verify(!insideFlick(findIn(kc, "searchField")), "search is not inside the flickable")
    verify(!insideFlick(findIn(kc, "projectHeading")), "heading is not inside the flickable")
    verify(insideFlick(findIn(kc, "documentsView")), "content is inside the flickable")
    verify(flick.y >= toolbar.y + toolbar.height, "content starts below the toolbar")
  }

  function test_clicking_the_runs_row_opens_the_runs_section() {
    var p = make(); if (!p) return
    p.app.projects.applyProjectsList([pA])
    // The snapshot the project selection launched cannot run here.
    p.app.runs.snapshotRunner.cancel()
    wait(50)
    var row = H.find(p, "navRuns")
    verify(row, "the Runs nav row")
    mouseClick(row, row.width / 2, row.height / 2)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.section, "runs")
  }

  // ---- no project (4.1): Runs is the one section that needs none

  function aRun(id) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "alpha", status: "started", started_at: "",
             lease: null, rows: [], tree: { stories: [], subtasks: [] }, project: { root: "/home/u/a", name: "alpha" } }
  }

  function test_clicking_the_runs_row_with_no_project_opens_the_runs_section() {
    var p = make(); if (!p) return
    compare(p.app.projects.selectedProject, null)
    var row = H.find(p, "navRuns")
    compare(row.enabled, true)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.nav.section, "runs")
    wait(50)
    compare(H.find(p, "runsView").visible, true)
    compare(H.find(p, "searchField").visible, true)
  }

  function test_focus_item_with_no_project() {
    var p = make(); if (!p) return
    compare(p.app.projects.selectedProject, null)
    compare(p.app.nav.viewMode, "board")
    compare(p.focusItem.objectName, "keyCatcher")
    p.navigator.showSection("runs")
    compare(p.focusItem.objectName, "searchField")
    p.app.runs.runs = [aRun("run-0000000000a1")]
    p.navigator.openRun("run-0000000000a1", "runs")
    compare(p.app.nav.viewMode, "run")
    compare(p.focusItem.objectName, "keyCatcher")
  }

  function test_with_no_project_the_bound_rows_stay_disabled_and_inert() {
    var p = make(); if (!p) return
    compare(p.app.projects.selectedProject, null)
    p.navigator.showSection("runs")
    compare(p.app.nav.viewMode, "runs")
    var rows = ["navBoard", "navGraph", "navDocuments", "navMemories", "navIssues"]
    for (var i = 0; i < rows.length; i++) {
      var row = H.find(p, rows[i])
      compare(row.enabled, false, rows[i])
      mouseClick(row, row.width / 2, row.height / 2)
      compare(p.app.nav.viewMode, "runs", rows[i])
    }
    var names = ["board", "graph", "documents", "memories", "issues"]
    for (var j = 0; j < names.length; j++) {
      p.navigator.showSection(names[j])
      compare(p.app.nav.viewMode, "runs", names[j])
    }
  }
}
