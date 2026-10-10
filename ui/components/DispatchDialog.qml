import QtQuick
import qs.Commons
import qs.Ui
import "../../core/domain/text.js" as TextQuery
import "../components" as UI
import "../theme" as T

// The dispatch modal over a dimmed backdrop: what will run, the form the store
// checks, what am would do, and what it costs. Renders and emits only -- the
// owner passes RunDispatchStore's dispatch values in and maps fieldEdited,
// startRequested and cancelRequested onto setDispatchField, dispatchStart and
// closeDispatch. Only a click on Start starts a run: Return never does. The
// owner may pass a ready target label (targetLabel), a row of targets
// (targetChosen), a blocked story's milestone, whose action emits
// suggestionRequested(), and a Start that takes two clicks (confirmFirst).
// At step "project" it lists the projects instead (projectRows), with Cancel
// only; the owner maps projectChosen onto dispatchProjectPick. At step
// "target" it lists the picked project's targets under a filter (targetRows),
// with Back and Cancel; the owner maps targetPicked onto dispatchTargetPick.
// Back shows at steps "target" and "form"; the owner maps backRequested onto
// dispatchBack.
Item {
  id: dialog
  objectName: "dispatchDialog"
  z: 100

  property bool shown: false
  // The one input for every colour and font: Panel passes its Theme down,
  // and a standalone instance renders with the shell defaults.
  property var theme: T.Theme {}
  // RunDispatchStore's dispatchState. Not `state`: Item already has one.
  property string dispatchState: "idle"
  // RunDispatchStore's dispatchTarget: {command, flags, level, offered, reason, suggest}.
  property var target: null
  // The target card's title; "" for the board.
  property string targetTitle: ""
  // The owner's ready-made target text (RunDispatchStore's dispatchTargetLabel); ""
  // builds it from the level and targetTitle. Only the target line reads it.
  property string targetLabel: ""
  // RunDispatchStore's dispatchForm: {base, prefix, verify, parallelism,
  // allowNoVerification}; null for a target refused at open.
  property var form: null
  // RunDispatchStore's dispatchPreview: {board, integrate, summary}.
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
  // RunDispatchStore's dispatchStep. "project" shows the project list and "target"
  // the target list, each in place of the target line, the form, the preview,
  // the warning and Start; any other value shows those.
  property string step: ""
  // The picked project's name, for the target step's heading.
  property string projectName: ""
  // RunDispatchStore's dispatchProjectRows, [{root, name, open, enabled, reason}];
  // anything not array-like reads as [].
  property var projectRows: []
  // RunDispatchStore's dispatchTargetRows, [{key, level, card, label, depth}];
  // anything not array-like reads as [].
  property var targetRows: []
  // RunDispatchStore's dispatchTargetLoading: the tree is still being read.
  property bool targetLoading: false
  // RunDispatchStore's dispatchTargetKey: the row the cursor lands on when the target
  // step is entered.
  property string targetKey: ""
  readonly property bool atProject: dialog.step === "project"
  readonly property bool atTarget: dialog.step === "target"
  // The form step's parts show at every step but the two pickers.
  readonly property bool atForm: !dialog.atProject && !dialog.atTarget
  // Back shows at the target step and at the form step a Runs dispatch reaches.
  readonly property bool canGoBack: dialog.atTarget || dialog.step === "form"
  readonly property bool hasEnabledProject: dialog.nextEnabledProject(0, 1) >= 0
  // The target rows the list shows; see shownTargets().
  readonly property var shownTargetRows: dialog.shownTargets()

  readonly property Item focusItem: dialog.atProject ? projectKeys
    : dialog.atTarget ? targetFilter
    : dialog.form ? baseField : cancelButton
  // The project step's cursor: a row index in projectRows, never a disabled
  // row; -1 with no enabled row and at every other step.
  readonly property int projectCursor: projectCursorState.index
  // The target step's cursor: an index in the shown target rows; -1 with no
  // shown row, while loading and at every other step.
  readonly property int targetCursor: targetCursorState.index
  readonly property bool canStart: dialog.dispatchState === "ready"
  readonly property bool busy: dialog.dispatchState === "starting"
  // The store takes edits in these states (setDispatchField); never while a
  // start is in flight, and never without a form.
  readonly property bool editable: !!dialog.form
    && ["previewing", "ready", "refused", "failed"].indexOf(dialog.dispatchState) >= 0
  readonly property bool hasChoices: !!dialog.targetChoices && typeof dialog.targetChoices.length === "number"
    && dialog.targetChoices.length > 0
  readonly property bool canOffer: dialog.atForm && dialog.dispatchState === "refused" && !!dialog.suggestion
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
  // two pickers show none.
  readonly property bool showRefusal: dialog.atForm
    && (dialog.dispatchState === "refused" || dialog.dispatchState === "failed")
  readonly property bool showSubtask: dialog.atForm && !dialog.showRefusal && dialog.targetLevel === "subtask"
  readonly property bool showChecking: dialog.atForm && !dialog.showRefusal && !dialog.showSubtask
    && dialog.dispatchState === "previewing"
  readonly property bool showSummary: dialog.atForm && !dialog.showRefusal && !dialog.showSubtask
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
  signal backRequested()
  signal targetPicked(string key)

  visible: shown
  // Any change to what Start would start drops the first click.
  onShownChanged: { arming.armed = false; dialog.syncFields(); dialog.resetProjectCursor(); dialog.resetTargetCursor() }
  onFormChanged: { arming.armed = false; dialog.syncFields() }
  onDispatchStateChanged: arming.armed = false
  onTargetChanged: arming.armed = false
  onConfirmFirstChanged: arming.armed = false
  onStepChanged: { dialog.resetProjectCursor(); dialog.resetTargetCursor() }
  onProjectRowsChanged: dialog.followProjectCursor()
  onTargetRowsChanged: dialog.followTargetCursor()
  onTargetLoadingChanged: dialog.followTargetCursor()
  onTargetKeyChanged: dialog.jumpToTargetKey()
  Component.onCompleted: { dialog.syncFields(); dialog.resetProjectCursor(); dialog.resetTargetCursor() }

  QtObject {
    id: arming
    property bool armed: false
  }

  // The cursor's row and its root, so new rows keep it on the same project.
  QtObject {
    id: projectCursorState
    property int index: -1
    property string root: ""
  }

  // The target cursor's row and its key, so new rows or a new filter keep it
  // on the same target.
  QtObject {
    id: targetCursorState
    property int index: -1
    property string key: ""
  }

  // Rows a step change, a new key or new rows bring are laid out after the
  // change; the reveal waits for them.
  Timer {
    id: targetReveal
    interval: 0
    onTriggered: dialog.revealTargetCursor()
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

  // Back one step: at the target step, and at the form step unless starting.
  function back() {
    if (dialog.canGoBack && !dialog.busy) dialog.backRequested()
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
    verifyField.sync()
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

  // The cursor onto an enabled row, or off with -1; any other index is ignored.
  function setProjectCursor(index) {
    if (index !== -1 && !dialog.rowEnabled(dialog.projectList()[index])) return
    projectCursorState.index = index
    projectCursorState.root = index === -1 ? "" : dialog.projectText(dialog.projectList()[index], "root")
  }

  // The project step starts on the first enabled row; any other step has no cursor.
  function resetProjectCursor() {
    dialog.setProjectCursor(dialog.step === "project" ? dialog.nextEnabledProject(0, 1) : -1)
  }

  // New rows keep the cursor on its root while that root has an enabled row.
  function followProjectCursor() {
    var rows = dialog.projectList()
    if (dialog.step === "project" && projectCursorState.index !== -1) {
      for (var i = 0; i < rows.length; i++) {
        if (dialog.rowEnabled(rows[i]) && dialog.projectText(rows[i], "root") === projectCursorState.root) {
          dialog.setProjectCursor(i)
          return
        }
      }
    }
    dialog.resetProjectCursor()
  }

  // Scrolls `flick` the least that shows the whole of `item`.
  function reveal(flick, item) {
    if (!item) return
    if (item.y < flick.contentY) flick.contentY = item.y
    else if (item.y + item.height > flick.contentY + flick.height)
      flick.contentY = item.y + item.height - flick.height
  }

  // Down (1) / Up (-1): the next enabled row that way, scrolled into view; the
  // cursor stays at either end.
  function moveProjectCursor(by) {
    if (projectCursorState.index === -1) return
    var next = dialog.nextEnabledProject(projectCursorState.index + by, by)
    if (next === -1) return
    dialog.setProjectCursor(next)
    dialog.reveal(projectFlick, projectRepeater.itemAt(next))
  }

  // A pick: at the project step and on an enabled row only.
  function pickProject(index) {
    if (!dialog.atProject || !dialog.rowEnabled(dialog.projectList()[index])) return
    dialog.setProjectCursor(index)
    dialog.projectChosen(dialog.projectText(dialog.projectList()[index], "root"))
  }

  // A hover moves the cursor onto an enabled row; a disabled row is ignored.
  function hoverProject(index) {
    if (dialog.atProject) dialog.setProjectCursor(index)
  }

  // Down / Up move the cursor, Return / Enter pick its row, Escape cancels;
  // any other key is left to the owner.
  function projectKey(event) {
    if (event.key === Qt.Key_Escape) dialog.cancel()
    else if (!dialog.atProject) return
    else if (event.key === Qt.Key_Down) dialog.moveProjectCursor(1)
    else if (event.key === Qt.Key_Up) dialog.moveProjectCursor(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dialog.pickProject(projectCursorState.index)
    else return
    event.accepted = true
  }

  // The target rows: a list, or the array-like a list arrives as through
  // createObject; anything else (null, an object, a string) reads as [].
  function targetList() {
    var rows = dialog.targetRows
    if (!rows || typeof rows !== "object" || typeof rows.length !== "number") return []
    return Array.prototype.slice.call(rows)
  }

  // A row is an object whose key is a non-empty string; anything else gives no row.
  function validTarget(row) {
    return !!row && typeof row === "object" && typeof row.key === "string" && row.key !== ""
  }

  // "Milestone", "Story" or "Subtask"; "" for the board and any other level.
  function targetLevelWord(row) {
    switch (row.level) {
    case "milestone": return "Milestone"
    case "story": return "Story"
    case "subtask": return "Subtask"
    }
    return ""
  }

  // "Whole board" for the board; else the card's string title, or "".
  function targetTitleOf(row) {
    if (row.level === "board") return "Whole board"
    var card = row.card
    return !!card && typeof card === "object" && typeof card.title === "string" ? card.title : ""
  }

  // The first 8 characters of the card's string id, or "".
  function targetShortId(row) {
    var card = row.card
    return !!card && typeof card === "object" && typeof card.id === "string" ? card.id.slice(0, 8) : ""
  }

  // A whole number >= 0; anything else reads as 0.
  function targetDepth(row) {
    var depth = row.depth
    return typeof depth === "number" && Number.isInteger(depth) && depth >= 0 ? depth : 0
  }

  // The valid rows whose title or short id holds the filter text, in
  // targetRows order; none while loading and at every other step.
  function shownTargets() {
    if (dialog.step !== "target" || dialog.targetLoading) return []
    var query = targetFilter.text
    return dialog.targetList().filter(function(row) {
      return dialog.validTarget(row)
        && (TextQuery.matchesQuery(dialog.targetTitleOf(row), query)
            || TextQuery.matchesQuery(dialog.targetShortId(row), query))
    })
  }

  // The index of the shown row whose key is `key`; -1 for none.
  function shownTargetIndex(rows, key) {
    for (var i = 0; i < rows.length; i++)
      if (rows[i].key === key) return i
    return -1
  }

  // The cursor onto a shown row, or off with -1; any other index is off.
  function setTargetCursor(index) {
    var rows = dialog.shownTargets()
    if (index < 0 || index >= rows.length) index = -1
    targetCursorState.index = index
    targetCursorState.key = index === -1 ? "" : rows[index].key
  }

  // targetKey's shown row, else shown row 0, else -1.
  function landingTarget() {
    var rows = dialog.shownTargets()
    var at = dialog.targetKey === "" ? -1 : dialog.shownTargetIndex(rows, dialog.targetKey)
    return at >= 0 ? at : rows.length > 0 ? 0 : -1
  }

  // Entering the target step clears the filter and lands the cursor, scrolled
  // into view; any other step has no cursor.
  function resetTargetCursor() {
    if (dialog.step === "target") targetFilter.text = ""
    dialog.setTargetCursor(dialog.step === "target" ? dialog.landingTarget() : -1)
    targetReveal.restart()
  }

  // New rows, loading or filter text keep the cursor on its key while that
  // row is shown; else it lands as on entry.
  function followTargetCursor() {
    var at = targetCursorState.key === "" ? -1
      : dialog.shownTargetIndex(dialog.shownTargets(), targetCursorState.key)
    dialog.setTargetCursor(at >= 0 ? at : dialog.landingTarget())
    targetReveal.restart()
  }

  // A new targetKey moves the cursor onto its row when that row is shown.
  function jumpToTargetKey() {
    if (dialog.step !== "target") return
    var at = dialog.shownTargetIndex(dialog.shownTargets(), dialog.targetKey)
    if (at === -1) return
    dialog.setTargetCursor(at)
    targetReveal.restart()
  }

  // Scrolls the target list the least that shows the cursor's row. A row
  // being replaced can still be a child, so the last one with the name wins.
  function revealTargetCursor() {
    if (targetCursorState.index === -1) return
    targetColumn.forceLayout()
    var name = "dispatchTargetRow" + targetCursorState.index
    var kids = targetColumn.children
    for (var i = kids.length - 1; i >= 0; i--) {
      if (kids[i].objectName === name) {
        dialog.reveal(targetFlick, kids[i])
        return
      }
    }
  }

  // A hover moves the cursor onto a shown row.
  function hoverTarget(index) {
    if (dialog.step === "target") dialog.setTargetCursor(index)
  }

  // Down (1) / Up (-1): the next shown row that way, scrolled into view; the
  // cursor stays at either end.
  function moveTargetCursor(by) {
    if (targetCursorState.index === -1) return
    var last = dialog.shownTargets().length - 1
    dialog.setTargetCursor(Math.max(0, Math.min(last, targetCursorState.index + by)))
    dialog.revealTargetCursor()
  }

  // A pick: at the target step and on a shown row only.
  function pickTarget(index) {
    var rows = dialog.shownTargets()
    if (dialog.step !== "target" || index < 0 || index >= rows.length) return
    dialog.setTargetCursor(index)
    dialog.targetPicked(rows[index].key)
  }

  // On the filter: Down / Up move the cursor, Return / Enter pick its row,
  // Backspace in an empty filter goes back, Escape cancels; any other key
  // edits the filter.
  function targetFieldKey(event) {
    if (event.key === Qt.Key_Escape) dialog.cancel()
    else if (dialog.step !== "target") return
    else if (event.key === Qt.Key_Down) dialog.moveTargetCursor(1)
    else if (event.key === Qt.Key_Up) dialog.moveTargetCursor(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dialog.pickTarget(targetCursorState.index)
    else if (event.key === Qt.Key_Backspace && targetFilter.text === "") dialog.back()
    else return
    event.accepted = true
  }

  // The project step's keys: focusItem at that step.
  Item {
    id: projectKeys
    objectName: "dispatchProjectKeys"
    Keys.onPressed: function(event) { dialog.projectKey(event) }
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
      text: dialog.atProject ? "Dispatch · 1 Project"
        : !dialog.atTarget ? "Dispatch"
        : dialog.projectName !== "" ? "Dispatch · 2 Target in " + dialog.projectName
        : "Dispatch · 2 Target"
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
            cursorIndex: dialog.projectCursor
            hoverCursorShape: projectRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHovered: function(index) { dialog.hoverProject(index) }
            onActivated: dialog.pickProject(projectRow.index)

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

    // The target step's keys: focusItem at that step.
    TextField {
      id: targetFilter
      objectName: "dispatchTargetFilter"
      visible: dialog.atTarget
      width: parent.width
      foreground: dialog.foregroundColor
      placeholderText: "Filter by title or id…"
      onTextChanged: dialog.followTargetCursor()
      Keys.onPressed: function(event) { dialog.targetFieldKey(event) }
    }

    // The target step's rows, in the owner's order, narrowed by the filter.
    Flickable {
      id: targetFlick
      objectName: "dispatchTargetList"
      visible: dialog.atTarget
      width: parent.width
      height: Math.min(targetColumn.implicitHeight, Style.space(240))
      contentHeight: targetColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      UI.FilterableList {
        id: targetColumn
        width: targetFlick.width
        theme: dialog.theme
        statusObjectName: "dispatchTargetStatus"
        loading: dialog.targetLoading
        loadingText: "Reading the board…"
        empty: dialog.shownTargetRows.length === 0
        filtered: targetFilter.text.trim() !== ""
        emptyText: "No target matches"
        filteredText: "No target matches"
        model: dialog.shownTargetRows
        rowDelegate: Component { TargetRow {} }
      }
    }

    UI.ThemedText {
      objectName: "dispatchTarget"
      theme: dialog.theme
      visible: dialog.atForm
      width: parent.width
      text: "Target   " + dialog.targetText
      elide: Text.ElideRight
    }

    // The Runs entry's targets; a click on the active one says nothing.
    UI.ChipRow {
      objectName: "dispatchTargetChoices"
      width: parent.width
      visible: dialog.hasChoices && dialog.atForm
      chipPrefix: "dispatchTargetChoice"
      theme: dialog.theme
      model: dialog.hasChoices ? dialog.targetChoices : []
      active: dialog.targetChoice
      busy: dialog.busy
      onChosen: function(id) { if (id !== dialog.targetChoice) dialog.targetChosen(id) }
    }

    Column {
      objectName: "dispatchForm"
      visible: !!dialog.form && dialog.atForm
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

      UI.VerifyCommandsField {
        id: verifyField
        width: parent.width
        objectNamePrefix: "dispatch"
        theme: dialog.theme
        commands: dialog.form ? dialog.form.verify : null
        allowNoVerification: !!dialog.form && dialog.form.allowNoVerification === true
        editable: dialog.editable
        onCommandsEdited: function(commands) { dialog.fieldEdited("verify", commands) }
        onAllowNoVerificationEdited: function(on) { dialog.fieldEdited("allowNoVerification", on) }
        onKeyPressed: function(event) { dialog.fieldKey(event) }
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
      visible: dialog.atForm
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
    // two pickers have none.
    UI.ThemedText {
      objectName: "dispatchWarning"
      variant: "small"
      theme: dialog.theme
      visible: dialog.atForm
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
      visible: arming.armed && dialog.atForm
      width: parent.width
      text: "Click Confirm start to start this subtask."
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.spacing.md

      UI.ActionButton {
        id: backButton
        objectName: "dispatchBack"
        visible: dialog.canGoBack
        text: "Back"
        enabled: !dialog.busy
        theme: dialog.theme
        onClicked: dialog.back()
      }

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
        visible: dialog.atForm
        iconText: "▶"
        text: dialog.busy ? "Starting…" : arming.armed ? "Confirm start" : "Start run"
        enabled: dialog.canStart
        theme: dialog.theme
        onClicked: dialog.start()
      }
    }
  }

  // One target row: the level word, the title and the short id on one line,
  // indented by depth.
  component TargetRow: UI.ListRow {
    id: targetRow
    required property var modelData
    required index
    objectName: "dispatchTargetRow" + targetRow.index
    width: targetFlick.width
    theme: dialog.theme
    cursorIndex: dialog.targetCursor
    onHovered: function(index) { dialog.hoverTarget(index) }
    onActivated: dialog.pickTarget(targetRow.index)
    // The cursor's row stays in view while the rows around it are laid out.
    onYChanged: if (targetRow.hasCursor) dialog.reveal(targetFlick, targetRow)
    onHeightChanged: if (targetRow.hasCursor) dialog.reveal(targetFlick, targetRow)

    Row {
      id: targetLine
      objectName: "dispatchTargetLine" + targetRow.index
      x: dialog.targetDepth(targetRow.modelData) * Style.space(16)
      width: Math.max(0, parent.width - targetLine.x)
      spacing: Style.space(8)

      UI.ThemedText {
        id: targetLevel
        objectName: "dispatchTargetLevel" + targetRow.index
        variant: "caption"
        theme: dialog.theme
        visible: targetLevel.text !== ""
        text: dialog.targetLevelWord(targetRow.modelData)
      }

      UI.ThemedText {
        objectName: "dispatchTargetTitle" + targetRow.index
        theme: dialog.theme
        width: Math.max(0, targetLine.width
          - (targetLevel.visible ? targetLevel.width + targetLine.spacing : 0)
          - (targetId.visible ? targetId.width + targetLine.spacing : 0))
        text: dialog.targetTitleOf(targetRow.modelData)
        color: dialog.foregroundColor
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: targetId
        objectName: "dispatchTargetId" + targetRow.index
        variant: "caption"
        theme: dialog.theme
        visible: targetId.text !== ""
        text: dialog.targetShortId(targetRow.modelData)
      }
    }
  }
}
