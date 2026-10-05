import QtQuick
import qs.Commons

// Every key the panel reacts to, in one place: the Ctrl chords, the run keys
// (p / r / c), the dispatch key (d), the Escape chain, the arrows the key
// catcher reports, and the search field's own keys.
// The ORDER of the guards here is load bearing -- a modal must swallow the
// global shortcuts, and Escape must unwind the modals before it unwinds the
// navigation -- so nothing in this file may be reordered.
// The panel hands in `actions`: close(), scrollBy(px), switchPanel(direction),
// searchAtEnd() (is the caret at the end of the search text?) and
// openDispatch(target) (a card id: open the dispatch dialog on it).
QtObject {
  id: keys

  property var app: null
  property var navigator: null
  property var actions: null

  // Shortcuts that work wherever the caret is. Returns true when it handled the
  // key. Ignored while a modal is open (modalOpen) so a stray Ctrl+P cannot
  // move things underneath it. The digit chords follow the order the sidebar
  // lists its sections in (Board, Graph, Documents, Memories, Issues, Runs) --
  // renumbering one means renumbering the sidebar too.
  function handleGlobalKey(event) {
    if (!(event.modifiers & Qt.ControlModifier) || keys.modalOpen()) return false
    if (event.key === Qt.Key_P) { keys.navigator.toggleDropdown(); return true }
    if (event.key === Qt.Key_1) { keys.navigator.showSection("board"); return true }
    if (event.key === Qt.Key_2) { keys.navigator.showSection("graph"); return true }
    if (event.key === Qt.Key_3) { keys.navigator.showSection("documents"); return true }
    if (event.key === Qt.Key_4) { keys.navigator.showSection("memories"); return true }
    if (event.key === Qt.Key_5) { keys.navigator.showSection("issues"); return true }
    if (event.key === Qt.Key_6) { keys.navigator.showSection("runs"); return true }
    if (event.key === Qt.Key_N && keys.app.nav.viewMode === "memories") { keys.app.memories.openNewMemory(); return true }
    if (event.key === Qt.Key_E && keys.app.nav.viewMode === "memory") { keys.app.memories.startMemoryEdit(); return true }
    return false
  }

  // Escape (and the key catcher's close gesture): innermost thing first. The
  // run toasts come right after the modals: they are not a modal, but an
  // Escape with toasts showing never goes Back or closes the panel. An open
  // dispatch closes like the other modals; while its start is in flight
  // closeDispatch() refuses, so that Escape does nothing at all.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.board.archiveOpen ? keys.app.board.cancelArchive() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : keys.app.runs.dispatchState !== "idle" ? keys.app.runs.closeDispatch() : keys.app.runs.cancelOpen ? keys.app.runs.closeCancel() : keys.app.runs.toasts.length > 0 ? keys.app.runs.dismissAllToasts() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
  }

  // A modal is open: the global shortcuts, the run keys and d do nothing under it.
  function modalOpen() {
    return !!(keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen
              || keys.app.milestones.dialogOpen || keys.app.board.archiveOpen || keys.app.runs.cancelOpen
              || keys.app.runs.dispatchState !== "idle")
  }

  // p / r / c with no modifier at all pause, resume or cancel a run: on Run
  // detail the open run, on the Runs list the cursor row -- there only while
  // the search is empty, since the search field has the focus and every letter
  // types once it holds text (Shift+letter always types). A refused key
  // flashes why; c opens the cancel confirmation. Returns true when it handled
  // the key; with no target run the letter is left alone.
  function handleRunKey(event) {
    if (event.modifiers !== Qt.NoModifier) return false
    var action = event.key === Qt.Key_P ? "pause" : event.key === Qt.Key_R ? "resume" : event.key === Qt.Key_C ? "cancel" : ""
    if (action === "") return false
    var mode = keys.app.nav.viewMode
    if (!keys.app.projects.selectedProject || (mode !== "runs" && mode !== "run")) return false
    if (keys.modalOpen() || keys.app.nav.dropdownOpen) return false
    if (mode === "runs" && keys.app.nav.searchQuery !== "") return false
    var run = mode === "run" ? keys.app.runs.runById(keys.app.runs.selectedRunId) : keys.app.runs.filteredRuns[keys.app.nav.cursorIndex]
    var id = run && typeof run.id === "string" ? run.id : ""
    if (id === "") return false
    var reason = keys.app.runs.refusalOf(action, id)
    if (reason !== "") keys.app.runs.flash(reason)
    else if (action === "cancel") keys.app.runs.openCancel(id)
    else keys.app.runs.control(action, id)
    return true
  }

  // d with no modifier at all opens the dispatch dialog -- it never starts
  // anything: on the board list for the cursor card, there only while the
  // search is empty (the search field has the focus and every letter types
  // once it holds text; Shift+D always types), and on a card for that card.
  // Needs a project and am; under a modal or the open dropdown, or anywhere
  // else, the letter is left alone.
  function handleDispatchKey(event) {
    if (event.modifiers !== Qt.NoModifier || event.key !== Qt.Key_D) return false
    var mode = keys.app.nav.viewMode
    if (!keys.app.projects.selectedProject || (mode !== "board" && mode !== "entry")) return false
    if (keys.app.runs.amStatus === "missing" || keys.modalOpen() || keys.app.nav.dropdownOpen) return false
    if (mode === "board" && keys.app.nav.searchQuery !== "") return false
    var card = mode === "entry" ? keys.app.board.cardMap[keys.app.board.selectedCardId]
                                : keys.app.board.boardCards[keys.app.nav.cursorIndex]
    var id = card && typeof card.id === "string" ? card.id : ""
    if (id === "") return false
    keys.actions.openDispatch(id)
    return true
  }

  function handleMove(dx, dy) {
    if (keys.app.nav.viewMode === "graph") {
      if (dx !== 0) keys.navigator.moveGraph(dx < 0 ? "left" : "right")
      else if (dy !== 0) keys.navigator.moveGraph(dy < 0 ? "up" : "down")
      return
    }
    if (dx < 0 && (keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run")) { keys.navigator.goBack(); return }
    if (keys.app.nav.viewMode !== "entry" && keys.app.nav.viewMode !== "document" && keys.app.nav.viewMode !== "memory" && keys.app.nav.viewMode !== "issue") return
    if (dx > 0) { if (keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "issue") keys.navigator.activateCursor(); return }
    if (dy === 0) return
    // Links are the cursor's targets; a card or an issue without any is just
    // text, so the arrows scroll it instead.
    if ((keys.app.nav.viewMode === "entry" && keys.app.board.detailLinkList.length > 0)
        || (keys.app.nav.viewMode === "issue" && keys.app.extras.detailLinkList.length > 0)) keys.navigator.moveCursor(dy)
    else keys.actions.scrollBy(dy * Style.space(56))
  }

  function handleActivate() {
    if (keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "issue") keys.navigator.activateCursor()
    else if (keys.app.nav.viewMode === "graph") keys.navigator.activateGraphNode()
  }

  // The search field's keys. Its Escape does not go through closeRequested():
  // the run toasts go first, then a non-empty search, then the panel.
  function handleSearchKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (keys.app.runs.toasts.length > 0) keys.app.runs.dismissAllToasts()
      else if (keys.app.nav.searchQuery !== "") { keys.app.nav.searchQuery = "" }
      else keys.actions.close()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right && keys.actions.searchAtEnd()) {
      keys.navigator.activateCursor(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Down) { keys.navigator.moveCursor(1); event.accepted = true; return }
    if (event.key === Qt.Key_Up) { keys.navigator.moveCursor(-1); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      keys.navigator.activateCursor(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      keys.actions.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
  }
}
