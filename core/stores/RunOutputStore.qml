import QtQml
import Quickshell
import Quickshell.Io
import "../domain/logStream.js" as LogStream
import "../domain/runs.js" as Runs

// Run detail's live output: runs-logs-follow.py for the one attempt or step
// the pane shows while it is in flight, its stdout folded line by line
// (LogStream.foldLine) into a bounded buffer. At most one follow process, and
// no background tails. App hands it `backendDir`, `active` (the panel is
// open), `inRunDetail` (the view mode is "run"), `run` (the selected run,
// normalized) and `selection` (RunStore's selectedAttempt), and routes
// snapshotWanted() to RunStore.refreshLogs(); it never reaches for another
// store, and the snapshot logs stay in RunStore.
//
// The followed key is {run_id, card_id, phase, attempt} (attempt 0 for a
// step). Every input change reconciles once: another key stops the process
// (latest wins), clears the state and, while the panel is open on Run detail
// and the selection is live (Runs.isLiveSelection) with a usable repo_dir,
// follows it from offset 0. Leaving Run detail or closing the panel stops the
// process and keeps the key and the buffer; coming back on the same live key
// follows it again from offset 0, unless its follow ended or failed. A key
// that stops being live keeps its process until the end line or the exit.
// The end line sets `ended` and endStatus; for a step it asks for one logs
// snapshot. An {"ok": false} line, or an exit before the end line, is an
// error. A stopped process's lines and exit are ignored.
Scope {
  id: store

  property string backendDir: ""      // <plugin>/core/backend/
  property bool active: false         // App binds this to "panel open"
  property bool inRunDetail: false    // App binds this to view mode "run"
  property var run: null              // the selected run, normalized; null when none
  property var selection: null        // RunStore's selectedAttempt; null when none

  property var followKey: null        // {run_id, card_id, phase, attempt} or null
  property string followStatus: "idle" // idle | connecting | following | ended | unsupported | error
  property string endStatus: ""       // am's end status; "" until the end line
  property string liveText: ""        // LogStream.bufferText of the buffer
  property int liveDropped: 0         // lines dropped from the buffer's front
  property bool hasOutput: false      // the buffer holds a line, a partial line or dropped lines
  property string followError: ""     // why the follow failed; "" when it has not
  property var followProc: null       // the current follow Process, or null
  property int followSeq: 0           // bumped on every start and stop: the launch guard
  property var buffer: LogStream.emptyBuffer()

  // A followed step ended: RunStore should fetch its logs snapshot.
  signal snapshotWanted()

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

  // {run_id, card_id, phase, attempt} of (run, sel), attempt 0 for a step;
  // null without a run id, a card id or a phase.
  function selectionKey(run, sel) {
    if (!store.isObject(run) || !store.isObject(sel)) return null
    if (typeof run.id !== "string" || run.id === "") return null
    if (typeof sel.card_id !== "string" || sel.card_id === "" || typeof sel.phase !== "string" || sel.phase === "") return null
    return { run_id: run.id, card_id: sel.card_id, phase: sel.phase, attempt: sel.step === true ? 0 : sel.attempt }
  }

  function sameKey(a, b) {
    if (a === null || b === null) return a === b
    return a.run_id === b.run_id && a.card_id === b.card_id && a.phase === b.phase && a.attempt === b.attempt
  }

  // The panel is open on Run detail.
  function isPresent() { return store.active && store.inRunDetail }

  function isLive() { return Runs.isLiveSelection(store.run, store.selection) }

  // k can be followed now: present, live and the run has a repo_dir.
  function canStart(k) {
    return k !== null && store.isPresent() && store.isLive()
        && typeof store.run.repo_dir === "string" && store.run.repo_dir !== ""
  }

  function setBuffer(b) {
    store.buffer = b
    store.liveText = LogStream.bufferText(b)
    store.liveDropped = b.dropped
    store.hasOutput = b.lines.length > 0 || b.partial !== "" || b.dropped > 0
  }

  function clear() {
    store.followKey = null
    store.followStatus = "idle"
    store.endStatus = ""
    store.followError = ""
    store.setBuffer(LogStream.emptyBuffer())
  }

  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (store.sameKey(k, store.followKey)) return
    if (store.followProc) store.stop()
    store.clear()
    if (store.canStart(k)) store.start(k)
  }

  // runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT, from offset 0, into a fresh buffer.
  function start(k) {
    store.followSeq += 1
    store.followKey = k
    store.setBuffer(LogStream.emptyBuffer())
    store.followStatus = "connecting"
    store.endStatus = ""
    store.followError = ""
    var proc = followC.createObject(store, { launchSeq: store.followSeq })
    proc.command = ["python3", store.backendDir + "runs/runs-logs-follow.py", store.run.repo_dir,
                    k.run_id, k.card_id, k.phase, String(k.attempt)]
    store.followProc = proc
    proc.running = true
  }

  // SIGTERM; the stopped process's later lines and exit are ignored.
  function stop() {
    store.followSeq += 1
    if (store.followProc) store.followProc.running = false
    store.followProc = null
  }

  onActiveChanged: store.reconcile()
  onInRunDetailChanged: store.reconcile()
  onRunChanged: store.reconcile()
  onSelectionChanged: store.reconcile()
  Component.onCompleted: store.reconcile()

  // One Process per follow launch, so each carries the launch it belongs to.
  Component {
    id: followC

    Process {
      id: fp
      objectName: "followProc"
      property int launchSeq: 0
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) { fp.destroy() }
    }
  }
}
