import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs
import "../domain/results.js" as Results

// The plugin's `service` entry point (manifest.json entryPoints.service). The
// shell creates one per shell, with no parent, while the plugin is enabled,
// and destroys it with the plugin; App does not compose it. `backendDir` is
// the absolute path of <plugin>/core/backend/, with a trailing "/" and no
// file:// scheme, derived from this file's own URL -- the same string
// ui/Panel.qml hands App as backendDir.
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc) and emits alertReceived(alert) for each alert line.
// Each alertReceived runs its own pipeline on a HelperRunner of its own
// (alertRunners; `step` "settings", then "snapshot"): viewer-state.py
// get-global-settings, read at each alert -- the alert is dropped unless
// notifyOnEscalation is exactly true --, then runs-snapshot.py of the
// alert's root, once (none when the root is not a non-empty string or
// starts with "-"), then notify.py TITLE BODY from Runs.alertNotification
// of that run (null when the snapshot fails or lacks it) on one more
// HelperRunner of its own (notifyRunners). No runner serves two alerts.
// `status` is "watching" while a launched helper has not exited, "waiting"
// between a retryable failure and the relaunch 300 s later (retryTimer, which
// runs only then), "stopped" after exit 0 or a SchemaMismatch /
// CorruptJournal failure; "stopped" is final for this instance. `lastError`
// is the most recent failure's text; each failure is one console.warn line.
Scope {
  id: service

  readonly property string backendDir: Qt.resolvedUrl("../backend/").toString().replace(/^file:\/\//, "")   // <plugin>/core/backend/
  readonly property alias status: alertsState.status        // "watching" | "waiting" | "stopped"
  readonly property alias lastError: alertsState.lastError  // "" until the first failure
  readonly property alias helperProc: alertsState.proc      // the current launch's Process while watching, else null
  readonly property alias retryTimer: retryTimer
  readonly property alias alertRunners: pipelineState.alertRunners    // per-alert settings / snapshot runners in flight, oldest first
  readonly property alias notifyRunners: pipelineState.notifyRunners  // notify.py runners in flight, oldest first

  // One emission per valid alert line of the current launch: the parsed
  // {run_id, root, project, state, ...} object, untouched.
  signal alertReceived(var alert)

  onAlertReceived: function(alert) { service.startAlert(alert) }

  Component.onCompleted: service.launch()

  Component.onDestruction: {
    alertsState.launchSeq += 1
    retryTimer.stop()
    if (alertsState.proc) alertsState.proc.running = false
  }

  // runs-alerts.py, no argument, on a new Process with the next launch number.
  function launch() {
    alertsState.launchSeq += 1
    retryTimer.stop()
    var proc = helperC.createObject(service, { launchSeq: alertsState.launchSeq })
    proc.command = ["python3", service.backendDir + "runs/runs-alerts.py"]
    alertsState.proc = proc
    alertsState.status = "watching"
    proc.running = true
  }

  // A line or exit counts only from the newest launch.
  function isCurrent(proc) {
    return proc.launchSeq === alertsState.launchSeq
  }

  // One stdout line of the current launch. {"ok": false, ...} is kept as the
  // envelope its exit explains. {"alert": {run_id: non-empty string, state:
  // "escalated" | "dead", ...}} emits alertReceived with that object.
  // Anything else is ignored. Never throws.
  function helperLine(proc, data) {
    if (!service.isCurrent(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (value.ok === false) { proc.envelope = value; return }
    var alert = value.alert
    if (alert === null || typeof alert !== "object" || Array.isArray(alert)) return
    if (typeof alert.run_id !== "string" || alert.run_id === "") return
    if (alert.state !== "escalated" && alert.state !== "dead") return
    service.alertReceived(alert)
  }

  // The current launch ended. Exit 0: stopped, no warning. Otherwise the last
  // envelope line decides: SchemaMismatch and CorruptJournal stop, anything
  // else (or no envelope) waits 300 s for a relaunch.
  function helperExited(proc, exitCode) {
    if (!service.isCurrent(proc)) return
    alertsState.proc = null
    if (exitCode === 0) {
      alertsState.status = "stopped"
      return
    }
    var envelope = proc.envelope
    var err = envelope ? envelope.error : null
    var type = err !== null && typeof err === "object" ? err.type : ""
    alertsState.lastError = envelope ? Runs.errorText(envelope) : "runs-alerts.py exited " + exitCode
    if (type === "SchemaMismatch" || type === "CorruptJournal") {
      alertsState.status = "stopped"
      console.warn("RunAlertsService: " + alertsState.lastError + " -- stopped")
    } else {
      alertsState.status = "waiting"
      retryTimer.start()
      console.warn("RunAlertsService: " + alertsState.lastError + " -- retrying in 300 s")
    }
  }

  // One alert's pipeline, on a HelperRunner of its own: get-global-settings,
  // read at each alert.
  function startAlert(alert) {
    var runner = alertC.createObject(service, { alert: alert, script: service.backendDir + "projects/viewer-state.py" })
    pipelineState.alertRunners = pipelineState.alertRunners.concat([runner])
    runner.run(["get-global-settings"])
  }

  // The newest run of an alert's runner finished; its step says which run it
  // was. Settings: the alert goes on only on exit 0 with notifyOnEscalation
  // exactly true, else it is dropped. Then one runs-snapshot.py of the
  // alert's root when that is a non-empty string not starting with "-", else
  // straight to notify with a null run. Snapshot: notify with the alert's run
  // in the reply (null when absent). Any other step changes nothing. Never
  // throws.
  function alertStepFinished(runner, stdout, exitCode) {
    var alert = runner.alert
    if (runner.step === "settings") {
      var settings = exitCode === 0 ? Results.parseEnvelope(stdout) : null
      if (settings === null || settings.notifyOnEscalation !== true) {
        service.dropAlertRunner(runner)
        return
      }
      var root = alert.root
      if (typeof root !== "string" || root === "" || root.charAt(0) === "-") {
        service.dropAlertRunner(runner)
        service.notify(alert, null)
        return
      }
      runner.step = "snapshot"
      runner.script = service.backendDir + "runs/runs-snapshot.py"
      runner.run([root])
    } else if (runner.step === "snapshot") {
      service.dropAlertRunner(runner)
      service.notify(alert, service.snapshotRun(stdout, exitCode, alert.run_id))
    }
  }

  // The runner leaves alertRunners; its step becomes "" so no later exit
  // advances it.
  function dropAlertRunner(runner) {
    runner.step = ""
    pipelineState.alertRunners = pipelineState.alertRunners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  // The run runId in one runs-snapshot.py reply, normalized; null unless the
  // exit is 0 and the last line is {"ok": true, "runs": [...]} holding it.
  // Entries that are not plain objects are skipped. Never throws.
  function snapshotRun(stdout, exitCode, runId) {
    if (exitCode !== 0) return null
    var envelope = Results.parseEnvelope(stdout)
    if (envelope === null || envelope.ok !== true || !Array.isArray(envelope.runs)) return null
    var runs = []
    for (var i = 0; i < envelope.runs.length; i++) {
      var entry = envelope.runs[i]
      if (entry === null || typeof entry !== "object" || Array.isArray(entry)) continue
      runs.push(Runs.normalizeRun({ row: service.rowOf(entry), status: entry.status }))
    }
    return Runs.runById(runs, runId)
  }

  // The `am runs` summary without its `status` key: the helper replaced the
  // summary's status string with the `am status` object, which normalizeRun
  // must never read as the row's status ("[object Object]").
  function rowOf(entry) {
    var row = {}
    for (var key in entry) {
      if (key !== "status" && Runs.hasKey(entry, key)) row[key] = entry[key]
    }
    return row
  }

  // One notify.py TITLE BODY for an alert, from Runs.alertNotification of run
  // (null: the short-id fallback), on a runner of its own so two never stop
  // each other. The reply is not read.
  function notify(alert, run) {
    var project = typeof alert.project === "string" ? alert.project : ""
    var n = Runs.alertNotification(run, alert.state, project, alert.run_id)
    var runner = notifyC.createObject(service)
    pipelineState.notifyRunners = pipelineState.notifyRunners.concat([runner])
    runner.run([String(n.title), String(n.body)])
  }

  function dropNotifyRunner(runner) {
    pipelineState.notifyRunners = pipelineState.notifyRunners.filter(function(r) { return r !== runner })
    runner.destroy()
  }

  Timer {
    id: retryTimer
    objectName: "retryTimer"
    interval: 300000
    repeat: false
    onTriggered: if (alertsState.status === "waiting") service.launch()
  }

  // What the public aliases read; kept apart so consumers cannot write it.
  QtObject {
    id: alertsState
    property string status: "stopped"
    property string lastError: ""
    property var proc: null
    property int launchSeq: 0
  }

  // The runners in flight; kept apart so consumers cannot write them.
  QtObject {
    id: pipelineState
    property var alertRunners: []
    property var notifyRunners: []
  }

  // One HelperRunner per alert: settings first, then the snapshot. Guard "".
  Component {
    id: alertC

    HelperRunner {
      id: ar
      property var alert: null
      property string step: "settings"   // "settings" | "snapshot"; "" once dropped
      guard: ""
      onFinished: function(stdout, exitCode) { service.alertStepFinished(ar, stdout, exitCode) }
    }
  }

  // One HelperRunner per notification. Guard "". It goes when its process exits.
  Component {
    id: notifyC

    HelperRunner {
      id: nr
      script: service.backendDir + "runs/notify.py"
      guard: ""
      onFinished: service.dropNotifyRunner(nr)
    }
  }

  // One Process per launch, so each carries its launch number and envelope.
  Component {
    id: helperC

    Process {
      id: hp
      objectName: "alertsProc"
      property int launchSeq: 0
      property var envelope: null       // the last {"ok": false, ...} line it printed
      stdout: SplitParser { onRead: function(data) { service.helperLine(hp, data) } }
      onExited: function(exitCode) {
        service.helperExited(hp, exitCode)
        hp.destroy()
      }
    }
  }
}
