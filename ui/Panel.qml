import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
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
  // the scroll is the panel's.
  Connections {
    target: appStores.runs
    function onRunFilterToggled() { Qt.callLater(root.scrollToTop) }
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
  // the panel, scrolling, switching panel and "is the caret at the end of the
  // search text?" are handed in.
  Shortcuts {
    id: sc
    app: appStores
    navigator: navi
    actions: ({
      close: function() { root.close() },
      scrollBy: root.scrollBy,
      switchPanel: function(direction) { root.switchPanel(direction) },
      searchAtEnd: function() { return searchField.cursorPosition === searchField.text.length }
    })
  }
  readonly property var shortcuts: sc

  readonly property Item focusItem: appStores.deleter.deleteTarget ? deleteModal.focusItem
    : appStores.board.archiveOpen ? archiveDialog.focusItem
    : appStores.memories.memoryDeleteOpen ? memoryConfirm.focusItem
    : appStores.memories.newMemoryOpen ? newMemoryDialog.focusItem
    : appStores.milestones.dialogOpen ? newMilestoneDialog.focusItem
    : (appStores.nav.viewMode === "memory" && appStores.memories.memoryEditing) ? memoryNoteScreen.editorItem
    : appStores.nav.dropdownOpen ? sidebar.filterItem
    : (appStores.nav.viewMode === "entry" || appStores.nav.viewMode === "document" || appStores.nav.viewMode === "memory" || appStores.nav.viewMode === "issue" || appStores.nav.viewMode === "run" || appStores.nav.viewMode === "graph" || !appStores.projects.selectedProject) ? keyCatcher
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

    Item {
      id: globalKeys
      Keys.onPressed: function(event) { if (sc.handleGlobalKey(event)) event.accepted = true }
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
          visible: !!appStores.projects.selectedProject && (appStores.nav.viewMode === "board" || appStores.nav.viewMode === "documents" || appStores.nav.viewMode === "memories" || appStores.nav.viewMode === "issues" || appStores.nav.viewMode === "runs")
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

          UI.ThemedText {
            variant: "dim"
            theme: panelTheme
            visible: !appStores.projects.selectedProject && appStores.projects.loadError === ""
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
          }

          RunDetailScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }
        }
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
    }
  }
}
