import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../core/domain/board.js" as Board
import "../core/domain/milestones.js" as Milestones
import "../core/domain/runs.js" as Runs
import "../core/stores" as Core
import "components"
import "components" as UI
import "screens"
import "theme" as T

// Browses brd's local kanban board (`brd projects` / `brd tree`), per
// project: pick a project, then view its cards as a Board.
// Cards are read-only with one exception: New milestone, which adds cards by
// handing one of the project's specs to the default coding agent
// (see MilestoneStore and core/backend/milestones/).
Panel {
  id: root
  moduleName: "paulomtts.omarchy-project-manager"
  ipcTarget: "paulomtts.omarchy-project-manager"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // The one Theme in the plugin: every view and shared component draws with
  // it, so the bar's palette reaches them through a single property.
  T.Theme {
    id: panelTheme
    foreground: root.foreground
    urgent: root.urgent
    fontFamily: root.fontFamily
  }

  // The plugin ROOT, not this file's folder: every helper is addressed as
  // pluginDir + "core/backend/...", and this file lives in <plugin>/ui/, so the
  // "../" is load-bearing (tests/ui/tst_plugin_dir.qml guards it).
  readonly property string pluginDir: Qt.resolvedUrl("../").toString().replace(/^file:\/\//, "")

  // All non-visual state lives in the stores; `app` is how the tests reach it.
  Core.App { id: appStores; backendDir: root.pluginDir + "core/backend/"; panelOpen: root.opened }
  readonly property var app: appStores

  readonly property bool documentsEnabled: true

  // The stores announce what the panel still has to do itself: reload the
  // sections a project change invalidates, and put the focus where the new
  // state belongs.
  Connections {
    target: appStores.projects
    function onSelected(project) {
      root.focusForView()
    }
  }

  // A different category means a different list: the cursor reset is App's, the
  // scroll is the panel's.
  Connections {
    target: appStores.docs
    function onCategoryToggled() { Qt.callLater(root.scrollToTop) }
  }

  // The memories store asks for the navigation and focus work it does not do
  // itself: the same list/note bookkeeping the panel does everywhere else.
  Connections {
    target: appStores.memories
    function onTypeToggled() { Qt.callLater(root.scrollToTop) }
    function onNoteOpenRequested(file) { navi.openMemory(file) }
    function onListRestoreRequested() { navi.restoreMemoriesList() }
    function onFocusRequested() { root.focusForView() }
  }

  // The open card left the board (a refetch dropped it): back to the list.
  Connections {
    target: appStores.board
    function onArchiveOpenChanged() { root.focusForView() }
    function onListViewRequested() { navi.restoreListView() }
  }

  // The open issue left the export (closed and pruned, or another project):
  // back to the Issues list.
  Connections {
    target: appStores.extras
    function onListViewRequested() { navi.restoreIssuesList() }
    function onStatusToggled() { Qt.callLater(root.scrollToTop) }
  }

  // A different Runs chip means a different list: the cursor reset is App's,
  // the scroll is the panel's. The cancel confirmation and the Resume dialog
  // take the focus when they open and give it back when they close; the open
  // dispatch dialog takes it at each Runs step. A started dispatch closes its
  // dialog and goes to the run; the run is usually not in the snapshot yet,
  // so every new list may hold the run the navigator still waits for.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
    function onRunsChanged() { navi.openAwaitedRun() }
  }
  Connections {
    target: appStores.runControl
    function onCancelOpenChanged() { root.focusForView() }
    function onResumeRunIdChanged() { root.focusForView() }
  }
  Connections {
    target: appStores.runDispatch
    function onDispatchStepChanged() { if (root.dispatchOpen) root.focusForView() }
    function onDispatchStarted(runId) {
      appStores.runDispatch.closeDispatch()
      navi.openStartedRun(runId)
    }
  }

  // The dialog picks one of the project's Markdown documents, so the documents
  // listing has to exist by the time the list is drawn. The store never reaches
  // for another store: the panel does the fetching when the dialog opens, once
  // -- a listing already in hand is reused.
  Connections {
    target: appStores.milestones
    function onDialogOpenChanged() {
      if (!appStores.milestones.dialogOpen) return
      if (appStores.docs.docs.length > 0 || appStores.docs.docsLoading) return
      appStores.docs.fetchDocs()
    }
  }

  // The running job's clock: one tick a second while it runs, so the elapsed
  // time below is recomputed. Nothing else in the panel polls.
  property real milestoneNow: 0
  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: appStores.milestones.jobState === "running"
    onTriggered: root.milestoneNow = Date.now()
  }
  readonly property string milestoneElapsed: appStores.milestones.jobState === "running"
    ? Milestones.formatElapsed(Math.max(0, root.milestoneNow - appStores.milestones.jobStartedAt))
    : ""

  Connections {
    target: appStores.deleter
    function onRequested() { root.focusForView() }
    function onClosed() { root.focusForView() }
    function onDeleted() { root.focusForView() }
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  // Where the panel is and how it gets there. The navigator owns no Items: the
  // Flickable and the four UI-only effects below are all it is given.
  Navigator {
    id: navi
    app: appStores
    flick: panelFlick
    documentsEnabled: root.documentsEnabled
    actions: ({
      focusForView: root.focusForView,
      scrollToTop: root.scrollToTop,
      scrollBy: root.scrollBy,
      centerOnGraphNode: function(id) { if (graphScreen.graphView) graphScreen.graphView.centerOn(id) }
    })
  }
  readonly property var navigator: navi

  // Every key the panel reacts to. Like the navigator it owns no Items: closing
  // the panel, scrolling, switching panel, "is the caret at the end of the
  // search text?" and opening a dispatch are handed in.
  Shortcuts {
    id: sc
    app: appStores
    navigator: navi
    actions: ({
      close: function() { root.close() },
      scrollBy: root.scrollBy,
      switchPanel: function(direction) { root.switchPanel(direction) },
      searchAtEnd: function() { return searchField.cursorPosition === searchField.text.length },
      openDispatch: function(target) { root.openDispatch(target) }
    })
  }
  readonly property var shortcuts: sc

  readonly property Item focusItem: appStores.deleter.deleteTarget ? deleteModal.focusItem
    : appStores.board.archiveOpen ? archiveDialog.focusItem
    : appStores.memories.memoryDeleteOpen ? memoryConfirm.focusItem
    : appStores.memories.newMemoryOpen ? newMemoryDialog.focusItem
    : appStores.milestones.dialogOpen ? newMilestoneDialog.focusItem
    : root.dispatchOpen ? dispatchDialog.focusItem
    : appStores.runControl.cancelOpen ? runCancelModal.focusItem
    : appStores.runControl.resumeRunId !== "" ? resumeDialog.focusItem
    : (appStores.nav.viewMode === "memory" && appStores.memories.memoryEditing) ? memoryNoteScreen.editorItem
    : appStores.nav.dropdownOpen ? sidebar.filterItem
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "issue" || appStores.nav.viewMode === "run" || appStores.nav.viewMode === "graph" || (!appStores.projects.selectedProject && appStores.nav.viewMode !== "runs")) ? keyCatcher
    : searchField

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.focusItem) root.focusItem.forceActiveFocus()
    })
  }

  function scrollToTop() {
    if (panelFlick) panelFlick.contentY = 0
  }

  property var revealTarget: null

  // Held arrow keys queue many reveals before the first runs; only the newest
  // row matters, and running the stale ones scrolls to rows the cursor left.
  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    var pending = root.revealTarget !== null
    root.revealTarget = item
    if (pending) return
    Qt.callLater(function() {
      var target = root.revealTarget
      root.revealTarget = null
      if (!target || !panelFlick) return
      var margin = Style.space(6)
      var point = target.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + target.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollBy(pixels) {
    if (!panelFlick) return
    panelFlick.contentY = root.clamp(panelFlick.contentY + pixels, 0, Math.max(0, panelFlick.contentHeight - panelFlick.height))
  }

  function displayPath(path) {
    return String(path || "").replace(/^\/home\/[^\/]+/, "~")
  }

  // A toast's Open: the toast goes, then the run opens from the Runs list, so
  // Back lands there whichever view the toast was clicked on (openRun keeps
  // the cursor it is opened from). A run that has left the snapshot cannot
  // open -- openRun would refuse silently -- so the list says why instead.
  function openToastRun(key, runId) {
    appStores.runAlerts.dismissToast(key)
    navi.showSection("runs")
    if (appStores.runs.runById(runId) === null) {
      appStores.runControl.flash("This run is no longer in the snapshot")
      return
    }
    navi.openRun(runId, "runs")
  }

  // The toolbar RunIndicator's counts: Runs.runFilterCounts over every
  // registered project's runs, whatever project is open and whatever the
  // Runs list's project filter, chip or search.
  readonly property var runCounts: Runs.runFilterCounts(appStores.runs.runs)

  // A RunIndicator segment: the Runs list over every registered project (All
  // projects), on that segment's chip -- "live", "parked" or "attention". The
  // chip is set, never toggled off: a click on the active chip keeps it.
  // Nothing changes while the navigator refuses the section (a modal is open
  // or a memory draft is dirty).
  function showRunsFiltered(filter) {
    navi.showSection("runs")
    if (appStores.nav.viewMode !== "runs") return
    if (appStores.runs.projectFilter !== "") appStores.runs.toggleProjectFilter("")
    if (appStores.runs.runFilter !== filter) appStores.runs.toggleRunFilter(filter)
  }

  // ---- Dispatch (S3 4.2). The card detail's Dispatch and d on the board
  // list or a card open it on a card (openDispatch); a refused plan does not
  // say which card it was for, and the dialog needs the card's title, story
  // and blockers, so the card is kept here. Start run and d on the Runs list
  // open it at RunDispatchStore's project step (dispatchOpenFromRuns); there the card
  // is the target row picked (pickRunsTarget).
  property string dispatchCardId: ""   // the target card's id; "" for the board
  // A dispatch in any state but idle, or a Runs dispatch at any step.
  readonly property bool dispatchOpen: appStores.runDispatch.dispatchState !== "idle" || appStores.runDispatch.dispatchStep !== ""
  // The target step's heading: the name of dispatchRoot's project row, else
  // the root itself; "" with no dispatchRoot.
  readonly property string dispatchProjectName: {
    var picked = appStores.runDispatch.dispatchRoot
    if (picked === "") return ""
    var rows = appStores.runDispatch.dispatchProjectRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].root !== picked) continue
      return typeof rows[i].name === "string" && rows[i].name !== "" ? rows[i].name : picked
    }
    return picked
  }
  // The card map the dispatched card, its story, its blockers and the
  // milestone offer are read from: a Runs dispatch's picked tree
  // (dispatchTargetCardMap, {} before its read), else the open board's.
  readonly property var dispatchCardMap: appStores.runDispatch.dispatchStep !== ""
    ? (appStores.runDispatch.dispatchTargetCardMap || {}) : appStores.board.cardMap
  readonly property var dispatchCard: root.dispatchCardId !== ""
    ? (root.dispatchCardMap[root.dispatchCardId] || null) : null
  readonly property bool dispatchSubtask: !!appStores.runDispatch.dispatchTarget
    && appStores.runDispatch.dispatchTarget.level === "subtask"
  // am has no dry run for one subtask, so its story and blockers are said
  // here instead; "" for any other target, and for a card the map dropped.
  readonly property string dispatchStoryTitle: {
    if (!root.dispatchSubtask || !root.dispatchCard) return ""
    var story = root.dispatchCardMap[root.dispatchCard.parentId]
    return story ? String(story.title || "") : ""
  }
  readonly property string dispatchBlockedText: {
    if (!root.dispatchSubtask || !root.dispatchCard) return ""
    var ids = root.dispatchCard.blocked_by
    var list = ids && typeof ids.length === "number" ? Array.prototype.slice.call(ids) : []
    if (list.length === 0) return "Blocked by: nothing"
    return "Blocked by: " + list.map(function(id) { return root.blockerText(id) }).join(", ")
  }
  // A refused story's milestone, offered only while it is in the card map.
  readonly property var dispatchSuggestion: {
    var suggest = appStores.runDispatch.dispatchSuggest
    return suggest && typeof suggest.id === "string" && root.dispatchCardMap[suggest.id] ? suggest : null
  }

  // One blocker as the dialog lists it: a card of the card map with its
  // status, an issue of the open board with its state while the dispatch is
  // for the open project, anything else by its id.
  function blockerText(id) {
    var issues = appStores.runDispatch.dispatchRoot === appStores.runs.project ? appStores.board.issueMap : {}
    var resolved = Board.resolvedCard(id, root.dispatchCardMap, issues)
    if (resolved.inBoard) return "\"" + resolved.title + "\" (" + appStores.board.statusText(resolved.status) + ")"
    if (resolved.kind === "issue") return "\"" + resolved.title + "\" (" + Board.issueBlockerLabel(resolved.status) + ")"
    return id + " (not on this board)"
  }

  // The dialog takes the focus when it opens (and at each Runs step, see the
  // runDispatch Connections) and gives it back when it closes, never on a
  // re-preview, which would pull the caret out of the field being typed in.
  onDispatchOpenChanged: root.focusForView()

  // A card id or "board": the card detail's Dispatch and d on the board list
  // or a card. The store refuses a re-open while a start is in flight; the
  // card kept here must then stay the one being started.
  function openDispatch(target) {
    if (appStores.runDispatch.dispatchState === "starting") return
    var board = target === "board"
    root.dispatchCardId = board ? "" : String(target)
    appStores.runDispatch.openDispatch(board ? "board" : appStores.board.cardMap[target], appStores.board.cardMap)
  }

  // A row picked at the Runs target step: the store opens the form on it, and
  // only then is its card the dispatched one ("" for the board row).
  function pickRunsTarget(key) {
    if (!appStores.runDispatch.dispatchTargetPick(key)) return
    var rows = appStores.runDispatch.dispatchTargetRows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key !== key) continue
      var card = rows[i].card
      root.dispatchCardId = card !== null && typeof card === "object" ? String(card.id) : ""
      return
    }
  }

  onOpenedChanged: if (opened) { appStores.projects.onPanelOpened(); root.focusForView() }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { appStores.projects.refreshProjects(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🗂️"
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    objectName: "mainPanel"
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.focusItem
    // Centered under the bar rather than under the icon, and wide enough for
    // the sidebar.
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(840), 0.8 * panel.screenW))
    // At least 80% of the screen tall, whatever the section holds, so the
    // popup does not jump in size between sections; long content still scrolls.
    readonly property real minContentHeight: 0.8 * panel.screenH - panel.verticalContentInset
    contentHeight: panel.fittedContentHeight(Math.max(toolbar.implicitHeight + Style.space(12) + column.implicitHeight, sidebar.implicitHeight, minContentHeight),
      Math.max(Style.space(620), 0.8 * panel.screenH))

    // The Ctrl chords, then the run keys (p / r / c on the Runs list and Run
    // detail), then d (the dispatch: on the board list and a card for a card,
    // on the Runs list at the project step), then e (Output / Events on Run
    // detail). An accepted key is not typed into the search field.
    Item {
      id: globalKeys
      Keys.onPressed: function(event) {
        if (sc.handleGlobalKey(event) || sc.handleRunKey(event) || sc.handleDispatchKey(event)
            || sc.handleEventsKey(event)) event.accepted = true
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "keyCatcher"
      Keys.forwardTo: [globalKeys]
      anchors.fill: parent
      onCloseRequested: sc.closeRequested()
      onMoveRequested: function(dx, dy) { sc.handleMove(dx, dy) }
      onActivateRequested: sc.handleActivate()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Sidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(200)
        projects: appStores.projects.filteredProjects
        selectedProject: appStores.projects.selectedProject
        section: appStores.nav.section
        dropdownOpen: appStores.nav.dropdownOpen
        dropdownQuery: appStores.nav.dropdownQuery
        dropdownCursor: appStores.nav.dropdownCursor
        canDelete: !!appStores.projects.selectedProject && !appStores.deleter.deleting && !appStores.deleter.deleteTarget
        documentsEnabled: root.documentsEnabled
        runsAttention: Runs.attention(appStores.runs.runs).length
        theme: panelTheme
        onDropdownToggled: navi.toggleDropdown()
        onProjectChosen: function(project) { navi.chooseProject(project) }
        onQueryEdited: function(text) { appStores.nav.dropdownQuery = text; appStores.nav.dropdownCursor = 0 }
        onSectionChosen: function(name) { navi.showSection(name) }
        onDeleteRequested: appStores.deleter.openDelete(appStores.projects.selectedProject)
        onCursorHovered: function(index) { appStores.nav.dropdownCursor = index }
        onDropdownMove: function(delta) { navi.moveDropdown(delta) }
        onDropdownAccept: navi.acceptDropdown()
        onDropdownCancel: navi.closeDropdown()
        onFilterKey: function(event) { if (sc.handleGlobalKey(event)) event.accepted = true }
      }

      // Column 2 of the layout: a toolbar that never scrolls (heading, refresh,
      // search) above the content, which scrolls on its own.
      Column {
        id: toolbar
        objectName: "panelToolbar"
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: Style.space(12)

        RowLayout {
          width: parent.width
          spacing: Style.spacing.md

          // Where the panel is, and the way out of a detail view: the first
          // crumb does what "‹ Back" used to, the ones after it open ancestors.
          UI.Breadcrumbs {
            Layout.fillWidth: true
            // Whatever else the row carries, the trail keeps a readable stub
            // rather than collapsing to nothing.
            Layout.minimumWidth: Style.space(60)
            theme: panelTheme
            crumbs: navi.crumbs
            onCrumbActivated: function(index) { navi.activateCrumb(index) }
          }

          // The Graph's two views. Single select with no empty state: the store
          // refuses anything but the two, so one chip is always the active one.
          UI.ChipRow {
            objectName: "graphViewChips"
            chipPrefix: "graphViewChip"
            theme: panelTheme
            visible: appStores.nav.viewMode === "graph" && !!appStores.projects.selectedProject
            Layout.preferredWidth: implicitWidth
            model: [{ id: "milestone", label: "Milestone" }, { id: "story", label: "Story" }]
            active: appStores.graph.graphView
            // Straight to the store, like the other toolbar actions: the view
            // it picks is a different set of nodes, and the canvas frames those
            // itself (GraphView.onIdKeyChanged), so there is nothing left for
            // the navigator to centre or scroll.
            onChosen: function(id) { appStores.graph.setGraphView(id) }
          }

          // Archived cards are hidden in the Graph unless this is on.
          UI.Chip {
            objectName: "graphArchivedChip"
            theme: panelTheme
            text: "Show archived"
            visible: appStores.nav.viewMode === "graph" && !!appStores.projects.selectedProject
            active: appStores.graph.showArchived
            onClicked: appStores.graph.setShowArchived(!appStores.graph.showArchived)
          }

          // Icon-only refresh, square and as tall as the New button beside it.
          UI.ActionButton {
            objectName: "refreshButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "board" || appStores.nav.viewMode === "graph" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues"
            text: ""
            iconText: ""
            tooltipText: "Refresh"
            Layout.preferredHeight: newMemoryButton.implicitHeight
            Layout.preferredWidth: newMemoryButton.implicitHeight
            onClicked: appStores.nav.viewMode === "memories" ? appStores.memories.fetchMemories() : appStores.board.fetchBoard()
          }

          UI.ActionButton {
            id: newMemoryButton
            objectName: "newMemoryButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "memories" && appStores.memories.canCreateMemory
            text: "＋ New"
            onClicked: appStores.memories.openNewMemory()
          }

          UI.ActionButton {
            objectName: "newMilestoneButton"
            theme: panelTheme
            // The board list only, and only while this project has no job to
            // show -- the indicator below the row takes over for that.
            visible: appStores.nav.viewMode === "board" && !!appStores.projects.selectedProject
              && !appStores.milestones.jobVisible
            text: "＋ New milestone"
            tooltipText: "New milestone"
            onClicked: appStores.milestones.openDialog()
          }

          UI.ActionButton {
            objectName: "archiveFinishedButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "board" && !!appStores.projects.selectedProject
              && appStores.board.archiveCandidates.length > 0
            text: "Archive finished (" + appStores.board.archiveCandidates.length + ")"
            tooltipText: "Archive milestones whose cards are all finished"
            onClicked: appStores.board.openArchive()
          }

          // The Runs list's way to start a run: the dialog opens at its
          // project step (dispatchOpenFromRuns). Shown on the Runs list with
          // or without a project; disabled while am is missing or no usable
          // project is registered, and the tooltip says which (am first).
          UI.ActionButton {
            objectName: "startRunButton"
            theme: panelTheme
            visible: appStores.nav.viewMode === "runs"
            enabled: appStores.runs.amStatus !== "missing" && appStores.runs.usableRoots().length > 0
            iconText: "▶"
            text: "Start run"
            tooltipText: appStores.runs.amStatus === "missing" ? "am is not installed or not on PATH"
              : appStores.runs.usableRoots().length === 0 ? "No projects registered" : "Start an am run"
            onClicked: appStores.runDispatch.dispatchOpenFromRuns()
          }

          // The am run strip, last in the row, over every registered project's
          // runs (runCounts), with or without an open project and in every view;
          // it hides itself while no run is running, parked or needs attention.
          // A segment shows the Runs list on its chip (showRunsFiltered).
          UI.RunIndicator {
            objectName: "runIndicator"
            theme: panelTheme
            running: root.runCounts.live
            parked: root.runCounts.parked
            attention: root.runCounts.attention
            onFilterRequested: function(filter) { root.showRunsFiltered(filter) }
          }
        }

        // A row of its own, under the trail: the indicator is as wide as a
        // sentence and would squeeze the breadcrumbs to nothing on a narrow
        // panel. `maxTextWidth` keeps its own text inside the toolbar too.
        UI.MilestoneJobIndicator {
          width: parent.width
          maxTextWidth: toolbar.width
          theme: panelTheme
          state: appStores.milestones.jobVisible && appStores.nav.viewMode === "board"
            ? appStores.milestones.jobState : ""
          elapsed: root.milestoneElapsed
          detail: appStores.milestones.jobState === "failed" ? appStores.milestones.jobError
            : appStores.milestones.jobState === "done" && appStores.milestones.cardsCountKnown
              ? appStores.milestones.cardsCreated + (appStores.milestones.cardsCreated === 1 ? " card created" : " cards created")
              : ""
          logPath: appStores.milestones.jobState === "running" ? "" : appStores.milestones.jobLog
          onCancelRequested: appStores.milestones.cancelJob()
          onDismissRequested: appStores.milestones.dismissResult()
        }

        TextField {
          id: searchField
          objectName: "searchField"
          // The Runs list searches with or without a project; the other lists need one.
          visible: appStores.nav.viewMode === "runs" || (!!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues"))
          width: parent.width
          foreground: root.foreground
          placeholderText: appStores.nav.viewMode === "documents" ? "Search documents…" : appStores.nav.viewMode === "memories" ? "Search memories…" : appStores.nav.viewMode === "issues" ? "Search issues…" : appStores.nav.viewMode === "runs" ? "Search runs…" : "Search cards…"
          text: appStores.nav.searchQuery
          Keys.forwardTo: [globalKeys]

          onTextChanged: {
            appStores.nav.searchQuery = text
            appStores.nav.cursorIndex = 0
          }

          Keys.onPressed: function(event) { sc.handleSearchKey(event) }
        }

        // The Documents filters and the open document's path/type picker are
        // toolbar furniture, not content: they stay put while the body scrolls.
        DocumentsToolbar {
          width: parent.width
          app: appStores
          theme: panelTheme
        }

        UI.ThemedText {
          variant: "caption"
          theme: panelTheme
          visible: appStores.projects.loadError !== ""
          width: parent.width
          text: appStores.projects.loadError
          wrapMode: Text.WordWrap
        }
      }

      Flickable {
        id: panelFlick
        objectName: "panelFlick"
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: toolbar.bottom
        anchors.topMargin: toolbar.height > 0 ? Style.space(12) : 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          UI.ThemedText {
            variant: "caption"
            theme: panelTheme
            visible: !appStores.deleter.deleteTarget && appStores.deleter.lastSnapshot !== ""
            width: parent.width
            text: "Removed. Snapshot saved to " + root.displayPath(appStores.deleter.lastSnapshot)
            wrapMode: Text.WrapAnywhere
          }

          // Not on the run views: they list runs with or without a project.
          UI.ThemedText {
            objectName: "noProjectsText"
            variant: "dim"
            theme: panelTheme
            visible: !appStores.projects.selectedProject && appStores.projects.loadError === ""
              && appStores.nav.viewMode !== "runs" && appStores.nav.viewMode !== "run"
            width: parent.width
            text: "No projects registered with brd."
            wrapMode: Text.WordWrap
          }

          BoardScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          GraphScreen {
            id: graphScreen
            width: parent.width
            viewportHeight: panelFlick.height
            app: appStores
            navigator: navi
            theme: panelTheme
          }

          MemoriesScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          MemoryNoteScreen {
            id: memoryNoteScreen
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
          }

          DocumentsScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          DocumentScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
          }

          CardDetailScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
            onCancelRequested: function(runId) { appStores.runControl.openCancel(runId) }
            onDispatchRequested: function(cardId) { root.openDispatch(cardId) }
          }

          IssuesScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          IssueDetailScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          RunsScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
            onCancelRequested: function(runId) { appStores.runControl.openCancel(runId) }
          }

          RunDetailScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
            onCancelRequested: function(runId) { appStores.runControl.openCancel(runId) }
          }
        }
      }

      // The run toasts (S2 4.4), bottom right over the screens. A sibling of
      // the dialogs below, so their z: 100 outranks this z: 50: an open
      // dialog's backdrop covers the toasts and takes their clicks.
      RunToast {
        id: runToast
        objectName: "runToast"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(12)
        z: 50
        theme: panelTheme
        toasts: appStores.runAlerts.toasts
        onDismissRequested: function(key) { appStores.runAlerts.dismissToast(key) }
        onOpenRequested: function(key, runId) { root.openToastRun(key, runId) }
      }

      // Delete confirmation: the shared typed-word modal, driven by the store.
      TypedConfirmDialog {
        id: deleteModal
        objectName: "deleteModal"
        anchors.fill: parent
        backdropObjectName: "deleteBackdrop"
        cardObjectName: "deleteCard"
        fieldObjectName: "confirmField"
        shown: !!appStores.deleter.deleteTarget
        message: "Type delete to permanently remove “" + (appStores.deleter.deleteTarget ? appStores.deleter.deleteTarget.name : "")
          + "” from brd. This can't be undone, but a snapshot of its board is saved first."
        detail: appStores.deleter.deleteTarget ? root.displayPath(appStores.deleter.deleteTarget.root_path) : ""
        confirmLabel: "Confirm delete"
        busyLabel: "Deleting…"
        busy: appStores.deleter.deleting
        error: appStores.deleter.deleteError
        typedText: appStores.deleter.confirmText
        theme: panelTheme
        onTypedEdited: function(text) { appStores.deleter.confirmText = text }
        onConfirmRequested: appStores.deleter.performDelete()
        onCancelRequested: appStores.deleter.cancelDelete()
      }

      TypedConfirmDialog {
        id: memoryConfirm
        anchors.fill: parent
        shown: appStores.memories.memoryDeleteOpen
        message: "Type delete to permanently remove this memory note and its MEMORY.md entry. A backup is saved first."
        detail: appStores.memories.selectedMemory
        busy: appStores.memories.memoryBusy
        error: appStores.memories.memoryDeleteError
        theme: panelTheme
        onConfirmRequested: appStores.memories.performMemoryDelete()
        onCancelRequested: appStores.memories.cancelMemoryDelete()
      }

      // Run cancel confirmation (S2 4.3): any run surface's Cancel, or c,
      // opens it through the run store; only its confirm cancels.
      TypedConfirmDialog {
        id: runCancelModal
        objectName: "runCancelModal"
        anchors.fill: parent
        backdropObjectName: "runCancelBackdrop"
        cardObjectName: "runCancelCard"
        fieldObjectName: "runCancelField"
        shown: appStores.runControl.cancelOpen
        confirmWord: "cancel"
        message: "Cancel run " + Runs.shortId({ id: appStores.runControl.cancelRunId }) + "? Cancel is final. The run cannot be resumed, only relaunched; cards keep their current status. A phase in flight finishes first."
        detail: appStores.runs.runById(appStores.runControl.cancelRunId) ? Runs.runTitle(appStores.runs.runById(appStores.runControl.cancelRunId)) : ""
        confirmLabel: "Cancel run"
        dismissLabel: "Keep running"
        error: appStores.runControl.cancelError
        typedText: appStores.runControl.cancelText
        theme: panelTheme
        onTypedEdited: function(text) { appStores.runControl.cancelText = text }
        onConfirmRequested: appStores.runControl.confirmCancel()
        onCancelRequested: appStores.runControl.closeCancel()
      }

      // The Resume dialog: a milestone resume with no stored verify set asks
      // for the commands through run control; only its confirm resumes.
      ResumeVerifyDialog {
        id: resumeDialog
        objectName: "resumeVerifyDialog"
        anchors.fill: parent
        shown: appStores.runControl.resumeRunId !== ""
        runLabel: Runs.shortId({ id: appStores.runControl.resumeRunId })
        commands: appStores.runControl.resumeVerify
        allowNoVerification: appStores.runControl.resumeAllowNoVerification
        error: appStores.runControl.resumeError
        theme: panelTheme
        onCommandsEdited: function(commands) { appStores.runControl.resumeVerify = commands }
        onAllowNoVerificationEdited: function(on) { appStores.runControl.resumeAllowNoVerification = on }
        onConfirmRequested: appStores.runControl.resumeConfirm()
        onCancelRequested: appStores.runControl.resumeClose()
      }

      NewMemoryDialog {
        id: newMemoryDialog
        anchors.fill: parent
        shown: appStores.memories.newMemoryOpen
        busy: appStores.memories.memoryBusy
        error: appStores.memories.newMemoryError
        theme: panelTheme
        onCreateRequested: function(name, type, description, body) { appStores.memories.createMemory(name, type, description, body) }
        onCancelRequested: appStores.memories.cancelNewMemory()
      }

      ArchiveFinishedDialog {
        id: archiveDialog
        anchors.fill: parent
        shown: appStores.board.archiveOpen
        candidates: appStores.board.archiveCandidates
        busy: appStores.board.archiveBusy
        error: appStores.board.archiveError
        theme: panelTheme
        onConfirmRequested: appStores.board.archiveAll()
        onCancelRequested: appStores.board.cancelArchive()
      }

      NewMilestoneDialog {
        id: newMilestoneDialog
        anchors.fill: parent
        shown: appStores.milestones.dialogOpen
        error: appStores.milestones.dialogError
        specs: Milestones.specChoices(appStores.docs.docs)
        selectedSpec: appStores.milestones.selectedSpec
        agentName: appStores.milestones.agentInfo ? String(appStores.milestones.agentInfo.agent || "") : ""
        agentNote: appStores.milestones.agentInfo ? String(appStores.milestones.agentInfo.note || "") : ""
        agentMessage: appStores.milestones.agentMessage
        // The caption says what the check is doing; OK follows the store's own
        // verdict, which also knows that an agent nobody has checked yet is not
        // one to start a run on.
        agentChecking: appStores.milestones.agentChecking
        agentReady: appStores.milestones.agentReady
        jobRunning: appStores.milestones.jobState === "running"
        docsLoading: appStores.docs.docsLoading
        docsError: appStores.docs.docsError
        theme: panelTheme
        onSpecChosen: function(path) { appStores.milestones.selectedSpec = path }
        onSubmitRequested: appStores.milestones.startFromSpec()
        onCancelRequested: appStores.milestones.cancelDialog()
      }

      // The dispatch (S3 4.2): the card detail's Dispatch and d open it for a
      // card at the form; Start run and d on the Runs list open it at the
      // store's project step, then its target step, then the form. Panel
      // keeps the card (dispatchCardId) and composes the subtask's story and
      // blockers; the store holds the rest.
      DispatchDialog {
        id: dispatchDialog
        objectName: "dispatchDialog"
        anchors.fill: parent
        shown: root.dispatchOpen
        theme: panelTheme
        step: appStores.runDispatch.dispatchStep
        projectName: root.dispatchProjectName
        projectRows: appStores.runDispatch.dispatchProjectRows
        targetRows: appStores.runDispatch.dispatchTargetRows
        targetLoading: appStores.runDispatch.dispatchTargetLoading
        targetKey: appStores.runDispatch.dispatchTargetKey
        dispatchState: appStores.runDispatch.dispatchState
        target: appStores.runDispatch.dispatchTarget
        targetTitle: root.dispatchCard ? String(root.dispatchCard.title || "") : ""
        targetLabel: appStores.runDispatch.dispatchTargetLabel
        form: appStores.runDispatch.dispatchForm
        preview: appStores.runDispatch.dispatchPreview
        error: appStores.runDispatch.dispatchError
        logPath: appStores.runDispatch.dispatchLog
        logTail: appStores.runDispatch.dispatchLogTail
        exitCode: appStores.runDispatch.dispatchExitCode
        storyTitle: root.dispatchStoryTitle
        blockedText: root.dispatchBlockedText
        confirmFirst: root.dispatchSubtask
        suggestion: root.dispatchSuggestion
        onProjectChosen: function(projectRoot) { appStores.runDispatch.dispatchProjectPick(projectRoot) }
        onTargetPicked: function(key) { root.pickRunsTarget(key) }
        onBackRequested: appStores.runDispatch.dispatchBack()
        onFieldEdited: function(name, value) { appStores.runDispatch.setDispatchField(name, value) }
        onStartRequested: appStores.runDispatch.dispatchStart()
        onCancelRequested: appStores.runDispatch.closeDispatch()
        // The store reopens on the milestone and clears its suggestion; the
        // card follows only when it did.
        onSuggestionRequested: {
          if (!root.dispatchSuggestion) return
          var milestoneId = root.dispatchSuggestion.id
          if (appStores.runDispatch.retargetToMilestone()) root.dispatchCardId = milestoneId
        }
      }
    }
  }
}
