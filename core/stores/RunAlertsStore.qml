import QtQml
import Quickshell
import Quickshell.Io
import "../domain/runs.js" as Runs

// The run alerts (S2 4.4): a toast for every run of any registered project
// that newly needs a human while the panel is open. Its one entry point for
// snapshot results is snapshotReplied, called once per project reply.
// `armedRoots` is {root: true} of every root whose runs may be
// compared against, and is replaced, never changed in place: a root's first
// ok reply after an opening, a `missing` reply or its return to the registry
// only arms it, so history is never replayed. `alertsArmed`: some root is
// armed. `toasts` is {key, id, title, state, reason, project, expiresMs},
// oldest first, at most 3, and is replaced, never changed in place; `project`
// is the name of the run's project. The panel-open flag and the registry are
// handed to it from outside -- it never reaches for another store and
// launches no helper. App composes it as `app.runAlerts` and routes the run
// store's snapshotReplied here.
Scope {
  id: alerts

  property bool active: false               // App binds this to "panel open" (app.panelOpen)
  property var projectRoots: []             // [{root, name}], the registry in its order; App binds it

  property var armedRoots: ({})
  readonly property bool alertsArmed: Object.keys(alerts.armedRoots).length > 0
  property var toasts: []
  property int toastMs: 8000

  readonly property alias toastTimer: toastTimer

  // Opening disarms every root; closing disarms every root and empties the toasts.
  onActiveChanged: {
    alerts.armedRoots = {}
    if (!alerts.active) alerts.toasts = []
  }

  onProjectRootsChanged: alerts.pruneArmed()

  // One project's snapshot reply. "ok" while active: when `root` is armed,
  // Runs.newAlerts(previousRuns, runs) is raised (a non-array previousRuns
  // counts as []), each alert with `project` the project.name of its run in
  // `runs` ("" when it has none); then `root` is armed. "missing" disarms
  // every root and keeps the toasts. "ok" while closed, "failed" and any other
  // outcome change nothing.
  function snapshotReplied(root, outcome, previousRuns, runs) {
    if (outcome === "missing") {
      alerts.armedRoots = {}
      return
    }
    if (outcome !== "ok" || !alerts.active) return
    if (Runs.hasKey(alerts.armedRoots, root)) {
      var found = Runs.newAlerts(Array.isArray(previousRuns) ? previousRuns : [], runs)
      for (var i = 0; i < found.length; i++) {
        var run = Runs.runById(runs, found[i].id)
        var project = run !== null && run.project !== null && typeof run.project === "object" ? run.project.name : ""
        found[i].project = typeof project === "string" ? project : ""
      }
      alerts.raiseAlerts(found)
    }
    var armed = Runs.copyMap(alerts.armedRoots)
    armed[root] = true
    alerts.armedRoots = armed
  }

  // The registry changed: every armed root that no entry of projectRoots
  // names (entry.root === root) loses its arming. armedRoots is replaced only
  // when a root went; no toast is touched.
  function pruneArmed() {
    var list = alerts.projectRoots
    var n = list !== null && typeof list === "object" && typeof list.length === "number" ? list.length : 0
    var named = {}
    for (var i = 0; i < n; i++) {
      var p = list[i]
      if (p !== null && typeof p === "object" && typeof p.root === "string") named[p.root] = true
    }
    var armed = {}
    var went = false
    for (var root in alerts.armedRoots) {
      if (!Runs.hasKey(alerts.armedRoots, root)) continue
      if (Runs.hasKey(named, root)) armed[root] = true
      else went = true
    }
    if (went) alerts.armedRoots = armed
  }

  // One toast per alert, newest last: a run's older toast goes first, then the
  // oldest beyond three. It does not check `active`.
  function raiseAlerts(items) {
    var list = Array.isArray(items) ? items : []
    for (var i = 0; i < list.length; i++) {
      var a = list[i]
      toastState.nextKey += 1
      var next = alerts.toasts.filter(function(t) { return t.id !== a.id })
      next.push({ key: toastState.nextKey, id: a.id, title: a.title, state: a.state, reason: a.reason,
                  project: typeof a.project === "string" ? a.project : "", expiresMs: Date.now() + alerts.toastMs })
      while (next.length > 3) next.shift()
      alerts.toasts = next
    }
  }

  // Drops every toast whose time is up at nowMs (the timer passes Date.now()).
  function expireToasts(nowMs) {
    var next = alerts.toasts.filter(function(t) { return t.expiresMs > nowMs })
    if (next.length !== alerts.toasts.length) alerts.toasts = next
  }

  // The toast with this key goes; an unknown key changes nothing.
  function dismissToast(key) {
    var next = alerts.toasts.filter(function(t) { return t.key !== key })
    if (next.length !== alerts.toasts.length) alerts.toasts = next
  }

  function dismissAllToasts() {
    if (alerts.toasts.length > 0) alerts.toasts = []
  }

  // Only while the panel is open and a toast shows: no timer while idle.
  Timer {
    id: toastTimer
    objectName: "toastTimer"
    interval: 250
    repeat: true
    running: alerts.active && alerts.toasts.length > 0
    onTriggered: alerts.expireToasts(Date.now())
  }

  // The toast keys only grow, so a stale Dismiss never removes a newer toast.
  QtObject {
    id: toastState
    property int nextKey: 0
  }
}
