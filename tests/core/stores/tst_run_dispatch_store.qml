// tests/core/stores/tst_run_dispatch_store.qml
// The dispatch store: the dispatch state machine (open, the --defaults
// lookup, the debounced check and preview, Start on one runner per Start),
// the story target and retargetToMilestone, and the signals it emits,
// including the run settings it asks for and asks to save. Built alone, and
// wired to a RunStore and a RunControlStore the way App wires
// app.runDispatch, with stubbed Process objects standing in for every helper.
import QtQuick
import QtTest
import "../../../core/domain/runs.js" as Runs

TestCase {
  id: tc
  name: "StoresRunDispatchStore"

  property string rootA: "/home/u/my proj"
  property string rootB: "/home/u/b"
  property string rootC: "/home/u/c"
  property string snapCmd: "python3|/plugin/core/backend/runs/runs-snapshot-all.py"
  property string viewerCmd: "python3|/plugin/core/backend/projects/viewer-state.py|"

  Component { id: spyC; SignalSpy {} }

  // A RunDispatchStore built alone, with nothing bound.
  function makeDispatch() {
    var comp = Qt.createComponent("../../../core/stores/RunDispatchStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
  }

  // Every {dispatch, runs, control} triple make() built.
  property var wired: []

  // A RunStore, a RunControlStore wired to it the way App wires
  // app.runControl, and a RunDispatchStore wired to both the way App wires
  // app.runDispatch: backendDir copied; project, active and runs bound to the
  // run store's own, runSettings to the control store's
  // runSettingsOf(project), projectRoots to the run store's; refreshRequested
  // to refresh() ("all") or requestSnapshot(roots); noticeRequested to the
  // control store's flash; runSettingsWanted and runSettingsSaveRequested to
  // its loadRunSettings and saveRunSettings, and its runSettingsSaveFailed
  // and runSettingsLoaded back to dispatchSaveFailed and
  // dispatchSettingsReplied.
  // Returns the dispatch store.
  function make() {
    var runsComp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (runsComp.status !== Component.Ready) { fail(runsComp.errorString()); return null }
    var store = runsComp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var controlComp = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (controlComp.status !== Component.Ready) { fail(controlComp.errorString()); return null }
    var c = controlComp.createObject(tc, { backendDir: store.backendDir })
    c.project = Qt.binding(function() { return store.project })
    c.active = Qt.binding(function() { return store.active })
    c.runs = Qt.binding(function() { return store.runs })
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
    c.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    var d = makeDispatch(); if (!d) return null
    d.backendDir = store.backendDir
    d.project = Qt.binding(function() { return store.project })
    d.active = Qt.binding(function() { return store.active })
    d.runs = Qt.binding(function() { return store.runs })
    d.runSettings = Qt.binding(function() { return c.runSettingsOf(store.project) })
    d.projectRoots = Qt.binding(function() { return store.projectRoots })
    d.refreshRequested.connect(function(roots) {
      if (roots === "all") store.refresh()
      else store.requestSnapshot(roots)
    })
    d.noticeRequested.connect(function(text) { c.flash(text) })
    d.runSettingsWanted.connect(function(root) { c.loadRunSettings(root) })
    d.runSettingsSaveRequested.connect(function(root, patch) { c.saveRunSettings(root, patch) })
    c.runSettingsSaveFailed.connect(function(root, patch) { d.dispatchSaveFailed(root, patch) })
    c.runSettingsLoaded.connect(function(root, settings) { d.dispatchSettingsReplied(root, settings) })
    tc.wired = tc.wired.concat([{ dispatch: d, runs: store, control: c }])
    return d
  }

  // The RunStore make() paired with dispatch store `d`; null when none.
  function runsOf(d) {
    for (var i = 0; i < tc.wired.length; i++) {
      if (tc.wired[i].dispatch === d) return tc.wired[i].runs
    }
    return null
  }

  // The RunControlStore make() paired with dispatch store `d`; null when none.
  function controlOf(d) {
    for (var i = 0; i < tc.wired.length; i++) {
      if (tc.wired[i].dispatch === d) return tc.wired[i].control
    }
    return null
  }

  // The paired control store's newest run settings load; null once it replied.
  function loadOf(d) { return controlOf(d).runSettingsLoadRunner }

  // The paired control store's newest run settings save in flight; null when none.
  function saveOf(d) {
    var saves = controlOf(d).runSettingsRunners.filter(function(r) { return r.saving })
    return saves.length > 0 ? saves[saves.length - 1] : null
  }

  // A root's registry entry: rootA is "alpha", rootB "beta", any other "proj".
  function rootEntry(root) {
    return { root: root, name: root === tc.rootA ? "alpha" : root === tc.rootB ? "beta" : "proj" }
  }

  // The registry of `roots`, in that order, as App hands it over.
  function registry(roots) {
    return roots.map(function(r) { return tc.rootEntry(r) })
  }

  // make() with `roots` registered and no project open: the snapshot of
  // every root is in flight.
  function makeWithRoots(roots) {
    var d = make(); if (!d) return null
    runsOf(d).projectRoots = registry(roots)
    return d
  }

  // make() with one registered project, `root`, open: its first snapshot (of
  // that root alone) and its run settings load are in flight.
  function makeWithProject(root) {
    var d = make(); if (!d) return null
    runsOf(d).projectRoots = [rootEntry(root)]
    runsOf(d).project = root
    return d
  }

  // makeWithProject(root) with the panel open.
  function activeStore(root) {
    var d = make(); if (!d) return null
    runsOf(d).active = true
    runsOf(d).projectRoots = [rootEntry(root)]
    runsOf(d).project = root
    return d
  }

  // A stubbed process's reply: its stdout, then its exit code.
  function reply(proc, text, code) {
    proc.outText = text
    proc.exited(code)
  }

  // A process's argv, joined with "|".
  function argv(proc) { return proc.command.join("|") }

  // A timer firing on its own: a one-shot timer has stopped by the time its
  // triggered() is emitted.
  function fire(timer) {
    if (!timer.repeat) timer.stop()
    timer.triggered()
  }

  function ctlFail(type, message) {
    return JSON.stringify({ ok: false, error: { type: type, message: message } }) + "\n"
  }

  // runs-snapshot-all.py's reply line: {"ok": true, "projects": projects, "data_dir"}.
  function allReply(projects) {
    return JSON.stringify({ ok: true, projects: projects, data_dir: "/home/u/.local/share" }) + "\n"
  }

  // One root's entry that answered, listing `runs`.
  function okEntry(root, runs) { return { root: root, ok: true, runs: runs } }

  // A reply where every root answered: rootA's entry, then one per other
  // root the entries' repo_dir names, in first-seen order, each listing the
  // entries with that repo_dir.
  function okReply(entries) {
    var order = [tc.rootA]
    var byRoot = {}
    byRoot[tc.rootA] = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var root = e !== null && typeof e === "object" && typeof e.repo_dir === "string" ? e.repo_dir : tc.rootA
      if (!byRoot.hasOwnProperty(root)) {
        byRoot[root] = []
        order.push(root)
      }
      byRoot[root].push(e)
    }
    return allReply(order.map(function(r) { return tc.okEntry(r, byRoot[r]) }))
  }

  // ---- the store alone (split-runstore 4.1)

  // A bare store on project A with dispatchSettings() as its run settings and
  // milestone m1's preview landed: Start is allowed.
  function bareReady() {
    var d = makeDispatch(); if (!d) return null
    d.project = tc.rootA
    d.runSettings = JSON.parse(dispatchSettings())
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchState, "ready")
    return d
  }

  // D-N1
  function test_a_bare_dispatch_store_is_idle_with_empty_inputs() {
    var d = makeDispatch(); if (!d) return
    checkDispatchIdle(d, "bare")
    compare(d.backendDir, "/plugin/core/backend/")
    compare(d.project, "")
    compare(d.active, false)
    compare(d.runs.length, 0)
    compare(Object.keys(d.runSettings).length, 0)
    compare(d.dispatchStartRunners.length, 0)
    compare(d.dispatchDebounceTimer.running, false)
    verify(!d.dispatchDefaultsRunner.current)
    verify(!d.dispatchPreviewRunner.current)
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), false, "no project: refused")
    checkDispatchIdle(d, "after the refused opening")
  }

  // D-N2 (A.3: the store's own active reaction)
  function test_its_own_active_closes_it_but_not_a_start() {
    var d = makeDispatch(); if (!d) return
    d.project = tc.rootA
    d.runSettings = JSON.parse(dispatchSettings())
    d.active = true
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(d.dispatchState, "previewing")
    d.active = false
    checkDispatchIdle(d, "closed")

    d.active = true
    checkDispatchIdle(d, "opening the panel does nothing")
    compare(d.openDispatch(cards.m1, cards), true)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchState, "ready")
    compare(d.dispatchStart(), true)
    var proc = d.dispatchStartRunners[0].current
    d.active = false
    compare(d.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
  }

  // D-N3 (A.3: the store's own project reaction)
  function test_its_own_project_change_resets_it_and_keeps_a_start_running() {
    var d = bareReady(); if (!d) return
    var started = spyC.createObject(tc, { target: d, signalName: "dispatchStarted" })
    var refresh = spyC.createObject(tc, { target: d, signalName: "refreshRequested" })
    var saves = spyC.createObject(tc, { target: d, signalName: "runSettingsSaveRequested" })
    compare(d.dispatchStart(), true)
    var runner = d.dispatchStartRunners[0]
    var proc = runner.current
    d.project = tc.rootB
    checkDispatchIdle(d, "after the switch from starting")
    compare(proc.running, true, "the start is not stopped")
    reply(proc, startOk("r-1", ""), 0)
    checkDispatchIdle(d, "after A's late start")
    compare(started.count, 0)
    compare(refresh.count, 0)
    compare(saves.count, 1, "the save is still asked for")
    compare(saves.signalArguments[0][0], tc.rootA, "recorded against A")
    compare(JSON.stringify(saves.signalArguments[0][1]), tc.savedJson)
    compare(d.dispatchStartRunners.length, 0)
  }

  // D-N4 (the coupling order of an ok start)
  function test_a_start_reply_emits_settings_then_refresh_then_started() {
    var d = bareReady(); if (!d) return
    var record = []
    var root = ""
    var patch = null
    var stateAtSettings = ""
    var stateAtStarted = ""
    d.runSettingsSaveRequested.connect(function(r, p) {
      record.push("settings")
      root = r
      patch = p
      stateAtSettings = d.dispatchState
    })
    d.refreshRequested.connect(function(roots) { record.push("refresh:" + JSON.stringify(roots)) })
    d.dispatchStarted.connect(function(runId) {
      record.push("started:" + runId)
      stateAtStarted = d.dispatchState
    })
    compare(d.dispatchStart(), true)
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(JSON.stringify(record), JSON.stringify(["settings", 'refresh:["/home/u/my proj"]', "started:r-1"]))
    compare(stateAtSettings, "starting", "the save is asked for before started")
    compare(stateAtStarted, "started")
    compare(root, tc.rootA)
    compare(patch.prefixHistory.join(","), "old")
    compare(patch.parallelism, 4)
    compare(patch.confirmDispatch, undefined, "the patch holds only what the start writes")
    compare(patch.prefixByMilestone.m1, "old")
    compare(d.dispatchStartRunners.length, 0)
  }

  // D-N5 (Review Focus 3 of 4.1)
  function test_the_store_never_writes_its_own_run_settings() {
    var d = makeDispatch(); if (!d) return
    var s = JSON.parse(dispatchSettings())
    d.project = tc.rootA
    d.runSettings = s
    var cards = dispatchCards()
    d.openDispatch(cards.m1, cards)
    reply(d.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(d.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(d.dispatchStart(), true)
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(d.dispatchState, "started")
    verify(d.runSettings === s, "the input is left as it was handed over")
    compare(d.runSettings.prefixByMilestone, undefined)
    compare(d.dispatchStartRunners.length, 0)
  }

  // bareReady() after an ok Start: `started`.
  function bareStarted() {
    var d = bareReady(); if (!d) return null
    compare(d.dispatchStart(), true)
    reply(d.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(d.dispatchState, "started")
    return d
  }

  // D-N6 (A.3: the notice) and Review Focus 5
  function test_a_failed_save_notices_only_while_it_is_this_dispatchs() {
    var d = bareStarted(); if (!d) return
    var notices = spyC.createObject(tc, { target: d, signalName: "noticeRequested" })
    d.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(notices.count, 1)
    compare(notices.signalArguments[0][0], "Dispatch settings could not be saved")
    d.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(notices.count, 1, "said once")

    var other = bareStarted(); if (!other) return
    var otherNotices = spyC.createObject(tc, { target: other, signalName: "noticeRequested" })
    other.dispatchSaveFailed(tc.rootA, { parallelism: 1 })
    other.dispatchSaveFailed(tc.rootB, JSON.parse(tc.savedJson))
    compare(otherNotices.count, 0, "another save's failure says nothing")

    var left = bareStarted(); if (!left) return
    var leftNotices = spyC.createObject(tc, { target: left, signalName: "noticeRequested" })
    left.project = tc.rootB
    left.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(leftNotices.count, 0, "no notice about A once the project changed")

    var closed = bareStarted(); if (!closed) return
    var closedNotices = spyC.createObject(tc, { target: closed, signalName: "noticeRequested" })
    compare(closed.closeDispatch(), true)
    closed.dispatchSaveFailed(tc.rootA, JSON.parse(tc.savedJson))
    compare(closedNotices.count, 0, "no notice once the dispatch was closed")
  }

  // D-N7 (the store's own project reaction asks for the run settings)
  function test_its_own_project_change_wants_the_run_settings() {
    var d = makeDispatch(); if (!d) return
    var wanted = spyC.createObject(tc, { target: d, signalName: "runSettingsWanted" })
    var states = []
    d.runSettingsWanted.connect(function(root) { states.push(d.dispatchState) })
    d.project = tc.rootA
    compare(wanted.count, 1)
    compare(wanted.signalArguments[0][0], tc.rootA)
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    compare(d.dispatchState, "previewing")
    d.project = tc.rootB
    compare(wanted.count, 2)
    compare(wanted.signalArguments[1][0], tc.rootB)
    d.project = ""
    compare(wanted.count, 2, "no project: nothing is wanted")
    compare(states.join(","), "idle,idle", "the store is reset before it asks")
  }

  // D-N8
  function test_a_start_launches_no_viewer_state_and_a_failed_start_saves_nothing() {
    var d = bareReady(); if (!d) return
    var saves = spyC.createObject(tc, { target: d, signalName: "runSettingsSaveRequested" })
    compare(d.dispatchStart(), true)
    var proc = d.dispatchStartRunners[0].current
    compare(argv(proc).indexOf("viewer-state.py"), -1)
    reply(proc, startOk("r-1", ""), 0)
    compare(d.dispatchStartRunners.length, 0, "no runner is left to write the settings")
    compare(saves.count, 1, "the save is only asked for")
    var replies = [ctlFail("AmExited", "am run exited at once (exit 2)"), startBlocked()]
    for (var i = 0; i < replies.length; i++) {
      var failed = bareReady(); if (!failed) return
      var none = spyC.createObject(tc, { target: failed, signalName: "runSettingsSaveRequested" })
      compare(failed.dispatchStart(), true)
      reply(failed.dispatchStartRunners[0].current, replies[i], 0)
      compare(none.count, 0, "reply " + i + ": nothing saved")
      compare(failed.dispatchStartRunners.length, 0, "reply " + i)
    }
  }
  // ---- dispatch (S3 3.1)

  property string previewCmd: "python3|/plugin/core/backend/runs/dispatch-preview.py|"
  property string startCmd: "python3|/plugin/core/backend/runs/start-run.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // Project A with its run settings read (dispatchSettings).
  function dispatchStore() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(loadOf(store).current, dispatchSettings(), 0)
    return store
  }

  // Every dispatch field at its "none" value.
  // S3's dispatch fields at their "none" values.
  function checkDispatchFieldsIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
    compare(store.dispatchTarget, null, label + ": target")
    compare(store.dispatchForm, null, label + ": form")
    compare(store.dispatchPreview, null, label + ": preview")
    compare(store.dispatchError, "", label + ": error")
    compare(store.dispatchErrorType, "", label + ": error type")
    compare(store.dispatchErrors.length, 0, label + ": errors")
    compare(store.dispatchSuggest, null, label + ": suggest")
    compare(store.dispatchRunId, "", label + ": run id")
    compare(store.dispatchMessage, "", label + ": message")
    compare(store.dispatchLog, "", label + ": log")
    compare(store.dispatchLogTail, "", label + ": log tail")
    compare(store.dispatchExitCode, null, label + ": exit code")
    compare(store.dispatchTargetLabel, "", label + ": target label")
  }

  function checkDispatchIdle(store, label) {
    checkDispatchFieldsIdle(store, label)
    compare(store.dispatchStep, "", label + ": step")
    compare(store.dispatchTargetRows.length, 0, label + ": target rows")
    compare(store.dispatchTargetCardMap, null, label + ": target card map")
    compare(store.dispatchTargetLoading, false, label + ": target loading")
    compare(store.dispatchTargetKey, "", label + ": target key")
  }

  // 1 (dispatchStart() from idle is checked in Task 5's test 21)
  function test_dispatch_starts_idle() {
    var store = make(); if (!store) return
    checkDispatchIdle(store, "fresh")
    compare(store.dispatchStartRunners.length, 0)
    compare(store.dispatchDebounceTimer.running, false)
    verify(!store.dispatchDefaultsRunner.current)
    verify(!store.dispatchPreviewRunner.current)
    compare(store.closeDispatch(), true, "closing an idle dispatch is fine")
    checkDispatchIdle(store, "after close")
  }

  // 2
  function test_open_without_project_is_refused() {
    var store = make(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), false)
    checkDispatchIdle(store, "no project")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
  }

  // 3
  function test_open_milestone_goes_previewing_and_asks_defaults() {
    var store = makeWithProject(rootA); if (!store) return
    reply(loadOf(store).current, JSON.stringify({ verify: ["uv run pytest", "  "], allowNoVerification: true,
      notifyOnEscalation: false, prefixHistory: [], parallelism: 6, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTarget.command, "milestone")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(proc.command[3], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.base, "", "no base until the lookup replies")
    compare(form.prefix, "m3")
    compare(form.verify.length, 1, "the stored non-blank commands")
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 6)
    compare(form.allowNoVerification, false, "the opt-out is never pre-ticked")
    verify(!store.dispatchPreviewRunner.current, "no preview before the default branch is known")
    compare(store.dispatchDebounceTimer.running, false)
  }

  function test_open_before_the_settings_reply_starts_from_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.verify.length, 0)
    compare(store.dispatchForm.parallelism, 4)
    reply(loadOf(store).current, dispatchSettings(), 0)
    compare(store.dispatchForm.verify.length, 0, "a late settings reply does not touch the open form")
    compare(store.runSettings.verify[0], "uv run pytest", "but it is kept for the next opening")
  }

  // 4
  function test_open_story_is_offered_with_the_story_flag() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.s1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchTarget.command, "story")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--story", "s1"]))
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    verify(store.dispatchForm, "an offered target has a form")
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the story's prefix")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.running, true)
  }

  // 5
  function test_open_done_card_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.d1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.openDispatch(null, cards), false)
    compare(store.dispatchError, "No card to dispatch")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  function test_close_and_reopen_drop_the_pending_lookup() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var first = store.dispatchDefaultsRunner.current
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
    compare(first.running, false, "the lookup is stopped")
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchState, "refused")
    compare(store.openDispatch(cards.m1, cards), true, "opening again replaces a refused target")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchSuggest, null)
    verify(store.dispatchDefaultsRunner.current !== first, "a fresh lookup per opening")
  }

  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  // Project A with milestone m1 opened and its default branch `main` read: the
  // first preview is in flight.
  function previewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 6
  function test_defaults_reply_sets_base_and_launches_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchDebounceTimer.running, false, "the check runs at once, no debounce")
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a preview was launched")
    compare(argv(proc), tc.previewCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.command[2], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.command[12], "uv run pytest", "a command with spaces is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  // 8 + Review Focus 2
  function test_defaults_failure_sends_no_base() {
    var replies = [JSON.stringify({ ok: false, error: { type: "NoDefaultBranch", message: "detached HEAD" } }) + "\n",
                   "Traceback: boom\n",
                   defaultsOk("   "),
                   JSON.stringify({ ok: true, data: { default_branch: null, source: "" } }) + "\n",
                   JSON.stringify({ ok: true }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      store.openDispatch(cards.m1, cards)
      reply(store.dispatchDefaultsRunner.current, replies[i], 1)
      compare(store.dispatchForm.base, "", "reply " + i + " leaves base blank")
      var proc = store.dispatchPreviewRunner.current
      verify(proc, "reply " + i + ": the check still runs")
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest",
              "reply " + i + ": no --base-branch pair")
    }
    var padded = dispatchStore(); if (!padded) return
    var map = dispatchCards()
    padded.openDispatch(map.m1, map)
    reply(padded.dispatchDefaultsRunner.current, defaultsOk("  main \n"), 0)
    compare(padded.dispatchForm.base, "main", "the branch is trimmed")
    compare(padded.dispatchPreviewRunner.current.command[6], "main")
  }

  // 10
  function test_preview_ok_goes_ready_with_summary() {
    var store = previewingStore(); if (!store) return
    compare(store.dispatchPreview, null)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done")
    compare(store.dispatchPreview.integrate, "Integrate → m3-integrate")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 11
  function test_preview_refusal_goes_refused_verbatim() {
    var store = previewingStore(); if (!store) return
    var message = "milestone m1 is claimed by run 20261005T010000Z-abcd (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchPreview, null)
    var untyped = previewingStore(); if (!untyped) return
    reply(untyped.dispatchPreviewRunner.current,
          JSON.stringify({ ok: false, error: { type: 7, message: "dependency cycle: s1 -> s2 -> s1" } }) + "\n", 0)
    compare(untyped.dispatchState, "refused")
    compare(untyped.dispatchError, "dependency cycle: s1 -> s2 -> s1")
    compare(untyped.dispatchErrorType, "", "a type that is not a string is unknown")
  }

  // 12
  function test_preview_unreadable_goes_refused() {
    var replies = ["", "Traceback: boom\n", "[1, 2]\n",
                   JSON.stringify({ ok: false, error: { type: "X", message: "  " } }) + "\n",
                   JSON.stringify({ ok: false, error: "boom" }) + "\n",
                   JSON.stringify({ ok: false, error: null }) + "\n",
                   JSON.stringify({ ok: "yes" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = previewingStore(); if (!store) return
      reply(store.dispatchPreviewRunner.current, replies[i], 1)
      compare(store.dispatchState, "refused", "reply " + i)
      compare(store.dispatchError, "The preview could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchPreview, null, "reply " + i)
    }
  }

  // 14
  function test_invalid_form_is_refused_without_launch() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch("board", cards), true)
    compare(store.dispatchTarget.level, "board")
    compare(store.dispatchForm.prefix, "", "the board has no milestone title to stem")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Form")
    compare(store.dispatchErrors.length, 1)
    compare(store.dispatchErrors[0].field, "prefix")
    compare(store.dispatchError, "Enter a branch prefix")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  // 20 (the preview half)
  function test_subtask_goes_ready_without_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), true)
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "old", "the history's first prefix names the subtask's prefix")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview, null, "am has no dry run for one card")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  function test_a_closed_dispatch_drops_the_late_defaults_reply() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var lookup = store.dispatchDefaultsRunner.current
    store.closeDispatch()
    reply(lookup, defaultsOk("main"), 0)
    checkDispatchIdle(store, "after the late reply")
    verify(!store.dispatchPreviewRunner.current, "no preview")
  }

  // 7
  function test_defaults_reply_keeps_a_user_set_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("base", "develop"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "develop", "the user's base wins over the lookup")
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
  }

  // 9
  function test_debounce_waits_for_defaults() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("prefix", "m3b"), true)
    compare(store.dispatchDebounceTimer.running, true)
    fire(store.dispatchDebounceTimer)
    verify(!store.dispatchPreviewRunner.current, "nothing launched before the default branch is known")
    compare(store.dispatchState, "previewing")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the defaults reply checks the form")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3b|--max-concurrent|4|--verify|uv run pytest")

    var early = dispatchStore(); if (!early) return
    early.openDispatch(cards.m1, cards)
    early.setDispatchField("parallelism", 2)
    reply(early.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(early.dispatchDebounceTimer.running, false, "the defaults reply's check replaces the pending one")
    compare(early.dispatchPreviewRunner.current.command[10], "2")
  }

  // 13
  function test_board_preview_argv() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch("board", cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused", "the board starts with no prefix")
    compare(store.setDispatchField("prefix", " all "), true)
    fire(store.dispatchDebounceTimer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the board is previewed")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|board|--base-branch|main|--branch-prefix|all|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 12)
    var board = { board: true, levels: [{ level: 0, milestones: [{ milestone_id: "m1", title: "M3", branch_prefix: "m3",
                                                                   base_branch: "main", plan: dispatchDryRun() }] }] }
    reply(proc, previewOk(board), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "1 milestone, 3 subtasks")
    compare(store.dispatchPreview.board, true)
  }

  // 15 + Review Focus 1
  function test_allow_no_verification_flag() {
    var store = previewingStore(); if (!store) return
    store.setDispatchField("verify", [])
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "no command and no opt-out")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "previewing")
    var proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
    store.setDispatchField("verify", ["", "  ", "-x make check", "uv run pytest"])
    fire(store.dispatchDebounceTimer)
    proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
    compare(proc.command[12], "-x make check", "a command that starts with a dash is one verbatim argument")
    store.setDispatchField("allowNoVerification", "yes")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchPreviewRunner.current.command[store.dispatchPreviewRunner.current.command.length - 1], "uv run pytest",
            "only a real true sends the opt-out")
  }

  // Review Focus 4 (the form half)
  function test_a_verify_value_that_is_not_a_list_is_refused_not_thrown() {
    var store = previewingStore(); if (!store) return
    compare(store.setDispatchField("verify", "uv run pytest"), true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    store.setDispatchField("parallelism", "4")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "the store converts nothing")
    compare(store.dispatchErrors[0].field, "parallelism")
    store.setDispatchField("parallelism", 4)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--allow-no-verification")
  }

  // 16
  function test_change_restarts_400ms_debounce_and_one_preview_per_burst() {
    var store = previewingStore(); if (!store) return
    var timer = store.dispatchDebounceTimer
    compare(timer.objectName, "dispatchDebounceTimer")
    compare(timer.interval, 400)
    compare(timer.repeat, false)
    var first = store.dispatchPreviewRunner.current
    compare(store.setDispatchField("prefix", "a"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("prefix", "ab"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("parallelism", 2), true)
    compare(store.dispatchState, "previewing")
    compare(timer.running, true)
    verify(store.dispatchPreviewRunner.current === first, "nothing launched during the burst")
    compare(first.running, false, "the preview in flight was cancelled")
    fire(timer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc !== first, "one preview for the burst")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|ab|--max-concurrent|2|--verify|uv run pytest")
  }

  // 17
  function test_latest_preview_wins() {
    var store = previewingStore(); if (!store) return
    var first = store.dispatchPreviewRunner.current
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    var second = store.dispatchPreviewRunner.current
    verify(second !== first, "a second preview")
    reply(first, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "previewing", "the older preview's reply is dropped")
    compare(store.dispatchPreview, null)
    reply(second, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    verify(store.dispatchPreview !== null)
  }

  // 18
  function test_change_after_ready_drops_preview_and_goes_previewing() {
    var store = previewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    var form = store.dispatchForm
    var list = ["make test"]
    compare(store.setDispatchField("verify", list), true)
    list.push("rm -rf /")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchPreview, null)
    compare(form.verify[0], "uv run pytest", "the old form was not changed in place")
    compare(store.dispatchForm.verify.length, 1, "verify is copied")
    compare(store.dispatchForm.verify[0], "make test")
    compare(store.dispatchForm.prefix, "old", "the other fields are kept")
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchDebounceTimer.running, true)
  }

  // 19
  function test_set_unknown_field_or_while_idle_is_refused() {
    var store = dispatchStore(); if (!store) return
    compare(store.setDispatchField("prefix", "x"), false, "idle")
    compare(store.dispatchForm, null)
    var cards = dispatchCards()
    store.openDispatch(cards.d1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("branch", "x"), false, "unknown field")
    compare(store.setDispatchField("__proto__", {}), false)
    compare(store.dispatchForm.prefix, "old", "nothing changed")
    compare(store.dispatchForm.branch, undefined)
    compare(store.dispatchDebounceTimer.running, false)
  }

  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // Project A with milestone m1's preview landed: Start is allowed.
  function readyStore() {
    var store = previewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    return store
  }

  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}'

  // 20 (the start half)
  function test_subtask_start_argv_uses_card() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.t1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchStart(), true)
    var proc = store.dispatchStartRunners[0].current
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 13)
  }

  // 21 + Review Focus 3
  function test_start_refused_unless_ready() {
    var store = dispatchStore(); if (!store) return
    compare(store.dispatchStart(), false, "idle")
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchStart(), false, "previewing")
    store.openDispatch(cards.d1, cards)
    compare(store.dispatchStart(), false, "refused")
    compare(store.dispatchStartRunners.length, 0, "no start runner")
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStart(), false, "a fresh store")
    var ready = readyStore(); if (!ready) return
    compare(ready.dispatchStart(), true)
    compare(ready.dispatchStart(), false, "a second Start while starting")
    compare(ready.dispatchStartRunners.length, 1, "one launch for a double click")
  }

  // 22
  function test_start_argv_and_starting() {
    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    compare(store.dispatchState, "starting")
    compare(store.dispatchStartRunners.length, 1)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/my proj")
    compare(runner.guard, "", "a preview or a project switch never stops a start")
    var proc = runner.current
    compare(argv(proc), tc.startCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.running, true)
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done", "the preview stays up while starting")
  }

  // 23
  function test_change_and_close_refused_while_starting() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    compare(store.setDispatchField("prefix", "x"), false)
    compare(store.dispatchForm.prefix, "old")
    compare(store.closeDispatch(), false)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchDebounceTimer.running, false)
  }

  // 24
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
    reply(runsOf(store).snapshotRunner.current, okReply([]), 0)
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var seq = runsOf(store).snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-1")
    compare(store.dispatchMessage, "")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(runsOf(store).snapshotRunner.seq, seq + 1, "the runs are fetched again")
    compare(argv(runsOf(store).snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
    compare(store.dispatchStartRunners.length, 0, "the start runner goes at its reply")
    verify(saveOf(store), "run control writes the settings")
    var save = saveOf(store).current
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.verify.join(","), "uv run pytest")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.allowNoVerification, false)
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0, "the start runner is already gone")
    compare(controlOf(store).runSettingsRunners.length, 0, "the save's runner goes after the write")
    compare(controlOf(store).flashText, "")
    compare(store.dispatchState, "started")
  }

  // 25 + Review Focus 5 (run id half)
  function test_start_ok_without_run_id_emits_null() {
    var ids = [null, "", 42]
    for (var i = 0; i < ids.length; i++) {
      var store = readyStore(); if (!store) return
      var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk(ids[i], "started, run not visible yet"), 0)
      compare(store.dispatchState, "started", "run_id " + i)
      compare(store.dispatchRunId, "", "run_id " + i)
      compare(store.dispatchMessage, "started, run not visible yet")
      compare(spy.count, 1)
      compare(spy.signalArguments[0][0], null, "run_id " + i + ": not visible yet")
    }
  }

  // 26 + Review Focus 4 (the history half)
  function test_prefix_history_dedups_and_caps_at_20() {
    var store = makeWithProject(rootA); if (!store) return
    var history = ["a", "m3", "", "  ", 7, "b"]
    for (var i = 0; i < 25; i++) history.push("p" + i)
    reply(loadOf(store).current, JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false,
      notifyOnEscalation: false, prefixHistory: history, parallelism: 4, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "  m3 ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3", "the prefix is sent trimmed")
    reply(runner.current, startOk("r-1", ""), 0)
    var expected = ["m3", "a", "b"]
    for (var j = 0; j < 17; j++) expected.push("p" + j)
    var saved = JSON.parse(saveOf(store).current.command[4])
    compare(saved.prefixHistory.length, 20)
    compare(saved.prefixHistory.join(","), expected.join(","))
    compare(store.runSettings.prefixHistory.join(","), expected.join(","))

    var bare = makeWithProject(rootA); if (!bare) return
    reply(loadOf(bare).current, "Traceback: boom\n", 1)
    bare.openDispatch(cards.m1, cards)
    reply(bare.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    bare.setDispatchField("verify", ["make test"])
    fire(bare.dispatchDebounceTimer)
    reply(bare.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(bare.dispatchStart(), true)
    var bareRunner = bare.dispatchStartRunners[0]
    reply(bareRunner.current, startOk("r-2", ""), 0)
    compare(argv(saveOf(bare).current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4,"prefixByMilestone":{"m1":"m3"}}')
  }

  // 27
  function test_start_failure_goes_failed_with_log() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, JSON.stringify({ ok: false, error: { type: "AmExited", message: "am run exited at once (exit 2)" },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: milestone m1 not found" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "am run exited at once (exit 2)")
    compare(store.dispatchErrorType, "AmExited")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "error: milestone m1 not found")
    compare(store.dispatchExitCode, 2)
    compare(spy.count, 0)
    compare(store.dispatchStartRunners.length, 0, "no settings write after a failed start")
    compare(store.runSettings.prefixHistory.join(","), "old", "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays for another try")
  }

  // 28 + Review Focus 5 (exit code half)
  function test_start_unreadable_goes_failed() {
    var replies = ["", "Traceback: boom\n", JSON.stringify({ ok: "maybe" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, replies[i], 1)
      compare(store.dispatchState, "failed", "reply " + i)
      compare(store.dispatchError, "The launch could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchLog, "", "reply " + i)
      compare(store.dispatchExitCode, null, "reply " + i)
      compare(store.dispatchStartRunners.length, 0, "reply " + i)
    }
    var blank = readyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, JSON.stringify({ ok: false, error: { type: "SpawnFailed", message: " " },
      log: "/tmp/l", exit_code: "2", log_tail: 5 }) + "\n", 0)
    compare(blank.dispatchState, "failed")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "SpawnFailed")
    compare(blank.dispatchLog, "/tmp/l")
    compare(blank.dispatchLogTail, "", "a log tail that is not a string")
    compare(blank.dispatchExitCode, null, "an exit code that is not a number")
  }

  // 29
  function test_failed_then_change_previews_again() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, ctlFail("ClaimedError", "claimed by r-0"), 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchStart(), false, "a failed start is not retried without a new check")
    compare(store.setDispatchField("prefix", "m3-retry"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchLog, "")
    compare(store.dispatchExitCode, null)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3-retry|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 1)
  }

  // A card dispatch's start re-snapshots its dispatchRoot (the open project) only.
  function test_a_dispatch_start_refreshes_only_its_root() {
    var store = makeWithRoots([tc.rootA, tc.rootB]); if (!store) return
    runsOf(store).project = rootA
    reply(loadOf(store).current, dispatchSettings(), 0)
    reply(runsOf(store).snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var seq = runsOf(store).snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(runsOf(store).snapshotRunner.seq, seq + 1, "one snapshot")
    compare(argv(runsOf(store).snapshotRunner.current), tc.snapCmd + "|" + tc.rootA)
  }

  // 30
  function test_settings_write_failure_flashes() {
    var replies = [JSON.stringify({ ok: false, error: { type: "Invalid", message: "x" } }) + "\n", "garbage\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      var runner = store.dispatchStartRunners[0]
      reply(runner.current, startOk("r-1", ""), 0)
      reply(saveOf(store).current, replies[i], 1)
      compare(controlOf(store).flashText, "Dispatch settings could not be saved", "reply " + i)
      compare(store.dispatchState, "started", "the run still started")
      compare(store.dispatchStartRunners.length, 0)
      compare(controlOf(store).notifyOnEscalation, false, "the notify switch is untouched")
      verify(!controlOf(store).settingsSaveRunner.current, "the notify switch's runner is not used")
    }
  }

  function test_started_refuses_changes_and_reopening_starts_over() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.setDispatchField("prefix", "x"), false, "started")
    compare(store.dispatchStart(), false, "started")
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRunId, "")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchForm.verify[0], "uv run pytest", "the next form starts from the saved values")
  }

  // 31
  function test_project_switch_resets_dispatch_and_drops_old_preview() {
    var store = previewingStore(); if (!store) return
    var preview = store.dispatchPreviewRunner.current
    runsOf(store).project = rootB
    checkDispatchIdle(store, "after the switch")
    compare(Object.keys(store.runSettings).length, 0)
    compare(preview.running, false, "A's preview is stopped")
    reply(preview, previewOk(dispatchDryRun()), 0)
    checkDispatchIdle(store, "after A's late preview")

    var pending = previewingStore(); if (!pending) return
    pending.setDispatchField("prefix", "x")
    compare(pending.dispatchDebounceTimer.running, true)
    runsOf(pending).project = rootB
    compare(pending.dispatchDebounceTimer.running, false, "no check is left pending")
    checkDispatchIdle(pending, "switch during a burst")

    var cleared = previewingStore(); if (!cleared) return
    runsOf(cleared).project = ""
    checkDispatchIdle(cleared, "no project")
  }

  // 32
  function test_start_result_belongs_to_its_project() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var startProc = runner.current
    runsOf(store).project = rootB
    checkDispatchIdle(store, "B after the switch from starting")
    compare(startProc.running, true, "the start is not stopped")
    compare(store.dispatchStartRunners.length, 1)
    var seq = runsOf(store).snapshotRunner.seq
    reply(startProc, startOk("r-1", ""), 0)
    checkDispatchIdle(store, "B after A's start landed")
    compare(spy.count, 0)
    compare(runsOf(store).snapshotRunner.seq, seq, "no refresh for B")
    compare(Object.keys(store.runSettings).length, 0, "B's settings do not take A's values")
    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(saveOf(store).current, "garbage\n", 1)
    compare(controlOf(store).flashText, "", "no flash about A in B")
    compare(store.dispatchStartRunners.length, 0)
  }

  // 32b
  function test_start_reply_after_switching_away_and_back_is_not_here() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    runsOf(store).project = rootB
    runsOf(store).project = rootA
    checkDispatchIdle(store, "back in A")
    reply(loadOf(store).current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(store.dispatchRunId, "")
    compare(spy.count, 0)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
  }

  // 33
  function test_start_in_other_project_does_not_stop_the_first() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var procA = store.dispatchStartRunners[0].current
    runsOf(store).project = rootB
    reply(loadOf(store).current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true, "B's dispatch opens while A's start is in flight")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 2)
    compare(store.dispatchStartRunners[0].madeFor, "/home/u/my proj")
    compare(store.dispatchStartRunners[1].madeFor, "/home/u/b")
    compare(procA.running, true, "A's start is still running")
    var procB = store.dispatchStartRunners[1].current
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(procA, startOk("r-a", ""), 0)
    compare(store.dispatchState, "starting", "A's reply does not land in B's dialog")
    reply(procB, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
  }

  // 34
  function test_panel_close_closes_dispatch_but_not_a_start() {
    var store = activeStore(rootA); if (!store) return
    reply(loadOf(store).current, dispatchSettings(), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    runsOf(store).active = false
    checkDispatchIdle(store, "closed from ready")

    runsOf(store).active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "x")
    compare(store.dispatchDebounceTimer.running, true)
    runsOf(store).active = false
    compare(store.dispatchDebounceTimer.running, false, "no timer while idle")
    checkDispatchIdle(store, "closed during a burst")

    runsOf(store).active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    runsOf(store).active = false
    compare(store.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started", "it lands normally")
    compare(store.dispatchRunId, "r-1")
  }

  // ---- dispatch: story target, retarget and keyed prefix (2.1)

  // get-run-settings like dispatchSettings(), with prefixByMilestone set to map.
  function keyedSettings(map) {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true, prefixByMilestone: map }) + "\n"
  }

  // 2.1 test 3
  function test_open_sets_the_target_label() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    store.openDispatch(cards.t1, cards)
    compare(store.dispatchTargetLabel, 'Subtask "RunStore dispatch"')
    store.openDispatch("board", cards)
    compare(store.dispatchTargetLabel, "Whole board")
    store.openDispatch(null, cards)
    compare(store.dispatchTargetLabel, "No card", "a refused opening is labelled too")
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
  }

  // 2.1 test 5
  function test_story_prefix_reads_the_snapshot_then_the_keyed_map() {
    var store = makeWithProject(rootA); if (!store) return
    reply(loadOf(store).current, keyedSettings({ m9: "m9-map" }), 0)
    var a = { root: tc.rootA, name: "alpha" }
    runsOf(store).runs = [{ id: "r-old", milestone_id: "m1", branch_prefix: "m3-old", started_at: "2026-10-01T00:00:00Z", project: a },
                  { id: "r-live", milestone_id: "m1", branch_prefix: " m3-live ", started_at: "2026-10-06T00:00:00Z", project: a },
                  { id: "r-other", milestone_id: "m2", branch_prefix: "m2-x", started_at: "2026-10-07T00:00:00Z", project: a }]
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the milestone's newest snapshot run wins")
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchForm.prefix, "m3-live", "the same default serves the milestone")

    var keyed = makeWithProject(rootA); if (!keyed) return
    reply(loadOf(keyed).current, keyedSettings({ m1: "m3-map" }), 0)
    keyed.openDispatch(cards.s1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "the keyed map beats the prefix history")
    keyed.openDispatch(cards.t1, cards)
    compare(keyed.dispatchForm.prefix, "m3-map", "a subtask reads its root milestone's entry")
  }

  // 2.1 test 12 (the done story)
  function test_a_done_story_is_refused_and_labelled() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    cards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    compare(store.openDispatch(cards.s1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchTargetLabel, 'Story "Dispatch store" (milestone "M3 Document runs")')
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  // `am run --story s1 --dry-run` data: one level, story s1 with 2 subtasks rooted on main.
  function storyDryRun() {
    return {
      max_concurrent: 4,
      levels: [{ level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
        { id: "t1", title: "RunStore dispatch", status: "todo", branch: "old-t1", base: "main" },
        { id: "t2", title: "Docs", status: "todo", branch: "old-t2", base: "old-t1" }] }] }],
      already_done: [],
      integrate: null
    }
  }

  // Project A with story s1 opened and its default branch `main` read: the
  // first preview is in flight.
  function storyPreviewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string storyPreviewArgs: "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest"

  // 2.1 test 4
  function test_story_preview_argv_and_story_summary() {
    var store = storyPreviewingStore(); if (!store) return
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a story is previewed")
    compare(argv(proc), tc.previewCmd + tc.storyPreviewArgs)
    reply(proc, previewOk(storyDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 subtasks · rooted on main")
    compare(store.dispatchPreview.integrate, "")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 2.1 test 12 (the preview half)
  function test_a_finished_story_preview_is_refused() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [],
      already_done: [{ kind: "story", id: "s1", title: "Dispatch store" }], integrate: null }), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "Nothing left to run")
    compare(store.dispatchErrorType, "Empty")
    compare(store.dispatchPreview, null)
    compare(store.dispatchSuggest, null)
    compare(store.dispatchStart(), false, "Start only works from ready")
    compare(store.dispatchStartRunners.length, 0)

    var milestone = previewingStore(); if (!milestone) return
    reply(milestone.dispatchPreviewRunner.current, previewOk({ max_concurrent: 4, levels: [], already_done: [], integrate: null }), 0)
    compare(milestone.dispatchState, "ready", "a milestone with nothing left keeps its behaviour")
    compare(milestone.dispatchPreview.summary, "0 levels · 0 subtasks")
  }

  // 2.1 test 11 (the preview half)
  function test_a_claimed_story_preview_names_the_other_run() {
    var store = storyPreviewingStore(); if (!store) return
    var message = "story s1 is claimed by run r-other (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchPreview, null)
  }

  property string blockedMessage: "story s1 is blocked by s0 (todo); dispatch milestone m1 instead"

  // Every dispatch field, as one string to compare before and after.
  function dispatchFields(store) {
    return JSON.stringify([store.dispatchState, store.dispatchTarget, store.dispatchTargetLabel, store.dispatchForm,
                           store.dispatchPreview, store.dispatchError, store.dispatchErrorType, store.dispatchErrors,
                           store.dispatchSuggest, store.dispatchRunId, store.dispatchMessage, store.dispatchLog,
                           store.dispatchLogTail, store.dispatchExitCode])
  }

  // retargetToMilestone() returns false, changes no dispatch field and launches no lookup.
  function checkRetargetRefused(store, label) {
    var before = dispatchFields(store)
    var lookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), false, label)
    compare(dispatchFields(store), before, label + ": nothing changed")
    verify(store.dispatchDefaultsRunner.current === lookup, label + ": no lookup")
  }

  // 2.1 test 8
  function test_retarget_from_a_blocked_preview() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, tc.blockedMessage, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStart(), false, "Start stays refused")
    var storyLookup = store.dispatchDefaultsRunner.current
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    var lookup = store.dispatchDefaultsRunner.current
    verify(lookup !== storyLookup, "a fresh --defaults lookup")
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/my proj")
    reply(lookup, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "the milestone is previewed")
  }

  // 2.1 test 10
  function test_retarget_refused_outside_a_blocked_refusal() {
    var cards = dispatchCards()
    var idle = dispatchStore(); if (!idle) return
    checkRetargetRefused(idle, "idle")
    checkDispatchIdle(idle, "idle after the refusal")

    var ready = readyStore(); if (!ready) return
    checkRetargetRefused(ready, "ready")

    var claimed = storyPreviewingStore(); if (!claimed) return
    reply(claimed.dispatchPreviewRunner.current, ctlFail("ClaimedError", "story s1 is claimed by run r-other"), 0)
    checkRetargetRefused(claimed, "ClaimedError")

    var form = dispatchStore(); if (!form) return
    form.openDispatch("board", cards)
    reply(form.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(form.dispatchErrorType, "Form")
    checkRetargetRefused(form, "Form")

    var target = dispatchStore(); if (!target) return
    var doneCards = dispatchCards()
    doneCards.s1 = { id: "s1", title: "Dispatch store", status: "done", parentId: "m1", depth: 1 }
    target.openDispatch(doneCards.s1, doneCards)
    compare(target.dispatchErrorType, "Target")
    checkRetargetRefused(target, "Target")

    var failed = readyStore(); if (!failed) return
    failed.dispatchStart()
    reply(failed.dispatchStartRunners[0].current, ctlFail("AmExited", "am run exited at once (exit 2)"), 0)
    compare(failed.dispatchState, "failed")
    checkRetargetRefused(failed, "failed")

    var orphan = dispatchStore(); if (!orphan) return
    var orphanCards = dispatchCards()
    orphanCards.o1 = { id: "o1", title: "Orphan", status: "todo", parentId: "", depth: 1 }
    orphan.openDispatch(orphanCards.o1, orphanCards)
    reply(orphan.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(orphan.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|o1|--base-branch|main|--branch-prefix|old|--max-concurrent|4|--verify|uv run pytest")
    reply(orphan.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", "story o1 is blocked"), 0)
    compare(orphan.dispatchState, "refused")
    compare(orphan.dispatchErrorType, "StoryBlockedError")
    compare(orphan.dispatchSuggest, null, "no milestone to offer")
    compare(orphan.dispatchTargetLabel, 'Story "Orphan"')
    checkRetargetRefused(orphan, "a blocked story with no milestone")

    var closed = storyPreviewingStore(); if (!closed) return
    reply(closed.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(closed.closeDispatch(), true)
    checkRetargetRefused(closed, "closed after a blocked refusal")
    checkDispatchIdle(closed, "still idle")
  }

  // 2.1 test 13
  function test_an_edit_after_a_blocked_refusal_previews_again() {
    var store = storyPreviewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.setDispatchField("prefix", "x"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchSuggest, null)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    checkRetargetRefused(store, "previewing after the edit")
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|story|s1|--base-branch|main|--branch-prefix|x|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}', "the action comes back")
  }

  // 2.1 Review Focus 4 and 5
  function test_retarget_goes_once_to_the_milestone_recorded_at_the_opening() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    cards.m1 = { id: "m1", title: "M4 Renamed", status: "todo", parentId: "", depth: 0 }
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"', "the milestone recorded at the opening")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchForm.parallelism, 4, "the story's edits are not carried over")
    compare(store.dispatchForm.prefix, "old")
    checkRetargetRefused(store, "the second call, while previewing")
  }

  // Project A with story s1's preview landed: Start is allowed.
  function storyReadyStore() {
    var store = storyPreviewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    return store
  }

  // 2.1 test 6
  function test_a_story_start_saves_the_prefix_under_its_milestone() {
    var store = makeWithProject(rootA); if (!store) return
    reply(loadOf(store).current, keyedSettings({ m9: "x" }), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + tc.storyPreviewArgs)
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" +
            '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4,"prefixByMilestone":{"m1":"old"}}')
    var map = store.runSettings.prefixByMilestone
    compare(Object.keys(map).sort().join(","), "m1,m9", "merged locally")
    compare(map.m9, "x", "the stored entry is kept")
    compare(map.m1, "old")
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
  }

  // 2.1 test 7
  function test_milestone_starts_key_the_prefix_and_subtask_or_board_starts_do_not() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, startOk("r-1", ""), 0)
    compare(saveOf(store).current.command[4], tc.savedJson, "a milestone start keys its own id")
    compare(store.runSettings.prefixByMilestone.m1, "old")

    var plain = '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["old"],"parallelism":4}'
    var cards = dispatchCards()
    var subtask = dispatchStore(); if (!subtask) return
    subtask.openDispatch(cards.t1, cards)
    reply(subtask.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(subtask.dispatchStart(), true)
    var subtaskRunner = subtask.dispatchStartRunners[0]
    reply(subtaskRunner.current, startOk("r-2", ""), 0)
    compare(argv(saveOf(subtask).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a subtask start keys nothing")
    compare(subtask.runSettings.prefixByMilestone, undefined, "nothing keyed locally")

    var board = dispatchStore(); if (!board) return
    board.openDispatch("board", cards)
    reply(board.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    board.setDispatchField("prefix", "old")
    fire(board.dispatchDebounceTimer)
    reply(board.dispatchPreviewRunner.current, previewOk({ board: true, levels: [] }), 0)
    compare(board.dispatchState, "ready")
    compare(board.dispatchStart(), true)
    var boardRunner = board.dispatchStartRunners[0]
    reply(boardRunner.current, startOk("r-3", ""), 0)
    compare(argv(saveOf(board).current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + plain, "a board start keys nothing")
  }

  // 2.1 Review Focus 2
  function test_a_stored_map_that_is_not_an_object_merges_from_nothing() {
    var stored = [[], "x", ["a"], 7, null]
    for (var i = 0; i < stored.length; i++) {
      var store = makeWithProject(rootA); if (!store) return
      reply(loadOf(store).current, keyedSettings(stored[i]), 0)
      var cards = dispatchCards()
      store.openDispatch(cards.s1, cards)
      reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
      compare(store.dispatchState, "started", "stored " + i)
      compare(Object.keys(store.runSettings.prefixByMilestone).join(","), "m1", "stored " + i + ": only the new entry")
      compare(store.runSettings.prefixByMilestone.m1, "old", "stored " + i)
    }
  }

  // 2.1 Review Focus 3
  function test_the_keyed_prefix_is_the_trimmed_one_sent() {
    var store = storyPreviewingStore(); if (!store) return
    store.setDispatchField("prefix", "  m3-spaced ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3-spaced", "sent trimmed")
    compare(runner.savedJson, '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3-spaced","old"],' +
                              '"parallelism":4,"prefixByMilestone":{"m1":"m3-spaced"}}')
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.runSettings.prefixByMilestone.m1, "m3-spaced")
  }

  // A StoryBlockedError start failure, with the log fields start-run.py adds.
  function startBlocked() {
    return JSON.stringify({ ok: false, error: { type: "StoryBlockedError", message: tc.blockedMessage },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: story s1 is blocked" }) + "\n"
  }

  // 2.1 test 9
  function test_retarget_from_a_blocked_start() {
    var store = storyReadyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    var settingsBefore = JSON.stringify(store.runSettings)
    compare(store.dispatchStart(), true)
    var seq = runsOf(store).snapshotRunner.seq
    reply(store.dispatchStartRunners[0].current, startBlocked(), 0)
    compare(store.dispatchState, "refused", "a blocked story is refused, not failed")
    compare(store.dispatchError, tc.blockedMessage)
    compare(store.dispatchErrorType, "StoryBlockedError")
    compare(store.dispatchLog, "")
    compare(store.dispatchLogTail, "")
    compare(store.dispatchExitCode, null)
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    compare(store.dispatchStartRunners.length, 0, "the runner is dropped: no set-run-settings")
    compare(JSON.stringify(store.runSettings), settingsBefore, "nothing saved")
    compare(store.dispatchForm.prefix, "old", "the form stays")
    compare(spy.count, 0)
    compare(runsOf(store).snapshotRunner.seq, seq, "no re-snapshot")
    compare(store.dispatchStart(), false, "Start stays refused")
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(JSON.stringify(store.dispatchTarget.flags), JSON.stringify(["--milestone", "m1"]))
    compare(store.dispatchTargetLabel, 'Milestone "M3 Document runs"')
    compare(store.dispatchSuggest, null)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs)

    var blank = storyReadyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, ctlFail("StoryBlockedError", "  "), 0)
    compare(blank.dispatchState, "refused")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "StoryBlockedError")
    compare(JSON.stringify(blank.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
  }

  // 2.1 test 11 (the start half)
  function test_a_claimed_story_start_fails_with_the_log() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, JSON.stringify({ ok: false,
      error: { type: "ClaimedError", message: "story s1 is claimed by run r-other" },
      log: "/home/u/.local/state/am-run.log", exit_code: 1, log_tail: "claimed" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "story s1 is claimed by run r-other")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "claimed")
    compare(store.dispatchExitCode, 1)
    compare(store.dispatchSuggest, null)
    compare(store.retargetToMilestone(), false)
  }

  // 2.1 Review Focus 1
  function test_a_late_blocked_start_reply_changes_nothing() {
    var store = storyReadyStore(); if (!store) return
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    runsOf(store).project = rootB
    checkDispatchIdle(store, "B after the switch")
    reply(proc, startBlocked(), 0)
    checkDispatchIdle(store, "B after A's blocked reply")
    compare(store.dispatchStartRunners.length, 0, "the runner goes")

    var back = storyReadyStore(); if (!back) return
    back.dispatchStart()
    var backProc = back.dispatchStartRunners[0].current
    runsOf(back).project = rootB
    runsOf(back).project = rootA
    reply(loadOf(back).current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(back.openDispatch(cards.m1, cards), true)
    reply(backProc, startBlocked(), 0)
    compare(back.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(back.dispatchError, "")
    compare(back.dispatchErrorType, "")
    compare(back.dispatchSuggest, null)
    compare(back.dispatchTargetLabel, 'Milestone "M3 Document runs"')
  }

  // ---- dispatch: dispatchRoot (2.1 RunStore dispatch)

  // 2.1 RunStore dispatch test 1
  function test_dispatch_root_starts_empty_and_card_entry_sets_project() {
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchRoot, "", "fresh")
    var cards = dispatchCards()
    compare(fresh.openDispatch(cards.m1, cards), false, "no project")
    compare(fresh.dispatchRoot, "", "a refused card entry sets no root")

    var store = dispatchStore(); if (!store) return
    compare(store.dispatchRoot, "", "opening a project opens no dispatch")
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRoot, tc.rootA, "a card entry dispatches for the open project")
    compare(store.closeDispatch(), true)
    compare(store.dispatchRoot, "", "closed")
    checkDispatchIdle(store, "closed")
    compare(store.openDispatch(cards.m1, cards), true)
    runsOf(store).project = tc.rootB
    compare(store.dispatchRoot, "", "a project switch forgets the root")
    checkDispatchIdle(store, "switched")

    var starting = readyStore(); if (!starting) return
    compare(starting.dispatchStart(), true)
    compare(starting.closeDispatch(), false)
    compare(starting.dispatchRoot, tc.rootA, "a refused close keeps the root")
    compare(starting.openDispatch(cards.t1, cards), false)
    compare(starting.dispatchRoot, tc.rootA, "a refused card entry keeps the root")
  }

  // 2.1 RunStore dispatch test 2
  function test_dispatch_open_for_refuses_without_a_root_or_while_starting() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.dispatchOpenFor(cards.m1, cards), false, "no root")
    checkDispatchIdle(store, "no root")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")

    var starting = readyStore(); if (!starting) return
    starting.dispatchStart()
    compare(starting.dispatchOpenFor(cards.t1, cards), false, "starting")
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchTarget.level, "milestone")
    compare(starting.dispatchRoot, tc.rootA)
  }

  // 2.1 RunStore dispatch: the defaults lookup and a refused target for another root
  function test_dispatch_open_for_launches_for_the_root() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.dispatchRoot = tc.rootB
    compare(store.dispatchOpenFor(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchRoot, tc.rootB, "the opening keeps the root")
    compare(runsOf(store).project, tc.rootA)
    var lookup = store.dispatchDefaultsRunner.current
    verify(lookup, "the default branch is looked up")
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/b")
    compare(lookup.launchGuard, "/home/u/b")
    compare(store.dispatchPreviewRunner.guard, "/home/u/b")

    var refused = dispatchStore(); if (!refused) return
    refused.dispatchRoot = tc.rootB
    compare(refused.dispatchOpenFor(cards.d1, cards), false)
    compare(refused.dispatchState, "refused")
    compare(refused.dispatchErrorType, "Target")
    compare(refused.dispatchRoot, tc.rootB)
    verify(!refused.dispatchDefaultsRunner.current, "a refused target launches nothing")
  }

  // Projects A and B registered (their snapshot in flight), A open with its
  // settings read (dispatchSettings), and the dispatch's root set to B.
  function otherRootStore() {
    var store = make(); if (!store) return null
    runsOf(store).projectRoots = registry([tc.rootA, tc.rootB])
    runsOf(store).project = tc.rootA
    reply(loadOf(store).current, dispatchSettings(), 0)
    store.dispatchRoot = tc.rootB
    return store
  }

  // B's get-run-settings: differs from A's in every value the form reads.
  function bSettings() {
    return JSON.stringify({ verify: ["make test"], parallelism: 2, prefixHistory: ["bpre", "bold"], confirmDispatch: false }) + "\n"
  }

  property string bPreviewArgs: "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test"

  // Opens milestone m1 for the store's dispatchRoot (B) and lands the
  // defaults (main), B's settings (bSettings) and the preview: Start is allowed.
  function readyForB(store) {
    var cards = dispatchCards()
    store.dispatchOpenFor(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(store).current, bSettings(), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
  }

  // 2.1 RunStore dispatch test 3
  function test_dispatch_open_for_other_root_argv() {
    var store = otherRootStore(); if (!store) return
    var loads = controlOf(store).runSettingsRunners.length
    var cards = dispatchCards()
    compare(store.dispatchOpenFor(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    var lookup = store.dispatchDefaultsRunner.current
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/b")
    var read = loadOf(store).current
    verify(read, "B's run settings are read")
    compare(argv(read), tc.viewerCmd + "get-run-settings|/home/u/b")
    compare(read.command.length, 4)
    compare(controlOf(store).runSettingsRunners.length, loads + 1, "A's run settings are not read again")
    compare(Object.keys(store.dispatchRunSettings).length, 0, "{} until the reply")
    compare(store.dispatchForm.verify.length, 0, "the form opens from {} settings")
    compare(store.dispatchForm.parallelism, 4)
    compare(store.dispatchForm.prefix, "m3", "the milestone's stem")
    reply(lookup, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    verify(!store.dispatchPreviewRunner.current, "no preview while B's settings are pending")
    reply(read, bSettings(), 0)
    compare(store.dispatchRunSettings.prefixHistory[0], "bpre")
    compare(store.dispatchRunSettings.confirmDispatch, false, "the object is kept as it was read")
    compare(store.dispatchForm.verify.join(","), "make test")
    compare(store.dispatchForm.parallelism, 2)
    compare(store.dispatchForm.prefix, "bpre")
    compare(store.dispatchForm.base, "main", "base is not touched by the settings reply")
    compare(store.dispatchForm.allowNoVerification, false)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the last reply checks the form")
    compare(argv(proc), tc.previewCmd + tc.bPreviewArgs)
    compare(proc.launchGuard, "/home/u/b")
    compare(store.runSettings.prefixHistory[0], "old", "A's settings are untouched")
    compare(store.runSettings.verify[0], "uv run pytest")

    var settingsFirst = otherRootStore(); if (!settingsFirst) return
    settingsFirst.dispatchOpenFor(cards.m1, cards)
    reply(loadOf(settingsFirst).current, bSettings(), 0)
    verify(!settingsFirst.dispatchPreviewRunner.current, "no preview while the defaults are pending")
    reply(settingsFirst.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(settingsFirst.dispatchPreviewRunner.current), tc.previewCmd + tc.bPreviewArgs, "whichever replies last checks")

    var refused = otherRootStore(); if (!refused) return
    compare(refused.dispatchOpenFor(cards.d1, cards), false)
    verify(!refused.dispatchDefaultsRunner.current, "a refused target: no defaults lookup")
    verify(!loadOf(refused), "a refused target: no settings read")
  }

  // 2.1 RunStore dispatch test 4 + Review Focus 1, 2 and 3
  function test_dispatch_settings_reply_keeps_user_edits_and_unreadable_is_empty() {
    var cards = dispatchCards()
    var edited = otherRootStore(); if (!edited) return
    edited.dispatchOpenFor(cards.m1, cards)
    compare(edited.setDispatchField("prefix", "mine"), true)
    compare(edited.setDispatchField("parallelism", 3), true)
    reply(edited.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    fire(edited.dispatchDebounceTimer)
    verify(!edited.dispatchPreviewRunner.current, "the debounced check waits for B's settings")
    reply(loadOf(edited).current, bSettings(), 0)
    compare(edited.dispatchForm.prefix, "mine", "the user's prefix is kept")
    compare(edited.dispatchForm.parallelism, 3, "the user's parallelism is kept")
    compare(edited.dispatchForm.verify.join(","), "make test", "verify takes B's")
    compare(argv(edited.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|mine|--max-concurrent|3|--verify|make test")

    var replies = ["Traceback: boom\n", "[1, 2]\n", ""]
    for (var i = 0; i < replies.length; i++) {
      var bad = otherRootStore(); if (!bad) return
      bad.dispatchOpenFor(cards.m1, cards)
      reply(bad.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      reply(loadOf(bad).current, replies[i], 1)
      compare(Object.keys(bad.dispatchRunSettings).length, 0, "reply " + i + ": unreadable is {}")
      compare(bad.dispatchForm.prefix, "m3", "reply " + i + ": the {} defaults stay")
      compare(bad.dispatchForm.parallelism, 4, "reply " + i)
      compare(bad.dispatchForm.verify.length, 0, "reply " + i)
      compare(bad.dispatchState, "refused", "reply " + i + ": the check ran")
      compare(bad.dispatchErrors[0].field, "verify", "reply " + i)
    }

    var late = otherRootStore(); if (!late) return
    late.dispatchOpenFor(cards.m1, cards)
    var lateRead = loadOf(late).current
    compare(late.closeDispatch(), true)
    reply(lateRead, bSettings(), 0)
    checkDispatchIdle(late, "a settings reply after the close")
    compare(Object.keys(late.dispatchRunSettings).length, 0, "nothing kept after the close")

    var reopened = otherRootStore(); if (!reopened) return
    reopened.dispatchOpenFor(cards.m1, cards)
    var bRead = loadOf(reopened).current
    compare(reopened.openDispatch(cards.m1, cards), true)
    compare(reopened.dispatchRoot, tc.rootA)
    reply(bRead, bSettings(), 0)
    compare(Object.keys(reopened.dispatchRunSettings).length, 0, "B's late reply is dropped")
    compare(reopened.dispatchForm.prefix, "old", "A's form stays")
    compare(reopened.dispatchForm.verify.join(","), "uv run pytest")
    compare(reopened.dispatchForm.parallelism, 4)
  }

  // 2.1 RunStore dispatch test 5
  function test_dispatch_prefix_default_reads_only_the_roots_runs() {
    var store = otherRootStore(); if (!store) return
    var cards = dispatchCards()
    var a = { root: tc.rootA, name: "alpha" }
    var b = { root: tc.rootB, name: "beta" }
    runsOf(store).runs = [{ id: "r-a", milestone_id: "m1", branch_prefix: "a-pre", started_at: "2026-10-07T00:00:00Z", project: a },
                  { id: "r-b", milestone_id: "m1", branch_prefix: "b-pre", started_at: "2026-10-06T00:00:00Z", project: b }]
    store.dispatchOpenFor(cards.s1, cards)
    compare(store.dispatchForm.prefix, "b-pre", "A's newer run of m1 does not supply B's prefix")
    reply(loadOf(store).current, bSettings(), 0)
    compare(store.dispatchForm.prefix, "b-pre", "B's run still beats B's history")

    compare(store.closeDispatch(), true)
    runsOf(store).runs = [{ id: "r-a", milestone_id: "m1", branch_prefix: "a-pre", started_at: "2026-10-06T00:00:00Z", project: a },
                  { id: "r-b", milestone_id: "m1", branch_prefix: "b-pre", started_at: "2026-10-07T00:00:00Z", project: b }]
    compare(store.openDispatch(cards.s1, cards), true)
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchForm.prefix, "a-pre", "a card entry reads only the open project's runs")
  }

  // 2.1 RunStore dispatch test 9
  function test_dispatch_retarget_keeps_the_root() {
    var store = otherRootStore(); if (!store) return
    var cards = dispatchCards()
    store.dispatchOpenFor(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(store).current, bSettings(), 0)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/b|story|s1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test")
    reply(store.dispatchPreviewRunner.current, ctlFail("StoryBlockedError", tc.blockedMessage), 0)
    compare(store.dispatchState, "refused")
    compare(JSON.stringify(store.dispatchSuggest), '{"id":"m1","title":"M3 Document runs"}')
    verify(!loadOf(store), "the story's read replied")
    compare(store.retargetToMilestone(), true)
    compare(store.dispatchRoot, tc.rootB, "the retarget keeps the root")
    compare(store.dispatchTarget.level, "milestone")
    compare(argv(store.dispatchDefaultsRunner.current), tc.previewCmd + "--defaults|/home/u/b")
    verify(loadOf(store), "B's settings are read afresh")
    compare(argv(loadOf(store).current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(store).current, bSettings(), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.bPreviewArgs, "B's milestone is previewed")
  }

  // 2.1 RunStore dispatch test 10 + Review Focus 4
  function test_dispatch_card_entry_launches_no_settings_read() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    verify(!loadOf(store), "the open project's runSettings are used")
    compare(Object.keys(store.dispatchRunSettings).length, 0)
    compare(store.dispatchForm.prefix, "old")
    compare(store.dispatchForm.verify.join(","), "uv run pytest")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "previewed on the defaults reply")

    var both = otherRootStore(); if (!both) return
    compare(both.openDispatch(cards.m1, cards), true)
    compare(both.dispatchRoot, tc.rootA, "the card entry replaces a root set before")
    verify(!loadOf(both), "no settings read for the open project")

    var same = dispatchStore(); if (!same) return
    same.dispatchRoot = tc.rootA
    compare(same.dispatchOpenFor(cards.m1, cards), true)
    verify(!loadOf(same), "dispatchOpenFor on the open project reads no settings")
    compare(same.dispatchForm.verify.join(","), "uv run pytest")
    reply(same.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(same.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs)
  }

  // otherRootStore() with A's and B's first snapshot landed (none in
  // flight) and milestone m1 ready for B (readyForB).
  function otherReadyStore() {
    var store = otherRootStore(); if (!store) return null
    reply(runsOf(store).snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    readyForB(store)
    return store
  }

  property string bSavedJson: '{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["bpre","bold"],"parallelism":2,"prefixByMilestone":{"m1":"bpre"}}'

  // 2.1 RunStore dispatch test 6 + Review Focus 5
  function test_dispatch_start_for_other_root_argv_save_and_refresh() {
    var store = otherReadyStore(); if (!store) return
    compare(store.dispatchState, "ready")
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    var aBefore = JSON.stringify(store.runSettings)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/b")
    compare(argv(runner.current), tc.startCmd + tc.bPreviewArgs)
    compare(runner.savedJson, tc.bSavedJson, "B's history follows the prefix sent")
    var seq = runsOf(store).snapshotRunner.seq
    reply(runner.current, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-b")
    compare(runsOf(store).snapshotRunner.seq, seq + 1, "one snapshot is asked for")
    compare(argv(runsOf(store).snapshotRunner.current), tc.snapCmd + "|" + tc.rootB, "of B only")
    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/b|" + tc.bSavedJson)
    compare(store.dispatchRunSettings.prefixHistory.join(","), "bpre,bold")
    compare(store.dispatchRunSettings.prefixByMilestone.m1, "bpre")
    compare(store.dispatchRunSettings.confirmDispatch, false, "B's other keys are kept")
    compare(JSON.stringify(store.runSettings), aBefore, "A's settings are untouched")
    reply(saveOf(store).current, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0)
    compare(controlOf(store).flashText, "")

    compare(store.closeDispatch(), true)
    compare(Object.keys(store.dispatchRunSettings).length, 0, "the merge does not outlive the close")
    store.dispatchRoot = tc.rootB
    var cards = dispatchCards()
    compare(store.dispatchOpenFor(cards.m1, cards), true)
    compare(argv(loadOf(store).current), tc.viewerCmd + "get-run-settings|/home/u/b", "B is read afresh")

    var busy = otherReadyStore(); if (!busy) return
    runsOf(busy).refresh()
    verify(runsOf(busy).snapshotRunner.busy, "a snapshot of every root is in flight")
    busy.dispatchStart()
    reply(busy.dispatchStartRunners[0].current, startOk("r-b", ""), 0)
    compare(busy.dispatchState, "started")
    compare(runsOf(busy).pendingSnapshot.join("|"), tc.rootB, "B joins the pending request")

    var lone = dispatchStore(); if (!lone) return
    reply(runsOf(lone).snapshotRunner.current, okReply([]), 0)
    lone.dispatchRoot = tc.rootB
    readyForB(lone)
    compare(lone.dispatchState, "ready")
    lone.dispatchStart()
    var loneSeq = runsOf(lone).snapshotRunner.seq
    reply(lone.dispatchStartRunners[0].current, startOk("r-b", ""), 0)
    compare(lone.dispatchState, "started")
    compare(runsOf(lone).snapshotRunner.seq, loneSeq, "B is not registered: no snapshot")
  }

  // 2.1 RunStore dispatch test 7
  function test_dispatch_story_start_for_other_root_saves_prefix_by_milestone_for_it() {
    var store = otherRootStore(); if (!store) return
    reply(runsOf(store).snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    var cards = dispatchCards()
    store.dispatchOpenFor(cards.s1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(store).current, JSON.stringify({ verify: ["make test"], parallelism: 2, prefixHistory: ["bpre"],
                                                                 prefixByMilestone: { m9: "b9" } }) + "\n", 0)
    reply(store.dispatchPreviewRunner.current, previewOk(storyDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + "/home/u/b|story|s1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test")
    reply(runner.current, startOk("r-s", ""), 0)
    compare(store.dispatchState, "started")
    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/b|" +
            '{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["bpre"],"parallelism":2,"prefixByMilestone":{"m1":"bpre"}}')
    var map = store.dispatchRunSettings.prefixByMilestone
    compare(Object.keys(map).sort().join(","), "m1,m9", "merged into B's settings")
    compare(map.m9, "b9", "B's stored entry is kept")
    compare(map.m1, "bpre")
    compare(store.runSettings.prefixByMilestone, undefined, "nothing keyed into A's settings")
  }

  // 2.1 RunStore dispatch test 8
  function test_dispatch_start_in_flight_completes_for_its_root_after_a_switch() {
    var store = otherReadyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    var proc = runner.current
    runsOf(store).project = tc.rootB
    compare(store.dispatchRoot, "", "the switch forgets the root")
    checkDispatchIdle(store, "after the switch")
    compare(proc.running, true, "the start is not stopped")
    var seq = runsOf(store).snapshotRunner.seq
    reply(proc, startOk("r-b", ""), 0)
    checkDispatchIdle(store, "after B's start landed")
    compare(spy.count, 0, "no signal")
    compare(runsOf(store).snapshotRunner.seq, seq, "no snapshot")
    compare(Object.keys(store.dispatchRunSettings).length, 0, "nothing merged into dispatchRunSettings")
    compare(store.runSettings.prefixHistory.join(","), "bpre,bold", "run control keeps the values it writes for B, now open")
    compare(argv(saveOf(store).current), tc.viewerCmd + "set-run-settings|/home/u/b|" + tc.bSavedJson, "still written for B")
    reply(saveOf(store).current, "garbage\n", 1)
    compare(controlOf(store).flashText, "", "a save failure that is not here does not flash")
    compare(store.dispatchStartRunners.length, 0)
  }

  // ---- dispatch: project and target steps (2.2)

  property string probeCmd: "python3|/plugin/core/backend/boards/board-tree.py|--probe"

  // board-tree.py --probe's reply line: {"ok": true, "projects": entries}.
  function probeReply(entries) {
    return JSON.stringify({ ok: true, projects: entries }) + "\n"
  }

  // The project step's rows as "root:name:open:on|off:reason", " / "-joined.
  function rowsText(rows) {
    return rows.map(function(r) {
      return r.root + ":" + r.name + ":" + (r.open ? "open" : "") + ":" + (r.enabled ? "on" : "off") + ":" + r.reason
    }).join(" / ")
  }

  // Projects A and B registered, A open with its settings read (dispatchSettings).
  function runsStore() {
    var store = make(); if (!store) return null
    runsOf(store).projectRoots = registry([tc.rootA, tc.rootB])
    runsOf(store).project = tc.rootA
    reply(loadOf(store).current, dispatchSettings(), 0)
    return store
  }

  // 2.2 test 1
  function test_dispatch_step_empty_for_idle_and_card_entry() {
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStep, "", "fresh")
    compare(fresh.dispatchProjectRows.length, 0, "fresh: no rows")
    compare(fresh.dispatchProjectProbe, null, "fresh: no probe")

    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchStep, "", "a card entry has no step")
    compare(store.dispatchProjectRows.length, 0, "a card entry has no rows")
    verify(!store.dispatchProjectRunner.current, "a card entry probes nothing")
  }
  // 2.2 test 2
  function test_dispatch_open_from_runs_argv_and_rows() {
    var store = runsStore(); if (!store) return
    compare(store.dispatchOpenFromRuns(), true)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "", "no root until a pick")
    compare(store.dispatchState, "idle")
    compare(store.dispatchTarget, null, "S3's fields keep their none values")
    compare(store.dispatchForm, null)
    var probe = store.dispatchProjectRunner.current
    verify(probe, "the probe is launched")
    compare(argv(probe), tc.probeCmd + "|/home/u/my proj|/home/u/b")
    compare(probe.command.length, 5)
    compare(store.dispatchProjectProbe, null, "null before the reply")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:",
            "before the reply every row is enabled, the open project first")
    reply(probe, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectProbe.ok, true)
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:no .brd marker")

    var none = makeWithRoots([tc.rootB, tc.rootA]); if (!none) return
    compare(none.dispatchOpenFromRuns(), true, "no project needs to be open")
    compare(argv(none.dispatchProjectRunner.current), tc.probeCmd + "|/home/u/b|/home/u/my proj", "registry order")
    compare(rowsText(none.dispatchProjectRows), "/home/u/my proj:alpha::on: / /home/u/b:beta::on:", "no row open, ordered by name")
  }
  // 2.2 test 3
  function test_dispatch_open_from_runs_with_no_root_and_while_starting() {
    var empty = make(); if (!empty) return
    compare(empty.dispatchOpenFromRuns(), true)
    compare(empty.dispatchStep, "project")
    compare(empty.dispatchProjectRows.length, 0, "No projects registered")
    verify(!empty.dispatchProjectRunner.current, "nothing to probe")

    var unusable = make(); if (!unusable) return
    runsOf(unusable).projectRoots = [{ root: "-x", name: "x" }, { root: "", name: "empty" }, null, { name: "no root" }]
    compare(unusable.dispatchOpenFromRuns(), true)
    compare(unusable.dispatchProjectRows.length, 0, "an unusable entry gives no row")
    verify(!unusable.dispatchProjectRunner.current, "an unusable entry is not probed")

    var emptied = runsStore(); if (!emptied) return
    emptied.dispatchOpenFromRuns()
    var old = emptied.dispatchProjectRunner.current
    runsOf(emptied).projectRoots = []
    compare(emptied.dispatchOpenFromRuns(), true)
    compare(emptied.dispatchProjectRows.length, 0)
    reply(old, probeReply([{ root: tc.rootA, ok: true }]), 0)
    compare(emptied.dispatchProjectProbe, null, "a reopening with no root drops the older probe")

    var starting = readyStore(); if (!starting) return
    compare(starting.dispatchStart(), true)
    compare(starting.dispatchOpenFromRuns(), false)
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchStep, "")
    compare(starting.dispatchRoot, tc.rootA)
    verify(!starting.dispatchProjectRunner.current, "nothing launched")
  }
  // 2.2 test 4
  function test_dispatch_project_probe_unreadable_and_latest_wins() {
    var store = runsStore(); if (!store) return
    var bad = probeReply([{ root: tc.rootB, ok: false, reason: "not a directory" }])
    var unreadable = ["Traceback: boom\n", "", "[1, 2]\n",
                      JSON.stringify({ ok: false, error: { type: "Usage", message: "no roots" } }) + "\n",
                      JSON.stringify({ ok: true, projects: "nope" }) + "\n"]
    for (var i = 0; i < unreadable.length; i++) {
      store.dispatchOpenFromRuns()
      reply(store.dispatchProjectRunner.current, bad, 0)
      verify(store.dispatchProjectProbe !== null, "case " + i + ": a good reply first")
      store.dispatchProjectReplied(unreadable[i])
      compare(store.dispatchProjectProbe, null, "case " + i + ": unreadable is null")
      compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:",
              "case " + i + ": every row enabled")
    }

    store.dispatchOpenFromRuns()
    var first = store.dispatchProjectRunner.current
    compare(store.dispatchOpenFromRuns(), true, "a second call starts the step over")
    var second = store.dispatchProjectRunner.current
    verify(first !== second, "a new probe")
    reply(first, bad, 0)
    compare(store.dispatchProjectProbe, null, "the older reply is dropped")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:")
    reply(second, bad, 0)
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:not a directory",
            "the newer reply applies")
  }

  // 2.2 test 5
  function test_dispatch_project_pick() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current,
          probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectPick(tc.rootB), false, "a disabled row")
    compare(store.dispatchProjectPick("/nope"), false, "an unknown root")
    compare(store.dispatchProjectPick(""), false, "no root")
    compare(store.dispatchStep, "project", "a refused pick keeps the step")
    compare(store.dispatchRoot, "", "a refused pick sets no root")
    compare(store.dispatchProjectPick(tc.rootA), true)
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchState, "idle")
    verify(!store.dispatchDefaultsRunner.current, "a pick looks up no defaults")
    verify(!loadOf(store), "a pick reads no settings")
    verify(!store.dispatchPreviewRunner.current, "a pick previews nothing")
    compare(store.dispatchProjectPick(tc.rootA), false, "no pick at the target step")
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootA)

    var idle = runsStore(); if (!idle) return
    compare(idle.dispatchProjectPick(tc.rootA), false, "no pick without a step")
    compare(idle.dispatchStep, "")
    compare(idle.dispatchRoot, "")

    var early = runsStore(); if (!early) return
    early.dispatchOpenFromRuns()
    compare(early.dispatchProjectPick(tc.rootB), true, "a row with no probe entry is enabled")
    compare(early.dispatchRoot, tc.rootB)
  }
  // 2.2 test 6
  function test_dispatch_back_from_target() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]), 0)
    var probe = store.dispatchProjectProbe
    var seq = store.dispatchProjectRunner.seq
    compare(store.dispatchProjectPick(tc.rootB), true)
    compare(store.dispatchBack(), true)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "")
    verify(store.dispatchProjectProbe === probe, "the probe is kept")
    compare(store.dispatchProjectRunner.seq, seq, "nothing relaunched")
    compare(store.dispatchProjectRows.length, 2)
    compare(store.dispatchBack(), false, "step 1 has no Back")
    compare(store.dispatchStep, "project")

    var idle = runsStore(); if (!idle) return
    compare(idle.dispatchBack(), false, "no Back without a step")
    compare(idle.dispatchStep, "")

    var form = runsStore(); if (!form) return
    form.dispatchOpenFromRuns()
    form.dispatchProjectPick(tc.rootB)
    form.dispatchStep = "form"
    compare(form.dispatchBack(), true, "Back from the form returns to the target step")
    compare(form.dispatchStep, "target")
    compare(form.dispatchRoot, tc.rootB)
  }
  // 2.2 test 10
  function test_dispatch_rows_follow_project_roots() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    var seq = store.dispatchProjectRunner.seq
    reply(store.dispatchProjectRunner.current,
          probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: false, reason: "not a directory" }]), 0)
    runsOf(store).projectRoots = [tc.rootEntry(tc.rootA), { root: tc.rootB, name: "zeta" }]
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:zeta::off:not a directory", "renamed")
    runsOf(store).projectRoots = [tc.rootEntry(tc.rootA), { root: tc.rootB, name: "zeta" }, tc.rootEntry(tc.rootC)]
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/c:proj::on: / /home/u/b:zeta::off:not a directory",
            "C added, enabled with no probe entry")
    runsOf(store).projectRoots = [tc.rootEntry(tc.rootC), { root: tc.rootB, name: "zeta" }, tc.rootEntry(tc.rootA)]
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/c:proj::on: / /home/u/b:zeta::off:not a directory",
            "reordered: still the open row first, then by name")
    compare(store.dispatchProjectRunner.seq, seq, "no new probe")

    runsOf(store).projectRoots = [{ root: "-x", name: "x" }, tc.rootEntry(tc.rootA), { root: "/home/u/b/", name: "beta" }]
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:not a directory",
            "no row for -x; the trailing / is trimmed")
    store.dispatchOpenFromRuns()
    compare(argv(store.dispatchProjectRunner.current), tc.probeCmd + "|/home/u/my proj|/home/u/b/",
            "-x is not probed; the root is probed as registered")
    compare(store.dispatchProjectPick("/home/u/b/"), false, "a pick names the row's root")
    compare(store.dispatchProjectPick("/home/u/b"), true)
    compare(store.dispatchRoot, "/home/u/b")
  }

  // 2.2 test 7
  function test_dispatch_close_and_card_entry_clear_the_steps() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    var late = store.dispatchProjectRunner.current
    compare(store.closeDispatch(), true)
    compare(store.dispatchStep, "")
    compare(store.dispatchProjectProbe, null)
    compare(store.dispatchProjectRows.length, 0)
    checkDispatchIdle(store, "closed")
    reply(late, probeReply([{ root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectProbe, null, "a reply after the close is dropped")
    compare(store.dispatchStep, "")
    store.dispatchProjectReplied(probeReply([{ root: tc.rootB, ok: true }]))
    compare(store.dispatchProjectProbe, null, "a reply is applied only while a step is open")

    var cards = dispatchCards()
    store.dispatchOpenFromRuns()
    var lateCard = store.dispatchProjectRunner.current
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchStep, "", "a card entry clears the steps")
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchProjectRows.length, 0)
    reply(lateCard, probeReply([{ root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    compare(store.dispatchProjectProbe, null, "a reply after a card entry is dropped")

    var panel = make(); if (!panel) return
    runsOf(panel).active = true
    runsOf(panel).projectRoots = registry([tc.rootA, tc.rootB])
    panel.dispatchOpenFromRuns()
    compare(panel.dispatchProjectPick(tc.rootB), true)
    runsOf(panel).active = false
    compare(panel.dispatchStep, "", "closing the panel clears the steps")
    compare(panel.dispatchRoot, "")

    var starting = readyStore(); if (!starting) return
    compare(starting.dispatchStart(), true)
    starting.dispatchStep = "form"
    compare(starting.closeDispatch(), false)
    compare(starting.dispatchStep, "form", "a refused close keeps the step")
    compare(starting.openDispatch(cards.m1, cards), false)
    compare(starting.dispatchStep, "form", "a refused card entry keeps the step")
  }

  // 2.2 test 8
  function test_dispatch_registry_change_while_open_drops_the_row() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    var seq = store.dispatchProjectRunner.seq
    runsOf(store).projectRoots = registry([tc.rootA])
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on:", "B's row is gone")
    compare(store.dispatchProjectRunner.seq, seq, "no new probe")
    compare(store.dispatchStep, "project")

    runsOf(store).projectRoots = registry([tc.rootA, tc.rootB])
    store.dispatchOpenFromRuns()
    compare(store.dispatchProjectPick(tc.rootB), true)
    runsOf(store).projectRoots = registry([tc.rootA])
    compare(store.dispatchStep, "project", "the picked root left: back to step 1")
    compare(store.dispatchRoot, "")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on:")

    compare(store.dispatchProjectPick(tc.rootA), true)
    runsOf(store).projectRoots = registry([tc.rootB, tc.rootA])
    compare(store.dispatchStep, "target", "a reorder keeps the step")
    compare(store.dispatchRoot, tc.rootA)
    runsOf(store).projectRoots = [{ root: tc.rootA + "/", name: "alpha" }, tc.rootEntry(tc.rootB)]
    compare(store.dispatchStep, "target", "a trailing / is the same root")
    compare(store.dispatchRoot, tc.rootA)

    store.dispatchStep = "form"
    runsOf(store).projectRoots = registry([tc.rootB])
    compare(store.dispatchStep, "project", "the picked root left the form: back to step 1")
    compare(store.dispatchRoot, "")
  }

  // 2.2 test 9
  function test_dispatch_open_project_switch_leaves_a_runs_dialog_alone() {
    var store = make(); if (!store) return
    runsOf(store).projectRoots = registry([tc.rootA, tc.rootB, tc.rootC])
    runsOf(store).project = tc.rootA
    reply(loadOf(store).current, dispatchSettings(), 0)
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current,
          probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }, { root: tc.rootC, ok: true }]), 0)
    var probe = store.dispatchProjectProbe
    compare(store.dispatchProjectPick(tc.rootB), true)
    runsOf(store).project = tc.rootC
    compare(store.dispatchStep, "target", "the step is kept")
    compare(store.dispatchRoot, tc.rootB, "the root is kept")
    verify(store.dispatchProjectProbe === probe, "the probe is kept")
    compare(store.dispatchState, "idle")
    compare(Object.keys(store.runSettings).length, 0, "the run settings are the new project's")
    compare(argv(loadOf(store).current), tc.viewerCmd + "get-run-settings|/home/u/c")
    compare(store.dispatchBack(), true)
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/c:proj:open:on: / /home/u/my proj:alpha::on: / /home/u/b:beta::on:", "the open mark follows")
    runsOf(store).project = ""
    compare(store.dispatchStep, "project", "closing the project keeps the step")
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha::on: / /home/u/b:beta::on: / /home/u/c:proj::on:", "no row open")

    var inFlight = runsStore(); if (!inFlight) return
    inFlight.dispatchOpenFromRuns()
    var proc = inFlight.dispatchProjectRunner.current
    runsOf(inFlight).project = tc.rootB
    reply(proc, probeReply([{ root: tc.rootA, ok: false, reason: "no .brd marker" }]), 0)
    compare(rowsText(inFlight.dispatchProjectRows),
            "/home/u/b:beta:open:on: / /home/u/my proj:alpha::off:no .brd marker", "a probe across a switch still applies")
  }

  // ---- dispatch: the target step (2.3)

  // board-tree.py ROOT's argv up to the root.
  property string treeCmd: "python3|/plugin/core/backend/boards/board-tree.py"

  // board-tree.py ROOT's reply line: {"ok": true, "data": data}.
  function treeReply(data) {
    return JSON.stringify({ ok: true, data: data }) + "\n"
  }

  // board-tree.py ROOT's failure line: {"ok": false, "error": {type, message}}.
  function treeFail(message) {
    return JSON.stringify({ ok: false, error: { type: "BrdFailed", message: message } }) + "\n"
  }

  // A fresh brd tree as brd prints it (children, no depth or parentId):
  // milestone m1 holding story s1, which holds subtask t1 (todo) and
  // subtask t2 (done); then the done milestone d1.
  function treeData() {
    return [
      { id: "m1", title: "M3 Document runs", status: "todo", children: [
        { id: "s1", title: "Dispatch store", status: "todo", children: [
          { id: "t1", title: "RunStore dispatch", status: "todo", children: [] },
          { id: "t2", title: "Docs", status: "done", children: [] }] }] },
      { id: "d1", title: "M2 Monitor runs", status: "done", children: [] }
    ]
  }

  // The target rows' keys, ","-joined.
  function targetKeys(rows) {
    return rows.map(function(r) { return r.key }).join(",")
  }

  // runsStore() opened from Runs, A and B probed ok, and `root` picked: its
  // tree read is in flight.
  function pickedStore(root) {
    var store = runsStore(); if (!store) return null
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]), 0)
    store.dispatchProjectPick(root)
    return store
  }

  // pickedStore(root) with treeData() read: the target rows are up.
  function targetStore(root) {
    var store = pickedStore(root); if (!store) return null
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    return store
  }

  // The target data at its cleared values.
  function checkTargetCleared(store, label) {
    compare(store.dispatchTargetRows.length, 0, label + ": target rows")
    compare(store.dispatchTargetCardMap, null, label + ": target card map")
    compare(store.dispatchTargetLoading, false, label + ": target loading")
    compare(store.dispatchTargetKey, "", label + ": target key")
  }

  // 2.3 test 1
  function test_dispatch_target_pick_launches_the_tree_read() {
    var store = runsStore(); if (!store) return
    store.dispatchOpenFromRuns()
    reply(store.dispatchProjectRunner.current, probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]), 0)
    verify(!store.dispatchTargetRunner.current, "no tree read before a pick")
    compare(store.dispatchTargetLoading, false)
    compare(store.dispatchProjectPick(tc.rootB), true)
    var proc = store.dispatchTargetRunner.current
    verify(proc, "the pick reads B's tree")
    compare(argv(proc), tc.treeCmd + "|/home/u/b")
    compare(proc.command.length, 3, "no --probe")
    compare(proc.launchGuard, tc.rootB, "guarded by the picked root")
    compare(store.dispatchTargetLoading, true)
    compare(store.dispatchTargetRows.length, 0, "no rows until the reply")
    compare(store.dispatchTargetCardMap, null)
    compare(store.dispatchTargetKey, "")
    compare(store.dispatchState, "idle")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
    verify(!loadOf(store), "no settings read")
    verify(!store.dispatchPreviewRunner.current, "no preview")
    var seq = store.dispatchTargetRunner.seq
    compare(store.dispatchProjectPick(tc.rootA), false, "no pick at the target step")
    compare(store.dispatchTargetRunner.seq, seq, "a refused pick launches nothing")
    verify(store.dispatchTargetRunner.current === proc)
    compare(store.dispatchRoot, tc.rootB)

    var off = runsStore(); if (!off) return
    off.dispatchOpenFromRuns()
    reply(off.dispatchProjectRunner.current, probeReply([{ root: tc.rootB, ok: false, reason: "no .brd marker" }]), 0)
    var offSeq = off.dispatchTargetRunner.seq
    compare(off.dispatchProjectPick(tc.rootB), false, "a disabled row")
    compare(off.dispatchTargetRunner.seq, offSeq, "a disabled row launches nothing")
    verify(!off.dispatchTargetRunner.current)
    compare(off.dispatchTargetLoading, false)
  }

  // 2.3 test 2
  function test_dispatch_target_rows_from_the_tree() {
    var store = pickedStore(tc.rootB); if (!store) return
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    compare(store.dispatchTargetLoading, false)
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchState, "idle")
    var rows = store.dispatchTargetRows
    compare(targetKeys(rows), "board,card:m1,card:s1,card:t1", "the board row, then the offered cards in tree order")
    compare(rows[0].card, "board")
    compare(rows[0].level, "board")
    compare(rows[0].label, "Whole board")
    compare(rows[1].level, "milestone")
    compare(rows[1].label, "Milestone \"M3 Document runs\"")
    compare(rows[3].level, "subtask")
    compare(rows[3].depth, 2)
    var map = store.dispatchTargetCardMap
    compare(map.t1.parentId, "s1", "indexed with Board.indexTree")
    compare(map.t1.depth, 2)
    compare(Object.keys(map).sort().join(","), "d1,m1,s1,t1,t2", "the map holds every card")
    verify(rows[3].card === map.t1, "the row's card is the map's card")

    var empty = pickedStore(tc.rootB); if (!empty) return
    reply(empty.dispatchTargetRunner.current, treeReply([]), 0)
    compare(targetKeys(empty.dispatchTargetRows), "board", "a tree with no offered card gives the board row only")
    compare(Object.keys(empty.dispatchTargetCardMap).length, 0)
    compare(empty.dispatchStep, "target")
  }

  // 2.3 test 8
  function test_dispatch_target_read_survives_a_project_switch() {
    var store = pickedStore(tc.rootB); if (!store) return
    var proc = store.dispatchTargetRunner.current
    runsOf(store).project = tc.rootC
    compare(store.dispatchStep, "target", "the step is kept")
    compare(store.dispatchRoot, tc.rootB, "the root is kept")
    compare(store.dispatchTargetLoading, true, "the read is still in flight")
    verify(store.dispatchTargetRunner.current === proc, "and not relaunched")
    reply(proc, treeReply(treeData()), 0)
    compare(store.dispatchTargetLoading, false)
    compare(targetKeys(store.dispatchTargetRows), "board,card:m1,card:s1,card:t1", "the reply applies")
  }

  // 2.3 test 5
  function test_dispatch_target_failure_disables_the_row() {
    var store = pickedStore(tc.rootB); if (!store) return
    var probeSeq = store.dispatchProjectRunner.seq
    reply(store.dispatchTargetRunner.current, treeFail(" ProjectNotFoundError: no project "), 0)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "")
    compare(store.dispatchState, "idle")
    checkTargetCleared(store, "failed")
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:ProjectNotFoundError: no project",
            "B is off with the helper's message, A unchanged")
    compare(store.dispatchProjectFailures[tc.rootB], "ProjectNotFoundError: no project")
    compare(store.dispatchProjectRunner.seq, probeSeq, "the probe is not relaunched")
    var seq = store.dispatchTargetRunner.seq
    compare(store.dispatchProjectPick(tc.rootB), false, "a failed row ignores a pick")
    compare(store.dispatchTargetRunner.seq, seq, "nothing launched")
    compare(store.dispatchStep, "project")
    store.dispatchProjectReplied(probeReply([{ root: tc.rootA, ok: true }, { root: tc.rootB, ok: true }]))
    compare(rowsText(store.dispatchProjectRows),
            "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:ProjectNotFoundError: no project",
            "a later probe saying B is ok does not lift the failure")

    var unreadable = ["Traceback: boom\n", JSON.stringify({ ok: true }) + "\n", treeReply([null]), treeFail("   ")]
    for (var i = 0; i < unreadable.length; i++) {
      var bad = pickedStore(tc.rootB); if (!bad) return
      reply(bad.dispatchTargetRunner.current, unreadable[i], i === 0 ? 1 : 0)
      compare(bad.dispatchStep, "project", "case " + i + ": back to step 1")
      compare(bad.dispatchRoot, "", "case " + i + ": no root")
      checkTargetCleared(bad, "case " + i)
      compare(rowsText(bad.dispatchProjectRows),
              "/home/u/my proj:alpha:open:on: / /home/u/b:beta::off:The board could not be read", "case " + i)
    }

    compare(store.dispatchOpenFromRuns(), true)
    compare(Object.keys(store.dispatchProjectFailures).length, 0, "a reopening forgets the failures")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on: / /home/u/b:beta::on:", "B is judged afresh")
    compare(store.dispatchProjectPick(tc.rootB), true)

    var closed = pickedStore(tc.rootB); if (!closed) return
    reply(closed.dispatchTargetRunner.current, treeFail("gone"), 0)
    compare(closed.closeDispatch(), true)
    compare(Object.keys(closed.dispatchProjectFailures).length, 0, "a close forgets the failures")
  }

  // 2.3 test 6
  function test_dispatch_back_from_target_cancels_the_read() {
    var store = pickedStore(tc.rootB); if (!store) return
    var probe = store.dispatchProjectProbe
    var probeSeq = store.dispatchProjectRunner.seq
    var late = store.dispatchTargetRunner.current
    compare(store.dispatchBack(), true)
    compare(store.dispatchStep, "project")
    compare(store.dispatchRoot, "")
    compare(store.dispatchTargetLoading, false, "Back cancels the read")
    verify(store.dispatchProjectProbe === probe, "the probe is kept")
    compare(store.dispatchProjectRunner.seq, probeSeq, "the probe is not relaunched")
    compare(store.dispatchProjectRows.length, 2)
    reply(late, treeReply(treeData()), 0)
    compare(store.dispatchStep, "project", "the late reply changes nothing")
    checkTargetCleared(store, "late reply")
    compare(Object.keys(store.dispatchProjectFailures).length, 0, "and marks nothing")
    var seq = store.dispatchTargetRunner.seq
    compare(store.dispatchProjectPick(tc.rootB), true)
    verify(store.dispatchTargetRunner.seq > seq, "a new read")
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    compare(targetKeys(store.dispatchTargetRows), "board,card:m1,card:s1,card:t1", "its reply applies")
    compare(store.dispatchBack(), true)
    checkTargetCleared(store, "Back after the reply")
  }

  // 2.3 test 7
  function test_dispatch_target_stale_replies_are_dropped() {
    var store = pickedStore(tc.rootB); if (!store) return
    var lateB = store.dispatchTargetRunner.current
    store.dispatchBack()
    compare(store.dispatchProjectPick(tc.rootA), true)
    var procA = store.dispatchTargetRunner.current
    reply(lateB, treeReply(treeData()), 0)
    compare(store.dispatchRoot, tc.rootA)
    compare(store.dispatchTargetLoading, true, "B's reply leaves A's read in flight")
    compare(store.dispatchTargetRows.length, 0, "B's tree is not shown for A")
    reply(procA, treeReply([]), 0)
    compare(targetKeys(store.dispatchTargetRows), "board", "A's reply applies")

    var failed = pickedStore(tc.rootB); if (!failed) return
    var lateFail = failed.dispatchTargetRunner.current
    failed.dispatchBack()
    failed.dispatchProjectPick(tc.rootA)
    reply(lateFail, treeFail("gone"), 0)
    compare(failed.dispatchStep, "target", "B's failure does not send A back")
    compare(failed.dispatchRoot, tc.rootA)
    compare(Object.keys(failed.dispatchProjectFailures).length, 0, "and marks nothing")

    var closed = pickedStore(tc.rootB); if (!closed) return
    var lateClosed = closed.dispatchTargetRunner.current
    compare(closed.closeDispatch(), true)
    checkDispatchIdle(closed, "closed")
    reply(lateClosed, treeReply(treeData()), 0)
    checkDispatchIdle(closed, "a reply after the close")
    compare(closed.dispatchRoot, "")

    var card = pickedStore(tc.rootB); if (!card) return
    var lateCard = card.dispatchTargetRunner.current
    var cards = dispatchCards()
    compare(card.openDispatch(cards.m1, cards), true)
    compare(card.dispatchStep, "")
    compare(card.dispatchRoot, tc.rootA)
    checkTargetCleared(card, "card entry")
    reply(lateCard, treeReply(treeData()), 0)
    checkTargetCleared(card, "a reply after a card entry")
    compare(card.dispatchStep, "")
    compare(card.dispatchState, "previewing", "the card's dispatch is untouched")

    var reopened = pickedStore(tc.rootB); if (!reopened) return
    var lateReopen = reopened.dispatchTargetRunner.current
    compare(reopened.dispatchOpenFromRuns(), true)
    checkTargetCleared(reopened, "reopened")
    reply(lateReopen, treeReply(treeData()), 0)
    compare(reopened.dispatchStep, "project", "a reply after a reopening is dropped")
    checkTargetCleared(reopened, "a reply after a reopening")

    var dropped = pickedStore(tc.rootB); if (!dropped) return
    var lateDropped = dropped.dispatchTargetRunner.current
    runsOf(dropped).projectRoots = registry([tc.rootA])
    compare(dropped.dispatchStep, "project")
    compare(dropped.dispatchRoot, "")
    checkTargetCleared(dropped, "registry fallback")
    reply(lateDropped, treeReply(treeData()), 0)
    compare(dropped.dispatchStep, "project", "a reply after the registry fallback is dropped")
    checkTargetCleared(dropped, "a reply after the registry fallback")
  }

  // 2.3 test 3
  function test_dispatch_target_pick_enters_the_form_for_another_project() {
    var store = targetStore(tc.rootB); if (!store) return
    var rows = store.dispatchTargetRows
    var map = store.dispatchTargetCardMap
    compare(store.dispatchTargetPick("card:m1"), true)
    compare(store.dispatchStep, "form")
    compare(store.dispatchTargetKey, "card:m1")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTargetLabel, Runs.dispatchLabel(map.m1, map))
    compare(store.dispatchTargetLabel, "Milestone \"M3 Document runs\"")
    compare(argv(store.dispatchDefaultsRunner.current), tc.previewCmd + "--defaults|/home/u/b")
    compare(argv(loadOf(store).current), tc.viewerCmd + "get-run-settings|/home/u/b")
    reply(loadOf(store).current, bSettings(), 0)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.parallelism, 2, "B's settings, not A's")
    compare(store.dispatchForm.verify.join(","), "make test")
    compare(store.dispatchForm.prefix, "bpre")
    compare(store.dispatchForm.base, "main")
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.bPreviewArgs, "B's milestone is previewed")
    verify(store.dispatchTargetRows === rows, "the rows stay")
    verify(store.dispatchTargetCardMap === map, "the card map stays")

    var board = targetStore(tc.rootB); if (!board) return
    compare(board.dispatchTargetPick("board"), true)
    compare(board.dispatchStep, "form")
    compare(board.dispatchTargetKey, "board")
    compare(board.dispatchTarget.level, "board")
    compare(board.dispatchTargetLabel, "Whole board")
  }

  // 2.3 test 4
  function test_dispatch_target_pick_for_the_open_project_and_refusals() {
    var store = pickedStore(tc.rootA); if (!store) return
    compare(store.dispatchTargetPick("board"), false, "no pick while loading")
    compare(store.dispatchStep, "target")
    compare(store.dispatchTargetLoading, true)
    reply(store.dispatchTargetRunner.current, treeReply(treeData()), 0)
    var refused = ["card:t2", "card:zz", "", "t1", null, 7]
    for (var i = 0; i < refused.length; i++) {
      compare(store.dispatchTargetPick(refused[i]), false, "key " + refused[i])
      compare(store.dispatchStep, "target", "key " + refused[i] + ": step")
      compare(store.dispatchTargetKey, "", "key " + refused[i] + ": key")
      compare(store.dispatchState, "idle", "key " + refused[i] + ": state")
    }
    verify(!store.dispatchDefaultsRunner.current, "a refused pick launches nothing")
    compare(store.dispatchTargetPick("card:t1"), true)
    compare(store.dispatchStep, "form")
    compare(store.dispatchTargetKey, "card:t1")
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchTargetLabel, "Subtask \"RunStore dispatch\"")
    verify(!loadOf(store), "the open project's runSettings are used")
    compare(argv(store.dispatchDefaultsRunner.current), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(store.dispatchForm.prefix, "old", "A's prefix history")
    compare(store.dispatchForm.parallelism, 4)
    var defaults = store.dispatchDefaultsRunner.current
    compare(store.dispatchTargetPick("card:m1"), false, "no pick at the form")
    compare(store.dispatchTargetKey, "card:t1")
    compare(store.dispatchTarget.level, "subtask")
    verify(store.dispatchDefaultsRunner.current === defaults, "nothing relaunched")

    var idle = runsStore(); if (!idle) return
    compare(idle.dispatchTargetPick("board"), false, "no pick without a step")
    checkDispatchIdle(idle, "no step")
  }

  // 2.3 test 11
  function test_dispatch_start_from_runs_refreshes_only_its_root() {
    var store = targetStore(tc.rootB); if (!store) return
    reply(runsOf(store).snapshotRunner.current, allReply([okEntry(tc.rootA, []), okEntry(tc.rootB, [])]), 0)
    compare(store.dispatchTargetPick("card:t1"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(store).current, bSettings(), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(argv(runner.current), tc.startCmd + "/home/u/b|card|t1|--base-branch|main|--branch-prefix|bpre|--max-concurrent|2|--verify|make test")
    var seq = runsOf(store).snapshotRunner.seq
    reply(runner.current, startOk("r9", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r9")
    compare(runsOf(store).snapshotRunner.seq, seq + 1, "one snapshot is asked for")
    compare(argv(runsOf(store).snapshotRunner.current), tc.snapCmd + "|/home/u/b", "of B only")
    compare(store.dispatchStep, "form")
  }

  // 2.3 test 9
  function test_dispatch_back_from_form_keeps_the_picked_row() {
    var store = targetStore(tc.rootB); if (!store) return
    var rows = store.dispatchTargetRows
    var map = store.dispatchTargetCardMap
    var treeSeq = store.dispatchTargetRunner.seq
    compare(store.dispatchTargetPick("card:m1"), true)
    var defaults = store.dispatchDefaultsRunner.current
    var settings = loadOf(store).current
    compare(store.dispatchBack(), true)
    compare(store.dispatchStep, "target")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchTargetKey, "card:m1", "the picked row is kept")
    verify(store.dispatchTargetRows === rows, "the rows are kept")
    verify(store.dispatchTargetCardMap === map, "the card map is kept")
    compare(store.dispatchTargetLoading, false)
    compare(store.dispatchTargetRunner.seq, treeSeq, "the tree is not read again")
    checkDispatchFieldsIdle(store, "Back from the form")
    reply(defaults, defaultsOk("main"), 0)
    reply(settings, bSettings(), 0)
    compare(store.dispatchState, "idle", "the form's lookups are dropped")
    compare(store.dispatchForm, null)
    compare(store.dispatchTargetPick("card:s1"), true)
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchTargetKey, "card:s1")

    var starting = targetStore(tc.rootB); if (!starting) return
    compare(starting.dispatchTargetPick("card:t1"), true)
    reply(starting.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(starting).current, bSettings(), 0)
    compare(starting.dispatchStart(), true)
    compare(starting.dispatchBack(), false, "no Back while starting")
    compare(starting.dispatchStep, "form")
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchTargetKey, "card:t1")
  }

  // 2.3 test 10
  function test_dispatch_registry_change_at_form() {
    var store = targetStore(tc.rootB); if (!store) return
    compare(store.dispatchTargetPick("card:m1"), true)
    var defaults = store.dispatchDefaultsRunner.current
    runsOf(store).projectRoots = registry([tc.rootB, tc.rootA])
    compare(store.dispatchStep, "form", "a reorder keeps the form")
    compare(store.dispatchRoot, tc.rootB)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTargetKey, "card:m1")
    runsOf(store).projectRoots = registry([tc.rootA])
    compare(store.dispatchStep, "project", "the picked root left: back to step 1")
    compare(store.dispatchRoot, "")
    checkDispatchFieldsIdle(store, "dropped at the form")
    checkTargetCleared(store, "dropped at the form")
    compare(rowsText(store.dispatchProjectRows), "/home/u/my proj:alpha:open:on:", "B's row is gone")
    reply(defaults, defaultsOk("main"), 0)
    compare(store.dispatchState, "idle", "the form's lookup is dropped")

    var starting = targetStore(tc.rootB); if (!starting) return
    compare(starting.dispatchTargetPick("card:t1"), true)
    reply(starting.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(loadOf(starting).current, bSettings(), 0)
    compare(starting.dispatchStart(), true)
    var runner = starting.dispatchStartRunners[0]
    runsOf(starting).projectRoots = registry([tc.rootA])
    compare(starting.dispatchStep, "form", "a start in flight keeps the form")
    compare(starting.dispatchState, "starting")
    compare(starting.dispatchRoot, tc.rootB)
    compare(starting.dispatchTargetKey, "card:t1")
    reply(runner.current, startOk("r9", ""), 0)
    compare(starting.dispatchState, "started", "the start completes for its root")
  }

  // ---- relaunch

  // Runs.stopReport's relaunch for m1 with a recorded prefix and base; extra's
  // keys are set over it.
  function relaunchOf(extra) {
    var r = { level: "milestone", cardId: "m1", prefix: "relaunch/m1", base: "release" }
    for (var key in extra) r[key] = extra[key]
    return r
  }

  property string relaunchArgs: "/home/u/my proj|milestone|m1|--base-branch|release|--branch-prefix|relaunch/m1|--max-concurrent|4|--verify|uv run pytest"

  function test_relaunch_overrides_prefix_and_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.relaunchOpenFor(cards.m1, cards, relaunchOf()), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTargetLabel, Runs.dispatchLabel(cards.m1, cards))
    compare(store.dispatchForm.prefix, "relaunch/m1")
    compare(store.dispatchForm.base, "release")
    compare(store.dispatchError, "")
    compare(store.dispatchDebounceTimer.running, false, "no check is scheduled before the defaults reply")
    verify(!store.dispatchPreviewRunner.current, "no preview before the defaults reply")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "release", "the default branch does not replace the recorded base")
    compare(store.dispatchForm.prefix, "relaunch/m1")
  }

  function test_relaunch_takes_verify_and_parallelism_from_the_settings() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    var r = relaunchOf({ verify: ["make lint"], parallelism: 9, allowNoVerification: true })
    compare(store.relaunchOpenFor(cards.m1, cards, r), true)
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.verify.length, 1)
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 4)
    compare(form.allowNoVerification, false)
  }

  function test_relaunch_dispatches_from_the_open_project() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    compare(runsOf(store).project, rootA)
    var lookup = store.dispatchDefaultsRunner.current
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/my proj")
    reply(lookup, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the preview is launched")
    compare(proc.command[2], "/home/u/my proj", "the first argument after the script is the open project")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  function test_relaunch_preview_and_start_carry_the_recorded_values() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.relaunchArgs)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(argv(store.dispatchStartRunners[0].current), tc.startCmd + tc.relaunchArgs)
  }

  function test_relaunch_without_a_card_or_relaunch_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    var noCards = [null, undefined, [], "m1"]
    for (var i = 0; i < noCards.length; i++) {
      compare(store.relaunchOpenFor(noCards[i], cards, relaunchOf()), false, "card " + i)
      checkDispatchIdle(store, "card " + i)
    }
    var noRelaunch = [null, undefined, []]
    for (var j = 0; j < noRelaunch.length; j++) {
      compare(store.relaunchOpenFor(cards.m1, cards, noRelaunch[j]), false, "relaunch " + j)
      checkDispatchIdle(store, "relaunch " + j)
    }
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")

    compare(store.openDispatch(cards.m1, cards), true)
    var target = store.dispatchTarget
    var form = store.dispatchForm
    var lookup = store.dispatchDefaultsRunner.current
    compare(store.relaunchOpenFor(null, cards, relaunchOf()), false)
    compare(store.dispatchState, "previewing", "the open dispatch stays open")
    verify(store.dispatchTarget === target, "same target")
    verify(store.dispatchForm === form, "same form")
    compare(store.dispatchForm.prefix, "old")
    verify(store.dispatchDefaultsRunner.current === lookup, "the same lookup")
    compare(lookup.running, true, "still in flight")

    compare(store.relaunchOpenFor(cards.d1, cards, relaunchOf({ cardId: "d1" })), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchForm, null, "nothing overridden")
  }

  function test_relaunch_blank_values_keep_the_defaults() {
    var variants = [{ prefix: "", base: "  " }, { prefix: 7, base: null }, { prefix: undefined, base: undefined }]
    for (var i = 0; i < variants.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      compare(store.relaunchOpenFor(cards.m1, cards, relaunchOf(variants[i])), true, "variant " + i)
      compare(store.dispatchForm.prefix, "old", "variant " + i + ": dispatchDefaults' prefix")
      compare(store.dispatchForm.base, "", "variant " + i + ": no base until the lookup replies")
      reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      compare(store.dispatchForm.base, "main", "variant " + i + ": the default branch fills base")
      compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "variant " + i)
    }
  }

  function test_relaunch_values_are_trimmed() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.relaunchOpenFor(cards.m1, cards, relaunchOf({ prefix: "  relaunch/m1 ", base: " release\n" })), true)
    compare(store.dispatchForm.prefix, "relaunch/m1")
    compare(store.dispatchForm.base, "release")
  }

  // Review Focus 1.
  function test_relaunch_is_refused_without_a_project_or_while_starting() {
    var bare = make(); if (!bare) return
    var cards = dispatchCards()
    compare(bare.relaunchOpenFor(cards.m1, cards, relaunchOf()), false)
    checkDispatchIdle(bare, "no project")
    verify(!bare.dispatchDefaultsRunner.current, "no defaults lookup")

    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    var form = store.dispatchForm
    compare(store.relaunchOpenFor(cards.s1, cards, relaunchOf({ level: "story", cardId: "s1" })), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone", "the start's target stays")
    verify(store.dispatchForm === form, "the start's form stays")
    compare(store.dispatchForm.prefix, "old")
    compare(store.dispatchStartRunners.length, 1)
  }

  // Review Focus 2.
  function test_relaunch_keeps_the_recorded_base_when_the_defaults_lookup_fails() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    reply(store.dispatchDefaultsRunner.current, "Traceback: boom\n", 1)
    compare(store.dispatchForm.base, "release")
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.relaunchArgs)
  }

  // Review Focus 3.
  function test_relaunch_of_a_subtask_is_ready_with_the_recorded_values() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.relaunchOpenFor(cards.t1, cards, relaunchOf({ level: "subtask", cardId: "t1", prefix: "relaunch/t1" })), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "relaunch/t1")
    compare(store.dispatchForm.base, "release")
    verify(!store.dispatchPreviewRunner.current, "a subtask has no preview")
  }

  // Review Focus 4.
  function test_an_opening_after_a_relaunch_takes_the_default_branch_again() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.prefix, "old")
    compare(store.dispatchForm.base, "")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main", "the relaunch's base override is not inherited")
  }
}
