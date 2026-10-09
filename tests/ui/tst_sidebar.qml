import QtQuick
import QtTest
import "../../ui/components"
import "../../ui/components/runGlyphs.js" as RG
TestCase {
  id: tc
  name: "Sidebar"
  when: windowShown
  visible: true
  width: 300; height: 500

  Component { id: sbC; Sidebar { width: 200; height: 460 } }
  SignalSpy { id: toggled; signalName: "dropdownToggled" }
  SignalSpy { id: chosen; signalName: "projectChosen" }
  SignalSpy { id: sectionSpy; signalName: "sectionChosen" }
  SignalSpy { id: deleteSpy; signalName: "deleteRequested" }
  SignalSpy { id: querySpy; signalName: "queryEdited" }
  SignalSpy { id: hoverSpy; signalName: "cursorHovered" }
  SignalSpy { id: moveSpy; signalName: "dropdownMove" }
  SignalSpy { id: acceptSpy; signalName: "dropdownAccept" }
  SignalSpy { id: cancelSpy; signalName: "dropdownCancel" }
  SignalSpy { id: keySpy; signalName: "filterKey" }

  property var projects: [{ root_path: "/a", name: "alpha" }, { root_path: "/b", name: "beta" }, { root_path: "/c", name: "gamma" }]

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var r = find(item.children[i], name)
      if (r) return r
    }
    return null
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  function make() {
    var sb = createTemporaryObject(sbC, tc)
    sb.projects = projects
    sb.selectedProject = projects[0]
    sb.canDelete = true
    var spies = [toggled, chosen, sectionSpy, deleteSpy, querySpy, hoverSpy, moveSpy, acceptSpy, cancelSpy, keySpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = sb; spies[i].clear() }
    wait(20)
    return sb
  }

  function test_button_shows_project_and_toggles() {
    var sb = make()
    var btn = find(sb, "projectButton")
    verify(btn, "projectButton")
    click(btn)
    compare(toggled.count, 1)
    sb.selectedProject = null
    compare(sb.hasProject, false)
  }

  function test_dropdown_lists_projects_and_chooses() {
    var sb = make()
    sb.dropdownOpen = true
    wait(20)
    compare(find(sb, "dropdown").visible, true)
    verify(find(sb, "projectRow2"), "three rows")
    verify(!find(sb, "projectRow3"), "no fourth row")
    click(find(sb, "projectRow1"))
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0].root_path, "/b")
  }

  function test_dropdown_is_hidden_when_closed() {
    var sb = make()
    compare(find(sb, "dropdown").visible, false)
  }

  function test_dropdown_shows_an_empty_message() {
    var sb = make()
    sb.projects = []
    sb.dropdownOpen = true
    wait(20)
    verify(!find(sb, "projectRow0"))
  }

  function test_filter_field_emits_query_and_keys() {
    var sb = make()
    sb.dropdownOpen = true
    var f = find(sb, "filterField")
    verify(f)
    f.text = "be"
    compare(querySpy.count, 1)
    compare(querySpy.signalArguments[0][0], "be")
  }

  function test_navigation_rows_emit_sections_and_respect_enabled() {
    var sb = make()
    click(find(sb, "navDocuments"))
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "documents")
    click(find(sb, "navBoard"))
    compare(sectionSpy.signalArguments[1][0], "board")
    sb.documentsEnabled = false
    click(find(sb, "navDocuments"))
    compare(sectionSpy.count, 2)
    sb.documentsEnabled = true
    sb.selectedProject = null
    click(find(sb, "navBoard"))
    click(find(sb, "navDocuments"))
    compare(sectionSpy.count, 2)
  }

  function test_delete_button_follows_canDelete() {
    var sb = make()
    var b = find(sb, "deleteButton")
    verify(b)
    compare(b.enabled, true)
    b.clicked()
    compare(deleteSpy.count, 1)
    sb.canDelete = false
    compare(b.enabled, false)
    sb.canDelete = true
    sb.selectedProject = null
    compare(b.enabled, false)
  }

  function test_row_hover_reports_the_index() {
    var sb = make()
    sb.dropdownOpen = true
    wait(20)
    var row = find(sb, "projectRow2")
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 2)
  }

  function test_the_graph_row_emits_its_section() {
    var sb = make()
    click(find(sb, "navGraph"))
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "graph")
  }

  function test_every_navigation_row_carries_its_own_icon_glyph() {
    var sb = make()
    var names = ["navIconBoard", "navIconGraph", "navIconDocuments", "navIconMemories", "navIconIssues"]
    var glyphs = []
    var size = -1
    for (var i = 0; i < names.length; i++) {
      var icon = find(sb, names[i])
      verify(icon, names[i])
      verify(String(icon.text) !== "", names[i] + " draws a glyph")
      verify(glyphs.indexOf(String(icon.text)) < 0, names[i] + " is not a repeat")
      glyphs.push(String(icon.text))
      if (size < 0) size = icon.font.pixelSize
      compare(icon.font.pixelSize, size, names[i] + " is drawn at the shared icon size")
    }
  }

  function test_a_row_icon_is_painted_like_its_label() {
    var sb = make()
    var icon = find(sb, "navIconBoard")
    var row = find(sb, "navBoard")
    compare(icon.color, row.foreground)
    verify(icon.mapToItem(row, 0, 0).x < find(sb, "navBoard").width / 2, "the icon leads the row")
  }
  function test_each_section_carries_its_own_glyph() {
    var sb = make()
    var wanted = {
      navIconBoard: "\uf0db",        // columns
      navIconGraph: "\uf0e8",        // sitemap
      navIconDocuments: "\uf15c",    // file-lines
      navIconMemories: "\udb82\uddd1", // brain (U+F09D1)
      navIconIssues: "\uf188"        // bug
    }
    for (var name in wanted) compare(String(find(sb, name).text), wanted[name], name)
  }

  function test_the_sidebar_lists_issues_last_with_its_own_icon() {
    var sb = make()
    var row = find(sb, "navIssues")
    verify(row, "the Issues nav row")
    compare(String(find(sb, "navIconIssues").text), "\uf188")
    verify(row.y > find(sb, "navMemories").y, "Issues comes after Memories, so it is Ctrl+5")
    click(row)
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "issues")
  }

  function test_runs_attention_defaults_to_nothing() {
    var sb = make()
    compare(sb.runsAttention, 0)
    compare(sb.runsAttentionText, "")
  }

  function test_runs_attention_text_follows_the_count() {
    var sb = make()
    sb.runsAttention = 3
    compare(sb.runsAttentionText, RG.glyphOf("escalated") + "3")
    compare(sb.runsAttentionText, "‼3", "the shared escalated glyph, no space")
    sb.runsAttention = 0
    compare(sb.runsAttentionText, "")
    sb.runsAttention = -2
    compare(sb.runsAttentionText, "", "a negative count shows nothing")
  }

  function test_existing_rows_show_no_count() {
    var sb = make()
    sb.runsAttention = 5
    wait(20)
    var names = ["navCountBoard", "navCountGraph", "navCountDocuments", "navCountMemories", "navCountIssues"]
    for (var i = 0; i < names.length; i++) {
      var count = find(sb, names[i])
      verify(count, names[i] + " slot exists")
      compare(count.visible, false, names[i] + " stays hidden: no existing row sets countText")
    }
  }

  function test_a_row_given_a_count_shows_it_after_its_label_in_urgent() {
    var sb = make()
    var row = find(sb, "navBoard")
    row.countText = "‼2"
    wait(20)
    var count = find(sb, "navCountBoard")
    compare(count.visible, true)
    compare(String(count.text), "‼2")
    verify(Qt.colorEqual(count.color, sb.theme.urgent), "the count reads in urgent")
    var label = find(sb, "navLabelBoard")
    verify(label, "navLabelBoard exists")
    verify(count.mapToItem(row, 0, 0).x > find(sb, "navIconBoard").mapToItem(row, 0, 0).x,
      "the count follows the icon")
    verify(count.mapToItem(row, 0, 0).x >= label.mapToItem(row, 0, 0).x + label.width,
      "the count follows the label")
    row.countText = ""
    wait(20)
    compare(count.visible, false)
  }

  // ---- the Runs row (5.1)

  function test_the_runs_row_comes_after_issues_with_its_own_icon() {
    var sb = make()
    var row = find(sb, "navRuns")
    verify(row, "the Runs nav row")
    compare(String(find(sb, "navLabelRuns").text), "Runs")
    compare(String(find(sb, "navIconRuns").text), "\uf04b")
    verify(row.y > find(sb, "navIssues").y, "Runs comes after Issues, so it is Ctrl+6")
    var others = ["navIconBoard", "navIconGraph", "navIconDocuments", "navIconMemories", "navIconIssues"]
    for (var i = 0; i < others.length; i++)
      verify(String(find(sb, others[i]).text) !== "\uf04b", others[i] + " draws a different glyph")
    compare(find(sb, "navIconRuns").font.pixelSize, find(sb, "navIconBoard").font.pixelSize)
    click(row)
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "runs")
  }

  function test_the_runs_row_is_enabled_without_a_project() {
    var sb = make()
    sb.selectedProject = null
    compare(find(sb, "navRuns").enabled, true)
    click(find(sb, "navRuns"))
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "runs")
  }

  function test_without_a_project_only_the_runs_row_is_enabled() {
    var sb = make()
    sb.selectedProject = null
    var bound = ["navBoard", "navGraph", "navDocuments", "navMemories", "navIssues"]
    for (var i = 0; i < bound.length; i++) {
      compare(find(sb, bound[i]).enabled, false, bound[i])
      click(find(sb, bound[i]))
    }
    compare(sectionSpy.count, 0, "no bound row emits a section")
    compare(find(sb, "deleteButton").enabled, false)
    compare(find(sb, "navRuns").enabled, true)
  }

  function test_the_runs_row_shows_the_attention_count() {
    var sb = make()
    var count = find(sb, "navCountRuns")
    verify(count, "the Runs count slot")
    compare(count.visible, false, "no count at 0")
    sb.runsAttention = 2
    wait(20)
    compare(count.visible, true)
    compare(String(count.text), "‼2")
    sb.runsAttention = 0
    wait(20)
    compare(count.visible, false)
  }
}
