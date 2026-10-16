import QtQuick
import QtTest
import qs.Commons
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "ActionButton"
  when: windowShown
  visible: true
  width: 300; height: 120

  T.Theme { id: tcTheme; foreground: "#00ff00"; urgent: "#ff0000" }
  T.Theme { id: darkTheme; foreground: "#eeeeee"; dark: true }
  T.Theme { id: lightTheme; foreground: "#111111"; dark: false }

  Component { id: normalC; UI.ActionButton { theme: tcTheme; text: "Save" } }
  Component { id: dangerC; UI.ActionButton { theme: tcTheme; text: "Delete"; tone: "danger" } }
  Component { id: themeC; T.Theme {} }
  Component { id: toneC; UI.ActionButton { theme: darkTheme; text: "Go" } }
  Component { id: bareC; UI.ActionButton { text: "Close"; tone: "close" } }
  SignalSpy { id: clicks; signalName: "clicked" }

  function make(component) {
    var button = createTemporaryObject(component, tc)
    clicks.target = button
    clicks.clear()
    return button
  }

  function test_it_carries_the_shared_button_style() {
    var button = make(normalC)
    compare(button.text, "Save")
    compare(button.bordered, true)
    compare(button.foreground, Qt.color("#00ff00"))
    compare(button.fontFamily, Style.font.family)
    compare(button.fontSize, Style.font.bodySmall)
    compare(button.verticalPadding, Style.spacing.controlPaddingY)
  }

  function test_the_danger_tone_uses_the_urgent_colour() {
    var button = make(dangerC)
    compare(button.tone, "danger")
    compare(button.foreground, Qt.color("#ff0000"))
  }

  function test_a_disabled_button_is_dimmed() {
    var button = make(normalC)
    compare(button.opacity, 1)
    button.enabled = false
    compare(button.opacity, 0.5)
  }

  function test_it_reports_clicks() {
    var button = make(normalC)
    mouseClick(button, button.width / 2, button.height / 2)
    compare(clicks.count, 1)
  }

  function test_the_warn_tone_uses_the_warn_colour() {
    var button = createTemporaryObject(toneC, tc, { tone: "warn" })
    compare(button.foreground, Qt.color("#f2b84b"))
  }

  function test_the_close_tone_uses_the_close_colour() {
    var button = createTemporaryObject(toneC, tc, { tone: "close" })
    compare(button.foreground, Qt.color("#ff9442"))
  }

  function test_the_accent_tone_uses_the_accent_colour() {
    var button = createTemporaryObject(toneC, tc, { tone: "accent" })
    compare(button.foreground, Qt.color("#7fb069"))
  }

  function test_the_tones_take_the_light_values_on_a_light_theme() {
    var expected = { "warn": "#a86b00", "close": "#c4560a", "accent": "#2f7d32" }
    for (var tone in expected) {
      var button = createTemporaryObject(toneC, tc, { theme: lightTheme, tone: tone })
      compare(button.foreground, Qt.color(expected[tone]), tone)
    }
  }

  function test_an_unknown_tone_uses_the_foreground() {
    var tones = ["", "Danger", "Close", "green"]
    for (var i = 0; i < tones.length; ++i) {
      var button = createTemporaryObject(toneC, tc, { tone: tones[i] })
      compare(button.foreground, Qt.color("#eeeeee"), "tone '" + tones[i] + "'")
    }
  }

  function test_changing_the_tone_repaints_the_button() {
    var button = createTemporaryObject(toneC, tc)
    compare(button.foreground, Qt.color("#eeeeee"))
    button.tone = "close"
    compare(button.foreground, Qt.color("#ff9442"))
    button.tone = "normal"
    compare(button.foreground, Qt.color("#eeeeee"))
  }

  function test_flipping_the_themes_dark_repaints_the_button() {
    var theme = createTemporaryObject(themeC, tc, { dark: true })
    var button = createTemporaryObject(toneC, tc, { theme: theme, tone: "accent" })
    compare(button.foreground, Qt.color("#7fb069"))
    theme.dark = false
    compare(button.foreground, Qt.color("#2f7d32"))
  }

  function test_a_button_without_a_theme_uses_its_own() {
    var button = createTemporaryObject(bareC, tc)
    compare(button.foreground, Qt.color("#ff9442"))
  }

  function test_dropping_the_theme_falls_back_to_the_buttons_own() {
    var button = createTemporaryObject(toneC, tc, { theme: lightTheme, tone: "close" })
    compare(button.foreground, Qt.color("#c4560a"))
    button.theme = null
    compare(button.foreground, Qt.color("#ff9442"))
  }
}
