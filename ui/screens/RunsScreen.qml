import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components/runControlFacts.js" as ControlFacts
import "../components" as UI
import "../theme" as T

// The Runs section: the selected project's am runs, one row each (state glyph,
// short id, title, done/total, current phase, age), with Needs attention /
// Live / Parked / All chips -- clicking the active chip means All again -- and
// a footer that says whether the runs are watched. It reads the run store and
// asks the navigator to open a run or move the cursor; it owns no state of its
// own. Ages are read against the clock once per snapshot: there is no timer.
Column {
  id: screen
  objectName: "runsView"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; a row that takes the cursor asks for it here.
  signal revealRequested(var item)
  // A run's Cancel was clicked. Cancelling needs a typed confirmation, which is
  // the owner's to ask for; nothing here cancels a run.
  signal cancelRequested(string runId)

  // Re-read whenever the list changes, i.e. with every snapshot.
  readonly property real nowMs: screen.app.runs.filteredRuns ? Date.now() : 0
  readonly property bool amMissing: screen.app.runs.amStatus === "missing"
  readonly property var counts: Runs.runFilterCounts(screen.app.runs.runs)

  visible: screen.app.nav.viewMode === "runs" && !!screen.app.projects.selectedProject
  spacing: Style.space(6)

  // A chip's wording, also used by the "No <chip> runs." line.
  function chipLabel(id) {
    return id === "attention" ? "Needs attention" : id === "live" ? "Live" : id === "parked" ? "Parked" : "All"
  }

  // A dead or parked run's state, spelled out with its age folded in so the
  // age shows once; "" for every other state.
  function stateText(state, age) {
    if (state === "dead")
      return age === "" ? "dead - lease lost" : age === "just now" ? "dead - lease lost just now" : "dead - lease lost " + age + " ago"
    if (state === "parked") return age === "" ? "parked" : "parked " + age
    return ""
  }

  // A row's control button: pause and resume go straight to the store, a
  // cancel only asks (cancelRequested).
  function requestControl(action, run) {
    var id = ControlFacts.runIdOf(run)
    if (id === "") return
    if (action === "cancel") screen.cancelRequested(id)
    else screen.app.runs.control(action, id)
  }

  UI.ThemedText {
    objectName: "runsSchemaBanner"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.amStatus === "schema"
    text: screen.app.runs.watchSchemaError !== "" ? screen.app.runs.watchSchemaError : screen.app.runs.lastError
    color: screen.theme.urgent
    wrapMode: Text.WordWrap
  }

  UI.ThemedText {
    objectName: "runsStaleBanner"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.stale
    text: "Run data is out of date"
    color: screen.theme.urgent
  }

  UI.ThemedText {
    objectName: "runsWarning"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.watchWarning !== ""
    text: screen.app.runs.watchWarning
    elide: Text.ElideRight
  }

  UI.FilterableList {
    width: parent.width
    theme: screen.theme

    chipsObjectName: "runChips"
    chipPrefix: "runChip"
    statusObjectName: "runsMessage"
    chips: ["attention", "live", "parked", "all"].map(function(id) {
      var chip = { id: id, label: screen.chipLabel(id), tint: screen.theme.dim }
      if (id !== "all") chip.count = screen.counts[id]
      return chip
    })
    activeChip: screen.app.runs.runFilter === "" ? "all" : screen.app.runs.runFilter
    onChipToggled: function(id) { screen.app.runs.toggleRunFilter(id) }

    error: screen.amMissing ? "am is not installed or not on PATH" : ""
    empty: screen.app.runs.filteredRuns.length === 0
    filtered: screen.app.nav.searchQuery !== "" || screen.app.runs.runFilter !== ""
    filteredText: screen.app.nav.searchQuery !== ""
      ? "No runs match “" + screen.app.nav.searchQuery + "”."
      : "No " + screen.chipLabel(screen.app.runs.runFilter) + " runs."
    emptyText: "No runs for this project yet."

    model: screen.app.runs.filteredRuns
    rowDelegate: Component { RunRow {} }
  }

  UI.ThemedText {
    objectName: "runsFooter"
    variant: "caption"
    theme: screen.theme
    width: parent.width
    visible: !screen.amMissing && screen.app.runs.amStatus !== "schema"
    text: screen.app.runs.amStatus === "error" && screen.app.runs.lastError !== ""
      ? screen.app.runs.lastError
      : "am · schema 1 · " + (screen.app.runs.watching ? "watching" : "not watching")
    wrapMode: Text.WordWrap
  }

  component RunRow: UI.ListRow {
    id: row
    required property var modelData
    required index
    objectName: "runRow" + row.index

    // The run is read back out of the store's list by position, NOT taken from
    // `modelData`: a Repeater hands the delegate a converted copy whose nested
    // arrays are no longer JS arrays (Array.isArray is false), so the domain
    // helpers that read `tree.subtasks` and `rows` would see an empty run and
    // the progress, phase and escalation reason would silently vanish.
    readonly property var run: screen.app.runs.filteredRuns[row.index]

    readonly property string runState: Runs.runState(row.run)
    readonly property var runProgress: Runs.runProgress(row.run)
    readonly property string runAge: Runs.runAgeText(row.run, screen.nowMs)

    width: screen.width
    theme: screen.theme
    opacity: screen.app.runs.stale ? 0.5 : 1
    cursorIndex: screen.app.nav.cursorIndex
    scrollOnCursor: screen.app.nav.scrollOnCursor
    onHovered: function(index) { screen.navigator.hoverCursor(index) }
    onActivated: screen.navigator.openRun(row.run ? row.run.id : "")
    onRevealRequested: function(item) { screen.revealRequested(item) }

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        id: rowGlyph
        objectName: "runRowGlyph" + row.index
        theme: screen.theme
        visible: text !== ""
        text: RunGlyphs.glyphOf(row.runState)
        color: row.runState === "escalated" || row.runState === "dead" ? screen.theme.urgent : screen.theme.foreground
      }

      UI.ThemedText {
        id: rowId
        objectName: "runRowId" + row.index
        variant: "caption"
        theme: screen.theme
        text: Runs.shortId(row.run)
      }

      UI.ThemedText {
        objectName: "runRowTitle" + row.index
        theme: screen.theme
        width: Math.max(0, parent.width - (rowGlyph.visible ? rowGlyph.width + parent.spacing : 0)
          - rowId.width - parent.spacing)
        text: Runs.runTitle(row.run)
        elide: Text.ElideRight
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      UI.ThemedText {
        objectName: "runRowProgress" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: row.runProgress.total > 0 ? row.runProgress.done + "/" + row.runProgress.total : ""
      }

      UI.ThemedText {
        objectName: "runRowPhase" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: Runs.currentPhase(row.run)
      }

      UI.ThemedText {
        objectName: "runRowAge" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: row.runState === "dead" || row.runState === "parked" ? "" : row.runAge
      }

      UI.ThemedText {
        objectName: "runRowState" + row.index
        variant: "caption"
        theme: screen.theme
        visible: text !== ""
        text: screen.stateText(row.runState, row.runAge)
        color: row.runState === "dead" ? screen.theme.urgent : screen.theme.dim
      }
    }

    UI.ThemedText {
      objectName: "runRowReason" + row.index
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: row.runState === "escalated"
      text: Runs.escalationReason(row.run)
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }

    // Under the row: the buttons while it has the cursor (hover moves the
    // cursor, so that is hover or selected) or a request is pending, and the
    // waiting and error lines whenever they apply.
    actions: [
      UI.RunControls {
        objectName: "runRowControls" + row.index
        width: parent.width
        theme: screen.theme
        run: row.run
        pendingAction: ControlFacts.pendingOf(screen.app.runs.pending, row.run)
        waiting: ControlFacts.waitingOf(screen.app.runs.stillWaiting, row.run)
        waitingText: screen.app.runs.stillWaitingText
        errorText: ControlFacts.errorOf(screen.app.runs.lastControlError, screen.app.runs.lastControlErrorRunId, row.run)
        wholeRun: false
        showButtons: row.hasCursor
        onActionRequested: function(action) { screen.requestControl(action, row.run) }
      }
    ]
  }
}
