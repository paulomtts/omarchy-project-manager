import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// The run toasts: one card per run that newly needs a human, oldest at the
// top and newest at the bottom, closest to the corner the owner puts it in.
// Each card reads `‼ Run needs you` (or `✖` for a dead run, from runGlyphs.js)
// in `urgent`, `<title> escalated` or `<title> died`, the reason, and Open /
// Dismiss.
//
// Presentation only, like RunControls: it imports no store. The owner passes
// RunStore.toasts ({key, id, title, state, reason, project, expiresMs}, oldest first)
// and handles openRequested(key, runId) and dismissRequested(key); Open does
// not dismiss by itself. A bad entry still renders and still offers Dismiss
// (key -1). With no toasts it is hidden and 0 tall.
Column {
  id: stack

  property var theme: T.Theme {}
  property var toasts: []

  signal openRequested(int key, string runId)
  signal dismissRequested(int key)

  // Not Array.isArray: a list handed in through createObject's property map
  // (the component test) arrives as a QML list, for which Array.isArray is
  // false although length and indexing work, so every toast would vanish.
  readonly property int count: stack.toasts && typeof stack.toasts === "object" && typeof stack.toasts.length === "number"
    ? stack.toasts.length : 0

  // The entry at index, read back out of `toasts` (a Repeater would hand the
  // delegate a converted copy); {} when it is not an object.
  function entryOf(index) {
    var t = index >= 0 && index < stack.count ? stack.toasts[index] : null
    return t !== null && t !== undefined && typeof t === "object" ? t : {}
  }

  function textOf(value) { return typeof value === "string" ? value : "" }

  function keyOf(entry) { return typeof entry.key === "number" ? entry.key : -1 }

  function lineOf(entry) {
    return stack.textOf(entry.title) + (entry.state === "dead" ? " died" : " escalated")
  }

  width: Style.space(320)
  spacing: Style.space(6)
  visible: stack.count > 0

  Repeater {
    model: stack.count

    delegate: Rectangle {
      id: card
      required property int index
      readonly property var entry: stack.entryOf(card.index)

      objectName: "runToast" + card.index
      width: stack.width
      height: body.implicitHeight + Style.space(20)
      radius: Style.space(8)
      color: Color.popups.background
      border.width: 1
      border.color: stack.theme.urgent

      // Takes the clicks between the buttons, so none reaches what is under it.
      MouseArea { anchors.fill: parent }

      Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        spacing: Style.space(4)

        UI.ThemedText {
          objectName: "runToastHeading" + card.index
          theme: stack.theme
          width: parent.width
          text: RunGlyphs.glyphOf(card.entry.state) + " Run needs you"
          color: stack.theme.urgent
          font.bold: true
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastLine" + card.index
          theme: stack.theme
          width: parent.width
          text: stack.lineOf(card.entry)
          elide: Text.ElideRight
        }

        UI.ThemedText {
          objectName: "runToastReason" + card.index
          variant: "caption"
          theme: stack.theme
          width: parent.width
          visible: text !== ""
          text: stack.textOf(card.entry.reason)
          wrapMode: Text.WordWrap
        }

        Row {
          x: parent.width - width
          spacing: Style.space(6)

          UI.ActionButton {
            objectName: "runToastOpen" + card.index
            theme: stack.theme
            text: "Open"
            onClicked: stack.openRequested(stack.keyOf(card.entry), stack.textOf(card.entry.id))
          }

          UI.ActionButton {
            objectName: "runToastDismiss" + card.index
            theme: stack.theme
            text: "Dismiss"
            onClicked: stack.dismissRequested(stack.keyOf(card.entry))
          }
        }
      }
    }
  }
}
