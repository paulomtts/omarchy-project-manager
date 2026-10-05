import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// One run's Pause / Resume / Cancel buttons and the lines under them: why a
// shown button is disabled, "applies to the whole run" on a story or subtask
// card, the store's still-waiting line and the control error for this run.
//
// Presentation only, like RunIndicator: it imports no store. The owner passes
// the run and what the store says about it (the action pending for it, whether
// that request is 30 s old, the control error for this run) and decides when
// the buttons show (`showButtons`); a click on an enabled button emits
// actionRequested("pause" | "resume" | "cancel"), and confirming a cancel is
// the owner's business. What a run allows is Runs.controls(run); a pending
// request disables every button.
//
// At most one of Pause and Resume shows: Pause on a running run, Resume on a
// parked, escalated or dead one, and a pending pause or resume keeps its own
// button until it settles. A finished, unknown or missing run shows no
// buttons, and with nothing to show the component is 0 tall.
//
// A disabled shell Button gets no hover, so its tooltip never shows: the
// reasons of the shown disabled buttons are also written out once, in the
// reason line.
Column {
  id: controls

  property var theme: T.Theme {}
  // One normalised run, as RunStore.runs holds them, or null.
  property var run: null
  // "" or the action pending for this run.
  property string pendingAction: ""
  // That request is 30 s or more old.
  property bool waiting: false
  property string waitingText: ""
  // The control error for THIS run; "" otherwise.
  property string errorText: ""
  // The controls sit on a story or subtask card: the labels say "run".
  property bool wholeRun: false
  // The owner's rule for showing the buttons; a pending request shows anyway.
  property bool showButtons: true

  signal actionRequested(string action)

  readonly property string runState: Runs.runState(controls.run)
  readonly property var allowed: Runs.controls(controls.run)
  readonly property bool requestPending: controls.pendingAction !== ""
  readonly property bool resumable: controls.runState === "parked" || controls.runState === "escalated"
    || controls.runState === "dead"
  readonly property bool buttonsShown: (controls.showButtons && (controls.runState === "running" || controls.resumable))
    || controls.requestPending
  readonly property bool pauseShown: controls.pendingAction === "pause"
    || (controls.pendingAction !== "resume" && controls.runState === "running")
  readonly property bool resumeShown: controls.pendingAction === "resume"
    || (controls.pendingAction !== "pause" && controls.resumable)
  // The distinct reasons of the shown disabled buttons, in button order.
  readonly property string reasonText: {
    if (!controls.buttonsShown || controls.requestPending || !controls.allowed) return ""
    var shown = []
    if (controls.pauseShown) shown.push("pause")
    if (controls.resumeShown) shown.push("resume")
    shown.push("cancel")
    var out = []
    for (var i = 0; i < shown.length; i++) {
      var a = controls.allowed[shown[i]]
      if (a && !a.enabled && a.reason !== "" && out.indexOf(a.reason) < 0) out.push(a.reason)
    }
    return out.join(" · ")
  }

  spacing: Style.space(2)

  function labelOf(action, word) {
    if (controls.pendingAction === action) return word + " requested…"
    return controls.wholeRun ? word + " run" : word
  }

  function enabledOf(action) {
    var a = controls.allowed ? controls.allowed[action] : null
    return !controls.requestPending && !!a && a.enabled === true
  }

  function tooltipOf(action) {
    if (controls.requestPending)
      return controls.pendingAction === action ? "Waiting for the run to act on the request" : "A request for this run is pending"
    var a = controls.allowed ? controls.allowed[action] : null
    return a ? a.reason : ""
  }

  Row {
    objectName: "runControlButtons"
    visible: controls.buttonsShown
    spacing: Style.space(6)

    UI.ActionButton {
      id: pauseButton
      objectName: "runControlPause"
      theme: controls.theme
      visible: controls.pauseShown
      text: controls.labelOf("pause", "Pause")
      iconText: RunGlyphs.glyphOf("parked")
      enabled: controls.enabledOf("pause")
      tooltipText: controls.tooltipOf("pause")
      onClicked: if (pauseButton.enabled) controls.actionRequested("pause")
    }

    UI.ActionButton {
      id: resumeButton
      objectName: "runControlResume"
      theme: controls.theme
      visible: controls.resumeShown
      text: controls.labelOf("resume", "Resume")
      iconText: RunGlyphs.glyphOf("running")
      enabled: controls.enabledOf("resume")
      tooltipText: controls.tooltipOf("resume")
      onClicked: if (resumeButton.enabled) controls.actionRequested("resume")
    }

    UI.ActionButton {
      id: cancelButton
      objectName: "runControlCancel"
      theme: controls.theme
      tone: "danger"
      text: controls.labelOf("cancel", "Cancel")
      iconText: RunGlyphs.glyphOf("cancelled")
      enabled: controls.enabledOf("cancel")
      tooltipText: controls.tooltipOf("cancel")
      onClicked: if (cancelButton.enabled) controls.actionRequested("cancel")
    }
  }

  UI.ThemedText {
    objectName: "runControlCaption"
    variant: "caption"
    theme: controls.theme
    visible: controls.buttonsShown && controls.wholeRun
    text: "applies to the whole run"
  }

  UI.ThemedText {
    objectName: "runControlReason"
    variant: "caption"
    theme: controls.theme
    width: parent.width
    visible: controls.reasonText !== ""
    text: controls.reasonText
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runControlWaiting"
    variant: "caption"
    theme: controls.theme
    width: parent.width
    visible: controls.waiting && controls.requestPending && controls.waitingText !== ""
    text: controls.waitingText
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runControlError"
    variant: "caption"
    theme: controls.theme
    width: parent.width
    visible: controls.errorText !== ""
    text: controls.errorText
    color: controls.theme ? controls.theme.urgent : Color.urgent
    wrapMode: Text.WordWrap
  }
}
