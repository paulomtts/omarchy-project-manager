import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../theme" as T

// A milestone's or story's am run rollup, under its title: one caption
// segment per non-zero count, in the RunBadge glyphs (running, parked,
// escalated, done) and then "N pending". Presentation only: `rollup` is
// {running, parked, escalated, done, pending, total} or null, computed
// elsewhere (runs.js `rollup`); a missing field is 0, and a null or empty
// rollup hides the whole bar. Escalated reads in `urgent`.
Row {
  id: bar
  objectName: "runRollupBar"

  // The owner's Theme, or none: `palette` then falls back to the bar's own.
  // Tearing a view down nulls it while the bindings still run once, so every
  // read of `palette` is guarded.
  property var theme: null
  property var rollup: null

  readonly property var palette: bar.theme || barTheme

  spacing: Style.space(8)
  visible: RunGlyphs.countOf(bar.rollup, "total") > 0

  Repeater {
    model: [
      { key: "running", name: "runRollupRunning" },
      { key: "parked", name: "runRollupParked" },
      { key: "escalated", name: "runRollupEscalated" },
      { key: "done", name: "runRollupDone" },
      { key: "pending", name: "runRollupPending" }
    ]

    delegate: ThemedText {
      id: segment
      required property var modelData

      readonly property int amount: RunGlyphs.countOf(bar.rollup, segment.modelData.key)

      objectName: segment.modelData.name
      variant: "caption"
      theme: bar.palette
      visible: segment.amount > 0
      text: segment.modelData.key === "pending"
        ? segment.amount + " pending"
        : RunGlyphs.glyphOf(segment.modelData.key) + " " + segment.amount
      color: !bar.palette ? Color.foreground
        : segment.modelData.key === "escalated" ? bar.palette.urgent
        : (segment.modelData.key === "running" || segment.modelData.key === "parked") ? bar.palette.foreground
        : bar.palette.dim
    }
  }

  T.Theme { id: barTheme }
}
