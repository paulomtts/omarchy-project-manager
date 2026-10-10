import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The plugin's `service` entry point (manifest.json entryPoints.service). The
// shell creates one per shell, with no parent, while the plugin is enabled,
// and destroys it with the plugin; App does not compose it. `backendDir` is
// the absolute path of <plugin>/core/backend/, with a trailing "/" and no
// file:// scheme, derived from this file's own URL -- the same string
// ui/Panel.qml hands App as backendDir.
// From creation to destruction it keeps runs-alerts.py running as a plain
// Process (helperProc). `status` is "watching" while a launched helper has not
// exited, "waiting" between a retryable failure and the relaunch 300 s later
// (retryTimer, which runs only then), "stopped" after exit 0 or a
// SchemaMismatch / CorruptJournal failure; "stopped" is final for this
// instance. `lastError` is the most recent failure's text; each failure is
// one console.warn line.
Scope {
  id: service

  readonly property string backendDir: Qt.resolvedUrl("../backend/").toString().replace(/^file:\/\//, "")   // <plugin>/core/backend/
  readonly property alias status: alertsState.status        // "watching" | "waiting" | "stopped"
  readonly property alias lastError: alertsState.lastError  // "" until the first failure
  readonly property alias helperProc: alertsState.proc      // the current launch's Process while watching, else null
  readonly property alias retryTimer: retryTimer

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
  // envelope its exit explains. Anything else is ignored. Never throws.
  function helperLine(proc, data) {
    if (!service.isCurrent(proc)) return
    var text = String(data || "").trim()
    if (text === "") return
    var value = null
    try { value = JSON.parse(text) } catch (e) { return }
    if (value === null || typeof value !== "object" || Array.isArray(value)) return
    if (value.ok === false) proc.envelope = value
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
