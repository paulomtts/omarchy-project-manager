import QtQuick
import "../core/domain/board.js" as Board

// The ui-side navigation controller: where the panel is, what the cursor is on,
// and the return-stack bookkeeping around an open card, document or memory note.
// The stores hold the state; this file combines them with the scroll position
// and the focus. Everything that needs an Item is handed in -- `flick` (the
// Flickable, null in tests that do not need it) and `actions`
// (`focusForView()`, `scrollToTop()`, `scrollBy(px)`, `centerOnGraphNode(id)`)
// -- so the navigator never reaches back into Panel.qml.
QtObject {
  id: navi

  property var app: null
  property Item flick: null
  property var actions: null
  property bool documentsEnabled: true

  function currentList() {
    if (navi.app.nav.viewMode === "board") return navi.app.board.boardCards
    if (navi.app.nav.viewMode === "entry") return navi.app.board.detailLinkList
    if (navi.app.nav.viewMode === "documents") return navi.app.docs.filteredDocs
    if (navi.app.nav.viewMode === "memories") return navi.app.memories.filteredMemories
    if (navi.app.nav.viewMode === "issues") return navi.app.extras.filteredIssues
    if (navi.app.nav.viewMode === "issue") return navi.app.extras.detailLinkList
    return []
  }

  function resetSearch() {
    navi.app.nav.resetSearch()
  }

  // ---- Breadcrumbs: where the panel is, as [{ label, clickable, id? }],
  // outermost first. The last crumb is the current location; the first one is
  // the section, and clicking it is what "‹ Back" used to be.
  readonly property var crumbs: navi.buildCrumbs()

  function buildCrumbs() {
    if (!navi.app) return []
    if (!navi.app.projects.selectedProject) return [{ label: "Project Manager", clickable: false }]
    var mode = navi.app.nav.viewMode
    var section = { label: navi.app.nav.sectionTitle,
                    clickable: mode === "entry" || mode === "document" || mode === "memory" || mode === "issue" }
    if (mode === "issue") {
      var issue = navi.app.extras.selectedIssue
      return [section, { label: issue ? issue.title : navi.app.extras.selectedIssueId, clickable: false }]
    }
    if (mode === "document")
      return [section, { label: navi.documentTitle(navi.app.docs.selectedDocPath), clickable: false }]
    if (mode === "memory") {
      var entry = navi.app.memories.selectedMemoryEntry
      return [section, { label: entry && entry.name ? entry.name : navi.app.memories.selectedMemory, clickable: false }]
    }
    if (mode === "entry") {
      var trail = [section]
      var ids = Board.ancestorIds(navi.app.board.selectedCardId, navi.app.board.cardMap)
      for (var i = 0; i < ids.length; i++)
        trail.push({ label: navi.app.board.cardMap[ids[i]].title, clickable: true, id: ids[i] })
      var card = navi.app.board.cardMap[navi.app.board.selectedCardId]
      trail.push({ label: card ? card.title : navi.app.board.selectedCardId, clickable: false })
      return trail
    }
    return [section]
  }

  // The listing's title for an open document, or its file name when it has none.
  function documentTitle(path) {
    var docs = navi.app.docs.docs
    for (var i = 0; i < docs.length; i++)
      if (docs[i].path === path && docs[i].title) return docs[i].title
    return String(path || "").split("/").pop()
  }

  // A click on a crumb: the section goes back the way "‹ Back" did, an ancestor
  // opens that card, and the current location does nothing.
  function activateCrumb(index) {
    var trail = navi.crumbs
    if (index < 0 || index >= trail.length) return
    var crumb = trail[index]
    if (!crumb.clickable) return
    if (index === 0) { navi.goBack(); return }
    if (crumb.id) navi.openCard(crumb.id)
  }

  function moveGraph(direction) {
    var next = navi.app.graph.moveGraph(direction)
    if (next === "") return
    navi.actions.centerOnGraphNode(next)
  }

  function moveCursor(delta) {
    var list = navi.currentList()
    if (list.length === 0) return
    navi.app.nav.moveCursor(delta, list.length)
    // Reaching the first row of a list shows whatever sits above it in the
    // scrolling content (e.g. the Documents type badges).
    if (navi.app.nav.cursorIndex === 0 && navi.app.nav.viewMode !== "entry") Qt.callLater(navi.actions.scrollToTop)
  }

  function hoverCursor(index) {
    navi.app.nav.hoverCursor(index)
  }

  function activateCursor() {
    var list = navi.currentList()
    if (navi.app.nav.cursorIndex < 0 || navi.app.nav.cursorIndex >= list.length) return
    if (navi.app.nav.viewMode === "documents") navi.openDoc(list[navi.app.nav.cursorIndex].path)
    else if (navi.app.nav.viewMode === "memories") navi.openMemory(list[navi.app.nav.cursorIndex].file)
    else if (navi.app.nav.viewMode === "issues") navi.openIssue(list[navi.app.nav.cursorIndex].id)
    else if (navi.app.nav.viewMode === "issue") navi.openIssueLink(list[navi.app.nav.cursorIndex].id)
    else if (navi.app.nav.viewMode === "entry") navi.openBlocker(list[navi.app.nav.cursorIndex].id)
    else navi.openCard(list[navi.app.nav.cursorIndex].id)
  }

  function activateGraphNode() {
    var id = navi.app.graph.activateGraphNode()
    if (id !== "") navi.openCard(id)
  }

  // The user picked a project in the dropdown. A dirty memory draft blocks the
  // switch.
  function chooseProject(project) {
    if (navi.app.memories.memoryEditing && navi.app.memories.memoryDraft !== navi.app.memories.memoryText) {
      navi.closeDropdown()
      navi.app.memories.memoryOpError = "You have unsaved changes. Save them, or choose Cancel to discard, before switching project."
      return
    }
    navi.closeDropdown()
    if (!project) return
    navi.app.projects.chooseProject(project)
    navi.actions.focusForView()
  }

  function toggleDropdown() {
    if (navi.app.deleter.deleteTarget) return
    if (navi.app.nav.dropdownOpen) { navi.closeDropdown(); return }
    var index = 0
    for (var i = 0; i < navi.app.projects.projects.length; i++)
      if (navi.app.projects.selectedProject && navi.app.projects.projects[i].root_path === navi.app.projects.selectedProject.root_path) index = i
    navi.app.nav.toggleDropdown(index)
    navi.actions.focusForView()
  }

  function closeDropdown() {
    if (!navi.app.nav.dropdownOpen) return
    navi.app.nav.closeDropdown()
    navi.actions.focusForView()
  }

  function moveDropdown(delta) {
    navi.app.nav.moveDropdown(delta, navi.app.projects.filteredProjects.length)
  }

  function acceptDropdown() {
    var list = navi.app.projects.filteredProjects
    if (navi.app.nav.dropdownCursor < 0 || navi.app.nav.dropdownCursor >= list.length) return
    navi.chooseProject(list[navi.app.nav.dropdownCursor])
  }

  function showSection(name) {
    if (!navi.app.projects.selectedProject || navi.app.deleter.deleteTarget || navi.app.memories.memoryDeleteOpen || navi.app.memories.newMemoryOpen || navi.app.milestones.dialogOpen || navi.app.board.archiveOpen) return
    if (navi.app.memories.memoryEditing && navi.app.memories.memoryDraft !== navi.app.memories.memoryText) return
    if (name === "documents" && !navi.documentsEnabled) return
    var wasSection = navi.app.nav.section
    if (navi.app.nav.dropdownOpen) navi.app.nav.dropdownOpen = false
    navi.resetSearch()
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.viewMode = name === "documents" ? "documents" : name === "graph" ? "graph"
      : name === "memories" ? "memories" : name === "issues" ? "issues" : "board"
    navi.app.memories.memoryEditing = false
    // Only here: `brd doc list` syncs every backup as it lists -- it WRITES --
    // so it follows the section being ENTERED and nothing else. Ctrl+3 pressed
    // again inside the Documents section refreshes the read-only listing and
    // leaves brd's backups alone.
    if (name === "documents") {
      navi.app.docs.fetchDocs()
      if (wasSection !== "documents") navi.app.docs.fetchRegisteredDocs()
    }
    if (name === "memories") navi.app.memories.fetchMemories()
    if (name === "graph" && navi.app.graph.graphCursor === "" && navi.app.graph.currentNodes.length > 0) navi.app.graph.graphCursor = navi.app.graph.currentNodes[0].id
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function openCard(id) {
    var from = navi.app.nav.viewMode
    if (!navi.app.board.openCard(id)) return
    // A card opened from an issue comes back to the Issues list, not the board.
    // openIssue() already stored that list's cursor and scroll position, so the
    // return slot is only re-labelled: overwriting it would bring the list back
    // on the detail's link index instead of the row the user left.
    if (from === "issue") navi.app.nav.returnMode = "issues"
    else if (from === "board" || from === "graph")
      navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0, from)
    navi.app.nav.viewMode = "entry"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  // Leaving a card puts the Board back exactly as it was: same highlighted
  // card, same scroll position.
  function restoreListView() {
    var back = navi.app.nav.popReturn()
    // Back to the Issues list: the issue that led here is no longer open.
    if (back.mode === "issues") navi.app.extras.restoreIssuesList()
    navi.app.nav.viewMode = back.mode
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  function openDoc(path) {
    if (!navi.app.docs.openDoc(path)) return
    navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "document"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function restoreDocumentsList() {
    navi.app.docs.restoreDocumentsList()
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = "documents"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  // ---- Memories: the notes themselves live in MemoriesStore; what stays here
  // is the navigation and focus work around them.
  function openMemory(file) {
    if (!navi.app.memories.openMemory(file)) return
    if (navi.app.nav.viewMode === "memories")
      navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "memory"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function restoreMemoriesList() {
    navi.app.memories.restoreMemoriesList()
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = "memories"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  // ---- Issues: the issues themselves live in ExtrasStore; the navigation and
  // focus work around them is here, like the cards and the documents.
  function openIssue(id) {
    var from = navi.app.nav.viewMode
    if (!navi.app.extras.openIssue(id)) return
    // From a card's blocker row the card stays open behind the issue and its
    // return slot must survive, so only the Issues list pushes one.
    navi.app.nav.issueReturnMode = from === "entry" ? "entry" : "issues"
    if (from !== "entry") navi.app.nav.pushReturn(navi.flick ? navi.flick.contentY : 0)
    navi.app.nav.viewMode = "issue"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  // A link row of an open issue: a card opens as a card, a known issue as an
  // issue. openIssue() pushes its own return position, so an issue reached from
  // an issue still comes back one step at a time.
  function openIssueLink(id) {
    var resolved = navi.app.extras.resolvedTarget(id)
    if (resolved.inBoard) navi.openCard(id)
    else if (resolved.kind === "issue") navi.openIssue(id)
  }

  // A blocker row of an open card: a card of this board opens as a card, an
  // issue the board knows opens in the Issues section (the same rule
  // openIssueLink() follows for an issue's own link rows).
  function openBlocker(id) {
    var resolved = navi.app.board.resolvedCard(id)
    if (resolved.inBoard) navi.openCard(id)
    else if (resolved.kind === "issue") navi.openIssue(id)
  }

  // Leaving an issue that was opened from a card: back to that card, with the
  // cursor on the blocker row it came from. The card's own return position was
  // never touched, so Back from the card still reaches its list.
  function restoreCardFromIssue() {
    var id = navi.app.extras.selectedIssueId
    navi.app.extras.restoreIssuesList()
    navi.app.nav.issueReturnMode = "issues"
    navi.app.nav.viewMode = "entry"
    navi.app.nav.scrollOnCursor = false
    var index = navi.app.board.linkIndex("blocker", id)
    navi.app.nav.cursorIndex = index >= 0 ? index : 0
    Qt.callLater(navi.actions.scrollToTop)
    navi.actions.focusForView()
  }

  function restoreIssuesList() {
    navi.app.extras.restoreIssuesList()
    var back = navi.app.nav.popReturn()
    navi.app.nav.viewMode = "issues"
    navi.app.nav.scrollOnCursor = false
    navi.app.nav.cursorIndex = back.cursor
    Qt.callLater(function() { if (navi.flick) navi.actions.scrollBy(back.scrollY - navi.flick.contentY) })
    navi.actions.focusForView()
  }

  function goBack() {
    if (navi.app.nav.viewMode === "issue") {
      if (navi.app.nav.issueReturnMode === "entry") navi.restoreCardFromIssue()
      else navi.restoreIssuesList()
      return
    }
    if (navi.app.nav.viewMode === "memory") { if (navi.app.memories.memoryEditing) navi.app.memories.memoryEscape(); else navi.restoreMemoriesList(); return }
    if (navi.app.nav.viewMode === "entry") { navi.restoreListView(); return }
    if (navi.app.nav.viewMode === "document") { navi.restoreDocumentsList(); return }
  }
}
