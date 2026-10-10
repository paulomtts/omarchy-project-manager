// tests/ui/screens/tst_run_detail_screen.qml
// ui/screens/RunDetailScreen.qml on its own: the header, the Why it stopped
// block and what feeds it, the story > subtask > attempt tree with its
// bookkeeping rows, the Output / Events tabs with the output pane (snapshot or
// live) and the events pane, and the missing-run line. A stub app: a REAL
// NavigationStore, a plain object carrying the RunStore properties the screen
// reads (with recorders for selectAttempt, refreshLogs and setDetailTab), one
// carrying the RunControlStore properties (with recorders for control and
// flash), one carrying RunDispatchStore's relaunchOpenFor (a recorder), a
// plain object carrying the RunOutputStore properties, one carrying
// RunTitlesStore's titlesByRoot (the open project's map, as the store mirrors
// it from the board), an extras stub whose commentsFor reads a settable map, a
// board whose cardMap lends brd statuses, and a navigator stub recording
// openCard.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components/runGlyphs.js" as RG
import "../../helpers/amFixtures.js" as F
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "RunDetailScreen"
  when: windowShown
  visible: true
  width: 500; height: 900

  Component { id: hostC; Item { width: 500; height: 900 } }

  Component {
    id: runsC
    QtObject {
      id: rs
      property var runs: []
      property string selectedRunId: ""
      property var selectedAttempt: null
      property string logsText: ""
      property bool logsTruncated: false
      property real logsFetchedMs: 0
      property bool logsLoading: false
      property string logsError: ""
      property string logsNote: ""
      property string amStatus: "ok"
      property var selected: null
      property int refreshed: 0
      // As RunStore: (card, phase, 0, true) is a step, stored with step: true.
      function selectAttempt(cardId, phase, attempt, step) {
        rs.selected = [cardId, phase, attempt, step === true]
        rs.selectedAttempt = step === true ? { card_id: cardId, phase: phase, attempt: 0, step: true }
                                           : { card_id: cardId, phase: phase, attempt: attempt }
      }
      function refreshLogs() { rs.refreshed += 1 }
      // The events and the tab (4.3). setDetailTab records every call and,
      // as the store does, takes only output and events.
      property var events: []
      property int eventsDropped: 0
      property string eventsStatus: "idle"
      property string eventsError: ""
      property string eventsFilter: "All"
      property string detailTab: "output"
      property var tabCalls: []
      function setDetailTab(tab) {
        rs.tabCalls = rs.tabCalls.concat([tab])
        if (tab !== "output" && tab !== "events") return false
        rs.detailTab = tab
        return true
      }
      // The open project's root (RunStore.project); "" when none is open.
      property string project: "/home/u/a"
    }
  }

  // The control surface the header reads (S2 4.2). `control` and `flash`
  // only record.
  Component {
    id: controlC
    QtObject {
      id: rc
      property string flashText: ""
      property var pending: ({})
      property var stillWaiting: ({})
      readonly property string stillWaitingText: "still waiting — the run may be between phases or dead"
      property string lastControlError: ""
      property string lastControlErrorRunId: ""
      property string lastControlErrorType: ""
      property var controlCalls: []
      function control(action, id) {
        rc.controlCalls = rc.controlCalls.concat([action + "|" + id])
        return true
      }
      property var flashes: []
      function flash(text) {
        rc.flashes = rc.flashes.concat([text])
        rc.flashText = text
      }
    }
  }

  // The dispatch surface Relaunch reaches: relaunchOpenFor only records.
  Component {
    id: dispatchC
    QtObject {
      id: rd
      property var relaunchCalls: []
      function relaunchOpenFor(card, cardMap, relaunch) {
        rd.relaunchCalls = rd.relaunchCalls.concat([{ card: card, cardMap: cardMap, relaunch: relaunch }])
        return true
      }
    }
  }

  Component {
    id: extrasC
    QtObject {
      id: ex
      // {cardId: comments}, as ExtrasStore.commentsByEntity: replaced, never edited.
      property var comments: ({})
      function commentsFor(id) {
        return Object.prototype.hasOwnProperty.call(ex.comments, id) ? ex.comments[id] : []
      }
    }
  }

  Component {
    id: naviC
    QtObject {
      id: nv
      property var opened: []
      function openCard(id) { nv.opened = nv.opened.concat([id]) }
    }
  }

  // The RunOutputStore surface the screen reads. Fields a store could hand
  // over malformed are var, so tests can put garbage in them.
  Component {
    id: roC
    QtObject {
      property var followStatus: "idle"
      property var endStatus: ""
      property var liveText: ""
      property int liveDropped: 0
      property bool hasOutput: false
      property var followError: ""
    }
  }

  Component {
    id: titlesC
    QtObject {
      property var titlesByRoot: ({ "/home/u/a": { s1: "Runs screens", t1: "RunDetailScreen", t2: "Old work",
                                                   s2: "Dropped story", t3: "Shelved" } })
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var runControl: null
      property var runTitles: null
      property var runDispatch: null
      property var runOutput: null
      property var extras: null
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" } })
      property var board: ({ cardMap: {
        s1: { id: "s1", title: "Runs screens", status: "in_progress" },
        t1: { id: "t1", title: "RunDetailScreen", status: "in_progress" },
        t2: { id: "t2", title: "Old work", status: "merged" },
        s2: { id: "s2", title: "Dropped story", status: "canceled" },
        t3: { id: "t3", title: "Shelved", status: "archived" },
        M3: { id: "M3", title: "Milestone three", status: "in_progress" }
      } })
    }
  }

  function make(list, selectedId, attempt) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    var ro = roC.createObject(host)
    var extras = extrasC.createObject(host)
    var control = controlC.createObject(host)
    var titles = titlesC.createObject(host)
    var dispatch = dispatchC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs, runControl: control, runTitles: titles,
                                        runDispatch: dispatch, runOutput: ro, extras: extras })
    var navi = naviC.createObject(host)
    var sC = Qt.createComponent("../../../ui/screens/RunDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: navi })
    nav.viewMode = "run"
    runs.runs = list || []
    runs.selectedRunId = selectedId === undefined ? "run-20261004-19efcddc" : selectedId
    runs.selectedAttempt = attempt === undefined ? null : attempt
    wait(20)
    return { app: app, runs: runs, control: control, titles: titles, dispatch: dispatch, nav: nav, screen: screen,
             ro: ro, extras: extras, navi: navi }
  }

  // Colours that differ only in the colour spec (Qt.darker's HSV against a
  // Text's RGB) are the same colour.
  function sameColor(a, b) {
    return Math.abs(a.r - b.r) < 0.01 && Math.abs(a.g - b.g) < 0.01
      && Math.abs(a.b - b.b) < 0.01 && Math.abs(a.a - b.a) < 0.01
  }

  // Puts each field of `fields` on the stub runOutput.
  function setLive(s, fields) {
    for (var key in fields) s.ro[key] = fields[key]
  }

  // n numbered lines, each ended by a newline.
  function lines(n) {
    var out = []
    for (var i = 1; i <= n; i++) out.push("line " + i)
    return out.join("\n") + "\n"
  }

  function atBottom(list) {
    return Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1
  }

  // The live list's model, as JSON.
  function liveModel(s) { return JSON.stringify(H.find(s.screen, "runOutputTail").model) }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // A normalised run, as RunStore holds them. live === null means no lease.
  // It belongs to the open project unless opts.project says otherwise (null:
  // no project at all) or opts.root names its project's root ("" for none);
  // opts.workflow and opts.card set workflow and card_id.
  function run(id, status, live, opts) {
    var o = opts || {}
    var r = { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "M3" : o.milestone,
              base_branch: o.base === undefined ? "master" : o.base,
              branch_prefix: o.prefix === undefined ? "m3" : o.prefix,
              status: status, started_at: "",
              lease: live === null ? null : { pid: 4121, host: "h", heartbeat_at: "", accepting: true, live: live },
              rows: o.rows || [], tree: o.tree || { stories: [], subtasks: [] } }
    if (o.project !== null)
      r.project = o.project !== undefined ? o.project : { root: o.root === undefined ? "/home/u/a" : o.root, name: "alpha" }
    if (o.workflow !== undefined) r.workflow = o.workflow
    if (o.card !== undefined) r.card_id = o.card
    return r
  }

  function detailTree() {
    return { stories: [{ card_id: "s1", status: "started", subtasks: ["t1", "t2"] },
                       { card_id: "s2", status: "cancelled", subtasks: ["t3"] }],
             subtasks: [
               { card_id: "t1", status: "started", phases: [
                 { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
                 { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] },
               { card_id: "t2", status: "done", phases: [{ name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] }] },
               { card_id: "t3", phases: [] }] }
  }

  function detail() { return [run("run-20261004-19efcddc", "started", true, { tree: detailTree() })] }
  function sel(card, phase, n) { return { card_id: card, phase: phase, attempt: n } }

  // t1 with a numbered implement.1 and a started verify step (kind
  // deterministic, no attempts): the tree lists implement.1 then the step.
  function stepTree() {
    return { stories: [{ card_id: "s1", status: "started", subtasks: ["t1"] }],
             subtasks: [{ card_id: "t1", status: "started", phases: [
               { name: "implement", status: "done", attempts: [{ n: 1, status: "done" }] },
               { name: "verify", kind: "deterministic", status: "started", attempts: [] }] }] }
  }
  function stepRun() { return [run("run-20261004-19efcddc", "started", true, { tree: stepTree() })] }
  function stepSel(card, phase) { return { card_id: card, phase: phase, attempt: 0, step: true } }

  // The escalated run of the reason test: t1's review failed.
  function failedTree() {
    return { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] }
  }
  function escalatedRun(opts) {
    return run("run-x-escl0002", "escalated", null, Object.assign({ tree: failedTree() }, opts || {}))
  }
  // One am note on cardId for runId, as ExtrasStore.commentsFor gives it.
  function amNote(runId, cardId, kind, fieldLines, createdAt) {
    var body = ["am · " + kind + " · run " + runId].concat(fieldLines)
      .concat(["am-key: " + runId + "/" + cardId + "/" + kind + ":0a1b2c3d"]).join("\n")
    return { id: "c-" + createdAt, entityId: cardId, author: "am", body: body, createdAt: createdAt }
  }
  function stop(s) { return H.find(s.screen, "runDetailStop") }
  function part(s, name) { return H.find(stop(s), name) }

  // One am run as RunStore hands it to normalizeRun, fresh on every call: the
  // fixture's `am runs` row (runs.json's entry with the same run id, else the
  // fixture's own _am_runs_row) without `status`, and the fixture's `am status`
  // data.
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

  // ---- header

  function test_the_header_names_the_run_its_state_and_its_branches() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runDetailTitle").text, "milestone …M3")
    compare(H.find(s.screen, "runDetailId").text, "…19efcddc")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("running") + " running")
    compare(H.find(s.screen, "runDetailMeta").text, "Milestone M3 · prefix m3 · base master · lease pid 4121 live")
    compare(H.find(s.screen, "runDetailReason"), null, "the block replaced the reason line")
    compare(stop(s).visible, false, "a running run has no Why it stopped")
  }

  function test_the_header_reads_the_runs_title_then_its_short_id_in_dim() {
    var s = make(detail()); if (!s) return
    var title = H.find(s.screen, "runDetailTitle")
    var id = H.find(s.screen, "runDetailId")
    var state = H.find(s.screen, "runDetailState")
    compare(title.text, "milestone …M3", "M3 is not in the map")
    s.titles.titlesByRoot = { "/home/u/a": { M3: "Runs monitor" } }
    compare(title.text, "Runs monitor")
    compare(id.text, "…19efcddc")
    compare(String(id.color), String(s.screen.theme.dim))
    compare(state.text, RG.glyphOf("running") + " running")
    verify(id.x > title.x, "the short id follows the title")
    verify(state.x > id.x, "the state follows the short id")
  }

  // A title of any length elides; the short id and the state stay on the row.
  function test_a_long_run_title_never_pushes_the_short_id_or_the_state_off_the_row() {
    var s = make(detail()); if (!s) return
    var long = "Long"
    for (var i = 0; i < 40; i++) long += " a very long run title"
    s.titles.titlesByRoot = { "/home/u/a": { M3: long } }
    var title = H.find(s.screen, "runDetailTitle")
    compare(title.text, long)
    compare(title.elide, Text.ElideRight)
    verify(title.width < title.implicitWidth, "the title is elided")
    var names = ["runDetailId", "runDetailState"]
    for (var j = 0; j < names.length; j++) {
      var t = H.find(s.screen, names[j])
      var right = t.mapToItem(s.screen, 0, 0).x + t.width
      verify(right <= s.screen.width, names[j] + " stays on the row: right edge " + right + " of " + s.screen.width)
    }
  }

  function test_a_dead_lease_and_no_lease() {
    var s = make([run("run-x-dead0001", "started", false, {})], "run-x-dead0001"); if (!s) return
    compare(H.find(s.screen, "runDetailMeta").text, "Milestone M3 · prefix m3 · base master · lease pid 4121 not live")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("dead") + " dead")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent), "dead is urgent")
    s.runs.runs = [run("run-x-dead0001", "stopped", null, { milestone: "", prefix: "", base: "" })]
    compare(H.find(s.screen, "runDetailMeta").text, "no lease", "empty parts are left out")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("parked") + " parked")
  }

  function test_an_escalated_run_shows_its_reason_in_urgent() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("escalated") + " escalated")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent))
    compare(stop(s).visible, true)
    compare(part(s, "stopHeadline").text, RG.glyphOf("escalated") + " Escalated at review · #t1")
    var reason = part(s, "stopDetail")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    verify(Qt.colorEqual(reason.color, s.screen.theme.urgent))
  }

  // ---- why it stopped (RR 3.3)

  // 12
  function test_the_block_sits_between_the_header_and_the_controls() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    var block = stop(s)
    compare(block.visible, true)
    verify(block.y > H.find(s.screen, "runDetailMeta").y, "below the meta line")
    verify(block.y < H.find(s.screen, "runDetailControls").y, "above the controls")
  }

  // 13
  function test_ams_note_comes_from_the_escalated_card_and_open_card_opens_it() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    compare(part(s, "stopNoteHeading").visible, false, "no comments yet")
    s.extras.comments = { t1: [amNote("run-x-escl0002", "t1", "escalated",
                                      ["reason: tests do not cover the empty list"], "2026-10-04T17:45:00Z")] }
    compare(part(s, "stopNoteHeading").visible, true, "re-read when the comments are replaced")
    compare(part(s, "stopNoteField0").text, "reason  tests do not cover the empty list")
    compare(s.screen.stopNoteCardId, "t1")
    var open = part(s, "stopOpenCard")
    compare(open.visible, true)
    compare(open.enabled, true)
    tap(open)
    compare(s.navi.opened.join(","), "t1")
  }

  // 14
  function test_the_note_falls_back_to_the_milestone_card() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    s.extras.comments = {
      t1: [amNote("run-x-other0009", "t1", "escalated", ["reason: someone else"], "2026-10-04T17:40:00Z")],
      M3: [amNote("run-x-escl0002", "M3", "run-end", ["next: am resume run-x-escl0002"], "2026-10-04T17:46:00Z")] }
    compare(part(s, "stopNoteField0").text, "next  am resume run-x-escl0002")
    compare(s.screen.stopNoteCardId, "M3")
    compare(H.find(s.screen, "runDetailStop").openCardId, "t1", "the escalated card is still the one to open")
    // Review Focus 2: a synthetic escalation opens the milestone card of its run-end note.
    s.runs.runs = [run("run-x-escl0002", "escalated", null,
                       { rows: [{ card_id: "integrate", phase: "integrate", status: "failed" }] })]
    compare(part(s, "stopHeadline").text, RG.glyphOf("escalated") + " Escalated at Integrate")
    compare(H.find(s.screen, "runDetailStop").openCardId, "M3")
    tap(part(s, "stopOpenCard"))
    compare(s.navi.opened.join(","), "M3")
  }

  // 15
  function test_a_run_of_another_project_shows_no_note_and_disables_its_buttons() {
    var other = { root: "/home/u/b", name: "beta" }
    var s = make([escalatedRun({ workflow: "task", card: "t1", project: other })], "run-x-escl0002"); if (!s) return
    s.extras.comments = {
      t1: [amNote("run-x-escl0002", "t1", "escalated", ["reason: tests red"], "2026-10-04T17:45:00Z")],
      M3: [amNote("run-x-escl0002", "M3", "run-end", ["next: relaunch"], "2026-10-04T17:46:00Z")] }
    var both = "Open this run's project to open its card · Open this run's project to relaunch it"
    compare(stop(s).visible, true)
    compare(part(s, "stopNoteHeading").visible, false, "no note from another project")
    compare(part(s, "stopOpenCard").visible, true)
    compare(part(s, "stopOpenCard").enabled, false)
    compare(part(s, "stopRelaunch").visible, true)
    compare(part(s, "stopRelaunch").enabled, false)
    compare(part(s, "stopActionReason").text, both)
    tap(part(s, "stopRelaunch"))
    tap(part(s, "stopOpenCard"))
    compare(s.dispatch.relaunchCalls.length, 0, "a disabled Relaunch dispatches nothing")
    compare(s.navi.opened.length, 0, "a disabled Open card navigates nowhere")

    s.runs.runs = [escalatedRun({ workflow: "task", card: "t1" })]
    compare(part(s, "stopNoteHeading").visible, true, "the open project's run shows its note")
    compare(part(s, "stopActionReason").visible, false)
    s.runs.project = ""
    compare(part(s, "stopNoteHeading").visible, false, "no project open")
    compare(part(s, "stopActionReason").text, both)
    // Review Focus 1.
    s.runs.project = "/home/u/a/"
    compare(part(s, "stopNoteHeading").visible, true, "the open root is compared without its trailing /")
    compare(part(s, "stopActionReason").visible, false)
    s.runs.runs = [escalatedRun({ workflow: "task", card: "t1", project: null })]
    compare(part(s, "stopNoteHeading").visible, false, "a run with no project")
    compare(part(s, "stopActionReason").text, both)
    s.runs.runs = [run("run-x-escl0002", "cancelled", null, { project: other })]
    compare(part(s, "stopOpenCard").visible, false, "a cancelled run names no card")
    compare(part(s, "stopRelaunch").enabled, false)
    compare(part(s, "stopActionReason").text, "Open this run's project to relaunch it")
  }

  // 16
  function test_a_cancelled_run_relaunches_its_milestone() {
    var s = make([run("run-x-canc0004", "cancelled", null, {})], "run-x-canc0004"); if (!s) return
    compare(part(s, "stopOpenCard").visible, false, "a cancelled run with no note names no card")
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    tap(relaunch)
    compare(s.dispatch.relaunchCalls.length, 1)
    var call = s.dispatch.relaunchCalls[0]
    verify(call.card === s.app.board.cardMap.M3, "the milestone card")
    verify(call.cardMap === s.app.board.cardMap, "the board's cardMap")
    compare(JSON.stringify(call.relaunch), '{"level":"milestone","cardId":"M3","prefix":"m3","base":"master"}')
    compare(s.control.flashes.length, 0)
  }

  // 17
  function test_a_relaunch_target_missing_from_the_board_flashes_why() {
    var s = make([run("run-x-canc0004", "cancelled", null, { milestone: "M404" })], "run-x-canc0004"); if (!s) return
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.enabled, true)
    tap(relaunch)
    compare(s.dispatch.relaunchCalls.length, 0)
    compare(s.control.flashes.join("|"), "The card to relaunch is no longer on the board")
    compare(H.find(s.screen, "runDetailFlash").text, "The card to relaunch is no longer on the board")
  }

  // 18
  function test_a_refused_resume_of_this_run_offers_relaunch() {
    var s = make([escalatedRun()], "run-x-escl0002"); if (!s) return
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.visible, false, "a resumable escalated run: Resume is in the controls")
    s.control.lastControlErrorType = "NotResumableError"
    s.control.lastControlErrorRunId = "run-x-escl0002"
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    s.control.lastControlErrorRunId = "run-x-other0009"
    compare(relaunch.visible, false, "another run's refusal")
    s.control.lastControlErrorRunId = "run-x-escl0002"
    s.control.lastControlErrorType = "RunIsLiveError"
    compare(relaunch.visible, false, "a refusal relaunching does not answer")
    s.control.lastControlErrorType = "CheckpointMismatchError"
    compare(relaunch.visible, true)
    s.runs.runs = [escalatedRun({ milestone: "" })]
    compare(relaunch.visible, false, "no relaunch target, whatever the refusal")
  }

  // 19
  function test_an_escalated_task_run_offers_relaunch() {
    var s = make([escalatedRun({ workflow: "task", card: "t1" })], "run-x-escl0002"); if (!s) return
    var relaunch = part(s, "stopRelaunch")
    compare(relaunch.visible, true)
    compare(relaunch.enabled, true)
    tap(relaunch)
    compare(s.dispatch.relaunchCalls.length, 1)
    verify(s.dispatch.relaunchCalls[0].card === s.app.board.cardMap.t1)
    compare(s.dispatch.relaunchCalls[0].relaunch.level, "card")
  }

  // 20
  function test_a_dead_run_shows_its_last_heartbeat_age() {
    var tree = { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ n: 1, status: "started" }] }] }] }
    var r = run("run-x-dead0005", "started", false, { tree: tree })
    r.lease.heartbeat_at = new Date(Date.now() - 150000).toISOString()
    var s = make([r], "run-x-dead0005"); if (!s) return
    compare(part(s, "stopHeadline").text, RG.glyphOf("dead") + " The run's process died · #t1 · at implement")
    compare(part(s, "stopHeartbeat").visible, true)
    compare(part(s, "stopHeartbeat").text, "Last heartbeat 2m ago")
    var bad = run("run-x-dead0005", "started", false, { tree: tree })
    bad.lease.heartbeat_at = "garbage"
    s.runs.runs = [bad]
    compare(part(s, "stopHeartbeat").visible, false, "an unparseable heartbeat")
  }

  // 21
  function test_the_heading_for_attempt_0_says_newest() {
    var s = make(detail(), undefined, sel("t1", "verify", 0)); if (!s) return
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 verify (newest)")
    s.runs.selectedAttempt = sel("t1", "implement", 2)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
  }

  // ---- tree

  function test_story_and_subtask_rows_carry_glyph_title_status_and_phase() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Runs screens · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " RunDetailScreen · started · implement.2")
    compare(H.find(s.screen, "runSubtaskLabel0_1").text, RG.glyphOf("done") + " Old work · done · spec.1")
    compare(H.find(s.screen, "runStory1").text, RG.glyphOf("cancelled") + " Dropped story · cancelled")
    compare(H.find(s.screen, "runSubtaskLabel1_0").text, "Shelved", "no status, no phase: just the card")
  }

  function test_terminal_brd_cards_are_dimmed_not_hidden() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_1").visible, true, "merged is listed")
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5)
    compare(H.find(s.screen, "runStory1").visible, true, "canceled is listed")
    compare(H.find(s.screen, "runStory1").opacity, 0.5)
    compare(H.find(s.screen, "runSubtask1_0").opacity, 0.5, "archived too")
    compare(H.find(s.screen, "runStory0").opacity, 1)
  }

  // A run of /home/u/b with the open board's ids.
  function betaDetail() { return [run("run-20261004-19efcddc", "started", true, { root: "/home/u/b", tree: detailTree() })] }

  // A run of /home/u/b whose ids the open board lacks; storyTitle is am's
  // own title of the story, when given.
  function betaOnly(storyTitle) {
    var story = { card_id: "s-beta-00000001", status: "started", subtasks: ["t-beta-00000002"] }
    if (storyTitle !== undefined) story.title = storyTitle
    return [run("run-20261004-19efcddc", "started", true, { root: "/home/u/b", tree: {
      stories: [story], subtasks: [{ card_id: "t-beta-00000002", status: "started", phases: [] }] } })]
  }

  function test_a_run_of_another_project_titles_its_tree_from_its_own_map() {
    var s = make(betaDetail()); if (!s) return
    s.titles.titlesByRoot = {
      "/home/u/a": { M3: "Alpha milestone", s1: "Alpha story", t1: "Alpha sub" },
      "/home/u/b": { M3: "Beta milestone", s1: "Beta story", t1: "Beta sub", t2: "Beta old", s2: "Beta dropped", t3: "Beta shelved" } }
    compare(H.find(s.screen, "runDetailTitle").text, "Beta milestone")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Beta sub · started · implement.2")
    compare(H.find(s.screen, "runSubtaskLabel1_0").text, "Beta shelved")
  }

  function test_cards_of_a_project_that_is_not_open_and_not_on_the_board() {
    var s = make(betaOnly()); if (!s) return
    s.titles.titlesByRoot = { "/home/u/b": { "s-beta-00000001": "Beta story", "t-beta-00000002": "Beta sub" } }
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Beta sub · started")
    compare(H.find(s.screen, "runStory0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
  }

  function test_a_card_without_a_title_shows_its_short_id() {
    var s = make(betaOnly()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …00000002 · started")
    s.runs.runs = betaOnly("am story")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " am story · started", "am's own story title")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …00000002 · started", "am has no subtask titles")
    s.runs.runs = betaOnly()
    s.app.runTitles = null
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …00000002 · started")
    compare(H.find(s.screen, "runDetailTitle").text, "milestone …M3")
  }

  function test_titles_follow_the_map() {
    var s = make(betaOnly()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    s.titles.titlesByRoot = { "/home/u/b": { M3: "Beta milestone", "s-beta-00000001": "Beta story", "t-beta-00000002": "Beta sub" } }
    compare(H.find(s.screen, "runDetailTitle").text, "Beta milestone")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Beta sub · started")
  }

  // app.runTitles set after the screen exists is read.
  function test_titles_arriving_after_the_screen_are_read() {
    var s = make(betaOnly()); if (!s) return
    var store = s.app.runTitles
    s.app.runTitles = null
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …00000001 · started")
    store.titlesByRoot = { "/home/u/b": { "s-beta-00000001": "Beta story" } }
    s.app.runTitles = store
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " Beta story · started")
  }

  function test_a_run_with_no_project_uses_no_map() {
    var s = make([run("run-20261004-19efcddc", "started", true, { root: "", tree: detailTree() })]); if (!s) return
    s.titles.titlesByRoot = { "/home/u/a": { M3: "Alpha milestone", s1: "Runs screens", t1: "RunDetailScreen" }, "": { s1: "Rootless" } }
    compare(H.find(s.screen, "runDetailTitle").text, "milestone …M3")
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …s1 · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …t1 · started · implement.2")
  }

  function test_dimming_reads_the_open_board_only() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5)
    compare(H.find(s.screen, "runStory1").opacity, 0.5)
    compare(H.find(s.screen, "runSubtask1_0").opacity, 0.5)
    compare(H.find(s.screen, "runStory0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
    var tree = detailTree()
    tree.stories[0].subtasks.push("t-beta-00000002")
    tree.subtasks.push({ card_id: "t-beta-00000002", status: "started", phases: [] })
    s.runs.runs = [run("run-20261004-19efcddc", "started", true, { root: "/home/u/b", tree: tree })]
    s.titles.titlesByRoot = { "/home/u/b": { t2: "Beta open", "t-beta-00000002": "Beta sub" } }
    compare(H.find(s.screen, "runSubtaskLabel0_1").text, RG.glyphOf("done") + " Beta open · done · spec.1")
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5, "the open board has t2 merged")
    compare(H.find(s.screen, "runSubtaskLabel0_2").text, RG.glyphOf("running") + " Beta sub · started")
    compare(H.find(s.screen, "runSubtask0_2").opacity, 1, "an id the board lacks is never dimmed")
  }

  // A card title of any length elides; the status and phase stay on the row.
  function test_a_long_card_title_never_pushes_the_status_or_phase_off_the_row() {
    var s = make(detail()); if (!s) return
    var long = "Long"
    for (var i = 0; i < 40; i++) long += " a very long card title"
    s.titles.titlesByRoot = { "/home/u/a": { s1: long, t1: long } }
    var rows = [["runStory0", "started"], ["runSubtaskLabel0_0", "started · implement.2"]]
    for (var j = 0; j < rows.length; j++) {
      var line = H.find(s.screen, rows[j][0])
      compare(line.text, RG.glyphOf("running") + " " + long + " · " + rows[j][1])
      var lead = H.find(s.screen, rows[j][0] + "Lead")
      verify(lead.width < lead.implicitWidth, rows[j][0] + "'s title is elided")
      var tail = H.find(s.screen, rows[j][0] + "Tail")
      compare(tail.text, "· " + rows[j][1])
      var right = tail.mapToItem(line, 0, 0).x + tail.width
      verify(right <= line.width, rows[j][0] + "'s status stays on the row: right edge " + right + " of " + line.width)
    }
  }

  // Own keys only: an id named like a prototype member has no title.
  function test_a_prototype_key_id_is_no_title() {
    var tree = { stories: [{ card_id: "__proto__", status: "started", subtasks: ["constructor"] }],
                 subtasks: [{ card_id: "constructor", status: "started", phases: [] }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })]); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " …_proto__ · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " …structor · started")
  }

  // A new map renames; the selected attempt, its timeline and output stay.
  function test_a_new_map_keeps_the_selected_attempt_and_its_output() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    s.titles.titlesByRoot = { "/home/u/a": { t1: "Renamed" } }
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " Renamed · started · implement.2")
    compare(s.runs.selectedAttempt, sel("t1", "implement", 2))
    compare(H.find(s.screen, "runTimeline0_0").visible, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_2").text, "› " + RG.glyphOf("running") + " implement.2 started")
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
  }

  function test_the_timeline_and_attempts_show_under_the_selected_subtask_only() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    var tl = H.find(s.screen, "runTimeline0_0")
    compare(tl.visible, true)
    compare(tl.text, "spec" + RG.GLYPHS.done + " → implement" + RG.GLYPHS.running)
    compare(H.find(s.screen, "runTimeline0_1").visible, false)
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("done") + " spec.1 done")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "  " + RG.glyphOf("dead") + " implement.1 failed")
    var chosen = H.find(s.screen, "runAttemptLabel0_0_2")
    compare(chosen.text, "› " + RG.glyphOf("running") + " implement.2 started", "a marker, not colour alone")
    compare(chosen.font.bold, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_1").font.bold, false)
    compare(H.find(s.screen, "runAttempt0_1_0"), null, "another subtask's attempts stay folded")
  }

  function test_no_selection_shows_no_attempt_rows() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runAttempt0_0_0"), null)
    compare(H.find(s.screen, "runTimeline0_0").visible, false)
    compare(H.find(s.screen, "runOutputNone").visible, true)
    compare(H.find(s.screen, "runOutputNone").text, "No attempt selected")
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
  }

  function test_clicking_an_attempt_selects_it() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected.join("|"), "t1|spec|1|false")
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text.indexOf("› "), 0, "the clicked row is marked")
    compare(H.find(s.screen, "runAttemptLabel0_0_2").text.indexOf("  "), 0)
  }

  // Review Focus 4.
  function test_clicking_a_subtask_selects_its_current_attempt() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runSubtask0_1"))
    compare(s.runs.selected.join("|"), "t2|spec|1|false")
    verify(H.find(s.screen, "runAttempt0_1_0"), "its attempts unfold")
    compare(H.find(s.screen, "runAttempt0_0_0"), null, "the other subtask folds")
    s.runs.selected = null
    tap(H.find(s.screen, "runSubtask1_0"))
    compare(s.runs.selected, null, "a subtask with no attempt selects nothing")
  }

  function test_failed_and_escalated_tree_rows_are_drawn_urgent() {
    var tree = { stories: [{ card_id: "s1", status: "escalated", subtasks: ["t1", "t2"] }],
                 subtasks: [
                   { card_id: "t1", status: "failed", phases: [{ name: "implement", status: "started",
                     attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] },
                   { card_id: "t2", status: "done", phases: [] },
                   { card_id: "integrate", status: "dead" }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, sel("t1", "implement", 2)); if (!s) return
    var urgent = s.screen.theme.urgent, fg = s.screen.theme.foreground
    verify(!Qt.colorEqual(urgent, fg), "the theme tells the two apart")
    verify(Qt.colorEqual(H.find(s.screen, "runStory0").color, urgent), "an escalated story")
    verify(Qt.colorEqual(H.find(s.screen, "runSubtaskLabel0_0").color, urgent), "a failed subtask")
    verify(Qt.colorEqual(H.find(s.screen, "runSubtaskLabel0_1").color, fg), "a done subtask is not urgent")
    verify(Qt.colorEqual(H.find(s.screen, "runAttemptLabel0_0_0").color, urgent), "a failed attempt")
    verify(Qt.colorEqual(H.find(s.screen, "runAttemptLabel0_0_1").color, fg), "a started attempt is not urgent")
    verify(Qt.colorEqual(H.find(s.screen, "runSynthetic0").color, urgent), "a dead bookkeeping row")
  }

  // Real am: review.1 of 10e26d57 is the gate_failed attempt that escalated
  // status-escalated.json; explore.1 of the same subtask is ok.
  function test_a_gate_failed_attempt_of_real_am_shows_the_dead_glyph_in_urgent() {
    var run = Runs.normalizeRun(amRun("status-escalated.json"))
    var card = "10e26d57-374c-48d3-bc45-09389b42cfac"
    var key = ""
    var stories = Runs.runTree(run).stories
    for (var si = 0; si < stories.length; si++) {
      for (var ti = 0; ti < stories[si].subtasks.length; ti++) {
        var t = stories[si].subtasks[ti]
        if (t.card_id !== card) continue
        for (var ai = 0; ai < t.attempts.length; ai++) {
          if (t.attempts[ai].phase === "review" && t.attempts[ai].attempt === 1) key = si + "_" + ti + "_" + ai
        }
      }
    }
    compare(key, "1_0_11", "where the capture puts review.1 of " + card)
    var s = make([run], run.id, sel(card, "review", 1)); if (!s) return
    var failed = H.find(s.screen, "runAttemptLabel" + key)
    compare(failed.text, "› " + RG.glyphOf("dead") + " review.1 gate_failed")
    verify(Qt.colorEqual(failed.color, s.screen.theme.urgent), "a gate_failed attempt is urgent")
    var ok = H.find(s.screen, "runAttemptLabel1_0_1")
    compare(ok.text, "  " + RG.glyphOf("done") + " explore.1 ok")
    verify(Qt.colorEqual(ok.color, s.screen.theme.foreground), "an ok attempt is not urgent")
  }

  // Review Focus 3.
  function test_an_unnumbered_attempt_is_listed_but_not_clickable() {
    var tree = { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ status: "started" }, { n: 1, status: "failed" }] }] }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("running") + " implement.? started")
    s.runs.selected = null
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected, null)
  }

  // ---- step rows

  function test_a_step_row_reads_its_phase_without_a_number() {
    var s = make(stepRun(), undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "› " + RG.glyphOf("done") + " implement.1 done")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "  " + RG.glyphOf("running") + " verify started")
  }

  function test_clicking_a_step_row_selects_the_step() {
    var s = make(stepRun(), undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttempt0_0_1").hoverCursorShape, Qt.PointingHandCursor)
    tap(H.find(s.screen, "runAttempt0_0_1"))
    compare(JSON.stringify(s.runs.selected), JSON.stringify(["t1", "verify", 0, true]))
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "› " + RG.glyphOf("running") + " verify started")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").font.bold, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("done") + " implement.1 done")
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected.join("|"), "t1|implement|1|false", "a numbered attempt still selects itself")
  }

  function test_a_step_selection_heading_has_no_number() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 verify")
    s.runs.selectedAttempt = sel("t1", "implement", 1)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.1")
    s.runs.selectedAttempt = null
    compare(H.find(s.screen, "runOutputHeading").text, "Output")
  }

  // Review Focus 2.
  function test_a_step_and_an_attempt_of_one_phase_are_never_both_selected() {
    var tree = stepTree()
    tree.subtasks[0].phases[1].attempts = [{ status: "started" }]
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, stepSel("t1", "verify")); if (!s) return
    var step = H.find(s.screen, "runAttemptLabel0_0_1")
    var unnumbered = H.find(s.screen, "runAttemptLabel0_0_2")
    compare(step.text, "› " + RG.glyphOf("running") + " verify started")
    compare(unnumbered.text, "  " + RG.glyphOf("running") + " verify.? started", "the step selection is not the attempt's")
    s.runs.selectedAttempt = sel("t1", "verify", 0)
    compare(step.text.indexOf("  "), 0, "an attempt-shaped selection never marks the step")
    compare(unnumbered.text.indexOf("› "), 0)
  }

  function test_bookkeeping_rows_only_when_present() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSynthetic0"), null)
    var tree = detailTree()
    tree.stories.push({ card_id: "base-s1", status: "done" })
    s.runs.runs = [run("run-20261004-19efcddc", "started", true,
                       { tree: tree, rows: [{ card_id: "integrate", phase: "integrate", status: "" }] })]
    compare(H.find(s.screen, "runSynthetic0").text, RG.glyphOf("done") + " Base s1 done")
    compare(H.find(s.screen, "runSynthetic1").text, "Integrate not started")
    compare(H.find(s.screen, "runStory2"), null, "a bookkeeping id is never a story row")
  }

  // ---- output pane

  function test_the_output_pane_is_a_labelled_snapshot_while_idle() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "collecting...\n3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    var heading = H.find(s.screen, "runOutputHeading")
    var age = H.find(s.screen, "runOutputAge")
    compare(heading.text, "Output · t1 implement.2")
    compare(age.text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputText").text, "collecting...\n3 passed")
    s.runs.logsTruncated = true
    compare(age.text, "snapshot 14s ago · last 200 lines")
    compare(heading.text.indexOf("live"), -1)
    compare(age.text.indexOf("live"), -1)
    compare(H.find(s.screen, "runOutputRefresh").text, "Refresh")
  }

  function test_loading_then_an_error_that_keeps_the_text() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsLoading = true
    compare(H.find(s.screen, "runOutputAge").text, "loading…")
    s.runs.logsLoading = false
    s.runs.logsText = "old text"
    s.runs.logsError = "AmMissing: am is not installed."
    var err = H.find(s.screen, "runOutputError")
    compare(err.visible, true)
    compare(err.text, "AmMissing: am is not installed.")
    verify(Qt.colorEqual(err.color, s.screen.theme.urgent))
    compare(H.find(s.screen, "runOutputText").visible, true, "the last text stays")
    compare(H.find(s.screen, "runOutputText").text, "old text")
    compare(H.find(s.screen, "runStory0").visible, true, "the tree stays as the snapshot left it")
  }

  function test_refresh_asks_the_store_again() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runOutputRefresh"))
    compare(s.runs.refreshed, 1)
  }

  // ---- live output: label, error, note, Refresh

  function test_following_with_output_reads_live() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "collecting...\n" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.visible, true)
    compare(age.text, RG.glyphOf("running") + " live")
    verify(sameColor(age.color, s.screen.theme.dim), "a plain caption")
    compare(H.find(s.screen, "runOutputError").visible, false)
  }

  function test_connecting_and_following_without_output_read_waiting() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    var age = H.find(s.screen, "runOutputAge")
    setLive(s, { followStatus: "connecting" })
    compare(age.text, RG.glyphOf("running") + " live · waiting for output")
    setLive(s, { followStatus: "following", hasOutput: false })
    compare(age.text, RG.glyphOf("running") + " live · waiting for output")
    setLive(s, { hasOutput: true })
    compare(age.text, RG.glyphOf("running") + " live")
  }

  function test_ended_ok_reads_ended_plainly() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "ok", hasOutput: true, liveText: "3 passed\n" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, "ended · ok")
    verify(sameColor(age.color, s.screen.theme.dim))
    setLive(s, { endStatus: "weird_status" })
    compare(age.text, "ended · weird_status", "an unknown end status is shown plainly")
    verify(sameColor(age.color, s.screen.theme.dim))
  }

  function test_ended_failures_are_urgent_with_the_escalated_glyph_data() {
    return [{ tag: "gate_failed", status: "gate_failed" },
            { tag: "schema_invalid", status: "schema_invalid" },
            { tag: "harness_error", status: "harness_error" }]
  }

  function test_ended_failures_are_urgent_with_the_escalated_glyph(data) {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: data.status, hasOutput: true, liveText: "x\n" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, RG.glyphOf("escalated") + " ended · " + data.status)
    verify(Qt.colorEqual(age.color, s.screen.theme.urgent))
  }

  function test_a_step_with_no_log_reads_a_plain_sentence() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "", followError: "This step records no output" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, "This step records no output")
    verify(!Qt.colorEqual(age.color, s.screen.theme.urgent), "never urgent")
    compare(H.find(s.screen, "runOutputError").visible, false)
  }

  function test_unsupported_puts_the_sentence_before_the_snapshot() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "unsupported", followError: "This am cannot stream output (am logs --follow is missing)" })
    var age = H.find(s.screen, "runOutputAge")
    compare(age.text, "This am cannot stream output (am logs --follow is missing)", "no snapshot yet: the sentence alone")
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    compare(age.text, "This am cannot stream output (am logs --follow is missing) · snapshot 14s ago")
    verify(sameColor(age.color, s.screen.theme.dim))
    compare(H.find(s.screen, "runOutputText").visible, true)
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
    tap(H.find(s.screen, "runOutputRefresh"))
    compare(s.runs.refreshed, 1, "Refresh works")
  }

  function test_a_long_label_wraps_and_keeps_refresh_on_screen() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsFetchedMs = Date.now() - 14000
    setLive(s, { followStatus: "unsupported", followError: "This am cannot stream output (am logs --follow is missing)" })
    var age = H.find(s.screen, "runOutputAge")
    var refresh = H.find(s.screen, "runOutputRefresh")
    var pane = H.find(s.screen, "runOutputPane")
    verify(age.lineCount > 1, "the label wraps")
    verify(refresh.mapToItem(pane, 0, 0).x + refresh.width <= pane.width + 1, "Refresh stays inside the pane")
  }

  function test_a_follow_error_is_urgent() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsError = "an older snapshot error"
    setLive(s, { followStatus: "error", followError: "Live output stopped: run not found" })
    var err = H.find(s.screen, "runOutputError")
    compare(err.visible, true)
    compare(err.text, "Live output stopped: run not found")
    verify(Qt.colorEqual(err.color, s.screen.theme.urgent))
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
    compare(H.find(s.screen, "runOutputAge").visible, false, "no live label for an error")
  }

  function test_refresh_only_for_a_snapshot_data() {
    return [{ tag: "idle", status: "idle", shown: true },
            { tag: "unsupported", status: "unsupported", shown: true },
            { tag: "connecting", status: "connecting", shown: false },
            { tag: "following", status: "following", shown: false },
            { tag: "ended", status: "ended", shown: false },
            { tag: "error", status: "error", shown: false }]
  }

  function test_refresh_only_for_a_snapshot(data) {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: data.status })
    compare(H.find(s.screen, "runOutputRefresh").visible, data.shown)
  }

  function test_a_logs_note_shows_dim_not_urgent() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    var note = H.find(s.screen, "runOutputNote")
    compare(note.visible, false, "no note, no line")
    s.runs.logsNote = "This step records no output"
    compare(note.visible, true)
    compare(note.text, "This step records no output")
    verify(sameColor(note.color, s.screen.theme.dim))
    verify(!Qt.colorEqual(note.color, s.screen.theme.urgent))
    setLive(s, { followStatus: "following" })
    compare(note.visible, false, "a snapshot's note only")
  }

  function test_no_run_output_object_is_the_snapshot() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.app.runOutput = null
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
    s.app.runOutput = undefined
    compare(H.find(s.screen, "runOutputRefresh").visible, true, "undefined too")
  }

  // Review Focus 1.
  function test_no_selection_ignores_a_live_run_output() {
    var s = make(detail()); if (!s) return
    s.runs.logsNote = "This step records no output"
    setLive(s, { followStatus: "error", followError: "Live output stopped" })
    compare(H.find(s.screen, "runOutputNone").visible, true)
    compare(H.find(s.screen, "runOutputAge").visible, false)
    compare(H.find(s.screen, "runOutputError").visible, false)
    compare(H.find(s.screen, "runOutputNote").visible, false)
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n" })
    compare(H.find(s.screen, "runOutputAge").visible, false)
  }

  // Review Focus 3.
  function test_an_unknown_follow_status_is_the_snapshot() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsFetchedMs = Date.now() - 14000
    setLive(s, { followStatus: "bogus" })
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
    setLive(s, { followStatus: 7 })
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    setLive(s, { followStatus: "ended", endStatus: 5, followError: null })
    compare(H.find(s.screen, "runOutputAge").visible, false, "a non-string end status is none, and so is the sentence")
    setLive(s, { followStatus: "error", followError: 9 })
    compare(H.find(s.screen, "runOutputError").visible, false)
  }

  // ---- live output: the list

  function test_idle_keeps_the_snapshot_pane() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    setLive(s, { followStatus: "idle", liveText: "live stuff\n", hasOutput: true })
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputList").count, 0)
    compare(H.find(s.screen, "runOutputText").visible, true)
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
  }

  function test_following_shows_the_live_text_not_the_snapshot() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "old snapshot"
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "… 3 earlier lines\ncollecting...\n" })
    wait(30)
    compare(H.find(s.screen, "runOutputText").visible, false)
    compare(H.find(s.screen, "runOutputTail").visible, true)
    compare(liveModel(s), JSON.stringify(["… 3 earlier lines", "collecting..."]))
    var row = H.find(s.screen, "runOutputRow1")
    compare(row.text, "collecting...")
    compare(row.textFormat, Text.PlainText)
    compare(row.wrapMode, Text.WrapAnywhere)
    compare(row.width, H.find(s.screen, "runOutputList").width)
  }

  function test_ended_ok_reads_ended_and_the_end_line_is_last() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "ok", hasOutput: true, liveText: "a\nb\n" })
    wait(30)
    compare(H.find(s.screen, "runOutputAge").text, "ended · ok")
    compare(liveModel(s), JSON.stringify(["a", "b", "— ended: ok —"]))
    compare(H.find(s.screen, "runOutputRow2").text, "— ended: ok —")
    compare(s.ro.liveText, "a\nb\n", "the end line is never part of liveText")
  }

  function test_ended_failures_end_with_their_end_line_data() {
    return [{ tag: "gate_failed", status: "gate_failed" },
            { tag: "schema_invalid", status: "schema_invalid" },
            { tag: "harness_error", status: "harness_error" }]
  }

  function test_ended_failures_end_with_their_end_line(data) {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: data.status, hasOutput: true, liveText: "x\n" })
    compare(liveModel(s), JSON.stringify(["x", "— ended: " + data.status + " —"]))
  }

  function test_a_step_with_no_log_has_no_end_line_and_no_rows() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "", followError: "This step records no output" })
    compare(liveModel(s), "[]")
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputText").visible, false)
  }

  function test_an_ended_step_shows_its_snapshot_then_the_end_line() {
    var s = make(stepRun(), undefined, stepSel("t1", "verify")); if (!s) return
    setLive(s, { followStatus: "ended", endStatus: "ok", hasOutput: true, liveText: "x\n" })
    compare(liveModel(s), JSON.stringify(["x", "— ended: ok —"]), "before the snapshot lands: the live text")
    s.runs.logsText = "a\nb"
    s.runs.logsFetchedMs = Date.now()
    compare(liveModel(s), JSON.stringify(["a", "b", "— ended: ok —"]))
    s.runs.selectedAttempt = sel("t1", "implement", 1)
    compare(liveModel(s), JSON.stringify(["x", "— ended: ok —"]), "an attempt always shows its live text")
  }

  function test_an_error_keeps_the_live_text_it_has() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "error", followError: "Live output stopped: run not found", liveText: "kept\n" })
    compare(liveModel(s), JSON.stringify(["kept"]))
    compare(H.find(s.screen, "runOutputText").visible, false)
    setLive(s, { liveText: "" })
    compare(H.find(s.screen, "runOutputTail").visible, false, "no text, no room")
  }

  function test_connecting_has_no_rows() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "old snapshot"
    setLive(s, { followStatus: "connecting" })
    compare(liveModel(s), "[]")
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputText").visible, false)
  }

  function test_the_live_list_follows_growing_text_and_offers_jump() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: lines(80) })
    wait(50)
    var tail = H.find(s.screen, "runOutputTail")
    var list = H.find(s.screen, "runOutputList")
    var jump = H.find(s.screen, "runOutputJump")
    compare(list.count, 80)
    verify(list.contentHeight > list.height, "the list scrolls")
    tryVerify(function () { return atBottom(list) }, 1000, "it opens at its bottom")
    compare(tail.following, true)
    compare(jump.visible, false)
    s.ro.liveText = lines(160)
    wait(50)
    compare(list.count, 160)
    tryVerify(function () { return atBottom(list) }, 1000, "growing text is followed")
    compare(tail.following, true)
    list.contentY = list.originY
    wait(30)
    compare(tail.following, false)
    compare(jump.visible, true)
    var before = list.contentY
    s.ro.liveText = lines(200)
    wait(50)
    compare(list.count, 200)
    compare(list.contentY, before, "scrolled up, it stays put")
    tap(jump)
    tryVerify(function () { return atBottom(list) }, 1000, "Jump puts it at its bottom")
    compare(tail.following, true)
  }

  // Review Focus 1.
  function test_no_selection_shows_no_live_list() {
    var s = make(detail()); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n" })
    compare(liveModel(s), "[]")
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputNone").visible, true)
  }

  // Review Focus 3.
  function test_a_non_string_live_text_gives_no_rows() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: 42 })
    compare(liveModel(s), "[]")
    setLive(s, { liveText: null })
    compare(liveModel(s), "[]")
    setLive(s, { followStatus: "ended", endStatus: { s: 1 }, liveText: "a\n" })
    compare(liveModel(s), JSON.stringify(["a"]), "a non-string end status adds no end line")
  }

  // Review Focus 4.
  function test_going_back_to_idle_restores_the_snapshot() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n" })
    compare(H.find(s.screen, "runOutputTail").visible, true)
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
    setLive(s, { followStatus: "idle" })
    compare(H.find(s.screen, "runOutputTail").visible, false)
    compare(H.find(s.screen, "runOutputText").visible, true)
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(H.find(s.screen, "runOutputAge").text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputRefresh").visible, true)
  }

  // Review Focus 5.
  function test_blank_lines_are_kept_and_a_trailing_newline_adds_no_row() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    setLive(s, { followStatus: "following", hasOutput: true, liveText: "a\n\nb\n" })
    compare(liveModel(s), JSON.stringify(["a", "", "b"]))
    setLive(s, { liveText: "a\n\nb" })
    compare(liveModel(s), JSON.stringify(["a", "", "b"]), "a partial last line is a row")
  }

  // ---- missing, malformed, visibility

  function test_a_run_no_longer_in_the_snapshot() {
    var s = make(detail(), "run-gone"); if (!s) return
    var msg = H.find(s.screen, "runDetailMissing")
    compare(msg.visible, true)
    compare(msg.text, "This run is no longer in the snapshot")
    compare(H.find(s.screen, "runDetailBody").visible, false)
  }

  function test_a_malformed_run_renders_without_throwing() {
    var odd = { id: "run-20261004-19efcddc", status: 7, lease: "x", rows: "y",
                tree: { stories: "x", subtasks: [null, 5, { card_id: 7 }, { card_id: "t9", phases: "x" }] } }
    var s = make([odd]); if (!s) return
    compare(H.find(s.screen, "runDetailMissing").visible, false)
    compare(H.find(s.screen, "runStory0").text, "Other")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, "…t9", "an id shorter than 8 is shown whole")
    compare(H.find(s.screen, "runOutputNone").visible, true)
  }

  function test_the_screen_is_hidden_outside_the_run_view() {
    var s = make(detail()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "runs"
    compare(s.screen.visible, false)
    s.nav.viewMode = "run"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, true, "no project: Run detail still shows")
  }

  // ---- run controls (S2 4.2)

  SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

  function ctl(s, name) { return H.find(H.find(s.screen, "runDetailControls"), "runControl" + name) }

  // 17
  function test_a_running_run_offers_pause_and_cancel_without_hover() {
    var s = make(detail()); if (!s) return
    compare(ctl(s, "Pause").visible, true)
    compare(ctl(s, "Pause").text, "Pause")
    compare(ctl(s, "Cancel").visible, true)
    compare(ctl(s, "Resume").visible, false)
    compare(ctl(s, "Caption").visible, false, "Run detail is the run itself, not a card")
  }

  function test_a_parked_run_offers_resume() {
    var s = make([run("run-x-park0002", "stopped", null, {})], "run-x-park0002"); if (!s) return
    compare(ctl(s, "Resume").visible, true)
    compare(ctl(s, "Resume").enabled, true)
    compare(ctl(s, "Pause").visible, false)
  }

  function test_pause_goes_to_the_store_and_cancel_only_asks() {
    var s = make(detail()); if (!s) return
    cancelSpy.target = s.screen
    cancelSpy.clear()
    tap(ctl(s, "Pause"))
    compare(s.control.controlCalls.join(","), "pause|run-20261004-19efcddc")
    tap(ctl(s, "Cancel"))
    compare(cancelSpy.count, 1)
    compare(cancelSpy.signalArguments[0][0], "run-20261004-19efcddc")
    compare(s.control.controlCalls.length, 1, "cancel never reaches the store")
  }

  function test_the_runs_own_error_and_waiting_lines() {
    var s = make(detail()); if (!s) return
    s.control.lastControlError = "The run no longer exists"
    s.control.lastControlErrorRunId = "run-other"
    compare(ctl(s, "Error").visible, false, "another run's error")
    s.control.lastControlErrorRunId = "run-20261004-19efcddc"
    compare(ctl(s, "Error").visible, true)
    compare(ctl(s, "Error").text, "The run no longer exists")
    s.control.pending = { "run-20261004-19efcddc": "pause" }
    s.control.stillWaiting = { "run-20261004-19efcddc": true }
    compare(ctl(s, "Pause").text, "Pause requested…")
    compare(ctl(s, "Waiting").visible, true)
  }

  // 18
  function test_a_done_run_shows_no_controls() {
    var s = make([run("run-x-done0003", "done", null, {})], "run-x-done0003"); if (!s) return
    compare(ctl(s, "Buttons").visible, false)
    compare(H.find(s.screen, "runDetailControls").height, 0)
  }

  // ---- the flash line (S2 4.3)

  // 15
  function test_the_flash_line_shows_only_while_there_is_a_flash() {
    var s = make(detail()); if (!s) return
    var line = H.find(s.screen, "runDetailFlash")
    verify(line, "the flash line")
    compare(line.visible, false)
    s.control.flashText = "Integrate is running; it cannot be paused or cancelled"
    compare(line.visible, true)
    compare(line.text, "Integrate is running; it cannot be paused or cancelled")
    s.control.flashText = ""
    compare(line.visible, false)
  }

  // ---- the Output / Events tabs (4.3)

  // A complete row as RunEvents.eventRow returns it; `fields` overrides.
  function eventRow(seq, fields) {
    var row = { seq: seq, time: "12:00:00", level: "attempt", label: "row " + seq, status: "done",
                glyph: "done", duration: "", detail: "", card: "card-" + seq, phase: "implement",
                attempt: 1 }
    for (var key in fields) row[key] = fields[key]
    return row
  }

  function rowsUpTo(n) {
    var rows = []
    for (var i = 1; i <= n; i++) rows.push(eventRow(i, {}))
    return rows
  }

  function shown(s, name) { return H.find(s.screen, name).visible }

  // 6
  function test_run_detail_opens_on_the_output_tab() {
    var s = make(detail()); if (!s) return
    var output = H.find(s.screen, "runTaboutput")
    verify(output, "the Output chip")
    compare(output.text, "Output")
    compare(output.active, true)
    verify(H.find(s.screen, "runTabevents"), "the Events chip")
    compare(H.find(s.screen, "runTabevents").active, false)
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
  }

  // 7
  function test_the_events_chip_counts_rows_held_plus_dropped() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runTabevents").text, "Events 0", "none")
    s.runs.events = rowsUpTo(3)
    s.runs.eventsDropped = 40
    compare(H.find(s.screen, "runTabevents").text, "Events 43")
    s.runs.events = rowsUpTo(5)
    compare(H.find(s.screen, "runTabevents").text, "Events 45")
    s.runs.events = []
    s.runs.eventsDropped = 0
    compare(H.find(s.screen, "runTabevents").text, "Events 0")
  }

  // 8
  function test_the_chips_switch_the_tabs() {
    var s = make(detail()); if (!s) return
    tap(H.find(s.screen, "runTabevents"))
    compare(s.runs.tabCalls.join(","), "events")
    compare(shown(s, "eventsPane"), true)
    compare(shown(s, "runOutputPane"), false)
    compare(H.find(s.screen, "runTabevents").active, true)
    tap(H.find(s.screen, "runTabevents"))
    compare(s.runs.detailTab, "events", "the active chip changes nothing")
    compare(shown(s, "eventsPane"), true)
    tap(H.find(s.screen, "runTaboutput"))
    compare(s.runs.detailTab, "output")
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
    compare(H.find(s.screen, "runTaboutput").active, true)
  }

  // 9
  function test_the_events_pane_shows_the_store_state() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = rowsUpTo(2)
    s.runs.eventsDropped = 3
    s.runs.eventsStatus = "ok"
    var pane = H.find(s.screen, "eventsPane")
    compare(JSON.stringify(pane.rows), JSON.stringify(s.runs.events))
    compare(pane.filter, "All")
    compare(pane.dropped, 3)
    compare(pane.status, "ok")
    compare(pane.errorMessage, "")
    verify(H.find(pane, "eventsRow2"), "the store's rows are drawn")
    compare(H.find(pane, "eventsErrorText").visible, false)
    s.runs.eventsStatus = "error"
    s.runs.eventsError = "AmMissing: am is not on PATH."
    compare(pane.status, "error")
    compare(pane.errorMessage, "AmMissing: am is not on PATH.")
    compare(H.find(pane, "eventsErrorText").visible, true)
  }

  // 10
  function test_a_filter_chip_sets_the_store_filter() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(1, { level: "phase", glyph: "dead", status: "failed" }), eventRow(2, {})]
    var pane = H.find(s.screen, "eventsPane")
    tap(H.find(pane, "eventsFilterChipFailures"))
    compare(s.runs.eventsFilter, "Failures")
    compare(pane.filter, "Failures", "the pane follows the store")
    compare(H.find(pane, "eventsFilterChipFailures").active, true)
  }

  // 11
  function test_a_row_naming_an_attempt_selects_it_and_shows_output() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(5, { card: "t1", phase: "implement", attempt: 1 })]
    wait(30)
    tap(H.find(s.screen, "eventsRow5"))
    compare(s.runs.selected.join("|"), "t1|implement|1|false")
    compare(s.runs.detailTab, "output")
    compare(shown(s, "runOutputPane"), true)
    compare(shown(s, "eventsPane"), false)
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.1")
  }

  // 12
  function test_a_row_without_an_attempt_changes_nothing() {
    var s = make(detail()); if (!s) return
    s.runs.setDetailTab("events")
    s.runs.events = [eventRow(6, { attempt: 0 })]
    wait(30)
    tap(H.find(s.screen, "eventsRow6"))
    compare(s.runs.selected, null)
    compare(s.runs.detailTab, "events")
    compare(s.runs.tabCalls.join(","), "events", "no tab call from the row")
  }

  // 13
  function test_a_missing_run_shows_no_tabs() {
    var s = make(detail(), "run-gone"); if (!s) return
    compare(shown(s, "runDetailBody"), false)
    compare(shown(s, "runTabs"), false)
    compare(shown(s, "runDetailMissing"), true)
  }

  // 14 and Review Focus 3
  function test_garbage_events_count_as_none() {
    failOnWarning(/TypeError|ReferenceError|is not a function|Unable to assign/)
    var s = make(detail()); if (!s) return
    s.runs.eventsDropped = 2
    s.runs.events = null
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "null")
    s.runs.events = "abcdefghi"
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "a string")
    s.runs.events = { length: 9 }
    compare(H.find(s.screen, "runTabevents").text, "Events 2", "an object with a length")
    s.runs.setDetailTab("events")
    compare(shown(s, "eventsPane"), true)
  }

  // Review Focus 1
  function test_rows_that_arrive_while_output_shows_open_at_the_newest() {
    var s = make(detail()); if (!s) return
    s.runs.events = rowsUpTo(60)
    wait(30)
    tap(H.find(s.screen, "runTabevents"))
    wait(30)
    var pane = H.find(s.screen, "eventsPane")
    var list = H.find(pane, "eventsList")
    verify(list.contentHeight > list.height, "the list scrolls")
    compare(pane.following, true)
    verify(Math.abs(list.contentY - (list.originY + list.contentHeight - list.height)) <= 1, "at the newest row")
    compare(H.find(pane, "eventsJump").visible, false)
  }

  // Review Focus 2
  function test_switching_tabs_keeps_the_output_and_the_filter() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "3 passed"
    s.runs.eventsFilter = "Failures"
    tap(H.find(s.screen, "runTabevents"))
    tap(H.find(s.screen, "runTaboutput"))
    compare(H.find(s.screen, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(s.screen, "runOutputText").text, "3 passed")
    compare(s.runs.selected, null, "no attempt was selected")
    compare(s.runs.refreshed, 0, "nothing was fetched")
    compare(s.runs.eventsFilter, "Failures")
  }
}
