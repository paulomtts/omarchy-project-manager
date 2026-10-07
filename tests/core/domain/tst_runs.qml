// tests/core/domain/tst_runs.qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

// normalizeRun's input is built from tests/fixtures/am/ via amRun.
TestCase {
  name: "DomainRuns"

  // One am run as RunStore hands it to normalizeRun, fresh on every call: the
  // fixture's `am runs` row (runs.json's entry with the same run id, else the
  // fixture's own _am_runs_row) without `status`, and the fixture's `am status`
  // data.
  function amRun(name) {
    var fixture = F.load(name)
    var runs = F.load("runs.json").data.runs
    var row = fixture._am_runs_row
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].id === fixture.data.run.id) row = runs[i]
    }
    delete row.status
    return { row: row, status: fixture.data }
  }

  // The four captures, normalized, in this order: started, done, escalated,
  // done-integrate.
  function fixtureRuns() {
    return [Runs.normalizeRun(amRun("status-started.json")), Runs.normalizeRun(amRun("status-done.json")),
            Runs.normalizeRun(amRun("status-escalated.json")), Runs.normalizeRun(amRun("status-done-integrate.json"))]
  }

  function checkDefaults(r, label) {
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,repo_dir,requests,rows,started_at,status,tree,workflow", label)
    compare(r.started_at, "", label)
    compare(r.id, "", label)
    compare(r.repo_dir, "", label)
    compare(r.milestone_id, "", label)
    compare(r.status, "", label)
    compare(r.base_branch, "", label)
    compare(r.branch_prefix, "", label)
    compare(r.lease, null, label)
    compare(Array.isArray(r.rows), true, label)
    compare(r.rows.length, 0, label)
    compare(Array.isArray(r.tree.stories), true, label)
    compare(r.tree.stories.length, 0, label)
    compare(Array.isArray(r.tree.subtasks), true, label)
    compare(r.tree.subtasks.length, 0, label)
  }

  function test_normalize_status_prefers_am_status() {
    // synthetic: the row's and am status's run statuses edited to disagree
    var raw = amRun("status-started.json")
    raw.row.status = "stopped"
    raw.status.run.status = "done"
    compare(Runs.normalizeRun(raw).status, "done")

    // synthetic: a bare am runs row
    compare(Runs.normalizeRun({ row: { id: "r1", status: "stopped" } }).status, "stopped")

    // synthetic: am status without its run
    var noRun = amRun("status-started.json")
    noRun.row.status = "escalated"
    delete noRun.status.run
    compare(Runs.normalizeRun(noRun).status, "escalated")

    // synthetic: an empty am status run status. It is not fresher detail: fall back to the row.
    var blank = amRun("status-started.json")
    blank.row.status = "stopped"
    blank.status.run.status = ""
    compare(Runs.normalizeRun(blank).status, "stopped")
  }

  function test_normalize_ids_fallback_and_coercion() {
    // synthetic: bare am runs rows and am status runs, one or two fields each
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
    // synthetic: am status without control
    var noControl = amRun("status-started.json")
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).lease, null, "no control")

    // synthetic: the capture's control replaced by each malformed shape
    var cases = [
      { label: "empty control", control: {} },
      { label: "null control", control: null },
      { label: "null lease", control: { lease: null } },
      { label: "string lease", control: { lease: "yes" } },
      { label: "array lease", control: { lease: [] } }
    ]
    for (var i = 0; i < cases.length; i++) {
      var raw = amRun("status-started.json")
      raw.status.control = cases[i].control
      compare(Runs.normalizeRun(raw).lease, null, cases[i].label)
    }

    // synthetic: a bare am runs row
    compare(Runs.normalizeRun({ row: { id: "r1", status: "started" } }).lease, null, "no status at all")
  }

  function test_normalize_lease_live_strict() {
    // synthetic: the capture's lease replaced by empty, null, string and numeric values
    var empty = amRun("status-started.json")
    empty.status.control.lease = {}
    var e = Runs.normalizeRun(empty).lease
    compare(e.live, false)
    compare(e.accepting, false)
    compare(e.pid, "")
    compare(e.host, "")
    compare(e.heartbeat_at, "")

    var nulls = amRun("status-started.json")
    nulls.status.control.lease = { pid: null, host: null, heartbeat_at: null, live: null, accepting: null }
    var n = Runs.normalizeRun(nulls).lease
    compare(n.pid, "", "null pid")
    compare(n.host, "", "null host")
    compare(n.heartbeat_at, "", "null heartbeat_at")
    compare(n.live, false, "null live")
    compare(n.accepting, false, "null accepting")

    var stringy = amRun("status-started.json")
    stringy.status.control.lease = { live: "true", accepting: "true" }
    compare(Runs.normalizeRun(stringy).lease.live, false)
    compare(Runs.normalizeRun(stringy).lease.accepting, false)

    var numeric = amRun("status-started.json")
    numeric.status.control.lease = { live: 1, accepting: 1 }
    compare(Runs.normalizeRun(numeric).lease.live, false)
    compare(Runs.normalizeRun(numeric).lease.accepting, false)
  }

  function test_normalize_tree_garbage() {
    // synthetic: am status with only a run
    var bare = Runs.normalizeRun({ status: { run: { status: "started" } } })
    compare(Array.isArray(bare.rows), true)
    compare(bare.rows.length, 0)
    compare(bare.tree.stories.length, 0)
    compare(bare.tree.subtasks.length, 0)

    // synthetic: rows, stories and a top-level subtasks that are not arrays
    var raw = amRun("status-started.json")
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

    // synthetic: rows as a string
    var strRows = amRun("status-started.json")
    strRows.status.rows = "x"
    compare(Runs.normalizeRun(strRows).rows.length, 0)

    // synthetic: a top-level subtasks list, which am never prints
    var topLevel = amRun("status-started.json")
    topLevel.status.subtasks = [{ card_id: "zz", phases: [] }]
    var t = Runs.normalizeRun(topLevel)
    compare(t.tree.subtasks.length, 8, "a top-level subtasks is ignored")
    for (var i = 0; i < t.tree.subtasks.length; i++) verify(t.tree.subtasks[i].card_id !== "zz", "no zz at " + i)

    // synthetic: garbage elements in place of the capture's stories and rows
    var junk = amRun("status-started.json")
    junk.status.stories = [null, 5, "s", [], { card_id: "s9" }, { card_id: "s8", subtasks: "x" },
                           { card_id: "s7", subtasks: [null, 3, { card_id: 4 }, { card_id: "t7" }] }]
    junk.status.rows = [null, "r", 7, {}, { story: 1, subtask: "t7", phase: [], attempt: "2", state: {} }]
    var g = Runs.normalizeRun(junk)
    compare(cardIds(g.tree.stories), "s9,s8,s7", "only object stories are kept")
    compare(JSON.stringify(g.tree.stories[0].subtasks), "[]", "missing subtasks")
    compare(JSON.stringify(g.tree.stories[1].subtasks), "[]", "subtasks not an array")
    compare(JSON.stringify(g.tree.stories[2].subtasks), "[\"t7\"]", "only string ids of object subtasks")
    compare(g.tree.subtasks.length, 2, "the two object subtasks of s7")
    compare(g.tree.subtasks[0].card_id, 4)
    compare(g.tree.subtasks[0].story_id, "s7")
    compare(g.tree.subtasks[1].card_id, "t7")
    compare(g.tree.subtasks[1].story_id, "s7")
    compare(g.rows.length, 2, "only object rows are kept")
    compare(JSON.stringify(g.rows[0]), JSON.stringify({ story_id: "", card_id: "", phase: "", attempt: null, status: "" }))
    compare(JSON.stringify(g.rows[1]), JSON.stringify({ story_id: "", card_id: "t7", phase: "", attempt: null, status: "" }))
  }

  function test_normalize_garbage() {
    // synthetic: garbage in place of a run
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

  // ---- 2.1: normalizeRun over the am captures ----------------------------------------------

  function test_normalize_fixture_counts() {
    var expected = [
      ["status-started.json", 4, 8, 44],
      ["status-done.json", 4, 10, 140],
      ["status-escalated.json", 3, 4, 40],
      ["status-done-integrate.json", 3, 2, 28]
    ]
    for (var i = 0; i < expected.length; i++) {
      var r = Runs.normalizeRun(amRun(expected[i][0]))
      compare(r.tree.stories.length, expected[i][1], expected[i][0] + " stories")
      compare(r.tree.subtasks.length, expected[i][2], expected[i][0] + " subtasks")
      compare(r.rows.length, expected[i][3], expected[i][0] + " rows")
    }
  }

  function test_normalize_scalars_from_fixture() {
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,repo_dir,requests,rows,started_at,status,tree,workflow")
    compare(r.id, "20261005T021400Z-837c4431")
    compare(r.repo_dir, "/home/user/Code/omarchy-project-manager")
    compare(r.milestone_id, "837c4431-7a24-4531-96a8-881698ea8c5e", "only the am runs row carries it")
    compare(r.status, "started")
    compare(r.workflow, "milestone")
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "dsp")
    compare(r.started_at, "2026-10-05 02:14:00.590972+00:00")
    compare(Object.keys(r.lease).sort().join(","), "accepting,heartbeat_at,host,live,pid", "acquired_at is not kept")
    compare(r.lease.pid, 3736962)
    compare(r.lease.host, "mtts-desktop")
    compare(r.lease.heartbeat_at, "2026-10-05T03:30:22.281942+00:00")
    compare(r.lease.accepting, true)
    compare(r.lease.live, true)
    compare(Array.isArray(r.requests), true)
    compare(r.requests.length, 0)
  }

  function test_normalize_stories_are_id_lists() {
    var raw = amRun("status-started.json")
    var am = raw.status.stories[1]
    var s = Runs.normalizeRun(raw).tree.stories[1]
    compare(s.card_id, "d3d879b9-cb74-41ca-9a37-63f477de9711")
    compare(JSON.stringify(s.subtasks), JSON.stringify(["a19ca446-659e-4735-86ed-5a583c1730bf",
                                                        "299ec9c0-b935-4c44-a7a0-982a104cbfe5",
                                                        "fdb5feb1-0907-40b2-9937-d9b4cc2875f0"]))
    for (var i = 0; i < s.subtasks.length; i++) compare(typeof s.subtasks[i], "string", "id " + i)
    compare(s.title, am.title)
    compare(s.level, am.level)
    compare(s.status, am.status)
    compare(s.tip_branch, am.tip_branch)
    compare(Object.keys(s).sort().join(","), "card_id,level,status,subtasks,tip_branch,title")
  }

  function test_normalize_subtasks_flatten_with_story_id() {
    var raw = amRun("status-started.json")
    var r = Runs.normalizeRun(raw)
    var ids = [], storyIds = []
    for (var i = 0; i < raw.status.stories.length; i++) {
      var story = raw.status.stories[i]
      for (var j = 0; j < story.subtasks.length; j++) {
        ids.push(story.subtasks[j].card_id)
        storyIds.push(story.card_id)
      }
    }
    compare(cardIds(r.tree.subtasks), ids.join(","), "am's flattened order")
    for (var k = 0; k < r.tree.subtasks.length; k++) compare(r.tree.subtasks[k].story_id, storyIds[k], "story_id " + k)
    var open = r.tree.subtasks[3]
    compare(open.card_id, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(open.story_id, "d3d879b9-cb74-41ca-9a37-63f477de9711")
    compare(Object.keys(open).sort().join(","), "base_branch,branch,card_id,phases,status,story_id,worktree_path")
    compare(open.phases[1].name, "explore")
    compare(open.phases[1].attempts[0].n, 1)
  }

  function test_normalize_rows_renamed() {
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(Object.keys(r.rows[0]).sort().join(","), "attempt,card_id,phase,status,story_id")
    compare(r.rows[0].story_id, "1c665cfd-9a72-4a9d-a539-4c83f0f6ddc1")
    compare(r.rows[0].card_id, "5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff")
    compare(r.rows[0].phase, "worktree")
    compare(r.rows[0].attempt, null)
    compare(r.rows[0].status, "done")
    compare(r.rows[43].story_id, "d3d879b9-cb74-41ca-9a37-63f477de9711")
    compare(r.rows[43].card_id, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(r.rows[43].phase, "explore")
    compare(r.rows[43].attempt, 1)
    compare(r.rows[43].status, "started")
  }

  function test_normalize_integrate_story_kept_resolver_dropped() {
    var r = Runs.normalizeRun(amRun("status-done-integrate.json"))
    var integrate = r.tree.stories[2]
    compare(integrate.card_id, "integrate")
    compare(JSON.stringify(integrate.subtasks), JSON.stringify(["b429248c-c69e-4df5-8f7d-52776253ea14"]))
    compare(integrate.status, "done")
    for (var i = 0; i < r.tree.subtasks.length; i++) {
      verify(r.tree.subtasks[i].story_id !== "integrate", "no subtask of integrate at " + i)
      verify(r.tree.subtasks[i].card_id !== "b429248c-c69e-4df5-8f7d-52776253ea14", "no resolver subtask at " + i)
    }
    compare(r.rows.length, 28, "the two resolver rows are dropped")
    for (var j = 0; j < r.rows.length; j++) verify(r.rows[j].story_id !== "integrate", "no integrate row at " + j)
  }

  function test_normalize_base_rows_kept() {
    // synthetic: a bases story, which no capture contains
    var raw = amRun("status-done-integrate.json")
    var baseId = "base-2f88f774-d2b6-4c8d-adc1-6ac9eb978017"
    raw.status.stories.push({ card_id: "bases", title: "Bases", level: 0, status: "done", tip_branch: "m3-bases",
                              subtasks: [{ card_id: baseId, branch: "m3-" + baseId, base_branch: "main", status: "done",
                                           worktree_path: "/tmp/m3-bases", phases: [] }] })
    raw.status.rows.push({ story: "bases", subtask: baseId, phase: "verify", attempt: null, state: "done" })
    var r = Runs.normalizeRun(raw)
    compare(r.tree.stories.length, 4)
    compare(r.tree.stories[3].card_id, "bases")
    compare(JSON.stringify(r.tree.stories[3].subtasks), JSON.stringify([baseId]))
    compare(r.tree.subtasks.length, 2, "the base subtask is not a tree subtask")
    for (var i = 0; i < r.tree.subtasks.length; i++) verify(r.tree.subtasks[i].card_id !== baseId, "no base subtask at " + i)
    compare(r.rows.length, 29, "28 real rows and the base row")
    var last = r.rows[28]
    compare(last.story_id, "bases")
    compare(last.card_id, baseId)
    compare(last.phase, "verify")
    compare(last.attempt, null)
    compare(last.status, "done")
    for (var j = 0; j < r.rows.length; j++) verify(r.rows[j].story_id !== "integrate", "resolver rows still dropped at " + j)
  }

  function test_normalize_copies_never_am_objects() {
    var raw = amRun("status-started.json")
    var before = JSON.stringify(raw)
    var r = Runs.normalizeRun(raw)
    verify(r.tree.stories[1] !== raw.status.stories[1], "story is a copy")
    verify(r.tree.subtasks[3] !== raw.status.stories[1].subtasks[1], "subtask is a copy")
    verify(r.tree.subtasks[3].phases !== raw.status.stories[1].subtasks[1].phases, "phases are a copy")
    verify(r.tree.subtasks[3].phases[1].attempts[0] !== raw.status.stories[1].subtasks[1].phases[1].attempts[0],
           "attempt is a copy")
    verify(r.rows[0] !== raw.status.rows[0], "row is a copy")
    r.tree.stories[1].title = "changed"
    r.tree.subtasks[3].phases[1].attempts[0].status = "changed"
    r.rows[0].phase = "changed"
    r.tree.stories[1].subtasks[0] = "changed"
    compare(JSON.stringify(raw), before, "changing the output leaves the input unchanged")

    var later = amRun("status-started.json")
    var out = Runs.normalizeRun(later)
    var outBefore = JSON.stringify(out)
    later.status.stories[1].title = "later"
    later.status.stories[1].subtasks[1].phases[1].attempts[0].status = "later"
    later.status.stories[1].subtasks.push({ card_id: "later" })
    later.status.rows[0].phase = "later"
    compare(JSON.stringify(out), outBefore, "changing the input after the call leaves the output unchanged")
  }

  function test_normalize_own_proto_key_never_sets_prototype() {
    // synthetic: an own __proto__ key, which no capture contains
    function withProto(o) { return JSON.parse('{"__proto__": {"x": 1}, ' + JSON.stringify(o).slice(1)) }
    var raw = amRun("status-started.json")
    var amStory = raw.status.stories[1]
    var phase = withProto(amStory.subtasks[1].phases[1])
    var subtask = withProto(amStory.subtasks[1])
    subtask.phases[1] = phase
    var story = withProto(amStory)
    story.subtasks[1] = subtask
    raw.status.stories[1] = story
    verify(Object.prototype.hasOwnProperty.call(story, "__proto__"), "the input carries an own __proto__ key")

    var r = Runs.normalizeRun(raw)
    var copies = [["story", r.tree.stories[1]], ["subtask", r.tree.subtasks[3]], ["phase", r.tree.subtasks[3].phases[1]]]
    for (var i = 0; i < copies.length; i++) {
      compare(Object.getPrototypeOf(copies[i][1]) === Object.prototype, true, copies[i][0] + " prototype")
      compare(copies[i][1].x, undefined, copies[i][0] + " x")
    }
    compare(r.tree.subtasks[3].card_id, "299ec9c0-b935-4c44-a7a0-982a104cbfe5", "the rest is copied")
    compare(r.tree.subtasks[3].phases[1].name, "explore")
  }

  function test_fixture_current_phase_and_default_attempt() {
    var expected = [
      ["explore", "299ec9c0-b935-4c44-a7a0-982a104cbfe5/explore/1"],
      ["", "22153f5f-9632-4b5f-a7dd-664c39d89e5c/review/1"],
      ["", "eb8b1851-8245-45c3-9a29-d1fcefaad0b9/review/1"],
      ["", "5d5114f9-8d86-4712-95f3-87dd9d56feef/review/1"]
    ]
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      compare(Runs.currentPhase(runs[i]), expected[i][0], "currentPhase " + runs[i].id)
      compare(at(Runs.defaultAttempt(runs[i])), expected[i][1], "defaultAttempt " + runs[i].id)
    }
  }

  function test_fixture_card_run_state_and_runs_touching() {
    var runs = fixtureRuns()
    var open = Runs.cardRunState(runs, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(open.state, "running")
    compare(open.runId, "20261005T021400Z-837c4431")
    compare(open.dimmed, false)
    compare(open.phase, "explore")
    compare(open.attempt, 1)
    var escalated = Runs.cardRunState(runs, "eb8b1851-8245-45c3-9a29-d1fcefaad0b9")
    compare(escalated.state, "escalated")
    compare(escalated.runId, "20261005T032543Z-bcc4e411")
    compare(escalated.dimmed, true)
    compare(escalated.phase, "review")
    compare(escalated.attempt, 1)

    var touchingOpen = Runs.runsTouching(runs, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(touchingOpen.length, 1)
    verify(touchingOpen[0] === runs[0], "the started run")
    var touchingReal = Runs.runsTouching(runs, "5d5114f9-8d86-4712-95f3-87dd9d56feef")
    compare(touchingReal.length, 1)
    verify(touchingReal[0] === runs[3], "the done-integrate run")
    var touchingStory = Runs.runsTouching(runs, "b429248c-c69e-4df5-8f7d-52776253ea14")
    compare(touchingStory.length, 1, "through its real story only")
    verify(touchingStory[0] === runs[3], "the done-integrate run, through its real story")
  }

  function test_fixture_run_tree_grouping() {
    var done = amRun("status-done.json")
    var t = Runs.runTree(Runs.normalizeRun(done))
    var sizes = [2, 3, 1, 4]
    compare(t.stories.length, 4)
    compare(JSON.stringify(t.synthetic), "[]")
    for (var i = 0; i < t.stories.length; i++) {
      var am = done.status.stories[i]
      compare(t.stories[i].card_id, am.card_id, "story " + i)
      compare(t.stories[i].other, false, "story " + i + " is not Other")
      compare(t.stories[i].subtasks.length, sizes[i], "story " + i + " size")
      for (var j = 0; j < t.stories[i].subtasks.length; j++)
        compare(t.stories[i].subtasks[j].card_id, am.subtasks[j].card_id, "story " + i + " subtask " + j)
    }

    var it = Runs.runTree(Runs.normalizeRun(amRun("status-done-integrate.json")))
    compare(it.stories.length, 2)
    compare(it.stories[0].subtasks.length, 1)
    compare(it.stories[1].subtasks.length, 1)
    compare(JSON.stringify(it.synthetic), JSON.stringify([{ id: "integrate", label: "Integrate", status: "done" }]))
    for (var k = 0; k < it.stories.length; k++) compare(it.stories[k].other, false, "no Other group " + k)
  }

  // The node with this card id in any group of a runTree result, else null.
  function treeNode(tree, cardId) {
    for (var i = 0; i < tree.stories.length; i++) {
      var subtasks = tree.stories[i].subtasks
      for (var j = 0; j < subtasks.length; j++) {
        if (subtasks[j].card_id === cardId) return subtasks[j]
      }
    }
    return null
  }

  // "phase/attempt" a tree node opens on.
  function opensOn(node) { return node === null ? "null" : node.currentPhase + "/" + node.currentAttempt }

  function test_fixture_run_tree_open_attempt() {
    var done = Runs.runTree(Runs.normalizeRun(amRun("status-done.json")))
    var count = 0
    for (var i = 0; i < done.stories.length; i++) {
      for (var j = 0; j < done.stories[i].subtasks.length; j++) {
        var node = done.stories[i].subtasks[j]
        compare(node.status, "done", node.card_id)
        compare(node.phases.length, 14, node.card_id + " phases")
        compare(node.attempts.length, 7, node.card_id + " attempts")
        compare(opensOn(node), "review/1", node.card_id + ": the last phase with a numbered attempt, past verify and mark_done")
        count++
      }
    }
    compare(count, 10, "every done subtask is a node")

    var started = Runs.runTree(Runs.normalizeRun(amRun("status-started.json")))
    var expected = [
      ["5eb7ec0c-9bb1-41cd-a0ca-506b4ab4f4ff", "review/1"],
      ["45cc9067-d6b3-441f-b8d2-6602a81311d2", "review/1"],
      ["a19ca446-659e-4735-86ed-5a583c1730bf", "review/1"],
      ["299ec9c0-b935-4c44-a7a0-982a104cbfe5", "explore/1"],
      ["fdb5feb1-0907-40b2-9937-d9b4cc2875f0", "/0"],
      ["66a6b6c0-5032-4598-b80c-0afb0d0d46b5", "/0"],
      ["dfc0ac87-978b-4419-87c2-61f10b9d0cd1", "/0"],
      ["46141e11-da16-4aa2-8e1a-10e0e23e6980", "/0"]
    ]
    for (var k = 0; k < expected.length; k++)
      compare(opensOn(treeNode(started, expected[k][0])), expected[k][1], "started run " + expected[k][0])

    var escalated = Runs.runTree(Runs.normalizeRun(amRun("status-escalated.json")))
    var expectedEscalated = [
      ["c5e41536-7e1b-448b-aa2d-55e9550e63b2", "review/1"],
      ["231a23cc-91bc-4516-924d-5b19476d5237", "review/1"],
      ["eb8b1851-8245-45c3-9a29-d1fcefaad0b9", "review/1"],
      ["ca31fde7-d22a-43a3-b3da-b1d2d6f9f41e", "/0"]
    ]
    for (var e = 0; e < expectedEscalated.length; e++)
      compare(opensOn(treeNode(escalated, expectedEscalated[e][0])), expectedEscalated[e][1], "escalated run " + expectedEscalated[e][0])
  }

  function test_fixture_run_tree_started_deterministic_phase() {
    var raw = amRun("status-started.json")
    var subtask = null
    for (var i = 0; i < raw.status.stories.length; i++) {
      var list = raw.status.stories[i].subtasks
      for (var j = 0; j < list.length; j++) {
        if (list[j].card_id === "299ec9c0-b935-4c44-a7a0-982a104cbfe5") subtask = list[j]
      }
    }
    verify(subtask !== null, "the started subtask is in the capture")
    compare(subtask.phases.length, 2)
    compare(subtask.phases[1].name + ":" + subtask.phases[1].status, "explore:started")
    // synthetic: a deterministic phase in flight after a finished agent phase -- no capture has one
    subtask.phases[1].status = "done"
    var added = { name: "mark_in_progress", kind: "deterministic", status: "started", started_at: "", ended_at: null, detail: null, attempts: [] }
    compare(Object.keys(added).sort().join(","), Object.keys(subtask.phases[0]).sort().join(","), "same keys as its neighbours")
    subtask.phases.push(added)

    var node = treeNode(Runs.runTree(Runs.normalizeRun(raw)), "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(opensOn(node), "mark_in_progress/0", "a started phase wins over an earlier numbered one, attempt 0 without attempts")
  }

  function test_state_running() {
    compare(Runs.runState({ status: "started", lease: { live: true } }), "running")
    compare(Runs.runState(Runs.normalizeRun(amRun("status-started.json"))), "running")
  }

  function test_state_dead_not_live() {
    compare(Runs.runState({ status: "started", lease: { live: false } }), "dead")

    // synthetic: the capture's lease edited to not live
    var raw = amRun("status-started.json")
    raw.status.control.lease.live = false
    compare(Runs.runState(Runs.normalizeRun(raw)), "dead")

    // synthetic: the capture's lease live as a string. A sloppy "true" string is not liveness.
    var stringy = amRun("status-started.json")
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
    // synthetic: a bare am runs row
    compare(Runs.runState(Runs.normalizeRun({ row: { id: "r1", status: "started" } })), "dead")

    // synthetic: am status without control
    var noLease = amRun("status-started.json")
    delete noLease.status.control
    compare(Runs.runState(Runs.normalizeRun(noLease)), "dead")
  }

  function test_state_terminal_and_parked() {
    var expected = [
      ["stopped", "parked"],
      ["escalated", "escalated"],
      ["cancelled", "cancelled"],
      ["canceled", "cancelled"],
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
    var statuses = ["weird", "", "stale", "STARTED", "Done", "running", "dead",
                    "Canceled", "CANCELED", " canceled", "cancel", "constructor", "__proto__", 5, null]
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

  // The two spellings am gives a cancelled run.
  function cancelSpellings() { return ["cancelled", "canceled"] }

  // The status-done.json run, normalized, with am's run status set to spelling.
  // Its control.lease is null, so no Integrate reason interferes.
  function cancelledRun(spelling) {
    // status-done.json copy, run.status set to spelling (cancelled or canceled)
    var raw = amRun("status-done.json")
    raw.status.run.status = spelling
    return Runs.normalizeRun(raw)
  }

  function test_fixture_cancel_spellings_run_state() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      compare(run.status, spellings[i], spellings[i] + ": normalizeRun keeps am's spelling")
      compare(Runs.runState(run), "cancelled", spellings[i] + ": runState")
    }
  }

  // A cancelled run in either spelling is found by its state name and sits in
  // no chip but `all`.
  function test_fixture_cancel_spellings_filters_and_search() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      var counts = Runs.runFilterCounts([run])
      compare([counts.attention, counts.live, counts.parked, counts.all].join(","), "0,0,0,1",
              spellings[i] + ": chip counts")
      compare(Runs.searchRuns([run], "cancelled").length, 1, spellings[i] + ": found by its state name")
      compare(Runs.searchRuns([run], "unknown").length, 0, spellings[i] + ": not unknown")
    }
  }

  // A newer cancelled run, in either spelling, never outranks an older running
  // run for a card; alone, it leaves the card with no run state, dimmed.
  function test_card_run_state_cancel_spellings() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var cancelled = mkRun("rx", spellings[i], null, { started_at: "2026-10-05 10:00:00+00:00" })
      var running = mkRun("rr", "started", true, { started_at: "2026-10-04 10:00:00+00:00" })
      var both = Runs.cardRunState([cancelled, running], "m1")
      compare(both.state + "/" + both.runId + "/" + both.dimmed, "running/rr/false",
              spellings[i] + ": beside an older running run")
      var alone = Runs.cardRunState([cancelled], "m1")
      compare(alone.state + "/" + alone.runId + "/" + alone.dimmed, "none/rx/true", spellings[i] + ": alone")
    }
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

    // synthetic: a bare am runs row among hand-built normalized runs
    var withBlank = [good, mkRun("blank", "started", true, { milestone_id: "" }),
                     Runs.normalizeRun({ row: { id: "z", status: "started" } })]
    var ids = [null, undefined, "", 0, 5, {}, []]
    for (var k = 0; k < ids.length; k++) checkNone(Runs.cardRunState(withBlank, ids[k]), "cardId " + k)
  }

  // ---- 2.2: rollups -----------------------------------------------------------------------

  function counts(r) {
    return [r.running, r.parked, r.escalated, r.done, r.pending, r.total].join(",")
  }

  function test_rollup_fixture_milestones() {
    var cases = [
      ["status-started.json", "837c4431-7a24-4531-96a8-881698ea8c5e", "1,0,0,3,4,8"],
      ["status-done.json", "cb11063d-78b9-4537-8569-fb5c249519f8", "0,0,0,10,0,10"],
      ["status-escalated.json", "bcc4e411-504c-48f4-8712-198a5c04ec8b", "0,0,1,2,1,4"],
      ["status-escalated-integrate.json", "5a2d70ff-b0c8-4bb8-8a87-1cb2c679a754", "0,0,0,2,0,2"],
      ["status-done-integrate.json", "2f6878ac-7e83-449f-9b6c-3b1f65acd30e", "0,0,0,2,0,2"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var name = cases[i][0]
      var run = Runs.normalizeRun(amRun(name))
      compare(run.milestone_id, cases[i][1], name + " milestone id")
      var r = Runs.rollup([run], { id: run.milestone_id })
      compare(Object.keys(r).sort().join(","), "done,escalated,parked,pending,running,total", name)
      compare(counts(r), cases[i][2], name)
    }
  }

  function test_rollup_fixture_stories_and_subtasks() {
    var started = [Runs.normalizeRun(amRun("status-started.json"))]
    var done = [Runs.normalizeRun(amRun("status-done.json"))]
    var escalated = [Runs.normalizeRun(amRun("status-escalated.json"))]
    var doneIntegrate = [Runs.normalizeRun(amRun("status-done-integrate.json"))]
    var cases = [
      [started, "d3d879b9-cb74-41ca-9a37-63f477de9711", "1,0,0,1,1,3", "started: story"],
      [started, "299ec9c0-b935-4c44-a7a0-982a104cbfe5", "1,0,0,0,0,1", "started: subtask with 2 rows"],
      [done, "f03629a7-5912-4b36-82b2-12f3b567294a", "0,0,0,4,0,4", "done: story"],
      [done, "22153f5f-9632-4b5f-a7dd-664c39d89e5c", "0,0,0,1,0,1", "done: subtask with 14 rows"],
      [escalated, "3f5aadb9-67b1-49b9-aec5-fb0bf81e46f9", "0,0,1,0,0,1", "escalated: story"],
      [escalated, "eb8b1851-8245-45c3-9a29-d1fcefaad0b9", "0,0,1,0,0,1", "escalated: subtask with 12 rows"],
      [doneIntegrate, "b429248c-c69e-4df5-8f7d-52776253ea14", "0,0,0,1,0,1",
       "done-integrate: real story whose id the Integrate resolver carries"]
    ]
    for (var i = 0; i < cases.length; i++) {
      compare(counts(Runs.rollup(cases[i][0], { id: cases[i][1] })), cases[i][2], cases[i][3])
    }
  }

  function test_rollup_never_reads_rows() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    compare(run.milestone_id, "cb11063d-78b9-4537-8569-fb5c249519f8")
    var milestone = { id: run.milestone_id }
    compare(run.rows.length, 140, "rows are per attempt")
    compare(counts(Runs.rollup([run], milestone)), "0,0,0,10,0,10", "one count per subtask")

    // synthetic: every row of the normalized capture set to started
    for (var i = 0; i < run.rows.length; i++) run.rows[i].status = "started"
    compare(counts(Runs.rollup([run], milestone)), "0,0,0,10,0,10", "row status ignored")

    // synthetic: the normalized capture with no subtasks, its 140 rows kept
    run.tree.subtasks = []
    compare(run.rows.length, 140)
    compare(counts(Runs.rollup([run], milestone)), "0,0,0,0,0,0", "rows alone count nothing")
  }

  function test_rollup_bucket_mapping() {
    var cases = [
      ["running", "1,0,0,0,0,1"], ["started", "1,0,0,0,0,1"],
      ["parked", "0,1,0,0,0,1"], ["stopped", "0,1,0,0,0,1"],
      ["escalated", "0,0,1,0,0,1"], ["failed", "0,0,1,0,0,1"],
      ["done", "0,0,0,1,0,1"],
      ["pending", "0,0,0,0,1,1"], ["cancelled", "0,0,0,0,1,1"], ["queued", "0,0,0,0,1,1"],
      ["RUNNING", "0,0,0,0,1,1"], ["Done", "0,0,0,0,1,1"], ["", "0,0,0,0,1,1"],
      [5, "0,0,0,0,1,1"], [null, "0,0,0,0,1,1"]
    ]
    for (var i = 0; i < cases.length; i++) {
      // synthetic: milestone m1 with one subtask t1 in the given status
      var run = mkRun("r1", "started", true, {
        tree: { stories: [], subtasks: [{ card_id: "t1", status: cases[i][0], phases: [] }] }
      })
      compare(counts(Runs.rollup([run], { id: "m1" })), cases[i][1], "status " + JSON.stringify(cases[i][0]))
    }
    // synthetic: milestone m1 with one subtask t1 that has no status
    var missing = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [{ card_id: "t1", phases: [] }] } })
    compare(counts(Runs.rollup([missing], { id: "m1" })), "0,0,0,0,1,1", "missing status")
  }

  // synthetic: milestone m1; story s1 lists t1 (id string) and t2 ({card_id}); t3 belongs to s2
  // via story_id; t4 belongs to no story.
  function membershipRun(id, status, live) {
    return mkRun(id, status, live, {
      tree: {
        stories: [{ card_id: "s1", subtasks: ["t1", { card_id: "t2" }] }, { card_id: "s2", subtasks: [] }],
        subtasks: [
          { card_id: "t1", status: "started", phases: [] },
          { card_id: "t2", status: "stopped", phases: [] },
          { card_id: "t3", story_id: "s2", status: "failed", phases: [] },
          { card_id: "t4", status: "done", phases: [] }
        ]
      }
    })
  }

  function test_rollup_story_membership() {
    var runs = [membershipRun("r1", "started", true)]
    compare(counts(Runs.rollup(runs, { id: "s1" })), "1,1,0,0,0,2", "string and {card_id} entries")
    compare(counts(Runs.rollup(runs, { id: "s2" })), "0,0,1,0,0,1", "story_id membership")
    compare(counts(Runs.rollup(runs, { id: "m1" })), "1,1,1,1,0,4", "milestone counts every subtask")
    compare(counts(Runs.rollup(runs, { id: "t4" })), "0,0,0,1,0,1", "subtask card")
  }

  function test_rollup_excludes_non_real_subtasks() {
    // synthetic: garbage and synthetic-id subtasks beside one real t1; story s9 lists an unknown zz
    var run = mkRun("r1", "started", true, {
      tree: {
        stories: [{ card_id: "s9", subtasks: ["zz"] }],
        subtasks: [null, "x", 5, { card_id: "" }, { card_id: 7 },
                   { card_id: "integrate", status: "started" }, { card_id: "bases", status: "started" },
                   { card_id: "base-s1", status: "started" }, { card_id: "t1", status: "done", phases: [] }]
      }
    })
    compare(counts(Runs.rollup([run], { id: "m1" })), "0,0,0,1,0,1", "only t1 counts")
    compare(counts(Runs.rollup([run], { id: "integrate" })), "0,0,0,0,0,0", "integrate card")
    compare(counts(Runs.rollup([run], { id: "base-s1" })), "0,0,0,0,0,0", "base-* card")
    compare(counts(Runs.rollup([run], { id: "s9" })), "0,0,0,0,0,0", "story listing only an unknown id")
  }

  function test_rollup_uses_winning_run_only() {
    // synthetic: a live run of m1 (t1 started) and an older done run (t1, t2 done)
    var winner = mkRun("live", "started", true, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "started", phases: [] }] }
    })
    var loser = mkRun("old", "done", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "done", phases: [] },
                                      { card_id: "t2", status: "done", phases: [] }] }
    })
    compare(counts(Runs.rollup([loser, winner], { id: "m1" })), "1,0,0,0,0,1", "milestone")
    compare(counts(Runs.rollup([loser, winner], { id: "t1" })), "1,0,0,0,0,1", "subtask")

    // synthetic: two finished runs, newest first, no started_at; the older one escalated with t1 failed
    var older = mkRun("older", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "failed", phases: [] }] }
    })
    compare(counts(Runs.rollup([loser, older], { id: "m1" })), "0,0,0,2,0,2", "all finished: newest wins")

    // synthetic: a started run whose lease is dead (t1 started) beside the done run
    var dead = mkRun("dead", "started", false, {
      tree: { stories: [], subtasks: [{ card_id: "t1", status: "started", phases: [] }] }
    })
    compare(counts(Runs.rollup([loser, dead], { id: "m1" })), "1,0,0,0,0,1", "dead lease still wins")
  }

  function test_rollup_prototype_ids() {
    // synthetic: card ids that are Object.prototype member names
    var proto = mkRun("p", "started", true, {
      tree: { stories: [{ card_id: "__proto__", subtasks: ["constructor"] }],
              subtasks: [{ card_id: "constructor", status: "done", phases: [] },
                         { card_id: "toString", status: "started", phases: [] }] }
    })
    compare(counts(Runs.rollup([proto], { id: "constructor" })), "0,0,0,1,0,1", "constructor subtask")
    compare(counts(Runs.rollup([proto], { id: "__proto__" })), "0,0,0,1,0,1", "__proto__ story")
    compare(counts(Runs.rollup([proto], { id: "valueOf" })), "0,0,0,0,0,0", "absent valueOf")
  }

  function test_rollup_ignores_brd_and_garbage() {
    var runs = [membershipRun("r1", "started", true)]
    var card = { id: "s1", status: "done", children: ["t1", "t2", "t9"], counts: { done: 9 } }
    compare(counts(Runs.rollup(runs, card)), "1,1,0,0,0,2", "brd status, children and counts ignored")
    compare(counts(Runs.rollup(runs, card)), counts(Runs.rollup(runs, { id: "s1" })))
    compare(counts(Runs.rollup(runs, { id: "s9x" })), "0,0,0,0,0,0", "untouched card")

    var garbage = [[undefined, { id: "m1" }], [null, { id: "m1" }], ["x", { id: "m1" }], [runs, null],
                   [runs, "m1"], [runs, {}], [runs, { id: "" }], [runs, { id: 5 }], [runs, []]]
    for (var i = 0; i < garbage.length; i++) {
      compare(counts(Runs.rollup(garbage[i][0], garbage[i][1])), "0,0,0,0,0,0", "garbage " + i)
    }

    // synthetic: a junk tree, with a row naming t1
    var junk = [{ id: "j", status: "started", lease: { live: true }, milestone_id: "m1",
                  tree: { stories: "x", subtasks: [null, 5] }, rows: [{ card_id: "t1", status: "running" }] }]
    compare(counts(Runs.rollup(junk, { id: "m1" })), "0,0,0,0,0,0", "junk tree")

    // synthetic: tree.subtasks is an object, not an array, with a row naming t1
    var notArray = mkRun("n", "started", true, {
      tree: { stories: [], subtasks: { card_id: "t1", status: "started" } },
      rows: [{ card_id: "t1", status: "started" }]
    })
    compare(counts(Runs.rollup([notArray], { id: "m1" })), "0,0,0,0,0,0", "subtasks not an array")
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

    // synthetic: a tree with no phase whose status is exactly "failed", fresh per call
    function noFailedTree() {
      return { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done" },
                                                                 { name: "plan", status: "FAILED" }] }] }
    }

    var failures = ["failed", "escalated", "gate_failed", "schema_invalid", "harness_error"]
    for (var f = 0; f < failures.length; f++) {
      // synthetic: one failure row followed by finished rows
      var oneFailure = mkRun("r", "escalated", null, { tree: noFailedTree(), rows: [
        { card_id: "t1", phase: "spec", status: "done" },
        { card_id: "t2", phase: "implement", status: failures[f] },
        { card_id: "t3", phase: "verify", status: "done" },
        { card_id: "t4", phase: "mark_done", status: "ok" }] })
      compare(Runs.escalationReason(oneFailure), "escalated at implement",
              failures[f] + ": the failure row, not a later finished row")
    }

    // synthetic: two failure rows, then a finished row
    var twoFailures = mkRun("r", "escalated", null, { tree: noFailedTree(), rows: [
      { phase: "spec", status: "failed" }, { phase: "review", status: "harness_error" },
      { phase: "mark_done", status: "done" }] })
    compare(Runs.escalationReason(twoFailures), "escalated at review", "the last failure row")

    // synthetic: the later failure rows have no usable phase
    var noPhase = mkRun("r", "escalated", null, { tree: noFailedTree(), rows: [
      { phase: "spec", status: "gate_failed" }, { phase: "  ", status: "failed" }, { status: "escalated" }, null, 5] })
    compare(Runs.escalationReason(noPhase), "escalated at spec", "a failure row without a phase is passed over")

    // synthetic: statuses that are not failures, every row with a phase
    var others = ["done", "ok", "started", "pending", "stopped", "cancelled", "FAILED", " failed", "dead",
                  null, 1, "__proto__", "constructor", "toString"]
    var otherRows = []
    for (var o = 0; o < others.length; o++) otherRows.push({ card_id: "t" + o, phase: "p" + o, status: others[o] })
    otherRows.push({ card_id: "tx", phase: "px" })
    compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: noFailedTree(), rows: otherRows })),
            "escalated", "no failure status; status match is exact")

    // synthetic: rows that are not an array
    var notArrays = ["x", {}]
    for (var n = 0; n < notArrays.length; n++)
      compare(Runs.escalationReason(mkRun("r", "escalated", null, { tree: noFailedTree(), rows: notArrays[n] })),
              "escalated", "rows not an array " + n)

    // synthetic: a failed tree phase and a failure row in another phase
    var both = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "review", status: "failed" }] }] },
      rows: [{ card_id: "t1", phase: "implement", status: "gate_failed" }]
    })
    compare(Runs.escalationReason(both), "escalated at review", "the failed tree phase wins over rows")

    var nameless = mkRun("r", "escalated", null, {
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ status: "failed" }] }] },
      rows: [{ card_id: "t1", phase: "spec", status: "failed" }]
    })
    compare(Runs.escalationReason(nameless), "escalated", "nameless failed phase")

    compare(Runs.escalationReason(mkRun("r", "escalated", null)), "escalated", "nothing at all")

    var bad = [undefined, null, "x", 5, [], {}, { tree: "x", rows: "y" },
               { tree: { subtasks: [null, { phases: "x" }, { phases: [null, 5] }] }, rows: [null] }]
    for (var i = 0; i < bad.length; i++) compare(Runs.escalationReason(bad[i]), "escalated", "garbage " + i)
  }

  // The two escalated captures and the reason each escalated with: status-escalated.json's
  // failed review phase's detail, and plain "escalated" for the Integrate escalation, whose
  // tree has no failed phase and whose rows have no failure status.
  function escalatedFixtures() {
    return [
      ["status-escalated.json", "phase 'review' gate 'review_blockers_gate' failed: blocked=review, detail=review left 1 unresolved blocker(s): the review-fail marker names m3/task-b1-only-subtask-of-eb8b1851"],
      ["status-escalated-integrate.json", "escalated"]
    ]
  }

  function test_fixture_escalation_reason() {
    var integrate = Runs.normalizeRun(amRun("status-escalated-integrate.json"))
    var last = integrate.rows[integrate.rows.length - 1]
    compare(last.phase + ":" + last.status, "mark_done:done", "the Integrate capture ends on a finished row")

    var cases = escalatedFixtures()
    for (var i = 0; i < cases.length; i++)
      compare(Runs.escalationReason(Runs.normalizeRun(amRun(cases[i][0]))), cases[i][1], cases[i][0])
  }

  function test_fixture_new_alerts_escalation_reason() {
    var cases = escalatedFixtures()
    for (var i = 0; i < cases.length; i++) {
      var next = Runs.normalizeRun(amRun(cases[i][0]))
      verify(next.id !== "", cases[i][0] + " has a run id")
      // synthetic: the same run one snapshot earlier, while it was running -- no capture holds both
      var prev = [mkRun(next.id, "started", true)]
      var a = Runs.newAlerts(prev, [next])
      compare(a.length, 1, cases[i][0] + " one alert")
      compare(a[0].state, "escalated", cases[i][0] + " state")
      compare(a[0].id, next.id, cases[i][0] + " id")
      compare(a[0].reason, cases[i][1], cases[i][0] + " reason")
    }
  }

  // Cancelled, in either spelling, is neither escalated nor dead: no alert,
  // whether the run is new or was running one snapshot earlier.
  function test_fixture_cancel_spellings_new_alerts() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      var run = cancelledRun(spellings[i])
      compare(Runs.newAlerts([], [run]).length, 0, spellings[i] + ": absent from prevRuns")

      // synthetic: the same run while it was running
      var prev = Runs.normalizeRun(amRun("status-done.json"))
      prev.status = "started"
      prev.lease = { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: true }
      compare(Runs.runState(prev), "running", spellings[i] + ": prev is running")
      compare(prev.id, run.id, spellings[i] + ": prev is the same run")
      compare(Runs.newAlerts([prev], [run]).length, 0, spellings[i] + ": was running")
    }
  }

  // ---- 1.2: error text --------------------------------------------------------------------

  function test_error_text() {
    compare(Runs.errorText({ ok: false, error: { type: "LeaseHeld", message: "run r1 is held by pid 42" } }),
            "LeaseHeld: run r1 is held by pid 42", "full envelope")
    compare(Runs.errorText({ type: "NotFound", message: "no such run" }), "NotFound: no such run", "bare error")
    compare(Runs.errorText({ ok: false, error: { type: "Timeout" } }), "Timeout", "type only")
    compare(Runs.errorText({ ok: false, error: { message: "boom" } }), "boom", "message only")
    compare(Runs.errorText({ ok: false, error: { type: "  ", message: "  boom  " } }), "boom", "blank type, trimmed")
    compare(Runs.errorText({ ok: false, error: { type: " Busy ", message: " try later " } }), "Busy: try later", "trimmed")
    compare(Runs.errorText({ ok: false, error: { type: 500, message: 7 } }), "500: 7", "coerced with String")
    compare(Runs.errorText({ ok: false, error: {} }), "unknown error", "neither")
    compare(Runs.errorText({ ok: false }), "unknown error", "no error key")
    compare(Runs.errorText({ ok: false, error: "x" }), "unknown error", "string error")
    compare(Runs.errorText({ ok: false, error: { type: null, message: undefined } }), "unknown error", "null fields")
    compare(Runs.errorText({ ok: true, data: {} }), "", "ok envelope")
    compare(Runs.errorText({ ok: true, error: { type: "X", message: "y" } }), "", "ok wins")

    var bad = [undefined, null, "boom", 5, true, []]
    for (var i = 0; i < bad.length; i++) compare(Runs.errorText(bad[i]), "unknown error", "garbage " + i)

    var weird = Object.create(null)
    compare(Runs.errorText({ ok: false, error: { type: weird, message: "m" } }), "m", "unconvertible type does not throw")
  }

  // ---- 5.1: the Runs screen's helpers -----------------------------------------------------

  function test_normalize_keeps_started_at() {
    compare(Runs.normalizeRun(amRun("status-started.json")).started_at, "2026-10-05 02:14:00.590972+00:00",
            "from the am runs row")
    // synthetic: bare am status runs and rows, one field each
    compare(Runs.normalizeRun({ status: { run: { started_at: "2026-10-01T00:00:00Z" } } }).started_at,
            "2026-10-01T00:00:00Z", "falls back to am status")
    compare(Runs.normalizeRun({ row: { id: "r1" } }).started_at, "", "absent")
    compare(Runs.normalizeRun({ row: { started_at: null } }).started_at, "", "null")
  }

  function test_short_id() {
    compare(Runs.shortId({ id: "run-20261003-abcdef12" }), "…abcdef12", "the last 8 characters")
    compare(Runs.shortId({ id: "abc" }), "…abc", "a short id keeps what it has")
    compare(Runs.shortId({ id: "" }), "…", "empty id")
    var bad = [undefined, null, "x", 5, [], {}, { id: 7 }, { id: null }]
    for (var i = 0; i < bad.length; i++) compare(Runs.shortId(bad[i]), "…", "garbage " + i)
  }

  function test_run_title() {
    compare(Runs.runTitle(mkRun("run-0000abcd1234", "started", true, { milestone_id: "4bf4fb2f" })), "4bf4fb2f")
    compare(Runs.runTitle(mkRun("run-0000abcd1234", "started", true, { milestone_id: "" })), "…abcd1234",
            "falls back to the short id")
    compare(Runs.runTitle({ id: "r1", milestone_id: 5 }), "…r1", "a non-string milestone is no title")
    var bad = [undefined, null, "x", 5, []]
    for (var i = 0; i < bad.length; i++) compare(Runs.runTitle(bad[i]), "…", "garbage " + i)
  }

  function progressTree() {
    return { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "spec", status: "done" }, { name: "plan", status: "done" }] },
      { card_id: "t2", phases: [{ name: "spec", status: "done" }, { name: "implement", status: "started" }] },
      { card_id: "t3", phases: [] },
      { card_id: "t4" },
      { card_id: "t5", phases: [{ name: "spec", status: "done" }, null] }
    ] }
  }

  // "done/total" of a runProgress result.
  function progressText(p) { return p.done + "/" + p.total }

  // The subtask of a normalized run with this card id, else null.
  function subtaskOf(run, cardId) {
    var subtasks = run.tree.subtasks
    for (var i = 0; i < subtasks.length; i++) {
      if (subtasks[i].card_id === cardId) return subtasks[i]
    }
    return null
  }

  function test_run_progress_fixtures() {
    var cases = [
      ["status-started.json", "3/8"],
      ["status-done.json", "10/10"],
      ["status-escalated.json", "2/4"],
      ["status-escalated-integrate.json", "2/2"],
      ["status-done-integrate.json", "2/2"]
    ]
    for (var i = 0; i < cases.length; i++) {
      var p = Runs.runProgress(Runs.normalizeRun(amRun(cases[i][0])))
      compare(Object.keys(p).sort().join(","), "done,total", cases[i][0])
      compare(progressText(p), cases[i][1], cases[i][0])
    }
  }

  function test_run_progress_reads_status_not_phases() {
    // synthetic: between two phases -- the started subtask's phases cut to its first, `worktree` done
    var started = Runs.normalizeRun(amRun("status-started.json"))
    var between = subtaskOf(started, "299ec9c0-b935-4c44-a7a0-982a104cbfe5")
    compare(between.status, "started")
    compare(between.phases.length, 2)
    between.phases = [between.phases[0]]
    compare(between.phases[0].name + ":" + between.phases[0].status, "worktree:done")
    compare(progressText(Runs.runProgress(started)), "3/8", "every recorded phase done, status started")

    // synthetic: a done subtask's status set to started, its phases left all done
    var stalled = Runs.normalizeRun(amRun("status-done.json"))
    var restarted = subtaskOf(stalled, "22153f5f-9632-4b5f-a7dd-664c39d89e5c")
    compare(restarted.status, "done")
    restarted.status = "started"
    compare(progressText(Runs.runProgress(stalled)), "9/10", "status started is not done")

    // synthetic: a done subtask's phases emptied
    var bare = Runs.normalizeRun(amRun("status-done.json"))
    var emptied = subtaskOf(bare, "22153f5f-9632-4b5f-a7dd-664c39d89e5c")
    compare(emptied.status, "done")
    emptied.phases = []
    compare(progressText(Runs.runProgress(bare)), "10/10", "status done without phases is done")

    // synthetic: every subtask's phases replaced by a string
    var garbled = Runs.normalizeRun(amRun("status-escalated.json"))
    for (var i = 0; i < garbled.tree.subtasks.length; i++) garbled.tree.subtasks[i].phases = "x"
    compare(progressText(Runs.runProgress(garbled)), "2/4", "phases not a list")
  }

  function test_run_progress_status_spelling() {
    var cases = [
      ["done", "1/1"],
      ["started", "0/1"], ["pending", "0/1"], ["failed", "0/1"], ["escalated", "0/1"],
      ["stopped", "0/1"], ["cancelled", "0/1"],
      ["Done", "0/1"], ["DONE", "0/1"], [" done", "0/1"], ["", "0/1"],
      [5, "0/1"], [true, "0/1"], [null, "0/1"]
    ]
    for (var i = 0; i < cases.length; i++) {
      // synthetic: one subtask t1 in the given status, every recorded phase done
      var run = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [
        { card_id: "t1", status: cases[i][0], phases: [{ name: "spec", status: "done" }] }] } })
      compare(progressText(Runs.runProgress(run)), cases[i][1], "status " + JSON.stringify(cases[i][0]))
    }
    // synthetic: one subtask t1 with no status, every recorded phase done
    var missing = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "spec", status: "done" }] }] } })
    compare(progressText(Runs.runProgress(missing)), "0/1", "missing status")
    // synthetic: one done subtask t1 with no phases key
    var noPhases = mkRun("r1", "done", null, { tree: { stories: [], subtasks: [{ card_id: "t1", status: "done" }] } })
    compare(progressText(Runs.runProgress(noPhases)), "1/1", "done without phases")
  }

  function test_run_progress_counts_real_subtasks_only() {
    // synthetic: garbage, id-less and synthetic-id subtasks beside a real done t1 and a real started t2
    var mixed = mkRun("r1", "started", true, { tree: { stories: [], subtasks: [
      null, "x", 5, [], {}, { status: "done" }, { card_id: "", status: "done" },
      { card_id: 7, status: "done" }, { card_id: "integrate", status: "done" },
      { card_id: "bases", status: "done" }, { card_id: "base-s1", status: "done" },
      { card_id: "t1", status: "done" }, { card_id: "t2", status: "started" }] } })
    compare(progressText(Runs.runProgress(mixed)), "1/2", "only t1 and t2 count")

    // synthetic: only synthetic-id subtasks, all done
    var bookkeeping = mkRun("r1", "done", null, { tree: { stories: [], subtasks: [
      { card_id: "integrate", status: "done" }, { card_id: "bases", status: "done" },
      { card_id: "base-s1", status: "done" }] } })
    compare(progressText(Runs.runProgress(bookkeeping)), "0/0", "bookkeeping ids are no subtasks")

    // synthetic: junk subtasks only
    var junk = Runs.runProgress({ tree: { subtasks: [null, "x", 5, { phases: "x" }] } })
    compare(progressText(junk), "0/0", "junk subtasks never count")
  }

  function test_run_progress_garbage() {
    // synthetic: a hand-built run with no subtasks
    compare(progressText(Runs.runProgress(mkRun("r", "started", true))), "0/0", "no subtasks")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" }, { tree: { subtasks: "y" } },
               { tree: { subtasks: null } }, { tree: null }]
    for (var i = 0; i < bad.length; i++) {
      var p = Runs.runProgress(bad[i])
      compare(Object.keys(p).sort().join(","), "done,total", "garbage " + i)
      compare(progressText(p), "0/0", "garbage " + i)
    }
  }

  function test_current_phase() {
    compare(Runs.currentPhase(mkRun("r", "started", true, { tree: progressTree() })), "implement")
    var two = { stories: [], subtasks: [
      { card_id: "a", phases: [{ name: "spec", status: "done" }] },
      { card_id: "b", phases: [{ name: "review", status: "started" }] },
      { card_id: "c", phases: [{ name: "verify", status: "started" }] }
    ] }
    compare(Runs.currentPhase(mkRun("r", "started", true, { tree: two })), "review", "the first started phase in subtask order")
    compare(Runs.currentPhase(mkRun("r", "done", null, { tree: { stories: [], subtasks: [
      { phases: [{ name: "x", status: "done" }] }] } })), "", "none started")
    compare(Runs.currentPhase(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { phases: [{ status: "started" }, { name: "plan", status: "started" }] }] } })), "plan", "a nameless started phase is skipped")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" },
               { tree: { subtasks: [null, { phases: "x" }, { phases: [null, 5] }] } }]
    for (var i = 0; i < bad.length; i++) compare(Runs.currentPhase(bad[i]), "", "garbage " + i)
  }

  function test_age_text() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    compare(Runs.ageText("2026-10-04T11:59:30Z", now), "just now")
    compare(Runs.ageText("2026-10-04T12:00:00Z", now), "just now", "zero seconds")
    compare(Runs.ageText("2026-10-04T11:59:00Z", now), "1m")
    compare(Runs.ageText("2026-10-04T11:01:00Z", now), "59m")
    compare(Runs.ageText("2026-10-04T11:00:00Z", now), "1h")
    compare(Runs.ageText("2026-10-03T12:00:01Z", now), "23h")
    compare(Runs.ageText("2026-10-03T12:00:00Z", now), "1d")
    compare(Runs.ageText("2026-09-24T12:00:00Z", now), "10d")
    compare(Runs.ageText("2026-10-04T12:00:01Z", now), "", "the future")
    var bad = ["", "not a date", null, undefined, 5, {}, []]
    for (var i = 0; i < bad.length; i++) compare(Runs.ageText(bad[i], now), "", "garbage iso " + i)
    var badNow = [undefined, null, "x", NaN, Infinity]
    for (var j = 0; j < badNow.length; j++) compare(Runs.ageText("2026-10-04T11:00:00Z", badNow[j]), "", "garbage now " + j)
  }

  function test_run_age_text() {
    var now = Date.parse("2026-10-04T12:00:00Z")
    compare(Runs.runAgeText(mkRun("r", "started", true, { started_at: "2026-10-04T10:00:00Z" }), now), "2h",
            "started_at for a live run")
    var dead = mkRun("d", "started", false, { started_at: "2026-10-01T00:00:00Z" })
    dead.lease.heartbeat_at = "2026-10-04T11:55:00Z"
    compare(Runs.runAgeText(dead, now), "5m", "the last heartbeat for a dead run")
    compare(Runs.runAgeText(mkRun("n", "started", null, { started_at: "2026-10-01T00:00:00Z" }), now), "",
            "a dead run with no lease has no age")
    compare(Runs.runAgeText(mkRun("p", "stopped", null, { started_at: "2026-10-03T12:00:00Z" }), now), "1d", "parked")
    compare(Runs.runAgeText(mkRun("e", "escalated", null), now), "", "no started_at")
    var bad = [undefined, null, "x", 5, [], {}, { status: "started", lease: { live: false, heartbeat_at: 5 } }]
    for (var i = 0; i < bad.length; i++) compare(Runs.runAgeText(bad[i], now), "", "garbage " + i)
  }

  function screenRuns() {
    return [
      mkRun("run-live-0001", "started", true, { milestone_id: "alpha", tree: { stories: [], subtasks: [
        { card_id: "t1", phases: [{ name: "implement", status: "started" }] }] } }),
      mkRun("run-esc-00002", "escalated", null, { milestone_id: "beta" }),
      mkRun("run-dead-0003", "started", false, { milestone_id: "gamma" }),
      mkRun("run-park-0004", "stopped", null, { milestone_id: "delta" }),
      mkRun("run-done-0005", "done", null, { milestone_id: "epsilon" })
    ]
  }

  function ids(list) { return list.map(function(r) { return r.id }).join(",") }

  function test_run_filter_counts() {
    var c = Runs.runFilterCounts(screenRuns())
    compare(Object.keys(c).sort().join(","), "all,attention,live,parked")
    compare([c.attention, c.live, c.parked, c.all].join(","), "2,1,1,5")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) {
      var b = Runs.runFilterCounts(bad[i])
      compare([b.attention, b.live, b.parked, b.all].join(","), "0,0,0,0", "garbage " + i)
    }
  }

  function test_filter_runs() {
    var list = screenRuns()
    compare(ids(Runs.filterRuns(list, "attention")), "run-esc-00002,run-dead-0003")
    compare(ids(Runs.filterRuns(list, "live")), "run-live-0001")
    compare(ids(Runs.filterRuns(list, "parked")), "run-park-0004")
    var all = ids(list)
    compare(ids(Runs.filterRuns(list, "all")), all)
    compare(ids(Runs.filterRuns(list, "")), all)
    compare(ids(Runs.filterRuns(list, "bogus")), all, "an unknown id is All")
    compare(ids(Runs.filterRuns(list, undefined)), all)
    compare(ids(Runs.filterRuns(list, "constructor")), all)
    compare(Runs.filterRuns(list, "live")[0] === list[0], true, "the same objects")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.filterRuns(bad[i], "live").length, 0, "garbage " + i)
  }

  function test_search_runs() {
    var list = screenRuns()
    compare(Runs.searchRuns(list, "") === list, true, "no query returns the input itself")
    compare(Runs.searchRuns(list, "   ") === list, true, "a query of spaces hides nothing")
    compare(ids(Runs.searchRuns(list, "GAMMA")), "run-dead-0003", "title, any case")
    compare(ids(Runs.searchRuns(list, "esc-0")), "run-esc-00002", "id")
    compare(ids(Runs.searchRuns(list, "implem")), "run-live-0001", "current phase")
    compare(ids(Runs.searchRuns(list, "parked")), "run-park-0004", "state name")
    compare(ids(Runs.searchRuns(list, "dead")), "run-dead-0003", "dead is a state name too")
    compare(Runs.searchRuns(list, "zzz").length, 0)
    compare(ids(Runs.searchRuns([null, 5, list[1]], "beta")), "run-esc-00002", "junk entries never match")
    var bad = [undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.searchRuns(bad[i], "a").length, 0, "garbage " + i)
  }

  // ---- Run detail (5.2)

  function test_normalize_branch_fields() {
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "dsp")
    // synthetic: bare am status runs and rows, branch fields only
    var fromRun = Runs.normalizeRun({ status: { run: { base_branch: "master", branch_prefix: "m3" } } })
    compare(fromRun.base_branch, "master", "status.run is the fallback")
    compare(fromRun.branch_prefix, "m3")
    var rowWins = Runs.normalizeRun({ row: { base_branch: "a", branch_prefix: "p" },
                                      status: { run: { base_branch: "b", branch_prefix: "q" } } })
    compare(rowWins.base_branch, "a", "the am runs row comes first")
    compare(rowWins.branch_prefix, "p")
    var blankRow = Runs.normalizeRun({ row: { base_branch: "", branch_prefix: null },
                                       status: { run: { base_branch: "b", branch_prefix: "q" } } })
    compare(blankRow.base_branch, "b", "an empty row value falls back")
    compare(blankRow.branch_prefix, "q")
    compare(Runs.normalizeRun({}).base_branch, "")
    compare(Runs.normalizeRun({}).branch_prefix, "")
  }

  function numbered(n, from) {
    var out = []
    for (var i = 0; i < n; i++) out.push("line " + ((from || 0) + i))
    return out.join("\n") + "\n"
  }

  // A fresh logs-attempt.json `am logs` data object whose stdout and stderr
  // artifact texts are `stdout` and `stderr`; an undefined argument keeps the
  // fixture's text (stdout: 19 lines, stderr: null).
  function logsData(stdout, stderr) {
    var data = F.load("logs-attempt.json").data
    // synthetic: the texts are the test's; the shape is the capture's.
    if (stdout !== undefined) data.artifacts.stdout.text = stdout
    if (stderr !== undefined) data.artifacts.stderr.text = stderr
    return data
  }

  // The capture's stdout text as its 19 lines.
  function fixtureStdoutLines() {
    var text = F.load("logs-attempt.json").data.artifacts.stdout.text
    return text.slice(0, -1).split("\n")
  }

  function test_log_tail() {
    var under = Runs.logTail(logsData("collecting...\n3 passed\n"), 200)
    compare(under.text, "collecting...\n3 passed")
    compare(under.truncated, false)

    var exact = Runs.logTail(logsData(numbered(200)), 200)
    compare(exact.text.split("\n").length, 200)
    compare(exact.truncated, false, "exactly 200 lines is not cut")

    var big = Runs.logTail(logsData(numbered(5000), ""), 200)
    var lines = big.text.split("\n")
    compare(lines.length, 200)
    compare(lines[0], "line 4800")
    compare(lines[199], "line 4999")
    compare(big.truncated, true)

    var withErr = Runs.logTail(logsData("out\n", "err1\nerr2\n"), 200)
    compare(withErr.text, "out\nerr1\nerr2", "stderr follows stdout")
    compare(withErr.truncated, false)

    var errOnly = Runs.logTail(logsData("", "boom"), 200)
    compare(errOnly.text, "boom")

    // A huge stderr is bounded too.
    var hugeErr = Runs.logTail(logsData("out\n", numbered(300)), 200)
    var errLines = hugeErr.text.split("\n")
    compare(errLines.length, 201, "stdout, then the last 200 stderr lines")
    compare(errLines[0], "out")
    compare(errLines[1], "line 100")
    compare(hugeErr.truncated, true)

    compare(Runs.logTail(logsData(numbered(250)), undefined).text.split("\n").length, 200, "a bad maxLines is 200")

    var newlineOnly = Runs.logTail(logsData("\n"), 200)
    compare(newlineOnly.text, "", "a lone newline is no lines")
    compare(newlineOnly.truncated, false)

    // synthetic: garbage in place of an `am logs` data object.
    var bad = [undefined, null, "x", 5, [], {}, { artifacts: null }, { artifacts: "x" }, { artifacts: [] },
               { artifacts: {} }, { artifacts: { stdout: 5, stderr: {} } },
               { artifacts: { stdout: { text: 5 }, stderr: { text: [] } } },
               { artifacts: { stdout: { text: null }, stderr: { text: null } } },
               { artifacts: { stdout: { text: "" } } }]
    for (var i = 0; i < bad.length; i++) {
      var t = Runs.logTail(bad[i], 200)
      compare(t.text, "", "garbage " + i)
      compare(t.truncated, false, "garbage " + i)
    }
  }

  function test_log_tail_of_a_real_attempt() {
    var data = F.load("logs-attempt.json").data
    var stdout = data.artifacts.stdout.text
    var tail = Runs.logTail(data, 200)
    compare(tail.text, stdout.slice(0, -1), "the stdout artifact without its trailing newline")
    var lines = tail.text.split("\n")
    compare(lines.length, 19)
    verify(lines[0].indexOf("Permission allow rule") === 0, lines[0])
    compare(lines[18], "| plan_hash | `e8f781ba` |")
    compare(tail.truncated, false)
    verify(tail.text.indexOf("# Reviewer") < 0, "the prompt artifact is not shown")

    var ten = Runs.logTail(F.load("logs-attempt.json").data, 10)
    compare(ten.text, lines.slice(9).join("\n"), "the last 10 of the 19 lines")
    compare(ten.truncated, true)
  }

  function test_log_tail_reads_only_the_stream_artifacts() {
    // synthetic: a top-level stdout/stderr of the old guessed shape added to a fresh copy.
    var legacy = F.load("logs-attempt.json").data
    legacy.stdout = "legacy\n"
    legacy.stderr = "legacy\n"
    compare(Runs.logTail(legacy, 200).text, fixtureStdoutLines().join("\n"), "the old shape is ignored")

    // synthetic: the old guessed shape alone.
    var old = Runs.logTail({ stdout: "x\n", stderr: "y\n" }, 200)
    compare(old.text, "")
    compare(old.truncated, false)

    // synthetic: a fresh copy with no stdout artifact and a stderr text.
    var noOut = logsData(undefined, "boom\n")
    delete noOut.artifacts.stdout
    compare(Runs.logTail(noOut, 200).text, "boom")

    // synthetic: a fresh copy whose stderr says present: false yet has a text.
    var late = logsData(undefined, "late\n")
    late.artifacts.stderr.present = false
    compare(Runs.logTail(late, 200).text, fixtureStdoutLines().concat(["late"]).join("\n"), "present is not consulted")

    var data = F.load("logs-attempt.json").data
    var before = JSON.stringify(data)
    Runs.logTail(data, 10)
    compare(JSON.stringify(data), before, "data is not mutated")
  }

  function test_snapshot_age_text() {
    var now = 1790000000000
    compare(Runs.snapshotAgeText(now, now), "0s")
    compare(Runs.snapshotAgeText(now - 14000, now), "14s")
    compare(Runs.snapshotAgeText(now - 59999, now), "59s")
    compare(Runs.snapshotAgeText(now - 60000, now), "1m")
    compare(Runs.snapshotAgeText(now - 3599999, now), "59m")
    compare(Runs.snapshotAgeText(now - 3600000, now), "1h")
    compare(Runs.snapshotAgeText(now - 86399999, now), "23h")
    compare(Runs.snapshotAgeText(now - 86400000, now), "1d")
    compare(Runs.snapshotAgeText(now + 1, now), "", "the future")
    var bad = [0, -5, NaN, Infinity, null, undefined, "x", {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.snapshotAgeText(bad[i], now), "", "missing fetch " + i)
    var badNow = [NaN, Infinity, null, undefined, "x"]
    for (var j = 0; j < badNow.length; j++) compare(Runs.snapshotAgeText(now, badNow[j]), "", "garbage now " + j)
  }

  // s1 owns t1 (via its list) and t2 (via a {card_id} entry); s2 lists t1 too
  // (already s1's) and owns t3 via story_id; t4 belongs to no story. base-s1,
  // bases and integrate are bookkeeping ids from the stories, subtasks and rows.
  function detailRun() {
    return mkRun("r", "started", true, {
      rows: [{ card_id: "t1", phase: "implement", attempt: 2, status: "started" },
             { card_id: "integrate", phase: "integrate", attempt: 1, status: "pending" }],
      tree: {
        stories: [{ card_id: "s1", status: "started", subtasks: ["t1", { card_id: "t2" }] },
                  { card_id: "s2", subtasks: ["t1"] },
                  { card_id: "base-s1", status: "done" }],
        subtasks: [
          { card_id: "t1", phases: [
            { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
            { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { attempt: 2, status: "started" }] }] },
          { card_id: "t2", status: "pending", phases: [{ name: "spec", status: "pending", attempts: [] }] },
          { card_id: "t3", story_id: "s2", phases: [] },
          { card_id: "t4", phases: [{ name: "review", status: "done", attempts: [{ status: "done" }] }] },
          { card_id: "bases", status: "done" }
        ]
      }
    })
  }

  function cardIds(list) { return list.map(function(x) { return x.card_id }).join(",") }

  function test_glyph_state_of() {
    var cases = [["started", "running"], ["running", "running"], ["stopped", "parked"], ["parked", "parked"],
                 ["escalated", "escalated"], ["failed", "dead"], ["dead", "dead"], ["cancelled", "cancelled"],
                 ["done", "done"], ["pending", ""], ["", ""], [undefined, ""], [null, ""], [5, ""], ["constructor", ""],
                 ["ok", "done"], ["gate_failed", "dead"],
                 // synthetic: no capture contains schema_invalid or harness_error.
                 ["schema_invalid", "dead"], ["harness_error", "dead"],
                 ["OK", ""], [" ok", ""], ["Gate_Failed", ""], ["canceled", "cancelled"], ["Canceled", ""],
                 [" canceled", ""], ["__proto__", ""]]
    for (var i = 0; i < cases.length; i++) compare(Runs.glyphStateOf(cases[i][0]), cases[i][1], String(cases[i][0]))
  }

  // Every attempt and row status of a real capture maps per `expected`; a
  // status missing from it fails, naming the status.
  function test_fixture_glyph_state_of_attempt_outcomes() {
    var expected = { ok: "done", done: "done", gate_failed: "dead", failed: "dead", escalated: "escalated",
                     started: "running", pending: "" }
    function walk(name) {
      var r = Runs.normalizeRun(amRun(name))
      var seen = []
      for (var i = 0; i < r.tree.subtasks.length; i++) {
        var phases = r.tree.subtasks[i].phases || []
        for (var j = 0; j < phases.length; j++) {
          var tries = phases[j].attempts || []
          for (var k = 0; k < tries.length; k++) seen.push(tries[k].status)
        }
      }
      for (var w = 0; w < r.rows.length; w++) seen.push(r.rows[w].status)
      for (var s = 0; s < seen.length; s++) {
        var st = seen[s]
        verify(typeof st === "string" && Object.prototype.hasOwnProperty.call(expected, st),
               name + ": status " + String(st) + " has no expected glyph state")
        compare(Runs.glyphStateOf(st), expected[st], name + ": " + st)
      }
      return seen
    }
    var escalated = walk("status-escalated.json")
    verify(escalated.indexOf("gate_failed") >= 0, "status-escalated.json has a gate_failed status")
    verify(escalated.indexOf("ok") >= 0, "status-escalated.json has an ok status")
    verify(walk("status-done.json").indexOf("ok") >= 0, "status-done.json has an ok status")
  }

  function test_run_tree() {
    var t = Runs.runTree(detailRun())
    compare(t.stories.map(function(s) { return s.label }).join(","), "s1,s2,Other")
    compare(cardIds(t.stories[0].subtasks), "t1,t2", "story_id-less membership through the story's list")
    compare(cardIds(t.stories[1].subtasks), "t3", "story_id membership; t1 stays with the first story only")
    compare(cardIds(t.stories[2].subtasks), "t4", "a subtask of no story is kept under Other")
    compare(t.stories[0].card_id, "s1")
    compare(t.stories[0].status, "started")
    compare(t.stories[0].other, false)
    compare(t.stories[1].status, "")
    compare(t.stories[2].card_id, "")
    compare(t.stories[2].other, true)

    var t1 = t.stories[0].subtasks[0]
    compare(t1.status, "started", "no own status: the last am row for the card")
    compare(t1.phases.map(function(p) { return p.name + ":" + p.status }).join(","), "spec:done,implement:started")
    compare(t1.attempts.map(function(a) { return a.phase + "." + a.attempt + ":" + a.status }).join(","),
            "spec.1:done,implement.1:failed,implement.2:started")
    compare(t1.currentPhase, "implement")
    compare(t1.currentAttempt, 2)

    var t2 = t.stories[0].subtasks[1]
    compare(t2.status, "pending", "its own status wins")
    compare(t2.currentPhase, "spec", "no started phase: the last named one")
    compare(t2.currentAttempt, 0)
    compare(t2.attempts.length, 0)

    // Review Focus 3: an unnumbered attempt is listed with attempt 0.
    var t4 = t.stories[2].subtasks[0]
    compare(t4.attempts.length, 1)
    compare(t4.attempts[0].attempt, 0)
    compare(t4.attempts[0].status, "done")
    compare(t4.currentAttempt, 0)

    compare(t.synthetic.map(function(s) { return s.id }).join(","), "base-s1,bases,integrate")
    compare(t.synthetic.map(function(s) { return s.label }).join(","), "Base s1,Bases,Integrate")
    compare(t.synthetic.map(function(s) { return s.status }).join(","), "done,done,pending")
  }

  function test_run_tree_without_synthetic_rows_or_orphans() {
    var t = Runs.runTree(mkRun("r", "started", true, { tree: { stories: [{ card_id: "s1", subtasks: [] }], subtasks: [] } }))
    compare(t.synthetic.length, 0, "no bookkeeping rows unless present")
    compare(t.stories.length, 1, "no Other group without orphans")
    compare(t.stories[0].subtasks.length, 0)
    compare(Runs.runTree(mkRun("r", "started", true)).stories.length, 0)
  }

  function test_run_tree_garbage() {
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" },
               { tree: { stories: "x", subtasks: [null, 5, { card_id: 7 }, { card_id: "" }] } }]
    for (var i = 0; i < bad.length; i++) {
      var t = Runs.runTree(bad[i])
      compare(t.stories.length, 0, "garbage " + i)
      compare(t.synthetic.length, 0, "garbage " + i)
    }
    var odd = Runs.runTree({ rows: "y", tree: { stories: [null, { card_id: "s1", subtasks: "x" }],
      subtasks: [{ card_id: "t1", phases: [null, { name: "" }, { name: "spec", attempts: "x" }] }] } })
    compare(odd.stories.map(function(s) { return s.label }).join(","), "s1,Other")
    compare(cardIds(odd.stories[1].subtasks), "t1")
    compare(odd.stories[1].subtasks[0].phases.length, 1)
    compare(odd.stories[1].subtasks[0].attempts.length, 0)
  }

  function test_run_tree_open_attempt_rule() {
    // synthetic: hand-built normalized subtasks, one per case of the open rule
    var t = Runs.runTree(mkRun("r", "done", null, { tree: {
      stories: [{ card_id: "s1", subtasks: ["a", "b", "c", "d", "e", "f", "g", "h", "i"] }],
      subtasks: [
        { card_id: "a", status: "done", phases: [
          { name: "spec", status: "done", attempts: [{ n: 2 }] },
          { name: "implement", status: "done", attempts: [{ n: 1 }] },
          { name: "verify", status: "done", attempts: [] },
          { name: "mark_done", status: "done", attempts: [{ status: "done" }] }] },
        { card_id: "b", status: "started", phases: [
          { name: "plan", status: "started", attempts: [] },
          { name: "review", status: "done", attempts: [{ n: 1 }] }] },
        { card_id: "c", status: "done", phases: [
          { name: "spec", status: "done", attempts: [{ n: 1 }] },
          { name: "", status: "done", attempts: [{ n: 3 }] },
          null,
          { name: "review", status: "done", attempts: [{ n: 0 }, { n: -1 }, { n: "2" }, { n: Infinity }, null] }] },
        { card_id: "d", status: "done", phases: [
          { name: "worktree", status: "done", attempts: [] },
          { name: "explore", status: "done", attempts: "x" }] },
        { card_id: "e", status: "started", phases: [
          { name: "spec", status: "done", attempts: [{ n: 1 }] },
          { name: "implement", status: "started", attempts: [] }] },
        { card_id: "f", status: "pending", phases: [null, { name: "" }, { name: 5, status: "started", attempts: [{ n: 1 }] }] },
        { card_id: "g", status: "pending" },
        { card_id: "h", status: "started", phases: [
          { name: "spec", status: "done", attempts: [{ n: 1 }] },
          { name: "implement", status: "running", attempts: [] },
          { name: "review", status: null, attempts: [] },
          { name: "verify", status: 5, attempts: [] }] },
        { card_id: "i", status: "done", phases: [
          { name: "spec", status: "done", attempts: [{ attempt: 2, status: "done" }] },
          { name: "verify", status: "done", attempts: [] }] }
      ] } }))
    compare(cardIds(t.stories[0].subtasks), "a,b,c,d,e,f,g,h,i")
    compare(opensOn(treeNode(t, "a")), "implement/1", "the last numbered phase by position, not the highest n; unnumbered and empty trailing phases passed over")
    compare(opensOn(treeNode(t, "b")), "plan/0", "a started phase wins over a later numbered one")
    compare(opensOn(treeNode(t, "c")), "spec/1", "unnamed and non-object phases are never current; bad numbers are not numbered")
    compare(opensOn(treeNode(t, "d")), "explore/0", "nothing numbered: the last phase")
    compare(opensOn(treeNode(t, "e")), "implement/0", "a started phase after a numbered one wins")
    compare(opensOn(treeNode(t, "f")), "/0", "only unnamed phases: no current phase")
    compare(opensOn(treeNode(t, "g")), "/0", "no phases")
    compare(opensOn(treeNode(t, "h")), "spec/1", "only the exact status started wins the first rule")
    compare(opensOn(treeNode(t, "i")), "spec/2", "a legacy attempt number counts")
  }

  function at(d) { return d === null ? "null" : d.card_id + "/" + d.phase + "/" + d.attempt }

  function test_default_attempt() {
    compare(at(Runs.defaultAttempt(detailRun())), "t1/implement/2")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "a", phases: [{ name: "review", status: "started", attempts: [] }] },
      { card_id: "b", phases: [{ name: "plan", status: "started", attempts: [{ n: 3, status: "started" }, { n: 1, status: "failed" }] }] }
    ] } }))), "b/plan/3", "a started phase without attempts is skipped; the highest number wins")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "integrate", phases: [{ name: "integrate", status: "started", attempts: [{ n: 1 }] }] }] } }))),
      "null", "a bookkeeping id is never a card")
    compare(at(Runs.defaultAttempt(mkRun("r", "done", null, {
      rows: [{ card_id: "t1", phase: "spec", attempt: 1, status: "done" }, { card_id: "integrate", phase: "integrate", attempt: 1 }],
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done", attempts: [{ n: 1 }, { n: 2 }] }] }] }
    }))), "t1/spec/2", "no started phase: the newest attempt of the last real row")
    compare(at(Runs.defaultAttempt(mkRun("r", "done", null, { rows: [{ card_id: "t5", phase: "plan", n: 4 }] }))),
            "t5/plan/4", "a row's own n")
    compare(at(Runs.defaultAttempt(mkRun("r", "done", null, { rows: [{ card_id: "t5", phase: "plan", status: "done" }] }))),
            "null", "a row with no number and no tree attempt")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "implement", status: "started", attempts: [{ status: "started" }] }] }] } }))),
      "null", "unnumbered attempts cannot be fetched")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true))), "null", "an empty tree")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x", rows: "y" }, { rows: [null, 5, { card_id: 7, phase: "x", n: 1 }] }]
    for (var i = 0; i < bad.length; i++) compare(Runs.defaultAttempt(bad[i]), null, "garbage " + i)
  }

  function test_attempt_status() {
    var run = detailRun()
    compare(Runs.attemptStatus(run, "t1", "implement", 2), "started")
    compare(Runs.attemptStatus(run, "t1", "implement", 1), "failed")
    compare(Runs.attemptStatus(run, "t1", "spec", 1), "done")
    compare(Runs.attemptStatus(run, "t1", "spec", 9), "")
    compare(Runs.attemptStatus(run, "t1", "verify", 1), "")
    compare(Runs.attemptStatus(run, "zz", "spec", 1), "")
    compare(Runs.attemptStatus(run, "t4", "review", 0), "", "0 is not an attempt number")
    var bad = [undefined, null, "x", 5, [], {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.attemptStatus(bad[i], "t1", "spec", 1), "", "garbage " + i)
    compare(Runs.attemptStatus(run, null, "spec", 1), "")
    compare(Runs.attemptStatus(run, "t1", null, 1), "")
    compare(Runs.attemptStatus(run, "t1", "spec", "1"), "", "a string attempt is not a number")
  }

  // ---- 5.3: the runs that touch one card (card detail's RUNS list) --------------------------

  function test_runs_touching() {
    var a = mkRun("ra", "started", true, { tree: sampleTree() })                 // m1; s1, s2; t1, t2, t3
    var b = mkRun("rb", "done", null, { milestone_id: "m2", rows: [{ card_id: "t1", status: "done" }] })
    var c = mkRun("rc", "stopped", null, { milestone_id: "m1" })
    var runs = [a, b, c]
    compare(ids(Runs.runsTouching(runs, "m1")), "ra,rc", "milestone, input order kept")
    compare(ids(Runs.runsTouching(runs, "s2")), "ra", "story")
    compare(ids(Runs.runsTouching(runs, "t3")), "ra", "subtask")
    compare(ids(Runs.runsTouching(runs, "m2")), "rb")
    compare(ids(Runs.runsTouching(runs, "t1")), "ra", "rb names t1 only in its rows: not a touch")
    verify(Runs.runsTouching(runs, "m1")[0] === a, "the same run objects, not copies")
    compare(Runs.runsTouching(runs, "zzz").length, 0, "unrelated")

    var badIds = ["", null, undefined, 5, {}, "integrate", "bases", "base-x"]
    for (var i = 0; i < badIds.length; i++)
      compare(Runs.runsTouching(runs, badIds[i]).length, 0, "bad id " + i)
    var badRuns = [undefined, null, "x", 5, {}, [null, 3, "s", []]]
    for (var j = 0; j < badRuns.length; j++)
      compare(Runs.runsTouching(badRuns[j], "m1").length, 0, "bad runs " + j)
  }

  // ---- S2 1.1: run controls ----------------------------------------------------------------

  readonly property string ctlIntegrate: "Integrate is running; it cannot be paused or cancelled"
  readonly property string ctlFinished: "The run has finished"
  readonly property string ctlUnknown: "The run's state is unknown"
  readonly property string ctlPauseNotRunning: "Only a running run can be paused"
  readonly property string ctlResumeRunning: "The run is still running"
  readonly property string ctlResumeCancelled: "A cancelled run cannot be resumed"
  readonly property string ctlCancelCancelled: "The run is already cancelled"

  // mkRun with the lease's accepting flag set; live === null still means no lease.
  function ctlRun(status, live, accepting) {
    var r = mkRun("rc", status, live)
    if (r.lease !== null) r.lease.accepting = accepting
    return r
  }

  // One action of a controls() result: exactly {enabled, reason}; enabled iff reason is "".
  function checkAction(a, reason, label) {
    compare(Object.keys(a).sort().join(","), "enabled,reason", label + " keys")
    compare(a.enabled, reason === "", label + " enabled")
    compare(a.reason, reason, label + " reason")
  }

  // A whole controls() result; "" means that action is enabled.
  function checkControls(c, pause, resume, cancel, label) {
    compare(Object.keys(c).sort().join(","), "cancel,pause,resume", label + " keys")
    checkAction(c.pause, pause, label + " pause")
    checkAction(c.resume, resume, label + " resume")
    checkAction(c.cancel, cancel, label + " cancel")
  }

  function test_controls_shape() {
    var run = ctlRun("started", true, true)
    var a = Runs.controls(run)
    checkControls(a, "", ctlResumeRunning, "", "running")
    var b = Runs.controls(run)
    verify(a !== b, "a fresh result per call")
    verify(a.pause !== b.pause && a.resume !== b.resume && a.cancel !== b.cancel, "fresh actions per call")
    verify(a.pause !== a.resume && a.resume !== a.cancel && a.pause !== a.cancel, "no action shared within a result")
    a.pause.enabled = false
    a.pause.reason = "changed"
    a.resume.reason = "changed"
    delete a.cancel
    checkControls(Runs.controls(run), "", ctlResumeRunning, "", "after mutating an earlier result")

    var u = Runs.controls(undefined)
    verify(u.pause !== u.resume && u.resume !== u.cancel && u.pause !== u.cancel, "no action shared in an unknown result")
    u.pause.reason = "changed"
    u.resume.enabled = true
    checkControls(Runs.controls(null), ctlUnknown, ctlUnknown, ctlUnknown, "after mutating an unknown result")

    var d = Runs.controls(ctlRun("done", null, true))
    d.cancel.reason = ""
    d.cancel.enabled = true
    checkControls(Runs.controls(ctlRun("done", null, true)), ctlFinished, ctlFinished, ctlFinished, "after mutating a done result")
  }

  function test_controls_running() {
    compare(Runs.runState(ctlRun("started", true, true)), "running", "fixture")
    checkControls(Runs.controls(ctlRun("started", true, true)), "", ctlResumeRunning, "", "running, accepting")
    checkControls(Runs.controls(ctlRun("started", true, false)), ctlIntegrate, ctlResumeRunning, ctlIntegrate,
                  "running, Integrate")
  }

  function test_controls_resumable_states() {
    var states = [["started", "dead"], ["stopped", "parked"], ["escalated", "escalated"]]
    for (var i = 0; i < states.length; i++) {
      var status = states[i][0], label = states[i][1]
      compare(Runs.runState(ctlRun(status, false, true)), label, label + " fixture")
      compare(Runs.runState(ctlRun(status, null, true)), label, label + " fixture, no lease")
      checkControls(Runs.controls(ctlRun(status, false, true)), ctlPauseNotRunning, "", "", label + ", accepting")
      checkControls(Runs.controls(ctlRun(status, false, false)), ctlPauseNotRunning, "", ctlIntegrate,
                    label + ", Integrate")
      checkControls(Runs.controls(ctlRun(status, null, false)), ctlPauseNotRunning, "", "",
                    label + ", no lease is not Integrate")
    }
  }

  function test_controls_finished_states() {
    var leases = [[false, true, "accepting"], [false, false, "Integrate"], [true, false, "live, Integrate"],
                  [null, true, "no lease"]]
    for (var i = 0; i < leases.length; i++) {
      var live = leases[i][0], accepting = leases[i][1], label = leases[i][2]
      var cancels = ["cancelled", "canceled"]
      for (var j = 0; j < cancels.length; j++) {
        compare(Runs.runState(ctlRun(cancels[j], live, accepting)), "cancelled", cancels[j] + " fixture " + label)
        checkControls(Runs.controls(ctlRun(cancels[j], live, accepting)),
                      ctlFinished, ctlResumeCancelled, ctlCancelCancelled, cancels[j] + ", " + label)
      }
      compare(Runs.runState(ctlRun("done", live, accepting)), "done", "fixture " + label)
      checkControls(Runs.controls(ctlRun("done", live, accepting)),
                    ctlFinished, ctlFinished, ctlFinished, "done, " + label)
    }
  }

  function test_fixture_cancel_spellings_controls() {
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++) {
      checkControls(Runs.controls(cancelledRun(spellings[i])), ctlFinished, ctlResumeCancelled, ctlCancelCancelled,
                    spellings[i])
    }
  }

  function test_controls_unknown_and_garbage() {
    // synthetic: normalizeRun(undefined) stands for garbage am output
    var runs = [ctlRun("", true, true), ctlRun("weird", true, false), ctlRun("STARTED", true, true),
                ctlRun("weird", null, true), undefined, null, 5, "x", {}, [], Object.create(null),
                Runs.normalizeRun(undefined)]
    for (var i = 0; i < runs.length; i++)
      checkControls(Runs.controls(runs[i]), ctlUnknown, ctlUnknown, ctlUnknown, "unknown " + i)

    // A lease that is not an object counts as no lease: never Integrate.
    var arrayLease = []
    arrayLease.accepting = false
    var badLeases = ["x", 5, [], arrayLease]
    for (var j = 0; j < badLeases.length; j++) {
      checkControls(Runs.controls({ status: "stopped", lease: badLeases[j] }), ctlPauseNotRunning, "", "",
                    "parked, lease " + j)
      checkControls(Runs.controls({ status: "started", lease: badLeases[j] }), ctlPauseNotRunning, "", "",
                    "dead, lease " + j)
    }
  }

  function test_controls_from_normalized() {
    // synthetic: am status with only a run and a lease
    function raw(lease) {
      return { status: { run: { id: "r", status: "started" }, control: { lease: lease } } }
    }
    var stringTrue = Runs.normalizeRun(raw({ pid: 1, live: true, accepting: "true" }))
    compare(stringTrue.lease.accepting, false, "normalised to false")
    checkControls(Runs.controls(stringTrue), ctlIntegrate, ctlResumeRunning, ctlIntegrate, "accepting \"true\"")
    checkControls(Runs.controls(Runs.normalizeRun(raw({ pid: 1, live: true }))),
                  ctlIntegrate, ctlResumeRunning, ctlIntegrate, "accepting missing")
    checkControls(Runs.controls(Runs.normalizeRun(raw({ pid: 1, live: true, accepting: true }))),
                  "", ctlResumeRunning, "", "accepting true")
    checkControls(Runs.controls(Runs.normalizeRun(raw(null))), ctlPauseNotRunning, "", "", "no lease: dead")
  }

  // [type, sentence] for every am control error controlError knows.
  function controlErrorTable() {
    return [
      ["UnknownRunError", "The run no longer exists"],
      ["NotRunningError", "The run is not running"],
      ["DeadRunError", "The run's process has died; resume it instead"],
      ["NotAcceptingError", ctlIntegrate],
      ["RunIsLiveError", "The run is still live; only a dead run can be resumed"],
      ["NotResumableError", "The run cannot be resumed"],
      ["ClaimedError", "Another run has already claimed this work"],
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
  }

  function test_control_error_table() {
    var table = controlErrorTable()
    compare(table.length, 8)
    for (var i = 0; i < table.length; i++)
      compare(Runs.controlError({ ok: false, error: { type: table[i][0], message: "am said so" } }), table[i][1],
              table[i][0])
    compare(Runs.controlError({ ok: false, error: { type: "NotAcceptingError", message: "m" } }),
            "Integrate is running; it cannot be paused or cancelled", "same text as the Integrate reason")
  }

  function test_control_error_shapes() {
    var table = controlErrorTable()
    for (var i = 0; i < table.length; i++) {
      compare(Runs.controlError({ type: table[i][0], message: "x" }), table[i][1], "bare " + table[i][0])
      compare(Runs.controlError({ type: table[i][0] }), table[i][1], "bare, no message " + table[i][0])
    }
    compare(Runs.controlError({ ok: false, error: { type: "  ClaimedError  ", message: "m" } }),
            "Another run has already claimed this work", "type is trimmed")
    compare(Runs.controlError({ type: "\tLockTimeoutError\n" }), "am is busy; try again in a moment", "trimmed, bare")
    compare(Runs.controlError({ ok: false, error: { type: "DeadRunError", message: "pid 42 is gone" } }),
            "The run's process has died; resume it instead", "the message is not shown for a known type")
    compare(Runs.controlError({ ok: false, error: { type: "claimederror", message: "m" } }), "claimederror: m",
            "case-sensitive")
    compare(Runs.controlError({ type: "CLAIMEDERROR" }), "CLAIMEDERROR", "case-sensitive, bare")
    compare(Runs.controlError({ ok: false, type: "ClaimedError", error: { type: "Foo", message: "bar" } }), "Foo: bar",
            "the envelope's error wins over a stray outer type, as in errorText")
    var bare = Object.create(null)
    bare.type = "ClaimedError"
    compare(Runs.controlError(bare), "Another run has already claimed this work", "prototype-less bare error")
  }

  function test_control_error_fallback() {
    compare(Runs.controlError({ ok: false, error: { type: "Foo", message: "bar" } }), "Foo: bar", "unknown type")
    compare(Runs.controlError({ ok: false, error: { type: "Foo" } }), "Foo", "type only")
    compare(Runs.controlError({ ok: false, error: { message: "bar" } }), "bar", "message only")
    compare(Runs.controlError({ ok: true, error: { type: "ClaimedError", message: "m" } }), "", "ok:true with an error")
    compare(Runs.controlError({ ok: true }), "", "ok:true")

    var garbage = [undefined, null, "boom", 5, true, [], { ok: false }, {}, { ok: false, error: "ClaimedError" },
                   { ok: false, error: { type: "", message: "  " } }, Object.create(null)]
    for (var i = 0; i < garbage.length; i++)
      compare(Runs.controlError(garbage[i]), "unknown error", "garbage " + i)

    var protoNames = ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]
    for (var k = 0; k < protoNames.length; k++) {
      var name = protoNames[k]
      compare(Runs.controlError({ ok: false, error: { type: name, message: "m" } }), name + ": m", "envelope " + name)
      compare(Runs.controlError({ type: name }), name, "bare " + name)
      compare(typeof Runs.controlError({ type: name }), "string", "a string for " + name)
    }

    var noProto = Object.create(null)
    compare(Runs.controlError({ ok: false, error: { type: noProto, message: "m" } }), "m",
            "a prototype-less type object reads as no type")
    compare(Runs.controlError({ type: noProto }), "unknown error", "a prototype-less type object alone")
  }

  // ---- S2 1.2: run alerts ------------------------------------------------------------------

  // A tree whose subtask t1 failed review: escalationReason gives "escalated at review".
  function alTree() {
    return { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "review", status: "failed" }] }] }
  }
  function alRunning(id) { return mkRun(id, "started", true) }
  function alDead(id) { return mkRun(id, "started", false) }
  function alEscalated(id) { return mkRun(id, "escalated", null, { tree: alTree() }) }

  // The alerts' ids (or states), comma-joined, in order.
  function alIds(alerts) {
    var out = []
    for (var i = 0; i < alerts.length; i++) out.push(alerts[i].id)
    return out.join(",")
  }
  function alStates(alerts) {
    var out = []
    for (var i = 0; i < alerts.length; i++) out.push(alerts[i].state)
    return out.join(",")
  }

  function checkAlert(a, id, title, state, reason, label) {
    compare(Object.keys(a).sort().join(","), "id,reason,state,title", label + " keys")
    compare(a.id, id, label + " id")
    compare(a.title, title, label + " title")
    compare(a.state, state, label + " state")
    compare(a.reason, reason, label + " reason")
  }

  function test_new_alerts_first_snapshot() {
    var next = [alEscalated("r1"), alDead("r2")]
    var prevs = [null, undefined, 5, "x", {}, Object.create(null), true]
    for (var i = 0; i < prevs.length; i++) {
      var a = Runs.newAlerts(prevs[i], next)
      compare(Array.isArray(a), true, "an array for prev " + i)
      compare(a.length, 0, "no alerts for prev " + i)
    }
    compare(Runs.newAlerts(null, []).length, 0, "null prev, empty next")
  }

  function test_new_alerts_entering_escalated() {
    var id = "run-20261004-0123456789abcdef"
    var a = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", null, { tree: alTree() })])
    compare(a.length, 1, "one alert")
    checkAlert(a[0], id, "m1", "escalated", "escalated at review", "with milestone")

    var b = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", null, { milestone_id: "", tree: alTree() })])
    compare(b.length, 1, "one alert without a milestone")
    checkAlert(b[0], id, "…89abcdef", "escalated", "escalated at review", "short id title")

    var detailTree = { stories: [], subtasks: [{ card_id: "t1",
                       phases: [{ name: "review", status: "failed", detail: "3 tests failed" }] }] }
    var c = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", true, { tree: detailTree })])
    compare(c.length, 1, "one alert with a detail")
    checkAlert(c[0], id, "m1", "escalated", "3 tests failed", "detail reason")

    var d = Runs.newAlerts([alRunning(id)], [mkRun(id, "escalated", null)])
    compare(d.length, 1, "one alert with no tree")
    compare(d[0].reason, "escalated", "bare escalated reason")
  }

  function test_new_alerts_entering_dead() {
    var a = Runs.newAlerts([alRunning("r1")], [mkRun("r1", "started", false)])
    compare(a.length, 1, "running -> dead (live false)")
    checkAlert(a[0], "r1", "m1", "dead", "process died", "live false")

    var b = Runs.newAlerts([mkRun("r1", "stopped", null)], [mkRun("r1", "started", null)])
    compare(b.length, 1, "parked -> dead (lease null)")
    checkAlert(b[0], "r1", "m1", "dead", "process died", "lease null")

    var c = Runs.newAlerts([alRunning("r1")], [mkRun("r1", "started", false, { tree: alTree() })])
    compare(c.length, 1, "dead with a failed phase")
    compare(c[0].reason, "process died", "never the escalation text")
  }

  function test_new_alerts_from_each_state() {
    var froms = [["parked", mkRun("r", "stopped", null)], ["cancelled", mkRun("r", "cancelled", null)],
                 ["done", mkRun("r", "done", null)], ["unknown", mkRun("r", "weird", true)],
                 ["running", alRunning("r")]]
    for (var i = 0; i < froms.length; i++) {
      var e = Runs.newAlerts([froms[i][1]], [alEscalated("r")])
      compare(e.length, 1, froms[i][0] + " -> escalated")
      compare(e[0].state, "escalated", froms[i][0] + " -> escalated state")
      var d = Runs.newAlerts([froms[i][1]], [alDead("r")])
      compare(d.length, 1, froms[i][0] + " -> dead")
      compare(d[0].state, "dead", froms[i][0] + " -> dead state")
    }

    var quiet = [["parked", mkRun("r", "stopped", null)], ["running", alRunning("r")],
                 ["cancelled", mkRun("r", "cancelled", null)], ["done", mkRun("r", "done", null)],
                 ["unknown", mkRun("r", "weird", true)]]
    for (var j = 0; j < quiet.length; j++) {
      compare(Runs.newAlerts([alRunning("r")], [quiet[j][1]]).length, 0, "running -> " + quiet[j][0])
      compare(Runs.newAlerts([alEscalated("r")], [quiet[j][1]]).length, 0, "escalated -> " + quiet[j][0])
      compare(Runs.newAlerts([alDead("r")], [quiet[j][1]]).length, 0, "dead -> " + quiet[j][0])
    }
  }

  function test_new_alerts_already_in_state() {
    compare(Runs.newAlerts([alEscalated("r")], [alEscalated("r")]).length, 0, "escalated -> escalated")
    compare(Runs.newAlerts([mkRun("r", "escalated", null)], [alEscalated("r")]).length, 0,
            "escalated -> escalated with a new reason")
    compare(Runs.newAlerts([alDead("r")], [alDead("r")]).length, 0, "dead -> dead")
    compare(Runs.newAlerts([mkRun("r", "started", false)], [mkRun("r", "started", null)]).length, 0,
            "dead (live false) -> dead (lease null)")
  }

  function test_new_alerts_switch_between() {
    var a = Runs.newAlerts([alEscalated("r")], [mkRun("r", "started", false, { tree: alTree() })])
    compare(a.length, 1, "escalated -> dead")
    checkAlert(a[0], "r", "m1", "dead", "process died", "escalated -> dead")

    var b = Runs.newAlerts([alDead("r")], [alEscalated("r")])
    compare(b.length, 1, "dead -> escalated")
    checkAlert(b[0], "r", "m1", "escalated", "escalated at review", "dead -> escalated")
  }

  function test_new_alerts_one_per_transition() {
    var next = [alEscalated("a"), alDead("b"), alRunning("c")]
    compare(Runs.newAlerts(next, next).length, 0, "same snapshot twice")

    var snaps = [[alRunning("r")], [alEscalated("r")], [alEscalated("r")], [alRunning("r")], [alEscalated("r")]]
    var expected = [1, 0, 0, 1]
    for (var i = 0; i < expected.length; i++)
      compare(Runs.newAlerts(snaps[i], snaps[i + 1]).length, expected[i], "s" + i + " -> s" + (i + 1))
  }

  function test_new_alerts_absent_and_vanished() {
    var e = Runs.newAlerts([], [alEscalated("r")])
    compare(e.length, 1, "empty prev, escalated next")
    compare(e[0].state, "escalated", "empty prev state")
    var d = Runs.newAlerts([], [alDead("r")])
    compare(d.length, 1, "empty prev, dead next")
    compare(d[0].state, "dead", "empty prev dead state")
    compare(alIds(Runs.newAlerts([alRunning("other")], [alEscalated("r")])), "r", "id not in prev")

    compare(Runs.newAlerts([alEscalated("r")], []).length, 0, "vanished escalated run")
    compare(Runs.newAlerts([alEscalated("r"), alDead("d")], [alRunning("x")]).length, 0, "vanished runs")

    var mix = Runs.newAlerts([alRunning("a"), alEscalated("b"), alRunning("c")],
                             [alEscalated("a"), alEscalated("b"), alRunning("c")])
    compare(alIds(mix), "a", "only the entering run")

    var two = Runs.newAlerts([alRunning("a"), alRunning("b"), alRunning("c")],
                             [alDead("c"), alRunning("b"), alEscalated("a")])
    compare(alIds(two), "c,a", "nextRuns order")
    compare(alStates(two), "dead,escalated", "states in nextRuns order")
  }

  function test_new_alerts_ids() {
    var names = ["__proto__", "constructor", "toString"]
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      compare(Runs.newAlerts([alEscalated(n)], [alEscalated(n)]).length, 0, n + " already escalated")
      compare(Runs.newAlerts([alDead(n)], [alDead(n)]).length, 0, n + " already dead")
      var entering = Runs.newAlerts([alRunning(n)], [alEscalated(n)])
      compare(entering.length, 1, n + " entering")
      compare(entering[0].id, n, n + " id")
      compare(alIds(Runs.newAlerts([alEscalated("other")], [alEscalated(n)])), n, n + " absent from prev")
    }

    compare(Runs.newAlerts([], [mkRun("", "escalated", null)]).length, 0, "empty id")
    compare(Runs.newAlerts([], [mkRun(5, "escalated", null)]).length, 0, "number id")
    compare(Runs.newAlerts([], [mkRun(null, "started", false)]).length, 0, "null id")
    var noId = alEscalated("x")
    delete noId.id
    compare(Runs.newAlerts([], [noId]).length, 0, "missing id")

    var dup = Runs.newAlerts([], [alEscalated("r"), alEscalated("r")])
    compare(dup.length, 1, "duplicate id in next")
    var firstQualifying = Runs.newAlerts([], [alRunning("r"), alEscalated("r"), alDead("r")])
    compare(firstQualifying.length, 1, "one alert for three occurrences")
    compare(firstQualifying[0].state, "escalated", "from the first qualifying occurrence")

    compare(Runs.newAlerts([alEscalated("r"), alRunning("r")], [alEscalated("r")]).length, 0,
            "duplicate id in prev: first occurrence (escalated) wins")
    compare(Runs.newAlerts([alRunning("r"), alEscalated("r")], [alEscalated("r")]).length, 1,
            "duplicate id in prev: first occurrence (running) wins")
  }

  function test_new_alerts_garbage() {
    var nexts = [null, undefined, 5, "x", {}, Object.create(null), true]
    for (var i = 0; i < nexts.length; i++) {
      var a = Runs.newAlerts([], nexts[i])
      compare(Array.isArray(a), true, "an array for next " + i)
      compare(a.length, 0, "no alerts for next " + i)
    }

    var bare = Object.create(null)
    var prev = [null, 5, "x", [], bare, alRunning("a"), undefined]
    var next = [null, alEscalated("a"), 5, "x", [], bare, alDead("b"), undefined]
    var mixed = Runs.newAlerts(prev, next)
    compare(alIds(mixed), "a,b", "real runs alert, garbage skipped")
    compare(alStates(mixed), "escalated,dead", "garbage skipped, states")

    var np = Object.create(null)
    np.id = "np"
    np.status = "escalated"
    var fromBare = Runs.newAlerts([bare], [np])
    compare(fromBare.length, 1, "a prototype-less run with an id alerts")
    checkAlert(fromBare[0], "np", "…np", "escalated", "escalated", "prototype-less run")

    // synthetic: garbage, and a bare am runs row with an escalated am status run
    compare(Runs.newAlerts([], [Runs.normalizeRun(undefined)]).length, 0, "normalised garbage")
    var normalised = Runs.normalizeRun({ row: { id: "rz", status: "started" },
                                         status: { run: { milestone_id: "m9", status: "escalated" } } })
    var fromNormalised = Runs.newAlerts([], [normalised])
    compare(fromNormalised.length, 1, "a normalised escalated run")
    checkAlert(fromNormalised[0], "rz", "m9", "escalated", "escalated", "normalised run")
  }

  function test_new_alerts_fresh_and_pure() {
    var prev = [alRunning("a"), alEscalated("b")]
    var next = [alEscalated("a"), alEscalated("b"), alDead("c")]
    var prevJson = JSON.stringify(prev)
    var nextJson = JSON.stringify(next)

    var x = Runs.newAlerts(prev, next)
    var y = Runs.newAlerts(prev, next)
    compare(alIds(x), "a,c", "first call")
    verify(x !== y, "distinct arrays")
    verify(x[0] !== y[0], "distinct alert objects")
    verify(x[1] !== y[1], "distinct alert objects (second)")

    x[0].title = "changed"
    x[0].reason = "changed"
    x.push({ id: "junk" })
    var z = Runs.newAlerts(prev, next)
    compare(alIds(z), "a,c", "mutating a result does not change the next one")
    checkAlert(z[0], "a", "m1", "escalated", "escalated at review", "after mutation")

    compare(JSON.stringify(prev), prevJson, "prevRuns unchanged")
    compare(JSON.stringify(next), nextJson, "nextRuns unchanged")
    compare(prev.length, 2, "prevRuns length")
    compare(next.length, 3, "nextRuns length")
  }

  // ---- S2 4.1: workflow and control requests ----------------------------------------------

  function test_normalize_workflow() {
    compare(Runs.normalizeRun(amRun("status-started.json")).workflow, "milestone", "from the am runs row")
    // synthetic: the capture's row and run workflows edited to each combination
    var raw = amRun("status-started.json")
    delete raw.row.workflow
    raw.status.run.workflow = "task"
    compare(Runs.normalizeRun(raw).workflow, "task", "falls back to the am status run")
    raw.row.workflow = "milestone"
    compare(Runs.normalizeRun(raw).workflow, "milestone", "the row wins")
    raw.row.workflow = ""
    compare(Runs.normalizeRun(raw).workflow, "task", "an empty row value falls back")
    delete raw.row.workflow
    delete raw.status.run.workflow
    compare(Runs.normalizeRun(raw).workflow, "", "neither gives empty")
    // synthetic: null workflows, and garbage
    compare(Runs.normalizeRun({ row: { workflow: null }, status: { run: { workflow: null } } }).workflow, "", "nulls")
    compare(Runs.normalizeRun(undefined).workflow, "", "garbage")
  }

  function test_normalize_requests() {
    // synthetic: three requests, which no capture contains
    var raw = amRun("status-started.json")
    raw.status.control.requests = [
      { command: "pause", requested_at: "2026-10-03T10:00:00Z", handled_at: "2026-10-03T10:00:05Z" },
      { command: "resume", requested_at: "2026-10-03T11:00:00Z", handled_at: null },
      { command: "cancel", requested_at: "2026-10-03T12:00:00Z" }
    ]
    var r = Runs.normalizeRun(raw)
    compare(Array.isArray(r.requests), true)
    compare(r.requests.length, 3)
    compare(Object.keys(r.requests[0]).sort().join(","), "command,handled_at,requested_at")
    compare(r.requests[0].command, "pause")
    compare(r.requests[0].requested_at, "2026-10-03T10:00:00Z")
    compare(r.requests[0].handled_at, "2026-10-03T10:00:05Z")
    compare(r.requests[1].command, "resume", "order is kept")
    compare(r.requests[1].handled_at, "", "null means not handled")
    compare(r.requests[2].command, "cancel")
    compare(r.requests[2].handled_at, "", "missing means not handled")
    r.requests[0].command = "x"
    compare(raw.status.control.requests[0].command, "pause", "the elements are fresh objects")
    compare(Runs.normalizeRun(amRun("status-started.json")).requests.length, 0, "the capture's requests are []")
    // synthetic: the capture's control without its requests key
    var noRequests = amRun("status-started.json")
    delete noRequests.status.control.requests
    var nr = Runs.normalizeRun(noRequests)
    compare(Array.isArray(nr.requests), true, "no requests key under control")
    compare(nr.requests.length, 0, "no requests key under control")
  }

  // Review Focus 4.
  function test_normalize_requests_garbage() {
    // synthetic: garbage request elements in place of the capture's []
    var raw = amRun("status-started.json")
    raw.status.control.requests = [null, "pause", 7, ["pause"], true,
                                   { command: 5, requested_at: true, handled_at: { a: 1 } }, {}]
    var r = Runs.normalizeRun(raw)
    compare(r.requests.length, 2, "non-object elements are skipped")
    compare(r.requests[0].command, "5")
    compare(r.requests[0].requested_at, "true")
    compare(r.requests[0].handled_at, "[object Object]")
    compare(r.requests[1].command, "")
    compare(r.requests[1].requested_at, "")
    compare(r.requests[1].handled_at, "")

    // synthetic: am status without control
    var noControl = amRun("status-started.json")
    delete noControl.status.control
    compare(Runs.normalizeRun(noControl).requests.length, 0, "no control")
    // synthetic: requests that are not a list
    var values = ["x", { a: 1 }, null, 5]
    for (var i = 0; i < values.length; i++) {
      var bad = amRun("status-started.json")
      bad.status.control.requests = values[i]
      var out = Runs.normalizeRun(bad)
      compare(Array.isArray(out.requests), true, "requests " + i)
      compare(out.requests.length, 0, "requests " + i)
    }
    // synthetic: control that is not an object
    compare(Runs.normalizeRun({ status: { control: "y" } }).requests.length, 0, "control not an object")
  }

  // ---- S3 1.1: dispatch -------------------------------------------------------------------

  function mkCard(id, depth, status, parentId, title) {
    return { id: id, depth: depth, status: status, parentId: parentId, title: title }
  }

  // Asserts a dispatchPlan result field by field; suggest compared as JSON.
  function checkPlan(p, offered, level, command, flags, reason, suggest, label) {
    compare(Object.keys(p).sort().join(","), "command,flags,level,offered,reason,suggest", label + " keys")
    compare(p.offered, offered, label + " offered")
    compare(p.level, level, label + " level")
    compare(p.command, command, label + " command")
    compare(Array.isArray(p.flags), true, label + " flags is array")
    compare(JSON.stringify(p.flags), JSON.stringify(flags), label + " flags")
    compare(p.reason, reason, label + " reason")
    compare(JSON.stringify(p.suggest), JSON.stringify(suggest), label + " suggest")
  }

  function test_dispatchPlan_shape() {
    var inputs = [mkCard("m1", 0, "todo", null, "M3 Document runs"), mkCard("s1", 1, "todo", "m1", "S"), undefined]
    for (var i = 0; i < inputs.length; i++) {
      var a = Runs.dispatchPlan(inputs[i])
      var b = Runs.dispatchPlan(inputs[i])
      compare(Object.keys(a).sort().join(","), "command,flags,level,offered,reason,suggest", "keys " + i)
      verify(a !== b, "distinct objects " + i)
      verify(a.flags !== b.flags, "distinct flags arrays " + i)
    }
    var first = Runs.dispatchPlan(inputs[0])
    first.flags.push("--evil")
    first.flags[1] = "x"
    compare(JSON.stringify(Runs.dispatchPlan(inputs[0]).flags), JSON.stringify(["--milestone", "m1"]), "mutation does not leak")
    var board = Runs.dispatchPlan("board")
    board.flags.push("--evil")
    compare(JSON.stringify(Runs.dispatchPlan("board").flags), JSON.stringify(["--board"]), "board flags fresh")
    var story = Runs.dispatchPlan(inputs[1])
    compare(JSON.stringify(story.flags), JSON.stringify(["--story", "s1"]), "the story input is offered")
  }

  function test_dispatchPlan_milestone() {
    var statuses = ["todo", "in_progress", "blocked", undefined]
    for (var i = 0; i < statuses.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("m1", 0, statuses[i], null, "M3")),
                true, "milestone", "milestone", ["--milestone", "m1"], "", null, "status " + statuses[i])
    }
  }

  function test_dispatchPlan_subtask() {
    checkPlan(Runs.dispatchPlan(mkCard("c1", 2, "todo", "s1", "C")),
              true, "subtask", "card", ["--card", "c1"], "", null, "depth 2")
    checkPlan(Runs.dispatchPlan(mkCard("c2", 3, "in_progress", "c1", "D")),
              true, "subtask", "card", ["--card", "c2"], "", null, "depth 3")
  }

  function test_dispatchPlan_board() {
    checkPlan(Runs.dispatchPlan("board"), true, "board", "board", ["--board"], "", null, "board")
    checkPlan(Runs.dispatchPlan("board", { m1: mkCard("m1", 0, "todo", null, "M") }),
              true, "board", "board", ["--board"], "", null, "board ignores cardMap")
    var near = ["Board", " board", "board "]
    for (var i = 0; i < near.length; i++) {
      checkPlan(Runs.dispatchPlan(near[i]), false, "", "", [], "No card to dispatch", null, "near '" + near[i] + "'")
    }
  }

  function test_dispatchPlan_story() {
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs") }
    var statuses = ["todo", "in_progress", "blocked", undefined]
    for (var i = 0; i < statuses.length; i++) {
      var story = mkCard("s1", 1, statuses[i], "m1", "Story")
      map.s1 = story
      checkPlan(Runs.dispatchPlan(story, map), true, "story", "story", ["--story", "s1"], "", null,
                "status " + statuses[i])
    }
  }

  // Review Focus 1.
  function test_dispatchPlan_story_ignores_parent() {
    var story = mkCard("s1", 1, "todo", "m1", "Story")
    var maps = [undefined, { s1: story }, { m1: "M3" }, { m1: mkCard("m1", 0, "todo", null, Object.create(null)) },
                { m1: mkCard("m1", 0, "todo", null, 7) }, { m1: mkCard("m1", 0, "todo", null, null) }]
    for (var i = 0; i < maps.length; i++) {
      checkPlan(Runs.dispatchPlan(story, maps[i]), true, "story", "story", ["--story", "s1"], "", null, "cardMap " + i)
    }
    var parents = [null, "", 5, "__proto__", undefined]
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs") }
    for (var j = 0; j < parents.length; j++) {
      checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "todo", parents[j], "S"), map), true, "story", "story",
                ["--story", "s1"], "", null, "parentId " + parents[j])
    }
  }

  function test_dispatchPlan_story_fresh() {
    var story = mkCard("s1", 1, "todo", "m1", "Story")
    var map = { m1: mkCard("m1", 0, "todo", null, "M3 Document runs"), s1: story }
    var before = JSON.stringify(map)
    var a = Runs.dispatchPlan(story, map)
    var b = Runs.dispatchPlan(story, map)
    verify(a !== b, "distinct objects")
    verify(a.flags !== b.flags, "distinct flags arrays")
    a.flags.push("--evil")
    a.flags[1] = "x"
    compare(JSON.stringify(b.flags), JSON.stringify(["--story", "s1"]), "the other result is untouched")
    compare(JSON.stringify(Runs.dispatchPlan(story, map).flags), JSON.stringify(["--story", "s1"]), "mutation does not leak")
    compare(JSON.stringify(map), before, "cardMap unchanged")
  }

  function test_dispatchPlan_finished() {
    var statuses = ["done", "merged", "canceled", "archived"]
    var levels = ["milestone", "story", "subtask"]
    var map = { m1: mkCard("m1", 0, "todo", null, "M3") }
    for (var i = 0; i < statuses.length; i++) {
      for (var d = 0; d < 3; d++) {
        checkPlan(Runs.dispatchPlan(mkCard("x1", d, statuses[i], "m1", "X"), map), false, levels[d], "", [],
                  "The card is " + statuses[i], null, statuses[i] + " depth " + d)
      }
    }
    compare(Runs.dispatchPlan(mkCard("s1", 1, "done", "m1", "S"), map).reason, "The card is done", "exact sentence")
    checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "blocked", "m1", "S"), map), true, "story", "story",
              ["--story", "s1"], "", null, "blocked is not finished")
    checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "merged", "m1", "S"), { m1: map.m1, s1: mkCard("s1", 1, "merged", "m1", "S") }),
              false, "story", "", [], "The card is merged", null, "a finished story with its milestone in cardMap")
    checkPlan(Runs.dispatchPlan(mkCard("m1", 0, "Done", null, "M")), true, "milestone", "milestone",
              ["--milestone", "m1"], "", null, "Done is not finished")
    checkPlan(Runs.dispatchPlan(mkCard("m1", 0, " done", null, "M")), true, "milestone", "milestone",
              ["--milestone", "m1"], "", null, "' done' is not finished")
  }

  function test_dispatchPlan_bad_id() {
    var ids = [undefined, "", 5, null, {}, "-x", "--board"]
    for (var i = 0; i < ids.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard(ids[i], 0, "todo", null, "M")), false, "", "", [],
                "No card to dispatch", null, "id " + i)
    }
    var noId = { depth: 0, status: "todo", parentId: null, title: "M" }
    checkPlan(Runs.dispatchPlan(noId), false, "", "", [], "No card to dispatch", null, "id missing")
    checkPlan(Runs.dispatchPlan(mkCard("a b", 2, "todo", "s1", "C")), true, "subtask", "card",
              ["--card", "a b"], "", null, "id used verbatim")
    checkPlan(Runs.dispatchPlan(mkCard(" m1 ", 0, "todo", null, "M")), true, "milestone", "milestone",
              ["--milestone", " m1 "], "", null, "id not trimmed")
  }

  function test_dispatchPlan_unknown_level() {
    var depths = [undefined, -1, 1.5, NaN, Infinity, "0", null]
    for (var i = 0; i < depths.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("x1", depths[i], "todo", null, "X")), false, "", "", [],
                "The card's level is unknown", null, "depth " + depths[i])
    }
    var noDepth = { id: "x1", status: "todo" }
    checkPlan(Runs.dispatchPlan(noDepth), false, "", "", [], "The card's level is unknown", null, "depth missing")
    checkPlan(Runs.dispatchPlan(mkCard("x1", -1, "done", null, "X")), false, "", "", [],
              "The card's level is unknown", null, "level checked before status")
  }

  function test_dispatchPlan_garbage() {
    var cards = [undefined, null, 0, true, "x", [], {}, Object.create(null)]
    for (var i = 0; i < cards.length; i++) {
      checkPlan(Runs.dispatchPlan(cards[i]), false, "", "", [], "No card to dispatch", null, "card " + i)
    }
    checkPlan(Runs.dispatchPlan(), false, "", "", [], "No card to dispatch", null, "no arguments")
    var story = mkCard("s1", 1, "todo", "m1", "S")
    var bare = Object.create(null)
    bare.m1 = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var maps = [null, "x", [], Object.create(null), bare]
    for (var j = 0; j < maps.length; j++) {
      checkPlan(Runs.dispatchPlan(story, maps[j]), true, "story", "story", ["--story", "s1"], "", null, "cardMap " + j)
    }
  }

  function test_dispatchPlan_proto_ids() {
    var ids = ["__proto__", "constructor", "toString"]
    for (var i = 0; i < ids.length; i++) {
      checkPlan(Runs.dispatchPlan(mkCard("s1", 1, "todo", ids[i], "S"), { m1: mkCard("m1", 0, "todo", null, "M") }),
                true, "story", "story", ["--story", "s1"], "", null, "parentId " + ids[i])
      checkPlan(Runs.dispatchPlan(mkCard(ids[i], 1, "todo", "m1", "S")), true, "story", "story",
                ["--story", ids[i]], "", null, "story id " + ids[i])
    }
  }

  function fullProject() {
    return { defaultBranch: "main",
             settings: { verify: ["uv run pytest", "bash tests/run.sh"], allowNoVerification: true,
                         notifyOnEscalation: true, parallelism: 2 } }
  }

  // Asserts all five dispatchDefaults fields; verify compared as JSON.
  function checkDefaults5(d, base, parallelism, prefix, verifyList, label) {
    compare(Object.keys(d).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify", label + " keys")
    compare(d.allowNoVerification, false, label + " allowNoVerification")
    compare(d.base, base, label + " base")
    compare(d.parallelism, parallelism, label + " parallelism")
    compare(d.prefix, prefix, label + " prefix")
    compare(Array.isArray(d.verify), true, label + " verify is array")
    compare(JSON.stringify(d.verify), JSON.stringify(verifyList), label + " verify")
  }

  function prefixOf(title) {
    return Runs.dispatchDefaults({}, mkCard("m1", 0, "todo", null, title)).prefix
  }

  function test_dispatchDefaults_shape() {
    var project = fullProject()
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    checkDefaults5(Runs.dispatchDefaults(project, m), "main", 2, "m3", ["uv run pytest", "bash tests/run.sh"], "full")
    checkDefaults5(Runs.dispatchDefaults(undefined, undefined, undefined), "", 4, "", [], "garbage")
    var a = Runs.dispatchDefaults(project, m)
    var b = Runs.dispatchDefaults(project, m)
    verify(a !== b, "distinct objects")
    verify(a.verify !== b.verify, "distinct verify arrays")
    verify(a.verify !== project.settings.verify, "verify is not the settings array")
    a.verify.push("rm -rf /")
    a.verify[0] = "x"
    compare(JSON.stringify(project.settings.verify), JSON.stringify(["uv run pytest", "bash tests/run.sh"]), "settings.verify unchanged")
    compare(JSON.stringify(Runs.dispatchDefaults(project, m).verify), JSON.stringify(["uv run pytest", "bash tests/run.sh"]), "next result unchanged")
  }

  function test_dispatchDefaults_base() {
    compare(Runs.dispatchDefaults({ defaultBranch: "main" }).base, "main", "main")
    compare(Runs.dispatchDefaults({ defaultBranch: "  trunk \n" }).base, "trunk", "trimmed")
    var bad = [undefined, null, 5, {}]
    for (var i = 0; i < bad.length; i++) {
      compare(Runs.dispatchDefaults({ defaultBranch: bad[i] }).base, "", "defaultBranch " + i)
    }
    compare(Runs.dispatchDefaults({}).base, "", "defaultBranch missing")
    var projects = [undefined, null, 0, "main", [], Object.create(null)]
    for (var j = 0; j < projects.length; j++) {
      compare(Runs.dispatchDefaults(projects[j]).base, "", "project " + j)
    }
  }

  function test_dispatchDefaults_prefix_stem() {
    var cases = [
      ["M3 Document runs", "m3"],
      ["M3: Document", "m3"],
      ["s12 Polish", "s12"],
      ["am run monitor (read-only)", "am-run-monitor"],
      ["Dispatching am runs from the panel", "dispatching-am-runs"],
      ["Milestone 3", "milestone-3"],
      ["Internationalization localization globalization", "internationalization-loc"],
      ["-- ** --", ""]
    ]
    for (var i = 0; i < cases.length; i++) {
      compare(prefixOf(cases[i][0]), cases[i][1], "'" + cases[i][0] + "'")
    }
    compare(prefixOf(undefined), "", "title missing")
    compare(prefixOf(null), "", "title null")
    compare(prefixOf(5), "5", "title 5")
    compare(Runs.dispatchDefaults({}, { id: "m1", depth: 0 }).prefix, "", "no title key")
  }

  // Review Focus 3 and 4.
  function test_dispatchDefaults_prefix_stem_edges() {
    compare(prefixOf("abcdefghijklmnopqrstuvw xyz"), "abcdefghijklmnopqrstuvw", "cut after a hyphen drops the hyphen")
    compare(prefixOf("Caf\u00e9 d\u00e9j\u00e0 vu"), "caf-dj-vu", "non-ASCII letters are dropped")
    compare(prefixOf("   "), "", "blank title")
    compare(prefixOf("M3\tDocument\nruns"), "m3", "any whitespace splits")
    compare(prefixOf("3M Polish"), "3m-polish", "digits first is not a stem")
    compare(prefixOf(Object.create(null)), "", "unconvertible title")
  }

  function test_dispatchDefaults_prefix_ancestor() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Story")
    var c = mkCard("c1", 2, "todo", "s1", "Subtask")
    var map = { m1: m, s1: s, c1: c }
    compare(Runs.dispatchDefaults({}, s, map).prefix, "m3", "story")
    compare(Runs.dispatchDefaults({}, c, map).prefix, "m3", "subtask")
    compare(Runs.dispatchDefaults({}, s).prefix, "", "story without cardMap")
    compare(Runs.dispatchDefaults({}, c).prefix, "", "subtask without cardMap")
    compare(Runs.dispatchDefaults({}, c, { s1: s, c1: c }).prefix, "", "broken chain")
    var a = mkCard("a", 1, "todo", "b", "A")
    var b = mkCard("b", 1, "todo", "a", "B")
    compare(Runs.dispatchDefaults({}, a, { a: a, b: b }).prefix, "", "two-card cycle")
    compare(Runs.dispatchDefaults({}, "board", map).prefix, "", "board")
    compare(Runs.dispatchDefaults({}, mkCard("c1", 2, "done", "s1", "Subtask"), map).prefix, "m3", "own status ignored")
    compare(Runs.dispatchDefaults({}, mkCard("m1", 0, "archived", null, "M3 Document runs")).prefix, "m3", "finished milestone still gives a prefix")
  }

  // Review Focus 2 and 5.
  function test_dispatchDefaults_prefix_ancestor_edges() {
    var loop = mkCard("x", 1, "todo", "x", "M3 Self")
    compare(Runs.dispatchDefaults({}, loop, { x: loop }).prefix, "", "self cycle")
    var stray = mkCard("m1", 0, "todo", "zz", "M3 Document runs")
    compare(Runs.dispatchDefaults({}, stray).prefix, "m3", "depth 0 with a stray parentId is its own milestone")
    var top = mkCard("t", 1, "todo", null, "S7 Top")
    var child = mkCard("c", 2, "todo", "t", "C")
    compare(Runs.dispatchDefaults({}, child, { t: top, c: child }).prefix, "s7", "walk ends at the parentless card whatever its depth")
    compare(Runs.dispatchDefaults({}, mkCard("o", undefined, "todo", null, "S8 Orphan"), {}).prefix, "s8", "no parentId and no depth: own milestone")
    compare(Runs.dispatchDefaults({}, mkCard("o", 1, "todo", "", "S9 Orphan"), {}).prefix, "s9", "empty parentId ends the walk")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", "__proto__", "C"), {}).prefix, "", "__proto__ parent is absent")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", "toString", "C"), {}).prefix, "", "toString parent is absent")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", "m1", "C"), { m1: "M3" }).prefix, "", "non-object entry")
    compare(Runs.dispatchDefaults({}, mkCard("c", 2, "todo", 5, "C"), { "5": mkCard("5", 0, "todo", null, "M5 Five") }).prefix,
            "", "a non-string parentId is a missing link")
  }

  function test_dispatchDefaults_verify() {
    var project = { settings: { verify: ["uv run pytest", "  ", "", 5, null, " make test "] } }
    compare(JSON.stringify(Runs.dispatchDefaults(project).verify), JSON.stringify(["uv run pytest", " make test "]), "filtered, verbatim, in order")
    var bad = [undefined, "x", {}]
    for (var i = 0; i < bad.length; i++) {
      compare(JSON.stringify(Runs.dispatchDefaults({ settings: { verify: bad[i] } }).verify), "[]", "verify " + i)
    }
    compare(JSON.stringify(Runs.dispatchDefaults({ settings: {} }).verify), "[]", "verify missing")
    compare(JSON.stringify(Runs.dispatchDefaults({ settings: "x" }).verify), "[]", "settings garbage")
    compare(JSON.stringify(Runs.dispatchDefaults({}).verify), "[]", "no settings")
  }

  function test_dispatchDefaults_allow_no_verification() {
    compare(Runs.dispatchDefaults({ settings: { allowNoVerification: true } }).allowNoVerification, false, "stored true")
    compare(Runs.dispatchDefaults({ settings: {} }).allowNoVerification, false, "absent")
    compare(Runs.dispatchDefaults(null).allowNoVerification, false, "garbage project")
  }

  function test_dispatchDefaults_parallelism() {
    compare(Runs.dispatchDefaults({ settings: { parallelism: 2 } }).parallelism, 2, "2")
    compare(Runs.dispatchDefaults({ settings: { parallelism: 1 } }).parallelism, 1, "1")
    compare(Runs.dispatchDefaults({ settings: { parallelism: 64 } }).parallelism, 64, "no upper cap")
    var bad = [undefined, 0, -3, 2.5, "3", NaN, Infinity, null]
    for (var i = 0; i < bad.length; i++) {
      compare(Runs.dispatchDefaults({ settings: { parallelism: bad[i] } }).parallelism, 4, "parallelism " + bad[i])
    }
    compare(Runs.dispatchDefaults({ settings: {} }).parallelism, 4, "missing")
  }

  function test_dispatchDefaults_garbage() {
    var values = [undefined, null, 0, "x", [], Object.create(null)]
    for (var p = 0; p < values.length; p++) {
      for (var c = 0; c < values.length; c++) {
        for (var m = 0; m < values.length; m++) {
          checkDefaults5(Runs.dispatchDefaults(values[p], values[c], values[m]), "", 4, "", [], "p" + p + " c" + c + " m" + m)
        }
      }
    }
    checkDefaults5(Runs.dispatchDefaults(), "", 4, "", [], "no arguments")
  }

  // Review Focus 1.
  function test_dispatch_inputs_unchanged() {
    var project = fullProject()
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Story")
    var c = mkCard("c1", 2, "todo", "s1", "Subtask")
    var map = { m1: m, s1: s, c1: c }
    var before = JSON.stringify([project, map])
    Runs.dispatchDefaults(project, c, map)
    Runs.dispatchDefaults(project, s, map)
    Runs.dispatchPlan(s, map)
    Runs.dispatchPlan(c, map)
    compare(JSON.stringify([project, map]), before, "project and cardMap unchanged")
    compare(Object.keys(c).sort().join(","), "depth,id,parentId,status,title", "no key added to the card")
  }

  // ---- 1.3: the prefix default --------------------------------------------------------------

  function mkPrefixRun(milestoneId, prefix, startedAt) {
    return { milestone_id: milestoneId, branch_prefix: prefix, started_at: startedAt }
  }

  // Milestone m1 "M3 Document runs" (stem m3), its story s1, the story's subtask c1, and their map.
  function prefixCards() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Story")
    var c = mkCard("c1", 2, "todo", "s1", "Subtask")
    return { m: m, s: s, c: c, map: { m1: m, s1: s, c1: c } }
  }

  // The prefix dispatchDefaults gives card with these settings and runs.
  function prefixWith(settings, card, map, runs) {
    return Runs.dispatchDefaults({ settings: settings }, card, map, runs).prefix
  }

  function test_dispatchDefaults_prefix_history() {
    var f = prefixCards()
    var cards = [f.m, f.s, f.c]
    for (var i = 0; i < cards.length; i++) {
      var id = cards[i].id
      compare(prefixWith({ prefixHistory: ["", "  ", 5, null, "hist-p", "older"] }, cards[i], f.map), "hist-p",
              id + ": the first non-blank string entry")
      var stems = [[], "hist-p", { 0: "x" }, ["", "  ", 5, null], null, undefined]
      for (var j = 0; j < stems.length; j++) {
        compare(prefixWith({ prefixHistory: stems[j] }, cards[i], f.map), "m3", id + ": history " + j + " falls to the stem")
      }
    }
    compare(prefixWith({}, f.s, f.map), "m3", "no history key")
    compare(prefixWith({ prefixHistory: ["hist-p"] }, mkCard("m9", 0, "todo", null, "-- **"), {}), "hist-p",
            "the history before an empty stem")
    compare(prefixWith({}, mkCard("m9", 0, "todo", null, "-- **"), {}), "", "an empty stem stays empty")
    compare(Runs.dispatchDefaults({ settings: "x" }, f.s, f.map).prefix, "m3", "settings garbage")
  }

  function test_dispatchDefaults_prefix_order() {
    var f = prefixCards()
    var cards = [f.m, f.s, f.c]
    var runs = [mkPrefixRun("m1", "run-p", "2026-10-06T10:00:00Z")]
    for (var i = 0; i < cards.length; i++) {
      var id = cards[i].id
      compare(prefixWith({ prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }, cards[i], f.map, runs), "run-p",
              id + ": the run first")
      compare(prefixWith({ prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }, cards[i], f.map, []), "map-p",
              id + ": then the map")
      compare(prefixWith({ prefixByMilestone: {}, prefixHistory: ["hist-p"] }, cards[i], f.map, []), "hist-p",
              id + ": then the history")
      compare(prefixWith({ prefixByMilestone: {}, prefixHistory: [] }, cards[i], f.map, []), "m3", id + ": then the stem")
    }
    compare(Runs.dispatchDefaults({ settings: "x" }, f.s, f.map, runs).prefix, "run-p", "a run needs no settings")
  }

  // Review Focus 1.
  function test_dispatchDefaults_prefix_runs_newest() {
    var f = prefixCards()
    var settings = { prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }
    var older = mkPrefixRun("m1", "older-p", "2026-10-05T10:00:00Z")
    var newer = mkPrefixRun("m1", "newer-p", "2026-10-06T10:00:00Z")
    compare(prefixWith(settings, f.s, f.map, [newer, older]), "newer-p", "newest first")
    compare(prefixWith(settings, f.s, f.map, [older, newer]), "newer-p", "a later started_at wins over the index")
    var stamps = [["2026-10-06T10:00:00Z", "2026-10-06T10:00:00Z"], [undefined, "2026-10-06T10:00:00Z"],
                  ["2026-10-06T10:00:00Z", undefined], [undefined, undefined], ["", "2026-10-06T10:00:00Z"],
                  ["", ""], [5, "2026-10-06T10:00:00Z"], [null, "2026-10-06T10:00:00Z"]]
    for (var i = 0; i < stamps.length; i++) {
      var runs = [mkPrefixRun("m1", "first-p", stamps[i][0]), mkPrefixRun("m1", "second-p", stamps[i][1])]
      compare(prefixWith(settings, f.s, f.map, runs), "first-p", "stamps " + i + ": the lower index wins")
    }
    var bare = { milestone_id: "m1", branch_prefix: "first-p" }
    compare(prefixWith(settings, f.s, f.map, [bare, newer]), "first-p", "no started_at key: the lower index wins")
    var blanks = ["", "  ", null, 5, undefined]
    for (var j = 0; j < blanks.length; j++) {
      compare(prefixWith(settings, f.s, f.map, [mkPrefixRun("m1", blanks[j], "2026-10-07T10:00:00Z"), older]), "older-p",
              "a newer run with prefix " + j + " is skipped")
      compare(prefixWith(settings, f.s, f.map, [older, mkPrefixRun("m1", blanks[j], "2026-10-07T10:00:00Z")]), "older-p",
              "a later-stamped run with prefix " + j + " is skipped")
      compare(prefixWith(settings, f.s, f.map, [mkPrefixRun("m1", blanks[j], "2026-10-07T10:00:00Z")]), "map-p",
              "the only run, with prefix " + j + ", falls to the map")
    }
  }

  // Review Focus 2, 3 and 4.
  function test_dispatchDefaults_prefix_runs_matching() {
    var f = prefixCards()
    var settings = { prefixByMilestone: { m1: "map-p" }, prefixHistory: ["hist-p"] }
    var mine = mkPrefixRun("m1", "run-p", "2026-10-05T10:00:00Z")
    compare(prefixWith(settings, f.m, f.map, [mkPrefixRun("m2", "other-p", "2026-10-07T10:00:00Z"), mine]), "run-p",
            "another milestone's newer run is ignored")
    compare(prefixWith(settings, f.s, f.map, [mkPrefixRun("s1", "story-p", "2026-10-07T10:00:00Z")]), "map-p",
            "a run keyed by the story's own id is ignored")
    compare(prefixWith(settings, f.c, f.map, [mkPrefixRun("c1", "card-p", "2026-10-07T10:00:00Z")]), "map-p",
            "a run keyed by the subtask's own id is ignored")
    var ids = [5, null, undefined, ["m1"], { id: "m1" }, " m1", "m1 ", "M1"]
    for (var i = 0; i < ids.length; i++) {
      compare(prefixWith(settings, f.s, f.map, [mkPrefixRun(ids[i], "bad-p", "2026-10-07T10:00:00Z")]), "map-p",
              "milestone_id " + i + " never matches")
    }
    compare(prefixWith(settings, f.s, f.map, [null, "x", [], 5, Object.create(null), mine]), "run-p", "garbage entries are skipped")
    var lists = [undefined, null, {}, "m1", 5, { 0: mine, length: 1 }]
    for (var j = 0; j < lists.length; j++) {
      compare(prefixWith(settings, f.s, f.map, lists[j]), "map-p", "runs " + j + " is []")
    }
    var sparse = []
    sparse[3] = mine
    compare(prefixWith(settings, f.s, f.map, sparse), "run-p", "holes are skipped")
    compare(prefixWith(settings, f.s, f.map, [{ milestone_id: "m1", branch_prefix: Object.create(null) }]), "map-p",
            "an unconvertible branch_prefix is skipped")
    var states = [{ status: "started", lease: { live: false } }, { status: "started", lease: { live: true } },
                  { status: "done" }, { status: "escalated" }, { status: "canceled" }, { status: "stopped" }, { status: "" }]
    for (var k = 0; k < states.length; k++) {
      var run = mkPrefixRun("m1", "state-p", "2026-10-06T10:00:00Z")
      run.status = states[k].status
      run.lease = states[k].lease
      compare(prefixWith(settings, f.s, f.map, [run]), "state-p", "a run in state " + k + " still names the prefix")
    }
  }

  // Review Focus 3 and 5.
  function test_dispatchDefaults_prefix_map() {
    var f = prefixCards()
    var hist = ["hist-p"]
    compare(prefixWith({ prefixByMilestone: { m2: "other-p" }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "another milestone's entry is ignored")
    compare(prefixWith({ prefixByMilestone: { s1: "story-p" }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "an entry for the story's own id is ignored")
    compare(prefixWith({ prefixByMilestone: { " m1": "a", "m1 ": "b", M1: "c" }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "near-miss keys are ignored")
    var values = ["", "   ", 5, null, ["p"], undefined]
    for (var i = 0; i < values.length; i++) {
      compare(prefixWith({ prefixByMilestone: { m1: values[i] }, prefixHistory: hist }, f.s, f.map, []), "hist-p",
              "value " + i + " falls through")
    }
    var maps = [null, [], "m1", 5, undefined]
    for (var j = 0; j < maps.length; j++) {
      compare(prefixWith({ prefixByMilestone: maps[j], prefixHistory: hist }, f.s, f.map, []), "hist-p", "map " + j + " is skipped")
    }
    compare(prefixWith({ prefixByMilestone: Object.create({ m1: "inh" }), prefixHistory: hist }, f.s, f.map, []), "hist-p",
            "an inherited entry does not match")
    var protoIds = ["constructor", "toString", "__proto__", "hasOwnProperty"]
    for (var k = 0; k < protoIds.length; k++) {
      var m = mkCard(protoIds[k], 0, "todo", null, "M3 Document runs")
      compare(prefixWith({ prefixByMilestone: {}, prefixHistory: hist }, m, {}, []), "hist-p",
              "milestone id " + protoIds[k] + " with a plain map")
    }
    var bare = Object.create(null)
    bare.m1 = "bare-p"
    compare(prefixWith({ prefixByMilestone: bare, prefixHistory: hist }, f.s, f.map, []), "bare-p", "a prototype-less map")
    var own = JSON.parse('{"__proto__": "own-p"}')
    compare(prefixWith({ prefixByMilestone: own, prefixHistory: hist }, mkCard("__proto__", 0, "todo", null, "M3 X"), {}, []),
            "own-p", "an own __proto__ entry matches")
  }

  function test_dispatchDefaults_prefix_trimmed() {
    var f = prefixCards()
    compare(prefixWith({}, f.s, f.map, [mkPrefixRun("m1", "  run-p \n", "2026-10-06T10:00:00Z")]), "run-p", "run")
    compare(prefixWith({ prefixByMilestone: { m1: " map-p " } }, f.s, f.map, []), "map-p", "map")
    compare(prefixWith({ prefixHistory: ["\thist-p "] }, f.s, f.map, []), "hist-p", "history")
    compare(prefixWith({ prefixByMilestone: { m1: " my map-p\n" } }, f.s, f.map, []), "my map-p", "inner whitespace kept")
  }

  function test_dispatchDefaults_prefix_no_milestone() {
    var f = prefixCards()
    var settings = { prefixByMilestone: { m1: "map-p", "": "blank-key-p" }, prefixHistory: ["hist-p"] }
    var runs = [mkPrefixRun("m1", "run-p", "2026-10-06T10:00:00Z"), mkPrefixRun("", "blank-run-p", "2026-10-07T10:00:00Z"),
                mkPrefixRun(undefined, "none-run-p", "2026-10-08T10:00:00Z")]
    compare(prefixWith(settings, "board", f.map, runs), "", "board")
    compare(prefixWith(settings, f.s, undefined, runs), "", "story without cardMap")
    compare(prefixWith(settings, f.c, { s1: f.s, c1: f.c }, runs), "", "broken chain")
    var a = mkCard("a", 1, "todo", "b", "A")
    var b = mkCard("b", 1, "todo", "a", "B")
    compare(prefixWith(settings, a, { a: a, b: b }, runs), "", "two-card cycle")
    compare(prefixWith(settings, null, f.map, runs), "", "no card")
    var noId = { depth: 0, status: "todo", parentId: null, title: "M3 Document runs" }
    var blankId = mkCard("", 0, "todo", null, "M3 Document runs")
    var numberId = mkCard(5, 0, "todo", null, "M3 Document runs")
    var keyless = [noId, blankId, numberId]
    var noHistory = { prefixByMilestone: settings.prefixByMilestone, prefixHistory: [] }
    for (var i = 0; i < keyless.length; i++) {
      compare(prefixWith(settings, keyless[i], {}, runs), "hist-p", "milestone " + i + " without a usable id skips run and map")
      compare(prefixWith(noHistory, keyless[i], {}, runs), "m3", "milestone " + i + ": then the stem")
    }
  }

  function test_dispatchDefaults_prefix_pure() {
    var f = prefixCards()
    var project = fullProject()
    project.settings.prefixByMilestone = { m1: "map-p", m2: "other-p" }
    project.settings.prefixHistory = ["hist-p", "older"]
    var runs = [mkPrefixRun("m2", "other-p", "2026-10-07T10:00:00Z"), mkPrefixRun("m1", "  run-p ", "2026-10-06T10:00:00Z")]
    var before = JSON.stringify([runs, project, f.map])
    var a = Runs.dispatchDefaults(project, f.c, f.map, runs)
    var b = Runs.dispatchDefaults(project, f.c, f.map, runs)
    compare(JSON.stringify([runs, project, f.map]), before, "runs, settings and cardMap unchanged")
    verify(a !== b, "distinct objects")
    verify(a.verify !== b.verify, "distinct verify arrays")
    checkDefaults5(a, "main", 2, "run-p", ["uv run pytest", "bash tests/run.sh"], "with runs")
    checkDefaults5(Runs.dispatchDefaults(project, f.c, f.map), "main", 2, "map-p", ["uv run pytest", "bash tests/run.sh"],
                   "without runs")
    var values = [undefined, null, 0, "x", [], Object.create(null), [null], [Object.create(null)]]
    for (var i = 0; i < values.length; i++) {
      checkDefaults5(Runs.dispatchDefaults(values[i], values[i], values[i], values[i]), "", 4, "", [], "garbage " + i)
    }
  }

  // ---- S3 1.2: dispatch form and preview ---------------------------------------------------

  function validForm() {
    return { allowNoVerification: false, base: "main", parallelism: 4, prefix: "m3", verify: ["uv run pytest"] }
  }

  // validForm() with key set to value.
  function formWith(key, value) {
    var f = validForm()
    f[key] = value
    return f
  }

  // validForm() without key.
  function formWithout(key) {
    var f = validForm()
    delete f[key]
    return f
  }

  // The pinned sentence for a validateDispatch error field.
  function formMessage(field) {
    if (field === "prefix") return "Enter a branch prefix"
    if (field === "verify") return "Add a verify command or choose to run without verification"
    if (field === "parallelism") return "Parallelism must be a whole number of at least 1"
    return "unknown field " + field
  }

  // Asserts a validateDispatch result: its keys, ok, each error's keys and
  // sentence, and the error fields in order.
  function checkValid(v, fields, label) {
    compare(Object.keys(v).sort().join(","), "errors,ok", label + " keys")
    compare(v.ok, fields.length === 0, label + " ok")
    compare(Array.isArray(v.errors), true, label + " errors is array")
    var got = []
    for (var i = 0; i < v.errors.length; i++) {
      compare(Object.keys(v.errors[i]).sort().join(","), "field,message", label + " error " + i + " keys")
      compare(v.errors[i].message, formMessage(v.errors[i].field), label + " error " + i + " message")
      got.push(v.errors[i].field)
    }
    compare(got.join(","), fields.join(","), label + " fields")
  }

  function test_validateDispatch_shape() {
    var forms = [validForm(), formWith("prefix", "")]
    for (var i = 0; i < forms.length; i++) {
      var a = Runs.validateDispatch(forms[i])
      var b = Runs.validateDispatch(forms[i])
      checkValid(a, i === 0 ? [] : ["prefix"], "form " + i)
      verify(a !== b, "distinct objects " + i)
      verify(a.errors !== b.errors, "distinct errors arrays " + i)
    }
    var first = Runs.validateDispatch(forms[1])
    var second = Runs.validateDispatch(forms[1])
    verify(first.errors[0] !== second.errors[0], "distinct error objects")
    first.errors.push({ field: "x", message: "y" })
    first.errors[0].message = "changed"
    checkValid(Runs.validateDispatch(forms[1]), ["prefix"], "mutation does not leak")
  }

  function test_validateDispatch_valid() {
    checkValid(Runs.validateDispatch(validForm()), [], "valid form")
    checkValid(Runs.validateDispatch(formWith("base", "")), [], "base unchecked")
    checkValid(Runs.validateDispatch(formWith("prefix", "my prefix")), [], "inner spaces")
    checkValid(Runs.validateDispatch(formWith("allowNoVerification", true)), [], "commands and opt-out")
  }

  function test_validateDispatch_prefix() {
    var bad = ["", "   ", "\t\n", null, 5]
    for (var i = 0; i < bad.length; i++) {
      checkValid(Runs.validateDispatch(formWith("prefix", bad[i])), ["prefix"], "prefix " + i)
    }
    checkValid(Runs.validateDispatch(formWithout("prefix")), ["prefix"], "prefix missing")
  }

  function test_validateDispatch_verify() {
    var lists = [[], ["", "  "], [5, null], "uv run pytest"]
    for (var i = 0; i < lists.length; i++) {
      checkValid(Runs.validateDispatch(formWith("verify", lists[i])), ["verify"], "verify " + i)
      var optedOut = formWith("verify", lists[i])
      optedOut.allowNoVerification = true
      checkValid(Runs.validateDispatch(optedOut), [], "opted out " + i)
    }
    var missing = formWithout("verify")
    checkValid(Runs.validateDispatch(missing), ["verify"], "verify missing")
    missing.allowNoVerification = true
    checkValid(Runs.validateDispatch(missing), [], "verify missing, opted out")
    var loose = ["true", 1]
    for (var j = 0; j < loose.length; j++) {
      var f = formWith("verify", [])
      f.allowNoVerification = loose[j]
      checkValid(Runs.validateDispatch(f), ["verify"], "opt-out " + loose[j] + " is not true")
    }
    checkValid(Runs.validateDispatch(formWith("verify", ["", " make test "])), [], "one real command")
  }

  function test_validateDispatch_parallelism() {
    checkValid(Runs.validateDispatch(formWith("parallelism", 1)), [], "1")
    checkValid(Runs.validateDispatch(formWith("parallelism", 16)), [], "16")
    var bad = [0, -1, 2.5, NaN, Infinity, "3", null]
    for (var i = 0; i < bad.length; i++) {
      checkValid(Runs.validateDispatch(formWith("parallelism", bad[i])), ["parallelism"], "parallelism " + bad[i])
    }
    checkValid(Runs.validateDispatch(formWithout("parallelism")), ["parallelism"], "parallelism missing")
  }

  function test_validateDispatch_all_errors() {
    var form = { allowNoVerification: false, base: "main", parallelism: 0, prefix: "  ", verify: [] }
    checkValid(Runs.validateDispatch(form), ["prefix", "verify", "parallelism"], "all three, in order")
  }

  function test_validateDispatch_defaults() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    checkValid(Runs.validateDispatch(Runs.dispatchDefaults(fullProject(), m)), [], "stored verify and a milestone")
    checkValid(Runs.validateDispatch(Runs.dispatchDefaults(null)), ["prefix", "verify"], "garbage project")
  }

  function test_validateDispatch_garbage() {
    var values = [undefined, null, 0, true, "x", [], {}, Object.create(null)]
    for (var i = 0; i < values.length; i++) {
      checkValid(Runs.validateDispatch(values[i]), ["prefix", "verify", "parallelism"], "form " + i)
    }
    checkValid(Runs.validateDispatch(), ["prefix", "verify", "parallelism"], "no argument")
  }

  // Review Focus 1, 4 and 5.
  function test_validateDispatch_edges() {
    var bare = Object.create(null)
    bare.allowNoVerification = false
    bare.base = "main"
    bare.parallelism = 2
    bare.prefix = "m3"
    bare.verify = ["make test"]
    checkValid(Runs.validateDispatch(bare), [], "prototype-less form with real values")
    var padded = formWith("prefix", "  m3 ")
    checkValid(Runs.validateDispatch(padded), [], "padded prefix is not blank")
    compare(padded.prefix, "  m3 ", "the form's prefix is not trimmed")
    checkValid(Runs.validateDispatch(formWith("verify", ["\t", "\n ", "\r\n"])), ["verify"], "whitespace-only commands")
  }

  // One subtask row of a dry-run level, as am prints it.
  function planSubtask(prefix, id, base) {
    return { id: id, title: "Subtask " + id, status: "todo", branch: prefix + "-" + id, base: base }
  }

  // `am run --milestone m3 --dry-run` data: 2 levels, 5 subtasks, 3 stories already done.
  function dryRunMilestone() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 2, stories: [
          { story: "s1", title: "Story one", root: "main",
            subtasks: [planSubtask("m3", "c1", "main"), planSubtask("m3", "c2", "m3-c1")] },
          { story: "s2", title: "Story two", root: "main",
            subtasks: [planSubtask("m3", "c3", "main")] }
        ] },
        { level: 1, concurrent: 1, stories: [
          { story: "s3", title: "Story three", root: "m3-s3", merged_from: ["s1", "s2"],
            subtasks: [planSubtask("m3", "c4", "m3-s3"), planSubtask("m3", "c5", "m3-c4")] }
        ] }
      ],
      already_done: [
        { kind: "story", id: "s4", title: "Story four" },
        { kind: "story", id: "s5", title: "Story five" },
        { kind: "story", id: "s6", title: "Story six" },
        { kind: "subtask", id: "c0", title: "Subtask c0", story: "s1" }
      ],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate",
                   order: [{ story: "s1", tip: "m3-c2" }, { story: "s2", tip: "m3-c3" }, { story: "s3", tip: "m3-c5" }] }
    }
  }

  // `am run --story s1 --dry-run` data as recorded in 1.1: one level, one story,
  // 2 subtasks stacked on master, no Integrate.
  function dryRunStory() {
    return {
      max_concurrent: 1,
      levels: [
        { level: 0, concurrent: 1, stories: [
          { story: "s1", title: "Story one", root: "master",
            subtasks: [planSubtask("p", "c1", "master"), planSubtask("p", "c2", "p-c1")] }
        ] }
      ],
      already_done: [],
      integrate: null
    }
  }

  // `am run --story s1 --dry-run` data for a finished story: no level, the story already done.
  function dryRunStoryDone() {
    return { max_concurrent: 1, levels: [], already_done: [{ kind: "story", id: "s1", title: "Story one" }], integrate: null }
  }

  // A board milestone's own plan: one level, one story with count subtasks,
  // one story already done, its own Integrate branch.
  function boardPlan(prefix, count) {
    var subtasks = []
    for (var i = 1; i <= count; i++) {
      subtasks.push(planSubtask(prefix, "c" + i, i === 1 ? "main" : prefix + "-c" + (i - 1)))
    }
    return {
      max_concurrent: 4,
      levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "main", subtasks: subtasks }] }],
      already_done: [{ kind: "story", id: "s9", title: "Story nine" }],
      integrate: { branch: prefix + "-integrate", worktree: "/repo/.worktrees/" + prefix + "-integrate",
                   order: [{ story: "s1", tip: prefix + "-c" + count }] }
    }
  }

  function boardMilestone(id, title, prefix, base, count) {
    return { milestone_id: id, title: title, branch_prefix: prefix, base_branch: base, plan: boardPlan(prefix, count) }
  }

  // `am run --board --dry-run` data: 3 milestones, 7 subtasks.
  function dryRunBoard() {
    return {
      board: true,
      max_concurrent: 4,
      levels: [
        { level: 0, milestones: [boardMilestone("m1", "M1 First", "m1", "main", 2),
                                 boardMilestone("m2", "M2 Second", "m2", "main", 3)] },
        { level: 1, milestones: [boardMilestone("m3", "M3 Third", "m3", "m1-integrate", 2)] }
      ]
    }
  }

  // Asserts a previewSummary result: its keys and the three values.
  function checkSummary(r, board, summary, integrate, label) {
    compare(Object.keys(r).sort().join(","), "board,integrate,summary", label + " keys")
    compare(r.board, board, label + " board")
    compare(r.summary, summary, label + " summary")
    compare(r.integrate, integrate, label + " integrate")
  }

  function test_previewSummary_milestone() {
    checkSummary(Runs.previewSummary(dryRunMilestone()), false,
                 "2 levels \u00b7 5 subtasks \u00b7 3 stories already done", "Integrate \u2192 m3-integrate", "milestone")
    var a = Runs.previewSummary(dryRunMilestone())
    var b = Runs.previewSummary(dryRunMilestone())
    verify(a !== b, "distinct objects")
    a.summary = "changed"
    compare(Runs.previewSummary(dryRunMilestone()).summary, "2 levels \u00b7 5 subtasks \u00b7 3 stories already done",
            "mutation does not leak")
  }

  function test_previewSummary_milestone_plurals() {
    var one = dryRunMilestone()
    one.levels = [one.levels[0]]
    one.levels[0].stories = [one.levels[0].stories[1]]
    one.already_done = [one.already_done[0], one.already_done[3]]
    checkSummary(Runs.previewSummary(one), false, "1 level \u00b7 1 subtask \u00b7 1 story already done",
                 "Integrate \u2192 m3-integrate", "singulars")
    var two = dryRunMilestone()
    two.levels = [two.levels[0]]
    two.levels[0].stories = [two.levels[0].stories[0]]
    two.already_done = []
    checkSummary(Runs.previewSummary(two), false, "1 level \u00b7 2 subtasks", "Integrate \u2192 m3-integrate", "nothing done")
    var subtaskOnly = dryRunMilestone()
    subtaskOnly.already_done = [subtaskOnly.already_done[3]]
    checkSummary(Runs.previewSummary(subtaskOnly), false, "2 levels \u00b7 5 subtasks", "Integrate \u2192 m3-integrate",
                 "only a subtask done")
    var allDone = dryRunMilestone()
    allDone.levels = []
    allDone.already_done.push({ kind: "story", id: "s7", title: "Story seven" })
    checkSummary(Runs.previewSummary(allDone), false, "0 levels \u00b7 0 subtasks \u00b7 4 stories already done",
                 "Integrate \u2192 m3-integrate", "everything done")
  }

  function test_previewSummary_milestone_counting() {
    var full = "2 levels \u00b7 5 subtasks \u00b7 3 stories already done"
    var d = dryRunMilestone()
    d.levels[0].stories.push("x", null, [], { story: "s8", title: "Story eight", root: "main", subtasks: "x" },
                             { story: "s9", title: "Story nine", root: "main" })
    d.levels[0].stories[0].subtasks.push(null, "c9", 7, [])
    d.levels.push("x", null, [])
    checkSummary(Runs.previewSummary(d), false, full, "Integrate \u2192 m3-integrate", "garbage entries skipped")
    var noDone = [undefined, "x", {}, 5]
    for (var i = 0; i < noDone.length; i++) {
      var e = dryRunMilestone()
      if (noDone[i] === undefined) delete e.already_done
      else e.already_done = noDone[i]
      checkSummary(Runs.previewSummary(e), false, "2 levels \u00b7 5 subtasks", "Integrate \u2192 m3-integrate",
                   "already_done " + i)
    }
    var kinds = dryRunMilestone()
    kinds.already_done = [{ kind: "Story", id: "s4" }, { id: "s5" }, "story", null,
                          { kind: "story", id: "s6", title: "Story six" }]
    checkSummary(Runs.previewSummary(kinds), false, "2 levels \u00b7 5 subtasks \u00b7 1 story already done",
                 "Integrate \u2192 m3-integrate", "only kind story counts")
  }

  function test_previewSummary_integrate() {
    var full = "2 levels \u00b7 5 subtasks \u00b7 3 stories already done"
    var padded = dryRunMilestone()
    padded.integrate.branch = "  m3-integrate \n"
    checkSummary(Runs.previewSummary(padded), false, full, "Integrate \u2192 m3-integrate", "branch trimmed")
    var objs = [undefined, null, "x", {}]
    for (var i = 0; i < objs.length; i++) {
      var e = dryRunMilestone()
      if (objs[i] === undefined) delete e.integrate
      else e.integrate = objs[i]
      checkSummary(Runs.previewSummary(e), false, full, "", "integrate " + i)
    }
    var branches = ["", "  ", 5, null]
    for (var j = 0; j < branches.length; j++) {
      var b = dryRunMilestone()
      b.integrate.branch = branches[j]
      checkSummary(Runs.previewSummary(b), false, full, "", "branch " + j)
    }
  }

  function test_previewSummary_board() {
    checkSummary(Runs.previewSummary(dryRunBoard()), true, "3 milestones, 7 subtasks", "", "board")
    var one = { board: true, max_concurrent: 4,
                levels: [{ level: 0, milestones: [boardMilestone("m1", "M1 First", "m1", "main", 1)] }] }
    checkSummary(Runs.previewSummary(one), true, "1 milestone, 1 subtask", "", "singulars")
    checkSummary(Runs.previewSummary({ board: true, max_concurrent: 4, levels: [] }), true,
                 "0 milestones, 0 subtasks", "", "no levels")
    var plans = dryRunBoard()
    delete plans.levels[0].milestones[0].plan
    plans.levels[1].milestones[0].plan = "x"
    checkSummary(Runs.previewSummary(plans), true, "3 milestones, 3 subtasks", "", "unreadable plans count 0")
    var skipped = dryRunBoard()
    skipped.levels[0].milestones.push("x", null, [])
    skipped.levels.push({ level: 2, milestones: "x" }, { level: 3 }, "x", null)
    checkSummary(Runs.previewSummary(skipped), true, "3 milestones, 7 subtasks", "", "garbage entries skipped")
  }

  function test_previewSummary_board_flag() {
    var flags = ["true", 1]
    for (var i = 0; i < flags.length; i++) {
      var d = dryRunBoard()
      d.board = flags[i]
      checkSummary(Runs.previewSummary(d), false, "2 levels \u00b7 0 subtasks", "", "board " + flags[i])
    }
  }

  function test_previewSummary_unreadable() {
    var values = [undefined, null, 0, true, "x", [], Object.create(null), {}, { levels: "x" }, { board: true },
                  { board: true, levels: {} }, { ok: true, data: dryRunMilestone() }]
    for (var i = 0; i < values.length; i++) {
      checkSummary(Runs.previewSummary(values[i]), false, "", "", "value " + i)
    }
    checkSummary(Runs.previewSummary(), false, "", "", "no argument")
  }

  // Review Focus 1, 2 and 3.
  function test_previewSummary_edges() {
    var src = dryRunMilestone()
    var bare = Object.create(null)
    bare.levels = src.levels
    bare.already_done = src.already_done
    bare.integrate = src.integrate
    checkSummary(Runs.previewSummary(bare), false, "2 levels \u00b7 5 subtasks \u00b7 3 stories already done",
                 "Integrate \u2192 m3-integrate", "prototype-less payload")
    var empty = dryRunMilestone()
    empty.levels[0].stories[1].subtasks = []
    empty.levels[1].stories = []
    checkSummary(Runs.previewSummary(empty), false, "2 levels \u00b7 2 subtasks \u00b7 3 stories already done",
                 "Integrate \u2192 m3-integrate", "empty story and empty level")
    var board = dryRunBoard()
    board.levels[0].milestones[0].plan.already_done.push({ kind: "story", id: "s8", title: "Story eight" })
    checkSummary(Runs.previewSummary(board), true, "3 milestones, 7 subtasks", "", "plans' done and integrate stay out")
  }

  function test_previewSummary_story() {
    checkSummary(Runs.previewSummary(dryRunStory(), "story"), false, "2 subtasks \u00b7 rooted on master", "", "story")
    var a = Runs.previewSummary(dryRunStory(), "story")
    var b = Runs.previewSummary(dryRunStory(), "story")
    verify(a !== b, "distinct objects")
    a.summary = "changed"
    a.board = true
    checkSummary(Runs.previewSummary(dryRunStory(), "story"), false, "2 subtasks \u00b7 rooted on master", "",
                 "mutation does not leak")
  }

  function test_previewSummary_story_singular() {
    var one = dryRunStory()
    one.levels[0].stories[0].subtasks = [planSubtask("p", "c1", "master")]
    checkSummary(Runs.previewSummary(one, "story"), false, "1 subtask \u00b7 rooted on master", "", "one subtask")
  }

  function test_previewSummary_story_nothing_left() {
    checkSummary(Runs.previewSummary(dryRunStoryDone(), "story"), false, "Nothing left to run", "", "finished story")
    var payloads = [
      { levels: [] },
      { levels: [{ level: 0, concurrent: 1, stories: [] }] },
      { levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "master", subtasks: [] }] }] },
      { levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "master" }] }] },
      { levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Story one", root: "master", subtasks: "x" }] }] },
      { levels: [null, "x", [], { level: 0, stories: ["x", null, [], { story: "s1", subtasks: [null, 7, "x", []] }] }] }
    ]
    for (var i = 0; i < payloads.length; i++) {
      checkSummary(Runs.previewSummary(payloads[i], "story"), false, "Nothing left to run", "", "payload " + i)
    }
  }

  // Review Focus 3.
  function test_previewSummary_story_ignores_integrate_and_done() {
    var full = "2 subtasks \u00b7 rooted on master"
    var integrated = dryRunStory()
    integrated.integrate = { branch: "p-integrate", worktree: "/repo/.worktrees/p-integrate", order: [] }
    checkSummary(Runs.previewSummary(integrated, "story"), false, full, "", "integrate branch")
    var done = dryRunStory()
    done.already_done = [{ kind: "story", id: "s9", title: "Story nine" },
                         { kind: "subtask", id: "c0", title: "Subtask c0", story: "s1" }]
    checkSummary(Runs.previewSummary(done, "story"), false, full, "", "already done")
    var board = dryRunStory()
    board.board = true
    checkSummary(Runs.previewSummary(board, "story"), false, full, "", "board true")
  }

  // Review Focus 2.
  function test_previewSummary_story_base() {
    var padded = dryRunStory()
    padded.levels[0].stories[0].subtasks[0].base = "  main \n"
    checkSummary(Runs.previewSummary(padded, "story"), false, "2 subtasks \u00b7 rooted on main", "", "base trimmed")
    var bases = ["", "  ", 5, null]
    for (var i = 0; i < bases.length; i++) {
      var d = dryRunStory()
      d.levels[0].stories[0].subtasks[0].base = bases[i]
      checkSummary(Runs.previewSummary(d, "story"), false, "2 subtasks", "", "base " + i + " (no fallback)")
    }
    var absent = dryRunStory()
    delete absent.levels[0].stories[0].subtasks[0].base
    checkSummary(Runs.previewSummary(absent, "story"), false, "2 subtasks", "", "base absent")
    var garbage = dryRunStory()
    garbage.levels[0].stories[0].subtasks.unshift(7, null, [], "c0")
    garbage.levels[0].stories.unshift("x", null, [], { story: "s0", title: "Empty", root: "main", subtasks: [] })
    garbage.levels.unshift(null, "x", [], { level: 9, stories: "x" })
    checkSummary(Runs.previewSummary(garbage, "story"), false, "2 subtasks \u00b7 rooted on master", "",
                 "the first object subtask's base")
    var partly = dryRunStory()
    partly.levels[0].stories[0].subtasks = [planSubtask("p", "c2", "p-c1"), planSubtask("p", "c3", "p-c2")]
    partly.already_done = [{ kind: "subtask", id: "c1", title: "Subtask c1", story: "s1" }]
    checkSummary(Runs.previewSummary(partly, "story"), false, "2 subtasks \u00b7 rooted on p-c1", "", "partly done")
  }

  // Review Focus 4.
  function test_previewSummary_story_unreadable() {
    var values = [undefined, null, 0, true, "x", [], Object.create(null), {}, { levels: "x" }, { levels: {} },
                  { ok: true, data: dryRunStory() }, { ok: true, data: dryRunStoryDone() }]
    for (var i = 0; i < values.length; i++) {
      checkSummary(Runs.previewSummary(values[i], "story"), false, "", "", "value " + i)
    }
    var bare = Object.create(null)
    bare.levels = dryRunStory().levels
    checkSummary(Runs.previewSummary(bare, "story"), false, "2 subtasks \u00b7 rooted on master", "", "prototype-less payload")
  }

  // Review Focus 5.
  function test_previewSummary_level_argument() {
    var levels = [undefined, "milestone", "board", "Story", " story", "story ", 1, null]
    for (var i = 0; i < levels.length; i++) {
      checkSummary(Runs.previewSummary(dryRunMilestone(), levels[i]), false,
                   "2 levels \u00b7 5 subtasks \u00b7 3 stories already done", "Integrate \u2192 m3-integrate",
                   "milestone with level " + levels[i])
      checkSummary(Runs.previewSummary(dryRunBoard(), levels[i]), true, "3 milestones, 7 subtasks", "",
                   "board with level " + levels[i])
    }
    checkSummary(Runs.previewSummary(dryRunStory()), false, "1 level \u00b7 2 subtasks", "", "a story payload alone is a milestone")
    checkSummary(Runs.previewSummary(dryRunStoryDone()), false, "0 levels \u00b7 0 subtasks \u00b7 1 story already done", "",
                 "a finished story payload alone is a milestone")
    checkSummary(Runs.previewSummary(dryRunMilestone(), "story"), false, "5 subtasks \u00b7 rooted on main", "",
                 "the argument selects the story variant")
  }

  function test_dispatch_form_preview_inputs_unchanged() {
    var form = validForm()
    var milestone = dryRunMilestone()
    var board = dryRunBoard()
    var story = dryRunStory()
    var storyDone = dryRunStoryDone()
    var before = JSON.stringify([form, milestone, board, story, storyDone])
    Runs.validateDispatch(form)
    Runs.validateDispatch(formWith("prefix", ""))
    Runs.previewSummary(milestone)
    Runs.previewSummary(board)
    Runs.previewSummary(story, "story")
    Runs.previewSummary(storyDone, "story")
    Runs.previewSummary(milestone, "story")
    compare(JSON.stringify([form, milestone, board, story, storyDone]), before, "form and payloads unchanged")
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify", "no key added to the form")
    compare(Object.keys(story).sort().join(","), "already_done,integrate,levels,max_concurrent", "no key added to the story payload")
  }

  // ---- 2.1: the dispatch target's milestone and label -------------------------------------

  // Milestone m1, its story s1, the story's subtask t1, an orphan story o1
  // (parentId ""), a story g1 whose parent is not in the map, and their map.
  function labelCards() {
    var m = mkCard("m1", 0, "todo", null, "M3 Document runs")
    var s = mkCard("s1", 1, "todo", "m1", "Dispatch store")
    var t = mkCard("t1", 2, "todo", "s1", "RunStore dispatch")
    var o = mkCard("o1", 1, "todo", "", "Orphan")
    var g = mkCard("g1", 1, "todo", "gone", "Lost")
    return { m: m, s: s, t: t, o: o, g: g, map: { m1: m, s1: s, t1: t, o1: o, g1: g } }
  }

  function test_dispatchMilestone_levels() {
    var f = labelCards()
    var m1 = '{"id":"m1","title":"M3 Document runs"}'
    compare(JSON.stringify(Runs.dispatchMilestone(f.s, f.map)), m1, "story")
    compare(JSON.stringify(Runs.dispatchMilestone(f.m, f.map)), m1, "milestone")
    compare(JSON.stringify(Runs.dispatchMilestone(f.m)), m1, "milestone without cardMap")
    compare(JSON.stringify(Runs.dispatchMilestone(f.t, f.map)), m1, "subtask")
  }

  function test_dispatchMilestone_null() {
    var f = labelCards()
    compare(Runs.dispatchMilestone(f.o, f.map), null, "a story whose parentId is empty")
    compare(Runs.dispatchMilestone(f.g, f.map), null, "a missing parent")
    var a = mkCard("a1", 1, "todo", "b1", "A")
    var b = mkCard("b1", 1, "todo", "a1", "B")
    compare(Runs.dispatchMilestone(a, { a1: a, b1: b }), null, "a cycle")
    compare(Runs.dispatchMilestone(f.s), null, "no cardMap")
    compare(Runs.dispatchMilestone("board", f.map), null, "the board")
    var values = [undefined, null, 0, "m1", [], true]
    for (var i = 0; i < values.length; i++) compare(Runs.dispatchMilestone(values[i], f.map), null, "card " + i)
    compare(Runs.dispatchMilestone(mkCard("-m", 0, "todo", null, "M"), {}), null, "an id read as a flag")
    compare(Runs.dispatchMilestone(mkCard("", 0, "todo", null, "M"), {}), null, "an empty id")
    compare(Runs.dispatchMilestone(mkCard("s1", 1, "todo", "-m", "S"), { "-m": mkCard("-m", 0, "todo", null, "M") }), null,
            "a root whose id is read as a flag")
    var root = { id: "r1", title: "R", parentId: "" }
    compare(Runs.dispatchMilestone(mkCard("s1", 1, "todo", "r1", "S"), { r1: root }), null, "a root without depth 0")
  }

  function test_dispatchMilestone_title_and_fresh() {
    var m = { id: "m1", depth: 0, status: "todo", parentId: null, title: 5 }
    var s = mkCard("s1", 1, "todo", "m1", "S")
    compare(JSON.stringify(Runs.dispatchMilestone(s, { m1: m, s1: s })), '{"id":"m1","title":""}', "a title that is not a string")
    compare(Runs.dispatchMilestone({ id: "m1", depth: 0 }).title, "", "no title key")
    var f = labelCards()
    var a = Runs.dispatchMilestone(f.s, f.map)
    var b = Runs.dispatchMilestone(f.s, f.map)
    verify(a !== b, "distinct objects")
    verify(a !== f.m, "not the card itself")
    compare(Object.keys(a).sort().join(","), "id,title", "only id and title")
    var before = JSON.stringify(f.map)
    a.title = "x"
    compare(JSON.stringify(f.map), before, "the cards are unchanged")
  }

  function test_dispatchLabel_rows() {
    var f = labelCards()
    compare(Runs.dispatchLabel("board", f.map), "Whole board", "board")
    compare(Runs.dispatchLabel(f.m, f.map), 'Milestone "M3 Document runs"', "milestone")
    compare(Runs.dispatchLabel(f.s, f.map), 'Story "Dispatch store" (milestone "M3 Document runs")', "story")
    compare(Runs.dispatchLabel(f.o, f.map), 'Story "Orphan"', "orphan story")
    compare(Runs.dispatchLabel(f.g, f.map), 'Story "Lost"', "a story whose parent is missing")
    compare(Runs.dispatchLabel(f.s), 'Story "Dispatch store"', "a story without cardMap")
    compare(Runs.dispatchLabel(f.t, f.map), 'Subtask "RunStore dispatch"', "subtask")
    compare(Runs.dispatchLabel(mkCard("t5", 5, "todo", "t1", "Deep"), f.map), 'Subtask "Deep"', "depth 5")
  }

  function test_dispatchLabel_no_card_and_odd_depths() {
    var values = [undefined, null, 0, "m1", [], true, {}, mkCard("", 0, "todo", null, "M"), mkCard("-x", 0, "todo", null, "M")]
    for (var i = 0; i < values.length; i++) compare(Runs.dispatchLabel(values[i], {}), "No card", "card " + i)
    var depths = [undefined, null, -1, 1.5, "1", NaN, Infinity]
    for (var j = 0; j < depths.length; j++) {
      compare(Runs.dispatchLabel({ id: "x1", title: "X", depth: depths[j] }, {}), '"X"', "depth " + j)
    }
  }

  function test_dispatchLabel_titles_and_status() {
    var f = labelCards()
    compare(Runs.dispatchLabel(mkCard("s2", 1, "done", "m1", "Finished story"), f.map),
            'Story "Finished story" (milestone "M3 Document runs")', "a done story is labelled")
    compare(Runs.dispatchLabel(mkCard("m2", 0, "done", null, "M2"), {}), 'Milestone "M2"', "a done milestone is labelled")
    compare(Runs.dispatchLabel({ id: "m3", depth: 0, title: 7 }, {}), 'Milestone ""', "a title that is not a string")
    var untitled = { id: "m4", depth: 0, parentId: null }
    compare(Runs.dispatchLabel(mkCard("s4", 1, "todo", "m4", null), { m4: untitled }), 'Story "" (milestone "")', "no titles")
    var before = JSON.stringify(f.map)
    Runs.dispatchLabel(f.s, f.map)
    Runs.dispatchMilestone(f.t, f.map)
    compare(JSON.stringify(f.map), before, "the inputs are unchanged")
  }
}
