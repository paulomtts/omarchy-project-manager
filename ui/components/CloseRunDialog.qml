import QtQuick
import qs.Commons
import qs.Commons as Cm
import "../components" as UI
import "../theme" as T
import "themeToken.js" as Tokens

// The Close dialog over a dimmed backdrop: `Close "<runTitle>"?`, that the run
// is recorded as cancelled and nothing is deleted, where else a card of the
// run is still open (`openIn`), `error` in urgent, then Keep and an orange
// Close. No typed confirmation. Renders and emits only: reads shown, runTitle,
// openIn, error, busy and theme and never changes them. Emits
// confirmRequested() for a click on Close, and cancelRequested() for Keep, the
// backdrop or Escape; Return never confirms. While busy nothing emits.
// focusItem is a key-only item that takes the focus when the dialog is shown.
// objectNames: closeDialogBackdrop, closeDialogCard, closeDialogTitle,
// closeDialogBody, closeDialogOpenIn, closeDialogError, closeDialogKeep,
// closeDialogAccept.
Item {
  id: dialog
  objectName: "closeRunDialog"
  z: 100

  property bool shown: false
  // The run's title as the row shows it.
  property string runTitle: ""
  // Another run in which a card of this run is still open, or blank.
  property string openIn: ""
  property string error: ""
  property bool busy: false
  // Colours and fonts; null falls back to the shell's Color.
  property var theme: T.Theme {}

  readonly property color closeColor: Tokens.token(dialog.theme, "closeTone", "#ff9442")
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Cm.Color.urgent
  readonly property Item focusItem: keyItem

  signal confirmRequested()
  signal cancelRequested()

  visible: shown
  onShownChanged: dialog.takeFocus()
  Component.onCompleted: dialog.takeFocus()

  function takeFocus() {
    if (dialog.shown) keyItem.forceActiveFocus()
  }

  // Escape cancels unless busy, and is swallowed either way; Return and Enter
  // are left alone, so they never confirm. A hidden item keeps its focus, so
  // a hidden dialog leaves every key alone.
  Item {
    id: keyItem
    objectName: "closeDialogKeys"
    Keys.onPressed: function(event) {
      if (!dialog.shown || event.key !== Qt.Key_Escape) return
      if (!dialog.busy) dialog.cancelRequested()
      event.accepted = true
    }
  }

  UI.ModalCard {
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(440)
    backdropObjectName: "closeDialogBackdrop"
    cardObjectName: "closeDialogCard"
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      objectName: "closeDialogTitle"
      variant: "heading"
      theme: dialog.theme
      width: parent.width
      text: dialog.runTitle.trim() === "" ? "Close this run?" : "Close \"" + dialog.runTitle + "\"?"
      textFormat: Text.PlainText
      font.bold: true
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "closeDialogBody"
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: "The run is recorded as cancelled. Nothing is deleted and no branch is touched."
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "closeDialogOpenIn"
      variant: "small"
      theme: dialog.theme
      visible: dialog.openIn.trim() !== ""
      width: parent.width
      text: "A card of this run is also open in run " + dialog.openIn.trim() + "; it stays continuable there."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "closeDialogError"
      variant: "small"
      theme: dialog.theme
      visible: dialog.error !== ""
      width: parent.width
      text: dialog.error
      textFormat: Text.PlainText
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        objectName: "closeDialogKeep"
        text: "Keep"
        enabled: !dialog.busy
        theme: dialog.theme
        onClicked: if (!dialog.busy) dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "closeDialogAccept"
        text: "Close"
        enabled: !dialog.busy
        foreground: dialog.closeColor
        theme: dialog.theme
        onClicked: if (!dialog.busy) dialog.confirmRequested()
      }
    }
  }
}
