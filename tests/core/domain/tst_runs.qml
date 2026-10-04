// tests/core/domain/tst_runs.qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

// Input shape for Runs.normalizeRun (provisional until the runs-snapshot helper exists):
//   raw = {
//     row:    { id, workflow, repo_dir, base_branch, branch_prefix, status, started_at }  // one `am runs` row
//     status: { run: {...}, rows: [...], stories: [...], subtasks: [...],
//               control: { lease: { pid, host, heartbeat_at, accepting, live } }, ... }  // `am status` data, may be absent
//   }
TestCase {
  name: "DomainRuns"

  function fullRaw() {
    return {
      row: { id: "r1", workflow: "orchestrator", repo_dir: "/home/u/repo", base_branch: "main",
             branch_prefix: "mon/", status: "started", started_at: "2026-10-03T10:00:00Z" },
      status: {
        run: { id: "r1", repo_dir: "/home/u/repo", milestone_id: "m-4bf4", status: "started" },
        rows: [{ card_id: "c1", phase: "implement" }],
        stories: [{ card_id: "s1", subtasks: [] }],
        subtasks: [{ card_id: "c1", phases: [{ name: "implement", attempts: [] }] }],
        control: { lease: { pid: 4242, host: "box", heartbeat_at: "2026-10-03T10:05:00Z",
                            accepting: true, live: true } },
        requests: [],
        claims: []
      }
    }
  }

  function checkDefaults(r, label) {
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,status,tree", label)
    compare(r.id, "", label)
    compare(r.repo_dir, "", label)
    compare(r.milestone_id, "", label)
    compare(r.status, "", label)
    compare(r.lease, null, label)
    compare(Array.isArray(r.rows), true, label)
    compare(r.rows.length, 0, label)
    compare(Array.isArray(r.tree.stories), true, label)
    compare(r.tree.stories.length, 0, label)
    compare(Array.isArray(r.tree.subtasks), true, label)
    compare(r.tree.subtasks.length, 0, label)
  }

  function test_normalize_full() {
    var r = Runs.normalizeRun(fullRaw())
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,status,tree")
    compare(r.id, "r1")
    compare(r.repo_dir, "/home/u/repo")
    compare(r.milestone_id, "m-4bf4")
    compare(r.status, "started")
    compare(Object.keys(r.lease).sort().join(","), "accepting,heartbeat_at,host,live,pid")
    compare(r.lease.pid, 4242)
    compare(r.lease.host, "box")
    compare(r.lease.heartbeat_at, "2026-10-03T10:05:00Z")
    compare(r.lease.accepting, true)
    compare(r.lease.live, true)
    compare(r.rows.length, 1)
    compare(r.rows[0].card_id, "c1")
    compare(r.tree.stories.length, 1)
    compare(r.tree.stories[0].card_id, "s1")
    compare(r.tree.subtasks.length, 1)
    compare(r.tree.subtasks[0].card_id, "c1")
    compare(r.tree.subtasks[0].phases[0].name, "implement")
  }

  function test_normalize_status_prefers_am_status() {
    var raw = fullRaw()
    raw.row.status = "stopped"
    raw.status.run.status = "done"
    compare(Runs.normalizeRun(raw).status, "done")

    compare(Runs.normalizeRun({ row: { id: "r1", status: "stopped" } }).status, "stopped")

    var noRun = fullRaw()
    noRun.row.status = "escalated"
    delete noRun.status.run
    compare(Runs.normalizeRun(noRun).status, "escalated")

    // An empty am-status value is not fresher detail: fall back to the row.
    var blank = fullRaw()
    blank.row.status = "stopped"
    blank.status.run.status = ""
    compare(Runs.normalizeRun(blank).status, "stopped")
  }

  function test_normalize_ids_fallback_and_coercion() {
    compare(Runs.normalizeRun({ row: { id: 7 } }).id, "7")

    var fromStatus = Runs.normalizeRun({ status: { run: { id: "r9", repo_dir: "/r", milestone_id: "m9" } } })
    compare(fromStatus.id, "r9")
    compare(fromStatus.repo_dir, "/r")
    compare(fromStatus.milestone_id, "m9")

    compare(Runs.normalizeRun({ row: { milestone_id: "m1" } }).milestone_id, "m1")
    compare(Runs.normalizeRun({ row: { milestone_id: "m1" }, status: { run: { milestone_id: "m2" } } }).milestone_id, "m2")

    var rowWins = Runs.normalizeRun({ row: { id: "a", repo_dir: "/a" }, status: { run: { id: "b", repo_dir: "/b" } } })
    compare(rowWins.id, "a")
    compare(rowWins.repo_dir, "/a")
  }

  function test_normalize_missing_lease() {
    var noControl = fullRaw()
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).lease, null, "no control")

    var cases = [
      { label: "empty control", control: {} },
      { label: "null control", control: null },
      { label: "null lease", control: { lease: null } },
      { label: "string lease", control: { lease: "yes" } },
      { label: "array lease", control: { lease: [] } }
    ]
    for (var i = 0; i < cases.length; i++) {
      var raw = fullRaw()
      raw.status.control = cases[i].control
      compare(Runs.normalizeRun(raw).lease, null, cases[i].label)
    }

    compare(Runs.normalizeRun({ row: { id: "r1", status: "started" } }).lease, null, "no status at all")
  }

  function test_normalize_lease_live_strict() {
    var empty = fullRaw()
    empty.status.control.lease = {}
    var e = Runs.normalizeRun(empty).lease
    compare(e.live, false)
    compare(e.accepting, false)
    compare(e.pid, "")
    compare(e.host, "")
    compare(e.heartbeat_at, "")

    var nulls = fullRaw()
    nulls.status.control.lease = { pid: null, host: null, heartbeat_at: null, live: null, accepting: null }
    var n = Runs.normalizeRun(nulls).lease
    compare(n.pid, "", "null pid")
    compare(n.host, "", "null host")
    compare(n.heartbeat_at, "", "null heartbeat_at")
    compare(n.live, false, "null live")
    compare(n.accepting, false, "null accepting")

    var stringy = fullRaw()
    stringy.status.control.lease = { live: "true", accepting: "true" }
    compare(Runs.normalizeRun(stringy).lease.live, false)
    compare(Runs.normalizeRun(stringy).lease.accepting, false)

    var numeric = fullRaw()
    numeric.status.control.lease = { live: 1, accepting: 1 }
    compare(Runs.normalizeRun(numeric).lease.live, false)
    compare(Runs.normalizeRun(numeric).lease.accepting, false)
  }

  function test_normalize_missing_rows_tree() {
    var bare = Runs.normalizeRun({ status: { run: { status: "started" } } })
    compare(Array.isArray(bare.rows), true)
    compare(bare.rows.length, 0)
    compare(bare.tree.stories.length, 0)
    compare(bare.tree.subtasks.length, 0)

    var raw = fullRaw()
    raw.status.rows = { a: 1 }
    raw.status.stories = {}
    raw.status.subtasks = "x"
    var r = Runs.normalizeRun(raw)
    compare(Array.isArray(r.rows), true)
    compare(r.rows.length, 0)
    compare(Array.isArray(r.tree.stories), true)
    compare(r.tree.stories.length, 0)
    compare(Array.isArray(r.tree.subtasks), true)
    compare(r.tree.subtasks.length, 0)

    var strRows = fullRaw()
    strRows.status.rows = "x"
    compare(Runs.normalizeRun(strRows).rows.length, 0)
  }

  function test_normalize_garbage() {
    checkDefaults(Runs.normalizeRun(undefined), "undefined")
    checkDefaults(Runs.normalizeRun(null), "null")
    checkDefaults(Runs.normalizeRun("x"), "string")
    checkDefaults(Runs.normalizeRun(5), "number")
    checkDefaults(Runs.normalizeRun({}), "empty object")
    checkDefaults(Runs.normalizeRun([]), "array")
    checkDefaults(Runs.normalizeRun({ row: "x", status: 5 }), "non-object row and status")
    checkDefaults(Runs.normalizeRun({ row: null, status: null }), "null row and status")
    checkDefaults(Runs.normalizeRun({ status: { run: "x", control: "y" } }), "non-object run and control")
  }

  function test_state_running() {
    compare(Runs.runState({ status: "started", lease: { live: true } }), "running")
    compare(Runs.runState(Runs.normalizeRun(fullRaw())), "running")
  }

  function test_state_dead_not_live() {
    compare(Runs.runState({ status: "started", lease: { live: false } }), "dead")

    var raw = fullRaw()
    raw.status.control.lease.live = false
    compare(Runs.runState(Runs.normalizeRun(raw)), "dead")

    // A sloppy "true" string is not liveness.
    var stringy = fullRaw()
    stringy.status.control.lease.live = "true"
    compare(Runs.runState(Runs.normalizeRun(stringy)), "dead")

    // runState itself demands live === true, even on a run not built by normalizeRun.
    var truthy = ["true", 1, {}, "yes"]
    for (var i = 0; i < truthy.length; i++) {
      compare(Runs.runState({ status: "started", lease: { live: truthy[i] } }), "dead", "live " + JSON.stringify(truthy[i]))
    }
    compare(Runs.runState({ status: "started", lease: "live" }), "dead", "string lease")
  }

  function test_state_dead_missing_lease() {
    compare(Runs.runState({ status: "started", lease: null }), "dead")
    compare(Runs.runState({ status: "started" }), "dead")
    compare(Runs.runState(Runs.normalizeRun({ row: { id: "r1", status: "started" } })), "dead")

    var noLease = fullRaw()
    delete noLease.status.control
    compare(Runs.runState(Runs.normalizeRun(noLease)), "dead")
  }

  function test_state_terminal_and_parked() {
    var expected = [
      ["stopped", "parked"],
      ["escalated", "escalated"],
      ["cancelled", "cancelled"],
      ["done", "done"]
    ]
    for (var i = 0; i < expected.length; i++) {
      var status = expected[i][0]
      var state = expected[i][1]
      compare(Runs.runState({ status: status, lease: { live: true } }), state, status + " live lease")
      compare(Runs.runState({ status: status, lease: { live: false } }), state, status + " dead lease")
      compare(Runs.runState({ status: status, lease: null }), state, status + " no lease")
      compare(Runs.runState({ status: status }), state, status + " lease key absent")
    }
  }

  function test_state_unknown() {
    var statuses = ["weird", "", "stale", "STARTED", "Done", "running", "dead"]
    for (var i = 0; i < statuses.length; i++) {
      compare(Runs.runState({ status: statuses[i], lease: { live: true } }), "unknown", "status " + statuses[i])
    }
    compare(Runs.runState({ lease: { live: true } }), "unknown", "missing status")
    compare(Runs.runState({}), "unknown", "empty run")
    compare(Runs.runState(null), "unknown", "null")
    compare(Runs.runState(undefined), "unknown", "undefined")
    compare(Runs.runState("x"), "unknown", "string run")
    compare(Runs.runState(Runs.normalizeRun(undefined)), "unknown", "normalised garbage")
  }
}
