import QtQuick
import qs.Commons
import qs.Commons as Cm

// The modal every dialog in the panel is built from: a dimmed backdrop that
// dismisses on a click, and a centred card that swallows its own clicks. The
// declared children go into the card's column.
Item {
  id: modal

  property bool shown: false
  property bool dismissable: true
  // The card is this wide unless the modal is too narrow for it.
  property real maxWidth: Style.space(440)
  // Negative means "as tall as the content"; a cap clips instead.
  property real maxHeight: -1
  // The callers' tests look the backdrop and the card up by name.
  property string backdropObjectName: "modalBackdrop"
  property string cardObjectName: "modalCard"

  default property alias content: column.data
  readonly property alias cardItem: card

  signal dismissed()

  z: 100
  visible: shown

  Rectangle {
    objectName: modal.backdropObjectName
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)

    MouseArea {
      anchors.fill: parent
      onClicked: if (modal.dismissable) modal.dismissed()
    }
  }

  Rectangle {
    id: card
    objectName: modal.cardObjectName
    anchors.centerIn: parent
    width: Math.min(modal.maxWidth, modal.width - Style.space(48))
    height: modal.maxHeight >= 0 ? Math.min(modal.maxHeight, column.implicitHeight + Style.space(36))
      : column.implicitHeight + Style.space(36)
    radius: Style.space(10)
    color: Cm.Color.popups.background
    border.width: 1
    border.color: Cm.Color.popups.border

    MouseArea { anchors.fill: parent }

    Column {
      id: column
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(8)
    }
  }
}
