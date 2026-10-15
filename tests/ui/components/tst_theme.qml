import QtQuick
import QtTest
import qs.Commons
import qs.Commons as Cm
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "Theme"

  Component { id: themeC; T.Theme {} }
  Component { id: tunedC; T.Theme { foreground: "#ff0000" } }

  function test_it_defaults_to_the_shell_colours_and_font() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.foreground, Cm.Color.foreground)
    compare(theme.urgent, Cm.Color.urgent)
    compare(theme.fontFamily, Style.font.family)
  }

  function test_dim_follows_the_foreground() {
    var theme = createTemporaryObject(tunedC, tc)
    compare(theme.dim, Qt.darker("#ff0000", 1.55))
  }

  function test_it_carries_the_three_font_sizes() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.bodySize, Style.font.body)
    compare(theme.captionSize, Style.font.caption)
    compare(theme.headingSize, Style.font.heading)
  }

  function test_it_carries_the_small_body_size_too() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.smallSize, Style.font.bodySmall)
  }
}
