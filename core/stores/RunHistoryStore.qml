import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// The older runs: each snapshot root's history, a page at a time.
// `historyByProject` is {root: {runs, more, loading, error}}, keyed by the
// root exactly as `snapshotByProject` keys it, replaced, never changed in
// place, each entry a new object whenever it changes; a root has an entry
// from its first launched showOlder until its pages are dropped.
// showOlder(root) runs runs-history.py ROOT --before CURSOR --status
// S1,S2,... [--since ISO] on runnerFor(root), only while `active`, for a
// root `snapshotByProject` has, with a non-empty
// Runs.historyStatuses(runFilter, finishedState) and a non-empty cursor:
// Runs.historyCursor over the root's snapshot and history runs. --since is
// local midnight for finishedAge "today", now minus 7 days for "week", and
// absent otherwise. Latest wins per root; roots page independently. An ok
// page appends its runs, built like the snapshot's, minus every id the
// root's snapshot or history lists, and sets `more`; any other reply keeps
// `runs` and `more` and sets `error`. A snapshot change drops the pages of
// every root it removes, moves a terminal run that leaves the snapshot of a
// root with history to the front of that history, and takes out of the
// history every run the snapshot lists; it never fetches. A changed query
// (status list or finishedAge) and the panel closing drop every root's
// pages. Dropping cancels the root's fetch in flight. No signal: history is
// never compared for alerts. The backend directory, the panel-open flag,
// the snapshot and the filter values are handed to it from outside -- it
// never reaches for another store. App composes it as `app.runHistory`.
Scope {
  id: history

  property string backendDir: ""        // <plugin>/core/backend/
  property bool active: false           // App binds this to "panel open" (app.panelOpen)
  property var snapshotByProject: ({})  // {root: [run]}, the run store's runsByProject; App binds it
  property string runFilter: ""         // the Runs chip; App binds the run store's runFilter
  property string finishedState: ""     // "done" | "escalated" | "cancelled"; anything else is every finished state
  property string finishedAge: "all"    // "today" | "week"; anything else is all time

  property var historyByProject: ({})   // {root: {runs, more, loading, error}}

  // The HelperRunner that serves `root`; null when there is none.
  function runnerFor(root) {
    return Runs.hasKey(historyState.runners, root) ? historyState.runners[root] : null
  }

  // Whether `root` is an own key of snapshotByProject.
  function isSnapshotRoot(root) {
    return typeof root === "string" && Runs.hasKey(history.snapshotByProject, root)
  }

  // The snapshot root's run list; [] for any other root or a list that is not an array.
  function snapshotOf(root) {
    var list = history.isSnapshotRoot(root) ? history.snapshotByProject[root] : null
    return Array.isArray(list) ? list : []
  }

  // The root's history runs; [] when it has no entry.
  function historyOf(root) {
    return Runs.hasKey(history.historyByProject, root) ? history.historyByProject[root].runs : []
  }

  // `root` as run.project.root holds it: its trailing "/" removed.
  function runRootOf(root) {
    return Runs.withProject({}, root, "").project.root
  }

  // The --since value of finishedAge at `nowMs`: local midnight for "today",
  // nowMs minus 7 days for "week", both as toISOString(); "" otherwise.
  function sinceOf(nowMs) {
    if (history.finishedAge === "week") return new Date(nowMs - 7 * 24 * 3600 * 1000).toISOString()
    if (history.finishedAge !== "today") return ""
    var midnight = new Date(nowMs)
    midnight.setHours(0, 0, 0, 0)
    return midnight.toISOString()
  }

  // historyByProject with root's entry replaced by `entry`.
  function setEntry(root, entry) {
    var map = Runs.copyMap(history.historyByProject)
    map[root] = entry
    history.historyByProject = map
  }

  // A new runner for `root`, kept as runnerFor(root).
  function makeRunner(root) {
    var runner = runnerC.createObject(history)
    var runners = Runs.copyMap(historyState.runners)
    runners[root] = runner
    historyState.runners = runners
    return runner
  }

  // Fetches one older page of `root` (see the header). The root's entry
  // keeps its runs and `more`, and becomes loading with no error; a fetch of
  // this root still in flight is superseded.
  function showOlder(root) {
    if (!history.active || !history.isSnapshotRoot(root)) return
    var statuses = Runs.historyStatuses(history.runFilter, history.finishedState)
    if (statuses.length === 0) return
    var cursor = Runs.historyCursor(history.snapshotOf(root).concat(history.historyOf(root)), history.runRootOf(root))
    if (cursor === "") return
    var args = [root, "--before", cursor, "--status", statuses.join(",")]
    var since = history.sinceOf(Date.now())
    if (since !== "") args.push("--since", since)
    var entry = Runs.hasKey(history.historyByProject, root) ? history.historyByProject[root] : { runs: [], more: false }
    history.setEntry(root, { runs: entry.runs, more: entry.more, loading: true, error: "" })
    var runner = history.runnerFor(root)
    if (runner === null) runner = history.makeRunner(root)
    runner.run(args)
  }

  // Bookkeeping kept apart so consumers cannot write it.
  QtObject {
    id: historyState
    property var runners: ({})   // {root: HelperRunner}, made on each root's first launch
  }

  // One runs-history.py runner per root. Guard "": the store cancels a
  // fetch that must not land.
  Component {
    id: runnerC
    HelperRunner {
      script: history.backendDir + "runs/runs-history.py"
    }
  }
}
