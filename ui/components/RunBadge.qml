import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs

// An am run's state as a glyph inside a ring: the Badge pill, so the ring,
// the caption text, `theme`/`palette` and the fallback Theme are Badge's own.
// Presentation only: `state` (Item's own string property, used as plain text)
// is running | parked | escalated | dead | cancelled | done, and anything else
// shows nothing. A subtask passes its `phase`; a parent passes `counts`
// ({running, parked, escalated, done}), which replace the single glyph.
//
// Escalated reads in `urgent`; never Board.statusColor. A running badge fades
// with the shared Pulse, and only while it is visible and `active`.
Badge {
  id: runBadge
  objectName: "runBadge"
  textObjectName: "runBadgeText"

  property string phase: ""
  // Rollup-shaped counts for a milestone/story, or null for a single run state.
  property var counts: null
  // The owner's own "this is on screen" verdict, ANDed into the pulse.
  property bool active: true

  readonly property bool hasCounts: runBadge.counts !== null && typeof runBadge.counts === "object"
  readonly property string glyph: RunGlyphs.glyphOf(runBadge.state)
  readonly property bool pulsing: pulse.running

  text: runBadge.hasCounts ? RunGlyphs.countsText(runBadge.counts)
    : runBadge.glyph === "" ? ""
    : runBadge.phase !== "" ? runBadge.glyph + " " + runBadge.phase
    : runBadge.glyph
  tint: !runBadge.palette ? Color.foreground
    : runBadge.hasCounts ? runBadge.palette.foreground
    : runBadge.state === "escalated" ? runBadge.palette.urgent
    : (runBadge.state === "done" || runBadge.state === "cancelled") ? runBadge.palette.dim
    : runBadge.palette.foreground
  visible: runBadge.text !== ""
  opacity: pulse.level

  Pulse {
    id: pulse
    running: runBadge.active && runBadge.visible && !runBadge.hasCounts && runBadge.state === "running"
  }
}
