// tests/core/stores/tst_run_titles_store.qml
// The run titles store: the open project's map mirrored from its card map,
// the one-at-a-time board-titles.py fetches of every other registered
// project with runs, the missing-id refetch, unreachable roots, Refresh, the
// panel reopening and registry changes. Built alone and driven through its
// inputs; stubbed Process objects stand in for board-titles.py.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunTitlesStore"

  property string rootA: "/home/u/a"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string titlesCmd: "python3|/plugin/core/backend/boards/board-titles.py|"

  // A RunTitlesStore built alone, closed, with nothing bound.
  function makeTitles() {
    var comp = Qt.createComponent("../../../core/stores/RunTitlesStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return { root: r, name: "proj" } })
  }

  // Run `id` of `root` as the run store hands it over: normalized, tagged
  // with its project, of milestone m1, with am's `stories` ([] when omitted).
  function runOf(id, root, stories) {
    var raw = {
      row: { id: id, repo_dir: root },
      status: { run: { id: id, milestone_id: "m1", status: "started" }, rows: [], stories: stories || [], subtasks: [] }
    }
    return Runs.withProject(Runs.normalizeRun(raw), root, "proj")
  }

  // A store with the registry `roots`, the run list `runList` and no open
  // project, then opened.
  function openTitles(roots, runList) {
    var s = makeTitles(); if (!s) return null
    s.projectRoots = registry(roots)
    s.runs = runList
    s.active = true
    return s
  }

  // board-titles.py's ok reply carrying `map`.
  function titlesOk(map) { return JSON.stringify({ ok: true, titles: map }) + "\n" }

  // The titles of every id a plain runOf run names.
  function plain() { return { m1: "Milestone one" } }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // The fetch in flight answered with `text` and exit code `code`.
  function answer(s, text, code) { reply(s.titlesRunner.current, text, code) }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // Store `s`'s queue, comma-joined.
  function queueOf(s) { return s.titleQueue.join(",") }

  // ---- the open project

  function test_the_open_project_mirrors_its_card_map() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA
    s.openCardMap = { c1: { title: " One " } }
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ c1: "One" }))
    compare(s.titleStatus[tc.rootA], "ok")
    s.openCardMap = { c1: { title: "One" }, c2: { title: "Two" } }
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ c1: "One", c2: "Two" }), "a new card map updates the map")
    s.openRoot = ""
    compare(Runs.hasKey(s.titlesByRoot, tc.rootA), false, "no open project: rootA's mirrored map is gone")
    compare(Runs.hasKey(s.titleStatus, tc.rootA), false, "and so is its status")
  }

  function test_an_open_root_with_a_trailing_slash_is_keyed_without_it() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA + "/"
    s.openCardMap = { c1: { title: "One" } }
    compare(s.titlesByRoot[tc.rootA].c1, "One")
    compare(Runs.hasKey(s.titlesByRoot, tc.rootA + "/"), false)
  }

  function test_the_open_project_is_never_fetched() {
    var s = makeTitles(); if (!s) return
    s.openRoot = tc.rootA
    s.openCardMap = { m1: { title: "Milestone one" } }
    s.projectRoots = registry([tc.rootA])
    s.runs = [runOf("r1", tc.rootA, [{ card_id: "s9", subtasks: [] }])]
    s.active = true
    compare(s.titlesRunner.current, null, "no board-titles.py for the open project, even for an id its board lacks")
    compare(queueOf(s), "")
    compare(s.fetchingRoot, "")
    compare(s.titleStatus[tc.rootA], "ok")
  }

  // ---- fetching on need

  function test_fetches_each_root_with_runs_one_at_a_time_in_registry_order() {
    var s = openTitles([tc.rootA, tc.rootB, tc.rootC], [runOf("rb", tc.rootB), runOf("ra", tc.rootA)])
    if (!s) return
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA, "registry order, not run order")
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB, "the root in flight is not in the queue")
    compare(s.titleStatus[tc.rootA], "loading")
    compare(s.titleStatus[tc.rootB], "loading")
    compare(Runs.hasKey(s.titleStatus, tc.rootC), false, "a root with no runs has no entry")
    answer(s, titlesOk(plain()), 0)
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify(plain()))
    compare(s.titleStatus[tc.rootA], "ok")
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootB, "the next queued root launches")
    compare(s.fetchingRoot, tc.rootB)
    compare(queueOf(s), "")
    answer(s, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootB], "ok")
    compare(s.fetchingRoot, "", "nothing left to fetch")
    compare(s.titlesRunner.busy, false)
  }

  function test_an_ok_reply_keeps_only_its_string_titles() {
    var s = openTitles([tc.rootA], [runOf("ra", tc.rootA)]); if (!s) return
    answer(s, titlesOk({ m1: "Milestone one", n: 5, o: null, p: { x: "y" } }), 0)
    compare(JSON.stringify(s.titlesByRoot[tc.rootA]), JSON.stringify({ m1: "Milestone one" }))
    compare(s.titleStatus[tc.rootA], "ok")
  }

  function test_a_new_run_list_queues_no_root_twice() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return
    var first = s.titlesRunner.current
    s.runs = [runOf("ra", tc.rootA), runOf("rb", tc.rootB), runOf("rb2", tc.rootB)]
    verify(s.titlesRunner.current === first, "the fetch in flight is not relaunched")
    compare(s.fetchingRoot, tc.rootA)
    compare(queueOf(s), tc.rootB)
  }

  function test_a_project_without_runs_is_never_fetched() {
    var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA)]); if (!s) return
    compare(queueOf(s), "")
    answer(s, titlesOk(plain()), 0)
    compare(s.fetchingRoot, "")
    compare(Runs.hasKey(s.titleStatus, tc.rootB), false)
    compare(Runs.hasKey(s.titlesByRoot, tc.rootB), false)
  }

  function test_unregistered_and_unusable_roots_are_never_fetched() {
    var s = makeTitles(); if (!s) return
    s.projectRoots = [{ root: "-x", name: "dash" }, { root: "", name: "empty" }, { root: tc.rootB, name: "b" }]
    var noProject = Runs.normalizeRun({ row: { id: "rn" }, status: { run: { id: "rn", milestone_id: "m1" } } })
    s.runs = [runOf("rx", "-x"), runOf("re", ""), runOf("ra", tc.rootA), noProject]
    s.active = true
    compare(s.titlesRunner.current, null, "no run of a registered, usable root: nothing launches")
    compare(queueOf(s), "")
    compare(JSON.stringify(s.titleStatus), "{}")
  }

  function test_a_registry_root_with_a_trailing_slash_is_keyed_and_fetched_without_it() {
    var s = makeTitles(); if (!s) return
    s.projectRoots = [{ root: tc.rootA + "/", name: "a" }, { root: tc.rootA, name: "a again" }]
    s.runs = [runOf("ra", tc.rootA + "/")]
    s.active = true
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA)
    compare(queueOf(s), "", "two entries of one root fetch it once")
    answer(s, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootA], "ok")
    compare(Runs.hasKey(s.titleStatus, tc.rootA + "/"), false)
    compare(s.fetchingRoot, "")
  }

  function test_nothing_launches_while_closed() {
    var s = makeTitles(); if (!s) return
    s.projectRoots = registry([tc.rootA, tc.rootB])
    s.runs = [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]
    compare(s.titlesRunner.current, null, "closed: nothing launches")
    compare(queueOf(s), tc.rootA + "," + tc.rootB, "the roots wait in the queue")
    s.active = true
    compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootA, "opening launches the first queued root")
    var proc = s.titlesRunner.current
    s.active = false
    reply(proc, titlesOk(plain()), 0)
    compare(s.titleStatus[tc.rootA], "ok", "a reply that lands after closing is applied")
    compare(s.fetchingRoot, "", "closed: rootB does not launch")
    compare(s.titlesRunner.busy, false)
    compare(queueOf(s), tc.rootB)
  }

  function test_an_unreachable_root_stays_quiet() {
    var bad = [
      [JSON.stringify({ ok: false, error: { type: "ProjectNotFoundError", message: "no project" } }) + "\n", 1],
      ["", 1],
      ["not json\n", 0],
      [JSON.stringify({ ok: true, titles: [] }) + "\n", 0]
    ]
    for (var i = 0; i < bad.length; i++) {
      var s = openTitles([tc.rootA, tc.rootB], [runOf("ra", tc.rootA), runOf("rb", tc.rootB)]); if (!s) return
      answer(s, bad[i][0], bad[i][1])
      compare(s.titleStatus[tc.rootA], "unreachable", "reply " + i)
      compare(Runs.hasKey(s.titlesByRoot, tc.rootA), false, "reply " + i + ": rootA's runs fall back to ids")
      compare(argv(s.titlesRunner.current), tc.titlesCmd + tc.rootB, "reply " + i + ": the queue goes on")
      answer(s, titlesOk(plain()), 0)
      s.runs = [runOf("ra", tc.rootA), runOf("ra2", tc.rootA), runOf("rb", tc.rootB)]
      compare(s.fetchingRoot, "", "reply " + i + ": a new run list asks nothing of rootA")
      compare(queueOf(s), "")
      compare(s.titleStatus[tc.rootA], "unreachable")
    }
  }
}
