import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "ListRow"
  when: windowShown
  visible: true
  width: 400; height: 300

  T.Theme { id: tcTheme; foreground: "#00ff00" }

  Component {
    id: rowC
    UI.ListRow {
      width: 300
      theme: tcTheme
      UI.ThemedText { objectName: "rowLabel"; theme: tcTheme; width: parent.width; text: "a row" }
    }
  }

  SignalSpy { id: hoverSpy; signalName: "hovered" }
  SignalSpy { id: activateSpy; signalName: "activated" }
  SignalSpy { id: revealSpy; signalName: "revealRequested" }

  function make() {
    var row = createTemporaryObject(rowC, tc)
    var spies = [hoverSpy, activateSpy, revealSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = row; spies[i].clear() }
    return row
  }

  function test_the_declared_children_are_the_rows_content() {
    var row = make()
    var label = H.find(row, "rowLabel")
    verify(label)
    compare(label.text, "a row")
    verify(row.implicitHeight > label.implicitHeight)
    compare(row.implicitHeight, label.implicitHeight + Style.spacing.rowPaddingX)
  }

  function test_the_cursor_is_on_the_row_whose_index_matches() {
    var row = make()
    row.index = 2
    compare(row.hasCursor, false)
    row.cursorIndex = 2
    compare(row.hasCursor, true)
    row.cursorIndex = 1
    compare(row.hasCursor, false)
  }

  function test_a_row_without_an_index_never_has_the_cursor() {
    var row = make()
    row.index = -1
    row.cursorIndex = -1
    compare(row.hasCursor, false)
  }

  function test_only_a_keyboard_move_asks_for_a_reveal() {
    var row = make()
    row.index = 1
    row.scrollOnCursor = false
    row.cursorIndex = 1
    compare(revealSpy.count, 0)
    row.cursorIndex = 0
    row.scrollOnCursor = true
    row.cursorIndex = 1
    compare(revealSpy.count, 1)
    compare(revealSpy.signalArguments[0][0], row)
  }

  function test_hovering_reports_the_index_and_clicking_activates() {
    var row = make()
    row.index = 3
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 3)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(activateSpy.count, 1)
  }

  function test_a_row_without_an_index_reports_no_hover() {
    var row = make()
    row.index = -1
    mouseMove(row, row.width / 2, row.height / 2)
    compare(hoverSpy.count, 0)
    mouseClick(row, row.width / 2, row.height / 2)
    compare(activateSpy.count, 1)
  }

  function test_the_content_is_inset_by_the_content_margin() {
    var row = make()
    var label = H.find(row, "rowLabel")
    compare(label.parent.x, Style.space(10))
    row.contentMargin = Style.space(6)
    compare(label.parent.x, Style.space(6))
  }

  function test_it_draws_with_the_themes_foreground() {
    var row = make()
    compare(row.foreground, Qt.color("#00ff00"))
  }

  // ---- the actions slot (S2 4.2, D2)

  Component {
    id: actionRowC
    UI.ListRow {
      width: 300
      theme: tcTheme
      UI.ThemedText { objectName: "rowLabel"; theme: tcTheme; width: parent.width; text: "a row" }
      actions: [
        UI.ActionButton { objectName: "rowButton"; theme: tcTheme; text: "Go" }
      ]
    }
  }

  SignalSpy { id: buttonSpy; signalName: "clicked" }

  function makeWithAction() {
    var row = createTemporaryObject(actionRowC, tc)
    var spies = [hoverSpy, activateSpy, revealSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = row; spies[i].clear() }
    buttonSpy.target = H.find(row, "rowButton")
    buttonSpy.clear()
    wait(20)
    return row
  }

  function test_an_empty_actions_slot_leaves_the_row_as_it_was() {
    var row = make()
    var label = H.find(row, "rowLabel")
    compare(row.actionsExtent, 0)
    compare(row.implicitHeight, label.implicitHeight + Style.spacing.rowPaddingX)
    fuzzyCompare(label.parent.y, (row.height - label.parent.height) / 2, 0.5, "the content stays centred")
  }

  function test_an_action_sits_under_the_content_and_adds_its_height_and_the_spacing() {
    var row = makeWithAction()
    var label = H.find(row, "rowLabel")
    var button = H.find(row, "rowButton")
    verify(button)
    fuzzyCompare(row.implicitHeight, label.implicitHeight + button.height + Style.space(2) + Style.spacing.rowPaddingX, 0.01)
    fuzzyCompare(label.parent.y, Style.spacing.rowPaddingX / 2, 0.5, "the content keeps its top inset")
    var b = button.mapToItem(row, 0, 0)
    var l = label.mapToItem(row, 0, 0)
    verify(b.y >= l.y + label.height, "the button is under the content")
    fuzzyCompare(b.x, Style.space(10), 0.5, "inside the content margin")
  }

  function test_a_hidden_action_takes_no_room() {
    var row = makeWithAction()
    var label = H.find(row, "rowLabel")
    H.find(row, "rowButton").visible = false
    wait(20)   // a Column re-lays out on the next polish, not synchronously
    compare(row.actionsExtent, 0)
    compare(row.implicitHeight, label.implicitHeight + Style.spacing.rowPaddingX)
  }

  function test_clicking_an_action_does_not_activate_the_row() {
    var row = makeWithAction()
    mouseClick(H.find(row, "rowButton"))
    compare(buttonSpy.count, 1)
    compare(activateSpy.count, 0)
  }

  function test_clicking_the_content_still_activates_a_row_with_actions() {
    var row = makeWithAction()
    mouseClick(H.find(row, "rowLabel"))
    compare(activateSpy.count, 1)
    compare(buttonSpy.count, 0)
  }

  // Review Focus 1: a disabled button lets the click through its own
  // MouseArea; the strip must still keep it from the row.
  function test_clicking_a_disabled_action_does_not_activate_the_row() {
    var row = makeWithAction()
    var button = H.find(row, "rowButton")
    button.enabled = false
    mouseClick(button)
    compare(buttonSpy.count, 0)
    compare(activateSpy.count, 0)
  }

  // Review Focus 4.
  function test_hovering_a_row_with_actions_reports_its_index() {
    var row = makeWithAction()
    row.index = 4
    // The mouse keeps its position between tests: park it outside the row (the
    // TestCase is 400x300, the row 300 wide) so the move into the content is an
    // enter.
    mouseMove(tc, 390, 290)
    mouseMove(row, row.width / 2, 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 4)
  }
}
