import QtQuick
import qs.Commons
import qs.Ui
import "../components" as UI
import "../theme" as T

// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does. The
// owner may pass a ready target label (targetLabel), a row of targets
// (targetChosen), a blocked story's milestone, whose action emits
// suggestionRequested(), and a Start that takes two clicks (confirmFirst).
// At step "project" it lists the projects instead (projectRows), with Cancel
// only; the owner maps projectChosen onto dispatchProjectPick.
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
  // The owner's ready-made target text (RunStore's dispatchTargetLabel); ""
  // builds it from the level and targetTitle. Only the target line reads it.
  property string targetLabel: ""
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
  // The Runs entry's targets, [{id, label}]; [] hides the row. targetChoice is
  // the active one's id.
  property var targetChoices: []
  property string targetChoice: ""
  // A blocked story's milestone {id, title}; with a refusal it shows the
  // retarget action.
  property var suggestion: null
  // Start takes two clicks: the first only arms it (a subtask has no preview,
  // so ready alone is not an explicit confirm).
  property bool confirmFirst: false
  readonly property bool armed: arming.armed
  // RunStore's dispatchStep. "project" shows the project list in place of the
  // target line, the form, the preview, the warning and Start; any other value
  // shows those.
  property string step: ""
  // RunStore's dispatchProjectRows, [{root, name, open, enabled, reason}];
  // anything not array-like reads as [].
  property var projectRows: []
  readonly property bool atProject: dialog.step === "project"
  readonly property bool hasEnabledProject: dialog.nextEnabledProject(0, 1) >= 0

  readonly property Item focusItem: dialog.form ? baseField : cancelButton
  readonly property bool canStart: dialog.dispatchState === "ready"
  readonly property bool busy: dialog.dispatchState === "starting"
  // The store takes edits in these states (setDispatchField); never while a
  // start is in flight, and never without a form.
  readonly property bool editable: !!dialog.form
    && ["previewing", "ready", "refused", "failed"].indexOf(dialog.dispatchState) >= 0
  // The verify rows are counted, not listed: typing in a row sends a list of
  // the same length, so the row (its focus, its cursor) is never recreated.
  readonly property int verifyRows: Math.max(1, dialog.storedVerify().length)
  readonly property bool hasChoices: !!dialog.targetChoices && typeof dialog.targetChoices.length === "number"
    && dialog.targetChoices.length > 0
  readonly property bool canOffer: !dialog.atProject && dialog.dispatchState === "refused" && !!dialog.suggestion
    && typeof dialog.suggestion.id === "string" && dialog.suggestion.id !== ""

  // Every object prop is read guarded: a refused target has no form, and
  // tearing a view down nulls them while these bindings still run once.
  readonly property string targetLevel: dialog.target && typeof dialog.target.level === "string"
    ? dialog.target.level : ""
  readonly property color foregroundColor: dialog.theme ? dialog.theme.foreground : Color.foreground
  readonly property color urgentColor: dialog.theme ? dialog.theme.urgent : Color.urgent
  readonly property color dimColor: dialog.theme ? dialog.theme.dim : Color.foreground
  readonly property string targetText: {
    if (dialog.targetLabel !== "") return dialog.targetLabel
    var quoted = "\"" + dialog.targetTitle + "\""
    switch (dialog.targetLevel) {
    case "board": return "Whole board"
    case "milestone": return "Milestone " + quoted
    case "story": return "Story " + quoted
    case "subtask": return "Subtask " + quoted
    }
    return dialog.targetTitle !== "" ? quoted : "No card"
  }

  // The preview area shows exactly one of these, checked in this order; the
  // project step shows none.
  readonly property bool showRefusal: !dialog.atProject
    && (dialog.dispatchState === "refused" || dialog.dispatchState === "failed")
  readonly property bool showSubtask: !dialog.atProject && !dialog.showRefusal && dialog.targetLevel === "subtask"
  readonly property bool showChecking: !dialog.atProject && !dialog.showRefusal && !dialog.showSubtask
    && dialog.dispatchState === "previewing"
  readonly property bool showSummary: !dialog.atProject && !dialog.showRefusal && !dialog.showSubtask
    && ["ready", "starting", "started"].indexOf(dialog.dispatchState) >= 0
  // A failed launch adds its exit code, log path and tail under the sentence.
  readonly property bool showLaunch: dialog.showRefusal && dialog.dispatchState === "failed"
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
  signal targetChosen(string id)
  signal suggestionRequested()
  signal projectChosen(string root)

  visible: shown
  // Any change to what Start would start drops the first click.
  onShownChanged: { arming.armed = false; dialog.syncFields() }
  onFormChanged: { arming.armed = false; dialog.syncFields() }
  onDispatchStateChanged: arming.armed = false
  onTargetChanged: arming.armed = false
  onConfirmFirstChanged: arming.armed = false
  Component.onCompleted: dialog.syncFields()

  QtObject {
    id: arming
    property bool armed: false
  }

  // A click on Start: from ready only; with confirmFirst the first click arms
  // and only the second starts.
  function start() {
    if (!dialog.canStart) return
    if (dialog.confirmFirst && !arming.armed) {
      arming.armed = true
      return
    }
    dialog.startRequested()
  }

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

  // The stored commands: a list, or the array-like a list arrives as through
  // createObject; anything else (missing, a string, null) reads as []. Read
  // straight from `form`, never through a bound property, which a formChanged
  // handler could still find holding the previous list.
  function storedVerify() {
    var verify = dialog.form ? dialog.form.verify : null
    if (!verify || typeof verify !== "object" || typeof verify.length !== "number") return []
    return Array.prototype.slice.call(verify)
  }

  function verifyAt(index) {
    var value = dialog.storedVerify()[index]
    return value === undefined || value === null ? "" : String(value)
  }

  // A fresh copy of the stored commands, padded with "" to the rows shown.
  function verifyPadded() {
    var stored = dialog.storedVerify(), list = []
    for (var i = 0; i < Math.max(1, stored.length); i++)
      list.push(stored[i] === undefined || stored[i] === null ? "" : String(stored[i]))
    return list
  }

  function editVerify(index, text) {
    var list = dialog.verifyPadded()
    list[index] = text
    dialog.fieldEdited("verify", list)
  }

  function removeVerify(index) {
    var list = dialog.verifyPadded()
    list.splice(index, 1)
    dialog.fieldEdited("verify", list)
  }

  function addVerify() {
    var list = dialog.verifyPadded()
    list.push("")
    dialog.fieldEdited("verify", list)
  }

  // Owner -> fields, never bound: a field emits only when it says something
  // other than the form, and these assignments make the two agree, so a new
  // form from the owner echoes nothing.
  function syncFields() {
    if (baseField.text !== dialog.formText("base")) baseField.text = dialog.formText("base")
    if (prefixField.text !== dialog.formText("prefix")) prefixField.text = dialog.formText("prefix")
    if (dialog.parallelValue(parallelField.text) !== dialog.parallelValue(dialog.formText("parallelism")))
      parallelField.text = dialog.formText("parallelism")
    // New rows sync themselves when the Repeater makes them.
    for (var i = 0; i < verifyRepeater.count; i++) {
      var row = verifyRepeater.itemAt(i)
      if (row) row.sync()
    }
  }


  // The project rows: a list, or the array-like a list arrives as through
  // createObject; anything else (null, an object, a string) reads as [].
  function projectList() {
    var rows = dialog.projectRows
    if (!rows || typeof rows !== "object" || typeof rows.length !== "number") return []
    return Array.prototype.slice.call(rows)
  }

  // A row's text field; a missing row or a non-string value reads as "".
  function projectText(row, key) {
    return row && typeof row[key] === "string" ? row[key] : ""
  }

  // Only a row whose enabled is exactly true takes the cursor or a pick.
  function rowEnabled(row) {
    return !!row && row.enabled === true
  }

  // The first enabled row from `from` on, stepping by `by` (1 or -1); -1 for none.
  function nextEnabledProject(from, by) {
    var rows = dialog.projectList()
    for (var i = from; i >= 0 && i < rows.length; i += by)
      if (dialog.rowEnabled(rows[i])) return i
    return -1
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
      text: dialog.atProject ? "Dispatch · 1 Project" : "Dispatch"
      font.bold: true
    }

    // The project step's rows, in the owner's order.
    Flickable {
      id: projectFlick
      objectName: "dispatchProjectList"
      visible: dialog.atProject
      width: parent.width
      height: Math.min(projectColumn.implicitHeight, Style.space(240))
      contentHeight: projectColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: projectColumn
        width: projectFlick.width
        spacing: Style.space(2)

        Repeater {
          id: projectRepeater
          model: dialog.atProject ? dialog.projectList() : []

          UI.ListRow {
            id: projectRow
            required property var modelData
            required index
            readonly property bool usable: dialog.rowEnabled(projectRow.modelData)
            objectName: "dispatchProjectRow" + projectRow.index
            width: projectColumn.width
            theme: dialog.theme

            Row {
              width: parent.width
              spacing: Style.space(8)

              UI.ThemedText {
                objectName: "dispatchProjectName" + projectRow.index
                theme: dialog.theme
                width: Math.max(0, parent.width - (openMark.visible ? openMark.width + parent.spacing : 0))
                text: dialog.projectText(projectRow.modelData, "name")
                color: projectRow.usable ? dialog.foregroundColor : dialog.dimColor
                elide: Text.ElideRight
              }

              UI.ThemedText {
                id: openMark
                objectName: "dispatchProjectOpen" + projectRow.index
                variant: "caption"
                theme: dialog.theme
                visible: !!projectRow.modelData && projectRow.modelData.open === true
                text: "open"
              }
            }

            UI.ThemedText {
              objectName: "dispatchProjectReason" + projectRow.index
              variant: "caption"
              theme: dialog.theme
              visible: !projectRow.usable
              width: parent.width
              text: dialog.projectText(projectRow.modelData, "reason")
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    UI.ThemedText {
      objectName: "dispatchProjectEmpty"
      theme: dialog.theme
      visible: dialog.atProject && !dialog.hasEnabledProject
      width: parent.width
      text: dialog.projectList().length === 0 ? "No projects registered" : "No project's board can be read"
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchTarget"
      theme: dialog.theme
      visible: !dialog.atProject
      width: parent.width
      text: "Target   " + dialog.targetText
      elide: Text.ElideRight
    }

    // The Runs entry's targets; a click on the active one says nothing.
    UI.ChipRow {
      objectName: "dispatchTargetChoices"
      width: parent.width
      visible: dialog.hasChoices && !dialog.atProject
      chipPrefix: "dispatchTargetChoice"
      theme: dialog.theme
      model: dialog.hasChoices ? dialog.targetChoices : []
      active: dialog.targetChoice
      busy: dialog.busy
      onChosen: function(id) { if (id !== dialog.targetChoice) dialog.targetChosen(id) }
    }

    Column {
      objectName: "dispatchForm"
      visible: !!dialog.form && !dialog.atProject
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

      UI.ThemedText {
        objectName: "dispatchVerifyLabel"
        variant: "caption"
        theme: dialog.theme
        text: "Verify"
      }

      Repeater {
        id: verifyRepeater
        model: dialog.verifyRows

        Row {
          id: verifyRow
          required property int index
          width: parent ? parent.width : 0
          spacing: Style.space(8)

          function sync() {
            var want = dialog.verifyAt(verifyRow.index)
            if (verifyField.text !== want) verifyField.text = want
          }

          Component.onCompleted: verifyRow.sync()

          TextField {
            id: verifyField
            objectName: "dispatchVerify" + verifyRow.index
            width: Math.max(0, verifyRow.width - (removeButton.visible ? removeButton.width + verifyRow.spacing : 0))
            foreground: dialog.foregroundColor
            placeholderText: "uv run pytest"
            enabled: dialog.editable
            onTextChanged: if (text !== dialog.verifyAt(verifyRow.index)) dialog.editVerify(verifyRow.index, text)
            Keys.onPressed: function(event) { dialog.fieldKey(event) }
          }

          UI.ActionButton {
            id: removeButton
            objectName: "dispatchVerifyRemove" + verifyRow.index
            visible: dialog.verifyRows >= 2
            text: "✕"
            enabled: dialog.editable
            theme: dialog.theme
            onClicked: dialog.removeVerify(verifyRow.index)
          }
        }
      }

      UI.ActionButton {
        objectName: "dispatchVerifyAdd"
        text: "+"
        enabled: dialog.editable
        theme: dialog.theme
        onClicked: dialog.addVerify()
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
      visible: !dialog.atProject
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

    // A blocked story's retarget onto its milestone, which the target line
    // already names.
    UI.ActionButton {
      objectName: "dispatchSuggest"
      visible: dialog.canOffer
      text: "Dispatch the milestone instead"
      theme: dialog.theme
      onClicked: if (dialog.canOffer) dialog.suggestionRequested()
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

    // The cost warning shows in every state, a refused target's included; the
    // project step has none.
    UI.ThemedText {
      objectName: "dispatchWarning"
      variant: "small"
      theme: dialog.theme
      visible: !dialog.atProject
      width: parent.width
      text: dialog.targetLevel === "board"
        ? "⚠ This starts agents on every open milestone and spends tokens."
        : "⚠ This starts agents and spends tokens."
      color: dialog.urgentColor
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "dispatchConfirmNote"
      variant: "caption"
      theme: dialog.theme
      visible: arming.armed && !dialog.atProject
      width: parent.width
      text: "Click Confirm start to start this subtask."
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
        visible: !dialog.atProject
        iconText: "▶"
        text: dialog.busy ? "Starting…" : arming.armed ? "Confirm start" : "Start run"
        enabled: dialog.canStart
        theme: dialog.theme
        onClicked: dialog.start()
      }
    }
  }
}
