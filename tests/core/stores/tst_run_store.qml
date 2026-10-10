// tests/core/stores/tst_run_store.qml
// The run monitor's store: the snapshot helper's exact argv, how its one JSON
// line becomes every registered root's normalized runs and an amStatus, the
// one-in-flight-plus-one-pending rule, what a registry change does and what a
// project switch leaves alone, the snapshotReplied it emits, and the Runs
// screen's list over the snapshot plus the history App hands it. Built
// directly, wired to a RunControlStore and a RunAlertsStore the way App wires
// app.runControl and app.runAlerts (and, where a test needs it, a
// RunDispatchStore the way App wires app.runDispatch), and driven through
// stubbed Process objects. The run controls and the notify switch are tested in
// tst_run_control_store.qml, the alerts in tst_run_alerts_store.qml. The
// dispatch is tested in tst_run_dispatch_store.qml, the run settings load
// and save in tst_run_control_store.qml.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "StoresRunStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
  property string watchCmd: "python3|/plugin/core/backend/runs/runs-watch.py"
  // The recorded escalated run (status-escalated.json) and the recorded
  // finished Integrate run (status-done-integrate.json).
  readonly property string escRun: "20261008T143755Z-f18d342f"
  readonly property string doneIntRun: "20261008T143803Z-f7f73454"
  property string logsCmd: "python3|/plugin/core/backend/runs/runs-logs.py|" + rootA + "|"
  // The started capture's open subtask (explore attempt 1 is started) and a
  // done subtask of it (spec attempt 1 is ok).
  readonly property string openCard: "2280a6ab-9c40-434b-9729-63fd1f373754"
  readonly property string doneCard: "5560d0fe-2b8e-4ef9-ad71-96b50ee89daa"

  Component { id: spyC; SignalSpy {} }

  // A RunStore wired to its own RunControlStore (wireControl), then to its
  // own RunAlertsStore (wireAlerts): App's snapshotReplied order.
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    wireControl(store)
    wireAlerts(store)
    return store
  }

  // Every {store, control} pair wireControl made.
  property var controlPairs: []

  // A RunControlStore wired to `store` the way App wires app.runControl:
  // backendDir copied; project, active and runs bound to the run store's own;
  // an ok snapshotReplied settles its requests; its refreshRequested goes to
  // refresh() ("all") or requestSnapshot(roots).
  function wireControl(store) {
    var comp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var c = comp.createObject(tc, { backendDir: store.backendDir })
    c.project = Qt.binding(function() { return store.project })
    c.active = Qt.binding(function() { return store.active })
    c.runs = Qt.binding(function() { return store.runs })
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
    c.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    tc.controlPairs = tc.controlPairs.concat([{ store: store, control: c }])
    return c
  }

  // The RunControlStore wireControl paired with `store`; null when none.
  function controlOf(store) {
    for (var i = 0; i < tc.controlPairs.length; i++) {
      if (tc.controlPairs[i].store === store) return tc.controlPairs[i].control
    }
    return null
  }

  // Every {store, alerts} pair wireAlerts made.
  property var alertsPairs: []

  // A RunAlertsStore wired to `store` the way App wires app.runAlerts:
  // backendDir copied; active and projectRoots bound to the run store's own,
  // notifyOnEscalation bound to the paired control store's; snapshotReplied
  // routed to it.
  function wireAlerts(store) {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var a = comp.createObject(tc, { backendDir: store.backendDir })
    a.active = Qt.binding(function() { return store.active })
    a.notifyOnEscalation = Qt.binding(function() { var c = controlOf(store); return c ? c.notifyOnEscalation : false })
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

  // Every {store, dispatch} pair wireDispatch made.
  property var dispatchPairs: []

  // A RunDispatchStore with backendDir copied. When `bound`, it is wired the
  // way App wires app.runDispatch: project, active and runs bound to the run
  // store's own, runSettings to the paired control store's
  // runSettingsOf(project); refreshRequested to refresh() ("all") or
  // requestSnapshot(roots); noticeRequested to the paired control store's
  // flash; runSettingsWanted and runSettingsSaveRequested to its
  // loadRunSettings and saveRunSettings, and its runSettingsSaveFailed back to
  // dispatchSaveFailed. Otherwise nothing is bound or routed.
  function wireDispatch(store, bound) {
    var comp = Qt.createComponent("../../../core/stores/RunDispatchStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var d = comp.createObject(tc, { backendDir: store.backendDir })
    if (bound) {
      d.project = Qt.binding(function() { return store.project })
      d.active = Qt.binding(function() { return store.active })
      d.runs = Qt.binding(function() { return store.runs })
      d.runSettings = Qt.binding(function() { return controlOf(store).runSettingsOf(store.project) })
      d.refreshRequested.connect(function(roots) {
        if (roots === "all") store.refresh()
        else store.requestSnapshot(roots)
      })
      d.noticeRequested.connect(function(text) { controlOf(store).flash(text) })
      var c = controlOf(store)
      d.runSettingsWanted.connect(function(root) { c.loadRunSettings(root) })
      d.runSettingsSaveRequested.connect(function(root, patch) { c.saveRunSettings(root, patch) })
      c.runSettingsSaveFailed.connect(function(root, patch) { d.dispatchSaveFailed(root, patch) })
    }
    tc.dispatchPairs = tc.dispatchPairs.concat([{ store: store, dispatch: d }])
    return d
  }

  // The RunDispatchStore wireDispatch paired with `store`; null when none.
  function dispatchOf(store) {
    for (var i = 0; i < tc.dispatchPairs.length; i++) {
      if (tc.dispatchPairs[i].store === store) return tc.dispatchPairs[i].dispatch
    }
    return null
  }

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
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

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
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

  // A recorded snapshot entry, {...am runs row, status: am status data}:
  // "started" and "done" are runs.json's two rows with status-started.json's
  // and status-done.json's data; any other name is status-<name>.json's
  // _am_runs_row with its data.
  function rec(name) {
    if (name === "started" || name === "done") {
      var row = F.load("runs.json").data.runs[name === "started" ? 0 : 1]
      row.status = F.load("status-" + name + ".json").data
      return row
    }
    var fixture = F.load("status-" + name + ".json")
    var out = fixture._am_runs_row
    out.status = fixture.data
    return out
  }

  // ---- the snapshot of every registered root (3.1)

  // 1
  function test_the_snapshot_names_every_usable_root_in_registry_order() {
    var store = make(); if (!store) return
    compare(store.project, "")
    store.projectRoots = [rootEntry(tc.rootA), rootEntry(tc.rootB)]
    var proc = store.snapshotRunner.current
    verify(proc, "a registry with roots launches a snapshot, with no project open")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
    compare(proc.command[2], tc.rootA, "a root with a space is one argument")
    compare(proc.launchGuard, "", "the snapshot has no guard")
    // synthetic: registry entries runs-snapshot-all.py would refuse, and repeats.
    store.projectRoots = [{ root: "", name: "empty" }, { root: "-x", name: "dash" }, { root: 7, name: "num" },
                          { name: "none" }, null, "/home/u/str", [tc.rootC], rootEntry(tc.rootA),
                          { root: tc.rootA, name: "again" }, rootEntry(tc.rootB)]
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB,
            "unusable and repeated roots are left out")
    store.refresh()
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, "refresh() names the same roots")
  }

  // 1 (no usable root) and Review Focus 2
  function test_no_usable_root_launches_nothing_and_empties_the_outputs() {
    var bare = make(); if (!bare) return
    bare.projectRoots = [{ root: "", name: "x" }, { root: "-y", name: "y" }, null]
    verify(!bare.snapshotRunner.current, "no usable root: nothing is launched")
    bare.refresh()
    verify(!bare.snapshotRunner.current, "refresh() launches nothing either")

    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.runs.length, 1)
    compare(Object.keys(store.projectErrors).join(","), tc.rootB)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    store.projectRoots = []
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0)
    compare(Object.keys(store.projectErrors).length, 0)
    compare(store.snapshotRunner.busy, false, "nothing is in flight")
    compare(inFlight.running, false, "the snapshot in flight was stopped")
    reply(inFlight, allReply([okEntry(tc.rootA, [rec("started")])]), 0)
    compare(store.runs.length, 0, "its late reply changes nothing")
    compare(store.amStatus, "ok", "and raises no banner")
  }

  // 2
  function test_runs_merge_every_root_in_registry_order_with_its_project() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [rec("done")]),
                                                  okEntry(tc.rootA, [rec("started"), rec("escalated")])]), 0)
    compare(ids(store.runsByProject[tc.rootA]), tc.startedRun + "," + tc.escRun, "A's runs in am's order")
    compare(ids(store.runsByProject[tc.rootB]), tc.doneRun)
    compare(ids(store.runs), [tc.startedRun, tc.escRun, tc.doneRun].join(","), "A then B, whatever the reply's order")
    compare(JSON.stringify(store.runs[0].project), JSON.stringify({ root: tc.rootA, name: "alpha" }))
    compare(JSON.stringify(store.runs[2].project), JSON.stringify({ root: tc.rootB, name: "beta" }))
    compare(store.runs[0].status, "started", "normalized from the recorded am status")
    verify(store.runs[0].tree.stories.length > 0, "the recorded tree")
    compare(Object.keys(store.projectErrors).length, 0)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    compare(ids(store.runs), [tc.doneRun, tc.startedRun, tc.escRun].join(","), "the registry's order decides")
  }

  // 3
  function test_a_run_listed_under_two_roots_is_listed_once_under_the_first() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    // synthetic: the same recorded run under both roots, and a run without an id under each.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started"), entry("", "started", true)]),
                                                  okEntry(tc.rootB, [rec("started"), rec("done"), entry("", "done", false)])]), 0)
    compare(ids(store.runs), [tc.startedRun, "", tc.doneRun, ""].join(","))
    compare(store.runs[0].project.root, tc.rootA, "the first root wins")
    compare(store.runs[3].project.root, tc.rootB, "runs without an id are never de-duplicated")
    compare(ids(store.runsByProject[tc.rootB]), [tc.startedRun, tc.doneRun, ""].join(","), "B keeps its own copy")
    compare(store.runsByProject[tc.rootB][0].project.root, tc.rootB)
    compare(Object.keys(store.appliedSeq).sort().join(","), [tc.startedRun, tc.doneRun].sort().join(","))
  }

  // 4 and Review Focus 5
  function test_a_failing_root_keeps_its_runs_and_says_why() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("escalated")])]), 0)
    compare(alerts(store).alertsArmed, true)
    compare(alerts(store).toasts.length, 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started"), rec("done-integrate")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(ids(store.runsByProject[tc.rootA]), tc.startedRun + "," + tc.doneIntRun, "A is updated")
    compare(ids(store.runsByProject[tc.rootB]), tc.escRun, "B keeps its previous runs")
    compare(ids(store.runs), [tc.startedRun, tc.doneIntRun, tc.escRun].join(","))
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    compare(Object.keys(store.projectErrors).join(","), tc.rootB)
    compare(store.amStatus, "ok", "A answered")
    compare(store.lastError, "")
    compare(alerts(store).toasts.length, 0, "a failed entry raises nothing")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("escalated")])]), 0)
    compare(Object.keys(store.projectErrors).length, 0, "a good entry clears B's error")
    compare(alerts(store).toasts.length, 0, "B's recovery replays no alert")

    var first = makeWithRoots([tc.rootA, tc.rootB]); if (!first) return
    reply(first.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "RootMissing", tc.rootB + " is not a directory.")]), 0)
    verify(Object.keys(first.runsByProject).indexOf(tc.rootB) >= 0, "a first failure still lists B")
    compare(first.runsByProject[tc.rootB].length, 0)
    compare(first.projectErrors[tc.rootB], "RootMissing: /home/u/b is not a directory.")
    compare(first.amStatus, "ok")
  }

  // 5
  function test_when_no_root_answers_the_snapshot_is_an_error_and_keeps_the_runs() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "StoreBusyError", "the am store is busy; try again"),
                                                  failEntry(tc.rootB, "SchemaMismatch", "the plugin needs the newer am")]), 0)
    compare(store.amStatus, "error")
    compare(store.lastError, "StoreBusyError: the am store is busy; try again", "the first failed entry in reply order")
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun, "the previous runs stay")
    compare(store.projectErrors[tc.rootA], "StoreBusyError: the am store is busy; try again")
    compare(store.projectErrors[tc.rootB], "SchemaMismatch: the plugin needs the newer am")
    compare(alerts(store).alertsArmed, true, "the armed state is unchanged")
    compare(store.stale, true, "stale is unchanged")

    var closed = makeWithRoots([tc.rootA]); if (!closed) return
    reply(closed.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(alerts(closed).alertsArmed, false, "a disarmed store stays disarmed")
    compare(closed.amStatus, "error")
  }

  // 6
  function test_am_missing_in_every_entry_empties_everything() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(alerts(store).alertsArmed, true)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed."),
                                                  failEntry(tc.rootB, "AmMissing", "am is not installed.")]), 0)
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0)
    compare(Object.keys(store.projectErrors).length, 0)
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.amStatus, "missing")
    compare(store.lastError, "AmMissing: am is not installed.")
    compare(alerts(store).alertsArmed, false)
    store.refresh()
    // synthetic: AmMissing beside another failure is not "am is missing".
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed."),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.amStatus, "error")
    compare(store.lastError, "AmMissing: am is not installed.")
  }

  // 7 and Review Focus 3
  function test_a_whole_call_failure_or_garbage_keeps_everything() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage",
          message: "usage: runs-snapshot-all.py <root> [<root> ...]" } }) + "\n", 2)
    compare(store.amStatus, "error")
    compare(store.lastError, "Usage: usage: runs-snapshot-all.py <root> [<root> ...]")
    compare(ids(store.runs), tc.startedRun)
    compare(Object.keys(store.runsByProject).sort().join(","), [tc.rootA, tc.rootB].sort().join(","))
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    store.refresh()
    reply(store.snapshotRunner.current, "Traceback (most recent call last):\n  oops", 1)
    compare(store.amStatus, "error")
    compare(store.lastError, "The runs snapshot gave no usable result (exit 1).")
    compare(ids(store.runs), tc.startedRun)
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    store.refresh()
    // synthetic: an ok line with no entry for any registered root.
    reply(store.snapshotRunner.current, JSON.stringify({ ok: true, data_dir: "/d" }) + "\n", 0)
    compare(store.amStatus, "error")
    compare(store.lastError, "The runs snapshot gave no usable result (exit 0).")
    compare(ids(store.runs), tc.startedRun, "runs are kept")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootC, [rec("done")])]), 0)
    compare(store.lastError, "The runs snapshot gave no usable result (exit 0).", "a foreign root alone is no answer either")
    compare(ids(store.runs), tc.startedRun)
  }

  // 8
  function test_a_list_covers_every_listed_run_at_0_and_nudges_follow_it() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    // A project is open: nudges ignore it.
    store.project = tc.rootA
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    compare(store.asOfSeq, 0)
    var want = {}
    want[tc.startedRun] = 0
    want[tc.doneRun] = 0
    compare(JSON.stringify(store.appliedSeq), JSON.stringify(want))
    verify(store.watchProc, "the watch runs")
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.doneRun, 1])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "a listed run costs one snapshot of its root, whatever its seq")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [rec("done")])]), 0)
    // synthetic: a run am started after the list.
    nudge(store, ["20261008T150000Z-0a1b2c3d", 1006])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 2, "an unlisted run costs one snapshot of every root")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // 9
  function test_a_registry_change_drops_renames_adds_and_snapshots_again() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
    compare(Object.keys(store.projectErrors).join(","), tc.rootB)
    store.projectRoots = registry([tc.rootA])
    compare(ids(store.runs), tc.startedRun, "a removed project's runs leave at once")
    compare(Object.keys(store.runsByProject).join(","), tc.rootA)
    compare(Object.keys(store.projectErrors).length, 0, "and so does its error")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "then A alone is snapshotted")
    compare(alerts(store).toasts.length, 0, "the registry change raises nothing")
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }]
    compare(store.runs[0].project.name, "renamed", "a renamed project's runs carry the new name at once")
    compare(store.runsByProject[tc.rootA][0].project.name, "renamed")
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB), rootEntry(tc.rootC)]
    compare(store.pendingSnapshot, "all", "a registry change during a snapshot waits as the pending request")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")])]), 0)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC,
            "adding C snapshots every root")
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootC)]
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [rec("done")]),
                                                  okEntry(tc.rootA, [rec("started"), rec("escalated")])]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.escRun, "B's entry is ignored: B is not registered")
    compare(store.runs[1].project.name, "renamed")
    compare(Object.keys(store.runsByProject).join(","), tc.rootA, "C, with no entry, has no list yet")
    compare(store.amStatus, "ok")
  }

  // 10
  function test_a_project_switch_leaves_the_run_list_and_the_live_state_alone() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    if (!wireDispatch(store, true)) return
    store.project = tc.rootA
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [treeEntry("r1", "started"), running("r2")]),
                                                  okEntry(tc.rootB, [rec("done")])]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    compare(controlOf(store).control("pause", "r2"), true)
    reply(controlOf(store).controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [treeEntry("r1", "started"), running("r2"), escalated("r3")]),
                                                  okEntry(tc.rootB, [rec("done")])]), 0)
    compare(alerts(store).toasts.length, 1, "r3 escalated")
    compare(controlOf(store).pending.r2, "pause", "acknowledged, not yet settled")
    store.toggleRunFilter("live")
    var watch = store.watchProc
    var runs = store.runs
    var applied = store.appliedSeq
    var attempt = store.selectedAttempt
    var toasts = alerts(store).toasts
    var seq = store.snapshotRunner.seq
    var targets = [tc.rootB, ""]
    for (var i = 0; i < targets.length; i++) {
      var label = "project " + JSON.stringify(targets[i])
      store.project = targets[i]
      verify(store.runs === runs, label + ": the runs")
      verify(store.appliedSeq === applied, label + ": the coverage")
      compare(store.selectedRunId, "r1", label)
      verify(store.selectedAttempt === attempt, label + ": the attempt")
      compare(store.logsText, "kept", label)
      compare(store.runFilter, "live", label)
      verify(store.watchProc === watch, label + ": the watch")
      compare(watch.running, true, label)
      compare(store.watching, true, label)
      verify(alerts(store).toasts === toasts, label + ": the toasts")
      compare(controlOf(store).pending.r2, "pause", label)
      compare(alerts(store).alertsArmed, true, label)
      compare(store.amStatus, "ok", label)
      compare(store.snapshotRunner.seq, seq, label + ": no snapshot")
    }
    sendLine(watch, { changed: [{ run: "r2", seq: 7 }] })
    compare(store.debounceTimer.running, true, "a watch line after the switch is still handled")
    compare(store.nudges.r2, 7)
    store.project = tc.rootB
    compare(dispatchOf(store).dispatchState, "idle", "and the dispatch is still reset")
  }

  // 10
  function test_opening_a_project_launches_no_snapshot() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    var seq = store.snapshotRunner.seq
    store.project = tc.rootA
    compare(store.snapshotRunner.seq, seq, "the registry, not the open project, decides the snapshot")
    store.project = ""
    compare(store.snapshotRunner.seq, seq)
  }

  // 11
  function test_with_no_project_open_the_panel_snapshots_every_root_and_watches() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel snapshots every root")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
    compare(store.staleTimer.running, true, "the stale clock runs with no project")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("done")])]), 0)
    verify(store.watchProc, "a good reply starts the watch")
    compare(store.watching, true)
    compare(alerts(store).alertsArmed, true)
    compare(store.staleTimer.running, true)
  }

  // ---- defaults and the snapshot command

  function test_defaults_and_no_process_without_a_project() {
    var store = make(); if (!store) return
    compare(store.runs.length, 0)
    compare(store.selectedRunId, "")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.project, "")
    verify(!store.snapshotRunner.current, "no snapshot while there is no project")
    store.refresh()
    verify(!store.snapshotRunner.current, "refresh() with no project does nothing")
  }

  // ---- ok snapshots

  function test_an_ok_reply_fills_runs_with_normalized_runs() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true), entry("r2", "", false)]), 0)
    compare(store.runs.length, 2)
    compare(store.runs[0].id, "r1")
    compare(store.runs[0].status, "started", "the status comes from the nested am status data")
    compare(store.runs[0].milestone_id, "m-r1")
    verify(store.runs[0].lease !== null, "the lease comes from the nested control data")
    compare(store.runs[0].lease.live, true)
    compare(store.runs[0].lease.pid, 42)
    compare(store.runs[1].id, "r2")
    // r2's am status has no run.status: normalizeRun falls back to the row's
    // status, which must not be the status OBJECT the helper put there.
    verify(store.runs[1].status !== "[object Object]", "the summary's overwritten status is not used")
    compare(store.runs[1].status, "")
    compare(store.runs[1].lease.live, false)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  function test_an_ok_reply_without_runs_is_ok_and_empty() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.runs.length, 1)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.runs.length, 0, "runs: [] empties the list")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([{ root: tc.rootA, ok: true }]), 0)
    compare(store.runs.length, 0, "an entry without a runs key is an empty list, not an error")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  function test_a_refresh_in_the_same_project_keeps_the_selection() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    store.selectedRunId = "r1"
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r1", "done", false)]), 0)
    compare(store.selectedRunId, "r1")
    compare(store.runs[0].status, "done")
  }

  function test_the_last_non_empty_line_is_the_reply() {
    var store = makeWithProject(rootA); if (!store) return
    var text = "warning: something chatty\n" + okReply([entry("r1", "started", true)]) + "\n  \n"
    reply(store.snapshotRunner.current, text, 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r1")
    compare(store.amStatus, "ok")
  }

  function test_malformed_runs_are_skipped_without_throwing() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [null, 3, "x", [1], entry("r1", "started", true), { id: "r2" }])]), 0)
    compare(store.runs.length, 2, "only the object entries are kept")
    compare(store.runs[0].id, "r1")
    compare(store.runs[1].id, "r2", "an entry without status data still normalizes")
    compare(store.runs[1].lease, null)
    compare(store.amStatus, "ok")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([{ root: tc.rootA, ok: true, runs: { r1: {} } }]), 0)
    compare(store.runs.length, 0, "a runs value that is not an array is empty")
    compare(store.amStatus, "ok")
    store.refresh()
    // synthetic: entries that are not objects or name no root, then a good one.
    reply(store.snapshotRunner.current, allReply([null, 3, [okEntry(tc.rootA, [])], { ok: true, runs: [] },
                                                  okEntry(tc.rootA, [entry("r3", "started", true)])]), 0)
    compare(ids(store.runs), "r3", "only the entry naming a registered root counts")
  }

  // ---- errors

  // A store whose first snapshot loaded r1, ready for the next reply.
  function loaded() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.runs.length, 1)
    store.refresh()
    return store
  }

  function test_am_missing_sets_missing_and_clears_the_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing")
    compare(store.runs.length, 0, "no badges while am is missing")
    compare(store.lastError, "AmMissing: am is not installed.")
  }

  function test_another_ok_false_keeps_the_previous_runs() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "AmBadOutput", "message": "am status did not print JSON (exit 3)."}}\n', 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1, "the previous runs stay")
    compare(store.runs[0].id, "r1")
    compare(store.lastError, "AmBadOutput: am status did not print JSON (exit 3).")
  }

  function test_garbage_stdout_keeps_the_previous_runs_and_names_the_exit_code() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, "Traceback (most recent call last):\n  oops {not json", 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r1")
    verify(store.lastError !== "", "the reason is shown")
    verify(store.lastError.indexOf("exit 1") >= 0, "the exit code is named: " + store.lastError)
    store.refresh()
    reply(store.snapshotRunner.current, "", 7)
    compare(store.amStatus, "error", "empty stdout is an error too")
    compare(store.runs.length, 1)
    verify(store.lastError.indexOf("exit 7") >= 0, "the exit code is named: " + store.lastError)
  }

  function test_json_that_is_not_an_envelope_is_an_error() {
    var store = loaded(); if (!store) return
    var shapes = ["[]", '"x"', "null", "{}", '{"ok": "yes"}']
    for (var i = 0; i < shapes.length; i++) {
      reply(store.snapshotRunner.current, shapes[i], 0)
      compare(store.amStatus, "error", shapes[i] + " is not a usable reply")
      compare(store.runs.length, 1, shapes[i] + " keeps the previous runs")
      verify(store.lastError.indexOf("exit 0") >= 0, "the exit code is named: " + store.lastError)
      store.refresh()
    }
  }

  function test_ok_false_without_an_error_object_is_unknown_error() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false}', 1)
    compare(store.amStatus, "error")
    compare(store.runs.length, 1)
    compare(store.lastError, "unknown error")
  }

  function test_a_good_reply_after_an_error_restores_ok() {
    var store = loaded(); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "The runs snapshot failed: boom"}}', 1)
    compare(store.amStatus, "error")
    verify(store.lastError !== "")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("r2", "done", false)]), 0)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r2")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.amStatus, "ok", "missing recovers too")
    compare(store.lastError, "")
  }

  // ---- one snapshot in flight plus one pending request (global 3.2)

  // 7 and Review Focus 1
  function test_a_request_during_a_snapshot_waits_as_the_one_pending_request() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var inFlight = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    var all = tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC
    compare(store.snapshotRoots.join("|"), [tc.rootA, tc.rootB, tc.rootC].join("|"), "the roots in flight")
    compare(store.pendingSnapshot, null, "nothing pending yet")
    store.requestSnapshot([tc.rootC])
    store.requestSnapshot([tc.rootB, tc.rootC])
    verify(store.snapshotRunner.current === inFlight, "the snapshot in flight is never replaced")
    compare(inFlight.running, true, "nor stopped")
    compare(store.snapshotRunner.seq, seq)
    compare(store.pendingSnapshot.join("|"), [tc.rootC, tc.rootB].join("|"), "the union of the roots")
    store.refresh()
    compare(store.pendingSnapshot, "all", "all wins over any roots")
    store.requestSnapshot([tc.rootB])
    compare(store.pendingSnapshot, "all", "and stays all")
    verify(store.snapshotRunner.current === inFlight)
    compare(store.snapshotRunner.seq, seq)
    reply(inFlight, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, []), okEntry(tc.rootC, [])]), 0)
    compare(ids(store.runs), "a1", "the reply is applied")
    compare(store.snapshotRunner.seq, seq + 1, "then exactly one follow-up launches")
    compare(argv(store.snapshotRunner.current), all)
    compare(store.pendingSnapshot, null)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, []),
                                                  okEntry(tc.rootC, [])]), 0)
    compare(store.snapshotRunner.seq, seq + 1, "answering the follow-up launches nothing more")
    compare(store.snapshotRunner.busy, false)
    compare(store.snapshotRoots.length, 0, "no roots in flight when idle")
  }

  // 7
  function test_a_pending_set_of_roots_launches_those_roots_in_registry_order() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var inFlight = store.snapshotRunner.current
    store.requestSnapshot([tc.rootC])
    store.requestSnapshot([tc.rootB])
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, []), okEntry(tc.rootC, [])]), 0)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB + "|" + tc.rootC, "B and C only, in registry order")
    compare(store.snapshotRoots.join("|"), tc.rootB + "|" + tc.rootC)
  }

  // 7
  function test_a_failed_or_garbage_reply_still_launches_the_pending_request() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var replies = [[JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }), 1],
                   ["Traceback (most recent call last):", 1], ["", 0],
                   [allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s.")]), 0]]
    for (var i = 0; i < replies.length; i++) {
      var label = JSON.stringify(replies[i][0])
      var seq = store.snapshotRunner.seq
      store.refresh()
      compare(store.snapshotRunner.seq, seq, label + ": waits")
      reply(store.snapshotRunner.current, replies[i][0], replies[i][1])
      compare(store.amStatus, "error", label + " is applied")
      compare(store.snapshotRunner.seq, seq + 1, label + ": then the follow-up launches")
      compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, label)
    }
  }

  // 8 and Review Focus 4
  function test_a_pending_request_resolves_against_the_registry_at_launch() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var inFlight = store.snapshotRunner.current
    store.requestSnapshot([tc.rootB])
    store.projectRoots = registry([tc.rootA, tc.rootC])
    compare(store.pendingSnapshot, "all", "the registry change itself requests every root")
    var seq = store.snapshotRunner.seq
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                              okEntry(tc.rootC, [])]), 0)
    compare(Object.keys(store.runsByProject).sort().join(","), [tc.rootA, tc.rootC].sort().join(","), "B's entry is ignored")
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.seq, seq + 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootC, "the registry as it is now")
  }

  // 8
  function test_a_request_for_roots_no_longer_usable_launches_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var seq = store.snapshotRunner.seq
    store.requestSnapshot(["/home/u/gone"])
    compare(store.snapshotRunner.seq, seq, "an idle runner launches nothing for a root that is not registered")
    compare(store.snapshotRunner.busy, false)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    store.requestSnapshot(["/home/u/gone"])
    compare(store.pendingSnapshot.join("|"), "/home/u/gone")
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(store.snapshotRunner.seq, seq + 1, "a pending request naming no usable root launches nothing")
    compare(store.snapshotRunner.busy, false)
    compare(store.pendingSnapshot, null)
  }

  // 8
  function test_an_emptied_registry_drops_the_snapshot_in_flight_and_the_pending_request() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var inFlight = store.snapshotRunner.current
    store.refresh()
    compare(store.pendingSnapshot, "all")
    store.projectRoots = []
    compare(inFlight.running, false, "the snapshot in flight is stopped")
    compare(store.snapshotRunner.busy, false)
    compare(store.pendingSnapshot, null, "the pending request is dropped")
    compare(store.snapshotRoots.length, 0)
    var seq = store.snapshotRunner.seq
    reply(inFlight, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    compare(store.snapshotRunner.seq, seq, "its late exit launches nothing")
    compare(store.runs.length, 0, "and applies nothing")
  }

  // 8
  function test_starting_over_stops_the_snapshot_in_flight_and_launches_every_root() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    verify(store.watchProc, "the watch runs")
    store.refresh()
    var old = store.snapshotRunner.current
    store.requestSnapshot([tc.rootB])
    // synthetic: a hello whose cursorReset is true.
    sendLine(store.watchProc, { hello: { schema: 2, am: "0.1.0", cursorReset: true } })
    compare(old.running, false, "the old store's snapshot is stopped")
    verify(store.snapshotRunner.current !== old, "one snapshot is launched at once")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, "of every root")
    compare(store.pendingSnapshot, null, "the pending request was dropped")
    var seq = store.snapshotRunner.seq
    reply(old, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)])]), 0)
    compare(store.runs.length, 0, "its late reply applies nothing")
    compare(store.snapshotRunner.seq, seq, "and launches nothing")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)]), okEntry(tc.rootB, [])]), 0)
    compare(alerts(store).toasts.length, 0, "the new store's first list only arms")
    compare(alerts(store).alertsArmed, true)
    compare(store.snapshotRunner.seq, seq, "no follow-up")
  }

  // 9
  function test_closing_the_panel_drops_the_pending_request() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    var inFlight = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    store.refresh()
    compare(store.pendingSnapshot, "all")
    store.active = false
    compare(store.pendingSnapshot, null, "closing drops it")
    compare(inFlight.running, true, "the snapshot in flight runs to its end")
    reply(inFlight, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    compare(ids(store.runs), "a1", "and is applied")
    compare(store.snapshotRunner.seq, seq, "no follow-up")
    compare(store.snapshotRunner.busy, false)
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC])
    compare(store.snapshotRunner.seq, seq + 1, "a registry change while closed still requests every root")
  }

  // 11 (the roots-left bullet) and Review Focus 4
  function test_a_reply_for_roots_that_all_left_the_registry_changes_nothing() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    store.projectRoots = registry([tc.rootC])
    reply(inFlight, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(store.amStatus, "ok", "not an error")
    compare(store.lastError, "")
    compare(store.stale, true, "stale is untouched")
    compare(store.staleTimer.running, false, "and so is the clock")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootC, "the pending request launches C")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [])]), 0)
    compare(store.amStatus, "error", "a reply matching nothing while C is still registered is still an error")
    compare(store.lastError, "The runs snapshot gave no usable result (exit 0).")
  }

  // ---- nudges announce their runs and refresh their roots (global 3.2)

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

  // threeRoots()'s reply again: every root answers with its one done run.
  function threeReply() {
    return allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                     okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                     okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])])
  }

  // 3
  function test_a_debounce_firing_announces_its_run_ids_once() {
    var store = threeRoots(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runsNudged" })
    nudge(store, ["b1", 5, "a1", 6])
    nudge(store, ["b1", 7])
    compare(spy.count, 0, "nothing before the debounce")
    fire(store.debounceTimer)
    compare(spy.count, 1, "once per firing")
    compare(JSON.stringify(spy.signalArguments[0][0]), JSON.stringify(["b1", "a1"]), "each id once, in first-nudge order")
    reply(store.snapshotRunner.current, threeReply(), 0)
    // synthetic: a run no root lists.
    nudge(store, ["z9", 8])
    fire(store.debounceTimer)
    compare(spy.count, 2, "an unknown id is announced too")
    compare(JSON.stringify(spy.signalArguments[1][0]), JSON.stringify(["z9"]))
    reply(store.snapshotRunner.current, threeReply(), 0)
    store.refresh()
    reply(store.snapshotRunner.current, threeReply(), 0)
    store.livenessTimer.triggered()
    store.pollTimer.triggered()
    reply(store.snapshotRunner.current, threeReply(), 0)
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, threeReply(), 0)
    fire(store.debounceTimer)
    compare(spy.count, 2, "refresh(), a liveness tick, a poll tick, an opening and an empty firing announce nothing")
  }

  // 4
  function test_a_nudge_refreshes_only_the_roots_that_list_its_runs() {
    var store = threeRoots(); if (!store) return
    var seq = store.snapshotRunner.seq
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB, "of B only")
    compare(store.snapshotRoots.join("|"), tc.rootB)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    nudge(store, ["c1", 6, "a1", 7])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 2, "one snapshot for the window")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootC, "A and C, in registry order")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(store.snapshotRunner.seq, seq + 2, "nothing more")
    compare(store.readRunners, undefined, "there are no run reads")
  }

  // 4
  function test_a_run_listed_by_two_roots_refreshes_both() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("s1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("s1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [])]), 0)
    compare(store.runById("s1").project.root, tc.rootA, "A won the de-duplication")
    nudge(store, ["s1", 5])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB, "every root that lists it")
  }

  // 5 and Review Focus 3
  function test_a_partial_reply_keeps_the_other_roots_as_they_were() {
    var store = threeRoots(); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  failEntry(tc.rootC, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(toastIds(store), "a1")
    fire(store.staleTimer)
    compare(store.stale, true)
    var a1 = store.runById("a1")
    var c1 = store.runById("c1")
    nudge(store, ["b1", 9])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB),
                                                                     entry("b2", "done", false, tc.rootB)])]), 0)
    compare(ids(store.runs), "a1,b1,b2,c1", "B's runs replaced, the others kept, in registry order")
    verify(store.runById("a1") === a1, "an unrefreshed root's run is the same object")
    verify(store.runById("c1") === c1)
    compare(store.projectErrors[tc.rootC], "AmTimeout: am did not answer within 60 s.", "C's error stays")
    compare(store.projectErrors[tc.rootB], undefined)
    compare(toastIds(store), "a1,b1", "only b1 alerts: the unrefreshed a1 does not alert again")
    compare(store.stale, false, "a good partial reply clears stale")
    compare(store.staleTimer.running, true, "and restarts the clock")
    compare(store.amStatus, "ok")
  }

  // 6
  function test_a_window_with_an_unknown_id_refreshes_every_root_once() {
    var store = threeRoots(); if (!store) return
    var seq = store.snapshotRunner.seq
    // synthetic: a run no root lists, beside a listed one.
    nudge(store, ["b1", 5, "z9", 6])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "exactly one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC)
  }

  // 7
  function test_two_nudge_windows_during_a_snapshot_follow_up_with_their_roots_only() {
    var store = threeRoots(); if (!store) return
    store.refresh()
    var inFlight = store.snapshotRunner.current
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    nudge(store, ["c1", 6])
    fire(store.debounceTimer)
    reply(inFlight, threeReply(), 0)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB + "|" + tc.rootC, "B and C only")
  }

  // 7 and Review Focus 1
  function test_nudges_and_liveness_during_a_snapshot_give_one_follow_up() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var first = allReply([okEntry(tc.rootA, [entry("a1", "started", true)]), okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                          okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])])
    reply(store.snapshotRunner.current, first, 0)
    store.refresh()
    var inFlight = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    nudge(store, ["c1", 6])
    fire(store.debounceTimer)
    store.livenessTimer.triggered()
    verify(store.snapshotRunner.current === inFlight, "the snapshot in flight is kept")
    compare(inFlight.running, true)
    compare(store.snapshotRunner.seq, seq)
    compare(store.pendingSnapshot.join("|"), [tc.rootB, tc.rootC, tc.rootA].join("|"), "one pending request")
    reply(inFlight, first, 0)
    compare(store.snapshotRunner.seq, seq + 1, "one follow-up")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB + "|" + tc.rootC,
            "the union, in registry order")
    reply(store.snapshotRunner.current, first, 0)
    compare(store.snapshotRunner.seq, seq + 1, "nothing more")
  }

  // 10
  function test_a_liveness_tick_refreshes_only_the_roots_with_a_running_run() {
    var store = activeRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "started", true)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "started", false, tc.rootC)])]), 0)
    compare(store.livenessTimer.running, true)
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "A alone: C's run is dead, B's done")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "started", true)])]), 0)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "started", true)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "started", true, tc.rootC)])]), 0)
    store.livenessTimer.triggered()
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootC, "A and C")
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(store.livenessTimer.running, false, "no running run: the timer is off")
    var idle = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, idle, "a forced tick launches nothing")
  }

  // 11
  function test_stale_follows_any_good_reply_full_or_partial() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    fire(store.staleTimer)
    compare(store.stale, true, "no good reply for 30 s")
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    compare(store.stale, false, "a partial reply with one ok entry clears it")
    compare(store.staleTimer.running, true, "and restarts the clock")
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.stale, true, "every entry failed: stale stays")
    compare(store.staleTimer.running, false, "and the clock is untouched")
  }

  // Kept behaviour: a refresh that moves the selected attempt refetches its logs.
  function test_a_nudge_refresh_that_moves_the_selected_attempt_fetches_its_logs() {
    var store = capturedStore(); if (!store) return
    store.selectedRunId = tc.startedRun
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var seq = store.logsRunner.seq
    nudge(store, [tc.startedRun, 990])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    // synthetic: the captured list with the started run's open attempt (explore 1) ok.
    var value = JSON.parse(capturedList())
    value.projects[0].runs[0].status.stories[1].subtasks[1].phases[1].attempts[0].status = "ok"
    reply(store.snapshotRunner.current, JSON.stringify(value) + "\n", 0)
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches the logs again")
    compare(argv(store.logsRunner.current), "python3|/plugin/core/backend/runs/runs-logs.py|" + tc.capRoot + "|" + tc.startedRun + "|" + tc.openCard + "|explore|1")
  }

  // Kept behaviour: a refresh that moves a run settles its pending request.
  function test_a_nudge_refresh_that_moves_the_run_settles_its_pending_request() {
    var store = capturedStore(); if (!store) return
    compare(controlOf(store).control("cancel", tc.startedRun), true)
    reply(controlOf(store).controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(controlOf(store).pending[tc.startedRun], "cancel", "acknowledged, not yet settled")
    nudge(store, [tc.startedRun, 1005])
    fire(store.debounceTimer)
    // synthetic: status-escalated.json's data under the started run's id.
    reply(store.snapshotRunner.current, capturedList([], true), 0)
    compare(controlOf(store).pending[tc.startedRun], undefined, "the refresh settled it")
  }

  // Kept behaviour: a nudge after a project switch is still handled.
  function test_a_nudge_after_a_project_switch_is_still_handled() {
    var store = threeRoots(); if (!store) return
    store.project = tc.rootA
    store.project = tc.rootB
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runsNudged" })
    nudge(store, ["a1", 5])
    fire(store.debounceTimer)
    compare(spy.count, 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "the nudged run's root, whatever project is open")
    store.project = ""
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)])]), 0)
    compare(store.runById("a1").status, "escalated", "applied with no project open")
  }

  // The plan's Review Focus 1
  function test_a_partial_reply_that_is_am_missing_empties_every_root() {
    var store = threeRoots(); if (!store) return
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB)
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootB, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing", "am is on PATH or it is not: the whole store")
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0, "A's and C's runs go too")
    compare(Object.keys(store.projectErrors).length, 0)
    compare(alerts(store).alertsArmed, false)
  }

  // The plan's Review Focus 3
  function test_a_nudge_after_the_registry_emptied_announces_and_launches_nothing() {
    var store = threeRoots(); if (!store) return
    var w = store.watchProc
    store.projectRoots = []
    compare(store.runs.length, 0)
    verify(store.watchProc === w, "no snapshot, so the watch is not restarted")
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runsNudged" })
    var seq = store.snapshotRunner.seq
    nudge(store, ["a1", 5])
    fire(store.debounceTimer)
    compare(spy.count, 1, "announced")
    compare(store.snapshotRunner.seq, seq, "no root to snapshot")
    compare(store.snapshotRunner.busy, false)
    compare(store.pendingSnapshot, null)
  }

  // The plan's Review Focus 4
  function test_a_nudge_for_a_run_kept_by_a_failed_root_refreshes_that_root() {
    var store = threeRoots(); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s."),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(ids(store.runs), "a1,b1,c1", "B keeps its run")
    var seq = store.snapshotRunner.seq
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1)
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootB, "B, not every root")
  }

  // ---- live refresh (3.2)

  // An active store (the panel is open) with project `root` registered and
  // open: its first snapshot is in flight.
  function activeStore(root) {
    var store = make(); if (!store) return null
    store.active = true
    store.projectRoots = [rootEntry(root)]
    store.project = root
    return store
  }

  // An active store on project A whose first snapshot listed `entries`, so its
  // watch is running.
  function watchedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  // ---- activation and watch start

  function test_activation_refreshes_every_root() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.snapshotRunner.seq, seq + 1, "opening the panel fetches a fresh snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
  }

  function test_activation_without_a_project_launches_nothing() {
    var store = make(); if (!store) return
    store.active = true
    verify(!store.snapshotRunner.current, "no snapshot without a project")
    verify(!store.watchProc, "no watch without a project")
    compare(store.watching, false)
  }

  function test_watch_not_started_before_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    verify(store.snapshotRunner.current, "the first snapshot is in flight")
    verify(!store.watchProc, "no watch before the first snapshot reply")
    compare(store.watching, false)
  }

  function test_watch_argv_after_first_snapshot() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("b", "done", false)]), 0)
    compare(store.runs.length, 2)
    var w = store.watchProc
    verify(w, "the first good snapshot starts the watch")
    compare(w.objectName, "watchProc")
    compare(JSON.stringify(w.command), JSON.stringify(["python3", "/plugin/core/backend/runs/runs-watch.py", tc.rootA, "a", "b"]),
            "the root, then the run ids, and no --since-seq")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_watch_with_no_runs_watches_the_project_alone() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var w = store.watchProc
    verify(w, "an empty project is watched too: its first run must show up")
    compare(argv(w), tc.watchCmd + "|" + tc.rootA, "the root alone")
    compare(w.running, true)
    compare(store.watching, true)
  }

  function test_watch_not_started_when_inactive() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.runs.length, 1)
    verify(!store.watchProc, "a closed panel never watches")
    compare(store.watching, false)
  }

  function test_failed_first_snapshot_does_not_start_watch() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n', 1)
    verify(!store.watchProc, "a failed snapshot starts no watch")
    compare(store.watching, false)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc, "the first GOOD snapshot starts it")
    compare(argv(store.watchProc), tc.watchCmd + "|" + tc.rootA + "|a")
    compare(store.watching, true)
  }

  function test_second_snapshot_does_not_restart_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true), entry("c", "started", true)]), 0)
    verify(store.watchProc === w, "the running watch is kept")
    compare(w.running, true)
    compare(argv(w), tc.watchCmd + "|" + tc.rootA + "|a", "its argv is not rewritten: the helper picks up a watched root's new runs itself")
  }

  // ---- the watch argv (global 3.2)

  // 1 and Review Focus 2
  function test_the_watch_names_every_root_then_every_known_run_id() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    var w = store.watchProc
    verify(w, "the first good reply starts the watch")
    compare(JSON.stringify(w.command), JSON.stringify(["python3", "/plugin/core/backend/runs/runs-watch.py", tc.rootA, tc.rootB, "a1", "b1"]))
    compare(w.command[2], tc.rootA, "a root with a space is one argument")
    compare(store.watchRoots.join("|"), tc.rootA + "|" + tc.rootB)
  }

  // 1 and Review Focus 2
  function test_the_watch_leaves_out_ids_and_roots_the_helper_would_refuse() {
    var store = make(); if (!store) return
    store.active = true
    store.projectRoots = [rootEntry(tc.rootA), { root: "rel/proj", name: "rel" }, rootEntry(tc.rootB)]
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|rel/proj|" + tc.rootB,
            "the snapshot still names every usable root")
    // synthetic: run ids runs-watch.py would refuse or read as roots, and a run listed under two roots.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("", "done", false), entry("-x", "done", false),
                                                                     entry("/x", "done", false), entry("a1", "done", false)]),
                                                  okEntry("rel/proj", [entry("r1", "done", false, "rel/proj")]),
                                                  okEntry(tc.rootB, [entry("a1", "done", false, tc.rootB)])]), 0)
    compare(JSON.stringify(store.watchProc.command),
            JSON.stringify(["python3", "/plugin/core/backend/runs/runs-watch.py", tc.rootA, tc.rootB, "a1", "r1"]),
            "no relative root, no refused id, a1 once")
  }

  // 1
  function test_with_no_runs_the_watch_names_the_roots_alone() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(argv(store.watchProc), tc.watchCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // 2
  function test_with_no_absolute_root_no_watch_is_launched() {
    var store = make(); if (!store) return
    store.active = true
    store.projectRoots = [{ root: "rel/proj", name: "rel" }]
    var good = allReply([okEntry("rel/proj", [entry("r1", "done", false, "rel/proj")])])
    reply(store.snapshotRunner.current, good, 0)
    compare(store.amStatus, "ok")
    verify(!store.watchProc, "no root the helper reads as a root: no watch")
    compare(store.watching, false)
    var seq = store.watchSeq
    store.refresh()
    reply(store.snapshotRunner.current, good, 0)
    verify(!store.watchProc, "a second good reply does not try again")
    compare(store.watching, false)
    compare(store.watchSeq, seq)
  }

  // 12 and Review Focus 5
  function test_a_new_root_set_restarts_a_running_watch() {
    var store = activeRoots([tc.rootA]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    var first = store.watchProc
    compare(argv(first), tc.watchCmd + "|" + tc.rootA + "|a1")
    store.projectRoots = registry([tc.rootA, tc.rootC])
    verify(store.watchProc === first, "a registry change alone restarts nothing")
    var both = allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])])
    reply(store.snapshotRunner.current, both, 0)
    var second = store.watchProc
    verify(second !== first, "the good reply for the new roots restarts the watch")
    compare(first.running, false, "the old watch is stopped")
    compare(argv(second), tc.watchCmd + "|" + tc.rootA + "|" + tc.rootC + "|a1|c1", "with C and its run ids")
    compare(second.running, true)
    compare(store.watching, true)
    store.refresh()
    reply(store.snapshotRunner.current, both, 0)
    verify(store.watchProc === second, "the same roots keep the watch")
    store.projectRoots = registry([tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    var third = store.watchProc
    verify(third !== second, "removing C restarts it too")
    compare(second.running, false)
    compare(argv(third), tc.watchCmd + "|" + tc.rootA + "|a1")
  }

  // 12
  function test_a_watch_that_ended_is_not_restarted_by_a_new_root_set() {
    var types = [["HelperError", 1], ["SchemaMismatch", 1]]
    for (var i = 0; i < types.length; i++) {
      var label = types[i][0]
      var store = activeRoots([tc.rootA]); if (!store) return
      reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
      endWatch(store.watchProc, watchError(types[i][0], "m"), types[i][1])
      compare(store.watching, false, label)
      var seq = store.watchSeq
      store.projectRoots = registry([tc.rootA, tc.rootC])
      reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootC, [])]), 0)
      compare(store.watchSeq, seq, label + ": no watch is started until the next opening")
      compare(store.watching, false, label)
    }
  }

  // The plan's Review Focus 2
  function test_a_reordered_or_renamed_registry_keeps_the_watch() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    var good = allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])])
    reply(store.snapshotRunner.current, good, 0)
    var w = store.watchProc
    store.projectRoots = [{ root: tc.rootB, name: "bee" }, rootEntry(tc.rootA)]
    reply(store.snapshotRunner.current, good, 0)
    verify(store.watchProc === w, "the same roots in another order, under another name, keep the watch")
    compare(w.running, true)
    compare(store.watchRoots.join("|"), tc.rootA + "|" + tc.rootB, "the roots it was launched with")
  }

  // The plan's Review Focus 5
  function test_a_restart_with_no_absolute_root_left_launches_no_watch() {
    var store = make(); if (!store) return
    store.active = true
    store.projectRoots = [rootEntry(tc.rootA), { root: "rel/proj", name: "rel" }]
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry("rel/proj", [])]), 0)
    var w = store.watchProc
    compare(argv(w), tc.watchCmd + "|" + tc.rootA)
    store.projectRoots = [{ root: "rel/proj", name: "rel" }]
    reply(store.snapshotRunner.current, allReply([okEntry("rel/proj", [entry("r1", "done", false, "rel/proj")])]), 0)
    compare(w.running, false, "the old watch is stopped")
    compare(store.watching, false, "and none replaces it: no root the helper reads as a root")
    var seq = store.watchSeq
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry("rel/proj", [])]), 0)
    compare(store.watchSeq, seq, "later replies do not try again")
    compare(store.amStatus, "ok")
  }

  // ---- debounce

  // One stdout line of a watch: an object is sent as its JSON, a string as is.
  function sendLine(proc, value) {
    proc.stdout.read(typeof value === "string" ? value : JSON.stringify(value))
  }

  function test_changed_line_starts_debounce() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var t = store.debounceTimer
    compare(t.objectName, "debounceTimer")
    compare(t.interval, 250)
    compare(t.repeat, false)
    compare(t.running, false, "idle until a line arrives")
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, { changed: [{ run: "a", seq: 990 }] })
    compare(t.running, true)
    compare(store.snapshotRunner.seq, seq, "a line alone launches no snapshot")
  }

  function test_burst_coalesces_to_one_snapshot() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    // synthetic: runs-watch.py changed lines for runs the list did not name.
    sendLine(store.watchProc, { changed: [{ run: "b", seq: 990 }] })
    sendLine(store.watchProc, { changed: [{ run: "c", seq: 991 }] })
    sendLine(store.watchProc, '{"changed": [{"run": "b", "seq": 992}, {"run": "c", "seq": 993}]}')
    compare(store.snapshotRunner.seq, seq, "no snapshot during the burst")
    store.debounceTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the burst cost exactly one snapshot")
    compare(store.snapshotRunner.current.command[1], "/plugin/core/backend/runs/runs-snapshot-all.py")
  }

  function test_garbage_watch_line_ignored() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var lines = ["", "   ", "not json {", "[]", "null", "3", '"changed"', "{}", '{"hello": 1}', '{"changed": "a"}', '{"changed": null}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.debounceTimer.running, false, JSON.stringify(lines[i]) + " is ignored")
    }
    compare(store.watching, true, "the watch keeps running")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
  }

  // ---- the hello

  // The helper's forwarded hello for watch-hello.json's `key` line.
  function helloLine(key) {
    var h = F.load("watch-hello.json")[key]
    return { hello: { schema: h.schema, am: h.am } }
  }

  function test_am_schema_and_version_default_unknown() {
    var store = make(); if (!store) return
    compare(store.amSchema, 0, "a fresh store knows no schema")
    compare(store.amVersion, "", "nor am's version")
    var watched = watchedStore([entry("a", "done", false)]); if (!watched) return
    compare(watched.amSchema, 0, "a running watch before its hello")
    compare(watched.amVersion, "")
  }

  function test_hello_sets_schema_and_version() {
    var cases = [["schema_1", 1], ["schema_2", 2]]
    for (var i = 0; i < cases.length; i++) {
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      sendLine(store.watchProc, helloLine(cases[i][0]))
      compare(store.amSchema, cases[i][1], cases[i][0])
      compare(store.amVersion, "0.1.0", cases[i][0])
    }
  }

  function test_hello_starts_nothing() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    var liveness = store.livenessTimer.running
    sendLine(store.watchProc, helloLine("schema_2"))
    compare(store.amSchema, 2)
    compare(store.debounceTimer.running, false, "a hello is not a change")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
    compare(store.livenessTimer.running, liveness, "the liveness timer is left as it was")
    compare(store.watching, true)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.watchWarning, "")
    compare(store.watchSchemaError, "")
    verify(!store.watchProc.envelope, "a hello is not an envelope")
    sendLine(store.watchProc, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, true, "a changed line still starts the debounce")
  }

  function test_malformed_hello_values() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var schemas = ["2", true, 2.5, 0, -1, null, undefined]
    for (var i = 0; i < schemas.length; i++) {
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amSchema, 2, "a known schema first")
      // synthetic: schema_1's forwarded hello with a schema that is not an
      // integer of 1 or more (undefined drops the key).
      var line = helloLine("schema_1")
      if (schemas[i] === undefined) delete line.hello.schema
      else line.hello.schema = schemas[i]
      sendLine(store.watchProc, line)
      compare(store.amSchema, 0, JSON.stringify(line))
      compare(store.amVersion, "0.1.0", JSON.stringify(line) + " keeps its string am")
    }
    var ams = [5, null, undefined]
    for (var j = 0; j < ams.length; j++) {
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amVersion, "0.1.0", "a known version first")
      // synthetic: schema_1's forwarded hello with an am that is not a string
      // (undefined drops the key).
      var amLine = helloLine("schema_1")
      if (ams[j] === undefined) delete amLine.hello.am
      else amLine.hello.am = ams[j]
      sendLine(store.watchProc, amLine)
      compare(store.amVersion, "", JSON.stringify(amLine))
      compare(store.amSchema, 1, JSON.stringify(amLine) + " keeps its integer schema")
    }
    // synthetic: the spec's error-table lines, typed as raw text.
    var raw = ['{"hello": {"schema": "2", "am": 5}}', '{"hello": {}}']
    for (var k = 0; k < raw.length; k++) {
      sendLine(store.watchProc, helloLine("schema_2"))
      sendLine(store.watchProc, raw[k])
      compare(store.amSchema, 0, raw[k])
      compare(store.amVersion, "", raw[k])
    }
  }

  function test_non_object_hello_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    var lines = ['{"hello": 1}', '{"hello": null}', '{"hello": []}', '{"hello": "x"}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.amSchema, 2, lines[i] + " is ignored")
      compare(store.amVersion, "0.1.0", lines[i] + " is ignored")
      compare(store.debounceTimer.running, false, lines[i])
    }
  }

  function test_a_later_hello_overwrites_both() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    sendLine(store.watchProc, helloLine("schema_1"))
    compare(store.amSchema, 1, "the latest hello wins")
    compare(store.amVersion, "0.1.0")
    // synthetic: schema_1's forwarded hello with neither a usable schema nor am.
    var line = helloLine("schema_1")
    line.hello.schema = "1"
    line.hello.am = 1
    sendLine(store.watchProc, line)
    compare(store.amSchema, 0, "a later malformed hello resets the schema")
    compare(store.amVersion, "", "and the version")
  }

  function test_hello_beside_changed_or_ok_false_keeps_its_meaning() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    // synthetic: a changed line that also carries schema_2's hello.
    var changed = helloLine("schema_2")
    changed.changed = [{ run: "a", seq: 990 }]
    sendLine(store.watchProc, changed)
    compare(store.debounceTimer.running, true, "a changed array still restarts the debounce")
    compare(store.amSchema, 0, "its hello is not read")
    compare(store.amVersion, "")
    // synthetic: an ok:false envelope that also carries schema_2's hello.
    var refusal = helloLine("schema_2")
    refusal.ok = false
    refusal.error = { type: "HelperError", message: "m" }
    sendLine(store.watchProc, refusal)
    verify(store.watchProc.envelope, "ok:false is still kept as the envelope")
    compare(store.watchProc.envelope.error.type, "HelperError")
    compare(store.amSchema, 0, "its hello is not read")
    compare(store.amVersion, "")
  }

  function test_hello_mid_burst_keeps_the_debounce() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var seq = store.snapshotRunner.seq
    // synthetic: a runs-watch.py changed line for a run the list did not name.
    sendLine(store.watchProc, { changed: [{ run: "z", seq: 990 }] })
    compare(store.debounceTimer.running, true)
    sendLine(store.watchProc, helloLine("schema_2"))
    compare(store.amSchema, 2)
    compare(store.debounceTimer.running, true, "the pending refresh is kept")
    compare(store.snapshotRunner.seq, seq, "and not fired early")
    store.debounceTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the burst still costs one snapshot")
  }

  function test_hello_extra_keys_are_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    // synthetic: am's raw hello object (event, runs_dir) as the hello value.
    sendLine(store.watchProc, { hello: F.load("watch-hello.json").schema_2 })
    compare(store.amSchema, 2)
    compare(store.amVersion, "0.1.0")
    // synthetic: schema_1's forwarded hello with an empty am and an unknown key.
    var line = helloLine("schema_1")
    line.hello.am = ""
    line.hello.extra = { schema: 9 }
    sendLine(store.watchProc, line)
    compare(store.amSchema, 1)
    compare(store.amVersion, "", "an empty string is still a string")
  }

  function test_hello_reset_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    compare(store.amSchema, 2)
    store.active = false
    compare(store.amSchema, 0, "a closed panel has no watch hello")
    compare(store.amVersion, "")
    store.active = true
    compare(store.amSchema, 0, "reopening alone restores nothing")
    compare(store.amVersion, "")
  }

  function test_hello_reset_on_watch_exit() {
    var cases = [["", 0], [watchError("HelperError", "m"), 1], ["", 137]]
    for (var i = 0; i < cases.length; i++) {
      var label = "exit " + cases[i][1] + " " + cases[i][0]
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amSchema, 2, label)
      endWatch(store.watchProc, cases[i][0], cases[i][1])
      compare(store.watching, false, label)
      compare(store.amSchema, 0, label + ": an ended watch has no hello")
      compare(store.amVersion, "", label)
    }
  }

  function test_hello_reset_when_poll_takes_over() {
    var types = ["SchemaMismatch", "CorruptJournal"]
    for (var i = 0; i < types.length; i++) {
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      sendLine(store.watchProc, helloLine("schema_2"))
      compare(store.amSchema, 2, types[i])
      endWatch(store.watchProc, watchError(types[i], "m"), 1)
      compare(store.amSchema, 0, types[i])
      compare(store.amVersion, "", types[i])
      compare(store.pollTimer.running, true, types[i] + " polls")
      store.pollTimer.triggered()
      reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
      compare(store.amSchema, 0, types[i] + ": a polled snapshot brings no hello")
      compare(store.amVersion, "", types[i])
    }
  }

  function test_a_project_switch_keeps_the_hello() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    sendLine(store.watchProc, helloLine("schema_2"))
    store.project = rootB
    compare(store.amSchema, 2, "the watch is every project's")
    compare(store.amVersion, "0.1.0")
    store.project = ""
    compare(store.amSchema, 2)
    compare(store.amVersion, "0.1.0")
  }

  function test_old_watch_hello_ignored() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var old = store.watchProc
    sendLine(old, helloLine("schema_2"))
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    verify(store.watchProc !== old, "the new opening runs its own watch")
    sendLine(old, helloLine("schema_2"))
    compare(store.amSchema, 0, "the old watch's late hello is dropped")
    compare(store.amVersion, "")
    sendLine(store.watchProc, helloLine("schema_1"))
    compare(store.amSchema, 1, "the new watch's own hello counts")
    compare(store.amVersion, "0.1.0")
    old.exited(0)
    compare(store.amSchema, 1, "the old watch's late exit forgets nothing")
    compare(store.amVersion, "0.1.0")
  }

  function test_new_watch_starts_unknown() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var old = store.watchProc
    sendLine(old, helloLine("schema_2"))
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old, "a new watch was started")
    compare(fresh.running, true)
    compare(store.amSchema, 0, "a new watch starts unknown")
    compare(store.amVersion, "")
    sendLine(fresh, helloLine("schema_1"))
    compare(store.amSchema, 1, "until its own hello")
    compare(store.amVersion, "0.1.0")
  }

  // ---- liveness

  function test_liveness_on_with_running_run() {
    var store = watchedStore([entry("a", "done", false), entry("b", "started", true)]); if (!store) return
    var t = store.livenessTimer
    compare(t.objectName, "livenessTimer")
    compare(t.interval, 10000)
    compare(t.repeat, true)
    compare(t.running, true, "a started run with a live lease is re-read")
  }

  function test_liveness_off_without_running_run() {
    var store = watchedStore([entry("d", "started", false), entry("p", "stopped", true), entry("f", "done", false)]); if (!store) return
    compare(store.livenessTimer.running, false, "dead, parked and done runs need no liveness re-read")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("d", "started", true)]), 0)
    compare(store.livenessTimer.running, true, "it starts once a run is running")
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("d", "done", false)]), 0)
    compare(store.livenessTimer.running, false, "and stops when none is")
  }

  function test_liveness_off_when_inactive() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.livenessTimer.running, false, "no timer while the panel is closed")
    store.active = true
    compare(store.livenessTimer.running, true, "opening the panel with a running run starts it")
  }

  function test_liveness_tick_refreshes() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "each tick fetches a snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA, "of the root with the running run")
  }

  // ---- deactivation

  function test_deactivate_kills_watch_and_timers() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    store.selectedRunId = "a"
    var w = store.watchProc
    sendLine(w, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, true)
    compare(store.livenessTimer.running, true)
    store.active = false
    compare(w.running, false, "the watch is killed")
    compare(store.watching, false)
    compare(store.debounceTimer.running, false, "the pending refresh is dropped")
    compare(Object.keys(store.nudges).length, 0, "and its nudges")
    compare(store.livenessTimer.running, false)
    compare(store.runs.length, 1, "the runs stay for the next opening")
    compare(store.runs[0].id, "a")
    compare(store.selectedRunId, "a")
    compare(store.amStatus, "ok")
  }

  function test_reactivation_starts_a_new_watch() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    store.active = true
    var first = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    store.active = false
    store.active = true
    verify(store.snapshotRunner.current === first, "the snapshot in flight is kept")
    compare(store.snapshotRunner.seq, seq)
    compare(store.pendingSnapshot, "all", "the second opening waits as the pending request")
    compare(old.running, false, "the old watch stays dead")
    reply(first, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old, "the reply that lands while open starts a new watch")
    compare(fresh.running, true)
    compare(argv(fresh), tc.watchCmd + "|" + tc.rootA + "|a")
    compare(store.watching, true)
    compare(store.snapshotRunner.seq, seq + 1, "then the pending request launches")
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc === fresh, "and its reply keeps the watch")
  }

  // ---- stale

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  function test_stale_timer_runs_only_while_active() {
    var store = makeWithProject(rootA); if (!store) return
    var t = store.staleTimer
    compare(t.objectName, "staleTimer")
    compare(t.interval, 30000)
    compare(t.repeat, false)
    compare(t.running, false, "no stale clock while the panel is closed")
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(t.running, false, "a good snapshot while closed starts no clock")
    store.active = true
    compare(t.running, true, "opening the panel starts the clock")
    compare(store.stale, false)
  }

  function test_stale_after_timer_fires() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "a good snapshot (re)starts the clock")
    fire(store.staleTimer)
    compare(store.stale, true)
    compare(store.runs.length, 1, "stale is not a run state: the runs are untouched")
    compare(store.runs[0].status, "done")
  }

  function test_good_snapshot_clears_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the clock counts from this snapshot")
  }

  function test_failed_snapshot_keeps_stale_timer_running() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var failure = '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}\n'
    store.refresh()
    reply(store.snapshotRunner.current, failure, 1)
    compare(store.staleTimer.running, true, "a failed snapshot leaves the clock running")
    compare(store.stale, false)
    fire(store.staleTimer)
    compare(store.stale, true)
    store.refresh()
    reply(store.snapshotRunner.current, failure, 1)
    compare(store.stale, true, "a failed snapshot does not clear stale")
    compare(store.staleTimer.running, false, "nor restart the clock")
  }

  function test_stale_cleared_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.active = false
    compare(store.stale, false)
    compare(store.staleTimer.running, false)
    compare(store.runs.length, 1)
  }

  function test_a_project_switch_keeps_stale() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    fire(store.staleTimer)
    compare(store.stale, true)
    store.project = rootB
    compare(store.stale, true, "the snapshot's age is every project's")
    compare(store.staleTimer.running, false, "the clock is not restarted")
  }

  function test_snapshot_landing_after_deactivation_starts_nothing() {
    var store = activeStore(rootA); if (!store) return
    var proc = store.snapshotRunner.current
    store.active = false
    reply(proc, okReply([entry("a", "started", true)]), 0)
    compare(store.runs.length, 1, "the runs are still applied")
    verify(!store.watchProc, "no watch for a closed panel")
    compare(store.watching, false)
    compare(store.staleTimer.running, false)
    compare(store.livenessTimer.running, false)
  }

  // ---- a project switch keeps the watch

  function test_a_project_switch_keeps_the_watch_and_the_runs() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    var seq = store.snapshotRunner.seq
    sendLine(w, { changed: [{ run: "a", seq: 990 }] })
    store.project = rootB
    compare(w.running, true, "the watch is not stopped")
    compare(store.watching, true)
    verify(store.watchProc === w)
    compare(store.debounceTimer.running, true, "its pending nudge stays")
    compare(store.nudges.a, 990)
    compare(ids(store.runs), "a")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
  }

  // Review Focus (spec 5)
  function test_watch_lines_after_a_switch_still_count() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    store.project = rootB
    sendLine(w, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, true, "a line after a switch is handled")
    compare(store.nudges.a, 990)
    store.project = ""
    sendLine(w, { cursor: 1005 })
    compare(store.watchCursor, 1005, "and with no project open")
  }

  function test_killed_watch_lines_ignored_after_deactivation() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    sendLine(old, { changed: [{ run: "a", seq: 990 }] })
    compare(store.debounceTimer.running, false, "a killed watch's late line is dropped")
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    verify(store.watchProc !== old)
    sendLine(old, { changed: [{ run: "a", seq: 991 }] })
    compare(store.debounceTimer.running, false, "same project, but an older launch")
  }

  function test_clearing_the_project_while_active_keeps_everything_running() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var w = store.watchProc
    var seq = store.snapshotRunner.seq
    store.project = ""
    compare(w.running, true, "the watch runs on")
    compare(store.watching, true)
    compare(store.staleTimer.running, true, "the stale clock runs with no project")
    compare(store.livenessTimer.running, true, "a running run is still re-read")
    compare(ids(store.runs), "a")
    compare(store.snapshotRunner.seq, seq, "no snapshot")
  }

  // ---- watch exit and the fallback poll

  function watchError(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } })
  }

  // The watch prints its last line (none when `line` is ""), then exits.
  function endWatch(proc, line, code) {
    if (line !== "") sendLine(proc, line)
    proc.exited(code)
  }

  function test_schema_mismatch_falls_back_to_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    var t = store.pollTimer
    compare(t.objectName, "pollTimer")
    compare(t.interval, 5000)
    compare(t.repeat, true)
    compare(t.running, false, "no poll while the watch works")
    var msg = "am watch speaks journal schema 2; this helper reads schema 1."
    endWatch(store.watchProc, watchError("SchemaMismatch", msg), 1)
    compare(store.amStatus, "schema")
    compare(store.lastError, "SchemaMismatch: " + msg)
    compare(store.watching, false)
    compare(t.running, true)
    var seq = store.snapshotRunner.seq
    t.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "a poll tick fetches a snapshot")
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.watching, false, "the poll replaces the watch: none is restarted")
    compare(t.running, true)
  }

  function test_schema_banner_survives_poll_snapshots() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    store.pollTimer.triggered()
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.runs[0].status, "done", "the polled snapshot is applied")
    compare(store.amStatus, "schema", "the banner stays while polling")
    compare(store.lastError, "SchemaMismatch: schema 2")
    compare(store.stale, false)
    compare(store.staleTimer.running, true, "the stale rule still applies while polling")
  }

  function test_corrupt_journal_sets_warning_and_polls() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "journal line 12 is not JSON"), 1)
    compare(store.watchWarning, "CorruptJournal: journal line 12 is not JSON")
    compare(store.amStatus, "ok", "a warning chip, not a banner")
    compare(store.lastError, "")
    compare(store.watching, false)
    compare(store.pollTimer.running, true)
    var seq = store.snapshotRunner.seq
    store.pollTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1)
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.watchWarning, "CorruptJournal: journal line 12 is not JSON", "the chip stays while polling")
    compare(store.amStatus, "ok")
    compare(store.watching, false)
  }

  function test_poll_stops_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.pollTimer.running, true)
    store.active = false
    compare(store.pollTimer.running, false)
    compare(store.amStatus, "schema", "deactivation leaves amStatus as it is")
    compare(store.lastError, "SchemaMismatch: schema 2")
    store.active = true
    compare(store.pollTimer.running, false, "the next opening tries the watch first")
    reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
    compare(store.amStatus, "ok", "a good snapshot after re-opening resets the status")
    compare(store.lastError, "")
    compare(store.watching, true, "and the watch is tried again")
  }

  function test_corrupt_warning_cleared_on_deactivate() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.watchWarning, "CorruptJournal: bad")
    store.active = false
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
  }

  function test_other_watch_error_stops_watching_without_poll() {
    var cases = [["HelperError", 1], ["AmMissing", 1], ["Usage", 2]]
    for (var i = 0; i < cases.length; i++) {
      var type = cases[i][0]
      var store = watchedStore([entry("a", "done", false)]); if (!store) return
      endWatch(store.watchProc, watchError(type, "m"), cases[i][1])
      compare(store.watching, false, type)
      compare(store.lastError, type + ": m")
      compare(store.amStatus, "ok", type + " is not a schema banner")
      compare(store.watchWarning, "", type + " is not a warning chip")
      compare(store.pollTimer.running, false, type + " starts no poll")
      store.refresh()
      reply(store.snapshotRunner.current, okReply([entry("a", "done", false)]), 0)
      compare(store.watching, false, type + ": no restart until the next opening")
    }
  }

  function test_watch_exit_without_envelope_names_the_exit_code() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, "", 137)
    compare(store.watching, false)
    verify(store.lastError.indexOf("exit 137") >= 0, "the exit code is named: " + store.lastError)
    compare(store.pollTimer.running, false)
    compare(store.amStatus, "ok")
  }

  function test_watch_exit_zero_only_clears_watching() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    sendLine(store.watchProc, { changed: [{ run: "a", seq: 990 }] })
    endWatch(store.watchProc, "", 0)
    compare(store.watching, false)
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    compare(store.watchWarning, "")
    compare(store.pollTimer.running, false)
    compare(store.debounceTimer.running, true, "the pending refresh still happens")
    compare(store.livenessTimer.running, true)
    compare(store.runs.length, 1)
  }

  function test_stale_exit_after_reactivation_ignored() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    var old = store.watchProc
    store.active = false
    store.active = true
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    var fresh = store.watchProc
    verify(fresh !== old)
    compare(store.watching, true)
    old.exited(0)
    compare(store.watching, true, "the killed watch's late exit does not end the new one")
    compare(fresh.running, true)
  }

  function test_a_watch_exit_after_a_switch_is_still_handled() {
    var store = watchedStore([entry("a", "started", true)]); if (!store) return
    store.project = rootB
    endWatch(store.watchProc, watchError("SchemaMismatch", "schema 2"), 1)
    compare(store.amStatus, "schema")
    compare(store.lastError, "SchemaMismatch: schema 2")
    compare(store.pollTimer.running, true)
  }

  function test_a_project_switch_keeps_the_warning_and_the_poll() {
    var store = watchedStore([entry("a", "done", false)]); if (!store) return
    endWatch(store.watchProc, watchError("CorruptJournal", "bad"), 1)
    compare(store.pollTimer.running, true)
    store.project = rootB
    compare(store.watchWarning, "CorruptJournal: bad")
    compare(store.pollTimer.running, true)
    compare(store.watching, false)
  }

  // ---- the Runs screen's filter and search (5.1)

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  function screenEntries() {
    return [entry("live1", "started", true), entry("esc1", "escalated", false),
            entry("dead1", "started", false), entry("park1", "stopped", false)]
  }

  function test_filtered_runs_follow_the_filter_and_the_search() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    compare(store.runFilter, "")
    compare(store.searchQuery, "")
    compare(ids(store.filteredRuns), "live1,esc1,dead1,park1")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "esc1,dead1")
    store.searchQuery = "DEAD"
    compare(ids(store.filteredRuns), "dead1", "the search composes with the filter")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "dead1")
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "live1,esc1,dead1,park1")
  }

  function test_toggle_run_filter_and_back_to_all() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    store.toggleRunFilter("live")
    compare(store.runFilter, "live")
    compare(spy.count, 1)
    store.toggleRunFilter("parked")
    compare(store.runFilter, "parked", "another chip replaces the filter")
    store.toggleRunFilter("parked")
    compare(store.runFilter, "", "the active chip again is All")
    store.toggleRunFilter("attention")
    store.toggleRunFilter("all")
    compare(store.runFilter, "", "the All chip is All")
    compare(spy.count, 5)
  }

  function test_a_project_switch_keeps_the_filter() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply(screenEntries()), 0)
    store.toggleRunFilter("attention")
    store.project = rootB
    compare(store.runFilter, "attention")
    compare(ids(store.filteredRuns), "esc1,dead1")
  }

  // ---- the project filter and the display order (3.3)

  readonly property string rootD: "/home/u/d"

  // The reply for rootA..rootD: A has only parked runs, B an escalated and a
  // parked one, C a live and a parked one, D none.
  function projectEntries() {
    return [okEntry(tc.rootA, [entry("a-park1", "stopped", false, tc.rootA), entry("a-park2", "stopped", false, tc.rootA)]),
            okEntry(tc.rootB, [entry("b-esc1", "escalated", false, tc.rootB), entry("b-park1", "stopped", false, tc.rootB)]),
            okEntry(tc.rootC, [entry("c-live1", "started", true, tc.rootC), entry("c-park1", "stopped", false, tc.rootC)]),
            okEntry(tc.rootD, [])]
  }

  // A store with rootA ("alpha"), rootB ("beta"), rootC ("proj") and rootD
  // ("proj") registered, the panel open when `open`, and projectEntries()
  // applied.
  function projectsStore(open) {
    var roots = [tc.rootA, tc.rootB, tc.rootC, tc.rootD]
    var store = open ? activeRoots(roots) : makeWithRoots(roots); if (!store) return null
    reply(store.snapshotRunner.current, allReply(projectEntries()), 0)
    return store
  }

  // Each group as "name:attention/live/parked", in order.
  function groupText(store) {
    return store.groups.map(function(g) {
      return g.project.name + ":" + g.counts.attention + "/" + g.counts.live + "/" + g.counts.parked
    }).join(",")
  }

  // 1
  function test_the_list_reads_project_by_project_in_display_order() {
    var store = projectsStore(false); if (!store) return
    compare(store.projectFilter, "")
    compare(ids(store.runs), "a-park1,a-park2,b-esc1,b-park1,c-live1,c-park1", "runs stay in registry order")
    compare(groupText(store), "beta:1/0/1,proj:0/1/1,alpha:0/0/2",
            "attention first, then live, then the rest; D has no runs and no group")
    compare(store.groups[0].project.root, tc.rootB)
    compare(store.groups[1].project.root, tc.rootC)
    compare(store.groups[2].project.root, tc.rootA)
    compare(ids(store.filteredRuns), "b-esc1,b-park1,c-live1,c-park1,a-park1,a-park2",
            "group by group, each group in am's order")
    verify(store.filteredRuns[0] === store.groups[0].runs[0], "the same objects")
  }

  // 2
  function test_display_order_of_groups_is_filtered_runs() {
    var store = projectsStore(false); if (!store) return
    store.runFilter = "parked"
    store.searchQuery = "park1"
    compare(ids(Runs.displayOrder(store.groups)), ids(store.filteredRuns))
    compare(groupText(store), "alpha:0/0/1,beta:0/0/1,proj:0/0/1", "groups count only the runs the chip and the search keep")
    compare(ids(store.filteredRuns), "a-park1,b-park1,c-park1")
    store.runFilter = "attention"
    store.searchQuery = ""
    compare(ids(Runs.displayOrder(store.groups)), ids(store.filteredRuns))
    compare(ids(store.filteredRuns), "b-esc1")
  }

  function test_no_runs_give_no_groups_and_an_empty_list() {
    var store = make(); if (!store) return
    compare(store.groups.length, 0)
    compare(store.filteredRuns.length, 0)
  }

  // 3
  function test_chip_search_and_project_compose() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([
      okEntry(tc.rootA, [entry("a-live1", "started", true, tc.rootA), entry("a-esc2", "escalated", false, tc.rootA)]),
      okEntry(tc.rootB, [entry("b-live1", "started", true, tc.rootB), entry("b-esc1", "escalated", false, tc.rootB),
                         entry("b-esc2", "escalated", false, tc.rootB)])]), 0)
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-live1,b-esc1,b-esc2")
    compare(store.groups.length, 1)
    compare(store.groups[0].project.root, tc.rootB)
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "b-esc1,b-esc2")
    compare(store.groups.length, 1)
    store.searchQuery = "esc2"
    compare(ids(store.filteredRuns), "b-esc2", "A's esc2 is not listed")
    compare(store.groups.length, 1)
    compare(store.groups[0].project.root, tc.rootB)
    store.runFilter = ""
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "b-live1,b-esc1,b-esc2")
    compare(store.projectFilter, tc.rootB)
  }

  // 4
  function test_a_chip_that_empties_the_filtered_project_keeps_the_filter() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    store.runFilter = "live"
    compare(store.filteredRuns.length, 0, "B has no live run")
    compare(store.groups.length, 0)
    compare(store.projectFilter, tc.rootB, "judged against runs, not the chip's list")
    store.runFilter = ""
    store.searchQuery = "zzz"
    compare(store.filteredRuns.length, 0)
    compare(store.projectFilter, tc.rootB, "nor the search's")
    store.searchQuery = ""
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
  }

  // 5
  function test_toggle_project_filter_and_its_signal() {
    var store = projectsStore(false); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    var request = store.snapshotRunner.current
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(spy.count, 1)
    store.toggleProjectFilter(tc.rootC)
    compare(store.projectFilter, tc.rootC, "another project replaces the filter")
    compare(spy.count, 2)
    store.toggleProjectFilter(tc.rootC)
    compare(store.projectFilter, "", "the active project again is All")
    compare(spy.count, 3)
    store.toggleProjectFilter("")
    compare(store.projectFilter, "", "the All chip is All")
    compare(spy.count, 4, "emitted even when nothing changed")
    store.toggleProjectFilter(tc.rootB + "/")
    compare(store.projectFilter, tc.rootB, "a trailing / selects the project")
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    compare(spy.count, 5)
    store.toggleProjectFilter("")
    compare(spy.count, 6)
    var junk = [undefined, null, 42, {}, [tc.rootB]]
    for (var i = 0; i < junk.length; i++) {
      store.toggleProjectFilter(tc.rootB)
      compare(store.projectFilter, tc.rootB)
      store.toggleProjectFilter(junk[i])
      compare(store.projectFilter, "", "a non-string is All: " + i)
    }
    compare(spy.count, 6 + 2 * junk.length)
    store.toggleProjectFilter("/home/u/zz")
    compare(store.projectFilter, "", "an unregistered root is All")
    store.toggleProjectFilter(tc.rootD)
    compare(store.projectFilter, "", "a registered root with no runs is All")
    store.toggleProjectFilter("///")
    compare(store.projectFilter, "", "\"/\" is not registered")
    compare(spy.count, 6 + 2 * junk.length + 3, "one emission per call")
    compare(store.runFilter, "")
    compare(store.searchQuery, "")
    compare(store.project, "")
    compare(store.snapshotRunner.current, request, "no process is launched")
  }

  // Error paths: a registry entry with a trailing "/"
  function test_a_root_registered_with_a_trailing_slash_is_filtered_by_either_spelling() {
    var store = make(); if (!store) return
    store.projectRoots = [{ root: tc.rootB + "/", name: "beta" }, rootEntry(tc.rootA)]
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB + "/", [entry("b-esc1", "escalated", false, tc.rootB)]),
                                                  okEntry(tc.rootA, [entry("a-park1", "stopped", false, tc.rootA)])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "Runs.withProject removes the trailing /")
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1")
    store.toggleProjectFilter("")
    store.toggleProjectFilter(tc.rootB + "/")
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1")
  }

  // 6 and Review Focus 3, 4
  function test_the_registry_dropping_the_filtered_root_falls_back_to_all() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.projectRoots = registry([tc.rootA, tc.rootC, tc.rootD])
    compare(store.projectFilter, "", "synchronous, by the time the assignment returns")
    compare(spy.count, 1)
    compare(ids(store.filteredRuns), "c-live1,c-park1,a-park1,a-park2", "every remaining project")
    store.projectRoots = registry([tc.rootA, tc.rootB, tc.rootC, tc.rootD])
    reply(store.snapshotRunner.current, allReply(projectEntries()), 0)
    compare(store.projectFilter, "", "the project coming back does not bring its filter back")
    compare(ids(store.filteredRuns), "b-esc1,b-park1,c-live1,c-park1,a-park1,a-park2")
    compare(spy.count, 1)

    var emptied = projectsStore(false); if (!emptied) return
    emptied.toggleProjectFilter(tc.rootB)
    var spy2 = createTemporaryObject(spyC, tc, { target: emptied, signalName: "projectFilterToggled" })
    emptied.projectRoots = []
    compare(emptied.projectFilter, "", "an empty registry empties runs")
    compare(spy2.count, 1)
    compare(emptied.filteredRuns.length, 0)
  }

  // 7 and Review Focus 2
  function test_a_reply_that_leaves_the_project_without_runs_falls_back_to_all() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.refresh()
    var entries = projectEntries()
    entries[1] = okEntry(tc.rootB, [])
    reply(store.snapshotRunner.current, allReply(entries), 0)
    compare(store.projectFilter, "")
    compare(spy.count, 1)
    compare(ids(store.filteredRuns), "c-live1,c-park1,a-park1,a-park2")

    var missing = projectsStore(false); if (!missing) return
    missing.toggleProjectFilter(tc.rootB)
    var spy2 = createTemporaryObject(spyC, tc, { target: missing, signalName: "projectFilterToggled" })
    missing.refresh()
    reply(missing.snapshotRunner.current, allReply([tc.rootA, tc.rootB, tc.rootC, tc.rootD].map(function(r) {
      return tc.failEntry(r, "AmMissing", "am is not installed or not on PATH.")
    })), 0)
    compare(missing.amStatus, "missing")
    compare(missing.projectFilter, "", "am missing empties runs")
    compare(spy2.count, 1)
  }

  // 7 (failed entry) and Review Focus 5
  function test_a_failed_entry_or_envelope_keeps_the_project_filter() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.refresh()
    var entries = projectEntries()
    entries[1] = failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")
    reply(store.snapshotRunner.current, allReply(entries), 0)
    compare(store.projectErrors[tc.rootB], "AmTimeout: am did not answer within 60 s.")
    compare(store.projectFilter, tc.rootB, "a failed entry keeps B's runs")
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    store.refresh()
    reply(store.snapshotRunner.current,
          JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(store.amStatus, "error")
    compare(store.projectFilter, tc.rootB, "a failed envelope keeps every run")
    compare(spy.count, 0)
  }

  // 8
  function test_no_fallback_while_the_filter_still_holds() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.refresh()
    var entries = projectEntries()
    entries[0] = okEntry(tc.rootA, [entry("a-park3", "stopped", false, tc.rootA)])
    reply(store.snapshotRunner.current, allReply(entries), 0)
    compare(ids(store.runs), "a-park3,b-esc1,b-park1,c-live1,c-park1", "A's runs changed")
    compare(store.projectFilter, tc.rootB)
    store.projectRoots = registry([tc.rootB, tc.rootA, tc.rootC])
    compare(store.projectFilter, tc.rootB, "a registry change that keeps B")
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    compare(spy.count, 0)
  }

  // Review Focus 1
  function test_starting_over_resets_the_project_filter() {
    var store = projectsStore(true); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.resetCursor()
    compare(store.runs.length, 0)
    compare(store.projectFilter, "", "the old store's choice is not kept")
    compare(spy.count, 1)
    reply(store.snapshotRunner.current, allReply(projectEntries()), 0)
    compare(store.projectFilter, "")
    compare(spy.count, 1)
  }

  // 9
  function test_closing_the_panel_resets_the_project_filter_silently() {
    var store = projectsStore(true); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    store.runFilter = "attention"
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.active = false
    compare(store.projectFilter, "")
    compare(spy.count, 0, "the list is not on screen")
    compare(store.runFilter, "attention", "nothing else in stopLive changes")
    compare(ids(store.runs), "a-park1,a-park2,b-esc1,b-park1,c-live1,c-park1", "the runs stay")
    store.active = true
    compare(store.projectFilter, "", "opening leaves it at All")
    compare(spy.count, 0)
  }

  // 10
  function test_a_project_switch_keeps_the_project_filter() {
    var store = projectsStore(false); if (!store) return
    store.toggleProjectFilter(tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "projectFilterToggled" })
    store.project = tc.rootA
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    store.project = ""
    compare(store.projectFilter, tc.rootB)
    compare(ids(store.filteredRuns), "b-esc1,b-park1")
    compare(spy.count, 0)
  }

  // ---- attempt logs (5.2)

  // A snapshot entry of the started capture: runs.json's first `am runs` row
  // whose `status` is status-started.json's `am status` data. Its open attempt
  // is openCard explore 1 and doneCard spec 1 is an earlier, ok attempt. The
  // run id and project root (`root`, else rootA) are the test's; so is the
  // open attempt's status, in am's attempt vocabulary (started, ok).
  function treeEntry(id, status, root) {
    var e = F.load("runs.json").data.runs[0]
    e.id = id
    e.repo_dir = root || tc.rootA
    e.project.repo_dir = root || tc.rootA
    e.status = F.load("status-started.json").data
    e.status.run.id = id
    e.status.stories[1].subtasks[1].phases[1].attempts[0].status = status
    return e
  }

  // A fresh logs-attempt.json `am logs` reply, as one JSON line, whose stdout
  // artifact text is `stdout` and, when given, whose stderr artifact text is
  // `stderr` (else the capture's null).
  function logsReply(stdout, stderr) {
    var envelope = F.load("logs-attempt.json")
    // synthetic: the texts are the test's; the envelope is the capture's.
    envelope.data.artifacts.stdout.text = stdout
    if (stderr !== undefined) envelope.data.artifacts.stderr.text = stderr
    return JSON.stringify(envelope) + "\n"
  }

  function argv(proc) { return proc.command.join("|") }

  // Project A's snapshot listed r1 (treeEntry) and r1 is the selected run, so
  // its default attempt's logs are in flight.
  function opened(status) {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", status || "started")]), 0)
    store.selectedRunId = "r1"
    return store
  }

  function test_logs_defaults() {
    var store = make(); if (!store) return
    compare(store.selectedAttempt, null)
    compare(store.logsText, "")
    compare(store.logsTruncated, false)
    compare(store.logsFetchedMs, 0)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.logsStatus, "")
    verify(!store.logsRunner.current, "no logs fetch at start")
  }

  function test_selecting_a_run_fetches_its_default_attempt() {
    var store = opened(); if (!store) return
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(argv(proc), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
    compare(proc.launchGuard, "", "no guard")
    compare(store.selectedAttempt.card_id, tc.openCard)
    compare(store.selectedAttempt.phase, "explore")
    compare(store.selectedAttempt.attempt, 1)
    compare(store.logsStatus, "started", "the status the fetch was launched for")
    compare(store.logsLoading, true)
  }

  function test_select_attempt_and_refresh_launch_the_exact_argv() {
    var store = opened(); if (!store) return
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.doneCard + "|spec|1")
    compare(store.logsStatus, "ok")
    var first = store.logsRunner.current
    var seq = store.logsRunner.seq
    store.refreshLogs()
    compare(store.logsRunner.seq, seq + 1, "Refresh fetches again")
    verify(store.logsRunner.current !== first)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.doneCard + "|spec|1")
  }

  function test_no_logs_launch_without_a_run_or_a_selection() {
    var bare = make(); if (!bare) return
    bare.selectAttempt(tc.doneCard, "spec", 1)
    verify(!bare.logsRunner.current, "no run selected")
    compare(bare.selectedAttempt, null)
    bare.refreshLogs()
    verify(!bare.logsRunner.current)

    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), entry("r2", "started", true)]), 0)
    store.selectAttempt(tc.doneCard, "spec", 1)
    verify(!store.logsRunner.current, "no run selected")
    compare(store.selectedAttempt, null)
    store.selectedRunId = "r2"
    verify(!store.logsRunner.current, "a run with no attempt selects nothing")
    compare(store.selectedAttempt, null)
    store.refreshLogs()
    verify(!store.logsRunner.current, "no selection")
    store.selectAttempt(tc.doneCard, "spec", 0)
    store.selectAttempt(tc.doneCard, "", 1)
    store.selectAttempt("", "spec", 1)
    store.selectAttempt(tc.doneCard, "spec", "1")
    verify(!store.logsRunner.current, "not a real attempt")
  }

  function test_an_ok_logs_reply_sets_text_truncation_and_time() {
    var store = opened(); if (!store) return
    var before = Date.now()
    reply(store.logsRunner.current, logsReply("collecting...\n3 passed\n"), 0)
    var after = Date.now()
    compare(store.logsText, "collecting...\n3 passed")
    compare(store.logsTruncated, false)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    verify(store.logsFetchedMs >= before && store.logsFetchedMs <= after, "fetched now: " + store.logsFetchedMs)
    var lines = []
    for (var i = 0; i < 250; i++) lines.push("line " + i)
    store.refreshLogs()
    reply(store.logsRunner.current, logsReply(lines.join("\n") + "\n", "boom\n"), 0)
    var shown = store.logsText.split("\n")
    compare(shown.length, 201, "the last 200 stdout lines, then stderr")
    compare(shown[0], "line 50")
    compare(shown[199], "line 249")
    compare(shown[200], "boom")
    compare(store.logsTruncated, true)
  }

  function test_a_real_logs_reply_shows_the_attempts_output() {
    var store = opened(); if (!store) return
    var envelope = F.load("logs-attempt.json")
    reply(store.logsRunner.current, JSON.stringify(envelope) + "\n", 0)
    compare(store.logsText, envelope.data.artifacts.stdout.text.slice(0, -1), "the attempt's stdout")
    compare(store.logsText.split("\n").length, 1)
    compare(store.logsTruncated, false)
    compare(store.logsError, "")
    compare(store.logsLoading, false)
  }

  function test_logs_failures_keep_the_text_and_never_touch_am_status() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var types = ["AmMissing", "AmBadOutput", "HelperError", "Usage", "UnknownRunError"]
    for (var i = 0; i < types.length; i++) {
      store.refreshLogs()
      reply(store.logsRunner.current, JSON.stringify({ ok: false, error: { type: types[i], message: "m" } }) + "\n",
            types[i] === "Usage" ? 2 : 0)
      compare(store.logsError, types[i] + ": m", types[i])
      compare(store.logsText, "kept", types[i] + " keeps the last text")
      compare(store.logsLoading, false)
      compare(store.amStatus, "ok", types[i] + " is not a snapshot failure")
      compare(store.lastError, "")
      compare(store.runs.length, 1)
    }
    store.refreshLogs()
    reply(store.logsRunner.current, "Traceback (most recent call last):\n  oops {not json", 1)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 1).")
    store.refreshLogs()
    reply(store.logsRunner.current, "", 0)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 0).")
    store.refreshLogs()
    reply(store.logsRunner.current, "[]", 0)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 0).")
    compare(store.logsText, "kept")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refreshLogs()
    reply(store.logsRunner.current, logsReply("new\n"), 0)
    compare(store.logsError, "", "a good reply clears the error")
    compare(store.logsText, "new")
  }

  function test_only_the_latest_logs_fetch_is_applied() {
    var store = opened(); if (!store) return
    var first = store.logsRunner.current
    store.selectAttempt(tc.doneCard, "spec", 1)
    var second = store.logsRunner.current
    compare(first.running, false, "the older fetch is stopped")
    reply(second, logsReply("spec text\n"), 0)
    compare(store.logsText, "spec text")
    reply(first, logsReply("explore text\n"), 0)
    compare(store.logsText, "spec text", "a late reply for an older selection changes nothing")
  }

  // Review Focus 1.
  function test_selecting_another_attempt_clears_the_old_text_but_refresh_keeps_it() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("first\n"), 0)
    store.refreshLogs()
    compare(store.logsText, "first", "a refresh keeps the text until its reply")
    compare(store.logsLoading, true)
    store.selectAttempt(tc.doneCard, "spec", 1)
    compare(store.logsText, "", "another attempt's text is never shown under this heading")
    compare(store.logsFetchedMs, 0)
    compare(store.logsError, "")
    compare(store.logsTruncated, false)
    compare(store.logsLoading, true)
  }

  function test_changing_the_selected_run_resets_to_its_default_attempt() {
    var store = makeWithProject(rootA); if (!store) return
    // r2 is the done capture: runs.json's second row with status-done.json's
    // `am status`, under the test's run id and repo dir.
    var r2 = F.load("runs.json").data.runs[1]
    r2.id = "r2"
    r2.repo_dir = tc.rootA
    r2.project.repo_dir = tc.rootA
    r2.status = F.load("status-done.json").data
    r2.status.run.id = "r2"
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), r2]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("r1 text\n"), 0)
    store.selectAttempt(tc.doneCard, "spec", 1)
    store.selectedRunId = "r2"
    compare(store.selectedAttempt.card_id, "767b5f1c-506a-4daa-9157-0c838165cc63")
    compare(store.selectedAttempt.phase, "review")
    compare(store.selectedAttempt.attempt, 1)
    compare(store.logsText, "")
    compare(store.logsFetchedMs, 0)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r2|767b5f1c-506a-4daa-9157-0c838165cc63|review|1")
    var pending = store.logsRunner.current
    store.selectedRunId = ""
    compare(store.selectedAttempt, null, "clearing the run clears the selection")
    compare(store.logsText, "")
    compare(store.logsLoading, false)
    compare(store.logsStatus, "")
    compare(pending.running, false, "the pending fetch is stopped")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "", "and its late reply is dropped")
  }

  function test_logs_add_no_timer_and_none_runs_while_idle() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var timers = []
    for (var i = 0; i < store.data.length; i++) {
      var o = store.data[i]
      if (o && typeof o.interval === "number" && typeof o.repeat === "boolean") timers.push(o.objectName)
    }
    compare(timers.sort().join(","), "debounceTimer,livenessTimer,pollTimer,staleTimer", "the logs add no timer")
    compare(store.debounceTimer.running, false)
    compare(store.livenessTimer.running, false)
    compare(store.staleTimer.running, false)
    compare(store.pollTimer.running, false)
    compare(controlOf(store).pendingTimer.running, false)
  }

  // The next snapshot of project A lists `entries`.
  function snapshot(store, entries) {
    store.refresh()
    reply(store.snapshotRunner.current, okReply(entries), 0)
  }

  function test_a_snapshot_that_changes_the_attempt_status_fetches_once() {
    var store = opened("started"); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var seq = store.logsRunner.seq
    snapshot(store, [treeEntry("r1", "started")])
    compare(store.logsRunner.seq, seq, "an unchanged status fetches nothing")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}', 1)
    compare(store.logsRunner.seq, seq, "a failed snapshot fetches nothing")
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "started -> ok fetches the logs again")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
    compare(store.logsStatus, "ok")
    compare(store.logsText, "a", "the text stays until the new reply")
    snapshot(store, [treeEntry("r1", "ok")])
    compare(store.logsRunner.seq, seq + 1, "only once")
  }

  function test_a_snapshot_without_a_selected_run_fetches_no_logs() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    snapshot(store, [treeEntry("r1", "ok")])
    verify(!store.logsRunner.current, "nothing is selected")
  }

  // Review Focus 2.
  function test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears() {
    var store = makeWithProject(rootA); if (!store) return
    // synthetic: the run before any attempt exists; shape kept
    var bare = treeEntry("r1", "started")
    var stories = bare.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) stories[i].subtasks[j].phases = []
    }
    bare.status.rows = []
    reply(store.snapshotRunner.current, okReply([bare]), 0)
    store.selectedRunId = "r1"
    compare(store.selectedAttempt, null)
    verify(!store.logsRunner.current)
    snapshot(store, [treeEntry("r1", "started")])
    verify(store.selectedAttempt, "the first attempt is picked once it exists")
    compare(store.selectedAttempt.attempt, 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|" + tc.openCard + "|explore|1")
  }

  // The logs launch: python3, the script, then the project root and the
  // attempt, five arguments; the root is the selected run's project.root, one
  // element.
  function test_logs_argv_leads_with_the_runs_project_root() {
    var store = opened(); if (!store) return
    var procA = store.logsRunner.current
    compare(argv(procA), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/my proj|r1|" + tc.openCard + "|explore|1")
    compare(procA.command.length, 7, "five arguments after python3 and the script")
    compare(procA.command[2], "/home/u/my proj", "the root with a space is one argument")
  }

  // The run's project.root reaches the runner byte-for-byte.
  function test_logs_argv_keeps_an_odd_root_verbatim() {
    var odd = "/home/u/o'dd; $x"
    var store = makeWithProject(odd); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started", odd)]), 0)
    store.selectedRunId = "r1"
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(proc.command.length, 7)
    compare(proc.command[2], odd, "not split, quoted, trimmed or normalised")
    compare(proc.command[3], "r1")
  }

  // ---- run controls (S2 4.1): the helpers the tests here share; the control tests are in tst_run_control_store.qml

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

  function ctlOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  // ---- alerts (S2 4.4): the helpers the tests above share; the alerts tests are in tst_run_alerts_store.qml

  function escalated(id) { return entry(id, "escalated", false) }
  function toastIds(store) { return alerts(store).toasts.map(function(t) { return t.id }).join(",") }

  // ---- list snapshots

  // The captured runs' project root, and their run ids (runs.json).
  readonly property string capRoot: "/home/user/Code/omarchy-project-manager"
  readonly property string startedRun: "20261008T143823Z-e795ad19"
  readonly property string doneRun: "20261008T143807Z-63060df3"

  // runs-snapshot-all.py's reply for the captures: the captured root's entry
  // lists runs.json's two `am runs` rows, each with `status` replaced by its
  // `am status` data (status-started.json, status-done.json); with
  // `escalate`, the started run's is status-escalated.json's data
  // (synthetic). `extra` entries come last.
  function capturedList(extra, escalate) {
    var runs = F.load("runs.json").data.runs
    runs[0].status = F.load(escalate ? "status-escalated.json" : "status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return allReply([okEntry(tc.capRoot, runs.concat(extra || []))])
  }

  function test_a_list_snapshot_asks_for_every_registered_root() {
    var store = makeWithProject(tc.capRoot); if (!store) return
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    compare(store.snapshotRunner.current.launchGuard, "", "no guard")
    store.refresh()
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
  }

  function test_a_list_reply_lists_the_roots_runs_and_covers_them_at_0() {
    var store = makeWithProject(tc.capRoot); if (!store) return
    // synthetic: a run whose repo_dir is another project's, listed under the captured root.
    reply(store.snapshotRunner.current, capturedList([entry("extra1", "done", false, "/home/u/elsewhere")]), 0)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun + ",extra1", "the entry's runs, in am's order, whatever their repo_dir")
    compare(store.runs[2].project.root, tc.capRoot, "a run belongs to the root whose entry lists it")
    compare(store.asOfSeq, 0)
    compare(Object.keys(store.appliedSeq).join(","), [tc.startedRun, tc.doneRun, "extra1"].join(","))
    compare(store.appliedSeq[tc.startedRun], 0)
  }

  function test_a_busy_root_keeps_its_runs_and_says_why() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    store.refresh()
    // synthetic: am's StoreBusyError, which runs-snapshot-all.py puts in the root's entry unchanged.
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "StoreBusyError", "the am store is busy; try again")]), 0)
    compare(ids(store.runs), "a", "the last good runs stay")
    compare(store.projectErrors[tc.rootA], "StoreBusyError: the am store is busy; try again")
    compare(store.amStatus, "error", "no root answered")
    compare(store.lastError, "StoreBusyError: the am store is busy; try again")
    compare(store.stale, false, "stale is left as it was")
    compare(alerts(store).toasts.length, 0)
    var seq = store.snapshotRunner.seq
    store.livenessTimer.triggered()
    compare(store.snapshotRunner.seq, seq + 1, "the next tick retries")
    reply(store.snapshotRunner.current, okReply([entry("a", "started", true)]), 0)
    compare(store.amStatus, "ok")
    compare(Object.keys(store.projectErrors).length, 0)
  }

  function test_am_missing_forgets_the_coverage_and_a_project_switch_keeps_it() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("r1", "started", true)]), 0)
    compare(store.appliedSeq.r1, 0)
    store.project = rootB
    compare(store.appliedSeq.r1, 0, "a project switch keeps the coverage")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(Object.keys(store.appliedSeq).length, 0, "AmMissing forgets it")
    compare(store.asOfSeq, 0)
  }

  // ---- nudges

  // An active store on the captured runs' project whose first list snapshot
  // was capturedList(extra): both captured runs are covered at 0 and the
  // watch runs.
  function capturedStore(extra) {
    var store = activeStore(tc.capRoot); if (!store) return null
    reply(store.snapshotRunner.current, capturedList(extra), 0)
    verify(store.watchProc, "the watch was started")
    return store
  }

  // synthetic: one runs-watch.py changed line, {"changed": [{run, seq}, ...]},
  // for pairs [run, seq, run, seq, ...].
  function nudge(store, pairs) {
    var list = []
    for (var i = 0; i < pairs.length; i += 2) list.push({ run: pairs[i], seq: pairs[i + 1] })
    sendLine(store.watchProc, { changed: list })
  }

  function test_invalid_changed_entries_are_ignored() {
    var store = capturedStore(); if (!store) return
    // synthetic: changed entries runs-watch.py never prints.
    var lines = ['{"changed": ["' + tc.doneRun + '"]}', '{"changed": [{"run": "x", "seq": 0}]}',
                 '{"changed": [{"run": "x", "seq": -3}]}', '{"changed": [{"run": "x", "seq": 2.5}]}',
                 '{"changed": [{"run": "x", "seq": "990"}]}', '{"changed": [{"run": "", "seq": 990}]}',
                 '{"changed": [{"run": 7, "seq": 990}]}', '{"changed": [{"seq": 990}]}',
                 '{"changed": [null, [], 3]}', '{"changed": []}']
    for (var i = 0; i < lines.length; i++) {
      sendLine(store.watchProc, lines[i])
      compare(store.debounceTimer.running, false, lines[i])
      compare(Object.keys(store.nudges).length, 0, lines[i])
    }
    sendLine(store.watchProc, '{"changed": ["x", {"run": "' + tc.doneRun + '", "seq": 990}, {"run": "y", "seq": 0}]}')
    compare(store.debounceTimer.running, true, "one valid entry is enough")
    compare(Object.keys(store.nudges).join(","), tc.doneRun)
    compare(store.nudges[tc.doneRun], 990)
  }

  function test_nudges_keep_the_highest_seq_per_run() {
    var store = capturedStore(); if (!store) return
    nudge(store, [tc.doneRun, 995])
    nudge(store, [tc.doneRun, 993, tc.startedRun, 990])
    nudge(store, [tc.doneRun, 997])
    compare(store.nudges[tc.doneRun], 997)
    compare(store.nudges[tc.startedRun], 990)
    compare(Object.keys(store.nudges).join(","), tc.doneRun + "," + tc.startedRun, "in first-nudge order")
  }

  function test_a_cursor_line_sets_the_watch_cursor() {
    var store = capturedStore(); if (!store) return
    compare(store.watchCursor, 0)
    // synthetic: runs-watch.py's cursor lines.
    sendLine(store.watchProc, { cursor: 1005 })
    compare(store.watchCursor, 1005)
    var bad = ['{"cursor": -1}', '{"cursor": 2.5}', '{"cursor": "1006"}', '{"cursor": null}', '{"cursor": true}']
    for (var i = 0; i < bad.length; i++) {
      sendLine(store.watchProc, bad[i])
      compare(store.watchCursor, 1005, bad[i])
    }
    sendLine(store.watchProc, { cursor: 0 })
    compare(store.watchCursor, 0, "0 is a cursor too")
    compare(store.debounceTimer.running, false, "a cursor is not a change")
  }

  function test_a_nudge_for_a_listed_run_always_costs_a_snapshot_of_its_root() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    nudge(store, [tc.startedRun, 1, tc.doneRun, 900])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot, whatever the seqs")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    compare(Object.keys(store.nudges).length, 0, "the nudges were taken")
  }

  function test_a_nudge_for_an_unknown_run_costs_one_list_snapshot() {
    var store = capturedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    // synthetic: a run am started after the list, beside a held run.
    nudge(store, [tc.doneRun, 1005, "20261008T150000Z-0a1b2c3d", 1006])
    nudge(store, ["20261008T150000Z-0a1b2c3d", 1007])
    fire(store.debounceTimer)
    compare(store.snapshotRunner.seq, seq + 1, "exactly one list snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.capRoot)
    compare(Object.keys(store.nudges).length, 0)
  }

  function test_a_project_switch_keeps_the_nudges_and_the_cursor() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.project = rootB
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.debounceTimer.running, true)
    compare(store.watchCursor, 1005)
  }

  // ---- logs for a run of any project (3.5); its control tests are in tst_run_control_store.qml

  // rootA and rootB registered, `open` the open project ("" for none), and
  // the first snapshot listed aRuns under A and bRuns under B.
  function crossStore(open, aRuns, bRuns) {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    store.project = open
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, aRuns), okEntry(tc.rootB, bRuns)]), 0)
    return store
  }

  // A run as the store holds it, built from snapshot entry `e`: normalized,
  // with no project root unless `root` is given.
  function held(e, root) {
    var row = {}
    for (var k in e) if (k !== "status") row[k] = e[k]
    var run = Runs.normalizeRun({ row: row, status: e.status })
    return root === undefined ? run : Runs.withProject(run, root, "")
  }

  // 8
  function test_logs_of_another_projects_run_load_with_no_project_open() {
    var store = crossStore("", [], [treeEntry("rb", "started", rootB)]); if (!store) return
    store.selectedRunId = "rb"
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(argv(proc), "python3|/plugin/core/backend/runs/runs-logs.py|/home/u/b|rb|" + tc.openCard + "|explore|1")
    compare(proc.launchGuard, "")
    reply(proc, logsReply("x\n"), 0)
    compare(store.logsText, "x")
  }

  // 9
  function test_a_logs_reply_after_a_project_switch_lands() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    store.refreshLogs()
    var pending = store.logsRunner.current
    compare(store.logsLoading, true)
    store.project = rootB
    compare(store.logsLoading, true, "still in flight")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "late", "the reply is applied")
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.selectedRunId, "r1")
    verify(store.selectedAttempt !== null)
  }

  // 10
  function test_no_logs_for_a_selected_run_without_a_project_root() {
    var store = make(); if (!store) return
    store.runs = [held(treeEntry("r1", "started"))]
    compare(store.runs[0].project.root, undefined, "normalizeRun's project has no root")
    store.selectedRunId = "r1"
    verify(store.selectedAttempt !== null, "the default attempt is selected")
    verify(!store.logsRunner.current, "no logs launch")
    compare(store.logsLoading, false)
  }

  // Review Focus 3.
  function test_a_selected_run_that_leaves_the_snapshot_launches_no_logs() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var seq = store.logsRunner.seq
    snapshot(store, [])
    compare(store.runById("r1"), null)
    compare(store.logsRunner.seq, seq, "no launch for a run not in the snapshot")
    compare(store.logsLoading, false)
    compare(store.logsText, "kept")
  }

  // ---- cursor reset

  // synthetic: runs-watch.py's forwarded hello for watch-hello.json's schema_2
  // (schema, am, head, storeId) with cursorReset set to `value`.
  function resetHello(value) {
    var h = F.load("watch-hello.json").schema_2
    return { hello: { schema: h.schema, am: h.am, head: h.head, cursorReset: value, storeId: h.store_id } }
  }

  function test_a_cursor_reset_starts_over_from_a_list_snapshot() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    store.refresh()
    var old = store.snapshotRunner.current
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    sendLine(store.watchProc, resetHello(true))
    compare(store.amSchema, 2, "still a hello")
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(store.runs.length, 0)
    compare(Object.keys(store.runsByProject).length, 0, "every root's list is forgotten too")
    compare(alerts(store).alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(old.running, false, "the old store's snapshot is stopped")
    var list = store.snapshotRunner.current
    verify(list !== old, "one list snapshot is launched")
    compare(argv(list), tc.snapCmd + "|" + tc.capRoot)
    reply(old, capturedList(), 0)
    compare(store.runs.length, 0, "the stopped snapshot's late reply changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    reply(list, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(alerts(store).toasts.length, 0, "the first list after a reset only arms")
    compare(alerts(store).alertsArmed, true)
    compare(store.appliedSeq[tc.startedRun], 0)
  }

  function test_only_a_true_cursor_reset_starts_over() {
    var store = capturedStore(); if (!store) return
    var values = [false, "true", 1, null, undefined]
    for (var i = 0; i < values.length; i++) {
      var label = "cursorReset " + JSON.stringify(values[i])
      var seq = store.snapshotRunner.seq
      sendLine(store.watchProc, resetHello(values[i]))
      compare(store.snapshotRunner.seq, seq, label)
      compare(store.runs.length, 2, label)
      compare(Object.keys(store.appliedSeq).length, 2, label)
      compare(alerts(store).alertsArmed, true, label)
    }
  }

  // ---- store id reset

  // The captures' store_id: every capture shares it.
  function fixtureStore() { return F.load("runs.json").data.store_id }

  // synthetic: another am store's id -- the fixture id with its last
  // character changed.
  function otherStore() {
    var id = fixtureStore()
    return id.slice(0, -1) + (id.charAt(id.length - 1) === "0" ? "1" : "0")
  }

  // capturedStore() whose watch then named the captures' store in its hello
  // (synthetic: storeHello with the fixture store id): storeId is the
  // fixture's, and nothing was reset.
  function namedStore() {
    var store = capturedStore(); if (!store) return null
    sendLine(store.watchProc, storeHello(tc.fixtureStore(), 989, false))
    compare(store.storeId, tc.fixtureStore())
    compare(store.runs.length, 2)
    return store
  }

  function test_a_store_id_starts_as_none() {
    var store = make(); if (!store) return
    compare(store.storeId, "")
  }

  function test_a_list_reply_never_reads_a_store_id() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    store.refresh()
    var seq = store.snapshotRunner.seq
    // synthetic: the captured list carrying another store's id at the top and in its entry.
    var value = JSON.parse(capturedList())
    value.store_id = otherStore()
    value.projects[0].store_id = otherStore()
    reply(store.snapshotRunner.current, JSON.stringify(value) + "\n", 0)
    compare(store.storeId, fixtureStore(), "the list names no store")
    compare(store.watchCursor, 1005)
    compare(store.nudges[tc.doneRun], 1005)
    compare(store.debounceTimer.running, true)
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
    compare(store.snapshotRunner.seq, seq, "no further list snapshot")
    var fresh = capturedStore(); if (!fresh) return
    compare(fresh.storeId, "", "a list alone names no store")
  }

  function test_the_store_id_outlives_the_watch_a_project_switch_and_am_missing() {
    var store = namedStore(); if (!store) return
    endWatch(store.watchProc, "", 0)
    compare(store.storeId, fixtureStore(), "the watch ending")
    store.active = false
    compare(store.storeId, fixtureStore(), "the panel closing")
    store.project = rootB
    compare(store.storeId, fixtureStore(), "a project switch")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.capRoot, "AmMissing", "am is not installed.")]), 0)
    compare(store.amStatus, "missing")
    compare(store.storeId, fixtureStore(), "AmMissing")
  }

  function test_a_refused_list_naming_another_store_changes_no_store_id() {
    var store = namedStore(); if (!store) return
    store.refresh()
    // synthetic: a whole-call refusal carrying another store's id.
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, store_id: otherStore(),
          error: { type: "HelperError", message: "The runs snapshot failed: boom" } }) + "\n", 1)
    compare(store.storeId, fixtureStore())
    compare(store.amStatus, "error")
    compare(ids(store.runs), tc.startedRun + "," + tc.doneRun)
  }

  // synthetic: runs-watch.py's forwarded schema_2 hello (resetHello) with
  // storeId `id` (the key absent when undefined), head `head` and
  // cursorReset `reset`.
  function storeHello(id, head, reset) {
    var value = resetHello(reset)
    value.hello.head = head
    if (id === undefined) delete value.hello.storeId
    else value.hello.storeId = id
    return value
  }

  function test_a_hello_with_the_seen_store_id_keeps_the_live_state() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(fixtureStore(), 1005, false))
    compare(store.amSchema, 2)
    compare(store.storeId, fixtureStore())
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
    compare(store.runs.length, 2)
    compare(Object.keys(store.appliedSeq).length, 2)
    compare(store.watchCursor, 1005)
    compare(store.nudges[tc.doneRun], 1005)
    compare(alerts(store).alertsArmed, true)
  }

  function test_a_hello_from_another_store_starts_over_from_a_list_snapshot() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    store.refresh()
    var old = store.snapshotRunner.current
    nudge(store, [tc.startedRun, 1006])
    store.selectedRunId = tc.doneRun
    // A head above the cursor: cursorReset is false, yet the store changed.
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    compare(store.amSchema, 2, "still a hello")
    compare(store.storeId, otherStore())
    compare(Object.keys(store.appliedSeq).length, 0)
    compare(store.asOfSeq, 0)
    compare(store.watchCursor, 0)
    compare(Object.keys(store.nudges).length, 0)
    compare(store.debounceTimer.running, false)
    compare(store.runs.length, 0)
    compare(alerts(store).alertsArmed, false)
    compare(store.selectedRunId, tc.doneRun, "the selection is untouched")
    compare(old.running, false, "the old store's snapshot is stopped")
    var list = store.snapshotRunner.current
    verify(list !== old, "one list snapshot is launched")
    var seq = store.snapshotRunner.seq
    reply(old, capturedList(), 0)
    compare(store.runs.length, 0, "the stopped snapshot's late reply changes nothing")
    compare(Object.keys(store.appliedSeq).length, 0)
    reply(list, capturedList([], true), 0)
    compare(store.runs[0].status, "escalated")
    compare(alerts(store).toasts.length, 0, "the new store's first list only arms")
    compare(alerts(store).alertsArmed, true)
    compare(store.appliedSeq[tc.startedRun], 0)
    compare(store.snapshotRunner.seq, seq, "its reply launches no further snapshot")
  }

  function test_a_hello_from_another_store_with_cursor_reset_launches_one_list() {
    var store = namedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(otherStore(), 900, true))
    compare(store.snapshotRunner.seq, seq + 1, "one list snapshot, not two")
    compare(store.storeId, otherStore())
    compare(store.runs.length, 0)
  }

  function test_the_first_store_id_a_hello_names_resets_nothing() {
    var store = capturedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(fixtureStore(), 1005, false))
    compare(store.storeId, fixtureStore())
    compare(store.runs.length, 2)
    compare(Object.keys(store.appliedSeq).length, 2)
    compare(store.watchCursor, 1005)
    compare(store.snapshotRunner.seq, seq, "no list snapshot")
  }

  function test_a_hello_without_a_store_id_is_ignored() {
    var store = namedStore(); if (!store) return
    sendLine(store.watchProc, { cursor: 1005 })
    nudge(store, [tc.doneRun, 1005])
    var bad = ["", 7, null, { id: "x" }, undefined]
    for (var i = 0; i < bad.length; i++) {
      var label = "storeId " + JSON.stringify(bad[i])
      var seq = store.snapshotRunner.seq
      sendLine(store.watchProc, storeHello(bad[i], 1200, false))
      compare(store.storeId, fixtureStore(), label)
      compare(store.snapshotRunner.seq, seq, label + ": no list snapshot")
      compare(store.runs.length, 2, label)
      compare(store.watchCursor, 1005, label)
      compare(store.nudges[tc.doneRun], 1005, label)
    }
    var before = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(undefined, 900, true))
    compare(store.snapshotRunner.seq, before + 1, "cursorReset alone still starts over")
    compare(store.storeId, fixtureStore())
  }

  // Review Focus 3.
  function test_a_store_that_changes_back_starts_over_again() {
    var store = namedStore(); if (!store) return
    var seq = store.snapshotRunner.seq
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.snapshotRunner.seq, seq + 1)
    sendLine(store.watchProc, { cursor: 1210 })
    sendLine(store.watchProc, storeHello(fixtureStore(), 1300, false))
    compare(store.storeId, fixtureStore(), "the first store again is a change too")
    compare(store.watchCursor, 0)
    compare(store.runs.length, 0)
    compare(store.snapshotRunner.seq, seq + 2)
  }

  // Review Focus 4.
  function test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied() {
    var store = namedStore(); if (!store) return
    store.refresh()
    var old = store.snapshotRunner.current
    sendLine(store.watchProc, storeHello(otherStore(), 1200, false))
    reply(old, capturedList(), 0)
    compare(store.runs.length, 0, "the old store's list was superseded")
    compare(store.storeId, otherStore(), "and names no store")
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.runs.length, 2)
  }
  // ---- snapshotReplied (split-runstore 2.2)

  // Every snapshotReplied of `store` from now on, as {root, outcome,
  // previous, runs, status, all, error}: the arguments (previousRuns and runs
  // as ids) and the store's amStatus, ids(runs) and lastError at emission.
  function recordReplies(store) {
    var out = []
    store.snapshotReplied.connect(function(root, outcome, previousRuns, runs) {
      out.push({ root: root, outcome: outcome, previous: ids(previousRuns), runs: ids(runs),
                 status: store.amStatus, all: ids(store.runs), error: store.lastError })
    })
    return out
  }

  // R1
  function test_an_ok_reply_emits_ok_per_root_in_registry_order() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)])]), 0)
    var seen = recordReplies(store)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotReplied" })
    store.refresh()
    // B's entry first: the registry's order decides, not the reply's.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB), entry("b2", "started", true, tc.rootB)]),
                                                  okEntry(tc.rootA, [entry("a2", "started", true)])]), 0)
    compare(spy.count, 2)
    compare(seen.length, 2)
    compare(seen[0].root, tc.rootA, "A first, in registry order")
    compare(seen[0].outcome, "ok")
    compare(seen[0].previous, "a1", "the root's runs before the reply")
    compare(seen[0].runs, "a2", "and after it")
    compare(seen[1].root, tc.rootB)
    compare(seen[1].outcome, "ok")
    compare(seen[1].previous, "b1")
    compare(seen[1].runs, "b1,b2")
    compare(seen[0].all, "a2,b1,b2", "emitted after the merged runs are applied")
    compare(seen[0].status, "ok")
    compare(seen[0].error, "")
    compare(spy.signalArguments[0][2][0].project.name, "alpha", "previousRuns are the tagged runs")
    compare(spy.signalArguments[1][3][1].project.name, "beta", "and so are runs")
  }

  // R2
  function test_a_root_with_no_entry_emits_nothing_and_a_failed_entry_emits_failed() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    var seen = recordReplies(store)
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootC, "AmTimeout", "am did not answer within 60 s."),
                                                  okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    compare(seen.length, 2, "B, with no entry, emits nothing")
    compare(seen[0].root, tc.rootA)
    compare(seen[0].outcome, "ok")
    compare(seen[0].previous, "", "a root with no runs before: []")
    compare(seen[0].runs, "a1")
    compare(seen[1].root, tc.rootC)
    compare(seen[1].outcome, "failed")
    compare(seen[1].previous, "")
    compare(seen[1].runs, "", "a failed root's runs are []")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    compare(seen.length, 4)
    compare(seen[2].root, tc.rootA)
    compare(seen[2].outcome, "failed")
    compare(seen[2].previous, "a1", "a failed root's runs before the reply")
    compare(seen[2].runs, "")
    compare(seen[3].root, tc.rootC)
    compare(seen[3].outcome, "ok")
    compare(seen[3].runs, "c1")
  }

  // R3
  function test_a_run_listed_under_two_roots_is_in_its_owners_runs_only() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var seen = recordReplies(store)
    // synthetic: x under both roots, and a run without an id under B.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("x", "done", false)]),
                                                  okEntry(tc.rootB, [entry("x", "done", false, tc.rootB), entry("b1", "done", false, tc.rootB),
                                                                     entry("", "done", false, tc.rootB)])]), 0)
    compare(seen.length, 2)
    compare(seen[0].runs, "x", "A owns x")
    compare(seen[1].runs, "b1", "B's runs lack x, and a run without an id is no root's")
    compare(ids(store.runsByProject[tc.rootB]), "x,b1,", "B's own list keeps all three")
  }

  // R4
  function test_every_entry_failed_emits_failed_after_the_error_is_set() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]), okEntry(tc.rootB, [])]), 0)
    var seen = recordReplies(store)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s."),
                                                  failEntry(tc.rootA, "HelperError", "boom")]), 0)
    compare(seen.length, 2)
    compare(seen[0].root, tc.rootA)
    compare(seen[0].outcome, "failed")
    compare(seen[0].previous, "a1")
    compare(seen[0].runs, "")
    compare(seen[1].root, tc.rootB)
    compare(seen[1].outcome, "failed")
    compare(seen[0].status, "error", "amStatus is set before the emission")
    compare(seen[0].error, "AmTimeout: am did not answer within 60 s.", "lastError is the first failed entry's sentence")
    compare(seen[0].all, "a1", "the runs stay")
  }

  // R5
  function test_am_missing_emits_missing_per_matched_root_after_the_runs_are_emptied() {
    var store = makeWithRoots([tc.rootA, tc.rootB, tc.rootC]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "done", false)]),
                                                  okEntry(tc.rootB, [entry("b1", "done", false, tc.rootB)]),
                                                  okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)])]), 0)
    var seen = recordReplies(store)
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootB, "AmMissing", "am is not installed."),
                                                  failEntry(tc.rootA, "AmMissing", "am is not installed.")]), 0)
    compare(seen.length, 2, "C, with no entry, emits nothing")
    compare(seen[0].root, tc.rootA, "registry order")
    compare(seen[0].outcome, "missing")
    compare(seen[0].previous, "a1", "the root's runs before the reply")
    compare(seen[0].runs, "")
    compare(seen[0].all, "", "emitted after the runs are emptied")
    compare(seen[0].status, "missing")
    compare(seen[1].root, tc.rootB)
    compare(seen[1].outcome, "missing")
    compare(seen[1].previous, "b1")
  }

  // R6
  function test_a_reply_with_no_usable_result_emits_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotReplied" })
    // synthetic: entries for no registered root.
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootC, [entry("c1", "done", false, tc.rootC)]), null, "x"]), 0)
    compare(store.amStatus, "error", "no matched entry")
    compare(spy.count, 0)
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage", message: "usage" } }) + "\n", 2)
    compare(spy.count, 0, "an ok: false envelope")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    compare(spy.count, 0, "garbage")
    store.refresh()
    var gone = store.snapshotRunner.current
    store.projectRoots = registry([tc.rootC])
    reply(gone, allReply([okEntry(tc.rootA, [entry("a1", "done", false)])]), 0)
    compare(spy.count, 0, "every launched root gone")
  }

  // R7
  function test_a_reply_while_closed_still_emits() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    compare(store.active, false)
    var seen = recordReplies(store)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [entry("a1", "escalated", false)])]), 0)
    compare(seen.length, 1)
    compare(seen[0].outcome, "ok")
    compare(seen[0].runs, "a1")
  }

  // R8
  function test_a_cursor_reset_emits_missing_for_every_usable_root() {
    var store = threeRoots(); if (!store) return
    var seen = recordReplies(store)
    sendLine(store.watchProc, resetHello(true))
    compare(seen.length, 3)
    var roots = [tc.rootA, tc.rootB, tc.rootC]
    var before = ["a1", "b1", "c1"]
    for (var i = 0; i < 3; i++) {
      compare(seen[i].root, roots[i], "registry order")
      compare(seen[i].outcome, "missing")
      compare(seen[i].previous, before[i], "the root's runs before the reset")
      compare(seen[i].runs, "")
      compare(seen[i].all, "", "emitted after the runs are cleared")
    }
  }


  // ---- the run store alone

  // R4
  function test_a_snapshot_settles_nothing_without_the_route() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var cc = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (cc.status !== Component.Ready) { fail(cc.errorString()); return }
    var c = cc.createObject(tc, { backendDir: "/plugin/core/backend/" })
    c.runs = Qt.binding(function() { return store.runs })
    store.projectRoots = [rootEntry(rootA)]
    store.project = rootA
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(c.control("pause", "r1"), true)
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])])
    compare(store.amStatus, "ok")
    compare(c.pending.r1, "pause", "the run store no longer settles requests itself")
  }

  // R5 and Review Focus 1, 5
  function test_opening_the_run_store_alone_reads_no_switch() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    store.projectRoots = [rootEntry(rootA)]
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    var seq = store.snapshotRunner.seq
    store.active = true
    var names = ["settingsLoadRunner", "settingsSaveRunner", "notifyOnEscalation"]
    for (var i = 0; i < names.length; i++)
      compare(typeof store[names[i]], "undefined", names[i] + ": the run store has no switch to read")
    compare(store.snapshotRunner.seq, seq + 1, "the opening still snapshots")
    verify(store.snapshotRunner.current)
  }

  // R-D5 and Review Focus 4
  function test_closing_and_switching_the_run_store_touch_no_dispatch() {
    var store = makeWithProject(rootA); if (!store) return
    var d = wireDispatch(store, false); if (!d) return
    d.project = rootA
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    compare(d.dispatchState, "previewing")
    store.active = true
    store.active = false
    compare(d.dispatchState, "previewing", "closing the run store leaves the dispatch")
    store.project = rootB
    compare(d.dispatchState, "previewing", "switching the run store's project leaves the dispatch")
  }

  // ---- history rows in the filtered list (3.3 history)

  // Run `id` of `root` as RunHistoryStore builds one: am status `status`,
  // milestone "m-<id>", started at `startedAt`, its lease live when `live`
  // (no lease otherwise), tagged with rootEntry(root)'s name.
  function histRun(id, root, status, startedAt, live) {
    var st = { run: { id: id, milestone_id: "m-" + id, status: status }, rows: [], stories: [], subtasks: [] }
    if (live) st.control = { lease: { pid: 42, host: "h", heartbeat_at: "2026-10-01T00:00:05Z", accepting: true, live: true } }
    var raw = { row: { id: id, repo_dir: root, started_at: startedAt, status: status }, status: st }
    return Runs.withProject(Runs.normalizeRun(raw), root, tc.rootEntry(root).name)
  }

  // rootA ("alpha") and rootB ("beta") registered, no project open, the
  // snapshot answered: A lists a-live1 (running) and a-park1, B lists b-park1.
  function historyStore() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([
      okEntry(tc.rootA, [entry("a-live1", "started", true, tc.rootA), entry("a-park1", "stopped", false, tc.rootA)]),
      okEntry(tc.rootB, [entry("b-park1", "stopped", false, tc.rootB)])]), 0)
    return store
  }

  // History for historyStore(), interleaved by root: A's a-h1 (done), B's
  // b-h1 (escalated), A's a-h2 (parked).
  function historyPage() {
    return [histRun("a-h1", tc.rootA, "done", "2026-09-20T00:00:00Z"),
            histRun("b-h1", tc.rootB, "escalated", "2026-09-19T00:00:00Z"),
            histRun("a-h2", tc.rootA, "stopped", "2026-09-18T00:00:00Z")]
  }

  // H1
  function test_each_projects_history_follows_its_snapshot_runs() {
    var store = historyStore(); if (!store) return
    compare(groupText(store), "alpha:0/1/1,beta:0/0/1", "before any history")
    store.historyRuns = historyPage()
    compare(ids(store.listedRuns), "a-live1,a-park1,b-park1,a-h1,b-h1,a-h2")
    compare(groupText(store), "beta:1/0/1,alpha:0/1/2", "b-h1 counts in beta's attention, a-h2 in alpha's parked")
    compare(ids(store.filteredRuns), "b-park1,b-h1,a-live1,a-park1,a-h1,a-h2",
            "each group: its snapshot runs, then its history in historyRuns order")
    compare(ids(Runs.displayOrder(store.groups)), ids(store.filteredRuns))
    verify(store.filteredRuns[1] === store.historyRuns[1], "the history objects themselves")
  }

  // H2
  function test_the_snapshot_wins_and_odd_history_entries_are_skipped() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    reply(store.snapshotRunner.current, okReply([entry("a-park1", "stopped", false, tc.rootA)]), 0)
    var seq = store.snapshotRunner.seq
    var applied = JSON.stringify(store.appliedSeq)
    var known = JSON.stringify(store.knownRunIds())
    var spies = ["snapshotReplied", "runsNudged", "projectFilterToggled", "runFilterToggled"].map(function(name) {
      return createTemporaryObject(spyC, tc, { target: store, signalName: name })
    })
    store.historyRuns = [null, 7, "x", [], histRun("a-park1", tc.rootA, "done", "2026-09-20T00:00:00Z"),
                         histRun("a-h1", tc.rootA, "started", "2026-09-19T00:00:00Z", true),
                         histRun("a-h1", tc.rootA, "done", "2026-09-18T00:00:00Z")]
    compare(ids(store.listedRuns), "a-park1,a-h1", "each id once")
    verify(store.listedRuns[0] === store.runs[0], "the snapshot's object wins")
    verify(store.listedRuns[1] === store.historyRuns[5], "the first of a duplicated history id")
    compare(Runs.runState(store.listedRuns[1]), "running")
    compare(ids(store.filteredRuns), "a-park1,a-h1")
    store.runFilter = "parked"
    compare(ids(store.filteredRuns), "a-park1", "the shared id is the snapshot's parked run")
    compare(ids(store.runs), "a-park1", "runs stays the snapshot")
    compare(store.hasRunningRun, false, "a running history run is not the snapshot's")
    compare(JSON.stringify(store.appliedSeq), applied)
    compare(JSON.stringify(store.knownRunIds()), known)
    compare(store.snapshotRunner.seq, seq, "no snapshot launched")
    for (var i = 0; i < spies.length; i++) compare(spies[i].count, 0, spies[i].signalName)
  }

  // Review Focus 2
  function test_a_history_that_is_not_an_array_lists_the_snapshot_alone() {
    var store = historyStore(); if (!store) return
    var values = [null, "runs", 3, ({ id: "a-h1" })]
    for (var i = 0; i < values.length; i++) {
      store.historyRuns = values[i]
      compare(ids(store.listedRuns), "a-live1,a-park1,b-park1", "historyRuns " + JSON.stringify(values[i]))
      compare(ids(store.filteredRuns), "a-live1,a-park1,b-park1")
    }
  }

  // H9
  function test_the_cursor_walks_snapshot_then_history_and_run_by_id_finds_both() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage().concat([histRun("a-park1", tc.rootA, "done", "2026-09-17T00:00:00Z")])
    var expected = ["b-park1", "b-h1", "a-live1", "a-park1", "a-h1", "a-h2"]
    compare(store.filteredRuns.length, expected.length)
    for (var i = 0; i < expected.length; i++) {
      compare(store.filteredRuns[i].id, expected[i], "row " + i)
      verify(store.runById(expected[i]) === store.filteredRuns[i], "runById(" + expected[i] + ")")
    }
    compare(store.runById("a-park1").status, "stopped", "a snapshot id is the snapshot's run")
    compare(store.runById("nope"), null)
  }

  // Review Focus 1
  function test_a_selected_history_run_fetches_its_logs_from_its_root() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage()
    store.selectedRunId = "b-h1"
    store.selectAttempt("c1", "spec", 1)
    compare(argv(store.logsRunner.current), "python3|/plugin/core/backend/runs/runs-logs.py|" + tc.rootB + "|b-h1|c1|spec|1")
    compare(store.logsLoading, true)
  }

  // Noon local time on 2026-10-09: the age tests' clock; that day's local
  // midnight; the clock minus 7 days.
  readonly property real fixedNow: new Date(2026, 9, 9, 12, 0, 0).getTime()
  readonly property real fixedMidnight: new Date(2026, 9, 9, 0, 0, 0).getTime()
  readonly property real fixedWeekAgo: fixedNow - 7 * 86400000

  // `ms` as an ISO started_at.
  function iso(ms) { return new Date(ms).toISOString() }

  // rootA and rootB registered, the snapshot answered: A lists a-live1
  // (running), a-dead1, a-park1, a-done1 and a-esc1, B lists b-canc1
  // ("cancelled"); the history adds A's a-hdone, a-hcanc ("canceled") and
  // a-hpark, and B's b-hesc. Every run started before 2026-10-02; nowMs is
  // fixedNow.
  function finishedStore() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return null
    reply(store.snapshotRunner.current, allReply([
      okEntry(tc.rootA, [entry("a-live1", "started", true, tc.rootA), entry("a-dead1", "started", false, tc.rootA),
                         entry("a-park1", "stopped", false, tc.rootA), entry("a-done1", "done", false, tc.rootA),
                         entry("a-esc1", "escalated", false, tc.rootA)]),
      okEntry(tc.rootB, [entry("b-canc1", "cancelled", false, tc.rootB)])]), 0)
    store.nowMs = tc.fixedNow
    store.historyRuns = [histRun("a-hdone", tc.rootA, "done", "2026-09-20T00:00:00Z"),
                         histRun("a-hcanc", tc.rootA, "canceled", "2026-09-19T00:00:00Z"),
                         histRun("a-hpark", tc.rootA, "stopped", "2026-09-18T00:00:00Z"),
                         histRun("b-hesc", tc.rootB, "escalated", "2026-09-17T00:00:00Z")]
    return store
  }

  // H3
  function test_each_chip_lists_snapshot_and_history_runs() {
    var store = finishedStore(); if (!store) return
    compare(ids(store.filteredRuns), "a-live1,a-dead1,a-park1,a-done1,a-esc1,a-hdone,a-hcanc,a-hpark,b-canc1,b-hesc")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "a-dead1,a-esc1,b-hesc")
    store.runFilter = "live"
    compare(ids(store.filteredRuns), "a-live1")
    store.runFilter = "parked"
    compare(ids(store.filteredRuns), "a-park1,a-hpark")
    store.runFilter = "finished"
    compare(ids(store.filteredRuns), "a-done1,a-esc1,a-hdone,a-hcanc,b-canc1,b-hesc")
    compare(groupText(store), "alpha:1/0/0,beta:1/0/0")
  }

  // H3
  function test_run_filter_counts_cover_snapshot_and_history_in_the_project_filter() {
    var store = finishedStore(); if (!store) return
    var all = JSON.stringify({ attention: 3, live: 1, parked: 2, finished: 6, all: 10 })
    compare(JSON.stringify(store.runFilterCounts), all)
    store.runFilter = "live"
    store.searchQuery = "zzz"
    store.finishedState = "done"
    store.finishedAge = "today"
    compare(store.filteredRuns.length, 0)
    compare(JSON.stringify(store.runFilterCounts), all, "the chip, the search and the finished rows never narrow the counts")
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    compare(JSON.stringify(store.runFilterCounts), JSON.stringify({ attention: 1, live: 0, parked: 0, finished: 2, all: 2 }))
  }

  // H4
  function test_the_finished_state_row_narrows_under_finished_only() {
    var store = finishedStore(); if (!store) return
    store.runFilter = "finished"
    store.finishedState = "done"
    compare(ids(store.filteredRuns), "a-done1,a-hdone")
    store.finishedState = "escalated"
    compare(ids(store.filteredRuns), "a-esc1,b-hesc")
    store.finishedState = "cancelled"
    compare(ids(store.filteredRuns), "a-hcanc,b-canc1", "both spellings")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "a-live1,a-dead1,a-park1,a-done1,a-esc1,a-hdone,a-hcanc,a-hpark,b-canc1,b-hesc",
            "All: the state row narrows nothing")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "a-dead1,a-esc1,b-hesc", "Attention: nothing either")
  }

  // Review Focus 5
  function test_an_unknown_finished_state_or_age_narrows_nothing() {
    var store = finishedStore(); if (!store) return
    store.runFilter = "finished"
    store.finishedState = "bogus"
    store.finishedAge = "fortnight"
    compare(ids(store.filteredRuns), "a-done1,a-esc1,a-hdone,a-hcanc,b-canc1,b-hesc")
  }

  // rootA alone, the snapshot answered with a-live1 (running), a-dead1 and
  // a-esc1, all started 2026-10-01T00:00:00Z; nowMs is fixedNow; the
  // history: t-after (done, a minute after midnight), t-before (done, a
  // minute before), w-in (escalated, a minute inside the 7 days), w-out
  // (done, a minute outside), h-park (parked) and h-live (running), both 8
  // days old, and h-nostart (done, no started_at).
  function ageStore() {
    var store = makeWithRoots([tc.rootA]); if (!store) return null
    reply(store.snapshotRunner.current, okReply([entry("a-live1", "started", true), entry("a-dead1", "started", false),
                                                 entry("a-esc1", "escalated", false)]), 0)
    store.nowMs = tc.fixedNow
    var old = tc.fixedWeekAgo - 86400000
    store.historyRuns = [histRun("t-after", tc.rootA, "done", iso(tc.fixedMidnight + 60000)),
                         histRun("t-before", tc.rootA, "done", iso(tc.fixedMidnight - 60000)),
                         histRun("w-in", tc.rootA, "escalated", iso(tc.fixedWeekAgo + 60000)),
                         histRun("w-out", tc.rootA, "done", iso(tc.fixedWeekAgo - 60000)),
                         histRun("h-park", tc.rootA, "stopped", iso(old)),
                         histRun("h-live", tc.rootA, "started", iso(old), true),
                         histRun("h-nostart", tc.rootA, "done", "")]
    return store
  }

  // H5
  function test_the_age_row_narrows_finished_runs_under_finished_and_all() {
    var store = ageStore(); if (!store) return
    store.runFilter = "finished"
    compare(ids(store.filteredRuns), "a-esc1,t-after,t-before,w-in,w-out,h-nostart", "all time")
    store.finishedAge = "today"
    compare(ids(store.filteredRuns), "t-after", "since local midnight; no started_at is hidden")
    store.finishedAge = "week"
    compare(ids(store.filteredRuns), "t-after,t-before,w-in", "the last 7 x 24 h")
    store.runFilter = ""
    compare(ids(store.filteredRuns), "a-live1,a-dead1,t-after,t-before,w-in,h-park,h-live",
            "All: the age narrows finished runs only")
    store.finishedAge = "today"
    compare(ids(store.filteredRuns), "a-live1,a-dead1,t-after,h-park,h-live",
            "a running, dead or parked run is never hidden")
    store.runFilter = "attention"
    compare(ids(store.filteredRuns), "a-dead1,a-esc1,w-in", "Attention: the age narrows nothing")
    store.runFilter = "parked"
    compare(ids(store.filteredRuns), "h-park", "Parked: nothing either")
    store.runFilter = "live"
    compare(ids(store.filteredRuns), "a-live1,h-live")
  }

  // Review Focus 3
  function test_now_ms_0_measures_the_age_against_the_current_time() {
    var store = makeWithRoots([tc.rootA]); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    compare(store.nowMs, 0)
    store.historyRuns = [histRun("fresh", tc.rootA, "done", iso(Date.now())),
                         histRun("stale", tc.rootA, "done", iso(Date.now() - 8 * 86400000))]
    store.runFilter = "finished"
    store.finishedAge = "week"
    compare(ids(store.filteredRuns), "fresh")
  }

  // H8
  function test_the_search_matches_a_history_runs_title() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage()
    store.searchQuery = "widget"
    compare(store.filteredRuns.length, 0, "no title map: no title to match")
    var titles = {}
    titles[tc.rootA] = { "m-a-h2": "Ship the Widget" }
    store.titlesByRoot = titles
    compare(ids(store.filteredRuns), "a-h2")
    store.titlesByRoot = ({})
    compare(store.filteredRuns.length, 0)
  }

  // Review Focus 4
  function test_without_a_title_map_the_search_matches_ids_and_fallback_titles() {
    var store = historyStore(); if (!store) return
    store.historyRuns = historyPage()
    store.titlesByRoot = "garbage"
    store.searchQuery = "b-h1"
    compare(ids(store.filteredRuns), "b-h1")
    store.searchQuery = "milestone …m-a-h2"
    compare(ids(store.filteredRuns), "a-h2", "runTitle's fallback title")
  }

  // H6
  function test_toggle_finished_state() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    var steps = [["done", "done"], ["escalated", "escalated"], ["escalated", ""], ["cancelled", "cancelled"],
                 ["all", ""], ["cancelled", "cancelled"], ["bogus", ""], ["", ""], ["done", "done"], [undefined, ""]]
    for (var i = 0; i < steps.length; i++) {
      store.toggleFinishedState(steps[i][0])
      compare(store.finishedState, steps[i][1], "toggleFinishedState(" + steps[i][0] + ")")
      compare(spy.count, i + 1, "one runFilterToggled per call, changed or not")
    }
    compare(store.runFilter, "", "the chip is untouched")
    compare(store.finishedAge, "all")
  }

  // H6
  function test_toggle_finished_age() {
    var store = make(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    var steps = [["today", "today"], ["week", "week"], ["week", "all"], ["today", "today"], ["all", "all"],
                 ["week", "week"], ["bogus", "all"], ["all", "all"]]
    for (var i = 0; i < steps.length; i++) {
      store.toggleFinishedAge(steps[i][0])
      compare(store.finishedAge, steps[i][1], "toggleFinishedAge(" + steps[i][0] + ")")
      compare(spy.count, i + 1, "one runFilterToggled per call, changed or not")
    }
    compare(store.runFilter, "", "the chip is untouched")
    compare(store.finishedState, "")
  }

  // H6
  function test_the_chip_and_the_finished_rows_are_independent_and_survive_a_project_switch() {
    var store = makeWithProject(rootA); if (!store) return
    store.toggleFinishedState("escalated")
    store.toggleFinishedAge("week")
    store.toggleRunFilter("finished")
    compare(store.runFilter, "finished")
    compare(store.finishedState, "escalated", "the chip leaves the state row")
    compare(store.finishedAge, "week", "and the age row")
    store.toggleRunFilter("finished")
    compare(store.runFilter, "")
    compare(store.finishedState, "escalated")
    compare(store.finishedAge, "week")
    store.project = rootB
    compare(store.finishedState, "escalated", "a project switch keeps the state row")
    compare(store.finishedAge, "week", "and the age row")
  }

  // H7
  function test_closing_the_panel_resets_the_finished_rows_and_keeps_the_chip() {
    var store = projectsStore(true); if (!store) return
    store.historyRuns = [histRun("a-h1", tc.rootA, "done", "2026-09-20T00:00:00Z")]
    store.toggleRunFilter("finished")
    store.searchQuery = "a-"
    store.toggleFinishedState("done")
    store.toggleFinishedAge("week")
    store.toggleProjectFilter(tc.rootB)
    compare(store.projectFilter, tc.rootB)
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "runFilterToggled" })
    store.active = false
    compare(store.finishedState, "")
    compare(store.finishedAge, "all")
    compare(store.projectFilter, "")
    compare(spy.count, 0, "no runFilterToggled")
    compare(store.runFilter, "finished", "the chip stays")
    compare(store.searchQuery, "a-", "the search stays")
    verify(ids(store.listedRuns).split(",").indexOf("a-h1") >= 0, "the history is App's input: kept")
  }
}
