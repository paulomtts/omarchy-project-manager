import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// The toolbar's am run strip, beside MilestoneJobIndicator: one segment per
// non-zero count, each the shared run glyph immediately followed by the count
// (`⟳2 ⏸1 ‼1`), in the order running, parked, attention. Attention reads in
// `urgent`; every state keeps its glyph, so colour is never the only signal.
// Static: no animation.
//
// Presentation only: the owner computes the three counts (attention is
// escalated plus dead) and passes them in. Each is read through
// runGlyphs.countOf, so a negative, non-finite or non-number value is 0, and
// the whole strip hides when all three are 0 -- no runs, or only finished
// ones. A click asks for the matching Runs screen filter through
// `filterRequested(filter)`. The filter vocabulary is the Runs screen's chip
// set: "attention" (Needs attention), "live", "parked" and "all"; the running
// segment asks for "live", parked for "parked", attention for "attention",
// and no segment asks for "all".
Item {
  id: indicator
  objectName: "runIndicator"

  property var running: 0
  property var parked: 0
  property var attention: 0
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}

  readonly property real runningCount: RunGlyphs.countOf({ n: indicator.running }, "n")
  readonly property real parkedCount: RunGlyphs.countOf({ n: indicator.parked }, "n")
  readonly property real attentionCount: RunGlyphs.countOf({ n: indicator.attention }, "n")

  signal filterRequested(string filter)

  visible: indicator.runningCount + indicator.parkedCount + indicator.attentionCount > 0
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    UI.ActionButton {
      objectName: "runIndicatorRunning"
      visible: indicator.runningCount > 0
      theme: indicator.theme
      text: RunGlyphs.glyphOf("running") + indicator.runningCount
      onClicked: indicator.filterRequested("live")
    }

    UI.ActionButton {
      objectName: "runIndicatorParked"
      visible: indicator.parkedCount > 0
      theme: indicator.theme
      text: RunGlyphs.glyphOf("parked") + indicator.parkedCount
      onClicked: indicator.filterRequested("parked")
    }

    UI.ActionButton {
      objectName: "runIndicatorAttention"
      visible: indicator.attentionCount > 0
      theme: indicator.theme
      text: RunGlyphs.glyphOf("escalated") + indicator.attentionCount
      tone: "danger"
      onClicked: indicator.filterRequested("attention")
    }
  }
}
