import QtQml
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results
import "../domain/runs.js" as Runs

// The run controls (S2 4.1), the cancel confirmation (S2 4.3) and the footer
// flash, for a run of any registered project. control(action, runId) starts a
// pause, resume or cancel of a run in `runs`, each on a HelperRunner of its
// own; `pending` ({runId: action}) holds a request until settleAfterSnapshot()
// sees it settled, `stillWaiting` ({runId: true}) the pending ones 30 s or
// more old. Both are replaced, never changed in place. The control error is
// its own pair of fields, which no snapshot touches. Every applied control
// reply asks for a re-snapshot of every root: refreshRequested("all"). The
// backend directory, the open project's root, the panel-open flag and the
// run list are handed to it from outside -- it never reaches for another
// store. App composes it as `app.runControl`, calls settleAfterSnapshot() on
// each ok snapshotReplied of the run store, and routes refreshRequested
// there. The "Notify on escalation" switch is viewer-wide: each opening reads
// it (get-global-settings) and setNotifyOnEscalation writes it
// (set-global-settings); a failed save puts it back and flashes. A project
// switch changes nothing here. Each project's run settings (`runSettings`,
// {root: settings}): loadRunSettings reads them and saveRunSettings merges
// and writes a patch, each on a runner of its own; a load's reply is
// announced (runSettingsLoaded) and a failed save too (runSettingsSaveFailed).
// A milestone resume with no stored verify set opens the Resume dialog
// (resumeOpenFor .. resumeConfirm), whose confirm saves the typed set for the
// run's project on resumeSaveRunner.
Scope {
  id: control

  property string backendDir: ""      // <plugin>/core/backend/
  property string project: ""         // the open project's root path; "" when none is open
  property bool active: false         // App binds this to "panel open" (app.panelOpen)
  property var runs: []               // the run store's merged run list; App binds it

  // A re-snapshot is wanted: "all" (every usable root) or [root, ...].
  signal refreshRequested(var roots)

  property var pending: ({})
  property var stillWaiting: ({})
  readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
  property string lastControlError: ""      // Runs.controlError sentence of the last failed request
  property string lastControlErrorRunId: "" // the run that sentence is about
  property string lastControlErrorType: ""  // am's error type of that failure; "" when it carried none

  // The cancel confirmation: the run it asks about ("" = closed), the typed
  // word and why the last confirm was refused.
  property string cancelRunId: ""
  readonly property bool cancelOpen: control.cancelRunId !== ""
  property string cancelText: ""
  property string cancelError: ""
  // The footer flash: why a run key was refused. flashTimer clears it.
  property string flashText: ""
  // "Notify on escalation", viewer-wide and off until read: the switch's
  // value, the last value read from or written to viewer-state.py's global
  // settings, and whether the user changed it since this opening's load was
  // launched (a late load reply then changes nothing). A project switch
  // never changes them.
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // Each project's run settings, {root: settings}: the root's last
  // get-run-settings object as read, with the saves since merged in.
  // Replaced, never changed in place.
  property var runSettings: ({})
  // A save's reply was not {"ok": true}: `patch` is what that save sent.
  signal runSettingsSaveFailed(var root, var patch)
  // A load's reply was kept for root: `settings` is root's entry now.
  signal runSettingsLoaded(var root, var settings)

  readonly property alias controlRunners: controlState.runners  // in-flight control requests, oldest first
  readonly property alias pendingTimer: pendingTimer
  readonly property alias flashTimer: flashTimer
  readonly property alias settingsLoadRunner: settingsLoadRunner
  readonly property alias settingsSaveRunner: settingsSaveRunner
  readonly property alias runSettingsRunners: runSettingsState.runners     // in-flight run settings loads and saves, oldest first
  readonly property alias runSettingsLoadRunner: runSettingsState.lastLoad // the newest load until it replies; else null

  // A new request for runId, a run in `runs`: the control error is dismissed,
  // the request is recorded with the run's state as its baseline, pending is
  // set, and its runner (repo_dir and project.root of the run, not launched
  // yet) joins controlRunners and is returned.
  function startRequest(action, runId) {
    var run = Runs.runById(control.runs, runId)
    control.dismissControlError()
    controlState.nextToken += 1
    var requests = Runs.copyMap(controlState.requests)
    requests[runId] = { token: controlState.nextToken, action: action, baseline: Runs.runState(run),
                        launchedMs: Date.now(), acknowledged: false, requestedAt: "" }
    controlState.requests = requests
    var p = Runs.copyMap(control.pending)
    p[runId] = action
    control.pending = p
    var runner = controlC.createObject(control, { runId: runId, action: action, token: controlState.nextToken,
                                                  repoDir: run.repo_dir, projectRoot: Runs.runRoot(run) })
    controlState.runners = controlState.runners.concat([runner])
    return runner
  }

  // Starts a pause, resume or cancel of one run in `runs`, of any project, and
  // returns whether it started: only when refusalOf(action, runId) is "".
  // The request acts on the run's repo_dir; a milestone resume reads the run
  // settings of the run's project.root. Confirming a cancel is the caller's job.
  function control(action, runId) {
    if (control.refusalOf(action, runId) !== "") return false
    var run = Runs.runById(control.runs, runId)
    var runner = control.startRequest(action, runId)
    if (action === "resume" && run.workflow !== "task") {
      // A milestone resume reuses its project's stored verify set: read it first.
      runner.settingsStep = true
      runner.script = control.backendDir + "projects/viewer-state.py"
      runner.run(["get-run-settings", runner.projectRoot])
    } else {
      control.launchControl(runner, [])
    }
    return true
  }

  // The request's run-control.py launch on its own runner: ACTION RUN REPO,
  // REPO the repo_dir the request was made with, then `extra` (a resume's
  // verify arguments).
  function launchControl(runner, extra) {
    runner.script = control.backendDir + "runs/run-control.py"
    runner.run([runner.action, runner.runId, runner.repoDir].concat(extra))
  }

  // The request this runner was launched for, while it is still the one
  // pending for its run; null once it was settled or replaced by a newer
  // request.
  function requestOf(runner) {
    if (!Runs.hasKey(controlState.requests, runner.runId)) return null
    var req = controlState.requests[runner.runId]
    return req.token === runner.token ? req : null
  }

  // The request for runId is over: its pending entry, its still-waiting mark
  // and its bookkeeping go.
  function settle(runId) {
    if (Runs.hasKey(control.pending, runId)) {
      var p = Runs.copyMap(control.pending)
      delete p[runId]
      control.pending = p
    }
    if (Runs.hasKey(control.stillWaiting, runId)) {
      var w = Runs.copyMap(control.stillWaiting)
      delete w[runId]
      control.stillWaiting = w
    }
    if (Runs.hasKey(controlState.requests, runId)) {
      var r = Runs.copyMap(controlState.requests)
      delete r[runId]
      controlState.requests = r
    }
  }

  // A request ended without am taking it: the buttons come back and the
  // sentence shows under that run. `type` is am's error type when a string,
  // else "".
  function failControl(runId, sentence, type) {
    control.settle(runId)
    control.lastControlError = sentence
    control.lastControlErrorRunId = runId
    control.lastControlErrorType = typeof type === "string" ? type : ""
  }

  function dismissControlError() {
    control.lastControlError = ""
    control.lastControlErrorRunId = ""
    control.lastControlErrorType = ""
  }

  // A runner's request is over: it leaves controlRunners and is destroyed.
  function dropRunner(runner) {
    controlState.runners = controlState.runners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // One run-control.py reply, whatever project is open. ok:true
  // means am has the request: pending stays until a snapshot settles it, and
  // the requested_at am gave it is remembered. Anything else ends it with a
  // sentence. Either way the runner goes, then refreshRequested("all"). A
  // reply for a request that is no longer the pending one changes nothing.
  function controlReplied(runner, stdout, exitCode) {
    var req = control.requestOf(runner)
    if (req === null) {
      control.dropRunner(runner)
      return
    }
    if (runner.settingsStep) {
      runner.settingsStep = false
      control.resumeWithSettings(runner, stdout, exitCode)
      return
    }
    var envelope = Results.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var data = envelope.data
      var requestedAt = data !== null && typeof data === "object" && typeof data.requested_at === "string" ? data.requested_at : ""
      var requests = Runs.copyMap(controlState.requests)
      requests[runner.runId] = { token: req.token, action: req.action, baseline: req.baseline,
                                 launchedMs: req.launchedMs, acknowledged: true, requestedAt: requestedAt }
      controlState.requests = requests
    } else if (envelope !== null && envelope.ok === false) {
      var err = envelope.error
      var type = err !== null && typeof err === "object" && typeof err.type === "string" ? err.type : ""
      control.failControl(runner.runId, Runs.controlError(envelope), type)
    } else {
      control.failControl(runner.runId, "The run control gave no usable result (exit " + exitCode + ").", "")
    }
    control.dropRunner(runner)
    control.refreshRequested("all")
  }

  // The run settings' reply for a milestone resume. A stored verify set (a
  // non-empty list of strings) goes to run-control as --verify pairs in its
  // order; otherwise the stored opt-out as --allow-no-verification. With
  // neither, the request is settled and the Resume dialog opens for the run;
  // with no readable reply, the request ends with a sentence. In both,
  // run-control is never launched and there is no re-snapshot.
  function resumeWithSettings(runner, stdout, exitCode) {
    var settings = Results.parseEnvelope(stdout)
    if (settings === null) {
      control.failControl(runner.runId, "The run settings gave no usable result (exit " + exitCode + ").", "")
      control.dropRunner(runner)
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
      control.launchControl(runner, extra)
    } else if (settings.allowNoVerification === true) {
      control.launchControl(runner, ["--allow-no-verification"])
    } else {
      var runId = runner.runId
      control.settle(runId)
      control.dropRunner(runner)
      control.resumeOpenFor(runId)
    }
  }

  // After every good snapshot: an acknowledged request is settled when its run
  // is gone from `runs`, when the run's state moved since the request started,
  // or (pause, cancel) when am marks its request handled. A request still in
  // flight is never settled by a snapshot: its buttons stay off until the reply.
  function settleAfterSnapshot() {
    var ids = Object.keys(control.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (!Runs.hasKey(controlState.requests, id)) continue
      var req = controlState.requests[id]
      if (!req.acknowledged) continue
      var run = Runs.runById(control.runs, id)
      if (run === null || Runs.runState(run) !== req.baseline
          || (req.action !== "resume" && control.isHandled(run, req))) control.settle(id)
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
    var ids = Object.keys(control.pending)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (Runs.hasKey(controlState.requests, id) && nowMs - controlState.requests[id].launchedMs >= 30000) out[id] = true
    }
    control.stillWaiting = out
  }

  // "" when control(action, runId) would start a request; otherwise why not:
  // a run that is not in `runs`, then a run with no repo_dir, then a resume
  // (not of a task run) of a run with no project root, then a request already
  // pending for it, then the reason Runs.controls gives. Changes nothing.
  function refusalOf(action, runId) {
    if (action !== "pause" && action !== "resume" && action !== "cancel") return "Unknown control"
    var run = typeof runId !== "string" || runId === "" ? null : Runs.runById(control.runs, runId)
    if (run === null) return "This run is no longer in the snapshot"
    if (typeof run.repo_dir !== "string" || run.repo_dir === "") return "This run has no repository"
    if (action === "resume" && run.workflow !== "task" && Runs.runRoot(run) === "") return "This run's project is not known"
    if (Runs.hasKey(control.pending, runId)) return "A request for this run is pending"
    return Runs.controls(run)[action].reason
  }

  // Shows text in the footers for 3 s; a new flash replaces it and restarts
  // the clock, flash("") clears it.
  function flash(text) {
    control.flashText = String(text || "")
    if (control.flashText === "") flashTimer.stop()
    else flashTimer.restart()
  }

  // Opens the cancel confirmation for a run that can be cancelled now;
  // otherwise flashes why not and leaves any dialog as it is.
  function openCancel(runId) {
    var reason = control.refusalOf("cancel", runId)
    if (reason !== "") {
      control.flash(reason)
      return false
    }
    control.cancelText = ""
    control.cancelError = ""
    control.cancelRunId = runId
    return true
  }

  function closeCancel() {
    control.cancelRunId = ""
    control.cancelText = ""
    control.cancelError = ""
  }

  // The dialog's confirm. The typed word is checked again here (the dialog
  // gates it too), then the run is checked again: one that changed under the
  // open dialog keeps it open with the reason. A started cancel closes it.
  function confirmCancel() {
    if (control.cancelRunId === "") return false
    if (String(control.cancelText).trim().toLowerCase() !== "cancel") return false
    var reason = control.refusalOf("cancel", control.cancelRunId)
    if (reason !== "") {
      control.cancelError = reason
      return false
    }
    if (!control.control("cancel", control.cancelRunId)) {
      control.cancelError = "The run could not be cancelled"
      return false
    }
    control.closeCancel()
    return true
  }

  // ---- resume dialog

  // The Resume dialog: a milestone resume with no stored verify set asks for
  // the commands here. `resumeRunId` is the run it asks about ("" = closed),
  // `resumeVerify` the commands as typed (blanks allowed),
  // `resumeAllowNoVerification` the opt-out, and `resumeError` why the last
  // confirm was refused.
  property string resumeRunId: ""
  property var resumeVerify: []
  property bool resumeAllowNoVerification: false
  property string resumeError: ""

  // Opens the dialog for runId with empty fields, replacing any open one, and
  // returns true. Returns false and changes nothing when runId is not a
  // non-empty string, its run is not in the snapshot, or it is a task run.
  function resumeOpenFor(runId) {
    if (typeof runId !== "string" || runId === "") return false
    var run = Runs.runById(control.runs, runId)
    if (run === null || run.workflow === "task") return false
    control.resumeVerify = []
    control.resumeAllowNoVerification = false
    control.resumeError = ""
    control.resumeRunId = runId
    return true
  }

  function resumeClose() {
    control.resumeRunId = ""
    control.resumeVerify = []
    control.resumeAllowNoVerification = false
    control.resumeError = ""
  }

  // The dialog's confirm. Refused, with resumeError and the dialog left open,
  // when the form has no non-blank command and no opt-out, or when the run
  // cannot be resumed now (refusalOf). Otherwise the resume starts as
  // control() starts one and launches run-control at once: the non-blank
  // commands as --verify pairs in order, else --allow-no-verification. The
  // set is saved for the run's project without waiting for the reply, the
  // dialog closes, and true is returned.
  function resumeConfirm() {
    if (control.resumeRunId === "") return false
    var form = { verify: control.resumeVerify, allowNoVerification: control.resumeAllowNoVerification }
    var missing = Runs.validateDispatch(form).errors.filter(function(e) { return e.field === "verify" })
    if (missing.length > 0) {
      control.resumeError = missing[0].message
      return false
    }
    var runId = control.resumeRunId
    var reason = control.refusalOf("resume", runId)
    if (reason !== "") {
      control.resumeError = reason
      return false
    }
    var commands = Runs.verifyCommands(form)
    var extra = []
    for (var i = 0; i < commands.length; i++) extra.push("--verify", commands[i])
    if (commands.length === 0) extra = ["--allow-no-verification"]
    var runner = control.startRequest("resume", runId)
    control.launchControl(runner, extra)
    resumeSaveRunner.run(["set-run-settings", runner.projectRoot,
                          JSON.stringify({ verify: commands, allowNoVerification: control.resumeAllowNoVerification === true })])
    control.resumeClose()
    return true
  }

  // set-run-settings: {"ok": true} changes nothing; anything else flashes.
  // Never touches the request, the control error or the dialog.
  function resumeSaveReplied(stdout, exitCode) {
    var reply = Results.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) return
    control.flash("The verify commands could not be saved")
  }

  // set-run-settings for a confirmed resume; latest wins. No guard: the save
  // is for the run's project, whatever project is open.
  HelperRunner {
    id: resumeSaveRunner
    script: control.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { control.resumeSaveReplied(stdout, exitCode) }
  }
  readonly property alias resumeSaveRunner: resumeSaveRunner

  // ---- the notify switch (S2 4.4)

  // Each opening (`active` turning true) reads the switch: notifyTouched is
  // cleared first unless a save is in flight. Closing launches nothing.
  onActiveChanged: {
    if (!control.active) return
    if (!settingsSaveRunner.busy) control.notifyTouched = false
    settingsLoadRunner.run(["get-global-settings"])
  }

  // The switch changed: shown at once, written to the global settings in the
  // background. Always works, with or without a project, and returns true.
  function setNotifyOnEscalation(on) {
    var value = !!on
    control.notifyOnEscalation = value
    control.notifyTouched = true
    settingsSaveRunner.sent = value
    settingsSaveRunner.run(["set-global-settings", JSON.stringify({ notifyOnEscalation: value })])
    return true
  }

  // get-global-settings: only a real true turns the switch on; an unreadable
  // reply leaves it off. Too late once the user changed the switch in this
  // opening.
  function applyGlobalSettings(stdout, exitCode) {
    if (control.notifyTouched) return
    var settings = Results.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
    control.notifyOnEscalation = on
    control.notifySaved = on
  }

  // set-global-settings: {"ok": true} means `sent` is stored; anything else puts
  // the switch back to what is stored and says so.
  function notifySaveReplied(stdout, exitCode, sent) {
    var reply = Results.parseEnvelope(stdout)
    if (reply !== null && reply.ok === true) {
      control.notifySaved = sent
      return
    }
    control.notifyOnEscalation = control.notifySaved
    control.flash("Notify on escalation could not be saved")
  }

  // ---- run settings (split-runstore 4.2)

  // root's run settings: its entry in runSettings, else one shared empty
  // object, the same on every call, which the store never writes.
  function runSettingsOf(root) {
    return Runs.hasKey(control.runSettings, root) ? control.runSettings[root] : runSettingsState.empty
  }

  // root's entry becomes `settings` as given (not a copy) in a new map;
  // anything that is not a non-null object gives {}. Root "" changes nothing.
  function applyRunSettings(root, settings) {
    if (typeof root !== "string" || root === "") return
    var map = Runs.copyMap(control.runSettings)
    map[root] = settings !== null && typeof settings === "object" ? settings : {}
    control.runSettings = map
  }

  // viewer-state.py get-run-settings ROOT on a runner of its own: root's
  // entry is dropped until the reply, which is kept whole for root whatever
  // project is open ({} when unreadable; it never touches the notify
  // switch). Root "" launches nothing.
  function loadRunSettings(root) {
    if (typeof root !== "string" || root === "") return
    var map = Runs.copyMap(control.runSettings)
    delete map[root]
    control.runSettings = map
    runSettingsState.lastLoad = control.launchRunSettings({ root: root }, ["get-run-settings", root])
  }

  // patch is merged over root's entry at once (each key replaces, except
  // prefixByMilestone, merged per milestone id), then viewer-state.py
  // set-run-settings ROOT JSON(patch) runs on a runner of its own. A reply
  // other than {"ok": true} emits runSettingsSaveFailed(root, patch) and
  // undoes nothing. Root "" or a patch that is not a non-null object
  // launches nothing.
  function saveRunSettings(root, patch) {
    if (typeof root !== "string" || root === "" || patch === null || typeof patch !== "object") return
    var merged = Runs.copyMap(control.runSettingsOf(root))
    for (var key in patch) {
      merged[key] = key === "prefixByMilestone" ? Runs.mergedPrefixes(merged.prefixByMilestone, patch[key]) : patch[key]
    }
    control.applyRunSettings(root, merged)
    var json = JSON.stringify(patch)
    control.launchRunSettings({ root: root, json: json, saving: true }, ["set-run-settings", root, json])
  }

  // A new runSettingsC runner with `props`, added to runSettingsRunners and
  // launched with `args`; returns it.
  function launchRunSettings(props, args) {
    var runner = runSettingsC.createObject(control, props)
    runSettingsState.runners = runSettingsState.runners.concat([runner])
    runner.run(args)
    return runner
  }

  // A load's reply is kept for its root and announced (runSettingsLoaded,
  // after the runner went); a save's reply other than {"ok": true} is
  // announced. Either way the runner goes.
  function runSettingsReplied(runner, stdout) {
    if (runner.saving) {
      var reply = Results.parseEnvelope(stdout)
      if (!(reply !== null && reply.ok === true)) control.runSettingsSaveFailed(runner.root, JSON.parse(runner.json))
      control.dropRunSettingsRunner(runner)
      return
    }
    var root = runner.root
    control.applyRunSettings(root, Results.parseEnvelope(stdout))
    control.dropRunSettingsRunner(runner)
    control.runSettingsLoaded(root, control.runSettingsOf(root))
  }

  // A run settings runner's request is over: it leaves runSettingsRunners
  // (and runSettingsLoadRunner) and is destroyed.
  function dropRunSettingsRunner(runner) {
    runSettingsState.runners = runSettingsState.runners.filter(function(r) { return r !== runner })
    if (runSettingsState.lastLoad === runner) runSettingsState.lastLoad = null
    runner.destroy()
  }

  // Only while the panel is open and a control request is pending: closing the
  // panel keeps `pending` but leaves no timer running.
  Timer {
    id: pendingTimer
    objectName: "pendingTimer"
    interval: 1000
    repeat: true
    running: control.active && Object.keys(control.pending).length > 0
    onTriggered: control.checkWaiting(Date.now())
  }

  // Clears the footer flash 3 s after the last flash().
  Timer {
    id: flashTimer
    objectName: "flashTimer"
    interval: 3000
    repeat: false
    onTriggered: control.flashText = ""
  }

  // get-global-settings, once per opening; latest wins. No guard: the switch
  // is viewer-wide, and a reply that lands after the panel closed is still
  // applied.
  HelperRunner {
    id: settingsLoadRunner
    script: control.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { control.applyGlobalSettings(stdout, exitCode) }
  }

  // set-global-settings on a change of the switch; latest wins. No guard: a
  // project switch never drops its reply. `sent` is the value the latest
  // launch writes.
  HelperRunner {
    id: settingsSaveRunner
    property bool sent: false
    script: control.backendDir + "projects/viewer-state.py"
    onFinished: function(stdout, exitCode) { control.notifySaveReplied(stdout, exitCode, settingsSaveRunner.sent) }
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
  // stop each other. No guard: a reply is applied whatever project is open.
  // A milestone resume uses its runner twice: viewer-state.py, then
  // run-control.py.
  Component {
    id: controlC

    HelperRunner {
      id: cr
      property string runId: ""
      property string action: ""
      property int token: 0
      property string repoDir: ""         // the run's repo_dir when the request was made
      property string projectRoot: ""     // the run's project.root then; "" when it had none
      property bool settingsStep: false   // reading the run settings; run-control comes next
      onFinished: function(stdout, exitCode) { control.controlReplied(cr, stdout, exitCode) }
    }
  }

  // The run settings requests' own state; kept apart so consumers cannot
  // write it. `lastLoad` is the newest load until it replies; `empty` is
  // runSettingsOf's shared empty object.
  QtObject {
    id: runSettingsState
    property var runners: []
    property var lastLoad: null
    property var empty: ({})
  }

  // One HelperRunner per run settings request, so loads and saves never stop
  // each other, the notify switch's runners or a resume's settings step. No
  // guard: a reply is applied whatever project is open.
  Component {
    id: runSettingsC

    HelperRunner {
      id: rr
      property string root: ""      // the project the request is for
      property string json: ""      // a save's patch as set-run-settings takes it; "" for a load
      property bool saving: false   // set-run-settings, not get-run-settings
      script: control.backendDir + "projects/viewer-state.py"
      onFinished: function(stdout, exitCode) { control.runSettingsReplied(rr, stdout) }
    }
  }
}
