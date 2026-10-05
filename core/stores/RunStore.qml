import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run,
// the attempt the Run detail pane shows and that attempt's `am logs` snapshot
// (runs-logs.py), and whether `am` could be asked at all. Two HelperRunners
// (snapshot, attempt logs) plus, while `active` (the panel is open), a
// long-lived runs-watch.py that says which runs changed; each burst of changes
// costs one debounced snapshot. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
// Pause, resume and cancel (control()) each get a HelperRunner of their own.
// The project root and the backend directory are handed to it from outside --
// it never reaches for another store. App composes it as `app.runs` and binds
// `active` to the panel being open.
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

  // The Run detail pane (5.2): which attempt of the selected run it shows and
  // that attempt's last `am logs` snapshot. Never a live tail.
  property var selectedAttempt: null  // { card_id, phase, attempt } or null
  property string logsText: ""        // Runs.logTail of the last good reply
  property bool logsTruncated: false  // lines were cut from it
  property real logsFetchedMs: 0      // Date.now() when that reply landed; 0 before any
  property bool logsLoading: false    // a fetch is in flight
  property string logsError: ""       // why the last fetch failed; "" after a good one
  property string logsStatus: ""      // the attempt's status when its fetch was launched

  // Run controls (S2 4.1). `pending` holds the requests not yet settled,
  // {runId: action}; `stillWaiting` the pending ones 30 s or more old,
  // {runId: true}. Both are replaced, never changed in place, so bindings see
  // every change. The control error is its own pair of fields: a snapshot never
  // touches it, and the snapshot's lastError never carries a control refusal.
  property var pending: ({})
  property var stillWaiting: ({})
  readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about

  // The cancel confirmation (S2 4.3). Panel renders it; the store keeps the
  // run it asks about ("" = closed), the typed word and why the last confirm
  // was refused.
  property string cancelRunId: ""
  readonly property bool cancelOpen: store.cancelRunId !== ""
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""

  readonly property alias watching: watchState.watching   // the footer's "watching"
  readonly property alias watchProc: watchState.proc      // the current watch Process, or null
  readonly property alias snapshotRunner: snapshotRunner
  readonly property alias debounceTimer: debounceTimer
  readonly property alias livenessTimer: livenessTimer
  readonly property alias staleTimer: staleTimer
  readonly property alias pollTimer: pollTimer
  readonly property alias logsRunner: logsRunner
  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer

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
    store.clearLogs()
    store.runFilter = ""
    store.lastError = ""
    store.amStatus = "ok"
    // Control requests already launched still complete in am; their replies
    // are dropped by their runners' guard. Nothing of the old project's stays.
    store.pending = {}
    store.stillWaiting = {}
    controlState.requests = {}
    store.dismissControlError()
    store.closeCancel()
    store.flash("")
    if (store.project !== "") store.refresh()
  }

  // ---- attempt logs (5.2)

  // The run with this id in the snapshot, or null.
  function runById(id) {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }

  // Shows (and fetches) one attempt of the selected run. Another attempt than
  // the one shown starts from an empty pane -- its predecessor's text is never
  // shown under its heading. Nothing happens without a project, a selected run
  // or a real attempt (a non-empty card and phase, a number above 0).
  function selectAttempt(cardId, phase, attempt) {
    if (store.project === "" || store.selectedRunId === "") return
    if (typeof cardId !== "string" || cardId === "" || typeof phase !== "string" || phase === "") return
    if (typeof attempt !== "number" || !isFinite(attempt) || attempt <= 0) return
    var old = store.selectedAttempt
    if (!old || old.card_id !== cardId || old.phase !== phase || old.attempt !== attempt) {
      store.logsText = ""
      store.logsTruncated = false
      store.logsFetchedMs = 0
      store.logsError = ""
    }
    store.selectedAttempt = { card_id: cardId, phase: phase, attempt: attempt }
    store.fetchLogs()
  }

  // The Refresh button: the same attempt again; the text stays until the reply.
  function refreshLogs() {
    store.fetchLogs()
  }

  // One runs-logs.py launch for the current selection, remembering the status
  // it was launched for (a snapshot that changes it fetches again).
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.project === "" || store.selectedRunId === "" || !sel) return
    store.logsStatus = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }

  // No selection and no logs; a fetch in flight is stopped and its reply dropped.
  function clearLogs() {
    logsRunner.cancel()
    store.selectedAttempt = null
    store.logsText = ""
    store.logsTruncated = false
    store.logsFetchedMs = 0
    store.logsLoading = false
    store.logsError = ""
    store.logsStatus = ""
  }

  // The selected run's default attempt, when it has one.
  function openDefaultAttempt() {
    var d = Runs.defaultAttempt(store.runById(store.selectedRunId))
    if (d) store.selectAttempt(d.card_id, d.phase, d.attempt)
  }

  // After every applied snapshot: a selected run with no attempt yet gets its
  // default once one exists; otherwise the selected attempt is fetched again
  // only when its status moved since its fetch was launched. Nothing else
  // fetches logs on its own.
  function logsAfterSnapshot() {
    if (store.selectedRunId === "") return
    var sel = store.selectedAttempt
    if (!sel) {
      store.openDefaultAttempt()
      return
    }
    var status = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    if (status !== store.logsStatus) store.fetchLogs()
  }

  // Another run (or none): the pane starts over on that run's default attempt.
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
  }

  // One logs reply. ok:true replaces the text with its last 200 lines; any
  // failure keeps the text and only says why. Never touches amStatus, runs or
  // lastError: those belong to the snapshot. A reply for a project the user
  // has left, or for an older fetch, never gets here (the runner's guards).
  function applyLogs(stdout, exitCode) {
    store.logsLoading = false
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var tail = Runs.logTail(envelope.data, 200)
      store.logsText = tail.text
      store.logsTruncated = tail.truncated
      store.logsFetchedMs = Date.now()
      store.logsError = ""
      return
    }
    if (envelope !== null && envelope.ok === false) {
      store.logsError = Runs.errorText(envelope)
      return
    }
    store.logsError = "The logs snapshot gave no usable result (exit " + exitCode + ")."
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
      store.settleAfterSnapshot()
      store.logsAfterSnapshot()
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

  // ---- run controls (S2 4.1)

  // A copy of a {key: value} map, so a change is a new object.
  function copyMap(map) {
    var out = {}
    for (var key in map) {
      if (Object.prototype.hasOwnProperty.call(map, key)) out[key] = map[key]
    }
    return out
  }

  function hasKey(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key)
  }

  // Starts a pause, resume or cancel of one run of this project and returns
  // whether it started. Refused: no project, an unknown action, a run that is
  // not in the snapshot, an action Runs.controls says is disabled, or a run
  // that already has a request pending. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (store.project === "") return false
    if (action !== "pause" && action !== "resume" && action !== "cancel") return false
    if (typeof runId !== "string" || runId === "") return false
    var run = store.runById(runId)
    if (run === null) return false
    if (!Runs.controls(run)[action].enabled) return false
    if (store.hasKey(store.pending, runId)) return false
    store.dismissControlError()
    controlState.nextToken += 1
    var requests = store.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = store.copyMap(store.pending)
    p[runId] = action
    store.pending = p
    var runner = controlC.createObject(store, { runId: runId, action: action,
                                                token: controlState.nextToken, madeFor: store.project })
    controlState.runners = controlState.runners.concat([runner])
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses the project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", store.project])
    } else {
      store.launchControl(runner, [])
    }
    return true
  }

  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // then `extra` (a resume's verify arguments).
  function launchControl(runner, extra) {
    runner.script = store.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, store.project].concat(extra))
  }

  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled, emptied by a project switch
  // or replaced by a newer request.
  function requestOf(runner) {
    if (!store.hasKey(controlState.requests, runner.runId)) return null
    var req = controlState.requests[runner.runId]
    return req.token === runner.token ? req : null
  }

  // The request for runId is over: its pending entry, its still-waiting mark
  // and its bookkeeping go.
  function settle(runId) {
    if (store.hasKey(store.pending, runId)) {
      var p = store.copyMap(store.pending)
      delete p[runId]
      store.pending = p
    }
    if (store.hasKey(store.stillWaiting, runId)) {
      var w = store.copyMap(store.stillWaiting)
      delete w[runId]
      store.stillWaiting = w
    }
    if (store.hasKey(controlState.requests, runId)) {
      var r = store.copyMap(controlState.requests)
      delete r[runId]
      controlState.requests = r
    }
  }

  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run.
  function failControl(runId, sentence) {
    store.settle(runId)
    store.lastControlError = sentence
    store.lastControlErrorRunId = runId
  }

  function dismissControlError() {
    store.lastControlError = ""
    store.lastControlErrorRunId = ""
  }

  // A runner's request is over: it leaves controlRunners and is destroyed.
  function dropRunner(runner) {
    controlState.runners = controlState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // One run-control.py reply, for the project the request was made in. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence. Either way the runs are fetched again. A reply for a request that
  // is no longer the pending one changes nothing.
  function controlReplied(runner, stdout, exitCode) {
    var req = store.requestOf(runner)
    if (req === null) {
      store.dropRunner(runner)
      return
    }
    if (runner.settingsStep) {
      runner.settingsStep = false
      store.resumeWithSettings(runner, stdout, exitCode)
      return
    }
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var data = envelope.data
      var requestedAt = data !== null && typeof data === "object" && typeof data.requested_at === "string" ? data.requested_at : ""
      var requests = store.copyMap(controlState.requests)
      requests[runner.runId] = { token: req.token, action: req.action, baseline: req.baseline,
                                 launchedMs: req.launchedMs, acknowledged: true, requestedAt: requestedAt }
      controlState.requests = requests
    } else if (envelope !== null && envelope.ok === false) {
      store.failControl(runner.runId, Runs.controlError(envelope))
    } else {
      store.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").")
    }
    store.dropRunner(runner)
    store.refresh()
  }

  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification; with
  // neither, or no readable reply, run-control is never launched and the
  // request ends with a sentence -- no re-snapshot, nothing was asked of am.
  function resumeWithSettings(runner, stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    if (settings === null) {
      store.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").")
      store.dropRunner(runner)
      return
    }
    var verify = Array.isArray(settings.verify) ? settings.verify : []
    var usable = verify.length > 0
    for (var i = 0; i < verify.length; i++) {
      if (typeof verify[i] !== "string") usable = false
    }
    if (usable) {
      var extra = []
      for (var j = 0; j < verify.length; j++) extra.push("--verify", verify[j])
      store.launchControl(runner, extra)
    } else if (settings.allowNoVerification === true) {
      store.launchControl(runner, ["--allow-no-verification"])
    } else {
      store.failControl(runner.runId, "Resume needs verify commands: none are stored for this project, and running without verification was not chosen.")
      store.dropRunner(runner)
    }
  }

  // After every good snapshot: an acknowledged request is settled when its run
  // is gone, when the run's state moved since the request started, or (pause,
  // cancel) when am marks its request handled. A request still in flight is
  // never settled by a snapshot: its buttons stay off until the reply.
  function settleAfterSnapshot() {
    var ids = Object.keys(store.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (!store.hasKey(controlState.requests, id)) continue
      var req = controlState.requests[id]
      if (!req.acknowledged) continue
      var run = store.runById(id)
      if (run === null || Runs.runState(run) !== req.baseline
          || (req.action !== "resume" && store.isHandled(run, req))) store.settle(id)
    }
  }

  // The run's am request row for this request has a handled_at: the row with
  // the requested_at am's reply gave, else the last row of the same command.
  function isHandled(run, req) {
    var list = Array.isArray(run.requests) ? run.requests : []
    var match = null
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (req.requestedAt !== "" ? row.requested_at === req.requestedAt : row.command === req.action) match = row
    }
    return match !== null && match.handled_at !== ""
  }

  // Marks the pending requests launched 30 s or more before nowMs (the timer
  // passes Date.now()); the UI shows stillWaitingText for them.
  function checkWaiting(nowMs) {
    var out = {}
    var ids = Object.keys(store.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (store.hasKey(controlState.requests, id) && nowMs - controlState.requests[id].launchedMs >= 30000) out[id] = true
    }
    store.stillWaiting = out
  }

  // ---- cancel confirmation and the footer flash (S2 4.3)

  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in the snapshot (or no project), then a request already
  // pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = store.project === "" || typeof runId !== "string" || runId === "" ? null : store.runById(runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (store.hasKey(store.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action].reason
  }

  // Shows text in the footers for 3 s; a new flash replaces it and restarts
  // the clock, flash("") clears it.
  function flash(text) {
    store.flashText = String(text || "")
    if (store.flashText === "") flashTimer.stop()
    else flashTimer.restart()
  }

  // Opens the cancel confirmation for a run that can be cancelled now;
  // otherwise flashes why not and leaves any dialog as it is.
  function openCancel(runId) {
    var reason = store.refusalOf("cancel", runId)
    if (reason !== "") {
      store.flash(reason)
      return false
    }
    store.cancelText = ""
    store.cancelError = ""
    store.cancelRunId = runId
    return true
  }

  function closeCancel() {
    store.cancelRunId = ""
    store.cancelText = ""
    store.cancelError = ""
  }

  // The dialog's confirm. The typed word is checked again here (the dialog
  // gates it too), then the run is checked again: one that changed under the
  // open dialog keeps it open with the reason. A started cancel closes it.
  function confirmCancel() {
    if (store.cancelRunId === "") return false
    if (String(store.cancelText).trim().toLowerCase() !== "cancel") return false
    var reason = store.refusalOf("cancel", store.cancelRunId)
    if (reason !== "") {
      store.cancelError = reason
      return false
    }
    if (!store.control("cancel", store.cancelRunId)) {
      store.cancelError = "The run could not be cancelled"
      return false
    }
    store.closeCancel()
    return true
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

  // The attempt-logs helper. Guarded by the project like the snapshot, so a
  // reply for a project the user has left is dropped; a newer fetch (another
  // attempt, a Refresh) wins over an older one. No onGuardChanged here: the
  // snapshot runner's already runs projectSwitched() once per switch.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.applyLogs(stdout, exitCode) }
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

  // Only while the panel is open and a control request is pending: closing the
  // panel keeps `pending` but leaves no timer running.
  Timer {
    id: pendingTimer
    objectName: "pendingTimer"
    interval: 1000
    repeat: true
    running: store.active && Object.keys(store.pending).length > 0
    onTriggered: store.checkWaiting(Date.now())
  }

  // Clears the footer flash 3 s after the last flash().
  Timer {
    id: flashTimer
    objectName: "flashTimer"
    interval: 3000
    repeat: false
    onTriggered: store.flashText = ""
  }

  // What the watch Process aliases read; kept apart so consumers cannot write it.
  QtObject {
    id: watchState
    property var proc: null
    property bool watching: false
  }

  // The control requests' own state; kept apart so consumers cannot write it.
  // `requests` is {runId: {token, action, baseline, launchedMs, acknowledged,
  // requestedAt}}: the run's state when the request started, when it started,
  // whether am acknowledged it, and the requested_at am gave it.
  QtObject {
    id: controlState
    property var runners: []
    property var requests: ({})
    property int nextToken: 0
  }

  // One HelperRunner per control request, so requests for different runs never
  // stop each other. Guarded by the project like the others: a reply for a
  // project the user has left is dropped, and its runner goes when its process
  // exits (the runner clears `busy` on that exit but emits no `finished`). No
  // onGuardChanged: the snapshot runner's already runs projectSwitched(). A
  // milestone resume uses its runner twice: viewer-state.py, then run-control.py.
  Component {
    id: controlC

    HelperRunner {
      id: cr
      property string runId: ""
      property string action: ""
      property int token: 0
      property string madeFor: ""         // the project the request was made in
      property bool settingsStep: false   // reading the run settings; run-control comes next
      guard: store.project
      onFinished: function(stdout, exitCode) { store.controlReplied(cr, stdout, exitCode) }
      onBusyChanged: if (!cr.busy && cr.guard !== cr.madeFor) store.dropRunner(cr)
    }
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
