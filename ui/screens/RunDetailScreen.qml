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
// tree, with the orchestrator's own Integrate / Bases / Base rows when it has
// them; and an output pane holding ONE attempt's `am logs` snapshot --
// labelled with its age, never presented as a live tail. Run state always
// comes from am (the run store), never from a brd status; brd's board only
// lends titles, dims the cards it has closed and holds the card Relaunch
// opens. It reads the run store and asks it to show another attempt, fetch
// again or open a relaunch; it owns no state of its own. A run outside the
// open project shows no note, and its Open card and Relaunch are disabled with
// the reason. Ages are read against the clock when a logs reply lands or a
// snapshot replaces the runs: no timer.
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

  function attemptText(a) {
    var glyph = screen.glyphOf(a.status)
    var label = a.phase + "." + (a.attempt > 0 ? a.attempt : "?")
    return (glyph !== "" ? glyph + " " : "") + label + (a.status !== "" ? " " + a.status : "")
  }

  function syntheticText(entry) {
    var glyph = screen.glyphOf(entry.status)
    return (glyph !== "" ? glyph + " " : "") + entry.label + " " + (entry.status !== "" ? entry.status : "not started")
  }

  function isSelected(cardId, phase, attempt) {
    var s = screen.selection
    return !!s && s.card_id === cardId && s.phase === phase && s.attempt === attempt
  }

  // The pane's age line: the snapshot's age (and "last 200 lines" when cut),
  // "loading…" before the first reply, "" otherwise. Never "live".
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
    else screen.app.runs.control(action, id)
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
    var store = screen.app.runs
    return store.lastControlErrorRunId === run.id && Runs.offersRelaunch({ type: store.lastControlErrorType })
  }

  // Opens the dispatch on the relaunch target's card; a card no longer on the
  // board opens nothing and flashes why.
  function relaunch() {
    var report = screen.stopReport
    if (!report || report.relaunch === null || typeof report.relaunch !== "object") return
    var card = screen.cardOf(report.relaunch.cardId)
    if (card === null) {
      screen.app.runs.flash("The card to relaunch is no longer on the board")
      return
    }
    screen.app.runs.relaunchOpenFor(card, screen.app.board.cardMap, report.relaunch)
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
      pendingAction: ControlFacts.pendingOf(screen.app.runs.pending, screen.run)
      waiting: ControlFacts.waitingOf(screen.app.runs.stillWaiting, screen.run)
      waitingText: screen.app.runs.stillWaitingText
      errorText: ControlFacts.errorOf(screen.app.runs.lastControlError, screen.app.runs.lastControlErrorRunId, screen.run)
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

    Column {
      objectName: "runOutputPane"
      width: parent.width
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(10)

        UI.ThemedText {
          objectName: "runOutputHeading"
          theme: screen.theme
          text: !screen.selection ? "Output"
            : screen.selection.attempt > 0
              ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
              : "Output · " + screen.selection.card_id + " " + screen.selection.phase + " (newest)"
        }

        UI.ThemedText {
          objectName: "runOutputAge"
          variant: "caption"
          theme: screen.theme
          visible: text !== ""
          text: screen.outputAge()
        }

        UI.ActionButton {
          objectName: "runOutputRefresh"
          theme: screen.theme
          visible: !!screen.selection
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

      UI.ThemedText {
        objectName: "runOutputError"
        variant: "caption"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && screen.app.runs.logsError !== ""
        text: screen.app.runs.logsError
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }

      // Read-only by nature: a Text, in the theme's font, never an editor.
      UI.ThemedText {
        objectName: "runOutputText"
        variant: "small"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && text !== ""
        text: screen.app.runs.logsText
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
      }
    }

    // Why the last run key was refused, while that flash lasts.
    UI.ThemedText {
      objectName: "runDetailFlash"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: text !== ""
      text: screen.app.runs.flashText
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
    readonly property bool selected: screen.isSelected(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    readonly property string key: attemptRow.storyIndex + "_" + attemptRow.subtaskIndex + "_" + attemptRow.index

    objectName: "runAttempt" + attemptRow.key
    width: screen.width
    theme: screen.theme
    contentMargin: Style.space(32)
    hoverCursorShape: attemptRow.attempt.attempt > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onActivated: {
      if (attemptRow.attempt.attempt > 0)
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
