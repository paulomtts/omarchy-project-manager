import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// A modal card over a dimmed backdrop that asks for a typed word before a
// destructive action. Renders and emits only.
Item {
  id: dialog
  objectName: "typedConfirmDialog"
  z: 100

  property bool shown: false
  property string message: ""
  property string detail: ""
  property string confirmLabel: "Confirm delete"
  property string busyLabel: "Working…"
  property bool busy: false
  property string error: ""
  // The typed word, when the owner keeps it (the store owns it for the
  // project delete); typedEdited reports every change back.
  property string typedText: ""
  // The callers' tests look these up by name.
  property string backdropObjectName: "confirmBackdrop"
  property string cardObjectName: "confirmCard"
  property string fieldObjectName: "confirmTyped"
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  // The word the user has to type, matched trimmed and case-blind; it is also
  // the field's placeholder. A blank word never confirms.
  property string confirmWord: "delete"
  // The safe button's text. A run cancel says "Keep running", so the way out
  // never reads like the destructive "Cancel run" beside it.
  property string dismissLabel: "Cancel"
  readonly property Item focusItem: field
  readonly property bool confirmed: {
    var word = dialog.confirmWord.trim().toLowerCase()
    return word !== "" && String(field.text).trim().toLowerCase() === word
  }

  signal confirmRequested()
  signal cancelRequested()
  signal typedEdited(string text)

  visible: shown
  // The field is cleared when the dialog closes and re-synced from the owner
  // when it opens; no binding is relied on, so an owner that keeps the typed
  // word (the project delete store) stays in step after any reopen.
  onShownChanged: field.text = shown ? dialog.typedText : ""
  onTypedTextChanged: if (field.text !== dialog.typedText) field.text = dialog.typedText

  UI.ModalCard {
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(440)
    backdropObjectName: dialog.backdropObjectName
    cardObjectName: dialog.cardObjectName
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: dialog.message
      color: dialog.theme.urgent
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      variant: "caption"
      theme: dialog.theme
      visible: dialog.detail !== ""
      width: parent.width
      text: dialog.detail
      elide: Text.ElideMiddle
    }

    TextField {
      id: field
      objectName: dialog.fieldObjectName
      width: parent.width
      foreground: dialog.theme.foreground
      placeholderText: dialog.confirmWord
      enabled: !dialog.busy
      text: dialog.typedText

      // Typing tells the owner; an owner-driven change arrives through
      // onTypedTextChanged above and matches, so nothing echoes.
      onTextChanged: if (text !== dialog.typedText) dialog.typedEdited(text)

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { dialog.cancelRequested(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (dialog.confirmed && !dialog.busy) dialog.confirmRequested()
          event.accepted = true
        }
      }
    }

    UI.ThemedText {
      objectName: "confirmError"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.error !== ""
      width: parent.width
      text: dialog.error
      color: dialog.theme.urgent
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        objectName: "confirmCancel"
        text: dialog.dismissLabel
        enabled: !dialog.busy
        opacity: 1
        theme: dialog.theme
        onClicked: dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "confirmAccept"
        text: dialog.busy ? dialog.busyLabel : dialog.confirmLabel
        enabled: !dialog.busy && dialog.confirmed
        tone: "danger"
        theme: dialog.theme
        onClicked: dialog.confirmRequested()
      }
    }
  }
}
