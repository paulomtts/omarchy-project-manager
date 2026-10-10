import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// The run titles: each registered project's {id: title} map, for the run
// screens to show titles in place of ids. `titlesByRoot` is
// {root: {id: title}} and `titleStatus` {root: "loading" | "ok" |
// "unreachable"}; both are replaced, never changed in place, and keyed by
// the root with its trailing "/" removed. The open project's map is
// Runs.titlesFromCards(openCardMap), its status "ok", and it is never
// fetched. Every other registered root with a run in `runs` is fetched with
// board-titles.py ROOT on `titlesRunner`, one root at a time from
// `titleQueue` (oldest first, each root once, never the root in flight,
// `fetchingRoot`) and only while `active`: when it has no entry, when its ok
// map is stale (each opening and refreshTitles() mark every ok map stale),
// or when a run names a milestone, story or card id its ok map lacks and
// that was not already asked about since the last opening or
// refreshTitles(). A queued root is "loading" and keeps its map until the
// reply. A reply that is not an ok titles object makes the root
// "unreachable" and drops its map; it is not asked again until
// refreshTitles(), the next opening or a registry change. A root that leaves
// the registry loses its entry. The backend directory, the panel-open flag,
// the registry, the open project's root and card map and the run list are
// handed to it from outside -- it never reaches for another store. App
// composes it as `app.runTitles`.
Scope {
  id: titles

  property string backendDir: ""     // <plugin>/core/backend/
  property bool active: false        // App binds this to "panel open" (app.panelOpen)
  property var projectRoots: []      // [{root, name}], the registry in its order; App binds it
  property string openRoot: ""       // the open project's root path; "" when none is open
  property var openCardMap: ({})     // the open project's {id: card}; App binds the board's cardMap
  property var runs: []              // the run store's merged run list; App binds it

  property var titlesByRoot: ({})
  property var titleStatus: ({})
  property var titleQueue: []        // the roots waiting to be fetched, oldest first
  property string fetchingRoot: ""   // the root whose fetch is in flight; "" when none is

  readonly property alias titlesRunner: titlesRunner

  onOpenRootChanged: titles.openRootMoved()
  onOpenCardMapChanged: titles.mirrorOpen()
  Component.onCompleted: titles.openRootMoved()

  // `path` with every trailing "/" removed ("/" for a path of only slashes);
  // "" when it is not a string.
  function rootKey(path) {
    if (typeof path !== "string") return ""
    var end = path.length
    while (end > 0 && path.charAt(end - 1) === "/") end--
    if (end === 0) return path === "" ? "" : "/"
    return path.substring(0, end)
  }

  // The open project's root as a key; "" when none is open.
  function openKey() { return titles.rootKey(titles.openRoot) }

  // The open project's map becomes Runs.titlesFromCards(openCardMap) and its
  // status "ok"; nothing while no project is open.
  function mirrorOpen() {
    var open = titles.openKey()
    if (open === "") return
    var maps = Runs.copyMap(titles.titlesByRoot)
    var status = Runs.copyMap(titles.titleStatus)
    maps[open] = Runs.titlesFromCards(titles.openCardMap)
    status[open] = "ok"
    titles.titlesByRoot = maps
    titles.titleStatus = status
  }

  // The open root moved: the previous one's mirrored map and status go, and
  // the new one's map mirrors openCardMap.
  function openRootMoved() {
    var open = titles.openKey()
    var prev = titlesState.mirrored
    if (prev !== "" && prev !== open) {
      var maps = Runs.copyMap(titles.titlesByRoot)
      var status = Runs.copyMap(titles.titleStatus)
      delete maps[prev]
      delete status[prev]
      titles.titlesByRoot = maps
      titles.titleStatus = status
    }
    titlesState.mirrored = open
    titles.mirrorOpen()
  }

  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: titlesState
    property string mirrored: ""   // the root whose map mirrors openCardMap; "" when none
  }

  // The one board-titles.py runner. Guard "": the store tracks the root in
  // flight itself and cancels a fetch that must not land.
  HelperRunner {
    id: titlesRunner
    script: titles.backendDir + "boards/board-titles.py"
    guard: ""
  }
}
