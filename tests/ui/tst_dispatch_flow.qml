// tests/ui/tst_dispatch_flow.qml
// The dispatch around the whole panel (S3 4.2): each entry point (the card
// detail's Dispatch, d on the board list, the Runs toolbar's Start run) opens
// the mounted dialog; a story opening on itself, the subtask's lines and
// two-click Start, Escape, the focus, and where a start takes the user. The
// dialog's own rendering is tests/ui/components/tst_dispatch_dialog.qml; the
// store's rules are tests/core/stores/tst_run_store.qml.
import QtQuick
import QtTest
import "../helpers/find.js" as H

TestCase {
  id: tc
  name: "DispatchFlow"
  when: windowShown
  visible: true
  width: 900; height: 700
  Component { id: hostC; Item { width: 900; height: 700 } }

  property var pA: ({ root_path: "/home/u/a", name: "alpha" })
  property var pB: ({ root_path: "/home/u/b", name: "beta" })

  function card(id, title, status, children, blockedBy) {
    var c = { id: id, title: title, status: status, description: "d", children: children || [] }
    if (blockedBy !== undefined) c.blocked_by = blockedBy
    return c
  }

  // m1 > s1 > t0 (done), t1 (blocked by t0, issue i1 and an unknown id), t2
  // (no blocked_by at all); m9 is a done milestone.
  function roots() {
    return [
      card("m1", "M one", "todo", [
        card("s1", "Story one", "todo", [
          card("t0", "Prep", "done", [], []),
          card("t1", "Do it", "todo", [], ["t0", "i1", "ghost"]),
          card("t2", "Loose end", "todo")
        ])
      ]),
      card("m9", "M nine", "done")
    ]
  }

  function run(id) {
    return { id: id, repo_dir: "/home/u/a", milestone_id: "M one", status: "started", started_at: "",
             lease: { pid: 1, host: "h", heartbeat_at: "", accepting: true, live: true },
             rows: [], tree: { stories: [], subtasks: [] } }
  }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    // No helper may really run here (start-run.py starts am): every script
    // path leads nowhere, and each launch a test cares about is answered
    // through reply() before the event loop could deliver its real exit.
    p.app.backendDir = "/plugin/core/backend/"
    p.opened = true
    p.app.projects.stateLoaded = true
    p.app.projects.applyProjectsList([pA, pB])
    if (!p.app.projects.selectedProject) { fail("project A is selected"); return null }
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.extras.extrasLoading = false
    p.app.runs.snapshotRunner.cancel()
    p.app.runControl.settingsLoadRunner.cancel()
    p.app.runControl.runSettingsLoadRunner.cancel()
    // A stored verify command, so a fresh form passes the store's checks.
    p.app.runControl.applyRunSettings(p.app.runs.project, { verify: ["uv run pytest"] })
    p.app.board.applyTreeData(roots())
    p.app.board.applyIssueData([{ id: "i1", title: "Broken build", status: "open" }])
    p.app.runs.runs = [run("run-0000000000a1")]
    wait(50)
    return p
  }

  // A helper's reply, delivered the way its Process would deliver it.
  function reply(proc, text) {
    proc.outText = text
    proc.exited(0)
  }

  // Answers the --defaults lookup and, for a milestone or the board, the dry
  // run it launches: the dispatch lands in ready.
  function toReady(p) {
    reply(p.app.runDispatch.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    if (p.app.runDispatch.dispatchState === "previewing")
      reply(p.app.runDispatch.dispatchPreviewRunner.current, '{"ok":true,"data":{"max_concurrent":4,"levels":[]}}')
    compare(p.app.runDispatch.dispatchState, "ready")
  }

  // The card detail of `id`, and a click on its Dispatch.
  function dispatchCard(p, id) {
    p.navigator.openCard(id)
    wait(50)
    compare(p.app.nav.viewMode, "entry")
    H.find(p, "cardDispatchButton").clicked()
    wait(50)
  }

  function text(p, name) { return String(H.find(p, name).text) }

  // ---- entry points

  // 19
  function test_the_card_detail_dispatch_opens_the_dialog_on_that_card() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "m1")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    toReady(p)
    compare(H.find(p, "dispatchStart").enabled, true)
    compare(text(p, "dispatchStart"), "Start run", "a milestone starts on one click")
    wait(50)
    compare(p.focusItem.objectName, "dispatchBase")
    verify(H.find(p, "dispatchBase").activeFocus, "the dialog has the keyboard")
  }

  // 20
  function test_d_on_the_board_list_opens_the_dialog_on_the_cursor_card_without_typing() {
    var p = make(); if (!p) return
    p.navigator.showSection("board")
    p.app.nav.cursorIndex = 0
    compare(p.app.board.boardCards[0].id, "m1")
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    keyClick("d")
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(p.dispatchCardId, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(String(field.text), "", "the handled letter was not typed")
    compare(p.app.nav.searchQuery, "")
  }

  // 22
  function test_a_story_opens_the_dialog_on_itself() {
    var p = make(); if (!p) return
    dispatchCard(p, "s1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "s1")
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"M one\")")
    compare(p.app.runDispatch.dispatchSuggest, null)
    compare(H.find(p, "dispatchSuggest").visible, false, "no milestone offer")
  }

  // A story's preview refused with `previewText`, after its defaults lookup.
  function refuseStory(p, previewText) {
    dispatchCard(p, "s1")
    reply(p.app.runDispatch.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    compare(p.app.runDispatch.dispatchState, "previewing")
    reply(p.app.runDispatch.dispatchPreviewRunner.current, previewText)
    compare(p.app.runDispatch.dispatchState, "refused")
  }

  // 9, Review Focus 1 and 3
  function test_a_blocked_story_retargets_to_its_milestone() {
    var p = make(); if (!p) return
    refuseStory(p, '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s0"}}')
    compare(text(p, "dispatchRefusal"), "Story blocked by s0")
    compare(H.find(p, "dispatchStart").enabled, false)
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true)
    compare(String(offer.text), "Dispatch the milestone instead")
    offer.clicked()
    compare(p.app.runDispatch.dispatchTarget.level, "milestone")
    compare(JSON.stringify(p.app.runDispatch.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(p.dispatchCardId, "m1")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(offer.visible, false)
    compare(H.find(p, "dispatchDialog").visible, true)
    offer.clicked()
    compare(p.dispatchCardId, "m1", "a second click changes nothing")
    compare(p.app.runDispatch.dispatchTarget.level, "milestone")
    compare(p.app.runDispatch.dispatchState, "previewing")
    wait(50)
    compare(p.focusItem.objectName, "dispatchBase")
    verify(H.find(p, "dispatchBase").activeFocus, "the retargeted form has the keyboard")
    toReady(p)
    compare(H.find(p, "dispatchStart").enabled, true)
  }

  // Review Focus 2
  function test_a_refused_retarget_leaves_the_story_dialog() {
    var p = make(); if (!p) return
    var dialog = H.find(p, "dispatchDialog")
    dispatchCard(p, "s1")
    compare(p.dispatchSuggestion, null)
    dialog.suggestionRequested()
    compare(p.dispatchCardId, "s1", "no suggestion: nothing happens")
    compare(p.app.runDispatch.dispatchTarget.level, "story")
    p.app.runDispatch.closeDispatch()
    refuseStory(p, '{"ok":false,"error":{"type":"StoryBlockedError","message":"Story blocked by s0"}}')
    verify(p.dispatchSuggestion !== null, "the milestone is offered")
    // The state moved on between render and click: the store refuses.
    p.app.runDispatch.dispatchState = "previewing"
    dialog.suggestionRequested()
    compare(p.dispatchCardId, "s1")
    compare(p.app.runDispatch.dispatchTarget.level, "story")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"M one\")")
    p.app.runDispatch.closeDispatch()
  }

  // 10
  function test_a_finished_or_claimed_story_says_why_data() {
    return [
      { tag: "finished", preview: '{"ok":true,"data":{"integrate":null,"levels":[]}}',
        text: "Nothing left to run" },
      { tag: "claimed", preview: '{"ok":false,"error":{"type":"ClaimedError","message":"Card s1 is claimed by run r-other"}}',
        text: "Card s1 is claimed by run r-other" }
    ]
  }

  function test_a_finished_or_claimed_story_says_why(data) {
    var p = make(); if (!p) return
    refuseStory(p, data.preview)
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\" (milestone \"M one\")")
    compare(text(p, "dispatchRefusal"), data.text)
    compare(H.find(p, "dispatchStart").enabled, false)
    compare(H.find(p, "dispatchSuggest").visible, false)
  }

  // 23
  function test_a_subtask_shows_its_story_and_blockers_and_starts_on_the_second_click() {
    var p = make(); if (!p) return
    dispatchCard(p, "t1")
    compare(text(p, "dispatchTarget"), "Target   Subtask \"Do it\"")
    toReady(p)
    compare(text(p, "dispatchStory"), "Story   \"Story one\"")
    compare(text(p, "dispatchBlocked"), "Blocked by: \"Prep\" (Done), \"Broken build\" (Issue · open), ghost (not on this board)")
    var start = H.find(p, "dispatchStart")
    start.clicked()
    compare(p.app.runDispatch.dispatchState, "ready", "the first click only arms")
    compare(p.app.runDispatch.dispatchStartRunners.length, 0)
    compare(String(start.text), "Confirm start")
    compare(H.find(p, "dispatchConfirmNote").visible, true)
    start.clicked()
    compare(p.app.runDispatch.dispatchState, "starting")
    compare(p.app.runDispatch.dispatchStartRunners.length, 1)
    p.app.runDispatch.dispatchStartRunners[0].cancel()
  }

  // Review Focus 4
  function test_a_subtask_without_blockers_says_so() {
    var p = make(); if (!p) return
    dispatchCard(p, "t2")
    toReady(p)
    compare(text(p, "dispatchStory"), "Story   \"Story one\"")
    compare(text(p, "dispatchBlocked"), "Blocked by: nothing")
  }

  // ---- Escape and the focus

  // 28
  function test_escape_closes_the_dialog_and_gives_the_focus_back() {
    var p = make(); if (!p) return
    dispatchCard(p, "s1")
    compare(H.find(p, "dispatchDialog").visible, true)
    var kc = H.find(p, "keyCatcher")
    kc.closeRequested()
    compare(p.app.runDispatch.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "entry", "that Escape closed the dialog only")
    compare(p.opened, true)
    wait(50)
    compare(p.focusItem.objectName, "keyCatcher")
    verify(kc.activeFocus, "the focus is back on the card")
  }

  // 28
  function test_escape_while_starting_does_nothing() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    toReady(p)
    compare(p.app.runDispatch.dispatchStart(), true)
    p.app.runDispatch.dispatchStartRunners[0].cancel()
    H.find(p, "keyCatcher").closeRequested()
    compare(p.app.runDispatch.dispatchState, "starting")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.app.nav.viewMode, "entry", "no Back")
    compare(p.opened, true, "no panel close")
  }

  // 29
  function test_a_re_preview_leaves_the_caret_in_the_field_being_typed_in() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    toReady(p)
    wait(50)
    var prefix = H.find(p, "dispatchPrefix")
    prefix.forceActiveFocus()
    prefix.text = "m-one-b"
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(p.app.runDispatch.dispatchForm.prefix, "m-one-b")
    // The 400 ms debounce, run now; then the dry run's reply.
    p.app.runDispatch.dispatchDebounceTimer.stop()
    p.app.runDispatch.checkDispatch()
    reply(p.app.runDispatch.dispatchPreviewRunner.current, '{"ok":true,"data":{"max_concurrent":4,"levels":[]}}')
    compare(p.app.runDispatch.dispatchState, "ready")
    wait(50)
    verify(prefix.activeFocus, "the caret stayed in Prefix")
  }

  // Review Focus 5
  function test_d_typed_in_a_dialog_field_types() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    toReady(p)
    wait(50)
    var prefix = H.find(p, "dispatchPrefix")
    prefix.forceActiveFocus()
    var before = String(prefix.text)
    keyClick("d")
    compare(String(prefix.text).length, before.length + 1, "the letter went into the field")
    compare(p.app.runDispatch.dispatchForm.prefix, String(prefix.text), "an edit, not a re-opened dispatch")
    compare(p.app.runDispatch.dispatchState, "previewing")
    compare(p.dispatchCardId, "m1")
  }

  // Review Focus 2
  function test_a_card_dropped_from_the_board_while_open_leaves_a_working_dialog() {
    var p = make(); if (!p) return
    dispatchCard(p, "t1")
    toReady(p)
    p.app.board.applyTreeData([card("m9", "M nine", "done")])
    wait(50)
    compare(H.find(p, "dispatchDialog").visible, true, "the store still holds the dispatch")
    compare(text(p, "dispatchTarget"), "Target   Subtask \"Do it\"", "the store's label from the opening")
    compare(H.find(p, "dispatchStory").visible, false)
    compare(H.find(p, "dispatchBlocked").visible, false)
    H.find(p, "dispatchCancel").clicked()
    compare(p.app.runDispatch.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
  }

  // ---- am missing

  // 31
  function test_without_am_the_card_dispatch_is_disabled_and_d_types() {
    var p = make(); if (!p) return
    p.app.runs.amStatus = "missing"
    p.navigator.openCard("m1")
    wait(50)
    compare(H.find(p, "cardDispatchButton").enabled, false)
    compare(text(p, "cardDispatchMissing"), "am is not installed or not on PATH")
    p.navigator.goBack()
    compare(p.app.nav.viewMode, "board")
    p.app.nav.cursorIndex = 0
    wait(50)
    var field = H.find(p, "searchField")
    field.forceActiveFocus()
    keyClick("d")
    compare(String(field.text), "d", "the letter typed into the search")
    compare(p.app.runDispatch.dispatchState, "idle")
  }

  // ---- the Runs entry

  // 21 (spec 12)
  function test_the_runs_toolbar_opens_the_project_step() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    compare(button.enabled, true)
    compare(String(button.tooltipText), "Start an am run")
    button.clicked()
    var dialog = H.find(p, "dispatchDialog")
    compare(dialog.visible, true)
    compare(p.app.runDispatch.dispatchStep, "project")
    compare(p.app.runDispatch.dispatchState, "idle")
    compare(p.app.runDispatch.dispatchRoot, "")
    compare(String(dialog.step), "project")
    compare(H.find(p, "dispatchProjectList").visible, true)
    compare(H.find(p, "dispatchTarget").visible, false, "not the whole board")
    compare(H.find(p, "dispatchTargetChoices").visible, false, "no row of targets")
    p.app.runDispatch.closeDispatch()
  }

  // 30 (spec 13): a card dialog closes on a project switch; a Runs dialog
  // stays (tests/ui/tst_runs_flow.qml).
  function test_a_project_switch_closes_a_card_dialog() {
    var p = make(); if (!p) return
    dispatchCard(p, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    p.navigator.chooseProject(tc.pB)
    if (p.app.extras.exportProc) {
      p.app.extras.exportProc.running = false
      p.app.extras.exportProc.launchGuard = "stale"
    }
    p.app.runControl.settingsLoadRunner.cancel()
    p.app.runControl.runSettingsLoadRunner.cancel()
    compare(p.app.runDispatch.dispatchState, "idle")
    compare(p.app.runDispatch.dispatchStep, "")
    compare(H.find(p, "dispatchDialog").visible, false)
  }

  // spec 14: the card entry points skip the Runs steps.
  function test_the_card_entries_open_the_form_at_once_data() {
    return [{ tag: "card-detail" }, { tag: "d-on-the-board" }]
  }

  function test_the_card_entries_open_the_form_at_once(data) {
    var p = make(); if (!p) return
    if (data.tag === "card-detail") {
      dispatchCard(p, "m1")
    } else {
      p.navigator.showSection("board")
      p.app.nav.cursorIndex = 0
      wait(50)
      H.find(p, "searchField").forceActiveFocus()
      keyClick("d")
    }
    var dialog = H.find(p, "dispatchDialog")
    compare(dialog.visible, true)
    compare(p.dispatchCardId, "m1")
    compare(p.app.runDispatch.dispatchStep, "")
    compare(p.app.runDispatch.dispatchRoot, "/home/u/a")
    compare(String(dialog.step), "")
    compare(H.find(p, "dispatchBack").visible, false, "no Back")
    compare(H.find(p, "dispatchForm").visible, true, "the form at once")
    verify(!p.app.runDispatch.dispatchProjectRunner.current, "a card entry probes nothing")
  }

  // 31
  function test_without_am_start_run_is_disabled() {
    var p = make(); if (!p) return
    p.app.runs.amStatus = "missing"
    p.navigator.showSection("runs")
    wait(50)
    compare(H.find(p, "startRunButton").enabled, false)
  }

  // ---- after a start

  // A ready subtask t1, started (two clicks), then start-run.py's reply.
  function startT1(p, replyText) {
    dispatchCard(p, "t1")
    toReady(p)
    var start = H.find(p, "dispatchStart")
    start.clicked()
    start.clicked()
    compare(p.app.runDispatch.dispatchState, "starting")
    reply(p.app.runDispatch.dispatchStartRunners[0].current, replyText)
    // A good start fetches the runs again; that launch cannot run here either.
    p.app.runs.snapshotRunner.cancel()
  }

  // 24
  function test_a_start_whose_run_is_listed_opens_its_run_detail() {
    var p = make(); if (!p) return
    p.app.runs.runs = [run("run-0000000000a1"), run("run-new")]
    startT1(p, '{"ok":true,"run_id":"run-new","message":"started"}')
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.runDispatch.dispatchState, "idle")
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-new")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs", "Back lands on the Runs list")
  }

  // 25
  function test_a_start_before_the_snapshot_waits_for_the_run_then_opens_it() {
    var p = make(); if (!p) return
    startT1(p, '{"ok":true,"run_id":"run-late","message":"started"}')
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "runs")
    wait(50)
    compare(text(p, "runsFooter"), "Started — opening the run when it appears")
    p.app.runs.runs = p.app.runs.runs.concat([run("run-late")])
    compare(p.app.nav.viewMode, "run")
    compare(p.app.runs.selectedRunId, "run-late")
  }

  // 26
  function test_a_start_without_a_run_id_goes_to_the_runs_list_and_says_so() {
    var p = make(); if (!p) return
    startT1(p, '{"ok":true,"message":"started, run not visible yet"}')
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.app.nav.viewMode, "runs")
    wait(50)
    compare(text(p, "runsFooter"), "Started — waiting for the run to appear")
  }

  // 27
  function test_a_failed_launch_keeps_the_dialog_and_goes_nowhere() {
    var p = make(); if (!p) return
    startT1(p, '{"ok":false,"error":{"type":"Spawn","message":"no am"},"log":"/tmp/l","exit_code":2}')
    compare(p.app.runDispatch.dispatchState, "failed")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(text(p, "dispatchRefusal"), "no am")
    compare(p.app.nav.viewMode, "entry")
  }
}
