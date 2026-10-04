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

  // The glyph for a phase status; "" for anything but an exact, own key
  // (so "Done", 3 and inherited names such as "constructor" show no glyph).
  function glyphOf(status) {
    var glyphs = {
      done: RunGlyphs.GLYPHS.done,
      started: RunGlyphs.GLYPHS.running,
      failed: RunGlyphs.GLYPHS.dead,
      pending: "·"
    }
    return typeof status === "string" && Object.prototype.hasOwnProperty.call(glyphs, status) ? glyphs[status] : ""
  }

  // The rendered line for a phases array. Anything but an array-like object
  // is no line at all; an entry that is not an object with a non-empty string
  // `name` (null, a number, a hole, "", 7) is skipped.
  function lineOf(phases) {
    if (phases === null || typeof phases !== "object" || typeof phases.length !== "number") return ""
    var parts = []
    for (var i = 0; i < phases.length; i++) {
      var entry = phases[i]
      if (entry === null || entry === undefined || typeof entry !== "object") continue
      if (typeof entry.name !== "string" || entry.name === "") continue
      parts.push(entry.name + timeline.glyphOf(entry.status))
    }
    return parts.join(" → ")
  }

  implicitWidth: line.implicitWidth
  implicitHeight: line.implicitHeight
  visible: timeline.text !== ""

  ThemedText {
    id: line
    objectName: "phaseTimelineText"
    theme: timeline.palette
    textFormat: Text.PlainText
    text: timeline.text
  }

  T.Theme { id: timelineTheme }
}
