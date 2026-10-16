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

  // Dark means a dark background, read off a light foreground (luminance above
  // one half). The hexes come from the Runs row design, dark value first.
  property bool dark: 0.2126 * theme.foreground.r + 0.7152 * theme.foreground.g
    + 0.0722 * theme.foreground.b > 0.5
  property color levelMilestone: theme.dark ? "#aab8ff" : "#2b3f9e"
  property color levelStory: theme.dark ? "#8196ee" : "#4a67d6"
  property color levelSubtask: theme.dark ? "#5d70b8" : "#7f93d9"
  property color closeTone: theme.dark ? "#ff9442" : "#c4560a"
  property color warn: theme.dark ? "#f2b84b" : "#a86b00"
  property color accent: theme.dark ? "#7fb069" : "#2f7d32"
}
