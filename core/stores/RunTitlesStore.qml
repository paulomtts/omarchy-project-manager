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

  onActiveChanged: if (titles.active) titles.needCheck()
  onProjectRootsChanged: titles.needCheck()
  onOpenRootChanged: titles.openRootMoved()
  onOpenCardMapChanged: titles.mirrorOpen()
  onRunsChanged: titles.needCheck()
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

  // The usable roots of projectRoots as keys, in registry order, each once:
  // an entry's root must be a non-empty string that does not start with "-".
  function registeredRoots() {
    var list = titles.projectRoots
    var n = list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
    var out = []
    for (var i = 0; i < n; i++) {
      var p = list[i]
      if (p === null || typeof p !== "object" || Array.isArray(p)) continue
      if (typeof p.root !== "string" || p.root === "" || p.root.charAt(0) === "-") continue
      var key = titles.rootKey(p.root)
      if (out.indexOf(key) < 0) out.push(key)
    }
    return out
  }

  // {root: [run, ...]} of the runs in `runs`, keyed by run.project.root as a
  // key; a run with no root belongs to none.
  function runsByRoot() {
    var list = Array.isArray(titles.runs) ? titles.runs : []
    var out = {}
    for (var i = 0; i < list.length; i++) {
      var key = titles.rootKey(Runs.runRoot(list[i]))
      if (key === "") continue
      if (!Runs.hasKey(out, key)) out[key] = []
      out[key].push(list[i])
    }
    return out
  }

  // The milestone, story and card ids `run` names, each a non-empty string:
  // milestone_id, story_id, card_id, the card_id of each tree story but
  // "integrate" and "bases", and the card_id of each tree subtask.
  function namedIds(run) {
    var out = []
    function add(id) { if (typeof id === "string" && id !== "") out.push(id) }
    if (run === null || typeof run !== "object") return out
    add(run.milestone_id)
    add(run.story_id)
    add(run.card_id)
    var tree = run.tree !== null && typeof run.tree === "object" ? run.tree : {}
    var stories = Array.isArray(tree.stories) ? tree.stories : []
    for (var i = 0; i < stories.length; i++) {
      var story = stories[i]
      if (story !== null && typeof story === "object" && story.card_id !== "integrate" && story.card_id !== "bases") add(story.card_id)
    }
    var subtasks = Array.isArray(tree.subtasks) ? tree.subtasks : []
    for (var j = 0; j < subtasks.length; j++) {
      var subtask = subtasks[j]
      if (subtask !== null && typeof subtask === "object") add(subtask.card_id)
    }
    return out
  }

  // The ids the runs `rootRuns` name that `map` has no own key for and
  // `asked` ({id: true}) does not hold, each once.
  function missingIds(rootRuns, map, asked) {
    var out = []
    for (var i = 0; i < rootRuns.length; i++) {
      var ids = titles.namedIds(rootRuns[i])
      for (var j = 0; j < ids.length; j++) {
        var id = ids[j]
        if (!Runs.hasKey(map, id) && !Runs.hasKey(asked, id) && out.indexOf(id) < 0) out.push(id)
      }
    }
    return out
  }

  // Queues, in registry order, every registered root other than the open
  // one that has a run in `runs`, is neither queued nor in flight, and has
  // no entry, or an ok map that lacks an id one of its runs names and that
  // was not asked about yet (those ids are then marked asked). A queued
  // root's status becomes "loading"; its map stays until the reply. Then
  // the queue launches.
  function needCheck() {
    var open = titles.openKey()
    var roots = titles.registeredRoots()
    var byRoot = titles.runsByRoot()
    var queue = titles.titleQueue.slice()
    var status = Runs.copyMap(titles.titleStatus)
    var asked = Runs.copyMap(titlesState.asked)
    var queued = false
    for (var i = 0; i < roots.length; i++) {
      var root = roots[i]
      if (root === open || !Runs.hasKey(byRoot, root)) continue
      if (root === titles.fetchingRoot || queue.indexOf(root) >= 0) continue
      var want = false
      if (!Runs.hasKey(status, root)) {
        want = true
      } else if (status[root] === "ok") {
        var map = Runs.hasKey(titles.titlesByRoot, root) ? titles.titlesByRoot[root] : {}
        var mine = Runs.hasKey(asked, root) ? asked[root] : {}
        var missing = titles.missingIds(byRoot[root], map, mine)
        if (missing.length > 0) {
          want = true
          var next = Runs.copyMap(mine)
          for (var j = 0; j < missing.length; j++) next[missing[j]] = true
          asked[root] = next
        }
      }
      if (!want) continue
      queue.push(root)
      status[root] = "loading"
      queued = true
    }
    if (queued) {
      titles.titleQueue = queue
      titles.titleStatus = status
      titlesState.asked = asked
    }
    titles.launchNext()
  }

  // Launches the head of the queue as fetchingRoot: only while active and
  // nothing is in flight.
  function launchNext() {
    if (!titles.active || titles.fetchingRoot !== "" || titles.titleQueue.length === 0) return
    var queue = titles.titleQueue.slice()
    var root = queue.shift()
    titles.titleQueue = queue
    titles.fetchingRoot = root
    titlesRunner.run([root])
  }

  // fetchingRoot's reply. Exit 0 with an {"ok": true, "titles": {...}}
  // envelope: its string titles become the root's map, its status "ok" and
  // its stale mark goes. Anything else: its status becomes "unreachable" and
  // its map goes. A root that has left the registry or become the open root
  // changes nothing. Then the queue launches and the roots are checked again.
  function replied(stdout, exitCode) {
    var root = titles.fetchingRoot
    titles.fetchingRoot = ""
    if (root !== "" && root !== titles.openKey() && titles.registeredRoots().indexOf(root) >= 0) {
      var env = exitCode === 0 ? Results.parseEnvelope(stdout) : null
      var got = env !== null && env.ok === true ? env.titles : null
      var maps = Runs.copyMap(titles.titlesByRoot)
      var status = Runs.copyMap(titles.titleStatus)
      if (got !== null && typeof got === "object" && !Array.isArray(got)) {
        maps[root] = titles.stringTitles(got)
        status[root] = "ok"
      } else {
        delete maps[root]
        status[root] = "unreachable"
      }
      titles.titlesByRoot = maps
      titles.titleStatus = status
    }
    titles.launchNext()
    titles.needCheck()
  }

  // A new map of each own key of `map` whose value is a string.
  function stringTitles(map) {
    var out = {}
    var keys = Object.keys(map)
    for (var i = 0; i < keys.length; i++) {
      var v = map[keys[i]]
      if (typeof v === "string") Object.defineProperty(out, keys[i], { value: v, enumerable: true, writable: true, configurable: true })
    }
    return out
  }

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

  // The open root moved: the previous one's mirrored map and status go (it
  // is an ordinary root from now on); the new one leaves the queue, its
  // fetch in flight is cancelled and its map mirrors openCardMap. Then the
  // queue launches and the roots are checked again.
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
    if (open !== "") {
      if (titles.titleQueue.indexOf(open) >= 0) titles.titleQueue = titles.titleQueue.filter(function(r) { return r !== open })
      if (titles.fetchingRoot === open) {
        titlesRunner.cancel()
        titles.fetchingRoot = ""
      }
      titles.mirrorOpen()
    }
    titles.launchNext()
    titles.needCheck()
  }

  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: titlesState
    property string mirrored: ""   // the root whose map mirrors openCardMap; "" when none
    property var asked: ({})       // {root: {id: true}}: missing ids already asked about
  }

  // The one board-titles.py runner. Guard "": the store tracks the root in
  // flight itself and cancels a fetch that must not land.
  HelperRunner {
    id: titlesRunner
    script: titles.backendDir + "boards/board-titles.py"
    guard: ""
    onFinished: function(stdout, exitCode) { titles.replied(stdout, exitCode) }
  }
}
