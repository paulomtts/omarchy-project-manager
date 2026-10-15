// tests/ui/components/tst_run_level_badge.qml
// ui/components/RunLevelBadge.qml: a run's level as an upper-cased caption in
// a 4px-radius rectangle (not a Badge pill). The milestone has a 2px border and
// a 22% fill, the story 1px and 12%, the subtask 1px and no fill. A level
// token on the theme wins; without one the badge paints RR's dark colour.
import QtQuick
import QtTest
import qs.Commons
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunLevelBadge"
  when: windowShown
  visible: true
  width: 400; height: 200

  // A theme with the level tokens, each a colour nothing else uses.
  QtObject {
    id: tokenTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Token Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
    property color levelMilestone: "#102030"
    property color levelStory: "#405060"
    property color levelSubtask: "#708090"
  }

  // The same theme without the tokens, built here so the fallback case holds
  // whether or not T.Theme has grown the tokens.
  QtObject {
    id: plainTheme
    property color foreground: "#eeeeee"
    property color dim: "#777777"
    property color urgent: "#ff3300"
    property string fontFamily: "Plain Sans"
    property real bodySize: 15
    property real smallSize: 13
    property real captionSize: 11
    property real headingSize: 19
  }

  Component { id: badgeC; UI.RunLevelBadge {} }
  Component { id: themeC; T.Theme {} }

  function make(props) {
    var badge = createTemporaryObject(badgeC, tc, props)
    wait(0)
    return badge
  }

  function labelOf(badge) { return H.find(badge, "runLevelBadgeText") }

  // 1
  function test_level_table_data() {
    return [
      { tag: "milestone", level: "milestone", text: "MILESTONE", border: 2, alpha: 0.22 },
      { tag: "story", level: "story", text: "STORY", border: 1, alpha: 0.12 },
      { tag: "subtask", level: "subtask", text: "SUBTASK", border: 1, alpha: 0 }
    ]
  }

  function test_level_table(data) {
    var badge = make({ theme: tokenTheme, level: data.level })
    compare(badge.objectName, "runLevelBadge")
    compare(badge.shownLevel, data.level)
    compare(labelOf(badge).text, data.text)
    compare(badge.border.width, data.border)
    fuzzyCompare(badge.color.a, data.alpha, 0.01)
    verify(Qt.colorEqual(badge.border.color, badge.levelColor), "the border is the level colour")
    verify(Qt.colorEqual(labelOf(badge).color, badge.levelColor), "the label is the level colour")
    compare(badge.visible, true)
  }

  // 2
  function test_garbage_level_reads_milestone_data() {
    return [
      { tag: "empty", level: "" },
      { tag: "capitalised", level: "Story" },
      { tag: "padded", level: " story" },
      { tag: "unknown", level: "epic" },
      { tag: "proto", level: "__proto__" }
    ]
  }

  function test_garbage_level_reads_milestone(data) {
    var badge = make({ theme: tokenTheme, level: data.level })
    compare(badge.shownLevel, "milestone")
    compare(labelOf(badge).text, "MILESTONE")
    compare(badge.border.width, 2)
    verify(Qt.colorEqual(badge.levelColor, tokenTheme.levelMilestone))
  }

  // 3
  function test_same_rectangle_for_every_level() {
    var levels = ["milestone", "story", "subtask"]
    for (var i = 0; i < levels.length; i++) {
      var badge = make({ theme: tokenTheme, level: levels[i] })
      compare(badge.radius, Style.space(4), levels[i])
      verify(badge.radius < badge.height / 2, levels[i] + " is a rectangle, not a pill")
      verify(badge.width > 0, levels[i] + " has a width")
      verify(badge.height > 0, levels[i] + " has a height")
    }
  }

  // 4
  function test_tokens_win_over_fallbacks() {
    verify(Qt.colorEqual(make({ theme: tokenTheme, level: "milestone" }).levelColor, "#102030"))
    verify(Qt.colorEqual(make({ theme: tokenTheme, level: "story" }).levelColor, "#405060"))
    verify(Qt.colorEqual(make({ theme: tokenTheme, level: "subtask" }).levelColor, "#708090"))
  }

  // 5
  function test_fallbacks_without_tokens() {
    verify(Qt.colorEqual(make({ theme: plainTheme, level: "milestone" }).levelColor, "#aab8ff"))
    verify(Qt.colorEqual(make({ theme: plainTheme, level: "story" }).levelColor, "#8196ee"))
    verify(Qt.colorEqual(make({ theme: plainTheme, level: "subtask" }).levelColor, "#5d70b8"))
  }

  // 6
  function test_label_uses_caption_font() {
    var label = labelOf(make({ theme: tokenTheme, level: "story" }))
    compare(label.font.family, "Token Sans")
    compare(label.font.pixelSize, 11)
  }

  // 7
  function test_level_change_updates_live() {
    var badge = make({ theme: tokenTheme, level: "milestone" })
    compare(labelOf(badge).text, "MILESTONE")
    badge.level = "subtask"
    compare(labelOf(badge).text, "SUBTASK")
    compare(badge.border.width, 1)
    compare(badge.color.a, 0)
    verify(Qt.colorEqual(badge.border.color, "#708090"))
  }

  // 8
  function test_not_a_badge() {
    var badge = make({ theme: tokenTheme, level: "story" })
    compare(badge.paddingY, undefined, "Badge's paddingY is not here")
    compare(badge.textObjectName, undefined, "nor Badge's textObjectName")
  }

  // Review Focus: a theme swapped on a live badge repaints it.
  function test_theme_swap_repaints() {
    var badge = make({ theme: tokenTheme, level: "story" })
    verify(Qt.colorEqual(badge.levelColor, "#405060"))
    badge.theme = plainTheme
    verify(Qt.colorEqual(badge.levelColor, "#8196ee"))
    verify(Qt.colorEqual(labelOf(badge).color, "#8196ee"))
    badge.theme = tokenTheme
    verify(Qt.colorEqual(badge.border.color, "#405060"))
  }

  // Review Focus: a null theme falls back to the badge's own Theme, quietly.
  function test_null_theme_uses_its_own_theme() {
    var own = createTemporaryObject(themeC, tc)
    var expected = own.levelStory === undefined ? "#8196ee" : own.levelStory
    var badge = make({ theme: tokenTheme, level: "story" })
    badge.theme = null
    wait(0)
    verify(Qt.colorEqual(badge.levelColor, expected))
    compare(labelOf(badge).text, "STORY")
    badge.destroy()
    wait(0)
  }
}
