import QtQuick
import "runGlyphs.js" as RunGlyphs
import "../theme" as T

// One subtask's phases as a single static line, e.g.
// `spec✔ → plan✔ → implement⟳ → verify· → review·`. Presentation only:
// `phases` is [{ name, status }] in display order (run.tree.subtasks[].phases[]),
// status started | done | failed | pending. done, started and failed borrow
// the run-state glyphs from runGlyphs.js (done, running, dead) so a state
// reads the same everywhere; pending has no run-state twin and is a local ·.
// State is the glyph, never colour; nothing animates.
Item {
  id: timeline
  objectName: "phaseTimeline"

  property var phases: []
  // The owner's Theme, or none: `palette` then falls back to the line's own.
  property var theme: null

  readonly property var palette: timeline.theme || timelineTheme
  readonly property string text: timeline.lineOf(timeline.phases)

  // The rendered line for a phases array.
  function lineOf(phases) {
    var glyphs = {
      done: RunGlyphs.GLYPHS.done,
      started: RunGlyphs.GLYPHS.running,
      failed: RunGlyphs.GLYPHS.dead,
      pending: "·"
    }
    var parts = []
    for (var i = 0; i < phases.length; i++)
      parts.push(phases[i].name + (glyphs[phases[i].status] || ""))
    return parts.join(" → ")
  }

  implicitWidth: line.implicitWidth
  implicitHeight: line.implicitHeight
  visible: timeline.text !== ""

  ThemedText {
    id: line
    objectName: "phaseTimelineText"
    theme: timeline.palette
    text: timeline.text
  }

  T.Theme { id: timelineTheme }
}
