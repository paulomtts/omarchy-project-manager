import QtQuick
import qs.Commons
import "../components" as UI
import "../theme" as T

// The Resume dialog over a dimmed backdrop: `Resume run <runLabel>`, why am
// needs the verify commands, a VerifyCommandsField (prefix `resume`), that the
// set is saved for the project, `error` in urgent, then Cancel and `⟳ Resume`.
// Renders and emits only: reads shown, runLabel, commands, allowNoVerification,
// error and theme and never changes them. Emits commandsEdited(commands) and
// allowNoVerificationEdited(on) as the field does, confirmRequested() for a
// click on Resume while canResume, and cancelRequested() for Cancel, the
// backdrop or Escape in a verify row; Return never confirms. canResume is the
// verify rule of Runs.validateDispatch: the opt-out, or a string command with
// non-whitespace content. focusItem is the first verify row. objectNames:
// resumeDialogBackdrop, resumeDialogCard, resumeDialogTitle, resumeDialogBody,
// resumeVerify…, resumeDialogSaved, resumeDialogError, resumeDialogCancel,
// resumeDialogAccept.
Item {
  id: dialog
  objectName: "resumeVerifyDialog"
  z: 100

  property bool shown: false
  // The run as the heading names it, e.g. `…4a51d663`.
  property string runLabel: ""
  // A list, or the array-like a list arrives as; anything else holds no command.
  property var commands: []
  property bool allowNoVerification: false
  property string error: ""
  // Colours and fonts; null falls back to the shell's Color.
  property var theme: T.Theme {}

  // Read through the field's children, so a row made again is picked up.
  readonly property Item focusItem: dialog.firstRow(verifyField.children)
  readonly property bool canResume: dialog.allowNoVerification || dialog.holdsCommand(dialog.commands)
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent

  signal commandsEdited(var commands)
  signal allowNoVerificationEdited(bool on)
  signal confirmRequested()
  signal cancelRequested()

  visible: shown

  function holdsCommand(list) {
    if (!list || typeof list !== "object" || typeof list.length !== "number") return false
    for (var i = 0; i < list.length; i++) {
      if (typeof list[i] === "string" && list[i].trim() !== "") return true
    }
    return false
  }

  // The `resumeVerify0` text field among the field's rows; null before it exists.
  function firstRow(rows) {
    for (var i = 0; i < rows.length; i++) {
      var kids = rows[i] ? rows[i].children : []
      for (var j = 0; j < kids.length; j++) {
        if (kids[j].objectName === "resumeVerify0") return kids[j]
      }
    }
    return null
  }

  // Escape in a verify row cancels; every other key is left to the row.
  function rowKey(event) {
    if (event.key !== Qt.Key_Escape) return
    dialog.cancelRequested()
    event.accepted = true
  }

  UI.ModalCard {
    anchors.fill: parent
    shown: true
    maxWidth: Style.space(520)
    maxHeight: dialog.height - Style.space(48)
    backdropObjectName: "resumeDialogBackdrop"
    cardObjectName: "resumeDialogCard"
    onDismissed: dialog.cancelRequested()

    UI.ThemedText {
      objectName: "resumeDialogTitle"
      variant: "heading"
      theme: dialog.theme
      width: parent.width
      text: "Resume run " + dialog.runLabel
      font.bold: true
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "resumeDialogBody"
      variant: "small"
      theme: dialog.theme
      width: parent.width
      text: "am does not record the verify commands. They run for every subtask without a checkpoint, merged bases and Integrate."
      wrapMode: Text.WordWrap
    }

    UI.VerifyCommandsField {
      id: verifyField
      width: parent.width
      objectNamePrefix: "resume"
      theme: dialog.theme
      commands: dialog.commands
      allowNoVerification: dialog.allowNoVerification
      editable: true
      onCommandsEdited: function(commands) { dialog.commandsEdited(commands) }
      onAllowNoVerificationEdited: function(on) { dialog.allowNoVerificationEdited(on) }
      onKeyPressed: function(event) { dialog.rowKey(event) }
    }

    UI.ThemedText {
      objectName: "resumeDialogSaved"
      variant: "caption"
      theme: dialog.theme
      width: parent.width
      text: "Saved for this project and reused by later resumes and dispatches."
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "resumeDialogError"
      variant: "small"
      theme: dialog.theme
      visible: dialog.error !== ""
      width: parent.width
      text: dialog.error
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        objectName: "resumeDialogCancel"
        text: "Cancel"
        theme: dialog.theme
        onClicked: dialog.cancelRequested()
      }

      UI.ActionButton {
        objectName: "resumeDialogAccept"
        iconText: "⟳"
        text: "Resume"
        enabled: dialog.canResume
        theme: dialog.theme
        onClicked: if (dialog.canResume) dialog.confirmRequested()
      }
    }
  }
}
