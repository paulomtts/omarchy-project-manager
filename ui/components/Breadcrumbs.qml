import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Cm
import "../theme" as T

// The trail that says where the panel is: `crumbs` is [{ label, clickable }],
// outermost first. Every crumb but the first is preceded by a chevron; the
// earlier ones are dim and report their index when clicked, and the last one is
// the current location, drawn as the heading and never clickable. It renders
// and emits only -- Navigator.qml builds the list and acts on the clicks.
Item {
  id: bar

  property var crumbs: []
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  signal crumbActivated(int index)

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight
  clip: true

  // A narrow row shrinks the ancestors, never the current location: they may
  // elide down to nothing, while the last crumb keeps at least this much.
  readonly property real currentMinimumWidth: Style.space(96)
  // ... and no single ancestor may eat the row on its own.
  readonly property real ancestorMaximumWidth: Math.max(Style.space(72), bar.width / 4)

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    // The gap before a crumb's chevron; `crumbRow` spaces the chevron from the
    // label after it by the same amount, so the separator sits centred.
    spacing: Style.space(6)

    Repeater {
      model: bar.crumbs

      delegate: Item {
        id: crumb
        required property var modelData
        required property int index
        readonly property bool last: crumb.index === bar.crumbs.length - 1

        objectName: "crumb" + crumb.index
        // The width this crumb wants: its label at full length behind its
        // chevron. Measured from the implicit widths only -- the labels size
        // themselves from the width the layout hands back, so reading their
        // width here would be a loop.
        readonly property real chevronWidth: separator.visible ? separator.implicitWidth + crumbRow.spacing : 0
        readonly property real naturalWidth: label.implicitWidth + crumb.chevronWidth

        implicitWidth: crumb.naturalWidth
        implicitHeight: crumbRow.implicitHeight
        Layout.fillWidth: crumb.last
        Layout.preferredWidth: crumb.naturalWidth
        // The current crumb is the one that must stay readable, so it keeps a
        // floor; an ancestor gets a ceiling and no floor, and elides instead.
        // `bar` is nulled while a torn-down panel runs these bindings one last
        // time, so both reads of it are guarded; the guard is never painted.
        Layout.minimumWidth: crumb.last ? Math.min(crumb.naturalWidth, bar ? bar.currentMinimumWidth : 0) : crumb.chevronWidth
        Layout.maximumWidth: crumb.last ? Number.POSITIVE_INFINITY
          : Math.min(crumb.naturalWidth, bar ? bar.ancestorMaximumWidth : crumb.naturalWidth)

        Row {
          id: crumbRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          spacing: Style.space(6)

          ThemedText {
            id: separator
            objectName: "crumbSeparator" + crumb.index
            visible: crumb.index > 0
            theme: bar.theme
            variant: "caption"
            anchors.verticalCenter: label.verticalCenter
            // Font Awesome chevron-right, drawn in the theme's font like every
            // other icon (tests/architecture/test_icon_glyphs.py checks it).
            text: ""
            color: bar.theme ? bar.theme.dim : Cm.Color.foreground
          }

          ThemedText {
            id: label
            objectName: crumb.last ? "projectHeading" : "crumbText" + crumb.index
            theme: bar.theme
            variant: crumb.last ? "heading" : "dim"
            font.bold: crumb.last
            text: crumb.modelData.label
            elide: Text.ElideRight
            // Whatever the layout left this crumb, minus its chevron: an
            // ancestor squeezed by a long trail elides instead of overflowing.
            width: Math.max(0, crumbRow.width - crumb.chevronWidth)

            MouseArea {
              anchors.fill: parent
              enabled: !!crumb.modelData.clickable
              cursorShape: Qt.PointingHandCursor
              onClicked: bar.crumbActivated(crumb.index)
            }
          }
        }
      }
    }
  }
}
