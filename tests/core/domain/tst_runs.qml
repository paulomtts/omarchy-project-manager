// tests/core/domain/tst_runs.qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../../core/domain/board.js" as Board
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
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow", label)
    compare(r.started_at, "", label)
    compare(r.id, "", label)
    compare(r.repo_dir, "", label)
    compare(r.milestone_id, "", label)
    compare(r.status, "", label)
    compare(r.base_branch, "", label)
    compare(r.branch_prefix, "", label)
    compare(r.card_id, "", label)
    compare(r.story_id, "", label)
    compare(r.lease, null, label)
    compare(r.project, null, label)
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
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,card_id,id,lease,milestone_id,project,repo_dir,requests,rows,started_at,status,story_id,tree,workflow")
    compare(r.id, "20261008T143823Z-e795ad19")
    compare(r.repo_dir, "/home/user/Code/omarchy-project-manager")
    compare(r.milestone_id, "e795ad19-c81f-43ec-bdda-ef61ab5f860b", "only the am runs row carries it")
    compare(r.status, "started")
    compare(r.workflow, "milestone")
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "dsp")
    compare(r.card_id, "", "a milestone run names no card")
    compare(r.story_id, "", "a milestone run names no story")
    compare(r.started_at, "2026-10-08 14:38:23.739155+00:00")
    compare(Object.keys(r.lease).sort().join(","), "accepting,heartbeat_at,host,live,pid", "acquired_at is not kept")
    compare(r.lease.pid, 1991)
    compare(r.lease.host, "mtts-desktop")
    compare(r.lease.heartbeat_at, "2026-10-08T14:38:28.740774+00:00")
    compare(r.lease.accepting, true)
    compare(r.lease.live, true)
    compare(Array.isArray(r.requests), true)
    compare(r.requests.length, 0)
  }

  function test_normalize_stories_are_id_lists() {
    var raw = amRun("status-started.json")
    var am = raw.status.stories[1]
    var s = Runs.normalizeRun(raw).tree.stories[1]
    compare(s.card_id, "7a7effb4-6ec5-4596-bcf1-be24546d4ac1")
    compare(JSON.stringify(s.subtasks), JSON.stringify(["e4214f55-1580-42fe-b0da-94a4e8b10912",
                                                        "2280a6ab-9c40-434b-9729-63fd1f373754",
                                                        "0849081e-b432-465e-81b1-0d2bc834f5fa"]))
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
    compare(open.card_id, "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(open.story_id, "7a7effb4-6ec5-4596-bcf1-be24546d4ac1")
    compare(Object.keys(open).sort().join(","), "base_branch,branch,card_id,phases,status,story_id,worktree_path")
    compare(open.phases[1].name, "explore")
    compare(open.phases[1].attempts[0].n, 1)
  }

  function test_normalize_rows_renamed() {
    var r = Runs.normalizeRun(amRun("status-started.json"))
    compare(Object.keys(r.rows[0]).sort().join(","), "attempt,card_id,phase,status,story_id")
    compare(r.rows[0].story_id, "9f0f68fc-f231-4ef2-b646-00a7af925ea2")
    compare(r.rows[0].card_id, "5560d0fe-2b8e-4ef9-ad71-96b50ee89daa")
    compare(r.rows[0].phase, "worktree")
    compare(r.rows[0].attempt, null)
    compare(r.rows[0].status, "done")
    compare(r.rows[43].story_id, "7a7effb4-6ec5-4596-bcf1-be24546d4ac1")
    compare(r.rows[43].card_id, "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(r.rows[43].phase, "explore")
    compare(r.rows[43].attempt, 1)
    compare(r.rows[43].status, "started")
  }

  function test_normalize_integrate_story_kept_resolver_dropped() {
    var r = Runs.normalizeRun(amRun("status-done-integrate.json"))
    var integrate = r.tree.stories[2]
    compare(integrate.card_id, "integrate")
    compare(JSON.stringify(integrate.subtasks), JSON.stringify(["862eb9b7-bb74-452f-9148-0f6a34434ab3"]))
    compare(integrate.status, "done")
    for (var i = 0; i < r.tree.subtasks.length; i++) {
      verify(r.tree.subtasks[i].story_id !== "integrate", "no subtask of integrate at " + i)
      verify(r.tree.subtasks[i].card_id !== "862eb9b7-bb74-452f-9148-0f6a34434ab3", "no resolver subtask at " + i)
    }
    compare(r.rows.length, 28, "the two resolver rows are dropped")
    for (var j = 0; j < r.rows.length; j++) verify(r.rows[j].story_id !== "integrate", "no integrate row at " + j)
  }

  function test_normalize_base_rows_kept() {
    // synthetic: a bases story, which no capture contains
    var raw = amRun("status-done-integrate.json")
    var baseId = "base-99f81fdf-94df-47da-abd3-ed625f851142"
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
    compare(r.tree.subtasks[3].card_id, "2280a6ab-9c40-434b-9729-63fd1f373754", "the rest is copied")
    compare(r.tree.subtasks[3].phases[1].name, "explore")
  }

  // ---- 4.0.3: the run's project and am 0.2.0's new keys ------------------------------------

  function hasOwn(o, key) { return Object.prototype.hasOwnProperty.call(o, key) }

  // The project normalizeRun gives for the status-started.json run whose row's
  // project is replaced by `project`.
  function projectOf(project) {
    var raw = amRun("status-started.json")
    raw.row.project = project
    return Runs.normalizeRun(raw).project
  }

  function test_normalize_project_from_fixture() {
    var names = ["status-started.json", "status-done.json", "status-escalated.json", "status-done-integrate.json"]
    for (var i = 0; i < names.length; i++) {
      var raw = amRun(names[i])
      verify(!hasOwn(raw.status.run, "project"), names[i] + ": the am status run has no project")
      var p = Runs.normalizeRun(raw).project
      compare(Object.keys(p).sort().join(","), "id,repo_dir", names[i] + " keys")
      compare(p.id, 1, names[i] + " id")
      compare(p.repo_dir, "/home/user/Code/omarchy-project-manager", names[i] + " repo_dir")
    }

    // the am runs rows alone, before any am status
    var rows = F.load("runs.json").data.runs
    for (var j = 0; j < rows.length; j++) {
      var bare = Runs.normalizeRun({ row: rows[j] }).project
      compare(JSON.stringify(bare), JSON.stringify({ id: 1, repo_dir: "/home/user/Code/omarchy-project-manager" }), "row " + j + " alone")
    }
  }

  function test_normalize_project_absent() {
    var missing = amRun("status-started.json")
    verify(hasOwn(missing.row, "project"), "the capture's row carries a project")
    // synthetic: the row's project deleted
    delete missing.row.project
    compare(Runs.normalizeRun(missing).project, null, "missing")

    // synthetic: the row's project replaced by each non-object
    var cases = [["null", null], ["string", "/home/user/Code/omarchy-project-manager"], ["number", 1],
                 ["array", [1, "/home/user/Code/omarchy-project-manager"]], ["true", true], ["false", false]]
    for (var i = 0; i < cases.length; i++) compare(projectOf(cases[i][1]), null, cases[i][0])
  }

  function test_normalize_project_coercion() {
    // synthetic: the row's project with each id that is not a finite number
    var badIds = [["string", "1"], ["null", null], ["NaN", NaN], ["Infinity", Infinity], ["-Infinity", -Infinity],
                  ["object", {}], ["array", [1]], ["boolean", true]]
    for (var i = 0; i < badIds.length; i++) {
      compare(projectOf({ id: badIds[i][1], repo_dir: "/p" }).id, null, "id " + badIds[i][0])
    }
    compare(projectOf({ repo_dir: "/p" }).id, null, "id missing")

    // synthetic: finite ids, falsy and fractional included, are kept as given
    var goodIds = [0, -3, 1.5, 2]
    for (var j = 0; j < goodIds.length; j++) compare(projectOf({ id: goodIds[j], repo_dir: "/p" }).id, goodIds[j], "id " + goodIds[j])

    // synthetic: repo_dir as text
    compare(projectOf({ id: 1 }).repo_dir, "", "repo_dir missing")
    compare(projectOf({ id: 1, repo_dir: null }).repo_dir, "", "repo_dir null")
    compare(projectOf({ id: 1, repo_dir: 42 }).repo_dir, "42", "repo_dir number")
    compare(projectOf({ id: 1, repo_dir: true }).repo_dir, "true", "repo_dir boolean")
    compare(projectOf({ id: 1, repo_dir: "" }).repo_dir, "", "repo_dir empty")

    // synthetic: extra keys inside the project are dropped
    var extra = projectOf({ id: 1, repo_dir: "/p", name: "x", root_path: "/r", story_id: "s" })
    compare(Object.keys(extra).sort().join(","), "id,repo_dir")
    compare(extra.id, 1)
    compare(extra.repo_dir, "/p")
  }

  function test_normalize_project_ignores_status() {
    // synthetic: a project only on the am status run and on am status itself
    var raw = amRun("status-started.json")
    delete raw.row.project
    raw.status.run.project = { id: 2, repo_dir: "/from/run" }
    raw.status.project = { id: 3, repo_dir: "/from/status" }
    compare(Runs.normalizeRun(raw).project, null, "am status never supplies the project")

    // synthetic: a project on the row, the am status run and am status
    var both = amRun("status-started.json")
    both.status.run.project = { id: 2, repo_dir: "/from/run" }
    both.status.project = { id: 3, repo_dir: "/from/status" }
    var p = Runs.normalizeRun(both).project
    compare(p.id, 1, "the row's id wins")
    compare(p.repo_dir, "/home/user/Code/omarchy-project-manager", "the row's repo_dir wins")
  }

  function test_normalize_project_independent_of_repo_dir() {
    // synthetic: the row's repo_dir and its project's repo_dir edited to differ
    var differ = amRun("status-started.json")
    differ.row.repo_dir = "/row/dir"
    differ.row.project.repo_dir = "/project/dir"
    var d = Runs.normalizeRun(differ)
    compare(d.repo_dir, "/row/dir")
    compare(d.project.repo_dir, "/project/dir")

    // synthetic: the row's and the am status run's repo_dir blanked
    var blank = amRun("status-started.json")
    blank.row.repo_dir = ""
    blank.status.run.repo_dir = ""
    var b = Runs.normalizeRun(blank)
    compare(b.repo_dir, "", "project.repo_dir is never the run's fallback")
    compare(b.project.repo_dir, "/home/user/Code/omarchy-project-manager")

    // synthetic: the project's repo_dir blanked
    var emptyProject = amRun("status-started.json")
    emptyProject.row.project.repo_dir = ""
    var e = Runs.normalizeRun(emptyProject)
    compare(e.project.repo_dir, "", "the run's repo_dir never fills the project's")
    compare(e.repo_dir, "/home/user/Code/omarchy-project-manager")
  }

  function test_normalize_project_is_a_copy() {
    var raw = amRun("status-started.json")
    var before = JSON.stringify(raw)
    var r = Runs.normalizeRun(raw)
    verify(r.project !== raw.row.project, "project is a copy")
    r.project.id = 99
    r.project.repo_dir = "changed"
    r.project.extra = 1
    compare(JSON.stringify(raw), before, "changing the output leaves the input unchanged")

    var later = amRun("status-started.json")
    var out = Runs.normalizeRun(later)
    var outBefore = JSON.stringify(out)
    later.row.project.id = 42
    later.row.project.repo_dir = "later"
    later.row.project.extra = 1
    compare(JSON.stringify(out), outBefore, "changing the input after the call leaves the output unchanged")
  }

  function test_normalize_project_own_proto_key() {
    // synthetic: an own __proto__ key inside the row's project, which no capture contains
    var p = projectOf(JSON.parse('{"__proto__": {"id": 5, "repo_dir": "/evil"}, "id": 1, "repo_dir": "/p"}'))
    compare(Object.getPrototypeOf(p) === Object.prototype, true, "prototype")
    compare(Object.keys(p).sort().join(","), "id,repo_dir")
    compare(p.id, 1)
    compare(p.repo_dir, "/p")

    var only = projectOf(JSON.parse('{"__proto__": {"id": 5, "repo_dir": "/evil"}}'))
    compare(only.id, null, "an id behind __proto__ is not read")
    compare(only.repo_dir, "", "a repo_dir behind __proto__ is not read")
  }

  function test_normalize_as_of_seq_not_kept() {
    var raw = amRun("status-started.json")
    compare(raw.status.as_of_seq, 989, "the am status capture carries as_of_seq")
    compare(raw.status.store_id, "91b9e8afc25044c385859292bfabfde7", "the am status capture carries store_id")
    var plain = Runs.normalizeRun(raw)
    var keys = Object.keys(plain)
    compare(keys.indexOf("as_of_seq"), -1, "as_of_seq from am status")
    compare(keys.indexOf("store_id"), -1, "store_id from am status")

    // synthetic: the am runs envelope's as_of_seq and store_id placed on the row
    var envelope = F.load("runs.json").data
    compare(envelope.as_of_seq, 989, "the am runs capture carries as_of_seq")
    compare(envelope.store_id, "91b9e8afc25044c385859292bfabfde7", "the am runs capture carries store_id")
    var onRow = amRun("status-started.json")
    onRow.row.as_of_seq = envelope.as_of_seq
    onRow.row.store_id = envelope.store_id
    var r = Runs.normalizeRun(onRow)
    compare(Object.keys(r).indexOf("as_of_seq"), -1, "as_of_seq from the row")
    compare(Object.keys(r).indexOf("store_id"), -1, "store_id from the row")
    compare(JSON.stringify(r), JSON.stringify(plain), "the row's as_of_seq and store_id change nothing")
  }

  function test_normalize_unknown_keys_ignored() {
    var plain = Runs.normalizeRun(amRun("status-started.json"))

    // synthetic: keys normalizeRun does not read, on raw, the row, am status and the am status run
    var raw = amRun("status-started.json")
    raw.extra = { a: 1 }
    raw.row.future_key = "x"
    raw.status.future_key = [1]
    raw.status.run.future_key = { b: 2 }
    compare(JSON.stringify(Runs.normalizeRun(raw)), JSON.stringify(plain), "unknown keys change nothing")

    var fixture = amRun("status-started.json")
    var keys = Object.keys(plain)
    var rowKeys = ["progress"]
    for (var i = 0; i < rowKeys.length; i++) {
      verify(hasOwn(fixture.row, rowKeys[i]), "the capture's row carries " + rowKeys[i])
      compare(keys.indexOf(rowKeys[i]), -1, "row " + rowKeys[i] + " is not kept")
    }
    verify(hasOwn(fixture.row, "story_id") && hasOwn(fixture.row, "card_id"), "the capture's row carries story_id and card_id")
    verify(keys.indexOf("story_id") >= 0 && keys.indexOf("card_id") >= 0, "row story_id and card_id are kept (RR 1.2)")
    var statusKeys = ["warnings", "integrity"]
    for (var j = 0; j < statusKeys.length; j++) {
      verify(hasOwn(fixture.status, statusKeys[j]), "the capture's am status carries " + statusKeys[j])
      compare(keys.indexOf(statusKeys[j]), -1, "am status " + statusKeys[j] + " is not kept")
    }
  }

  function test_normalize_takes_no_events() {
    var plain = JSON.stringify(Runs.normalizeRun(amRun("status-started.json")))
    var log = F.load("events.json").data
    verify(log.events.length > 0, "the events capture has events")

    // synthetic: events.json's events and cursors placed on raw and on am status
    var raw = amRun("status-started.json")
    var targets = [raw, raw.status]
    for (var i = 0; i < targets.length; i++) {
      targets[i].events = log.events
      targets[i].gseq = log.events[log.events.length - 1].gseq
      targets[i].seq = log.events[0].seq
      targets[i].head = log.head
      targets[i].cursor_reset = true
    }
    compare(JSON.stringify(Runs.normalizeRun(raw)), plain, "events and cursors change nothing")
  }

  function test_normalize_project_garbage_never_throws() {
    // synthetic: a project whose id and repo_dir are the wrong types
    compare(JSON.stringify(projectOf({ id: {}, repo_dir: [] })), JSON.stringify({ id: null, repo_dir: "" }), "wrong types")

    // synthetic: a project with no prototype
    compare(JSON.stringify(projectOf(Object.create(null))), JSON.stringify({ id: null, repo_dir: "" }), "no prototype")
  }

  function test_fixture_current_phase_and_default_attempt() {
    var expected = [
      ["explore", "2280a6ab-9c40-434b-9729-63fd1f373754/explore/1"],
      ["", "767b5f1c-506a-4daa-9157-0c838165cc63/review/1"],
      ["", "10e26d57-374c-48d3-bc45-09389b42cfac/review/1"],
      ["", "f74961fc-1d90-4ef4-9130-2246229bb71a/review/1"]
    ]
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      compare(Runs.currentPhase(runs[i]), expected[i][0], "currentPhase " + runs[i].id)
      compare(at(Runs.defaultAttempt(runs[i])), expected[i][1], "defaultAttempt " + runs[i].id)
    }
  }

  function test_fixture_card_run_state_and_runs_touching() {
    var runs = fixtureRuns()
    var open = Runs.cardRunState(runs, "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(open.state, "running")
    compare(open.runId, "20261008T143823Z-e795ad19")
    compare(open.dimmed, false)
    compare(open.phase, "explore")
    compare(open.attempt, 1)
    var escalated = Runs.cardRunState(runs, "10e26d57-374c-48d3-bc45-09389b42cfac")
    compare(escalated.state, "escalated")
    compare(escalated.runId, "20261008T143755Z-f18d342f")
    compare(escalated.dimmed, true)
    compare(escalated.phase, "review")
    compare(escalated.attempt, 1)

    var touchingOpen = Runs.runsTouching(runs, "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(touchingOpen.length, 1)
    verify(touchingOpen[0] === runs[0], "the started run")
    var touchingReal = Runs.runsTouching(runs, "f74961fc-1d90-4ef4-9130-2246229bb71a")
    compare(touchingReal.length, 1)
    verify(touchingReal[0] === runs[3], "the done-integrate run")
    var touchingStory = Runs.runsTouching(runs, "862eb9b7-bb74-452f-9148-0f6a34434ab3")
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
        compare(node.attempts.length, 14, node.card_id + " attempts")
        compare(opensOn(node), "review/1", node.card_id + ": the last phase with a numbered attempt, past verify and mark_done")
        count++
      }
    }
    compare(count, 10, "every done subtask is a node")

    var started = Runs.runTree(Runs.normalizeRun(amRun("status-started.json")))
    var expected = [
      ["5560d0fe-2b8e-4ef9-ad71-96b50ee89daa", "review/1"],
      ["0bddd95f-7876-4cfb-9064-f48a62b3aaed", "review/1"],
      ["e4214f55-1580-42fe-b0da-94a4e8b10912", "review/1"],
      ["2280a6ab-9c40-434b-9729-63fd1f373754", "explore/1"],
      ["0849081e-b432-465e-81b1-0d2bc834f5fa", "/0"],
      ["ddabd94d-4a4d-418e-a93e-c09470679a53", "/0"],
      ["d44f4062-a413-43b9-a355-ff0bd95c2716", "/0"],
      ["cf1814c9-e1ff-4dc9-96b7-592a904983e3", "/0"]
    ]
    for (var k = 0; k < expected.length; k++)
      compare(opensOn(treeNode(started, expected[k][0])), expected[k][1], "started run " + expected[k][0])

    var escalated = Runs.runTree(Runs.normalizeRun(amRun("status-escalated.json")))
    var expectedEscalated = [
      ["f6ac3b15-77df-4921-a9c0-0b442db53bb5", "review/1"],
      ["618d1b92-fe77-420d-b4b7-8e0165fad51a", "review/1"],
      ["10e26d57-374c-48d3-bc45-09389b42cfac", "review/1"],
      ["460aaaa9-0520-40f7-aaa5-f162afab8bc0", "/0"]
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
        if (list[j].card_id === "2280a6ab-9c40-434b-9729-63fd1f373754") subtask = list[j]
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

    var node = treeNode(Runs.runTree(Runs.normalizeRun(raw)), "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(opensOn(node), "mark_in_progress/0", "a started phase wins over an earlier numbered one, attempt 0 without attempts")
  }

  // ---- Live output 2.2: step entries, a started step, live selections ------------------------

  // The am subtask with this card id in a raw amRun's stories, else null.
  function rawSubtask(raw, cardId) {
    var stories = raw.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) {
        if (stories[i].subtasks[j].card_id === cardId) return stories[i].subtasks[j]
      }
    }
    return null
  }

  // status-started.json, raw, with 2280a6ab's explore finished and a
  // deterministic phase `name` started after it.
  function startedStepRaw(name) {
    var raw = amRun("status-started.json")
    var subtask = rawSubtask(raw, "2280a6ab-9c40-434b-9729-63fd1f373754")
    // synthetic: explore finished (phase done, attempt 1 ok) and a deterministic phase in flight -- no capture has one
    subtask.phases[1].status = "done"
    subtask.phases[1].attempts[0].status = "ok"
    subtask.phases.push({ name: name, kind: "deterministic", status: "started", started_at: "", ended_at: null, detail: null, attempts: [] })
    return raw
  }

  // "phase.attempt[:step]:status" for each attempts entry of a tree node, comma-joined.
  function entries(node) {
    return node.attempts.map(function(a) {
      return a.phase + "." + a.attempt + (a.step === true ? ":step" : "") + ":" + a.status
    }).join(",")
  }

  function test_fixture_normalized_phases_keep_kind() {
    var names = ["status-started.json", "status-done.json", "status-escalated.json", "status-done-integrate.json"]
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      var raw = amRun(names[i])
      var subtasks = runs[i].tree.subtasks
      var checked = 0
      for (var j = 0; j < subtasks.length; j++) {
        var am = rawSubtask(raw, subtasks[j].card_id)
        verify(am !== null, names[i] + " " + subtasks[j].card_id + " is in the capture")
        var phases = subtasks[j].phases
        for (var k = 0; k < phases.length; k++) {
          var label = names[i] + " " + subtasks[j].card_id + " " + phases[k].name
          verify(phases[k].kind === "agent" || phases[k].kind === "deterministic", label + " kind " + phases[k].kind)
          compare(phases[k].kind, am.phases[k].kind, label + " matches the capture")
          checked++
        }
      }
      verify(checked > 0, names[i] + " has phases")
    }
  }

  function test_fixture_run_tree_step_entries() {
    var done = amRun("status-done.json")
    var tree = Runs.runTree(Runs.normalizeRun(done))
    var nodes = 0
    for (var i = 0; i < tree.stories.length; i++) {
      for (var j = 0; j < tree.stories[i].subtasks.length; j++) {
        var node = tree.stories[i].subtasks[j]
        var am = rawSubtask(done, node.card_id)
        var stepNames = am.phases.filter(function(p) { return p.kind === "deterministic" })
                                 .map(function(p) { return p.name }).join(",")
        compare(stepNames, "worktree,mark_in_progress,plan_check,mark_validated,docs_commit,verify,mark_done", node.card_id + " capture")
        compare(node.attempts.length, 14, node.card_id + " attempts")
        var steps = node.attempts.filter(function(a) { return a.step === true })
        compare(steps.length, 7, node.card_id + " steps")
        compare(steps.map(function(a) { return a.phase }).join(","), stepNames, node.card_id + " steps in phase order")
        for (var s = 0; s < steps.length; s++) {
          compare(Object.keys(steps[s]).join(","), "phase,attempt,step,status", node.card_id + " step shape")
          compare(steps[s].attempt, 0, node.card_id + " " + steps[s].phase)
          compare(steps[s].status, "done", node.card_id + " " + steps[s].phase)
        }
        var agents = node.attempts.filter(function(a) { return !("step" in a) })
        compare(agents.length, 7, node.card_id + " agent attempts")
        for (var g = 0; g < agents.length; g++)
          compare(Object.keys(agents[g]).join(","), "phase,attempt,status", node.card_id + " agent shape")
        nodes++
      }
    }
    compare(nodes, 10, "every done subtask is a node")

    var escalated = Runs.runTree(Runs.normalizeRun(amRun("status-escalated.json")))
    var node10 = treeNode(escalated, "10e26d57-374c-48d3-bc45-09389b42cfac")
    compare(entries(node10),
            "worktree.0:step:done,explore.1:ok,mark_in_progress.0:step:done,plan_check.0:step:done," +
            "spec.1:ok,validate_spec.1:ok,plan.1:ok,validate_plan.1:ok," +
            "mark_validated.0:step:done,docs_commit.0:step:done,implement.1:ok,review.1:gate_failed")
    compare(node10.attempts[11].phase + "." + node10.attempts[11].attempt, "review.1")
    compare(node10.attempts[1].phase + "." + node10.attempts[1].attempt, "explore.1")
  }

  function test_fixture_run_tree_started_step_entry() {
    var node = treeNode(Runs.runTree(Runs.normalizeRun(startedStepRaw("verify"))), "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(entries(node), "worktree.0:step:done,explore.1:ok,verify.0:step:started")
    compare(opensOn(node), "verify/0")
  }

  function test_fixture_default_attempt_on_a_started_step() {
    compare(JSON.stringify(Runs.defaultAttempt(Runs.normalizeRun(startedStepRaw("verify")))),
            JSON.stringify({ card_id: "2280a6ab-9c40-434b-9729-63fd1f373754", phase: "verify", attempt: 0, step: true }))
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      var d = Runs.defaultAttempt(runs[i])
      verify(d !== null, "a default for " + runs[i].id)
      verify(!("step" in d), "an agent attempt carries no step key: " + runs[i].id)
    }
  }

  function test_fixture_is_live_selection_by_run_state() {
    var card = "2280a6ab-9c40-434b-9729-63fd1f373754"
    var explore = { card_id: card, phase: "explore", attempt: 1 }
    var verifyStep = { card_id: card, phase: "verify", attempt: 0, step: true }
    // [label, synthetic edit of the capture copy, runState, live]
    var cases = [
      ["running", function(raw) {}, "running", true],
      // synthetic: the lease edited to not live
      ["lease not live", function(raw) { raw.status.control.lease.live = false }, "dead", false],
      // synthetic: am's control removed, so no lease
      ["no control", function(raw) { delete raw.status.control }, "dead", false],
      // synthetic: the run status edited to stopped
      ["stopped", function(raw) { raw.status.run.status = "stopped" }, "parked", false],
      // synthetic: the run status edited to escalated
      ["escalated", function(raw) { raw.status.run.status = "escalated" }, "escalated", false],
      // synthetic: the run status edited to done
      ["done", function(raw) { raw.status.run.status = "done" }, "done", false],
      // synthetic: the run status edited to a status am does not give
      ["unknown", function(raw) { raw.status.run.status = "weird" }, "unknown", false]
    ]
    var spellings = cancelSpellings()
    for (var c = 0; c < spellings.length; c++) {
      // synthetic: the run status edited to a cancelled spelling
      cases.push([spellings[c], (function(s) { return function(raw) { raw.status.run.status = s } })(spellings[c]), "cancelled", false])
    }
    for (var i = 0; i < cases.length; i++) {
      var agentRaw = amRun("status-started.json")
      cases[i][1](agentRaw)
      var agentRun = Runs.normalizeRun(agentRaw)
      compare(Runs.runState(agentRun), cases[i][2], cases[i][0] + ": the edit gives the state")
      compare(Runs.isLiveSelection(agentRun, explore), cases[i][3], cases[i][0] + ": explore.1, attempt started")

      var stepRaw = startedStepRaw("verify")
      cases[i][1](stepRaw)
      var stepRun = Runs.normalizeRun(stepRaw)
      compare(Runs.runState(stepRun), cases[i][2], cases[i][0] + ": the edit gives the state (step)")
      compare(Runs.isLiveSelection(stepRun, verifyStep), cases[i][3], cases[i][0] + ": the verify step, phase started")
    }
  }

  function test_fixture_is_live_selection_by_attempt_status() {
    var card = "2280a6ab-9c40-434b-9729-63fd1f373754"
    var explore = { card_id: card, phase: "explore", attempt: 1 }
    var statuses = [["started", true], ["ok", false], ["gate_failed", false], ["schema_invalid", false],
                    ["harness_error", false], ["", false]]
    for (var i = 0; i < statuses.length; i++) {
      var raw = amRun("status-started.json")
      var attempt = rawSubtask(raw, card).phases[1].attempts[0]
      compare(rawSubtask(raw, card).phases[1].name + "." + attempt.n, "explore.1", "the capture's explore.1")
      // synthetic: explore.1's status edited
      attempt.status = statuses[i][0]
      compare(Runs.isLiveSelection(Runs.normalizeRun(raw), explore), statuses[i][1], "attempt status '" + statuses[i][0] + "'")
    }
    var started = Runs.normalizeRun(amRun("status-started.json"))
    compare(Runs.isLiveSelection(started, { card_id: "5560d0fe-2b8e-4ef9-ad71-96b50ee89daa", phase: "review", attempt: 1 }), false,
            "a finished attempt of a running run")
    compare(Runs.isLiveSelection(started, { card_id: card, phase: "worktree", attempt: 0, step: true }), false,
            "a done step of a running run")
    var escalated = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(Runs.isLiveSelection(escalated, { card_id: "10e26d57-374c-48d3-bc45-09389b42cfac", phase: "review", attempt: 1 }), false,
            "the escalated capture's gate_failed review.1")
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
      ["status-started.json", "e795ad19-c81f-43ec-bdda-ef61ab5f860b", "1,0,0,3,4,8"],
      ["status-done.json", "63060df3-f582-4eb9-a56e-44cadb15b693", "0,0,0,10,0,10"],
      ["status-escalated.json", "f18d342f-4887-4cd8-a86e-dd2755237c2c", "0,0,1,2,1,4"],
      ["status-escalated-integrate.json", "76043cd6-2077-47d4-afbb-c0ab60e62416", "0,0,0,2,0,2"],
      ["status-done-integrate.json", "f7f73454-b9c5-464a-b8d4-659dd5b353af", "0,0,0,2,0,2"]
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
      [started, "7a7effb4-6ec5-4596-bcf1-be24546d4ac1", "1,0,0,1,1,3", "started: story"],
      [started, "2280a6ab-9c40-434b-9729-63fd1f373754", "1,0,0,0,0,1", "started: subtask with 2 rows"],
      [done, "c9965561-026a-4747-a3f3-3fdfa6a99ded", "0,0,0,4,0,4", "done: story"],
      [done, "767b5f1c-506a-4daa-9157-0c838165cc63", "0,0,0,1,0,1", "done: subtask with 14 rows"],
      [escalated, "bf8154fc-e65c-46f5-b6e8-92b616a6e62b", "0,0,1,0,0,1", "escalated: story"],
      [escalated, "10e26d57-374c-48d3-bc45-09389b42cfac", "0,0,1,0,0,1", "escalated: subtask with 12 rows"],
      [doneIntegrate, "862eb9b7-bb74-452f-9148-0f6a34434ab3", "0,0,0,1,0,1",
       "done-integrate: real story whose id the Integrate resolver carries"]
    ]
    for (var i = 0; i < cases.length; i++) {
      compare(counts(Runs.rollup(cases[i][0], { id: cases[i][1] })), cases[i][2], cases[i][3])
    }
  }

  function test_rollup_never_reads_rows() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    compare(run.milestone_id, "63060df3-f582-4eb9-a56e-44cadb15b693")
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
      ["status-escalated.json", "phase 'review' gate 'review_blockers_gate' failed: blocked=review, detail=review left 1 unresolved blocker(s): the review-fail marker names m3/task-b1-only-subtask-of-10e26d57"],
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
    compare(Runs.normalizeRun(amRun("status-started.json")).started_at, "2026-10-08 14:38:23.739155+00:00",
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
    var between = subtaskOf(started, "2280a6ab-9c40-434b-9729-63fd1f373754")
    compare(between.status, "started")
    compare(between.phases.length, 2)
    between.phases = [between.phases[0]]
    compare(between.phases[0].name + ":" + between.phases[0].status, "worktree:done")
    compare(progressText(Runs.runProgress(started)), "3/8", "every recorded phase done, status started")

    // synthetic: a done subtask's status set to started, its phases left all done
    var stalled = Runs.normalizeRun(amRun("status-done.json"))
    var restarted = subtaskOf(stalled, "767b5f1c-506a-4daa-9157-0c838165cc63")
    compare(restarted.status, "done")
    restarted.status = "started"
    compare(progressText(Runs.runProgress(stalled)), "9/10", "status started is not done")

    // synthetic: a done subtask's phases emptied
    var bare = Runs.normalizeRun(amRun("status-done.json"))
    var emptied = subtaskOf(bare, "767b5f1c-506a-4daa-9157-0c838165cc63")
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
  // fixture's text (stdout: 1 line, stderr: null).
  function logsData(stdout, stderr) {
    var data = F.load("logs-attempt.json").data
    // synthetic: the texts are the test's; the shape is the capture's.
    if (stdout !== undefined) data.artifacts.stdout.text = stdout
    if (stderr !== undefined) data.artifacts.stderr.text = stderr
    return data
  }

  // The capture's stdout text as its lines (it has 1).
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
    compare(lines.length, 1)
    compare(lines[0], "fake-claude ok phase=review")
    compare(tail.truncated, false)
    verify(tail.text.indexOf("# Reviewer") < 0, "the prompt artifact is not shown")

    // The capture's stdout is one line: a tail of exactly that many lines is all of it.
    var one = Runs.logTail(F.load("logs-attempt.json").data, 1)
    compare(one.text, lines[0], "the last 1 of the 1 line")
    compare(one.truncated, false)
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

  function test_run_tree_step_entries_rule() {
    function det(name, status) { return { name: name, kind: "deterministic", status: status, attempts: [] } }
    function other(name, kind) { return { name: name, kind: kind, status: "done", attempts: [] } }
    // synthetic: hand-built normalized subtasks, one per case of the step-entry rule
    var run = mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "a", phases: [
        det("s1", "started"), det("s2", "done"), det("s3", "failed"), det("s4", "escalated"),
        det("s5", "stopped"), det("s6", "cancelled"), det("s7", "canceled"),
        det("p1", "pending"), det("p2", ""), det("p3", "running"), det("p4", null), det("p5", 5),
        det("p6", "Started"), det("p7", "constructor"), { name: "p8", kind: "deterministic", attempts: [] },
        other("k1", "agent"), { name: "k2", status: "done", attempts: [] }, other("k3", "Deterministic"), other("k4", 5),
        { name: "x", kind: "deterministic", status: "done", attempts: [{ n: 1, status: "ok" }] },
        det("", "done"), { kind: "deterministic", status: "done", attempts: [] }, { name: 7, kind: "deterministic", status: "done" }
      ] },
      { card_id: "b", phases: [det("verify", "done"), det("verify", "started")] }
    ] } })
    var before = JSON.stringify(run)
    var t = Runs.runTree(run)
    compare(JSON.stringify(run), before, "the run is not mutated")
    var a = treeNode(t, "a")
    compare(entries(a),
            "s1.0:step:started,s2.0:step:done,s3.0:step:failed,s4.0:step:escalated," +
            "s5.0:step:stopped,s6.0:step:cancelled,s7.0:step:canceled,x.0:step:done,x.1:ok")
    compare(Object.keys(a.attempts[0]).join(","), "phase,attempt,step,status", "step entry key order")
    compare(Object.keys(a.attempts[8]).join(","), "phase,attempt,status", "a step phase's own attempt has no step key")
    compare(Object.keys(a.phases[0]).join(","), "name,status", "phases entries carry no kind")
    compare(opensOn(a), "s1/0", "the current-phase rule is unchanged")
    compare(entries(treeNode(t, "b")), "verify.0:step:done,verify.0:step:started", "one step entry per phase object")
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

  function test_default_attempt_prefers_the_first_started_phase() {
    function step(name, status) { return { name: name, kind: "deterministic", status: status, attempts: [] } }
    function agent(name, status, attempts) { return { name: name, kind: "agent", status: status, attempts: attempts } }
    function dflt(subtasks, rows) {
      // synthetic: hand-built normalized subtasks for the default-attempt rule
      var run = mkRun("r", "started", true, { rows: rows || [], tree: { stories: [], subtasks: subtasks } })
      var before = JSON.stringify(run)
      var d = Runs.defaultAttempt(run)
      compare(JSON.stringify(run), before, "the run is not mutated")
      return JSON.stringify(d)
    }
    compare(dflt([{ card_id: "a", phases: [step("worktree", "done"), step("verify", "started")] },
                  { card_id: "b", phases: [agent("implement", "started", [{ n: 1, status: "started" }])] }]),
            JSON.stringify({ card_id: "a", phase: "verify", attempt: 0, step: true }),
            "a started step of an earlier subtask wins over a later numbered attempt")
    compare(dflt([{ card_id: "a", phases: [agent("plan", "started", []), step("verify", "started")] }]),
            JSON.stringify({ card_id: "a", phase: "verify", attempt: 0, step: true }),
            "a started agent phase without numbers is passed over for a later started step")
    compare(dflt([{ card_id: "a", phases: [agent("implement", "started", [{ n: 2, status: "started" }]), step("verify", "started")] }]),
            JSON.stringify({ card_id: "a", phase: "implement", attempt: 2 }),
            "a started agent attempt before a started step wins, with no step key")
    compare(dflt([{ card_id: "integrate", phases: [step("integrate", "started")] }]), "null",
            "a bookkeeping id with a started step is never a card")
    compare(dflt([{ card_id: "a", phases: [step("", "started"), step("verify", "running"), step("verify", "done")] }],
                 [{ card_id: "a", phase: "verify", attempt: null, status: "done" }]), "null",
            "an unnamed or not-started step is not chosen, and the row fallback never yields a step")
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

  function test_phase_status() {
    var card = "2280a6ab-9c40-434b-9729-63fd1f373754"
    var started = Runs.normalizeRun(amRun("status-started.json"))
    var before = JSON.stringify(started)
    compare(Runs.phaseStatus(started, card, "worktree"), "done", "the capture's worktree step")
    compare(Runs.phaseStatus(started, card, "explore"), "started", "an agent phase's own status")
    compare(Runs.phaseStatus(started, "00000000-0000-0000-0000-000000000000", "worktree"), "", "an unknown card")
    compare(Runs.phaseStatus(started, card, "verify"), "", "an unknown phase")
    var phases = ["", null, undefined, 3, {}, []]
    for (var i = 0; i < phases.length; i++)
      compare(Runs.phaseStatus(started, card, phases[i]), "", "phase " + JSON.stringify(phases[i]))
    var cards = ["", null, undefined, 7, {}]
    for (var c = 0; c < cards.length; c++)
      compare(Runs.phaseStatus(started, cards[c], "worktree"), "", "card " + JSON.stringify(cards[c]))
    var runs = [null, undefined, {}, "x", 5, []]
    for (var r = 0; r < runs.length; r++)
      compare(Runs.phaseStatus(runs[r], card, "worktree"), "", "run " + JSON.stringify(runs[r]))
    compare(JSON.stringify(started), before, "the run is not changed")

    // synthetic: a non-string status, a repeated phase name and bookkeeping ids with started phases
    var odd = { tree: { subtasks: [
      { card_id: "t9", phases: [{ name: "verify", status: 5 }, { name: "verify", status: "done" }] },
      { card_id: "t8", phases: [{ name: "verify", kind: "deterministic", status: "started" }, { name: "verify", status: "done" }] },
      { card_id: "integrate", phases: [{ name: "integrate", status: "started" }] },
      { card_id: "bases", phases: [{ name: "bases", status: "started" }] },
      { card_id: "base-s1", phases: [{ name: "worktree", status: "started" }] }
    ] } }
    compare(Runs.phaseStatus(odd, "t9", "verify"), "", "the first phase of the name has no string status")
    compare(Runs.phaseStatus(odd, "t8", "verify"), "started", "the first phase of that name decides")
    compare(Runs.phaseStatus(odd, "integrate", "integrate"), "", "integrate is not a card")
    compare(Runs.phaseStatus(odd, "bases", "bases"), "", "bases is not a card")
    compare(Runs.phaseStatus(odd, "base-s1", "worktree"), "", "base-* is not a card")
  }

  function test_is_live_selection_garbage() {
    var results = []
    function live(run, sel, label) {
      var r = Runs.isLiveSelection(run, sel)
      results.push([r, label])
      return r
    }
    var run = detailRun()
    var good = { card_id: "t1", phase: "implement", attempt: 2 }
    compare(live(run, good, "baseline"), true, "the baseline selection is live")

    var badRuns = [undefined, null, "x", 5, [], {}, { tree: "x" }]
    for (var i = 0; i < badRuns.length; i++) compare(live(badRuns[i], good, "run " + i), false, "garbage run " + i)

    var badSels = [undefined, null, "x", 5, [], {},
      { card_id: "", phase: "implement", attempt: 2 }, { card_id: 7, phase: "implement", attempt: 2 },
      { card_id: null, phase: "implement", attempt: 2 }, { phase: "implement", attempt: 2 },
      { card_id: "t1", attempt: 2 }, { card_id: "t1", phase: "", attempt: 2 }, { card_id: "t1", phase: 5, attempt: 2 },
      { card_id: "t1", phase: null, attempt: 2, step: true },
      { card_id: "zz", phase: "implement", attempt: 2 }, { card_id: "zz", phase: "implement", attempt: 0, step: true },
      { card_id: "t1", phase: "verify", attempt: 2 }, { card_id: "t1", phase: "verify", attempt: 0, step: true },
      { card_id: "t1", phase: "implement", attempt: "2" }, { card_id: "t1", phase: "implement", attempt: 0 },
      { card_id: "t1", phase: "implement", attempt: -2 }, { card_id: "t1", phase: "implement", attempt: NaN },
      { card_id: "t1", phase: "implement", attempt: Infinity }, { card_id: "t1", phase: "implement" }]
    for (var j = 0; j < badSels.length; j++) compare(live(run, badSels[j], "sel " + j), false, "garbage selection " + j)

    // synthetic: bookkeeping ids carrying a started attempt and a started step
    var books = mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "integrate", phases: [{ name: "integrate", status: "started", attempts: [{ n: 1, status: "started" }] }] },
      { card_id: "bases", phases: [{ name: "bases", kind: "deterministic", status: "started", attempts: [{ n: 1, status: "started" }] }] },
      { card_id: "base-s1", phases: [{ name: "base", status: "started", attempts: [{ n: 1, status: "started" }] }] }] } })
    var ids = [["integrate", "integrate"], ["bases", "bases"], ["base-s1", "base"]]
    for (var k = 0; k < ids.length; k++) {
      compare(live(books, { card_id: ids[k][0], phase: ids[k][1], attempt: 1 }, ids[k][0]), false, ids[k][0] + " attempt")
      compare(live(books, { card_id: ids[k][0], phase: ids[k][1], attempt: 0, step: true }, ids[k][0] + " step"), false, ids[k][0] + " step")
    }

    var before = JSON.stringify(run) + JSON.stringify(good)
    live(run, good, "again")
    compare(JSON.stringify(run) + JSON.stringify(good), before, "neither argument is mutated")
    for (var r = 0; r < results.length; r++) compare(typeof results[r][0], "boolean", "a boolean: " + results[r][1])
  }

  function test_is_live_selection_step_flag() {
    // synthetic: a running run with a started agent phase, a started step and a re-run step
    var run = mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [
        { name: "spec", kind: "agent", status: "done", attempts: [{ n: 1, status: "ok" }] },
        { name: "implement", kind: "agent", status: "started", attempts: [{ n: 1, status: "gate_failed" }, { n: 2, status: "started" }] }] },
      { card_id: "t2", phases: [
        { name: "worktree", kind: "deterministic", status: "done", attempts: [] },
        { name: "verify", kind: "deterministic", status: "started", attempts: [] }] },
      { card_id: "t3", phases: [
        { name: "verify", kind: "deterministic", status: "done", attempts: [] },
        { name: "verify", kind: "deterministic", status: "started", attempts: [] }] }] } })
    var cases = [
      [{ card_id: "t1", phase: "implement", attempt: 2 }, true, "a started attempt"],
      [{ card_id: "t1", phase: "implement", attempt: 0, step: true }, true, "step: true reads the phase, which is started"],
      [{ card_id: "t1", phase: "implement", attempt: 0 }, false, "attempt 0 without step"],
      [{ card_id: "t1", phase: "implement", attempt: 2, step: "true" }, true, "step \"true\" is the agent branch"],
      [{ card_id: "t1", phase: "implement", attempt: 0, step: "true" }, false, "step \"true\" with attempt 0"],
      [{ card_id: "t1", phase: "implement", attempt: 0, step: 1 }, false, "step 1 with attempt 0"],
      [{ card_id: "t1", phase: "implement", attempt: 2, step: false, extra: "x" }, true, "step false and extra keys: the agent branch"],
      [{ card_id: "t1", phase: "implement", attempt: 1 }, false, "a gate_failed attempt of a started phase"],
      [{ card_id: "t1", phase: "spec", attempt: 0, step: true }, false, "a done phase as a step"],
      [{ card_id: "t2", phase: "verify", attempt: 0, step: true }, true, "a started step"],
      [{ card_id: "t2", phase: "verify", attempt: 5, step: true }, true, "a step selection's attempt is not read"],
      [{ card_id: "t2", phase: "verify", attempt: "x", step: true }, true, "not even a non-number"],
      [{ card_id: "t2", phase: "verify", attempt: 0 }, false, "a started step without step: true"],
      [{ card_id: "t2", phase: "worktree", attempt: 0, step: true }, false, "a done step"],
      [{ card_id: "t3", phase: "verify", attempt: 0, step: true }, false, "a repeated name reads the first phase, which is done"]
    ]
    for (var i = 0; i < cases.length; i++)
      compare(Runs.isLiveSelection(run, cases[i][0]), cases[i][1], cases[i][2])
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
  readonly property string ctlResumeEscalatedCard: "An escalated card run cannot be resumed; relaunch it"

  // mkRun with the lease's accepting flag set; live === null still means no lease.
  function ctlRun(status, live, accepting) {
    var r = mkRun("rc", status, live)
    if (r.lease !== null) r.lease.accepting = accepting
    return r
  }

  // ctlRun with a `workflow` (mkRun sets none); an escalated "task" run is an escalated card run.
  function ctlRunOf(status, live, accepting, workflow) {
    var r = ctlRun(status, live, accepting)
    r.workflow = workflow
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

  function test_controls_escalated_card_run() {
    var run = ctlRunOf("escalated", false, true, "task")
    compare(Runs.runState(run), "escalated", "fixture")
    checkControls(Runs.controls(run), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, accepting")
    checkControls(Runs.controls(ctlRunOf("escalated", false, false, "task")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, ctlIntegrate, "task, Integrate")
    checkControls(Runs.controls(ctlRunOf("escalated", null, false, "task")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, no lease is not Integrate")
    checkControls(Runs.controls(ctlRunOf("escalated", false, true, "  task  ")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, padded")
    checkControls(Runs.controls(ctlRunOf("escalated", false, true, "\ttask\n")),
                  ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, tab and newline")
    var liveRun = ctlRunOf("escalated", true, true, "task")
    compare(Runs.runState(liveRun), "escalated", "a live lease does not change an escalated state")
    checkControls(Runs.controls(liveRun), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "task, live lease")
  }

  function test_controls_escalated_card_run_from_fixture() {
    var r = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(r.workflow, "milestone", "recorded workflow")
    r.workflow = "task"
    compare(r.lease, null, "the capture has no lease")
    checkControls(Runs.controls(r), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "escalated capture as a task run")
  }

  function test_controls_escalated_milestone_run_unchanged() {
    var r = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(r.workflow, "milestone", "recorded workflow")
    compare(Runs.runState(r), "escalated", "recorded state")
    checkControls(Runs.controls(r), ctlPauseNotRunning, "", "", "escalated milestone capture")
  }

  function test_controls_escalated_card_run_normalized() {
    // synthetic: the workflow from only the `am runs` row, or only `am status`
    var fromRow = Runs.normalizeRun({ row: { id: "r", status: "escalated", workflow: " task " } })
    checkControls(Runs.controls(fromRow), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "workflow on the row")
    var fromStatus = Runs.normalizeRun({ status: { run: { id: "r", status: "escalated", workflow: "task" } } })
    checkControls(Runs.controls(fromStatus), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "workflow in am status")
    var rowWins = Runs.normalizeRun({ row: { id: "r", workflow: "milestone" },
                                      status: { run: { id: "r", status: "escalated", workflow: "task" } } })
    checkControls(Runs.controls(rowWins), ctlPauseNotRunning, "", "", "the row's milestone workflow wins")
  }

  function test_controls_escalated_other_workflows_resumable() {
    var noProto = Object.create(null)
    var workflows = ["", "Task", "TASK", "tasks", "task run", "milestone", 5, {}, null, undefined, noProto]
    for (var i = 0; i < workflows.length; i++)
      checkControls(Runs.controls(ctlRunOf("escalated", false, true, workflows[i])), ctlPauseNotRunning, "", "",
                    "escalated, workflow " + i)
    checkControls(Runs.controls(ctlRun("escalated", false, true)), ctlPauseNotRunning, "", "",
                  "escalated, workflow missing")
  }

  function test_controls_task_run_other_states() {
    checkControls(Runs.controls(ctlRunOf("started", false, true, "task")), ctlPauseNotRunning, "", "", "dead task run")
    checkControls(Runs.controls(ctlRunOf("started", null, true, "task")), ctlPauseNotRunning, "", "",
                  "dead task run, no lease")
    checkControls(Runs.controls(ctlRunOf("stopped", false, true, "task")), ctlPauseNotRunning, "", "", "parked task run")
    checkControls(Runs.controls(ctlRunOf("started", true, true, "task")), "", ctlResumeRunning, "", "running task run")
    var spellings = cancelSpellings()
    for (var i = 0; i < spellings.length; i++)
      checkControls(Runs.controls(ctlRunOf(spellings[i], false, true, "task")),
                    ctlFinished, ctlResumeCancelled, ctlCancelCancelled, spellings[i] + " task run")
    checkControls(Runs.controls(ctlRunOf("done", false, true, "task")), ctlFinished, ctlFinished, ctlFinished,
                  "done task run")
    checkControls(Runs.controls(ctlRunOf("weird", true, true, "task")), ctlUnknown, ctlUnknown, ctlUnknown,
                  "unknown task run")
  }

  function test_controls_escalated_card_run_fresh() {
    var run = ctlRunOf("escalated", false, true, "task")
    var a = Runs.controls(run)
    var b = Runs.controls(run)
    verify(a !== b, "a fresh result per call")
    verify(a.pause !== b.pause && a.resume !== b.resume && a.cancel !== b.cancel, "fresh actions per call")
    verify(a.pause !== a.resume && a.resume !== a.cancel && a.pause !== a.cancel, "no action shared within a result")
    a.resume.enabled = true
    a.resume.reason = ""
    delete a.pause
    checkControls(b, ctlPauseNotRunning, ctlResumeEscalatedCard, "", "the second result after mutating the first")
    checkControls(Runs.controls(run), ctlPauseNotRunning, ctlResumeEscalatedCard, "", "a third call")
  }

  // [type, sentence] for every am control error controlError knows.
  function controlErrorTable() {
    return [
      ["UnknownRunError", "The run no longer exists"],
      ["NotRunningError", "The run is not running"],
      ["DeadRunError", "The run's process has died, so nobody can act on this request. Resume picks the run up."],
      ["NotAcceptingError", ctlIntegrate],
      ["RunIsLiveError", "Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died."],
      ["NotResumableError", "am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work."],
      ["CheckpointMismatchError", "The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase."],
      ["ClaimedError", "Another run has already claimed this work"],
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
  }

  function test_control_error_table() {
    var table = controlErrorTable()
    compare(table.length, 9)
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
            "The run's process has died, so nobody can act on this request. Resume picks the run up.",
            "the message is not shown for a known type")
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

  function test_control_sentences_are_ascii() {
    var texts = [Runs.controls(ctlRunOf("escalated", false, true, "task")).resume.reason]
    var table = controlErrorTable()
    for (var i = 0; i < table.length; i++)
      texts.push(Runs.controlError({ ok: false, error: { type: table[i][0], message: "m" } }))
    for (var j = 0; j < texts.length; j++) {
      for (var k = 0; k < texts[j].length; k++)
        verify(texts[j].charCodeAt(k) < 128, "plain ASCII: text " + j + " at " + k)
    }
  }

  // offersRelaunch(error) is exactly the boolean `want`, never another falsy or truthy value.
  function checkRelaunch(error, want, label) {
    var got = Runs.offersRelaunch(error)
    compare(typeof got, "boolean", label + " is a boolean")
    compare(got, want, label)
  }

  function test_offers_relaunch_table() {
    var table = controlErrorTable()
    var offered = 0
    for (var i = 0; i < table.length; i++) {
      var type = table[i][0]
      var want = type === "NotResumableError" || type === "CheckpointMismatchError"
      if (want) offered++
      checkRelaunch({ ok: false, error: { type: type, message: "m" } }, want, "envelope " + type)
      checkRelaunch({ type: type }, want, "bare " + type)
      checkRelaunch({ type: type, message: "m" }, want, "bare with message " + type)
    }
    compare(offered, 2, "two types offer relaunch")
  }

  function test_offers_relaunch_reading() {
    checkRelaunch({ ok: false, error: { type: "  NotResumableError\n", message: "m" } }, true, "trimmed envelope")
    checkRelaunch({ type: "  NotResumableError\n" }, true, "trimmed bare")
    checkRelaunch({ type: " CheckpointMismatchError " }, true, "trimmed bare checkpoint")
    checkRelaunch({ ok: false, error: { type: "notresumableerror", message: "m" } }, false, "case-sensitive envelope")
    checkRelaunch({ type: "CHECKPOINTMISMATCHERROR" }, false, "case-sensitive bare")
    var bare = Object.create(null)
    bare.type = "CheckpointMismatchError"
    checkRelaunch(bare, true, "prototype-less bare error")
    checkRelaunch({ ok: false, type: "NotResumableError", error: { type: "Foo" } }, false,
                  "the envelope's error wins over a stray outer type")
    checkRelaunch({ ok: false, type: "Foo", error: { type: "NotResumableError" } }, true,
                  "the envelope's error is read")
    checkRelaunch({ ok: true, error: { type: "NotResumableError" } }, false, "ok:true")
    checkRelaunch({ ok: false, error: "NotResumableError" }, false, "a string error reads the outer object")
  }

  function test_offers_relaunch_unknown_and_garbage() {
    checkRelaunch({ ok: false, error: { type: "Foo", message: "bar" } }, false, "unknown type")
    checkRelaunch({ ok: false, error: { type: "", message: "bar" } }, false, "empty type")
    checkRelaunch({ type: "" }, false, "empty bare type")
    var protoNames = ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]
    for (var k = 0; k < protoNames.length; k++) {
      checkRelaunch({ ok: false, error: { type: protoNames[k], message: "m" } }, false, "envelope " + protoNames[k])
      checkRelaunch({ type: protoNames[k] }, false, "bare " + protoNames[k])
    }
    var noProto = Object.create(null)
    checkRelaunch({ ok: false, error: { type: noProto, message: "m" } }, false, "prototype-less type object, envelope")
    checkRelaunch({ type: noProto }, false, "prototype-less type object, bare")
    var arrayError = []
    arrayError.type = "NotResumableError"
    var garbage = [undefined, null, "NotResumableError", 5, true, [], {}, { ok: false }, { ok: true },
                   Object.create(null), arrayError]
    for (var i = 0; i < garbage.length; i++)
      checkRelaunch(garbage[i], false, "garbage " + i)
  }

  function test_offers_relaunch_parsed_json() {
    // synthetic: am's reply text as RunStore parses it
    checkRelaunch(JSON.parse('{"ok": false, "error": {"type": "NotResumableError", "message": "run r1 is cancelled"}}'),
                  true, "parsed NotResumableError")
    checkRelaunch(JSON.parse('{"ok": false, "error": {"type": "CheckpointMismatchError", "message": "m"}}'),
                  true, "parsed CheckpointMismatchError")
    checkRelaunch(JSON.parse('{"ok": false, "error": {"type": "RunIsLiveError", "message": "run r1 is live"}}'),
                  false, "parsed RunIsLiveError")
    checkRelaunch(JSON.parse('{"__proto__": {"type": "NotResumableError"}}'), false,
                  "an own __proto__ key is not read as the prototype")
    checkRelaunch(JSON.parse('{"ok": false, "error": {"__proto__": {"type": "NotResumableError"}}}'), false,
                  "an own __proto__ key inside the envelope")
  }

  function test_offers_relaunch_agrees_with_control_error() {
    var relaunchSentences = [controlErrorTable()[5][1], controlErrorTable()[6][1]]
    var noProto = Object.create(null)
    noProto.type = "NotResumableError"
    var inputs = [undefined, null, "x", 5, [], {}, { ok: true }, { ok: false }, noProto,
                  { type: "Foo" }, { ok: false, error: "CheckpointMismatchError" },
                  { ok: false, type: "NotResumableError", error: { type: "Foo" } },
                  { ok: false, type: "Foo", error: { type: "CheckpointMismatchError" } }]
    var table = controlErrorTable()
    for (var i = 0; i < table.length; i++) {
      inputs.push({ ok: false, error: { type: table[i][0], message: "m" } })
      inputs.push({ type: " " + table[i][0] + " " })
    }
    for (var j = 0; j < inputs.length; j++) {
      var sentence = Runs.controlError(inputs[j])
      var isRelaunchSentence = sentence === relaunchSentences[0] || sentence === relaunchSentences[1]
      compare(Runs.offersRelaunch(inputs[j]), isRelaunchSentence, "input " + j + ": " + sentence)
    }
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

  // ---- S6 1.1: the run's registered project -----------------------------------------------

  function test_with_project_from_fixture() {
    var runs = fixtureRuns()
    for (var i = 0; i < runs.length; i++) {
      var run = runs[i]
      var label = "fixture " + i
      compare(run.project.repo_dir, "/home/user/Code/omarchy-project-manager", label + " repo_dir")
      var out = Runs.withProject(run, run.project.repo_dir, "omarchy-project-manager")
      compare(Object.keys(out.project).sort().join(","), "name,root", label + " project keys")
      compare(out.project.root, "/home/user/Code/omarchy-project-manager", label + " root")
      compare(out.project.name, "omarchy-project-manager", label + " name")
      compare(Object.keys(out).sort().join(","), Object.keys(run).sort().join(","), label + " keys")
      var keys = Object.keys(run)
      for (var k = 0; k < keys.length; k++) {
        if (keys[k] === "project") continue
        compare(JSON.stringify(out[keys[k]]), JSON.stringify(run[keys[k]]), label + " " + keys[k])
      }
    }
  }

  function test_with_project_is_a_copy() {
    var run = Runs.normalizeRun(amRun("status-started.json"))
    var before = JSON.stringify(run)
    var out = Runs.withProject(run, "/p/one", "One")
    compare(JSON.stringify(run), before, "input unchanged by the call")
    verify(out !== run, "a new run")
    verify(out.tree !== run.tree, "a new tree")
    verify(out.tree.stories !== run.tree.stories, "new stories")
    verify(out.tree.stories[0] !== run.tree.stories[0], "a new story")
    verify(out.tree.subtasks[0] !== run.tree.subtasks[0], "a new subtask")
    verify(out.rows !== run.rows, "new rows")
    verify(out.lease !== run.lease, "a new lease")
    verify(out.requests !== run.requests, "new requests")

    out.tree.stories[0].title = "changed"
    out.tree.stories[0].subtasks.push("x")
    out.tree.subtasks[0].phases = []
    out.rows[0].status = "changed"
    out.rows.push({})
    out.lease.live = false
    out.requests.push({ command: "pause" })
    out.project.root = "/elsewhere"
    compare(JSON.stringify(run), before, "input unchanged by mutating the result")
    compare(run.project.repo_dir, "/home/user/Code/omarchy-project-manager", "input project kept")

    // re-projecting a projected run: the new project wins, the first result is untouched
    var again = Runs.withProject(out, "/p/two/", null)
    compare(Object.keys(again.project).sort().join(","), "name,root", "re-projected keys")
    compare(again.project.root, "/p/two", "re-projected root")
    compare(again.project.name, "two", "re-projected name")
    compare(out.project.root, "/elsewhere", "first result unchanged")
  }

  function test_with_project_trailing_slash() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    // synthetic: roots with trailing slashes, only slashes, empty, padded and unresolved
    var cases = [["/a/b/", "/a/b"], ["/a/b///", "/a/b"], ["/a/b", "/a/b"], ["/", "/"], ["//", "/"], ["", ""],
                 [" /a/b ", " /a/b "], ["/a/b/ ", "/a/b/ "], ["/A/./b/../c/", "/A/./b/../c"], ["~/x/", "~/x"]]
    for (var i = 0; i < cases.length; i++) {
      compare(Runs.withProject(run, cases[i][0], "N").project.root, cases[i][1], JSON.stringify(cases[i][0]))
    }
  }

  function test_with_project_name_fallback() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    // synthetic: names that are missing, null, blank or not a string
    var blanks = [["undefined", undefined], ["null", null], ["empty", ""], ["spaces", "   "], ["tab", "\t"],
                  ["number", 42], ["object", {}], ["array", ["x"]], ["boolean", true]]
    for (var i = 0; i < blanks.length; i++) {
      compare(Runs.withProject(run, "/a/proj/", blanks[i][1]).project.name, "proj", blanks[i][0])
    }
    compare(Runs.withProject(run, "/a/proj/").project.name, "proj", "name argument omitted")
    compare(Runs.withProject(run, "/", null).project.name, "/", "root /")
    compare(Runs.withProject(run, "//", "").project.name, "/", "root //")
    compare(Runs.withProject(run, "", null).project.name, "", "root empty")
    compare(Runs.withProject(run, 5, null).project.name, "", "root not a string")
    compare(Runs.withProject(run, "proj", null).project.name, "proj", "a relative root is its own name")
    compare(Runs.withProject(run, "proj", null).project.root, "proj", "a relative root is kept")
    compare(Runs.withProject(run, "/home/user/Code/omarchy-project-manager", null).project.name,
            "omarchy-project-manager", "the fixture root")
    compare(Runs.withProject(run, "/a/proj", "  My Proj  ").project.name, "My Proj", "a given name is trimmed")
    compare(Runs.withProject(run, "/a/proj", "team/app").project.name, "team/app", "a given name is kept verbatim")
    compare(Runs.withProject(run, "/a/proj", "Proj").project.name, "Proj", "case kept")
  }

  function test_with_project_garbage() {
    var run = Runs.normalizeRun(amRun("status-done.json"))
    // synthetic: values that are not a run are returned as is
    var notRuns = [undefined, null, "x", 5, true, [], [run]]
    for (var i = 0; i < notRuns.length; i++) {
      verify(Runs.withProject(notRuns[i], "/p", "P") === notRuns[i], "not a run " + i)
    }

    // synthetic: roots that are not a string
    var badRoots = [undefined, null, 5, true, {}, [], ["/p"]]
    for (var j = 0; j < badRoots.length; j++) {
      var p = Runs.withProject(run, badRoots[j], "P").project
      compare(p.root, "", "root " + j)
      compare(p.name, "P", "name with root " + j)
    }

    // synthetic: a prototype-less run and an empty run
    var bare = Object.create(null)
    bare.id = "b1"
    var fromBare = Runs.withProject(bare, "/p/x", null)
    compare(fromBare.id, "b1", "prototype-less id")
    compare(fromBare.project.root, "/p/x", "prototype-less root")
    compare(fromBare.project.name, "x", "prototype-less name")
    verify(Object.getPrototypeOf(fromBare) === Object.prototype, "the copy has Object.prototype")
    var fromEmpty = Runs.withProject({}, "/p/y", "Y")
    compare(Object.keys(fromEmpty).join(","), "project", "an empty run gains only project")
    compare(fromEmpty.project.root, "/p/y", "empty run root")
    compare(fromEmpty.project.name, "Y", "empty run name")

    // synthetic: whatever project the run held is replaced
    var olds = [null, "x", 5, [], { id: 1, repo_dir: "/old" }, { root: "/old", name: "Old", extra: 1 }]
    for (var k = 0; k < olds.length; k++) {
      var g = Runs.withProject({ id: "g", project: olds[k] }, "/new", null).project
      compare(Object.keys(g).sort().join(","), "name,root", "old project " + k + " keys")
      compare(g.root, "/new", "old project " + k + " root")
      compare(g.name, "new", "old project " + k + " name")
    }
    var missing = Runs.withProject({ id: "m" }, "/new", "New")
    compare(missing.project.root, "/new", "no project before")

    // synthetic: own __proto__ keys, which no capture contains
    var poisoned = JSON.parse('{"id": "p1", "__proto__": {"polluted": true}, "tree": {"__proto__": {"x": 1}, "stories": []}}')
    verify(hasOwn(poisoned, "__proto__"), "the input carries an own __proto__ key")
    var clean = Runs.withProject(poisoned, "/p", "P")
    compare(hasOwn(clean, "__proto__"), false, "top-level __proto__ dropped")
    compare(hasOwn(clean.tree, "__proto__"), false, "nested __proto__ dropped")
    verify(Object.getPrototypeOf(clean) === Object.prototype, "top-level prototype")
    verify(Object.getPrototypeOf(clean.tree) === Object.prototype, "nested prototype")
    compare(clean.polluted, undefined, "nothing read through __proto__")
    compare(clean.tree.x, undefined, "nothing read through a nested __proto__")
    compare(clean.id, "p1", "other keys kept")
    compare(clean.tree.stories.length, 0, "nested keys kept")
  }

  function test_filter_by_project() {
    var runs = fixtureRuns()
    var a = Runs.withProject(runs[0], "/p/one", "One")
    var b = Runs.withProject(runs[1], "/p/two", "Two")
    var c = Runs.withProject(runs[2], "/p/one", "One")
    var d = Runs.withProject(runs[3], "/p/one/", null)
    var list = [a, b, c, d]
    var before = JSON.stringify(list)
    var out = Runs.filterByProject(list, "/p/one")
    verify(out !== list, "a new array")
    compare(out.length, 3, "three runs of /p/one")
    verify(out[0] === a, "same object, input order")
    verify(out[1] === c, "same object, input order")
    verify(out[2] === d, "same object, input order")
    var two = Runs.filterByProject(list, "/p/two")
    compare(two.length, 1, "one run of /p/two")
    verify(two[0] === b, "same object")
    compare(Runs.filterByProject(list, "/p/three").length, 0, "no run of /p/three")
    compare(list.length, 4, "input length unchanged")
    verify(list[0] === a && list[1] === b && list[2] === c && list[3] === d, "input order unchanged")
    compare(JSON.stringify(list), before, "input entries unchanged")
  }

  function test_filter_by_project_no_root_keeps_all() {
    var runs = fixtureRuns()
    // synthetic: entries that are not runs, and a run with no project
    var list = [runs[0], null, "x", Runs.withProject(runs[1], "/p/one", "One"), { id: "bare" }, 5, runs[2]]
    var roots = [["null", null], ["undefined", undefined], ["empty", ""]]
    for (var i = 0; i < roots.length; i++) {
      var out = Runs.filterByProject(list, roots[i][1])
      verify(out !== list, roots[i][0] + ": a new array")
      compare(out.length, list.length, roots[i][0] + ": every entry")
      for (var j = 0; j < list.length; j++) verify(out[j] === list[j], roots[i][0] + ": entry " + j)
    }
    var omitted = Runs.filterByProject(list)
    compare(omitted.length, list.length, "root omitted")
    verify(omitted !== list, "root omitted: a new array")
    var empty = []
    var fromEmpty = Runs.filterByProject(empty, null)
    compare(fromEmpty.length, 0, "an empty list")
    verify(fromEmpty !== empty, "an empty list: a new array")
  }

  function test_filter_by_project_trailing_slash() {
    var runs = fixtureRuns()
    var one = Runs.withProject(runs[0], "/p/one", "One")
    // synthetic: a project root set by hand with its trailing slash
    var slashed = Runs.normalizeRun(amRun("status-done.json"))
    slashed.project = { root: "/p/one/", name: "One" }
    var list = [one, slashed]
    var roots = ["/p/one", "/p/one/", "/p/one//"]
    for (var i = 0; i < roots.length; i++) {
      var out = Runs.filterByProject(list, roots[i])
      compare(out.length, 2, roots[i])
      verify(out[0] === one, roots[i] + ": first")
      verify(out[1] === slashed, roots[i] + ": second")
    }
    compare(Runs.filterByProject(list, "/P/one").length, 0, "case-sensitive")
    compare(Runs.filterByProject(list, "/p/on").length, 0, "no prefix match")
    compare(Runs.filterByProject(list, "/p").length, 0, "no parent match")
    compare(Runs.filterByProject(list, "/p/one/sub").length, 0, "no child match")
    compare(Runs.filterByProject(list, " /p/one").length, 0, "no trimming")
    compare(Runs.filterByProject(list, "/p/./one").length, 0, "no path resolution")

    // the filesystem root is a project of its own, not a match-all
    var top = Runs.withProject(runs[1], "/", null)
    // synthetic: a project root of only slashes, set by hand
    var topSlashed = { id: "t", project: { root: "//", name: "/" } }
    var rooted = Runs.filterByProject([one, top, topSlashed], "/")
    compare(rooted.length, 2, "root /")
    verify(rooted[0] === top, "root /: first")
    verify(rooted[1] === topSlashed, "root /: second")
    var doubled = Runs.filterByProject([one, top], "//")
    compare(doubled.length, 1, "root //")
    verify(doubled[0] === top, "root //: the / project")
  }

  function test_filter_by_project_without_project() {
    var root = "/home/user/Code/omarchy-project-manager"
    var runs = fixtureRuns()
    compare(runs[1].project.repo_dir, root, "the normalizeRun project names the root as repo_dir")
    var kept = Runs.withProject(runs[0], root, null)
    // synthetic: projects without a string root, and entries that are not runs
    var list = [runs[1], { id: "n", project: null }, { id: "m" }, { id: "s", project: "x" },
                { id: "num", project: { root: 5 } }, { id: "arr", project: [root] },
                { id: "rd", project: { repo_dir: root } }, null, "x", 5, kept, [kept]]
    var out = Runs.filterByProject(list, root)
    compare(out.length, 1, "only the projected run")
    verify(out[0] === kept, "same object")
  }

  function test_filter_by_project_garbage() {
    var run = Runs.withProject(Runs.normalizeRun(amRun("status-done.json")), "/p/one", "One")
    // synthetic: runs that are not an array
    var badRuns = [undefined, null, "x", 5, true, {}, { length: 1, 0: run }]
    for (var i = 0; i < badRuns.length; i++) {
      var withRoot = Runs.filterByProject(badRuns[i], "/p/one")
      compare(Array.isArray(withRoot), true, "runs " + i + " with a root")
      compare(withRoot.length, 0, "runs " + i + " with a root")
      var noRoot = Runs.filterByProject(badRuns[i], null)
      compare(Array.isArray(noRoot), true, "runs " + i + " without a root")
      compare(noRoot.length, 0, "runs " + i + " without a root")
    }
    // synthetic: roots that are neither a string nor null/undefined
    var list = [run]
    var badRoots = [5, 0, true, false, NaN, {}, [], ["/p/one"], { root: "/p/one" }]
    for (var j = 0; j < badRoots.length; j++) {
      var out = Runs.filterByProject(list, badRoots[j])
      compare(Array.isArray(out), true, "root " + j)
      compare(out.length, 0, "root " + j)
    }
    compare(list.length, 1, "input unchanged")
    verify(list[0] === run, "input entry unchanged")
  }

  function test_attention_across_projects() {
    var runs = fixtureRuns()
    var running = Runs.withProject(runs[0], "/p/a", "A")
    var escalated = Runs.withProject(runs[2], "/p/a", "A")
    var done = Runs.withProject(runs[1], "/p/b", "B")
    var dead = Runs.withProject(runs[0], "/p/b", "B")
    // synthetic: the started capture's lease marked dead
    dead.lease.live = false
    compare(Runs.runState(running), "running", "the started capture is running")
    compare(Runs.runState(dead), "dead", "its dead copy")
    var list = [running, escalated, done, dead]
    var out = Runs.attention(list)
    compare(out.length, 2, "one run of each project")
    verify(out[0] === escalated, "same object, input order")
    verify(out[1] === dead, "same object, input order")
    compare(list.length, 4, "input not modified")

    var onlyB = Runs.attention(Runs.filterByProject(list, "/p/b"))
    compare(onlyB.length, 1, "attention of one project")
    verify(onlyB[0] === dead, "the dead run of /p/b")
  }

  // ---- S6 1.2: grouping -------------------------------------------------------------------

  // The `project.root` of every group, comma-joined.
  function groupRoots(groups) {
    var roots = []
    for (var i = 0; i < groups.length; i++) roots.push(groups[i].project.root)
    return roots.join(",")
  }

  function test_group_by_project_order_by_rank() {
    var runs = fixtureRuns()
    compare(Runs.runState(runs[0]), "running", "fixture 0 is running")
    compare(Runs.runState(runs[1]), "done", "fixture 1 is done")
    compare(Runs.runState(runs[2]), "escalated", "fixture 2 is escalated")
    compare(Runs.runState(runs[3]), "done", "fixture 3 is done")
    var c1 = Runs.withProject(runs[1], "/p/c", "C")
    var b1 = Runs.withProject(runs[0], "/p/b", "B")
    var a1 = Runs.withProject(runs[3], "/p/a", "A")
    var z1 = Runs.withProject(runs[2], "/p/z", "Z")
    var b2 = Runs.withProject(runs[1], "/p/b", "B")
    var groups = Runs.groupByProject([c1, b1, a1, z1, b2])
    compare(groups.length, 4, "one group per project, none empty")
    compare(groupRoots(groups), "/p/z,/p/b,/p/a,/p/c", "attention, then live, then by name")

    // synthetic: the started capture's lease marked dead
    var dead = Runs.withProject(runs[0], "/p/y", "Y")
    dead.lease.live = false
    compare(Runs.runState(dead), "dead", "the dead copy")
    compare(groupRoots(Runs.groupByProject([b1, dead, a1])), "/p/y,/p/b,/p/a", "a dead run ranks as attention")

    var mixedLive = Runs.withProject(runs[0], "/p/x", "X")
    var mixedEscalated = Runs.withProject(runs[2], "/p/x", "X")
    compare(groupRoots(Runs.groupByProject([b1, mixedLive, a1, mixedEscalated])), "/p/x,/p/b,/p/a",
            "attention and live together rank as attention")
  }

  function test_group_by_project_name_ties() {
    var runs = fixtureRuns()
    var beta = Runs.withProject(runs[1], "/r/2", "beta")
    var upperAlpha = Runs.withProject(runs[3], "/r/3", "Alpha")
    var alpha = Runs.withProject(runs[1], "/r/1", "alpha")
    var groups = Runs.groupByProject([beta, upperAlpha, alpha])
    compare(groupRoots(groups), "/r/1,/r/3,/r/2", "case-blind name, then root")
    compare(groups[0].project.name, "alpha", "first name")
    compare(groups[1].project.name, "Alpha", "second name")
    compare(groups[2].project.name, "beta", "third name")

    // synthetic: a name set by hand to "" sorts before the named groups of its rank
    var blank = Runs.withProject(runs[3], "/r/9", "x")
    blank.project.name = ""
    compare(groupRoots(Runs.groupByProject([beta, alpha, blank])), "/r/9,/r/1,/r/2", "an empty name first")

    // synthetic: non-ASCII names order by code unit after toLowerCase, whatever the input order
    var accented = Runs.withProject(runs[1], "/u/1", "\u00c9clair")
    var zeta = Runs.withProject(runs[1], "/u/2", "zeta")
    var plain = Runs.withProject(runs[1], "/u/3", "eclair")
    compare(groupRoots(Runs.groupByProject([accented, zeta, plain])), "/u/3,/u/2,/u/1", "code-unit order")
    compare(groupRoots(Runs.groupByProject([plain, zeta, accented])), "/u/3,/u/2,/u/1", "same order reversed")
  }

  function test_group_by_project_counts() {
    var runs = fixtureRuns()
    var running = Runs.withProject(runs[0], "/p/m", "M")
    // synthetic: the started capture's lease marked dead
    var dead = Runs.withProject(runs[0], "/p/m", "M")
    dead.lease.live = false
    // synthetic: a done capture marked stopped (parked) and cancelled
    var parked = Runs.withProject(runs[1], "/p/m", "M")
    parked.status = "stopped"
    var cancelled = Runs.withProject(runs[1], "/p/m", "M")
    cancelled.status = "cancelled"
    var escalated = Runs.withProject(runs[2], "/p/m", "M")
    var done = Runs.withProject(runs[3], "/p/m", "M")
    var otherDone = Runs.withProject(runs[1], "/p/n", "N")
    var otherIntegrate = Runs.withProject(runs[3], "/p/n", "N")
    // synthetic: a run whose status am never writes
    var unknown = { id: "u", status: "weird", project: { root: "/p/n", name: "N" } }
    compare(Runs.runState(unknown), "unknown", "the unknown run")

    var groups = Runs.groupByProject([running, dead, otherDone, parked, escalated, unknown, done, cancelled, otherIntegrate])
    compare(groupRoots(groups), "/p/m,/p/n", "two groups")
    var m = groups[0]
    compare(Object.keys(m.counts).sort().join(","), "attention,live,parked", "count keys")
    compare(m.counts.live, 1, "one running")
    compare(m.counts.parked, 1, "one parked")
    compare(m.counts.attention, 2, "dead and escalated")
    compare(m.counts.attention, Runs.attention(m.runs).length, "attention counts what Runs.attention returns")
    compare(m.runs.length, 6, "every run of /p/m")
    var n = groups[1]
    compare(n.runs.length, 3, "every run of /p/n")
    compare(n.counts.live, 0, "no live run")
    compare(n.counts.parked, 0, "no parked run")
    compare(n.counts.attention, 0, "no attention run")
  }

  function test_group_by_project_shape() {
    var runs = fixtureRuns()
    var first = Runs.withProject(runs[1], "/p/s", "First")
    var live = Runs.withProject(runs[0], "/p/t", "T")
    var second = Runs.withProject(runs[3], "/p/s/", "Second")
    var list = [first, live, second]
    var groups = Runs.groupByProject(list)
    compare(groupRoots(groups), "/p/t,/p/s", "the live group first")
    var s = groups[1]
    compare(Object.keys(s).sort().join(","), "counts,project,runs", "group keys")
    compare(Object.keys(s.project).sort().join(","), "name,root", "project keys")
    compare(s.project.root, "/p/s", "root")
    compare(s.project.name, "First", "the name of the first run")
    compare(s.runs.length, 2, "both runs of /p/s")
    verify(s.runs[0] === first, "same object, input order")
    verify(s.runs[1] === second, "same object, input order")
    verify(s.runs !== list, "a new runs array")
    verify(s.project !== first.project, "a new project object")

    var again = Runs.groupByProject(list)
    verify(again !== groups, "a new array per call")
    verify(again[1] !== s, "a new group per call")
    verify(again[1].project !== s.project, "a new project per call")
    verify(again[1].counts !== s.counts, "new counts per call")
    verify(again[1].runs !== s.runs, "new runs per call")

    // synthetic: the first run of a root names it with a non-string name
    var unnamed = { id: "q1", status: "done", project: { root: "/p/q", name: 5 } }
    var named = { id: "q2", status: "done", project: { root: "/p/q", name: "Q" } }
    var q = Runs.groupByProject([unnamed, named])
    compare(q.length, 1, "one group")
    compare(q[0].project.name, "", "a non-string first name is empty")
  }

  function test_group_by_project_trailing_slash() {
    var runs = fixtureRuns()
    var plain = Runs.withProject(runs[1], "/p/one", "One")
    // synthetic: a project root set by hand with its trailing slash
    var slashed = Runs.normalizeRun(amRun("status-done.json"))
    slashed.project = { root: "/p/one/", name: "One" }
    var upper = Runs.withProject(runs[3], "/P/one", "One")
    var groups = Runs.groupByProject([slashed, plain, upper])
    compare(groupRoots(groups), "/P/one,/p/one", "two groups, case-sensitive, ordered by root")
    compare(groups[1].runs.length, 2, "trailing slash shares the group")
    verify(groups[1].runs[0] === slashed, "same object, input order")
    verify(groups[1].runs[1] === plain, "same object, input order")

    // the filesystem root is a project of its own, not the no-project group
    var top = Runs.withProject(runs[1], "/", null)
    var rooted = Runs.groupByProject([top, { id: "loose", status: "done" }])
    compare(rooted.length, 2, "/ and the no-project group")
    compare(rooted[0].project.root, "/", "/ is a project group")
    compare(rooted[0].project.name, "/", "named /")
    compare(rooted[1].project.root, "", "the no-project group last")

    // synthetic: a root of only slashes set by hand shares the / group
    var slashes = { id: "s", status: "done", project: { root: "///", name: "S" } }
    var tops = Runs.groupByProject([top, slashes])
    compare(tops.length, 1, "one / group")
    compare(tops[0].project.root, "/", "root /")
    compare(tops[0].runs.length, 2, "both runs")
  }

  function test_group_by_project_empty() {
    var run = Runs.withProject(Runs.normalizeRun(amRun("status-done.json")), "/p/one", "One")
    var empty = []
    // synthetic: runs that are not an array
    var bad = [empty, undefined, null, "x", 5, {}, { length: 1, 0: run }]
    for (var i = 0; i < bad.length; i++) {
      var out = Runs.groupByProject(bad[i])
      compare(Array.isArray(out), true, "runs " + i)
      compare(out.length, 0, "runs " + i)
    }
    verify(Runs.groupByProject(empty) !== empty, "a new array for []")
    verify(Runs.groupByProject(null) !== Runs.groupByProject(null), "a new array per call")
    // synthetic: entries that are not plain objects
    compare(Runs.groupByProject([null, undefined, "x", 5, true, []]).length, 0, "non-object entries dropped")
  }

  function test_group_by_project_without_project() {
    var runs = fixtureRuns()
    var plain = runs[1]
    var escalated = runs[2]
    compare(Object.keys(plain.project).sort().join(","), "id,repo_dir", "normalizeRun gives no root")
    // synthetic: projects without a string root, and a prototype-less entry
    var nullProject = { id: "n", status: "done", project: null }
    var noProject = { id: "m", status: "done" }
    var numRoot = { id: "num", status: "done", project: { root: 5 } }
    var blankRoot = Runs.withProject(runs[3], 5, "x")
    compare(blankRoot.project.root, "", "withProject with a non-string root gives root \"\"")
    var bare = Object.create(null)
    bare.id = "b"
    var a = Runs.withProject(runs[1], "/p/a", "A")
    var b = Runs.withProject(runs[0], "/p/b", "B")
    var list = [plain, a, nullProject, noProject, escalated, numRoot, b, blankRoot, bare]
    var groups = Runs.groupByProject(list)
    compare(groupRoots(groups), "/p/b,/p/a,", "the no-project group last, even with an attention run")
    var last = groups[2]
    compare(last.project.root, "", "no-project root")
    compare(last.project.name, "", "no-project name, never the name of a run")
    compare(last.counts.attention, 1, "it holds the escalated run")
    var expected = [plain, nullProject, noProject, escalated, numRoot, blankRoot, bare]
    compare(last.runs.length, expected.length, "every run without a project")
    for (var i = 0; i < expected.length; i++) verify(last.runs[i] === expected[i], "same object, input order " + i)

    // its position in the input does not move the project groups
    var reordered = Runs.groupByProject([escalated, b, plain, a])
    compare(groupRoots(reordered), "/p/b,/p/a,", "no-project first in the input, last in the groups")
  }

  function test_group_by_project_pure() {
    var runs = fixtureRuns()
    var a = Runs.withProject(runs[0], "/p/a", "A")
    var b = Runs.withProject(runs[2], "/p/b", "B")
    var c = Runs.withProject(runs[1], "/p/a/", "A")
    var bare = Object.create(null)
    bare.id = "bare"
    // synthetic: garbage entries and garbage projects
    var list = [a, null, b, "x", 5, [], { id: "s", project: "junk" }, { id: "arr", project: [1] },
                { id: "obj", project: { root: {}, name: {} } }, bare, undefined, c]
    var entries = list.slice()
    var before = []
    for (var i = 0; i < list.length; i++) before.push(JSON.stringify(list[i]))
    var groups = Runs.groupByProject(list)
    compare(groupRoots(groups), "/p/b,/p/a,", "attention, live, no-project")
    compare(list.length, entries.length, "input length unchanged")
    for (var j = 0; j < list.length; j++) {
      verify(list[j] === entries[j], "entry " + j + " is the same object")
      compare(JSON.stringify(list[j]), before[j], "entry " + j + " unchanged")
    }
  }

  function test_display_order() {
    var runs = fixtureRuns()
    var c1 = Runs.withProject(runs[1], "/p/c", "C")
    var b1 = Runs.withProject(runs[0], "/p/b", "B")
    var a1 = Runs.withProject(runs[3], "/p/a", "A")
    var z1 = Runs.withProject(runs[2], "/p/z", "Z")
    var b2 = Runs.withProject(runs[1], "/p/b", "B")
    var loose = runs[1]
    // synthetic: entries that are not runs
    var list = [c1, b1, null, a1, loose, z1, "x", b2]
    var flat = Runs.displayOrder(Runs.groupByProject(list))
    var expected = [z1, b1, b2, a1, c1, loose]
    compare(flat.length, expected.length, "every object entry once")
    for (var i = 0; i < expected.length; i++) verify(flat[i] === expected[i], "same object, display order " + i)
  }

  function test_display_order_garbage() {
    // synthetic: groups that are not an array
    var bad = [[], undefined, null, "x", 5, {}]
    for (var i = 0; i < bad.length; i++) {
      var out = Runs.displayOrder(bad[i])
      compare(Array.isArray(out), true, "groups " + i)
      compare(out.length, 0, "groups " + i)
    }
    // synthetic: malformed groups among good ones
    var r1 = { id: "r1" }, r2 = { id: "r2" }, r3 = { id: "r3" }
    var g1 = { runs: [r1, r2] }
    var g2 = { runs: [r3, null] }
    var groups = [null, g1, 5, {}, { runs: "x" }, [r1], g2]
    var before = JSON.stringify(groups)
    var flat = Runs.displayOrder(groups)
    compare(flat.length, 4, "the runs of the two good groups")
    verify(flat[0] === r1 && flat[1] === r2 && flat[2] === r3, "same objects, in order")
    compare(flat[3], null, "elements of runs copied as they are")
    verify(flat !== g1.runs && flat !== g2.runs, "a new array")
    compare(JSON.stringify(groups), before, "groups unchanged")
    compare(g1.runs.length, 2, "first group's runs unchanged")
    var single = Runs.displayOrder([g1])
    verify(single !== g1.runs, "a new array for a single group")
    compare(single.length, 2, "its runs")
  }

  function test_run_by_id_returns_the_entry_itself() {
    var list = [{ id: "a" }, { id: "b" }, { id: "c" }]
    verify(Runs.runById(list, "b") === list[1], "the entry itself")
    compare(Runs.runById(list, "z"), null)
  }

  function test_run_by_id_skips_empty_entries() {
    var list = [null, undefined, 0, { id: "a" }]
    verify(Runs.runById(list, "a") === list[3], "found past the empty entries")
  }

  function test_run_by_id_on_a_non_list_is_null() {
    compare(Runs.runById(null, "a"), null)
    compare(Runs.runById(undefined, "a"), null)
    compare(Runs.runById({}, "a"), null)
    compare(Runs.runById({ a: { id: "a" } }, "a"), null)
    compare(Runs.runById("abc", "a"), null)
  }

  function test_run_by_id_with_a_prototype_member_name() {
    var names = ["constructor", "toString", "__proto__", "hasOwnProperty", "valueOf"]
    for (var i = 0; i < names.length; i++) {
      compare(Runs.runById([{ id: "a" }], names[i]), null, names[i] + " absent")
      var list = [{ id: "a" }, { id: names[i] }]
      verify(Runs.runById(list, names[i]) === list[1], names[i] + " present")
    }
  }

  function test_run_by_id_is_strict() {
    compare(Runs.runById([{ id: "1" }], 1), null)
  }

  function test_run_by_id_of_the_empty_id_matches_no_idless_entry() {
    compare(Runs.runById([{}, { id: "a" }, { id: null }], ""), null)
  }

  function test_run_by_id_skips_primitive_entries() {
    compare(Runs.runById(["a", 5, true], "a"), null)
    var list = ["a", 5, true, { id: "a" }]
    verify(Runs.runById(list, "a") === list[3], "the object entry")
  }

  function test_has_key_counts_own_keys_only() {
    compare(Runs.hasKey({ a: 1 }, "a"), true)
    var names = ["toString", "constructor", "hasOwnProperty", "valueOf", "__proto__"]
    for (var i = 0; i < names.length; i++) {
      compare(Runs.hasKey({}, names[i]), false, names[i] + " inherited")
      var own = JSON.parse("{\"" + names[i] + "\": 1}")
      compare(Runs.hasKey(own, names[i]), true, names[i] + " own")
    }
  }

  function test_has_key_with_a_shadowed_has_own_property() {
    var map = { hasOwnProperty: 1, a: 2 }
    compare(Runs.hasKey(map, "a"), true)
    compare(Runs.hasKey(map, "b"), false)
  }

  function test_has_key_on_nothing_is_false() {
    compare(Runs.hasKey(null, "a"), false)
    compare(Runs.hasKey(undefined, "a"), false)
  }

  function test_has_key_coerces_the_key_like_has_own_property() {
    compare(Runs.hasKey({ "1": "x" }, 1), true)
    compare(Runs.hasKey({ "1": "x" }, 2), false)
  }

  function test_copy_map_is_a_new_shallow_copy() {
    var nested = { deep: true }
    var map = { a: 1, b: "two", c: nested }
    var copy = Runs.copyMap(map)
    verify(copy !== map, "a new object")
    compare(Object.keys(copy).sort().join(","), "a,b,c")
    compare(copy.a, 1)
    compare(copy.b, "two")
    verify(copy.c === nested, "shallow: the nested object is the same reference")
    copy.a = 99
    copy.d = 4
    compare(map.a, 1, "input value unchanged")
    compare(Object.prototype.hasOwnProperty.call(map, "d"), false, "input keys unchanged")
  }

  function test_copy_map_copies_own_keys_only() {
    var map = Object.create({ inherited: 1 })
    map.a = 2
    var copy = Runs.copyMap(map)
    compare(Object.prototype.hasOwnProperty.call(copy, "a"), true)
    compare(copy.a, 2)
    compare(Object.prototype.hasOwnProperty.call(copy, "inherited"), false)
    compare(copy.inherited, undefined)
    var named = Runs.copyMap({ constructor: 1, toString: 2 })
    compare(Object.prototype.hasOwnProperty.call(named, "constructor"), true)
    compare(Object.prototype.hasOwnProperty.call(named, "toString"), true)
    compare(named.constructor, 1)
    compare(named.toString, 2)
  }

  function test_copy_map_of_nothing_is_empty() {
    var a = Runs.copyMap(null)
    var b = Runs.copyMap(undefined)
    compare(typeof a, "object")
    verify(a !== null, "an object, not null")
    compare(Object.keys(a).length, 0)
    compare(Object.keys(b).length, 0)
    verify(a !== b, "a new object on each call")
  }

  // D1
  function test_run_root_is_the_projects_root_string() {
    compare(Runs.runRoot({ project: { root: "/a" } }), "/a")
    compare(Runs.runRoot({ project: { root: "" } }), "", "an empty root stays empty")
  }

  // D2
  function test_run_root_of_anything_else_is_empty() {
    var others = [null, undefined, 5, "x", {}, { project: null }, { project: "x" }, { project: {} }, { project: { root: 7 } }]
    for (var i = 0; i < others.length; i++) compare(Runs.runRoot(others[i]), "", JSON.stringify(others[i]))
  }

  function dispatchRoots(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) out.push(rows[i].root)
    return out.join(",")
  }

  function test_dispatch_projects_order() {
    // synthetic: three registered projects, no open project, an empty probe
    var roots = [{ root: "/p/b", name: "b" }, { root: "/p/a", name: "A" }, { root: "/p/c", name: "c" }]
    var rows = Runs.dispatchProjects(roots, { ok: true, projects: [] }, "")
    compare(dispatchRoots(rows), "/p/a,/p/b,/p/c", "by name, case-blind")
    compare(rows[0].name, "A", "name as given")
    for (var i = 0; i < rows.length; i++) {
      compare(Object.keys(rows[i]).sort().join(","), "enabled,name,open,reason,root", "row " + i + " keys")
      compare(rows[i].open, false, "row " + i + " not open")
      compare(rows[i].enabled, true, "row " + i + " enabled")
      compare(rows[i].reason, "", "row " + i + " no reason")
    }
    verify(rows[0] !== roots[1], "a new row object")
    verify(rows !== roots, "a new array")
  }

  function test_dispatch_projects_open_first() {
    // synthetic: the open project's name sorts last
    var roots = [{ root: "/p/a", name: "alpha" }, { root: "/p/z", name: "zulu" }, { root: "/p/m", name: "mike" }]
    var rows = Runs.dispatchProjects(roots, [], "/p/z")
    compare(dispatchRoots(rows), "/p/z,/p/a,/p/m", "open first, then by name")
    compare(rows[0].open, true, "the open row")
    compare(rows[1].open, false, "alpha not open")
    compare(rows[2].open, false, "mike not open")
    var slashed = Runs.dispatchProjects(roots, [], "/p/z/")
    compare(dispatchRoots(slashed), "/p/z,/p/a,/p/m", "openRoot with a trailing /")
    compare(slashed[0].open, true, "openRoot with a trailing / is open")
    compare(Runs.dispatchProjects(roots, [], "/p/z//")[0].open, true, "openRoot with trailing slashes")
    var none = Runs.dispatchProjects(roots, [], "/p/q")
    compare(dispatchRoots(none), "/p/a,/p/m,/p/z", "an unregistered openRoot")
    for (var i = 0; i < none.length; i++) compare(none[i].open, false, "nothing open " + i)
  }

  function test_dispatch_projects_ties() {
    // synthetic: names that differ only by case
    var roots = [{ root: "/p/y", name: "foo" }, { root: "/p/x", name: "Foo" }, { root: "/p/a", name: "zed" }]
    var rows = Runs.dispatchProjects(roots, [], null)
    compare(dispatchRoots(rows), "/p/x,/p/y,/p/a", "a case-only name tie by root")
    compare(rows[0].name, "Foo", "case kept")
    compare(rows[1].name, "foo", "case kept")
    // synthetic: the upper-case name on the later root
    var flipped = Runs.dispatchProjects([{ root: "/p/y", name: "Foo" }, { root: "/p/x", name: "foo" }], [], null)
    compare(dispatchRoots(flipped), "/p/x,/p/y", "root decides, not case or input order")
    compare(flipped[1].name, "Foo", "case kept on the later row")
  }

  function test_dispatch_projects_unreachable() {
    // synthetic: board-tree.py --probe output for three of four registered roots
    var roots = [{ root: "/p/a", name: "a" }, { root: "/p/b", name: "b" }, { root: "/p/c", name: "c" },
                 { root: "/p/d", name: "d" }]
    var probe = { ok: true, projects: [{ root: "/p/a", ok: false, reason: "no .brd marker" },
                                       { root: "/p/b", ok: false },
                                       { root: "/p/c", ok: true }] }
    var shapes = [["payload", probe], ["projects array", probe.projects]]
    for (var s = 0; s < shapes.length; s++) {
      var label = shapes[s][0]
      var rows = Runs.dispatchProjects(roots, shapes[s][1], "")
      compare(dispatchRoots(rows), "/p/a,/p/b,/p/c,/p/d", label + ": order unchanged by reachability")
      compare(rows[0].enabled, false, label + ": no marker disabled")
      compare(rows[0].reason, "no .brd marker", label + ": the probe's reason")
      compare(rows[1].enabled, false, label + ": ok false disabled")
      compare(rows[1].reason, "unreachable", label + ": no reason given")
      compare(rows[2].enabled, true, label + ": ok true enabled")
      compare(rows[2].reason, "", label + ": ok true no reason")
      compare(rows[3].enabled, true, label + ": absent from the probe enabled")
      compare(rows[3].reason, "", label + ": absent no reason")
    }
    var openDisabled = Runs.dispatchProjects(roots, probe, "/p/b")
    compare(dispatchRoots(openDisabled), "/p/b,/p/a,/p/c,/p/d", "a disabled open project still first")
    compare(openDisabled[0].open, true, "open")
    compare(openDisabled[0].enabled, false, "and disabled")
    compare(openDisabled[0].reason, "unreachable", "with its reason")
    // synthetic: a probe root with a trailing /, padded, blank and numeric reasons, two entries for one root
    var odd = [{ root: "/p/a/", ok: false, reason: "not a directory" },
               { root: "/p/b", ok: false, reason: "  no .brd marker  " },
               { root: "/p/c", ok: false, reason: "   " },
               { root: "/p/d", ok: true }, { root: "/p/d", ok: false, reason: "late" },
               { root: "/p/a", ok: true }]
    var r = Runs.dispatchProjects(roots, odd, "")
    compare(r[0].enabled, false, "a probe root with a trailing / matches")
    compare(r[0].reason, "not a directory", "its reason")
    compare(r[1].reason, "no .brd marker", "the reason trimmed")
    compare(r[2].enabled, false, "a blank reason is still disabled")
    compare(r[2].reason, "unreachable", "a blank reason")
    compare(r[3].enabled, true, "the first entry for a root wins over a later ok false")
    compare(r[3].reason, "", "the later reason is not used")
    var numeric = Runs.dispatchProjects([{ root: "/p/a" }], [{ root: "/p/a", ok: false, reason: 5 }], "")
    compare(numeric[0].reason, "unreachable", "a non-string reason")
  }

  function test_dispatch_projects_names() {
    // synthetic: names that are missing, blank, padded or not a string, and roots with trailing slashes
    var roots = [{ root: "/p/one/", name: "" }, { root: "/p/two", name: "   " }, { root: "/p/three" },
                 { root: "/p/four", name: 4 }, { root: "/p/five", name: null }, { root: "/", name: "" },
                 { root: "/p/six", name: "  Six  " }, { root: "/p/seven", name: "team/app" }]
    var rows = Runs.dispatchProjects(roots, [], "")
    var pairs = []
    for (var i = 0; i < rows.length; i++) pairs.push(rows[i].root + "=" + rows[i].name)
    compare(pairs.join(","),
            "/=/,/p/five=five,/p/four=four,/p/one=one,/p/six=Six,/p/seven=team/app,/p/three=three,/p/two=two",
            "names fall back to the root's last segment, trimmed otherwise")
    var slashes = Runs.dispatchProjects([{ root: "//", name: "" }], [], "")
    compare(slashes[0].root, "/", "a root of only slashes is /")
    compare(slashes[0].name, "/", "and is named /")
    compare(Runs.dispatchProjects([{ root: "/p/one///", name: "One" }], [], "")[0].root, "/p/one",
            "every trailing / removed")
  }

  function test_dispatch_projects_empty() {
    // synthetic: an empty registry with every probe shape and openRoot
    var probes = [undefined, null, [], { ok: true, projects: [] },
                  { ok: true, projects: [{ root: "/p/a", ok: false, reason: "no .brd marker" }] }]
    var opens = [undefined, null, "", "/p/a"]
    for (var p = 0; p < probes.length; p++) {
      for (var o = 0; o < opens.length; o++) {
        var out = Runs.dispatchProjects([], probes[p], opens[o])
        verify(Array.isArray(out), "probe " + p + " open " + o + " is an array")
        compare(out.length, 0, "probe " + p + " open " + o + " is empty")
      }
    }
    var empty = []
    verify(Runs.dispatchProjects(empty, [], "") !== empty, "a new array for []")
  }

  function test_dispatch_projects_garbage() {
    // synthetic: a registry that is not an array
    var notLists = [undefined, null, "x", 5, {}]
    for (var i = 0; i < notLists.length; i++) {
      var out = Runs.dispatchProjects(notLists[i], [], "/p/a")
      verify(Array.isArray(out), "registry " + i + " is an array")
      compare(out.length, 0, "registry " + i + " is empty")
    }
    // synthetic: junk entries among good ones, and a duplicate root
    var roots = [null, { root: "/p/b", name: "b" }, "x", [], {}, { root: 5, name: "five" },
                 { root: "", name: "blank" }, { root: "/p/a", name: "a" }, { root: "/p/b/", name: "dup" },
                 undefined, ["/p/c"]]
    var rows = Runs.dispatchProjects(roots, [], "")
    compare(dispatchRoots(rows), "/p/a,/p/b", "only valid, first-seen rows")
    compare(rows[1].name, "b", "the first entry for a root wins")
    // synthetic: probes that are not the helper's output, and junk probe entries
    var probes = [undefined, null, "x", 5, {}, { projects: "x" },
                  { ok: false, error: { type: "BrdMissing", message: "brd not found" } },
                  [null, { root: 5, ok: false }, { root: "/p/a", ok: "no" }, "x", 5, []]]
    for (var p = 0; p < probes.length; p++) {
      var probed = Runs.dispatchProjects(roots, probes[p], "")
      compare(dispatchRoots(probed), "/p/a,/p/b", "probe " + p + " rows")
      for (var j = 0; j < probed.length; j++) {
        compare(probed[j].enabled, true, "probe " + p + " row " + j + " enabled")
        compare(probed[j].reason, "", "probe " + p + " row " + j + " no reason")
      }
    }
    // synthetic: openRoots that are not a registered root string
    var opens = [5, {}, null, "", undefined, ["/p/a"]]
    for (var o = 0; o < opens.length; o++) {
      var opened = Runs.dispatchProjects(roots, [], opens[o])
      compare(dispatchRoots(opened), "/p/a,/p/b", "openRoot " + o + " rows")
      for (var k = 0; k < opened.length; k++) compare(opened[k].open, false, "openRoot " + o + " row " + k)
    }
    // the inputs are left as they were
    var probe = { ok: true, projects: [{ root: "/p/a/", ok: false, reason: " x " }] }
    var beforeRoots = JSON.stringify(roots), beforeProbe = JSON.stringify(probe)
    var result = Runs.dispatchProjects(roots, probe, "/p/b/")
    compare(dispatchRoots(result), "/p/b,/p/a", "open first")
    compare(result[1].reason, "x", "the reason trimmed in the row")
    compare(JSON.stringify(roots), beforeRoots, "projectRoots unchanged")
    compare(JSON.stringify(probe), beforeProbe, "probe unchanged")
    compare(roots[8].root, "/p/b/", "an entry's root not trimmed in place")
    compare(probe.projects[0].reason, " x ", "a probe reason not trimmed in place")
  }

  function test_dispatch_projects_edges() {
    // synthetic: a padded root, roots spelled like Object.prototype keys, a non-ASCII name,
    // a duplicate whose first entry has no name, and a prototype-less entry
    var bare = Object.create(null)
    bare.root = "/p/bare"
    bare.name = "bare"
    var roots = [{ root: " /p/pad", name: "pad" }, { root: "__proto__", name: "proto" },
                 { root: "constructor", name: "ctor" }, { root: "/p/e", name: "éclair" },
                 { root: "/p/z", name: "zed" }, { root: "/p/dup" }, { root: "/p/dup", name: "Named" }, bare]
    var probe = [{ root: " /p/pad", ok: false, reason: "not a directory" }, { root: "/p/pad", ok: true },
                 { root: "__proto__", ok: false, reason: "no .brd marker" }]
    var rows = Runs.dispatchProjects(roots, probe, " /p/pad")
    compare(dispatchRoots(rows), " /p/pad,/p/bare,constructor,/p/dup,__proto__,/p/z,/p/e",
            "padded open root first, then plain comparison of lower-cased names")
    compare(rows[0].open, true, "a padded openRoot matches the padded root exactly")
    compare(rows[0].enabled, false, "the padded root's own probe entry")
    compare(rows[0].reason, "not a directory", "not the unpadded entry")
    var unpadded = Runs.dispatchProjects(roots, probe, "/p/pad")
    compare(dispatchRoots(unpadded), "/p/bare,constructor,/p/dup, /p/pad,__proto__,/p/z,/p/e",
            "an unpadded openRoot puts nothing first")
    for (var i = 0; i < unpadded.length; i++) compare(unpadded[i].open, false, "nothing open " + i)
    compare(rows[1].name, "bare", "a prototype-less entry gives a row")
    compare(rows[2].name, "ctor", "a constructor root keeps its row")
    compare(rows[2].enabled, true, "and is enabled")
    compare(rows[3].name, "dup", "the first duplicate wins, its name from the root")
    compare(rows[4].name, "proto", "a __proto__ root keeps its row")
    compare(rows[4].enabled, false, "and its probe entry")
    compare(rows[4].reason, "no .brd marker", "with its reason")
    compare(rows[6].name, "éclair", "a non-ASCII name sorts after z")
  }

  // ---- dfr 1.3: dispatch targets ----------------------------------------------------------

  // A card as brd tree returns it, before Board.indexTree.
  function tnode(id, status, children) {
    return { id: id, title: "T " + id, status: status, children: children }
  }

  function targetKeys(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) out.push(rows[i].key)
    return out.join(",")
  }

  function checkWholeBoard(row, label) {
    compare(Object.keys(row).sort().join(","), "card,depth,key,label,level", label + " keys")
    compare(row.key, "board", label + " key")
    compare(row.level, "board", label + " level")
    compare(row.card, "board", label + " card")
    compare(row.label, "Whole board", label + " label")
    compare(row.depth, 0, label + " depth")
  }

  function test_dispatch_targets_board_first() {
    // synthetic: one milestone with one story holding one todo subtask
    var roots = [tnode("m1", "todo", [tnode("s1", "todo", [tnode("t1", "todo")])])]
    var cardMap = Board.indexTree(roots).cardMap
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(rows.length, 4, "the Whole board and three cards")
    checkWholeBoard(rows[0], "row 0")
    for (var i = 1; i < rows.length; i++)
      compare(Object.keys(rows[i]).sort().join(","), "card,depth,key,label,level", "row " + i + " keys")
  }

  function test_dispatch_targets_tree_order_and_depth() {
    // synthetic: two milestones, each with two stories, each story with two todo subtasks;
    // t1 holds one todo card at depth 3
    var roots = [tnode("m1", "todo", [tnode("s1", "todo", [tnode("t1", "todo", [tnode("u1", "todo")]), tnode("t2", "todo")]),
                                      tnode("s2", "todo", [tnode("t3", "todo"), tnode("t4", "todo")])]),
                 tnode("m2", "todo", [tnode("s3", "todo", [tnode("t5", "todo"), tnode("t6", "todo")]),
                                      tnode("s4", "todo", [tnode("t7", "todo"), tnode("t8", "todo")])])]
    var cardMap = Board.indexTree(roots).cardMap
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(targetKeys(rows), "board,card:m1,card:s1,card:t1,card:u1,card:t2,card:s2,card:t3,card:t4,"
            + "card:m2,card:s3,card:t5,card:t6,card:s4,card:t7,card:t8", "pre-order")
    var levels = ["milestone", "story", "subtask", "subtask"]
    for (var i = 1; i < rows.length; i++) {
      var card = cardMap[rows[i].key.substring("card:".length)]
      verify(rows[i].card === card, rows[i].key + " carries the node itself")
      compare(rows[i].depth, card.depth, rows[i].key + " depth")
      compare(rows[i].level, levels[card.depth], rows[i].key + " level")
    }
    compare(rows[4].level, "subtask", "a depth-3 card is a subtask")
    compare(rows[4].depth, 3, "at depth 3")
  }

  function test_dispatch_targets_finished_omitted() {
    var finished = ["done", "merged", "canceled", "archived"]
    for (var f = 0; f < finished.length; f++) {
      var st = finished[f]
      // synthetic: a finished milestone over a todo story and subtask; a todo milestone over a
      // finished story with a todo subtask, and over a todo story whose only subtask is finished
      var roots = [tnode("m1", st, [tnode("s1", "todo", [tnode("t1", "todo")])]),
                   tnode("m2", "todo", [tnode("s2", st, [tnode("t2", "todo")]),
                                        tnode("s3", "todo", [tnode("t3", st)])])]
      var cardMap = Board.indexTree(roots).cardMap
      compare(targetKeys(Runs.dispatchTargets(roots, cardMap)), "board,card:s1,card:t1,card:m2,card:t2,card:s3", st)
    }
  }

  function test_dispatch_targets_only_todo_subtasks() {
    // synthetic: an in_progress milestone over a blocked story holding one subtask per status,
    // and an in_progress story; a blocked milestone
    var subtasks = [tnode("a", "in_progress"), tnode("b", "review"), tnode("c", "blocked"), tnode("d", ""),
                    { id: "e", title: "T e" }, tnode("f", "TODO"), tnode("g", "todo")]
    var roots = [tnode("m1", "in_progress", [tnode("s1", "blocked", subtasks), tnode("s2", "in_progress")]),
                 tnode("m2", "blocked")]
    var cardMap = Board.indexTree(roots).cardMap
    compare(targetKeys(Runs.dispatchTargets(roots, cardMap)), "board,card:m1,card:s1,card:g,card:s2,card:m2",
            "only the todo subtask; milestones and stories of any unfinished status")
  }

  function test_dispatch_targets_stories_included() {
    // synthetic: one milestone with one in_progress story
    var roots = [tnode("m1", "todo", [tnode("s1", "in_progress")])]
    var cardMap = Board.indexTree(roots).cardMap
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(targetKeys(rows), "board,card:m1,card:s1", "the story is listed")
    compare(rows[2].level, "story", "level")
    compare(rows[2].depth, 1, "depth")
    compare(rows[2].label, "Story \"T s1\" (milestone \"T m1\")", "label names its milestone")
    var bare = Runs.dispatchTargets(roots, undefined)
    compare(targetKeys(bare), "board,card:m1,card:s1", "still listed without a cardMap")
    compare(bare[2].label, "Story \"T s1\"", "label without its milestone")
  }

  function test_dispatch_targets_agree_with_dispatchPlan() {
    // synthetic: a milestone per status, a story per status under each, a subtask per status
    // under each story; under m0s0, cards with ids "-x", "" and 5, then one appended after
    // indexing, so it has no depth
    var statuses = ["todo", "in_progress", "review", "blocked", "", "TODO", undefined,
                    "done", "merged", "canceled", "archived"]
    var roots = []
    for (var i = 0; i < statuses.length; i++) {
      var stories = []
      for (var j = 0; j < statuses.length; j++) {
        var subtasks = []
        for (var k = 0; k < statuses.length; k++) subtasks.push(tnode("m" + i + "s" + j + "t" + k, statuses[k]))
        stories.push(tnode("m" + i + "s" + j, statuses[j], subtasks))
      }
      roots.push(tnode("m" + i, statuses[i], stories))
    }
    var odd = roots[0].children[0].children
    odd.push(tnode("-x", "todo"), tnode("", "todo"), tnode(5, "todo"))
    var cardMap = Board.indexTree(roots).cardMap
    odd.push(tnode("nodepth", "todo"))
    var rows = Runs.dispatchTargets(roots, cardMap)
    // 7 unfinished milestones, 11 * 7 unfinished stories, 121 todo subtasks
    compare(rows.length, 1 + 7 + 77 + 121, "row count")
    var rowed = {}
    for (var r = 1; r < rows.length; r++) {
      var plan = Runs.dispatchPlan(rows[r].card, cardMap)
      compare(plan.offered, true, rows[r].key + " offered")
      compare(plan.level, rows[r].level, rows[r].key + " level")
      compare(rows[r].label, Runs.dispatchLabel(rows[r].card, cardMap), rows[r].key + " label")
      rowed[rows[r].key] = true
    }
    var ids = Object.keys(cardMap)
    for (var c = 0; c < ids.length; c++) {
      var card = cardMap[ids[c]]
      if (rowed["card:" + card.id] === true) continue
      var p = Runs.dispatchPlan(card, cardMap)
      verify(!p.offered || (p.level === "subtask" && card.status !== "todo"),
             ids[c] + " has no row only when refused or a subtask that is not todo")
    }
    compare(rowed["card:-x"], undefined, "a flag-like id gives no row")
    compare(rowed["card:"], undefined, "an empty id gives no row")
    compare(rowed["card:5"], undefined, "a number id gives no row")
    compare(rowed["card:nodepth"], undefined, "a card without depth gives no row")
  }

  function test_dispatch_targets_empty_tree() {
    // synthetic: roots that hold no tree
    var empties = [[], undefined, null, "x", 5, {}]
    for (var e = 0; e < empties.length; e++) {
      var rows = Runs.dispatchTargets(empties[e], {})
      compare(rows.length, 1, "roots " + e + " gives one row")
      checkWholeBoard(rows[0], "roots " + e)
    }
    // synthetic: every card finished or a subtask that is not todo
    var roots = [tnode("m1", "done", [tnode("s1", "merged", [tnode("t1", "in_progress"), tnode("t2", "review")])]),
                 tnode("m2", "archived", [tnode("s2", "canceled")])]
    var cardMap = Board.indexTree(roots).cardMap
    var only = Runs.dispatchTargets(roots, cardMap)
    compare(only.length, 1, "no offered target gives one row")
    checkWholeBoard(only[0], "no offered target")
  }

  function test_dispatch_targets_garbage() {
    // synthetic: non-object roots around one milestone, depth set by hand
    var m = tnode("m1", "todo")
    m.depth = 0
    m.parentId = null
    var mixed = [null, "x", [], 5, m]
    var mixedBefore = JSON.stringify(mixed)
    compare(targetKeys(Runs.dispatchTargets(mixed, {})), "board,card:m1", "only the milestone")
    compare(JSON.stringify(mixed), mixedBefore, "mixed roots unchanged")

    // synthetic: children that are not an array
    var odd = [tnode("a", "todo", "x"), tnode("b", "todo", {}), tnode("c", "todo", null)]
    for (var o = 0; o < odd.length; o++) {
      odd[o].depth = 0
      odd[o].parentId = null
    }
    var oddBefore = JSON.stringify(odd)
    compare(targetKeys(Runs.dispatchTargets(odd, {})), "board,card:a,card:b,card:c", "each node listed, no children")
    compare(JSON.stringify(odd), oddBefore, "odd children unchanged")

    // synthetic: a story whose children hold its own milestone
    var cm = tnode("m1", "todo", [])
    var cs = tnode("s1", "todo", [cm])
    cm.depth = 0
    cm.parentId = null
    cs.depth = 1
    cs.parentId = "m1"
    cm.children.push(cs)
    compare(targetKeys(Runs.dispatchTargets([cm], { m1: cm, s1: cs })), "board,card:m1,card:s1", "a cycle lists each node once")

    // synthetic: one subtask object in two stories' children
    var shared = tnode("t1", "todo")
    var sharedRoots = [tnode("m1", "todo", [tnode("s1", "todo", [shared]), tnode("s2", "todo", [shared])])]
    var sharedMap = Board.indexTree(sharedRoots).cardMap
    var sharedBefore = JSON.stringify(sharedRoots)
    compare(targetKeys(Runs.dispatchTargets(sharedRoots, sharedMap)), "board,card:m1,card:s1,card:t1,card:s2",
            "a shared child is listed once, under its first parent")
    compare(JSON.stringify(sharedRoots), sharedBefore, "shared tree unchanged")

    // synthetic: two distinct stories with the same id
    var first = tnode("s1", "todo", [tnode("t1", "todo")])
    var twin = tnode("s1", "todo", [tnode("t2", "todo")])
    var twinRoots = [tnode("m1", "todo", [first, twin])]
    var twinMap = Board.indexTree(twinRoots).cardMap
    var twinRows = Runs.dispatchTargets(twinRoots, twinMap)
    compare(targetKeys(twinRows), "board,card:m1,card:s1,card:t1,card:t2", "the first twin only, the later twin's children walked")
    verify(twinRows[2].card === first, "the first twin's node")

    // synthetic: a milestone whose id is "board"
    var boardRoots = [tnode("board", "todo")]
    var boardRows = Runs.dispatchTargets(boardRoots, Board.indexTree(boardRoots).cardMap)
    compare(targetKeys(boardRows), "board,card:board", "a card id board is not the Whole board")
    compare(boardRows[1].level, "milestone", "it is a milestone")
    compare(boardRows[1].label, "Milestone \"T board\"", "with its own label")

    // synthetic: cardMaps that are not a plain map, and one owning a __proto__ entry
    var tree = [tnode("m1", "todo", [tnode("s1", "todo", [tnode("t1", "todo")])])]
    Board.indexTree(tree)
    var protoMap = {}
    Object.defineProperty(protoMap, "__proto__", { value: tnode("__proto__", "todo"), enumerable: true })
    var maps = [null, "x", [], protoMap]
    for (var p = 0; p < maps.length; p++)
      compare(targetKeys(Runs.dispatchTargets(tree, maps[p])), "board,card:m1,card:s1,card:t1", "cardMap " + p)
  }

  function test_dispatch_targets_deep_chain() {
    // synthetic: a chain of 5000 todo cards, each the only child of the previous; depth and
    // parentId set by hand, as Board.indexTree recurses past the call stack at this depth
    var chain = []
    var cardMap = {}
    for (var i = 0; i < 5000; i++) {
      var c = tnode("c" + i, "todo", [])
      c.depth = i
      c.parentId = i === 0 ? null : "c" + (i - 1)
      if (i > 0) chain[i - 1].children.push(c)
      chain.push(c)
      cardMap[c.id] = c
    }
    var roots = [chain[0]]
    var rows = Runs.dispatchTargets(roots, cardMap)
    compare(rows.length, 5001, "the Whole board and every card")
    checkWholeBoard(rows[0], "row 0")
    compare(rows[1].level, "milestone", "c0")
    compare(rows[2].level, "story", "c1")
    for (var r = 1; r < rows.length; r++) {
      compare(rows[r].key, "card:c" + (r - 1), "row " + r + " key")
      if (r >= 3) compare(rows[r].level, "subtask", "row " + r + " level")
    }
  }

  function test_dispatch_targets_fresh() {
    // synthetic: one milestone with one story
    var roots = [tnode("m1", "todo", [tnode("s1", "todo")])]
    var cardMap = Board.indexTree(roots).cardMap
    var a = Runs.dispatchTargets(roots, cardMap)
    var b = Runs.dispatchTargets(roots, cardMap)
    verify(a !== b, "a new array each call")
    compare(a.length, b.length, "same rows")
    for (var i = 0; i < a.length; i++) verify(a[i] !== b[i], "row " + i + " is a new object")
    verify(a[1].card === roots[0], "row 1 carries the milestone node")
    verify(b[2].card === roots[0].children[0], "row 2 carries the story node")
    a[0].label = "changed"
    checkWholeBoard(Runs.dispatchTargets(roots, cardMap)[0], "after a caller edits a row")
  }

  // ---- RR 1.2: why it stopped -------------------------------------------------------------

  readonly property string stopEscCard: "10e26d57-374c-48d3-bc45-09389b42cfac"
  readonly property string stopEscStory: "bf8154fc-e65c-46f5-b6e8-92b616a6e62b"
  readonly property string stopEscStoryTitle: "Story B: blocked by story A"
  readonly property string stopEscMilestone: "f18d342f-4887-4cd8-a86e-dd2755237c2c"
  readonly property string stopEscPending: "460aaaa9-0520-40f7-aaa5-f162afab8bc0"
  readonly property string stopReviewDetail: "phase 'review' gate 'review_blockers_gate' failed: blocked=review, detail=review left 1 unresolved blocker(s): the review-fail marker names m3/task-b1-only-subtask-of-10e26d57"
  readonly property string stopStartedCard: "2280a6ab-9c40-434b-9729-63fd1f373754"
  readonly property string stopStartedStory: "7a7effb4-6ec5-4596-bcf1-be24546d4ac1"
  readonly property string stopStartedMilestone: "e795ad19-c81f-43ec-bdda-ef61ab5f860b"
  readonly property string stopHeartbeat: "2026-10-08T14:38:28.740774+00:00"
  readonly property string stopHeadlineDead: "The run's process died"
  readonly property string stopHeadlineParked: "Paused at a phase boundary"
  readonly property string stopHeadlineCancelled: "Cancelled. A cancelled run cannot be resumed, only relaunched; cards keep their status"

  // The report stopReport gives when nothing is named, with `over`'s keys replacing the defaults.
  function stopWant(over) {
    var want = { state: "", headline: "", cardId: "", storyId: "", storyTitle: "", phase: "", detail: "",
                 heartbeatAt: "", attempt: null, parked: [], relaunch: null }
    var keys = Object.keys(over)
    for (var i = 0; i < keys.length; i++) want[keys[i]] = over[keys[i]]
    return want
  }

  // a and b, null or flat objects, have the same keys and the same values.
  function compareFlat(a, b, label) {
    if (b === null) { compare(a, null, label); return }
    verify(a !== null && typeof a === "object", label + ": an object")
    compare(Object.keys(a).sort().join(","), Object.keys(b).sort().join(","), label + ": keys")
    var keys = Object.keys(b)
    for (var i = 0; i < keys.length; i++) compare(a[keys[i]], b[keys[i]], label + ": " + keys[i])
  }

  // A stopReport result equals `want` (a stopWant): exactly the eleven keys, every value.
  function checkReport(rep, want, label) {
    verify(rep !== null && typeof rep === "object", label + ": a report")
    compare(Object.keys(rep).sort().join(","),
            "attempt,cardId,detail,headline,heartbeatAt,parked,phase,relaunch,state,storyId,storyTitle", label + ": keys")
    var keys = ["state", "headline", "cardId", "storyId", "storyTitle", "phase", "detail", "heartbeatAt"]
    for (var i = 0; i < keys.length; i++) compare(rep[keys[i]], want[keys[i]], label + ": " + keys[i])
    compareFlat(rep.attempt, want.attempt, label + ": attempt")
    compare(Array.isArray(rep.parked), true, label + ": parked is an array")
    compare(JSON.stringify(rep.parked), JSON.stringify(want.parked), label + ": parked")
    compareFlat(rep.relaunch, want.relaunch, label + ": relaunch")
  }

  // The recorded escalated run's relaunch target.
  function stopEscRelaunch() { return { level: "milestone", cardId: stopEscMilestone, prefix: "m3", base: "main" } }

  // The recorded started run's relaunch target.
  function stopStartedRelaunch() { return { level: "milestone", cardId: stopStartedMilestone, prefix: "dsp", base: "main" } }

  // The report on the recorded escalated run, with `over`'s keys replacing it.
  function stopEscWant(over) {
    var want = stopWant({ state: "escalated", headline: "Escalated at review", cardId: stopEscCard, storyId: stopEscStory,
                          storyTitle: stopEscStoryTitle, phase: "review", detail: stopReviewDetail,
                          attempt: { card_id: stopEscCard, phase: "review", attempt: 1 }, relaunch: stopEscRelaunch() })
    var keys = Object.keys(over)
    for (var i = 0; i < keys.length; i++) want[keys[i]] = over[keys[i]]
    return want
  }

  // amRun("status-started.json") with its lease no longer live: a dead run.
  function deadStartedRaw() {
    var raw = amRun("status-started.json")
    raw.status.control.lease.live = false
    return raw
  }

  // The report on deadStartedRaw(), with `over`'s keys replacing it.
  function stopDeadWant(over) {
    var want = stopWant({ state: "dead", headline: stopHeadlineDead, cardId: stopStartedCard, storyId: stopStartedStory,
                          storyTitle: "Dispatch backend", phase: "explore", heartbeatAt: stopHeartbeat,
                          attempt: { card_id: stopStartedCard, phase: "explore", attempt: 1 }, relaunch: stopStartedRelaunch() })
    var keys = Object.keys(over)
    for (var i = 0; i < keys.length; i++) want[keys[i]] = over[keys[i]]
    return want
  }

  function test_normalize_card_and_story_ids() {
    var recorded = Runs.normalizeRun(amRun("status-escalated.json"))
    compare(recorded.card_id, "", "recorded escalated: card_id null")
    compare(recorded.story_id, "", "recorded escalated: story_id null")

    // synthetic: the row names a card and a story
    var fromRow = amRun("status-started.json")
    fromRow.row.card_id = "c-1"
    fromRow.row.story_id = "s-1"
    var r = Runs.normalizeRun(fromRow)
    compare(r.card_id, "c-1", "row card_id")
    compare(r.story_id, "s-1", "row story_id")

    // synthetic: only am status's run names them
    var fromStatus = amRun("status-started.json")
    fromStatus.status.run.card_id = "c-2"
    fromStatus.status.run.story_id = "s-2"
    r = Runs.normalizeRun(fromStatus)
    compare(r.card_id, "c-2", "status run card_id")
    compare(r.story_id, "s-2", "status run story_id")

    // synthetic: both name them; the row wins
    var both = amRun("status-started.json")
    both.row.card_id = "c-1"
    both.row.story_id = "s-1"
    both.status.run.card_id = "c-2"
    both.status.run.story_id = "s-2"
    r = Runs.normalizeRun(both)
    compare(r.card_id, "c-1", "row wins card_id")
    compare(r.story_id, "s-1", "row wins story_id")

    // synthetic: null on both sides, and numbers
    r = Runs.normalizeRun({ row: { card_id: null, story_id: null }, status: { run: { card_id: null, story_id: null } } })
    compare(r.card_id, "", "null card_id")
    compare(r.story_id, "", "null story_id")
    r = Runs.normalizeRun({ row: { card_id: 7 }, status: { run: { story_id: 8 } } })
    compare(r.card_id, "7", "number card_id is text")
    compare(r.story_id, "8", "number story_id is text")
  }

  function test_stopReport_escalated_recorded() {
    checkReport(Runs.stopReport(Runs.normalizeRun(amRun("status-escalated.json"))), stopEscWant({}), "recorded escalated")
  }

  function test_stopReport_escalated_detail_from_attempt() {
    // synthetic: the review phase's detail removed, its attempt given one
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].detail = null
    raw.status.stories[1].subtasks[0].phases[11].attempts[0].detail = "  from the attempt \n"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({ detail: "from the attempt" }), "detail from the attempt")
  }

  function test_stopReport_escalated_failed_step() {
    // synthetic: review done, a failed deterministic verify step appended
    var raw = amRun("status-escalated.json")
    var subtask = raw.status.stories[1].subtasks[0]
    subtask.phases[11].status = "done"
    subtask.phases.push({ name: "verify", kind: "deterministic", status: "failed",
                          detail: "VerifyError: 2 tests failed", attempts: [] })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ headline: "Escalated at verify", phase: "verify", detail: "VerifyError: 2 tests failed",
                              attempt: { card_id: stopEscCard, phase: "verify", attempt: 0 } }), "failed step, attempt 0")
  }

  function test_stopReport_escalated_phase_from_row() {
    // synthetic: the failed review phase set done; its gate_failed row remains
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "phase from the row")
  }

  function test_stopReport_synthetic_story() {
    // synthetic: the done-integrate capture made escalated, its integrate story escalated
    var raw = amRun("status-done-integrate.json")
    raw.status.run.status = "escalated"
    raw.status.stories[2].status = "escalated"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated at Integrate", storyId: "integrate", storyTitle: "Integrate",
                           relaunch: { level: "milestone", cardId: "f7f73454-b9c5-464a-b8d4-659dd5b353af", prefix: "m3", base: "main" } }),
                "integrate story")
  }

  function test_stopReport_synthetic_base_row() {
    // synthetic: an escalated run, every subtask done, whose rows end with a failed base merge
    var raw = amRun("status-escalated-integrate.json")
    raw.status.rows.push({ story: "bases", subtask: "base-s1", phase: "merge", attempt: null, state: "failed" })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated at Base s1", storyId: "base-s1", storyTitle: "Base s1",
                           phase: "merge",
                           relaunch: { level: "milestone", cardId: "76043cd6-2077-47d4-afbb-c0ab60e62416", prefix: "m4", base: "main" } }),
                "base row")
  }

  function test_stopReport_escalated_nothing_named() {
    checkReport(Runs.stopReport(Runs.normalizeRun(amRun("status-escalated-integrate.json"))),
                stopWant({ state: "escalated", headline: "Escalated",
                           relaunch: { level: "milestone", cardId: "76043cd6-2077-47d4-afbb-c0ab60e62416", prefix: "m4", base: "main" } }),
                "recorded escalated integrate")
  }

  function test_stopReport_dead() {
    var dead = Runs.normalizeRun(deadStartedRaw())
    compare(Runs.runState(dead), "dead", "fixture")
    checkReport(Runs.stopReport(dead), stopDeadWant({}), "dead, lease not live")

    // synthetic: no lease at all
    var raw = amRun("status-started.json")
    delete raw.status.control.lease
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopDeadWant({ heartbeatAt: "" }), "dead, no lease")
  }

  function test_stopReport_dead_nothing_in_flight() {
    // synthetic: the dead capture's in-flight explore phase set done
    var raw = deadStartedRaw()
    raw.status.stories[1].subtasks[1].phases[1].status = "done"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopDeadWant({ cardId: "", storyId: "", storyTitle: "", phase: "", attempt: null }), "dead, nothing in flight")
  }

  function test_stopReport_parked() {
    // synthetic: the started capture stopped, its in-flight subtask stopped
    var raw = amRun("status-started.json")
    raw.status.run.status = "stopped"
    raw.status.stories[1].subtasks[1].status = "stopped"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "parked", headline: stopHeadlineParked, parked: [stopStartedCard], relaunch: stopStartedRelaunch() }),
                "parked")
  }

  function test_stopReport_cancelled_both_spellings() {
    var spellings = ["cancelled", "canceled"]
    for (var i = 0; i < spellings.length; i++) {
      // synthetic: the started capture cancelled, its in-flight subtask stopped
      var raw = amRun("status-started.json")
      raw.status.run.status = spellings[i]
      raw.status.stories[1].subtasks[1].status = "stopped"
      checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                  stopWant({ state: "cancelled", headline: stopHeadlineCancelled, parked: [stopStartedCard], relaunch: stopStartedRelaunch() }),
                  spellings[i])
    }
  }

  function test_stopReport_escalated_lists_parked() {
    // synthetic: the escalated capture's pending subtask stopped
    var raw = amRun("status-escalated.json")
    raw.status.stories[2].subtasks[0].status = "stopped"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({ parked: [stopEscPending] }), "escalated lists parked")
  }

  function test_stopReport_task_run() {
    // synthetic: the escalated capture as a task run of its escalated card
    var raw = amRun("status-escalated.json")
    raw.row.workflow = "task"
    raw.row.card_id = stopEscCard
    var task = { level: "card", cardId: stopEscCard, prefix: "m3", base: "main" }
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({ relaunch: task }), "task run")

    // synthetic: padded workflow and card id
    var padded = amRun("status-escalated.json")
    padded.row.workflow = "  task "
    padded.row.card_id = "  " + stopEscCard + "\n"
    compareFlat(Runs.stopReport(Runs.normalizeRun(padded)).relaunch, task, "padded task run")

    // synthetic: a task run that names no card
    var noCard = amRun("status-escalated.json")
    noCard.row.workflow = "task"
    compare(Runs.stopReport(Runs.normalizeRun(noCard)).relaunch, null, "task run without a card")

    // synthetic: workflow is case-sensitive: "Task" is a milestone run
    var upper = amRun("status-escalated.json")
    upper.row.workflow = "Task"
    upper.row.card_id = stopEscCard
    compareFlat(Runs.stopReport(Runs.normalizeRun(upper)).relaunch, stopEscRelaunch(), "Task is not task")
  }

  function test_stopReport_story_run() {
    // synthetic: the escalated capture as a story run of its escalated story
    var raw = amRun("status-escalated.json")
    raw.row.workflow = "story"
    raw.row.story_id = stopEscStory
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ relaunch: { level: "story", cardId: stopEscStory, prefix: "m3", base: "main" } }), "story run")

    // synthetic: a story run that names no story
    var noStory = amRun("status-escalated.json")
    noStory.row.workflow = "story"
    compare(Runs.stopReport(Runs.normalizeRun(noStory)).relaunch, null, "story run without a story")

    // synthetic: a story run whose story is bookkeeping
    var bases = amRun("status-escalated.json")
    bases.row.workflow = "story"
    bases.row.story_id = "bases"
    compare(Runs.stopReport(Runs.normalizeRun(bases)).relaunch, null, "story run of bases")
  }

  function test_stopReport_milestone_run_without_milestone() {
    var ids = ["", "integrate", "base-x"]
    for (var i = 0; i < ids.length; i++) {
      // synthetic: the milestone id blanked or made bookkeeping on both sides
      var raw = amRun("status-escalated.json")
      raw.row.milestone_id = ids[i]
      raw.status.run.milestone_id = ids[i]
      compare(Runs.stopReport(Runs.normalizeRun(raw)).relaunch, null, "milestone_id \"" + ids[i] + "\"")
    }
  }

  function test_stopReport_null_unless_stopped() {
    compare(Runs.stopReport(Runs.normalizeRun(amRun("status-started.json"))), null, "running")
    compare(Runs.stopReport(Runs.normalizeRun(amRun("status-done.json"))), null, "done")
    var statuses = ["", "bogus", " stopped", "Escalated"]
    for (var i = 0; i < statuses.length; i++) {
      // synthetic: run statuses that are unknown to runState
      var raw = amRun("status-escalated.json")
      raw.status.run.status = statuses[i]
      compare(Runs.stopReport(Runs.normalizeRun(raw)), null, "status \"" + statuses[i] + "\"")
    }
  }

  function test_stopReport_garbage() {
    var notRuns = [undefined, null, 0, "escalated", true, [], {}]
    for (var i = 0; i < notRuns.length; i++) compare(Runs.stopReport(notRuns[i]), null, "not a run " + i)

    // synthetic: stopped runs with nothing readable
    checkReport(Runs.stopReport({ status: "escalated" }), stopWant({ state: "escalated", headline: "Escalated" }), "bare escalated")
    checkReport(Runs.stopReport({ status: "stopped", tree: "x" }), stopWant({ state: "parked", headline: stopHeadlineParked }), "tree not an object")
    checkReport(Runs.stopReport({ status: "escalated",
                                  tree: { subtasks: [null, { phases: "x" }, { card_id: 5 }], stories: [null] }, rows: [null, 3] }),
                stopWant({ state: "escalated", headline: "Escalated" }), "broken tree and rows")
    checkReport(Runs.stopReport({ status: "started", lease: "x" }), stopWant({ state: "dead", headline: stopHeadlineDead }), "lease not an object")
    checkReport(Runs.stopReport({ status: "escalated", tree: { subtasks: "x" } }), stopWant({ state: "escalated", headline: "Escalated" }), "subtasks not an array")

    // synthetic: a real escalated subtask with broken phases, attempts, rows, title and ids
    var broken = { status: "escalated", workflow: 5, milestone_id: 7,
                   tree: { stories: [null, { card_id: "s1", title: 5 }],
                           subtasks: [{ card_id: "t1", story_id: "s1", status: "escalated",
                                        phases: [null, 3, { name: "review", status: "failed", attempts: "x" }] }] },
                   rows: [null, 3, { card_id: "t1", phase: "review", attempt: "x", status: "failed" }] }
    checkReport(Runs.stopReport(broken),
                stopWant({ state: "escalated", headline: "Escalated at review", cardId: "t1", storyId: "s1", phase: "review",
                           attempt: { card_id: "t1", phase: "review", attempt: 0 } }), "broken escalated subtask")

    // synthetic: a dead run with a numeric heartbeat and odd attempts
    var deadOdd = { status: "started", lease: { live: false, heartbeat_at: 42 },
                    tree: { subtasks: [{ card_id: "t1", phases: [{ name: "plan", status: "started", attempts: [null, "x", { n: 2 }] }] }] } }
    checkReport(Runs.stopReport(deadOdd),
                stopWant({ state: "dead", headline: stopHeadlineDead, cardId: "t1", phase: "plan", heartbeatAt: "42",
                           attempt: { card_id: "t1", phase: "plan", attempt: 2 } }), "dead, odd attempts")
  }

  function test_stopReport_fresh_and_untouched() {
    var run = Runs.normalizeRun(amRun("status-escalated.json"))
    // synthetic: a stopped subtask so parked is not empty
    run.tree.subtasks[3].status = "stopped"
    var before = JSON.stringify(run)
    var a = Runs.stopReport(run)
    var b = Runs.stopReport(run)
    compare(JSON.stringify(run), before, "the run is unchanged")
    verify(a !== b, "a new report per call")
    verify(a.attempt !== b.attempt, "a new attempt per call")
    verify(a.parked !== b.parked, "a new parked list per call")
    verify(a.relaunch !== b.relaunch, "a new relaunch per call")
    a.headline = "x"
    a.attempt.phase = "x"
    a.parked.push("x")
    a.relaunch.cardId = "x"
    compare(JSON.stringify(run), before, "mutating a report leaves the run unchanged")
    checkReport(Runs.stopReport(run), stopEscWant({ parked: [stopEscPending] }), "after mutating an earlier report")
  }

  function test_stopReport_other_cards_row() {
    // synthetic: review set done, and the last (gate_failed review) row moved to another card
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    raw.status.rows[raw.status.rows.length - 1].subtask = stopEscPending
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ headline: "Escalated", phase: "", detail: "", attempt: null }), "another card's failed row")
  }

  function test_stopReport_last_failed_row_wins() {
    // synthetic: review set done, and an earlier implement row of the same card made failed
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    var rows = raw.status.rows
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].subtask === stopEscCard && rows[i].phase === "implement") rows[i].state = "failed"
    }
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "the last failed row names the phase")
  }

  function test_stopReport_row_attempt_newer() {
    // synthetic: review set done, its gate_failed row a second attempt the tree has not recorded
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].subtasks[0].phases[11].status = "done"
    raw.status.rows[raw.status.rows.length - 1].attempt = 2
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ attempt: { card_id: stopEscCard, phase: "review", attempt: 2 } }), "row attempt wins")
  }

  function test_stopReport_escalated_order() {
    // synthetic: an earlier subtask's explore phase failed; the later escalated subtask still wins
    var raw = amRun("status-escalated.json")
    raw.status.stories[0].subtasks[0].phases[1].status = "failed"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "escalated status wins")

    // synthetic: with no escalated subtask, the first subtask with a failed phase is named
    raw.status.stories[1].subtasks[0].status = "started"
    var cardA = "f6ac3b15-77df-4921-a9c0-0b442db53bb5"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopEscWant({ headline: "Escalated at explore", cardId: cardA, storyId: "c16cfbe3-ca4f-4f27-8bdb-f595620296c6",
                              storyTitle: "Story A: the first level", phase: "explore", detail: "",
                              attempt: { card_id: cardA, phase: "explore", attempt: 1 } }), "first failed phase in tree order")
  }

  function test_stopReport_synthetic_precedence() {
    var relaunch = { level: "milestone", cardId: "f7f73454-b9c5-464a-b8d4-659dd5b353af", prefix: "m3", base: "main" }
    // synthetic: escalated, but the integrate story is done and a synthetic row is ok
    var raw = amRun("status-done-integrate.json")
    raw.status.run.status = "escalated"
    raw.status.rows.push({ story: "bases", subtask: "base-s1", phase: "merge", attempt: null, state: "ok" })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated", relaunch: relaunch }), "done story and ok row are not named")

    // synthetic: a failed synthetic row wins over an escalated synthetic story
    raw.status.stories[2].status = "escalated"
    raw.status.rows.push({ story: "bases", subtask: "base-s1", phase: "merge", attempt: null, state: "failed" })
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)),
                stopWant({ state: "escalated", headline: "Escalated at Base s1", storyId: "base-s1", storyTitle: "Base s1",
                           phase: "merge", relaunch: relaunch }), "row wins over story")
  }

  function test_stopReport_story_title_edges() {
    // synthetic: a padded story title
    var raw = amRun("status-escalated.json")
    raw.status.stories[1].title = "  " + stopEscStoryTitle + " \n"
    checkReport(Runs.stopReport(Runs.normalizeRun(raw)), stopEscWant({}), "padded title")

    var ids = ["constructor", "__proto__", "toString"]
    for (var i = 0; i < ids.length; i++) {
      // synthetic: the escalated subtask's story id set to a name no story has
      var run = Runs.normalizeRun(amRun("status-escalated.json"))
      run.tree.subtasks[2].story_id = ids[i]
      checkReport(Runs.stopReport(run), stopEscWant({ storyId: ids[i], storyTitle: "" }), "story id " + ids[i])
    }
  }

  // ---- RR 1.3: am's note -------------------------------------------------------------------

  readonly property string noteRun: "20261004T165007Z-4a51d663"
  readonly property string noteOtherRun: "20261004T170000Z-ffffffff"
  readonly property string noteAt: "2026-10-04T17:45:00Z"
  readonly property string noteLaterAt: "2026-10-04T18:00:00Z"

  // One card comment as ExtrasStore.commentsFor gives it.
  function comment(author, body, createdAt) {
    return { id: "c-" + createdAt, entityId: "5bfe746d-8ac3-41c4-8e3e-abb939e0b45a", author: author, body: body,
             createdAt: createdAt }
  }

  // SUBTASK_BODY's lines (RR 62-68, the ellipses kept as in RR).
  function noteSubtaskLines() {
    return ["am \u00b7 escalated \u00b7 run 20261004T165007Z-4a51d663",
            "phase: verify",
            "detail: VerifyError: could not run none (CLAUDE.md: …)",
            "next: `am resume 20261004T165007Z-4a51d663`",
            "why: `am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify`",
            "am-key: 20261004T165007Z-4a51d663/5bfe746d-…/escalated:cef56efb…"]
  }

  function noteSubtaskBody() { return noteSubtaskLines().join("\n") }

  // RUN_END_BODY. synthetic: assembled from RR 71-72
  function noteRunEndBody() {
    return ["am \u00b7 escalated \u00b7 run 20261004T165007Z-4a51d663",
            "escalated: [[5bfe746d-8ac3-41c4-8e3e-abb939e0b45a]] at verify",
            "next: `am resume 20261004T165007Z-4a51d663`",
            "am-key: 20261004T165007Z-4a51d663/76043cd6-2077-47d4-afbb-c0ab60e62416/run-end:0a1b2c3d"].join("\n")
  }

  // DONE_BODY. synthetic: a later note of the same run
  function noteDoneBody() {
    return ["am \u00b7 done \u00b7 run 20261004T165007Z-4a51d663",
            "am-key: 20261004T165007Z-4a51d663/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/done:9f9f9f9f"].join("\n")
  }

  // The note stopComment reads from SUBTASK_BODY, posted at createdAt.
  function noteSubtaskWant(createdAt) {
    return { createdAt: createdAt, kind: "escalated", fields: [
      { key: "detail", value: "VerifyError: could not run none (CLAUDE.md: …)" },
      { key: "next", value: "am resume 20261004T165007Z-4a51d663" },
      { key: "why", value: "am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify" }] }
  }

  // got is the note want describes: exactly the keys createdAt, fields and kind,
  // with want's values (fields compared in order); or both are null.
  function checkNote(got, want, label) {
    if (want === null) { compare(got, null, label); return }
    verify(got !== null && typeof got === "object", label + ": an object")
    compare(Object.keys(got).sort().join(","), "createdAt,fields,kind", label + ": keys")
    compare(got.createdAt, want.createdAt, label + ": createdAt")
    compare(got.kind, want.kind, label + ": kind")
    verify(Array.isArray(got.fields), label + ": fields is an array")
    compare(JSON.stringify(got.fields), JSON.stringify(want.fields), label + ": fields")
  }

  function test_stopComment_subtask_escalation() {
    checkNote(Runs.stopComment([comment("am", noteSubtaskBody(), noteAt)], noteRun), noteSubtaskWant(noteAt), "subtask note")
  }

  function test_stopComment_milestone_run_end() {
    checkNote(Runs.stopComment([comment("am", noteRunEndBody(), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: [{ key: "next", value: "am resume 20261004T165007Z-4a51d663" }] },
              "run-end note, its escalated: line is not a field")
  }

  function test_stopComment_newest_wins() {
    var sub = comment("am", noteSubtaskBody(), noteAt)
    var done = comment("am", noteDoneBody(), noteLaterAt)
    checkNote(Runs.stopComment([sub, done], noteRun), { createdAt: noteLaterAt, kind: "done", fields: [] }, "the done note is newer")
    checkNote(Runs.stopComment([done, sub], noteRun), noteSubtaskWant(noteAt), "array order, not createdAt, says newest")
  }

  function test_stopComment_other_run() {
    var sub = comment("am", noteSubtaskBody(), noteAt)
    // synthetic: a newer note of another run on the same card
    var other = comment("am", ["am \u00b7 escalated \u00b7 run " + noteOtherRun,
                               "next: `am resume " + noteOtherRun + "`",
                               "am-key: " + noteOtherRun + "/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/escalated:11111111"].join("\n"),
                        noteLaterAt)
    var list = [sub, other]
    checkNote(Runs.stopComment(list, noteRun), noteSubtaskWant(noteAt), "the other run's newer note is skipped")
    checkNote(Runs.stopComment(list, noteOtherRun),
              { createdAt: noteLaterAt, kind: "escalated", fields: [{ key: "next", value: "am resume " + noteOtherRun }] },
              "asked for the other run")
    compare(Runs.stopComment(list, "20261004T999999Z-00000000"), null, "an unknown run")
  }

  function test_stopComment_run_id_prefix() {
    compare(Runs.stopComment([comment("am", noteSubtaskBody(), noteAt)], "20261004T165007Z-4a51d6"), null,
            "a prefix of the note's run id")
    // synthetic: the am-key is the run id with no "/"
    var bare = comment("am", "am \u00b7 done \u00b7 run " + noteRun + "\nam-key: " + noteRun, noteAt)
    compare(Runs.stopComment([bare], noteRun), null, "no slash after the run id")
  }

  function test_stopComment_author() {
    var am = comment("am", noteSubtaskBody(), noteAt)
    var others = ["paulo", "AM", "am-bot"]
    for (var i = 0; i < others.length; i++) {
      checkNote(Runs.stopComment([am, comment(others[i], noteSubtaskBody(), noteLaterAt)], noteRun), noteSubtaskWant(noteAt),
                "a newer comment by " + others[i])
    }
    compare(Runs.stopComment([comment("paulo", noteSubtaskBody(), noteAt), comment("AM", noteDoneBody(), noteLaterAt)], noteRun),
            null, "only non-am comments")
    checkNote(Runs.stopComment([comment(" am ", noteSubtaskBody(), noteAt)], noteRun), noteSubtaskWant(noteAt), "a padded author")
  }

  function test_stopComment_no_am_key() {
    var am = comment("am", noteSubtaskBody(), noteAt)
    var keyless = noteSubtaskLines()
    keyless.pop()
    checkNote(Runs.stopComment([am, comment("am", keyless.join("\n"), noteLaterAt)], noteRun), noteSubtaskWant(noteAt),
              "a newer am comment with no am-key line")
    // synthetic: a line after the am-key
    var middle = noteSubtaskLines()
    middle.push("note: written after the key")
    checkNote(Runs.stopComment([am, comment("am", middle.join("\n"), noteLaterAt)], noteRun), noteSubtaskWant(noteAt),
              "am-key on a middle line")
    compare(Runs.stopComment([comment("am", middle.join("\n"), noteLaterAt)], noteRun), null, "am-key not last, alone")
  }

  function test_stopComment_fields() {
    // synthetic: fields out of order, a duplicate next, look-alike keys
    var key = "am-key: " + noteRun + "/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/escalated:22222222"
    var lines = ["am \u00b7 escalated \u00b7 run " + noteRun,
                 "why: `am logs " + noteRun + "`",
                 "next: `am resume " + noteRun + "`",
                 "reason: `tests` do not cover the empty list",
                 "detail: VerifyError: boom",
                 "next: something else",
                 "Reason: capitalised",
                 "nextstep: not a field",
                 "phase: verify",
                 key]
    var want = [{ key: "reason", value: "tests do not cover the empty list" }, { key: "detail", value: "VerifyError: boom" },
                { key: "next", value: "am resume " + noteRun }, { key: "why", value: "am logs " + noteRun }]
    checkNote(Runs.stopComment([comment("am", lines.join("\n"), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: want }, "fixed order, first of each key, backticks removed")

    // synthetic: an empty reason and one made only of backticks
    var empty = lines.slice()
    empty[3] = "reason:"
    checkNote(Runs.stopComment([comment("am", empty.join("\n"), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: want.slice(1) }, "an empty reason is omitted")
    empty[3] = "reason:  `` "
    checkNote(Runs.stopComment([comment("am", empty.join("\n"), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: want.slice(1) }, "a reason of backticks only is omitted")

    // synthetic: a key on the first line is not a field
    checkNote(Runs.stopComment([comment("am", "next: `am resume " + noteRun + "`\n" + key, noteAt)], noteRun),
              { createdAt: noteAt, kind: "", fields: [] }, "a key on the first line")
  }

  function test_stopComment_kind() {
    var key = "am-key: " + noteRun + "/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/escalated:33333333"
    var cases = [["am \u00b7 base failed \u00b7 run " + noteRun, "base failed"],
                 ["am \u00b7 cancelled \u00b7 run " + noteRun, "cancelled"],
                 ["am \u00b7 done", "done"],
                 ["am \u00b7   done   \u00b7 run " + noteRun, "done"],
                 ["note \u00b7 escalated \u00b7 run " + noteRun, ""]]
    for (var i = 0; i < cases.length; i++) {
      checkNote(Runs.stopComment([comment("am", cases[i][0] + "\n" + key, noteAt)], noteRun),
                { createdAt: noteAt, kind: cases[i][1], fields: [] }, "first line " + i)
    }
    checkNote(Runs.stopComment([comment("am", key, noteAt)], noteRun), { createdAt: noteAt, kind: "", fields: [] },
              "only the am-key line")
  }

  function test_stopComment_line_endings() {
    var body = noteSubtaskLines().join("\r\n") + " \r\n\n  "
    checkNote(Runs.stopComment([comment("am", body, noteAt)], noteRun), noteSubtaskWant(noteAt), "CRLF and trailing blanks")
  }

  function test_stopComment_garbage() {
    var valid = comment("am", noteSubtaskBody(), noteAt)
    var badComments = [undefined, null, 0, "x", {}, true]
    for (var i = 0; i < badComments.length; i++) compare(Runs.stopComment(badComments[i], noteRun), null, "comments " + i)
    var badIds = [undefined, null, 42, {}, "", "  "]
    for (var j = 0; j < badIds.length; j++) compare(Runs.stopComment([valid], badIds[j]), null, "runId " + j)
    checkNote(Runs.stopComment([valid], "  " + noteRun + " "), noteSubtaskWant(noteAt), "a padded run id is trimmed")

    var junk = [undefined, null, 3, "x", [], {}, { author: "am" }, { author: "am", body: 7 },
                { author: 5, body: noteSubtaskBody() }, { author: "am", body: "" }, { author: "am", body: "\n \n" }]
    compare(Runs.stopComment(junk, noteRun), null, "only junk")
    checkNote(Runs.stopComment(junk.concat([valid]), noteRun), noteSubtaskWant(noteAt), "junk, then a note")
    checkNote(Runs.stopComment([valid].concat(junk), noteRun), noteSubtaskWant(noteAt), "a note, then newer junk")

    var noTime = comment("am", noteSubtaskBody(), noteAt)
    noTime.createdAt = 5
    checkNote(Runs.stopComment([noTime], noteRun), noteSubtaskWant(""), "a non-string createdAt")
  }

  function test_stopComment_fresh_and_untouched() {
    var list = [comment("am", noteSubtaskBody(), noteAt)]
    var before = JSON.stringify(list)
    var a = Runs.stopComment(list, noteRun)
    var b = Runs.stopComment(list, noteRun)
    verify(a !== b, "two calls, two objects")
    verify(a.fields !== b.fields, "two calls, two fields arrays")
    verify(a.fields[0] !== b.fields[0], "two calls, two field objects")
    a.kind = "changed"
    a.fields[0].value = "changed"
    a.fields.push({ key: "reason", value: "added" })
    checkNote(Runs.stopComment(list, noteRun), noteSubtaskWant(noteAt), "mutating a result leaves the next call alone")
    compare(JSON.stringify(list), before, "the comments are untouched")
  }

  function test_stopComment_regex_id() {
    // synthetic: a run id holding regex metacharacters
    var c = comment("am", "am \u00b7 done \u00b7 run a.b*c\nam-key: a.b*c/x", noteAt)
    checkNote(Runs.stopComment([c], "a.b*c"), { createdAt: noteAt, kind: "done", fields: [] }, "metacharacters match themselves")
    compare(Runs.stopComment([c], "aXbbc"), null, "the id is not a pattern")
  }

  // ---- store helpers shared by the run stores (split-runstore merge)

  function test_usable_roots_keep_each_root_once_in_registry_order() {
    var list = [{ root: "/a", name: "A" }, null, [], { root: "" }, { root: "-x" }, { root: 7 },
                { root: "/b", name: "B" }, { root: "/a", name: "again" }]
    compare(JSON.stringify(Runs.usableRoots(list)), JSON.stringify([{ root: "/a", name: "A" }, { root: "/b", name: "B" }]))
    compare(Runs.usableRoots(null).length, 0)
    compare(Runs.usableRoots(undefined).length, 0)
    compare(Runs.usableRoots({}).length, 0, "no numeric length")
    compare(Runs.usableRoots([{ root: "constructor" }])[0].root, "constructor", "a root named like a prototype member")
  }

  function test_verify_commands_keep_the_non_blank_strings_in_order() {
    compare(JSON.stringify(Runs.verifyCommands({ verify: ["a", " ", "", 5, null, " b "] })), JSON.stringify(["a", " b "]))
    compare(Runs.verifyCommands({ verify: "a" }).length, 0)
    compare(Runs.verifyCommands({}).length, 0)
    compare(Runs.verifyCommands(null).length, 0)
  }

  function test_merged_prefixes_override_the_stored_entries() {
    compare(JSON.stringify(Runs.mergedPrefixes({ m1: "a", m2: "b" }, { m2: "c" })), JSON.stringify({ m1: "a", m2: "c" }))
    var stored = { m1: "a" }
    var merged = Runs.mergedPrefixes(stored, { m3: "d" })
    verify(merged !== stored, "a fresh map")
    compare(JSON.stringify(stored), JSON.stringify({ m1: "a" }), "the stored map is not changed")
    compare(JSON.stringify(Runs.mergedPrefixes(["x"], { m1: "a" })), JSON.stringify({ m1: "a" }), "an array merges from nothing")
    compare(JSON.stringify(Runs.mergedPrefixes(null, { m1: "a" })), JSON.stringify({ m1: "a" }))
  }
}
