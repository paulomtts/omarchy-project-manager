// tests/ui/tst_panel_toolbar.qml
// The fixed toolbar of ui/Panel.qml: the refresh and New icon/action buttons
// (their look, their order in the row and what they call), and the Documents
// pieces that live in the toolbar instead of the scrolling content.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "PanelToolbar"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/my proj", name: "alpha" })
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
    p.app.projects.selectedProject = null
    p.app.nav.viewMode = "runs"
    compare(button.visible, true, "no project: still shown")
    compare(button.enabled, false)
    compare(String(button.tooltipText), "Open a project to dispatch")
  }
}
