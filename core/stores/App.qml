import QtQml

// The panel's non-visual state, in one place, plus the wiring between stores:
// a store never reaches for another one, App composes them and hands each
// what it needs through properties and signals.
QtObject {
  id: app

  property string backendDir: ""
  property bool panelOpen: false   // the panel is open; Panel.qml binds it to its `opened`

  readonly property NavigationStore nav: NavigationStore {}

  readonly property ProjectStore projects: ProjectStore {
    backendDir: app.backendDir
    dropdownQuery: app.nav.dropdownQuery
    onSelected: function(project) {
      app.nav.viewMode = "board"
      app.nav.resetSearch()
      app.graph.graphCursor = ""
      app.extras.reset()
      app.board.resetArchive()
      app.board.fetchBoard()
      app.docs.reset()
      app.memories.resetMemories()
      app.milestones.reset()
    }
    onCleared: {
      app.nav.viewMode = "board"
      app.board.resetArchive()
      app.board.applyTreeData([])
      app.board.applyIssueData([])
      app.graph.graphCursor = ""
      app.extras.reset()
      app.docs.reset()
      app.memories.resetMemories()
      app.milestones.reset()
    }
    onChosen: app.deleter.lastSnapshot = ""
    onOpened: {
      app.nav.dropdownOpen = false
      app.nav.dropdownQuery = ""
      app.deleter.onPanelOpened()
    }
  }

  readonly property BoardStore board: BoardStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject
    dbPath: app.projects.watchedDbPath
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onErrored: function(message) { app.projects.loadError = message }
    onRefetched: app.extras.fetchExtras()
  }

  // The extras follow the board: same triggers, one extra read-only brd call.
  // They never feed the board back -- the blocker rows and the graph keep
  // reading BoardStore's own issue map.
  readonly property ExtrasStore extras: ExtrasStore {
    project: app.projects.selectedProject
    cardMap: app.board.cardMap
    issueMap: app.board.issueMap
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onStatusToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }

  readonly property DocumentsStore docs: DocumentsStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onCategoryToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }

  readonly property MemoriesStore memories: MemoriesStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject
    viewMode: app.nav.viewMode
    searchQuery: app.nav.searchQuery
    onTypeToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
  }

  // The milestone store never imports the board store: the number of cards the
  // board knows about is handed in, and its refresh request is routed here.
  readonly property MilestoneStore milestones: MilestoneStore {
    backendDir: app.backendDir
    project: app.projects.selectedProject
    cardCount: Object.keys(app.board.cardMap).length
    onBoardRefreshRequested: app.board.fetchBoard()
  }

  // The run store never imports the project or board store: App hands it the
  // registry's roots and names in registry order, the selected project's root
  // path (never the project object), the open project's card id -> title map
  // (titles, from the board's cardMap) and the panel-open flag that starts
  // and stops its watch.
  readonly property RunStore runs: RunStore {
    backendDir: app.backendDir
    projectRoots: app.projects.projects.map(function(p) { return { root: p.root_path, name: p.name } })
    project: app.projects.selectedProject ? app.projects.selectedProject.root_path : ""
    titles: {
      var map = app.board.cardMap || {}
      var out = {}
      var ids = Object.keys(map)
      for (var i = 0; i < ids.length; i++) {
        var card = map[ids[i]]
        if (card && typeof card.title === "string") out[ids[i]] = card.title
      }
      return out
    }
    active: app.panelOpen
    searchQuery: app.nav.searchQuery
    onRunFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
    onProjectFilterToggled: {
      app.nav.cursorIndex = 0
      app.nav.scrollOnCursor = false
    }
    onSnapshotReplied: function(root, outcome, previousRuns, runs) {
      if (outcome === "ok") app.runControl.settleAfterSnapshot()
      app.runAlerts.snapshotReplied(root, outcome, previousRuns, runs)
    }
  }

  // The run controls never import the run store: App hands them the backend
  // directory, the open project's root, the panel-open flag and the run list,
  // settles their requests on each ok snapshot reply, routes their
  // refreshRequested to the run store, their runSettingsSaveFailed to the
  // dispatch's dispatchSaveFailed and their runSettingsLoaded to the
  // dispatch's dispatchSettingsReplied.
  readonly property RunControlStore runControl: RunControlStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
    onRunSettingsSaveFailed: function(root, patch) { app.runDispatch.dispatchSaveFailed(root, patch) }
    onRunSettingsLoaded: function(root, settings) { app.runDispatch.dispatchSettingsReplied(root, settings) }
  }

  // The run alerts never import the run store: App hands them the backend
  // directory, the panel-open flag, run control's notify switch and the
  // registry, and routes every project's snapshot reply (runs.snapshotReplied)
  // here.
  readonly property RunAlertsStore runAlerts: RunAlertsStore {
    backendDir: app.backendDir
    active: app.panelOpen
    notifyOnEscalation: app.runControl.notifyOnEscalation
    projectRoots: app.runs.projectRoots
  }

  // The dispatch never imports the run store or run control: App hands it the
  // backend directory, the open project's root, the registry, the panel-open
  // flag, the run list and the open project's run settings from run control,
  // routes its refreshRequested to the run store, its noticeRequested to run
  // control's flash, and its runSettingsWanted and runSettingsSaveRequested
  // to run control's loadRunSettings and saveRunSettings.
  readonly property RunDispatchStore runDispatch: RunDispatchStore {
    backendDir: app.backendDir
    project: app.runs.project
    active: app.panelOpen
    runs: app.runs.runs
    runSettings: app.runControl.runSettingsOf(app.runs.project)
    projectRoots: app.runs.projectRoots
    onRefreshRequested: function(roots) {
      if (roots === "all") app.runs.refresh()
      else app.runs.requestSnapshot(roots)
    }
    onNoticeRequested: function(text) { app.runControl.flash(text) }
    onRunSettingsWanted: function(root) { app.runControl.loadRunSettings(root) }
    onRunSettingsSaveRequested: function(root, patch) { app.runControl.saveRunSettings(root, patch) }
  }

  // The live output store never imports the run store: App hands it the
  // selected run (normalized, from the run store's snapshot), the attempt or
  // step Run detail shows (selectedAttempt) and the two presence flags --
  // the panel open and the view mode "run" -- and routes its snapshot
  // request to the run store's refreshLogs.
  readonly property RunOutputStore runOutput: RunOutputStore {
    backendDir: app.backendDir
    active: app.panelOpen
    inRunDetail: app.nav.viewMode === "run"
    run: app.runs.runById(app.runs.selectedRunId)
    selection: app.runs.selectedAttempt
    onSnapshotWanted: app.runs.refreshLogs()
  }

  readonly property GraphStore graph: GraphStore {
    cardRoots: app.board.cardRoots
    issueMap: app.board.issueMap
  }

  readonly property ProjectDeleteStore deleter: ProjectDeleteStore {
    backendDir: app.backendDir
    projects: app.projects
    onRequested: app.nav.dropdownOpen = false
    onDeleted: app.nav.cursorIndex = 0
  }
}
