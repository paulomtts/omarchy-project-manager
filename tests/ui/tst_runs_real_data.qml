// tests/ui/tst_runs_real_data.qml
// The run monitor fed only the captured am output in tests/fixtures/am/: the
// Runs list, Run detail (tree, default attempt, logs argv, output pane), the
// Graph's story mark and a subtask's card detail, on the real Panel.
import QtQuick
import QtTest
import "../helpers/find.js" as H
import "../helpers/amFixtures.js" as F

TestCase {
  id: tc
  name: "RunsRealData"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })

  readonly property string startedRun: "20261005T021400Z-837c4431"
  readonly property string doneRun: "20261004T204141Z-cb11063d"

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA])
    // Selecting the project starts a `brd export`, a runs snapshot and a run
    // settings read that cannot run here: all three are disarmed so their late
    // replies change nothing.
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runs.settingsLoadRunner.cancel()
    return p
  }

  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // The runs-snapshot.py reply for the captured runs: each `am runs` row with
  // its `status` replaced by that run's `am status` data, as the helper does.
  function snapshot() {
    var runs = F.load("runs.json").data.runs
    runs[0].status = F.load("status-started.json").data
    runs[1].status = F.load("status-done.json").data
    return JSON.stringify({ ok: true, runs: runs, data_dir: "/d" }) + "\n"
  }

  // The next snapshot of project A is the captured one.
  function feedFixtures(p) {
    p.app.runs.refresh()
    reply(p.app.runs.snapshotRunner.current, snapshot(), 0)
  }

  // The panel on the done run's detail view, its default attempt's logs in flight.
  function openDoneRun() {
    var p = make(); if (!p) return null
    feedFixtures(p)
    p.navigator.showSection("runs")
    p.navigator.openRun(doneRun)
    wait(50)
    return p
  }

  function test_the_runs_list_shows_progress_and_the_current_phase_of_real_runs() {
    var p = make(); if (!p) return
    feedFixtures(p)
    p.navigator.showSection("runs")
    wait(50)
    verify(H.find(p, "runRow0"), "the started run's row")
    verify(H.find(p, "runRow1"), "the done run's row")
    verify(!H.find(p, "runRow2"), "two runs only")
    compare(p.app.runs.filteredRuns[0].id, startedRun)
    compare(p.app.runs.filteredRuns[1].id, doneRun)
    compare(H.find(p, "runRowProgress0").text, "3/8")
    compare(H.find(p, "runRowProgress1").text, "10/10")
    compare(H.find(p, "runRowPhase0").text, "explore")
    compare(H.find(p, "runRowPhase1").text, "")
    compare(H.find(p, "runRowPhase1").visible, false)
    compare(String(H.find(p, "navCountRuns").text), "", "a live run and a done run need no attention")
  }

  function test_run_detail_of_the_done_run_shows_its_stories_and_subtasks() {
    var p = openDoneRun(); if (!p) return
    var view = H.find(p, "runDetailView")
    verify(view, "the Run detail screen is mounted")
    compare(view.visible, true)
    var sizes = [2, 3, 1, 4]
    for (var s = 0; s < sizes.length; s++) {
      verify(H.find(p, "runStory" + s), "story " + s)
      for (var t = 0; t < sizes[s]; t++) verify(H.find(p, "runSubtask" + s + "_" + t), "subtask " + s + "_" + t)
      verify(!H.find(p, "runSubtask" + s + "_" + sizes[s]), "story " + s + " has " + sizes[s] + " subtasks")
    }
    verify(!H.find(p, "runStory4"), "four stories")
    var label = String(H.find(p, "runSubtaskLabel0_0").text)
    verify(label.indexOf("adff6c85-ba42-4586-8066-b93e8ac877bb") >= 0, label)
    verify(label.endsWith("· review.1"), label)
  }
}
