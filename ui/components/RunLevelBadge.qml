import QtQuick
import qs.Commons
import "../theme" as T
import "themeToken.js" as Tokens

// A run's level (milestone, story or subtask) as an upper-cased caption in a
// small 4px-radius rectangle. Every level is the same shape: the milestone has
// a 2px border and a 22% fill, the story a 1px border and a 12% fill, the
// subtask a 1px border and no fill. Not a Badge, which is a pill. Presentation
// only: `level` is Runs.runLevel's string, and anything but "subtask" or
// "story" reads as a milestone.
Rectangle {
  id: levelBadge
  objectName: "runLevelBadge"

  // The owner's Theme, or none: `palette` then falls back to the badge's own.
  // Both are objects, and tearing a view down nulls them while the bindings
  // below still run once, so every read of `palette` is guarded; the guard's
  // value is never painted.
  property var theme: null
  property string level: ""

  readonly property var palette: levelBadge.theme || levelTheme
  readonly property string shownLevel: (levelBadge.level === "subtask" || levelBadge.level === "story")
    ? levelBadge.level : "milestone"
  readonly property color levelColor: levelBadge.shownLevel === "subtask"
    ? Tokens.token(levelBadge.palette, "levelSubtask", "#5d70b8")
    : levelBadge.shownLevel === "story" ? Tokens.token(levelBadge.palette, "levelStory", "#8196ee")
    : Tokens.token(levelBadge.palette, "levelMilestone", "#aab8ff")

  width: label.implicitWidth + Style.space(12)
  height: label.implicitHeight + Style.space(4)
  radius: Style.space(4)
  border.width: levelBadge.shownLevel === "milestone" ? 2 : 1
  border.color: levelBadge.levelColor
  color: levelBadge.shownLevel === "milestone" ? Qt.alpha(levelBadge.levelColor, 0.22)
    : levelBadge.shownLevel === "story" ? Qt.alpha(levelBadge.levelColor, 0.12)
    : "transparent"

  ThemedText {
    id: label
    objectName: "runLevelBadgeText"
    anchors.centerIn: parent
    theme: levelBadge.palette
    variant: "caption"
    text: levelBadge.shownLevel.toUpperCase()
    color: levelBadge.levelColor
  }

  T.Theme { id: levelTheme }
}
