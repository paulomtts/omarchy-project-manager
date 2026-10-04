import QtQuick
import "runGlyphs.js" as RunGlyphs

// One card's am run mark, as the Board and the Graph draw it: a RunBadge inside
// the wrapper that dims it. Presentation only: the owner hands in what runs.js
// said -- `runState` (cardRunState) and `rollup` (rollup), or null for "no
// mark" (a merged or canceled card, am not installed) -- and never brd status.
// A subtask shows its glyph and phase; a milestone or story its non-zero
// counts, else its run's glyph. A dimmed winner (a finished run speaking for
// the card) or stale run data is drawn at half opacity and never pulses. The
// dimming is this wrapper's: RunBadge's own opacity follows its Pulse.
Item {
  id: mark
  objectName: "runMark"

  property var theme: null
  property var runState: null
  property var rollup: null
  // Glyph and phase rather than counts.
  property bool subtask: false
  property bool stale: false
  // The owner's own "this is on screen" verdict, ANDed into the pulse.
  property bool active: true

  readonly property bool hasRunState: mark.runState !== null && mark.runState !== undefined
    && typeof mark.runState === "object"
  readonly property string stateName: mark.hasRunState && typeof mark.runState.state === "string" ? mark.runState.state : ""
  readonly property bool dimmed: mark.stale || (mark.hasRunState && mark.runState.dimmed === true)
  readonly property bool showCounts: !mark.subtask && RunGlyphs.countsText(mark.rollup) !== ""
  readonly property bool shown: mark.showCounts || RunGlyphs.glyphOf(mark.stateName) !== ""

  visible: mark.shown
  implicitWidth: badge.width
  implicitHeight: badge.height
  width: implicitWidth
  height: implicitHeight
  opacity: mark.dimmed ? 0.5 : 1

  RunBadge {
    id: badge
    theme: mark.theme
    state: mark.showCounts ? "" : mark.stateName
    phase: !mark.showCounts && mark.subtask && mark.hasRunState && typeof mark.runState.phase === "string"
      ? mark.runState.phase : ""
    counts: mark.showCounts ? mark.rollup : null
    active: mark.active && !mark.dimmed
  }
}
