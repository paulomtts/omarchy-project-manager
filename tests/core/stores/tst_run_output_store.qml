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
  // T5
  function test_lines_fold_into_the_live_text() {
    var store = following(); if (!store) return
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    send(proc, lines[0])
    compare(store.followStatus, "following", "the hello")
    compare(store.hasOutput, false)
    compare(store.liveText, "")
    send(proc, lines[1])
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.hasOutput, true)
    compare(store.liveDropped, 0)
    compare(store.followStatus, "following")
    send(proc, "")
    send(proc, "   ")
    send(proc, "not json")
    compare(store.liveText, "stub claude ok phase=review", "blank and unparseable lines change nothing")
    compare(store.followStatus, "following")
    compare(store.followError, "")
  }

  // T7
  function test_a_non_live_selection_stops_and_clears() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, tc.chunkLine)
    store.selection = { card_id: tc.openCard, phase: "worktree", attempt: 0, step: true }
    compare(old.running, false)
    compare(store.followProc, null)
    compare(store.followKey, null)
    compare(store.liveText, "")
    compare(store.hasOutput, false)
    compare(store.followStatus, "idle")
    compare(seen.length, 0, "no new process")
  }

  // T8
  function test_another_run_or_none_stops_and_clears() {
    var store = following(); if (!store) return
    var old = store.followProc
    send(old, tc.chunkLine)
    store.run = otherRun("20261009T000000Z-0th3r000", "ok")
    compare(old.running, false)
    compare(store.followProc, null)
    compare(store.followKey, null)
    compare(store.liveText, "")
    compare(store.followStatus, "idle")
    store.selection = null
    compare(store.followProc, null)
    compare(store.followKey, null)

    var again = following(); if (!again) return
    var proc = again.followProc
    send(proc, tc.chunkLine)
    again.run = null
    compare(proc.running, false)
    compare(again.followProc, null)
    compare(again.followKey, null)
    compare(again.liveText, "")
    compare(again.followStatus, "idle")
  }

  // T9
  function test_latest_wins_the_older_process_is_ignored() {
    var store = following(stepRun(false), explore()); if (!store) return
    var a = store.followProc
    verify(a, "process A follows explore.1")
    store.selection = verifyStep()
    var b = store.followProc
    compare(a.running, false, "A is stopped")
    verify(b && b !== a, "B is the current one")
    compare(argv(b), tc.followCmd + tc.runId + "|" + tc.openCard + "|verify|0")
    send(a, tc.chunkLine)
    compare(store.liveText, "", "A's late line is dropped")
    compare(store.followStatus, "connecting")
    a.exited(0)
    compare(store.followProc, b, "A's late exit does not null out B")
    compare(store.followStatus, "connecting")
    compare(store.followError, "")
    var lines = streamLines("logs-follow-step.jsonl")
    send(b, lines[0])
    send(b, lines[1])
    compare(store.liveText, "==> verify-ok (exit 0)\nverified")
    compare(store.followStatus, "following")
  }

  // T11
  function test_a_new_snapshot_of_the_same_key_does_not_restart() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    store.run = startedRun()
    compare(store.followProc, proc)
    compare(proc.running, true)
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.followStatus, "following")
  }

  // T12
  function test_the_end_of_an_agent_attempt_keeps_the_buffer() {
    var store = following(); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    for (var i = 0; i < lines.length; i++) send(proc, lines[i])
    compare(store.followStatus, "ended")
    compare(store.endStatus, "ok")
    compare(store.liveText, "stub claude ok phase=review")
    compare(spy.count, 0, "an agent attempt asks for no snapshot")
    send(proc, '{"offset":28,"text":"late\\n"}')
    compare(store.liveText, "stub claude ok phase=review", "a line after the end is ignored")
    proc.exited(0)
    compare(store.followStatus, "ended")
    compare(store.followError, "")
    compare(store.followProc, null)
    store.run = exploreOkRun()
    compare(store.followStatus, "ended", "a snapshot where it finished keeps the ended state")
    compare(store.endStatus, "ok")
    compare(store.liveText, "stub claude ok phase=review")
    compare(store.followProc, null, "nothing starts")
  }

  // T13
  function test_the_end_of_a_step_asks_for_one_snapshot() {
    var store = following(stepRun(true), verifyStep()); if (!store) return
    var spy = createTemporaryObject(spyC, tc, { target: store, signalName: "snapshotWanted" })
    var proc = store.followProc
    var lines = streamLines("logs-follow-step.jsonl")
    for (var i = 0; i < lines.length; i++) send(proc, lines[i])
    compare(store.followStatus, "ended")
    compare(store.endStatus, "ok")
    compare(store.liveText, "==> verify-ok (exit 0)\nverified")
    compare(spy.count, 1)
    send(proc, lines[2])
    compare(spy.count, 1, "a repeated end line asks again for nothing")
    proc.exited(0)
    compare(spy.count, 1, "nor does the exit")
    compare(store.followStatus, "ended")
  }

  // T14
  function test_an_end_without_a_string_status() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, streamLines("logs-follow-agent.jsonl")[0])
    // synthetic: an end line with no status
    send(proc, '{"event":"end"}')
    compare(store.followStatus, "ended")
    compare(store.endStatus, "")
  }

  // T15
  function test_an_error_line() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    var envelope = F.load("logs-follow-refusal.json")
    send(proc, JSON.stringify(envelope))
    compare(store.followStatus, "error")
    compare(store.followError, Runs.errorText(envelope))
    compare(store.liveText, "stub claude ok phase=review", "the buffer stays")
    proc.exited(0)
    compare(store.followStatus, "error")
    compare(store.followError, Runs.errorText(envelope), "the exit after it changes nothing")
    compare(store.followProc, null)
  }

  // T16
  function test_an_exit_with_no_end_line() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    proc.exited(0)
    compare(store.followStatus, "error")
    compare(store.followError, "Live output stopped: the helper exited with code 0")
    compare(store.followProc, null)
    compare(store.liveText, "stub claude ok phase=review")
  }

  // Review Focus 1
  function test_an_equal_selection_object_does_not_restart() {
    var store = following(); if (!store) return
    var proc = store.followProc
    send(proc, tc.chunkLine)
    store.selection = explore()
    compare(store.followProc, proc)
    compare(proc.running, true)
    compare(store.liveText, "stub claude ok phase=review")
  }

  // Review Focus 2
  function test_a_key_that_stops_being_live_keeps_its_process() {
    var store = following(); if (!store) return
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    send(proc, lines[0])
    send(proc, lines[1])
    store.run = exploreOkRun()
    compare(store.followProc, proc, "the process stays for the end line")
    compare(proc.running, true)
    send(proc, lines[2])
    compare(store.followStatus, "ended")
    compare(store.endStatus, "ok")
    compare(store.liveText, "stub claude ok phase=review")
  }

  // Review Focus 4
  function test_a_new_run_with_the_old_selection_then_its_own() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var a = store.followProc
    var other = "20261009T000000Z-0th3r000"
    store.run = otherRun(other, "started")
    compare(a.running, false, "the old run's process stops")
    compare(runningCount(seen), 1, "the old selection is live in the new run too")
    compare(store.followKey.run_id, other)
    compare(argv(store.followProc), tc.followCmd + other + "|" + tc.openCard + "|explore|1")
    var b = store.followProc
    store.selection = null
    compare(b.running, false)
    compare(store.followProc, null)
    compare(store.followKey, null)
    send(a, tc.chunkLine)
    send(b, tc.chunkLine)
    compare(store.liveText, "", "neither stopped process folds")
  }
  // T6
  function test_leaving_run_detail_stops_and_keeps_then_returning_restarts() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    var key = JSON.stringify(store.followKey)
    store.inRunDetail = false
    compare(old.running, false, "SIGTERM")
    compare(store.followProc, null)
    compare(JSON.stringify(store.followKey), key, "the key stays")
    compare(store.liveText, "stub claude ok phase=review", "the buffer stays")
    compare(store.followStatus, "following")
    store.inRunDetail = true
    compare(seen.length, 1, "exactly one new process")
    verify(store.followProc !== old)
    compare(store.followProc.running, true)
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(store.followStatus, "connecting")
  }

  // T6
  function test_closing_the_panel_stops_and_keeps_then_reopening_restarts() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    var key = JSON.stringify(store.followKey)
    store.active = false
    compare(old.running, false, "SIGTERM")
    compare(store.followProc, null)
    compare(JSON.stringify(store.followKey), key, "the key stays")
    compare(store.liveText, "stub claude ok phase=review", "the buffer stays")
    compare(store.followStatus, "following")
    store.active = true
    compare(seen.length, 1, "exactly one new process")
    verify(store.followProc !== old)
    compare(store.followProc.running, true)
    compare(argv(store.followProc), tc.followCmd + tc.runId + "|" + tc.openCard + "|explore|1")
    compare(store.followStatus, "connecting")
  }

  // B2 step 5: back on the same key after it stopped being live off Run detail
  function test_returning_to_a_key_that_is_no_longer_live_clears() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var old = store.followProc
    send(old, streamLines("logs-follow-agent.jsonl")[0])
    send(old, tc.chunkLine)
    store.inRunDetail = false
    store.run = exploreOkRun()
    compare(store.liveText, "stub claude ok phase=review", "off Run detail the buffer stays")
    compare(store.followStatus, "following")
    store.inRunDetail = true
    compare(seen.length, 0, "nothing starts")
    compare(store.followProc, null)
    compare(store.followKey, null)
    compare(store.liveText, "")
    compare(store.hasOutput, false)
    compare(store.followStatus, "idle")
  }

  // T10
  function test_at_most_one_follow_process_runs() {
    var store = make(); if (!store) return
    var seen = recorder(store)
    store.run = stepRun(false)
    store.selection = explore()
    store.active = true
    store.inRunDetail = true
    compare(runningCount(seen), 1, "A")
    store.selection = verifyStep()
    compare(runningCount(seen), 1, "B replaces A")
    store.inRunDetail = false
    compare(runningCount(seen), 0, "left Run detail")
    store.inRunDetail = true
    compare(runningCount(seen), 1, "back on Run detail")
    store.selection = explore()
    compare(runningCount(seen), 1, "back to explore.1")
    store.active = false
    compare(runningCount(seen), 0, "panel closed")
    store.active = true
    compare(runningCount(seen), 1, "panel open")
    compare(seen.length, 5)
    for (var i = 0; i < seen.length; i++) compare(seen[i].objectName, "followProc")
  }

  // Review Focus 3
  function test_an_ended_or_failed_follow_survives_leave_and_return() {
    var store = following(); if (!store) return
    var seen = recorder(store)
    var proc = store.followProc
    var lines = streamLines("logs-follow-agent.jsonl")
    for (var i = 0; i < lines.length; i++) send(proc, lines[i])
    store.active = false
    store.active = true
    compare(seen.length, 0, "an ended follow does not restart")
    compare(store.followStatus, "ended")
    compare(store.liveText, "stub claude ok phase=review")

    var failed = following(); if (!failed) return
    var seen2 = recorder(failed)
    var p2 = failed.followProc
    send(p2, tc.chunkLine)
    p2.exited(0)
    failed.inRunDetail = false
    failed.inRunDetail = true
    compare(seen2.length, 0, "a failed follow does not restart")
    compare(failed.followStatus, "error")
    compare(failed.liveText, "stub claude ok phase=review")
  }
}
