// tests/core/stores/tst_navigation_store.qml
import QtQuick
import QtTest

TestCase {
  id: tc
  name: "StoresNavigationStore"

  function make() {
    var comp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc)
  }

  function test_the_section_and_its_title_follow_the_view_mode() {
    var n = make(); if (!n) return
    compare(n.viewMode, "board")
    compare(n.section, "board")
    compare(n.sectionTitle, "Board")
    n.viewMode = "documents"
    compare(n.section, "documents"); compare(n.sectionTitle, "Documents")
    n.viewMode = "document"
    compare(n.section, "documents"); compare(n.sectionTitle, "Documents")
    n.viewMode = "memories"
    compare(n.section, "memories"); compare(n.sectionTitle, "Memories")
    n.viewMode = "memory"
    compare(n.section, "memories"); compare(n.sectionTitle, "Memories")
    n.viewMode = "graph"
    compare(n.section, "graph"); compare(n.sectionTitle, "Graph")
  }

  function test_the_issues_view_modes_share_one_section() {
    var nav = make(); if (!nav) return
    nav.viewMode = "issues"
    compare(nav.section, "issues")
    compare(nav.sectionTitle, "Issues")
    nav.viewMode = "issue"
    compare(nav.section, "issues")
    compare(nav.sectionTitle, "Issues")
  }

  function test_the_runs_view_modes_share_one_section() {
    var nav = make(); if (!nav) return
    nav.viewMode = "runs"
    compare(nav.section, "runs")
    compare(nav.sectionTitle, "Runs")
    nav.viewMode = "run"
    compare(nav.section, "runs")
    compare(nav.sectionTitle, "Runs")
  }

  // A card opened from an issue is still the Issues section, so the sidebar
  // keeps Issues lit and the trail keeps saying "Issues".
  function test_a_card_opened_from_an_issue_keeps_the_issues_section() {
    var nav = make(); if (!nav) return
    nav.viewMode = "entry"
    nav.returnMode = "issues"
    compare(nav.section, "issues")
    compare(nav.sectionTitle, "Issues")
  }

  function test_a_card_opened_from_the_graph_keeps_the_graph_section() {
    var n = make(); if (!n) return
    n.viewMode = "entry"
    n.returnMode = "board"
    compare(n.section, "board")
    n.returnMode = "graph"
    compare(n.section, "graph")
    compare(n.sectionTitle, "Graph")
  }

  function test_reset_search_clears_the_query_and_the_cursor() {
    var n = make(); if (!n) return
    n.searchQuery = "design"
    n.cursorIndex = 4
    n.resetSearch()
    compare(n.searchQuery, "")
    compare(n.cursorIndex, 0)
  }

  function test_move_cursor_clamps_to_the_list_and_arms_keyboard_scrolling() {
    var n = make(); if (!n) return
    n.scrollOnCursor = false
    n.moveCursor(1, 3)
    compare(n.cursorIndex, 1)
    compare(n.scrollOnCursor, true)
    n.moveCursor(5, 3)
    compare(n.cursorIndex, 2)
    n.moveCursor(-9, 3)
    compare(n.cursorIndex, 0)
  }

  function test_move_cursor_does_nothing_on_an_empty_list() {
    var n = make(); if (!n) return
    n.cursorIndex = 0
    n.scrollOnCursor = false
    n.moveCursor(1, 0)
    compare(n.cursorIndex, 0)
    compare(n.scrollOnCursor, false)
  }

  function test_hover_within_300ms_of_a_key_move_does_not_steal_the_cursor() {
    var n = make(); if (!n) return
    n.moveCursor(1, 4)
    compare(n.cursorIndex, 1)
    n.hoverCursor(0)
    compare(n.cursorIndex, 1)
    wait(400)
    n.hoverCursor(0)
    compare(n.cursorIndex, 0)
    compare(n.scrollOnCursor, false)
  }

  function test_push_and_pop_return_round_trip_the_list_position() {
    var n = make(); if (!n) return
    n.viewMode = "graph"
    n.cursorIndex = 7
    n.pushReturn(120, n.viewMode)
    n.viewMode = "entry"
    n.cursorIndex = 0
    var back = n.popReturn()
    compare(back.mode, "graph")
    compare(back.cursor, 7)
    compare(back.scrollY, 120)
  }

  function test_push_return_without_a_mode_keeps_the_previous_return_mode() {
    var n = make(); if (!n) return
    n.returnMode = "graph"
    n.cursorIndex = 2
    n.pushReturn(40)
    compare(n.returnMode, "graph")
    compare(n.returnCursor, 2)
    compare(n.returnScrollY, 40)
  }

  function test_toggling_the_dropdown_opens_it_on_the_given_row_and_closes_it_clean() {
    var n = make(); if (!n) return
    n.dropdownQuery = "left over"
    n.toggleDropdown(2)
    compare(n.dropdownOpen, true)
    compare(n.dropdownCursor, 2)
    compare(n.dropdownQuery, "")
    n.dropdownQuery = "x"
    n.toggleDropdown(0)
    compare(n.dropdownOpen, false)
    compare(n.dropdownQuery, "")
  }

  function test_closing_a_closed_dropdown_does_nothing() {
    var n = make(); if (!n) return
    n.dropdownQuery = "kept"
    n.closeDropdown()
    compare(n.dropdownOpen, false)
    compare(n.dropdownQuery, "kept")
  }

  function test_dropdown_movement_clamps_to_the_filtered_list() {
    var n = make(); if (!n) return
    n.toggleDropdown(0)
    n.moveDropdown(1, 3)
    compare(n.dropdownCursor, 1)
    n.moveDropdown(9, 3)
    compare(n.dropdownCursor, 2)
    n.moveDropdown(-9, 3)
    compare(n.dropdownCursor, 0)
    n.moveDropdown(1, 0)
    compare(n.dropdownCursor, 0)
  }

  // An open run goes back to the Runs list unless a card's RUNS row opened it
  // (Navigator sets "entry" then; tst_navigator.qml covers that path).
  function test_a_run_returns_to_the_runs_list_by_default() {
    var n = make(); if (!n) return
    compare(n.runReturnMode, "runs")
  }
}
