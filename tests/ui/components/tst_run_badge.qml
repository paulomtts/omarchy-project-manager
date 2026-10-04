// tests/ui/components/tst_run_badge.qml
// ui/components/RunBadge.qml: an am run's state as a glyph inside a Badge ring
// (never colour alone), with a subtask's phase beside it or a parent's
// non-zero counts instead of it. Escalated reads in `urgent`; only a visible,
// active running badge pulses, through the shared Pulse.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "RunBadge"
  when: windowShown
  visible: true
  width: 400; height: 200

  // Three distinct tokens, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: badgeC; UI.RunBadge {} }
  Component { id: hostC; Item { width: 200; height: 60 } }

  function make(props) {
    var badge = createTemporaryObject(badgeC, tc, props)
    wait(30)
    return badge
  }

  function textOf(badge) { return H.find(badge, "runBadgeText").text }

  function test_running() {
    var badge = make({ theme: testTheme, state: "running" })
    compare(badge.objectName, "runBadge")
    compare(badge.glyph, "⟳")
    compare(textOf(badge), "⟳")
    compare(badge.visible, true)
    verify(badge.radius > 0, "the glyph sits in the Badge ring")
    verify(Qt.colorEqual(badge.tint, testTheme.foreground))
    compare(badge.pulsing, true, "a visible running badge pulses")
    wait(120)
    verify(badge.opacity < 1, "the ring fades")
  }

  function test_running_hidden() {
    var off = make({ theme: testTheme, state: "running", active: false })
    compare(off.pulsing, false, "the owner can switch the pulse off")
    compare(off.opacity, 1)
    off.active = true
    wait(30)
    compare(off.pulsing, true)

    var host = createTemporaryObject(hostC, tc)
    var badge = badgeC.createObject(host, { theme: testTheme, state: "running" })
    wait(30)
    compare(badge.pulsing, true)
    wait(120)
    verify(badge.opacity < 1)
    host.visible = false
    wait(60)
    compare(badge.pulsing, false, "an invisible ancestor runs nothing")
    compare(badge.opacity, 1, "and leaves the ring unfaded")
    host.visible = true
    wait(30)
    compare(badge.pulsing, true, "showing it again restarts the pulse")

    wait(120)
    badge.state = "parked"
    wait(30)
    compare(badge.pulsing, false, "leaving running stops the pulse")
    compare(badge.opacity, 1)
    badge.destroy()
  }

  function test_parked() {
    var badge = make({ theme: testTheme, state: "parked" })
    compare(badge.glyph, "⏸")
    compare(textOf(badge), "⏸")
    compare(badge.pulsing, false)
    compare(badge.opacity, 1)
    verify(Qt.colorEqual(badge.tint, testTheme.foreground))
  }

  function test_escalated() {
    var badge = make({ theme: testTheme, state: "escalated" })
    compare(badge.glyph, "‼")
    compare(textOf(badge), "‼")
    compare(badge.pulsing, false)
    verify(Qt.colorEqual(badge.tint, testTheme.urgent), "escalated reads in urgent")
    verify(Qt.colorEqual(H.find(badge, "runBadgeText").color, testTheme.urgent))

    // No theme handed down: the badge's own fallback Theme, still urgent.
    var own = make({ state: "escalated" })
    verify(own.palette, "falls back to its own Theme")
    verify(Qt.colorEqual(own.tint, own.palette.urgent))
  }

  function test_dead() {
    var badge = make({ theme: testTheme, state: "dead" })
    compare(badge.glyph, "✖")
    compare(textOf(badge), "✖")
    compare(badge.pulsing, false)
    verify(Qt.colorEqual(badge.tint, testTheme.foreground))
  }

  function test_cancelled() {
    var badge = make({ theme: testTheme, state: "cancelled" })
    compare(badge.glyph, "⊘")
    compare(textOf(badge), "⊘")
    verify(Qt.colorEqual(badge.tint, testTheme.dim))
  }

  function test_done() {
    var badge = make({ theme: testTheme, state: "done" })
    compare(badge.glyph, "✔")
    compare(textOf(badge), "✔")
    verify(Qt.colorEqual(badge.tint, testTheme.dim))
  }

  function test_unknown_state_hidden() {
    var names = ["", "none", "bogus", "constructor"]
    for (var i = 0; i < names.length; i++) {
      var badge = make({ theme: testTheme, state: names[i] })
      compare(badge.glyph, "", names[i])
      compare(badge.visible, false, "no badge for '" + names[i] + "'")
      compare(badge.pulsing, false)
    }
  }

  function test_phase_text() {
    var badge = make({ theme: testTheme, state: "running", phase: "implement" })
    compare(textOf(badge), "⟳ implement")
    badge.phase = ""
    wait(30)
    compare(textOf(badge), "⟳", "no phase, just the glyph")
    var parked = make({ theme: testTheme, state: "parked", phase: "plan" })
    compare(textOf(parked), "⏸ plan")
  }

  function test_parent_counts() {
    var badge = make({ theme: testTheme, counts: { running: 2, parked: 1, escalated: 0, done: 0 } })
    compare(textOf(badge), "⟳ 2 ⏸ 1")
    compare(badge.visible, true)
    verify(Qt.colorEqual(badge.tint, testTheme.foreground), "the counts form is neutral")

    badge.counts = { running: 0, parked: 0, escalated: 3, done: 4 }
    wait(30)
    compare(textOf(badge), "‼ 3 ✔ 4")

    // Counts win over the single state: no phase, and no single running ring to pulse.
    var both = make({ theme: testTheme, state: "running", phase: "plan", counts: { running: 1 } })
    compare(textOf(both), "⟳ 1")
    compare(both.pulsing, false)

    // Missing and garbage entries count as 0.
    var odd = make({ theme: testTheme, counts: { running: -1, parked: "x", done: 2 } })
    compare(textOf(odd), "✔ 2")

    var zero = make({ theme: testTheme, counts: { running: 0, parked: 0, escalated: 0, done: 0 } })
    compare(zero.visible, false, "all-zero counts show nothing")
    var empty = make({ theme: testTheme, counts: {} })
    compare(empty.visible, false)
  }

  function test_no_forbidden_colours() {
    var states = ["running", "parked", "escalated", "dead", "cancelled", "done"]
    for (var i = 0; i < states.length; i++) {
      var badge = make({ state: states[i] })
      verify(!Qt.colorEqual(badge.tint, "#9b72cf"), states[i] + " is not the merged colour")
      verify(!Qt.colorEqual(badge.tint, "#d9534f"), states[i] + " is not the canceled colour")
    }
  }
}
