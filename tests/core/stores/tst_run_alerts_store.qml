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


  // ---- through a RunStore wired the way App wires app.runAlerts

  // A RunStore wired to its own RunAlertsStore (wireAlerts).
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireAlerts(store)
    return store
  }

  // Every {store, alerts} pair wireAlerts made.
  property var alertsPairs: []

  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active and projectRoots bound to the run store's own;
  // snapshotReplied routed to it. notifyOnEscalation is left to each test.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
    a.active = Qt.binding(function() { return store.active })
    a.projectRoots = Qt.binding(function() { return store.projectRoots })
    store.snapshotReplied.connect(a.snapshotReplied)
    tc.alertsPairs = tc.alertsPairs.concat([{ store: store, alerts: a }])
    return a
  }

  // The RunAlertsStore wireAlerts paired with `store`; null when none.
  function alerts(store) {
    for (var i = 0; i < tc.alertsPairs.length; i++) {
      if (tc.alertsPairs[i].store === store) return tc.alertsPairs[i].alerts
    }
    return null
  }

  // A store with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var store = make(); if (!store) return null
    store.projectRoots = registry(roots)
    return store
  }

  // An active store (the panel is open) with `roots` registered and no
  // project open: the snapshot of every root is in flight.
  function activeRoots(roots) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = registry(roots)
    return store
  }

  // A store with one registered project, `root`, open: its first snapshot (of
  // that root alone) is in flight.
  function makeWithProject(root) {
    var store = make(); if (!store) return null
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // An active store (the panel is open) with project `root` registered and
  // open: its first snapshot is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // One snapshot entry: an `am runs` summary whose `status` string the helper
  // has replaced with the `am status` data. Its repo_dir is `root`, else rootA.
  function entry(id, runStatus, live, root) {
    var run = { id: id, milestone_id: "m-" + id }
    if (runStatus !== "") run.status = runStatus
    return {
      id: id, workflow: "orchestrator", repo_dir: root || tc.rootA, started_at: "2026-10-01T00:00:00Z",
      status: {
        run: run,
        rows: [],
        stories: [],
        subtasks: [],
        control: { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: live } }
      }
    }
  }

  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // One root's entry that failed with {type, message}.
  function failEntry(root, type, message) {
    return { root: root, ok: false, error: { type: type, message: message } }
  }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir. The store ignores a root it has not registered.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // The next snapshot of project A lists `entries`.
  function snapshot(store, entries) {
    store.refresh()
    reply(store.snapshotRunner.current, okReply(entries), 0)
  }

  // entry() for the control tests: the run's workflow ("milestone" unless
  // given), its am control requests, and whether its lease accepts requests.
  function ctlEntry(id, runStatus, live, workflow, requests, accepting) {
    var e = entry(id, runStatus, live)
    e.workflow = workflow || "milestone"
    e.status.control.requests = requests || []
    if (accepting === false) e.status.control.lease.accepting = false
    return e
  }

  function running(id) { return ctlEntry(id, "started", true) }

  function dead(id) { return ctlEntry(id, "started", false) }

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  // One stdout line of a watch: an object is sent as its JSON, a string as is.
  function sendLine(proc, value) {
    proc.stdout.read(typeof value === "string" ? value : JSON.stringify(value))
  }

  // synthetic: one runs-watch.py changed line, {"changed": [{run, seq}, ...]},
  // for pairs [run, seq, run, seq, ...].
  function nudge(store, pairs) {
    var list = []
    for (var i = 0; i < pairs.length; i += 2) list.push({ run: pairs[i], seq: pairs[i + 1] })
    sendLine(store.watchProc, { changed: list })
  }

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  // An active store with A, B and C registered and no project open, whose
  // first snapshot listed a1 under A, b1 under B and c1 under C (all done):
  // its watch runs and nothing is in flight.
  function threeRoots() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }
  function escalated(id) { return entry(id, "escalated", false) }

  function toastIds(store) { return alerts(store).toasts.map(function(t) { return t.id }).join(",") }

  // The armed roots of `store`, sorted, comma-joined.
  function armedKeys(store) { return Object.keys(alerts(store).armedRoots).sort().join(",") }

  function bothRoots() { return [tc.rootA, tc.rootB].sort().join(",") }

  // The next list reply of `store`: a snapshot of every root, answered with `projects`.
  function answer(store, projects) {
    store.refresh()
    reply(store.snapshotRunner.current, allReply(projects), 0)
  }

  // An active store with A and B registered and no project open, whose first
  // reply listed `aRuns` under A and `bRuns` under B: both are armed, nothing raised.
  function armedTwo(aRuns, bRuns) {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, aRuns), okEntry(tc.rootB, bRuns)]), 0)
    compare(armedKeys(store), bothRoots(), "the first reply arms both")
    compare(alerts(store).alertsArmed, true)
    compare(alerts(store).toasts.length, 0, "and raises nothing")
    return store
  }

  // An active store on project A whose first snapshot listed `entries`: that
  // snapshot only armed the alerts.
  function armedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    compare(alerts(store).alertsArmed, true, "the first good snapshot while open arms the alerts")
    compare(alerts(store).toasts.length, 0, "and raises nothing")
    return store
  }

  // Kept behaviour: a refresh that escalates a run raises one toast.
  function test_a_nudge_refresh_that_escalates_a_run_raises_one_toast() {
    var store = threeRoots(); if (!store) return
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(alerts(store).toasts.length, 1)
    compare(alerts(store).toasts[0].id, "b1")
    compare(alerts(store).toasts[0].state, "escalated")
    nudge(store, ["b1", 6])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(alerts(store).toasts.length, 1, "still escalated: no second toast")
  }
  // ---- alerts: the toasts (S2 4.4)

  // 1
  function test_no_toast_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    compare(alerts(store).alertsArmed, false)
    compare(alerts(store).toasts.length, 0)
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 0)
    compare(alerts(store).alertsArmed, false, "a closed panel never arms")
  }

  // 2
  function test_a_run_that_turns_escalated_raises_one_toast() {
    var store = activeStore(rootA); if (!store) return
    compare(alerts(store).toastMs, 8000)
    reply(store.snapshotRunner.current, okReply([escalated("a"), running("b")]), 0)
    compare(alerts(store).toasts.length, 0, "the first snapshot after opening never replays history")
    compare(alerts(store).alertsArmed, true)
    var before = Date.now()
    snapshot(store, [escalated("a"), escalated("b")])
    compare(alerts(store).toasts.length, 1)
    var t = alerts(store).toasts[0]
    compare(t.id, "b")
    compare(t.title, "m-b")
    compare(t.state, "escalated")
    compare(t.reason, Runs.escalationReason(store.runById("b")))
    compare(t.reason, "escalated")
    compare(typeof t.key, "number")
    verify(t.expiresMs >= before + 8000 && t.expiresMs <= Date.now() + 8000, "it expires 8 s from now")
  }

  // 3
  function test_a_run_still_escalated_raises_nothing_again() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 1)
    var key = alerts(store).toasts[0].key
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 1)
    compare(alerts(store).toasts[0].key, key, "the same toast, not a new one")
  }

  // 4 (Review focus: reopening never replays history)
  function test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), running("b")])
    compare(alerts(store).toasts.length, 1)
    store.active = false
    compare(alerts(store).toasts.length, 0, "a toast never outlives the panel opening")
    compare(alerts(store).alertsArmed, false)
    store.active = true
    compare(alerts(store).alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("a"), dead("b")]), 0)
    compare(alerts(store).toasts.length, 0, "b died while the panel was closed: not replayed")
    compare(alerts(store).alertsArmed, true)
    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(toastIds(store), "c")
  }

  // Review Focus 1 (D3)
  function test_a_snapshot_landing_after_the_panel_closed_raises_nothing_and_does_not_arm() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    var late = store.snapshotRunner.current
    store.active = false
    reply(late, okReply([escalated("a")]), 0)
    compare(store.runs[0].status, "escalated", "the snapshot itself is still applied")
    compare(alerts(store).toasts.length, 0)
    compare(alerts(store).alertsArmed, false)
  }

  // 5
  function test_am_missing_disarms_and_a_failed_snapshot_does_not() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed")]), 0)
    compare(store.runs.length, 0)
    compare(alerts(store).alertsArmed, false)
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 0, "the first good snapshot after am came back raises nothing")
    compare(alerts(store).alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "b", "the one after that compares normally")

    var other = armedStore([running("x")]); if (!other) return
    other.refresh()
    reply(other.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(alerts(other).alertsArmed, true, "a failed snapshot keeps the baseline")
    other.refresh()
    reply(other.snapshotRunner.current, "garbage\n", 1)
    compare(alerts(other).alertsArmed, true)
    snapshot(other, [escalated("x")])
    compare(toastIds(other), "x")
  }

  // 6
  function test_five_alerts_in_one_snapshot_leave_the_last_three_toasts() {
    var store = armedStore([]); if (!store) return
    snapshot(store, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(toastIds(store), "r3,r4,r5")
    verify(alerts(store).toasts[0].key < alerts(store).toasts[1].key && alerts(store).toasts[1].key < alerts(store).toasts[2].key, "keys only grow")
    compare(alerts(store).toasts[0].state, "dead")
    compare(alerts(store).toasts[0].reason, "process died")
  }

  // 7
  function test_a_run_that_alerts_again_replaces_its_own_toast() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    var oldKey = alerts(store).toasts[0].key
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a", "a's old toast went and its new one is the newest")
    compare(alerts(store).toasts[1].state, "dead")
    compare(alerts(store).toasts[1].reason, "process died")
    verify(alerts(store).toasts[1].key > oldKey, "a new key")
  }

  // 8
  function test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    var timer = alerts(store).toastTimer
    compare(timer.objectName, "toastTimer")
    compare(timer.interval, 250)
    compare(timer.repeat, true)
    compare(timer.running, false, "no toast: no timer")
    snapshot(store, [escalated("a"), running("b")])
    compare(timer.running, true)
    var aExpires = alerts(store).toasts[0].expiresMs
    alerts(store).toastMs = 60000
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    alerts(store).expireToasts(aExpires - 1)
    compare(toastIds(store), "a,b", "not yet")
    alerts(store).expireToasts(aExpires)
    compare(toastIds(store), "b", "expiresMs <= now goes")
    alerts(store).dismissAllToasts()
    compare(timer.running, false, "nothing left: no timer")
    alerts(store).toastMs = 50
    snapshot(store, [escalated("a"), dead("b")])
    compare(alerts(store).toasts.length, 1)
    tryVerify(function() { return alerts(store).toasts.length === 0 }, 2000, "the timer dropped the expired toast")
    compare(timer.running, false)
  }

  // 9 (and Review Focus 2)
  function test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    var keyA = alerts(store).toasts[0].key
    alerts(store).dismissToast(-12345)
    compare(toastIds(store), "a,b", "an unknown key changes nothing")
    alerts(store).dismissToast(keyA)
    compare(toastIds(store), "b")
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a")
    alerts(store).dismissToast(keyA)
    compare(toastIds(store), "b,a", "a's stale key leaves its newer toast")
    alerts(store).dismissAllToasts()
    compare(alerts(store).toasts.length, 0)
  }

  // 10 (the toast half; Task 2 pins the setting half)
  function test_a_project_switch_keeps_the_toasts_and_the_alerts_armed() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(alerts(store).toasts.length, 1)
    store.project = rootB
    compare(alerts(store).toasts.length, 1)
    compare(alerts(store).alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b", "the next snapshot compares as before")
  }
  // ---- alerts across projects (3.4)

  // 1
  function test_an_escalation_in_another_project_raises_one_toast_with_its_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    compare(store.project, "")
    alerts(store).notifyOnEscalation = true
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "b1")
    compare(alerts(store).toasts[0].project, "beta")
    compare(alerts(store).toasts[0].title, "m-b1")
    compare(alerts(store).toasts[0].state, "escalated")
    compare(alerts(store).notifyRunners.length, 1, "one notification")
    compare(argv(alerts(store).notifyRunners[0].current), tc.notifyCmd + "m-b1|escalated", "its text does not change")
  }

  // 2
  function test_a_project_that_first_fails_or_joins_later_only_arms_on_its_first_good_entry() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(armedKeys(store), tc.rootA, "only A answered")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2")])])
    compare(alerts(store).toasts.length, 0, "B's first good entry only arms")
    compare(armedKeys(store), bothRoots())
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2"), escalated("b3")])])
    compare(toastIds(store), "b3", "the entry after that compares normally")
    compare(alerts(store).toasts[0].project, "beta")
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]),
                                                  okEntry(tc.rootB, [escalated("b1"), dead("b2"), escalated("b3")]),
                                                  okEntry(tc.rootC, [escalated("c1")])]), 0)
    compare(toastIds(store), "b3", "a project added later: its first entry raises nothing")
    compare(armedKeys(store), [tc.rootA, tc.rootB, tc.rootC].sort().join(","), "and arms it")
  }

  // 3
  function test_a_failing_project_raises_nothing_and_stays_armed() {
    var store = armedTwo([running("a1")], [running("b1"), escalated("b2")]); if (!store) return
    answer(store, [okEntry(tc.rootA, [running("a1")]), failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")])
    compare(alerts(store).toasts.length, 0, "a failed entry raises nothing")
    compare(ids(store.runsByProject[tc.rootB]), "b1,b2", "B keeps its runs")
    compare(armedKeys(store), bothRoots(), "and stays armed")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), escalated("b2")])])
    compare(toastIds(store), "b1", "the recovery compares against the kept runs: b2 is not replayed")
    compare(alerts(store).toasts[0].project, "beta")
  }

  // 4
  function test_an_am_missing_spell_disarms_every_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmMissing", "am is not installed."), failEntry(tc.rootB, "AmMissing", "am is not installed.")])
    compare(armedKeys(store), "")
    compare(alerts(store).alertsArmed, false)
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(alerts(store).toasts.length, 0, "the next good reply only arms")
    compare(armedKeys(store), bothRoots())
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), failEntry(tc.rootB, "AmMissing", "am is not installed.")])
    compare(store.amStatus, "ok", "AmMissing beside an ok entry is no spell")
    compare(ids(store.runsByProject[tc.rootB]), "b1", "B keeps its runs")
    compare(armedKeys(store), bothRoots(), "and its armed state")
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2")])])
    compare(toastIds(store), "b2")
  }

  // 5 and Review Focus 4
  function test_a_run_listed_under_two_roots_alerts_once_under_the_first() {
    var store = armedTwo([running("x")], [running("x")]); if (!store) return
    alerts(store).notifyOnEscalation = true
    // B's entry first: the registry's order decides, not the reply's.
    answer(store, [okEntry(tc.rootB, [escalated("x")]), okEntry(tc.rootA, [escalated("x")])])
    compare(toastIds(store), "x")
    compare(alerts(store).toasts[0].project, "alpha")
    compare(alerts(store).notifyRunners.length, 1, "one notification")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "B owns x now")
    compare(alerts(store).toasts.length, 1, "a new owner replays nothing")
    compare(alerts(store).notifyRunners.length, 1)
  }

  // 5: the owner decides, even when only the other root answers
  function test_a_run_listed_under_two_roots_alerts_only_from_its_owners_entry() {
    var store = armedTwo([running("x")], [running("x")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."), okEntry(tc.rootB, [escalated("x")])])
    compare(store.runs[0].project.root, tc.rootA, "A still owns x")
    compare(alerts(store).toasts.length, 0, "B's entry never alerts a run A owns")
    answer(store, [okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])])
    compare(toastIds(store), "x", "A's own entry does")
    compare(alerts(store).toasts[0].project, "alpha")
  }

  // Review Focus 1, 2 and 3
  function test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone() {
    // synthetic: a run without an id under B.
    var store = armedTwo([running("a1")], [running("b1"), entry("", "started", true)]); if (!store) return
    var armed = alerts(store).armedRoots
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage", message: "usage" } }) + "\n", 2)
    verify(alerts(store).armedRoots === armed, "a whole-call failure leaves the arming alone")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    verify(alerts(store).armedRoots === armed, "so does garbage")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [escalated("b1"), entry("", "escalated", false)])]), 0)
    compare(toastIds(store), "b1", "a run without an id never alerts")
    compare(alerts(store).toasts[0].project, "beta")
    compare(armedKeys(store), bothRoots(), "A, with no entry, stays armed")
    compare(ids(store.runsByProject[tc.rootA]), "a1")
  }

  // 7
  function test_a_project_switch_keeps_the_toasts_and_every_projects_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [running("b1")])])
    compare(toastIds(store), "a1")
    compare(alerts(store).toasts[0].project, "alpha")
    var toasts = alerts(store).toasts
    var armed = alerts(store).armedRoots
    var targets = [tc.rootA, ""]
    for (var i = 0; i < targets.length; i++) {
      var label = "project " + JSON.stringify(targets[i])
      store.project = targets[i]
      verify(alerts(store).toasts === toasts, label + ": the toasts")
      verify(alerts(store).armedRoots === armed, label + ": the arming")
    }
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "a1,b1", "the next escalation still alerts")
    compare(alerts(store).toasts[1].project, "beta")
  }

  // the closed panel (spec §2)
  function test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [running("b1")])]), 0)
    compare(armedKeys(store), "", "a closed panel never arms")
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(alerts(store).toasts.length, 0)
    compare(armedKeys(store), "")
    compare(ids(store.runs), "a1,b1", "the runs are still applied")
  }

  // 6
  function test_a_root_that_leaves_the_registry_loses_its_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    store.projectRoots = registry([tc.rootA])
    compare(armedKeys(store), tc.rootA, "B left: its arming goes at once")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")])]), 0)
    store.projectRoots = registry([tc.rootA, tc.rootB])
    compare(armedKeys(store), tc.rootA, "coming back does not re-arm")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])]), 0)
    compare(alerts(store).toasts.length, 0, "its next good entry only arms")
    compare(armedKeys(store), bothRoots())
    var armed = alerts(store).armedRoots
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB)]
    verify(alerts(store).armedRoots === armed, "no root went: the map is not replaced")
    store.projectRoots = []
    compare(armedKeys(store), "", "an empty registry arms nothing")
  }
  // ---- alerts: the desktop notifications (S2 4.4)

  // 12
  function test_with_the_setting_on_each_alert_launches_its_own_notification() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    compare(alerts(store).notifyRunners.length, 0)
    alerts(store).notifyOnEscalation = true
    snapshot(store, [escalated("a"), dead("b")])
    compare(alerts(store).notifyRunners.length, 2, "one runner per alert")
    var first = alerts(store).notifyRunners[0].current, second = alerts(store).notifyRunners[1].current
    compare(argv(first), tc.notifyCmd + "m-a|escalated")
    compare(argv(second), tc.notifyCmd + "m-b|process died")
    compare(first.running, true, "the second launch did not stop the first")
    compare(second.running, true)
    compare(first.launchGuard, "")
    reply(first, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(alerts(store).notifyRunners.length, 1)
    reply(second, "garbage\n", 1)
    compare(alerts(store).notifyRunners.length, 0, "a failed notification goes too")
    compare(toastIds(store), "a,b", "the replies change nothing else")

    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(alerts(store).notifyRunners.length, 1)
    var proc = alerts(store).notifyRunners[0].current
    store.project = rootB
    compare(proc.running, true, "a project switch does not stop a launched notification")
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(alerts(store).notifyRunners.length, 0)

    var off = armedStore([running("a")]); if (!off) return
    snapshot(off, [escalated("a")])
    compare(alerts(off).toasts.length, 1)
    compare(alerts(off).notifyRunners.length, 0, "setting off: toasts only")

    var five = armedStore([]); if (!five) return
    alerts(five).notifyOnEscalation = true
    snapshot(five, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(alerts(five).toasts.length, 3)
    compare(alerts(five).notifyRunners.length, 5, "every alert notifies, even those whose toast was capped away")
  }

  // 1 (the notification half)
  function test_no_notification_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    alerts(store).notifyOnEscalation = true
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(alerts(store).notifyRunners.length, 0)
    compare(alerts(store).toasts.length, 0)
  }
}
