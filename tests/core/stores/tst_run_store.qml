// tests/core/stores/tst_run_store.qml
// The run monitor's store: the snapshot helper's exact argv, how its one JSON
// line becomes every registered root's normalized runs and an amStatus, the
// one-in-flight-plus-one-pending rule, what a registry change does and what a
// project switch leaves alone. Built directly and driven through stubbed
// Process objects.
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

  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
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
    compare(store.alertsArmed, true)
    compare(store.toasts.length, 0)
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
    compare(store.toasts.length, 0, "a failed entry raises nothing")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]), okEntry(tc.rootB, [rec("escalated")])]), 0)
    compare(Object.keys(store.projectErrors).length, 0, "a good entry clears B's error")
    compare(store.toasts.length, 0, "B's recovery replays no alert")

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
    compare(store.alertsArmed, true, "the armed state is unchanged")
    compare(store.stale, true, "stale is unchanged")

    var closed = makeWithRoots([tc.rootA]); if (!closed) return
    reply(closed.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(closed.alertsArmed, false, "a disarmed store stays disarmed")
    compare(closed.amStatus, "error")
  }

  // 6
  function test_am_missing_in_every_entry_empties_everything() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [rec("started")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(store.alertsArmed, true)
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
    compare(store.alertsArmed, false)
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
    compare(store.toasts.length, 0, "the registry change raises nothing")
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
    store.project = tc.rootA
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [treeEntry("r1", "started"), running("r2")]),
                                                  okEntry(tc.rootB, [rec("done")])]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    compare(store.control("pause", "r2"), true)
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [treeEntry("r1", "started"), running("r2"), escalated("r3")]),
                                                  okEntry(tc.rootB, [rec("done")])]), 0)
    compare(store.toasts.length, 1, "r3 escalated")
    compare(store.pending.r2, "pause", "acknowledged, not yet settled")
    store.toggleRunFilter("live")
    var watch = store.watchProc
    var runs = store.runs
    var applied = store.appliedSeq
    var attempt = store.selectedAttempt
    var toasts = store.toasts
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
      verify(store.toasts === toasts, label + ": the toasts")
      compare(store.pending.r2, "pause", label)
      compare(store.alertsArmed, true, label)
      compare(store.amStatus, "ok", label)
      compare(store.snapshotRunner.seq, seq, label + ": no snapshot")
    }
    sendLine(watch, { changed: [{ run: "r2", seq: 7 }] })
    compare(store.debounceTimer.running, true, "a watch line after the switch is still handled")
    compare(store.nudges.r2, 7)
    store.project = tc.rootB
    compare(argv(store.runSettingsRunner.current), tc.viewerCmd + "get-run-settings|" + tc.rootB,
            "the new project's run settings still load")
    compare(store.dispatchState, "idle", "and the dispatch is still reset")
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
    compare(store.alertsArmed, true)
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
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
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

  // Kept behaviour: a refresh that escalates a run raises one toast.
  function test_a_nudge_refresh_that_escalates_a_run_raises_one_toast() {
    var store = threeRoots(); if (!store) return
    nudge(store, ["b1", 5])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(store.toasts.length, 1)
    compare(store.toasts[0].id, "b1")
    compare(store.toasts[0].state, "escalated")
    nudge(store, ["b1", 6])
    fire(store.debounceTimer)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [entry("b1", "escalated", false, tc.rootB)])]), 0)
    compare(store.toasts.length, 1, "still escalated: no second toast")
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
    compare(store.control("cancel", tc.startedRun), true)
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.pending[tc.startedRun], "cancel", "acknowledged, not yet settled")
    nudge(store, [tc.startedRun, 1005])
    fire(store.debounceTimer)
    // synthetic: status-escalated.json's data under the started run's id.
    reply(store.snapshotRunner.current, capturedList([], true), 0)
    compare(store.pending[tc.startedRun], undefined, "the refresh settled it")
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
    compare(store.alertsArmed, false)
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
    compare(timers.sort().join(","), "debounceTimer,dispatchDebounceTimer,flashTimer,livenessTimer,pendingTimer,pollTimer,staleTimer,toastTimer", "the logs add no timer")
    compare(store.debounceTimer.running, false)
    compare(store.livenessTimer.running, false)
    compare(store.staleTimer.running, false)
    compare(store.pollTimer.running, false)
    compare(store.pendingTimer.running, false)
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

  // ---- run controls (S2 4.1)

  property string ctlCmd: "python3|/plugin/core/backend/runs/run-control.py|"

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

  // Project A whose first snapshot listed `entries`. Not active: no watch.
  function ctlStore(entries) {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    return store
  }

  function ctlOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  function test_control_defaults() {
    var store = make(); if (!store) return
    compare(Object.keys(store.pending).length, 0)
    compare(Object.keys(store.stillWaiting).length, 0)
    compare(store.stillWaitingText, "still waiting — the run may be between phases or dead")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    compare(store.controlRunners.length, 0)
  }

  function test_pause_and_cancel_launch_the_exact_argv() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    compare(store.control("pause", "r1"), true)
    compare(store.control("cancel", "r2"), true)
    compare(store.controlRunners.length, 2)
    compare(store.controlRunners[0].runId, "r1")
    compare(store.controlRunners[0].action, "pause")
    var pause = store.controlRunners[0].current
    compare(pause.command.length, 5)
    compare(argv(pause), tc.ctlCmd + "pause|r1|/home/u/my proj")
    compare(pause.command[4], "/home/u/my proj", "the root with a space is one argument")
    compare(pause.running, true)
    compare(pause.launchGuard, "", "no guard")
    var cancel = store.controlRunners[1].current
    compare(cancel.command.length, 5)
    compare(argv(cancel), tc.ctlCmd + "cancel|r2|/home/u/my proj")
  }

  function test_control_sets_pending_as_a_new_object() {
    var store = ctlStore([running("r1")]); if (!store) return
    var before = store.pending
    var spy = spyC.createObject(tc, { target: store, signalName: "pendingChanged" })
    compare(store.control("pause", "r1"), true)
    compare(spy.count, 1)
    compare(store.pending.r1, "pause")
    compare(before.r1, undefined, "the old object was not changed in place")
  }

  function test_an_ok_reply_keeps_pending_and_refreshes() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var snap = store.snapshotRunner.current
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, ctlOk({ run_id: "r1", command: "pause", effective: true,
      requested_at: "t1", already_requested: false, message: "pause requested" }), 0)
    compare(store.pending.r1, "pause", "pending until a snapshot settles it")
    compare(store.lastControlError, "")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")
    verify(store.snapshotRunner.current !== snap)
    compare(store.controlRunners.length, 0)
  }

  function test_an_ok_false_reply_clears_pending_and_says_why() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    var seq = store.snapshotRunner.seq
    var text = ctlFail("NotAcceptingError", "run r1 is in integrate")
    reply(store.controlRunners[0].current, text, 0)
    compare(store.pending.r1, undefined, "the buttons come back")
    compare(store.lastControlError, Runs.controlError(JSON.parse(text)))
    compare(store.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastError, "", "the snapshot banner is not the control error")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")

    store.control("cancel", "r2")
    var failed = ctlFail("AmFailed", "am: database is locked")
    reply(store.controlRunners[0].current, failed, 0)
    compare(store.lastControlError, Runs.controlError(JSON.parse(failed)))
    verify(store.lastControlError !== "", "AmFailed says something")
    compare(store.lastControlErrorRunId, "r2")
  }

  function test_garbled_control_output_names_the_exit_code() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("cancel", "r1")
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, "Traceback (most recent call last):\nboom\n", 1)
    compare(store.pending.r1, undefined)
    compare(store.lastControlError, "The run control gave no usable result (exit 1).")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.snapshotRunner.seq, seq + 1)
  }

  function test_an_unknown_run_error_survives_the_snapshot_that_drops_the_row() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("cancel", "r1")
    reply(store.controlRunners[0].current, ctlFail("UnknownRunError", "no run r1"), 0)
    compare(store.lastControlError, "The run no longer exists")
    reply(store.snapshotRunner.current, okReply([running("r2")]), 0)
    compare(store.runs.length, 1)
    compare(store.runs[0].id, "r2", "the row is dropped")
    compare(store.lastControlError, "The run no longer exists", "a snapshot never clears the control error")
    compare(store.lastControlErrorRunId, "r1")
    compare(store.lastError, "")
    snapshot(store, [running("r2")])
    compare(store.lastControlError, "The run no longer exists")
    compare(store.lastError, "")
  }

  function test_control_refusals_launch_nothing() {
    var bare = make(); if (!bare) return
    compare(bare.control("pause", "r1"), false, "a run not in the snapshot")
    compare(bare.controlRunners.length, 0)

    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false),
                          ctlEntry("r3", "started", true, "milestone", [], false)]); if (!store) return
    compare(store.control("stop", "r1"), false, "unknown action")
    compare(store.control("Pause", "r1"), false, "actions are exact")
    compare(store.control("", "r1"), false, "empty action")
    compare(store.control("pause", ""), false, "empty id")
    compare(store.control("pause", 7), false, "an id that is not a string")
    compare(store.control("pause", "nope"), false, "a run not in the snapshot")
    compare(store.control("pause", "r2"), false, "pause on a parked run is disabled")
    compare(store.control("cancel", "r3"), false, "cancel during Integrate is disabled")
    compare(store.control("pause", "r3"), false, "pause during Integrate is disabled")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.control("pause", "r1"), true)
    compare(store.control("pause", "r1"), false, "no double fire")
    compare(store.control("cancel", "r1"), false, "one request per run at a time")
    compare(store.controlRunners.length, 1)
    compare(Object.keys(store.pending).join(","), "r1")
  }

  function test_two_runs_in_flight_at_once_both_apply() {
    var store = ctlStore([running("a"), running("b")]); if (!store) return
    store.control("pause", "a")
    store.control("cancel", "b")
    compare(store.controlRunners.length, 2)
    var ra = store.controlRunners[0], rb = store.controlRunners[1]
    compare(ra.current.running, true, "cancelling b did not stop a's pause")
    compare(rb.current.running, true)
    reply(ra.current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.controlRunners.length, 1)
    compare(store.controlRunners[0].runId, "b")
    compare(store.pending.a, "pause")
    compare(store.pending.b, "cancel")
    reply(rb.current, ctlFail("NotRunningError", "not running"), 0)
    compare(store.controlRunners.length, 0)
    compare(store.pending.a, "pause")
    compare(store.pending.b, undefined)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "b")
  }

  function test_a_finished_request_leaves_control_runners() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.controlRunners.length, 0, "an applied reply")

    var other = ctlStore([running("r1")]); if (!other) return
    other.control("pause", "r1")
    var proc = other.controlRunners[0].current
    other.project = rootB
    compare(other.controlRunners.length, 1, "a launched request still completes in am")
    var seq = other.snapshotRunner.seq
    reply(proc, ctlOk({ requested_at: "t1" }), 0)
    compare(other.controlRunners.length, 0, "a reply after a switch is applied and removes its runner")
    compare(other.snapshotRunner.seq, seq + 1, "and re-snapshots")
  }

  function test_a_new_request_and_dismiss_clear_the_control_error() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlError, "am is busy; try again in a moment")
    compare(store.control("pause", "r1"), true, "the failed request no longer blocks the run")
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
    reply(store.controlRunners[0].current, ctlFail("LockTimeoutError", "busy"), 0)
    compare(store.lastControlErrorRunId, "r1")
    store.dismissControlError()
    compare(store.lastControlError, "")
    compare(store.lastControlErrorRunId, "")
  }

  property string settingsCmd: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/my proj"
  property string noVerifySentence: "Resume needs verify commands: none are stored for this project, and running without verification was not chosen."

  // viewer-state.py get-run-settings: one bare object, not an envelope.
  function settingsReply(verify, allow) {
    return JSON.stringify({ verify: verify, allowNoVerification: allow, notifyOnEscalation: false }) + "\n"
  }

  function test_milestone_resume_reads_the_settings_then_passes_the_verify_set() {
    var store = ctlStore([dead("r1")]); if (!store) return
    compare(store.control("resume", "r1"), true)
    compare(store.controlRunners.length, 1)
    var runner = store.controlRunners[0]
    compare(argv(runner.current), tc.settingsCmd)
    compare(runner.current.command.length, 4)
    compare(store.pending.r1, "resume")
    reply(runner.current, settingsReply(["a", "-b c"], true), 0)
    compare(store.controlRunners.length, 1, "the same request goes on to run-control")
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--verify|a|--verify|-b c")
    compare(proc.command.length, 9, "each verify command is one argument")
    compare(proc.command[8], "-b c")
    compare(proc.command.indexOf("--allow-no-verification"), -1, "a stored verify set wins over the opt-out")
    compare(store.pending.r1, "resume")
  }

  function test_milestone_resume_with_the_opt_out_passes_allow_no_verification() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    reply(store.controlRunners[0].current, settingsReply([], true), 0)
    var proc = store.controlRunners[0].current
    compare(argv(proc), tc.ctlCmd + "resume|r1|/home/u/my proj|--allow-no-verification")
    compare(proc.command.length, 6)
  }

  function test_milestone_resume_with_nothing_stored_launches_nothing() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, settingsReply([], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.lastControlError, tc.noVerifySentence)
    compare(store.lastControlErrorRunId, "r1")
    compare(store.snapshotRunner.seq, seq, "nothing was asked of am, so no snapshot")
  }

  function test_garbled_run_settings_end_the_resume() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    reply(runner.current, "oops\n", 2)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.controlRunners.length, 0)
    compare(Object.keys(store.pending).length, 0)
    compare(store.lastControlError, "The run settings gave no usable result (exit 2).")
    compare(store.lastControlErrorRunId, "r1")
  }

  function test_a_card_run_resume_skips_the_settings() {
    var store = ctlStore([ctlEntry("r1", "started", false, "task"),
                          ctlEntry("r2", "started", false, "orchestrator")]); if (!store) return
    compare(store.control("resume", "r1"), true)
    compare(store.controlRunners.length, 1)
    var runner = store.controlRunners[0]
    compare(runner.seq, 1, "one launch only")
    compare(argv(runner.current), tc.ctlCmd + "resume|r1|/home/u/my proj")
    compare(runner.current.command.length, 5)
    compare(store.control("resume", "r2"), true)
    compare(argv(store.controlRunners[1].current), tc.settingsCmd, "any workflow but task follows the milestone rule")
  }

  // Review Focus 3.
  function test_a_verify_set_with_a_non_string_is_not_used() {
    var store = ctlStore([dead("r1"), dead("r2")]); if (!store) return
    store.control("resume", "r1")
    var runner = store.controlRunners[0]
    reply(runner.current, settingsReply(["a", 5], false), 0)
    compare(runner.seq, 1, "run-control was never launched")
    compare(store.lastControlError, tc.noVerifySentence)
    store.control("resume", "r2")
    reply(store.controlRunners[0].current, settingsReply(["a", 5], true), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|r2|/home/u/my proj|--allow-no-verification")
  }

  // One am control request row.
  function amRequest(command, requestedAt, handledAt) {
    return { command: command, requested_at: requestedAt, handled_at: handledAt }
  }

  // A pause of `id` that am acknowledged; requestedAt "" leaves it out of the reply.
  function pauseAcked(store, id, requestedAt) {
    compare(store.control("pause", id), true)
    var data = { run_id: id, command: "pause" }
    if (requestedAt !== "") data.requested_at = requestedAt
    reply(store.controlRunners[store.controlRunners.length - 1].current, ctlOk(data), 0)
  }

  function test_a_pause_settles_when_its_request_is_handled() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", null)])])
    compare(store.pending.r1, "pause", "not handled yet")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [amRequest("pause", "t0", "t0h"), amRequest("pause", "t1", "")])])
    compare(store.pending.r1, "pause", "an older handled pause is another request")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [amRequest("pause", "t0", "t0h"), amRequest("pause", "t1", "t1h")])])
    compare(store.pending.r1, undefined, "handled")
  }

  function test_without_requested_at_the_last_request_of_that_command_decides() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
      [amRequest("pause", "t0", "t0h"), amRequest("cancel", "t1", "t1h"), amRequest("pause", "t2", null)])])
    compare(store.pending.r1, "pause", "the last pause is not handled; a handled cancel is another request")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
      [amRequest("pause", "t0", "t0h"), amRequest("pause", "t2", "t2h")])])
    compare(store.pending.r1, undefined)
  }

  // Review Focus 2.
  function test_a_resume_settles_when_the_run_state_changes() {
    var store = ctlStore([dead("r1")]); if (!store) return
    store.control("resume", "r1")
    reply(store.controlRunners[0].current, settingsReply(["make test"], false), 0)
    reply(store.controlRunners[0].current, ctlOk({ action: "resume", run_id: "r1", detached: true }), 0)
    compare(store.pending.r1, "resume", "a detached resume is acknowledged, not failed")
    compare(store.lastControlError, "")
    snapshot(store, [ctlEntry("r1", "started", false, "milestone", [amRequest("resume", "t1", "t1h")])])
    compare(store.pending.r1, "resume", "still dead; resume never reads a request row")
    snapshot(store, [running("r1")])
    compare(store.pending.r1, undefined, "dead -> running")
  }

  function test_a_request_settles_when_its_run_vanishes() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    snapshot(store, [running("r2")])
    compare(store.pending.r1, undefined)
  }

  // D5.
  function test_a_snapshot_never_settles_a_request_in_flight() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var runner = store.controlRunners[0]
    snapshot(store, [ctlEntry("r1", "stopped", false)])
    compare(store.pending.r1, "pause", "the reply has not come back yet")
    snapshot(store, [])
    compare(store.pending.r1, "pause", "not even when the run vanished")
    reply(runner.current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.pending.r1, "pause")
    snapshot(store, [ctlEntry("r1", "stopped", false)])
    compare(store.pending.r1, undefined, "settled once acknowledged")
  }

  function test_a_failed_snapshot_settles_nothing() {
    var store = ctlStore([running("r1")]); if (!store) return
    pauseAcked(store, "r1", "t1")
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "AmFailed", message: "boom" } }) + "\n", 0)
    compare(store.pending.r1, "pause")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    compare(store.pending.r1, "pause")
  }

  // Review Focus 1: A -> B -> A before the old reply lands.
  function test_a_reply_after_returning_to_the_project_is_applied() {
    var store = ctlStore([running("r1")]); if (!store) return
    store.control("pause", "r1")
    var proc = store.controlRunners[0].current
    store.project = rootB
    store.project = rootA
    compare(store.pending.r1, "pause", "the request is still pending")
    compare(store.control("pause", "r1"), false, "so the run cannot be asked again")
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotAcceptingError", "x"), 0)
    compare(store.pending.r1, undefined, "its reply is this project's again and settles it")
    compare(store.lastControlError, "Integrate is running; it cannot be paused or cancelled")
    compare(store.snapshotRunner.seq, seq + 1, "and re-snapshots")
    compare(store.controlRunners.length, 0)
  }

  function test_a_request_is_still_waiting_after_30_seconds() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.control("pause", "r1")
    store.checkWaiting(Date.now() + 29000)
    compare(store.stillWaiting.r1, undefined, "29 s is not yet")
    store.checkWaiting(Date.now() + 30000)
    compare(store.stillWaiting.r1, true)
    compare(store.stillWaiting.r2, undefined, "only pending runs")
    compare(store.stillWaitingText, "still waiting — the run may be between phases or dead")
    reply(store.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    compare(store.stillWaiting.r1, true, "acknowledged but not settled: still waiting")
    snapshot(store, [ctlEntry("r1", "started", true, "milestone", [amRequest("pause", "t1", "t1h")]), running("r2")])
    compare(store.stillWaiting.r1, undefined, "settling removes it")
    compare(Object.keys(store.stillWaiting).length, 0)
  }

  // Review Focus 5 and D6.
  function test_the_pending_timer_runs_only_while_active_with_something_pending() {
    var store = activeStore(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(store.pendingTimer.running, false, "nothing pending")
    compare(store.pendingTimer.interval, 1000)
    compare(store.pendingTimer.repeat, true)
    store.control("pause", "r1")
    compare(store.pendingTimer.running, true)
    store.pendingTimer.triggered()
    compare(store.stillWaiting.r1, undefined, "a fresh request is not waiting yet")
    store.active = false
    compare(store.pendingTimer.running, false, "no timer while the panel is closed")
    compare(store.pending.r1, "pause", "closing the panel keeps pending")
    compare(store.controlRunners.length, 1, "and the request in flight")
    store.active = true
    compare(store.pendingTimer.running, true, "reopening starts it again")
    reply(store.controlRunners[0].current, ctlFail("NotRunningError", "x"), 0)
    compare(store.pendingTimer.running, false, "nothing pending any more")

    var idle = ctlStore([running("r1")]); if (!idle) return
    idle.control("pause", "r1")
    compare(idle.pendingTimer.running, false, "an inactive store runs no timer")
  }

  // ---- cancel confirmation and the footer flash (S2 4.3)

  property string integrateReason: "Integrate is running; it cannot be paused or cancelled"

  // A running run whose lease is not accepting requests: am is in Integrate.
  function integrate(id) { return ctlEntry(id, "started", true, "milestone", [], false) }

  // 1 (and Review Focus 4)
  function test_refusal_of_says_why_a_control_would_not_start() {
    var bare = make(); if (!bare) return
    compare(bare.refusalOf("pause", "r1"), "This run is no longer in the snapshot", "not in the snapshot")
    var store = ctlStore([running("r1"), ctlEntry("r2", "stopped", false), integrate("r3"),
                          ctlEntry("r4", "done", false), running("r5"), running("constructor")]); if (!store) return
    compare(store.refusalOf("pause", "r1"), "")
    compare(store.refusalOf("cancel", "r1"), "")
    compare(store.refusalOf("resume", "r2"), "")
    compare(store.refusalOf("cancel", "r2"), "")
    compare(store.refusalOf("pause", "nope"), "This run is no longer in the snapshot")
    compare(store.refusalOf("pause", ""), "This run is no longer in the snapshot")
    compare(store.refusalOf("pause", "r3"), tc.integrateReason)
    compare(store.refusalOf("cancel", "r3"), tc.integrateReason)
    compare(store.refusalOf("cancel", "r4"), "The run has finished")
    compare(store.refusalOf("resume", "r1"), "The run is still running")
    compare(store.refusalOf("bogus", "r1"), "Unknown control")
    compare(store.refusalOf("pause", "constructor"), "", "an id like constructor is not pending")
    compare(store.refusalOf("resume", "constructor"), "The run is still running")
    compare(store.control("pause", "r5"), true)
    compare(store.refusalOf("pause", "r5"), "A request for this run is pending")
    compare(store.refusalOf("resume", "r5"), "A request for this run is pending", "pending wins over the state's reason")
    compare(store.controlRunners.length, 1, "refusalOf starts nothing")
  }

  // 2
  function test_a_flash_clears_itself_and_a_new_one_restarts_the_clock() {
    var store = make(); if (!store) return
    compare(store.flashText, "")
    compare(store.flashTimer.interval, 3000)
    compare(store.flashTimer.repeat, false)
    compare(store.flashTimer.running, false)
    store.flashTimer.interval = 500
    store.flash("first")
    compare(store.flashText, "first")
    compare(store.flashTimer.running, true)
    wait(300)
    store.flash("second")
    compare(store.flashText, "second", "the new text replaces the old")
    wait(300)
    compare(store.flashText, "second", "the clock restarted with the second flash")
    tryCompare(store, "flashText", "", 2000)
    compare(store.flashTimer.running, false)
    store.flash("third")
    store.flash("")
    compare(store.flashText, "")
    compare(store.flashTimer.running, false, "flash(\"\") stops the clock")
  }

  // 3
  function test_open_cancel_opens_only_for_a_cancellable_run() {
    var store = ctlStore([running("r1"), integrate("r3")]); if (!store) return
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    store.cancelText = "left over"
    store.cancelError = "old"
    compare(store.openCancel("r1"), true)
    compare(store.cancelOpen, true)
    compare(store.cancelRunId, "r1")
    compare(store.cancelText, "", "the dialog opens empty")
    compare(store.cancelError, "")
    compare(store.flashText, "")
    store.closeCancel()
    compare(store.cancelOpen, false)
    compare(store.openCancel("r3"), false)
    compare(store.cancelOpen, false, "an Integrate run gets no dialog")
    compare(store.flashText, tc.integrateReason)
    compare(store.controlRunners.length, 0)
  }

  // 4 (and Review Focus 1)
  function test_confirm_cancel_needs_the_word_then_starts_the_cancel_and_closes() {
    var store = ctlStore([running("r1")]); if (!store) return
    compare(store.confirmCancel(), false, "nothing is open")
    store.openCancel("r1")
    store.cancelText = "cancle"
    compare(store.confirmCancel(), false)
    compare(store.controlRunners.length, 0)
    compare(store.cancelOpen, true)
    compare(store.cancelError, "", "a wrong word is not an error")
    store.cancelText = " Cancel "
    compare(store.confirmCancel(), true)
    compare(store.pending.r1, "cancel")
    compare(store.controlRunners.length, 1)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|r1|/home/u/my proj")
    compare(store.cancelOpen, false)
    compare(store.cancelRunId, "")
    compare(store.cancelText, "")
    compare(store.cancelError, "")
    compare(store.confirmCancel(), false, "a second confirm finds the dialog closed")
    compare(store.controlRunners.length, 1)
  }

  // 5 (D6, Review Focus 2)
  function test_a_run_that_changed_under_the_open_dialog_refuses_the_confirm() {
    var store = ctlStore([running("r1"), running("r2")]); if (!store) return
    store.openCancel("r2")
    store.cancelText = "cancel"
    store.control("pause", "r2")
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "A request for this run is pending")
    compare(store.cancelOpen, true)
    compare(store.controlRunners.length, 1, "only the pause")
    store.closeCancel()

    store.openCancel("r1")
    store.cancelText = "cancel"
    snapshot(store, [ctlEntry("r1", "done", false)])
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "The run has finished")
    compare(store.cancelOpen, true, "the dialog stays for the user to read why")
    compare(store.cancelRunId, "r1")
    compare(store.pending.r1, undefined)
    snapshot(store, [])
    compare(store.confirmCancel(), false)
    compare(store.cancelError, "This run is no longer in the snapshot")
    compare(store.cancelOpen, true)
    compare(store.controlRunners.length, 1, "no cancel was ever launched")
  }

  // ---- alerts: the toasts (S2 4.4)

  function escalated(id) { return entry(id, "escalated", false) }
  function toastIds(store) { return store.toasts.map(function(t) { return t.id }).join(",") }

  // An active store on project A whose first snapshot listed `entries`: that
  // snapshot only armed the alerts.
  function armedStore(entries) {
    var store = activeStore(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply(entries), 0)
    compare(store.alertsArmed, true, "the first good snapshot while open arms the alerts")
    compare(store.toasts.length, 0, "and raises nothing")
    return store
  }

  // 1
  function test_no_toast_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    compare(store.alertsArmed, false)
    compare(store.toasts.length, 0)
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false, "a closed panel never arms")
  }

  // 2
  function test_a_run_that_turns_escalated_raises_one_toast() {
    var store = activeStore(rootA); if (!store) return
    compare(store.toastMs, 8000)
    reply(store.snapshotRunner.current, okReply([escalated("a"), running("b")]), 0)
    compare(store.toasts.length, 0, "the first snapshot after opening never replays history")
    compare(store.alertsArmed, true)
    var before = Date.now()
    snapshot(store, [escalated("a"), escalated("b")])
    compare(store.toasts.length, 1)
    var t = store.toasts[0]
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
    compare(store.toasts.length, 1)
    var key = store.toasts[0].key
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    compare(store.toasts[0].key, key, "the same toast, not a new one")
  }

  // 4 (Review focus: reopening never replays history)
  function test_closing_empties_the_toasts_and_reopening_raises_nothing_at_first() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), running("b")])
    compare(store.toasts.length, 1)
    store.active = false
    compare(store.toasts.length, 0, "a toast never outlives the panel opening")
    compare(store.alertsArmed, false)
    store.active = true
    compare(store.alertsArmed, false)
    reply(store.snapshotRunner.current, okReply([escalated("a"), dead("b")]), 0)
    compare(store.toasts.length, 0, "b died while the panel was closed: not replayed")
    compare(store.alertsArmed, true)
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
    compare(store.toasts.length, 0)
    compare(store.alertsArmed, false)
  }

  // 5
  function test_am_missing_disarms_and_a_failed_snapshot_does_not() {
    var store = armedStore([running("a")]); if (!store) return
    store.refresh()
    reply(store.snapshotRunner.current, allReply([failEntry(tc.rootA, "AmMissing", "am is not installed")]), 0)
    compare(store.runs.length, 0)
    compare(store.alertsArmed, false)
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 0, "the first good snapshot after am came back raises nothing")
    compare(store.alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "b", "the one after that compares normally")

    var other = armedStore([running("x")]); if (!other) return
    other.refresh()
    reply(other.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "HelperError", message: "boom" } }) + "\n", 1)
    compare(other.alertsArmed, true, "a failed snapshot keeps the baseline")
    other.refresh()
    reply(other.snapshotRunner.current, "garbage\n", 1)
    compare(other.alertsArmed, true)
    snapshot(other, [escalated("x")])
    compare(toastIds(other), "x")
  }

  // 6
  function test_five_alerts_in_one_snapshot_leave_the_last_three_toasts() {
    var store = armedStore([]); if (!store) return
    snapshot(store, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(toastIds(store), "r3,r4,r5")
    verify(store.toasts[0].key < store.toasts[1].key && store.toasts[1].key < store.toasts[2].key, "keys only grow")
    compare(store.toasts[0].state, "dead")
    compare(store.toasts[0].reason, "process died")
  }

  // 7
  function test_a_run_that_alerts_again_replaces_its_own_toast() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    var oldKey = store.toasts[0].key
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a", "a's old toast went and its new one is the newest")
    compare(store.toasts[1].state, "dead")
    compare(store.toasts[1].reason, "process died")
    verify(store.toasts[1].key > oldKey, "a new key")
  }

  // 8
  function test_toasts_expire_and_the_timer_runs_only_while_open_with_toasts() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    var timer = store.toastTimer
    compare(timer.objectName, "toastTimer")
    compare(timer.interval, 250)
    compare(timer.repeat, true)
    compare(timer.running, false, "no toast: no timer")
    snapshot(store, [escalated("a"), running("b")])
    compare(timer.running, true)
    var aExpires = store.toasts[0].expiresMs
    store.toastMs = 60000
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b")
    store.expireToasts(aExpires - 1)
    compare(toastIds(store), "a,b", "not yet")
    store.expireToasts(aExpires)
    compare(toastIds(store), "b", "expiresMs <= now goes")
    store.dismissAllToasts()
    compare(timer.running, false, "nothing left: no timer")
    store.toastMs = 50
    snapshot(store, [escalated("a"), dead("b")])
    compare(store.toasts.length, 1)
    tryVerify(function() { return store.toasts.length === 0 }, 2000, "the timer dropped the expired toast")
    compare(timer.running, false)
  }

  // 9 (and Review Focus 2)
  function test_dismiss_removes_one_toast_by_key_and_dismiss_all_empties() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    snapshot(store, [escalated("a"), escalated("b")])
    var keyA = store.toasts[0].key
    store.dismissToast(-12345)
    compare(toastIds(store), "a,b", "an unknown key changes nothing")
    store.dismissToast(keyA)
    compare(toastIds(store), "b")
    snapshot(store, [dead("a"), escalated("b")])
    compare(toastIds(store), "b,a")
    store.dismissToast(keyA)
    compare(toastIds(store), "b,a", "a's stale key leaves its newer toast")
    store.dismissAllToasts()
    compare(store.toasts.length, 0)
  }

  // 10 (the toast half; Task 2 pins the setting half)
  function test_a_project_switch_keeps_the_toasts_and_the_alerts_armed() {
    var store = armedStore([running("a")]); if (!store) return
    snapshot(store, [escalated("a")])
    compare(store.toasts.length, 1)
    store.project = rootB
    compare(store.toasts.length, 1)
    compare(store.alertsArmed, true)
    snapshot(store, [escalated("a"), escalated("b")])
    compare(toastIds(store), "a,b", "the next snapshot compares as before")
  }

  // ---- alerts across projects (3.4)

  // The armed roots of `store`, sorted, comma-joined.
  function armedKeys(store) { return Object.keys(store.armedRoots).sort().join(",") }
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
    compare(store.alertsArmed, true)
    compare(store.toasts.length, 0, "and raises nothing")
    return store
  }

  // 1
  function test_an_escalation_in_another_project_raises_one_toast_with_its_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    compare(store.project, "")
    store.notifyOnEscalation = true
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "b1")
    compare(store.toasts[0].project, "beta")
    compare(store.toasts[0].title, "m-b1")
    compare(store.toasts[0].state, "escalated")
    compare(store.notifyRunners.length, 1, "one notification")
    compare(argv(store.notifyRunners[0].current), tc.notifyCmd + "m-b1|escalated", "its text does not change")
  }

  // 2
  function test_a_project_that_first_fails_or_joins_later_only_arms_on_its_first_good_entry() {
    var store = activeRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]),
                                                  failEntry(tc.rootB, "AmTimeout", "am did not answer within 60 s.")]), 0)
    compare(armedKeys(store), tc.rootA, "only A answered")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2")])])
    compare(store.toasts.length, 0, "B's first good entry only arms")
    compare(armedKeys(store), bothRoots())
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), dead("b2"), escalated("b3")])])
    compare(toastIds(store), "b3", "the entry after that compares normally")
    compare(store.toasts[0].project, "beta")
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
    compare(store.toasts.length, 0, "a failed entry raises nothing")
    compare(ids(store.runsByProject[tc.rootB]), "b1,b2", "B keeps its runs")
    compare(armedKeys(store), bothRoots(), "and stays armed")
    answer(store, [okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [escalated("b1"), escalated("b2")])])
    compare(toastIds(store), "b1", "the recovery compares against the kept runs: b2 is not replayed")
    compare(store.toasts[0].project, "beta")
  }

  // 4
  function test_an_am_missing_spell_disarms_every_project() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmMissing", "am is not installed."), failEntry(tc.rootB, "AmMissing", "am is not installed.")])
    compare(armedKeys(store), "")
    compare(store.alertsArmed, false)
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(store.toasts.length, 0, "the next good reply only arms")
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
    store.notifyOnEscalation = true
    // B's entry first: the registry's order decides, not the reply's.
    answer(store, [okEntry(tc.rootB, [escalated("x")]), okEntry(tc.rootA, [escalated("x")])])
    compare(toastIds(store), "x")
    compare(store.toasts[0].project, "alpha")
    compare(store.notifyRunners.length, 1, "one notification")
    store.projectRoots = registry([tc.rootB, tc.rootA])
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])]), 0)
    compare(store.runs[0].project.root, tc.rootB, "B owns x now")
    compare(store.toasts.length, 1, "a new owner replays nothing")
    compare(store.notifyRunners.length, 1)
  }

  // 5: the owner decides, even when only the other root answers
  function test_a_run_listed_under_two_roots_alerts_only_from_its_owners_entry() {
    var store = armedTwo([running("x")], [running("x")]); if (!store) return
    answer(store, [failEntry(tc.rootA, "AmTimeout", "am did not answer within 60 s."), okEntry(tc.rootB, [escalated("x")])])
    compare(store.runs[0].project.root, tc.rootA, "A still owns x")
    compare(store.toasts.length, 0, "B's entry never alerts a run A owns")
    answer(store, [okEntry(tc.rootA, [escalated("x")]), okEntry(tc.rootB, [escalated("x")])])
    compare(toastIds(store), "x", "A's own entry does")
    compare(store.toasts[0].project, "alpha")
  }

  // Review Focus 1, 2 and 3
  function test_a_partial_or_failed_reply_leaves_the_other_roots_arming_alone() {
    // synthetic: a run without an id under B.
    var store = armedTwo([running("a1")], [running("b1"), entry("", "started", true)]); if (!store) return
    var armed = store.armedRoots
    store.refresh()
    reply(store.snapshotRunner.current, JSON.stringify({ ok: false, error: { type: "Usage", message: "usage" } }) + "\n", 2)
    verify(store.armedRoots === armed, "a whole-call failure leaves the arming alone")
    store.refresh()
    reply(store.snapshotRunner.current, "garbage\n", 1)
    verify(store.armedRoots === armed, "so does garbage")
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootB, [escalated("b1"), entry("", "escalated", false)])]), 0)
    compare(toastIds(store), "b1", "a run without an id never alerts")
    compare(store.toasts[0].project, "beta")
    compare(armedKeys(store), bothRoots(), "A, with no entry, stays armed")
    compare(ids(store.runsByProject[tc.rootA]), "a1")
  }

  // 7
  function test_a_project_switch_keeps_the_toasts_and_every_projects_arming() {
    var store = armedTwo([running("a1")], [running("b1")]); if (!store) return
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [running("b1")])])
    compare(toastIds(store), "a1")
    compare(store.toasts[0].project, "alpha")
    var toasts = store.toasts
    var armed = store.armedRoots
    var targets = [tc.rootA, ""]
    for (var i = 0; i < targets.length; i++) {
      var label = "project " + JSON.stringify(targets[i])
      store.project = targets[i]
      verify(store.toasts === toasts, label + ": the toasts")
      verify(store.armedRoots === armed, label + ": the arming")
    }
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(toastIds(store), "a1,b1", "the next escalation still alerts")
    compare(store.toasts[1].project, "beta")
  }

  // the closed panel (spec §2)
  function test_a_reply_while_the_panel_is_closed_raises_nothing_and_arms_nothing() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [running("b1")])]), 0)
    compare(armedKeys(store), "", "a closed panel never arms")
    answer(store, [okEntry(tc.rootA, [escalated("a1")]), okEntry(tc.rootB, [escalated("b1")])])
    compare(store.toasts.length, 0)
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
    compare(store.toasts.length, 0, "its next good entry only arms")
    compare(armedKeys(store), bothRoots())
    var armed = store.armedRoots
    store.projectRoots = [{ root: tc.rootA, name: "renamed" }, rootEntry(tc.rootB)]
    verify(store.armedRoots === armed, "no root went: the map is not replaced")
    store.projectRoots = []
    compare(armedKeys(store), "", "an empty registry arms nothing")
  }
  // ---- alerts: the setting and the desktop notifications (S2 4.4)

  property string notifyCmd: "python3|/plugin/core/backend/runs/notify.py|"
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  function runSettings(notify) {
    return JSON.stringify({ verify: [], allowNoVerification: false, notifyOnEscalation: notify }) + "\n"
  }

  // 8 and Review Focus 5
  function test_the_global_switch_loads_on_each_opening_with_no_project() {
    var idle = make(); if (!idle) return
    verify(!idle.settingsLoadRunner.current, "a closed panel loads nothing")
    idle.project = tc.rootA
    verify(!idle.settingsLoadRunner.current, "a project switch launches no global load")

    var store = make(); if (!store) return
    store.active = true
    var load = store.settingsLoadRunner.current
    verify(load, "opening the panel loads the switch, with no project and no registry")
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    compare(load.command.length, 3)
    compare(load.launchGuard, "")
    reply(load, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(store.notifyOnEscalation, true)
    compare(store.notifySaved, true)
    store.project = tc.rootB
    compare(store.notifyOnEscalation, true, "a project switch leaves the switch alone")
    compare(store.notifySaved, true)
    compare(store.notifyTouched, false)
    var seq = store.settingsLoadRunner.seq
    store.project = ""
    compare(store.settingsLoadRunner.seq, seq, "and launches no global load")
    store.active = false
    store.active = true
    compare(store.settingsLoadRunner.seq, seq + 1, "each opening loads once")
    reply(store.settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(store.notifyOnEscalation, false, "an unreadable reply leaves it off")
    compare(store.notifySaved, false)
    store.active = false
    store.active = true
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: "yes" }) + "\n", 0)
    compare(store.notifyOnEscalation, false, "only a real true turns it on")
    store.active = false
    store.active = true
    reply(store.settingsLoadRunner.current, "{}\n", 0)
    compare(store.notifyOnEscalation, false)
    store.active = false
    store.active = true
    var late = store.settingsLoadRunner.current
    store.active = false
    reply(late, JSON.stringify({ notifyOnEscalation: true }) + "\n", 0)
    compare(store.notifyOnEscalation, true, "a reply after the panel closed still lands")
    store.active = true
    var older = store.settingsLoadRunner.current
    store.active = false
    store.active = true
    reply(older, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, true, "an earlier opening's reply is dropped")
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, false, "the newest opening's reply lands")
  }

  // 12
  function test_run_settings_load_per_project_and_never_set_the_switch() {
    var store = makeWithProject(rootA); if (!store) return
    var loadA = store.runSettingsRunner.current
    verify(loadA, "selecting a project loads its run settings")
    compare(argv(loadA), tc.viewerCmd + "get-run-settings|/home/u/my proj")
    compare(loadA.command.length, 4)
    compare(loadA.launchGuard, "/home/u/my proj")
    verify(!store.settingsLoadRunner.current, "and no global load")
    reply(loadA, runSettings(true), 0)
    compare(store.runSettings.notifyOnEscalation, true, "the object is kept as it was read")
    compare(store.notifyOnEscalation, false, "a stored per-project value is never the switch")
    compare(store.notifySaved, false)
    store.project = rootB
    compare(Object.keys(store.runSettings).length, 0, "a project switch forgets A's settings")
    var loadB = store.runSettingsRunner.current
    verify(loadB !== loadA, "a new load")
    compare(argv(loadB), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(loadB.launchGuard, "/home/u/b", "the launch is guarded by the NEW project")
    var seq = store.runSettingsRunner.seq
    store.project = ""
    compare(store.runSettingsRunner.seq, seq, "no project: nothing is loaded")
    compare(store.runSettingsRunner.guard, "")

    var other = makeWithProject(rootA); if (!other) return
    var lateA = other.runSettingsRunner.current
    other.project = rootB
    reply(lateA, dispatchSettings(), 0)
    compare(Object.keys(other.runSettings).length, 0, "a late reply for A is dropped")
    compare(other.notifyOnEscalation, false)
  }

  // 12
  function test_with_the_setting_on_each_alert_launches_its_own_notification() {
    var store = armedStore([running("a"), running("b")]); if (!store) return
    compare(store.notifyRunners.length, 0)
    store.notifyOnEscalation = true
    snapshot(store, [escalated("a"), dead("b")])
    compare(store.notifyRunners.length, 2, "one runner per alert")
    var first = store.notifyRunners[0].current, second = store.notifyRunners[1].current
    compare(argv(first), tc.notifyCmd + "m-a|escalated")
    compare(argv(second), tc.notifyCmd + "m-b|process died")
    compare(first.running, true, "the second launch did not stop the first")
    compare(second.running, true)
    compare(first.launchGuard, "")
    reply(first, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(store.notifyRunners.length, 1)
    reply(second, "garbage\n", 1)
    compare(store.notifyRunners.length, 0, "a failed notification goes too")
    compare(toastIds(store), "a,b", "the replies change nothing else")
    compare(store.flashText, "")

    snapshot(store, [escalated("a"), dead("b"), escalated("c")])
    compare(store.notifyRunners.length, 1)
    var proc = store.notifyRunners[0].current
    store.project = rootB
    compare(proc.running, true, "a project switch does not stop a launched notification")
    reply(proc, JSON.stringify({ ok: true, sent: true }) + "\n", 0)
    compare(store.notifyRunners.length, 0)

    var off = armedStore([running("a")]); if (!off) return
    snapshot(off, [escalated("a")])
    compare(off.toasts.length, 1)
    compare(off.notifyRunners.length, 0, "setting off: toasts only")

    var five = armedStore([]); if (!five) return
    five.notifyOnEscalation = true
    snapshot(five, [escalated("r1"), escalated("r2"), dead("r3"), escalated("r4"), dead("r5")])
    compare(five.toasts.length, 3)
    compare(five.notifyRunners.length, 5, "every alert notifies, even those whose toast was capped away")
  }

  // 1 (the notification half)
  function test_no_notification_while_the_panel_is_closed() {
    var store = makeWithProject(rootA); if (!store) return
    store.notifyOnEscalation = true
    reply(store.snapshotRunner.current, okReply([running("a")]), 0)
    snapshot(store, [escalated("a")])
    compare(store.notifyRunners.length, 0)
    compare(store.toasts.length, 0)
  }

  // 13
  function test_the_switch_saves_globally_and_a_failed_save_puts_it_back() {
    var store = make(); if (!store) return
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
    compare(store.notifyTouched, false)
    compare(store.notifyRunners.length, 0)
    compare(store.setNotifyOnEscalation(true), true, "no project and no registry: it still works")
    compare(store.notifyOnEscalation, true, "the switch flips at once")
    compare(store.notifyTouched, true)
    var save = store.settingsSaveRunner.current
    verify(save, "a save was launched")
    compare(save.command.length, 4)
    compare(argv(save), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":true}')
    compare(save.launchGuard, "")
    verify(!store.settingsLoadRunner.current, "a closed panel loads nothing")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true)
    compare(store.flashText, "")
    compare(store.setNotifyOnEscalation(false), true)
    compare(store.notifyOnEscalation, false)
    compare(argv(store.settingsSaveRunner.current), tc.viewerCmd + 'set-global-settings|{"notifyOnEscalation":false}')
    reply(store.settingsSaveRunner.current, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, true, "back to the value last saved")
    compare(store.notifySaved, true)
    compare(store.flashText, "Notify on escalation could not be saved")
    store.flash("")
    store.setNotifyOnEscalation(false)
    reply(store.settingsSaveRunner.current, "garbage\n", 1)
    compare(store.notifyOnEscalation, true, "an unreadable reply is a failure too")
    compare(store.flashText, "Notify on escalation could not be saved")
  }

  // 10
  function test_a_save_reply_survives_a_project_switch() {
    var store = makeWithProject(rootA); if (!store) return
    store.setNotifyOnEscalation(true)
    var save = store.settingsSaveRunner.current
    store.project = rootB
    compare(store.notifyOnEscalation, true, "the switch is viewer-wide")
    compare(store.notifyTouched, true)
    reply(save, JSON.stringify({ ok: false, error: "x" }) + "\n", 1)
    compare(store.notifyOnEscalation, false, "rolled back to the value last saved")
    compare(store.notifySaved, false)
    compare(store.flashText, "Notify on escalation could not be saved")
    store.flash("")
    store.setNotifyOnEscalation(true)
    var second = store.settingsSaveRunner.current
    store.project = ""
    reply(second, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true, "an ok reply after a switch is applied")
    compare(store.notifyOnEscalation, true)
  }

  // 11
  function test_a_save_in_flight_survives_a_reopening() {
    var store = make(); if (!store) return
    store.active = true
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    store.setNotifyOnEscalation(true)
    var save = store.settingsSaveRunner.current
    store.active = false
    store.active = true
    compare(store.notifyTouched, true, "a save is in flight: the touch stays")
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, true, "the new load cannot undo the user's choice")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.notifySaved, true, "the save reply settles notifySaved")
    store.active = false
    store.active = true
    compare(store.notifyTouched, false, "no save in flight: the next opening reads again")
    reply(store.settingsLoadRunner.current, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, false)
    compare(store.notifySaved, false)
  }

  // 14
  function test_a_load_reply_after_the_user_toggled_is_ignored() {
    var store = makeWithProject(rootA); if (!store) return
    store.active = true
    var load = store.settingsLoadRunner.current
    compare(argv(load), tc.viewerCmd + "get-global-settings")
    store.setNotifyOnEscalation(true)
    reply(load, JSON.stringify({ notifyOnEscalation: false }) + "\n", 0)
    compare(store.notifyOnEscalation, true)
    compare(store.notifyTouched, true)
  }

  // ---- dispatch (S3 3.1)

  property string previewCmd: "python3|/plugin/core/backend/runs/dispatch-preview.py|"
  property string startCmd: "python3|/plugin/core/backend/runs/start-run.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // 35
  function test_run_settings_kept_even_after_notify_touched() {
    var store = makeWithProject(rootA); if (!store) return
    compare(Object.keys(store.runSettings).length, 0, "{} until the reply")
    var load = store.runSettingsRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, dispatchSettings(), 0)
    compare(store.notifyOnEscalation, true, "the switch keeps the user's value")
    compare(store.runSettings.prefixHistory.length, 1)
    compare(store.runSettings.prefixHistory[0], "old")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.confirmDispatch, true)
    compare(store.runSettings.verify[0], "uv run pytest")
    compare(store.runSettings.notifyOnEscalation, false, "the object is kept as it was read")
  }

  function test_run_settings_follow_the_project() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    compare(store.runSettings.parallelism, 4)
    store.project = rootB
    compare(Object.keys(store.runSettings).length, 0, "a project switch forgets A's settings")
    reply(store.runSettingsRunner.current, "Traceback: boom\n", 1)
    compare(Object.keys(store.runSettings).length, 0, "an unreadable reply is {}")
    var other = makeWithProject(rootA); if (!other) return
    reply(other.runSettingsRunner.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(other.runSettings.parallelism, 9)
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

  // Project A with its run settings read (dispatchSettings).
  function dispatchStore() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    return store
  }

  // Every dispatch field at its "none" value.
  function checkDispatchIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
    compare(store.dispatchTarget, null, label + ": target")
    compare(store.dispatchForm, null, label + ": form")
    compare(store.dispatchPreview, null, label + ": preview")
    compare(store.dispatchError, "", label + ": error")
    compare(store.dispatchErrorType, "", label + ": error type")
    compare(store.dispatchErrors.length, 0, label + ": errors")
    compare(store.dispatchSuggest, null, label + ": suggest")
    compare(store.dispatchRunId, "", label + ": run id")
    compare(store.dispatchMessage, "", label + ": message")
    compare(store.dispatchLog, "", label + ": log")
    compare(store.dispatchLogTail, "", label + ": log tail")
    compare(store.dispatchExitCode, null, label + ": exit code")
    compare(store.dispatchTargetLabel, "", label + ": target label")
  }

  // 1 (dispatchStart() from idle is checked in Task 5's test 21)
  function test_dispatch_starts_idle() {
    var store = make(); if (!store) return
    checkDispatchIdle(store, "fresh")
    compare(store.dispatchStartRunners.length, 0)
    compare(store.dispatchDebounceTimer.running, false)
    verify(!store.dispatchDefaultsRunner.current)
    verify(!store.dispatchPreviewRunner.current)
    compare(store.closeDispatch(), true, "closing an idle dispatch is fine")
    checkDispatchIdle(store, "after close")
  }

  // 2
  function test_open_without_project_is_refused() {
    var store = make(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), false)
    checkDispatchIdle(store, "no project")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
  }

  // 3
  function test_open_milestone_goes_previewing_and_asks_defaults() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.runSettingsRunner.current, JSON.stringify({ verify: ["uv run pytest", "  "], allowNoVerification: true,
      notifyOnEscalation: false, prefixHistory: [], parallelism: 6, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTarget.command, "milestone")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(proc.command[3], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.base, "", "no base until the lookup replies")
    compare(form.prefix, "m3")
    compare(form.verify.length, 1, "the stored non-blank commands")
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 6)
    compare(form.allowNoVerification, false, "the opt-out is never pre-ticked")
    verify(!store.dispatchPreviewRunner.current, "no preview before the default branch is known")
    compare(store.dispatchDebounceTimer.running, false)
  }

  function test_open_before_the_settings_reply_starts_from_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.verify.length, 0)
    compare(store.dispatchForm.parallelism, 4)
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    compare(store.dispatchForm.verify.length, 0, "a late settings reply does not touch the open form")
    compare(store.runSettings.verify[0], "uv run pytest", "but it is kept for the next opening")
  }

  // 4
  function test_open_story_is_offered_with_the_story_flag() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.s1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchTarget.command, "story")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--story", "s1"]))
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    verify(store.dispatchForm, "an offered target has a form")
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the story's prefix")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.running, true)
  }

  // 5
  function test_open_done_card_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.d1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.openDispatch(null, cards), false)
    compare(store.dispatchError, "No card to dispatch")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  function test_close_and_reopen_drop_the_pending_lookup() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var first = store.dispatchDefaultsRunner.current
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
    compare(first.running, false, "the lookup is stopped")
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchState, "refused")
    compare(store.openDispatch(cards.m1, cards), true, "opening again replaces a refused target")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchSuggest, null)
    verify(store.dispatchDefaultsRunner.current !== first, "a fresh lookup per opening")
  }

  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  // Project A with milestone m1 opened and its default branch `main` read: the
  // first preview is in flight.
  function previewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 6
  function test_defaults_reply_sets_base_and_launches_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchDebounceTimer.running, false, "the check runs at once, no debounce")
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a preview was launched")
    compare(argv(proc), tc.previewCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.command[2], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.command[12], "uv run pytest", "a command with spaces is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  // 8 + Review Focus 2
  function test_defaults_failure_sends_no_base() {
    var replies = [JSON.stringify({ ok: false, error: { type: "NoDefaultBranch", message: "detached HEAD" } }) + "\n",
                   "Traceback: boom\n",
                   defaultsOk("   "),
                   JSON.stringify({ ok: true, data: { default_branch: null, source: "" } }) + "\n",
                   JSON.stringify({ ok: true }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      store.openDispatch(cards.m1, cards)
      reply(store.dispatchDefaultsRunner.current, replies[i], 1)
      compare(store.dispatchForm.base, "", "reply " + i + " leaves base blank")
      var proc = store.dispatchPreviewRunner.current
      verify(proc, "reply " + i + ": the check still runs")
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest",
              "reply " + i + ": no --base-branch pair")
    }
    var padded = dispatchStore(); if (!padded) return
    var map = dispatchCards()
    padded.openDispatch(map.m1, map)
    reply(padded.dispatchDefaultsRunner.current, defaultsOk("  main \n"), 0)
    compare(padded.dispatchForm.base, "main", "the branch is trimmed")
    compare(padded.dispatchPreviewRunner.current.command[6], "main")
  }

  // 10
  function test_preview_ok_goes_ready_with_summary() {
    var store = previewingStore(); if (!store) return
    compare(store.dispatchPreview, null)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done")
    compare(store.dispatchPreview.integrate, "Integrate → m3-integrate")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 11
  function test_preview_refusal_goes_refused_verbatim() {
    var store = previewingStore(); if (!store) return
    var message = "milestone m1 is claimed by run 20261005T010000Z-abcd (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchPreview, null)
    var untyped = previewingStore(); if (!untyped) return
    reply(untyped.dispatchPreviewRunner.current,
          JSON.stringify({ ok: false, error: { type: 7, message: "dependency cycle: s1 -> s2 -> s1" } }) + "\n", 0)
    compare(untyped.dispatchState, "refused")
    compare(untyped.dispatchError, "dependency cycle: s1 -> s2 -> s1")
    compare(untyped.dispatchErrorType, "", "a type that is not a string is unknown")
  }

  // 12
  function test_preview_unreadable_goes_refused() {
    var replies = ["", "Traceback: boom\n", "[1, 2]\n",
                   JSON.stringify({ ok: false, error: { type: "X", message: "  " } }) + "\n",
                   JSON.stringify({ ok: false, error: "boom" }) + "\n",
                   JSON.stringify({ ok: false, error: null }) + "\n",
                   JSON.stringify({ ok: "yes" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = previewingStore(); if (!store) return
      reply(store.dispatchPreviewRunner.current, replies[i], 1)
      compare(store.dispatchState, "refused", "reply " + i)
      compare(store.dispatchError, "The preview could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchPreview, null, "reply " + i)
    }
  }

  // 14
  function test_invalid_form_is_refused_without_launch() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch("board", cards), true)
    compare(store.dispatchTarget.level, "board")
    compare(store.dispatchForm.prefix, "", "the board has no milestone title to stem")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Form")
    compare(store.dispatchErrors.length, 1)
    compare(store.dispatchErrors[0].field, "prefix")
    compare(store.dispatchError, "Enter a branch prefix")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  // 20 (the preview half)
  function test_subtask_goes_ready_without_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), true)
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the subtask's prefix")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview, null, "am has no dry run for one card")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  function test_a_closed_dispatch_drops_the_late_defaults_reply() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var lookup = store.dispatchDefaultsRunner.current
    store.closeDispatch()
    reply(lookup, defaultsOk("main"), 0)
    checkDispatchIdle(store, "after the late reply")
    verify(!store.dispatchPreviewRunner.current, "no preview")
  }

  // 7
  function test_defaults_reply_keeps_a_user_set_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("base", "develop"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "develop", "the user's base wins over the lookup")
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
  }

  // 9
  function test_debounce_waits_for_defaults() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("prefix", "m3b"), true)
    compare(store.dispatchDebounceTimer.running, true)
    fire(store.dispatchDebounceTimer)
    verify(!store.dispatchPreviewRunner.current, "nothing launched before the default branch is known")
    compare(store.dispatchState, "previewing")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the defaults reply checks the form")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3b|--max-concurrent|4|--verify|uv run pytest")

    var early = dispatchStore(); if (!early) return
    early.openDispatch(cards.m1, cards)
    early.setDispatchField("parallelism", 2)
    reply(early.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(early.dispatchDebounceTimer.running, false, "the defaults reply's check replaces the pending one")
    compare(early.dispatchPreviewRunner.current.command[10], "2")
  }

  // 13
  function test_board_preview_argv() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch("board", cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused", "the board starts with no prefix")
    compare(store.setDispatchField("prefix", " all "), true)
    fire(store.dispatchDebounceTimer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the board is previewed")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|board|--base-branch|main|--branch-prefix|all|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 12)
    var board = { board: true, levels: [{ level: 0, milestones: [{ milestone_id: "m1", title: "M3", branch_prefix: "m3",
                                                                   base_branch: "main", plan: dispatchDryRun() }] }] }
    reply(proc, previewOk(board), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "1 milestone, 3 subtasks")
    compare(store.dispatchPreview.board, true)
  }

  // 15 + Review Focus 1
  function test_allow_no_verification_flag() {
    var store = previewingStore(); if (!store) return
    store.setDispatchField("verify", [])
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "no command and no opt-out")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "previewing")
    var proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
    store.setDispatchField("verify", ["", "  ", "-x make check", "uv run pytest"])
    fire(store.dispatchDebounceTimer)
    proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
    compare(proc.command[12], "-x make check", "a command that starts with a dash is one verbatim argument")
    store.setDispatchField("allowNoVerification", "yes")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchPreviewRunner.current.command[store.dispatchPreviewRunner.current.command.length - 1], "uv run pytest",
            "only a real true sends the opt-out")
  }

  // Review Focus 4 (the form half)
  function test_a_verify_value_that_is_not_a_list_is_refused_not_thrown() {
    var store = previewingStore(); if (!store) return
    compare(store.setDispatchField("verify", "uv run pytest"), true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    store.setDispatchField("parallelism", "4")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "the store converts nothing")
    compare(store.dispatchErrors[0].field, "parallelism")
    store.setDispatchField("parallelism", 4)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
  }

  // 16
  function test_change_restarts_400ms_debounce_and_one_preview_per_burst() {
    var store = previewingStore(); if (!store) return
    var timer = store.dispatchDebounceTimer
    compare(timer.objectName, "dispatchDebounceTimer")
    compare(timer.interval, 400)
    compare(timer.repeat, false)
    var first = store.dispatchPreviewRunner.current
    compare(store.setDispatchField("prefix", "a"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("prefix", "ab"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("parallelism", 2), true)
    compare(store.dispatchState, "previewing")
    compare(timer.running, true)
    verify(store.dispatchPreviewRunner.current === first, "nothing launched during the burst")
    compare(first.running, false, "the preview in flight was cancelled")
    fire(timer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc !== first, "one preview for the burst")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|ab|--max-concurrent|2|--verify|uv run pytest")
  }

  // 17
  function test_latest_preview_wins() {
    var store = previewingStore(); if (!store) return
    var first = store.dispatchPreviewRunner.current
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    var second = store.dispatchPreviewRunner.current
    verify(second !== first, "a second preview")
    reply(first, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "previewing", "the older preview's reply is dropped")
    compare(store.dispatchPreview, null)
    reply(second, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    verify(store.dispatchPreview !== null)
  }

  // 18
  function test_change_after_ready_drops_preview_and_goes_previewing() {
    var store = previewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    var form = store.dispatchForm
    var list = ["make test"]
    compare(store.setDispatchField("verify", list), true)
    list.push("rm -rf /")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchPreview, null)
    compare(form.verify[0], "uv run pytest", "the old form was not changed in place")
    compare(store.dispatchForm.verify.length, 1, "verify is copied")
    compare(store.dispatchForm.verify[0], "make test")
    compare(store.dispatchForm.prefix, "old", "the other fields are kept")
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchDebounceTimer.running, true)
  }

  // 19
  function test_set_unknown_field_or_while_idle_is_refused() {
    var store = dispatchStore(); if (!store) return
    compare(store.setDispatchField("prefix", "x"), false, "idle")
    compare(store.dispatchForm, null)
    var cards = dispatchCards()
    store.openDispatch(cards.d1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("branch", "x"), false, "unknown field")
    compare(store.setDispatchField("__proto__", {}), false)
    compare(store.dispatchForm.prefix, "old", "nothing changed")
    compare(store.dispatchForm.branch, undefined)
    compare(store.dispatchDebounceTimer.running, false)
  }

  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // Project A with milestone m1's preview landed: Start is allowed.
  function readyStore() {
    var store = previewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    return store
  }

  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}'

  // 20 (the start half)
  function test_subtask_start_argv_uses_card() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.t1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchStart(), true)
    var proc = store.dispatchStartRunners[0].current
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 13)
  }

  // 21 + Review Focus 3
  function test_start_refused_unless_ready() {
    var store = dispatchStore(); if (!store) return
    compare(store.dispatchStart(), false, "idle")
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchStart(), false, "previewing")
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchStart(), false, "refused")
    compare(store.dispatchStartRunners.length, 0, "no start runner")
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStart(), false, "a fresh store")
    var ready = readyStore(); if (!ready) return
    compare(ready.dispatchStart(), true)
    compare(ready.dispatchStart(), false, "a second Start while starting")
    compare(ready.dispatchStartRunners.length, 1, "one launch for a double click")
  }

  // 22
  function test_start_argv_and_starting() {
    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    compare(store.dispatchState, "starting")
    compare(store.dispatchStartRunners.length, 1)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/my proj")
    compare(runner.guard, "", "a preview or a project switch never stops a start")
    var proc = runner.current
    compare(argv(proc), tc.startCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.running, true)
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done", "the preview stays up while starting")
  }

  // 23
  function test_change_and_close_refused_while_starting() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    compare(store.setDispatchField("prefix", "x"), false)
    compare(store.dispatchForm.prefix, "old")
    compare(store.closeDispatch(), false)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchDebounceTimer.running, false)
  }

  // 24
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
    reply(store.snapshotRunner.current, okReply([]), 0)
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-1")
    compare(store.dispatchMessage, "")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
    compare(store.dispatchStartRunners.length, 1, "the same runner writes the settings")
    verify(store.dispatchStartRunners[0] === runner)
    var save = runner.current
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.verify.join(","), "uv run pytest")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.allowNoVerification, false)
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0, "the runner goes after the write")
    compare(store.flashText, "")
    compare(store.dispatchState, "started")
  }

  // 25 + Review Focus 5 (run id half)
  function test_start_ok_without_run_id_emits_null() {
    var ids = [null, "", 42]
    for (var i = 0; i < ids.length; i++) {
      var store = readyStore(); if (!store) return
      var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk(ids[i], "started, run not visible yet"), 0)
      compare(store.dispatchState, "started", "run_id " + i)
      compare(store.dispatchRunId, "", "run_id " + i)
      compare(store.dispatchMessage, "started, run not visible yet")
      compare(spy.count, 1)
      compare(spy.signalArguments[0][0], null, "run_id " + i + ": not visible yet")
    }
  }

  // 26 + Review Focus 4 (the history half)
  function test_prefix_history_dedups_and_caps_at_20() {
    var store = makeWithProject(rootA); if (!store) return
    var history = ["a", "m3", "", "  ", 7, "b"]
    for (var i = 0; i < 25; i++) history.push("p" + i)
    reply(store.runSettingsRunner.current, JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false,
      notifyOnEscalation: false, prefixHistory: history, parallelism: 4, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "  m3 ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3", "the prefix is sent trimmed")
    reply(runner.current, startOk("r-1", ""), 0)
    var expected = ["m3", "a", "b"]
    for (var j = 0; j < 17; j++) expected.push("p" + j)
    var saved = JSON.parse(runner.current.command[4])
    compare(saved.prefixHistory.length, 20)
    compare(saved.prefixHistory.join(","), expected.join(","))
    compare(store.runSettings.prefixHistory.join(","), expected.join(","))

    var bare = makeWithProject(rootA); if (!bare) return
    reply(bare.runSettingsRunner.current, "Traceback: boom\n", 1)
    bare.openDispatch(cards.m1, cards)
    reply(bare.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    bare.setDispatchField("verify", ["make test"])
    fire(bare.dispatchDebounceTimer)
    reply(bare.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(bare.dispatchStart(), true)
    var bareRunner = bare.dispatchStartRunners[0]
    reply(bareRunner.current, startOk("r-2", ""), 0)
    compare(argv(bareRunner.current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4,"prefixByMilestone":{"m1":"m3"}}')
  }

  // 27
  function test_start_failure_goes_failed_with_log() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, JSON.stringify({ ok: false, error: { type: "AmExited", message: "am run exited at once (exit 2)" },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: milestone m1 not found" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "am run exited at once (exit 2)")
    compare(store.dispatchErrorType, "AmExited")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "error: milestone m1 not found")
    compare(store.dispatchExitCode, 2)
    compare(spy.count, 0)
    compare(store.dispatchStartRunners.length, 0, "no settings write after a failed start")
    compare(store.runSettings.prefixHistory.join(","), "old", "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays for another try")
  }

  // 28 + Review Focus 5 (exit code half)
  function test_start_unreadable_goes_failed() {
    var replies = ["", "Traceback: boom\n", JSON.stringify({ ok: "maybe" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, replies[i], 1)
      compare(store.dispatchState, "failed", "reply " + i)
      compare(store.dispatchError, "The launch could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchLog, "", "reply " + i)
      compare(store.dispatchExitCode, null, "reply " + i)
      compare(store.dispatchStartRunners.length, 0, "reply " + i)
    }
    var blank = readyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, JSON.stringify({ ok: false, error: { type: "SpawnFailed", message: " " },
      log: "/tmp/l", exit_code: "2", log_tail: 5 }) + "\n", 0)
    compare(blank.dispatchState, "failed")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "SpawnFailed")
    compare(blank.dispatchLog, "/tmp/l")
    compare(blank.dispatchLogTail, "", "a log tail that is not a string")
    compare(blank.dispatchExitCode, null, "an exit code that is not a number")
  }

  // 29
  function test_failed_then_change_previews_again() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, ctlFail("ClaimedError", "claimed by r-0"), 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchStart(), false, "a failed start is not retried without a new check")
    compare(store.setDispatchField("prefix", "m3-retry"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchLog, "")
    compare(store.dispatchExitCode, null)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3-retry|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 1)
  }

  // A start re-snapshots every usable root, not only the project it was made in.
  function test_a_dispatch_start_refreshes_every_usable_root() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    store.project = rootA
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var seq = store.snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // 30
  function test_settings_write_failure_flashes() {
    var replies = [JSON.stringify({ ok: false, error: { type: "Invalid", message: "x" } }) + "\n", "garbage\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      var runner = store.dispatchStartRunners[0]
      reply(runner.current, startOk("r-1", ""), 0)
      reply(runner.current, replies[i], 1)
      compare(store.flashText, "Dispatch settings could not be saved", "reply " + i)
      compare(store.dispatchState, "started", "the run still started")
      compare(store.dispatchStartRunners.length, 0)
      compare(store.notifyOnEscalation, false, "the notify switch is untouched")
      verify(!store.settingsSaveRunner.current, "the notify switch's runner is not used")
    }
  }

  function test_started_refuses_changes_and_reopening_starts_over() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.setDispatchField("prefix", "x"), false, "started")
    compare(store.dispatchStart(), false, "started")
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRunId, "")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchForm.verify[0], "uv run pytest", "the next form starts from the saved values")
  }

  // 31
  function test_project_switch_resets_dispatch_and_drops_old_preview() {
    var store = previewingStore(); if (!store) return
    var preview = store.dispatchPreviewRunner.current
    store.project = rootB
    checkDispatchIdle(store, "after the switch")
    compare(Object.keys(store.runSettings).length, 0)
    compare(preview.running, false, "A's preview is stopped")
    reply(preview, previewOk(dispatchDryRun()), 0)
    checkDispatchIdle(store, "after A's late preview")

    var pending = previewingStore(); if (!pending) return
    pending.setDispatchField("prefix", "x")
    compare(pending.dispatchDebounceTimer.running, true)
    pending.project = rootB
    compare(pending.dispatchDebounceTimer.running, false, "no check is left pending")
    checkDispatchIdle(pending, "switch during a burst")

    var cleared = previewingStore(); if (!cleared) return
    cleared.project = ""
    checkDispatchIdle(cleared, "no project")
  }

  // 32
  function test_start_result_belongs_to_its_project() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var startProc = runner.current
    store.project = rootB
    checkDispatchIdle(store, "B after the switch from starting")
    compare(startProc.running, true, "the start is not stopped")
    compare(store.dispatchStartRunners.length, 1)
    var seq = store.snapshotRunner.seq
    reply(startProc, startOk("r-1", ""), 0)
    checkDispatchIdle(store, "B after A's start landed")
    compare(spy.count, 0)
    compare(store.snapshotRunner.seq, seq, "no refresh for B")
    compare(Object.keys(store.runSettings).length, 0, "B's settings do not take A's values")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(runner.current, "garbage\n", 1)
    compare(store.flashText, "", "no flash about A in B")
    compare(store.dispatchStartRunners.length, 0)
  }

  // 32b
  function test_start_reply_after_switching_away_and_back_is_not_here() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    store.project = rootB
    store.project = rootA
    checkDispatchIdle(store, "back in A")
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(store.dispatchRunId, "")
    compare(spy.count, 0)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
  }

  // 33
  function test_start_in_other_project_does_not_stop_the_first() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var procA = store.dispatchStartRunners[0].current
    store.project = rootB
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true, "B's dispatch opens while A's start is in flight")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 2)
    compare(store.dispatchStartRunners[0].madeFor, "/home/u/my proj")
    compare(store.dispatchStartRunners[1].madeFor, "/home/u/b")
    compare(procA.running, true, "A's start is still running")
    var procB = store.dispatchStartRunners[1].current
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(procA, startOk("r-a", ""), 0)
    compare(store.dispatchState, "starting", "A's reply does not land in B's dialog")
    reply(procB, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
  }

  // 34
  function test_panel_close_closes_dispatch_but_not_a_start() {
    var store = activeStore(rootA); if (!store) return
    reply(store.runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    store.active = false
    checkDispatchIdle(store, "closed from ready")

    store.active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "x")
    compare(store.dispatchDebounceTimer.running, true)
    store.active = false
    compare(store.dispatchDebounceTimer.running, false, "no timer while idle")
    checkDispatchIdle(store, "closed during a burst")

    store.active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    store.active = false
    compare(store.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started", "it lands normally")
    compare(store.dispatchRunId, "r-1")
  }

  // ---- dispatch: story target, retarget and keyed prefix (2.1)

  // get-run-settings like dispatchSettings(), with prefixByMilestone set to map.
  function keyedSettings(map) {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true, prefixByMilestone: map }) + "\n"
  }

  // 2.1 test 3
  function test_open_sets_the_target_label() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    store.openDispatch(cards.t1, cards)
    compare(store.dispatchTargetLabel, 'Subtask "RunStore dispatch"')
    store.openDispatch("board", cards)
    compare(store.dispatchTargetLabel, "Whole board")
    store.openDispatch(null, cards)
    compare(store.dispatchTargetLabel, "No card", "a refused opening is labelled too")
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
  }

  // 2.1 test 5
  function test_story_prefix_reads_the_snapshot_then_the_keyed_map() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.runSettingsRunner.current, keyedSettings({ m9: "m9-map" }), 0)
    store.runs = [{ id: "r-old", milestone_id: "m1", branch_prefix: "m3-old", started_at: "2026-10-01T00:00:00Z" },
                  { id: "r-live", milestone_id: "m1", branch_prefix: " m3-live ", started_at: "2026-10-06T00:00:00Z" },
                  { id: "r-other", milestone_id: "m2", branch_prefix: "m2-x", started_at: "2026-10-07T00:00:00Z" }]
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the milestone's newest snapshot run wins")
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the same default serves the milestone")

    var keyed = makeWithProject(rootA); if (!keyed) return
    reply(keyed.runSettingsRunner.current, keyedSettings({ m1: "m3-map" }), 0)
    keyed.openDispatch(cards.s1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "the keyed map beats the prefix history")
    keyed.openDispatch(cards.t1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "a subtask reads its root milestone's entry")
  }

  // 2.1 test 12 (the done story)
  function test_a_done_story_is_refused_and_labelled() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    cards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    compare(store.openDispatch(cards.s1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  // `am run --story s1 --dry-run` data: one level, story s1 with 2 subtasks rooted on main.
  function storyDryRun() {
    return {
      max_concurrent: 4,
      levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
        { id: "t1", title: "RunStore dispatch", status: "todo", branch: "old-t1", base: "main" },
        { id: "t2", title: "Docs", status: "todo", branch: "old-t2", base: "old-t1" }] }] }],
      already_done: [],
      integrate: null
    }
  }

  // Project A with story s1 opened and its default branch `main` read: the
  // first preview is in flight.
  function storyPreviewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string storyPreviewArgs: "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 2.1 test 4
  function test_story_preview_argv_and_story_summary() {
    var store = storyPreviewingStore(); if (!store) return
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a story is previewed")
    compare(argv(proc), tc.previewCmd + tc.storyPreviewArgs)
    reply(proc, previewOk(storyDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 subtasks · rooted on main")
    compare(store.dispatchPreview.integrate, "")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 2.1 test 12 (the preview half)
  function test_a_finished_story_preview_is_refused() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [],
      already_done: [{ kind: "story", id: "s1", title: "Dispatch store" }], integrate: null }), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "Nothing left to run")
    compare(store.dispatchErrorType, "Empty")
    compare(store.dispatchPreview, null)
    compare(store.dispatchSuggest, null)
    compare(store.dispatchStart(), false, "Start only works from ready")
    compare(store.dispatchStartRunners.length, 0)

    var milestone = previewingStore(); if (!milestone) return
    reply(milestone.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [], already_done: [], integrate: null }), 0)
    compare(milestone.dispatchState, "ready", "a milestone with nothing left keeps its behaviour")
    compare(milestone.dispatchPreview.summary, "0 levels · 0 subtasks")
  }

  // 2.1 test 11 (the preview half)
  function test_a_claimed_story_preview_names_the_other_run() {
    var store = storyPreviewingStore(); if (!store) return
    var message = "story s1 is claimed by run r-other (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchPreview, null)
  }

  property string blockedMessage: "story s1 is blocked by s0 (todo); dispatch milestone m1 instead"

  // Every dispatch field, as one string to compare before and after.
  function dispatchFields(store) {
    return JSON.stringify([store.dispatchState, store.dispatchTarget, store.dispatchTargetLabel, store.dispatchForm,
                           store.dispatchPreview, store.dispatchError, store.dispatchErrorType, store.dispatchErrors,
                           store.dispatchSuggest, store.dispatchRunId, store.dispatchMessage, store.dispatchLog,
                           store.dispatchLogTail, store.dispatchExitCode])
  }

  // retargetToMilestone() returns false, changes no dispatch field and launches no lookup.
  function checkRetargetRefused(store, label) {
    var before = dispatchFields(store)
    var lookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), false, label)
    compare(dispatchFields(store), before, label + ": nothing changed")
    verify(store.dispatchDefaultsRunner.current === lookup, label + ": no lookup")
  }

  // 2.1 test 8
  function test_retarget_from_a_blocked_preview() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, tc.blockedMessage, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStart(), false, "Start stays refused")
    var storyLookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    var lookup = store.dispatchDefaultsRunner.current
    verify(lookup !== storyLookup, "a fresh --defaults lookup")
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/my proj")
    reply(lookup, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "the milestone is previewed")
  }

  // 2.1 test 10
  function test_retarget_refused_outside_a_blocked_refusal() {
    var cards = dispatchCards()
    var idle = dispatchStore(); if (!idle) return
    checkRetargetRefused(idle, "idle")
    checkDispatchIdle(idle, "idle after the refusal")

    var ready = readyStore(); if (!ready) return
    checkRetargetRefused(ready, "ready")

    var claimed = storyPreviewingStore(); if (!claimed) return
    reply(claimed.dispatchPreviewRunner.current, ctlFail("ClaimedError", "story s1 is claimed by run r-other"), 0)
    checkRetargetRefused(claimed, "ClaimedError")

    var form = dispatchStore(); if (!form) return
    form.openDispatch("board", cards)
    reply(form.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(form.dispatchErrorType, "Form")
    checkRetargetRefused(form, "Form")

    var target = dispatchStore(); if (!target) return
    var doneCards = dispatchCards()
    doneCards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    target.openDispatch(doneCards.s1, doneCards)
    compare(target.dispatchErrorType, "Target")
    checkRetargetRefused(target, "Target")

    var failed = readyStore(); if (!failed) return
    failed.dispatchStart()
    reply(failed.dispatchStartRunners[0].current, ctlFail("AmExited", "am run exited at once (exit 2)"), 0)
    compare(failed.dispatchState, "failed")
    checkRetargetRefused(failed, "failed")

    var orphan = dispatchStore(); if (!orphan) return
    var orphanCards = dispatchCards()
    orphanCards.o1 = { id: "o1", title: "Orphan", status: "todo", parentId: "", depth: 1 }
    orphan.openDispatch(orphanCards.o1, orphanCards)
    reply(orphan.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(orphan.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|o1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(orphan.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", "story o1 is blocked"), 0)
    compare(orphan.dispatchState, "refused")
    compare(orphan.dispatchErrorType, "StoryBlockedError")
    compare(orphan.dispatchSuggest, null, "no milestone to offer")
    compare(orphan.dispatchTargetLabel, 'Story "Orphan"')
    checkRetargetRefused(orphan, "a blocked story with no milestone")

    var closed = storyPreviewingStore(); if (!closed) return
    reply(closed.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(closed.closeDispatch(), true)
    checkRetargetRefused(closed, "closed after a blocked refusal")
    checkDispatchIdle(closed, "still idle")
  }

  // 2.1 test 13
  function test_an_edit_after_a_blocked_refusal_previews_again() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.setDispatchField("prefix", "x"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    checkRetargetRefused(store, "previewing after the edit")
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|x|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}', "the action comes back")
  }

  // 2.1 Review Focus 4 and 5
  function test_retarget_goes_once_to_the_milestone_recorded_at_the_opening() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    cards.m1 = { id: "m1", title: "M4 Renamed", status: "todo", parentId: "", depth: 0 }
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"', "the milestone recorded at the opening")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchForm.parallelism, 4, "the story's edits are not carried over")
    compare(store.dispatchForm.prefix, "old")
    checkRetargetRefused(store, "the second call, while previewing")
  }

  // Project A with story s1's preview landed: Start is allowed.
  function storyReadyStore() {
    var store = storyPreviewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    return store
  }

  // 2.1 test 6
  function test_a_story_start_saves_the_prefix_under_its_milestone() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.runSettingsRunner.current, keyedSettings({ m9: "x" }), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + tc.storyPreviewArgs)
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" +
            '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}')
    var map = store.runSettings.prefixByMilestone
    compare(Object.keys(map).sort().join(","), "m1,m9", "merged locally")
    compare(map.m9, "x", "the stored entry is kept")
    compare(map.m1, "old")
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
  }

  // 2.1 test 7
  function test_milestone_starts_key_the_prefix_and_subtask_or_board_starts_do_not() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(runner.current.command[4], tc.savedJson, "a milestone start keys its own id")
    compare(store.runSettings.prefixByMilestone.m1, "old")

    var plain = '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4}'
    var cards = dispatchCards()
    var subtask = dispatchStore(); if (!subtask) return
    subtask.openDispatch(cards.t1, cards)
    reply(subtask.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(subtask.dispatchStart(), true)
    var subtaskRunner = subtask.dispatchStartRunners[0]
    reply(subtaskRunner.current, startOk("r-2", ""), 0)
    compare(argv(subtaskRunner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a subtask start keys nothing")
    compare(subtask.runSettings.prefixByMilestone, undefined, "nothing keyed locally")

    var board = dispatchStore(); if (!board) return
    board.openDispatch("board", cards)
    reply(board.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    board.setDispatchField("prefix", "old")
    fire(board.dispatchDebounceTimer)
    reply(board.dispatchPreviewRunner.current, previewOk({ board: true, levels: [] }), 0)
    compare(board.dispatchState, "ready")
    compare(board.dispatchStart(), true)
    var boardRunner = board.dispatchStartRunners[0]
    reply(boardRunner.current, startOk("r-3", ""), 0)
    compare(argv(boardRunner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a board start keys nothing")
  }

  // 2.1 Review Focus 2
  function test_a_stored_map_that_is_not_an_object_merges_from_nothing() {
    var stored = [[], "x", ["a"], 7, null]
    for (var i = 0; i < stored.length; i++) {
      var store = makeWithProject(rootA); if (!store) return
      reply(store.runSettingsRunner.current, keyedSettings(stored[i]), 0)
      var cards = dispatchCards()
      store.openDispatch(cards.s1, cards)
      reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
      compare(store.dispatchState, "started", "stored " + i)
      compare(Object.keys(store.runSettings.prefixByMilestone).join(","), "m1", "stored " + i + ": only the new entry")
      compare(store.runSettings.prefixByMilestone.m1, "old", "stored " + i)
    }
  }

  // 2.1 Review Focus 3
  function test_the_keyed_prefix_is_the_trimmed_one_sent() {
    var store = storyPreviewingStore(); if (!store) return
    store.setDispatchField("prefix", "  m3-spaced ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3-spaced", "sent trimmed")
    compare(runner.savedJson, '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3-spaced","old"],' +
                              '"parallelism":4,"prefixByMilestone":{"m1":"m3-spaced"}}')
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.runSettings.prefixByMilestone.m1, "m3-spaced")
  }

  // A StoryBlockedError start failure, with the log fields start-run.py adds.
  function startBlocked() {
    return JSON.stringify({ ok: false, error: { type: "StoryBlockedError", message: tc.blockedMessage },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: story s1 is blocked" }) + "\n"
  }

  // 2.1 test 9
  function test_retarget_from_a_blocked_start() {
    var store = storyReadyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    var settingsBefore = JSON.stringify(store.runSettings)
    compare(store.dispatchStart(), true)
    var seq = store.snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startBlocked(), 0)
    compare(store.dispatchState, "refused", "a blocked story is refused, not failed")
    compare(store.dispatchError, tc.blockedMessage)
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(store.dispatchLog, "")
    compare(store.dispatchLogTail, "")
    compare(store.dispatchExitCode, null)
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStartRunners.length, 0, "the runner is dropped: no set-run-settings")
    compare(JSON.stringify(store.runSettings), settingsBefore, "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays")
    compare(spy.count, 0)
    compare(store.snapshotRunner.seq, seq, "no re-snapshot")
    compare(store.dispatchStart(), false, "Start stays refused")
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs)

    var blank = storyReadyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, ctlFail("StoryBlockedError", "  "), 0)
    compare(blank.dispatchState, "refused")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(blank.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
  }

  // 2.1 test 11 (the start half)
  function test_a_claimed_story_start_fails_with_the_log() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, JSON.stringify({ ok: false,
      error: { type: "ClaimedError", message: "story s1 is claimed by run r-other" },
      log: "/home/u/.local/state/am-run.log", exit_code: 1, log_tail: "claimed" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "story s1 is claimed by run r-other")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "claimed")
    compare(store.dispatchExitCode, 1)
    compare(store.dispatchSuggest, null)
    compare(store.retargetToMilestone(), false)
  }

  // 2.1 Review Focus 1
  function test_a_late_blocked_start_reply_changes_nothing() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    store.project = rootB
    checkDispatchIdle(store, "B after the switch")
    reply(proc, startBlocked(), 0)
    checkDispatchIdle(store, "B after A's blocked reply")
    compare(store.dispatchStartRunners.length, 0, "the runner goes")

    var back = storyReadyStore(); if (!back) return
    back.dispatchStart()
    var backProc = back.dispatchStartRunners[0].current
    back.project = rootB
    back.project = rootA
    reply(back.runSettingsRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(back.openDispatch(cards.m1, cards), true)
    reply(backProc, startBlocked(), 0)
    compare(back.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(back.dispatchError, "")
    compare(back.dispatchErrorType, "")
    compare(back.dispatchSuggest, null)
    compare(back.dispatchTargetLabel, 'Milestone "M3 Document runs"')
  }

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
    compare(store.toasts.length, 0)
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

  // ---- control and logs for a run of any project (3.5)

  property string bRepo: "/home/u/b-work"
  property string settingsCmdB: "python3|/plugin/core/backend/projects/viewer-state.py|get-run-settings|/home/u/b"

  // `e` with its repo_dir moved to bRepo: a run of rootB whose repository is
  // not the registry root (the store tags it by the entry's root).
  function bWork(e) {
    e.repo_dir = tc.bRepo
    return e
  }

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

  // 1
  function test_pause_and_cancel_pass_the_runs_repo_dir_with_or_without_a_project() {
    var store = crossStore("", [running("a1")], [bWork(running("b1")), bWork(running("b2"))]); if (!store) return
    compare(store.project, "")
    compare(store.control("pause", "b1"), true, "no project open is not a refusal")
    var pause = store.controlRunners[0].current
    compare(argv(pause), tc.ctlCmd + "pause|b1|/home/u/b-work")
    compare(pause.command.length, 5)
    compare(pause.launchGuard, "", "no guard")
    compare(store.control("cancel", "a1"), true)
    compare(argv(store.controlRunners[1].current), tc.ctlCmd + "cancel|a1|/home/u/my proj")
    store.project = rootA
    compare(store.control("pause", "b2"), true)
    compare(argv(store.controlRunners[2].current), tc.ctlCmd + "pause|b2|/home/u/b-work", "never the open project's root")
  }

  // 2
  function test_a_task_runs_resume_passes_its_repo_dir_with_no_settings_step() {
    var store = crossStore(rootA, [running("a1")], [bWork(ctlEntry("b1", "started", false, "task"))]); if (!store) return
    compare(store.control("resume", "b1"), true)
    var runner = store.controlRunners[0]
    compare(runner.seq, 1, "one launch only")
    compare(argv(runner.current), tc.ctlCmd + "resume|b1|/home/u/b-work")
    compare(runner.current.command.length, 5)
  }

  // 3
  function test_a_milestone_resume_reads_its_own_projects_settings() {
    var store = crossStore(rootA, [running("a1")], [bWork(dead("b1"))]); if (!store) return
    compare(store.control("resume", "b1"), true)
    var runner = store.controlRunners[0]
    compare(argv(runner.current), tc.settingsCmdB, "B's run settings, not A's")
    compare(runner.current.command.length, 4)
    compare(runner.current.launchGuard, "")
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|b1|/home/u/b-work|--verify|a")
  }

  // 4
  function test_the_resume_keeps_the_repository_it_was_asked_for() {
    var store = crossStore(rootA, [running("a1")], [bWork(dead("b1"))]); if (!store) return
    store.control("resume", "b1")
    var runner = store.controlRunners[0]
    store.refresh()
    reply(store.snapshotRunner.current, allReply([okEntry(tc.rootA, [running("a1")]), okEntry(tc.rootB, [])]), 0)
    compare(store.runById("b1"), null, "the run left the snapshot")
    compare(store.pending.b1, "resume", "a request in flight is never settled by a snapshot")
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|b1|/home/u/b-work|--verify|a")
    compare(store.pending.b1, "resume")
  }

  // 5
  function test_a_run_with_no_repository_or_no_project_root_is_refused() {
    var store = make(); if (!store) return
    var noRepo = held(running("r1"), rootA)
    noRepo.repo_dir = ""
    store.runs = [noRepo, held(dead("r2")), held(ctlEntry("r3", "started", false, "task"))]
    var actions = ["pause", "resume", "cancel"]
    for (var i = 0; i < actions.length; i++) {
      compare(store.refusalOf(actions[i], "r1"), "This run has no repository", actions[i])
      compare(store.control(actions[i], "r1"), false, actions[i])
    }
    compare(store.refusalOf("resume", "r2"), "This run's project is not known")
    compare(store.control("resume", "r2"), false)
    compare(store.controlRunners.length, 0, "nothing launched")
    compare(Object.keys(store.pending).length, 0)
    compare(store.refusalOf("cancel", "r2"), "", "a cancel needs no project root")
    compare(store.control("cancel", "r2"), true)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|r2|/home/u/my proj")
    compare(store.refusalOf("resume", "r3"), "", "a task run's resume needs no project root")
    compare(store.control("resume", "r3"), true)
    compare(argv(store.controlRunners[1].current), tc.ctlCmd + "resume|r3|/home/u/my proj")
    compare(store.controlRunners[1].seq, 1)
    compare(store.controlRunners.length, 2)
  }

  // 6
  function test_a_request_for_another_projects_run_survives_a_switch_and_its_reply_shows_on_that_run() {
    var store = crossStore(rootA, [running("a1")],
                           [bWork(running("b1")), bWork(running("b2")), bWork(dead("b3"))]); if (!store) return
    compare(store.control("pause", "b1"), true)
    var proc = store.controlRunners[0].current
    store.project = rootB
    store.project = ""
    compare(store.pending.b1, "pause", "a switch settles nothing")
    compare(store.controlRunners.length, 1)
    var seq = store.snapshotRunner.seq
    reply(proc, ctlOk({ requested_at: "t1" }), 0)
    compare(store.pending.b1, "pause", "acknowledged: pending until a snapshot settles it")
    compare(store.snapshotRunner.seq, seq + 1, "and re-snapshots")
    compare(store.controlRunners.length, 0)

    compare(store.control("pause", "b2"), true)
    var proc2 = store.controlRunners[0].current
    store.project = rootA
    reply(proc2, ctlFail("NotRunningError", "not running"), 0)
    compare(store.pending.b2, undefined)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "b2", "the error shows on that run")

    compare(store.control("resume", "b3"), true)
    var runner = store.controlRunners[0]
    store.project = rootB
    reply(runner.current, settingsReply(["a"], false), 0)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "resume|b3|/home/u/b-work|--verify|a",
            "the settings reply after a switch launches run-control")
  }

  // Review Focus 5.
  function test_a_request_made_with_no_project_open_is_answered_after_one_opens() {
    var store = crossStore("", [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(store.control("pause", "b1"), true)
    var proc = store.controlRunners[0].current
    store.project = rootA
    var seq = store.snapshotRunner.seq
    reply(proc, ctlFail("NotRunningError", "not running"), 0)
    compare(store.pending.b1, undefined)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "b1")
    compare(store.snapshotRunner.seq, seq + 1)
  }

  // A control reply re-snapshots every usable root, not only the run's.
  function test_a_control_reply_refreshes_every_usable_root() {
    var store = crossStore(rootA, [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(store.control("pause", "a1"), true)
    var seq = store.snapshotRunner.seq
    reply(store.controlRunners[0].current, ctlOk({ run_id: "a1", command: "pause", requested_at: "t1" }), 0)
    compare(store.snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(store.snapshotRunner.current), tc.snapCmd + "|" + tc.rootA + "|" + tc.rootB)
  }

  // Review Focus 2.
  function test_open_cancel_on_a_run_with_no_repository_flashes_why() {
    var store = make(); if (!store) return
    var run = held(running("r1"), rootA)
    run.repo_dir = ""
    store.runs = [run]
    compare(store.openCancel("r1"), false)
    compare(store.cancelOpen, false)
    compare(store.flashText, "This run has no repository")
    compare(store.controlRunners.length, 0)
  }

  // 7
  function test_a_project_switch_keeps_the_dialog_the_flash_the_control_error_and_the_requests() {
    var store = ctlStore([running("r1"), running("r2"), running("r3")]); if (!store) return
    store.control("pause", "r3")
    store.control("pause", "r2")
    reply(store.controlRunners[1].current, ctlFail("NotRunningError", "not running"), 0)
    compare(store.lastControlErrorRunId, "r2")
    store.checkWaiting(Date.now() + 30000)
    compare(store.stillWaiting.r3, true)
    store.openCancel("r1")
    store.cancelText = "can"
    store.cancelError = "x"
    store.flash("The run has finished")
    store.project = rootB
    compare(store.cancelOpen, true)
    compare(store.cancelRunId, "r1")
    compare(store.cancelText, "can")
    compare(store.cancelError, "x")
    compare(store.flashText, "The run has finished")
    compare(store.flashTimer.running, true)
    compare(store.lastControlError, "The run is not running")
    compare(store.lastControlErrorRunId, "r2")
    compare(store.pending.r3, "pause")
    compare(store.stillWaiting.r3, true)
    compare(store.controlRunners.length, 1)
    compare(store.controlRunners[0].runId, "r3")
  }

  // Review Focus 1.
  function test_a_cancel_dialog_for_another_projects_run_survives_closing_the_project_and_confirms() {
    var store = crossStore(rootA, [running("a1")], [bWork(running("b1"))]); if (!store) return
    compare(store.openCancel("b1"), true)
    store.project = ""
    compare(store.cancelRunId, "b1", "the dialog is kept")
    store.cancelText = "cancel"
    compare(store.confirmCancel(), true)
    compare(argv(store.controlRunners[0].current), tc.ctlCmd + "cancel|b1|/home/u/b-work")
    compare(store.cancelOpen, false)
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
    compare(store.alertsArmed, false)
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
    compare(store.toasts.length, 0, "the first list after a reset only arms")
    compare(store.alertsArmed, true)
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
      compare(store.alertsArmed, true, label)
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
    compare(store.alertsArmed, true)
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
    compare(store.alertsArmed, false)
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
    compare(store.toasts.length, 0, "the new store's first list only arms")
    compare(store.alertsArmed, true)
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
}
