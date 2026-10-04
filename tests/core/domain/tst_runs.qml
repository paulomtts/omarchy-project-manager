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

  // ---- 1.2: card mapping ------------------------------------------------------------------

  // A normalised run (the shape normalizeRun returns), built directly. live === null means no lease.
  // opts: { milestone_id (default "m1"), rows, tree, started_at }
  function mkRun(id, status, live, opts) {
    var o = opts || {}
    return {
      id: id, repo_dir: "/r",
      milestone_id: o.milestone_id === undefined ? "m1" : o.milestone_id,
      status: status,
      lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: live },
      rows: o.rows || [],
      tree: o.tree || { stories: [], subtasks: [] },
      started_at: o.started_at
    }
  }

  function sampleTree() {
    return {
      stories: [{ card_id: "s1", subtasks: ["t1", { card_id: "t2" }] }, { card_id: "s2", subtasks: [] }],
      subtasks: [
        { card_id: "t1", phases: [{ name: "spec", status: "done", attempts: [{}] },
                                  { name: "implement", status: "running", attempts: [{}, {}] }] },
        { card_id: "t2", phases: [] },
        { card_id: "t3", story_id: "s2", phases: [{ name: "plan", attempts: [] }] }
      ]
    }
  }

  function checkNone(r, label) {
    compare(Object.keys(r).sort().join(","), "attempt,dimmed,phase,runId,state", label)
    compare(r.state, "none", label)
    compare(r.runId, "", label)
    compare(r.dimmed, false, label)
    compare(r.phase, "", label)
    compare(r.attempt, 0, label)
  }

  function test_card_maps_story_subtask_milestone() {
    var runs = [mkRun("r1", "started", true, { tree: sampleTree() })]
    var s = Runs.cardRunState(runs, "s1")
    compare(s.state, "running", "story")
    compare(s.runId, "r1")
    compare(s.dimmed, false)
    compare(Runs.cardRunState(runs, "t3").state, "running", "subtask")
    compare(Runs.cardRunState(runs, "t3").runId, "r1", "subtask")
    compare(Runs.cardRunState(runs, "m1").state, "running", "milestone")
    checkNone(Runs.cardRunState(runs, "zzz"), "unrelated")

    // A card id that appears only in rows, or only as a subtask's story_id, does not touch the run.
    var rowsOnly = [mkRun("r2", "started", true, {
      rows: [{ card_id: "x9", status: "running" }],
      tree: { stories: [], subtasks: [{ card_id: "t9", story_id: "s9" }] }
    })]
    checkNone(Runs.cardRunState(rowsOnly, "x9"), "row only")
    checkNone(Runs.cardRunState(rowsOnly, "s9"), "story_id only")
  }

  function test_card_synthetic_ids_never_match() {
    var tree = {
      stories: [{ card_id: "integrate", subtasks: [] }, { card_id: "bases", subtasks: [] }],
      subtasks: [{ card_id: "base-x", phases: [] }, { card_id: "integrate", phases: [] }]
    }
    var runs = [
      mkRun("r1", "started", true, { tree: tree, milestone_id: "bases", rows: [{ card_id: "integrate", status: "running" }] }),
      mkRun("r2", "started", true, { milestone_id: "base-x" })
    ]
    var ids = ["integrate", "bases", "base-x", "base-"]
    for (var i = 0; i < ids.length; i++) checkNone(Runs.cardRunState(runs, ids[i]), ids[i])

    // Look-alikes are real cards.
    var lookalike = [mkRun("r3", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "basex" }, { card_id: "my-base-x" }, { card_id: "integrated" }] }
    })]
    compare(Runs.cardRunState(lookalike, "basex").state, "running", "basex")
    compare(Runs.cardRunState(lookalike, "my-base-x").state, "running", "my-base-x")
    compare(Runs.cardRunState(lookalike, "integrated").state, "running", "integrated")
  }

  function test_card_newest_nonterminal_wins() {
    // Input is newest-first: index 0 is the newest run.
    var s = Runs.cardRunState([mkRun("new", "done", null), mkRun("old", "started", true)], "m1")
    compare(s.state, "running")
    compare(s.runId, "old")
    compare(s.dimmed, false)

    s = Runs.cardRunState([mkRun("new", "escalated", null), mkRun("old", "started", false)], "m1")
    compare(s.state, "dead", "dead is non-terminal")
    compare(s.runId, "old")
    compare(s.dimmed, false)

    s = Runs.cardRunState([mkRun("p", "stopped", null), mkRun("d", "started", null)], "m1")
    compare(s.state, "dead", "parked is finished, a lease-less started run is not")
    compare(s.runId, "d")
    compare(s.dimmed, false)

    s = Runs.cardRunState([mkRun("a", "started", true), mkRun("b", "started", false)], "m1")
    compare(s.runId, "a", "two non-terminal: newest wins")
    compare(s.state, "running")
  }

  function test_card_all_terminal_newest_dimmed() {
    var cases = [["stopped", "parked"], ["escalated", "escalated"], ["done", "none"], ["cancelled", "none"]]
    for (var i = 0; i < cases.length; i++) {
      var runs = [mkRun("newest", cases[i][0], null), mkRun("older", "escalated", null), mkRun("oldest", "stopped", null)]
      var s = Runs.cardRunState(runs, "m1")
      compare(s.state, cases[i][1], cases[i][0])
      compare(s.runId, "newest", cases[i][0])
      compare(s.dimmed, true, cases[i][0])
    }
    // An unknown status is not non-terminal either.
    var u = Runs.cardRunState([mkRun("u", "weird", true), mkRun("e", "escalated", null)], "m1")
    compare(u.state, "none")
    compare(u.runId, "u")
    compare(u.dimmed, true)
  }

  function test_card_newest_by_started_at_then_order() {
    var a = mkRun("a", "done", null, { started_at: "2026-10-01T10:00:00Z" })
    var b = mkRun("b", "escalated", null, { started_at: "2026-10-03T10:00:00Z" })
    compare(Runs.cardRunState([a, b], "m1").runId, "b", "later started_at beats index")
    compare(Runs.cardRunState([b, a], "m1").runId, "b")

    var live = mkRun("live", "started", true, { started_at: "2026-09-01T00:00:00Z" })
    compare(Runs.cardRunState([b, live], "m1").runId, "live", "non-terminal beats a newer finished run")

    var l1 = mkRun("l1", "started", true, { started_at: "2026-10-01T00:00:00Z" })
    var l2 = mkRun("l2", "started", false, { started_at: "2026-10-02T00:00:00Z" })
    compare(Runs.cardRunState([l1, l2], "m1").runId, "l2", "started_at decides between non-terminal runs")

    var c = mkRun("c", "done", null)
    compare(Runs.cardRunState([c, b], "m1").runId, "c", "only one has started_at: index decides")
    compare(Runs.cardRunState([b, c], "m1").runId, "b", "only one has started_at: index decides")

    var d = mkRun("d", "done", null, { started_at: "2026-10-03T10:00:00Z" })
    compare(Runs.cardRunState([d, b], "m1").runId, "d", "equal started_at: index decides")

    var n = mkRun("n", "done", null, { started_at: 99999999999999 })
    compare(Runs.cardRunState([a, n], "m1").runId, "a", "non-string started_at is ignored")

    var e = mkRun("e", "done", null, { started_at: "" })
    compare(Runs.cardRunState([e, b], "m1").runId, "e", "empty started_at is ignored")
  }

  function test_card_subtask_phase_attempt() {
    var runs = [mkRun("r1", "started", true, { tree: sampleTree() })]
    var t1 = Runs.cardRunState(runs, "t1")
    compare(t1.phase, "implement")
    compare(t1.attempt, 2)
    var t2 = Runs.cardRunState(runs, "t2")
    compare(t2.phase, "", "empty phases")
    compare(t2.attempt, 0, "empty phases")
    var t3 = Runs.cardRunState(runs, "t3")
    compare(t3.phase, "plan")
    compare(t3.attempt, 0)
    var s1 = Runs.cardRunState(runs, "s1")
    compare(s1.phase, "", "story")
    compare(s1.attempt, 0, "story")
    var m1 = Runs.cardRunState(runs, "m1")
    compare(m1.phase, "", "milestone")
    compare(m1.attempt, 0, "milestone")

    var tree = { stories: [], subtasks: [
      { card_id: "a", phases: [{ name: "review", attempts: [{ attempt: 1 }, { attempt: 3 }] }] },
      { card_id: "b", phases: [{ name: "review", attempts: [{ n: 4 }] }] },
      { card_id: "c", phases: [{ name: "review", attempts: [{ attempt: "7" }] }] },
      { card_id: "d", phases: "x" },
      { card_id: "e" },
      { card_id: "f", phases: [null] },
      { card_id: "g", phases: [{ name: 5, attempts: "x" }] }
    ] }
    var r2 = [mkRun("r2", "started", true, { tree: tree })]
    var expected = [["a", "review", 3], ["b", "review", 4], ["c", "review", 1],
                    ["d", "", 0], ["e", "", 0], ["f", "", 0], ["g", "", 0]]
    for (var i = 0; i < expected.length; i++) {
      var r = Runs.cardRunState(r2, expected[i][0])
      compare(r.state, "running", expected[i][0])
      compare(r.phase, expected[i][1], expected[i][0])
      compare(r.attempt, expected[i][2], expected[i][0])
    }
  }

  function test_card_ignores_brd_status() {
    var runs = [mkRun("r1", "stopped", null, { tree: {
      stories: [{ card_id: "s1", status: "done" }],
      subtasks: [{ card_id: "t1", status: "done", phases: [] }]
    } })]
    compare(Runs.cardRunState(runs, "s1").state, "parked", "story status field ignored")
    compare(Runs.cardRunState(runs, "t1").state, "parked", "subtask status field ignored")
    // A brd card object is not a card id.
    checkNone(Runs.cardRunState(runs, { id: "s1", status: "in_progress" }), "card object as id")
  }

  function test_card_proto_ids() {
    var plain = [mkRun("r1", "started", true, { tree: sampleTree() })]
    var ids = ["__proto__", "constructor", "toString", "hasOwnProperty", "valueOf"]
    for (var i = 0; i < ids.length; i++) checkNone(Runs.cardRunState(plain, ids[i]), "absent " + ids[i])

    var tree = {
      stories: [{ card_id: "constructor", subtasks: ["toString"] }],
      subtasks: [{ card_id: "toString", phases: [{ name: "spec", attempts: [{}] }] }, { card_id: "__proto__", phases: [] }]
    }
    var real = [mkRun("r2", "stopped", null, { tree: tree, milestone_id: "valueOf" })]
    var present = ["__proto__", "constructor", "toString", "valueOf"]
    for (var j = 0; j < present.length; j++) {
      compare(Runs.cardRunState(real, present[j]).state, "parked", "present " + present[j])
      compare(Runs.cardRunState(real, present[j]).runId, "r2", "present " + present[j])
    }
    compare(Runs.cardRunState(real, "toString").phase, "spec")
    compare(Runs.cardRunState(real, "toString").attempt, 1)
    checkNone(Runs.cardRunState(real, "hasOwnProperty"), "still absent")
  }

  function test_card_garbage() {
    var good = mkRun("r1", "started", true, { tree: sampleTree() })
    var inputs = [undefined, null, "x", 5, {}, { length: 1, 0: good }]
    for (var i = 0; i < inputs.length; i++) checkNone(Runs.cardRunState(inputs[i], "m1"), "runs " + i)

    compare(Runs.cardRunState([null, "x", 5, [], good], "m1").runId, "r1", "junk entries skipped")

    var junk = [
      { id: "j", status: "started", lease: { live: true }, tree: "x", rows: 5 },
      { id: "k", status: "started", lease: { live: true }, milestone_id: "m1",
        tree: { stories: [null, 5, { card_id: null }], subtasks: "y" } }
    ]
    compare(Runs.cardRunState(junk, "m1").runId, "k")
    checkNone(Runs.cardRunState(junk, "j"), "run id is not a card id")

    var withBlank = [good, mkRun("blank", "started", true, { milestone_id: "" }),
                     Runs.normalizeRun({ row: { id: "z", status: "started" } })]
    var ids = [null, undefined, "", 0, 5, {}, []]
    for (var k = 0; k < ids.length; k++) checkNone(Runs.cardRunState(withBlank, ids[k]), "cardId " + k)
  }

  // ---- 1.2: rollups -----------------------------------------------------------------------

  // Milestone m1; story s1 owns t1 (string entry) and t2 ({card_id} entry); t3 belongs to s2
  // via story_id; t4 belongs to no story; "integrate" is a synthetic subtask.
  function rollupRun(id, status, live) {
    return mkRun(id, status, live, {
      tree: {
        stories: [{ card_id: "s1", subtasks: ["t1", { card_id: "t2" }] }, { card_id: "s2", subtasks: [] }],
        subtasks: [
          { card_id: "t1", phases: [] }, { card_id: "t2", phases: [] }, { card_id: "t3", story_id: "s2", phases: [] },
          { card_id: "t4", phases: [] }, { card_id: "integrate", phases: [] }
        ]
      },
      rows: [
        { card_id: "t1", status: "running" }, { card_id: "t1", status: "started" },
        { card_id: "t2", status: "parked" }, { card_id: "t2", status: "stopped" },
        { card_id: "t3", status: "escalated" }, { card_id: "t3", status: "failed" },
        { card_id: "t4", status: "done" },
        { card_id: "t4", status: "queued" }, { card_id: "t4" },
        { card_id: "s1", status: "running" },
        { card_id: "integrate", status: "running" },
        { card_id: "bases", status: "running" },
        { card_id: "zz", status: "running" },
        null, "x"
      ]
    })
  }

  function counts(r) {
    return [r.running, r.parked, r.escalated, r.done, r.pending, r.total].join(",")
  }

  function test_rollup_milestone() {
    var r = Runs.rollup([rollupRun("r1", "started", true)], { id: "m1" })
    compare(Object.keys(r).sort().join(","), "done,escalated,parked,pending,running,total")
    // story row s1, synthetic integrate/bases, unknown zz and junk rows are excluded
    compare(counts(r), "2,2,2,1,2,9")

    var odd = mkRun("r2", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "RUNNING" }, { card_id: "t1", status: "Done" }, { card_id: "t1", status: 5 }]
    })
    compare(counts(Runs.rollup([odd], { id: "m1" })), "0,0,0,0,3,3", "status match is exact")
  }

  function test_rollup_story_membership() {
    var runs = [rollupRun("r1", "started", true)]
    compare(counts(Runs.rollup(runs, { id: "s1" })), "2,2,0,0,0,4", "string and {card_id} entries")
    compare(counts(Runs.rollup(runs, { id: "s2" })), "0,0,2,0,0,2", "story_id membership")
  }

  function test_rollup_uses_winning_run_only() {
    var winner = mkRun("live", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "running" }]
    })
    var loser = mkRun("old", "done", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "done" }, { card_id: "t1", status: "done" }]
    })
    compare(counts(Runs.rollup([loser, winner], { id: "m1" })), "1,0,0,0,0,1", "milestone")
    compare(counts(Runs.rollup([loser, winner], { id: "t1" })), "1,0,0,0,0,1", "subtask")

    var older = mkRun("older", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1" }] },
      rows: [{ card_id: "t1", status: "escalated" }]
    })
    compare(counts(Runs.rollup([loser, older], { id: "m1" })), "0,0,0,2,0,2", "all finished: newest wins")
  }

  function test_rollup_subtask_card() {
    var runs = [rollupRun("r1", "started", true)]
    compare(counts(Runs.rollup(runs, { id: "t1" })), "2,0,0,0,0,2")
    compare(counts(Runs.rollup(runs, { id: "t4" })), "0,0,0,1,2,3")
    compare(counts(Runs.rollup(runs, { id: "integrate" })), "0,0,0,0,0,0", "synthetic card")

    var proto = mkRun("p", "started", true, {
      tree: { stories: [{ card_id: "__proto__", subtasks: ["constructor"] }],
              subtasks: [{ card_id: "constructor" }, { card_id: "toString" }] },
      rows: [{ card_id: "constructor", status: "done" }, { card_id: "toString", status: "running" }]
    })
    compare(counts(Runs.rollup([proto], { id: "constructor" })), "0,0,0,1,0,1", "constructor subtask")
    compare(counts(Runs.rollup([proto], { id: "__proto__" })), "0,0,0,1,0,1", "__proto__ story")
    compare(counts(Runs.rollup([proto], { id: "valueOf" })), "0,0,0,0,0,0", "absent valueOf")
  }

  function test_rollup_rows_only_not_brd() {
    var runs = [rollupRun("r1", "started", true)]
    var card = { id: "s1", status: "done", children: ["t1", "t2", "t9"], counts: { done: 9 } }
    compare(counts(Runs.rollup(runs, card)), "2,2,0,0,0,4", "brd status and children ignored")
    compare(counts(Runs.rollup(runs, { id: "s9", status: "in_progress" })), "0,0,0,0,0,0", "untouched card")

    var garbage = [[undefined, { id: "m1" }], [null, { id: "m1" }], ["x", { id: "m1" }], [runs, null],
                   [runs, "m1"], [runs, {}], [runs, { id: "" }], [runs, { id: 5 }], [runs, []]]
    for (var i = 0; i < garbage.length; i++) {
      compare(counts(Runs.rollup(garbage[i][0], garbage[i][1])), "0,0,0,0,0,0", "garbage " + i)
    }

    var junk = [{ id: "j", status: "started", lease: { live: true }, milestone_id: "m1",
                  tree: { stories: "x", subtasks: [null, 5] }, rows: [{ card_id: "t1", status: "running" }] }]
    compare(counts(Runs.rollup(junk, { id: "m1" })), "0,0,0,0,0,0", "junk tree")
  }

  // ---- 1.2: attention ---------------------------------------------------------------------

  function test_attention() {
    var liveRun = mkRun("run", "started", true)
    var dead = mkRun("dead", "started", false)
    var noLease = mkRun("nl", "started", null)
    var parked = mkRun("p", "stopped", null)
    var esc = mkRun("e", "escalated", null)
    var done = mkRun("d", "done", null)
    var canc = mkRun("c", "cancelled", null)
    var unk = mkRun("u", "weird", true)
    var list = [liveRun, esc, parked, dead, done, canc, unk, noLease, null, "x"]
    var out = Runs.attention(list)
    compare(out.length, 3)
    compare(out[0] === esc, true, "same object, input order")
    compare(out[1] === dead, true)
    compare(out[2] === noLease, true)
    compare(list.length, 10, "input not modified")
    compare(Runs.attention([]).length, 0)

    var bad = [undefined, null, "x", 5, {}, { length: 1, 0: esc }]
    for (var i = 0; i < bad.length; i++) {
      var r = Runs.attention(bad[i])
      compare(Array.isArray(r), true, "garbage " + i)
      compare(r.length, 0, "garbage " + i)
    }
  }

  // ---- 1.2: escalation reason -------------------------------------------------------------

  function test_escalation_reason_detail() {
    var tree = { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "spec", status: "done", detail: "fine" }] },
      { card_id: "t2", phases: [{ name: "plan", status: "done" },
                                { name: "implement", status: "failed", detail: "  tests red after 3 attempts  " }] },
      { card_id: "t3", phases: [{ name: "review", status: "failed", detail: "second failure" }] }
    ] }
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: tree })), "tests red after 3 attempts",
            "first failed phase, trimmed")

    var fromAttempt = { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "verify", status: "failed", detail: "  ",
      attempts: [{ detail: "first" }, { detail: "second" }, { detail: "" }, null] }] }] }
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: fromAttempt })), "second",
            "last attempt that has a detail")

    var numeric = { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "x", status: "failed", detail: 42 }] }] }
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: numeric })), "42", "detail coerced with String")
  }

  function test_escalation_reason_fallbacks() {
    var noDetail = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "review", status: "failed",
                                                                  attempts: [{}, { detail: "" }] }] }] },
      rows: [{ card_id: "t1", phase: "other" }]
    })
    compare(Runs.escalationReason(noDetail), "escalated at review")

    var noFailed = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done" },
                                                                { name: "plan", status: "FAILED" }] }] },
      rows: [{ card_id: "t1", phase: "spec" }, { card_id: "t2", phase: "implement" },
             { card_id: "t3", phase: "" }, { card_id: "t4" }, null]
    })
    compare(Runs.escalationReason(noFailed), "escalated at implement", "last row phase; status match is exact")

    var nameless = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ status: "failed" }] }] },
      rows: [{ card_id: "t1", phase: "spec" }]
    })
    compare(Runs.escalationReason(nameless), "escalated", "nameless failed phase")

    compare(Runs.escalationReason(mkRun("r", "escalated", null)), "escalated", "nothing at all")

    var bad = [undefined, null, "x", 5, [], {}, { tree: "x", rows: "y" },
               { tree: { subtasks: [null, { phases: "x" }, { phases: [null, 5] }] }, rows: [null] }]
    for (var i = 0; i < bad.length; i++) compare(Runs.escalationReason(bad[i]), "escalated", "garbage " + i)
  }
}
