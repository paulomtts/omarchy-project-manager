// tests/core/domain/tst_run_row_contract.qml
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

// The Runs row redesign's shared contract (card 6f9f8639): the action
// vocabularies, and the signatures of runLevel, visibleActions,
// controls().close and controlError(error, action). The contract tests run
// against whatever runs.js has, stubs included. Fixture runs are built from
// tests/fixtures/am/ via amRun, as in tst_runs.qml.
TestCase {
  name: "DomainRunRowContract"

  readonly property string reasonIntegrate: "Integrate is running; it cannot be paused or cancelled"
  readonly property string reasonFinished: "The run has finished"
  readonly property string reasonUnknown: "The run's state is unknown"
  readonly property string reasonCancelled: "The run is already cancelled"
  readonly property string reasonRunning: "A running run is cancelled, not closed"

  // The UI's action names, left to right as RR's button table lists them.
  function uiActions() { return ["pause", "resume", "cancel", "close", "relaunch"] }
  // The store's and the backend's action names; also controlError's `action`.
  function storeActions() { return ["pause", "resume", "cancel", "reset"] }
  function levels() { return ["subtask", "story", "milestone"] }

  // One am run as RunStore hands it to normalizeRun, fresh on every call: the
  // fixture's `am runs` row (runs.json's entry with the same run id, else the
  // fixture's own _am_runs_row) without `status`, and the fixture's `am status`
  // data. Copied from tst_runs.qml.
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

  function fixtureRun(name) { return Runs.normalizeRun(amRun(name)) }

  // The status-done.json run, normalized, with am's run status set to spelling.
  // Its control.lease is null, so no Integrate reason interferes.
  function cancelledRun(spelling) {
    var raw = amRun("status-done.json")
    raw.status.run.status = spelling
    return Runs.normalizeRun(raw)
  }

  // A normalised-shape run. live === null means no lease; otherwise the lease's
  // live and accepting flags are as given (accepting !== true is Integrate).
  // workflow is set only when given.
  function runOf(status, live, accepting, workflow) {
    var r = {
      id: "rc", repo_dir: "/r", milestone_id: "m1", status: status,
      lease: live === null ? null : { pid: 1, host: "h", heartbeat_at: "", accepting: accepting, live: live },
      rows: [], tree: { stories: [], subtasks: [] }
    }
    if (workflow !== undefined) r.workflow = workflow
    return r
  }

  // [label, run, close reason ("" = enabled), visibleActions joined with ","]:
  // the spec's controls(run).close / visibleActions table, one row per state,
  // lease and Integrate case, plus a normalised fixture run per state the
  // fixtures provide.
  function rowTable() {
    return [
      ["running", runOf("started", true, true), reasonRunning, "cancel,pause"],
      ["running, Integrate", runOf("started", true, false), reasonRunning, ""],
      ["parked", runOf("stopped", false, true), "", "close,resume"],
      ["parked, no lease", runOf("stopped", null, false), "", "close,resume"],
      ["parked, Integrate", runOf("stopped", false, false), reasonIntegrate, "resume"],
      ["escalated", runOf("escalated", false, true), "", "close,relaunch"],
      ["escalated, no lease", runOf("escalated", null, false), "", "close,relaunch"],
      ["escalated, Integrate", runOf("escalated", false, false), reasonIntegrate, "relaunch"],
      ["escalated card run", runOf("escalated", false, true, "task"), "", "close,relaunch"],
      ["escalated card run, padded", runOf("escalated", false, true, "  task  "), "", "close,relaunch"],
      ["escalated card run, tab and newline", runOf("escalated", false, true, "\ttask\n"), "", "close,relaunch"],
      ["dead", runOf("started", false, true), "", "close,relaunch"],
      ["dead, no lease", runOf("started", null, false), "", "close,relaunch"],
      ["dead, Integrate", runOf("started", false, false), reasonIntegrate, "relaunch"],
      ["done", runOf("done", false, true), reasonFinished, ""],
      ["done, Integrate", runOf("done", false, false), reasonFinished, ""],
      ["done, live, Integrate", runOf("done", true, false), reasonFinished, ""],
      ["done, no lease", runOf("done", null, true), reasonFinished, ""],
      ["cancelled", runOf("cancelled", false, true), reasonCancelled, ""],
      ["cancelled, Integrate", runOf("cancelled", false, false), reasonCancelled, ""],
      ["canceled, no lease", runOf("canceled", null, true), reasonCancelled, ""],
      ["canceled, live, Integrate", runOf("canceled", true, false), reasonCancelled, ""],
      ["unknown, empty status", runOf("", true, true), reasonUnknown, ""],
      ["unknown, weird, Integrate", runOf("weird", true, false), reasonUnknown, ""],
      ["unknown, STARTED", runOf("STARTED", true, true), reasonUnknown, ""],
      ["unknown, undefined", undefined, reasonUnknown, ""],
      ["unknown, null", null, reasonUnknown, ""],
      ["unknown, 5", 5, reasonUnknown, ""],
      ["unknown, x", "x", reasonUnknown, ""],
      ["unknown, {}", {}, reasonUnknown, ""],
      ["unknown, []", [], reasonUnknown, ""],
      ["unknown, prototype-less", Object.create(null), reasonUnknown, ""],
      ["fixture started", fixtureRun("status-started.json"), reasonRunning, "cancel,pause"],
      ["fixture done", fixtureRun("status-done.json"), reasonFinished, ""],
      ["fixture done-integrate", fixtureRun("status-done-integrate.json"), reasonFinished, ""],
      ["fixture escalated", fixtureRun("status-escalated.json"), "", "close,relaunch"],
      ["fixture escalated-integrate", fixtureRun("status-escalated-integrate.json"), "", "close,relaunch"],
      ["fixture cancelled", cancelledRun("cancelled"), reasonCancelled, ""],
      ["fixture canceled", cancelledRun("canceled"), reasonCancelled, ""]
    ]
  }

  // [label, run]: inputs no caller should send, which must still give a value
  // of the stated type without throwing.
  function garbageRuns() {
    return [
      ["undefined", undefined], ["null", null], ["5", 5], ["x", "x"], ["true", true], ["{}", {}], ["[]", []],
      ["prototype-less", Object.create(null)],
      ["object workflow", { workflow: {} }],
      ["object story_id", { story_id: {} }],
      ["prototype-less workflow", { workflow: Object.create(null) }],
      ["prototype-less story_id", { story_id: Object.create(null) }],
      ["__proto__ workflow", { workflow: "__proto__" }],
      ["constructor story_id", { story_id: "constructor" }],
      ["normalised garbage", Runs.normalizeRun(undefined)],
      ["fixture run", fixtureRun("status-started.json")]
    ]
  }

  // [label, run] for every row of rowTable() and every garbage run.
  function allRuns() {
    var out = []
    var table = rowTable()
    for (var i = 0; i < table.length; i++) out.push([table[i][0], table[i][1]])
    var garbage = garbageRuns()
    for (var j = 0; j < garbage.length; j++) out.push(["garbage " + garbage[j][0], garbage[j][1]])
    return out
  }

  // [type, sentence] for every am control error controlError knows today.
  // Copied from tst_runs.qml.
  function controlErrorTable() {
    return [
      ["UnknownRunError", "The run no longer exists"],
      ["NotRunningError", "The run is not running"],
      ["DeadRunError", "The run's process has died, so nobody can act on this request. Resume picks the run up."],
      ["NotAcceptingError", reasonIntegrate],
      ["RunIsLiveError", "Another am process is still driving this run. Wait for it to stop, or pause it; resume only takes over a run whose process died."],
      ["NotResumableError", "am cannot resume this run (cancelled, finished, or an escalated card run). Relaunch starts a new run of the same work."],
      ["CheckpointMismatchError", "The workflow changed since this run saved its progress, so it cannot be resumed. Relaunch starts those cards again from their first phase."],
      ["ClaimedError", "Another run has already claimed this work"],
      ["LockTimeoutError", "am is busy; try again in a moment"]
    ]
  }

  // ---- Contract tests: always on --------------------------------------------------------

  function test_contract_run_level_signature() {
    compare(typeof Runs.runLevel, "function")
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var level = Runs.runLevel(runs[i][1])
      verify(levels().indexOf(level) >= 0, runs[i][0] + ": a level, got " + level)
    }
  }

  function test_contract_visible_actions_signature() {
    compare(typeof Runs.visibleActions, "function")
    var ui = uiActions()
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var label = runs[i][0], run = runs[i][1]
      var a = Runs.visibleActions(run)
      var b = Runs.visibleActions(run)
      verify(Array.isArray(a), label + ": an array")
      verify(a !== b, label + ": a fresh array per call")
      var seen = []
      for (var j = 0; j < a.length; j++) {
        verify(ui.indexOf(a[j]) >= 0, label + ": " + a[j] + " is a UI action")
        verify(seen.indexOf(a[j]) < 0, label + ": " + a[j] + " appears once")
        seen.push(a[j])
      }
      a.push("pause")
      a.push("bogus")
      compare(Runs.visibleActions(run).join(","), b.join(","), label + ": unchanged after pushing onto an earlier result")
    }
  }

  function test_contract_controls_close_present() {
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var label = runs[i][0], run = runs[i][1]
      var a = Runs.controls(run)
      var b = Runs.controls(run)
      compare(Object.keys(a).sort().join(","), "cancel,close,pause,resume", label + ": keys")
      compare(Object.keys(a.close).sort().join(","), "enabled,reason", label + ": close keys")
      compare(typeof a.close.reason, "string", label + ": close reason is a string")
      compare(a.close.enabled, a.close.reason === "", label + ": close enabled iff no reason")
      verify(a.close !== b.close, label + ": a fresh close per call")
      verify(a.close !== a.pause && a.close !== a.resume && a.close !== a.cancel, label + ": close not shared")
      var before = b.close.reason
      a.close.reason = "changed"
      a.close.enabled = !a.close.enabled
      compare(Runs.controls(run).close.reason, before, label + ": close unchanged after mutating an earlier result")
    }
  }

  function test_contract_control_error_action_arg() {
    var errors = []
    var table = controlErrorTable()
    compare(table.length, 9)
    for (var i = 0; i < table.length; i++) {
      errors.push(["envelope " + table[i][0], { ok: false, error: { type: table[i][0], message: "am said so" } }])
      errors.push(["bare " + table[i][0], { type: table[i][0] }])
    }
    errors.push(["unknown type", { ok: false, error: { type: "Foo", message: "bar" } }])
    errors.push(["ok:true", { ok: true }])
    errors.push(["undefined", undefined])
    errors.push(["null", null])
    errors.push(["x", "x"])
    var actions = [undefined, "pause", "resume", "cancel", "close", 5, null, {}, "__proto__", "constructor"]
    for (var j = 0; j < errors.length; j++) {
      var one = Runs.controlError(errors[j][1])
      compare(typeof one, "string", errors[j][0] + ": a string")
      for (var k = 0; k < actions.length; k++)
        compare(Runs.controlError(errors[j][1], actions[k]), one, errors[j][0] + ", action " + k)
    }
  }

  function test_contract_action_vocabulary() {
    var ui = uiActions(), store = storeActions()
    compare(ui.join(","), "pause,resume,cancel,close,relaunch", "UI vocabulary")
    compare(store.join(","), "pause,resume,cancel,reset", "store and backend vocabulary")
    verify(ui.indexOf("reset") < 0, "the UI never says reset")
    verify(store.indexOf("close") < 0 && store.indexOf("relaunch") < 0, "the store never says close or relaunch")
    var runs = allRuns()
    for (var i = 0; i < runs.length; i++) {
      var label = runs[i][0], run = runs[i][1]
      var shown = Runs.visibleActions(run)
      for (var j = 0; j < shown.length; j++)
        verify(ui.indexOf(shown[j]) >= 0, label + ": visible " + shown[j] + " is a UI action")
      var keys = Object.keys(Runs.controls(run))
      for (var k = 0; k < keys.length; k++) {
        verify(ui.indexOf(keys[k]) >= 0, label + ": controls key " + keys[k] + " is a UI action")
        verify(keys[k] !== "relaunch", label + ": relaunch has no controls() entry")
      }
    }
  }
}
