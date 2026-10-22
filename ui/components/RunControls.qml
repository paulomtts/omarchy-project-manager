import QtQuick
import qs.Commons
import qs.Commons as Cm
import "../../core/domain/runs.js" as Runs
import "../components" as UI
import "../theme" as T

// One run's buttons and the lines under them: "applies to the whole run" on a
// story or subtask card, the store's still-waiting line and the control error
// for this run.
//
// Presentation only, like RunIndicator: it imports no store. The owner passes
// the run and what the store says about it (the action pending for it, whether
// that request is 30 s old, the control error for this run) and decides when
// the buttons show (`showButtons`); a click emits actionRequested with the
// UI's name -- cancel, pause, close, resume or relaunch, never the store's
// reset -- and what that click does is the owner's business.
//
// The buttons are exactly Runs.visibleActions(run), left to right: running
// Cancel, Pause; parked Close, Resume; escalated and dead Close, Relaunch;
// Integrate drops Pause, Cancel and Close; anything else shows nothing.
// `relaunchShown: false` drops Relaunch (Run detail has its own; a card has
// no relaunch path). No button is ever disabled, with one exception: while
// a request is pending, only that request's button shows (a pending reset is
// the Close button), labelled `<Word> requested…`, disabled, as a progress
// marker; an unknown pending action shows no button at all. With nothing to
// show the component is 0 tall. There is no reason line: nothing shown is
// disabled for a reason.
Column {
  id: controls

  property var theme: T.Theme {}
  // One normalised run, as RunStore.runs holds them, or null.
  property var run: null
  // "" or the store's action pending for this run: pause, resume, cancel or reset.
  property string pendingAction: ""
  // That request is 30 s or more old.
  property bool waiting: false
  property string waitingText: ""
  // The control error for THIS run; "" otherwise.
  property string errorText: ""
  // The controls sit on a story or subtask card: the labels say "run".
  property bool wholeRun: false
  // The owner's rule for showing the buttons; a pending marker shows anyway.
  property bool showButtons: true
  // Whether Relaunch may show at all.
  property bool relaunchShown: true

  signal actionRequested(string action)

  // The UI actions this run shows, in order (Runs.visibleActions, minus
  // relaunch when relaunchShown is false).
  readonly property var shownActions: {
    var all = Runs.visibleActions(controls.run)
    return controls.relaunchShown ? all : all.filter(function(a) { return a !== "relaunch" })
  }
  readonly property bool requestPending: controls.pendingAction !== ""
  // The UI button of the pending request: reset is Close; "" when nothing is
  // pending or the pending value is unknown.
  readonly property string pendingButton: controls.pendingAction === "reset" ? "close"
    : controls.pendingAction === "pause" || controls.pendingAction === "resume" || controls.pendingAction === "cancel"
      ? controls.pendingAction : ""
  readonly property bool buttonsShown: controls.requestPending ? controls.pendingButton !== ""
    : controls.showButtons && controls.shownActions.length > 0

  spacing: Style.space(2)

  // Whether the button for `action` (a UI name) shows.
  function shows(action) {
    if (controls.requestPending) return controls.pendingButton === action
    return controls.showButtons && controls.shownActions.indexOf(action) >= 0
  }

  function labelOf(action, word) {
    if (controls.pendingButton === action) return word + " requested…"
    return controls.wholeRun ? word + " run" : word
  }

  // A click: nothing while a request is pending (the marker is no action).
  function ask(action) {
    if (!controls.requestPending) controls.actionRequested(action)
  }

  // At most one of Cancel and Close ever shows, so this fixed order renders
  // every visibleActions list left to right.
  Row {
    objectName: "runControlButtons"
    visible: controls.buttonsShown
    spacing: Style.space(6)

    UI.ActionButton {
      objectName: "runControlCancel"
      theme: controls.theme
      tone: "danger"
      visible: controls.shows("cancel")
      text: controls.labelOf("cancel", "Cancel")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("cancel")
    }

    UI.ActionButton {
      objectName: "runControlClose"
      theme: controls.theme
      tone: "close"
      visible: controls.shows("close")
      text: controls.labelOf("close", "Close")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("close")
    }

    UI.ActionButton {
      objectName: "runControlPause"
      theme: controls.theme
      tone: "warn"
      visible: controls.shows("pause")
      text: controls.labelOf("pause", "Pause")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("pause")
    }

    UI.ActionButton {
      objectName: "runControlResume"
      theme: controls.theme
      tone: "accent"
      visible: controls.shows("resume")
      text: controls.labelOf("resume", "Resume")
      enabled: !controls.requestPending
      tooltipText: controls.requestPending ? "Waiting for the run to act on the request" : ""
      onClicked: controls.ask("resume")
    }

    UI.ActionButton {
      objectName: "runControlRelaunch"
      theme: controls.theme
      tone: "accent"
      visible: controls.shows("relaunch")
      text: controls.labelOf("relaunch", "Relaunch")
      enabled: !controls.requestPending
      tooltipText: ""
      onClicked: controls.ask("relaunch")
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
    color: controls.theme ? controls.theme.urgent : Cm.Color.urgent
    wrapMode: Text.WordWrap
  }
}
