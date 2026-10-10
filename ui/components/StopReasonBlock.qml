import QtQuick
import qs.Commons
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// Why a stopped run stopped, for Run detail, top to bottom: "Why it stopped";
// the headline (the state's glyph, Runs.stopReport's headline, the card as
// "#<first 8>" with its story's title, and a dead run's phase), urgent for
// escalated and dead; the detail; a dead run's "Last heartbeat <age> ago"; am's
// note (a heading with its local time, then one indented "<key>  <value>" line
// per field); the parked cards; the Open card and Relaunch buttons; and the
// reasons of the shown disabled buttons, written out because a disabled shell
// Button gets no hover.
//
// Presentation only: it imports no store and never changes its inputs. The
// owner passes `report` (Runs.stopReport), `note` (Runs.stopComment),
// `heartbeatAge`, the card Open card opens with why it is disabled, and
// whether Relaunch shows with why it is disabled. A click on an enabled button
// emits openCardRequested(openCardId) or relaunchRequested(). Visible exactly
// when `report` is an object; a missing field of it reads as "" or [].
//
// objectNames: stopTitle, stopHeadline, stopDetail, stopHeartbeat,
// stopNoteHeading, stopNoteField<i>, stopParked, stopActions, stopOpenCard,
// stopRelaunch, stopActionReason.
Column {
  id: block
  objectName: "stopReasonBlock"

  property var theme: T.Theme {}
  // Runs.stopReport(run), or null.
  property var report: null
  // Runs.stopComment(…), or null.
  property var note: null
  // A dead run's last heartbeat age without "ago" ("5m"); "" for none.
  property string heartbeatAge: ""
  // The card Open card opens; "" hides the button.
  property string openCardId: ""
  // Why Open card is disabled; "" when it is enabled.
  property string openCardReason: ""
  property bool relaunchOffered: false
  // Why Relaunch is disabled; "" when it is enabled.
  property string relaunchReason: ""

  signal openCardRequested(string id)
  signal relaunchRequested()

  readonly property bool hasReport: block.isObject(block.report)
  readonly property string stopState: block.hasReport ? block.textOf(block.report.state) : ""
  readonly property bool urgent: block.stopState === "escalated" || block.stopState === "dead"
  readonly property string detailText: block.hasReport ? block.textOf(block.report.detail) : ""
  readonly property bool hasNote: block.isObject(block.note)
  readonly property var noteFields: block.hasNote && block.isList(block.note.fields) ? block.note.fields : []
  readonly property string parkedText: block.parkedLine(block.hasReport ? block.report.parked : null)
  readonly property bool openShown: block.openCardId !== ""
  // The distinct non-empty reasons of the shown disabled buttons, Open card first.
  readonly property string actionReason: {
    var out = []
    if (block.openShown && block.openCardReason !== "") out.push(block.openCardReason)
    if (block.relaunchOffered && block.relaunchReason !== "" && out.indexOf(block.relaunchReason) < 0)
      out.push(block.relaunchReason)
    return out.join(" · ")
  }

  visible: block.hasReport
  spacing: Style.space(2)

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
  function textOf(v) { return typeof v === "string" ? v : "" }
  // Not Array.isArray: a list handed in through createObject's property map
  // arrives as a QML list, for which Array.isArray is false although length
  // and indexing work.
  function isList(v) { return v !== null && typeof v === "object" && typeof v.length === "number" }
  function shortCard(id) { return "#" + id.substring(0, 8) }

  // "<glyph> <headline> · #<card> · story "<title>" · at <phase>", each part
  // only when it has something; the phase for a dead run only.
  function headlineOf(r) {
    if (!block.isObject(r)) return ""
    var glyph = RunGlyphs.glyphOf(r.state)
    var line = (glyph !== "" ? glyph + " " : "") + block.textOf(r.headline)
    var cardId = block.textOf(r.cardId)
    if (cardId !== "") {
      line += " · " + block.shortCard(cardId)
      var story = block.textOf(r.storyTitle)
      if (story !== "") line += " · story \"" + story + "\""
    }
    var phase = block.textOf(r.phase)
    if (r.state === "dead" && phase !== "") line += " · at " + phase
    return line
  }

  // "am's note", with " · HH:mm" (local) when createdAt parses.
  function noteHeadingOf(n) {
    var at = block.isObject(n) ? block.textOf(n.createdAt) : ""
    return isFinite(Date.parse(at)) ? "am's note · " + Qt.formatTime(new Date(at), "hh:mm") : "am's note"
  }

  function fieldText(f) { return block.isObject(f) ? block.textOf(f.key) + "  " + block.textOf(f.value) : "" }

  // "Parked: #<first 8>, …" over the non-empty string ids; "" when none.
  function parkedLine(ids) {
    if (!block.isList(ids)) return ""
    var out = []
    for (var i = 0; i < ids.length; i++) {
      if (typeof ids[i] === "string" && ids[i] !== "") out.push(block.shortCard(ids[i]))
    }
    return out.length > 0 ? "Parked: " + out.join(", ") : ""
  }

  function colorOf(isUrgent) {
    if (!block.theme) return isUrgent ? Color.urgent : Color.foreground
    return isUrgent ? block.theme.urgent : block.theme.foreground
  }

  UI.ThemedText {
    objectName: "stopTitle"
    theme: block.theme
    text: "Why it stopped"
    font.bold: true
  }

  UI.ThemedText {
    objectName: "stopHeadline"
    theme: block.theme
    width: parent.width
    text: block.headlineOf(block.report)
    color: block.colorOf(block.urgent)
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "stopDetail"
    variant: "small"
    theme: block.theme
    width: parent.width
    visible: block.detailText.trim() !== ""
    text: block.detailText
    color: block.colorOf(block.urgent)
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "stopHeartbeat"
    variant: "caption"
    theme: block.theme
    visible: block.stopState === "dead" && block.heartbeatAge !== ""
    text: "Last heartbeat " + block.heartbeatAge + " ago"
  }

  UI.ThemedText {
    objectName: "stopNoteHeading"
    variant: "caption"
    theme: block.theme
    visible: block.hasNote
    text: block.noteHeadingOf(block.note)
  }

  Repeater {
    model: block.noteFields.length
    delegate: UI.ThemedText {
      required property int index
      objectName: "stopNoteField" + index
      variant: "small"
      theme: block.theme
      x: Style.space(12)
      width: block.width - Style.space(12)
      text: block.fieldText(block.noteFields[index])
      wrapMode: Text.WordWrap
    }
  }

  UI.ThemedText {
    objectName: "stopParked"
    variant: "small"
    theme: block.theme
    width: parent.width
    visible: block.parkedText !== ""
    text: block.parkedText
    wrapMode: Text.WordWrap
  }

  Row {
    objectName: "stopActions"
    visible: block.openShown || block.relaunchOffered
    spacing: Style.space(6)

    UI.ActionButton {
      id: openButton
      objectName: "stopOpenCard"
      theme: block.theme
      visible: block.openShown
      text: "Open card"
      enabled: block.openCardReason === ""
      tooltipText: block.openCardReason
      onClicked: if (openButton.enabled) block.openCardRequested(block.openCardId)
    }

    UI.ActionButton {
      id: relaunchButton
      objectName: "stopRelaunch"
      theme: block.theme
      visible: block.relaunchOffered
      text: "Relaunch"
      enabled: block.relaunchReason === ""
      tooltipText: block.relaunchReason
      onClicked: if (relaunchButton.enabled) block.relaunchRequested()
    }
  }

  UI.ThemedText {
    objectName: "stopActionReason"
    variant: "caption"
    theme: block.theme
    width: parent.width
    visible: block.actionReason !== ""
    text: block.actionReason
    wrapMode: Text.WordWrap
  }
}
