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

  function tokensOf(theme) {
    return [theme.levelMilestone, theme.levelStory, theme.levelSubtask,
            theme.closeTone, theme.warn, theme.accent]
  }

  function compareTokens(theme, hexes) {
    var tokens = tokensOf(theme)
    for (var i = 0; i < hexes.length; ++i)
      compare(tokens[i], Qt.color(hexes[i]), "token " + i)
  }

  function test_a_light_foreground_makes_the_theme_dark() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.dark, true)
  }

  function test_a_dark_foreground_makes_the_theme_light() {
    var theme = createTemporaryObject(themeC, tc, { foreground: "#202020" })
    compare(theme.dark, false)
  }

  function test_the_line_sits_at_half_luminance() {
    compare(createTemporaryObject(themeC, tc, { foreground: "#7f7f7f" }).dark, false)
    compare(createTemporaryObject(themeC, tc, { foreground: "#808080" }).dark, true)
  }

  function test_a_transparent_foreground_makes_the_theme_light() {
    var theme = createTemporaryObject(themeC, tc, { foreground: "transparent" })
    compare(theme.dark, false)
    compare(theme.closeTone, Qt.color("#c4560a"))
  }

  function test_the_dark_tokens_carry_the_designs_dark_values() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    compareTokens(theme, ["#aab8ff", "#8196ee", "#5d70b8", "#ff9442", "#f2b84b", "#7fb069"])
  }

  function test_the_light_tokens_carry_the_designs_light_values() {
    var theme = createTemporaryObject(themeC, tc, { dark: false })
    compareTokens(theme, ["#2b3f9e", "#4a67d6", "#7f93d9", "#c4560a", "#a86b00", "#2f7d32"])
  }

  function test_an_explicit_dark_wins_over_the_foreground() {
    var light = createTemporaryObject(themeC, tc, { foreground: "#ffffff", dark: false })
    compare(light.levelMilestone, Qt.color("#2b3f9e"))
    var dark = createTemporaryObject(themeC, tc, { foreground: "#000000", dark: true })
    compare(dark.levelMilestone, Qt.color("#aab8ff"))
  }

  function test_the_tokens_follow_a_change_of_dark() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    compare(theme.closeTone, Qt.color("#ff9442"))
    theme.dark = false
    compare(theme.closeTone, Qt.color("#c4560a"))
  }

  function test_the_tokens_follow_the_foreground_across_the_line() {
    var theme = createTemporaryObject(themeC, tc)
    compare(theme.levelStory, Qt.color("#8196ee"))
    theme.foreground = "#101010"
    compare(theme.dark, false)
    compare(theme.levelStory, Qt.color("#4a67d6"))
  }

  function test_an_assigned_token_stays_put_when_dark_changes() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    theme.closeTone = "#123456"
    theme.dark = false
    compare(theme.closeTone, Qt.color("#123456"))
    compare(theme.levelStory, Qt.color("#4a67d6"))
  }

  function test_amber_is_not_a_level_colour() {
    var modes = [true, false]
    for (var m = 0; m < modes.length; ++m) {
      var theme = createTemporaryObject(themeC, tc, { dark: modes[m] })
      var levels = [theme.levelMilestone, theme.levelStory, theme.levelSubtask]
      for (var i = 0; i < levels.length; ++i) {
        verify(!Qt.colorEqual(levels[i], theme.warn), "level " + i + " is warn, dark " + modes[m])
        verify(!Qt.colorEqual(levels[i], theme.closeTone), "level " + i + " is closeTone, dark " + modes[m])
      }
    }
  }
}
