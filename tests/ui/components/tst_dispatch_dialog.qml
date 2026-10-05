import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components" as UI

TestCase {
  id: tc
  name: "DispatchDialog"
  when: windowShown
  visible: true
  width: 640; height: 700

  // Not `states`: TestCase is an Item, and Item already has one.
  readonly property var dispatchStates: ["idle", "previewing", "ready", "refused", "starting", "started", "failed"]

  Component { id: dialogC; UI.DispatchDialog { width: 640; height: 700 } }
  SignalSpy { id: edits; signalName: "fieldEdited" }
  SignalSpy { id: starts; signalName: "startRequested" }
  SignalSpy { id: cancels; signalName: "cancelRequested" }

  function milestoneForm(over) {
    return Object.assign({ base: "main", prefix: "m3", verify: ["uv run pytest"], parallelism: 4,
                           allowNoVerification: false }, over || {})
  }
  // The spec's milestone dialog, ready to start; `over` replaces any prop.
  function milestone(over) {
    return Object.assign({
      dispatchState: "ready",
      target: { level: "milestone", offered: true, reason: "", suggest: null },
      targetTitle: "Document milestone runs",
      form: milestoneForm(),
      preview: { board: false, summary: "2 levels · 5 subtasks · 3 stories already done",
                 integrate: "Integrate → m3-integrate" }
    }, over || {})
  }
  function make(over) {
    var d = createTemporaryObject(dialogC, tc, milestone(over))
    edits.target = d; starts.target = d; cancels.target = d
    edits.clear(); starts.clear(); cancels.clear()
    d.shown = true
    wait(30)
    return d
  }
  // A form that just appeared is laid out on the next frame: wait for it, so
  // the click lands on the item and not where it was.
  function click(item) { wait(30); mouseClick(item, item.width / 2, item.height / 2) }

  // ---- shell ------------------------------------------------------------

  function test_it_is_hidden_until_shown_and_heads_the_card() {
    var d = createTemporaryObject(dialogC, tc)
    compare(d.visible, false)
    d.shown = true
    compare(d.visible, true)
    verify(H.find(d, "dispatchCard"), "the modal card")
    verify(H.find(d, "dispatchBackdrop"), "the backdrop")
    compare(H.find(d, "dispatchHeading").text, "Dispatch")
    compare(d.dispatchState, "idle")
    compare(d.state, "", "dispatchState never shadows Item.state")
  }

  // ---- the target line --------------------------------------------------

  function test_the_target_line_names_the_level_data() {
    return [
      { tag: "milestone", level: "milestone", title: "Document milestone runs",
        text: "Target   Milestone \"Document milestone runs\"" },
      { tag: "board", level: "board", title: "", text: "Target   Whole board" },
      { tag: "subtask", level: "subtask", title: "RunStore dispatch", text: "Target   Subtask \"RunStore dispatch\"" },
      { tag: "story", level: "story", title: "Dispatch UI", text: "Target   Story \"Dispatch UI\"" },
      { tag: "unknown-level", level: "", title: "Loose card", text: "Target   \"Loose card\"" },
      { tag: "no-level-no-title", level: "", title: "", text: "Target   No card" }
    ]
  }

  function test_the_target_line_names_the_level(data) {
    var d = make({ target: { level: data.level }, targetTitle: data.title })
    compare(H.find(d, "dispatchTarget").text, data.text)
  }

  function test_a_null_target_without_a_title_is_no_card() {
    var d = make({ target: null, targetTitle: "" })
    compare(H.find(d, "dispatchTarget").text, "Target   No card")
  }

  // ---- Start only from ready ----------------------------------------------

  function test_start_is_disabled_unless_ready_data() {
    return [
      { tag: "idle", state: "idle" },
      { tag: "previewing", state: "previewing" },
      { tag: "refused", state: "refused" },
      { tag: "starting", state: "starting" },
      { tag: "started", state: "started" },
      { tag: "failed", state: "failed" }
    ]
  }

  function test_start_is_disabled_unless_ready(data) {
    var d = make({ dispatchState: data.state })
    var start = H.find(d, "dispatchStart")
    compare(d.canStart, false)
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0)
  }

  function test_start_in_ready_emits_once_with_its_label_and_glyph() {
    var d = make()
    var start = H.find(d, "dispatchStart")
    compare(d.canStart, true)
    compare(start.enabled, true)
    compare(start.text, "Start run")
    compare(start.iconText, "▶")
    click(start)
    compare(starts.count, 1)
    compare(cancels.count, 0)
  }

  // ---- the cost warning -------------------------------------------------

  function test_the_cost_warning_shows_in_every_state_data() {
    var rows = []
    for (var i = 0; i < tc.dispatchStates.length; i++) {
      rows.push({ tag: tc.dispatchStates[i] + "-form", state: tc.dispatchStates[i], withForm: true })
      rows.push({ tag: tc.dispatchStates[i] + "-no-form", state: tc.dispatchStates[i], withForm: false })
    }
    return rows
  }

  function test_the_cost_warning_shows_in_every_state(data) {
    var d = make({ dispatchState: data.state, form: data.withForm ? milestoneForm() : null })
    var warning = H.find(d, "dispatchWarning")
    verify(warning.visible, "the warning")
    compare(warning.text, "⚠ This starts agents and spends tokens.")
    compare(warning.color, d.theme.urgent)
  }

  function test_the_board_warning_names_every_open_milestone() {
    var d = make({ target: { level: "board" }, targetTitle: "" })
    compare(H.find(d, "dispatchWarning").text, "⚠ This starts agents on every open milestone and spends tokens.")
  }

  // ---- cancelling -------------------------------------------------------

  function test_cancel_and_the_backdrop_cancel_but_the_card_does_not() {
    var d = make()
    click(H.find(d, "dispatchCancel"))
    compare(cancels.count, 1)
    mouseClick(H.find(d, "dispatchBackdrop"), 2, 2)
    compare(cancels.count, 2)
    mouseClick(H.find(d, "dispatchCard"), 3, 3)
    compare(cancels.count, 2)
    compare(starts.count, 0)
  }

  function test_starting_locks_start_cancel_and_the_backdrop() {
    var d = make({ dispatchState: "starting" })
    var start = H.find(d, "dispatchStart"), cancel = H.find(d, "dispatchCancel")
    compare(d.busy, true)
    compare(start.text, "Starting…")
    compare(start.enabled, false)
    compare(cancel.enabled, false)
    click(start)
    click(cancel)
    mouseClick(H.find(d, "dispatchBackdrop"), 2, 2)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  function test_without_a_form_the_focus_goes_to_cancel() {
    var d = make({ form: null, dispatchState: "refused" })
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  // ---- the preview area -------------------------------------------------

  function test_ready_shows_what_am_would_do() {
    var d = make()
    compare(H.find(d, "dispatchPreviewHeading").text, "Preview  (am run --dry-run)")
    var summary = H.find(d, "dispatchSummary"), integrate = H.find(d, "dispatchIntegrate")
    verify(summary.visible, "the summary")
    compare(summary.text, "2 levels · 5 subtasks · 3 stories already done")
    verify(integrate.visible, "the integrate line")
    compare(integrate.text, "Integrate → m3-integrate")
    verify(!H.find(d, "dispatchRefusal").visible, "no refusal")
    verify(!H.find(d, "dispatchChecking").visible, "not checking")
    verify(!H.find(d, "dispatchSubtaskNote").visible, "no subtask note")
  }

  function test_an_empty_integrate_line_is_hidden() {
    var d = make({ preview: { board: false, summary: "1 level · 2 subtasks", integrate: "" } })
    compare(H.find(d, "dispatchSummary").text, "1 level · 2 subtasks")
    verify(!H.find(d, "dispatchIntegrate").visible)
  }

  function test_an_empty_or_missing_preview_falls_back_to_one_sentence_data() {
    return [
      { tag: "both-empty", preview: { board: false, summary: "", integrate: "" } },
      { tag: "null", preview: null },
      { tag: "no-keys", preview: {} }
    ]
  }

  function test_an_empty_or_missing_preview_falls_back_to_one_sentence(data) {
    var d = make({ preview: data.preview })
    var summary = H.find(d, "dispatchSummary")
    verify(summary.visible)
    compare(summary.text, "am accepted the plan; it could not be summarised here")
    verify(!H.find(d, "dispatchIntegrate").visible)
  }

  function test_starting_and_started_keep_the_summary_data() {
    return [{ tag: "starting", state: "starting" }, { tag: "started", state: "started" }]
  }

  function test_starting_and_started_keep_the_summary(data) {
    var d = make({ dispatchState: data.state })
    verify(H.find(d, "dispatchSummary").visible)
    compare(H.find(d, "dispatchSummary").text, "2 levels · 5 subtasks · 3 stories already done")
  }

  function test_the_preview_heading_names_the_dry_run_for_board_and_milestone_only_data() {
    return [
      { tag: "board", level: "board", text: "Preview  (am run --dry-run)" },
      { tag: "milestone", level: "milestone", text: "Preview  (am run --dry-run)" },
      { tag: "story", level: "story", text: "Preview" },
      { tag: "subtask", level: "subtask", text: "Preview" },
      { tag: "none", level: "", text: "Preview" }
    ]
  }

  function test_the_preview_heading_names_the_dry_run_for_board_and_milestone_only(data) {
    var d = make({ target: { level: data.level } })
    compare(H.find(d, "dispatchPreviewHeading").text, data.text)
  }

  function test_a_refusal_shows_inline_verbatim() {
    var d = make({ dispatchState: "refused", error: "Card m1 is claimed by run r-123 (ClaimedError)" })
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Card m1 is claimed by run r-123 (ClaimedError)")
    compare(refusal.color, d.theme.urgent)
    verify(!H.find(d, "dispatchSummary").visible, "no summary")
    verify(!H.find(d, "dispatchExitCode").visible, "no launch details for a refusal")
    compare(H.find(d, "dispatchStart").enabled, false)
  }

  function test_a_refusal_shows_no_launch_details() {
    var d = make({ dispatchState: "refused", error: "No such milestone", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "boom" })
    verify(!H.find(d, "dispatchExitCode").visible)
    verify(!H.find(d, "dispatchLogPath").visible)
    verify(!H.find(d, "dispatchLogTail").visible)
  }

  function test_a_target_refused_at_open_shows_the_refusal_and_no_form() {
    var d = make({ dispatchState: "refused", form: null, preview: null,
                   target: { level: "story", offered: false, reason: "A story is dispatched through its milestone" },
                   targetTitle: "Dispatch UI", error: "A story is dispatched through its milestone" })
    var base = H.find(d, "dispatchBase")
    verify(!base || !base.visible, "no form field")
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Dispatch UI\"")
    verify(H.find(d, "dispatchRefusal").visible)
    compare(H.find(d, "dispatchRefusal").text, "A story is dispatched through its milestone")
    verify(H.find(d, "dispatchWarning").visible)
    compare(H.find(d, "dispatchCancel").enabled, true)
    compare(H.find(d, "dispatchStart").enabled, false)
  }

  function test_previewing_says_checking() {
    var d = make({ dispatchState: "previewing", preview: null })
    var checking = H.find(d, "dispatchChecking")
    verify(checking.visible)
    compare(checking.text, "Checking…")
    verify(!H.find(d, "dispatchSummary").visible)
    verify(!H.find(d, "dispatchRefusal").visible)
  }

  function test_a_failed_launch_shows_the_exit_code_the_log_and_its_tail() {
    var d = make({ dispatchState: "failed", error: "am exited before the run appeared", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "Traceback\nValueError: bad base" })
    compare(H.find(d, "dispatchRefusal").text, "am exited before the run appeared")
    verify(H.find(d, "dispatchRefusal").visible)
    verify(H.find(d, "dispatchExitCode").visible)
    compare(H.find(d, "dispatchExitCode").text, "Exit code 2")
    verify(H.find(d, "dispatchLogPath").visible)
    compare(H.find(d, "dispatchLogPath").text, "Log: /tmp/x.log")
    verify(H.find(d, "dispatchLogTail").visible)
    compare(H.find(d, "dispatchLogTail").text, "Traceback\nValueError: bad base")
    verify(!H.find(d, "dispatchSummary").visible)
    compare(H.find(d, "dispatchStart").enabled, false)
  }

  function test_a_failure_without_a_code_or_a_log_hides_those_lines() {
    var d = make({ dispatchState: "failed", error: "start-run.py failed", exitCode: null, logPath: "", logTail: "" })
    verify(H.find(d, "dispatchRefusal").visible)
    verify(!H.find(d, "dispatchExitCode").visible)
    verify(!H.find(d, "dispatchLogPath").visible)
    verify(!H.find(d, "dispatchLogTail").visible)
  }

  function test_an_exit_code_of_zero_still_shows() {
    var d = make({ dispatchState: "failed", error: "the run never appeared", exitCode: 0 })
    verify(H.find(d, "dispatchExitCode").visible)
    compare(H.find(d, "dispatchExitCode").text, "Exit code 0")
  }

  function test_a_twenty_line_tail_keeps_its_last_six_lines_and_the_buttons_in_the_card() {
    var lines = []
    for (var i = 1; i <= 20; i++) lines.push("line " + i)
    var d = make({ dispatchState: "failed", error: "am exited", exitCode: 1, logPath: "/tmp/x.log",
                   logTail: lines.join("\n") })
    compare(H.find(d, "dispatchLogTail").text, "line 15\nline 16\nline 17\nline 18\nline 19\nline 20")
    var card = H.find(d, "dispatchCard"), cancel = H.find(d, "dispatchCancel")
    var p = cancel.mapToItem(card, 0, 0)
    verify(p.y >= 0 && p.y + cancel.height <= card.height,
           "Cancel ends at " + (p.y + cancel.height) + ", the card at " + card.height)
  }

  function test_a_subtask_has_no_dry_run_and_shows_the_owners_facts() {
    var d = make({ target: { level: "subtask", offered: true }, targetTitle: "RunStore dispatch", preview: null,
                   storyTitle: "Control store", blockedText: "Blocked by 3.1 RunStore dispatch (done)" })
    var note = H.find(d, "dispatchSubtaskNote")
    verify(note.visible)
    compare(note.text, "No preview: am has no dry run for one subtask")
    verify(H.find(d, "dispatchStory").visible)
    compare(H.find(d, "dispatchStory").text, "Story   \"Control store\"")
    verify(H.find(d, "dispatchBlocked").visible)
    compare(H.find(d, "dispatchBlocked").text, "Blocked by 3.1 RunStore dispatch (done)")
    compare(H.find(d, "dispatchPreviewHeading").text, "Preview")
    verify(!H.find(d, "dispatchSummary").visible, "no am summary for a subtask")
    compare(H.find(d, "dispatchStart").enabled, true)
  }

  function test_a_subtask_without_a_story_or_blockers_shows_only_the_note() {
    var d = make({ target: { level: "subtask" }, targetTitle: "RunStore dispatch", storyTitle: "", blockedText: "" })
    verify(H.find(d, "dispatchSubtaskNote").visible)
    verify(!H.find(d, "dispatchStory").visible)
    verify(!H.find(d, "dispatchBlocked").visible)
  }

  function test_a_refused_subtask_shows_the_refusal_not_the_note() {
    var d = make({ dispatchState: "refused", target: { level: "subtask" }, error: "This card is done",
                   storyTitle: "Control store" })
    verify(H.find(d, "dispatchRefusal").visible)
    verify(!H.find(d, "dispatchSubtaskNote").visible)
    verify(!H.find(d, "dispatchStory").visible)
  }

  function test_a_previewing_subtask_shows_the_note_not_checking() {
    var d = make({ dispatchState: "previewing", target: { level: "subtask" } })
    verify(H.find(d, "dispatchSubtaskNote").visible)
    verify(!H.find(d, "dispatchChecking").visible)
  }

  // ---- base and prefix --------------------------------------------------

  function test_base_and_prefix_show_the_form_and_report_edits() {
    var d = make()
    var base = H.find(d, "dispatchBase"), prefix = H.find(d, "dispatchPrefix")
    verify(base.visible, "the base field")
    compare(base.text, "main")
    compare(base.placeholderText, "main")
    compare(prefix.text, "m3")
    compare(edits.count, 0, "showing the form echoes nothing")
    base.text = "dev"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "base")
    compare(edits.signalArguments[0][1], "dev")
    prefix.text = "m4"
    compare(edits.count, 2)
    compare(edits.signalArguments[1][0], "prefix")
    compare(edits.signalArguments[1][1], "m4")
  }

  function test_edits_go_out_verbatim_the_store_trims() {
    var d = make()
    H.find(d, "dispatchBase").text = " dev "
    compare(edits.signalArguments[0][1], " dev ")
  }

  function test_a_new_form_from_the_owner_updates_the_fields_and_echoes_nothing() {
    var d = make()
    d.form = milestoneForm({ base: "release", prefix: "m9", parallelism: 2 })
    compare(H.find(d, "dispatchBase").text, "release")
    compare(H.find(d, "dispatchPrefix").text, "m9")
    compare(H.find(d, "dispatchParallel").text, "2")
    compare(edits.count, 0)
  }

  function test_the_owner_feeding_an_edit_back_changes_nothing() {
    var d = make()
    var base = H.find(d, "dispatchBase")
    base.text = "dev"
    compare(edits.count, 1)
    d.form = milestoneForm({ base: "dev" })
    compare(base.text, "dev")
    compare(edits.count, 1)
  }

  function test_opening_a_form_into_a_mounted_dialog_echoes_nothing() {
    var d = make({ dispatchState: "idle", form: null })
    d.dispatchState = "ready"
    d.form = milestoneForm()
    compare(H.find(d, "dispatchBase").text, "main")
    compare(H.find(d, "dispatchPrefix").text, "m3")
    compare(H.find(d, "dispatchParallel").text, "4")
    compare(edits.count, 0)
  }

  function test_a_partial_form_reads_as_empty_fields() {
    var d = make({ form: null })
    d.form = {}
    compare(H.find(d, "dispatchBase").text, "")
    compare(H.find(d, "dispatchPrefix").text, "")
    compare(H.find(d, "dispatchParallel").text, "")
    compare(H.find(d, "dispatchNoVerify").active, false)
    compare(edits.count, 0)
  }

  // ---- the no-verification chip -----------------------------------------

  function test_the_no_verification_chip_flips_the_opt_out() {
    var d = make()
    var chip = H.find(d, "dispatchNoVerify")
    compare(chip.text, "run without any verification")
    compare(chip.active, false)
    click(chip)
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "allowNoVerification")
    compare(edits.signalArguments[0][1], true)
    d.form = milestoneForm({ allowNoVerification: true })
    compare(chip.active, true)
    compare(chip.tint, d.theme.urgent)
    click(chip)
    compare(edits.count, 2)
    compare(edits.signalArguments[1][0], "allowNoVerification")
    compare(edits.signalArguments[1][1], false)
  }

  // ---- parallelism ------------------------------------------------------

  function test_parallelism_is_a_number_when_it_is_all_digits() {
    var d = make()
    var field = H.find(d, "dispatchParallel")
    compare(field.text, "4")
    field.text = "6"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "parallelism")
    compare(edits.signalArguments[0][1], 6)
    compare(typeof edits.signalArguments[0][1], "number")
    field.text = "abc"
    compare(edits.count, 2)
    compare(edits.signalArguments[1][1], "abc")
    compare(typeof edits.signalArguments[1][1], "string")
    field.text = ""
    compare(edits.count, 3)
    compare(edits.signalArguments[2][1], "")
  }

  function test_a_padded_number_is_sent_trimmed_and_kept_as_typed() {
    var d = make()
    var field = H.find(d, "dispatchParallel")
    field.text = " 6 "
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], 6)
    d.form = milestoneForm({ parallelism: 6 })
    compare(field.text, " 6 ", "the owner's 6 agrees, so the typing stays")
    compare(edits.count, 1)
  }

  function test_a_parallelism_the_owner_holds_as_text_echoes_nothing() {
    var d = make({ form: null })
    d.form = milestoneForm({ parallelism: "6" })
    compare(H.find(d, "dispatchParallel").text, "6")
    compare(edits.count, 0)
  }

  // ---- keys -------------------------------------------------------------

  function test_escape_in_a_field_cancels() {
    var d = make()
    H.find(d, "dispatchPrefix").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    H.find(d, "dispatchParallel").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 2)
    compare(starts.count, 0)
  }

  function test_return_in_a_field_never_starts_data() {
    return [{ tag: "base", name: "dispatchBase" }, { tag: "prefix", name: "dispatchPrefix" },
            { tag: "parallel", name: "dispatchParallel" }]
  }

  function test_return_in_a_field_never_starts(data) {
    var d = make()
    compare(d.canStart, true)
    H.find(d, data.name).forceActiveFocus()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // ---- editable ---------------------------------------------------------

  function test_fields_are_editable_only_where_the_store_takes_edits_data() {
    return [
      { tag: "idle", state: "idle", editable: false },
      { tag: "previewing", state: "previewing", editable: true },
      { tag: "ready", state: "ready", editable: true },
      { tag: "refused", state: "refused", editable: true },
      { tag: "starting", state: "starting", editable: false },
      { tag: "started", state: "started", editable: false },
      { tag: "failed", state: "failed", editable: true }
    ]
  }

  function test_fields_are_editable_only_where_the_store_takes_edits(data) {
    var d = make({ dispatchState: data.state })
    compare(d.editable, data.editable)
    compare(H.find(d, "dispatchBase").enabled, data.editable)
    compare(H.find(d, "dispatchPrefix").enabled, data.editable)
    compare(H.find(d, "dispatchParallel").enabled, data.editable)
    compare(H.find(d, "dispatchNoVerify").busy, !data.editable)
  }

  function test_without_a_form_nothing_is_editable() {
    var d = make({ form: null, dispatchState: "refused" })
    compare(d.editable, false)
  }

  function test_starting_disables_the_fields_the_chip_and_escape() {
    var d = make()
    var prefix = H.find(d, "dispatchPrefix")
    prefix.forceActiveFocus()
    d.dispatchState = "starting"
    compare(H.find(d, "dispatchBase").enabled, false)
    compare(prefix.enabled, false)
    compare(H.find(d, "dispatchParallel").enabled, false)
    var chip = H.find(d, "dispatchNoVerify")
    compare(chip.busy, true)
    click(chip)
    compare(edits.count, 0)
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 0)
  }

  // ---- focus and teardown -----------------------------------------------

  function test_with_a_form_the_focus_goes_to_base() {
    var d = make()
    compare(d.focusItem, H.find(d, "dispatchBase"))
    d.form = null
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  function test_nulling_every_object_prop_and_destroying_is_quiet() {
    var d = make()
    d.theme = null
    d.target = null
    d.form = null
    d.preview = null
    wait(0)
    compare(edits.count, 0)
    verify(H.find(d, "dispatchWarning").visible)
    compare(H.find(d, "dispatchTarget").text, "Target   \"Document milestone runs\"")
    d.destroy()
    wait(0)
  }
}
