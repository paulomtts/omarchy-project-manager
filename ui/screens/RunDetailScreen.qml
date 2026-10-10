import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T

// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; for a stopped run, Why it stopped
// (StopReasonBlock: Runs.stopReport, am's note from the open project's
// comments, Open card and Relaunch); its story > subtask > phase > attempt
// tree (a step row reads its phase and selects the step), with the
// orchestrator's own Integrate / Bases / Base rows when it has them; and a
// bottom area of two tabs, app.runs.detailTab, chosen by the Output / Events
// chips. Output shows ONE selected attempt or step. While app.runOutput's
// followStatus is connecting, following, ended or error it is live:
// app.runOutput's text in a TailScroll under a live / ended label, closed by
// an end line once ended, and no Refresh. Otherwise (idle, unsupported, or no
// app.runOutput) it is the selection's `am logs` snapshot labelled with its
// age, with Refresh. Events is the run's event timeline (EventsPane over
// app.runs.events); its filter chips set app.runs.eventsFilter, and a row
// naming an attempt selects that attempt and shows Output. The Events chip
// counts the rows held plus app.runs.eventsDropped. Run state always comes
// from am (the run store), never from a brd status; brd's board only lends
// titles, dims the cards it has closed and holds the card Relaunch opens. It
// reads the run store, app.runControl and app.runOutput, asks the run store
// to show another attempt or tab or fetch again, run control to pause or
// resume and the dispatch (app.runDispatch) to open a relaunch; it owns no
// state of its own. A run outside the open project shows no note, and its Open card
// and Relaunch are disabled with the reason. Ages are read against the clock
// when a logs reply lands or a snapshot replaces the runs: no timer.
Column {
  id: screen
  objectName: "runDetailView"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; Panel wires this like every other screen's.
  signal revealRequested(var item)
  // The run's Cancel was clicked. Cancelling needs a typed confirmation, which
  // is the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)

  readonly property var run: screen.runById(screen.app.runs.runs, screen.app.runs.selectedRunId)
  readonly property var tree: Runs.runTree(screen.run)
  readonly property string runState: Runs.runState(screen.run)
  readonly property var selection: screen.app.runs.selectedAttempt
  // Re-read whenever a logs reply lands or a snapshot replaces the runs.
  readonly property real nowMs: screen.app.runs.logsFetchedMs >= 0 && screen.app.runs.runs ? Date.now() : 0
  readonly property var stopReport: Runs.stopReport(screen.run)
  readonly property bool inOpenProject: screen.belongsTo(screen.run, screen.app.runs.project)
  readonly property var stopNoteFound: screen.noteOf(screen.run, screen.stopReport, screen.inOpenProject)
  readonly property var stopNote: screen.stopNoteFound.note
  readonly property string stopNoteCardId: screen.stopNoteFound.cardId
  // The rows the store holds; 0 when `events` is not an array.
  readonly property int eventsHeld: Array.isArray(screen.app.runs.events) ? screen.app.runs.events.length : 0
  // app.runOutput, or null when the app has none.
  readonly property var ro: screen.app.runOutput || null
  // ro's followStatus; "idle" without ro or for anything it does not name.
  readonly property string followStatus: {
    var f = screen.ro ? screen.ro.followStatus : "idle"
    return ["connecting", "following", "ended", "error", "unsupported"].indexOf(f) >= 0 ? f : "idle"
  }
  // The pane presents ro (live mode) rather than the snapshot.
  readonly property bool live: ["connecting", "following", "ended", "error"].indexOf(screen.followStatus) >= 0

  visible: screen.app.nav.viewMode === "run"
  spacing: Style.space(6)

  function runById(list, id) {
    if (!list || typeof id !== "string" || id === "") return null
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }

  // "Milestone M3 · prefix m3 · base master · lease pid 4121 live"; empty parts
  // are left out, and a run without a lease says so.
  function metaText(run) {
    if (!run) return ""
    var parts = []
    if (typeof run.milestone_id === "string" && run.milestone_id !== "") parts.push("Milestone " + run.milestone_id)
    if (typeof run.branch_prefix === "string" && run.branch_prefix !== "") parts.push("prefix " + run.branch_prefix)
    if (typeof run.base_branch === "string" && run.base_branch !== "") parts.push("base " + run.base_branch)
    var lease = run.lease
    if (lease !== null && typeof lease === "object") {
      var pid = lease.pid === undefined || lease.pid === null || lease.pid === "" ? "" : " pid " + lease.pid
      parts.push("lease" + pid + (lease.live === true ? " live" : " not live"))
    } else {
      parts.push("no lease")
    }
    return parts.join(" · ")
  }

  // The brd card behind an id, or null. Own keys only, so "__proto__" is no card.
  function cardOf(id) {
    var map = screen.app.board ? screen.app.board.cardMap : null
    if (!map || typeof id !== "string" || id === "") return null
    return Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }

  function titleOf(id) {
    var card = screen.cardOf(id)
    return card && typeof card.title === "string" ? card.title : ""
  }

  // brd has closed this card: it is listed dimmed, never hidden.
  function isClosed(id) {
    var card = screen.cardOf(id)
    return !!card && Board.isClosedStatus(card.status)
  }

  function glyphOf(status) { return RunGlyphs.glyphOf(Runs.glyphStateOf(status)) }

  function isUrgent(status) {
    var s = Runs.glyphStateOf(status)
    return s === "escalated" || s === "dead"
  }

  // "<glyph> <id> <title> · <status>", each part only when it has something.
  function cardLine(id, status) {
    var parts = []
    var glyph = screen.glyphOf(status)
    if (glyph !== "") parts.push(glyph)
    parts.push(id)
    var title = screen.titleOf(id)
    if (title !== "") parts.push(title)
    var line = parts.join(" ")
    return status !== "" ? line + " · " + status : line
  }

  function phaseText(subtask) {
    if (subtask.currentPhase === "") return ""
    return subtask.currentAttempt > 0 ? subtask.currentPhase + "." + subtask.currentAttempt : subtask.currentPhase
  }

  // "<glyph> <phase>.<n> <status>"; a step reads its phase alone, an
  // unnumbered attempt "<phase>.?".
  function attemptText(a) {
    var glyph = screen.glyphOf(a.status)
    var label = a.step === true ? a.phase : a.phase + "." + (a.attempt > 0 ? a.attempt : "?")
    return (glyph !== "" ? glyph + " " : "") + label + (a.status !== "" ? " " + a.status : "")
  }

  function syntheticText(entry) {
    var glyph = screen.glyphOf(entry.status)
    return (glyph !== "" ? glyph + " " : "") + entry.label + " " + (entry.status !== "" ? entry.status : "not started")
  }

  // A step row is selected by a step selection of its card and phase; an
  // attempt row by an attempt selection of its card, phase and number.
  function isSelected(cardId, phase, attempt, step) {
    var s = screen.selection
    if (!s || s.card_id !== cardId || s.phase !== phase) return false
    return step === true ? s.step === true : s.step !== true && s.attempt === attempt
  }

  // The snapshot's label: its age (and "last 200 lines" when cut),
  // "loading…" before the first reply, "" otherwise or with no selection.
  function outputAge() {
    var store = screen.app.runs
    if (!screen.selection) return ""
    if (store.logsFetchedMs > 0) {
      var age = Runs.snapshotAgeText(store.logsFetchedMs, screen.nowMs)
      var line = age !== "" ? "snapshot " + age + " ago" : "snapshot"
      return store.logsTruncated ? line + " · last 200 lines" : line
    }
    return store.logsLoading ? "loading…" : ""
  }

  // A string field of ro; "" without ro or when it is not a string.
  function roText(key) {
    var v = screen.ro ? screen.ro[key] : ""
    return typeof v === "string" ? v : ""
  }

  // The end statuses drawn urgent, with the escalated glyph.
  function endIsUrgent(end) {
    return end === "gate_failed" || end === "schema_invalid" || end === "harness_error"
  }

  // The pane's status line: live or waiting, ended with its status (or ro's
  // sentence for an end without one), the unsupported sentence before the
  // snapshot's label, or the snapshot's label. "" with no selection and for a
  // follow error, which runOutputError states.
  function statusLabel() {
    if (!screen.selection) return ""
    var f = screen.followStatus
    var running = RunGlyphs.glyphOf("running")
    if (f === "connecting" || (f === "following" && screen.ro.hasOutput !== true)) return running + " live · waiting for output"
    if (f === "following") return running + " live"
    if (f === "error") return ""
    if (f === "ended") {
      var end = screen.roText("endStatus")
      if (end === "") return screen.roText("followError")
      return (screen.endIsUrgent(end) ? RunGlyphs.glyphOf("escalated") + " " : "") + "ended · " + end
    }
    var age = screen.outputAge()
    if (f !== "unsupported") return age
    var sentence = screen.roText("followError")
    return sentence !== "" && age !== "" ? sentence + " · " + age : sentence + age
  }

  // The status line is drawn urgent: an ended attempt with an urgent status.
  function statusUrgent() {
    return !!screen.selection && screen.followStatus === "ended" && screen.endIsUrgent(screen.roText("endStatus"))
  }

  // The live list's rows: the source text's lines (an ended step's landed
  // snapshot, else ro's liveText; no trailing empty row), then the end line
  // once ro has ended with a status. [] with no selection or outside live mode.
  function liveRows() {
    if (!screen.selection || !screen.live) return []
    var store = screen.app.runs
    var ended = screen.followStatus === "ended"
    var source = ended && screen.selection.step === true && store.logsFetchedMs > 0
      ? store.logsText : screen.roText("liveText")
    var rows = typeof source === "string" && source !== "" ? source.split("\n") : []
    if (rows.length > 0 && rows[rows.length - 1] === "") rows.pop()
    var end = screen.roText("endStatus")
    if (ended && end !== "") rows.push("— ended: " + end + " —")
    return rows
  }

  // Safe reads by position: a Repeater may still bind a delegate once while
  // the tree it came from shrinks under it.
  function storyAt(i) {
    return screen.tree.stories[i] || ({ card_id: "", label: "", status: "", other: false, subtasks: [] })
  }
  function subtaskAt(i, j) {
    return screen.storyAt(i).subtasks[j] || ({ card_id: "", status: "", phases: [], attempts: [], currentPhase: "", currentAttempt: 0 })
  }
  function attemptAt(subtask, k) {
    return subtask.attempts[k] || ({ phase: "", attempt: 0, status: "" })
  }
  function syntheticAt(k) {
    return screen.tree.synthetic[k] || ({ id: "", label: "", status: "" })
  }

  // A control button: pause and resume go straight to the store, a cancel
  // only asks (cancelRequested).
  function requestControl(action) {
    var id = ControlFacts.runIdOf(screen.run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else screen.app.runControl.control(action, id)
  }

  // The run is in the open project: both roots are non-empty and equal, the
  // open one with trailing "/" removed as runs are tagged.
  function belongsTo(run, openRoot) {
    if (typeof openRoot !== "string" || openRoot === "") return false
    if (!run || run.project === null || typeof run.project !== "object") return false
    var root = run.project.root
    return typeof root === "string" && root !== "" && root === Runs.withProject({}, openRoot, "").project.root
  }

  // am's note on the stopped run, {note, cardId}: from the report's card, else
  // from the milestone card; {null, ""} outside the open project or without
  // an extras store.
  function noteOf(run, report, inProject) {
    var none = { note: null, cardId: "" }
    var extras = screen.app.extras
    if (!inProject || !extras || !report || !run) return none
    if (report.cardId !== "") {
      var onCard = Runs.stopComment(extras.commentsFor(report.cardId), run.id)
      if (onCard !== null) return { note: onCard, cardId: report.cardId }
    }
    if (typeof run.milestone_id === "string" && run.milestone_id !== "") {
      var onMilestone = Runs.stopComment(extras.commentsFor(run.milestone_id), run.id)
      if (onMilestone !== null) return { note: onMilestone, cardId: run.milestone_id }
    }
    return none
  }

  // A dead run's last heartbeat age without "ago"; "" otherwise or unparseable.
  function heartbeatAgeOf(report) {
    if (!report || report.state !== "dead") return ""
    return Runs.snapshotAgeText(Date.parse(report.heartbeatAt), screen.nowMs)
  }

  // Relaunch shows for a run with a relaunch target that cannot be resumed,
  // or whose last resume am refused with a type relaunching answers.
  function offersRelaunch(run, report) {
    if (!report || report.relaunch === null || typeof report.relaunch !== "object") return false
    if (!Runs.controls(run).resume.enabled) return true
    var control = screen.app.runControl
    return control.lastControlErrorRunId === run.id && Runs.offersRelaunch({ type: control.lastControlErrorType })
  }

  // Opens the dispatch on the relaunch target's card; a card no longer on the
  // board opens nothing and flashes why.
  function relaunch() {
    var report = screen.stopReport
    if (!report || report.relaunch === null || typeof report.relaunch !== "object") return
    var card = screen.cardOf(report.relaunch.cardId)
    if (card === null) {
      screen.app.runControl.flash("The card to relaunch is no longer on the board")
      return
    }
    screen.app.runDispatch.relaunchOpenFor(card, screen.app.board.cardMap, report.relaunch)
  }

  UI.ListStatus {
    objectName: "runDetailMissing"
    theme: screen.theme
    width: parent.width
    empty: !screen.run
    emptyText: "This run is no longer in the snapshot"
  }

  Column {
    objectName: "runDetailBody"
    width: parent.width
    spacing: Style.space(6)
    visible: !!screen.run

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "runDetailTitle"
        variant: "heading"
        theme: screen.theme
        text: "Run " + Runs.shortId(screen.run)
      }

      UI.ThemedText {
        objectName: "runDetailState"
        variant: "heading"
        theme: screen.theme
        text: (RunGlyphs.glyphOf(screen.runState) !== "" ? RunGlyphs.glyphOf(screen.runState) + " " : "") + screen.runState
        color: screen.runState === "escalated" || screen.runState === "dead" ? screen.theme.urgent : screen.theme.foreground
      }
    }

    UI.ThemedText {
      objectName: "runDetailMeta"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: text !== ""
      text: screen.metaText(screen.run)
      wrapMode: Text.WordWrap
    }

    UI.StopReasonBlock {
      objectName: "runDetailStop"
      width: parent.width
      theme: screen.theme
      report: screen.stopReport
      note: screen.stopNote
      heartbeatAge: screen.heartbeatAgeOf(screen.stopReport)
      openCardId: screen.stopReport && screen.stopReport.cardId !== "" ? screen.stopReport.cardId : screen.stopNoteCardId
      openCardReason: screen.inOpenProject ? "" : "Open this run's project to open its card"
      relaunchOffered: screen.offersRelaunch(screen.run, screen.stopReport)
      relaunchReason: screen.inOpenProject ? "" : "Open this run's project to relaunch it"
      onOpenCardRequested: function(id) { if (screen.navigator) screen.navigator.openCard(id) }
      onRelaunchRequested: screen.relaunch()
    }

    UI.RunControls {
      objectName: "runDetailControls"
      width: parent.width
      theme: screen.theme
      run: screen.run
      pendingAction: ControlFacts.pendingOf(screen.app.runControl.pending, screen.run)
      waiting: ControlFacts.waitingOf(screen.app.runControl.stillWaiting, screen.run)
      waitingText: screen.app.runControl.stillWaitingText
      errorText: ControlFacts.errorOf(screen.app.runControl.lastControlError, screen.app.runControl.lastControlErrorRunId, screen.run)
      wholeRun: false
      showButtons: true
      onActionRequested: function(action) { screen.requestControl(action) }
    }

    Repeater {
      model: screen.tree.stories.length
      delegate: StoryBlock {}
    }

    Repeater {
      model: screen.tree.synthetic.length
      delegate: SyntheticRow {}
    }

    UI.ChipRow {
      objectName: "runTabs"
      width: parent.width
      theme: screen.theme
      chipPrefix: "runTab"
      active: screen.app.runs.detailTab
      model: [{ id: "output", label: "Output" },
              { id: "events", label: "Events", count: screen.eventsHeld + screen.app.runs.eventsDropped }]
      onChosen: function(id) { screen.app.runs.setDetailTab(id) }
    }

    Column {
      objectName: "runOutputPane"
      width: parent.width
      spacing: Style.space(4)
      visible: screen.app.runs.detailTab === "output"

      Row {
        width: parent.width
        spacing: Style.space(10)

        UI.ThemedText {
          id: outputHeading
          objectName: "runOutputHeading"
          theme: screen.theme
          text: !screen.selection ? "Output"
            : screen.selection.step === true
              ? "Output · " + screen.selection.card_id + " " + screen.selection.phase
            : screen.selection.attempt > 0
              ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
              : "Output · " + screen.selection.card_id + " " + screen.selection.phase + " (newest)"
        }

        UI.ThemedText {
          objectName: "runOutputAge"
          variant: "caption"
          theme: screen.theme
          // Wraps within the room the heading and Refresh leave, so Refresh stays on screen.
          width: Math.min(implicitWidth, Math.max(Style.space(80), parent.width - outputHeading.width - outputRefresh.width - 2 * parent.spacing))
          wrapMode: Text.WordWrap
          visible: text !== ""
          text: screen.statusLabel()
          color: screen.statusUrgent() ? screen.theme.urgent : screen.theme.dim
        }

        UI.ActionButton {
          id: outputRefresh
          objectName: "runOutputRefresh"
          theme: screen.theme
          visible: !!screen.selection && !screen.live
          text: "Refresh"
          tooltipText: "Fetch this attempt's output again"
          onClicked: screen.app.runs.refreshLogs()
        }
      }

      UI.ThemedText {
        objectName: "runOutputNone"
        variant: "dim"
        theme: screen.theme
        visible: !screen.selection
        text: "No attempt selected"
      }

      // The snapshot's fetch error, or in live mode the follow's error.
      UI.ThemedText {
        objectName: "runOutputError"
        variant: "caption"
        theme: screen.theme
        width: parent.width
        visible: text !== ""
        text: !screen.selection ? ""
          : !screen.live ? screen.app.runs.logsError
          : screen.followStatus === "error" ? screen.roText("followError") : ""
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }

      // The snapshot's neutral note (a step that records no output), never urgent.
      UI.ThemedText {
        objectName: "runOutputNote"
        variant: "dim"
        theme: screen.theme
        width: parent.width
        visible: text !== ""
        text: !!screen.selection && !screen.live && typeof screen.app.runs.logsNote === "string" ? screen.app.runs.logsNote : ""
        wrapMode: Text.WordWrap
      }

      // The snapshot. Read-only by nature: a Text, in the theme's font, never an editor.
      UI.ThemedText {
        objectName: "runOutputText"
        variant: "small"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && !screen.live && text !== ""
        text: screen.app.runs.logsText
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
      }

      // Live mode's text, one row per line, following its bottom; outside
      // live mode it has no rows and takes no room.
      UI.TailScroll {
        objectName: "runOutputTail"
        width: parent.width
        theme: screen.theme
        model: screen.liveRows()
        listName: "runOutputList"
        jumpName: "runOutputJump"

        rowDelegate: UI.ThemedText {
          id: outputRow
          required property var modelData
          required property int index

          objectName: "runOutputRow" + outputRow.index
          width: outputRow.ListView.view ? outputRow.ListView.view.width : 0
          variant: "small"
          theme: screen.theme
          text: outputRow.modelData
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
        }
      }
    }

    UI.EventsPane {
      width: parent.width
      visible: screen.app.runs.detailTab === "events"
      theme: screen.theme
      rows: screen.app.runs.events
      filter: screen.app.runs.eventsFilter
      dropped: screen.app.runs.eventsDropped
      status: screen.app.runs.eventsStatus
      errorMessage: screen.app.runs.eventsError
      onFilterRequested: function(f) { screen.app.runs.eventsFilter = f }
      onAttemptRequested: function(card, phase, attempt) {
        screen.app.runs.selectAttempt(card, phase, attempt)
        screen.app.runs.setDetailTab("output")
      }
    }

    // Why the last run key was refused, while that flash lasts.
    UI.ThemedText {
      objectName: "runDetailFlash"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: text !== ""
      text: screen.app.runControl.flashText
      wrapMode: Text.WordWrap
    }
  }

  component StoryBlock: Column {
    id: storyBlock
    required property int index
    readonly property var story: screen.storyAt(storyBlock.index)

    width: screen.width
    spacing: Style.space(2)

    UI.ThemedText {
      objectName: "runStory" + storyBlock.index
      theme: screen.theme
      width: parent.width
      opacity: !storyBlock.story.other && screen.isClosed(storyBlock.story.card_id) ? 0.5 : 1
      text: storyBlock.story.other ? storyBlock.story.label : screen.cardLine(storyBlock.story.card_id, storyBlock.story.status)
      color: screen.isUrgent(storyBlock.story.status) ? screen.theme.urgent : screen.theme.foreground
      elide: Text.ElideRight
    }

    Repeater {
      model: storyBlock.story.subtasks.length
      delegate: SubtaskBlock { storyIndex: storyBlock.index }
    }
  }

  component SubtaskBlock: Column {
    id: subBlock
    required property int index
    property int storyIndex: -1
    readonly property var subtask: screen.subtaskAt(subBlock.storyIndex, subBlock.index)
    readonly property bool expanded: !!screen.selection && screen.selection.card_id === subBlock.subtask.card_id
    readonly property string key: subBlock.storyIndex + "_" + subBlock.index

    width: screen.width
    spacing: Style.space(2)

    UI.ListRow {
      objectName: "runSubtask" + subBlock.key
      width: parent.width
      theme: screen.theme
      contentMargin: Style.space(22)
      opacity: screen.isClosed(subBlock.subtask.card_id) ? 0.5 : 1
      onActivated: {
        if (subBlock.subtask.currentAttempt > 0)
          screen.app.runs.selectAttempt(subBlock.subtask.card_id, subBlock.subtask.currentPhase, subBlock.subtask.currentAttempt)
      }

      UI.ThemedText {
        objectName: "runSubtaskLabel" + subBlock.key
        theme: screen.theme
        width: parent.width
        text: {
          var line = screen.cardLine(subBlock.subtask.card_id, subBlock.subtask.status)
          var phase = screen.phaseText(subBlock.subtask)
          return phase !== "" ? line + " · " + phase : line
        }
        color: screen.isUrgent(subBlock.subtask.status) ? screen.theme.urgent : screen.theme.foreground
        elide: Text.ElideRight
      }
    }

    UI.PhaseTimeline {
      objectName: "runTimeline" + subBlock.key
      x: Style.space(32)
      theme: screen.theme
      visible: subBlock.expanded && text !== ""
      phases: subBlock.subtask.phases
    }

    Repeater {
      model: subBlock.expanded ? subBlock.subtask.attempts.length : 0
      delegate: AttemptRow { storyIndex: subBlock.storyIndex; subtaskIndex: subBlock.index }
    }
  }

  component AttemptRow: UI.ListRow {
    id: attemptRow
    required index
    property int storyIndex: -1
    property int subtaskIndex: -1
    readonly property var subtask: screen.subtaskAt(attemptRow.storyIndex, attemptRow.subtaskIndex)
    readonly property var attempt: screen.attemptAt(attemptRow.subtask, attemptRow.index)
    readonly property bool isStep: attemptRow.attempt.step === true
    readonly property bool selected: screen.isSelected(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt, attemptRow.isStep)
    readonly property string key: attemptRow.storyIndex + "_" + attemptRow.subtaskIndex + "_" + attemptRow.index

    objectName: "runAttempt" + attemptRow.key
    width: screen.width
    theme: screen.theme
    contentMargin: Style.space(32)
    hoverCursorShape: attemptRow.isStep || attemptRow.attempt.attempt > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onActivated: {
      if (attemptRow.isStep)
        screen.app.runs.selectAttempt(attemptRow.subtask.card_id, attemptRow.attempt.phase, 0, true)
      else if (attemptRow.attempt.attempt > 0)
        screen.app.runs.selectAttempt(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    }

    UI.ThemedText {
      objectName: "runAttemptLabel" + attemptRow.key
      theme: screen.theme
      text: (attemptRow.selected ? "› " : "  ") + screen.attemptText(attemptRow.attempt)
      font.bold: attemptRow.selected
      color: screen.isUrgent(attemptRow.attempt.status) ? screen.theme.urgent : screen.theme.foreground
    }
  }

  component SyntheticRow: UI.ThemedText {
    id: synthRow
    required property int index
    readonly property var entry: screen.syntheticAt(synthRow.index)

    objectName: "runSynthetic" + synthRow.index
    theme: screen.theme
    width: screen.width
    text: screen.syntheticText(synthRow.entry)
    color: screen.isUrgent(synthRow.entry.status) ? screen.theme.urgent : screen.theme.foreground
  }
}
