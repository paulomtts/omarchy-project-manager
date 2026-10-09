import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../../core/domain/runEvents.js" as RunEvents
import "../theme" as T

// One run's event timeline. Presentation only: it draws its props and emits.
//   rows: RunEvents.eventRow rows, ascending seq, unfiltered.
//   filter: All | Phases | Failures. The pane shows RunEvents.filterRows(rows,
//     filter) as `shownRows`, oldest first, and never assigns `filter`.
//   dropped: events of the run not held; above 0 shows "… N earlier events".
//   status: idle | loading | ok | error. error shows errorText, with
//     errorMessage one Details click away, above the rows held.
//   maxListHeight: the list's height cap; past it the list scrolls itself and
//     a wheel at its ends reaches the enclosing Flickable.
//   filterRequested(filter): a chip was clicked.
//   attemptRequested(card, phase, attempt): a row with a non-empty card and
//     phase and an attempt above 0 was clicked.
Item {
  id: pane
  objectName: "eventsPane"

  // The owner's Theme, or none: `palette` then falls back to the pane's own.
  property var theme: null
  property var rows: []

  readonly property var palette: pane.theme || paneTheme
  readonly property var shownRows: RunEvents.filterRows(pane.rows, "All")

  // row[key] when row is an object and that field is a string, else "".
  function _field(row, key) {
    return row !== null && typeof row === "object" && typeof row[key] === "string" ? row[key] : ""
  }

  function _isFailure(row) { return RunEvents.filterRows([row], "Failures").length === 1 }

  function _glyphOf(row) {
    if (pane._isFailure(row)) return RunGlyphs.glyphOf("escalated")
    return RunGlyphs.glyphOf(row !== null && typeof row === "object" ? row.glyph : "")
  }

  // urgent on a failure row, else the palette's `token` colour.
  function _tint(failure, token) {
    if (!pane.palette) return Color.foreground
    return failure ? pane.palette.urgent : pane.palette[token]
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: pane.width
    spacing: Style.space(6)

    ListView {
      id: list
      objectName: "eventsList"
      visible: pane.shownRows.length > 0
      width: parent.width
      height: list.contentHeight
      interactive: false
      model: pane.shownRows

      delegate: ListRow {
        id: row
        required property var modelData
        readonly property bool failure: pane._isFailure(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: list.width
        theme: pane.palette

        Row {
          spacing: Style.space(8)

          ThemedText {
            objectName: "eventsRowTime"
            theme: pane.palette
            variant: "dim"
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "time")
          }
          ThemedText {
            objectName: "eventsRowGlyph"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._glyphOf(row.modelData)
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowLabel"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "label")
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowStatus"
            theme: pane.palette
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "status")
            color: pane._tint(row.failure, "foreground")
          }
          ThemedText {
            objectName: "eventsRowDuration"
            theme: pane.palette
            variant: "dim"
            textFormat: Text.PlainText
            text: pane._field(row.modelData, "duration")
          }
        }

        ThemedText {
          objectName: "eventsRowDetail"
          width: parent.width
          theme: pane.palette
          visible: text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: pane._field(row.modelData, "detail")
          color: pane._tint(row.failure, "dim")
        }
      }
    }
  }

  T.Theme { id: paneTheme }
}
