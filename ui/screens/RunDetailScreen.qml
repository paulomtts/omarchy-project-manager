import QtQuick
import qs.Commons
import "../../core/domain/board.js" as Board
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T

// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; its story > subtask > phase > attempt tree, with
// the orchestrator's own Integrate / Bases / Base rows when it has them; and an
// output pane holding ONE attempt's `am logs` snapshot -- labelled with its age,
// never presented as a live tail. Run state always comes from am (the run
// store), never from a brd status. Titles come from the run's own project map
// in app.runTitles: the header reads the run's title, then its short id in
// dim; each tree card its title, else its short card id. brd's board only dims
// the cards it has closed. It reads the run store and asks it to show another
// attempt or fetch again; it owns no state of its own. Ages are read against
// the clock when a logs reply lands or a snapshot replaces the runs: no timer.
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
  // The run's project titles map (titlesOfRun); {} without app.runTitles.
  readonly property var titles: Runs.titlesOfRun(screen.run, screen.app.runTitles ? screen.app.runTitles.titlesByRoot : null)
  readonly property var selection: screen.app.runs.selectedAttempt
  // Re-read whenever a logs reply lands or a snapshot replaces the runs.
  readonly property real nowMs: screen.app.runs.logsFetchedMs >= 0 && screen.app.runs.runs ? Date.now() : 0

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

  // The brd card behind an id on the open board, or null. Own keys only, so
  // "__proto__" is no card.
  function cardOf(id) {
    var map = screen.app.board ? screen.app.board.cardMap : null
    if (!map || typeof id !== "string" || id === "") return null
    return Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }

  // The card's title in the run's map (cardTitle), else "…" and the id's last
  // 8 characters (all of a shorter one); "" for a non-string or empty id.
  function nameOf(id) {
    var title = Runs.cardTitle(id, screen.run, screen.titles)
    if (title !== "") return title
    return typeof id === "string" && id !== "" ? "…" + id.slice(-8) : ""
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

  // "<glyph> <name>", each part only when it has something.
  function leadOf(id, status) {
    var parts = []
    var glyph = screen.glyphOf(status)
    if (glyph !== "") parts.push(glyph)
    var name = screen.nameOf(id)
    if (name !== "") parts.push(name)
    return parts.join(" ")
  }

  // "<status> · <phase>", each part only when it has something.
  function tailOf(status, phase) {
    var parts = []
    if (status !== "") parts.push(status)
    if (phase !== "") parts.push(phase)
    return parts.join(" · ")
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
    else screen.app.runControl.control(action, id)
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

      // Takes the width the others leave and elides, so they stay on the row.
      UI.ThemedText {
        objectName: "runDetailTitle"
        variant: "heading"
        theme: screen.theme
        width: Math.max(0, Math.min(implicitWidth, parent.width - detailId.width - detailState.width - parent.spacing * 2))
        text: Runs.runTitle(screen.run, screen.titles)
        elide: Text.ElideRight
      }

      UI.ThemedText {
        id: detailId
        objectName: "runDetailId"
        variant: "caption"
        theme: screen.theme
        text: Runs.runSubtitle(screen.run)
        color: screen.theme.dim
      }

      UI.ThemedText {
        id: detailState
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

    UI.ThemedText {
      objectName: "runDetailReason"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: screen.runState === "escalated"
      text: Runs.escalationReason(screen.run)
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
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
          text: screen.selection
            ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
            : "Output"
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

    CardLine {
      objectName: "runStory" + storyBlock.index
      width: parent.width
      opacity: !storyBlock.story.other && screen.isClosed(storyBlock.story.card_id) ? 0.5 : 1
      lead: storyBlock.story.other ? storyBlock.story.label : screen.leadOf(storyBlock.story.card_id, storyBlock.story.status)
      tail: storyBlock.story.other ? "" : screen.tailOf(storyBlock.story.status, "")
      color: screen.isUrgent(storyBlock.story.status) ? screen.theme.urgent : screen.theme.foreground
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

      CardLine {
        objectName: "runSubtaskLabel" + subBlock.key
        width: parent.width
        lead: screen.leadOf(subBlock.subtask.card_id, subBlock.subtask.status)
        tail: screen.tailOf(subBlock.subtask.status, screen.phaseText(subBlock.subtask))
        color: screen.isUrgent(subBlock.subtask.status) ? screen.theme.urgent : screen.theme.foreground
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

  // A card's line, `text` "<lead> · <tail>" (just the one that is not ""):
  // the lead elides so the tail stays on the row.
  component CardLine: Row {
    id: cardLine
    property string lead: ""
    property string tail: ""
    property color color: screen.theme.foreground
    readonly property string text: cardLine.lead === "" || cardLine.tail === ""
      ? cardLine.lead + cardLine.tail : cardLine.lead + " · " + cardLine.tail

    spacing: Style.space(4)

    UI.ThemedText {
      objectName: cardLine.objectName + "Lead"
      theme: screen.theme
      width: Math.max(0, Math.min(implicitWidth, cardLine.width - (lineTail.visible ? lineTail.width + cardLine.spacing : 0)))
      text: cardLine.lead
      color: cardLine.color
      elide: Text.ElideRight
    }

    UI.ThemedText {
      id: lineTail
      objectName: cardLine.objectName + "Tail"
      theme: screen.theme
      visible: cardLine.tail !== ""
      text: cardLine.lead !== "" ? "· " + cardLine.tail : cardLine.tail
      color: cardLine.color
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
