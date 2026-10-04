// tests/ui/components/tst_phase_timeline.qml
// ui/components/PhaseTimeline.qml: one subtask's phases as a single static
// line, `name` + glyph joined by " → " (done ✔, started ⟳, failed ✖ from
// runGlyphs.js, pending ·). Never colour alone, never animated, and nothing at
// all for missing, empty or garbage phases.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI
import "../../../ui/components/runGlyphs.js" as RG
import "../../../ui/theme" as T

TestCase {
  id: tc
  name: "PhaseTimeline"
  when: windowShown
  visible: true
  width: 600; height: 200

  // Three distinct tokens, so a tint can only match the one it is meant to.
  T.Theme { id: testTheme; foreground: "#eeeeee"; dim: "#777777"; urgent: "#ff3300" }

  Component { id: timelineC; UI.PhaseTimeline {} }

  function make(props) {
    var timeline = createTemporaryObject(timelineC, tc, props || {})
    wait(30)
    return timeline
  }

  function lineOf(timeline) { return H.find(timeline, "phaseTimelineText").text }

  function test_full_timeline() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "spec", status: "done" },
      { name: "plan", status: "done" },
      { name: "implement", status: "started" },
      { name: "verify", status: "pending" },
      { name: "review", status: "pending" }
    ] })
    compare(timeline.objectName, "phaseTimeline")
    compare(lineOf(timeline), "spec✔ → plan✔ → implement⟳ → verify· → review·")
    compare(timeline.text, "spec✔ → plan✔ → implement⟳ → verify· → review·")
    compare(timeline.visible, true)
    verify(timeline.implicitWidth > 0, "sized to its line")
    verify(timeline.implicitHeight > 0)
  }

  function test_failed_glyph() {
    var timeline = make({ theme: testTheme, phases: [{ name: "verify", status: "failed" }] })
    compare(lineOf(timeline), "verify✖")
    compare(lineOf(timeline), "verify" + RG.GLYPHS.dead, "failed reads as the run-state dead glyph")
  }

  function test_glyphs_match_run_glyphs() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "a", status: "done" },
      { name: "b", status: "started" }
    ] })
    compare(lineOf(timeline), "a" + RG.GLYPHS.done + " → b" + RG.GLYPHS.running)
  }

  function test_names_from_array() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "alpha", status: "done" },
      { name: "beta", status: "pending" }
    ] })
    compare(lineOf(timeline), "alpha✔ → beta·")

    var one = make({ theme: testTheme, phases: [{ name: "solo", status: "started" }] })
    compare(lineOf(one), "solo⟳", "one entry, no arrow")
  }

  function test_updates_on_change() {
    var timeline = make({ theme: testTheme, phases: [{ name: "spec", status: "started" }] })
    compare(lineOf(timeline), "spec⟳")
    timeline.phases = [{ name: "spec", status: "done" }, { name: "plan", status: "started" }]
    wait(30)
    compare(lineOf(timeline), "spec✔ → plan⟳")
    timeline.phases = []
    wait(30)
    compare(lineOf(timeline), "")
    compare(timeline.visible, false, "an emptied timeline hides")
  }

  function test_theme_fallback() {
    var themed = make({ theme: testTheme, phases: [{ name: "spec", status: "done" }] })
    verify(Qt.colorEqual(H.find(themed, "phaseTimelineText").color, testTheme.foreground),
           "the line reads in the owner's foreground")

    var own = make({ phases: [{ name: "spec", status: "done" }] })
    verify(own.palette, "falls back to its own Theme")
    compare(lineOf(own), "spec✔")
    verify(Qt.colorEqual(H.find(own, "phaseTimelineText").color, own.palette.foreground))

    var states = ["done", "started", "failed", "pending"]
    for (var i = 0; i < states.length; i++) {
      var t = make({ phases: [{ name: "p", status: states[i] }] })
      var c = H.find(t, "phaseTimelineText").color
      verify(!Qt.colorEqual(c, "#9b72cf"), states[i] + " is not the merged colour")
      verify(!Qt.colorEqual(c, "#d9534f"), states[i] + " is not the canceled colour")
    }
  }

  function test_static() {
    var timeline = make({ theme: testTheme, phases: [
      { name: "spec", status: "done" },
      { name: "implement", status: "started" }
    ] })
    wait(120)
    compare(timeline.opacity, 1, "no pulse on the timeline")
    compare(H.find(timeline, "phaseTimelineText").opacity, 1, "no pulse on the line")
  }
}
