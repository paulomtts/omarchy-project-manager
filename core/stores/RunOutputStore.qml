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
  property int reconnects: 0          // unexpected exits counted toward the limit; 0 after a good chunk or clear()
  property real nowMs: 0              // the restart window's clock, epoch ms; 0 = Date.now()
  property var exitTimes: []          // the counted exits' times, epoch ms
  readonly property alias retryTimer: retryTimer   // the pending restart; running while one is scheduled

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

  // No key, idle, an empty buffer, no counted exits and no pending restart.
  function clear() {
    store.retryTimer.stop()
    store.followKey = null
    store.followStatus = "idle"
    store.endStatus = ""
    store.followError = ""
    store.reconnects = 0
    store.exitTimes = []
    store.setBuffer(LogStream.emptyBuffer())
  }

  // Another key: stop, clear, and start when it can be followed. The same key
  // off Run detail or with the panel closed: stop, cancel a pending restart
  // and keep the rest. The same key back with no process while connecting or
  // following: clear it once it is not live, leave a pending restart in
  // charge, else resume it from the buffer's nextOffset. A running process of
  // the same key is left alone.
  function reconcile() {
    var k = store.selectionKey(store.run, store.selection)
    if (!store.sameKey(k, store.followKey)) {
      if (store.followProc) store.stop()
      store.clear()
      if (store.canStart(k)) store.start(k, 0)
      return
    }
    if (k === null) return
    if (!store.isPresent()) {
      if (store.followProc) store.stop()
      store.retryTimer.stop()
      return
    }
    if (store.followProc) return
    var s = store.followStatus
    if (s !== "connecting" && s !== "following") return
    if (!store.isLive()) store.clear()
    else if (store.retryTimer.running) return
    else if (store.canStart(k)) store.start(k, store.buffer.nextOffset)
  }

  // runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT, plus OFFSET when offset
  // > 0. The buffer is kept: a new key reaches here only after clear().
  function start(k, offset) {
    store.retryTimer.stop()
    store.followSeq += 1
    store.followKey = k
    store.followStatus = "connecting"
    store.endStatus = ""
    store.followError = ""
    var proc = followC.createObject(store, { launchSeq: store.followSeq })
    var command = ["python3", store.backendDir + "runs/runs-logs-follow.py", store.run.repo_dir,
                   k.run_id, k.card_id, k.phase, String(k.attempt)]
    if (offset > 0) command.push(String(offset))
    proc.command = command
    store.followProc = proc
    proc.running = true
  }

  // SIGTERM and no pending restart; the stopped process's later lines and
  // exit are ignored.
  function stop() {
    store.retryTimer.stop()
    store.followSeq += 1
    if (store.followProc) store.followProc.running = false
    store.followProc = null
  }

  function isCurrentFollow(proc) {
    return proc !== null && proc === store.followProc && proc.launchSeq === store.followSeq
  }

  // One stdout line of the current process, after its end or error ignored:
  // trimmed and parsed (blank or not JSON is null), then one LogStream.foldLine.
  // A hello or a chunk replaces the buffer and is `following`; a chunk (new
  // output, not a duplicate) also resets `reconnects`. The end is
  // `ended` with am's status, and asks for a logs snapshot for a step (attempt
  // 0); an {"ok": false} line is `error` with its Runs.errorText. The buffer
  // stays on the end and on an error.
  function followLine(proc, data) {
    if (!store.isCurrentFollow(proc)) return
    if (store.followStatus === "ended" || store.followStatus === "error") return
    var text = String(data || "").trim()
    var value = null
    if (text !== "") {
      try { value = JSON.parse(text) } catch (e) { value = null }
    }
    var r = LogStream.foldLine(store.buffer, value)
    if (r.kind === "hello" || r.kind === "chunk") {
      store.setBuffer(r.buffer)
      store.followStatus = "following"
      if (r.kind === "chunk") {
        store.reconnects = 0
        store.exitTimes = []
      }
    } else if (r.kind === "end") {
      store.followStatus = "ended"
      store.endStatus = typeof value.status === "string" ? value.status : ""
      if (store.followKey.attempt === 0) store.snapshotWanted()
    } else if (r.kind === "refusal") {
      store.followStatus = "error"
      store.followError = Runs.errorText(value)
    }
  }

  // The current process exited: no process is left. While connecting or
  // following it is an unexpected exit: exits 60 s or older leave the window,
  // this one is counted in `reconnects`, and the same key restarts after 1 s,
  // 2 s, then 4 s (retryTimer); the fourth within 60 s is an error naming the
  // exit code.
  function followExited(proc, exitCode) {
    if (!store.isCurrentFollow(proc)) return
    store.followProc = null
    if (store.followStatus !== "connecting" && store.followStatus !== "following") return
    var t = store.nowMs > 0 ? store.nowMs : Date.now()
    var kept = store.exitTimes.filter(function(e) { return t - e < 60000 })
    kept.push(t)
    store.exitTimes = kept
    store.reconnects = kept.length
    if (store.reconnects <= 3) {
      store.retryTimer.interval = 1000 * Math.pow(2, store.reconnects - 1)
      store.retryTimer.start()
      return
    }
    store.followStatus = "error"
    store.followError = "Live output stopped: the helper exited with code " + exitCode
  }

  // The pending restart is due: the same key, with no process and still
  // connecting or following, resumes from nextOffset when it can be followed
  // and is cleared once it is not live; any other fire does nothing.
  function retry() {
    var k = store.selectionKey(store.run, store.selection)
    if (k === null || !store.sameKey(k, store.followKey) || store.followProc) return
    if (store.followStatus !== "connecting" && store.followStatus !== "following") return
    if (store.canStart(k)) store.start(k, store.buffer.nextOffset)
    else if (!store.isLive()) store.clear()
  }

  onActiveChanged: store.reconcile()
  onInRunDetailChanged: store.reconcile()
  onRunChanged: store.reconcile()
  onSelectionChanged: store.reconcile()
  Component.onCompleted: store.reconcile()

  Timer {
    id: retryTimer
    objectName: "retryTimer"
    repeat: false
    onTriggered: store.retry()
  }

  // One Process per follow launch, so each carries the launch it belongs to.
  Component {
    id: followC

    Process {
      id: fp
      objectName: "followProc"
      property int launchSeq: 0
      stdout: SplitParser { onRead: function(data) { store.followLine(fp, data) } }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        store.followExited(fp, exitCode)
        fp.destroy()
      }
    }
  }
}
