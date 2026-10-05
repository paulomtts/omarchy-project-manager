import QtQuick
import qs.Commons
import qs.Ui
import "../theme" as T

// One row of a keyboard-navigable list: the cursor highlight, the reveal a
// keyboard move asks for, and the hover/click handling every list row in the
// panel shares. The declared children go into the row's content column; the
// items in `actions` go into a second column under it, stacked above the row's
// MouseArea, so a button there takes its own click and the row does not
// activate for it.
CursorSurface {
  id: row

  // -1 means "not a row of the list": it never takes the cursor and never
  // reports a hover (the card detail's link rows use that for a link that is
  // not in the cursor's list).
  property int index: -1
  property int cursorIndex: -1
  property bool scrollOnCursor: false
  property var theme: null
  property real contentMargin: Style.space(10)
  property int hoverCursorShape: Qt.PointingHandCursor

  default property alias content: contentColumn.data
  // Buttons and the lines that go with them, under the content.
  property alias actions: actionsColumn.data
  readonly property var palette: row.theme || rowTheme
  // The actions' share of the row: nothing at all while no action item has a
  // height, so a row without actions is exactly as tall as it always was.
  readonly property real actionsExtent: actionsColumn.implicitHeight > 0
    ? actionsColumn.implicitHeight + contentColumn.spacing : 0

  signal hovered(int index)
  signal activated()
  signal revealRequested(var item)

  implicitHeight: contentColumn.implicitHeight + row.actionsExtent + Style.spacing.rowPaddingX
  hasCursor: row.index >= 0 && row.cursorIndex === row.index
  foreground: row.palette ? row.palette.foreground : Color.foreground
  onHasCursorChanged: if (hasCursor && row.scrollOnCursor) row.revealRequested(row)

  Column {
    id: contentColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -row.actionsExtent / 2
    anchors.leftMargin: row.contentMargin
    anchors.rightMargin: row.contentMargin
    spacing: Style.space(2)
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.hoverCursorShape
    onEntered: if (row.index >= 0) row.hovered(row.index)
    onClicked: row.activated()
  }

  // Above the row's MouseArea. A click anywhere in this strip stays in it: a
  // button takes it, and a disabled button or the gap beside one never opens
  // the row.
  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: contentColumn.bottom
    anchors.topMargin: row.actionsExtent > 0 ? contentColumn.spacing : 0
    anchors.leftMargin: row.contentMargin
    anchors.rightMargin: row.contentMargin
    height: actionsColumn.implicitHeight

    MouseArea { anchors.fill: parent }

    Column {
      id: actionsColumn
      width: parent.width
      spacing: contentColumn.spacing
    }
  }

  T.Theme { id: rowTheme }
}
