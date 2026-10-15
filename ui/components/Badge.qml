import QtQuick
import qs.Commons
import qs.Commons as Cm
import "../theme" as T

// A small coloured pill: the tint at 18% behind the tint-coloured caption.
Rectangle {
  id: badge

  // The owner's Theme, or none: `palette` then falls back to the badge's own.
  // Both are objects, and tearing a view down nulls them while the bindings
  // below still run once, so every read of `palette` is guarded; the guard's
  // value is never painted.
  property var theme: null
  property string text: ""
  property color tint: badge.palette ? badge.palette.dim : Cm.Color.foreground
  // The badges in the lists are tighter than the one in a memory's header.
  property real paddingY: Style.space(2)
  property alias textObjectName: label.objectName

  readonly property var palette: badge.theme || badgeTheme

  width: label.implicitWidth + Style.space(12)
  height: label.implicitHeight + badge.paddingY
  radius: height / 2
  color: Qt.alpha(label.color, 0.18)

  ThemedText {
    id: label
    anchors.centerIn: parent
    theme: badge.palette
    variant: "caption"
    text: badge.text
    color: badge.tint
  }

  T.Theme { id: badgeTheme }
}
