import QtQml
import Quickshell
import Quickshell.Io
import "../domain/board.js" as Board

// The kanban board: the card tree from `brd tree`, the issues from
// `brd issue list` (a card's blocked_by may name one), what is visible once the
// search has been applied, and which card is open. The project, the watched
// database and the navigation values it needs are handed to it by App -- it
// never reaches for another store. Scrolling and focus stay in the panel.
Scope {
  id: board

  property var project: null          // set by App from ProjectStore.selectedProject
  property string dbPath: ""          // set by App from ProjectStore.watchedDbPath
  property string viewMode: "board"   // set by App from NavigationStore.viewMode
  property string searchQuery: ""     // set by App from NavigationStore.searchQuery
  property string backendDir: ""      // <plugin>/core/backend/, set by App
  // The clock the archive rule reads, in epoch ms; 0 means "the real time".
  // A test pins it so the rule is deterministic.
  property real nowMs: 0

  property var cardRoots: []   // top-level cards from the last brd tree fetch
  property var cardMap: ({})   // id -> card, from Board.indexTree
  property var issueMap: ({})  // id -> {id, title, status}, from Board.indexIssues
  readonly property var statuses: ["todo", "in_progress", "done", "merged", "canceled", "archived"]
  property string selectedCardId: ""

  // Archive finished: the milestones the rule offers, the confirm dialog and
  // the one helper run behind it. `archiveCandidates` follows the board and is
  // recomputed when the dialog opens and again at confirm time, so only what
  // the CURRENT board says is finished is ever handed to the helper.
  property var archiveCandidates: []
  property bool archiveOpen: false
  property string archiveError: ""
  readonly property bool archiveBusy: archiveRunner.busy
  readonly property alias archiveRunner: archiveRunner

  readonly property alias treeProc: treeProc
  readonly property alias issueProc: issueProc
  readonly property alias dbFile: dbFile
  readonly property alias watchTimer: watchTimer

  // The board could not be read, or was read again: the message the panel
  // shows lives on the project store, which App keeps in step.
  signal errored(string message)
  // The open card is gone from the tree: the panel puts its list back.
  signal listViewRequested()
  // The board was (re)fetched: whatever else follows the board -- the extras --
  // is refetched on the same triggers, without this store reaching for it.
  signal refetched()

  function fetchBoard() {
    if (!board.project) return
    board.errored("")
    treeProc.workingDirectory = board.project.root_path
    treeProc.running = false
    treeProc.running = true
    issueProc.workingDirectory = board.project.root_path
    issueProc.running = false
    issueProc.running = true
    board.refetched()
  }

  function applyTreeData(roots) {
    board.cardRoots = roots
    var indexed = Board.indexTree(roots)
    board.cardMap = indexed.cardMap
    board.refreshArchiveCandidates()
    if (board.viewMode === "entry" && !board.cardMap[board.selectedCardId]) board.listViewRequested()
  }

  function refreshArchiveCandidates() {
    board.archiveCandidates = Board.archivable(board.cardRoots, board.nowMs > 0 ? board.nowMs : Date.now())
  }

  function openArchive() {
    if (!board.project || board.archiveBusy) return
    board.refreshArchiveCandidates()
    if (board.archiveCandidates.length === 0) return
    board.archiveError = ""
    board.archiveOpen = true
  }

  function cancelArchive() {
    if (board.archiveBusy) return
    board.archiveOpen = false
    board.archiveError = ""
  }

  // A project change: the dialog goes, and so does any answer still on its way.
  function resetArchive() {
    if (board.archiveBusy) board.archiveRunner.cancel()
    board.archiveOpen = false
    board.archiveError = ""
  }

  function archiveAll() {
    if (!board.archiveOpen || board.archiveBusy || !board.project) return
    board.refreshArchiveCandidates()
    var ids = board.archiveCandidates.map(function(c) { return c.id })
    if (ids.length === 0) { board.archiveOpen = false; return }
    board.archiveError = ""
    board.archiveRunner.run([board.project.root_path].concat(ids))
  }

  function applyArchiveResult(stdout, exitCode) {
    var result = Board.parseArchiveResult(stdout, exitCode)
    if (result.ok) {
      board.archiveOpen = false
      board.archiveError = ""
      return
    }
    var titles = {}
    board.archiveCandidates.forEach(function(c) { titles[c.id] = c.title })
    board.archiveError = result.failures.length > 0
      ? result.failures.map(function(f) {
          return "Could not archive " + (titles[f.id] || f.id) + ": " + f.error
        }).join("\n")
      : result.error
  }

  function applyIssueData(issues) {
    board.issueMap = Board.indexIssues(issues)
  }

  readonly property var visibleBoardRoots: board.cardRoots.filter(function(c) {
    return Board.subtreeMatches(c, board.searchQuery)
  })

  function boardColumn(status) {
    return board.visibleBoardRoots.filter(function(c) {
      return Board.effectiveStatus(c) === status
    })
  }

  // All visible Board cards as one list, section by section: the order the
  // keyboard cursor walks them in.
  readonly property var boardCards: Board.boardOrder(board.visibleBoardRoots, board.statuses)

  // The clickable rows of the card being viewed, in display order.
  readonly property var detailLinkList: board.viewMode === "entry"
    ? Board.detailLinks(board.cardMap[board.selectedCardId], board.cardMap, board.issueMap) : []

  function boardIndexOf(id) {
    for (var i = 0; i < board.boardCards.length; i++)
      if (board.boardCards[i].id === id) return i
    return -1
  }

  function linkIndex(section, id) {
    for (var i = 0; i < board.detailLinkList.length; i++)
      if (board.detailLinkList[i].section === section && board.detailLinkList[i].id === id) return i
    return -1
  }

  function statusText(status) {
    if (status === "todo") return "Todo"
    if (status === "in_progress") return "In progress"
    if (status === "done") return "Done"
    if (status === "merged") return "Merged"
    if (status === "canceled") return "Canceled"
    if (status === "archived") return "Archived"
    if (status === "blocked") return "Blocked"
    return String(status || "")
  }

  function statusLabel(status) {
    if (status === "todo") return "Todo"
    if (status === "in_progress") return "In Progress"
    if (status === "merged") return "Merged"
    if (status === "canceled") return "Canceled"
    if (status === "archived") return "Archived"
    return "Done"
  }

  // Selects a card, and says whether there was one to select: the navigation
  // bookkeeping around it is the panel's.
  function openCard(id) {
    if (!board.cardMap[id]) return false
    board.selectedCardId = id
    return true
  }

  function resolvedCard(id) {
    return Board.resolvedCard(id, board.cardMap, board.issueMap)
  }

  // Latest run wins; the guard is the project, so an answer that arrives after
  // a switch is dropped. The board refetches by itself when brd writes.
  HelperRunner {
    id: archiveRunner
    objectName: "archiveRunner"
    script: board.backendDir + "boards/archive-milestones.py"
    guard: board.project ? board.project.root_path : ""
    onFinished: function(stdout, exitCode) { board.applyArchiveResult(stdout, exitCode) }
  }

  FileView {
    id: dbFile
    objectName: "dbFile"
    path: board.dbPath !== "" ? board.dbPath : ""
    watchChanges: true
    printErrors: false
    // One brd write touches the database several times, and every touch would
    // otherwise cost a tree + issue + export fetch. The burst is coalesced into
    // a single refetch; Refresh and a project switch call fetchBoard() directly
    // and stay immediate.
    onFileChanged: watchTimer.restart()
  }

  Timer {
    id: watchTimer
    objectName: "watchTimer"
    interval: 250
    repeat: false
    onTriggered: board.fetchBoard()
  }

  Process {
    id: treeProc
    objectName: "treeProc"
    command: ["brd", "tree"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          board.errored("")
          board.applyTreeData(parsed.data || [])
        } catch (e) {
          board.applyTreeData([])
          board.errored("Could not load the board for this project.")
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        board.applyTreeData([])
        board.errored("Could not load the board for this project.")
      }
    }
  }

  // Issues are extra: a brd too old to have them (or any other failure) just
  // means no issues, never a board error.
  Process {
    id: issueProc
    objectName: "issueProc"
    command: ["brd", "issue", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          board.applyIssueData(parsed.ok === true && Array.isArray(parsed.data) ? parsed.data : [])
        } catch (e) {
          board.applyIssueData([])
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) board.applyIssueData([])
    }
  }
}
