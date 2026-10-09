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
  SignalSpy { id: chosen; signalName: "targetChosen" }
  SignalSpy { id: offers; signalName: "suggestionRequested" }
  SignalSpy { id: picks; signalName: "projectChosen" }
  SignalSpy { id: backs; signalName: "backRequested" }
  SignalSpy { id: targetPicks; signalName: "targetPicked" }

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
    edits.target = d; starts.target = d; cancels.target = d; chosen.target = d; offers.target = d
    picks.target = d; backs.target = d; targetPicks.target = d
    edits.clear(); starts.clear(); cancels.clear(); chosen.clear(); offers.clear(); picks.clear()
    backs.clear(); targetPicks.clear()
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
      { tag: "no-level-no-title", level: "", title: "", text: "Target   No card" },
      { tag: "story-empty-label", level: "story", title: "Dispatch UI", label: "",
        text: "Target   Story \"Dispatch UI\"" }
    ]
  }

  function test_the_target_line_names_the_level(data) {
    var over = { target: { level: data.level }, targetTitle: data.title }
    if (data.label !== undefined) over.targetLabel = data.label
    var d = make(over)
    compare(H.find(d, "dispatchTarget").text, data.text)
  }

  function test_a_null_target_without_a_title_is_no_card() {
    var d = make({ target: null, targetTitle: "" })
    compare(H.find(d, "dispatchTarget").text, "Target   No card")
  }

  function test_the_owners_label_is_the_target_line_verbatim_data() {
    return [
      { tag: "story", level: "story", title: "Story one", label: "Story \"Story one\" (milestone \"M one\")",
        text: "Target   Story \"Story one\" (milestone \"M one\")" },
      { tag: "milestone-over-another-title", level: "milestone", title: "other", label: "Milestone \"M one\"",
        text: "Target   Milestone \"M one\"" }
    ]
  }

  function test_the_owners_label_is_the_target_line_verbatim(data) {
    var d = make({ target: { level: data.level }, targetTitle: data.title, targetLabel: data.label })
    compare(H.find(d, "dispatchTarget").text, data.text)
  }

  function test_the_label_leaves_the_level_driven_areas_alone() {
    var d = make({ target: { level: "subtask" }, targetTitle: "Do it", targetLabel: "Milestone \"M one\"",
                   dispatchState: "previewing", preview: null })
    compare(H.find(d, "dispatchPreviewHeading").text, "Preview")
    verify(H.find(d, "dispatchSubtaskNote").visible, "the subtask note follows the level")
    compare(H.find(d, "dispatchWarning").text, "⚠ This starts agents and spends tokens.")
  }

  function test_a_long_label_elides_on_one_line() {
    var long = "Story \"" + new Array(40).join("A very long story title ") + "\" (milestone \"M one\")"
    var d = make({ target: { level: "story" }, targetTitle: "x", targetLabel: long })
    var line = H.find(d, "dispatchTarget")
    compare(line.elide, Text.ElideRight)
    compare(line.text, "Target   " + long)
    verify(line.truncated, "the label is cut, not wrapped")
    compare(line.lineCount, 1)
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

  // ---- verify rows ------------------------------------------------------

  function test_editing_a_verify_row_sends_the_whole_list() {
    var d = make()
    var row0 = H.find(d, "dispatchVerify0")
    compare(row0.text, "uv run pytest")
    compare(row0.placeholderText, "uv run pytest")
    compare(edits.count, 0)
    row0.text = "uv run pytest -x"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "verify")
    compare(edits.signalArguments[0][1], ["uv run pytest -x"])
  }

  function test_plus_adds_an_empty_command() {
    var d = make()
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][0], "verify")
    compare(edits.signalArguments[0][1], ["uv run pytest", ""])
    d.form = milestoneForm({ verify: ["uv run pytest", ""] })
    verify(H.find(d, "dispatchVerify1"), "the new row")
    compare(H.find(d, "dispatchVerify1").text, "")
    verify(H.find(d, "dispatchVerifyRemove0").visible)
    verify(H.find(d, "dispatchVerifyRemove1").visible)
    compare(edits.count, 1, "the new row echoes nothing")
  }

  function test_an_empty_set_shows_one_empty_row_and_plus_gives_two() {
    var d = make({ form: null })
    d.form = milestoneForm({ verify: [] })
    compare(H.find(d, "dispatchVerify0").text, "")
    verify(!H.find(d, "dispatchVerify1"), "one row only")
    verify(!H.find(d, "dispatchVerifyRemove0").visible, "no remove on the only row")
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], ["", ""])
  }

  function test_remove_drops_that_row() {
    var d = make()
    d.form = milestoneForm({ verify: ["a", "b"] })
    compare(edits.count, 0)
    compare(H.find(d, "dispatchVerify0").text, "a")
    compare(H.find(d, "dispatchVerify1").text, "b")
    click(H.find(d, "dispatchVerifyRemove1"))
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], ["a"])
    click(H.find(d, "dispatchVerifyRemove0"))
    compare(edits.count, 2)
    compare(edits.signalArguments[1][1], ["b"])
  }

  function test_editing_the_second_row_keeps_the_first() {
    var d = make()
    d.form = milestoneForm({ verify: ["a", "b"] })
    H.find(d, "dispatchVerify1").text = "b2"
    compare(edits.count, 1)
    compare(edits.signalArguments[0][1], ["a", "b2"])
  }

  function test_one_row_has_no_remove_button() {
    var d = make()
    var remove = H.find(d, "dispatchVerifyRemove0")
    verify(!remove || !remove.visible)
  }

  function test_a_verify_row_survives_the_owner_feeding_its_edit_back() {
    var d = make()
    var row0 = H.find(d, "dispatchVerify0")
    row0.forceActiveFocus()
    row0.text = "uv run pytest -x"
    compare(edits.count, 1)
    d.form = milestoneForm({ verify: ["uv run pytest -x"] })
    verify(H.find(d, "dispatchVerify0") === row0, "the same row, not a new one")
    compare(row0.text, "uv run pytest -x")
    verify(row0.activeFocus, "still focused")
    compare(edits.count, 1)
  }

  function test_a_missing_or_malformed_verify_reads_as_one_empty_row_data() {
    return [
      { tag: "missing", form: { base: "main", prefix: "m3", parallelism: 4 } },
      { tag: "a-string", form: { base: "main", verify: "uv run pytest" } },
      { tag: "null", form: { base: "main", verify: null } }
    ]
  }

  function test_a_missing_or_malformed_verify_reads_as_one_empty_row(data) {
    var d = make({ form: null })
    d.form = data.form
    compare(H.find(d, "dispatchVerify0").text, "")
    verify(!H.find(d, "dispatchVerify1"), "one row only")
    compare(edits.count, 0)
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.signalArguments[0][1], ["", ""])
  }

  function test_escape_in_a_verify_row_cancels() {
    var d = make()
    H.find(d, "dispatchVerify0").forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
  }

  function test_starting_disables_the_verify_rows_and_plus() {
    var d = make()
    d.form = milestoneForm({ verify: ["a", "b"] })
    d.dispatchState = "starting"
    compare(H.find(d, "dispatchVerify0").enabled, false)
    compare(H.find(d, "dispatchVerifyRemove0").enabled, false)
    compare(H.find(d, "dispatchVerifyAdd").enabled, false)
    click(H.find(d, "dispatchVerifyAdd"))
    compare(edits.count, 0)
  }

  // ---- the card's fit ---------------------------------------------------

  function test_the_buttons_stay_inside_the_card_with_four_commands_and_a_failure() {
    var d = make({ dispatchState: "failed", error: "am exited before the run appeared", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "one\ntwo\nthree",
                   form: milestoneForm({ verify: ["a", "b", "c", "d"] }) })
    verify(H.find(d, "dispatchVerify3"), "four rows")
    var card = H.find(d, "dispatchCard")
    var names = ["dispatchStart", "dispatchCancel"]
    for (var i = 0; i < names.length; i++) {
      var button = H.find(d, names[i])
      var p = button.mapToItem(card, 0, 0)
      verify(p.y >= 0 && p.y + button.height <= card.height,
             names[i] + " ends at " + (p.y + button.height) + ", the card at " + card.height)
    }
  }

  // ---- the Runs entry's target row (S3 4.2) ------------------------------

  property var boardChoices: [{ id: "board", label: "Whole board" }, { id: "m1", label: "M one" }]

  // 1
  function test_the_target_row_is_hidden_without_choices() {
    var d = make()
    var row = H.find(d, "dispatchTargetChoices")
    verify(row, "the target row")
    compare(row.visible, false)
  }

  // 1
  function test_the_target_row_shows_the_choices_and_emits_another_one() {
    var d = make({ target: { level: "board" }, targetTitle: "", targetChoices: tc.boardChoices, targetChoice: "board" })
    compare(H.find(d, "dispatchTargetChoices").visible, true)
    var board = H.find(d, "dispatchTargetChoiceboard")
    var m1 = H.find(d, "dispatchTargetChoicem1")
    verify(board && m1, "both chips")
    compare(board.text, "Whole board")
    compare(m1.text, "M one")
    compare(board.active, true)
    compare(m1.active, false)
    click(board)
    compare(chosen.count, 0, "the active chip emits nothing")
    click(m1)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "m1")
    compare(starts.count, 0)
  }

  // 1
  function test_the_target_row_is_busy_while_starting() {
    var d = make({ target: { level: "board" }, targetChoices: tc.boardChoices, targetChoice: "board" })
    d.dispatchState = "starting"
    var m1 = H.find(d, "dispatchTargetChoicem1")
    compare(m1.busy, true)
    click(m1)
    compare(chosen.count, 0)
  }

  // ---- the story's refusals and the blocked story's action (S7) -----------

  function storyRefusal(over) {
    return Object.assign({ dispatchState: "refused", target: { level: "story", offered: true }, targetTitle: "Story one",
                           targetLabel: "Story \"Story one\" (milestone \"M one\")",
                           form: null, preview: null,
                           error: "Story \"Story one\" is blocked by \"Story zero\" (StoryBlockedError)",
                           suggestion: { id: "m1", title: "M one" } }, over || {})
  }

  // 3
  function test_a_blocked_story_shows_the_refusal_and_the_milestone_action() {
    var d = make(storyRefusal())
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Story one\" (milestone \"M one\")")
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Story \"Story one\" is blocked by \"Story zero\" (StoryBlockedError)")
    compare(refusal.color, d.theme.urgent)
    var start = H.find(d, "dispatchStart")
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0, "a disabled Start emits nothing")
    var offer = H.find(d, "dispatchSuggest")
    verify(offer, "the action")
    compare(offer.visible, true)
    compare(offer.text, "Dispatch the milestone instead")
    click(offer)
    compare(offers.count, 1)
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // Review Focus 1
  function test_a_second_click_after_the_owner_moves_on_emits_nothing() {
    var d = make(storyRefusal())
    var offer = H.find(d, "dispatchSuggest")
    click(offer)
    compare(offers.count, 1)
    d.dispatchState = "previewing"
    d.suggestion = null
    offer.clicked()
    compare(offers.count, 1, "the second click finds no refusal")
    compare(offer.visible, false)
  }

  // 4, Review Focus 4
  function test_the_action_text_ignores_the_title_data() {
    return [
      { tag: "titled", suggestion: { id: "m1", title: "M one" } },
      { tag: "untitled", suggestion: { id: "m1", title: "" } },
      { tag: "non-string-title", suggestion: { id: "m1", title: 7 } },
      { tag: "no-title", suggestion: { id: "m1" } }
    ]
  }

  function test_the_action_text_ignores_the_title(data) {
    var d = make(storyRefusal({ suggestion: data.suggestion }))
    var offer = H.find(d, "dispatchSuggest")
    compare(offer.visible, true)
    compare(offer.text, "Dispatch the milestone instead")
  }

  // 5
  function test_the_offer_shows_only_for_a_refusal_with_a_milestone_id_data() {
    return [
      { tag: "ready", over: { dispatchState: "ready" } },
      { tag: "no-suggestion", over: { suggestion: null } },
      { tag: "empty-id", over: { suggestion: { id: "", title: "M one" } } },
      { tag: "non-string-id", over: { suggestion: { id: 7, title: "M one" } } },
      { tag: "failed", over: { dispatchState: "failed" } }
    ]
  }

  function test_the_offer_shows_only_for_a_refusal_with_a_milestone_id(data) {
    var d = make(storyRefusal(data.over))
    var offer = H.find(d, "dispatchSuggest")
    compare(offer.visible, false)
    offer.clicked()
    compare(offers.count, 0, "a hidden offer emits nothing")
  }

  // 6
  function test_a_finished_story_says_nothing_is_left_to_run() {
    var d = make(storyRefusal({ error: "Nothing left to run", suggestion: null }))
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Story one\" (milestone \"M one\")")
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Nothing left to run")
    var start = H.find(d, "dispatchStart")
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0)
    compare(H.find(d, "dispatchSuggest").visible, false)
    compare(H.find(d, "dispatchSummary").visible, false)
  }

  // 7
  function test_a_claimed_story_names_the_holding_run() {
    var d = make(storyRefusal({ error: "Card s1 is claimed by run r-123 (ClaimedError)", suggestion: null }))
    compare(H.find(d, "dispatchTarget").text, "Target   Story \"Story one\" (milestone \"M one\")")
    var refusal = H.find(d, "dispatchRefusal")
    verify(refusal.visible, "the refusal")
    compare(refusal.text, "Card s1 is claimed by run r-123 (ClaimedError)")
    verify(String(refusal.text).indexOf("r-123") >= 0, "the holding run")
    var start = H.find(d, "dispatchStart")
    compare(start.enabled, false)
    click(start)
    compare(starts.count, 0)
    compare(H.find(d, "dispatchSuggest").visible, false)
    compare(H.find(d, "dispatchExitCode").visible, false)
    compare(H.find(d, "dispatchLogPath").visible, false)
  }

  // ---- the subtask's two-click Start (S3 4.2) -----------------------------

  function subtask(over) {
    return Object.assign({ target: { level: "subtask", offered: true }, targetTitle: "Do it", preview: null,
                           confirmFirst: true }, over || {})
  }

  // 3
  function test_confirm_first_needs_a_second_click() {
    var d = make(subtask())
    var start = H.find(d, "dispatchStart")
    var note = H.find(d, "dispatchConfirmNote")
    verify(note, "the confirm note")
    compare(d.armed, false)
    compare(note.visible, false)
    click(start)
    compare(starts.count, 0, "the first click only arms")
    compare(d.armed, true)
    compare(start.text, "Confirm start")
    compare(note.visible, true)
    compare(note.text, "Click Confirm start to start this subtask.")
    click(start)
    compare(starts.count, 1)
  }

  // 4
  function test_the_arming_is_dropped_data() {
    return [{ tag: "new-form" }, { tag: "re-preview" }, { tag: "hidden" }, { tag: "confirm-off" }, { tag: "new-target" }]
  }

  function test_the_arming_is_dropped(data) {
    var d = make(subtask())
    var start = H.find(d, "dispatchStart")
    click(start)
    compare(d.armed, true)
    if (data.tag === "new-form") d.form = milestoneForm({ prefix: "m4" })
    else if (data.tag === "re-preview") { d.dispatchState = "previewing"; d.dispatchState = "ready" }
    else if (data.tag === "hidden") { d.shown = false; d.shown = true }
    else if (data.tag === "confirm-off") d.confirmFirst = false
    else d.target = { level: "subtask", offered: true }
    compare(d.armed, false)
    compare(start.text, "Start run")
    compare(H.find(d, "dispatchConfirmNote").visible, false)
    compare(starts.count, 0)
    compare(edits.count, 0, "a new form echoes nothing")
  }

  // 5
  function test_without_confirm_first_one_click_starts() {
    var d = make(subtask({ confirmFirst: false }))
    click(H.find(d, "dispatchStart"))
    compare(starts.count, 1)
    compare(d.armed, false)
  }

  // ---- the project step -------------------------------------------------

  // A colour stored in a `color` property is rounded to 8 bits per channel, so
  // it differs from the theme's float colour by up to 1/255.
  function sameColour(a, b) {
    return Math.abs(a.r - b.r) < 1 / 255 && Math.abs(a.g - b.g) < 1 / 255
      && Math.abs(a.b - b.b) < 1 / 255 && Math.abs(a.a - b.a) < 1 / 255
  }

  // RunStore's dispatchProjectRows: the open project first, then by name; one
  // board unreadable.
  function fixtureRows() {
    return [
      { root: "/home/u/Code/omarchy-project-manager", name: "omarchy-project-manager", open: true,
        enabled: true, reason: "" },
      { root: "/home/u/Code/agent-manager", name: "agent-manager", open: false, enabled: true, reason: "" },
      { root: "/home/u/Code/ori", name: "ori", open: false, enabled: true, reason: "" },
      { root: "/home/u/Code/py-ai-toolkit", name: "py-ai-toolkit", open: false, enabled: false,
        reason: "board unreachable: no .brd" }
    ]
  }

  // A disabled row first, and one between two enabled rows.
  function disabledFirstRows() {
    return [
      { root: "/r/a", name: "a", open: false, enabled: false, reason: "board unreachable: no .brd" },
      { root: "/r/b", name: "b", open: false, enabled: true, reason: "" },
      { root: "/r/c", name: "c", open: false, enabled: false, reason: "board unreachable: tree read failed" },
      { root: "/r/d", name: "d", open: false, enabled: true, reason: "" }
    ]
  }

  // The dialog at the project step over fixtureRows(); `over` replaces any prop.
  function projectStep(over) {
    return make(Object.assign({ step: "project", projectRows: tc.fixtureRows() }, over || {}))
  }

  // 3: each part shows at the form step, hides at the project step, and comes
  // back when the step leaves.
  function test_the_project_step_hides_the_form_steps_parts_data() {
    var refused = storyRefusal()
    var failed = { dispatchState: "failed", error: "am exited before the run appeared", exitCode: 2,
                   logPath: "/tmp/x.log", logTail: "Traceback" }
    var sub = { target: { level: "subtask", offered: true }, targetTitle: "Do it", preview: null,
                storyTitle: "Control store", blockedText: "Blocked by 3.1 RunStore dispatch (done)" }
    return [
      { tag: "target", name: "dispatchTarget", over: {} },
      { tag: "target-choices", name: "dispatchTargetChoices",
        over: { targetChoices: tc.boardChoices, targetChoice: "board" } },
      { tag: "form", name: "dispatchForm", over: {} },
      { tag: "preview-heading", name: "dispatchPreviewHeading", over: {} },
      { tag: "refusal", name: "dispatchRefusal", over: refused },
      { tag: "suggest", name: "dispatchSuggest", over: refused },
      { tag: "exit-code", name: "dispatchExitCode", over: failed },
      { tag: "log-path", name: "dispatchLogPath", over: failed },
      { tag: "log-tail", name: "dispatchLogTail", over: failed },
      { tag: "subtask-note", name: "dispatchSubtaskNote", over: sub },
      { tag: "story", name: "dispatchStory", over: sub },
      { tag: "blocked", name: "dispatchBlocked", over: sub },
      { tag: "checking", name: "dispatchChecking", over: { dispatchState: "previewing", preview: null } },
      { tag: "summary", name: "dispatchSummary", over: {} },
      { tag: "integrate", name: "dispatchIntegrate", over: {} },
      { tag: "warning", name: "dispatchWarning", over: {} },
      { tag: "confirm-note", name: "dispatchConfirmNote", over: subtask(), arm: true },
      { tag: "start", name: "dispatchStart", over: {} }
    ]
  }

  function test_the_project_step_hides_the_form_steps_parts(data) {
    var d = make(data.over)
    if (data.arm) click(H.find(d, "dispatchStart"))
    verify(H.find(d, data.name).visible, "shown at the form step")
    d.step = "project"
    verify(!H.find(d, data.name).visible, "hidden at the project step")
    d.step = ""
    verify(H.find(d, data.name).visible, "shown again once the step leaves")
  }

  // 3
  function test_the_project_step_heads_the_card_and_keeps_only_cancel() {
    var d = projectStep()
    var heading = H.find(d, "dispatchHeading")
    compare(heading.text, "Dispatch · 1 Project")
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
    d.step = ""
    compare(heading.text, "Dispatch")
    d.step = "target"
    compare(heading.text, "Dispatch · 2 Target")
    compare(picks.count, 0)
  }

  // 1
  function test_the_project_step_lists_each_project_with_its_marks() {
    var d = projectStep()
    var rows = tc.fixtureRows()
    verify(H.find(d, "dispatchProjectList").visible, "the list")
    for (var i = 0; i < rows.length; i++) {
      verify(H.find(d, "dispatchProjectRow" + i), "row " + i)
      compare(H.find(d, "dispatchProjectName" + i).text, rows[i].name)
      compare(H.find(d, "dispatchProjectOpen" + i).visible, i === 0, "open mark on row " + i)
      compare(H.find(d, "dispatchProjectReason" + i).visible, i === 3, "reason on row " + i)
    }
    compare(H.find(d, "dispatchProjectRow4"), null)
    compare(H.find(d, "dispatchProjectOpen0").text, "open")
    compare(H.find(d, "dispatchProjectReason3").text, "board unreachable: no .brd")
    verify(tc.sameColour(H.find(d, "dispatchProjectReason3").color, d.theme.dim), "reason colour")
    verify(!H.find(d, "dispatchProjectEmpty").visible, "no empty line")
  }

  // 2
  function test_a_disabled_rows_name_is_dimmed() {
    var d = projectStep()
    verify(tc.sameColour(H.find(d, "dispatchProjectName3").color, d.theme.dim), "name colour")
    verify(tc.sameColour(H.find(d, "dispatchProjectName0").color, d.theme.foreground), "name colour")
    verify(tc.sameColour(H.find(d, "dispatchProjectName2").color, d.theme.foreground), "name colour")
  }

  // 3
  function test_the_list_and_the_empty_line_show_only_at_the_project_step_data() {
    return [{ tag: "none", step: "" }, { tag: "target", step: "target" }, { tag: "other", step: "whatever" }]
  }

  function test_the_list_and_the_empty_line_show_only_at_the_project_step(data) {
    var full = make({ step: data.step, projectRows: tc.fixtureRows() })
    verify(!H.find(full, "dispatchProjectList").visible, "no list")
    compare(H.find(full, "dispatchProjectRow0"), null)
    var empty = make({ step: data.step, projectRows: [] })
    verify(!H.find(empty, "dispatchProjectEmpty").visible, "no empty line")
  }

  // 10
  function test_an_empty_or_malformed_registry_says_no_projects_data() {
    return [
      { tag: "empty", rows: [] },
      { tag: "null", rows: null },
      { tag: "undefined", rows: undefined },
      { tag: "object", rows: {} },
      { tag: "string", rows: "x" }
    ]
  }

  function test_an_empty_or_malformed_registry_says_no_projects(data) {
    var d = projectStep({ projectRows: data.rows })
    var empty = H.find(d, "dispatchProjectEmpty")
    verify(empty.visible, "the empty line")
    compare(empty.text, "No projects registered")
    compare(H.find(d, "dispatchProjectRow0"), null)
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
  }

  // 11
  function test_every_board_unreachable_lists_the_rows_with_their_reasons() {
    var rows = tc.fixtureRows()
    for (var i = 0; i < rows.length; i++) {
      rows[i].enabled = false
      rows[i].reason = "board unreachable: " + rows[i].name
    }
    var d = projectStep({ projectRows: rows })
    var empty = H.find(d, "dispatchProjectEmpty")
    verify(empty.visible, "the empty line")
    compare(empty.text, "No project's board can be read")
    for (var j = 0; j < rows.length; j++) {
      verify(H.find(d, "dispatchProjectRow" + j), "row " + j)
      var reason = H.find(d, "dispatchProjectReason" + j)
      verify(reason.visible, "reason " + j)
      compare(reason.text, "board unreachable: " + rows[j].name)
      verify(tc.sameColour(H.find(d, "dispatchProjectName" + j).color, d.theme.dim), "name colour")
    }
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
  }

  // Review Focus 3
  function test_a_malformed_row_reads_as_empty_and_disabled() {
    var d = projectStep({ projectRows: [
      { root: "/r/a", name: null, open: "yes", enabled: true },
      { root: "/r/b", name: "b", enabled: "yes", reason: 7 },
      null
    ] })
    compare(H.find(d, "dispatchProjectName0").text, "")
    verify(!H.find(d, "dispatchProjectOpen0").visible, "open only when exactly true")
    verify(!H.find(d, "dispatchProjectReason0").visible, "row 0 is enabled")
    compare(H.find(d, "dispatchProjectName1").text, "b")
    verify(H.find(d, "dispatchProjectReason1").visible, "enabled that is not true is disabled")
    compare(H.find(d, "dispatchProjectReason1").text, "")
    verify(tc.sameColour(H.find(d, "dispatchProjectName1").color, d.theme.dim), "name colour")
    verify(H.find(d, "dispatchProjectRow2"), "a null row is still a row")
    compare(H.find(d, "dispatchProjectName2").text, "")
    verify(!H.find(d, "dispatchProjectEmpty").visible, "row 0 is enabled")
  }

  // Review Focus 4
  function test_a_long_project_name_elides_on_one_line() {
    var long = new Array(30).join("a-very-long-project-name-")
    var d = projectStep({ projectRows: [{ root: "/r/l", name: long, open: true, enabled: true, reason: "" }] })
    var name = H.find(d, "dispatchProjectName0")
    compare(name.text, long)
    compare(name.elide, Text.ElideRight)
    verify(name.truncated, "the name is cut, not wrapped")
    compare(name.lineCount, 1)
    verify(H.find(d, "dispatchProjectOpen0").visible, "the open mark stays")
  }

  // 17
  function test_nulling_every_object_prop_at_the_project_step_and_destroying_is_quiet() {
    var d = projectStep()
    d.theme = null
    d.target = null
    d.form = null
    d.preview = null
    d.projectRows = null
    wait(0)
    compare(H.find(d, "dispatchProjectEmpty").text, "No projects registered")
    compare(picks.count, 0)
    d.destroy()
    wait(0)
  }

  // A dialog inside an owner that counts the keys the dialog leaves to it.
  Component {
    id: hostC
    Item {
      id: host
      property alias dialog: hosted
      property int passed: 0
      width: 640; height: 700
      Keys.onPressed: function(event) { host.passed++ }
      UI.DispatchDialog { id: hosted; width: 640; height: 700 }
    }
  }

  // 4
  function test_the_cursor_starts_on_the_first_enabled_row() {
    var d = projectStep({ projectRows: tc.disabledFirstRows() })
    compare(d.projectCursor, 1)
    verify(H.find(d, "dispatchProjectRow1").hasCursor, "row 1 is highlighted")
    verify(!H.find(d, "dispatchProjectRow0").hasCursor, "the disabled row never is")
    compare(projectStep().projectCursor, 0)
    compare(make().projectCursor, -1, "no cursor outside the project step")
  }

  // 5
  function test_down_and_up_skip_disabled_rows_and_stop_at_the_ends() {
    var d = projectStep({ projectRows: tc.disabledFirstRows() })
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Up)
    compare(d.projectCursor, 1, "Up on the first enabled row stays")
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 3, "Down jumps over the disabled row")
    verify(H.find(d, "dispatchProjectRow3").hasCursor)
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 3, "Down on the last enabled row stays")
    keyClick(Qt.Key_Up)
    compare(d.projectCursor, 1)
    compare(picks.count, 0)
  }

  // 6
  function test_enter_picks_the_cursor_row_data() {
    return [{ tag: "return", key: Qt.Key_Return }, { tag: "enter", key: Qt.Key_Enter }]
  }

  function test_enter_picks_the_cursor_row(data) {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(data.key)
    compare(picks.count, 1)
    compare(picks.signalArguments[0][0], "/home/u/Code/agent-manager")
    compare(cancels.count, 0)
    compare(starts.count, 0)
  }

  // 10, 11
  function test_without_an_enabled_row_there_is_no_cursor_and_enter_picks_nothing_data() {
    var off = tc.fixtureRows()
    for (var i = 0; i < off.length; i++) off[i].enabled = false
    return [
      { tag: "empty", rows: [] },
      { tag: "null", rows: null },
      { tag: "undefined", rows: undefined },
      { tag: "object", rows: {} },
      { tag: "string", rows: "x" },
      { tag: "all-disabled", rows: off }
    ]
  }

  function test_without_an_enabled_row_there_is_no_cursor_and_enter_picks_nothing(data) {
    var d = projectStep({ projectRows: data.rows })
    compare(d.projectCursor, -1)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(d.projectCursor, -1)
    compare(picks.count, 0)
  }

  // 12
  function test_escape_cancel_and_the_backdrop_cancel_the_project_step() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    click(H.find(d, "dispatchCancel"))
    compare(cancels.count, 2)
    mouseClick(H.find(d, "dispatchBackdrop"), 2, 2)
    compare(cancels.count, 3)
    mouseClick(H.find(d, "dispatchCard"), 3, 3)
    compare(cancels.count, 3, "the card itself does nothing")
    compare(picks.count, 0)
  }

  // Review Focus 5
  function test_escape_at_the_project_step_does_nothing_while_starting() {
    var d = projectStep({ dispatchState: "starting" })
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 0)
    compare(picks.count, 0)
  }

  // 13
  function test_the_project_step_focuses_its_key_item() {
    var d = projectStep()
    compare(d.focusItem, H.find(d, "dispatchProjectKeys"))
    d.step = ""
    compare(d.focusItem, H.find(d, "dispatchBase"))
    d.form = null
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  // 14
  function test_the_cursor_follows_its_root_when_the_rows_change() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 2, "on ori")
    var rows = tc.fixtureRows()
    d.projectRows = [rows[3], rows[2], rows[0], rows[1]]
    compare(d.projectCursor, 1, "still on ori")
    verify(H.find(d, "dispatchProjectRow1").hasCursor)
    var off = tc.fixtureRows()
    off[2].enabled = false
    off[2].reason = "board unreachable: tree read failed"
    d.projectRows = off
    compare(d.projectCursor, 0, "ori disabled: the first enabled row")
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 1)
    d.step = ""
    compare(d.projectCursor, -1)
    d.step = "project"
    compare(d.projectCursor, 0, "a new project step starts over")
    compare(picks.count, 0)
  }

  // Review Focus 2
  function test_rows_shrinking_past_the_cursor_put_it_on_the_first_enabled_row() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(d.projectCursor, 2)
    d.projectRows = [tc.fixtureRows()[1]]
    compare(d.projectCursor, 0)
    d.projectRows = [tc.fixtureRows()[3]]
    compare(d.projectCursor, -1, "the only row left is disabled")
    compare(H.find(d, "dispatchProjectEmpty").text, "No project's board can be read")
  }

  // 15
  function test_a_long_list_keeps_the_cursor_in_view() {
    var rows = []
    for (var i = 0; i < 30; i++)
      rows.push({ root: "/r/p" + i, name: "project " + i, open: false, enabled: true, reason: "" })
    var d = projectStep({ projectRows: rows })
    var list = H.find(d, "dispatchProjectList")
    verify(list.contentHeight > list.height, "the list scrolls")
    compare(list.contentY, 0)
    d.focusItem.forceActiveFocus()
    for (var k = 0; k < 29; k++) keyClick(Qt.Key_Down)
    compare(d.projectCursor, 29)
    var last = H.find(d, "dispatchProjectRow29")
    verify(list.contentY > 0, "the list scrolled")
    verify(last.y >= list.contentY, "the last row's top is in view")
    verify(last.y + last.height <= list.contentY + list.height + 0.5, "the last row's bottom is in view")
  }

  // 16
  function test_other_keys_pass_through_to_the_owner() {
    var host = createTemporaryObject(hostC, tc)
    var d = host.dialog
    picks.target = d; cancels.target = d
    picks.clear(); cancels.clear()
    d.step = "project"
    d.projectRows = tc.fixtureRows()
    d.shown = true
    wait(30)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_A)
    compare(host.passed, 1, "a letter is not accepted")
    keyClick(Qt.Key_Down)
    compare(host.passed, 1, "Down is accepted")
    compare(d.projectCursor, 1)
    compare(picks.count, 0)
    compare(cancels.count, 0)
  }

  // Review Focus 1
  function test_enter_after_leaving_the_project_step_picks_nothing() {
    var d = projectStep()
    H.find(d, "dispatchProjectKeys").forceActiveFocus()
    d.step = "target"
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(picks.count, 0)
  }

  // 7
  function test_a_click_on_an_enabled_row_picks_it() {
    var d = projectStep()
    click(H.find(d, "dispatchProjectRow2"))
    compare(d.projectCursor, 2)
    compare(picks.count, 1)
    compare(picks.signalArguments[0][0], "/home/u/Code/ori")
    compare(cancels.count, 0)
  }

  // 8
  function test_a_disabled_row_ignores_hover_and_click() {
    var d = projectStep()
    var row = H.find(d, "dispatchProjectRow3")
    wait(30)
    mouseMove(row, row.width / 2, row.height / 2)
    wait(30)
    compare(d.projectCursor, 0)
    click(row)
    compare(d.projectCursor, 0)
    compare(picks.count, 0)
    compare(cancels.count, 0)
    compare(row.hoverCursorShape, Qt.ArrowCursor)
  }

  // 9
  function test_hovering_an_enabled_row_moves_the_cursor() {
    var d = projectStep()
    var row = H.find(d, "dispatchProjectRow2")
    wait(30)
    mouseMove(row, row.width / 2, row.height / 2)
    tryCompare(d, "projectCursor", 2)
    verify(row.hasCursor)
    compare(picks.count, 0)
    compare(row.hoverCursorShape, Qt.PointingHandCursor)
  }

  // ---- the target step --------------------------------------------------

  // 3
  function test_the_target_step_heads_the_card_with_back_and_cancel() {
    var d = make({ step: "target", projectName: "agent-manager" })
    var heading = H.find(d, "dispatchHeading")
    compare(heading.text, "Dispatch · 2 Target in agent-manager")
    verify(H.find(d, "dispatchBack").visible, "Back")
    verify(H.find(d, "dispatchBack").enabled, "Back is enabled")
    verify(H.find(d, "dispatchCancel").visible, "Cancel")
    verify(!H.find(d, "dispatchStart").visible, "no Start")
    verify(!H.find(d, "dispatchProjectList").visible, "no project list")
    verify(!H.find(d, "dispatchProjectEmpty").visible, "no project empty line")
    d.projectName = ""
    compare(heading.text, "Dispatch · 2 Target")
    d.step = "form"
    compare(heading.text, "Dispatch")
    d.step = "project"
    compare(heading.text, "Dispatch · 1 Project")
  }

  // 3: every part the project step hides is hidden at the target step too.
  function test_the_target_step_hides_the_form_steps_parts_data() {
    return tc.test_the_project_step_hides_the_form_steps_parts_data()
  }

  function test_the_target_step_hides_the_form_steps_parts(data) {
    var d = make(data.over)
    if (data.arm) click(H.find(d, "dispatchStart"))
    verify(H.find(d, data.name).visible, "shown at the form step")
    d.step = "target"
    verify(!H.find(d, data.name).visible, "hidden at the target step")
    d.step = "form"
    verify(H.find(d, data.name).visible, "shown again at the form step")
  }

  // 15, 21
  function test_back_shows_at_the_target_and_form_steps_only() {
    var d = make()
    var back = H.find(d, "dispatchBack")
    verify(!back.visible, "no Back on a card-opened dialog")
    d.step = "project"
    verify(!back.visible, "no Back at the project step")
    d.step = "target"
    verify(back.visible, "Back at the target step")
    verify(back.enabled)
    click(back)
    compare(backs.count, 1)
    d.step = "form"
    verify(back.visible, "Back at the form step")
    verify(back.enabled)
    verify(H.find(d, "dispatchStart").visible, "the form step keeps Start")
    verify(H.find(d, "dispatchForm").visible, "and its form")
    click(back)
    compare(backs.count, 2)
    compare(cancels.count, 0)
    compare(starts.count, 0)
  }

  // 21
  function test_back_at_the_form_step_is_disabled_while_starting() {
    var d = make({ step: "form", dispatchState: "starting" })
    var back = H.find(d, "dispatchBack")
    verify(back.visible)
    verify(!back.enabled)
    click(back)
    compare(backs.count, 0)
    d.back()
    compare(backs.count, 0, "back() refuses while starting")
  }

  // 22
  function test_the_card_opened_dialog_has_no_back_data() {
    return tc.dispatchStates.map(function(s) { return { tag: s, state: s } })
  }

  function test_the_card_opened_dialog_has_no_back(data) {
    var d = make({ dispatchState: data.state })
    verify(!H.find(d, "dispatchBack").visible)
    var base = H.find(d, "dispatchBase")
    base.forceActiveFocus()
    base.cursorPosition = base.text.length
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 0)
    if (d.editable) compare(base.text, "mai", "Backspace edits the field")
    d.back()
    compare(backs.count, 0, "back() refuses at step \"\"")
  }

  // RunStore's dispatchTargetRows for one milestone, as Runs.dispatchTargets
  // builds them: the board row, then the tree in order.
  function targetFixture() {
    return [
      { key: "board", level: "board", card: "board", label: "Whole board", depth: 0 },
      { key: "card:aaaa1111-0000-4000-8000-000000000001", level: "milestone",
        card: { id: "aaaa1111-0000-4000-8000-000000000001", title: "M4 Run story", status: "todo", depth: 0 },
        label: "Milestone \"M4 Run story\"", depth: 0 },
      { key: "card:bbbb2222-0000-4000-8000-000000000002", level: "story",
        card: { id: "bbbb2222-0000-4000-8000-000000000002", title: "Story dispatch backend", status: "todo",
                depth: 1 },
        label: "Story \"Story dispatch backend\"", depth: 1 },
      { key: "card:cccc3333-0000-4000-8000-000000000003", level: "subtask",
        card: { id: "cccc3333-0000-4000-8000-000000000003", title: "1.2 runs.js: targets", status: "todo",
                depth: 2 },
        label: "Subtask \"1.2 runs.js: targets\"", depth: 2 },
      { key: "card:dddd4444-0000-4000-8000-000000000004", level: "subtask",
        card: { id: "dddd4444-0000-4000-8000-000000000004", title: "1.3 dialog rows", status: "todo", depth: 2 },
        label: "Subtask \"1.3 dialog rows\"", depth: 2 }
    ]
  }

  // The dialog at the target step over targetFixture(); `over` replaces any
  // prop. The mouse is parked on the backdrop so no row is hovered.
  function targetStep(over) {
    var d = make(Object.assign({ step: "target", targetRows: tc.targetFixture(), projectName: "agent-manager" },
                               over || {}))
    mouseMove(d, 1, 1)
    return d
  }

  // How many target rows are on screen: dispatchTargetRow0, 1, … up to the
  // first one missing. The wait lets a replaced row finish being deleted.
  function shownRowCount(d) {
    wait(0)
    var n = 0
    while (H.find(d, "dispatchTargetRow" + n)) n++
    return n
  }

  // 1
  function test_the_target_step_lists_each_row_with_its_level_and_id() {
    var d = targetStep()
    compare(shownRowCount(d), 5)
    var titles = ["Whole board", "M4 Run story", "Story dispatch backend", "1.2 runs.js: targets", "1.3 dialog rows"]
    var levels = ["", "Milestone", "Story", "Subtask", "Subtask"]
    var ids = ["", "aaaa1111", "bbbb2222", "cccc3333", "dddd4444"]
    for (var i = 0; i < 5; i++) {
      compare(H.find(d, "dispatchTargetTitle" + i).text, titles[i], "title " + i)
      var level = H.find(d, "dispatchTargetLevel" + i)
      compare(level.text, levels[i], "level " + i)
      compare(level.visible, levels[i] !== "", "level " + i + " visible")
      var id = H.find(d, "dispatchTargetId" + i)
      compare(id.text, ids[i], "id " + i)
      compare(id.visible, ids[i] !== "", "id " + i + " visible")
    }
    verify(!H.find(d, "dispatchTargetStatus").visible, "no status line over rows")
    verify(sameColour(H.find(d, "dispatchTargetLevel1").color, d.theme.dim), "the level word is dim")
    verify(sameColour(H.find(d, "dispatchTargetId1").color, d.theme.dim), "the id is dim")
    verify(sameColour(H.find(d, "dispatchTargetTitle1").color, d.theme.foreground), "the title is foreground")
  }

  // 2 (the line, not the title, is indented: see the plan's deviation note)
  function test_target_rows_are_indented_by_depth() {
    var d = targetStep()
    var want = [0, 0, 16, 32, 32]
    for (var i = 0; i < 5; i++)
      compare(H.find(d, "dispatchTargetLine" + i).x, want[i], "row " + i)
  }

  // 3
  function test_the_filter_and_the_list_show_only_at_the_target_step_data() {
    return [
      { tag: "card", step: "", shown: false },
      { tag: "project", step: "project", shown: false },
      { tag: "form", step: "form", shown: false },
      { tag: "target", step: "target", shown: true }
    ]
  }

  function test_the_filter_and_the_list_show_only_at_the_target_step(data) {
    var d = targetStep({ step: data.step })
    var filter = H.find(d, "dispatchTargetFilter")
    compare(filter.visible, data.shown)
    compare(H.find(d, "dispatchTargetList").visible, data.shown)
    compare(filter.placeholderText, "Filter by title or id…")
    compare(filter.width, H.find(d, "dispatchHeading").parent.width, "full card width")
    if (!data.shown) compare(shownRowCount(d), 0, "no rows off the target step")
  }

  // 4, 15
  function test_loading_reads_the_board_and_shows_no_row_data() {
    return [{ tag: "no-rows", rows: [] }, { tag: "rows", rows: tc.targetFixture() }]
  }

  function test_loading_reads_the_board_and_shows_no_row(data) {
    var d = targetStep({ targetRows: data.rows, targetLoading: true })
    var status = H.find(d, "dispatchTargetStatus")
    verify(status.visible)
    compare(status.text, "Reading the board…")
    compare(shownRowCount(d), 0)
    verify(H.find(d, "dispatchTargetFilter").visible, "the filter shows while loading")
    click(H.find(d, "dispatchBack"))
    compare(backs.count, 1, "Back cancels the read")
    d.targetRows = tc.targetFixture()
    d.targetLoading = false
    compare(shownRowCount(d), 5)
    verify(!status.visible)
  }

  // 5
  function test_an_empty_or_malformed_target_list_says_no_target_matches_data() {
    return [
      { tag: "empty", rows: [] },
      { tag: "null", rows: null },
      { tag: "undefined", rows: undefined },
      { tag: "object", rows: {} },
      { tag: "string", rows: "x" }
    ]
  }

  function test_an_empty_or_malformed_target_list_says_no_target_matches(data) {
    var d = targetStep({ targetRows: data.rows })
    var status = H.find(d, "dispatchTargetStatus")
    verify(status.visible)
    compare(status.text, "No target matches")
    compare(shownRowCount(d), 0)
    click(H.find(d, "dispatchBack"))
    compare(backs.count, 1)
  }

  // 6, Review Focus 4
  function test_the_filter_matches_titles_case_blind_data() {
    return [
      { tag: "lower", query: "dialog", titles: ["1.3 dialog rows"] },
      { tag: "upper", query: "DIALOG", titles: ["1.3 dialog rows"] },
      { tag: "padded", query: "  dialog ", titles: ["1.3 dialog rows"] },
      { tag: "blank", query: "   ",
        titles: ["Whole board", "M4 Run story", "Story dispatch backend", "1.2 runs.js: targets", "1.3 dialog rows"] }
    ]
  }

  function test_the_filter_matches_titles_case_blind(data) {
    var d = targetStep()
    H.find(d, "dispatchTargetFilter").text = data.query
    compare(shownRowCount(d), data.titles.length)
    for (var i = 0; i < data.titles.length; i++)
      compare(H.find(d, "dispatchTargetTitle" + i).text, data.titles[i])
    verify(!H.find(d, "dispatchTargetStatus").visible)
  }

  // 7
  function test_the_filter_matches_the_short_id_not_the_level_word() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    filter.text = "cccc33"
    compare(shownRowCount(d), 1)
    compare(H.find(d, "dispatchTargetTitle0").text, "1.2 runs.js: targets")
    filter.text = "story"
    compare(shownRowCount(d), 2)
    compare(H.find(d, "dispatchTargetTitle0").text, "M4 Run story")
    compare(H.find(d, "dispatchTargetTitle1").text, "Story dispatch backend")
    filter.text = "subtask"
    compare(shownRowCount(d), 0, "the level word is not matched")
    filter.text = "0000-4000"
    compare(shownRowCount(d), 0, "only the short id is matched, not the whole id")
  }

  // 8
  function test_a_filter_matching_nothing_says_no_target_matches() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    filter.text = "zzz"
    compare(shownRowCount(d), 0)
    compare(H.find(d, "dispatchTargetStatus").text, "No target matches")
    filter.text = ""
    compare(shownRowCount(d), 5)
    verify(!H.find(d, "dispatchTargetStatus").visible)
  }

  // 25, Review Focus 1
  function test_malformed_target_rows() {
    var rows = [
      { level: "subtask", card: { id: "ffff0000-x", title: "No key" }, depth: 2 },
      42,
      null,
      { key: "", level: "story", card: { id: "ffff1111-x", title: "Empty key" }, depth: 1 },
      { key: "card:nocard", level: "subtask", card: null, depth: 1 },
      { key: "card:neg", level: "story", card: { id: "eeee5555-0000", title: "Negative" }, depth: -1 },
      { key: "card:frac", level: "story", card: { id: "eeee6666-0000", title: "Fraction" }, depth: 1.5 },
      { key: "card:inf", level: "story", card: { id: "eeee7777-0000", title: "Infinite" }, depth: Infinity },
      { key: "card:text", level: "story", card: { id: "eeee8888-0000", title: "Text depth" }, depth: "2" },
      { key: "card:odd", level: "epic", card: { id: 7, title: 9 } }
    ]
    var d = targetStep({ targetRows: rows })
    compare(shownRowCount(d), 6, "no key, a number, null and an empty key give no row")
    compare(H.find(d, "dispatchTargetTitle0").text, "", "no card: no title")
    verify(!H.find(d, "dispatchTargetId0").visible, "no card: no id")
    compare(H.find(d, "dispatchTargetLevel0").text, "Subtask")
    compare(H.find(d, "dispatchTargetLine0").x, 16, "a valid depth still indents")
    for (var i = 1; i <= 4; i++)
      compare(H.find(d, "dispatchTargetLine" + i).x, 0, "row " + i + " reads as depth 0")
    compare(H.find(d, "dispatchTargetLevel5").text, "", "an unknown level has no word")
    verify(!H.find(d, "dispatchTargetLevel5").visible)
    compare(H.find(d, "dispatchTargetTitle5").text, "", "a non-string title reads as empty")
    compare(H.find(d, "dispatchTargetId5").text, "", "a non-string id reads as empty")
    compare(H.find(d, "dispatchTargetLine5").x, 0, "a missing depth reads as 0")
  }

  // Review Focus 5
  function test_a_long_target_title_elides_and_keeps_its_id() {
    var long = new Array(30).join("A very long subtask title ")
    var rows = [{ key: "card:long", level: "subtask", card: { id: "abcd1234-0000", title: long }, depth: 2 }]
    var d = targetStep({ targetRows: rows })
    var title = H.find(d, "dispatchTargetTitle0")
    var row = H.find(d, "dispatchTargetRow0")
    var id = H.find(d, "dispatchTargetId0")
    compare(title.elide, Text.ElideRight)
    verify(title.truncated, "the title is cut, not wrapped")
    compare(title.lineCount, 1)
    verify(id.visible)
    var idRight = id.mapToItem(row, id.width, 0).x
    verify(idRight <= row.width + 0.5, "the id stays inside the row")
    verify(H.find(d, "dispatchTargetLevel0").visible, "the level word stays")
  }

  // 26
  function test_nulling_every_object_prop_at_the_target_step_and_destroying_is_quiet() {
    var d = targetStep()
    d.theme = null
    d.target = null
    d.form = null
    d.preview = null
    d.targetRows = null
    wait(0)
    compare(H.find(d, "dispatchTargetStatus").text, "No target matches")
    compare(edits.count, 0)
    d.destroy()
    wait(0)
  }

  // Types `text` into the item with the active focus, one key per character.
  function typeText(text) {
    for (var i = 0; i < text.length; i++) keyClick(text[i])
  }

  // 9
  function test_the_cursor_starts_on_row_0_or_on_target_key() {
    var d = targetStep()
    compare(d.targetCursor, 0)
    verify(H.find(d, "dispatchTargetRow0").hasCursor, "row 0 is highlighted")
    var e = targetStep({ targetKey: "card:cccc3333-0000-4000-8000-000000000003" })
    compare(e.targetCursor, 3)
    verify(H.find(e, "dispatchTargetRow3").hasCursor)
    var f = targetStep({ targetKey: "card:gone" })
    compare(f.targetCursor, 0, "a key naming no row lands on row 0")
    f.targetKey = "card:bbbb2222-0000-4000-8000-000000000002"
    compare(f.targetCursor, 2, "a new targetKey moves the cursor onto its row")
    f.targetKey = "card:gone"
    compare(f.targetCursor, 2, "a key naming no row leaves it")
    compare(make().targetCursor, -1, "no cursor at step \"\"")
    compare(targetStep({ step: "project" }).targetCursor, -1, "none at the project step")
    compare(targetStep({ step: "form" }).targetCursor, -1, "none at the form step")
  }

  // 10
  function test_down_and_up_move_the_cursor_from_the_filter_and_stop_at_the_ends() {
    var host = createTemporaryObject(hostC, tc)
    var d = host.dialog
    d.step = "target"
    d.targetRows = tc.targetFixture()
    d.shown = true
    wait(30)
    mouseMove(d, 1, 1)
    d.focusItem.forceActiveFocus()
    for (var i = 1; i <= 4; i++) {
      keyClick(Qt.Key_Down)
      compare(d.targetCursor, i)
    }
    keyClick(Qt.Key_Down)
    compare(d.targetCursor, 4, "Down on the last row stays")
    for (var k = 0; k < 5; k++) keyClick(Qt.Key_Up)
    compare(d.targetCursor, 0, "Up on the first row stays")
    compare(host.passed, 0, "Down and Up are accepted")
    compare(H.find(d, "dispatchTargetFilter").text, "", "the filter text is unchanged")
  }

  // 11
  function test_enter_picks_the_cursor_target_row_data() {
    return [{ tag: "return", key: Qt.Key_Return }, { tag: "enter", key: Qt.Key_Enter }]
  }

  function test_enter_picks_the_cursor_target_row(data) {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(data.key)
    compare(targetPicks.count, 1)
    compare(targetPicks.signalArguments[0][0], "card:aaaa1111-0000-4000-8000-000000000001")
    H.find(d, "dispatchTargetFilter").text = "dialog"
    compare(d.targetCursor, 0)
    keyClick(data.key)
    compare(targetPicks.count, 2)
    compare(targetPicks.signalArguments[1][0], "card:dddd4444-0000-4000-8000-000000000004",
            "the shown row's key, not the unfiltered row 0")
    compare(picks.count, 0, "no projectChosen at the target step")
    compare(starts.count, 0)
    compare(cancels.count, 0)
  }

  // 4, 5, 8: no cursor and no pick while loading, with no rows or no match.
  function test_with_no_shown_row_there_is_no_cursor_and_enter_picks_nothing_data() {
    return [
      { tag: "loading", over: { targetLoading: true }, filter: "" },
      { tag: "empty", over: { targetRows: [] }, filter: "" },
      { tag: "null", over: { targetRows: null }, filter: "" },
      { tag: "string", over: { targetRows: "x" }, filter: "" },
      { tag: "no-match", over: {}, filter: "zzz" }
    ]
  }

  function test_with_no_shown_row_there_is_no_cursor_and_enter_picks_nothing(data) {
    var d = targetStep(data.over)
    H.find(d, "dispatchTargetFilter").text = data.filter
    compare(d.targetCursor, -1)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(d.targetCursor, -1)
    compare(targetPicks.count, 0)
  }

  // 4
  function test_loading_ending_puts_the_cursor_on_row_0() {
    var d = targetStep({ targetLoading: true })
    compare(d.targetCursor, -1)
    d.targetLoading = false
    compare(d.targetCursor, 0)
  }

  // 8
  function test_clearing_a_filter_that_matched_nothing_brings_the_cursor_back() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    filter.text = "zzz"
    compare(d.targetCursor, -1)
    filter.text = ""
    compare(d.targetCursor, 0)
  }

  // 12
  function test_the_filter_keeps_the_cursor_on_its_key() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    for (var i = 0; i < 4; i++) keyClick(Qt.Key_Down)
    compare(d.targetCursor, 4, "on 1.3 dialog rows")
    typeText("rows")
    compare(H.find(d, "dispatchTargetFilter").text, "rows")
    compare(shownRowCount(d), 1)
    compare(d.targetCursor, 0, "still on 1.3 dialog rows, now row 0")
    H.find(d, "dispatchTargetFilter").text = "story"
    compare(H.find(d, "dispatchTargetTitle0").text, "M4 Run story")
    compare(d.targetCursor, 0, "its row is hidden: shown row 0")
  }

  // 14
  function test_backspace_in_an_empty_filter_goes_back() {
    var d = targetStep()
    var filter = H.find(d, "dispatchTargetFilter")
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 1)
    typeText("ab")
    keyClick(Qt.Key_Backspace)
    compare(filter.text, "a", "Backspace deletes one character")
    compare(backs.count, 1, "and emits nothing")
    keyClick(Qt.Key_Backspace)
    compare(filter.text, "")
    compare(backs.count, 1, "the last character is deleted, not a Back")
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 2, "Backspace in the now-empty field goes back")
    compare(cancels.count, 0)
  }

  // 4: Backspace in an empty filter still goes back while loading.
  function test_backspace_goes_back_while_loading() {
    var d = targetStep({ targetLoading: true })
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Backspace)
    compare(backs.count, 1)
  }

  // 16
  function test_escape_on_the_filter_cancels() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Escape)
    compare(cancels.count, 1)
    compare(backs.count, 0)
    compare(targetPicks.count, 0)
  }

  // 17
  function test_the_target_step_focuses_its_filter() {
    var d = targetStep()
    compare(d.focusItem, H.find(d, "dispatchTargetFilter"))
    d.step = "project"
    compare(d.focusItem, H.find(d, "dispatchProjectKeys"))
    d.step = ""
    compare(d.focusItem, H.find(d, "dispatchBase"))
    d.form = null
    compare(d.focusItem, H.find(d, "dispatchCancel"))
  }

  // 18
  function test_the_filter_is_cleared_on_re_entry() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    typeText("zz")
    compare(shownRowCount(d), 0)
    d.step = "form"
    d.step = "target"
    compare(H.find(d, "dispatchTargetFilter").text, "")
    compare(shownRowCount(d), 5)
    compare(d.targetCursor, 0)
    d.shown = false
    H.find(d, "dispatchTargetFilter").text = "zz"
    d.shown = true
    compare(H.find(d, "dispatchTargetFilter").text, "", "showing the dialog at the step clears it too")
  }

  // 19
  function test_back_from_the_form_keeps_the_picked_row() {
    var d = targetStep({ step: "form", targetKey: "card:dddd4444-0000-4000-8000-000000000004" })
    compare(d.targetCursor, -1)
    d.step = "target"
    compare(d.targetCursor, 4)
    verify(H.find(d, "dispatchTargetRow4").hasCursor)
  }

  // 23
  function test_signals_stay_in_their_step() {
    var d = projectStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 0, "no targetPicked at the project step")
    compare(backs.count, 0)
    var e = make()
    e.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(targetPicks.count, 0, "no targetPicked at step \"\"")
    var f = targetStep()
    f.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 1)
    compare(picks.count, 0, "no projectChosen at the target step")
  }

  // 24
  function test_rows_arriving_keep_target_keys_row() {
    var d = targetStep({ targetRows: [], targetLoading: true,
                         targetKey: "card:cccc3333-0000-4000-8000-000000000003" })
    compare(d.targetCursor, -1)
    d.targetRows = tc.targetFixture()
    compare(d.targetCursor, -1, "still loading")
    d.targetLoading = false
    compare(d.targetCursor, 3)
  }

  // Review Focus 3
  function test_a_re_read_drops_the_cursor_until_the_rows_return() {
    var d = targetStep()
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Down)
    compare(d.targetCursor, 2)
    d.targetLoading = true
    compare(d.targetCursor, -1)
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 0)
    d.targetLoading = false
    compare(d.targetCursor, 0, "no targetKey: row 0")
    d.targetLoading = true
    d.targetKey = "card:dddd4444-0000-4000-8000-000000000004"
    compare(d.targetCursor, -1, "a key arriving while loading does not move it")
    d.targetLoading = false
    compare(d.targetCursor, 4)
  }

  // Review Focus 2
  function test_keys_on_the_filter_after_leaving_the_target_step_do_nothing() {
    var d = targetStep()
    H.find(d, "dispatchTargetFilter").forceActiveFocus()
    d.step = "form"
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Backspace)
    compare(targetPicks.count, 0)
    compare(backs.count, 0)
    compare(d.targetCursor, -1)
  }

  // 25: a row without a card is still picked by its key.
  function test_a_row_without_a_card_is_picked_by_its_key() {
    var d = targetStep({ targetRows: [{ key: "card:nocard", level: "subtask", card: null, depth: 1 }] })
    compare(d.targetCursor, 0)
    d.focusItem.forceActiveFocus()
    keyClick(Qt.Key_Return)
    compare(targetPicks.count, 1)
    compare(targetPicks.signalArguments[0][0], "card:nocard")
  }
}
