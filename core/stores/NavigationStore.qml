import QtQml

// Where the panel is and what the keyboard cursor is on. State and pure
// functions only: everything that needs an Item (scrolling, focus) stays in the
// UI, which passes in whatever the store needs (a list length, a scroll offset).
QtObject {
  id: nav

  property string viewMode: "board"   // "board" | "entry" | "documents" | "document" | "graph" | "memories" | "memory" | "issues" | "issue" | "runs" | "run"

  readonly property string section: (viewMode === "documents" || viewMode === "document") ? "documents"
    : (viewMode === "memories" || viewMode === "memory") ? "memories"
    : (viewMode === "issues" || viewMode === "issue") ? "issues"
    : (viewMode === "runs" || viewMode === "run") ? "runs"
    : viewMode === "graph" ? "graph"
    : (viewMode === "entry" && nav.returnMode === "graph") ? "graph"
    : (viewMode === "entry" && nav.returnMode === "issues") ? "issues" : "board"
  readonly property string sectionTitle: section === "documents" ? "Documents" : section === "graph" ? "Graph"
    : section === "memories" ? "Memories" : section === "issues" ? "Issues" : section === "runs" ? "Runs" : "Board"

  property string searchQuery: ""
  property int cursorIndex: 0
  // True only while the keyboard is driving the cursor: rows then scroll
  // themselves into view. Hover must not scroll, or the list would move
  // under a stationary pointer and re-trigger hover.
  property bool scrollOnCursor: false
  property double lastKeyMoveMs: 0

  property int returnCursor: 0
  property string returnMode: "board"   // the list a card was opened from
  property real returnScrollY: 0

  // Where an open issue goes back to. An issue reached from a card's blocker
  // row returns to that card, and the single return slot above -- which holds
  // the card's own way back -- is left untouched, so Back from the card still
  // works afterwards.
  property string issueReturnMode: "issues"   // "issues" | "entry"

  // Where an open run goes back to. A run reached from a card's RUNS row
  // returns to that card, and the single return slot above -- which holds the
  // card's own way back -- is left untouched, as for an issue.
  property string runReturnMode: "runs"   // "runs" | "entry"

  property bool dropdownOpen: false
  property string dropdownQuery: ""
  property int dropdownCursor: 0

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function resetSearch() {
    searchQuery = ""
    cursorIndex = 0
  }

  function moveCursor(delta, count) {
    if (count === 0) return
    nav.scrollOnCursor = true
    nav.lastKeyMoveMs = Date.now()
    nav.cursorIndex = nav.clamp(nav.cursorIndex + delta, 0, count - 1)
  }

  // Scrolling with the keys slides rows under a stationary pointer, which fires
  // their hover handlers; those must not steal the cursor from the keyboard.
  function hoverCursor(index) {
    if (Date.now() - nav.lastKeyMoveMs < 300) return
    nav.scrollOnCursor = false
    nav.cursorIndex = index
  }

  // Remember where to come back to. `mode` is passed only when leaving a list
  // that can be returned to as itself (Board, Graph).
  function pushReturn(scrollY, mode) {
    if (mode !== undefined) nav.returnMode = mode
    nav.returnCursor = nav.cursorIndex
    nav.returnScrollY = scrollY
  }

  function popReturn() {
    return { mode: nav.returnMode, cursor: nav.returnCursor, scrollY: nav.returnScrollY }
  }

  function toggleDropdown(startIndex) {
    if (nav.dropdownOpen) { nav.closeDropdown(); return }
    nav.dropdownQuery = ""
    nav.dropdownCursor = startIndex
    nav.dropdownOpen = true
  }

  function closeDropdown() {
    if (!nav.dropdownOpen) return
    nav.dropdownOpen = false
    nav.dropdownQuery = ""
  }

  function moveDropdown(delta, count) {
    if (count === 0) return
    nav.dropdownCursor = nav.clamp(nav.dropdownCursor + delta, 0, count - 1)
  }
}
