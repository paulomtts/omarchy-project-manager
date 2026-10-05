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

  readonly property Item focusItem: dialog.form ? baseField : cancelButton
  readonly property bool canStart: dialog.dispatchState === "ready"
  readonly property bool busy: dialog.dispatchState === "starting"
  // The store takes edits in these states (setDispatchField); never while a
  // start is in flight, and never without a form.
  readonly property bool editable: !!dialog.form
    && ["previewing", "ready", "refused", "failed"].indexOf(dialog.dispatchState) >= 0

  // Every object prop is read guarded: a refused target has no form, and
  // tearing a view down nulls them while these bindings still run once.
  readonly property string targetLevel: dialog.target && typeof dialog.target.level === "string"
    ? dialog.target.level : ""
  readonly property color foregroundColor: dialog.theme ? dialog.theme.foreground : Color.foreground
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent
  readonly property color dimColor: dialog.theme ? dialog.theme.dim : Color.foreground
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

  // The preview area shows exactly one of these, checked in this order.
  readonly property bool showRefusal: dialog.dispatchState === "refused" || dialog.dispatchState === "failed"
  readonly property bool showSubtask: !dialog.showRefusal && dialog.targetLevel === "subtask"
  readonly property bool showChecking: !dialog.showRefusal && !dialog.showSubtask
    && dialog.dispatchState === "previewing"
  readonly property bool showSummary: !dialog.showRefusal && !dialog.showSubtask
    && ["ready", "starting", "started"].indexOf(dialog.dispatchState) >= 0
  // A failed launch adds its exit code, log path and tail under the sentence.
  readonly property bool showLaunch: dialog.dispatchState === "failed"
  readonly property string integrateText: dialog.preview && typeof dialog.preview.integrate === "string"
    ? dialog.preview.integrate : ""
  readonly property string summaryText: {
    var summary = dialog.preview && typeof dialog.preview.summary === "string" ? dialog.preview.summary : ""
    return summary === "" && dialog.integrateText === ""
      ? "am accepted the plan; it could not be summarised here" : summary
  }
  // The tail's last lines only: the log holds the rest, and the card keeps its
  // buttons in view (start-run.py sends up to 20 lines).
  readonly property string tailText: {
    var lines = dialog.logTail.split("\n")
    return lines.slice(Math.max(0, lines.length - 6)).join("\n")
  }

  signal fieldEdited(string name, var value)
  signal startRequested()
  signal cancelRequested()

  visible: shown
  onShownChanged: dialog.syncFields()
  onFormChanged: dialog.syncFields()
  Component.onCompleted: dialog.syncFields()

  function cancel() {
    if (!dialog.busy) dialog.cancelRequested()
  }

  // Escape in any field cancels (not while starting); Return is left alone,
  // so it never starts a run.
  function fieldKey(event) {
    if (event.key !== Qt.Key_Escape) return
    dialog.cancel()
    event.accepted = true
  }

  // A form value as its field shows it; a missing key reads as "".
  function formText(name) {
    var value = dialog.form ? dialog.form[name] : undefined
    return value === undefined || value === null ? "" : String(value)
  }

  // All digits is the number; anything else goes out as the trimmed text, and
  // the store's validateDispatch refuses it with its own sentence.
  function parallelValue(text) {
    var trimmed = String(text).trim()
    return /^[0-9]+$/.test(trimmed) ? parseInt(trimmed, 10) : trimmed
  }

  // Owner -> fields, never bound: a field emits only when it says something
  // other than the form, and these assignments make the two agree, so a new
  // form from the owner echoes nothing.
  function syncFields() {
    if (baseField.text !== dialog.formText("base")) baseField.text = dialog.formText("base")
    if (prefixField.text !== dialog.formText("prefix")) prefixField.text = dialog.formText("prefix")
    if (dialog.parallelValue(parallelField.text) !== dialog.parallelValue(dialog.formText("parallelism")))
      parallelField.text = dialog.formText("parallelism")
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

    Column {
      objectName: "dispatchForm"
      visible: !!dialog.form
      width: parent.width
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        UI.ThemedText {
          id: baseLabel
          variant: "caption"
          theme: dialog.theme
          text: "Base"
        }

        TextField {
          id: baseField
          objectName: "dispatchBase"
          width: Math.max(0, (parent.width - baseLabel.width - prefixLabel.width - 3 * parent.spacing) / 2)
          foreground: dialog.foregroundColor
          placeholderText: "main"
          enabled: dialog.editable
          // Verbatim: the store trims.
          onTextChanged: if (text !== dialog.formText("base")) dialog.fieldEdited("base", text)
          Keys.onPressed: function(event) { dialog.fieldKey(event) }
        }

        UI.ThemedText {
          id: prefixLabel
          variant: "caption"
          theme: dialog.theme
          text: "Prefix"
        }

        TextField {
          id: prefixField
          objectName: "dispatchPrefix"
          width: baseField.width
          foreground: dialog.foregroundColor
          enabled: dialog.editable
          onTextChanged: if (text !== dialog.formText("prefix")) dialog.fieldEdited("prefix", text)
          Keys.onPressed: function(event) { dialog.fieldKey(event) }
        }
      }

      // The opt-out from verification is a chip, so the form adds no checkbox.
      UI.Chip {
        id: noVerifyChip
        objectName: "dispatchNoVerify"
        theme: dialog.theme
        text: "run without any verification"
        active: !!dialog.form && dialog.form.allowNoVerification === true
        busy: !dialog.editable
        tint: noVerifyChip.active ? dialog.urgentColor : dialog.dimColor
        onClicked: dialog.fieldEdited("allowNoVerification", !noVerifyChip.active)
      }

      Row {
        spacing: Style.space(8)

        UI.ThemedText {
          variant: "caption"
          theme: dialog.theme
          text: "Parallel"
        }

        TextField {
          id: parallelField
          objectName: "dispatchParallel"
          width: Style.space(48)
          foreground: dialog.foregroundColor
          enabled: dialog.editable
          // Compared as values, so the owner's 6 agrees with a typed " 6 ".
          onTextChanged: {
            var value = dialog.parallelValue(text)
            if (value !== dialog.parallelValue(dialog.formText("parallelism")))
              dialog.fieldEdited("parallelism", value)
          }
          Keys.onPressed: function(event) { dialog.fieldKey(event) }
        }

        UI.ThemedText {
          variant: "caption"
          theme: dialog.theme
          text: "stories at once"
        }
      }
    }

    UI.ThemedText {
      objectName: "dispatchPreviewHeading"
      variant: "caption"
      theme: dialog.theme
      text: dialog.targetLevel === "board" || dialog.targetLevel === "milestone"
        ? "Preview  (am run --dry-run)" : "Preview"
    }

    // A refusal (the store's, am's or a failed launch's) verbatim: no parsing.
    UI.ThemedText {
      objectName: "dispatchRefusal"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showRefusal
      width: parent.width
      text: dialog.error
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchExitCode"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showLaunch && typeof dialog.exitCode === "number"
      text: "Exit code " + dialog.exitCode
    }

    UI.ThemedText {
      objectName: "dispatchLogPath"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showLaunch && dialog.logPath !== ""
      width: parent.width
      text: "Log: " + dialog.logPath
      elide: Text.ElideMiddle
    }

    UI.ThemedText {
      objectName: "dispatchLogTail"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showLaunch && dialog.logTail !== ""
      width: parent.width
      text: dialog.tailText
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }

    UI.ThemedText {
      objectName: "dispatchSubtaskNote"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showSubtask
      width: parent.width
      text: "No preview: am has no dry run for one subtask"
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchStory"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSubtask && dialog.storyTitle !== ""
      width: parent.width
      text: "Story   \"" + dialog.storyTitle + "\""
      elide: Text.ElideRight
    }

    UI.ThemedText {
      objectName: "dispatchBlocked"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSubtask && dialog.blockedText !== ""
      width: parent.width
      text: dialog.blockedText
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchChecking"
      variant: "caption"
      theme: dialog.theme
      visible: dialog.showChecking
      text: "Checking…"
    }

    UI.ThemedText {
      objectName: "dispatchSummary"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSummary && dialog.summaryText !== ""
      width: parent.width
      text: dialog.summaryText
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchIntegrate"
      variant: "small"
      theme: dialog.theme
      visible: dialog.showSummary && dialog.integrateText !== ""
      width: parent.width
      text: dialog.integrateText
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
