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
}
