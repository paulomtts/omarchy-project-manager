import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run
// and whether `am` could be asked at all. While `active` (the panel is open) a
// long-lived runs-watch.py says which runs changed, and each burst of changes
// costs one debounced snapshot. The project root and the backend directory are
// handed to it from outside -- it never reaches for another store. App
// composes it as `app.runs` and binds `active` to the panel being open.
Scope {
  id: store

  property string project: ""         // project root path
  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open" (app.panelOpen)

  property var runs: []               // Runs.normalizeRun output, am's order
  property string selectedRunId: ""   // set by the UI
  property string amStatus: "ok"      // "ok" | "missing" | "schema" | "error"
  property string lastError: ""
  property bool stale: false          // the last good snapshot is over 30 s old while active
  property string watchWarning: ""    // the corrupt-journal chip; "" when there is none

  // The Runs screen's chip ("" means All, else "attention" | "live" | "parked")
  // and search text. App binds searchQuery to the navigation store; the chip
  // survives a section switch and is reset by a project switch.
  property string runFilter: ""
  property string searchQuery: ""
  // The chip changed: a different list, so the cursor goes home (App's job).
  signal runFilterToggled()
  // The one filtered list: the screen's rows and the navigator's cursor list.
  readonly property var filteredRuns: Runs.searchRuns(Runs.filterRuns(store.runs, store.runFilter), store.searchQuery)

  // A watch has been started since the last activation or project switch:
  // later snapshots never start another (the helper picks up the project's new
  // runs itself), and a watch that ended is not restarted until the next
  // activation or project switch.
  property bool watchTried: false
  property int watchSeq: 0            // bumped on every watch start and stop: the launch guard
  property string watchSchemaError: "" // the schema banner text while its fallback poll runs

  readonly property alias watching: watchState.watching   // the footer's "watching"
  readonly property alias watchProc: watchState.proc      // the current watch Process, or null
  readonly property alias snapshotRunner: snapshotRunner
  readonly property alias debounceTimer: debounceTimer
  readonly property alias livenessTimer: livenessTimer
  readonly property alias staleTimer: staleTimer
  readonly property alias pollTimer: pollTimer

  // Some run is started with a live lease: its heartbeat must be re-read even
  // when the journal is quiet.
  readonly property bool hasRunningRun: {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (Runs.runState(list[i]) === "running") return true
    }
    return false
  }

  // Asks for a fresh snapshot of the current project. A newer call replaces an
  // older one (the runner's latest-wins rule).
  function refresh() {
    if (store.project === "") return
    snapshotRunner.run([store.project])
  }

  // A chip was chosen: the All chip, or the active one again, means All.
  function toggleRunFilter(id) {
    store.runFilter = id === "all" || id === store.runFilter ? "" : String(id || "")
    store.runFilterToggled()
  }

  onActiveChanged: {
    if (store.active) store.startLive()
    else store.stopLive()
  }

  // The panel opened: fetch now; the first good snapshot starts the watch, and
  // the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.restartStale()
    store.refresh()
  }

  // The panel closed: no process and no timer is left running. The runs, the
  // selection and amStatus stay for the next opening.
  function stopLive() {
    store.stopWatch()
    debounceTimer.stop()
    store.stopPoll()
    staleTimer.stop()
    store.stale = false
    store.watchWarning = ""
  }

  // Nothing is stale yet; the 30 s clock starts again while there is something
  // to watch.
  function restartStale() {
    store.stale = false
    if (store.active && store.project !== "") staleTimer.restart()
    else staleTimer.stop()
  }

  function stopWatch() {
    store.watchSeq += 1
    if (watchState.proc) watchState.proc.running = false
    watchState.watching = false
  }

  // runs-watch.py for this project and the runs the snapshot just listed, in
  // its order. Long-lived, so a plain Process rather than the HelperRunner.
  function startWatch() {
    store.watchSeq += 1
    store.watchTried = true
    var ids = []
    for (var i = 0; i < store.runs.length; i++) {
      var id = store.runs[i].id
      if (typeof id === "string" && id !== "") ids.push(id)
    }
    var proc = watchC.createObject(store, { launchSeq: store.watchSeq, launchProject: store.project })
    proc.command = ["python3", store.backendDir + "runs/runs-watch.py", store.project].concat(ids)
    watchState.proc = proc
    watchState.watching = true
    proc.running = true
  }

  // A line or exit counts only from the newest launch, for the project it was
  // launched for: a watch that was stopped (project switch, panel closed) may
  // still print or exit late.
  function isCurrentWatch(proc) {
    return proc.launchSeq === store.watchSeq && proc.launchProject === store.project
  }

  // One stdout line of the watch. {"changed": [...]} (re)starts the debounce;
  // anything else -- blank, not JSON, not an object -- is ignored. Never throws.
  function watchLine(proc, data) {
    if (!store.isCurrentWatch(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (Array.isArray(value.changed)) debounceTimer.restart()
    else if (value.ok === false) proc.envelope = value
  }

  // The watch ended. Exit 0: it was stopped (by us, or because am exited).
  // Otherwise the last envelope line it printed says why: a journal the helper
  // cannot read switches to the 5 s poll; anything else is reported and the
  // watch stays off until the next activation or project switch.
  function watchExited(proc, exitCode) {
    if (!store.isCurrentWatch(proc)) return
    watchState.watching = false
    if (exitCode === 0) return
    var envelope = proc.envelope
    var err = envelope ? envelope.error : null
    var type = err !== null && typeof err === "object" ? err.type : ""
    if (type === "SchemaMismatch") {
      store.watchSchemaError = Runs.errorText(envelope)
      store.amStatus = "schema"
      store.lastError = store.watchSchemaError
      store.startPoll()
    } else if (type === "CorruptJournal") {
      store.watchWarning = Runs.errorText(envelope)
      store.startPoll()
    } else {
      store.lastError = envelope ? Runs.errorText(envelope) : "The runs watch stopped (exit " + exitCode + ")."
    }
  }

  // The poll replaces the watch signal until the panel closes or the project
  // changes.
  function startPoll() {
    pollTimer.start()
  }

  function stopPoll() {
    pollTimer.stop()
    store.watchSchemaError = ""
  }

  // A different project: nothing the old one left behind may show, and its
  // runs are fetched straight away.
  function projectSwitched() {
    store.stopWatch()
    store.watchTried = false
    debounceTimer.stop()
    store.stopPoll()
    store.watchWarning = ""
    store.restartStale()
    store.runs = []
    store.selectedRunId = ""
    store.runFilter = ""
    store.lastError = ""
    store.amStatus = "ok"
    if (store.project !== "") store.refresh()
  }

  // The helper prints exactly one JSON line; anything before it (a warning) and
  // blank lines after it are ignored.
  function lastLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line !== "") return line
    }
    return ""
  }

  // The reply's envelope object, or null when there is none to read.
  function parseEnvelope(text) {
    var line = store.lastLine(text)
    if (line === "") return null
    var value = null
    try { value = JSON.parse(line) } catch (e) { return null }
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null
  }

  // The `am runs` summary without its `status` key: the helper replaced the
  // summary's status string with the `am status` object, which normalizeRun
  // must never read as the row's status ("[object Object]").
  function rowOf(entry) {
    var row = {}
    for (var key in entry) {
      if (key !== "status" && Object.prototype.hasOwnProperty.call(entry, key)) row[key] = entry[key]
    }
    return row
  }

  // One snapshot reply. ok:true replaces the runs (none at all is fine).
  // AmMissing empties them: no badges while am is not there. Any other failure
  // -- an ok:false envelope or output that is not one -- keeps what the last
  // good snapshot said and only reports why this one failed. Never throws.
  // A reply for a project the user has left never gets here: the runner only
  // emits `finished` when the launch guard still equals its (project) guard.
  function applySnapshot(stdout, exitCode) {
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var list = Array.isArray(envelope.runs) ? envelope.runs : []
      var out = []
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e === null || typeof e !== "object" || Array.isArray(e)) continue
        out.push(Runs.normalizeRun({ row: store.rowOf(e), status: e.status }))
      }
      store.runs = out
      if (pollTimer.running && store.watchSchemaError !== "") {
        // The watch's schema banner outlives the polling snapshots.
        store.amStatus = "schema"
        store.lastError = store.watchSchemaError
      } else {
        store.amStatus = "ok"
        store.lastError = ""
      }
      store.stale = false
      if (store.active) {
        staleTimer.restart()
        if (!store.watchTried) store.startWatch()
      }
      return
    }
    if (envelope !== null && envelope.ok === false) {
      var err = envelope.error
      var type = err !== null && typeof err === "object" ? err.type : ""
      store.lastError = Runs.errorText(envelope)
      if (type === "AmMissing") {
        store.runs = []
        store.amStatus = "missing"
      } else {
        store.amStatus = "error"
      }
      return
    }
    store.amStatus = "error"
    store.lastError = "The runs snapshot gave no usable result (exit " + exitCode + ")."
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
    onFinished: function(stdout, exitCode) { store.applySnapshot(stdout, exitCode) }
  }

  // A burst of changed lines costs one snapshot.
  Timer {
    id: debounceTimer
    objectName: "debounceTimer"
    interval: 250
    repeat: false
    onTriggered: store.refresh()
  }

  // Only while the panel is open and a run is running: no timer while idle.
  Timer {
    id: livenessTimer
    objectName: "livenessTimer"
    interval: 10000
    repeat: true
    running: store.active && store.hasRunningRun
    onTriggered: store.refresh()
  }

  // Fires 30 s after the last good snapshot (or the activation) while open.
  Timer {
    id: staleTimer
    objectName: "staleTimer"
    interval: 30000
    repeat: false
    onTriggered: store.stale = true
  }

  // Replaces the watch when it cannot read am's journal (schema or corrupt).
  Timer {
    id: pollTimer
    objectName: "pollTimer"
    interval: 5000
    repeat: true
    onTriggered: store.refresh()
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
  QtObject {
    id: watchState
    property var proc: null
    property bool watching: false
  }

  // One Process per watch launch, so each carries what it was launched with.
  Component {
    id: watchC

    Process {
      id: wp
      objectName: "watchProc"
      property int launchSeq: 0
      property string launchProject: ""
      property var envelope: null       // the last {"ok": false, ...} line it printed
      stdout: SplitParser { onRead: function(data) { store.watchLine(wp, data) } }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        store.watchExited(wp, exitCode)
        wp.destroy()
      }
    }
  }
}
