import QtQuick
import qs.Commons
import "../theme" as T

// A bounded list that scrolls itself and follows its bottom. Presentation only.
//   model: the rows, any ListView model. rowDelegate draws one row and sizes
//     itself; the list's width is ListView.view.width.
//   maxHeight: the list's height cap; past it the list scrolls itself and a
//     wheel at its ends reaches the enclosing Flickable.
//   listName / jumpName: objectNames of the inner ListView and Jump button.
//   following (read-only): true while the list is at its bottom (its rows fit,
//     or contentY is within 1 px of it). While true, new or taller rows, a new
//     model and a new height keep the list at its bottom; otherwise a new model
//     or height keeps contentY within the new bounds. A scroll sets it to
//     whether the list is at its bottom. While false and the list can scroll,
//     "Jump ↓" under the list, or jump(), puts the list at its bottom and sets it.
//   With no rows it is not visible and takes no room in a Column.
Item {
  id: tail
  objectName: "tailScroll"

  // The owner's Theme, or none: `palette` then falls back to TailScroll's own.
  property var theme: null
  property var model: []
  property Component rowDelegate: null
  property real maxHeight: Style.space(320)
  property string listName: "tailList"
  property string jumpName: "tailJump"

  readonly property var palette: tail.theme || tailTheme
  readonly property bool following: tail._following
  property bool _following: true
  property bool _relayout: false

  // True when the list's rows fit or its contentY is within 1 px of its bottom.
  function _atBottom() {
    return list.contentHeight <= list.height
      || Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // y within the list's scroll bounds; a list that fits gets its top.
  function _clamped(y) {
    return Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
  }

  // Puts the list at its bottom; contentY moves made here are not a user scroll.
  function _toBottom() {
    tail._relayout = true
    list.forceLayout()
    list.positionViewAtEnd()
    tail._relayout = false
  }

  // Hands model to the list. A new model puts a ListView back at its top, so
  // a following list goes to its bottom and any other keeps its contentY,
  // within its new bounds.
  function _showRows() {
    tail._relayout = true
    var y = list.contentY
    list.model = tail.model
    list.forceLayout()
    if (tail._following) list.positionViewAtEnd()
    else list.contentY = tail._clamped(y)
    tail._relayout = false
    tail._following = tail._atBottom()
  }

  // Puts the list at its bottom and sets following.
  function jump() {
    tail._toBottom()
    tail._following = true
  }

  visible: list.count > 0
  implicitHeight: column.implicitHeight
  onModelChanged: tail._showRows()
  Component.onCompleted: tail._showRows()

  Column {
    id: column
    width: tail.width
    spacing: Style.space(6)

    ListView {
      id: list
      objectName: tail.listName
      visible: list.count > 0
      width: parent.width
      height: Math.min(list.contentHeight, tail.maxHeight)
      clip: true
      orientation: ListView.Vertical
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds
      delegate: tail.rowDelegate
      onContentYChanged: if (!tail._relayout) tail._following = tail._atBottom()
      onContentHeightChanged: if (tail._following && !tail._relayout) tail._toBottom()
      // A height that is not followed keeps contentY in bounds; that move is a scroll.
      onHeightChanged: {
        if (tail._relayout) return
        if (tail._following) tail._toBottom()
        else list.contentY = tail._clamped(list.contentY)
      }
    }

    Item {
      width: parent.width
      height: jumpButton.height
      visible: list.visible && list.contentHeight > list.height && !tail._following

      ActionButton {
        id: jumpButton
        objectName: tail.jumpName
        anchors.right: parent.right
        theme: tail.palette
        text: "Jump ↓"
        onClicked: tail.jump()
      }
    }
  }

  T.Theme { id: tailTheme }
}
