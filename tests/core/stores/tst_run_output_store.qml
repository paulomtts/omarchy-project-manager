// tests/core/stores/tst_run_output_store.qml
// Run detail's live output store: when runs-logs-follow.py starts and stops
// for the selected attempt or step, its exact argv, how its stdout lines fold
// into the live buffer, the end line, an error line, an exit with no end, and
// latest wins. Built directly and driven through stubbed Process objects.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "StoresRunOutputStore"

  // status-started.json: its run, its repo_dir (runs.json's first row), its
  // open subtask (worktree step done, explore attempt 1 started) and a done
  // subtask (spec attempt 1 ok).
  readonly property string runId: "20261008T143823Z-e795ad19"
  readonly property string repo: "/home/user/Code/omarchy-project-manager"
  readonly property string openCard: "2280a6ab-9c40-434b-9729-63fd1f373754"
  readonly property string doneCard: "5560d0fe-2b8e-4ef9-ad71-96b50ee89daa"
  readonly property string followCmd: "python3|/plugin/core/backend/runs/runs-logs-follow.py|" + repo + "|"
  readonly property string chunkLine: '{"offset":0,"text":"stub claude ok phase=review\\n"}'

  Component { id: spyC; SignalSpy {} }

  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunOutputStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // One am run as RunStore hands it to normalizeRun, fresh on every call:
  // runs.json's row with the fixture's run id, without `status`, and the
  // fixture's `am status` data.
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

  function rawSubtask(raw, cardId) {
    var stories = raw.status.stories
    for (var i = 0; i < stories.length; i++) {
      for (var j = 0; j < stories[i].subtasks.length; j++) {
        if (stories[i].subtasks[j].card_id === cardId) return stories[i].subtasks[j]
      }
    }
    return null
  }

  // The started capture, normalized: explore.1 is live.
  function startedRun() { return Runs.normalizeRun(amRun("status-started.json")) }

  // The started capture with a deterministic `verify` phase started on
  // openCard; explore.1 stays started unless `exploreDone`.
  function stepRun(exploreDone) {
    var raw = amRun("status-started.json")
    var subtask = rawSubtask(raw, tc.openCard)
    // synthetic: a deterministic phase in flight -- no capture has one
    if (exploreDone) {
      subtask.phases[1].status = "done"
      subtask.phases[1].attempts[0].status = "ok"
    }
    subtask.phases.push({ name: "verify", kind: "deterministic", status: "started", started_at: "",
                          ended_at: null, detail: null, attempts: [] })
    return Runs.normalizeRun(raw)
  }

  // The started capture with explore.1 finished `ok` (its phase done).
  function exploreOkRun() {
    var raw = amRun("status-started.json")
    var subtask = rawSubtask(raw, tc.openCard)
    // synthetic: explore.1 finished
    subtask.phases[1].status = "done"
    subtask.phases[1].attempts[0].status = "ok"
    return Runs.normalizeRun(raw)
  }

  // The started capture under another run id; explore.1 is `status` there.
  function otherRun(id, status) {
    var raw = amRun("status-started.json")
    // synthetic: another running run
    raw.row.id = id
    raw.status.run.id = id
    rawSubtask(raw, tc.openCard).phases[1].attempts[0].status = status
    return Runs.normalizeRun(raw)
  }

  function explore() { return { card_id: tc.openCard, phase: "explore", attempt: 1 } }
  function verifyStep() { return { card_id: tc.openCard, phase: "verify", attempt: 0, step: true } }

  // The raw non-empty lines of tests/fixtures/am/<name>, as strings.
  function streamLines(name) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../../fixtures/am/" + name), false)
    xhr.send()
    return xhr.responseText.split("\n").filter(function(r) { return r !== "" })
  }

  function argv(proc) { return proc.command.join("|") }
  function send(proc, line) { proc.stdout.read(line) }

  // A store on Run detail with the panel open, following `sel` (explore.1 by
  // default) of `run` (the started capture by default).
  function following(run, sel) {
    var store = make(); if (!store) return null
    store.run = run || startedRun()
    store.selection = sel || explore()
    store.active = true
    store.inRunDetail = true
    return store
  }

  // Every follow process the store holds, in order, recorded on followProcChanged.
  function recorder(store) {
    var seen = []
    store.followProcChanged.connect(function() { if (store.followProc) seen.push(store.followProc) })
    return seen
  }

  function runningCount(procs) {
    return procs.filter(function(p) { return p.running === true }).length
  }

  // T1
  function test_defaults() {
    var store = make(); if (!store) return
    compare(store.followKey, null)
    compare(store.followStatus, "idle")
    compare(store.endStatus, "")
    compare(store.liveText, "")
    compare(store.liveDropped, 0)
    compare(store.hasOutput, false)
    compare(store.followError, "")
    compare(store.followProc, null)
  }

  // T2
  function test_starts_on_a_live_agent_attempt() {
    var store = following(); if (!store) return
    var proc = store.followProc
    verify(proc, "a follow process")
    compare(proc.objectName, "followProc")
    compare(proc.running, true)
    compare(proc.command.length, 7, "no OFFSET")
    compare(argv(proc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(JSON.stringify(store.followKey),
            JSON.stringify({ run_id: tc.runId, card_id: tc.openCard, phase: "explore", attempt: 1 }))
    compare(store.followStatus, "connecting")
  }

  // T3
  function test_starts_on_a_live_step_with_attempt_0() {
    var store = following(stepRun(true), verifyStep()); if (!store) return
    var proc = store.followProc
    verify(proc, "a follow process")
    compare(proc.command.length, 7)
    compare(argv(proc), tc.followCmd + tc.runId + "|" + tc.openCard + "|verify|0")
    compare(store.followKey.attempt, 0)
    compare(store.followStatus, "connecting")
  }

  // T4
  function test_no_start_without_presence_or_a_live_selection() {
    var noRepo = amRun("status-started.json")
    // synthetic: a run with no repo_dir anywhere
    noRepo.row.repo_dir = ""
    noRepo.status.run.repo_dir = ""
    var cases = [
      ["not active", startedRun(), explore(), false, true],
      ["not in Run detail", startedRun(), explore(), true, false],
      ["a done step", startedRun(), { card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }, true, true],
      ["a finished attempt", startedRun(), { card_id: tc.doneCard, phase: "spec", attempt: 1 }, true, true],
      ["no selection", startedRun(), null, true, true],
      ["no run", null, explore(), true, true],
      ["no repo_dir", Runs.normalizeRun(noRepo), explore(), true, true]
    ]
    for (var i = 0; i < cases.length; i++) {
      var store = make(); if (!store) return
      store.run = cases[i][1]
      store.selection = cases[i][2]
      store.active = cases[i][3]
      store.inRunDetail = cases[i][4]
      compare(store.followProc, null, cases[i][0])
      compare(store.followStatus, "idle", cases[i][0])
    }
  }

  // Review Focus 5
  function test_malformed_inputs_start_nothing() {
    var runs = [startedRun(), "run", [], { id: "" }, { id: 7, repo_dir: tc.repo }]
    var sels = [explore(), { card_id: "", phase: "explore", attempt: 1 }, { card_id: tc.openCard, phase: 7, attempt: 1 },
                { card_id: tc.openCard, phase: "explore", attempt: "1" }, "explore", [explore()]]
    for (var i = 0; i < runs.length; i++) {
      for (var j = 0; j < sels.length; j++) {
        if (i === 0 && j === 0) continue
        var store = make(); if (!store) return
        store.active = true
        store.inRunDetail = true
        store.run = runs[i]
        store.selection = sels[j]
        compare(store.followProc, null, "run " + i + ", selection " + j)
        compare(store.followStatus, "idle", "run " + i + ", selection " + j)
      }
    }
  }
}
