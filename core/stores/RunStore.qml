import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run
// and whether `am` could be asked at all. The project root and the backend
// directory are handed to it from outside -- it never reaches for another
// store. The live watch (3.2) and composing it into App (3.3) come later.
Scope {
  id: store

  property string project: ""         // project root path
  property string backendDir: ""      // <plugin>/core/backend/

  property var runs: []               // Runs.normalizeRun output, am's order
  property string selectedRunId: ""   // set by the UI
  property string amStatus: "ok"      // "ok" | "missing" | "schema" | "error"
  property string lastError: ""

  readonly property alias snapshotRunner: snapshotRunner

  // Asks for a fresh snapshot of the current project. A newer call replaces an
  // older one (the runner's latest-wins rule).
  function refresh() {
    if (store.project === "") return
    snapshotRunner.run([store.project])
  }

  // A different project: nothing the old one left behind may show, and its
  // runs are fetched straight away.
  function projectSwitched() {
    store.runs = []
    store.selectedRunId = ""
    store.lastError = ""
    store.amStatus = "ok"
    if (store.project !== "") store.refresh()
  }

  // The guard is the project root, so a snapshot launched for a project the
  // user has since left is dropped. The project-change reaction hangs off the
  // guard, not off `project`: the guard has already followed the project by the
  // time it changes, so the snapshot launched here is always guarded by the NEW
  // project (QML does not order a binding against a sibling change handler).
  HelperRunner {
    id: snapshotRunner
    script: store.backendDir + "runs/runs-snapshot.py"
    guard: store.project
    onGuardChanged: store.projectSwitched()
  }
}
