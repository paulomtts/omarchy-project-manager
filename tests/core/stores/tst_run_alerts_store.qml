// tests/core/stores/tst_run_alerts_store.qml
// The run alerts store: per-project arming, the toast queue, the toast expiry
// and the notify.py desktop notification. Built alone and driven through
// snapshotReplied, active and projectRoots; and, through a RunStore wired to
// it the way App wires them, a real snapshot reply turning into a toast.
// Stubbed Process objects stand in for every helper.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunAlertsStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"

  // A RunAlertsStore built alone, with nothing bound.
  function makeAlerts() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // A run of `root` (rootA when omitted) as the run store hands it over:
  // normalized and tagged with its project, am status `runStatus`, its lease
  // live or not.
  function runOf(id, runStatus, live, root) {
    var r = root || tc.rootA
    var raw = {
      row: { id: id, repo_dir: r },
      status: {
        run: { id: id, milestone_id: "m-" + id, status: runStatus },
        rows: [], stories: [], subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
    return Runs.withProject(Runs.normalizeRun(raw), r, tc.rootEntry(r).name)
  }
  function runningRun(id, root) { return runOf(id, "started", true, root) }
  function deadRun(id, root) { return runOf(id, "started", false, root) }
  function escalatedRun(id, root) { return runOf(id, "escalated", false, root) }

  // An open alerts store with each of `roots` armed by an ok reply, nothing raised.
  function armedAlerts(roots) {
    var a = makeAlerts(); if (!a) return null
    a.active = true
    for (var i = 0; i < roots.length; i++) a.snapshotReplied(roots[i], "ok", [], [])
    compare(armedKeysOf(a), roots.slice().sort().join(","), "every root's first ok reply arms it")
    compare(a.toasts.length, 0, "and raises nothing")
    return a
  }

  // The armed roots of alerts store `a`, sorted, comma-joined.
  function armedKeysOf(a) { return Object.keys(a.armedRoots).sort().join(",") }

  // The run ids of alerts store `a`'s toasts, oldest first, comma-joined.
  function toastIdsOf(a) { return a.toasts.map(function(t) { return t.id }).join(",") }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // ---- the store alone (split-runstore 2.2)

  // S1
  function test_a_bare_alerts_store_is_disarmed_and_empty() {
    var a = makeAlerts(); if (!a) return
    compare(JSON.stringify(a.armedRoots), "{}")
    compare(a.alertsArmed, false)
    compare(JSON.stringify(a.toasts), "[]")
    compare(a.toastMs, 8000)
    compare(a.notifyRunners.length, 0)
    compare(a.active, false)
    compare(a.notifyOnEscalation, false)
    compare(a.projectRoots.length, 0)
    compare(a.toastTimer.objectName, "toastTimer")
    compare(a.toastTimer.interval, 250)
    compare(a.toastTimer.repeat, true)
    compare(a.toastTimer.running, false)
  }

  // S2
  function test_the_toast_timer_is_the_stores_only_timer() {
    var a = makeAlerts(); if (!a) return
    var timers = []
    for (var i = 0; i < a.data.length; i++) {
      var o = a.data[i]
      if (o && typeof o.interval === "number" && typeof o.repeat === "boolean") timers.push(o.objectName)
    }
    compare(timers.join(","), "toastTimer")
  }

  // S3
  function test_an_ok_reply_while_closed_changes_nothing() {
    var a = makeAlerts(); if (!a) return
    a.notifyOnEscalation = true
    var armed = a.armedRoots
    var toasts = a.toasts
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    verify(a.armedRoots === armed, "armedRoots is not replaced")
    verify(a.toasts === toasts, "no toast")
    compare(a.alertsArmed, false)
    compare(a.notifyRunners.length, 0, "no notification")
  }

  // S4
  function test_the_first_ok_reply_of_a_root_while_open_only_arms_it() {
    var a = makeAlerts(); if (!a) return
    a.active = true
    a.notifyOnEscalation = true
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1"), deadRun("a2")])
    compare(armedKeysOf(a), tc.rootA)
    compare(a.armedRoots[tc.rootA], true)
    compare(a.alertsArmed, true)
    compare(a.toasts.length, 0, "history is never replayed")
    compare(a.notifyRunners.length, 0)
  }

  // S5
  function test_an_armed_roots_ok_reply_raises_new_alerts_with_the_projects_name() {
    var a = armedAlerts([tc.rootB]); if (!a) return
    var armed = a.armedRoots
    var prev = [runningRun("b1", tc.rootB), runningRun("b2", tc.rootB), runningRun("b3", tc.rootB)]
    var next = [escalatedRun("b1", tc.rootB), runningRun("b2", tc.rootB), deadRun("b3", tc.rootB)]
    var expected = Runs.newAlerts(prev, next)
    var before = Date.now()
    a.snapshotReplied(tc.rootB, "ok", prev, next)
    compare(toastIdsOf(a), "b1,b3", "in the order of runs")
    compare(a.toasts[0].project, "beta", "run.project.name")
    compare(a.toasts[0].title, expected[0].title)
    compare(a.toasts[0].title, "m-b1")
    compare(a.toasts[0].state, "escalated")
    compare(a.toasts[0].reason, expected[0].reason)
    compare(a.toasts[1].project, "beta")
    compare(a.toasts[1].state, "dead")
    compare(a.toasts[1].reason, "process died")
    verify(a.toasts[0].key < a.toasts[1].key, "keys only grow")
    verify(a.toasts[0].expiresMs >= before + 8000 && a.toasts[0].expiresMs <= Date.now() + 8000, "8 s from now")
    verify(a.armedRoots !== armed, "armedRoots is replaced")
    compare(armedKeysOf(a), tc.rootB, "and still holds the root")
    compare(a.notifyRunners.length, 0, "the switch is off")
  }

  // S6
  function test_a_run_with_no_project_name_toasts_with_an_empty_project() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    // synthetic: a run the run store never hands over, with no project.
    var bare = Runs.normalizeRun({ row: { id: "x1" }, status: { run: { id: "x1", milestone_id: "m-x1", status: "escalated" } } })
    compare(bare.project, null)
    a.snapshotReplied(tc.rootA, "ok", [], [bare])
    compare(toastIdsOf(a), "x1")
    compare(a.toasts[0].project, "")
  }

  // S7
  function test_a_failed_reply_and_an_unknown_outcome_change_nothing() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1")
    var armed = a.armedRoots
    var toasts = a.toasts
    var outcomes = ["failed", "error", "", "OK", undefined, null]
    for (var i = 0; i < outcomes.length; i++) {
      var label = "outcome " + String(outcomes[i])
      a.snapshotReplied(tc.rootA, outcomes[i], [runningRun("a2")], [escalatedRun("a2")])
      a.snapshotReplied(tc.rootB, outcomes[i], [], [])
      verify(a.armedRoots === armed, label + ": the arming")
      verify(a.toasts === toasts, label + ": the toasts")
    }
  }

  // S8
  function test_missing_disarms_every_root_and_keeps_the_toasts() {
    var a = armedAlerts([tc.rootA, tc.rootB]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1")
    a.snapshotReplied(tc.rootA, "missing", [escalatedRun("a1")], [])
    compare(JSON.stringify(a.armedRoots), "{}", "every root, not only A")
    compare(a.alertsArmed, false)
    compare(toastIdsOf(a), "a1", "the toasts stay")
    a.snapshotReplied(tc.rootB, "ok", [], [escalatedRun("b1", tc.rootB)])
    compare(toastIdsOf(a), "a1", "B's next ok reply only arms")
    compare(armedKeysOf(a), tc.rootB)
  }

  // S9
  function test_non_array_previous_runs_count_as_empty_and_non_array_runs_raise_nothing() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", undefined, [escalatedRun("a1")])
    compare(toastIdsOf(a), "a1", "undefined previousRuns is []")
    a.snapshotReplied(tc.rootA, "ok", null, [escalatedRun("a1"), escalatedRun("a2")])
    compare(toastIdsOf(a), "a1,a2", "null previousRuns is [] too: a1 raises again and replaces its own toast")
    a.snapshotReplied(tc.rootB, "ok", [], null)
    compare(armedKeysOf(a), [tc.rootA, tc.rootB].sort().join(","), "non-array runs still arm")
    a.snapshotReplied(tc.rootA, "ok", [], null)
    a.snapshotReplied(tc.rootA, "ok", [], "garbage")
    compare(toastIdsOf(a), "a1,a2", "and raise nothing")
    compare(armedKeysOf(a), [tc.rootA, tc.rootB].sort().join(","))
  }

  // S10
  function test_opening_disarms_and_closing_disarms_and_empties_the_toasts() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    compare(a.toasts.length, 1)
    compare(a.toastTimer.running, true, "open with a toast: the timer runs")
    a.active = false
    compare(JSON.stringify(a.armedRoots), "{}", "closing disarms")
    compare(a.toasts.length, 0, "and empties the toasts")
    compare(a.toastTimer.running, false)
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a2")])
    compare(a.alertsArmed, false, "a reply after closing arms nothing")
    compare(a.toasts.length, 0, "and raises nothing")
    a.raiseAlerts([{ id: "z", title: "t", state: "escalated", reason: "r" }])
    compare(toastIdsOf(a), "z", "raiseAlerts itself does not check active")
    compare(a.toastTimer.running, false, "closed: no timer")
    // synthetic: an arming left in place while closed.
    a.armedRoots = ({ "/home/u/c": true })
    a.active = true
    compare(JSON.stringify(a.armedRoots), "{}", "opening disarms")
    compare(toastIdsOf(a), "z", "opening empties no toast")
    compare(a.toastTimer.running, true)
    a.snapshotReplied(tc.rootA, "ok", [], [escalatedRun("a1")])
    compare(toastIdsOf(a), "z", "the first ok reply after opening only arms")
    compare(armedKeysOf(a), tc.rootA)
  }

  // S11
  function test_a_root_no_registry_entry_names_loses_its_arming() {
    var a = makeAlerts(); if (!a) return
    a.projectRoots = registry([tc.rootA, tc.rootB])
    a.active = true
    a.snapshotReplied(tc.rootA, "ok", [], [])
    a.snapshotReplied(tc.rootB, "ok", [], [])
    a.raiseAlerts([{ id: "t1", title: "t", state: "escalated", reason: "r", project: "beta" }])
    var toasts = a.toasts
    a.projectRoots = registry([tc.rootA, tc.rootC])
    compare(armedKeysOf(a), tc.rootA, "no entry names B: its arming goes")
    verify(a.toasts === toasts, "no toast is touched")
    var armed = a.armedRoots
    // synthetic: entries the run store would skip, around A renamed.
    a.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootC), null, "x", { name: "none" }]
    verify(a.armedRoots === armed, "no armed root went: the map is not replaced")
    a.projectRoots = [rootEntry(tc.rootA), rootEntry(tc.rootA)]
    verify(a.armedRoots === armed, "a duplicate entry keeps A")
    a.projectRoots = []
    compare(armedKeysOf(a), "", "an empty registry arms nothing")
    a.snapshotReplied(tc.rootA, "ok", [], [])
    compare(armedKeysOf(a), tc.rootA)
    // synthetic: no registry at all.
    a.projectRoots = null
    compare(armedKeysOf(a), "", "a registry that is not a list names no root")
    verify(a.toasts === toasts, "and still touches no toast")
  }

  // S12
  function test_notifications_follow_the_switch() {
    var a = armedAlerts([tc.rootA]); if (!a) return
    a.notifyOnEscalation = true
    a.snapshotReplied(tc.rootA, "ok", [runningRun("a1")], [escalatedRun("a1")])
    compare(a.notifyRunners.length, 1, "one runner per alert")
    var proc = a.notifyRunners[0].current
    compare(argv(proc), tc.notifyCmd + "m-a1|escalated")
    compare(proc.command.length, 4)
    compare(proc.launchGuard, "", "guard \"\"")
    compare(proc.running, true)
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(a.notifyRunners.length, 0, "the runner goes when its process exits")
    a.notifyOnEscalation = false
    a.snapshotReplied(tc.rootA, "ok", [escalatedRun("a1")], [escalatedRun("a1"), deadRun("a2")])
    compare(toastIdsOf(a), "a1,a2")
    compare(a.notifyRunners.length, 0, "the switch is off: toasts only")
  }
}
