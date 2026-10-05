import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does.
Item {
  id: dialog
  objectName: "dispatchDialog"
  z: 100

  property bool shown: false
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  // RunStore's dispatchState. Not `state`: Item already has one.
  property string dispatchState: "idle"
  // RunStore's dispatchTarget: {command, flags, level, offered, reason, suggest}.
  property var target: null
  // The target card's title; "" for the board.
  property string targetTitle: ""
  // RunStore's dispatchForm: {base, prefix, verify, parallelism,
  // allowNoVerification}; null for a target refused at open.
  property var form: null
  // RunStore's dispatchPreview: {board, integrate, summary}.
  property var preview: null
  property string error: ""
  property string logPath: ""
  property string logTail: ""
  property var exitCode: null
  // am has no dry run for one subtask, so the owner composes these instead.
  property string storyTitle: ""
  property string blockedText: ""

  readonly property Item focusItem: cancelButton
  readonly property bool canStart: dialog.dispatchState === "ready"
  readonly property bool busy: dialog.dispatchState === "starting"

  // Every object prop is read guarded: a refused target has no form, and
  // tearing a view down nulls them while these bindings still run once.
  readonly property string targetLevel: dialog.target && typeof dialog.target.level === "string"
    ? dialog.target.level : ""
  readonly property color foregroundColor: dialog.theme ? dialog.theme.foreground : Color.foreground
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent
  readonly property string targetText: {
    var quoted = "\"" + dialog.targetTitle + "\""
    switch (dialog.targetLevel) {
    case "board": return "Whole board"
    case "milestone": return "Milestone " + quoted
    case "story": return "Story " + quoted
    case "subtask": return "Subtask " + quoted
    }
    return dialog.targetTitle !== "" ? quoted : "No card"
  }

  signal fieldEdited(string name, var value)
  signal startRequested()
  signal cancelRequested()

  visible: shown

  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }

  UI.ModalCard {
    id: modal
    anchors.fill: parent
    shown: true
    dismissable: !dialog.busy
    maxWidth: Style.space(520)
    maxHeight: dialog.height - Style.space(48)
    backdropObjectName: "dispatchBackdrop"
    cardObjectName: "dispatchCard"
    onDismissed: dialog.cancel()

    UI.ThemedText {
      objectName: "dispatchHeading"
      variant: "heading"
      theme: dialog.theme
      text: "Dispatch"
      font.bold: true
    }

    UI.ThemedText {
      objectName: "dispatchTarget"
      theme: dialog.theme
      width: parent.width
      text: "Target   " + dialog.targetText
      elide: Text.ElideRight
    }

    // The cost warning shows in every state, a refused target's included.
    UI.ThemedText {
      objectName: "dispatchWarning"
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: dialog.targetLevel === "board"
        ? "⚠ This starts agents on every open milestone and spends tokens."
        : "⚠ This starts agents and spends tokens."
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        id: cancelButton
        objectName: "dispatchCancel"
        text: "Cancel"
        enabled: !dialog.busy
        theme: dialog.theme
        onClicked: dialog.cancel()
      }

      UI.ActionButton {
        objectName: "dispatchStart"
        iconText: "▶"
        text: dialog.busy ? "Starting…" : "Start run"
        enabled: dialog.canStart
        theme: dialog.theme
        onClicked: if (dialog.canStart) dialog.startRequested()
      }
    }
  }
}
