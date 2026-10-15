import QtQuick
import qs.Commons
import qs.Commons as Cm

// The colours and font sizes every view and component draws with. Not a
// singleton: Panel.qml creates one bound to the bar's palette and passes it
// down, and every component keeps a default one so it renders standalone.
QtObject {
  id: theme

  property color foreground: Cm.Color.foreground
  property color dim: Qt.darker(theme.foreground, 1.55)
  property color urgent: Cm.Color.urgent
  property string fontFamily: Style.font.family

  property real bodySize: Style.font.body
  // The slightly smaller body size the markdown bodies and link rows use.
  property real smallSize: Style.font.bodySmall
  property real captionSize: Style.font.caption
  property real headingSize: Style.font.heading
}
