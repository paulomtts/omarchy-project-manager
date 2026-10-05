// tests/ui/tst_dispatch_flow.qml
// The dispatch around the whole panel (S3 4.2): each entry point (the card
// detail's Dispatch, d on the board list, the Runs toolbar's Start run) opens
// the mounted dialog; the story's milestone offer, the subtask's lines and
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
    p.app.runs.settingsLoadRunner.cancel()
    // A stored verify command, so a fresh form passes the store's checks.
    p.app.runs.runSettings = { verify: ["uv run pytest"] }
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
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    if (p.app.runs.dispatchState === "previewing")
      reply(p.app.runs.dispatchPreviewRunner.current, '{"ok":true,"data":{"max_concurrent":4,"levels":[]}}')
    compare(p.app.runs.dispatchState, "ready")
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
    compare(p.app.runs.dispatchState, "previewing")
    compare(p.dispatchCardId, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(String(field.text), "", "the handled letter was not typed")
    compare(p.app.nav.searchQuery, "")
  }

  // 22
  function test_a_story_offers_its_milestone_and_the_offer_reopens_on_it() {
    var p = make(); if (!p) return
    dispatchCard(p, "s1")
    compare(p.app.runs.dispatchState, "refused")
    compare(text(p, "dispatchTarget"), "Target   Story \"Story one\"")
    compare(text(p, "dispatchRefusal"), "A story is dispatched through its milestone")
    compare(H.find(p, "dispatchStart").enabled, false)
    var offer = H.find(p, "dispatchSuggest")
    compare(offer.visible, true)
    compare(String(offer.text), "Dispatch its milestone \"M one\"")
    offer.clicked()
    compare(p.dispatchCardId, "m1")
    compare(p.app.runs.dispatchState, "previewing")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(offer.visible, false)
    wait(50)
    compare(p.focusItem.objectName, "dispatchBase", "the re-opened dialog has the focus")
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
    compare(p.app.runs.dispatchState, "ready", "the first click only arms")
    compare(p.app.runs.dispatchStartRunners.length, 0)
    compare(String(start.text), "Confirm start")
    compare(H.find(p, "dispatchConfirmNote").visible, true)
    start.clicked()
    compare(p.app.runs.dispatchState, "starting")
    compare(p.app.runs.dispatchStartRunners.length, 1)
    p.app.runs.dispatchStartRunners[0].cancel()
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
    compare(p.app.runs.dispatchState, "idle")
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
    compare(p.app.runs.dispatchStart(), true)
    p.app.runs.dispatchStartRunners[0].cancel()
    H.find(p, "keyCatcher").closeRequested()
    compare(p.app.runs.dispatchState, "starting")
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
    compare(p.app.runs.dispatchState, "previewing")
    compare(p.app.runs.dispatchForm.prefix, "m-one-b")
    // The 400 ms debounce, run now; then the dry run's reply.
    p.app.runs.dispatchDebounceTimer.stop()
    p.app.runs.checkDispatch()
    reply(p.app.runs.dispatchPreviewRunner.current, '{"ok":true,"data":{"max_concurrent":4,"levels":[]}}')
    compare(p.app.runs.dispatchState, "ready")
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
    compare(p.app.runs.dispatchForm.prefix, String(prefix.text), "an edit, not a re-opened dispatch")
    compare(p.app.runs.dispatchState, "previewing")
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
    compare(text(p, "dispatchTarget"), "Target   Subtask \"\"")
    compare(H.find(p, "dispatchStory").visible, false)
    compare(H.find(p, "dispatchBlocked").visible, false)
    H.find(p, "dispatchCancel").clicked()
    compare(p.app.runs.dispatchState, "idle")
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
    compare(p.app.runs.dispatchState, "idle")
  }

  // ---- the Runs entry

  // 21
  function test_the_runs_toolbar_opens_the_whole_board_with_a_row_of_targets() {
    var p = make(); if (!p) return
    compare(p.shortcuts.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_6 }), true)
    wait(50)
    var button = H.find(p, "startRunButton")
    compare(button.visible, true)
    button.clicked()
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(p.dispatchCardId, "")
    compare(text(p, "dispatchTarget"), "Target   Whole board")
    compare(H.find(p, "dispatchTargetChoices").visible, true)
    compare(p.dispatchChoices.map(function(c) { return c.id + ":" + c.label }).join(","), "board:Whole board,m1:M one")
    verify(H.find(p, "dispatchTargetChoiceboard"), "the board chip")
    verify(!H.find(p, "dispatchTargetChoicem9"), "a done milestone is not offered")
    compare(H.find(p, "dispatchTargetChoiceboard").active, true)
    // The board has no milestone to name a branch prefix after: refused until one is typed.
    reply(p.app.runs.dispatchDefaultsRunner.current, '{"ok":true,"data":{"default_branch":"main"}}')
    compare(p.app.runs.dispatchState, "refused")
    compare(H.find(p, "dispatchTargetChoices").visible, true, "a refused board keeps its row")
    H.find(p, "dispatchTargetChoicem1").clicked()
    compare(p.dispatchCardId, "m1")
    compare(p.app.runs.dispatchState, "previewing")
    compare(text(p, "dispatchTarget"), "Target   Milestone \"M one\"")
    compare(H.find(p, "dispatchTargetChoices").visible, true, "the row survives a re-target")
    compare(p.dispatchChoices.length, 2)
    compare(H.find(p, "dispatchTargetChoicem1").active, true)
    compare(H.find(p, "dispatchTargetChoiceboard").active, false)
    H.find(p, "dispatchCancel").clicked()
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.dispatchChoices.length, 0, "a close drops the row")
    dispatchCard(p, "m1")
    compare(H.find(p, "dispatchDialog").visible, true)
    compare(H.find(p, "dispatchTargetChoices").visible, false, "the card detail has no row")
  }

  // 30
  function test_a_project_switch_drops_the_dialog_and_its_targets() {
    var p = make(); if (!p) return
    p.navigator.showSection("runs")
    H.find(p, "startRunButton").clicked()
    compare(p.dispatchChoices.length, 2)
    p.navigator.chooseProject(tc.pB)
    compare(p.app.runs.dispatchState, "idle")
    compare(H.find(p, "dispatchDialog").visible, false)
    compare(p.dispatchChoices.length, 0)
  }

  // 31
  function test_without_am_start_run_is_disabled() {
    var p = make(); if (!p) return
    p.app.runs.amStatus = "missing"
    p.navigator.showSection("runs")
    wait(50)
    compare(H.find(p, "startRunButton").enabled, false)
  }
}
