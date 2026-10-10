// tests/core/stores/tst_run_history_store.qml
// The run history store: showOlder's runs-history.py page per snapshot root
// (argv per chip and age, the no-op cases), its reply (dedupe against the
// snapshot and the history, the cursor chaining pages, `more`, errors that
// keep the rows, latest wins per root), window overflow and snapshot-wins
// on a snapshot change, and every trigger that drops the pages. Built alone
// and driven through its inputs; stubbed Process objects stand in for
// runs-history.py.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunHistoryStore"

  Component { id: spyC; SignalSpy {} }

  property string rootA: "/home/u/a"
  property string rootB: "/home/u/b"
  property string historyCmd: "python3|/plugin/core/backend/runs/runs-history.py|"
  property string allStatuses: "done,escalated,stopped,cancelled,canceled"

  // A RunHistoryStore built alone, closed, with an empty snapshot.
  function makeHistory() {
    var comp = Qt.createComponent("../../../core/stores/RunHistoryStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // Run `id` of `root` as the run store hands it over: am status `status`
  // (a "started" run has no lease, so it is not terminal), started at
  // `startedAt`, tagged with project "proj".
  function runOf(id, root, status, startedAt) {
    var raw = {
      row: { id: id, repo_dir: root, started_at: startedAt, status: status },
      status: { run: { id: id, status: status }, rows: [], stories: [], subtasks: [] }
    }
    return Runs.withProject(Runs.normalizeRun(raw), root, "proj")
  }

  // rootA's base snapshot: a1 live, a2 done, a3 parked (the oldest terminal).
  function baseA() {
    return [runOf("a1", tc.rootA, "started", "2026-10-05T10:00:00Z"),
            runOf("a2", tc.rootA, "done", "2026-10-04T00:00:00Z"),
            runOf("a3", tc.rootA, "stopped", "2026-10-03T00:00:00Z")]
  }

  // rootB's base snapshot: b1 done.
  function baseB() { return [runOf("b1", tc.rootB, "done", "2026-10-02T00:00:00Z")] }

  // A snapshotByProject value: rootA lists aRuns, rootB lists bRuns; a null list leaves its root out.
  function snap(aRuns, bRuns) {
    var out = {}
    if (aRuns !== null) out[tc.rootA] = aRuns
    if (bRuns !== null) out[tc.rootB] = bRuns
    return out
  }

  // A store with the snapshot `byProject`, then opened.
  function openHistory(byProject) {
    var s = makeHistory(); if (!s) return null
    s.snapshotByProject = byProject
    s.active = true
    return s
  }

  // One runs-history.py entry: an am runs row whose `status` is the am status object.
  function entryOf(id, root, status, startedAt) {
    return { id: id, repo_dir: root, started_at: startedAt,
             status: { run: { id: id, status: status }, rows: [], stories: [], subtasks: [] } }
  }

  function h1() { return entryOf("h1", tc.rootA, "done", "2026-10-02T00:00:00Z") }
  function h2() { return entryOf("h2", tc.rootA, "stopped", "2026-10-01T00:00:00Z") }
  function h3() { return entryOf("h3", tc.rootA, "done", "2026-09-30T00:00:00Z") }
  function hb1() { return entryOf("hb1", tc.rootB, "done", "2026-10-01T00:00:00Z") }
  function hb2() { return entryOf("hb2", tc.rootB, "done", "2026-09-30T00:00:00Z") }

  // runs-history.py's ok reply; no `more` key when `more` is undefined.
  function pageOk(entries, more) { return JSON.stringify({ ok: true, runs: entries, more: more }) + "\n" }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // root's latest launch answered with `text` and exit code `code`.
  function answer(s, root, text, code) { reply(s.runnerFor(root).current, text, code) }

  // showOlder(root), answered with an ok page of `entries` and `more`.
  function page(s, root, entries, more) {
    s.showOlder(root)
    answer(s, root, pageOk(entries, more), 0)
  }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // The value after --since in a process's argv; "" when there is none.
  function sinceArg(proc) {
    var i = proc.command.indexOf("--since")
    return i < 0 ? "" : proc.command[i + 1]
  }

  // The ids of root's history runs, comma-joined.
  function idsOf(s, root) { return s.historyByProject[root].runs.map(function(r) { return r.id }).join(",") }

  // Store `s` (snapshot snap(baseA(), baseB())) with a first page for each
  // root (rootA [h1], rootB [hb1]) and a second page in flight for each.
  // Returns the two processes in flight.
  function inFlight(s) {
    page(s, tc.rootA, [h1()], true)
    page(s, tc.rootB, [hb1()], true)
    s.showOlder(tc.rootA)
    s.showOlder(tc.rootB)
    return { a: s.runnerFor(tc.rootA).current, b: s.runnerFor(tc.rootB).current }
  }

  // ---- showOlder launches

  function test_show_older_runs_the_helper_with_the_cursor_and_every_terminal_status() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    compare(s.runnerFor(tc.rootA), null, "no runner before the first showOlder")
    s.showOlder(tc.rootA)
    var cmd = argv(s.runnerFor(tc.rootA).current)
    compare(cmd, tc.historyCmd + tc.rootA + "|--before|2026-10-03T00:00:00Z|--status|" + tc.allStatuses)
    verify(cmd.indexOf("--since") < 0, "no --since under all time")
    verify(cmd.indexOf("--limit") < 0, "no --limit")
    var e = s.historyByProject[tc.rootA]
    compare(JSON.stringify(e.runs), "[]")
    compare(e.more, false)
    compare(e.loading, true)
    compare(e.error, "")
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "only the root asked for has an entry")
    compare(s.runnerFor(tc.rootB), null)
  }

  function test_the_status_list_follows_the_chip_and_the_finished_state() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    var head = tc.historyCmd + tc.rootA + "|--before|2026-10-03T00:00:00Z|--status|"
    s.runFilter = "parked"
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "stopped")
    s.runFilter = "attention"
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "escalated")
    s.runFilter = "finished"
    s.finishedState = "cancelled"
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "cancelled,canceled")
    s.finishedState = ""
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current), head + "done,escalated,cancelled,canceled")
  }

  function test_the_live_chip_launches_nothing() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.runFilter = "live"
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null, "a live run is never terminal: no page")
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  function test_since_is_a_week_back_under_week() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.finishedAge = "week"
    var t0 = Date.now()
    s.showOlder(tc.rootA)
    var t1 = Date.now()
    var since = Date.parse(sinceArg(s.runnerFor(tc.rootA).current))
    var week = 7 * 24 * 3600 * 1000
    verify(since >= t0 - week && since <= t1 - week, "since " + since + " not in [" + (t0 - week) + ", " + (t1 - week) + "]")
    verify(argv(s.runnerFor(tc.rootA).current).indexOf("|--status|" + tc.allStatuses + "|--since|") > 0, "--since comes last")
  }

  function test_since_is_local_midnight_under_today() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.finishedAge = "today"
    var m0 = new Date(); m0.setHours(0, 0, 0, 0)
    s.showOlder(tc.rootA)
    var m1 = new Date(); m1.setHours(0, 0, 0, 0)
    var since = sinceArg(s.runnerFor(tc.rootA).current)
    verify(since === m0.toISOString() || since === m1.toISOString(), since)
  }

  // ---- showOlder does nothing

  function test_an_inactive_store_launches_nothing() {
    var s = makeHistory(); if (!s) return
    s.snapshotByProject = snap(baseA(), null)
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null)
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  function test_a_root_the_snapshot_lacks_launches_nothing() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.showOlder(tc.rootB)
    compare(s.runnerFor(tc.rootB), null)
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false)
  }

  function test_a_root_with_no_terminal_run_launches_nothing() {
    var s = openHistory(snap([baseA()[0]], null)); if (!s) return
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null, "no cursor: no page")
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  function test_a_root_with_a_trailing_slash_is_used_as_given() {
    var key = tc.rootA + "/"
    var byProject = {}
    byProject[key] = baseA()
    var s = openHistory(byProject); if (!s) return
    s.showOlder(tc.rootA)
    compare(s.runnerFor(tc.rootA), null, "the root without its slash is not a snapshot root")
    s.showOlder(key)
    compare(argv(s.runnerFor(key).current), tc.historyCmd + key + "|--before|2026-10-03T00:00:00Z|--status|" + tc.allStatuses)
    compare(s.historyByProject[key].loading, true)
    compare(Runs.hasKey(s.historyByProject, tc.rootA), false)
  }

  // ---- a page's reply

  function test_an_ok_page_drops_the_ids_the_snapshot_lists() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [entryOf("a2", tc.rootA, "done", "2026-10-04T00:00:00Z"), h1(), h2()], true)
    var e = s.historyByProject[tc.rootA]
    compare(idsOf(s, tc.rootA), "h1,h2", "a2 is in the snapshot: the snapshot wins")
    compare(e.loading, false)
    compare(e.error, "")
    compare(e.runs[0].project.root, tc.rootA)
    compare(e.runs[0].project.name, "proj", "the name of the root's first snapshot run")
    compare(e.runs[0].status, "done", "the am status, normalized, not [object Object]")
    compare(e.runs[1].status, "stopped")
    compare(e.runs[0].started_at, "2026-10-02T00:00:00Z")
  }

  function test_pages_chain_from_the_oldest_run_listed_so_far() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1(), h2()], true)
    compare(s.historyByProject[tc.rootA].more, true)
    s.showOlder(tc.rootA)
    compare(argv(s.runnerFor(tc.rootA).current),
            tc.historyCmd + tc.rootA + "|--before|2026-10-01T00:00:00Z|--status|" + tc.allStatuses,
            "h2 is the oldest terminal run of the snapshot and the history")
    compare(idsOf(s, tc.rootA), "h1,h2", "a launch keeps the loaded runs")
    compare(s.historyByProject[tc.rootA].more, true, "and `more`")
    compare(s.historyByProject[tc.rootA].loading, true)
    answer(s, tc.rootA, pageOk([h2(), h3()], false), 0)
    compare(idsOf(s, tc.rootA), "h1,h2,h3", "the repeated h2 is not added twice")
    compare(s.historyByProject[tc.rootA].more, false, "exhausted")
    compare(s.historyByProject[tc.rootA].loading, false)
  }

  function test_a_failed_page_keeps_the_rows_and_shows_its_error() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1()], true)
    var replies = [
      [JSON.stringify({ ok: false, error: { type: "AmMissing", message: "am is not installed." } }) + "\n", 1, "AmMissing: am is not installed."],
      ["not json\n", 0, "unknown error"],
      [JSON.stringify({ ok: true, runs: {} }) + "\n", 0, "unknown error"],
      ["", 2, "unknown error"]
    ]
    for (var i = 0; i < replies.length; i++) {
      s.showOlder(tc.rootA)
      compare(s.historyByProject[tc.rootA].error, "", "a launch clears the error, case " + i)
      answer(s, tc.rootA, replies[i][0], replies[i][1])
      var e = s.historyByProject[tc.rootA]
      compare(idsOf(s, tc.rootA), "h1", "the rows stay, case " + i)
      compare(e.more, true, "`more` stays, case " + i)
      compare(e.loading, false, "case " + i)
      compare(e.error, replies[i][2], "case " + i)
    }
    page(s, tc.rootA, [h2()], false)
    compare(s.historyByProject[tc.rootA].error, "", "an ok page clears the error")
    compare(idsOf(s, tc.rootA), "h1,h2")
  }

  function test_a_page_skips_entries_that_are_not_objects_and_repeated_ids() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [null, "h9", [h3()], h1(), h1(), h2()], false)
    compare(idsOf(s, tc.rootA), "h1,h2")
    compare(s.historyByProject[tc.rootA].error, "")
  }

  function test_more_is_true_only_when_the_page_says_so() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1()], undefined)
    compare(s.historyByProject[tc.rootA].more, false, "no `more` key")
    page(s, tc.rootA, [h2()], "yes")
    compare(s.historyByProject[tc.rootA].more, false, "a `more` that is not true")
    page(s, tc.rootA, [h3()], true)
    compare(s.historyByProject[tc.rootA].more, true)
  }

  function test_a_second_show_older_supersedes_the_page_in_flight() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    s.showOlder(tc.rootA)
    var first = s.runnerFor(tc.rootA).current
    s.showOlder(tc.rootA)
    var second = s.runnerFor(tc.rootA).current
    verify(first !== second, "a new process")
    reply(first, pageOk([h1()], true), 0)
    compare(idsOf(s, tc.rootA), "", "the superseded reply changes nothing")
    compare(s.historyByProject[tc.rootA].loading, true)
    reply(second, pageOk([h2()], false), 0)
    compare(idsOf(s, tc.rootA), "h2")
    compare(s.historyByProject[tc.rootA].loading, false)
  }

  function test_roots_page_independently() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    s.showOlder(tc.rootA)
    s.showOlder(tc.rootB)
    compare(s.runnerFor(tc.rootA).busy, true, "rootA's page is not cancelled by rootB's")
    compare(s.runnerFor(tc.rootB).busy, true)
    compare(argv(s.runnerFor(tc.rootB).current), tc.historyCmd + tc.rootB + "|--before|2026-10-02T00:00:00Z|--status|" + tc.allStatuses)
    answer(s, tc.rootB, pageOk([hb1()], false), 0)
    compare(idsOf(s, tc.rootB), "hb1")
    compare(s.historyByProject[tc.rootA].loading, true)
    answer(s, tc.rootA, pageOk([h1()], true), 0)
    compare(idsOf(s, tc.rootA), "h1")
    compare(idsOf(s, tc.rootB), "hb1")
    compare(s.historyByProject[tc.rootB].runs[0].project.root, tc.rootB)
  }

  // ---- snapshot changes

  function test_a_terminal_run_leaving_the_snapshot_moves_into_history() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    page(s, tc.rootA, [h1()], true)
    var spy = spyC.createObject(tc, { target: s, signalName: "historyByProjectChanged" })
    var a0 = runOf("a0", tc.rootA, "started", "2026-10-06T00:00:00Z")
    var base = baseA()
    s.snapshotByProject = snap([a0, base[0], base[1]], baseB())
    compare(idsOf(s, tc.rootA), "a3,h1", "a3 left the window: it moves to the front")
    var e = s.historyByProject[tc.rootA]
    compare(e.runs[0].status, "stopped")
    compare(e.runs[0].project.root, tc.rootA)
    compare(e.more, true, "`more` is kept")
    compare(e.loading, false)
    compare(e.error, "")
    compare(spy.count, 1)
    s.snapshotByProject = snap([a0, base[1]], baseB())
    compare(idsOf(s, tc.rootA), "a3,h1", "the live a1 leaving moves nothing")
    compare(spy.count, 1, "an entry whose runs did not change is not replaced")
    s.snapshotByProject = snap([a0, base[1]], [])
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "rootB has no history: b1 leaving creates no entry")
    compare(spy.count, 1)
  }

  function test_overflow_keeps_the_previous_snapshot_order() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1()], true)
    var base = baseA()
    s.snapshotByProject = snap([base[0]], null)
    compare(idsOf(s, tc.rootA), "a2,a3,h1", "a2 and a3 in their snapshot order, in front")
    s.snapshotByProject = snap([base[0], runOf("h1", tc.rootA, "done", "2026-10-02T00:00:00Z")], null)
    s.snapshotByProject = snap([base[0]], null)
    compare(idsOf(s, tc.rootA), "h1,a2,a3", "h1 came back and left again: moved once, to the front")
  }

  function test_a_history_run_the_snapshot_lists_again_leaves_the_history() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1(), h2()], true)
    s.snapshotByProject = snap(baseA().concat([runOf("h1", tc.rootA, "started", "2026-10-02T00:00:00Z")]), null)
    compare(idsOf(s, tc.rootA), "h2", "h1 was resumed: the snapshot wins")
  }

  function test_a_snapshot_change_never_fetches() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    s.snapshotByProject = snap(baseA().slice(1), baseB())
    compare(s.runnerFor(tc.rootA), null, "no history: no runs-history.py")
    page(s, tc.rootA, [h1()], true)
    var runner = s.runnerFor(tc.rootA)
    var seq = runner.seq
    s.snapshotByProject = snap(baseA().slice(0, 2), [])
    s.snapshotByProject = snap(baseA(), baseB())
    compare(runner.seq, seq, "with history: still no launch")
    compare(runner.busy, false)
    compare(s.runnerFor(tc.rootB), null)
  }

  function test_a_root_leaving_the_snapshot_loses_its_pages() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.snapshotByProject = snap(baseA(), null)
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "rootB left: its entry is gone")
    compare(s.runnerFor(tc.rootB).busy, false, "and its fetch is cancelled")
    compare(s.historyByProject[tc.rootA].loading, true, "rootA keeps its entry and its page in flight")
    reply(procs.b, pageOk([hb2()], false), 0)
    compare(Runs.hasKey(s.historyByProject, tc.rootB), false, "rootB's old reply creates no entry")
    reply(procs.a, pageOk([h2()], false), 0)
    compare(idsOf(s, tc.rootA), "h1,h2", "rootA's reply still lands")
  }

  // ---- dropped pages

  // The processes `procs` (from inFlight) reply after their roots were
  // dropped: no entry comes back.
  function lateRepliesLandNowhere(s, procs) {
    reply(procs.a, pageOk([h2()], false), 0)
    reply(procs.b, pageOk([hb2()], false), 0)
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]", "the dropped roots' old replies create no entry")
  }

  function test_a_changed_age_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.finishedAge = "week"
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    compare(s.runnerFor(tc.rootA).busy, false, "rootA's fetch is cancelled")
    compare(s.runnerFor(tc.rootB).busy, false)
    lateRepliesLandNowhere(s, procs)
  }

  function test_a_changed_finished_state_under_finished_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    s.runFilter = "finished"
    var procs = inFlight(s)
    s.finishedState = "done"
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    lateRepliesLandNowhere(s, procs)
  }

  function test_a_changed_chip_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.runFilter = "parked"
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    lateRepliesLandNowhere(s, procs)
  }

  function test_a_finished_state_change_under_all_drops_nothing() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.finishedState = "done"
    compare(idsOf(s, tc.rootA), "h1", "the All chip's status list did not change")
    compare(idsOf(s, tc.rootB), "hb1")
    compare(s.historyByProject[tc.rootA].loading, true)
    reply(procs.a, pageOk([h2()], false), 0)
    compare(idsOf(s, tc.rootA), "h1,h2", "the page in flight still lands")
  }

  function test_closing_the_panel_drops_every_root() {
    var s = openHistory(snap(baseA(), baseB())); if (!s) return
    var procs = inFlight(s)
    s.active = false
    compare(JSON.stringify(Object.keys(s.historyByProject)), "[]")
    lateRepliesLandNowhere(s, procs)
  }

  function test_show_older_after_a_drop_starts_over_from_the_snapshot() {
    var s = openHistory(snap(baseA(), null)); if (!s) return
    page(s, tc.rootA, [h1(), h2()], true)
    s.finishedAge = "week"
    s.showOlder(tc.rootA)
    var cmd = argv(s.runnerFor(tc.rootA).current)
    compare(cmd.indexOf(tc.historyCmd + tc.rootA + "|--before|2026-10-03T00:00:00Z|--status|" + tc.allStatuses + "|--since|"), 0,
            "the cursor comes from the snapshot alone: " + cmd)
    compare(JSON.stringify(s.historyByProject[tc.rootA].runs), "[]")
    compare(s.historyByProject[tc.rootA].more, false)
  }
}
