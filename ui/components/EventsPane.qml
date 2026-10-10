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
//   following (read-only): true while the list is at its bottom. New rows keep
//     a following list at its bottom; otherwise the list keeps its contentY.
//     A scroll sets it to whether the list is at its bottom; a filter change
//     keeps it. While false and the list can scroll, "Jump ↓" under the list
//     puts it at its bottom and sets it.
//   filterRequested(filter): a chip was clicked.
//   attemptRequested(card, phase, attempt): a row with a non-empty card and
//     phase and an attempt above 0 was clicked.
Item {
  id: pane
  objectName: "eventsPane"

  // The owner's Theme, or none: `palette` then falls back to the pane's own.
  property var theme: null
  property var rows: []
  property string filter: "All"
  property int dropped: 0
  property string status: "idle"
  property string errorText: "Events unreadable."
  property string errorMessage: ""
  property real maxListHeight: Style.space(320)

  readonly property var palette: pane.theme || paneTheme
  readonly property var shownRows: RunEvents.filterRows(pane.rows, pane.filter)
  readonly property int _heldCount: RunEvents.filterRows(pane.rows, "All").length
  property bool _errorExpanded: false
  readonly property bool following: pane._following
  property bool _following: true
  property bool _relayout: false

  signal filterRequested(string filter)
  signal attemptRequested(string card, string phase, int attempt)

  // row[key] when row is an object and that field is a string, else "".
  function _field(row, key) {
    return row !== null && typeof row === "object" && typeof row[key] === "string" ? row[key] : ""
  }

  function _isFailure(row) { return RunEvents.filterRows([row], "Failures").length === 1 }

  function _namesAttempt(row) {
    return pane._field(row, "card") !== "" && pane._field(row, "phase") !== ""
      && typeof row.attempt === "number" && isFinite(row.attempt) && row.attempt > 0
  }

  function _glyphOf(row) {
    if (pane._isFailure(row)) return RunGlyphs.glyphOf("escalated")
    return RunGlyphs.glyphOf(row !== null && typeof row === "object" ? row.glyph : "")
  }

  // urgent on a failure row, else the palette's `token` colour.
  function _tint(failure, token) {
    if (!pane.palette) return Color.foreground
    return failure ? pane.palette.urgent : pane.palette[token]
  }

  // True when the list's rows fit or its contentY is within 1 px of its bottom.
  function _atBottom() {
    return list.contentHeight <= list.height
      || Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // Puts the list at its bottom; contentY moves made here are not a user scroll.
  function _toBottom() {
    pane._relayout = true
    list.forceLayout()
    list.positionViewAtEnd()
    pane._relayout = false
  }

  // Hands shownRows to the list. A new model puts a ListView back at its top,
  // so a following list goes to its bottom and any other keeps its scroll
  // position, within its new bounds.
  function _showRows() {
    pane._relayout = true
    var y = list.contentY
    list.model = pane.shownRows
    list.forceLayout()
    if (pane._following) list.positionViewAtEnd()
    else list.contentY = Math.max(list.originY, Math.min(y, list.originY + list.contentHeight - list.height))
    pane._relayout = false
    pane._following = pane._atBottom()
  }

  function _jump() {
    pane._toBottom()
    pane._following = true
  }

  implicitHeight: column.implicitHeight
  onStatusChanged: if (pane.status !== "error") pane._errorExpanded = false
  onShownRowsChanged: pane._showRows()
  Component.onCompleted: pane._showRows()

  Column {
    id: column
    width: pane.width
    spacing: Style.space(6)

    ChipRow {
      width: parent.width
      theme: pane.palette
      chipPrefix: "eventsFilterChip"
      active: pane.filter
      model: [{ id: "All", label: "All" }, { id: "Phases", label: "Phases" },
              { id: "Failures", label: "Failures" }]
      onChosen: function(id) { pane.filterRequested(id) }
    }

    Column {
      objectName: "eventsError"
      visible: pane.status === "error"
      width: parent.width
      spacing: Style.space(4)

      Row {
        spacing: Style.space(8)

        ThemedText {
          objectName: "eventsErrorText"
          theme: pane.palette
          textFormat: Text.PlainText
          text: pane.errorText
          color: pane._tint(true, "urgent")
        }

        ActionButton {
          objectName: "eventsErrorToggle"
          theme: pane.palette
          visible: pane.errorMessage !== ""
          text: pane._errorExpanded ? "Hide" : "Details"
          onClicked: pane._errorExpanded = !pane._errorExpanded
        }
      }

      ThemedText {
        objectName: "eventsErrorMessage"
        width: parent.width
        theme: pane.palette
        variant: "dim"
        visible: pane._errorExpanded && pane.errorMessage !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: pane.errorMessage
      }
    }

    ThemedText {
      objectName: "eventsEarlier"
      theme: pane.palette
      variant: "dim"
      visible: pane.dropped > 0
      text: "… " + pane.dropped + " earlier event" + (pane.dropped === 1 ? "" : "s")
    }

    ListStatus {
      objectName: "eventsStatus"
      width: parent.width
      theme: pane.palette
      loading: pane.status === "loading" && pane.shownRows.length === 0
      loadingText: "Loading events…"
      error: ""
      empty: pane.shownRows.length === 0 && (pane._heldCount > 0 || pane.status !== "error")
      filtered: pane._heldCount > 0
      emptyText: "No events yet."
      filteredText: "No events match the filter."
    }

    ListView {
      id: list
      objectName: "eventsList"
      visible: pane.shownRows.length > 0
      width: parent.width
      height: Math.min(list.contentHeight, pane.maxListHeight)
      clip: true
      orientation: ListView.Vertical
      flickableDirection: Flickable.VerticalFlick
      boundsBehavior: Flickable.StopAtBounds
      onContentYChanged: if (!pane._relayout) pane._following = pane._atBottom()
      onContentHeightChanged: if (pane._following && !pane._relayout) pane._toBottom()
      onHeightChanged: if (pane._following && !pane._relayout) pane._toBottom()

      delegate: ListRow {
        id: row
        required property var modelData
        readonly property bool failure: pane._isFailure(row.modelData)
        readonly property bool namesAttempt: pane._namesAttempt(row.modelData)

        objectName: "eventsRow" + (row.modelData ? row.modelData.seq : "")
        width: list.width
        theme: pane.palette
        hoverCursorShape: row.namesAttempt ? Qt.PointingHandCursor : Qt.ArrowCursor
        onActivated: if (row.namesAttempt)
          pane.attemptRequested(row.modelData.card, row.modelData.phase, row.modelData.attempt)

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

    Item {
      width: parent.width
      height: jump.height
      visible: list.visible && list.contentHeight > list.height && !pane._following

      ActionButton {
        id: jump
        objectName: "eventsJump"
        anchors.right: parent.right
        theme: pane.palette
        text: "Jump ↓"
        onClicked: pane._jump()
      }
    }
  }

  T.Theme { id: paneTheme }
}
