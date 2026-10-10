// tests/ui/tst_panel_toolbar.qml
// The fixed toolbar of ui/Panel.qml: the refresh and New icon/action buttons
// (their look, their order in the row and what they call), and the Documents
// pieces that live in the toolbar instead of the scrolling content.
import QtQuick
import QtTest
import "../helpers/find.js" as H
import "../../core/domain/runs.js" as Runs
import "../../ui/components/runGlyphs.js" as RG

TestCase {
  id: tc
  name: "PanelToolbar"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })
  property string memList: '{"ok": true, "found": true, "memory_dir": "/c/-home-u-my-proj/memory", "notes": [' +
    '{"file": "user_role.md", "name": "Role", "description": "d", "type": "user", "size": 10, "indexed": true}]}'
  property string docList: '{"ok": true, "docs": [' +
    '{"path": "docs/architecture/a.md", "title": "Arch", "size": 1, "category": "architecture"},' +
    '{"path": "docs/specs/s.md", "title": "Spec", "size": 1, "category": "specs"}], "truncated": false}'

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    return p
  }

  function inMemories() {
    var p = make(); if (!p) return null
    p.navigator.showSection("memories")
    p.app.memories.applyMemoriesResult(memList, 0)
    wait(50)
    return p
  }

  function inDocuments() {
    var p = make(); if (!p) return null
    p.navigator.showSection("documents")
    p.app.docs.applyDocsResult(docList, 0)
    wait(50)
    return p
  }

  // Walks up from `item`: is it inside the item named `name`?
  function isUnder(item, name) {
    var node = item
    while (node) {
      if (node.objectName === name) return true
      node = node.parent
    }
    return false
  }

  // ---- the refresh and New buttons

  function test_the_refresh_button_is_a_bordered_icon_button() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    verify(refresh, "the refresh button")
    verify(String(refresh.iconText) !== "", "it draws a glyph")
    compare(String(refresh.text), "")
    compare(refresh.bordered, true)
    compare(String(refresh.tooltipText), "Refresh")
  }

  function test_the_refresh_button_is_square_and_as_tall_as_the_new_button() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    var newButton = H.find(p, "newMemoryButton")
    verify(refresh && newButton, "both toolbar buttons")
    compare(newButton.visible, true)
    compare(refresh.width, refresh.height)
    compare(refresh.height, newButton.height)
  }

  function test_the_refresh_button_sits_left_of_the_new_button() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    var newButton = H.find(p, "newMemoryButton")
    verify(refresh && newButton, "both toolbar buttons")
    compare(refresh.visible, true)
    compare(newButton.visible, true)
    var rx = refresh.mapToItem(p, 0, 0).x
    var nx = newButton.mapToItem(p, 0, 0).x
    verify(rx < nx, "refresh at " + rx + " is left of New at " + nx)
  }

  function test_the_new_button_is_a_bordered_button_that_opens_the_dialog() {
    var p = inMemories(); if (!p) return
    var newButton = H.find(p, "newMemoryButton")
    verify(newButton, "the New button")
    compare(newButton.bordered, true)
    verify(String(newButton.text) !== "", "it keeps its label")
    mouseClick(newButton, newButton.width / 2, newButton.height / 2)
    compare(p.app.memories.newMemoryOpen, true)
  }

  function test_the_refresh_button_refetches_the_open_section() {
    var p = inMemories(); if (!p) return
    var refresh = H.find(p, "refreshButton")
    mouseClick(refresh, refresh.width / 2, refresh.height / 2)
    compare(p.app.memories.memoriesLoading, true)
    p.navigator.showSection("board")
    wait(50)
    p.app.board.treeProc.running = false
    refresh = H.find(p, "refreshButton")
    compare(refresh.visible, true)
    mouseClick(refresh, refresh.width / 2, refresh.height / 2)
    compare(p.app.board.treeProc.running, true)
  }

  function test_the_refresh_button_is_hidden_outside_board_graph_and_memories() {
    var p = inDocuments(); if (!p) return
    compare(H.find(p, "refreshButton").visible, false)
    p.navigator.showSection("graph")
    wait(50)
    compare(H.find(p, "refreshButton").visible, true)
  }

  // ---- the Graph's Milestone | Story switch

  function test_the_graph_view_chips_live_in_the_toolbar_of_the_graph_section() {
    var p = make(); if (!p) return
    var chips = H.find(p, "graphViewChips")
    verify(chips, "the view switch")
    compare(chips.visible, false, "not in the board")
    p.navigator.showSection("graph")
    wait(50)
    compare(chips.visible, true)
    verify(isUnder(chips, "panelToolbar"), "inside the fixed toolbar")
    verify(!isUnder(chips, "panelFlick"), "and not inside the scrolling content")
  }

  function test_clicking_the_story_chip_switches_the_graph_view() {
    var p = make(); if (!p) return
    p.navigator.showSection("graph")
    wait(50)
    var story = H.find(p, "graphViewChipstory")
    verify(story, "the Story chip")
    compare(p.app.graph.graphView, "milestone")
    mouseClick(story, story.width / 2, story.height / 2)
    compare(p.app.graph.graphView, "story")
    var milestone = H.find(p, "graphViewChipmilestone")
    mouseClick(milestone, milestone.width / 2, milestone.height / 2)
    compare(p.app.graph.graphView, "milestone")
  }

  // ---- the Graph's Show archived toggle

  function test_the_show_archived_toggle_lives_in_the_graph_toolbar_off_by_default() {
    var p = make(); if (!p) return
    var chip = H.find(p, "graphArchivedChip")
    verify(chip, "the toggle")
    compare(chip.visible, false, "not in the board")
    p.navigator.showSection("graph")
    wait(50)
    compare(chip.visible, true)
    verify(isUnder(chip, "panelToolbar"), "inside the fixed toolbar")
    compare(chip.active, false, "archived cards are hidden by default")
    compare(p.app.graph.showArchived, false)
  }

  function test_clicking_the_show_archived_toggle_flips_the_graph_setting() {
    var p = make(); if (!p) return
    // The test Panel is 380 wide, narrower than the toolbar with this chip.
    var panel = H.find(p, "mainPanel")
    panel.width = 840; panel.height = 600
    p.navigator.showSection("graph")
    wait(50)
    var chip = H.find(p, "graphArchivedChip")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(p.app.graph.showArchived, true)
    compare(chip.active, true)
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(p.app.graph.showArchived, false)
    compare(chip.active, false)
  }

  // ---- the Documents pieces the toolbar owns

  function test_the_document_category_chips_live_in_the_toolbar() {
    var p = inDocuments(); if (!p) return
    var chips = H.find(p, "docChips")
    verify(chips, "the category chips")
    verify(isUnder(chips, "panelToolbar"), "the chips are inside the fixed toolbar")
    verify(!isUnder(chips, "panelFlick"), "and not inside the scrolling content")
    compare(chips.visible, true)
  }

  function test_a_toolbar_chip_still_toggles_the_store_category() {
    var p = inDocuments(); if (!p) return
    var chip = H.find(p, "docChipspecs")
    verify(chip, "the specs chip")
    compare(String(chip.text), "Specs 1")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(p.app.docs.docCategory, "specs")
    wait(50)
    mouseClick(H.find(p, "docChipspecs"), 5, 5)
    compare(p.app.docs.docCategory, "")
  }

  function test_the_open_documents_path_and_tag_picker_live_in_the_toolbar() {
    var p = inDocuments(); if (!p) return
    p.app.nav.cursorIndex = 1
    p.navigator.activateCursor()
    wait(50)
    compare(p.app.nav.viewMode, "document")
    var path = H.find(p, "docPath")
    verify(path, "the document path")
    compare(String(path.text), "docs/specs/s.md")
    compare(path.elide, Text.ElideMiddle)
    verify(isUnder(path, "panelToolbar"), "the path is inside the fixed toolbar")
    verify(!isUnder(path, "panelFlick"))
    var picker = H.find(p, "tagPicker")
    verify(picker, "the tag picker")
    verify(isUnder(picker, "panelToolbar"), "the picker is inside the fixed toolbar")
    verify(!isUnder(picker, "panelFlick"))
    compare(picker.current, "specs")
    var chip = H.find(p, "tagChipaudits")
    verify(chip, "the audits chip")
    mouseClick(chip, chip.width / 2, chip.height / 2)
    verify(p.app.docs.tagger.current, "the toolbar asked the store to set the tag")
    compare(p.app.docs.tagger.current.command[4], "audits")
  }

  function test_the_documents_toolbar_pieces_are_hidden_in_other_views() {
    var p = inDocuments(); if (!p) return
    compare(H.find(p, "tagPicker").visible, false)
    compare(H.find(p, "docPath").visible, false)
    p.navigator.showSection("board")
    wait(50)
    compare(H.find(p, "docChips").visible, false)
    compare(H.find(p, "tagPicker").visible, false)
  }

  // ---- the breadcrumb trail

  function texts(item, out) {
    out = out || []
    if (item.visible === false) return out
    if (item.text !== undefined && String(item.text) !== "") out.push(String(item.text))
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) texts(kids[i], out)
    return out
  }

  function test_the_toolbar_leads_with_the_breadcrumb_trail() {
    var p = inDocuments(); if (!p) return
    var heading = H.find(p, "projectHeading")
    verify(heading, "the current crumb still carries the heading object name")
    compare(String(heading.text), "Documents")
    verify(isUnder(heading, "panelToolbar"), "the trail is in the fixed toolbar")
    var crumb = H.find(p, "crumb0")
    verify(crumb, "the first crumb")
    verify(crumb.mapToItem(p, 0, 0).x < H.find(p, "refreshButton").mapToItem(p, 0, 0).x,
      "the trail leads the toolbar row")
  }

  function test_an_open_document_shows_a_two_crumb_trail_and_no_back_label() {
    var p = inDocuments(); if (!p) return
    p.app.nav.cursorIndex = 1
    p.navigator.activateCursor()
    wait(50)
    compare(String(H.find(p, "crumbText0").text), "Documents")
    compare(String(H.find(p, "projectHeading").text), "Spec")
    verify(texts(p).indexOf("\u2039 Back") < 0, "the Back label is gone")
  }

  function test_clicking_the_section_crumb_goes_back_to_the_list() {
    var p = inDocuments(); if (!p) return
    p.app.nav.cursorIndex = 1
    p.navigator.activateCursor()
    wait(50)
    compare(p.app.nav.viewMode, "document")
    var crumb = H.find(p, "crumbText0")
    mouseClick(crumb, crumb.width / 2, crumb.height / 2)
    compare(p.app.nav.viewMode, "documents")
  }

  // ---- Start run (S3 4.2)

  // 18
  function test_start_run_shows_only_on_the_runs_list() {
    var p = make(); if (!p) return
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = [{ id: "run-0000000000a1", repo_dir: "/home/u/my proj", milestone_id: "alpha", status: "started",
                         started_at: "", lease: null, rows: [], tree: { stories: [], subtasks: [] } }]
    var button = H.find(p, "startRunButton")
    verify(button, "the Start run button")
    var hidden = ["board", "graph", "memories", "issues"]
    for (var i = 0; i < hidden.length; i++) {
      p.navigator.showSection(hidden[i])
      compare(button.visible, false, hidden[i])
    }
    p.navigator.showSection("runs")
    wait(50)
    compare(button.visible, true)
    compare(String(button.text), "Start run")
    compare(String(button.iconText), "▶")
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    p.navigator.openRun("run-0000000000a1", "runs")
    compare(p.app.nav.viewMode, "run")
    compare(button.visible, false, "run detail")
    p.navigator.goBack()
    compare(button.visible, true)
    p.app.runs.amStatus = "missing"
    compare(button.enabled, false)
    compare(String(button.tooltipText), "am is not installed or not on PATH")
    p.app.runs.amStatus = "ok"
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, true, "no project: still shown")
    compare(button.enabled, true, "pA is registered: there is a project to pick")
    compare(String(button.tooltipText), "Start an am run")
  }

  // ---- the run indicator (4.5)

  // One normalized run of the project at `root` named `name`; `status` and
  // `live` (null: no lease) give its Runs state.
  function runOf(id, root, name, status, live) {
    return { id: id, repo_dir: root, milestone_id: "m-" + id.slice(-2), status: status, started_at: "",
             lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: [], tree: { stories: [], subtasks: [] }, project: { root: root, name: name } }
  }

  // The run list, set directly; a snapshot launched by a registry change or
  // a project switch is cancelled first, so its reply never lands.
  function setRuns(p, list) {
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.runs = list
  }

  // alpha: one running, one escalated. beta: one running, one parked, one dead.
  function twoProjectRuns() {
    return [runOf("run-0000000000a1", pA.root_path, "alpha", "started", true),
            runOf("run-0000000000a2", pA.root_path, "alpha", "escalated", null),
            runOf("run-0000000000b1", pB.root_path, "beta", "started", true),
            runOf("run-0000000000b2", pB.root_path, "beta", "stopped", null),
            runOf("run-0000000000b3", pB.root_path, "beta", "started", false)]
  }

  // make() with pA and pB registered (pA open) and twoProjectRuns().
  function makeTwo() {
    var p = make(); if (!p) return null
    p.app.projects.applyProjectsList([pA, pB])
    setRuns(p, twoProjectRuns())
    return p
  }

  // The test Panel is 380 wide, narrower than the toolbar with the strip.
  function widen(p) {
    var panel = H.find(p, "mainPanel")
    panel.width = 840; panel.height = 600
    wait(50)
  }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item, item.width / 2, item.height / 2)
  }

  function test_the_run_indicator_is_mounted_in_the_toolbar_and_hidden_with_no_runs() {
    var p = make(); if (!p) return
    widen(p)
    var ind = H.find(p, "runIndicator")
    verify(ind, "the run indicator")
    verify(isUnder(ind, "panelToolbar"), "inside the fixed toolbar")
    verify(!isUnder(ind, "panelFlick"), "and not inside the scrolling content")
    setRuns(p, [])
    compare(ind.visible, false, "no runs")
    setRuns(p, [runOf("run-0000000000a1", pA.root_path, "alpha", "started", true)])
    wait(50)
    compare(ind.visible, true)
    var running = H.find(p, "runIndicatorRunning")
    compare(String(running.text), RG.glyphOf("running") + "1")
    compare(String(running.text), "⟳1")
    verify(ind.width > 0, "a visible strip has a width")
    var toolbar = H.find(p, "panelToolbar")
    var right = ind.mapToItem(toolbar, 0, 0).x + ind.width
    verify(right <= toolbar.width + 0.5, "inside the toolbar: right edge " + right + " of " + toolbar.width)
    setRuns(p, [runOf("run-0000000000d4", pA.root_path, "alpha", "done", null)])
    compare(ind.visible, false, "only finished runs")
  }

  function test_the_run_indicator_counts_runs_across_two_projects() {
    var runs = twoProjectRuns()
    var states = runs.map(function(r) { return Runs.runState(r) }).join(",")
    compare(states, "running,escalated,running,parked,dead", "the fixture's states")
    var counts = Runs.runFilterCounts(runs)
    compare(counts.live, 2)
    compare(counts.parked, 1)
    compare(counts.attention, 2)
    var p = makeTwo(); if (!p) return
    compare(p.app.projects.selectedProject.root_path, pA.root_path, "pA is open")
    var ind = H.find(p, "runIndicator")
    compare(ind.visible, true)
    compare(ind.running, 2)
    compare(ind.parked, 1)
    compare(ind.attention, 2)
    p.app.runs.toggleProjectFilter(pA.root_path)
    compare(p.app.runs.projectFilter, pA.root_path, "the Runs list is narrowed to alpha")
    compare(ind.running, 2)
    compare(ind.parked, 1)
    compare(ind.attention, 2)
  }

  function test_the_run_indicator_shows_with_no_project_open() {
    var p = makeTwo(); if (!p) return
    p.app.projects.selectedProject = null
    setRuns(p, twoProjectRuns())
    wait(50)
    var ind = H.find(p, "runIndicator")
    compare(ind.visible, true, "in " + p.app.nav.viewMode)
    compare(ind.running, 2)
    compare(ind.parked, 1)
    compare(ind.attention, 2)
    p.navigator.showSection("runs")
    wait(50)
    compare(ind.visible, true, "on the Runs list")
    compare(ind.running, 2)
  }

  // Review Focus 1, 2
  function test_clicking_an_indicator_segment_shows_runs_on_that_chip() {
    var p = makeTwo(); if (!p) return
    widen(p)
    p.navigator.showSection("board")
    wait(50)
    compare(p.app.runs.runFilter, "")
    tap(H.find(p, "runIndicatorParked"))
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.runFilter, "parked")
    wait(50)
    p.app.nav.searchQuery = "zzz"
    tap(H.find(p, "runIndicatorParked"))
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.runFilter, "parked", "the active chip is kept, not toggled to All")
    compare(p.app.nav.searchQuery, "", "the search is cleared, so the list holds what was counted")
    tap(H.find(p, "runIndicatorAttention"))
    compare(p.app.runs.runFilter, "attention")
    tap(H.find(p, "runIndicatorRunning"))
    compare(p.app.runs.runFilter, "live")
    compare(p.app.projects.selectedProject.root_path, pA.root_path, "the open project is kept")
  }

  function test_an_indicator_click_resets_the_project_filter_and_works_with_no_project() {
    var p = makeTwo(); if (!p) return
    widen(p)
    p.app.projects.selectedProject = null
    setRuns(p, twoProjectRuns())
    p.navigator.showSection("runs")
    p.app.runs.toggleProjectFilter(pB.root_path)
    compare(p.app.runs.projectFilter, pB.root_path)
    p.navigator.openRun("run-0000000000b1", "runs")
    compare(p.app.nav.viewMode, "run")
    wait(50)
    tap(H.find(p, "runIndicatorRunning"))
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.runFilter, "live")
    compare(p.app.runs.projectFilter, "", "All projects, as the indicator counts")
    compare(p.app.projects.selectedProject, null)
  }

  // A pin: passes before showRunsFiltered exists (nothing handles the
  // signal yet) and must keep passing after it.
  function test_an_indicator_click_under_a_modal_changes_nothing() {
    var p = makeTwo(); if (!p) return
    p.navigator.showSection("board")
    compare(p.app.runs.runFilter, "")
    p.app.deleter.openDelete(pA)
    verify(p.app.deleter.deleteTarget, "the delete confirmation is open")
    // The backdrop takes mouse clicks, so the segment is asked through its signal.
    H.find(p, "runIndicator").filterRequested("parked")
    compare(p.app.nav.viewMode, "board")
    compare(p.app.runs.runFilter, "")
    compare(p.app.runs.projectFilter, "")
  }
}
