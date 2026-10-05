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

  // Alerts (S2 4.4): a toast for every run that newly needs a human while the
  // panel is open. `alertsArmed` says the current `runs` may be compared
  // against: the first good snapshot after an opening, a project switch or an
  // am-missing spell only arms, so history is never replayed. `toasts` is
  // {key, id, title, state, reason, expiresMs}, oldest first, at most 3, and
  // is replaced, never changed in place.
  property bool alertsArmed: false
  property var toasts: []
  property int toastMs: 8000
  // "Notify on escalation", per project and off by default: the switch's
  // value, the last value read from or written to viewer-state.py, and
  // whether the user changed it since the project was selected (a late load
  // reply then changes nothing).
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // The current project's last get-run-settings object, as it was read: {}
  // until its reply, when the reply is unreadable, and after a project switch.
  // The dispatch form starts from it.
  property var runSettings: ({})

  // Dispatch (S3 3.1): starting an am run. The UI opens it for a target
  // (openDispatch), edits the form (setDispatchField) and presses Start
  // (dispatchStart); the store checks the form, previews it with
  // dispatch-preview.py and starts it with start-run.py. `dispatchState` is
  // idle | previewing | ready | refused | starting | started | failed. Every
  // object here is replaced, never changed in place.
  property string dispatchState: "idle"
  property var dispatchTarget: null     // Runs.dispatchPlan of the opened target; null while idle
  property var dispatchForm: null       // {base, prefix, verify, parallelism, allowNoVerification}; null while idle
  property var dispatchPreview: null    // Runs.previewSummary of the latest good preview
  property string dispatchError: ""     // the sentence for refused / failed
  property string dispatchErrorType: "" // am's or the helper's error.type, "Form", "Target" or ""
  property var dispatchErrors: []       // Runs.validateDispatch errors of a form refusal
  property var dispatchSuggest: null    // a refused story's milestone {id, title}
  property string dispatchRunId: ""     // the started run's id; "" when none (yet)
  property string dispatchMessage: ""   // start-run.py's message after a start
  property string dispatchLog: ""       // a failed start's log path
  property string dispatchLogTail: ""   // the end of that log
  property var dispatchExitCode: null   // a failed start's exit code, when a number
  // A start for the current project went: the run id, or null while am does
  // not list it yet.
  signal dispatchStarted(var runId)

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
  readonly property alias toastTimer: toastTimer
  readonly property alias settingsLoadRunner: settingsLoadRunner
  readonly property alias settingsSaveRunner: settingsSaveRunner
  readonly property alias notifyRunners: notifyState.runners    // in-flight notify.py launches, oldest first
  readonly property alias dispatchDefaultsRunner: dispatchDefaultsRunner
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchDebounceTimer: dispatchDebounceTimer
  readonly property alias dispatchStartRunners: dispatchBook.runners // in-flight start runners, oldest first

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

  // The panel opened: fetch now; the first good snapshot starts the watch and
  // arms the alerts, and the stale clock counts from now.
  function startLive() {
    store.watchTried = false
    store.alertsArmed = false
    store.restartStale()
    store.refresh()
  }

  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // runs, the selection and amStatus stay for the next opening.
  function stopLive() {
    store.stopWatch()
    debounceTimer.stop()
    store.stopPoll()
    staleTimer.stop()
    store.stale = false
    store.watchWarning = ""
    store.alertsArmed = false
    store.toasts = []
    // A start in flight refuses and lands normally.
    store.closeDispatch()
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
    store.alertsArmed = false
    store.toasts = []
    // The switch reads off until this project's own reply. Notifications
    // already launched still run.
    store.notifyOnEscalation = false
    store.notifySaved = false
    store.notifyTouched = false
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    settingsLoadRunner.guard = store.project
    if (store.project !== "") {
      store.refresh()
      settingsLoadRunner.run(["get-run-settings", store.project])
    }
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
      // Compared before the runs are replaced; raised below only while open.
      var alerts = Runs.newAlerts(store.alertsArmed ? store.runs : null, out)
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
        store.raiseAlerts(alerts)
        store.alertsArmed = true
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
        // Comparing the next good snapshot against [] would alert every
        // escalated run again.
        store.alertsArmed = false
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

  // ---- alerts (S2 4.4)

  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. With the setting on, each alert also notifies.
  // Called from applySnapshot only while active.
  function raiseAlerts(alerts) {
    var list = Array.isArray(alerts) ? alerts : []
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      toastState.nextKey += 1
      var next = store.toasts.filter(function(t) { return t.id !== a.id })
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  expiresMs: Date.now() + store.toastMs })
      while (next.length > 3) next.shift()
      store.toasts = next
      if (store.notifyOnEscalation) store.notify(a)
    }
  }

  // Drops every toast whose time is up at nowMs (the timer passes Date.now()).
  function expireToasts(nowMs) {
    var next = store.toasts.filter(function(t) { return t.expiresMs > nowMs })
    if (next.length !== store.toasts.length) store.toasts = next
  }

  // The toast with this key goes; an unknown key changes nothing.
  function dismissToast(key) {
    var next = store.toasts.filter(function(t) { return t.key !== key })
    if (next.length !== store.toasts.length) store.toasts = next
  }

  function dismissAllToasts() {
    if (store.toasts.length > 0) store.toasts = []
  }

  // One notify.py launch for an alert, on a runner of its own so two never
  // stop each other. The reply is not read: a failed or skipped notification
  // changes nothing here.
  function notify(alert) {
    var runner = notifyC.createObject(store)
    notifyState.runners = notifyState.runners.concat([runner])
    runner.run([String(alert.title), String(alert.reason)])
  }

  function dropNotifyRunner(runner) {
    notifyState.runners = notifyState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // The switch changed: shown at once, written in the background. Refused
  // (false, nothing changes) without a project.
  function setNotifyOnEscalation(on) {
    if (store.project === "") return false
    var value = !!on
    store.notifyOnEscalation = value
    store.notifyTouched = true
    settingsSaveRunner.sent = value
    settingsSaveRunner.run(["set-run-settings", store.project, JSON.stringify({ notifyOnEscalation: value })])
    return true
  }

  // get-run-settings: one bare object, kept whole as runSettings ({} when
  // unreadable) on every reply. Only a real true turns the switch on; an
  // unreadable reply leaves it off. Too late for the switch once the user
  // changed it.
  function applyRunSettings(stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    store.runSettings = settings !== null ? settings : {}
    if (store.notifyTouched) return
    var on = settings !== null && settings.notifyOnEscalation === true
    store.notifyOnEscalation = on
    store.notifySaved = on
  }

  // set-run-settings: {"ok": true} means `sent` is stored; anything else puts
  // the switch back to what is stored and says so.
  function notifySaveReplied(stdout, exitCode, sent) {
    var reply = store.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) {
      store.notifySaved = sent
      return
    }
    store.notifyOnEscalation = store.notifySaved
    store.flash("Notify on escalation could not be saved")
  }

  // ---- dispatch (S3 3.1)

  // No refusal or failure to show.
  function clearDispatchError() {
    store.dispatchError = ""
    store.dispatchErrorType = ""
    store.dispatchErrors = []
    store.dispatchLog = ""
    store.dispatchLogTail = ""
    store.dispatchExitCode = null
  }

  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    store.dispatchState = "idle"
    store.dispatchTarget = null
    store.dispatchForm = null
    store.dispatchPreview = null
    store.clearDispatchError()
    store.dispatchSuggest = null
    store.dispatchRunId = ""
    store.dispatchMessage = ""
  }

  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or
  // "board", with its {id: card} map, and returns whether it may be started.
  // Refused (false, nothing changes) without a project or while a start is in
  // flight. A target dispatchPlan does not offer is `refused` at once; any
  // other starts from dispatchDefaults with this project's runSettings and
  // looks up the default branch before anything is checked.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    store.dispatchTarget = plan
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      store.dispatchSuggest = plan.suggest
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: store.runSettings }, card, cardMap)
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", store.project])
    return true
  }

  // Back to idle. Refused while a start is in flight: its outcome must land in
  // a dialog that still shows what was started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    return true
  }

  // A copy of the form with one field set as given; verify is copied as a
  // fresh array when it is one. The store converts nothing else.
  function withField(form, name, value) {
    var next = store.copyMap(form)
    next[name] = name === "verify" && Array.isArray(value) ? value.slice() : value
    return next
  }

  // The helpers' target words: milestone ID, card ID or board.
  function dispatchTargetArgs() {
    var plan = store.dispatchTarget
    return plan.command === "board" ? ["board"] : [plan.command, plan.flags[1]]
  }

  // The form's verify commands that are non-blank strings, verbatim, in order.
  function dispatchCommands(form) {
    var list = Array.isArray(form.verify) ? form.verify : []
    return list.filter(function(c) { return typeof c === "string" && c.trim() !== "" })
  }

  // The options the preview and the start share. A blank base is left out, so
  // am uses its own default; each verify command is one argument.
  function dispatchOptionArgs() {
    var form = store.dispatchForm
    var args = []
    var base = typeof form.base === "string" ? form.base.trim() : ""
    if (base !== "") args.push("--base-branch", base)
    args.push("--branch-prefix", form.prefix.trim(), "--max-concurrent", String(form.parallelism))
    var commands = store.dispatchCommands(form)
    for (var i = 0; i < commands.length; i++) args.push("--verify", commands[i])
    if (form.allowNoVerification === true) args.push("--allow-no-verification")
    return args
  }

  // The --defaults reply: a non-blank default branch becomes base unless the
  // user set base since the opening; anything else leaves base as it is.
  // Then the form is checked at once.
  function dispatchDefaultsReplied(stdout) {
    if (!dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
    dispatchBook.defaultsPending = false
    var envelope = store.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true ? envelope.data : null
    var branch = data !== null && typeof data === "object" && typeof data.default_branch === "string"
        ? data.default_branch.trim() : ""
    if (branch !== "" && !dispatchBook.baseTouched) store.dispatchForm = store.withField(store.dispatchForm, "base", branch)
    store.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone or the
  // board is previewed. Waits for the defaults lookup, whose reply checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
    dispatchDebounceTimer.stop()
    var result = Runs.validateDispatch(store.dispatchForm)
    if (!result.ok) {
      store.dispatchState = "refused"
      store.dispatchErrors = result.errors
      store.dispatchError = result.errors[0].message
      store.dispatchErrorType = "Form"
      return
    }
    if (store.dispatchTarget.level === "subtask") {
      store.dispatchState = "ready"
      return
    }
    dispatchPreviewRunner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
  }

  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with its summary; am's refusal:
  // its message verbatim; anything else cannot be read.
  function dispatchPreviewReplied(stdout) {
    if (store.dispatchState !== "previewing") return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.dispatchPreview = Runs.previewSummary(envelope.data)
      store.dispatchState = "ready"
      return
    }
    var err = envelope !== null && envelope.ok === false ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message : ""
    store.dispatchState = "refused"
    if (message.trim() !== "") {
      store.dispatchError = message
      store.dispatchErrorType = typeof err.type === "string" ? err.type : ""
    } else {
      store.dispatchError = "The preview could not be read"
      store.dispatchErrorType = ""
    }
  }

  // One form field changed (name one of base, prefix, verify, parallelism,
  // allowNoVerification) while the form may be edited: back to previewing,
  // the preview, any refusal or failure and any preview in flight dropped,
  // and the 400 ms check restarted, so a burst of changes costs one check.
  // Refused (false, nothing changes) for another name, without a form, and
  // while idle, starting or started.
  function setDispatchField(name, value) {
    if (["base", "prefix", "verify", "parallelism", "allowNoVerification"].indexOf(name) < 0) return false
    var state = store.dispatchState
    if (state !== "previewing" && state !== "ready" && state !== "refused" && state !== "failed") return false
    if (store.dispatchForm === null) return false
    store.dispatchForm = store.withField(store.dispatchForm, name, value)
    if (name === "base") dispatchBook.baseTouched = true
    store.dispatchState = "previewing"
    store.dispatchPreview = null
    store.clearDispatchError()
    dispatchPreviewRunner.cancel()
    dispatchDebounceTimer.restart()
    return true
  }

  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), and the parallelism.
  function dispatchStart() {
    if (store.dispatchState !== "ready") return false
    var form = store.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(store.runSettings.prefixHistory) ? store.runSettings.prefixHistory : []
    for (var i = 0; i < stored.length && history.length < 20; i++) {
      var p = stored[i]
      if (typeof p === "string" && p.trim() !== "" && p !== prefix) history.push(p)
    }
    var saved = { verify: store.dispatchCommands(form), allowNoVerification: form.allowNoVerification === true,
                  prefixHistory: history, parallelism: form.parallelism }
    var runner = dispatchStartC.createObject(store, { madeFor: store.project, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    store.dispatchState = "starting"
    runner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
    return true
  }

  // A start runner's reply is this dispatch's: it was made in the current
  // project and is the runner that put the store into `starting` (an idle
  // reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === store.project && dispatchBook.startRunner === runner
  }

  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values in runSettings, a re-snapshot
  // and dispatchStarted(id or null); anything else gives `failed` with what
  // the helper said. After any successful start, wherever it was made, the
  // same runner writes the saved values for the project it was made in.
  function dispatchStartReplied(runner, stdout) {
    if (runner.saving) {
      store.dispatchSaveReplied(runner, stdout)
      return
    }
    var here = store.isHereStart(runner)
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      if (here) {
        store.dispatchRunId = typeof envelope.run_id === "string" ? envelope.run_id : ""
        store.dispatchMessage = typeof envelope.message === "string" ? envelope.message : ""
        var settings = store.copyMap(store.runSettings)
        // Parsed from the JSON that is written: a var property hands back a
        // list Runs.dispatchDefaults does not take for an array.
        var saved = JSON.parse(runner.savedJson)
        for (var key in saved) settings[key] = saved[key]
        store.runSettings = settings
        store.dispatchState = "started"
        store.refresh()
        store.dispatchStarted(store.dispatchRunId !== "" ? store.dispatchRunId : null)
      }
      runner.saving = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["set-run-settings", runner.madeFor, runner.savedJson])
      return
    }
    if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      store.dispatchState = "failed"
      store.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      store.dispatchErrorType = isErr && typeof err.type === "string" ? err.type : ""
      store.dispatchLog = typeof failure.log === "string" ? failure.log : ""
      store.dispatchLogTail = typeof failure.log_tail === "string" ? failure.log_tail : ""
      store.dispatchExitCode = typeof failure.exit_code === "number" ? failure.exit_code : null
    }
    store.dropStartRunner(runner)
  }

  // set-run-settings after a start: a failure is said only while the
  // dispatch is still this one. The runner then goes.
  function dispatchSaveReplied(runner, stdout) {
    var reply = store.parseEnvelope(stdout)
    if (store.isHereStart(runner) && !(reply !== null && reply.ok === true)) store.flash("Dispatch settings could not be saved")
    store.dropStartRunner(runner)
  }

  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
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

  // get-run-settings on a project switch. Its guard is set by projectSwitched()
  // itself rather than bound to `project`: projectSwitched() runs from the
  // snapshot runner's guard change, before a binding here is sure to have
  // followed the project, and this launch must carry the NEW project.
  HelperRunner {
    id: settingsLoadRunner
    script: store.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { store.applyRunSettings(stdout, exitCode) }
  }

  // set-run-settings on a change of the switch; latest wins. Bound to the
  // project like the logs: it is launched by a click, long after the binding
  // followed the project. `sent` is the value the latest launch writes.
  HelperRunner {
    id: settingsSaveRunner
    property bool sent: false
    script: store.backendDir + "projects/viewer-state.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.notifySaveReplied(stdout, exitCode, settingsSaveRunner.sent) }
  }

  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped. No onGuardChanged:
  // the snapshot runner's already runs projectSwitched().
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchDefaultsReplied(stdout) }
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchPreviewReplied(stdout) }
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

  // Only while the panel is open and a toast shows: no timer while idle.
  Timer {
    id: toastTimer
    objectName: "toastTimer"
    interval: 250
    repeat: true
    running: store.active && store.toasts.length > 0
    onTriggered: store.expireToasts(Date.now())
  }

  // only while a change waits to be checked.
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
    onTriggered: store.checkDispatch()
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

  // The toast keys only grow, so a stale Dismiss never removes a newer toast.
  QtObject {
    id: toastState
    property int nextKey: 0
  }

  // The notify.py runners in flight; kept apart so consumers cannot write it.
  QtObject {
    id: notifyState
    property var runners: []
  }

  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet.
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property bool baseTouched: false
    property bool defaultsPending: false
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

  // One HelperRunner per notification. Guard "": a project switch does not
  // stop a notification already launched. It goes when its process exits.
  Component {
    id: notifyC

    HelperRunner {
      id: nr
      script: store.backendDir + "runs/notify.py"
      guard: ""
      onFinished: store.dropNotifyRunner(nr)
    }
  }

  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. After a successful start the same runner writes the settings
  // for `madeFor`; it goes when that write replies, or at once after a
  // failed start.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
      property string savedJson: ""   // `saved` as set-run-settings takes it
      property bool saving: false     // the settings write is in flight
      script: store.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { store.dispatchStartReplied(sr, stdout) }
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
