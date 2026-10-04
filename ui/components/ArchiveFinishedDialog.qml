import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// The confirmation behind the Board's Archive finished button: each milestone
// that is about to be archived (title, how long it has been idle, how many
// cards it holds), then Archive all or Cancel. Renders and emits only; the
// owner decides what is listed and what a click does. Escape and the backdrop
// cancel, and neither works while a run is busy.
Item {
  id: dialog
  objectName: "archiveDialog"
  z: 100

  property bool shown: false
  // [{id, title, idleDays, cardCount}], from Board.archivable.
  property var candidates: []
  property bool busy: false
  property string error: ""
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  readonly property Item focusItem: keyItem

  signal confirmRequested()
  signal cancelRequested()

  function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s") }

  visible: shown

  Item {
    id: keyItem
    objectName: "archiveKeys"
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) { dialog.cancelRequested(); event.accepted = true }
    }
  }

  UI.ModalCard {
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(520)
    maxHeight: dialog.height - Style.space(48)
    backdropObjectName: "archiveBackdrop"
    cardObjectName: "archiveCard"
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      objectName: "archiveHeading"
      variant: "heading"
      theme: dialog.theme
      text: "Archive finished milestones"
      font.bold: true
    }

    UI.ThemedText {
      variant: "caption"
      theme: dialog.theme
      width: parent.width
      text: "Only the milestone card is archived; its stories and subtasks stay as they are."
      wrapMode: Text.WordWrap
    }

    Flickable {
      id: list
      objectName: "archiveList"
      width: parent.width
      height: Math.min(listColumn.implicitHeight, Style.space(240))
      contentHeight: listColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: listColumn
        width: list.width
        spacing: Style.space(2)

        Repeater {
          model: dialog.candidates

          UI.ListRow {
            id: row
            required property var modelData
            required property int index
            objectName: "archiveRow" + row.index
            width: listColumn.width
            theme: dialog.theme

            UI.ThemedText {
              objectName: "archiveRowTitle" + row.index
              theme: dialog.theme
              width: parent.width
              text: row.modelData.title
              elide: Text.ElideRight
            }

            UI.ThemedText {
              objectName: "archiveRowMeta" + row.index
              variant: "caption"
              theme: dialog.theme
              width: parent.width
              text: "idle " + dialog.plural(row.modelData.idleDays, "day")
                + " · " + dialog.plural(row.modelData.cardCount, "card")
            }
          }
        }
      }
    }

    UI.ThemedText {
      objectName: "archiveError"
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
        objectName: "archiveCancel"
        text: "Cancel"
        enabled: !dialog.busy
        opacity: 1
        theme: dialog.theme
        onClicked: dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "archiveConfirm"
        text: dialog.busy ? "Archiving…" : "Archive all"
        enabled: !dialog.busy && dialog.candidates.length > 0
        theme: dialog.theme
        onClicked: dialog.confirmRequested()
      }
    }
  }
}
