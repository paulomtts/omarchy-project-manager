// tests/ui/components/tst_run_state_badge.qml
// ui/components/RunStateBadge.qml: RUNNING in the accent tint and ESCALATED in
// the warn tint, on the Badge pill; every other state shows nothing. No glyph,
// no pulse. A token on the theme wins; without one the badge paints its own
// green and amber.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunStateBadge"
  when: windowShown
  visible: true
  width: 400; height: 200

  // A theme with the accent and warn tokens, each a colour nothing else uses.
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
    property color accent: "#11aa22"
    property color warn: "#cc8800"
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

  Component { id: badgeC; UI.RunStateBadge {} }
  Component { id: themeC; T.Theme {} }

  function make(props) {
    var badge = createTemporaryObject(badgeC, tc, props)
    wait(0)
    return badge
  }

  function textOf(badge) { return H.find(badge, "runStateBadgeText").text }

  // 1
  function test_running() {
    var badge = make({ theme: tokenTheme, state: "running" })
    compare(badge.visible, true)
    compare(textOf(badge), "RUNNING")
    verify(Qt.colorEqual(badge.tint, "#11aa22"), "the accent token")
    compare(badge.radius, badge.height / 2, "the Badge pill")
    compare(badge.opacity, 1)
    wait(120)
    compare(badge.opacity, 1, "it never fades")
    verify(Qt.colorEqual(make({ theme: plainTheme, state: "running" }).tint, "#7ed491"), "the fallback green")
  }

  // 2
  function test_escalated() {
    var badge = make({ theme: tokenTheme, state: "escalated" })
    compare(badge.visible, true)
    compare(textOf(badge), "ESCALATED")
    verify(Qt.colorEqual(badge.tint, "#cc8800"), "the warn token")
    verify(Qt.colorEqual(make({ theme: plainTheme, state: "escalated" }).tint, "#f0b54a"), "the fallback amber")
  }

  // 3
  function test_hidden_states_data() {
    return [
      { tag: "parked", state: "parked" },
      { tag: "dead", state: "dead" },
      { tag: "done", state: "done" },
      { tag: "cancelled", state: "cancelled" },
      { tag: "empty", state: "" },
      { tag: "capitalised", state: "Running" },
      { tag: "unknown", state: "stopped" }
    ]
  }

  function test_hidden_states(data) {
    var badge = make({ theme: tokenTheme, state: data.state })
    compare(badge.visible, false)
    compare(textOf(badge), "")
  }

  // 4
  function test_no_glyphs() {
    var states = ["running", "escalated"]
    var glyphs = ["⟳", "⚠", "⏸"]
    for (var i = 0; i < states.length; i++) {
      var text = textOf(make({ theme: tokenTheme, state: states[i] }))
      for (var j = 0; j < glyphs.length; j++)
        verify(text.indexOf(glyphs[j]) === -1, states[i] + " shows no " + glyphs[j])
    }
  }

  // 5
  function test_state_change_updates_live() {
    var badge = make({ theme: tokenTheme, state: "running" })
    compare(badge.visible, true)
    badge.state = "parked"
    compare(badge.visible, false)
    compare(textOf(badge), "")
    badge.state = "escalated"
    compare(badge.visible, true)
    compare(textOf(badge), "ESCALATED")
    verify(Qt.colorEqual(badge.tint, "#cc8800"))
  }

  // 6
  function test_object_names() {
    var badge = make({ theme: tokenTheme, state: "running" })
    compare(badge.objectName, "runStateBadge")
    verify(H.find(badge, "runStateBadgeText"), "the label")
  }

  // Review Focus: a null theme falls back to the badge's own Theme, quietly.
  function test_null_theme_uses_its_own_theme() {
    var own = createTemporaryObject(themeC, tc)
    var expected = own.accent === undefined ? "#7ed491" : own.accent
    var badge = make({ theme: tokenTheme, state: "running" })
    badge.theme = null
    wait(0)
    verify(Qt.colorEqual(badge.tint, expected))
    compare(textOf(badge), "RUNNING")
    badge.destroy()
    wait(0)
  }
}
