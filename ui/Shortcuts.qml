import QtQuick
import qs.Commons

// Every key the panel reacts to, in one place: the Ctrl chords, the Escape
// chain, the arrows the key catcher reports, and the search field's own keys.
// The ORDER of the guards here is load bearing -- a modal must swallow the
// global shortcuts, and Escape must unwind the modals before it unwinds the
// navigation -- so nothing in this file may be reordered.
// The panel hands in `actions`: close(), scrollBy(px), switchPanel(direction)
// and searchAtEnd() (is the caret at the end of the search text?).
QtObject {
  id: keys

  property var app: null
  property var navigator: null
  property var actions: null

  // Shortcuts that work wherever the caret is. Returns true when it handled the
  // key. Ignored while a delete confirmation is open so a stray Ctrl+P cannot
  // move things underneath it. The digit chords follow the order the sidebar
  // lists its sections in (Board, Graph, Documents, Memories, Issues, Runs) --
  // renumbering one means renumbering the sidebar too.
  function handleGlobalKey(event) {
    if (!(event.modifiers & Qt.ControlModifier) || keys.app.deleter.deleteTarget || keys.app.memories.memoryDeleteOpen || keys.app.memories.newMemoryOpen || keys.app.milestones.dialogOpen) return false
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

  // Escape (and the key catcher's close gesture): innermost thing first.
  function closeRequested() {
    keys.app.deleter.deleteTarget ? keys.app.deleter.cancelDelete() : keys.app.memories.memoryDeleteOpen ? keys.app.memories.cancelMemoryDelete() : keys.app.memories.newMemoryOpen ? keys.app.memories.cancelNewMemory() : keys.app.milestones.dialogOpen ? keys.app.milestones.cancelDialog() : (keys.app.nav.dropdownOpen ? keys.navigator.closeDropdown() : ((keys.app.nav.viewMode === "entry" || keys.app.nav.viewMode === "document" || keys.app.nav.viewMode === "memory" || keys.app.nav.viewMode === "issue" || keys.app.nav.viewMode === "run") ? keys.navigator.goBack() : keys.actions.close()))
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

  function handleSearchKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (keys.app.nav.searchQuery !== "") { keys.app.nav.searchQuery = "" }
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
