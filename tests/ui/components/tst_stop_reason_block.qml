// tests/ui/components/tst_stop_reason_block.qml
// ui/components/StopReasonBlock.qml on its own: the rendered lines for each
// stopped state, am's note, the parked cards, and the Open card / Relaunch
// buttons with their signals and written-out reasons.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components/runGlyphs.js" as RG
import "../../../core/domain/runs.js" as Runs
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "StopReasonBlock"
  when: windowShown
  visible: true
  width: 520; height: 700

  Component { id: blockC; UI.StopReasonBlock { width: 480 } }
  SignalSpy { id: opens; signalName: "openCardRequested" }
  SignalSpy { id: relaunches; signalName: "relaunchRequested" }

  readonly property string card: "5bfe746d-8ac3-41c4-8e3e-abb939e0b45a"
  readonly property string noteAt: "2026-10-04T17:45:00Z"

  // A block with `over` as its props; the spies follow it.
  function make(over) {
    var b = createTemporaryObject(blockC, tc, over || {})
    opens.target = b; relaunches.target = b
    opens.clear(); relaunches.clear()
    wait(30)
    return b
  }
  // A freshly laid-out item is placed on the next frame: wait, so the click
  // lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }
  function part(b, name) { return H.find(b, name) }

  // Pinned literal reports: the fields the block reads, every one given.
  function escalatedReport() {
    return { state: "escalated", headline: "Escalated at verify", cardId: tc.card, storyId: "s1",
             storyTitle: "Dry run of a board", phase: "verify", detail: "VerifyError: could not run none",
             heartbeatAt: "", attempt: { card_id: tc.card, phase: "verify", attempt: 0 }, parked: [], relaunch: null }
  }
  function syntheticReport() {
    return { state: "escalated", headline: "Escalated at Integrate", cardId: "", storyId: "integrate",
             storyTitle: "Integrate", phase: "integrate", detail: "", heartbeatAt: "", attempt: null, parked: [],
             relaunch: null }
  }
  function deadReport() {
    return { state: "dead", headline: "The run's process died", cardId: "7d2c0e11-0000-4000-8000-000000000001",
             storyId: "s1", storyTitle: "Runs screens", phase: "implement", detail: "",
             heartbeatAt: "2026-10-04T17:40:00Z", attempt: null, parked: [], relaunch: null }
  }
  // A normalised run whose subtasks are `stopped` (parked) cards, in `status`.
  function stoppedRun(status, parkedIds) {
    var subtasks = []
    for (var i = 0; i < parkedIds.length; i++) subtasks.push({ card_id: parkedIds[i], status: "stopped", phases: [] })
    return { id: "run-x-stop0001", status: status, milestone_id: "M3", lease: null, rows: [],
             tree: { stories: [], subtasks: subtasks } }
  }
  function note(createdAt, fields) { return { createdAt: createdAt, kind: "escalated", fields: fields } }

  // 1
  function test_an_escalated_subtask_names_its_card_story_and_detail_in_urgent() {
    var b = make({ report: escalatedReport(), heartbeatAge: "5m" })
    compare(b.visible, true)
    compare(b.objectName, "stopReasonBlock")
    compare(part(b, "stopTitle").text, "Why it stopped")
    compare(part(b, "stopTitle").font.bold, true)
    var head = part(b, "stopHeadline")
    compare(head.text, "‼ Escalated at verify · #5bfe746d · story \"Dry run of a board\"")
    compare(head.wrapMode, Text.WordWrap)
    verify(Qt.colorEqual(head.color, b.theme.urgent), "escalated is urgent")
    var detail = part(b, "stopDetail")
    compare(detail.visible, true)
    compare(detail.text, "VerifyError: could not run none")
    compare(detail.wrapMode, Text.WordWrap)
    verify(Qt.colorEqual(detail.color, b.theme.urgent))
    compare(part(b, "stopHeartbeat").visible, false, "only a dead run has a heartbeat line")
    compare(part(b, "stopParked").visible, false)
  }

  // 2
  function test_a_synthetic_escalation_is_its_headline_alone() {
    var b = make({ report: syntheticReport() })
    compare(part(b, "stopHeadline").text, "‼ Escalated at Integrate")
    compare(part(b, "stopHeadline").text.indexOf("#"), -1)
    compare(part(b, "stopDetail").visible, false, "no detail")
  }

  // 3
  function test_a_parked_run_lists_its_parked_cards_in_foreground() {
    var report = Runs.stopReport(stoppedRun("stopped", ["6c1e09aa-1111-4000-8000-000000000001",
                                                        "9f02b7d1-2222-4000-8000-000000000002"]))
    var b = make({ report: report })
    var head = part(b, "stopHeadline")
    compare(head.text, RG.glyphOf("parked") + " Paused at a phase boundary")
    verify(Qt.colorEqual(head.color, b.theme.foreground), "parked is not urgent")
    compare(part(b, "stopParked").visible, true)
    compare(part(b, "stopParked").text, "Parked: #6c1e09aa, #9f02b7d1")
    compare(part(b, "stopDetail").visible, false)
    var odd = Runs.stopReport(stoppedRun("stopped", []))
    odd.parked = [5, null, "", "abc"]
    b.report = odd
    compare(part(b, "stopParked").text, "Parked: #abc", "only non-empty string ids are listed")
  }

  // 4
  function test_a_dead_run_names_its_phase_and_last_heartbeat() {
    var b = make({ report: deadReport(), heartbeatAge: "5m" })
    var head = part(b, "stopHeadline")
    compare(head.text, "✖ The run's process died · #7d2c0e11 · story \"Runs screens\" · at implement")
    verify(Qt.colorEqual(head.color, b.theme.urgent), "dead is urgent")
    compare(part(b, "stopHeartbeat").visible, true)
    compare(part(b, "stopHeartbeat").text, "Last heartbeat 5m ago")
    b.heartbeatAge = ""
    compare(part(b, "stopHeartbeat").visible, false)
  }

  // 5
  function test_a_cancelled_run_says_so_and_lists_what_it_parked() {
    var report = Runs.stopReport(stoppedRun("cancelled", ["6c1e09aa-1111-4000-8000-000000000001"]))
    var b = make({ report: report })
    compare(part(b, "stopHeadline").text, RG.glyphOf("cancelled") + " " + report.headline)
    verify(Qt.colorEqual(part(b, "stopHeadline").color, b.theme.foreground))
    compare(part(b, "stopParked").text, "Parked: #6c1e09aa")
    b.report = Runs.stopReport(stoppedRun("canceled", []))
    compare(part(b, "stopHeadline").text, RG.glyphOf("cancelled") + " " + report.headline, "canceled too")
    compare(part(b, "stopParked").visible, false)
  }

  // 6
  function test_no_report_shows_nothing() {
    var b = make({ report: null })
    compare(b.visible, false)
    b.report = "escalated"
    compare(b.visible, false)
    b.report = { state: "escalated" }
    compare(b.visible, true, "missing fields read as empty")
    compare(part(b, "stopHeadline").text, "‼ ")
  }

  // 7
  function test_ams_note_shows_its_time_and_fields() {
    var b = make({ report: escalatedReport(), note: note(tc.noteAt, [
      { key: "reason", value: "tests do not cover the empty list" },
      { key: "next", value: "am resume 20261004T165007Z-4a51d663" }]) })
    var heading = part(b, "stopNoteHeading")
    compare(heading.visible, true)
    compare(heading.text, "am's note · " + Qt.formatTime(new Date(tc.noteAt), "hh:mm"))
    var f0 = part(b, "stopNoteField0")
    compare(f0.text, "reason  tests do not cover the empty list")
    compare(f0.x, 12, "indented one step")
    compare(f0.wrapMode, Text.WordWrap)
    compare(part(b, "stopNoteField1").text, "next  am resume 20261004T165007Z-4a51d663")
    compare(part(b, "stopNoteField2"), null)
    b.note = note("yesterday", [])
    compare(heading.text, "am's note", "an unparseable time is left out")
    b.note = { createdAt: tc.noteAt, kind: "escalated", fields: "x" }
    compare(heading.visible, true)
    compare(part(b, "stopNoteField0"), null, "non-array fields give no lines")
  }

  // 8
  function test_no_note_hides_the_heading_and_fields() {
    var b = make({ report: escalatedReport(), note: null })
    compare(part(b, "stopNoteHeading").visible, false)
    compare(part(b, "stopNoteField0"), null)
  }

  // 9
  function test_open_card_emits_its_id_only_while_enabled() {
    var b = make({ report: escalatedReport(), openCardId: "" })
    compare(part(b, "stopOpenCard").visible, false)
    compare(part(b, "stopActions").visible, false, "no button, no row")
    b.openCardId = "t1"
    var open = part(b, "stopOpenCard")
    compare(open.visible, true)
    compare(open.text, "Open card")
    compare(open.enabled, true)
    compare(part(b, "stopActionReason").visible, false)
    click(open)
    compare(opens.count, 1)
    compare(opens.signalArguments[0][0], "t1")
    b.openCardReason = "Open this run's project to open its card"
    compare(open.enabled, false)
    compare(open.tooltipText, "Open this run's project to open its card")
    click(open)
    compare(opens.count, 1, "a disabled Open card emits nothing")
    compare(part(b, "stopActionReason").visible, true)
    compare(part(b, "stopActionReason").text, "Open this run's project to open its card")
  }

  // 10
  function test_relaunch_emits_only_while_enabled_and_reasons_are_written_out() {
    var b = make({ report: escalatedReport(), relaunchOffered: false })
    compare(part(b, "stopRelaunch").visible, false)
    b.relaunchOffered = true
    var relaunch = part(b, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.text, "Relaunch")
    compare(relaunch.enabled, true)
    click(relaunch)
    compare(relaunches.count, 1)
    b.relaunchReason = "Open this run's project to relaunch it"
    compare(relaunch.enabled, false)
    click(relaunch)
    compare(relaunches.count, 1, "a disabled Relaunch emits nothing")
    compare(part(b, "stopActionReason").text, "Open this run's project to relaunch it")
    b.openCardId = "t1"
    b.openCardReason = "A"
    b.relaunchReason = "B"
    compare(part(b, "stopActionReason").text, "A · B", "Open card's reason first")
    b.relaunchReason = "A"
    compare(part(b, "stopActionReason").text, "A", "the same reason once")
    b.relaunchOffered = false
    b.relaunchReason = "B"
    compare(part(b, "stopActionReason").text, "A", "a hidden button's reason is not written")
  }

  // 11
  function test_null_inputs_are_quiet() {
    var b = make({ report: deadReport(), heartbeatAge: "5m", openCardId: "t1", relaunchOffered: true,
                   note: note(tc.noteAt, [{ key: "reason", value: "r" }]) })
    b.theme = null
    wait(20)
    compare(part(b, "stopHeadline").text.indexOf("The run's process died") >= 0, true)
    b.report = null
    b.note = null
    wait(20)
    compare(b.visible, false)
    b.destroy()
    wait(20)
  }
}
